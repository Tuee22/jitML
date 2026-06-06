-- | Training-progress panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each
-- | `/api/ws/training` frame appends to the in-memory frame list;
-- | the render shows the loss curve as a textual table plus the
-- | canvas placeholder a future renderer can draw against.
module Panels.Training where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Chrome.Header as Header
import Panels.Stream (subscribeStream)

type TrainingFrame =
  { panel :: String
  , experimentHash :: String
  , epoch :: Int
  , trainingLoss :: Number
  , validationLoss :: Number
  , timestampNs :: Int
  }

type State =
  { frames :: Array TrainingFrame
  , liveFrames :: Array String
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | FrameReceived TrainingFrame
  | LiveFrame String
  | StreamFailed String

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
      subscribeStream ("/api/ws/" <> "training") LiveFrame
    LiveFrame payload ->
      H.modify_
        ( \s ->
            s
              { liveFrames = Array.take 200 (Array.snoc s.liveFrames payload)
              , lastError = Nothing
              }
        )
    FrameReceived frame ->
      H.modify_
        ( \s ->
            s
              { frames = Array.take 200 (Array.snoc s.frames frame)
              , lastError = Nothing
              }
        )
    StreamFailed message ->
      H.modify_ (_ { lastError = Just message })

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Training progress" ]
      , HH.canvas
          [ HP.id (panelName <> "-curve")
          , HP.width 640
          , HP.height 240
          ]
      , HH.table
          [ HP.id (panelName <> "-table")
          , HP.classes [ H.ClassName "loss-table" ]
          ]
          ( [ HH.tr_
                [ HH.th_ [ HH.text "epoch" ]
                , HH.th_ [ HH.text "train_loss" ]
                , HH.th_ [ HH.text "val_loss" ]
                ]
            ] <> map renderRow state.frames
          )
      , HH.ol
          [ HP.id (panelName <> "-live")
          , HP.classes [ H.ClassName "live-frames" ]
          ]
          (map (\frame -> HH.li_ [ HH.text frame ]) state.liveFrames)
      , renderError state
      ]

  renderRow frame =
    HH.tr_
      [ HH.td_ [ HH.text (show frame.epoch) ]
      , HH.td_ [ HH.text (show frame.trainingLoss) ]
      , HH.td_ [ HH.text (show frame.validationLoss) ]
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

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
