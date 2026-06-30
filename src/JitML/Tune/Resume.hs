{-# LANGUAGE OverloadedStrings #-}

module JitML.Tune.Resume
  ( ResumeOutcome (..)
  , ResumeReadFailure (..)
  , persistTrialTranscript
  , replaySweep
  )
where

import Codec.Serialise (deserialiseOrFail, serialise)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (rights)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError)
import JitML.Tune.Catalog (TrialTranscript (..), trialStorageKey)

data ResumeOutcome = ResumeOutcome
  { resumedSeeds :: [Int]
  , resumedTrials :: [TrialTranscript]
  , resumeReadFailures :: [(Text, ResumeReadFailure)]
  }
  deriving stock (Eq, Show)

data ResumeReadFailure
  = ResumeServiceFailure ServiceError
  | ResumeDecodeFailure Text
  deriving stock (Eq, Show)

-- | Persist a single trial transcript to MinIO under
-- `trialStorageKey experimentHash trialSeed`. Returns the broker-assigned
-- ETag on success or the typed `ServiceError` from the failed PUT.
persistTrialTranscript
  :: (HasMinIO m)
  => TrialTranscript
  -> m (Either ServiceError ETag)
persistTrialTranscript transcript = do
  let bucket = BucketName "jitml-trials"
      key =
        trialStorageKey
          (transcriptExperimentHash transcript)
          (transcriptTrialSeed transcript)
      ref = ObjectRef bucket (ObjectKey key)
      payload = LazyByteString.toStrict (serialise transcript)
  putBlobBytesIfAbsent ref payload

-- | Replay a partial sweep by reading the trial transcripts for the
-- given seed list back from MinIO. The order is preserved (caller is
-- responsible for canonical ordering per
-- [../../README.md → Canonical replay order]). Missing transcripts are
-- recorded as `ResumeServiceFailure`; corrupt transcripts are recorded as
-- `ResumeDecodeFailure`. The caller can decide whether to abort or re-run a
-- trial without forcing a latent bottom.
replaySweep
  :: (HasMinIO m)
  => Text
  -- ^ experiment hash
  -> [Int]
  -- ^ trial seeds, in canonical replay order
  -> m ResumeOutcome
replaySweep experimentHash seeds = do
  results <- traverse readOne seeds
  let trials = rights results
      failures = [(key, err) | (key, Left err) <- zip keys results]
      keys = fmap (trialStorageKey experimentHash) seeds
  pure
    ResumeOutcome
      { resumedSeeds = seeds
      , resumedTrials = trials
      , resumeReadFailures = failures
      }
 where
  readOne seed = do
    let bucket = BucketName "jitml-trials"
        key = trialStorageKey experimentHash seed
        ref = ObjectRef bucket (ObjectKey key)
    payload <- minioReadBytes ref
    case payload of
      Left err -> pure (Left (ResumeServiceFailure err))
      Right bytes ->
        case deserialiseOrFail (LazyByteString.fromStrict bytes) of
          Left decodeErr ->
            pure (Left (ResumeDecodeFailure (Text.pack (show decodeErr))))
          Right transcript -> pure (Right transcript)
