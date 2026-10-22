{-# LANGUAGE OverloadedStrings #-}

-- | Fixed native-case numerical observations only. No constructor here proves
-- actual training, producer/device origin, canonical plan membership, durable
-- work, accepted ARS steps, checkpoint admission or qualification.
module JitML.RL.NativeReturnEvaluation
  ( NativeNeuralPolicy (..)
  , NativeEvaluationPolicy (..)
  , NativeForwardOutcome (..)
  , NativeForwardObservation (..)
  , NativeEvaluationFailureKind (..)
  , NativeEvaluationStatus (..)
  , NativeEvaluationWork (..)
  , RawNativeReturnEvaluation (..)
  , nativeReturnEvaluationContract
  , nativeEvaluationObservedForwardCalls
  , validateNativeNeuralReturnContext
  , evaluateNativeNeuralReturnPolicy
  , evaluateNativeArsReturnPolicy
  , nativeArsLegalAction
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, throwIO, tryAny)
import Control.Monad (unless)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU

import JitML.Numerics.Mlp (MlpForward (..), MlpParams)
import JitML.Numerics.MlpDevice (MlpDevice (..))
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.Simulator qualified as Sim

nativeReturnEvaluationContract :: Text
nativeReturnEvaluationContract = "native-return-learned-fixed-cases-data-v1"

-- Raw supplied policy data, not canonical training or initial/final authority.
data NativeNeuralPolicy
  = NativeOnPolicy !Ppo.PpoTrainConfig !MlpParams
  | NativeDqn !Dqn.DqnTrainConfig !MlpParams
  | NativeQrDqn !Qr.QrDqnTrainConfig !MlpParams
  | NativeContinuous !Continuous.ContinuousTrainConfig !MlpParams
  deriving stock (Eq, Show)

data NativeEvaluationPolicy
  = NativeNeuralEvaluation !NativeNeuralPolicy
  | NativeArsHostEvaluation !Ars.ArsTrainConfig !(Vector Double)
  deriving stock (Eq, Show)

data NativeForwardOutcome
  = NativeForwardReturned !(Either Text (Vector Double))
  | NativeForwardException !Text
  deriving stock (Eq, Show)

-- Actual callback arguments/results retained as data. Raw Double vectors retain
-- their bits; Eq/Show is not an authenticated portable binary representation.
data NativeForwardObservation = NativeForwardObservation
  { nativeForwardCaseIndex :: !Int
  , nativeForwardCallIndex :: !Integer
  , nativeForwardParameters :: !MlpParams
  , nativeForwardInput :: !(Vector Double)
  , nativeForwardOutcome :: !NativeForwardOutcome
  }
  deriving stock (Eq, Show)

data NativeEvaluationFailureKind
  = NativeDelegatedLeft
  | NativeSynchronousException
  | NativeInvalidReturnedEpisodes
  | NativeArsInputFailure
  | NativeArsTransitionFailure
  deriving stock (Eq, Show)

data NativeEvaluationStatus
  = NativeEvaluationComplete
  | NativeEvaluationRejected !Text
  | NativeEvaluationFailed !Int !NativeEvaluationFailureKind !Text
  deriving stock (Eq, Show)

-- Failed neural cases have Nothing partial transitions: their delegated Left
-- does not return simulator counters. Forward calls MUST NOT replace them.
data NativeEvaluationWork
  = NativeCompleteWork !Integer
  | NativeRejectedWork
  | NativeFailedWork !Integer !(Maybe Integer)
  deriving stock (Eq, Show)

data RawNativeReturnEvaluation = RawNativeReturnEvaluation
  { nativeEvaluationSpec :: !Ref.NativeReturnReferenceSpec
  , nativeEvaluationPolicy :: !NativeEvaluationPolicy
  , nativeEvaluationEpisodes :: ![Ref.NativeReturnEpisode]
  , nativeEvaluationForwards :: ![NativeForwardObservation]
  , nativeEvaluationStatus :: !NativeEvaluationStatus
  , nativeEvaluationWork :: !NativeEvaluationWork
  , nativeEvaluationFailedReturnedEpisodes :: !(Maybe [Common.EvaluationEpisodeResult])
  }
  deriving stock (Eq, Show)

nativeEvaluationObservedForwardCalls :: RawNativeReturnEvaluation -> Integer
nativeEvaluationObservedForwardCalls = toInteger . length . nativeEvaluationForwards

-- Checks only evaluation context, not a canonical architecture/training recipe.
-- The actual delegated checked evaluator validates numerical parameter tensors
-- before any callback. A prospective prepared/checked DQN dependency is required.
validateNativeNeuralReturnContext
  :: Ref.NativeReturnReferenceSpec -> NativeNeuralPolicy -> Either Text ()
validateNativeNeuralReturnContext spec policy = do
  validateSpec spec
  let algorithm = Ref.nativeReturnSpecAlgorithm spec
      width = Ref.nativeReturnSpecObservationSize spec
      horizon = Ref.nativeReturnSpecHorizon spec
      actions = discreteCount spec
  case policy of
    NativeOnPolicy config _ -> do
      require
        (onPolicyAlgorithm (Ppo.ppoVariant config) == algorithm)
        "native return on-policy variant differs from the specified row"
      require
        ( actions == Just (Ppo.ppoActionCount config)
            && width == Ppo.ppoObsSize config
            && horizon == Ppo.ppoMaxEpisodeSteps config
        )
        "native return on-policy evaluation dimensions differ from the fixed context"
    NativeDqn config _ -> do
      require (algorithm == "DQN") "native return DQN family differs from the specified row"
      require
        ( actions == Just (Dqn.dqnActionCount config)
            && width == Dqn.dqnObsSize config
            && horizon == Dqn.dqnMaxEpisodeSteps config
        )
        "native return DQN evaluation dimensions differ from the fixed context"
    NativeQrDqn config _ -> do
      require (algorithm == "QR-DQN") "native return QR-DQN family differs from the specified row"
      require
        ( actions == Just (Qr.qrActionCount config)
            && width == Qr.qrObsSize config
            && horizon == Qr.qrMaxEpisodeSteps config
        )
        "native return QR-DQN evaluation dimensions differ from the fixed context"
    NativeContinuous config _ -> do
      require
        (continuousAlgorithm (Continuous.ctVariant config) == algorithm)
        "native return continuous variant differs from the specified row"
      require
        ( width == Continuous.ctObsSize config
            && horizon == Continuous.ctMaxEpisodeSteps config
            && Continuous.ctEnvName config == Ref.nativeReturnSpecEnvironment spec
        )
        "native return continuous evaluation context differs from the fixed context"
      case Ref.nativeReturnSpecDomain spec of
        Ref.NativeContinuous lo hi ->
          require
            (Continuous.ctActionLow config == lo && Continuous.ctActionHigh config == hi)
            "native return continuous action bounds differ from the actual native domain"
        _ -> Left "native return continuous policy supplied for a discrete domain"

validateSpec :: Ref.NativeReturnReferenceSpec -> Either Text ()
validateSpec spec = do
  expected <-
    Ref.canonicalNativeReturnSpec
      (Ref.nativeReturnSpecAlgorithm spec)
      (Ref.nativeReturnSpecEnvironment spec)
  require
    ( spec == expected
        && Ref.nativeReturnSpecEpisodeCount spec == 20
        && Ref.nativeReturnSpecHorizon spec > 0
    )
    "native return fixed-case specification differs from the exact declared context"

discreteCount :: Ref.NativeReturnReferenceSpec -> Maybe Int
discreteCount spec = case Ref.nativeReturnSpecDomain spec of
  Ref.NativeUnmaskedDiscrete count -> Just count
  Ref.NativeMaskedDiscrete count -> Just count
  Ref.NativeContinuous {} -> Nothing

onPolicyAlgorithm :: Ppo.OnPolicyVariant -> Text
onPolicyAlgorithm variant = case variant of
  Ppo.VariantPPO -> "PPO"
  Ppo.VariantA2C -> "A2C"
  Ppo.VariantTRPO -> "TRPO"
  Ppo.VariantMaskablePPO -> "MaskablePPO"
  Ppo.VariantRecurrentPPO -> "RecurrentPPO"

continuousAlgorithm :: Continuous.ContinuousVariant -> Text
continuousAlgorithm variant = case variant of
  Continuous.VariantDDPG -> "DDPG"
  Continuous.VariantTD3 -> "TD3"
  Continuous.VariantSAC -> "SAC"
  Continuous.VariantCrossQ -> "CrossQ"
  Continuous.VariantTQC -> "TQC"

-- | The provided device is used unchanged except for recording actual scalar
-- forwards. This is data, not an attestation that an injected device is real.
-- Async exceptions are deliberately not caught by safe-exceptions' tryAny.
evaluateNativeNeuralReturnPolicy
  :: MlpDevice
  -> Ref.NativeReturnReferenceSpec
  -> NativeNeuralPolicy
  -> IO RawNativeReturnEvaluation
evaluateNativeNeuralReturnPolicy device spec policy =
  case validateNativeNeuralReturnContext spec policy of
    Left err -> pure (rejected spec (NativeNeuralEvaluation policy) err)
    Right () -> collect 0 [] []
 where
  collect caseIndex episodes forwards
    | caseIndex >= Ref.nativeReturnSpecEpisodeCount spec =
        pure
          ( result
              episodes
              forwards
              NativeEvaluationComplete
              (NativeCompleteWork (episodeWork episodes))
              Nothing
          )
    | otherwise = do
        observed <- newIORef []
        ordinal <- newIORef (0 :: Integer)
        let record outcome params input = do
              index <- readIORef ordinal
              modifyIORef' ordinal (+ 1)
              modifyIORef' observed (NativeForwardObservation caseIndex index params input outcome :)
            captured =
              device
                { mlpdForward = \params input -> do
                    attempted <- tryAny (mlpdForward device params input >>= forceForwardResult)
                    case attempted of
                      Left exception -> do
                        message <- observedExceptionText exception
                        record (NativeForwardException message) params input
                        throwIO exception
                      Right forwarded -> do
                        record (NativeForwardReturned (fmap forwardOutput forwarded)) params input
                        pure forwarded
                }
        attempted <- tryAny (delegate captured >>= forceEpisodeResult)
        current <- reverse <$> readIORef observed
        let allForwards = forwards <> current
            failCase kind err raw =
              pure
                ( result
                    episodes
                    allForwards
                    (NativeEvaluationFailed caseIndex kind err)
                    (NativeFailedWork (episodeWork episodes) Nothing)
                    raw
                )
        case attempted of
          Left exception -> do
            message <- observedExceptionText exception
            failCase NativeSynchronousException message Nothing
          Right (Left err) -> failCase NativeDelegatedLeft err Nothing
          Right (Right [episode]) -> case validateEpisode spec episode of
            Left err -> failCase NativeInvalidReturnedEpisodes err (Just [episode])
            Right () -> collect (caseIndex + 1) (episodes <> [keyEpisode caseIndex episode]) allForwards
          Right (Right raw) ->
            failCase
              NativeInvalidReturnedEpisodes
              "native return delegated evaluator did not return exactly one episode"
              (Just raw)
  result = RawNativeReturnEvaluation spec (NativeNeuralEvaluation policy)
  delegate captured = case policy of
    NativeOnPolicy config params ->
      withDiscrete
        ( \environment ->
            Ppo.evaluateOnPolicyOnDeviceWithEnvironment captured environment config params 1
        )
    NativeDqn config params ->
      withDiscrete
        ( \environment ->
            Dqn.evaluateDqnPolicyWithEnvironment captured environment config params 1
        )
    NativeQrDqn config params ->
      withDiscrete
        ( \environment ->
            Qr.evaluateQrDqnPolicyOnDeviceWithEnvironment captured environment config params 1
        )
    NativeContinuous config params -> case Sim.lookupContinuousEnvironmentByName (Ref.nativeReturnSpecEnvironment spec) of
      Nothing -> pure (Left "native return actual continuous simulator is absent")
      Just environment -> Continuous.evaluateContinuousPolicyOnDeviceWithEnvironment captured environment config params 1
  withDiscrete run = case Sim.lookupSimulatedEnvironmentByName (Ref.nativeReturnSpecEnvironment spec) of
    Nothing -> pure (Left "native return actual discrete simulator is absent")
    Just environment -> run environment

-- Force exactly the returned data this module promises to retain while still
-- inside safe-exceptions' synchronous boundary. Do not traverse unused hidden
-- forward intermediates or change any numeric validation/arithmetic.
forceForwardResult :: Either Text MlpForward -> IO (Either Text MlpForward)
forceForwardResult result = do
  case result of
    Left err -> forceObservedText err
    Right forward -> do
      _ <- evaluate (VU.foldl' (\() value -> value `seq` ()) () (forwardOutput forward))
      pure ()
  pure result

forceEpisodeResult
  :: Either Text [Common.EvaluationEpisodeResult]
  -> IO (Either Text [Common.EvaluationEpisodeResult])
forceEpisodeResult result = do
  case result of
    Left err -> forceObservedText err
    Right episodes -> do
      _ <- evaluate (foldr forceEpisode () episodes)
      pure ()
  pure result
 where
  forceEpisode episode rest =
    Common.evaluationEpisodeReward episode `seq`
      Common.evaluationEpisodeSteps episode `seq`
        Common.evaluationEpisodeTerminated episode `seq`
          rest

forceObservedText :: Text -> IO ()
forceObservedText message = do
  _ <- evaluate (Text.length message)
  pure ()

-- Even an exception's custom renderer may fail synchronously. This fallback
-- reports that limit; it does not invent the original exception's message.
-- Async cancellation continues to propagate through both safe tryAny calls.
observedExceptionText :: SomeException -> IO Text
observedExceptionText exception = do
  attempted <- tryAny $ do
    let message = Text.pack (displayException exception)
    forceObservedText message
    pure message
  pure $ case attempted of
    Left _ -> "synchronous exception rendering failed"
    Right message -> message

-- | A genuinely legal host-linear action. Row-major dot arithmetic is exactly
-- the old ARS Double expression; legal candidates are filtered before argmax.
-- Arbitrary finite Double is allowed if the actual legal score stays finite.
nativeArsLegalAction
  :: Int -> Int -> Vector Double -> Vector Double -> Maybe [Bool] -> Either Text Int
nativeArsLegalAction actionCount observationWidth theta observation mask = do
  require
    ( actionCount > 0
        && observationWidth > 0
        && toInteger actionCount * toInteger observationWidth <= toInteger (maxBound :: Int)
        && toInteger (VU.length theta) == toInteger actionCount * toInteger observationWidth
    )
    "native ARS linear parameter dimensions are invalid"
  require
    (VU.length observation == observationWidth && VU.all finite observation && VU.all finite theta)
    "native ARS linear parameters or observation are nonfinite or malformed"
  flags <- case mask of
    Nothing -> Right (replicate actionCount True)
    Just values -> do
      require
        (length values == actionCount && or values)
        "native ARS mask has wrong width or no legal action"
      Right values
  let candidates =
        [ ( index
          , VU.sum (VU.zipWith (*) (VU.slice (index * observationWidth) observationWidth theta) observation)
          )
        | (index, True) <- zip [0 .. actionCount - 1] flags
        ]
  require (all (finite . snd) candidates) "native ARS actual legal linear score is nonfinite"
  case candidates of
    [] -> Left "native ARS mask has no legal action"
    first : rest ->
      Right
        (fst (foldl' (\best candidate -> if snd candidate > snd best then candidate else best) first rest))

evaluateNativeArsReturnPolicy
  :: Ref.NativeReturnReferenceSpec
  -> Ars.ArsTrainConfig
  -> Vector Double
  -> RawNativeReturnEvaluation
evaluateNativeArsReturnPolicy spec config theta =
  case preflight of
    Left err -> rejected spec policy err
    Right () -> case Sim.lookupSimulatedEnvironmentByName (Ref.nativeReturnSpecEnvironment spec) of
      Nothing -> rejected spec policy "native ARS actual discrete simulator is absent"
      Just (Sim.SomeSimulatedEnvironment environment) -> collect environment 0 []
 where
  policy = NativeArsHostEvaluation config theta
  preflight = do
    validateSpec spec
    require
      (Ref.nativeReturnSpecAlgorithm spec == "ARS")
      "native ARS family differs from the specified row"
    require
      ( discreteCount spec == Just (Ars.arsActionCount config)
          && Ref.nativeReturnSpecObservationSize spec == Ars.arsObsSize config
          && Ref.nativeReturnSpecHorizon spec == Ars.arsMaxEpisodeSteps config
      )
      "native ARS evaluation dimensions differ from the fixed context"
    require
      ( toInteger (VU.length theta)
          == toInteger (Ars.arsActionCount config) * toInteger (Ars.arsObsSize config)
          && VU.all finite theta
      )
      "native ARS supplied parameter tensor is malformed or nonfinite"
  collect
    :: Sim.SimulatedEnvironment state -> Int -> [Ref.NativeReturnEpisode] -> RawNativeReturnEvaluation
  collect environment caseIndex episodes
    | caseIndex >= Ref.nativeReturnSpecEpisodeCount spec =
        RawNativeReturnEvaluation
          spec
          policy
          episodes
          []
          NativeEvaluationComplete
          (NativeCompleteWork (episodeWork episodes))
          Nothing
    | otherwise = case episode environment caseIndex (Sim.envInitial environment) 0 0 of
        Left (kind, err, steps) ->
          RawNativeReturnEvaluation
            spec
            policy
            episodes
            []
            (NativeEvaluationFailed caseIndex kind err)
            (NativeFailedWork (episodeWork episodes) (Just steps))
            Nothing
        Right completed -> collect environment (caseIndex + 1) (episodes <> [completed])
  episode
    :: Sim.SimulatedEnvironment state
    -> Int
    -> state
    -> Int
    -> Double
    -> Either (NativeEvaluationFailureKind, Text, Integer) Ref.NativeReturnEpisode
  episode environment caseIndex state steps reward
    | steps >= Ars.arsMaxEpisodeSteps config =
        Right (Ref.NativeReturnEpisode caseIndex reward steps False)
    | otherwise = do
        let observation = VU.fromList (Sim.renderObservation (Sim.envRenderFrame environment state))
            mask = Sim.envActionMask environment <*> Just state
        action <- case nativeArsLegalAction (Ars.arsActionCount config) (Ars.arsObsSize config) theta observation mask of
          Left err -> Left (NativeArsInputFailure, err, toInteger steps)
          Right value -> Right value
        let transition = Sim.envStep environment state action
            nextReward = reward + Sim.simStepReward transition
            nextSteps = steps + 1
            successorObservation = Sim.renderObservation (Sim.envRenderFrame environment (Sim.simStepState transition))
        if not
          ( finite (Sim.simStepReward transition)
              && finite nextReward
              && length successorObservation == Ars.arsObsSize config
              && all finite successorObservation
          )
          then
            Left
              ( NativeArsTransitionFailure
              , "native ARS actual reward or successor observation is nonfinite or malformed"
              , toInteger nextSteps
              )
          else
            if Sim.simStepDone transition
              then Right (Ref.NativeReturnEpisode caseIndex nextReward nextSteps True)
              else episode environment caseIndex (Sim.simStepState transition) nextSteps nextReward

validateEpisode :: Ref.NativeReturnReferenceSpec -> Common.EvaluationEpisodeResult -> Either Text ()
validateEpisode spec episode =
  require
    ( finite (Common.evaluationEpisodeReward episode)
        && Common.evaluationEpisodeSteps episode > 0
        && Common.evaluationEpisodeSteps episode <= Ref.nativeReturnSpecHorizon spec
        && ( Common.evaluationEpisodeTerminated episode
               || Common.evaluationEpisodeSteps episode == Ref.nativeReturnSpecHorizon spec
           )
    )
    "native return actual returned episode is incomplete or nonfinite"

keyEpisode :: Int -> Common.EvaluationEpisodeResult -> Ref.NativeReturnEpisode
keyEpisode index episode =
  Ref.NativeReturnEpisode
    index
    (Common.evaluationEpisodeReward episode)
    (Common.evaluationEpisodeSteps episode)
    (Common.evaluationEpisodeTerminated episode)

episodeWork :: [Ref.NativeReturnEpisode] -> Integer
episodeWork = sum . map (toInteger . Ref.nativeReturnEpisodeSteps)

rejected
  :: Ref.NativeReturnReferenceSpec -> NativeEvaluationPolicy -> Text -> RawNativeReturnEvaluation
rejected spec policy err =
  RawNativeReturnEvaluation
    spec
    policy
    []
    []
    (NativeEvaluationRejected err)
    NativeRejectedWork
    Nothing

finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)

require :: Bool -> Text -> Either Text ()
require condition message = unless condition (Left message)
