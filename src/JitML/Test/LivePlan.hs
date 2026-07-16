{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.LivePlan
  ( LivePlanStep (..)
  , LiveResourceOwnership (..)
  , ScopedLivePlan (..)
  , flattenScopedLivePlan
  , liveE2EPlan
  , liveE2EPlanFor
  , scopedLiveE2EPlanFor
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

scopedLiveE2EPlanFor :: LiveResourceOwnership -> Substrate -> ScopedLivePlan
scopedLiveE2EPlanFor ownership substrate =
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
                , "-w"
                , "/work"
                , "-e"
                , "JITML_SUBSTRATE=" <> renderSubstrate substrate
                , "-e"
                , "PLAYWRIGHT_TEST_RESULTS_DIR=/tmp/jitml-playwright-test-results"
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
                    , ">/tmp/jitml-playwright-install.log"
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
