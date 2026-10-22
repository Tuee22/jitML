{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.TrainerExecution
  ( TrainerRun (..)
  , TrainedArtifact
  , ArsProducerSourceInput (..)
  , ArsProducerSourceCoverage (..)
  , ArsAttemptStage (..)
  , ArsAttemptFailure (..)
  , ArsBoundExecutionInput
  , ArsProductAttempt
  , ProducedArsHostExecution
  , prepareArsBoundExecutionInput
  , runArsProductAttempt
  , BegunArsProductAttempt
  , PreparedArsProductAttempt
  , PendingArsProductReturn
  , beginArsProductAttempt
  , begunArsInput
  , begunArsAttemptId
  , begunArsBeforeProcess
  , begunArsSourceCoverage
  , prepareBegunArsProductAttempt
  , preparedArsProductInput
  , preparedArsProductAttemptId
  , preparedArsProductSnapshot
  , runPreparedArsProductAttempt
  , pendingArsProductInput
  , pendingArsProductAttemptId
  , pendingArsPreparedSnapshot
  , pendingArsRawReturn
  , pendingArsReturnFailure
  , finishArsProductAttempt
  , arsProductAttemptPreparedSnapshot
  , producedArsHostPreparedSnapshot
  , observeArsStageFailureBoundary
  , arsBoundInputRunPlan
  , arsBoundInputCompiledPlan
  , arsBoundInputRowId
  , arsBoundInputSubstrate
  , arsBoundInputSuppliedInvocation
  , arsBoundInputSourceInput
  , arsProductAttemptRawReturn
  , arsProductAttemptEvaluation
  , arsProductAttemptFailure
  , arsProductAttemptStrictResult
  , arsProductAttemptOrigin
  , producedArsHostRunPlan
  , producedArsHostCompiledPlan
  , producedArsHostRowId
  , producedArsHostSubstrate
  , producedArsHostSuppliedInvocation
  , producedArsHostSourceCoverage
  , producedArsHostAttemptId
  , producedArsHostTrace
  , producedArsHostReference
  , producedArsHostBeforeProcess
  , producedArsHostAfterProcess
  , producedArsHostEvaluation
  , GenericArsAttempt
  , ProducedGenericArsHostExecution
  , runGenericArsAttemptForPlan
  , genericArsAttemptStrictResult
  , genericArsAttemptRawReturn
  , genericArsAttemptEvaluation
  , genericArsAttemptFailure
  , genericArsAttemptOrigin
  , producedGenericArsHostCompiledPlan
  , producedGenericArsHostExperiment
  , producedGenericArsHostTrace
  , producedGenericArsHostReference
  , producedGenericArsHostBeforeProcess
  , producedGenericArsHostAfterProcess
  , compileTraditionalRlPlan
  , evaluationSetEpisodes
  , evaluationSetFromEvaluations
  , rlTrainerEnvironmentCompatibilityError
  , runDeviceRollout
  , runTrainerEpisodesForPlan
  , runRawTrainerObservationForPlan
  , evaluateStrictTrainerReturn
  , refineStrictRecordedTrainerObservation
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

import Control.Exception (evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Crypto.Hash.SHA256 qualified
import Data.Bifunctor (first)
import Data.ByteString qualified
import Data.ByteString.Lazy qualified as LazyByteString
import Data.IORef qualified as IORef
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import System.Environment (lookupEnv)
import System.IO (IOMode (ReadMode), withBinaryFile)
import Text.Read (readMaybe)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Execution.ProducerObservation qualified as Producer
import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.MlpDevice (MlpDevice, mlpdExecutionWitness, probeMlpDevice)
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as ArsReference
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.Common qualified as AlgorithmCommon
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnTrainer qualified as QrDqnTrainer
import JitML.RL.ArsHostTrace qualified as ArsTrace
import JitML.RL.EpisodeEnvelope qualified as EpisodeEnvelope
import JitML.RL.Framework qualified as Framework
import JitML.RL.ProductBudget qualified as ProductBudget
import JitML.RL.Simulator qualified as RLSim
import JitML.RL.TrainerConfiguration qualified as Configuration
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Training.Budget qualified as TrainingBudget

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
runTrainerEpisodesForPlan substrate device atariRomPath plan = do
  -- Strict counters are refined at the old lower-trainer return boundary,
  -- before final evaluator IO. Everything after it keeps its original order.
  attempted <- executeRawTrainerObservation StrictBeforeEvaluation substrate device atariRomPath plan
  case attempted >>= refineStrictObservation substrate of
    Left err -> pure (Left err)
    Right run@(EvaluationOnly _) -> pure (Right run)
    Right run@(Trained artifact)
      | ProductBudget.compiledRlTrainerKind plan == "ars" -> pure (Right run)
      | otherwise -> do
          -- Same selected device, exactly once, only after all strict
          -- counter/evaluator/curve/weight/evidence refinement has succeeded.
          witnessResult <- mlpdExecutionWitness device
          pure $ do
            witness <-
              witnessResult
                >>= maybe
                  (Left "RL selected-device training returned no execution witness")
                  Right
            when
              (DeviceWitness.witnessSubstrate witness /= substrate)
              (Left "RL selected-device execution witness substrate differs from the requested substrate")
            witnessedEvidence <-
              ProductEvidence.attachDeviceExecutionWitness witness (trainedArtifactEvidence artifact)
            Right (Trained artifact {trainedArtifactEvidence = witnessedEvidence})

-- | Raw numerical attempt only. No MLP witness is queried, and no training
-- evidence, bar eligibility, checkpoint or producer authentication is minted.
-- Synchronous training exceptions retain no invented state/counters. A final
-- evaluation exception retains the already returned actual training result.
runRawTrainerObservationForPlan
  :: Substrate
  -> MlpDevice
  -> Maybe Text
  -> ProductBudget.CompiledRlPlan
  -> IO Observation.RawTrainerAttempt
runRawTrainerObservationForPlan substrate device atariRomPath plan = do
  attempted <-
    tryAny (executeRawTrainerObservation RetainBeforeEvaluation substrate device atariRomPath plan)
  pure $ case attempted of
    Left exception ->
      Observation.TrainerDidNotReturn (Observation.TrainingThrew (Text.pack (displayException exception)))
    Right (Left err) -> Observation.TrainerDidNotReturn (Observation.TrainingRejected err)
    Right (Right result) -> result

-- Private mode: only the raw path may retain a zero-update completed return.
-- Strict callers reject exactly where the old positive counter constructor ran.
data BeforeEvaluation = StrictBeforeEvaluation | RetainBeforeEvaluation

executeRawTrainerObservation
  :: BeforeEvaluation
  -> Substrate
  -> MlpDevice
  -> Maybe Text
  -> ProductBudget.CompiledRlPlan
  -> IO (Either Text Observation.RawTrainerAttempt)
executeRawTrainerObservation beforeEvaluation _substrate device atariRomPath plan
  | Text.toLower envName == "atari-subset" = do
      -- Atari routes through the runtime-loaded ALE adapter (Sprint 8.8),
      -- not the MLP device; ROM-policy failures surface as a typed `Left`.
      result <- ALE.runAtariSubsetEpisodes atariRomPath seed evalEpisodes maxStepsPerEpisode
      pure
        ( do
            episodes <- result
            let observedEpisodes = fmap fromAleEpisode episodes
            evaluationSet <- evaluationSetFromEpisodes evalEpisodes observedEpisodes
            Right (Observation.TrainerEvaluationOnly evaluationSet)
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
  knownMlpTrainers = Configuration.knownNeuralTrainerKinds
  dispatchMlpTrainer =
    case Configuration.resolveNeuralTrainerRecipe plan of
      Left err -> pure (Left err)
      Right recipe ->
        Configuration.foldNeuralTrainerRecipe
          onPolicyEpisodes
          dqnEpisodes
          qrDqnEpisodes
          continuousEpisodes
          herEpisodes
          recipe
  fromAleEpisode episode =
    EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = ALE.aleEpisodeIndex episode
      , EpisodeEnvelope.simEpisodeSteps = ALE.aleEpisodeSteps episode
      , EpisodeEnvelope.simEpisodeReward = ALE.aleEpisodeReward episode
      , EpisodeEnvelope.simEpisodeDone = ALE.aleEpisodeDone episode
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  -- Config resolution above is data-only; these original numerical and final
  -- evaluation bodies keep the same selected device and strict/raw ordering.
  onPolicyEpisodes variant simEnv config = do
    resultE <- PpoTrainer.trainOnPolicyOnDeviceWithEnvironmentRaw device simEnv variant config
    case resultE of
      Left err -> pure (Left err)
      Right result ->
        finishNumerical (Observation.ReturnedOnPolicy result) $ do
          evaluationE <-
            PpoTrainer.evaluateOnPolicyOnDeviceWithEnvironment
              device
              simEnv
              config
              (AlgorithmCommon.rawTrainerFinalParams result)
              evalEpisodes
          pure (fmap (Observation.EvaluationReturned . evaluationsToEpisodes) evaluationE)
  dqnEpisodes simEnv config = do
    resultE <- DqnTrainer.trainDqnOnDeviceWithEnvironmentRaw device simEnv config
    case resultE of
      Left err -> pure (Left err)
      Right result ->
        finishNumerical (Observation.ReturnedDqn result) $ do
          evaluationE <-
            DqnTrainer.evaluateDqnPolicyWithEnvironment
              device
              simEnv
              config
              (AlgorithmCommon.rawTrainerFinalParams result)
              evalEpisodes
          pure (fmap (Observation.EvaluationReturned . evaluationsToEpisodes) evaluationE)
  qrDqnEpisodes simEnv config = do
    resultE <- QrDqnTrainer.trainQrDqnOnDeviceWithEnvironmentRaw device simEnv config
    case resultE of
      Left err -> pure (Left err)
      Right result ->
        finishNumerical (Observation.ReturnedQrDqn result) $ do
          evaluationE <-
            QrDqnTrainer.evaluateQrDqnPolicyOnDeviceWithEnvironment
              device
              simEnv
              config
              (AlgorithmCommon.rawTrainerFinalParams result)
              evalEpisodes
          pure (fmap (Observation.EvaluationReturned . evaluationsToEpisodes) evaluationE)
  continuousEpisodes contEnv config = do
    resultE <- ContinuousTrainer.trainContinuousOnDeviceWithEnvironmentRaw device contEnv config
    case resultE of
      Left err -> pure (Left err)
      Right result ->
        finishNumerical (Observation.ReturnedContinuous result) $ do
          evaluationE <-
            ContinuousTrainer.evaluateContinuousPolicyOnDeviceWithEnvironment
              device
              contEnv
              config
              (AlgorithmCommon.rawTrainerFinalParams result)
              evalEpisodes
          pure (fmap (Observation.EvaluationReturned . evaluationsToEpisodes) evaluationE)
  arsEpisodes = do
    case RLSim.lookupSimulatedEnvironmentByName envName of
      Nothing -> pure (Left ("unknown discrete RL environment: " <> envName))
      Just simEnv@(RLSim.SomeSimulatedEnvironment environment) ->
        case scheduleMaybe of
          Just schedule@ProductBudget.ArsTrainingSchedule {} -> do
            let config =
                  arsExecutionConfig environment seed schedule
            result <- ArsTrainer.trainArsOnEnvironmentRaw simEnv config
            finishNumerical (Observation.ReturnedArs result) $
              pure (Right (arsFinalEvaluation simEnv config result evalEpisodes))
          _ -> pure (Left ("internal RL schedule kind mismatch for " <> trainerKind))
  herEpisodes config = do
    resultE <- HerTrainer.trainHerOnDeviceRaw device config
    case resultE of
      Left err -> pure (Left err)
      Right result ->
        finishNumerical (Observation.ReturnedHer result) $ do
          evaluationE <-
            HerTrainer.evaluateHerGreedyOnDevice
              device
              config
              (AlgorithmCommon.rawTrainerFinalParams result)
              evalEpisodes
              (seed + 104729)
          pure (fmap Observation.HerEvaluationReturned evaluationE)
  -- The strict path rejects raw zero counters before starting this action.
  -- The raw path retains failed evaluation together with genuine returned state.
  finishNumerical policy evaluatePolicy =
    case beforeEvaluation of
      StrictBeforeEvaluation -> do
        evaluated <- evaluateStrictTrainerReturn policy evaluatePolicy
        pure (fmap returned evaluated)
      RetainBeforeEvaluation -> do
        evaluated <- tryAny evaluatePolicy
        pure $ Right $ returned $ case evaluated of
          Left exception ->
            Observation.EvaluationFailed (Observation.EvaluationThrew (Text.pack (displayException exception)))
          Right (Left err) -> Observation.EvaluationFailed (Observation.EvaluationRejected err)
          Right (Right evaluation) -> evaluation
   where
    returned evaluation =
      Observation.TrainerReturned
        Observation.RawTrainerObservation
          { Observation.observedPlan = plan
          , Observation.observedPolicy = policy
          , Observation.observedEvaluation = evaluation
          }
{-# NOINLINE runTrainerEpisodesForPlan #-}

-- | Shared exact strict boundary, exposed for direct numerical callback
-- controls. This checks positive counters only; it grants no evidence or
-- producer authority. The dispatcher invokes it before final evaluator IO.
evaluateStrictTrainerReturn
  :: Observation.ReturnedPolicy -> IO (Either Text a) -> IO (Either Text a)
evaluateStrictTrainerReturn policy evaluatePolicy =
  case AlgorithmCommon.refineObservedTrainerCounters (Observation.returnedCounters policy) of
    Left err -> case policy of
      -- ARS's old lower IO entrypoint used fail on counter errors.
      Observation.ReturnedArs _ -> fail (Text.unpack err)
      _ -> pure (Left err)
    Right _ -> evaluatePolicy

herEvaluationEpisodes :: [(Bool, Double, Int)] -> [EpisodeEnvelope.SimulatedEpisode]
herEvaluationEpisodes evals =
  [ EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = i
      , EpisodeEnvelope.simEpisodeSteps = steps
      , EpisodeEnvelope.simEpisodeReward = 1.0 - normDist
      , EpisodeEnvelope.simEpisodeDone = reached
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  | (i, (reached, normDist, steps)) <- zip [0 ..] evals
  ]

-- | Reuse the existing strict numerical guards without executing another
-- evaluator. The supplied raw data and returned artifact establish no actual
-- producer, five-run qualification, authenticated parent or Store admission.
-- The native publication boundary must obtain its input from the actual opaque
-- cohort and separately retain/bind those observations before consuming this.
refineStrictRecordedTrainerObservation
  :: Substrate -> Observation.RawTrainerAttempt -> Either Text TrainerRun
refineStrictRecordedTrainerObservation = refineStrictObservation

refineStrictObservation :: Substrate -> Observation.RawTrainerAttempt -> Either Text TrainerRun
refineStrictObservation substrate attempt = case attempt of
  Observation.TrainerDidNotReturn failure -> case failure of
    Observation.TrainingRejected err -> Left err
    Observation.TrainingThrew err -> Left err
  Observation.TrainerEvaluationOnly evaluation -> Right (EvaluationOnly evaluation)
  Observation.TrainerReturned observed -> do
    episodes <- case Observation.observedEvaluation observed of
      Observation.EvaluationReturned values -> Right values
      Observation.HerEvaluationReturned values -> Right (herEvaluationEpisodes values)
      Observation.EvaluationFailed failure -> case failure of
        Observation.EvaluationRejected err -> Left err
        Observation.EvaluationThrew err -> Left err
    let plan = Observation.observedPlan observed
        policy = Observation.observedPolicy observed
        (metric, statistics) = Observation.returnedLearningStatistics policy
    evaluationSet <-
      evaluationSetFromEpisodes (ProductBudget.compiledRlEvaluationEpisodes plan) episodes
    learningCurve <- learningCurveFromStats metric statistics
    counters <- AlgorithmCommon.refineObservedTrainerCounters (Observation.returnedCounters policy)
    schedule <-
      maybe (Left "RL trained policy has no schedule") Right (ProductBudget.compiledRlSchedule plan)
    trainerRunWithEvidence
      substrate
      (ProductBudget.compiledRlTrainerKind plan)
      (ProductBudget.compiledRlEnvironment plan)
      (ProductBudget.compiledRlSeed plan)
      (ProductBudget.scheduleObservedEnvironmentSteps schedule)
      counters
      learningCurve
      evaluationSet
      (Observation.returnedInitialWeights policy)
      (Observation.returnedFinalWeights policy)

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

-- Shared recipe/evaluator only: old dispatch still owns its original call and
-- strict/raw ordering. The origin path supplies the actual prepared return.
arsExecutionConfig
  :: RLSim.SimulatedEnvironment state
  -> Int
  -> ProductBudget.RlTrainingSchedule
  -> ArsTrainer.ArsTrainConfig
arsExecutionConfig environment seed schedule =
  ArsTrainer.defaultArsTrainConfig
    { ArsTrainer.arsSeed = seed
    , ArsTrainer.arsIterations = ProductBudget.scheduleArsIterations schedule
    , ArsTrainer.arsNumDirections = ProductBudget.scheduleArsDirections schedule
    , ArsTrainer.arsMaxEpisodeSteps = ProductBudget.scheduleArsMaxEpisodeSteps schedule
    , ArsTrainer.arsActionCount = RLSim.envActionCount environment
    , ArsTrainer.arsObsSize = RLSim.envObservationSize environment
    }

arsFinalEvaluation
  :: RLSim.SomeSimulatedEnvironment
  -> ArsTrainer.ArsTrainConfig
  -> ArsTrainer.ArsTrainObservation
  -> Int
  -> Observation.RawEvaluation
arsFinalEvaluation simEnv config result evalEpisodes =
  Observation.EvaluationReturned
    ( evaluationsToEpisodes
        ( ArsTrainer.evaluateArsPolicyWithEnvironment
            simEnv
            config
            (AlgorithmCommon.rawTrainerFinalParams result)
            evalEpisodes
        )
    )

evaluationsToEpisodes
  :: [AlgorithmCommon.EvaluationEpisodeResult]
  -> [EpisodeEnvelope.SimulatedEpisode]
evaluationsToEpisodes evaluations =
  [ EpisodeEnvelope.SimulatedEpisode
      { EpisodeEnvelope.simEpisodeIndex = index
      , EpisodeEnvelope.simEpisodeSteps = AlgorithmCommon.evaluationEpisodeSteps evaluation
      , EpisodeEnvelope.simEpisodeReward = AlgorithmCommon.evaluationEpisodeReward evaluation
      , EpisodeEnvelope.simEpisodeDone = AlgorithmCommon.evaluationEpisodeTerminated evaluation
      , EpisodeEnvelope.simEpisodeFrames = []
      }
  | (index, evaluation) <- zip [0 ..] evaluations
  ]

-- BEGIN BOUNDED ACTUAL ARS SINGLETON ORIGIN
-- Inputs are supplied data, never proof of App receipt or parent authority.
-- A local source observation does not establish source-to-executable coherence.
data ArsProducerSourceInput
  = ObserveArsSourceRoot !FilePath
  | SuppliedArsParentSource !Source.SourceStamp
  deriving stock (Eq, Show)

data ArsProducerSourceCoverage
  = ObservedArsLocalSource !FilePath !Source.SourceStamp
  | UnauthenticatedArsSuppliedParentSource !Source.SourceStamp
  deriving stock (Eq, Show)

data ArsAttemptStage
  = ArsBeforeProcess
  | ArsSuppliedContext
  | ArsNonce
  | ArsPreparation
  | ArsTraining
  | ArsRawReturnForcing
  | ArsCounters
  | ArsEvaluation
  | ArsTraceValidation
  | ArsAfterProcess
  | ArsStrictRefinement
  deriving stock (Eq, Show)

data ArsAttemptFailure = ArsAttemptFailure !ArsAttemptStage !Text
  deriving stock (Eq, Show)

-- No constructors/field labels/Read/Generic/codecs for input, attempt or origin.
-- The whole RunPlan (including subject/artifact/topic) is SUPPLIED bound
-- context. Its numeric seed/lane/budget must match the compiled recipe; this
-- lower module cannot establish Matrix semantic descriptor correspondence.
-- Higher consumption MUST compare the whole canonical Matrix projection AND
-- derive/check the exact compiled recipe. A same-budget text substitution
-- can be retained here but can never establish canonical product eligibility.
-- The prepared capability is created and consumed privately by the real runner.
data ArsBoundExecutionInput
  = ArsBoundExecutionInput
      (Plan.RunPlan 'Plan.ReinforcementLearning)
      ProductBudget.CompiledRlPlan
      Text
      Substrate
      (Maybe TrainingBudget.ProductScenarioInvocation)
      ArsProducerSourceInput
      RLSim.SomeSimulatedEnvironment
      ArsTrainer.ArsTrainConfig

data ArsProductAttempt
  = ArsProductAttempt
      (Maybe ArsTrainer.ArsTrainObservation)
      (Maybe Observation.RawEvaluation)
      (Maybe ArsAttemptFailure)
      (Either Text TrainerRun)
      (Maybe ProducedArsHostExecution)
      (Maybe ArsTrainer.ArsPreparedSnapshot)

data ProducedArsHostExecution
  = ProducedArsHostExecution
      ArsBoundExecutionInput
      ArsProducerSourceCoverage
      Text
      ArsTrace.ArsHostTrace
      ArsReference.ArsHostReference
      Producer.ObservedProducerProcess
      Producer.ObservedProducerProcess
      Observation.RawEvaluation
      ArsTrainer.ArsPreparedSnapshot

arsBoundInputRunPlan :: ArsBoundExecutionInput -> Plan.RunPlan 'Plan.ReinforcementLearning
arsBoundInputRunPlan (ArsBoundExecutionInput plan _ _ _ _ _ _ _) = plan
arsBoundInputCompiledPlan :: ArsBoundExecutionInput -> ProductBudget.CompiledRlPlan
arsBoundInputCompiledPlan (ArsBoundExecutionInput _ plan _ _ _ _ _ _) = plan
arsBoundInputRowId :: ArsBoundExecutionInput -> Text
arsBoundInputRowId (ArsBoundExecutionInput _ _ row _ _ _ _ _) = row
arsBoundInputSubstrate :: ArsBoundExecutionInput -> Substrate
arsBoundInputSubstrate (ArsBoundExecutionInput _ _ _ lane _ _ _ _) = lane
arsBoundInputSuppliedInvocation
  :: ArsBoundExecutionInput -> Maybe TrainingBudget.ProductScenarioInvocation
arsBoundInputSuppliedInvocation (ArsBoundExecutionInput _ _ _ _ invocation _ _ _) = invocation
arsBoundInputSourceInput :: ArsBoundExecutionInput -> ArsProducerSourceInput
arsBoundInputSourceInput (ArsBoundExecutionInput _ _ _ _ _ source _ _) = source

arsProductAttemptRawReturn :: ArsProductAttempt -> Maybe ArsTrainer.ArsTrainObservation
arsProductAttemptRawReturn (ArsProductAttempt raw _ _ _ _ _) = raw
arsProductAttemptEvaluation :: ArsProductAttempt -> Maybe Observation.RawEvaluation
arsProductAttemptEvaluation (ArsProductAttempt _ evaluation _ _ _ _) = evaluation
arsProductAttemptFailure :: ArsProductAttempt -> Maybe ArsAttemptFailure
arsProductAttemptFailure (ArsProductAttempt _ _ failure _ _ _) = failure
arsProductAttemptStrictResult :: ArsProductAttempt -> Either Text TrainerRun
arsProductAttemptStrictResult (ArsProductAttempt _ _ _ strict _ _) = strict
arsProductAttemptOrigin :: ArsProductAttempt -> Maybe ProducedArsHostExecution
arsProductAttemptOrigin (ArsProductAttempt _ _ _ _ origin _) = origin

-- | Supplied bound context, not a proof that its subject/artifact/topic is the
-- canonical semantic descriptor for the actual compiled ARS recipe.
producedArsHostRunPlan :: ProducedArsHostExecution -> Plan.RunPlan 'Plan.ReinforcementLearning
producedArsHostRunPlan (ProducedArsHostExecution input _ _ _ _ _ _ _ _) = arsBoundInputRunPlan input

producedArsHostCompiledPlan :: ProducedArsHostExecution -> ProductBudget.CompiledRlPlan
producedArsHostCompiledPlan (ProducedArsHostExecution input _ _ _ _ _ _ _ _) = arsBoundInputCompiledPlan input
producedArsHostRowId :: ProducedArsHostExecution -> Text
producedArsHostRowId (ProducedArsHostExecution input _ _ _ _ _ _ _ _) = arsBoundInputRowId input
producedArsHostSubstrate :: ProducedArsHostExecution -> Substrate
producedArsHostSubstrate (ProducedArsHostExecution input _ _ _ _ _ _ _ _) = arsBoundInputSubstrate input
producedArsHostSuppliedInvocation
  :: ProducedArsHostExecution -> Maybe TrainingBudget.ProductScenarioInvocation
producedArsHostSuppliedInvocation (ProducedArsHostExecution input _ _ _ _ _ _ _ _) = arsBoundInputSuppliedInvocation input
producedArsHostSourceCoverage :: ProducedArsHostExecution -> ArsProducerSourceCoverage
producedArsHostSourceCoverage (ProducedArsHostExecution _ source _ _ _ _ _ _ _) = source
producedArsHostAttemptId :: ProducedArsHostExecution -> Text
producedArsHostAttemptId (ProducedArsHostExecution _ _ attempt _ _ _ _ _ _) = attempt
producedArsHostTrace :: ProducedArsHostExecution -> ArsTrace.ArsHostTrace
producedArsHostTrace (ProducedArsHostExecution _ _ _ trace _ _ _ _ _) = trace
producedArsHostReference :: ProducedArsHostExecution -> ArsReference.ArsHostReference
producedArsHostReference (ProducedArsHostExecution _ _ _ _ reference _ _ _ _) = reference
producedArsHostBeforeProcess
  , producedArsHostAfterProcess
    :: ProducedArsHostExecution -> Producer.ObservedProducerProcess
producedArsHostBeforeProcess (ProducedArsHostExecution _ _ _ _ _ before _ _ _) = before
producedArsHostAfterProcess (ProducedArsHostExecution _ _ _ _ _ _ after _ _) = after
producedArsHostEvaluation :: ProducedArsHostExecution -> Observation.RawEvaluation
producedArsHostEvaluation (ProducedArsHostExecution _ _ _ _ _ _ _ evaluation _) = evaluation

prepareArsBoundExecutionInput
  :: Text
  -> Plan.RunPlan 'Plan.ReinforcementLearning
  -> ProductBudget.CompiledRlPlan
  -> Substrate
  -> Maybe TrainingBudget.ProductScenarioInvocation
  -> ArsProducerSourceInput
  -> Either Text ArsBoundExecutionInput
prepareArsBoundExecutionInput row run compiled lane invocation source = do
  reparsed <-
    ProductBudget.parseCompiledRlPlanTransport (ProductBudget.renderCompiledRlPlanTransport compiled)
  requireArsInput
    (reparsed == compiled)
    "ARS supplied compiled plan differs from its public compiler projection"
  requireArsInput
    (ProductBudget.compiledRlTrainerKind compiled == "ars")
    "ARS product input trainer is not ARS"
  let environmentName = ProductBudget.compiledRlEnvironment compiled
      seed = ProductBudget.compiledRlSeed compiled
  requireArsInput
    ( row == "ARS/" <> environmentName
        && row `elem` ["ARS/cartpole", "ARS/mountain-car", "ARS/lunar-lander", "ARS/key-door-grid"]
    )
    "ARS product input row differs from the supported compiled environment"
  schedule <- case ProductBudget.compiledRlSchedule compiled of
    Just value@ProductBudget.ArsTrainingSchedule {} -> Right value
    _ -> Left "ARS product input has no ARS schedule"
  simEnv <-
    maybe
      (Left "ARS product input environment is unavailable")
      Right
      (RLSim.lookupSimulatedEnvironmentByName environmentName)
  let config = case simEnv of
        RLSim.SomeSimulatedEnvironment environment -> arsExecutionConfig environment seed schedule
      (transitions, ticks, vectors, horizon, evaluations) = Plan.runPlanRlBudget run
  ArsTrace.validateArsHostConfigForPlan compiled config
  requireArsInput
    ( ProductBudget.compiledRlEvaluationEpisodes compiled >= 1
        && ProductBudget.compiledRlEvaluationEpisodes compiled
          <= ProductBudget.productRlDefaultEvaluationEpisodes
    )
    "ARS singleton origin evaluation count exceeds its 1..20 resource scope"
  requireArsInput (Plan.runPlanSubstrate run == lane) "ARS product input lane differs"
  requireArsInput
    (seed >= 0 && NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds run)) == [fromIntegral seed])
    "ARS product input singleton seed differs"
  requireArsInput
    (Plan.quantityValue transitions == ProductBudget.scheduleObservedEnvironmentSteps schedule)
    "ARS product input transition budget differs"
  requireArsInput
    (toInteger (Plan.quantityValue ticks) == toInteger (ArsTrainer.arsMaxEpisodeSteps config))
    "ARS product input rollout ticks differ"
  requireArsInput (Plan.quantityValue vectors == 1) "ARS product input vector width differs"
  requireArsInput
    (toInteger (Plan.quantityValue horizon) == toInteger (ArsTrainer.arsMaxEpisodeSteps config))
    "ARS product input horizon differs"
  requireArsInput
    ( toInteger (Plan.quantityValue evaluations)
        == toInteger (ProductBudget.compiledRlEvaluationEpisodes compiled)
    )
    "ARS product input evaluation count differs"
  _ <- ArsReference.arsHostObjectKey (Plan.runPlanExperimentId run) (Text.replicate 64 "0")
  case invocation of
    Nothing -> case source of
      SuppliedArsParentSource _ -> Left "ARS supplied parent source requires a supplied scenario invocation"
      ObserveArsSourceRoot _ -> Right ()
    Just supplied -> do
      roundtripped <-
        TrainingBudget.parseProductScenarioInvocation
          (TrainingBudget.renderProductScenarioInvocation supplied)
      requireArsInput (roundtripped == supplied) "ARS supplied invocation is not canonical"
      requireArsInput
        (TrainingBudget.productScenarioInvocationRowId supplied == row)
        "ARS supplied invocation row differs"
      requireArsInput
        (TrainingBudget.productScenarioInvocationPlanId supplied == Plan.runPlanId run)
        "ARS supplied invocation plan differs; auxiliary child association is unsupported"
      requireArsInput
        (TrainingBudget.productScenarioInvocationSubstrate supplied == lane)
        "ARS supplied invocation lane differs"
  case source of
    ObserveArsSourceRoot _ -> Right ()
    SuppliedArsParentSource stamp -> do
      requireArsInput
        (Source.stampAlgorithm stamp == Source.sourceDigestAlgorithm)
        "ARS supplied source algorithm is unsupported"
      requireArsInput
        (canonicalArsSha (Source.stampSha256 stamp))
        "ARS supplied source SHA is not canonical"
  pure (ArsBoundExecutionInput run compiled row lane invocation source simEnv config)

requireArsInput :: Bool -> Text -> Either Text ()
requireArsInput True _ = Right ()
requireArsInput False detail = Left detail

canonicalArsSha :: Text -> Bool
canonicalArsSha value = Text.length value == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) value

-- Every invocation supplied through this API is caller data. No public input
-- claims that an App actually received it, or that a parent authenticated it.
-- The sole origin constructor is below the actual one-shot numerical return,
-- single final evaluation, same-runtime trace replay and real process checks.
-- BEGIN ACTUAL ARS SINGLE-USE DURABILITY STAGES
-- These capabilities enable real higher barriers on the SAME execution. No
-- stage callback, acknowledged-write boolean, raw restore or origin factory is
-- accepted. A capability alone makes no remote durability/canonical claim.
data BegunArsProductAttempt
  = BegunArsProductAttempt
      ArsBoundExecutionInput
      ArsProducerSourceCoverage
      Text
      Producer.ObservedProducerProcess
      SingleUse.SingleUse

data PreparedArsProductAttempt
  = PreparedArsProductAttempt
      BegunArsProductAttempt
      ArsTrainer.PreparedArsTraining
      ArsTrainer.ArsPreparedSnapshot
      SingleUse.SingleUse

data PendingArsProductReturn
  = PendingArsProductReturn
      PreparedArsProductAttempt
      (Maybe ArsTrainer.ArsTrainObservation)
      (Maybe ArsAttemptFailure)
      SingleUse.SingleUse

begunArsInput :: BegunArsProductAttempt -> ArsBoundExecutionInput
begunArsInput (BegunArsProductAttempt input _ _ _ _) = input
begunArsAttemptId :: BegunArsProductAttempt -> Text
begunArsAttemptId (BegunArsProductAttempt _ _ attempt _ _) = attempt
begunArsBeforeProcess :: BegunArsProductAttempt -> Producer.ObservedProducerProcess
begunArsBeforeProcess (BegunArsProductAttempt _ _ _ observed _) = observed
begunArsSourceCoverage :: BegunArsProductAttempt -> ArsProducerSourceCoverage
begunArsSourceCoverage (BegunArsProductAttempt _ coverage _ _ _) = coverage

preparedArsProductInput :: PreparedArsProductAttempt -> ArsBoundExecutionInput
preparedArsProductInput (PreparedArsProductAttempt begun _ _ _) = begunArsInput begun
preparedArsProductAttemptId :: PreparedArsProductAttempt -> Text
preparedArsProductAttemptId (PreparedArsProductAttempt begun _ _ _) = begunArsAttemptId begun
preparedArsProductSnapshot :: PreparedArsProductAttempt -> ArsTrainer.ArsPreparedSnapshot
preparedArsProductSnapshot (PreparedArsProductAttempt _ _ snapshot _) = snapshot

pendingArsProductInput :: PendingArsProductReturn -> ArsBoundExecutionInput
pendingArsProductInput (PendingArsProductReturn prepared _ _ _) = preparedArsProductInput prepared
pendingArsProductAttemptId :: PendingArsProductReturn -> Text
pendingArsProductAttemptId (PendingArsProductReturn prepared _ _ _) = preparedArsProductAttemptId prepared
pendingArsPreparedSnapshot :: PendingArsProductReturn -> ArsTrainer.ArsPreparedSnapshot
pendingArsPreparedSnapshot (PendingArsProductReturn prepared _ _ _) = preparedArsProductSnapshot prepared
pendingArsRawReturn :: PendingArsProductReturn -> Maybe ArsTrainer.ArsTrainObservation
pendingArsRawReturn (PendingArsProductReturn _ raw _ _) = raw
pendingArsReturnFailure :: PendingArsProductReturn -> Maybe ArsAttemptFailure
pendingArsReturnFailure (PendingArsProductReturn _ _ failure _) = failure

-- Actual pre-cap failure reports diagnostic/input only; it does not promise an
-- unavailable partial observation when, for example, the nonce read fails.
-- No trainer initializer/rollout/evaluator is called by begin.
beginArsProductAttempt
  :: ArsBoundExecutionInput -> IO (Either ArsAttemptFailure BegunArsProductAttempt)
beginArsProductAttempt input = do
  let source = arsBoundInputSourceInput input
  beforeE <- arsAt ArsBeforeProcess (actualProcess source)
  case beforeE of
    Left failure -> pure (Left failure)
    Right before -> do
      contextE <-
        arsAt ArsSuppliedContext $
          pure
            ( actualSourceCoverage source before
                >>= validateSuppliedExecutable (arsBoundInputSuppliedInvocation input) before
            )
      case contextE of
        Left failure -> pure (Left failure)
        Right coverage -> arsAt ArsNonce $ do
          nonceE <- actualArsAttemptId
          case nonceE of
            Left detail -> pure (Left detail)
            Right attempt ->
              Right . BegunArsProductAttempt input coverage attempt before <$> SingleUse.newSingleUse

prepareBegunArsProductAttempt
  :: BegunArsProductAttempt -> IO (Either ArsAttemptFailure PreparedArsProductAttempt)
prepareBegunArsProductAttempt begun@(BegunArsProductAttempt input _ _ _ token) = do
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (Left (ArsAttemptFailure ArsPreparation "ARS begun preparation was already consumed"))
    else arsAt ArsPreparation $ do
      let ArsBoundExecutionInput _ _ _ _ _ _ simEnv config = input
      actualPrepared <- ArsTrainer.prepareArsOnEnvironment simEnv config
      let snapshot = ArsTrainer.preparedArsSnapshot actualPrepared
      Right . PreparedArsProductAttempt begun actualPrepared snapshot <$> SingleUse.newSingleUse

-- Run returns uncensored actual data before strict counters/final evaluation.
-- A genuine training/forcing failure is an opaque pending return with its
-- actual available snapshot/raw, never a made-up numerical result.
runPreparedArsProductAttempt
  :: PreparedArsProductAttempt -> IO (Either ArsAttemptFailure PendingArsProductReturn)
runPreparedArsProductAttempt prepared@(PreparedArsProductAttempt _ actualPrepared _ token) = do
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (Left (ArsAttemptFailure ArsTraining "ARS prepared run was already consumed"))
    else do
      returnedE <- arsAt ArsTraining (ArsTrainer.continuePreparedArsRaw actualPrepared)
      case returnedE of
        Left failure -> pending Nothing (Just failure)
        Right raw -> do
          forcedE <- arsAt ArsRawReturnForcing $ do
            -- Force returned fields only, with no validity/learning/counter
            -- refinement or extra rollout/evaluator. Actual values stay raw.
            _ <- evaluate (length (show raw))
            pure (Right ())
          pending (Just raw) (either Just (const Nothing) forcedE)
 where
  pending raw failure =
    Right . PendingArsProductReturn prepared raw failure <$> SingleUse.newSingleUse

finishArsProductAttempt
  :: PendingArsProductReturn -> IO (Either ArsAttemptFailure ArsProductAttempt)
finishArsProductAttempt pending@(PendingArsProductReturn prepared raw failure token) = do
  claimed <- SingleUse.tryConsumeSingleUse token
  if not claimed
    then pure (Left (ArsAttemptFailure ArsEvaluation "ARS pending finish was already consumed"))
    else case failure of
      Just actualFailure -> pure (Right (arsFailedWithSnapshot raw Nothing actualFailure (Just snapshot)))
      Nothing -> case raw of
        Nothing ->
          pure
            ( Right
                ( arsFailedWithSnapshot
                    Nothing
                    Nothing
                    (ArsAttemptFailure ArsTraining "ARS actual pending return has no numerical result")
                    (Just snapshot)
                )
            )
        Just actualRaw -> Right <$> finishActualArsReturn pending actualRaw
 where
  snapshot = preparedArsProductSnapshot prepared

-- The same staged functions, never a parallel numerical implementation.
runArsProductAttempt :: ArsBoundExecutionInput -> IO ArsProductAttempt
runArsProductAttempt input = do
  begunE <- beginArsProductAttempt input
  case begunE of
    Left failure -> pure (arsFailed Nothing Nothing failure)
    Right begun -> do
      preparedE <- prepareBegunArsProductAttempt begun
      case preparedE of
        Left failure -> pure (arsFailed Nothing Nothing failure)
        Right prepared -> do
          returnedE <- runPreparedArsProductAttempt prepared
          case returnedE of
            Left failure ->
              pure (arsFailedWithSnapshot Nothing Nothing failure (Just (preparedArsProductSnapshot prepared)))
            Right pending -> do
              finishedE <- finishArsProductAttempt pending
              pure $ case finishedE of
                Left failure ->
                  arsFailedWithSnapshot
                    (pendingArsRawReturn pending)
                    Nothing
                    failure
                    (Just (pendingArsPreparedSnapshot pending))
                Right actual -> actual

-- The raw value can reach this private constructor route only through the
-- privately constructed/consumed Pending capability above, never a public DTO.
finishActualArsReturn
  :: PendingArsProductReturn -> ArsTrainer.ArsTrainObservation -> IO ArsProductAttempt
finishActualArsReturn (PendingArsProductReturn prepared _ _ _) raw = do
  countersE <-
    arsAt
      ArsCounters
      (evaluateStrictTrainerReturn (Observation.ReturnedArs raw) (pure (Right ())))
  case countersE of
    Left failure -> pure (failed Nothing failure)
    Right () -> do
      evaluatedE <- arsAt ArsEvaluation $ do
        let evaluation = arsFinalEvaluation simEnv config raw (ProductBudget.compiledRlEvaluationEpisodes compiled)
        forceArsEvaluation evaluation
        pure (Right evaluation)
      case evaluatedE of
        Left failure ->
          let evaluation = Observation.EvaluationFailed (Observation.EvaluationThrew (arsFailureDetail failure))
           in pure (failed (Just evaluation) failure)
        Right evaluation -> do
          traceE <- arsAt ArsTraceValidation $ do
            let checked = do
                  requireArsInput
                    (AlgorithmCommon.rawTrainerConfig raw == ArsTrainer.arsPreparedConfig snapshot)
                    "ARS actual returned config differs from the prepared snapshot"
                  requireArsInput
                    ( Checkpoint.encodeJmw1 (Observation.returnedInitialWeights (Observation.ReturnedArs raw))
                        == Checkpoint.encodeJmw1 (VU.toList (ArsTrainer.arsPreparedInitialParams snapshot))
                    )
                    "ARS actual returned initial weights differ from the prepared snapshot"
                  buildActualArsTrace input before coverage attemptId raw
            case checked of
              Left detail -> pure (Left detail)
              Right (trace, reference) -> do
                _ <- evaluate (Data.ByteString.length (ArsTrace.encodeArsHostTrace trace))
                pure (Right (trace, reference))
          case traceE of
            Left failure -> pure (failed (Just evaluation) failure)
            Right (trace, reference) -> do
              afterE <- arsAt ArsAfterProcess (actualProcess source)
              case afterE of
                Left failure -> pure (failed (Just evaluation) failure)
                Right after -> case Producer.compareProducerProcessObservations before after of
                  Left mismatch ->
                    pure
                      ( failed
                          (Just evaluation)
                          (ArsAttemptFailure ArsAfterProcess (Text.pack (show mismatch)))
                      )
                  Right () -> do
                    let origin =
                          ProducedArsHostExecution input coverage attemptId trace reference before after evaluation snapshot
                        observed =
                          Observation.TrainerReturned
                            (Observation.RawTrainerObservation compiled (Observation.ReturnedArs raw) evaluation)
                    strictE <- arsAt ArsStrictRefinement $ do
                      let strict = refineStrictObservation lane observed >>= attachActualArsReference reference
                      _ <- evaluate (length (show strict))
                      pure (Right strict)
                    pure $ case strictE of
                      Left failure ->
                        ArsProductAttempt
                          (Just raw)
                          (Just evaluation)
                          (Just failure)
                          (Left (arsFailureDetail failure))
                          (Just origin)
                          (Just snapshot)
                      Right strict ->
                        ArsProductAttempt
                          (Just raw)
                          (Just evaluation)
                          (either (Just . ArsAttemptFailure ArsStrictRefinement) (const Nothing) strict)
                          strict
                          (Just origin)
                          (Just snapshot)
 where
  PreparedArsProductAttempt (BegunArsProductAttempt input coverage attemptId before _) _ snapshot _ = prepared
  ArsBoundExecutionInput _ compiled _ lane _ source simEnv config = input
  failed evaluation failure = arsFailedWithSnapshot (Just raw) evaluation failure (Just snapshot)

-- END ACTUAL ARS SINGLE-USE DURABILITY STAGES

actualProcess :: ArsProducerSourceInput -> IO (Either Text Producer.ObservedProducerProcess)
actualProcess source = do
  observed <- Producer.observeProducerProcess $ case source of
    ObserveArsSourceRoot root -> Producer.ObserveSourceAt root
    SuppliedArsParentSource _ -> Producer.NoSourceObservation
  pure (first (Text.pack . show) observed)

actualSourceCoverage
  :: ArsProducerSourceInput
  -> Producer.ObservedProducerProcess
  -> Either Text ArsProducerSourceCoverage
actualSourceCoverage source observed = case source of
  ObserveArsSourceRoot root -> case Producer.producerObservedSource observed of
    Just (actualRoot, stamp) | actualRoot == root -> Right (ObservedArsLocalSource root stamp)
    _ -> Left "ARS actual local source observation is absent"
  SuppliedArsParentSource stamp -> do
    requireArsInput
      (isNothing (Producer.producerObservedSource observed))
      "ARS supplied parent source was incorrectly relabelled as locally observed"
    pure (UnauthenticatedArsSuppliedParentSource stamp)

validateSuppliedExecutable
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> Producer.ObservedProducerProcess
  -> ArsProducerSourceCoverage
  -> Either Text ArsProducerSourceCoverage
validateSuppliedExecutable Nothing _ coverage = Right coverage
validateSuppliedExecutable (Just supplied) observed coverage = do
  requireArsInput
    ( TrainingBudget.productScenarioInvocationExecutableSha256 supplied
        == Producer.producerExecutableFileSha256 observed
    )
    "ARS supplied invocation executable differs from actual process FILE observation"
  pure coverage

-- OS entropy is independent of the trainer's StdGen. No clock/PID/installed-CLI
-- fallback supplies a nominal nonce; absent/short entropy is an actual failure.
actualArsAttemptId :: IO (Either Text Text)
actualArsAttemptId = withBinaryFile "/dev/urandom" ReadMode $ \handle -> do
  bytes <- Data.ByteString.hGet handle 32
  pure $
    if Data.ByteString.length bytes == 32
      then Right (hashBytes bytes)
      else Left "ARS actual OS nonce read was short"

buildActualArsTrace
  :: ArsBoundExecutionInput
  -> Producer.ObservedProducerProcess
  -> ArsProducerSourceCoverage
  -> Text
  -> ArsTrainer.ArsTrainObservation
  -> Either Text (ArsTrace.ArsHostTrace, ArsReference.ArsHostReference)
buildActualArsTrace input@(ArsBoundExecutionInput run compiled row lane invocation _ _ _) before coverage attemptId raw = do
  let stamp = case coverage of
        ObservedArsLocalSource _ value -> value
        UnauthenticatedArsSuppliedParentSource value -> value
      context =
        ArsTrace.RawArsHostContext
          { ArsTrace.rawArsHostRowId = row
          , ArsTrace.rawArsHostExperiment = Plan.runPlanExperimentId run
          , ArsTrace.rawArsHostPlanId = Plan.planIdText (Plan.runPlanId run)
          , ArsTrace.rawArsHostCompiledTransport = ProductBudget.renderCompiledRlPlanTransport compiled
          , ArsTrace.rawArsHostLane = renderSubstrate lane
          , ArsTrace.rawArsHostSourceSha256 = Source.stampSha256 stamp
          , ArsTrace.rawArsHostExecutableSha256 = Producer.producerExecutableFileSha256 before
          , ArsTrace.rawArsHostInvocationSha256 =
              maybe
                (directArsInvocationDigest input before coverage attemptId)
                TrainingBudget.productScenarioInvocationDigest
                invocation
          , ArsTrace.rawArsHostExecutionBinding =
              maybe "direct-local-attempt-v1" (const "product-scenario-invocation-v1") invocation
          , ArsTrace.rawArsHostKernelOS = Producer.producerKernelOperatingSystem before
          , ArsTrace.rawArsHostKernelMachine = Producer.producerKernelMachine before
          , ArsTrace.rawArsHostKernelRelease = Producer.producerKernelRelease before
          , ArsTrace.rawArsHostSimulatorContract =
              "jitml-known-discrete-simulator-ars-v1:" <> ProductBudget.compiledRlEnvironment compiled
          , ArsTrace.rawArsHostProcessId = Text.pack (show (Producer.producerProcessId before))
          , ArsTrace.rawArsHostAttemptId = attemptId
          }
  trace <-
    ArsTrace.refineArsHostTrace
      (ArsTrace.RawArsHostTrace context ArsTrainer.arsNativeNumericalRuntime raw)
  ArsTrace.validateArsHostTracePlan compiled trace
  ArsTrace.validateArsHostTraceLocal trace
  reference <- ArsTrace.arsHostTraceRecordedReference trace
  ArsTrace.validateArsHostTraceReference reference trace
  pure (trace, reference)

attachActualArsReference :: ArsReference.ArsHostReference -> TrainerRun -> Either Text TrainerRun
attachActualArsReference reference run = case run of
  EvaluationOnly _ -> Left "ARS actual training cannot produce evaluation-only evidence"
  Trained artifact -> do
    evidence <-
      ProductEvidence.attachRecordedArsHostReference reference (trainedArtifactEvidence artifact)
    pure (Trained artifact {trainedArtifactEvidence = evidence})

forceArsEvaluation :: Observation.RawEvaluation -> IO ()
forceArsEvaluation evaluation = do
  _ <- evaluate (length (show evaluation))
  pure ()

-- | Data-only probe of the same production synchronous-stage catcher. The
-- unit result cannot manufacture a stage capability, origin or durable receipt.
observeArsStageFailureBoundary
  :: ArsAttemptStage -> IO (Either Text ()) -> IO (Either ArsAttemptFailure ())
observeArsStageFailureBoundary = arsAt

arsAt :: ArsAttemptStage -> IO (Either Text value) -> IO (Either ArsAttemptFailure value)
arsAt stage action = do
  attempted <- tryAny $ do
    result <- action
    outer <- evaluate result
    case outer of
      Left detail -> do
        _ <- evaluate (Text.length detail)
        pure (Left detail)
      Right value -> pure (Right value)
  pure $ case attempted of
    Left exception -> Left (ArsAttemptFailure stage (Text.pack (displayException exception)))
    Right result -> first (ArsAttemptFailure stage) result

arsFailed
  :: Maybe ArsTrainer.ArsTrainObservation
  -> Maybe Observation.RawEvaluation
  -> ArsAttemptFailure
  -> ArsProductAttempt
arsFailed raw evaluation failure = arsFailedWithSnapshot raw evaluation failure Nothing

arsFailedWithSnapshot
  :: Maybe ArsTrainer.ArsTrainObservation
  -> Maybe Observation.RawEvaluation
  -> ArsAttemptFailure
  -> Maybe ArsTrainer.ArsPreparedSnapshot
  -> ArsProductAttempt
arsFailedWithSnapshot raw evaluation failure =
  ArsProductAttempt raw evaluation (Just failure) (Left (arsFailureDetail failure)) Nothing

arsProductAttemptPreparedSnapshot :: ArsProductAttempt -> Maybe ArsTrainer.ArsPreparedSnapshot
arsProductAttemptPreparedSnapshot (ArsProductAttempt _ _ _ _ _ snapshot) = snapshot

producedArsHostPreparedSnapshot :: ProducedArsHostExecution -> ArsTrainer.ArsPreparedSnapshot
producedArsHostPreparedSnapshot (ProducedArsHostExecution _ _ _ _ _ _ _ _ snapshot) = snapshot

-- This digest scopes an actual OS nonce to actual/supplied bound context. It
-- accepts no caller hash and includes no future trace/manifest hash cycle.
-- The existing lower recorded context codec and both tags remain unchanged.
directArsInvocationDigest
  :: ArsBoundExecutionInput
  -> Producer.ObservedProducerProcess
  -> ArsProducerSourceCoverage
  -> Text
  -> Text
directArsInvocationDigest input before coverage attemptId =
  hashBytes
    ( Text.Encoding.encodeUtf8
        ( Text.concat
            ( fmap
                field
                [ "jitml-ars-direct-invocation-context-v1"
                , attemptId
                , Plan.planIdText (Plan.runPlanId (arsBoundInputRunPlan input))
                , ProductBudget.renderCompiledRlPlanTransport (arsBoundInputCompiledPlan input)
                , arsBoundInputRowId input
                , renderSubstrate (arsBoundInputSubstrate input)
                , Text.pack (show (Source.stampAlgorithm stamp))
                , Source.stampSha256 stamp
                , Producer.producerExecutableFileSha256 before
                ]
            )
        )
    )
 where
  stamp = case coverage of
    ObservedArsLocalSource _ value -> value
    UnauthenticatedArsSuppliedParentSource value -> value
  field value = Text.pack (show (Text.length value)) <> ":" <> value

arsFailureDetail :: ArsAttemptFailure -> Text
arsFailureDetail (ArsAttemptFailure _ detail) = detail

-- END BOUNDED ACTUAL ARS SINGLETON ORIGIN

-- BEGIN ACTUAL GENERIC ARS HOST EXECUTION

-- Separate actual singleton origin, never a ProductRow/qualification capsule.
-- There is no constructor/decoder/callback route to either opaque type.
data GenericArsAttempt
  = GenericArsAttempt
      !(Maybe ArsTrainer.ArsTrainObservation)
      !(Maybe Observation.RawEvaluation)
      !(Maybe ArsAttemptFailure)
      !(Either Text TrainerRun)
      !(Maybe ProducedGenericArsHostExecution)

data ProducedGenericArsHostExecution
  = ProducedGenericArsHostExecution
      !ProductBudget.CompiledRlPlan
      !Text
      !ArsTrace.ArsHostTrace
      !ArsReference.ArsHostReference
      !Producer.ObservedProducerProcess
      !Producer.ObservedProducerProcess

genericArsAttemptRawReturn :: GenericArsAttempt -> Maybe ArsTrainer.ArsTrainObservation
genericArsAttemptRawReturn (GenericArsAttempt raw _ _ _ _) = raw
genericArsAttemptEvaluation :: GenericArsAttempt -> Maybe Observation.RawEvaluation
genericArsAttemptEvaluation (GenericArsAttempt _ evaluation _ _ _) = evaluation
genericArsAttemptFailure :: GenericArsAttempt -> Maybe ArsAttemptFailure
genericArsAttemptFailure (GenericArsAttempt _ _ failure _ _) = failure
genericArsAttemptStrictResult :: GenericArsAttempt -> Either Text TrainerRun
genericArsAttemptStrictResult (GenericArsAttempt _ _ _ strict _) = strict
genericArsAttemptOrigin :: GenericArsAttempt -> Maybe ProducedGenericArsHostExecution
genericArsAttemptOrigin (GenericArsAttempt _ _ _ _ origin) = origin

producedGenericArsHostCompiledPlan
  :: ProducedGenericArsHostExecution -> ProductBudget.CompiledRlPlan
producedGenericArsHostCompiledPlan (ProducedGenericArsHostExecution plan _ _ _ _ _) = plan
producedGenericArsHostExperiment :: ProducedGenericArsHostExecution -> Text
producedGenericArsHostExperiment (ProducedGenericArsHostExecution _ experiment _ _ _ _) = experiment
producedGenericArsHostTrace :: ProducedGenericArsHostExecution -> ArsTrace.ArsHostTrace
producedGenericArsHostTrace (ProducedGenericArsHostExecution _ _ trace _ _ _) = trace
producedGenericArsHostReference :: ProducedGenericArsHostExecution -> ArsReference.ArsHostReference
producedGenericArsHostReference (ProducedGenericArsHostExecution _ _ _ reference _ _) = reference
producedGenericArsHostBeforeProcess
  , producedGenericArsHostAfterProcess
    :: ProducedGenericArsHostExecution -> Producer.ObservedProducerProcess
producedGenericArsHostBeforeProcess (ProducedGenericArsHostExecution _ _ _ _ before _) = before
producedGenericArsHostAfterProcess (ProducedGenericArsHostExecution _ _ _ _ _ after) = after

-- The same prepared numerical continuation and final evaluator used above.
-- The generic identity has no invented RunPlan or borrowed scenario invocation.
-- All positive compiled evaluation counts/current simulated ARS environments
-- remain supported; trace resource refusal is explicit, never a shortened run.
runGenericArsAttemptForPlan
  :: Substrate -> Text -> FilePath -> ProductBudget.CompiledRlPlan -> IO GenericArsAttempt
runGenericArsAttemptForPlan lane experiment sourceRoot compiled = do
  rawRef <- IORef.newIORef Nothing
  evaluationRef <- IORef.newIORef Nothing
  originRef <- IORef.newIORef Nothing
  result <- runExceptT $ do
    (simEnv, config) <- stage ArsSuppliedContext $ pure $ do
      reparsed <-
        ProductBudget.parseCompiledRlPlanTransport (ProductBudget.renderCompiledRlPlanTransport compiled)
      requireArsInput
        (reparsed == compiled)
        "generic ARS compiled plan differs from its exact public compiler projection"
      requireArsInput
        (isNothing (ProductMatrix.productRowForExperimentHash experiment))
        "generic ARS cannot occupy a canonical ProductRow experiment"
      _ <- ArsReference.arsHostObjectKey experiment (Text.replicate 64 "0")
      ArsTrace.resolveArsHostPlanData compiled
    before <- stage ArsBeforeProcess (actualProcess (ObserveArsSourceRoot sourceRoot))
    coverage <-
      stage ArsSuppliedContext $
        pure (actualSourceCoverage (ObserveArsSourceRoot sourceRoot) before)
    attemptId <- stage ArsNonce actualArsAttemptId
    prepared <- stage ArsPreparation $ Right <$> ArsTrainer.prepareArsOnEnvironment simEnv config
    let snapshot = ArsTrainer.preparedArsSnapshot prepared
    raw <- stage ArsTraining (ArsTrainer.continuePreparedArsRaw prepared)
    stage ArsRawReturnForcing $ do
      _ <- evaluate (length (show raw))
      pure (Right ())
    liftIO (IORef.writeIORef rawRef (Just raw))
    stage ArsCounters $
      evaluateStrictTrainerReturn (Observation.ReturnedArs raw) (pure (Right ()))
    evaluation <- stage ArsEvaluation $ do
      let actual = arsFinalEvaluation simEnv config raw (ProductBudget.compiledRlEvaluationEpisodes compiled)
      forceArsEvaluation actual
      pure (Right actual)
    liftIO (IORef.writeIORef evaluationRef (Just evaluation))
    (trace, reference) <- stage ArsTraceValidation $ do
      let checked = do
            requireArsInput
              (AlgorithmCommon.rawTrainerConfig raw == ArsTrainer.arsPreparedConfig snapshot)
              "generic ARS returned config differs from its actual prepared snapshot"
            requireArsInput
              ( Checkpoint.encodeJmw1 (Observation.returnedInitialWeights (Observation.ReturnedArs raw))
                  == Checkpoint.encodeJmw1 (VU.toList (ArsTrainer.arsPreparedInitialParams snapshot))
              )
              "generic ARS returned initial bytes differ from its actual prepared snapshot"
            buildActualGenericArsTrace lane experiment compiled before coverage attemptId raw
      case checked of
        Left reason -> pure (Left reason)
        Right pair@(actualTrace, _) -> do
          _ <- evaluate (Data.ByteString.length (ArsTrace.encodeArsHostTrace actualTrace))
          pure (Right pair)
    after <- stage ArsAfterProcess (actualProcess (ObserveArsSourceRoot sourceRoot))
    stage ArsAfterProcess $
      pure (first (Text.pack . show) (Producer.compareProducerProcessObservations before after))
    liftIO $
      IORef.writeIORef originRef $
        Just $
          ProducedGenericArsHostExecution compiled experiment trace reference before after
    stage ArsStrictRefinement $ do
      let strict =
            refineStrictObservation
              lane
              ( Observation.TrainerReturned
                  (Observation.RawTrainerObservation compiled (Observation.ReturnedArs raw) evaluation)
              )
              >>= attachActualArsReference reference
      _ <- evaluate (length (show strict))
      pure strict
  raw <- IORef.readIORef rawRef
  evaluation <- IORef.readIORef evaluationRef
  origin <- IORef.readIORef originRef
  pure $ case result of
    Left failure -> GenericArsAttempt raw evaluation (Just failure) (Left (arsFailureDetail failure)) origin
    Right strict -> GenericArsAttempt raw evaluation Nothing (Right strict) origin
 where
  stage phase = ExceptT . arsAt phase
{-# NOINLINE runGenericArsAttemptForPlan #-}

buildActualGenericArsTrace
  :: Substrate
  -> Text
  -> ProductBudget.CompiledRlPlan
  -> Producer.ObservedProducerProcess
  -> ArsProducerSourceCoverage
  -> Text
  -> ArsTrainer.ArsTrainObservation
  -> Either Text (ArsTrace.ArsHostTrace, ArsReference.ArsHostReference)
buildActualGenericArsTrace lane experiment compiled before coverage attemptId raw = do
  stamp <- case coverage of
    ObservedArsLocalSource _ actual -> Right actual
    UnauthenticatedArsSuppliedParentSource _ -> Left "generic ARS requires an actual source observation"
  let row = "generic-ars/" <> ProductBudget.compiledRlEnvironment compiled
      invocationDigest =
        hashBytes $
          Text.Encoding.encodeUtf8 $
            Text.concat $
              fmap
                field
                [ "jitml-generic-ars-compiled-plan-attempt-v1"
                , attemptId
                , experiment
                , ProductBudget.compiledRlPlanId compiled
                , ProductBudget.renderCompiledRlPlanTransport compiled
                , renderSubstrate lane
                , Text.pack (show (Source.stampAlgorithm stamp))
                , Source.stampSha256 stamp
                , Producer.producerExecutableFileSha256 before
                , Text.pack (show (Producer.producerProcessId before))
                ]
      context =
        ArsTrace.RawArsHostContext
          { ArsTrace.rawArsHostRowId = row
          , ArsTrace.rawArsHostExperiment = experiment
          , ArsTrace.rawArsHostPlanId = ProductBudget.compiledRlPlanId compiled
          , ArsTrace.rawArsHostCompiledTransport = ProductBudget.renderCompiledRlPlanTransport compiled
          , ArsTrace.rawArsHostLane = renderSubstrate lane
          , ArsTrace.rawArsHostSourceSha256 = Source.stampSha256 stamp
          , ArsTrace.rawArsHostExecutableSha256 = Producer.producerExecutableFileSha256 before
          , ArsTrace.rawArsHostInvocationSha256 = invocationDigest
          , ArsTrace.rawArsHostExecutionBinding = "generic-compiled-plan-attempt-v1"
          , ArsTrace.rawArsHostKernelOS = Producer.producerKernelOperatingSystem before
          , ArsTrace.rawArsHostKernelMachine = Producer.producerKernelMachine before
          , ArsTrace.rawArsHostKernelRelease = Producer.producerKernelRelease before
          , ArsTrace.rawArsHostSimulatorContract =
              "jitml-known-discrete-simulator-ars-v1:" <> ProductBudget.compiledRlEnvironment compiled
          , ArsTrace.rawArsHostProcessId = Text.pack (show (Producer.producerProcessId before))
          , ArsTrace.rawArsHostAttemptId = attemptId
          }
  trace <-
    ArsTrace.refineArsHostTrace
      (ArsTrace.RawArsHostTrace context ArsTrainer.arsNativeNumericalRuntime raw)
  ArsTrace.validateArsHostTracePlan compiled trace
  ArsTrace.validateArsHostTraceLocal trace
  reference <- ArsTrace.arsHostTraceRecordedReference trace
  ArsTrace.validateArsHostTraceReference reference trace
  pure (trace, reference)
 where
  field value = Text.pack (show (Text.length value)) <> ":" <> value

-- END ACTUAL GENERIC ARS HOST EXECUTION
