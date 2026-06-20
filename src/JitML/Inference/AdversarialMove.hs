{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — __pure adversarial move
-- selection__ for the Connect-4 / AlphaZero panel. The contract makes the
-- __Engine__ the only role that computes; this module relocates the MCTS tree
-- search (previously run in the webapp's HTTP handler) so the daemon runs the
-- policy/value inference __and__ the search, emitting the chosen move. The webapp
-- and browser panel then carry no search logic.
module JitML.Inference.AdversarialMove
  ( AdversarialMoveOutcome (..)
  , adversarialRuntimeInput
  , computeAdversarialMove
  )
where

import Data.List (maximumBy)
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Text (Text)

import JitML.Inference.Decode (softmax)
import JitML.RL.AlphaZero qualified as AlphaZero
import JitML.RL.AlphaZero.Mcts qualified as Mcts

-- | The decoded outcome of an MCTS move search: the chosen column, the legal
-- moves, their visit counts, the masked policy priors over the legal moves, the
-- value estimate, and whether the game is over.
data AdversarialMoveOutcome = AdversarialMoveOutcome
  { amoChosenColumn :: Int
  , amoLegalMoves :: [Int]
  , amoVisitCounts :: [Int]
  , amoPolicyPriors :: [Double]
  , amoValueEstimate :: Double
  , amoGameOver :: Bool
  }
  deriving stock (Eq, Show)

-- | Run the policy-masked MCTS search over a game's neural-net output and return
-- the chosen move and supporting telemetry. Pure: this is the Engine's
-- move-selection step.
computeAdversarialMove
  :: Text
  -- ^ game
  -> [Int]
  -- ^ move history
  -> Int
  -- ^ human-is-player
  -> Int
  -- ^ simulations per move
  -> [Double]
  -- ^ neural-net policy+value output
  -> AdversarialMoveOutcome
computeAdversarialMove game moves humanIsPlayer simulations output =
  let actionCount = actionCountForGame game
      state = gameStateAfter game moves
      legalMoves = filter (\move -> AlphaZero.isLegalMove game move state) [0 .. actionCount - 1]
      priors = maskedPriors actionCount legalMoves output
      valueEstimate = tanh (valueAt actionCount output)
      config =
        (Mcts.defaultMctsConfig actionCount) {Mcts.mctsSimulations = max 1 simulations}
      terminal = AlphaZero.gameIsTerminal state
      root =
        Mcts.runSearchWithPrior
          (const (Mcts.NodeEval priors valueEstimate terminal))
          config
          (length moves + humanIsPlayer)
      visitCounts = fmap (visitsFor root) legalMoves
      chosenMove = chooseMove legalMoves visitCounts
   in AdversarialMoveOutcome
        { amoChosenColumn = chosenMove
        , amoLegalMoves = legalMoves
        , amoVisitCounts = visitCounts
        , amoPolicyPriors = fmap (`valueAt` priors) legalMoves
        , amoValueEstimate = valueEstimate
        , amoGameOver = terminal || null legalMoves
        }

-- | The neural-net input vector for an adversarial position — derived in the
-- Engine from the game and move history (it no longer happens in the webapp).
adversarialRuntimeInput :: Text -> [Int] -> Int -> Int -> [Double]
adversarialRuntimeInput game moves humanIsPlayer simulations =
  let actionCount = actionCountForGame game
      state = gameStateAfter game moves
      legalMoves = filter (\move -> AlphaZero.isLegalMove game move state) [0 .. actionCount - 1]
   in fmap fromIntegral moves
        <> fmap fromIntegral legalMoves
        <> [fromIntegral humanIsPlayer, fromIntegral simulations]

actionCountForGame :: Text -> Int
actionCountForGame =
  AlphaZero.policyHeadSize . AlphaZero.twoHeadedNetworkFor

gameStateAfter :: Text -> [Int] -> AlphaZero.GameState
gameStateAfter game =
  foldl (flip AlphaZero.applyMove) initial
 where
  initial =
    case game of
      "othello" -> AlphaZero.initialOthello
      "hex" -> AlphaZero.initialHex
      "gomoku" -> AlphaZero.initialGomoku
      _ -> AlphaZero.initialConnect4

maskedPriors :: Int -> [Int] -> [Double] -> [Double]
maskedPriors actionCount legalMoves output =
  let base = softmax (take actionCount (output <> repeat 0.0))
      masked =
        [ if action `elem` legalMoves then valueAt action base else 0.0
        | action <- [0 .. actionCount - 1]
        ]
      total = sum masked
   in if total <= 0
        then
          [ if action `elem` legalMoves then 1.0 / fromIntegral (max 1 (length legalMoves)) else 0.0
          | action <- [0 .. actionCount - 1]
          ]
        else fmap (/ total) masked

visitsFor :: Mcts.MctsNode -> Int -> Int
visitsFor root action =
  fromMaybe 0 $ do
    edge <- findByAction action (Mcts.nodeChildren root)
    pure (Mcts.edgeVisits edge)

findByAction :: Int -> [Mcts.MctsEdge] -> Maybe Mcts.MctsEdge
findByAction action = go
 where
  go [] = Nothing
  go (edge : rest)
    | Mcts.edgeAction edge == action = Just edge
    | otherwise = go rest

chooseMove :: [Int] -> [Int] -> Int
chooseMove [] _ = 0
chooseMove legalMoves visitCounts =
  fst (maximumBy (comparing snd) (zip legalMoves (visitCounts <> repeat 0)))

valueAt :: Int -> [Double] -> Double
valueAt index values
  | index < 0 = 0.0
  | otherwise = case drop index values of
      value : _ -> value
      [] -> 0.0
