-- | Complete failure DATA assembled from already captured payload references.
-- This module never retries an unsafe payload, runs a trainer or acknowledges
-- storage. The phase codec validates every referenced object independently.
module JitML.Checkpoint.NativePhase.Failure
  ( NativeAttemptFamily (..)
  , NativeFailureOrigin (..)
  , NativeReturnMaterialization (..)
  , NativeSizeKnowledge (..)
  , NativeFailureCaptureStatus (..)
  , NativePayloadCapture (..)
  , NativeFailurePayloads (..)
  , emptyNativeFailurePayloads
  , NativeDiagnosticData (..)
  , captureNativeDiagnostic
  , captureNativeExceptionDiagnostic
  , projectSafeFailureData
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)

import JitML.Checkpoint.NativePhase.Graph (NodePool)
import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Types
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural

data NativeAttemptFamily
  = NativeOnPolicyFamily
  | NativeDqnFamily
  | NativeQrFamily
  | NativeContinuousFamily
  | NativeHerFamily
  | NativeArsFamily
  | NativeArenaFamily
  deriving stock (Eq, Show)

data NativeFailureOrigin
  = NativeNeuralStageFailure !NativeAttemptFamily !Neural.NativeAttemptFailure
  | NativeArsStageFailure !Ars.NativeArsFailure
  | NativeArenaStageFailure !Arena.NativeArenaFailure
  | NativePhaseCaptureFailure
      !NativeAttemptFamily
      !PhaseTag
      !NativeFailureCaptureStatus
      !NativeDiagnosticData

data NativeReturnMaterialization
  = NoReturnObserved
  | ReturnedButUnmaterializable
  | MaterializedBindingRejected
  | MaterializedReturned
  deriving stock (Eq, Show)

data NativeSizeKnowledge
  = ExactNativeSize !Word64
  | LowerBoundNativeSize !Word64
  | UnknownNativeSize
  deriving stock (Eq, Show)

data NativeFailureCaptureStatus
  = CompleteNativeFailureCapture
  | UnsupportedNativeCapture !Text !Text
  | RefusedNativeCapture !Resource !Word64 !NativeSizeKnowledge
  | SynchronousNativeCaptureFailure !Text
  deriving stock (Eq, Show)

-- Only Present carries a reference. A refusal records what is known about
-- size; a conservative construction bound must not be called an exact size
-- or a lower bound on unique encoded bytes.
data NativePayloadCapture
  = NativePayloadPresent !Digest
  | NativePayloadAbsent
  | NativePayloadUnavailable
  | NativePayloadUnmaterializable
  | NativePayloadRefused !Resource !Word64 !NativeSizeKnowledge
  | NativePayloadNotAttempted
  deriving stock (Eq, Show)

data NativeFailurePayloads = NativeFailurePayloads
  { nativeFailureSnapshotPayload :: !NativePayloadCapture
  , nativeFailureColdSnapshotPayload :: !NativePayloadCapture
  , nativeFailureRawPayload :: !NativePayloadCapture
  , nativeFailureInitialEvaluationPayload :: !NativePayloadCapture
  , nativeFailureCurrentEvaluationPayload :: !NativePayloadCapture
  , nativeFailureLowPayload :: !NativePayloadCapture
  }
  deriving stock (Eq, Show)

-- Use actual getter absence only after observing a getter. The initial record
-- explicitly says capture has not been attempted for any of its six slots.
emptyNativeFailurePayloads :: NativeFailurePayloads
emptyNativeFailurePayloads =
  NativeFailurePayloads
    NativePayloadNotAttempted
    NativePayloadNotAttempted
    NativePayloadNotAttempted
    NativePayloadNotAttempted
    NativePayloadNotAttempted
    NativePayloadNotAttempted

data NativeDiagnosticData
  = CompleteNativeDiagnostic !Text
  | OversizeNativeDiagnostic !NativeSizeKnowledge
  | UnmaterializableNativeDiagnostic
  deriving stock (Eq, Show)

-- | Fully materialize at most the bounded UTF8 text. Preserve exact absence
-- when formatting/materialization fails. safe-exceptions propagates async
-- cancellation; a prefix is never returned as a complete diagnostic.
-- | Bound a user-defined exception renderer before constructing Text. An
-- incomplete/lazy renderer yields no substituted complete prefix. A character
-- count is only a lower bound on UTF8 bytes; the ordinary Text capture then
-- applies the exact diagnostic byte limit. Async cancellation propagates.
captureNativeExceptionDiagnostic :: SomeException -> IO NativeDiagnosticData
captureNativeExceptionDiagnostic exception = do
  captured <- tryAny $ do
    let cap = nativePhaseLimit DiagnosticTextBytes
        characters = take (fromInteger cap + 1) (displayException exception)
        count = toInteger (length characters)
    _ <- evaluate count
    if count > cap
      then pure (OversizeNativeDiagnostic (LowerBoundNativeSize (fromInteger count)))
      else captureNativeDiagnostic (Text.pack characters)
  pure $ case captured of
    Right actual -> actual
    Left _ -> UnmaterializableNativeDiagnostic

captureNativeDiagnostic :: Text -> IO NativeDiagnosticData
captureNativeDiagnostic detail = do
  attempted <- tryAny (evaluate materialized)
  pure $ case attempted of
    Left _ -> UnmaterializableNativeDiagnostic
    Right actual -> actual
 where
  cap = nativePhaseLimit DiagnosticTextBytes
  materialized =
    let characters = toInteger (Text.length detail)
     in if characters > cap
          then OversizeNativeDiagnostic (LowerBoundNativeSize (fromInteger characters))
          else
            let bytes = toInteger (BS.length (UTF8.encodeUtf8 detail))
             in if bytes > cap
                  then OversizeNativeDiagnostic (ExactNativeSize (fromInteger bytes))
                  else Text.length detail `seq` CompleteNativeDiagnostic detail

projectSafeFailureData
  :: NodePool
  -> NativeFailureOrigin
  -> NativeReturnMaterialization
  -> NativeFailureCaptureStatus
  -> NativeFailurePayloads
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectSafeFailureData pool origin returned capture payloads = do
  diagnostic <- captureDiagnosticData (originDiagnostic origin)
  projectSafely pool $ do
    let (family, stage, kind) = originValues origin
        slots =
          [ nativeFailureSnapshotPayload payloads
          , nativeFailureColdSnapshotPayload payloads
          , nativeFailureRawPayload payloads
          , nativeFailureInitialEvaluationPayload payloads
          , nativeFailureCurrentEvaluationPayload payloads
          , nativeFailureLowPayload payloads
          ]
    diagnosticValue <- diagnosticData diagnostic
    captureValue <- captureData capture
    kindValue <- case kind of
      Left observed -> pure observed
      Right refused -> do
        actual <- captureData refused
        pure (VList [VWord 1, actual])
    coverage <- traverse payloadCoverage slots
    emit
      NSafeFailure
      ( [ VWord (familyTag family)
        , stage
        , kindValue
        , diagnosticValue
        , VWord (materializationTag returned)
        , captureValue
        , VList coverage
        ]
          <> fmap payloadReference slots
      )

-- Force the supplied diagnostic alternative inside the safe IO boundary too:
-- an outer lazy constructor must not escape before its text is inspected.
captureDiagnosticData :: NativeDiagnosticData -> IO NativeDiagnosticData
captureDiagnosticData supplied = do
  attempted <- tryAny (evaluate supplied)
  case attempted of
    Left _ -> pure UnmaterializableNativeDiagnostic
    Right (CompleteNativeDiagnostic detail) -> captureNativeDiagnostic detail
    Right actual -> pure actual

originDiagnostic :: NativeFailureOrigin -> NativeDiagnosticData
originDiagnostic value = case value of
  NativeNeuralStageFailure _ failure -> CompleteNativeDiagnostic (Neural.nativeFailureDetail failure)
  NativeArsStageFailure failure -> CompleteNativeDiagnostic (Ars.nativeArsFailureDetail failure)
  NativeArenaStageFailure failure -> CompleteNativeDiagnostic (Arena.nativeAlphaZeroFailureDetail failure)
  NativePhaseCaptureFailure _ _ _ diagnostic -> diagnostic

originValues
  :: NativeFailureOrigin
  -> (NativeAttemptFamily, NodeValue, Either NodeValue NativeFailureCaptureStatus)
originValues value = case value of
  NativeNeuralStageFailure family failure ->
    ( family
    , observedStage 0 (neuralStage (Neural.nativeFailureStage failure))
    , Left (observedKind 0 (neuralKind (Neural.nativeFailureKind failure)))
    )
  NativeArsStageFailure failure ->
    ( NativeArsFamily
    , observedStage 1 (arsStage (Ars.nativeArsFailureStage failure))
    , Left (observedKind 1 (arsKind (Ars.nativeArsFailureKind failure)))
    )
  NativeArenaStageFailure failure ->
    ( NativeArenaFamily
    , observedStage 2 (arenaStage (Arena.nativeAlphaZeroFailureStage failure))
    , Left (observedKind 2 (arenaKind (Arena.nativeAlphaZeroFailureKind failure)))
    )
  NativePhaseCaptureFailure family phase capture _ ->
    (family, VList [VWord 1, VWord (phaseTag phase)], Right capture)
 where
  observedStage family stage = VList [VWord 0, VList [VWord family, VWord stage]]
  observedKind family kind = VList [VWord 0, VList [VWord family, VWord kind]]

diagnosticData :: NativeDiagnosticData -> Build NodeValue
diagnosticData value = case value of
  CompleteNativeDiagnostic detail -> do
    actual <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 0, actual])
  OversizeNativeDiagnostic size -> pure (VList [VWord 1, sizeData size])
  UnmaterializableNativeDiagnostic -> pure (VList [VWord 2])

captureData :: NativeFailureCaptureStatus -> Build NodeValue
captureData value = case value of
  CompleteNativeFailureCapture -> pure (VList [VWord 0])
  UnsupportedNativeCapture path reason -> do
    p <- textValue GeneralTextBytes path
    r <- textValue GeneralTextBytes reason
    pure (VList [VWord 1, p, r])
  RefusedNativeCapture resource limit size ->
    pure (VList [VWord 2, VWord (resourceTag resource), VWord limit, sizeData size])
  SynchronousNativeCaptureFailure path -> do
    p <- textValue GeneralTextBytes path
    pure (VList [VWord 3, p])

sizeData :: NativeSizeKnowledge -> NodeValue
sizeData value = case value of
  ExactNativeSize size -> VList [VWord 0, VWord size]
  LowerBoundNativeSize size -> VList [VWord 1, VWord size]
  UnknownNativeSize -> VList [VWord 2]

payloadCoverage :: NativePayloadCapture -> Build NodeValue
payloadCoverage value = pure $ case value of
  NativePayloadPresent _ -> VList [VWord 0]
  NativePayloadAbsent -> VList [VWord 1]
  NativePayloadUnavailable -> VList [VWord 2]
  NativePayloadUnmaterializable -> VList [VWord 3]
  NativePayloadRefused resource limit size ->
    VList [VWord 4, VWord (resourceTag resource), VWord limit, sizeData size]
  NativePayloadNotAttempted -> VList [VWord 5]

payloadReference :: NativePayloadCapture -> NodeValue
payloadReference (NativePayloadPresent digest) = VRef digest
payloadReference _ = VNull

familyTag :: NativeAttemptFamily -> Word64
familyTag value = case value of
  NativeOnPolicyFamily -> 0
  NativeDqnFamily -> 1
  NativeQrFamily -> 2
  NativeContinuousFamily -> 3
  NativeHerFamily -> 4
  NativeArsFamily -> 5
  NativeArenaFamily -> 6

materializationTag :: NativeReturnMaterialization -> Word64
materializationTag value = case value of
  NoReturnObserved -> 0
  ReturnedButUnmaterializable -> 1
  MaterializedBindingRejected -> 2
  MaterializedReturned -> 3

neuralStage :: Neural.NativeAttemptStage -> Word64
neuralStage value = case value of
  Neural.NativeSelection -> 0
  Neural.NativePreparation -> 1
  Neural.NativeInitialization -> 2
  Neural.NativeInitialEvaluation -> 3
  Neural.NativeTraining -> 4
  Neural.NativeReturnBinding -> 5
  Neural.NativeFinalEvaluation -> 6

neuralKind :: Neural.NativeFailureKind -> Word64
neuralKind value = case value of
  Neural.NativeContextRejected -> 0
  Neural.NativeLowRejected -> 1
  Neural.NativeEvaluationRejected -> 2
  Neural.NativeSynchronousFailure -> 3
  Neural.NativeAlreadyConsumed -> 4

arsStage :: Ars.NativeArsStage -> Word64
arsStage value = case value of
  Ars.NativeArsSelection -> 0
  Ars.NativeArsBeginning -> 1
  Ars.NativeArsPreparation -> 2
  Ars.NativeArsInitialEvaluation -> 3
  Ars.NativeArsTraining -> 4
  Ars.NativeArsReturnMaterialization -> 5
  Ars.NativeArsReturnBinding -> 6
  Ars.NativeArsFinalEvaluation -> 7
  Ars.NativeArsLineage -> 8
  Ars.NativeArsAfterProcess -> 9

arsKind :: Ars.NativeArsFailureKind -> Word64
arsKind value = case value of
  Ars.NativeArsRejected -> 0
  Ars.NativeArsSynchronousFailure -> 1
  Ars.NativeArsAlreadyConsumed -> 2
  Ars.NativeArsUnmaterializable -> 3

arenaStage :: Arena.NativeArenaAttemptStage -> Word64
arenaStage value = case value of
  Arena.NativeArenaSelection -> 0
  Arena.NativeArenaPreparation -> 1
  Arena.NativeArenaInitialEvaluation -> 2
  Arena.NativeArenaTraining -> 3
  Arena.NativeArenaReturnBinding -> 4
  Arena.NativeArenaFinalEvaluation -> 5

arenaKind :: Arena.NativeArenaFailureKind -> Word64
arenaKind value = case value of
  Arena.NativeArenaContextRejected -> 0
  Arena.NativeArenaLowRejected -> 1
  Arena.NativeArenaEvaluationRejected -> 2
  Arena.NativeArenaSynchronousFailure -> 3
  Arena.NativeArenaAlreadyConsumed -> 4
