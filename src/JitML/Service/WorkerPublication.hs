{-# LANGUAGE OverloadedStrings #-}

-- | Service coordinates for a real worker or a published host-side CLI.
-- Coordinates are not a live-readiness, source, executable or device proof.
module JitML.Service.WorkerPublication
  ( WorkerLiveContext
  , resolveWorkerLiveContext
  , resolveWorkerLiveContextAt
  , workerServiceBootConfigPath
  , workerLivePublication
  , workerLiveMinIOSettings
  , workerLivePulsarSettings
  , workerLiveUsesMountedServices
  ) where

import Control.Exception (IOException, try)
import Control.Exception.Safe (tryAny)
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.Error (Errno (..), eNOENT)
import GHC.IO.Exception (ioe_errno)
import System.FilePath ((</>))
import System.Posix.Files (getSymbolicLinkStatus)

import JitML.Bootstrap (readExistingLivePublication)
import JitML.Cluster.Publication (ClusterPublication, defaultPublication)
import JitML.Cluster.Publication qualified as Publication
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.MinIOSubprocess qualified as MinIO
import JitML.Service.PulsarWebSocketSubprocess qualified as Pulsar
import JitML.Substrate (substrateEdgePort)

data WorkerLiveContext
  = WorkerLiveContext
      !ClusterPublication
      !MinIO.MinIOSettings
      !Pulsar.PulsarWebSocketSettings
      !Bool

workerLivePublication :: WorkerLiveContext -> ClusterPublication
workerLivePublication (WorkerLiveContext publication _ _ _) = publication

workerLiveMinIOSettings :: WorkerLiveContext -> MinIO.MinIOSettings
workerLiveMinIOSettings (WorkerLiveContext _ settings _ _) = settings

workerLivePulsarSettings :: WorkerLiveContext -> Pulsar.PulsarWebSocketSettings
workerLivePulsarSettings (WorkerLiveContext _ _ settings _) = settings

workerLiveUsesMountedServices :: WorkerLiveContext -> Bool
workerLiveUsesMountedServices (WorkerLiveContext _ _ _ mounted) = mounted

workerServiceBootConfigPath :: FilePath
workerServiceBootConfigPath = "/etc/jitml/service/BootConfig.dhall"

resolveWorkerLiveContext :: FilePath -> IO (Either Text (Maybe WorkerLiveContext))
resolveWorkerLiveContext = resolveWorkerLiveContextAt workerServiceBootConfigPath

-- | A present mounted configuration is an explicit publication source. Decode
-- or I/O failure must not turn it into an offline success or host-edge fallback.
-- Only an absent mount consults the existing host live-publication resolver.
-- With neither source, local offline commands retain their local-only behavior.
resolveWorkerLiveContextAt
  :: FilePath
  -> FilePath
  -> IO (Either Text (Maybe WorkerLiveContext))
resolveWorkerLiveContextAt bootPath repositoryRoot = do
  configured <- configuredEntryPresent bootPath
  case configured of
    Left exception -> pure (Left (configurationFailure bootPath exception))
    Right True -> do
      loaded <- tryAny (BootConfig.loadBootConfig bootPath)
      pure $ case loaded of
        Left exception -> Left (configurationFailure bootPath exception)
        Right boot ->
          let clients = ServiceClients.engineClientSettingsForBootConfig boot
           in Right
                ( Just
                    ( WorkerLiveContext
                        (publicationFromBootConfig boot)
                        (ServiceClients.engineMinIOSettings clients)
                        (ServiceClients.enginePulsarSettings clients)
                        True
                    )
                )
    Right False -> do
      let publicationPath = repositoryRoot </> ".build" </> "runtime" </> "cluster-publication.json"
      hostConfigured <- configuredEntryPresent publicationPath
      case hostConfigured of
        Left exception -> pure (Left (configurationFailure publicationPath exception))
        Right False -> pure (Right Nothing)
        Right True -> do
          existing <- tryAny (readExistingLivePublication repositoryRoot)
          pure $ case existing of
            Left exception -> Left (configurationFailure publicationPath exception)
            Right Nothing ->
              Left
                ( "worker publication configuration at "
                    <> Text.pack publicationPath
                    <> " is present but is not a valid live publication"
                )
            Right (Just publication) -> Right (Just (hostContext publication))
 where
  hostContext publication =
    let edgePort = Publication.publicationEdgePort publication
     in WorkerLiveContext
          publication
          (MinIO.minioSettingsForLocalEdge edgePort)
          (Pulsar.pulsarSettingsForLocalEdge edgePort)
          False
  configurationFailure path exception =
    "worker publication configuration at " <> Text.pack path <> ": " <> Text.pack (show exception)

-- | lstat observes the configured directory entry itself, including a dangling
-- symlink. Only the actual ENOENT errno means absent: the broader Haskell
-- NoSuchThing classification also includes ENOTDIR, which must fail closed.
-- The project pins base to 4.21, including the errno accessor used here.
configuredEntryPresent :: FilePath -> IO (Either IOException Bool)
configuredEntryPresent path = do
  observed <- try (getSymbolicLinkStatus path)
  pure $ case observed of
    Right _ -> Right True
    Left exception
      | fmap Errno (ioe_errno exception) == Just eNOENT -> Right False
      | otherwise -> Left exception

publicationFromBootConfig :: BootConfig.BootConfig -> ClusterPublication
publicationFromBootConfig boot =
  (defaultPublication (BootConfig.bootSubstrate boot))
    { Publication.publicationEdgePort = substrateEdgePort (BootConfig.bootSubstrate boot)
    , Publication.publicationPulsarUrl = BootConfig.bootPulsarServiceUrl boot
    , Publication.publicationMinioUrl = BootConfig.bootMinioEndpoint boot
    }
