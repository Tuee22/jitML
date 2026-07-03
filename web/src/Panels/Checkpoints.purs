-- | Checkpoint browse panel.
-- |
-- | Sprint 14.1 (Feature A) — asynchronous to the browser: on init it POSTs
-- | `/api/checkpoints` (a trigger) and subscribes to `/api/ws/inference`. The
-- | Engine lists product-row checkpoint manifests from MinIO and replies with a
-- | `CheckpointList` frame, which this panel renders as row selector state plus
-- | eligible checkpoint summaries. No webapp/panel compute — the daemon lists;
-- | the panel renders.
module Panels.Checkpoints where

import Prelude

import Data.Array as Array
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
      , renderArtifactRenderers state
      , renderModelMatrix state
      , renderError state
      ]

  renderStatus state =
    HH.div
      [ HP.id (panelName <> "-status") ]
      [ HH.text
          ( case state.lastResponse of
              Just response ->
                if response.selectorState == "fail-closed:no-inference-eligible-artifact" then
                  "No inference-eligible checkpoint artifacts"
                else
                  "Inference-eligible checkpoints"
              Nothing ->
                if state.pendingList then "Loading checkpoints…" else "Inference-eligible checkpoints"
          )
      ]

  renderList state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        if response.selectorState == "fail-closed:no-inference-eligible-artifact" then
          HH.div
            [ HP.id (panelName <> "-fail-closed")
            , HP.classes [ H.ClassName "jitml-fail-closed" ]
            ]
            [ HH.text "No row has an inference-eligible artifact yet." ]
        else
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
      , HH.div_ [ HH.text ("row: " <> summary.rowId) ]
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

  renderModelMatrix state =
    HH.section
      [ HP.id (panelName <> "-model-matrix") ]
      [ HH.h3_ [ HH.text "All model artifact rows" ]
      , HH.ol
          [ HP.id (panelName <> "-model-matrix-list") ]
          ( case state.lastResponse of
              Just response -> map renderSelectorRow response.rowSelectors
              Nothing -> map renderModelRow Contracts.allModelMatrixRows
          )
      ]

  renderSelectorRow row =
    HH.li_
      [ HH.div_ [ HH.text ("model: " <> row.rowId) ]
      , HH.div_ [ HH.text ("kind: " <> row.family) ]
      , HH.div_ [ HH.text ("selector: " <> row.selectorState) ]
      , HH.div_ [ HH.text ("checkpoints: " <> show row.checkpointCount) ]
      , HH.div_ [ HH.text ("experiment: " <> row.experimentHash) ]
      , HH.div_ [ HH.text ("panel: " <> row.demoPanel) ]
      , HH.div_
          [ HH.text "requires trained artifact: yes" ]
      ]

  renderModelRow row =
    HH.li_
      [ HH.div_ [ HH.text ("model: " <> row.name) ]
      , HH.div_ [ HH.text ("kind: " <> row.kind) ]
      , HH.div_ [ HH.text ("experiment: " <> row.experimentHash) ]
      , HH.div_ [ HH.text ("panel: " <> row.demoPanel) ]
      , HH.div_ [ HH.text ("budget: " <> row.budget) ]
      , HH.div_
          [ HH.text
              ( "requires trained artifact: "
                  <> (if row.requiresTrainedArtifact then "yes" else "no")
              )
          ]
      ]

  renderArtifactRenderers state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.section
          [ HP.id (panelName <> "-artifact-renderers") ]
          [ HH.h3_ [ HH.text "Artifact renderers" ]
          , HH.ol
              [ HP.id (panelName <> "-artifact-renderer-list") ]
              (map (renderArtifactCard response.checkpoints) response.rowSelectors)
          ]

  renderArtifactCard checkpoints selector =
    let
      summary = Array.find (\checkpoint -> checkpoint.rowId == selector.rowId) checkpoints
    in
      HH.li
        [ HP.id (panelName <> "-artifact-" <> selector.experimentHash)
        , HP.classes
            [ H.ClassName "jitml-artifact-card"
            , H.ClassName ("artifact-" <> selector.family)
            , H.ClassName ("selector-" <> selector.selectorState)
            ]
        ]
        [ HH.div_ [ HH.text ("row: " <> selector.rowId) ]
        , HH.div_ [ HH.text ("state: " <> selector.selectorState) ]
        , case summary of
            Nothing ->
              HH.div_
                [ HH.text ("artifact: " <> selector.selectorState) ]
            Just checkpoint ->
              renderFamilyArtifact selector checkpoint
        ]

  renderFamilyArtifact selector summary =
    case selector.family of
      "supervised" -> renderSupervisedArtifact selector summary
      "rl" -> renderRlArtifact selector summary
      "alphazero" -> renderAlphaZeroArtifact selector summary
      "tuning" -> renderTuningArtifact selector summary
      _ -> renderGenericArtifact selector summary

  renderSupervisedArtifact selector summary =
    HH.div
      [ HP.classes [ H.ClassName "artifact-supervised-renderer" ] ]
      [ HH.div_ [ HH.text ("input: " <> supervisedInputLabel selector.demoPanel) ]
      , HH.div_ [ HH.text ("output: " <> supervisedOutputLabel selector.rowId) ]
      , renderCheckpointMetadata summary
      ]

  supervisedInputLabel panel =
    case panel of
      "mnist-live-inference" -> "28x28 grayscale tensor"
      "cifar-imagenet-upload" -> "image tensor"
      "generic-inference-lab" -> "numeric feature vector"
      _ -> "tensor input"

  supervisedOutputLabel rowId =
    if rowId == "california-housing-mlp" then "regression value" else "class probabilities"

  renderRlArtifact selector summary =
    HH.div
      [ HP.classes [ H.ClassName "artifact-rl-renderer" ] ]
      [ HH.div_ [ HH.text ("trajectory: " <> selector.demoPanel) ]
      , HH.div_ [ HH.text ("policy row: " <> selector.rowId) ]
      , HH.div_ [ HH.text ("action metadata: policy distribution + rollout reward") ]
      , renderCheckpointMetadata summary
      ]

  renderAlphaZeroArtifact selector summary =
    HH.div
      [ HP.classes [ H.ClassName "artifact-alphazero-renderer" ] ]
      [ HH.div_ [ HH.text ("board: " <> alphaZeroBoardLabel selector.rowId) ]
      , HH.div_ [ HH.text "policy/value: legal moves, MCTS visits, value estimate" ]
      , HH.div_ [ HH.text ("replay panel: " <> selector.demoPanel) ]
      , renderCheckpointMetadata summary
      ]

  alphaZeroBoardLabel rowId =
    case rowId of
      "othello" -> "8x8 othello"
      "hex" -> "11x11 hex"
      "gomoku" -> "15x15 gomoku"
      _ -> "6x7 connect4"

  renderTuningArtifact selector summary =
    HH.div
      [ HP.classes [ H.ClassName "artifact-tuning-renderer" ] ]
      [ HH.div_ [ HH.text ("sweep: " <> selector.rowId) ]
      , HH.div_ [ HH.text "trial table: best objective and promoted checkpoint" ]
      , renderCheckpointMetadata summary
      ]

  renderGenericArtifact selector summary =
    HH.div
      [ HP.classes [ H.ClassName "artifact-generic-renderer" ] ]
      [ HH.div_ [ HH.text ("panel: " <> selector.demoPanel) ]
      , renderCheckpointMetadata summary
      ]

  renderCheckpointMetadata summary =
    HH.div
      [ HP.classes [ H.ClassName "artifact-metadata" ] ]
      [ HH.div_ [ HH.text ("manifest: " <> summary.sha) ]
      , HH.div_ [ HH.text ("budget: " <> summary.completedBudget) ]
      , HH.div_ [ HH.text ("convergence: " <> summary.convergenceMetrics) ]
      , HH.div_ [ HH.text ("tensorboard: " <> summary.tensorboardPrefix) ]
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
