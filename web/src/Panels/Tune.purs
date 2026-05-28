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
import Effect (Effect)
import Effect.Aff.Class (class MonadAff)
import Halogen as H
import Halogen.Aff (awaitBody, runHalogenAff)
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Panels.Stream (subscribeStream)

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
  , liveFrames :: Array String
  , bestObjective :: Number
  , sweepDone :: Maybe TuneSweepDoneFrame
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | TrialReceived TuneTrialFrame
  | LiveFrame String
  | SweepCompleted TuneSweepDoneFrame
  | StreamFailed String

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

initialState :: State
initialState =
  { trials: []
  , liveFrames: []
  , bestObjective: 0.0
  , sweepDone: Nothing
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
      subscribeStream ("/api/ws/" <> "tune") LiveFrame
    LiveFrame payload ->
      H.modify_
        ( \s ->
            s
              { liveFrames = Array.take 200 (Array.snoc s.liveFrames payload)
              , lastError = Nothing
              }
        )
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
                , lastError = Nothing
                }
        )
    SweepCompleted frame ->
      H.modify_
        ( \s ->
            s
              { sweepDone = Just frame
              , bestObjective = max s.bestObjective frame.bestObjective
              }
        )
    StreamFailed message ->
      H.modify_ (_ { lastError = Just message })

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ HH.h2_ [ HH.text "Hyperparameter sweep" ]
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
      , HH.ol
          [ HP.id (panelName <> "-live")
          , HP.classes [ H.ClassName "live-frames" ]
          ]
          (map (\frame -> HH.li_ [ HH.text frame ]) state.liveFrames)
      , renderSweepDone state
      , renderError state
      ]

  renderTrialRow trial =
    HH.tr_
      [ HH.td_ [ HH.text (show trial.trialIndex) ]
      , HH.td_ [ HH.text (show trial.trialSeed) ]
      , HH.td_ [ HH.text (show trial.objective) ]
      , HH.td_ [ HH.text (if trial.pruned then "yes" else "no") ]
      ]

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
