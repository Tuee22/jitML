-- | Hyperparameter-sweep panel. The Halogen component renders the trial
-- | log + best-objective summary; the live `/api/ws/tune` stream wiring
-- | is owned by Phase 13 Sprint 13.13.
module Panels.Tune where

import Prelude

import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

type TuneTrialFrame =
  { panel :: String
  , trialIndex :: Int
  , trialSeed :: Int
  , objective :: Number
  , pruned :: Boolean
  , parametersJson :: String
  }

type TuneSweepDoneFrame =
  { panel :: String
  , trialsCompleted :: Int
  , trialsPruned :: Int
  , bestObjective :: Number
  }

type State =
  { trials :: Array TuneTrialFrame
  , bestObjective :: Number
  }

panelName :: String
panelName = "hyperparameter-sweep"

renderTrialFrame :: Int -> Int -> Number -> Boolean -> String -> TuneTrialFrame
renderTrialFrame trialIndex trialSeed objective pruned parametersJson =
  { panel: panelName
  , trialIndex
  , trialSeed
  , objective
  , pruned
  , parametersJson
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> { trials: [], bestObjective: 0.0 }
    , render
    , eval: H.mkEval H.defaultEval
    }
  where
  render _ =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "Hyperparameter sweep" ]
      , HH.ul [ HP.id (panelName <> "-trials") ] []
      , HH.div
          [ HP.id (panelName <> "-best") ]
          [ HH.text "best objective: --" ]
      ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
