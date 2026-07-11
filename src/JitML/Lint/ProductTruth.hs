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

import Data.Char (isAlphaNum)
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
