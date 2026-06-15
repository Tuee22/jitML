{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero
  ( GameState (..)
  , GameOutcome (..)
  , ArenaSummary (..)
  , MctsState (..)
  , PerfectInformationGame (..)
  , PerfectInformation (..)
  , TwoHeadedNetwork (..)
  , applyMove
  , arenaWinRate
  , canonicalGames
  , connect4BoardAfter
  , connect4Network
  , connect4LegalMove
  , gameIsTerminal
  , gameOutcome
  , gomokuActionCount
  , gomokuApplyMove
  , gomokuLegalMove
  , gomokuNetwork
  , hasGomokuLine
  , hexActionCount
  , hexApplyMove
  , hexConnected
  , hexLegalMove
  , hexNetwork
  , initialConnect4
  , initialGomoku
  , initialHex
  , initialOthello
  , isLegalMove
  , othelloActionCount
  , othelloApplyMove
  , othelloBoardAfter
  , othelloFlipsFor
  , othelloInitialBoard
  , othelloLegalMove
  , othelloNetwork
  , renderArenaSummary
  , selfPlayTranscript
  , selfPlayTranscriptFor
  , terminalValueForToMove
  , twoHeadedNetworkFor
  )
where

import Codec.Serialise (Serialise)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.IntSet (IntSet)
import Data.IntSet qualified as IntSet
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Generics (Generic)

data GameState = GameState
  { gameName :: Text
  , gameMoves :: [Int]
  , gameCurrentPlayer :: Int
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

data GameOutcome
  = GameInProgress
  | GameDraw
  | GameWon Int
  deriving stock (Eq, Generic, Show)
  deriving anyclass (Serialise)

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
-- exposes its initial state, applies a move through the game's legal-action
-- surface, and reports its typed action count plus two-headed network metadata.
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
applyMove candidate state =
  case nextLegalMove (gameName state) candidate state of
    Nothing -> state
    Just legal ->
      case gameName state of
        "connect4" -> applyConnect4Move legal state
        "othello" -> applyOthelloMove legal state
        "hex" -> applyHexMove legal state
        "gomoku" -> applyGomokuMove legal state
        _ ->
          state
            { gameMoves = gameMoves state <> [legal `mod` 7]
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

gameOutcome :: GameState -> GameOutcome
gameOutcome state =
  case gameName state of
    "connect4" -> connect4Outcome state
    "othello" -> othelloOutcome state
    "hex" -> hexOutcome state
    "gomoku" -> gomokuOutcome state
    _ -> GameInProgress

gameIsTerminal :: GameState -> Bool
gameIsTerminal state =
  case gameOutcome state of
    GameInProgress -> False
    GameDraw -> True
    GameWon _ -> True

terminalValueForToMove :: GameState -> Double
terminalValueForToMove state =
  case gameOutcome state of
    GameWon winner
      | winner == gameCurrentPlayer state -> 1.0
      | otherwise -> -1.0
    GameDraw -> 0.0
    GameInProgress -> 0.0

selfPlayTranscript :: Int -> [GameState]
selfPlayTranscript = selfPlayTranscriptFor "connect4"

-- | Per-game deterministic self-play transcript. The move modulus and initial
-- state depend on the named game; the move sequence is seeded by `seed` and
-- advances past illegal candidates by incrementing the candidate cell modulo
-- the per-game action count until a legal candidate is found. Used by
-- `jitml-rl-canonicals` for same-seed run-to-run transcript assertions.
selfPlayTranscriptFor :: Text -> Int -> [GameState]
selfPlayTranscriptFor gameId seed =
  take 8 (initial : go initial (seed `mod` modulus) (7 :: Int))
 where
  initial = initialFor gameId
  modulus = modulusFor gameId

  initialFor "connect4" = initialConnect4
  initialFor "othello" = initialOthello
  initialFor "hex" = initialHex
  initialFor "gomoku" = initialGomoku
  initialFor _ = initialConnect4

  go _state _candidate 0 = []
  go state candidate remaining =
    case nextLegalMove gameId candidate state of
      Nothing -> []
      Just legal ->
        let state' = applyMove legal state
            nextCandidate = (legal * 5 + 3) `mod` modulus
         in state' : go state' nextCandidate (remaining - 1)

modulusFor :: Text -> Int
modulusFor "connect4" = connect4ActionCount
modulusFor "othello" = othelloActionCount
modulusFor "hex" = hexActionCount
modulusFor "gomoku" = gomokuActionCount
modulusFor _ = connect4ActionCount

nextLegalMove :: Text -> Int -> GameState -> Maybe Int
nextLegalMove gameId startCandidate state =
  let modulus = modulusFor gameId
      probe offset
        | offset >= modulus = Nothing
        | otherwise =
            let candidate = (startCandidate + offset) `mod` modulus
             in if isLegalMove gameId candidate state
                  then Just candidate
                  else probe (offset + 1)
   in probe 0

-- | Per-game legality check used by `selfPlayTranscriptFor` to advance past
-- illegal seeded candidates. Connect 4 rejects full columns; Hex / Gomoku
-- reject occupied cells; Othello requires that the placement flip at least
-- one opponent stone (the canonical Othello legality rule).
isLegalMove :: Text -> Int -> GameState -> Bool
isLegalMove gameId candidate state =
  case gameId of
    "connect4" -> connect4LegalMove candidate state
    "othello" -> othelloLegalMove candidate state
    "hex" -> hexLegalMove candidate state
    "gomoku" -> gomokuLegalMove candidate state
    _ -> False

connect4LegalMove :: Int -> GameState -> Bool
connect4LegalMove column state =
  column >= 0
    && column < connect4ActionCount
    && length (filter (== column) (gameMoves state)) < connect4Rows
 where
  connect4Rows = 6

connect4BoardAfter :: [Int] -> [Int]
connect4BoardAfter moves0 =
  foldl' place (replicate (connect4Rows * connect4ActionCount) 0) (zip [0 :: Int ..] moves0)
 where
  connect4Rows = 6
  place grid (ix, rawColumn) =
    let player = if even ix then 1 else -1
        column = rawColumn `mod` connect4ActionCount
     in case [ r | r <- [connect4Rows - 1, connect4Rows - 2 .. 0], grid !! (r * connect4ActionCount + column) == 0
             ] of
          r : _ ->
            let cell = r * connect4ActionCount + column
             in take cell grid <> [player] <> drop (cell + 1) grid
          [] -> grid

connect4Outcome :: GameState -> GameOutcome
connect4Outcome state =
  let grid = connect4BoardAfter (gameMoves state)
      winner = lineWinner (negate (gameCurrentPlayer state)) grid connect4Rows connect4ActionCount 4
      boardFull = 0 `notElem` grid
   in case winner of
        Just player -> GameWon player
        Nothing
          | boardFull -> GameDraw
          | otherwise -> GameInProgress
 where
  connect4Rows = 6

hexLegalMove :: Int -> GameState -> Bool
hexLegalMove cell state =
  cell >= 0
    && cell < hexActionCount
    && cell `notElem` gameMoves state

gomokuLegalMove :: Int -> GameState -> Bool
gomokuLegalMove cell state =
  cell >= 0
    && cell < gomokuActionCount
    && cell `notElem` gameMoves state

-- | Apply the canonical Othello opening to a 0-keyed board and return the
-- resulting cell-occupancy map (Map cell-index → player-id, where +1 is the
-- first player to move and -1 is the second).
othelloInitialBoard :: IntMap Int
othelloInitialBoard =
  IntMap.fromList
    [ (27, -1) -- D4 = White
    , (28, 1) -- E4 = Black
    , (35, 1) -- D5 = Black
    , (36, -1) -- E5 = White
    ]

othelloDirections :: [(Int, Int)]
othelloDirections =
  [(dr, dc) | dr <- [-1, 0, 1], dc <- [-1, 0, 1], (dr, dc) /= (0, 0)]

-- | Reconstruct the Othello board state after a list of cell moves, applying
-- the canonical capture-flip rule on each move. Moves whose placement does
-- not flip any opponent stone are skipped to keep the transcript playable
-- when callers append candidate moves directly through `othelloApplyMove`.
othelloBoardAfter :: [Int] -> IntMap Int
othelloBoardAfter =
  snd . othelloReplay

othelloReplay :: [Int] -> (Int, IntMap Int)
othelloReplay =
  foldl' step (1, othelloInitialBoard)
 where
  step (player, board) cell =
    if cell < 0
      then (negate player, board)
      else
        let flipped = othelloFlipsFor board player cell
            board' =
              foldr
                (`IntMap.insert` player)
                board
                (cell : flipped)
         in if null flipped || IntMap.member cell board
              then (negate player, board)
              else (negate player, board')

-- | Compute the list of opponent cells that flip when @player@ places at
-- @cell@ on @board@. Returns @[]@ when the move is illegal under Othello
-- rules (no flips in any direction).
othelloFlipsFor :: IntMap Int -> Int -> Int -> [Int]
othelloFlipsFor board player cell =
  concatMap (flipsInDirection board player cell) othelloDirections

flipsInDirection :: IntMap Int -> Int -> Int -> (Int, Int) -> [Int]
flipsInDirection board player start (dr, dc) =
  let row0 = start `div` 8
      col0 = start `mod` 8
      coords =
        takeWhile othelloInBounds (iterate (\(r, c) -> (r + dr, c + dc)) (row0 + dr, col0 + dc))
      cells = fmap (\(r, c) -> r * 8 + c) coords
      (opps, rest) =
        span (\c -> IntMap.lookup c board == Just (negate player)) cells
   in case rest of
        anchor : _
          | IntMap.lookup anchor board == Just player -> opps
        _ -> []

othelloInBounds :: (Int, Int) -> Bool
othelloInBounds (r, c) = r >= 0 && r < 8 && c >= 0 && c < 8

othelloLegalMove :: Int -> GameState -> Bool
othelloLegalMove cell state
  | cell < 0 || cell >= othelloActionCount = False
  | otherwise =
      let board = othelloBoardAfter (gameMoves state)
          player = fst (othelloReplay (gameMoves state))
       in IntMap.notMember cell board
            && not (null (othelloFlipsFor board player cell))

othelloOutcome :: GameState -> GameOutcome
othelloOutcome state =
  let board = othelloBoardAfter (gameMoves state)
      legalFor player =
        any
          ( \cell ->
              IntMap.notMember cell board
                && not (null (othelloFlipsFor board player cell))
          )
          [0 .. othelloActionCount - 1]
      terminal = IntMap.size board >= othelloActionCount || not (legalFor 1 || legalFor (-1))
      black = length (filter (== 1) (IntMap.elems board))
      white = length (filter (== (-1)) (IntMap.elems board))
   in if not terminal
        then GameInProgress
        else case compare black white of
          GT -> GameWon 1
          LT -> GameWon (-1)
          EQ -> GameDraw

-- | Whether @player@'s stones on @board@ connect the player's two target
-- edges on the canonical 11x11 Hex board. Player +1 connects the top edge
-- (row 0) to the bottom edge (row 10); player -1 connects the left edge
-- (col 0) to the right edge (col 10). Hex adjacency is the six standard
-- neighbours plus the parallelogram-board diagonals.
hexConnected :: Int -> IntSet -> Bool
hexConnected player stones = any reachesEnd starts
 where
  starts =
    [ start
    | start <- IntSet.toList stones
    , isStartEdge start
    ]
  isStartEdge cell =
    let (r, c) = (cell `div` 11, cell `mod` 11)
     in if player > 0 then r == 0 else c == 0
  isEndEdge cell =
    let (r, c) = (cell `div` 11, cell `mod` 11)
     in if player > 0 then r == 10 else c == 10
  reachesEnd start = bfs (IntSet.singleton start) [start]
  bfs _visited [] = False
  bfs visited (cell : rest)
    | isEndEdge cell = True
    | otherwise =
        let neighbours =
              [ n
              | n <- hexNeighbours cell
              , IntSet.member n stones
              , not (IntSet.member n visited)
              ]
            visited' = foldr IntSet.insert visited neighbours
         in bfs visited' (rest <> neighbours)

hexNeighbours :: Int -> [Int]
hexNeighbours cell =
  let r = cell `div` 11
      c = cell `mod` 11
      candidates =
        [ (r - 1, c)
        , (r - 1, c + 1)
        , (r, c - 1)
        , (r, c + 1)
        , (r + 1, c - 1)
        , (r + 1, c)
        ]
   in [ rr * 11 + cc
      | (rr, cc) <- candidates
      , rr >= 0
      , rr < 11
      , cc >= 0
      , cc < 11
      ]

hexOutcome :: GameState -> GameOutcome
hexOutcome state =
  let playerStones player = stonesForPlayer player hexActionCount (gameMoves state)
      playerOneWon = hexConnected 1 (playerStones 1)
      playerTwoWon = hexConnected (-1) (playerStones (-1))
      boardFull = IntSet.size (IntSet.union (playerStones 1) (playerStones (-1))) >= hexActionCount
   in case (playerOneWon, playerTwoWon) of
        (True, _) -> GameWon 1
        (_, True) -> GameWon (-1)
        _
          | boardFull -> GameDraw
          | otherwise -> GameInProgress

-- | Whether @player@'s stones on @board@ contain a five-in-a-row line
-- horizontally, vertically, or diagonally on the canonical 15x15 Gomoku
-- board.
hasGomokuLine :: IntSet -> Bool
hasGomokuLine stones =
  any (lineThrough stones) (IntSet.toList stones)
 where
  lineThrough s cell =
    any (lineFrom s cell) gomokuDirections
  lineFrom s cell (dr, dc) =
    all (\step -> IntSet.member (offset cell (dr * step) (dc * step)) s) [0 .. 4]
      && inBoundsRange cell (dr, dc)
  offset cell dr dc =
    let r = cell `div` 15
        c = cell `mod` 15
     in (r + dr) * 15 + (c + dc)
  inBoundsRange cell (dr, dc) =
    let r = cell `div` 15
        c = cell `mod` 15
        r4 = r + dr * 4
        c4 = c + dc * 4
     in r4 >= 0 && r4 < 15 && c4 >= 0 && c4 < 15

gomokuDirections :: [(Int, Int)]
gomokuDirections = [(0, 1), (1, 0), (1, 1), (1, -1)]

gomokuOutcome :: GameState -> GameOutcome
gomokuOutcome state =
  let playerStones player = stonesForPlayer player gomokuActionCount (gameMoves state)
      playerOneWon = hasGomokuLine (playerStones 1)
      playerTwoWon = hasGomokuLine (playerStones (-1))
      boardFull = IntSet.size (IntSet.union (playerStones 1) (playerStones (-1))) >= gomokuActionCount
   in case (playerOneWon, playerTwoWon) of
        (True, _) -> GameWon 1
        (_, True) -> GameWon (-1)
        _
          | boardFull -> GameDraw
          | otherwise -> GameInProgress

stonesForPlayer :: Int -> Int -> [Int] -> IntSet
stonesForPlayer player actionCount moves0 =
  IntSet.fromList
    [ raw `mod` actionCount
    | (ix, raw) <- zip [0 :: Int ..] moves0
    , let movePlayer = if even ix then 1 else -1
    , movePlayer == player
    ]

lineWinner :: Int -> [Int] -> Int -> Int -> Int -> Maybe Int
lineWinner preferredPlayer grid rows columns lineLength =
  firstWinner (preferredPlayer : filter (/= preferredPlayer) [1, -1])
 where
  firstWinner [] = Nothing
  firstWinner (player : rest)
    | hasLine player = Just player
    | otherwise = firstWinner rest
  hasLine player =
    any
      ( \(r, c) ->
          any (runOf player (r, c)) [(0, 1), (1, 0), (1, 1), (1, -1)]
      )
      [(r, c) | r <- [0 .. rows - 1], c <- [0 .. columns - 1]]
  runOf player (r0, c0) (dr, dc) =
    all
      ( \k ->
          let r = r0 + k * dr
              c = c0 + k * dc
           in r >= 0
                && r < rows
                && c >= 0
                && c < columns
                && grid !! (r * columns + c) == player
      )
      [0 .. lineLength - 1]

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
