-- | Checkpoint-comparison panel.
-- |
-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — asynchronous to the
-- | browser: publishes a checkpoint-compare `WorkCommand` fire-and-forget and
-- | renders the Engine-computed `CompareFrame` (two inferences + delta, computed
-- | in the daemon) streamed on `/api/ws/inference`, matched by
-- | `baseline-experiment-hash`. No webapp/panel compute.
module Panels.CheckpointCompare where

import Prelude

import Chrome.Header as Header
import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Maybe as Maybe
import Data.Number as Number
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

type CheckpointCompareRequest = Contracts.BrowserCheckpointCompareRequest

type CheckpointCompareResponse = Contracts.CompareFrame

type State =
  { lastResponse :: Maybe CheckpointCompareResponse
  , pendingCompare :: Boolean
  , lastError :: Maybe String
  , inputText :: Array String
  }

data Action
  = Initialize
  | SetInput Int String
  | CompareCheckpoints
  | CompareAck String
  | FrameText String
  | CompareReceived CheckpointCompareResponse
  | CompareFailed String

panelName :: String
panelName = "checkpoint-compare-lab"

defaultBaselineExperimentHash :: String
defaultBaselineExperimentHash = "generic-tensor-demo"

defaultCandidateExperimentHash :: String
defaultCandidateExperimentHash = "generic-tensor-demo-candidate"

defaultInputText :: Array String
defaultInputText = [ "0.25", "-0.5", "1.0", "2.0" ]

renderRequest :: Array Number -> CheckpointCompareRequest
renderRequest input =
  { panel: panelName
  , baselineExperimentHash: defaultBaselineExperimentHash
  , candidateExperimentHash: defaultCandidateExperimentHash
  , input
  }

initialState :: State
initialState =
  { lastResponse: Nothing
  , pendingCompare: false
  , lastError: Nothing
  , inputText: defaultInputText
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
      subscribeStream "/api/ws/inference" FrameText CompareFailed
    SetInput index value ->
      H.modify_
        ( \s ->
            s
              { inputText =
                  Maybe.fromMaybe s.inputText (Array.updateAt index value s.inputText)
              }
        )
    CompareCheckpoints -> do
      state <- H.get
      H.modify_ (_ { pendingCompare = true, lastError = Nothing })
      requestText
        "POST"
        "/api/checkpoints/compare"
        ( Contracts.renderBrowserCheckpointCompareRequest
            panelName
            defaultBaselineExperimentHash
            defaultCandidateExperimentHash
            (compareInput state)
        )
        CompareAck
        CompareFailed
    CompareAck payload ->
      case Contracts.parseCompareFrame payload of
        Just frame | frame.baselineExperimentHash == defaultBaselineExperimentHash ->
          handleAction (CompareReceived frame)
        _ ->
          pure unit
    FrameText payload ->
      case Contracts.fieldValue "baseline-experiment-hash" payload of
        Just hash | hash == defaultBaselineExperimentHash ->
          case Contracts.parseCompareFrame payload of
            Just frame -> handleAction (CompareReceived frame)
            Nothing -> handleAction (CompareFailed ("unexpected compare frame: " <> payload))
        _ ->
          pure unit
    CompareReceived response ->
      H.modify_
        ( _
            { pendingCompare = false
            , lastResponse = Just response
            , lastError = Nothing
            }
        )
    CompareFailed message ->
      H.modify_
        ( _
            { pendingCompare = false
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Checkpoint comparison" ]
      , HH.div
          [ HP.id (panelName <> "-inputs") ]
          [ HH.text
              ( defaultBaselineExperimentHash
                  <> " vs "
                  <> defaultCandidateExperimentHash
                  <> " on "
                  <> show (compareInput state)
              )
          ]
      , HH.div
          [ HP.id (panelName <> "-input") ]
          (Array.mapWithIndex renderInput state.inputText)
      , HH.button
          [ HP.id (panelName <> "-submit")
          , HP.disabled state.pendingCompare
          , HE.onClick (\_ -> CompareCheckpoints)
          ]
          [ HH.text (if state.pendingCompare then "Comparing..." else "Compare") ]
      , renderResult state
      , renderError state
      ]

  renderResult state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.div
          [ HP.id (panelName <> "-result")
          , HP.classes [ H.ClassName "jitml-compare-result" ]
          ]
          [ HH.div_ [ HH.text ("baseline " <> response.baselineExperimentHash) ]
          , HH.div_ [ HH.text ("candidate " <> response.candidateExperimentHash) ]
          , HH.div_ [ HH.text ("max delta " <> show response.maxAbsDelta) ]
          , HH.div_ [ HH.text ("mean delta " <> show response.meanAbsDelta) ]
          , HH.ol
              [ HP.id (panelName <> "-baseline-output")
              , HP.classes [ H.ClassName "jitml-distribution" ]
              ]
              (map renderOutputValue response.baselineOutput)
          , HH.ol
              [ HP.id (panelName <> "-candidate-output")
              , HP.classes [ H.ClassName "jitml-distribution" ]
              ]
              (map renderOutputValue response.candidateOutput)
          ]

  renderOutputValue value =
    HH.li_ [ HH.text (show value) ]

  renderInput index value =
    HH.input
      [ HP.id (panelName <> "-input-" <> show index)
      , HP.type_ HP.InputText
      , HP.value value
      , HE.onValueInput (SetInput index)
      ]

  compareInput state =
    map parseNumber state.inputText

  parseNumber raw =
    Maybe.fromMaybe 0.0 (Number.fromString raw)

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("checkpoint compare error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose

renderCompareSnapshot :: Maybe CheckpointCompareResponse -> String
renderCompareSnapshot response =
  Maybe.fromMaybe
    "checkpoint-compare: (none)"
    ( response
        # map
            ( \r ->
                "checkpoint-compare: max="
                  <> show r.maxAbsDelta
                  <> " mean="
                  <> show r.meanAbsDelta
            )
    )
