{-# LANGUAGE OverloadedStrings #-}

module JitML.Bootstrap
  ( LiveExecutionResult (..)
  , bootstrapPlanSteps
  , hostBootConfigForPublication
  , livePhasedRolloutSubprocesses
  , liveExecutePhasedRollout
  , materializeBootstrapFiles
  )
where

import Data.Aeson (FromJSON (..), eitherDecode, encode, withObject, (.:))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import System.Directory (createDirectoryIfMissing, doesFileExist, removeFile, renameFile)
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
  ( helmDependencyBuildSubprocess
  , helmInstallSubprocessForEdgePort
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
import JitML.Cluster.PulsarBootstrap (pulsarTopicCreateSubprocesses)
import JitML.Cluster.Readiness (platformReadinessSubprocesses)
import JitML.Cluster.Readiness qualified as Readiness
import JitML.Cluster.Storage
  ( ManualPV (..)
  , manualPVs
  , pvLocalDataPath
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
import JitML.Sub.Subprocess (Subprocess, subprocess, subprocessWithStdin)
import JitML.Substrate (Substrate (..), renderSubstrate, substrateEdgePort)

bootstrapPlanSteps :: Substrate -> [Text]
bootstrapPlanSteps substrate =
  [ "reconcile prerequisite graph for cluster"
  , "render kind/cluster-" <> renderSubstrate substrate <> ".yaml"
  , "prepare Helm dependencies with " <> renderHelmDependencyBuildPlan "chart"
  , "create/export Kind kubeconfig and copy it to ./.build/jitml.kubeconfig"
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
  routeResults <- traverse (writeRoute chartTemplatesRoot) routeRegistry
  legacyValuesChanged <- removeFileIfExists (chartTemplatesRoot </> "minio-values.yaml")
  standaloneValuesChanged <- removeFileIfExists (chartRoot </> "minio-values.yaml")
  let clusterBoot = defaultBootConfig substrate Cluster
  configResults <-
    sequence
      [ writeTextFileIfChanged
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
  livePhasedRolloutSubprocessesForPort substrate (substrateEdgePort substrate)

livePhasedRolloutSubprocessesForPort :: Substrate -> Int -> FilePath -> [Subprocess]
livePhasedRolloutSubprocessesForPort substrate edgePort chartPath =
  [ kindCreateSubprocess substrate kindConfigPath
  , helmDependencyBuildSubprocess chartPath
  ]
    <> foundationManifestApplySubprocesses chartPath
    <> concatMap releaseSteps minioBootstrapReleases
    <> Readiness.minioBootstrapReadinessSubprocesses
    <> concatMap releaseSteps postgresOperatorReleases
    <> postgresClusterApplySubprocesses
    <> Readiness.postgresReadinessSubprocesses
    <> postgresSchemaGrantSubprocesses
    <> concatMap releaseSteps harborApplicationReleases
    <> mirrorBuildSteps substrate
    <> concatMap releaseSteps remainingReleases
    <> observabilityManifestApplySubprocesses chartPath
    <> platformReadinessSubprocesses
    <> edgeManifestApplySubprocesses chartPath
    <> pulsarTopicCreateSubprocesses
 where
  kindConfigPath = "kind/cluster-" <> Text.unpack (renderSubstrate substrate) <> ".yaml"

  releaseSteps release =
    [helmInstallSubprocessForEdgePort substrate edgePort release chartPath]

  postgresOperatorReleases =
    filter ((== "harbor-pg") . releaseName) phasedReleases

  minioBootstrapReleases =
    filter ((== "minio") . releaseName) phasedReleases

  harborApplicationReleases =
    filter ((== "harbor") . releaseName) phasedReleases

  remainingReleases =
    filter
      ( \release ->
          releaseName release /= "harbor-pg"
            && releaseName release /= "harbor"
            && releaseName release /= "minio"
      )
      phasedReleases

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

postgresSchemaGrantSubprocesses :: [Subprocess]
postgresSchemaGrantSubprocesses =
  fmap postgresSchemaGrantSubprocess postgresRegistry

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

postgresSchemaGrantSubprocess :: PerconaPGCluster -> Subprocess
postgresSchemaGrantSubprocess cluster =
  subprocess
    "sh"
    [ "-c"
    , Text.concat
        [ "primary=$(kubectl --kubeconfig ./.build/jitml.kubeconfig get pod -n "
        , perconaNamespace cluster
        , " -l postgres-operator.crunchydata.com/cluster="
        , perconaClusterName cluster
        , ",postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}'); "
        , "kubectl --kubeconfig ./.build/jitml.kubeconfig exec -n "
        , perconaNamespace cluster
        , " \"$primary\" -c database -- psql -d "
        , perconaDatabase cluster
        , " -c \"GRANT ALL ON SCHEMA public TO "
        , perconaDatabase cluster
        , "; ALTER SCHEMA public OWNER TO "
        , perconaDatabase cluster
        , ";\""
        ]
    ]

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
  lease <- selectLiveLease substrate
  let publication = publicationWithLeasedPort lease (defaultPublication substrate)
  patchLiveMaterialization substrate lease publication
  runSteps
    publication
    []
    []
    (livePhasedRolloutSubprocessesForPort substrate (EdgePort.leasedPort lease) chartPath)
 where
  runSteps :: ClusterPublication -> [Text] -> [(Text, Text)] -> [Subprocess] -> IO LiveExecutionResult
  runSteps publication executed failed [] = do
    measuredPublication <- measureLivePublication publication
    _ <- writeLivePublication "." measuredPublication
    pure
      LiveExecutionResult
        { liveStepsExecuted = reverse executed
        , liveStepsFailed = reverse failed
        , livePublication = measuredPublication
        }
  runSteps publication executed failed (subprocessValue : rest) = do
    let rendered = renderSubprocess subprocessValue
    (exitCode, _stdout, stderrText) <- runStreaming defaultSubprocessEnv subprocessValue
    case exitCode of
      ExitSuccess -> runSteps publication (rendered : executed) failed rest
      ExitFailure _ ->
        pure
          LiveExecutionResult
            { liveStepsExecuted = reverse (rendered : executed)
            , liveStepsFailed = reverse ((rendered, stderrText) : failed)
            , livePublication = publication
            }

selectLiveLease :: Substrate -> IO EdgePort.EdgePortLease
selectLiveLease substrate = do
  existing <- readExistingLivePublication "."
  case existing of
    Just publication
      | publicationSubstrate publication == substrate ->
          pure
            EdgePort.EdgePortLease
              { EdgePort.leasedPort = publicationEdgePort publication
              , EdgePort.leasedHost = "127.0.0.1"
              }
    _ ->
      fromMaybe defaultLease
        <$> EdgePort.leaseEdgePort
          (substrateEdgePort substrate : filter (/= substrateEdgePort substrate) EdgePort.defaultPortCandidates)
 where
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
