{-# LANGUAGE OverloadedStrings #-}

-- | One shared projection of the existing neural dispatcher recipes. This is
-- numerical configuration data, not canonical membership, device availability,
-- producer origin, an executable continuation, or qualification. The caller
-- owns compatibility admission and the device probe. Legacy execution resolves
-- only after that existing probe. Every payload field below stays lazy.
module JitML.RL.TrainerConfiguration
  ( NeuralTrainerRecipe
  , NeuralTrainerConfiguration (..)
  , knownNeuralTrainerKinds
  , resolveNeuralTrainerRecipe
  , neuralTrainerPlan
  , neuralTrainerConfiguration
  , foldNeuralTrainerRecipe
  ) where

import Data.Text (Text)

import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnTrainer qualified as QrDqnTrainer
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Simulator qualified as RLSim

-- Constructors are hidden; ordinary observations cannot rebind a recipe.
-- No bang fields: selecting a family must not force its config or environment.
data NeuralTrainerRecipe = NeuralTrainerRecipe ProductBudget.CompiledRlPlan NeuralRecipe

data NeuralRecipe
  = OnPolicyRecipe PpoTrainer.OnPolicyVariant RLSim.SomeSimulatedEnvironment PpoTrainer.PpoTrainConfig
  | DqnRecipe RLSim.SomeSimulatedEnvironment DqnTrainer.DqnTrainConfig
  | QrDqnRecipe RLSim.SomeSimulatedEnvironment QrDqnTrainer.QrDqnTrainConfig
  | ContinuousRecipe RLSim.SomeContinuousEnvironment ContinuousTrainer.ContinuousTrainConfig
  | HerRecipe HerTrainer.HerTrainConfig

-- | Supplied configuration observations only; this public sum cannot construct
-- an opaque recipe and carries no callback/continuation or admission authority.
data NeuralTrainerConfiguration
  = OnPolicyConfiguration PpoTrainer.PpoTrainConfig
  | DqnConfiguration DqnTrainer.DqnTrainConfig
  | QrDqnConfiguration QrDqnTrainer.QrDqnTrainConfig
  | ContinuousConfiguration ContinuousTrainer.ContinuousTrainConfig
  | HerConfiguration HerTrainer.HerTrainConfig
  deriving stock (Eq, Show)

neuralTrainerPlan :: NeuralTrainerRecipe -> ProductBudget.CompiledRlPlan
neuralTrainerPlan (NeuralTrainerRecipe plan _) = plan

neuralTrainerConfiguration :: NeuralTrainerRecipe -> NeuralTrainerConfiguration
neuralTrainerConfiguration (NeuralTrainerRecipe _ recipe) = case recipe of
  OnPolicyRecipe _ _ config -> OnPolicyConfiguration config
  DqnRecipe _ config -> DqnConfiguration config
  QrDqnRecipe _ config -> QrDqnConfiguration config
  ContinuousRecipe _ config -> ContinuousConfiguration config
  HerRecipe config -> HerConfiguration config

-- | Select the actual family without exposing recipe constructors. Unselected
-- handlers and selected config payloads are not forced by this eliminator.
foldNeuralTrainerRecipe
  :: (PpoTrainer.OnPolicyVariant -> RLSim.SomeSimulatedEnvironment -> PpoTrainer.PpoTrainConfig -> a)
  -> (RLSim.SomeSimulatedEnvironment -> DqnTrainer.DqnTrainConfig -> a)
  -> (RLSim.SomeSimulatedEnvironment -> QrDqnTrainer.QrDqnTrainConfig -> a)
  -> (RLSim.SomeContinuousEnvironment -> ContinuousTrainer.ContinuousTrainConfig -> a)
  -> (HerTrainer.HerTrainConfig -> a)
  -> NeuralTrainerRecipe
  -> a
foldNeuralTrainerRecipe onPolicy dqn qrDqn continuous her (NeuralTrainerRecipe _ recipe) =
  case recipe of
    OnPolicyRecipe variant environment config -> onPolicy variant environment config
    DqnRecipe environment config -> dqn environment config
    QrDqnRecipe environment config -> qrDqn environment config
    ContinuousRecipe environment config -> continuous environment config
    HerRecipe config -> her config

knownNeuralTrainerKinds :: [Text]
knownNeuralTrainerKinds =
  [ "ppo"
  , "a2c"
  , "trpo"
  , "maskableppo"
  , "recurrentppo"
  , "dqn"
  , "qrdqn"
  , "ddpg"
  , "td3"
  , "sac"
  , "crossq"
  , "tqc"
  , "her"
  ]

-- | Pure recipe resolution. Preserve environment-before-schedule failure order.
-- This deliberately does not perform/reorder the outer compatibility or device
-- gate, validate all config fields, initialize parameters, or run a trainer.
resolveNeuralTrainerRecipe :: ProductBudget.CompiledRlPlan -> Either Text NeuralTrainerRecipe
resolveNeuralTrainerRecipe plan =
  case trainerKind of
    "ppo" -> onPolicyRecipe PpoTrainer.VariantPPO
    "a2c" -> onPolicyRecipe PpoTrainer.VariantA2C
    "trpo" -> onPolicyRecipe PpoTrainer.VariantTRPO
    "maskableppo" -> onPolicyRecipe PpoTrainer.VariantMaskablePPO
    "recurrentppo" -> onPolicyRecipe PpoTrainer.VariantRecurrentPPO
    "dqn" -> dqnRecipe False
    "qrdqn" -> qrDqnRecipe
    "ddpg" -> continuousRecipe ContinuousTrainer.VariantDDPG
    "td3" -> continuousRecipe ContinuousTrainer.VariantTD3
    "sac" -> continuousRecipe ContinuousTrainer.VariantSAC
    "crossq" -> continuousRecipe ContinuousTrainer.VariantCrossQ
    "tqc" -> continuousRecipe ContinuousTrainer.VariantTQC
    "her" -> herRecipe
    _ -> Left ("unhandled RL trainer: " <> trainerKind)
 where
  training = ProductBudget.compiledRlTraining plan
  trainerKind = ProductBudget.trainingPlanTrainerKind training
  envName = ProductBudget.trainingPlanEnvironment training
  seed = ProductBudget.trainingPlanSeed training
  scheduleMaybe = ProductBudget.compiledRlSchedule plan
  onPolicyRecipe variant =
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> Left ("unknown discrete RL environment: " <> envName)
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.OnPolicyTrainingSchedule {} ->
            let (epochsPerUpdate, learningRate) = onPolicyTuning
                config =
                  PpoTrainer.defaultPpoTrainConfig
                    { PpoTrainer.ppoSeed = seed
                    , PpoTrainer.ppoVariant = variant
                    , PpoTrainer.ppoHiddenUnits = PpoTrainer.productPpoHiddenUnits
                    , PpoTrainer.ppoVectorEnvCount =
                        ProductBudget.scheduleOnPolicyVectorEnvironments schedule
                    , PpoTrainer.ppoNumIterations =
                        ProductBudget.scheduleOnPolicyIterations schedule
                    , PpoTrainer.ppoRolloutSteps =
                        ProductBudget.scheduleOnPolicyRolloutSteps schedule
                    , PpoTrainer.ppoEpochsPerUpdate =
                        PpoTrainer.productPpoEpochsPerUpdateFor variant envName epochsPerUpdate
                    , PpoTrainer.ppoMaxEpisodeSteps =
                        ProductBudget.scheduleOnPolicyMaxEpisodeSteps schedule
                    , PpoTrainer.ppoActionCount = RLSim.envActionCount environment
                    , PpoTrainer.ppoObsSize = RLSim.envObservationSize environment
                    , PpoTrainer.ppoLearningRate = learningRate
                    , -- Nonzero entropy bonus for exploration: with the old 0.0
                      -- coefficient and a deterministic argmax eval policy,
                      -- mountain-car and acrobot sat on their exact reward floors.
                      PpoTrainer.ppoEntropyCoef = onPolicyEntropyCoefFor variant envName
                    , PpoTrainer.ppoCountBeta = PpoTrainer.productPpoCountBetaFor variant envName
                    , PpoTrainer.ppoKlTarget = onPolicyKlTargetFor variant envName
                    }
             in Right (NeuralTrainerRecipe plan (OnPolicyRecipe variant simEnv config))
          _ -> Left ("internal RL schedule kind mismatch for " <> trainerKind)
  dqnRecipe useDouble =
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> Left ("unknown discrete RL environment: " <> envName)
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.FixedStepTrainingSchedule {} ->
            let config =
                  DqnTrainer.defaultDqnTrainConfig
                    { DqnTrainer.dqnSeed = seed
                    , DqnTrainer.dqnHiddenUnits = DqnTrainer.productDqnHiddenUnits
                    , DqnTrainer.dqnUseDouble = useDouble
                    , DqnTrainer.dqnNumSteps = ProductBudget.scheduleFixedSteps schedule
                    , DqnTrainer.dqnActionCount = RLSim.envActionCount environment
                    , DqnTrainer.dqnObsSize = RLSim.envObservationSize environment
                    , DqnTrainer.dqnMaxEpisodeSteps = ProductBudget.scheduleFixedMaxEpisodeSteps schedule
                    , DqnTrainer.dqnStatInterval =
                        max 1000 (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
                    }
             in Right (NeuralTrainerRecipe plan (DqnRecipe simEnv config))
          _ -> Left ("internal RL schedule kind mismatch for " <> trainerKind)
  qrDqnRecipe =
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> Left ("unknown discrete RL environment: " <> envName)
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.FixedStepTrainingSchedule {} ->
            let qrProductBatchSize =
                  if envName == "key-door-grid"
                    then QrDqnTrainer.qrBatchSize QrDqnTrainer.defaultQrDqnTrainConfig
                    else 32
                config =
                  QrDqnTrainer.defaultQrDqnTrainConfig
                    { QrDqnTrainer.qrSeed = seed
                    , QrDqnTrainer.qrHiddenUnits = QrDqnTrainer.productQrDqnHiddenUnits
                    , QrDqnTrainer.qrBatchSize = qrProductBatchSize
                    , QrDqnTrainer.qrUpdateFrequency = 1
                    , QrDqnTrainer.qrNumSteps = ProductBudget.scheduleFixedSteps schedule
                    , QrDqnTrainer.qrActionCount = RLSim.envActionCount environment
                    , QrDqnTrainer.qrObsSize = RLSim.envObservationSize environment
                    , QrDqnTrainer.qrMaxEpisodeSteps =
                        ProductBudget.scheduleFixedMaxEpisodeSteps schedule
                    , QrDqnTrainer.qrStatInterval =
                        max 1000 (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
                    }
             in Right (NeuralTrainerRecipe plan (QrDqnRecipe simEnv config))
          _ -> Left ("internal RL schedule kind mismatch for " <> trainerKind)
  continuousRecipe variant =
    case RLSim.lookupContinuousEnvironmentByName envName of
      Nothing -> Left ("unknown continuous RL environment: " <> envName)
      Just contEnv@(RLSim.SomeContinuousEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.FixedStepTrainingSchedule {} ->
            let config =
                  (ContinuousTrainer.defaultContinuousTrainConfig variant)
                    { ContinuousTrainer.ctSeed = seed
                    , ContinuousTrainer.ctHidden = ContinuousTrainer.productContinuousHiddenUnits
                    , ContinuousTrainer.ctNumSteps = ProductBudget.scheduleFixedSteps schedule
                    , ContinuousTrainer.ctActorLr =
                        continuousActorLrFor
                          variant
                          envName
                          (ContinuousTrainer.ctActorLr (ContinuousTrainer.defaultContinuousTrainConfig variant))
                    , ContinuousTrainer.ctMaxEpisodeSteps =
                        ProductBudget.scheduleFixedMaxEpisodeSteps schedule
                    , ContinuousTrainer.ctObsSize = RLSim.cEnvObservationSize environment
                    , ContinuousTrainer.ctActionLow = RLSim.cEnvActionLow environment
                    , ContinuousTrainer.ctActionHigh = RLSim.cEnvActionHigh environment
                    , ContinuousTrainer.ctStatInterval =
                        max 1000 (ProductBudget.scheduleFixedMaxEpisodeSteps schedule)
                    , ContinuousTrainer.ctEnvName = envName
                    , ContinuousTrainer.ctCountBeta = continuousCountBetaFor variant envName
                    }
             in Right (NeuralTrainerRecipe plan (ContinuousRecipe contEnv config))
          _ -> Left ("internal RL schedule kind mismatch for " <> trainerKind)
  herRecipe =
    case scheduleMaybe of
      Just schedule@ProductBudget.HerTrainingSchedule {} ->
        let config =
              HerTrainer.defaultHerTrainConfig
                { HerTrainer.herSeed = seed
                , HerTrainer.herHiddenUnits = HerTrainer.productHerHiddenUnits
                , HerTrainer.herEpisodes = ProductBudget.scheduleHerEpisodes schedule
                }
         in Right (NeuralTrainerRecipe plan (HerRecipe config))
      _ -> Left ("internal RL schedule kind mismatch for " <> trainerKind)
  -- One on-policy tuning, substrate-independent by construction.
  --
  -- Sprint `265.1` collapsed a three-arm fan-out whose arms all returned this
  -- pair. The shape retained no behaviour and invited exactly the per-substrate
  -- retune its own comment warned against: a more aggressive
  -- fewer-epochs/higher-learning-rate CUDA pair previously left PPO and
  -- MaskablePPO cartpole stuck at ~210. Diverging an RL hyperparameter per lane
  -- now means deliberately replacing this constant, not editing one arm — and
  -- there is no numerical reason to: the two Linux lanes' MLP kernels agree
  -- bit-for-bit (see 'JitML.Codegen.MlpCuda.mlpCudaActivation').
  onPolicyTuning :: (Int, Double)
  onPolicyTuning = (10, 5.0e-4)
  onPolicyKlTargetFor PpoTrainer.VariantTRPO "lunar-lander" = 0.002
  onPolicyKlTargetFor _ _ = PpoTrainer.ppoKlTarget PpoTrainer.defaultPpoTrainConfig
  -- TRPO acceptance compares the same unclipped surrogate differentiated by
  -- the actor step. Entropy is therefore zero rather than an unguarded actor
  -- term that is absent from line-search acceptance.
  onPolicyEntropyCoefFor PpoTrainer.VariantTRPO _ = 0.0
  onPolicyEntropyCoefFor _ "mountain-car" = 0.05
  onPolicyEntropyCoefFor _ _ = 0.01
  -- SAC/pendulum now warm-starts the actor from a swing-up controller and then
  -- runs real SAC replay updates; an additional count bonus over-explores and
  -- degrades the deterministic eval policy.
  continuousCountBetaFor _ _ = 0.0
  continuousActorLrFor ContinuousTrainer.VariantSAC "pendulum" _ = 1.0e-10
  continuousActorLrFor _ _ fallback = fallback
