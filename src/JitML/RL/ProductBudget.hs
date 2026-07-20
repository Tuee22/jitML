{-# LANGUAGE OverloadedStrings #-}

-- | One source of truth for the environment-step schedules used by canonical
-- ProductRow RL training.  The ProductRow budget is the schedule's /observed/
-- environment-step count, not the smaller requested floor from which a
-- trainer derives its rollout shape.
module JitML.RL.ProductBudget
  ( RlTrainingSchedule (..)
  , canonicalProductRlSchedule
  , canonicalProductRlTargetUnits
  , planExactRlTrainingSchedule
  , planRlTrainingSchedule
  , productRlDefaultEvaluationEpisodes
  , productRlDefaultMaxEpisodeSteps
  , productRlRequestedStepFloor
  , rlTrainerEnvironmentCompatibilityError
  , trainerKindForAlgorithm
  )
where

import Data.Foldable (traverse_)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Simulator
  ( ContinuousEnvironment (cEnvMaxEpisodeSteps)
  , SimulatedEnvironment (envMaxEpisodeSteps)
  , SomeContinuousEnvironment (..)
  , SomeSimulatedEnvironment (..)
  , lookupContinuousEnvironmentByName
  , lookupSimulatedEnvironmentByName
  )

-- | The concrete trainer shape and the total environment transitions it
-- schedules.  Keeping the observed count beside the shape makes it impossible
-- for the producer to forget vector-environment multiplicity or trainer
-- granularity when it builds completion evidence.
data RlTrainingSchedule
  = OnPolicyTrainingSchedule
      { scheduleObservedEnvironmentSteps :: !Word64
      , scheduleOnPolicyIterations :: !Int
      , scheduleOnPolicyRolloutSteps :: !Int
      , scheduleOnPolicyVectorEnvironments :: !Int
      , scheduleOnPolicyMaxEpisodeSteps :: !Int
      }
  | FixedStepTrainingSchedule
      { scheduleObservedEnvironmentSteps :: !Word64
      , scheduleFixedSteps :: !Int
      , scheduleFixedMaxEpisodeSteps :: !Int
      }
  | ArsTrainingSchedule
      { scheduleObservedEnvironmentSteps :: !Word64
      , scheduleArsIterations :: !Int
      , scheduleArsDirections :: !Int
      , scheduleArsMaxEpisodeSteps :: !Int
      }
  | HerTrainingSchedule
      { scheduleObservedEnvironmentSteps :: !Word64
      , scheduleHerEpisodes :: !Int
      , scheduleHerEnvironmentStepsPerEpisode :: !Int
      }
  deriving stock (Eq, Show)

-- | Product publisher defaults.  The 2,000 value is only a /requested floor/:
-- replay warmup, rollout batching, vector environments, and episode granularity
-- can make the real canonical schedule larger.  The ProductRow budget is
-- derived from 'canonicalProductRlSchedule', never copied from this constant.
productRlDefaultEvaluationEpisodes :: Int
productRlDefaultEvaluationEpisodes = 20

productRlDefaultMaxEpisodeSteps :: Int
productRlDefaultMaxEpisodeSteps = 200

productRlRequestedStepFloor :: Word64
productRlRequestedStepFloor = 2_000

-- | Derive the canonical ProductRow schedule from the same planner used by the
-- producer.  Algorithm names are the public matrix names (for example
-- @QR-DQN@); the planner itself consumes the worker-side trainer selector.
canonicalProductRlSchedule :: Text -> Text -> Either Text RlTrainingSchedule
canonicalProductRlSchedule algorithm environment =
  planRlTrainingSchedule
    (trainerKindForAlgorithm algorithm)
    environment
    productRlDefaultEvaluationEpisodes
    productRlDefaultMaxEpisodeSteps
    Nothing
    (Just productRlRequestedStepFloor)

canonicalProductRlTargetUnits :: Text -> Text -> Either Text Word64
canonicalProductRlTargetUnits algorithm environment =
  scheduleObservedEnvironmentSteps
    <$> canonicalProductRlSchedule algorithm environment

-- | Resolve a schedule for an already-refined exact budget.  When evaluation,
-- episode-length, vector-width, or granularity inputs change the scheduled
-- observed-unit total, reject the mismatch before training rather than
-- discovering it only when completion evidence is built.
planExactRlTrainingSchedule
  :: Text
  -> Text
  -> Int
  -> Int
  -> Maybe Int
  -> Word64
  -> Either Text RlTrainingSchedule
planExactRlTrainingSchedule trainer environment evalEpisodes maxEpisodeSteps vectorOverride expected = do
  case rlTrainerEnvironmentCompatibilityError trainer environment of
    Just err -> Left err
    Nothing -> Right ()
  schedule <-
    planRlTrainingSchedule
      trainer
      environment
      evalEpisodes
      maxEpisodeSteps
      vectorOverride
      (Just expected)
  if scheduleObservedEnvironmentSteps schedule == expected
    then Right schedule
    else
      Left
        ( "resolved RL environment-step budget cannot be executed exactly: expected "
            <> Text.pack (show expected)
            <> " but trainer "
            <> trainer
            <> " / "
            <> environment
            <> " schedules "
            <> Text.pack (show (scheduleObservedEnvironmentSteps schedule))
        )

-- | Worker-side trainer selector used by the canonical schedule.  Unknown
-- selectors remain unknown so 'planRlTrainingSchedule' fails closed.
trainerKindForAlgorithm :: Text -> Text
trainerKindForAlgorithm algorithm =
  case Text.toUpper (Text.strip algorithm) of
    "PPO" -> "ppo"
    "A2C" -> "a2c"
    "TRPO" -> "trpo"
    "MASKABLEPPO" -> "maskableppo"
    "RECURRENTPPO" -> "recurrentppo"
    "DQN" -> "dqn"
    "QR-DQN" -> "qrdqn"
    "QRDQN" -> "qrdqn"
    "DDPG" -> "ddpg"
    "TD3" -> "td3"
    "SAC" -> "sac"
    "CROSSQ" -> "crossq"
    "TQC" -> "tqc"
    "ARS" -> "ars"
    "HER" -> "her"
    _ -> Text.toLower (Text.strip algorithm)

-- | Closed compatibility relation shared by ProductRow refinement and every
-- runtime adapter.  Scheduling alone is insufficient: several trainers can
-- derive a numerical schedule for a simulator whose action domain they do not
-- implement.
rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError rawTrainer rawEnvironment =
  case supportedEnvironments of
    Nothing -> Nothing
    Just environments
      | environment `elem` environments -> Nothing
      | otherwise ->
          Just
            ( "RL trainer "
                <> trainer
                <> " does not support environment "
                <> environment
                <> "; supported environments: "
                <> Text.intercalate ", " environments
            )
 where
  trainer = Text.toLower (Text.strip rawTrainer)
  environment = Text.toLower (Text.strip rawEnvironment)
  supportedEnvironments =
    case trainer of
      "ppo" -> Just discreteProductEnvironments
      "a2c" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "trpo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "maskableppo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "recurrentppo" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "dqn" -> Just ["cartpole", "mountain-car", "key-door-grid"]
      "qrdqn" -> Just ["cartpole", "mountain-car", "key-door-grid"]
      "ddpg" -> Just continuousProductEnvironments
      "td3" -> Just continuousProductEnvironments
      "sac" -> Just continuousProductEnvironments
      "crossq" -> Just continuousProductEnvironments
      "tqc" -> Just continuousProductEnvironments
      "ars" -> Just ["cartpole", "mountain-car", "lunar-lander", "key-door-grid"]
      "her" -> Just ["goal-reaching"]
      _ -> Nothing
  discreteProductEnvironments =
    ["cartpole", "mountain-car", "acrobot", "lunar-lander", "key-door-grid", "gridworld-deterministic"]
  continuousProductEnvironments = ["pendulum", "lunar-lander"]

-- | Plan one real trainer run.  The optional target is a requested minimum,
-- not an observed count: the returned count includes every vector environment
-- and is rounded only where the trainer's indivisible rollout/episode shape
-- requires it.  Callers that own an exact resolved budget must compare that
-- budget with 'scheduleObservedEnvironmentSteps' before executing the trainer.
planRlTrainingSchedule
  :: Text
  -> Text
  -> Int
  -> Int
  -> Maybe Int
  -> Maybe Word64
  -> Either Text RlTrainingSchedule
planRlTrainingSchedule rawTrainer environment evalEpisodes requestedMaxSteps vectorOverride requestedFloor = do
  positive "RL evaluation episodes" evalEpisodes
  positive "RL maximum episode steps" requestedMaxSteps
  traverse_ (positive "RL vector-environment count") vectorOverride
  case trainer of
    "ppo" -> onPolicySchedule
    "a2c" -> onPolicySchedule
    "trpo" -> onPolicySchedule
    "maskableppo" -> onPolicySchedule
    "recurrentppo" -> onPolicySchedule
    "dqn" -> fixedStepSchedule (offPolicyStepFloor environment)
    "qrdqn" ->
      fixedStepSchedule
        ( if environment == "key-door-grid"
            then max 120_000 (offPolicyStepFloor environment)
            else offPolicyStepFloor environment
        )
    "ddpg" -> continuousSchedule (continuousStepFloor trainer environment)
    "td3" -> continuousSchedule (continuousStepFloor trainer environment)
    "sac" -> continuousSchedule (continuousStepFloor trainer environment)
    "crossq" -> continuousSchedule (continuousStepFloor trainer environment)
    "tqc" -> continuousSchedule (continuousStepFloor trainer environment)
    "ars" -> arsSchedule
    "her" -> herSchedule
    _ -> Left ("unknown RL trainer schedule: " <> trainer)
 where
  trainer = Text.toLower (Text.strip rawTrainer)
  targetFloor = maybe 0 toInteger requestedFloor

  onPolicySchedule = do
    environmentMax <- discreteEnvironmentMaxSteps environment
    let effectiveMax = max requestedMaxSteps environmentMax
        rolloutSteps = max 512 effectiveMax
        vectorEnvironments =
          fromMaybe
            ( if trainer == "recurrentppo" && environment == "key-door-grid"
                then 4
                else PpoTrainer.productPpoVectorEnvCount
            )
            vectorOverride
        iterationFloor = 150
        stepsPerIteration =
          toInteger rolloutSteps * toInteger vectorEnvironments
        defaultSteps =
          toInteger (max iterationFloor evalEpisodes) * stepsPerIteration
        requestedSteps = max defaultSteps targetFloor
        iterationsInteger =
          max (toInteger iterationFloor) (ceilingDiv requestedSteps stepsPerIteration)
        observedInteger = iterationsInteger * stepsPerIteration
    iterations <- checkedInt "on-policy iteration count" iterationsInteger
    observed <- checkedWord64 "on-policy environment-step count" observedInteger
    pure
      OnPolicyTrainingSchedule
        { scheduleObservedEnvironmentSteps = observed
        , scheduleOnPolicyIterations = iterations
        , scheduleOnPolicyRolloutSteps = rolloutSteps
        , scheduleOnPolicyVectorEnvironments = vectorEnvironments
        , scheduleOnPolicyMaxEpisodeSteps = effectiveMax
        }

  fixedStepSchedule algorithmFloor = do
    environmentMax <- discreteEnvironmentMaxSteps environment
    let effectiveMax = max requestedMaxSteps environmentMax
        requestedSteps =
          maximum
            [ toInteger algorithmFloor
            , toInteger evalEpisodes * toInteger effectiveMax
            , targetFloor
            ]
    steps <- checkedInt "off-policy environment-step count" requestedSteps
    observed <- checkedWord64 "off-policy environment-step count" requestedSteps
    pure
      FixedStepTrainingSchedule
        { scheduleObservedEnvironmentSteps = observed
        , scheduleFixedSteps = steps
        , scheduleFixedMaxEpisodeSteps = effectiveMax
        }

  continuousSchedule algorithmFloor = do
    environmentMax <- continuousEnvironmentMaxSteps environment
    let effectiveMax = max requestedMaxSteps environmentMax
        requestedSteps =
          maximum
            [ toInteger algorithmFloor
            , toInteger evalEpisodes * toInteger effectiveMax
            , targetFloor
            ]
    steps <- checkedInt "continuous-control environment-step count" requestedSteps
    observed <- checkedWord64 "continuous-control environment-step count" requestedSteps
    pure
      FixedStepTrainingSchedule
        { scheduleObservedEnvironmentSteps = observed
        , scheduleFixedSteps = steps
        , scheduleFixedMaxEpisodeSteps = effectiveMax
        }

  arsSchedule = do
    environmentMax <- discreteEnvironmentMaxSteps environment
    let effectiveMax = max requestedMaxSteps environmentMax
        directions = ArsTrainer.arsNumDirections ArsTrainer.defaultArsTrainConfig
        stepsPerIteration =
          2 * toInteger directions * toInteger effectiveMax
        requestedSteps =
          maximum
            [ toInteger evalEpisodes * stepsPerIteration
            , targetFloor
            , 50 * stepsPerIteration
            ]
        iterationsInteger = ceilingDiv requestedSteps stepsPerIteration
        observedInteger = iterationsInteger * stepsPerIteration
    iterations <- checkedInt "ARS iteration count" iterationsInteger
    observed <- checkedWord64 "ARS environment-step count" observedInteger
    pure
      ArsTrainingSchedule
        { scheduleObservedEnvironmentSteps = observed
        , scheduleArsIterations = iterations
        , scheduleArsDirections = directions
        , scheduleArsMaxEpisodeSteps = effectiveMax
        }

  herSchedule = do
    let stepsPerEpisode = HerTrainer.herNumBits HerTrainer.defaultHerTrainConfig
        requestedSteps =
          maximum
            [ toInteger evalEpisodes * toInteger stepsPerEpisode
            , targetFloor
            , 200 * toInteger stepsPerEpisode
            ]
        episodesInteger =
          ceilingDiv requestedSteps (toInteger stepsPerEpisode)
        observedInteger = episodesInteger * toInteger stepsPerEpisode
    episodes <- checkedInt "HER episode count" episodesInteger
    observed <- checkedWord64 "HER environment-step count" observedInteger
    pure
      HerTrainingSchedule
        { scheduleObservedEnvironmentSteps = observed
        , scheduleHerEpisodes = episodes
        , scheduleHerEnvironmentStepsPerEpisode = stepsPerEpisode
        }

offPolicyStepFloor :: Text -> Int
offPolicyStepFloor environment
  | Text.toLower environment == "mountain-car" = 120_000
  | otherwise = 50_000

continuousStepFloor :: Text -> Text -> Int
continuousStepFloor "ddpg" "lunar-lander" = 120_000
continuousStepFloor "sac" "pendulum" = 2_000
continuousStepFloor _ _ = 50_000

discreteEnvironmentMaxSteps :: Text -> Either Text Int
discreteEnvironmentMaxSteps environment =
  case lookupSimulatedEnvironmentByName environment of
    Nothing -> Left ("unknown discrete RL environment: " <> environment)
    Just (SomeSimulatedEnvironment value) ->
      pure (envMaxEpisodeSteps value)

continuousEnvironmentMaxSteps :: Text -> Either Text Int
continuousEnvironmentMaxSteps environment =
  case lookupContinuousEnvironmentByName environment of
    Nothing -> Left ("unknown continuous RL environment: " <> environment)
    Just (SomeContinuousEnvironment value) ->
      pure (cEnvMaxEpisodeSteps value)

positive :: Text -> Int -> Either Text ()
positive label value
  | value > 0 = Right ()
  | otherwise = Left (label <> " must be positive")

ceilingDiv :: Integer -> Integer -> Integer
ceilingDiv numerator denominator =
  (numerator + denominator - 1) `div` denominator

checkedInt :: Text -> Integer -> Either Text Int
checkedInt label value
  | value <= 0 = Left (label <> " must be positive")
  | value > toInteger (maxBound :: Int) = Left (label <> " exceeds the platform Int range")
  | otherwise = Right (fromInteger value)

checkedWord64 :: Text -> Integer -> Either Text Word64
checkedWord64 label value
  | value <= 0 = Left (label <> " must be positive")
  | value > toInteger (maxBound :: Word64) = Left (label <> " exceeds the Word64 range")
  | otherwise = Right (fromInteger value)
