-- | Transcript-backed adversarial replay panel.
-- |
-- | Sprint 14.1 (Feature B) — asynchronous to the browser: the operator pastes a
-- | persisted transcript id (a `jitml-transcripts` MinIO key, as emitted by the
-- | Connect4 panel's streamed `transcript-id`) and presses "Load transcript".
-- | The panel POSTs `/api/transcripts/replay`; the Engine reads the persisted
-- | transcript from MinIO and replies with a `TranscriptReplay` frame on
-- | `/api/ws/inference`. The panel populates `moves` from the streamed frame and
-- | drives the same `StepReplay` scrubber + connect4 cell reconstruction the
-- | live Connect4 panel uses, over the persisted moves. No webapp/panel
-- | compute.
module Panels.Replay where

import Prelude

import Chrome.Header as Header
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
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type TranscriptReplayResponse = Contracts.TranscriptReplay

type State =
  { transcriptId :: String
  , moves :: Array Int
  , game :: String
  , replayIndex :: Int
  , pendingLoad :: Boolean
  , lastResponse :: Maybe TranscriptReplayResponse
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | SetTranscriptId String
  | LoadTranscript
  | LoadAck String
  | FrameText String
  | ReplayReceived TranscriptReplayResponse
  | ReplayFailed String
  | StepReplay Int

panelName :: String
panelName = "transcript-replay"

connect4Cols :: Int
connect4Cols = 7

connect4Rows :: Int
connect4Rows = 6

initialState :: State
initialState =
  { transcriptId: ""
  , moves: []
  , game: "connect4"
  , replayIndex: 0
  , pendingLoad: false
  , lastResponse: Nothing
  , lastError: Nothing
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> initialState
    , render
    , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
    }
  where
  handleAction = case _ of
    Initialize ->
      subscribeStream "/api/ws/inference" FrameText ReplayFailed
    SetTranscriptId value ->
      H.modify_ (_ { transcriptId = value })
    LoadTranscript -> do
      state <- H.get
      H.modify_ (_ { pendingLoad = true, lastError = Nothing })
      requestText
        "POST"
        "/api/transcripts/replay"
        ( "kind: BrowserLoadTranscriptRequest\n"
            <> "transcript-id: "
            <> state.transcriptId
            <> "\n"
        )
        LoadAck
        ReplayFailed
    LoadAck payload ->
      case Contracts.parseTranscriptReplay payload of
        Just frame -> handleAction (ReplayReceived frame)
        Nothing -> pure unit
    FrameText payload ->
      case Contracts.parseTranscriptReplay payload of
        Just frame -> handleAction (ReplayReceived frame)
        Nothing ->
          pure unit
    ReplayReceived response ->
      H.modify_
        ( _
            { pendingLoad = false
            , moves = response.moves
            , game = response.game
            , replayIndex = 0
            , lastResponse = Just response
            , lastError = Nothing
            }
        )
    ReplayFailed message ->
      H.modify_
        ( _
            { pendingLoad = false
            , lastError = Just message
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
      , HH.h2_ [ HH.text "Transcript replay" ]
      , HH.input
          [ HP.id (panelName <> "-transcript-id")
          , HP.type_ HP.InputText
          , HP.value state.transcriptId
          , HP.placeholder "transcript id"
          , HE.onValueInput SetTranscriptId
          ]
      , HH.button
          [ HP.id (panelName <> "-transcript-load")
          , HP.disabled (state.pendingLoad || state.transcriptId == "")
          , HE.onClick (\_ -> LoadTranscript)
          ]
          [ HH.text (if state.pendingLoad then "Loading…" else "Load transcript") ]
      , renderBoard state
      , HH.div
          [ HP.id (panelName <> "-moves") ]
          [ HH.text ("moves: " <> show (visibleMoves state)) ]
      , renderReplayControls state
      , renderError state
      ]

  visibleMoves state =
    Array.take state.replayIndex state.moves

  renderBoard state =
    HH.div
      [ HP.id (panelName <> "-board")
      , HP.classes [ H.ClassName "connect4-board" ]
      ]
      [ HH.div
          [ HP.id (panelName <> "-grid")
          , HP.classes [ H.ClassName "connect4-grid" ]
          ]
          (map (renderCell (visibleMoves state)) boardCells)
      ]

  boardCells =
    Array.concatMap
      (\row -> map (\col -> { row, col }) (range 0 (connect4Cols - 1)))
      (range 0 (connect4Rows - 1))

  renderCell moves cell =
    HH.div
      [ HP.classes
          [ H.ClassName "connect4-cell"
          , H.ClassName (cellClass (connect4CellOwner moves cell.row cell.col))
          ]
      ]
      [ HH.text (cellText (connect4CellOwner moves cell.row cell.col)) ]

  connect4CellOwner moves row col =
    let
      columnMoves =
        Array.filter
          (\item -> item.move == col)
          (Array.mapWithIndex (\index move -> { index, move }) moves)
      slotFromBottom = (connect4Rows - 1) - row
    in
      case Array.index columnMoves slotFromBottom of
        Nothing -> Nothing
        Just item ->
          if item.index `mod` 2 == 0 then Just 1 else Just 2

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

  renderReplayControls state =
    HH.div
      [ HP.id (panelName <> "-replay")
      , HP.classes [ H.ClassName "adversarial-replay" ]
      ]
      [ HH.button
          [ HP.id (panelName <> "-replay-prev")
          , HP.disabled (state.replayIndex <= 0 || state.pendingLoad)
          , HE.onClick (\_ -> StepReplay (-1))
          ]
          [ HH.text "prev" ]
      , HH.button
          [ HP.id (panelName <> "-replay-next")
          , HP.disabled (state.replayIndex >= Array.length state.moves || state.pendingLoad)
          , HE.onClick (\_ -> StepReplay 1)
          ]
          [ HH.text "next" ]
      , HH.span
          [ HP.id (panelName <> "-replay-cursor") ]
          [ HH.text
              ( show state.replayIndex
                  <> "/"
                  <> show (Array.length state.moves)
              )
          ]
      ]

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("transcript replay error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
