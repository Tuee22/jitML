-- | CIFAR / ImageNet upload-then-inference panel.
module Panels.Cifar where

import Prelude

import Effect (Effect)

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

mount :: Effect Unit
mount = pure unit
