{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

-- | Node-local PV projection must precede the node's runtime and kubelet on
-- every boot. A later overmount cannot repair an already-bound Pod volume.
-- The bundle is also exported for a controlled repair of stopped, retained
-- node CIDs; it never changes PV/PVC objects or restores/initializes payloads.
module JitML.Cluster.StatefulPV
  ( StatefulPVConsumer (..)
  , statefulPVScriptPath
  , statefulPVServiceName
  , statefulPVStartupUnit
  , statefulPVDependencyDropIn
  , renderStatefulPVProjectionScript
  , statefulPVBundleFiles
  , statefulPVInitializeSubprocess
  , statefulPVFreshInstallSubprocesses
  , parseStatefulPVConsumers
  , validateStatefulPVUnitProperties
  , verifyStatefulPVReuseIO
  )
where

import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless, void)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (Value, eitherDecodeStrict', withObject, (.!=), (.:), (.:?))
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as ByteString
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Either.Combinators (mapLeft)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Numeric (showHex)
import System.FilePath (takeDirectory)
import System.Timeout (timeout)

import JitML.Cluster.Kind (substrateKindNodeContainerNames)
import JitML.Cluster.Resources (ClusterResources, workerCount)
import JitML.Cluster.Storage (ManualPV (..), manualPVsFor, pvIsPostgres, pvNodeDataPath)
import JitML.Sub.Outcome (ProcessOutcome (..), ProcessTranscript (..), renderProcessFailure)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess, subprocessWithStdin)
import JitML.Substrate (Substrate (LinuxCUDA), substrateClusterName)

statefulPVScriptPath :: Text
statefulPVScriptPath = "/usr/local/libexec/jitml-stateful-pv"

statefulPVServiceName :: Text
statefulPVServiceName = "jitml-stateful-pv.service"

statefulPVStartupUnit :: Text
statefulPVStartupUnit =
  Text.unlines
    [ "[Unit]"
    , "Description=jitML node-local persistent volume projection"
    , "After=local-fs.target"
    , "Before=containerd.service kubelet.service"
    , "RequiresMountsFor=/var /jitml/.data"
    , "[Service]"
    , "Type=oneshot"
    , "RemainAfterExit=yes"
    , "TimeoutStartSec=10s"
    , "ExecStart=" <> statefulPVScriptPath <> " project"
    ]

statefulPVDependencyDropIn :: Text
statefulPVDependencyDropIn =
  Text.unlines
    [ "[Unit]"
    , "Requires=" <> statefulPVServiceName
    , "After=" <> statefulPVServiceName
    , "[Service]"
    , "ExecStartPre=" <> statefulPVScriptPath <> " verify"
    ]

statefulPVBundleFiles :: [ManualPV] -> [(FilePath, Text)]
statefulPVBundleFiles roots =
  [ (Text.unpack statefulPVScriptPath, renderStatefulPVProjectionScript roots)
  , ("/etc/systemd/system/jitml-stateful-pv.service", statefulPVStartupUnit)
  , ("/etc/systemd/system/containerd.service.d/20-jitml-stateful-pv.conf", statefulPVDependencyDropIn)
  , ("/etc/systemd/system/kubelet.service.d/20-jitml-stateful-pv.conf", statefulPVDependencyDropIn)
  ]

nodePaths :: [ManualPV] -> [Text]
nodePaths = fmap (Text.dropWhileEnd (== '/') . pvNodeDataPath)

-- No private systemd mount namespace: these mounts belong to the node itself.
-- Startup never creates source leaves. Only the explicit fresh initialization
-- branch may create a genuinely absent leaf; existing/restored metadata stays
-- untouched. No unmount, copying from host .data, or recursive ownership fixup.
renderStatefulPVProjectionScript :: [ManualPV] -> Text
renderStatefulPVProjectionScript roots
  | not (all safePath (nodePaths roots)) = "#!/bin/sh\nexit 1\n"
  | otherwise =
      Text.unlines $
        [ "#!/bin/sh"
        , "set -eu"
        , "export LC_ALL=C"
        , "fail() { echo \"jitML stateful PV: $*\" >&2; exit 1; }"
        , "safe_path() { case \"$1\" in /*) ;; *) fail 'absolute path required';; esac; case \"/$1/\" in */../*|*/./*) fail 'unsafe path';; esac; case \"$1\" in *[!a-zA-Z0-9/._-]*) fail 'unsafe path characters';; esac; case \"$(printf '%s' \"$1\" | tr '[:upper:]' '[:lower:]')/\" in */journal.key/*) fail 'forbidden key coordinate';; esac; }"
        , "safe_relative() { case \"$1\" in ''|/*|*/|*//*) fail 'unsafe relative directory';; esac; safe_path \"/$1\"; }"
        , "physical() {"
        , "  safe_path \"$1\"; p=; oldifs=$IFS; IFS=/; set -- $1; IFS=$oldifs"
        , "  for part do [ -n \"$part\" ] || continue; p=$p/$part; [ ! -L \"$p\" ] && [ -d \"$p\" ] || fail \"nonphysical directory $p\"; done"
        , "}"
        , "make_physical() {"
        , "  safe_path \"$1\"; p=; oldifs=$IFS; IFS=/; set -- $1; IFS=$oldifs"
        , "  for part do [ -n \"$part\" ] || continue; p=$p/$part; [ ! -L \"$p\" ] || fail \"symlink $p\"; if [ -e \"$p\" ]; then [ -d \"$p\" ] || fail \"not a directory $p\"; else mkdir \"$p\"; fi; done"
        , "}"
        , "identity() { stat -Lc '%d:%i' -- \"$1\"; }"
        , "known_root() { case \"$1\" in"
        ]
          <> ["  " <> Text.intercalate "|" (nodePaths roots) <> ") ;;" | not (null roots)]
          <> [ "  *) fail 'unregistered PV root';; esac; }"
             , "one() {"
             , "  root=$1; mode=$2; owner=$3; source=/var/local/jitml-stateful-pv$root"
             , "  if [ \"$mode\" = initialize ]; then"
             , "    [ ! -L \"$source\" ] || fail \"symlink $source\""
             , "    if [ -e \"$source\" ]; then physical \"$source\"; else make_physical \"$(dirname \"$source\")\"; mkdir \"$source\"; if [ \"$owner\" = postgres ]; then chown 26:26 \"$source\"; else chmod 0777 \"$source\"; fi; fi"
             , "  else physical \"$source\"; fi"
             , "  if [ \"$mode\" = verify ]; then physical \"$root\"; else make_physical \"$root\"; fi"
             , "  if ! mountpoint -q -- \"$root\"; then"
             , "    [ \"$mode\" != verify ] || fail \"projection absent at $root; stopped-node repair required\""
             , "    mount --bind \"$source\" \"$root\""
             , "  fi"
             , "  [ \"$(identity \"$source\")\" = \"$(identity \"$root\")\" ] || fail \"wrong projection at $root; stopped-node repair required\""
             , "}"
             , "all_roots() {"
             , "  :"
             ]
          <> [ "  one "
                 <> Text.dropWhileEnd (== '/') (pvNodeDataPath pv)
                 <> " \"$1\" "
                 <> (if pvIsPostgres pv then "postgres" else "shared")
             | pv <- roots
             ]
          <> [ "}"
             , "start_time() { raw=$(cat \"/proc/$1/stat\") || fail 'consumer disappeared'; rest=${raw##*) }; set -- $rest; [ \"$#\" -ge 20 ] || fail 'invalid consumer stat'; shift 19; printf '%s' \"$1\"; }"
             , "mode=${1-}; case \"$mode\" in"
             , "initialize|project|verify) [ \"$#\" = 1 ] || fail 'unexpected arguments'; all_roots \"$mode\";;"
             , "verify-consumer)"
             , "  [ \"$#\" = 4 ] || [ \"$#\" = 5 ] || fail 'consumer arguments required'; consumer_root=$2; consumer_pid=$3; consumer_target=$4; consumer_subpath=${5-}"
             , "  known_root \"$consumer_root\"; safe_path \"$consumer_target\""
             , "  if [ -n \"$consumer_subpath\" ]; then safe_relative \"$consumer_subpath\"; fi"
             , "  case \"$consumer_pid\" in ''|*[!0-9]*|0) fail 'invalid consumer PID';; esac"
             , "  all_roots verify; before=$(start_time \"$consumer_pid\")"
             , "  consumer_source=/var/local/jitml-stateful-pv$consumer_root; if [ -n \"$consumer_subpath\" ]; then consumer_source=$consumer_source/$consumer_subpath; fi; physical \"$consumer_source\""
             , "  [ -d \"/proc/$consumer_pid/root$consumer_target\" ] || fail 'consumer mount absent'"
             , "  [ \"$(identity \"$consumer_source\")\" = \"$(identity \"/proc/$consumer_pid/root$consumer_target\")\" ] || fail \"stale consumer bind for $consumer_root; stopped-node repair required\""
             , "  [ \"$before\" = \"$(start_time \"$consumer_pid\")\" ] || fail 'consumer PID changed';;"
             , "*) fail 'mode must be initialize, project, verify or verify-consumer';; esac"
             ]

statefulPVInitializeSubprocess :: Text -> [ManualPV] -> Subprocess
statefulPVInitializeSubprocess node roots =
  subprocess
    "docker"
    ["exec", node, "sh", "-c", "set -- initialize\n" <> renderStatefulPVProjectionScript roots]

-- Only called for actual fresh creation after restoration and before any
-- registered PV consumer. A retained running cluster is verification-only.
statefulPVFreshInstallSubprocesses :: Substrate -> ClusterResources -> [Subprocess]
statefulPVFreshInstallSubprocesses LinuxCUDA _ = []
statefulPVFreshInstallSubprocesses substrate resources = concatMap install nodes
 where
  roots = manualPVsFor resources
  nodes = substrateKindNodeContainerNames substrate (workerCount resources)
  install node =
    fmap (writeBundleFile node) (statefulPVBundleFiles roots)
      <> [ subprocess "docker" ["exec", node, "sync", "-f", "/etc/systemd/system"]
         , statefulPVInitializeSubprocess node roots
         , subprocess "docker" ["exec", node, "systemctl", "daemon-reload"]
         , subprocess "docker" ["exec", node, "systemctl", "start", statefulPVServiceName]
         ]

writeBundleFile :: Text -> (FilePath, Text) -> Subprocess
writeBundleFile node (path, content) =
  subprocessWithStdin "docker" ["exec", "--interactive", node, "sh", "-c", writer] content
 where
  destination = Text.pack path
  parent = Text.pack (takeDirectory path)
  mode = if destination == statefulPVScriptPath then "0755" else "0644"
  writer =
    Text.unlines
      [ "set -eu; umask 077"
      , "p=; oldifs=$IFS; IFS=/; set -- " <> parent <> "; IFS=$oldifs"
      , "for part do [ -n \"$part\" ] || continue; p=$p/$part; test ! -L \"$p\"; if test -e \"$p\"; then test -d \"$p\"; else mkdir \"$p\"; fi; done"
      , "destination=" <> destination
      , "test ! -L \"$destination\"; if test -e \"$destination\"; then test -f \"$destination\"; test \"$(stat -c %h:%u -- \"$destination\")\" = 1:0; fi"
      , "temporary=$(mktemp \"$destination.jitml-XXXXXXXX\"); trap 'rm -f -- \"$temporary\"' EXIT HUP INT TERM"
      , "dd of=\"$temporary\" oflag=nofollow conv=fsync status=none"
      , "test \"$(sha256sum -- \"$temporary\" | cut -d' ' -f1)\" = " <> sha256 content
      , "chown 0:0 -- \"$temporary\"; chmod "
          <> mode
          <> " -- \"$temporary\"; mv -T -- \"$temporary\" \"$destination\""
      ]

data StatefulPVConsumer = StatefulPVConsumer
  { consumerNode :: Text
  , consumerPodUid :: Text
  , consumerContainerId :: Text
  , consumerNodePath :: Text
  , consumerMountPath :: Text
  , consumerSubPath :: Text
  }
  deriving stock (Eq, Ord, Show)

parseStatefulPVConsumers
  :: Substrate -> ClusterResources -> Text -> Either Text [StatefulPVConsumer]
parseStatefulPVConsumers substrate resources raw = do
  unless (Text.length raw <= 8 * 1024 * 1024) (Left "PV consumer inventory exceeds its bound")
  value <- mapLeft Text.pack (eitherDecodeStrict' (Encoding.encodeUtf8 raw))
  either (Left . Text.pack) (Right . sort . concat) (parseEither parseList value)
 where
  nodes = substrateKindNodeContainerNames substrate (workerCount resources)
  registry =
    Map.fromList
      [ ((pvNamespace pv, claim), Text.dropWhileEnd (== '/') (pvNodeDataPath pv))
      | pv <- manualPVsFor resources
      , Just claim <- [pvClaimRefName pv]
      ]
  parseList :: Value -> Parser [[StatefulPVConsumer]]
  parseList = withObject "PV consumer PodList" (\value -> value .: "items" >>= traverse parsePod)
  parsePod :: Value -> Parser [StatefulPVConsumer]
  parsePod = withObject "PV consumer Pod" $ \value -> do
    metadata <- value .: "metadata"
    uid <- metadata .: "uid"
    namespace <- metadata .: "namespace"
    spec <- value .: "spec"
    node <- spec .:? "nodeName" .!= ""
    volumes <- spec .:? "volumes" .!= []
    registered <- Map.fromList . catMaybes <$> traverse (parseVolume namespace) volumes
    if Map.null registered || Text.null node
      then pure []
      else do
        unless (node `elem` nodes) (fail "registered PVC consumer is on an unexpected node")
        unless (safeIdentifier uid) (fail "invalid PV consumer Pod UID")
        status <- value .: "status"
        regularStatuses <- status .:? "containerStatuses" .!= []
        initStatuses <- status .:? "initContainerStatuses" .!= []
        ephemeralStatuses <- status .:? "ephemeralContainerStatuses" .!= []
        let statuses = regularStatuses <> initStatuses <> ephemeralStatuses
        running <- Map.fromList . catMaybes <$> traverse parseRunning statuses
        regularContainers <- spec .: "containers"
        initContainers <- spec .:? "initContainers" .!= []
        ephemeralContainers <- spec .:? "ephemeralContainers" .!= []
        let containers = regularContainers <> initContainers <> ephemeralContainers
        concat <$> traverse (parseContainer registered running node uid) containers
  parseVolume :: Text -> Value -> Parser (Maybe (Text, Text))
  parseVolume namespace = withObject "Pod volume" $ \value -> do
    name <- value .: "name"
    claim <- value .:? "persistentVolumeClaim"
    case claim of
      Nothing -> pure Nothing
      Just pvc -> do
        claimName <- pvc .: "claimName"
        pure ((name,) <$> Map.lookup (namespace, claimName) registry)
  parseRunning :: Value -> Parser (Maybe (Text, Text))
  parseRunning = withObject "container status" $ \value -> do
    name <- value .: "name"
    state <- value .: "state"
    running <- state .:? "running" :: Parser (Maybe Value)
    case running of
      Nothing -> pure Nothing
      Just _ -> do
        rawId <- value .: "containerID"
        cid <-
          maybe (fail "PV consumer has no containerd identity") pure (Text.stripPrefix "containerd://" rawId)
        unless (Text.length cid == 64 && Text.all hex cid) (fail "invalid PV consumer container ID")
        pure (Just (name, cid))
  parseContainer
    :: Map.Map Text Text -> Map.Map Text Text -> Text -> Text -> Value -> Parser [StatefulPVConsumer]
  parseContainer registered running node uid = withObject "PV consumer container" $ \value -> do
    name <- value .: "name"
    mounts <- value .:? "volumeMounts" .!= []
    case Map.lookup name running of
      Nothing -> pure []
      Just cid -> catMaybes <$> traverse (parseMount registered node uid cid) mounts
  parseMount
    :: Map.Map Text Text -> Text -> Text -> Text -> Value -> Parser (Maybe StatefulPVConsumer)
  parseMount registered node uid cid = withObject "PV consumer mount" $ \value -> do
    name <- value .: "name"
    case Map.lookup name registered of
      Nothing -> pure Nothing
      Just root -> do
        target <- value .: "mountPath"
        subpath <- value .:? "subPath" .!= ""
        expression <- value .:? "subPathExpr" .!= ""
        unless
          (Text.null expression)
          (fail "registered PVC subPathExpr is unsupported by the identity guard")
        unless
          (Text.null subpath || safeRelativeDirectory subpath)
          (fail "unsafe registered PVC directory subPath")
        unless (safePath target) (fail "unsafe PV consumer mount path")
        pure (Just (StatefulPVConsumer node uid cid root target subpath))
  hex character = isDigit character || character `elem` ("abcdef" :: String)

safeIdentifier :: Text -> Bool
safeIdentifier value = not (Text.null value) && Text.length value <= 253 && Text.all identifierChar value
 where
  identifierChar character =
    isAsciiLower character
      || isAsciiUpper character
      || isDigit character
      || character `elem` ("-_." :: String)

safePath :: Text -> Bool
safePath value =
  "/" `Text.isPrefixOf` value
    && Text.length value <= 4096
    && all
      (\part -> part /= ".." && part /= "." && Text.toCaseFold part /= "journal.key")
      (Text.splitOn "/" value)
    && Text.all
      ( \character ->
          isAsciiLower character
            || isAsciiUpper character
            || isDigit character
            || character `elem` ("/._-" :: String)
      )
      value

safeRelativeDirectory :: Text -> Bool
safeRelativeDirectory value =
  not (Text.null value)
    && not ("/" `Text.isPrefixOf` value)
    && not (any Text.null (Text.splitOn "/" value))
    && safePath ("/" <> value)

-- | Validate effective systemd properties, including every pre-start command.
-- systemctl emits a separate ExecStartPre= record for each command; Kind can
-- have a pre-existing modprobe hook before the appended projection verifier.
-- The executable, exact arguments and non-ignored failure must belong to the
-- same record, not to an unrelated command containing the verifier as text.
validateStatefulPVUnitProperties :: Text -> Either Text ()
validateStatefulPVUnitProperties output
  | hasDependency "Requires"
      && hasDependency "After"
      && any verifiesProjection (properties "ExecStartPre") =
      Right ()
  | otherwise = Left "effective fail-closed projection dependencies are absent or malformed"
 where
  properties name = mapMaybe (Text.stripPrefix (name <> "=")) (Text.lines output)
  hasDependency name = any (elem statefulPVServiceName . Text.words) (properties name)
  verifiesProjection value = case Text.stripPrefix "{" (Text.strip value) >>= Text.stripSuffix "}" of
    Nothing -> False
    Just body ->
      field "path" body == Just statefulPVScriptPath
        && fmap Text.words (field "argv[]" body) == Just [statefulPVScriptPath, "verify"]
        && field "ignore_errors" body == Just "no"
  field name body = case [ Text.strip (Text.drop 1 suffix)
                         | part <- Text.splitOn ";" body
                         , let (key, suffix) = Text.breakOn "=" (Text.strip part)
                         , Text.strip key == name
                         , not (Text.null suffix)
                         ] of
    [value] -> Just value
    _ -> Nothing

-- A marker proves restoration into a node volume, not what an existing Pod
-- actually mounted. This verification is read-only and precedes convergence,
-- kubelet calibration and any attempt to establish late projections.
verifyStatefulPVReuseIO :: Substrate -> ClusterResources -> IO (Either Text ())
verifyStatefulPVReuseIO LinuxCUDA _ = pure (Right ())
verifyStatefulPVReuseIO substrate resources = do
  outcome <- timeout 45_000_000 verify
  pure (fromMaybe (Left (coldRepair "projection/consumer verification exceeded45seconds")) outcome)
 where
  roots = manualPVsFor resources
  nodes = substrateKindNodeContainerNames substrate (workerCount resources)
  inventory =
    subprocess
      "kubectl"
      [ "--kubeconfig"
      , "./.build/jitml.kubeconfig"
      , "--context"
      , "kind-" <> substrateClusterName substrate
      , "--request-timeout=5s"
      , "get"
      , "pods"
      , "--all-namespaces"
      , "-o"
      , "json"
      ]
  verify = do
    installed <- traverse verifyNode nodes
    case sequence installed of
      Left reason -> pure (Left (coldRepair reason))
      Right _ -> do
        first <- execute inventory
        case first >>= parseStatefulPVConsumers substrate resources of
          Left reason -> pure (Left (coldRepair reason))
          Right consumers -> do
            observed <- traverse verifyConsumer consumers
            case sequence observed of
              Left reason -> pure (Left (coldRepair reason))
              Right _ -> do
                final <- execute inventory
                pure $ case final >>= parseStatefulPVConsumers substrate resources of
                  Right again | again == consumers -> Right ()
                  _ -> Left (coldRepair "PV consumer identities changed during verification")
  verifyNode node = do
    files <- traverse (verifyFile node) (statefulPVBundleFiles roots)
    case sequence files of
      Left reason -> pure (Left reason)
      Right _ -> do
        dependencies <- traverse (verifyDependency node) ["containerd.service", "kubelet.service"]
        case sequence dependencies of
          Left reason -> pure (Left reason)
          Right _ -> do
            active <- execute (nodeProbe node ["systemctl", "is-active", statefulPVServiceName])
            case active of
              Right value
                | Text.strip value == "active" ->
                    void <$> execute (nodeProbe node [statefulPVScriptPath, "verify"])
              _ -> pure (Left (node <> ": startup projection service is not active"))
  verifyFile node (path, content) = do
    let file = Text.pack path
        metadata = if file == statefulPVScriptPath then "755:0:0:1" else "644:0:0:1"
    actual <-
      execute
        ( nodeProbe
            node
            [ "sh"
            , "-c"
            , "test ! -L "
                <> file
                <> " && test -f "
                <> file
                <> " && test \"$(stat -c %a:%u:%g:%h -- "
                <> file
                <> ")\" = "
                <> metadata
                <> " && sha256sum -- "
                <> file
            ]
        )
    pure $ case actual of
      Right value | take 1 (Text.words value) == [sha256 content] -> Right ()
      _ -> Left (node <> ": startup projection bundle is absent or differs")
  verifyDependency node unit = do
    actual <-
      execute
        ( nodeProbe
            node
            ["systemctl", "show", unit, "--property=Requires", "--property=After", "--property=ExecStartPre"]
        )
    pure $ case actual of
      Right value ->
        mapLeft (\reason -> node <> ": " <> unit <> ": " <> reason) (validateStatefulPVUnitProperties value)
      Left reason -> Left reason
  verifyConsumer consumer = do
    metadata <-
      execute
        ( nodeProbe
            (consumerNode consumer)
            [ "crictl"
            , "--runtime-endpoint"
            , "unix:///run/containerd/containerd.sock"
            , "--timeout"
            , "5s"
            , "inspect"
            , "--output"
            , "go-template"
            , "--template"
            , "{{.info.pid}} {{index .status.labels \"io.kubernetes.pod.uid\"}} {{.status.id}}"
            , consumerContainerId consumer
            ]
        )
    case metadata of
      Right value -> case Text.words value of
        [pid, uid, cid]
          | not (Text.null pid)
              && Text.all isDigit pid
              && Text.any (/= '0') pid
          , uid == consumerPodUid consumer && cid == consumerContainerId consumer ->
              void
                <$> execute
                  ( nodeProbe
                      (consumerNode consumer)
                      [ statefulPVScriptPath
                      , "verify-consumer"
                      , consumerNodePath consumer
                      , pid
                      , consumerMountPath consumer
                      , consumerSubPath consumer
                      ]
                  )
        _ -> pure (Left "CRI container/PID/Pod identity differs")
      Left reason -> pure (Left reason)

-- A local Docker-client timeout alone does not retire its node-side process.
-- Keep TERM+KILL within the ten-second local ceiling even after disconnection.
nodeProbe :: Text -> [Text] -> Subprocess
nodeProbe node arguments =
  subprocess
    "docker"
    (["exec", node, "timeout", "--signal=TERM", "--kill-after=1s", "7s"] <> arguments)

execute :: Subprocess -> IO (Either Text Text)
execute command = do
  outcome <- tryAny (timeout 10_000_000 (runStreaming defaultSubprocessEnv command))
  pure $ case outcome of
    Left failure -> Left ("PV projection command exception: " <> Text.pack (displayException failure))
    Right Nothing -> Left "PV projection command exceeded10seconds"
    Right (Just (ProcessFailed failure)) -> Left (renderProcessFailure failure)
    Right (Just (ProcessSucceeded transcript))
      | Text.length (processTranscriptStdout transcript) <= 8 * 1024 * 1024 ->
          Right (processTranscriptStdout transcript)
      | otherwise -> Left "PV projection metadata output exceeded its bound"

coldRepair :: Text -> Text
coldRepair reason =
  reason
    <> "; refuse late PV overmount/reinitialization: stop the retained Kind nodes, install the source-rendered startup projection bundle, then explicitly restart the same CIDs and verify consumer binds. Preserve Pod NodeName, PV/PVCs, Jobs and original data."

sha256 :: Text -> Text
sha256 = Text.pack . concatMap hex . ByteString.unpack . SHA256.hash . Encoding.encodeUtf8
 where
  hex byte = case showHex byte "" of
    [digit] -> ['0', digit]
    digits -> digits
