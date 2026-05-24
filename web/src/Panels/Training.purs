-- | Training-progress panel. The Halogen component renders the loss-curve
-- | DOM; the live `/api/ws/training` stream wiring is owned by Phase 13
-- | Sprint 13.13.
module Panels.Training where

import Prelude

import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

type TrainingFrame =
  { panel :: String
  , experimentHash :: String
  , epoch :: Int
  , trainingLoss :: Number
  , validationLoss :: Number
  , timestampNs :: Int
  }

type State = { frames :: Array TrainingFrame }

panelName :: String
panelName = "training-progress"

renderFrame :: String -> Int -> Number -> Number -> Int -> TrainingFrame
renderFrame experimentHash epoch trainingLoss validationLoss timestampNs =
  { panel: panelName
  , experimentHash
  , epoch
  , trainingLoss
  , validationLoss
  , timestampNs
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> { frames: [] }
    , render
    , eval: H.mkEval H.defaultEval
    }
  where
  render _ =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "Training progress" ]
      , HH.canvas
          [ HP.id (panelName <> "-curve")
          , HP.width 640
          , HP.height 240
          ]
      ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
