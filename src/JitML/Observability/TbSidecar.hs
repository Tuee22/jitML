{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.TbSidecar
  ( checkpointDoneToMarker
  , dispatchCheckpointDone
  , dispatchCheckpointPayload
  , dispatchTensorBoardSideEffect
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
import JitML.Proto.Training
  ( CheckpointDone (..)
  , parseTrainingCheckpointDone
  )
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Consumer (EventDomain (..))
import JitML.Service.Retry (ServiceError)

-- | Sprint 4.6 wiring: take a `CheckpointDone`-shaped record (step,
-- manifest sha, experiment hash, etc.) and write the typed
-- `TbCheckpointMarker` CBOR sidecar to the canonical key produced by
-- `checkpointSidecarKey`. Returns the broker-assigned ETag on success or
-- the typed `ServiceError` from the failed PUT. The caller can wire this
-- into the daemon's `CheckpointDone` handler.
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
-- (the in-memory shape of a `CheckpointDone` event) into the sidecar
-- writer using the marker's own `tcmExperimentSha` / `tcmStep` /
-- `tcmManifestSha` fields. This is the function the daemon's
-- per-domain dispatcher calls when an `inference.event.<substrate>`
-- envelope deserialises to a `CheckpointDone`. The key derivation
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

dispatchCheckpointPayload
  :: (HasMinIO m)
  => Text
  -> m (Maybe (Either ServiceError ETag))
dispatchCheckpointPayload payload =
  case parseTrainingCheckpointDone payload of
    Nothing -> pure Nothing
    Just checkpoint -> Just <$> dispatchCheckpointDone (checkpointDoneToMarker checkpoint)

dispatchTensorBoardSideEffect
  :: (HasMinIO m)
  => EventDomain
  -> Text
  -> m (Maybe (Either ServiceError ETag))
dispatchTensorBoardSideEffect domain payload =
  case domain of
    TrainingDomain -> dispatchCheckpointPayload payload
    InferenceDomain -> dispatchCheckpointPayload payload
    TuneDomain -> pure Nothing
    RlDomain -> pure Nothing
