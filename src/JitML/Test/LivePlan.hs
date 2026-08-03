{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.LivePlan
  ( BrowserEvidencePlanPaths (..)
  , LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  , defaultBrowserEvidencePlanPaths
  , flattenScopedLivePlan
  , liveE2EPlan
  , liveE2EPlanFor
  , liveE2EPlanForBrowserEvidence
  , scopedLiveE2EPlanFor
  , scopedLiveE2EPlanForBrowserEvidence
  , livePhasedClusterPlan
  , renderLivePlan
  , renderScopedLivePlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Bootstrap (livePhasedRolloutSubprocesses)
import JitML.Cluster.Helm
  ( helmDependencyBuildSubprocess
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate (..), renderSubstrate)

data LivePlanStep = LivePlanStep
  { livePlanStepName :: Text
  , livePlanStepCommand :: Subprocess
  }
  deriving stock (Eq, Show)

data LiveResourceOwnership
  = OwnedEphemeralCluster
  | BorrowedLiveCluster
  deriving stock (Eq, Show)

-- | Host-visible paths for the browser evidence subprocess.  The catalogue and
-- exact cluster publication are mounted as individual read-only files.  The
-- separate browser scope is writable only so the reporter can consume and
-- unlink its fresh signing key, write its atomic result journal, and retain
-- Playwright diagnostics.  It never contains the ProductScenario journal,
-- checkpoint root, executable challenge, or any Phase 261 signing capability.
data BrowserEvidencePlanPaths = BrowserEvidencePlanPaths
  { browserEvidenceCataloguePath :: !FilePath
  , browserEvidencePublicationPath :: !FilePath
  , browserEvidenceScopePath :: !FilePath
  }
  deriving stock (Eq, Show)

-- | Structural/default paths used by plan rendering.  The live command runner
-- supplies a fresh command-owned scope through
-- 'scopedLiveE2EPlanForBrowserEvidence'.
defaultBrowserEvidencePlanPaths :: BrowserEvidencePlanPaths
defaultBrowserEvidencePlanPaths =
  BrowserEvidencePlanPaths
    { browserEvidenceCataloguePath = "./.build/runtime/browser-catalogue-input.json"
    , browserEvidencePublicationPath = "./.build/runtime/cluster-publication.json"
    , browserEvidenceScopePath = "./.build/runtime/browser-evidence"
    }

-- | Resource phases stay distinct so the IO runner can bracket acquire/use/
-- release.  Flattening exists only for renderer/backward compatibility; an
-- interpreter must not treat release as an ordinary tail step that disappears
-- after a body failure.
data ScopedLivePlan = ScopedLivePlan
  { scopedLivePlanOwnership :: LiveResourceOwnership
  , scopedLivePlanAcquire :: [LivePlanStep]
  , scopedLivePlanBody :: [LivePlanStep]
  , scopedLivePlanRelease :: [LivePlanStep]
  }
  deriving stock (Eq, Show)

-- | The substrate-parametrized e2e plan for the live-cluster infrastructure
-- stanza. Sequences `helm dependency build chart` → `jitml bootstrap`
-- (ephemeral Kind cluster + phased Helm rollout) → substrate-bound Playwright
-- in the pinned Playwright browser image from a read-only repo mount →
-- `jitml cluster down`; local stanzas validate the typed order while the
-- explicit live driver selects or bootstraps the live stack.
liveE2EPlan :: [LivePlanStep]
liveE2EPlan =
  liveE2EPlanFor LinuxCPU

liveE2EPlanFor :: Substrate -> [LivePlanStep]
liveE2EPlanFor substrate =
  flattenScopedLivePlan (scopedLiveE2EPlanFor OwnedEphemeralCluster substrate)

liveE2EPlanForBrowserEvidence
  :: BrowserEvidencePlanPaths
  -> Substrate
  -> [LivePlanStep]
liveE2EPlanForBrowserEvidence paths substrate =
  flattenScopedLivePlan
    (scopedLiveE2EPlanForBrowserEvidence paths OwnedEphemeralCluster substrate)

scopedLiveE2EPlanFor :: LiveResourceOwnership -> Substrate -> ScopedLivePlan
scopedLiveE2EPlanFor =
  scopedLiveE2EPlanForBrowserEvidence defaultBrowserEvidencePlanPaths

scopedLiveE2EPlanForBrowserEvidence
  :: BrowserEvidencePlanPaths
  -> LiveResourceOwnership
  -> Substrate
  -> ScopedLivePlan
scopedLiveE2EPlanForBrowserEvidence evidencePaths ownership substrate =
  ScopedLivePlan
    { scopedLivePlanOwnership = ownership
    , scopedLivePlanAcquire =
        case ownership of
          OwnedEphemeralCluster ->
            [ LivePlanStep "helm-dependency-build" (helmDependencyBuildSubprocess "chart")
            , LivePlanStep
                "bootstrap"
                (subprocess "jitml" ["bootstrap", "--" <> renderSubstrate substrate])
            ]
          BorrowedLiveCluster -> []
    , scopedLivePlanBody =
        [ LivePlanStep
            "playwright"
            ( subprocess
                "docker"
                [ "run"
                , "--rm"
                , "--network"
                , "host"
                , "-v"
                , ".:/work:ro"
                , "-v"
                , Text.pack (browserEvidenceCataloguePath evidencePaths)
                    <> ":/jitml-browser-input/catalogue.json:ro"
                , "-v"
                , Text.pack (browserEvidencePublicationPath evidencePaths)
                    <> ":/jitml-browser-input/cluster-publication.json:ro"
                , "-v"
                , Text.pack (browserEvidenceScopePath evidencePaths)
                    <> ":/jitml-browser-scope:rw"
                , "-w"
                , "/work"
                , "-e"
                , "JITML_SUBSTRATE=" <> renderSubstrate substrate
                , "-e"
                , "JITML_BROWSER_CATALOGUE_PATH=/jitml-browser-input/catalogue.json"
                , "-e"
                , "JITML_BROWSER_PUBLICATION_PATH=/jitml-browser-input/cluster-publication.json"
                , "-e"
                , "JITML_BROWSER_RESULT_PATH=/jitml-browser-scope/result.json"
                , "-e"
                , "JITML_BROWSER_RESULT_KEY_FILE=/jitml-browser-scope/result.key"
                , "-e"
                , "PLAYWRIGHT_TEST_RESULTS_DIR=/jitml-browser-scope/playwright-test-results"
                , "mcr.microsoft.com/playwright:v1.49.1-noble"
                , "sh"
                , "-lc"
                , Text.unwords
                    [ "npm_config_update_notifier=false"
                    , "npm install"
                    , "--prefix /tmp/jitml-playwright"
                    , "--package-lock=false"
                    , "--no-audit"
                    , "--no-fund"
                    , "--loglevel=error"
                    , "@playwright/test@1.49.1"
                    , ">/jitml-browser-scope/npm-install.log"
                    , "2>&1"
                    , "&&"
                    , "NODE_PATH=/tmp/jitml-playwright/node_modules"
                    , "/tmp/jitml-playwright/node_modules/.bin/playwright"
                    , "test"
                    , "--config"
                    , "playwright/playwright.config.ts"
                    ]
                ]
            )
        ]
    , scopedLivePlanRelease =
        case ownership of
          OwnedEphemeralCluster ->
            [LivePlanStep "cluster-down" (subprocess "jitml" ["cluster", "down"])]
          BorrowedLiveCluster -> []
    }

flattenScopedLivePlan :: ScopedLivePlan -> [LivePlanStep]
flattenScopedLivePlan plan =
  scopedLivePlanAcquire plan
    <> scopedLivePlanBody plan
    <> scopedLivePlanRelease plan

-- | The phased cluster plan emitted by the same typed subprocess list used by
-- `jitml bootstrap`, including Helm releases and the Docker build / explicit
-- Kind image-load phase.
livePhasedClusterPlan :: Substrate -> FilePath -> [LivePlanStep]
livePhasedClusterPlan substrate chartPath =
  fmap
    ( \(index, command) ->
        LivePlanStep ("cluster-step-" <> Text.pack (show index)) command
    )
    (zip [(1 :: Int) ..] (livePhasedRolloutSubprocesses substrate chartPath))

renderLivePlan :: [LivePlanStep] -> Text
renderLivePlan =
  Text.unlines . fmap renderStep
 where
  renderStep step =
    livePlanStepName step <> ": " <> renderSubprocess (livePlanStepCommand step)

renderScopedLivePlan :: ScopedLivePlan -> Text
renderScopedLivePlan plan =
  Text.unlines
    [ "ownership: " <> renderOwnership (scopedLivePlanOwnership plan)
    , "acquire:"
    , renderLivePlan (scopedLivePlanAcquire plan)
    , "body:"
    , renderLivePlan (scopedLivePlanBody plan)
    , "release:"
    , renderLivePlan (scopedLivePlanRelease plan)
    ]
 where
  renderOwnership OwnedEphemeralCluster = "owned-ephemeral-cluster"
  renderOwnership BorrowedLiveCluster = "borrowed-live-cluster"
