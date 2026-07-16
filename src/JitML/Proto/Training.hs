{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Training
  ( CheckpointDone (..)
  , CompletedCheckpointDone
  , ccdCheckpoint
  , ccdCompletedTraining
  , completeCheckpointDone
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
  , parseTrainingCommand
  , parseTrainingEvent
  , renderTrainingCommand
  , renderTrainingEvent
  )
where

import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import Text.Read (readMaybe)

import JitML.Proto.Wire
  ( ProtoField (..)
  , ProtoValue (..)
  , boolField
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
  , completedTrainingObservedUnits
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
  , stPlanId :: Text
  , stResolvedPlan :: Text
  , stTrainingExamples :: Word32
  , stEvaluationExamples :: Word32
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
  }
  deriving stock (Eq, Show)

-- | A persisted checkpoint paired with a mandatory, re-refined completion
-- witness. The constructor is hidden so a malformed candidate cannot be
-- promoted merely by deserialising a record containing a pass flag.
data CompletedCheckpointDone = CompletedCheckpointDone
  { ccdCheckpoint :: CheckpointDone
  , ccdCompletedTraining :: CompletedTraining
  }
  deriving stock (Eq, Show)

completeCheckpointDone
  :: CheckpointDone
  -> CompletedTraining
  -> Either Text CompletedCheckpointDone
completeCheckpointDone checkpoint completed = do
  validateCheckpointDone checkpoint
  if cdStep checkpoint /= completedTrainingObservedUnits completed
    then Left "checkpoint step does not match completed-training observed units"
    else
      Right
        CompletedCheckpointDone
          { ccdCheckpoint = checkpoint
          , ccdCompletedTraining = completed
          }

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
  | TrainingCompletedCheckpoint CompletedCheckpointDone
  | TrainingFailure TrainingFailed
  deriving stock (Eq, Show)

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
        , "plan-id: " <> stPlanId envelope
        , "resolved-plan: " <> stResolvedPlan envelope
        , "training-examples: " <> Text.pack (show (stTrainingExamples envelope))
        , "evaluation-examples: " <> Text.pack (show (stEvaluationExamples envelope))
        ]
    TrainingStop envelope ->
      Text.unlines
        [ "kind: StopTraining"
        , "experiment-hash: " <> stopExperimentHash envelope
        , "drain: " <> Text.pack (show (stopDrain envelope))
        ]

parseTrainingCommand :: Text -> Maybe TrainingCommand
parseTrainingCommand payload = do
  fields <- traverse parseField (Text.lines payload)
  kind <- requiredField "kind" fields
  case kind of
    "StartTraining" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "dhall-object-key"
        , "substrate"
        , "seed"
        , "epochs"
        , "batch-size"
        , "plan-id"
        , "resolved-plan"
        , "training-examples"
        , "evaluation-examples"
        ]
        fields
      TrainingStart
        <$> ( StartTraining
                <$> requiredField "experiment-hash" fields
                <*> requiredField "dhall-object-key" fields
                <*> (requiredField "substrate" fields >>= parseSubstrate)
                <*> requiredReadField "seed" fields
                <*> requiredPositiveReadField "epochs" fields
                <*> requiredPositiveReadField "batch-size" fields
                <*> requiredField "plan-id" fields
                <*> requiredField "resolved-plan" fields
                <*> requiredPositiveReadField "training-examples" fields
                <*> requiredPositiveReadField "evaluation-examples" fields
            )
    "StopTraining" -> do
      requireOnlyFields ["kind", "experiment-hash", "drain"] fields
      TrainingStop
        <$> ( StopTraining
                <$> requiredField "experiment-hash" fields
                <*> requiredReadField "drain" fields
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
  case fields of
    [ProtoField 1 (LengthDelimited startBytes)] ->
      TrainingStart <$> decodeStartTrainingProto startBytes
    [ProtoField 2 (LengthDelimited stopBytes)] ->
      TrainingStop <$> decodeStopTrainingProto stopBytes
    [ProtoField fieldNumber _]
      | fieldNumber `elem` [1, 2] ->
          Left "TrainingCommand oneof body has the wrong protobuf wire type"
    _ -> Left "expected exactly one TrainingCommand oneof field"

encodeTrainingEventProto :: TrainingEvent -> ByteString
encodeTrainingEventProto event =
  case event of
    TrainingEpoch epoch ->
      encodeMessage [messageField 1 (encodeEpochCompletedProto epoch)]
    TrainingCheckpoint checkpoint ->
      encodeMessage [messageField 2 (encodeCheckpointDoneProto checkpoint)]
    TrainingCompletedCheckpoint completed ->
      encodeMessage [messageField 4 (encodeCompletedCheckpointDoneProto completed)]
    TrainingFailure failure ->
      encodeMessage [messageField 3 (encodeTrainingFailedProto failure)]

decodeTrainingEventProto :: ByteString -> Either Text TrainingEvent
decodeTrainingEventProto bytes = do
  fields <- decodeMessage bytes
  case fields of
    [ProtoField 1 (LengthDelimited epochBytes)] ->
      TrainingEpoch <$> decodeEpochCompletedProto epochBytes
    [ProtoField 2 (LengthDelimited checkpointBytes)] ->
      TrainingCheckpoint <$> decodeCheckpointDoneProto checkpointBytes
    [ProtoField 3 (LengthDelimited failureBytes)] ->
      TrainingFailure <$> decodeTrainingFailedProto failureBytes
    [ProtoField 4 (LengthDelimited completedBytes)] ->
      TrainingCompletedCheckpoint
        <$> decodeCompletedCheckpointDoneProto completedBytes
    [ProtoField fieldNumber _]
      | fieldNumber `elem` [1 .. 4] ->
          Left "TrainingEvent oneof body has the wrong protobuf wire type"
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
        , "timestamp-ns: " <> Text.pack (show (ecTimestampNs e))
        ]
    TrainingCheckpoint c ->
      renderCheckpointDone "CheckpointCandidate" c []
    TrainingCompletedCheckpoint completed ->
      renderCheckpointDone
        "CheckpointCompleted"
        (ccdCheckpoint completed)
        [ "completed-training: "
            <> renderCompletedTraining (ccdCompletedTraining completed)
        ]
    TrainingFailure f ->
      Text.unlines
        [ "kind: TrainingFailed"
        , "experiment-hash: " <> tfExperimentHash f
        , "error-code: " <> sanitizeScalar (tfErrorCode f)
        , "error-text: " <> sanitizeScalar (tfErrorText f)
        , "timestamp-ns: " <> Text.pack (show (tfTimestampNs f))
        ]

-- | Decode exactly one event shape emitted by 'renderTrainingEvent'. Malformed
-- optional fields, duplicate scalar fields, unknown fields, and non-finite
-- measurements are rejected instead of being silently discarded.
parseTrainingEvent :: Text -> Maybe TrainingEvent
parseTrainingEvent payload = do
  fields <- traverse parseField (Text.lines payload)
  kind <- requiredField "kind" fields
  case kind of
    "EpochCompleted" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "epoch"
        , "loss"
        , "validation-loss"
        , "timestamp-ns"
        ]
        fields
      TrainingEpoch
        <$> ( EpochCompleted
                <$> requiredField "experiment-hash" fields
                <*> requiredReadField "epoch" fields
                <*> requiredFiniteField "loss" fields
                <*> requiredFiniteField "validation-loss" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "CheckpointCandidate" -> do
      requireOnlyFields
        [ "kind"
        , "protocol-version"
        , "experiment-hash"
        , "manifest-sha"
        , "step"
        , "pointer-key"
        , "epoch"
        , "run-uuid"
        , "trial-sha"
        , "metric"
        ]
        fields
      requiredTextProtocolVersion fields
      trialSha <- optionalField "trial-sha" fields
      metrics <- traverse parseFiniteMetric (fieldValues "metric" fields)
      checkpoint <-
        CheckpointDone
          <$> requiredField "experiment-hash" fields
          <*> requiredField "manifest-sha" fields
          <*> requiredReadField "step" fields
          <*> requiredField "pointer-key" fields
          <*> requiredReadField "epoch" fields
          <*> pure trialSha
          <*> requiredField "run-uuid" fields
          <*> pure metrics
      eitherToMaybe (validateCheckpointDone checkpoint)
      pure (TrainingCheckpoint checkpoint)
    "CheckpointCompleted" -> do
      requireOnlyFields
        [ "kind"
        , "protocol-version"
        , "experiment-hash"
        , "manifest-sha"
        , "step"
        , "pointer-key"
        , "epoch"
        , "run-uuid"
        , "trial-sha"
        , "metric"
        , "completed-training"
        ]
        fields
      requiredTextProtocolVersion fields
      trialSha <- optionalField "trial-sha" fields
      metrics <- traverse parseFiniteMetric (fieldValues "metric" fields)
      completed <- requiredField "completed-training" fields >>= parseCompletedTraining
      checkpoint <-
        CheckpointDone
          <$> requiredField "experiment-hash" fields
          <*> requiredField "manifest-sha" fields
          <*> requiredReadField "step" fields
          <*> requiredField "pointer-key" fields
          <*> requiredReadField "epoch" fields
          <*> pure trialSha
          <*> requiredField "run-uuid" fields
          <*> pure metrics
      TrainingCompletedCheckpoint
        <$> eitherToMaybe (completeCheckpointDone checkpoint completed)
    "TrainingFailed" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "error-code"
        , "error-text"
        , "timestamp-ns"
        ]
        fields
      TrainingFailure
        <$> ( TrainingFailed
                <$> requiredField "experiment-hash" fields
                <*> requiredSingleLineField "error-code" fields
                <*> requiredSingleLineField "error-text" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    _ -> Nothing

renderMetric :: (Text, Double) -> Text
renderMetric (name, value) =
  "metric: " <> name <> "=" <> Text.pack (show value)

renderCheckpointDone :: Text -> CheckpointDone -> [Text] -> Text
renderCheckpointDone kind checkpoint extraFields =
  Text.unlines
    ( [ "kind: " <> kind
      , "protocol-version: " <> Text.pack (show protocolVersion)
      , "experiment-hash: " <> cdExperimentHash checkpoint
      , "manifest-sha: " <> cdManifestSha checkpoint
      , "step: " <> Text.pack (show (cdStep checkpoint))
      , "pointer-key: " <> cdPointerKey checkpoint
      , "epoch: " <> Text.pack (show (cdEpoch checkpoint))
      , "run-uuid: " <> cdRunUuid checkpoint
      ]
        <> maybe [] (\trialSha -> ["trial-sha: " <> trialSha]) (cdTrialSha checkpoint)
        <> fmap renderMetric (cdMetricsAtStep checkpoint)
        <> extraFields
    )

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

parseFiniteMetric :: Text -> Maybe (Text, Double)
parseFiniteMetric field = do
  (name, value) <- parseMetric field
  if Text.null name || not (finiteDouble value)
    then Nothing
    else Just (name, value)

fieldValues :: Text -> [(Text, Text)] -> [Text]
fieldValues key fields =
  [value | (candidate, value) <- fields, candidate == key]

requiredField :: Text -> [(Text, Text)] -> Maybe Text
requiredField key fields =
  case fieldValues key fields of
    [value]
      | not (Text.null value) -> Just value
    _ -> Nothing

requiredSingleLineField :: Text -> [(Text, Text)] -> Maybe Text
requiredSingleLineField key fields = do
  value <- requiredField key fields
  if Text.any (`elem` ['\n', '\r']) value
    then Nothing
    else Just value

optionalField :: Text -> [(Text, Text)] -> Maybe (Maybe Text)
optionalField key fields =
  case fieldValues key fields of
    [] -> Just Nothing
    [value]
      | not (Text.null value) -> Just (Just value)
    _ -> Nothing

requiredReadField :: (Read value) => Text -> [(Text, Text)] -> Maybe value
requiredReadField key fields =
  requiredField key fields >>= readText

requiredPositiveReadField :: Text -> [(Text, Text)] -> Maybe Word32
requiredPositiveReadField key fields = do
  value <- requiredReadField key fields
  if value == 0 then Nothing else Just value

requiredTextProtocolVersion :: [(Text, Text)] -> Maybe ()
requiredTextProtocolVersion fields = do
  version <- requiredReadField "protocol-version" fields
  if version == protocolVersion then Just () else Nothing

requiredFiniteField :: Text -> [(Text, Text)] -> Maybe Double
requiredFiniteField key fields = do
  value <- requiredReadField key fields
  if finiteDouble value then Just value else Nothing

finiteDouble :: Double -> Bool
finiteDouble value =
  not (isNaN value || isInfinite value)

requireOnlyFields :: [Text] -> [(Text, Text)] -> Maybe ()
requireOnlyFields allowed fields
  | all ((`elem` allowed) . fst) fields = Just ()
  | otherwise = Nothing

sanitizeScalar :: Text -> Text
sanitizeScalar =
  Text.replace "\r" " " . Text.replace "\n" " "

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
    , stringField 7 (stPlanId start)
    , stringField 8 (stResolvedPlan start)
    , uint32Field 9 (stTrainingExamples start)
    , uint32Field 10 (stEvaluationExamples start)
    ]

decodeStartTrainingProto :: ByteString -> Either Text StartTraining
decodeStartTrainingProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "StartTraining" [1 .. 10] fields
  StartTraining
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "dhall_object_key" (fieldString 2 fields)
    <*> ( require "substrate" (fieldString 3 fields)
            >>= requireParsed "substrate" parseSubstrate
        )
    <*> require "seed" (fieldWord64 4 fields)
    <*> requirePositiveWord32 "epochs" (fieldWord32 5 fields)
    <*> requirePositiveWord32 "batch_size" (fieldWord32 6 fields)
    <*> requireNonEmptyText "plan_id" (fieldString 7 fields)
    <*> requireNonEmptyText "resolved_plan" (fieldString 8 fields)
    <*> requirePositiveWord32 "training_examples" (fieldWord32 9 fields)
    <*> requirePositiveWord32 "evaluation_examples" (fieldWord32 10 fields)

encodeStopTrainingProto :: StopTraining -> ByteString
encodeStopTrainingProto stop =
  encodeMessage
    [ stringField 1 (stopExperimentHash stop)
    , boolField 2 (stopDrain stop)
    ]

decodeStopTrainingProto :: ByteString -> Either Text StopTraining
decodeStopTrainingProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "StopTraining" [1, 2] fields
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
  requireExactProtoFields "EpochCompleted" [1 .. 5] fields
  EpochCompleted
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "epoch" (fieldWord32 2 fields)
    <*> requireFiniteDouble "loss" (fieldDouble 3 fields)
    <*> requireFiniteDouble "validation_loss" (fieldDouble 4 fields)
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
      <> [uint32Field 9 protocolVersion]

decodeCheckpointDoneProto :: ByteString -> Either Text CheckpointDone
decodeCheckpointDoneProto bytes = do
  fields <- decodeMessage bytes
  requireCheckpointDoneProtoFields fields
  version <- require "protocol_version" (fieldWord32 9 fields)
  requireProtocolVersion "CheckpointDone" version
  metrics <-
    traverse
      decodeScalarMetricProto
      =<< require "metrics_at_step" (fieldMessages 8 fields)
  checkpoint <-
    CheckpointDone
      <$> require "experiment_hash" (fieldString 1 fields)
      <*> require "manifest_sha" (fieldString 2 fields)
      <*> require "step" (fieldWord64 3 fields)
      <*> require "pointer_key" (fieldString 4 fields)
      <*> require "epoch" (fieldWord32 5 fields)
      <*> pure (fieldString 6 fields)
      <*> require "run_uuid" (fieldString 7 fields)
      <*> pure metrics
  validateCheckpointDone checkpoint
  Right checkpoint

encodeCompletedCheckpointDoneProto :: CompletedCheckpointDone -> ByteString
encodeCompletedCheckpointDoneProto completed =
  encodeMessage
    [ uint32Field 1 protocolVersion
    , messageField 2 (encodeCheckpointDoneProto (ccdCheckpoint completed))
    , messageField 3 (encodeCompletedTraining (ccdCompletedTraining completed))
    ]

decodeCompletedCheckpointDoneProto
  :: ByteString
  -> Either Text CompletedCheckpointDone
decodeCompletedCheckpointDoneProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "CompletedCheckpointDone" [1, 2, 3] fields
  version <- require "protocol_version" (fieldWord32 1 fields)
  requireProtocolVersion "CompletedCheckpointDone" version
  checkpointBytes <- require "checkpoint" (fieldMessage 2 fields)
  completionBytes <- require "completed_training" (fieldMessage 3 fields)
  checkpoint <- decodeCheckpointDoneProto checkpointBytes
  completed <- decodeCompletedTraining completionBytes
  completeCheckpointDone checkpoint completed

encodeScalarMetricProto :: (Text, Double) -> ByteString
encodeScalarMetricProto (tag, value) =
  encodeMessage
    [ stringField 1 tag
    , doubleField 2 value
    ]

decodeScalarMetricProto :: ByteString -> Either Text (Text, Double)
decodeScalarMetricProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "ScalarMetric" [1, 2] fields
  metric <-
    (,)
      <$> require "tag" (fieldString 1 fields)
      <*> requireFiniteDouble "value" (fieldDouble 2 fields)
  validateMetric metric
  Right metric

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
  requireExactProtoFields "TrainingFailed" [1 .. 4] fields
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

protocolVersion :: Word32
protocolVersion = 1

requireProtocolVersion :: Text -> Word32 -> Either Text ()
requireProtocolVersion messageName version
  | version == protocolVersion = Right ()
  | otherwise =
      Left
        ( "unsupported "
            <> messageName
            <> " protocol version: "
            <> Text.pack (show version)
        )

requireFiniteDouble :: Text -> Maybe Double -> Either Text Double
requireFiniteDouble fieldName maybeValue = do
  value <- require fieldName maybeValue
  if finiteDouble value
    then Right value
    else Left ("non-finite protobuf field: " <> fieldName)

requireExactProtoFields :: Text -> [Word64] -> [ProtoField] -> Either Text ()
requireExactProtoFields messageName expected fields =
  let actual = fmap protoFieldNumber fields
      missing = filter (`notElem` actual) expected
      unexpected = filter (`notElem` expected) actual
      duplicate = any (\fieldNumber -> length (filter (== fieldNumber) actual) /= 1) expected
   in if null missing && null unexpected && not duplicate
        then Right ()
        else Left ("unexpected, duplicate, or missing protobuf fields in " <> messageName)

requireCheckpointDoneProtoFields :: [ProtoField] -> Either Text ()
requireCheckpointDoneProtoFields fields =
  let actual = fmap protoFieldNumber fields
      required = [1, 2, 3, 4, 5, 7, 9]
      allowed = [1 .. 9]
      missing = filter (`notElem` actual) required
      unexpected = filter (`notElem` allowed) actual
      singular = [1, 2, 3, 4, 5, 6, 7, 9]
      duplicate = any (\fieldNumber -> length (filter (== fieldNumber) actual) > 1) singular
   in if null missing && null unexpected && not duplicate
        then Right ()
        else Left "unexpected, duplicate, or missing protobuf fields in CheckpointDone"

validateCheckpointDone :: CheckpointDone -> Either Text ()
validateCheckpointDone checkpoint = do
  requireNonBlank "experiment_hash" (cdExperimentHash checkpoint)
  requireNonBlank "manifest_sha" (cdManifestSha checkpoint)
  requireNonBlank "pointer_key" (cdPointerKey checkpoint)
  requireNonBlank "run_uuid" (cdRunUuid checkpoint)
  case cdTrialSha checkpoint of
    Nothing -> Right ()
    Just trialSha -> requireNonBlank "trial_sha" trialSha
  if cdStep checkpoint == 0
    then Left "checkpoint step must be positive"
    else traverse_ validateMetric (cdMetricsAtStep checkpoint)

validateMetric :: (Text, Double) -> Either Text ()
validateMetric (name, value) = do
  requireNonBlank "metric tag" name
  if finiteDouble value
    then Right ()
    else Left ("checkpoint metric must be finite: " <> name)

requireNonBlank :: Text -> Text -> Either Text ()
requireNonBlank fieldName value
  | Text.null (Text.strip value) = Left ("empty field: " <> fieldName)
  | otherwise = Right ()

traverse_ :: (a -> Either error ()) -> [a] -> Either error ()
traverse_ f = foldr (\value rest -> f value >> rest) (Right ())

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe = either (const Nothing) Just

requireNonEmptyText :: Text -> Maybe Text -> Either Text Text
requireNonEmptyText fieldName maybeValue = do
  value <- require fieldName maybeValue
  if Text.null (Text.strip value)
    then Left ("empty protobuf field: " <> fieldName)
    else Right value

requirePositiveWord32 :: Text -> Maybe Word32 -> Either Text Word32
requirePositiveWord32 fieldName maybeValue = do
  value <- require fieldName maybeValue
  if value == 0
    then Left ("non-positive protobuf field: " <> fieldName)
    else Right value
