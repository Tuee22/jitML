{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- Real Linux bind mounts and the production snapshot/projection programs.
-- Fixture volumes contain ordinary data only; no host, socket or Kind mounts.
module StatefulPvProjection (tests) where

import Control.Concurrent.MVar (newMVar, withMVar)
import Control.Exception (SomeException, displayException, mask, throwIO, try)
import Control.Monad (forM_, void, when)
import Data.Aeson
  ( FromJSON
  , Result (..)
  , ToJSON
  , Value (..)
  , eitherDecode
  , encode
  , fromJSON
  , object
  , (.=)
  )
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import System.Directory
  ( createDirectoryIfMissing
  , emptyPermissions
  , makeAbsolute
  , setOwnerReadable
  , setOwnerWritable
  , setPermissions
  )
import System.Exit (ExitCode (..))
import System.FilePath (makeRelative, takeDirectory, takeFileName, (</>))
import System.IO.Temp (createTempDirectory)
import System.Posix.Files (setFileMode)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.CLI.Output qualified as CLIOutput
import JitML.Cluster.PVSnapshot
  ( NodeIdentity (..)
  , SnapshotRequest (..)
  , decodeTreeManifest
  , sameRestoredTree
  )
import JitML.Cluster.PVSnapshotPrograms (SnapshotPrograms (..), defaultSnapshotPrograms)
import JitML.Cluster.Resources (defaultClusterResources)
import JitML.Cluster.StatefulPV
  ( StatefulPVConsumer (..)
  , parseStatefulPVConsumers
  , renderStatefulPVProjectionScript
  , statefulPVBundleFiles
  , statefulPVDependencyDropIn
  , statefulPVInitializeSubprocess
  , statefulPVScriptPath
  , statefulPVServiceName
  , validateStatefulPVUnitProperties
  )
import JitML.Cluster.Storage (ManualPV (..), manualPVs, pvNodeDataPath)
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Sub.Outcome (ProcessOutcome (..), processFailureExitCode, renderProcessOutcome)
import JitML.Sub.Stream qualified as Stream
import JitML.Sub.Subprocess (Subprocess (..), subprocess, subprocessWithStdin)
import JitML.Substrate (Substrate (LinuxCPU))

tests :: TestTree
tests = withResource (newMVar ()) (const (pure ())) $ \getLock ->
  let serialTest name action = testCase name (getLock >>= \lock -> withMVar lock (const action))
   in testGroup
        "actual Linux stateful PV projection"
        [ serialTest "PV projection preserves restored Linux metadata" restoredMetadata
        , serialTest "PV projection initializes only genuinely new leaves" freshAndExistingEmpty
        , serialTest "PV projection refuses file backing without overwrite" (refusesBacking "file")
        , serialTest "PV projection refuses symlink backing without overwrite" (refusesBacking "symlink")
        , serialTest "PV projection refuses a wrong existing bind without overwrite" wrongBind
        , serialTest "late node projection leaves an existing consumer stale and refuses it" lateConsumerBind
        , serialTest
            "systemd component ordering blocks failed projection and survives a cold restart"
            systemdOrdering
        , serialTest
            "static subPath requires the selected physical child instead of the PV root"
            staticConsumerBind
        , testCase "PV consumer parser binds a running container to the actual registry" consumerParserRunning
        , testCase
            "PV consumer parser accepts safe static subPath and refuses expressions or traversal"
            consumerParserSubPath
        , testCase "PV consumer parser ignores a foreign namespace claim alias" consumerParserNamespace
        , testCase "PV consumer parser refuses malformed active identities" consumerParserIdentity
        , testCase
            "effective unit properties accept the real preceding modprobe record"
            unitPropertiesRepeatedPreStart
        , testCase
            "effective unit properties require both projection dependencies"
            unitPropertiesMissingDependency
        , testCase
            "effective unit properties require exact verifier executable and arguments"
            unitPropertiesWrongCommand
        , testCase "effective unit properties reject an ignored verifier failure" unitPropertiesIgnoredFailure
        ]

data Fixture = Fixture
  { container :: Text
  , image :: Text
  , owner :: Text
  , volumes :: [Text]
  , evidence :: FilePath
  , serial :: IORef Int
  , usesSystemd :: Bool
  }

backing :: Text
backing = "/var/local/jitml-stateful-pv"

pvPaths :: [Text]
pvPaths = fmap (Text.dropWhileEnd (== '/') . pvNodeDataPath) manualPVs

fixtureRoots :: [Text]
fixtureRoots = fmap (Text.dropWhile (== '/')) pvPaths

restoredMetadata :: Assertion
restoredMetadata = withFixture "restored" $ \fixture -> do
  void (python fixture fixtureSetup ["restored", jsonText pvPaths])
  source <- manifest fixture "/fixture/source"
  archived <- archive fixture ["archive", "/fixture/source", "/fixture/generation", "original.pax"]
  digestBytes <- member "digestBytes" archived :: IO Integer
  digestSHA <- member "digestSHA256" archived :: IO Text
  empty <- archive fixture ["empty", "/var/local", "jitml-stateful-pv", "create"]
  identity <- member "identity" empty :: IO Value
  void $
    archive
      fixture
      [ "extract"
      , "/fixture/generation/original.pax"
      , backing
      , Text.pack (show digestBytes)
      , digestSHA
      , jsonText identity
      ]
  restored <- manifest fixture backing
  let request =
        SnapshotRequest
          "linux-cpu"
          "jitml-linux-cpu"
          [NodeIdentity "worker" (Text.replicate 64 "a")]
          fixtureRoots
  left <- expect (decodeTreeManifest request (LBS.toStrict (encode source)))
  right <- expect (decodeTreeManifest request (LBS.toStrict (encode restored)))
  assertBool
    "literal production extract did not preserve portable metadata"
    (sameRestoredTree left right)
  void (python fixture fixtureChecks ["restored", jsonText pvPaths])
  project fixture
  projected <- manifest fixture backing
  -- This is the old-producer counterexample: 02751 and its access ACL must not
  -- be broadened after the strict production restore comparison has passed.
  assertBool
    "production projection changed restored Linux root metadata/payload"
    (projected == restored)
  assertProjected fixture
  project fixture
  manifest fixture backing >>= (@?= restored)
  assertProjected fixture

freshAndExistingEmpty :: Assertion
freshAndExistingEmpty = withFixture "fresh" $ \fixture -> do
  void (python fixture fixtureSetup ["fresh", jsonText pvPaths])
  original <- manifest fixture (backing <> headPath)
  project fixture
  manifest fixture (backing <> headPath) >>= (@?= original)
  void (python fixture fixtureChecks ["fresh", jsonText pvPaths])
  initialized <- manifest fixture backing
  assertProjected fixture
  project fixture
  manifest fixture backing >>= (@?= initialized)
  assertProjected fixture

refusesBacking :: Text -> Assertion
refusesBacking kind = withFixture kind $ \fixture -> do
  void (python fixture fixtureSetup [kind, jsonText pvPaths])
  original <- manifest fixture backing
  external <- manifest fixture "/fixture/external"
  target <- manifest fixture "/jitml/.data"
  rejectProjection fixture
  manifest fixture backing >>= (@?= original)
  manifest fixture "/fixture/external" >>= (@?= external)
  manifest fixture "/jitml/.data" >>= (@?= target)

wrongBind :: Assertion
wrongBind = withFixture "wrong-bind" $ \fixture -> do
  void (python fixture fixtureSetup ["wrong-bind", jsonText pvPaths])
  original <- manifest fixture backing
  external <- manifest fixture "/fixture/external"
  target <- manifest fixture "/jitml/.data"
  rejectProjection fixture
  manifest fixture backing >>= (@?= original)
  manifest fixture "/fixture/external" >>= (@?= external)
  manifest fixture "/jitml/.data" >>= (@?= target)

-- A bind made by a container runtime pins its source inode. A later mount at
-- the node path changes the node's view, but cannot repair that existing bind.
-- This reproduces the kernel failure with ordinary fixture data and then
-- exercises the actual consumer guard, rather than checking generated text.
lateConsumerBind :: Assertion
lateConsumerBind = withFixture "late-consumer" $ \fixture -> do
  before <- python fixture consumerSetup [headPath]
  oldIdentity <- member "old_identity" before :: IO [Integer]
  restoredIdentity <- member "restored_identity" before :: IO [Integer]
  assertBool "fixture source identities unexpectedly coincide" (oldIdentity /= restoredIdentity)
  project fixture
  observed <- python fixture consumerChecks ["stale", headPath]
  member "node_identity" observed >>= (@?= restoredIdentity)
  member "consumer_identity" observed >>= (@?= oldIdentity)
  rejectCommand
    fixture
    (projectionMode fixture ["verify-consumer", headPath, "1", "/fixture/consumer"])
  void (python fixture consumerChecks ["stale", headPath])
  -- Only a new consumer bind made after the projection sees the restored tree.
  void (python fixture consumerChecks ["rebind", headPath])
  void
    (succeeded fixture (projectionMode fixture ["verify-consumer", headPath, "1", "/fixture/consumer"]))
  repaired <- python fixture consumerChecks ["current", headPath]
  member "node_identity" repaired >>= (@?= restoredIdentity)
  member "consumer_identity" repaired >>= (@?= restoredIdentity)

staticConsumerBind :: Assertion
staticConsumerBind = withFixture "static-consumer" $ \fixture -> do
  project fixture
  void (python fixture staticConsumerSetup [headPath])
  -- The whole root is a valid bind, but not the requested child directory.
  void
    (succeeded fixture (projectionMode fixture ["verify-consumer", headPath, "1", "/fixture/consumer"]))
  rejectCommand
    fixture
    ( projectionMode
        fixture
        ["verify-consumer", headPath, "1", "/fixture/consumer", "nested/prometheus-db"]
    )
  void (python fixture staticConsumerChecks [headPath])
  void
    ( succeeded
        fixture
        ( projectionMode
            fixture
            ["verify-consumer", headPath, "1", "/fixture/consumer", "nested/prometheus-db"]
        )
    )
  rejectCommand
    fixture
    ( projectionMode
        fixture
        ["verify-consumer", headPath, "1", "/fixture/consumer", "nested/../prometheus-db"]
    )
  rejectCommand
    fixture
    (projectionMode fixture ["verify-consumer", headPath, "1", "/fixture/consumer", "link-to-child"])

consumerParserRunning :: Assertion
consumerParserRunning =
  parseConsumers (consumerPod registryNamespace fixtureNode fixturePodUid fixtureContainerId [])
    @?= Right [expectedConsumer ""]

consumerParserSubPath :: Assertion
consumerParserSubPath = do
  forM_ ["prometheus-db", "nested/prometheus-db"] $ \path ->
    parseConsumers
      (consumerPod registryNamespace fixtureNode fixturePodUid fixtureContainerId ["subPath" .= path])
      @?= Right [expectedConsumer path]
  let invalidSubpaths =
        [ "/absolute"
        , "../escape"
        , "safe/../escape"
        , "safe//child"
        , "safe/./child"
        , "journal.key"
        , "safe/journal.key"
        ]
  forM_ invalidSubpaths $ \path ->
    refusesConsumer
      ( consumerPod
          registryNamespace
          fixtureNode
          fixturePodUid
          fixtureContainerId
          ["subPath" .= (path :: Text)]
      )
  refusesConsumer
    ( consumerPod
        registryNamespace
        fixtureNode
        fixturePodUid
        fixtureContainerId
        ["subPathExpr" .= ("$(POD_NAME)" :: Text)]
    )

consumerParserNamespace :: Assertion
consumerParserNamespace =
  -- A same-named foreign PVC is not our registered storage. Its foreign node
  -- must not turn it into a retained-node consumer or trigger our node guard.
  parseConsumers
    (consumerPod "foreign-fixture-namespace" "foreign-node" fixturePodUid fixtureContainerId [])
    @?= Right []

consumerParserIdentity :: Assertion
consumerParserIdentity = do
  forM_
    [ "docker://" <> fixtureContainerId
    , "containerd://short"
    , "containerd://" <> Text.replicate 64 "g"
    , "containerd://" <> Text.replicate 64 "١"
    ]
    $ \cid ->
      refusesConsumer (consumerPod registryNamespace fixtureNode fixturePodUid cid [])
  refusesConsumer
    (consumerPod registryNamespace "unexpected-node" fixturePodUid fixtureContainerId [])
  refusesConsumer (consumerPod registryNamespace fixtureNode "invalid pod uid" fixtureContainerId [])

-- Curated actual systemctl serialization from the retained control-plane
-- unit: each pre-start command has its own repeated property name.
unitPropertiesSample :: Text
unitPropertiesSample =
  Text.unlines
    [ "ExecStartPre={ path=/sbin/modprobe ; argv[]=/sbin/modprobe overlay ; ignore_errors=yes ; start_time=[Sun 2026-11-01 09:04:26 UTC] ; stop_time=[Sun 2026-11-01 09:04:26 UTC] ; pid=158 ; code=exited ; status=0 }"
    , "ExecStartPre={ path=/usr/local/libexec/jitml-stateful-pv ; argv[]=/usr/local/libexec/jitml-stateful-pv verify ; ignore_errors=no ; start_time=[Sun 2026-11-01 09:04:26 UTC] ; stop_time=[Sun 2026-11-01 09:04:26 UTC] ; pid=160 ; code=exited ; status=0 }"
    , "Requires=sysinit.target system.slice jitml-stateful-pv.service"
    , "After=system.slice sysinit.target jitml-stateful-pv.service undo-mount-hacks.service basic.target systemd-journald.socket network.target local-fs.target"
    ]

unitPropertiesRepeatedPreStart :: Assertion
unitPropertiesRepeatedPreStart = validateStatefulPVUnitProperties unitPropertiesSample @?= Right ()

unitPropertiesMissingDependency :: Assertion
unitPropertiesMissingDependency =
  forM_ ["Requires=", "After="] $ \property ->
    refusesUnitProperties
      (Text.unlines (filter (not . Text.isPrefixOf property) (Text.lines unitPropertiesSample)))

unitPropertiesWrongCommand :: Assertion
unitPropertiesWrongCommand = do
  forM_
    [ ("path=/usr/local/libexec/jitml-stateful-pv ;", "path=/bin/echo ;")
    ,
      ( "argv[]=/usr/local/libexec/jitml-stateful-pv verify ;"
      , "argv[]=/usr/local/libexec/jitml-stateful-pv verify --extra ;"
      )
    ,
      ( "argv[]=/usr/local/libexec/jitml-stateful-pv verify ;"
      , "argv[]=/bin/echo /usr/local/libexec/jitml-stateful-pv verify ;"
      )
    ]
    $ \(original, changed) -> refusesUnitProperties (Text.replace original changed unitPropertiesSample)
  -- Matching fields spread across two commands must not combine into proof.
  refusesUnitProperties $
    Text.unlines
      [ "Requires=jitml-stateful-pv.service"
      , "After=jitml-stateful-pv.service"
      , "ExecStartPre={ path=/usr/local/libexec/jitml-stateful-pv ; argv[]=/bin/true ; ignore_errors=no }"
      , "ExecStartPre={ path=/bin/true ; argv[]=/usr/local/libexec/jitml-stateful-pv verify ; ignore_errors=no }"
      ]

unitPropertiesIgnoredFailure :: Assertion
unitPropertiesIgnoredFailure =
  refusesUnitProperties (Text.replace "ignore_errors=no" "ignore_errors=yes" unitPropertiesSample)

refusesUnitProperties :: Text -> Assertion
refusesUnitProperties value = case validateStatefulPVUnitProperties value of
  Left _ -> pure ()
  Right () ->
    assertFailure "effective unit parser accepted missing dependencies or an invalid verifier command"

refusesConsumer :: Value -> Assertion
refusesConsumer value = case parseConsumers value of
  Left _ -> pure ()
  Right accepted -> assertFailure ("PV consumer parser accepted malformed metadata: " <> show accepted)

parseConsumers :: Value -> Either Text [StatefulPVConsumer]
parseConsumers pod =
  parseStatefulPVConsumers LinuxCPU defaultClusterResources $
    jsonText (object ["apiVersion" .= ("v1" :: Text), "kind" .= ("PodList" :: Text), "items" .= [pod]])

registryPV :: ManualPV
registryPV = case [pv | pv <- manualPVs, Just _ <- [pvClaimRefName pv]] of
  first : _ -> first
  [] -> error "the production manual PV registry has no bound claims"

registryNamespace :: Text
registryNamespace = pvNamespace registryPV

fixtureNode, fixturePodUid, fixtureContainerId :: Text
fixtureNode = "jitml-linux-cpu-worker"
fixturePodUid = "fixture-pod-1234"
fixtureContainerId = Text.replicate 64 "a"

expectedConsumer :: Text -> StatefulPVConsumer
expectedConsumer path =
  StatefulPVConsumer
    { consumerNode = fixtureNode
    , consumerPodUid = fixturePodUid
    , consumerContainerId = fixtureContainerId
    , consumerNodePath = Text.dropWhileEnd (== '/') (pvNodeDataPath registryPV)
    , consumerMountPath = "/ordinary/data"
    , consumerSubPath = path
    }

consumerPod :: Text -> Text -> Text -> Text -> [(Key.Key, Value)] -> Value
consumerPod namespace node uid cid mountFields =
  object
    [ "apiVersion" .= ("v1" :: Text)
    , "kind" .= ("Pod" :: Text)
    , "metadata"
        .= object ["namespace" .= namespace, "uid" .= uid, "name" .= ("ordinary-consumer" :: Text)]
    , "spec"
        .= object
          [ "nodeName" .= node
          , "volumes"
              .= [ object
                     [ "name" .= ("data" :: Text)
                     , "persistentVolumeClaim" .= object ["claimName" .= pvClaimRefName registryPV]
                     ]
                 ]
          , "containers"
              .= [ object
                     [ "name" .= ("consumer" :: Text)
                     , "volumeMounts"
                         .= [object (["name" .= ("data" :: Text), "mountPath" .= ("/ordinary/data" :: Text)] <> mountFields)]
                     ]
                 ]
          ]
    , "status"
        .= object
          [ "containerStatuses"
              .= [ object
                     [ "name" .= ("consumer" :: Text)
                     , "containerID" .= (if "://" `Text.isInfixOf` cid then cid else "containerd://" <> cid)
                     , "state" .= object ["running" .= object ["startedAt" .= ("2026-11-01T00:00:00Z" :: Text)]]
                     ]
                 ]
          ]
    ]

-- This is a real systemd dependency/component test. Its two daemon names are
-- inert oneshot marker services, not containerd, kubelet or Kubernetes. The
-- production service/drop-ins run against isolated ordinary named volumes.
-- Actual restored Kind/Pod identities still need their separate live proof.
systemdOrdering :: Assertion
systemdOrdering = withFixtureMode True "systemd-ordering" $ \fixture -> do
  void (shell fixture systemdFailureChecks)
  -- Startup must fail closed for missing backing; only controlled explicit
  -- initialization may create it. The same real production command is used.
  project fixture
  void (shell fixture systemdStartChecks)
  assertEffectiveDependencies fixture
  expected <-
    Text.strip . Encoding.decodeUtf8 . LBS.toStrict
      <$> shell fixture ("stat -Lc '%d:%i' -- " <> backing <> headPath)
  assertDaemonIdentities fixture expected
  void (shell fixture "rm -- /fixture/containerd.identity /fixture/kubelet.identity")
  stopOwned fixture
  assertStopped fixture
  void (succeeded fixture (subprocess "docker" ["start", container fixture]))
  verifyContainer fixture
  verifySystemdBundleFiles fixture
  void (shell fixture systemdReadyChecks)
  assertEffectiveDependencies fixture
  assertDaemonIdentities fixture expected

assertEffectiveDependencies :: Fixture -> Assertion
assertEffectiveDependencies fixture = forM_ ["containerd.service", "kubelet.service"] $ \unit -> do
  actual <-
    Encoding.decodeUtf8 . LBS.toStrict
      <$> shell
        fixture
        ("systemctl show " <> unit <> " --property=Requires --property=After --property=ExecStartPre")
  case filter (Text.isPrefixOf "ExecStartPre=") (Text.lines actual) of
    first : _ : _ ->
      assertBool "fixture preceding pre-start hook differs" ("path=/bin/true ;" `Text.isInfixOf` first)
    _ ->
      assertFailure
        "real systemd fixture did not emit the preceding hook and verifier as separate records"
  validateStatefulPVUnitProperties actual @?= Right ()

assertDaemonIdentities :: Fixture -> Text -> Assertion
assertDaemonIdentities fixture expected = forM_ ["containerd", "kubelet"] $ \daemon -> do
  actual <- shell fixture ("cat -- /fixture/" <> daemon <> ".identity")
  Text.strip (Encoding.decodeUtf8 (LBS.toStrict actual)) @?= expected

shell :: Fixture -> Text -> IO LBS.ByteString
shell fixture body =
  succeeded fixture (subprocess "docker" ["exec", container fixture, "sh", "-c", "set -eu\n" <> body])

installSystemdFixture :: Fixture -> IO ()
installSystemdFixture fixture = do
  let bundle = evidence fixture </> "systemd-bundle"
      dummy daemon =
        Text.unlines
          [ "[Unit]"
          , "Description=isolated jitML projection dependency component fixture"
          , "DefaultDependencies=no"
          , "[Service]"
          , "Type=oneshot"
          , "RemainAfterExit=yes"
          , "TimeoutStartSec=5s"
          , "ExecStart=/bin/sh -c 'stat -Lc \"%%d:%%i\" -- "
              <> headPath
              <> " > /fixture/"
              <> daemon
              <> ".identity'"
          ]
      -- A cached Kind image can have kubeadm/containerd drop-ins. Reset their
      -- command hooks, retain one benign preceding pre-start command, then
      -- append the exact production dependency/verify drop-in last. The real
      -- serialization must reach the production effective-property validator.
      -- No real runtime daemon may execute in this fixture.
      inertOverride daemon =
        Text.unlines
          [ "[Service]"
          , "ExecCondition="
          , "ExecStartPre="
          , "ExecStartPre=/bin/true"
          , "ExecStart="
          , "ExecStartPost="
          , "ExecReload="
          , "ExecStop="
          , "ExecStopPost="
          , "EnvironmentFile="
          , "Restart=no"
          , "Type=oneshot"
          , "RemainAfterExit=yes"
          , "ExecStart=/bin/sh -c 'stat -Lc \"%%d:%%i\" -- "
              <> headPath
              <> " > /fixture/"
              <> daemon
              <> ".identity'"
          ]
          <> statefulPVDependencyDropIn
      files =
        statefulPVBundleFiles manualPVs
          <> [
               ( "/etc/systemd/system/jitml-pv-fixture.target"
               , "[Unit]\nDescription=isolated PV ordering component fixture\nDefaultDependencies=no\nWants=containerd.service kubelet.service\nAfter=containerd.service kubelet.service\n"
               )
             ]
          <> concatMap
            ( \daemon ->
                [ ("/etc/systemd/system/" <> Text.unpack daemon <> ".service", dummy daemon)
                ,
                  ( "/etc/systemd/system/" <> Text.unpack daemon <> ".service.d/99-jitml-fixture.conf"
                  , inertOverride daemon
                  )
                ]
            )
            ["containerd", "kubelet"]
  forM_ files $ \(absolute, content) -> do
    assertBool "fixture bundle destination must be absolute" (take 1 absolute == "/")
    let destination = bundle </> makeRelative "/" absolute
    createDirectoryIfMissing True (takeDirectory destination)
    privateWrite destination (LBS.fromStrict (Encoding.encodeUtf8 content))
    setFileMode destination (if Text.pack absolute == statefulPVScriptPath then 0o755 else 0o644)
  void
    (succeeded fixture (subprocess "docker" ["cp", Text.pack bundle <> "/.", container fixture <> ":/"]))

verifySystemdBundleFiles :: Fixture -> Assertion
verifySystemdBundleFiles fixture = forM_ (statefulPVBundleFiles manualPVs) $ \(path, _) -> do
  let destination = Text.pack path
      mode = if destination == statefulPVScriptPath then "755" else "644"
  actual <-
    shell fixture ("test ! -L " <> destination <> "\nstat -Lc '%a:%u:%g:%h' -- " <> destination)
  Text.strip (Encoding.decodeUtf8 (LBS.toStrict actual)) @?= mode <> ":0:0:1"

systemdFailureChecks :: Text
systemdFailureChecks =
  Text.unlines $
    [ "timeout 20s sh -c 'until systemctl is-failed --quiet "
        <> statefulPVServiceName
        <> "; do sleep 0.1; done'"
    , "timeout 20s sh -c 'while test -n \"$(systemctl list-jobs --no-legend --no-pager)\"; do sleep 0.1; done'"
    , "test \"$(systemctl show --property=Result --value " <> statefulPVServiceName <> ")\" = exit-code"
    ]
      <> concatMap
        ( \daemon ->
            [ "test ! -e /fixture/" <> daemon <> ".identity"
            , "test \"$(systemctl show --property=ExecMainStartTimestampMonotonic --value "
                <> daemon
                <> ".service)\" = 0"
            , "test \"$(systemctl show --property=MainPID --value " <> daemon <> ".service)\" = 0"
            , "test \"$(systemctl show --property=ActiveState --value " <> daemon <> ".service)\" = inactive"
            ]
        )
        ["containerd", "kubelet"]
      <> [ "systemctl show --property=ActiveState,SubState,Result,ExecMainStartTimestampMonotonic,MainPID "
             <> statefulPVServiceName
             <> " containerd.service kubelet.service"
         ]

systemdStartChecks :: Text
systemdStartChecks =
  "systemctl reset-failed "
    <> statefulPVServiceName
    <> " containerd.service kubelet.service\n"
    <> "timeout 20s systemctl start containerd.service kubelet.service\n"
    <> systemdReadyChecks

systemdReadyChecks :: Text
systemdReadyChecks =
  Text.unlines
    [ "timeout 20s sh -c 'until systemctl is-active --quiet "
        <> statefulPVServiceName
        <> " && systemctl is-active --quiet containerd.service && systemctl is-active --quiet kubelet.service; do sleep 0.1; done'"
    , "test \"$(systemctl show --property=SubState --value " <> statefulPVServiceName <> ")\" = exited"
    , "test \"$(systemctl show --property=Result --value " <> statefulPVServiceName <> ")\" = success"
    , Text.unlines
        [ "test \"$(systemctl show --property=Result --value "
            <> daemon
            <> ".service)\" = success\ntest -s /fixture/"
            <> daemon
            <> ".identity"
        | daemon <- ["containerd", "kubelet"]
        ]
    , "systemctl show --property=ActiveState,SubState,Result,ExecMainStartTimestampMonotonic,MainPID "
        <> statefulPVServiceName
        <> " containerd.service kubelet.service"
    ]

headPath :: Text
headPath = case pvPaths of
  first : _ -> first
  [] -> error "the production manual PV registry is empty"

-- The node operand is fixture-owned; the command body is the production API.
projection :: Fixture -> IO Subprocess
projection fixture = pure (statefulPVInitializeSubprocess (container fixture) manualPVs)

projectionMode :: Fixture -> [Text] -> Subprocess
projectionMode fixture args =
  subprocessWithStdin
    "docker"
    (["exec", "--interactive", container fixture, "sh", "-s", "--"] <> args)
    (renderStatefulPVProjectionScript manualPVs)

project :: Fixture -> IO ()
project fixture = projection fixture >>= succeeded fixture >> pure ()

rejectProjection :: Fixture -> IO ()
rejectProjection fixture = do
  command <- projection fixture
  rejectCommand fixture command

rejectCommand :: Fixture -> Subprocess -> IO ()
rejectCommand fixture command = do
  (outcome, _) <- recorded fixture command
  case outcome of
    ProcessFailed _ -> pure ()
    ProcessSucceeded _ -> assertFailure "production projection accepted an invalid backing/bind/consumer"

assertProjected :: Fixture -> IO ()
assertProjected fixture = forM_ pvPaths $ \path -> do
  source <- manifest fixture (backing <> path)
  target <- manifest fixture path
  -- The two path coordinates name the same real bind-mounted tree. Everything
  -- else, including physical identity, complete payload and hardlinks, is exact.
  withoutRoot source @?= withoutRoot target
 where
  withoutRoot (Object value) = Object (KM.delete "root" value)
  withoutRoot value = value

manifest :: Fixture -> Text -> IO Value
manifest fixture path = python fixture (manifestProgram defaultSnapshotPrograms) [path]

archive :: Fixture -> [Text] -> IO Value
archive fixture = python fixture (archiveIOProgram defaultSnapshotPrograms)

python :: Fixture -> Text -> [Text] -> IO Value
python fixture program args =
  succeeded
    fixture
    ( subprocessWithStdin
        "docker"
        (["exec", "--interactive", container fixture, "python3", "-"] <> args)
        program
    )
    >>= decodeJSON

withFixture :: Text -> (Fixture -> IO ()) -> IO ()
withFixture = withFixtureMode False

withFixtureMode :: Bool -> Text -> (Fixture -> IO ()) -> IO ()
withFixtureMode systemd kind action = mask $ \restore -> do
  parent <- makeAbsolute ".build/runtime/pv-projection-fixtures"
  createDirectoryIfMissing True parent
  directory <- createTempDirectory parent (Text.unpack kind <> "-")
  counter <- newIORef 0
  let token = Text.pack (takeFileName directory)
      ownedVolumes =
        fmap (\suffix -> "jitml-pv-projection-" <> token <> "-" <> suffix) ["fixture", "backend", "targets"]
      initial = Fixture "" "" token ownedVolumes directory counter systemd
      cachedImage = if systemd then "kindest/node:v1.34.0" else "jitml:local"
  pinned <-
    Text.strip . Encoding.decodeUtf8 . LBS.toStrict
      <$> succeeded initial (subprocess "docker" ["image", "inspect", "--format", "{{.Id}}", cachedImage])
  assertBool
    "fixture image is not an immutable SHA256 ID"
    (Text.length pinned == 71 && "sha256:" `Text.isPrefixOf` pinned && Text.all hex (Text.drop 7 pinned))
  forM_ ownedVolumes $ \name -> do
    existing <- succeeded initial (subprocess "docker" ["volume", "ls", "--format", "{{.Name}}"])
    assertBool
      "fixture volume name already exists; refusing reuse"
      (name `notElem` Text.lines (Encoding.decodeUtf8 (LBS.toStrict existing)))
    actual <- succeeded initial (subprocess "docker" ["volume", "create", "--label", label token, name])
    Text.strip (Encoding.decodeUtf8 (LBS.toStrict actual)) @?= name
    verifyVolume initial name
  let mounts =
        concatMap
          ( \(name, target) -> ["--mount", "type=volume,source=" <> name <> ",target=" <> target <> ",volume-nocopy"]
          )
          (zip ownedVolumes (fixtureVolumeTargets systemd))
  created <-
    succeeded initial $
      subprocess "docker" $
        [ "create"
        , "--pull"
        , "never"
        , "--name"
        , "jitml-pv-projection-" <> token
        , "--network"
        , "none"
        , "--cpus"
        , "0.5"
        , "--memory"
        , "1g"
        , "--memory-swap"
        , "1g"
        , "--pids-limit"
        , "128"
        , "--cgroupns"
        , "private"
        , "--security-opt"
        , "no-new-privileges"
        , "--label"
        , label token
        ]
          <> ( if systemd
                 then
                   [ "--privileged"
                   , "--security-opt"
                   , "seccomp=unconfined"
                   , "--security-opt"
                   , "apparmor=unconfined"
                   , "--security-opt"
                   , "label=disable"
                   , "--tmpfs"
                   , "/run:rw,nosuid,nodev,size=64m,mode=0755"
                   , "--tmpfs"
                   , "/tmp:rw,nosuid,nodev,size=64m,mode=1777"
                   , "--env"
                   , "container=docker"
                   ]
                 else ["--read-only", "--cap-add", "SYS_ADMIN", "--security-opt", "apparmor=unconfined"]
             )
          <> mounts
          <> ["--entrypoint", fixtureEntrypoint systemd, pinned]
          <> fixtureArguments systemd
  let cid = Text.strip (Encoding.decodeUtf8 (LBS.toStrict created))
      fixture = initial {container = cid, image = pinned}
  assertBool "fixture create returned an invalid CID" (Text.length cid == 64 && Text.all hex cid)
  attempted <- try $ restore $ do
    verifyContainer fixture
    when systemd (installSystemdFixture fixture)
    void (succeeded fixture (subprocess "docker" ["start", cid]))
    verifyContainer fixture
    forM_ ownedVolumes (verifyVolume fixture)
    if systemd
      then do
        void
          ( shell
              fixture
              "test \"$(id -u)\" = 0\ncase \"$(readlink /proc/1/exe)\" in */systemd) ;; *) exit 1;; esac"
          )
        verifySystemdBundleFiles fixture
      else
        void
          (python fixture "import json,os; assert os.geteuid()==0; print(json.dumps({'euid':os.geteuid()}))" [])
    within "complete PV fixture" 240 (action fixture)
  stopped <- try (stopOwned fixture) :: IO (Either SomeException ())
  case attempted of
    Left (failure :: SomeException) -> do
      privateWrite (directory </> "failure.json") $
        encode $
          object
            [ "exception" .= displayException failure
            , "retained_container" .= cid
            , "retained_volumes" .= ownedVolumes
            , "stop_result" .= either displayException (const "stopped") stopped
            ]
      -- Keep the archive, fixture payload, raw receipts and stopped context.
      CLIOutput.writeLineIO ("PV projection fixture retained: " <> Text.pack directory)
      throwIO failure
    Right () -> do
      either throwIO pure stopped
      verifyContainer fixture
      void (succeeded fixture (subprocess "docker" ["rm", cid]))
      forM_ ownedVolumes $ \name -> do
        verifyVolume fixture name
        void (succeeded fixture (subprocess "docker" ["volume", "rm", name]))
      remaining <-
        succeeded
          fixture
          ( subprocess
              "docker"
              ["ps", "--all", "--no-trunc", "--filter", "label=" <> label token, "--format", "{{.ID}}"]
          )
      Text.strip (Encoding.decodeUtf8 (LBS.toStrict remaining)) @?= ""
      remainingVolumes <-
        succeeded
          fixture
          (subprocess "docker" ["volume", "ls", "--filter", "label=" <> label token, "--format", "{{.Name}}"])
      Text.strip (Encoding.decodeUtf8 (LBS.toStrict remainingVolumes)) @?= ""
 where
  hex c = c `elem` ("0123456789abcdef" :: String)

label :: Text -> Text
label token = "jitml.test.pv-projection=" <> token

parkProgram :: Text
parkProgram = "import time; time.sleep(600)"

fixtureEntrypoint :: Bool -> Text
fixtureEntrypoint systemd = if systemd then "/sbin/init" else "python3"

fixtureArguments :: Bool -> [Text]
fixtureArguments systemd =
  if systemd
    then ["--unit=jitml-pv-fixture.target", "--log-target=console", "--log-level=notice"]
    else ["-c", parkProgram]

fixtureVolumeTargets :: Bool -> [Text]
fixtureVolumeTargets systemd =
  -- The Kind image declares VOLUME /var. Override it with an owned volume,
  -- rather than silently creating an untracked anonymous volume at startup.
  ["/fixture", if systemd then "/var" else "/var/local", "/jitml/.data"]

verifyLabel :: Fixture -> Value -> IO ()
verifyLabel fixture value = do
  actual <- member "jitml.test.pv-projection" value
  (actual :: Text) @?= owner fixture

verifyVolume :: Fixture -> Text -> IO ()
verifyVolume fixture name = do
  value <-
    succeeded fixture (subprocess "docker" ["volume", "inspect", "--format", "{{json .}}", name])
      >>= decodeJSON
  actualName <- member "Name" value
  driver <- member "Driver" value
  (actualName :: Text) @?= name
  (driver :: Text) @?= "local"
  member "Labels" value >>= verifyLabel fixture

verifyContainer :: Fixture -> IO ()
verifyContainer fixture = do
  let format =
        "{\"id\":{{json .Id}},\"name\":{{json .Name}},\"image\":{{json .Image}},\"labels\":{{json .Config.Labels}},\"mounts\":{{json .Mounts}},\"network\":{{json .HostConfig.NetworkMode}},\"readonly\":{{json .HostConfig.ReadonlyRootfs}},\"privileged\":{{json .HostConfig.Privileged}},\"pid\":{{json .HostConfig.PidMode}},\"ipc\":{{json .HostConfig.IpcMode}},\"cgroupns\":{{json .HostConfig.CgroupnsMode}},\"memory\":{{json .HostConfig.Memory}},\"memory_swap\":{{json .HostConfig.MemorySwap}},\"nano_cpus\":{{json .HostConfig.NanoCpus}},\"pids\":{{json .HostConfig.PidsLimit}},\"tmpfs\":{{json (index .HostConfig \"Tmpfs\")}},\"devices\":{{json .HostConfig.Devices}},\"device_requests\":{{json (index .HostConfig \"DeviceRequests\")}},\"device_rules\":{{json (index .HostConfig \"DeviceCgroupRules\")}},\"caps\":{{json .HostConfig.CapAdd}},\"cap_drop\":{{json .HostConfig.CapDrop}},\"security\":{{json .HostConfig.SecurityOpt}},\"entrypoint\":{{json .Config.Entrypoint}},\"cmd\":{{json .Config.Cmd}},\"user\":{{json .Config.User}}}"
  value <-
    succeeded
      fixture
      (subprocess "docker" ["inspect", "--type", "container", "--format", format, container fixture])
      >>= decodeJSON
  actualCID <- member "id" value
  actualImage <- member "image" value
  actualName <- member "name" value
  (actualCID :: Text) @?= container fixture
  (actualImage :: Text) @?= image fixture
  (actualName :: Text) @?= "/jitml-pv-projection-" <> owner fixture
  member "labels" value >>= verifyLabel fixture
  network <- member "network" value
  readOnly <- member "readonly" value
  privileged <- member "privileged" value
  pidMode <- member "pid" value
  ipcMode <- member "ipc" value
  (network :: Text) @?= "none"
  (readOnly :: Bool) @?= not (usesSystemd fixture)
  (privileged :: Bool) @?= usesSystemd fixture
  (pidMode :: Text) @?= ""
  (ipcMode :: Text) @?= "private"
  member "cgroupns" value >>= (@?= ("private" :: Text))
  member "memory" value >>= (@?= (1073741824 :: Integer))
  member "memory_swap" value >>= (@?= (1073741824 :: Integer))
  member "nano_cpus" value >>= (@?= (500000000 :: Integer))
  member "pids" value >>= (@?= (128 :: Integer))
  let expectedTmpfs =
        object
          [ "/run" .= ("rw,nosuid,nodev,size=64m,mode=0755" :: Text)
          , "/tmp" .= ("rw,nosuid,nodev,size=64m,mode=1777" :: Text)
          ]
  tmpfs <- member "tmpfs" value :: IO Value
  assertBool "unexpected fixture tmpfs mounts" $
    if usesSystemd fixture
      then tmpfs == expectedTmpfs
      else tmpfs == Null || tmpfs == Object mempty
  forM_ ["devices", "device_requests", "device_rules", "cap_drop"] $ \key -> do
    actual <- member key value :: IO Value
    assertBool ("unexpected fixture " <> Text.unpack key) (actual == Null || actual == Array mempty)
  capabilities <- member "caps" value :: IO Value
  if usesSystemd fixture
    then
      assertBool
        "unexpected explicit systemd fixture capabilities"
        (capabilities == Null || capabilities == Array mempty)
    else do
      decoded <-
        expect (case fromJSON capabilities of Success actual -> Right actual; Error reason -> Left reason)
      fmap (Text.replace "CAP_" "") decoded @?= ["SYS_ADMIN"]
  security <- member "security" value :: IO [Text]
  let normalize option = case Text.replace ":" "=" option of
        "no-new-privileges=true" -> "no-new-privileges"
        other -> other
  sort (fmap normalize security)
    @?= sort
      ( if usesSystemd fixture
          then ["no-new-privileges", "seccomp=unconfined", "apparmor=unconfined", "label=disable"]
          else ["apparmor=unconfined", "no-new-privileges"]
      )
  entrypoint <- member "entrypoint" value
  arguments <- member "cmd" value
  configuredUser <- member "user" value :: IO Text
  (entrypoint :: [Text]) @?= [fixtureEntrypoint (usesSystemd fixture)]
  (arguments :: [Text]) @?= fixtureArguments (usesSystemd fixture)
  assertBool
    "fixture image configured a non-root user"
    (configuredUser `elem` ["", "root", "0", "0:0", "root:root"])
  mounts <- member "mounts" value :: IO [Value]
  actualNames <- traverse (member "Name") mounts :: IO [Text]
  actualTypes <- traverse (member "Type") mounts :: IO [Text]
  actualTargets <- traverse (member "Destination") mounts :: IO [Text]
  writable <- traverse (member "RW") mounts :: IO [Bool]
  sort actualNames @?= sort (volumes fixture)
  actualTypes @?= replicate 3 "volume"
  sort actualTargets @?= sort (fixtureVolumeTargets (usesSystemd fixture))
  writable @?= replicate 3 True

stopOwned :: Fixture -> IO ()
stopOwned fixture = do
  verifyContainer fixture
  void (succeeded fixture (subprocess "docker" ["stop", "--time", "5", container fixture]))
  assertStopped fixture

assertStopped :: Fixture -> IO ()
assertStopped fixture = do
  state <-
    succeeded
      fixture
      ( subprocess
          "docker"
          ["inspect", "--type", "container", "--format", "{{json .State}}", container fixture]
      )
      >>= decodeJSON
  member "Running" state >>= (@?= False)
  member "Paused" state >>= (@?= False)
  member "Restarting" state >>= (@?= False)
  member "Pid" state >>= (@?= (0 :: Integer))

-- Every actual command keeps exact captured bytes under the ignored fixture
-- home. Tar bytes remain in the owned generation file, never Haskell Text.
recorded :: Fixture -> Subprocess -> IO (ProcessOutcome, LBS.ByteString)
recorded fixture command = do
  number <- atomicModifyIORef' (serial fixture) (\n -> (n + 1, n))
  let stem = evidence fixture </> ("command-" <> show number)
  privateWrite (stem <> "-input.json") $
    encode $
      object
        [ "executable" .= subprocessPath command
        , "argv" .= subprocessArguments command
        , "stdin_sha256" .= fmap (sha256Hex . Encoding.encodeUtf8) (subprocessStdin command)
        ]
  forM_ (subprocessStdin command) $ \input ->
    privateWrite (stem <> "-stdin.raw") (LBS.fromStrict (Encoding.encodeUtf8 input))
  attempted <-
    timeout 45000000 (Stream.runStreamingWithSpawnObservation Stream.defaultSubprocessEnv command)
  actual <- case attempted of
    Just observation -> pure observation
    Nothing -> do
      privateWrite (stem <> "-result.json") $
        encode
          ( object
              [ "status" .= ("fixture_subprocess_wall_timeout" :: Text)
              , "wall_seconds" .= (45 :: Int)
              , "actual_exit" .= Null
              ]
          )
      assertFailure ("PV fixture subprocess exceeded 45 seconds; evidence: " <> stem)
  let stdout = Stream.nativeSpawnResultStdoutBytes actual
      stderr = Stream.nativeSpawnResultStderrBytes actual
      outcome = Stream.nativeSpawnResultOutcome actual
      actualExit = case outcome of
        ProcessSucceeded _ -> 0
        ProcessFailed failure -> case processFailureExitCode failure of
          ExitFailure failureCode -> failureCode
          ExitSuccess -> error "ProcessFailed cannot contain ExitSuccess"
  privateWrite (stem <> "-stdout.raw") stdout
  privateWrite (stem <> "-stderr.raw") stderr
  privateWrite (stem <> "-result.json") $
    encode $
      object
        [ "actual_exit" .= actualExit
        , "outcome" .= renderProcessOutcome outcome
        , "stdout_bytes" .= LBS.length stdout
        , "stdout_sha256" .= sha256Hex (LBS.toStrict stdout)
        , "stderr_bytes" .= LBS.length stderr
        , "stderr_sha256" .= sha256Hex (LBS.toStrict stderr)
        ]
  pure (outcome, stdout)

within :: String -> Int -> IO a -> IO a
within description seconds action = do
  attempted <- timeout (seconds * 1000000) action
  maybe
    (assertFailure (description <> " exceeded " <> show seconds <> " seconds") >> fail "fixture timeout")
    pure
    attempted

succeeded :: Fixture -> Subprocess -> IO LBS.ByteString
succeeded fixture command = do
  (outcome, stdout) <- recorded fixture command
  case outcome of
    ProcessSucceeded _ -> pure stdout
    ProcessFailed _ ->
      assertFailure
        ( "fixture command failed; retained evidence: "
            <> evidence fixture
            <> "\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

privateWrite :: FilePath -> LBS.ByteString -> IO ()
privateWrite path bytes = do
  LBS.writeFile path bytes
  setPermissions path (setOwnerWritable True (setOwnerReadable True emptyPermissions))

decodeJSON :: LBS.ByteString -> IO Value
decodeJSON = expect . eitherDecode

member :: (FromJSON a) => Text -> Value -> IO a
member key (Object fields) = case KM.lookup (Key.fromText key) fields of
  Nothing -> fail ("missing fixture JSON field " <> Text.unpack key)
  Just value -> case fromJSON value of
    Success actual -> pure actual
    Error reason -> fail reason
member _ _ = fail "fixture JSON object expected"

expect :: Either String a -> IO a
expect = either fail pure

jsonText :: (ToJSON a) => a -> Text
jsonText = Encoding.decodeUtf8 . LBS.toStrict . encode

consumerSetup :: Text
consumerSetup =
  Text.unlines
    [ "import json,os,pathlib,subprocess,sys"
    , "assert os.geteuid()==0"
    , "root=pathlib.Path(sys.argv[1]); source=pathlib.Path('/var/local/jitml-stateful-pv'+str(root)); consumer=pathlib.Path('/fixture/consumer')"
    , "assert not list(pathlib.Path('/fixture').iterdir()) and not list(pathlib.Path('/var/local').iterdir()) and not list(pathlib.Path('/jitml/.data').iterdir())"
    , "root.mkdir(parents=True); source.mkdir(parents=True); consumer.mkdir()"
    , "(root/'identity').write_bytes(b'old-host-home'); (source/'identity').write_bytes(b'restored-node-var')"
    , "subprocess.run(['mount','--bind',str(root),str(consumer)],check=True,timeout=10)"
    , "def identity(p): s=p.stat(); return [s.st_dev,s.st_ino]"
    , "assert identity(root)==identity(consumer) and identity(root)!=identity(source)"
    , "print(json.dumps({'old_identity':identity(root),'restored_identity':identity(source)}))"
    ]

consumerChecks :: Text
consumerChecks =
  Text.unlines
    [ "import json,pathlib,subprocess,sys"
    , "mode=sys.argv[1]; root=pathlib.Path(sys.argv[2]); source=pathlib.Path('/var/local/jitml-stateful-pv'+str(root)); consumer=pathlib.Path('/fixture/consumer')"
    , "def identity(p): s=p.stat(); return [s.st_dev,s.st_ino]"
    , "assert identity(root)==identity(source) and (root/'identity').read_bytes()==b'restored-node-var'"
    , "if mode=='rebind':"
    , " subprocess.run(['umount',str(consumer)],check=True,timeout=10)"
    , " subprocess.run(['mount','--bind',str(root),str(consumer)],check=True,timeout=10)"
    , "elif mode=='stale':"
    , " assert identity(consumer)!=identity(source) and (consumer/'identity').read_bytes()==b'old-host-home'"
    , "elif mode=='current':"
    , " assert identity(consumer)==identity(source) and (consumer/'identity').read_bytes()==b'restored-node-var'"
    , "else: raise AssertionError('unknown consumer fixture mode')"
    , "print(json.dumps({'node_identity':identity(root),'consumer_identity':identity(consumer)}))"
    ]

staticConsumerSetup :: Text
staticConsumerSetup =
  Text.unlines
    [ "import json,os,pathlib,subprocess,sys"
    , "root=pathlib.Path(sys.argv[1]); source=pathlib.Path('/var/local/jitml-stateful-pv'+str(root)); child=source/'nested/prometheus-db'; consumer=pathlib.Path('/fixture/consumer')"
    , "assert os.geteuid()==0 and not list(pathlib.Path('/fixture').iterdir())"
    , "child.mkdir(parents=True); (child/'identity').write_bytes(b'ordinary-static-child'); consumer.mkdir()"
    , "(source/'link-to-child').symlink_to('nested/prometheus-db',target_is_directory=True)"
    , "subprocess.run(['mount','--bind',str(root),str(consumer)],check=True,timeout=10)"
    , "assert consumer.stat().st_ino==source.stat().st_ino and consumer.stat().st_ino!=child.stat().st_ino"
    , "print(json.dumps({'fixture':'static-consumer','whole_root_is_not_selected_child':True}))"
    ]

staticConsumerChecks :: Text
staticConsumerChecks =
  Text.unlines
    [ "import json,pathlib,subprocess,sys"
    , "root=pathlib.Path(sys.argv[1]); child=root/'nested/prometheus-db'; consumer=pathlib.Path('/fixture/consumer')"
    , "subprocess.run(['umount',str(consumer)],check=True,timeout=10)"
    , "subprocess.run(['mount','--bind',str(child),str(consumer)],check=True,timeout=10)"
    , "a=child.stat(); b=consumer.stat(); assert (a.st_dev,a.st_ino)==(b.st_dev,b.st_ino)"
    , "assert (consumer/'identity').read_bytes()==b'ordinary-static-child'"
    , "print(json.dumps({'fixture':'static-consumer','selected_child_bind_matches':True}))"
    ]

fixtureSetup :: Text
fixtureSetup =
  Text.unlines
    [ "import json,os,pathlib,stat,struct,subprocess,sys"
    , "kind=sys.argv[1]; paths=json.loads(sys.argv[2]); base=pathlib.Path('/var/local/jitml-stateful-pv')"
    , "assert os.geteuid()==0 and not list(pathlib.Path('/fixture').iterdir())"
    , "assert not list(pathlib.Path('/var/local').iterdir()) and not list(pathlib.Path('/jitml/.data').iterdir())"
    , "def acl():"
    , " return struct.pack('<I',2)+b''.join(struct.pack('<HHI',t,p,u) for t,p,u in [(1,7,0xffffffff),(2,5,34567),(4,5,0xffffffff),(16,5,0xffffffff),(32,1,0xffffffff)])"
    , "def restrictive(p):"
    , " os.chown(p,12345,23456); os.chmod(p,0o2751)"
    , " for name in ['system.posix_acl_access','system.posix_acl_default']: os.setxattr(p,name,acl())"
    , " os.setxattr(p,'user.jitml-projection',b'ordinary-retained-root')"
    , " os.utime(p,ns=(1700000000456789123,1700000000456789123))"
    , " assert stat.S_IMODE(os.stat(p).st_mode)==0o2751"
    , "external=pathlib.Path('/fixture/external'); external.mkdir(); (external/'control').write_bytes(b'foreign-fixture-control')"
    , "if kind=='restored':"
    , " source=pathlib.Path('/fixture/source'); source.mkdir()"
    , " for path in paths: (source/path.lstrip('/')).mkdir(parents=True)"
    , " leaf=source/paths[0].lstrip('/'); (leaf/'payload').write_bytes(b'ordinary-restored-payload')"
    , " os.link(leaf/'payload',leaf/'hardlink'); os.symlink('payload',leaf/'symlink')"
    , " os.chown(leaf/'payload',12346,23457); os.chmod(leaf/'payload',0o640)"
    , " os.setxattr(leaf/'payload','user.jitml-projection',b'ordinary-payload')"
    , " os.utime(leaf/'payload',ns=(1700000000123456789,1700000000123456789))"
    , " restrictive(leaf); os.chmod(source,0o2755)"
    , " pathlib.Path('/fixture/generation').mkdir(mode=0o700)"
    , "else:"
    , " base.mkdir(); leaf=base/paths[0].lstrip('/'); leaf.parent.mkdir(parents=True)"
    , " if kind=='file': leaf.write_bytes(b'original-file-blocker')"
    , " elif kind=='symlink': leaf.symlink_to(external,target_is_directory=True)"
    , " else: leaf.mkdir(); restrictive(leaf)"
    , " if kind=='wrong-bind':"
    , "  target=pathlib.Path(paths[0]); target.mkdir(parents=True)"
    , "  subprocess.run(['mount','--bind',str(external),str(target)],check=True)"
    , "print(json.dumps({'fixture':kind,'registered_roots':paths}))"
    ]

fixtureChecks :: Text
fixtureChecks =
  Text.unlines
    [ "import json,os,pathlib,stat,sys"
    , "kind=sys.argv[1]; paths=json.loads(sys.argv[2]); base=pathlib.Path('/var/local/jitml-stateful-pv')"
    , "leaf=base/paths[0].lstrip('/'); s=leaf.stat()"
    , "assert (s.st_uid,s.st_gid,stat.S_IMODE(s.st_mode),s.st_mtime_ns)==(12345,23456,0o2751,1700000000456789123)"
    , "assert all(x in os.listxattr(leaf) for x in ['system.posix_acl_access','system.posix_acl_default','user.jitml-projection'])"
    , "if kind=='restored':"
    , " assert (leaf/'payload').read_bytes()==b'ordinary-restored-payload'"
    , " assert (leaf/'payload').stat().st_ino==(leaf/'hardlink').stat().st_ino"
    , " assert os.readlink(leaf/'symlink')=='payload'"
    , "elif kind=='fresh':"
    , " assert not list(leaf.iterdir())"
    , " for path in paths[1:]:"
    , "  s=(base/path.lstrip('/')).stat(); assert stat.S_IMODE(s.st_mode)==0o777"
    , "print(json.dumps({'checked':kind}))"
    ]
