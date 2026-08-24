{-# LANGUAGE OverloadedStrings #-}

module JitML.Docs.Check
  ( DocsDrift (..)
  , checkDocs
  , checkDocumentClosureClaimsText
  , checkDocumentMetadataText
  , checkRootDocMetadataText
  , docNameConforms
  , docsCategoryAllowed
  , docsDriftRemedy
  , phaseLinkTargets
  , renderDocsDrift
  , replaceGeneratedSection
  )
where

import Control.Monad (filterM)
import Data.Char (isAsciiLower, isDigit)
import Data.List (find, findIndex, isPrefixOf, sort)
import Data.Maybe (isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (takeBaseName, takeDirectory, takeExtension, takeFileName, (</>))

import JitML.Generated.Paths (TrackedGeneratedPath (..), trackingGeneratedPaths)
import JitML.Generated.Registry
  ( GeneratedSectionRule (..)
  , endMarker
  , generatedSectionRules
  , startMarker
  )
import JitML.Lint.Docs
  ( ClosureClaim (..)
  , closureClaimKey
  , scanClosureClaims
  )
import JitML.Product.PhaseStatus qualified as PhaseStatus

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
  governedPaths <- governedMarkdownPaths
  metadataDrifts <- concat <$> traverse checkDocumentMetadata governedPaths
  closureClaimDrifts <- concat <$> traverse checkDocumentClosureClaims governedPaths
  phaseLinkDrifts <- concat <$> traverse checkDocumentPhaseLinks governedPaths
  orphanDrifts <- checkOrphanedGeneratedTemplates
  taxonomyDrifts <- checkDocumentsTaxonomy
  namingDrifts <- checkDocumentsNaming
  pure
    ( sectionDrifts
        <> pathDrifts
        <> metadataDrifts
        <> closureClaimDrifts
        <> phaseLinkDrifts
        <> orphanDrifts
        <> taxonomyDrifts
        <> namingDrifts
    )

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
  | "closure-claim." `Text.isPrefixOf` driftKey drift =
      "remove the current product-closure claim, or mark dated historical evidence explicitly"
  | "phase-link." `Text.isPrefixOf` driftKey drift =
      "repoint the citation at an existing phase document; a renumber moves every target"
  | "orphan-template." `Text.isPrefixOf` driftKey drift =
      "delete the stale generated template, or restore the registry entry that produced it"
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
  rootDocs <- concat <$> traverse markdownFileIfPresent rootDocNames
  planDocs <- markdownFilesUnder "DEVELOPMENT_PLAN"
  governedDocs <- markdownFilesUnder "documents"
  pure (sort (rootDocs <> planDocs <> governedDocs))

rootDocNames :: [FilePath]
rootDocNames = ["README.md", "AGENTS.md", "CLAUDE.md"]

isRootDoc :: FilePath -> Bool
isRootDoc path = path `elem` rootDocNames

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

-- | A generated chart template with no registry entry behind it is stale.
--
-- @jitml docs generate@ writes tracked paths but does not remove files that
-- stopped being tracked, and drift checking only inspects paths still on the
-- list, so deleting a registry entry silently leaves its rendered template on
-- disk. Helm would keep deploying it. Removing the Harbor routes left exactly
-- four such orphans. The generated prefixes are enumerated rather than globbed
-- so an unrelated hand-written template is never mistaken for an orphan.
checkOrphanedGeneratedTemplates :: IO [DocsDrift]
checkOrphanedGeneratedTemplates = do
  dirExists <- doesDirectoryExist templateDirectory
  if not dirExists
    then pure []
    else do
      entries <- listDirectory templateDirectory
      let tracked =
            Set.fromList (fmap trackedPath trackingGeneratedPaths)
          orphans =
            [ path
            | entry <- sort entries
            , any (`isPrefixOf` entry) generatedTemplatePrefixes
            , let path = templateDirectory </> entry
            , not (Set.member path tracked)
            ]
      pure (fmap orphanTemplateDrift orphans)
 where
  templateDirectory = "chart" </> "templates"

-- | Template name prefixes that are rendered from a Haskell registry.
generatedTemplatePrefixes :: [FilePath]
generatedTemplatePrefixes =
  ["httproute-", "grafana-dashboard-", "prometheus-scrapeconfig-"]

orphanTemplateDrift :: FilePath -> DocsDrift
orphanTemplateDrift path =
  DocsDrift
    { driftPath = path
    , driftKey = "orphan-template." <> Text.pack (takeFileName path)
    , driftReason = "generated template has no tracked registry entry"
    }

-- | Every @phase-N-slug.md@ citation in a governed document must resolve.
--
-- Metadata validation alone cannot catch this: a phase renumber rewrites the
-- numbers in prose and moves the files, and any citation missed by that sweep
-- stays syntactically valid markdown pointing at nothing. The 2026-07-24
-- renumber left a long tail of exactly those. Resolving each target against the
-- citing document\'s own directory makes a renumber fail closed here instead of
-- silently degrading the plan\'s cross-references.
checkDocumentPhaseLinks :: FilePath -> IO [DocsDrift]
checkDocumentPhaseLinks path = do
  contents <- Text.IO.readFile path
  let base = takeDirectory path
  concat <$> traverse (resolve base) (phaseLinkTargets contents)
 where
  resolve base target = do
    exists <- doesFileExist (base </> target)
    pure [phaseLinkDrift path target | not exists]

-- | The distinct @phase-N-slug.md@ link targets a markdown document cites.
--
-- Targets are read out of markdown link destinations only, so a phase file name
-- mentioned in prose or inside a fenced block is not mistaken for a citation.
phaseLinkTargets :: Text -> [FilePath]
phaseLinkTargets contents =
  Set.toList
    ( Set.fromList
        [ Text.unpack candidate
        | segment <- linkDestinations contents
        , let candidate = Text.takeWhile (\c -> c /= ')' && c /= '#') segment
        , isPhaseDocumentName (takeFileName (Text.unpack candidate))
        ]
    )
 where
  -- Everything after a "](" is a link destination; the leading segment is the
  -- prose before the first link and is not one.
  linkDestinations text =
    case Text.splitOn "](" text of
      [] -> []
      (_prose : destinations) -> destinations

-- | @phase-<digits>-<lower-kebab>.md@, the canonical phase document name.
isPhaseDocumentName :: FilePath -> Bool
isPhaseDocumentName name =
  case stripPrefixText "phase-" name of
    Nothing -> False
    Just rest ->
      let (digits, remainder) = span isDigit rest
       in not (null digits)
            && takeExtension name == ".md"
            && case remainder of
              ('-' : slug) -> not (null (takeBaseName slug))
              _ -> False
 where
  stripPrefixText prefix value =
    if prefix == take (length prefix) value
      then Just (drop (length prefix) value)
      else Nothing

phaseLinkDrift :: FilePath -> FilePath -> DocsDrift
phaseLinkDrift path target =
  DocsDrift
    { driftPath = path
    , driftKey = "phase-link." <> Text.pack target
    , driftReason = "cited phase document does not exist: " <> Text.pack target
    }

checkDocumentsTaxonomy :: IO [DocsDrift]
checkDocumentsTaxonomy = do
  dirExists <- doesDirectoryExist "documents"
  if not dirExists
    then pure []
    else do
      entries <- sort <$> listDirectory "documents"
      subdirs <- filterM (doesDirectoryExist . ("documents" </>)) entries
      pure
        [ metadataDrift
            ("documents" </> name)
            "taxonomy.category"
            ("documents/ category `" <> Text.pack name <> "` is not an allowed category (cli, engineering)")
        | name <- subdirs
        , not (docsCategoryAllowed name)
        ]

docsCategoryAllowed :: FilePath -> Bool
docsCategoryAllowed name = name `elem` ["cli", "engineering"]

checkDocumentsNaming :: IO [DocsDrift]
checkDocumentsNaming = do
  paths <- markdownFilesUnder "documents"
  pure
    [ metadataDrift
        path
        "naming.snake-case"
        ("governed document name `" <> Text.pack (takeFileName path) <> "` is not lowercase snake_case")
    | path <- paths
    , not (docNameConforms (takeFileName path))
    ]

docNameConforms :: FilePath -> Bool
docNameConforms name
  | name == "README.md" = True
  | takeExtension name /= ".md" = False
  | otherwise = not (null base) && all conformingChar base
 where
  base = takeBaseName name
  conformingChar c = isAsciiLower c || isDigit c || c == '_'

checkDocumentMetadata :: FilePath -> IO [DocsDrift]
checkDocumentMetadata path =
  metadataChecker path <$> Text.IO.readFile path
 where
  metadataChecker
    | isRootDoc path = checkRootDocMetadataText
    | otherwise = checkDocumentMetadataText

checkDocumentClosureClaims :: FilePath -> IO [DocsDrift]
checkDocumentClosureClaims path =
  checkDocumentClosureClaimsText PhaseStatus.allProductPhasesDone path <$> Text.IO.readFile path

checkDocumentClosureClaimsText :: Bool -> FilePath -> Text -> [DocsDrift]
checkDocumentClosureClaimsText productPhasesDone path =
  fmap closureClaimDrift . scanClosureClaims productPhasesDone path

checkDocumentMetadataText :: FilePath -> Text -> [DocsDrift]
checkDocumentMetadataText path content =
  missingRequiredFieldDrifts path content topicRequiredFields
    <> generatedSectionDrifts path content

checkRootDocMetadataText :: FilePath -> Text -> [DocsDrift]
checkRootDocMetadataText path content =
  missingRequiredFieldDrifts path content rootRequiredFields
    <> generatedSectionDrifts path content

topicRequiredFields :: [(Text, Text)]
topicRequiredFields =
  [ ("metadata.status", "**Status**:")
  , ("metadata.supersedes", "**Supersedes**:")
  , ("metadata.referenced-by", "**Referenced by**:")
  , ("metadata.generated-sections", "**Generated sections**:")
  , ("metadata.purpose", "> **Purpose**:")
  ]

rootRequiredFields :: [(Text, Text)]
rootRequiredFields =
  [ ("metadata.status", "**Status**:")
  , ("metadata.supersedes", "**Supersedes**:")
  , ("metadata.canonical-homes", "**Canonical homes**:")
  , ("metadata.purpose", "> **Purpose**:")
  ]

headerField :: Text -> Text -> Maybe Text
headerField content prefix =
  Text.strip . Text.drop (Text.length prefix)
    <$> find (Text.isPrefixOf prefix . Text.strip) (take 80 (Text.lines content))

missingRequiredFieldDrifts :: FilePath -> Text -> [(Text, Text)] -> [DocsDrift]
missingRequiredFieldDrifts path content requiredFields =
  [ metadataDrift path key ("missing required header field `" <> prefix <> "`")
  | (key, prefix) <- requiredFields
  , isNothing (headerField content prefix)
  ]

generatedSectionDrifts :: FilePath -> Text -> [DocsDrift]
generatedSectionDrifts path content =
  case headerField content "**Generated sections**:" of
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

closureClaimDrift :: ClosureClaim -> DocsDrift
closureClaimDrift claim =
  DocsDrift
    { driftPath = closureClaimPath claim
    , driftKey = closureClaimKey claim
    , driftReason =
        "product closure claim before Phases 220-287 are Done at line "
          <> Text.pack (show (closureClaimLineNumber claim))
          <> ": "
          <> closureClaimLine claim
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
