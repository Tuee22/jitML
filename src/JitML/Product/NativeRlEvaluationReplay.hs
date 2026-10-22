{-# LANGUAGE OverloadedStrings #-}

-- | Re-evaluate the actual immutable initial/final models of an opaque produced
-- cohort. This does not load an admitted artifact, authenticate a parent or
-- prove source/loaded-image coherence, retention, learning or Store eligibility.
module JitML.Product.NativeRlEvaluationReplay
  ( NativeEvaluationReplayResult
  , NativeEvaluationReplayedCohort
  , NativeEvaluationReplayReport (..)
  , NativeEvaluationReplayChildData (..)
  , NativeEvaluationReplayData (..)
  , NativeReplayStage (..)
  , NativeReplayCapture (..)
  , NativeReplayFinding (..)
  , replayNativeProducedEvaluations
  , nativeEvaluationReplayReport
  , nativeEvaluationReplaySucceeded
  , nativeEvaluationReplayedCohort
  , nativeEvaluationReplayedProducer
  , nativeEvaluationReplayedReport
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask)
import Data.ByteString (ByteString)
import Data.Text (Text)

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.SchemaTable (FieldType (TText))
import JitML.Checkpoint.NativePhase.Types
  ( CodecError
  , Digest
  , NodeValue (VText)
  , Resource (GeneralTextBytes, PathTextBytes)
  )
import JitML.Env.Env (App, Env)
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Numerics.MlpDevice (MlpDevice (mlpdExecutionWitness))
import JitML.Numerics.MlpDeviceSelect qualified as Select
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as Arena
import JitML.Product.NativePreparedArsAttempt qualified as Ars
import JitML.Product.NativePreparedNeuralAttempt qualified as Neural
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as ArenaEvaluation
import JitML.RL.NativeHerEvaluation qualified as HerEvaluation
import JitML.RL.NativeReturnEvaluation qualified as ReturnEvaluation
import JitML.Substrate (Substrate)

data NativeReplayStage = ReplayInitialEvaluation | ReplayFinalEvaluation
  deriving stock (Eq, Show)

-- Canonical node bytes retain raw Double bits, including signed zero and NaNs.
-- These ordinary values can be forged and cannot construct a replay capsule.
data NativeReplayCapture = NativeReplayCapture !Digest ![(Digest, ByteString)]
  deriving stock (Eq, Show)

data NativeReplayFinding
  = ReplayNotAttempted !Text
  | ReplaySourceEvaluationIncomplete
  | ReplaySourceCaptureFailed !Project.ProjectionFailure
  | ReplayActualCaptureFailed !Project.ProjectionFailure
  | ReplayGraphFailed !CodecError
  | ReplaySynchronousFailure
  | ReplayActualEvaluationIncomplete
  | ReplayCanonicalBytesDiffer
  | ReplayDeviceEvidenceMissing
  | ReplayDeviceEvidenceFailed
  | ReplayDeviceLaneDiffers
  | ReplayDeviceProducerDiffers
  | ReplayDeviceDataRejected !CodecError
  | ReplayProcessObservationFailed
  | ReplayProcessChanged
  deriving stock (Eq, Show)

data NativeEvaluationReplayData = NativeEvaluationReplayData
  { nativeReplayStage :: !NativeReplayStage
  , nativeReplayExpectedRoot :: !(Maybe Digest)
  , nativeReplayActualCapture :: !(Maybe NativeReplayCapture)
  , nativeReplayFindings :: ![NativeReplayFinding]
  }
  deriving stock (Eq, Show)

data NativeEvaluationReplayChildData = NativeEvaluationReplayChildData
  { nativeReplayChildIndex :: !Int
  , nativeReplayChildAttempt :: !Digest
  , nativeReplayChildEvaluations :: ![NativeEvaluationReplayData]
  , nativeReplayChildDevice :: !Producer.NativeDeviceData
  , nativeReplayChildFindings :: ![NativeReplayFinding]
  }
  deriving stock (Eq, Show)

data NativeEvaluationReplayReport = NativeEvaluationReplayReport
  { nativeReplayProcessBefore :: !(Maybe Process.RecordedProducerObservation)
  , nativeReplayProcessAfter :: !(Maybe Process.RecordedProducerObservation)
  , nativeReplayChildren :: ![NativeEvaluationReplayChildData]
  , nativeReplayReportFindings :: ![NativeReplayFinding]
  }
  deriving stock (Eq, Show)

-- Private positional constructors bind the exact original cohort and all ten
-- actual comparison results. There is no DATA/parser/callback capsule factory.
data NativeEvaluationReplayResult
  = NativeEvaluationReplayResult
      !Producer.NativeProducedCohort
      !NativeEvaluationReplayReport
data NativeEvaluationReplayedCohort
  = NativeEvaluationReplayedCohort
      !Producer.NativeProducedCohort
      !NativeEvaluationReplayReport

nativeEvaluationReplayReport :: NativeEvaluationReplayResult -> NativeEvaluationReplayReport
nativeEvaluationReplayReport (NativeEvaluationReplayResult _ report) = report

nativeEvaluationReplaySucceeded :: NativeEvaluationReplayResult -> Bool
nativeEvaluationReplaySucceeded = null . nativeReplayReportFindings . nativeEvaluationReplayReport

nativeEvaluationReplayedCohort
  :: NativeEvaluationReplayResult -> Maybe NativeEvaluationReplayedCohort
nativeEvaluationReplayedCohort (NativeEvaluationReplayResult cohort report)
  | null (nativeReplayReportFindings report) = Just (NativeEvaluationReplayedCohort cohort report)
  | otherwise = Nothing

nativeEvaluationReplayedProducer :: NativeEvaluationReplayedCohort -> Producer.NativeProducedCohort
nativeEvaluationReplayedProducer (NativeEvaluationReplayedCohort cohort _) = cohort

nativeEvaluationReplayedReport :: NativeEvaluationReplayedCohort -> NativeEvaluationReplayReport
nativeEvaluationReplayedReport (NativeEvaluationReplayedCohort _ report) = report

-- The entry accepts no numerical, witness, device, evaluator or Store callback.
-- The absence of a source observation is explicit; a later authenticated command
-- must bind the process, source and physical artifact independently.
replayNativeProducedEvaluations :: Producer.NativeProducedCohort -> App NativeEvaluationReplayResult
replayNativeProducedEvaluations cohort = do
  env <- ask
  liftIO $ do
    before <- observeProcess
    children <- case before of
      Left _ -> pure (fmap notRun (Producer.nativeProducedChildren cohort))
      Right _ -> traverse (replayChild env) (Producer.nativeProducedChildren cohort)
    after <- observeProcess
    let observations = case (before, after) of
          (Right a, Right b) -> case Process.compareProducerProcessObservations a b of
            Left _ -> [ReplayProcessChanged]
            Right () -> []
          _ -> [ReplayProcessObservationFailed]
        findings = observations <> concatMap childFindings children
        report = NativeEvaluationReplayReport (recorded before) (recorded after) children findings
    pure (NativeEvaluationReplayResult cohort report)
 where
  recorded = either (const Nothing) (Just . Process.recordedProducerObservation)
  childFindings child =
    nativeReplayChildFindings child
      <> concatMap nativeReplayFindings (nativeReplayChildEvaluations child)
  notRun produced =
    let child = Producer.nativeProducedChildData produced
     in NativeEvaluationReplayChildData
          (Cohort.nativeSeedIndexValue (Producer.nativeChildIndex child))
          (Producer.nativeChildAttempt child)
          [notAttempted stage "actual replay before-process observation failed" | stage <- stages]
          Producer.NativeDeviceNotQueried
          []

observeProcess :: IO (Either () Process.ObservedProducerProcess)
observeProcess = do
  observed <- tryAny (Process.observeProducerProcess Process.NoSourceObservation)
  pure $ case observed of
    Right (Right actual) -> Right actual
    _ -> Left ()

stages :: [NativeReplayStage]
stages = [ReplayInitialEvaluation, ReplayFinalEvaluation]

notAttempted :: NativeReplayStage -> Text -> NativeEvaluationReplayData
notAttempted stage reason = NativeEvaluationReplayData stage Nothing Nothing [ReplayNotAttempted reason]

replayChild :: Env -> Producer.NativeProducedChild -> IO NativeEvaluationReplayChildData
replayChild env produced = do
  let child = Producer.nativeProducedChildData produced
      index = Cohort.nativeSeedIndexValue (Producer.nativeChildIndex child)
      attempt = Producer.nativeChildAttempt child
  (evaluations, deviceData, findings) <- case Producer.nativeProducedModelData produced of
    Producer.NativeNeuralNumericalData actual -> do
      let returned = Neural.nativeEvaluatedReturnedData actual
          batch = Neural.nativeNeuralRowBatch (Neural.nativeNeuralChildRow (Neural.nativeReturnedChild returned))
          lane = Cohort.nativeRlCohortBatchSubstrate batch
          device = Select.rlDeviceForSubstrate lane env
      initial <-
        replayNeural device ReplayInitialEvaluation (Neural.nativeReturnedInitialEvaluation returned)
      final <- replayNeural device ReplayFinalEvaluation (Neural.nativeEvaluatedFinalEvaluation actual)
      (witness, problems) <- observeDevice lane (Producer.nativeChildDevice child) device
      pure ([initial, final], witness, problems)
    Producer.NativeArsNumericalData actual -> do
      let returned = Ars.nativeArsFinalReturned actual
      initial <-
        replayReturn Nothing ReplayInitialEvaluation (Ars.nativeArsReturnedInitialEvaluation returned)
      final <- case Ars.nativeArsFinalEvaluation actual of
        Nothing -> pure (notAttempted ReplayFinalEvaluation "actual produced ARS final evaluation is absent")
        Just evaluation -> replayReturn Nothing ReplayFinalEvaluation evaluation
      pure ([initial, final], Producer.NativeNoMlpDevice, [])
    Producer.NativeArenaNumericalData actual -> do
      let returned = Arena.nativeAlphaZeroEvaluatedReturnedData actual
          row = Arena.nativeAlphaZeroChildRow (Arena.nativeAlphaZeroReturnedChild returned)
          lane = Cohort.nativeRlCohortBatchSubstrate (Arena.nativeAlphaZeroRowBatch row)
          device = Select.rlDeviceForSubstrate lane env
      initial <-
        replayArena device ReplayInitialEvaluation (Arena.nativeAlphaZeroReturnedInitialEvaluation returned)
      final <-
        replayArena device ReplayFinalEvaluation (Arena.nativeAlphaZeroEvaluatedFinalEvaluation actual)
      (witness, problems) <- observeDevice lane (Producer.nativeChildDevice child) device
      pure ([initial, final], witness, problems)
  pure (NativeEvaluationReplayChildData index attempt evaluations deviceData findings)

observeDevice
  :: Substrate
  -> Producer.NativeDeviceData
  -> MlpDevice
  -> IO (Producer.NativeDeviceData, [NativeReplayFinding])
observeDevice lane expected device = do
  observed <- tryAny $ do
    returned <- mlpdExecutionWitness device
    case returned of
      Left reason -> do
        diagnostic <- Failure.captureNativeDiagnostic reason
        pure (Producer.NativeDeviceFailed diagnostic, [ReplayDeviceEvidenceFailed])
      Right Nothing -> pure (Producer.NativeDeviceReturned Nothing, [ReplayDeviceEvidenceMissing])
      Right actual@(Just witness) -> do
        let raw = Witness.deviceExecutionWitnessToRaw witness
            checked = do
              mapM_
                (Schema.validateValue (TText GeneralTextBytes 1024) . VText)
                [ Witness.rawWitnessSubstrate raw
                , Witness.rawWitnessBackend raw
                , Witness.rawWitnessKernelHash raw
                , Witness.rawWitnessArtifactSha256 raw
                , Witness.rawWitnessExecutedIdentity raw
                ]
              Schema.validateValue (TText PathTextBytes 4096) (VText (Witness.rawWitnessArtifactPath raw))
        materialized <- evaluate checked
        case materialized of
          Left failure ->
            pure
              ( Producer.NativeDeviceFailed
                  (Failure.CompleteNativeDiagnostic "actual replay witness DATA capture was rejected")
              , [ReplayDeviceDataRejected failure]
              )
          Right () -> do
            sameLane <- evaluate (Witness.witnessSubstrate witness == lane)
            sameProducer <- evaluate $ case expected of
              Producer.NativeDeviceReturned (Just original) -> Witness.deviceExecutionWitnessToRaw original == raw
              _ -> False
            pure
              ( Producer.NativeDeviceReturned actual
              , [ReplayDeviceLaneDiffers | not sameLane] <> [ReplayDeviceProducerDiffers | not sameProducer]
              )
  case observed of
    Left exception -> do
      diagnostic <- Failure.captureNativeExceptionDiagnostic exception
      pure (Producer.NativeDeviceFailed diagnostic, [ReplayDeviceEvidenceFailed])
    Right actual -> pure actual

replayNeural
  :: MlpDevice -> NativeReplayStage -> Neural.NativeEvaluationData -> IO NativeEvaluationReplayData
replayNeural device stage actual = case actual of
  Neural.NativeReturnEvaluation value -> replayReturn (Just device) stage value
  Neural.NativeHerEvaluation value ->
    replayOne
      stage
      (HerEvaluation.nativeHerEvaluationStatus value == HerEvaluation.NativeHerEvaluationComplete)
      Project.projectHerEvaluationData
      value
      ( HerEvaluation.evaluateNativeHerPolicy
          device
          (HerEvaluation.nativeHerEvaluationSchedule value)
          (HerEvaluation.nativeHerEvaluationConfig value)
          (HerEvaluation.nativeHerEvaluationParameters value)
      )
      ((== HerEvaluation.NativeHerEvaluationComplete) . HerEvaluation.nativeHerEvaluationStatus)

replayReturn
  :: Maybe MlpDevice
  -> NativeReplayStage
  -> ReturnEvaluation.RawNativeReturnEvaluation
  -> IO NativeEvaluationReplayData
replayReturn device stage actual = case (device, ReturnEvaluation.nativeEvaluationPolicy actual) of
  (Just selected, ReturnEvaluation.NativeNeuralEvaluation policy) ->
    run
      ( ReturnEvaluation.evaluateNativeNeuralReturnPolicy
          selected
          (ReturnEvaluation.nativeEvaluationSpec actual)
          policy
      )
  (Nothing, ReturnEvaluation.NativeArsHostEvaluation config theta) ->
    run
      ( evaluate
          ( ReturnEvaluation.evaluateNativeArsReturnPolicy
              (ReturnEvaluation.nativeEvaluationSpec actual)
              config
              theta
          )
      )
  _ -> pure (notAttempted stage "actual replay policy family differs from the produced model")
 where
  run action =
    replayOne
      stage
      (ReturnEvaluation.nativeEvaluationStatus actual == ReturnEvaluation.NativeEvaluationComplete)
      Project.projectReturnEvaluationData
      actual
      action
      ((== ReturnEvaluation.NativeEvaluationComplete) . ReturnEvaluation.nativeEvaluationStatus)

replayArena
  :: MlpDevice
  -> NativeReplayStage
  -> ArenaEvaluation.RawNativeArenaEvaluation
  -> IO NativeEvaluationReplayData
replayArena device stage actual = case ArenaEvaluation.nativeArenaEvaluationInput actual of
  Just input | ArenaEvaluation.nativeArenaInputScope input == ArenaEvaluation.CanonicalNativeArena ->
    case ArenaEvaluation.nativeArenaInputSpecification input of
      Just spec ->
        replayOne
          stage
          (ArenaEvaluation.nativeArenaEvaluationStatus actual == ArenaEvaluation.NativeArenaEvaluationComplete)
          Project.projectArenaEvaluationData
          actual
          ( ArenaEvaluation.evaluateNativeArenaPolicy
              device
              spec
              (ArenaEvaluation.nativeArenaInputTape input)
              (ArenaEvaluation.nativeArenaInputPolicy input)
          )
          ((== ArenaEvaluation.NativeArenaEvaluationComplete) . ArenaEvaluation.nativeArenaEvaluationStatus)
      Nothing -> pure (notAttempted stage "actual canonical arena specification is absent")
  _ -> pure (notAttempted stage "actual produced arena input is absent or a fixture")

-- Source capture precedes actual replay. Neither a rejected/lazy source nor a
-- failed actual capture is retried. The actual capture is retained even when it
-- differs or is incomplete. Async cancellation propagates through tryAny.
replayOne
  :: NativeReplayStage
  -> Bool
  -> (Graph.NodePool -> value -> IO (Either Project.ProjectionFailure (Digest, Graph.NodePool)))
  -> value
  -> IO value
  -> (value -> Bool)
  -> IO NativeEvaluationReplayData
replayOne stage sourceComplete project source action complete = do
  expected <- capture project source
  case expected of
    Left finding -> pure (NativeEvaluationReplayData stage Nothing Nothing [finding])
    Right wanted@(NativeReplayCapture root _) ->
      if not sourceComplete
        then pure (NativeEvaluationReplayData stage (Just root) Nothing [ReplaySourceEvaluationIncomplete])
        else do
          attempted <- tryAny $ do
            actual <- action
            captured <- capture project actual
            case captured of
              Left finding -> pure (Nothing, [actualFinding finding])
              Right observed -> do
                finished <- evaluate (complete actual)
                pure
                  ( Just observed
                  , [ReplayActualEvaluationIncomplete | not finished]
                      <> [ReplayCanonicalBytesDiffer | observed /= wanted]
                  )
          pure $ case attempted of
            Left _ -> NativeEvaluationReplayData stage (Just root) Nothing [ReplaySynchronousFailure]
            Right (observed, findings) -> NativeEvaluationReplayData stage (Just root) observed findings
 where
  actualFinding (ReplaySourceCaptureFailed failure) = ReplayActualCaptureFailed failure
  actualFinding other = other

capture
  :: (Graph.NodePool -> value -> IO (Either Project.ProjectionFailure (Digest, Graph.NodePool)))
  -> value
  -> IO (Either NativeReplayFinding NativeReplayCapture)
capture project value = do
  projected <- project Graph.emptyNodePool value
  pure $ case projected of
    Left failure -> Left (ReplaySourceCaptureFailed failure)
    Right (root, pool) -> case Graph.validateReachableData [root] pool >> Graph.reachableNodePool [root] pool of
      Left failure -> Left (ReplayGraphFailed failure)
      Right exact ->
        Right
          (NativeReplayCapture root [(digest, bytes) | (digest, _, bytes) <- Graph.nodePoolEntries exact])
