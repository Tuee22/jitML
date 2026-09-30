{-# LANGUAGE OverloadedStrings #-}

module JitML.Lint.ProductTruth
  ( ProductScaffold (..)
  , SourceModule (..)
  , checkProductTruth
  , nonProductScaffolding
  , productScaffoldRegistry
  , reachableModulesFrom
  , scanProductTruthImports
  , scanProductTruthSourceText
  )
where

import Data.Char (isAlphaNum, isDigit)
import Data.List qualified as List
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import System.FilePath qualified as FilePath

import JitML.Lint.Stack.Types (LintFinding (..))

data ProductScaffold = ProductScaffold
  { scaffoldKey :: Text
  , scaffoldNeedles :: [Text]
  , scaffoldDescription :: Text
  }
  deriving stock (Eq, Show)

data SourceModule = SourceModule
  { sourceModuleName :: Text
  , sourceModulePath :: FilePath
  , sourceModuleImports :: [Text]
  }
  deriving stock (Eq, Show)

productScaffoldRegistry :: [ProductScaffold]
productScaffoldRegistry =
  [ enforced "deterministicStep" ["deterministicStep"] "deterministic environment step helper"
  , enforced "runRLLoop" ["runRLLoop"] "non-learned RL loop"
  , enforced
      "runSimulatedEpisode"
      ["runSimulatedEpisode", "runSimulatedEpisodes", "runSimulatedEpisodesByName"]
      "fake-policy simulator episode runner"
  , enforced
      "completedTrainingFromMetrics"
      ["completedTrainingFromMetrics"]
      "fabricated completion witness helper"
  , enforced
      "seeded-demo-weights"
      ["seededDemoCheckpoints", "-demo-weights"]
      "seeded product demo checkpoint weights"
  ]
 where
  enforced = ProductScaffold

nonProductScaffolding :: [Text]
nonProductScaffolding = fmap scaffoldKey productScaffoldRegistry

checkProductTruth :: IO [LintFinding]
checkProductTruth = do
  files <- sourceFiles
  sourceFindings <-
    concat
      <$> traverse
        ( \path -> do
            content <- Text.IO.readFile path
            pure (scanProductTruthSourceText path content)
        )
        files
  modules <- traverse readSourceModule files
  pure (sourceFindings <> scanProductTruthImports modules)

scanProductTruthSourceText :: FilePath -> Text -> [LintFinding]
scanProductTruthSourceText path content
  | normalizedPath path == productTruthPath = []
  | otherwise =
      [ scaffoldFinding path scaffold needle
      | scaffold <- productScaffoldRegistry
      , needle <- scaffoldNeedles scaffold
      , needle `Text.isInfixOf` content
      ]
        <> measuredBarFindings path content
        <> literalCohortBarFindings path content

-- This source check guards the product constructor boundary. Runtime equality
-- between a measurement and a literature value cannot establish provenance:
-- a valid run may happen to land exactly on the target. The source declaration
-- must therefore never pass a measured expression as the bar target.
measuredBarFindings :: FilePath -> Text -> [LintFinding]
measuredBarFindings path _content
  | "src/JitML/Test/" `List.isPrefixOf` normalizedPath path = []
measuredBarFindings path content =
  [ measuredBarFinding path
  | tokens <- List.tails (codeTokens content)
  , case tokens of
      constructor : _name : _goal : target : _
        | barConstructor constructor -> tainted target
      constructor : _name : target : _
        | regressionBarConstructor constructor -> tainted target
      constructor : target : _
        | tableConstructor constructor -> tainted target
      _ -> False
  ]
    <> [ measuredBarFinding path
       | line <- Text.lines content
       , let code = Text.strip (fst (Text.breakOn "--" line))
       , tokens <- List.tails (codeTokens code)
       , case tokens of
           field : "=" : value : _ -> targetField field && tainted value
           _ -> False
       ]
 where
  barConstructor name =
    name == "mkConvergenceBar" || ".mkConvergenceBar" `Text.isSuffixOf` name
  regressionBarConstructor name =
    name == "regressionRmseBar" || ".regressionRmseBar" `Text.isSuffixOf` name
  tableConstructor name =
    name `elem` ["ConvergenceThreshold", "SlConvergenceThreshold"]
      || ".ConvergenceThreshold" `Text.isSuffixOf` name
      || ".SlConvergenceThreshold" `Text.isSuffixOf` name
  targetField name =
    name
      `elem` [ "convergenceLiteratureTarget"
             , "convergenceThreshold"
             , "threshold"
             , "literatureTarget"
             , "slLiteratureTarget"
             ]
  tainted name = measuredName name || name `elem` measuredAliases
  -- Follow simple value declarations to their fixed point. A measured value
  -- can be hidden behind multiple `let` or top-level aliases; comparing the
  -- final numeric bar to a table cannot reveal that source relationship.
  measuredAliases =
    let declarations = mapMaybe valueDeclaration (Text.lines content)
        close aliases =
          let next =
                List.nub
                  ( aliases
                      <> [ name
                         | (name, rhs) <- declarations
                         , any (\token -> measuredName token || token `elem` aliases) rhs
                         ]
                  )
           in if length next == length aliases then aliases else close next
     in close []
  valueDeclaration line =
    case codeTokens (fst (Text.breakOn "--" line)) of
      name : "=" : rhs | not (null rhs) -> Just (name, rhs)
      "let" : name : "=" : rhs | not (null rhs) -> Just (name, rhs)
      _ -> Nothing
  measuredName name =
    let lowered = Text.toLower name
     in "measured" `Text.isInfixOf` lowered
          || lowered `elem` ["cometricvalue", "metricvalue", "observedvalue"]

codeTokens :: Text -> [Text]
codeTokens =
  Text.words
    . Text.map (\char -> if isAlphaNum char || char `elem` ("._=" :: String) then char else ' ')
    . Text.unlines
    . fmap (fst . Text.breakOn "--")
    . Text.lines

measuredBarFinding :: FilePath -> LintFinding
measuredBarFinding path =
  LintFinding
    path
    "product-truth.measured-bar"
    "a product convergence threshold is derived from a measured value"
    "use a reviewed external target and project-calibrated slack"

-- A data-flow name check alone can miss a helper that returns a measurement
-- under an innocuous name. The two authoritative cohort tables therefore
-- require literal target/slack declarations. This rules out arbitrary helper
-- calls at the source of ProductRow convergence bars, including indirect
-- measured-derived values whose identifier carries no useful clue.
literalCohortBarFindings :: FilePath -> Text -> [LintFinding]
literalCohortBarFindings path content
  | normalizedPath path
      `notElem` [ "src/JitML/RL/ConvergenceThresholds.hs"
                , "src/JitML/SL/ConvergenceThresholds.hs"
                ] =
      []
  | otherwise =
      [ LintFinding
          path
          "product-truth.nonliteral-bar"
          "a canonical cohort bar is not declared with literal target and slack"
          "declare reviewed numeric target and slack constants in the cohort table"
      | line <- Text.lines content
      , let code = fst (Text.breakOn "--" line)
      , "\"" `Text.isInfixOf` code
      , tokens <- List.tails (codeTokens code)
      , case tokens of
          constructor : target : slack : _
            | constructor `elem` ["ConvergenceThreshold", "SlConvergenceThreshold"] ->
                not (numericToken target && numericToken slack)
          _ -> False
      ]
 where
  numericToken token =
    not (Text.null token)
      && Text.any isDigit token
      && Text.all (\char -> isDigit char || char == '.') token

scanProductTruthImports :: [SourceModule] -> [LintFinding]
scanProductTruthImports modules =
  [ importFinding sourceModule imported
  | sourceModule <- reachableModulesFrom ["JitML.App"] modules
  , imported <- sourceModuleImports sourceModule
  , imported `elem` forbiddenScaffoldModules
  ]

reachableModulesFrom :: [Text] -> [SourceModule] -> [SourceModule]
reachableModulesFrom roots modules =
  go [] roots
 where
  go seen [] = fmap snd (List.sortOn fst seen)
  go seen (name : rest)
    | name `elem` fmap fst seen = go seen rest
    | otherwise =
        case lookupModule name of
          Nothing -> go seen rest
          Just sourceModule ->
            go ((name, sourceModule) : seen) (sourceModuleImports sourceModule <> rest)
  lookupModule name =
    List.find ((== name) . sourceModuleName) modules

readSourceModule :: FilePath -> IO SourceModule
readSourceModule path = do
  content <- Text.IO.readFile path
  pure
    SourceModule
      { sourceModuleName = moduleNameFromPath path content
      , sourceModulePath = path
      , sourceModuleImports = mapMaybe parseImportLine (Text.lines content)
      }

moduleNameFromPath :: FilePath -> Text -> Text
moduleNameFromPath path content =
  case mapMaybe parseModuleLine (Text.lines content) of
    name : _ -> name
    [] -> pathModuleName path

parseModuleLine :: Text -> Maybe Text
parseModuleLine line =
  let stripped = Text.strip line
   in if "module " `Text.isPrefixOf` stripped
        then Just (takeModuleName (Text.drop 7 stripped))
        else Nothing

parseImportLine :: Text -> Maybe Text
parseImportLine line =
  let stripped = Text.strip line
   in if "import " `Text.isPrefixOf` stripped
        then firstModuleToken (Text.words (Text.drop 7 stripped))
        else Nothing

firstModuleToken :: [Text] -> Maybe Text
firstModuleToken [] = Nothing
firstModuleToken (token : rest)
  | token `elem` ["qualified", "safe"] = firstModuleToken rest
  | otherwise =
      let name = takeModuleName token
       in if Text.null name then Nothing else Just name

takeModuleName :: Text -> Text
takeModuleName =
  Text.takeWhile isModuleNameChar

isModuleNameChar :: Char -> Bool
isModuleNameChar char =
  isAlphaNum char || char == '.' || char == '_'

sourceFiles :: IO [FilePath]
sourceFiles = do
  exists <- doesDirectoryExist "src"
  if exists
    then filter isHaskellSource <$> repoFiles "src"
    else pure []

repoFiles :: FilePath -> IO [FilePath]
repoFiles root = do
  entries <- listDirectory root
  concat
    <$> traverse
      ( \entry -> do
          let path = root </> entry
          isDir <- doesDirectoryExist path
          if isDir
            then repoFiles path
            else pure [path]
      )
      entries

isHaskellSource :: FilePath -> Bool
isHaskellSource path =
  FilePath.takeExtension path == ".hs"

pathModuleName :: FilePath -> Text
pathModuleName path =
  Text.intercalate "." $
    Text.splitOn "/" $
      Text.pack $
        FilePath.dropExtension $
          dropSrcPrefix (normalizedPath path)

dropSrcPrefix :: FilePath -> FilePath
dropSrcPrefix path =
  fromMaybe path (List.stripPrefix "src/" path)

normalizedPath :: FilePath -> FilePath
normalizedPath = FilePath.normalise

productTruthPath :: FilePath
productTruthPath = "src/JitML/Lint/ProductTruth.hs"

forbiddenScaffoldModules :: [Text]
forbiddenScaffoldModules =
  [ "JitML.RL.Loop"
  , "JitML.RL.SimulatorLoop"
  , "Support.DeterministicStep"
  , "Support.Loop"
  , "Support.SimulatorLoop"
  ]

scaffoldFinding :: FilePath -> ProductScaffold -> Text -> LintFinding
scaffoldFinding path scaffold needle =
  LintFinding
    path
    ("product-truth.scaffold." <> scaffoldKey scaffold)
    ( "product source mentions forbidden scaffold `"
        <> needle
        <> "` ("
        <> scaffoldDescription scaffold
        <> ")"
    )
    "remove the scaffold from src/ or keep it under test support only"

importFinding :: SourceModule -> Text -> LintFinding
importFinding sourceModule imported =
  LintFinding
    (sourceModulePath sourceModule)
    "product-truth.reachable-import"
    ( "product command graph reaches forbidden scaffold import `"
        <> imported
        <> "` from module `"
        <> sourceModuleName sourceModule
        <> "`"
    )
    "remove the import from product-reachable modules or move the helper under test support"
