-- | Live workflow-status panel.
-- |
-- | Sprint 14.1 (Feature C) — asynchronous to the browser: subscribes to
-- | `/api/ws/workflow` and renders the Engine's reconciled `WorkflowStatus`
-- | frames (queued / running / done / failed) as a live table keyed by run id.
-- | The status projector in the daemon republishes each observed lifecycle
-- | transition onto `workflow.status.<substrate>`; this panel renders it. No
-- | webapp/panel compute.
module Panels.Workflow where

import Prelude

import Chrome.Header as Header
import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Generated.Contracts as Contracts
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Panels.Stream (subscribeStream)

type WorkflowStatus = Contracts.WorkflowStatus

type State =
  { rows :: Array WorkflowStatus
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | FrameText String
  | StatusReceived WorkflowStatus
  | StatusFailed String

panelName :: String
panelName = "workflow-status"

initialState :: State
initialState =
  { rows: []
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
      subscribeStream "/api/ws/workflow" FrameText StatusFailed
    FrameText payload ->
      case Contracts.parseWorkflowStatus payload of
        Just status -> handleAction (StatusReceived status)
        Nothing ->
          pure unit
    StatusReceived status ->
      H.modify_
        ( \s ->
            s
              { rows = upsertStatus status s.rows
              , lastError = Nothing
              }
        )
    StatusFailed message ->
      H.modify_ (_ { lastError = Just message })

  -- Latest status wins per run id: replace an existing row, else append.
  upsertStatus status rows =
    case Array.findIndex (\row -> row.runId == status.runId) rows of
      Just index -> fromMaybe rows (Array.updateAt index status rows)
      Nothing -> Array.snoc rows status

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Workflow status" ]
      , renderTable state
      , renderError state
      ]

  renderTable state =
    HH.table
      [ HP.id (panelName <> "-table")
      , HP.classes [ H.ClassName "jitml-workflow-table" ]
      ]
      ( [ HH.tr_
            [ HH.th_ [ HH.text "run" ]
            , HH.th_ [ HH.text "status" ]
            , HH.th_ [ HH.text "detail" ]
            ]
        ]
          <> map renderRow state.rows
      )

  renderRow row =
    HH.tr
      [ HP.id (panelName <> "-row-" <> row.runId)
      , HP.classes [ H.ClassName "jitml-workflow-row" ]
      ]
      [ HH.td_ [ HH.text row.runId ]
      , HH.td_ [ HH.text row.status ]
      , HH.td_ [ HH.text row.detail ]
      ]

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("workflow status error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
