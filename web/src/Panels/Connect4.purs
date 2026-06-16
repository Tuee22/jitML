-- | AlphaZero-vs-human adversarial game panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each legal action button
-- | dispatches 'PlayMove move'; the daemon's MCTS reply lands as
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
import Generated.Contracts as Contracts
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Chrome.Header as Header
import Panels.Api (requestText)

type Connect4MoveRequest =
  { panel :: String
  , game :: String
  , experimentHash :: String
  , moves :: Array Int
  , humanIsPlayer :: Int
  , simulationsPerMove :: Int
  }

type Connect4MoveResponse = Contracts.AdversarialMoveResult

type GameSpec =
  { name :: String
  , label :: String
  , experimentHash :: String
  , rows :: Int
  , cols :: Int
  }

type State =
  { moves :: Array Int
  , game :: GameSpec
  , humanIsPlayer :: Int
  , replayIndex :: Int
  , pendingMove :: Boolean
  , lastResponse :: Maybe Connect4MoveResponse
  , lastError :: Maybe String
  }

data Action
  = PlayMove Int
  | MoveText String
  | MoveReceived Connect4MoveResponse
  | MoveFailed String
  | SelectGame GameSpec
  | ResetGame
  | StepReplay Int

panelName :: String
panelName = "connect4-human-vs-alphazero"

defaultSimulations :: Int
defaultSimulations = 400

defaultExperimentHash :: String
defaultExperimentHash = "connect4-alphazero"

connect4Game :: GameSpec
connect4Game =
  { name: "connect4"
  , label: "Connect 4"
  , experimentHash: defaultExperimentHash
  , rows: 6
  , cols: 7
  }

othelloGame :: GameSpec
othelloGame =
  { name: "othello"
  , label: "Othello"
  , experimentHash: "othello-alphazero"
  , rows: 8
  , cols: 8
  }

hexGame :: GameSpec
hexGame =
  { name: "hex"
  , label: "Hex"
  , experimentHash: "hex-alphazero"
  , rows: 11
  , cols: 11
  }

gomokuGame :: GameSpec
gomokuGame =
  { name: "gomoku"
  , label: "Gomoku"
  , experimentHash: "gomoku-alphazero"
  , rows: 15
  , cols: 15
  }

canonicalGames :: Array GameSpec
canonicalGames = [ connect4Game, othelloGame, hexGame, gomokuGame ]

renderMoveRequest :: Array Int -> Int -> Connect4MoveRequest
renderMoveRequest moves humanIsPlayer =
  { panel: panelName
  , game: connect4Game.name
  , experimentHash: connect4Game.experimentHash
  , moves
  , humanIsPlayer
  , simulationsPerMove: defaultSimulations
  }

initialState :: State
initialState =
  { moves: []
  , game: connect4Game
  , humanIsPlayer: 1
  , replayIndex: 0
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
    PlayMove move -> do
      state <- H.get
      let
        replayMoves = visibleMoves state
        nextMoves = Array.snoc replayMoves move
      H.put
        state
          { moves = nextMoves
          , replayIndex = Array.length nextMoves
          , pendingMove = true
          , lastError = Nothing
          }
      requestText
        "POST"
        "/api/connect4/move"
        ( Contracts.renderBrowserAdversarialMoveRequest
            panelName
            state.game.name
            state.game.experimentHash
            nextMoves
            state.humanIsPlayer
            defaultSimulations
        )
        MoveText
        MoveFailed
    MoveText payload ->
      case Contracts.parseAdversarialMoveResult payload of
        Just response ->
          handleAction (MoveReceived response)
        Nothing ->
          handleAction (MoveFailed ("unexpected move response: " <> payload))
    MoveReceived response ->
      H.modify_
        ( \s ->
            let
              nextMoves = Array.snoc s.moves response.chosenColumn
            in
              s
                { moves = nextMoves
                , replayIndex = Array.length nextMoves
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
    SelectGame game ->
      H.put
        initialState
          { game = game
          }
    ResetGame ->
      H.modify_
        ( \s ->
            initialState
              { game = s.game
              }
        )
    StepReplay delta ->
      H.modify_
        ( \s ->
            let
              upper = Array.length s.moves
              nextIndex = min upper (max 0 (s.replayIndex + delta))
            in
              s { replayIndex = nextIndex }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text (state.game.label <> " (human vs AlphaZero)") ]
      , renderGameTabs state
      , renderGameRules state
      , renderBoard state
      , HH.div
          [ HP.id (panelName <> "-moves")
          , HP.classes [ H.ClassName "connect4-moves" ]
          ]
          [ HH.text ("moves: " <> show (visibleMoves state)) ]
      , renderReplayControls state
      , renderAnalysis state
      , HH.button
          [ HP.id (panelName <> "-reset")
          , HE.onClick (\_ -> ResetGame)
          ]
          [ HH.text "Reset" ]
      , renderError state
      ]

  renderGameTabs state =
    HH.div
      [ HP.id (panelName <> "-games")
      , HP.classes [ H.ClassName "adversarial-games" ]
      ]
      (map (gameButton state) canonicalGames)

  gameButton state game =
    HH.button
      [ HP.id (panelName <> "-game-" <> game.name)
      , HP.classes
          [ H.ClassName "adversarial-game-tab"
          , H.ClassName (if state.game.name == game.name then "selected" else "idle")
          ]
      , HP.disabled state.pendingMove
      , HE.onClick (\_ -> SelectGame game)
      ]
      [ HH.text game.label ]

  renderBoard state =
    let
      boardState = replayState state
    in
      HH.div
        [ HP.id (panelName <> "-board")
        , HP.classes [ H.ClassName "connect4-board", H.ClassName ("game-" <> state.game.name) ]
        ]
        [ renderMoveControls boardState
        , HH.div
            [ HP.id (panelName <> "-grid")
            , HP.classes [ H.ClassName "connect4-grid" ]
            ]
            (map (renderCell boardState) (boardCells state.game))
        ]

  renderMoveControls state =
    if state.game.name == "connect4" then
      HH.div
        [ HP.id (panelName <> "-columns")
        , HP.classes [ H.ClassName "connect4-columns" ]
        ]
        (map (moveButton state) (range 0 (state.game.cols - 1)))
    else
      HH.div
        [ HP.id (panelName <> "-cells")
        , HP.classes [ H.ClassName "adversarial-cell-actions" ]
        ]
        []

  moveButton state move =
    HH.button
      [ HP.id (panelName <> "-move-" <> show move)
      , HP.classes [ H.ClassName "connect4-column" ]
      , HP.disabled (moveDisabled state move)
      , HE.onClick (\_ -> PlayMove move)
      ]
      [ HH.text (show move) ]

  renderCell state cell =
    HH.button
      [ HP.classes
          [ H.ClassName "connect4-cell"
          , H.ClassName (cellClass (cellOwner state cell.row cell.col))
          ]
      , HP.disabled (cellDisabled state cell)
      , HE.onClick (\_ -> PlayMove (cellAction state.game cell))
      ]
      [ HH.text (cellText (cellOwner state cell.row cell.col)) ]

  boardCells game =
    Array.concatMap
      (\row -> map (\col -> { row, col }) (range 0 (game.cols - 1)))
      (range 0 (game.rows - 1))

  cellOwner state row col =
    case state.game.name of
      "connect4" -> connect4CellOwner state.moves row col
      "othello" -> othelloCellOwner state.moves row col
      _ -> flatCellOwner state.moves (row * state.game.cols + col)

  connect4CellOwner moves row col =
    let
      columnMoves =
        Array.filter
          (\item -> item.move == col)
          (Array.mapWithIndex (\index move -> { index, move }) moves)
      slotFromBottom = 5 - row
    in
      case Array.index columnMoves slotFromBottom of
        Nothing -> Nothing
        Just item ->
          if item.index `mod` 2 == 0 then Just 1 else Just 2

  othelloCellOwner moves row col =
    let
      action = row * othelloGame.cols + col
    in
      case flatCellOwner moves action of
        Just owner -> Just owner
        Nothing ->
          case action of
            27 -> Just 2
            28 -> Just 1
            35 -> Just 1
            36 -> Just 2
            _ -> Nothing

  flatCellOwner moves action =
    case Array.findIndex (_ == action) moves of
      Nothing -> Nothing
      Just index ->
        if index `mod` 2 == 0 then Just 1 else Just 2

  cellClass owner =
    case owner of
      Just 1 -> "connect4-cell-p1"
      Just 2 -> "connect4-cell-p2"
      _ -> "connect4-cell-empty"

  cellText owner =
    case owner of
      Just 1 -> "1"
      Just 2 -> "2"
      _ -> ""

  cellAction game cell =
    if game.name == "connect4" then cell.col else cell.row * game.cols + cell.col

  cellIsOpen state cell =
    moveIsOpen state (cellAction state.game cell)

  moveDisabled state move =
    state.pendingMove || state.replayIndex < Array.length state.moves || not (moveIsOpen state move)

  cellDisabled state cell =
    state.pendingMove || state.replayIndex < Array.length state.moves || not (cellIsOpen state cell)

  moveIsOpen state move =
    if state.game.name == "connect4" then
      Array.length (Array.filter (_ == move) state.moves) < state.game.rows
    else
      case Array.findIndex (_ == move) state.moves of
        Nothing -> true
        Just _ -> false

  visibleMoves state =
    Array.take state.replayIndex state.moves

  replayState state =
    state { moves = visibleMoves state }

  actionCount game =
    if game.name == "connect4" then game.cols else game.rows * game.cols

  renderGameRules state =
    let
      boardState = replayState state
      actions = range 0 (actionCount state.game - 1)
      legalCount = Array.length (Array.filter (moveIsOpen boardState) actions)
    in
      HH.div
        [ HP.id (panelName <> "-rules")
        , HP.classes [ H.ClassName "adversarial-rules" ]
        ]
        [ HH.div_ [ HH.text ("rules: " <> rulesSummary state.game.name) ]
        , HH.ul
            [ HP.id (panelName <> "-rules-detail")
            , HP.classes [ H.ClassName "adversarial-rules-detail" ]
            ]
            (map (\line -> HH.li_ [ HH.text line ]) (gameRulesDetail state.game))
        , HH.div_ [ HH.text ("legal actions: " <> show legalCount) ]
        ]

  rulesSummary gameName =
    case gameName of
      "othello" -> "8x8 disk-flip game with center opening and pass-aware terminal scoring"
      "hex" -> "11x11 connection game; players race to join opposing board edges"
      "gomoku" -> "15x15 five-in-a-row game over rows, columns, and diagonals"
      _ -> "7-column gravity game; four connected stones wins"

  -- Rules-complete per-game annotations: board size, win condition, and
  -- move semantics for each canonical adversarial game, rendered as a
  -- detail list alongside the one-line summary and live legal-action count.
  gameRulesDetail game =
    [ "board: " <> show game.rows <> " rows x " <> show game.cols <> " cols"
    , "win condition: " <> winCondition game.name
    , "move semantics: " <> moveSemantics game.name
    ]

  winCondition gameName =
    case gameName of
      "othello" -> "hold the majority of disks when neither player has a legal move"
      "hex" -> "join your two opposing board edges with one unbroken chain of stones"
      "gomoku" -> "place five stones in a row horizontally, vertically, or diagonally"
      _ -> "connect four of your stones in a line before your opponent does"

  moveSemantics gameName =
    case gameName of
      "othello" -> "place a disk that brackets and flips at least one opposing line"
      "hex" -> "place one stone on any empty cell; there are no captures and no draws"
      "gomoku" -> "place one stone on any empty intersection of the grid"
      _ -> "drop a stone into a column; it falls to the lowest open cell"

  renderReplayControls state =
    HH.div
      [ HP.id (panelName <> "-replay")
      , HP.classes [ H.ClassName "adversarial-replay" ]
      ]
      [ HH.button
          [ HP.id (panelName <> "-replay-prev")
          , HP.disabled (state.replayIndex <= 0 || state.pendingMove)
          , HE.onClick (\_ -> StepReplay (-1))
          ]
          [ HH.text "prev" ]
      , HH.button
          [ HP.id (panelName <> "-replay-next")
          , HP.disabled (state.replayIndex >= Array.length state.moves || state.pendingMove)
          , HE.onClick (\_ -> StepReplay 1)
          ]
          [ HH.text "next" ]
      , HH.span_
          [ HH.text
              ( show state.replayIndex
                  <> "/"
                  <> show (Array.length state.moves)
              )
          ]
      ]

  renderAnalysis state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.div
          [ HP.id (panelName <> "-analysis")
          , HP.classes [ H.ClassName "connect4-analysis" ]
          ]
          [ HH.div_ [ HH.text ("engine action: " <> show response.chosenColumn) ]
          , HH.div_ [ HH.text ("value: " <> show response.valueEstimate) ]
          , HH.div_ [ HH.text ("transcript: " <> response.transcriptId) ]
          , HH.ol
              [ HP.id (panelName <> "-visits") ]
              (map renderVisit (Array.zipWith (\move visits -> { move, visits }) response.legalMoves response.visitCounts))
          ]

  renderVisit item =
    HH.li_
      [ HH.text ("move " <> show item.move <> ": " <> show item.visits <> " visits") ]

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
