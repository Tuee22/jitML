{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}

module JitML.Tune.Resume
  ( ResumeOutcome (..)
  , persistTrialTranscript
  , replaySweep
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (rights)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Generics (Generic)

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError)
import JitML.Tune.Catalog (TrialTranscript (..), trialStorageKey)

-- The transcript is serialised through Codec.Serialise so the bytes
-- round-trip bit-equal across read/write, matching the production MinIO
-- semantics.
deriving stock instance Generic TrialTranscript
deriving anyclass instance Serialise TrialTranscript

data ResumeOutcome = ResumeOutcome
  { resumedSeeds :: [Int]
  , resumedTrials :: [TrialTranscript]
  , resumeReadFailures :: [(Text, ServiceError)]
  }
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
-- recorded as `resumeReadFailures` so the caller can decide whether to
-- abort or re-run the trial.
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
      keys = fmap (Text.pack . show) seeds
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
      Left err -> pure (Left err)
      Right bytes ->
        case deserialiseOrFail (LazyByteString.fromStrict bytes) of
          Left decodeErr ->
            pure (Left . error . show $ decodeErr)
          Right transcript -> pure (Right transcript)
