{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.AppleInferenceRpc
  ( AppleInferenceRpcPlan (..)
  , appleInferenceRpcPlan
  , correlateAppleInferenceEvent
  , handleAppleInferenceCommand
  , publishAppleInferenceEvent
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
  , renderAppleInferenceEvent
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

-- | Sprint 14.4 — host-native side of the RPC. Given a runner that executes the
-- command's inference on Metal and stages its outputs (returning the MinIO output
-- references, or an error), build the `AppleInferenceEvent` reply. A successful
-- run yields an `AppleEventCompleted` carrying the output refs; a failure yields
-- an `AppleEventError` with the message. The reply always echoes the command's
-- `call-id` so the cluster side can correlate it.
handleAppleInferenceCommand
  :: (Monad m)
  => (AppleInferenceCommand -> m (Either Text [Text]))
  -> AppleInferenceCommand
  -> m AppleInferenceEvent
handleAppleInferenceCommand runCommand command = do
  outcome <- runCommand command
  pure $
    case outcome of
      Right outputRefs ->
        AppleInferenceEvent
          { appleEventCallId = appleCommandCallId command
          , appleEventKind = AppleEventCompleted
          , appleEventOutputRefs = outputRefs
          , appleEventErrorCode = Nothing
          , appleEventMessage = Nothing
          }
      Left err ->
        AppleInferenceEvent
          { appleEventCallId = appleCommandCallId command
          , appleEventKind = AppleEventError
          , appleEventOutputRefs = []
          , appleEventErrorCode = Just "inference-failed"
          , appleEventMessage = Just err
          }

-- | Publish a host-produced `AppleInferenceEvent` reply on
-- `inference.event.apple-silicon` for the cluster daemon to correlate.
publishAppleInferenceEvent
  :: (HasPulsar m)
  => AppleInferenceEvent
  -> m (Either ServiceError Text)
publishAppleInferenceEvent event =
  pulsarPublish (TopicName appleInferenceEventTopic) (renderAppleInferenceEvent event)

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
