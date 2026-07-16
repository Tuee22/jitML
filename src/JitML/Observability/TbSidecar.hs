{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.TbSidecar
  ( checkpointDoneToMarker
  , dispatchCheckpointDone
  , writeCheckpointSidecar
  )
where

import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Word (Word64)

import JitML.Observability.TensorBoard
  ( TbCheckpointMarker (..)
  , checkpointSidecarKey
  , encodeTbCheckpointMarker
  )
import JitML.Proto.Training (CheckpointDone (..))
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError)

-- | Sprint 4.6 wiring: take checkpoint-candidate fields (step, manifest SHA,
-- experiment hash, etc.) and write the typed
-- `TbCheckpointMarker` CBOR sidecar to the canonical key produced by
-- `checkpointSidecarKey`. Returns the broker-assigned ETag on success or
-- the typed `ServiceError` from the failed PUT. Sidecar persistence records
-- observability metadata only; it does not promote a candidate checkpoint to
-- completed or inference-eligible state.
writeCheckpointSidecar
  :: (HasMinIO m)
  => Text
  -- ^ experiment hash
  -> Word64
  -- ^ training step
  -> Text
  -- ^ manifest sha
  -> TbCheckpointMarker
  -> m (Either ServiceError ETag)
writeCheckpointSidecar experimentHash step manifestSha marker = do
  let bucket = BucketName "jitml-tensorboard"
      key = checkpointSidecarKey experimentHash (fromIntegral step) manifestSha
      ref = ObjectRef bucket (ObjectKey key)
      payload = LazyByteString.toStrict (encodeTbCheckpointMarker marker)
  putBlobBytesIfAbsent ref payload

-- | Consumer-domain entry point: route a typed `TbCheckpointMarker`
-- (the in-memory shape projected from a checkpoint candidate) into the sidecar
-- writer using the marker's own `tcmExperimentSha` / `tcmStep` /
-- `tcmManifestSha` fields. A typed training-event handler may call this for a
-- `TrainingCheckpoint` candidate or for the candidate nested inside a
-- `TrainingCompletedCheckpoint`; the distinction is retained outside this
-- observability adapter. The key derivation
-- and write semantics are identical to `writeCheckpointSidecar`;
-- this variant just removes the field-redundancy at the call site.
dispatchCheckpointDone
  :: (HasMinIO m)
  => TbCheckpointMarker
  -> m (Either ServiceError ETag)
dispatchCheckpointDone marker =
  writeCheckpointSidecar
    (tcmExperimentSha marker)
    (tcmStep marker)
    (tcmManifestSha marker)
    marker

checkpointDoneToMarker :: CheckpointDone -> TbCheckpointMarker
checkpointDoneToMarker checkpoint =
  TbCheckpointMarker
    { tcmStep = cdStep checkpoint
    , tcmEpoch = cdEpoch checkpoint
    , tcmManifestSha = cdManifestSha checkpoint
    , tcmExperimentSha = cdExperimentHash checkpoint
    , tcmTrialSha = cdTrialSha checkpoint
    , tcmRunUuid = cdRunUuid checkpoint
    , tcmMetricsAtStep = cdMetricsAtStep checkpoint
    }
