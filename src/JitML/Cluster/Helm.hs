{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Helm
  ( HelmPhase (..)
  , HelmRelease (..)
  , dependencyPackages
  , helmDependencyBuildSubprocess
  , helmInstallSubprocess
  , helmInstallSubprocessForEdgePort
  , helmInstallSubprocessForSubstrate
  , helmPhasedRolloutPlan
  , kindCreateKubeconfigPath
  , kindCreateSubprocess
  , kindDeleteSubprocess
  , phasedReleases
  , renderHelmDependencyBuildPlan
  , renderHelmPhasedRolloutPlan
  )
where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import System.FilePath ((</>))

import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate, renderSubstrate, substrateClusterName, substrateEdgePort)

-- | Sprint 2.9 — typed @helm dependency build@. The previous @sh -c@ short-
-- circuited when every subchart @.tgz@ was already present in @chart/charts/@;
-- helm's own @dependency build@ is idempotent (a fast no-op when the cache is
-- up to date), so the typed single command preserves the user-visible
-- behavior without embedding shell.
helmDependencyBuildSubprocess :: FilePath -> Subprocess
helmDependencyBuildSubprocess chartPath =
  subprocess "helm" ["dependency", "build", Text.pack chartPath]

renderHelmDependencyBuildPlan :: FilePath -> Text
renderHelmDependencyBuildPlan chartPath =
  "helm dependency build " <> Text.pack chartPath

-- | Sprint 2.9 — the subchart packages 'helm dependency build' would download
-- into @chart/charts/@. Used by 'JitML.Bootstrap.ensureHelmDependenciesIO' to
-- decide whether the build step is needed: when every @.tgz@ already exists,
-- the bootstrap reconciler skips the dep-build call (which would otherwise
-- fail in a fresh container that has no @helm repo@ definitions yet).
dependencyPackages :: [Text]
dependencyPackages =
  mapMaybe releasePackage phasedReleases

-- | Helm releases in the cluster reconciler. `JitML.Bootstrap` inserts the
-- non-Helm Docker build / Kind image-load phase between Harbor and the final
-- workload releases.
data HelmPhase
  = HarborPhase
  | PlatformPhase
  | FinalPhase
  deriving stock (Eq, Show)

data HelmRelease = HelmRelease
  { releaseName :: Text
  , releaseChart :: Text
  , releasePhase :: HelmPhase
  , releasePackage :: Maybe Text
  , releaseValuesFile :: Maybe FilePath
  }
  deriving stock (Eq, Show)

phasedReleases :: [HelmRelease]
phasedReleases =
  [ HelmRelease "harbor-pg" "pg-operator" HarborPhase (Just "pg-operator-2.5.1.tgz") Nothing
  , HelmRelease "minio" "minio" HarborPhase (Just "minio-14.8.5.tgz") (Just "values/minio.yaml")
  , HelmRelease "harbor" "harbor" HarborPhase (Just "harbor-1.16.2.tgz") (Just "values/harbor.yaml")
  , HelmRelease "pulsar" "pulsar" PlatformPhase (Just "pulsar-3.6.0.tgz") (Just "values/pulsar.yaml")
  , HelmRelease
      "kube-prometheus-stack"
      "kube-prometheus-stack"
      PlatformPhase
      (Just "kube-prometheus-stack-70.4.2.tgz")
      (Just "values/kube-prometheus-stack.yaml")
  , HelmRelease "tensorboard" "tensorboard" PlatformPhase Nothing Nothing
  , HelmRelease "jitml-service" "jitml-service" FinalPhase Nothing Nothing
  , HelmRelease "jitml-demo" "jitml-demo" FinalPhase Nothing Nothing
  , HelmRelease "envoy-gateway" "gateway-helm" FinalPhase (Just "gateway-helm-1.2.6.tgz") Nothing
  ]

helmInstallSubprocess :: HelmRelease -> FilePath -> Subprocess
helmInstallSubprocess =
  helmInstallSubprocessWith []

helmInstallSubprocessForSubstrate :: Substrate -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessForSubstrate substrate =
  helmInstallSubprocessForEdgePort substrate (substrateEdgePort substrate)

helmInstallSubprocessForEdgePort :: Substrate -> Int -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessForEdgePort substrate edgePort release =
  helmInstallSubprocessWith
    ( [ "--set"
      , "substrate=" <> renderSubstrate substrate
      , "--set"
      , "edgePort=" <> Text.pack (show edgePort)
      ]
        <> harborEdgeArgs edgePort release
    )
    release

helmInstallSubprocessWith :: [Text] -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessWith extraArgs release chartPath =
  subprocess
    "helm"
    ( [ "upgrade"
      , "--install"
      , releaseName release
      , chartReference release chartPath
      , "--namespace"
      , "platform"
      , "--create-namespace"
      , "--wait"
      , "--kubeconfig"
      , "./.build/jitml.kubeconfig"
      ]
        <> valuesArgs release chartPath
        <> extraArgs
    )

chartReference :: HelmRelease -> FilePath -> Text
chartReference release chartPath =
  case releasePackage release of
    Just package -> Text.pack chartPath <> "/charts/" <> package
    Nothing -> Text.pack chartPath <> "/local/" <> releaseChart release

valuesArgs :: HelmRelease -> FilePath -> [Text]
valuesArgs release chartPath =
  case releaseValuesFile release of
    Just valuesFile -> ["--values", Text.pack (chartPath </> valuesFile)]
    Nothing -> []

harborEdgeArgs :: Int -> HelmRelease -> [Text]
harborEdgeArgs edgePort release
  | releaseName release == "harbor" =
      [ "--set"
      , "expose.type=clusterIP"
      , "--set"
      , "expose.tls.enabled=false"
      , "--set-string"
      , "externalURL=http://127.0.0.1:" <> Text.pack (show edgePort)
      ]
  | otherwise = []

helmPhasedRolloutPlan :: FilePath -> [Subprocess]
helmPhasedRolloutPlan chartPath =
  helmDependencyBuildSubprocess chartPath
    : [helmInstallSubprocess release chartPath | release <- phasedReleases]

renderHelmPhasedRolloutPlan :: FilePath -> Text
renderHelmPhasedRolloutPlan chartPath =
  Text.unlines (fmap renderSubprocess (helmPhasedRolloutPlan chartPath))

kindCreateKubeconfigPath :: Substrate -> FilePath
kindCreateKubeconfigPath substrate =
  "/tmp/jitml-kind-create-" <> Text.unpack (renderSubstrate substrate) <> ".kubeconfig"

-- | Sprint 2.9 — typed @kind create cluster@. The previous @sh -c@ wrote a
-- temp kubeconfig, branched on @kind get clusters@ to either create or just
-- re-export, then copied to @./.build/jitml.kubeconfig@. The typed command now
-- asks Kind to write its create-time kubeconfig under @/tmp@; the live executor
-- captures @kind get kubeconfig@ and writes the repo-local kubeconfig itself so
-- Kind never has to lock a macOS bind-mounted @.build@ path.
kindCreateSubprocess :: Substrate -> FilePath -> Subprocess
kindCreateSubprocess substrate kindConfigPath =
  subprocess
    "kind"
    [ "create"
    , "cluster"
    , "--name"
    , substrateClusterName substrate
    , "--config"
    , Text.pack kindConfigPath
    , "--kubeconfig"
    , Text.pack (kindCreateKubeconfigPath substrate)
    ]

-- | Sprint 2.9 — typed @kind delete cluster@. Replaces the prior @sh -c@
-- existence-check + delete; @kind delete@ on a missing cluster errors, which
-- the typed rollout surfaces directly.
kindDeleteSubprocess :: Substrate -> Subprocess
kindDeleteSubprocess substrate =
  subprocess
    "kind"
    ["delete", "cluster", "--name", substrateClusterName substrate]
