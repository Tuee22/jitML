{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Rl
  ( CheckpointDoneRL (..)
  , EpisodeDone (..)
  , EvalDone (..)
  , MetricUpdate (..)
  , RlAnimationFrame (..)
  , RlCommand (..)
  , RlEvent (..)
  , RlReplayFrame (..)
  , StartRLRun (..)
  , StopRLRun (..)
  , decodeRlCommandProto
  , decodeRlEventProto
  , encodeRlCommandProto
  , encodeRlEventProto
  , parseRlCommand
  , parseRlEvent
  , renderRlCommand
  , renderRlEvent
  , rlCommandTopic
  , rlEventTopic
  )
where

import Data.ByteString (ByteString)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import Text.Read (readMaybe)

import JitML.Proto.Wire
  ( boolField
  , decodeMessage
  , doubleField
  , encodeMessage
  , fieldBool
  , fieldDouble
  , fieldDoubles
  , fieldMessage
  , fieldString
  , fieldWord32
  , fieldWord64
  , messageField
  , packedDoubleField
  , stringField
  , uint32Field
  , uint64Field
  )
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

data StartRLRun = StartRLRun
  { srlExperimentHash :: Text
  , srlAlgorithm :: Text
  , srlEnvironment :: Text
  , srlSubstrate :: Substrate
  , srlSeed :: Word64
  , srlMaxSteps :: Word32
  , srlEvalEpisodes :: Word32
  }
  deriving stock (Eq, Show)

data StopRLRun = StopRLRun
  { srStopExperimentHash :: Text
  , srStopDrain :: Bool
  }
  deriving stock (Eq, Show)

data EpisodeDone = EpisodeDone
  { edExperimentHash :: Text
  , edEpisode :: Word32
  , edReward :: Double
  , edSteps :: Word32
  , edTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data EvalDone = EvalDone
  { evExperimentHash :: Text
  , evEpoch :: Word32
  , evAvgReward :: Double
  , evStdReward :: Double
  , evTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data CheckpointDoneRL = CheckpointDoneRL
  { cdrlExperimentHash :: Text
  , cdrlManifestSha :: Text
  , cdrlStep :: Word64
  , cdrlPointerKey :: Text
  }
  deriving stock (Eq, Show)

data MetricUpdate = MetricUpdate
  { muExperimentHash :: Text
  , muName :: Text
  , muValue :: Double
  , muTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data RlAnimationFrame = RlAnimationFrame
  { rafExperimentHash :: Text
  , rafEnvironment :: Text
  , rafEpisode :: Word32
  , rafStep :: Word32
  , rafReward :: Double
  , rafDone :: Bool
  , rafAction :: Word32
  , rafObservation :: [Double]
  , rafActionProbabilities :: [Double]
  , rafObservationHash :: Word32
  , rafReplayCursor :: Word64
  , rafTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data RlReplayFrame = RlReplayFrame
  { rrfExperimentHash :: Text
  , rrfReplayId :: Text
  , rrfEnvironment :: Text
  , rrfEpisode :: Word32
  , rrfStep :: Word32
  , rrfAction :: Word32
  , rrfReward :: Double
  , rrfDone :: Bool
  , rrfObservation :: [Double]
  , rrfNextObservation :: [Double]
  , rrfPolicyVersion :: Word64
  , rrfObservationHash :: Word32
  , rrfTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data RlCommand
  = RlStart StartRLRun
  | RlStop StopRLRun
  deriving stock (Eq, Show)

data RlEvent
  = RlEpisode EpisodeDone
  | RlEval EvalDone
  | RlCheckpoint CheckpointDoneRL
  | RlMetric MetricUpdate
  | RlAnimation RlAnimationFrame
  | RlReplay RlReplayFrame
  deriving stock (Eq, Show)

rlCommandTopic :: Substrate -> Text
rlCommandTopic substrate = "rl.command." <> renderSubstrate substrate

rlEventTopic :: Substrate -> Text
rlEventTopic substrate = "rl.event." <> renderSubstrate substrate

renderRlCommand :: RlCommand -> Text
renderRlCommand command =
  case command of
    RlStart e ->
      Text.unlines
        [ "kind: StartRLRun"
        , "experiment-hash: " <> srlExperimentHash e
        , "algorithm: " <> srlAlgorithm e
        , "environment: " <> srlEnvironment e
        , "substrate: " <> renderSubstrate (srlSubstrate e)
        , "seed: " <> Text.pack (show (srlSeed e))
        , "max-steps: " <> Text.pack (show (srlMaxSteps e))
        , "eval-episodes: " <> Text.pack (show (srlEvalEpisodes e))
        ]
    RlStop e ->
      Text.unlines
        [ "kind: StopRLRun"
        , "experiment-hash: " <> srStopExperimentHash e
        , "drain: " <> Text.pack (show (srStopDrain e))
        ]

parseRlCommand :: Text -> Maybe RlCommand
parseRlCommand payload =
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
   in case value "kind" of
        Just "StartRLRun" ->
          RlStart
            <$> ( StartRLRun
                    <$> value "experiment-hash"
                    <*> value "algorithm"
                    <*> value "environment"
                    <*> (value "substrate" >>= parseSubstrate)
                    <*> (value "seed" >>= readText)
                    <*> (value "max-steps" >>= readText)
                    <*> (value "eval-episodes" >>= readText)
                )
        Just "StopRLRun" ->
          RlStop
            <$> ( StopRLRun
                    <$> value "experiment-hash"
                    <*> (value "drain" >>= readText)
                )
        _ -> Nothing

encodeRlCommandProto :: RlCommand -> ByteString
encodeRlCommandProto command =
  case command of
    RlStart start ->
      encodeMessage [messageField 1 (encodeStartRLRunProto start)]
    RlStop stop ->
      encodeMessage [messageField 2 (encodeStopRLRunProto stop)]

decodeRlCommandProto :: ByteString -> Either Text RlCommand
decodeRlCommandProto bytes = do
  fields <- decodeMessage bytes
  case (fieldMessage 1 fields, fieldMessage 2 fields) of
    (Just startBytes, Nothing) ->
      RlStart <$> decodeStartRLRunProto startBytes
    (Nothing, Just stopBytes) ->
      RlStop <$> decodeStopRLRunProto stopBytes
    _ -> Left "expected exactly one RlCommand oneof field"

encodeRlEventProto :: RlEvent -> ByteString
encodeRlEventProto event =
  case event of
    RlEpisode episode ->
      encodeMessage [messageField 1 (encodeEpisodeDoneProto episode)]
    RlEval eval ->
      encodeMessage [messageField 2 (encodeEvalDoneProto eval)]
    RlCheckpoint checkpoint ->
      encodeMessage [messageField 3 (encodeCheckpointDoneRLProto checkpoint)]
    RlMetric metric ->
      encodeMessage [messageField 4 (encodeMetricUpdateProto metric)]
    RlAnimation frame ->
      encodeMessage [messageField 5 (encodeRlAnimationFrameProto frame)]
    RlReplay frame ->
      encodeMessage [messageField 6 (encodeRlReplayFrameProto frame)]

decodeRlEventProto :: ByteString -> Either Text RlEvent
decodeRlEventProto bytes = do
  fields <- decodeMessage bytes
  let body =
        ( fieldMessage 1 fields
        , fieldMessage 2 fields
        , fieldMessage 3 fields
        , fieldMessage 4 fields
        , fieldMessage 5 fields
        , fieldMessage 6 fields
        )
  case body of
    (Just episodeBytes, Nothing, Nothing, Nothing, Nothing, Nothing) ->
      RlEpisode <$> decodeEpisodeDoneProto episodeBytes
    (Nothing, Just evalBytes, Nothing, Nothing, Nothing, Nothing) ->
      RlEval <$> decodeEvalDoneProto evalBytes
    (Nothing, Nothing, Just checkpointBytes, Nothing, Nothing, Nothing) ->
      RlCheckpoint <$> decodeCheckpointDoneRLProto checkpointBytes
    (Nothing, Nothing, Nothing, Just metricBytes, Nothing, Nothing) ->
      RlMetric <$> decodeMetricUpdateProto metricBytes
    (Nothing, Nothing, Nothing, Nothing, Just frameBytes, Nothing) ->
      RlAnimation <$> decodeRlAnimationFrameProto frameBytes
    (Nothing, Nothing, Nothing, Nothing, Nothing, Just frameBytes) ->
      RlReplay <$> decodeRlReplayFrameProto frameBytes
    _ -> Left "expected exactly one RlEvent oneof field"

renderRlEvent :: RlEvent -> Text
renderRlEvent envelope =
  case envelope of
    RlEpisode e ->
      Text.unlines
        [ "kind: EpisodeDone"
        , "experiment-hash: " <> edExperimentHash e
        , "episode: " <> Text.pack (show (edEpisode e))
        , "reward: " <> Text.pack (show (edReward e))
        , "steps: " <> Text.pack (show (edSteps e))
        , "timestamp-ns: " <> Text.pack (show (edTimestampNs e))
        ]
    RlEval e ->
      Text.unlines
        [ "kind: EvalDone"
        , "experiment-hash: " <> evExperimentHash e
        , "epoch: " <> Text.pack (show (evEpoch e))
        , "avg-reward: " <> Text.pack (show (evAvgReward e))
        , "std-reward: " <> Text.pack (show (evStdReward e))
        , "timestamp-ns: " <> Text.pack (show (evTimestampNs e))
        ]
    RlCheckpoint c ->
      Text.unlines
        [ "kind: CheckpointDoneRL"
        , "experiment-hash: " <> cdrlExperimentHash c
        , "manifest-sha: " <> cdrlManifestSha c
        , "step: " <> Text.pack (show (cdrlStep c))
        , "pointer-key: " <> cdrlPointerKey c
        ]
    RlMetric m ->
      Text.unlines
        [ "kind: MetricUpdate"
        , "experiment-hash: " <> muExperimentHash m
        , "name: " <> muName m
        , "value: " <> Text.pack (show (muValue m))
        , "timestamp-ns: " <> Text.pack (show (muTimestampNs m))
        ]
    RlAnimation f ->
      Text.unlines
        [ "kind: RlAnimationFrame"
        , "experiment-hash: " <> rafExperimentHash f
        , "environment: " <> rafEnvironment f
        , "episode: " <> Text.pack (show (rafEpisode f))
        , "step: " <> Text.pack (show (rafStep f))
        , "reward: " <> Text.pack (show (rafReward f))
        , "done: " <> Text.pack (show (rafDone f))
        , "action: " <> Text.pack (show (rafAction f))
        , "observation: " <> renderDoubleList (rafObservation f)
        , "action-probabilities: " <> renderDoubleList (rafActionProbabilities f)
        , "observation-hash: " <> Text.pack (show (rafObservationHash f))
        , "replay-cursor: " <> Text.pack (show (rafReplayCursor f))
        , "timestamp-ns: " <> Text.pack (show (rafTimestampNs f))
        ]
    RlReplay f ->
      Text.unlines
        [ "kind: RlReplayFrame"
        , "experiment-hash: " <> rrfExperimentHash f
        , "replay-id: " <> rrfReplayId f
        , "environment: " <> rrfEnvironment f
        , "episode: " <> Text.pack (show (rrfEpisode f))
        , "step: " <> Text.pack (show (rrfStep f))
        , "action: " <> Text.pack (show (rrfAction f))
        , "reward: " <> Text.pack (show (rrfReward f))
        , "done: " <> Text.pack (show (rrfDone f))
        , "observation: " <> renderDoubleList (rrfObservation f)
        , "next-observation: " <> renderDoubleList (rrfNextObservation f)
        , "policy-version: " <> Text.pack (show (rrfPolicyVersion f))
        , "observation-hash: " <> Text.pack (show (rrfObservationHash f))
        , "timestamp-ns: " <> Text.pack (show (rrfTimestampNs f))
        ]

parseRlEvent :: Text -> Maybe RlEvent
parseRlEvent payload =
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
   in case value "kind" of
        Just "EpisodeDone" ->
          RlEpisode
            <$> ( EpisodeDone
                    <$> value "experiment-hash"
                    <*> (value "episode" >>= readText)
                    <*> (value "reward" >>= readText)
                    <*> (value "steps" >>= readText)
                    <*> (value "timestamp-ns" >>= readText)
                )
        Just "EvalDone" ->
          RlEval
            <$> ( EvalDone
                    <$> value "experiment-hash"
                    <*> (value "epoch" >>= readText)
                    <*> (value "avg-reward" >>= readText)
                    <*> (value "std-reward" >>= readText)
                    <*> (value "timestamp-ns" >>= readText)
                )
        Just "CheckpointDoneRL" ->
          RlCheckpoint
            <$> ( CheckpointDoneRL
                    <$> value "experiment-hash"
                    <*> value "manifest-sha"
                    <*> (value "step" >>= readText)
                    <*> value "pointer-key"
                )
        Just "MetricUpdate" ->
          RlMetric
            <$> ( MetricUpdate
                    <$> value "experiment-hash"
                    <*> value "name"
                    <*> (value "value" >>= readText)
                    <*> (value "timestamp-ns" >>= readText)
                )
        Just "RlAnimationFrame" ->
          RlAnimation
            <$> ( RlAnimationFrame
                    <$> value "experiment-hash"
                    <*> value "environment"
                    <*> (value "episode" >>= readText)
                    <*> (value "step" >>= readText)
                    <*> (value "reward" >>= readText)
                    <*> (value "done" >>= readText)
                    <*> (value "action" >>= readText)
                    <*> (value "observation" >>= parseDoubleList)
                    <*> (value "action-probabilities" >>= parseDoubleList)
                    <*> (value "observation-hash" >>= readText)
                    <*> (value "replay-cursor" >>= readText)
                    <*> (value "timestamp-ns" >>= readText)
                )
        Just "RlReplayFrame" ->
          RlReplay
            <$> ( RlReplayFrame
                    <$> value "experiment-hash"
                    <*> value "replay-id"
                    <*> value "environment"
                    <*> (value "episode" >>= readText)
                    <*> (value "step" >>= readText)
                    <*> (value "action" >>= readText)
                    <*> (value "reward" >>= readText)
                    <*> (value "done" >>= readText)
                    <*> (value "observation" >>= parseDoubleList)
                    <*> (value "next-observation" >>= parseDoubleList)
                    <*> (value "policy-version" >>= readText)
                    <*> (value "observation-hash" >>= readText)
                    <*> (value "timestamp-ns" >>= readText)
                )
        _ -> Nothing

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack

renderDoubleList :: [Double] -> Text
renderDoubleList =
  Text.intercalate "," . fmap (Text.pack . show)

parseDoubleList :: Text -> Maybe [Double]
parseDoubleList raw
  | Text.null (Text.strip raw) = Just []
  | otherwise = traverse readText (Text.splitOn "," raw)

encodeStartRLRunProto :: StartRLRun -> ByteString
encodeStartRLRunProto start =
  encodeMessage
    [ stringField 1 (srlExperimentHash start)
    , stringField 2 (srlAlgorithm start)
    , stringField 3 (srlEnvironment start)
    , stringField 4 (renderSubstrate (srlSubstrate start))
    , uint64Field 5 (srlSeed start)
    , uint32Field 6 (srlMaxSteps start)
    , uint32Field 7 (srlEvalEpisodes start)
    ]

decodeStartRLRunProto :: ByteString -> Either Text StartRLRun
decodeStartRLRunProto bytes = do
  fields <- decodeMessage bytes
  StartRLRun
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "algorithm" (fieldString 2 fields)
    <*> require "environment" (fieldString 3 fields)
    <*> ( require "substrate" (fieldString 4 fields)
            >>= requireParsed "substrate" parseSubstrate
        )
    <*> require "seed" (fieldWord64 5 fields)
    <*> require "max_steps" (fieldWord32 6 fields)
    <*> require "eval_episodes" (fieldWord32 7 fields)

encodeStopRLRunProto :: StopRLRun -> ByteString
encodeStopRLRunProto stop =
  encodeMessage
    [ stringField 1 (srStopExperimentHash stop)
    , boolField 2 (srStopDrain stop)
    ]

decodeStopRLRunProto :: ByteString -> Either Text StopRLRun
decodeStopRLRunProto bytes = do
  fields <- decodeMessage bytes
  StopRLRun
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "drain" (fieldBool 2 fields)

encodeEpisodeDoneProto :: EpisodeDone -> ByteString
encodeEpisodeDoneProto episode =
  encodeMessage
    [ stringField 1 (edExperimentHash episode)
    , uint32Field 2 (edEpisode episode)
    , doubleField 3 (edReward episode)
    , uint32Field 4 (edSteps episode)
    , uint64Field 5 (edTimestampNs episode)
    ]

decodeEpisodeDoneProto :: ByteString -> Either Text EpisodeDone
decodeEpisodeDoneProto bytes = do
  fields <- decodeMessage bytes
  EpisodeDone
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "episode" (fieldWord32 2 fields)
    <*> require "reward" (fieldDouble 3 fields)
    <*> require "steps" (fieldWord32 4 fields)
    <*> require "timestamp_ns" (fieldWord64 5 fields)

encodeEvalDoneProto :: EvalDone -> ByteString
encodeEvalDoneProto eval =
  encodeMessage
    [ stringField 1 (evExperimentHash eval)
    , uint32Field 2 (evEpoch eval)
    , doubleField 3 (evAvgReward eval)
    , doubleField 4 (evStdReward eval)
    , uint64Field 5 (evTimestampNs eval)
    ]

decodeEvalDoneProto :: ByteString -> Either Text EvalDone
decodeEvalDoneProto bytes = do
  fields <- decodeMessage bytes
  EvalDone
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "epoch" (fieldWord32 2 fields)
    <*> require "avg_reward" (fieldDouble 3 fields)
    <*> require "std_reward" (fieldDouble 4 fields)
    <*> require "timestamp_ns" (fieldWord64 5 fields)

encodeCheckpointDoneRLProto :: CheckpointDoneRL -> ByteString
encodeCheckpointDoneRLProto checkpoint =
  encodeMessage
    [ stringField 1 (cdrlExperimentHash checkpoint)
    , stringField 2 (cdrlManifestSha checkpoint)
    , uint64Field 3 (cdrlStep checkpoint)
    , stringField 4 (cdrlPointerKey checkpoint)
    ]

decodeCheckpointDoneRLProto :: ByteString -> Either Text CheckpointDoneRL
decodeCheckpointDoneRLProto bytes = do
  fields <- decodeMessage bytes
  CheckpointDoneRL
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "manifest_sha" (fieldString 2 fields)
    <*> require "step" (fieldWord64 3 fields)
    <*> require "pointer_key" (fieldString 4 fields)

encodeMetricUpdateProto :: MetricUpdate -> ByteString
encodeMetricUpdateProto metric =
  encodeMessage
    [ stringField 1 (muExperimentHash metric)
    , stringField 2 (muName metric)
    , doubleField 3 (muValue metric)
    , uint64Field 4 (muTimestampNs metric)
    ]

decodeMetricUpdateProto :: ByteString -> Either Text MetricUpdate
decodeMetricUpdateProto bytes = do
  fields <- decodeMessage bytes
  MetricUpdate
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "name" (fieldString 2 fields)
    <*> require "value" (fieldDouble 3 fields)
    <*> require "timestamp_ns" (fieldWord64 4 fields)

encodeRlAnimationFrameProto :: RlAnimationFrame -> ByteString
encodeRlAnimationFrameProto frame =
  encodeMessage
    [ stringField 1 (rafExperimentHash frame)
    , stringField 2 (rafEnvironment frame)
    , uint32Field 3 (rafEpisode frame)
    , uint32Field 4 (rafStep frame)
    , doubleField 5 (rafReward frame)
    , boolField 6 (rafDone frame)
    , uint32Field 7 (rafAction frame)
    , packedDoubleField 8 (rafObservation frame)
    , packedDoubleField 9 (rafActionProbabilities frame)
    , uint32Field 10 (rafObservationHash frame)
    , uint64Field 11 (rafReplayCursor frame)
    , uint64Field 12 (rafTimestampNs frame)
    ]

decodeRlAnimationFrameProto :: ByteString -> Either Text RlAnimationFrame
decodeRlAnimationFrameProto bytes = do
  fields <- decodeMessage bytes
  RlAnimationFrame
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "environment" (fieldString 2 fields)
    <*> require "episode" (fieldWord32 3 fields)
    <*> require "step" (fieldWord32 4 fields)
    <*> require "reward" (fieldDouble 5 fields)
    <*> require "done" (fieldBool 6 fields)
    <*> require "action" (fieldWord32 7 fields)
    <*> require "observation" (fieldDoubles 8 fields)
    <*> require "action_probabilities" (fieldDoubles 9 fields)
    <*> require "observation_hash" (fieldWord32 10 fields)
    <*> require "replay_cursor" (fieldWord64 11 fields)
    <*> require "timestamp_ns" (fieldWord64 12 fields)

encodeRlReplayFrameProto :: RlReplayFrame -> ByteString
encodeRlReplayFrameProto frame =
  encodeMessage
    [ stringField 1 (rrfExperimentHash frame)
    , stringField 2 (rrfReplayId frame)
    , stringField 3 (rrfEnvironment frame)
    , uint32Field 4 (rrfEpisode frame)
    , uint32Field 5 (rrfStep frame)
    , uint32Field 6 (rrfAction frame)
    , doubleField 7 (rrfReward frame)
    , boolField 8 (rrfDone frame)
    , packedDoubleField 9 (rrfObservation frame)
    , packedDoubleField 10 (rrfNextObservation frame)
    , uint64Field 11 (rrfPolicyVersion frame)
    , uint32Field 12 (rrfObservationHash frame)
    , uint64Field 13 (rrfTimestampNs frame)
    ]

decodeRlReplayFrameProto :: ByteString -> Either Text RlReplayFrame
decodeRlReplayFrameProto bytes = do
  fields <- decodeMessage bytes
  RlReplayFrame
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "replay_id" (fieldString 2 fields)
    <*> require "environment" (fieldString 3 fields)
    <*> require "episode" (fieldWord32 4 fields)
    <*> require "step" (fieldWord32 5 fields)
    <*> require "action" (fieldWord32 6 fields)
    <*> require "reward" (fieldDouble 7 fields)
    <*> require "done" (fieldBool 8 fields)
    <*> require "observation" (fieldDoubles 9 fields)
    <*> require "next_observation" (fieldDoubles 10 fields)
    <*> require "policy_version" (fieldWord64 11 fields)
    <*> require "observation_hash" (fieldWord32 12 fields)
    <*> require "timestamp_ns" (fieldWord64 13 fields)

require :: Text -> Maybe a -> Either Text a
require fieldName =
  maybe (Left ("missing protobuf field: " <> fieldName)) Right

requireParsed :: Text -> (a -> Maybe b) -> a -> Either Text b
requireParsed fieldName parseValue value =
  maybe (Left ("invalid protobuf field: " <> fieldName)) Right (parseValue value)
