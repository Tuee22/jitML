-- | RL rollout trajectory panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each
-- | `/api/ws/rl` frame the daemon publishes lands through
-- | 'FrameReceived' and appends to the in-memory frame list; the
-- | render shows the most-recent frames as `<li>` entries.
module Panels.Rl where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
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

type RlStreamFrame = Contracts.RlAnimationFrame

type RlReplayFrame = Contracts.RlReplayFrame

type WorkflowStatus = Contracts.WorkflowStatus

type State =
  { frames :: Array RlStreamFrame
  , replayFrames :: Array RlReplayFrame
  , replayIndex :: Int
  , commandStatus :: Maybe WorkflowStatus
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | FrameText String
  | FrameReceived RlStreamFrame
  | ReplayReceived RlReplayFrame
  | StreamFailed String
  | SendCommand String
  | CommandText String
  | StepReplay Int
  | ClearFrames

panelName :: String
panelName = "rl-trajectory"

renderFrame :: Int -> Int -> Number -> Boolean -> String -> RlStreamFrame
renderFrame episodeIndex stepIndex reward done observationHash =
  Contracts.renderRlAnimationFrame
    "live"
    "cartpole"
    episodeIndex
    stepIndex
    reward
    done
    0
    []
    []
    observationHash
    "0"
    "0"

workflowStatus :: String -> String -> WorkflowStatus
workflowStatus status detail =
  Contracts.renderWorkflowStatus panelName "rl-demo" status detail

initialState :: State
initialState =
  { frames: []
  , replayFrames: []
  , replayIndex: 0
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
      -- Sprint 13.13 — open the held-open `/api/ws/rl` bridge; each
      -- broker frame the daemon publishes is parsed into a typed frame.
      subscribeStream ("/api/ws/" <> "rl") FrameText StreamFailed
    FrameText payload ->
      case Contracts.parseRlAnimationFrame payload of
        Just frame ->
          handleAction (FrameReceived frame)
        Nothing ->
          case Contracts.parseRlReplayFrame payload of
            Just frame ->
              handleAction (ReplayReceived frame)
            Nothing ->
              handleAction (StreamFailed ("unexpected rl frame: " <> payload))
    FrameReceived frame ->
      -- Keep the last 200 frames so the DOM diff bounded; older
      -- frames roll off the head.
      H.modify_
        ( \s ->
            s
              { frames = Array.take 200 (Array.snoc s.frames frame)
              , commandStatus =
                  Just
                    ( workflowStatus
                        (if frame.done then "done" else "running")
                        ("episode " <> show frame.episodeIndex <> " step " <> show frame.stepIndex)
                    )
              , lastError = Nothing
              }
        )
    ReplayReceived frame ->
      H.modify_
        ( \s ->
            let
              nextReplayFrames = Array.take 200 (Array.snoc s.replayFrames frame)
            in
              s
                { replayFrames = nextReplayFrames
                , replayIndex = max 0 (Array.length nextReplayFrames - 1)
                , commandStatus = Just (workflowStatus "running" ("replay " <> frame.replayId))
                , lastError = Nothing
                }
        )
    StreamFailed message ->
      H.modify_ (_ { commandStatus = Just (workflowStatus "failed" message), lastError = Just message })
    SendCommand command -> do
      H.modify_ (_ { commandStatus = Just (workflowStatus "queued" ("sending " <> command)), lastError = Nothing })
      requestText "POST" "/api/runs/rl-demo/command" (commandPayload command) CommandText StreamFailed
    CommandText payload ->
      case Contracts.parseWorkflowCommandAck payload of
        Just ack ->
          H.modify_ (_ { commandStatus = Just (workflowStatus "queued" (ack.command <> " " <> ack.status)), lastError = Nothing })
        Nothing ->
          H.modify_ (_ { commandStatus = Just (workflowStatus "failed" ("unexpected command response: " <> payload)), lastError = Nothing })
    StepReplay delta ->
      H.modify_
        ( \s ->
            let
              upper = max 0 (Array.length s.replayFrames - 1)
              nextIndex = min upper (max 0 (s.replayIndex + delta))
            in
              s { replayIndex = nextIndex }
        )
    ClearFrames ->
      H.put initialState

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "RL trajectory" ]
      , renderControls
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
      , renderAnimation state
      , renderPolicy state
      , renderReplay state
      , renderCommandStatus state
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
        Contracts.renderStartRlCommand "rl-demo" "ppo" "cartpole" 1 128 4
      _ ->
        Contracts.renderStopRlCommand "rl-demo" true

  renderEpisodeFrame frame =
    HH.li_
      [ HH.text
          ( "ep="
              <> show frame.episodeIndex
              <> " step="
              <> show frame.stepIndex
              <> " action="
              <> show frame.action
              <> " reward="
              <> show frame.reward
              <> (if frame.done then " (done)" else "")
          )
      ]

  renderPolicy state =
    case Array.last state.frames of
      Nothing -> HH.div_ []
      Just frame ->
        HH.div
          [ HP.id (panelName <> "-policy")
          , HP.classes [ H.ClassName "policy-bars" ]
          ]
          (map renderPolicyBar frame.actionProbabilities)

  renderPolicyBar probability =
    HH.div
      [ HP.classes [ H.ClassName "policy-bar" ] ]
      [ HH.div
          [ HP.classes [ H.ClassName "policy-bar-fill" ]
          , HP.style ("width: " <> show (probability * 100.0) <> "%")
          ]
          []
      , HH.span_ [ HH.text (show probability) ]
      ]

  -- Live environment animation. Drives a CSS-transform scene from the
  -- most-recent typed `RlAnimationFrame.observation`: a cart-pole render
  -- for cartpole environments, a per-dimension observation strip for
  -- every other environment, plus a recent-reward sparkline. Pure
  -- HTML+CSS so it needs no canvas/svg dependency; the inline `style`
  -- bindings mirror the existing policy/loss bar idiom.
  degreesPerRadian :: Number
  degreesPerRadian = 57.29577951308232

  clampPercent :: Number -> Number
  clampPercent value = max 0.0 (min 100.0 value)

  renderAnimation state =
    case Array.last state.frames of
      Nothing -> HH.div_ []
      Just frame ->
        HH.div
          [ HP.id (panelName <> "-animation")
          , HP.classes [ H.ClassName "rl-animation" ]
          ]
          [ renderScene frame
          , renderObservationStrip frame
          , renderRewardSparkline state.frames
          ]

  renderScene frame =
    if frame.environment == "cartpole" then
      let
        cartPosition = fromMaybe 0.0 (Array.index frame.observation 0)
        poleAngle = fromMaybe 0.0 (Array.index frame.observation 2)
        cartLeftPercent = clampPercent (50.0 + (cartPosition / 2.4) * 40.0)
        poleDegrees = poleAngle * degreesPerRadian
      in
        HH.div
          [ HP.id (panelName <> "-scene")
          , HP.classes [ H.ClassName "rl-scene", H.ClassName "rl-scene-cartpole" ]
          ]
          [ HH.div [ HP.classes [ H.ClassName "rl-track" ] ] []
          , HH.div
              [ HP.classes [ H.ClassName "rl-cart" ]
              , HP.style ("left: " <> show cartLeftPercent <> "%")
              ]
              [ HH.div
                  [ HP.classes [ H.ClassName "rl-pole" ]
                  , HP.style ("transform: rotate(" <> show poleDegrees <> "deg)")
                  ]
                  []
              ]
          ]
    else
      HH.div
        [ HP.id (panelName <> "-scene")
        , HP.classes [ H.ClassName "rl-scene", H.ClassName "rl-scene-generic" ]
        ]
        [ HH.div_ [ HH.text ("environment: " <> frame.environment) ] ]

  renderObservationStrip frame =
    HH.div
      [ HP.id (panelName <> "-observation-strip")
      , HP.classes [ H.ClassName "rl-observation-strip" ]
      ]
      (Array.mapWithIndex renderObservationBar frame.observation)

  renderObservationBar index value =
    HH.div
      [ HP.classes [ H.ClassName "rl-observation-bar" ] ]
      [ HH.div
          [ HP.classes [ H.ClassName "rl-observation-bar-fill" ]
          , HP.style ("height: " <> show (clampPercent (50.0 + value * 25.0)) <> "%")
          ]
          []
      , HH.span_ [ HH.text ("x" <> show index) ]
      ]

  renderRewardSparkline frames =
    HH.div
      [ HP.id (panelName <> "-reward-sparkline")
      , HP.classes [ H.ClassName "rl-reward-sparkline" ]
      ]
      (map renderRewardBar (Array.takeEnd 40 frames))

  renderRewardBar frame =
    HH.div
      [ HP.classes [ H.ClassName "rl-reward-bar" ]
      , HP.style ("height: " <> show (clampPercent (frame.reward * 10.0)) <> "%")
      ]
      []

  renderReplay state =
    case Array.index state.replayFrames state.replayIndex of
      Nothing -> HH.div_ []
      Just frame ->
        HH.div
          [ HP.id (panelName <> "-replay")
          , HP.classes [ H.ClassName "rl-replay" ]
          ]
          [ HH.div
              [ HP.id (panelName <> "-replay-controls")
              , HP.classes [ H.ClassName "replay-controls" ]
              ]
              [ HH.button
                  [ HP.id (panelName <> "-replay-prev")
                  , HP.disabled (state.replayIndex <= 0)
                  , HE.onClick (\_ -> StepReplay (-1))
                  ]
                  [ HH.text "prev" ]
              , HH.button
                  [ HP.id (panelName <> "-replay-next")
                  , HP.disabled (state.replayIndex + 1 >= Array.length state.replayFrames)
                  , HE.onClick (\_ -> StepReplay 1)
                  ]
                  [ HH.text "next" ]
              , HH.span_
                  [ HH.text
                      ( show (state.replayIndex + 1)
                          <> "/"
                          <> show (Array.length state.replayFrames)
                      )
                  ]
              ]
          , HH.div_ [ HH.text ("replay: " <> frame.replayId) ]
          , HH.div_ [ HH.text ("policy version: " <> frame.policyVersion) ]
          , HH.div_
              [ HH.text
                  ( "ep="
                      <> show frame.episodeIndex
                      <> " step="
                      <> show frame.stepIndex
                      <> " action="
                      <> show frame.action
                      <> " reward="
                      <> show frame.reward
                  )
              ]
          , HH.div_ [ HH.text ("observation hash: " <> frame.observationHash) ]
          , HH.ol
              [ HP.id (panelName <> "-replay-observation") ]
              (map renderObservationValue frame.observation)
          ]

  renderObservationValue value =
    HH.li_ [ HH.text (show value) ]

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
