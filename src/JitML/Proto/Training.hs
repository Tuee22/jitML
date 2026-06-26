{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Training
  ( CheckpointDone (..)
  , EpochCompleted (..)
  , StartTraining (..)
  , StopTraining (..)
  , TrainingCommand (..)
  , TrainingEvent (..)
  , TrainingFailed (..)
  , decodeTrainingCommandProto
  , decodeTrainingEventProto
  , encodeTrainingCommandProto
  , encodeTrainingEventProto
  , parseTrainingCheckpointDone
  , parseTrainingCommand
  , renderTrainingCommand
  , renderTrainingEvent
  , trainingCommandTopic
  , trainingEventTopic
  )
where

import Data.ByteString (ByteString)
import Data.Maybe (fromMaybe, mapMaybe)
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
  , fieldMessage
  , fieldMessages
  , fieldString
  , fieldWord32
  , fieldWord64
  , messageField
  , stringField
  , uint32Field
  , uint64Field
  )
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Training.Budget
  ( CompletedTraining
  , decodeCompletedTraining
  , encodeCompletedTraining
  , parseCompletedTraining
  , renderCompletedTraining
  )

data StartTraining = StartTraining
  { stExperimentHash :: Text
  , stDhallObjectKey :: Text
  , stSubstrate :: Substrate
  , stSeed :: Word64
  , stEpochs :: Word32
  , stBatchSize :: Word32
  }
  deriving stock (Eq, Show)

data StopTraining = StopTraining
  { stopExperimentHash :: Text
  , stopDrain :: Bool
  }
  deriving stock (Eq, Show)

data EpochCompleted = EpochCompleted
  { ecExperimentHash :: Text
  , ecEpoch :: Word32
  , ecLoss :: Double
  , ecValidationLoss :: Double
  , ecTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data CheckpointDone = CheckpointDone
  { cdExperimentHash :: Text
  , cdManifestSha :: Text
  , cdStep :: Word64
  , cdPointerKey :: Text
  , cdEpoch :: Word32
  , cdTrialSha :: Maybe Text
  , cdRunUuid :: Text
  , cdMetricsAtStep :: [(Text, Double)]
  , cdCompletedTraining :: Maybe CompletedTraining
  }
  deriving stock (Eq, Show)

data TrainingFailed = TrainingFailed
  { tfExperimentHash :: Text
  , tfErrorCode :: Text
  , tfErrorText :: Text
  , tfTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data TrainingCommand
  = TrainingStart StartTraining
  | TrainingStop StopTraining
  deriving stock (Eq, Show)

data TrainingEvent
  = TrainingEpoch EpochCompleted
  | TrainingCheckpoint CheckpointDone
  | TrainingFailure TrainingFailed
  deriving stock (Eq, Show)

trainingCommandTopic :: Substrate -> Text
trainingCommandTopic substrate =
  "training.command." <> renderSubstrate substrate

trainingEventTopic :: Substrate -> Text
trainingEventTopic substrate =
  "training.event." <> renderSubstrate substrate

renderTrainingCommand :: TrainingCommand -> Text
renderTrainingCommand command =
  case command of
    TrainingStart envelope ->
      Text.unlines
        [ "kind: StartTraining"
        , "experiment-hash: " <> stExperimentHash envelope
        , "dhall-object-key: " <> stDhallObjectKey envelope
        , "substrate: " <> renderSubstrate (stSubstrate envelope)
        , "seed: " <> Text.pack (show (stSeed envelope))
        , "epochs: " <> Text.pack (show (stEpochs envelope))
        , "batch-size: " <> Text.pack (show (stBatchSize envelope))
        ]
    TrainingStop envelope ->
      Text.unlines
        [ "kind: StopTraining"
        , "experiment-hash: " <> stopExperimentHash envelope
        , "drain: " <> Text.pack (show (stopDrain envelope))
        ]

parseTrainingCommand :: Text -> Maybe TrainingCommand
parseTrainingCommand payload =
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
   in case value "kind" of
        Just "StartTraining" ->
          TrainingStart
            <$> ( StartTraining
                    <$> value "experiment-hash"
                    <*> value "dhall-object-key"
                    <*> (value "substrate" >>= parseSubstrate)
                    <*> (value "seed" >>= readText)
                    <*> (value "epochs" >>= readText)
                    <*> (value "batch-size" >>= readText)
                )
        Just "StopTraining" ->
          TrainingStop
            <$> ( StopTraining
                    <$> value "experiment-hash"
                    <*> (value "drain" >>= readText)
                )
        _ -> Nothing

encodeTrainingCommandProto :: TrainingCommand -> ByteString
encodeTrainingCommandProto command =
  case command of
    TrainingStart start ->
      encodeMessage [messageField 1 (encodeStartTrainingProto start)]
    TrainingStop stop ->
      encodeMessage [messageField 2 (encodeStopTrainingProto stop)]

decodeTrainingCommandProto :: ByteString -> Either Text TrainingCommand
decodeTrainingCommandProto bytes = do
  fields <- decodeMessage bytes
  case (fieldMessage 1 fields, fieldMessage 2 fields) of
    (Just startBytes, Nothing) ->
      TrainingStart <$> decodeStartTrainingProto startBytes
    (Nothing, Just stopBytes) ->
      TrainingStop <$> decodeStopTrainingProto stopBytes
    _ -> Left "expected exactly one TrainingCommand oneof field"

encodeTrainingEventProto :: TrainingEvent -> ByteString
encodeTrainingEventProto event =
  case event of
    TrainingEpoch epoch ->
      encodeMessage [messageField 1 (encodeEpochCompletedProto epoch)]
    TrainingCheckpoint checkpoint ->
      encodeMessage [messageField 2 (encodeCheckpointDoneProto checkpoint)]
    TrainingFailure failure ->
      encodeMessage [messageField 3 (encodeTrainingFailedProto failure)]

decodeTrainingEventProto :: ByteString -> Either Text TrainingEvent
decodeTrainingEventProto bytes = do
  fields <- decodeMessage bytes
  let body =
        ( fieldMessage 1 fields
        , fieldMessage 2 fields
        , fieldMessage 3 fields
        )
  case body of
    (Just epochBytes, Nothing, Nothing) ->
      TrainingEpoch <$> decodeEpochCompletedProto epochBytes
    (Nothing, Just checkpointBytes, Nothing) ->
      TrainingCheckpoint <$> decodeCheckpointDoneProto checkpointBytes
    (Nothing, Nothing, Just failureBytes) ->
      TrainingFailure <$> decodeTrainingFailedProto failureBytes
    _ -> Left "expected exactly one TrainingEvent oneof field"

renderTrainingEvent :: TrainingEvent -> Text
renderTrainingEvent envelope =
  case envelope of
    TrainingEpoch e ->
      Text.unlines
        [ "kind: EpochCompleted"
        , "experiment-hash: " <> ecExperimentHash e
        , "epoch: " <> Text.pack (show (ecEpoch e))
        , "loss: " <> Text.pack (show (ecLoss e))
        , "validation-loss: " <> Text.pack (show (ecValidationLoss e))
        ]
    TrainingCheckpoint c ->
      Text.unlines
        ( [ "kind: CheckpointDone"
          , "experiment-hash: " <> cdExperimentHash c
          , "manifest-sha: " <> cdManifestSha c
          , "step: " <> Text.pack (show (cdStep c))
          , "pointer-key: " <> cdPointerKey c
          , "epoch: " <> Text.pack (show (cdEpoch c))
          , "run-uuid: " <> cdRunUuid c
          ]
            <> maybe [] (\trialSha -> ["trial-sha: " <> trialSha]) (cdTrialSha c)
            <> fmap renderMetric (cdMetricsAtStep c)
            <> maybe
              []
              (\completed -> ["completed-training: " <> renderCompletedTraining completed])
              (cdCompletedTraining c)
        )
    TrainingFailure f ->
      Text.unlines
        [ "kind: TrainingFailed"
        , "experiment-hash: " <> tfExperimentHash f
        , "error-code: " <> tfErrorCode f
        , "error-text: " <> tfErrorText f
        ]

parseTrainingCheckpointDone :: Text -> Maybe CheckpointDone
parseTrainingCheckpointDone payload = do
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
  "CheckpointDone" <- value "kind"
  experimentHash <- value "experiment-hash"
  manifestSha <- value "manifest-sha"
  step <- value "step" >>= readText
  pointerKey <- value "pointer-key"
  let epoch = fromMaybe 0 (value "epoch" >>= readText)
      runUuid = fromMaybe pointerKey (value "run-uuid")
      trialSha = value "trial-sha"
      metrics = mapMaybe parseMetric [metric | ("metric", metric) <- fields]
      completed = value "completed-training" >>= parseCompletedTraining
  pure
    CheckpointDone
      { cdExperimentHash = experimentHash
      , cdManifestSha = manifestSha
      , cdStep = step
      , cdPointerKey = pointerKey
      , cdEpoch = epoch
      , cdTrialSha = trialSha
      , cdRunUuid = runUuid
      , cdMetricsAtStep = metrics
      , cdCompletedTraining = completed
      }

renderMetric :: (Text, Double) -> Text
renderMetric (name, value) =
  "metric: " <> name <> "=" <> Text.pack (show value)

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

parseMetric :: Text -> Maybe (Text, Double)
parseMetric field = do
  let (name, rest) = Text.breakOn "=" field
  if Text.null rest
    then Nothing
    else do
      value <- readText (Text.strip (Text.drop 1 rest))
      pure (Text.strip name, value)

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack

encodeStartTrainingProto :: StartTraining -> ByteString
encodeStartTrainingProto start =
  encodeMessage
    [ stringField 1 (stExperimentHash start)
    , stringField 2 (stDhallObjectKey start)
    , stringField 3 (renderSubstrate (stSubstrate start))
    , uint64Field 4 (stSeed start)
    , uint32Field 5 (stEpochs start)
    , uint32Field 6 (stBatchSize start)
    ]

decodeStartTrainingProto :: ByteString -> Either Text StartTraining
decodeStartTrainingProto bytes = do
  fields <- decodeMessage bytes
  StartTraining
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "dhall_object_key" (fieldString 2 fields)
    <*> ( require "substrate" (fieldString 3 fields)
            >>= requireParsed "substrate" parseSubstrate
        )
    <*> require "seed" (fieldWord64 4 fields)
    <*> require "epochs" (fieldWord32 5 fields)
    <*> require "batch_size" (fieldWord32 6 fields)

encodeStopTrainingProto :: StopTraining -> ByteString
encodeStopTrainingProto stop =
  encodeMessage
    [ stringField 1 (stopExperimentHash stop)
    , boolField 2 (stopDrain stop)
    ]

decodeStopTrainingProto :: ByteString -> Either Text StopTraining
decodeStopTrainingProto bytes = do
  fields <- decodeMessage bytes
  StopTraining
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "drain" (fieldBool 2 fields)

encodeEpochCompletedProto :: EpochCompleted -> ByteString
encodeEpochCompletedProto epoch =
  encodeMessage
    [ stringField 1 (ecExperimentHash epoch)
    , uint32Field 2 (ecEpoch epoch)
    , doubleField 3 (ecLoss epoch)
    , doubleField 4 (ecValidationLoss epoch)
    , uint64Field 5 (ecTimestampNs epoch)
    ]

decodeEpochCompletedProto :: ByteString -> Either Text EpochCompleted
decodeEpochCompletedProto bytes = do
  fields <- decodeMessage bytes
  EpochCompleted
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "epoch" (fieldWord32 2 fields)
    <*> require "loss" (fieldDouble 3 fields)
    <*> require "validation_loss" (fieldDouble 4 fields)
    <*> require "timestamp_ns" (fieldWord64 5 fields)

encodeCheckpointDoneProto :: CheckpointDone -> ByteString
encodeCheckpointDoneProto checkpoint =
  encodeMessage $
    [ stringField 1 (cdExperimentHash checkpoint)
    , stringField 2 (cdManifestSha checkpoint)
    , uint64Field 3 (cdStep checkpoint)
    , stringField 4 (cdPointerKey checkpoint)
    , uint32Field 5 (cdEpoch checkpoint)
    ]
      <> maybe [] (\trialSha -> [stringField 6 trialSha]) (cdTrialSha checkpoint)
      <> [stringField 7 (cdRunUuid checkpoint)]
      <> fmap
        (messageField 8 . encodeScalarMetricProto)
        (cdMetricsAtStep checkpoint)
      <> maybe
        []
        (\completed -> [messageField 9 (encodeCompletedTraining completed)])
        (cdCompletedTraining checkpoint)

decodeCheckpointDoneProto :: ByteString -> Either Text CheckpointDone
decodeCheckpointDoneProto bytes = do
  fields <- decodeMessage bytes
  metrics <-
    traverse
      decodeScalarMetricProto
      =<< require "metrics_at_step" (fieldMessages 8 fields)
  completed <-
    case fieldMessage 9 fields of
      Nothing -> Right Nothing
      Just completedBytes -> Just <$> decodeCompletedTraining completedBytes
  CheckpointDone
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "manifest_sha" (fieldString 2 fields)
    <*> require "step" (fieldWord64 3 fields)
    <*> require "pointer_key" (fieldString 4 fields)
    <*> require "epoch" (fieldWord32 5 fields)
    <*> pure (fieldString 6 fields)
    <*> require "run_uuid" (fieldString 7 fields)
    <*> pure metrics
    <*> pure completed

encodeScalarMetricProto :: (Text, Double) -> ByteString
encodeScalarMetricProto (tag, value) =
  encodeMessage
    [ stringField 1 tag
    , doubleField 2 value
    ]

decodeScalarMetricProto :: ByteString -> Either Text (Text, Double)
decodeScalarMetricProto bytes = do
  fields <- decodeMessage bytes
  (,)
    <$> require "tag" (fieldString 1 fields)
    <*> require "value" (fieldDouble 2 fields)

encodeTrainingFailedProto :: TrainingFailed -> ByteString
encodeTrainingFailedProto failure =
  encodeMessage
    [ stringField 1 (tfExperimentHash failure)
    , stringField 2 (tfErrorCode failure)
    , stringField 3 (tfErrorText failure)
    , uint64Field 4 (tfTimestampNs failure)
    ]

decodeTrainingFailedProto :: ByteString -> Either Text TrainingFailed
decodeTrainingFailedProto bytes = do
  fields <- decodeMessage bytes
  TrainingFailed
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "error_code" (fieldString 2 fields)
    <*> require "error_text" (fieldString 3 fields)
    <*> require "timestamp_ns" (fieldWord64 4 fields)

require :: Text -> Maybe a -> Either Text a
require fieldName =
  maybe (Left ("missing protobuf field: " <> fieldName)) Right

requireParsed :: Text -> (a -> Maybe b) -> a -> Either Text b
requireParsed fieldName parseValue value =
  maybe (Left ("invalid protobuf field: " <> fieldName)) Right (parseValue value)
