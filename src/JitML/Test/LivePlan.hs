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

-- | The single-command e2e plan. Sequences `helm dependency build chart` →
-- `pulumi up` (ephemeral Kind) → `npx playwright test` → `pulumi destroy` →
-- `pulumi stack rm`; local stanzas validate the typed order while explicit
-- live commands execute the real stack.
liveE2EPlan :: [LivePlanStep]
liveE2EPlan =
  [ LivePlanStep "helm-dependency-build" (helmDependencyBuildSubprocess "chart")
  , LivePlanStep "pulumi-up" (subprocess "pulumi" ["up", "--yes", "--cwd", "infra/pulumi"])
  , LivePlanStep "playwright" (subprocess "npx" ["playwright", "test"])
  , LivePlanStep "pulumi-destroy" (subprocess "pulumi" ["destroy", "--yes", "--cwd", "infra/pulumi"])
  , LivePlanStep
      "pulumi-stack-rm"
      (subprocess "pulumi" ["stack", "rm", "--yes", "--cwd", "infra/pulumi"])
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
