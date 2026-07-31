{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.TrainerExecution
  ( TrainerRun
  , compileTraditionalRlPlan
  , rlObservedBudgetUnits
  , rlTrainerEnvironmentCompatibilityError
  , runDeviceRollout
  , runTrainerEpisodesForPlan
  , trainerRunEpisodes
  , trainerRunEvidence
  , trainerRunObservedUnits
  , trainerRunWeights
  , validateTrainerEvidenceCounters
  )
where

import Crypto.Hash.SHA256 qualified
import Data.ByteString qualified
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (traverse_)
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
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnTrainer qualified as QrDqnTrainer
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Simulator qualified as RLSim
import JitML.Substrate (Substrate (..), renderSubstrate)

-- | Worker-side RL result: per-iteration summaries plus optional flattened
-- trained weights for checkpoint persistence.
data TrainerRun = TrainerRun
  { trainerRunEpisodes :: [EpisodeEnvelope.SimulatedEpisode]
  , trainerRunObservedUnits :: Word64
  , trainerRunWeights :: Maybe [Double]
  , trainerRunEvidence :: Maybe ProductEvidence.TrainingEvidence
  }
  deriving stock (Eq, Show)

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
  -> [Double]
  -> [Double]
  -> Word64
  -> [EpisodeEnvelope.SimulatedEpisode]
  -> Either Text TrainerRun
trainerRunWithEvidence substrate trainerKind envName seed updateCount initialWeights finalWeights observedUnits episodes = do
  validateTrainerEvidenceCounters updateCount observedUnits
  evidence <-
    ProductEvidence.mkTrainingEvidence
      (hashWeightList initialWeights)
      (hashWeightList finalWeights)
      updateCount
      (rlEvidenceReadHash substrate trainerKind envName seed)
  pure
    TrainerRun
      { trainerRunEpisodes = episodes
      , trainerRunObservedUnits = observedUnits
      , trainerRunWeights = Just finalWeights
      , trainerRunEvidence = Just evidence
      }

validateTrainerEvidenceCounters :: Word64 -> Word64 -> Either Text ()
validateTrainerEvidenceCounters updateCount observedUnits
  | updateCount == 0 = Left "RL training evidence requires a positive update count"
  | observedUnits == 0 = Left "RL training evidence requires positive observed budget units"
  | otherwise = Right ()

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
-- validated 'ProductBudget.CompiledRlPlan', projecting trainer summaries into
-- the 'EpisodeEnvelope.SimulatedEpisode' publication envelope consumed by the
-- trajectory artifact and @EpisodeDone@ path. Every training dimension is read
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
            observedUnits <- rlObservedBudgetUnits observedEpisodes
            Right
              TrainerRun
                { trainerRunEpisodes = observedEpisodes
                , trainerRunObservedUnits = observedUnits
                , trainerRunWeights = Nothing
                , trainerRunEvidence = Nothing
                }
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
  asEpisodeWithSteps index (reward, steps) =
    EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = index
      , EpisodeEnvelope.simEpisodeSteps = steps
      , EpisodeEnvelope.simEpisodeReward = reward
      , EpisodeEnvelope.simEpisodeDone = True
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  evaluatedEpisodes :: [(Double, Int)] -> [EpisodeEnvelope.SimulatedEpisode]
  evaluatedEpisodes = goEvaluated 0
   where
    goEvaluated _ [] = []
    goEvaluated i (episode : rest) = asEpisodeWithSteps i episode : goEvaluated (i + 1) rest
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
                  let episodes =
                        evaluatedEpisodes $
                          PpoTrainer.evaluateOnPolicyWithEnvironment
                            simEnv
                            config
                            (PpoTrainer.resultFinalParams result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (PpoTrainer.initialPpoParams config)
                      finalWeights = mlpParamsToFlat (PpoTrainer.resultFinalParams result)
                   in do
                        updateCount <-
                          positiveWordFromInt
                            "RL on-policy update count"
                            (PpoTrainer.resultOptimizerSteps result)
                        trainerRunWithEvidence
                          substrate
                          trainerKind
                          envName
                          seed
                          updateCount
                          initialWeights
                          finalWeights
                          (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                          episodes
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
                    let episodes = evaluatedEpisodes evaluation
                        initialWeights = mlpParamsToFlat (DqnTrainer.initialDqnParams config)
                        finalWeights = mlpParamsToFlat (DqnTrainer.dqnResultFinalParams result)
                     in do
                          updateCount <-
                            positiveWordFromInt
                              "DQN update count"
                              (DqnTrainer.dqnResultOptimizerSteps result)
                          trainerRunWithEvidence
                            substrate
                            trainerKind
                            envName
                            seed
                            updateCount
                            initialWeights
                            finalWeights
                            (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                            episodes
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
                  let episodes =
                        evaluatedEpisodes $
                          QrDqnTrainer.evaluateQrDqnPolicyWithEnvironment
                            simEnv
                            config
                            (QrDqnTrainer.qrResultFinalParams result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (QrDqnTrainer.initialQrDqnParams config)
                      finalWeights = mlpParamsToFlat (QrDqnTrainer.qrResultFinalParams result)
                   in do
                        updateCount <-
                          positiveWordFromInt
                            "QR-DQN update count"
                            (QrDqnTrainer.qrResultOptimizerSteps result)
                        trainerRunWithEvidence
                          substrate
                          trainerKind
                          envName
                          seed
                          updateCount
                          initialWeights
                          finalWeights
                          (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                          episodes
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
                  let episodes =
                        evaluatedEpisodes $
                          ContinuousTrainer.evaluateContinuousPolicyWithEnvironment
                            contEnv
                            config
                            (ContinuousTrainer.contResultFinalActor result)
                            evalEpisodes
                      initialWeights = mlpParamsToFlat (ContinuousTrainer.initialContinuousActor config)
                      finalWeights = mlpParamsToFlat (ContinuousTrainer.contResultFinalActor result)
                   in do
                        updateCount <-
                          positiveWordFromInt
                            "continuous-RL actor update count"
                            (ContinuousTrainer.contResultActorOptimizerSteps result)
                        trainerRunWithEvidence
                          substrate
                          trainerKind
                          envName
                          seed
                          updateCount
                          initialWeights
                          finalWeights
                          (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                          episodes
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
            let episodes =
                  evaluatedEpisodes $
                    ArsTrainer.evaluateArsPolicyWithEnvironment
                      simEnv
                      config
                      (ArsTrainer.arsResultFinalParams result)
                      evalEpisodes
                initialWeights = VU.toList (ArsTrainer.initialArsParams config)
                finalWeights = VU.toList (ArsTrainer.arsResultFinalParams result)
            pure $ do
              updateCount <- positiveWordFromInt "ARS update count" (ArsTrainer.arsIterations config)
              trainerRunWithEvidence
                substrate
                trainerKind
                envName
                seed
                updateCount
                initialWeights
                finalWeights
                (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                episodes
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  herEpisodes = do
    case scheduleMaybe of
      Just schedule@ProductBudget.HerTrainingSchedule {} -> do
        let config =
              HerTrainer.defaultHerTrainConfig
                { HerTrainer.herSeed = seed
                , HerTrainer.herHiddenUnits = HerTrainer.productHerHiddenUnits
                , HerTrainer.herEpisodes = ProductBudget.scheduleHerEpisodes schedule
                , HerTrainer.herStatInterval = max 25 evalEpisodes
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
                        , EpisodeEnvelope.simEpisodeSteps = HerTrainer.herNumBits config
                        , EpisodeEnvelope.simEpisodeReward = 1.0 - normDist
                        , EpisodeEnvelope.simEpisodeDone = reached
                        , EpisodeEnvelope.simEpisodeFrames = []
                        }
                    | (i, (reached, normDist)) <- zip [0 ..] evals
                    ]
                  initialWeights = mlpParamsToFlat (HerTrainer.initialHerParams config)
                  finalWeights = mlpParamsToFlat (HerTrainer.herResultFinalParams result)
               in do
                    updateCount <-
                      positiveWordFromInt
                        "HER update count"
                        (HerTrainer.herResultOptimizerSteps result)
                    trainerRunWithEvidence
                      substrate
                      trainerKind
                      envName
                      seed
                      updateCount
                      initialWeights
                      finalWeights
                      (ProductBudget.scheduleObservedEnvironmentSteps schedule)
                      episodes
      _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
{-# NOINLINE runTrainerEpisodesForPlan #-}

rlTrainerEnvironmentCompatibilityError :: Text -> Text -> Maybe Text
rlTrainerEnvironmentCompatibilityError =
  ProductBudget.rlTrainerEnvironmentCompatibilityError

rlObservedBudgetUnits
  :: [EpisodeEnvelope.SimulatedEpisode]
  -> Either Text Word64
rlObservedBudgetUnits episodes = do
  traverse_ validateEpisodeSteps episodes
  positiveWordFromInteger
    "RL observed environment-step count"
    (sum (fmap (toInteger . EpisodeEnvelope.simEpisodeSteps) episodes))
 where
  validateEpisodeSteps episode
    | EpisodeEnvelope.simEpisodeSteps episode <= 0 =
        Left
          ( "RL episode "
              <> Text.pack (show (EpisodeEnvelope.simEpisodeIndex episode))
              <> " must report positive observed steps"
          )
    | otherwise = Right ()

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
