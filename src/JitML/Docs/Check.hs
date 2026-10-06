{-# LANGUAGE OverloadedStrings #-}

module JitML.Docs.Check
  ( DocsCheckEnvironment (..)
  , DocsDrift (..)
  , catalogueProblemDrifts
  , checkDocs
  , checkDocsWith
  , checkDocumentClosureClaimsText
  , checkDocumentMetadataText
  , checkRootDocMetadataText
  , closureStatusDrifts
  , docNameConforms
  , docsCategoryAllowed
  , docsDriftRemedy
  , phaseCoverageDrifts
  , phaseLinkTargets
  , productionDocsEnvironment
  , renderDocsDrift
  , replaceGeneratedSection
  , statusProjectionDrifts
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
import JitML.Product.PlanDoc
  ( PlanIssue (..)
  , closureStatusLengthIssue
  , closureStatusLineCap
  , planDocumentIssues
  , unregisteredPhaseDocuments
  )
import JitML.Product.StatusEvidence
  ( ClosureVerdict
  , PhaseEntry (..)
  , SprintEntry (..)
  , SprintProjection (..)
  , StatusReport
  , closureVerdictSummary
  , reportProjections
  , reportVerdict
  )
import JitML.Product.StatusLoader
  ( listCommittedValidationFilesIn
  , loadProductStatusReport
  , underRoot
  , unexpectedValidationFiles
  )
import JitML.Product.ValidationRecord (committedValidationDirectory)

data DocsDrift = DocsDrift
  { driftPath :: FilePath
  , driftKey :: Text
  , driftReason :: Text
  }
  deriving stock (Eq, Show)

-- | Everything one @docs check@ pass reads that is not compiled into the binary:
-- the repository root, the Closure Status length cap, and how the evidence
-- projection is obtained. The production pass is 'productionDocsEnvironment';
-- a test supplies a fixture tree, a cap, and where a case needs it a fixed
-- report, so the whole composed check runs without touching the working
-- directory.
data DocsCheckEnvironment = DocsCheckEnvironment
  { docsRoot :: FilePath
  -- ^ every governed file is read below this directory; drift paths stay
  -- relative to it
  , docsClosureStatusLineCap :: Maybe Int
  -- ^ the cap on the plan README's Closure Status section, if it is enforced
  , docsCatalogueProblems :: [Text]
  -- ^ the status catalogue's own structural problems, each reported as a drift
  , docsStatusReport :: IO StatusReport
  -- ^ the projection every status and closure check consumes
  }

-- | The production pass: the working directory is the repository root, the cap
-- is the one constant in "JitML.Product.PlanDoc", the catalogue problems are those
-- of the real catalogue, and the projection is read from the evidence committed in
-- that tree.
productionDocsEnvironment :: DocsCheckEnvironment
productionDocsEnvironment =
  DocsCheckEnvironment
    { docsRoot = "."
    , docsClosureStatusLineCap = closureStatusLineCap
    , docsCatalogueProblems = PhaseStatus.validateProductStatusCatalogue
    , docsStatusReport = loadProductStatusReport
    }

checkDocs :: IO [DocsDrift]
checkDocs = checkDocsWith productionDocsEnvironment

-- | The composed check. The status projection is read once; the closure-claim
-- scan and the phase-document comparison consume the same report.
checkDocsWith :: DocsCheckEnvironment -> IO [DocsDrift]
checkDocsWith environment = do
  sectionDrifts <- concat <$> traverse (checkGeneratedSection root) generatedSectionRules
  pathDrifts <- concat <$> traverse (checkTrackedGeneratedPath root) trackingGeneratedPaths
  governedPaths <- governedMarkdownPaths root
  metadataDrifts <- concat <$> traverse (checkDocumentMetadata root) governedPaths
  report <- docsStatusReport environment
  closureClaimDrifts <-
    concat <$> traverse (checkDocumentClosureClaims root (reportVerdict report)) governedPaths
  let catalogueDrifts = catalogueProblemDrifts (docsCatalogueProblems environment)
  projectionDrifts <- checkStatusProjection root report
  coverageDrifts <- checkPhaseDocumentCoverage root
  validationFileDrifts <- checkValidationDirectory root
  thinStatusDrifts <- checkClosureStatusThin root (docsClosureStatusLineCap environment)
  phaseLinkDrifts <- concat <$> traverse (checkDocumentPhaseLinks root) governedPaths
  orphanDrifts <- checkOrphanedGeneratedTemplates root
  taxonomyDrifts <- checkDocumentsTaxonomy root
  namingDrifts <- checkDocumentsNaming root
  pure
    ( sectionDrifts
        <> pathDrifts
        <> metadataDrifts
        <> closureClaimDrifts
        <> catalogueDrifts
        <> projectionDrifts
        <> coverageDrifts
        <> validationFileDrifts
        <> thinStatusDrifts
        <> phaseLinkDrifts
        <> orphanDrifts
        <> taxonomyDrifts
        <> namingDrifts
    )
 where
  root = docsRoot environment

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
  | "status-projection." `Text.isPrefixOf` driftKey drift =
      "make the sprint header say the status the evidence derives, or land or refresh the evidence the projection reads (`jitml docs status` lists every unmet obligation)"
  | "plan-structure." `Text.isPrefixOf` driftKey drift =
      "repair the sprint block: Status, Blocked by, Remaining Work, and Validation follow development-plan standards rules C, H, and M"
  | "validation-record." `Text.isPrefixOf` driftKey drift =
      "rename or delete the file: the validation directory holds exactly one `<gate>.<substrate>.json` record per gate and substrate"
  | "status-catalogue." `Text.isPrefixOf` driftKey drift =
      "repair the status catalogue in src/JitML/Product/PhaseStatus.hs; legacy attestation is frozen and shrink-only"
  | "closure-status." `Text.isPrefixOf` driftKey drift =
      "move dated narrative below the thin Closure Status section into the historical diary"
  | "orphan-template." `Text.isPrefixOf` driftKey drift =
      "delete the stale generated template, or restore the registry entry that produced it"
  | otherwise = "run `jitml docs generate` to update"

checkGeneratedSection :: FilePath -> GeneratedSectionRule -> IO [DocsDrift]
checkGeneratedSection root rule = do
  exists <- doesFileExist (underRoot root (rulePath rule))
  if exists
    then do
      current <- Text.IO.readFile (underRoot root (rulePath rule))
      case replaceGeneratedSection rule current of
        Left reason -> pure [sectionDrift rule reason]
        Right expected
          | expected == current -> pure []
          | otherwise -> pure [sectionDrift rule "generated section drift"]
    else pure [sectionDrift rule "file is missing"]

checkTrackedGeneratedPath :: FilePath -> TrackedGeneratedPath -> IO [DocsDrift]
checkTrackedGeneratedPath root tracked = do
  exists <- doesFileExist (underRoot root (trackedPath tracked))
  if exists
    then do
      current <- Text.IO.readFile (underRoot root (trackedPath tracked))
      if current == ensureFinalNewline (trackedRendered tracked)
        then pure []
        else pure [pathDrift tracked "tracked-generated file drift"]
    else pure [pathDrift tracked "tracked-generated file is missing"]

-- | The governed Markdown files below @root@, as paths relative to it.
governedMarkdownPaths :: FilePath -> IO [FilePath]
governedMarkdownPaths root = do
  rootDocs <- concat <$> traverse (markdownFileIfPresent root) rootDocNames
  planDocs <- markdownFilesUnder root "DEVELOPMENT_PLAN"
  governedDocs <- markdownFilesUnder root "documents"
  pure (sort (rootDocs <> planDocs <> governedDocs))

rootDocNames :: [FilePath]
rootDocNames = ["README.md", "AGENTS.md", "CLAUDE.md"]

isRootDoc :: FilePath -> Bool
isRootDoc path = path `elem` rootDocNames

markdownFileIfPresent :: FilePath -> FilePath -> IO [FilePath]
markdownFileIfPresent root path = do
  exists <- doesFileExist (underRoot root path)
  pure [path | exists, takeExtension path == ".md"]

markdownFilesUnder :: FilePath -> FilePath -> IO [FilePath]
markdownFilesUnder root path = do
  fileExists <- doesFileExist (underRoot root path)
  dirExists <- doesDirectoryExist (underRoot root path)
  case (fileExists, dirExists) of
    (True, _) -> markdownFileIfPresent root path
    (_, True) -> do
      entries <- sort <$> listDirectory (underRoot root path)
      concat <$> traverse (markdownFilesUnder root . (path </>)) entries
    _ -> pure []

-- | A generated chart template with no registry entry behind it is stale.
--
-- @jitml docs generate@ writes tracked paths but does not remove files that
-- stopped being tracked, and drift checking only inspects paths still on the
-- list, so deleting a registry entry silently leaves its rendered template on
-- disk. Helm would keep deploying it. Removing the Harbor routes left exactly
-- four such orphans. The generated prefixes are enumerated rather than globbed
-- so an unrelated hand-written template is never mistaken for an orphan.
checkOrphanedGeneratedTemplates :: FilePath -> IO [DocsDrift]
checkOrphanedGeneratedTemplates root = do
  dirExists <- doesDirectoryExist (underRoot root templateDirectory)
  if not dirExists
    then pure []
    else do
      entries <- listDirectory (underRoot root templateDirectory)
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
checkDocumentPhaseLinks :: FilePath -> FilePath -> IO [DocsDrift]
checkDocumentPhaseLinks root path = do
  contents <- Text.IO.readFile (underRoot root path)
  let base = takeDirectory path
  concat <$> traverse (resolve base) (phaseLinkTargets contents)
 where
  resolve base target = do
    exists <- doesFileExist (underRoot root (base </> target))
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

checkDocumentsTaxonomy :: FilePath -> IO [DocsDrift]
checkDocumentsTaxonomy root = do
  dirExists <- doesDirectoryExist (underRoot root "documents")
  if not dirExists
    then pure []
    else do
      entries <- sort <$> listDirectory (underRoot root "documents")
      subdirs <- filterM (doesDirectoryExist . underRoot root . ("documents" </>)) entries
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

checkDocumentsNaming :: FilePath -> IO [DocsDrift]
checkDocumentsNaming root = do
  paths <- markdownFilesUnder root "documents"
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

checkDocumentMetadata :: FilePath -> FilePath -> IO [DocsDrift]
checkDocumentMetadata root path =
  metadataChecker path <$> Text.IO.readFile (underRoot root path)
 where
  metadataChecker
    | isRootDoc path = checkRootDocMetadataText
    | otherwise = checkDocumentMetadataText

checkDocumentClosureClaims :: FilePath -> ClosureVerdict -> FilePath -> IO [DocsDrift]
checkDocumentClosureClaims root verdict path =
  checkDocumentClosureClaimsText verdict path <$> Text.IO.readFile (underRoot root path)

-- | Closure claims are allowed only when the evidence projection closes; a
-- refused verdict rejects them whatever any status literal says.
checkDocumentClosureClaimsText :: ClosureVerdict -> FilePath -> Text -> [DocsDrift]
checkDocumentClosureClaimsText verdict path =
  fmap (closureClaimDrift verdict) . scanClosureClaims verdict path

-- | Compare every phase document with the status the evidence derives, and
-- apply the plan-structure rules to each sprint block.
checkStatusProjection :: FilePath -> StatusReport -> IO [DocsDrift]
checkStatusProjection root report = do
  documents <- traverse readPhaseDocument PhaseStatus.productStatusCatalogue
  pure (statusProjectionDrifts report documents)
 where
  readPhaseDocument phase = do
    let path = underRoot root (entryPhaseDocument phase)
    exists <- doesFileExist path
    content <- traverse Text.IO.readFile (if exists then Just path else Nothing)
    pure (phase, content)

-- | Every plan document from the first product phase on must be in the status
-- catalogue: a phase dropped from the catalogue would leave every closure
-- verdict while its document stayed in the plan.
checkPhaseDocumentCoverage :: FilePath -> IO [DocsDrift]
checkPhaseDocumentCoverage root = do
  exists <- doesDirectoryExist (underRoot root planDirectory)
  names <- if exists then sort <$> listDirectory (underRoot root planDirectory) else pure []
  pure (phaseCoverageDrifts names)

planDirectory :: FilePath
planDirectory = "DEVELOPMENT_PLAN"

-- | The pure core of 'checkPhaseDocumentCoverage' over the file names found in
-- the plan directory.
phaseCoverageDrifts :: [FilePath] -> [DocsDrift]
phaseCoverageDrifts names =
  [ DocsDrift
      { driftPath = planDirectory </> name
      , driftKey = issueKey issue
      , driftReason = issueMessage issue
      }
  | (name, issue) <-
      unregisteredPhaseDocuments
        PhaseStatus.firstProductPhase
        PhaseStatus.productPhaseNumbers
        names
  ]

-- | A file in the committed validation directory that is not a record name is
-- misplaced evidence: the projection would read it as absent.
checkValidationDirectory :: FilePath -> IO [DocsDrift]
checkValidationDirectory root = do
  names <- listCommittedValidationFilesIn root
  pure
    [ DocsDrift
        { driftPath = committedValidationDirectory </> name
        , driftKey = "validation-record." <> Text.pack name
        , driftReason =
            "not a <gate>.<substrate>.json validation record name, so the status projection ignores it"
        }
    | name <- unexpectedValidationFiles names
    ]

-- | Each structural problem of the status catalogue as a drift against the file
-- that holds the catalogue. The key is a stable slug of the problem's opening.
catalogueProblemDrifts :: [Text] -> [DocsDrift]
catalogueProblemDrifts problems =
  [ DocsDrift
      { driftPath = "src/JitML/Product/PhaseStatus.hs"
      , driftKey = "status-catalogue." <> Text.take 60 (Text.map keyChar problem)
      , driftReason = problem
      }
  | problem <- problems
  ]
 where
  keyChar char
    | isAsciiLower char || isDigit char = char
    | otherwise = '-'

-- | The pure core of 'checkStatusProjection': each catalogue phase paired with
-- its document text, or 'Nothing' when the document is missing.
statusProjectionDrifts :: StatusReport -> [(PhaseEntry, Maybe Text)] -> [DocsDrift]
statusProjectionDrifts report =
  concatMap phaseDrifts
 where
  phaseDrifts (phase, Nothing) =
    [ DocsDrift
        { driftPath = entryPhaseDocument phase
        , driftKey = "status-projection." <> entrySprintId sprint
        , driftReason = "the phase document for sprint " <> entrySprintId sprint <> " is missing"
        }
    | sprint <- take 1 (entrySprints phase)
    ]
  phaseDrifts (phase, Just content) =
    fmap
      (planIssueDrift (entryPhaseDocument phase))
      (planDocumentIssues (projectionsOf phase) content)
  projectionsOf phase =
    [ projection
    | projection <- reportProjections report
    , projectionSprint projection `elem` fmap entrySprintId (entrySprints phase)
    ]

planIssueDrift :: FilePath -> PlanIssue -> DocsDrift
planIssueDrift path issue =
  DocsDrift
    { driftPath = path
    , driftKey = issueKey issue
    , driftReason = issueMessage issue
    }

-- | The plan README's Closure Status section must stay thin once the cap in
-- 'closureStatusLineCap' is set; while the cap is off nothing is read.
checkClosureStatusThin :: FilePath -> Maybe Int -> IO [DocsDrift]
checkClosureStatusThin root cap =
  case cap of
    Nothing -> pure []
    Just _ -> do
      let path = "DEVELOPMENT_PLAN" </> "README.md"
      exists <- doesFileExist (underRoot root path)
      if exists
        then closureStatusDrifts cap path <$> Text.IO.readFile (underRoot root path)
        else pure []

-- | The pure core of 'checkClosureStatusThin' for a given cap and README text.
closureStatusDrifts :: Maybe Int -> FilePath -> Text -> [DocsDrift]
closureStatusDrifts cap path content =
  fmap (planIssueDrift path) (closureStatusLengthIssue cap content)

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

closureClaimDrift :: ClosureVerdict -> ClosureClaim -> DocsDrift
closureClaimDrift verdict claim =
  DocsDrift
    { driftPath = closureClaimPath claim
    , driftKey = closureClaimKey claim
    , driftReason =
        "product closure claim before Phases "
          <> Text.pack (show first)
          <> "-"
          <> Text.pack (show final)
          <> " are Done ("
          <> closureVerdictSummary verdict
          <> ") at line "
          <> Text.pack (show (closureClaimLineNumber claim))
          <> ": "
          <> closureClaimLine claim
    }
 where
  (first, final) = PhaseStatus.productPhaseRange

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
