-- | Checkpoint browse panel.
-- |
-- | The daemon returns one complete, publication-bound `CheckpointList` from
-- | `/api/checkpoints`. The generated parser rejects partial, duplicated,
-- | orphaned, reordered, or identity-mismatched rows before this component can
-- | render them. Static registry rows are declarations only and are always
-- | shown as `NotRun`; only a validated live response can render `Passed`.
module Panels.Checkpoints where

import Prelude

import Chrome.Header as Header
import Data.Array as Array
import Data.Either (Either(..))
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

type CheckpointListResponse = Contracts.CheckpointList

type State =
  { lastResponse :: Maybe CheckpointListResponse
  , pendingList :: Boolean
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | ListAck String
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
    Initialize ->
      requestText
        "POST"
        "/api/checkpoints"
        "kind: BrowserListCheckpointsRequest\n"
        ListAck
        ListFailed
    ListAck payload ->
      case Contracts.parseCheckpointList payload of
        Left detail -> handleAction (ListFailed detail)
        Right response -> handleAction (ListReceived response)
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
            , lastResponse = Nothing
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Checkpoint browse" ]
      , renderStatus state
      , renderPublication state
      , renderList state
      , renderArtifactRenderers state
      , renderModelMatrix state
      , renderError state
      ]

  renderStatus state =
    HH.div
      [ HP.id (panelName <> "-status") ]
      [ HH.text
          ( case state.lastResponse, state.lastError of
              Just response, _ ->
                let
                  passed = Array.length (Array.filter (\row -> row.evidenceStatus == "Passed") response.rowSelectors)
                  failed = Array.length (Array.filter (\row -> row.evidenceStatus == "Failed") response.rowSelectors)
                  notRun = Array.length (Array.filter (\row -> row.evidenceStatus == "NotRun") response.rowSelectors)
                  completion =
                    if passed == response.count && failed == 0 && notRun == 0 then
                      "; complete publication-bound checkpoint evidence"
                    else
                      "; incomplete checkpoint evidence"
                in
                  "Passed: " <> show passed <> "; Failed: " <> show failed
                    <> "; NotRun: "
                    <> show notRun
                    <> completion
              Nothing, Just _ ->
                "Passed: 0; Failed: 0; NotRun: " <> show (Array.length Contracts.allModelMatrixRows)
                  <> "; request: Failed; checkpoint evidence was rejected"
              Nothing, Nothing ->
                if state.pendingList then
                  "Passed: 0; Failed: 0; NotRun: " <> show (Array.length Contracts.allModelMatrixRows)
                    <> "; loading checkpoint evidence"
                else
                  "Passed: 0; Failed: 0; NotRun: " <> show (Array.length Contracts.allModelMatrixRows)
                    <> "; checkpoint evidence unavailable"
          )
      ]

  renderPublication state =
    case state.lastResponse of
      Nothing ->
        HH.section
          [ HP.id (panelName <> "-publication") ]
          [ HH.div [ HP.id (panelName <> "-publication-status") ] [ HH.text "status: NotRun" ]
          , HH.div [ HP.id (panelName <> "-publication-reason") ] [ HH.text "reason: no validated live CheckpointList" ]
          ]
      Just response ->
        HH.section
          [ HP.id (panelName <> "-publication") ]
          [ HH.div [ HP.id (panelName <> "-publication-status") ] [ HH.text ("status: " <> response.publicationStatus) ]
          , HH.div [ HP.id (panelName <> "-run-id") ] [ HH.text ("run-id: " <> response.runId) ]
          , HH.div [ HP.id (panelName <> "-substrate") ] [ HH.text ("substrate: " <> response.substrate) ]
          , HH.div [ HP.id (panelName <> "-catalogue-sha256") ] [ HH.text ("catalogue-sha256: " <> response.catalogueSha256) ]
          , HH.div [ HP.id (panelName <> "-source-journal-sha256") ] [ HH.text ("source-journal-sha256: " <> response.sourceJournalSha256) ]
          , HH.div [ HP.id (panelName <> "-row-count") ] [ HH.text ("count: " <> show response.count) ]
          , HH.div [ HP.id (panelName <> "-selector-state") ] [ HH.text ("selector-state: " <> response.selectorState) ]
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
    let
      prefix = panelName <> "-summary-" <> show summary.ordinal
    in
      HH.li
        [ HP.id prefix
        , HP.classes [ H.ClassName "jitml-checkpoint-item" ]
        ]
        [ evidenceCell prefix "row-id" ("row: " <> summary.rowId)
        , evidenceCell prefix "plan-id" ("PlanId: " <> summary.planId)
        , evidenceCell prefix "experiment-hash" ("experiment: " <> summary.experimentHash)
        , evidenceCell prefix "manifest-sha256" ("manifest: " <> summary.sha)
        , evidenceCell prefix "step" ("step: " <> show summary.step)
        , evidenceCell prefix "family" ("family: " <> summary.modelFamily)
        , evidenceCell prefix "tensor-count" ("tensors: " <> show summary.tensorCount)
        , evidenceCell prefix "eligibility" ("eligibility: " <> summary.eligibility)
        , evidenceCell prefix "budget" ("budget: " <> summary.completedBudget)
        , evidenceCell prefix "measured-result" ("measured-result: " <> summary.measuredResult)
        , HH.div
            [ HP.id (prefix <> "-tensorboard") ]
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
    let
      prefix = panelName <> "-selector-" <> show row.ordinal
    in
      HH.li
        [ HP.id prefix ]
        [ evidenceCell prefix "row-id" ("model: " <> row.rowId)
        , evidenceCell prefix "plan-id" ("PlanId: " <> row.planId)
        , evidenceCell prefix "experiment-hash" ("experiment: " <> row.experimentHash)
        , evidenceCell prefix "manifest-sha256" ("manifest: " <> row.manifestSha)
        , evidenceCell prefix "family" ("kind: " <> row.family)
        , evidenceCell prefix "status" ("status: " <> row.evidenceStatus)
        , evidenceCell prefix "reason" (renderEvidenceReason row.evidenceReason)
        , evidenceCell prefix "panel" ("panel: " <> row.demoPanel)
        ]

  renderModelRow row =
    let
      prefix = panelName <> "-declaration-" <> row.name
    in
      HH.li
        [ HP.id prefix ]
        [ evidenceCell prefix "row-id" ("model: " <> row.name)
        , evidenceCell prefix "plan-id" "PlanId: NotRun; live substrate unavailable"
        , evidenceCell prefix "experiment-hash" ("experiment: " <> row.experimentHash)
        , evidenceCell prefix "status" "status: NotRun"
        , evidenceCell prefix "reason" "reason: declaration only; substrate-bound live evidence not loaded"
        , evidenceCell prefix "e2e" ("e2e: " <> row.e2eTest)
        , evidenceCell prefix "panel" ("panel: " <> row.demoPanel)
        , evidenceCell prefix "budget" ("budget: " <> row.budget)
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
      prefix = panelName <> "-artifact-" <> show selector.ordinal
      summary =
        Array.find
          ( \checkpoint ->
              checkpoint.ordinal == selector.ordinal
                && checkpoint.rowId == selector.rowId
                && checkpoint.planId == selector.planId
                && checkpoint.experimentHash == selector.experimentHash
                && checkpoint.sha == selector.manifestSha
          )
          checkpoints
    in
      HH.li
        [ HP.id prefix
        , HP.classes
            [ H.ClassName "jitml-artifact-card"
            , H.ClassName ("artifact-" <> selector.family)
            , H.ClassName ("evidence-" <> selector.evidenceStatus)
            ]
        ]
        [ evidenceCell prefix "row-id" ("row: " <> selector.rowId)
        , evidenceCell prefix "plan-id" ("PlanId: " <> selector.planId)
        , evidenceCell prefix "experiment-hash" ("experiment: " <> selector.experimentHash)
        , evidenceCell prefix "manifest-sha256" ("manifest: " <> selector.manifestSha)
        , evidenceCell prefix "status" ("status: " <> selector.evidenceStatus)
        , evidenceCell prefix "reason" (renderEvidenceReason selector.evidenceReason)
        , case summary of
            Nothing ->
              HH.div
                [ HP.id (prefix <> "-identity-error"), HP.classes [ H.ClassName "jitml-error" ] ]
                [ HH.text "Failed: exact selector/summary identity is missing" ]
            Just checkpoint -> renderFamilyArtifact selector checkpoint
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

  supervisedInputLabel candidatePanel =
    case candidatePanel of
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
      , HH.div_ [ HH.text "action metadata: policy distribution + rollout reward" ]
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
      , HH.div_ [ HH.text ("PlanId: " <> summary.planId) ]
      , HH.div_ [ HH.text ("budget: " <> summary.completedBudget) ]
      , HH.div_ [ HH.text ("measured-result: " <> summary.measuredResult) ]
      , HH.div_ [ HH.text ("tensorboard: " <> summary.tensorboardPrefix) ]
      ]

  evidenceCell prefix suffix value =
    HH.div [ HP.id (prefix <> "-" <> suffix) ] [ HH.text value ]

  renderEvidenceReason reason =
    if reason == "" then "reason: (none)" else "reason: " <> reason

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
