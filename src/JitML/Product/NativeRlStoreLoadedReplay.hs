{-# LANGUAGE OverloadedStrings #-}

-- | Replay only the physically fetched FINAL serving weights. The initial
-- model remains the earlier, explicitly in-memory replay. No model/device/
-- evaluator callback, raw result, decoder or ACK can mint this opaque result.
module JitML.Product.NativeRlStoreLoadedReplay
  ( NativeStoreLoadedReplay
  , NativeStoreLoadedReplayFailure
  , NativeLoadedReplayReport (..)
  , NativeLoadedReplayFinding (..)
  , NativeLoadedReplayCapture (..)
  , NativeLoadedReplayDevice (..)
  , NativeLoadedReplayEvaluation (..)
  , replayNativeStoreLoadedServing
  , nativeStoreLoadedCompletedServing
  , nativeStoreLoadedAdmittedCheckpoint
  , nativeStoreLoadedCandidate
  , nativeStoreLoadedEvaluation
  , nativeStoreLoadedReport
  , nativeStoreLoadedFailureReport
  , validateNativeLoadedWeightData
  ) where

import Control.Exception (Exception, evaluate, toException)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.SchemaTable (FieldType (TText))
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weights
import JitML.Env.Env (App, Env)
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (mlpdExecutionWitness))
import JitML.Numerics.MlpDeviceSelect qualified as Select
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeRlAssessment qualified as Assessment
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlCompletedServing qualified as Completed
import JitML.Product.NativeRlEvaluationReplay qualified as Replay
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlServingCandidate qualified as Candidate
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as ArenaEvaluation
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.NativeHerEvaluation qualified as HerEvaluation
import JitML.RL.NativeReturnEvaluation qualified as ReturnEvaluation
import JitML.Substrate (Substrate)
import JitML.Training.Budget qualified as Training

data NativeLoadedReplayFinding
  = LoadedBindingRejected
  | LoadedSourceProjectionRejected
  | LoadedActualProjectionRejected
  | LoadedSourceIncomplete
  | LoadedActualIncomplete
  | LoadedCanonicalBytesDiffer
  | LoadedProcessObservationFailed
  | LoadedProcessChanged
  | LoadedDeviceEvidenceFailed
  | LoadedDeviceEvidenceMissing
  | LoadedDeviceLaneDiffers
  | LoadedDeviceIdentityDiffers
  | LoadedSynchronousFailure
  deriving stock (Eq, Show)

-- Ordinary graph DATA, fully materialized beneath the safe catcher. Equality
-- compares all canonical node bytes, never Double's numeric equality.
data NativeLoadedReplayCapture = NativeLoadedReplayCapture !Digest ![(Digest, ByteString)]
  deriving stock (Eq, Show)
data NativeLoadedReplayDevice
  = LoadedDeviceNotQueried
  | LoadedDeviceAbsent
  | LoadedHostNoMlpDevice
  | LoadedDeviceObserved !Witness.DeviceExecutionWitness
  | LoadedDeviceUnavailable !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)
data NativeLoadedReplayEvaluation
  = LoadedReturnEvaluation !ReturnEvaluation.RawNativeReturnEvaluation
  | LoadedHerEvaluation !HerEvaluation.RawNativeHerEvaluation
  | LoadedArenaEvaluation !ArenaEvaluation.RawNativeArenaEvaluation

data NativeLoadedReplayReport = NativeLoadedReplayReport
  { loadedReplayManifestSha :: !(Maybe Text)
  , loadedReplayManifestBodySha :: !(Maybe Text)
  , loadedReplayExpectedCapture :: !(Maybe NativeLoadedReplayCapture)
  , loadedReplayActualCapture :: !(Maybe NativeLoadedReplayCapture)
  , loadedReplayBeforeProcess :: !(Maybe Process.RecordedProducerObservation)
  , loadedReplayAfterProcess :: !(Maybe Process.RecordedProducerObservation)
  , loadedReplayDevice :: !NativeLoadedReplayDevice
  , loadedReplayFindings :: ![NativeLoadedReplayFinding]
  , loadedReplayDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)

-- Neither constructor is exported. A failed result retains no potentially
-- poisoned input capsule/raw handle. The success binds BOTH exact originals.
data NativeStoreLoadedReplay
  = NativeStoreLoadedReplay
      !Completed.NativeCompletedServing
      !Store.AdmittedExecutionCheckpoint
      !NativeLoadedReplayEvaluation
      !NativeLoadedReplayReport
newtype NativeStoreLoadedReplayFailure = NativeStoreLoadedReplayFailure NativeLoadedReplayReport

nativeStoreLoadedCompletedServing :: NativeStoreLoadedReplay -> Completed.NativeCompletedServing
nativeStoreLoadedCompletedServing (NativeStoreLoadedReplay actual _ _ _) = actual
nativeStoreLoadedAdmittedCheckpoint :: NativeStoreLoadedReplay -> Store.AdmittedExecutionCheckpoint
nativeStoreLoadedAdmittedCheckpoint (NativeStoreLoadedReplay _ actual _ _) = actual
nativeStoreLoadedCandidate :: NativeStoreLoadedReplay -> Candidate.NativeServingCandidate
nativeStoreLoadedCandidate = Completed.nativeCompletedCandidate . nativeStoreLoadedCompletedServing
nativeStoreLoadedEvaluation :: NativeStoreLoadedReplay -> NativeLoadedReplayEvaluation
nativeStoreLoadedEvaluation (NativeStoreLoadedReplay _ _ actual _) = actual
nativeStoreLoadedReport :: NativeStoreLoadedReplay -> NativeLoadedReplayReport
nativeStoreLoadedReport (NativeStoreLoadedReplay _ _ _ actual) = actual
nativeStoreLoadedFailureReport :: NativeStoreLoadedReplayFailure -> NativeLoadedReplayReport
nativeStoreLoadedFailureReport (NativeStoreLoadedReplayFailure actual) = actual

-- The supplied parameters are ordinary DATA. Unit-only validation never
-- admits a checkpoint or constructs a replay. The actual route derives the
-- expected name/count/values privately from its same completed candidate.
validateNativeLoadedWeightData
  :: Text -> Int -> [Double] -> [Store.LoadedWeightTensor] -> Either Text ()
validateNativeLoadedWeightData name count expected loaded = do
  require
    (count > 0 && toInteger count <= nativePhaseLimit AggregateF64Coordinates)
    "loaded weight count exceeds bounded F64 scope"
  n <- dataCount count expected
  require (n == count) "expected weight count differs from exact source shape"
  tensor <- case loaded of
    [actual] -> Right actual
    _ -> Left "loaded native policy requires exactly one physical tensor"
  let descriptor = Store.loadedWeightTensor tensor
      bytes = Store.loadedWeightJmw1Bytes tensor
  require
    (Format.tensorName descriptor == name && Format.tensorShape descriptor == [count])
    "loaded tensor name or exact flat shape differs"
  require
    (toInteger (BS.length bytes) <= 8 * toInteger count + 1024)
    "loaded JMW1 exceeds exact tensor plus bounded header scope"
  observedCount <- dataCount count (Store.loadedWeightValues tensor)
  require (observedCount == count) "loaded value count differs from source shape"
  actual <- Weights.decodeJmw1 (LBS.fromStrict bytes)
  actualCount <- dataCount count actual
  require (actualCount == count) "physical JMW1 count differs from source shape"
  require
    (sameBits actual (Store.loadedWeightValues tensor))
    "loaded values differ in F64 bits from physical JMW1"
  require
    (sameBits expected actual)
    "physical final weights differ in F64 bits from the same completed candidate"
  require
    (LBS.toStrict (Weights.encodeJmw1 expected) == bytes)
    "physical JMW1 differs from exact expected frozen representation"
 where
  dataCount cap values =
    either
      (const (Left "loaded F64 list exceeds exact shape"))
      Right
      (boundedLength AggregateF64Coordinates (toInteger cap) values)

sameBits :: [Double] -> [Double] -> Bool
sameBits left right = fmap castDoubleToWord64 left == fmap castDoubleToWord64 right
require :: Bool -> Text -> Either Text ()
require predicate reason = unless predicate (Left reason)

data LoadedModel
  = ReturnModel
      !Substrate
      !ReturnEvaluation.RawNativeReturnEvaluation
      !ReturnEvaluation.NativeEvaluationPolicy
  | HerModel !Substrate !HerEvaluation.RawNativeHerEvaluation !Mlp.MlpParams
  | ArenaModel !Substrate !ArenaEvaluation.RawNativeArenaEvaluation !Net.PolicyValueNet

emptyReport :: NativeLoadedReplayReport
emptyReport =
  NativeLoadedReplayReport
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    Nothing
    LoadedDeviceNotQueried
    []
    Nothing
type Program = ExceptT NativeLoadedReplayFinding IO
replayNativeStoreLoadedServing
  :: Completed.NativeCompletedServing
  -> Store.AdmittedExecutionCheckpoint
  -> App (Either NativeStoreLoadedReplayFailure NativeStoreLoadedReplay)
replayNativeStoreLoadedServing completed admitted = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    attempted <- tryAny (runExceptT (program report env completed admitted))
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        add report LoadedSynchronousFailure
        modifyIORef' report (\actual -> actual {loadedReplayDiagnostic = Just diagnostic})
        Left . NativeStoreLoadedReplayFailure <$> readIORef report
      Right (Left finding) -> do
        add report finding
        Left . NativeStoreLoadedReplayFailure <$> readIORef report
      Right (Right evaluation) -> do
        actual <- readIORef report
        if null (loadedReplayFindings actual)
          then pure (Right (NativeStoreLoadedReplay completed admitted evaluation actual))
          else pure (Left (NativeStoreLoadedReplayFailure actual))

program
  :: IORef NativeLoadedReplayReport
  -> Env
  -> Completed.NativeCompletedServing
  -> Store.AdmittedExecutionCheckpoint
  -> Program NativeLoadedReplayEvaluation
program report env completed admitted = do
  -- Establish explicit input-WHNF order inside the safe catcher. Pure Eq/CBOR
  -- comparisons do not otherwise promise which poisoned argument is forced.
  _ <- liftIO (evaluate completed)
  _ <- liftIO (evaluate admitted)
  model <- checked report (bindLoadedModel completed admitted)
  let base = Store.admittedExecutionCheckpoint admitted
  liftIO $
    modifyIORef'
      report
      ( \actual ->
          actual
            { loadedReplayManifestSha = Just (Store.admittedCheckpointManifestSha base)
            , loadedReplayManifestBodySha = Store.admittedCheckpointManifestBodySha base
            }
      )
  wanted <- projection report LoadedSourceProjectionRejected =<< sourceData model
  liftIO $ modifyIORef' report (\actual -> actual {loadedReplayExpectedCapture = Just wanted})
  unless (sourceComplete model) (throwError LoadedSourceIncomplete)
  before <- observeProcess report
  liftIO $
    modifyIORef'
      report
      (\actual -> actual {loadedReplayBeforeProcess = Just (Process.recordedProducerObservation before)})
  let device = case model of
        ReturnModel _ _ (ReturnEvaluation.NativeArsHostEvaluation _ _) -> Nothing
        _ -> Just (Select.rlDeviceForSubstrate (modelLane model) env)
  actual <- liftIO (evaluateLoaded device model)
  captured <- projection report LoadedActualProjectionRejected actual
  liftIO $ modifyIORef' report (\value -> value {loadedReplayActualCapture = Just captured})
  unless (evaluationComplete actual) (liftIO (add report LoadedActualIncomplete))
  unless (captured == wanted) (liftIO (add report LoadedCanonicalBytesDiffer))
  liftIO (observeDevice report (modelLane model) admitted device)
  after <- observeProcess report
  liftIO $
    modifyIORef'
      report
      (\value -> value {loadedReplayAfterProcess = Just (Process.recordedProducerObservation after)})
  case Process.compareProducerProcessObservations before after of
    Left _ -> liftIO (add report LoadedProcessChanged)
    Right () -> pure ()
  pure actual

checked :: IORef NativeLoadedReplayReport -> Either Text a -> Program a
checked report value = case value of
  Right actual -> pure actual
  Left reason -> do
    diagnostic <- liftIO (Failure.captureNativeDiagnostic reason)
    liftIO $ modifyIORef' report (\actual -> actual {loadedReplayDiagnostic = Just diagnostic})
    throwError LoadedBindingRejected

-- Completion bytes bind all criteria/evidence/invocation/budget fields without
-- a second recipe table or Eq Double. Actual Store owns physical admission.
-- Retain pair-pattern forcing: second would increase laziness.
{- HLINT ignore bindLoadedModel "Use second" -}
bindLoadedModel
  :: Completed.NativeCompletedServing -> Store.AdmittedExecutionCheckpoint -> Either Text LoadedModel
bindLoadedModel completed admitted = do
  let base = Store.admittedExecutionCheckpoint admitted
      manifest = Store.admittedCheckpointManifest base
      expected = Completed.nativeCompletedTraining completed
      observed = Store.admittedExecutionCompletedTraining admitted
      candidate = Completed.nativeCompletedCandidate completed
      produced =
        Replay.nativeEvaluationReplayedProducer
          (Assessment.nativeAssessmentReplay (Candidate.nativeServingCandidateAssessment candidate))
      loaded = Store.admittedCheckpointWeights base
      weights = Completed.nativeCompletedWeights completed
  require
    (Training.encodeCompletedTraining expected == Training.encodeCompletedTraining observed)
    "admitted completion bytes differ from the same completed serving candidate"
  require
    ( Format.manifestExperiment manifest == Completed.nativeCompletedExperiment completed
        && Format.manifestStep manifest == Completed.nativeCompletedStep completed
        && Format.manifestPlanId manifest == Just (Training.completedTrainingPlanId expected)
    )
    "admitted manifest experiment step or PlanId differs"
  actualManifestCompletion <-
    maybe (Left "admitted manifest completion absent") Right (Format.manifestCompletedTraining manifest)
  require
    ( Training.encodeCompletedTraining actualManifestCompletion
        == Training.encodeCompletedTraining expected
    )
    "admitted manifest completion differs from its capability and candidate"
  require
    ( fmap (\(key, value) -> (key, castDoubleToWord64 value)) (Format.manifestMetrics manifest)
        == fmap
          (\(key, value) -> (key, castDoubleToWord64 value))
          (sortOn fst (Completed.nativeCompletedMetrics completed))
    )
    "admitted complete metric bits/order differ"
  require
    (Format.manifestTensors manifest == fmap Store.loadedWeightTensor loaded)
    "admitted loaded tensor descriptors differ from full manifest order"
  require
    ( Format.manifestInitialWeightHash manifest
        == Just (Training.completedTrainingInitialWeightHash expected)
        && Format.manifestFinalWeightHash manifest == Just (Training.completedTrainingFinalWeightHash expected)
        && Format.manifestUpdateCount manifest == Just (Training.completedTrainingUpdateCount expected)
        && Format.manifestDatasetShaAtRead manifest
          == Just (Training.completedTrainingDatasetShaAtRead expected)
    )
    "admitted weight update or source/sample hash metadata differs"
  served <- case Producer.nativeProducedChildren produced of
    first : _
      | Cohort.nativeSeedIndexValue (Producer.nativeChildIndex (Producer.nativeProducedChildData first))
          == 0 ->
          Right first
    _ -> Left "same candidate lacks original actual serving child0"
  model <- case (Candidate.nativeServingCandidateModel candidate, Producer.nativeProducedModelData served) of
    ( Candidate.NativeReturnServingCandidateData seed _ Nothing
      , Producer.NativeNeuralNumericalData actual
      ) -> do
        let returned = Neural.nativeEvaluatedReturnedData actual
            child = Neural.nativeReturnedChild returned
            lane = Singleton.nativeSingletonSubstrate (Cohort.nativeRlSeedPlanSingleton seed)
        require (seed == Neural.nativeNeuralChildSeedPlan child) "loaded neural source seed differs"
        case Neural.nativeEvaluatedFinalEvaluation actual of
          Neural.NativeReturnEvaluation evaluation -> case ReturnEvaluation.nativeEvaluationPolicy evaluation of
            ReturnEvaluation.NativeNeuralEvaluation policy ->
              ReturnModel lane evaluation . ReturnEvaluation.NativeNeuralEvaluation
                <$> loadNeural policy weights loaded
            _ -> Left "loaded neural final evaluation has foreign policy kind"
          Neural.NativeHerEvaluation evaluation -> do
            params <- loadParams (HerEvaluation.nativeHerEvaluationParameters evaluation) weights loaded
            Right (HerModel lane evaluation params)
    ( Candidate.NativeReturnServingCandidateData seed _ (Just trace)
      , Producer.NativeArsNumericalData actual
      ) -> do
        let returned = Ars.nativeArsFinalReturned actual
            child = Ars.nativeArsReturnedChild returned
            lane = Singleton.nativeSingletonSubstrate (Cohort.nativeRlSeedPlanSingleton seed)
        require (seed == Ars.nativeArsChildSeedPlan child) "loaded ARS source seed differs"
        case Store.admittedExecutionProvenance admitted of
          ArsHostLinearExecution physical ->
            require
              (Trace.encodeArsHostTrace trace == Trace.encodeArsHostTrace (Store.admittedArsHostTrace physical))
              "admitted actual host trace differs from the same serving origin"
          _ -> Left "loaded ARS checkpoint lacks physical host admission"
        evaluation <-
          maybe (Left "loaded ARS source final evaluation absent") Right (Ars.nativeArsFinalEvaluation actual)
        case ReturnEvaluation.nativeEvaluationPolicy evaluation of
          ReturnEvaluation.NativeArsHostEvaluation config theta -> do
            require (sameBits weights (VU.toList theta)) "loaded ARS source final parameter bits differ"
            flat <- loadFlat weights loaded
            Right
              (ReturnModel lane evaluation (ReturnEvaluation.NativeArsHostEvaluation config (VU.fromList flat)))
          _ -> Left "loaded ARS source final policy differs"
    (Candidate.NativeArenaServingCandidateData seed _, Producer.NativeArenaNumericalData actual) -> do
      let returned = Arena.nativeAlphaZeroEvaluatedReturnedData actual
          child = Arena.nativeAlphaZeroReturnedChild returned
          evaluation = Arena.nativeAlphaZeroEvaluatedFinalEvaluation actual
          lane = Singleton.nativeSingletonSubstrate (Cohort.nativeRlSeedPlanSingleton seed)
      require (seed == Arena.nativeAlphaZeroChildSeedPlan child) "loaded arena source seed differs"
      input <-
        maybe
          (Left "loaded arena final input absent")
          Right
          (ArenaEvaluation.nativeArenaEvaluationInput evaluation)
      require
        (ArenaEvaluation.nativeArenaInputScope input == ArenaEvaluation.CanonicalNativeArena)
        "loaded arena input is a fixture"
      let net = ArenaEvaluation.nativeArenaInputPolicy input
      params <- loadParams (Net.pvnParams net) weights loaded
      Right (ArenaModel lane evaluation (net {Net.pvnParams = params}))
    _ -> Left "loaded model family differs from same opaque candidate"
  let family = case model of
        ArenaModel {} -> Format.AlphaZeroPolicyValueFamily
        _ -> Format.ReinforcementLearningPolicyFamily
  require
    ( Format.manifestModelFamily manifest == family
        && Format.architectureModelFamily (Format.manifestArchitecture manifest) == family
    )
    "loaded manifest architecture family differs"
  case (Completed.nativeCompletedHostTrace completed, Store.admittedExecutionProvenance admitted) of
    (Nothing, NeuralDeviceExecution _) -> Right ()
    (Just _, ArsHostLinearExecution _) -> Right ()
    _ -> Left "loaded execution provenance differs from source family"
  pure model
 where
  loadFlat expected loaded = do
    count <-
      either
        (const (Left "expected native weight allocation exceeds bounded scope"))
        Right
        (boundedLength AggregateF64Coordinates (nativePhaseLimit AggregateF64Coordinates) expected)
    validateNativeLoadedWeightData (Completed.nativeCompletedTensorName completed) count expected loaded
    case loaded of
      [tensor] -> Weights.decodeJmw1 (LBS.fromStrict (Store.loadedWeightJmw1Bytes tensor))
      _ -> Left "physical loaded tensor count differs"
  loadParams original expected loaded = do
    let shape = Mlp.paramShape original
        count =
          toInteger (Mlp.mlpHidden shape) * toInteger (Mlp.mlpInputs shape)
            + toInteger (Mlp.mlpHidden shape)
            + toInteger (Mlp.mlpOutputs shape) * toInteger (Mlp.mlpHidden shape)
            + toInteger (Mlp.mlpOutputs shape)
    require
      ( all (> 0) [Mlp.mlpInputs shape, Mlp.mlpHidden shape, Mlp.mlpOutputs shape]
          && count <= nativePhaseLimit AggregateF64Coordinates
          && count <= toInteger (maxBound :: Int)
      )
      "source dense shape exceeds exact bounded scope"
    require
      (sameBits expected (Mlp.mlpParamsToFlat original))
      "source final dense parameter bits differ from completed weights"
    flat <- loadFlat expected loaded
    mapLeft Text.pack (Mlp.mlpParamsFromFlat shape flat)
  loadNeural policy expected loaded = case policy of
    ReturnEvaluation.NativeOnPolicy config params -> ReturnEvaluation.NativeOnPolicy config <$> loadParams params expected loaded
    ReturnEvaluation.NativeDqn config params -> ReturnEvaluation.NativeDqn config <$> loadParams params expected loaded
    ReturnEvaluation.NativeQrDqn config params -> ReturnEvaluation.NativeQrDqn config <$> loadParams params expected loaded
    ReturnEvaluation.NativeContinuous config params -> ReturnEvaluation.NativeContinuous config <$> loadParams params expected loaded

modelLane :: LoadedModel -> Substrate
modelLane model = case model of ReturnModel lane _ _ -> lane; HerModel lane _ _ -> lane; ArenaModel lane _ _ -> lane
sourceData :: LoadedModel -> Program NativeLoadedReplayEvaluation
sourceData model = pure $ case model of
  ReturnModel _ value _ -> LoadedReturnEvaluation value
  HerModel _ value _ -> LoadedHerEvaluation value
  ArenaModel _ value _ -> LoadedArenaEvaluation value
sourceComplete :: LoadedModel -> Bool
sourceComplete model = case model of
  ReturnModel _ value _ -> ReturnEvaluation.nativeEvaluationStatus value == ReturnEvaluation.NativeEvaluationComplete
  HerModel _ value _ -> HerEvaluation.nativeHerEvaluationStatus value == HerEvaluation.NativeHerEvaluationComplete
  ArenaModel _ value _ ->
    ArenaEvaluation.nativeArenaEvaluationStatus value == ArenaEvaluation.NativeArenaEvaluationComplete
evaluationComplete :: NativeLoadedReplayEvaluation -> Bool
evaluationComplete value = case value of
  LoadedReturnEvaluation actual -> ReturnEvaluation.nativeEvaluationStatus actual == ReturnEvaluation.NativeEvaluationComplete
  LoadedHerEvaluation actual -> HerEvaluation.nativeHerEvaluationStatus actual == HerEvaluation.NativeHerEvaluationComplete
  LoadedArenaEvaluation actual ->
    ArenaEvaluation.nativeArenaEvaluationStatus actual == ArenaEvaluation.NativeArenaEvaluationComplete

evaluateLoaded :: Maybe MlpDevice -> LoadedModel -> IO NativeLoadedReplayEvaluation
evaluateLoaded selected model = case (selected, model) of
  (Just device, ReturnModel _ original (ReturnEvaluation.NativeNeuralEvaluation policy)) ->
    LoadedReturnEvaluation
      <$> ReturnEvaluation.evaluateNativeNeuralReturnPolicy
        device
        (ReturnEvaluation.nativeEvaluationSpec original)
        policy
  (Nothing, ReturnModel _ original (ReturnEvaluation.NativeArsHostEvaluation config theta)) ->
    LoadedReturnEvaluation
      <$> evaluate
        ( ReturnEvaluation.evaluateNativeArsReturnPolicy
            (ReturnEvaluation.nativeEvaluationSpec original)
            config
            theta
        )
  (Just device, HerModel _ original params) ->
    LoadedHerEvaluation
      <$> HerEvaluation.evaluateNativeHerPolicy
        device
        (HerEvaluation.nativeHerEvaluationSchedule original)
        (HerEvaluation.nativeHerEvaluationConfig original)
        params
  (Just device, ArenaModel _ original net) -> case ArenaEvaluation.nativeArenaEvaluationInput original of
    Just input -> case ArenaEvaluation.nativeArenaInputSpecification input of
      Just spec ->
        LoadedArenaEvaluation
          <$> ArenaEvaluation.evaluateNativeArenaPolicy
            device
            spec
            (ArenaEvaluation.nativeArenaInputTape input)
            net
      Nothing -> fail "closed canonical arena source has no specification"
    Nothing -> fail "closed canonical arena source has no input"
  _ -> fail "closed loaded model and internal device selection differ"

projection
  :: IORef NativeLoadedReplayReport
  -> NativeLoadedReplayFinding
  -> NativeLoadedReplayEvaluation
  -> Program NativeLoadedReplayCapture
projection report finding value = do
  result <- liftIO $ case value of
    LoadedReturnEvaluation actual -> Project.projectReturnEvaluationData Graph.emptyNodePool actual
    LoadedHerEvaluation actual -> Project.projectHerEvaluationData Graph.emptyNodePool actual
    LoadedArenaEvaluation actual -> Project.projectArenaEvaluationData Graph.emptyNodePool actual
  case result of
    Left problem -> do
      diagnostic <-
        liftIO (Failure.captureNativeExceptionDiagnostic (toException (ProjectionException problem)))
      liftIO $ modifyIORef' report (\actual -> actual {loadedReplayDiagnostic = Just diagnostic})
      throwError finding
    Right (root, pool) -> case Graph.validateReachableData [root] pool >> Graph.reachableNodePool [root] pool of
      Left problem -> do
        diagnostic <-
          liftIO (Failure.captureNativeExceptionDiagnostic (toException (GraphException problem)))
        liftIO $ modifyIORef' report (\actual -> actual {loadedReplayDiagnostic = Just diagnostic})
        throwError finding
      Right exact -> do
        let entries = [(digest, bytes) | (digest, _, bytes) <- Graph.nodePoolEntries exact]
        _ <- liftIO (evaluate (sum [toInteger (BS.length bytes) | (_, bytes) <- entries]))
        pure (NativeLoadedReplayCapture root entries)

-- Keep the exception constructor boundary; newtype changes bottom semantics.
{- HLINT ignore ProjectionException "Use newtype instead of data" -}
data ProjectionException = ProjectionException Project.ProjectionFailure deriving stock (Show)
instance Exception ProjectionException

-- Keep the exception constructor boundary; newtype changes bottom semantics.
{- HLINT ignore GraphException "Use newtype instead of data" -}
data GraphException = GraphException CodecError deriving stock (Show)
instance Exception GraphException

-- Keep the exception constructor boundary; newtype changes bottom semantics.
{- HLINT ignore ProcessException "Use newtype instead of data" -}
data ProcessException = ProcessException Process.ProducerObservationError deriving stock (Show)
instance Exception ProcessException

observeProcess :: IORef NativeLoadedReplayReport -> Program Process.ObservedProducerProcess
observeProcess report = do
  observed <- liftIO (Process.observeProducerProcess Process.NoSourceObservation)
  case observed of
    Right value -> pure value
    Left problem -> do
      diagnostic <-
        liftIO (Failure.captureNativeExceptionDiagnostic (toException (ProcessException problem)))
      liftIO $ modifyIORef' report (\actual -> actual {loadedReplayDiagnostic = Just diagnostic})
      throwError LoadedProcessObservationFailed

observeDevice
  :: IORef NativeLoadedReplayReport
  -> Substrate
  -> Store.AdmittedExecutionCheckpoint
  -> Maybe MlpDevice
  -> IO ()
observeDevice report lane admitted selected = case selected of
  Nothing -> modifyIORef' report (\actual -> actual {loadedReplayDevice = LoadedHostNoMlpDevice})
  Just device -> do
    attempted <- tryAny $ do
      returned <- mlpdExecutionWitness device
      case returned of
        Left reason -> do
          diagnostic <- Failure.captureNativeDiagnostic reason
          modifyIORef' report (\actual -> actual {loadedReplayDevice = LoadedDeviceUnavailable diagnostic})
          add report LoadedDeviceEvidenceFailed
        Right Nothing -> do
          modifyIORef' report (\actual -> actual {loadedReplayDevice = LoadedDeviceAbsent})
          add report LoadedDeviceEvidenceMissing
        Right (Just witness) -> do
          let raw = Witness.deviceExecutionWitnessToRaw witness
              valid = do
                mapM_
                  (Schema.validateValue (TText GeneralTextBytes 1024) . VText)
                  [ Witness.rawWitnessSubstrate raw
                  , Witness.rawWitnessBackend raw
                  , Witness.rawWitnessKernelHash raw
                  , Witness.rawWitnessArtifactSha256 raw
                  , Witness.rawWitnessExecutedIdentity raw
                  ]
                Schema.validateValue (TText PathTextBytes 4096) (VText (Witness.rawWitnessArtifactPath raw))
          case valid of
            Left problem -> do
              diagnostic <- Failure.captureNativeExceptionDiagnostic (toException (GraphException problem))
              modifyIORef' report (\actual -> actual {loadedReplayDevice = LoadedDeviceUnavailable diagnostic})
              add report LoadedDeviceEvidenceFailed
            Right () -> do
              modifyIORef' report (\actual -> actual {loadedReplayDevice = LoadedDeviceObserved witness})
              unless (Witness.witnessSubstrate witness == lane) (add report LoadedDeviceLaneDiffers)
              case Store.admittedExecutionProvenance admitted of
                NeuralDeviceExecution original ->
                  unless
                    (Witness.deviceExecutionWitnessToRaw original == raw)
                    (add report LoadedDeviceIdentityDiffers)
                _ -> add report LoadedDeviceIdentityDiffers
    case attempted of
      Right () -> pure ()
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef' report (\actual -> actual {loadedReplayDevice = LoadedDeviceUnavailable diagnostic})
        add report LoadedDeviceEvidenceFailed

add :: IORef NativeLoadedReplayReport -> NativeLoadedReplayFinding -> IO ()
add report finding =
  modifyIORef'
    report
    (\actual -> actual {loadedReplayFindings = loadedReplayFindings actual <> [finding]})
