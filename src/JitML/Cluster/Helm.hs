{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Helm
  ( HelmPhase (..)
  , HelmRelease (..)
  , dependencyPackages
  , helmDependencyBuildSubprocess
  , helmInstallSubprocess
  , helmInstallSubprocessForEdgePort
  , helmInstallSubprocessForEdgePortNoWait
  , helmInstallSubprocessForSubstrate
  , helmPhasedRolloutPlan
  , kindCreateKubeconfigPath
  , kindCreateSubprocess
  , kindDeleteSubprocess
  , kindGetClustersSubprocess
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
-- non-Helm Docker build / Kind image-load phase between the registry and the
-- final workload releases: the registry must be serving before any image is
-- pushed to it.
data HelmPhase
  = RegistryPhase
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
  [ -- MinIO first: it provides the S3 backend and the bucket the registry
    -- stores layers in, so the registry cannot serve before it is up. The
    -- registry itself is a template in this chart rather than a dependency
    -- release, so it needs no entry here.
    HelmRelease "minio" "minio" RegistryPhase (Just "minio-14.8.5.tgz") (Just "values/minio.yaml")
  , -- The registry is a repo-owned local chart rather than a dependency
    -- subchart, and it installs after MinIO because its S3 backend is the
    -- bucket MinIO provisions.
    HelmRelease "registry" "registry" RegistryPhase Nothing Nothing
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
  helmInstallSubprocessWith True []

helmInstallSubprocessForSubstrate :: Substrate -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessForSubstrate substrate =
  helmInstallSubprocessForEdgePort substrate (substrateEdgePort substrate)

helmInstallSubprocessForEdgePort :: Substrate -> Int -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessForEdgePort substrate edgePort =
  helmInstallSubprocessWith
    True
    [ "--set"
    , "substrate=" <> renderSubstrate substrate
    , "--set"
    , "edgePort=" <> Text.pack (show edgePort)
    ]

-- | Apply a repo-owned app release without waiting on its existing Deployment.
-- Bootstrap loads mutable local tags immediately before this command, then its
-- typed executor reconciles pod image identities and performs explicit rollout
-- and readiness gates. Waiting here could deadlock on the stale pod that the
-- subsequent same-tag reconcile is responsible for replacing.
helmInstallSubprocessForEdgePortNoWait
  :: Substrate
  -> Int
  -> HelmRelease
  -> FilePath
  -> Subprocess
helmInstallSubprocessForEdgePortNoWait substrate edgePort =
  helmInstallSubprocessWith
    False
    [ "--set"
    , "substrate=" <> renderSubstrate substrate
    , "--set"
    , "edgePort=" <> Text.pack (show edgePort)
    ]

helmInstallSubprocessWith :: Bool -> [Text] -> HelmRelease -> FilePath -> Subprocess
helmInstallSubprocessWith waitForReady extraArgs release chartPath =
  subprocess
    "helm"
    ( [ "upgrade"
      , "--install"
      , releaseName release
      , chartReference release chartPath
      , "--namespace"
      , "platform"
      , "--create-namespace"
      , "--kubeconfig"
      , "./.build/jitml.kubeconfig"
      ]
        <> waitArgs
        <> valuesArgs release chartPath
        <> extraArgs
    )
 where
  waitArgs
    | waitForReady = ["--wait", "--timeout=900s"]
    | otherwise = ["--timeout=900s"]

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

-- | Typed Kind-cluster presence probe used by the live bootstrap executor
-- before it decides whether the create step is necessary. Keeping the probe
-- separate from @kind create cluster@ lets a retained matching cluster export
-- its kubeconfig and continue through the idempotent rollout.
kindGetClustersSubprocess :: Subprocess
kindGetClustersSubprocess =
  subprocess "kind" ["get", "clusters"]

-- | Sprint 2.9 — typed @kind delete cluster@. Replaces the prior @sh -c@
-- existence-check + delete; @kind delete@ on a missing cluster errors, which
-- the typed rollout surfaces directly.
kindDeleteSubprocess :: Substrate -> Subprocess
kindDeleteSubprocess substrate =
  subprocess
    "kind"
    ["delete", "cluster", "--name", substrateClusterName substrate]
