{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero
  ( GameState (..)
  , ArenaSummary (..)
  , MctsState (..)
  , PerfectInformationGame (..)
  , TwoHeadedNetwork (..)
  , applyMove
  , arenaWinRate
  , canonicalGames
  , connect4Network
  , initialConnect4
  , renderArenaSummary
  , selfPlayTranscript
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

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

data PerfectInformationGame = PerfectInformationGame
  { pigName :: Text
  , pigBoardRows :: Int
  , pigBoardColumns :: Int
  , pigActionCount :: Int
  }
  deriving stock (Eq, Show)

data TwoHeadedNetwork = TwoHeadedNetwork
  { networkName :: Text
  , policyHeadSize :: Int
  , valueHeadSize :: Int
  }
  deriving stock (Eq, Show)

data ArenaSummary = ArenaSummary
  { arenaCandidateWins :: Int
  , arenaReferenceWins :: Int
  , arenaDraws :: Int
  }
  deriving stock (Eq, Show)

initialConnect4 :: GameState
initialConnect4 =
  GameState "connect4" [] 1

canonicalGames :: [PerfectInformationGame]
canonicalGames =
  [ PerfectInformationGame "connect4" 6 7 7
  , PerfectInformationGame "othello" 8 8 64
  , PerfectInformationGame "hex" 11 11 121
  , PerfectInformationGame "gomoku" 15 15 225
  ]

connect4Network :: TwoHeadedNetwork
connect4Network =
  TwoHeadedNetwork
    { networkName = "connect4-two-headed"
    , policyHeadSize = 7
    , valueHeadSize = 1
    }

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
  moves = iterate (\value -> (value * 5 + 3) `mod` 7)

arenaWinRate :: ArenaSummary -> Double
arenaWinRate summary =
  case arenaCandidateWins summary + arenaReferenceWins summary + arenaDraws summary of
    0 -> 0
    total -> fromIntegral (arenaCandidateWins summary) / fromIntegral total

renderArenaSummary :: ArenaSummary -> Text
renderArenaSummary summary =
  Text.unlines
    [ "candidate_wins: " <> Text.pack (show (arenaCandidateWins summary))
    , "reference_wins: " <> Text.pack (show (arenaReferenceWins summary))
    , "draws: " <> Text.pack (show (arenaDraws summary))
    , "candidate_win_rate: " <> Text.pack (show (arenaWinRate summary))
    ]
