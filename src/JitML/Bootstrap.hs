{-# LANGUAGE OverloadedStrings #-}

module JitML.Bootstrap
  ( LiveExecutionResult (..)
  , bootstrapPlanSteps
  , hostBootConfigForPublication
  , livePhasedRolloutSubprocesses
  , liveExecutePhasedRollout
  , materializeBootstrapFiles
  , readExistingLivePublication
  , selectLiveLease
  )
where

import Control.Monad (filterM, when)
import Data.Aeson (FromJSON (..), eitherDecode, encode, withObject, (.:))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (isPrefixOf, isSuffixOf)
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , listDirectory
  , removeFile
  , renameFile
  )
import System.Exit (ExitCode (..))
import System.FilePath ((</>))

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
  , kindCreateKubeconfigPath
  , kindCreateSubprocess
  , phasedReleases
  , releaseName
  , renderHelmDependencyBuildPlan
  )
import JitML.Cluster.Kind (kindConfigFor, kindConfigForEdgePort, renderKindConfig)
import JitML.Cluster.PostgresRegistry
  ( PerconaPGCluster (..)
  , postgresRegistry
  , renderPerconaPGCluster
  )
import JitML.Cluster.Publication
  ( ClusterPublication (..)
  , defaultPublication
  , publicationWithLeasedPort
  )
import JitML.Cluster.PulsarBootstrap (runPulsarTopicCreatesIO)
import JitML.Cluster.Readiness (platformReadinessSubprocesses, runMinioBucketReadinessIO)
import JitML.Cluster.Readiness qualified as Readiness
import JitML.Cluster.Resources
  ( ClusterResources
  , clusterNodeCapSubprocess
  , defaultClusterResources
  , loadClusterResourcesOrDefault
  , renderClusterResourcesDhall
  )
import JitML.Cluster.Storage
  ( ManualPV (..)
  , manualPVs
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
import JitML.Service.ConfigMap (renderServiceConfigMap, renderServiceDeployment, renderServiceRBAC)
import JitML.Service.LiveConfig (defaultLiveConfig, renderLiveConfigDhall)
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess
  ( Subprocess
  , subprocess
  , subprocessArguments
  , subprocessPath
  , subprocessWithStdin
  )
import JitML.Substrate (Substrate (..), renderSubstrate, substrateClusterName, substrateEdgePort)

bootstrapPlanSteps :: Substrate -> [Text]
bootstrapPlanSteps substrate =
  [ "reconcile prerequisite graph for cluster"
  , "render kind/cluster-" <> renderSubstrate substrate <> ".yaml"
  , "prepare Helm dependencies with " <> renderHelmDependencyBuildPlan "chart"
  , "create/export Kind kubeconfig and copy it to ./.build/jitml.kubeconfig"
  , "raise Kind-node inotify caps for multi-cluster host readiness"
  , "prepare substrate-specific Percona PV storage"
  , "apply jitml-manual StorageClass and manual PVs"
  , "install MinIO and Percona storage for Harbor"
  , "install Harbor bootstrap phase"
  , "build jitml:local and jitml-demo:local and load them into Kind"
  , "install Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
  , "write ./.build/runtime/cluster-publication.json"
  ]

materializeBootstrapFiles :: FilePath -> Substrate -> IO Bool
materializeBootstrapFiles root substrate = do
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
  results <-
    sequence
      [ writeTextFileIfChanged
          (kindRoot </> "cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml")
          (renderKindConfig (kindConfigFor substrate))
      , writeTextFileIfChanged (chartTemplatesRoot </> "storageclass-jitml-manual.yaml") renderStorageClass
      , writeTextFileIfChanged (chartTemplatesRoot </> "gatewayclass-jitml.yaml") renderGatewayClass
      , writeTextFileIfChanged
          (chartTemplatesRoot </> "gateway-jitml-edge.yaml")
          (renderGateway (substrateEdgePort substrate))
      , writeTextFileIfChanged (chartTemplatesRoot </> "envoyproxy-jitml-edge.yaml") $
          renderEnvoyProxy (substrateEdgePort substrate)
      ]
  pvResults <- traverse (materializePv chartTemplatesRoot) manualPVs
  -- Sprint 3.2 (reopened): when the manualPVs list shrinks (e.g., MinIO
  -- distributed→standalone), any chart/templates/pv-*.yaml files that no longer
  -- correspond to a registered PV would lint-fail with "manual PV must declare
  -- claimRef". Sweep stale PV manifests on materialize.
  stalePvResults <- sweepStalePvManifests chartTemplatesRoot manualPVs
  routeResults <- traverse (writeRoute chartTemplatesRoot) routeRegistry
  legacyValuesChanged <- removeFileIfExists (chartTemplatesRoot </> "minio-values.yaml")
  standaloneValuesChanged <- removeFileIfExists (chartRoot </> "minio-values.yaml")
  let clusterBoot = defaultBootConfig substrate Cluster
  clusterResources <- loadClusterResourcesOrDefault root
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
          renderServiceConfigMap clusterBoot defaultLiveConfig
      , writeTextFileIfChanged (chartTemplatesRoot </> "deployment-jitml-service.yaml") $
          renderServiceDeployment substrate
      , writeTextFileIfChanged (chartTemplatesRoot </> "rbac-jitml-service.yaml") renderServiceRBAC
      ]
  hostResults <- case substrate of
    AppleSilicon ->
      fmap (: []) $
        writeTextFileIfChanged (hostConfRoot </> "apple-silicon.dhall") $
          renderBootConfigDhall (hostBootConfigForPublication (defaultPublication AppleSilicon))
    _ -> pure []
  publicationChanged <-
    writeLazyByteStringIfChanged (runtimeRoot </> "cluster-publication.json") $
      encode (defaultPublication substrate)
  pure
    ( or
        ( results
            <> pvResults
            <> stalePvResults
            <> routeResults
            <> configResults
            <> hostResults
            <> [publicationChanged, legacyValuesChanged, standaloneValuesChanged]
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
  , liveStepsFailed :: [(Text, Text)]
  , livePublication :: ClusterPublication
  }
  deriving stock (Eq, Show)

livePhasedRolloutSubprocesses :: Substrate -> FilePath -> [Subprocess]
livePhasedRolloutSubprocesses substrate =
  livePhasedRolloutSubprocessesForPort substrate (substrateEdgePort substrate) defaultClusterResources

-- | Sprint 2.9 — the rollout splits in two around the postgres schema grant:
-- the pre-grant phase brings the operator + cluster up through readiness, then
-- the typed Haskell schema grant runs (replacing the former @sh -c@ that used
-- @$(kubectl ...)@ command substitution), then the post-grant phase continues
-- with Harbor through Pulsar topics. Each half is still a typed @[Subprocess]@
-- so the LivePlan/integration dry-run rendering is unchanged.
livePreGrantSubprocessesForPort :: Substrate -> Int -> ClusterResources -> FilePath -> [Subprocess]
livePreGrantSubprocessesForPort substrate edgePort resources chartPath =
  [ kindCreateSubprocess substrate kindConfigPath
  , kindNodeInotifyCapSubprocess substrate
  , kubectlRestartPodsByLabelSubprocess "kube-system" "k8s-app=kube-proxy"
  , kubectlRestartPodsByLabelSubprocess "local-path-storage" "app=local-path-provisioner"
  , clusterNodeCapSubprocess substrate resources
  , helmDependencyBuildSubprocess chartPath
  ]
    <> kindPreparePostgresPvSubprocesses substrate
    <> cachedThirdPartyImageLoadSteps substrate
    <> foundationManifestApplySubprocesses chartPath
    <> concatMap releaseSteps minioBootstrapReleases
    <> Readiness.minioBootstrapReadinessSubprocesses
    <> concatMap releaseSteps postgresOperatorReleases
    <> postgresClusterApplySubprocesses
    <> Readiness.postgresReadinessSubprocesses
 where
  kindConfigPath = "kind/cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml"
  releaseSteps release = [helmInstallSubprocessForEdgePort substrate edgePort release chartPath]
  postgresOperatorReleases = filter ((== "harbor-pg") . releaseName) phasedReleases
  minioBootstrapReleases = filter ((== "minio") . releaseName) phasedReleases

livePostGrantSubprocessesForPort :: Substrate -> Int -> FilePath -> [Subprocess]
livePostGrantSubprocessesForPort substrate edgePort chartPath =
  concatMap releaseSteps harborApplicationReleases
    <> mirrorBuildSteps substrate
    <> concatMap releaseSteps remainingReleases
    <> observabilityManifestApplySubprocesses chartPath
    <> platformReadinessSubprocesses
    <> edgeManifestApplySubprocesses chartPath
 where
  releaseSteps release = [helmInstallSubprocessForEdgePort substrate edgePort release chartPath]
  harborApplicationReleases = filter ((== "harbor") . releaseName) phasedReleases
  remainingReleases =
    filter
      ( \release ->
          releaseName release /= "harbor-pg"
            && releaseName release /= "harbor"
            && releaseName release /= "minio"
      )
      phasedReleases

livePhasedRolloutSubprocessesForPort
  :: Substrate -> Int -> ClusterResources -> FilePath -> [Subprocess]
livePhasedRolloutSubprocessesForPort substrate edgePort resources chartPath =
  livePreGrantSubprocessesForPort substrate edgePort resources chartPath
    <> livePostGrantSubprocessesForPort substrate edgePort chartPath

-- | The same Dockerfile produces both `jitml` and `jitml-demo`
-- binaries inside a single image, so build `jitml:local` once and
-- retag it as `jitml-demo:local` instead of running a second full
-- `docker build`. Both tags are then loaded into Kind so the local
-- charts can pull them by their distinct names.
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
  , "goharbor/harbor-core:v2.12.2"
  , "goharbor/harbor-jobservice:v2.12.2"
  , "goharbor/nginx-photon:v2.12.2"
  , "goharbor/harbor-portal:v2.12.2"
  , "goharbor/registry-photon:v2.12.2"
  , "goharbor/harbor-registryctl:v2.12.2"
  , "goharbor/redis-photon:v2.12.2"
  , "goharbor/trivy-adapter-photon:v2.12.2"
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

kindNodeInotifyCapSubprocess :: Substrate -> Subprocess
kindNodeInotifyCapSubprocess substrate =
  subprocess
    "docker"
    [ "exec"
    , substrateClusterName substrate <> "-control-plane"
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

kindNormalizePostgresPvOwnershipSubprocess :: Substrate -> Subprocess
kindNormalizePostgresPvOwnershipSubprocess substrate =
  subprocess
    "docker"
    ( [ "exec"
      , substrateClusterName substrate <> "-control-plane"
      , "chown"
      , "-R"
      , "26:26"
      ]
        <> fmap pvNodeDataPath postgresManualPVs
    )

kindPreparePostgresPvSubprocesses :: Substrate -> [Subprocess]
kindPreparePostgresPvSubprocesses AppleSilicon =
  [kindMountPostgresPvNodeLocalSubprocess AppleSilicon]
kindPreparePostgresPvSubprocesses substrate =
  [kindNormalizePostgresPvOwnershipSubprocess substrate]

kindMountPostgresPvNodeLocalSubprocess :: Substrate -> Subprocess
kindMountPostgresPvNodeLocalSubprocess substrate =
  subprocess
    "docker"
    [ "exec"
    , substrateClusterName substrate <> "-control-plane"
    , "sh"
    , "-c"
    , Text.unwords
        ( ["set -e;"]
            <> fmap mountOne postgresManualPVs
        )
    ]
 where
  mountOne pv =
    let nodePath = pvNodeDataPath pv
        localPath = "/var/local/jitml-postgres-pv" <> nodePath
     in Text.unwords
          [ "mkdir -p"
          , localPath
          , nodePath <> ";"
          , "mountpoint -q"
          , nodePath
          , "|| mount --bind"
          , localPath
          , nodePath <> ";"
          , "chown -R 26:26"
          , localPath <> ";"
          ]

postgresManualPVs :: [ManualPV]
postgresManualPVs =
  filter isPostgresPV manualPVs
 where
  isPostgresPV pv =
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
postgresSchemaGrantIO :: PerconaPGCluster -> IO (Either Text ())
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
  (getCode, getStdout, getStderr) <- runStreaming defaultSubprocessEnv getPodSub
  case getCode of
    ExitFailure _ ->
      pure (Left ("postgres get-primary " <> cn <> ": " <> getStderr))
    ExitSuccess ->
      let podName = Text.strip getStdout
       in if Text.null podName
            then pure (Left ("postgres get-primary " <> cn <> ": empty pod name"))
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
                      , "GRANT ALL ON SCHEMA public TO "
                          <> db
                          <> "; ALTER SCHEMA public OWNER TO "
                          <> db
                          <> ";"
                      ]
              (psqlCode, _, psqlStderr) <- runStreaming defaultSubprocessEnv psqlSub
              case psqlCode of
                ExitSuccess -> pure (Right ())
                ExitFailure _ ->
                  pure (Left ("postgres schema grant " <> cn <> ": " <> psqlStderr))

-- | Run all postgres schema grants in registry order, returning the first
-- failure as @Left@. Equivalent to the former @postgresSchemaGrantSubprocesses@
-- list except that command-substitution lives in Haskell, not @sh -c@.
runPostgresSchemaGrantsIO :: IO (Either Text ())
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
    , bootHarborRegistry = "127.0.0.1:" <> portText <> "/library"
    }
 where
  portText = Text.pack (show (publicationEdgePort publication))

-- | Live phased rollout executor. Runs the typed
-- `kindCreateSubprocess` + Helm phases + Docker build / Kind image-load phase
-- through the typed `runStreaming` boundary. The rollout stops at the first
-- failed step so later phases cannot mask a missing image or broken prerequisite.
-- The App tier invokes this directly for a substrate bootstrap command after
-- handling explicit plan/dry-run output.
liveExecutePhasedRollout :: Substrate -> FilePath -> IO LiveExecutionResult
liveExecutePhasedRollout substrate chartPath = do
  resources <- loadClusterResourcesOrDefault "."
  lease <- selectLiveLease "." substrate
  let publication = publicationWithLeasedPort lease (defaultPublication substrate)
      port = EdgePort.leasedPort lease
  patchLiveMaterialization substrate lease publication
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
    [] -> runAfterPreGrant port publication []
    kindSub : remainingPreGrantSubs -> do
      (kindExecuted, kindFailure) <- runStepList [kindSub]
      case kindFailure of
        Just (renderedFail, stderrTxt) ->
          pure $
            LiveExecutionResult
              { liveStepsExecuted = kindExecuted
              , liveStepsFailed = [(renderedFail, stderrTxt)]
              , livePublication = publication
              }
        Nothing -> do
          kubeconfigOutcome <- writeKindKubeconfigIO substrate
          let kubeconfigLabel = "kind kubeconfig export"
          case kubeconfigOutcome of
            Left err ->
              pure $
                LiveExecutionResult
                  { liveStepsExecuted = kindExecuted <> [kubeconfigLabel]
                  , liveStepsFailed = [(kubeconfigLabel, err)]
                  , livePublication = publication
                  }
            Right () -> do
              (preRestExecuted, preFailure) <- runStepList remainingPreGrantSubs
              let preExecuted = kindExecuted <> [kubeconfigLabel] <> preRestExecuted
              case preFailure of
                Just (renderedFail, stderrTxt) ->
                  pure $
                    LiveExecutionResult
                      { liveStepsExecuted = preExecuted
                      , liveStepsFailed = [(renderedFail, stderrTxt)]
                      , livePublication = publication
                      }
                Nothing -> runAfterPreGrant port publication preExecuted
 where
  runAfterPreGrant port publication preExecuted = do
    bucketsOutcome <- runMinioBucketReadinessIO
    let bucketsLabel = "minio bucket readiness"
    case bucketsOutcome of
      Left err ->
        pure $
          LiveExecutionResult
            { liveStepsExecuted = preExecuted <> [bucketsLabel]
            , liveStepsFailed = [(bucketsLabel, err)]
            , livePublication = publication
            }
      Right () -> do
        grantOutcome <- runPostgresSchemaGrantsIO
        let grantLabel = "postgres schema grant"
        case grantOutcome of
          Left err ->
            pure $
              LiveExecutionResult
                { liveStepsExecuted = preExecuted <> [bucketsLabel, grantLabel]
                , liveStepsFailed = [(grantLabel, err)]
                , livePublication = publication
                }
          Right () -> do
            postGrantSubs <-
              filterDockerBuildWhenImageExists
                (livePostGrantSubprocessesForPort substrate port chartPath)
            (postExecuted, postFailure) <- runStepList postGrantSubs
            let prePostExecuted = preExecuted <> [bucketsLabel, grantLabel] <> postExecuted
            case postFailure of
              Just (renderedFail, stderrTxt) ->
                pure $
                  LiveExecutionResult
                    { liveStepsExecuted = prePostExecuted
                    , liveStepsFailed = [(renderedFail, stderrTxt)]
                    , livePublication = publication
                    }
              Nothing -> do
                topicsOutcome <- runPulsarTopicCreatesIO
                let topicsLabel = "pulsar topic create"
                    allExecuted = prePostExecuted <> [topicsLabel]
                case topicsOutcome of
                  Left err ->
                    pure $
                      LiveExecutionResult
                        { liveStepsExecuted = allExecuted
                        , liveStepsFailed = [(topicsLabel, err)]
                        , livePublication = publication
                        }
                  Right () -> do
                    measuredPublication <- measureLivePublication publication
                    _ <- writeLivePublication "." measuredPublication
                    pure $
                      LiveExecutionResult
                        { liveStepsExecuted = allExecuted
                        , liveStepsFailed = []
                        , livePublication = measuredPublication
                        }

  runStepList :: [Subprocess] -> IO ([Text], Maybe (Text, Text))
  runStepList = go []
   where
    go executed [] = pure (reverse executed, Nothing)
    go executed (subprocessValue : rest) = do
      let rendered = renderSubprocess subprocessValue
      (exitCode, _stdout, stderrText) <- runStreaming defaultSubprocessEnv subprocessValue
      case exitCode of
        ExitSuccess -> go (rendered : executed) rest
        ExitFailure _
          | isCachedThirdPartyImageLoad subprocessValue ->
              go ((rendered <> " (optional warm-cache load skipped)") : executed) rest
        ExitFailure _ ->
          pure (reverse (rendered : executed), Just (rendered, stderrText))

prepareKindKubeconfigFiles :: Substrate -> IO ()
prepareKindKubeconfigFiles substrate = do
  createDirectoryIfMissing True ".build"
  removeIfExists (".build" </> "jitml.kubeconfig.lock")
  removeIfExists (kindCreateKubeconfigPath substrate <> ".lock")
 where
  removeIfExists path = do
    pathExists <- doesFileExist path
    when pathExists (removeFile path)

writeKindKubeconfigIO :: Substrate -> IO (Either Text ())
writeKindKubeconfigIO substrate = do
  (exitCode, stdoutText, stderrText) <-
    runStreaming
      defaultSubprocessEnv
      (subprocess "kind" ["get", "kubeconfig", "--name", substrateClusterName substrate])
  case exitCode of
    ExitFailure _ -> pure (Left ("kind get kubeconfig: " <> stderrText))
    ExitSuccess ->
      if Text.null (Text.strip stdoutText)
        then pure (Left "kind get kubeconfig: empty kubeconfig")
        else do
          createDirectoryIfMissing True ".build"
          Text.IO.writeFile (".build" </> "jitml.kubeconfig") stdoutText
          pure (Right ())

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

-- | Sprint 13.1 (re-verification) — skip in-bootstrap @docker build -t jitml:local@
-- when the host Docker daemon already has the @jitml:local@ tag. The
-- in-bootstrap rebuild repeats the (already-host-cached) 12-minute layered
-- build because the bootstrap container does not share the host's buildkit
-- cache. The reconciler runs the host Docker daemon over the mounted
-- @/var/run/docker.sock@, so a host-side @docker image inspect jitml:local@
-- hit means the subsequent @kind load docker-image jitml:local@ already has
-- a target. Falls back to running the build subprocess when the image is
-- absent.
filterDockerBuildWhenImageExists :: [Subprocess] -> IO [Subprocess]
filterDockerBuildWhenImageExists subs = do
  hasImage <- imageExistsLocally "jitml:local"
  pure $
    if hasImage
      then filter (not . isJitmlLocalBuild) subs
      else subs
 where
  isJitmlLocalBuild s =
    subprocessPath s == "docker"
      && take 3 (subprocessArguments s) == ["build", "-t", "jitml:local"]

imageExistsLocally :: Text -> IO Bool
imageExistsLocally tag = do
  let probe =
        subprocess "docker" ["image", "inspect", tag]
  (exitCode, _stdoutText, _stderrText) <- runStreaming defaultSubprocessEnv probe
  case exitCode of
    ExitSuccess -> pure True
    ExitFailure _ -> pure False

selectLiveLease :: FilePath -> Substrate -> IO EdgePort.EdgePortLease
selectLiveLease root substrate = do
  existing <- readExistingLivePublication root
  fromMaybe defaultLease <$> EdgePort.leaseEdgePort (candidatePorts existing)
 where
  candidatePorts existing =
    uniquePorts $
      existingPublicationPorts existing
        <> [substrateEdgePort substrate]
        <> EdgePort.defaultPortCandidates

  existingPublicationPorts (Just publication)
    | publicationSubstrate publication == substrate =
        [publicationEdgePort publication]
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
  let path = root </> ".build" </> "runtime" </> "cluster-publication.json"
  exists <- doesFileExist path
  if exists
    then do
      bytes <- LazyByteString.readFile path
      pure (eitherToMaybe (eitherDecode bytes))
    else pure Nothing

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

newtype HelmStatus = HelmStatus Text
  deriving stock (Eq, Show)

instance FromJSON HelmStatus where
  parseJSON =
    withObject "HelmStatus" $ \objectValue -> do
      infoValue <- objectValue .: "info"
      withObject "HelmInfo" (\infoObject -> HelmStatus <$> infoObject .: "status") infoValue

measureLivePublication :: ClusterPublication -> IO ClusterPublication
measureLivePublication publication = do
  components <- traverse measureComponent publicationHealthChecks
  pure publication {publicationComponents = components}

publicationHealthChecks :: [(Text, [Text])]
publicationHealthChecks =
  [ ("harbor", ["harbor"])
  , ("minio", ["minio"])
  , ("pulsar", ["pulsar"])
  , ("postgres", ["harbor-pg"])
  , ("observability", ["kube-prometheus-stack", "tensorboard", "envoy-gateway"])
  , ("jitml-service", ["jitml-service"])
  , ("jitml-demo", ["jitml-demo"])
  ]

measureComponent :: (Text, [Text]) -> IO (Text, Text)
measureComponent (componentName, releases) = do
  releaseStatuses <- traverse measureHelmRelease releases
  pure (componentName, componentStatus releaseStatuses)

measureHelmRelease :: Text -> IO (Text, Text)
measureHelmRelease release = do
  (exitCode, stdoutText, _stderrText) <-
    runStreaming defaultSubprocessEnv (helmStatusSubprocess release)
  case exitCode of
    ExitSuccess -> pure (release, parseHelmStatus stdoutText)
    ExitFailure _ -> pure (release, "unavailable")

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

patchLiveMaterialization :: Substrate -> EdgePort.EdgePortLease -> ClusterPublication -> IO ()
patchLiveMaterialization substrate lease publication = do
  let kindRoot = "kind"
      chartTemplatesRoot = "chart" </> "templates"
      hostConfRoot = ".build" </> "conf" </> "host"
      kindConfigPath = kindRoot </> "cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml"
  createDirectoryIfMissing True kindRoot
  createDirectoryIfMissing True chartTemplatesRoot
  createDirectoryIfMissing True hostConfRoot
  _ <-
    writeTextFileIfChanged
      kindConfigPath
      (renderKindConfig (kindConfigForEdgePort substrate (EdgePort.leasedPort lease)))
  _ <-
    writeTextFileIfChanged
      (chartTemplatesRoot </> "gateway-jitml-edge.yaml")
      (renderGateway (EdgePort.leasedPort lease))
  _ <-
    writeTextFileIfChanged
      (chartTemplatesRoot </> "envoyproxy-jitml-edge.yaml")
      (renderEnvoyProxy (EdgePort.leasedPort lease))
  case substrate of
    AppleSilicon -> do
      _ <-
        writeTextFileIfChanged
          (hostConfRoot </> "apple-silicon.dhall")
          (renderBootConfigDhall (hostBootConfigForPublication publication))
      pure ()
    _ -> pure ()

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
