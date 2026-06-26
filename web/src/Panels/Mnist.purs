-- | MNIST live-inference panel.
-- |
-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — the panel is now
-- | __asynchronous to the browser__: it subscribes to the
-- | `/api/ws/inference` websocket stream, publishes the inference request
-- | fire-and-forget via `POST /api/inference` (which the Webapp role turns
-- | into an Engine `WorkCommand`), and renders the streamed, Engine-decoded
-- | `DecodedInference` frame (matched by `experiment-hash`). The panel does
-- | __no compute__ — argmax/softmax happen once, in the Engine.
module Panels.Mnist where

import Prelude

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
import Chrome.Header as Header
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type MnistInferenceRequest =
  { panel :: String
  , canvasPixels :: Array Int
  , modelId :: String
  }

type Prediction = Contracts.DecodedInference

type State =
  { lastPrediction :: Maybe Prediction
  , pendingInference :: Boolean
  , lastError :: Maybe String
  , inkInput :: String
  , inkValue :: Number
  }

data Action
  = Initialize
  | SetInk String
  | Predict
  | PredictAck String
  | FrameText String
  | PredictionReceived Prediction
  | PredictionFailed String

panelName :: String
panelName = "mnist-live-inference"

defaultModelId :: String
defaultModelId = "mnist-deep-mlp"

defaultExperimentHash :: String
defaultExperimentHash = defaultModelId

emptyCanvas :: Array Int
emptyCanvas = []

renderRequest :: Array Int -> MnistInferenceRequest
renderRequest pixels =
  { panel: panelName
  , canvasPixels: pixels
  , modelId: defaultModelId
  }

initialState :: State
initialState =
  { lastPrediction: Nothing
  , pendingInference: false
  , lastError: Nothing
  , inkInput: "0.85"
  , inkValue: 0.85
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
      subscribeStream "/api/ws/inference" FrameText PredictionFailed
    SetInk raw ->
      H.modify_
        ( \s ->
            s
              { inkInput = raw
              , inkValue = Maybe.fromMaybe s.inkValue (Number.fromString raw)
              }
        )
    Predict -> do
      state <- H.get
      H.modify_ (_ { pendingInference = true, lastError = Nothing })
      requestText
        "POST"
        "/api/inference"
        (Contracts.renderBrowserInferenceRequest panelName defaultModelId defaultExperimentHash (mnistInferenceInput state))
        PredictAck
        PredictionFailed
    PredictAck payload ->
      case Contracts.parseInferenceResult payload of
        Just result | result.modelId == defaultModelId ->
          handleAction (PredictionReceived (inferenceAckToDecoded result))
        _ ->
          pure unit
    FrameText payload ->
      case Contracts.fieldValue "experiment-hash" payload of
        Just hash | hash == defaultExperimentHash ->
          case Contracts.parseDecodedInference payload of
            Just decoded -> handleAction (PredictionReceived decoded)
            Nothing -> handleAction (PredictionFailed ("unexpected inference frame: " <> payload))
        _ ->
          pure unit
    PredictionReceived decoded ->
      H.modify_
        ( _
            { pendingInference = false
            , lastPrediction = Just decoded
            , lastError = Nothing
            }
        )
    PredictionFailed message ->
      H.modify_
        ( _
            { pendingInference = false
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "MNIST live inference" ]
      , HH.canvas
          [ HP.id (panelName <> "-canvas")
          , HP.width 280
          , HP.height 280
          , HP.style ("background: rgba(0, 0, 0, " <> show state.inkValue <> ");")
          ]
      , HH.input
          [ HP.id (panelName <> "-ink")
          , HP.type_ HP.InputText
          , HP.value state.inkInput
          , HE.onValueInput SetInk
          ]
      , HH.button
          [ HP.id (panelName <> "-submit")
          , HP.disabled state.pendingInference
          , HE.onClick (\_ -> Predict)
          ]
          [ HH.text (if state.pendingInference then "Predicting…" else "Predict") ]
      , renderPredictionBadge state
      , renderError state
      ]

  renderPredictionBadge state =
    case state.lastPrediction of
      Nothing -> HH.div_ []
      Just prediction ->
        HH.div
          [ HP.id (panelName <> "-prediction")
          , HP.classes [ H.ClassName "jitml-prediction" ]
          ]
          [ HH.div_
              [ HH.text
                  ( "predicted "
                      <> show prediction.topClass
                      <> " from "
                      <> defaultModelId
                      <> " (confidence "
                      <> show prediction.confidence
                      <> ")"
                  )
              ]
          , HH.ol
              [ HP.id (panelName <> "-distribution")
              , HP.classes [ H.ClassName "jitml-distribution" ]
              ]
              (map renderProbabilityBar prediction.probabilities)
          ]

  renderProbabilityBar probability =
    HH.li_
      [ HH.div
          [ HP.classes [ H.ClassName "jitml-bar" ] ]
          [ HH.div
              [ HP.classes [ H.ClassName "jitml-bar-fill" ]
              , HP.style ("width: " <> show (probability * 100.0) <> "%")
              ]
              []
          , HH.span_ [ HH.text (show probability) ]
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
          [ HH.text ("inference error: " <> message) ]

  mnistInferenceInput state =
    Array.replicate 784 state.inkValue

  inferenceAckToDecoded result =
    { kind: "classification"
    , topClass: result.topClass
    , confidence: result.confidence
    , probabilities: result.probabilities
    , labels: []
    , values: []
    , value: 0.0
    , output: result.output
    }

-- | Top-level mount used by `web/src/Main.purs` to attach the component
-- | to the demo page's `<main id="app">` element. The Halogen driver
-- | owns DOM diffing from here on.
mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose

-- | Deterministic textual snapshot of the predicted-class badge for the
-- | Playwright stub to assert against as a pure string.
renderPredictionSnapshot :: Maybe Prediction -> String
renderPredictionSnapshot prediction =
  Maybe.fromMaybe
    "predicted: (none)"
    ( prediction
        # map
            ( \r ->
                "predicted: "
                  <> show r.topClass
                  <> " confidence="
                  <> show r.confidence
            )
    )
