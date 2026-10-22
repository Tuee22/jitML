{-# LANGUAGE OverloadedStrings #-}

-- | Pure recorded-data consistency only. This validator fetches nothing and
-- cannot construct a Store admission, producer origin or restored trainer.
module JitML.Checkpoint.ArsHostPhysical
  ( validateArsHostCheckpointData
  , validateArsHostCheckpointRecordedData
  , validateGenericArsHostCompletionData
  ) where

import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (find)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.WeightCodec qualified as Weight
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as Reference
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.ProductBudget qualified as RlBudget
import JitML.Training.Budget qualified as Budget

-- Equality of JMW1 bytes includes every signed-zero bit. The same-runtime
-- numerical replay does not establish portable libm identity or fresh origin.
validateArsHostCheckpointData
  :: Text
  -> Budget.CompletedTraining
  -> BS.ByteString
  -> Reference.ArsHostReference
  -> Trace.ArsHostTrace
  -> Either Text ()
validateArsHostCheckpointData experiment completed finalBytes reference trace = do
  validateArsHostCheckpointRecordedData experiment completed finalBytes reference trace
  -- Preserve every original same-runtime arithmetic check on live admission.
  Trace.validateArsHostTraceLocal trace

-- | Portable recorded consistency only. This verifies the exact trace/ref,
-- canonical plan/budget, counters and complete initial/final JMW1 bytes. It
-- deliberately does not regenerate host arithmetic or assert fresh runtime,
-- device, origin, Store admission, parent authority or qualification. A later
-- lane reader must separately authenticate the ORIGINAL parent observations.
validateArsHostCheckpointRecordedData
  :: Text
  -> Budget.CompletedTraining
  -> BS.ByteString
  -> Reference.ArsHostReference
  -> Trace.ArsHostTrace
  -> Either Text ()
validateArsHostCheckpointRecordedData experiment completed finalBytes reference trace =
  case Matrix.productRowForExperimentHash experiment of
    Nothing -> validateGenericArsHostCheckpointRecordedData experiment completed finalBytes reference trace
    Just _ -> validateCanonicalArsHostCheckpointRecordedData experiment completed finalBytes reference trace

-- The original canonical validator body is preserved literally below.
validateCanonicalArsHostCheckpointRecordedData
  :: Text
  -> Budget.CompletedTraining
  -> BS.ByteString
  -> Reference.ArsHostReference
  -> Trace.ArsHostTrace
  -> Either Text ()
validateCanonicalArsHostCheckpointRecordedData experiment completed finalBytes reference trace = do
  recorded <- Budget.completedTrainingExecutionProvenance completed
  require
    (recorded == Just (ArsHostLinearExecution reference))
    "ARS physical completion recorded provenance differs from its exact reference"
  Trace.validateArsHostTraceReference reference trace
  let context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext trace)
  require
    (Trace.rawArsHostExperiment context == experiment)
    "ARS physical trace experiment differs from the admitted checkpoint"
  -- The completed PlanId belongs to the WHOLE canonical Matrix singleton.
  -- Its compiled recipe has a different identity and is derived from the
  -- checked current row/lane, never attached by relabeling the completion.
  batch <- Cohort.mkCanonicalNativeRlCohorts (Reference.arsHostReferenceLane reference)
  cohort <-
    maybe
      (Left "ARS physical trace row is absent from the canonical native batch")
      Right
      ( find
          ((== Trace.rawArsHostRowId context) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  let serving = Cohort.nativeRlCohortServingChild cohort
      singleton = Cohort.nativeRlSeedPlanSingleton serving
  require
    (Singleton.nativeSingletonPlanId singleton == Budget.completedTrainingPlanId completed)
    "ARS physical whole canonical serving PlanId differs from completed training"
  require
    (Cohort.nativeRlSeedPlanTrainingBudget serving == Budget.completedTrainingBudget completed)
    "ARS physical whole canonical serving budget differs from completed training"
  require
    (Singleton.nativeSingletonExperiment singleton == experiment)
    "ARS physical canonical serving experiment differs from the admitted checkpoint"
  plan <-
    maybe
      (Left "ARS physical canonical serving child has no compiled RETURN recipe")
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn serving)
  Trace.validateArsHostTracePlan plan trace
  let actual = Trace.arsHostTraceObservation trace
      counters = Common.rawTrainerCounters actual
      initial = Weight.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams actual))
      final = Weight.encodeJmw1 (VU.toList (Common.rawTrainerFinalParams actual))
  require
    ( Reference.arsHostReferencePlanId reference == Budget.completedTrainingPlanId completed
        && Trace.rawArsHostPlanId context == Plan.planIdText (Budget.completedTrainingPlanId completed)
    )
    "ARS physical trace PlanId differs from completed training"
  require
    ( Common.observedEnvironmentTransitionCount counters
        == Budget.completedTrainingObservedUnits completed
        && Common.observedOptimizerUpdateCount counters == Budget.completedTrainingUpdateCount completed
    )
    "ARS physical trace counters differ from completed training"
  require
    (Weight.jmw1ContentSha initial == Budget.completedTrainingInitialWeightHash completed)
    "ARS physical initial JMW1 differs from completed training"
  require
    ( LBS.toStrict final == finalBytes
        && Weight.jmw1ContentSha final == Budget.completedTrainingFinalWeightHash completed
    )
    "ARS physical final JMW1 bytes differ from trace or completed training"
  case Budget.completedTrainingProductScenarioInvocation completed of
    Nothing ->
      require
        (Trace.rawArsHostExecutionBinding context == "direct-local-attempt-v1")
        "ARS physical direct completion has a foreign execution binding"
    Just invocation -> do
      require
        (Trace.rawArsHostExecutionBinding context == "product-scenario-invocation-v1")
        "ARS physical scenario completion has no scenario execution binding"
      require
        ( Reference.arsHostReferenceInvocationSha256 reference
            == Budget.productScenarioInvocationDigest invocation
            && Reference.arsHostReferenceExecutableSha256 reference
              == Budget.productScenarioInvocationExecutableSha256 invocation
            && Reference.arsHostReferencePlanId reference == Budget.productScenarioInvocationPlanId invocation
            && Reference.arsHostReferenceLane reference == Budget.productScenarioInvocationSubstrate invocation
            && Trace.rawArsHostRowId context == Budget.productScenarioInvocationRowId invocation
        )
        "ARS physical trace differs from the exact scenario invocation"
 where
  require predicate reason = unless predicate (Left reason)

-- Closed generic completion identity, ordinary DATA only. It grants no
-- producer, physical admission, source authentication or qualification.
validateGenericArsHostCompletionData
  :: Text -> Budget.CompletedTraining -> Either Text RlBudget.CompiledRlPlan
validateGenericArsHostCompletionData experiment completed = do
  require
    (case Matrix.productRowForExperimentHash experiment of Nothing -> True; Just _ -> False)
    "generic ARS host completion cannot occupy any canonical ProductRow experiment"
  plan <-
    maybe
      (Left "generic ARS host completion has no exact compiled RL plan")
      Right
      (Budget.completedTrainingRlPlan completed)
  rebound <- Budget.bindCompletedTrainingToRlPlan plan completed
  require (rebound == completed) "generic ARS host completion compiled binding differs"
  require
    (RlBudget.compiledRlTrainerKind plan == "ars")
    "generic host completion compiled trainer is not ARS"
  require
    (isNothing (Budget.completedTrainingProductScenarioInvocation completed))
    "generic ARS host completion cannot borrow a ProductScenario invocation"
  case Budget.completedTrainingExecutionProvenance completed of
    Right (Just (ArsHostLinearExecution reference)) ->
      require
        (Reference.arsHostReferencePlanId reference == Budget.completedTrainingPlanId completed)
        "generic ARS host reference PlanId differs from its compiled completion"
    _ -> Left "generic ARS host completion requires recorded host linear provenance"
  pure plan
 where
  require predicate reason = unless predicate (Left reason)

validateGenericArsHostCheckpointRecordedData
  :: Text
  -> Budget.CompletedTraining
  -> BS.ByteString
  -> Reference.ArsHostReference
  -> Trace.ArsHostTrace
  -> Either Text ()
validateGenericArsHostCheckpointRecordedData experiment completed finalBytes reference trace = do
  plan <- validateGenericArsHostCompletionData experiment completed
  recorded <- Budget.completedTrainingExecutionProvenance completed
  require
    (recorded == Just (ArsHostLinearExecution reference))
    "generic ARS physical completion differs from its exact reference"
  Trace.validateArsHostTraceReference reference trace
  Trace.validateArsHostTracePlan plan trace
  let context = Trace.arsHostContextToRaw (Trace.arsHostTraceContext trace)
      actual = Trace.arsHostTraceObservation trace
      counters = Common.rawTrainerCounters actual
      initial = Weight.encodeJmw1 (VU.toList (Common.rawTrainerInitialParams actual))
      final = Weight.encodeJmw1 (VU.toList (Common.rawTrainerFinalParams actual))
  require
    ( Trace.rawArsHostExperiment context == experiment
        && Trace.rawArsHostPlanId context == RlBudget.compiledRlPlanId plan
        && Trace.rawArsHostExecutionBinding context == "generic-compiled-plan-attempt-v1"
        && Trace.rawArsHostRowId context == "generic-ars/" <> RlBudget.compiledRlEnvironment plan
    )
    "generic ARS physical trace differs from its exact experiment/compiled identity"
  require
    ( Common.observedEnvironmentTransitionCount counters
        == Budget.completedTrainingObservedUnits completed
        && Common.observedOptimizerUpdateCount counters == Budget.completedTrainingUpdateCount completed
    )
    "generic ARS physical trace counters differ from completed training"
  require
    (Weight.jmw1ContentSha initial == Budget.completedTrainingInitialWeightHash completed)
    "generic ARS physical initial JMW1 differs from completed training"
  require
    ( LBS.toStrict final == finalBytes
        && Weight.jmw1ContentSha final == Budget.completedTrainingFinalWeightHash completed
    )
    "generic ARS physical final JMW1 bytes differ from trace or completed training"
 where
  require predicate reason = unless predicate (Left reason)
