module Panels.CheckpointCompare where

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

type CheckpointCompareRequest = Contracts.BrowserCheckpointCompareRequest

type CheckpointCompareResponse = Contracts.CheckpointCompareResult

type State =
  { lastResponse :: Maybe CheckpointCompareResponse
  , pendingCompare :: Boolean
  , lastError :: Maybe String
  }

data Action
  = CompareCheckpoints
  | CompareText String
  | CompareReceived CheckpointCompareResponse
  | CompareFailed String

panelName :: String
panelName = "checkpoint-compare-lab"

defaultBaselineExperimentHash :: String
defaultBaselineExperimentHash = "generic-tensor-demo"

defaultCandidateExperimentHash :: String
defaultCandidateExperimentHash = "generic-tensor-demo-candidate"

defaultInput :: Array Number
defaultInput = [ 0.25, -0.5, 1.0, 2.0 ]

renderRequest :: Array Number -> CheckpointCompareRequest
renderRequest input =
  { panel: panelName
  , baselineExperimentHash: defaultBaselineExperimentHash
  , candidateExperimentHash: defaultCandidateExperimentHash
  , input
  }

initialState :: State
initialState =
  { lastResponse: Nothing
  , pendingCompare: false
  , lastError: Nothing
  }

component :: forall query input output m. MonadAff m => H.Component query input output m
component =
  H.mkComponent
    { initialState: \_ -> initialState
    , render
    , eval: H.mkEval H.defaultEval { handleAction = handleAction }
    }
  where
  handleAction = case _ of
    CompareCheckpoints -> do
      H.modify_ (_ { pendingCompare = true, lastError = Nothing })
      requestText
        "POST"
        "/api/checkpoints/compare"
        ( Contracts.renderBrowserCheckpointCompareRequest
            panelName
            defaultBaselineExperimentHash
            defaultCandidateExperimentHash
            defaultInput
        )
        CompareText
        CompareFailed
    CompareText payload ->
      case Contracts.parseCheckpointCompareResult payload of
        Just response ->
          handleAction (CompareReceived response)
        Nothing ->
          handleAction (CompareFailed ("unexpected checkpoint compare response: " <> payload))
    CompareReceived response ->
      H.modify_
        ( _
            { pendingCompare = false
            , lastResponse = Just response
            , lastError = Nothing
            }
        )
    CompareFailed message ->
      H.modify_
        ( _
            { pendingCompare = false
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "Checkpoint comparison" ]
      , HH.div
          [ HP.id (panelName <> "-inputs") ]
          [ HH.text
              ( defaultBaselineExperimentHash
                  <> " vs "
                  <> defaultCandidateExperimentHash
                  <> " on "
                  <> show defaultInput
              )
          ]
      , HH.button
          [ HP.id (panelName <> "-submit")
          , HP.disabled state.pendingCompare
          , HE.onClick (\_ -> CompareCheckpoints)
          ]
          [ HH.text (if state.pendingCompare then "Comparing..." else "Compare") ]
      , renderResult state
      , renderError state
      ]

  renderResult state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.div
          [ HP.id (panelName <> "-result")
          , HP.classes [ H.ClassName "jitml-compare-result" ]
          ]
          [ HH.div_ [ HH.text ("baseline " <> response.baselineCheckpointSha) ]
          , HH.div_ [ HH.text ("candidate " <> response.candidateCheckpointSha) ]
          , HH.div_ [ HH.text ("max delta " <> show response.maxAbsDelta) ]
          , HH.div_ [ HH.text ("mean delta " <> show response.meanAbsDelta) ]
          , HH.div_ [ HH.text ("latency " <> show response.latencyMs <> " ms") ]
          , HH.ol
              [ HP.id (panelName <> "-baseline-output")
              , HP.classes [ H.ClassName "jitml-distribution" ]
              ]
              (map renderOutputValue response.baselineOutput)
          , HH.ol
              [ HP.id (panelName <> "-candidate-output")
              , HP.classes [ H.ClassName "jitml-distribution" ]
              ]
              (map renderOutputValue response.candidateOutput)
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
          [ HH.text ("checkpoint compare error: " <> message) ]

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose

renderCompareSnapshot :: Maybe CheckpointCompareResponse -> String
renderCompareSnapshot response =
  Maybe.fromMaybe
    "checkpoint-compare: (none)"
    ( response
        # map
            ( \r ->
                "checkpoint-compare: max="
                  <> show r.maxAbsDelta
                  <> " mean="
                  <> show r.meanAbsDelta
            )
    )
