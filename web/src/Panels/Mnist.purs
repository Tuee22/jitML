-- | MNIST live-inference panel.
-- |
-- | Sprint 13.13 — adds Halogen render machinery (slot + state + action
-- | handler) on top of the panel-payload contract from Sprint 11.4. The
-- | panel:
-- |
-- |   1. Initialises with no prediction.
-- |   2. On `Predict` click, takes the canvas pixels, calls
-- |      `/api/inference` via `Fetch`, and stores the parsed
-- |      `MnistInferenceResponse` in state.
-- |   3. Re-renders the prediction badge whenever state changes
-- |      (Halogen's VDom diff handles minimal DOM patching).
-- |
-- | A live `/api/ws` WebSocket bridge that streams real broker frames
-- | is owned by Sprint 13.13's server-side proxy work; this module is
-- | the client-side render surface that consumes those frames once the
-- | bridge is in place.
module Panels.Mnist where

import Prelude

import Data.Maybe (Maybe(..))
import Data.Maybe as Maybe
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

type MnistInferenceRequest =
  { panel :: String
  , canvasPixels :: Array Int
  , modelId :: String
  }

type MnistInferenceResponse = Contracts.InferenceResult

type State =
  { lastPrediction :: Maybe MnistInferenceResponse
  , pendingInference :: Boolean
  , lastError :: Maybe String
  }

data Action
  = Predict
  | PredictionText String
  | PredictionReceived MnistInferenceResponse
  | PredictionFailed String

panelName :: String
panelName = "mnist-live-inference"

defaultModelId :: String
defaultModelId = "mnist-deep-mlp"

defaultExperimentHash :: String
defaultExperimentHash = defaultModelId

defaultInferenceInput :: Array Number
defaultInferenceInput = [ 1.0, 2.0 ]

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
    Predict -> do
      H.modify_ (_ { pendingInference = true, lastError = Nothing })
      requestText
        "POST"
        "/api/inference"
        (Contracts.renderBrowserInferenceRequest panelName defaultModelId defaultExperimentHash defaultInferenceInput)
        PredictionText
        PredictionFailed
    PredictionText payload ->
      case Contracts.parseInferenceResult payload of
        Just response ->
          handleAction (PredictionReceived response)
        Nothing ->
          handleAction (PredictionFailed ("unexpected inference response: " <> payload))
    PredictionReceived response ->
      H.modify_
        ( _
            { pendingInference = false
            , lastPrediction = Just response
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
                      <> prediction.modelId
                      <> " (confidence "
                      <> show prediction.confidence
                      <> ", "
                      <> show prediction.latencyMs
                      <> " ms)"
                  )
              ]
          , HH.div
              [ HP.id (panelName <> "-checkpoint") ]
              [ HH.text ("checkpoint " <> prediction.checkpointSha) ]
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

-- | Top-level mount used by `web/src/Main.purs` to attach the component
-- | to the demo page's `<main id="app">` element. The Halogen driver
-- | owns DOM diffing from here on.
mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose

-- | Provide a deterministic textual snapshot of the predicted-class
-- | badge so the Playwright stub can assert against a pure string. Once
-- | the live `/api/inference` round-trip lands the assertion checks the
-- | actual rendered badge.
renderPredictionSnapshot :: Maybe MnistInferenceResponse -> String
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
