{-# LANGUAGE OverloadedStrings #-}

-- | Product-truth source lints: forbidden scaffolding, product-reachable
-- scaffold imports, and (through "JitML.Lint.ProductTruthBars") convergence
-- bars derived from the value they grade.
module JitML.Lint.ProductTruth
  ( ProductScaffold (..)
  , SourceModule (..)
  , checkProductTruth
  , checkProductTruthIn
  , nonProductScaffolding
  , productScaffoldRegistry
  , productTruthSourceFiles
  , reachableModulesFrom
  , scanProductTruthImports
  , scanProductTruthSourceText
  )
where

import Data.Char (isAlphaNum)
import Data.List qualified as List
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath ((</>))
import System.FilePath qualified as FilePath

import JitML.Lint.ProductTruthBars (barSourceFindings)
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

-- | The lint over the repository rooted at the working directory, which is how
-- @jitml check-code@ runs it.
checkProductTruth :: IO [LintFinding]
checkProductTruth = checkProductTruthIn "."

-- | The lint over the repository rooted at @root@. Files are read below @root@
-- but scanned, and their findings reported, by their path relative to it
-- (@src/...@): the scanner's exemptions are keyed by repository-relative path.
checkProductTruthIn :: FilePath -> IO [LintFinding]
checkProductTruthIn root = do
  files <- productTruthSourceFiles root
  sourceFindings <-
    concat
      <$> traverse
        ( \path -> do
            content <- Text.IO.readFile (root </> path)
            pure (scanProductTruthSourceText path content)
        )
        files
  modules <- traverse (readSourceModule root) files
  pure (sourceFindings <> scanProductTruthImports modules)

-- | The Haskell sources the gate reads: every @.hs@ file below @root/src@, at any
-- depth, as paths relative to @root@ in path order. A root without a @src@
-- directory has none, as for the sibling lints.
productTruthSourceFiles :: FilePath -> IO [FilePath]
productTruthSourceFiles root = do
  exists <- doesDirectoryExist (root </> "src")
  if exists
    then List.sort . filter isHaskellSource <$> repoFiles root "src"
    else pure []

scanProductTruthSourceText :: FilePath -> Text -> [LintFinding]
scanProductTruthSourceText path content
  | normalizedPath path == productTruthPath = []
  | otherwise =
      [ scaffoldFinding path scaffold needle
      | scaffold <- productScaffoldRegistry
      , needle <- scaffoldNeedles scaffold
      , needle `Text.isInfixOf` content
      ]
        <> barSourceFindings path content

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

readSourceModule :: FilePath -> FilePath -> IO SourceModule
readSourceModule root path = do
  content <- Text.IO.readFile (root </> path)
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

-- | Every file below @relative@ (a directory of the repository rooted at
-- @root@), as a path relative to @root@.
repoFiles :: FilePath -> FilePath -> IO [FilePath]
repoFiles root relative = do
  entries <- listDirectory (root </> relative)
  concat
    <$> traverse
      ( \entry -> do
          let path = relative </> entry
          isDir <- doesDirectoryExist (root </> path)
          if isDir
            then repoFiles root path
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
