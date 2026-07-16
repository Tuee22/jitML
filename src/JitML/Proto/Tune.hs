{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , SweepCompleted
  , SweepFinished (..)
  , completeSweep
  , scCompletedTraining
  , scFinished
  , TrialFinished (..)
  , TrialStarted (..)
  , TuneCommand (..)
  , TuneEvent (..)
  , decodeTuneCommandProto
  , decodeTuneEventProto
  , encodeTuneCommandProto
  , encodeTuneEventProto
  , parseTuneCommand
  , parseTuneEvent
  , renderTuneCommand
  , renderTuneEvent
  )
where

import Data.ByteString (ByteString)
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import Text.Read (readMaybe)

import JitML.Plan.Plan (planIdText)
import JitML.Proto.Wire
  ( ProtoField (..)
  , boolField
  , decodeMessage
  , doubleField
  , encodeMessage
  , fieldBool
  , fieldDouble
  , fieldMessage
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
  ( BudgetKind (TuningTrialBudget)
  , CompletedTraining
  , completedTrainingBudget
  , completedTrainingPlanId
  , decodeCompletedTraining
  , encodeCompletedTraining
  , parseCompletedTraining
  , renderCompletedTraining
  , trainingBudgetKind
  , trainingBudgetTargetUnits
  )

data StartSweep = StartSweep
  { ssExperimentHash :: Text
  , ssDhallObjectKey :: Text
  , ssSubstrate :: Substrate
  , ssSweepSeed :: Word64
  , ssTrialBudget :: Word32
  , ssBudgetPerTrial :: Word32
  , ssSampler :: Text
  , ssScheduler :: Text
  , ssPruner :: Text
  , ssParallelism :: Word32
  , ssPromotions :: Word32
  , ssPlanId :: Text
  , ssResolvedPlan :: Text
  }
  deriving stock (Eq, Show)

newtype StopSweep = StopSweep
  { ssStopExperimentHash :: Text
  }
  deriving stock (Eq, Show)

data TrialStarted = TrialStarted
  { tsExperimentHash :: Text
  , tsPlanId :: Text
  , tsTrial :: Word32
  , tsTrialSeed :: Word64
  , tsParametersJson :: Text
  , tsTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data TrialFinished = TrialFinished
  { tfTuneExperimentHash :: Text
  , tfTunePlanId :: Text
  , tfTuneTrial :: Word32
  , tfTuneObjective :: Double
  , tfTunePruned :: Bool
  , tfTuneTranscriptObjectKey :: Text
  , tfTuneTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data SweepFinished = SweepFinished
  { sfExperimentHash :: Text
  , sfPlanId :: Text
  , sfTrialsCompleted :: Word32
  , sfTrialsPruned :: Word32
  , sfTrialsPromoted :: Word32
  , sfBestObjective :: Double
  }
  deriving stock (Eq, Show)

-- | A sweep terminal whose mandatory completion payload has been decoded as a
-- versioned raw DTO and re-refined into an opaque 'CompletedTraining' value.
data SweepCompleted = SweepCompleted
  { scFinished :: SweepFinished
  , scCompletedTraining :: CompletedTraining
  }
  deriving stock (Eq, Show)

completeSweep
  :: SweepFinished
  -> CompletedTraining
  -> Either Text SweepCompleted
completeSweep finished completed = do
  validateSweepFinished finished
  let budget = completedTrainingBudget completed
  if sfPlanId finished /= planIdText (completedTrainingPlanId completed)
    then Left "sweep plan_id does not match completed-training plan identity"
    else
      if trainingBudgetKind budget /= TuningTrialBudget
        then Left "sweep completion requires a tuning-trial budget"
        else
          if fromIntegral (sfTrialsCompleted finished) /= trainingBudgetTargetUnits budget
            then Left "completed sweep trials do not match completed-training target units"
            else
              Right
                SweepCompleted
                  { scFinished = finished
                  , scCompletedTraining = completed
                  }

data TuneCommand
  = TuneStart StartSweep
  | TuneStop StopSweep
  deriving stock (Eq, Show)

data TuneEvent
  = TuneTrialStarted TrialStarted
  | TuneTrialFinished TrialFinished
  | TuneSweepFinished SweepFinished
  | TuneSweepCompleted SweepCompleted
  deriving stock (Eq, Show)

renderTuneCommand :: TuneCommand -> Text
renderTuneCommand command =
  case command of
    TuneStart e ->
      Text.unlines
        [ "kind: StartSweep"
        , "experiment-hash: " <> ssExperimentHash e
        , "dhall-object-key: " <> ssDhallObjectKey e
        , "substrate: " <> renderSubstrate (ssSubstrate e)
        , "sweep-seed: " <> Text.pack (show (ssSweepSeed e))
        , "trial-budget: " <> Text.pack (show (ssTrialBudget e))
        , "budget-per-trial: " <> Text.pack (show (ssBudgetPerTrial e))
        , "sampler: " <> ssSampler e
        , "scheduler: " <> ssScheduler e
        , "pruner: " <> ssPruner e
        , "parallelism: " <> Text.pack (show (ssParallelism e))
        , "promotions: " <> Text.pack (show (ssPromotions e))
        , "plan-id: " <> ssPlanId e
        , "resolved-plan: " <> ssResolvedPlan e
        ]
    TuneStop e ->
      Text.unlines
        [ "kind: StopSweep"
        , "experiment-hash: " <> ssStopExperimentHash e
        ]

parseTuneCommand :: Text -> Maybe TuneCommand
parseTuneCommand payload = do
  fields <- traverse parseField (Text.lines payload)
  kind <- requiredField "kind" fields
  case kind of
    "StartSweep" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "dhall-object-key"
        , "substrate"
        , "sweep-seed"
        , "trial-budget"
        , "budget-per-trial"
        , "sampler"
        , "scheduler"
        , "pruner"
        , "parallelism"
        , "promotions"
        , "plan-id"
        , "resolved-plan"
        ]
        fields
      TuneStart
        <$> ( StartSweep
                <$> requiredField "experiment-hash" fields
                <*> requiredField "dhall-object-key" fields
                <*> (requiredField "substrate" fields >>= parseSubstrate)
                <*> requiredReadField "sweep-seed" fields
                <*> requiredReadField "trial-budget" fields
                <*> requiredReadField "budget-per-trial" fields
                <*> requiredField "sampler" fields
                <*> requiredField "scheduler" fields
                <*> requiredField "pruner" fields
                <*> requiredPositiveReadField "parallelism" fields
                <*> requiredPositiveReadField "promotions" fields
                <*> requiredField "plan-id" fields
                <*> requiredField "resolved-plan" fields
            )
    "StopSweep" -> do
      requireOnlyFields ["kind", "experiment-hash"] fields
      TuneStop . StopSweep
        <$> requiredField "experiment-hash" fields
    _ -> Nothing

encodeTuneCommandProto :: TuneCommand -> ByteString
encodeTuneCommandProto command =
  case command of
    TuneStart start ->
      encodeMessage [messageField 1 (encodeStartSweepProto start)]
    TuneStop stop ->
      encodeMessage [messageField 2 (encodeStopSweepProto stop)]

decodeTuneCommandProto :: ByteString -> Either Text TuneCommand
decodeTuneCommandProto bytes = do
  fields <- decodeMessage bytes
  requireOneOfProtoFields "TuneCommand" [1, 2] fields
  case (fieldMessage 1 fields, fieldMessage 2 fields) of
    (Just startBytes, Nothing) ->
      TuneStart <$> decodeStartSweepProto startBytes
    (Nothing, Just stopBytes) ->
      TuneStop <$> decodeStopSweepProto stopBytes
    _ -> Left "expected exactly one TuneCommand oneof field"

encodeTuneEventProto :: TuneEvent -> ByteString
encodeTuneEventProto event =
  case event of
    TuneTrialStarted started ->
      encodeMessage [messageField 1 (encodeTrialStartedProto started)]
    TuneTrialFinished finished ->
      encodeMessage [messageField 2 (encodeTrialFinishedProto finished)]
    TuneSweepFinished finished ->
      encodeMessage [messageField 3 (encodeSweepFinishedProto finished)]
    TuneSweepCompleted completed ->
      encodeMessage [messageField 4 (encodeSweepCompletedProto completed)]

decodeTuneEventProto :: ByteString -> Either Text TuneEvent
decodeTuneEventProto bytes = do
  fields <- decodeMessage bytes
  requireOneOfProtoFields "TuneEvent" [1, 2, 3, 4] fields
  let body =
        ( fieldMessage 1 fields
        , fieldMessage 2 fields
        , fieldMessage 3 fields
        , fieldMessage 4 fields
        )
  case body of
    (Just startedBytes, Nothing, Nothing, Nothing) ->
      TuneTrialStarted <$> decodeTrialStartedProto startedBytes
    (Nothing, Just finishedBytes, Nothing, Nothing) ->
      TuneTrialFinished <$> decodeTrialFinishedProto finishedBytes
    (Nothing, Nothing, Just finishedBytes, Nothing) ->
      TuneSweepFinished <$> decodeSweepFinishedProto finishedBytes
    (Nothing, Nothing, Nothing, Just completedBytes) ->
      TuneSweepCompleted <$> decodeSweepCompletedProto completedBytes
    _ -> Left "expected exactly one TuneEvent oneof field"

renderTuneEvent :: TuneEvent -> Text
renderTuneEvent envelope =
  case envelope of
    TuneTrialStarted t ->
      Text.unlines
        [ "kind: TrialStarted"
        , "experiment-hash: " <> tsExperimentHash t
        , "plan-id: " <> tsPlanId t
        , "trial: " <> Text.pack (show (tsTrial t))
        , "trial-seed: " <> Text.pack (show (tsTrialSeed t))
        , "parameters-json: " <> tsParametersJson t
        , "timestamp-ns: " <> Text.pack (show (tsTimestampNs t))
        ]
    TuneTrialFinished t ->
      Text.unlines
        [ "kind: TrialFinished"
        , "experiment-hash: " <> tfTuneExperimentHash t
        , "plan-id: " <> tfTunePlanId t
        , "trial: " <> Text.pack (show (tfTuneTrial t))
        , "objective: " <> Text.pack (show (tfTuneObjective t))
        , "pruned: " <> Text.pack (show (tfTunePruned t))
        , "transcript-object-key: " <> tfTuneTranscriptObjectKey t
        , "timestamp-ns: " <> Text.pack (show (tfTuneTimestampNs t))
        ]
    TuneSweepFinished finished ->
      renderSweepFinished "SweepFinished" finished []
    TuneSweepCompleted completed ->
      renderSweepFinished
        "SweepCompleted"
        (scFinished completed)
        [ "completed-training: "
            <> renderCompletedTraining (scCompletedTraining completed)
        ]

-- | Decode exactly one event shape emitted by 'renderTuneEvent'. Scalar
-- duplicates, unknown fields, malformed optional completion evidence, and
-- non-finite objectives are rejected.
parseTuneEvent :: Text -> Maybe TuneEvent
parseTuneEvent payload = do
  fields <- traverse parseField (Text.lines payload)
  kind <- requiredField "kind" fields
  case kind of
    "TrialStarted" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "plan-id"
        , "trial"
        , "trial-seed"
        , "parameters-json"
        , "timestamp-ns"
        ]
        fields
      TuneTrialStarted
        <$> ( TrialStarted
                <$> requiredField "experiment-hash" fields
                <*> requiredField "plan-id" fields
                <*> requiredReadField "trial" fields
                <*> requiredReadField "trial-seed" fields
                <*> requiredField "parameters-json" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "TrialFinished" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "plan-id"
        , "trial"
        , "objective"
        , "pruned"
        , "transcript-object-key"
        , "timestamp-ns"
        ]
        fields
      TuneTrialFinished
        <$> ( TrialFinished
                <$> requiredField "experiment-hash" fields
                <*> requiredField "plan-id" fields
                <*> requiredReadField "trial" fields
                <*> requiredFiniteField "objective" fields
                <*> requiredReadField "pruned" fields
                <*> requiredField "transcript-object-key" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "SweepFinished" -> do
      requireOnlyFields
        [ "kind"
        , "protocol-version"
        , "experiment-hash"
        , "plan-id"
        , "trials-completed"
        , "trials-pruned"
        , "trials-promoted"
        , "best-objective"
        ]
        fields
      requiredTextProtocolVersion fields
      finished <-
        SweepFinished
          <$> requiredField "experiment-hash" fields
          <*> requiredField "plan-id" fields
          <*> requiredReadField "trials-completed" fields
          <*> requiredReadField "trials-pruned" fields
          <*> requiredReadField "trials-promoted" fields
          <*> requiredFiniteField "best-objective" fields
      eitherToMaybe (validateSweepFinished finished)
      pure (TuneSweepFinished finished)
    "SweepCompleted" -> do
      requireOnlyFields
        [ "kind"
        , "protocol-version"
        , "experiment-hash"
        , "plan-id"
        , "trials-completed"
        , "trials-pruned"
        , "trials-promoted"
        , "best-objective"
        , "completed-training"
        ]
        fields
      requiredTextProtocolVersion fields
      finished <-
        SweepFinished
          <$> requiredField "experiment-hash" fields
          <*> requiredField "plan-id" fields
          <*> requiredReadField "trials-completed" fields
          <*> requiredReadField "trials-pruned" fields
          <*> requiredReadField "trials-promoted" fields
          <*> requiredFiniteField "best-objective" fields
      completed <- requiredField "completed-training" fields >>= parseCompletedTraining
      TuneSweepCompleted <$> eitherToMaybe (completeSweep finished completed)
    _ -> Nothing

renderSweepFinished :: Text -> SweepFinished -> [Text] -> Text
renderSweepFinished kind finished extraFields =
  Text.unlines
    ( [ "kind: " <> kind
      , "protocol-version: " <> Text.pack (show protocolVersion)
      , "experiment-hash: " <> sfExperimentHash finished
      , "plan-id: " <> sfPlanId finished
      , "trials-completed: " <> Text.pack (show (sfTrialsCompleted finished))
      , "trials-pruned: " <> Text.pack (show (sfTrialsPruned finished))
      , "trials-promoted: " <> Text.pack (show (sfTrialsPromoted finished))
      , "best-objective: " <> Text.pack (show (sfBestObjective finished))
      ]
        <> extraFields
    )

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack

fieldValues :: Text -> [(Text, Text)] -> [Text]
fieldValues key fields =
  [value | (candidate, value) <- fields, candidate == key]

requiredField :: Text -> [(Text, Text)] -> Maybe Text
requiredField key fields =
  case fieldValues key fields of
    [value]
      | not (Text.null value) -> Just value
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

encodeStartSweepProto :: StartSweep -> ByteString
encodeStartSweepProto start =
  encodeMessage
    [ stringField 1 (ssExperimentHash start)
    , stringField 2 (ssDhallObjectKey start)
    , stringField 3 (renderSubstrate (ssSubstrate start))
    , uint64Field 4 (ssSweepSeed start)
    , uint32Field 5 (ssTrialBudget start)
    , uint32Field 6 (ssBudgetPerTrial start)
    , stringField 7 (ssSampler start)
    , stringField 8 (ssScheduler start)
    , stringField 9 (ssPruner start)
    , uint32Field 10 (ssParallelism start)
    , uint32Field 11 (ssPromotions start)
    , stringField 12 (ssPlanId start)
    , stringField 13 (ssResolvedPlan start)
    ]

decodeStartSweepProto :: ByteString -> Either Text StartSweep
decodeStartSweepProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "StartSweep" [[1 .. 13]] fields
  StartSweep
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "dhall_object_key" (fieldString 2 fields)
    <*> ( require "substrate" (fieldString 3 fields)
            >>= requireParsed "substrate" parseSubstrate
        )
    <*> require "sweep_seed" (fieldWord64 4 fields)
    <*> require "trial_budget" (fieldWord32 5 fields)
    <*> require "budget_per_trial" (fieldWord32 6 fields)
    <*> require "sampler" (fieldString 7 fields)
    <*> require "scheduler" (fieldString 8 fields)
    <*> require "pruner" (fieldString 9 fields)
    <*> requirePositiveWord32 "parallelism" (fieldWord32 10 fields)
    <*> requirePositiveWord32 "promotions" (fieldWord32 11 fields)
    <*> requireNonEmptyText "plan_id" (fieldString 12 fields)
    <*> requireNonEmptyText "resolved_plan" (fieldString 13 fields)

encodeStopSweepProto :: StopSweep -> ByteString
encodeStopSweepProto stop =
  encodeMessage
    [ stringField 1 (ssStopExperimentHash stop)
    ]

decodeStopSweepProto :: ByteString -> Either Text StopSweep
decodeStopSweepProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "StopSweep" [[1]] fields
  StopSweep
    <$> require "experiment_hash" (fieldString 1 fields)

encodeTrialStartedProto :: TrialStarted -> ByteString
encodeTrialStartedProto started =
  encodeMessage
    [ stringField 1 (tsExperimentHash started)
    , uint32Field 2 (tsTrial started)
    , uint64Field 3 (tsTrialSeed started)
    , stringField 4 (tsParametersJson started)
    , uint64Field 5 (tsTimestampNs started)
    , stringField 6 (tsPlanId started)
    ]

decodeTrialStartedProto :: ByteString -> Either Text TrialStarted
decodeTrialStartedProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "TrialStarted" [[1 .. 6]] fields
  TrialStarted
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> requireNonEmptyText "plan_id" (fieldString 6 fields)
    <*> require "trial" (fieldWord32 2 fields)
    <*> require "trial_seed" (fieldWord64 3 fields)
    <*> require "parameters_json" (fieldString 4 fields)
    <*> require "timestamp_ns" (fieldWord64 5 fields)

encodeTrialFinishedProto :: TrialFinished -> ByteString
encodeTrialFinishedProto finished =
  encodeMessage
    [ stringField 1 (tfTuneExperimentHash finished)
    , uint32Field 2 (tfTuneTrial finished)
    , doubleField 3 (tfTuneObjective finished)
    , boolField 4 (tfTunePruned finished)
    , stringField 5 (tfTuneTranscriptObjectKey finished)
    , uint64Field 6 (tfTuneTimestampNs finished)
    , stringField 7 (tfTunePlanId finished)
    ]

decodeTrialFinishedProto :: ByteString -> Either Text TrialFinished
decodeTrialFinishedProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "TrialFinished" [[1 .. 7]] fields
  TrialFinished
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> requireNonEmptyText "plan_id" (fieldString 7 fields)
    <*> require "trial" (fieldWord32 2 fields)
    <*> requireFiniteDouble "objective" (fieldDouble 3 fields)
    <*> require "pruned" (fieldBool 4 fields)
    <*> require "transcript_object_key" (fieldString 5 fields)
    <*> require "timestamp_ns" (fieldWord64 6 fields)

encodeSweepFinishedProto :: SweepFinished -> ByteString
encodeSweepFinishedProto finished =
  encodeMessage
    [ stringField 1 (sfExperimentHash finished)
    , uint32Field 2 (sfTrialsCompleted finished)
    , uint32Field 3 (sfTrialsPruned finished)
    , doubleField 4 (sfBestObjective finished)
    , stringField 6 (sfPlanId finished)
    , uint32Field 7 (sfTrialsPromoted finished)
    , uint32Field 8 protocolVersion
    ]

decodeSweepFinishedProto :: ByteString -> Either Text SweepFinished
decodeSweepFinishedProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "SweepFinished" [[1, 2, 3, 4, 6, 7, 8]] fields
  version <- require "protocol_version" (fieldWord32 8 fields)
  requireProtocolVersion "SweepFinished" version
  finished <-
    SweepFinished
      <$> require "experiment_hash" (fieldString 1 fields)
      <*> requireNonEmptyText "plan_id" (fieldString 6 fields)
      <*> require "trials_completed" (fieldWord32 2 fields)
      <*> require "trials_pruned" (fieldWord32 3 fields)
      <*> require "trials_promoted" (fieldWord32 7 fields)
      <*> requireFiniteDouble "best_objective" (fieldDouble 4 fields)
  validateSweepFinished finished
  Right finished

encodeSweepCompletedProto :: SweepCompleted -> ByteString
encodeSweepCompletedProto completed =
  encodeMessage
    [ uint32Field 1 protocolVersion
    , messageField 2 (encodeSweepFinishedProto (scFinished completed))
    , messageField 3 (encodeCompletedTraining (scCompletedTraining completed))
    ]

decodeSweepCompletedProto :: ByteString -> Either Text SweepCompleted
decodeSweepCompletedProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "SweepCompleted" [[1, 2, 3]] fields
  version <- require "protocol_version" (fieldWord32 1 fields)
  requireProtocolVersion "SweepCompleted" version
  finishedBytes <- require "finished" (fieldMessage 2 fields)
  completionBytes <- require "completed_training" (fieldMessage 3 fields)
  finished <- decodeSweepFinishedProto finishedBytes
  completed <- decodeCompletedTraining completionBytes
  completeSweep finished completed

require :: Text -> Maybe a -> Either Text a
require fieldName =
  maybe (Left ("missing protobuf field: " <> fieldName)) Right

requireParsed :: Text -> (a -> Maybe b) -> a -> Either Text b
requireParsed fieldName parseValue value =
  maybe (Left ("invalid protobuf field: " <> fieldName)) Right (parseValue value)

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

requireFiniteDouble :: Text -> Maybe Double -> Either Text Double
requireFiniteDouble fieldName maybeValue = do
  value <- require fieldName maybeValue
  if finiteDouble value
    then Right value
    else Left ("non-finite protobuf field: " <> fieldName)

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

validateSweepFinished :: SweepFinished -> Either Text ()
validateSweepFinished finished
  | Text.null (Text.strip (sfExperimentHash finished)) =
      Left "empty field: experiment_hash"
  | Text.null (Text.strip (sfPlanId finished)) =
      Left "empty field: plan_id"
  | sfTrialsCompleted finished == 0 =
      Left "sweep requires a positive completed-trial count"
  | sfTrialsPruned finished > sfTrialsCompleted finished =
      Left "pruned trial count exceeds completed trial count"
  | sfTrialsPromoted finished > sfTrialsCompleted finished =
      Left "promoted trial count exceeds completed trial count"
  | not (finiteDouble (sfBestObjective finished)) =
      Left "sweep best objective must be finite"
  | otherwise = Right ()

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe = either (const Nothing) Just

requireOneOfProtoFields :: Text -> [Word64] -> [ProtoField] -> Either Text ()
requireOneOfProtoFields messageName allowed fields =
  case fmap protoFieldNumber fields of
    [fieldNumber]
      | fieldNumber `elem` allowed -> Right ()
    _ -> Left ("expected exactly one " <> messageName <> " oneof field")

requireExactProtoFields :: Text -> [[Word64]] -> [ProtoField] -> Either Text ()
requireExactProtoFields messageName alternatives fields =
  let actual = List.sort (fmap protoFieldNumber fields)
      expected = fmap List.sort alternatives
   in if actual `elem` expected
        then Right ()
        else Left ("unexpected or duplicate protobuf fields in " <> messageName)
