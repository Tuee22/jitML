{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module JitML.Bootstrap
  ( AppPodImagePollDecision (..)
  , TopicStatsPollDecision (..)
  , LiveExecutionResult (..)
  , LiveStepFailure (..)
  , KindClusterPresence (..)
  , LiveKindAction (..)
  , appPodImageEvidenceMatchesLoadedImage
  , appPodImagePollDecision
  , appRolloutMatchesLoadedImage
  , bootstrapPlanSteps
  , cachedThirdPartyRolloutImages
  , hostBootConfigForPublication
  , kindPrepareStatefulPvSubprocesses
  , livePhasedRolloutSubprocesses
  , liveExecutePhasedRollout
  , materializeBootstrapFiles
  , materializeBootstrapFilesForPort
  , parseAppPodImageEvidence
  , parseContainerdImageListDigest
  , prepareLiveKindRecovery
  , publicReadyzSubprocessForPort
  , readExistingLivePublication
  , renderLiveStepFailure
  , resolveKindClusterPresence
  , selectLiveKindRecovery
  , selectLiveLease
  , topicStatsPollDecision
  , uniformImageId
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (mapConcurrently)
import Control.Monad (filterM, when)
import Data.Aeson
  ( FromJSON (..)
  , Value (..)
  , decode
  , eitherDecode
  , encode
  , object
  , withObject
  , (.!=)
  , (.:)
  , (.:?)
  , (.=)
  )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isHexDigit)
import Data.List (isPrefixOf, isSuffixOf, nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getHomeDirectory
  , listDirectory
  , removeFile
  , renameFile
  )
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))

import JitML.Cluster.DockerImage
  ( dockerBuildAndKindLoadPlan
  , dockerTagSubprocess
  , kindLoadDockerImageSubprocess
  )
import JitML.Cluster.EdgePort qualified as EdgePort
import JitML.Cluster.Gateway (renderEnvoyProxy, renderGateway, renderGatewayClass)
import JitML.Cluster.Helm
  ( dependencyPackages
  , helmDependencyBuildSubprocess
  , helmInstallSubprocessForEdgePort
  , helmInstallSubprocessForEdgePortNoWait
  , kindCreateKubeconfigPath
  , kindCreateSubprocess
  , kindGetClustersSubprocess
  , phasedReleases
  , releaseName
  , renderHelmDependencyBuildPlan
  )
import JitML.Cluster.Kind
  ( kindConfigForEdgePortAndWorkers
  , renderKindConfig
  , substrateKindNodeContainerNames
  )
import JitML.Cluster.PostgresRegistry
  ( PerconaPGCluster (..)
  , postgresRegistry
  , renderPerconaPGCluster
  )
import JitML.Cluster.Publication
  ( ClusterPublication (..)
  , defaultPublication
  , markPublicationLive
  , publicationHasLiveEvidence
  , publicationWithLeasedPort
  , requiredPublicationComponents
  )
import JitML.Cluster.PulsarBootstrap (runPulsarTopicCreatesIO)
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Cluster.Readiness (platformReadinessSubprocesses, runMinioBucketReadinessIO)
import JitML.Cluster.Readiness qualified as Readiness
import JitML.Cluster.ReconcileStamp
  ( LivePublicationObservation (..)
  , ReconcileDecision (..)
  , ReconcileEvidence (..)
  , ReconcileObservation (..)
  , ReconcileStamp (..)
  , classifyReconcileObservation
  , fingerprintWorkspace
  , mkReconcileStamp
  )
import JitML.Cluster.Resources
  ( ClusterResources
  , clusterNodeCapSubprocesses
  , defaultClusterResources
  , loadClusterResourcesOrDefault
  , renderClusterResourcesDhall
  , validateEngineTopology
  , validateLocalPlatformTopology
  , workerCount
  )
import JitML.Cluster.Storage
  ( ManualPV (..)
  , manualPVs
  , manualPVsFor
  , pvLocalDataPath
  , pvNodeDataPath
  , renderManualPV
  , renderStorageClass
  )
import JitML.Observability.Grafana qualified as Grafana
import JitML.Routes (Route (..), renderHTTPRoute, routeRegistry)
import JitML.Service.BootConfig
  ( BootConfig (..)
  , Residency (..)
  , defaultBootConfig
  , renderBootConfigDhall
  )
import JitML.Service.ConfigMap
  ( renderServiceConfigMaps
  , renderServiceDeployment
  , renderServiceRBAC
  , renderServiceValues
  )
import JitML.Service.LiveConfig (defaultLiveConfig, renderLiveConfigDhall)
import JitML.Sub.Outcome
  ( ProcessFailure
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , renderProcessFailure
  , renderProcessOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess
  ( Subprocess
  , subprocess
  , subprocessArguments
  , subprocessPath
  , subprocessWithStdin
  )
import JitML.Substrate
  ( Substrate (..)
  , renderSubstrate
  , substrateClusterName
  , substrateEdgePort
  , substrateHasClusterCompute
  )

bootstrapPlanSteps :: Substrate -> [Text]
bootstrapPlanSteps substrate =
  [ "reconcile prerequisite graph for cluster"
  , "render kind/cluster-" <> renderSubstrate substrate <> ".yaml"
  , "prepare Helm dependencies with " <> renderHelmDependencyBuildPlan "chart"
  , "create/export Kind kubeconfig and copy it to ./.build/jitml.kubeconfig"
  , "raise Kind-node inotify caps for multi-cluster host readiness"
  , "prepare substrate-specific stateful PV storage"
  , "apply jitml-manual StorageClass and manual PVs"
  , "install MinIO and provision the image-registry bucket"
  , "build jitml:local, retag jitml-demo:local, and load them into Kind"
  , "install Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
  , "reconcile app pods to the loaded image identities"
  , "prove Engine, Coordinator, and public edge readiness"
  , "write ./.build/runtime/cluster-publication.json"
  ]

materializeBootstrapFiles :: FilePath -> Substrate -> IO Bool
materializeBootstrapFiles root substrate =
  materializeBootstrapFilesForPort root substrate (substrateEdgePort substrate)

-- | Materialize every edge-coordinate-bearing input from one authoritative
-- port. The public file-only materializer uses the substrate default, while a
-- live retained-cluster reconcile supplies the port recovered from its
-- publication before checking whether any input changed.
materializeBootstrapFilesForPort :: FilePath -> Substrate -> Int -> IO Bool
materializeBootstrapFilesForPort root substrate edgePort = do
  let buildRoot = root </> ".build"
      runtimeRoot = buildRoot </> "runtime"
      clusterConfRoot = buildRoot </> "conf" </> "cluster"
      hostConfRoot = buildRoot </> "conf" </> "host"
      kindRoot = root </> "kind"
      chartRoot = root </> "chart"
      chartTemplatesRoot = chartRoot </> "templates"
  createDirectoryIfMissing True kindRoot
  createDirectoryIfMissing True chartRoot
  createDirectoryIfMissing True chartTemplatesRoot
  createDirectoryIfMissing True runtimeRoot
  createDirectoryIfMissing True clusterConfRoot
  createDirectoryIfMissing True hostConfRoot
  clusterResources <- loadClusterResourcesOrDefault root
  case validateLocalPlatformTopology clusterResources of
    Left reason -> ioError (userError (Text.unpack reason))
    Right () -> pure ()
  case validateEngineTopology clusterResources of
    Left reason -> ioError (userError (Text.unpack reason))
    Right () -> pure ()
  results <-
    sequence
      [ writeTextFileIfChanged
          (kindRoot </> "cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml")
          ( renderKindConfig
              (kindConfigForEdgePortAndWorkers substrate edgePort (workerCount clusterResources))
          )
      , writeTextFileIfChanged (chartTemplatesRoot </> "storageclass-jitml-manual.yaml") renderStorageClass
      , writeTextFileIfChanged (chartTemplatesRoot </> "gatewayclass-jitml.yaml") renderGatewayClass
      , writeTextFileIfChanged
          (chartTemplatesRoot </> "gateway-jitml-edge.yaml")
          (renderGateway edgePort)
      , writeTextFileIfChanged (chartTemplatesRoot </> "envoyproxy-jitml-edge.yaml") $
          renderEnvoyProxy edgePort
      ]
  let configuredManualPVs = manualPVsFor clusterResources
  pvResults <- traverse (materializePv chartTemplatesRoot) configuredManualPVs
  -- Sprint 3.2 (reopened): when the manualPVs list shrinks (e.g., MinIO
  -- distributed→standalone), any chart/templates/pv-*.yaml files that no longer
  -- correspond to a registered PV would lint-fail with "manual PV must declare
  -- claimRef". Sweep stale PV manifests on materialize.
  stalePvResults <- sweepStalePvManifests chartTemplatesRoot configuredManualPVs
  routeResults <- traverse (writeRoute chartTemplatesRoot) routeRegistry
  legacyValuesChanged <- removeFileIfExists (chartTemplatesRoot </> "minio-values.yaml")
  standaloneValuesChanged <- removeFileIfExists (chartRoot </> "minio-values.yaml")
  let clusterBoot = defaultBootConfig substrate Cluster
  configResults <-
    sequence
      [ writeTextFileIfChanged
          (clusterConfRoot </> "Resources.dhall")
          (renderClusterResourcesDhall clusterResources)
      , writeTextFileIfChanged
          (clusterConfRoot </> Text.unpack (renderSubstrate substrate) <> ".dhall")
          (renderBootConfigDhall clusterBoot)
      , writeTextFileIfChanged
          (clusterConfRoot </> "LiveConfig.dhall")
          (renderLiveConfigDhall defaultLiveConfig)
      , writeTextFileIfChanged (chartTemplatesRoot </> "configmap-jitml-service.yaml") $
          renderServiceConfigMaps clusterBoot defaultLiveConfig
      , writeTextFileIfChanged (chartTemplatesRoot </> "deployment-jitml-service.yaml") $
          renderServiceDeployment clusterResources substrate
      , writeTextFileIfChanged (chartTemplatesRoot </> "rbac-jitml-service.yaml") renderServiceRBAC
      , writeTextFileIfChanged (chartRoot </> "local/jitml-service/values.yaml") $
          renderServiceValues clusterResources
      ]
  hostResults <- case substrate of
    AppleSilicon ->
      let lease =
            EdgePort.EdgePortLease
              { EdgePort.leasedPort = edgePort
              , EdgePort.leasedHost = "127.0.0.1"
              }
          publication = publicationWithLeasedPort lease (defaultPublication AppleSilicon)
       in sequence
            [ writeTextFileIfChanged (hostConfRoot </> "apple-silicon.dhall") $
                renderBootConfigDhall (hostBootConfigForPublication publication)
            , writeTextFileIfChanged
                (hostConfRoot </> "LiveConfig.dhall")
                (renderLiveConfigDhall defaultLiveConfig)
            ]
    _ -> pure []
  -- Sprint 2.14 — materialize the in-cluster Docker Hub imagePullSecret manifest
  -- from the host login (the credential lands only in this gitignored file).
  hostRegcred <- discoverHostDockerHubRegcred
  regcredChanged <-
    writeTextFileIfChanged (runtimeRoot </> "regcred.yaml") (renderRegcredManifest hostRegcred)
  pure
    ( or
        ( results
            <> pvResults
            <> stalePvResults
            <> routeResults
            <> configResults
            <> hostResults
            <> [legacyValuesChanged, standaloneValuesChanged, regcredChanged]
        )
    )
 where
  materializePv chartTemplatesRoot pv = do
    createDirectoryIfMissing True (Text.unpack (pvLocalDataPath pv))
    writeTextFileIfChanged
      ( chartTemplatesRoot
          </> ( "pv-"
                  <> Text.unpack (pvNamespace pv)
                  <> "-"
                  <> Text.unpack (pvStatefulSet pv)
                  <> "-"
                  <> show (pvReplica pv)
                  <> ".yaml"
              )
      )
      (renderManualPV pv)

  writeRoute chartTemplatesRoot route =
    writeTextFileIfChanged
      (chartTemplatesRoot </> ("httproute-" <> Text.unpack (routeName route) <> ".yaml"))
      (renderHTTPRoute route)

data LiveExecutionResult = LiveExecutionResult
  { liveStepsExecuted :: [Text]
  , liveStepsFailed :: [LiveStepFailure]
  , livePublication :: ClusterPublication
  , liveAlreadyConverged :: Bool
  }
  deriving stock (Eq, Show)

data LiveStepFailure
  = LiveStepProcessFailure Text ProcessFailure
  | LiveStepInvalidResult Text Text ProcessTranscript
  | LiveStepInvariantFailure Text Text
  deriving stock (Eq, Show)

data KindClusterPresence
  = KindClusterAbsent
  | KindClusterPresent
  deriving stock (Eq, Show)

data LiveKindAction
  = CreateLiveKindCluster
  | ReuseLiveKindCluster
  deriving stock (Eq, Show)

renderLiveStepFailure :: LiveStepFailure -> Text
renderLiveStepFailure (LiveStepProcessFailure label failure) =
  label <> ":\n" <> renderProcessFailure failure
renderLiveStepFailure (LiveStepInvalidResult label message transcript) =
  label
    <> ": "
    <> message
    <> "\n"
    <> renderProcessOutcome (ProcessSucceeded transcript)
renderLiveStepFailure (LiveStepInvariantFailure label message) =
  label <> ": " <> message

livePhasedRolloutSubprocesses :: Substrate -> FilePath -> [Subprocess]
livePhasedRolloutSubprocesses substrate =
  livePhasedRolloutSubprocessesForPort substrate (substrateEdgePort substrate) defaultClusterResources

-- | Sprint 2.9 — the rollout splits in two around the postgres schema grant:
-- the pre-grant phase brings storage up through readiness, the typed Haskell
-- schema grant runs, then the post-grant phase builds and loads the images and
-- installs the remaining releases. Each half is a typed @[Subprocess]@ so the
-- LivePlan/integration dry-run rendering is unchanged.
--
-- Sprint `269.1` emptied the Postgres registry with Harbor, so the grant is a
-- no-op over an empty list rather than a removed step: the machinery is generic
-- over `postgresRegistry`, and a future Postgres-backed service restores it by
-- adding one row.
livePreGrantSubprocessesForPort :: Substrate -> Int -> ClusterResources -> FilePath -> [Subprocess]
livePreGrantSubprocessesForPort substrate edgePort resources chartPath =
  [ kindCreateSubprocess substrate kindConfigPath
  ]
    <> kindNodeInotifyCapSubprocesses substrate resources
    <> [ kubectlRestartPodsByLabelSubprocess "kube-system" "k8s-app=kube-proxy"
       , kubectlRestartPodsByLabelSubprocess "local-path-storage" "app=local-path-provisioner"
       ]
    <> clusterNodeCapSubprocesses substrate resources
    <> [helmDependencyBuildSubprocess chartPath]
    <> kindPrepareStatefulPvSubprocesses substrate resources
    <> cachedThirdPartyImageLoadSteps substrate
    <> foundationManifestApplySubprocesses chartPath
    -- Sprint 2.14 — bind the host Docker Hub login to the platform namespace's
    -- default ServiceAccount (regcred imagePullSecret) before any release pulls,
    -- so the kind node's pods pull Docker Hub images authenticated (no 429).
    <> [kubectlApplyFileSubprocess regcredManifestPath]
    <> concatMap releaseSteps minioBootstrapReleases
    <> Readiness.minioBootstrapReadinessSubprocesses
    -- The registry stores layers in the bucket MinIO just provisioned, so it
    -- installs only after MinIO reports ready.
    <> concatMap releaseSteps registryBootstrapReleases
    <> postgresClusterApplySubprocesses
    <> Readiness.postgresReadinessSubprocesses
 where
  kindConfigPath = "kind/cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml"
  releaseSteps release = [helmInstallSubprocessForEdgePort substrate edgePort release chartPath]
  minioBootstrapReleases = filter ((== "minio") . releaseName) phasedReleases
  registryBootstrapReleases = filter ((== "registry") . releaseName) phasedReleases

livePostGrantSubprocessesForPort :: Substrate -> Int -> FilePath -> [Subprocess]
livePostGrantSubprocessesForPort substrate edgePort chartPath =
  livePostGrantApplySubprocessesForPort substrate edgePort chartPath
    <> livePostGrantReadinessSubprocesses edgePort

livePostGrantApplySubprocessesForPort :: Substrate -> Int -> FilePath -> [Subprocess]
livePostGrantApplySubprocessesForPort substrate edgePort chartPath =
  mirrorBuildSteps substrate
    <> concatMap releaseSteps remainingReleases
    <> observabilityManifestApplySubprocesses chartPath
    <> edgeManifestApplySubprocesses chartPath
 where
  releaseSteps release =
    [ if releaseName release `elem` repoAppReleaseNames
        then helmInstallSubprocessForEdgePortNoWait substrate edgePort release chartPath
        else helmInstallSubprocessForEdgePort substrate edgePort release chartPath
    ]
  remainingReleases =
    filter (\release -> releaseName release `notElem` ["minio", "registry"]) phasedReleases
  repoAppReleaseNames = ["jitml-service", "jitml-demo"]

livePostGrantReadinessSubprocesses :: Int -> [Subprocess]
livePostGrantReadinessSubprocesses edgePort =
  platformReadinessSubprocesses <> [publicReadyzSubprocessForPort edgePort]

livePhasedRolloutSubprocessesForPort
  :: Substrate -> Int -> ClusterResources -> FilePath -> [Subprocess]
livePhasedRolloutSubprocessesForPort substrate edgePort resources chartPath =
  livePreGrantSubprocessesForPort substrate edgePort resources chartPath
    <> livePostGrantSubprocessesForPort substrate edgePort chartPath

-- | The same one-binary image backs the daemon and the Webapp role, so build
-- @jitml:local@ once and retag it as @jitml-demo:local@ instead of running a
-- second full @docker build@. Both tags are loaded into Kind so the local
-- charts can pull them by their distinct workload image names.
mirrorBuildSteps :: Substrate -> [Subprocess]
mirrorBuildSteps substrate =
  dockerBuildAndKindLoadPlan substrate "jitml:local" "."
    ++ [ dockerTagSubprocess "jitml:local" "jitml-demo:local"
       , kindLoadDockerImageSubprocess substrate "jitml-demo:local"
       ]

-- | Optional warm-cache image loads for third-party chart images. The live
-- executor filters these out when the image is not present in the host Docker
-- cache, so first-run behavior still falls back to Kubernetes pulls while
-- warm hosts avoid Docker Hub rate limits during Helm waits.
cachedThirdPartyImageLoadSteps :: Substrate -> [Subprocess]
cachedThirdPartyImageLoadSteps substrate =
  fmap (kindLoadDockerImageSubprocess substrate) cachedThirdPartyRolloutImages

cachedThirdPartyRolloutImages :: [Text]
cachedThirdPartyRolloutImages =
  [ "percona/percona-postgresql-operator:2.5.1"
  , "percona/percona-postgresql-operator:2.5.1-ppg16.8-postgres"
  , "percona/percona-postgresql-operator:2.5.1-ppg16.8-pgbackrest2.54.2"
  , "percona/percona-postgresql-operator:2.5.1-ppg16.8-pgbouncer1.24.0"
  , "docker.io/bitnamilegacy/minio:2024.11.7-debian-12-r0"
  , "bitnamilegacy/minio-client:2024.10.29-debian-12-r1"
  , "apachepulsar/pulsar-all:3.0.7"
  , "docker.io/library/registry:2"
  , "docker.io/envoyproxy/gateway:v1.2.6"
  , "docker.io/envoyproxy/ratelimit:49af5cca"
  , "docker.io/envoyproxy/envoy:v1.31.4"
  , "quay.io/kiwigrid/k8s-sidecar:1.30.0"
  , "docker.io/grafana/grafana:11.6.0"
  , "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0"
  , "quay.io/prometheus-operator/prometheus-operator:v0.81.0"
  , "quay.io/prometheus/prometheus:v3.2.1"
  , "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.2"
  , "python:3.11-slim"
  ]

kindNodeInotifyCapSubprocesses :: Substrate -> ClusterResources -> [Subprocess]
kindNodeInotifyCapSubprocesses substrate resources =
  fmap
    kindNodeInotifyCapSubprocess
    (substrateKindNodeContainerNames substrate (workerCount resources))

kindNodeInotifyCapSubprocess :: Text -> Subprocess
kindNodeInotifyCapSubprocess nodeName =
  subprocess
    "docker"
    [ "exec"
    , nodeName
    , "sysctl"
    , "-w"
    , "fs.inotify.max_user_instances=1024"
    , "fs.inotify.max_queued_events=65536"
    ]

kubectlRestartPodsByLabelSubprocess :: Text -> Text -> Subprocess
kubectlRestartPodsByLabelSubprocess namespace selector =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "delete"
    , "pod"
    , "-n"
    , namespace
    , "-l"
    , selector
    , "--ignore-not-found"
    ]

kindNormalizePostgresPvOwnershipSubprocess :: Text -> Subprocess
kindNormalizePostgresPvOwnershipSubprocess nodeName =
  subprocess
    "docker"
    ( [ "exec"
      , nodeName
      , "chown"
      , "-R"
      , "26:26"
      ]
        <> fmap pvNodeDataPath postgresManualPVs
    )

kindPrepareStatefulPvSubprocesses :: Substrate -> ClusterResources -> [Subprocess]
kindPrepareStatefulPvSubprocesses substrate resources =
  case substrate of
    AppleSilicon ->
      fmap kindMountStatefulPvNodeLocalSubprocess nodeNames
    LinuxCPU ->
      fmap kindMountStatefulPvNodeLocalSubprocess nodeNames
    LinuxCUDA
      -- The ownership fixup takes the Postgres PV paths as its operands, so an
      -- empty registry would render `chown -R 26:26` with nothing to chown and
      -- fail the bootstrap. No registered Postgres means no fixup to perform.
      | null postgresManualPVs -> []
      | otherwise -> fmap kindNormalizePostgresPvOwnershipSubprocess nodeNames
 where
  nodeNames = substrateKindNodeContainerNames substrate (workerCount resources)

kindMountStatefulPvNodeLocalSubprocess :: Text -> Subprocess
kindMountStatefulPvNodeLocalSubprocess nodeName =
  subprocess
    "docker"
    [ "exec"
    , nodeName
    , "sh"
    , "-c"
    , Text.unwords
        ( ["set -e;"]
            <> fmap mountOne manualPVs
        )
    ]
 where
  mountOne pv =
    let nodePath = pvNodeDataPath pv
        localPath = "/var/local/jitml-stateful-pv" <> nodePath
     in Text.unwords
          [ "mkdir -p"
          , localPath
          , nodePath <> ";"
          , "mountpoint -q"
          , nodePath
          , "|| mount --bind"
          , localPath
          , nodePath <> ";"
          , pvOwnershipCommand pv
          , localPath <> ";"
          ]

pvOwnershipCommand :: ManualPV -> Text
pvOwnershipCommand pv
  | pvIsPostgres pv = "chown -R 26:26"
  | otherwise = "chmod 0777"

postgresManualPVs :: [ManualPV]
postgresManualPVs =
  filter pvIsPostgres manualPVs

pvIsPostgres :: ManualPV -> Bool
pvIsPostgres pv =
  any
    ( \cluster ->
        pvNamespace pv == perconaNamespace cluster
          && ( pvStatefulSet pv == perconaClusterName cluster
                 || pvStatefulSet pv == perconaClusterName cluster <> "-repo1"
             )
    )
    postgresRegistry

foundationManifestApplySubprocesses :: FilePath -> [Subprocess]
foundationManifestApplySubprocesses chartPath =
  fmap
    (kubectlApplyFileSubprocess . templatePath)
    ( ["storageclass-jitml-manual.yaml", "runtimeclass-nvidia.yaml"]
        <> fmap pvManifestName manualPVs
    )
 where
  templatePath fileName = chartPath </> "templates" </> fileName

edgeManifestApplySubprocesses :: FilePath -> [Subprocess]
edgeManifestApplySubprocesses chartPath =
  fmap
    (kubectlApplyFileSubprocess . templatePath)
    ( [ "gatewayclass-jitml.yaml"
      , "envoyproxy-jitml-edge.yaml"
      , "gateway-jitml-edge.yaml"
      ]
        <> fmap routeManifestName routeRegistry
    )
 where
  templatePath fileName = chartPath </> "templates" </> fileName

-- | Prove the complete public edge path after the Gateway and HTTPRoutes have
-- been applied. The @jitml-service@ Service selects only the Coordinator, so a
-- successful fail-on-HTTP-error request proves Gateway admission, Service
-- routing, and the Coordinator's dynamic readiness state before publication.
-- Curl's per-attempt and aggregate limits keep this a bounded typed subprocess;
-- no shell retry loop or stringly status parsing is involved.
publicReadyzSubprocessForPort :: Int -> Subprocess
publicReadyzSubprocessForPort edgePort =
  subprocess
    "curl"
    [ "--fail"
    , "--silent"
    , "--show-error"
    , "--connect-timeout"
    , "5"
    , "--max-time"
    , "10"
    , "--retry"
    , "30"
    , "--retry-delay"
    , "2"
    , "--retry-max-time"
    , "180"
    , "--retry-connrefused"
    , "--retry-all-errors"
    , "http://127.0.0.1:" <> Text.pack (show edgePort) <> "/readyz"
    ]

observabilityManifestApplySubprocesses :: FilePath -> [Subprocess]
observabilityManifestApplySubprocesses chartPath =
  fmap
    (kubectlApplyFileSubprocess . templatePath)
    ( fmap dashboardManifestName Grafana.dashboards
        <> ["prometheus-scrapeconfig-jitml.yaml"]
    )
 where
  templatePath fileName = chartPath </> "templates" </> fileName

dashboardManifestName :: Grafana.Dashboard -> FilePath
dashboardManifestName dashboard =
  "grafana-dashboard-" <> Text.unpack (Grafana.dashboardName dashboard) <> ".yaml"

kubectlApplyFileSubprocess :: FilePath -> Subprocess
kubectlApplyFileSubprocess path =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "apply"
    , "-f"
    , Text.pack path
    ]

-- | Sprint 2.14 — the repo-relative path of the materialized in-cluster Docker
-- Hub @imagePullSecret@ manifest. It lives under the gitignored @.build/runtime@
-- so the Docker Hub credential never enters the repo tree.
regcredManifestPath :: FilePath
regcredManifestPath = ".build" </> "runtime" </> "regcred.yaml"

-- | Sprint 2.14 — discover the host's Docker Hub credential and project the
-- minimal @docker.io@-only @dockerconfigjson@ (mirroring the host
-- @config.json@ @auths@ filtering, so private-registry creds are not
-- forwarded into the cluster). Reads, never writes, the host config. Returns
-- 'Nothing' when the host is not logged in to Docker Hub (the cluster then falls
-- back to anonymous pulls). This is jitML's own self-contained Docker Hub
-- credential-forwarding path for the bootstrap.
discoverHostDockerHubRegcred :: IO (Maybe Text)
discoverHostDockerHubRegcred = do
  dockerConfigDir <- lookupEnv "DOCKER_CONFIG"
  home <- getHomeDirectory
  let configPath = case dockerConfigDir of
        Just dir | not (null dir) -> dir </> "config.json"
        _ -> home </> ".docker" </> "config.json"
  configExists <- doesFileExist configPath
  if not configExists
    then pure Nothing
    else do
      raw <- LazyByteString.readFile configPath
      pure $ case decode raw of
        Just (Object top) -> case KeyMap.lookup "auths" top of
          Just (Object auths) ->
            let hub = KeyMap.filterWithKey (\k _ -> "docker.io" `Text.isInfixOf` Key.toText k) auths
             in if KeyMap.null hub
                  then Nothing
                  else
                    Just . Text.Encoding.decodeUtf8 . LazyByteString.toStrict $
                      encode (object ["auths" .= Object hub])
          _ -> Nothing
        _ -> Nothing

-- | Sprint 2.14 — render the in-cluster Docker Hub @imagePullSecret@ manifest for
-- the @platform@ namespace. Always declares the namespace (an idempotent ensure
-- the Helm @--create-namespace@ then no-ops); when the host is logged in, also
-- declares the @regcred@ @dockerconfigjson@ Secret and binds it to the namespace
-- @default@ ServiceAccount so every pod pulls Docker Hub images authenticated
-- (no anonymous 429). @stringData@ carries the credential plaintext so the kube
-- API server base64-encodes it; the credential persists only in the gitignored
-- materialized file.
renderRegcredManifest :: Maybe Text -> Text
renderRegcredManifest mDockerConfigJson =
  Text.unlines $
    [ "apiVersion: v1"
    , "kind: Namespace"
    , "metadata:"
    , "  name: platform"
    ]
      <> case mDockerConfigJson of
        Nothing -> []
        Just dockerConfigJson ->
          [ "---"
          , "apiVersion: v1"
          , "kind: Secret"
          , "metadata:"
          , "  name: regcred"
          , "  namespace: platform"
          , "type: kubernetes.io/dockerconfigjson"
          , "stringData:"
          , "  .dockerconfigjson: '" <> dockerConfigJson <> "'"
          , "---"
          , "apiVersion: v1"
          , "kind: ServiceAccount"
          , "metadata:"
          , "  name: default"
          , "  namespace: platform"
          , "imagePullSecrets:"
          , "  - name: regcred"
          ]

postgresClusterApplySubprocesses :: [Subprocess]
postgresClusterApplySubprocesses =
  fmap postgresClusterApplySubprocess postgresRegistry

postgresClusterApplySubprocess :: PerconaPGCluster -> Subprocess
postgresClusterApplySubprocess cluster =
  subprocessWithStdin
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "apply"
    , "-n"
    , "platform"
    , "-f"
    , "-"
    ]
    (renderPerconaPGCluster cluster)

-- | Sprint 2.9 — typed Haskell postgres schema grant. Replaces the prior @sh
-- -c@ that captured the primary pod name via @$(kubectl ... jsonpath)@ and
-- then exec'd @psql -c \"GRANT ...\"@. Two typed @kubectl@ subprocesses; the
-- pod-name capture happens in Haskell via @runStreaming@'s stdout result.
postgresSchemaGrantIO :: PerconaPGCluster -> IO (Either LiveStepFailure ())
postgresSchemaGrantIO cluster = do
  let ns = perconaNamespace cluster
      cn = perconaClusterName cluster
      db = perconaDatabase cluster
      getPodSub =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "get"
          , "pod"
          , "-n"
          , ns
          , "-l"
          , "postgres-operator.crunchydata.com/cluster="
              <> cn
              <> ",postgres-operator.crunchydata.com/role=master"
          , "-o"
          , "jsonpath={.items[0].metadata.name}"
          ]
  getOutcome <- runStreaming defaultSubprocessEnv getPodSub
  case getOutcome of
    ProcessFailed failure ->
      pure (Left (LiveStepProcessFailure ("postgres get-primary " <> cn) failure))
    ProcessSucceeded transcript ->
      let podName = Text.strip (processTranscriptStdout transcript)
       in if Text.null podName
            then
              pure
                ( Left
                    ( LiveStepInvalidResult
                        ("postgres get-primary " <> cn)
                        "empty pod name"
                        transcript
                    )
                )
            else do
              let psqlSub =
                    subprocess
                      "kubectl"
                      [ "--kubeconfig"
                      , "./.build/jitml.kubeconfig"
                      , "exec"
                      , "-n"
                      , ns
                      , podName
                      , "-c"
                      , "database"
                      , "--"
                      , "psql"
                      , "-d"
                      , db
                      , "-c"
                      , "ALTER DATABASE "
                          <> db
                          <> " OWNER TO "
                          <> db
                          <> "; GRANT ALL PRIVILEGES ON DATABASE "
                          <> db
                          <> " TO "
                          <> db
                          <> "; GRANT ALL ON SCHEMA public TO "
                          <> db
                          <> "; ALTER SCHEMA public OWNER TO "
                          <> db
                          <> ";"
                      ]
              psqlOutcome <- runStreaming defaultSubprocessEnv psqlSub
              case psqlOutcome of
                ProcessSucceeded _ -> pure (Right ())
                ProcessFailed failure ->
                  pure (Left (LiveStepProcessFailure ("postgres schema grant " <> cn) failure))

-- | Run all postgres schema grants in registry order, returning the first
-- failure as @Left@. Equivalent to the former @postgresSchemaGrantSubprocesses@
-- list except that command-substitution lives in Haskell, not @sh -c@.
runPostgresSchemaGrantsIO :: IO (Either LiveStepFailure ())
runPostgresSchemaGrantsIO = go postgresRegistry
 where
  go [] = pure (Right ())
  go (cluster : rest) = do
    result <- postgresSchemaGrantIO cluster
    case result of
      Left err -> pure (Left err)
      Right () -> go rest

pvManifestName :: ManualPV -> FilePath
pvManifestName pv =
  "pv-"
    <> Text.unpack (pvNamespace pv)
    <> "-"
    <> Text.unpack (pvStatefulSet pv)
    <> "-"
    <> show (pvReplica pv)
    <> ".yaml"

routeManifestName :: Route -> FilePath
routeManifestName route =
  "httproute-" <> Text.unpack (routeName route) <> ".yaml"

hostBootConfigForPublication :: ClusterPublication -> BootConfig
hostBootConfigForPublication publication =
  (defaultBootConfig AppleSilicon Host)
    { bootPulsarServiceUrl = publicationPulsarUrl publication
    , bootPulsarAdminUrl = "http://127.0.0.1:" <> portText <> "/pulsar/admin"
    , bootMinioEndpoint = publicationMinioUrl publication
    , bootImageRegistry = "127.0.0.1:" <> portText <> "/library"
    }
 where
  portText = Text.pack (show (publicationEdgePort publication))

data RepoAppImageSpec = RepoAppImageSpec
  { repoAppDeployment :: Text
  , repoAppLabel :: Text
  , repoAppImageTag :: Text
  }

repoAppImageSpecs :: Substrate -> [RepoAppImageSpec]
repoAppImageSpecs substrate =
  engineSpec
    <> [ RepoAppImageSpec "jitml-coordinator" "jitml-coordinator" "jitml:local"
       , RepoAppImageSpec "jitml-demo" "jitml-demo" "jitml-demo:local"
       ]
 where
  engineSpec =
    [ RepoAppImageSpec "jitml-service" "jitml-service" "jitml:local"
    | substrateHasClusterCompute substrate
    ]

newtype AppPodList = AppPodList [AppPodObservation]

instance FromJSON AppPodList where
  parseJSON =
    withObject "AppPodList" $ \root ->
      AppPodList <$> root .: "items"

data AppPodObservation = AppPodObservation
  { appPodDeletionTimestamp :: Maybe Text
  , appPodContainerStatuses :: [AppContainerObservation]
  }

instance FromJSON AppPodObservation where
  parseJSON =
    withObject "AppPodObservation" $ \pod -> do
      metadata <- pod .: "metadata"
      status <- pod .: "status"
      AppPodObservation
        <$> withObject
          "AppPodMetadata"
          (.:? "deletionTimestamp")
          metadata
        <*> withObject
          "AppPodStatus"
          (\statusObject -> statusObject .:? "containerStatuses" .!= [])
          status

data AppContainerObservation = AppContainerObservation
  { appContainerReady :: Bool
  , appContainerImageId :: Text
  }

instance FromJSON AppContainerObservation where
  parseJSON =
    withObject "AppContainerObservation" $ \container ->
      AppContainerObservation
        <$> container .: "ready"
        <*> container .: "imageID"

data AppPodImageEvidence = AppPodImageEvidence
  { appPodActiveImageIds :: [Text]
  , appPodTerminatingImageIds :: [Text]
  , appPodIncompleteActiveCount :: Int
  }
  deriving (Eq, Show)

-- | Parse the exact image state of every label-matching repo-owned app pod.
-- Deployment rollout completion and Pod-object deletion are separate events,
-- so terminating pods remain explicit evidence until the API object is gone.
-- Active pods are complete only when they expose exactly one ready container
-- with a concrete SHA-256 config digest.
parseAppPodImageEvidence :: Text -> Maybe AppPodImageEvidence
parseAppPodImageEvidence output = do
  AppPodList pods <-
    decode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 output))
  observations <- traverse observePod pods
  pure
    AppPodImageEvidence
      { appPodActiveImageIds = concatMap activeIds observations
      , appPodTerminatingImageIds = concatMap terminatingIds observations
      , appPodIncompleteActiveCount = sum (fmap incompleteActive observations)
      }
 where
  observePod pod
    | isJust (appPodDeletionTimestamp pod) =
        Just
          PodImageObservation
            { activeIds = []
            , terminatingIds = containerImageIds pod
            , incompleteActive = 0
            }
    | otherwise =
        case appPodContainerStatuses pod of
          [container]
            | let imageId = Text.strip (appContainerImageId container) ->
                Just
                  PodImageObservation
                    { activeIds = [imageId]
                    , terminatingIds = []
                    , incompleteActive =
                        if appContainerReady container && validSha256Digest imageId
                          then 0
                          else 1
                    }
          _ ->
            Just
              PodImageObservation
                { activeIds = containerImageIds pod
                , terminatingIds = []
                , incompleteActive = 1
                }

  containerImageIds =
    fmap (Text.strip . appContainerImageId) . appPodContainerStatuses

data PodImageObservation = PodImageObservation
  { activeIds :: [Text]
  , terminatingIds :: [Text]
  , incompleteActive :: Int
  }

appPodImageEvidenceMatchesLoadedImage
  :: Int
  -> Text
  -> AppPodImageEvidence
  -> Bool
appPodImageEvidenceMatchesLoadedImage expectedReplicas expectedImageId evidence =
  null (appPodTerminatingImageIds evidence)
    && appPodIncompleteActiveCount evidence == 0
    && appRolloutMatchesLoadedImage
      expectedReplicas
      expectedImageId
      (appPodActiveImageIds evidence)

data AppPodImagePollDecision
  = AppPodImageConverged
  | AppPodImageRetry
  | AppPodImageExhausted
  deriving (Eq, Show)

appPodImagePollDecision
  :: Int
  -> Text
  -> Int
  -> AppPodImageEvidence
  -> AppPodImagePollDecision
appPodImagePollDecision expectedReplicas expectedImageId attemptsRemaining evidence
  | appPodImageEvidenceMatchesLoadedImage expectedReplicas expectedImageId evidence =
      AppPodImageConverged
  | attemptsRemaining > 1 = AppPodImageRetry
  | otherwise = AppPodImageExhausted

-- | Decide whether the complete ready pod set already resolves the mutable
-- local tag to the image identity loaded into Kind. A same-tag rebuild is not
-- a Kubernetes template change, so bootstrap uses this predicate after Helm
-- and rolls only workloads whose observed config IDs are stale or incomplete.
appRolloutMatchesLoadedImage :: Int -> Text -> [Text] -> Bool
appRolloutMatchesLoadedImage expectedReplicas expectedImageId observedImageIds =
  expectedReplicas > 0
    && length observedImageIds == expectedReplicas
    && all (== expectedImageId) observedImageIds

reconcileStampPath :: FilePath -> FilePath
reconcileStampPath root =
  root </> ".build" </> "runtime" </> "cluster-reconcile-stamp.json"

readReconcileStamp :: FilePath -> IO (Maybe ReconcileStamp)
readReconcileStamp root = do
  let path = reconcileStampPath root
  exists <- doesFileExist path
  if exists
    then decode <$> LazyByteString.readFile path
    else pure Nothing

writeReconcileStamp :: FilePath -> ReconcileStamp -> IO Bool
writeReconcileStamp root stamp = do
  let path = reconcileStampPath root
  createDirectoryIfMissing True (root </> ".build" </> "runtime")
  writeLazyByteStringIfChanged path (encode stamp)

localDockerImageInspectSubprocess :: Text -> Subprocess
localDockerImageInspectSubprocess imageTag =
  subprocess
    "docker"
    [ "image"
    , "inspect"
    , "--format={{.Descriptor.digest}}"
    , imageTag
    ]

kindNodeImageInspectSubprocess :: Text -> Text -> Subprocess
kindNodeImageInspectSubprocess nodeName imageTag =
  subprocess
    "docker"
    [ "exec"
    , nodeName
    , "crictl"
    , "inspecti"
    , imageTag
    ]

kindNodeImageManifestInspectSubprocess :: Text -> Text -> Subprocess
kindNodeImageManifestInspectSubprocess nodeName imageTag =
  subprocess
    "docker"
    [ "exec"
    , nodeName
    , "ctr"
    , "-n"
    , "k8s.io"
    , "images"
    , "ls"
    , "name==" <> containerdImageReference imageTag
    ]

containerdImageReference :: Text -> Text
containerdImageReference imageTag
  | "/" `Text.isInfixOf` imageTag = imageTag
  | otherwise = "docker.io/library/" <> imageTag

-- | Extract the exact OCI target digest from one filtered @ctr images ls@
-- result. The header is ignored because its digest column is not a SHA-256;
-- multiple matching rows are rejected instead of selecting one ambiguously.
parseContainerdImageListDigest :: Text -> Maybe Text
parseContainerdImageListDigest output =
  case [ digest
       | line <- Text.lines output
       , _reference : _mediaType : digest : _ <- [Text.words line]
       , validSha256Digest digest
       ] of
    [digest] -> Just digest
    _ -> Nothing

validSha256Digest :: Text -> Bool
validSha256Digest digest =
  case Text.stripPrefix "sha256:" digest of
    Just hexadecimal ->
      Text.length hexadecimal == 64 && Text.all isHexDigit hexadecimal
    Nothing -> False

inspectLocalDockerImageIdIO :: Text -> IO (Either LiveStepFailure Text)
inspectLocalDockerImageIdIO imageTag = do
  let command = localDockerImageInspectSubprocess imageTag
      label = renderSubprocess command
  outcome <- runStreaming defaultSubprocessEnv command
  pure $
    case outcome of
      ProcessFailed failure -> Left (LiveStepProcessFailure label failure)
      ProcessSucceeded transcript ->
        let imageId = Text.strip (processTranscriptStdout transcript)
         in if Text.null imageId
              then Left (LiveStepInvalidResult label "empty image identity" transcript)
              else Right imageId

inspectKindNodeImageIdIO :: Text -> Text -> IO (Maybe Text)
inspectKindNodeImageIdIO nodeName imageTag = do
  outcome <-
    runStreaming
      defaultSubprocessEnv
      (kindNodeImageInspectSubprocess nodeName imageTag)
  pure $
    case outcome of
      ProcessFailed _ -> Nothing
      ProcessSucceeded transcript ->
        case eitherDecode
          (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
          Right (Object root)
            | Just (Object status) <- KeyMap.lookup "status" root
            , Just (String imageId) <- KeyMap.lookup "id" status
            , not (Text.null (Text.strip imageId)) ->
                Just (Text.strip imageId)
          _ -> Nothing

inspectKindNodeImageManifestIdIO :: Text -> Text -> IO (Maybe Text)
inspectKindNodeImageManifestIdIO nodeName imageTag = do
  outcome <-
    runStreaming
      defaultSubprocessEnv
      (kindNodeImageManifestInspectSubprocess nodeName imageTag)
  pure $
    case outcome of
      ProcessFailed _ -> Nothing
      ProcessSucceeded transcript ->
        parseContainerdImageListDigest (processTranscriptStdout transcript)

repoAppImageTags :: Substrate -> [Text]
repoAppImageTags = nub . fmap repoAppImageTag . repoAppImageSpecs

repoAppImageIdsIO :: Substrate -> IO (Either LiveStepFailure (Map Text Text))
repoAppImageIdsIO substrate = go Map.empty (repoAppImageTags substrate)
 where
  go imageIds [] = pure (Right imageIds)
  go imageIds (imageTag : rest) = do
    inspected <- inspectLocalDockerImageIdIO imageTag
    case inspected of
      Left failure -> pure (Left failure)
      Right imageId -> go (Map.insert imageTag imageId imageIds) rest

buildExpectedReconcileStampIO
  :: FilePath
  -> Substrate
  -> Int
  -> IO (Either LiveStepFailure ReconcileStamp)
buildExpectedReconcileStampIO root substrate edgePort = do
  fingerprint <- fingerprintWorkspace root
  imageIdsResult <- repoAppImageIdsIO substrate
  pure $ do
    imageIds <- imageIdsResult
    case mkReconcileStamp substrate edgePort fingerprint imageIds of
      Left message ->
        Left (LiveStepInvariantFailure "cluster reconcile stamp" message)
      Right stamp -> Right stamp

releaseConvergenceEvidenceIO :: IO ReconcileEvidence
releaseConvergenceEvidenceIO = do
  let expected = fmap releaseName phasedReleases
  statuses <- traverse measureHelmRelease expected
  pure
    ReconcileEvidence
      { reconcileEvidenceExpected = expected
      , reconcileEvidenceObserved =
          fmap (\(release, status) -> (release, status == "deployed")) statuses
      }

readinessConvergenceEvidence :: ClusterPublication -> ReconcileEvidence
readinessConvergenceEvidence publication =
  ReconcileEvidence
    { reconcileEvidenceExpected =
        requiredPublicationComponents (publicationSubstrate publication)
    , reconcileEvidenceObserved =
        fmap (\(name, status) -> (name, status == "ready")) (publicationComponents publication)
    }

data TopicStatsPollDecision
  = TopicStatsObserved
  | TopicStatsRetry
  | TopicStatsExhausted
  deriving stock (Eq, Show)

topicStatsPollDecision :: Int -> Maybe Text -> TopicStatsPollDecision
topicStatsPollDecision attemptsRemaining capturedStdout
  | maybe False topicStatsJsonObject capturedStdout = TopicStatsObserved
  | attemptsRemaining <= 1 = TopicStatsExhausted
  | otherwise = TopicStatsRetry
 where
  topicStatsJsonObject output =
    case eitherDecode
      ( LazyByteString.fromStrict
          (Text.Encoding.encodeUtf8 output)
      ) of
      Right (Object _) -> True
      _ -> False

topicConvergenceEvidenceIO :: IO ReconcileEvidence
topicConvergenceEvidenceIO = do
  observed <- mapConcurrently observeTopic PulsarBootstrap.pulsarTopics
  pure
    ReconcileEvidence
      { reconcileEvidenceExpected = fmap fst observed
      , reconcileEvidenceObserved = observed
      }
 where
  observeTopic topic =
    (PulsarBootstrap.topicName topic,) <$> probeTopic (3 :: Int) topic
  probeTopic attemptsRemaining topic = do
    outcome <-
      runStreaming
        defaultSubprocessEnv
        (PulsarBootstrap.pulsarTopicStatsSubprocess topic)
    let capturedStdout =
          case outcome of
            ProcessSucceeded transcript -> Just (processTranscriptStdout transcript)
            ProcessFailed _ -> Nothing
    case topicStatsPollDecision attemptsRemaining capturedStdout of
      TopicStatsObserved -> pure True
      TopicStatsExhausted -> pure False
      TopicStatsRetry -> do
        threadDelay 500_000
        probeTopic (attemptsRemaining - 1) topic

nodeImageConvergenceEvidenceIO
  :: Substrate
  -> ClusterResources
  -> Map Text Text
  -> IO (ReconcileEvidence, Map Text Text)
nodeImageConvergenceEvidenceIO substrate resources expectedImageIds = do
  let nodeNames =
        substrateKindNodeContainerNames substrate (workerCount resources)
      imageTags = repoAppImageTags substrate
      nodeImagePairs =
        [ (nodeName, imageTag)
        | nodeName <- nodeNames
        , imageTag <- imageTags
        ]
      expected =
        concatMap
          ( \(nodeName, imageTag) ->
              let (manifestLabel, configLabel) =
                    nodeImageEvidenceLabels nodeName imageTag
               in [manifestLabel, configLabel]
          )
          nodeImagePairs
  manifestIds <-
    traverse
      ( \pair@(nodeName, imageTag) ->
          (pair,) <$> inspectKindNodeImageManifestIdIO nodeName imageTag
      )
      nodeImagePairs
  configIds <-
    traverse
      ( \pair@(nodeName, imageTag) ->
          (pair,) <$> inspectKindNodeImageIdIO nodeName imageTag
      )
      nodeImagePairs
  let uniformConfigIds =
        Map.fromList
          [ (imageTag, configId)
          | imageTag <- imageTags
          , Just configId <-
              [ uniformImageId
                  [ configId
                  | ((_, observedTag), configId) <- configIds
                  , observedTag == imageTag
                  ]
              ]
          ]
      observed =
        concatMap
          ( \pair@(nodeName, imageTag) ->
              let (manifestLabel, configLabel) =
                    nodeImageEvidenceLabels nodeName imageTag
                  manifestMatches =
                    case (lookup pair manifestIds, Map.lookup imageTag expectedImageIds) of
                      (Just (Just actual), Just expectedId) -> actual == expectedId
                      _ -> False
                  configMatches =
                    case (lookup pair configIds, Map.lookup imageTag uniformConfigIds) of
                      (Just (Just actual), Just expectedId) -> actual == expectedId
                      _ -> False
               in [
                    ( manifestLabel
                    , manifestMatches
                    )
                  ,
                    ( configLabel
                    , configMatches
                    )
                  ]
          )
          nodeImagePairs
  pure
    ( ReconcileEvidence
        { reconcileEvidenceExpected = expected
        , reconcileEvidenceObserved = observed
        }
    , uniformConfigIds
    )

nodeImageEvidenceLabels :: Text -> Text -> (Text, Text)
nodeImageEvidenceLabels nodeName imageTag =
  ( nodeName <> "/" <> imageTag <> "/oci-target"
  , nodeName <> "/" <> imageTag <> "/config"
  )

uniformImageId :: [Maybe Text] -> Maybe Text
uniformImageId values =
  case sequence values of
    Just (first : rest)
      | not (Text.null (Text.strip first))
      , all (== first) rest ->
          Just first
    _ -> Nothing

appImageConvergenceEvidenceIO
  :: Substrate
  -> Map Text Text
  -> IO ReconcileEvidence
appImageConvergenceEvidenceIO substrate expectedImageIds = do
  let specs = repoAppImageSpecs substrate
      expected = fmap repoAppDeployment specs
  observed <- traverse observe specs
  pure
    ReconcileEvidence
      { reconcileEvidenceExpected = expected
      , reconcileEvidenceObserved = observed
      }
 where
  observe spec = do
    replicaOutcome <-
      runStreaming
        defaultSubprocessEnv
        (appDeploymentReplicaCountSubprocess (repoAppDeployment spec))
    imageOutcome <-
      runStreaming
        defaultSubprocessEnv
        (appPodEvidenceSubprocess (repoAppLabel spec))
    let expectedImageId = Map.lookup (repoAppImageTag spec) expectedImageIds
        expectedReplicas =
          case replicaOutcome of
            ProcessFailed _ -> Nothing
            ProcessSucceeded transcript ->
              case reads (Text.unpack (Text.strip (processTranscriptStdout transcript))) of
                [(replicaCount, "")] | replicaCount > 0 -> Just replicaCount
                _ -> Nothing
        observedEvidence =
          case imageOutcome of
            ProcessFailed _ -> Nothing
            ProcessSucceeded transcript ->
              parseAppPodImageEvidence (processTranscriptStdout transcript)
        current =
          case (expectedReplicas, expectedImageId, observedEvidence) of
            (Just replicas, Just imageId, Just evidence) ->
              appPodImageEvidenceMatchesLoadedImage replicas imageId evidence
            _ -> False
    pure (repoAppDeployment spec, current)

data LiveConvergenceObservation
  = LiveClusterAlreadyConverged ClusterPublication
  | LiveClusterNeedsReconcile Text

observeLiveConvergenceIO
  :: FilePath
  -> Substrate
  -> ClusterResources
  -> LiveKindAction
  -> Int
  -> Bool
  -> IO LiveConvergenceObservation
observeLiveConvergenceIO root substrate resources kindAction edgePort materializationChanged =
  case kindAction of
    CreateLiveKindCluster ->
      pure (LiveClusterNeedsReconcile "target Kind cluster is absent")
    ReuseLiveKindCluster
      | materializationChanged ->
          pure (LiveClusterNeedsReconcile "port-aware materialization changed")
      | otherwise -> do
          publicationState <- readExistingPublicationState root
          persistedStamp <- readReconcileStamp root
          expectedStampResult <- buildExpectedReconcileStampIO root substrate edgePort
          case (publicationState, expectedStampResult) of
            (ExistingPublicationValid publication, Right expectedStamp) -> do
              measuredPublication <- measureLivePublication publication
              releaseEvidence <- releaseConvergenceEvidenceIO
              topicEvidence <- topicConvergenceEvidenceIO
              let expectedImageIds = reconcileStampRepoAppImageIds expectedStamp
              (nodeImageEvidence, liveConfigImageIds) <-
                nodeImageConvergenceEvidenceIO substrate resources expectedImageIds
              appImageEvidence <-
                appImageConvergenceEvidenceIO substrate liveConfigImageIds
              let publicationObservation
                    | publicationSubstrate publication /= substrate =
                        LivePublicationInvalid "publication substrate does not match"
                    | publicationEdgePort publication /= edgePort =
                        LivePublicationInvalid "publication edge port does not match"
                    | not (publicationHasLiveEvidence publication) =
                        LivePublicationNotReady "persisted publication lacks live evidence"
                    | publicationHasLiveEvidence measuredPublication =
                        LivePublicationReady
                    | otherwise =
                        LivePublicationNotReady (renderIncompletePublication measuredPublication)
                  observation =
                    ReconcileObservation
                      { reconcileExpectedStamp = expectedStamp
                      , reconcilePersistedStamp = persistedStamp
                      , reconcileLivePublication = publicationObservation
                      , reconcileReleaseEvidence = releaseEvidence
                      , reconcileReadinessEvidence =
                          readinessConvergenceEvidence measuredPublication
                      , reconcileTopicEvidence = topicEvidence
                      , reconcileNodeImageEvidence = nodeImageEvidence
                      , reconcileAppImageEvidence = appImageEvidence
                      , reconcilePortAwareMaterializationUnchanged = True
                      }
              pure $
                case classifyReconcileObservation observation of
                  AlreadyConverged -> LiveClusterAlreadyConverged publication
                  NeedsReconcile reasons ->
                    LiveClusterNeedsReconcile (Text.pack (show reasons))
            (ExistingPublicationMissing, _) ->
              pure (LiveClusterNeedsReconcile "cluster publication is missing")
            (ExistingPublicationInvalid message, _) ->
              pure (LiveClusterNeedsReconcile ("cluster publication is invalid: " <> message))
            (_, Left failure) ->
              pure (LiveClusterNeedsReconcile (renderLiveStepFailure failure))

kindImageInspectSubprocess :: Substrate -> Text -> Subprocess
kindImageInspectSubprocess substrate imageTag =
  subprocess
    "docker"
    [ "exec"
    , substrateClusterName substrate <> "-control-plane"
    , "crictl"
    , "inspecti"
    , imageTag
    ]

appPodEvidenceSubprocess :: Text -> Subprocess
appPodEvidenceSubprocess appLabel =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "get"
    , "pod"
    , "-n"
    , "platform"
    , "-l"
    , "app=" <> appLabel
    , "-o"
    , "json"
    ]

appDeploymentReplicaCountSubprocess :: Text -> Subprocess
appDeploymentReplicaCountSubprocess deployment =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "get"
    , "deployment/" <> deployment
    , "-n"
    , "platform"
    , "-o"
    , "jsonpath={.spec.replicas}"
    ]

appRolloutRestartSubprocess :: Text -> Subprocess
appRolloutRestartSubprocess deployment =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "rollout"
    , "restart"
    , "deployment/" <> deployment
    , "-n"
    , "platform"
    ]

appRolloutStatusSubprocess :: Text -> Subprocess
appRolloutStatusSubprocess deployment =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "rollout"
    , "status"
    , "deployment/" <> deployment
    , "-n"
    , "platform"
    , "--timeout=300s"
    ]

runRepoAppImageReconcileIO :: Substrate -> IO (Either LiveStepFailure [Text])
runRepoAppImageReconcileIO substrate = go [] (repoAppImageSpecs substrate)
 where
  go executed [] = pure (Right (reverse executed))
  go executed (spec : rest) = do
    expectedResult <- inspectExpectedImage spec
    case expectedResult of
      Left failure -> pure (Left failure)
      Right (expectedImageId, expectedLabel) -> do
        replicaResult <- inspectExpectedReplicas spec
        case replicaResult of
          Left failure -> pure (Left failure)
          Right (expectedReplicas, replicaLabel) -> do
            observedResult <- inspectObservedImages spec
            case observedResult of
              Left failure -> pure (Left failure)
              Right (observedEvidence, observedLabel) ->
                if appPodImageEvidenceMatchesLoadedImage
                  expectedReplicas
                  expectedImageId
                  observedEvidence
                  then
                    go
                      ( ( "app image reconcile "
                            <> repoAppDeployment spec
                            <> " already current at "
                            <> expectedImageId
                        )
                          : observedLabel
                          : replicaLabel
                          : expectedLabel
                          : executed
                      )
                      rest
                  else do
                    rolloutResult <- rollAndVerify spec expectedReplicas expectedImageId
                    case rolloutResult of
                      Left failure -> pure (Left failure)
                      Right rolloutLabels ->
                        go
                          ( reverse rolloutLabels
                              <> (observedLabel : replicaLabel : expectedLabel : executed)
                          )
                          rest

  inspectExpectedImage spec = do
    let command = kindImageInspectSubprocess substrate (repoAppImageTag spec)
        label = renderSubprocess command
    outcome <- runStreaming defaultSubprocessEnv command
    pure $
      case outcome of
        ProcessFailed failure -> Left (LiveStepProcessFailure label failure)
        ProcessSucceeded transcript ->
          case eitherDecode
            (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
            Right (Object root)
              | Just (Object status) <- KeyMap.lookup "status" root
              , Just (String imageId) <- KeyMap.lookup "id" status
              , not (Text.null (Text.strip imageId)) ->
                  Right (Text.strip imageId, label)
            _ -> Left (LiveStepInvalidResult label "missing status.id image identity" transcript)

  inspectExpectedReplicas spec = do
    let command = appDeploymentReplicaCountSubprocess (repoAppDeployment spec)
        label = renderSubprocess command
    outcome <- runStreaming defaultSubprocessEnv command
    pure $
      case outcome of
        ProcessFailed failure -> Left (LiveStepProcessFailure label failure)
        ProcessSucceeded transcript ->
          case reads (Text.unpack (Text.strip (processTranscriptStdout transcript))) of
            [(replicaCount, "")]
              | replicaCount > 0 -> Right (replicaCount, label)
            _ -> Left (LiveStepInvalidResult label "missing positive spec.replicas" transcript)

  inspectObservedImages spec = do
    let command = appPodEvidenceSubprocess (repoAppLabel spec)
        label = renderSubprocess command
    outcome <- runStreaming defaultSubprocessEnv command
    pure $
      case outcome of
        ProcessFailed failure -> Left (LiveStepProcessFailure label failure)
        ProcessSucceeded transcript ->
          case parseAppPodImageEvidence (processTranscriptStdout transcript) of
            Just evidence -> Right (evidence, label)
            Nothing ->
              Left
                ( LiveStepInvalidResult
                    label
                    "app pod evidence is not valid Kubernetes PodList JSON"
                    transcript
                )

  rollAndVerify spec expectedReplicas expectedImageId = do
    restartOutcome <- runStreaming defaultSubprocessEnv restartCommand
    case restartOutcome of
      ProcessFailed failure ->
        pure (Left (LiveStepProcessFailure (renderSubprocess restartCommand) failure))
      ProcessSucceeded _ -> do
        statusOutcome <- runStreaming defaultSubprocessEnv statusCommand
        case statusOutcome of
          ProcessFailed failure ->
            pure (Left (LiveStepProcessFailure (renderSubprocess statusCommand) failure))
          ProcessSucceeded _ ->
            pollForStablePodSet 60
   where
    restartCommand = appRolloutRestartSubprocess (repoAppDeployment spec)
    statusCommand = appRolloutStatusSubprocess (repoAppDeployment spec)

    pollForStablePodSet attemptsRemaining = do
      verified <- inspectObservedImages spec
      case verified of
        Left failure -> pure (Left failure)
        Right (observedEvidence, observedLabel) ->
          case appPodImagePollDecision
            expectedReplicas
            expectedImageId
            attemptsRemaining
            observedEvidence of
            AppPodImageConverged ->
              pure $
                Right
                  [ renderSubprocess restartCommand
                  , renderSubprocess statusCommand
                  , observedLabel
                  ]
            AppPodImageRetry -> do
              threadDelay 500000
              pollForStablePodSet (attemptsRemaining - 1)
            AppPodImageExhausted ->
              pure $
                Left
                  ( LiveStepInvariantFailure
                      ("app image reconcile " <> repoAppDeployment spec)
                      ( "expected a stable set of "
                          <> Text.pack (show expectedReplicas)
                          <> " ready pods at "
                          <> expectedImageId
                          <> ", observed "
                          <> Text.pack (show observedEvidence)
                      )
                  )

-- | Live phased rollout executor. Runs the typed
-- `kindCreateSubprocess` + Helm phases + Docker build / Kind image-load phase
-- through the typed `runStreaming` boundary. The rollout stops at the first
-- failed step so later phases cannot mask a missing image or broken prerequisite.
-- The App tier invokes this directly for a substrate bootstrap command after
-- handling explicit plan/dry-run output.
liveExecutePhasedRollout :: Substrate -> FilePath -> IO LiveExecutionResult
liveExecutePhasedRollout substrate chartPath = do
  resources <- loadClusterResourcesOrDefault "."
  presenceOutcome <- probeKindClusterPresenceIO substrate
  case presenceOutcome of
    Left failure ->
      pure $
        LiveExecutionResult
          { liveStepsExecuted = [renderSubprocess kindGetClustersSubprocess]
          , liveStepsFailed = [failure]
          , livePublication = defaultPublication substrate
          , liveAlreadyConverged = False
          }
    Right presence -> do
      recoveryOutcome <- selectLiveKindRecovery "." substrate presence
      case recoveryOutcome of
        Left failure ->
          pure $
            LiveExecutionResult
              { liveStepsExecuted = [renderSubprocess kindGetClustersSubprocess]
              , liveStepsFailed = [failure]
              , livePublication = defaultPublication substrate
              , liveAlreadyConverged = False
              }
        Right (kindAction, lease, publication) -> do
          let port = EdgePort.leasedPort lease
          materializationChanged <-
            materializeBootstrapFilesForPort "." substrate port
          convergence <-
            observeLiveConvergenceIO
              "."
              substrate
              resources
              kindAction
              port
              materializationChanged
          case convergence of
            LiveClusterAlreadyConverged currentPublication ->
              pure $
                LiveExecutionResult
                  { liveStepsExecuted =
                      [ renderSubprocess kindGetClustersSubprocess
                      , "cluster convergence observation: already converged"
                      ]
                  , liveStepsFailed = []
                  , livePublication = currentPublication
                  , liveAlreadyConverged = True
                  }
            LiveClusterNeedsReconcile reason -> do
              -- Invalidate prior live evidence only after retained coordinates,
              -- port-aware materialization, and the read-only convergence
              -- decision are complete. A failed apply retains retryable
              -- coordinates without advertising stale readiness.
              _ <- writeLivePublication "." publication
              executeRequiredReconcile
                resources
                kindAction
                lease
                publication
                reason
 where
  executeRequiredReconcile resources kindAction lease publication reason = do
    let port = EdgePort.leasedPort lease
        probeExecuted =
          [ renderSubprocess kindGetClustersSubprocess
          , "cluster convergence drift: " <> reason
          , "cluster publication marked reconciling"
          ]
    prepareKindKubeconfigFiles substrate
    -- Sprint 2.9: skip `helm dependency build` when every subchart `.tgz` is
    -- already present in `chart/charts/` (the previous `sh -c` did this in
    -- shell). The typed subprocess is still in the rendered plan for
    -- visibility; this filter only affects live execution.
    preGrantSubs <-
      filterCachedThirdPartyImageLoads
        =<< filterHelmDepBuildWhenArchivesPresent
          chartPath
          (livePreGrantSubprocessesForPort substrate port resources chartPath)
    case preGrantSubs of
      [] -> runAfterPreGrant resources port publication probeExecuted
      kindSub : remainingPreGrantSubs -> do
        (kindExecuted, kindFailure) <-
          case kindAction of
            CreateLiveKindCluster -> runStepList [kindSub]
            ReuseLiveKindCluster ->
              pure
                (
                  [ "kind cluster "
                      <> substrateClusterName substrate
                      <> " already present; create skipped"
                  ]
                , Nothing
                )
        case kindFailure of
          Just failure ->
            pure $
              LiveExecutionResult
                { liveStepsExecuted = probeExecuted <> kindExecuted
                , liveStepsFailed = [failure]
                , livePublication = publication
                , liveAlreadyConverged = False
                }
          Nothing -> do
            kubeconfigOutcome <- writeKindKubeconfigIO substrate
            let kubeconfigLabel = "kind kubeconfig export"
            case kubeconfigOutcome of
              Left err ->
                pure $
                  LiveExecutionResult
                    { liveStepsExecuted =
                        probeExecuted <> kindExecuted <> [kubeconfigLabel]
                    , liveStepsFailed = [err]
                    , livePublication = publication
                    , liveAlreadyConverged = False
                    }
              Right () -> do
                (preRestExecuted, preFailure) <- runStepList remainingPreGrantSubs
                let preExecuted =
                      probeExecuted
                        <> kindExecuted
                        <> [kubeconfigLabel]
                        <> preRestExecuted
                case preFailure of
                  Just failure ->
                    pure $
                      LiveExecutionResult
                        { liveStepsExecuted = preExecuted
                        , liveStepsFailed = [failure]
                        , livePublication = publication
                        , liveAlreadyConverged = False
                        }
                  Nothing -> runAfterPreGrant resources port publication preExecuted

  runAfterPreGrant resources port publication preExecuted = do
    bucketsOutcome <- runMinioBucketReadinessIO
    let bucketsLabel = "minio bucket readiness"
    case bucketsOutcome of
      Left err ->
        pure $
          LiveExecutionResult
            { liveStepsExecuted = preExecuted <> [bucketsLabel]
            , liveStepsFailed = [LiveStepProcessFailure bucketsLabel err]
            , livePublication = publication
            , liveAlreadyConverged = False
            }
      Right () -> do
        grantOutcome <- runPostgresSchemaGrantsIO
        let grantLabel = "postgres schema grant"
        case grantOutcome of
          Left err ->
            pure $
              LiveExecutionResult
                { liveStepsExecuted = preExecuted <> [bucketsLabel, grantLabel]
                , liveStepsFailed = [err]
                , livePublication = publication
                , liveAlreadyConverged = False
                }
          Right () -> do
            postGrantSubs <-
              filterDockerBuildWhenImageExists
                (livePostGrantApplySubprocessesForPort substrate port chartPath)
            (postExecuted, postFailure) <- runStepList postGrantSubs
            let prePostExecuted = preExecuted <> [bucketsLabel, grantLabel] <> postExecuted
            case postFailure of
              Just failure ->
                pure $
                  LiveExecutionResult
                    { liveStepsExecuted = prePostExecuted
                    , liveStepsFailed = [failure]
                    , livePublication = publication
                    , liveAlreadyConverged = False
                    }
              Nothing -> do
                imageReconcile <- runRepoAppImageReconcileIO substrate
                case imageReconcile of
                  Left failure ->
                    pure $
                      LiveExecutionResult
                        { liveStepsExecuted = prePostExecuted <> ["app image reconcile"]
                        , liveStepsFailed = [failure]
                        , livePublication = publication
                        , liveAlreadyConverged = False
                        }
                  Right imageExecuted -> do
                    let reconciledExecuted = prePostExecuted <> imageExecuted
                    (readinessExecuted, readinessFailure) <-
                      runStepList (livePostGrantReadinessSubprocesses port)
                    let reverifiedExecuted = reconciledExecuted <> readinessExecuted
                    case readinessFailure of
                      Just failure ->
                        pure $
                          LiveExecutionResult
                            { liveStepsExecuted = reverifiedExecuted
                            , liveStepsFailed = [failure]
                            , livePublication = publication
                            , liveAlreadyConverged = False
                            }
                      Nothing ->
                        finishLivePublication resources publication reverifiedExecuted

  finishLivePublication resources publication executed = do
    topicsOutcome <- runPulsarTopicCreatesIO
    let topicsLabel = "pulsar topic create"
        allExecuted = executed <> [topicsLabel]
    case topicsOutcome of
      Left (PulsarBootstrap.TopicCreateFailed _topic err) ->
        pure $
          LiveExecutionResult
            { liveStepsExecuted = allExecuted
            , liveStepsFailed = [LiveStepProcessFailure topicsLabel err]
            , livePublication = publication
            , liveAlreadyConverged = False
            }
      Left (PulsarBootstrap.InvalidTopicFamilyEvidence evidenceError) ->
        pure $
          LiveExecutionResult
            { liveStepsExecuted = allExecuted
            , liveStepsFailed =
                [ LiveStepInvariantFailure
                    topicsLabel
                    ("invalid Coordinator topic family: " <> Text.pack (show evidenceError))
                ]
            , livePublication = publication
            , liveAlreadyConverged = False
            }
      Right _evidence -> do
        measuredPublication <- measureLivePublication publication
        let publicationLabel = "cluster publication readiness"
            measuredExecuted = allExecuted <> [publicationLabel]
        if publicationHasLiveEvidence measuredPublication
          then do
            stampResult <-
              buildExpectedReconcileStampIO
                "."
                substrate
                (publicationEdgePort measuredPublication)
            case stampResult of
              Left failure ->
                pure $
                  LiveExecutionResult
                    { liveStepsExecuted = measuredExecuted <> ["cluster reconcile stamp"]
                    , liveStepsFailed = [failure]
                    , livePublication = measuredPublication
                    , liveAlreadyConverged = False
                    }
              Right stamp -> do
                releaseEvidence <- releaseConvergenceEvidenceIO
                topicEvidence <- topicConvergenceEvidenceIO
                let expectedImageIds = reconcileStampRepoAppImageIds stamp
                (nodeImageEvidence, liveConfigImageIds) <-
                  nodeImageConvergenceEvidenceIO substrate resources expectedImageIds
                appImageEvidence <-
                  appImageConvergenceEvidenceIO substrate liveConfigImageIds
                let postReconcileObservation =
                      ReconcileObservation
                        { reconcileExpectedStamp = stamp
                        , reconcilePersistedStamp = Just stamp
                        , reconcileLivePublication = LivePublicationReady
                        , reconcileReleaseEvidence = releaseEvidence
                        , reconcileReadinessEvidence =
                            readinessConvergenceEvidence measuredPublication
                        , reconcileTopicEvidence = topicEvidence
                        , reconcileNodeImageEvidence = nodeImageEvidence
                        , reconcileAppImageEvidence = appImageEvidence
                        , reconcilePortAwareMaterializationUnchanged = True
                        }
                    proofLabel = "post-reconcile convergence proof"
                    proofExecuted = measuredExecuted <> [proofLabel]
                case classifyReconcileObservation postReconcileObservation of
                  NeedsReconcile reasons ->
                    pure $
                      LiveExecutionResult
                        { liveStepsExecuted = proofExecuted
                        , liveStepsFailed =
                            [ LiveStepInvariantFailure
                                proofLabel
                                (Text.pack (show reasons))
                            ]
                        , livePublication = measuredPublication
                        , liveAlreadyConverged = False
                        }
                  AlreadyConverged -> do
                    _ <- writeLivePublication "." measuredPublication
                    _ <- writeReconcileStamp "." stamp
                    pure $
                      LiveExecutionResult
                        { liveStepsExecuted = proofExecuted <> ["cluster reconcile stamp"]
                        , liveStepsFailed = []
                        , livePublication = measuredPublication
                        , liveAlreadyConverged = False
                        }
          else
            pure $
              LiveExecutionResult
                { liveStepsExecuted = measuredExecuted
                , liveStepsFailed =
                    [ LiveStepInvariantFailure
                        publicationLabel
                        (renderIncompletePublication measuredPublication)
                    ]
                , livePublication = measuredPublication
                , liveAlreadyConverged = False
                }

  runStepList :: [Subprocess] -> IO ([Text], Maybe LiveStepFailure)
  runStepList = go []
   where
    go executed [] = pure (reverse executed, Nothing)
    go executed (subprocessValue : rest) = do
      let rendered = renderSubprocess subprocessValue
      outcome <- runStreaming defaultSubprocessEnv subprocessValue
      case outcome of
        ProcessSucceeded _ -> go (rendered : executed) rest
        ProcessFailed failure
          | isCachedThirdPartyImageLoad subprocessValue ->
              go
                ( ( rendered
                      <> " (optional warm-cache load skipped after:\n"
                      <> renderProcessFailure failure
                      <> ")"
                  )
                    : executed
                )
                rest
        ProcessFailed failure ->
          pure
            ( reverse (rendered : executed)
            , Just (LiveStepProcessFailure rendered failure)
            )

prepareKindKubeconfigFiles :: Substrate -> IO ()
prepareKindKubeconfigFiles substrate = do
  createDirectoryIfMissing True ".build"
  removeIfExists (".build" </> "jitml.kubeconfig.lock")
  removeIfExists (kindCreateKubeconfigPath substrate <> ".lock")
 where
  removeIfExists path = do
    pathExists <- doesFileExist path
    when pathExists (removeFile path)

probeKindClusterPresenceIO
  :: Substrate
  -> IO (Either LiveStepFailure KindClusterPresence)
probeKindClusterPresenceIO substrate =
  resolveKindClusterPresence substrate
    <$> runStreaming defaultSubprocessEnv kindGetClustersSubprocess

-- | Refine the typed @kind get clusters@ outcome into exact target-cluster
-- presence. Cluster names are compared as complete trimmed lines so a
-- similarly prefixed cluster cannot accidentally suppress creation.
resolveKindClusterPresence
  :: Substrate
  -> ProcessOutcome
  -> Either LiveStepFailure KindClusterPresence
resolveKindClusterPresence substrate outcome =
  case outcome of
    ProcessFailed failure ->
      Left
        ( LiveStepProcessFailure
            (renderSubprocess kindGetClustersSubprocess)
            failure
        )
    ProcessSucceeded transcript ->
      Right $
        if substrateClusterName substrate `elem` clusterNames transcript
          then KindClusterPresent
          else KindClusterAbsent
 where
  clusterNames =
    filter
      ( \name ->
          not (Text.null name)
            && name /= "No kind clusters found."
      )
      . fmap Text.strip
      . Text.lines
      . processTranscriptStdout

writeKindKubeconfigIO :: Substrate -> IO (Either LiveStepFailure ())
writeKindKubeconfigIO substrate = do
  outcome <-
    runStreaming
      defaultSubprocessEnv
      (subprocess "kind" ["get", "kubeconfig", "--name", substrateClusterName substrate])
  case outcome of
    ProcessFailed failure ->
      pure (Left (LiveStepProcessFailure "kind get kubeconfig" failure))
    ProcessSucceeded transcript ->
      if Text.null (Text.strip (processTranscriptStdout transcript))
        then
          pure
            ( Left
                (LiveStepInvalidResult "kind get kubeconfig" "empty kubeconfig" transcript)
            )
        else do
          createDirectoryIfMissing True ".build"
          Text.IO.writeFile
            (".build" </> "jitml.kubeconfig")
            (processTranscriptStdout transcript)
          pure (Right ())

data ExistingPublicationState
  = ExistingPublicationMissing
  | ExistingPublicationInvalid Text
  | ExistingPublicationValid ClusterPublication

-- | Select the create/reuse path and its fixed edge coordinate before any
-- rollout mutation. A retained Kind cluster already owns its host-port
-- mapping, so it must recover that exact port from a matching persisted
-- publication; probing the occupied port as though it were a fresh lease
-- would incorrectly select a different coordinate. Both an earlier live
-- publication and an evidence-free interrupted-rollout publication are valid
-- coordinate authorities. A fresh cluster retains the established
-- bindability-based lease behavior.
--
-- On success this function atomically writes an evidence-free recovery
-- publication before the caller mutates the cluster. A failed rollout
-- therefore cannot leave stale live evidence behind, but its fixed edge port
-- remains available to the next retained-cluster retry.
prepareLiveKindRecovery
  :: FilePath
  -> Substrate
  -> KindClusterPresence
  -> IO
       ( Either
           LiveStepFailure
           (LiveKindAction, EdgePort.EdgePortLease, ClusterPublication)
       )
prepareLiveKindRecovery root substrate presence =
  do
    prepared <- selectLiveKindRecovery root substrate presence
    case prepared of
      Left failure -> pure (Left failure)
      Right recovered@(_, _, publication) -> do
        _ <- writeLivePublication root publication
        pure (Right recovered)

-- | Resolve a fresh or retained Kind cluster to one live action, edge lease,
-- and fail-closed recovery publication without mutating the publication file.
-- Phase 3 uses this non-mutating half to perform port-aware materialization and
-- convergence observation before it decides whether a rollout is needed.
selectLiveKindRecovery
  :: FilePath
  -> Substrate
  -> KindClusterPresence
  -> IO
       ( Either
           LiveStepFailure
           (LiveKindAction, EdgePort.EdgePortLease, ClusterPublication)
       )
selectLiveKindRecovery root substrate presence =
  case presence of
    KindClusterAbsent -> do
      lease <- selectLiveLease root substrate
      pure
        ( Right
            ( CreateLiveKindCluster
            , lease
            , recoveryPublication substrate lease
            )
        )
    KindClusterPresent -> do
      existing <- readExistingPublicationState root
      pure $ do
        publication <-
          case existing of
            ExistingPublicationMissing ->
              Left
                ( recoveryFailure
                    "matching Kind cluster exists, but cluster-publication.json is missing; the fixed host edge port cannot be recovered safely"
                )
            ExistingPublicationInvalid decodeError ->
              Left
                ( recoveryFailure
                    ( "matching Kind cluster exists, but cluster-publication.json is invalid: "
                        <> decodeError
                    )
                )
            ExistingPublicationValid publication ->
              Right publication
        lease <- recoverExistingKindLease substrate publication
        Right
          ( ReuseLiveKindCluster
          , lease
          , recoveryPublication substrate lease
          )
 where
  recoveryFailure =
    LiveStepInvariantFailure
      ("kind cluster recovery " <> substrateClusterName substrate)

recoveryPublication
  :: Substrate
  -> EdgePort.EdgePortLease
  -> ClusterPublication
recoveryPublication substrate lease =
  (publicationWithLeasedPort lease (defaultPublication substrate))
    { publicationComponents =
        fmap (,"reconciling") (requiredPublicationComponents substrate)
    , publicationEvidence = Nothing
    }

recoverExistingKindLease
  :: Substrate
  -> ClusterPublication
  -> Either LiveStepFailure EdgePort.EdgePortLease
recoverExistingKindLease substrate publication
  | publicationSubstrate publication /= substrate =
      Left
        ( recoveryFailure
            ( "persisted publication substrate is "
                <> renderSubstrate (publicationSubstrate publication)
                <> ", expected "
                <> renderSubstrate substrate
            )
        )
  | publicationEdgePort publication < 1 || publicationEdgePort publication > 65535 =
      Left
        ( recoveryFailure
            ( "persisted publication edge port is outside 1..65535: "
                <> Text.pack (show (publicationEdgePort publication))
            )
        )
  | publicationPulsarUrl publication /= publicationPulsarUrl expectedPublication =
      Left
        ( recoveryFailure
            "persisted publication Pulsar URL does not match its loopback edge port"
        )
  | publicationMinioUrl publication /= publicationMinioUrl expectedPublication =
      Left
        ( recoveryFailure
            "persisted publication MinIO URL does not match its loopback edge port"
        )
  | otherwise = Right lease
 where
  lease =
    EdgePort.EdgePortLease
      { EdgePort.leasedPort = publicationEdgePort publication
      , EdgePort.leasedHost = "127.0.0.1"
      }
  expectedPublication =
    publicationWithLeasedPort lease (defaultPublication substrate)
  recoveryFailure =
    LiveStepInvariantFailure
      ("kind cluster recovery " <> substrateClusterName substrate)

-- | Sprint 2.9 — replaces the original @sh -c "if test -f ...; then exit 0;
-- else helm dependency build ...; fi"@ heuristic with a typed Haskell
-- existence check. When every subchart @.tgz@ Helm would download is already
-- present in @chart/charts/@, the helm-dependency-build subprocess is filtered
-- out of the live rollout (it would otherwise fail in a fresh container that
-- has no @helm repo@ definitions). The rendered plan is unchanged so the
-- LivePlan and unit tests still observe the typed subprocess.
filterHelmDepBuildWhenArchivesPresent :: FilePath -> [Subprocess] -> IO [Subprocess]
filterHelmDepBuildWhenArchivesPresent chartPath subs = do
  let archivePaths =
        fmap (\pkg -> chartPath </> "charts" </> Text.unpack pkg) dependencyPackages
  present <- traverse doesFileExist archivePaths
  pure $
    if and present
      then filter (not . isHelmDepBuild) subs
      else subs
 where
  isHelmDepBuild s =
    subprocessPath s == "helm"
      && take 2 (subprocessArguments s) == ["dependency", "build"]

filterCachedThirdPartyImageLoads :: [Subprocess] -> IO [Subprocess]
filterCachedThirdPartyImageLoads =
  filterM keep
 where
  keep sub =
    case cachedThirdPartyImageFromLoad sub of
      Nothing -> pure True
      Just tag -> imageExistsLocally tag

cachedThirdPartyImageFromLoad :: Subprocess -> Maybe Text
cachedThirdPartyImageFromLoad sub =
  case subprocessArguments sub of
    ["load", "docker-image", tag, "--name", _]
      | subprocessPath sub == "kind" && tag `elem` cachedThirdPartyRolloutImages ->
          Just tag
    _ -> Nothing

isCachedThirdPartyImageLoad :: Subprocess -> Bool
isCachedThirdPartyImageLoad = isJust . cachedThirdPartyImageFromLoad

-- | Repo-owned images must be rebuilt during bootstrap by default. A stale
-- `jitml:local` tag can otherwise leave the live daemon running old code while
-- the worktree and host binary are current. Third-party warm-cache image loads
-- are still filtered separately by `filterCachedThirdPartyImageLoads`.
--
-- Escape hatch for resource-constrained hosts: when
-- @JITML_BOOTSTRAP_SKIP_IMAGE_BUILD@ is set (@1@/@true@/@yes@) and a local
-- @jitml:local@ image already exists, the in-rollout @docker build@ is filtered
-- out so the bootstrap reuses a pre-built image (the subsequent @kind load@
-- still runs). This lets a host whose RAM cannot compile the project in-place
-- while the cluster is running pre-build the image with the cluster down, then
-- bootstrap against it. The default (env unset) is unchanged: always rebuild.
filterDockerBuildWhenImageExists :: [Subprocess] -> IO [Subprocess]
filterDockerBuildWhenImageExists subs = do
  skipRequested <- lookupEnv "JITML_BOOTSTRAP_SKIP_IMAGE_BUILD"
  case fmap (Text.toLower . Text.pack) skipRequested of
    Just flag
      | flag `elem` ["1", "true", "yes"] -> do
          imagePresent <- imageExistsLocally "jitml:local"
          pure $ if imagePresent then filter (not . isDockerBuildStep) subs else subs
    _ -> pure subs
 where
  isDockerBuildStep s =
    subprocessPath s == "docker"
      && take 1 (subprocessArguments s) == ["build"]

imageExistsLocally :: Text -> IO Bool
imageExistsLocally tag = do
  let probe =
        subprocess "docker" ["image", "inspect", tag]
  outcome <- runStreaming defaultSubprocessEnv probe
  case outcome of
    ProcessSucceeded _ -> pure True
    -- A non-zero @docker image inspect@ is the command's documented
    -- not-present result, not an execution error. No diagnostic is consumed
    -- by this Boolean existence probe.
    ProcessFailed _ -> pure False

selectLiveLease :: FilePath -> Substrate -> IO EdgePort.EdgePortLease
selectLiveLease root substrate = do
  existing <- readExistingPublicationState root
  fromMaybe defaultLease <$> EdgePort.leaseEdgePort (candidatePorts existing)
 where
  candidatePorts existing =
    uniquePorts $
      existingPublicationPorts existing
        <> [substrateEdgePort substrate]
        <> EdgePort.defaultPortCandidates

  existingPublicationPorts (ExistingPublicationValid publication) =
    case recoverExistingKindLease substrate publication of
      Right lease -> [EdgePort.leasedPort lease]
      Left _ -> []
  existingPublicationPorts _ = []

  uniquePorts = go []
   where
    go _ [] = []
    go seen (port : rest)
      | port `elem` seen = go seen rest
      | otherwise = port : go (port : seen) rest

  defaultLease =
    EdgePort.EdgePortLease
      { EdgePort.leasedPort = substrateEdgePort substrate
      , EdgePort.leasedHost = "127.0.0.1"
      }

readExistingLivePublication :: FilePath -> IO (Maybe ClusterPublication)
readExistingLivePublication root = do
  state <- readExistingPublicationState root
  pure $
    case state of
      ExistingPublicationValid publication
        | publicationHasLiveEvidence publication -> Just publication
      _ -> Nothing

readExistingPublicationState :: FilePath -> IO ExistingPublicationState
readExistingPublicationState root = do
  let path = root </> ".build" </> "runtime" </> "cluster-publication.json"
  exists <- doesFileExist path
  if exists
    then do
      bytes <- LazyByteString.readFile path
      pure $
        case eitherDecode bytes of
          Left decodeError ->
            ExistingPublicationInvalid (Text.pack decodeError)
          Right publication ->
            ExistingPublicationValid publication
    else pure ExistingPublicationMissing

newtype HelmStatus = HelmStatus Text
  deriving stock (Eq, Show)

instance FromJSON HelmStatus where
  parseJSON =
    withObject "HelmStatus" $ \objectValue -> do
      infoValue <- objectValue .: "info"
      withObject "HelmInfo" (\infoObject -> HelmStatus <$> infoObject .: "status") infoValue

data PublicationHealthCheck
  = HelmPublicationHealthCheck Text [Text]
  | SubprocessPublicationHealthCheck Text Subprocess

measureLivePublication :: ClusterPublication -> IO ClusterPublication
measureLivePublication publication = do
  components <- traverse measurePublicationHealthCheck (publicationHealthChecks publication)
  pure $
    markPublicationLive
      publication
        { publicationComponents = components
        , publicationEvidence = Nothing
        }

publicationHealthChecks :: ClusterPublication -> [PublicationHealthCheck]
publicationHealthChecks publication =
  [ -- The registry is a template in this chart rather than a dependency
    -- release, so its health is a rollout status rather than a Helm release
    -- listing. The Postgres check left with Harbor, which was its only user.
    SubprocessPublicationHealthCheck
      "registry"
      (Readiness.rolloutStatusSubprocess "deployment/registry")
  , HelmPublicationHealthCheck "minio" ["minio"]
  , HelmPublicationHealthCheck "pulsar" ["pulsar"]
  , HelmPublicationHealthCheck
      "observability"
      ["kube-prometheus-stack", "tensorboard", "envoy-gateway"]
  ]
    <> engineHealthChecks
    <> [ SubprocessPublicationHealthCheck
           "jitml-coordinator"
           (Readiness.rolloutStatusSubprocess "deployment/jitml-coordinator")
       , HelmPublicationHealthCheck "jitml-demo" ["jitml-demo"]
       , SubprocessPublicationHealthCheck
           "edge"
           (publicReadyzSubprocessForPort (publicationEdgePort publication))
       ]
 where
  engineHealthChecks =
    [engineHealthCheck | substrateHasClusterCompute (publicationSubstrate publication)]
  engineHealthCheck =
    SubprocessPublicationHealthCheck
      "jitml-engine"
      (Readiness.rolloutStatusSubprocess "deployment/jitml-service")

measurePublicationHealthCheck :: PublicationHealthCheck -> IO (Text, Text)
measurePublicationHealthCheck healthCheck =
  case healthCheck of
    HelmPublicationHealthCheck componentName releases ->
      measureComponent (componentName, releases)
    SubprocessPublicationHealthCheck componentName readinessSubprocess ->
      measureSubprocessComponent componentName readinessSubprocess

measureSubprocessComponent :: Text -> Subprocess -> IO (Text, Text)
measureSubprocessComponent componentName readinessSubprocess = do
  outcome <- runStreaming defaultSubprocessEnv readinessSubprocess
  pure $
    case outcome of
      ProcessSucceeded _ -> (componentName, "ready")
      ProcessFailed failure ->
        (componentName, "not-ready:\n" <> renderProcessFailure failure)

renderIncompletePublication :: ClusterPublication -> Text
renderIncompletePublication publication =
  "required component readiness is incomplete; required exactly once and ready: "
    <> Text.intercalate "," (requiredPublicationComponents (publicationSubstrate publication))
    <> "; measured: "
    <> Text.intercalate
      ","
      [name <> "=" <> status | (name, status) <- publicationComponents publication]

measureComponent :: (Text, [Text]) -> IO (Text, Text)
measureComponent (componentName, releases) = do
  releaseStatuses <- traverse measureHelmRelease releases
  pure (componentName, componentStatus releaseStatuses)

measureHelmRelease :: Text -> IO (Text, Text)
measureHelmRelease release = do
  outcome <-
    runStreaming defaultSubprocessEnv (helmStatusSubprocess release)
  case outcome of
    ProcessSucceeded transcript ->
      pure (release, parseHelmStatus (processTranscriptStdout transcript))
    ProcessFailed failure ->
      pure (release, "unavailable:\n" <> renderProcessFailure failure)

componentStatus :: [(Text, Text)] -> Text
componentStatus releaseStatuses
  | all ((== "deployed") . snd) releaseStatuses = "ready"
  | otherwise =
      "not-ready:"
        <> Text.intercalate "," (fmap renderReleaseStatus releaseStatuses)
 where
  renderReleaseStatus (release, status) =
    release <> "=" <> status

parseHelmStatus :: Text -> Text
parseHelmStatus stdoutText =
  case eitherDecode (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 stdoutText)) of
    Right (HelmStatus status) -> status
    Left _ -> "unknown"

helmStatusSubprocess :: Text -> Subprocess
helmStatusSubprocess release =
  subprocess
    "helm"
    [ "status"
    , release
    , "--namespace"
    , "platform"
    , "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "--output"
    , "json"
    ]

writeLivePublication :: FilePath -> ClusterPublication -> IO Bool
writeLivePublication root publication = do
  let runtimeRoot = root </> ".build" </> "runtime"
  createDirectoryIfMissing True runtimeRoot
  writeLazyByteStringIfChanged (runtimeRoot </> "cluster-publication.json") (encode publication)

writeTextFileIfChanged :: FilePath -> Text -> IO Bool
writeTextFileIfChanged path expected = do
  exists <- doesFileExist path
  current <-
    if exists
      then Text.IO.readFile path
      else pure ""
  if current == expected
    then pure False
    else do
      createDirectoryIfMissing True (takeDirectory path)
      let tmpPath = path <> ".tmp"
      Text.IO.writeFile tmpPath expected
      renameFile tmpPath path
      pure True

writeLazyByteStringIfChanged :: FilePath -> LazyByteString.ByteString -> IO Bool
writeLazyByteStringIfChanged path expected = do
  exists <- doesFileExist path
  current <-
    if exists
      then LazyByteString.readFile path
      else pure ""
  if current == expected
    then pure False
    else do
      let tmpPath = path <> ".tmp"
      LazyByteString.writeFile tmpPath expected
      renameFile tmpPath path
      pure True

removeFileIfExists :: FilePath -> IO Bool
removeFileIfExists path = do
  exists <- doesFileExist path
  if exists
    then do
      removeFile path
      pure True
    else pure False

-- | Sprint 3.2 (reopened) — delete any @chart/templates/pv-*.yaml@ file that
-- does not correspond to a current 'ManualPV'. When the manualPVs registry
-- shrinks (e.g., MinIO distributed→standalone), the orphaned PV manifests
-- would lint-fail with "manual PV must declare claimRef". Returns one 'Bool'
-- per file actually deleted so the caller's change-detection 'or' reports a
-- materialization change.
sweepStalePvManifests :: FilePath -> [ManualPV] -> IO [Bool]
sweepStalePvManifests chartTemplatesRoot currentPVs = do
  let expected = fmap pvManifestName currentPVs
  entries <- listDirectory chartTemplatesRoot
  let stale =
        [ entry
        | entry <- entries
        , "pv-" `isPrefixOf` entry
        , ".yaml" `isSuffixOf` entry
        , entry `notElem` expected
        ]
  traverse (\entry -> removeFileIfExists (chartTemplatesRoot </> entry)) stale
