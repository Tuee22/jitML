-- | CIFAR / ImageNet upload-then-inference panel.
-- |
-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — asynchronous to the
-- | browser: subscribes to `/api/ws/inference`, publishes the upload request
-- | fire-and-forget, and renders the Engine-decoded `DecodedInference`
-- | (classification: top class + the full probability distribution) matched by
-- | `experiment-hash`. No browser-side ranking/argmax — the Engine decodes.
module Panels.Cifar where

import Prelude

import Data.Array as Array
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
import Chrome.Header as Header
import Panels.Api (requestText)
import Panels.Stream (subscribeStream)

type CifarUploadRequest =
  { panel :: String
  , imageBase64 :: String
  , datasetName :: String
  }

type CifarInferenceResponse = Contracts.DecodedInference

type State =
  { lastResponse :: Maybe CifarInferenceResponse
  , pendingUpload :: Boolean
  , lastError :: Maybe String
  , imageToken :: String
  }

data Action
  = Initialize
  | SelectImageToken String
  | UploadImage
  | UploadAck String
  | FrameText String
  | UploadCompleted CifarInferenceResponse
  | UploadFailed String

panelName :: String
panelName = "cifar-imagenet-upload"

defaultDataset :: String
defaultDataset = "CIFAR-10"

defaultExperimentHash :: String
defaultExperimentHash = "cifar-imagenet"

renderUploadRequest :: String -> CifarUploadRequest
renderUploadRequest imageBase64 =
  { panel: panelName
  , imageBase64
  , datasetName: defaultDataset
  }

initialState :: State
initialState =
  { lastResponse: Nothing
  , pendingUpload: false
  , lastError: Nothing
  , imageToken: ""
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
      subscribeStream "/api/ws/inference" FrameText UploadFailed
    SelectImageToken token ->
      H.modify_ (_ { imageToken = token })
    UploadImage -> do
      state <- H.get
      H.modify_ (_ { pendingUpload = true, lastError = Nothing })
      requestText
        "POST"
        "/api/images"
        (Contracts.renderBrowserImageRequest panelName defaultDataset defaultExperimentHash state.imageToken (cifarInferenceInput state))
        UploadAck
        UploadFailed
    UploadAck payload ->
      case Contracts.parseImageInferenceResult payload of
        Just result | result.datasetName == defaultDataset ->
          handleAction (UploadCompleted (imageAckToDecoded result))
        _ ->
          pure unit
    FrameText payload ->
      case Contracts.fieldValue "experiment-hash" payload of
        Just hash | hash == defaultExperimentHash ->
          case Contracts.parseDecodedInference payload of
            Just decoded -> handleAction (UploadCompleted decoded)
            Nothing -> handleAction (UploadFailed ("unexpected image frame: " <> payload))
        _ ->
          pure unit
    UploadCompleted response ->
      H.modify_
        ( _
            { pendingUpload = false
            , lastResponse = Just response
            , lastError = Nothing
            }
        )
    UploadFailed message ->
      H.modify_
        ( _
            { pendingUpload = false
            , lastError = Just message
            }
        )

  render state =
    HH.div
      [ HP.id panelName, HP.classes [ H.ClassName "jitml-panel" ] ]
      [ Header.render
      , HH.h2_ [ HH.text "CIFAR / ImageNet upload" ]
      , HH.input
          [ HP.id (panelName <> "-file")
          , HP.type_ HP.InputFile
          , HE.onValueInput SelectImageToken
          ]
      , HH.button
          [ HP.id (panelName <> "-submit")
          , HP.disabled state.pendingUpload
          , HE.onClick (\_ -> UploadImage)
          ]
          [ HH.text (if state.pendingUpload then "Classifying…" else "Classify") ]
      , renderResponseList state
      , renderError state
      ]

  renderResponseList state =
    case state.lastResponse of
      Nothing -> HH.div_ []
      Just response ->
        HH.div_
          [ HH.div
              [ HP.id (panelName <> "-top-class") ]
              [ HH.text ("top class " <> show response.topClass) ]
          , HH.ol
              [ HP.id (panelName <> "-topk")
              , HP.classes [ H.ClassName "jitml-topk" ]
              ]
              (renderDistribution response)
          ]

  renderDistribution response =
    let
      pairs =
        Array.mapWithIndex (\classIx prob -> { classIx, prob }) response.probabilities
    in
      map
        ( \pair ->
            HH.li_ [ HH.text (show pair.classIx <> " (" <> show pair.prob <> ")") ]
        )
        pairs

  renderError state =
    case state.lastError of
      Nothing -> HH.div_ []
      Just message ->
        HH.div
          [ HP.id (panelName <> "-error")
          , HP.classes [ H.ClassName "jitml-error" ]
          ]
          [ HH.text ("upload error: " <> message) ]

  cifarInferenceInput state =
    Array.replicate 3072 (if state.imageToken == "" then 0.0 else 1.0)

  imageAckToDecoded result =
    { kind: "classification"
    , topClass: Maybe.fromMaybe 0 (Array.head result.topK)
    , confidence: Maybe.fromMaybe 0.0 (Array.head result.probabilities)
    , probabilities: result.probabilities
    , labels: []
    , values: []
    , value: 0.0
    , output: result.probabilities
    }

mount :: Aff (Aff Unit)
mount = do
  body <- awaitBody
  ui <- runUI component unit body
  pure ui.dispose

renderTopKSnapshot :: Maybe CifarInferenceResponse -> String
renderTopKSnapshot response =
  Maybe.fromMaybe
    "topk: (none)"
    ( response
        # map
            ( \r ->
                "topk: " <> show r.topClass <> " probs=" <> show r.probabilities
            )
    )
