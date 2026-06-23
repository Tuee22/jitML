{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Inference
  ( AdversarialMoveCommand (..)
  , AdversarialMoveResult (..)
  , CheckpointCompareCommand (..)
  , CheckpointCompareResult (..)
  , InferenceRequest (..)
  , InferenceResult (..)
  , ListCheckpointsCommand (..)
  , LoadTranscriptCommand (..)
  , appleInferenceCommandTopic
  , parseAdversarialMoveCommand
  , parseCheckpointCompareCommand
  , parseListCheckpointsCommand
  , parseLoadTranscriptCommand
  , renderAdversarialMoveResult
  , renderAdversarialMoveCommand
  , renderCheckpointCompareCommand
  , renderCheckpointCompareResult
  , renderListCheckpointsCommand
  , renderLoadTranscriptCommand
  , decodeInferenceRequestProto
  , decodeInferenceResultProto
  , encodeInferenceRequestProto
  , encodeInferenceResultProto
  , inferenceRequestTopic
  , inferenceResultTopic
  , parseInferenceInput
  , parseInferenceRequest
  , parseInferenceResult
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

-- | Sprint 11.10 — checkpoint-compare as an __Engine__ job: the daemon runs two
-- inferences and computes the delta (it no longer happens in the webapp). Rides
-- the inference request/result topics with its own @kind@.
data CheckpointCompareCommand = CheckpointCompareCommand
  { cccCallId :: Text
  , cccBaselineExperimentHash :: Text
  , cccCandidateExperimentHash :: Text
  , cccReplyTopic :: Text
  , cccInput :: [Double]
  }
  deriving stock (Eq, Show)

data CheckpointCompareResult = CheckpointCompareResult
  { ccrCallId :: Text
  , ccrBaselineExperimentHash :: Text
  , ccrCandidateExperimentHash :: Text
  , ccrBaselineOutput :: [Double]
  , ccrCandidateOutput :: [Double]
  , ccrMaxAbsDelta :: Double
  , ccrMeanAbsDelta :: Double
  }
  deriving stock (Eq, Show)

-- | Sprint 11.10 — adversarial (Connect-4) move selection as an __Engine__ job:
-- the daemon runs the policy/value inference __and__ the MCTS tree search (it no
-- longer happens in the webapp) and emits the chosen move.
data AdversarialMoveCommand = AdversarialMoveCommand
  { amcCallId :: Text
  , amcGame :: Text
  , amcExperimentHash :: Text
  , amcReplyTopic :: Text
  , amcMoves :: [Int]
  , amcHumanIsPlayer :: Int
  , amcSimulationsPerMove :: Int
  , amcInput :: [Double]
  }
  deriving stock (Eq, Show)

data AdversarialMoveResult = AdversarialMoveResult
  { amrCallId :: Text
  , amrExperimentHash :: Text
  , amrGame :: Text
  , amrChosenColumn :: Int
  , amrLegalMoves :: [Int]
  , amrVisitCounts :: [Int]
  , amrPolicyPriors :: [Double]
  , amrValueEstimate :: Double
  , amrGameOver :: Bool
  , amrTranscriptId :: Text
  }
  deriving stock (Eq, Show)

-- | Sprint 14.1 (Feature A) — checkpoint browse as an __Engine__ job: the Webapp
-- publishes this command on the inference request topic and the Engine lists the
-- seeded experiments' manifests from MinIO, replying with a @CheckpointList@
-- frame on the reply topic. Carries no input beyond the reply topic.
data ListCheckpointsCommand = ListCheckpointsCommand
  { lccCallId :: Text
  , lccReplyTopic :: Text
  }
  deriving stock (Eq, Show)

-- | Sprint 14.1 (Feature B) — transcript replay as an __Engine__ job: the Webapp
-- publishes this command (carrying a persisted transcript key) on the inference
-- request topic and the Engine reads the transcript record from the
-- @jitml-transcripts@ MinIO bucket, replying with a @TranscriptReplay@ frame on
-- the reply topic.
data LoadTranscriptCommand = LoadTranscriptCommand
  { ltcCallId :: Text
  , ltcTranscriptId :: Text
  , ltcReplyTopic :: Text
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

-- | Sprint 11.10 — parse the daemon's @renderInferenceResult@ reply text (the
-- inference @WorkResult@) so the CLI / Webapp publisher can render the streamed
-- result instead of computing in-process.
parseInferenceResult :: Text -> Maybe InferenceResult
parseInferenceResult payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "InferenceResult" <- value "kind"
  InferenceResult
    <$> value "call-id"
    <*> value "experiment-hash"
    <*> (value "output" >>= parseInferenceInput)

renderInferenceResult :: InferenceResult -> Text
renderInferenceResult result =
  Text.unlines
    [ "kind: InferenceResult"
    , "call-id: " <> iresCallId result
    , "experiment-hash: " <> iresExperimentHash result
    , "output: " <> renderInferenceInput (iresOutput result)
    ]

renderCheckpointCompareCommand :: CheckpointCompareCommand -> Text
renderCheckpointCompareCommand command =
  Text.unlines
    [ "kind: CheckpointCompareCommand"
    , "call-id: " <> cccCallId command
    , "baseline-experiment-hash: " <> cccBaselineExperimentHash command
    , "candidate-experiment-hash: " <> cccCandidateExperimentHash command
    , "reply-topic: " <> cccReplyTopic command
    , "input: " <> renderInferenceInput (cccInput command)
    ]

parseCheckpointCompareCommand :: Text -> Maybe CheckpointCompareCommand
parseCheckpointCompareCommand payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "CheckpointCompareCommand" <- value "kind"
  CheckpointCompareCommand
    <$> value "call-id"
    <*> value "baseline-experiment-hash"
    <*> value "candidate-experiment-hash"
    <*> value "reply-topic"
    <*> (value "input" >>= parseInferenceInput)

renderCheckpointCompareResult :: CheckpointCompareResult -> Text
renderCheckpointCompareResult result =
  Text.unlines
    [ "kind: CheckpointCompareResult"
    , "call-id: " <> ccrCallId result
    , "baseline-experiment-hash: " <> ccrBaselineExperimentHash result
    , "candidate-experiment-hash: " <> ccrCandidateExperimentHash result
    , "baseline-output: " <> renderInferenceInput (ccrBaselineOutput result)
    , "candidate-output: " <> renderInferenceInput (ccrCandidateOutput result)
    , "max-abs-delta: " <> Text.pack (show (ccrMaxAbsDelta result))
    , "mean-abs-delta: " <> Text.pack (show (ccrMeanAbsDelta result))
    ]

renderAdversarialMoveCommand :: AdversarialMoveCommand -> Text
renderAdversarialMoveCommand command =
  Text.unlines
    [ "kind: AdversarialMoveCommand"
    , "call-id: " <> amcCallId command
    , "game: " <> amcGame command
    , "experiment-hash: " <> amcExperimentHash command
    , "reply-topic: " <> amcReplyTopic command
    , "moves: " <> renderIntList (amcMoves command)
    , "human-is-player: " <> Text.pack (show (amcHumanIsPlayer command))
    , "simulations-per-move: " <> Text.pack (show (amcSimulationsPerMove command))
    , "input: " <> renderInferenceInput (amcInput command)
    ]

parseAdversarialMoveCommand :: Text -> Maybe AdversarialMoveCommand
parseAdversarialMoveCommand payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "AdversarialMoveCommand" <- value "kind"
  AdversarialMoveCommand
    <$> value "call-id"
    <*> value "game"
    <*> value "experiment-hash"
    <*> value "reply-topic"
    <*> (value "moves" >>= parseIntList)
    <*> (value "human-is-player" >>= readText)
    <*> (value "simulations-per-move" >>= readText)
    <*> (value "input" >>= parseInferenceInput)

renderListCheckpointsCommand :: ListCheckpointsCommand -> Text
renderListCheckpointsCommand command =
  Text.unlines
    [ "kind: ListCheckpointsCommand"
    , "call-id: " <> lccCallId command
    , "reply-topic: " <> lccReplyTopic command
    ]

parseListCheckpointsCommand :: Text -> Maybe ListCheckpointsCommand
parseListCheckpointsCommand payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "ListCheckpointsCommand" <- value "kind"
  ListCheckpointsCommand
    <$> value "call-id"
    <*> value "reply-topic"

renderLoadTranscriptCommand :: LoadTranscriptCommand -> Text
renderLoadTranscriptCommand command =
  Text.unlines
    [ "kind: LoadTranscriptCommand"
    , "call-id: " <> ltcCallId command
    , "transcript-id: " <> ltcTranscriptId command
    , "reply-topic: " <> ltcReplyTopic command
    ]

parseLoadTranscriptCommand :: Text -> Maybe LoadTranscriptCommand
parseLoadTranscriptCommand payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "LoadTranscriptCommand" <- value "kind"
  LoadTranscriptCommand
    <$> value "call-id"
    <*> value "transcript-id"
    <*> value "reply-topic"

renderAdversarialMoveResult :: AdversarialMoveResult -> Text
renderAdversarialMoveResult result =
  Text.unlines
    [ "kind: AdversarialMoveResult"
    , "call-id: " <> amrCallId result
    , "experiment-hash: " <> amrExperimentHash result
    , "game: " <> amrGame result
    , "chosen-column: " <> Text.pack (show (amrChosenColumn result))
    , "legal-moves: " <> renderIntList (amrLegalMoves result)
    , "visit-counts: " <> renderIntList (amrVisitCounts result)
    , "policy-priors: " <> renderInferenceInput (amrPolicyPriors result)
    , "value-estimate: " <> Text.pack (show (amrValueEstimate result))
    , "game-over: " <> (if amrGameOver result then "true" else "false")
    , "transcript-id: " <> amrTranscriptId result
    ]

renderIntList :: [Int] -> Text
renderIntList = Text.intercalate "," . fmap (Text.pack . show)

parseIntList :: Text -> Maybe [Int]
parseIntList value
  | Text.null (Text.strip value) = Just []
  | otherwise = traverse (readText . Text.strip) (Text.splitOn "," value)

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
parseInferenceInput value
  | Text.null (Text.strip value) = Just []
  | otherwise = traverse (readText . Text.strip) (Text.splitOn "," value)

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
