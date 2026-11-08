{-# LANGUAGE OverloadedStrings #-}

-- | Structural refiners over actual collector observations. Ordinary parsed
-- fixture values do not authenticate a provider, device or producer. Physical
-- checkpoint checks require public Store admission; no opaque value is forged.
module GenericRlPhysicalProof
  ( parseReceiptField
  , validateSelectedSubstrate
  , validateNoMountedRunConfig
  , validateNoSemanticOverride
  , ProofStage (..)
  , ProofCause (..)
  , ProofFailure (..)
  , validateImageTarget
  , validateOwnedContainerId
  , validateCli
  , validateCliPath
  , validateCliMagic
  , validateImageDescriptor
  , imageProofHelperMemoryBytes
  , imageProofHelperNanoCpus
  , imageProofHelperName
  , imageProofHelperCreateArguments
  , validateImageProofHelper
  , validateImageExecutable
  , validateImageSource
  , validateResolvedExecutable
  , validateNode
  , imageTargetFromListing
  , decodeOciContent
  , platformManifestDigest
  , validateOciConfig
  , validateCriImage
  , validateJob
  , selectOwnedPod
  , validatePodPlacement
  , validatePodRuntime
  , validatePodSpec
  , validateAdmittedCheckpoint
  , validateRawEnvelope
  , validateCheckpointEvaluation
  , parseTrajectory
  , parseTrajectoryRows
  , refineTrajectoryOutcomes
  , validateEventProjection
  , publishPreflight
  ) where

import Codec.Serialise qualified as Serialise
import Control.Monad (unless)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (traverse_)
import Data.List qualified as List
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Data.Word (Word64)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.ExternalBars qualified as Bars
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Proto.Rl qualified as Rl
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as Budget
import JitML.Service.Capabilities (HasMinIO (..), ObjectRef)
import JitML.Service.Retry (ServiceError)
import JitML.Service.Workload qualified as Workload
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Training.Budget qualified as Training
import System.FilePath ((</>))
import Text.Read (readMaybe)

data ProofStage
  = Cli
  | Image
  | Node
  | Oci
  | Job
  | PodOwner
  | PodPlacement
  | PodRuntime
  | PodSpec
  | CheckpointAdmission
  | RawEnvelope
  | Trajectory
  | CheckpointEvaluation
  | Event
  | Preflight
  deriving stock (Eq, Show)

data ProofCause
  = Rejected String
  | MissingField Text
  | WrongJsonType String
  | ValueMismatch String String
  | Invalid String
  | PutFailed ServiceError
  | ReadFailed ServiceError
  deriving stock (Eq, Show)

data ProofFailure = ProofFailure ProofStage ProofCause
  deriving stock (Eq, Show)

type Check = Either ProofCause

at :: ProofStage -> Check a -> Either ProofFailure a
at stage = first (ProofFailure stage)

require :: String -> Bool -> Check ()
require reason = flip unless (Left (Rejected reason))

infix 4 ===
(===) :: (Eq a, Show a) => a -> a -> Check ()
actual === expected = if actual == expected then Right () else Left (ValueMismatch (show actual) (show expected))

bad :: String -> Check a
bad = Left . Invalid

expect :: (Show e) => Either e a -> Check a
expect = first (Invalid . show)

optional :: Aeson.Value -> Text -> Maybe Aeson.Value
optional (Aeson.Object values) key = KeyMap.lookup (Key.fromText key) values
optional _ _ = Nothing

field :: Aeson.Value -> Text -> Check Aeson.Value
field value key = maybe (Left (MissingField key)) Right (optional value key)

as :: (Aeson.FromJSON a) => Aeson.Value -> Check a
as value = case Aeson.fromJSON value of
  Aeson.Success result -> Right result
  Aeson.Error reason -> Left (WrongJsonType reason)

text :: Aeson.Value -> Text -> Check Text
text value key = field value key >>= as

sha :: Text -> Bool
sha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

digest :: Text -> Bool
digest value = maybe False sha (Text.stripPrefix "sha256:" value)

parseReceiptField :: Text -> Text -> Either ProofFailure Text
parseReceiptField key output = at Cli $
  case [value | row <- Text.lines output, Just value <- [Text.stripPrefix (key <> ": ") row]] of
    [value] -> Right value
    _ -> bad ("missing or duplicate actual CLI receipt field " <> Text.unpack key)

validateSelectedSubstrate :: Substrate -> Maybe String -> Either ProofFailure ()
validateSelectedSubstrate substrate actual = at Cli (actual === Just (Text.unpack (renderSubstrate substrate)))

validateNoMountedRunConfig :: Bool -> Either ProofFailure ()
validateNoMountedRunConfig mounted =
  at Cli $ require "WorkflowMatrix local CLI proof refuses a mounted worker RunConfig" (not mounted)

validateNoSemanticOverride :: String -> Maybe String -> Either ProofFailure ()
validateNoSemanticOverride name value =
  at Cli $
    require
      ("WorkflowMatrix RL proof refuses inherited semantic override " <> name)
      (maybe True null value)

validateImageTarget :: Text -> Either ProofFailure ()
validateImageTarget value = at Image $ require "the promoted image has no canonical immutable OCI target" (digest value)

validateOwnedContainerId :: Text -> Either ProofFailure ()
validateOwnedContainerId value = at Image $ require "docker create returned a noncanonical owned container id" (sha value)

validateCli
  :: FilePath -> FilePath -> FilePath -> BS.ByteString -> BS.ByteString -> Either ProofFailure ()
validateCli repo archDir canonicalPath expectedMagic bytes = do
  validateCliPath repo archDir canonicalPath
  validateCliMagic expectedMagic bytes

validateCliPath :: FilePath -> FilePath -> FilePath -> Either ProofFailure ()
validateCliPath repo archDir canonicalPath =
  at Cli $
    require
      "GenericRL refuses an installed/baked CLI fallback; build the current CLI"
      ((repo </> "dist-newstyle" </> archDir </> "") `List.isPrefixOf` canonicalPath)

validateCliMagic :: BS.ByteString -> BS.ByteString -> Either ProofFailure ()
validateCliMagic expectedMagic bytes =
  at Cli $
    require "GenericRL needs the actual current-platform executable" (BS.take 4 bytes == expectedMagic)

validateImageDescriptor :: Text -> Aeson.Value -> Either ProofFailure ()
validateImageDescriptor target config = at Image $ do
  text config "Image" >>= (=== target)
  text config "WorkingDir" >>= (=== "/jitml")
  environment <- field config "Env" >>= as
  path <- case [value | entry <- (environment :: [Text]), Just value <- [Text.stripPrefix "PATH=" entry]] of
    [value] -> Right value
    _ -> bad "immutable producer image has no unique PATH"
  require
    "image PATH contains a relative or empty executable lookup component"
    (all (Text.isPrefixOf "/") (Text.splitOn ":" path))

imageProofHelperMemoryBytes, imageProofHelperNanoCpus :: Integer
imageProofHelperMemoryBytes = 536870912
imageProofHelperNanoCpus = 500000000

-- A fixed name per caller is also Docker's atomic exclusion boundary: another
-- proof cannot create a second sibling before the first has been removed.
imageProofHelperName :: Text -> Text
imageProofHelperName owner =
  "jm-generic-rl-image-proof-" <> Text.take 24 (sha256Hex (Encoding.encodeUtf8 owner))

imageProofHelperCreateArguments :: Text -> Text -> Text -> Source.SourceStamp -> [Text]
imageProofHelperCreateArguments architecture target owner stamp =
  [ "create"
  , "--pull=never"
  , "--platform=linux/" <> architecture
  , "--name=" <> imageProofHelperName owner
  , "--label=jitml.proof.role=generic-rl-image-capability"
  , "--label=jitml.proof.owner=" <> owner
  , "--label=jitml.proof.source=" <> Source.stampSha256 stamp
  , "--user=0:0"
  , "--cpus=0.5"
  , "--memory=" <> Text.pack (show imageProofHelperMemoryBytes)
  , "--memory-swap=" <> Text.pack (show imageProofHelperMemoryBytes)
  , "--pids-limit=64"
  , "--network=none"
  , "--cgroupns=private"
  , "--read-only"
  , "--cap-drop=ALL"
  , "--security-opt=no-new-privileges"
  , "--restart=no"
  , "--tmpfs=/tmp:rw,nosuid,nodev,size=67108864"
  , "--entrypoint=/bin/sh"
  , target
  , "-c"
  , "command -v jitml"
  ]

-- Refine actual Docker observations before start, independently of the create
-- arguments. Parsed observations alone do not authenticate their producer.
validateImageProofHelper
  :: Text -> Text -> Source.SourceStamp -> Aeson.Value -> Either ProofFailure ()
validateImageProofHelper target owner stamp observed = at Image $ do
  text observed "Name" >>= (=== ("/" <> imageProofHelperName owner))
  config <- field observed "Config"
  text config "Image" >>= (=== target)
  text config "User" >>= (=== "0:0")
  entrypoint <- field config "Entrypoint" >>= as
  (entrypoint :: [Text]) === ["/bin/sh"]
  command <- field config "Cmd" >>= as
  (command :: [Text]) === ["-c", "command -v jitml"]
  labels <- field config "Labels"
  text labels "jitml.proof.role" >>= (=== "generic-rl-image-capability")
  text labels "jitml.proof.owner" >>= (=== owner)
  text labels "jitml.proof.source" >>= (=== Source.stampSha256 stamp)
  caps <- field observed "HostConfig"
  let integer key expected = do
        actual <- field caps key >>= as
        (actual :: Integer) === expected
      boolean value key expected = do
        actual <- field value key >>= as
        (actual :: Bool) === expected
  integer "NanoCpus" imageProofHelperNanoCpus
  integer "Memory" imageProofHelperMemoryBytes
  integer "MemorySwap" imageProofHelperMemoryBytes
  integer "PidsLimit" 64
  boolean caps "ReadonlyRootfs" True
  boolean caps "Privileged" False
  text caps "NetworkMode" >>= (=== "none")
  text caps "CgroupnsMode" >>= (=== "private")
  pidMode <- text caps "PidMode"
  require "image proof helper must have a private PID namespace" (pidMode `elem` ["", "private"])
  require
    "image proof helper must not add capabilities"
    (optional caps "CapAdd" `elem` [Just Aeson.Null, Just (Aeson.Array mempty)])
  dropped <- field caps "CapDrop" >>= as
  (dropped :: [Text]) === ["ALL"]
  security <- field caps "SecurityOpt" >>= as
  require
    "image proof helper requires no-new-privileges"
    ((security :: [Text]) == ["no-new-privileges"] || security == ["no-new-privileges=true"])
  field caps "RestartPolicy" >>= (`text` "Name") >>= (=== "no")
  tmpfs <- field caps "Tmpfs"
  tmpfs === Aeson.object ["/tmp" Aeson..= ("rw,nosuid,nodev,size=67108864" :: Text)]
  mounts <- field observed "Mounts" >>= as
  require "image proof helper must not mount host data" (length (mounts :: [Aeson.Value]) <= 1)
  traverse_
    ( \mount -> do
        text mount "Type" >>= (=== "tmpfs")
        text mount "Destination" >>= (=== "/tmp")
        boolean mount "RW" True
    )
    mounts
  state <- field observed "State"
  text state "Status" >>= (=== "created")
  text state "Error" >>= (=== "")
  pid <- field state "Pid" >>= as
  (pid :: Integer) === 0
  traverse_ (\key -> boolean state key False) ["Running", "Paused", "Restarting", "Dead", "OOMKilled"]
  started <- text state "StartedAt"
  require "image proof helper was already started" ("0001-" `Text.isPrefixOf` started)

validateImageExecutable :: Text -> BS.ByteString -> Either ProofFailure ()
validateImageExecutable expected bytes = at Image (sha256Hex bytes === expected)

validateImageSource :: Source.SourceStamp -> Source.SourceStamp -> Either ProofFailure ()
validateImageSource expected actual = at Image (actual === expected)

validateResolvedExecutable :: Text -> Either ProofFailure ()
validateResolvedExecutable actual = at Image (actual === "/usr/local/bin/jitml")

validateNode :: Substrate -> Text -> Aeson.Value -> Either ProofFailure Text
validateNode substrate architecture node = at Node $ do
  metadata <- field node "metadata"
  name <- text metadata "name"
  labels <- field metadata "labels"
  require
    "node belongs to another cluster/substrate"
    (("jitml-" <> renderSubstrate substrate <> "-") `Text.isPrefixOf` name)
  text labels ("jitml.substrate/" <> renderSubstrate substrate) >>= (=== "true")
  status <- field node "status"
  conditions <- field status "conditions" >>= as
  ready <-
    traverse
      (\condition -> (,) <$> text condition "type" <*> text condition "status")
      (conditions :: [Aeson.Value])
  require "a current published node is not Ready" (("Ready", "True") `elem` ready)
  info <- field status "nodeInfo"
  text info "architecture" >>= (=== architecture)
  pure name

imageTargetFromListing :: Text -> Text -> Either ProofFailure ()
imageTargetFromListing target listing = at Oci $
  case [value | row <- Text.lines listing, _ : _ : value : _ <- [Text.words row], digest value] of
    [actual] -> actual === target
    _ -> bad "the current Kind node has no unique promoted image target"

decodeOciContent :: Text -> BS.ByteString -> Either ProofFailure Aeson.Value
decodeOciContent expected bytes = at Oci $ do
  require "noncanonical OCI content digest" (digest expected)
  ("sha256:" <> sha256Hex bytes) === expected
  first (Invalid . ("invalid OCI JSON: " <>)) (Aeson.eitherDecodeStrict' bytes)

platformManifestDigest :: Text -> Aeson.Value -> Either ProofFailure (Maybe Text)
platformManifestDigest architecture root = at Oci $
  case optional root "manifests" of
    Nothing -> Right Nothing
    Just descriptors -> do
      candidates <- as descriptors
      selected <-
        traverse
          ( \descriptor -> do
              platform <- field descriptor "platform"
              os <- text platform "os"
              arch <- text platform "architecture"
              value <- text descriptor "digest"
              pure (os == "linux" && arch == architecture, value)
          )
          (candidates :: [Aeson.Value])
      case [value | (True, value) <- selected] of
        [value] -> Right (Just value)
        _ -> bad "image target has no unique current-node Linux platform manifest"

validateOciConfig :: Text -> Aeson.Value -> Either ProofFailure ()
validateOciConfig architecture config = at Oci $ do
  text config "os" >>= (=== "linux")
  text config "architecture" >>= (=== architecture)

validateCriImage :: Text -> Aeson.Value -> Either ProofFailure ()
validateCriImage configDigest cri =
  at Oci $
    field cri "status" >>= (`text` "id") >>= (=== configDigest)

validateJob :: Rl.StartRLRun -> Aeson.Value -> Either ProofFailure Text
validateJob start job = do
  at Job $ do
    metadata <- field job "metadata"
    text metadata "name" >>= (=== jobName)
    uid <- text metadata "uid"
    require "Job has no actual UID" (not (Text.null uid))
  template <- at Job (field job "spec" >>= (`field` "template") >>= (`field` "spec"))
  validatePodSpec start template
  at Job (field job "metadata" >>= (`text` "uid"))
 where
  jobName = "jitml-rl-" <> Rl.srlExperimentHash start

selectOwnedPod :: Text -> Text -> Aeson.Value -> Either ProofFailure Aeson.Value
selectOwnedPod jobName jobUid podList = at PodOwner $ do
  pods <- field podList "items" >>= as
  owned <-
    traverse
      ( \pod -> do
          metadata <- field pod "metadata"
          owners <- field metadata "ownerReferences" >>= as
          identities <-
            traverse
              (\owner -> (,,) <$> text owner "kind" <*> text owner "name" <*> text owner "uid")
              (owners :: [Aeson.Value])
          pure
            ( [(kind, name, uid) | (kind, name, uid) <- identities, kind == "Job", name == jobName, uid == jobUid]
                == [("Job", jobName, jobUid)]
            , pod
            )
      )
      (pods :: [Aeson.Value])
  case [value | (True, value) <- owned] of
    [value] -> Right value
    _ -> bad "expected one actual Pod owned by the exact Job UID"

validatePodPlacement
  :: Rl.StartRLRun -> [(Text, Text)] -> Aeson.Value -> Either ProofFailure (Text, Text)
validatePodPlacement start nodePins pod = do
  at PodPlacement $ do
    metadata <- field pod "metadata"
    uid <- text metadata "uid"
    require "Pod has no actual UID" (not (Text.null uid))
    require
      "owned Pod is already deleting"
      (optional metadata "deletionTimestamp" `elem` [Nothing, Just Aeson.Null])
  spec <- at PodPlacement (field pod "spec")
  validatePodSpec start spec
  at PodPlacement $ do
    node <- text spec "nodeName"
    config <-
      maybe
        (bad "worker ran on a node outside the pre-launch image capability set")
        Right
        (lookup node nodePins)
    pure (node, config)

validatePodRuntime :: Text -> Aeson.Value -> Either ProofFailure ()
validatePodRuntime config pod = at PodRuntime $ do
  status <- field pod "status"
  text status "phase" >>= (=== "Succeeded")
  statuses <- field status "containerStatuses" >>= as
  worker <- case (statuses :: [Aeson.Value]) of
    [value] -> Right value
    _ -> bad "worker Pod did not contain exactly one observed container"
  text worker "name" >>= (=== "rl")
  text worker "imageID" >>= (=== config)
  containerId <- text worker "containerID"
  require
    "worker has no canonical actual containerd identity"
    (maybe False sha (Text.stripPrefix "containerd://" containerId))
  restarts <- field worker "restartCount" >>= as
  (restarts :: Int) === 0
  terminated <- field worker "state" >>= (`field` "terminated")
  exitCode <- field terminated "exitCode" >>= as
  (exitCode :: Int) === 0

validatePodSpec :: Rl.StartRLRun -> Aeson.Value -> Either ProofFailure ()
validatePodSpec start spec = at PodSpec $ do
  require
    "unexpected worker init containers"
    (optional spec "initContainers" `elem` [Nothing, Just (Aeson.Array mempty)])
  containers <- field spec "containers" >>= as
  worker <- case (containers :: [Aeson.Value]) of
    [value] -> pure value
    _ -> bad "expected one production RL worker container"
  text worker "name" >>= (=== "rl")
  text worker "image" >>= (=== "jitml:local")
  command <- field worker "command" >>= as
  (command :: [Text]) === ["jitml"]
  args <- field worker "args" >>= as
  (args :: [Text]) === ["rl", "train", Rl.srlExperimentHash start]
  require
    "unexpected worker envFrom may replace executable PATH"
    (optional worker "envFrom" `elem` [Nothing, Just (Aeson.Array mempty)])
  environment <- case optional worker "env" of
    Nothing -> pure []
    Just value -> do
      entries <- as value
      traverse (\entry -> (,) <$> text entry "name" <*> text entry "value") (entries :: [Aeson.Value])
  environment === case Rl.srlSubstrate start of
    LinuxCUDA -> [("NVIDIA_VISIBLE_DEVICES", "all"), ("NVIDIA_DRIVER_CAPABILITIES", "compute,utility")]
    _ -> []
  require
    "worker changes the image executable lookup directory"
    (optional worker "workingDir" `elem` [Nothing, Just (Aeson.String "/jitml")])
  require
    "unexpected worker lifecycle can replace the image executable"
    (isNothing (optional worker "lifecycle"))
  traverse_
    ( require
        "unexpected worker probe/block mount changes the audited executable boundary"
        . isNothing
        . optional worker
    )
    ["startupProbe", "livenessProbe", "readinessProbe", "volumeDevices"]
  mounts <- field worker "volumeMounts" >>= as
  paths <-
    traverse
      ( \mount -> do
          name <- text mount "name"
          path <- text mount "mountPath"
          require
            "worker subPath changes the audited mount boundary"
            (isNothing (optional mount "subPath") && isNothing (optional mount "subPathExpr"))
          if (name, path)
            `elem` [("jitml-run-config", "/etc/jitml/run"), ("jitml-service-config", "/etc/jitml/service")]
            then pure (name, path)
            else do
              require
                "unexpected worker mount can replace image executable/source"
                ("kube-api-access-" `Text.isPrefixOf` name && path == "/var/run/secrets/kubernetes.io/serviceaccount")
              field mount "readOnly" >>= as >>= (=== True)
              pure (name, path)
      )
      (mounts :: [Aeson.Value])
  length (filter (== ("jitml-run-config", "/etc/jitml/run")) paths) === 1
  length (filter (== ("jitml-service-config", "/etc/jitml/service")) paths) === 1

validateAdmittedCheckpoint
  :: Rl.StartRLRun -> Store.AdmittedCheckpoint -> Either ProofFailure Training.CompletedTraining
validateAdmittedCheckpoint start admitted = at CheckpointAdmission $ do
  expected <- expect (Workload.rlPlanForStart start)
  require
    "this live generic control requires the unchanged PPO/cartpole cohort"
    ( Budget.compiledRlTrainerKind expected == "ppo"
        && Budget.compiledRlEnvironment expected == "cartpole"
    )
  let experiment = Rl.srlExperimentHash start
  require
    "generic RL checkpoint must not claim a canonical ProductRow"
    (case Matrix.productRowForExperimentHash experiment of Nothing -> True; Just _ -> False)
  let manifest = Store.admittedCheckpointManifest admitted
  validated <- expect (Checkpoint.validateCheckpointCompletion manifest)
  let completed = Checkpoint.validatedCheckpointCompletedTraining validated
      budget = Training.completedTrainingBudget completed
  bound <-
    maybe
      (bad "generic completion has no actual compiled plan")
      pure
      (Training.completedTrainingRlPlan completed)
  bound === expected
  schedule <-
    maybe
      (bad "generic MLP completion has no compiled training schedule")
      pure
      (Budget.compiledRlSchedule expected)
  let steps = Budget.scheduleObservedEnvironmentSteps schedule
  Training.trainingBudgetKind budget === Training.RlEnvironmentStepBudget
  Training.trainingBudgetTargetUnits budget === steps
  Training.completedTrainingObservedUnits completed === steps
  Checkpoint.manifestStep manifest === steps
  Checkpoint.manifestExperiment manifest === experiment
  Checkpoint.manifestPlanId manifest === Just (Training.completedTrainingPlanId completed)
  require
    "actual optimizer update counter is not positive"
    (Training.completedTrainingUpdateCount completed > 0)
  require
    "generic trained weights did not move"
    ( Training.completedTrainingInitialWeightHash completed
        /= Training.completedTrainingFinalWeightHash completed
    )
  require
    "generic budget seed contradicts its exact compiled request"
    (maybe True ((== toInteger (Rl.srlSeed start)) . toInteger) (Training.trainingBudgetSeed budget))
  Bars.assertRlConvergenceObservationsExternal bound (Training.completedTrainingMetrics completed)
    === []
  witness <-
    expect (Training.completedTrainingDeviceWitness completed)
      >>= maybe
        (bad "generic selected-device producer returned no actual execution witness")
        pure
  Witness.witnessSubstrate witness === Rl.srlSubstrate start
  case Store.admittedCheckpointWeights admitted of
    [loaded] -> do
      Checkpoint.tensorName (Store.loadedWeightTensor loaded) === "rl-"
        <> Budget.compiledRlTrainerKind expected
        <> "-weights"
      require "generic physical JMW1 payload is empty" (not (null (Store.loadedWeightValues loaded)))
      WeightCodec.jmw1ContentSha (LBS.fromStrict (Store.loadedWeightJmw1Bytes loaded))
        === Training.completedTrainingFinalWeightHash completed
    _ -> bad "generic RL must bind exactly one physical trained weight tensor"
  pure completed

validateRawEnvelope
  :: Rl.StartRLRun -> Store.AdmittedCheckpoint -> BS.ByteString -> Either ProofFailure ()
validateRawEnvelope start admitted rawBytes = at RawEnvelope $ do
  expected <- expect (Workload.rlPlanForStart start)
  let manifestDigest = Store.admittedCheckpointManifestSha admitted
      manifest = Store.admittedCheckpointManifest admitted
  addressed <- expect (Checkpoint.decodeAddressedManifestCbor (LBS.fromStrict rawBytes))
  Checkpoint.addressedManifestSha addressed === manifestDigest
  Checkpoint.addressedManifest addressed === manifest
  envelope <- expect (Serialise.deserialiseOrFail (LBS.fromStrict rawBytes))
  Checkpoint.rawCheckpointVersion envelope === Checkpoint.checkpointWireVersion
  body <-
    expect (Serialise.deserialiseOrFail (LBS.fromStrict (Checkpoint.rawCheckpointBodyBytes envelope)))
  rawManifest <- case body of
    Checkpoint.RawWeightOnlyBody value -> pure value
    Checkpoint.RawSupervisedGraphBody _ -> bad "generic RL returned a supervised graph payload"
  rawCompletion <-
    maybe
      (bad "physical envelope has no raw completion")
      pure
      (Checkpoint.rawManifestCompletedTraining rawManifest)
  Training.rawCompletedTrainingVersion rawCompletion === 3
  Training.rawCompletedTrainingRlPlan rawCompletion
    === Just (Budget.renderCompiledRlPlanTransport expected)

validateCheckpointEvaluation
  :: Rl.StartRLRun
  -> Store.AdmittedCheckpoint
  -> Training.CompletedTraining
  -> Framework.EvaluationSet
  -> Either ProofFailure ()
validateCheckpointEvaluation start admitted completed evaluation = at CheckpointEvaluation $ do
  let manifest = Store.admittedCheckpointManifest admitted
  expected <- expect (Workload.rlPlanForStart start)
  schedule <-
    maybe
      (bad "generic MLP completion has no compiled training schedule")
      Right
      (Budget.compiledRlSchedule expected)
  let steps = Budget.scheduleObservedEnvironmentSteps schedule
  [ Training.coMetricValue value
    | value <- Training.completedTrainingMetrics completed
    , Training.coMetricName value == "median_final_reward"
    ]
    === [Framework.evaluationSetMedianReward evaluation]
  let metrics = Checkpoint.manifestMetrics manifest
  [value | (name, value) <- metrics, name == "env_steps"] === [fromIntegral steps]
  [value | (name, value) <- metrics, name == "episode_count"]
    === [fromIntegral (Rl.srlEvalEpisodes start)]
  [value | (name, value) <- metrics, name == "avg_reward"]
    === [Framework.evaluationSetMeanReward evaluation]
  [value | (name, value) <- metrics, name == "median_final_reward"]
    === [Framework.evaluationSetMedianReward evaluation]

parseTrajectory
  :: Rl.StartRLRun -> Text -> BS.ByteString -> Either ProofFailure Framework.EvaluationSet
parseTrajectory start objectKey bytes = parseTrajectoryRows start objectKey bytes >>= refineTrajectoryOutcomes start

parseTrajectoryRows
  :: Rl.StartRLRun -> Text -> BS.ByteString -> Either ProofFailure [(Word64, Double, Int, Bool)]
parseTrajectoryRows start objectKey bytes = at Trajectory $ do
  let experiment = Rl.srlExperimentHash start
  objectKey === experiment <> "/artifacts/rl-trajectory/" <> sha256Hex bytes <> ".txt"
  rawText <- expect (Encoding.decodeUtf8' bytes)
  expected <- expect (Workload.rlPlanForStart start)
  let count = fromIntegral (Rl.srlEvalEpisodes start) :: Int
      rows = Text.lines rawText
      header =
        [ "kind: rl-trajectory-v1"
        , "experiment-hash: " <> experiment
        , "environment: " <> Rl.srlEnvironment start
        , "trainer: " <> Budget.compiledRlTrainerKind expected
        , "seed: " <> Text.pack (show (Rl.srlSeed start))
        , "episodes: " <> Text.pack (show count)
        ]
  take 6 rows === header
  length rows === 6 + 5 * count
  traverse
    ( \index -> case take 5 (drop (6 + 5 * index) rows) of
        [key, stepsRow, rewardRow, doneRow, frames] -> do
          key === "episode: " <> Text.pack (show index)
          frames === "episode-frame-count: 0"
          steps <- readField "episode-steps: " stepsRow
          reward <- readField "episode-reward: " rewardRow
          done <- readField "episode-done: " doneRow
          pure (fromIntegral index, reward, steps, done)
        _ -> bad "truncated generic RL trajectory row"
    )
    [0 .. count - 1]

refineTrajectoryOutcomes
  :: Rl.StartRLRun -> [(Word64, Double, Int, Bool)] -> Either ProofFailure Framework.EvaluationSet
refineTrajectoryOutcomes start = at Trajectory . expect . Framework.mkEvaluationSet (fromIntegral (Rl.srlEvalEpisodes start))

readField :: (Read a) => Text -> Text -> Check a
readField prefix row = case Text.stripPrefix prefix row >>= readMaybe . Text.unpack of
  Just value -> Right value
  Nothing -> bad ("invalid physical trajectory field " <> Text.unpack prefix)

validateEventProjection
  :: Rl.StartRLRun
  -> Store.AdmittedCheckpoint
  -> Training.CompletedTraining
  -> Framework.EvaluationSet
  -> Rl.CompletedCheckpointDoneRL
  -> [(Word64, Double, Word64, Bool)]
  -> Double
  -> Either ProofFailure ()
validateEventProjection start admitted completed evaluation event observed median = at Event $ do
  let checkpoint = Rl.ccdrlCheckpoint event
  Rl.cdrlExperimentHash checkpoint === Rl.srlExperimentHash start
  Rl.cdrlManifestSha checkpoint === Store.admittedCheckpointManifestSha admitted
  Rl.cdrlPointerKey checkpoint === Checkpoint.latestPointerKey (Rl.srlExperimentHash start)
  Rl.cdrlStep checkpoint === Training.completedTrainingObservedUnits completed
  Rl.ccdrlCompletedTraining event === completed
  let actual =
        [ ( Framework.evaluationEpisodeIdValue key
          , Framework.episodeOutcomeReward outcome
          , fromIntegral (Framework.episodeOutcomeSteps outcome)
          , Framework.episodeOutcomeDone outcome
          )
        | (key, outcome) <- Framework.evaluationSetOutcomes evaluation
        ]
  observed === actual
  median === Framework.evaluationSetMedianReward evaluation

-- | Strict fresh publication. Even identical existing bytes are a failed PUT;
-- no idempotent artifact helper or provider Boolean substitutes exact readback.
publishPreflight :: (HasMinIO m) => ObjectRef -> BS.ByteString -> m (Either ProofFailure ())
publishPreflight ref bytes = do
  put <- putBlobBytesIfAbsent ref bytes
  case put of
    Left failure -> pure (Left (ProofFailure Preflight (PutFailed failure)))
    Right _ -> do
      fetched <- minioReadBytes ref
      pure $ case fetched of
        Left failure -> Left (ProofFailure Preflight (ReadFailed failure))
        Right actual -> at Preflight (actual === bytes)
