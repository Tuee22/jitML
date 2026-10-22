{-# LANGUAGE OverloadedStrings #-}

-- | One actual canonical reference calculation, with the exact already selected
-- row-owned cases. These captures are neither ACKs nor parent/Store authority.
module JitML.Product.NativeReferenceCalibration
  ( NativeReferenceInput (..)
  , CapturedNativeReferences
  , NativeReferenceObservations (..)
  , NativeReferenceCalibrationFailure
  , NativeReferenceCaptureStage (..)
  , NativeReferenceWork (..)
  , captureNativeReferenceCalibration
  , nativeCapturedReferenceCohort
  , nativeCapturedReferenceData
  , nativeCapturedReferenceBytes
  , nativeCapturedReferenceObservations
  , nativeReferenceFailureStage
  , nativeReferenceFailureCohort
  , nativeReferenceFailureDiagnostic
  , nativeReferenceFailureWork
  , nativeReferenceFailureBytes
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8

import JitML.Checkpoint.NativePhase.CBOR qualified as CBORData
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection.Build qualified as Project
import JitML.Checkpoint.NativePhase.Projection.Cases qualified as Cases
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReferences qualified as Wire
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeArenaLearningPolicy qualified as ArenaPolicy
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.RL.AlphaZero.NativeArenaReferences qualified as ArenaRef
import JitML.RL.NativeHerReferences qualified as Her
import JitML.RL.NativeReturnReferences qualified as Return

-- Opaque canonical descriptors, without devices, results or callbacks. The
-- producer passes the same descriptor that its five numerical children use.
data NativeReferenceInput
  = NativeReferenceNeuralInput !Neural.NativeNeuralRowData
  | NativeReferenceArsInput !Ars.NativeArsRowData
  | NativeReferenceArenaInput !Arena.NativeAlphaZeroRowData

data NativeReferenceObservations
  = NativeReferenceReturnObservations !Return.NativeReturnReferenceSet
  | NativeReferenceHerObservations !Her.NativeHerReferenceFamily
  | NativeReferenceArenaObservations !ArenaPolicy.NativeArenaReferenceCalibration

data CapturedNativeReferences
  = CapturedNativeReferences
      !Cohort.NativeRlCohortPlan
      !Wire.NativeReferenceData
      !NativeReferenceObservations

data NativeReferenceCaptureStage
  = NativeReferenceInputStage
  | NativeReferenceCalculationStage
  | NativeReferenceEncodingStage
  deriving stock (Eq, Show)
data NativeReferenceWork = NativeReferenceWorkUnknown deriving stock (Eq, Show)

-- A failed whole-Either/reference materialization has no safely exposed prefix.
-- Only the actual diagnostic and fully captured optional context are retained.
data NativeReferenceCalibrationFailure
  = NativeReferenceCalibrationFailure
      !NativeReferenceCaptureStage
      !(Maybe Cohort.NativeRlCohortPlan)
      !Failure.NativeDiagnosticData
      !ByteString

data ReferenceCases
  = ReturnCases !Return.NativeReturnReferenceSpec
  | HerCases !Her.NativeHerGoalSchedule
  | ArenaCases !Arena.NativeAlphaZeroRowData

data CapturedInput
  = CapturedInput
      !Cohort.NativeRlCohortPlan
      !Text
      !ByteString
      !Digest
      !Graph.NodePool
      !ReferenceCases

nativeCapturedReferenceCohort :: CapturedNativeReferences -> Cohort.NativeRlCohortPlan
nativeCapturedReferenceCohort (CapturedNativeReferences value _ _) = value
nativeCapturedReferenceData :: CapturedNativeReferences -> Wire.NativeReferenceData
nativeCapturedReferenceData (CapturedNativeReferences _ value _) = value
nativeCapturedReferenceBytes :: CapturedNativeReferences -> ByteString
nativeCapturedReferenceBytes = Wire.nativeReferenceDataBytes . nativeCapturedReferenceData
nativeCapturedReferenceObservations :: CapturedNativeReferences -> NativeReferenceObservations
nativeCapturedReferenceObservations (CapturedNativeReferences _ _ value) = value
nativeReferenceFailureStage :: NativeReferenceCalibrationFailure -> NativeReferenceCaptureStage
nativeReferenceFailureStage (NativeReferenceCalibrationFailure value _ _ _) = value
nativeReferenceFailureCohort :: NativeReferenceCalibrationFailure -> Maybe Cohort.NativeRlCohortPlan
nativeReferenceFailureCohort (NativeReferenceCalibrationFailure _ value _ _) = value
nativeReferenceFailureDiagnostic
  :: NativeReferenceCalibrationFailure -> Failure.NativeDiagnosticData
nativeReferenceFailureDiagnostic (NativeReferenceCalibrationFailure _ _ value _) = value
nativeReferenceFailureWork :: NativeReferenceCalibrationFailure -> NativeReferenceWork
nativeReferenceFailureWork _ = NativeReferenceWorkUnknown
nativeReferenceFailureBytes :: NativeReferenceCalibrationFailure -> ByteString
nativeReferenceFailureBytes (NativeReferenceCalibrationFailure _ _ _ value) = value

captureNativeReferenceCalibration
  :: NativeReferenceInput -> IO (Either NativeReferenceCalibrationFailure CapturedNativeReferences)
captureNativeReferenceCalibration input = do
  stage <- newIORef NativeReferenceInputStage
  known <- newIORef Nothing
  attempted <- tryAny $ do
    checked <- captureInput input
    case checked of
      Left reason -> forceLeft reason
      Right actual@(CapturedInput cohort identity transport spec pool cases) -> do
        -- This stored context has already been completely forced inside the
        -- input catcher. No unobserved/poisoned label is attached on failure.
        writeIORef known (Just actual)
        writeIORef stage NativeReferenceCalculationStage
        observed <- case cases of
          ReturnCases value ->
            pure (NativeReferenceReturnObservations <$> Return.evaluateCanonicalNativeReturnReferences value)
          HerCases value -> pure (NativeReferenceHerObservations <$> Her.evaluateNativeHerReferenceFamily value)
          ArenaCases row ->
            fmap NativeReferenceArenaObservations
              <$> ArenaPolicy.observeNativeArenaReferenceCalibrationOnTape
                (Arena.nativeAlphaZeroRowSpec row)
                (Arena.nativeAlphaZeroRowTape row)
        outer <- evaluate observed
        case outer of
          Left reason -> forceLeft reason
          Right observations -> do
            writeIORef stage NativeReferenceEncodingStage
            let sameInput = case (cases, observations) of
                  (ReturnCases expected, NativeReferenceReturnObservations value) ->
                    Return.nativeReturnObservedSpec value == expected
                  (HerCases expected, NativeReferenceHerObservations value) ->
                    Her.nativeHerObservedSchedule value == expected
                  (ArenaCases row, NativeReferenceArenaObservations value) ->
                    ArenaPolicy.nativeArenaCalibrationSpec value == Arena.nativeAlphaZeroRowSpec row
                      && ArenaPolicy.nativeArenaCalibrationTape value == Arena.nativeAlphaZeroRowTape row
                      && ArenaRef.nativeArenaObservedSpec (ArenaPolicy.nativeArenaCalibrationReferences value)
                        == Arena.nativeAlphaZeroRowSpec row
                  _ -> False
            unless sameInput (fail "actual native reference returned input differs")
            let encoded = case observations of
                  NativeReferenceReturnObservations value -> Wire.encodeNativeReturnReferencesData identity transport spec pool value
                  NativeReferenceHerObservations value -> Wire.encodeNativeHerReferencesData identity transport spec pool value
                  NativeReferenceArenaObservations value ->
                    Wire.encodeNativeArenaReferencesData
                      identity
                      transport
                      spec
                      pool
                      (ArenaPolicy.nativeArenaCalibrationReferences value)
            case encoded of
              Left problem -> forceLeft (Text.pack (show problem))
              Right dataValue -> do
                _ <- evaluate (BS.length (Wire.nativeReferenceDataBytes dataValue))
                pure (Right (CapturedNativeReferences cohort dataValue observations))
  case attempted of
    Right (Right actual) -> pure (Right actual)
    Right (Left detail) -> do
      at <- readIORef stage
      facts <- readIORef known
      diagnostic <- Failure.captureNativeDiagnostic detail
      Left <$> failureData at facts diagnostic
    Left exception -> do
      at <- readIORef stage
      facts <- readIORef known
      diagnostic <- Failure.captureNativeExceptionDiagnostic exception
      Left <$> failureData at facts diagnostic
 where
  forceLeft detail = do
    _ <- evaluate (Text.length detail)
    pure (Left detail)

captureInput :: NativeReferenceInput -> IO (Either Text CapturedInput)
captureInput input = do
  let (batch, cohort, cases) = case input of
        NativeReferenceNeuralInput row ->
          ( Neural.nativeNeuralRowBatch row
          , Neural.nativeNeuralRowCohort row
          , case (Neural.nativeNeuralRowReturnSpec row, Neural.nativeNeuralRowHerSchedule row) of
              (Just value, Nothing) -> Right (ReturnCases value)
              (Nothing, Just value) -> Right (HerCases value)
              _ -> Left "native reference neural row has inconsistent fixed-case alternatives"
          )
        NativeReferenceArsInput row ->
          ( Ars.nativeArsRowBatch row
          , Ars.nativeArsRowCohort row
          , Right (ReturnCases (Ars.nativeArsRowReference row))
          )
        NativeReferenceArenaInput row ->
          (Arena.nativeAlphaZeroRowBatch row, Arena.nativeAlphaZeroRowCohort row, Right (ArenaCases row))
      actualRow = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
      identity = Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)
      transport = Cohort.nativeRlCohortPlanTransport cohort
      checked = do
        refined <-
          Cohort.refineNativeRlCohortBatch
            (Cohort.nativeRlCohortBatchSubstrate batch)
            (Cohort.nativeRlCohortBatchPlans batch)
        unless (refined == batch) (Left "native reference complete batch differs")
        found <-
          maybe
            (Left "native reference row is absent from its complete batch")
            Right
            ( find
                ((== actualRow) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
                (Cohort.nativeRlCohortBatchPlans refined)
            )
        unless (found == cohort) (Left "native reference complete row cohort differs")
        cases
  _ <- evaluate (BS.length (UTF8.encodeUtf8 actualRow))
  _ <- evaluate (BS.length (UTF8.encodeUtf8 identity))
  _ <- evaluate (BS.length transport)
  case checked of
    Left reason -> pure (Left reason)
    Right selected -> do
      let action = case selected of
            ReturnCases value -> Cases.returnSpec value
            HerCases value -> Cases.herSchedule value
            ArenaCases row -> Cases.arenaSpec (Arena.nativeAlphaZeroRowSpec row)
      projected <- Project.projectSafely Graph.emptyNodePool action
      pure $ case projected of
        Left failure -> Left (Text.pack (show failure))
        Right (spec, pool) -> case Wire.checkNativeReferenceInput identity transport spec pool of
          Left problem -> Left (Text.pack (show problem))
          Right () -> Right (CapturedInput cohort identity transport spec pool selected)

failureData
  :: NativeReferenceCaptureStage
  -> Maybe CapturedInput
  -> Failure.NativeDiagnosticData
  -> IO NativeReferenceCalibrationFailure
failureData stage actual diagnostic = do
  let cohort = case actual of Just (CapturedInput value _ _ _ _ _) -> Just value; Nothing -> Nothing
      context = case actual of
        Nothing -> CBOR.encodeNull
        Just (CapturedInput _ identity transport _ _ _) ->
          CBOR.encodeListLen 2 <> CBOR.encodeString identity <> CBOR.encodeBytes transport
      bytes =
        CBORData.encodeStrict
          ( CBOR.encodeListLen 6
              <> CBOR.encodeString "jitml-native-reference-failure-v1"
              <> CBOR.encodeWord64 1
              <> CBOR.encodeWord64
                ( case stage of
                    NativeReferenceInputStage -> 0
                    NativeReferenceCalculationStage -> 1
                    NativeReferenceEncodingStage -> 2
                )
              <> context
              <> diagnosticEncoding diagnostic
              <> CBOR.encodeString "unknown-failed-reference-work"
          )
  _ <- evaluate (BS.length bytes)
  -- Only already materialized, bounded context/diagnostic fields are encoded
  -- here. No original input/payload is retried, and no secondary invariant
  -- exception is introduced while reporting an actual failed calculation.
  pure (NativeReferenceCalibrationFailure stage cohort diagnostic bytes)

diagnosticEncoding :: Failure.NativeDiagnosticData -> CBOR.Encoding
diagnosticEncoding actual = case actual of
  Failure.CompleteNativeDiagnostic detail -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 0 <> CBOR.encodeString detail
  Failure.OversizeNativeDiagnostic size ->
    CBOR.encodeListLen 2 <> CBOR.encodeWord64 1 <> case size of
      Failure.ExactNativeSize value -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 0 <> CBOR.encodeWord64 value
      Failure.LowerBoundNativeSize value -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 1 <> CBOR.encodeWord64 value
      Failure.UnknownNativeSize -> CBOR.encodeListLen 1 <> CBOR.encodeWord64 2
  Failure.UnmaterializableNativeDiagnostic -> CBOR.encodeListLen 1 <> CBOR.encodeWord64 2
