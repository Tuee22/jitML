{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Clients
  ( DaemonClientSettings (..)
  , DaemonServiceClient (..)
  , daemonClientSettingsForBootConfig
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

import JitML.Service.BootConfig
  ( BootConfig (..)
  , Residency (..)
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
import JitML.Service.KubectlSubprocess
  ( KubectlSettings (..)
  , KubectlSubprocess
  , defaultKubectlSettings
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

data DaemonClientSettings = DaemonClientSettings
  { daemonMinIOSettings :: MinIOSettings
  , daemonPulsarSettings :: PulsarWebSocketSettings
  , daemonHarborSettings :: HarborSettings
  , daemonKubectlSettings :: KubectlSettings
  }
  deriving stock (Eq, Show)

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

daemonClientSettingsForBootConfig :: BootConfig -> DaemonClientSettings
daemonClientSettingsForBootConfig bootConfig =
  DaemonClientSettings
    { daemonMinIOSettings = minioSettingsForBootConfig bootConfig
    , daemonPulsarSettings = pulsarSettingsForBootConfig bootConfig
    , daemonHarborSettings = harborSettingsForBootConfig bootConfig
    , daemonKubectlSettings = defaultKubectlSettings
    }

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
  pulsarAcknowledge topic payload =
    runDaemonPulsarAction (pulsarAcknowledge topic payload)
  pulsarSubscribe topic subscription =
    runDaemonPulsarAction (pulsarSubscribe topic subscription)
  pulsarConsume subscription =
    runDaemonPulsarAction (pulsarConsume subscription)
  pulsarSeek subscription eventId =
    runDaemonPulsarAction (pulsarSeek subscription eventId)

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
    , "harbor_registry: " <> harborRegistry harborSettings
    , "harbor_api_base_url: " <> harborApiBaseUrl harborSettings
    , "kubectl_kubeconfig: " <> Text.pack (kubectlKubeconfig kubectlSettings)
    , "kubectl_namespace: " <> kubectlNamespace kubectlSettings
    ]
 where
  minioSettings = daemonMinIOSettings settings
  pulsarSettings = daemonPulsarSettings settings
  harborSettings = daemonHarborSettings settings
  kubectlSettings = daemonKubectlSettings settings

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
    Host -> pulsarSettingsForEndpoint (bootPulsarServiceUrl bootConfig)
    Cluster ->
      PulsarWebSocketSettings
        { pulsarNodeBinary = "node"
        , pulsarWebSocketEndpoint = "ws://pulsar-broker.platform.svc.cluster.local:8080/ws"
        }

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
