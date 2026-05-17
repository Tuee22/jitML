{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Helm
  ( HelmPhase (..)
  , HelmRelease (..)
  , helmDependencyBuildSubprocess
  , helmInstallSubprocess
  , helmPhasedRolloutPlan
  , kindCreateSubprocess
  , phasedReleases
  , renderHelmDependencyBuildPlan
  , renderHelmPhasedRolloutPlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate, renderSubstrate)

helmDependencyBuildSubprocess :: FilePath -> Subprocess
helmDependencyBuildSubprocess chartPath =
  subprocess "helm" ["dependency", "build", Text.pack chartPath]

renderHelmDependencyBuildPlan :: FilePath -> Text
renderHelmDependencyBuildPlan =
  renderSubprocess . helmDependencyBuildSubprocess

-- | The phased rollout the cluster reconciler walks: Harbor first (so later
-- pulls succeed), then the rest of the platform services, then mirror/build
-- of the jitml images into Harbor, then the final per-substrate services
-- (jitml-service + jitml-demo + observability).
data HelmPhase
  = HarborPhase
  | PlatformPhase
  | MirrorBuildPhase
  | FinalPhase
  deriving stock (Eq, Show)

data HelmRelease = HelmRelease
  { releaseName :: Text
  , releaseChart :: Text
  , releasePhase :: HelmPhase
  }
  deriving stock (Eq, Show)

phasedReleases :: [HelmRelease]
phasedReleases =
  [ HelmRelease "harbor" "harbor" HarborPhase
  , HelmRelease "harbor-pg" "pg-operator" HarborPhase
  , HelmRelease "minio" "minio" PlatformPhase
  , HelmRelease "pulsar" "pulsar" PlatformPhase
  , HelmRelease "kube-prometheus-stack" "kube-prometheus-stack" PlatformPhase
  , HelmRelease "tensorboard" "tensorboard" PlatformPhase
  , HelmRelease "jitml-mirror" "jitml-images" MirrorBuildPhase
  , HelmRelease "jitml-service" "jitml-service" FinalPhase
  , HelmRelease "jitml-demo" "jitml-demo" FinalPhase
  , HelmRelease "envoy-gateway" "envoy-gateway" FinalPhase
  ]

helmInstallSubprocess :: HelmRelease -> FilePath -> Subprocess
helmInstallSubprocess release chartPath =
  subprocess
    "helm"
    [ "upgrade"
    , "--install"
    , releaseName release
    , Text.pack chartPath <> "/charts/" <> releaseChart release
    , "--namespace"
    , "platform"
    , "--create-namespace"
    , "--wait"
    , "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    ]

helmPhasedRolloutPlan :: FilePath -> [Subprocess]
helmPhasedRolloutPlan chartPath =
  helmDependencyBuildSubprocess chartPath
    : [helmInstallSubprocess release chartPath | release <- phasedReleases]

renderHelmPhasedRolloutPlan :: FilePath -> Text
renderHelmPhasedRolloutPlan chartPath =
  Text.unlines (fmap renderSubprocess (helmPhasedRolloutPlan chartPath))

kindCreateSubprocess :: Substrate -> FilePath -> Subprocess
kindCreateSubprocess substrate kindConfigPath =
  subprocess
    "kind"
    [ "create"
    , "cluster"
    , "--name"
    , "jitml-" <> renderSubstrate substrate
    , "--config"
    , Text.pack kindConfigPath
    , "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    ]
