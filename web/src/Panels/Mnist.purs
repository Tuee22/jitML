-- | MNIST live-inference panel. Renders an HTML5 canvas the user draws a
-- | digit on, posts the digit to `/api/inference`, and animates the daemon's
-- | response. The Halogen component owns the panel DOM; the live wiring to
-- | the daemon's `/api/inference` HTTP endpoint and `/api/ws` WebSocket
-- | stream is owned by Phase 13 Sprint 13.13.
module Panels.Mnist where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

type MnistInferenceRequest =
  { panel :: String
  , canvasPixels :: Array Int
  , modelId :: String
  }

type MnistInferenceResponse =
  { topClass :: Int
  , confidence :: Number
  , latencyMs :: Number
  }

type State = { lastPrediction :: Maybe MnistInferenceResponse }

data Action = NoOp

panelName :: String
panelName = "mnist-live-inference"

defaultModelId :: String
defaultModelId = "mnist-deep-mlp"

emptyCanvas :: Array Int
emptyCanvas = []

renderRequest :: Array Int -> MnistInferenceRequest
renderRequest pixels =
  { panel: panelName
  , canvasPixels: pixels
  , modelId: defaultModelId
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> { lastPrediction: Nothing }
    , render
    , eval: H.mkEval H.defaultEval
    }
  where
  render _ =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "MNIST live inference" ]
      , HH.canvas
          [ HP.id (panelName <> "-canvas")
          , HP.width 280
          , HP.height 280
          ]
      , HH.button [ HP.id (panelName <> "-submit") ] [ HH.text "Predict" ]
      ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
