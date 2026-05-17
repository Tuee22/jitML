-- | AlphaZero vs human Connect 4 panel. The human picks a column; the panel
-- posts the current move sequence to `/api/connect4/move`; the daemon returns
-- the AlphaZero MCTS-recommended next move plus visit-count distribution.
module Panels.Connect4 where

import Prelude

import Effect (Effect)

type Connect4MoveRequest =
  { panel :: String
  , moves :: Array Int
  , humanIsPlayer :: Int
  , simulationsPerMove :: Int
  }

type Connect4MoveResponse =
  { chosenColumn :: Int
  , visitCounts :: Array Int
  , policyPriors :: Array Number
  , gameOver :: Boolean
  }

panelName :: String
panelName = "connect4-human-vs-alphazero"

defaultSimulations :: Int
defaultSimulations = 400

renderMoveRequest :: Array Int -> Int -> Connect4MoveRequest
renderMoveRequest moves humanIsPlayer =
  { panel: panelName
  , moves
  , humanIsPlayer
  , simulationsPerMove: defaultSimulations
  }

mount :: Effect Unit
mount = pure unit
