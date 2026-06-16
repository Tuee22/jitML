-- | Hyperparameter-sweep panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each
-- | `/api/ws/tune` 'TrialStarted' / 'TrialFinished' / 'SweepDone'
-- | frame lands through 'TrialReceived' / 'SweepCompleted'; render
-- | walks the trial list as a `<table>` and surfaces the best
-- | objective the daemon has reported so far.
module Panels.Tune where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Generated.Contracts as Contracts
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Chrome.Header as Header
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type TuneTrialFrame = Contracts.TuneTrialFrame

type TuneSweepDoneFrame = Contracts.TuneSweepDoneFrame

type WorkflowStatus = Contracts.WorkflowStatus

type State =
  { trials :: Array TuneTrialFrame
  , bestObjective :: Number
  , sweepDone :: Maybe TuneSweepDoneFrame
  , commandStatus :: Maybe WorkflowStatus
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | TrialText String
  | TrialReceived TuneTrialFrame
  | SweepCompleted TuneSweepDoneFrame
  | SendCommand String
  | CommandText String
  | StreamFailed String

panelName :: String
panelName = "hyperparameter-sweep"

renderTrialFrame :: Int -> Int -> Number -> Boolean -> String -> TuneTrialFrame
renderTrialFrame trialIndex trialSeed objective pruned parametersJson =
  Contracts.renderTuneTrialFrame
    "local-sweep"
    trialIndex
    trialSeed
    objective
    pruned
    "TPE"
    "median"
    "none"
    parametersJson
    ""

workflowStatus :: String -> String -> WorkflowStatus
workflowStatus status detail =
  Contracts.renderWorkflowStatus panelName "tune-demo" status detail

initialState :: State
initialState =
  { trials: []
  , bestObjective: 0.0
  , sweepDone: Nothing
  , commandStatus: Nothing
  , lastError: Nothing
  }

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
      subscribeStream ("/api/ws/" <> "tune") TrialText StreamFailed
    TrialText payload ->
      case Contracts.parseTuneTrialFrame payload of
        Just trial ->
          handleAction (TrialReceived trial)
        Nothing ->
          case Contracts.parseTuneSweepDoneFrame payload of
            Just done ->
              handleAction (SweepCompleted done)
            Nothing ->
              handleAction (StreamFailed ("unexpected tune frame: " <> payload))
    TrialReceived trial ->
      H.modify_
        ( \s ->
            let
              nextTrials = Array.take 200 (Array.snoc s.trials trial)
              nextBest = foldl max s.bestObjective (map _.objective nextTrials)
            in
              s
                { trials = nextTrials
                , bestObjective = nextBest
                , commandStatus = Just (workflowStatus "running" ("trial " <> show trial.trialIndex))
                , lastError = Nothing
                }
        )
    SweepCompleted frame ->
      H.modify_
        ( \s ->
            s
              { sweepDone = Just frame
              , bestObjective = max s.bestObjective frame.bestObjective
              , commandStatus = Just (workflowStatus "done" ("completed " <> show frame.trialsCompleted <> " trials"))
              }
        )
    SendCommand command -> do
      H.modify_ (_ { commandStatus = Just (workflowStatus "queued" ("sending " <> command)), lastError = Nothing })
      requestText "POST" "/api/runs/tune-demo/command" (commandPayload command) CommandText StreamFailed
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
      , HH.h2_ [ HH.text "Hyperparameter sweep" ]
      , renderControls
      , renderFrontier state.trials
      , HH.table
          [ HP.id (panelName <> "-trials")
          , HP.classes [ H.ClassName "trials" ]
          ]
          ( [ HH.tr_
                [ HH.th_ [ HH.text "trial" ]
                , HH.th_ [ HH.text "seed" ]
                , HH.th_ [ HH.text "objective" ]
                , HH.th_ [ HH.text "pruned" ]
                ]
            ] <> map renderTrialRow state.trials
          )
      , HH.div
          [ HP.id (panelName <> "-best") ]
          [ HH.text ("best objective: " <> show state.bestObjective) ]
      , renderCommandStatus state
      , renderSweepDone state
      , renderError state
      ]

  renderControls =
    HH.div
      [ HP.id (panelName <> "-controls")
      , HP.classes [ H.ClassName "workflow-controls" ]
      ]
      (map commandButton [ "start", "stop" ])

  commandButton command =
    HH.button
      [ HP.id (panelName <> "-command-" <> command)
      , HE.onClick (\_ -> SendCommand command)
      ]
      [ HH.text command ]

  commandPayload command =
    case command of
      "start" ->
        Contracts.renderStartTuneCommand "tune-demo" "experiments/mnist-tune.dhall" 1 8 100 "TPE" "median" "none"
      _ ->
        Contracts.renderStopTuneCommand "tune-demo"

  renderFrontier trials =
    HH.div
      [ HP.id (panelName <> "-heatmap")
      , HP.classes [ H.ClassName "trial-heatmap" ]
      ]
      (map renderTrialCell trials)

  renderTrialCell trial =
    HH.div
      [ HP.classes [ H.ClassName "trial-cell" ]
      , HP.style ("opacity: " <> show (0.2 + trial.objective))
      ]
      [ HH.text (show trial.trialIndex) ]

  renderTrialRow trial =
    HH.tr_
      [ HH.td_ [ HH.text (show trial.trialIndex) ]
      , HH.td_ [ HH.text (show trial.trialSeed) ]
      , HH.td_ [ HH.text (show trial.objective) ]
      , HH.td_ [ HH.text (if trial.pruned then "yes" else "no") ]
      ]

  renderCommandStatus state =
    case state.commandStatus of
      Nothing -> HH.div_ []
      Just status ->
        HH.div
          [ HP.id (panelName <> "-command-status") ]
          [ HH.text (status.status <> ": " <> status.detail) ]

  renderSweepDone state =
    case state.sweepDone of
      Nothing -> HH.div_ []
      Just frame ->
        HH.div
          [ HP.id (panelName <> "-summary")
          , HP.classes [ H.ClassName "sweep-summary" ]
          ]
          [ HH.text
              ( "sweep done: completed="
                  <> show frame.trialsCompleted
                  <> " pruned="
                  <> show frame.trialsPruned
                  <> " promoted="
                  <> frame.promotedCheckpointSha
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

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
