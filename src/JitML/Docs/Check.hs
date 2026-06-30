{-# LANGUAGE OverloadedStrings #-}

module JitML.Docs.Check
  ( DocsDrift (..)
  , checkDocs
  , checkDocumentMetadataText
  , docsDriftRemedy
  , renderDocsDrift
  , replaceGeneratedSection
  )
where

import Data.List (find, findIndex, sort)
import Data.Maybe (isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import JitML.Generated.Paths (TrackedGeneratedPath (..), trackingGeneratedPaths)
import JitML.Generated.Registry
  ( GeneratedSectionRule (..)
  , endMarker
  , generatedSectionRules
  , startMarker
  )

data DocsDrift = DocsDrift
  { driftPath :: FilePath
  , driftKey :: Text
  , driftReason :: Text
  }
  deriving stock (Eq, Show)

checkDocs :: IO [DocsDrift]
checkDocs = do
  sectionDrifts <- concat <$> traverse checkGeneratedSection generatedSectionRules
  pathDrifts <- concat <$> traverse checkTrackedGeneratedPath trackingGeneratedPaths
  metadataDrifts <- concat <$> (governedMarkdownPaths >>= traverse checkDocumentMetadata)
  pure (sectionDrifts <> pathDrifts <> metadataDrifts)

renderDocsDrift :: DocsDrift -> Text
renderDocsDrift drift =
  Text.unlines
    [ "file: " <> Text.pack (driftPath drift)
    , "key: " <> driftKey drift
    , "reason: " <> driftReason drift
    , "remedy: " <> docsDriftRemedy drift
    ]

docsDriftRemedy :: DocsDrift -> Text
docsDriftRemedy drift
  | "metadata." `Text.isPrefixOf` driftKey drift =
      "update governed document header metadata"
  | otherwise = "run `jitml docs generate` to update"

checkGeneratedSection :: GeneratedSectionRule -> IO [DocsDrift]
checkGeneratedSection rule = do
  exists <- doesFileExist (rulePath rule)
  if exists
    then do
      current <- Text.IO.readFile (rulePath rule)
      case replaceGeneratedSection rule current of
        Left reason -> pure [sectionDrift rule reason]
        Right expected
          | expected == current -> pure []
          | otherwise -> pure [sectionDrift rule "generated section drift"]
    else pure [sectionDrift rule "file is missing"]

checkTrackedGeneratedPath :: TrackedGeneratedPath -> IO [DocsDrift]
checkTrackedGeneratedPath tracked = do
  exists <- doesFileExist (trackedPath tracked)
  if exists
    then do
      current <- Text.IO.readFile (trackedPath tracked)
      if current == ensureFinalNewline (trackedRendered tracked)
        then pure []
        else pure [pathDrift tracked "tracked-generated file drift"]
    else pure [pathDrift tracked "tracked-generated file is missing"]

governedMarkdownPaths :: IO [FilePath]
governedMarkdownPaths = do
  rootReadme <- markdownFileIfPresent "README.md"
  planDocs <- markdownFilesUnder "DEVELOPMENT_PLAN"
  governedDocs <- markdownFilesUnder "documents"
  pure (sort (rootReadme <> planDocs <> governedDocs))

markdownFileIfPresent :: FilePath -> IO [FilePath]
markdownFileIfPresent path = do
  exists <- doesFileExist path
  pure [path | exists, takeExtension path == ".md"]

markdownFilesUnder :: FilePath -> IO [FilePath]
markdownFilesUnder path = do
  fileExists <- doesFileExist path
  dirExists <- doesDirectoryExist path
  case (fileExists, dirExists) of
    (True, _) -> markdownFileIfPresent path
    (_, True) -> do
      entries <- sort <$> listDirectory path
      concat <$> traverse (markdownFilesUnder . (path </>)) entries
    _ -> pure []

checkDocumentMetadata :: FilePath -> IO [DocsDrift]
checkDocumentMetadata path =
  checkDocumentMetadataText path <$> Text.IO.readFile path

checkDocumentMetadataText :: FilePath -> Text -> [DocsDrift]
checkDocumentMetadataText path content =
  missingHeaderDrifts <> generatedSectionDrifts
 where
  headerLines = take 80 (Text.lines content)
  field prefix =
    Text.strip . Text.drop (Text.length prefix)
      <$> find (Text.isPrefixOf prefix . Text.strip) headerLines
  requiredFields =
    [ ("metadata.status", "**Status**:")
    , ("metadata.supersedes", "**Supersedes**:")
    , ("metadata.referenced-by", "**Referenced by**:")
    , ("metadata.generated-sections", "**Generated sections**:")
    , ("metadata.purpose", "> **Purpose**:")
    ]
  missingHeaderDrifts =
    [ metadataDrift path key ("missing required header field `" <> prefix <> "`")
    | (key, prefix) <- requiredFields
    , isNothing (field prefix)
    ]
  generatedSectionDrifts =
    case field "**Generated sections**:" of
      Nothing -> []
      Just value ->
        case parseGeneratedSectionsMetadata value of
          Left reason -> [metadataDrift path "metadata.generated-sections" reason]
          Right declared ->
            let (startKeys, endKeys) = scanGeneratedMarkers content
                completePhysicalKeys = sortUnique [key | key <- startKeys, key `elem` endKeys]
                registeredKeys = sortUnique [ruleKey rule | rule <- generatedSectionRules, rulePath rule == path]
             in concat
                  [ [ metadataDrift
                        path
                        ("metadata.generated-sections." <> key)
                        "generated-section start marker has no matching end marker"
                    | key <- difference startKeys endKeys
                    ]
                  , [ metadataDrift
                        path
                        ("metadata.generated-sections." <> key)
                        "generated-section end marker has no matching start marker"
                    | key <- difference endKeys startKeys
                    ]
                  , [ metadataDrift
                        path
                        ("metadata.generated-sections." <> key)
                        "Generated sections metadata declares a key without a physical marker pair"
                    | key <- difference declared completePhysicalKeys
                    ]
                  , [ metadataDrift
                        path
                        ("metadata.generated-sections." <> key)
                        "physical generated-section marker pair is missing from Generated sections metadata"
                    | key <- difference completePhysicalKeys declared
                    ]
                  , [ metadataDrift
                        path
                        ("metadata.generated-sections." <> key)
                        "Generated sections metadata omits a key registered for this file"
                    | key <- difference registeredKeys declared
                    ]
                  , [ metadataDrift
                        path
                        ("metadata.generated-sections." <> key)
                        "Generated sections metadata names a key not registered for this file"
                    | key <- difference declared registeredKeys
                    ]
                  ]

replaceGeneratedSection :: GeneratedSectionRule -> Text -> Either Text Text
replaceGeneratedSection rule current = do
  startIndex <-
    maybe
      (Left "start marker is missing")
      Right
      (findIndex ((== startMarker (ruleKey rule)) . Text.strip) currentLines)
  endIndex <-
    maybe
      (Left "end marker is missing")
      Right
      (findIndex ((== endMarker (ruleKey rule)) . Text.strip) currentLines)
  if startIndex >= endIndex
    then Left "start marker appears after end marker"
    else
      Right $
        Text.unlines $
          take (startIndex + 1) currentLines
            <> Text.lines (ensureFinalNewline (ruleRendered rule))
            <> drop endIndex currentLines
 where
  currentLines = Text.lines current

sectionDrift :: GeneratedSectionRule -> Text -> DocsDrift
sectionDrift rule reason =
  DocsDrift
    { driftPath = rulePath rule
    , driftKey = ruleKey rule
    , driftReason = reason
    }

pathDrift :: TrackedGeneratedPath -> Text -> DocsDrift
pathDrift tracked reason =
  DocsDrift
    { driftPath = trackedPath tracked
    , driftKey = trackedKey tracked
    , driftReason = reason
    }

metadataDrift :: FilePath -> Text -> Text -> DocsDrift
metadataDrift path key reason =
  DocsDrift
    { driftPath = path
    , driftKey = key
    , driftReason = reason
    }

parseGeneratedSectionsMetadata :: Text -> Either Text [Text]
parseGeneratedSectionsMetadata value
  | Text.null cleaned = Left "Generated sections metadata is empty"
  | cleaned == "none" = Right []
  | otherwise =
      let keys = fmap Text.strip (Text.splitOn "," cleaned)
       in if any Text.null keys
            then Left "Generated sections metadata contains an empty key"
            else Right (sortUnique keys)
 where
  cleaned = Text.strip value

scanGeneratedMarkers :: Text -> ([Text], [Text])
scanGeneratedMarkers =
  go False [] [] . Text.lines
 where
  go _ starts ends [] = (sortUnique starts, sortUnique ends)
  go inFence starts ends (line : rest)
    | isFence line = go (not inFence) starts ends rest
    | inFence = go inFence starts ends rest
    | otherwise =
        case (startMarkerKey stripped, endMarkerKey stripped) of
          (Just key, _) -> go inFence (key : starts) ends rest
          (_, Just key) -> go inFence starts (key : ends) rest
          _ -> go inFence starts ends rest
   where
    stripped = Text.strip line

  isFence line =
    let stripped = Text.strip line
     in "```" `Text.isPrefixOf` stripped || "~~~" `Text.isPrefixOf` stripped

startMarkerKey :: Text -> Maybe Text
startMarkerKey line =
  Text.stripPrefix "<!-- jitml:" line >>= Text.stripSuffix ":start -->"

endMarkerKey :: Text -> Maybe Text
endMarkerKey line =
  Text.stripPrefix "<!-- jitml:" line >>= Text.stripSuffix ":end -->"

sortUnique :: [Text] -> [Text]
sortUnique = Set.toAscList . Set.fromList

difference :: [Text] -> [Text] -> [Text]
difference left right = [value | value <- left, value `notElem` right]

ensureFinalNewline :: Text -> Text
ensureFinalNewline value
  | Text.isSuffixOf "\n" value = value
  | otherwise = value <> "\n"
