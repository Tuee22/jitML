-- | RL rollout trajectory panel. The Halogen component renders the
-- | episode/reward log; the live `/api/ws` stream wiring is owned by
-- | Phase 13 Sprint 13.13.
module Panels.Rl where

import Prelude

import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)

type RlStreamFrame =
  { panel :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , reward :: Number
  , done :: Boolean
  , observationHash :: Int
  }

type State = { frames :: Array RlStreamFrame }

panelName :: String
panelName = "rl-trajectory"

renderFrame :: Int -> Int -> Number -> Boolean -> Int -> RlStreamFrame
renderFrame episodeIndex stepIndex reward done observationHash =
  { panel: panelName
  , episodeIndex
  , stepIndex
  , reward
  , done
  , observationHash
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
      [ HH.h2_ [ HH.text "RL trajectory" ]
      , HH.ul [ HP.id (panelName <> "-log") ] []
      ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
