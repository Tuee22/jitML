{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | Actual low numerical preparation/continuation only. No evaluation,
-- canonical native membership, provider/origin, durability or qualification.
module JitML.RL.PreparedNeuralAttempt
  ( PreparedNeuralAttempt
  , EffectiveNeuralAttempt
  , NeuralSnapshot
  , NeuralPendingReturn
  , NeuralReturnedData
  , NeuralPreparationStage (..)
  , NeuralAttemptStage (..)
  , NeuralFailureKind (..)
  , NeuralFailureFacts (..)
  , NeuralAttemptFailure (..)
  , NeuralPreparationResult (..)
  , NeuralInitializationResult (..)
  , NeuralTrainingResult (..)
  , prepareNeuralAttempt
  , neuralPreparationStage
  , neuralPreparedSnapshot
  , initializePreparedNeural
  , neuralEffectiveSnapshot
  , neuralEffectiveColdSnapshot
  , runPreparedNeuralRaw
  , neuralSnapshotConfiguration
  , neuralSnapshotInitialParams
  , foldNeuralSnapshot
  , neuralPendingReturnedData
  , neuralReturnedPolicy
  , neuralReturnedPlan
  , neuralReturnedExpectedConfiguration
  , neuralReturnedExpectedInitialParams
  , validateNeuralReturnedBinding
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless, void, when)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Execution.SingleUse qualified as SingleUse
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.Simulator qualified as Sim
import JitML.RL.TrainerConfiguration qualified as Config
import JitML.RL.TrainerObservation qualified as Observation

-- Private capsules preserve the actual existential state and action closures.
data PreparedCore where
  PpoCore :: Ppo.PreparedPpo state -> PreparedCore
  DqnCore :: Dqn.PreparedDqn state -> PreparedCore
  QrCore :: Qr.PreparedQrDqn state -> PreparedCore
  ColdCore :: Continuous.PreparedContinuousCold state -> PreparedCore
  ContinuousCore :: Continuous.PreparedContinuous state -> PreparedCore
  HerCore :: Her.PreparedHer -> PreparedCore

data NeuralSnapshot where
  PpoSnapshot :: Ppo.PpoPreparedSnapshot state -> NeuralSnapshot
  DqnSnapshot :: Dqn.DqnPreparedSnapshot state -> NeuralSnapshot
  QrSnapshot :: Qr.QrDqnPreparedSnapshot state -> NeuralSnapshot
  ContinuousSnapshot :: Continuous.ContinuousPreparedSnapshot state -> NeuralSnapshot
  HerSnapshot :: Her.HerPreparedSnapshot -> NeuralSnapshot

-- No constructors, record labels, Read/Generic or capsule/action observers.
data PreparedNeuralAttempt
  = PreparedNeuralAttempt
      Plan.CompiledRlPlan
      Config.NeuralTrainerConfiguration
      NeuralSnapshot
      PreparedCore
      SingleUse.SingleUse
data EffectiveNeuralAttempt
  = EffectiveNeuralAttempt
      Plan.CompiledRlPlan
      Config.NeuralTrainerConfiguration
      NeuralSnapshot
      (Maybe NeuralSnapshot)
      PreparedCore
      SingleUse.SingleUse
data NeuralReturnedData
  = NeuralReturnedData
      Plan.CompiledRlPlan
      Config.NeuralTrainerConfiguration
      Mlp.MlpParams
      Observation.ReturnedPolicy

-- Retain the data wrapper: newtype would change its intentional laziness.
{- HLINT ignore NeuralPendingReturn "Use newtype instead of data" -}
data NeuralPendingReturn = NeuralPendingReturn NeuralReturnedData

data NeuralPreparationStage = NeuralCold | NeuralAlreadyEffective
  deriving stock (Eq, Show)
data NeuralAttemptStage
  = NeuralAdmission
  | NeuralProbe
  | NeuralRecipe
  | NeuralPrepare
  | NeuralInitialization
  | NeuralContinuation
  | NeuralReturnMaterialization
  | NeuralReturnBinding
  deriving stock (Eq, Show)
data NeuralFailureKind = NeuralRejected | NeuralSynchronousFailure | NeuralAlreadyConsumed
  deriving stock (Eq, Show)

-- Every optional fact below was fully observed before retention. An undefined
-- supplied input or unmaterializable returned thunk is never retained here.
data NeuralFailureFacts = NeuralFailureFacts
  { neuralFailurePlan :: !(Maybe Plan.CompiledRlPlan)
  , neuralFailureExpectedConfiguration :: !(Maybe Config.NeuralTrainerConfiguration)
  , neuralFailureInitialParams :: !(Maybe Mlp.MlpParams)
  , neuralFailureReturnedConfiguration :: !(Maybe Config.NeuralTrainerConfiguration)
  , neuralFailureReturnedCounters :: !(Maybe Common.ObservedTrainerCounters)
  }
  deriving stock (Eq, Show)
data NeuralAttemptFailure = NeuralAttemptFailure
  { neuralFailureStage :: !NeuralAttemptStage
  , neuralFailureKind :: !NeuralFailureKind
  , neuralFailureDetail :: !Text
  , neuralFailureFacts :: !NeuralFailureFacts
  }
  deriving stock (Eq, Show)

data NeuralPreparationResult
  = NeuralPreparationFailed !NeuralAttemptFailure
  | NeuralPreparationReady PreparedNeuralAttempt
data NeuralInitializationResult
  = NeuralInitializationFailed !NeuralAttemptFailure
  | NeuralInitializationReady EffectiveNeuralAttempt
data NeuralTrainingResult
  = NeuralTrainingFailed !NeuralAttemptFailure
  | NeuralReturnedButUnmaterializable !NeuralAttemptFailure
  | NeuralReturnedBindingFailed NeuralReturnedData !NeuralAttemptFailure
  | NeuralTrainingReturned NeuralPendingReturn

emptyFacts :: NeuralFailureFacts
emptyFacts = NeuralFailureFacts Nothing Nothing Nothing Nothing Nothing

prepareNeuralAttempt :: MlpDevice -> Plan.CompiledRlPlan -> IO NeuralPreparationResult
prepareNeuralAttempt device plan = do
  stage <- newIORef NeuralAdmission
  facts <- newIORef emptyFacts
  attempted <- tryAny $ do
    let kind = Plan.compiledRlTrainerKind plan
        environment = Plan.compiledRlEnvironment plan
    admission <- forceEitherText $ do
      when
        (Plan.isAleAdapterEnvironment environment)
        (Left "prepared neural attempt excludes the ALE adapter")
      unless (kind /= "ars") (Left "prepared neural attempt excludes ARS host training")
      unless
        (kind `elem` Config.knownNeuralTrainerKinds)
        ( Left
            ( "unknown RL trainer: "
                <> kind
                <> " (expected one of: "
                <> Text.intercalate ", " (Config.knownNeuralTrainerKinds <> ["ars"])
                <> ")"
            )
        )
      maybe (Right ()) Left (Plan.rlTrainerEnvironmentCompatibilityError kind environment)
    case admission of
      Left reason -> pure (Left reason)
      Right () -> do
        writeIORef stage NeuralProbe
        probed <- probeMlpDevice device >>= forceEitherText
        case probed of
          Left reason -> pure (Left ("RL substrate device unavailable for trainer " <> kind <> ": " <> reason))
          Right () -> do
            writeIORef stage NeuralRecipe
            resolved <- forceEitherText (Config.resolveNeuralTrainerRecipe plan)
            case resolved of
              Left reason -> pure (Left reason)
              Right recipe -> do
                -- The probe precedes all recipe/schedule/config materialization.
                let configuration = Config.neuralTrainerConfiguration recipe
                _ <- evaluate (forcePlan plan)
                modifyIORef' facts (\known -> known {neuralFailurePlan = Just plan})
                _ <- evaluate (forceConfiguration configuration)
                modifyIORef' facts (\known -> known {neuralFailureExpectedConfiguration = Just configuration})
                writeIORef stage NeuralPrepare
                core <- prepareCore device recipe
                let snapshot = snapshotCore core
                _ <- evaluate (forceSnapshot snapshot)
                checked <-
                  forceEitherText (validateConfiguration configuration (neuralSnapshotConfiguration snapshot))
                case checked of
                  Left reason -> pure (Left reason)
                  Right () -> do
                    let initial = neuralSnapshotInitialParams snapshot
                    modifyIORef' facts (\known -> known {neuralFailureInitialParams = Just initial})
                    Right . PreparedNeuralAttempt plan configuration snapshot core
                      <$> SingleUse.newSingleUse
  at <- readIORef stage
  known <- readIORef facts
  case attempted of
    Left exception -> NeuralPreparationFailed <$> exceptionFailure at known exception
    Right (Left reason) -> pure (NeuralPreparationFailed (NeuralAttemptFailure at NeuralRejected reason known))
    Right (Right prepared) -> pure (NeuralPreparationReady prepared)

prepareCore :: MlpDevice -> Config.NeuralTrainerRecipe -> IO PreparedCore
prepareCore device =
  Config.foldNeuralTrainerRecipe
    ( \_ (Sim.SomeSimulatedEnvironment environment) config -> PpoCore <$> Ppo.preparePpoOnDeviceWithEnvironment device environment config
    )
    ( \(Sim.SomeSimulatedEnvironment environment) config -> DqnCore <$> Dqn.prepareDqnOnDeviceWithEnvironment device environment config
    )
    ( \(Sim.SomeSimulatedEnvironment environment) config -> QrCore <$> Qr.prepareQrDqnOnDeviceWithEnvironment device environment config
    )
    ( \(Sim.SomeContinuousEnvironment environment) config -> ColdCore <$> Continuous.prepareContinuousOnDeviceWithEnvironment device environment config
    )
    (fmap HerCore . Her.prepareHerOnDevice device)

snapshotCore :: PreparedCore -> NeuralSnapshot
snapshotCore core = case core of
  PpoCore prepared -> PpoSnapshot (Ppo.preparedPpoSnapshot prepared)
  DqnCore prepared -> DqnSnapshot (Dqn.preparedDqnSnapshot prepared)
  QrCore prepared -> QrSnapshot (Qr.preparedQrDqnSnapshot prepared)
  ColdCore prepared -> ContinuousSnapshot (Continuous.preparedContinuousColdSnapshot prepared)
  ContinuousCore prepared -> ContinuousSnapshot (Continuous.preparedContinuousSnapshot prepared)
  HerCore prepared -> HerSnapshot (Her.preparedHerSnapshot prepared)

neuralPreparationStage :: PreparedNeuralAttempt -> NeuralPreparationStage
neuralPreparationStage (PreparedNeuralAttempt _ _ _ core _) = case core of
  ColdCore _ -> NeuralCold
  _ -> NeuralAlreadyEffective

neuralPreparedSnapshot :: PreparedNeuralAttempt -> NeuralSnapshot
neuralPreparedSnapshot (PreparedNeuralAttempt _ _ snapshot _ _) = snapshot

neuralEffectiveSnapshot :: EffectiveNeuralAttempt -> NeuralSnapshot
neuralEffectiveSnapshot (EffectiveNeuralAttempt _ _ snapshot _ _ _) = snapshot

neuralEffectiveColdSnapshot :: EffectiveNeuralAttempt -> Maybe NeuralSnapshot
neuralEffectiveColdSnapshot (EffectiveNeuralAttempt _ _ _ cold _ _) = cold

initializePreparedNeural :: PreparedNeuralAttempt -> IO NeuralInitializationResult
initializePreparedNeural (PreparedNeuralAttempt plan config before core guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let known = snapshotFacts plan config before
  if not claimed
    then
      pure
        ( NeuralInitializationFailed
            ( NeuralAttemptFailure
                NeuralInitialization
                NeuralAlreadyConsumed
                "prepared neural initialization has already been consumed"
                known
            )
        )
    else do
      attempted <- tryAny $ do
        initialized <- case core of
          ColdCore prepared -> fmap (fmap ContinuousCore) (Continuous.continuePreparedContinuousInitialization prepared)
          _ -> pure (Right core)
        case initialized of
          Left reason -> forceText reason >> pure (Left reason)
          Right effective -> do
            let snapshot = snapshotCore effective
            _ <- evaluate (forceSnapshot snapshot)
            checked <- forceEitherText (validateConfiguration config (neuralSnapshotConfiguration snapshot))
            case checked of
              Left reason -> pure (Left reason)
              Right () -> do
                nextGuard <- SingleUse.newSingleUse
                let cold = case core of ColdCore _ -> Just before; _ -> Nothing
                pure (Right (EffectiveNeuralAttempt plan config snapshot cold effective nextGuard))
      case attempted of
        Left exception -> NeuralInitializationFailed <$> exceptionFailure NeuralInitialization known exception
        Right (Left reason) ->
          pure
            (NeuralInitializationFailed (NeuralAttemptFailure NeuralInitialization NeuralRejected reason known))
        Right (Right effective) -> pure (NeuralInitializationReady effective)

runPreparedNeuralRaw :: EffectiveNeuralAttempt -> IO NeuralTrainingResult
runPreparedNeuralRaw (EffectiveNeuralAttempt plan config snapshot _ core guard) = do
  claimed <- SingleUse.tryConsumeSingleUse guard
  let known = snapshotFacts plan config snapshot
  if not claimed
    then
      pure
        ( NeuralTrainingFailed
            ( NeuralAttemptFailure
                NeuralContinuation
                NeuralAlreadyConsumed
                "prepared neural training has already been consumed"
                known
            )
        )
    else do
      at <- newIORef NeuralContinuation
      didReturn <- newIORef False
      materialized <- newIORef Nothing
      facts <- newIORef known
      attempted <- tryAny $ do
        actual <- continueCore core
        case actual of
          Left reason -> forceText reason >> pure (Left reason)
          Right policy -> do
            -- Observe actual outer Right before forcing its payload. No retryable
            -- handle to an unmaterializable return is exposed or retained.
            writeIORef didReturn True
            writeIORef at NeuralReturnMaterialization
            let counters = Observation.returnedCounters policy
            _ <- evaluate (forceCounters counters)
            modifyIORef' facts (\observed -> observed {neuralFailureReturnedCounters = Just counters})
            let returnedConfig = configurationOf policy
            _ <- evaluate (forceConfiguration returnedConfig)
            modifyIORef'
              facts
              (\observed -> observed {neuralFailureReturnedConfiguration = Just returnedConfig})
            _ <- evaluate (forceReturnedPolicy policy)
            let returned = NeuralReturnedData plan config (neuralSnapshotInitialParams snapshot) policy
            writeIORef materialized (Just returned)
            writeIORef at NeuralReturnBinding
            checked <-
              forceEitherText (validateNeuralReturnedBinding config (neuralSnapshotInitialParams snapshot) policy)
            pure (Right (returned, checked))
      stage <- readIORef at
      observed <- readIORef facts
      case attempted of
        Left exception -> do
          failure <- exceptionFailure stage observed exception
          complete <- readIORef materialized
          case complete of
            Just returned -> pure (NeuralReturnedBindingFailed returned failure)
            Nothing -> do
              returned <- readIORef didReturn
              pure (if returned then NeuralReturnedButUnmaterializable failure else NeuralTrainingFailed failure)
        Right (Left reason) -> pure (NeuralTrainingFailed (NeuralAttemptFailure stage NeuralRejected reason observed))
        Right (Right (returned, Left reason)) ->
          pure
            (NeuralReturnedBindingFailed returned (NeuralAttemptFailure stage NeuralRejected reason observed))
        Right (Right (returned, Right ())) -> pure (NeuralTrainingReturned (NeuralPendingReturn returned))

continueCore :: PreparedCore -> IO (Either Text Observation.ReturnedPolicy)
continueCore core = case core of
  PpoCore prepared -> fmap (fmap Observation.ReturnedOnPolicy) (Ppo.continuePreparedPpoRaw prepared)
  DqnCore prepared -> fmap (fmap Observation.ReturnedDqn) (Dqn.continuePreparedDqnRaw prepared)
  QrCore prepared -> fmap (fmap Observation.ReturnedQrDqn) (Qr.continuePreparedQrDqnRaw prepared)
  ContinuousCore prepared -> fmap (fmap Observation.ReturnedContinuous) (Continuous.continuePreparedContinuousRaw prepared)
  HerCore prepared -> fmap (fmap Observation.ReturnedHer) (Her.continuePreparedHerRaw prepared)
  ColdCore _ -> pure (Left "prepared neural continuous training requires its actual effective initialization")

neuralPendingReturnedData :: NeuralPendingReturn -> NeuralReturnedData
neuralPendingReturnedData (NeuralPendingReturn returned) = returned
neuralReturnedPolicy :: NeuralReturnedData -> Observation.ReturnedPolicy
neuralReturnedPolicy (NeuralReturnedData _ _ _ policy) = policy
neuralReturnedPlan :: NeuralReturnedData -> Plan.CompiledRlPlan
neuralReturnedPlan (NeuralReturnedData plan _ _ _) = plan
neuralReturnedExpectedConfiguration :: NeuralReturnedData -> Config.NeuralTrainerConfiguration
neuralReturnedExpectedConfiguration (NeuralReturnedData _ config _ _) = config
neuralReturnedExpectedInitialParams :: NeuralReturnedData -> Mlp.MlpParams
neuralReturnedExpectedInitialParams (NeuralReturnedData _ _ initial _) = initial

-- | Data-only predicate. Even matching supplied observations return only unit,
-- never a prepared/pending capability or any learning/completion evidence.
validateNeuralReturnedBinding
  :: Config.NeuralTrainerConfiguration -> Mlp.MlpParams -> Observation.ReturnedPolicy -> Either Text ()
validateNeuralReturnedBinding expected initial policy = do
  case policy of
    Observation.ReturnedArs _ -> Left "prepared neural return has an excluded ARS family"
    _ -> Right ()
  validateConfiguration expected (configurationOf policy)
  unless
    (sameParams initial (initialOf policy))
    (Left "prepared neural returned initial parameters differ from the actual effective snapshot")

validateConfiguration
  :: Config.NeuralTrainerConfiguration -> Config.NeuralTrainerConfiguration -> Either Text ()
validateConfiguration expected actual =
  unless
    (projectNeuralConfiguration expected == projectNeuralConfiguration actual)
    (Left "prepared neural actual full configuration differs from its resolved recipe")

configurationOf :: Observation.ReturnedPolicy -> Config.NeuralTrainerConfiguration
configurationOf policy = case policy of
  Observation.ReturnedOnPolicy raw -> Config.OnPolicyConfiguration (Common.rawTrainerConfig raw)
  Observation.ReturnedDqn raw -> Config.DqnConfiguration (Common.rawTrainerConfig raw)
  Observation.ReturnedQrDqn raw -> Config.QrDqnConfiguration (Common.rawTrainerConfig raw)
  Observation.ReturnedContinuous raw -> Config.ContinuousConfiguration (Common.rawTrainerConfig raw)
  Observation.ReturnedHer raw -> Config.HerConfiguration (Common.rawTrainerConfig raw)
  Observation.ReturnedArs _ -> error "excluded ARS has no neural configuration"

initialOf :: Observation.ReturnedPolicy -> Mlp.MlpParams
initialOf policy = case policy of
  Observation.ReturnedOnPolicy raw -> Common.rawTrainerInitialParams raw
  Observation.ReturnedDqn raw -> Common.rawTrainerInitialParams raw
  Observation.ReturnedQrDqn raw -> Common.rawTrainerInitialParams raw
  Observation.ReturnedContinuous raw -> Common.rawTrainerInitialParams raw
  Observation.ReturnedHer raw -> Common.rawTrainerInitialParams raw
  Observation.ReturnedArs _ -> error "excluded ARS has no neural parameters"

sameParams :: Mlp.MlpParams -> Mlp.MlpParams -> Bool
sameParams left right =
  Mlp.paramShape left == Mlp.paramShape right
    && map
      (VU.map castDoubleToWord64)
      [Mlp.paramW1 left, Mlp.paramB1 left, Mlp.paramW2 left, Mlp.paramB2 left]
      == map
        (VU.map castDoubleToWord64)
        [Mlp.paramW1 right, Mlp.paramB1 right, Mlp.paramW2 right, Mlp.paramB2 right]

snapshotFacts
  :: Plan.CompiledRlPlan -> Config.NeuralTrainerConfiguration -> NeuralSnapshot -> NeuralFailureFacts
snapshotFacts plan config snapshot =
  NeuralFailureFacts
    (Just plan)
    (Just config)
    (Just (neuralSnapshotInitialParams snapshot))
    Nothing
    Nothing

neuralSnapshotConfiguration :: NeuralSnapshot -> Config.NeuralTrainerConfiguration
neuralSnapshotConfiguration =
  foldNeuralSnapshot
    (Config.OnPolicyConfiguration . Ppo.ppoPreparedConfig)
    (Config.DqnConfiguration . Dqn.dqnPreparedConfig)
    (Config.QrDqnConfiguration . Qr.qrDqnPreparedConfig)
    (Config.ContinuousConfiguration . Continuous.continuousPreparedConfig)
    (Config.HerConfiguration . Her.herPreparedConfig)

neuralSnapshotInitialParams :: NeuralSnapshot -> Mlp.MlpParams
neuralSnapshotInitialParams =
  foldNeuralSnapshot
    Ppo.ppoPreparedInitialParams
    Dqn.dqnPreparedInitialParams
    Qr.qrDqnPreparedInitialParams
    Continuous.continuousPreparedActor
    Her.herPreparedInitialParams

-- | Pure immutable-data eliminator only. It never supplies a capsule, device
-- or action to a handler, and cannot mint a stage from its result.
foldNeuralSnapshot
  :: (forall state. Ppo.PpoPreparedSnapshot state -> result)
  -> (forall state. Dqn.DqnPreparedSnapshot state -> result)
  -> (forall state. Qr.QrDqnPreparedSnapshot state -> result)
  -> (forall state. Continuous.ContinuousPreparedSnapshot state -> result)
  -> (Her.HerPreparedSnapshot -> result)
  -> NeuralSnapshot
  -> result
foldNeuralSnapshot ppo dqn qr continuous her snapshot = case snapshot of
  PpoSnapshot actual -> ppo actual
  DqnSnapshot actual -> dqn actual
  QrSnapshot actual -> qr actual
  ContinuousSnapshot actual -> continuous actual
  HerSnapshot actual -> her actual

forceEitherText :: Either Text value -> IO (Either Text value)
forceEitherText returned = do
  case returned of Left reason -> forceText reason; Right _ -> pure ()
  pure returned

exceptionFailure
  :: NeuralAttemptStage -> NeuralFailureFacts -> SomeException -> IO NeuralAttemptFailure
exceptionFailure stage facts exception = do
  attempted <- tryAny $ do
    let message = Text.pack (displayException exception)
    forceText message
    pure message
  let message = case attempted of Left _ -> "synchronous exception rendering failed"; Right actual -> actual
  pure (NeuralAttemptFailure stage NeuralSynchronousFailure message facts)

forceText :: Text -> IO ()
forceText value = void (evaluate (Text.length value))

-- Materialization helpers/projection follow below. No refinement/filter is
-- allowed here: even nonfinite returned numeric values remain observed data.

-- Private data only. Keep both constructors and this projection out of exports.
-- Preserve the exact Double payload, including signed zero and NaN payload bits.
-- Equality is NOT validation, canonical-plan admission, initialization or origin.
data NeuralConfigurationProjection = NeuralConfigurationProjection Text [ConfigAtom]
  deriving stock (Eq)

data ConfigAtom
  = ConfigInt Int
  | ConfigBool Bool
  | ConfigText Text
  | ConfigWord Word64
  deriving stock (Eq)

projectNeuralConfiguration :: Config.NeuralTrainerConfiguration -> NeuralConfigurationProjection
projectNeuralConfiguration configuration = case configuration of
  Config.OnPolicyConfiguration
    ( Ppo.PpoTrainConfig
        v01 -- ppoSeed :: Int
        v02 -- ppoHiddenUnits :: Int
        v03 -- ppoVectorEnvCount :: Int
        v04 -- ppoRolloutSteps :: Int
        v05 -- ppoNumIterations :: Int
        v06 -- ppoEpochsPerUpdate :: Int
        v07 -- ppoMiniBatchSize :: Int
        v08 -- ppoGamma :: Double
        v09 -- ppoLambda :: Double
        v10 -- ppoClipEps :: Double
        v11 -- ppoValueCoef :: Double
        v12 -- ppoEntropyCoef :: Double
        v13 -- ppoCountBeta :: Double
        v14 -- ppoMaxEpisodeSteps :: Int
        v15 -- ppoActionCount :: Int
        v16 -- ppoObsSize :: Int
        v17 -- ppoLearningRate :: Double
        v18 -- ppoVariant :: OnPolicyVariant
        v19 -- ppoKlTarget :: Double
        v20 -- ppoTrpoCgIterations :: Int
        v21 -- ppoTrpoCgDamping :: Double
        v22 -- ppoTrpoBacktrackIterations :: Int
        v23 -- ppoTrpoBacktrackCoef :: Double
        v24 -- ppoTrpoCriticUpdates :: Int
        v25 -- ppoTrpoCriticLearningRate :: Double
        v26 -- ppoRecurrentStateSize :: Int
      ) ->
      NeuralConfigurationProjection
        "on-policy"
        [ ConfigInt v01 -- ppoSeed
        , ConfigInt v02 -- ppoHiddenUnits
        , ConfigInt v03 -- ppoVectorEnvCount
        , ConfigInt v04 -- ppoRolloutSteps
        , ConfigInt v05 -- ppoNumIterations
        , ConfigInt v06 -- ppoEpochsPerUpdate
        , ConfigInt v07 -- ppoMiniBatchSize
        , ConfigWord (castDoubleToWord64 v08) -- ppoGamma
        , ConfigWord (castDoubleToWord64 v09) -- ppoLambda
        , ConfigWord (castDoubleToWord64 v10) -- ppoClipEps
        , ConfigWord (castDoubleToWord64 v11) -- ppoValueCoef
        , ConfigWord (castDoubleToWord64 v12) -- ppoEntropyCoef
        , ConfigWord (castDoubleToWord64 v13) -- ppoCountBeta
        , ConfigInt v14 -- ppoMaxEpisodeSteps
        , ConfigInt v15 -- ppoActionCount
        , ConfigInt v16 -- ppoObsSize
        , ConfigWord (castDoubleToWord64 v17) -- ppoLearningRate
        , ConfigText (projectOnPolicyVariant v18) -- ppoVariant
        , ConfigWord (castDoubleToWord64 v19) -- ppoKlTarget
        , ConfigInt v20 -- ppoTrpoCgIterations
        , ConfigWord (castDoubleToWord64 v21) -- ppoTrpoCgDamping
        , ConfigInt v22 -- ppoTrpoBacktrackIterations
        , ConfigWord (castDoubleToWord64 v23) -- ppoTrpoBacktrackCoef
        , ConfigInt v24 -- ppoTrpoCriticUpdates
        , ConfigWord (castDoubleToWord64 v25) -- ppoTrpoCriticLearningRate
        , ConfigInt v26 -- ppoRecurrentStateSize
        ]
  Config.DqnConfiguration
    ( Dqn.DqnTrainConfig
        v01 -- dqnSeed :: Int
        v02 -- dqnHiddenUnits :: Int
        v03 -- dqnNumSteps :: Int
        v04 -- dqnReplayCapacity :: Int
        v05 -- dqnBatchSize :: Int
        v06 -- dqnLearningRate :: Double
        v07 -- dqnGamma :: Double
        v08 -- dqnTargetUpdateInterval :: Int
        v09 -- dqnEpsilonStart :: Double
        v10 -- dqnEpsilonEnd :: Double
        v11 -- dqnEpsilonDecaySteps :: Int
        v12 -- dqnTrainStart :: Int
        v13 -- dqnUpdateFrequency :: Int
        v14 -- dqnMaxEpisodeSteps :: Int
        v15 -- dqnActionCount :: Int
        v16 -- dqnObsSize :: Int
        v17 -- dqnStatInterval :: Int
        v18 -- dqnUseDouble :: Bool
      ) ->
      NeuralConfigurationProjection
        "dqn"
        [ ConfigInt v01 -- dqnSeed
        , ConfigInt v02 -- dqnHiddenUnits
        , ConfigInt v03 -- dqnNumSteps
        , ConfigInt v04 -- dqnReplayCapacity
        , ConfigInt v05 -- dqnBatchSize
        , ConfigWord (castDoubleToWord64 v06) -- dqnLearningRate
        , ConfigWord (castDoubleToWord64 v07) -- dqnGamma
        , ConfigInt v08 -- dqnTargetUpdateInterval
        , ConfigWord (castDoubleToWord64 v09) -- dqnEpsilonStart
        , ConfigWord (castDoubleToWord64 v10) -- dqnEpsilonEnd
        , ConfigInt v11 -- dqnEpsilonDecaySteps
        , ConfigInt v12 -- dqnTrainStart
        , ConfigInt v13 -- dqnUpdateFrequency
        , ConfigInt v14 -- dqnMaxEpisodeSteps
        , ConfigInt v15 -- dqnActionCount
        , ConfigInt v16 -- dqnObsSize
        , ConfigInt v17 -- dqnStatInterval
        , ConfigBool v18 -- dqnUseDouble
        ]
  Config.QrDqnConfiguration
    ( Qr.QrDqnTrainConfig
        v01 -- qrSeed :: Int
        v02 -- qrHiddenUnits :: Int
        v03 -- qrNumQuantiles :: Int
        v04 -- qrNumSteps :: Int
        v05 -- qrReplayCapacity :: Int
        v06 -- qrBatchSize :: Int
        v07 -- qrLearningRate :: Double
        v08 -- qrGamma :: Double
        v09 -- qrKappa :: Double
        v10 -- qrTargetUpdateInterval :: Int
        v11 -- qrEpsilonStart :: Double
        v12 -- qrEpsilonEnd :: Double
        v13 -- qrEpsilonDecaySteps :: Int
        v14 -- qrTrainStart :: Int
        v15 -- qrUpdateFrequency :: Int
        v16 -- qrMaxEpisodeSteps :: Int
        v17 -- qrActionCount :: Int
        v18 -- qrObsSize :: Int
        v19 -- qrStatInterval :: Int
      ) ->
      NeuralConfigurationProjection
        "qrdqn"
        [ ConfigInt v01 -- qrSeed
        , ConfigInt v02 -- qrHiddenUnits
        , ConfigInt v03 -- qrNumQuantiles
        , ConfigInt v04 -- qrNumSteps
        , ConfigInt v05 -- qrReplayCapacity
        , ConfigInt v06 -- qrBatchSize
        , ConfigWord (castDoubleToWord64 v07) -- qrLearningRate
        , ConfigWord (castDoubleToWord64 v08) -- qrGamma
        , ConfigWord (castDoubleToWord64 v09) -- qrKappa
        , ConfigInt v10 -- qrTargetUpdateInterval
        , ConfigWord (castDoubleToWord64 v11) -- qrEpsilonStart
        , ConfigWord (castDoubleToWord64 v12) -- qrEpsilonEnd
        , ConfigInt v13 -- qrEpsilonDecaySteps
        , ConfigInt v14 -- qrTrainStart
        , ConfigInt v15 -- qrUpdateFrequency
        , ConfigInt v16 -- qrMaxEpisodeSteps
        , ConfigInt v17 -- qrActionCount
        , ConfigInt v18 -- qrObsSize
        , ConfigInt v19 -- qrStatInterval
        ]
  Config.ContinuousConfiguration
    ( Continuous.ContinuousTrainConfig
        v01 -- ctVariant :: ContinuousVariant
        v02 -- ctSeed :: Int
        v03 -- ctHidden :: Int
        v04 -- ctNumSteps :: Int
        v05 -- ctReplayCapacity :: Int
        v06 -- ctBatchSize :: Int
        v07 -- ctActorLr :: Double
        v08 -- ctCriticLr :: Double
        v09 -- ctGamma :: Double
        v10 -- ctTau :: Double
        v11 -- ctPolicyDelay :: Int
        v12 -- ctExplNoise :: Double
        v13 -- ctTargetNoise :: Double
        v14 -- ctNoiseClip :: Double
        v15 -- ctSacAlpha :: Double
        v16 -- ctAlphaLr :: Double
        v17 -- ctTargetEntropy :: Double
        v18 -- ctPolicyStd :: Double
        v19 -- ctTqcDropPerCritic :: Int
        v20 -- ctStartSteps :: Int
        v21 -- ctTrainStart :: Int
        v22 -- ctMaxEpisodeSteps :: Int
        v23 -- ctObsSize :: Int
        v24 -- ctActionLow :: Double
        v25 -- ctActionHigh :: Double
        v26 -- ctStatInterval :: Int
        v27 -- ctEnvName :: Text
        v28 -- ctCountBeta :: Double
      ) ->
      NeuralConfigurationProjection
        "continuous"
        [ ConfigText (projectContinuousVariant v01) -- ctVariant
        , ConfigInt v02 -- ctSeed
        , ConfigInt v03 -- ctHidden
        , ConfigInt v04 -- ctNumSteps
        , ConfigInt v05 -- ctReplayCapacity
        , ConfigInt v06 -- ctBatchSize
        , ConfigWord (castDoubleToWord64 v07) -- ctActorLr
        , ConfigWord (castDoubleToWord64 v08) -- ctCriticLr
        , ConfigWord (castDoubleToWord64 v09) -- ctGamma
        , ConfigWord (castDoubleToWord64 v10) -- ctTau
        , ConfigInt v11 -- ctPolicyDelay
        , ConfigWord (castDoubleToWord64 v12) -- ctExplNoise
        , ConfigWord (castDoubleToWord64 v13) -- ctTargetNoise
        , ConfigWord (castDoubleToWord64 v14) -- ctNoiseClip
        , ConfigWord (castDoubleToWord64 v15) -- ctSacAlpha
        , ConfigWord (castDoubleToWord64 v16) -- ctAlphaLr
        , ConfigWord (castDoubleToWord64 v17) -- ctTargetEntropy
        , ConfigWord (castDoubleToWord64 v18) -- ctPolicyStd
        , ConfigInt v19 -- ctTqcDropPerCritic
        , ConfigInt v20 -- ctStartSteps
        , ConfigInt v21 -- ctTrainStart
        , ConfigInt v22 -- ctMaxEpisodeSteps
        , ConfigInt v23 -- ctObsSize
        , ConfigWord (castDoubleToWord64 v24) -- ctActionLow
        , ConfigWord (castDoubleToWord64 v25) -- ctActionHigh
        , ConfigInt v26 -- ctStatInterval
        , ConfigText v27 -- ctEnvName
        , ConfigWord (castDoubleToWord64 v28) -- ctCountBeta
        ]
  Config.HerConfiguration
    ( Her.HerTrainConfig
        v01 -- herSeed :: Int
        v02 -- herNumBits :: Int
        v03 -- herHiddenUnits :: Int
        v04 -- herEpisodes :: Int
        v05 -- herReplayCapacity :: Int
        v06 -- herBatchSize :: Int
        v07 -- herLearningRate :: Double
        v08 -- herGamma :: Double
        v09 -- herTargetUpdateInterval :: Int
        v10 -- herEpsilon :: Double
        v11 -- herUseHindsight :: Bool
        v12 -- herStrategy :: HerStrategy
        v13 -- herStatInterval :: Int
        v14 -- herUpdatesPerEpisode :: Int
      ) ->
      NeuralConfigurationProjection
        "her"
        [ ConfigInt v01 -- herSeed
        , ConfigInt v02 -- herNumBits
        , ConfigInt v03 -- herHiddenUnits
        , ConfigInt v04 -- herEpisodes
        , ConfigInt v05 -- herReplayCapacity
        , ConfigInt v06 -- herBatchSize
        , ConfigWord (castDoubleToWord64 v07) -- herLearningRate
        , ConfigWord (castDoubleToWord64 v08) -- herGamma
        , ConfigInt v09 -- herTargetUpdateInterval
        , ConfigWord (castDoubleToWord64 v10) -- herEpsilon
        , ConfigBool v11 -- herUseHindsight
        , ConfigText (projectHerStrategy v12) -- herStrategy
        , ConfigInt v13 -- herStatInterval
        , ConfigInt v14 -- herUpdatesPerEpisode
        ]

projectOnPolicyVariant :: Ppo.OnPolicyVariant -> Text
projectOnPolicyVariant variant = case variant of
  Ppo.VariantPPO -> "PPO"
  Ppo.VariantA2C -> "A2C"
  Ppo.VariantTRPO -> "TRPO"
  Ppo.VariantMaskablePPO -> "MaskablePPO"
  Ppo.VariantRecurrentPPO -> "RecurrentPPO"

projectContinuousVariant :: Continuous.ContinuousVariant -> Text
projectContinuousVariant variant = case variant of
  Continuous.VariantDDPG -> "DDPG"
  Continuous.VariantTD3 -> "TD3"
  Continuous.VariantSAC -> "SAC"
  Continuous.VariantCrossQ -> "CrossQ"
  Continuous.VariantTQC -> "TQC"

projectHerStrategy :: HerLoss.HerStrategy -> Text
projectHerStrategy strategy = case strategy of
  HerLoss.HerFuture -> "future"
  HerLoss.HerEpisode -> "episode"
  HerLoss.HerRandom -> "random"

forceConfiguration :: Config.NeuralTrainerConfiguration -> ()
forceConfiguration configuration = case projectNeuralConfiguration configuration of
  NeuralConfigurationProjection family atoms -> textValue family `seq` forceList atom atoms
 where
  atom value = case value of
    ConfigInt actual -> actual `seq` ()
    ConfigBool actual -> actual `seq` ()
    ConfigText actual -> textValue actual
    ConfigWord actual -> actual `seq` ()

forcePlan :: Plan.CompiledRlPlan -> ()
forcePlan (Plan.CompiledRlPlan training (Plan.EvaluationPlan episodes) schedule) =
  forceTraining training `seq` episodes `seq` forceMaybe forceSchedule schedule
 where
  forceTraining (Plan.TrainingPlan kind environment seed horizon floor_ vectors requested exact) =
    textValue kind `seq`
      textValue environment `seq`
        seed `seq`
          horizon `seq`
            floor_ `seq`
              forceMaybe whnf vectors `seq`
                forceMaybe whnf requested `seq`
                  forceMaybe whnf exact
  forceSchedule value = case value of
    Plan.OnPolicyTrainingSchedule count iterations rollout vectors horizon -> count `seq` iterations `seq` rollout `seq` vectors `seq` horizon `seq` ()
    Plan.FixedStepTrainingSchedule count steps horizon -> count `seq` steps `seq` horizon `seq` ()
    Plan.ArsTrainingSchedule count iterations directions horizon -> count `seq` iterations `seq` directions `seq` horizon `seq` ()
    Plan.HerTrainingSchedule count episodes_ width -> count `seq` episodes_ `seq` width `seq` ()

forceSnapshot :: NeuralSnapshot -> ()
forceSnapshot = foldNeuralSnapshot forcePpo forceDqn forceQr forceContinuous forceHer
 where
  forcePpo :: Ppo.PpoPreparedSnapshot state -> ()
  forcePpo snapshot =
    forceAll
      [ forceConfiguration (Config.OnPolicyConfiguration (Ppo.ppoPreparedConfig snapshot))
      , forceParams (Ppo.ppoPreparedInitialParams snapshot)
      , forceAdam (Ppo.ppoPreparedAdam snapshot)
      , whnf (Ppo.ppoPreparedGenerator snapshot)
      , forceMaybe whnf (Ppo.ppoPreparedSingleState snapshot)
      , forceList
          (\(state, reward, steps) -> state `seq` reward `seq` steps `seq` ())
          (Ppo.ppoPreparedVectorSlots snapshot)
      , forceList forceVector (Ppo.ppoPreparedFrames snapshot)
      , forceCounts (Ppo.ppoPreparedCountEntries snapshot)
      , forceList forcePpoStat (Ppo.ppoPreparedStatistics snapshot)
      , whnf (Ppo.ppoPreparedActorSteps snapshot)
      , whnf (Ppo.ppoPreparedTransitions snapshot)
      , textValue (Ppo.ppoPreparedEnvironmentName snapshot)
      , whnf (Ppo.ppoPreparedObservationWidth snapshot)
      , whnf (Ppo.ppoPreparedActionCount snapshot)
      ]
  forceDqn :: Dqn.DqnPreparedSnapshot state -> ()
  forceDqn snapshot =
    forceAll
      [ forceConfiguration (Config.DqnConfiguration (Dqn.dqnPreparedConfig snapshot))
      , forceParams (Dqn.dqnPreparedInitialParams snapshot)
      , forceParams (Dqn.dqnPreparedOnlineParams snapshot)
      , forceParams (Dqn.dqnPreparedTargetParams snapshot)
      , forceAdam (Dqn.dqnPreparedAdam snapshot)
      , whnf (Dqn.dqnPreparedGenerator snapshot)
      , forceList forceDqnTransition (Dqn.dqnPreparedReplay snapshot)
      , whnf (Dqn.dqnPreparedStep snapshot)
      , whnf (Dqn.dqnPreparedState snapshot)
      , whnf (Dqn.dqnPreparedEpisodeLength snapshot)
      , whnf (Dqn.dqnPreparedEpisodeReturn snapshot)
      , forceList whnf (Dqn.dqnPreparedRecentReturns snapshot)
      , forceList forceDqnStat (Dqn.dqnPreparedStatistics snapshot)
      , textValue (Dqn.dqnPreparedEnvironmentName snapshot)
      , whnf (Dqn.dqnPreparedObservationWidth snapshot)
      , whnf (Dqn.dqnPreparedActionCount snapshot)
      , forceVector (Dqn.dqnPreparedFrame snapshot)
      ]
  forceQr :: Qr.QrDqnPreparedSnapshot state -> ()
  forceQr snapshot =
    forceAll
      [ forceConfiguration (Config.QrDqnConfiguration (Qr.qrDqnPreparedConfig snapshot))
      , forceParams (Qr.qrDqnPreparedInitialParams snapshot)
      , forceParams (Qr.qrDqnPreparedOnlineParams snapshot)
      , forceParams (Qr.qrDqnPreparedTargetParams snapshot)
      , forceAdam (Qr.qrDqnPreparedAdam snapshot)
      , whnf (Qr.qrDqnPreparedGenerator snapshot)
      , forceList forceReplayTuple (Qr.qrDqnPreparedReplay snapshot)
      , whnf (Qr.qrDqnPreparedStep snapshot)
      , whnf (Qr.qrDqnPreparedState snapshot)
      , whnf (Qr.qrDqnPreparedEpisodeLength snapshot)
      , whnf (Qr.qrDqnPreparedEpisodeReturn snapshot)
      , forceList whnf (Qr.qrDqnPreparedRecentReturns snapshot)
      , forceList forceQrStat (Qr.qrDqnPreparedStatistics snapshot)
      , textValue (Qr.qrDqnPreparedEnvironmentName snapshot)
      , whnf (Qr.qrDqnPreparedObservationWidth snapshot)
      , whnf (Qr.qrDqnPreparedActionCount snapshot)
      , forceVector (Qr.qrDqnPreparedFrame snapshot)
      ]
  forceContinuous :: Continuous.ContinuousPreparedSnapshot state -> ()
  forceContinuous snapshot =
    forceAll
      [ whnf (Continuous.continuousPreparedStage snapshot)
      , forceConfiguration (Config.ContinuousConfiguration (Continuous.continuousPreparedConfig snapshot))
      , forceParams (Continuous.continuousPreparedColdActor snapshot)
      , forceParams (Continuous.continuousPreparedActor snapshot)
      , forceParams (Continuous.continuousPreparedCriticA snapshot)
      , forceParams (Continuous.continuousPreparedCriticB snapshot)
      , forceMaybe forceParams (Continuous.continuousPreparedTargetActor snapshot)
      , forceMaybe forceParams (Continuous.continuousPreparedTargetCriticA snapshot)
      , forceMaybe forceParams (Continuous.continuousPreparedTargetCriticB snapshot)
      , whnf (Continuous.continuousPreparedLogAlpha snapshot)
      , forceAdam (Continuous.continuousPreparedActorAdam snapshot)
      , forceAdam (Continuous.continuousPreparedCriticAAdam snapshot)
      , forceAdam (Continuous.continuousPreparedCriticBAdam snapshot)
      , forceMaybe forceAdam (Continuous.continuousPreparedWarmAdam snapshot)
      , whnf (Continuous.continuousPreparedGenerator snapshot)
      , forceList forceContTransition (Continuous.continuousPreparedReplay snapshot)
      , whnf (Continuous.continuousPreparedStep snapshot)
      , whnf (Continuous.continuousPreparedState snapshot)
      , whnf (Continuous.continuousPreparedEpisodeLength snapshot)
      , whnf (Continuous.continuousPreparedEpisodeReturn snapshot)
      , forceList whnf (Continuous.continuousPreparedRecentReturns snapshot)
      , forceList forceContinuousStat (Continuous.continuousPreparedStatistics snapshot)
      , textValue (Continuous.continuousPreparedEnvironmentName snapshot)
      , forceList whnf (Continuous.continuousPreparedObservation snapshot)
      , forceCounts (Continuous.continuousPreparedCountEntries snapshot)
      ]
  forceHer :: Her.HerPreparedSnapshot -> ()
  forceHer snapshot =
    forceAll
      [ forceConfiguration (Config.HerConfiguration (Her.herPreparedConfig snapshot))
      , forceParams (Her.herPreparedInitialParams snapshot)
      , forceParams (Her.herPreparedOnlineParams snapshot)
      , forceParams (Her.herPreparedTargetParams snapshot)
      , forceAdam (Her.herPreparedAdam snapshot)
      , whnf (Her.herPreparedGenerator snapshot)
      , forceList forceReplayTuple (Her.herPreparedReplay snapshot)
      , whnf (Her.herPreparedEpisode snapshot)
      , whnf (Her.herPreparedObservedTransitions snapshot)
      , forceList whnf (Her.herPreparedRecentSuccesses snapshot)
      , forceList forceHerStat (Her.herPreparedStatistics snapshot)
      ]

forceReturnedPolicy :: Observation.ReturnedPolicy -> ()
forceReturnedPolicy policy = case policy of
  Observation.ReturnedOnPolicy raw -> forceRaw (Config.OnPolicyConfiguration . Common.rawTrainerConfig) forcePpoStat raw
  Observation.ReturnedDqn raw -> forceRaw (Config.DqnConfiguration . Common.rawTrainerConfig) forceDqnStat raw
  Observation.ReturnedQrDqn raw -> forceRaw (Config.QrDqnConfiguration . Common.rawTrainerConfig) forceQrStat raw
  Observation.ReturnedContinuous raw -> forceRaw (Config.ContinuousConfiguration . Common.rawTrainerConfig) forceContinuousStat raw
  Observation.ReturnedHer raw -> forceRaw (Config.HerConfiguration . Common.rawTrainerConfig) forceHerStat raw
  Observation.ReturnedArs _ -> () -- Closed actual low dispatch never returns ARS.

forceRaw
  :: (Common.RawTrainerResult Mlp.MlpParams statistic config -> Config.NeuralTrainerConfiguration)
  -> (statistic -> ())
  -> Common.RawTrainerResult Mlp.MlpParams statistic config
  -> ()
forceRaw config statistic raw =
  forceAll
    [ forceConfiguration (config raw)
    , forceCounters (Common.rawTrainerCounters raw)
    , forceParams (Common.rawTrainerInitialParams raw)
    , forceParams (Common.rawTrainerFinalParams raw)
    , forceList statistic (Common.rawTrainerStats raw)
    ]

forceCounters :: Common.ObservedTrainerCounters -> ()
forceCounters counters =
  Common.observedEnvironmentTransitionCount counters `seq`
    Common.observedOptimizerUpdateCount counters `seq`
      ()

forceParams :: Mlp.MlpParams -> ()
forceParams params =
  Mlp.paramShape params `seq`
    forceAll
      (map forceVector [Mlp.paramW1 params, Mlp.paramB1 params, Mlp.paramW2 params, Mlp.paramB2 params])

forceAdam :: Mlp.AdamState -> ()
forceAdam adam = Mlp.adamStep_ adam `seq` forceGradient (Mlp.adamM adam) `seq` forceGradient (Mlp.adamV adam)

forceGradient :: Mlp.MlpGradient -> ()
forceGradient gradient =
  forceAll
    (map forceVector [Mlp.gradW1 gradient, Mlp.gradB1 gradient, Mlp.gradW2 gradient, Mlp.gradB2 gradient])

forcePpoStat :: Ppo.PpoIterationStat -> ()
forcePpoStat (Ppo.PpoIterationStat index mean median maximum_ episodes) = index `seq` mean `seq` median `seq` maximum_ `seq` episodes `seq` ()
forceDqnStat :: Dqn.DqnIterationStat -> ()
forceDqnStat (Dqn.DqnIterationStat step episodes mean last_) = step `seq` episodes `seq` mean `seq` last_ `seq` ()
forceQrStat :: Qr.QrDqnIterationStat -> ()
forceQrStat (Qr.QrDqnIterationStat step episodes mean) = step `seq` episodes `seq` mean `seq` ()
forceContinuousStat :: Continuous.ContinuousIterationStat -> ()
forceContinuousStat (Continuous.ContinuousIterationStat step episodes mean last_) = step `seq` episodes `seq` mean `seq` last_ `seq` ()
forceHerStat :: Her.HerIterationStat -> ()
forceHerStat (Her.HerIterationStat episode rate) = episode `seq` rate `seq` ()

forceDqnTransition :: Dqn.Transition -> ()
forceDqnTransition (Dqn.Transition state action reward next done) = forceVector state `seq` action `seq` reward `seq` forceVector next `seq` done `seq` ()
forceContTransition :: Continuous.ContTransition -> ()
forceContTransition (Continuous.ContTransition state action reward next done) = forceVector state `seq` action `seq` reward `seq` forceVector next `seq` done `seq` ()
forceReplayTuple :: (Vector Double, Int, Double, Vector Double, Bool) -> ()
forceReplayTuple (state, action, reward, next, done) = forceVector state `seq` action `seq` reward `seq` forceVector next `seq` done `seq` ()
forceCounts :: [((Int, Int), Int)] -> ()
forceCounts = forceList (\((state, action), count) -> state `seq` action `seq` count `seq` ())
forceVector :: Vector Double -> ()
forceVector = VU.foldl' (\() value -> value `seq` ()) ()
textValue :: Text -> ()
textValue value = Text.length value `seq` ()
whnf :: value -> ()
whnf value = value `seq` ()
forceList :: (value -> ()) -> [value] -> ()
forceList force = foldr (\value rest -> force value `seq` rest) ()
forceMaybe :: (value -> ()) -> Maybe value -> ()
forceMaybe = maybe ()
forceAll :: [()] -> ()
forceAll = forceList id
