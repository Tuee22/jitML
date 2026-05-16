{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Helm
  ( helmDependencyBuildSubprocess
  , renderHelmDependencyBuildPlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)

helmDependencyBuildSubprocess :: FilePath -> Subprocess
helmDependencyBuildSubprocess chartPath =
  subprocess "helm" ["dependency", "build", Text.pack chartPath]

renderHelmDependencyBuildPlan :: FilePath -> Text
renderHelmDependencyBuildPlan =
  renderSubprocess . helmDependencyBuildSubprocess
