{-# LANGUAGE OverloadedStrings #-}

-- | One concrete internally selected-device execution through actual immutable
-- retention barriers. Produced values are neither learning/quality/Store
-- admission nor parent authentication, loaded-image or fsync evidence.
module JitML.Product.NativeRlProducer
  ( NativeProducerSource (..)
  , NativeProducerContext (..)
  , NativeProducerResult
  , NativeProducerStatus (..)
  , NativeProducerFailure (..)
  , nativeProducerStatus
  , nativeProducerFailure
  , nativeProducerAllocation
  , nativeProducerPreludeObjects
  , nativeProducerChildReports
  , nativeProducerRetainedInventory
  , nativeProducerProducedCohort
  , NativeChildDisposition (..)
  , NativeChildData
  , NativeDeviceData (..)
  , NativeProducedChild
  , NativeProducedCohort
  , NativeRetainedInventory
  , NativeNumericalModelData (..)
  , produceNativeRlCohort
  , nativeInventoryRow
  , nativeInventoryAllocation
  , nativeInventoryTerminal
  , nativeInventoryPreludeObjects
  , nativeInventoryChildren
  , nativeChildIndex
  , nativeChildAttempt
  , nativeChildDisposition
  , nativeChildObjects
  , nativeChildDevice
  , nativeChildFailure
  , nativeChildNumericalData
  , nativeProducedInventory
  , nativeProducedReferences
  , nativeProducedReferenceObject
  , nativeProducedReferencePayloadDigest
  , nativeProducedAcquisitionScope
  , nativeProducedAssociation
  , nativeProducedSources
  , nativeProducedBeforeProcess
  , nativeProducedChildren
  , nativeProducedChildData
  , nativeProducedModelData
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad (unless)
import Control.Monad.Except (ExceptT, catchError, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Control.Monad.State.Strict (StateT, gets, modify', runStateT)
import Control.Monad.Trans.Class (lift)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Combinators (mapLeft)
import Data.Foldable (for_)
import Data.List (find)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import System.IO (IOMode (ReadMode), withBinaryFile)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Codec qualified as Codec
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Producer qualified as ProducerData
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.SchemaTable (FieldType (TText))
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Env.Env (App, Env)
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Numerics.MlpDevice (MlpDevice (mlpdExecutionWitness))
import JitML.Numerics.MlpDeviceSelect qualified as Select
import JitML.Plan.Plan qualified as Plan
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeReferenceCalibration qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlProducer.Inventory qualified as Inventory
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.ProductBudget qualified as Budget
import JitML.Training.Budget qualified as Training

-- Supplied source remains supplied, even when its bytes equal an observation.
data NativeProducerSource
  = ObserveNativeProducerSource !FilePath
  | SuppliedNativeProducerSource !Source.SourceStamp
  deriving stock (Eq, Show)
data NativeProducerContext
  = DirectNativeProducer !FilePath
  | ScenarioNativeProducer !Training.ProductScenarioInvocation !NativeProducerSource
  deriving stock (Eq, Show)

data NativeProducerFailure
  = NativeProducerRejected !Text
  | NativeProducerProcessFailure !Text
  | NativeProducerCaptureFailure !Project.ProjectionFailure
  | NativeProducerCodecFailure !CodecError
  | NativeProducerRetentionFailure !Retain.NativeRetentionFailure
  | NativeProducerReferenceFailure !Reference.NativeReferenceCaptureStage !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)

data NativeChildDisposition
  = NativeChildCompleted
  | NativeChildFailed
  | NativeChildExecutionEvidenceFailure
  | NativeChildIncomplete
  | NativeChildNotRun
  deriving stock (Eq, Show)

-- This is DATA observed from one internally selected device. Absence/error
-- must not be silently converted to a declared-lane execution witness.
data NativeDeviceData
  = NativeNoMlpDevice
  | NativeDeviceNotQueried
  | NativeDeviceReturned !(Maybe Witness.DeviceExecutionWitness)
  | NativeDeviceFailed !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)

data NativeChildData
  = NativeChildData
      !Cohort.NativeSeedIndex
      !Digest
      !NativeChildDisposition
      ![Retain.NativeRetainedObjectData]
      !NativeDeviceData
      !(Maybe NativeProducerFailure)
      !(Maybe NativeNumericalModelData)

data NativeNumericalModelData
  = NativeNeuralNumericalData !Neural.NativeEvaluatedData
  | NativeArsNumericalData !Ars.NativeArsFinalObservation
  | NativeArenaNumericalData !Arena.NativeAlphaZeroEvaluatedData

-- No constructor, label, Read/Generic, action getter or restoration API.
data NativeProducedChild = NativeProducedChild !NativeChildData !NativeNumericalModelData

-- The capture, raw payload digest and actual outer-envelope ACK are minted
-- together only by captureReferences below, never supplied/re-paired by callers.
data NativeRetainedReferences
  = NativeRetainedReferences
      !Reference.CapturedNativeReferences
      !Retain.NativeRetainedObjectData
      !Digest

-- The original actual input observations stay associated with the same five
-- children and ACKs. Public getters expose ordinary DATA, never a factory.
data NativeProducedContext
  = NativeProducedContext
      !Retain.NativeAllocationScope
      !Context.NativeContextAssociation
      !Context.NativeContextSources
      !Process.ObservedProducerProcess
data NativeProducedCohort
  = NativeProducedCohort
      !NativeRetainedInventory
      !NativeRetainedReferences
      ![NativeProducedChild]
      !NativeProducedContext
data NativeRetainedInventory
  = NativeRetainedInventory
      !Text
      !Retain.NativeRetainedObjectData
      !Retain.NativeRetainedObjectData
      ![Retain.NativeRetainedObjectData]
      ![NativeChildData]

data NativeProducerStatus = NativeProducerRetainedStatus | NativeProducerStoppedStatus
  deriving stock (Eq, Show)

data NativeProducerResult
  = NativeProducerRetained !NativeRetainedInventory !(Maybe NativeProducedCohort)
  | NativeProducerStopped
      !(Maybe Retain.NativeRetainedObjectData)
      ![Retain.NativeRetainedObjectData]
      ![NativeChildData]
      !NativeProducerFailure

-- Ordinary observations do not manufacture/re-pair the opaque result.
nativeProducerStatus :: NativeProducerResult -> NativeProducerStatus
nativeProducerStatus NativeProducerRetained {} = NativeProducerRetainedStatus
nativeProducerStatus NativeProducerStopped {} = NativeProducerStoppedStatus
nativeProducerFailure :: NativeProducerResult -> Maybe NativeProducerFailure
nativeProducerFailure (NativeProducerStopped _ _ _ failure) = Just failure
nativeProducerFailure NativeProducerRetained {} = Nothing
nativeProducerAllocation :: NativeProducerResult -> Maybe Retain.NativeRetainedObjectData
nativeProducerAllocation (NativeProducerStopped allocation _ _ _) = allocation
nativeProducerAllocation (NativeProducerRetained inventory _) = Just (nativeInventoryAllocation inventory)
nativeProducerPreludeObjects :: NativeProducerResult -> [Retain.NativeRetainedObjectData]
nativeProducerPreludeObjects (NativeProducerStopped _ objects _ _) = objects
nativeProducerPreludeObjects (NativeProducerRetained inventory _) = nativeInventoryPreludeObjects inventory
nativeProducerChildReports :: NativeProducerResult -> [NativeChildData]
nativeProducerChildReports (NativeProducerStopped _ _ children _) = children
nativeProducerChildReports (NativeProducerRetained inventory _) = nativeInventoryChildren inventory
nativeProducerRetainedInventory :: NativeProducerResult -> Maybe NativeRetainedInventory
nativeProducerRetainedInventory (NativeProducerRetained inventory _) = Just inventory
nativeProducerRetainedInventory NativeProducerStopped {} = Nothing
nativeProducerProducedCohort :: NativeProducerResult -> Maybe NativeProducedCohort
nativeProducerProducedCohort (NativeProducerRetained _ cohort) = cohort
nativeProducerProducedCohort NativeProducerStopped {} = Nothing

nativeInventoryRow :: NativeRetainedInventory -> Text
nativeInventoryRow (NativeRetainedInventory row _ _ _ _) = row
nativeInventoryAllocation :: NativeRetainedInventory -> Retain.NativeRetainedObjectData
nativeInventoryAllocation (NativeRetainedInventory _ allocation _ _ _) = allocation
nativeInventoryTerminal :: NativeRetainedInventory -> Retain.NativeRetainedObjectData
nativeInventoryTerminal (NativeRetainedInventory _ _ terminal _ _) = terminal
nativeInventoryPreludeObjects :: NativeRetainedInventory -> [Retain.NativeRetainedObjectData]
nativeInventoryPreludeObjects (NativeRetainedInventory _ _ _ objects _) = objects
nativeInventoryChildren :: NativeRetainedInventory -> [NativeChildData]
nativeInventoryChildren (NativeRetainedInventory _ _ _ _ children) = children
nativeChildIndex :: NativeChildData -> Cohort.NativeSeedIndex
nativeChildIndex (NativeChildData index _ _ _ _ _ _) = index
nativeChildAttempt :: NativeChildData -> Digest
nativeChildAttempt (NativeChildData _ attempt _ _ _ _ _) = attempt
nativeChildDisposition :: NativeChildData -> NativeChildDisposition
nativeChildDisposition (NativeChildData _ _ disposition _ _ _ _) = disposition
nativeChildObjects :: NativeChildData -> [Retain.NativeRetainedObjectData]
nativeChildObjects (NativeChildData _ _ _ objects _ _ _) = objects
nativeChildDevice :: NativeChildData -> NativeDeviceData
nativeChildDevice (NativeChildData _ _ _ _ device _ _) = device
nativeChildFailure :: NativeChildData -> Maybe NativeProducerFailure
nativeChildFailure (NativeChildData _ _ _ _ _ failure _) = failure
nativeChildNumericalData :: NativeChildData -> Maybe NativeNumericalModelData
nativeChildNumericalData (NativeChildData _ _ _ _ _ _ actual) = actual
nativeProducedInventory :: NativeProducedCohort -> NativeRetainedInventory
nativeProducedInventory (NativeProducedCohort inventory _ _ _) = inventory
nativeProducedReferences :: NativeProducedCohort -> Reference.CapturedNativeReferences
nativeProducedReferences (NativeProducedCohort _ (NativeRetainedReferences actual _ _) _ _) = actual
nativeProducedReferenceObject :: NativeProducedCohort -> Retain.NativeRetainedObjectData
nativeProducedReferenceObject (NativeProducedCohort _ (NativeRetainedReferences _ actual _) _ _) = actual
nativeProducedReferencePayloadDigest :: NativeProducedCohort -> Digest
nativeProducedReferencePayloadDigest (NativeProducedCohort _ (NativeRetainedReferences _ _ actual) _ _) = actual
nativeProducedChildren :: NativeProducedCohort -> [NativeProducedChild]
nativeProducedChildren (NativeProducedCohort _ _ children _) = children
nativeProducedAcquisitionScope :: NativeProducedCohort -> Retain.NativeAllocationScope
nativeProducedAcquisitionScope (NativeProducedCohort _ _ _ (NativeProducedContext actual _ _ _)) = actual
nativeProducedAssociation :: NativeProducedCohort -> Context.NativeContextAssociation
nativeProducedAssociation (NativeProducedCohort _ _ _ (NativeProducedContext _ actual _ _)) = actual
nativeProducedSources :: NativeProducedCohort -> Context.NativeContextSources
nativeProducedSources (NativeProducedCohort _ _ _ (NativeProducedContext _ _ actual _)) = actual
nativeProducedBeforeProcess :: NativeProducedCohort -> Process.ObservedProducerProcess
nativeProducedBeforeProcess (NativeProducedCohort _ _ _ (NativeProducedContext _ _ _ actual)) = actual
nativeProducedChildData :: NativeProducedChild -> NativeChildData
nativeProducedChildData (NativeProducedChild actual _) = actual
nativeProducedModelData :: NativeProducedChild -> NativeNumericalModelData
nativeProducedModelData (NativeProducedChild _ actual) = actual

data FamilyRow
  = NeuralRow !Neural.NativeNeuralRowData
  | ArsRow !Ars.NativeArsRowData
  | ArenaRow !Arena.NativeAlphaZeroRowData

data SelectedChild
  = NeuralChild !Neural.NativeNeuralChildData
  | ArsChild !Ars.NativeArsChildData
  | ArenaChild !Arena.NativeAlphaZeroChildData

data Inputs = Inputs
  { inputBatch :: !Cohort.NativeRlCohortBatch
  , inputRow :: !Text
  , inputFamily :: !FamilyRow
  , inputContext :: !NativeProducerContext
  , inputAssociation :: !Context.NativeContextAssociation
  , inputSources :: !Context.NativeContextSources
  , inputBefore :: !Process.ObservedProducerProcess
  , inputAcquisition :: !Digest
  , inputDevice :: !(Maybe MlpDevice)
  , inputProducerRoot :: !Digest
  , inputProducerPool :: !Graph.NodePool
  }

data CurrentChild = CurrentChild
  { currentIndex :: !Cohort.NativeSeedIndex
  , currentAttempt :: !Digest
  , currentPool :: !Graph.NodePool
  , currentProducer :: !Digest
  , currentPayloads :: !Failure.NativeFailurePayloads
  , currentTerminal :: !(Maybe (PhaseTag, Digest))
  , currentObjects :: ![Retain.NativeRetainedObjectData]
  , currentRawAcknowledged :: !Bool
  , currentMaterialization :: !Failure.NativeReturnMaterialization
  , currentDevice :: !NativeDeviceData
  , currentNumerical :: !(Maybe NativeNumericalModelData)
  }

data RunState = RunState
  { runCursor :: !Retain.NativeRetentionCursor
  , runPrevious :: !Digest
  , runCurrent :: !(Maybe CurrentChild)
  , runCompleted :: ![NativeChildData]
  , runProduced :: ![NativeProducedChild]
  , runPrelude :: ![Retain.NativeRetainedObjectData]
  }

type Pipeline = ExceptT NativeProducerFailure (StateT RunState IO)

data ChildIssue
  = ChildIssue
      !Failure.NativeFailureOrigin
      !Failure.NativeReturnMaterialization
      !Failure.NativeFailureCaptureStatus

type ChildProgram = ExceptT ChildIssue Pipeline

data Slot = SnapshotSlot | ColdSlot | RawSlot | InitialSlot | CurrentSlot | LowSlot

-- The public seam is fixed: no caller can supply a numerical/store callback.
produceNativeRlCohort
  :: Cohort.NativeRlCohortBatch -> Text -> NativeProducerContext -> App NativeProducerResult
produceNativeRlCohort batch row context = do
  env <- ask
  prepared <- liftIO (prepareInputs env batch row context)
  case prepared of
    Left failure -> pure (NativeProducerStopped Nothing [] [] failure)
    Right (inputs, inventory, address) -> do
      session <- Retain.captureNativeRetentionSession (retentionMode context)
      case session of
        Left failure -> pure (NativeProducerStopped Nothing [] [] (NativeProducerRetentionFailure failure))
        Right actualSession -> do
          claimed <-
            liftIO
              ( Retain.claimNativeAllocation
                  actualSession
                  address
                  (LBS.fromStrict (Inventory.encodeNativeAllocationData inventory))
              )
          case claimed of
            Left failure -> pure (NativeProducerStopped Nothing [] [] (NativeProducerRetentionFailure failure))
            Right (allocation, cursor) -> liftIO $ do
              let object = Retain.nativeRetainedAllocationData allocation
              case Context.digestFromCanonicalText (Retain.nativeRetainedObjectSha256 object) of
                Left failure -> pure (NativeProducerStopped (Just object) [] [] (NativeProducerCodecFailure failure))
                Right previous -> do
                  let initial = RunState cursor previous Nothing [] [] []
                      execute = do
                        references <- captureReferences inputs
                        terminal <- runFive inputs inventory
                        pure (references, terminal)
                  (result, finalState) <- runStateT (runExceptT execute) initial
                  case result of
                    Left failure ->
                      pure
                        ( NativeProducerStopped
                            (Just object)
                            (reverse (runPrelude finalState))
                            (completePartial inventory finalState failure)
                            failure
                        )
                    Right (references, terminal) -> do
                      let children = reverse (runCompleted finalState)
                          produced = reverse (runProduced finalState)
                          inventoryData = NativeRetainedInventory row object terminal (reverse (runPrelude finalState)) children
                          actualContext =
                            NativeProducedContext
                              (Retain.nativeAllocationAddressScope address)
                              (inputAssociation inputs)
                              (inputSources inputs)
                              (inputBefore inputs)
                          cohort =
                            if length produced == 5
                              then Just (NativeProducedCohort inventoryData references produced actualContext)
                              else Nothing
                      pure (NativeProducerRetained inventoryData cohort)

-- One actual row-owned reference calculation after the fixed claim and
-- before every child Started/initializer. No arbitrary capture/ACK argument.
-- The prelude ACK survives later child failure in both ordinary result forms.
captureReferences :: Inputs -> Pipeline NativeRetainedReferences
captureReferences inputs = do
  let selected = case inputFamily inputs of
        NeuralRow actual -> Reference.NativeReferenceNeuralInput actual
        ArsRow actual -> Reference.NativeReferenceArsInput actual
        ArenaRow actual -> Reference.NativeReferenceArenaInput actual
  captured <- liftIO (Reference.captureNativeReferenceCalibration selected)
  case captured of
    Left failure -> do
      _ <-
        appendPreludeBytes "reference-calibration-failed" (Reference.nativeReferenceFailureBytes failure)
      throwError
        ( NativeProducerReferenceFailure
            (Reference.nativeReferenceFailureStage failure)
            (Reference.nativeReferenceFailureDiagnostic failure)
        )
    Right actual -> do
      let expected = familyCohort (inputFamily inputs)
          observed = Reference.nativeCapturedReferenceCohort actual
          bytes = Reference.nativeCapturedReferenceBytes actual
          payloadDigest = hashBytes bytes
      -- Retain the actual returned family even if a later identity check
      -- refuses it. No child starts and no capsule is minted on mismatch.
      object <- appendPreludeBytes "reference-calibration" bytes
      unless
        ( Cohort.nativeRlCohortPlanId observed == Cohort.nativeRlCohortPlanId expected
            && Cohort.nativeRlCohortPlanTransport observed == Cohort.nativeRlCohortPlanTransport expected
        )
        ( throwError
            (NativeProducerRejected "actual captured reference full cohort differs from preclaimed row")
        )
      pure (NativeRetainedReferences actual object payloadDigest)

appendPreludeBytes :: Text -> ByteString -> Pipeline Retain.NativeRetainedObjectData
appendPreludeBytes label bytes = do
  object <- appendBytes label bytes
  modify' $ \state -> state {runPrelude = object : runPrelude state}
  pure object

retentionMode :: NativeProducerContext -> Retain.NativeRetentionMode
retentionMode DirectNativeProducer {} = Retain.AllowLocalNativeRetention
retentionMode ScenarioNativeProducer {} = Retain.RequireLiveNativeRetention

prepareInputs
  :: Env
  -> Cohort.NativeRlCohortBatch
  -> Text
  -> NativeProducerContext
  -> IO
       ( Either
           NativeProducerFailure
           (Inputs, Inventory.NativeAllocationData, Retain.NativeAllocationAddress)
       )
prepareInputs env batch row context = do
  attempted <- tryAny $ do
    result <- gatherInputs env batch row context
    evaluate $ case result of
      Left failure -> forceProducerFailure failure `seq` Left failure
      Right actual@(_, inventory, address) ->
        BS.length (Inventory.encodeNativeAllocationData inventory) `seq`
          Text.length (Retain.nativeAllocationAddressKey address) `seq`
            Right actual
  pure $ case attempted of
    Left _ -> Left (NativeProducerRejected "producer complete input/allocation capture failed synchronously")
    Right result -> result

gatherInputs
  :: Env
  -> Cohort.NativeRlCohortBatch
  -> Text
  -> NativeProducerContext
  -> IO
       ( Either
           NativeProducerFailure
           (Inputs, Inventory.NativeAllocationData, Retain.NativeAllocationAddress)
       )
gatherInputs env batch row context = do
  attempted <- tryAny $ do
    selected <- evaluate (selectFamily batch row)
    case selected of
      Left detail -> pure (Left (NativeProducerRejected detail))
      Right family -> do
        before <- Process.observeProducerProcess (sourceMode context)
        case before of
          Left _ -> pure (Left (NativeProducerProcessFailure "actual producer before-process observation failed"))
          Right actualBefore -> do
            nonces <- osNonces
            case nonces of
              Left detail -> pure (Left (NativeProducerRejected detail))
              Right (acquisitionNonce, attempts) -> do
                let acquisition = Inventory.allocationNonceDigest acquisitionNonce
                    sources = contextSources context actualBefore
                    association = case context of
                      DirectNativeProducer _ -> Context.DirectLocalContext acquisition
                      ScenarioNativeProducer invocation _ -> Context.SuppliedScenarioContext invocation
                    device = case family of
                      ArsRow _ -> Nothing
                      _ -> Just (Select.rlDeviceForSubstrate (Cohort.nativeRlCohortBatchSubstrate batch) env)
                projected <-
                  ProducerData.projectProducerContextData
                    Graph.emptyNodePool
                    (Just (Process.recordedProducerObservation actualBefore))
                    Nothing
                    Nothing
                pure $ do
                  (producer, pool) <- mapLeft NativeProducerCaptureFailure projected
                  _ <- mapLeft NativeProducerCodecFailure (Graph.producerClosureBytes producer pool)
                  case context of
                    ScenarioNativeProducer invocation _ ->
                      unless
                        ( Training.productScenarioInvocationExecutableSha256 invocation
                            == Process.producerExecutableFileSha256 actualBefore
                        )
                        ( Left
                            ( NativeProducerRejected
                                "supplied invocation executable FILE SHA differs from actual producer observation"
                            )
                        )
                    DirectNativeProducer _ -> Right ()
                  let inputs = Inputs batch row family context association sources actualBefore acquisition device producer pool
                  children <-
                    sequence
                      [ do
                          values <-
                            codecData
                              ( Context.nativePhaseContextValues
                                  batch
                                  row
                                  index
                                  association
                                  sources
                                  (Inventory.attemptNonceDigest nonce)
                                  acquisition
                                  producer
                              )
                          canonical <- codecData (Schema.mkContextData values)
                          codecData (Inventory.mkNativeAllocationChildData nonce canonical)
                      | (index, nonce) <- zip Cohort.nativeSeedIndices attempts
                      ]
                  inventory <- codecData (Inventory.mkNativeAllocationData acquisitionNonce producer pool children)
                  source <- case (Context.nativeContextObservedSource sources, Context.nativeContextSuppliedSource sources) of
                    (Just observed, _) -> Right observed
                    (_, Just supplied) -> Right supplied
                    _ -> Left (NativeProducerRejected "allocation source coverage is absent")
                  let scopeContext = case context of
                        DirectNativeProducer _ -> Retain.NativeDirectLocalAcquisition (digestText acquisition)
                        ScenarioNativeProducer invocation _ -> Retain.NativeSuppliedScenarioDigest (Training.productScenarioInvocationDigest invocation)
                      -- The scenario slot is independent of the fresh OS nonce.
                      -- Different claims for this invocation conflict before init.
                      slot = case context of
                        DirectNativeProducer _ -> digestText acquisition
                        ScenarioNativeProducer invocation _ -> Training.productScenarioInvocationDigest invocation
                      scope =
                        Retain.NativeAllocationScope
                          scopeContext
                          row
                          source
                          (Plan.planIdText (Cohort.nativeRlCohortPlanId (familyCohort family)))
                          slot
                  address <- mapLeft NativeProducerRejected (Retain.mkNativeAllocationAddress scope)
                  let bytes = Inventory.encodeNativeAllocationData inventory
                  BS.length bytes `seq` Right (inputs, inventory, address)
  pure $ case attempted of
    Left _ ->
      Left
        (NativeProducerRejected "producer input/source/allocation materialization failed synchronously")
    Right actual -> actual
 where
  codecData :: Either CodecError a -> Either NativeProducerFailure a
  codecData = mapLeft NativeProducerCodecFailure

selectFamily :: Cohort.NativeRlCohortBatch -> Text -> Either Text FamilyRow
selectFamily batch row = case Neural.selectNativeNeuralRowData batch row of
  Right actual -> Right (NeuralRow actual)
  Left _ -> case Ars.selectNativeArsRowData batch row of
    Right actual -> Right (ArsRow actual)
    Left _ -> case Arena.selectNativeAlphaZeroRowData batch row of
      Right actual -> Right (ArenaRow actual)
      Left failure -> Left (Arena.nativeAlphaZeroFailureDetail failure)

familyCohort :: FamilyRow -> Cohort.NativeRlCohortPlan
familyCohort value = case value of
  NeuralRow actual -> Neural.nativeNeuralRowCohort actual
  ArsRow actual -> Ars.nativeArsRowCohort actual
  ArenaRow actual -> Arena.nativeAlphaZeroRowCohort actual

sourceMode :: NativeProducerContext -> Process.SourceObservationMode
sourceMode context = case context of
  DirectNativeProducer root -> Process.ObserveSourceAt root
  ScenarioNativeProducer _ (ObserveNativeProducerSource root) -> Process.ObserveSourceAt root
  ScenarioNativeProducer _ (SuppliedNativeProducerSource _) -> Process.NoSourceObservation

contextSources
  :: NativeProducerContext -> Process.ObservedProducerProcess -> Context.NativeContextSources
contextSources context process =
  Context.NativeContextSources
    (snd <$> Process.producerObservedSource process)
    ( case context of
        ScenarioNativeProducer _ (SuppliedNativeProducerSource stamp) -> Just stamp
        _ -> Nothing
    )

-- Actual OS entropy only, with exactly one prescribed six-nonce allocation.
-- No training RNG is sampled and collisions/errors do not trigger replacements.
osNonces :: IO (Either Text (ByteString, [ByteString]))
osNonces = withBinaryFile "/dev/urandom" ReadMode $ \handle -> do
  bytes <- BS.hGet handle (6 * 32)
  pure $
    if BS.length bytes /= 192
      then Left "OS nonce source did not return the complete six identities"
      else case chunks bytes of
        acquisition : attempts | length attempts == 5 -> Right (acquisition, attempts)
        _ -> Left "OS nonce allocation count differs"
 where
  chunks bytes
    | BS.null bytes = []
    | otherwise = let (first, rest) = BS.splitAt 32 bytes in first : chunks rest

digestText :: Digest -> Text
digestText = Text.pack . concatMap hexadecimal . BS.unpack . digestBytes
 where
  alphabet = "0123456789abcdef"
  hexadecimal byte = [digit (fromIntegral byte `div` 16), digit (fromIntegral byte `mod` 16)]
  digit n = case drop n alphabet of first : _ -> first; [] -> '0'

modifyCurrent :: (CurrentChild -> CurrentChild) -> Pipeline ()
modifyCurrent change = modify' $ \state -> state {runCurrent = change <$> runCurrent state}

requireCurrent :: Pipeline CurrentChild
requireCurrent = do
  current <- gets runCurrent
  maybe (throwError (NativeProducerRejected "internal producer child context is absent")) pure current

appendBytes :: Text -> ByteString -> Pipeline Retain.NativeRetainedObjectData
appendBytes label bytes = do
  phase <-
    either (throwError . NativeProducerRejected) pure (Retain.mkNativeRetentionPhaseLabel label)
  cursor <- gets runCursor
  result <- liftIO (Retain.appendNativeRetentionPhase cursor phase (LBS.fromStrict bytes))
  case result of
    Left failure -> throwError (NativeProducerRetentionFailure failure)
    Right (retained, next) -> do
      let object = Retain.nativeRetainedPhaseData retained
      previous <-
        either
          (throwError . NativeProducerCodecFailure)
          pure
          (Context.digestFromCanonicalText (Retain.nativeRetainedObjectSha256 object))
      modify' $ \state -> state {runCursor = next, runPrevious = previous}
      modifyCurrent $ \child -> child {currentObjects = object : currentObjects child}
      pure object

childLabel :: CurrentChild -> Text -> Text
childLabel child suffix = "child" <> Text.pack (show (Cohort.nativeSeedIndexValue (currentIndex child))) <> "." <> suffix

phaseAcknowledgement :: Inputs -> Text -> PhaseTag -> Digest -> Pipeline ()
phaseAcknowledgement inputs suffix phase root = do
  child <- requireCurrent
  previous <- gets runPrevious
  values <-
    codecOrStop
      ( Context.nativePhaseContextValues
          (inputBatch inputs)
          (inputRow inputs)
          (currentIndex child)
          (inputAssociation inputs)
          (inputSources inputs)
          (currentAttempt child)
          (inputAcquisition inputs)
          (currentProducer child)
      )
  context <- codecOrStop (Schema.mkContextData values)
  contextRoots <- codecOrStop (Schema.contextReferences context)
  let roots = root : fmap snd contextRoots
  closure <- codecOrStop (Graph.reachableNodePool roots (currentPool child))
  captured <- codecOrStop (Codec.mkPhaseData phase context (Just previous) root closure)
  _ <- appendBytes (childLabel child suffix) (Codec.encodePhaseData captured)
  modifyCurrent $ \actual ->
    actual
      { currentTerminal = Just (phase, root)
      , currentRawAcknowledged = currentRawAcknowledged actual || phase == RawReturnPhase
      }
 where
  codecOrStop :: Either CodecError a -> Pipeline a
  codecOrStop = either (throwError . NativeProducerCodecFailure) pure

slotUpdate
  :: Slot
  -> Failure.NativePayloadCapture
  -> Failure.NativeFailurePayloads
  -> Failure.NativeFailurePayloads
slotUpdate slot value payloads = case slot of
  SnapshotSlot -> payloads {Failure.nativeFailureSnapshotPayload = value}
  ColdSlot -> payloads {Failure.nativeFailureColdSnapshotPayload = value}
  RawSlot -> payloads {Failure.nativeFailureRawPayload = value}
  InitialSlot -> payloads {Failure.nativeFailureInitialEvaluationPayload = value}
  CurrentSlot -> payloads {Failure.nativeFailureCurrentEvaluationPayload = value}
  LowSlot -> payloads {Failure.nativeFailureLowPayload = value}

captureBody
  :: Inputs
  -> Slot
  -> Text
  -> PhaseTag
  -> (Graph.NodePool -> IO (Either Project.ProjectionFailure (Digest, Graph.NodePool)))
  -> ChildProgram Digest
captureBody inputs slot label phase project = do
  child <- lift requireCurrent
  result <- liftIO (project (currentPool child))
  case result of
    Left failure -> do
      diagnostic <- liftIO (projectionDiagnostic failure)
      let status = projectionCapture failure
      lift $ modifyCurrent $ \actual -> actual {currentPayloads = slotUpdate slot (projectionPayload failure) (currentPayloads actual)}
      throwError
        ( ChildIssue
            (Failure.NativePhaseCaptureFailure (familyTag (inputFamily inputs)) phase status diagnostic)
            (currentMaterialization child)
            status
        )
    Right (root, pool) -> do
      lift $ modifyCurrent $ \actual ->
        actual
          { currentPool = pool
          , currentPayloads = slotUpdate slot (Failure.NativePayloadPresent root) (currentPayloads actual)
          }
      rejected <- lift (tryCodecAcknowledgement (phaseAcknowledgement inputs label phase root))
      case rejected of
        Nothing -> pure root
        Just problem -> do
          diagnostic <- liftIO (projectionDiagnostic (Project.ProjectionDataRejected problem))
          let capture = projectionCapture (Project.ProjectionDataRejected problem)
          throwError
            ( ChildIssue
                (Failure.NativePhaseCaptureFailure (familyTag (inputFamily inputs)) phase capture diagnostic)
                (currentMaterialization child)
                capture
            )

-- Conservative construction upper counts are not exact/lower encoded sizes.
projectionCapture :: Project.ProjectionFailure -> Failure.NativeFailureCaptureStatus
projectionCapture actual = case actual of
  Project.ProjectionAllocationRefused resource cap _ -> Failure.RefusedNativeCapture resource (fromInteger cap) Failure.UnknownNativeSize
  Project.ProjectionDataRejected (ResourceExceeded resource cap _) -> Failure.RefusedNativeCapture resource (fromInteger cap) Failure.UnknownNativeSize
  Project.ProjectionDataRejected _ -> Failure.UnsupportedNativeCapture "phase-data" "closed DATA graph refused"
  Project.ProjectionSynchronousFailure _ -> Failure.SynchronousNativeCaptureFailure "phase-data"

projectionPayload :: Project.ProjectionFailure -> Failure.NativePayloadCapture
projectionPayload actual = case actual of
  Project.ProjectionAllocationRefused resource cap _ -> Failure.NativePayloadRefused resource (fromInteger cap) Failure.UnknownNativeSize
  Project.ProjectionDataRejected (ResourceExceeded resource cap _) -> Failure.NativePayloadRefused resource (fromInteger cap) Failure.UnknownNativeSize
  Project.ProjectionSynchronousFailure _ -> Failure.NativePayloadUnmaterializable
  Project.ProjectionDataRejected _ -> Failure.NativePayloadUnavailable

familyTag :: FamilyRow -> Failure.NativeAttemptFamily
familyTag actual = case actual of
  ArsRow _ -> Failure.NativeArsFamily
  ArenaRow _ -> Failure.NativeArenaFamily
  NeuralRow row -> case Cohort.nativeRlSeedPlanCompiledReturn
    (Cohort.nativeRlCohortServingChild (Neural.nativeNeuralRowCohort row)) of
    Nothing -> Failure.NativeOnPolicyFamily
    Just plan -> case Budget.compiledRlTrainerKind plan of
      "dqn" -> Failure.NativeDqnFamily
      "qrdqn" -> Failure.NativeQrFamily
      "her" -> Failure.NativeHerFamily
      name | name `elem` ["ddpg", "td3", "sac", "crossq", "tqc"] -> Failure.NativeContinuousFamily
      _ -> Failure.NativeOnPolicyFamily

projectEvaluation
  :: Neural.NativeEvaluationData
  -> Graph.NodePool
  -> IO (Either Project.ProjectionFailure (Digest, Graph.NodePool))
projectEvaluation value = case value of
  Neural.NativeReturnEvaluation actual -> (`Project.projectReturnEvaluationData` actual)
  Neural.NativeHerEvaluation actual -> (`Project.projectHerEvaluationData` actual)

-- Optional getter capture has no invented phase/ACK. A failed stage's safe
-- payloads are acknowledged together by its actual SafeFailure record.
-- Only the closed high-stage failure paths below call this helper. Their Known
-- fields retain the same lexical prepared/effective snapshot, cold snapshot and
-- initial evaluation already captured in this slot. ARS after-process failures
-- likewise retain the same final evaluation captured before origin checking.
-- Preserve that existing root instead of retrying an immutable getter/projector.
-- A cold initialization failure has no effective SnapshotSlot yet and therefore
-- still captures its actual supplied snapshot here; slots are never substituted.
rememberOptional
  :: Slot
  -> Maybe a
  -> (Graph.NodePool -> a -> IO (Either Project.ProjectionFailure (Digest, Graph.NodePool)))
  -> Pipeline ()
rememberOptional slot actual project = do
  child <- requireCurrent
  case slotLookup slot (currentPayloads child) of
    Failure.NativePayloadPresent _ -> pure ()
    _ -> case actual of
      Nothing -> modifyCurrent $ \state -> state {currentPayloads = slotUpdate slot Failure.NativePayloadAbsent (currentPayloads state)}
      Just value -> do
        result <- liftIO (project (currentPool child) value)
        case result of
          Left failure -> modifyCurrent $ \state -> state {currentPayloads = slotUpdate slot (projectionPayload failure) (currentPayloads state)}
          Right (root, pool) -> modifyCurrent $ \state ->
            state
              { currentPool = pool
              , currentPayloads = slotUpdate slot (Failure.NativePayloadPresent root) (currentPayloads state)
              }

neuralFailure
  :: Inputs -> Failure.NativeReturnMaterialization -> Neural.NativeAttemptFailure -> ChildProgram a
neuralFailure inputs returned failure = do
  lift $ do
    rememberOptional
      SnapshotSlot
      (Neural.nativeFailureSnapshot failure)
      Project.projectNeuralSnapshotData
    rememberOptional
      ColdSlot
      (Neural.nativeFailureColdSnapshot failure)
      Project.projectNeuralSnapshotData
    rememberOptional
      InitialSlot
      (Neural.nativeFailureInitialEvaluation failure)
      (flip projectEvaluation)
    rememberOptional
      CurrentSlot
      (Neural.nativeFailureEvaluation failure)
      (flip projectEvaluation)
    rememberOptional
      LowSlot
      (Neural.nativeFailureLowFailure failure)
      Project.projectLowNeuralFailureData
  throwError
    ( ChildIssue
        (Failure.NativeNeuralStageFailure (familyTag (inputFamily inputs)) failure)
        returned
        Failure.CompleteNativeFailureCapture
    )

arenaFailure :: Failure.NativeReturnMaterialization -> Arena.NativeArenaFailure -> ChildProgram a
arenaFailure returned failure = do
  lift $ do
    rememberOptional
      SnapshotSlot
      (Arena.nativeAlphaZeroFailureSnapshot failure)
      Project.projectAlphaZeroSnapshotData
    rememberOptional
      InitialSlot
      (Arena.nativeAlphaZeroFailureInitialEvaluation failure)
      Project.projectArenaEvaluationData
    rememberOptional
      CurrentSlot
      (Arena.nativeAlphaZeroFailureEvaluation failure)
      Project.projectArenaEvaluationData
  throwError
    (ChildIssue (Failure.NativeArenaStageFailure failure) returned Failure.CompleteNativeFailureCapture)

arsFailure :: Failure.NativeReturnMaterialization -> Ars.NativeArsFailure -> ChildProgram a
arsFailure returned failure = do
  lift $ do
    rememberOptional SnapshotSlot (Ars.nativeArsFailureSnapshot failure) Project.projectArsSnapshotData
    rememberOptional
      InitialSlot
      (Ars.nativeArsFailureInitialEvaluation failure)
      Project.projectReturnEvaluationData
    rememberOptional
      CurrentSlot
      (Ars.nativeArsFailureEvaluation failure)
      Project.projectReturnEvaluationData
  throwError
    (ChildIssue (Failure.NativeArsStageFailure failure) returned Failure.CompleteNativeFailureCapture)

runNeuralChild
  :: Inputs -> Neural.NativeNeuralChildData -> MlpDevice -> ChildProgram NativeNumericalModelData
runNeuralChild inputs child device = do
  preparedResult <- liftIO (Neural.prepareNativeNeuralAttempt child device)
  prepared <- case preparedResult of
    Neural.NativePreparationFailed failure -> neuralFailure inputs Failure.NoReturnObserved failure
    Neural.NativePreparationReady actual -> pure actual
  let cold = Neural.nativePreparedStage prepared == Low.NeuralCold
      firstPhase = if cold then ColdSnapshotPhase else EffectiveSnapshotPhase
      firstSlot = if cold then ColdSlot else SnapshotSlot
  _ <-
    captureBody
      inputs
      firstSlot
      "prepared"
      firstPhase
      (\pool -> Project.projectNeuralSnapshotData pool (Neural.nativePreparedSnapshot prepared))
  initialized <- liftIO (Neural.completeNativeNeuralInitialization prepared)
  effective <- case initialized of
    Neural.NativeInitializationFailed failure -> neuralFailure inputs Failure.NoReturnObserved failure
    Neural.NativeInitializationReady actual -> pure actual
  _ <-
    captureBody
      inputs
      SnapshotSlot
      "effective"
      EffectiveSnapshotPhase
      (\pool -> Project.projectNeuralSnapshotData pool (Neural.nativeEffectiveSnapshot effective))
  initialResult <- liftIO (Neural.evaluateNativeNeuralInitial effective)
  ready <- case initialResult of
    Neural.NativeInitialEvaluationFailed failure -> neuralFailure inputs Failure.NoReturnObserved failure
    Neural.NativeInitialEvaluationReady actual -> pure actual
  _ <-
    captureBody
      inputs
      InitialSlot
      "initial"
      InitialEvaluationPhase
      (projectEvaluation (Neural.nativeReadyInitialEvaluation ready))
  trained <- liftIO (Neural.continueNativeNeuralTraining ready)
  pending <- case trained of
    Neural.NativeTrainingFailed failure -> neuralFailure inputs Failure.NoReturnObserved failure
    Neural.NativeTrainingReturnedButUnmaterializable failure -> do
      lift (setMaterialization Failure.ReturnedButUnmaterializable)
      lift $ modifyCurrent $ \actual ->
        actual
          { currentPayloads = slotUpdate RawSlot Failure.NativePayloadUnmaterializable (currentPayloads actual)
          }
      neuralFailure inputs Failure.ReturnedButUnmaterializable failure
    Neural.NativeTrainingBindingFailed returned failure -> do
      lift (setMaterialization Failure.MaterializedBindingRejected)
      _ <-
        captureBody
          inputs
          RawSlot
          "raw"
          RawReturnPhase
          (\pool -> Project.projectNeuralReturnedData pool (Neural.nativeReturnedLowData returned))
      neuralFailure inputs Failure.MaterializedBindingRejected failure
    Neural.NativeTrainingReturned actual -> do
      lift (setMaterialization Failure.MaterializedReturned)
      _ <-
        captureBody
          inputs
          RawSlot
          "raw"
          RawReturnPhase
          ( \pool ->
              Project.projectNeuralReturnedData
                pool
                (Neural.nativeReturnedLowData (Neural.nativeReturnedData actual))
          )
      pure actual
  finalResult <- liftIO (Neural.evaluateNativeNeuralFinal pending)
  final <- case finalResult of
    -- The second result field is nativeFailureEvaluation failure itself;
    -- neuralFailure captures that one actual getter once, without a retry.
    Neural.NativeFinalEvaluationFailed _ _ failure ->
      neuralFailure inputs Failure.MaterializedReturned failure
    Neural.NativeFinalEvaluationComplete actual -> pure actual
  _ <-
    captureBody
      inputs
      CurrentSlot
      "final"
      FinalEvaluationPhase
      (projectEvaluation (Neural.nativeEvaluatedFinalEvaluation final))
  pure (NativeNeuralNumericalData final)

runArenaChild
  :: Inputs -> Arena.NativeAlphaZeroChildData -> MlpDevice -> ChildProgram NativeNumericalModelData
runArenaChild inputs child device = do
  preparedResult <- liftIO (Arena.prepareNativeAlphaZeroAttempt child device)
  prepared <- case preparedResult of
    Arena.NativeArenaPreparationFailed failure -> arenaFailure Failure.NoReturnObserved failure
    Arena.NativeArenaPreparationReady actual -> pure actual
  _ <-
    captureBody
      inputs
      SnapshotSlot
      "prepared"
      EffectiveSnapshotPhase
      (\pool -> Project.projectAlphaZeroSnapshotData pool (Arena.nativeAlphaZeroPreparedSnapshot prepared))
  initialResult <- liftIO (Arena.evaluateNativeAlphaZeroInitial prepared)
  ready <- case initialResult of
    Arena.NativeArenaInitialFailed failure -> arenaFailure Failure.NoReturnObserved failure
    Arena.NativeArenaInitialReady actual -> pure actual
  _ <-
    captureBody
      inputs
      InitialSlot
      "initial"
      InitialEvaluationPhase
      (\pool -> Project.projectArenaEvaluationData pool (Arena.nativeAlphaZeroReadyInitialEvaluation ready))
  trained <- liftIO (Arena.continueNativeAlphaZeroTraining ready)
  pending <- case trained of
    Arena.NativeArenaTrainingFailed failure -> arenaFailure Failure.NoReturnObserved failure
    Arena.NativeArenaTrainingReturnedButUnmaterializable failure -> do
      lift (setMaterialization Failure.ReturnedButUnmaterializable)
      lift $ modifyCurrent $ \actual ->
        actual
          { currentPayloads = slotUpdate RawSlot Failure.NativePayloadUnmaterializable (currentPayloads actual)
          }
      arenaFailure Failure.ReturnedButUnmaterializable failure
    Arena.NativeArenaTrainingBindingFailed returned failure -> do
      lift (setMaterialization Failure.MaterializedBindingRejected)
      _ <-
        captureBody
          inputs
          RawSlot
          "raw"
          RawReturnPhase
          ( \pool -> Project.projectAlphaZeroReturnedData pool (Arena.nativeAlphaZeroReturnedRawObservation returned)
          )
      arenaFailure Failure.MaterializedBindingRejected failure
    Arena.NativeArenaTrainingReturned actual -> do
      lift (setMaterialization Failure.MaterializedReturned)
      _ <-
        captureBody
          inputs
          RawSlot
          "raw"
          RawReturnPhase
          ( \pool ->
              Project.projectAlphaZeroReturnedData
                pool
                (Arena.nativeAlphaZeroReturnedRawObservation (Arena.nativeAlphaZeroReturnedData actual))
          )
      pure actual
  finalResult <- liftIO (Arena.evaluateNativeAlphaZeroFinal pending)
  final <- case finalResult of
    -- The second result field is nativeAlphaZeroFailureEvaluation failure;
    -- arenaFailure captures that one actual getter once, without a retry.
    Arena.NativeArenaFinalFailed _ _ failure ->
      arenaFailure Failure.MaterializedReturned failure
    Arena.NativeArenaFinalComplete actual -> pure actual
  _ <-
    captureBody
      inputs
      CurrentSlot
      "final"
      FinalEvaluationPhase
      ( \pool -> Project.projectArenaEvaluationData pool (Arena.nativeAlphaZeroEvaluatedFinalEvaluation final)
      )
  pure (NativeArenaNumericalData final)

arsContext :: NativeProducerContext -> Ars.NativeArsContextInput
arsContext context = case context of
  DirectNativeProducer root -> Ars.DirectNativeArsLocal root
  ScenarioNativeProducer invocation source -> Ars.SuppliedNativeArsParent invocation $ case source of
    ObserveNativeProducerSource root -> Ars.ObserveNativeArsSourceRoot root
    SuppliedNativeProducerSource stamp -> Ars.SuppliedNativeArsParentSource stamp

runArsChild :: Inputs -> Ars.NativeArsChildData -> ChildProgram NativeNumericalModelData
runArsChild inputs child = do
  begunResult <- liftIO (Ars.beginNativeArsAttempt child (arsContext (inputContext inputs)))
  begun <- case begunResult of
    Ars.NativeArsBeginFailed failure -> arsFailure Failure.NoReturnObserved failure
    Ars.NativeArsBegunReady actual -> pure actual
  -- The exact actual INNER identity is retained separately; it is never
  -- replaced by the outer preclaimed identity or injected into an origin.
  lift (acknowledgeArsBegun inputs begun)
  preparedResult <- liftIO (Ars.prepareNativeArsAttempt begun)
  prepared <- case preparedResult of
    Ars.NativeArsPreparationFailed failure -> arsFailure Failure.NoReturnObserved failure
    Ars.NativeArsPreparationReady actual -> pure actual
  _ <-
    captureBody
      inputs
      SnapshotSlot
      "prepared"
      EffectiveSnapshotPhase
      (\pool -> Project.projectArsSnapshotData pool (Ars.nativeArsPreparedSnapshot prepared))
  initialResult <- liftIO (Ars.evaluateNativeArsInitial prepared)
  ready <- case initialResult of
    Ars.NativeArsInitialFailed failure -> arsFailure Failure.NoReturnObserved failure
    Ars.NativeArsInitialReady actual -> pure actual
  _ <-
    captureBody
      inputs
      InitialSlot
      "initial"
      InitialEvaluationPhase
      (\pool -> Project.projectReturnEvaluationData pool (Ars.nativeArsReadyInitialEvaluation ready))
  trained <- liftIO (Ars.continueNativeArsTraining ready)
  pending <- case trained of
    Ars.NativeArsTrainingFailed failure -> arsFailure Failure.NoReturnObserved failure
    Ars.NativeArsReturnedButUnmaterializable failure -> do
      lift (setMaterialization Failure.ReturnedButUnmaterializable)
      lift $ modifyCurrent $ \actual ->
        actual
          { currentPayloads = slotUpdate RawSlot Failure.NativePayloadUnmaterializable (currentPayloads actual)
          }
      arsFailure Failure.ReturnedButUnmaterializable failure
    Ars.NativeArsReturnedBindingFailed returned failure -> do
      lift (setMaterialization Failure.MaterializedBindingRejected)
      _ <- captureArsRaw returned
      arsFailure Failure.MaterializedBindingRejected failure
    Ars.NativeArsTrainingReturned actual -> do
      lift (setMaterialization Failure.MaterializedReturned)
      _ <- captureArsRaw (Ars.nativeArsPendingReturned actual)
      pure actual
  finalResult <- liftIO (Ars.finishNativeArsAttempt pending)
  final <- case finalResult of
    Ars.NativeArsFinishRejected _ failure -> arsFailure Failure.MaterializedReturned failure
    Ars.NativeArsFinished actual -> pure actual
  case Ars.nativeArsFinalEvaluation final of
    Just evaluation -> do
      _ <-
        captureBody
          inputs
          CurrentSlot
          "final"
          FinalEvaluationPhase
          (`Project.projectReturnEvaluationData` evaluation)
      pure ()
    Nothing -> pure ()
  for_ (Ars.nativeArsFinalEvaluationFailure final) (arsFailure Failure.MaterializedReturned)
  case Ars.nativeArsFinalOrigin final of
    Left failure -> arsFailure Failure.MaterializedReturned failure
    Right origin -> do
      -- Check actual inner identity/process lineage against this exact begun
      -- capsule. No new origin is constructed by comparing supplied DATA.
      unless
        ( Ars.nativeArsOriginAttemptId origin == Ars.nativeArsBegunAttemptId begun
            && Ars.nativeArsOriginContextDigest origin == Ars.nativeArsBegunContextDigest begun
            && Ars.nativeArsOriginChild origin == Ars.nativeArsBegunChild begun
            && Ars.nativeArsOriginContext origin == Ars.nativeArsBegunContext begun
            && Ars.nativeArsOriginSourceCoverage origin == Ars.nativeArsBegunSourceCoverage begun
        )
        ( throwError
            ( captureIssue
                inputs
                FailurePhase
                "actual ARS inner origin identity differs from retained begun capsule"
                Failure.MaterializedReturned
            )
        )
      lift $
        processOrStop
          ( Process.compareProducerProcessObservations
              (Ars.nativeArsBegunBeforeProcess begun)
              (Ars.nativeArsOriginBeforeProcess origin)
          )
      lift (acknowledgeArsOrigin inputs origin)
  unless
    (isJust (Ars.nativeArsFinalEvaluation final))
    ( throwError
        ( captureIssue
            inputs
            FinalEvaluationPhase
            "actual ARS final evaluation is absent"
            Failure.MaterializedReturned
        )
    )
  pure (NativeArsNumericalData final)
 where
  captureArsRaw returned =
    captureBody
      inputs
      RawSlot
      "raw"
      RawReturnPhase
      ( \pool ->
          Project.projectArsReturnedData
            pool
            (Ars.nativeArsChildCompiledPlan child)
            (Ars.nativeArsReturnedPolicy returned)
      )

captureIssue :: Inputs -> PhaseTag -> Text -> Failure.NativeReturnMaterialization -> ChildIssue
captureIssue inputs phase reason returned =
  let capture = Failure.UnsupportedNativeCapture "native-producer" reason
   in ChildIssue
        ( Failure.NativePhaseCaptureFailure
            (familyTag (inputFamily inputs))
            phase
            capture
            (Failure.CompleteNativeDiagnostic reason)
        )
        returned
        capture

processOrStop :: Either Process.ProducerObservationError () -> Pipeline ()
processOrStop =
  either
    ( const
        (throwError (NativeProducerProcessFailure "actual producer process/source observations differ"))
    )
    pure

setMaterialization :: Failure.NativeReturnMaterialization -> Pipeline ()
setMaterialization value = modifyCurrent $ \child -> child {currentMaterialization = value}

slotLookup :: Slot -> Failure.NativeFailurePayloads -> Failure.NativePayloadCapture
slotLookup slot payloads = case slot of
  SnapshotSlot -> Failure.nativeFailureSnapshotPayload payloads
  ColdSlot -> Failure.nativeFailureColdSnapshotPayload payloads
  RawSlot -> Failure.nativeFailureRawPayload payloads
  InitialSlot -> Failure.nativeFailureInitialEvaluationPayload payloads
  CurrentSlot -> Failure.nativeFailureCurrentEvaluationPayload payloads
  LowSlot -> Failure.nativeFailureLowPayload payloads

-- A codec refusal leaves the concrete cursor unconsumed; an actual failed
-- retention call does not. Only the former can attempt a smaller failure DATA
-- record. NativeRetentionFailure always propagates without a write retry.
tryCodecAcknowledgement :: Pipeline () -> Pipeline (Maybe CodecError)
tryCodecAcknowledgement action =
  (action >> pure Nothing) `catchError` \case
    NativeProducerCodecFailure problem -> pure (Just problem)
    actual -> throwError actual

persistChildIssue :: Inputs -> ChildIssue -> Pipeline ()
persistChildIssue inputs (ChildIssue origin returned capture) = do
  child <- requireCurrent
  projected <-
    liftIO
      (Failure.projectSafeFailureData (currentPool child) origin returned capture (currentPayloads child))
  refused <- case projected of
    Left failure -> pure (Just failure)
    Right (root, pool) -> do
      modifyCurrent $ \actual -> actual {currentPool = pool}
      rejected <- tryCodecAcknowledgement (phaseAcknowledgement inputs "failure" FailurePhase root)
      pure (Project.ProjectionDataRejected <$> rejected)
  case refused of
    Nothing -> pure ()
    Just failure -> do
      -- No numerical/snapshot/raw projector is retried. Prior acknowledged
      -- objects remain in the physical chain through runPrevious. A Present
      -- slot omitted from THIS fallback is not unavailable at its public seam:
      -- resource status records this composite capture refusal with unknown
      -- individual payload size, never a claim that each payload exceeded cap.
      -- For other failures, no subpayload capture is attempted in this fallback.
      -- Preserve all prior non-Present source/capture classifications and the
      -- already safe origin's diagnostic with the new capture refusal status.
      let fallbackCapture = projectionCapture failure
          omitted Failure.NativePayloadPresent {} = case fallbackCapture of
            Failure.RefusedNativeCapture resource cap _ -> Failure.NativePayloadRefused resource cap Failure.UnknownNativeSize
            _ -> Failure.NativePayloadNotAttempted
          omitted value = value
          old = currentPayloads child
          fallback =
            Failure.NativeFailurePayloads
              (omitted (Failure.nativeFailureSnapshotPayload old))
              (omitted (Failure.nativeFailureColdSnapshotPayload old))
              (omitted (Failure.nativeFailureRawPayload old))
              (omitted (Failure.nativeFailureInitialEvaluationPayload old))
              (omitted (Failure.nativeFailureCurrentEvaluationPayload old))
              (omitted (Failure.nativeFailureLowPayload old))
      minimal <-
        liftIO
          (Failure.projectSafeFailureData (inputProducerPool inputs) origin returned fallbackCapture fallback)
      case minimal of
        Left stopped -> throwError (NativeProducerCaptureFailure stopped)
        Right (root, pool) -> do
          modifyCurrent $ \actual ->
            actual {currentPool = pool, currentProducer = inputProducerRoot inputs, currentPayloads = fallback}
          phaseAcknowledgement inputs "failure-capture" FailurePhase root

runFive :: Inputs -> Inventory.NativeAllocationData -> Pipeline Retain.NativeRetainedObjectData
runFive inputs inventory = do
  let allocated = zip Cohort.nativeSeedIndices (Inventory.allocationChildren inventory)
  unless
    (length allocated == 5)
    (throwError (NativeProducerRejected "checked allocation does not contain five prescribed indices"))
  mapM_ runOne allocated
  children <- gets (reverse . runCompleted)
  unless
    (fmap nativeChildIndex children == Cohort.nativeSeedIndices)
    (throwError (NativeProducerRejected "actual producer terminal ordered inventory differs"))
  appendBytes "cohort-terminal" (terminalInventory children)
 where
  runOne (index, allocationChild) = do
    let attempt = Inventory.attemptNonceDigest (Inventory.allocationChildNonce allocationChild)
        child =
          CurrentChild
            index
            attempt
            (inputProducerPool inputs)
            (inputProducerRoot inputs)
            Failure.emptyNativeFailurePayloads
            Nothing
            []
            False
            Failure.NoReturnObserved
            NativeDeviceNotQueried
            Nothing
    modify' $ \state -> state {runCurrent = Just child}
    (started, pool) <-
      codecOrStop
        (Schema.mkNodeData NStarted [VWord 1] >>= (\node -> Graph.internNode node (currentPool child)))
    modifyCurrent $ \actual -> actual {currentPool = pool}
    phaseAcknowledgement inputs "started" StartedPhase started
    selected <- case selectedChild (inputFamily inputs) index of
      Left reason -> do
        persistChildIssue inputs (captureIssue inputs StartedPhase reason Failure.NoReturnObserved)
        pure Nothing
      Right value -> pure (Just value)
    result <- case selected of
      Nothing -> pure Nothing
      Just actual -> do
        executed <- runExceptT (runSelected inputs actual)
        case executed of
          Left issue -> persistChildIssue inputs issue >> pure Nothing
          Right model -> pure (Just model)
    modifyCurrent $ \actual -> actual {currentNumerical = result}
    device <- captureActualDevice inputs
    afterProcess inputs
    completed <- requireCurrent
    let eligible = actualDeviceEligible inputs device
        disposition = case result of
          Nothing -> NativeChildFailed
          Just _ | eligible -> NativeChildCompleted
          Just _ -> NativeChildExecutionEvidenceFailure
        failure = case result of
          Nothing ->
            Just
              ( NativeProducerRejected
                  "actual native attempt failed; retained failure phase contains its complete safe observations"
              )
          Just _ | eligible -> Nothing
          Just _ ->
            Just
              ( NativeProducerRejected
                  "actual selected-device witness was absent, failed or differed from the required lane; numerical observations remain retained"
              )
        dataValue =
          NativeChildData index attempt disposition (reverse (currentObjects completed)) device failure result
    modify' $ \state ->
      state
        { runCompleted = dataValue : runCompleted state
        , runProduced = case result of
            Just model | eligible -> NativeProducedChild dataValue model : runProduced state
            _ -> runProduced state
        , runCurrent = Nothing
        }
  codecOrStop :: Either CodecError a -> Pipeline a
  codecOrStop = either (throwError . NativeProducerCodecFailure) pure

selectedChild :: FamilyRow -> Cohort.NativeSeedIndex -> Either Text SelectedChild
selectedChild family index = case family of
  NeuralRow row ->
    either
      (Left . Neural.nativeFailureDetail)
      (Right . NeuralChild)
      (Neural.selectNativeNeuralChildData row index)
  ArsRow row ->
    either
      (Left . Ars.nativeArsFailureDetail)
      (Right . ArsChild)
      (Ars.selectNativeArsChildData row index)
  ArenaRow row ->
    either
      (Left . Arena.nativeAlphaZeroFailureDetail)
      (Right . ArenaChild)
      (Arena.selectNativeAlphaZeroChildData row index)

runSelected :: Inputs -> SelectedChild -> ChildProgram NativeNumericalModelData
runSelected inputs child = case child of
  ArsChild actual -> runArsChild inputs actual
  NeuralChild actual -> case inputDevice inputs of
    Just device -> runNeuralChild inputs actual device
    Nothing ->
      throwError
        ( captureIssue
            inputs
            StartedPhase
            "internally selected neural device is absent"
            Failure.NoReturnObserved
        )
  ArenaChild actual -> case inputDevice inputs of
    Just device -> runArenaChild inputs actual device
    Nothing ->
      throwError
        ( captureIssue
            inputs
            StartedPhase
            "internally selected arena device is absent"
            Failure.NoReturnObserved
        )

-- The record is separate from73 and binds BOTH outer and actual inner IDs.
-- Its nested producer pool is canonical ordinary DATA, not an origin parser.
acknowledgeArsBegun :: Inputs -> Ars.NativeArsBegun -> Pipeline ()
acknowledgeArsBegun inputs begun = do
  child <- requireCurrent
  processOrStop
    ( Process.compareProducerProcessObservations
        (inputBefore inputs)
        (Ars.nativeArsBegunBeforeProcess begun)
    )
  projected <-
    liftIO
      ( ProducerData.projectProducerContextData
          Graph.emptyNodePool
          (Just (Process.recordedProducerObservation (Ars.nativeArsBegunBeforeProcess begun)))
          Nothing
          Nothing
      )
  (producer, pool) <- either (throwError . NativeProducerCaptureFailure) pure projected
  _ <-
    either (throwError . NativeProducerCodecFailure) pure (Graph.producerClosureBytes producer pool)
  innerContext <-
    either
      (throwError . NativeProducerCodecFailure)
      pure
      (Context.digestFromCanonicalText (Ars.nativeArsBegunContextDigest begun))
  let sourceCoverage = case Ars.nativeArsBegunSourceCoverage begun of
        Ars.NativeArsObservedLocal root stamp -> VList [VWord 0, VText (Text.pack root), stampValue stamp]
        Ars.NativeArsUnauthenticatedParentSource stamp -> VList [VWord 1, stampValue stamp]
      bytes =
        Wire.encodeStrict
          ( CBOR.encodeListLen 9
              <> CBOR.encodeString "jitml-native-ars-begun-lineage-v1"
              <> CBOR.encodeWord64 1
              <> CBOR.encodeBytes (digestBytes (currentAttempt child))
              <> CBOR.encodeBytes (digestBytes (inputAcquisition inputs))
              <> CBOR.encodeString (Ars.nativeArsBegunAttemptId begun)
              <> CBOR.encodeBytes (digestBytes innerContext)
              <> CBOR.encodeBytes (digestBytes producer)
              <> poolEncoding pool
              <> Wire.rawValueEncoding sourceCoverage
          )
  _ <- appendBytes (childLabel child "ars-begun") bytes
  pure ()

stampValue :: Source.SourceStamp -> NodeValue
stampValue stamp = VList [VWord (Source.stampAlgorithm stamp), VText (Source.stampSha256 stamp)]

poolEncoding :: Graph.NodePool -> CBOR.Encoding
poolEncoding pool = CBOR.encodeListLen (fromIntegral (length entries)) <> foldMap pair entries
 where
  entries = Graph.nodePoolEntries pool
  pair (digest, _, bytes) = CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes

captureActualDevice :: Inputs -> Pipeline NativeDeviceData
captureActualDevice inputs = do
  child <- requireCurrent
  actual <- case inputFamily inputs of
    ArsRow _ -> pure NativeNoMlpDevice
    _ | not (currentRawAcknowledged child) -> pure NativeDeviceNotQueried
    _ -> case inputDevice inputs of
      Nothing -> pure NativeDeviceNotQueried
      Just device -> do
        queried <- liftIO $ tryAny $ do
          result <- mlpdExecutionWitness device
          case result of
            Left reason -> Right . NativeDeviceFailed <$> Failure.captureNativeDiagnostic reason
            Right witness -> do
              let actualData = NativeDeviceReturned witness
              case deviceEncoding actualData of
                Left failure -> pure (Left failure)
                Right bytes -> do
                  _ <- evaluate (BS.length bytes)
                  pure (Right actualData)
        case queried of
          Right (Right result) -> pure result
          Right (Left failure) -> do
            persistChildIssue
              inputs
              ( captureIssue
                  inputs
                  FailurePhase
                  "actual device witness DATA exceeded its closed capture bounds"
                  (currentMaterialization child)
              )
            throwError (NativeProducerCodecFailure failure)
          Left exception -> NativeDeviceFailed <$> liftIO (producerExceptionDiagnostic exception)
  modifyCurrent $ \state -> state {currentDevice = actual}
  bytes <- either (throwError . NativeProducerCodecFailure) pure (deviceEncoding actual)
  _ <- appendBytes (childLabel child "device-observation") bytes
  pure actual

deviceEncoding :: NativeDeviceData -> Either CodecError ByteString
deviceEncoding actual = do
  case actual of
    NativeDeviceReturned (Just witness) -> do
      let raw = Witness.deviceExecutionWitnessToRaw witness
      mapM_
        (Schema.validateValue (TText GeneralTextBytes 1024) . VText)
        [ Witness.rawWitnessSubstrate raw
        , Witness.rawWitnessBackend raw
        , Witness.rawWitnessKernelHash raw
        , Witness.rawWitnessArtifactSha256 raw
        , Witness.rawWitnessExecutedIdentity raw
        ]
      Schema.validateValue (TText PathTextBytes 4096) (VText (Witness.rawWitnessArtifactPath raw))
    _ -> pure ()
  pure $
    Wire.encodeStrict
      ( CBOR.encodeListLen 3
          <> CBOR.encodeString "jitml-native-device-observation-v1"
          <> CBOR.encodeWord64 1
          <> body
      )
 where
  body = case actual of
    NativeNoMlpDevice -> CBOR.encodeListLen 1 <> CBOR.encodeWord64 0
    NativeDeviceNotQueried -> CBOR.encodeListLen 1 <> CBOR.encodeWord64 1
    NativeDeviceReturned Nothing -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 2 <> CBOR.encodeNull
    NativeDeviceReturned (Just witness) ->
      CBOR.encodeListLen 2
        <> CBOR.encodeWord64 2
        <> CBOR.encodeListLen 6
        <> foldMap
          CBOR.encodeString
          [ Witness.rawWitnessSubstrate raw
          , Witness.rawWitnessBackend raw
          , Witness.rawWitnessKernelHash raw
          , Witness.rawWitnessArtifactPath raw
          , Witness.rawWitnessArtifactSha256 raw
          , Witness.rawWitnessExecutedIdentity raw
          ]
     where
      raw = Witness.deviceExecutionWitnessToRaw witness
    NativeDeviceFailed diagnostic -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 3 <> diagnosticEncoding diagnostic

diagnosticEncoding :: Failure.NativeDiagnosticData -> CBOR.Encoding
diagnosticEncoding actual = case actual of
  Failure.CompleteNativeDiagnostic detail -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 0 <> CBOR.encodeString detail
  Failure.OversizeNativeDiagnostic size -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 1 <> sizeEncoding size
  Failure.UnmaterializableNativeDiagnostic -> CBOR.encodeListLen 1 <> CBOR.encodeWord64 2

sizeEncoding :: Failure.NativeSizeKnowledge -> CBOR.Encoding
sizeEncoding actual = case actual of
  Failure.ExactNativeSize count -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 0 <> CBOR.encodeWord64 count
  Failure.LowerBoundNativeSize count -> CBOR.encodeListLen 2 <> CBOR.encodeWord64 1 <> CBOR.encodeWord64 count
  Failure.UnknownNativeSize -> CBOR.encodeListLen 1 <> CBOR.encodeWord64 2

afterProcess :: Inputs -> Pipeline ()
afterProcess inputs = do
  child <- requireCurrent
  observed <- liftIO (Process.observeProducerProcess (sourceMode (inputContext inputs)))
  case observed of
    Left _ -> do
      persistChildIssue
        inputs
        ( captureIssue
            inputs
            FailurePhase
            "actual after-process/source observation failed"
            (currentMaterialization child)
        )
      throwError (NativeProducerProcessFailure "actual after-process/source observation failed")
    Right after -> do
      projected <-
        liftIO
          ( ProducerData.projectProducerContextData
              (currentPool child)
              (Just (Process.recordedProducerObservation (inputBefore inputs)))
              (Just (Process.recordedProducerObservation after))
              Nothing
          )
      (producer, pool) <- either (throwError . NativeProducerCaptureFailure) pure projected
      modifyCurrent $ \actual -> actual {currentProducer = producer, currentPool = pool}
      case currentTerminal child of
        Nothing -> throwError (NativeProducerRejected "actual child has no acknowledged terminal phase body")
        Just (phase, root) -> phaseAcknowledgement inputs "after-process" phase root
      -- The complete record is acknowledged even on mismatch; a mismatch
      -- cannot mint a produced child or permit subsequent canonical work.
      processOrStop (Process.compareProducerProcessObservations (inputBefore inputs) after)

terminalInventory :: [NativeChildData] -> ByteString
terminalInventory children =
  Wire.encodeStrict
    ( CBOR.encodeListLen 3
        <> CBOR.encodeString "jitml-native-five-terminal-v1"
        <> CBOR.encodeWord64 1
        <> CBOR.encodeListLen (fromIntegral (length children))
        <> foldMap child children
    )
 where
  child actual =
    CBOR.encodeListLen 4
      <> CBOR.encodeWord64 (fromIntegral (Cohort.nativeSeedIndexValue (nativeChildIndex actual)))
      <> CBOR.encodeBytes (digestBytes (nativeChildAttempt actual))
      <> CBOR.encodeWord64
        ( case nativeChildDisposition actual of
            NativeChildCompleted -> 0
            NativeChildFailed -> 1
            NativeChildExecutionEvidenceFailure -> 2
            NativeChildIncomplete -> 3
            NativeChildNotRun -> 4
        )
      <> CBOR.encodeListLen (fromIntegral (length objects))
      <> foldMap object objects
   where
    objects = nativeChildObjects actual
  object actual =
    CBOR.encodeListLen 3
      <> CBOR.encodeString (Retain.nativeRetainedObjectKey actual)
      <> CBOR.encodeString (Retain.nativeRetainedObjectSha256 actual)
      <> CBOR.encodeWord64 (Retain.nativeRetainedObjectBytes actual)

completePartial
  :: Inventory.NativeAllocationData -> RunState -> NativeProducerFailure -> [NativeChildData]
completePartial inventory state failure = zipWith (curry slot) Cohort.nativeSeedIndices (Inventory.allocationChildren inventory)
 where
  completed = reverse (runCompleted state)
  slot (index, allocation) = case find ((== index) . nativeChildIndex) completed of
    Just actual -> actual
    Nothing -> case runCurrent state of
      Just current
        | currentIndex current == index ->
            NativeChildData
              index
              (currentAttempt current)
              (if null (currentObjects current) then NativeChildNotRun else NativeChildIncomplete)
              (reverse (currentObjects current))
              (currentDevice current)
              (Just failure)
              (currentNumerical current)
      _ ->
        NativeChildData
          index
          (Inventory.attemptNonceDigest (Inventory.allocationChildNonce allocation))
          NativeChildNotRun
          []
          NativeDeviceNotQueried
          (Just failure)
          Nothing

producerExceptionDiagnostic :: SomeException -> IO Failure.NativeDiagnosticData
producerExceptionDiagnostic = captureRenderedDiagnostic . displayException

projectionDiagnostic :: Project.ProjectionFailure -> IO Failure.NativeDiagnosticData
projectionDiagnostic failure = case failure of
  Project.ProjectionSynchronousFailure (Project.ProjectionDiagnosticComplete detail) -> pure (Failure.CompleteNativeDiagnostic detail)
  Project.ProjectionSynchronousFailure Project.ProjectionDiagnosticUnavailable -> pure Failure.UnmaterializableNativeDiagnostic
  actual -> captureRenderedDiagnostic (show actual)

captureRenderedDiagnostic :: String -> IO Failure.NativeDiagnosticData
captureRenderedDiagnostic rendered = do
  captured <- tryAny $ do
    let cap = nativePhaseLimit DiagnosticTextBytes
        characters = take (fromInteger cap + 1) rendered
        count = toInteger (length characters)
    _ <- evaluate count
    if count > cap
      then pure (Failure.OversizeNativeDiagnostic (Failure.LowerBoundNativeSize (fromInteger count)))
      else Failure.captureNativeDiagnostic (Text.pack characters)
  pure $ case captured of
    Right actual -> actual
    Left _ -> Failure.UnmaterializableNativeDiagnostic

actualDeviceEligible :: Inputs -> NativeDeviceData -> Bool
actualDeviceEligible inputs actual = case (inputFamily inputs, actual) of
  (ArsRow _, NativeNoMlpDevice) -> True
  (NeuralRow _, NativeDeviceReturned (Just witness)) -> matches witness
  (ArenaRow _, NativeDeviceReturned (Just witness)) -> matches witness
  _ -> False
 where
  matches witness = Witness.witnessSubstrate witness == Cohort.nativeRlCohortBatchSubstrate (inputBatch inputs)

acknowledgeArsOrigin :: Inputs -> Ars.NativeArsExecutionOrigin -> Pipeline ()
acknowledgeArsOrigin inputs origin = do
  child <- requireCurrent
  processOrStop
    ( Process.compareProducerProcessObservations
        (Ars.nativeArsOriginBeforeProcess origin)
        (Ars.nativeArsOriginAfterProcess origin)
    )
  projected <-
    liftIO
      ( ProducerData.projectProducerContextData
          Graph.emptyNodePool
          (Just (Process.recordedProducerObservation (Ars.nativeArsOriginBeforeProcess origin)))
          (Just (Process.recordedProducerObservation (Ars.nativeArsOriginAfterProcess origin)))
          Nothing
      )
  (producer, pool) <- either (throwError . NativeProducerCaptureFailure) pure projected
  _ <-
    either (throwError . NativeProducerCodecFailure) pure (Graph.producerClosureBytes producer pool)
  actualContext <-
    either
      (throwError . NativeProducerCodecFailure)
      pure
      (Context.digestFromCanonicalText (Ars.nativeArsOriginContextDigest origin))
  let runtime = Ars.nativeArsOriginNumericalRuntime origin
      components =
        [ ArsTrainer.arsRuntimeOperatingSystem runtime
        , ArsTrainer.arsRuntimeArchitecture runtime
        , ArsTrainer.arsRuntimeCompiler runtime
        , ArsTrainer.arsRuntimeCompilerVersion runtime
        ]
  mapM_
    ( either (throwError . NativeProducerCodecFailure) pure
        . Schema.validateValue (TText ProducerComponentBytes 256)
        . VText
    )
    components
  either
    (throwError . NativeProducerCodecFailure)
    pure
    ( Schema.validateValue
        (TText GeneralTextBytes 1024)
        (VText (ArsTrainer.arsRuntimeArithmeticRecipe runtime))
    )
  let bytes =
        Wire.encodeStrict
          ( CBOR.encodeListLen 9
              <> CBOR.encodeString "jitml-native-ars-origin-lineage-v1"
              <> CBOR.encodeWord64 1
              <> CBOR.encodeBytes (digestBytes (currentAttempt child))
              <> CBOR.encodeBytes (digestBytes (inputAcquisition inputs))
              <> CBOR.encodeString (Ars.nativeArsOriginAttemptId origin)
              <> CBOR.encodeBytes (digestBytes actualContext)
              <> CBOR.encodeBytes (digestBytes producer)
              <> poolEncoding pool
              <> CBOR.encodeListLen 5
              <> foldMap CBOR.encodeString (components <> [ArsTrainer.arsRuntimeArithmeticRecipe runtime])
          )
  _ <- appendBytes (childLabel child "ars-origin") bytes
  pure ()

forceProducerFailure :: NativeProducerFailure -> ()
forceProducerFailure actual = case actual of
  NativeProducerRejected detail -> Text.length detail `seq` ()
  NativeProducerProcessFailure detail -> Text.length detail `seq` ()
  NativeProducerCaptureFailure failure -> case failure of
    Project.ProjectionDataRejected problem -> forceCodecFailure problem
    Project.ProjectionAllocationRefused resource cap observed -> resource `seq` cap `seq` observed `seq` ()
    Project.ProjectionSynchronousFailure diagnostic -> case diagnostic of
      Project.ProjectionDiagnosticComplete detail -> Text.length detail `seq` ()
      Project.ProjectionDiagnosticUnavailable -> ()
  NativeProducerCodecFailure problem -> forceCodecFailure problem
  NativeProducerRetentionFailure failure -> failure `seq` ()
  NativeProducerReferenceFailure stage diagnostic ->
    stage `seq` case diagnostic of
      Failure.CompleteNativeDiagnostic detail -> Text.length detail `seq` ()
      Failure.OversizeNativeDiagnostic size -> size `seq` ()
      Failure.UnmaterializableNativeDiagnostic -> ()

forceCodecFailure :: CodecError -> ()
forceCodecFailure problem = case problem of
  Malformed detail -> Text.length detail `seq` ()
  NonCanonical detail -> Text.length detail `seq` ()
  WrongReferenceType digest detail -> BS.length (digestBytes digest) `seq` Text.length detail `seq` ()
  ResourceExceeded resource cap observed -> resource `seq` cap `seq` observed `seq` ()
  UnexpectedEnd offset -> offset `seq` ()
  MissingReference digest -> BS.length (digestBytes digest) `seq` ()
  HashMismatch digest -> BS.length (digestBytes digest) `seq` ()
  DigestCollision digest -> BS.length (digestBytes digest) `seq` ()
  ReferenceCycle digest -> BS.length (digestBytes digest) `seq` ()
  UnreachablePoolMember digest -> BS.length (digestBytes digest) `seq` ()
