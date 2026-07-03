{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero.SelfPlay
  ( SelfPlayConfig (..)
  , SelfPlayBuffer (..)
  , SelfPlayGame (..)
  , bufferInsert
  , bufferLength
  , bufferStorageKey
  , bufferTranscriptHash
  , defaultSelfPlayConfig
  , emptyBuffer
  , readSelfPlayBuffer
  , reportCardSelfPlayConfig
  , runSelfPlay
  , runSelfPlayWithPrior
  , runSelfPlayWithOracleFactory
  , writeSelfPlayBuffer
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

import JitML.RL.AlphaZero (GameState (..), actionCountFor, applyMove, initialStateFor)
import JitML.RL.AlphaZero.Mcts
  ( MctsConfig (..)
  , PriorOracle
  , defaultMctsConfig
  , defaultPriorOracle
  , emptyTranspositionTable
  , runSearchWithTableAndPrior
  , selectAction
  , transpositionSize
  )
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError)
import JitML.Test.Report (ReportCardKnobs (knobAzGames, knobAzSims))

data SelfPlayConfig = SelfPlayConfig
  { selfPlayGamesPerGeneration :: Int
  , selfPlaySimulationsPerMove :: Int
  , selfPlayMaxPlies :: Int
  , selfPlaySeed :: Int
  , selfPlayGame :: Text
  , selfPlayActionSpace :: Int
  }
  deriving stock (Eq, Show)

defaultSelfPlayConfig :: SelfPlayConfig
defaultSelfPlayConfig =
  SelfPlayConfig
    { selfPlayGamesPerGeneration = 200
    , selfPlaySimulationsPerMove = 400
    , selfPlayMaxPlies = 42
    , selfPlaySeed = 42
    , selfPlayGame = "connect4"
    , selfPlayActionSpace = 7
    }

data SelfPlayGame = SelfPlayGame
  { gameSeed :: Int
  , gameTranscript :: [GameState]
  , gameFinalPly :: Int
  , gameMctsCacheSizes :: [Int]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

newtype SelfPlayBuffer = SelfPlayBuffer
  { unBuffer :: [SelfPlayGame]
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

emptyBuffer :: SelfPlayBuffer
emptyBuffer = SelfPlayBuffer []

bufferInsert :: SelfPlayGame -> SelfPlayBuffer -> SelfPlayBuffer
bufferInsert g (SelfPlayBuffer gs) = SelfPlayBuffer (g : gs)

bufferLength :: SelfPlayBuffer -> Int
bufferLength = length . unBuffer

-- | Deterministic content hash of the buffer's transcript, used as the MinIO
-- pointer key suffix in the checkpoint round-trip.
bufferTranscriptHash :: SelfPlayBuffer -> Text
bufferTranscriptHash (SelfPlayBuffer games) =
  hashHex $
    SHA256.hash $
      Text.Encoding.encodeUtf8 $
        Text.unlines
          [ Text.pack (show (gameSeed g))
              <> "|"
              <> Text.intercalate "," (fmap (Text.pack . show . gameMoves) (gameTranscript g))
          | g <- games
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

runSelfPlay :: SelfPlayConfig -> SelfPlayBuffer
runSelfPlay = runSelfPlayWithPrior defaultPriorOracle

-- | Sprint 9.10 — run self-play with a caller-supplied position oracle. The
-- production AlphaZero loop passes a network-backed oracle (see
-- 'JitML.RL.AlphaZero.PolicyValueNet.netOracleFactory') so the search tree's
-- priors and value backups come from the real policy/value network forward pass.
runSelfPlayWithPrior :: PriorOracle -> SelfPlayConfig -> SelfPlayBuffer
runSelfPlayWithPrior oracle = runSelfPlayWithOracleFactory (const oracle)

-- | Sprint 9.10 — run self-play with a per-position oracle factory. At each
-- ply the factory is applied to the current 'GameState' to produce the
-- 'PriorOracle' the MCTS search consumes, rooted at that position, so a real
-- policy/value network emits position-dependent priors and value estimates (the
-- AlphaZero contract). The production loop passes
-- @'JitML.RL.AlphaZero.PolicyValueNet.netOracleFactory' net@ here; a fixed
-- factory @const oracle@ recovers the 'runSelfPlayWithPrior' behaviour.
runSelfPlayWithOracleFactory
  :: (GameState -> PriorOracle) -> SelfPlayConfig -> SelfPlayBuffer
runSelfPlayWithOracleFactory oracleFactory config =
  SelfPlayBuffer
    [ playOneGame oracleFactory config gameId
    | gameId <- [0 .. selfPlayGamesPerGeneration config - 1]
    ]

-- | Sprint 13.9 — construct a 'SelfPlayConfig' from the @az_games@ /
-- @az_sims@ knobs declared in @cabal.project@ (read via
-- 'JitML.Test.Report.loadReportCardKnobs'). The canonical stanza body
-- consumes this to drive the live self-play loop with the same counts
-- the report-card declares.
reportCardSelfPlayConfig :: ReportCardKnobs -> SelfPlayConfig
reportCardSelfPlayConfig knobs =
  defaultSelfPlayConfig
    { selfPlayGamesPerGeneration = max 1 (knobAzGames knobs)
    , selfPlaySimulationsPerMove = max 1 (knobAzSims knobs)
    }

playOneGame :: (GameState -> PriorOracle) -> SelfPlayConfig -> Int -> SelfPlayGame
playOneGame oracleFactory config gameId =
  let seed = selfPlaySeed config + gameId
      initial = initialStateFor (selfPlayGame config)
      actionSpace = max 1 (actionCountFor (selfPlayGame config))
      mctsCfg =
        (defaultMctsConfig actionSpace)
          { mctsSimulations = selfPlaySimulationsPerMove config
          }
      step state table cacheSizes ply
        | ply >= selfPlayMaxPlies config = (state, ply, cacheSizes)
        | otherwise =
            -- Build the prior oracle from the current position so a real
            -- network emits position-dependent priors (Sprint 13.9).
            let (tree, table') =
                  runSearchWithTableAndPrior
                    (oracleFactory state)
                    mctsCfg
                    (splitSeed seed ply)
                    (gameMoves state)
                    table
                cacheSizes' = cacheSizes <> [transpositionSize table']
             in case selectAction mctsCfg tree of
                  Nothing -> (state, ply, cacheSizes')
                  Just action ->
                    let state' = applyMove action state
                     in step state' table' cacheSizes' (ply + 1)
      (finalState, finalPly, finalCacheSizes) = step initial emptyTranspositionTable [] 0
   in SelfPlayGame
        { gameSeed = seed
        , gameTranscript = scanlMovesFrom initial finalState
        , gameFinalPly = finalPly
        , gameMctsCacheSizes = finalCacheSizes
        }

splitSeed :: Int -> Int -> Int
splitSeed seed ply =
  seed * 1103515245 + ply * 12345 + 1013904223

scanlMovesFrom :: GameState -> GameState -> [GameState]
scanlMovesFrom initial state =
  scanl (flip applyMove) initial (gameMoves state)

-- | Sprint 13.9 — MinIO storage key for a self-play buffer. The
-- experiment-hash-prefixed path lives under the same `jitml-checkpoints`
-- bucket as the rest of the AlphaZero checkpoint family; the buffer's
-- content hash supplies the last segment so two distinct generations'
-- buffers don't collide even when they share an experiment hash.
bufferStorageKey :: Text -> SelfPlayBuffer -> Text
bufferStorageKey experimentHash buffer =
  "jitml-checkpoints/"
    <> experimentHash
    <> "/selfplay/"
    <> bufferTranscriptHash buffer
    <> ".cbor"

-- | Sprint 13.9 — persist a SelfPlayBuffer to MinIO under
-- `bufferStorageKey`. The body is `Codec.Serialise`-encoded CBOR. The
-- returned ETag identifies the stored object so a subsequent generation's
-- write can CAS-promote a champion pointer if needed.
writeSelfPlayBuffer
  :: (HasMinIO m)
  => Text
  -> SelfPlayBuffer
  -> m (Either ServiceError ETag)
writeSelfPlayBuffer experimentHash buffer = do
  let ref =
        ObjectRef
          (BucketName "jitml-checkpoints")
          (ObjectKey (bufferStorageKey experimentHash buffer))
      payload = LazyByteString.toStrict (serialise buffer)
  putBlobBytesIfAbsent ref payload

-- | Sprint 13.9 — fetch a previously-persisted SelfPlayBuffer from MinIO.
-- The caller supplies the content hash (as returned by
-- `bufferTranscriptHash`) so the read addresses the exact generation.
readSelfPlayBuffer
  :: (HasMinIO m)
  => Text
  -> Text
  -> m (Either Text SelfPlayBuffer)
readSelfPlayBuffer experimentHash contentHash = do
  let key =
        "jitml-checkpoints/"
          <> experimentHash
          <> "/selfplay/"
          <> contentHash
          <> ".cbor"
      ref = ObjectRef (BucketName "jitml-checkpoints") (ObjectKey key)
  bytes <- minioReadBytes ref
  pure $ case bytes of
    Left err ->
      Left ("selfplay buffer read failed: " <> Text.pack (show err))
    Right rawBytes ->
      case deserialiseOrFail (LazyByteString.fromStrict rawBytes) of
        Left decodeErr ->
          Left ("selfplay buffer decode failed: " <> Text.pack (show decodeErr))
        Right buffer -> Right buffer
