-- | CIFAR / ImageNet upload-then-inference panel.
-- |
-- | Sprint 13.13 — typed Halogen render machinery following the
-- | 'Panels.Mnist' template:
-- |
-- |   * 'State' carries the last 'CifarInferenceResponse', pending
-- |     flag, and an optional error message.
-- |   * 'Action' covers user 'UploadImage' clicks plus
-- |     server-response landings.
-- |   * 'render' switches on state to display the upload control,
-- |     pending spinner, top-k probability list, and error badge.
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

type CifarUploadRequest =
  { panel :: String
  , imageBase64 :: String
  , datasetName :: String
  }

type CifarInferenceResponse = Contracts.ImageInferenceResult

type State =
  { lastResponse :: Maybe CifarInferenceResponse
  , pendingUpload :: Boolean
  , lastError :: Maybe String
  }

data Action
  = UploadImage
  | UploadText String
  | UploadCompleted CifarInferenceResponse
  | UploadFailed String

panelName :: String
panelName = "cifar-imagenet-upload"

defaultDataset :: String
defaultDataset = "CIFAR-10"

defaultExperimentHash :: String
defaultExperimentHash = "cifar-imagenet"

defaultInferenceInput :: Array Number
defaultInferenceInput = [ 1.0, 2.0 ]

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
    UploadImage -> do
      H.modify_ (_ { pendingUpload = true, lastError = Nothing })
      requestText
        "POST"
        "/api/images"
        (Contracts.renderBrowserImageRequest panelName defaultDataset defaultExperimentHash "" defaultInferenceInput)
        UploadText
        UploadFailed
    UploadText payload ->
      case Contracts.parseImageInferenceResult payload of
        Just response ->
          handleAction (UploadCompleted response)
        Nothing ->
          handleAction (UploadFailed ("unexpected image response: " <> payload))
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
              [ HP.id (panelName <> "-checkpoint") ]
              [ HH.text ("checkpoint " <> response.checkpointSha) ]
          , HH.ol
              [ HP.id (panelName <> "-topk")
              , HP.classes [ H.ClassName "jitml-topk" ]
              ]
              (renderTopK response)
          , HH.div
              [ HP.id (panelName <> "-latency") ]
              [ HH.text
                  ( "preprocess "
                      <> show response.preprocessingMs
                      <> " ms, inference "
                      <> show response.inferenceMs
                      <> " ms"
                  )
              ]
          ]

  renderTopK response =
    let
      pairs =
        Array.zipWith (\classIx prob -> { classIx, prob })
          response.topK
          response.probabilities
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
                "topk: " <> show r.topK <> " probs=" <> show r.probabilities
            )
    )
