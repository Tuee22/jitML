-- | Training-progress panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each
-- | `/api/ws/training` frame appends to the in-memory frame list;
-- | the render shows loss, throughput, checkpoint, TensorBoard, and
-- | device metadata from the typed frame.
module Panels.Training where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Generated.Contracts as Contracts
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML.Events as HE
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Chrome.Header as Header
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type TrainingFrame = Contracts.TrainingEventFrame

type WorkflowStatus = Contracts.WorkflowStatus

type State =
  { frames :: Array TrainingFrame
  , commandStatus :: Maybe WorkflowStatus
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | FrameText String
  | FrameReceived TrainingFrame
  | SendCommand String
  | CommandText String
  | StreamFailed String

panelName :: String
panelName = "training-progress"

renderFrame :: String -> Int -> Number -> Number -> Int -> TrainingFrame
renderFrame experimentHash epoch trainingLoss validationLoss timestampNs =
  Contracts.renderTrainingEventFrame
    experimentHash
    epoch
    epoch
    trainingLoss
    validationLoss
    0.0
    "local"
    ""
    ""
    (show timestampNs)

workflowStatus :: String -> String -> WorkflowStatus
workflowStatus status detail =
  Contracts.renderWorkflowStatus panelName "training-demo" status detail

initialState :: State
initialState = { frames: [], commandStatus: Nothing, lastError: Nothing }

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
      subscribeStream ("/api/ws/" <> "training") FrameText StreamFailed
    FrameText payload ->
      case Contracts.parseTrainingEventFrame payload of
        Just frame ->
          handleAction (FrameReceived frame)
        Nothing ->
          handleAction (StreamFailed ("unexpected training frame: " <> payload))
    FrameReceived frame ->
      H.modify_
        ( \s ->
            s
              { frames = Array.take 200 (Array.snoc s.frames frame)
              , commandStatus = Just (workflowStatus "running" ("epoch " <> show frame.epoch <> " step " <> show frame.step))
              , lastError = Nothing
              }
        )
    SendCommand command -> do
      H.modify_ (_ { commandStatus = Just (workflowStatus "queued" ("sending " <> command)), lastError = Nothing })
      requestText "POST" "/api/runs/training-demo/command" (commandPayload command) CommandText StreamFailed
    CommandText payload ->
      case Contracts.parseWorkflowCommandAck payload of
        Just ack ->
          H.modify_ (_ { commandStatus = Just (workflowStatus "queued" (ack.command <> " " <> ack.status)), lastError = Nothing })
        Nothing ->
          H.modify_ (_ { commandStatus = Just (workflowStatus "failed" ("unexpected command response: " <> payload)), lastError = Nothing })
    StreamFailed message ->
      H.modify_ (_ { commandStatus = Just (workflowStatus "failed" message), lastError = Just message })

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Training progress" ]
      , renderControls
      , renderLossChart state.frames
      , renderLatestMetadata state.frames
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
      , renderCommandStatus state
      , renderError state
      ]

  renderControls =
    HH.div
      [ HP.id (panelName <> "-controls")
      , HP.classes [ H.ClassName "workflow-controls" ]
      ]
      (map commandButton [ "start", "stop", "kill" ])

  commandButton command =
    HH.button
      [ HP.id (panelName <> "-command-" <> command)
      , HE.onClick (\_ -> SendCommand command)
      ]
      [ HH.text command ]

  commandPayload command =
    case command of
      "start" ->
        Contracts.renderStartTrainingCommand "training-demo" "experiments/mnist.dhall" 1 2 32
      "kill" ->
        Contracts.renderStopTrainingCommand "training-demo" false
      _ ->
        Contracts.renderStopTrainingCommand "training-demo" true

  renderLossChart frames =
    HH.div
      [ HP.id (panelName <> "-curve")
      , HP.classes [ H.ClassName "loss-chart" ]
      ]
      (map renderLossBar frames)

  renderLossBar frame =
    HH.div
      [ HP.classes [ H.ClassName "loss-bar" ] ]
      [ HH.div
          [ HP.classes [ H.ClassName "loss-bar-train" ]
          , HP.style ("height: " <> show (frame.trainingLoss * 100.0) <> "%")
          ]
          []
      , HH.div
          [ HP.classes [ H.ClassName "loss-bar-validation" ]
          , HP.style ("height: " <> show (frame.validationLoss * 100.0) <> "%")
          ]
          []
      ]

  renderRow frame =
    HH.tr_
      [ HH.td_ [ HH.text (show frame.epoch) ]
      , HH.td_ [ HH.text (show frame.trainingLoss) ]
      , HH.td_ [ HH.text (show frame.validationLoss) ]
      ]

  renderLatestMetadata frames =
    case Array.last frames of
      Nothing -> HH.div_ []
      Just frame ->
        HH.div
          [ HP.id (panelName <> "-metadata")
          , HP.classes [ H.ClassName "training-metadata" ]
          ]
          [ HH.div_ [ HH.text ("experiment: " <> frame.experimentHash) ]
          , HH.div_ [ HH.text ("step: " <> show frame.step) ]
          , HH.div_ [ HH.text ("throughput: " <> show frame.throughput) ]
          , HH.div_ [ HH.text ("device: " <> frame.device) ]
          , HH.div_ [ HH.text ("checkpoint: " <> frame.checkpointSha) ]
          , renderTensorBoardLink frame.tensorboardUrl
          ]

  renderTensorBoardLink url
    | url == "" = HH.div_ []
    | otherwise =
        HH.a
          [ HP.id (panelName <> "-tensorboard")
          , HP.href url
          ]
          [ HH.text ("tensorboard: " <> url) ]

  renderCommandStatus state =
    case state.commandStatus of
      Nothing -> HH.div_ []
      Just status ->
        HH.div
          [ HP.id (panelName <> "-command-status") ]
          [ HH.text (status.status <> ": " <> status.detail) ]

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
