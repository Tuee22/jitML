{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Inference
  ( InferenceRequest (..)
  , InferenceResult (..)
  , inferenceRequestTopic
  , inferenceResultTopic
  , parseInferenceInput
  , parseInferenceRequest
  , renderInferenceRequest
  , renderInferenceResult
  )
where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Text.Read (readMaybe)

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

inferenceRequestTopic :: Substrate -> Text
inferenceRequestTopic substrate =
  "inference.request." <> renderSubstrate substrate

inferenceResultTopic :: Substrate -> Text
inferenceResultTopic substrate =
  "inference.result." <> renderSubstrate substrate

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

renderInferenceInput :: [Double] -> Text
renderInferenceInput =
  Text.intercalate "," . fmap (Text.pack . show)

parseInferenceInput :: Text -> Maybe [Double]
parseInferenceInput value =
  traverse (readText . Text.strip) (Text.splitOn "," value)

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack
