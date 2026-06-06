-- | AlphaZero-vs-human Connect 4 panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each column button
-- | dispatches 'PlayColumn col'; the daemon's MCTS reply lands as
-- | 'MoveReceived'. The board renders state.moves so the user sees
-- | both the human moves and the daemon's responses without page
-- | refresh.
module Panels.Connect4 where

import Prelude

import Data.Array (range)
import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Chrome.Header as Header

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
  , pendingMove :: Boolean
  , lastResponse :: Maybe Connect4MoveResponse
  , lastError :: Maybe String
  }

data Action
  = PlayColumn Int
  | MoveReceived Connect4MoveResponse
  | MoveFailed String
  | ResetGame

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

initialState :: State
initialState =
  { moves: []
  , humanIsPlayer: 1
  , pendingMove: false
  , lastResponse: Nothing
  , lastError: Nothing
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> initialState
    , render
    , eval: H.mkEval H.defaultEval { handleAction = handleAction }
    }
  where
  handleAction = case _ of
    PlayColumn col ->
      H.modify_
        ( \s ->
            s
              { moves = Array.snoc s.moves col
              , pendingMove = true
              , lastError = Nothing
              }
        )
    MoveReceived response ->
      H.modify_
        ( \s ->
            s
              { moves = Array.snoc s.moves response.chosenColumn
              , pendingMove = false
              , lastResponse = Just response
              , lastError = Nothing
              }
        )
    MoveFailed message ->
      H.modify_
        ( _
            { pendingMove = false
            , lastError = Just message
            }
        )
    ResetGame ->
      H.put initialState

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Connect 4 (human vs AlphaZero)" ]
      , HH.div
          [ HP.id (panelName <> "-board")
          , HP.classes [ H.ClassName "connect4-board" ]
          ]
          (map (columnButton state.pendingMove) (range 0 6))
      , HH.div
          [ HP.id (panelName <> "-moves")
          , HP.classes [ H.ClassName "connect4-moves" ]
          ]
          [ HH.text ("moves: " <> show state.moves) ]
      , HH.button
          [ HP.id (panelName <> "-reset")
          , HE.onClick (\_ -> ResetGame)
          ]
          [ HH.text "Reset" ]
      , renderError state
      ]

  columnButton pending col =
    HH.button
      [ HP.id (panelName <> "-col-" <> show col)
      , HP.classes [ H.ClassName "connect4-column" ]
      , HP.disabled pending
      , HE.onClick (\_ -> PlayColumn col)
      ]
      [ HH.text (show col) ]

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("move error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
