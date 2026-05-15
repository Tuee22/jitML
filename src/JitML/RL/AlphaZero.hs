{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero
    ( GameState (..)
    , MctsState (..)
    , applyMove
    , initialConnect4
    , selfPlayTranscript
    )
where

import Data.Text (Text)

data GameState = GameState
    { gameName :: Text
    , gameMoves :: [Int]
    , gameCurrentPlayer :: Int
    }
    deriving stock (Eq, Show)

data MctsState = MctsState
    { mctsVisitCount :: Int
    , mctsPriorSeed :: Int
    }
    deriving stock (Eq, Show)

initialConnect4 :: GameState
initialConnect4 =
    GameState "connect4" [] 1

applyMove :: Int -> GameState -> GameState
applyMove column state =
    state
        { gameMoves = gameMoves state <> [column `mod` 7]
        , gameCurrentPlayer = negate (gameCurrentPlayer state)
        }

selfPlayTranscript :: Int -> [GameState]
selfPlayTranscript seed =
    take 8 $
        scanl (flip applyMove) initialConnect4 (moves seed)
  where
    moves start = iterate (\value -> (value * 5 + 3) `mod` 7) start
