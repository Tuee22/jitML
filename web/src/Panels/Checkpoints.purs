-- | Checkpoint browse panel.
-- |
-- | Sprint 14.1 (Feature A) — asynchronous to the browser: on init it POSTs
-- | `/api/checkpoints` (a trigger) and subscribes to `/api/ws/inference`. The
-- | Engine lists the seeded experiments' manifests from MinIO and replies with a
-- | `CheckpointList` frame, which this panel renders as a list. No webapp/panel
-- | compute — the daemon lists; the panel renders.
module Panels.Checkpoints where

import Prelude

import Chrome.Header as Header
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Generated.Contracts as Contracts
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type CheckpointListResponse = Contracts.CheckpointList

type State =
  { lastResponse :: Maybe CheckpointListResponse
  , pendingList :: Boolean
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | ListAck String
  | FrameText String
  | ListReceived CheckpointListResponse
  | ListFailed String

panelName :: String
panelName = "checkpoint-browse"

initialState :: State
initialState =
  { lastResponse: Nothing
  , pendingList: true
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
    Initialize -> do
      subscribeStream "/api/ws/inference" FrameText ListFailed
      requestText
        "POST"
        "/api/checkpoints"
        "kind: BrowserListCheckpointsRequest\n"
        ListAck
        ListFailed
    ListAck _ ->
      pure unit
    FrameText payload ->
      case Contracts.parseCheckpointList payload of
        Just frame -> handleAction (ListReceived frame)
        Nothing ->
          pure unit
    ListReceived response ->
      H.modify_
        ( _
            { pendingList = false
            , lastResponse = Just response
            , lastError = Nothing
            }
        )
    ListFailed message ->
      H.modify_
        ( _
            { pendingList = false
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Checkpoint browse" ]
      , renderStatus state
      , renderList state
      , renderModelMatrix
      , renderError state
      ]

  renderStatus state =
    HH.div
      [ HP.id (panelName <> "-status") ]
      [ HH.text
          ( if state.pendingList then "Loading checkpoints…"
            else "Seeded experiment checkpoints"
          )
      ]

  renderList state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.ol
          [ HP.id (panelName <> "-list")
          , HP.classes [ H.ClassName "jitml-checkpoint-list" ]
          ]
          (map renderItem response.checkpoints)

  renderItem summary =
    HH.li
      [ HP.id (panelName <> "-item-" <> summary.sha)
      , HP.classes [ H.ClassName "jitml-checkpoint-item" ]
      ]
      [ HH.div_ [ HH.text ("experiment: " <> summary.experimentHash) ]
      , HH.div_ [ HH.text ("sha: " <> summary.sha) ]
      , HH.div_ [ HH.text ("step: " <> show summary.step) ]
      , HH.div_ [ HH.text ("family: " <> summary.modelFamily) ]
      , HH.div_ [ HH.text ("tensors: " <> show summary.tensorCount) ]
      , HH.div_ [ HH.text ("eligibility: " <> summary.eligibility) ]
      , HH.div_ [ HH.text ("budget: " <> summary.completedBudget) ]
      , HH.div_ [ HH.text ("convergence: " <> summary.convergenceMetrics) ]
      , HH.div_
          [ HH.a
              [ HP.href ("/tensorboard/#" <> summary.tensorboardPrefix) ]
              [ HH.text ("tensorboard: " <> summary.tensorboardPrefix) ]
          ]
      ]

  renderModelMatrix =
    HH.section
      [ HP.id (panelName <> "-model-matrix") ]
      [ HH.h3_ [ HH.text "All model artifact rows" ]
      , HH.ol
          [ HP.id (panelName <> "-model-matrix-list") ]
          (map renderModelRow Contracts.allModelMatrixRows)
      ]

  renderModelRow row =
    HH.li_
      [ HH.div_ [ HH.text ("model: " <> row.name) ]
      , HH.div_ [ HH.text ("kind: " <> row.kind) ]
      , HH.div_ [ HH.text ("budget: " <> row.budget) ]
      , HH.div_
          [ HH.text
              ( "requires trained artifact: "
                  <> (if row.requiresTrainedArtifact then "yes" else "no")
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
          [ HH.text ("checkpoint browse error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
