{-# LANGUAGE OverloadedStrings #-}

module JitML.Docs.Check
  ( DocsCheckEnvironment (..)
  , DocsDrift (..)
  , catalogueProblemDrifts
  , checkDocs
  , checkDocsWith
  , checkDocumentClosureClaimsText
  , checkDocumentMetadataText
  , checkCanonicalOwners
  , checkCanonicalDeclarations
  , checkPinnedGeneratedSource
  , checkExecutionTargetBoundary
  , checkRegisteredTargetBoundary
  , checkLocalLinkTargets
  , checkLocalLinkAnchors
  , checkLocalLinkAnchorsBatch
  , checkRootDocMetadataText
  , closureStatusDrifts
  , docNameConforms
  , docsCategoryAllowed
  , docsDriftRemedy
  , phaseCoverageDrifts
  , phaseLinkTargets
  , githubHeadingSlug
  , productionDocsEnvironment
  , renderDocsDrift
  , replaceGeneratedSection
  , statusProjectionDrifts
  )
where

import CMarkGFM (Node (..), NodeType (..), PosInfo (..), commonmarkToNode, extTable)
import Control.Exception (IOException, try)
import Control.Monad (filterM)
import Data.ByteString qualified as ByteString
import Data.Char
  ( digitToInt
  , isAlpha
  , isAlphaNum
  , isAsciiLower
  , isDigit
  , isHexDigit
  )
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (find, isPrefixOf, sort, tails)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe, maybeToList)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.FilePath (isAbsolute, takeBaseName, takeDirectory, takeExtension, takeFileName, (</>))
import Text.HTML.TagSoup (Tag (..), parseTags)

import JitML.Docs.GithubSlugData qualified as GithubSlugData
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
import JitML.Product.ValidationRecord (committedValidationDirectory, sha256Hex)

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
  sourceDrifts <-
    concat
      <$> traverse (uncurry (checkPinnedGeneratedSource root)) pinnedGeneratedSources
  governedPaths <- governedMarkdownPaths root
  metadataDrifts <- concat <$> traverse (checkDocumentMetadata root) governedPaths
  ownerDrifts <- checkCanonicalOwners root requiredCanonicalContracts canonicalOwners
  governedContents <-
    traverse (\path -> (,) path <$> Text.IO.readFile (underRoot root path)) governedPaths
  let declarationDrifts = checkCanonicalDeclarations canonicalOwners governedContents
      targetBoundaryDrifts = concatMap checkRegisteredTargetBoundary governedContents
  report <- docsStatusReport environment
  closureClaimDrifts <-
    concat <$> traverse (checkDocumentClosureClaims root (reportVerdict report)) governedPaths
  let catalogueDrifts = catalogueProblemDrifts (docsCatalogueProblems environment)
  projectionDrifts <- checkStatusProjection root report
  coverageDrifts <- checkPhaseDocumentCoverage root
  validationFileDrifts <- checkValidationDirectory root
  thinStatusDrifts <- checkClosureStatusThin root (docsClosureStatusLineCap environment)
  phaseLinkDrifts <- concat <$> traverse (checkDocumentPhaseLinks root) governedPaths
  localLinkDrifts <- concat <$> traverse (checkDocumentLocalLinks root) governedPaths
  anchorDrifts <- checkLocalLinkAnchorsBatch root governedContents
  orphanDrifts <- checkOrphanedGeneratedTemplates root
  taxonomyDrifts <- checkDocumentsTaxonomy root
  namingDrifts <- checkDocumentsNaming root
  pure
    ( sectionDrifts
        <> pathDrifts
        <> sourceDrifts
        <> metadataDrifts
        <> ownerDrifts
        <> declarationDrifts
        <> targetBoundaryDrifts
        <> closureClaimDrifts
        <> catalogueDrifts
        <> projectionDrifts
        <> coverageDrifts
        <> validationFileDrifts
        <> thinStatusDrifts
        <> phaseLinkDrifts
        <> localLinkDrifts
        <> anchorDrifts
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
  | "canonical-owner." `Text.isPrefixOf` driftKey drift =
      "restore one authoritative owner for the contract and reconcile its registered path"
  | "target-boundary." `Text.isPrefixOf` driftKey drift =
      "label the target and implemented boundaries and link the target to its owning phase"
  | "generated-source." `Text.isPrefixOf` driftKey drift =
      "regenerate the pinned source from its documented reference and update its reviewed digest"
  | "closure-claim." `Text.isPrefixOf` driftKey drift =
      "remove the current product-closure claim, or mark dated historical evidence explicitly"
  | "phase-link." `Text.isPrefixOf` driftKey drift =
      "repoint the citation at an existing phase document; a renumber moves every target"
  | "local-link." `Text.isPrefixOf` driftKey drift =
      "repair the relative destination or restore the cited file or directory"
  | "local-anchor." `Text.isPrefixOf` driftKey drift =
      "repair the fragment or restore the cited heading or explicit anchor"
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

-- | Generated source whose reference data is external to the runtime renderer.
-- The digest is reviewed alongside the generator and pinned upstream inputs.
pinnedGeneratedSources :: [(FilePath, Text)]
pinnedGeneratedSources =
  [
    ( "src/JitML/Docs/GithubSlugData.hs"
    , "17d6c4d33fe41a4bd3ff4b0005210a6721692c0edc50e842dca888d383ef41c6"
    )
  ]

checkPinnedGeneratedSource :: FilePath -> FilePath -> Text -> IO [DocsDrift]
checkPinnedGeneratedSource root path expected = do
  result <-
    try (ByteString.readFile (underRoot root path)) :: IO (Either IOException ByteString.ByteString)
  pure $ case result of
    Left _ -> [sourceDrift "generated source cannot be read"]
    Right bytes -> [sourceDrift "generated source differs from its pinned digest" | sha256Hex bytes /= expected]
 where
  sourceDrift reason =
    DocsDrift
      { driftPath = path
      , driftKey = "generated-source." <> Text.pack path
      , driftReason = reason
      }

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
        [ path
        | destination <- markdownLinkDestinations contents
        , Right (Just path) <- [relativeLinkPath destination]
        , isPhaseDocumentName (takeFileName path)
        ]
    )

markdownLinkDestinations :: Text -> [Text]
markdownLinkDestinations = markdownNodeDestinations . commonmarkToNode [] [extTable]

markdownNodeDestinations :: Node -> [Text]
markdownNodeDestinations = linkDestinations
 where
  linkDestinations (Node _ nodeType children) =
    currentDestination nodeType <> concatMap linkDestinations children
  currentDestination (LINK url _) = [url]
  currentDestination (IMAGE url _) = [url]
  currentDestination (HTML_INLINE html) = htmlDestinations html
  currentDestination (HTML_BLOCK html) = htmlDestinations html
  currentDestination _ = []

htmlDestinations :: Text -> [Text]
htmlDestinations html =
  [ destination
  | TagOpen name attributes <- parseTags html
  , let tag = Text.toCaseFold name
  , (key, value) <- attributes
  , destination <- htmlAttributeDestinations tag (Text.toCaseFold key) value
  ]

htmlAttributeDestinations :: Text -> Text -> Text -> [Text]
htmlAttributeDestinations tag key value
  | (tag, key) `elem` htmlUrlAttributes = [value]
  | (tag, key) `elem` [("img", "srcset"), ("source", "srcset"), ("link", "imagesrcset")] =
      srcsetDestinations value
  | otherwise = []

-- Form actions are application routes, not filesystem destinations.
htmlUrlAttributes :: [(Text, Text)]
htmlUrlAttributes =
  [ ("a", "href")
  , ("area", "href")
  , ("link", "href")
  , ("img", "src")
  , ("source", "src")
  , ("audio", "src")
  , ("video", "src")
  , ("video", "poster")
  , ("track", "src")
  , ("script", "src")
  , ("iframe", "src")
  , ("embed", "src")
  , ("object", "data")
  ]

-- Follow the HTML srcset URL and descriptor token boundaries, retaining every
-- URL even if a descriptor is invalid. This is deliberately conservative: a
-- broken candidate is reported rather than silently omitted by descriptor
-- validation. Commas inside URL tokens (notably data URLs) are not separators.
srcsetDestinations :: Text -> [Text]
srcsetDestinations input =
  case Text.uncons (Text.dropWhile isSeparator input) of
    Nothing -> []
    Just _ ->
      let (token, rest) = Text.span (not . isAsciiSpace) (Text.dropWhile isSeparator input)
          url = Text.dropWhileEnd (== ',') token
          remainder = if Text.isSuffixOf "," token then rest else afterDescriptors False rest
       in [url | not (Text.null url)] <> srcsetDestinations remainder
 where
  isAsciiSpace char = char `elem` (" \t\n\r\f" :: String)
  isSeparator char = isAsciiSpace char || char == ','
  afterDescriptors inParens text =
    case Text.uncons text of
      Nothing -> ""
      Just (char, rest)
        | char == ',' && not inParens -> rest
        | char == '(' && not inParens -> afterDescriptors True rest
        | char == ')' && inParens -> afterDescriptors False rest
        | otherwise -> afterDescriptors inParens rest

-- | Check relative file and directory destinations in parsed Markdown links.
-- Anchor validation is a separate obligation; absolute and external URLs do
-- not refer to a repository-relative filesystem target.
checkLocalLinkTargets :: FilePath -> FilePath -> Text -> IO [DocsDrift]
checkLocalLinkTargets root path contents =
  concat
    <$> traverse checkDestination (Set.toAscList (Set.fromList (markdownLinkDestinations contents)))
 where
  checkDestination destination =
    case relativeLinkPath destination of
      Left reason -> pure [localLinkDrift path destination reason]
      Right Nothing -> pure []
      Right (Just target)
        | isPhaseDocumentName (takeFileName target) -> pure []
        | otherwise -> do
            let resolved = underRoot root (takeDirectory path </> target)
            fileExists <- doesFileExist resolved
            directoryExists <- doesDirectoryExist resolved
            pure
              [ localLinkDrift path destination "relative target does not exist"
              | not (fileExists || directoryExists)
              ]

checkDocumentLocalLinks :: FilePath -> FilePath -> IO [DocsDrift]
checkDocumentLocalLinks root path = do
  contents <- Text.IO.readFile (underRoot root path)
  checkLocalLinkTargets root path contents

-- | Check fragments in local Markdown and HTML links using the pinned
-- github-slugger character tables and contextual case mapping.
checkLocalLinkAnchors :: FilePath -> FilePath -> Text -> IO [DocsDrift]
checkLocalLinkAnchors root path contents =
  checkLocalLinkAnchorsBatch root [(path, contents)]

-- | Share immutable target indexes for one composed observation. A new call
-- gets a fresh cache, so later checks can observe changed files.
checkLocalLinkAnchorsBatch :: FilePath -> [(FilePath, Text)] -> IO [DocsDrift]
checkLocalLinkAnchorsBatch root documents = do
  cache <- newIORef Map.empty
  concat
    <$> traverse (uncurry (checkLocalLinkAnchorsWith cache root)) documents

type AnchorIndex = (Set.Set Text, Either Text (Set.Set Text))

type AnchorCache = IORef (Map.Map FilePath (Either Text AnchorIndex))

checkLocalLinkAnchorsWith :: AnchorCache -> FilePath -> FilePath -> Text -> IO [DocsDrift]
checkLocalLinkAnchorsWith cache root path contents =
  concat
    <$> traverse checkDestination (Set.toAscList (Set.fromList (markdownLinkDestinations contents)))
 where
  checkDestination destination =
    case Text.breakOn "#" destination of
      (_, fragment) | Text.null fragment || fragment == "#" -> pure []
      (location, fragment) ->
        case decodeUrlPath (Text.drop 1 fragment) of
          Left reason -> pure [anchorDrift path destination reason]
          Right anchor -> do
            target <- resolveTarget location
            case target of
              Left reason -> pure [anchorDrift path destination reason]
              Right Nothing -> pure []
              Right (Just targetPath) -> do
                fileExists <- doesFileExist targetPath
                directoryExists <- doesDirectoryExist targetPath
                let documentPath = if directoryExists then targetPath </> "README.md" else targetPath
                documentExists <- if directoryExists then doesFileExist documentPath else pure fileExists
                if not documentExists
                  then
                    pure
                      [ anchorDrift path destination "directory fragment target has no README.md"
                      | directoryExists
                      ]
                  else
                    if documentExtension documentPath `elem` [".md", ".markdown", ".html", ".htm", ".svg"]
                      then do
                        result <- cachedAnchorIndex cache documentPath
                        pure $ case result of
                          Left reason -> [anchorDrift path destination reason]
                          Right index -> validateMarkdownAnchor path destination anchor index
                      else
                        pure
                          [anchorDrift path destination "fragment target is not a supported Markdown, HTML or SVG document"]

  resolveTarget location
    | Text.null (Text.takeWhile (/= '?') location) = pure (Right (Just (underRoot root path)))
    | otherwise =
        pure $ case relativeLinkPath location of
          Left reason -> Left reason
          Right Nothing -> Right Nothing
          Right (Just target) -> Right (Just (underRoot root (takeDirectory path </> target)))

cachedAnchorIndex :: AnchorCache -> FilePath -> IO (Either Text AnchorIndex)
cachedAnchorIndex cache path = do
  indexes <- readIORef cache
  case Map.lookup path indexes of
    Just result -> pure result
    Nothing -> do
      readResult <- try (Text.IO.readFile path) :: IO (Either IOException Text)
      let result = case readResult of
            Left _ -> Left "cannot read fragment target"
            Right contents ->
              Right $
                if documentExtension path `elem` [".md", ".markdown"]
                  then markdownAnchorIndex contents
                  else (Set.fromList (htmlAnchors contents), Right Set.empty)
      modifyIORef' cache (Map.insert path result)
      pure result

documentExtension :: FilePath -> Text
documentExtension = Text.toLower . Text.pack . takeExtension

anchorDrift :: FilePath -> Text -> Text -> DocsDrift
anchorDrift path destination reason =
  DocsDrift
    { driftPath = path
    , driftKey = "local-anchor." <> destination
    , driftReason = reason <> ": " <> destination
    }

validateMarkdownAnchor :: FilePath -> Text -> Text -> AnchorIndex -> [DocsDrift]
validateMarkdownAnchor path destination anchor (explicit, headingsResult)
  | Set.member anchor explicit = []
  | otherwise =
      case headingsResult of
        Left reason -> [anchorDrift path destination reason]
        Right headings ->
          [ anchorDrift path destination "fragment does not match a heading or explicit anchor"
          | not (Set.member anchor headings)
          ]

markdownAnchorIndex :: Text -> AnchorIndex
markdownAnchorIndex contents =
  (Set.fromList (explicitAnchors document), headingAnchors document)
 where
  document = commonmarkToNode [] [extTable] contents

explicitAnchors :: Node -> [Text]
explicitAnchors (Node _ nodeType children) =
  current nodeType <> concatMap explicitAnchors children
 where
  current (HTML_INLINE html) = htmlAnchors html
  current (HTML_BLOCK html) = htmlAnchors html
  current _ = []

htmlAnchors :: Text -> [Text]
htmlAnchors html =
  [ value
  | TagOpen name attributes <- parseTags html
  , (key, value) <- attributes
  , Text.toCaseFold key == "id"
      || (Text.toCaseFold name == "a" && Text.toCaseFold key == "name")
  ]

headingAnchors :: Node -> Either Text (Set.Set Text)
headingAnchors document = foldl addHeading (Right Set.empty) (headingTexts document)
 where
  addHeading result heading = do
    existing <- result
    base <- githubHeadingSlug heading
    let candidates = base : [base <> "-" <> Text.pack (show number) | number <- [1 :: Int ..]]
    case find (`Set.notMember` existing) candidates of
      Nothing -> Left "could not allocate heading anchor"
      Just unique -> Right (Set.insert unique existing)

headingTexts :: Node -> [Text]
headingTexts (Node _ nodeType children) =
  current nodeType <> concatMap headingTexts children
 where
  current (HEADING _) = [Text.concat (fmap headingText children)]
  current _ = []

headingText :: Node -> Text
headingText (Node _ nodeType children) =
  case nodeType of
    TEXT text -> text
    CODE text -> text
    SOFTBREAK -> " "
    LINEBREAK -> " "
    HTML_INLINE _ -> ""
    HTML_BLOCK _ -> ""
    _ -> Text.concat (fmap headingText children)

-- github-slugger lowercases the complete heading before applying its pinned
-- character filter. Final sigma is the context-sensitive default case mapping;
-- the generated tables carry the remaining scalar mappings and properties.
githubHeadingSlug :: Text -> Either Text Text
githubHeadingSlug heading = Right (Text.concat (zipWith3 slugCharacter characters before after))
 where
  characters = Text.unpack heading
  before = scanl precedingCased False characters
  after = case scanr followingCased False characters of
    [] -> []
    _ : rest -> rest
  precedingCased previous character
    | GithubSlugData.githubCaseIgnorable character = previous
    | otherwise = GithubSlugData.githubCased character
  followingCased character next
    | GithubSlugData.githubCaseIgnorable character = next
    | otherwise = GithubSlugData.githubCased character
  slugCharacter character previous next
    | character == '\x03A3' && previous && not next = "ς"
    | otherwise = GithubSlugData.githubSlugScalar character

localLinkDrift :: FilePath -> Text -> Text -> DocsDrift
localLinkDrift path destination reason =
  DocsDrift
    { driftPath = path
    , driftKey = "local-link." <> destination
    , driftReason = reason <> ": " <> destination
    }

relativeLinkPath :: Text -> Either Text (Maybe FilePath)
relativeLinkPath destination
  | Text.null path || "/" `Text.isPrefixOf` path || hasScheme path = Right Nothing
  | otherwise = do
      decoded <- decodeUrlPath path
      let filePath = Text.unpack decoded
      if Text.any (== '\NUL') decoded || isAbsolute filePath
        then Left "relative destination decodes to an invalid or absolute path"
        else Right (Just filePath)
 where
  path = Text.takeWhile (\c -> c /= '?' && c /= '#') destination
  hasScheme value =
    case Text.breakOn ":" value of
      (prefix, suffix) ->
        not (Text.null suffix)
          && case Text.uncons prefix of
            Nothing -> False
            Just (first, rest) -> isAlpha first && Text.all (\c -> isAlphaNum c || c `elem` ("+-." :: String)) rest

decodeUrlPath :: Text -> Either Text Text
decodeUrlPath value = do
  bytes <- decodeBytes (ByteString.unpack (Text.Encoding.encodeUtf8 value))
  case Text.Encoding.decodeUtf8' (ByteString.pack bytes) of
    Left _ -> Left "relative destination is not valid UTF-8"
    Right decoded -> Right decoded
 where
  decodeBytes [] = Right []
  decodeBytes (37 : first : second : rest)
    | isHexDigit (toEnum (fromIntegral first)) && isHexDigit (toEnum (fromIntegral second)) =
        let byte = 16 * digitToInt (toEnum (fromIntegral first)) + digitToInt (toEnum (fromIntegral second))
         in (fromIntegral byte :) <$> decodeBytes rest
  decodeBytes (37 : _) = Left "relative destination has an invalid percent escape"
  decodeBytes (byte : rest) = (byte :) <$> decodeBytes rest

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

-- These ownership boundaries are already explicit in the documentation
-- standard. This is deliberately not an inventory of all durable contracts;
-- untransferred root authority remains binding.
requiredCanonicalContracts :: [Text]
requiredCanonicalContracts =
  [ "documentation-standards"
  , "development-plan-standards"
  , "durable-state-configuration"
  , "execution-resources"
  , "checkpoint-storage-contract"
  , "product-completion-proof"
  , "training-metrics-and-splits"
  , "validation-execution"
  ]

canonicalOwners :: [(Text, FilePath)]
canonicalOwners =
  [ ("documentation-standards", "documents/documentation_standards.md")
  , ("development-plan-standards", "DEVELOPMENT_PLAN/development_plan_standards.md")
  , ("durable-state-configuration", "documents/engineering/durable_state_dsl.md")
  , ("execution-resources", "documents/engineering/execution_resources.md")
  , ("checkpoint-storage-contract", "documents/engineering/checkpoint_format.md")
  , ("product-completion-proof", "documents/engineering/product_completion_contract.md")
  , ("training-metrics-and-splits", "documents/engineering/training_metrics_and_splits.md")
  , ("validation-execution", "documents/engineering/validation_execution.md")
  ]

checkRegisteredTargetBoundary :: (FilePath, Text) -> [DocsDrift]
checkRegisteredTargetBoundary (path, content)
  | path
      `elem` [ owner | (key, owner) <- canonicalOwners, key `elem` ["execution-resources", "validation-execution"]
             ] =
      checkExecutionTargetBoundary path content
  | otherwise = []

-- | These execution-topic summaries describe target behavior. Require an
-- explicit boundary and a phase citation; this does not classify arbitrary
-- prose or prove that a cited phase implements the target.
checkExecutionTargetBoundary :: FilePath -> Text -> [DocsDrift]
checkExecutionTargetBoundary path content =
  sectionDrifts "TL;DR" summarySections
    <> sectionDrifts "Current Status" statusSections
    <> concatMap checkSummary summarySections
    <> concatMap checkStatus statusSections
 where
  summarySections = sections "TL;DR"
  statusSections = sections "Current Status"
  sections heading =
    [ takeWhile (not . isSectionHeading) rest
    | Node _ (HEADING 2) children : rest <- tails topLevelNodes
    , Text.concat (fmap headingText children) == heading
    ]
  Node _ _ topLevelNodes = commonmarkToNode [] [extTable] content
  isSectionHeading (Node _ (HEADING level) _) = level <= 2
  isSectionHeading _ = False
  sectionDrifts name found =
    [ boundaryDrift path "section" (name <> " section must occur exactly once")
    | length found /= 1
    ]
  checkSummary summary =
    [ boundaryDrift path "summary" "target summary must begin with an explicit target label"
    | case summary of
        first : _ -> not (hasLabel "Target." first)
        [] -> True
    ]
  checkStatus status =
    [ boundaryDrift path "implemented" "current status must label its implemented boundary once"
    | length implemented /= 1
    ]
      <> [ boundaryDrift path "target" "current status must label its target boundary once"
         | length targets /= 1
         ]
      <> [ boundaryDrift path "owner" "target boundary must cite an owning phase document"
         | [target] <- [targets]
         , not (any isPhaseDestination (markdownNodeDestinations target))
         ]
   where
    implemented = filter (hasLabel "Implemented boundary.") status
    targets = filter (hasLabel "Target.") status
  hasLabel label (Node _ PARAGRAPH (Node _ STRONG children : _)) =
    Text.concat (fmap headingText children) == label
  hasLabel _ _ = False
  isPhaseDestination destination =
    case relativeLinkPath destination of
      Right (Just target) -> isPhaseDocumentName (takeFileName target)
      _ -> False

boundaryDrift :: FilePath -> Text -> Text -> DocsDrift
boundaryDrift path key reason =
  DocsDrift
    { driftPath = path
    , driftKey = "target-boundary." <> key
    , driftReason = reason
    }

-- | Check the registered ownership boundary, not implementation of the
-- contract described by an owner. A status header alone is never evidence
-- that a target resource protocol exists or is implemented.
checkCanonicalOwners :: FilePath -> [Text] -> [(Text, FilePath)] -> IO [DocsDrift]
checkCanonicalOwners root required owners = do
  fileDrifts <- concat <$> traverse checkOwner owners
  pure (structureDrifts <> fileDrifts)
 where
  keys = Set.toAscList (Set.fromList (required <> fmap fst owners))
  structureDrifts = concatMap checkKey keys
  checkKey key =
    let paths = [path | (registered, path) <- owners, registered == key]
     in [ ownerDrift "src/JitML/Docs/Check.hs" key "contract is not in the required inventory"
        | key `notElem` required
        ]
          <> [ ownerDrift "src/JitML/Docs/Check.hs" key "contract has no registered owner"
             | key `elem` required && null paths
             ]
          <> [ ownerDrift "src/JitML/Docs/Check.hs" key "contract has multiple registered owners"
             | length paths > 1
             ]
  checkOwner (key, path) = do
    content <- try (Text.IO.readFile (underRoot root path)) :: IO (Either IOException Text)
    pure $ case content of
      Left _ -> [ownerDrift path key "registered canonical owner cannot be read"]
      Right document ->
        [ ownerDrift path key "registered canonical owner is not an authoritative source"
        | headerField document "**Status**:" /= Just "Authoritative source"
        ]

ownerDrift :: FilePath -> Text -> Text -> DocsDrift
ownerDrift path key reason =
  DocsDrift
    { driftPath = path
    , driftKey = "canonical-owner." <> key
    , driftReason = reason
    }

-- | Reconcile explicit header claims with registered owner paths. This is not a
-- natural-language classifier for unmarked claims in prose.
checkCanonicalDeclarations :: [(Text, FilePath)] -> [(FilePath, Text)] -> [DocsDrift]
checkCanonicalDeclarations owners documents =
  concatMap checkDocument documents <> missingDeclarations
 where
  declarations = [(path, declarationFields content) | (path, content) <- documents]
  checkDocument (path, content) =
    let fields = declarationFields content
        claims = concatMap (fmap Text.strip . Text.splitOn ",") fields
     in [ ownerDrift path "declaration" "canonical contracts header appears more than once"
        | length fields > 1
        ]
          <> [ownerDrift path "declaration" "canonical contract key is empty" | any Text.null claims]
          <> [ ownerDrift path key "canonical contract is claimed outside its registered owner"
             | key <- Set.toAscList (Set.fromList (filter (not . Text.null) claims))
             , (key, path) `notElem` owners
             ]
          <> [ ownerDrift path key "canonical contract is declared more than once"
             | key <- Set.toAscList (Set.fromList claims)
             , not (Text.null key)
             , length (filter (== key) claims) > 1
             ]
  missingDeclarations =
    [ ownerDrift path key "registered canonical owner does not declare its contract"
    | (key, path) <- owners
    , let fields = fromMaybe [] (lookup path declarations)
    , key `notElem` concatMap (fmap Text.strip . Text.splitOn ",") fields
    ]

declarationFields :: Text -> [Text]
declarationFields content =
  [ Text.strip (Text.drop (Text.length prefix) line)
  | raw <-
      takeWhile (not . Text.isPrefixOf "> **Purpose**:" . Text.strip) (metadataLines content)
  , let line = Text.strip raw
  , prefix `Text.isPrefixOf` line
  ]
 where
  prefix = "**Canonical contracts**:"

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
headerField content prefix = listToMaybe (headerFields content prefix)

headerFields :: Text -> Text -> [Text]
headerFields content prefix =
  [ Text.strip (Text.drop (Text.length prefix) line)
  | raw <- metadataLines content
  , let line = Text.strip raw
  , prefix `Text.isPrefixOf` line
  ]

-- Only top-level paragraphs and the purpose blockquote can provide metadata.
-- Source positions retain the original spelling while excluding examples in
-- code blocks, lists and nested quotations.
metadataLines :: Text -> [Text]
metadataLines content = concatMap sourceLines metadataNodes
 where
  Node _ _ nodes = commonmarkToNode [] [extTable] content
  metadataNodes = takeWhile (not . laterHeading) nodes
  laterHeading (Node _ (HEADING level) _) = level > 1
  laterHeading _ = False
  linesOfDocument = take 80 (Text.lines content)
  sourceLines (Node (Just position) nodeType _)
    | nodeType == PARAGRAPH || nodeType == BLOCK_QUOTE =
        take (endLine position - startLine position + 1) (drop (startLine position - 1) linesOfDocument)
  sourceLines _ = []

missingRequiredFieldDrifts :: FilePath -> Text -> [(Text, Text)] -> [DocsDrift]
missingRequiredFieldDrifts path content =
  concatMap checkField
 where
  checkField (key, prefix) =
    let values = headerFields content prefix
     in [metadataDrift path key ("missing required header field `" <> prefix <> "`") | null values]
          <> [metadataDrift path key ("empty required header field `" <> prefix <> "`") | any Text.null values]
          <> [metadataDrift path key ("duplicate required header field `" <> prefix <> "`") | length values > 1]

generatedSectionDrifts :: FilePath -> Text -> [DocsDrift]
generatedSectionDrifts path content =
  case headerField content "**Generated sections**:" of
    Nothing -> []
    Just value ->
      case parseGeneratedSectionsMetadata value of
        Left reason -> [metadataDrift path "metadata.generated-sections" reason]
        Right declared ->
          let (startKeys, endKeys) = scanGeneratedMarkers content
              markers = generatedMarkerLines content
              completePhysicalKeys = sortUnique [key | key <- startKeys, key `elem` endKeys]
              registeredKeys = sortUnique [ruleKey rule | rule <- generatedSectionRules, rulePath rule == path]
           in concat
                [ [ metadataDrift
                      path
                      ("metadata.generated-sections." <> key)
                      "generated-section start marker appears more than once"
                  | key <- sortUnique startKeys
                  , length (filter (== key) startKeys) > 1
                  ]
                , [ metadataDrift
                      path
                      ("metadata.generated-sections." <> key)
                      "generated-section end marker appears more than once"
                  | key <- sortUnique endKeys
                  , length (filter (== key) endKeys) > 1
                  ]
                , [ metadataDrift
                      path
                      ("metadata.generated-sections." <> key)
                      "generated-section end marker precedes its start marker"
                  | key <- completePhysicalKeys
                  , [start] <- [[line | (line, marker) <- markers, startMarkerKey marker == Just key]]
                  , [end] <- [[line | (line, marker) <- markers, endMarkerKey marker == Just key]]
                  , end < start
                  ]
                , [ metadataDrift
                      path
                      ("metadata.generated-sections." <> first)
                      ("generated section overlaps " <> second)
                  | (first, second) <- generatedMarkerOverlaps markers
                  ]
                , [ metadataDrift
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
  if length startIndices > 1
    then Left "start marker appears more than once"
    else Right ()
  if length endIndices > 1
    then Left "end marker appears more than once"
    else Right ()
  startIndex <-
    maybe
      (Left "start marker is missing outside Markdown examples")
      Right
      (listToMaybe startIndices)
  endIndex <-
    maybe
      (Left "end marker is missing outside Markdown examples")
      Right
      (listToMaybe endIndices)
  if startIndex >= endIndex
    then Left "start marker appears after end marker"
    else
      if generatedMarkersMalformed markers
        then Left "another generated section has invalid markers"
        else
          if not (null (generatedMarkerOverlaps markers))
            then Left "generated sections overlap"
            else
              Right $
                Text.unlines $
                  take (startIndex + 1) currentLines
                    <> Text.lines (ensureFinalNewline (ruleRendered rule))
                    <> drop endIndex currentLines
 where
  currentLines = Text.lines current
  markers = generatedMarkerLines current
  startIndices = [index | (index, line) <- markers, line == startMarker (ruleKey rule)]
  endIndices = [index | (index, line) <- markers, line == endMarker (ruleKey rule)]

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
scanGeneratedMarkers contents =
  ( [key | line <- markerLines, Just key <- [startMarkerKey line]]
  , [key | line <- markerLines, Just key <- [endMarkerKey line]]
  )
 where
  markerLines = fmap snd (generatedMarkerLines contents)

generatedMarkerOverlaps :: [(Int, Text)] -> [(Text, Text)]
generatedMarkerOverlaps markers =
  [ (first, second)
  | (first, firstStart, firstEnd) <- spans
  , (second, secondStart, _) <- spans
  , firstStart < secondStart
  , secondStart < firstEnd
  ]
 where
  keys = sortUnique [key | (_, marker) <- markers, Just key <- [startMarkerKey marker]]
  spans =
    [ (key, start, end)
    | key <- keys
    , [start] <- [[line | (line, marker) <- markers, startMarkerKey marker == Just key]]
    , [end] <- [[line | (line, marker) <- markers, endMarkerKey marker == Just key]]
    , start < end
    ]

generatedMarkersMalformed :: [(Int, Text)] -> Bool
generatedMarkersMalformed markers = any invalid keys
 where
  keys =
    sortUnique
      [ key
      | (_, marker) <- markers
      , key <- maybeToList (startMarkerKey marker) <> maybeToList (endMarkerKey marker)
      ]
  invalid key =
    case ( [line | (line, marker) <- markers, startMarkerKey marker == Just key]
         , [line | (line, marker) <- markers, endMarkerKey marker == Just key]
         ) of
      ([start], [end]) -> start >= end
      _ -> True

-- A marker is a standalone HTML comment at its actual source line. In
-- particular, a matching comment in a block quote must not authorize replacing
-- a same-named example elsewhere in the file.
generatedMarkerLines :: Text -> [(Int, Text)]
generatedMarkerLines contents = collect (commonmarkToNode [] [extTable] contents)
 where
  sourceLines = Text.lines contents
  collect (Node position nodeType children) =
    current position nodeType <> concatMap collect children
  current (Just position) (HTML_BLOCK html)
    | let index = startLine position - 1
    , index >= 0
    , sourceLine : _ <- drop index sourceLines
    , let marker = Text.strip sourceLine
    , marker == Text.strip html
    , isJust (startMarkerKey marker) || isJust (endMarkerKey marker) =
        [(index, marker)]
  current _ _ = []

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
