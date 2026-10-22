{-# LANGUAGE OverloadedStrings #-}

-- | Fixed-case numerical observations of supplied HER policies. No value here
-- proves training, initial/final ownership, provider identity or qualification.
module JitML.RL.NativeHerEvaluation
  ( NativeHerForwardOutcome (..)
  , NativeHerForwardObservation (..)
  , NativeHerEvaluationPhase (..)
  , NativeHerCaseProgress (..)
  , NativeHerEvaluationFailureKind (..)
  , NativeHerEvaluationStatus (..)
  , NativeHerEvaluationWork (..)
  , RawNativeHerEvaluation (..)
  , nativeHerEvaluationContract
  , nativeHerObservedForwardCalls
  , validateNativeHerEvaluationContext
  , evaluateNativeHerPolicy
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Foreign.C.Types (CInt)

import JitML.Numerics.Mlp (MlpForward, MlpParams (..), MlpShape (..), forwardOutput)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.NativeHerReferences qualified as Ref

nativeHerEvaluationContract :: Text
nativeHerEvaluationContract = "native-her-learned-supplied-fixed-goals-data-v1"

data NativeHerForwardOutcome
  = NativeHerForwardReturned !(Either Text (Vector Double))
  | NativeHerForwardException !Text
  deriving stock (Eq, Show)

data NativeHerForwardObservation = NativeHerForwardObservation
  { nativeHerForwardCaseId :: !Int
  , nativeHerForwardCallIndex :: !Int
  , nativeHerForwardParameters :: !MlpParams
  , nativeHerForwardInput :: !(Vector Double)
  , nativeHerForwardOutcome :: !NativeHerForwardOutcome
  }
  deriving stock (Eq, Show)

data NativeHerEvaluationPhase
  = NativeHerBeforeForward
  | NativeHerCheckingOutput
  | NativeHerApplyingTransition
  | NativeHerProducingOutcome
  deriving stock (Eq, Show)

-- Fully observed state only. An in-flight computation is never guessed.
data NativeHerCaseProgress = NativeHerCaseProgress
  { nativeHerProgressCaseId :: !Int
  , nativeHerProgressGoal :: !(Vector Double)
  , nativeHerProgressState :: !(Vector Double)
  , nativeHerProgressActions :: ![Int]
  , nativeHerProgressTransitions :: !Int
  , nativeHerProgressPhase :: !NativeHerEvaluationPhase
  }
  deriving stock (Eq, Show)

data NativeHerEvaluationFailureKind
  = NativeHerContextRejected
  | NativeHerDeviceRejected
  | NativeHerSynchronousException
  | NativeHerInvalidOutput
  | NativeHerInvalidTransition
  | NativeHerInvalidOutcome
  deriving stock (Eq, Show)

data NativeHerEvaluationStatus
  = NativeHerEvaluationComplete
  | NativeHerEvaluationRejected !NativeHerEvaluationFailureKind !Text
  | NativeHerEvaluationFailed !Int !NativeHerEvaluationFailureKind !Text
  deriving stock (Eq, Show)

-- Failed work: exact completed-case transitions, exact observed failed-case
-- prefix, and Maybe total failed-case transitions. Nothing is Unknown, never
-- a substituted forward-call count. No hardware/hidden device-work claim.
data NativeHerEvaluationWork
  = NativeHerCompleteWork !Integer
  | NativeHerRejectedWork
  | NativeHerFailedWork !Integer !Integer !(Maybe Integer)
  deriving stock (Eq, Show)

data RawNativeHerEvaluation = RawNativeHerEvaluation
  { nativeHerEvaluationSchedule :: !Ref.NativeHerGoalSchedule
  , nativeHerEvaluationConfig :: !Her.HerTrainConfig
  , nativeHerEvaluationParameters :: !MlpParams
  , nativeHerEvaluationOutcomes :: ![Ref.NativeHerReferenceOutcome]
  , nativeHerEvaluationForwards :: ![NativeHerForwardObservation]
  , nativeHerEvaluationStatus :: !NativeHerEvaluationStatus
  , nativeHerEvaluationWork :: !NativeHerEvaluationWork
  , nativeHerEvaluationFailedProgress :: !(Maybe NativeHerCaseProgress)
  }
  deriving stock (Eq, Show)

nativeHerObservedForwardCalls :: RawNativeHerEvaluation -> Integer
nativeHerObservedForwardCalls = toInteger . length . nativeHerEvaluationForwards

-- | Numerical evaluation context only, not a canonical training recipe. The
-- opaque supplied schedule already proves sampler membership. Never regenerate
-- or re-sample its goals here; their order and duplicates are authoritative data
-- for this numerical call, not authenticated execution evidence.
validateNativeHerEvaluationContext
  :: Ref.NativeHerGoalSchedule -> Her.HerTrainConfig -> MlpParams -> Either Text ()
validateNativeHerEvaluationContext schedule config params = do
  canonical <- Ref.canonicalNativeHerReferenceSpec
  let spec = Ref.nativeHerScheduleSpec schedule
      bits = Ref.nativeHerSpecBits spec
      hidden = Her.herHiddenUnits config
      inputs = toInteger bits * 2
      expected = MlpShape (2 * bits) hidden bits
  require
    ( spec == canonical
        && bits == 6
        && Ref.nativeHerSpecHorizon spec == 6
        && Ref.nativeHerSpecEpisodeCount spec == 20
    )
    "native HER fixed-goal specification differs from the canonical context"
  require
    ( Her.herNumBits config == bits
        && hidden > 0
        && toInteger hidden <= toInteger (maxBound :: CInt)
        && inputs <= toInteger (maxBound :: CInt)
        && inputs * toInteger hidden <= toInteger (maxBound :: Int)
    )
    "native HER policy dimensions differ from the fixed context or exceed the ABI"
  require
    ( paramShape params == expected
        && toInteger (VU.length (paramW1 params)) == inputs * toInteger hidden
        && VU.length (paramB1 params) == hidden
        && toInteger (VU.length (paramW2 params)) == toInteger bits * toInteger hidden
        && VU.length (paramB2 params) == bits
    )
    "native HER policy parameter tensors differ from the declared shape"
  require
    (all float32Vector [paramW1 params, paramB1 params, paramW2 params, paramB2 params])
    "native HER policy parameters are nonfinite or overflow the Float32 ABI"
  let cases = Ref.nativeHerScheduleCases schedule
  require
    (map Ref.rawNativeHerCaseId cases == [0 .. 19])
    "native HER supplied goal schedule has an invalid ordered case inventory"
  require
    (all (validGoal bits . Ref.rawNativeHerGoal) cases)
    "native HER supplied goal schedule contains an invalid goal"

-- | The exact supplied params and scalar device callback score every supplied
-- case. This operation never initializes/trains, draws RNG, queries a witness,
-- qualifies a policy or authenticates an injected numerical device.
evaluateNativeHerPolicy
  :: MlpDevice
  -> Ref.NativeHerGoalSchedule
  -> Her.HerTrainConfig
  -> MlpParams
  -> IO RawNativeHerEvaluation
evaluateNativeHerPolicy device schedule config params = do
  preflight <- tryAny $ do
    let checked = validateNativeHerEvaluationContext schedule config params
    case checked of
      Left reason -> forceText reason
      Right () -> pure ()
    pure checked
  case preflight of
    Left exception -> do
      message <- exceptionText exception
      pure
        ( result
            []
            []
            (NativeHerEvaluationRejected NativeHerSynchronousException message)
            NativeHerRejectedWork
            Nothing
        )
    Right (Left reason) ->
      pure
        ( result
            []
            []
            (NativeHerEvaluationRejected NativeHerContextRejected reason)
            NativeHerRejectedWork
            Nothing
        )
    Right (Right ()) -> do
      forwards <- newIORef []
      collect forwards [] (Ref.nativeHerScheduleCases schedule)
 where
  bits = Ref.nativeHerSpecBits (Ref.nativeHerScheduleSpec schedule)
  horizon = Ref.nativeHerSpecHorizon (Ref.nativeHerScheduleSpec schedule)
  result = RawNativeHerEvaluation schedule config params
  collect forwards outcomes [] = do
    observed <- reverse <$> readIORef forwards
    pure
      ( result
          outcomes
          observed
          NativeHerEvaluationComplete
          (NativeHerCompleteWork (outcomeWork outcomes))
          Nothing
      )
  collect forwards outcomes (one : remaining) = do
    let caseId = Ref.rawNativeHerCaseId one
        goal = Ref.rawNativeHerGoal one
        initial = NativeHerCaseProgress caseId goal (VU.replicate bits 0) [] 0 NativeHerBeforeForward
    progress <- newIORef initial
    attempted <- tryAny $ runCase forwards progress >>= forceCaseResult
    observed <- reverse <$> readIORef forwards
    current <- readIORef progress
    let failCase kind message total =
          pure
            ( result
                outcomes
                observed
                (NativeHerEvaluationFailed caseId kind message)
                (NativeHerFailedWork (outcomeWork outcomes) (toInteger (nativeHerProgressTransitions current)) total)
                (Just current)
            )
    case attempted of
      Left exception -> do
        message <- exceptionText exception
        -- The prefix is known; a synchronous fault while forcing an in-flight
        -- transition/outcome does not justify an invented returned transition.
        failCase NativeHerSynchronousException message Nothing
      Right (Left (kind, message)) ->
        failCase kind message (Just (toInteger (nativeHerProgressTransitions current)))
      Right (Right outcome) -> collect forwards (outcomes <> [outcome]) remaining
  runCase forwards progress = do
    current <- readIORef progress
    let state = nativeHerProgressState current
        goal = nativeHerProgressGoal current
        steps = nativeHerProgressTransitions current
    if state == goal || steps >= horizon
      then do
        writeIORef progress (current {nativeHerProgressPhase = NativeHerProducingOutcome})
        let distance = Her.bitDistance state goal
            normalized = distance / fromIntegral bits
        if not
          ( finite distance
              && finite normalized
              && distance >= 0
              && distance <= fromIntegral bits
              && distance == fromIntegral (round distance :: Int)
          )
          then pure (Left (NativeHerInvalidOutcome, "native HER observed distance is invalid"))
          else
            pure
              ( Right
                  ( Ref.NativeHerReferenceOutcome
                      (nativeHerProgressCaseId current)
                      goal
                      state
                      (state == goal)
                      normalized
                      (round distance)
                      steps
                      (state == goal)
                      (nativeHerProgressActions current)
                  )
              )
      else do
        writeIORef progress (current {nativeHerProgressPhase = NativeHerBeforeForward})
        let input = state VU.++ goal
        forceVector input
        forwarded <- observeForward device forwards current params input
        case forwarded of
          Left failure -> pure (Left failure)
          Right forward -> do
            writeIORef progress (current {nativeHerProgressPhase = NativeHerCheckingOutput})
            let output = forwardOutput forward
            if VU.length output /= bits || not (float32Vector output)
              then
                pure
                  ( Left
                      (NativeHerInvalidOutput, "native HER device output has the wrong shape or is not finite Float32")
                  )
              else case firstArgmax output of
                Nothing -> pure (Left (NativeHerInvalidOutput, "native HER device output has no action"))
                Just action -> do
                  writeIORef progress (current {nativeHerProgressPhase = NativeHerApplyingTransition})
                  let next = Her.flipBit action state
                  forceVector next
                  if VU.length next /= bits || not (VU.all binary next)
                    then pure (Left (NativeHerInvalidTransition, "native HER actual bit-flip transition is invalid"))
                    else do
                      writeIORef
                        progress
                        ( current
                            { nativeHerProgressState = next
                            , nativeHerProgressActions = nativeHerProgressActions current <> [action]
                            , nativeHerProgressTransitions = steps + 1
                            , nativeHerProgressPhase = NativeHerBeforeForward
                            }
                        )
                      runCase forwards progress

observeForward
  :: MlpDevice
  -> IORef [NativeHerForwardObservation]
  -> NativeHerCaseProgress
  -> MlpParams
  -> Vector Double
  -> IO (Either (NativeHerEvaluationFailureKind, Text) MlpForward)
observeForward device observed progress params input = do
  attempted <- tryAny (mlpdForward device params input >>= forceForward)
  let record outcome =
        modifyIORef'
          observed
          ( NativeHerForwardObservation
              (nativeHerProgressCaseId progress)
              (nativeHerProgressTransitions progress)
              params
              input
              outcome
              :
          )
  case attempted of
    Left exception -> do
      message <- exceptionText exception
      record (NativeHerForwardException message)
      pure (Left (NativeHerSynchronousException, message))
    Right returned -> do
      record (NativeHerForwardReturned (fmap forwardOutput returned))
      pure $ case returned of
        Left reason -> Left (NativeHerDeviceRejected, "native HER device forward failed: " <> reason)
        Right forward -> Right forward

firstArgmax :: Vector Double -> Maybe Int
firstArgmax = fmap fst . VU.ifoldl' choose Nothing
 where
  choose Nothing index value = Just (index, value)
  choose best@(Just (_, score)) index value
    | value > score = Just (index, value)
    | otherwise = best

forceForward :: Either Text MlpForward -> IO (Either Text MlpForward)
forceForward returned = do
  case returned of
    Left reason -> forceText reason
    Right forward -> forceVector (forwardOutput forward)
  pure returned

forceCaseResult
  :: Either (NativeHerEvaluationFailureKind, Text) Ref.NativeHerReferenceOutcome
  -> IO (Either (NativeHerEvaluationFailureKind, Text) Ref.NativeHerReferenceOutcome)
forceCaseResult returned = do
  case returned of
    Left (kind, reason) -> evaluate kind >> forceText reason
    Right outcome -> do
      forceVector (Ref.nativeHerOutcomeGoal outcome)
      forceVector (Ref.nativeHerOutcomeFinalState outcome)
      _ <-
        evaluate
          ( Ref.nativeHerOutcomeCaseId outcome `seq`
              Ref.nativeHerOutcomeSuccess outcome `seq`
                Ref.nativeHerOutcomeNormalizedDistance outcome `seq`
                  Ref.nativeHerOutcomeHammingDistance outcome `seq`
                    Ref.nativeHerOutcomeSteps outcome `seq`
                      Ref.nativeHerOutcomeTerminated outcome `seq`
                        ()
          )
      _ <-
        evaluate
          (foldr seq () (Ref.nativeHerOutcomeConsumedActions outcome))
      pure ()
  pure returned

outcomeWork :: [Ref.NativeHerReferenceOutcome] -> Integer
outcomeWork = sum . map (toInteger . Ref.nativeHerOutcomeSteps)

validGoal :: Int -> Vector Double -> Bool
validGoal bits goal = VU.length goal == bits && VU.all binary goal && VU.any (== 1) goal

binary :: Double -> Bool
binary value = finite value && (value == 0 || value == 1)

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

float32Vector :: Vector Double -> Bool
float32Vector =
  VU.all
    ( \value ->
        finite value && let encoded = realToFrac value :: Float in not (isNaN encoded || isInfinite encoded)
    )

forceVector :: Vector Double -> IO ()
forceVector vector = do
  _ <- evaluate (VU.foldl' (\() value -> value `seq` ()) () vector)
  pure ()

forceText :: Text -> IO ()
forceText reason = do
  _ <- evaluate (Text.length reason)
  pure ()

exceptionText :: SomeException -> IO Text
exceptionText exception = do
  attempted <- tryAny $ do
    let message = Text.pack (displayException exception)
    forceText message
    pure message
  pure $ case attempted of
    Left _ -> "synchronous exception rendering failed"
    Right message -> message

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
