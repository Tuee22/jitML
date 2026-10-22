-- | Supplied actual observations, including failed/nonfinite returns and known
-- prefix/Unknown work. No evaluation or fixed-case regeneration occurs here.
module JitML.Checkpoint.NativePhase.Projection.Evaluations
  ( returnEvaluation
  , herEvaluation
  , parametersFor
  , returnedForward
  , exceptionForward
  ) where

import Data.Text (Text)
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.NativePhase.Projection.Build
import JitML.Checkpoint.NativePhase.Projection.Cases
import JitML.Checkpoint.NativePhase.Projection.Values
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.NativeHerEvaluation qualified as Her
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef

-- Reuse only after bit-exact equality with the actual supplied policy, never
-- Double Eq or a nominal expected policy. Distinct actual params remain data.
parametersFor :: Maybe (Mlp.MlpParams, Digest) -> Mlp.MlpParams -> Build Digest
parametersFor fixed actual = case fixed of
  Just (known, digest) | sameParams known actual -> pure digest
  _ -> parameters actual
 where
  sameParams a b =
    Mlp.paramShape a == Mlp.paramShape b
      && sameVector (Mlp.paramW1 a) (Mlp.paramW1 b)
      && sameVector (Mlp.paramB1 a) (Mlp.paramB1 b)
      && sameVector (Mlp.paramW2 a) (Mlp.paramW2 b)
      && sameVector (Mlp.paramB2 a) (Mlp.paramB2 b)
  sameVector a b =
    VU.length a == VU.length b
      && VU.ifoldl'
        (\equal i value -> equal && castDoubleToWord64 value == castDoubleToWord64 (b VU.! i))
        True
        a

returnedForward :: Either Text (Vector Double) -> Build NodeValue
returnedForward actual = case actual of
  Left detail -> do
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 1, text])
  Right values -> do
    actualVector <- tensor values
    pure (VList [VWord 0, VRef actualVector])

exceptionForward :: Text -> Build NodeValue
exceptionForward detail = do
  text <- textValue DiagnosticTextBytes detail
  pure (VList [VWord 2, text])

returnEvaluation :: Return.RawNativeReturnEvaluation -> Build Digest
returnEvaluation actual = do
  spec <- returnSpec (Return.nativeEvaluationSpec actual)
  (policy, fixed) <- returnPolicy (Return.nativeEvaluationPolicy actual)
  episodes <-
    referenceSequence (RefElement NReturnEpisode) returnEpisode (Return.nativeEvaluationEpisodes actual)
  forwards <-
    referenceSequence
      (RefElement NReturnForward)
      (returnForward fixed)
      (Return.nativeEvaluationForwards actual)
  status <- returnStatus (Return.nativeEvaluationStatus actual)
  work <- returnWork (Return.nativeEvaluationWork actual)
  failedReturned <- case Return.nativeEvaluationFailedReturnedEpisodes actual of
    Nothing -> pure VNull
    Just values -> VRef <$> referenceSequence (RefElement NCommonEpisode) commonEpisode values
  emit
    NReturnEvaluation
    [VRef spec, VRef policy, VRef episodes, VRef forwards, status, work, failedReturned]

returnPolicy :: Return.NativeEvaluationPolicy -> Build (Digest, Maybe (Mlp.MlpParams, Digest))
returnPolicy actual = case actual of
  Return.NativeNeuralEvaluation neural -> case neural of
    Return.NativeOnPolicy config values -> do
      c <- ppoConfig config
      shared 0 c values
    Return.NativeDqn config values -> do
      c <- dqnConfig config
      shared 1 c values
    Return.NativeQrDqn config values -> do
      c <- qrConfig config
      shared 2 c values
    Return.NativeContinuous config values -> do
      c <- continuousConfig config
      shared 3 c values
  Return.NativeArsHostEvaluation config values -> do
    c <- arsConfig config
    p <- tensor values
    root <- emit NReturnPolicy [VWord 5, VRef c, VRef p]
    pure (root, Nothing)
 where
  shared family config actualParams = do
    p <- parameters actualParams
    root <- emit NReturnPolicy [VWord family, VRef config, VRef p]
    pure (root, Just (actualParams, p))

returnEpisode :: ReturnRef.NativeReturnEpisode -> Build Digest
returnEpisode (ReturnRef.NativeReturnEpisode identity reward steps terminated) = do
  i <- intValue identity
  s <- intValue steps
  emit NReturnEpisode [i, bitValue reward, s, VBool terminated]

commonEpisode :: Common.EvaluationEpisodeResult -> Build Digest
commonEpisode (Common.EvaluationEpisodeResult reward steps terminated) = do
  s <- intValue steps
  emit NCommonEpisode [bitValue reward, s, VBool terminated]

returnForward :: Maybe (Mlp.MlpParams, Digest) -> Return.NativeForwardObservation -> Build Digest
returnForward fixed actual = do
  identity <- intValue (Return.nativeForwardCaseIndex actual)
  ordinal <- integerValue (Return.nativeForwardCallIndex actual)
  params <- parametersFor fixed (Return.nativeForwardParameters actual)
  input <- tensor (Return.nativeForwardInput actual)
  outcome <- case Return.nativeForwardOutcome actual of
    Return.NativeForwardReturned value -> returnedForward value
    Return.NativeForwardException detail -> exceptionForward detail
  emit NReturnForward [identity, ordinal, VRef params, VRef input, outcome]

returnStatus :: Return.NativeEvaluationStatus -> Build NodeValue
returnStatus actual = case actual of
  Return.NativeEvaluationComplete -> pure (VList [VWord 0])
  Return.NativeEvaluationRejected detail -> do
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 1, text])
  Return.NativeEvaluationFailed identity kind detail -> do
    i <- intValue identity
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 2, i, returnFailureKind kind, text])

returnFailureKind :: Return.NativeEvaluationFailureKind -> NodeValue
returnFailureKind value = VWord $ case value of
  Return.NativeDelegatedLeft -> 0
  Return.NativeSynchronousException -> 1
  Return.NativeInvalidReturnedEpisodes -> 2
  Return.NativeArsInputFailure -> 3
  Return.NativeArsTransitionFailure -> 4

returnWork :: Return.NativeEvaluationWork -> Build NodeValue
returnWork actual = case actual of
  Return.NativeCompleteWork observed -> do
    value <- integerValue observed
    pure (VList [VWord 0, value])
  Return.NativeRejectedWork -> pure (VList [VWord 1])
  Return.NativeFailedWork completed partial -> do
    known <- integerValue completed
    current <- maybe (pure VNull) integerValue partial
    pure (VList [VWord 2, known, current])

herEvaluation :: Her.RawNativeHerEvaluation -> Build Digest
herEvaluation actual = do
  schedule <- herSchedule (Her.nativeHerEvaluationSchedule actual)
  config <- herConfig (Her.nativeHerEvaluationConfig actual)
  let actualParams = Her.nativeHerEvaluationParameters actual
  params <- parameters actualParams
  outcomes <-
    referenceSequence (RefElement NHerOutcome) herOutcome (Her.nativeHerEvaluationOutcomes actual)
  forwards <-
    referenceSequence
      (RefElement NHerForward)
      (herForward (Just (actualParams, params)))
      (Her.nativeHerEvaluationForwards actual)
  status <- herStatus (Her.nativeHerEvaluationStatus actual)
  work <- herWork (Her.nativeHerEvaluationWork actual)
  progress <- optional herProgress (Her.nativeHerEvaluationFailedProgress actual)
  emit
    NHerEvaluation
    [VRef schedule, VRef config, VRef params, VRef outcomes, VRef forwards, status, work, progress]

herOutcome :: HerRef.NativeHerReferenceOutcome -> Build Digest
herOutcome actual = do
  identity <- intValue (HerRef.nativeHerOutcomeCaseId actual)
  goal <- tensor (HerRef.nativeHerOutcomeGoal actual)
  state <- tensor (HerRef.nativeHerOutcomeFinalState actual)
  hamming <- intValue (HerRef.nativeHerOutcomeHammingDistance actual)
  steps <- intValue (HerRef.nativeHerOutcomeSteps actual)
  actions <- scalarSequenceWith ScalarInt intValue (HerRef.nativeHerOutcomeConsumedActions actual)
  emit
    NHerOutcome
    [ identity
    , VRef goal
    , VRef state
    , VBool (HerRef.nativeHerOutcomeSuccess actual)
    , bitValue (HerRef.nativeHerOutcomeNormalizedDistance actual)
    , hamming
    , steps
    , VBool (HerRef.nativeHerOutcomeTerminated actual)
    , VRef actions
    ]

herForward :: Maybe (Mlp.MlpParams, Digest) -> Her.NativeHerForwardObservation -> Build Digest
herForward fixed actual = do
  identity <- intValue (Her.nativeHerForwardCaseId actual)
  ordinal <- intValue (Her.nativeHerForwardCallIndex actual)
  params <- parametersFor fixed (Her.nativeHerForwardParameters actual)
  input <- tensor (Her.nativeHerForwardInput actual)
  outcome <- case Her.nativeHerForwardOutcome actual of
    Her.NativeHerForwardReturned value -> returnedForward value
    Her.NativeHerForwardException detail -> exceptionForward detail
  emit NHerForward [identity, ordinal, VRef params, VRef input, outcome]

herProgress :: Her.NativeHerCaseProgress -> Build Digest
herProgress actual = do
  identity <- intValue (Her.nativeHerProgressCaseId actual)
  goal <- tensor (Her.nativeHerProgressGoal actual)
  state <- tensor (Her.nativeHerProgressState actual)
  actions <- scalarSequenceWith ScalarInt intValue (Her.nativeHerProgressActions actual)
  transitions <- intValue (Her.nativeHerProgressTransitions actual)
  let phase = VWord $ case Her.nativeHerProgressPhase actual of
        Her.NativeHerBeforeForward -> 0
        Her.NativeHerCheckingOutput -> 1
        Her.NativeHerApplyingTransition -> 2
        Her.NativeHerProducingOutcome -> 3
  emit NHerProgress [identity, VRef goal, VRef state, VRef actions, transitions, phase]

herStatus :: Her.NativeHerEvaluationStatus -> Build NodeValue
herStatus actual = case actual of
  Her.NativeHerEvaluationComplete -> pure (VList [VWord 0])
  Her.NativeHerEvaluationRejected kind detail -> do
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 1, herFailureKind kind, text])
  Her.NativeHerEvaluationFailed identity kind detail -> do
    i <- intValue identity
    text <- textValue DiagnosticTextBytes detail
    pure (VList [VWord 2, i, herFailureKind kind, text])

herFailureKind :: Her.NativeHerEvaluationFailureKind -> NodeValue
herFailureKind value = VWord $ case value of
  Her.NativeHerContextRejected -> 0
  Her.NativeHerDeviceRejected -> 1
  Her.NativeHerSynchronousException -> 2
  Her.NativeHerInvalidOutput -> 3
  Her.NativeHerInvalidTransition -> 4
  Her.NativeHerInvalidOutcome -> 5

herWork :: Her.NativeHerEvaluationWork -> Build NodeValue
herWork actual = case actual of
  Her.NativeHerCompleteWork observed -> do
    value <- integerValue observed
    pure (VList [VWord 0, value])
  Her.NativeHerRejectedWork -> pure (VList [VWord 1])
  Her.NativeHerFailedWork completed current unknown -> do
    c <- integerValue completed
    p <- integerValue current
    u <- maybe (pure VNull) integerValue unknown
    pure (VList [VWord 2, c, p, u])
