{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.TrainerExecution
  ( TrainerRun (..)
  , TrainedArtifact
  , compileTraditionalRlPlan
  , evaluationSetEpisodes
  , evaluationSetFromEvaluations
  , rlTrainerEnvironmentCompatibilityError
  , runDeviceRollout
  , runTrainerEpisodesForPlan
  , trainedArtifactCounters
  , trainedArtifactEvaluationSet
  , trainedArtifactEvidence
  , trainedArtifactLearningCurve
  , trainedArtifactWeights
  , trainerRunEpisodes
  , trainerRunEvaluationSet
  , validateTrainerEvidenceCounters
  )
where

import Control.Monad (when)
import Crypto.Hash.SHA256 qualified
import Data.ByteString qualified
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Numerics.Mlp (mlpParamsToFlat)
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.Common qualified as AlgorithmCommon
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnTrainer qualified as QrDqnTrainer
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Simulator qualified as RLSim
import JitML.Substrate (Substrate (..), renderSubstrate)

-- | A trained result carries all proof-bearing resources together. Independent
-- optional weights/evidence pairs are deliberately unrepresentable.
data TrainedArtifact = TrainedArtifact
  { trainedArtifactLearningCurve :: !Framework.LearningCurve
  , trainedArtifactEvaluationSet :: !Framework.EvaluationSet
  , trainedArtifactCounters :: !AlgorithmCommon.MeasuredTrainerCounters
  , trainedArtifactWeights :: ![Double]
  , trainedArtifactEvidence :: !ProductEvidence.TrainingEvidence
  }
  deriving stock (Eq, Show)

-- | ALE can currently supply final evaluation only. Every learned neural or
-- ARS policy must use the proof-bearing 'Trained' branch.
data TrainerRun
  = EvaluationOnly !Framework.EvaluationSet
  | Trained !TrainedArtifact
  deriving stock (Eq, Show)

trainerRunEvaluationSet :: TrainerRun -> Framework.EvaluationSet
trainerRunEvaluationSet run =
  case run of
    EvaluationOnly evaluationSet -> evaluationSet
    Trained artifact -> trainedArtifactEvaluationSet artifact

trainerRunEpisodes :: TrainerRun -> [EpisodeEnvelope.SimulatedEpisode]
trainerRunEpisodes = evaluationSetEpisodes . trainerRunEvaluationSet

evaluationSetEpisodes :: Framework.EvaluationSet -> [EpisodeEnvelope.SimulatedEpisode]
evaluationSetEpisodes evaluationSet =
  [ EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex =
          fromIntegral (Framework.evaluationEpisodeIdValue episodeId)
      , EpisodeEnvelope.simEpisodeSteps =
          fromIntegral (Framework.episodeOutcomeSteps outcome)
      , EpisodeEnvelope.simEpisodeReward = Framework.episodeOutcomeReward outcome
      , EpisodeEnvelope.simEpisodeDone = Framework.episodeOutcomeDone outcome
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  | (episodeId, outcome) <- Framework.evaluationSetOutcomes evaluationSet
  ]

runDeviceRollout :: MlpDevice -> Int -> IO (Either Text [EpisodeEnvelope.SimulatedEpisode])
runDeviceRollout device seed = do
  let config =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = seed
          , PpoTrainer.ppoVariant = PpoTrainer.VariantPPO
          , PpoTrainer.ppoNumIterations = 1
          , PpoTrainer.ppoRolloutSteps = 512
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
  resultE <- PpoTrainer.trainOnPolicyOnDevice device PpoTrainer.VariantPPO config
  pure $
    fmap
      ( map
          ( \stat ->
              EpisodeEnvelope.SimulatedEpisode
                { EpisodeEnvelope.simEpisodeIndex = PpoTrainer.iterIndex stat
                , EpisodeEnvelope.simEpisodeSteps = 512
                , EpisodeEnvelope.simEpisodeReward = PpoTrainer.iterMeanReward stat
                , EpisodeEnvelope.simEpisodeDone = True
                , EpisodeEnvelope.simEpisodeFrames = []
                }
          )
          . PpoTrainer.resultIterations
      )
      resultE
{-# NOINLINE runDeviceRollout #-}

trainerRunWithEvidence
  :: Substrate
  -> Text
  -> Text
  -> Int
  -> Word64
  -> AlgorithmCommon.MeasuredTrainerCounters
  -> Framework.LearningCurve
  -> Framework.EvaluationSet
  -> [Double]
  -> [Double]
  -> Either Text TrainerRun
trainerRunWithEvidence substrate trainerKind envName seed expectedTransitions counters learningCurve evaluationSet initialWeights finalWeights = do
  validateTrainerEvidenceCounters expectedTransitions counters
  validateTrainerWeights initialWeights finalWeights
  evidence <-
    ProductEvidence.mkTrainingEvidence
      (hashWeightList initialWeights)
      (hashWeightList finalWeights)
      (AlgorithmCommon.measuredOptimizerUpdateCount counters)
      (rlEvidenceReadHash substrate trainerKind envName seed)
  when
    ( ProductEvidence.evidenceUpdateCount evidence
        /= AlgorithmCommon.measuredOptimizerUpdateCount counters
    )
    (Left "RL measured optimizer-update count does not match training evidence")
  pure
    ( Trained
        TrainedArtifact
          { trainedArtifactLearningCurve = learningCurve
          , trainedArtifactEvaluationSet = evaluationSet
          , trainedArtifactCounters = counters
          , trainedArtifactWeights = finalWeights
          , trainedArtifactEvidence = evidence
          }
    )

validateTrainerEvidenceCounters
  :: Word64
  -> AlgorithmCommon.MeasuredTrainerCounters
  -> Either Text ()
validateTrainerEvidenceCounters expectedTransitions counters
  | AlgorithmCommon.measuredEnvironmentTransitionCount counters /= expectedTransitions =
      Left
        ( "RL measured environment-transition count mismatch: expected "
            <> Text.pack (show expectedTransitions)
            <> ", observed "
            <> Text.pack
              (show (AlgorithmCommon.measuredEnvironmentTransitionCount counters))
        )
  | otherwise = Right ()

validateTrainerWeights :: [Double] -> [Double] -> Either Text ()
validateTrainerWeights initialWeights finalWeights
  | null initialWeights = Left "RL training evidence requires non-empty initial weights"
  | null finalWeights = Left "RL training evidence requires non-empty final weights"
  | length initialWeights /= length finalWeights =
      Left
        ( "RL initial/final weight cardinality mismatch: initial "
            <> Text.pack (show (length initialWeights))
            <> ", final "
            <> Text.pack (show (length finalWeights))
        )
  | any nonFinite initialWeights = Left "RL initial weights must be finite"
  | any nonFinite finalWeights = Left "RL final weights must be finite"
  | otherwise = Right ()
 where
  nonFinite value = isNaN value || isInfinite value

hashWeightList :: [Double] -> Text
hashWeightList =
  hashBytes . LazyByteString.toStrict . Checkpoint.encodeJmw1

rlEvidenceReadHash :: Substrate -> Text -> Text -> Int -> Text
rlEvidenceReadHash substrate trainerKind envName seed =
  sha256Text $
    Text.intercalate
      ":"
      [ "rl-evidence"
      , renderSubstrate substrate
      , trainerKind
      , envName
      , Text.pack (show seed)
      ]

positiveWordFromInt :: Text -> Int -> Either Text Word64
positiveWordFromInt label = positiveWordFromInteger label . toInteger

positiveWordFromInteger :: Text -> Integer -> Either Text Word64
positiveWordFromInteger label value
  | value <= 0 = Left (label <> " must be positive")
  | value > toInteger (maxBound :: Word64) =
      Left (label <> " exceeds the Word64 range")
  | otherwise = Right (fromIntegral value)

evaluationSetFromEpisodes
  :: Int
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Either Text Framework.EvaluationSet
evaluationSetFromEpisodes expectedEpisodes episodes = do
  expected <- positiveWordFromInt "RL planned evaluation-episode count" expectedEpisodes
  raw <- traverse toRawOutcome episodes
  Framework.mkEvaluationSet expected raw
 where
  toRawOutcome episode
    | EpisodeEnvelope.simEpisodeIndex episode < 0 =
        Left "RL evaluation episode id must be non-negative"
    | otherwise =
        Right
          ( fromIntegral (EpisodeEnvelope.simEpisodeIndex episode)
          , EpisodeEnvelope.simEpisodeReward episode
          , EpisodeEnvelope.simEpisodeSteps episode
          , EpisodeEnvelope.simEpisodeDone episode
          )

-- | Key zero-based evaluator results into the exact planned final-policy
-- cohort.  The evaluator's environment-terminal bit is carried unchanged;
-- horizon exhaustion is not promoted to terminal success.
evaluationSetFromEvaluations
  :: Int
  -> [AlgorithmCommon.EvaluationEpisodeResult]
  -> Either Text Framework.EvaluationSet
evaluationSetFromEvaluations expectedEpisodes evaluations = do
  expected <- positiveWordFromInt "RL planned evaluation-episode count" expectedEpisodes
  Framework.mkEvaluationSet expected (fmap toRawOutcome (zip [0 ..] evaluations))
 where
  toRawOutcome (episodeId, evaluation) =
    ( episodeId
    , AlgorithmCommon.evaluationEpisodeReward evaluation
    , AlgorithmCommon.evaluationEpisodeSteps evaluation
    , AlgorithmCommon.evaluationEpisodeTerminated evaluation
    )

learningCurveFromStats
  :: Text
  -> [(Int, Double)]
  -> Either Text Framework.LearningCurve
learningCurveFromStats metricName stats = do
  summaries <- traverse toSummary stats
  Framework.mkLearningCurve summaries
 where
  toSummary (index, value)
    | index < 0 = Left "RL learning-curve iteration index must be non-negative"
    | otherwise = Framework.mkIterationSummary (fromIntegral index) metricName value

-- | Phase 251 — compile a traditional (non-product) RL run into a validated
-- 'ProductBudget.CompiledRlPlan'. This is the sole reader of the
-- @JITML_PRODUCT_RL_VEC_ENVS@ vector-width compatibility override; once it is
-- resolved the schedule is derived by the pure plan compiler. The training
-- episode-budget floor is the canonical training constant, never the evaluation
-- episode count, so the evaluation count can never move a training dimension.
compileTraditionalRlPlan
  :: Text
  -> Text
  -> Int
  -> Int
  -> Int
  -> Maybe Word64
  -> IO (Either Text ProductBudget.CompiledRlPlan)
compileTraditionalRlPlan trainerKind envName seed evalEpisodes maxEpisodeSteps requestedFloor = do
  vectorOverrideE <- resolveCompatibilityVectorOverride
  pure $ do
    vectorOverride <- vectorOverrideE
    let training =
          ProductBudget.TrainingPlan
            { ProductBudget.trainingPlanTrainerKind = trainerKind
            , ProductBudget.trainingPlanEnvironment = envName
            , ProductBudget.trainingPlanSeed = seed
            , ProductBudget.trainingPlanMaxEpisodeSteps = maxEpisodeSteps
            , ProductBudget.trainingPlanEpisodeBudgetFloor =
                ProductBudget.productRlDefaultTrainingEpisodeFloor
            , ProductBudget.trainingPlanVectorEnvironments = vectorOverride
            , ProductBudget.trainingPlanRequestedTransitionFloor = requestedFloor
            , ProductBudget.trainingPlanExactTransitionTarget = Nothing
            }
    ProductBudget.compileRlPlan training (ProductBudget.EvaluationPlan evalEpisodes)

resolveCompatibilityVectorOverride :: IO (Either Text (Maybe Int))
resolveCompatibilityVectorOverride = do
  raw <- lookupEnv "JITML_PRODUCT_RL_VEC_ENVS"
  pure $
    case raw of
      Nothing -> Right Nothing
      Just encoded ->
        case readMaybe encoded of
          Nothing -> Left "JITML_PRODUCT_RL_VEC_ENVS must be a positive integer"
          Just value
            | value <= 0 -> Left "JITML_PRODUCT_RL_VEC_ENVS must be positive"
            | otherwise -> Right (Just value)

-- | Dispatch the worker-side RL run to the selected real trainer using a
-- validated 'ProductBudget.CompiledRlPlan'. Learning summaries remain an
-- ordered 'Framework.LearningCurve'; final-policy outcomes become an exact
-- keyed 'Framework.EvaluationSet', with 'EpisodeEnvelope.SimulatedEpisode' kept
-- only as a trajectory/animation projection. Every training dimension is read
-- from the pre-compiled schedule; the evaluation episode count feeds only the
-- @evaluate*@ scoring calls. Every trainer is bit-deterministic on the same
-- substrate / same seed per
-- [../documents/engineering/determinism_contract.md](../documents/engineering/determinism_contract.md).
-- The @atari-subset@ environment always routes through ALE first; an
-- unrecognised @trainerKind@ for other environments fails closed before any
-- artifact or broker event is emitted.
runTrainerEpisodesForPlan
  :: Substrate
  -> MlpDevice
  -> Maybe Text
  -> ProductBudget.CompiledRlPlan
  -> IO (Either Text TrainerRun)
runTrainerEpisodesForPlan substrate device atariRomPath plan
  | Text.toLower envName == "atari-subset" = do
      -- Atari routes through the runtime-loaded ALE adapter (Sprint 8.8),
      -- not the MLP device; ROM-policy failures surface as a typed `Left`.
      result <- ALE.runAtariSubsetEpisodes atariRomPath seed evalEpisodes maxStepsPerEpisode
      pure
        ( do
            episodes <- result
            let observedEpisodes = fmap fromAleEpisode episodes
            evaluationSet <- evaluationSetFromEpisodes evalEpisodes observedEpisodes
            Right (EvaluationOnly evaluationSet)
        )
  | trainerKind == "ars" =
      -- ARS is the lone no-MLP exception (Sprint 8.11): a finite-difference
      -- random-search method with no network forward/backward, so it does not
      -- route through the device seam.
      case rlTrainerEnvironmentCompatibilityError trainerKind envName of
        Just err -> pure (Left err)
        Nothing -> arsEpisodes
  | trainerKind `notElem` knownMlpTrainers =
      pure
        ( Left
            ( "unknown RL trainer: "
                <> trainerKind
                <> " (expected one of: "
                <> Text.intercalate ", " (knownMlpTrainers <> ["ars"])
                <> ")"
            )
        )
  | Just err <- rlTrainerEnvironmentCompatibilityError trainerKind envName =
      pure (Left err)
  | otherwise = do
      -- Sprint 8.11 fail-closed device gate: confirm the substrate's JIT
      -- kernel compiles/loads/runs on this host before dispatching, so a
      -- missing toolchain/hardware fails closed instead of a trainer
      -- silently degrading to its pure-Haskell update path.
      probe <- probeMlpDevice device
      case probe of
        Left engineErr ->
          pure
            ( Left
                ( "RL substrate device unavailable for trainer "
                    <> trainerKind
                    <> ": "
                    <> engineErr
                )
            )
        Right () -> dispatchMlpTrainer
 where
  training = ProductBudget.compiledRlTraining plan
  trainerKind = ProductBudget.trainingPlanTrainerKind training
  envName = ProductBudget.trainingPlanEnvironment training
  seed = ProductBudget.trainingPlanSeed training
  evalEpisodes = ProductBudget.compiledRlEvaluationEpisodes plan
  maxStepsPerEpisode = ProductBudget.compiledRlMaxEpisodeSteps plan
  scheduleMaybe = ProductBudget.compiledRlSchedule plan
  knownMlpTrainers =
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
  dispatchMlpTrainer =
    case trainerKind of
      "ppo" -> onPolicyEpisodes PpoTrainer.VariantPPO
      "a2c" -> onPolicyEpisodes PpoTrainer.VariantA2C
      "trpo" -> onPolicyEpisodes PpoTrainer.VariantTRPO
      "maskableppo" -> onPolicyEpisodes PpoTrainer.VariantMaskablePPO
      "recurrentppo" -> onPolicyEpisodes PpoTrainer.VariantRecurrentPPO
      "dqn" -> dqnEpisodes False
      "qrdqn" -> qrDqnEpisodes
      "ddpg" -> continuousEpisodes ContinuousTrainer.VariantDDPG
      "td3" -> continuousEpisodes ContinuousTrainer.VariantTD3
      "sac" -> continuousEpisodes ContinuousTrainer.VariantSAC
      "crossq" -> continuousEpisodes ContinuousTrainer.VariantCrossQ
      "tqc" -> continuousEpisodes ContinuousTrainer.VariantTQC
      "her" -> herEpisodes
      _ -> pure (Left ("unhandled RL trainer: " <> trainerKind))
  fromAleEpisode episode =
    EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = ALE.aleEpisodeIndex episode
      , EpisodeEnvelope.simEpisodeSteps = ALE.aleEpisodeSteps episode
      , EpisodeEnvelope.simEpisodeReward = ALE.aleEpisodeReward episode
      , EpisodeEnvelope.simEpisodeDone = ALE.aleEpisodeDone episode
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  -- Sprint 8.11 — every MLP-backed trainer routes through its `*OnDevice`
  -- variant against the resolved substrate device, with iteration budgets
  -- raised from the old `max 1 evalEpisodes` floor so training actually
  -- learns rather than running a single non-converging iteration.
  onPolicyEpisodes variant = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.OnPolicyTrainingSchedule {} -> do
            let (epochsPerUpdate, learningRate) = onPolicyTuning substrate
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
                        onPolicyEpochsPerUpdateFor variant envName epochsPerUpdate
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
            resultE <- PpoTrainer.trainOnPolicyOnDeviceWithEnvironment device simEnv variant config
            pure $
              resultE
                >>= \result ->
                  let evaluations =
                        PpoTrainer.evaluateOnPolicyWithEnvironment
                          simEnv
                          config
                          (PpoTrainer.resultFinalParams result)
                          evalEpisodes
                      initialWeights = mlpParamsToFlat (PpoTrainer.initialPpoParams config)
                      finalWeights = mlpParamsToFlat (PpoTrainer.resultFinalParams result)
                   in do
                        evaluationSet <- evaluationSetFromEvaluations evalEpisodes evaluations
                        learningCurve <-
                          learningCurveFromStats
                            "training_median_reward"
                            [ ( PpoTrainer.iterIndex stat
                              , PpoTrainer.iterMedianReward stat
                              )
                            | stat <- PpoTrainer.resultIterations result
                            , PpoTrainer.iterEpisodes stat > 0
                            ]
                        trainerRunWithEvidence
                          substrate
                          trainerKind
                          envName
                          seed
                          (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                          (PpoTrainer.resultMeasuredCounters result)
                          learningCurve
                          evaluationSet
                          initialWeights
                          finalWeights
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  -- One on-policy tuning across substrates: the cuBLAS (linux-cuda) and oneDNN
  -- (linux-cpu) GEMM paths are numerically close, so the same (epochs, lr) that
  -- converges cartpole/lunar on linux-cpu must be used on linux-cuda rather than
  -- a more aggressive (fewer-epochs, higher-lr) pair that left PPO/MaskablePPO
  -- cartpole stuck at ~210 on the CUDA lane.
  onPolicyTuning LinuxCPU = (10, 5.0e-4)
  onPolicyTuning LinuxCUDA = (10, 5.0e-4)
  onPolicyTuning AppleSilicon = (10, 5.0e-4)
  -- TRPO performs one natural-gradient actor step and its own isolated
  -- value-head fitting passes per rollout. PPO's repeated gradient-epoch field
  -- is deliberately ignored; the TRPO critic count and learning rate are
  -- explicit trainer fields.
  onPolicyEpochsPerUpdateFor PpoTrainer.VariantTRPO _ _ = 1
  onPolicyEpochsPerUpdateFor _ _ fallback = fallback
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
  dqnEpisodes useDouble = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.FixedStepTrainingSchedule {} -> do
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
            resultE <- DqnTrainer.trainDqnOnDeviceWithEnvironment device simEnv config
            case resultE of
              Left err -> pure (Left err)
              Right result -> do
                evaluationE <-
                  DqnTrainer.evaluateDqnPolicyWithEnvironment
                    device
                    simEnv
                    config
                    (DqnTrainer.dqnResultFinalParams result)
                    evalEpisodes
                pure $
                  evaluationE >>= \evaluation ->
                    let initialWeights = mlpParamsToFlat (DqnTrainer.initialDqnParams config)
                        finalWeights = mlpParamsToFlat (DqnTrainer.dqnResultFinalParams result)
                     in do
                          evaluationSet <- evaluationSetFromEvaluations evalEpisodes evaluation
                          learningCurve <-
                            learningCurveFromStats
                              "training_mean_reward"
                              [ ( DqnTrainer.dqnIterStep stat
                                , DqnTrainer.dqnIterMeanReward stat
                                )
                              | stat <- DqnTrainer.dqnResultStats result
                              , DqnTrainer.dqnIterEpisodes stat > 0
                              ]
                          trainerRunWithEvidence
                            substrate
                            trainerKind
                            envName
                            seed
                            (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                            (DqnTrainer.dqnResultMeasuredCounters result)
                            learningCurve
                            evaluationSet
                            initialWeights
                            finalWeights
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  qrDqnEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.FixedStepTrainingSchedule {} -> do
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
            resultE <- QrDqnTrainer.trainQrDqnOnDeviceWithEnvironment device simEnv config
            pure $
              resultE
                >>= \result ->
                  let evaluations =
                        QrDqnTrainer.evaluateQrDqnPolicyWithEnvironment
                          simEnv
                          config
                          (QrDqnTrainer.qrResultFinalParams result)
                          evalEpisodes
                      initialWeights = mlpParamsToFlat (QrDqnTrainer.initialQrDqnParams config)
                      finalWeights = mlpParamsToFlat (QrDqnTrainer.qrResultFinalParams result)
                   in do
                        evaluationSet <- evaluationSetFromEvaluations evalEpisodes evaluations
                        learningCurve <-
                          learningCurveFromStats
                            "training_mean_reward"
                            [ ( QrDqnTrainer.qrIterStep stat
                              , QrDqnTrainer.qrIterMeanReward stat
                              )
                            | stat <- QrDqnTrainer.qrResultStats result
                            , QrDqnTrainer.qrIterEpisodes stat > 0
                            ]
                        trainerRunWithEvidence
                          substrate
                          trainerKind
                          envName
                          seed
                          (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                          (QrDqnTrainer.qrResultMeasuredCounters result)
                          learningCurve
                          evaluationSet
                          initialWeights
                          finalWeights
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  continuousEpisodes variant = do
    case RLSim.lookupContinuousEnvironmentByName envName of
      Nothing -> pure (Left ("unknown continuous RL environment: " <> envName))
      Just contEnv@(RLSim.SomeContinuousEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.FixedStepTrainingSchedule {} -> do
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
            resultE <- ContinuousTrainer.trainContinuousOnDeviceWithEnvironment device contEnv config
            pure $
              resultE
                >>= \result ->
                  let evaluations =
                        ContinuousTrainer.evaluateContinuousPolicyWithEnvironment
                          contEnv
                          config
                          (ContinuousTrainer.contResultFinalActor result)
                          evalEpisodes
                      initialWeights = mlpParamsToFlat (ContinuousTrainer.initialContinuousActor config)
                      finalWeights = mlpParamsToFlat (ContinuousTrainer.contResultFinalActor result)
                   in do
                        evaluationSet <- evaluationSetFromEvaluations evalEpisodes evaluations
                        learningCurve <-
                          learningCurveFromStats
                            "training_mean_reward"
                            [ ( ContinuousTrainer.contIterStep stat
                              , ContinuousTrainer.contIterMeanReward stat
                              )
                            | stat <- ContinuousTrainer.contResultStats result
                            , ContinuousTrainer.contIterEpisodes stat > 0
                            ]
                        trainerRunWithEvidence
                          substrate
                          trainerKind
                          envName
                          seed
                          (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                          (ContinuousTrainer.contResultMeasuredCounters result)
                          learningCurve
                          evaluationSet
                          initialWeights
                          finalWeights
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  arsEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.ArsTrainingSchedule {} -> do
            let config =
                  ArsTrainer.defaultArsTrainConfig
                    { ArsTrainer.arsSeed = seed
                    , ArsTrainer.arsIterations = ProductBudget.scheduleArsIterations schedule
                    , ArsTrainer.arsNumDirections = ProductBudget.scheduleArsDirections schedule
                    , ArsTrainer.arsMaxEpisodeSteps = ProductBudget.scheduleArsMaxEpisodeSteps schedule
                    , ArsTrainer.arsActionCount = RLSim.envActionCount environment
                    , ArsTrainer.arsObsSize = RLSim.envObservationSize environment
                    }
            result <- ArsTrainer.trainArsOnEnvironment simEnv config
            let evaluations =
                  ArsTrainer.evaluateArsPolicyWithEnvironment
                    simEnv
                    config
                    (ArsTrainer.arsResultFinalParams result)
                    evalEpisodes
                initialWeights = VU.toList (ArsTrainer.initialArsParams config)
                finalWeights = VU.toList (ArsTrainer.arsResultFinalParams result)
            pure $ do
              evaluationSet <- evaluationSetFromEvaluations evalEpisodes evaluations
              learningCurve <-
                learningCurveFromStats
                  "training_mean_reward"
                  [ ( ArsTrainer.arsIterIndex stat
                    , ArsTrainer.arsIterMeanReturn stat
                    )
                  | stat <- ArsTrainer.arsResultStats result
                  ]
              trainerRunWithEvidence
                substrate
                trainerKind
                envName
                seed
                (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                (ArsTrainer.arsResultMeasuredCounters result)
                learningCurve
                evaluationSet
                initialWeights
                finalWeights
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  herEpisodes = do
    case scheduleMaybe of
      Just schedule@ProductBudget.HerTrainingSchedule {} -> do
        let config =
              HerTrainer.defaultHerTrainConfig
                { HerTrainer.herSeed = seed
                , HerTrainer.herHiddenUnits = HerTrainer.productHerHiddenUnits
                , HerTrainer.herEpisodes = ProductBudget.scheduleHerEpisodes schedule
                }
        resultE <- HerTrainer.trainHerOnDevice device config
        pure $
          resultE
            >>= \result ->
              let evals =
                    HerTrainer.evaluateHerGreedy
                      config
                      (HerTrainer.herResultFinalParams result)
                      evalEpisodes
                      (seed + 104729)
                  -- Encode the greedy (epsilon=0) eval into the SimulatedEpisode
                  -- plumbing: done = reached-goal, reward = 1 - normalized distance.
                  episodes =
                    [ EpisodeEnvelope.SimulatedEpisode
                        { EpisodeEnvelope.simEpisodeIndex = i
                        , EpisodeEnvelope.simEpisodeSteps = steps
                        , EpisodeEnvelope.simEpisodeReward = 1.0 - normDist
                        , EpisodeEnvelope.simEpisodeDone = reached
                        , EpisodeEnvelope.simEpisodeFrames = []
                        }
                    | (i, (reached, normDist, steps)) <- zip [0 ..] evals
                    ]
                  initialWeights = mlpParamsToFlat (HerTrainer.initialHerParams config)
                  finalWeights = mlpParamsToFlat (HerTrainer.herResultFinalParams result)
               in do
                    evaluationSet <- evaluationSetFromEpisodes evalEpisodes episodes
                    learningCurve <-
                      learningCurveFromStats
                        "training_success_rate"
                        [ ( HerTrainer.herIterEpisode stat
                          , HerTrainer.herIterSuccessRate stat
                          )
                        | stat <- HerTrainer.herResultStats result
                        ]
                    trainerRunWithEvidence
                      substrate
                      trainerKind
                      envName
                      seed
                      (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                      (HerTrainer.herResultMeasuredCounters result)
                      learningCurve
                      evaluationSet
                      initialWeights
                      finalWeights
      _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
{-# NOINLINE runTrainerEpisodesForPlan #-}

rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError =
  ProductBudget.rlTrainerEnvironmentCompatibilityError

sha256Text :: Text -> Text
sha256Text =
  hashBytes . Crypto.Hash.SHA256.hash . Text.Encoding.encodeUtf8

hashBytes :: Data.ByteString.ByteString -> Text
hashBytes =
  hexEncodeBytes . Crypto.Hash.SHA256.hash

hexEncodeBytes :: Data.ByteString.ByteString -> Text
hexEncodeBytes =
  Text.pack
    . concatMap (\b -> [hexDigit (fromIntegral b `div` 16), hexDigit (fromIntegral b `mod` 16)])
    . Data.ByteString.unpack
 where
  hexDigit n
    | n < 10 = toEnum (fromEnum '0' + n)
    | otherwise = toEnum (fromEnum 'a' + n - 10)
