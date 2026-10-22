{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Canonical child association plus actual numerical phase ordering only.
-- No producer/provider origin, durability, learning or Store qualification.
module JitML.Product.NativePreparedNeuralAttempt
  ( NativeNeuralRowData
  , NativeNeuralChildData
  , NativePrepared
  , NativeEffectivePrepared
  , NativeReadyToTrain
  , NativePendingFinalEvaluation
  , NativeReturnedData
  , NativeEvaluatedData
  , NativeEvaluationData (..)
  , NativeAttemptStage (..)
  , NativeFailureKind (..)
  , NativeAttemptFailure
  , NativePreparationResult (..)
  , NativeInitializationResult (..)
  , NativeInitialEvaluationResult (..)
  , NativeTrainingResult (..)
  , NativeFinalEvaluationResult (..)
  , selectNativeNeuralRowData
  , selectNativeNeuralChildData
  , nativeNeuralRowId
  , nativeNeuralRowBatch
  , nativeNeuralRowCohort
  , nativeNeuralRowReturnSpec
  , nativeNeuralRowHerSchedule
  , nativeNeuralChildRow
  , nativeNeuralChildSeedPlan
  , nativeNeuralChildCompiledPlan
  , prepareNativeNeuralAttempt
  , nativePreparedSnapshot
  , nativePreparedStage
  , completeNativeNeuralInitialization
  , nativeEffectiveSnapshot
  , nativeEffectiveColdSnapshot
  , evaluateNativeNeuralInitial
  , nativeReadyInitialEvaluation
  , nativeReadySnapshot
  , continueNativeNeuralTraining
  , nativeReturnedData
  , nativeReturnedPolicy
  , nativeReturnedLowData
  , nativeReturnedInitialEvaluation
  , nativeReturnedSnapshot
  , nativeReturnedColdSnapshot
  , nativeReturnedChild
  , evaluateNativeNeuralFinal
  , nativeEvaluatedReturnedData
  , nativeEvaluatedFinalEvaluation
  , validateNativeEvaluationData
  , nativeFailureStage
  , nativeFailureKind
  , nativeFailureDetail
  , nativeFailureChild
  , nativeFailureSnapshot
  , nativeFailureColdSnapshot
  , nativeFailureInitialEvaluation
  , nativeFailureEvaluation
  , nativeFailureLowFailure
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless, void)
import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)

import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice)
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.NativeHerEvaluation qualified as Her
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerConfiguration qualified as Config
import JitML.RL.TrainerObservation qualified as Observation

-- Both alternatives are checked case DATA, not sampled by evaluation/training.
data FixedCases = ReturnCases ReturnRef.NativeReturnReferenceSpec | HerCases HerRef.NativeHerGoalSchedule
  deriving stock (Eq, Show)
data NativeNeuralRowData
  = NativeNeuralRowData Cohort.NativeRlCohortBatch Cohort.NativeRlCohortPlan FixedCases
  deriving stock (Eq, Show)
data NativeNeuralChildData
  = NativeNeuralChildData NativeNeuralRowData Cohort.NativeRlSeedPlan Budget.CompiledRlPlan
  deriving stock (Eq, Show)

-- Private action-bearing constructors and labels; no Read/Generic/restore.
data NativePrepared
  = NativePrepared NativeNeuralChildData MlpDevice Low.PreparedNeuralAttempt SingleUse.SingleUse
data NativeEffectivePrepared
  = NativeEffectivePrepared
      NativeNeuralChildData
      MlpDevice
      Low.EffectiveNeuralAttempt
      SingleUse.SingleUse
data NativeReadyToTrain
  = NativeReadyToTrain
      NativeNeuralChildData
      MlpDevice
      Low.EffectiveNeuralAttempt
      NativeEvaluationData
      SingleUse.SingleUse
data NativeReturnedData
  = NativeReturnedData
      NativeNeuralChildData
      Low.NeuralSnapshot
      (Maybe Low.NeuralSnapshot)
      NativeEvaluationData
      Low.NeuralReturnedData
data NativePendingFinalEvaluation
  = NativePendingFinalEvaluation NativeReturnedData MlpDevice SingleUse.SingleUse
data NativeEvaluatedData = NativeEvaluatedData NativeReturnedData NativeEvaluationData

-- Public observations are data only; they cannot enter any capability factory.
data NativeEvaluationData
  = NativeReturnEvaluation Return.RawNativeReturnEvaluation
  | NativeHerEvaluation Her.RawNativeHerEvaluation
  deriving stock (Eq, Show)
data NativeAttemptStage
  = NativeSelection
  | NativePreparation
  | NativeInitialization
  | NativeInitialEvaluation
  | NativeTraining
  | NativeReturnBinding
  | NativeFinalEvaluation
  deriving stock (Eq, Show)
data NativeFailureKind
  = NativeContextRejected
  | NativeLowRejected
  | NativeEvaluationRejected
  | NativeSynchronousFailure
  | NativeAlreadyConsumed
  deriving stock (Eq, Show)

-- Every retained optional value was observed safely, or came from a prior
-- closed stage that had already materialized it. No poisonous raw handle.
data Known
  = Known
      (Maybe NativeNeuralChildData)
      (Maybe Low.NeuralSnapshot)
      (Maybe Low.NeuralSnapshot)
      (Maybe NativeEvaluationData)
      (Maybe NativeEvaluationData)
      (Maybe Low.NeuralAttemptFailure)
data NativeAttemptFailure = NativeAttemptFailure NativeAttemptStage NativeFailureKind Text Known

data NativePreparationResult
  = NativePreparationFailed NativeAttemptFailure
  | NativePreparationReady NativePrepared
data NativeInitializationResult
  = NativeInitializationFailed NativeAttemptFailure
  | NativeInitializationReady NativeEffectivePrepared
data NativeInitialEvaluationResult
  = NativeInitialEvaluationFailed NativeAttemptFailure
  | NativeInitialEvaluationReady NativeReadyToTrain
data NativeTrainingResult
  = NativeTrainingFailed NativeAttemptFailure
  | NativeTrainingReturnedButUnmaterializable NativeAttemptFailure
  | NativeTrainingBindingFailed NativeReturnedData NativeAttemptFailure
  | NativeTrainingReturned NativePendingFinalEvaluation
data NativeFinalEvaluationResult
  = NativeFinalEvaluationFailed NativeReturnedData (Maybe NativeEvaluationData) NativeAttemptFailure
  | NativeFinalEvaluationComplete NativeEvaluatedData

emptyKnown :: Known
emptyKnown = Known Nothing Nothing Nothing Nothing Nothing Nothing

nativeNeuralRowId :: NativeNeuralRowData -> Text
nativeNeuralRowId = Matrix.rowId . Cohort.nativeRlCohortPlanRow . nativeNeuralRowCohort
nativeNeuralRowBatch :: NativeNeuralRowData -> Cohort.NativeRlCohortBatch
nativeNeuralRowBatch (NativeNeuralRowData batch _ _) = batch
nativeNeuralRowCohort :: NativeNeuralRowData -> Cohort.NativeRlCohortPlan
nativeNeuralRowCohort (NativeNeuralRowData _ cohort _) = cohort
nativeNeuralRowReturnSpec :: NativeNeuralRowData -> Maybe ReturnRef.NativeReturnReferenceSpec
nativeNeuralRowReturnSpec (NativeNeuralRowData _ _ cases) = case cases of ReturnCases spec -> Just spec; HerCases _ -> Nothing
nativeNeuralRowHerSchedule :: NativeNeuralRowData -> Maybe HerRef.NativeHerGoalSchedule
nativeNeuralRowHerSchedule (NativeNeuralRowData _ _ cases) = case cases of ReturnCases _ -> Nothing; HerCases schedule -> Just schedule
nativeNeuralChildRow :: NativeNeuralChildData -> NativeNeuralRowData
nativeNeuralChildRow (NativeNeuralChildData row _ _) = row
nativeNeuralChildSeedPlan :: NativeNeuralChildData -> Cohort.NativeRlSeedPlan
nativeNeuralChildSeedPlan (NativeNeuralChildData _ child _) = child
nativeNeuralChildCompiledPlan :: NativeNeuralChildData -> Budget.CompiledRlPlan
nativeNeuralChildCompiledPlan (NativeNeuralChildData _ _ compiled) = compiled
childCases :: NativeNeuralChildData -> FixedCases
childCases (NativeNeuralChildData (NativeNeuralRowData _ _ cases) _ _) = cases

-- | Only a whole checked batch can create this data selection. There is no
-- constructor from an individual cohort, arbitrary plan or low capability.
selectNativeNeuralRowData
  :: Cohort.NativeRlCohortBatch -> Text -> Either NativeAttemptFailure NativeNeuralRowData
selectNativeNeuralRowData batch rowId = do
  cohort <-
    maybe
      (selectionFailure "native neural row is absent from the checked batch")
      Right
      ( find
          ((== rowId) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  compiled <-
    maybe
      (selectionFailure "native neural selection excludes AlphaZero")
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn (Cohort.nativeRlCohortServingChild cohort))
  unless
    (Budget.compiledRlTrainerKind compiled `elem` Config.knownNeuralTrainerKinds)
    (selectionFailure "native neural selection excludes non-neural ARS training")
  cases <- case Cohort.nativeRlCohortPlanProjection cohort of
    Matrix.SomeProductProjection Plan.ReinforcementLearningWitness projection ->
      case Matrix.productProjectionDescriptor projection of
        descriptor@Matrix.RlProductDescriptor {} ->
          if Budget.compiledRlTrainerKind compiled == "her"
            then do
              spec <- selectionEither HerRef.canonicalNativeHerReferenceSpec
              unless
                (rowId == HerRef.nativeHerSpecRowId spec)
                (selectionFailure "native HER row differs from the fixed reference context")
              HerCases <$> selectionEither (HerRef.generateNativeHerGoalSchedule spec)
            else do
              spec <-
                selectionEither
                  ( ReturnRef.canonicalNativeReturnSpec
                      (Matrix.rlDescriptorAlgorithm descriptor)
                      (Matrix.rlDescriptorEnvironment descriptor)
                  )
              unless
                (ReturnRef.nativeReturnSpecRowId spec == rowId)
                (selectionFailure "native return row differs from the fixed reference context")
              pure (ReturnCases spec)
    _ -> selectionFailure "native neural selection requires a canonical RL projection"
  pure (NativeNeuralRowData batch cohort cases)

selectNativeNeuralChildData
  :: NativeNeuralRowData -> Cohort.NativeSeedIndex -> Either NativeAttemptFailure NativeNeuralChildData
selectNativeNeuralChildData row index = do
  child <-
    maybe
      (selectionFailure "native neural child is absent from its checked cohort")
      Right
      ( find
          ((== index) . Cohort.nativeRlSeedPlanIndex)
          (Cohort.nativeRlCohortPlanChildren (nativeNeuralRowCohort row))
      )
  compiled <-
    maybe
      (selectionFailure "native neural child has no compiled return recipe")
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn child)
  unless
    (Budget.compiledRlTrainerKind compiled `elem` Config.knownNeuralTrainerKinds)
    (selectionFailure "native neural child has an excluded trainer")
  pure (NativeNeuralChildData row child compiled)

selectionFailure :: Text -> Either NativeAttemptFailure value
selectionFailure reason = Left (NativeAttemptFailure NativeSelection NativeContextRejected reason emptyKnown)
selectionEither :: Either Text value -> Either NativeAttemptFailure value
selectionEither = either selectionFailure Right

prepareNativeNeuralAttempt :: NativeNeuralChildData -> MlpDevice -> IO NativePreparationResult
prepareNativeNeuralAttempt child device = do
  observed <- newIORef emptyKnown
  attempted <- tryAny $ do
    _ <- evaluate (forceSelection child)
    let known = Known (Just child) Nothing Nothing Nothing Nothing Nothing
    writeIORef observed known
    prepared <- Low.prepareNeuralAttempt device (nativeNeuralChildCompiledPlan child)
    case prepared of
      Low.NeuralPreparationFailed failure -> pure (NativePreparationFailed (lowFailure NativePreparation known failure))
      Low.NeuralPreparationReady actual ->
        NativePreparationReady . NativePrepared child device actual <$> SingleUse.newSingleUse
  case attempted of
    Right result -> pure result
    Left exception -> do
      known <- readIORef observed
      NativePreparationFailed <$> exceptionFailure NativePreparation known exception

nativePreparedSnapshot :: NativePrepared -> Low.NeuralSnapshot
nativePreparedSnapshot (NativePrepared _ _ prepared _) = Low.neuralPreparedSnapshot prepared
nativePreparedStage :: NativePrepared -> Low.NeuralPreparationStage
nativePreparedStage (NativePrepared _ _ prepared _) = Low.neuralPreparationStage prepared
nativeEffectiveSnapshot :: NativeEffectivePrepared -> Low.NeuralSnapshot
nativeEffectiveSnapshot (NativeEffectivePrepared _ _ prepared _) = Low.neuralEffectiveSnapshot prepared
nativeEffectiveColdSnapshot :: NativeEffectivePrepared -> Maybe Low.NeuralSnapshot
nativeEffectiveColdSnapshot (NativeEffectivePrepared _ _ prepared _) = Low.neuralEffectiveColdSnapshot prepared

completeNativeNeuralInitialization :: NativePrepared -> IO NativeInitializationResult
completeNativeNeuralInitialization (NativePrepared child device prepared guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let snapshot = Low.neuralPreparedSnapshot prepared
      cold = if Low.neuralPreparationStage prepared == Low.NeuralCold then Just snapshot else Nothing
      known = Known (Just child) (Just snapshot) cold Nothing Nothing Nothing
  if not claimed
    then pure (NativeInitializationFailed (consumed NativeInitialization known))
    else do
      attempted <- tryAny $ do
        initialized <- Low.initializePreparedNeural prepared
        case initialized of
          Low.NeuralInitializationFailed failure -> pure (NativeInitializationFailed (lowFailure NativeInitialization known failure))
          Low.NeuralInitializationReady actual ->
            NativeInitializationReady . NativeEffectivePrepared child device actual <$> SingleUse.newSingleUse
      case attempted of
        Right result -> pure result
        Left exception -> NativeInitializationFailed <$> exceptionFailure NativeInitialization known exception

nativeReadyInitialEvaluation :: NativeReadyToTrain -> NativeEvaluationData
nativeReadyInitialEvaluation (NativeReadyToTrain _ _ _ initial _) = initial
nativeReadySnapshot :: NativeReadyToTrain -> Low.NeuralSnapshot
nativeReadySnapshot (NativeReadyToTrain _ _ prepared _ _) = Low.neuralEffectiveSnapshot prepared

evaluateNativeNeuralInitial :: NativeEffectivePrepared -> IO NativeInitialEvaluationResult
evaluateNativeNeuralInitial (NativeEffectivePrepared child device prepared guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let snapshot = Low.neuralEffectiveSnapshot prepared
      known =
        Known
          (Just child)
          (Just snapshot)
          (Low.neuralEffectiveColdSnapshot prepared)
          Nothing
          Nothing
          Nothing
  if not claimed
    then pure (NativeInitialEvaluationFailed (consumed NativeInitialEvaluation known))
    else do
      evaluated <-
        evaluateClosed
          NativeInitialEvaluation
          known
          child
          device
          (Low.neuralSnapshotConfiguration snapshot)
          (Low.neuralSnapshotInitialParams snapshot)
      case evaluated of
        Left failure -> pure (NativeInitialEvaluationFailed failure)
        Right initial -> do
          allocated <- tryAny SingleUse.newSingleUse
          case allocated of
            Left exception ->
              NativeInitialEvaluationFailed
                <$> exceptionFailure NativeInitialEvaluation (withEvaluation (Just initial) known) exception
            Right next -> pure (NativeInitialEvaluationReady (NativeReadyToTrain child device prepared initial next))

continueNativeNeuralTraining :: NativeReadyToTrain -> IO NativeTrainingResult
continueNativeNeuralTraining (NativeReadyToTrain child device prepared initial guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let snapshot = Low.neuralEffectiveSnapshot prepared
      cold = Low.neuralEffectiveColdSnapshot prepared
      known = Known (Just child) (Just snapshot) cold (Just initial) Nothing Nothing
      returnedData = NativeReturnedData child snapshot cold initial
  if not claimed
    then pure (NativeTrainingFailed (consumed NativeTraining known))
    else do
      materialized <- newIORef Nothing
      stage <- newIORef NativeTraining
      attempted <- tryAny $ do
        result <- Low.runPreparedNeuralRaw prepared
        case result of
          Low.NeuralTrainingFailed failure -> pure (NativeTrainingFailed (lowFailure NativeTraining known failure))
          Low.NeuralReturnedButUnmaterializable failure -> pure (NativeTrainingReturnedButUnmaterializable (lowFailure NativeTraining known failure))
          Low.NeuralReturnedBindingFailed actual failure ->
            pure
              (NativeTrainingBindingFailed (returnedData actual) (lowFailure NativeReturnBinding known failure))
          Low.NeuralTrainingReturned pending -> do
            let actual = Low.neuralPendingReturnedData pending
                retained = returnedData actual
            writeIORef materialized (Just retained)
            writeIORef stage NativeReturnBinding
            checked <- forceEitherText (validateReturnedChild child actual)
            case checked of
              Left reason ->
                pure
                  ( NativeTrainingBindingFailed
                      retained
                      (NativeAttemptFailure NativeReturnBinding NativeContextRejected reason known)
                  )
              Right () ->
                NativeTrainingReturned . NativePendingFinalEvaluation retained device <$> SingleUse.newSingleUse
      case attempted of
        Right result -> pure result
        Left exception -> do
          at <- readIORef stage
          failure <- exceptionFailure at known exception
          actual <- readIORef materialized
          pure (maybe (NativeTrainingFailed failure) (`NativeTrainingBindingFailed` failure) actual)

-- Reuse the low105-field bitwise predicate. No second recipe/projection table.
validateReturnedChild :: NativeNeuralChildData -> Low.NeuralReturnedData -> Either Text ()
validateReturnedChild child actual = do
  let expected = nativeNeuralChildCompiledPlan child
      returned = Low.neuralReturnedPlan actual
  require
    ( returned == expected
        && Budget.renderCompiledRlPlanTransport returned == Budget.renderCompiledRlPlanTransport expected
    )
    "native neural returned complete compiled child differs"
  Low.validateNeuralReturnedBinding
    (Low.neuralReturnedExpectedConfiguration actual)
    (Low.neuralReturnedExpectedInitialParams actual)
    (Low.neuralReturnedPolicy actual)

nativeReturnedData :: NativePendingFinalEvaluation -> NativeReturnedData
nativeReturnedData (NativePendingFinalEvaluation actual _ _) = actual
nativeReturnedPolicy :: NativeReturnedData -> Observation.ReturnedPolicy
nativeReturnedPolicy = Low.neuralReturnedPolicy . nativeReturnedLowData
nativeReturnedLowData :: NativeReturnedData -> Low.NeuralReturnedData
nativeReturnedLowData (NativeReturnedData _ _ _ _ actual) = actual
nativeReturnedInitialEvaluation :: NativeReturnedData -> NativeEvaluationData
nativeReturnedInitialEvaluation (NativeReturnedData _ _ _ initial _) = initial
nativeReturnedSnapshot :: NativeReturnedData -> Low.NeuralSnapshot
nativeReturnedSnapshot (NativeReturnedData _ snapshot _ _ _) = snapshot
nativeReturnedColdSnapshot :: NativeReturnedData -> Maybe Low.NeuralSnapshot
nativeReturnedColdSnapshot (NativeReturnedData _ _ cold _ _) = cold
nativeReturnedChild :: NativeReturnedData -> NativeNeuralChildData
nativeReturnedChild (NativeReturnedData child _ _ _ _) = child
nativeEvaluatedReturnedData :: NativeEvaluatedData -> NativeReturnedData
nativeEvaluatedReturnedData (NativeEvaluatedData returned _) = returned
nativeEvaluatedFinalEvaluation :: NativeEvaluatedData -> NativeEvaluationData
nativeEvaluatedFinalEvaluation (NativeEvaluatedData _ final) = final

evaluateNativeNeuralFinal :: NativePendingFinalEvaluation -> IO NativeFinalEvaluationResult
evaluateNativeNeuralFinal (NativePendingFinalEvaluation returned device guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let child = nativeReturnedChild returned
      known =
        Known
          (Just child)
          (Just (nativeReturnedSnapshot returned))
          (nativeReturnedColdSnapshot returned)
          (Just (nativeReturnedInitialEvaluation returned))
          Nothing
          Nothing
  if not claimed
    then pure (NativeFinalEvaluationFailed returned Nothing (consumed NativeFinalEvaluation known))
    else do
      evaluated <- evaluateClosedReturned known child device (nativeReturnedPolicy returned)
      pure $ case evaluated of
        Left failure -> NativeFinalEvaluationFailed returned (nativeFailureEvaluation failure) failure
        Right final -> NativeFinalEvaluationComplete (NativeEvaluatedData returned final)

-- Only actual closed low returns reach here; no public raw-to-stage factory.
evaluateClosedReturned
  :: Known
  -> NativeNeuralChildData
  -> MlpDevice
  -> Observation.ReturnedPolicy
  -> IO (Either NativeAttemptFailure NativeEvaluationData)
evaluateClosedReturned known child device policy = case policy of
  Observation.ReturnedOnPolicy raw ->
    evaluateClosed
      NativeFinalEvaluation
      known
      child
      device
      (Config.OnPolicyConfiguration (Common.rawTrainerConfig raw))
      (Common.rawTrainerFinalParams raw)
  Observation.ReturnedDqn raw ->
    evaluateClosed
      NativeFinalEvaluation
      known
      child
      device
      (Config.DqnConfiguration (Common.rawTrainerConfig raw))
      (Common.rawTrainerFinalParams raw)
  Observation.ReturnedQrDqn raw ->
    evaluateClosed
      NativeFinalEvaluation
      known
      child
      device
      (Config.QrDqnConfiguration (Common.rawTrainerConfig raw))
      (Common.rawTrainerFinalParams raw)
  Observation.ReturnedContinuous raw ->
    evaluateClosed
      NativeFinalEvaluation
      known
      child
      device
      (Config.ContinuousConfiguration (Common.rawTrainerConfig raw))
      (Common.rawTrainerFinalParams raw)
  Observation.ReturnedHer raw ->
    evaluateClosed
      NativeFinalEvaluation
      known
      child
      device
      (Config.HerConfiguration (Common.rawTrainerConfig raw))
      (Common.rawTrainerFinalParams raw)
  Observation.ReturnedArs _ ->
    pure
      ( Left
          ( NativeAttemptFailure
              NativeFinalEvaluation
              NativeContextRejected
              "native neural final evaluation excludes ARS"
              known
          )
      )

evaluateClosed
  :: NativeAttemptStage
  -> Known
  -> NativeNeuralChildData
  -> MlpDevice
  -> Config.NeuralTrainerConfiguration
  -> Mlp.MlpParams
  -> IO (Either NativeAttemptFailure NativeEvaluationData)
evaluateClosed stage known child device config params = do
  observed <- newIORef Nothing
  attempted <- tryAny $ do
    actual <- actualEvaluation device (childCases child) config params
    case actual of
      Left reason -> forceText reason >> pure (Left reason)
      Right result -> do
        _ <- evaluate (forceEvaluation result)
        writeIORef observed (Just result)
        checked <- forceEitherText (validateNativeEvaluationData child result)
        pure (result <$ checked)
  retained <- readIORef observed
  let facts = withEvaluation retained known
  case attempted of
    Left exception -> Left <$> exceptionFailure stage facts exception
    Right (Left reason) -> pure (Left (NativeAttemptFailure stage NativeEvaluationRejected reason facts))
    Right (Right complete) -> pure (Right complete)

actualEvaluation
  :: MlpDevice
  -> FixedCases
  -> Config.NeuralTrainerConfiguration
  -> Mlp.MlpParams
  -> IO (Either Text NativeEvaluationData)
actualEvaluation device cases config params = case (cases, config) of
  (ReturnCases spec, Config.OnPolicyConfiguration actual) ->
    Right . NativeReturnEvaluation
      <$> Return.evaluateNativeNeuralReturnPolicy device spec (Return.NativeOnPolicy actual params)
  (ReturnCases spec, Config.DqnConfiguration actual) ->
    Right . NativeReturnEvaluation
      <$> Return.evaluateNativeNeuralReturnPolicy device spec (Return.NativeDqn actual params)
  (ReturnCases spec, Config.QrDqnConfiguration actual) ->
    Right . NativeReturnEvaluation
      <$> Return.evaluateNativeNeuralReturnPolicy device spec (Return.NativeQrDqn actual params)
  (ReturnCases spec, Config.ContinuousConfiguration actual) ->
    Right . NativeReturnEvaluation
      <$> Return.evaluateNativeNeuralReturnPolicy device spec (Return.NativeContinuous actual params)
  (HerCases schedule, Config.HerConfiguration actual) -> Right . NativeHerEvaluation <$> Her.evaluateNativeHerPolicy device schedule actual params
  _ -> pure (Left "native neural evaluation family differs from its captured fixed cases")

-- | Data-only completeness/context checks. No observation can construct any
-- executable stage through this helper. This is not independent policy physics,
-- full105-field identity or authentication. No floor/improvement/reference test.
validateNativeEvaluationData :: NativeNeuralChildData -> NativeEvaluationData -> Either Text ()
validateNativeEvaluationData child actual = case (childCases child, actual) of
  (ReturnCases spec, NativeReturnEvaluation raw) -> do
    require (Return.nativeEvaluationSpec raw == spec) "native return evaluation specification differs"
    case Return.nativeEvaluationPolicy raw of
      Return.NativeNeuralEvaluation policy -> Return.validateNativeNeuralReturnContext spec policy
      Return.NativeArsHostEvaluation {} -> Left "native neural evaluation contains ARS data"
    case Return.nativeEvaluationStatus raw of
      Return.NativeEvaluationComplete -> pure ()
      Return.NativeEvaluationRejected reason -> Left reason
      Return.NativeEvaluationFailed index _ reason -> Left ("native return case " <> Text.pack (show index) <> ": " <> reason)
    let episodes = Return.nativeEvaluationEpisodes raw
        count = ReturnRef.nativeReturnSpecEpisodeCount spec
        horizon = ReturnRef.nativeReturnSpecHorizon spec
        work = sum (map (toInteger . ReturnRef.nativeReturnEpisodeSteps) episodes)
    require
      (map ReturnRef.nativeReturnEpisodeId episodes == [0 .. count - 1])
      "native return complete case inventory differs"
    require
      ( all
          ( \episode ->
              finite (ReturnRef.nativeReturnEpisodeReward episode)
                && ReturnRef.nativeReturnEpisodeSteps episode > 0
                && ReturnRef.nativeReturnEpisodeSteps episode <= horizon
                && ( ReturnRef.nativeReturnEpisodeTerminated episode
                       || ReturnRef.nativeReturnEpisodeSteps episode == horizon
                   )
          )
          episodes
      )
      "native return complete observation is nonfinite or incomplete"
    require
      (Return.nativeEvaluationWork raw == Return.NativeCompleteWork work)
      "native return complete work differs"
  (HerCases schedule, NativeHerEvaluation raw) -> do
    require (Her.nativeHerEvaluationSchedule raw == schedule) "native HER evaluation schedule differs"
    Her.validateNativeHerEvaluationContext
      schedule
      (Her.nativeHerEvaluationConfig raw)
      (Her.nativeHerEvaluationParameters raw)
    case Her.nativeHerEvaluationStatus raw of
      Her.NativeHerEvaluationComplete -> pure ()
      Her.NativeHerEvaluationRejected _ reason -> Left reason
      Her.NativeHerEvaluationFailed index _ reason -> Left ("native HER case " <> Text.pack (show index) <> ": " <> reason)
    let outcomes = Her.nativeHerEvaluationOutcomes raw
        cases = HerRef.nativeHerScheduleCases schedule
        horizon = HerRef.nativeHerSpecHorizon (HerRef.nativeHerScheduleSpec schedule)
        work = sum (map (toInteger . HerRef.nativeHerOutcomeSteps) outcomes)
    require
      ( map HerRef.nativeHerOutcomeCaseId outcomes == map HerRef.rawNativeHerCaseId cases
          && length outcomes == length cases
      )
      "native HER complete case inventory differs"
    require
      ( and
          ( zipWith
              (\outcome goal -> sameVector (HerRef.nativeHerOutcomeGoal outcome) (HerRef.rawNativeHerGoal goal))
              outcomes
              cases
          )
      )
      "native HER complete goals differ from the captured schedule"
    require
      ( all
          ( \outcome ->
              finite (HerRef.nativeHerOutcomeNormalizedDistance outcome)
                && HerRef.nativeHerOutcomeSteps outcome > 0
                && HerRef.nativeHerOutcomeSteps outcome <= horizon
                && (HerRef.nativeHerOutcomeTerminated outcome || HerRef.nativeHerOutcomeSteps outcome == horizon)
          )
          outcomes
      )
      "native HER complete observation is nonfinite or incomplete"
    require
      (Her.nativeHerEvaluationWork raw == Her.NativeHerCompleteWork work)
      "native HER complete work differs"
  _ -> Left "native neural evaluation observation has the wrong fixed-case family"

nativeFailureStage :: NativeAttemptFailure -> NativeAttemptStage
nativeFailureStage (NativeAttemptFailure stage _ _ _) = stage
nativeFailureKind :: NativeAttemptFailure -> NativeFailureKind
nativeFailureKind (NativeAttemptFailure _ kind _ _) = kind
nativeFailureDetail :: NativeAttemptFailure -> Text
nativeFailureDetail (NativeAttemptFailure _ _ detail _) = detail
nativeFailureChild :: NativeAttemptFailure -> Maybe NativeNeuralChildData
nativeFailureChild (NativeAttemptFailure _ _ _ (Known value _ _ _ _ _)) = value
nativeFailureSnapshot :: NativeAttemptFailure -> Maybe Low.NeuralSnapshot
nativeFailureSnapshot (NativeAttemptFailure _ _ _ (Known _ value _ _ _ _)) = value
nativeFailureColdSnapshot :: NativeAttemptFailure -> Maybe Low.NeuralSnapshot
nativeFailureColdSnapshot (NativeAttemptFailure _ _ _ (Known _ _ value _ _ _)) = value
nativeFailureInitialEvaluation :: NativeAttemptFailure -> Maybe NativeEvaluationData
nativeFailureInitialEvaluation (NativeAttemptFailure _ _ _ (Known _ _ _ value _ _)) = value
nativeFailureEvaluation :: NativeAttemptFailure -> Maybe NativeEvaluationData
nativeFailureEvaluation (NativeAttemptFailure _ _ _ (Known _ _ _ _ value _)) = value
nativeFailureLowFailure :: NativeAttemptFailure -> Maybe Low.NeuralAttemptFailure
nativeFailureLowFailure (NativeAttemptFailure _ _ _ (Known _ _ _ _ _ value)) = value
withEvaluation :: Maybe NativeEvaluationData -> Known -> Known
withEvaluation value (Known child snapshot cold initial _ low) = Known child snapshot cold initial value low
lowFailure :: NativeAttemptStage -> Known -> Low.NeuralAttemptFailure -> NativeAttemptFailure
lowFailure stage (Known child snapshot cold initial actual _) low =
  NativeAttemptFailure
    stage
    kind
    (Low.neuralFailureDetail low)
    (Known child snapshot cold initial actual (Just low))
 where
  kind =
    if Low.neuralFailureKind low == Low.NeuralAlreadyConsumed
      then NativeAlreadyConsumed
      else NativeLowRejected
consumed :: NativeAttemptStage -> Known -> NativeAttemptFailure
consumed stage = NativeAttemptFailure stage NativeAlreadyConsumed "native neural phase has already been consumed"
exceptionFailure :: NativeAttemptStage -> Known -> SomeException -> IO NativeAttemptFailure
exceptionFailure stage known exception = do
  attempted <- tryAny $ do
    let detail = Text.pack (displayException exception)
    forceText detail
    pure detail
  pure
    ( NativeAttemptFailure
        stage
        NativeSynchronousFailure
        (fromRight "synchronous exception rendering failed" attempted)
        known
    )

forceSelection :: NativeNeuralChildData -> ()
forceSelection child =
  forceAll
    [ textValue (nativeNeuralRowId (nativeNeuralChildRow child))
    , textValue (Budget.renderCompiledRlPlanTransport (nativeNeuralChildCompiledPlan child))
    , BS.length (Cohort.nativeRlCohortPlanTransport (nativeNeuralRowCohort (nativeNeuralChildRow child))) `seq`
        ()
    , textValue
        ( Native.renderNativeSingletonPlan
            (Cohort.nativeRlSeedPlanSingleton (nativeNeuralChildSeedPlan child))
        )
    , case childCases child of
        ReturnCases spec ->
          forceAll
            [ ReturnRef.nativeReturnSpecEpisodeCount spec `seq` ()
            , ReturnRef.nativeReturnSpecHorizon spec `seq` ()
            , textValue (ReturnRef.nativeReturnSpecRowId spec)
            ]
        HerCases schedule -> forceList (forceVector . HerRef.rawNativeHerGoal) (HerRef.nativeHerScheduleCases schedule)
    ]

-- The config/spec inputs are already observed closed values from the low and
-- row selections. Traverse every NEW actual outcome/forward/failure field.
forceEvaluation :: NativeEvaluationData -> ()
forceEvaluation observation = case observation of
  NativeReturnEvaluation raw ->
    forceAll
      [ Return.nativeEvaluationSpec raw `seq` ()
      , Return.nativeEvaluationPolicy raw `seq` ()
      , forceList forceReturnEpisode (Return.nativeEvaluationEpisodes raw)
      , forceList forceReturnForward (Return.nativeEvaluationForwards raw)
      , case Return.nativeEvaluationStatus raw of
          Return.NativeEvaluationComplete -> ()
          Return.NativeEvaluationRejected reason -> textValue reason
          Return.NativeEvaluationFailed index kind reason -> forceAll [index `seq` (), kind `seq` (), textValue reason]
      , case Return.nativeEvaluationWork raw of
          Return.NativeCompleteWork n -> n `seq` ()
          Return.NativeRejectedWork -> ()
          Return.NativeFailedWork prefix partial -> forceAll [prefix `seq` (), forceMaybe whnf partial]
      , forceMaybe (forceList forceCommonEpisode) (Return.nativeEvaluationFailedReturnedEpisodes raw)
      ]
  NativeHerEvaluation raw ->
    forceAll
      [ Her.nativeHerEvaluationSchedule raw `seq` ()
      , Her.nativeHerEvaluationConfig raw `seq` ()
      , forceParams (Her.nativeHerEvaluationParameters raw)
      , forceList forceHerOutcome (Her.nativeHerEvaluationOutcomes raw)
      , forceList forceHerForward (Her.nativeHerEvaluationForwards raw)
      , case Her.nativeHerEvaluationStatus raw of
          Her.NativeHerEvaluationComplete -> ()
          Her.NativeHerEvaluationRejected kind reason -> forceAll [kind `seq` (), textValue reason]
          Her.NativeHerEvaluationFailed index kind reason -> forceAll [index `seq` (), kind `seq` (), textValue reason]
      , case Her.nativeHerEvaluationWork raw of
          Her.NativeHerCompleteWork n -> n `seq` ()
          Her.NativeHerRejectedWork -> ()
          Her.NativeHerFailedWork prefix observed partial -> forceAll [prefix `seq` (), observed `seq` (), forceMaybe whnf partial]
      , forceMaybe forceHerProgress (Her.nativeHerEvaluationFailedProgress raw)
      ]
forceReturnEpisode :: ReturnRef.NativeReturnEpisode -> ()
forceReturnEpisode (ReturnRef.NativeReturnEpisode index reward steps done) = forceAll [index `seq` (), reward `seq` (), steps `seq` (), done `seq` ()]
forceCommonEpisode :: Common.EvaluationEpisodeResult -> ()
forceCommonEpisode (Common.EvaluationEpisodeResult reward steps done) = forceAll [reward `seq` (), steps `seq` (), done `seq` ()]
forceReturnForward :: Return.NativeForwardObservation -> ()
forceReturnForward (Return.NativeForwardObservation episode index params input outcome) =
  forceAll
    [ episode `seq` ()
    , index `seq` ()
    , forceParams params
    , forceVector input
    , case outcome of
        Return.NativeForwardReturned result -> forceEitherVector result
        Return.NativeForwardException reason -> textValue reason
    ]
forceHerForward :: Her.NativeHerForwardObservation -> ()
forceHerForward (Her.NativeHerForwardObservation episode index params input outcome) =
  forceAll
    [ episode `seq` ()
    , index `seq` ()
    , forceParams params
    , forceVector input
    , case outcome of
        Her.NativeHerForwardReturned result -> forceEitherVector result
        Her.NativeHerForwardException reason -> textValue reason
    ]
forceHerOutcome :: HerRef.NativeHerReferenceOutcome -> ()
forceHerOutcome (HerRef.NativeHerReferenceOutcome index goal final success normalized hamming steps done actions) =
  forceAll
    [ index `seq` ()
    , forceVector goal
    , forceVector final
    , success `seq` ()
    , normalized `seq` ()
    , hamming `seq` ()
    , steps `seq` ()
    , done `seq` ()
    , forceList whnf actions
    ]
forceHerProgress :: Her.NativeHerCaseProgress -> ()
forceHerProgress (Her.NativeHerCaseProgress index goal state actions steps phase) =
  forceAll
    [ index `seq` ()
    , forceVector goal
    , forceVector state
    , forceList whnf actions
    , steps `seq` ()
    , phase `seq` ()
    ]
forceParams :: Mlp.MlpParams -> ()
forceParams (Mlp.MlpParams (Mlp.MlpShape inputs hidden outputs) w1 b1 w2 b2) =
  forceAll
    [ inputs `seq` ()
    , hidden `seq` ()
    , outputs `seq` ()
    , forceVector w1
    , forceVector b1
    , forceVector w2
    , forceVector b2
    ]
forceEitherVector :: Either Text (VU.Vector Double) -> ()
forceEitherVector = either textValue forceVector
forceEitherText :: Either Text value -> IO (Either Text value)
forceEitherText actual = do
  outer <- evaluate actual
  case outer of
    Left reason -> forceText reason >> pure (Left reason)
    Right value -> pure (Right value)
forceText :: Text -> IO ()
forceText value = void (evaluate (Text.length value))
textValue :: Text -> ()
textValue value = Text.length value `seq` ()
forceVector :: VU.Vector Double -> ()
forceVector = VU.foldl' (\() value -> value `seq` ()) ()
forceAll :: [()] -> ()
forceAll = forceList id
forceList :: (value -> ()) -> [value] -> ()
forceList force = foldr (\value rest -> force value `seq` rest) ()
forceMaybe :: (value -> ()) -> Maybe value -> ()
forceMaybe = maybe ()
whnf :: value -> ()
whnf value = value `seq` ()
sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector left right =
  VU.length left == VU.length right
    && VU.and (VU.zipWith (\a z -> castDoubleToWord64 a == castDoubleToWord64 z) left right)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require predicate reason = unless predicate (Left reason)
