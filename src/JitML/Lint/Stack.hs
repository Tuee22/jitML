{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.Stack
  ( LintFinding (..)
  , LintMode (..)
  , LintTarget (..)
  , renderLintFinding
  , runCheckCode
  , runLint
  )
where

import Control.Monad (filterM)
import Data.ByteString qualified as ByteString
import Data.List (isInfixOf, isPrefixOf, isSuffixOf)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , listDirectory
  , renameFile
  )
import System.Exit (ExitCode (..))
import System.FilePath qualified as FilePath
import System.IO.Temp (withSystemTempDirectory)

import JitML.Docs.Check (checkDocs)
import JitML.Docs.Check qualified as DocsCheck
import JitML.Lint.Chart (checkChartFiles)
import JitML.Lint.DhallNumerics (checkDhallNumerics)
import JitML.Lint.DhallRL (checkDhallRL)
import JitML.Lint.ForbiddenPaths (ForbiddenPathRule (..), matchForbiddenPath)
import JitML.Lint.Stack.Types (LintFinding (..), LintMode (..), LintTarget (..))
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Web.Bundle (panelEndpoint, panelSurfaces)
import JitML.Web.Contracts (renderPureScriptContracts)
import JitML.Web.Contracts qualified as Contracts

runCheckCode :: IO [LintFinding]
runCheckCode = do
  domainFindings <- checkCodeQualityDomain
  if not (null domainFindings)
    then pure domainFindings
    else do
      lintFindings <- runLintUnchecked LintAll LintCheck
      buildFindings <- checkWarningCleanBuild
      pure (lintFindings <> buildFindings)

runLint :: LintTarget -> LintMode -> IO [LintFinding]
runLint target mode = do
  domainFindings <- checkCodeQualityDomain
  if not (null domainFindings)
    then pure domainFindings
    else runLintUnchecked target mode

runLintUnchecked :: LintTarget -> LintMode -> IO [LintFinding]
runLintUnchecked target mode =
  case target of
    LintFiles -> checkFiles mode
    LintDocs -> checkDocsLint
    LintProto -> checkOptionalDirectory "proto" "proto.absent"
    LintChart -> checkChartFiles
    LintHaskell -> checkHaskellLint mode
    LintPurescript -> checkPureScriptLint
    LintAll ->
      concat
        <$> sequence
          [ checkFiles mode
          , checkDocsLint
          , checkOptionalDirectory "proto" "proto.absent"
          , checkChartFiles
          , checkHaskellLint mode
          , checkPureScriptLint
          ]

renderLintFinding :: LintFinding -> Text
renderLintFinding finding =
  Text.unlines
    [ "file: " <> Text.pack (findingPath finding)
    , "key: " <> findingKey finding
    , "message: " <> findingMessage finding
    , "remedy: " <> findingRemedy finding
    ]

checkFiles :: LintMode -> IO [LintFinding]
checkFiles mode = do
  files <- trackedTextFiles
  whitespaceFindings <- concat <$> traverse (checkWhitespace mode) files
  forbiddenFindings <- forbiddenPathFindings
  generatedFindings <- generatedPathFindings
  staticJitFindings <- staticJitArtefactFindings
  pure (whitespaceFindings <> forbiddenFindings <> generatedFindings <> staticJitFindings)

checkDocsLint :: IO [LintFinding]
checkDocsLint =
  fmap docsDriftFinding <$> checkDocs

checkOptionalDirectory :: FilePath -> Text -> IO [LintFinding]
checkOptionalDirectory path _key = do
  _exists <- doesDirectoryExist path
  pure []

checkPureScriptLint :: IO [LintFinding]
checkPureScriptLint = do
  contractFindings <- checkPureScriptContractsFile
  sources <- purescriptSources
  sourceFindings <- concat <$> traverse checkPureScriptSource sources
  tidyFindings <- runPureScriptTidyCheck
  specFindings <- runPureScriptSpecSuite
  pure
    ( contractFindings
        <> checkPureScriptRenderer
        <> checkPureScriptSourceSet sources
        <> sourceFindings
        <> checkPureScriptPanelCoverage
        <> checkPureScriptToolSubprocesses
        <> tidyFindings
        <> specFindings
    )

-- | Invoke the container-installed `purs-tidy check` to enforce
-- PureScript formatting drift on the default lint path. The lint
-- target runs inside `jitml:local`, where `npm install -g purs-tidy`
-- has produced the binary at `/usr/local/bin/purs-tidy`. When the
-- binary is not present (host invocation, half-built image), the
-- check reports a missing-tools finding instead of silently
-- skipping.
runPureScriptTidyCheck :: IO [LintFinding]
runPureScriptTidyCheck = do
  webExists <- doesDirectoryExist "web"
  if not webExists
    then pure []
    else do
      tidyAvailable <- doesFileExist containerPureScriptTidyPath
      if not tidyAvailable
        then pure [missingPureScriptToolsFinding]
        else
          runCommandFinding
            "web/src"
            "purescript.purs-tidy.drift"
            "purs-tidy reported PureScript formatting drift"
            pureScriptTidyCmd

-- | Invoke the container-installed `spago test` to run the
-- `purescript-spec` smoke suite that touches every typed `Panels.*`
-- contract. When `spago` is missing (host invocation), the lint target
-- reports a missing-tools finding via 'runPureScriptTidyCheck' (the two
-- paths share the same container-tools precondition); a present `spago`
-- runs the suite and surfaces any failure as a `purescript.spec.fail`
-- finding with the captured stdout/stderr.
runPureScriptSpecSuite :: IO [LintFinding]
runPureScriptSpecSuite = do
  webExists <- doesDirectoryExist "web"
  if not webExists
    then pure []
    else do
      spagoAvailable <- doesFileExist containerPureScriptSpagoPath
      if not spagoAvailable
        then pure []
        else
          runCommandFinding
            "web/test/Main.purs"
            "purescript.spec.fail"
            "purescript-spec smoke suite reported failures"
            pureScriptSpagoCmd

missingPureScriptToolsFinding :: LintFinding
missingPureScriptToolsFinding =
  LintFinding
    containerPureScriptTidyPath
    "purescript.tools.missing"
    "container PureScript tools are not available"
    ( Text.unlines
        [ "rebuild the jitML container image with `docker compose build jitml`"
        , "then run `docker compose run --rm jitml jitml lint purescript`"
        , "expected `purs-tidy` and `spago` in: /usr/local/bin"
        ]
    )

checkPureScriptContractsFile :: IO [LintFinding]
checkPureScriptContractsFile = do
  let path = "web/src/Generated/Contracts.purs"
  exists <- doesFileExist path
  if exists
    then do
      content <- Text.IO.readFile path
      pure
        [ LintFinding
            path
            "purescript.contracts.missing-endpoint"
            "generated PureScript contracts do not name InferenceRun"
            "run `jitml docs generate` to refresh generated contracts"
        | not ("InferenceRun" `Text.isInfixOf` content)
        ]
    else
      pure
        [ LintFinding
            path
            "purescript.contracts.missing"
            "generated PureScript contracts file is missing"
            "run `jitml docs generate` to create web/src/Generated/Contracts.purs"
        ]

checkPureScriptRenderer :: [LintFinding]
checkPureScriptRenderer =
  [ LintFinding
      "src/JitML/Web/Contracts.hs"
      "purescript.contracts.module-header"
      "PureScript contract renderer does not emit the Generated.Contracts module header"
      "keep renderPureScriptContracts aligned with web/src/Generated/Contracts.purs"
  | not ("module Generated.Contracts where" `Text.isInfixOf` renderPureScriptContracts)
  ]

checkPureScriptSourceSet :: [FilePath] -> [LintFinding]
checkPureScriptSourceSet sources =
  [ LintFinding
      "web"
      "purescript.sources.empty"
      "PureScript source set is empty"
      "add checked-in PureScript sources under web/src or web/test"
  | null sources
  ]

checkPureScriptSource :: FilePath -> IO [LintFinding]
checkPureScriptSource path = do
  source <- Text.IO.readFile path
  pure
    ( [ LintFinding
          path
          "purescript.whitespace.tabs"
          "PureScript source contains tab characters"
          "replace tabs with spaces"
      | "\t" `Text.isInfixOf` source
      ]
        <> [ LintFinding
               path
               "purescript.whitespace.final-newline"
               "PureScript source is missing a final newline"
               "end the file with a newline"
           | not ("\n" `Text.isSuffixOf` source)
           ]
    )

checkPureScriptPanelCoverage :: [LintFinding]
checkPureScriptPanelCoverage =
  [ LintFinding
      "src/JitML/Web/Contracts.hs"
      "purescript.contracts.panel-coverage"
      "frontend panel endpoints do not match generated API contract endpoints"
      "update panelSurfaces and apiEndpoints together"
  | fmap panelEndpoint panelSurfaces /= fmap Contracts.endpointPath panelContractEndpoints
  ]

panelContractEndpoints :: [Contracts.ApiEndpoint]
panelContractEndpoints =
  case Contracts.apiEndpoints of
    _runCommandEndpoint : rest -> rest
    [] -> []

checkPureScriptToolSubprocesses :: [LintFinding]
checkPureScriptToolSubprocesses =
  expectSubprocess
    "purescript.spago-test"
    pureScriptSpagoCmd
    containerPureScriptSpagoPath
    ["test"]
    (Just "web")
    <> expectSubprocess
      "purescript.purs-tidy"
      pureScriptTidyCmd
      containerPureScriptTidyPath
      ["check", "src/**/*.purs"]
      (Just "web")

pureScriptSpagoCmd :: Subprocess
pureScriptSpagoCmd =
  (subprocess containerPureScriptSpagoPath ["test"])
    { subprocessWorkingDirectory = Just "web"
    }

pureScriptTidyCmd :: Subprocess
pureScriptTidyCmd =
  (subprocess containerPureScriptTidyPath ["check", "src/**/*.purs"])
    { subprocessWorkingDirectory = Just "web"
    }

-- | The Dockerfile installs the PureScript toolchain via
-- `npm install -g purescript spago purs-tidy`, which lands the
-- executables at `/usr/local/bin/`. The lint stack runs only inside
-- `jitml:local`, so the absolute path is a deterministic typed value.
containerPureScriptSpagoPath :: FilePath
containerPureScriptSpagoPath = "/usr/local/bin/spago"

containerPureScriptTidyPath :: FilePath
containerPureScriptTidyPath = "/usr/local/bin/purs-tidy"

expectSubprocess :: Text -> Subprocess -> FilePath -> [Text] -> Maybe FilePath -> [LintFinding]
expectSubprocess key command expectedPath expectedArgs expectedDirectory =
  [ LintFinding
      "src/JitML/Lint/Stack.hs"
      key
      "PureScript tool command is not represented by the expected typed Subprocess"
      "keep the PureScript lint tool subprocess definition explicit and deterministic"
  | subprocessPath command /= expectedPath
      || subprocessArguments command /= expectedArgs
      || subprocessWorkingDirectory command /= expectedDirectory
  ]

purescriptSources :: IO [FilePath]
purescriptSources =
  concat <$> traverse listPursFiles ["web/src", "web/test"]

listPursFiles :: FilePath -> IO [FilePath]
listPursFiles root = do
  exists <- doesDirectoryExist root
  if exists
    then do
      entries <- listDirectory root
      concat <$> traverse (listPursEntry root) entries
    else pure []

listPursEntry :: FilePath -> FilePath -> IO [FilePath]
listPursEntry root entry = do
  let path = root FilePath.</> entry
  isDirectory <- doesDirectoryExist path
  if isDirectory
    then listPursFiles path
    else pure [path | FilePath.takeExtension path == ".purs"]

checkHaskellLint :: LintMode -> IO [LintFinding]
checkHaskellLint mode = do
  fourmoluFindings <- checkRequiredConfig "fourmolu.yaml" requiredFourmoluKeys
  hlintExists <- doesFileExist ".hlint.yaml"
  primitiveFindings <- forbiddenPrimitiveFindings
  dhallNumericsFindings <- checkDhallNumerics
  dhallRLFindings <- checkDhallRL
  externalFindings <- checkExternalHaskellStyle mode
  let hlintFindings =
        [ LintFinding
            ".hlint.yaml"
            "hlint.config.missing"
            "missing .hlint.yaml"
            "create .hlint.yaml with the doctrine-required rules"
        | not hlintExists
        ]
  pure
    ( fourmoluFindings
        <> hlintFindings
        <> primitiveFindings
        <> dhallNumericsFindings
        <> dhallRLFindings
        <> externalFindings
    )

checkRequiredConfig :: FilePath -> [Text] -> IO [LintFinding]
checkRequiredConfig path keys = do
  exists <- doesFileExist path
  if exists
    then do
      content <- Text.IO.readFile path
      pure
        [ LintFinding
            path
            ("fourmolu." <> key)
            ("missing fourmolu setting: " <> key)
            "add the setting to fourmolu.yaml"
        | key <- keys
        , not (key `Text.isInfixOf` content)
        ]
    else
      pure
        [ LintFinding
            path
            "fourmolu.config.missing"
            "missing fourmolu.yaml"
            "create fourmolu.yaml with the doctrine-required settings"
        ]

trackedTextFiles :: IO [FilePath]
trackedTextFiles = filter isLintedTextFile <$> repoFiles "."

repoFiles :: FilePath -> IO [FilePath]
repoFiles = go
 where
  go dir = do
    entries <- listDirectory dir
    let visibleEntries = filter (not . shouldSkipPath . normalizePath . pathFrom dir) entries
    paths <- traverse (descend dir) visibleEntries
    pure (concat paths)

  descend dir entry = do
    let path = normalizePath (pathFrom dir entry)
    isDir <- doesDirectoryExist path
    if isDir
      then go path
      else pure [path]

pathFrom :: FilePath -> FilePath -> FilePath
pathFrom "." entry = entry
pathFrom dir entry = dir FilePath.</> entry

normalizePath :: FilePath -> FilePath
normalizePath = dropPrefix "./"

dropPrefix :: (Eq a) => [a] -> [a] -> [a]
dropPrefix prefix value
  | prefix `isPrefixOf` value = drop (length prefix) value
  | otherwise = value

shouldSkipPath :: FilePath -> Bool
shouldSkipPath path =
  any
    (`isPrefixOf` path)
    [ ".git/"
    , ".build/"
    , ".data/"
    , "dist-newstyle/"
    , ".dist-newstyle/"
    , "gen/"
    , "node_modules/"
    , "web/node_modules/"
    , "web/output/"
    , "web/dist/"
    , "web/.spago/"
    , "playwright-report/"
    , "test-results/"
    , "infra/pulumi/node_modules/"
    ]
    || "/node_modules/" `isInfixOf` path
    || "/.spago/" `isInfixOf` path
    || "/output/" `isInfixOf` path
    || "/dist/" `isInfixOf` path

isLintedTextFile :: FilePath -> Bool
isLintedTextFile path =
  any (`isSuffixOf` path) lintedSuffixes
    || path `elem` [".gitignore", ".dockerignore", "cabal.project", "jitml.cabal"]

lintedSuffixes :: [String]
lintedSuffixes =
  [ ".hs"
  , ".md"
  , ".yaml"
  , ".yml"
  , ".json"
  , ".dhall"
  , ".project"
  , ".cabal"
  , ".sh"
  , ".fish"
  , ".zsh"
  ]

checkWhitespace :: LintMode -> FilePath -> IO [LintFinding]
checkWhitespace mode path = do
  content <- Text.IO.readFile path
  let rewritten = normalizeWhitespace content
  if content == rewritten
    then pure []
    else case mode of
      LintWrite -> do
        writeTextFileAtomic path rewritten
        pure []
      LintCheck ->
        pure
          [ LintFinding
              path
              "files.whitespace"
              "trailing whitespace or missing final newline"
              "run `jitml lint files --write`"
          ]

normalizeWhitespace :: Text -> Text
normalizeWhitespace content =
  Text.unlines (fmap Text.stripEnd (Text.lines content))

forbiddenPathFindings :: IO [LintFinding]
forbiddenPathFindings = do
  files <- repoFiles "."
  let paths = files <> forbiddenDirectoryCandidates
  existingForbidden <- filterM forbiddenExists paths
  pure
    [forbiddenFinding path rule | path <- existingForbidden, Just rule <- [matchForbiddenPath path]]

forbiddenDirectoryCandidates :: [FilePath]
forbiddenDirectoryCandidates =
  [ ".github/workflows/"
  , ".husky/"
  , ".githooks/"
  ]

forbiddenExists :: FilePath -> IO Bool
forbiddenExists path
  | "/" `isSuffixOf` path = doesDirectoryExist path
  | otherwise = doesFileExist path

forbiddenFinding :: FilePath -> ForbiddenPathRule -> LintFinding
forbiddenFinding path rule =
  LintFinding
    { findingPath = path
    , findingKey = forbiddenKey rule
    , findingMessage = "forbidden path exists"
    , findingRemedy =
        "delete this path; the canonical equivalent is `"
          <> forbiddenCanonicalCommand rule
          <> "`"
    }

generatedPathFindings :: IO [LintFinding]
generatedPathFindings =
  fmap docsDriftFinding <$> checkDocs

docsDriftFinding :: DocsCheck.DocsDrift -> LintFinding
docsDriftFinding drift =
  LintFinding
    { findingPath = DocsCheck.driftPath drift
    , findingKey = DocsCheck.driftKey drift
    , findingMessage = "generated documentation drift"
    , findingRemedy = "run `jitml docs generate` to update"
    }

writeTextFileAtomic :: FilePath -> Text -> IO ()
writeTextFileAtomic path content = do
  createDirectoryIfMissing True (FilePath.takeDirectory path)
  let tmpPath = path <> ".tmp"
  Text.IO.writeFile tmpPath content
  renameFile tmpPath path

requiredFourmoluKeys :: [Text]
requiredFourmoluKeys =
  [ "indentation:"
  , "column-limit:"
  , "function-arrows:"
  , "comma-style:"
  , "import-export-style:"
  , "indent-wheres:"
  , "record-brace-space:"
  , "newlines-between-decls:"
  , "haddock-style:"
  , "let-style:"
  , "in-style:"
  , "unicode:"
  , "respectful:"
  ]

forbiddenPrimitiveFindings :: IO [LintFinding]
forbiddenPrimitiveFindings = do
  files <- filter isHaskellSource <$> repoFiles "."
  concat <$> traverse checkForbiddenPrimitive files

isHaskellSource :: FilePath -> Bool
isHaskellSource path =
  ".hs" `isSuffixOf` path

checkForbiddenPrimitive :: FilePath -> IO [LintFinding]
checkForbiddenPrimitive path
  | path == "src/JitML/Sub/Stream.hs" = checkForbiddenTerminalPrimitive path
  | path == "src/JitML/CLI/Output.hs" = checkForbiddenSubprocessPrimitive path
  | otherwise = do
      subprocessFindings <- checkForbiddenSubprocessPrimitive path
      terminalFindings <- checkForbiddenTerminalPrimitive path
      pure (subprocessFindings <> terminalFindings)

checkForbiddenSubprocessPrimitive :: FilePath -> IO [LintFinding]
checkForbiddenSubprocessPrimitive path = do
  content <- Text.IO.readFile path
  pure
    [ LintFinding
        path
        key
        "forbidden subprocess primitive outside typed interpreter"
        "move subprocess execution through `src/JitML/Sub/Stream.hs`"
    | (key, needle) <- forbiddenSubprocessNeedles
    , needle `Text.isInfixOf` content
    ]

checkForbiddenTerminalPrimitive :: FilePath -> IO [LintFinding]
checkForbiddenTerminalPrimitive path = do
  content <- Text.IO.readFile path
  pure
    [ LintFinding
        path
        key
        "forbidden terminal output primitive outside CLI output module"
        "move terminal output through `src/JitML/CLI/Output.hs`"
    | (key, needle) <- forbiddenTerminalNeedles
    , needle `Text.isInfixOf` content
    ]

forbiddenSubprocessNeedles :: [(Text, Text)]
forbiddenSubprocessNeedles =
  [ ("subprocess.call-process", "call" <> "Process")
  , ("subprocess.read-create-process", "read" <> "Create" <> "Process")
  , ("subprocess.system-process", "System." <> "Process")
  , ("subprocess.typed-process", "System." <> "Process.Typed")
  , ("subprocess.proc", "Typed." <> "proc")
  ]

forbiddenTerminalNeedles :: [(Text, Text)]
forbiddenTerminalNeedles =
  [ ("terminal.put-str", "put" <> "Str")
  , ("terminal.put-str-ln", "put" <> "StrLn")
  , ("terminal.hput-str", "hPut" <> "Str")
  , ("terminal.hput-str-ln", "hPut" <> "StrLn")
  , ("terminal.exit-failure", "exit" <> "Failure")
  ]

staticJitArtefactFindings :: IO [LintFinding]
staticJitArtefactFindings = do
  files <- repoFiles "."
  pure
    [ LintFinding
        path
        "files.static-jit-source"
        "checked-in JIT source or build script"
        "move compiler inputs into Haskell RuntimeSource renderers; generated source belongs under ./.build/jit-src/"
    | path <- files
    , isStaticJitArtefact path
    ]

isStaticJitArtefact :: FilePath -> Bool
isStaticJitArtefact path =
  not ("test/golden/" `isPrefixOf` path)
    && (FilePath.takeFileName path == "build.sh" || FilePath.takeExtension path `elem` staticJitExtensions)

staticJitExtensions :: [String]
staticJitExtensions =
  [ ".cu"
  , ".cc"
  , ".cpp"
  , ".cxx"
  , ".metal"
  , ".swift"
  ]

checkExternalHaskellStyle :: LintMode -> IO [LintFinding]
checkExternalHaskellStyle mode = do
  styleTools <- resolveStyleTools
  case styleTools of
    Left missingFindings -> pure missingFindings
    Right tools -> do
      fourmoluFindings <- runFourmolu tools mode
      hlintFindings <- runHlint tools
      cabalFormatFindings <- runCabalFormat mode
      pure (fourmoluFindings <> hlintFindings <> cabalFormatFindings)

data StyleTools = StyleTools
  { styleFourmoluPath :: !FilePath
  , styleHlintPath :: !FilePath
  }

resolveStyleTools :: IO (Either [LintFinding] StyleTools)
resolveStyleTools = do
  tools <- styleToolsAt containerStyleToolBin
  case tools of
    Just resolvedTools -> pure (Right resolvedTools)
    Nothing -> pure (Left [missingStyleToolsFinding])

styleToolsAt :: FilePath -> IO (Maybe StyleTools)
styleToolsAt bin = do
  let tools =
        StyleTools
          { styleFourmoluPath = bin FilePath.</> "fourmolu"
          , styleHlintPath = bin FilePath.</> "hlint"
          }
  fourmoluExists <- doesFileExist (styleFourmoluPath tools)
  hlintExists <- doesFileExist (styleHlintPath tools)
  pure
    ( if fourmoluExists && hlintExists
        then Just tools
        else Nothing
    )

missingStyleToolsFinding :: LintFinding
missingStyleToolsFinding =
  LintFinding
    containerStyleToolBin
    "haskell.style-tools.missing"
    "Container Haskell style tools are not available"
    ( Text.unlines
        [ "rebuild the jitML container image with `docker compose build jitml`"
        , "then run code-quality commands inside `jitml:local`"
        , "expected `fourmolu` and `hlint` in: " <> Text.pack containerStyleToolBin
        ]
    )

runFourmolu :: StyleTools -> LintMode -> IO [LintFinding]
runFourmolu tools mode =
  runCommandFinding
    "src"
    "haskell.fourmolu"
    "fourmolu reported formatting drift"
    ( subprocess
        (styleFourmoluPath tools)
        ( case mode of
            LintCheck -> fourmoluMode "check"
            LintWrite -> fourmoluMode "inplace"
        )
    )

fourmoluMode :: Text -> [Text]
fourmoluMode mode =
  ["--no-cabal", "--ghc-opt", "-XGHC2024", "--mode", mode, "src", "app", "test"]

runHlint :: StyleTools -> IO [LintFinding]
runHlint tools =
  runCommandFinding
    "src"
    "haskell.hlint"
    "hlint reported hints"
    ( subprocess
        (styleHlintPath tools)
        [ "--with-group=default"
        , "--with-group=extra"
        , "--hint"
        , ".hlint.yaml"
        , "src"
        , "app"
        , "test"
        ]
    )

runCabalFormat :: LintMode -> IO [LintFinding]
runCabalFormat LintWrite =
  runCommandFinding
    "jitml.cabal"
    "haskell.cabal-format"
    "cabal format failed"
    (subprocess "cabal" ["format", "jitml.cabal"])
runCabalFormat LintCheck =
  withSystemTempDirectory "jitml-cabal-format" $ \directory -> do
    let tempCabal = directory FilePath.</> "jitml.cabal"
    ByteString.readFile "jitml.cabal" >>= ByteString.writeFile tempCabal
    formatFindings <-
      runCommandFinding
        "jitml.cabal"
        "haskell.cabal-format"
        "cabal format failed"
        (subprocess "cabal" ["format", Text.pack tempCabal])
    if not (null formatFindings)
      then pure formatFindings
      else do
        original <- ByteString.readFile "jitml.cabal"
        formatted <- ByteString.readFile tempCabal
        pure
          [ LintFinding
              "jitml.cabal"
              "haskell.cabal-format"
              "cabal format would change jitml.cabal"
              "run `cabal format jitml.cabal`"
          | original /= formatted
          ]

checkWarningCleanBuild :: IO [LintFinding]
checkWarningCleanBuild =
  runCommandFinding
    "jitml.cabal"
    "haskell.warning-clean-build"
    "warning-clean cabal build failed"
    (subprocess "cabal" ["build", "all", "--ghc-options=-Werror"])

runCommandFinding :: FilePath -> Text -> Text -> Subprocess -> IO [LintFinding]
runCommandFinding path key message command = do
  (exitCode, stdoutText, stderrText) <- runStreaming defaultSubprocessEnv command
  case exitCode of
    ExitSuccess -> pure []
    ExitFailure _ ->
      pure
        [ LintFinding
            path
            key
            message
            (commandFailureRemedy command stdoutText stderrText)
        ]

commandFailureRemedy :: Subprocess -> Text -> Text -> Text
commandFailureRemedy command stdoutText stderrText =
  Text.unlines
    [ "command: " <> renderSubprocess command
    , "stdout: " <> clipped stdoutText
    , "stderr: " <> clipped stderrText
    ]

clipped :: Text -> Text
clipped value =
  let limit = 4000
   in if Text.length value <= limit
        then value
        else Text.take limit value <> "\n... truncated ..."

checkCodeQualityDomain :: IO [LintFinding]
checkCodeQualityDomain = do
  markerExists <- doesFileExist codeQualityContainerMarker
  pure
    [ LintFinding
        codeQualityContainerMarker
        "code-quality.container.required"
        "Code quality commands must run inside the jitML container"
        ( Text.unlines
            [ "run `docker compose run --rm jitml jitml <lint-or-check-code-command>`"
            , "style and code-quality commands are not Cabal test stanzas"
            , "rebuild the container with `docker compose build jitml` if the marker is absent"
            ]
        )
    | not markerExists
    ]

codeQualityContainerMarker :: FilePath
codeQualityContainerMarker = "/opt/jitml-code-quality-domain"

containerStyleToolBin :: FilePath
containerStyleToolBin = "/opt/jitml-style-tools/bin"
