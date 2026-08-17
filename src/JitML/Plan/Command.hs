{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Raw protocol commands refined into the workload plans workers execute.
--
-- The wire records deliberately remain forgeable DTOs.  These functions are
-- the only bridge into the hidden resolved-plan types: producers attach a
-- canonical transport plus its derived identity, while consumers re-refine the
-- raw fields and transport and require byte-for-byte semantic agreement.
module JitML.Plan.Command
  ( prepareStartAlphaZeroRun
  , prepareStartTraining
  , prepareStartSweep
  , prepareStartSweepWithExecutionSpec
  , rawAlphaZeroPlanForCommand
  , rawSupervisedPlanForCommand
  , rawTuningPlanForCommand
  , validateStartAlphaZeroRun
  , validateStartTraining
  , validateStartSweep
  , validateStartSweepWithExecutionSpec
  )
where

import Control.Monad (unless)
import Data.Bifunctor (first)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Plan.Plan
  ( RawRunBudget (..)
  , RawRunRequest (..)
  , RunKindWitness (..)
  , RunPlacement (..)
  , Validation
  , planIdText
  , validationToEither
  )
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , RawAlphaZeroPlan (..)
  , RawSupervisedPlan (..)
  , RawTuningPlan (..)
  , SupervisedPlan
  , TuningPlan
  , alphaZeroPlanId
  , parseAlphaZeroPlanTransport
  , parseSupervisedPlanTransport
  , parseTuningPlanTransport
  , renderAlphaZeroPlanTransport
  , renderSupervisedPlanTransport
  , renderTuningPlanTransport
  , resolveAlphaZeroPlan
  , resolveSupervisedPlan
  , resolveTuningPlan
  , resolveTuningPlanWithExecutionSpec
  , supervisedPlanId
  , tuningPlanExecutionSpec
  , tuningPlanId
  )
import JitML.Proto.Rl (StartAlphaZeroRun (..))
import JitML.Proto.Training (StartTraining (..))
import JitML.Proto.Tune (StartSweep (..))
import JitML.Substrate (Substrate (..), renderSubstrate, substrateHasClusterCompute)
import JitML.Tune.Catalog (TuningExecutionSpec)

prepareStartTraining
  :: StartTraining
  -> Either Text (StartTraining, SupervisedPlan)
prepareStartTraining raw = do
  plan <- resolveValidation (resolveSupervisedPlan (rawSupervisedPlanForCommand raw))
  let prepared =
        raw
          { stPlanId = planIdText (supervisedPlanId plan)
          , stResolvedPlan = renderSupervisedPlanTransport plan
          }
  pure (prepared, plan)

validateStartTraining :: StartTraining -> Either Text SupervisedPlan
validateStartTraining command = do
  expected <- resolveValidation (resolveSupervisedPlan (rawSupervisedPlanForCommand command))
  transported <-
    resolveValidation (parseSupervisedPlanTransport (stResolvedPlan command))
  requireEqual
    "supervised plan-id"
    (planIdText (supervisedPlanId expected))
    (stPlanId command)
  requireEqual "supervised transported plan" expected transported
  requireEqual
    "supervised canonical transport"
    (renderSupervisedPlanTransport expected)
    (stResolvedPlan command)
  pure expected

rawSupervisedPlanForCommand :: StartTraining -> RawSupervisedPlan
rawSupervisedPlanForCommand command =
  RawSupervisedPlan
    RawRunRequest
      { rawRunVersion = 1
      , rawRunKind = SupervisedTrainingWitness
      , rawRunExperimentId = stExperimentHash command
      , rawRunSubjectId = stDhallObjectKey command
      , rawRunArtifactId = stDhallObjectKey command
      , rawRunTopicId = commandTopic "training" (stSubstrate command)
      , rawRunSubstrate = stSubstrate command
      , rawRunPlacement = placementFor (stSubstrate command)
      , rawRunSeeds = [stSeed command]
      , rawRunBudget =
          RawSupervisedBudget
            (toInteger (stEpochs command))
            (toInteger (stTrainingExamples command))
            (toInteger (stEvaluationExamples command))
            (toInteger (stBatchSize command))
            ( supervisedOptimizerUpdates
                (toInteger (stEpochs command))
                (toInteger (stTrainingExamples command))
                (toInteger (stBatchSize command))
            )
      }

supervisedOptimizerUpdates :: Integer -> Integer -> Integer -> Integer
supervisedOptimizerUpdates epochs trainingExamples batchExamples
  | batchExamples <= 0 = 0
  | otherwise =
      epochs * ((trainingExamples + batchExamples - 1) `div` batchExamples)

prepareStartSweep :: StartSweep -> Either Text (StartSweep, TuningPlan)
prepareStartSweep raw = do
  plan <- resolveValidation (resolveTuningPlan (rawTuningPlanForCommand raw))
  pure (attachTuningPlan raw plan, plan)

-- | Prepare a tuning command from the complete normalized execution spec.
-- Dhall-backed producers use this entrypoint so search spaces, objectives, and
-- scheduler/pruner parameters participate in both refinement and 'PlanId'.
prepareStartSweepWithExecutionSpec
  :: TuningExecutionSpec
  -> StartSweep
  -> Either Text (StartSweep, TuningPlan)
prepareStartSweepWithExecutionSpec executionSpec raw = do
  plan <-
    resolveValidation
      ( resolveTuningPlanWithExecutionSpec
          executionSpec
          (rawTuningPlanForCommand raw)
      )
  pure (attachTuningPlan raw plan, plan)

attachTuningPlan :: StartSweep -> TuningPlan -> StartSweep
attachTuningPlan raw plan =
  let prepared =
        raw
          { ssPlanId = planIdText (tuningPlanId plan)
          , ssResolvedPlan = renderTuningPlanTransport plan
          }
   in prepared

validateStartSweep :: StartSweep -> Either Text TuningPlan
validateStartSweep command = do
  transported <- resolveValidation (parseTuningPlanTransport (ssResolvedPlan command))
  validateTransportedStartSweep
    (tuningPlanExecutionSpec transported)
    command
    transported

-- | Validate a tuning command against an independently retained normalized
-- execution spec.  This is the producer/config-agreement gate; ordinary
-- workers can use 'validateStartSweep', whose canonical transport already
-- carries and re-refines that same complete spec.
validateStartSweepWithExecutionSpec
  :: TuningExecutionSpec
  -> StartSweep
  -> Either Text TuningPlan
validateStartSweepWithExecutionSpec executionSpec command = do
  transported <- resolveValidation (parseTuningPlanTransport (ssResolvedPlan command))
  requireEqual
    "tuning execution spec"
    executionSpec
    (tuningPlanExecutionSpec transported)
  validateTransportedStartSweep executionSpec command transported

validateTransportedStartSweep
  :: TuningExecutionSpec
  -> StartSweep
  -> TuningPlan
  -> Either Text TuningPlan
validateTransportedStartSweep executionSpec command transported = do
  expected <-
    resolveValidation
      ( resolveTuningPlanWithExecutionSpec
          executionSpec
          (rawTuningPlanForCommand command)
      )
  requireEqual "tuning plan-id" (planIdText (tuningPlanId expected)) (ssPlanId command)
  requireEqual "tuning transported plan" expected transported
  requireEqual
    "tuning canonical transport"
    (renderTuningPlanTransport expected)
    (ssResolvedPlan command)
  pure expected

rawTuningPlanForCommand :: StartSweep -> RawTuningPlan
rawTuningPlanForCommand command =
  RawTuningPlan
    { rawTuningRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = HyperparameterTuningWitness
          , rawRunExperimentId = ssExperimentHash command
          , rawRunSubjectId = ssDhallObjectKey command
          , rawRunArtifactId = ssDhallObjectKey command
          , rawRunTopicId = commandTopic "tune" (ssSubstrate command)
          , rawRunSubstrate = ssSubstrate command
          , rawRunPlacement = placementFor (ssSubstrate command)
          , rawRunSeeds = [ssSweepSeed command]
          , rawRunBudget =
              RawTuningBudget
                (toInteger (ssTrialBudget command))
                (toInteger (ssParallelism command))
                (toInteger (ssPromotions command))
                (toInteger (ssBudgetPerTrial command))
          }
    , rawTuningSampler = ssSampler command
    , rawTuningScheduler = ssScheduler command
    , rawTuningPruner = ssPruner command
    }

prepareStartAlphaZeroRun
  :: StartAlphaZeroRun
  -> Either Text (StartAlphaZeroRun, AlphaZeroPlan)
prepareStartAlphaZeroRun raw = do
  plan <- resolveValidation (resolveAlphaZeroPlan (rawAlphaZeroPlanForCommand raw))
  let prepared =
        raw
          { sazPlanId = planIdText (alphaZeroPlanId plan)
          , sazResolvedPlan = renderAlphaZeroPlanTransport plan
          }
  pure (prepared, plan)

validateStartAlphaZeroRun :: StartAlphaZeroRun -> Either Text AlphaZeroPlan
validateStartAlphaZeroRun command = do
  expected <- resolveValidation (resolveAlphaZeroPlan (rawAlphaZeroPlanForCommand command))
  transported <- resolveValidation (parseAlphaZeroPlanTransport (sazResolvedPlan command))
  requireEqual
    "AlphaZero plan-id"
    (planIdText (alphaZeroPlanId expected))
    (sazPlanId command)
  requireEqual "AlphaZero transported plan" expected transported
  requireEqual
    "AlphaZero canonical transport"
    (renderAlphaZeroPlanTransport expected)
    (sazResolvedPlan command)
  pure expected

rawAlphaZeroPlanForCommand :: StartAlphaZeroRun -> RawAlphaZeroPlan
rawAlphaZeroPlanForCommand command =
  RawAlphaZeroPlan
    { rawAlphaZeroRun =
        RawRunRequest
          { rawRunVersion = 1
          , rawRunKind = AlphaZeroSelfPlayWitness
          , rawRunExperimentId = sazExperimentHash command
          , rawRunSubjectId = sazGame command
          , rawRunArtifactId = "alphazero/" <> sazExperimentHash command
          , rawRunTopicId = commandTopic "rl" (sazSubstrate command)
          , rawRunSubstrate = sazSubstrate command
          , rawRunPlacement = placementFor (sazSubstrate command)
          , rawRunSeeds = [sazSeed command]
          , rawRunBudget =
              RawAlphaZeroBudget
                (toInteger (sazGenerations command))
                (toInteger (sazSelfPlayGames command))
                (toInteger (sazMctsSimulationsPerMove command))
                (toInteger (sazMaxPlies command))
                (toInteger (sazOptimizerUpdates command))
                (toInteger (sazArenaGames command))
          }
    , rawAlphaZeroGame = sazGame command
    }

-- | Where a substrate's numerical work runs, read off the one profile rather
-- than restated per substrate (Sprint `79.1`).
placementFor :: Substrate -> RunPlacement
placementFor substrate
  | substrateHasClusterCompute substrate = ClusterRun
  | otherwise = HostRun

commandTopic :: Text -> Substrate -> Text
commandTopic domain substrate =
  domain <> ".command." <> renderSubstrate substrate

resolveValidation
  :: (Show error)
  => Validation (NonEmpty error) value
  -> Either Text value
resolveValidation =
  first (Text.pack . show) . validationToEither

requireEqual :: (Eq value, Show value) => Text -> value -> value -> Either Text ()
requireEqual label expected observed =
  unless (expected == observed) $
    Left
      ( label
          <> " mismatch: expected "
          <> Text.pack (show expected)
          <> ", observed "
          <> Text.pack (show observed)
      )
