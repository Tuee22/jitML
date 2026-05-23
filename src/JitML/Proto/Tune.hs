{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , SweepDone (..)
  , TrialFinished (..)
  , TrialStarted (..)
  , TuneCommand (..)
  , TuneEvent (..)
  , decodeTuneCommandProto
  , decodeTuneEventProto
  , encodeTuneCommandProto
  , encodeTuneEventProto
  , parseTuneCommand
  , renderTuneCommand
  , renderTuneEvent
  , tuneCommandTopic
  , tuneEventTopic
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
  }
  deriving stock (Eq, Show)

newtype StopSweep = StopSweep
  { ssStopExperimentHash :: Text
  }
  deriving stock (Eq, Show)

data TrialStarted = TrialStarted
  { tsExperimentHash :: Text
  , tsTrial :: Word32
  , tsTrialSeed :: Word64
  , tsParametersJson :: Text
  , tsTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data TrialFinished = TrialFinished
  { tfTuneExperimentHash :: Text
  , tfTuneTrial :: Word32
  , tfTuneObjective :: Double
  , tfTunePruned :: Bool
  , tfTuneTranscriptObjectKey :: Text
  , tfTuneTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data SweepDone = SweepDone
  { sdExperimentHash :: Text
  , sdTrialsCompleted :: Word32
  , sdTrialsPruned :: Word32
  , sdBestObjective :: Double
  }
  deriving stock (Eq, Show)

data TuneCommand
  = TuneStart StartSweep
  | TuneStop StopSweep
  deriving stock (Eq, Show)

data TuneEvent
  = TuneTrialStarted TrialStarted
  | TuneTrialFinished TrialFinished
  | TuneSweepDone SweepDone
  deriving stock (Eq, Show)

tuneCommandTopic :: Substrate -> Text
tuneCommandTopic substrate = "tune.command." <> renderSubstrate substrate

tuneEventTopic :: Substrate -> Text
tuneEventTopic substrate = "tune.event." <> renderSubstrate substrate

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
        ]
    TuneStop e ->
      Text.unlines
        [ "kind: StopSweep"
        , "experiment-hash: " <> ssStopExperimentHash e
        ]

parseTuneCommand :: Text -> Maybe TuneCommand
parseTuneCommand payload =
  let fields = mapMaybe parseField (Text.lines payload)
      value key = lookup key fields
   in case value "kind" of
        Just "StartSweep" ->
          TuneStart
            <$> ( StartSweep
                    <$> value "experiment-hash"
                    <*> value "dhall-object-key"
                    <*> (value "substrate" >>= parseSubstrate)
                    <*> (value "sweep-seed" >>= readText)
                    <*> (value "trial-budget" >>= readText)
                    <*> (value "budget-per-trial" >>= readText)
                    <*> value "sampler"
                    <*> value "scheduler"
                    <*> value "pruner"
                )
        Just "StopSweep" ->
          TuneStop . StopSweep
            <$> value "experiment-hash"
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
    TuneSweepDone done ->
      encodeMessage [messageField 3 (encodeSweepDoneProto done)]

decodeTuneEventProto :: ByteString -> Either Text TuneEvent
decodeTuneEventProto bytes = do
  fields <- decodeMessage bytes
  let body =
        ( fieldMessage 1 fields
        , fieldMessage 2 fields
        , fieldMessage 3 fields
        )
  case body of
    (Just startedBytes, Nothing, Nothing) ->
      TuneTrialStarted <$> decodeTrialStartedProto startedBytes
    (Nothing, Just finishedBytes, Nothing) ->
      TuneTrialFinished <$> decodeTrialFinishedProto finishedBytes
    (Nothing, Nothing, Just doneBytes) ->
      TuneSweepDone <$> decodeSweepDoneProto doneBytes
    _ -> Left "expected exactly one TuneEvent oneof field"

renderTuneEvent :: TuneEvent -> Text
renderTuneEvent envelope =
  case envelope of
    TuneTrialStarted t ->
      Text.unlines
        [ "kind: TrialStarted"
        , "experiment-hash: " <> tsExperimentHash t
        , "trial: " <> Text.pack (show (tsTrial t))
        , "trial-seed: " <> Text.pack (show (tsTrialSeed t))
        , "parameters-json: " <> tsParametersJson t
        ]
    TuneTrialFinished t ->
      Text.unlines
        [ "kind: TrialFinished"
        , "experiment-hash: " <> tfTuneExperimentHash t
        , "trial: " <> Text.pack (show (tfTuneTrial t))
        , "objective: " <> Text.pack (show (tfTuneObjective t))
        , "pruned: " <> Text.pack (show (tfTunePruned t))
        , "transcript-object-key: " <> tfTuneTranscriptObjectKey t
        ]
    TuneSweepDone d ->
      Text.unlines
        [ "kind: SweepDone"
        , "experiment-hash: " <> sdExperimentHash d
        , "trials-completed: " <> Text.pack (show (sdTrialsCompleted d))
        , "trials-pruned: " <> Text.pack (show (sdTrialsPruned d))
        , "best-objective: " <> Text.pack (show (sdBestObjective d))
        ]

parseField :: Text -> Maybe (Text, Text)
parseField line =
  let (key, rest) = Text.breakOn ":" line
   in if Text.null rest
        then Nothing
        else Just (Text.strip key, Text.strip (Text.drop 1 rest))

readText :: (Read a) => Text -> Maybe a
readText =
  readMaybe . Text.unpack

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
    ]

decodeStartSweepProto :: ByteString -> Either Text StartSweep
decodeStartSweepProto bytes = do
  fields <- decodeMessage bytes
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

encodeStopSweepProto :: StopSweep -> ByteString
encodeStopSweepProto stop =
  encodeMessage
    [ stringField 1 (ssStopExperimentHash stop)
    ]

decodeStopSweepProto :: ByteString -> Either Text StopSweep
decodeStopSweepProto bytes = do
  fields <- decodeMessage bytes
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
    ]

decodeTrialStartedProto :: ByteString -> Either Text TrialStarted
decodeTrialStartedProto bytes = do
  fields <- decodeMessage bytes
  TrialStarted
    <$> require "experiment_hash" (fieldString 1 fields)
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
    ]

decodeTrialFinishedProto :: ByteString -> Either Text TrialFinished
decodeTrialFinishedProto bytes = do
  fields <- decodeMessage bytes
  TrialFinished
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "trial" (fieldWord32 2 fields)
    <*> require "objective" (fieldDouble 3 fields)
    <*> require "pruned" (fieldBool 4 fields)
    <*> require "transcript_object_key" (fieldString 5 fields)
    <*> require "timestamp_ns" (fieldWord64 6 fields)

encodeSweepDoneProto :: SweepDone -> ByteString
encodeSweepDoneProto done =
  encodeMessage
    [ stringField 1 (sdExperimentHash done)
    , uint32Field 2 (sdTrialsCompleted done)
    , uint32Field 3 (sdTrialsPruned done)
    , doubleField 4 (sdBestObjective done)
    ]

decodeSweepDoneProto :: ByteString -> Either Text SweepDone
decodeSweepDoneProto bytes = do
  fields <- decodeMessage bytes
  SweepDone
    <$> require "experiment_hash" (fieldString 1 fields)
    <*> require "trials_completed" (fieldWord32 2 fields)
    <*> require "trials_pruned" (fieldWord32 3 fields)
    <*> require "best_objective" (fieldDouble 4 fields)

require :: Text -> Maybe a -> Either Text a
require fieldName =
  maybe (Left ("missing protobuf field: " <> fieldName)) Right

requireParsed :: Text -> (a -> Maybe b) -> a -> Either Text b
requireParsed fieldName parseValue value =
  maybe (Left ("invalid protobuf field: " <> fieldName)) Right (parseValue value)
