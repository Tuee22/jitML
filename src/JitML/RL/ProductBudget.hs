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
  , productRlDefaultTrainingEpisodeFloor
  , productRlRequestedStepFloor
  , rlTrainerEnvironmentCompatibilityError
  , trainerKindForAlgorithm

    -- * Phase 251 — TrainingPlan/EvaluationPlan compiler
  , TrainingPlan (..)
  , EvaluationPlan (..)
  , CompiledRlPlan (..)
  , compileRlPlan
  , compiledRlTrainerKind
  , compiledRlEnvironment
  , compiledRlSeed
  , compiledRlMaxEpisodeSteps
  , compiledRlEvaluationEpisodes
  , isAleAdapterEnvironment
  , compiledRlPlanId
  , renderCompiledRlPlanTransport
  , parseCompiledRlPlanTransport
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (isDigit)
import Data.Foldable (traverse_)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import Text.Read (readMaybe)

import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.Registry qualified as Cohort
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

-- | Phase 251 — the canonical /training-side/ episode-budget floor. This is a
-- training dimension: it scales the requested rollout/step floor a schedule is
-- planned against, independently of how many /evaluation/ episodes the run will
-- later score. It shares the value @20@ with
-- 'productRlDefaultEvaluationEpisodes' by history, but the two are now separate
-- inputs: changing the evaluation episode count can never move a training
-- dimension, because the schedule reads only this training floor.
productRlDefaultTrainingEpisodeFloor :: Int
productRlDefaultTrainingEpisodeFloor = 20

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
    productRlDefaultTrainingEpisodeFloor
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
planExactRlTrainingSchedule trainer environment trainingEpisodeFloor maxEpisodeSteps vectorOverride expected = do
  case rlTrainerEnvironmentCompatibilityError trainer environment of
    Just err -> Left err
    Nothing -> Right ()
  schedule <-
    planRlTrainingSchedule
      trainer
      environment
      trainingEpisodeFloor
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
-- selectors remain unknown so 'planRlTrainingSchedule' fails closed.  The
-- rendering is owned by the typed cohort registry
-- ('JitML.RL.Algorithms.Registry') so the daemon, worker, publisher, and
-- completion path all derive the same identity string from one source.
trainerKindForAlgorithm :: Text -> Text
trainerKindForAlgorithm = Cohort.trainerKindForAlgorithmName

-- | Closed compatibility relation shared by ProductRow refinement and every
-- runtime adapter.  Scheduling alone is insufficient: several trainers can
-- derive a numerical schedule for a simulator whose action domain they do not
-- implement.  Backed by the typed action-domain cohort registry.
rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError = Cohort.trainerEnvironmentCompatibilityError

-- | Plan one real trainer run.  The optional target is a requested minimum,
-- not an observed count: the returned count includes every vector environment
-- and is rounded only where the trainer's indivisible rollout/episode shape
-- requires it.  Callers that own an exact resolved budget must compare that
-- budget with 'scheduleObservedEnvironmentSteps' before executing the trainer.
--
-- Phase 251: the third argument is the /training/ episode-budget floor, not the
-- evaluation episode count. Evaluation episodes never reach this function, so no
-- training dimension the schedule produces can depend on how many episodes the
-- run is later scored over.
planRlTrainingSchedule
  :: Text
  -> Text
  -> Int
  -> Int
  -> Maybe Int
  -> Maybe Word64
  -> Either Text RlTrainingSchedule
planRlTrainingSchedule rawTrainer environment trainingEpisodeFloor requestedMaxSteps vectorOverride requestedFloor = do
  positive "RL training episode budget floor" trainingEpisodeFloor
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
          toInteger (max iterationFloor trainingEpisodeFloor) * stepsPerIteration
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
            , toInteger trainingEpisodeFloor * toInteger effectiveMax
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
            , toInteger trainingEpisodeFloor * toInteger effectiveMax
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
            [ toInteger trainingEpisodeFloor * stepsPerIteration
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
            [ toInteger trainingEpisodeFloor * toInteger stepsPerEpisode
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

-- Phase 251 — TrainingPlan/EvaluationPlan compiler. -----------------------
--
-- The pure plan compiler is the single owner of RL dimensional arithmetic. A
-- 'TrainingPlan' carries every input that shapes a training run (the trainer,
-- the environment, the seed, the episode-length cap, the training episode
-- budget floor, the vector-environment width, and either a requested transition
-- floor or an exact resolved transition target). A separate 'EvaluationPlan'
-- carries only the number of episodes the trained policy is later scored over.
-- 'compileRlPlan' derives a validated 'CompiledRlPlan' whose training
-- dimensions are a function of the 'TrainingPlan' alone: the 'EvaluationPlan'
-- can never move the schedule.

-- | The training-shaping inputs for one RL run. No evaluation episode count
-- appears here — that is the whole point.
data TrainingPlan = TrainingPlan
  { trainingPlanTrainerKind :: !Text
  -- ^ Worker-side trainer selector (for example @qrdqn@).
  , trainingPlanEnvironment :: !Text
  -- ^ Canonical environment name (for example @lunar-lander@).
  , trainingPlanSeed :: !Int
  -- ^ Deterministic run seed. Does not affect the scheduled dimensions.
  , trainingPlanMaxEpisodeSteps :: !Int
  -- ^ Requested per-episode step cap; the schedule combines it with the
  --   environment's own geometry maximum.
  , trainingPlanEpisodeBudgetFloor :: !Int
  -- ^ The training episode-budget floor (see
  --   'productRlDefaultTrainingEpisodeFloor'). Scales the schedule's requested
  --   floor. Distinct from the evaluation episode count.
  , trainingPlanVectorEnvironments :: !(Maybe Int)
  -- ^ Optional exact vector-environment width; 'Nothing' lets the compiler pick
  --   the trainer default.
  , trainingPlanRequestedTransitionFloor :: !(Maybe Word64)
  -- ^ Optional requested minimum total transitions.
  , trainingPlanExactTransitionTarget :: !(Maybe Word64)
  -- ^ When 'Just', the schedule must reproduce this exact transition total or
  --   compilation fails closed.
  }
  deriving stock (Eq, Show)

-- | The evaluation-only inputs for one RL run. Nothing here can reach the
-- schedule.
newtype EvaluationPlan = EvaluationPlan
  { evaluationPlanEpisodes :: Int
  }
  deriving stock (Eq, Show)

-- | A validated plan: the training inputs, the evaluation inputs, and the
-- derived training schedule. The schedule is 'Nothing' only for the ALE
-- @atari-subset@ adapter, which has no neural-trainer schedule.
data CompiledRlPlan = CompiledRlPlan
  { compiledRlTraining :: !TrainingPlan
  , compiledRlEvaluation :: !EvaluationPlan
  , compiledRlSchedule :: !(Maybe RlTrainingSchedule)
  }
  deriving stock (Eq, Show)

compiledRlTrainerKind :: CompiledRlPlan -> Text
compiledRlTrainerKind = trainingPlanTrainerKind . compiledRlTraining

compiledRlEnvironment :: CompiledRlPlan -> Text
compiledRlEnvironment = trainingPlanEnvironment . compiledRlTraining

compiledRlSeed :: CompiledRlPlan -> Int
compiledRlSeed = trainingPlanSeed . compiledRlTraining

compiledRlMaxEpisodeSteps :: CompiledRlPlan -> Int
compiledRlMaxEpisodeSteps = trainingPlanMaxEpisodeSteps . compiledRlTraining

compiledRlEvaluationEpisodes :: CompiledRlPlan -> Int
compiledRlEvaluationEpisodes = evaluationPlanEpisodes . compiledRlEvaluation

-- | The lone environment routed through the runtime-loaded ALE adapter rather
-- than a scheduled neural trainer.
isAleAdapterEnvironment :: Text -> Bool
isAleAdapterEnvironment environment = Text.toLower (Text.strip environment) == "atari-subset"

-- | Compile a 'TrainingPlan' and a separate 'EvaluationPlan' into a validated
-- 'CompiledRlPlan'. The derived schedule is a function of the 'TrainingPlan'
-- alone; the 'EvaluationPlan' only records how many episodes the policy will be
-- scored over.
compileRlPlan :: TrainingPlan -> EvaluationPlan -> Either Text CompiledRlPlan
compileRlPlan training evaluation = do
  positive "RL evaluation episodes" (evaluationPlanEpisodes evaluation)
  positive "RL maximum episode steps" (trainingPlanMaxEpisodeSteps training)
  positive "RL training episode budget floor" (trainingPlanEpisodeBudgetFloor training)
  traverse_ (positive "RL vector-environment count") (trainingPlanVectorEnvironments training)
  scheduleMaybe <-
    if isAleAdapterEnvironment (trainingPlanEnvironment training)
      then Right Nothing
      else Just <$> planTrainingScheduleFor training
  pure
    CompiledRlPlan
      { compiledRlTraining = training
      , compiledRlEvaluation = evaluation
      , compiledRlSchedule = scheduleMaybe
      }

planTrainingScheduleFor :: TrainingPlan -> Either Text RlTrainingSchedule
planTrainingScheduleFor training =
  case trainingPlanExactTransitionTarget training of
    Just target ->
      planExactRlTrainingSchedule
        (trainingPlanTrainerKind training)
        (trainingPlanEnvironment training)
        (trainingPlanEpisodeBudgetFloor training)
        (trainingPlanMaxEpisodeSteps training)
        (trainingPlanVectorEnvironments training)
        target
    Nothing ->
      planRlTrainingSchedule
        (trainingPlanTrainerKind training)
        (trainingPlanEnvironment training)
        (trainingPlanEpisodeBudgetFloor training)
        (trainingPlanMaxEpisodeSteps training)
        (trainingPlanVectorEnvironments training)
        (trainingPlanRequestedTransitionFloor training)

-- Phase 251 — canonical transport for the mounted worker RunConfig. ---------
--
-- A single-line, pipe-delimited @key=value@ transport (mirroring the supervised
-- plan transport) carrying only the plan inputs; the schedule is re-derived on
-- parse. The plan id is the SHA-256 of the canonical input fields, so it is
-- stable across the daemon→worker hop and independent of schedule derivation.

-- | The content-addressed identity of a compiled plan: a hex SHA-256 over its
-- canonical input fields.
compiledRlPlanId :: CompiledRlPlan -> Text
compiledRlPlanId plan =
  sha256Hex
    ( renderTransportFieldList
        (canonicalRlPlanFields (compiledRlTraining plan) (compiledRlEvaluation plan))
    )

-- | Render the full transport: the plan id followed by the canonical inputs.
renderCompiledRlPlanTransport :: CompiledRlPlan -> Text
renderCompiledRlPlanTransport plan =
  renderTransportFieldList
    ( ("plan-id", compiledRlPlanId plan)
        : canonicalRlPlanFields (compiledRlTraining plan) (compiledRlEvaluation plan)
    )

-- | Parse and re-validate a compiled-plan transport. Fails closed unless the
-- declared plan id matches the recomputed id and the canonical re-render is
-- byte-identical to the input.
parseCompiledRlPlanTransport :: Text -> Either Text CompiledRlPlan
parseCompiledRlPlanTransport input = do
  fields <- parseTransportFieldList input
  declaredPlanId <- lookupField "plan-id" fields
  training <-
    TrainingPlan
      <$> (decodeHexField =<< lookupField "trainer-kind" fields)
      <*> (decodeHexField =<< lookupField "environment" fields)
      <*> (intField "seed" =<< lookupField "seed" fields)
      <*> (intField "max-episode-steps" =<< lookupField "max-episode-steps" fields)
      <*> (intField "training-episode-floor" =<< lookupField "training-episode-floor" fields)
      <*> (maybeIntField "vector-environments" =<< lookupField "vector-environments" fields)
      <*> (maybeWord64Field "requested-transition-floor" =<< lookupField "requested-transition-floor" fields)
      <*> (maybeWord64Field "exact-transition-target" =<< lookupField "exact-transition-target" fields)
  evaluation <-
    EvaluationPlan <$> (intField "evaluation-episodes" =<< lookupField "evaluation-episodes" fields)
  plan <- compileRlPlan training evaluation
  if compiledRlPlanId plan /= declaredPlanId
    then Left "compiled RL plan id does not match its declared transport id"
    else
      if renderCompiledRlPlanTransport plan /= input
        then Left "compiled RL plan transport is not canonical"
        else Right plan

canonicalRlPlanFields :: TrainingPlan -> EvaluationPlan -> [(Text, Text)]
canonicalRlPlanFields training evaluation =
  [ ("transport-version", "1")
  , ("kind", "rl-compiled-plan")
  , ("trainer-kind", encodeHexField (trainingPlanTrainerKind training))
  , ("environment", encodeHexField (trainingPlanEnvironment training))
  , ("seed", showText (trainingPlanSeed training))
  , ("max-episode-steps", showText (trainingPlanMaxEpisodeSteps training))
  , ("training-episode-floor", showText (trainingPlanEpisodeBudgetFloor training))
  , ("vector-environments", renderMaybeInt (trainingPlanVectorEnvironments training))
  , ("requested-transition-floor", renderMaybeWord64 (trainingPlanRequestedTransitionFloor training))
  , ("exact-transition-target", renderMaybeWord64 (trainingPlanExactTransitionTarget training))
  , ("evaluation-episodes", showText (evaluationPlanEpisodes evaluation))
  ]

renderTransportFieldList :: [(Text, Text)] -> Text
renderTransportFieldList =
  Text.intercalate "|" . fmap (\(key, value) -> key <> "=" <> value)

parseTransportFieldList :: Text -> Either Text [(Text, Text)]
parseTransportFieldList input =
  traverse parsePair (Text.splitOn "|" input)
 where
  parsePair raw =
    case Text.breakOn "=" raw of
      (key, rest)
        | Text.null rest -> Left ("malformed RL plan transport field: " <> raw)
        | otherwise -> Right (key, Text.drop 1 rest)

lookupField :: Text -> [(Text, Text)] -> Either Text Text
lookupField key fields =
  case lookup key fields of
    Just value -> Right value
    Nothing -> Left ("RL plan transport is missing field: " <> key)

intField :: Text -> Text -> Either Text Int
intField label raw =
  case readMaybe (Text.unpack raw) of
    Just value -> Right value
    Nothing -> Left ("RL plan transport field " <> label <> " is not an integer")

maybeIntField :: Text -> Text -> Either Text (Maybe Int)
maybeIntField label raw
  | raw == "none" = Right Nothing
  | Just rest <- Text.stripPrefix "some:" raw = Just <$> intField label rest
  | otherwise = Left ("RL plan transport field " <> label <> " is not an optional integer")

maybeWord64Field :: Text -> Text -> Either Text (Maybe Word64)
maybeWord64Field label raw
  | raw == "none" = Right Nothing
  | Just rest <- Text.stripPrefix "some:" raw =
      case readMaybe (Text.unpack rest) of
        Just value -> Right (Just value)
        Nothing -> Left ("RL plan transport field " <> label <> " is not an optional Word64")
  | otherwise = Left ("RL plan transport field " <> label <> " is not an optional Word64")

renderMaybeInt :: Maybe Int -> Text
renderMaybeInt Nothing = "none"
renderMaybeInt (Just value) = "some:" <> showText value

renderMaybeWord64 :: Maybe Word64 -> Text
renderMaybeWord64 Nothing = "none"
renderMaybeWord64 (Just value) = "some:" <> showText value

showText :: (Show value) => value -> Text
showText = Text.pack . show

encodeHexField :: Text -> Text
encodeHexField =
  Text.pack . concatMap byteHex . ByteString.unpack . Text.Encoding.encodeUtf8
 where
  byteHex :: Word8 -> String
  byteHex b = [hexDigit (fromIntegral b `div` 16), hexDigit (fromIntegral b `mod` 16)]

decodeHexField :: Text -> Either Text Text
decodeHexField raw =
  case pairs (Text.unpack raw) of
    Nothing -> Left "RL plan transport hex field is malformed"
    Just bytes ->
      case Text.Encoding.decodeUtf8' (ByteString.pack bytes) of
        Left _ -> Left "RL plan transport hex field is not valid UTF-8"
        Right value -> Right value
 where
  pairs [] = Just []
  pairs (h : l : rest) = do
    hi <- hexValue h
    lo <- hexValue l
    ((fromIntegral (hi * 16 + lo) :: Word8) :) <$> pairs rest
  pairs [_] = Nothing

hexDigit :: Int -> Char
hexDigit n
  | n < 10 = toEnum (fromEnum '0' + n)
  | otherwise = toEnum (fromEnum 'a' + n - 10)

hexValue :: Char -> Maybe Int
hexValue c
  | isDigit c = Just (fromEnum c - fromEnum '0')
  | c >= 'a' && c <= 'f' = Just (fromEnum c - fromEnum 'a' + 10)
  | c >= 'A' && c <= 'F' = Just (fromEnum c - fromEnum 'A' + 10)
  | otherwise = Nothing

sha256Hex :: Text -> Text
sha256Hex =
  Text.pack . concatMap byteHex . ByteString.unpack . SHA256.hash . Text.Encoding.encodeUtf8
 where
  byteHex :: Word8 -> String
  byteHex b = [hexDigit (fromIntegral b `div` 16), hexDigit (fromIntegral b `mod` 16)]
