{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.AppleInferenceRpc
  ( AppleInferenceRpcPlan (..)
  , appleInferenceRpcPlan
  , correlateAppleInferenceEvent
  , publishAppleInferenceRpcCommand
  , renderAppleInferenceRpcPlan
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Proto.Inference
  ( AppleInferenceCommand (..)
  , AppleInferenceCommandKind (..)
  , AppleInferenceEvent (..)
  , AppleInferenceEventKind (..)
  , InferenceRequest (..)
  , appleInferenceCommandTopic
  , appleInferenceEventTopic
  , renderAppleInferenceCommand
  , renderInferenceInput
  )
import JitML.Service.Capabilities
  ( HasPulsar (..)
  , TopicName (..)
  )
import JitML.Service.Retry (ServiceError)

data AppleInferenceRpcPlan = AppleInferenceRpcPlan
  { appleRpcCommandTopic :: TopicName
  , appleRpcEventTopic :: TopicName
  , appleRpcClientReplyTopic :: TopicName
  , appleRpcCommand :: AppleInferenceCommand
  , appleRpcCommandPayload :: Text
  }
  deriving stock (Eq, Show)

appleInferenceRpcPlan :: Text -> InferenceRequest -> AppleInferenceRpcPlan
appleInferenceRpcPlan startingSnapshot request =
  AppleInferenceRpcPlan
    { appleRpcCommandTopic = TopicName appleInferenceCommandTopic
    , appleRpcEventTopic = TopicName appleInferenceEventTopic
    , appleRpcClientReplyTopic = TopicName (irReplyTopic request)
    , appleRpcCommand = command
    , appleRpcCommandPayload = renderAppleInferenceCommand command
    }
 where
  command =
    AppleInferenceCommand
      { appleCommandCallId = irCallId request
      , appleCommandKind = AppleCommandInference
      , appleCommandModelId = irExperimentHash request
      , appleCommandStartingSnapshot = startingSnapshot
      , appleCommandReplyTopic = appleInferenceEventTopic
      , appleCommandInputs = renderInferenceInput (irInput request)
      }

publishAppleInferenceRpcCommand
  :: (HasPulsar m)
  => AppleInferenceRpcPlan
  -> m (Either ServiceError Text)
publishAppleInferenceRpcCommand plan =
  pulsarPublish (appleRpcCommandTopic plan) (appleRpcCommandPayload plan)

correlateAppleInferenceEvent
  :: AppleInferenceCommand
  -> AppleInferenceEvent
  -> Either Text [Text]
correlateAppleInferenceEvent command event
  | appleEventCallId event /= appleCommandCallId command =
      Left
        ( "apple inference event call-id mismatch: expected "
            <> appleCommandCallId command
            <> ", got "
            <> appleEventCallId event
        )
  | otherwise =
      case appleEventKind event of
        AppleEventCompleted ->
          Right (appleEventOutputRefs event)
        AppleEventError ->
          Left
            ( "apple inference event error"
                <> renderErrorCode (appleEventErrorCode event)
                <> renderErrorMessage (appleEventMessage event)
            )

renderAppleInferenceRpcPlan :: AppleInferenceRpcPlan -> Text
renderAppleInferenceRpcPlan plan =
  Text.unlines
    [ "apple_inference_rpc:"
    , "  command_topic: " <> unTopicName (appleRpcCommandTopic plan)
    , "  event_topic: " <> unTopicName (appleRpcEventTopic plan)
    , "  client_reply_topic: " <> unTopicName (appleRpcClientReplyTopic plan)
    , "  call_id: " <> appleCommandCallId (appleRpcCommand plan)
    , "  model_id: " <> appleCommandModelId (appleRpcCommand plan)
    , "  starting_snapshot: " <> appleCommandStartingSnapshot (appleRpcCommand plan)
    ]

renderErrorCode :: Maybe Text -> Text
renderErrorCode Nothing = ""
renderErrorCode (Just code) = " " <> code

renderErrorMessage :: Maybe Text -> Text
renderErrorMessage Nothing = ""
renderErrorMessage (Just message) = ": " <> message
