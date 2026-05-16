{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.LivePlan
  ( LivePlanStep (..)
  , liveE2EPlan
  , renderLivePlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cluster.Helm (helmDependencyBuildSubprocess)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data LivePlanStep = LivePlanStep
  { livePlanStepName :: Text
  , livePlanStepCommand :: Subprocess
  }
  deriving stock (Eq, Show)

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

renderLivePlan :: [LivePlanStep] -> Text
renderLivePlan =
  Text.unlines . fmap renderStep
 where
  renderStep step =
    livePlanStepName step <> ": " <> renderSubprocess (livePlanStepCommand step)
