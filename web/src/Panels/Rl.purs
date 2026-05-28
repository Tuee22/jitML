-- | RL rollout trajectory panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each
-- | `/api/ws/rl` frame the daemon publishes lands through
-- | 'FrameReceived' and appends to the in-memory frame list; the
-- | render shows the most-recent frames as `<li>` entries.
module Panels.Rl where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Panels.Stream (subscribeStream)

type RlStreamFrame =
  { panel :: String
  , episodeIndex :: Int
  , stepIndex :: Int
  , reward :: Number
  , done :: Boolean
  , observationHash :: Int
  }

type State =
  { frames :: Array RlStreamFrame
  , liveFrames :: Array String
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | FrameReceived RlStreamFrame
  | LiveFrame String
  | StreamFailed String
  | ClearFrames

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

initialState :: State
initialState = { frames: [], liveFrames: [], lastError: Nothing }

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
      -- Sprint 13.13 — open the held-open `/api/ws/rl` bridge; each
      -- broker frame the daemon publishes lands as a `LiveFrame`.
      subscribeStream ("/api/ws/" <> "rl") LiveFrame
    LiveFrame payload ->
      H.modify_
        ( \s ->
            s
              { liveFrames = Array.take 200 (Array.snoc s.liveFrames payload)
              , lastError = Nothing
              }
        )
    FrameReceived frame ->
      -- Keep the last 200 frames so the DOM diff bounded; older
      -- frames roll off the head.
      H.modify_
        ( \s ->
            s
              { frames = Array.take 200 (Array.snoc s.frames frame)
              , lastError = Nothing
              }
        )
    StreamFailed message ->
      H.modify_ (_ { lastError = Just message })
    ClearFrames ->
      H.put initialState

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "RL trajectory" ]
      , HH.button
          [ HP.id (panelName <> "-clear")
          , HE.onClick (\_ -> ClearFrames)
          ]
          [ HH.text "Clear" ]
      , HH.ol
          [ HP.id (panelName <> "-episodes")
          , HP.classes [ H.ClassName "episodes" ]
          ]
          (map renderEpisodeFrame state.frames)
      , HH.ol
          [ HP.id (panelName <> "-live")
          , HP.classes [ H.ClassName "live-frames" ]
          ]
          (map (\frame -> HH.li_ [ HH.text frame ]) state.liveFrames)
      , renderError state
      ]

  renderEpisodeFrame frame =
    HH.li_
      [ HH.text
          ( "ep="
              <> show frame.episodeIndex
              <> " step="
              <> show frame.stepIndex
              <> " reward="
              <> show frame.reward
              <> (if frame.done then " (done)" else "")
          )
      ]

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("stream error: " <> message) ]

mount :: Effect Unit
mount = runHalogenAff do
  body <- awaitBody
  void (runUI component unit body)
