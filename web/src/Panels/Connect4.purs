-- | AlphaZero vs human Connect 4 panel. The Halogen component owns the
-- | panel DOM; the live `/api/connect4/move` POST + MCTS rendering is
-- | owned by Phase 13 Sprint 13.13.
module Panels.Connect4 where

import Prelude

import Data.Array (range)
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

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

type State =
  { moves :: Array Int
  , humanIsPlayer :: Int
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

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> { moves: [], humanIsPlayer: 1 }
    , render
    , eval: H.mkEval H.defaultEval
    }
  where
  render _ =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "Connect 4 (human vs AlphaZero)" ]
      , HH.div
          [ HP.id (panelName <> "-board")
          , HP.classes [ H.ClassName "connect4-board" ]
          ]
          (map columnButton (range 0 6))
      ]

  columnButton col =
    HH.button
      [ HP.id (panelName <> "-col-" <> show col)
      , HP.classes [ H.ClassName "connect4-column" ]
      ]
      [ HH.text (show col) ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
