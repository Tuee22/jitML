-- | Safely capture ordinary public numerical DATA into the bounded node graph.
-- A projected digest/pool proves no origin, durable barrier, provider, Store
-- admission, restoration, learning, criterion or qualification. This module
-- cannot initialize, evaluate or continue a trainer and accepts no callbacks.
module JitML.Checkpoint.NativePhase.Projection
  ( ProjectionFailure (..)
  , ProjectionDiagnostic (..)
  , projectNativeReturnSpecData
  , projectNativeHerScheduleData
  , projectNeuralSnapshotData
  , projectPpoSnapshotData
  , projectDqnSnapshotData
  , projectQrSnapshotData
  , projectContinuousSnapshotData
  , projectHerSnapshotData
  , projectArsSnapshotData
  , projectAlphaZeroSnapshotData
  , projectNeuralReturnedData
  , projectArsReturnedData
  , projectAlphaZeroReturnedData
  , projectReturnEvaluationData
  , projectHerEvaluationData
  , projectArenaEvaluationData
  , projectLowNeuralFailureData
  ) where

import JitML.Checkpoint.NativePhase.Graph (NodePool)
import JitML.Checkpoint.NativePhase.Projection.Arena qualified as Arena
import JitML.Checkpoint.NativePhase.Projection.Build
  ( ProjectionDiagnostic (..)
  , ProjectionFailure (..)
  , projectSafely
  )
import JitML.Checkpoint.NativePhase.Projection.Cases qualified as Cases
import JitML.Checkpoint.NativePhase.Projection.Evaluations qualified as Evaluation
import JitML.Checkpoint.NativePhase.Projection.Returns qualified as Return
import JitML.Checkpoint.NativePhase.Projection.Snapshots qualified as Snapshot
import JitML.Checkpoint.NativePhase.Types (Digest)
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as ArenaEvaluation
import JitML.RL.AlphaZero.PreparedTrainer qualified as AZ
import JitML.RL.NativeHerEvaluation qualified as HerEvaluation
import JitML.RL.NativeHerReferences qualified as HerReference
import JitML.RL.NativeReturnEvaluation qualified as ReturnEvaluation
import JitML.RL.NativeReturnReferences qualified as ReturnReference
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.ProductBudget qualified as Plan

-- These ordinary spec/schedule projectors use the same safe bounded DATA
-- builder as the other public projections; they create no execution capability.
projectNativeReturnSpecData
  :: NodePool
  -> ReturnReference.NativeReturnReferenceSpec
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectNativeReturnSpecData pool actual = projectSafely pool (Cases.returnSpec actual)

projectNativeHerScheduleData
  :: NodePool -> HerReference.NativeHerGoalSchedule -> IO (Either ProjectionFailure (Digest, NodePool))
projectNativeHerScheduleData pool actual = projectSafely pool (Cases.herSchedule actual)

projectNeuralSnapshotData
  :: NodePool -> Low.NeuralSnapshot -> IO (Either ProjectionFailure (Digest, NodePool))
projectNeuralSnapshotData pool actual = projectSafely pool (Snapshot.neuralSnapshot actual)

projectPpoSnapshotData
  :: NodePool -> Ppo.PpoPreparedSnapshot state -> IO (Either ProjectionFailure (Digest, NodePool))
projectPpoSnapshotData pool actual = projectSafely pool (Snapshot.ppoSnapshot actual)

projectDqnSnapshotData
  :: NodePool -> Dqn.DqnPreparedSnapshot state -> IO (Either ProjectionFailure (Digest, NodePool))
projectDqnSnapshotData pool actual = projectSafely pool (Snapshot.dqnSnapshot actual)

projectQrSnapshotData
  :: NodePool -> Qr.QrDqnPreparedSnapshot state -> IO (Either ProjectionFailure (Digest, NodePool))
projectQrSnapshotData pool actual = projectSafely pool (Snapshot.qrSnapshot actual)

projectContinuousSnapshotData
  :: NodePool
  -> Continuous.ContinuousPreparedSnapshot state
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectContinuousSnapshotData pool actual = projectSafely pool (Snapshot.continuousSnapshot actual)

projectHerSnapshotData
  :: NodePool -> Her.HerPreparedSnapshot -> IO (Either ProjectionFailure (Digest, NodePool))
projectHerSnapshotData pool actual = projectSafely pool (Snapshot.herSnapshot actual)

projectArsSnapshotData
  :: NodePool -> Ars.ArsPreparedSnapshot -> IO (Either ProjectionFailure (Digest, NodePool))
projectArsSnapshotData pool actual = projectSafely pool (Snapshot.arsSnapshot actual)

projectAlphaZeroSnapshotData
  :: NodePool -> AZ.AlphaZeroPreparedSnapshot -> IO (Either ProjectionFailure (Digest, NodePool))
projectAlphaZeroSnapshotData pool actual = projectSafely pool (Snapshot.alphaZeroSnapshot actual)

projectNeuralReturnedData
  :: NodePool -> Low.NeuralReturnedData -> IO (Either ProjectionFailure (Digest, NodePool))
projectNeuralReturnedData pool actual = projectSafely pool (Return.neuralReturned actual)

-- Supplied compiled context is encoded as supplied DATA, not actual-origin or
-- recipe correspondence proof. The high producer owns that independent check.
projectArsReturnedData
  :: NodePool
  -> Plan.CompiledRlPlan
  -> Ars.ArsTrainObservation
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectArsReturnedData pool suppliedPlan actual = projectSafely pool (Return.arsReturned suppliedPlan actual)

projectAlphaZeroReturnedData
  :: NodePool -> AZ.AlphaZeroTrainObservation -> IO (Either ProjectionFailure (Digest, NodePool))
projectAlphaZeroReturnedData pool actual = projectSafely pool (Return.alphaZeroReturned actual)

projectReturnEvaluationData
  :: NodePool
  -> ReturnEvaluation.RawNativeReturnEvaluation
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectReturnEvaluationData pool actual = projectSafely pool (Evaluation.returnEvaluation actual)

projectHerEvaluationData
  :: NodePool -> HerEvaluation.RawNativeHerEvaluation -> IO (Either ProjectionFailure (Digest, NodePool))
projectHerEvaluationData pool actual = projectSafely pool (Evaluation.herEvaluation actual)

projectArenaEvaluationData
  :: NodePool
  -> ArenaEvaluation.RawNativeArenaEvaluation
  -> IO (Either ProjectionFailure (Digest, NodePool))
projectArenaEvaluationData pool actual = projectSafely pool (Arena.arenaEvaluation actual)

projectLowNeuralFailureData
  :: NodePool -> Low.NeuralAttemptFailure -> IO (Either ProjectionFailure (Digest, NodePool))
projectLowNeuralFailureData pool actual = projectSafely pool (Return.lowNeuralFailure actual)
