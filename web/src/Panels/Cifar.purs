-- | CIFAR / ImageNet upload-then-inference panel. The Halogen component
-- | owns the panel DOM; the live upload→infer pipeline is owned by Phase
-- | 13 Sprint 13.13.
module Panels.Cifar where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

type CifarUploadRequest =
  { panel :: String
  , imageBase64 :: String
  , datasetName :: String
  }

type CifarInferenceResponse =
  { topK :: Array Int
  , probabilities :: Array Number
  , preprocessingMs :: Number
  , inferenceMs :: Number
  }

type State = { lastResponse :: Maybe CifarInferenceResponse }

panelName :: String
panelName = "cifar-imagenet-upload"

defaultDataset :: String
defaultDataset = "CIFAR-10"

renderUploadRequest :: String -> CifarUploadRequest
renderUploadRequest imageBase64 =
  { panel: panelName
  , imageBase64
  , datasetName: defaultDataset
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> { lastResponse: Nothing }
    , render
    , eval: H.mkEval H.defaultEval
    }
  where
  render _ =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "CIFAR / ImageNet upload" ]
      , HH.input
          [ HP.id (panelName <> "-file")
          , HP.type_ HP.InputFile
          ]
      , HH.button [ HP.id (panelName <> "-submit") ] [ HH.text "Classify" ]
      ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
