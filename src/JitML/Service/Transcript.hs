{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 14.1 (Feature B) — persisted adversarial-game transcripts.
--
-- The Engine persists each completed adversarial move's transcript to the
-- @jitml-transcripts@ MinIO bucket, keyed by a deterministic content hash, so
-- the browser replay panel can load and scrub a real persisted game instead of
-- a synthesized @game:moves:player@ string. The body is @Codec.Serialise@ CBOR,
-- matching the self-play buffer round-trip in
-- 'JitML.RL.AlphaZero.SelfPlay'.
module JitML.Service.Transcript
  ( TranscriptRecord (..)
  , readTranscriptRecord
  , transcriptRecordKey
  , writeTranscriptRecord
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)
import GHC.Generics (Generic)

import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag (..)
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError)

-- | A persisted adversarial-game transcript: the game, the experiment whose
-- policy/value network produced the moves, the move sequence, and a free-text
-- per-game analysis summary.
data TranscriptRecord = TranscriptRecord
  { transcriptGame :: Text
  , transcriptExperimentHash :: Text
  , transcriptMoves :: [Int]
  , transcriptAnalysis :: Text
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

-- | Deterministic content hash of a transcript record, used as the MinIO key
-- suffix. Two transcripts with identical game/experiment/moves collapse to the
-- same key (write-once content addressing).
transcriptContentHash :: TranscriptRecord -> Text
transcriptContentHash record =
  hashHex $
    SHA256.hash $
      Text.Encoding.encodeUtf8 $
        Text.intercalate
          "|"
          [ transcriptGame record
          , transcriptExperimentHash record
          , Text.intercalate "," (fmap (Text.pack . show) (transcriptMoves record))
          ]

hashHex :: ByteString.ByteString -> Text
hashHex =
  Text.pack . concatMap byteHex . ByteString.unpack
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

-- | MinIO storage key for a transcript record under the @jitml-transcripts@
-- bucket. The deterministic content hash supplies the last segment.
transcriptRecordKey :: TranscriptRecord -> Text
transcriptRecordKey record =
  "transcripts/" <> transcriptContentHash record <> ".cbor"

-- | Persist a transcript record to the @jitml-transcripts@ bucket under
-- 'transcriptRecordKey'. Returns the stored object's 'ETag' (or the existing
-- one when the content-addressed object was already present), and the key the
-- replay command should later read.
writeTranscriptRecord
  :: (HasMinIO m)
  => TranscriptRecord
  -> m (Either ServiceError (Text, ETag))
writeTranscriptRecord record = do
  let key = transcriptRecordKey record
      ref = ObjectRef (BucketName "jitml-transcripts") (ObjectKey key)
      payload = LazyByteString.toStrict (serialise record)
  write <- putBlobBytesIfAbsent ref payload
  case write of
    Right etag -> pure (Right (key, etag))
    Left err -> do
      -- The key is content-addressed, so a write that fails because the object
      -- is already present (a prior identical move) is not an error — the same
      -- record is already at @key@. Read back to distinguish "already present"
      -- (return the key the replay command reads) from a genuine write failure.
      existing <- minioReadBytes ref
      case existing of
        Right _ -> pure (Right (key, ETag ""))
        Left _ -> pure (Left err)

-- | Read a previously-persisted transcript record from the
-- @jitml-transcripts@ bucket by its full object key (as returned from
-- 'writeTranscriptRecord').
readTranscriptRecord
  :: (HasMinIO m)
  => Text
  -> m (Either Text TranscriptRecord)
readTranscriptRecord key = do
  let ref = ObjectRef (BucketName "jitml-transcripts") (ObjectKey key)
  bytes <- minioReadBytes ref
  pure $ case bytes of
    Left err ->
      Left ("transcript read failed: " <> Text.pack (show err))
    Right rawBytes ->
      case deserialiseOrFail (LazyByteString.fromStrict rawBytes) of
        Left decodeErr ->
          Left ("transcript decode failed: " <> Text.pack (show decodeErr))
        Right record -> Right record
