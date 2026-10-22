{-# LANGUAGE OverloadedStrings #-}

-- | Unauthenticated numerical observations. These types neither mint
-- TrainingEvidence nor admit checkpoints; completion means physical budget
-- completion and finite returned data, not learning or convergence.
module JitML.RL.TrainerObservation
  ( ReturnedPolicy (..)
  , EvaluationFailure (..)
  , RawEvaluation (..)
  , TrainingFailure (..)
  , RawTrainerAttempt (..)
  , RawTrainerObservation (..)
  , BudgetCompleteTrainerObservation
  , refineBudgetCompleteTrainerObservation
  , budgetCompleteObservation
  , returnedCounters
  , returnedInitialWeights
  , returnedFinalWeights
  , returnedLearningStatistics
  ) where

import Control.Monad (unless)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.Simulator qualified as Sim

-- Actual family/config/statistics and initial/final values are retained.
data ReturnedPolicy
  = ReturnedOnPolicy !Ppo.PpoTrainObservation
  | ReturnedDqn !Dqn.DqnTrainObservation
  | ReturnedQrDqn !Qr.QrDqnTrainObservation
  | ReturnedContinuous !Continuous.ContinuousTrainObservation
  | ReturnedHer !Her.HerTrainObservation
  | ReturnedArs !Ars.ArsTrainObservation
  deriving stock (Eq, Show)

data EvaluationFailure
  = EvaluationRejected !Text
  | EvaluationThrew !Text
  deriving stock (Eq, Show)

data RawEvaluation
  = EvaluationReturned ![Episode.SimulatedEpisode]
  | HerEvaluationReturned ![(Bool, Double, Int)]
  | EvaluationFailed !EvaluationFailure
  deriving stock (Eq, Show)

data TrainingFailure
  = TrainingRejected !Text
  | TrainingThrew !Text
  deriving stock (Eq, Show)

data RawTrainerObservation = RawTrainerObservation
  { observedPlan :: !Plan.CompiledRlPlan
  , observedPolicy :: !ReturnedPolicy
  , observedEvaluation :: !RawEvaluation
  }
  deriving stock (Eq, Show)

data RawTrainerAttempt
  = TrainerDidNotReturn !TrainingFailure
  | TrainerReturned !RawTrainerObservation
  | -- ALE has no returned trained policy, and is outside product qualification.
    TrainerEvaluationOnly !Framework.EvaluationSet
  deriving stock (Eq, Show)

-- Private constructor and no exported record labels: callers cannot clear refinement.
newtype BudgetCompleteTrainerObservation = BudgetCompleteTrainerObservation RawTrainerObservation
  deriving stock (Eq, Show)

budgetCompleteObservation :: BudgetCompleteTrainerObservation -> RawTrainerObservation
budgetCompleteObservation (BudgetCompleteTrainerObservation observed) = observed

returnedCounters :: ReturnedPolicy -> Common.ObservedTrainerCounters
returnedCounters policy = case policy of
  ReturnedOnPolicy r -> Common.rawTrainerCounters r
  ReturnedDqn r -> Common.rawTrainerCounters r
  ReturnedQrDqn r -> Common.rawTrainerCounters r
  ReturnedContinuous r -> Common.rawTrainerCounters r
  ReturnedHer r -> Common.rawTrainerCounters r
  ReturnedArs r -> Common.rawTrainerCounters r

returnedInitialWeights :: ReturnedPolicy -> [Double]
returnedInitialWeights policy = case policy of
  ReturnedOnPolicy r -> Mlp.mlpParamsToFlat (Common.rawTrainerInitialParams r)
  ReturnedDqn r -> Mlp.mlpParamsToFlat (Common.rawTrainerInitialParams r)
  ReturnedQrDqn r -> Mlp.mlpParamsToFlat (Common.rawTrainerInitialParams r)
  ReturnedContinuous r -> Mlp.mlpParamsToFlat (Common.rawTrainerInitialParams r)
  ReturnedHer r -> Mlp.mlpParamsToFlat (Common.rawTrainerInitialParams r)
  ReturnedArs r -> VU.toList (Common.rawTrainerInitialParams r)

returnedFinalWeights :: ReturnedPolicy -> [Double]
returnedFinalWeights policy = case policy of
  ReturnedOnPolicy r -> Mlp.mlpParamsToFlat (Common.rawTrainerFinalParams r)
  ReturnedDqn r -> Mlp.mlpParamsToFlat (Common.rawTrainerFinalParams r)
  ReturnedQrDqn r -> Mlp.mlpParamsToFlat (Common.rawTrainerFinalParams r)
  ReturnedContinuous r -> Mlp.mlpParamsToFlat (Common.rawTrainerFinalParams r)
  ReturnedHer r -> Mlp.mlpParamsToFlat (Common.rawTrainerFinalParams r)
  ReturnedArs r -> VU.toList (Common.rawTrainerFinalParams r)

-- Preserve the original strict adapter's exact filters; raw results keep all
-- the omitted statistics as well, through their family-specific record.
returnedLearningStatistics :: ReturnedPolicy -> (Text, [(Int, Double)])
returnedLearningStatistics policy = case policy of
  ReturnedOnPolicy r ->
    ( "training_median_reward"
    , [(Ppo.iterIndex s, Ppo.iterMedianReward s) | s <- Common.rawTrainerStats r, Ppo.iterEpisodes s > 0]
    )
  ReturnedDqn r ->
    ( "training_mean_reward"
    , [ (Dqn.dqnIterStep s, Dqn.dqnIterMeanReward s)
      | s <- Common.rawTrainerStats r
      , Dqn.dqnIterEpisodes s > 0
      ]
    )
  ReturnedQrDqn r ->
    ( "training_mean_reward"
    , [(Qr.qrIterStep s, Qr.qrIterMeanReward s) | s <- Common.rawTrainerStats r, Qr.qrIterEpisodes s > 0]
    )
  ReturnedContinuous r ->
    ( "training_mean_reward"
    , [ (Continuous.contIterStep s, Continuous.contIterMeanReward s)
      | s <- Common.rawTrainerStats r
      , Continuous.contIterEpisodes s > 0
      ]
    )
  ReturnedHer r ->
    ( "training_success_rate"
    , [(Her.herIterEpisode s, Her.herIterSuccessRate s) | s <- Common.rawTrainerStats r]
    )
  ReturnedArs r ->
    ( "training_mean_reward"
    , [ (Ars.arsIterIndex s, Ars.arsIterMeanReturn s)
      | observation <- Common.rawTrainerStats r
      , let s = Ars.arsObservationStatistic observation
      ]
    )

-- This checks data consistency only. The caller must separately authenticate
-- actual producer/config/input origin. No update positivity, movement, curve,
-- improvement, bar, witness or publication condition belongs in this type.
refineBudgetCompleteTrainerObservation
  :: RawTrainerObservation -> Either Text BudgetCompleteTrainerObservation
refineBudgetCompleteTrainerObservation observed = do
  let plan = observedPlan observed
      policy = observedPolicy observed
      training = Plan.compiledRlTraining plan
      counters = returnedCounters policy
  canonical <-
    Plan.compileRlPlan training (Plan.EvaluationPlan (Plan.compiledRlEvaluationEpisodes plan))
  unless (canonical == plan) (Left "raw RL compiled plan is not canonical")
  schedule <-
    maybe (Left "raw RL policy requires a training schedule") Right (Plan.compiledRlSchedule plan)
  unless
    (Common.observedEnvironmentTransitionCount counters == Plan.scheduleObservedEnvironmentSteps schedule)
    (Left "raw RL physical transition budget mismatch")
  unless
    (validPolicyConfig plan policy && matchesEnvironment plan policy)
    (Left "raw RL actual configuration differs from its plan or is invalid")
  unless (validPolicyState policy) (Left "raw RL initial/final policy shape or values are invalid")
  unless
    (finiteStatistics policy)
    (Left "raw RL statistics contain invalid indices/counts or nonfinite observations")
  case observedEvaluation observed of
    EvaluationFailed _ -> pure ()
    HerEvaluationReturned values -> do
      unless
        (case policy of ReturnedHer _ -> True; _ -> False)
        (Left "raw HER evaluation has the wrong policy family")
      unless
        ( all
            (\(_, distance, steps) -> finite distance && distance >= 0 && distance <= 1 && steps >= 0)
            values
        )
        (Left "raw HER evaluation has invalid observations")
      _ <-
        Framework.mkEvaluationSet
          (fromIntegral (Plan.compiledRlEvaluationEpisodes plan))
          [(index, 1.0 - distance, steps, reached) | (index, (reached, distance, steps)) <- zip [0 ..] values]
      pure ()
    EvaluationReturned episodes -> do
      unless
        (case policy of ReturnedHer _ -> False; _ -> True)
        (Left "raw HER evaluation must retain exact returned goal distances")
      unless
        (all (null . Episode.simEpisodeFrames) episodes)
        (Left "raw final evaluation must not invent trajectory frames")
      let actual =
            [ ( fromIntegral (Episode.simEpisodeIndex e)
              , Episode.simEpisodeReward e
              , Episode.simEpisodeSteps e
              , Episode.simEpisodeDone e
              )
            | e <- episodes
            ]
      unless (all ((>= 0) . Episode.simEpisodeIndex) episodes) (Left "raw RL evaluation id is negative")
      _ <- Framework.mkEvaluationSet (fromIntegral (Plan.compiledRlEvaluationEpisodes plan)) actual
      pure ()
  pure (BudgetCompleteTrainerObservation observed)

finite :: Double -> Bool
finite x = not (isNaN x || isInfinite x)

positive :: [Int] -> Bool
positive = all (> 0)

probability :: Double -> Bool
probability x = finite x && x >= 0 && x <= 1

validPolicyConfig :: Plan.CompiledRlPlan -> ReturnedPolicy -> Bool
validPolicyConfig plan policy = case (Plan.compiledRlSchedule plan, policy) of
  (Just s@Plan.OnPolicyTrainingSchedule {}, ReturnedOnPolicy r) ->
    let c = Common.rawTrainerConfig r
     in trainer == onPolicyName (Ppo.ppoVariant c)
          && seed == Ppo.ppoSeed c
          && Ppo.ppoNumIterations c == Plan.scheduleOnPolicyIterations s
          && Ppo.ppoRolloutSteps c == Plan.scheduleOnPolicyRolloutSteps s
          && Ppo.ppoVectorEnvCount c == Plan.scheduleOnPolicyVectorEnvironments s
          && Ppo.ppoMaxEpisodeSteps c == Plan.scheduleOnPolicyMaxEpisodeSteps s
          && positive
            [ Ppo.ppoHiddenUnits c
            , Ppo.ppoActionCount c
            , Ppo.ppoObsSize c
            , Ppo.ppoEpochsPerUpdate c
            , Ppo.ppoMiniBatchSize c
            , Ppo.ppoRecurrentStateSize c
            ]
          && all
            finite
            [ Ppo.ppoClipEps c
            , Ppo.ppoValueCoef c
            , Ppo.ppoEntropyCoef c
            , Ppo.ppoCountBeta c
            , Ppo.ppoLearningRate c
            , Ppo.ppoKlTarget c
            , Ppo.ppoTrpoCgDamping c
            , Ppo.ppoTrpoBacktrackCoef c
            , Ppo.ppoTrpoCriticLearningRate c
            ]
          && probability (Ppo.ppoGamma c)
          && probability (Ppo.ppoLambda c)
          && Ppo.ppoLearningRate c >= 0
          && Ppo.ppoTrpoCgDamping c >= 0
          && positive [Ppo.ppoTrpoCgIterations c, Ppo.ppoTrpoBacktrackIterations c, Ppo.ppoTrpoCriticUpdates c]
  (Just s@Plan.FixedStepTrainingSchedule {}, ReturnedDqn r) ->
    let c = Common.rawTrainerConfig r
     in trainer == "dqn"
          && seed == Dqn.dqnSeed c
          && Dqn.dqnNumSteps c == Plan.scheduleFixedSteps s
          && Dqn.dqnMaxEpisodeSteps c == Plan.scheduleFixedMaxEpisodeSteps s
          && positive
            [ Dqn.dqnHiddenUnits c
            , Dqn.dqnReplayCapacity c
            , Dqn.dqnBatchSize c
            , Dqn.dqnTargetUpdateInterval c
            , Dqn.dqnEpsilonDecaySteps c
            , Dqn.dqnUpdateFrequency c
            , Dqn.dqnActionCount c
            , Dqn.dqnObsSize c
            , Dqn.dqnStatInterval c
            ]
          && Dqn.dqnTrainStart c >= 0
          && finite (Dqn.dqnLearningRate c)
          && Dqn.dqnLearningRate c >= 0
          && all probability [Dqn.dqnGamma c, Dqn.dqnEpsilonStart c, Dqn.dqnEpsilonEnd c]
  (Just s@Plan.FixedStepTrainingSchedule {}, ReturnedQrDqn r) ->
    let c = Common.rawTrainerConfig r
     in trainer == "qrdqn"
          && seed == Qr.qrSeed c
          && Qr.qrNumSteps c == Plan.scheduleFixedSteps s
          && Qr.qrMaxEpisodeSteps c == Plan.scheduleFixedMaxEpisodeSteps s
          && positive
            [ Qr.qrHiddenUnits c
            , Qr.qrNumQuantiles c
            , Qr.qrReplayCapacity c
            , Qr.qrBatchSize c
            , Qr.qrTargetUpdateInterval c
            , Qr.qrEpsilonDecaySteps c
            , Qr.qrUpdateFrequency c
            , Qr.qrActionCount c
            , Qr.qrObsSize c
            , Qr.qrStatInterval c
            ]
          && Qr.qrTrainStart c >= 0
          && all finite [Qr.qrLearningRate c, Qr.qrKappa c]
          && Qr.qrLearningRate c >= 0
          && Qr.qrKappa c > 0
          && all probability [Qr.qrGamma c, Qr.qrEpsilonStart c, Qr.qrEpsilonEnd c]
  (Just s@Plan.FixedStepTrainingSchedule {}, ReturnedContinuous r) ->
    let c = Common.rawTrainerConfig r
     in trainer == continuousName (Continuous.ctVariant c)
          && seed == Continuous.ctSeed c
          && Continuous.ctNumSteps c == Plan.scheduleFixedSteps s
          && Continuous.ctMaxEpisodeSteps c == Plan.scheduleFixedMaxEpisodeSteps s
          && Continuous.ctEnvName c == Plan.compiledRlEnvironment plan
          && positive
            [ Continuous.ctHidden c
            , Continuous.ctReplayCapacity c
            , Continuous.ctBatchSize c
            , Continuous.ctPolicyDelay c
            , Continuous.ctMaxEpisodeSteps c
            , Continuous.ctObsSize c
            , Continuous.ctStatInterval c
            ]
          && all
            finite
            [ Continuous.ctActorLr c
            , Continuous.ctCriticLr c
            , Continuous.ctExplNoise c
            , Continuous.ctTargetNoise c
            , Continuous.ctNoiseClip c
            , Continuous.ctSacAlpha c
            , Continuous.ctAlphaLr c
            , Continuous.ctTargetEntropy c
            , Continuous.ctPolicyStd c
            , Continuous.ctActionLow c
            , Continuous.ctActionHigh c
            , Continuous.ctCountBeta c
            ]
          && probability (Continuous.ctGamma c)
          && probability (Continuous.ctTau c)
          && Continuous.ctActorLr c >= 0
          && Continuous.ctCriticLr c >= 0
          && Continuous.ctPolicyStd c > 0
          && Continuous.ctActionLow c < Continuous.ctActionHigh c
          && Continuous.ctTqcDropPerCritic c >= 0
          && Continuous.ctTrainStart c >= 0
          && Continuous.ctStartSteps c >= 0
  (Just s@Plan.HerTrainingSchedule {}, ReturnedHer r) ->
    let c = Common.rawTrainerConfig r
     in trainer == "her"
          && seed == Her.herSeed c
          && Her.herEpisodes c == Plan.scheduleHerEpisodes s
          && Her.herNumBits c == Plan.scheduleHerEnvironmentStepsPerEpisode s
          && positive
            [ Her.herNumBits c
            , Her.herHiddenUnits c
            , Her.herReplayCapacity c
            , Her.herBatchSize c
            , Her.herTargetUpdateInterval c
            , Her.herStatInterval c
            , Her.herUpdatesPerEpisode c
            ]
          && all probability [Her.herGamma c, Her.herEpsilon c]
          && finite (Her.herLearningRate c)
          && Her.herLearningRate c >= 0
  (Just s@Plan.ArsTrainingSchedule {}, ReturnedArs r) ->
    let c = Common.rawTrainerConfig r
     in trainer == "ars"
          && seed == Ars.arsSeed c
          && Ars.arsIterations c == Plan.scheduleArsIterations s
          && Ars.arsNumDirections c == Plan.scheduleArsDirections s
          && Ars.arsMaxEpisodeSteps c == Plan.scheduleArsMaxEpisodeSteps s
          && positive [Ars.arsTopB c, Ars.arsObsSize c, Ars.arsActionCount c]
          && Ars.arsTopB c <= Ars.arsNumDirections c
          && all finite [Ars.arsStepSize c, Ars.arsNoiseStd c]
          && Ars.arsStepSize c >= 0
          && Ars.arsNoiseStd c > 0
  _ -> False
 where
  trainer = Plan.compiledRlTrainerKind plan
  seed = Plan.compiledRlSeed plan
  onPolicyName v = case v of
    Ppo.VariantPPO -> "ppo"
    Ppo.VariantA2C -> "a2c"
    Ppo.VariantTRPO -> "trpo"
    Ppo.VariantMaskablePPO -> "maskableppo"
    Ppo.VariantRecurrentPPO -> "recurrentppo"
  continuousName v = case v of
    Continuous.VariantDDPG -> "ddpg"
    Continuous.VariantTD3 -> "td3"
    Continuous.VariantSAC -> "sac"
    Continuous.VariantCrossQ -> "crossq"
    Continuous.VariantTQC -> "tqc"

matchesEnvironment :: Plan.CompiledRlPlan -> ReturnedPolicy -> Bool
matchesEnvironment plan policy = case policy of
  ReturnedContinuous r -> case Sim.lookupContinuousEnvironmentByName (Plan.compiledRlEnvironment plan) of
    Nothing -> False
    Just (Sim.SomeContinuousEnvironment env) ->
      let c = Common.rawTrainerConfig r
       in Continuous.ctObsSize c == Sim.cEnvObservationSize env
            && Continuous.ctActionLow c == Sim.cEnvActionLow env
            && Continuous.ctActionHigh c == Sim.cEnvActionHigh env
  ReturnedHer _ -> Plan.compiledRlEnvironment plan == "goal-reaching"
  _ -> case Sim.lookupSimulatedEnvironmentByName (Plan.compiledRlEnvironment plan) of
    Nothing -> False
    Just (Sim.SomeSimulatedEnvironment env) -> case policy of
      ReturnedOnPolicy r ->
        let c = Common.rawTrainerConfig r
         in Ppo.ppoObsSize c == Sim.envObservationSize env && Ppo.ppoActionCount c == Sim.envActionCount env
      ReturnedDqn r ->
        let c = Common.rawTrainerConfig r
         in Dqn.dqnObsSize c == Sim.envObservationSize env && Dqn.dqnActionCount c == Sim.envActionCount env
      ReturnedQrDqn r ->
        let c = Common.rawTrainerConfig r
         in Qr.qrObsSize c == Sim.envObservationSize env && Qr.qrActionCount c == Sim.envActionCount env
      ReturnedArs r ->
        let c = Common.rawTrainerConfig r
         in Ars.arsObsSize c == Sim.envObservationSize env && Ars.arsActionCount c == Sim.envActionCount env

validPolicyState :: ReturnedPolicy -> Bool
validPolicyState policy = case policy of
  ReturnedOnPolicy r ->
    let c = Common.rawTrainerConfig r
     in neural (Ppo.ppoObsSize c) (Ppo.ppoHiddenUnits c) (toInteger (Ppo.ppoActionCount c) + 1) r
  ReturnedDqn r ->
    let c = Common.rawTrainerConfig r
     in neural (Dqn.dqnObsSize c) (Dqn.dqnHiddenUnits c) (toInteger (Dqn.dqnActionCount c)) r
  ReturnedQrDqn r ->
    let c = Common.rawTrainerConfig r
     in neural
          (Qr.qrObsSize c)
          (Qr.qrHiddenUnits c)
          (toInteger (Qr.qrActionCount c) * toInteger (Qr.qrNumQuantiles c))
          r
  ReturnedContinuous r -> let c = Common.rawTrainerConfig r in neural (Continuous.ctObsSize c) (Continuous.ctHidden c) 1 r
  ReturnedHer r ->
    let c = Common.rawTrainerConfig r
     in neuralInteger
          (2 * toInteger (Her.herNumBits c))
          (Her.herHiddenUnits c)
          (toInteger (Her.herNumBits c))
          r
  ReturnedArs r ->
    let c = Common.rawTrainerConfig r
        expected = toInteger (Ars.arsActionCount c) * toInteger (Ars.arsObsSize c)
     in linear expected (Common.rawTrainerInitialParams r)
          && linear expected (Common.rawTrainerFinalParams r)
 where
  linear :: Integer -> VU.Vector Double -> Bool
  linear expected v = expected > 0 && toInteger (VU.length v) == expected && VU.all finite v
  neural :: Int -> Int -> Integer -> Common.RawTrainerResult Mlp.MlpParams stat config -> Bool
  neural inputs = neuralInteger (toInteger inputs)
  neuralInteger
    :: Integer -> Int -> Integer -> Common.RawTrainerResult Mlp.MlpParams stat config -> Bool
  neuralInteger inputs hidden outputs r =
    all
      (\n -> n > 0 && n <= toInteger (maxBound :: Int))
      [inputs, toInteger hidden, outputs, inputs * toInteger hidden, outputs * toInteger hidden]
      && let shape = Mlp.MlpShape (fromInteger inputs) hidden (fromInteger outputs)
          in valid shape (Common.rawTrainerInitialParams r) && valid shape (Common.rawTrainerFinalParams r)
  valid :: Mlp.MlpShape -> Mlp.MlpParams -> Bool
  valid shape params =
    Mlp.paramShape params == shape
      && linear (toInteger (Mlp.mlpHidden shape) * toInteger (Mlp.mlpInputs shape)) (Mlp.paramW1 params)
      && linear (toInteger (Mlp.mlpHidden shape)) (Mlp.paramB1 params)
      && linear (toInteger (Mlp.mlpOutputs shape) * toInteger (Mlp.mlpHidden shape)) (Mlp.paramW2 params)
      && linear (toInteger (Mlp.mlpOutputs shape)) (Mlp.paramB2 params)

finiteStatistics :: ReturnedPolicy -> Bool
finiteStatistics policy = case policy of
  ReturnedOnPolicy r ->
    all
      ( \s ->
          Ppo.iterIndex s >= 0
            && Ppo.iterEpisodes s >= 0
            && all finite [Ppo.iterMeanReward s, Ppo.iterMedianReward s, Ppo.iterMaxReward s]
      )
      (Common.rawTrainerStats r)
  ReturnedDqn r ->
    all
      ( \s ->
          Dqn.dqnIterStep s >= 0
            && Dqn.dqnIterEpisodes s >= 0
            && all finite [Dqn.dqnIterMeanReward s, Dqn.dqnIterLastEpisodeReward s]
      )
      (Common.rawTrainerStats r)
  ReturnedQrDqn r ->
    all
      (\s -> Qr.qrIterStep s >= 0 && Qr.qrIterEpisodes s >= 0 && finite (Qr.qrIterMeanReward s))
      (Common.rawTrainerStats r)
  ReturnedContinuous r ->
    all
      ( \s ->
          Continuous.contIterStep s >= 0
            && Continuous.contIterEpisodes s >= 0
            && all finite [Continuous.contIterMeanReward s, Continuous.contIterLastEpisodeReward s]
      )
      (Common.rawTrainerStats r)
  ReturnedHer r ->
    all
      (\s -> Her.herIterEpisode s >= 0 && finite (Her.herIterSuccessRate s))
      (Common.rawTrainerStats r)
  ReturnedArs r -> case Ars.validateArsTrainObservation r of
    Left _ -> False
    Right () -> True
