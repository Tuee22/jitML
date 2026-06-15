-- | RL rollout trajectory panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery. Each
-- | `/api/ws/rl` frame the daemon publishes lands through
-- | 'FrameReceived' and appends to the in-memory frame list; the
-- | render shows the most-recent frames as `<li>` entries.
module Panels.Rl where

import Prelude

import Data.Array as Array
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Number as Number
import Data.String as String
import Data.String.Pattern (Pattern(..))
import Data.Traversable (traverse)
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
import Panels.Stream (subscribeStream)

type RlStreamFrame = Contracts.RlAnimationFrame

type State =
  { frames :: Array RlStreamFrame
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | FrameText String
  | FrameReceived RlStreamFrame
  | StreamFailed String
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

initialState :: State
initialState = { frames: [], lastError: Nothing }

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
      case parseRlFrame payload of
        Just frame ->
          handleAction (FrameReceived frame)
        Nothing ->
          handleAction (StreamFailed ("unexpected rl frame: " <> payload))
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
      [ Header.render
      , HH.h2_ [ HH.text "RL trajectory" ]
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
      , renderError state
      ]

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

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("stream error: " <> message) ]

parseRlFrame :: String -> Maybe RlStreamFrame
parseRlFrame payload
  | fieldValue "kind" payload == Just "RlAnimationFrame" =
      Contracts.renderRlAnimationFrame
        <$> fieldValue "experiment-hash" payload
        <*> fieldValue "environment" payload
        <*> intField "episode" payload
        <*> intField "step" payload
        <*> numberField "reward" payload
        <*> boolField "done" payload
        <*> intField "action" payload
        <*> numberListField "observation" payload
        <*> numberListField "action-probabilities" payload
        <*> fieldValue "observation-hash" payload
        <*> fieldValue "replay-cursor" payload
        <*> fieldValue "timestamp-ns" payload
  | otherwise = Nothing

fieldValue :: String -> String -> Maybe String
fieldValue key payload =
  Array.head
    ( Array.mapMaybe
        (String.stripPrefix (Pattern (key <> ": ")) <<< String.trim)
        (String.split (Pattern "\n") payload)
    )

intField :: String -> String -> Maybe Int
intField key payload =
  fieldValue key payload >>= Int.fromString

numberField :: String -> String -> Maybe Number
numberField key payload =
  fieldValue key payload >>= Number.fromString

numberListField :: String -> String -> Maybe (Array Number)
numberListField key payload =
  case fieldValue key payload of
    Just raw | String.trim raw == "" -> Just []
    Just raw -> traverse Number.fromString (String.split (Pattern ",") raw)
    Nothing -> Nothing

boolField :: String -> String -> Maybe Boolean
boolField key payload =
  case fieldValue key payload of
    Just "True" -> Just true
    Just "False" -> Just false
    Just "true" -> Just true
    Just "false" -> Just false
    _ -> Nothing

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose
