{-# LANGUAGE OverloadedStrings #-}

-- | Actual parent-selected evaluation and actual admitted final-weight replay.
-- No device/evaluator/fetch/model callback is supplied. Recorded DATA never
-- restores a producer, initialization, training, ACK or parent authentication.
module JitML.Product.NativeParentEvaluationReplay
  ( NativeParentEvaluatedCohort
  , NativeParentEvaluationFailure
  , NativeParentEvaluationReport (..)
  , NativeParentEvaluationItem (..)
  , NativeParentEvaluationStage (..)
  , NativeParentEvaluationItemStatus (..)
  , NativeParentEvaluationCapture (..)
  , NativeParentEvaluationDevice (..)
  , NativeParentReferenceStatus (..)
  , NativeParentActualEvaluation (..)
  , replayNativeParentPolicyEvaluations
  , nativeParentEvaluatedPolicy
  , nativeParentEvaluatedCheckpoint
  , nativeParentEvaluationReport
  , nativeParentEvaluationFailureReport
  ) where

import Control.Exception (Exception, evaluate, toException)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentPolicyData qualified as Policy
import JitML.Checkpoint.NativeParentPolicyData.Lineage qualified as Lineage
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReferences qualified as References
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.WeightCodec qualified as Weights
import JitML.Env.Env (App, Env)
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (mlpdExecutionWitness))
import JitML.Numerics.MlpDeviceSelect qualified as Select
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeArenaLearningPolicy qualified as ArenaPolicy
import JitML.Product.NativeParentCompletionData qualified as Completion
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlStoreLoadedReplay qualified as Loaded
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.NativeHerEvaluation qualified as Her
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.ProductBudget qualified as Budget
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Substrate (Substrate, renderSubstrate)
import JitML.Training.Budget qualified as Training

data NativeParentEvaluationStage
  = ParentEvaluationInput
  | ParentEvaluationBinding
  | ParentEvaluationBeforeProcess
  | ParentEvaluationReferences
  | ParentEvaluationRunning !Int
  | ParentEvaluationAfterProcess
  | ParentEvaluationFinished
  deriving stock (Eq, Show)
data NativeParentEvaluationItemStatus
  = ParentEvaluationNotRun
  | ParentEvaluationStarted
  | ParentEvaluationMatched
  deriving stock (Eq, Show)
data NativeParentEvaluationCapture = NativeParentEvaluationCapture !Digest ![(Digest, ByteString)]
  deriving stock (Eq, Show)
data NativeParentEvaluationDevice
  = ParentEvaluationDeviceNotQueried
  | ParentEvaluationHostNoMlp
  | ParentEvaluationDeviceQueryStarted
  | ParentEvaluationDeviceQueryFailed !Failure.NativeDiagnosticData
  | ParentEvaluationDeviceQueryMissing
  | ParentEvaluationDeviceObserved !Witness.DeviceExecutionWitness
  deriving stock (Eq, Show)
data NativeParentReferenceStatus
  = ParentReferenceNotChecked
  | ParentReferenceNotApplicable
  | ParentReferenceMatched !Digest
  deriving stock (Eq, Show)
data NativeParentEvaluationItem = NativeParentEvaluationItem
  { parentEvaluationOrdinal :: !Int
  , parentEvaluationStatus :: !NativeParentEvaluationItemStatus
  , parentEvaluationExpectedStage :: !Replay.NativeReplayObjectStage
  , parentEvaluationExpectedIndex :: !Int
  , parentEvaluationExpectedRoot :: !Digest
  , parentEvaluationActualRaw :: !(Maybe NativeParentActualEvaluation)
  , parentEvaluationActualCapture :: !(Maybe NativeParentEvaluationCapture)
  , parentEvaluationDevice :: !NativeParentEvaluationDevice
  }
  deriving stock (Eq, Show)
data NativeParentEvaluationReport = NativeParentEvaluationReport
  { parentEvaluationStage :: !NativeParentEvaluationStage
  , parentEvaluationBeforeProcess :: !(Maybe Process.RecordedProducerObservation)
  , parentEvaluationAfterProcess :: !(Maybe Process.RecordedProducerObservation)
  , parentEvaluationArenaReferenceStatus :: !NativeParentReferenceStatus
  , parentEvaluationItems :: ![NativeParentEvaluationItem]
  , parentEvaluationRefusal :: !(Maybe Text)
  , parentEvaluationDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)
data NativeParentEvaluatedCohort
  = NativeParentEvaluatedCohort
      !Policy.NativeParentPolicyData
      !Store.AdmittedExecutionCheckpoint
      !NativeParentEvaluationReport
newtype NativeParentEvaluationFailure = NativeParentEvaluationFailure NativeParentEvaluationReport

nativeParentEvaluatedPolicy :: NativeParentEvaluatedCohort -> Policy.NativeParentPolicyData
nativeParentEvaluatedPolicy (NativeParentEvaluatedCohort actual _ _) = actual
nativeParentEvaluatedCheckpoint :: NativeParentEvaluatedCohort -> Store.AdmittedExecutionCheckpoint
nativeParentEvaluatedCheckpoint (NativeParentEvaluatedCohort _ actual _) = actual
nativeParentEvaluationReport :: NativeParentEvaluatedCohort -> NativeParentEvaluationReport
nativeParentEvaluationReport (NativeParentEvaluatedCohort _ _ actual) = actual
nativeParentEvaluationFailureReport :: NativeParentEvaluationFailure -> NativeParentEvaluationReport
nativeParentEvaluationFailureReport (NativeParentEvaluationFailure actual) = actual

data Model
  = ReturnModel !Return.RawNativeReturnEvaluation !Return.NativeEvaluationPolicy
  | HerModel !Her.RawNativeHerEvaluation !Mlp.MlpParams
  | ArenaModel !Arena.RawNativeArenaEvaluation !Net.PolicyValueNet
data Work = Work !Replay.NativeReplayObjectData !Policy.NativeDeviceObservationData !Model
data NativeParentActualEvaluation
  = ActualReturn !Return.RawNativeReturnEvaluation
  | ActualHer !Her.RawNativeHerEvaluation
  | ActualArena !Arena.RawNativeArenaEvaluation
  deriving stock (Eq, Show)
type Program = ExceptT Text App
emptyReport :: NativeParentEvaluationReport
emptyReport =
  NativeParentEvaluationReport
    ParentEvaluationInput
    Nothing
    Nothing
    ParentReferenceNotChecked
    []
    Nothing
    Nothing

-- This actual IO result proves only these evaluations and same admitted final
-- weights. The higher parent still owns source/build/launch/attempt-ledger
-- authentication, original physical acquisition and final Report admission.
replayNativeParentPolicyEvaluations
  :: Policy.NativeParentPolicyData
  -> Store.AdmittedExecutionCheckpoint
  -> App (Either NativeParentEvaluationFailure NativeParentEvaluatedCohort)
replayNativeParentPolicyEvaluations policy admitted = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    attempted <- tryAny (runReaderT (runExceptT (program report env policy admitted)) env)
    case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \actual ->
              actual
                { parentEvaluationRefusal = Just "synchronous actual parent evaluation failure"
                , parentEvaluationDiagnostic = Just diagnostic
                }
          )
        Left . NativeParentEvaluationFailure <$> readIORef report
      Right (Left reason) -> do
        diagnostic <- Failure.captureNativeDiagnostic reason
        modifyIORef'
          report
          ( \actual ->
              actual
                { parentEvaluationRefusal = Just reason
                , parentEvaluationDiagnostic = case parentEvaluationDiagnostic actual of
                    Just original -> Just original
                    Nothing -> Just diagnostic
                }
          )
        Left . NativeParentEvaluationFailure <$> readIORef report
      Right (Right ()) -> Right . NativeParentEvaluatedCohort policy admitted <$> readIORef report

-- Keep base zipWith and the explicit zero-based ordinal stream.
{- HLINT ignore program "Use zipWithFrom" -}
program
  :: IORef NativeParentEvaluationReport
  -> Env
  -> Policy.NativeParentPolicyData
  -> Store.AdmittedExecutionCheckpoint
  -> Program ()
program report env policy admitted = do
  _ <- liftIO (evaluate policy)
  _ <- liftIO (evaluate admitted)
  stage report ParentEvaluationBinding
  require
    (null (Policy.nativeParentPolicyFindings policy))
    "parent recorded mathematical cohort retains learning findings"
  let binding = Policy.nativeParentPolicyBinding policy
      cohort = Binding.nativeParentBindingCohort binding
      metadata = Metadata.nativeQualificationReceiptFields (Binding.nativeParentBindingMetadata binding)
      children = Policy.nativeParentPolicyChildren policy
      replays = Binding.nativeParentBindingReplays binding
      lane =
        Singleton.nativeSingletonSubstrate
          (Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort))
  require
    (map childIndex children == [0 .. 4] && length replays == 11)
    "parent actual replay requires all original five children and eleven exact graph records"
  update report (\actual -> actual {parentEvaluationItems = zipWith initialItem [0 ..] replays})
  checked (Completion.checkNativeParentCompletionData policy admitted)
  checked (bindAdmitted cohort metadata admitted)
  memory <- concat <$> checked (traverse childModels children)
  require (length memory == 10) "parent decoded numerical model denominator differs"
  loaded <- case children of
    served : _ -> checked (loadedModel cohort metadata admitted served)
    [] -> throwError "parent actual replay has no original serving child"
  let models = memory <> [loaded]
      work = zipWith (\expected (device, model) -> Work expected device model) replays models
  stage report ParentEvaluationBeforeProcess
  before <- observe report
  update
    report
    ( \actual -> actual {parentEvaluationBeforeProcess = Just (Process.recordedProducerObservation before)}
    )
  stage report ParentEvaluationReferences
  replayArenaReferences report binding children
  mapM_ (uncurry (runOne report env lane)) (zip [0 ..] work)
  stage report ParentEvaluationAfterProcess
  after <- observe report
  update
    report
    (\actual -> actual {parentEvaluationAfterProcess = Just (Process.recordedProducerObservation after)})
  either
    (const (throwError "actual parent process changed during evaluation replay"))
    pure
    (Process.compareProducerProcessObservations before after)
  stage report ParentEvaluationFinished

initialItem :: Int -> Replay.NativeReplayObjectData -> NativeParentEvaluationItem
initialItem ordinal expected =
  NativeParentEvaluationItem
    ordinal
    ParentEvaluationNotRun
    (Replay.nativeReplayObjectStage expected)
    (fromIntegral (Replay.nativeReplayObjectIndex expected))
    (Replay.nativeReplayObjectRoot expected)
    Nothing
    Nothing
    ParentEvaluationDeviceNotQueried
childIndex :: Policy.NativeParentChildPolicyData -> Int
childIndex value = case value of
  Policy.NativeParentReturnChild index _ _ _ _ _ _ -> index
  Policy.NativeParentHerChild index _ _ _ _ _ -> index
  Policy.NativeParentArenaChild index _ _ _ _ _ -> index
childModels
  :: Policy.NativeParentChildPolicyData -> Either Text [(Policy.NativeDeviceObservationData, Model)]
childModels value = case value of
  Policy.NativeParentReturnChild _ _ first last_ _ device _ ->
    Right
      [ (device, ReturnModel first (Return.nativeEvaluationPolicy first))
      , (device, ReturnModel last_ (Return.nativeEvaluationPolicy last_))
      ]
  Policy.NativeParentHerChild _ _ first last_ _ device ->
    Right
      [ (device, HerModel first (Her.nativeHerEvaluationParameters first))
      , (device, HerModel last_ (Her.nativeHerEvaluationParameters last_))
      ]
  Policy.NativeParentArenaChild _ _ first last_ _ device -> do
    firstNet <- arenaNet first
    lastNet <- arenaNet last_
    Right [(device, ArenaModel first firstNet), (device, ArenaModel last_ lastNet)]
 where
  arenaNet actual = case Arena.nativeArenaEvaluationInput actual of
    Just input -> Right (Arena.nativeArenaInputPolicy input)
    Nothing -> Left "validated complete parent arena evaluation has no input"

-- Neutral-MCTS reference distributions are freshly calculated here. The
-- recorded policy audit establishes legal/rule/tape DATA, but deliberately
-- cannot restore a reference calibration capability from recorded outputs.
replayArenaReferences
  :: IORef NativeParentEvaluationReport
  -> Binding.NativeParentBindingData
  -> [Policy.NativeParentChildPolicyData]
  -> Program ()
replayArenaReferences report binding children = case children of
  Policy.NativeParentArenaChild _ _ initial _ _ _ : _ -> do
    input <-
      maybe
        (throwError "parent initial arena input absent")
        pure
        (Arena.nativeArenaEvaluationInput initial)
    spec <-
      maybe
        (throwError "parent canonical arena specification absent")
        pure
        (Arena.nativeArenaInputSpecification input)
    calibration <-
      liftIO
        (ArenaPolicy.observeNativeArenaReferenceCalibrationOnTape spec (Arena.nativeArenaInputTape input))
        >>= checked
    let original = Acquisition.acquisitionReferences (Binding.nativeParentBindingAcquisition binding)
    reconstructed <-
      either
        (const (throwError "fresh actual arena reference envelope refused"))
        pure
        ( References.encodeNativeArenaReferencesData
            (References.nativeReferenceDataCohortId original)
            (References.nativeReferenceDataCohortTransport original)
            (References.nativeReferenceDataSpecRoot original)
            (References.nativeReferenceDataSpecPool original)
            (ArenaPolicy.nativeArenaCalibrationReferences calibration)
        )
    require
      (References.nativeReferenceDataBytes reconstructed == References.nativeReferenceDataBytes original)
      "fresh actual Neutral-MCTS reference distributions differ from complete retained bytes"
    update
      report
      ( \actual ->
          actual
            { parentEvaluationArenaReferenceStatus =
                ParentReferenceMatched (hashBytes (References.nativeReferenceDataBytes reconstructed))
            }
      )
  _ ->
    update
      report
      (\actual -> actual {parentEvaluationArenaReferenceStatus = ParentReferenceNotApplicable})

runOne :: IORef NativeParentEvaluationReport -> Env -> Substrate -> Int -> Work -> Program ()
runOne report env lane ordinal (Work expected expectedDevice model) = do
  stage report (ParentEvaluationRunning ordinal)
  item report ordinal (\value -> value {parentEvaluationStatus = ParentEvaluationStarted})
  let selected = case model of
        ReturnModel _ (Return.NativeArsHostEvaluation _ _) -> Nothing
        _ -> Just (Select.rlDeviceForSubstrate lane env)
  actual <- liftIO (evaluateModel selected model)
  item report ordinal (\value -> value {parentEvaluationActualRaw = Just actual})
  captured <- projectActual report actual
  item report ordinal (\value -> value {parentEvaluationActualCapture = Just captured})
  require (complete actual) "actual parent selected evaluation did not complete"
  require
    ( captured
        == NativeParentEvaluationCapture
          (Replay.nativeReplayObjectRoot expected)
          (Replay.nativeReplayObjectEntries expected)
    )
    "actual parent selected evaluation root or full canonical node bytes differ"
  case (selected, expectedDevice) of
    (Nothing, Policy.NativeHostNoMlpData) ->
      item report ordinal (\value -> value {parentEvaluationDevice = ParentEvaluationHostNoMlp})
    (Just device, Policy.NativeRecordedDeviceData original) -> do
      item report ordinal (\value -> value {parentEvaluationDevice = ParentEvaluationDeviceQueryStarted})
      observed <- liftIO (mlpdExecutionWitness device)
      witness <- case observed of
        Left reason -> do
          diagnostic <- liftIO (Failure.captureNativeDiagnostic reason)
          item
            report
            ordinal
            (\value -> value {parentEvaluationDevice = ParentEvaluationDeviceQueryFailed diagnostic})
          update report (\value -> value {parentEvaluationDiagnostic = Just diagnostic})
          throwError "actual parent selected device witness query failed"
        Right Nothing -> do
          item report ordinal (\value -> value {parentEvaluationDevice = ParentEvaluationDeviceQueryMissing})
          throwError "actual parent selected device supplied no execution witness"
        Right (Just actualWitness) -> pure actualWitness
      item
        report
        ordinal
        (\value -> value {parentEvaluationDevice = ParentEvaluationDeviceObserved witness})
      require
        (Witness.witnessSubstrate witness == lane && Witness.deviceExecutionWitnessToRaw witness == original)
        "actual parent witness lane or all six recorded artifact identity fields differ"
    _ -> throwError "actual parent model device selection differs from recorded family"
  item report ordinal (\value -> value {parentEvaluationStatus = ParentEvaluationMatched})

evaluateModel :: Maybe MlpDevice -> Model -> IO NativeParentActualEvaluation
evaluateModel selected model = case (selected, model) of
  (Just device, ReturnModel source (Return.NativeNeuralEvaluation supplied)) ->
    ActualReturn
      <$> Return.evaluateNativeNeuralReturnPolicy device (Return.nativeEvaluationSpec source) supplied
  (Nothing, ReturnModel source (Return.NativeArsHostEvaluation config theta)) ->
    ActualReturn
      <$> evaluate (Return.evaluateNativeArsReturnPolicy (Return.nativeEvaluationSpec source) config theta)
  (Just device, HerModel source params) ->
    ActualHer
      <$> Her.evaluateNativeHerPolicy
        device
        (Her.nativeHerEvaluationSchedule source)
        (Her.nativeHerEvaluationConfig source)
        params
  (Just device, ArenaModel source net) -> case Arena.nativeArenaEvaluationInput source of
    Just input -> case Arena.nativeArenaInputSpecification input of
      Just spec ->
        ActualArena <$> Arena.evaluateNativeArenaPolicy device spec (Arena.nativeArenaInputTape input) net
      Nothing -> fail "canonical parent arena evaluation has no specification"
    Nothing -> fail "canonical parent arena evaluation has no input"
  _ -> fail "closed actual parent model and selected device differ"
complete :: NativeParentActualEvaluation -> Bool
complete value = case value of
  ActualReturn actual -> Return.nativeEvaluationStatus actual == Return.NativeEvaluationComplete
  ActualHer actual -> Her.nativeHerEvaluationStatus actual == Her.NativeHerEvaluationComplete
  ActualArena actual -> Arena.nativeArenaEvaluationStatus actual == Arena.NativeArenaEvaluationComplete

-- Preserve the boxed exception boundary and its existing forcing behavior.
{- HLINT ignore ProjectionProblem "Use newtype instead of data" -}
data ProjectionProblem = ProjectionProblem Project.ProjectionFailure deriving stock (Show)
instance Exception ProjectionProblem

-- Preserve the boxed exception boundary and its existing forcing behavior.
{- HLINT ignore GraphProblem "Use newtype instead of data" -}
data GraphProblem = GraphProblem CodecError deriving stock (Show)
instance Exception GraphProblem
projectActual
  :: IORef NativeParentEvaluationReport
  -> NativeParentActualEvaluation
  -> Program NativeParentEvaluationCapture
projectActual report value = do
  projected <- liftIO $ case value of
    ActualReturn actual -> Project.projectReturnEvaluationData Graph.emptyNodePool actual
    ActualHer actual -> Project.projectHerEvaluationData Graph.emptyNodePool actual
    ActualArena actual -> Project.projectArenaEvaluationData Graph.emptyNodePool actual
  (root, pool) <- case projected of
    Right actual -> pure actual
    Left failure -> do
      diagnostic <-
        liftIO (Failure.captureNativeExceptionDiagnostic (toException (ProjectionProblem failure)))
      update report (\actual -> actual {parentEvaluationDiagnostic = Just diagnostic})
      throwError "actual parent evaluation projection refused"
  selected <- case Graph.validateReachableData [root] pool >> Graph.reachableNodePool [root] pool of
    Right actual -> pure actual
    Left failure -> do
      diagnostic <- liftIO (Failure.captureNativeExceptionDiagnostic (toException (GraphProblem failure)))
      update report (\actual -> actual {parentEvaluationDiagnostic = Just diagnostic})
      throwError "actual parent evaluation graph refused"
  let entries = [(digest, bytes) | (digest, _, bytes) <- Graph.nodePoolEntries selected]
  _ <- liftIO (evaluate (sum [toInteger (BS.length bytes) | (_, bytes) <- entries]))
  pure (NativeParentEvaluationCapture root entries)

bindAdmitted
  :: Cohort.NativeRlCohortPlan
  -> Metadata.NativeQualificationReceiptFields
  -> Store.AdmittedExecutionCheckpoint
  -> Either Text ()
bindAdmitted cohort metadata admitted = do
  let base = Store.admittedExecutionCheckpoint admitted
      manifest = Store.admittedCheckpointManifest base
      completed = Store.admittedExecutionCompletedTraining admitted
      served = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
  manifestDigest <-
    mapLeft
      (Text.pack . show)
      (Context.digestFromCanonicalText (Store.admittedCheckpointManifestSha base))
  requireData
    ( Metadata.nativeReceiptManifest metadata == manifestDigest
        && Metadata.nativeReceiptCompletedTrainingBytes metadata == Training.encodeCompletedTraining completed
    )
    "parent actual addressed checkpoint differs from exact metadata manifest or completion"
  requireData
    ( Format.manifestExperiment manifest == Singleton.nativeSingletonExperiment served
        && Format.manifestPlanId manifest == Just (Singleton.nativeSingletonPlanId served)
        && Training.completedTrainingPlanId completed == Singleton.nativeSingletonPlanId served
        && Training.completedTrainingBudget completed
          == Cohort.nativeRlSeedPlanTrainingBudget (Cohort.nativeRlCohortServingChild cohort)
    )
    "parent actual checkpoint differs from current whole serving plan experiment or budget"
  requireData
    ( Format.manifestTensors manifest
        == map Store.loadedWeightTensor (Store.admittedCheckpointWeights base)
    )
    "parent actual loaded tensors differ from the full admitted manifest order"
  actualCompletion <-
    maybe
      (Left "parent admitted manifest has no completion")
      Right
      (Format.manifestCompletedTraining manifest)
  requireData
    (Training.encodeCompletedTraining actualCompletion == Training.encodeCompletedTraining completed)
    "parent admitted manifest and actual capability completion bytes differ"

loadedModel
  :: Cohort.NativeRlCohortPlan
  -> Metadata.NativeQualificationReceiptFields
  -> Store.AdmittedExecutionCheckpoint
  -> Policy.NativeParentChildPolicyData
  -> Either Text (Policy.NativeDeviceObservationData, Model)
loadedModel cohort metadata admitted child = do
  requireData (childIndex child == 0) "parent physical serving model is not original child0"
  let loaded = Store.admittedCheckpointWeights (Store.admittedExecutionCheckpoint admitted)
      row = Matrix.rowClass (Cohort.nativeRlCohortPlanRow cohort)
      tensor = case row of
        Matrix.RlAlgorithmEnvironment algorithm _ -> "rl-" <> Text.toLower algorithm <> "-weights"
        Matrix.RlGoalConditioned _ -> "rl-her-weights"
        Matrix.AlphaZeroGame game -> "alphazero-" <> game <> "-policy-value-weights"
        _ -> ""
  case child of
    Policy.NativeParentReturnChild _ _ _ final returned device lineages -> do
      let expected = Observation.returnedFinalWeights returned
      flat <- loadFlat tensor expected loaded
      case (Return.nativeEvaluationPolicy final, Store.admittedExecutionProvenance admitted, returned) of
        ( Return.NativeArsHostEvaluation config _
          , ArsHostLinearExecution trace
          , Observation.ReturnedArs observation
          ) -> do
            expectedTrace <- expectedArsTrace cohort metadata observation lineages
            requireData
              ( Trace.encodeArsHostTrace expectedTrace
                  == Trace.encodeArsHostTrace (Store.admittedArsHostTrace trace)
              )
              "parent physical ARS trace differs from full original raw observation context and applied-step lineage"
            pure (device, ReturnModel final (Return.NativeArsHostEvaluation config (VU.fromList flat)))
        (Return.NativeNeuralEvaluation supplied, NeuralDeviceExecution _, _) -> do
          actual <- loadNeural supplied flat
          pure (device, ReturnModel final (Return.NativeNeuralEvaluation actual))
        _ -> Left "parent actual admitted execution provenance differs from RETURN family"
    Policy.NativeParentHerChild _ _ _ final returned device -> do
      requireNeural admitted
      flat <- loadFlat tensor (Observation.returnedFinalWeights returned) loaded
      params <- fromFlat (Her.nativeHerEvaluationParameters final) flat
      pure (device, HerModel final params)
    Policy.NativeParentArenaChild _ _ _ final _ device -> do
      requireNeural admitted
      input <-
        maybe
          (Left "parent complete final arena input absent")
          Right
          (Arena.nativeArenaEvaluationInput final)
      let net = Arena.nativeArenaInputPolicy input
      flat <- loadFlat tensor (Net.policyValueNetToFlat net) loaded
      params <- fromFlat (Net.pvnParams net) flat
      pure (device, ArenaModel final (net {Net.pvnParams = params}))
 where
  loadFlat tensor expected loaded = do
    count <-
      mapLeft
        (Text.pack . show)
        (boundedLength AggregateF64Coordinates (nativePhaseLimit AggregateF64Coordinates) expected)
    Loaded.validateNativeLoadedWeightData tensor count expected loaded
    case loaded of
      [actual] -> Weights.decodeJmw1 (LBS.fromStrict (Store.loadedWeightJmw1Bytes actual))
      _ -> Left "parent final physical tensor count differs"
  fromFlat original flat = mapLeft Text.pack (Mlp.mlpParamsFromFlat (Mlp.paramShape original) flat)
  loadNeural supplied flat = case supplied of
    Return.NativeOnPolicy config original -> Return.NativeOnPolicy config <$> fromFlat original flat
    Return.NativeDqn config original -> Return.NativeDqn config <$> fromFlat original flat
    Return.NativeQrDqn config original -> Return.NativeQrDqn config <$> fromFlat original flat
    Return.NativeContinuous config original -> Return.NativeContinuous config <$> fromFlat original flat
  requireNeural value = case Store.admittedExecutionProvenance value of
    NeuralDeviceExecution _ -> Right ()
    _ -> Left "parent neural model has a host-linear admitted provenance"

expectedArsTrace
  :: Cohort.NativeRlCohortPlan
  -> Metadata.NativeQualificationReceiptFields
  -> Ars.ArsTrainObservation
  -> [Lineage.NativeArsLineageData]
  -> Either Text Trace.ArsHostTrace
expectedArsTrace cohort metadata observation lineages = do
  origin <- case lineages of
    [_begun, actual] | isJust (Lineage.nativeLineageAfter actual) -> Right actual
    _ -> Left "parent physical ARS requires original begun and complete origin DATA"
  runtime <-
    maybe (Left "parent original ARS origin runtime absent") Right (Lineage.nativeLineageRuntime origin)
  let served = Cohort.nativeRlCohortServingChild cohort
      singleton = Cohort.nativeRlSeedPlanSingleton served
      before = Lineage.nativeLineageBefore origin
  compiled <-
    maybe
      (Left "parent original ARS serving child has no compiled recipe")
      Right
      (Cohort.nativeRlSeedPlanCompiledReturn served)
  source <- case (Metadata.nativeReceiptObservedSource metadata, Metadata.nativeReceiptSuppliedSource metadata) of
    (Just actual, _) -> Right actual
    (_, Just actual) -> Right actual
    _ -> Left "parent original ARS has no source coverage role"
  invocation <- case Metadata.nativeReceiptAssociation metadata of
    Metadata.NativeReceiptScenarioData actual -> Training.parseProductScenarioInvocation actual
    _ -> Left "parent physical serving validation currently requires its issued scenario association"
  let context =
        Trace.RawArsHostContext
          { Trace.rawArsHostRowId = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
          , Trace.rawArsHostExperiment = Singleton.nativeSingletonExperiment singleton
          , Trace.rawArsHostPlanId = Plan.planIdText (Singleton.nativeSingletonPlanId singleton)
          , Trace.rawArsHostCompiledTransport = Budget.renderCompiledRlPlanTransport compiled
          , Trace.rawArsHostLane = renderSubstrate (Singleton.nativeSingletonSubstrate singleton)
          , Trace.rawArsHostSourceSha256 = Source.stampSha256 source
          , Trace.rawArsHostExecutableSha256 = Process.recordedExecutableFileSha256 before
          , Trace.rawArsHostInvocationSha256 = Training.productScenarioInvocationDigest invocation
          , Trace.rawArsHostExecutionBinding = "product-scenario-invocation-v1"
          , Trace.rawArsHostKernelOS = Process.recordedKernelOperatingSystem before
          , Trace.rawArsHostKernelMachine = Process.recordedKernelMachine before
          , Trace.rawArsHostKernelRelease = Process.recordedKernelRelease before
          , Trace.rawArsHostSimulatorContract =
              "jitml-known-discrete-simulator-ars-v1:" <> Budget.compiledRlEnvironment compiled
          , Trace.rawArsHostProcessId = Text.pack (show (Process.recordedProcessId before))
          , Trace.rawArsHostAttemptId = Lineage.nativeLineageInnerAttempt origin
          }
  -- This public trace is ordinary mathematical DATA, never an origin/admission
  -- capsule. Full bytes are compared with the trace ACTUALLY read by Store.
  expected <- Trace.refineArsHostTrace (Trace.RawArsHostTrace context runtime observation)
  Trace.validateArsHostTracePlan compiled expected
  Trace.validateArsHostTraceLocal expected
  pure expected

observe :: IORef NativeParentEvaluationReport -> Program Process.ObservedProducerProcess
observe _ = do
  outcome <- liftIO (Process.observeProducerProcess Process.NoSourceObservation)
  either (const (throwError "actual parent process observation failed")) pure outcome

-- Keep base zipWith and the explicit zero-based ordinal stream.
{- HLINT ignore item "Use zipWithFrom" -}
item
  :: IORef NativeParentEvaluationReport
  -> Int
  -> (NativeParentEvaluationItem -> NativeParentEvaluationItem)
  -> Program ()
item report ordinal change =
  update
    report
    ( \actual ->
        actual
          { parentEvaluationItems =
              zipWith
                (\index value -> if index == ordinal then change value else value)
                [0 ..]
                (parentEvaluationItems actual)
          }
    )
stage :: IORef NativeParentEvaluationReport -> NativeParentEvaluationStage -> Program ()
stage report value = update report (\actual -> actual {parentEvaluationStage = value})
update
  :: IORef NativeParentEvaluationReport
  -> (NativeParentEvaluationReport -> NativeParentEvaluationReport)
  -> Program ()
update report = liftIO . modifyIORef' report
require :: Bool -> Text -> Program ()
require condition reason = unless condition (throwError reason)
checked :: Either Text a -> Program a
checked = either throwError pure
requireData :: Bool -> Text -> Either Text ()
requireData condition reason = unless condition (Left reason)
