{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Inference
  ( AppleInferenceCommand (..)
  , AppleInferenceCommandKind (..)
  , AppleInferenceEvent (..)
  , AppleInferenceEventKind (..)
  , InferenceRequest (..)
  , InferenceResult (..)
  , appleInferenceCommandTopic
  , appleInferenceEventTopic
  , decodeInferenceRequestProto
  , decodeInferenceResultProto
  , encodeInferenceRequestProto
  , encodeInferenceResultProto
  , inferenceRequestTopic
  , inferenceResultTopic
  , parseAppleInferenceCommand
  , parseAppleInferenceEvent
  , parseInferenceInput
  , parseInferenceRequest
  , renderAppleInferenceCommand
  , renderAppleInferenceEvent
  , renderInferenceInput
  , renderInferenceRequest
  , renderInferenceResult
  )
where

import Data.ByteString (ByteString)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

import JitML.Proto.Wire
  ( decodeMessage
  , encodeMessage
  , fieldDoubles
  , fieldString
  , packedDoubleField
  , stringField
  )
import JitML.Substrate (Substrate, renderSubstrate)

data InferenceRequest = InferenceRequest
  { irCallId :: Text
  , irExperimentHash :: Text
  , irReplyTopic :: Text
  , irInput :: [Double]
  }
  deriving stock (Eq, Show)

data InferenceResult = InferenceResult
  { iresCallId :: Text
  , iresExperimentHash :: Text
  , iresOutput :: [Double]
  }
  deriving stock (Eq, Show)

data AppleInferenceCommandKind
  = AppleCommandTraining
  | AppleCommandInference
  deriving stock (Eq, Show)

data AppleInferenceCommand = AppleInferenceCommand
  { appleCommandCallId :: Text
  , appleCommandKind :: AppleInferenceCommandKind
  , appleCommandModelId :: Text
  , appleCommandStartingSnapshot :: Text
  , appleCommandReplyTopic :: Text
  , appleCommandInputs :: Text
  }
  deriving stock (Eq, Show)

data AppleInferenceEventKind
  = AppleEventCompleted
  | AppleEventError
  deriving stock (Eq, Show)

data AppleInferenceEvent = AppleInferenceEvent
  { appleEventCallId :: Text
  , appleEventKind :: AppleInferenceEventKind
  , appleEventOutputRefs :: [Text]
  , appleEventErrorCode :: Maybe Text
  , appleEventMessage :: Maybe Text
  }
  deriving stock (Eq, Show)

inferenceRequestTopic :: Substrate -> Text
inferenceRequestTopic substrate =
  "inference.request." <> renderSubstrate substrate

inferenceResultTopic :: Substrate -> Text
inferenceResultTopic substrate =
  "inference.result." <> renderSubstrate substrate

appleInferenceCommandTopic :: Text
appleInferenceCommandTopic =
  "inference.command.apple-silicon"

appleInferenceEventTopic :: Text
appleInferenceEventTopic =
  "inference.event.apple-silicon"

renderInferenceRequest :: InferenceRequest -> Text
renderInferenceRequest request =
  Text.unlines
    [ "kind: RunInference"
    , "call-id: " <> irCallId request
    , "experiment-hash: " <> irExperimentHash request
    , "reply-topic: " <> irReplyTopic request
    , "input: " <> renderInferenceInput (irInput request)
    ]

parseInferenceRequest :: Text -> Maybe InferenceRequest
parseInferenceRequest payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "RunInference" <- value "kind"
  inferenceRequestFromFields value

renderAppleInferenceCommand :: AppleInferenceCommand -> Text
renderAppleInferenceCommand command =
  Text.unlines
    [ "envelope: AppleInferenceCommand"
    , "call-id: " <> appleCommandCallId command
    , "kind: " <> renderAppleInferenceCommandKind (appleCommandKind command)
    , "model-id: " <> appleCommandModelId command
    , "starting-snapshot: " <> appleCommandStartingSnapshot command
    , "reply-topic: " <> appleCommandReplyTopic command
    , "inputs: " <> appleCommandInputs command
    ]

parseAppleInferenceCommand :: Text -> Maybe AppleInferenceCommand
parseAppleInferenceCommand payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "AppleInferenceCommand" <- value "envelope"
  AppleInferenceCommand
    <$> value "call-id"
    <*> (value "kind" >>= parseAppleInferenceCommandKind)
    <*> value "model-id"
    <*> value "starting-snapshot"
    <*> value "reply-topic"
    <*> value "inputs"

encodeInferenceRequestProto :: InferenceRequest -> ByteString
encodeInferenceRequestProto request =
  encodeMessage
    [ stringField 1 (irCallId request)
    , stringField 2 (irExperimentHash request)
    , stringField 3 (irReplyTopic request)
    , packedDoubleField 4 (irInput request)
    ]

decodeInferenceRequestProto :: ByteString -> Either Text InferenceRequest
decodeInferenceRequestProto bytes = do
  fields <- decodeMessage bytes
  InferenceRequest
    <$> require "call_id" (fieldString 1 fields)
    <*> require "experiment_hash" (fieldString 2 fields)
    <*> require "reply_topic" (fieldString 3 fields)
    <*> require "input" (fieldDoubles 4 fields)

inferenceRequestFromFields :: (Text -> Maybe Text) -> Maybe InferenceRequest
inferenceRequestFromFields value =
  InferenceRequest
    <$> value "call-id"
    <*> value "experiment-hash"
    <*> value "reply-topic"
    <*> (value "input" >>= parseInferenceInput)

renderInferenceResult :: InferenceResult -> Text
renderInferenceResult result =
  Text.unlines
    [ "kind: InferenceResult"
    , "call-id: " <> iresCallId result
    , "experiment-hash: " <> iresExperimentHash result
    , "output: " <> renderInferenceInput (iresOutput result)
    ]

renderAppleInferenceEvent :: AppleInferenceEvent -> Text
renderAppleInferenceEvent event =
  Text.unlines $
    [ "envelope: AppleInferenceEvent"
    , "call-id: " <> appleEventCallId event
    , "kind: " <> renderAppleInferenceEventKind (appleEventKind event)
    , "output-refs: " <> renderTextList (appleEventOutputRefs event)
    ]
      <> optionalField "error-code" (appleEventErrorCode event)
      <> optionalField "message" (appleEventMessage event)

parseAppleInferenceEvent :: Text -> Maybe AppleInferenceEvent
parseAppleInferenceEvent payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "AppleInferenceEvent" <- value "envelope"
  AppleInferenceEvent
    <$> value "call-id"
    <*> (value "kind" >>= parseAppleInferenceEventKind)
    <*> (value "output-refs" >>= Just . parseTextList)
    <*> Just (value "error-code")
    <*> Just (value "message")

encodeInferenceResultProto :: InferenceResult -> ByteString
encodeInferenceResultProto result =
  encodeMessage
    [ stringField 1 (iresCallId result)
    , stringField 2 (iresExperimentHash result)
    , packedDoubleField 3 (iresOutput result)
    ]

decodeInferenceResultProto :: ByteString -> Either Text InferenceResult
decodeInferenceResultProto bytes = do
  fields <- decodeMessage bytes
  InferenceResult
    <$> require "call_id" (fieldString 1 fields)
    <*> require "experiment_hash" (fieldString 2 fields)
    <*> require "output" (fieldDoubles 3 fields)

renderInferenceInput :: [Double] -> Text
renderInferenceInput =
  Text.intercalate "," . fmap (Text.pack . show)

parseInferenceInput :: Text -> Maybe [Double]
parseInferenceInput value =
  traverse (readText . Text.strip) (Text.splitOn "," value)

renderAppleInferenceCommandKind :: AppleInferenceCommandKind -> Text
renderAppleInferenceCommandKind AppleCommandTraining = "training"
renderAppleInferenceCommandKind AppleCommandInference = "inference"

parseAppleInferenceCommandKind :: Text -> Maybe AppleInferenceCommandKind
parseAppleInferenceCommandKind "training" = Just AppleCommandTraining
parseAppleInferenceCommandKind "inference" = Just AppleCommandInference
parseAppleInferenceCommandKind _ = Nothing

renderAppleInferenceEventKind :: AppleInferenceEventKind -> Text
renderAppleInferenceEventKind AppleEventCompleted = "completed"
renderAppleInferenceEventKind AppleEventError = "error"

parseAppleInferenceEventKind :: Text -> Maybe AppleInferenceEventKind
parseAppleInferenceEventKind "completed" = Just AppleEventCompleted
parseAppleInferenceEventKind "error" = Just AppleEventError
parseAppleInferenceEventKind _ = Nothing

renderTextList :: [Text] -> Text
renderTextList =
  Text.intercalate ","

parseTextList :: Text -> [Text]
parseTextList value
  | Text.null (Text.strip value) = []
  | otherwise = fmap Text.strip (Text.splitOn "," value)

optionalField :: Text -> Maybe Text -> [Text]
optionalField _ Nothing = []
optionalField fieldName (Just value) = [fieldName <> ": " <> value]

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack

require :: Text -> Maybe a -> Either Text a
require fieldName =
  maybe (Left ("missing protobuf field: " <> fieldName)) Right
