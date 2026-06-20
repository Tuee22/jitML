-- | Generic tensor-inference panel.
-- |
-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — asynchronous to the
-- | browser: subscribes to `/api/ws/inference`, publishes the request
-- | fire-and-forget, and renders the Engine-decoded `DecodedInference`
-- | (generic output vector) matched by `experiment-hash`.
module Panels.GenericInference where

import Prelude

import Chrome.Header as Header
import Data.Maybe (Maybe(..))
import Data.Maybe as Maybe
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Generated.Contracts as Contracts
import Halogen as H
import Halogen.Aff (awaitBody)
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.VDom.Driver (runUI)
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type GenericInferenceRequest = Contracts.BrowserGenericInferenceRequest

type GenericInferenceResponse = Contracts.DecodedInference

type State =
  { lastResponse :: Maybe GenericInferenceResponse
  , pendingInference :: Boolean
  , lastError :: Maybe String
  }

data Action
  = Initialize
  | RunInference
  | RunAck String
  | FrameText String
  | InferenceReceived GenericInferenceResponse
  | InferenceFailed String

panelName :: String
panelName = "generic-inference-lab"

defaultExperimentHash :: String
defaultExperimentHash = "generic-tensor-demo"

defaultInput :: Array Number
defaultInput = [ 0.25, -0.5, 1.0, 2.0 ]

renderRequest :: Array Number -> GenericInferenceRequest
renderRequest input =
  { panel: panelName
  , experimentHash: defaultExperimentHash
  , input
  }

initialState :: State
initialState =
  { lastResponse: Nothing
  , pendingInference: false
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
      subscribeStream "/api/ws/inference" FrameText InferenceFailed
    RunInference -> do
      H.modify_ (_ { pendingInference = true, lastError = Nothing })
      requestText
        "POST"
        "/api/inference/generic"
        (Contracts.renderBrowserGenericInferenceRequest panelName defaultExperimentHash defaultInput)
        RunAck
        InferenceFailed
    RunAck _ ->
      pure unit
    FrameText payload ->
      case Contracts.fieldValue "experiment-hash" payload of
        Just hash | hash == defaultExperimentHash ->
          case Contracts.parseDecodedInference payload of
            Just decoded -> handleAction (InferenceReceived decoded)
            Nothing -> handleAction (InferenceFailed ("unexpected generic inference frame: " <> payload))
        _ ->
          pure unit
    InferenceReceived response ->
      H.modify_
        ( _
            { pendingInference = false
            , lastResponse = Just response
            , lastError = Nothing
            }
        )
    InferenceFailed message ->
      H.modify_
        ( _
            { pendingInference = false
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Generic tensor inference" ]
      , HH.div
          [ HP.id (panelName <> "-input") ]
          [ HH.text ("input " <> show defaultInput) ]
      , HH.button
          [ HP.id (panelName <> "-submit")
          , HP.disabled state.pendingInference
          , HE.onClick (\_ -> RunInference)
          ]
          [ HH.text (if state.pendingInference then "Running..." else "Run inference") ]
      , renderResult state
      , renderError state
      ]

  renderResult state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.div
          [ HP.id (panelName <> "-result")
          , HP.classes [ H.ClassName "jitml-inference-result" ]
          ]
          [ HH.div_ [ HH.text ("kind " <> response.kind) ]
          , HH.ol
              [ HP.id (panelName <> "-output")
              , HP.classes [ H.ClassName "jitml-distribution" ]
              ]
              (map renderOutputValue response.output)
          ]

  renderOutputValue value =
    HH.li_ [ HH.text (show value) ]

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("generic inference error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose

renderOutputSnapshot :: Maybe GenericInferenceResponse -> String
renderOutputSnapshot response =
  Maybe.fromMaybe
    "generic-output: (none)"
    ( response
        # map
            ( \r ->
                "generic-output: " <> show r.output <> " kind=" <> r.kind
            )
    )
