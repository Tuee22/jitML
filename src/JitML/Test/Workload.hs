{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Workload
  ( workloadTests
  )
where

import Data.ByteString qualified as ByteString
import Data.Foldable (traverse_)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Coordinator.Topology
  ( ProtocolRoute (..)
  , Topic
  , topicFor
  )
import JitML.Plan.Command (prepareStartSweep, prepareStartTraining, validateStartTraining)
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl
  ( RlCommand (..)
  , StartRLRun (..)
  , StopRLRun (..)
  )
import JitML.Proto.Training
  ( StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , renderTrainingCommand
  )
import JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , TuneCommand (..)
  )
import JitML.Service.BootConfig (Residency (..))
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , ImageRef (..)
  , KubeResource (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Workload
  ( ClusterJobSpec (..)
  , SomeWorkloadEffect (..)
  , WorkloadDecodeError (..)
  , WorkloadEffect (..)
  , WorkloadEffectResult (..)
  , WorkloadLaunch (..)
  , WorkloadPlacement (..)
  , buildInferenceWorkloadEffectsForTopic
  , buildRlWorkloadEffects
  , buildTrainingWorkloadEffects
  , buildTuneWorkloadEffects
  , hostCommandSpecPayload
  , hostCommandSpecTopicName
  , inferenceResultTargetSubstrate
  , inferenceResultTargetTopicName
  , parseWorkloadEffectPayload
  , planWorkloadPlacement
  , renderSomeWorkloadEffect
  , renderWorkloadEffect
  , renderWorkloadEffectPayload
  , renderWorkloadEffectResult
  )
import JitML.Substrate (Substrate (..))

workloadTests :: TestTree
workloadTests =
  testGroup
    "Workload"
    [ testCase "every typed non-inference builder produces a non-empty program" $ do
        assertNonEmptyEffects
          (buildTrainingWorkloadEffects Cluster LinuxCPU (TrainingStart trainingStart))
        assertNonEmptyEffects
          ( buildTrainingWorkloadEffects
              Cluster
              LinuxCPU
              (TrainingStop (StopTraining "training-exp" True))
          )
        assertNonEmptyEffects (buildTuneWorkloadEffects Cluster LinuxCPU (TuneStart tuneStart))
        assertNonEmptyEffects
          (buildTuneWorkloadEffects Cluster LinuxCPU (TuneStop (StopSweep "tune-exp")))
        assertNonEmptyEffects (buildRlWorkloadEffects Cluster LinuxCPU (RlStart rlStart))
        assertNonEmptyEffects
          (buildRlWorkloadEffects Cluster LinuxCPU (RlStop (StopRLRun "rl-exp" True)))
        case buildInferenceWorkloadEffectsForTopic
          linuxInferenceTopic
          (Inference.RunInference inferenceRequest) of
          Left err -> assertFailure (show err)
          Right effects ->
            assertBool "typed inference program was empty" (not (null effects))
    , testCase "Linux Stop programs delete each Job and its derived RunConfig ConfigMap" $ do
        traverse_
          (uncurry assertRenderedEffects)
          [
            (
              [ "kubectl:delete job/jitml-train-training-exp"
              , "kubectl:delete configmap/runconfig-jitml-train-training-exp"
              ]
            , buildTrainingWorkloadEffects
                Cluster
                LinuxCPU
                (TrainingStop (StopTraining "training-exp" True))
            )
          ,
            (
              [ "kubectl:delete job/jitml-train-training-exp"
              , "kubectl:delete configmap/runconfig-jitml-train-training-exp"
              ]
            , buildTrainingWorkloadEffects
                Cluster
                LinuxCUDA
                (TrainingStop (StopTraining "training-exp" False))
            )
          ,
            (
              [ "kubectl:delete job/jitml-tune-tune-exp"
              , "kubectl:delete configmap/runconfig-jitml-tune-tune-exp"
              ]
            , buildTuneWorkloadEffects
                Cluster
                LinuxCPU
                (TuneStop (StopSweep "tune-exp"))
            )
          ,
            (
              [ "kubectl:delete job/jitml-tune-tune-exp"
              , "kubectl:delete configmap/runconfig-jitml-tune-tune-exp"
              ]
            , buildTuneWorkloadEffects
                Cluster
                LinuxCUDA
                (TuneStop (StopSweep "tune-exp"))
            )
          ,
            (
              [ "kubectl:delete job/jitml-rl-rl-exp"
              , "kubectl:delete configmap/runconfig-jitml-rl-rl-exp"
              ]
            , buildRlWorkloadEffects
                Cluster
                LinuxCPU
                (RlStop (StopRLRun "rl-exp" True))
            )
          ,
            (
              [ "kubectl:delete job/jitml-rl-rl-exp"
              , "kubectl:delete configmap/runconfig-jitml-rl-rl-exp"
              ]
            , buildRlWorkloadEffects
                Cluster
                LinuxCUDA
                (RlStop (StopRLRun "rl-exp" False))
            )
          ]
    , testCase "all five inference command forms retain their correct effect" $ do
        traverse_
          assertInferenceCommandEffect
          [
            ( Inference.RunInference inferenceRequest
            , "RunInference"
            )
          ,
            ( Inference.CompareCheckpoints compareCommand
            , "CompareInferenceCheckpoints"
            )
          ,
            ( Inference.SelectAdversarialMove adversarialCommand
            , "RunAdversarialMove"
            )
          ,
            ( Inference.ListCheckpoints listCommand
            , "ListInferenceCheckpoints"
            )
          ,
            ( Inference.LoadTranscript transcriptCommand
            , "LoadInferenceTranscript"
            )
          ]
    , testCase "indexed effects only accept their legal result constructors" $ do
        let indexedPairs =
              [ renderIndexedPair
                  (WriteCheckpointBlob checkpointRef (ByteString.pack [0, 1, 255]))
                  (CheckpointBlobWritten (ETag "etag-blob"))
              , renderIndexedPair
                  (UpdateCheckpointPointer checkpointRef Nothing "pointer")
                  (CheckpointPointerUpdated (ETag "etag-pointer"))
              , renderIndexedPair
                  (PromoteWorkloadImage (ImageRef "jitml:build") (ImageRef "jitml:ready"))
                  (WorkloadImagePromoted (ImageRef "jitml:ready"))
              , renderIndexedPair
                  (ApplyWorkloadResource (KubeResource "job/demo") "kind: Job\n")
                  WorkloadResourceApplied
              , renderIndexedPair
                  (ReadWorkloadResourceStatus (KubeResource "job/demo"))
                  (WorkloadResourceStatus "Complete")
              , renderIndexedPair
                  (DeleteWorkloadResource (KubeResource "job/demo"))
                  WorkloadResourceDeleted
              ]
        length indexedPairs @?= 6
        assertBool "every indexed pair renders its legal result" (all (Text.isInfixOf " => ") indexedPairs)
        case buildInferenceWorkloadEffectsForTopic linuxInferenceTopic (Inference.RunInference inferenceRequest) of
          Left err -> assertFailure (show err)
          Right effects ->
            case NonEmpty.head effects of
              SomeWorkloadEffect effect@(RunInference _ _) ->
                assertBool
                  "indexed inference result did not render"
                  ( "inference-result-published message-1"
                      `Text.isInfixOf` renderIndexedPair effect (InferenceResultPublished "message-1")
                  )
              other -> assertFailure ("unexpected inference effect: " <> show other)
    , testCase "placement carries the complete cluster resource and manifest" $
        case planWorkloadPlacement Cluster (trainingLaunch trainingStart) of
          Left err -> assertFailure (show err)
          Right (WorkloadHostCommand _) -> assertFailure "Linux CPU launch was placed on the host"
          Right (WorkloadClusterJob spec) -> do
            clusterJobResource spec @?= KubeResource "job/jitml-train-training-exp"
            assertBool
              "cluster placement retained the rendered Job manifest"
              ("kind: Job" `Text.isInfixOf` clusterJobManifest spec)
            assertBool
              "cluster placement retained its typed RunConfig"
              ("RunConfig.dhall" `Text.isInfixOf` clusterJobManifest spec)
    , testCase "placement carries a typed host topic and typed command payload" $
        case planWorkloadPlacement Cluster (trainingLaunch appleTrainingStart) of
          Left err -> assertFailure (show err)
          Right (WorkloadClusterJob _) -> assertFailure "Apple Silicon launch was placed in cluster"
          Right (WorkloadHostCommand spec) -> do
            hostCommandSpecTopicName spec
              @?= "persistent://public/default/training.host-command.apple-silicon"
            hostCommandSpecPayload spec
              @?= renderTrainingCommand (TrainingStart appleTrainingStart)
            assertRoundTrip (SomeWorkloadEffect (PublishHostWorkloadCommand spec))
    , testCase "effect payload decoding rejects missing, duplicate, and raw inference effects" $ do
        assertDecodeFailure "kind: WorkloadEffect\neffect: ApplyWorkloadResource\n"
        assertDecodeFailure
          "kind: WorkloadEffect\neffect: DeleteWorkloadResource\nresource: job/a\nresource: job/b\n"
        case buildInferenceWorkloadEffectsForTopic
          linuxInferenceTopic
          (Inference.CompareCheckpoints compareCommand) of
          Left err -> assertFailure (show err)
          Right effects ->
            case NonEmpty.head effects of
              SomeWorkloadEffect effect ->
                parseWorkloadEffectPayload (renderWorkloadEffectPayload effect)
                  @?= inferenceEffectRequiresTypedInputTopic
    , testCase "all typed inference effects reject raw reconstruction" $
        traverse_
          assertInferenceCannotRoundTrip
          [ Inference.RunInference inferenceRequest
          , Inference.CompareCheckpoints compareCommand
          , Inference.SelectAdversarialMove adversarialCommand
          , Inference.ListCheckpoints listCommand
          , Inference.LoadTranscript transcriptCommand
          ]
    , testCase "typed input topic rejects a valid reply topic from another substrate" $ do
        let crossLane =
              inferenceRequest
                { Inference.irReplyTopic = "inference.result.linux-cuda"
                }
        case buildInferenceWorkloadEffectsForTopic linuxInferenceTopic (Inference.RunInference crossLane) of
          Left (WorkloadTopologyError _) -> pure ()
          Left err -> assertFailure ("unexpected decode error: " <> show err)
          Right effects -> assertFailure ("cross-lane command produced effects: " <> show effects)
        case buildInferenceWorkloadEffectsForTopic linuxInferenceTopic (Inference.RunInference inferenceRequest) of
          Left err -> assertFailure (show err)
          Right effects ->
            case NonEmpty.head effects of
              SomeWorkloadEffect (RunInference target _) -> do
                inferenceResultTargetSubstrate target @?= LinuxCPU
                inferenceResultTargetTopicName target
                  @?= "persistent://public/default/inference.result.linux-cpu"
              other -> assertFailure ("unexpected inference effect: " <> show other)
    , testCase "typed command builders reject payload substrates from another lane" $ do
        buildTrainingWorkloadEffects
          Cluster
          LinuxCUDA
          (TrainingStart trainingStart)
          @?= Left (WorkloadCommandSubstrateMismatch LinuxCUDA LinuxCPU)
        buildTuneWorkloadEffects
          Cluster
          AppleSilicon
          (TuneStart tuneStart)
          @?= Left (WorkloadCommandSubstrateMismatch AppleSilicon LinuxCPU)
        buildRlWorkloadEffects
          Cluster
          LinuxCUDA
          (RlStart rlStart)
          @?= Left (WorkloadCommandSubstrateMismatch LinuxCUDA LinuxCPU)
    ]

assertNonEmptyEffects
  :: Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
  -> Assertion
assertNonEmptyEffects result =
  case result of
    Left err -> assertFailure (show err)
    Right effects ->
      assertBool "typed workload program was empty" (not (null effects))

assertRenderedEffects
  :: [Text]
  -> Either WorkloadDecodeError (NonEmpty SomeWorkloadEffect)
  -> Assertion
assertRenderedEffects expected result =
  case result of
    Left err -> assertFailure (show err)
    Right effects ->
      fmap renderSomeWorkloadEffect (NonEmpty.toList effects) @?= expected

assertInferenceCommandEffect :: (Inference.InferenceCommand, Text) -> Assertion
assertInferenceCommandEffect (command, expected) =
  case buildInferenceWorkloadEffectsForTopic linuxInferenceTopic command of
    Left err -> assertFailure (show err)
    Right effects ->
      inferenceEffectConstructor (NonEmpty.head effects) @?= expected

inferenceEffectConstructor :: SomeWorkloadEffect -> Text
inferenceEffectConstructor (SomeWorkloadEffect effect) =
  case effect of
    RunInference {} -> "RunInference"
    CompareInferenceCheckpoints {} -> "CompareInferenceCheckpoints"
    RunAdversarialMove {} -> "RunAdversarialMove"
    ListInferenceCheckpoints {} -> "ListInferenceCheckpoints"
    LoadInferenceTranscript {} -> "LoadInferenceTranscript"
    _ -> "not-an-inference-effect"

renderIndexedPair
  :: WorkloadEffect kind
  -> WorkloadEffectResult kind
  -> Text
renderIndexedPair effect result =
  renderWorkloadEffect effect <> " => " <> renderWorkloadEffectResult result

assertRoundTrip :: SomeWorkloadEffect -> Assertion
assertRoundTrip expected@(SomeWorkloadEffect effect) =
  parseWorkloadEffectPayload (renderWorkloadEffectPayload effect) @?= Right expected

assertInferenceCannotRoundTrip :: Inference.InferenceCommand -> Assertion
assertInferenceCannotRoundTrip command =
  case buildInferenceWorkloadEffectsForTopic linuxInferenceTopic command of
    Left err -> assertFailure (show err)
    Right effects ->
      case NonEmpty.head effects of
        SomeWorkloadEffect effect ->
          parseWorkloadEffectPayload (renderWorkloadEffectPayload effect)
            @?= inferenceEffectRequiresTypedInputTopic

inferenceEffectRequiresTypedInputTopic
  :: Either WorkloadDecodeError SomeWorkloadEffect
inferenceEffectRequiresTypedInputTopic =
  Left
    ( InvalidWorkloadEffectPayload
        "inference effects require a typed input topic"
    )

assertDecodeFailure :: Text -> Assertion
assertDecodeFailure payload =
  case parseWorkloadEffectPayload payload of
    Left _ -> pure ()
    Right effect -> assertFailure ("unexpectedly decoded: " <> show effect)

checkpointRef :: ObjectRef
checkpointRef =
  ObjectRef
    (BucketName "jitml-checkpoints")
    (ObjectKey "experiments/demo/blob")

trainingStart :: StartTraining
trainingStart = preparedStartTraining (rawTrainingStart LinuxCPU)

appleTrainingStart :: StartTraining
appleTrainingStart = preparedStartTraining (rawTrainingStart AppleSilicon)

rawTrainingStart :: Substrate -> StartTraining
rawTrainingStart substrate =
  StartTraining
    { stExperimentHash = "training-exp"
    , stDhallObjectKey = "experiments/training.dhall"
    , stSubstrate = substrate
    , stSeed = 7
    , stEpochs = 3
    , stBatchSize = 16
    , stPlanId = ""
    , stResolvedPlan = ""
    , stTrainingExamples = 64
    , stEvaluationExamples = 16
    }

preparedStartTraining :: StartTraining -> StartTraining
preparedStartTraining raw =
  case prepareStartTraining raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartTraining test fixture: " <> Text.unpack message)

trainingLaunch :: StartTraining -> WorkloadLaunch
trainingLaunch start =
  case validateStartTraining start of
    Right plan -> ResolvedTrainingLaunch start plan
    Left message -> error ("invalid StartTraining launch fixture: " <> Text.unpack message)

tuneStart :: StartSweep
tuneStart =
  preparedStartSweep
    StartSweep
      { ssExperimentHash = "tune-exp"
      , ssDhallObjectKey = "experiments/tune.dhall"
      , ssSubstrate = LinuxCPU
      , ssSweepSeed = 8
      , ssTrialBudget = 4
      , ssBudgetPerTrial = 2
      , ssSampler = "tpe"
      , ssScheduler = "asha"
      , ssPruner = "median"
      , ssParallelism = 1
      , ssPromotions = 1
      , ssPlanId = ""
      , ssResolvedPlan = ""
      }

preparedStartSweep :: StartSweep -> StartSweep
preparedStartSweep raw =
  case prepareStartSweep raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartSweep test fixture: " <> Text.unpack message)

rlStart :: StartRLRun
rlStart =
  StartRLRun
    { srlExperimentHash = "rl-exp"
    , srlAlgorithm = "PPO"
    , srlEnvironment = "cartpole"
    , srlSubstrate = LinuxCPU
    , srlSeed = 9
    , srlMaxSteps = 100
    , srlEvalEpisodes = 2
    }

inferenceRequest :: Inference.InferenceRequest
inferenceRequest =
  Inference.InferenceRequest
    { Inference.irCallId = "call-run"
    , Inference.irExperimentHash = "inference-exp"
    , Inference.irReplyTopic = "inference.result.linux-cpu"
    , Inference.irInput = [1.0, 2.0]
    }

compareCommand :: Inference.CheckpointCompareCommand
compareCommand =
  Inference.CheckpointCompareCommand
    { Inference.cccCallId = "call-compare"
    , Inference.cccBaselineExperimentHash = "baseline-exp"
    , Inference.cccCandidateExperimentHash = "candidate-exp"
    , Inference.cccReplyTopic = "inference.result.linux-cpu"
    , Inference.cccInput = [3.0]
    }

adversarialCommand :: Inference.AdversarialMoveCommand
adversarialCommand =
  Inference.AdversarialMoveCommand
    { Inference.amcCallId = "call-adversarial"
    , Inference.amcGame = "connect4"
    , Inference.amcExperimentHash = "policy-exp"
    , Inference.amcReplyTopic = "inference.result.linux-cpu"
    , Inference.amcMoves = [0, 1]
    , Inference.amcHumanIsPlayer = 1
    , Inference.amcSimulationsPerMove = 32
    , Inference.amcInput = [0.0]
    }

listCommand :: Inference.ListCheckpointsCommand
listCommand =
  Inference.ListCheckpointsCommand
    { Inference.lccCallId = "call-list"
    , Inference.lccReplyTopic = "inference.result.linux-cpu"
    }

transcriptCommand :: Inference.LoadTranscriptCommand
transcriptCommand =
  Inference.LoadTranscriptCommand
    { Inference.ltcCallId = "call-transcript"
    , Inference.ltcTranscriptId = "transcript-1"
    , Inference.ltcReplyTopic = "inference.result.linux-cpu"
    }

linuxInferenceTopic :: Topic Inference.InferenceCommand
linuxInferenceTopic =
  case topicFor InferenceRequestRoute LinuxCPU of
    Left err -> error (show err)
    Right topic -> topic
