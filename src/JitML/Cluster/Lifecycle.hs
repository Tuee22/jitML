{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Lifecycle
  ( StopOutcome (..)
  , stopCluster
  , resetCluster
  , restoreCreatedCluster
  , assertClusterReusable
  ) where

import Control.Exception
  ( SomeAsyncException
  , SomeException
  , displayException
  , fromException
  , mask
  , throwIO
  , try
  )
import Control.Monad (unless, void, when)
import Data.Aeson (object, (.=))
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory (makeAbsolute)
import System.FilePath ((</>))
import System.Posix.Process (getProcessID)

import JitML.CLI.Output (writeLineIO)
import JitML.Cluster.Helm (kindDeleteSubprocess)
import JitML.Cluster.Kind (KindConfig, kindConfigForWorkers)
import JitML.Cluster.LifecycleFilesystem
import JitML.Cluster.LifecycleTarget
import JitML.Cluster.PVSnapshot
import JitML.Cluster.PVSnapshotDocker qualified as Docker
import JitML.Cluster.PVSnapshotPosix qualified as Posix
import JitML.Cluster.PVSnapshotPrograms (defaultSnapshotPrograms)
import JitML.Cluster.ResourceRuntime (checkResourceEnvelopeWithSiblingIO)
import JitML.Cluster.Resources (ClusterResources, loadClusterResourcesOrDefault, workerCount)
import JitML.Cluster.Storage (manualPVsFor, pvNodeDataPath)
import JitML.Sub.Outcome
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), renderSubstrate, substrateClusterName)

data StopOutcome = ClusterDeleted | ClusterAlreadyAbsent
  deriving (Eq, Show)

failure :: String -> IO a
failure = throwIO . userError

freshToken :: IO Text
freshToken = do
  pid <- getProcessID
  tick <- getMonotonicTimeNSec
  pure ("p" <> Text.pack (show pid) <> "-" <> Text.pack (show tick))

-- Every outcome is captured literally. Failed commands never become a pass or
-- a missing-cluster observation, and cancellation remains an exception.
runObserved :: Posix.LifecycleLease -> Subprocess -> IO ProcessOutcome
runObserved lease spec = mask $ \restore -> do
  attempted <- try (restore (runStreaming defaultSubprocessEnv spec))
  outcome <- case attempted of
    Left original -> do
      recorded <-
        try
          ( Posix.recordLifecycleEvent lease $
              object
                [ "event" .= ("command-attempt-failed" :: Text)
                , "executable" .= subprocessPath spec
                , "argv" .= subprocessArguments spec
                , "exception" .= displayException (original :: SomeException)
                ]
          )
          :: IO (Either SomeException ())
      case (fromException original :: Maybe SomeAsyncException, recorded) of
        (Nothing, Left cleanup) | Just _ <- (fromException cleanup :: Maybe SomeAsyncException) -> throwIO cleanup
        _ -> throwIO original
    Right actual -> pure actual
  let transcript = case outcome of
        ProcessSucceeded value -> value
        ProcessFailed value -> processFailureTranscript value
      exit = case outcome of
        ProcessSucceeded _ -> "ExitSuccess"
        ProcessFailed value -> Text.pack (show (processFailureExitCode value))
  Posix.recordLifecycleEvent lease $
    object
      [ "event" .= ("command" :: Text)
      , "executable" .= subprocessPath spec
      , "argv" .= subprocessArguments spec
      , "cwd" .= subprocessWorkingDirectory spec
      , "actual_exit" .= exit
      , "stdout" .= processTranscriptStdout transcript
      , "stderr" .= processTranscriptStderr transcript
      , "duration_ns" .= processDurationNanoseconds (processTranscriptDuration transcript)
      ]
  pure outcome

requireSuccess :: ProcessOutcome -> IO Text
requireSuccess (ProcessSucceeded value) = pure (processTranscriptStdout value)
requireSuccess (ProcessFailed value) = failure (Text.unpack (renderProcessFailure value))

inRoot :: FilePath -> Subprocess -> Subprocess
inRoot root command = command {subprocessWorkingDirectory = Just root}

helperImage :: Posix.LifecycleLease -> FilePath -> IO Text
helperImage lease root = do
  let inventory =
        inRoot
          root
          (subprocess "docker" ["image", "ls", "--no-trunc", "--quiet", "--filter", "reference=jitml:local"])
      readIDs = Text.lines . Text.strip <$> (runObserved lease inventory >>= requireSuccess)
  identifiers <- readIDs
  case identifiers of
    [] ->
      failure
        "snapshot helper image is absent; build jitml:local explicitly with the cluster stopped before lifecycle operations"
    [identifier] -> pure identifier
    _ -> failure "canonical helper image inventory is missing or ambiguous"

makeBackend
  :: Posix.LifecycleLease
  -> FilePath
  -> Substrate
  -> ClusterResources
  -> Text
  -> Posix.PosixSnapshotStore
  -> IO Docker.DockerSnapshotConfig
makeBackend lease root substrate resources token store = do
  -- Snapshot helpers are siblings of a containerized CLI. Reserve their actual
  -- fixed caps inside the selected job slot before creating any helper or
  -- triggering the helper-image fallback build.
  budget <-
    checkResourceEnvelopeWithSiblingIO
      Docker.snapshotHelperMemoryBytes
      (Docker.snapshotHelperNanoCpus `div` 1000000)
      resources
  either (failure . Text.unpack) (const (pure ())) budget
  image <- helperImage lease root
  pure
    Docker.DockerSnapshotConfig
      { Docker.workspaceRoot = root
      , Docker.topology = kindConfigForWorkers substrate (workerCount resources)
      , Docker.closedManualPVs = manualPVsFor resources
      , Docker.helperImageID = image
      , Docker.generationToken = token
      , Docker.programs = defaultSnapshotPrograms
      , Docker.sourceMode = Docker.LiveQuiesced
      , Docker.kubectlCommand = \args ->
          inRoot root $
            subprocess
              "kubectl"
              ( [ "--kubeconfig"
                , Text.pack (root </> ".build/jitml.kubeconfig")
                , "--context"
                , "kind-" <> substrateClusterName substrate
                ]
                  <> args
              )
      , Docker.requireOwnedGeneration = Posix.reserveOwnedGeneration store
      , Docker.verifyHostArchive = Posix.verifyHostArchive store
      , Docker.recordSnapshotEvent = Posix.recordLifecycleEvent lease
      }

target
  :: FilePath -> [Text] -> IO (LifecycleTarget, Maybe BS.ByteString)
target root options = do
  explicit <- either (failure . Text.unpack) pure (parseLifecycleSubstrate options)
  (authority, bytes) <- readLifecyclePublication root
  selected <- either (failure . Text.unpack) pure (selectLifecycleTarget explicit authority)
  pure (selected, bytes)

ownedNodes :: Posix.LifecycleLease -> FilePath -> KindConfig -> IO [NodeIdentity]
ownedNodes lease root config = Docker.discoverOwnedKindNodes root config (Posix.recordLifecycleEvent lease)

deleteExact
  :: Posix.LifecycleLease -> FilePath -> Substrate -> KindConfig -> [NodeIdentity] -> IO ()
deleteExact lease root substrate config expected = do
  now <- ownedNodes lease root config
  unless (now == expected && not (null now)) (failure "Kind node ownership changed before deletion")
  void (runObserved lease (inRoot root (kindDeleteSubprocess substrate)) >>= requireSuccess)
  remaining <- ownedNodes lease root config
  unless (null remaining) (failure "Kind deletion returned without removing every owned node")

stopCluster :: FilePath -> [Text] -> IO StopOutcome
stopCluster workspace options = do
  root <- makeAbsolute workspace
  Posix.withPosixLifecycle root $ \lease -> do
    (selected, original) <- target root options
    let substrate = targetSubstrate selected
    resources <- loadClusterResourcesOrDefault root
    token <- freshToken
    let config = kindConfigForWorkers substrate (workerCount resources)
    nodes <- ownedNodes lease root config
    when (substrate /= LinuxCUDA && not (null nodes)) $
      Posix.assertReusableCluster lease (renderSubstrate substrate) nodes
    current <-
      if null nodes then pure original else invalidateReadiness lease root token selected original
    outcome <-
      if null nodes
        then pure ClusterAlreadyAbsent
        else do
          if substrate == LinuxCUDA
            then deleteExact lease root substrate config nodes
            else do
              store <-
                Posix.openPosixSnapshotStore
                  lease
                  (Posix.PosixSnapshotConfig root (renderSubstrate substrate) token)
              dockerConfig <- makeBackend lease root substrate resources token store
              request <- Docker.discoverSnapshotRequest dockerConfig
              unless (snapshotNodes request == nodes) (failure "Kind nodes changed before preservation")
              backend <- Docker.dockerSnapshotBackend dockerConfig
              void
                ( preserveBeforeDelete
                    backend
                    (Posix.snapshotStore store)
                    request
                    (deleteExact lease root substrate config . snapshotNodes)
                )
          pure ClusterDeleted
    case (current, targetPublication selected) of
      (Just bytes, Just publication) -> writeStoppedPublication lease root (Text.unpack token) bytes publication
      (Nothing, Nothing) -> pure ()
      _ -> failure "lifecycle publication read was inconsistent"
    Posix.recordLifecycleEvent
      lease
      (object ["event" .= ("cluster-stopped" :: Text), "outcome" .= show outcome])
    pure outcome

invalidateReadiness
  :: Posix.LifecycleLease
  -> FilePath
  -> Text
  -> LifecycleTarget
  -> Maybe BS.ByteString
  -> IO (Maybe BS.ByteString)
invalidateReadiness lease root token selected original = case (original, targetPublication selected) of
  (Just bytes, Just publication) ->
    Just <$> writeStoppingPublication lease root (Text.unpack token <> "-stopping") bytes publication
  (Nothing, Nothing) -> pure Nothing
  _ -> failure "lifecycle publication read was inconsistent"

-- Bootstrap alone owns readiness. This hook is called only for actual fresh
-- Kind creation, before any PV overlays, manifests or Helm releases.
restoreCreatedCluster
  :: Posix.LifecycleLease -> FilePath -> Substrate -> ClusterResources -> IO RestoreOutcome
restoreCreatedCluster _ _ LinuxCUDA _ = pure NoSelectedSnapshot
restoreCreatedCluster lease workspace substrate resources = do
  root <- makeAbsolute workspace
  token <- freshToken
  store <-
    Posix.openPosixSnapshotStore
      lease
      (Posix.PosixSnapshotConfig root (renderSubstrate substrate) token)
  selected <- readSelection (Posix.snapshotStore store)
  case selected of
    Nothing -> pure NoSelectedSnapshot
    Just saved -> do
      nodes <- ownedNodes lease root (kindConfigForWorkers substrate (workerCount resources))
      let request =
            SnapshotRequest
              (renderSubstrate substrate)
              (substrateClusterName substrate)
              nodes
              ( fmap
                  (Text.dropWhileEnd (== '/') . Text.dropWhile (== '/') . pvNodeDataPath)
                  (manualPVsFor resources)
              )
      config <- makeBackend lease root substrate resources token store
      actual <- Docker.discoverSnapshotRequest config
      unless (actual == request) (failure "fresh Kind nodes changed after restore selection")
      backend <- Docker.dockerSnapshotBackend config
      -- Caller/image/endpoint preflight failures must not consume a fresh-CID
      -- restoration attempt by writing a pending marker before any restore.
      restoration <- Posix.beginSnapshotRestore store request saved
      outcome <- restoreBeforeMounts backend (Posix.snapshotStore store) request
      unless
        (outcome == RestoredSnapshot (selectionGeneration saved))
        (failure "restore selected a different snapshot generation")
      Posix.completeSnapshotRestore restoration
      pure outcome

assertClusterReusable :: Posix.LifecycleLease -> FilePath -> Substrate -> ClusterResources -> IO ()
assertClusterReusable lease workspace substrate resources = do
  root <- makeAbsolute workspace
  nodes <- ownedNodes lease root (kindConfigForWorkers substrate (workerCount resources))
  when (null nodes) (failure "existing Kind nodes disappeared before reuse")
  when (substrate /= LinuxCUDA) (Posix.assertReusableCluster lease (renderSubstrate substrate) nodes)

resetCluster :: FilePath -> [Text] -> Bool -> IO ()
resetCluster workspace options full = do
  root <- makeAbsolute workspace
  Posix.withPosixLifecycle root $ \lease -> do
    (selected, original) <- target root options
    let substrate = targetSubstrate selected
    resources <- loadClusterResourcesOrDefault root
    let config = kindConfigForWorkers substrate (workerCount resources)
    observed <- Docker.discoverCanonicalKindClusters (Posix.recordLifecycleEvent lease)
    either (failure . Text.unpack) pure (requireExclusivePurgeTarget substrate observed)
    nodes <- ownedNodes lease root config
    token <- freshToken
    current <- invalidateReadiness lease root token selected original
    -- Durable outside-.data epochs are invalidated before any payload removal.
    Posix.invalidateAllSnapshotSelections lease
    unless (null nodes) (deleteExact lease root substrate config nodes)
    case (current, targetPublication selected) of
      (Just bytes, Just publication) -> writeStoppedPublication lease root (Text.unpack token) bytes publication
      (Nothing, Nothing) -> pure ()
      _ -> failure "lifecycle publication read was inconsistent"
    Posix.recordLifecycleEvent lease (object ["event" .= ("purge-start" :: Text), "full" .= full])
    purgeRuntimeRoots lease root (Text.unpack token) full
    -- Full purge deliberately removes its runtime receipts. Do not recreate
    -- .build or publish readiness after the removal.
    when (full && substrate /= AppleSilicon) $ do
      outcome <-
        runStreaming
          defaultSubprocessEnv
          (inRoot root (subprocess "docker" ["compose", "down", "--rmi", "local", "--volumes"]))
      writeLineIO (renderProcessOutcome outcome)
      void (requireSuccess outcome)
