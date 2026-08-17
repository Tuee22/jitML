{-# LANGUAGE OverloadedStrings #-}

-- | Execution-path fail-open scan.
--
-- A /fail-open wildcard/ is a catch-all branch on the execution path whose
-- right-hand side is a vacuously successful value: an empty list, 'False',
-- zero, 'mempty', a unit action, or — in rendered native source — a
-- @switch@ @default:@ label that only @break;@s. Such a branch turns an
-- unhandled operator into a silent no-op instead of a typed failure, which
-- the hardware-native determinism contract forbids on the execution path.
--
-- The scan is scoped to the execution path — the JIT source renderers, the
-- engine dispatch surface, and the numerical execution modules — and is
-- zero-tolerance for /new/ sites. Sites that already exist when the rule
-- lands are enumerated in 'failOpenPendingRegistry' together with the sprint
-- that owns closing them; the registry is exact, so removing a site without
-- updating the registry is also a finding.
module JitML.Lint.FailOpen
  ( FailOpenForm (..)
  , FailOpenSite (..)
  , PendingFailOpen (..)
  , checkFailOpenWildcards
  , executionPathRoots
  , failOpenFormKey
  , failOpenPendingRegistry
  , isExecutionPathSource
  , renderFailOpenForm
  , scanFailOpenSites
  )
where

import Data.List (isPrefixOf, isSuffixOf, sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath qualified as FilePath

import JitML.Lint.Stack.Types (LintFinding (..))

-- | The shape of a fail-open catch-all.
data FailOpenForm
  = -- | @_ -> []@
    WildcardEmptyList
  | -- | @_ -> False@
    WildcardFalse
  | -- | @_ -> 0@
    WildcardZero
  | -- | @_ -> mempty@
    WildcardMempty
  | -- | @_ -> pure ()@
    WildcardUnitAction
  | -- | Rendered native @default:@ whose only statement is @break;@
    RenderedSwitchDefaultBreak
  deriving stock (Eq, Ord, Show)

-- | One detected fail-open site.
data FailOpenSite = FailOpenSite
  { sitePath :: FilePath
  , siteForm :: FailOpenForm
  , siteLine :: Int
  }
  deriving stock (Eq, Ord, Show)

-- | A fail-open site that predates this rule, with the sprint that owns it.
data PendingFailOpen = PendingFailOpen
  { pendingPath :: FilePath
  , pendingForm :: FailOpenForm
  , pendingCount :: Int
  , pendingOwningSprint :: Text
  }
  deriving stock (Eq, Show)

-- | Source roots that constitute the execution path: JIT source renderers,
-- engine dispatch, and numerical execution.
executionPathRoots :: [FilePath]
executionPathRoots =
  [ "src/JitML/Codegen"
  , "src/JitML/Engines"
  , "src/JitML/Numerics"
  ]

-- | Is this path an execution-path Haskell source file?
isExecutionPathSource :: FilePath -> Bool
isExecutionPathSource path =
  ".hs" `isSuffixOf` path
    && any (\root -> (root <> "/") `isPrefixOf` path) executionPathRoots

-- | Fail-open sites that predate this rule. Each entry names the sprint whose
-- @### Remaining Work@ owns closing it; when that sprint closes, its entry is
-- deleted and the scan proves the site is gone.
-- Sprint `241.1` closed the three sites this registry was created with: the
-- rendered @jitml_op_train@ @default: break;@ (the entry now returns a non-zero
-- executed-opcode status), and the @_ -> False@ / @_ -> 0@ wildcards that
-- decided whether an operator had a device kernel and which evidence code it
-- reported (both replaced by the total 'JitML.Numerics.LayerGraphDevice.lowerLayerOp').
-- The registry is exact, so it is now empty and the scan is zero-tolerance.
failOpenPendingRegistry :: [PendingFailOpen]
failOpenPendingRegistry = []

-- | Stable lint-key fragment for a form.
failOpenFormKey :: FailOpenForm -> Text
failOpenFormKey form =
  case form of
    WildcardEmptyList -> "empty-list"
    WildcardFalse -> "false"
    WildcardZero -> "zero"
    WildcardMempty -> "mempty"
    WildcardUnitAction -> "unit-action"
    RenderedSwitchDefaultBreak -> "switch-default-break"

-- | Human-readable rendering of a form.
renderFailOpenForm :: FailOpenForm -> Text
renderFailOpenForm form =
  case form of
    WildcardEmptyList -> "_ -> []"
    WildcardFalse -> "_ -> False"
    WildcardZero -> "_ -> 0"
    WildcardMempty -> "_ -> mempty"
    WildcardUnitAction -> "_ -> pure ()"
    RenderedSwitchDefaultBreak -> "rendered `default:` followed only by `break;`"

-- | Scan one source file for fail-open sites.
scanFailOpenSites :: FilePath -> Text -> [FailOpenSite]
scanFailOpenSites path content =
  wildcardSites <> switchDefaultSites
 where
  numbered = zip [1 :: Int ..] (Text.lines content)

  wildcardSites =
    [ FailOpenSite path form line
    | (line, raw) <- numbered
    , Just form <- [wildcardForm (Text.strip raw)]
    ]

  switchDefaultSites =
    [ FailOpenSite path RenderedSwitchDefaultBreak line
    | ((line, raw), (_, next)) <- adjacentPairs numbered
    , isRenderedSwitchDefault (Text.strip raw)
    , isRenderedBreak (Text.strip next)
    ]

-- | Every adjacent pair of a list, without a partial `tail`.
adjacentPairs :: [a] -> [(a, a)]
adjacentPairs values =
  case values of
    [] -> []
    (_ : rest) -> zip values rest

-- | Classify a stripped Haskell source line as a fail-open catch-all.
wildcardForm :: Text -> Maybe FailOpenForm
wildcardForm stripped =
  case Text.stripPrefix "_ ->" stripped of
    Nothing -> Nothing
    Just rest ->
      lookup
        (Text.strip rest)
        [ ("[]", WildcardEmptyList)
        , ("False", WildcardFalse)
        , ("0", WildcardZero)
        , ("mempty", WildcardMempty)
        , ("pure ()", WildcardUnitAction)
        ]

-- | Is this line a rendered native @switch@ @default:@ label? Rendered source
-- lives inside Haskell string literals, so the label is matched inside quotes.
isRenderedSwitchDefault :: Text -> Bool
isRenderedSwitchDefault stripped =
  "default:" `Text.isSuffixOf` Text.strip (Text.dropWhileEnd (== '"') stripped)

-- | Is this line a rendered native @break;@ statement?
isRenderedBreak :: Text -> Bool
isRenderedBreak stripped =
  "break;" `Text.isSuffixOf` Text.strip (Text.dropWhileEnd (== '"') stripped)

-- | Run the execution-path fail-open scan and reconcile it against the
-- pending registry.
checkFailOpenWildcards :: IO [LintFinding]
checkFailOpenWildcards = do
  sources <- executionPathSources
  detected <- concat <$> traverse scanSource (sort sources)
  pure (newSiteFindings detected <> staleRegistrationFindings detected)
 where
  scanSource path = scanFailOpenSites path <$> Text.IO.readFile path

newSiteFindings :: [FailOpenSite] -> [LintFinding]
newSiteFindings detected =
  [ newSiteFinding site
  | (site, ordinal) <- withOrdinals detected
  , ordinal > registeredCount (sitePath site) (siteForm site)
  ]

staleRegistrationFindings :: [FailOpenSite] -> [LintFinding]
staleRegistrationFindings detected =
  [ staleRegistrationFinding pending observed
  | pending <- failOpenPendingRegistry
  , let observed =
          length
            [ ()
            | site <- detected
            , sitePath site == pendingPath pending
            , siteForm site == pendingForm pending
            ]
  , observed < pendingCount pending
  ]

-- | Pair each site with its 1-based ordinal among sites of the same
-- (path, form), so the registry can hold an exact count rather than a
-- line number that moves whenever the file is edited.
withOrdinals :: [FailOpenSite] -> [(FailOpenSite, Int)]
withOrdinals = go []
 where
  go _ [] = []
  go seen (site : rest) =
    let key = (sitePath site, siteForm site)
        ordinal = 1 + length (filter (== key) seen)
     in (site, ordinal) : go (key : seen) rest

registeredCount :: FilePath -> FailOpenForm -> Int
registeredCount path form =
  sum
    [ pendingCount pending
    | pending <- failOpenPendingRegistry
    , pendingPath pending == path
    , pendingForm pending == form
    ]

newSiteFinding :: FailOpenSite -> LintFinding
newSiteFinding site =
  LintFinding
    { findingPath = sitePath site
    , findingKey = "execution.fail-open." <> failOpenFormKey (siteForm site)
    , findingMessage =
        "fail-open catch-all on the execution path at line "
          <> Text.pack (show (siteLine site))
          <> ": "
          <> renderFailOpenForm (siteForm site)
    , findingRemedy =
        Text.unlines
          [ "return a typed failure from the catch-all instead of a vacuous value"
          , "the execution path must not degrade an unhandled operator to a silent no-op"
          ]
    }

staleRegistrationFinding :: PendingFailOpen -> Int -> LintFinding
staleRegistrationFinding pending observed =
  LintFinding
    { findingPath = pendingPath pending
    , findingKey = "execution.fail-open.stale-registration"
    , findingMessage =
        "pending fail-open registry expects "
          <> Text.pack (show (pendingCount pending))
          <> " × `"
          <> renderFailOpenForm (pendingForm pending)
          <> "` but the scan found "
          <> Text.pack (show observed)
    , findingRemedy =
        "drop the closed entry from `failOpenPendingRegistry` in src/JitML/Lint/FailOpen.hs (owner: sprint "
          <> pendingOwningSprint pending
          <> ")"
    }

executionPathSources :: IO [FilePath]
executionPathSources =
  concat <$> traverse listHaskellSources executionPathRoots

listHaskellSources :: FilePath -> IO [FilePath]
listHaskellSources root = do
  exists <- doesDirectoryExist root
  if not exists
    then pure []
    else do
      entries <- listDirectory root
      concat <$> traverse (descend root) entries

descend :: FilePath -> FilePath -> IO [FilePath]
descend root entry = do
  let path = root FilePath.</> entry
  isDirectory <- doesDirectoryExist path
  if isDirectory
    then listHaskellSources path
    else pure [path | ".hs" `isSuffixOf` path]
