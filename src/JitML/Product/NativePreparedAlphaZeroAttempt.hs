{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Full canonical child association and numerical phase ordering only.
-- No producer/provider origin, durability, learning, qualification or Store
-- admission follows from a supplied device, decoded data or successful predicate.
module JitML.Product.NativePreparedAlphaZeroAttempt
  ( NativeAlphaZeroRowData
  , NativeAlphaZeroChildData
  , NativeArenaPrepared
  , NativeArenaReadyToTrain
  , NativeArenaPendingFinal
  , NativeAlphaZeroReturnedData
  , NativeAlphaZeroEvaluatedData
  , NativeArenaAttemptStage (..)
  , NativeArenaFailureKind (..)
  , NativeArenaFailure
  , NativeArenaPreparationResult (..)
  , NativeArenaInitialResult (..)
  , NativeArenaTrainingResult (..)
  , NativeArenaFinalResult (..)
  , selectNativeAlphaZeroRowData
  , selectNativeAlphaZeroChildData
  , nativeAlphaZeroRowId
  , nativeAlphaZeroRowBatch
  , nativeAlphaZeroRowCohort
  , nativeAlphaZeroRowSpec
  , nativeAlphaZeroRowTape
  , nativeAlphaZeroChildRow
  , nativeAlphaZeroChildSeedPlan
  , nativeAlphaZeroChildPlan
  , prepareNativeAlphaZeroAttempt
  , nativeAlphaZeroPreparedSnapshot
  , evaluateNativeAlphaZeroInitial
  , nativeAlphaZeroReadySnapshot
  , nativeAlphaZeroReadyInitialEvaluation
  , continueNativeAlphaZeroTraining
  , nativeAlphaZeroReturnedData
  , nativeAlphaZeroReturnedChild
  , nativeAlphaZeroReturnedSnapshot
  , nativeAlphaZeroReturnedInitialEvaluation
  , nativeAlphaZeroReturnedRawObservation
  , evaluateNativeAlphaZeroFinal
  , nativeAlphaZeroEvaluatedReturnedData
  , nativeAlphaZeroEvaluatedFinalEvaluation
  , validateNativeAlphaZeroPreparedData
  , validateNativeAlphaZeroReturnedData
  , validateNativeAlphaZeroTrainingSampleData
  , validateNativeAlphaZeroEvaluationData
  , nativeAlphaZeroFailureStage
  , nativeAlphaZeroFailureKind
  , nativeAlphaZeroFailureDetail
  , nativeAlphaZeroFailureChild
  , nativeAlphaZeroFailureSnapshot
  , nativeAlphaZeroFailureInitialEvaluation
  , nativeAlphaZeroFailureEvaluation
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (foldM, unless, void)
import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.List.NonEmpty qualified as NE
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Plan.NativeSingletonPlan qualified as Native
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Ref
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.AlphaZero.PreparedTrainer qualified as Low
import JitML.Training.Budget qualified as Budget

-- Read-only selections require the complete checked whole-lane batch. These
-- data constructors cannot be used to create a different tape, plan or device.
data NativeAlphaZeroRowData
  = NativeAlphaZeroRowData
      Cohort.NativeRlCohortBatch
      Cohort.NativeRlCohortPlan
      Ref.NativeArenaSpec
      Tape.ArenaTape
  deriving stock (Eq, Show)
data NativeAlphaZeroChildData
  = NativeAlphaZeroChildData NativeAlphaZeroRowData Cohort.NativeRlSeedPlan Workload.AlphaZeroPlan
  deriving stock (Eq, Show)

-- Action-bearing stages have no exported constructors, labels, instances or
-- restore operation. Each transition privately captures the SAME actual device.
data NativeArenaPrepared
  = NativeArenaPrepared
      NativeAlphaZeroChildData
      MlpDevice
      Low.PreparedAlphaZero
      Low.AlphaZeroPreparedSnapshot
      SingleUse.SingleUse
data NativeArenaReadyToTrain
  = NativeArenaReadyToTrain
      NativeAlphaZeroChildData
      MlpDevice
      Low.PreparedAlphaZero
      Low.AlphaZeroPreparedSnapshot
      Arena.RawNativeArenaEvaluation
      SingleUse.SingleUse
data NativeAlphaZeroReturnedData
  = NativeAlphaZeroReturnedData
      NativeAlphaZeroChildData
      Low.AlphaZeroPreparedSnapshot
      Arena.RawNativeArenaEvaluation
      Low.AlphaZeroTrainObservation
data NativeArenaPendingFinal
  = NativeArenaPendingFinal NativeAlphaZeroReturnedData MlpDevice SingleUse.SingleUse
data NativeAlphaZeroEvaluatedData
  = NativeAlphaZeroEvaluatedData NativeAlphaZeroReturnedData Arena.RawNativeArenaEvaluation

data NativeArenaAttemptStage
  = NativeArenaSelection
  | NativeArenaPreparation
  | NativeArenaInitialEvaluation
  | NativeArenaTraining
  | NativeArenaReturnBinding
  | NativeArenaFinalEvaluation
  deriving stock (Eq, Show)
data NativeArenaFailureKind
  = NativeArenaContextRejected
  | NativeArenaLowRejected
  | NativeArenaEvaluationRejected
  | NativeArenaSynchronousFailure
  | NativeArenaAlreadyConsumed
  deriving stock (Eq, Show)
data Known
  = Known
      (Maybe NativeAlphaZeroChildData)
      (Maybe Low.AlphaZeroPreparedSnapshot)
      (Maybe Arena.RawNativeArenaEvaluation)
      (Maybe Arena.RawNativeArenaEvaluation)
data NativeArenaFailure = NativeArenaFailure NativeArenaAttemptStage NativeArenaFailureKind Text Known

data NativeArenaPreparationResult
  = NativeArenaPreparationFailed NativeArenaFailure
  | NativeArenaPreparationReady NativeArenaPrepared
data NativeArenaInitialResult
  = NativeArenaInitialFailed NativeArenaFailure
  | NativeArenaInitialReady NativeArenaReadyToTrain
data NativeArenaTrainingResult
  = NativeArenaTrainingFailed NativeArenaFailure
  | NativeArenaTrainingReturnedButUnmaterializable NativeArenaFailure
  | NativeArenaTrainingBindingFailed NativeAlphaZeroReturnedData NativeArenaFailure
  | NativeArenaTrainingReturned NativeArenaPendingFinal
data NativeArenaFinalResult
  = NativeArenaFinalFailed
      NativeAlphaZeroReturnedData
      (Maybe Arena.RawNativeArenaEvaluation)
      NativeArenaFailure
  | NativeArenaFinalComplete NativeAlphaZeroEvaluatedData

emptyKnown :: Known
emptyKnown = Known Nothing Nothing Nothing Nothing

nativeAlphaZeroRowId :: NativeAlphaZeroRowData -> Text
nativeAlphaZeroRowId = Matrix.rowId . Cohort.nativeRlCohortPlanRow . nativeAlphaZeroRowCohort
nativeAlphaZeroRowBatch :: NativeAlphaZeroRowData -> Cohort.NativeRlCohortBatch
nativeAlphaZeroRowBatch (NativeAlphaZeroRowData batch _ _ _) = batch
nativeAlphaZeroRowCohort :: NativeAlphaZeroRowData -> Cohort.NativeRlCohortPlan
nativeAlphaZeroRowCohort (NativeAlphaZeroRowData _ cohort _ _) = cohort
nativeAlphaZeroRowSpec :: NativeAlphaZeroRowData -> Ref.NativeArenaSpec
nativeAlphaZeroRowSpec (NativeAlphaZeroRowData _ _ spec _) = spec
nativeAlphaZeroRowTape :: NativeAlphaZeroRowData -> Tape.ArenaTape
nativeAlphaZeroRowTape (NativeAlphaZeroRowData _ _ _ tape) = tape
nativeAlphaZeroChildRow :: NativeAlphaZeroChildData -> NativeAlphaZeroRowData
nativeAlphaZeroChildRow (NativeAlphaZeroChildData row _ _) = row
nativeAlphaZeroChildSeedPlan :: NativeAlphaZeroChildData -> Cohort.NativeRlSeedPlan
nativeAlphaZeroChildSeedPlan (NativeAlphaZeroChildData _ child _) = child
nativeAlphaZeroChildPlan :: NativeAlphaZeroChildData -> Workload.AlphaZeroPlan
nativeAlphaZeroChildPlan (NativeAlphaZeroChildData _ _ plan) = plan

selectNativeAlphaZeroRowData
  :: Cohort.NativeRlCohortBatch -> Text -> Either NativeArenaFailure NativeAlphaZeroRowData
selectNativeAlphaZeroRowData batch rowId = do
  cohort <-
    maybe
      (selectionFailure "native AlphaZero row is absent from the checked batch")
      Right
      ( find
          ((== rowId) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  game <- case Cohort.nativeRlCohortPlanProjection cohort of
    Matrix.SomeProductProjection Plan.AlphaZeroSelfPlayWitness projection ->
      case (Matrix.productProjectionDescriptor projection, Matrix.productProjectionResolvedPlan projection) of
        (Matrix.AlphaZeroProductDescriptor observed _ _ _ _ _, Matrix.ResolvedAlphaZeroProductPlan plan) -> do
          requireSelection
            (observed == Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan))
            "native AlphaZero full game differs from projection"
          requireSelection
            (Matrix.productProjectionPlanId projection == Workload.alphaZeroPlanId plan)
            "native AlphaZero full workload PlanId differs from projection"
          Right observed
    _ -> selectionFailure "native AlphaZero selection excludes all return HER and ARS rows"
  spec <- selectionEither (Ref.canonicalNativeArenaSpec game)
  requireSelection
    (rowId == Ref.nativeArenaSpecRowId spec)
    "native AlphaZero row differs from its fixed arena context"
  let tape = Ref.materializeNativeArenaTape spec
  pure (NativeAlphaZeroRowData batch cohort spec tape)

selectNativeAlphaZeroChildData
  :: NativeAlphaZeroRowData
  -> Cohort.NativeSeedIndex
  -> Either NativeArenaFailure NativeAlphaZeroChildData
selectNativeAlphaZeroChildData row index = do
  child <-
    maybe
      (selectionFailure "native AlphaZero child is absent from its checked cohort")
      Right
      ( find
          ((== index) . Cohort.nativeRlSeedPlanIndex)
          (Cohort.nativeRlCohortPlanChildren (nativeAlphaZeroRowCohort row))
      )
  plan <-
    maybe
      (selectionFailure "native AlphaZero child has no full game workload")
      Right
      (Cohort.nativeRlSeedPlanAlphaZero child)
  let result = NativeAlphaZeroChildData row child plan
  selectionEither (validateChild result)
  pure result

selectionFailure :: Text -> Either NativeArenaFailure value
selectionFailure reason = Left (NativeArenaFailure NativeArenaSelection NativeArenaContextRejected reason emptyKnown)
selectionEither :: Either Text value -> Either NativeArenaFailure value
selectionEither = either selectionFailure Right
requireSelection :: Bool -> Text -> Either NativeArenaFailure ()
requireSelection condition reason = unless condition (selectionFailure reason)

-- Only actual checked public-plan quantities feed the unchanged low recipe.
data Schedule = Schedule Text Int Int Int Int Int Int Int
schedule :: NativeAlphaZeroChildData -> Either Text Schedule
schedule child = do
  let plan = nativeAlphaZeroChildPlan child
      game = Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan)
  seed <- intValue "seed" (Cohort.nativeRlSeedPlanSeed (nativeAlphaZeroChildSeedPlan child))
  generations <- intValue "generations" (Plan.quantityValue (Workload.alphaZeroPlanGenerations plan))
  games <- intValue "self-play games" (Plan.quantityValue (Workload.alphaZeroPlanSelfPlayGames plan))
  sims <-
    intValue "training simulations" (Plan.quantityValue (Workload.alphaZeroPlanMctsSimulations plan))
  plies <- intValue "maximum plies" (Plan.quantityValue (Workload.alphaZeroPlanMaxPlies plan))
  updates <- intValue "optimizer updates" (Plan.quantityValue (Workload.alphaZeroPlanUpdates plan))
  arena <- intValue "arena games" (Plan.quantityValue (Workload.alphaZeroPlanArenaGames plan))
  require
    (all (> 0) [generations, games, sims, plies, updates, arena])
    "native AlphaZero schedule has a nonpositive quantity"
  pure (Schedule game seed generations games sims plies updates arena)
intValue :: Text -> Word64 -> Either Text Int
intValue label value = do
  require
    (toInteger value <= toInteger (maxBound :: Int))
    ("native AlphaZero " <> label <> " exceeds actual Int range")
  pure (fromIntegral value)

validateChild :: NativeAlphaZeroChildData -> Either Text ()
validateChild child = do
  let row = nativeAlphaZeroChildRow child
      prescribed = nativeAlphaZeroChildSeedPlan child
      plan = nativeAlphaZeroChildPlan child
      singleton = Cohort.nativeRlSeedPlanSingleton prescribed
      reference = Ref.nativeArenaSpecTrainingBudget (nativeAlphaZeroRowSpec row)
      run = Workload.alphaZeroPlanRunPlan plan
      target = Plan.quantityValue (Workload.alphaZeroPlanGenerations plan)
      seed = Cohort.nativeRlSeedPlanSeed prescribed
  require
    ( Native.nativeSingletonAlphaZeroPlan singleton == Just plan
        && Native.nativeSingletonPlanId singleton == Workload.alphaZeroPlanId plan
        && fmap Workload.renderAlphaZeroPlanTransport (Native.nativeSingletonAlphaZeroPlan singleton)
          == Just (Workload.renderAlphaZeroPlanTransport plan)
        && Native.nativeSingletonSubstrate singleton
          == Cohort.nativeRlCohortBatchSubstrate (nativeAlphaZeroRowBatch row)
    )
    "native AlphaZero complete child transport or selected lane differs"
  require
    ( Workload.renderAlphaZeroGame (Workload.alphaZeroPlanGame plan)
        == Ref.nativeArenaSpecRowId (nativeAlphaZeroRowSpec row)
    )
    "native AlphaZero child game differs from row"
  require
    (NE.toList (Plan.seedCohortValues (Plan.runPlanSeeds run)) == [seed])
    "native AlphaZero child seed cohort differs"
  expected <-
    Budget.mkTrainingBudget
      (Budget.trainingBudgetKind reference)
      (Budget.trainingBudgetTargetUnits reference)
      (Just seed)
  require
    ( Budget.trainingBudgetKind reference == Budget.AlphaZeroSelfPlayBudget
        && isNothing (Budget.trainingBudgetSeed reference)
        && target == Budget.trainingBudgetTargetUnits reference
        && Cohort.nativeRlSeedPlanTrainingBudget prescribed == expected
    )
    "native AlphaZero seeded budget differs from the seedless fixed reference declaration"
  Schedule _ _ _ _ sims plies _ arena <- schedule child
  require
    ( toInteger sims == toInteger (Ref.nativeArenaSpecTrainingSimulations (nativeAlphaZeroRowSpec row))
        && plies == Ref.nativeArenaSpecMaxPlies (nativeAlphaZeroRowSpec row)
        && toInteger arena
          == toInteger (Tape.arenaTapeSpecGames (Tape.arenaTapeSpec (nativeAlphaZeroRowTape row)))
    )
    "native AlphaZero child schedule differs from fixed arena metadata"

prepareNativeAlphaZeroAttempt
  :: NativeAlphaZeroChildData -> MlpDevice -> IO NativeArenaPreparationResult
prepareNativeAlphaZeroAttempt child device = do
  observed <- newIORef emptyKnown
  attempted <- tryAny $ do
    _ <- evaluate (forceSelection child)
    let known = Known (Just child) Nothing Nothing Nothing
    writeIORef observed known
    checked <- forceEitherText (validateChild child)
    case checked of
      Left reason ->
        pure
          ( NativeArenaPreparationFailed
              (NativeArenaFailure NativeArenaPreparation NativeArenaContextRejected reason known)
          )
      Right () -> do
        probe <- probeMlpDevice device >>= forceEitherText
        case probe of
          Left reason ->
            pure
              ( NativeArenaPreparationFailed
                  (NativeArenaFailure NativeArenaPreparation NativeArenaLowRejected reason known)
              )
          Right () -> do
            values <- forceEitherText (schedule child)
            case values of
              Left reason ->
                pure
                  ( NativeArenaPreparationFailed
                      (NativeArenaFailure NativeArenaPreparation NativeArenaContextRejected reason known)
                  )
              Right (Schedule game seed generations games sims plies updates _) -> do
                prepared <-
                  Low.prepareAlphaZeroWithDevice
                    device
                    game
                    Low.canonicalAlphaZeroHiddenUnits
                    seed
                    generations
                    games
                    sims
                    plies
                    updates
                let actual = Low.preparedAlphaZeroSnapshot prepared
                _ <- evaluate (forceSnapshot actual)
                let facts = Known (Just child) (Just actual) Nothing Nothing
                writeIORef observed facts
                bound <- forceEitherText (validateNativeAlphaZeroPreparedData child actual)
                case bound of
                  Left reason ->
                    pure
                      ( NativeArenaPreparationFailed
                          (NativeArenaFailure NativeArenaPreparation NativeArenaContextRejected reason facts)
                      )
                  Right () ->
                    NativeArenaPreparationReady . NativeArenaPrepared child device prepared actual
                      <$> SingleUse.newSingleUse
  case attempted of
    Right result -> pure result
    Left exception -> do
      facts <- readIORef observed
      NativeArenaPreparationFailed <$> exceptionFailure NativeArenaPreparation facts exception

nativeAlphaZeroPreparedSnapshot :: NativeArenaPrepared -> Low.AlphaZeroPreparedSnapshot
nativeAlphaZeroPreparedSnapshot (NativeArenaPrepared _ _ _ snapshot _) = snapshot
nativeAlphaZeroReadySnapshot :: NativeArenaReadyToTrain -> Low.AlphaZeroPreparedSnapshot
nativeAlphaZeroReadySnapshot (NativeArenaReadyToTrain _ _ _ snapshot _ _) = snapshot
nativeAlphaZeroReadyInitialEvaluation :: NativeArenaReadyToTrain -> Arena.RawNativeArenaEvaluation
nativeAlphaZeroReadyInitialEvaluation (NativeArenaReadyToTrain _ _ _ _ initial _) = initial

evaluateNativeAlphaZeroInitial :: NativeArenaPrepared -> IO NativeArenaInitialResult
evaluateNativeAlphaZeroInitial (NativeArenaPrepared child device prepared snapshot guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let known = Known (Just child) (Just snapshot) Nothing Nothing
  if not claimed
    then pure (NativeArenaInitialFailed (consumed NativeArenaInitialEvaluation known))
    else do
      evaluated <-
        evaluateClosed
          NativeArenaInitialEvaluation
          known
          child
          device
          (Low.alphaZeroPreparedInitialNet snapshot)
      case evaluated of
        Left failure -> pure (NativeArenaInitialFailed failure)
        Right initial -> do
          next <- tryAny SingleUse.newSingleUse
          case next of
            Left exception ->
              NativeArenaInitialFailed
                <$> exceptionFailure
                  NativeArenaInitialEvaluation
                  (Known (Just child) (Just snapshot) (Just initial) (Just initial))
                  exception
            Right guardNext ->
              pure
                (NativeArenaInitialReady (NativeArenaReadyToTrain child device prepared snapshot initial guardNext))

continueNativeAlphaZeroTraining :: NativeArenaReadyToTrain -> IO NativeArenaTrainingResult
continueNativeAlphaZeroTraining (NativeArenaReadyToTrain child device prepared snapshot initial guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let known = Known (Just child) (Just snapshot) (Just initial) Nothing
      wrap = NativeAlphaZeroReturnedData child snapshot initial
  if not claimed
    then pure (NativeArenaTrainingFailed (consumed NativeArenaTraining known))
    else do
      returnedRight <- newIORef False
      materialized <- newIORef Nothing
      attempted <- tryAny $ do
        result <- Low.continuePreparedAlphaZeroRaw prepared
        outer <- evaluate result
        case outer of
          Left reason -> do
            forceText reason
            pure
              ( NativeArenaTrainingFailed
                  (NativeArenaFailure NativeArenaTraining NativeArenaLowRejected reason known)
              )
          Right actual -> do
            writeIORef returnedRight True
            _ <- evaluate (forceRaw actual)
            let retained = wrap actual
            writeIORef materialized (Just retained)
            checked <- forceEitherText (validateNativeAlphaZeroReturnedData child snapshot actual)
            case checked of
              Left reason ->
                pure
                  ( NativeArenaTrainingBindingFailed
                      retained
                      (NativeArenaFailure NativeArenaReturnBinding NativeArenaContextRejected reason known)
                  )
              Right () -> NativeArenaTrainingReturned . NativeArenaPendingFinal retained device <$> SingleUse.newSingleUse
      case attempted of
        Right result -> pure result
        Left exception -> do
          safe <- readIORef materialized
          sawRight <- readIORef returnedRight
          failure <-
            exceptionFailure (maybe NativeArenaTraining (const NativeArenaReturnBinding) safe) known exception
          pure $ case safe of
            Just actual -> NativeArenaTrainingBindingFailed actual failure
            Nothing ->
              if sawRight
                then NativeArenaTrainingReturnedButUnmaterializable failure
                else NativeArenaTrainingFailed failure

nativeAlphaZeroReturnedData :: NativeArenaPendingFinal -> NativeAlphaZeroReturnedData
nativeAlphaZeroReturnedData (NativeArenaPendingFinal actual _ _) = actual
nativeAlphaZeroReturnedChild :: NativeAlphaZeroReturnedData -> NativeAlphaZeroChildData
nativeAlphaZeroReturnedChild (NativeAlphaZeroReturnedData child _ _ _) = child
nativeAlphaZeroReturnedSnapshot :: NativeAlphaZeroReturnedData -> Low.AlphaZeroPreparedSnapshot
nativeAlphaZeroReturnedSnapshot (NativeAlphaZeroReturnedData _ snapshot _ _) = snapshot
nativeAlphaZeroReturnedInitialEvaluation
  :: NativeAlphaZeroReturnedData -> Arena.RawNativeArenaEvaluation
nativeAlphaZeroReturnedInitialEvaluation (NativeAlphaZeroReturnedData _ _ initial _) = initial
nativeAlphaZeroReturnedRawObservation
  :: NativeAlphaZeroReturnedData -> Low.AlphaZeroTrainObservation
nativeAlphaZeroReturnedRawObservation (NativeAlphaZeroReturnedData _ _ _ raw) = raw
nativeAlphaZeroEvaluatedReturnedData :: NativeAlphaZeroEvaluatedData -> NativeAlphaZeroReturnedData
nativeAlphaZeroEvaluatedReturnedData (NativeAlphaZeroEvaluatedData actual _) = actual
nativeAlphaZeroEvaluatedFinalEvaluation
  :: NativeAlphaZeroEvaluatedData -> Arena.RawNativeArenaEvaluation
nativeAlphaZeroEvaluatedFinalEvaluation (NativeAlphaZeroEvaluatedData _ final) = final

evaluateNativeAlphaZeroFinal :: NativeArenaPendingFinal -> IO NativeArenaFinalResult
evaluateNativeAlphaZeroFinal (NativeArenaPendingFinal actual device guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let child = nativeAlphaZeroReturnedChild actual
      snapshot = nativeAlphaZeroReturnedSnapshot actual
      initial = nativeAlphaZeroReturnedInitialEvaluation actual
      known = Known (Just child) (Just snapshot) (Just initial) Nothing
  if not claimed
    then pure (NativeArenaFinalFailed actual Nothing (consumed NativeArenaFinalEvaluation known))
    else do
      evaluated <-
        evaluateClosed
          NativeArenaFinalEvaluation
          known
          child
          device
          (Low.alphaZeroObservedFinalNet (nativeAlphaZeroReturnedRawObservation actual))
      pure $ case evaluated of
        Left failure -> NativeArenaFinalFailed actual (nativeAlphaZeroFailureEvaluation failure) failure
        Right final -> NativeArenaFinalComplete (NativeAlphaZeroEvaluatedData actual final)

evaluateClosed
  :: NativeArenaAttemptStage
  -> Known
  -> NativeAlphaZeroChildData
  -> MlpDevice
  -> Net.PolicyValueNet
  -> IO (Either NativeArenaFailure Arena.RawNativeArenaEvaluation)
evaluateClosed stage known child device net = do
  safe <- newIORef Nothing
  attempted <- tryAny $ do
    let row = nativeAlphaZeroChildRow child
    actual <-
      Arena.evaluateNativeArenaPolicy device (nativeAlphaZeroRowSpec row) (nativeAlphaZeroRowTape row) net
    _ <- evaluate (forceArena actual)
    writeIORef safe (Just actual)
    checked <- forceEitherText (validateNativeAlphaZeroEvaluationData child net actual)
    pure (actual <$ checked)
  retained <- readIORef safe
  let facts = withEvaluation retained known
  case attempted of
    Left exception -> Left <$> exceptionFailure stage facts exception
    Right (Left reason) -> pure (Left (NativeArenaFailure stage NativeArenaEvaluationRejected reason facts))
    Right (Right actual) -> pure (Right actual)

-- Unit-only data validation; none of these helpers can mint an action stage.
validateNativeAlphaZeroPreparedData
  :: NativeAlphaZeroChildData -> Low.AlphaZeroPreparedSnapshot -> Either Text ()
validateNativeAlphaZeroPreparedData child snapshot = do
  validateChild child
  Schedule game seed generations games sims plies updates _ <- schedule child
  require
    ( Low.alphaZeroPreparedGame snapshot == game
        && Low.alphaZeroPreparedInitialState snapshot == Game.initialStateFor game
        && Low.alphaZeroPreparedHiddenUnits snapshot == Low.canonicalAlphaZeroHiddenUnits
        && Low.alphaZeroPreparedSeed snapshot == seed
        && Low.alphaZeroPreparedGenerationTarget snapshot == generations
        && Low.alphaZeroPreparedGames snapshot == games
        && Low.alphaZeroPreparedSimulations snapshot == sims
        && Low.alphaZeroPreparedMaxPlies snapshot == plies
        && Low.alphaZeroPreparedUpdates snapshot == updates
    )
    "native AlphaZero actual prepared schedule differs from full child"
  let net = Low.alphaZeroPreparedInitialNet snapshot
      params = Net.pvnParams net
      shape = Mlp.paramShape params
      row = nativeAlphaZeroChildRow child
      adam = Low.alphaZeroPreparedInitialAdam snapshot
  Arena.validateNativeArenaPolicyContext (nativeAlphaZeroRowSpec row) (nativeAlphaZeroRowTape row) net
  require
    (Mlp.mlpHidden shape == Low.canonicalAlphaZeroHiddenUnits)
    "native AlphaZero actual hidden width differs from the shared producer recipe"
  validateAdam shape adam
  require
    (Mlp.adamStep_ adam == 0)
    "native AlphaZero actual prepared Adam is not the initialized state"

validateNativeAlphaZeroReturnedData
  :: NativeAlphaZeroChildData
  -> Low.AlphaZeroPreparedSnapshot
  -> Low.AlphaZeroTrainObservation
  -> Either Text ()
validateNativeAlphaZeroReturnedData child snapshot raw = do
  validateNativeAlphaZeroPreparedData child snapshot
  Schedule _ seed generations games sims plies updates _ <- schedule child
  require
    ( Low.alphaZeroObservedInitialState raw == Low.alphaZeroPreparedInitialState snapshot
        && sameNet (Low.alphaZeroObservedInitialNet raw) (Low.alphaZeroPreparedInitialNet snapshot)
        && sameAdam (Low.alphaZeroObservedInitialAdam raw) (Low.alphaZeroPreparedInitialAdam snapshot)
    )
    "native AlphaZero actual returned initial state net or Adam bits differ from its prepared snapshot"
  require
    ( Low.alphaZeroObservedSeed raw == seed
        && Low.alphaZeroObservedGenerationTarget raw == generations
        && Low.alphaZeroObservedGames raw == games
        && Low.alphaZeroObservedSimulations raw == sims
        && Low.alphaZeroObservedMaxPlies raw == plies
        && Low.alphaZeroObservedUpdates raw == updates
    )
    "native AlphaZero actual returned schedule differs from full child"
  require
    (Low.alphaZeroObservedGenerationCount raw == generations)
    "native AlphaZero actual returned generation count differs from its unchanged schedule"
  let initialNet = Low.alphaZeroPreparedInitialNet snapshot
      finalNet = Low.alphaZeroObservedFinalNet raw
      shape = Mlp.paramShape (Net.pvnParams initialNet)
      row = nativeAlphaZeroChildRow child
  require
    ( Net.pvnObservationSize finalNet == Net.pvnObservationSize initialNet
        && Net.pvnActionCount finalNet == Net.pvnActionCount initialNet
        && Mlp.paramShape (Net.pvnParams finalNet) == shape
    )
    "native AlphaZero actual returned final network metadata differs"
  Arena.validateNativeArenaPolicyContext
    (nativeAlphaZeroRowSpec row)
    (nativeAlphaZeroRowTape row)
    finalNet
  validateAdam shape (Low.alphaZeroObservedFinalAdam raw)
  require
    (Low.alphaZeroObservedOptimizerApplicationDelta raw >= 0)
    "native AlphaZero actual optimizer step delta is negative"
  mapM_ (validateNativeAlphaZeroTrainingSampleData child) (Low.alphaZeroObservedSamples raw)

validateAdam :: Mlp.MlpShape -> Mlp.AdamState -> Either Text ()
validateAdam shape adam = do
  require (Mlp.adamStep_ adam >= 0) "native AlphaZero actual Adam step is negative"
  mapM_ one [Mlp.adamM adam, Mlp.adamV adam]
 where
  one gradient =
    require
      ( toInteger (VU.length (Mlp.gradW1 gradient))
          == toInteger (Mlp.mlpInputs shape) * toInteger (Mlp.mlpHidden shape)
          && VU.length (Mlp.gradB1 gradient) == Mlp.mlpHidden shape
          && toInteger (VU.length (Mlp.gradW2 gradient))
            == toInteger (Mlp.mlpHidden shape) * toInteger (Mlp.mlpOutputs shape)
          && VU.length (Mlp.gradB2 gradient) == Mlp.mlpOutputs shape
          && all
            (VU.all finite)
            [Mlp.gradW1 gradient, Mlp.gradB1 gradient, Mlp.gradW2 gradient, Mlp.gradB2 gradient]
      )
      "native AlphaZero actual Adam moments are malformed or nonfinite"

-- | Recorded sample DATA only. Public game rules verify the transcript;
-- Othello -1 markers are mandatory passes, never counted placements/work.
-- This unit predicate cannot construct a returned value or executable stage.
validateNativeAlphaZeroTrainingSampleData
  :: NativeAlphaZeroChildData -> Net.PolicyValueTrainingSample -> Either Text ()
validateNativeAlphaZeroTrainingSampleData child sample = do
  let row = nativeAlphaZeroChildRow child
      game = Ref.nativeArenaSpecRowId (nativeAlphaZeroRowSpec row)
      state = Net.sampleState sample
      distribution = Net.sampleVisitDist sample
      count = Ref.nativeArenaSpecActionCount (nativeAlphaZeroRowSpec row)
      transcript = Game.gameMoves state
      placements = length (filter (>= 0) transcript)
  require
    ( Game.gameName state == game
        && Game.gameCurrentPlayer state `elem` [1, -1]
        && placements <= Ref.nativeArenaSpecMaxPlies (nativeAlphaZeroRowSpec row)
        && VU.length distribution == count
        && VU.all (\value -> finite value && value >= 0) distribution
        && finite (Net.sampleOutcome sample)
    )
    "native AlphaZero actual training sample fields are malformed or nonfinite"
  replayed <- foldM (sampleTranscriptStep game) (Game.initialStateFor game) transcript
  require
    (replayed == state)
    "native AlphaZero actual training sample state differs from its legal transcript"

sampleTranscriptStep :: Text -> Game.GameState -> Int -> Either Text Game.GameState
sampleTranscriptStep game raw action
  | action == -1 = do
      let passed = Game.normaliseForcedPass raw
      require
        (game == "othello" && Game.gameOutcome raw == Game.GameInProgress && passed /= raw)
        "native AlphaZero training sample has a spurious or non-Othello pass marker"
      pure passed
  | otherwise = do
      require
        ( action >= 0
            && Game.gameOutcome raw == Game.GameInProgress
            && Game.normaliseForcedPass raw == raw
            && action `elem` Game.legalMoves raw
        )
        "native AlphaZero training sample placement is illegal or omits a forced pass marker"
      pure (Game.applyMove action raw)

validateNativeAlphaZeroEvaluationData
  :: NativeAlphaZeroChildData -> Net.PolicyValueNet -> Arena.RawNativeArenaEvaluation -> Either Text ()
validateNativeAlphaZeroEvaluationData child net raw = do
  validateChild child
  let row = nativeAlphaZeroChildRow child
  Arena.validateNativeArenaEvaluationData
    (nativeAlphaZeroRowSpec row)
    (nativeAlphaZeroRowTape row)
    net
    raw

nativeAlphaZeroFailureStage :: NativeArenaFailure -> NativeArenaAttemptStage
nativeAlphaZeroFailureStage (NativeArenaFailure stage _ _ _) = stage
nativeAlphaZeroFailureKind :: NativeArenaFailure -> NativeArenaFailureKind
nativeAlphaZeroFailureKind (NativeArenaFailure _ kind _ _) = kind
nativeAlphaZeroFailureDetail :: NativeArenaFailure -> Text
nativeAlphaZeroFailureDetail (NativeArenaFailure _ _ detail _) = detail
nativeAlphaZeroFailureChild :: NativeArenaFailure -> Maybe NativeAlphaZeroChildData
nativeAlphaZeroFailureChild (NativeArenaFailure _ _ _ (Known child _ _ _)) = child
nativeAlphaZeroFailureSnapshot :: NativeArenaFailure -> Maybe Low.AlphaZeroPreparedSnapshot
nativeAlphaZeroFailureSnapshot (NativeArenaFailure _ _ _ (Known _ snapshot _ _)) = snapshot
nativeAlphaZeroFailureInitialEvaluation
  :: NativeArenaFailure -> Maybe Arena.RawNativeArenaEvaluation
nativeAlphaZeroFailureInitialEvaluation (NativeArenaFailure _ _ _ (Known _ _ initial _)) = initial
nativeAlphaZeroFailureEvaluation :: NativeArenaFailure -> Maybe Arena.RawNativeArenaEvaluation
nativeAlphaZeroFailureEvaluation (NativeArenaFailure _ _ _ (Known _ _ _ actual)) = actual
withEvaluation :: Maybe Arena.RawNativeArenaEvaluation -> Known -> Known
withEvaluation actual (Known child snapshot initial _) = Known child snapshot initial actual
consumed :: NativeArenaAttemptStage -> Known -> NativeArenaFailure
consumed stage =
  NativeArenaFailure
    stage
    NativeArenaAlreadyConsumed
    "native AlphaZero phase has already been consumed"
exceptionFailure :: NativeArenaAttemptStage -> Known -> SomeException -> IO NativeArenaFailure
exceptionFailure stage known exception = do
  attempted <- tryAny $ do
    let detail = Text.pack (displayException exception)
    forceText detail
    pure detail
  pure
    ( NativeArenaFailure
        stage
        NativeArenaSynchronousFailure
        (fromRight "synchronous exception rendering failed" attempted)
        known
    )

-- The exact actual values are forced, not reinitialized or serialized as a
-- made-up producer/resume proof. Every Double is observed by its binary64 bits.
forceSelection :: NativeAlphaZeroChildData -> ()
forceSelection child =
  forceAll
    [ textValue (nativeAlphaZeroRowId row)
    , BS.length (Cohort.nativeRlCohortPlanTransport (nativeAlphaZeroRowCohort row)) `seq` ()
    , textValue (Workload.renderAlphaZeroPlanTransport (nativeAlphaZeroChildPlan child))
    , textValue
        ( Native.renderNativeSingletonPlan
            (Cohort.nativeRlSeedPlanSingleton (nativeAlphaZeroChildSeedPlan child))
        )
    , BS.length (Tape.arenaTapeBytes (nativeAlphaZeroRowTape row)) `seq` ()
    , textValue (Tape.arenaTapeSha256 (nativeAlphaZeroRowTape row))
    ]
 where
  row = nativeAlphaZeroChildRow child
forceSnapshot :: Low.AlphaZeroPreparedSnapshot -> ()
forceSnapshot snapshot =
  forceAll
    [ textValue (Low.alphaZeroPreparedGame snapshot)
    , forceState (Low.alphaZeroPreparedInitialState snapshot)
    , forceNet (Low.alphaZeroPreparedInitialNet snapshot)
    , forceAdam (Low.alphaZeroPreparedInitialAdam snapshot)
    , Low.alphaZeroPreparedHiddenUnits snapshot `seq` ()
    , Low.alphaZeroPreparedSeed snapshot `seq` ()
    , Low.alphaZeroPreparedGenerationTarget snapshot `seq` ()
    , Low.alphaZeroPreparedGames snapshot `seq` ()
    , Low.alphaZeroPreparedSimulations snapshot `seq` ()
    , Low.alphaZeroPreparedMaxPlies snapshot `seq` ()
    , Low.alphaZeroPreparedUpdates snapshot `seq` ()
    ]
forceRaw :: Low.AlphaZeroTrainObservation -> ()
forceRaw raw =
  forceAll
    [ forceState (Low.alphaZeroObservedInitialState raw)
    , forceNet (Low.alphaZeroObservedInitialNet raw)
    , forceAdam (Low.alphaZeroObservedInitialAdam raw)
    , forceNet (Low.alphaZeroObservedFinalNet raw)
    , forceAdam (Low.alphaZeroObservedFinalAdam raw)
    , forceList forceSample (Low.alphaZeroObservedSamples raw)
    , Low.alphaZeroObservedGenerationCount raw `seq` ()
    , Low.alphaZeroObservedGenerationTarget raw `seq` ()
    , Low.alphaZeroObservedGames raw `seq` ()
    , Low.alphaZeroObservedSimulations raw `seq` ()
    , Low.alphaZeroObservedMaxPlies raw `seq` ()
    , Low.alphaZeroObservedUpdates raw `seq` ()
    , Low.alphaZeroObservedSeed raw `seq` ()
    ]
forceSample :: Net.PolicyValueTrainingSample -> ()
forceSample (Net.PolicyValueTrainingSample state distribution outcome) =
  forceAll
    [forceState state, forceVector distribution, castDoubleToWord64 outcome `seq` ()]
forceState :: Game.GameState -> ()
forceState (Game.GameState game moves player) = forceAll [textValue game, forceList whnf moves, player `seq` ()]
forceNet :: Net.PolicyValueNet -> ()
forceNet (Net.PolicyValueNet params count obs) = forceAll [forceParams params, count `seq` (), obs `seq` ()]
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
forceGradient :: Mlp.MlpGradient -> ()
forceGradient (Mlp.MlpGradient w1 b1 w2 b2) = forceAll [forceVector w1, forceVector b1, forceVector w2, forceVector b2]
forceAdam :: Mlp.AdamState -> ()
forceAdam (Mlp.AdamState step m v) = forceAll [step `seq` (), forceGradient m, forceGradient v]
forceArena :: Arena.RawNativeArenaEvaluation -> ()
forceArena raw =
  forceAll
    [ maybe () forceArenaInput (Arena.nativeArenaEvaluationInput raw)
    , forceList forceEpisode (Arena.nativeArenaEvaluationEpisodes raw)
    , maybe () forceProgress (Arena.nativeArenaEvaluationProgress raw)
    , let summary = Arena.nativeArenaEvaluationForwards raw
       in forceAll
            [ Arena.nativeArenaForwardCalls summary `seq` ()
            , forceList forceForward (Arena.nativeArenaFirstForwards summary)
            , maybe () forceForward (Arena.nativeArenaFailedForward summary)
            ]
    , case Arena.nativeArenaEvaluationStatus raw of
        Arena.NativeArenaEvaluationComplete -> ()
        Arena.NativeArenaEvaluationRejected detail -> textValue detail
        Arena.NativeArenaEvaluationFailed game slot kind detail -> forceAll [game `seq` (), slot `seq` (), kind `seq` (), textValue detail]
    , let work = Arena.nativeArenaEvaluationWork raw
       in forceAll
            [ Arena.nativeArenaCompletedEpisodeTransitions work `seq` ()
            , Arena.nativeArenaCurrentEpisodeTransitions work `seq` ()
            , Arena.nativeArenaCompletedSearchRootVisits work `seq` ()
            , Arena.nativeArenaUnfinishedSearch work `seq` ()
            ]
    ]
forceArenaInput :: Arena.NativeArenaInput -> ()
forceArenaInput input =
  forceAll
    [ Arena.nativeArenaInputScope input `seq` ()
    , maybe
        ()
        ( \spec ->
            forceAll
              [ textValue (Ref.nativeArenaSpecRowId spec)
              , Ref.nativeArenaSpecActionCount spec `seq` ()
              , Ref.nativeArenaSpecObservationSize spec `seq` ()
              , Ref.nativeArenaSpecMaxPlies spec `seq` ()
              , Ref.nativeArenaSpecArenaSimulations spec `seq` ()
              ]
        )
        (Arena.nativeArenaInputSpecification input)
    , forceState (Arena.nativeArenaInputInitialState input)
    , BS.length (Tape.arenaTapeBytes (Arena.nativeArenaInputTape input)) `seq` ()
    , textValue (Tape.arenaTapeSha256 (Arena.nativeArenaInputTape input))
    , forceNet (Arena.nativeArenaInputPolicy input)
    ]
forceForward :: Arena.NativeArenaForwardObservation -> ()
forceForward actual =
  forceAll
    [ Arena.nativeArenaForwardGame actual `seq` ()
    , Arena.nativeArenaForwardSlot actual `seq` ()
    , Arena.nativeArenaForwardOrdinal actual `seq` ()
    , forceParams (Arena.nativeArenaForwardParameters actual)
    , forceVector (Arena.nativeArenaForwardInput actual)
    , case Arena.nativeArenaForwardOutcome actual of
        Arena.NativeArenaForwardException detail -> textValue detail
        Arena.NativeArenaForwardReturned actualOutput -> either textValue forceVector actualOutput
    ]
forceProgress :: Arena.NativeArenaCaseProgress -> ()
forceProgress progress =
  forceAll
    [ Arena.nativeArenaProgressGame progress `seq` ()
    , Arena.nativeArenaProgressTransitions progress `seq` ()
    , forceState (Arena.nativeArenaProgressState progress)
    , forceList forceDecision (Arena.nativeArenaProgressDecisions progress)
    ]
forceDecision :: Ref.NativeArenaDecision -> ()
forceDecision decision =
  forceAll
    [ Ref.nativeArenaDecisionSlot decision `seq` ()
    , forceState (Ref.nativeArenaDecisionRawState decision)
    , forceState (Ref.nativeArenaDecisionNormalizedState decision)
    , Ref.nativeArenaDecisionForcedPass decision `seq` ()
    , Ref.nativeArenaDecisionPlayer decision `seq` ()
    , forceList whnf (Ref.nativeArenaDecisionLegalActions decision)
    , forceVector (Ref.nativeArenaDecisionDistribution decision)
    , Ref.nativeArenaDecisionAction decision `seq` ()
    , forceTapeEntry (Ref.nativeArenaDecisionTapeEntry decision)
    , Ref.nativeArenaDecisionSearchRootVisits decision `seq` ()
    , forceState (Ref.nativeArenaDecisionPostState decision)
    , forceOutcome (Ref.nativeArenaDecisionPostOutcome decision)
    ]
forceEpisode :: Ref.NativeArenaEpisode -> ()
forceEpisode episode =
  forceAll
    [ Ref.nativeArenaEpisodeId episode `seq` ()
    , forceState (Ref.nativeArenaEpisodeInitialState episode)
    , forceState (Ref.nativeArenaEpisodeFinalState episode)
    , forceOutcome (Ref.nativeArenaEpisodeRuleOutcome episode)
    , forceOutcome (Ref.nativeArenaEpisodeScoredOutcome episode)
    , Ref.nativeArenaEpisodeHorizonTruncated episode `seq` ()
    , forceList forceDecision (Ref.nativeArenaEpisodeDecisions episode)
    ]
forceTapeEntry :: Tape.ArenaTapeEntry -> ()
forceTapeEntry entry =
  forceAll
    [ Tape.arenaEntryGame entry `seq` ()
    , Tape.arenaEntrySlot entry `seq` ()
    , Tape.arenaEntrySignedPlayer entry `seq` ()
    , Tape.arenaEntrySideCode entry `seq` ()
    , Tape.arenaEntryQ entry `seq` ()
    , castDoubleToWord64 (Tape.arenaEntryUnit entry) `seq` ()
    , Tape.arenaEntryMctsSeed entry `seq` ()
    ]
forceOutcome :: Game.GameOutcome -> ()
forceOutcome outcome = case outcome of
  Game.GameWon player -> player `seq` ()
  Game.GameInProgress -> ()
  Game.GameDraw -> ()
forceEitherText :: Either Text value -> IO (Either Text value)
forceEitherText value = do
  outer <- evaluate value
  case outer of
    Left reason -> forceText reason >> pure (Left reason)
    Right actual -> pure (Right actual)
forceText :: Text -> IO ()
forceText value = void (evaluate (Text.length value))
textValue :: Text -> ()
textValue value = Text.length value `seq` ()
forceVector :: VU.Vector Double -> ()
forceVector = VU.foldl' (\() value -> castDoubleToWord64 value `seq` ()) ()
forceAll :: [()] -> ()
forceAll = forceList id
forceList :: (value -> ()) -> [value] -> ()
forceList force = foldr (\value rest -> force value `seq` rest) ()
whnf :: value -> ()
whnf value = value `seq` ()
sameNet :: Net.PolicyValueNet -> Net.PolicyValueNet -> Bool
sameNet left right =
  Net.pvnObservationSize left == Net.pvnObservationSize right
    && Net.pvnActionCount left == Net.pvnActionCount right
    && sameParams (Net.pvnParams left) (Net.pvnParams right)
sameParams :: Mlp.MlpParams -> Mlp.MlpParams -> Bool
sameParams a b =
  Mlp.paramShape a == Mlp.paramShape b
    && and
      ( zipWith
          sameVector
          [Mlp.paramW1 a, Mlp.paramB1 a, Mlp.paramW2 a, Mlp.paramB2 a]
          [Mlp.paramW1 b, Mlp.paramB1 b, Mlp.paramW2 b, Mlp.paramB2 b]
      )
sameGradient :: Mlp.MlpGradient -> Mlp.MlpGradient -> Bool
sameGradient a b =
  and
    ( zipWith
        sameVector
        [Mlp.gradW1 a, Mlp.gradB1 a, Mlp.gradW2 a, Mlp.gradB2 a]
        [Mlp.gradW1 b, Mlp.gradB1 b, Mlp.gradW2 b, Mlp.gradB2 b]
    )
sameAdam :: Mlp.AdamState -> Mlp.AdamState -> Bool
sameAdam a b =
  Mlp.adamStep_ a == Mlp.adamStep_ b
    && sameGradient (Mlp.adamM a) (Mlp.adamM b)
    && sameGradient (Mlp.adamV a) (Mlp.adamV b)
sameVector :: VU.Vector Double -> VU.Vector Double -> Bool
sameVector a b =
  VU.length a == VU.length b
    && VU.and (VU.zipWith (\left right -> castDoubleToWord64 left == castDoubleToWord64 right) a b)
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
