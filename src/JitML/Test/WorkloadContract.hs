{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.WorkloadContract
  ( workloadContractTests
  )
where

import Data.List (permutations)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertFailure, testCase, (@?=))

import JitML.Plan.Plan
  ( PlanError (..)
  , PlanId
  , RawRunBudget (..)
  , RawRunRequest (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , Validation (..)
  , finiteMeasurementValue
  , planIdText
  )
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , RawAlphaZeroPlan (..)
  , RawTuningPlan (..)
  , TuningPlan
  , alphaZeroPlanId
  , resolveAlphaZeroPlan
  , resolveTuningPlan
  , tuningPlanId
  )
import JitML.Product.Evidence (mkTrainingEvidence)
import JitML.Proto.Rl
  ( ArenaCompleted (..)
  , GenerationCompleted (..)
  , RlEvent (..)
  )
import JitML.Proto.Tune
  ( SweepFinished (..)
  , TrialFinished (..)
  , TuneEvent (..)
  , completeSweep
  , scCompletedTraining
  , scFinished
  )
import JitML.Run.Contract
  ( ContractViolation (..)
  , MissingEvidence (..)
  , finishContract
  , initialProgress
  )
import JitML.Run.WorkloadContract
import JitML.Substrate (Substrate (..))
import JitML.Training.Budget
  ( BudgetKind (..)
  , CompletedTraining
  , MetricGoal (..)
  , TensorBoardRunMetadata (..)
  , completedTraining
  , measureCriterion
  , mkTrainingBudget
  )

workloadContractTests :: TestTree
workloadContractTests =
  testGroup
    "workload completion contracts (Sprint 10.12)"
    [ testCase "tuning exact completion is arrival-order independent" $ do
        let contract = tuningCompletionContract tuningPlan
            events = fmap tuneTrial [0, 1, 2] <> [tuneSweepCompleted]
        mapM_
          ( \arrivalOrder -> do
              progress <- ingestTuneEvents arrivalOrder
              case finishContract contract progress of
                Failure errors ->
                  assertFailure ("expected completed tuning evidence, got " <> show errors)
                Success completion -> do
                  Map.keys (tuningCompletedTrials completion) @?= [0, 1, 2]
                  finiteMeasurementValue
                    (tuningSweepBestObjective (tuningCompletedSweep completion))
                    @?= 0.25
                  tuningSweepTrialsPromoted (tuningCompletedSweep completion) @?= 1
          )
          (permutations events)
    , testCase "tuning redelivery is idempotent and conflicting duplicates fail" $ do
        let contract = tuningCompletionContract tuningPlan
            first = tuneTrial 0
        once <- expectRight $ ingestTuneEvent tuningPlan (initialProgress contract) first
        twice <- expectRight $ ingestTuneEvent tuningPlan once first
        twice @?= once
        case ingestTuneEvent tuningPlan once (setTuneObjective 9.0 first) of
          Left (WorkloadEvidenceViolation ConflictingDuplicate {}) -> pure ()
          other -> assertFailure ("expected conflicting duplicate, got " <> show other)
    , testCase "tuning reports missing trials and rejects extra trial indices" $ do
        let contract = tuningCompletionContract tuningPlan
        incomplete <- ingestTuneEvents [tuneTrial 0, tuneTrial 2, tuneSweepCompleted]
        finishContract contract incomplete
          @?= Failure
            (MissingKeys "tuning-trial-finished" ("1" :| []) :| [])
        ingestTuneEvent tuningPlan (initialProgress contract) (tuneTrial 3)
          @?= Left
            ( WorkloadEvidenceViolation
                OutOfRangeKey
                  { violationRequirement = "tuning-trial-finished"
                  , violationKey = "3"
                  }
            )
    , testCase "tuning rejects a wrong PlanId before evidence insertion" $
        ingestTuneEvent
          tuningPlan
          (initialProgress (tuningCompletionContract tuningPlan))
          (setTunePlanId "wrong-plan" (tuneTrial 0))
          @?= Left
            WorkloadEventPlanMismatch
              { workloadRequirement = "tuning-trial-finished"
              , workloadExpectedPlanId = planIdText (tuningPlanId tuningPlan)
              , workloadObservedPlanId = "wrong-plan"
              }
    , testCase "tuning rejects non-finite trial and sweep objectives" $ do
        let progress = initialProgress (tuningCompletionContract tuningPlan)
        ingestTuneEvent tuningPlan progress (setTuneObjective (0 / 0) (tuneTrial 0))
          @?= Left
            WorkloadEventRefinementFailure
              { workloadRequirement = "tuning-trial-finished"
              , workloadPlanErrors =
                  NonFiniteMeasurement "tuning-trial-objective" :| []
              }
        ingestTuneEvent tuningPlan progress (setSweepObjective (1 / 0) tuneSweepFinished)
          @?= Left
            WorkloadEventRefinementFailure
              { workloadRequirement = "tuning-sweep-finished"
              , workloadPlanErrors =
                  NonFiniteMeasurement "tuning-best-objective" :| []
              }
    , testCase "tuning rejects a promoted count that differs from the plan" $
        ingestTuneEvent
          tuningPlan
          (initialProgress (tuningCompletionContract tuningPlan))
          (setSweepPromoted 2 tuneSweepFinished)
          @?= Left
            WorkloadEventBudgetMismatch
              { workloadRequirement = "tuning-sweep-promoted-trials"
              , workloadExpectedBudget = 1
              , workloadObservedBudget = 2
              }
    , testCase "proof-free sweep completion is validated but cannot finish the contract" $ do
        progress <-
          ingestTuneEvents
            (fmap tuneTrial [0, 1, 2] <> [tuneSweepFinished])
        finishContract (tuningCompletionContract tuningPlan) progress
          @?= Failure
            (MissingExactlyOne "tuning-sweep-completed" :| [])
    , testCase "completed sweep rejects a proof for a different PlanId" $
        completeSweep
          sweepFinished
          (tuningCompletionProof (alphaZeroPlanId alphaZeroPlan) TuningTrialBudget 3 (Just 7))
          @?= Left "sweep plan_id does not match completed-training plan identity"
    , testCase "completed sweep rejects a proof in the wrong budget unit" $
        completeSweep
          sweepFinished
          (tuningCompletionProof (tuningPlanId tuningPlan) SupervisedEpochBudget 3 (Just 7))
          @?= Left "sweep completion requires a tuning-trial budget"
    , testCase "completed sweep rejects a proof with a different trial budget" $
        completeSweep
          sweepFinished
          (tuningCompletionProof (tuningPlanId tuningPlan) TuningTrialBudget 2 (Just 7))
          @?= Left "completed sweep trials do not match completed-training target units"
    , testCase "completed sweep rejects a proof with a different deterministic seed" $
        ingestTuneEvent
          tuningPlan
          (initialProgress (tuningCompletionContract tuningPlan))
          ( completedSweepEvent
              (tuningCompletionProof (tuningPlanId tuningPlan) TuningTrialBudget 3 (Just 99))
          )
          @?= Left
            WorkloadEventSeedMismatch
              { workloadRequirement = "tuning-sweep-completed-training"
              , workloadExpectedSeed = Just 7
              , workloadObservedSeed = Just 99
              }
    , testCase "AlphaZero exact completion is arrival-order independent" $ do
        let contract = alphaZeroCompletionContract alphaZeroPlan
            events = fmap alphaZeroGeneration [0, 1, 2] <> [alphaZeroArena]
        mapM_
          ( \arrivalOrder -> do
              progress <- ingestAlphaZeroEvents arrivalOrder
              case finishContract contract progress of
                Failure errors ->
                  assertFailure ("expected completed AlphaZero evidence, got " <> show errors)
                Success completion -> do
                  Map.keys (alphaZeroCompletedGenerations completion) @?= [0, 1, 2]
                  finiteMeasurementValue
                    (alphaZeroArenaWinRate (alphaZeroCompletedArena completion))
                    @?= 0.75
          )
          (permutations events)
    , testCase "AlphaZero redelivery is idempotent and conflicting duplicates fail" $ do
        let contract = alphaZeroCompletionContract alphaZeroPlan
            first = alphaZeroArena
        once <- expectRight $ ingestAlphaZeroEvent alphaZeroPlan (initialProgress contract) first
        twice <- expectRight $ ingestAlphaZeroEvent alphaZeroPlan once first
        twice @?= once
        case ingestAlphaZeroEvent alphaZeroPlan once (setArenaWinRate 0.5 first) of
          Left (WorkloadEvidenceViolation ConflictingDuplicate {}) -> pure ()
          other -> assertFailure ("expected conflicting duplicate, got " <> show other)
    , testCase "AlphaZero reports missing generations and rejects extra indices" $ do
        let contract = alphaZeroCompletionContract alphaZeroPlan
        incomplete <-
          ingestAlphaZeroEvents
            [alphaZeroGeneration 0, alphaZeroGeneration 2, alphaZeroArena]
        finishContract contract incomplete
          @?= Failure
            ( MissingKeys
                "alphazero-generation-completed"
                ("1" :| [])
                :| []
            )
        ingestAlphaZeroEvent alphaZeroPlan (initialProgress contract) (alphaZeroGeneration 3)
          @?= Left
            ( WorkloadEvidenceViolation
                OutOfRangeKey
                  { violationRequirement = "alphazero-generation-completed"
                  , violationKey = "3"
                  }
            )
    , testCase "AlphaZero rejects a wrong PlanId before evidence insertion" $
        ingestAlphaZeroEvent
          alphaZeroPlan
          (initialProgress (alphaZeroCompletionContract alphaZeroPlan))
          (setAlphaZeroPlanId "wrong-plan" (alphaZeroGeneration 0))
          @?= Left
            WorkloadEventPlanMismatch
              { workloadRequirement = "alphazero-generation-completed"
              , workloadExpectedPlanId = planIdText (alphaZeroPlanId alphaZeroPlan)
              , workloadObservedPlanId = "wrong-plan"
              }
    , testCase "AlphaZero rejects a non-finite arena win rate" $
        ingestAlphaZeroEvent
          alphaZeroPlan
          (initialProgress (alphaZeroCompletionContract alphaZeroPlan))
          (setArenaWinRate (0 / 0) alphaZeroArena)
          @?= Left
            WorkloadEventRefinementFailure
              { workloadRequirement = "alphazero-arena-completed"
              , workloadPlanErrors =
                  NonFiniteMeasurement "alphazero-arena-win-rate" :| []
              }
    ]

tuningPlan :: TuningPlan
tuningPlan =
  expectSuccess $ resolveTuningPlan rawTuningPlan

rawTuningPlan :: RawTuningPlan
rawTuningPlan =
  RawTuningPlan
    { rawTuningRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = HyperparameterTuningWitness
          , rawRunExperimentId = "contract-tuning"
          , rawRunSubjectId = "mnist/dense"
          , rawRunArtifactId = "best-checkpoint"
          , rawRunTopicId = "tune.event.linux-cpu"
          , rawRunSubstrate = LinuxCPU
          , rawRunPlacement = ClusterRun
          , rawRunSeeds = [7]
          , rawRunBudget = RawTuningBudget 3 1 1 10
          }
    , rawTuningSampler = "TPE"
    , rawTuningScheduler = "ASHA"
    , rawTuningPruner = "MedianPruner"
    }

alphaZeroPlan :: AlphaZeroPlan
alphaZeroPlan =
  expectSuccess $ resolveAlphaZeroPlan rawAlphaZeroPlan

rawAlphaZeroPlan :: RawAlphaZeroPlan
rawAlphaZeroPlan =
  RawAlphaZeroPlan
    { rawAlphaZeroRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = AlphaZeroSelfPlayWitness
          , rawRunExperimentId = "contract-alphazero"
          , rawRunSubjectId = "connect4-policy-value"
          , rawRunArtifactId = "alphazero-checkpoint"
          , rawRunTopicId = "rl.event.linux-cpu"
          , rawRunSubstrate = LinuxCPU
          , rawRunPlacement = ClusterRun
          , rawRunSeeds = [11]
          , rawRunBudget = RawAlphaZeroBudget 3 4 16 42 8 6
          }
    , rawAlphaZeroGame = "connect4"
    }

tuneTrial :: Word32 -> TuneEvent
tuneTrial trial =
  TuneTrialFinished
    TrialFinished
      { tfTuneExperimentHash = "contract-tuning"
      , tfTunePlanId = planIdText (tuningPlanId tuningPlan)
      , tfTuneTrial = trial
      , tfTuneObjective = 1 / fromIntegral (trial + 1)
      , tfTunePruned = False
      , tfTuneTranscriptObjectKey =
          "trials/" <> showText trial <> ".cbor"
      , tfTuneTimestampNs = fromIntegral trial + 100
      }

tuneSweepFinished :: TuneEvent
tuneSweepFinished = TuneSweepFinished sweepFinished

tuneSweepCompleted :: TuneEvent
tuneSweepCompleted = completedSweepEvent validTuningCompletionProof

sweepFinished :: SweepFinished
sweepFinished =
  SweepFinished
    { sfExperimentHash = "contract-tuning"
    , sfPlanId = planIdText (tuningPlanId tuningPlan)
    , sfTrialsCompleted = 3
    , sfTrialsPruned = 0
    , sfTrialsPromoted = 1
    , sfBestObjective = 0.25
    }

validTuningCompletionProof :: CompletedTraining
validTuningCompletionProof =
  tuningCompletionProof
    (tuningPlanId tuningPlan)
    TuningTrialBudget
    3
    (Just 7)

tuningCompletionProof
  :: PlanId
  -> BudgetKind
  -> Word64
  -> Maybe Word64
  -> CompletedTraining
tuningCompletionProof planId kind trialBudget seed =
  expectRightValue $ do
    budget <- mkTrainingBudget kind trialBudget seed
    evidence <-
      mkTrainingEvidence
        "tuning-initial-weights"
        "tuning-final-weights"
        (max 1 trialBudget)
        "tuning-dataset-sha"
    observation <-
      measureCriterion "best_objective" MetricMinimise 0.25 0.25
    completedTraining
      planId
      budget
      trialBudget
      evidence
      [observation]
      TensorBoardRunMetadata
        { tbrRunId = "contract-tuning"
        , tbrLogPrefix = "jitml-tensorboard/contract-tuning"
        , tbrScalarTags = ["best_objective"]
        }

completedSweepEvent :: CompletedTraining -> TuneEvent
completedSweepEvent proof =
  TuneSweepCompleted (expectRightValue (completeSweep sweepFinished proof))

alphaZeroGeneration :: Word32 -> RlEvent
alphaZeroGeneration generation =
  RlGenerationCompleted
    GenerationCompleted
      { gcPlanId = planIdText (alphaZeroPlanId alphaZeroPlan)
      , gcExperimentHash = "contract-alphazero"
      , gcGeneration = generation
      , gcSelfPlayGames = 4
      , gcSamples = fromIntegral generation + 1000
      }

alphaZeroArena :: RlEvent
alphaZeroArena =
  RlArenaCompleted
    ArenaCompleted
      { acPlanId = planIdText (alphaZeroPlanId alphaZeroPlan)
      , acExperimentHash = "contract-alphazero"
      , acArenaGames = 6
      , acWinRate = 0.75
      }

setTuneObjective :: Double -> TuneEvent -> TuneEvent
setTuneObjective objective event =
  case event of
    TuneTrialFinished finished ->
      TuneTrialFinished finished {tfTuneObjective = objective}
    _ -> event

setSweepObjective :: Double -> TuneEvent -> TuneEvent
setSweepObjective objective event =
  case event of
    TuneSweepFinished finished ->
      TuneSweepFinished finished {sfBestObjective = objective}
    TuneSweepCompleted completed ->
      rebuildCompletedSweep
        ((scFinished completed) {sfBestObjective = objective})
        (scCompletedTraining completed)
    _ -> event

setSweepPromoted :: Word32 -> TuneEvent -> TuneEvent
setSweepPromoted promoted event =
  case event of
    TuneSweepFinished finished ->
      TuneSweepFinished finished {sfTrialsPromoted = promoted}
    TuneSweepCompleted completed ->
      rebuildCompletedSweep
        ((scFinished completed) {sfTrialsPromoted = promoted})
        (scCompletedTraining completed)
    _ -> event

rebuildCompletedSweep
  :: SweepFinished
  -> CompletedTraining
  -> TuneEvent
rebuildCompletedSweep finished proof =
  TuneSweepCompleted (expectRightValue (completeSweep finished proof))

setTunePlanId :: Text -> TuneEvent -> TuneEvent
setTunePlanId planId event =
  case event of
    TuneTrialFinished finished ->
      TuneTrialFinished finished {tfTunePlanId = planId}
    _ -> event

setArenaWinRate :: Double -> RlEvent -> RlEvent
setArenaWinRate winRate event =
  case event of
    RlArenaCompleted arena -> RlArenaCompleted arena {acWinRate = winRate}
    _ -> event

setAlphaZeroPlanId :: Text -> RlEvent -> RlEvent
setAlphaZeroPlanId planId event =
  case event of
    RlGenerationCompleted generation ->
      RlGenerationCompleted generation {gcPlanId = planId}
    _ -> event

ingestTuneEvents :: [TuneEvent] -> IO TuningCompletionProgress
ingestTuneEvents =
  foldEvents
    (ingestTuneEvent tuningPlan)
    (initialProgress (tuningCompletionContract tuningPlan))

ingestAlphaZeroEvents :: [RlEvent] -> IO AlphaZeroCompletionProgress
ingestAlphaZeroEvents =
  foldEvents
    (ingestAlphaZeroEvent alphaZeroPlan)
    (initialProgress (alphaZeroCompletionContract alphaZeroPlan))

foldEvents
  :: (Show error)
  => (progress -> event -> Either error progress)
  -> progress
  -> [event]
  -> IO progress
foldEvents ingest = go
 where
  go progress [] = pure progress
  go progress (event : rest) = do
    next <- expectRight (ingest progress event)
    go next rest

expectRight :: (Show error) => Either error value -> IO value
expectRight result =
  case result of
    Right value -> pure value
    Left err -> assertFailure ("expected Right, got Left " <> show err) >> error "unreachable"

expectSuccess :: (Show error) => Validation error value -> value
expectSuccess result =
  case result of
    Success value -> value
    Failure errors -> error ("expected Success, got Failure " <> show errors)

expectRightValue :: (Show error) => Either error value -> value
expectRightValue result =
  case result of
    Right value -> value
    Left err -> error ("expected Right, got Left " <> show err)

showText :: (Show value) => value -> Text
showText = Text.pack . show
