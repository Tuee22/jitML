{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero.SelfPlay
  ( SelfPlayConfig (..)
  , SelfPlayBuffer (..)
  , SelfPlayGame (..)
  , bufferInsert
  , bufferLength
  , bufferTranscriptHash
  , defaultSelfPlayConfig
  , emptyBuffer
  , runSelfPlay
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

import JitML.RL.AlphaZero (GameState (..), applyMove, initialConnect4)
import JitML.RL.AlphaZero.Mcts (MctsConfig (..), defaultMctsConfig, runSearch, selectAction)

data SelfPlayConfig = SelfPlayConfig
  { selfPlayGamesPerGeneration :: Int
  , selfPlaySimulationsPerMove :: Int
  , selfPlayMaxPlies :: Int
  , selfPlaySeed :: Int
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
    , selfPlayActionSpace = 7
    }

data SelfPlayGame = SelfPlayGame
  { gameSeed :: Int
  , gameTranscript :: [GameState]
  , gameFinalPly :: Int
  }
  deriving stock (Eq, Show)

newtype SelfPlayBuffer = SelfPlayBuffer
  { unBuffer :: [SelfPlayGame]
  }
  deriving stock (Eq, Show)

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
runSelfPlay config =
  SelfPlayBuffer
    [ playOneGame config gameId
    | gameId <- [0 .. selfPlayGamesPerGeneration config - 1]
    ]

playOneGame :: SelfPlayConfig -> Int -> SelfPlayGame
playOneGame config gameId =
  let seed = selfPlaySeed config + gameId
      mctsCfg =
        (defaultMctsConfig (selfPlayActionSpace config))
          { mctsSimulations = selfPlaySimulationsPerMove config
          }
      step state ply
        | ply >= selfPlayMaxPlies config = (state, ply)
        | otherwise =
            let tree = runSearch mctsCfg (seed + ply)
             in case selectAction mctsCfg tree of
                  Nothing -> (state, ply)
                  Just action ->
                    let state' = applyMove action state
                     in step state' (ply + 1)
      (finalState, finalPly) = step initialConnect4 0
   in SelfPlayGame
        { gameSeed = seed
        , gameTranscript = scanlMoves finalState
        , gameFinalPly = finalPly
        }

scanlMoves :: GameState -> [GameState]
scanlMoves state =
  scanl (flip applyMove) initialConnect4 (gameMoves state)
