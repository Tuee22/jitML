{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Explicitly synthetic raw provider observations and public disk-backed
-- Store fixtures. None attests Docker, Kubernetes, MinIO or device execution.
module GenericRlPhysicalControls (genericRlPhysicalControls) where

import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, ask, runReaderT)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import GenericRlPhysicalProof qualified as Proof
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan (refinePlanIdText)
import JitML.Product.Evidence qualified as Evidence
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Proto.Rl qualified as Rl
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as Budget
import JitML.Service.Capabilities (ETag (..), HasMinIO (..))
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.Workload qualified as Workload
import JitML.Substrate (Substrate (..))
import JitML.Test.DeviceWitnessFixture qualified as WitnessFixture
import JitML.Training.Budget qualified as Training
import System.Directory (removeFile)
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

genericRlPhysicalControls :: TestTree
genericRlPhysicalControls =
  testGroup
    "generic RL physical proof controls"
    [ testCase "current dist path and platform bytes reject installed or foreign executables" $ do
        let root = "/fixture/repo"
            arch = "build/aarch64-linux"
            actual = root <> "/dist-newstyle/" <> arch <> "/jitml/build/jitml"
            elf = BS.pack [127, 69, 76, 70, 0]
        Proof.validateCli root arch actual (BS.take 4 elf) elf @?= Right ()
        Proof.parseReceiptField "address" "address: observed\n" @?= Right "observed"
        forM_ ["", "address: one\naddress: two\n"] $ \output ->
          invalid
            Proof.Cli
            "missing or duplicate actual CLI receipt field address"
            (Proof.parseReceiptField "address" output)
        Proof.validateSelectedSubstrate LinuxCPU (Just "linux-cpu") @?= Right ()
        mismatch
          Proof.Cli
          (Nothing :: Maybe String)
          (Just "linux-cpu" :: Maybe String)
          (Proof.validateSelectedSubstrate LinuxCPU Nothing)
        mismatch
          Proof.Cli
          (Just "linux-cuda" :: Maybe String)
          (Just "linux-cpu" :: Maybe String)
          (Proof.validateSelectedSubstrate LinuxCPU (Just "linux-cuda"))
        Proof.validateNoMountedRunConfig False @?= Right ()
        rejected
          Proof.Cli
          "WorkflowMatrix local CLI proof refuses a mounted worker RunConfig"
          (Proof.validateNoMountedRunConfig True)
        forM_ [Nothing, Just ""] $ \value -> Proof.validateNoSemanticOverride "JITML_MAX_STEPS" value @?= Right ()
        forM_
          ["JITML_MAX_STEPS", "JITML_EVAL_EPISODES", "JITML_PRODUCT_RL_VEC_ENVS", "JITML_EXPERIMENT_HASH"]
          $ \key ->
            rejected
              Proof.Cli
              ("WorkflowMatrix RL proof refuses inherited semantic override " <> key)
              (Proof.validateNoSemanticOverride key (Just "override"))
        rejected
          Proof.Cli
          "GenericRL refuses an installed/baked CLI fallback; build the current CLI"
          (Proof.validateCli root arch "/usr/local/bin/jitml" (BS.take 4 elf) elf)
        rejected
          Proof.Cli
          "GenericRL needs the actual current-platform executable"
          (Proof.validateCli root arch actual (BS.take 4 elf) "MachO")
    , testCase "image executable source and PATH pins are independently enforced" $ do
        let bytes = "fixture executable observation"
            expected = sha256Hex bytes
            stamp = Source.sourceStampFromFiles [("src/fixture.hs", "old")]
            changed = Source.sourceStampFromFiles [("src/fixture.hs", "new")]
        Proof.validateImageTarget target @?= Right ()
        Proof.validateOwnedContainerId (Text.replicate 64 "c") @?= Right ()
        rejected
          Proof.Image
          "the promoted image has no canonical immutable OCI target"
          (Proof.validateImageTarget "mutable:tag")
        rejected
          Proof.Image
          "docker create returned a noncanonical owned container id"
          (Proof.validateOwnedContainerId "short")
        Proof.validateImageDescriptor target imageConfig @?= Right ()
        assertCause
          Proof.Image
          (Proof.MissingField "Env")
          ( Proof.validateImageDescriptor
              target
              (object ["Image" .= target, "WorkingDir" .= ("/jitml" :: Text)])
          )
        Proof.validateImageExecutable expected bytes @?= Right ()
        Proof.validateImageSource stamp stamp @?= Right ()
        Proof.validateResolvedExecutable "/usr/local/bin/jitml" @?= Right ()
        mismatch
          Proof.Image
          (sha256Hex "substituted")
          expected
          (Proof.validateImageExecutable expected "substituted")
        mismatch Proof.Image changed stamp (Proof.validateImageSource stamp changed)
        mismatch
          Proof.Image
          ("/tmp/jitml" :: Text)
          "/usr/local/bin/jitml"
          (Proof.validateResolvedExecutable "/tmp/jitml")
        forM_ [[], ["PATH=/a", "PATH=/b"]] $ \paths ->
          invalid
            Proof.Image
            "immutable producer image has no unique PATH"
            (Proof.validateImageDescriptor target (put "Env" (Aeson.toJSON (paths :: [Text])) imageConfig))
        forM_ ["PATH=/bin:", "PATH=relative:/bin", "PATH=:/bin"] $ \path ->
          rejected
            Proof.Image
            "image PATH contains a relative or empty executable lookup component"
            (Proof.validateImageDescriptor target (put "Env" (Aeson.toJSON [path :: Text]) imageConfig))
        mismatch
          Proof.Image
          ("/other" :: Text)
          "/jitml"
          (Proof.validateImageDescriptor target (put "WorkingDir" (String "/other") imageConfig))
        mismatch
          Proof.Image
          ("mutable:tag" :: Text)
          target
          (Proof.validateImageDescriptor target (put "Image" (String "mutable:tag") imageConfig))
    , testCase "image proof rejects unbounded siblings and substituted ownership before start" $ do
        let caller = "fixture-client"
            stamp = Source.sourceStampFromFiles [("src/fixture.hs", "source")]
            observed = imageProofHelper caller stamp
            check = Proof.validateImageProofHelper target caller stamp
        check observed @?= Right ()
        forM_
          [ (["HostConfig", "NanoCpus"], Aeson.toJSON (0 :: Integer))
          , (["HostConfig", "Memory"], Aeson.toJSON (0 :: Integer))
          , (["HostConfig", "MemorySwap"], Aeson.toJSON (-1 :: Integer))
          , (["HostConfig", "PidsLimit"], Aeson.Null)
          , (["HostConfig", "ReadonlyRootfs"], Bool False)
          , (["HostConfig", "Privileged"], Bool True)
          , (["HostConfig", "NetworkMode"], String "host")
          , (["HostConfig", "CgroupnsMode"], String "host")
          , (["HostConfig", "PidMode"], String "host")
          , (["HostConfig", "CapAdd"], Aeson.toJSON ["SYS_ADMIN" :: Text])
          , (["HostConfig", "CapDrop"], Aeson.toJSON ([] :: [Text]))
          , (["HostConfig", "SecurityOpt"], Aeson.toJSON ([] :: [Text]))
          , (["HostConfig", "RestartPolicy", "Name"], String "always")
          , (["HostConfig", "Tmpfs"], object [])
          , (["Name"], String "/another-helper")
          , (["Config", "Image"], String "mutable:tag")
          , (["Config", "Labels", "jitml.proof.owner"], String "another-client")
          , (["Config", "Labels", "jitml.proof.source"], String (Text.replicate 64 "0"))
          , (["Config", "Cmd"], Aeson.toJSON ["-c", "sleep 30" :: Text])
          , (["State", "Running"], Bool True)
          , (["State", "StartedAt"], String "2026-11-03T00:00:00Z")
          ,
            ( ["Mounts"]
            , Aeson.toJSON [object ["Type" .= ("bind" :: Text), "Destination" .= ("/data" :: Text), "RW" .= True]]
            )
          ]
          $ \(path, replacement) ->
            assertBool ("unsafe image helper accepted: " <> show path) $
              case check (change path replacement observed) of
                Left (Proof.ProofFailure stage _) -> stage == Proof.Image
                Right () -> False
        assertBool
          "different callers share an image-proof exclusion name"
          (Proof.imageProofHelperName caller /= Proof.imageProofHelperName "another-client")
    , testCase "OCI raw bytes platform selection and CRI config cannot be substituted" $ do
        let bytes =
              LBS.toStrict
                (Aeson.encode (object ["os" .= ("linux" :: Text), "architecture" .= ("arm64" :: Text)]))
            address = "sha256:" <> sha256Hex bytes
            descriptor arch =
              object
                [ "digest" .= configDigest
                , "platform" .= object ["os" .= ("linux" :: Text), "architecture" .= (arch :: Text)]
                ]
            index entries = object ["manifests" .= entries]
            config = object ["os" .= ("linux" :: Text), "architecture" .= ("arm64" :: Text)]
            cri = object ["status" .= object ["id" .= configDigest]]
        _ <- expectRight (Proof.decodeOciContent address bytes)
        mismatch
          Proof.Oci
          ("sha256:" <> sha256Hex (bytes <> " "))
          address
          (Proof.decodeOciContent address (bytes <> " "))
        rejected Proof.Oci "noncanonical OCI content digest" (Proof.decodeOciContent "mutable:tag" bytes)
        let malformed = "not-json"
        invalidPrefix
          Proof.Oci
          "invalid OCI JSON:"
          (Proof.decodeOciContent ("sha256:" <> sha256Hex malformed) malformed)
        Proof.platformManifestDigest "arm64" config @?= Right Nothing
        Proof.platformManifestDigest "arm64" (index [descriptor "arm64"]) @?= Right (Just configDigest)
        forM_ [[], [descriptor "amd64"], [descriptor "arm64", descriptor "arm64"]] $ \entries ->
          invalid
            Proof.Oci
            "image target has no unique current-node Linux platform manifest"
            (Proof.platformManifestDigest "arm64" (index entries))
        Proof.imageTargetFromListing target ("name type " <> target <> " remainder") @?= Right ()
        forM_ ["", "name type " <> target <> "\nname type " <> target] $ \listing ->
          invalid
            Proof.Oci
            "the current Kind node has no unique promoted image target"
            (Proof.imageTargetFromListing target listing)
        mismatch
          Proof.Oci
          configDigest
          target
          (Proof.imageTargetFromListing target ("name type " <> configDigest))
        Proof.validateOciConfig "arm64" config @?= Right ()
        Proof.validateCriImage configDigest cri @?= Right ()
        mismatch
          Proof.Oci
          ("amd64" :: Text)
          "arm64"
          (Proof.validateOciConfig "arm64" (put "architecture" (String "amd64") config))
        mismatch
          Proof.Oci
          ("darwin" :: Text)
          "linux"
          (Proof.validateOciConfig "arm64" (put "os" (String "darwin") config))
        mismatch
          Proof.Oci
          target
          configDigest
          (Proof.validateCriImage configDigest (object ["status" .= object ["id" .= target]]))
    , testCase "node lane readiness and exact Job UID ownership are required" $ do
        Proof.validateNode LinuxCPU "arm64" node @?= Right nodeName
        rejected
          Proof.Node
          "node belongs to another cluster/substrate"
          (Proof.validateNode LinuxCPU "arm64" (change ["metadata", "name"] (String "foreign") node))
        rejected
          Proof.Node
          "a current published node is not Ready"
          ( Proof.validateNode
              LinuxCPU
              "arm64"
              (change ["status", "conditions"] (Aeson.toJSON ([] :: [Value])) node)
          )
        mismatch
          Proof.Node
          ("amd64" :: Text)
          "arm64"
          ( Proof.validateNode
              LinuxCPU
              "arm64"
              (change ["status", "nodeInfo", "architecture"] (String "amd64") node)
          )
        mismatch
          Proof.Node
          ("false" :: Text)
          "true"
          ( Proof.validateNode
              LinuxCPU
              "arm64"
              (change ["metadata", "labels", "jitml.substrate/linux-cpu"] (String "false") node)
          )
        Proof.validateJob start job @?= Right "job-uid"
        mismatch
          Proof.Job
          ("foreign-name" :: Text)
          jobName
          (Proof.validateJob start (change ["metadata", "name"] (String "foreign-name") job))
        Proof.selectOwnedPod jobName "job-uid" (object ["items" .= [pod]]) @?= Right pod
        forM_
          [[], [change ["metadata", "ownerReferences"] (Aeson.toJSON [owner "foreign-uid"]) pod], [pod, pod]]
          $ \pods ->
            invalid
              Proof.PodOwner
              "expected one actual Pod owned by the exact Job UID"
              (Proof.selectOwnedPod jobName "job-uid" (object ["items" .= pods]))
        invalid
          Proof.PodOwner
          "expected one actual Pod owned by the exact Job UID"
          ( Proof.selectOwnedPod
              jobName
              "job-uid"
              ( object
                  [ "items"
                      .= [change ["metadata", "ownerReferences"] (Aeson.toJSON [owner "job-uid", owner "job-uid"]) pod]
                  ]
              )
          )
        rejected
          Proof.Job
          "Job has no actual UID"
          (Proof.validateJob start (change ["metadata", "uid"] (String "") job))
        rejected
          Proof.PodPlacement
          "Pod has no actual UID"
          (Proof.validatePodPlacement start pins (change ["metadata", "uid"] (String "") pod))
        rejected
          Proof.PodPlacement
          "owned Pod is already deleting"
          ( Proof.validatePodPlacement
              start
              pins
              (change ["metadata", "deletionTimestamp"] (String "deleting") pod)
          )
        invalid
          Proof.PodPlacement
          "worker ran on a node outside the pre-launch image capability set"
          (Proof.validatePodPlacement start [] pod)
    , testCase "worker spec rejects executable replacement through command environment or mounts" $ do
        Proof.validatePodSpec start spec @?= Right ()
        mismatch
          Proof.PodSpec
          (["sh"] :: [Text])
          ["jitml"]
          (Proof.validatePodSpec start (workerPut "command" (Aeson.toJSON ["sh" :: Text]) spec))
        mismatch
          Proof.PodSpec
          (["rl", "train", "foreign"] :: [Text])
          ["rl", "train", experiment]
          ( Proof.validatePodSpec
              start
              (workerPut "args" (Aeson.toJSON ["rl", "train", "foreign" :: Text]) spec)
          )
        forM_
          [ ("envFrom", Aeson.toJSON [object []], "unexpected worker envFrom may replace executable PATH")
          , ("workingDir", String "/tmp", "worker changes the image executable lookup directory")
          , ("lifecycle", object [], "unexpected worker lifecycle can replace the image executable")
          ]
          $ \(key, value, reason) ->
            rejected Proof.PodSpec reason (Proof.validatePodSpec start (workerPut key value spec))
        forM_ ["startupProbe", "livenessProbe", "readinessProbe", "volumeDevices"] $ \key ->
          rejected
            Proof.PodSpec
            "unexpected worker probe/block mount changes the audited executable boundary"
            (Proof.validatePodSpec start (workerPut key (object []) spec))
        rejected
          Proof.PodSpec
          "unexpected worker init containers"
          (Proof.validatePodSpec start (put "initContainers" (Aeson.toJSON [object []]) spec))
        invalid
          Proof.PodSpec
          "expected one production RL worker container"
          (Proof.validatePodSpec start (put "containers" (Aeson.toJSON ([] :: [Value])) spec))
        mismatch
          Proof.PodSpec
          ([("PATH", "/tmp")] :: [(Text, Text)])
          []
          ( Proof.validatePodSpec
              start
              ( workerPut
                  "env"
                  (Aeson.toJSON [object ["name" .= ("PATH" :: Text), "value" .= ("/tmp" :: Text)]])
                  spec
              )
          )
        forM_ [("subPath", String "jitml"), ("subPathExpr", String "$(PATH)")] $ \(key, value) ->
          rejected
            Proof.PodSpec
            "worker subPath changes the audited mount boundary"
            ( Proof.validatePodSpec
                start
                (workerPut "volumeMounts" (Aeson.toJSON [put key value runMount, serviceMount]) spec)
            )
        rejected
          Proof.PodSpec
          "unexpected worker mount can replace image executable/source"
          ( Proof.validatePodSpec
              start
              ( workerPut
                  "volumeMounts"
                  ( Aeson.toJSON
                      [ runMount
                      , serviceMount
                      , object ["name" .= ("replace" :: Text), "mountPath" .= ("/usr/local/bin" :: Text)]
                      ]
                  )
                  spec
              )
          )
        mismatch
          Proof.PodSpec
          (False :: Bool)
          True
          ( Proof.validatePodSpec
              start
              ( workerPut
                  "volumeMounts"
                  (Aeson.toJSON [runMount, serviceMount, put "readOnly" (Bool False) accountMount])
                  spec
              )
          )
        mismatch
          Proof.PodSpec
          (0 :: Int)
          1
          (Proof.validatePodSpec start (workerPut "volumeMounts" (Aeson.toJSON [serviceMount]) spec))
        mismatch
          Proof.PodSpec
          (2 :: Int)
          1
          ( Proof.validatePodSpec
              start
              (workerPut "volumeMounts" (Aeson.toJSON [runMount, runMount, serviceMount]) spec)
          )
    , testCase "actual worker runtime identity successful exit and zero restarts are required" $ do
        Proof.validatePodPlacement start pins pod @?= Right (nodeName, configDigest)
        Proof.validatePodRuntime configDigest pod @?= Right ()
        invalid
          Proof.PodRuntime
          "worker Pod did not contain exactly one observed container"
          ( Proof.validatePodRuntime
              configDigest
              (change ["status", "containerStatuses"] (Aeson.toJSON ([] :: [Value])) pod)
          )
        mismatch
          Proof.PodRuntime
          ("Failed" :: Text)
          "Succeeded"
          (Proof.validatePodRuntime configDigest (change ["status", "phase"] (String "Failed") pod))
        forM_
          [ ("name", String "foreign", Proof.ValueMismatch (show ("foreign" :: Text)) (show ("rl" :: Text)))
          , ("imageID", String target, Proof.ValueMismatch (show target) (show configDigest))
          , ("restartCount", Aeson.toJSON (1 :: Int), Proof.ValueMismatch "1" "0")
          ,
            ( "containerID"
            , String "docker://tag"
            , Proof.Rejected "worker has no canonical actual containerd identity"
            )
          ]
          $ \(key, value, cause) ->
            Proof.validatePodRuntime configDigest (statusPut key value pod)
              @?= Left (Proof.ProofFailure Proof.PodRuntime cause)
        mismatch
          Proof.PodRuntime
          (2 :: Int)
          0
          ( Proof.validatePodRuntime
              configDigest
              (statusPut "state" (object ["terminated" .= object ["exitCode" .= (2 :: Int)]]) pod)
          )
    , testCase "public Store fixture binds physical generic completion before deeper proof checks" $
        withSystemTempDirectory "generic-physical-store" $ \root -> do
          (admitted, completed, blob, final) <- storeFixture root Nothing "rl-ppo-weights" (Just LinuxCPU)
          Proof.validateAdmittedCheckpoint start admitted @?= Right completed
          let foreignStart = start {Rl.srlExperimentHash = "foreign-experiment"}
          mismatch
            Proof.CheckpointAdmission
            experiment
            ("foreign-experiment" :: Text)
            (Proof.validateAdmittedCheckpoint foreignStart admitted)
          let changed = start {Rl.srlSeed = 8}
          expected <- expectRight (Workload.rlPlanForStart changed)
          actual <- expectRight (Workload.rlPlanForStart start)
          mismatch
            Proof.CheckpointAdmission
            actual
            expected
            (Proof.validateAdmittedCheckpoint changed admitted)
          path <-
            expectRight
              ( Store.objectPathForKey
                  root
                  (Checkpoint.manifestKey experiment (Store.admittedCheckpointManifestSha admitted))
              )
          raw <- BS.readFile path
          Proof.validateRawEnvelope start admitted raw @?= Right ()
          blobPath <- expectRight (Store.objectPathForKey root blob)
          BS.writeFile blobPath "tampered physical JMW1"
          corrupted <-
            Store.admitLocalCheckpointAt root experiment (Store.admittedCheckpointManifestSha admitted)
          case corrupted of
            Left (Store.AdmissionBlobInvalid reason) ->
              assertBool
                "wrong physical payload rejection"
                ("writer-commit SHA-256 mismatch" `Text.isInfixOf` reason)
            other -> assertFailure ("expected actual physical blob rejection: " <> show other)
          removeFile blobPath
          missing <-
            Store.admitLocalCheckpointAt root experiment (Store.admittedCheckpointManifestSha admitted)
          case missing of
            Left (Store.AdmissionBlobReadFailed key _) -> key @?= blob
            other -> assertFailure ("expected exact missing physical blob: " <> show other)
          LBS.writeFile blobPath final
          BS.writeFile path "tampered actual manifest"
          malformed <-
            Store.admitLocalCheckpointAt root experiment (Store.admittedCheckpointManifestSha admitted)
          case malformed of
            Left (Store.AdmissionManifestInvalid _) -> pure ()
            other -> assertFailure ("expected addressed-envelope decoding rejection: " <> show other)
    , testCase "real admitted generic fixtures reject missing foreign witnesses and tensor substitution" $
        withSystemTempDirectory "generic-physical-fixture-variants" $ \root -> do
          (missing, _, _, _) <- storeFixture (root <> "/missing") Nothing "rl-ppo-weights" Nothing
          invalid
            Proof.CheckpointAdmission
            "generic selected-device producer returned no actual execution witness"
            (Proof.validateAdmittedCheckpoint start missing)
          (foreignWitness, _, _, _) <-
            storeFixture (root <> "/foreign") Nothing "rl-ppo-weights" (Just LinuxCUDA)
          mismatch
            Proof.CheckpointAdmission
            LinuxCUDA
            LinuxCPU
            (Proof.validateAdmittedCheckpoint start foreignWitness)
          (renamed, _, _, _) <- storeFixture (root <> "/renamed") Nothing "foreign-tensor" (Just LinuxCPU)
          mismatch
            Proof.CheckpointAdmission
            ("foreign-tensor" :: Text)
            "rl-ppo-weights"
            (Proof.validateAdmittedCheckpoint start renamed)
    , testCase "trajectory raw address complete ordering finite values and headers are required" $ do
        let bytes = trajectory 500
            key = trajectoryKey bytes
        evaluation <- expectRight (Proof.parseTrajectory start key bytes)
        Framework.evaluationSetMedianReward evaluation @?= 500
        mismatch
          Proof.Trajectory
          (trajectoryKey "substituted")
          key
          (Proof.parseTrajectory start (trajectoryKey "substituted") bytes)
        let changed old new = Encoding.encodeUtf8 (Text.replace old new (Encoding.decodeUtf8 bytes))
            check raw = Proof.parseTrajectory start (trajectoryKey raw) raw
        mismatch
          Proof.Trajectory
          ("episode: 0" :: Text)
          "episode: 1"
          (check (changed "episode: 1" "episode: 0"))
        mismatch
          Proof.Trajectory
          ("episode-frame-count: 1" :: Text)
          "episode-frame-count: 0"
          (check (changed "episode-frame-count: 0" "episode-frame-count: 1"))
        let header = take 6 (Text.lines (Encoding.decodeUtf8 bytes))
            foreignHeader = take 6 (Text.lines (Encoding.decodeUtf8 (changed "seed: 7" "seed: 8")))
        mismatch Proof.Trajectory foreignHeader header (check (changed "seed: 7" "seed: 8"))
        invalid
          Proof.Trajectory
          "invalid physical trajectory field episode-steps: "
          (check (changed "episode-steps: 500" "episode-steps: invalid"))
        invalid
          Proof.Trajectory
          (show ("RL evaluation reward must be finite" :: Text))
          (check (changed "episode-reward: 500.0" "episode-reward: 1e999"))
        invalid
          Proof.Trajectory
          (show ("RL evaluation episode 0 must report positive steps" :: Text))
          (check (changed "episode-steps: 500" "episode-steps: 0"))
        let truncated = Encoding.encodeUtf8 (Text.unlines (take 15 (Text.lines (Encoding.decodeUtf8 bytes))))
        mismatch Proof.Trajectory (15 :: Int) 16 (check truncated)
        let trailing = bytes <> "unexpected trailing row\n"
        mismatch Proof.Trajectory (17 :: Int) 16 (check trailing)
    , testCase "physical completion and event compare the entire finite evaluation cohort" $
        withSystemTempDirectory "generic-physical-cohort" $ \root -> do
          (admitted, completed, _, _) <- storeFixture root Nothing "rl-ppo-weights" (Just LinuxCPU)
          evaluation <-
            expectRight (Proof.parseTrajectory start (trajectoryKey (trajectory 500)) (trajectory 500))
          Proof.validateCheckpointEvaluation start admitted completed evaluation @?= Right ()
          event <-
            expectRight
              ( Rl.completeCheckpointDoneRL
                  ( Rl.CheckpointDoneRL
                      experiment
                      (Store.admittedCheckpointManifestSha admitted)
                      (Training.completedTrainingObservedUnits completed)
                      (Checkpoint.latestPointerKey experiment)
                  )
                  completed
              )
          let outcomes = [(0, 500, 500, True), (1, 500, 500, True)]
          Proof.validateEventProjection start admitted completed evaluation event outcomes 500 @?= Right ()
          mismatch
            Proof.Event
            (499 :: Double)
            500
            (Proof.validateEventProjection start admitted completed evaluation event outcomes 499)
          mismatch
            Proof.Event
            (take 1 outcomes)
            outcomes
            (Proof.validateEventProjection start admitted completed evaluation event (take 1 outcomes) 500)
          forM_
            [ [(0, 499, 500, True), (1, 500, 500, True)]
            , [(0, 500, 499, True), (1, 500, 500, True)]
            , [(0, 500, 500, False), (1, 500, 500, True)]
            ]
            $ \changedOutcomes ->
              mismatch
                Proof.Event
                changedOutcomes
                outcomes
                (Proof.validateEventProjection start admitted completed evaluation event changedOutcomes 500)
          let changed =
                event {Rl.ccdrlCheckpoint = (Rl.ccdrlCheckpoint event) {Rl.cdrlManifestSha = Text.replicate 64 "f"}}
          mismatch
            Proof.Event
            (Text.replicate 64 "f")
            (Store.admittedCheckpointManifestSha admitted)
            (Proof.validateEventProjection start admitted completed evaluation changed outcomes 500)
          (_, otherCompleted, _, _) <-
            storeFixture (root <> "/other-completion") Nothing "rl-ppo-weights" Nothing
          mismatch
            Proof.Event
            otherCompleted
            completed
            ( Proof.validateEventProjection
                start
                admitted
                completed
                evaluation
                (event {Rl.ccdrlCompletedTraining = otherCompleted})
                outcomes
                500
            )
          worse <- expectRight (Proof.parseTrajectory start (trajectoryKey (trajectory 499)) (trajectory 499))
          mismatch
            Proof.CheckpointEvaluation
            ([500] :: [Double])
            [499]
            (Proof.validateCheckpointEvaluation start admitted completed worse)
    , testCase "strict new preflight persists exact bytes and rejects even an identical duplicate" $
        withSystemTempDirectory "generic-physical-preflight" $ \root -> do
          let ref = Store.checkpointObjectRef "jitml-checkpoints/fixture/artifacts/preflight/fresh.txt"
          runFilesystemMinIO root (Proof.publishPreflight ref "actual bytes") >>= (@?= Right ())
          result <- runFilesystemMinIO root (Proof.publishPreflight ref "actual bytes")
          case result of
            Left (Proof.ProofFailure Proof.Preflight (Proof.PutFailed (SEConflict _))) -> pure ()
            other -> assertFailure ("strict duplicate preflight did not fail: " <> show other)
          runFilesystemMinIO root (minioReadBytes ref) >>= (@?= Right "actual bytes")
    , testCase "preflight never reads after failed PUT and never trusts an acknowledged false write" $ do
        forM_ [PutFailure, ReadFailure, UnauthorizedRead, WrongBytes, HonestBytes] $ \mode -> do
          calls <- newIORef []
          let ref = Store.checkpointObjectRef "jitml-checkpoints/fixture/preflight"
          result <- runReaderT (unTransport (Proof.publishPreflight ref "actual bytes")) (mode, calls)
          case mode of
            PutFailure ->
              result @?= Left (Proof.ProofFailure Proof.Preflight (Proof.PutFailed (SEUnauthorized "put denied")))
            ReadFailure ->
              result
                @?= Left
                  (Proof.ProofFailure Proof.Preflight (Proof.ReadFailed (SENotFound "false PUT acknowledgement")))
            UnauthorizedRead ->
              result
                @?= Left (Proof.ProofFailure Proof.Preflight (Proof.ReadFailed (SEUnauthorized "read denied")))
            WrongBytes -> mismatch Proof.Preflight ("substituted" :: BS.ByteString) "actual bytes" result
            HonestBytes -> result @?= Right ()
          readIORef calls >>= (@?= if mode == PutFailure then ["put"] else ["put", "read"])
    ]

start :: Rl.StartRLRun
start = Rl.StartRLRun experiment "ppo" "cartpole" LinuxCPU 7 128 2

experiment, target, configDigest, nodeName, jobName :: Text
experiment = "generic-physical-offline-fixture"
target = "sha256:" <> Text.replicate 64 "a"
configDigest = "sha256:" <> Text.replicate 64 "b"
nodeName = "jitml-linux-cpu-worker"
jobName = "jitml-rl-" <> experiment

pins :: [(Text, Text)]
pins = [(nodeName, configDigest)]

imageConfig, spec, runMount, serviceMount, accountMount, node, job, pod :: Value
imageConfig =
  object
    [ "Image" .= target
    , "WorkingDir" .= ("/jitml" :: Text)
    , "Env" .= ["PATH=/usr/local/bin:/usr/bin" :: Text]
    ]

imageProofHelper :: Text -> Source.SourceStamp -> Value
imageProofHelper caller stamp =
  object
    [ "Name" .= ("/" <> Proof.imageProofHelperName caller)
    , "Config"
        .= object
          [ "Image" .= target
          , "User" .= ("0:0" :: Text)
          , "Entrypoint" .= ["/bin/sh" :: Text]
          , "Cmd" .= ["-c", "command -v jitml" :: Text]
          , "Labels"
              .= object
                [ "jitml.proof.role" .= ("generic-rl-image-capability" :: Text)
                , "jitml.proof.owner" .= caller
                , "jitml.proof.source" .= Source.stampSha256 stamp
                ]
          ]
    , "HostConfig"
        .= object
          [ "NanoCpus" .= (500000000 :: Integer)
          , "Memory" .= (536870912 :: Integer)
          , "MemorySwap" .= (536870912 :: Integer)
          , "PidsLimit" .= (64 :: Int)
          , "ReadonlyRootfs" .= True
          , "Privileged" .= False
          , "NetworkMode" .= ("none" :: Text)
          , "CgroupnsMode" .= ("private" :: Text)
          , "PidMode" .= ("" :: Text)
          , "CapAdd" .= Aeson.Null
          , "CapDrop" .= ["ALL" :: Text]
          , "SecurityOpt" .= ["no-new-privileges" :: Text]
          , "RestartPolicy" .= object ["Name" .= ("no" :: Text)]
          , "Tmpfs" .= object ["/tmp" .= ("rw,nosuid,nodev,size=67108864" :: Text)]
          ]
    , "Mounts" .= ([] :: [Value])
    , "State"
        .= object
          [ "Status" .= ("created" :: Text)
          , "Error" .= ("" :: Text)
          , "Pid" .= (0 :: Int)
          , "Running" .= False
          , "Paused" .= False
          , "Restarting" .= False
          , "Dead" .= False
          , "OOMKilled" .= False
          , "StartedAt" .= ("0001-01-01T00:00:00Z" :: Text)
          ]
    ]
runMount = object ["name" .= ("jitml-run-config" :: Text), "mountPath" .= ("/etc/jitml/run" :: Text)]
serviceMount =
  object ["name" .= ("jitml-service-config" :: Text), "mountPath" .= ("/etc/jitml/service" :: Text)]
accountMount =
  object
    [ "name" .= ("kube-api-access-fixture" :: Text)
    , "mountPath" .= ("/var/run/secrets/kubernetes.io/serviceaccount" :: Text)
    , "readOnly" .= True
    ]
spec =
  object
    [ "nodeName" .= nodeName
    , "containers"
        .= [ object
               [ "name" .= ("rl" :: Text)
               , "image" .= ("jitml:local" :: Text)
               , "command" .= ["jitml" :: Text]
               , "args" .= ["rl", "train", experiment]
               , "volumeMounts" .= [runMount, serviceMount, accountMount]
               ]
           ]
    ]
node =
  object
    [ "metadata"
        .= object ["name" .= nodeName, "labels" .= object ["jitml.substrate/linux-cpu" .= ("true" :: Text)]]
    , "status"
        .= object
          [ "conditions" .= [object ["type" .= ("Ready" :: Text), "status" .= ("True" :: Text)]]
          , "nodeInfo" .= object ["architecture" .= ("arm64" :: Text)]
          ]
    ]
job =
  object
    [ "metadata" .= object ["name" .= jobName, "uid" .= ("job-uid" :: Text)]
    , "spec" .= object ["template" .= object ["spec" .= spec]]
    ]
pod =
  object
    [ "metadata" .= object ["uid" .= ("pod-uid" :: Text), "ownerReferences" .= [owner "job-uid"]]
    , "spec" .= spec
    , "status"
        .= object
          [ "phase" .= ("Succeeded" :: Text)
          , "containerStatuses"
              .= [ object
                     [ "name" .= ("rl" :: Text)
                     , "imageID" .= configDigest
                     , "containerID" .= ("containerd://" <> Text.replicate 64 "c")
                     , "restartCount" .= (0 :: Int)
                     , "state" .= object ["terminated" .= object ["exitCode" .= (0 :: Int)]]
                     ]
                 ]
          ]
    ]

owner :: Text -> Value
owner uid = object ["kind" .= ("Job" :: Text), "name" .= jobName, "uid" .= uid]

put :: Text -> Value -> Value -> Value
put key value (Object fields) = Object (KeyMap.insert (Key.fromText key) value fields)
put _ _ value = value

change :: [Text] -> Value -> Value -> Value
change [] value _ = value
change [key] value current = put key value current
change (key : keys) value current@(Object fields) =
  maybe
    current
    (\old -> put key (change keys value old) current)
    (KeyMap.lookup (Key.fromText key) fields)
change _ _ value = value

arrayPut :: Text -> Text -> Value -> Value -> Value
arrayPut array key value current@(Object fields) = case KeyMap.lookup (Key.fromText array) fields of
  Just old -> case Aeson.fromJSON old of
    Aeson.Success [entry] -> put array (Aeson.toJSON [put key value entry]) current
    _ -> current
  _ -> current
arrayPut _ _ _ value = value

workerPut :: Text -> Value -> Value -> Value
workerPut = arrayPut "containers"

statusPut :: Text -> Value -> Value -> Value
statusPut key value current@(Object fields) = case KeyMap.lookup "status" fields of
  Just status -> put "status" (arrayPut "containerStatuses" key value status) current
  Nothing -> current
statusPut _ _ value = value

storeFixture
  :: FilePath
  -> Maybe Text
  -> Text
  -> Maybe Substrate
  -> IO (Store.AdmittedCheckpoint, Training.CompletedTraining, Text, LBS.ByteString)
storeFixture root overrideExperiment tensorName witnessLane = do
  let actualStart = maybe start (\value -> start {Rl.srlExperimentHash = value}) overrideExperiment
      name = Rl.srlExperimentHash actualStart
      final = WeightCodec.encodeJmw1 [1, 2]
      initial = WeightCodec.encodeJmw1 [0, 0]
      finalSha = WeightCodec.jmw1ContentSha final
      blob = Checkpoint.blobKey name finalSha
  plan <- expectRight (Workload.rlPlanForStart actualStart)
  schedule <-
    maybe
      (assertFailure "fixture requires actual public neural schedule" >> fail "unreachable")
      pure
      (Budget.compiledRlSchedule plan)
  let steps = Budget.scheduleObservedEnvironmentSteps schedule
  budget <- expectRight (Training.mkTrainingBudget Training.RlEnvironmentStepBudget steps (Just 7))
  evidence0 <-
    expectRight
      ( Evidence.mkTrainingEvidence
          (WeightCodec.jmw1ContentSha initial)
          finalSha
          3
          (sha256Hex "fixture-environment-observation")
      )
  evidence <- case witnessLane of
    Nothing -> pure evidence0
    Just lane -> do
      witness <- expectRight =<< WitnessFixture.fixtureDeviceExecutionWitnessFor lane
      expectRight (Evidence.attachDeviceExecutionWitness witness evidence0)
  criterion <-
    expectRight (Training.measureCriterion "median_final_reward" Training.MetricMaximise 450 500)
  planId <- expectRight (refinePlanIdText (Budget.compiledRlPlanId plan))
  unbound <-
    expectRight
      ( Training.completedTraining
          planId
          budget
          steps
          evidence
          [criterion]
          ( Training.TensorBoardRunMetadata
              "generic-offline-fixture"
              "tensorboard/generic-offline-fixture"
              ["median_final_reward"]
          )
      )
  completed <- expectRight (Training.bindCompletedTrainingToRlPlan plan unbound)
  let manifest =
        Checkpoint.attachCompletedTraining completed $
          (Checkpoint.emptyManifest "generic-physical-fixture" name [Checkpoint.TensorBlob tensorName [2] blob])
            { Checkpoint.manifestStep = steps
            , Checkpoint.manifestMetrics =
                [ ("env_steps", fromIntegral steps)
                , ("episode_count", 2)
                , ("avg_reward", 500)
                , ("median_final_reward", 500)
                ]
            }
  _ <-
    expectRight
      =<< Store.writeCompletedCheckpointSnapshot root completed manifest [(blob, final)] Nothing
  admitted <- expectRight =<< Store.admitLocalLatestCheckpoint root name
  exact <-
    expectRight
      =<< Store.admitLocalCheckpointAt root name (Store.admittedCheckpointManifestSha admitted)
  admitted @?= exact
  physicalBlob <- case Checkpoint.manifestTensors (Store.admittedCheckpointManifest admitted) of
    [tensor] -> do
      Checkpoint.tensorName tensor @?= tensorName
      Checkpoint.tensorShape tensor @?= [2]
      pure (Checkpoint.tensorBlobKey tensor)
    _ -> assertFailure "fixture expected exactly one admitted tensor" >> fail "unreachable"
  physicalPath <- expectRight (Store.objectPathForKey root physicalBlob)
  physicalBytes <- BS.readFile physicalPath
  physicalBytes @?= LBS.toStrict final
  pure (admitted, completed, physicalBlob, final)

trajectory :: Double -> BS.ByteString
trajectory reward =
  Encoding.encodeUtf8 $
    Text.unlines $
      [ "kind: rl-trajectory-v1"
      , "experiment-hash: " <> experiment
      , "environment: cartpole"
      , "trainer: ppo"
      , "seed: 7"
      , "episodes: 2"
      ]
        <> concat
          [ [ "episode: " <> Text.pack (show index)
            , "episode-steps: 500"
            , "episode-reward: " <> Text.pack (show reward)
            , "episode-done: True"
            , "episode-frame-count: 0"
            ]
          | index <- [0 :: Int, 1]
          ]

trajectoryKey :: BS.ByteString -> Text
trajectoryKey bytes = experiment <> "/artifacts/rl-trajectory/" <> sha256Hex bytes <> ".txt"

data Mode = PutFailure | ReadFailure | UnauthorizedRead | WrongBytes | HonestBytes
  deriving stock (Eq, Show)
newtype Transport a = Transport {unTransport :: ReaderT (Mode, IORef [Text]) IO a}
  deriving newtype (Functor, Applicative, Monad)

instance HasMinIO Transport where
  minioPutIfAbsent _ _ = pure (Left (SETransient "unexpected text PUT"))
  minioReadObject _ = pure (Left (SETransient "unexpected text read"))
  minioReadBytes _ = Transport $ do
    (mode, calls) <- ask
    liftIO (modifyIORef' calls (<> ["read"]))
    pure $ case mode of
      ReadFailure -> Left (SENotFound "false PUT acknowledgement")
      UnauthorizedRead -> Left (SEUnauthorized "read denied")
      WrongBytes -> Right "substituted"
      _ -> Right "actual bytes"
  putBlobIfAbsent _ _ = pure (Left (SETransient "unexpected text blob PUT"))
  putBlobBytesIfAbsent _ _ = Transport $ do
    (mode, calls) <- ask
    liftIO (modifyIORef' calls (<> ["put"]))
    pure $
      if mode == PutFailure then Left (SEUnauthorized "put denied") else Right (ETag "acknowledged")
  casPointer _ _ _ = pure (Left (SETransient "unexpected CAS"))
  listObjects _ _ = pure (Left (SETransient "unexpected list"))
  deleteObject _ = pure (Left (SETransient "unexpected delete"))

expectRight :: (Show e) => Either e a -> IO a
expectRight = either (\failure -> assertFailure (show failure) >> fail "unreachable") pure

rejected :: Proof.ProofStage -> String -> Either Proof.ProofFailure a -> Assertion
rejected stage reason = assertCause stage (Proof.Rejected reason)

invalid :: Proof.ProofStage -> String -> Either Proof.ProofFailure a -> Assertion
invalid stage reason = assertCause stage (Proof.Invalid reason)

mismatch :: (Show a) => Proof.ProofStage -> a -> a -> Either Proof.ProofFailure c -> Assertion
mismatch stage actual expected = assertCause stage (Proof.ValueMismatch (show actual) (show expected))

assertCause :: Proof.ProofStage -> Proof.ProofCause -> Either Proof.ProofFailure a -> Assertion
assertCause stage cause result = case result of
  Left failure -> failure @?= Proof.ProofFailure stage cause
  Right _ -> assertFailure "invalid raw observation was accepted"

invalidPrefix :: Proof.ProofStage -> String -> Either Proof.ProofFailure a -> Assertion
invalidPrefix stage prefix result = case result of
  Left (Proof.ProofFailure actualStage (Proof.Invalid reason)) -> do
    actualStage @?= stage
    assertBool
      ("wrong specific invalid cause: " <> reason)
      (Text.pack prefix `Text.isPrefixOf` Text.pack reason)
  Left failure -> assertFailure ("wrong typed failure: " <> show failure)
  Right _ -> assertFailure "invalid raw observation was accepted"
