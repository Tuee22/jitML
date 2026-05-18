{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero
  ( GameState (..)
  , ArenaSummary (..)
  , MctsState (..)
  , PerfectInformationGame (..)
  , PerfectInformation (..)
  , TwoHeadedNetwork (..)
  , applyMove
  , arenaWinRate
  , canonicalGames
  , connect4Network
  , gomokuActionCount
  , gomokuApplyMove
  , gomokuNetwork
  , hexActionCount
  , hexApplyMove
  , hexNetwork
  , initialConnect4
  , initialGomoku
  , initialHex
  , initialOthello
  , othelloActionCount
  , othelloApplyMove
  , othelloNetwork
  , renderArenaSummary
  , selfPlayTranscript
  , selfPlayTranscriptFor
  , twoHeadedNetworkFor
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

-- | Typeclass for the four canonical perfect-information games. Each game
-- exposes its initial state, applies a move (mod-action wrapping so the
-- transcript stays legal under deterministic adversarial play), and reports
-- its typed action count plus two-headed network metadata.
class PerfectInformation g where
  initialGame :: g
  applyGameMove :: Int -> g -> g
  gameActionCount :: g -> Int
  gameTwoHeadedNetwork :: g -> TwoHeadedNetwork

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

initialOthello :: GameState
initialOthello =
  -- Othello starts with the canonical centre square initialisation; the
  -- move-history records D3 (27), E3 (28) implicitly as "setup" placeholders.
  GameState "othello" [] 1

initialHex :: GameState
initialHex =
  GameState "hex" [] 1

initialGomoku :: GameState
initialGomoku =
  GameState "gomoku" [] 1

canonicalGames :: [PerfectInformationGame]
canonicalGames =
  [ PerfectInformationGame "connect4" 6 7 connect4ActionCount
  , PerfectInformationGame "othello" 8 8 othelloActionCount
  , PerfectInformationGame "hex" 11 11 hexActionCount
  , PerfectInformationGame "gomoku" 15 15 gomokuActionCount
  ]

connect4ActionCount :: Int
connect4ActionCount = 7

othelloActionCount :: Int
othelloActionCount = 8 * 8

hexActionCount :: Int
hexActionCount = 11 * 11

gomokuActionCount :: Int
gomokuActionCount = 15 * 15

connect4Network :: TwoHeadedNetwork
connect4Network =
  TwoHeadedNetwork
    { networkName = "connect4-two-headed"
    , policyHeadSize = connect4ActionCount
    , valueHeadSize = 1
    }

othelloNetwork :: TwoHeadedNetwork
othelloNetwork =
  TwoHeadedNetwork
    { networkName = "othello-two-headed"
    , policyHeadSize = othelloActionCount
    , valueHeadSize = 1
    }

hexNetwork :: TwoHeadedNetwork
hexNetwork =
  TwoHeadedNetwork
    { networkName = "hex-two-headed"
    , policyHeadSize = hexActionCount
    , valueHeadSize = 1
    }

gomokuNetwork :: TwoHeadedNetwork
gomokuNetwork =
  TwoHeadedNetwork
    { networkName = "gomoku-two-headed"
    , policyHeadSize = gomokuActionCount
    , valueHeadSize = 1
    }

twoHeadedNetworkFor :: Text -> TwoHeadedNetwork
twoHeadedNetworkFor "connect4" = connect4Network
twoHeadedNetworkFor "othello" = othelloNetwork
twoHeadedNetworkFor "hex" = hexNetwork
twoHeadedNetworkFor "gomoku" = gomokuNetwork
twoHeadedNetworkFor other =
  TwoHeadedNetwork
    { networkName = other <> "-two-headed"
    , policyHeadSize = 1
    , valueHeadSize = 1
    }

applyMove :: Int -> GameState -> GameState
applyMove column state =
  case gameName state of
    "connect4" -> applyConnect4Move column state
    "othello" -> applyOthelloMove column state
    "hex" -> applyHexMove column state
    "gomoku" -> applyGomokuMove column state
    _ ->
      state
        { gameMoves = gameMoves state <> [column `mod` 7]
        , gameCurrentPlayer = negate (gameCurrentPlayer state)
        }

applyConnect4Move :: Int -> GameState -> GameState
applyConnect4Move column state =
  state
    { gameMoves = gameMoves state <> [column `mod` connect4ActionCount]
    , gameCurrentPlayer = negate (gameCurrentPlayer state)
    }

applyOthelloMove :: Int -> GameState -> GameState
applyOthelloMove = othelloApplyMove

applyHexMove :: Int -> GameState -> GameState
applyHexMove = hexApplyMove

applyGomokuMove :: Int -> GameState -> GameState
applyGomokuMove = gomokuApplyMove

othelloApplyMove :: Int -> GameState -> GameState
othelloApplyMove cell state =
  state
    { gameMoves = gameMoves state <> [cell `mod` othelloActionCount]
    , gameCurrentPlayer = negate (gameCurrentPlayer state)
    }

hexApplyMove :: Int -> GameState -> GameState
hexApplyMove cell state =
  state
    { gameMoves = gameMoves state <> [cell `mod` hexActionCount]
    , gameCurrentPlayer = negate (gameCurrentPlayer state)
    }

gomokuApplyMove :: Int -> GameState -> GameState
gomokuApplyMove cell state =
  state
    { gameMoves = gameMoves state <> [cell `mod` gomokuActionCount]
    , gameCurrentPlayer = negate (gameCurrentPlayer state)
    }

selfPlayTranscript :: Int -> [GameState]
selfPlayTranscript = selfPlayTranscriptFor "connect4"

-- | Per-game deterministic self-play transcript. The move modulus and initial
-- state depend on the named game; the move sequence is seeded by `seed`.
-- Used by `jitml-rl-canonicals` to bind per-game golden replay fixtures
-- under `test/golden/alphazero/<game>-transcript.txt`.
selfPlayTranscriptFor :: Text -> Int -> [GameState]
selfPlayTranscriptFor gameId seed =
  take 8 $
    scanl (flip applyMove) (initialFor gameId) (movesFor gameId seed)
 where
  initialFor "connect4" = initialConnect4
  initialFor "othello" = initialOthello
  initialFor "hex" = initialHex
  initialFor "gomoku" = initialGomoku
  initialFor _ = initialConnect4

  movesFor name s =
    let modulus = case name of
          "connect4" -> connect4ActionCount
          "othello" -> othelloActionCount
          "hex" -> hexActionCount
          "gomoku" -> gomokuActionCount
          _ -> connect4ActionCount
     in iterate (\value -> (value * 5 + 3) `mod` modulus) s

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

instance PerfectInformation GameState where
  initialGame = initialConnect4
  applyGameMove = applyMove
  gameActionCount state =
    case gameName state of
      "connect4" -> connect4ActionCount
      "othello" -> othelloActionCount
      "hex" -> hexActionCount
      "gomoku" -> gomokuActionCount
      _ -> connect4ActionCount
  gameTwoHeadedNetwork state = twoHeadedNetworkFor (gameName state)
