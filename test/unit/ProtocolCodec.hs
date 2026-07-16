{-# LANGUAGE OverloadedStrings #-}

module ProtocolCodec
  ( protocolCodecTests
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase, (@?=))

import JitML.Coordinator.Topology qualified as Topology
import JitML.Plan.Command qualified as PlanCommand
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Proto.Gc qualified as Gc
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Proto.Wire qualified as Wire
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget

protocolCodecTests :: TestTree
protocolCodecTests =
  testGroup
    "ProtocolCodec"
    [ testCase "Training commands require one exact, well-formed field set" $ do
        let start = Training.TrainingStart trainingStart
            stop =
              Training.TrainingStop
                Training.StopTraining
                  { Training.stopExperimentHash = "training-exp"
                  , Training.stopDrain = True
                  }
            rendered = Training.renderTrainingCommand start
        Training.parseTrainingCommand rendered @?= Just start
        Training.parseTrainingCommand (Training.renderTrainingCommand stop) @?= Just stop
        assertRejected "Training malformed line" Training.parseTrainingCommand (rendered <> "not-a-field\n")
        assertRejected "Training duplicate field" Training.parseTrainingCommand (rendered <> "seed: 99\n")
        assertRejected
          "Training unknown field"
          Training.parseTrainingCommand
          (rendered <> "surprise: value\n")
        assertRejected
          "Training missing field"
          Training.parseTrainingCommand
          (removeField "batch-size" rendered)
        assertRejected
          "Training invalid numeric field"
          Training.parseTrainingCommand
          (replaceField "seed" "not-a-word" rendered)
        assertRejected
          "Training empty identity"
          Training.parseTrainingCommand
          (replaceField "experiment-hash" "" rendered)
        assertRejected
          "Training missing canonical plan"
          Training.parseTrainingCommand
          (removeField "resolved-plan" rendered)
        assertRejected
          "Training zero evaluation examples"
          Training.parseTrainingCommand
          (replaceField "evaluation-examples" "0" rendered)
        Training.decodeTrainingCommandProto (Training.encodeTrainingCommandProto start)
          @?= Right start
        assertDecodeRejected
          "Training protobuf missing plan transport"
          Training.decodeTrainingCommandProto
          (trainingCommandProto (filter ((/= 8) . Wire.protoFieldNumber) trainingProtoFields))
    , testCase "Tune commands require one exact, well-formed field set" $ do
        let start = Tune.TuneStart tuneStart
            stop = Tune.TuneStop (Tune.StopSweep "tune-exp")
            rendered = Tune.renderTuneCommand start
        Tune.parseTuneCommand rendered @?= Just start
        Tune.parseTuneCommand (Tune.renderTuneCommand stop) @?= Just stop
        assertRejected "Tune malformed line" Tune.parseTuneCommand (rendered <> "not-a-field\n")
        assertRejected "Tune duplicate field" Tune.parseTuneCommand (rendered <> "sampler: Random\n")
        assertRejected "Tune unknown field" Tune.parseTuneCommand (rendered <> "surprise: value\n")
        assertRejected "Tune missing field" Tune.parseTuneCommand (removeField "pruner" rendered)
        assertRejected
          "Tune invalid numeric field"
          Tune.parseTuneCommand
          (replaceField "trial-budget" "many" rendered)
        assertRejected "Tune empty scalar" Tune.parseTuneCommand (replaceField "sampler" "" rendered)
    , testCase "RL commands require one exact, well-formed field set" $ do
        let start = Rl.RlStart rlStart
            alphaZero = Rl.RlStartAlphaZero alphaZeroStart
            stop =
              Rl.RlStop
                Rl.StopRLRun
                  { Rl.srStopExperimentHash = "rl-exp"
                  , Rl.srStopDrain = False
                  }
            rendered = Rl.renderRlCommand start
            renderedAlphaZero = Rl.renderRlCommand alphaZero
        Rl.parseRlCommand rendered @?= Just start
        Rl.parseRlCommand renderedAlphaZero @?= Just alphaZero
        Rl.parseRlCommand (Rl.renderRlCommand stop) @?= Just stop
        Rl.decodeRlCommandProto (Rl.encodeRlCommandProto start) @?= Right start
        Rl.decodeRlCommandProto (Rl.encodeRlCommandProto stop) @?= Right stop
        Rl.decodeRlCommandProto (Rl.encodeRlCommandProto alphaZero) @?= Right alphaZero
        assertRejected "RL malformed line" Rl.parseRlCommand (rendered <> "not-a-field\n")
        assertRejected "RL duplicate field" Rl.parseRlCommand (rendered <> "algorithm: DQN\n")
        assertRejected "RL unknown field" Rl.parseRlCommand (rendered <> "surprise: value\n")
        assertRejected "RL missing field" Rl.parseRlCommand (removeField "environment" rendered)
        assertRejected
          "RL invalid numeric field"
          Rl.parseRlCommand
          (replaceField "max-steps" "forever" rendered)
        assertRejected "RL empty scalar" Rl.parseRlCommand (replaceField "algorithm" "" rendered)
        assertRejected
          "AlphaZero duplicate field"
          Rl.parseRlCommand
          (renderedAlphaZero <> "arena-games: 8\n")
        assertRejected
          "AlphaZero unknown field"
          Rl.parseRlCommand
          (renderedAlphaZero <> "surprise: value\n")
        assertRejected
          "AlphaZero missing field"
          Rl.parseRlCommand
          (removeField "optimizer-updates" renderedAlphaZero)
        assertRejected
          "AlphaZero invalid numeric field"
          Rl.parseRlCommand
          (replaceField "mcts-simulations-per-move" "many" renderedAlphaZero)
        assertRejected
          "AlphaZero empty game"
          Rl.parseRlCommand
          (replaceField "game" "" renderedAlphaZero)
        assertRejected
          "AlphaZero empty plan id"
          Rl.parseRlCommand
          (replaceField "plan-id" "" renderedAlphaZero)
        assertRejected
          "AlphaZero empty resolved plan"
          Rl.parseRlCommand
          (replaceField "resolved-plan" "" renderedAlphaZero)
        assertDecodeRejected
          "AlphaZero proto unknown field"
          Rl.decodeRlCommandProto
          (alphaZeroCommandProto (alphaZeroProtoFields <> [Wire.stringField 99 "unknown"]))
        assertDecodeRejected
          "AlphaZero proto duplicate field"
          Rl.decodeRlCommandProto
          (alphaZeroCommandProto (alphaZeroProtoFields <> [Wire.stringField 5 "hex"]))
        assertDecodeRejected
          "AlphaZero proto missing field"
          Rl.decodeRlCommandProto
          (alphaZeroCommandProto (take 11 alphaZeroProtoFields))
        assertDecodeRejected
          "AlphaZero proto empty plan id"
          Rl.decodeRlCommandProto
          ( alphaZeroCommandProto
              (take 2 alphaZeroProtoFields <> [Wire.stringField 3 ""] <> drop 3 alphaZeroProtoFields)
          )
    , testCase "AlphaZero plan-correlated events have strict finite codecs" $ do
        let generation =
              Rl.RlGenerationCompleted
                Rl.GenerationCompleted
                  { Rl.gcPlanId = "plan-alpha-zero"
                  , Rl.gcExperimentHash = "alpha-zero-exp"
                  , Rl.gcGeneration = 2
                  , Rl.gcSelfPlayGames = 16
                  , Rl.gcSamples = 1024
                  }
            arena =
              Rl.RlArenaCompleted
                Rl.ArenaCompleted
                  { Rl.acPlanId = "plan-alpha-zero"
                  , Rl.acExperimentHash = "alpha-zero-exp"
                  , Rl.acArenaGames = 20
                  , Rl.acWinRate = 0.65
                  }
            renderedGeneration = Rl.renderRlEvent generation
            renderedArena = Rl.renderRlEvent arena
            nonFiniteArena =
              Rl.RlArenaCompleted
                Rl.ArenaCompleted
                  { Rl.acPlanId = "plan-alpha-zero"
                  , Rl.acExperimentHash = "alpha-zero-exp"
                  , Rl.acArenaGames = 20
                  , Rl.acWinRate = 0 / 0
                  }
        Rl.parseRlEvent renderedGeneration @?= Just generation
        Rl.parseRlEvent renderedArena @?= Just arena
        Rl.decodeRlEventProto (Rl.encodeRlEventProto generation) @?= Right generation
        Rl.decodeRlEventProto (Rl.encodeRlEventProto arena) @?= Right arena
        assertRejected
          "Generation duplicate field"
          Rl.parseRlEvent
          (renderedGeneration <> "samples: 2048\n")
        assertRejected
          "Generation unknown field"
          Rl.parseRlEvent
          (renderedGeneration <> "surprise: value\n")
        assertRejected
          "Generation missing field"
          Rl.parseRlEvent
          (removeField "plan-id" renderedGeneration)
        assertRejected
          "Arena non-finite text win rate"
          Rl.parseRlEvent
          (replaceField "win-rate" "NaN" renderedArena)
        assertDecodeRejected
          "Arena non-finite proto win rate"
          Rl.decodeRlEventProto
          (Rl.encodeRlEventProto nonFiniteArena)
        assertDecodeRejected
          "Generation proto unknown field"
          Rl.decodeRlEventProto
          ( generationEventProto
              (generationProtoFields <> [Wire.stringField 99 "unknown"])
          )
        assertDecodeRejected
          "Generation proto duplicate field"
          Rl.decodeRlEventProto
          (generationEventProto (generationProtoFields <> [Wire.uint32Field 3 4]))
        assertDecodeRejected
          "Arena proto missing field"
          Rl.decodeRlEventProto
          (arenaEventProto (take 3 arenaProtoFields))
    , testCase "candidate and completed checkpoint terminals are distinct closed variants" $ do
        let trainingCandidate = Training.TrainingCheckpoint trainingCheckpoint
            trainingCompleted =
              Training.TrainingCompletedCheckpoint
                ( expectRightFixture
                    "completed training checkpoint"
                    ( Training.completeCheckpointDone
                        trainingCheckpoint
                        supervisedCompletion
                    )
                )
            rlCandidate = Rl.RlCheckpoint rlCheckpoint
            rlCompleted =
              Rl.RlCompletedCheckpoint
                ( expectRightFixture
                    "completed RL checkpoint"
                    (Rl.completeCheckpointDoneRL rlCheckpoint rlCompletion)
                )
            tuneFinished = Tune.TuneSweepFinished sweepFinished
            tuneCompleted =
              Tune.TuneSweepCompleted
                ( expectRightFixture
                    "completed tuning sweep"
                    (Tune.completeSweep sweepFinished tuningCompletion)
                )
            trainingEvents = [trainingCandidate, trainingCompleted]
            rlEvents = [rlCandidate, rlCompleted]
            tuneEvents = [tuneFinished, tuneCompleted]
        mapM_
          (\event -> Training.parseTrainingEvent (Training.renderTrainingEvent event) @?= Just event)
          trainingEvents
        mapM_
          ( \event -> Training.decodeTrainingEventProto (Training.encodeTrainingEventProto event) @?= Right event
          )
          trainingEvents
        mapM_
          (\event -> Rl.parseRlEvent (Rl.renderRlEvent event) @?= Just event)
          rlEvents
        mapM_
          (\event -> Rl.decodeRlEventProto (Rl.encodeRlEventProto event) @?= Right event)
          rlEvents
        mapM_
          (\event -> Tune.parseTuneEvent (Tune.renderTuneEvent event) @?= Just event)
          tuneEvents
        mapM_
          (\event -> Tune.decodeTuneEventProto (Tune.encodeTuneEventProto event) @?= Right event)
          tuneEvents
        assertRefinementRejected
          "training checkpoint/completion step mismatch"
          ( Training.completeCheckpointDone
              (trainingCheckpoint {Training.cdStep = Training.cdStep trainingCheckpoint + 1})
              supervisedCompletion
          )
        assertRefinementRejected
          "RL checkpoint/completion step mismatch"
          ( Rl.completeCheckpointDoneRL
              (rlCheckpoint {Rl.cdrlStep = Rl.cdrlStep rlCheckpoint + 1})
              rlCompletion
          )
        assertRefinementRejected
          "tuning sweep/completion plan mismatch"
          ( Tune.completeSweep
              (sweepFinished {Tune.sfPlanId = Text.replicate 64 "b"})
              tuningCompletion
          )
        assertRefinementRejected
          "tuning sweep/completion budget-kind mismatch"
          (Tune.completeSweep sweepFinished supervisedCompletion)
        assertRefinementRejected
          "tuning sweep/completion trial mismatch"
          ( Tune.completeSweep
              (sweepFinished {Tune.sfTrialsCompleted = Tune.sfTrialsCompleted sweepFinished + 1})
              tuningCompletion
          )
    , testCase "completion event decode re-refines malformed, non-finite, incomplete, and forged raw DTOs" $ do
        let incomplete =
              rawSupervisedCompletion
                { TrainingBudget.rawCompletedTrainingObservedUnits = 2
                }
            forgedPass =
              rawSupervisedCompletion
                { TrainingBudget.rawCompletedTrainingMeasurements =
                    [ TrainingBudget.RawConvergenceObservation
                        { TrainingBudget.rawCriterionName = "accuracy"
                        , TrainingBudget.rawCriterionRule = TrainingBudget.RawCriterionAtLeast
                        , TrainingBudget.rawCriterionThreshold = 0.8
                        , TrainingBudget.rawMeasurementValue = 0.2
                        }
                    ]
                }
            nonFiniteMeasurement =
              rawSupervisedCompletion
                { TrainingBudget.rawCompletedTrainingMeasurements =
                    [ TrainingBudget.RawConvergenceObservation
                        { TrainingBudget.rawCriterionName = "accuracy"
                        , TrainingBudget.rawCriterionRule = TrainingBudget.RawCriterionAtLeast
                        , TrainingBudget.rawCriterionThreshold = 0.8
                        , TrainingBudget.rawMeasurementValue = 0 / 0
                        }
                    ]
                }
            unitMismatch =
              rawSupervisedCompletion
                { TrainingBudget.rawCompletedTrainingObservedUnitLabel = "trials"
                }
            missingCriterion =
              rawSupervisedCompletion
                { TrainingBudget.rawCompletedTrainingMeasurements = []
                }
            nonFiniteCandidate =
              trainingCheckpoint
                { Training.cdMetricsAtStep = [("accuracy", 0 / 0)]
                }
        assertDecodeRejected
          "malformed completion DTO"
          Training.decodeTrainingEventProto
          (trainingCompletedEventProto "not-cbor")
        assertDecodeRejected
          "malformed RL completion DTO"
          Rl.decodeRlEventProto
          (rlCompletedEventProto "not-cbor")
        assertDecodeRejected
          "malformed tuning completion DTO"
          Tune.decodeTuneEventProto
          (tuneCompletedEventProto "not-cbor")
        assertDecodeRejected
          "incomplete completion DTO"
          Training.decodeTrainingEventProto
          ( trainingCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining incomplete)
          )
        assertDecodeRejected
          "forged passing completion DTO"
          Training.decodeTrainingEventProto
          ( trainingCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining forgedPass)
          )
        assertDecodeRejected
          "non-finite completion measurement"
          Training.decodeTrainingEventProto
          ( trainingCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining nonFiniteMeasurement)
          )
        assertDecodeRejected
          "completion budget-unit mismatch"
          Training.decodeTrainingEventProto
          ( trainingCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining unitMismatch)
          )
        assertDecodeRejected
          "completion missing measured criterion"
          Training.decodeTrainingEventProto
          ( trainingCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining missingCriterion)
          )
        assertDecodeRejected
          "RL rejects incomplete completion DTO"
          Rl.decodeRlEventProto
          ( rlCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining incomplete)
          )
        assertDecodeRejected
          "tuning rejects forged passing completion DTO"
          Tune.decodeTuneEventProto
          ( tuneCompletedEventProto
              (TrainingBudget.encodeRawCompletedTraining forgedPass)
          )
        assertDecodeRejected
          "non-finite candidate metric"
          Training.decodeTrainingEventProto
          (Training.encodeTrainingEventProto (Training.TrainingCheckpoint nonFiniteCandidate))
        assertRejected
          "unsupported checkpoint text version"
          Training.parseTrainingEvent
          ( replaceField
              "protocol-version"
              "2"
              (Training.renderTrainingEvent (Training.TrainingCheckpoint trainingCheckpoint))
          )
    , testCase "topology rejects cross-lane Training, Tune, RL, and GC payloads" $ do
        assertRouteAccepts
          Topology.TrainingCommandRoute
          LinuxCPU
          (trainingCommandFor LinuxCPU)
        assertRouteRejects
          Topology.TrainingCommandRoute
          LinuxCPU
          (trainingCommandFor LinuxCUDA)
        assertRouteAccepts
          Topology.TrainingHostCommandRoute
          AppleSilicon
          (trainingCommandFor AppleSilicon)
        assertRouteRejects
          Topology.TrainingHostCommandRoute
          AppleSilicon
          (trainingCommandFor LinuxCPU)
        assertRouteAccepts Topology.TuneCommandRoute LinuxCPU (tuneCommandFor LinuxCPU)
        assertRouteRejects Topology.TuneCommandRoute LinuxCPU (tuneCommandFor LinuxCUDA)
        assertRouteAccepts
          Topology.TuneHostCommandRoute
          AppleSilicon
          (tuneCommandFor AppleSilicon)
        assertRouteRejects
          Topology.TuneHostCommandRoute
          AppleSilicon
          (tuneCommandFor LinuxCPU)
        assertRouteAccepts Topology.RlCommandRoute LinuxCPU (rlCommandFor LinuxCPU)
        assertRouteRejects Topology.RlCommandRoute LinuxCPU (rlCommandFor LinuxCUDA)
        assertRouteAccepts
          Topology.RlHostCommandRoute
          AppleSilicon
          (rlCommandFor AppleSilicon)
        assertRouteRejects
          Topology.RlHostCommandRoute
          AppleSilicon
          (rlCommandFor LinuxCPU)
        assertRouteAccepts Topology.GcEventRoute LinuxCPU (gcEventFor LinuxCPU)
        assertRouteRejects Topology.GcEventRoute LinuxCPU (gcEventFor LinuxCUDA)
    , testCase "every inference command variant rejects a cross-lane reply topic" $ do
        mapM_
          (assertRouteAccepts Topology.InferenceRequestRoute LinuxCPU)
          (inferenceCommandsForReply "inference.result.linux-cpu")
        mapM_
          (assertRouteRejects Topology.InferenceRequestRoute LinuxCPU)
          (inferenceCommandsForReply "inference.result.linux-cuda")
        mapM_
          (assertRouteAccepts Topology.InferenceHostCommandRoute AppleSilicon)
          (inferenceCommandsForReply "inference.result.apple-silicon")
        mapM_
          (assertRouteRejects Topology.InferenceHostCommandRoute AppleSilicon)
          (inferenceCommandsForReply "inference.result.linux-cpu")
    , testCase "all inference command variants round trip through the strict family decoder" $ do
        let commands =
              [ Inference.RunInference inferenceRequest
              , Inference.CompareCheckpoints compareCommand
              , Inference.SelectAdversarialMove adversarialCommand
              , Inference.ListCheckpoints listCommand
              , Inference.LoadTranscript transcriptCommand
              ]
        mapM_
          ( \command ->
              Inference.parseInferenceCommand (Inference.renderInferenceCommand command)
                @?= Just command
          )
          commands
        Inference.parseInferenceRequest (Inference.renderInferenceRequest inferenceRequest)
          @?= Just inferenceRequest
        Inference.parseCheckpointCompareCommand
          (Inference.renderCheckpointCompareCommand compareCommand)
          @?= Just compareCommand
        Inference.parseAdversarialMoveCommand
          (Inference.renderAdversarialMoveCommand adversarialCommand)
          @?= Just adversarialCommand
        Inference.parseListCheckpointsCommand
          (Inference.renderListCheckpointsCommand listCommand)
          @?= Just listCommand
        Inference.parseLoadTranscriptCommand
          (Inference.renderLoadTranscriptCommand transcriptCommand)
          @?= Just transcriptCommand
    , testCase "Inference commands reject malformed, duplicate, unknown, missing, and non-finite values" $ do
        let rendered = Inference.renderInferenceCommand (Inference.RunInference inferenceRequest)
            adversarial = Inference.renderInferenceCommand (Inference.SelectAdversarialMove adversarialCommand)
        assertRejected
          "Inference malformed line"
          Inference.parseInferenceCommand
          (rendered <> "not-a-field\n")
        assertRejected
          "Inference duplicate field"
          Inference.parseInferenceCommand
          (rendered <> "call-id: duplicate\n")
        assertRejected
          "Inference unknown field"
          Inference.parseInferenceCommand
          (rendered <> "surprise: value\n")
        assertRejected
          "Inference missing field"
          Inference.parseInferenceCommand
          (removeField "reply-topic" rendered)
        assertRejected
          "Inference non-finite input"
          Inference.parseInferenceCommand
          (replaceField "input" "NaN" rendered)
        assertRejected
          "Inference invalid integral field"
          Inference.parseInferenceCommand
          (replaceField "simulations-per-move" "many" adversarial)
        assertRejected
          "Inference empty call id"
          Inference.parseInferenceCommand
          (replaceField "call-id" "" rendered)
    , testCase "typed inference results accept every finite result form" $ do
        let base =
              Inference.renderInferenceResult
                Inference.InferenceResult
                  { Inference.iresCallId = "call-1"
                  , Inference.iresExperimentHash = "experiment-1"
                  , Inference.iresOutput = [0.25, -0.5]
                  }
            decodedResults =
              fmap
                (base <>)
                [ Text.unlines
                    [ "decoded-kind: classification"
                    , "decoded-top-class: 1"
                    , "decoded-confidence: 0.75"
                    , "decoded-probabilities: 0.25,0.75"
                    , "decoded-labels: zero,one"
                    ]
                , Text.unlines
                    [ "decoded-kind: regression"
                    , "decoded-values: 0.25,-0.5"
                    , "decoded-units: "
                    ]
                , Text.unlines
                    [ "decoded-kind: policy"
                    , "decoded-probabilities: 0.25,0.75"
                    , "decoded-labels: left,right"
                    ]
                , Text.unlines ["decoded-kind: value", "decoded-value: -0.25"]
                , Text.unlines ["decoded-kind: mcts", "decoded-visits: 0.25,0.75"]
                , Text.unlines ["decoded-kind: replay", "decoded-output: "]
                , Text.unlines ["decoded-kind: generic", "decoded-output: 0.25,-0.5"]
                ]
            comparison =
              Inference.renderCheckpointCompareResult
                Inference.CheckpointCompareResult
                  { Inference.ccrCallId = "call-2"
                  , Inference.ccrBaselineExperimentHash = "baseline"
                  , Inference.ccrCandidateExperimentHash = "candidate"
                  , Inference.ccrBaselineOutput = [0.1]
                  , Inference.ccrCandidateOutput = [0.2]
                  , Inference.ccrMaxAbsDelta = 0.1
                  , Inference.ccrMeanAbsDelta = 0.1
                  }
            move =
              Inference.renderAdversarialMoveResult
                Inference.AdversarialMoveResult
                  { Inference.amrCallId = "call-3"
                  , Inference.amrExperimentHash = "connect4"
                  , Inference.amrGame = "connect4"
                  , Inference.amrChosenColumn = 3
                  , Inference.amrLegalMoves = [0, 1, 2, 3]
                  , Inference.amrVisitCounts = [1, 2, 3, 4]
                  , Inference.amrPolicyPriors = [0.1, 0.2, 0.3, 0.4]
                  , Inference.amrValueEstimate = 0.5
                  , Inference.amrGameOver = False
                  , Inference.amrTranscriptId = "transcript-1"
                  }
            checkpointList =
              Text.unlines
                [ "kind: CheckpointList"
                , "call-id: call-4"
                , "panel: checkpoint-browse"
                , "status: published"
                , "count: 1"
                , "selector-state: ready"
                , "row-selector: row-1"
                , "checkpoint-summary: checkpoint-1"
                ]
            transcript =
              Text.unlines
                [ "kind: TranscriptReplay"
                , "call-id: call-5"
                , "panel: transcript-replay"
                , "transcript-id: transcript-1"
                , "game: connect4"
                , "experiment-hash: experiment-1"
                , "moves: 1,2,3"
                , "analysis: complete"
                ]
        mapM_
          assertResultAccepted
          ([base] <> decodedResults <> [comparison, move, checkpointList, transcript])
    , testCase "typed inference results reject malformed schemas and non-finite numbers" $ do
        let base =
              Text.unlines
                [ "kind: InferenceResult"
                , "call-id: call-1"
                , "experiment-hash: experiment-1"
                , "output: 0.25,-0.5"
                ]
            comparison =
              Text.unlines
                [ "kind: CheckpointCompareResult"
                , "call-id: call-2"
                , "baseline-experiment-hash: baseline"
                , "candidate-experiment-hash: candidate"
                , "baseline-output: 0.1"
                , "candidate-output: 0.2"
                , "max-abs-delta: 0.1"
                , "mean-abs-delta: 0.1"
                ]
            checkpointList =
              Text.unlines
                [ "kind: CheckpointList"
                , "call-id: call-4"
                , "panel: checkpoint-browse"
                , "status: published"
                , "count: 1"
                , "selector-state: ready"
                ]
            transcript =
              Text.unlines
                [ "kind: TranscriptReplay"
                , "call-id: call-5"
                , "panel: transcript-replay"
                , "transcript-id: transcript-1"
                , "game: connect4"
                , "experiment-hash: experiment-1"
                , "moves: 1,not-an-int"
                , "analysis: complete"
                ]
        mapM_
          assertResultRejected
          [ base <> "unknown: value\n"
          , base <> "output: 0.5\n"
          , replaceField "output" "NaN" base
          , base
              <> Text.unlines
                [ "decoded-kind: value"
                , "decoded-value: Infinity"
                ]
          , replaceField "max-abs-delta" "NaN" comparison
          , checkpointList
          , transcript
          , "kind: InferenceResult\nnot-a-field\n"
          ]
    ]

trainingStart :: Training.StartTraining
trainingStart =
  expectPreparedStartTraining (rawTrainingStart LinuxCPU)

trainingCommandFor :: Substrate -> Training.TrainingCommand
trainingCommandFor substrate =
  Training.TrainingStart (expectPreparedStartTraining (rawTrainingStart substrate))

rawTrainingStart :: Substrate -> Training.StartTraining
rawTrainingStart substrate =
  Training.StartTraining
    { Training.stExperimentHash = "training-exp"
    , Training.stDhallObjectKey = "experiments/training.dhall"
    , Training.stSubstrate = substrate
    , Training.stSeed = 7
    , Training.stEpochs = 3
    , Training.stBatchSize = 16
    , Training.stPlanId = ""
    , Training.stResolvedPlan = ""
    , Training.stTrainingExamples = 48
    , Training.stEvaluationExamples = 16
    }

expectPreparedStartTraining :: Training.StartTraining -> Training.StartTraining
expectPreparedStartTraining raw =
  case PlanCommand.prepareStartTraining raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartTraining test fixture: " <> Text.unpack message)

trainingProtoFields :: [Wire.ProtoField]
trainingProtoFields =
  [ Wire.stringField 1 (Training.stExperimentHash trainingStart)
  , Wire.stringField 2 (Training.stDhallObjectKey trainingStart)
  , Wire.stringField 3 (renderSubstrate (Training.stSubstrate trainingStart))
  , Wire.uint64Field 4 (Training.stSeed trainingStart)
  , Wire.uint32Field 5 (Training.stEpochs trainingStart)
  , Wire.uint32Field 6 (Training.stBatchSize trainingStart)
  , Wire.stringField 7 (Training.stPlanId trainingStart)
  , Wire.stringField 8 (Training.stResolvedPlan trainingStart)
  , Wire.uint32Field 9 (Training.stTrainingExamples trainingStart)
  , Wire.uint32Field 10 (Training.stEvaluationExamples trainingStart)
  ]

trainingCommandProto :: [Wire.ProtoField] -> ByteString
trainingCommandProto fields =
  Wire.encodeMessage [Wire.messageField 1 (Wire.encodeMessage fields)]

trainingCheckpoint :: Training.CheckpointDone
trainingCheckpoint =
  Training.CheckpointDone
    { Training.cdExperimentHash = "training-exp"
    , Training.cdManifestSha = "manifest-training"
    , Training.cdStep = 3
    , Training.cdPointerKey = "checkpoints/training/latest"
    , Training.cdEpoch = 3
    , Training.cdTrialSha = Nothing
    , Training.cdRunUuid = "run-training"
    , Training.cdMetricsAtStep = [("accuracy", 0.9)]
    }

rlCheckpoint :: Rl.CheckpointDoneRL
rlCheckpoint =
  Rl.CheckpointDoneRL
    { Rl.cdrlExperimentHash = "rl-exp"
    , Rl.cdrlManifestSha = "manifest-rl"
    , Rl.cdrlStep = 100
    , Rl.cdrlPointerKey = "checkpoints/rl/latest"
    }

sweepFinished :: Tune.SweepFinished
sweepFinished =
  Tune.SweepFinished
    { Tune.sfExperimentHash = "tune-exp"
    , Tune.sfPlanId = Text.replicate 64 "a"
    , Tune.sfTrialsCompleted = 4
    , Tune.sfTrialsPruned = 1
    , Tune.sfTrialsPromoted = 1
    , Tune.sfBestObjective = 0.9
    }

supervisedCompletion :: TrainingBudget.CompletedTraining
supervisedCompletion =
  decodeCompletionFixture "supervised completion" rawSupervisedCompletion

rlCompletion :: TrainingBudget.CompletedTraining
rlCompletion =
  decodeCompletionFixture
    "RL completion"
    ( rawCompletion
        TrainingBudget.RlEnvironmentStepBudget
        "environment-steps"
        100
        "reward"
        0.5
        0.75
    )

tuningCompletion :: TrainingBudget.CompletedTraining
tuningCompletion =
  decodeCompletionFixture
    "tuning completion"
    ( rawCompletion
        TrainingBudget.TuningTrialBudget
        "trials"
        4
        "best_objective"
        0.8
        0.9
    )

rawSupervisedCompletion :: TrainingBudget.RawCompletedTraining
rawSupervisedCompletion =
  rawCompletion
    TrainingBudget.SupervisedEpochBudget
    "epochs"
    3
    "accuracy"
    0.8
    0.9

rawCompletion
  :: TrainingBudget.BudgetKind
  -> Text
  -> Word64
  -> Text
  -> Double
  -> Double
  -> TrainingBudget.RawCompletedTraining
rawCompletion budgetKind unitLabel target metric threshold measurement =
  TrainingBudget.RawCompletedTraining
    { TrainingBudget.rawCompletedTrainingVersion =
        TrainingBudget.completedTrainingWireVersion
    , TrainingBudget.rawCompletedTrainingPlanId = Text.replicate 64 "a"
    , TrainingBudget.rawCompletedTrainingBudget =
        TrainingBudget.RawTrainingBudget
          { TrainingBudget.rawTrainingBudgetKind = budgetKind
          , TrainingBudget.rawTrainingBudgetTargetUnits = target
          , TrainingBudget.rawTrainingBudgetSeed = Just 7
          }
    , TrainingBudget.rawCompletedTrainingObservedKind = budgetKind
    , TrainingBudget.rawCompletedTrainingObservedUnits = target
    , TrainingBudget.rawCompletedTrainingObservedUnitLabel = unitLabel
    , TrainingBudget.rawCompletedTrainingEvidence = trainingEvidence
    , TrainingBudget.rawCompletedTrainingMeasurements =
        [ TrainingBudget.RawConvergenceObservation
            { TrainingBudget.rawCriterionName = metric
            , TrainingBudget.rawCriterionRule = TrainingBudget.RawCriterionAtLeast
            , TrainingBudget.rawCriterionThreshold = threshold
            , TrainingBudget.rawMeasurementValue = measurement
            }
        ]
    , TrainingBudget.rawCompletedTrainingTensorBoard =
        TrainingBudget.TensorBoardRunMetadata
          { TrainingBudget.tbrRunId = "protocol-run"
          , TrainingBudget.tbrLogPrefix = "tensorboard/protocol-run"
          , TrainingBudget.tbrScalarTags = [metric]
          }
    }

trainingEvidence :: ProductEvidence.TrainingEvidence
trainingEvidence =
  expectRightFixture
    "training evidence"
    ( ProductEvidence.mkTrainingEvidence
        "initial-weights"
        "final-weights"
        3
        "dataset-at-read"
    )

decodeCompletionFixture
  :: Text
  -> TrainingBudget.RawCompletedTraining
  -> TrainingBudget.CompletedTraining
decodeCompletionFixture label raw =
  expectRightFixture
    label
    ( TrainingBudget.decodeCompletedTraining
        (TrainingBudget.encodeRawCompletedTraining raw)
    )

trainingCompletedEventProto :: ByteString -> ByteString
trainingCompletedEventProto completionBytes =
  let checkpointBytes =
        oneOfBody
          2
          (Training.encodeTrainingEventProto (Training.TrainingCheckpoint trainingCheckpoint))
      completedBody =
        Wire.encodeMessage
          [ Wire.uint32Field 1 1
          , Wire.messageField 2 checkpointBytes
          , Wire.messageField 3 completionBytes
          ]
   in Wire.encodeMessage [Wire.messageField 4 completedBody]

rlCompletedEventProto :: ByteString -> ByteString
rlCompletedEventProto completionBytes =
  let checkpointBytes =
        oneOfBody
          3
          (Rl.encodeRlEventProto (Rl.RlCheckpoint rlCheckpoint))
      completedBody =
        Wire.encodeMessage
          [ Wire.uint32Field 1 1
          , Wire.messageField 2 checkpointBytes
          , Wire.messageField 3 completionBytes
          ]
   in Wire.encodeMessage [Wire.messageField 9 completedBody]

tuneCompletedEventProto :: ByteString -> ByteString
tuneCompletedEventProto completionBytes =
  let finishedBytes =
        oneOfBody
          3
          (Tune.encodeTuneEventProto (Tune.TuneSweepFinished sweepFinished))
      completedBody =
        Wire.encodeMessage
          [ Wire.uint32Field 1 1
          , Wire.messageField 2 finishedBytes
          , Wire.messageField 3 completionBytes
          ]
   in Wire.encodeMessage [Wire.messageField 4 completedBody]

oneOfBody :: Word64 -> ByteString -> ByteString
oneOfBody expectedField encoded =
  case Wire.decodeMessage encoded of
    Right [Wire.ProtoField fieldNumber (Wire.LengthDelimited body)]
      | fieldNumber == expectedField -> body
    other -> error ("invalid oneof fixture: " <> show other)

expectRightFixture :: Text -> Either Text value -> value
expectRightFixture label result =
  case result of
    Right value -> value
    Left err -> error (Text.unpack label <> ": " <> Text.unpack err)

tuneStart :: Tune.StartSweep
tuneStart = preparedTuneStart LinuxCPU

preparedTuneStart :: Substrate -> Tune.StartSweep
preparedTuneStart substrate =
  expectPreparedStartSweep $
    Tune.StartSweep
      { Tune.ssExperimentHash = "tune-exp"
      , Tune.ssDhallObjectKey = "experiments/tune.dhall"
      , Tune.ssSubstrate = substrate
      , Tune.ssSweepSeed = 11
      , Tune.ssTrialBudget = 4
      , Tune.ssBudgetPerTrial = 2
      , Tune.ssSampler = "Sobol"
      , Tune.ssScheduler = "Fifo"
      , Tune.ssPruner = "NoPruner"
      , Tune.ssParallelism = 1
      , Tune.ssPromotions = 1
      , Tune.ssPlanId = ""
      , Tune.ssResolvedPlan = ""
      }

tuneCommandFor :: Substrate -> Tune.TuneCommand
tuneCommandFor substrate =
  Tune.TuneStart (preparedTuneStart substrate)

rlStart :: Rl.StartRLRun
rlStart =
  Rl.StartRLRun
    { Rl.srlExperimentHash = "rl-exp"
    , Rl.srlAlgorithm = "PPO"
    , Rl.srlEnvironment = "CartPole"
    , Rl.srlSubstrate = LinuxCPU
    , Rl.srlSeed = 13
    , Rl.srlMaxSteps = 100
    , Rl.srlEvalEpisodes = 3
    }

rlCommandFor :: Substrate -> Rl.RlCommand
rlCommandFor substrate =
  Rl.RlStart rlStart {Rl.srlSubstrate = substrate}

alphaZeroStart :: Rl.StartAlphaZeroRun
alphaZeroStart =
  expectPreparedStartAlphaZeroRun $
    Rl.StartAlphaZeroRun
      { Rl.sazSubstrate = LinuxCPU
      , Rl.sazExperimentHash = "alpha-zero-exp"
      , Rl.sazPlanId = ""
      , Rl.sazResolvedPlan = ""
      , Rl.sazGame = "hex"
      , Rl.sazGenerations = 3
      , Rl.sazSelfPlayGames = 16
      , Rl.sazMctsSimulationsPerMove = 64
      , Rl.sazMaxPlies = 128
      , Rl.sazOptimizerUpdates = 8
      , Rl.sazArenaGames = 20
      , Rl.sazSeed = 17
      }

expectPreparedStartSweep :: Tune.StartSweep -> Tune.StartSweep
expectPreparedStartSweep raw =
  case PlanCommand.prepareStartSweep raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartSweep test fixture: " <> Text.unpack message)

expectPreparedStartAlphaZeroRun :: Rl.StartAlphaZeroRun -> Rl.StartAlphaZeroRun
expectPreparedStartAlphaZeroRun raw =
  case PlanCommand.prepareStartAlphaZeroRun raw of
    Right (prepared, _) -> prepared
    Left message -> error ("invalid StartAlphaZeroRun test fixture: " <> Text.unpack message)

alphaZeroProtoFields :: [Wire.ProtoField]
alphaZeroProtoFields =
  [ Wire.stringField 1 (renderSubstrate (Rl.sazSubstrate alphaZeroStart))
  , Wire.stringField 2 (Rl.sazExperimentHash alphaZeroStart)
  , Wire.stringField 3 (Rl.sazPlanId alphaZeroStart)
  , Wire.stringField 4 (Rl.sazResolvedPlan alphaZeroStart)
  , Wire.stringField 5 (Rl.sazGame alphaZeroStart)
  , Wire.uint32Field 6 (Rl.sazGenerations alphaZeroStart)
  , Wire.uint32Field 7 (Rl.sazSelfPlayGames alphaZeroStart)
  , Wire.uint32Field 8 (Rl.sazMctsSimulationsPerMove alphaZeroStart)
  , Wire.uint32Field 9 (Rl.sazMaxPlies alphaZeroStart)
  , Wire.uint32Field 10 (Rl.sazOptimizerUpdates alphaZeroStart)
  , Wire.uint32Field 11 (Rl.sazArenaGames alphaZeroStart)
  , Wire.uint64Field 12 (Rl.sazSeed alphaZeroStart)
  ]

alphaZeroCommandProto :: [Wire.ProtoField] -> ByteString
alphaZeroCommandProto fields =
  Wire.encodeMessage [Wire.messageField 3 (Wire.encodeMessage fields)]

generationProtoFields :: [Wire.ProtoField]
generationProtoFields =
  [ Wire.stringField 1 "plan-alpha-zero"
  , Wire.stringField 2 "alpha-zero-exp"
  , Wire.uint32Field 3 2
  , Wire.uint32Field 4 16
  , Wire.uint64Field 5 1024
  ]

generationEventProto :: [Wire.ProtoField] -> ByteString
generationEventProto fields =
  Wire.encodeMessage [Wire.messageField 7 (Wire.encodeMessage fields)]

arenaProtoFields :: [Wire.ProtoField]
arenaProtoFields =
  [ Wire.stringField 1 "plan-alpha-zero"
  , Wire.stringField 2 "alpha-zero-exp"
  , Wire.uint32Field 3 20
  , Wire.doubleField 4 0.65
  ]

arenaEventProto :: [Wire.ProtoField] -> ByteString
arenaEventProto fields =
  Wire.encodeMessage [Wire.messageField 8 (Wire.encodeMessage fields)]

inferenceRequest :: Inference.InferenceRequest
inferenceRequest =
  Inference.InferenceRequest
    { Inference.irCallId = "call-inference"
    , Inference.irExperimentHash = "inference-exp"
    , Inference.irReplyTopic = "inference.result.linux-cpu"
    , Inference.irInput = [0.25, -0.5]
    }

compareCommand :: Inference.CheckpointCompareCommand
compareCommand =
  Inference.CheckpointCompareCommand
    { Inference.cccCallId = "call-compare"
    , Inference.cccBaselineExperimentHash = "baseline"
    , Inference.cccCandidateExperimentHash = "candidate"
    , Inference.cccReplyTopic = "inference.result.linux-cpu"
    , Inference.cccInput = [0.5]
    }

adversarialCommand :: Inference.AdversarialMoveCommand
adversarialCommand =
  Inference.AdversarialMoveCommand
    { Inference.amcCallId = "call-move"
    , Inference.amcGame = "connect4"
    , Inference.amcExperimentHash = "move-exp"
    , Inference.amcReplyTopic = "inference.result.linux-cpu"
    , Inference.amcMoves = [3, 2]
    , Inference.amcHumanIsPlayer = 1
    , Inference.amcSimulationsPerMove = 32
    , Inference.amcInput = []
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

inferenceCommandsForReply :: Text -> [Inference.InferenceCommand]
inferenceCommandsForReply replyTopic =
  [ Inference.RunInference inferenceRequest {Inference.irReplyTopic = replyTopic}
  , Inference.CompareCheckpoints compareCommand {Inference.cccReplyTopic = replyTopic}
  , Inference.SelectAdversarialMove adversarialCommand {Inference.amcReplyTopic = replyTopic}
  , Inference.ListCheckpoints listCommand {Inference.lccReplyTopic = replyTopic}
  , Inference.LoadTranscript transcriptCommand {Inference.ltcReplyTopic = replyTopic}
  ]

gcEventFor :: Substrate -> Gc.GcReapedEvent
gcEventFor substrate =
  Gc.GcReapedEvent
    { Gc.gcEventExperimentHash = "gc-exp"
    , Gc.gcEventManifestSha = "sha256:gc"
    , Gc.gcEventReapedBlobShas = ["blob-gc"]
    , Gc.gcEventStepAtReap = 17
    , Gc.gcEventSubstrate = substrate
    , Gc.gcEventTimestampNs = 23
    }

assertRouteAccepts
  :: (Eq event, Show event)
  => Topology.ProtocolRoute event
  -> Substrate
  -> event
  -> Assertion
assertRouteAccepts route substrate event =
  case Topology.topicFor route substrate of
    Left err -> assertFailure ("failed to resolve route: " <> show err)
    Right topic ->
      Topology.decodeTopicPayload topic (Topology.encodeTopicPayload topic event)
        @?= Right event

assertRouteRejects
  :: Topology.ProtocolRoute event
  -> Substrate
  -> event
  -> Assertion
assertRouteRejects route substrate event =
  case Topology.topicFor route substrate of
    Left err -> assertFailure ("failed to resolve route: " <> show err)
    Right topic ->
      case Topology.decodeTopicPayload topic (Topology.encodeTopicPayload topic event) of
        Left _ -> pure ()
        Right _ -> assertFailure "cross-lane payload unexpectedly passed its topic decoder"

assertRejected :: Text -> (Text -> Maybe value) -> Text -> Assertion
assertRejected label parser payload =
  case parser payload of
    Nothing -> pure ()
    Just _ -> assertFailure (Text.unpack label <> " was accepted")

assertDecodeRejected
  :: Text
  -> (ByteString -> Either Text value)
  -> ByteString
  -> Assertion
assertDecodeRejected label decoder payload =
  case decoder payload of
    Left _ -> pure ()
    Right _ -> assertFailure (Text.unpack label <> " was accepted")

assertRefinementRejected :: Text -> Either Text value -> Assertion
assertRefinementRejected label result =
  case result of
    Left _ -> pure ()
    Right _ -> assertFailure (Text.unpack label <> " was accepted")

assertResultAccepted :: Text -> Assertion
assertResultAccepted payload =
  case Topology.mkInferenceResultMessage payload of
    Right _ -> pure ()
    Left err -> assertFailure ("valid inference result was rejected: " <> Text.unpack err)

assertResultRejected :: Text -> Assertion
assertResultRejected payload =
  case Topology.mkInferenceResultMessage payload of
    Left _ -> pure ()
    Right _ -> assertFailure ("invalid inference result was accepted: " <> Text.unpack payload)

removeField :: Text -> Text -> Text
removeField key =
  Text.unlines . filter (not . Text.isPrefixOf (key <> ":")) . Text.lines

replaceField :: Text -> Text -> Text -> Text
replaceField key replacement =
  Text.unlines . fmap replace . Text.lines
 where
  replace line
    | Text.isPrefixOf (key <> ":") line = key <> ": " <> replacement
    | otherwise = line
