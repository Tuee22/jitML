{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.LivePlan
  ( LivePlanStep (..)
  , liveE2EPlan
  , livePhasedClusterPlan
  , renderLivePlan
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
import JitML.Substrate (Substrate)

data LivePlanStep = LivePlanStep
  { livePlanStepName :: Text
  , livePlanStepCommand :: Subprocess
  }
  deriving stock (Eq, Show)

-- | The single-command e2e plan for the ephemeral-cluster infrastructure
-- stanza. Sequences `helm dependency build chart` → `jitml bootstrap`
-- (ephemeral Kind cluster + phased Helm rollout) → `npx playwright test` →
-- `jitml cluster down` (always-teardown); local stanzas validate the typed
-- order while the explicit live driver executes the real stack.
liveE2EPlan :: [LivePlanStep]
liveE2EPlan =
  [ LivePlanStep "helm-dependency-build" (helmDependencyBuildSubprocess "chart")
  , LivePlanStep "bootstrap" (subprocess "jitml" ["bootstrap", "--linux-cpu"])
  , LivePlanStep "playwright" (subprocess "npx" ["playwright", "test"])
  , LivePlanStep "cluster-down" (subprocess "jitml" ["cluster", "down"])
  ]

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
