{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Clients
  ( EngineClientSettings
  , EngineServiceClient
  , engineClientSettingsForBootConfig
  , engineClientSettingsWithPublicationDeadline
  , engineMinIOSettings
  , enginePulsarSettings
  , renderEngineClientSettings
  , runEngineServiceClient
  , DaemonRoleClientSettings
  , coordinatorRoleClientSettings
  , daemonRoleClientSettingsForBootConfig
  , engineRoleClientSettings
  , renderDaemonRoleClientSettings
  , rolePulsarSettings
  , DaemonClientSettings (..)
  , DaemonServiceClient (..)
  , coordinatorClientSettingsForBootConfig
  , renderDaemonClientSettings
  , runDaemonServiceClient
  , runDaemonHarborClient
  , runDaemonKubectlClient
  , runDaemonMinIOClient
  , runDaemonPulsarClient
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Reader (MonadReader, ReaderT, ask, runReaderT)
import GHC.Clock (getMonotonicTimeNSec)

import JitML.Service.BootConfig
  ( BootConfig (..)
  , Residency (..)
  , Role (..)
  )
import JitML.Service.Capabilities
  ( HasHarbor (..)
  , HasKubectl (..)
  , HasMinIO (..)
  , HasPulsar (..)
  )
import JitML.Service.HarborSubprocess
  ( HarborSettings (..)
  , HarborSubprocess
  , runHarborSubprocess
  )
import JitML.Service.InferenceBatch (batchDeadlineExpiredAt)
import JitML.Service.KubectlSubprocess
  ( KubectlSettings (..)
  , KubectlSubprocess
  , defaultKubectlSettings
  , inClusterKubectlSettings
  , runKubectlSubprocess
  )
import JitML.Service.MinIOSubprocess
  ( MinIOSettings (..)
  , MinIOSubprocess
  , minioSettingsForEndpoint
  , runMinIOSubprocess
  )
import JitML.Service.PulsarWebSocketSubprocess
  ( PulsarWebSocketSettings (..)
  , PulsarWebSocketSubprocess
  , pulsarSettingsForEndpoint
  , runPulsarWebSocketSubprocess
  )
import JitML.Service.Retry (ServiceError (..))

data DaemonClientSettings = DaemonClientSettings
  { daemonMinIOSettings :: MinIOSettings
  , daemonPulsarSettings :: PulsarWebSocketSettings
  , daemonHarborSettings :: HarborSettings
  , daemonKubectlSettings :: KubectlSettings
  }
  deriving stock (Eq, Show)

-- | Capability-minimal settings retained by an Engine process. The
-- constructor is private: Engine startup can project only MinIO and Pulsar and
-- cannot recover Harbor credentials or kubectl configuration from this value.
data EngineClientSettings = EngineClientSettings
  { engineMinIOSettings :: MinIOSettings
  , enginePulsarSettings :: PulsarWebSocketSettings
  , enginePublicationDeadlineNanoseconds :: Maybe Integer
  }
  deriving stock (Eq, Show)

-- | Closed, role-projected settings retained by 'DaemonRuntime'. Webapp owns
-- no daemon client settings; its browser Pulsar endpoint stays in the Webapp
-- serve path. Constructors remain private so callers cannot attach Coordinator
-- credentials to an Engine runtime.
data DaemonRoleClientSettings
  = EngineRoleClientSettings EngineClientSettings
  | CoordinatorRoleClientSettings DaemonClientSettings
  | WebappRoleClientSettings
  deriving stock (Eq, Show)

-- | Opaque Engine interpreter. Deliberately has no 'HasHarbor' or 'HasKubectl'
-- instance, so orchestration effects cannot type-check in the Engine path.
newtype EngineServiceClient a = EngineServiceClient
  { unEngineServiceClient :: ReaderT EngineClientSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader EngineClientSettings
    )

newtype DaemonServiceClient a = DaemonServiceClient
  { unDaemonServiceClient :: ReaderT DaemonClientSettings IO a
  }
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader DaemonClientSettings
    )

engineClientSettingsForBootConfig :: BootConfig -> EngineClientSettings
engineClientSettingsForBootConfig bootConfig =
  EngineClientSettings
    { engineMinIOSettings = minioSettingsForBootConfig bootConfig
    , enginePulsarSettings = pulsarSettingsForBootConfig bootConfig
    , enginePublicationDeadlineNanoseconds = Nothing
    }

-- | Scope an Engine dispatch to one transport-owned publication deadline.
-- MinIO reads and device execution may consume the budget, but the final
-- Pulsar side effect is never entered after the captured monotonic fence.
engineClientSettingsWithPublicationDeadline
  :: Integer
  -> EngineClientSettings
  -> EngineClientSettings
engineClientSettingsWithPublicationDeadline deadline settings =
  settings {enginePublicationDeadlineNanoseconds = Just deadline}

runEngineServiceClient
  :: EngineClientSettings
  -> EngineServiceClient a
  -> IO a
runEngineServiceClient settings action =
  runReaderT (unEngineServiceClient action) settings

runEngineMinIOAction :: MinIOSubprocess a -> EngineServiceClient a
runEngineMinIOAction action = do
  settings <- ask
  liftIO (runMinIOSubprocess (engineMinIOSettings settings) action)

runEnginePulsarAction
  :: PulsarWebSocketSubprocess a
  -> EngineServiceClient a
runEnginePulsarAction action = do
  settings <- ask
  liftIO (runPulsarWebSocketSubprocess (enginePulsarSettings settings) action)

instance HasMinIO EngineServiceClient where
  minioPutIfAbsent ref payload =
    runEngineMinIOAction (minioPutIfAbsent ref payload)
  minioReadObject ref =
    runEngineMinIOAction (minioReadObject ref)
  minioReadBytes ref =
    runEngineMinIOAction (minioReadBytes ref)
  putBlobIfAbsent ref payload =
    runEngineMinIOAction (putBlobIfAbsent ref payload)
  putBlobBytesIfAbsent ref payload =
    runEngineMinIOAction (putBlobBytesIfAbsent ref payload)
  casPointer ref expected payload =
    runEngineMinIOAction (casPointer ref expected payload)
  listObjects bucket prefix =
    runEngineMinIOAction (listObjects bucket prefix)
  deleteObject ref =
    runEngineMinIOAction (deleteObject ref)

instance HasPulsar EngineServiceClient where
  pulsarPublish topic payload = do
    settings <- ask
    deadlineResult <- liftIO (enginePublicationDeadlineResult settings)
    case deadlineResult of
      Left err -> pure (Left err)
      Right () -> runEnginePulsarAction (pulsarPublish topic payload)
  pulsarConsumeUntil subscription observe handler = do
    settings <- ask
    liftIO $
      runPulsarWebSocketSubprocess (enginePulsarSettings settings) $
        pulsarConsumeUntil
          subscription
          (liftIO . runEngineServiceClient settings . observe)
          (liftIO . runEngineServiceClient settings . handler)
  pulsarConsumeBatchesUntil readPolicy compatibilityKey subscription observe handler = do
    settings <- ask
    liftIO $
      runPulsarWebSocketSubprocess (enginePulsarSettings settings) $
        pulsarConsumeBatchesUntil
          (liftIO (runEngineServiceClient settings readPolicy))
          compatibilityKey
          subscription
          (liftIO . runEngineServiceClient settings . observe)
          (liftIO . runEngineServiceClient settings . handler)

enginePublicationDeadlineResult :: EngineClientSettings -> IO (Either ServiceError ())
enginePublicationDeadlineResult settings =
  case enginePublicationDeadlineNanoseconds settings of
    Nothing -> pure (Right ())
    Just deadline -> do
      now <- getMonotonicTimeNSec
      pure $
        if batchDeadlineExpiredAt now deadline
          then Left (SETimeout "inference batch publication deadline expired before publish")
          else Right ()

renderEngineClientSettings :: EngineClientSettings -> Text
renderEngineClientSettings settings =
  Text.unlines
    [ "minio_endpoint: " <> minioEndpoint minioSettings
    , "minio_request_path_prefix: "
        <> renderMaybeEmpty (minioRequestPathPrefix minioSettings)
    , "pulsar_websocket_endpoint: "
        <> pulsarWebSocketEndpoint pulsarSettings
    ]
 where
  minioSettings = engineMinIOSettings settings
  pulsarSettings = enginePulsarSettings settings

daemonRoleClientSettingsForBootConfig :: BootConfig -> DaemonRoleClientSettings
daemonRoleClientSettingsForBootConfig bootConfig =
  case bootActiveRole bootConfig of
    Engine ->
      EngineRoleClientSettings (engineClientSettingsForBootConfig bootConfig)
    Coordinator ->
      CoordinatorRoleClientSettings (coordinatorClientSettingsForBootConfig bootConfig)
    Webapp -> WebappRoleClientSettings

engineRoleClientSettings
  :: DaemonRoleClientSettings
  -> Maybe EngineClientSettings
engineRoleClientSettings roleSettings =
  case roleSettings of
    EngineRoleClientSettings settings -> Just settings
    CoordinatorRoleClientSettings _settings -> Nothing
    WebappRoleClientSettings -> Nothing

coordinatorRoleClientSettings
  :: DaemonRoleClientSettings
  -> Maybe DaemonClientSettings
coordinatorRoleClientSettings roleSettings =
  case roleSettings of
    EngineRoleClientSettings _settings -> Nothing
    CoordinatorRoleClientSettings settings -> Just settings
    WebappRoleClientSettings -> Nothing

rolePulsarSettings
  :: DaemonRoleClientSettings
  -> Maybe PulsarWebSocketSettings
rolePulsarSettings roleSettings =
  case roleSettings of
    EngineRoleClientSettings settings -> Just (enginePulsarSettings settings)
    CoordinatorRoleClientSettings settings -> Just (daemonPulsarSettings settings)
    WebappRoleClientSettings -> Nothing

renderDaemonRoleClientSettings :: DaemonRoleClientSettings -> Text
renderDaemonRoleClientSettings roleSettings =
  case roleSettings of
    EngineRoleClientSettings settings -> renderEngineClientSettings settings
    CoordinatorRoleClientSettings settings -> renderDaemonClientSettings settings
    WebappRoleClientSettings -> "(browser-only; no daemon clients)\n"

coordinatorClientSettingsForBootConfig :: BootConfig -> DaemonClientSettings
coordinatorClientSettingsForBootConfig bootConfig =
  DaemonClientSettings
    { daemonMinIOSettings = minioSettingsForBootConfig bootConfig
    , daemonPulsarSettings = pulsarSettingsForBootConfig bootConfig
    , daemonHarborSettings = harborSettingsForBootConfig bootConfig
    , daemonKubectlSettings = kubectlSettingsForBootConfig bootConfig
    }

kubectlSettingsForBootConfig :: BootConfig -> KubectlSettings
kubectlSettingsForBootConfig bootConfig =
  case bootResidency bootConfig of
    Cluster -> inClusterKubectlSettings
    Host -> defaultKubectlSettings

runDaemonServiceClient :: DaemonClientSettings -> DaemonServiceClient a -> IO a
runDaemonServiceClient settings action =
  runReaderT (unDaemonServiceClient action) settings

runDaemonMinIOClient :: DaemonClientSettings -> MinIOSubprocess a -> IO a
runDaemonMinIOClient settings =
  runMinIOSubprocess (daemonMinIOSettings settings)

runDaemonPulsarClient :: DaemonClientSettings -> PulsarWebSocketSubprocess a -> IO a
runDaemonPulsarClient settings =
  runPulsarWebSocketSubprocess (daemonPulsarSettings settings)

runDaemonHarborClient :: DaemonClientSettings -> HarborSubprocess a -> IO a
runDaemonHarborClient settings =
  runHarborSubprocess (daemonHarborSettings settings)

runDaemonKubectlClient :: DaemonClientSettings -> KubectlSubprocess a -> IO a
runDaemonKubectlClient settings =
  runKubectlSubprocess (daemonKubectlSettings settings)

runDaemonMinIOAction :: MinIOSubprocess a -> DaemonServiceClient a
runDaemonMinIOAction action = do
  settings <- ask
  liftIO (runDaemonMinIOClient settings action)

runDaemonPulsarAction :: PulsarWebSocketSubprocess a -> DaemonServiceClient a
runDaemonPulsarAction action = do
  settings <- ask
  liftIO (runDaemonPulsarClient settings action)

runDaemonHarborAction :: HarborSubprocess a -> DaemonServiceClient a
runDaemonHarborAction action = do
  settings <- ask
  liftIO (runDaemonHarborClient settings action)

runDaemonKubectlAction :: KubectlSubprocess a -> DaemonServiceClient a
runDaemonKubectlAction action = do
  settings <- ask
  liftIO (runDaemonKubectlClient settings action)

instance HasMinIO DaemonServiceClient where
  minioPutIfAbsent ref payload =
    runDaemonMinIOAction (minioPutIfAbsent ref payload)
  minioReadObject ref =
    runDaemonMinIOAction (minioReadObject ref)
  minioReadBytes ref =
    runDaemonMinIOAction (minioReadBytes ref)
  putBlobIfAbsent ref payload =
    runDaemonMinIOAction (putBlobIfAbsent ref payload)
  putBlobBytesIfAbsent ref payload =
    runDaemonMinIOAction (putBlobBytesIfAbsent ref payload)
  casPointer ref expected payload =
    runDaemonMinIOAction (casPointer ref expected payload)
  listObjects bucket prefix =
    runDaemonMinIOAction (listObjects bucket prefix)
  deleteObject ref =
    runDaemonMinIOAction (deleteObject ref)

instance HasPulsar DaemonServiceClient where
  pulsarPublish topic payload =
    runDaemonPulsarAction (pulsarPublish topic payload)
  pulsarConsumeUntil subscription observe handler = do
    settings <- ask
    liftIO $
      runDaemonPulsarClient settings $
        pulsarConsumeUntil
          subscription
          (liftIO . runDaemonServiceClient settings . observe)
          (liftIO . runDaemonServiceClient settings . handler)
  pulsarConsumeBatchesUntil readPolicy compatibilityKey subscription observe handler = do
    settings <- ask
    liftIO $
      runDaemonPulsarClient settings $
        pulsarConsumeBatchesUntil
          (liftIO (runDaemonServiceClient settings readPolicy))
          compatibilityKey
          subscription
          (liftIO . runDaemonServiceClient settings . observe)
          (liftIO . runDaemonServiceClient settings . handler)

instance HasHarbor DaemonServiceClient where
  harborImageExists image =
    runDaemonHarborAction (harborImageExists image)
  harborPromoteImage source target =
    runDaemonHarborAction (harborPromoteImage source target)
  harborPushImage image =
    runDaemonHarborAction (harborPushImage image)
  harborPullImage image =
    runDaemonHarborAction (harborPullImage image)
  harborListImages project =
    runDaemonHarborAction (harborListImages project)

instance HasKubectl DaemonServiceClient where
  kubectlApply resource yaml =
    runDaemonKubectlAction (kubectlApply resource yaml)
  kubectlStatus resource =
    runDaemonKubectlAction (kubectlStatus resource)
  kubectlGet resource =
    runDaemonKubectlAction (kubectlGet resource)
  kubectlDelete resource =
    runDaemonKubectlAction (kubectlDelete resource)

renderDaemonClientSettings :: DaemonClientSettings -> Text
renderDaemonClientSettings settings =
  Text.unlines
    [ "minio_endpoint: " <> minioEndpoint minioSettings
    , "minio_request_path_prefix: " <> renderMaybeEmpty (minioRequestPathPrefix minioSettings)
    , "pulsar_websocket_endpoint: " <> pulsarWebSocketEndpoint pulsarSettings
    , "pulsar_admin_endpoint: " <> pulsarAdminEndpoint pulsarSettings
    , "harbor_registry: " <> harborRegistry harborSettings
    , "harbor_api_base_url: " <> harborApiBaseUrl harborSettings
    , "kubectl_kubeconfig: " <> renderKubectlKubeconfig kubectlSettings
    , "kubectl_namespace: " <> kubectlNamespace kubectlSettings
    ]
 where
  minioSettings = daemonMinIOSettings settings
  pulsarSettings = daemonPulsarSettings settings
  harborSettings = daemonHarborSettings settings
  kubectlSettings = daemonKubectlSettings settings

renderKubectlKubeconfig :: KubectlSettings -> Text
renderKubectlKubeconfig settings =
  case kubectlKubeconfig settings of
    "" -> "(in-cluster)"
    kubeconfig -> Text.pack kubeconfig

minioSettingsForBootConfig :: BootConfig -> MinIOSettings
minioSettingsForBootConfig bootConfig =
  (minioSettingsForEndpoint origin)
    { minioRequestPathPrefix = pathPrefix
    }
 where
  (origin, pathPrefix) = splitHttpEndpointPath (bootMinioEndpoint bootConfig)

pulsarSettingsForBootConfig :: BootConfig -> PulsarWebSocketSettings
pulsarSettingsForBootConfig bootConfig =
  case bootResidency bootConfig of
    Host ->
      (pulsarSettingsForEndpoint (bootPulsarServiceUrl bootConfig))
        { pulsarAdminEndpoint = pulsarAdminV2Endpoint (bootPulsarAdminUrl bootConfig)
        }
    Cluster ->
      PulsarWebSocketSettings
        { pulsarNodeBinary = "node"
        , pulsarWebSocketEndpoint = "ws://pulsar-broker.platform.svc.cluster.local:8080/ws"
        , pulsarAdminEndpoint = pulsarAdminV2Endpoint (bootPulsarAdminUrl bootConfig)
        }

pulsarAdminV2Endpoint :: Text -> Text
pulsarAdminV2Endpoint rawEndpoint
  | "/admin/v2" `Text.isSuffixOf` endpoint = endpoint
  | "/admin" `Text.isSuffixOf` endpoint = endpoint <> "/v2"
  | otherwise = endpoint <> "/admin/v2"
 where
  endpoint = stripTrailingSlash rawEndpoint

harborSettingsForBootConfig :: BootConfig -> HarborSettings
harborSettingsForBootConfig bootConfig =
  case bootResidency bootConfig of
    Host ->
      baseHarborSettings registryRoot ("http://" <> registryRoot <> "/harbor/api")
    Cluster ->
      baseHarborSettings registryRoot "http://harbor.platform.svc.cluster.local/api"
 where
  registryRoot = registryRootFromPrefix (bootHarborRegistry bootConfig)

baseHarborSettings :: Text -> Text -> HarborSettings
baseHarborSettings registry apiBase =
  HarborSettings
    { harborDockerBinary = "docker"
    , harborDockerHost = Nothing
    , harborDockerConfigDir = "./.build/docker/harbor"
    , harborCurlBinary = "curl"
    , harborRegistry = registry
    , harborApiBaseUrl = apiBase
    , harborUsername = "admin"
    , harborPassword = "Harbor12345"
    }

splitHttpEndpointPath :: Text -> (Text, Text)
splitHttpEndpointPath endpoint =
  case Text.breakOn "://" endpoint of
    (_prefix, "") -> (stripTrailingSlash endpoint, "")
    (scheme, restWithSeparator) ->
      let rest = Text.drop 3 restWithSeparator
          (authority, path) = Text.breakOn "/" rest
          origin = scheme <> "://" <> authority
       in (stripTrailingSlash origin, stripTrailingSlash path)

registryRootFromPrefix :: Text -> Text
registryRootFromPrefix registryPrefix =
  fst (Text.breakOn "/" registryPrefix)

stripTrailingSlash :: Text -> Text
stripTrailingSlash value
  | "/" `Text.isSuffixOf` value = stripTrailingSlash (Text.dropEnd 1 value)
  | otherwise = value

renderMaybeEmpty :: Text -> Text
renderMaybeEmpty value
  | Text.null value = "(none)"
  | otherwise = value
