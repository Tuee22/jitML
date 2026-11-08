{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Concrete Docker/quiescence/archive interpreter for node-local PV snapshots.
-- The caller supplies the POSIX store, exclusive generation, durable audit and
-- host FD verifier. No module initializer runs Docker.
module JitML.Cluster.PVSnapshotDocker
  ( DockerSnapshotConfig (..)
  , SnapshotSourceMode (..)
  , SnapshotPrograms (..)
  , defaultSnapshotPrograms
  , discoverOwnedKindNodes
  , discoverCanonicalKindClusters
  , discoverSnapshotRequest
  , dockerSnapshotBackend
  , validateSnapshotHelperResources
  , validateColdSnapshotNode
  , snapshotHelperMemoryBytes
  , snapshotHelperNanoCpus
  ) where

import Control.Exception
  ( SomeAsyncException
  , SomeException
  , displayException
  , fromException
  , mask
  , throwIO
  , toException
  , try
  )
import Control.Monad (filterM, forM, forM_, unless, void, when, (>=>))
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (..)
  , Result (..)
  , Value (..)
  , eitherDecodeStrict'
  , encode
  , fromJSON
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as Vector
import Numeric (showHex)
import System.Exit (ExitCode (..))
import System.FilePath (isAbsolute, normalise, (</>))

import JitML.Cluster.Kind (KindConfig (..), kindConfigNodeContainerNames)
import JitML.Cluster.PVSnapshot
import JitML.Cluster.PVSnapshotPrograms
  ( SnapshotPrograms (..)
  , defaultSnapshotPrograms
  , snapshotArchiveSHA256
  , snapshotManifestSHA256
  )
import JitML.Cluster.Storage (ManualPV, pvNodeDataPath)
import JitML.Sub.Outcome
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess (..), subprocess, subprocessWithStdin)
import JitML.Substrate (renderSubstrate)

-- Cold preservation is an explicit recovery operation. The caller must bind the
-- selected daemon/VM and prove that its containerd task namespaces are empty;
-- Docker's saved Running counter alone is not that physical runtime proof.
-- The hook is required and is invoked only between serial helper tasks.
data SnapshotSourceMode
  = LiveQuiesced
  | ColdStopped [NodeIdentity] (IO ())

data DockerSnapshotConfig = DockerSnapshotConfig
  { workspaceRoot :: FilePath
  , topology :: KindConfig
  , closedManualPVs :: [ManualPV]
  , helperImageID :: Text
  , generationToken :: Text
  , programs :: SnapshotPrograms
  , sourceMode :: SnapshotSourceMode
  , -- Exact typed prefix from the existing CLI's kubeconfig/tool interpreter.
    -- This permits host or image-owned kubectl without requiring a host install.
    kubectlCommand :: [Text] -> Subprocess
  , -- REQUIRED concrete POSIX hooks; no default no-op implementation is provided.
    -- Shared root: .data/.jitml-pv-snapshots/<lane>/generations/<token>, mode0700.
    requireOwnedGeneration :: IO ()
  , -- Relative to lane root, strict no-follow HOST FD open, regular/nlink1, full
    -- before/open/after path identity and SHA/size readback. Call before AND after
    -- every Docker read; do not equate guest 9P inode numbers with HOST identity.
    verifyHostArchive :: FilePath -> FileDigest -> IO ()
  , -- Must durably retain actual command statuses/streams and metadata under the
    -- owned generation. IO failures propagate; there is no fabricated transcript.
    recordSnapshotEvent :: Value -> IO ()
  }

data LiveNode = LiveNode
  { liveIdentity :: NodeIdentity
  , liveVarVolume :: Text
  , liveAddresses :: [Text]
  }
  deriving (Eq, Show)

data Controller = Controller
  { ownerKind :: Text
  , ownerName :: Text
  , ownerUID :: Text
  , ownerReplicas :: Int
  }
  deriving (Eq, Show)

abort :: String -> IO a
abort = throwIO . userError

require :: Bool -> String -> IO ()
require condition message = unless condition (abort message)

-- An earlier async always wins; otherwise the first async encountered while
-- compensating outranks an ordinary failure. Ordinary cleanup errors never
-- replace an existing primary. Every independent compensation is attempted.
preferFailure :: SomeException -> SomeException -> SomeException
preferFailure first later
  | asynchronous first = first
  | asynchronous later = later
  | otherwise = first
 where
  asynchronous value = case fromException value :: Maybe SomeAsyncException of
    Just _ -> True
    Nothing -> False

rememberFailure :: IORef SomeException -> Either SomeException a -> IO ()
rememberFailure pending result = case result of
  Left later -> modifyIORef' pending (`preferFailure` later)
  Right _ -> pure ()

json :: (FromJSON a) => Text -> IO a
json = either abort pure . eitherDecodeStrict' . TE.encodeUtf8

as :: (FromJSON a) => Value -> IO a
as value = case fromJSON value of Success result -> pure result; Error message -> abort message

field :: (FromJSON a) => Text -> Value -> IO a
field key (Object value) = maybe (abort ("missing " <> T.unpack key)) as (KM.lookup (Key.fromText key) value)
field _ _ = abort "expected JSON object"

at :: [Text] -> Value -> IO Value
at [] value = pure value
at (key : rest) value = field key value >>= at rest

items :: Value -> IO [Value]
items = field "items"

jsonText :: Value -> Text
jsonText = TE.decodeUtf8 . LBS.toStrict . encode

sha :: Text -> Text
sha =
  T.pack
    . concatMap (\b -> let s = showHex b "" in if length s == 1 then '0' : s else s)
    . BS.unpack
    . SHA256.hash
    . TE.encodeUtf8

audit :: DockerSnapshotConfig -> Text -> Value -> IO ()
audit config event detail = recordSnapshotEvent config (object ["event" .= event, "detail" .= detail])

-- Try includes async exceptions solely to retain the original and compensate;
-- it never converts cancellation into an exit code or successful snapshot.
command :: DockerSnapshotConfig -> Subprocess -> IO Text
command config = commandRecording (recordSnapshotEvent config)

commandRecording :: (Value -> IO ()) -> Subprocess -> IO Text
commandRecording record spec = mask $ \restore -> do
  attempted <- try (restore (runStreaming defaultSubprocessEnv spec))
  let base =
        [ "executable" .= subprocessPath spec
        , "argv" .= subprocessArguments spec
        , "cwd" .= subprocessWorkingDirectory spec
        , "stdin_sha256" .= fmap sha (subprocessStdin spec)
        ]
      report value = record (object ["event" .= ("command" :: Text), "detail" .= object (base <> value)])
      transcript value =
        [ "stdout" .= processTranscriptStdout value
        , "stderr" .= processTranscriptStderr value
        , "duration_ns" .= processDurationNanoseconds (processTranscriptDuration value)
        ]
  case attempted of
    Left (original :: SomeException) -> do
      recorded <- try (report ["attempt_exception" .= displayException original])
      throwIO (either (preferFailure original) (const original) (recorded :: Either SomeException ()))
    Right (ProcessFailed failed) -> do
      code <- case processFailureExitCode failed of
        ExitFailure number -> pure number
        ExitSuccess -> abort "invalid ProcessFailed success status"
      let original = toException (userError (T.unpack (renderProcessFailure failed)))
      recorded <- try (report (["actual_exit" .= code] <> transcript (processFailureTranscript failed)))
      throwIO (either (preferFailure original) (const original) (recorded :: Either SomeException ()))
    Right (ProcessSucceeded result) -> do
      report (["actual_exit" .= (0 :: Int)] <> transcript result)
      pure (processTranscriptStdout result)

docker :: DockerSnapshotConfig -> [Text] -> IO Text
docker config = command config . subprocess "docker"

kubectl :: DockerSnapshotConfig -> [Text] -> IO Value
kubectl config args = command config (kubectlCommand config args) >>= json

lane :: DockerSnapshotConfig -> Text
lane = renderSubstrate . kindConfigSubstrate . topology

laneRoot :: DockerSnapshotConfig -> FilePath
laneRoot config = workspaceRoot config </> ".data" </> ".jitml-pv-snapshots" </> T.unpack (lane config)

generationRelative :: DockerSnapshotConfig -> FilePath
generationRelative config = "generations" </> T.unpack (generationToken config)

generationRoot :: DockerSnapshotConfig -> FilePath
generationRoot config = laneRoot config </> generationRelative config

roots :: DockerSnapshotConfig -> [Text]
roots = fmap (T.dropWhileEnd (== '/') . T.dropWhile (== '/') . pvNodeDataPath) . closedManualPVs

checkConfig :: DockerSnapshotConfig -> IO ()
checkConfig config = do
  checkDiscoveryConfig (workspaceRoot config) (topology config)
  require (lane config `elem` ["linux-cpu", "apple-silicon"]) "not a node-local lane"
  require (kindConfigName (topology config) == "jitml-" <> lane config) "noncanonical Kind cluster"
  require
    ( T.length (helperImageID config) == 71
        && "sha256:" `T.isPrefixOf` helperImageID config
        && T.all (`elem` ("0123456789abcdef" :: String)) (T.drop 7 (helperImageID config))
    )
    "immutable helper image ID required"
  require
    ( not (T.null (generationToken config))
        && T.length (generationToken config) <= 40
        && T.all (`elem` ("abcdefghijklmnopqrstuvwxyz0123456789-" :: String)) (generationToken config)
    )
    "unsafe generation token"
  -- Resources must be the reviewed on-demand programs, not caller shell code.
  require
    (sha (manifestProgram (programs config)) == snapshotManifestSHA256)
    "manifest resource changed"
  require
    (sha (archiveIOProgram (programs config)) == snapshotArchiveSHA256)
    "archive I/O resource changed"
  case sourceMode config of
    LiveQuiesced -> pure ()
    ColdStopped expected _ -> do
      either abort pure $
        validateRequest
          (SnapshotRequest (lane config) (kindConfigName (topology config)) expected (roots config))
      require
        ( fmap (\node -> kindConfigName (topology config) <> "-" <> nodeRole node) expected
            == kindConfigNodeContainerNames (topology config)
            && all (validContainerID . nodeContainerId) expected
        )
        "cold source requires the exact ordered canonical node CIDs"

validContainerID :: Text -> Bool
validContainerID cid = T.length cid == 64 && T.all (`elem` ("0123456789abcdef" :: String)) cid

data ColdSnapshotNode = ColdSnapshotNode Text Bool Bool Bool Integer

instance FromJSON ColdSnapshotNode where
  parseJSON = withObject "cold snapshot node inspect" $ \value -> do
    state <- value .: "State"
    ColdSnapshotNode
      <$> value .: "Id"
      <*> state .: "Running"
      <*> state .: "Paused"
      <*> state .: "Restarting"
      <*> state .: "Pid"

-- | A stopped source is identified by a full immutable CID and physical state,
-- rather than by a Docker summary counter or a stale Kubernetes Ready value.
validateColdSnapshotNode :: Text -> Value -> Either String ()
validateColdSnapshotNode expected observed = do
  ColdSnapshotNode cid running paused restarting pid <- case fromJSON observed of
    Error message -> Left ("invalid cold snapshot node inspection: " <> message)
    Success value -> Right value
  unless (validContainerID expected && cid == expected) (Left "cold source node CID differs")
  unless
    (not running && not paused && not restarting && pid == 0)
    (Left "cold source node is not physically stopped")

checkDiscoveryConfig :: FilePath -> KindConfig -> IO ()
checkDiscoveryConfig root kindConfig = do
  require
    (isAbsolute root && normalise root == root && not (any (`elem` root) [',', '\n', '\NUL']))
    "unsafe workspace path"
  require
    (kindConfigName kindConfig == "jitml-" <> renderSubstrate (kindConfigSubstrate kindConfig))
    "noncanonical Kind cluster"

inspectUsing :: ([Text] -> IO Text) -> Text -> IO Value
inspectUsing runDocker identifier = do
  values <- runDocker ["inspect", "--type", "container", identifier] >>= json
  case values of [value] -> pure value; _ -> abort "container inspection membership"

inspectOne :: DockerSnapshotConfig -> Text -> IO Value
inspectOne config = inspectUsing (docker config)

-- Shared ownership decoder for CPU, Apple AND CUDA. Entirely absent returns [];
-- partial/foreign nodes never become an absent-cluster no-op. Stopped canonical
-- nodes still count as extant ownership; the snapshot path separately requires
-- running nodes/API/CRI before it may claim quiescence.
discoverOwnedKindNodes :: FilePath -> KindConfig -> (Value -> IO ()) -> IO [NodeIdentity]
discoverOwnedKindNodes root kindConfig record =
  fmap (fmap liveIdentity) (discoverUsing root kindConfig AnyNodeState True record)

-- Shared-.data purge can refuse any other extant jitML lane, including stopped
-- nodes. Unknown jitml-* labels fail closed, rather than disappear from scope.
discoverCanonicalKindClusters :: (Value -> IO ()) -> IO [Text]
discoverCanonicalKindClusters record = do
  output <-
    commandRecording
      record
      ( subprocess
          "docker"
          [ "ps"
          , "--all"
          , "--filter"
          , "label=io.x-k8s.kind.cluster"
          , "--format"
          , "{{.Label \"io.x-k8s.kind.cluster\"}}"
          ]
      )
  let names = Map.keys (Map.fromList [(name, ()) | name <- T.lines output, "jitml-" `T.isPrefixOf` name])
  require
    (all (`elem` ["jitml-apple-silicon", "jitml-linux-cpu", "jitml-linux-cuda"]) names)
    "unrecognized jitML Kind cluster; refuse shared-data purge"
  pure names

discover :: DockerSnapshotConfig -> IO [LiveNode]
discover config =
  discoverUsing
    (workspaceRoot config)
    (topology config)
    RunningNode
    False
    (recordSnapshotEvent config)

data NodeStateRequirement = AnyNodeState | RunningNode | StoppedNode
  deriving (Eq)

discoverSource :: DockerSnapshotConfig -> IO [LiveNode]
discoverSource config = case sourceMode config of
  LiveQuiesced -> discover config
  ColdStopped expected proveRuntime -> do
    nodes <-
      discoverUsing
        (workspaceRoot config)
        (topology config)
        StoppedNode
        False
        (recordSnapshotEvent config)
    require
      (fmap liveIdentity nodes == expected)
      "cold source node CIDs differ from the explicit recovery set"
    active <- docker config ["ps", "--no-trunc", "--format", "{{.ID}}"]
    require
      (T.null (T.strip active))
      "cold snapshot requires no active Docker containers between helpers"
    proveRuntime
    pure nodes

discoverUsing
  :: FilePath -> KindConfig -> NodeStateRequirement -> Bool -> (Value -> IO ()) -> IO [LiveNode]
discoverUsing root kindConfig stateRequirement allowAbsent record = do
  checkDiscoveryConfig root kindConfig
  let runDocker = commandRecording record . subprocess "docker"
  identifiers <-
    T.lines
      <$> runDocker
        [ "ps"
        , "--all"
        , "--no-trunc"
        , "--filter"
        , "label=io.x-k8s.kind.cluster=" <> kindConfigName kindConfig
        , "--format"
        , "{{.ID}}"
        ]
  observed <- forM identifiers $ \cid -> do
    value <- inspectUsing runDocker cid
    actualID <- field "Id" value
    name <- T.dropWhile (== '/') <$> field "Name" value
    labels <- at ["Config", "Labels"] value >>= as :: IO (Map.Map Text Text)
    running <- at ["State", "Running"] value >>= as
    when (stateRequirement == StoppedNode) $
      either abort pure (validateColdSnapshotNode cid value)
    mounts <- field "Mounts" value :: IO [Value]
    let canonical = kindConfigNodeContainerNames kindConfig
        role = T.drop (T.length (kindConfigName kindConfig) + 1) name
        kindRole = if role == "control-plane" then role else "worker"
    require
      ( actualID == cid
          && name `elem` canonical
          && (stateRequirement /= RunningNode || running)
          && Map.lookup "io.x-k8s.kind.cluster" labels == Just (kindConfigName kindConfig)
          && Map.lookup "io.x-k8s.kind.role" labels == Just kindRole
      )
      "Kind node identity/labels/state mismatch"
    forM_ [".build", ".data"] $ \part -> do
      found <- filterM (fmap (== "/jitml/" <> part) . field "Destination") mounts
      case found of
        [mount] -> do
          kind <- field "Type" mount
          source <- field "Source" mount
          rw <- field "RW" mount
          require
            (kind == ("bind" :: Text) && normalise (T.unpack source) == root </> T.unpack part && rw)
            "foreign workspace mount"
        _ -> abort "missing/duplicate workspace bind"
    vars <- filterM (fmap (== ("/var" :: Text)) . field "Destination") mounts
    volume <- case vars of
      [mount] -> do
        kind <- field "Type" mount
        rw <- field "RW" mount
        name' <- field "Name" mount
        require
          (kind == ("volume" :: Text) && rw && not (T.null name'))
          "node /var is not an owned Docker volume"
        pure name'
      _ -> abort "missing/duplicate node /var volume"
    networks <- at ["NetworkSettings", "Networks"] value >>= as :: IO (Map.Map Text Value)
    addresses <- concatForM (Map.elems networks) $ \network -> do
      ipv4 <- field "IPAddress" network
      ipv6 <- field "GlobalIPv6Address" network
      pure (filter (not . T.null) [ipv4, ipv6])
    require
      (stateRequirement /= RunningNode || not (null addresses))
      "Kind node has no observable network address"
    pure (name, LiveNode (NodeIdentity role cid) volume addresses)
  require (not (null observed) || allowAbsent) "Kind cluster is absent"
  if null observed
    then pure []
    else do
      require
        (sort (fmap fst observed) == sort (kindConfigNodeContainerNames kindConfig))
        "canonical node set differs"
      let byName = Map.fromList observed
      require (Map.size byName == length observed) "duplicate node identity"
      require
        (Map.size (Map.fromList [(liveVarVolume node, ()) | (_, node) <- observed]) == length observed)
        "nodes share /var volume"
      forM (kindConfigNodeContainerNames kindConfig) $ \name ->
        maybe (abort "missing canonical node") pure (Map.lookup name byName)

-- GHC 9.12's base predates concatForM. Keep the same left-to-right effect
-- ordering without adding a package dependency for this list traversal.
concatForM :: (Applicative m) => [a] -> (a -> m [b]) -> m [b]
concatForM [] _ = pure []
concatForM (value : values) action =
  (<>) <$> action value <*> concatForM values action

discoverSnapshotRequest :: DockerSnapshotConfig -> IO SnapshotRequest
discoverSnapshotRequest config = do
  checkConfig config
  nodes <- discoverSource config
  let request =
        SnapshotRequest
          (lane config)
          (kindConfigName (topology config))
          (fmap liveIdentity nodes)
          (roots config)
  either abort pure (validateRequest request)
  pure request

requestNodes :: DockerSnapshotConfig -> SnapshotRequest -> IO [LiveNode]
requestNodes config request = do
  require
    ( snapshotLane request == lane config
        && snapshotCluster request == kindConfigName (topology config)
        && registeredRoots request == roots config
    )
    "request differs from closed canonical registry"
  nodes <- discoverSource config
  require (fmap liveIdentity nodes == snapshotNodes request) "node CIDs changed"
  pure nodes

controller :: Value -> IO Controller
controller value =
  Controller
    <$> field "kind" value
    <*> (at ["metadata", "name"] value >>= as)
    <*> (at ["metadata", "uid"] value >>= as)
    <*> (at ["spec", "replicas"] value >>= as)

controllers :: DockerSnapshotConfig -> IO [Controller]
controllers config =
  kubectl config ["get", "deployment,statefulset", "-n", "platform", "-o", "json"]
    >>= items
    >>= traverse controller

-- Atomic UID+old-replicas tests prevent restoring a replacement controller or
-- overwriting a concurrent owner's scaling change. All captured owners are
-- attempted on compensation, preserving the original exception.
patchReplicas :: DockerSnapshotConfig -> Controller -> Int -> Int -> IO ()
patchReplicas config owner from to =
  void $
    command config $
      kubectlCommand
        config
        [ "patch"
        , T.toLower (ownerKind owner)
        , ownerName owner
        , "-n"
        , "platform"
        , "--type=json"
        , "-p"
        , jsonText toJSONPatch
        ]
 where
  toJSONPatch =
    Array $
      fromListV
        [ object ["op" .= ("test" :: Text), "path" .= ("/metadata/uid" :: Text), "value" .= ownerUID owner]
        , object ["op" .= ("test" :: Text), "path" .= ("/spec/replicas" :: Text), "value" .= from]
        , object ["op" .= ("replace" :: Text), "path" .= ("/spec/replicas" :: Text), "value" .= to]
        ]

fromListV :: [Value] -> Vector.Vector Value
fromListV = Vector.fromList

assertKubeNodes :: DockerSnapshotConfig -> [LiveNode] -> IO ()
assertKubeNodes config nodes = do
  values <- kubectl config ["get", "nodes", "-o", "json"] >>= items
  named <- forM values $ \value -> do
    name <- at ["metadata", "name"] value >>= as
    labels <- at ["metadata", "labels"] value >>= as :: IO (Map.Map Text Text)
    addresses <- at ["status", "addresses"] value >>= as :: IO [Value]
    internal <- filterM (fmap (== ("InternalIP" :: Text)) . field "type") addresses
    ips <- traverse (field "address") internal
    expected <- case filter
      (\node -> kindConfigName (topology config) <> "-" <> nodeRole (liveIdentity node) == name)
      nodes of
      [node] -> pure node
      _ -> abort "Kubernetes node is not the canonical Docker node"
    require
      ( Map.lookup ("jitml.substrate/" <> lane config) labels == Just "true"
          && not (null ips)
          && all (`elem` liveAddresses expected) ips
      )
      "Kubernetes context/node address mismatch"
    pure name
  require
    (sort named == sort (kindConfigNodeContainerNames (topology config)))
    "Kubernetes node membership mismatch"

assertClosedPVRegistry :: DockerSnapshotConfig -> IO ()
assertClosedPVRegistry config = do
  pvs <- kubectl config ["get", "pv", "-o", "json"] >>= items
  let expected = fmap ("/" <>) (roots config)
  paths <- concatForM pvs $ \value -> do
    spec <- field "spec" value :: IO Value
    case spec of
      Object fields -> case KM.lookup "local" fields of
        Nothing -> pure []
        Just local -> do
          path <- field "path" local
          if "/jitml/.data/" `T.isPrefixOf` path
            then do
              require
                (any (\root -> path == root || path == root <> "/") expected)
                "unregistered node-local PV path"
              claim <- field "claimRef" spec :: IO Value
              namespace <- field "namespace" claim
              require (namespace == ("platform" :: Text)) "registered PV claimed outside platform"
              pure [if "/" `T.isSuffixOf` path then T.dropEnd 1 path else path]
            else pure []
      _ -> abort "invalid PV spec"
  require (sort paths == sort expected) "actual PV registry differs from manualPVsFor"

assertNoOtherVolumeWriters :: DockerSnapshotConfig -> [LiveNode] -> IO ()
assertNoOtherVolumeWriters config nodes = do
  allCIDs <- T.lines <$> docker config ["ps", "--no-trunc", "--format", "{{.ID}}"]
  let ownCIDs = fmap (nodeContainerId . liveIdentity) nodes
      volumes = fmap liveVarVolume nodes
  forM_ (filter (`notElem` ownCIDs) allCIDs) $ \cid -> do
    details <- inspectOne config cid
    mounts <- field "Mounts" details :: IO [Value]
    forM_ mounts $ \mount -> do
      kind <- field "Type" mount
      when (kind == ("volume" :: Text)) $ do
        name <- field "Name" mount
        rw <- field "RW" mount
        require (not (name `elem` volumes && rw)) "another Docker container can write a node /var volume"

assertNoWriters :: DockerSnapshotConfig -> SnapshotRequest -> [Controller] -> IO ()
assertNoWriters config request original = do
  nodes <- requestNodes config request
  assertKubeNodes config nodes
  assertNoOtherVolumeWriters config nodes
  current <- controllers config
  require
    ( sort (fmap ownerKey current) == sort (fmap ownerKey original)
        && all ((== 0) . ownerReplicas) current
    )
    "platform controller membership/replicas changed"
  pods <- kubectl config ["get", "pods", "-n", "platform", "-o", "json"] >>= items
  forM_ pods $ \pod -> do
    phase <- at ["status", "phase"] pod >>= as
    require
      (phase `elem` (["Succeeded", "Failed"] :: [Text]))
      "active platform pod remains while capturing PVs"
  forM_ nodes $ \node -> do
    allContainers <-
      docker
        config
        [ "exec"
        , nodeContainerId (liveIdentity node)
        , "crictl"
        , "--runtime-endpoint"
        , "unix:///run/containerd/containerd.sock"
        , "ps"
        , "-o"
        , "json"
        ]
        >>= json
        >>= field "containers"
        :: IO [Value]
    forM_ allContainers $ \container -> do
      labels <- field "labels" container :: IO (Map.Map Text Text)
      require
        (Map.lookup "io.kubernetes.pod.namespace" labels /= Just "platform")
        "platform CRI process remains"
      cid <- field "id" container
      details <-
        docker
          config
          [ "exec"
          , nodeContainerId (liveIdentity node)
          , "crictl"
          , "--runtime-endpoint"
          , "unix:///run/containerd/containerd.sock"
          , "inspect"
          , cid
          ]
          >>= json
      mounts <- at ["info", "runtimeSpec", "mounts"] details >>= as :: IO [Value]
      forM_ mounts $ \mount -> do
        source <- field "source" mount
        destination <- field "destination" mount
        let protected path =
              any
                (\root -> path == root || (root <> "/") `T.isPrefixOf` path)
                ("/var/local/jitml-stateful-pv" : fmap ("/" <>) (registeredRoots request))
        require
          (not (protected source || protected destination))
          "unpaused CRI container mounts registered PV storage"
 where
  ownerKey owner = (ownerKind owner, ownerName owner, ownerUID owner)

refuseAutonomousWriters :: DockerSnapshotConfig -> IO ()
refuseAutonomousWriters config = do
  extras <-
    kubectl config ["get", "hpa,cronjob,job,daemonset", "-n", "platform", "-o", "json"] >>= items
  forM_ extras $ \value -> do
    kind <- field "kind" value
    require
      (kind == ("Job" :: Text))
      "autonomous platform writer/controller requires an explicit quiescence adapter"
    conditions <- at ["status", "conditions"] value >>= as :: IO [Value]
    terminal <-
      filterM
        ( \condition -> do
            label <- field "type" condition
            status <- field "status" condition
            pure (label `elem` (["Complete", "Failed"] :: [Text]) && status == ("True" :: Text))
        )
        conditions
    require (not (null terminal)) "nonterminal platform Job can still create writers"
  -- Arbitrary direct hostPath/PVC writers are not inferred to be harmless.
  pvcs <- kubectl config ["get", "pods", "--all-namespaces", "-o", "json"] >>= items
  forM_ pvcs $ \pod -> do
    namespace <- at ["metadata", "namespace"] pod >>= as
    volumes <- at ["spec", "volumes"] pod >>= as :: IO [Value]
    when (namespace /= ("platform" :: Text)) $ forM_ volumes $ \case
      Object value ->
        when (KM.member "persistentVolumeClaim" value) $
          abort "non-platform PVC writer requires explicit registry proof"
      _ -> abort "invalid pod volume"

withPaused :: DockerSnapshotConfig -> IORef (Maybe [Controller]) -> SnapshotRequest -> IO a -> IO a
withPaused config active request action = mask $ \restore -> do
  nodes <- restore (requestNodes config request)
  restore (assertKubeNodes config nodes)
  restore (assertClosedPVRegistry config)
  restore (refuseAutonomousWriters config)
  original <- restore (controllers config)
  require
    (not (null original) && all ((>= 0) . ownerReplicas) original)
    "missing platform controller registry"
  audit config "captured-controller-replicas" (object ["controllers" .= fmap ownerJSON original])
  writeIORef active (Just original)
  result <- try $ restore $ do
    forM_ original $ \owner -> patchReplicas config owner (ownerReplicas owner) 0
    remainingPods <- kubectl config ["get", "pods", "-n", "platform", "-o", "json"] >>= items
    activePods <-
      filterM
        ( \pod -> do
            phase <- at ["status", "phase"] pod >>= as
            pure (phase `notElem` (["Succeeded", "Failed"] :: [Text]))
        )
        remainingPods
    podNames <- forM activePods (at ["metadata", "name"] >=> as)
    unless (null podNames) $
      void $
        command config $
          kubectlCommand
            config
            (["wait", "--for=delete", "-n", "platform", "--timeout=90s"] <> fmap ("pod/" <>) podNames)
    assertNoWriters config request original
    value <- action
    -- Successful preservation callback must actually remove THIS cluster.
    remaining <-
      docker
        config
        [ "ps"
        , "--all"
        , "--no-trunc"
        , "--filter"
        , "label=io.x-k8s.kind.cluster=" <> snapshotCluster request
        , "--format"
        , "{{.ID}}"
        ]
    require (T.null (T.strip remaining)) "delete callback returned while old Kind nodes remain"
    pure value
  case result of
    Right value -> writeIORef active Nothing >> pure value
    Left (first :: SomeException) -> do
      pending <- newIORef first
      stillOriginal <- try (requestNodes config request) :: IO (Either SomeException [LiveNode])
      rememberFailure pending stillOriginal
      case stillOriginal of
        Left reason -> do
          noted <- try (audit config "compensation-NotRun" (object ["reason" .= displayException reason]))
          rememberFailure pending (noted :: Either SomeException ())
        Right _ -> forM_ original $ \owner -> do
          compensated <- try $ do
            current <- controllers config
            same <- case filter
              ( \x -> ownerKind x == ownerKind owner && ownerName x == ownerName owner && ownerUID x == ownerUID owner
              )
              current of
              [found] -> pure found
              _ -> abort "original controller UID no longer present"
            if ownerReplicas same == ownerReplicas owner
              then pure ()
              else patchReplicas config owner 0 (ownerReplicas owner)
          rememberFailure pending (compensated :: Either SomeException ())
          noted <-
            try
              ( audit
                  config
                  "compensation"
                  ( object
                      [ "controller" .= ownerJSON owner
                      , "result" .= either displayException (const "restored-or-already-original") compensated
                      ]
                  )
              )
          rememberFailure pending (noted :: Either SomeException ())
      writeIORef active Nothing
      readIORef pending >>= throwIO
 where
  ownerJSON owner =
    object
      [ "kind" .= ownerKind owner
      , "name" .= ownerName owner
      , "uid" .= ownerUID owner
      , "replicas" .= ownerReplicas owner
      ]

assertColdIdle :: DockerSnapshotConfig -> IO ()
assertColdIdle config = case sourceMode config of
  LiveQuiesced -> pure ()
  ColdStopped _ _ -> void (discoverSource config)

-- Already stopped source nodes require no scale-down or compensation. In
-- particular this bracket never calls kubectl, docker exec or docker start on
-- a source node. Its caller still supplies the real exact-node delete callback.
withStoppedSources
  :: DockerSnapshotConfig -> IORef (Maybe [LiveNode]) -> SnapshotRequest -> IO a -> IO a
withStoppedSources config active request action = mask $ \restore -> do
  existing <- readIORef active
  require (isNothing existing) "nested cold snapshot lifecycle"
  nodes <- restore (requestNodes config request)
  audit config "captured-cold-stopped-sources" (object ["nodes" .= fmap liveIdentity nodes])
  writeIORef active (Just nodes)
  result <- try $ restore $ do
    value <- action
    remaining <-
      docker
        config
        [ "ps"
        , "--all"
        , "--no-trunc"
        , "--filter"
        , "label=io.x-k8s.kind.cluster=" <> snapshotCluster request
        , "--format"
        , "{{.ID}}"
        ]
    require (T.null (T.strip remaining)) "cold delete callback returned while old Kind nodes remain"
    -- The nodes are now deliberately absent, so discovery is no longer the
    -- applicable postcondition. Check actual daemon/task idleness instead.
    running <- docker config ["ps", "--no-trunc", "--format", "{{.ID}}"]
    require (T.null (T.strip running)) "active Docker container after cold preservation"
    case sourceMode config of
      ColdStopped _ proveRuntime -> proveRuntime
      LiveQuiesced -> abort "cold bracket requires ColdStopped mode"
    pure value
  writeIORef active Nothing
  case result of
    Right value -> pure value
    Left (first :: SomeException) -> do
      noted <-
        try
          ( audit
              config
              "cold-preservation-failed-no-source-resume"
              (object ["reason" .= displayException first])
          )
      throwIO (either (preferFailure first) (const first) (noted :: Either SomeException ()))

-- Source /var volumes must remain read-only even if a daemon changes the
-- requested create settings. Scratch volumes and the new archive generation
-- are separate writable targets and are not source-node volumes.
assertColdHelperMounts :: DockerSnapshotConfig -> [Text] -> Value -> IO ()
assertColdHelperMounts config requested helperInfo = case sourceMode config of
  LiveQuiesced -> pure ()
  ColdStopped _ _ -> do
    sources <- discoverSource config
    mounts <- field "Mounts" helperInfo :: IO [Value]
    actual <- concatForM mounts $ \mount -> do
      kind <- field "Type" mount
      if kind == ("volume" :: Text)
        then do
          name <- field "Name" mount
          if name `elem` fmap liveVarVolume sources
            then do
              rw <- field "RW" mount
              target <- field "Destination" mount
              require (not rw) "cold helper has a writable source /var volume"
              pure [(name, target)]
            else pure []
        else pure []
    let expected =
          [ (volume, target)
          | mount <- requested
          , ["type=volume", source, destination, "readonly"] <- [T.splitOn "," mount]
          , Just volume <- [T.stripPrefix "source=" source]
          , volume `elem` fmap liveVarVolume sources
          , Just target <- [T.stripPrefix "target=" destination]
          ]
    require (sort actual == sort expected) "cold helper source volume/mount identity differs"

volumeMount :: Text -> Text -> Bool -> Text
volumeMount volume target readonly =
  "type=volume,source="
    <> volume
    <> ",target="
    <> target
    <> if readonly then ",readonly" else ",volume-nocopy"

bindMount :: FilePath -> Text -> Bool -> Text
bindMount source target readonly =
  "type=bind,source="
    <> T.pack source
    <> ",target="
    <> target
    <> if readonly then ",readonly" else ""

-- Serial archive bytes are streamed, but the reviewed Python programs retain
-- per-file manifest/member metadata. These immutable limits are a failure
-- boundary, not evidence that every possible PV fits in the helper's heap.
snapshotHelperMemoryBytes, snapshotHelperNanoCpus, snapshotHelperPids :: Integer
snapshotHelperMemoryBytes = 536870912
snapshotHelperNanoCpus = 500000000
snapshotHelperPids = 64

snapshotHelperTmpfsOptions :: Text
snapshotHelperTmpfsOptions = "rw,nosuid,nodev,size=67108864"

data SnapshotHelperResources
  = SnapshotHelperResources Integer Integer Integer Integer (Map.Map Text Text)

instance FromJSON SnapshotHelperResources where
  parseJSON = withObject "snapshot helper inspect" $ \value -> do
    host <- value .: "HostConfig"
    SnapshotHelperResources
      <$> host .: "Memory"
      <*> host .: "MemorySwap"
      <*> host .: "NanoCpus"
      <*> host .: "PidsLimit"
      <*> host .: "Tmpfs"

-- | Verify actual Docker HostConfig before an inert helper can start. Missing,
-- unlimited, malformed or changed limits refuse; tmpfs option order alone is
-- irrelevant. This is a Docker configuration proof, not a whole-VM envelope or
-- a claim that the admitted workload will avoid OOM.
validateSnapshotHelperResources :: Value -> Either String ()
validateSnapshotHelperResources observed = do
  SnapshotHelperResources memory swap cpu pids tmpfs <- case fromJSON observed of
    Error message -> Left ("invalid snapshot helper resource inspection: " <> message)
    Success value -> Right value
  check (memory == snapshotHelperMemoryBytes) "snapshot helper Memory differs from its fixed budget"
  check (swap == memory) "snapshot helper MemorySwap must equal Memory to disable swap"
  check (cpu == snapshotHelperNanoCpus) "snapshot helper NanoCpus differs from its fixed budget"
  check (pids == snapshotHelperPids) "snapshot helper PidsLimit differs from its fixed budget"
  check
    ( Map.keys tmpfs == ["/tmp"]
        && fmap (sort . T.splitOn ",") (Map.lookup "/tmp" tmpfs)
          == Just (sort (T.splitOn "," snapshotHelperTmpfsOptions))
    )
    "snapshot helper Tmpfs must contain only the bounded 64-MiB /tmp mount"
 where
  check condition message = unless condition (Left message)

-- A created helper is inert until its exact CID is captured. On failure/cancel
-- terminate ONLY that CID after verifying owner labels+immutable image. Failed
-- create can retain an inert labelled container, never an unowned tar writer.
helper :: DockerSnapshotConfig -> IORef Int -> [Text] -> Text -> [Text] -> IO Text
helper config serial mounts program args = mask $ \restore -> do
  restore (assertColdIdle config)
  index <- atomicModifyIORef' serial (\n -> (n + 1, n))
  let name = "jitml-pv-" <> generationToken config <> "-" <> T.pack (show index)
      owner = generationToken config
  cid <-
    T.strip
      <$> restore
        ( docker
            config
            ( [ "create"
              , "--rm"
              , "--interactive"
              , "--name"
              , name
              , "--network"
              , "none"
              , "--read-only"
              , "--cpus"
              , "0.5"
              , "--memory"
              , T.pack (show snapshotHelperMemoryBytes)
              , "--memory-swap"
              , T.pack (show snapshotHelperMemoryBytes)
              , "--pids-limit"
              , T.pack (show snapshotHelperPids)
              , "--tmpfs"
              , "/tmp:" <> snapshotHelperTmpfsOptions
              , "--label"
              , "jitml.pv-snapshot.operation=" <> owner
              , "--label"
              , "jitml.pv-snapshot.workspace=" <> T.pack (workspaceRoot config)
              ]
                <> concatMap (\m -> ["--mount", m]) mounts
                <> ["--entrypoint", "python3", helperImageID config, "-"]
                <> args
            )
        )
  require
    (T.length cid == 64 && T.all (`elem` ("0123456789abcdef" :: String)) cid)
    "helper create returned invalid CID"
  observed <- inspectOne config cid
  createdCID <- field "Id" observed
  actualImage <- field "Image" observed
  createdLabels <- at ["Config", "Labels"] observed >>= as :: IO (Map.Map Text Text)
  createdRunning <- at ["State", "Running"] observed >>= as
  createdPaused <- at ["State", "Paused"] observed >>= as
  createdRestarting <- at ["State", "Restarting"] observed >>= as
  createdPid <- at ["State", "Pid"] observed >>= as :: IO Integer
  require
    ( createdCID == cid
        && actualImage == helperImageID config
        && Map.lookup "jitml.pv-snapshot.operation" createdLabels == Just owner
        && Map.lookup "jitml.pv-snapshot.workspace" createdLabels == Just (T.pack (workspaceRoot config))
    )
    "created helper ownership changed"
  require
    (not createdRunning && not createdPaused && not createdRestarting && createdPid == 0)
    "created snapshot helper is not inert"
  either abort pure (validateSnapshotHelperResources observed)
  restore (assertColdHelperMounts config mounts observed)
  attempted <-
    try
      ( restore
          (command config (subprocessWithStdin "docker" ["start", "--attach", "--interactive", cid] program))
      )
  case attempted of
    Right output -> restore (assertColdIdle config) >> pure output
    Left (first :: SomeException) -> do
      pending <- newIORef first
      cleanup <- try $ do
        info <- inspectOne config cid
        actualCID <- field "Id" info
        image <- field "Image" info
        labels <- at ["Config", "Labels"] info >>= as :: IO (Map.Map Text Text)
        running <- at ["State", "Running"] info >>= as
        require
          ( actualCID == cid
              && image == helperImageID config
              && Map.lookup "jitml.pv-snapshot.operation" labels == Just owner
              && Map.lookup "jitml.pv-snapshot.workspace" labels == Just (T.pack (workspaceRoot config))
          )
          "helper ownership changed"
        when running $
          void (docker config ["kill", "--signal=KILL", cid]) >> void (docker config ["wait", cid])
      rememberFailure pending (cleanup :: Either SomeException ())
      idle <- try (restore (assertColdIdle config))
      rememberFailure pending (idle :: Either SomeException ())
      noted <-
        try
          ( audit
              config
              "failed-helper-stop"
              ( object
                  [ "cid" .= cid
                  , "result" .= either displayException (const "stopped-or-already-stopped") cleanup
                  ]
              )
          )
      rememberFailure pending (noted :: Either SomeException ())
      readIORef pending >>= throwIO

manifest :: DockerSnapshotConfig -> IORef Int -> Text -> Text -> IO BS.ByteString
manifest config serial volume path =
  TE.encodeUtf8
    <$> helper
      config
      serial
      [volumeMount volume "/nodevar" True]
      (manifestProgram (programs config))
      [path]

ioHelper :: DockerSnapshotConfig -> IORef Int -> [Text] -> [Text] -> IO Value
ioHelper config serial mounts args = helper config serial mounts (archiveIOProgram (programs config)) args >>= json

digestFrom :: Value -> IO FileDigest
digestFrom value = FileDigest <$> field "digestBytes" value <*> field "digestSHA256" value

checkArchive :: DockerSnapshotConfig -> IORef Int -> FilePath -> FileDigest -> IO ()
checkArchive config serial relative expected = do
  -- Immutable selection explicitly carries the OLD generation in this path;
  -- never substitute the current capture token or reread a mutable selector.
  case T.splitOn "/" (T.pack relative) of
    ["generations", token, leaf] ->
      require (safe token && safe leaf && ".pax" `T.isSuffixOf` leaf) "unsafe selected generation archive"
    _ -> abort "archive must be generations/token/role.pax relative to lane root"
  verifyHostArchive config relative expected
  observed <-
    ioHelper
      config
      serial
      [bindMount (laneRoot config) "/snapshots" True]
      ["digest", "/snapshots/" <> T.pack relative]
      >>= digestFrom
  require (observed == expected) "archive digest readback differs"
  verifyHostArchive config relative expected
 where
  safe value =
    not (T.null value)
      && value /= "."
      && value /= ".."
      && T.all (`elem` ("abcdefghijklmnopqrstuvwxyz0123456789-." :: String)) value

findNode :: DockerSnapshotConfig -> SnapshotRequest -> NodeIdentity -> IO LiveNode
findNode config request node =
  requestNodes config request >>= \nodes -> case filter ((== node) . liveIdentity) nodes of
    [value] -> pure value
    _ -> abort "node not in exact request"

scratchVolume :: DockerSnapshotConfig -> NodeIdentity -> IO Text
scratchVolume config node = do
  let name = "jitml-pv-check-" <> generationToken config <> "-" <> nodeRole node
  existing <- docker config ["volume", "ls", "--format", "{{.Name}}"]
  require (name `notElem` T.lines existing) "scratch volume already exists; no reuse"
  actual <-
    T.strip
      <$> docker
        config
        [ "volume"
        , "create"
        , "--label"
        , "jitml.pv-snapshot.operation=" <> generationToken config
        , "--label"
        , "jitml.pv-snapshot.purpose=scratch"
        , name
        ]
  require (actual == name) "scratch volume create membership"
  verifyScratch config name
  pure name

verifyScratch :: DockerSnapshotConfig -> Text -> IO ()
verifyScratch config name = do
  values <- docker config ["volume", "inspect", name] >>= json
  value <- case values of [one] -> pure one; _ -> abort "scratch inspection membership"
  labels <- field "Labels" value :: IO (Map.Map Text Text)
  require
    ( Map.lookup "jitml.pv-snapshot.operation" labels == Just (generationToken config)
        && Map.lookup "jitml.pv-snapshot.purpose" labels == Just "scratch"
    )
    "scratch volume ownership mismatch"

emptyIdentity :: DockerSnapshotConfig -> IORef Int -> Text -> Text -> Text -> Bool -> IO Value
emptyIdentity config serial volume parent leaf create = do
  value <-
    ioHelper
      config
      serial
      [volumeMount volume "/nodevar" False]
      ["empty", parent, leaf, if create then "create" else "existing"]
  entries <- field "entries" value :: IO [Value]
  require (null entries) "nonempty restore target"
  field "identity" value

extractArchive
  :: DockerSnapshotConfig -> IORef Int -> Text -> Text -> Value -> NodeSnapshot -> IO ()
extractArchive config serial volume target expectedRoot saved = do
  checkArchive config serial (savedArchive saved) (savedDigest saved)
  void $
    ioHelper
      config
      serial
      [volumeMount volume "/nodevar" False, bindMount (laneRoot config) "/snapshots" True]
      [ "extract"
      , "/snapshots/" <> T.pack (savedArchive saved)
      , target
      , T.pack (show (digestBytes (savedDigest saved)))
      , digestSHA256 (savedDigest saved)
      , jsonText expectedRoot
      ]
  checkArchive config serial (savedArchive saved) (savedDigest saved)

assertNoPVOverlays :: DockerSnapshotConfig -> SnapshotRequest -> LiveNode -> IO ()
assertNoPVOverlays config request node = do
  mountinfo <-
    docker config ["exec", nodeContainerId (liveIdentity node), "cat", "/proc/self/mountinfo"]
  forM_ (T.lines mountinfo) $ \line -> case T.words line of
    (_ : _ : _ : _ : target : _) ->
      require
        ( not
            ( any
                (\root -> target == root || (root <> "/") `T.isPrefixOf` target)
                ("/var/local/jitml-stateful-pv" : fmap ("/" <>) (registeredRoots request))
            )
        )
        "fresh node already has PV overlays"
    _ -> abort "malformed actual mountinfo"

dockerSnapshotBackend :: DockerSnapshotConfig -> IO SnapshotBackend
dockerSnapshotBackend config = do
  checkConfig config
  serial <- newIORef 0
  active <- newIORef Nothing
  coldActive <- newIORef Nothing
  fresh <- newIORef Map.empty
  let paused request = case sourceMode config of
        LiveQuiesced ->
          readIORef active >>= maybe (abort "not inside quiesced lifecycle") (assertNoWriters config request)
        ColdStopped _ _ -> do
          original <- readIORef coldActive >>= maybe (abort "not inside cold lifecycle") pure
          now <- requestNodes config request
          require (now == original) "cold source node/volume identity changed"
      capture request node = do
        paused request
        requireOwnedGeneration config
        actual <- findNode config request node
        before <- manifest config serial (liveVarVolume actual) "/nodevar/local/jitml-stateful-pv"
        let relative = generationRelative config </> T.unpack (nodeRole node) <> ".pax"
            leaf = nodeRole node <> ".pax"
        digest <-
          ioHelper
            config
            serial
            [ volumeMount (liveVarVolume actual) "/nodevar" True
            , bindMount (generationRoot config) "/generation" False
            ]
            ["archive", "/nodevar/local/jitml-stateful-pv", "/generation", leaf]
            >>= digestFrom
        verifyHostArchive config relative digest
        after <- manifest config serial (liveVarVolume actual) "/nodevar/local/jitml-stateful-pv"
        let saved = NodeSnapshot node relative digest before
        scratch <- scratchVolume config node
        targetIdentity <- emptyIdentity config serial scratch "/" "nodevar" False
        extractArchive config serial scratch "/nodevar" targetIdentity saved
        restored <- manifest config serial scratch "/nodevar"
        -- Validate before removing scratch; failed/unverified scratch is retained.
        left <- either abort pure (decodeTreeManifest request before)
        right <- either abort pure (decodeTreeManifest request restored)
        sourceAfter <- either abort pure (decodeTreeManifest request after)
        require (left == sourceAfter && sameRestoredTree left right) "scratch/source verification failed"
        paused request
        verifyScratch config scratch
        void (docker config ["volume", "rm", scratch])
        pure (NodeCandidate node relative digest before after restored)
      revalidate request saved = do
        paused request
        forM_ saved $ \node -> do
          actual <- findNode config request (savedNode node)
          bytes <- manifest config serial (liveVarVolume actual) "/nodevar/local/jitml-stateful-pv"
          expected <- either abort pure (decodeTreeManifest request (savedManifest node))
          observed <- either abort pure (decodeTreeManifest request bytes)
          require (expected == observed) "source changed before selection/delete"
          checkArchive config serial (savedArchive node) (savedDigest node)
      requireFresh request = do
        case sourceMode config of
          LiveQuiesced -> pure ()
          ColdStopped _ _ -> abort "fresh restore requires a separate LiveQuiesced backend"
        nodes <- requestNodes config request
        forM_ nodes $ \node -> do
          assertNoPVOverlays config request node
          identity <-
            emptyIdentity config serial (liveVarVolume node) "/nodevar/local" "jitml-stateful-pv" True
          modifyIORef' fresh (Map.insert (nodeContainerId (liveIdentity node)) (node, identity))
      restore node saved = do
        observed <- readIORef fresh
        (actual, identity) <-
          maybe
            (abort "all-node fresh preflight not performed")
            pure
            (Map.lookup (nodeContainerId node) observed)
        -- Recheck canonical CIDs/binds AND same-domain root identity immediately
        -- before the extraction; expectedRoot is checked again while held open.
        now <- discover config
        require (actual `elem` now) "fresh node replaced before restore"
        identityNow <-
          emptyIdentity config serial (liveVarVolume actual) "/nodevar/local" "jitml-stateful-pv" False
        require (identity == identityNow) "fresh root identity changed"
        extractArchive
          config
          serial
          (liveVarVolume actual)
          "/nodevar/local/jitml-stateful-pv"
          identity
          saved
        manifest config serial (liveVarVolume actual) "/nodevar/local/jitml-stateful-pv"
  pure
    SnapshotBackend
      { withQuiesced = case sourceMode config of
          LiveQuiesced -> withPaused config active
          ColdStopped _ _ -> withStoppedSources config coldActive
      , captureAndScratchRestore = capture
      , revalidateSourceNodes = revalidate
      , requireFreshEmptyRoots = requireFresh
      , verifySelectedArchive = \saved -> checkArchive config serial (savedArchive saved) (savedDigest saved)
      , restoreNode = restore
      }
