-- | MNIST live-inference panel. Renders an HTML5 canvas the user draws a
-- digit on, posts the digit to `/api/inference`, and animates the daemon's
-- response.
module Panels.Mnist where

import Prelude

import Effect (Effect)

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

-- | Halogen mount point. The Halogen renderer + slot wiring lives in the
-- generated `Main.purs` shell once `purescript-bridge` emits the Halogen
-- contract; this module owns the panel's payload-shape contracts.
mount :: Effect Unit
mount = pure unit
