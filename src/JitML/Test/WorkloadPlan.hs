{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.WorkloadPlan
  ( workloadPlanTests
  )
where

import Data.Char (ord)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( PlanError (..)
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , Validation (..)
  , planIdText
  , quantityValue
  , refinePlanIdText
  )
import JitML.Plan.Workload
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Service.RunConfig qualified as RunConfig
import JitML.Substrate (Substrate (..))
import JitML.Tune.Catalog qualified as Catalog

workloadPlanTests :: TestTree
workloadPlanTests =
  testGroup
    "resolved workload plans (Sprints 9.17 / 10.12)"
    [ testCase "supervised transport is canonical, dimensioned, and re-refined" $ do
        (prepared, plan) <- expectPreparedSupervised validSupervisedCommand
        PlanCommand.validateStartTraining prepared @?= Right plan
        quantityValue (supervisedPlanEpochs plan) @?= 3
        quantityValue (supervisedPlanTrainingExamples plan) @?= 64
        quantityValue (supervisedPlanEvaluationExamples plan) @?= 16
        quantityValue (supervisedPlanBatchExamples plan) @?= 16
        quantityValue (supervisedPlanOptimizerUpdates plan) @?= 12
        let encoded = renderSupervisedPlanTransport plan
        assertSingleLineAscii encoded
        parseSupervisedPlanTransport encoded @?= Success plan
        refinePlanIdText (Training.stPlanId prepared) @?= Right (supervisedPlanId plan)
    , testCase "supervised command adapter rejects every forged transport boundary" $ do
        (prepared, _) <- expectPreparedSupervised validSupervisedCommand
        assertRejected
          "missing supervised transport"
          (PlanCommand.validateStartTraining prepared {Training.stResolvedPlan = ""})
        assertRejected
          "incompatible supervised transport version"
          ( PlanCommand.validateStartTraining
              prepared
                { Training.stResolvedPlan =
                    Text.replace
                      "transport-version=1"
                      "transport-version=2"
                      (Training.stResolvedPlan prepared)
                }
          )
        assertRejected
          "non-canonical supervised transport"
          ( PlanCommand.validateStartTraining
              prepared {Training.stResolvedPlan = reorderTransport (Training.stResolvedPlan prepared)}
          )
        assertRejected
          "mismatched supervised PlanId"
          (PlanCommand.validateStartTraining prepared {Training.stPlanId = Text.replicate 64 "0"})
        assertRejected
          "raw supervised budget differs from transported plan"
          ( PlanCommand.validateStartTraining
              prepared {Training.stTrainingExamples = Training.stTrainingExamples prepared + 1}
          )
        assertTransportFailure
          isDerivedQuantityMismatch
          ( parseSupervisedPlanTransport
              ( Text.replace
                  "optimizer-updates=12"
                  "optimizer-updates=13"
                  (Training.stResolvedPlan prepared)
              )
          )
    , testCase "TrainingRunConfig contains and re-refines only plan semantics" $ do
        (_, plan) <- expectPreparedSupervised validSupervisedCommand
        let config =
              RunConfig.TrainingRunConfig
                { RunConfig.trcPlanId = planIdText (supervisedPlanId plan)
                , RunConfig.trcResolvedPlan = renderSupervisedPlanTransport plan
                , RunConfig.trcPulsarWsUrl = "ws://pulsar.example/ws"
                }
        RunConfig.supervisedPlanFromRunConfig config @?= Right plan
        assertRejected
          "TrainingRunConfig PlanId mismatch"
          ( RunConfig.supervisedPlanFromRunConfig
              config {RunConfig.trcPlanId = Text.replicate 64 "f"}
          )
        assertRejected
          "TrainingRunConfig malformed transport"
          ( RunConfig.supervisedPlanFromRunConfig
              config {RunConfig.trcResolvedPlan = "not-a-plan"}
          )
    , testCase "tuning refinement accumulates base and closed-axis errors" $ do
        let invalid =
              RawTuningPlan
                { rawTuningRun =
                    (rawTuningRun validTuning)
                      { rawRunVersion = 0
                      , rawRunExperimentId = " "
                      , rawRunSubjectId = ""
                      , rawRunArtifactId = "\t"
                      , rawRunTopicId = ""
                      , rawRunPlacement = HostRun
                      , rawRunSeeds = []
                      , rawRunBudget = RawTuningBudget 0 0 0 0
                      }
                , rawTuningSampler = "unknown-sampler"
                , rawTuningScheduler = "unknown-scheduler"
                , rawTuningPruner = "unknown-pruner"
                }
        case resolveTuningPlan invalid of
          Success _ -> assertFailure "invalid tuning plan unexpectedly resolved"
          Failure errors -> do
            let allErrors = NonEmpty.toList errors
            length allErrors @?= 14
            assertBool
              "base version error retained"
              (CommonRunPlanError (UnsupportedRunPlanVersion 0) `elem` allErrors)
            assertBool
              "all tuning quantity failures retained"
              (length (filter isCommonNonPositive allErrors) == 4)
            assertBool
              "all closed-axis failures retained"
              ( length
                  ( filter
                      isUnknownTuningAxis
                      allErrors
                  )
                  == 3
              )
    , testCase "AlphaZero refinement accumulates unknown game and quantity errors" $ do
        let invalid =
              validAlphaZero
                { rawAlphaZeroRun =
                    (rawAlphaZeroRun validAlphaZero)
                      { rawRunBudget = RawAlphaZeroBudget 0 0 0 0 0 0
                      }
                , rawAlphaZeroGame = "chess"
                }
        case resolveAlphaZeroPlan invalid of
          Success _ -> assertFailure "invalid AlphaZero plan unexpectedly resolved"
          Failure errors -> do
            let allErrors = NonEmpty.toList errors
            length (filter isCommonNonPositive allErrors) @?= 6
            assertBool
              "unknown game retained"
              (UnknownAlphaZeroGame "chess" `elem` allErrors)
    , testCase "workload quantities reject values beyond Word64" $ do
        let tooLarge = toInteger (maxBound :: Word64) + 1
            invalidTuning =
              validTuning
                { rawTuningRun =
                    (rawTuningRun validTuning)
                      { rawRunBudget = RawTuningBudget tooLarge 2 1 100
                      }
                }
            invalidAlphaZero =
              validAlphaZero
                { rawAlphaZeroRun =
                    (rawAlphaZeroRun validAlphaZero)
                      { rawRunBudget = RawAlphaZeroBudget 1 2 tooLarge 42 4 8
                      }
                }
        assertPlanError
          (QuantityOutOfRange "trials" tooLarge)
          (resolveTuningPlan invalidTuning)
        assertPlanError
          (QuantityOutOfRange "mcts-simulations-per-move" tooLarge)
          (resolveAlphaZeroPlan invalidAlphaZero)
    , testCase "tuning parallelism and promotions cannot exceed trials" $ do
        let invalid =
              validTuning
                { rawTuningRun =
                    (rawTuningRun validTuning)
                      { rawRunBudget = RawTuningBudget 3 4 5 1
                      }
                }
        assertPlanError
          (QuantityExceeds "parallel-trials" 4 "trials" 3)
          (resolveTuningPlan invalid)
        assertPlanError
          (QuantityExceeds "promotions" 5 "trials" 3)
          (resolveTuningPlan invalid)
    , testCase "tuning PlanId is stable and every semantic field is sensitive" $ do
        baseline <- expectTuning validTuning
        normalized <-
          expectTuning
            validTuning
              { rawTuningRun =
                  (rawTuningRun validTuning)
                    { rawRunExperimentId = "  tune-exp "
                    , rawRunSeeds = [17, 11]
                    }
              , rawTuningSampler = " TPE "
              }
        tuningPlanId normalized @?= tuningPlanId baseline
        changed <- traverse expectTuning tuningMutations
        assertDistinctPlanIds
          (planIdText (tuningPlanId baseline))
          (fmap (planIdText . tuningPlanId) changed)
    , testCase "AlphaZero PlanId is stable and every semantic field is sensitive" $ do
        baseline <- expectAlphaZero validAlphaZero
        normalized <-
          expectAlphaZero
            validAlphaZero
              { rawAlphaZeroRun =
                  (rawAlphaZeroRun validAlphaZero)
                    { rawRunSubjectId = "  connect4-policy-value "
                    , rawRunSeeds = [31]
                    }
              , rawAlphaZeroGame = " Connect 4 "
              }
        alphaZeroPlanId normalized @?= alphaZeroPlanId baseline
        changed <- traverse expectAlphaZero alphaZeroMutations
        assertDistinctPlanIds
          (planIdText (alphaZeroPlanId baseline))
          (fmap (planIdText . alphaZeroPlanId) changed)
    , testCase "resolved accessors preserve distinct typed quantities" $ do
        tuning <- expectTuning validTuning
        quantityValue (tuningPlanTrials tuning) @?= 12
        quantityValue (tuningPlanParallelism tuning) @?= 3
        quantityValue (tuningPlanPromotions tuning) @?= 1
        quantityValue (tuningPlanPerTrialUpdates tuning) @?= 100
        alphaZero <- expectAlphaZero validAlphaZero
        alphaZeroPlanGame alphaZero @?= Connect4
        quantityValue (alphaZeroPlanGenerations alphaZero) @?= 2
        quantityValue (alphaZeroPlanSelfPlayGames alphaZero) @?= 8
        quantityValue (alphaZeroPlanMctsSimulations alphaZero) @?= 32
        quantityValue (alphaZeroPlanMaxPlies alphaZero) @?= 42
        quantityValue (alphaZeroPlanUpdates alphaZero) @?= 4
        quantityValue (alphaZeroPlanArenaGames alphaZero) @?= 16
    , testCase "tuning transport is deterministic, single-line, and re-refines" $ do
        plan <- expectTuning validTuning
        let encoded = renderTuningPlanTransport plan
        assertSingleLineAscii encoded
        renderTuningPlanTransport plan @?= encoded
        parseTuningPlanTransport encoded @?= Success plan
    , testCase "AlphaZero transport is deterministic, single-line, and re-refines" $ do
        plan <- expectAlphaZero validAlphaZero
        let encoded = renderAlphaZeroPlanTransport plan
        assertSingleLineAscii encoded
        renderAlphaZeroPlanTransport plan @?= encoded
        parseAlphaZeroPlanTransport encoded @?= Success plan
    , testCase "transport rejects tampered PlanId and incompatible versions" $ do
        tuning <- expectTuning validTuning
        alphaZero <- expectAlphaZero validAlphaZero
        assertTamperedTuningIdentity tuning
        assertTamperedAlphaZeroIdentity alphaZero
        parseTuningPlanTransport
          (Text.replace "transport-version=1" "transport-version=2" (renderTuningPlanTransport tuning))
          @?= Failure (UnsupportedTransportVersion 2 NonEmpty.:| [])
        case parseAlphaZeroPlanTransport
          (Text.replace "run-version=1" "run-version=9" (renderAlphaZeroPlanTransport alphaZero)) of
          Failure errors ->
            assertBool
              "unsupported run-plan version survives transport decode"
              ( CommonRunPlanError (UnsupportedRunPlanVersion 9)
                  `elem` NonEmpty.toList errors
              )
          Success _ -> assertFailure "incompatible run version unexpectedly parsed"
    , testCase "transport rejects malformed, duplicate, unknown, and cross-kind fields" $ do
        tuning <- expectTuning validTuning
        alphaZero <- expectAlphaZero validAlphaZero
        let tuningText = renderTuningPlanTransport tuning
            alphaZeroText = renderAlphaZeroPlanTransport alphaZero
        assertTransportFailure isDuplicate $ parseTuningPlanTransport (tuningText <> "|plan-id=duplicate")
        assertTransportFailure isUnknownField $ parseTuningPlanTransport (tuningText <> "|future-field=1")
        assertTransportFailure isMalformed $ parseTuningPlanTransport (tuningText <> "|broken-token")
        assertTransportFailure isKindMismatch $
          parseAlphaZeroPlanTransport
            (Text.replace "kind=alphazero-self-play" "kind=hyperparameter-tuning" alphaZeroText)
    , testCase "command adapters reject mismatched or non-canonical tuning plans" $ do
        (prepared, plan) <- expectPreparedTuning validTuningCommand
        PlanCommand.validateStartSweep prepared @?= Right plan
        assertRejected
          "missing tuning transport"
          (PlanCommand.validateStartSweep prepared {Tune.ssResolvedPlan = ""})
        assertRejected
          "incompatible tuning transport version"
          ( PlanCommand.validateStartSweep
              prepared
                { Tune.ssResolvedPlan =
                    Text.replace
                      "transport-version=1"
                      "transport-version=2"
                      (Tune.ssResolvedPlan prepared)
                }
          )
        assertRejected
          "non-canonical tuning transport"
          ( PlanCommand.validateStartSweep
              prepared {Tune.ssResolvedPlan = reorderTransport (Tune.ssResolvedPlan prepared)}
          )
        assertRejected
          "mismatched tuning PlanId"
          (PlanCommand.validateStartSweep prepared {Tune.ssPlanId = Text.replicate 64 "0"})
        assertRejected
          "raw tuning budget differs from transported plan"
          ( PlanCommand.validateStartSweep
              prepared {Tune.ssTrialBudget = Tune.ssTrialBudget prepared + 1}
          )
    , testCase "exact tuning command binds the normalized Dhall semantics and revalidates them" $ do
        let executionSpec = Catalog.canonicalMnistTuningExecutionSpec
            searchSpace = Catalog.tuningExecutionSearchSpace executionSpec
            learningRate = Catalog.tuningSearchLearningRate searchSpace
            changedSpec =
              executionSpec
                { Catalog.tuningExecutionSearchSpace =
                    searchSpace
                      { Catalog.tuningSearchLearningRate =
                          learningRate {Catalog.floatSearchMaximum = 2.0e-2}
                      }
                }
        (prepared, plan) <- expectPreparedExactTuning executionSpec exactTuningCommand
        tuningPlanExecutionSpec plan @?= executionSpec
        PlanCommand.validateStartSweep prepared @?= Right plan
        PlanCommand.validateStartSweepWithExecutionSpec executionSpec prepared @?= Right plan
        (changedPrepared, changedPlan) <-
          expectPreparedExactTuning changedSpec exactTuningCommand
        assertBool
          "search-space mutation must change exact tuning PlanId"
          (tuningPlanId changedPlan /= tuningPlanId plan)
        assertRejected
          "retained Dhall spec differs from transported tuning spec"
          (PlanCommand.validateStartSweepWithExecutionSpec executionSpec changedPrepared)
    , testCase "browser Tune defaults parse, prepare, and admit their exact promotion budget" $ do
        unresolved <-
          case Tune.parseTuneCommand browserTuneStartPayload of
            Just (Tune.TuneStart start) -> pure start
            other -> assertFailure ("unexpected browser Tune command parse: " <> show other) >> fail "unreachable"
        Tune.ssPlanId unresolved @?= "browser-unresolved"
        Tune.ssResolvedPlan unresolved @?= "browser-unresolved"
        (prepared, plan) <- expectPreparedTuning unresolved
        PlanCommand.validateStartSweep prepared @?= Right plan
        quantityValue (tuningPlanTrials plan) @?= 8
        quantityValue (tuningPlanParallelism plan) @?= 8
        quantityValue (tuningPlanPromotions plan) @?= 1
        tuningPlanSampler plan @?= Catalog.TPE
        tuningPlanScheduler plan @?= Catalog.ASHA
        tuningPlanPruner plan @?= Catalog.MedianPruner
        results <-
          case Catalog.trialObjectiveResultsForBudget Catalog.TPE 8 100 8 of
            Left message -> assertFailure (Text.unpack message) >> fail "unreachable"
            Right values -> pure values
        executions <-
          case Catalog.trialExecutions Catalog.ASHA Catalog.MedianPruner 1 results of
            Left message -> assertFailure (Text.unpack message) >> fail "unreachable"
            Right values -> pure values
        length (filter Catalog.trialExecutionPromoted executions) @?= 1
    , testCase "command adapters reject mismatched or non-canonical AlphaZero plans" $ do
        (prepared, plan) <- expectPreparedAlphaZero validAlphaZeroCommand
        PlanCommand.validateStartAlphaZeroRun prepared @?= Right plan
        assertRejected
          "missing AlphaZero transport"
          (PlanCommand.validateStartAlphaZeroRun prepared {Rl.sazResolvedPlan = ""})
        assertRejected
          "incompatible AlphaZero transport version"
          ( PlanCommand.validateStartAlphaZeroRun
              prepared
                { Rl.sazResolvedPlan =
                    Text.replace
                      "transport-version=1"
                      "transport-version=2"
                      (Rl.sazResolvedPlan prepared)
                }
          )
        assertRejected
          "non-canonical AlphaZero transport"
          ( PlanCommand.validateStartAlphaZeroRun
              prepared {Rl.sazResolvedPlan = reorderTransport (Rl.sazResolvedPlan prepared)}
          )
        assertRejected
          "mismatched AlphaZero PlanId"
          (PlanCommand.validateStartAlphaZeroRun prepared {Rl.sazPlanId = Text.replicate 64 "f"})
        assertRejected
          "raw AlphaZero game differs from transported plan"
          (PlanCommand.validateStartAlphaZeroRun prepared {Rl.sazGame = "othello"})
    , testCase "TuneRunConfig re-refines identity, version, and canonical transport" $ do
        (_, plan) <- expectPreparedTuning validTuningCommand
        let config =
              RunConfig.TuneRunConfig
                { RunConfig.turcPlanId = planIdText (tuningPlanId plan)
                , RunConfig.turcResolvedPlan = renderTuningPlanTransport plan
                , RunConfig.turcPulsarWsUrl = "ws://pulsar.example/ws"
                }
        RunConfig.tuningPlanFromRunConfig config @?= Right plan
        assertRejected
          "TuneRunConfig PlanId mismatch"
          (RunConfig.tuningPlanFromRunConfig config {RunConfig.turcPlanId = Text.replicate 64 "0"})
        assertRejected
          "TuneRunConfig malformed transport"
          (RunConfig.tuningPlanFromRunConfig config {RunConfig.turcResolvedPlan = "not-a-plan"})
        assertRejected
          "TuneRunConfig incompatible transport version"
          ( RunConfig.tuningPlanFromRunConfig
              config
                { RunConfig.turcResolvedPlan =
                    Text.replace
                      "transport-version=1"
                      "transport-version=2"
                      (RunConfig.turcResolvedPlan config)
                }
          )
        assertRejected
          "TuneRunConfig non-canonical transport"
          ( RunConfig.tuningPlanFromRunConfig
              config
                { RunConfig.turcResolvedPlan = reorderTransport (RunConfig.turcResolvedPlan config)
                }
          )
    , testCase "AlphaZeroRunConfig re-refines identity, version, and canonical transport" $ do
        (_, plan) <- expectPreparedAlphaZero validAlphaZeroCommand
        let config =
              RunConfig.AlphaZeroRunConfig
                { RunConfig.azrcPlanId = planIdText (alphaZeroPlanId plan)
                , RunConfig.azrcResolvedPlan = renderAlphaZeroPlanTransport plan
                , RunConfig.azrcPulsarWsUrl = "ws://pulsar.example/ws"
                }
        RunConfig.alphaZeroPlanFromRunConfig config @?= Right plan
        assertRejected
          "AlphaZeroRunConfig PlanId mismatch"
          ( RunConfig.alphaZeroPlanFromRunConfig
              config {RunConfig.azrcPlanId = Text.replicate 64 "f"}
          )
        assertRejected
          "AlphaZeroRunConfig malformed transport"
          (RunConfig.alphaZeroPlanFromRunConfig config {RunConfig.azrcResolvedPlan = "not-a-plan"})
        assertRejected
          "AlphaZeroRunConfig incompatible transport version"
          ( RunConfig.alphaZeroPlanFromRunConfig
              config
                { RunConfig.azrcResolvedPlan =
                    Text.replace
                      "transport-version=1"
                      "transport-version=2"
                      (RunConfig.azrcResolvedPlan config)
                }
          )
        assertRejected
          "AlphaZeroRunConfig non-canonical transport"
          ( RunConfig.alphaZeroPlanFromRunConfig
              config
                { RunConfig.azrcResolvedPlan =
                    reorderTransport (RunConfig.azrcResolvedPlan config)
                }
          )
    ]

validSupervisedCommand :: Training.StartTraining
validSupervisedCommand =
  Training.StartTraining
    { Training.stExperimentHash = "supervised-exp"
    , Training.stDhallObjectKey = "experiments/mnist.dhall"
    , Training.stSubstrate = LinuxCPU
    , Training.stSeed = 19
    , Training.stEpochs = 3
    , Training.stBatchSize = 16
    , Training.stPlanId = ""
    , Training.stResolvedPlan = ""
    , Training.stTrainingExamples = 64
    , Training.stEvaluationExamples = 16
    }

validTuningCommand :: Tune.StartSweep
validTuningCommand =
  Tune.StartSweep
    { Tune.ssExperimentHash = "tune-exp"
    , Tune.ssDhallObjectKey = "experiments/mnist-tune.dhall"
    , Tune.ssSubstrate = LinuxCPU
    , Tune.ssSweepSeed = 17
    , Tune.ssTrialBudget = 12
    , Tune.ssBudgetPerTrial = 100
    , Tune.ssSampler = "TPE"
    , Tune.ssScheduler = "ASHA"
    , Tune.ssPruner = "MedianPruner"
    , Tune.ssParallelism = 3
    , Tune.ssPromotions = 1
    , Tune.ssPlanId = ""
    , Tune.ssResolvedPlan = ""
    }

exactTuningCommand :: Tune.StartSweep
exactTuningCommand =
  validTuningCommand
    { Tune.ssSweepSeed = 1729
    , Tune.ssTrialBudget = 128
    , Tune.ssBudgetPerTrial = 1000
    , Tune.ssParallelism = 1
    , Tune.ssPromotions = 1
    }

browserTuneStartPayload :: Text
browserTuneStartPayload =
  Text.unlines
    [ "kind: StartSweep"
    , "experiment-hash: product-row-hyperparameter-tuning"
    , "dhall-object-key: experiments/mnist-tune.dhall"
    , "substrate: linux-cpu"
    , "sweep-seed: 1"
    , "trial-budget: 8"
    , "budget-per-trial: 100"
    , "sampler: TPE"
    , "scheduler: ASHA"
    , "pruner: MedianPruner"
    , "parallelism: 8"
    , "promotions: 1"
    , "plan-id: browser-unresolved"
    , "resolved-plan: browser-unresolved"
    ]

validAlphaZeroCommand :: Rl.StartAlphaZeroRun
validAlphaZeroCommand =
  Rl.StartAlphaZeroRun
    { Rl.sazSubstrate = LinuxCPU
    , Rl.sazExperimentHash = "alphazero-exp"
    , Rl.sazPlanId = ""
    , Rl.sazResolvedPlan = ""
    , Rl.sazGame = "connect4"
    , Rl.sazGenerations = 2
    , Rl.sazSelfPlayGames = 8
    , Rl.sazMctsSimulationsPerMove = 32
    , Rl.sazMaxPlies = 42
    , Rl.sazOptimizerUpdates = 4
    , Rl.sazArenaGames = 16
    , Rl.sazSeed = 31
    }

validTuning :: RawTuningPlan
validTuning =
  RawTuningPlan
    { rawTuningRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = HyperparameterTuningWitness
          , rawRunExperimentId = "tune-exp"
          , rawRunSubjectId = "mnist/dense"
          , rawRunArtifactId = "tune-best-checkpoint"
          , rawRunTopicId = "tune.event.linux-cpu"
          , rawRunSubstrate = LinuxCPU
          , rawRunPlacement = ClusterRun
          , rawRunSeeds = [11, 17]
          , rawRunBudget = RawTuningBudget 12 3 1 100
          }
    , rawTuningSampler = "TPE"
    , rawTuningScheduler = "ASHA"
    , rawTuningPruner = "MedianPruner"
    }

validAlphaZero :: RawAlphaZeroPlan
validAlphaZero =
  RawAlphaZeroPlan
    { rawAlphaZeroRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = AlphaZeroSelfPlayWitness
          , rawRunExperimentId = "alphazero-exp"
          , rawRunSubjectId = "connect4-policy-value"
          , rawRunArtifactId = "alphazero-checkpoint"
          , rawRunTopicId = "rl.event.linux-cpu"
          , rawRunSubstrate = LinuxCPU
          , rawRunPlacement = ClusterRun
          , rawRunSeeds = [31]
          , rawRunBudget = RawAlphaZeroBudget 2 8 32 42 4 16
          }
    , rawAlphaZeroGame = "connect4"
    }

tuningMutations :: [RawTuningPlan]
tuningMutations =
  fmap
    mutateRun
    [ baseRun {rawRunExperimentId = "other-tune-exp"}
    , baseRun {rawRunSubjectId = "fashion-mnist/dense"}
    , baseRun {rawRunArtifactId = "other-best-checkpoint"}
    , baseRun {rawRunTopicId = "tune.event.other"}
    , baseRun {rawRunSubstrate = AppleSilicon, rawRunPlacement = HostRun}
    , baseRun {rawRunSeeds = [12, 17]}
    , baseRun {rawRunBudget = RawTuningBudget 13 3 1 100}
    , baseRun {rawRunBudget = RawTuningBudget 12 4 1 100}
    , baseRun {rawRunBudget = RawTuningBudget 12 3 2 100}
    , baseRun {rawRunBudget = RawTuningBudget 12 3 1 101}
    ]
    <> [validTuning {rawTuningSampler = "Sobol"}]
    <> [validTuning {rawTuningScheduler = "Fifo"}]
    <> [validTuning {rawTuningPruner = "NoPruner"}]
 where
  baseRun = rawTuningRun validTuning
  mutateRun runPlan = validTuning {rawTuningRun = runPlan}

alphaZeroMutations :: [RawAlphaZeroPlan]
alphaZeroMutations =
  fmap
    mutateRun
    [ baseRun {rawRunExperimentId = "other-alphazero-exp"}
    , baseRun {rawRunSubjectId = "other-policy-value"}
    , baseRun {rawRunArtifactId = "other-alphazero-checkpoint"}
    , baseRun {rawRunTopicId = "rl.event.other"}
    , baseRun {rawRunSubstrate = AppleSilicon, rawRunPlacement = HostRun}
    , baseRun {rawRunSeeds = [32]}
    , baseRun {rawRunBudget = RawAlphaZeroBudget 3 8 32 42 4 16}
    , baseRun {rawRunBudget = RawAlphaZeroBudget 2 9 32 42 4 16}
    , baseRun {rawRunBudget = RawAlphaZeroBudget 2 8 33 42 4 16}
    , baseRun {rawRunBudget = RawAlphaZeroBudget 2 8 32 43 4 16}
    , baseRun {rawRunBudget = RawAlphaZeroBudget 2 8 32 42 5 16}
    , baseRun {rawRunBudget = RawAlphaZeroBudget 2 8 32 42 4 17}
    ]
    <> [validAlphaZero {rawAlphaZeroGame = "othello"}]
 where
  baseRun = rawAlphaZeroRun validAlphaZero
  mutateRun runPlan = validAlphaZero {rawAlphaZeroRun = runPlan}

expectTuning :: RawTuningPlan -> IO TuningPlan
expectTuning raw =
  case resolveTuningPlan raw of
    Success plan -> pure plan
    Failure errors -> assertFailure (show errors) >> fail "unreachable"

expectAlphaZero :: RawAlphaZeroPlan -> IO AlphaZeroPlan
expectAlphaZero raw =
  case resolveAlphaZeroPlan raw of
    Success plan -> pure plan
    Failure errors -> assertFailure (show errors) >> fail "unreachable"

expectPreparedTuning :: Tune.StartSweep -> IO (Tune.StartSweep, TuningPlan)
expectPreparedTuning raw =
  case PlanCommand.prepareStartSweep raw of
    Right prepared -> pure prepared
    Left message -> assertFailure (Text.unpack message) >> fail "unreachable"

expectPreparedExactTuning
  :: Catalog.TuningExecutionSpec
  -> Tune.StartSweep
  -> IO (Tune.StartSweep, TuningPlan)
expectPreparedExactTuning executionSpec raw =
  case PlanCommand.prepareStartSweepWithExecutionSpec executionSpec raw of
    Right prepared -> pure prepared
    Left message -> assertFailure (Text.unpack message) >> fail "unreachable"

expectPreparedSupervised
  :: Training.StartTraining
  -> IO (Training.StartTraining, SupervisedPlan)
expectPreparedSupervised raw =
  case PlanCommand.prepareStartTraining raw of
    Right prepared -> pure prepared
    Left message -> assertFailure (Text.unpack message) >> fail "unreachable"

expectPreparedAlphaZero :: Rl.StartAlphaZeroRun -> IO (Rl.StartAlphaZeroRun, AlphaZeroPlan)
expectPreparedAlphaZero raw =
  case PlanCommand.prepareStartAlphaZeroRun raw of
    Right prepared -> pure prepared
    Left message -> assertFailure (Text.unpack message) >> fail "unreachable"

reorderTransport :: Text -> Text
reorderTransport = Text.intercalate "|" . reverse . Text.splitOn "|"

assertRejected :: Text -> Either Text value -> IO ()
assertRejected _ (Left _) = pure ()
assertRejected label (Right _) =
  assertFailure (Text.unpack label <> " unexpectedly passed refinement")

assertPlanError
  :: PlanError
  -> Validation (NonEmpty.NonEmpty WorkloadPlanError) value
  -> IO ()
assertPlanError expected result =
  case result of
    Failure errors ->
      assertBool
        ("missing expected plan error: " <> show expected <> " in " <> show errors)
        (CommonRunPlanError expected `elem` NonEmpty.toList errors)
    Success _ -> assertFailure "invalid workload plan unexpectedly resolved"

assertDistinctPlanIds :: Text -> [Text] -> IO ()
assertDistinctPlanIds baseline changed = do
  assertBool "every mutation changes PlanId" (baseline `notElem` changed)
  Set.size (Set.fromList changed) @?= length changed

assertSingleLineAscii :: Text -> IO ()
assertSingleLineAscii encoded = do
  assertBool "transport is non-empty" (not (Text.null encoded))
  assertBool "transport contains no newline" (not (Text.any (`elem` ['\n', '\r']) encoded))
  assertBool "transport is ASCII-safe" (Text.all ((< 128) . ord) encoded)

assertTamperedTuningIdentity :: TuningPlan -> IO ()
assertTamperedTuningIdentity plan =
  let encoded = renderTuningPlanTransport plan
      declared = planIdText (tuningPlanId plan)
      tampered = Text.replace ("plan-id=" <> declared) ("plan-id=" <> Text.replicate 64 "0") encoded
   in case parseTuningPlanTransport tampered of
        Failure (TransportPlanIdMismatch observed derived NonEmpty.:| []) -> do
          observed @?= Text.replicate 64 "0"
          derived @?= declared
        other -> assertFailure ("unexpected tampered tuning result: " <> show other)

assertTamperedAlphaZeroIdentity :: AlphaZeroPlan -> IO ()
assertTamperedAlphaZeroIdentity plan =
  let encoded = renderAlphaZeroPlanTransport plan
      declared = planIdText (alphaZeroPlanId plan)
      tampered = Text.replace ("plan-id=" <> declared) ("plan-id=" <> Text.replicate 64 "f") encoded
   in case parseAlphaZeroPlanTransport tampered of
        Failure (TransportPlanIdMismatch observed derived NonEmpty.:| []) -> do
          observed @?= Text.replicate 64 "f"
          derived @?= declared
        other -> assertFailure ("unexpected tampered AlphaZero result: " <> show other)

assertTransportFailure
  :: (WorkloadPlanError -> Bool)
  -> Validation (NonEmpty.NonEmpty WorkloadPlanError) value
  -> IO ()
assertTransportFailure predicate result =
  case result of
    Failure errors ->
      assertBool
        ("expected transport failure not found in " <> show errors)
        (any predicate (NonEmpty.toList errors))
    Success _ -> assertFailure "malformed transport unexpectedly parsed"

isCommonNonPositive :: WorkloadPlanError -> Bool
isCommonNonPositive (CommonRunPlanError (NonPositiveQuantity _)) = True
isCommonNonPositive _ = False

isUnknownTuningAxis :: WorkloadPlanError -> Bool
isUnknownTuningAxis UnknownTuningSampler {} = True
isUnknownTuningAxis UnknownTuningScheduler {} = True
isUnknownTuningAxis UnknownTuningPruner {} = True
isUnknownTuningAxis _ = False

isDuplicate :: WorkloadPlanError -> Bool
isDuplicate DuplicateTransportField {} = True
isDuplicate _ = False

isUnknownField :: WorkloadPlanError -> Bool
isUnknownField UnknownTransportField {} = True
isUnknownField _ = False

isMalformed :: WorkloadPlanError -> Bool
isMalformed InvalidTransportLine {} = True
isMalformed _ = False

isKindMismatch :: WorkloadPlanError -> Bool
isKindMismatch TransportKindMismatch {} = True
isKindMismatch _ = False

isDerivedQuantityMismatch :: WorkloadPlanError -> Bool
isDerivedQuantityMismatch (CommonRunPlanError DerivedQuantityMismatch {}) = True
isDerivedQuantityMismatch _ = False
