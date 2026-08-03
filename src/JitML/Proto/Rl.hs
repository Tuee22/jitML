{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Rl
  ( ArenaCompleted (..)
  , CheckpointDoneRL (..)
  , CompletedCheckpointDoneRL
  , ccdrlCheckpoint
  , ccdrlCompletedTraining
  , completeCheckpointDoneRL
  , EvaluationOutcome (..)
  , GenerationCompleted (..)
  , IterationSummary (..)
  , MetricUpdate (..)
  , RlAnimationFrame (..)
  , RlCommand (..)
  , RlEvent (..)
  , RlReplayFrame (..)
  , StartAlphaZeroRun (..)
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
  )
where

import Data.ByteString (ByteString)
import Data.List qualified as List
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
import JitML.Training.Budget
  ( CompletedTraining
  , completedTrainingObservedUnits
  , decodeCompletedTraining
  , encodeCompletedTraining
  , parseCompletedTraining
  , renderCompletedTraining
  )

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

-- | The AlphaZero command has its own dimensional budget vocabulary. These are
-- raw wire quantities; semantic positivity and cross-field validation happen
-- at the resolved-plan boundary before worker execution.
data StartAlphaZeroRun = StartAlphaZeroRun
  { sazSubstrate :: Substrate
  , sazExperimentHash :: Text
  , sazPlanId :: Text
  , sazResolvedPlan :: Text
  , sazGame :: Text
  , sazGenerations :: Word32
  , sazSelfPlayGames :: Word32
  , sazMctsSimulationsPerMove :: Word32
  , sazMaxPlies :: Word32
  , sazOptimizerUpdates :: Word32
  , sazArenaGames :: Word32
  , sazSeed :: Word64
  }
  deriving stock (Eq, Show)

data StopRLRun = StopRLRun
  { srStopExperimentHash :: Text
  , srStopDrain :: Bool
  }
  deriving stock (Eq, Show)

data EvaluationOutcome = EvaluationOutcome
  { eoPlanId :: Text
  , eoExperimentHash :: Text
  , eoEpisodeId :: Word64
  , eoReward :: Double
  , eoSteps :: Word64
  , eoDone :: Bool
  , eoTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data IterationSummary = IterationSummary
  { isPlanId :: Text
  , isExperimentHash :: Text
  , isIteration :: Word64
  , isMetricName :: Text
  , isMetricValue :: Double
  , isTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data CheckpointDoneRL = CheckpointDoneRL
  { cdrlExperimentHash :: Text
  , cdrlManifestSha :: Text
  , cdrlStep :: Word64
  , cdrlPointerKey :: Text
  }
  deriving stock (Eq, Show)

-- | An RL checkpoint whose mandatory completion payload has survived raw DTO
-- refinement. Candidate checkpoints remain a separate event variant.
data CompletedCheckpointDoneRL = CompletedCheckpointDoneRL
  { ccdrlCheckpoint :: CheckpointDoneRL
  , ccdrlCompletedTraining :: CompletedTraining
  }
  deriving stock (Eq, Show)

completeCheckpointDoneRL
  :: CheckpointDoneRL
  -> CompletedTraining
  -> Either Text CompletedCheckpointDoneRL
completeCheckpointDoneRL checkpoint completed = do
  validateCheckpointDoneRL checkpoint
  if cdrlStep checkpoint /= completedTrainingObservedUnits completed
    then Left "RL checkpoint step does not match completed-training observed units"
    else
      Right
        CompletedCheckpointDoneRL
          { ccdrlCheckpoint = checkpoint
          , ccdrlCompletedTraining = completed
          }

data MetricUpdate = MetricUpdate
  { muPlanId :: Text
  , muExperimentHash :: Text
  , muName :: Text
  , muValue :: Double
  , muTimestampNs :: Word64
  }
  deriving stock (Eq, Show)

data GenerationCompleted = GenerationCompleted
  { gcPlanId :: Text
  , gcExperimentHash :: Text
  , gcGeneration :: Word32
  , gcSelfPlayGames :: Word32
  , gcSamples :: Word64
  }
  deriving stock (Eq, Show)

data ArenaCompleted = ArenaCompleted
  { acPlanId :: Text
  , acExperimentHash :: Text
  , acArenaGames :: Word32
  , acWinRate :: Double
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
  | RlStartAlphaZero StartAlphaZeroRun
  deriving stock (Eq, Show)

data RlEvent
  = RlEvaluation EvaluationOutcome
  | RlIteration IterationSummary
  | RlCheckpoint CheckpointDoneRL
  | RlCompletedCheckpoint CompletedCheckpointDoneRL
  | RlMetric MetricUpdate
  | RlAnimation RlAnimationFrame
  | RlReplay RlReplayFrame
  | RlGenerationCompleted GenerationCompleted
  | RlArenaCompleted ArenaCompleted
  deriving stock (Eq, Show)

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
    RlStartAlphaZero e ->
      Text.unlines
        [ "kind: StartAlphaZeroRun"
        , "substrate: " <> renderSubstrate (sazSubstrate e)
        , "experiment-hash: " <> sazExperimentHash e
        , "plan-id: " <> sazPlanId e
        , "resolved-plan: " <> sazResolvedPlan e
        , "game: " <> sazGame e
        , "generations: " <> Text.pack (show (sazGenerations e))
        , "self-play-games: " <> Text.pack (show (sazSelfPlayGames e))
        , "mcts-simulations-per-move: " <> Text.pack (show (sazMctsSimulationsPerMove e))
        , "max-plies: " <> Text.pack (show (sazMaxPlies e))
        , "optimizer-updates: " <> Text.pack (show (sazOptimizerUpdates e))
        , "arena-games: " <> Text.pack (show (sazArenaGames e))
        , "seed: " <> Text.pack (show (sazSeed e))
        ]

parseRlCommand :: Text -> Maybe RlCommand
parseRlCommand payload = do
  fields <- traverse parseField (Text.lines payload)
  kind <- requiredField "kind" fields
  case kind of
    "StartRLRun" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "algorithm"
        , "environment"
        , "substrate"
        , "seed"
        , "max-steps"
        , "eval-episodes"
        ]
        fields
      RlStart
        <$> ( StartRLRun
                <$> requiredField "experiment-hash" fields
                <*> requiredField "algorithm" fields
                <*> requiredField "environment" fields
                <*> (requiredField "substrate" fields >>= parseSubstrate)
                <*> requiredReadField "seed" fields
                <*> requiredReadField "max-steps" fields
                <*> requiredReadField "eval-episodes" fields
            )
    "StopRLRun" -> do
      requireOnlyFields ["kind", "experiment-hash", "drain"] fields
      RlStop
        <$> ( StopRLRun
                <$> requiredField "experiment-hash" fields
                <*> requiredReadField "drain" fields
            )
    "StartAlphaZeroRun" -> do
      requireOnlyFields
        [ "kind"
        , "substrate"
        , "experiment-hash"
        , "plan-id"
        , "resolved-plan"
        , "game"
        , "generations"
        , "self-play-games"
        , "mcts-simulations-per-move"
        , "max-plies"
        , "optimizer-updates"
        , "arena-games"
        , "seed"
        ]
        fields
      RlStartAlphaZero
        <$> ( StartAlphaZeroRun
                <$> (requiredField "substrate" fields >>= parseSubstrate)
                <*> requiredField "experiment-hash" fields
                <*> requiredField "plan-id" fields
                <*> requiredField "resolved-plan" fields
                <*> requiredField "game" fields
                <*> requiredReadField "generations" fields
                <*> requiredReadField "self-play-games" fields
                <*> requiredReadField "mcts-simulations-per-move" fields
                <*> requiredReadField "max-plies" fields
                <*> requiredReadField "optimizer-updates" fields
                <*> requiredReadField "arena-games" fields
                <*> requiredReadField "seed" fields
            )
    _ -> Nothing

encodeRlCommandProto :: RlCommand -> ByteString
encodeRlCommandProto command =
  case command of
    RlStart start ->
      encodeMessage [messageField 1 (encodeStartRLRunProto start)]
    RlStop stop ->
      encodeMessage [messageField 2 (encodeStopRLRunProto stop)]
    RlStartAlphaZero start ->
      encodeMessage [messageField 3 (encodeStartAlphaZeroRunProto start)]

decodeRlCommandProto :: ByteString -> Either Text RlCommand
decodeRlCommandProto bytes = do
  fields <- decodeMessage bytes
  case fields of
    [ProtoField 1 (LengthDelimited startBytes)] ->
      RlStart <$> decodeStartRLRunProto startBytes
    [ProtoField 2 (LengthDelimited stopBytes)] ->
      RlStop <$> decodeStopRLRunProto stopBytes
    [ProtoField 3 (LengthDelimited startBytes)] ->
      RlStartAlphaZero <$> decodeStartAlphaZeroRunProto startBytes
    [ProtoField fieldNumber _]
      | fieldNumber `elem` [1, 2, 3] ->
          Left "RlCommand oneof body has the wrong protobuf wire type"
    _ -> Left "expected exactly one RlCommand oneof field"

encodeRlEventProto :: RlEvent -> ByteString
encodeRlEventProto event =
  case event of
    RlEvaluation outcome ->
      encodeMessage [messageField 1 (encodeEvaluationOutcomeProto outcome)]
    RlIteration summary ->
      encodeMessage [messageField 2 (encodeIterationSummaryProto summary)]
    RlCheckpoint checkpoint ->
      encodeMessage [messageField 3 (encodeCheckpointDoneRLProto checkpoint)]
    RlCompletedCheckpoint completed ->
      encodeMessage [messageField 9 (encodeCompletedCheckpointDoneRLProto completed)]
    RlMetric metric ->
      encodeMessage [messageField 4 (encodeMetricUpdateProto metric)]
    RlAnimation frame ->
      encodeMessage [messageField 5 (encodeRlAnimationFrameProto frame)]
    RlReplay frame ->
      encodeMessage [messageField 6 (encodeRlReplayFrameProto frame)]
    RlGenerationCompleted generation ->
      encodeMessage [messageField 7 (encodeGenerationCompletedProto generation)]
    RlArenaCompleted arena ->
      encodeMessage [messageField 8 (encodeArenaCompletedProto arena)]

decodeRlEventProto :: ByteString -> Either Text RlEvent
decodeRlEventProto bytes = do
  fields <- decodeMessage bytes
  case fields of
    [ProtoField 1 (LengthDelimited outcomeBytes)] ->
      RlEvaluation <$> decodeEvaluationOutcomeProto outcomeBytes
    [ProtoField 2 (LengthDelimited summaryBytes)] ->
      RlIteration <$> decodeIterationSummaryProto summaryBytes
    [ProtoField 3 (LengthDelimited checkpointBytes)] ->
      RlCheckpoint <$> decodeCheckpointDoneRLProto checkpointBytes
    [ProtoField 4 (LengthDelimited metricBytes)] ->
      RlMetric <$> decodeMetricUpdateProto metricBytes
    [ProtoField 5 (LengthDelimited frameBytes)] ->
      RlAnimation <$> decodeRlAnimationFrameProto frameBytes
    [ProtoField 6 (LengthDelimited frameBytes)] ->
      RlReplay <$> decodeRlReplayFrameProto frameBytes
    [ProtoField 7 (LengthDelimited generationBytes)] ->
      RlGenerationCompleted <$> decodeGenerationCompletedProto generationBytes
    [ProtoField 8 (LengthDelimited arenaBytes)] ->
      RlArenaCompleted <$> decodeArenaCompletedProto arenaBytes
    [ProtoField 9 (LengthDelimited completedBytes)] ->
      RlCompletedCheckpoint <$> decodeCompletedCheckpointDoneRLProto completedBytes
    [ProtoField fieldNumber _]
      | fieldNumber `elem` [1 .. 9] ->
          Left "RlEvent oneof body has the wrong protobuf wire type"
    _ -> Left "expected exactly one RlEvent oneof field"

renderRlEvent :: RlEvent -> Text
renderRlEvent envelope =
  case envelope of
    RlEvaluation e ->
      Text.unlines
        [ "kind: EvaluationOutcome"
        , "plan-id: " <> eoPlanId e
        , "experiment-hash: " <> eoExperimentHash e
        , "episode-id: " <> Text.pack (show (eoEpisodeId e))
        , "reward: " <> Text.pack (show (eoReward e))
        , "steps: " <> Text.pack (show (eoSteps e))
        , "done: " <> Text.pack (show (eoDone e))
        , "timestamp-ns: " <> Text.pack (show (eoTimestampNs e))
        ]
    RlIteration e ->
      Text.unlines
        [ "kind: IterationSummary"
        , "plan-id: " <> isPlanId e
        , "experiment-hash: " <> isExperimentHash e
        , "iteration: " <> Text.pack (show (isIteration e))
        , "metric-name: " <> isMetricName e
        , "metric-value: " <> Text.pack (show (isMetricValue e))
        , "timestamp-ns: " <> Text.pack (show (isTimestampNs e))
        ]
    RlCheckpoint c ->
      renderCheckpointDoneRL "CheckpointCandidateRL" c []
    RlCompletedCheckpoint completed ->
      renderCheckpointDoneRL
        "CheckpointCompletedRL"
        (ccdrlCheckpoint completed)
        [ "completed-training: "
            <> renderCompletedTraining (ccdrlCompletedTraining completed)
        ]
    RlMetric m ->
      Text.unlines
        [ "kind: MetricUpdate"
        , "plan-id: " <> muPlanId m
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
    RlGenerationCompleted generation ->
      Text.unlines
        [ "kind: GenerationCompleted"
        , "plan-id: " <> gcPlanId generation
        , "experiment-hash: " <> gcExperimentHash generation
        , "generation: " <> Text.pack (show (gcGeneration generation))
        , "self-play-games: " <> Text.pack (show (gcSelfPlayGames generation))
        , "samples: " <> Text.pack (show (gcSamples generation))
        ]
    RlArenaCompleted arena ->
      Text.unlines
        [ "kind: ArenaCompleted"
        , "plan-id: " <> acPlanId arena
        , "experiment-hash: " <> acExperimentHash arena
        , "arena-games: " <> Text.pack (show (acArenaGames arena))
        , "win-rate: " <> Text.pack (show (acWinRate arena))
        ]

parseRlEvent :: Text -> Maybe RlEvent
parseRlEvent payload = do
  fields <- traverse parseField (Text.lines payload)
  kind <- requiredField "kind" fields
  case kind of
    "EvaluationOutcome" -> do
      requireOnlyFields
        [ "kind"
        , "plan-id"
        , "experiment-hash"
        , "episode-id"
        , "reward"
        , "steps"
        , "done"
        , "timestamp-ns"
        ]
        fields
      RlEvaluation
        <$> ( EvaluationOutcome
                <$> requiredField "plan-id" fields
                <*> requiredField "experiment-hash" fields
                <*> requiredReadField "episode-id" fields
                <*> requiredFiniteField "reward" fields
                <*> requiredPositiveWord64Field "steps" fields
                <*> requiredReadField "done" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "IterationSummary" -> do
      requireOnlyFields
        [ "kind"
        , "plan-id"
        , "experiment-hash"
        , "iteration"
        , "metric-name"
        , "metric-value"
        , "timestamp-ns"
        ]
        fields
      RlIteration
        <$> ( IterationSummary
                <$> requiredField "plan-id" fields
                <*> requiredField "experiment-hash" fields
                <*> requiredReadField "iteration" fields
                <*> requiredField "metric-name" fields
                <*> requiredFiniteField "metric-value" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "CheckpointCandidateRL" -> do
      requireOnlyFields
        [ "kind"
        , "protocol-version"
        , "experiment-hash"
        , "manifest-sha"
        , "step"
        , "pointer-key"
        ]
        fields
      requiredTextProtocolVersion fields
      checkpoint <-
        CheckpointDoneRL
          <$> requiredField "experiment-hash" fields
          <*> requiredField "manifest-sha" fields
          <*> requiredReadField "step" fields
          <*> requiredField "pointer-key" fields
      eitherToMaybe (validateCheckpointDoneRL checkpoint)
      pure (RlCheckpoint checkpoint)
    "CheckpointCompletedRL" -> do
      requireOnlyFields
        [ "kind"
        , "protocol-version"
        , "experiment-hash"
        , "manifest-sha"
        , "step"
        , "pointer-key"
        , "completed-training"
        ]
        fields
      requiredTextProtocolVersion fields
      checkpoint <-
        CheckpointDoneRL
          <$> requiredField "experiment-hash" fields
          <*> requiredField "manifest-sha" fields
          <*> requiredReadField "step" fields
          <*> requiredField "pointer-key" fields
      completed <- requiredField "completed-training" fields >>= parseCompletedTraining
      RlCompletedCheckpoint
        <$> eitherToMaybe (completeCheckpointDoneRL checkpoint completed)
    "MetricUpdate" -> do
      requireOnlyFields
        [ "kind"
        , "plan-id"
        , "experiment-hash"
        , "name"
        , "value"
        , "timestamp-ns"
        ]
        fields
      RlMetric
        <$> ( MetricUpdate
                <$> requiredField "plan-id" fields
                <*> requiredField "experiment-hash" fields
                <*> requiredField "name" fields
                <*> requiredFiniteField "value" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "RlAnimationFrame" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "environment"
        , "episode"
        , "step"
        , "reward"
        , "done"
        , "action"
        , "observation"
        , "action-probabilities"
        , "observation-hash"
        , "replay-cursor"
        , "timestamp-ns"
        ]
        fields
      RlAnimation
        <$> ( RlAnimationFrame
                <$> requiredField "experiment-hash" fields
                <*> requiredField "environment" fields
                <*> requiredReadField "episode" fields
                <*> requiredReadField "step" fields
                <*> requiredFiniteField "reward" fields
                <*> requiredReadField "done" fields
                <*> requiredReadField "action" fields
                <*> requiredDoubleListField "observation" fields
                <*> requiredDoubleListField "action-probabilities" fields
                <*> requiredReadField "observation-hash" fields
                <*> requiredReadField "replay-cursor" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "RlReplayFrame" -> do
      requireOnlyFields
        [ "kind"
        , "experiment-hash"
        , "replay-id"
        , "environment"
        , "episode"
        , "step"
        , "action"
        , "reward"
        , "done"
        , "observation"
        , "next-observation"
        , "policy-version"
        , "observation-hash"
        , "timestamp-ns"
        ]
        fields
      RlReplay
        <$> ( RlReplayFrame
                <$> requiredField "experiment-hash" fields
                <*> requiredField "replay-id" fields
                <*> requiredField "environment" fields
                <*> requiredReadField "episode" fields
                <*> requiredReadField "step" fields
                <*> requiredReadField "action" fields
                <*> requiredFiniteField "reward" fields
                <*> requiredReadField "done" fields
                <*> requiredDoubleListField "observation" fields
                <*> requiredDoubleListField "next-observation" fields
                <*> requiredReadField "policy-version" fields
                <*> requiredReadField "observation-hash" fields
                <*> requiredReadField "timestamp-ns" fields
            )
    "GenerationCompleted" -> do
      requireOnlyFields
        [ "kind"
        , "plan-id"
        , "experiment-hash"
        , "generation"
        , "self-play-games"
        , "samples"
        ]
        fields
      RlGenerationCompleted
        <$> ( GenerationCompleted
                <$> requiredField "plan-id" fields
                <*> requiredField "experiment-hash" fields
                <*> requiredReadField "generation" fields
                <*> requiredReadField "self-play-games" fields
                <*> requiredReadField "samples" fields
            )
    "ArenaCompleted" -> do
      requireOnlyFields
        [ "kind"
        , "plan-id"
        , "experiment-hash"
        , "arena-games"
        , "win-rate"
        ]
        fields
      RlArenaCompleted
        <$> ( ArenaCompleted
                <$> requiredField "plan-id" fields
                <*> requiredField "experiment-hash" fields
                <*> requiredReadField "arena-games" fields
                <*> requiredFiniteField "win-rate" fields
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

renderCheckpointDoneRL :: Text -> CheckpointDoneRL -> [Text] -> Text
renderCheckpointDoneRL kind checkpoint extraFields =
  Text.unlines
    ( [ "kind: " <> kind
      , "protocol-version: " <> Text.pack (show protocolVersion)
      , "experiment-hash: " <> cdrlExperimentHash checkpoint
      , "manifest-sha: " <> cdrlManifestSha checkpoint
      , "step: " <> Text.pack (show (cdrlStep checkpoint))
      , "pointer-key: " <> cdrlPointerKey checkpoint
      ]
        <> extraFields
    )

parseDoubleList :: Text -> Maybe [Double]
parseDoubleList raw
  | Text.null (Text.strip raw) = Just []
  | otherwise = traverse readFiniteDouble (Text.splitOn "," raw)

fieldValues :: Text -> [(Text, Text)] -> [Text]
fieldValues key fields =
  [value | (candidate, value) <- fields, candidate == key]

uniqueField :: Text -> [(Text, Text)] -> Maybe Text
uniqueField key fields =
  case fieldValues key fields of
    [value] -> Just value
    _ -> Nothing

requiredField :: Text -> [(Text, Text)] -> Maybe Text
requiredField key fields = do
  value <- uniqueField key fields
  if Text.null value then Nothing else Just value

requiredReadField :: (Read value) => Text -> [(Text, Text)] -> Maybe value
requiredReadField key fields =
  requiredField key fields >>= readText

requiredPositiveWord64Field :: Text -> [(Text, Text)] -> Maybe Word64
requiredPositiveWord64Field key fields = do
  value <- requiredReadField key fields
  if value == 0 then Nothing else Just value

requiredFiniteField :: Text -> [(Text, Text)] -> Maybe Double
requiredFiniteField key fields =
  requiredField key fields >>= readFiniteDouble

requiredTextProtocolVersion :: [(Text, Text)] -> Maybe ()
requiredTextProtocolVersion fields = do
  version <- requiredReadField "protocol-version" fields
  if version == protocolVersion then Just () else Nothing

requiredDoubleListField :: Text -> [(Text, Text)] -> Maybe [Double]
requiredDoubleListField key fields =
  uniqueField key fields >>= parseDoubleList

readFiniteDouble :: Text -> Maybe Double
readFiniteDouble encoded = do
  value <- readText encoded
  if finiteDouble value then Just value else Nothing

finiteDouble :: Double -> Bool
finiteDouble value =
  not (isNaN value || isInfinite value)

requireOnlyFields :: [Text] -> [(Text, Text)] -> Maybe ()
requireOnlyFields allowed fields
  | all ((`elem` allowed) . fst) fields = Just ()
  | otherwise = Nothing

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
  requireExactProtoFields "StartRLRun" [1 .. 7] fields
  StartRLRun
    <$> requireNonEmptyProtoString "experiment_hash" (fieldString 1 fields)
    <*> requireNonEmptyProtoString "algorithm" (fieldString 2 fields)
    <*> requireNonEmptyProtoString "environment" (fieldString 3 fields)
    <*> ( require "substrate" (fieldString 4 fields)
            >>= requireParsed "substrate" parseSubstrate
        )
    <*> require "seed" (fieldWord64 5 fields)
    <*> require "max_steps" (fieldWord32 6 fields)
    <*> require "eval_episodes" (fieldWord32 7 fields)

encodeStartAlphaZeroRunProto :: StartAlphaZeroRun -> ByteString
encodeStartAlphaZeroRunProto start =
  encodeMessage
    [ stringField 1 (renderSubstrate (sazSubstrate start))
    , stringField 2 (sazExperimentHash start)
    , stringField 3 (sazPlanId start)
    , stringField 4 (sazResolvedPlan start)
    , stringField 5 (sazGame start)
    , uint32Field 6 (sazGenerations start)
    , uint32Field 7 (sazSelfPlayGames start)
    , uint32Field 8 (sazMctsSimulationsPerMove start)
    , uint32Field 9 (sazMaxPlies start)
    , uint32Field 10 (sazOptimizerUpdates start)
    , uint32Field 11 (sazArenaGames start)
    , uint64Field 12 (sazSeed start)
    ]

decodeStartAlphaZeroRunProto :: ByteString -> Either Text StartAlphaZeroRun
decodeStartAlphaZeroRunProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "StartAlphaZeroRun" [1 .. 12] fields
  StartAlphaZeroRun
    <$> ( require "substrate" (fieldString 1 fields)
            >>= requireParsed "substrate" parseSubstrate
        )
    <*> requireNonEmptyProtoString "experiment_hash" (fieldString 2 fields)
    <*> requireNonEmptyProtoString "plan_id" (fieldString 3 fields)
    <*> requireNonEmptyProtoString "resolved_plan" (fieldString 4 fields)
    <*> requireNonEmptyProtoString "game" (fieldString 5 fields)
    <*> require "generations" (fieldWord32 6 fields)
    <*> require "self_play_games" (fieldWord32 7 fields)
    <*> require "mcts_simulations_per_move" (fieldWord32 8 fields)
    <*> require "max_plies" (fieldWord32 9 fields)
    <*> require "optimizer_updates" (fieldWord32 10 fields)
    <*> require "arena_games" (fieldWord32 11 fields)
    <*> require "seed" (fieldWord64 12 fields)

encodeStopRLRunProto :: StopRLRun -> ByteString
encodeStopRLRunProto stop =
  encodeMessage
    [ stringField 1 (srStopExperimentHash stop)
    , boolField 2 (srStopDrain stop)
    ]

decodeStopRLRunProto :: ByteString -> Either Text StopRLRun
decodeStopRLRunProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "StopRLRun" [1, 2] fields
  StopRLRun
    <$> requireNonEmptyProtoString "experiment_hash" (fieldString 1 fields)
    <*> require "drain" (fieldBool 2 fields)

encodeEvaluationOutcomeProto :: EvaluationOutcome -> ByteString
encodeEvaluationOutcomeProto outcome =
  encodeMessage
    [ stringField 1 (eoPlanId outcome)
    , stringField 2 (eoExperimentHash outcome)
    , uint64Field 3 (eoEpisodeId outcome)
    , doubleField 4 (eoReward outcome)
    , uint64Field 5 (eoSteps outcome)
    , boolField 6 (eoDone outcome)
    , uint64Field 7 (eoTimestampNs outcome)
    ]

decodeEvaluationOutcomeProto :: ByteString -> Either Text EvaluationOutcome
decodeEvaluationOutcomeProto bytes = do
  fields <- decodeMessage bytes
  requireKnownUniqueProtoFields "EvaluationOutcome" [1 .. 7] fields
  planId <- requireNonEmptyProtoString "plan_id" (fieldString 1 fields)
  experimentHash <-
    requireNonEmptyProtoString "experiment_hash" (fieldString 2 fields)
  episodeId <-
    proto3ScalarField "episode_id" 3 0 (fieldWord64 3 fields) fields
  rewardValue <-
    proto3ScalarField "reward" 4 0.0 (fieldDouble 4 fields) fields
      >>= requireFiniteProtoDouble "reward" . Just
  stepsValue <-
    proto3ScalarField "steps" 5 0 (fieldWord64 5 fields) fields
      >>= requirePositiveProtoWord64 "steps" . Just
  doneValue <-
    proto3ScalarField "done" 6 False (fieldBool 6 fields) fields
  timestampNs <-
    proto3ScalarField "timestamp_ns" 7 0 (fieldWord64 7 fields) fields
  pure
    EvaluationOutcome
      { eoPlanId = planId
      , eoExperimentHash = experimentHash
      , eoEpisodeId = episodeId
      , eoReward = rewardValue
      , eoSteps = stepsValue
      , eoDone = doneValue
      , eoTimestampNs = timestampNs
      }

encodeIterationSummaryProto :: IterationSummary -> ByteString
encodeIterationSummaryProto summary =
  encodeMessage
    [ stringField 1 (isPlanId summary)
    , stringField 2 (isExperimentHash summary)
    , uint64Field 3 (isIteration summary)
    , stringField 4 (isMetricName summary)
    , doubleField 5 (isMetricValue summary)
    , uint64Field 6 (isTimestampNs summary)
    ]

decodeIterationSummaryProto :: ByteString -> Either Text IterationSummary
decodeIterationSummaryProto bytes = do
  fields <- decodeMessage bytes
  requireKnownUniqueProtoFields "IterationSummary" [1 .. 6] fields
  planId <- requireNonEmptyProtoString "plan_id" (fieldString 1 fields)
  experimentHash <-
    requireNonEmptyProtoString "experiment_hash" (fieldString 2 fields)
  iterationValue <-
    proto3ScalarField "iteration" 3 0 (fieldWord64 3 fields) fields
  metricName <-
    requireNonEmptyProtoString "metric_name" (fieldString 4 fields)
  metricValue <-
    proto3ScalarField "metric_value" 5 0.0 (fieldDouble 5 fields) fields
      >>= requireFiniteProtoDouble "metric_value" . Just
  timestampNs <-
    proto3ScalarField "timestamp_ns" 6 0 (fieldWord64 6 fields) fields
  pure
    IterationSummary
      { isPlanId = planId
      , isExperimentHash = experimentHash
      , isIteration = iterationValue
      , isMetricName = metricName
      , isMetricValue = metricValue
      , isTimestampNs = timestampNs
      }

encodeCheckpointDoneRLProto :: CheckpointDoneRL -> ByteString
encodeCheckpointDoneRLProto checkpoint =
  encodeMessage
    [ stringField 1 (cdrlExperimentHash checkpoint)
    , stringField 2 (cdrlManifestSha checkpoint)
    , uint64Field 3 (cdrlStep checkpoint)
    , stringField 4 (cdrlPointerKey checkpoint)
    , uint32Field 5 protocolVersion
    ]

decodeCheckpointDoneRLProto :: ByteString -> Either Text CheckpointDoneRL
decodeCheckpointDoneRLProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "CheckpointDoneRL" [1 .. 5] fields
  version <- require "protocol_version" (fieldWord32 5 fields)
  requireProtocolVersion "CheckpointDoneRL" version
  checkpoint <-
    CheckpointDoneRL
      <$> require "experiment_hash" (fieldString 1 fields)
      <*> require "manifest_sha" (fieldString 2 fields)
      <*> require "step" (fieldWord64 3 fields)
      <*> require "pointer_key" (fieldString 4 fields)
  validateCheckpointDoneRL checkpoint
  Right checkpoint

encodeCompletedCheckpointDoneRLProto :: CompletedCheckpointDoneRL -> ByteString
encodeCompletedCheckpointDoneRLProto completed =
  encodeMessage
    [ uint32Field 1 protocolVersion
    , messageField 2 (encodeCheckpointDoneRLProto (ccdrlCheckpoint completed))
    , messageField 3 (encodeCompletedTraining (ccdrlCompletedTraining completed))
    ]

decodeCompletedCheckpointDoneRLProto
  :: ByteString
  -> Either Text CompletedCheckpointDoneRL
decodeCompletedCheckpointDoneRLProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "CompletedCheckpointDoneRL" [1, 2, 3] fields
  version <- require "protocol_version" (fieldWord32 1 fields)
  requireProtocolVersion "CompletedCheckpointDoneRL" version
  checkpointBytes <- require "checkpoint" (fieldMessage 2 fields)
  completionBytes <- require "completed_training" (fieldMessage 3 fields)
  checkpoint <- decodeCheckpointDoneRLProto checkpointBytes
  completed <- decodeCompletedTraining completionBytes
  completeCheckpointDoneRL checkpoint completed

encodeMetricUpdateProto :: MetricUpdate -> ByteString
encodeMetricUpdateProto metric =
  encodeMessage
    [ stringField 1 (muExperimentHash metric)
    , stringField 2 (muName metric)
    , doubleField 3 (muValue metric)
    , uint64Field 4 (muTimestampNs metric)
    , stringField 5 (muPlanId metric)
    ]

decodeMetricUpdateProto :: ByteString -> Either Text MetricUpdate
decodeMetricUpdateProto bytes = do
  fields <- decodeMessage bytes
  requireKnownUniqueProtoFields "MetricUpdate" [1 .. 5] fields
  planId <- requireNonEmptyProtoString "plan_id" (fieldString 5 fields)
  experimentHash <-
    requireNonEmptyProtoString "experiment_hash" (fieldString 1 fields)
  name <- requireNonEmptyProtoString "name" (fieldString 2 fields)
  metricValue <-
    proto3ScalarField "value" 3 0.0 (fieldDouble 3 fields) fields
      >>= requireFiniteProtoDouble "value" . Just
  timestampNs <-
    proto3ScalarField "timestamp_ns" 4 0 (fieldWord64 4 fields) fields
  pure
    MetricUpdate
      { muPlanId = planId
      , muExperimentHash = experimentHash
      , muName = name
      , muValue = metricValue
      , muTimestampNs = timestampNs
      }

encodeGenerationCompletedProto :: GenerationCompleted -> ByteString
encodeGenerationCompletedProto generation =
  encodeMessage
    [ stringField 1 (gcPlanId generation)
    , stringField 2 (gcExperimentHash generation)
    , uint32Field 3 (gcGeneration generation)
    , uint32Field 4 (gcSelfPlayGames generation)
    , uint64Field 5 (gcSamples generation)
    ]

decodeGenerationCompletedProto :: ByteString -> Either Text GenerationCompleted
decodeGenerationCompletedProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "GenerationCompleted" [1 .. 5] fields
  GenerationCompleted
    <$> requireNonEmptyProtoString "plan_id" (fieldString 1 fields)
    <*> requireNonEmptyProtoString "experiment_hash" (fieldString 2 fields)
    <*> require "generation" (fieldWord32 3 fields)
    <*> require "self_play_games" (fieldWord32 4 fields)
    <*> require "samples" (fieldWord64 5 fields)

encodeArenaCompletedProto :: ArenaCompleted -> ByteString
encodeArenaCompletedProto arena =
  encodeMessage
    [ stringField 1 (acPlanId arena)
    , stringField 2 (acExperimentHash arena)
    , uint32Field 3 (acArenaGames arena)
    , doubleField 4 (acWinRate arena)
    ]

decodeArenaCompletedProto :: ByteString -> Either Text ArenaCompleted
decodeArenaCompletedProto bytes = do
  fields <- decodeMessage bytes
  requireExactProtoFields "ArenaCompleted" [1 .. 4] fields
  winRate <- require "win_rate" (fieldDouble 4 fields)
  if finiteDouble winRate
    then
      ArenaCompleted
        <$> requireNonEmptyProtoString "plan_id" (fieldString 1 fields)
        <*> requireNonEmptyProtoString "experiment_hash" (fieldString 2 fields)
        <*> require "arena_games" (fieldWord32 3 fields)
        <*> pure winRate
    else Left "invalid protobuf field: win_rate must be finite"

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
  requireExactProtoFields "RlAnimationFrame" [1 .. 12] fields
  RlAnimationFrame
    <$> requireNonEmptyProtoString "experiment_hash" (fieldString 1 fields)
    <*> requireNonEmptyProtoString "environment" (fieldString 2 fields)
    <*> require "episode" (fieldWord32 3 fields)
    <*> require "step" (fieldWord32 4 fields)
    <*> requireFiniteProtoDouble "reward" (fieldDouble 5 fields)
    <*> require "done" (fieldBool 6 fields)
    <*> require "action" (fieldWord32 7 fields)
    <*> requireFiniteProtoDoubles "observation" (fieldDoubles 8 fields)
    <*> requireFiniteProtoDoubles "action_probabilities" (fieldDoubles 9 fields)
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
  requireExactProtoFields "RlReplayFrame" [1 .. 13] fields
  RlReplayFrame
    <$> requireNonEmptyProtoString "experiment_hash" (fieldString 1 fields)
    <*> requireNonEmptyProtoString "replay_id" (fieldString 2 fields)
    <*> requireNonEmptyProtoString "environment" (fieldString 3 fields)
    <*> require "episode" (fieldWord32 4 fields)
    <*> require "step" (fieldWord32 5 fields)
    <*> require "action" (fieldWord32 6 fields)
    <*> requireFiniteProtoDouble "reward" (fieldDouble 7 fields)
    <*> require "done" (fieldBool 8 fields)
    <*> requireFiniteProtoDoubles "observation" (fieldDoubles 9 fields)
    <*> requireFiniteProtoDoubles "next_observation" (fieldDoubles 10 fields)
    <*> require "policy_version" (fieldWord64 11 fields)
    <*> require "observation_hash" (fieldWord32 12 fields)
    <*> require "timestamp_ns" (fieldWord64 13 fields)

requireExactProtoFields :: Text -> [Word64] -> [ProtoField] -> Either Text ()
requireExactProtoFields messageName expected fields
  | not (null unknown) =
      Left
        ( messageName
            <> " contains unknown protobuf fields: "
            <> renderFieldNumbers unknown
        )
  | length actual /= length (List.nub actual) =
      Left (messageName <> " contains duplicate protobuf fields")
  | not (null missing) =
      Left
        ( messageName
            <> " is missing protobuf fields: "
            <> renderFieldNumbers missing
        )
  | otherwise = Right ()
 where
  actual = fmap protoFieldNumber fields
  unknown = filter (`notElem` expected) actual
  missing = filter (`notElem` actual) expected
  renderFieldNumbers = Text.intercalate "," . fmap (Text.pack . show)

-- | Proto3 encoders omit scalar fields whose values equal their wire defaults.
-- Evidence messages still reject unknown and duplicate tags, while admitting
-- omitted default-valued scalars such as evaluation episode zero, iteration
-- zero, a zero reward/metric, or @done = false@.
requireKnownUniqueProtoFields :: Text -> [Word64] -> [ProtoField] -> Either Text ()
requireKnownUniqueProtoFields messageName expected fields
  | not (null unknown) =
      Left
        ( messageName
            <> " contains unknown protobuf fields: "
            <> renderFieldNumbers unknown
        )
  | length actual /= length (List.nub actual) =
      Left (messageName <> " contains duplicate protobuf fields")
  | otherwise = Right ()
 where
  actual = fmap protoFieldNumber fields
  unknown = filter (`notElem` expected) actual
  renderFieldNumbers = Text.intercalate "," . fmap (Text.pack . show)

proto3ScalarField
  :: Text
  -> Word64
  -> value
  -> Maybe value
  -> [ProtoField]
  -> Either Text value
proto3ScalarField fieldName fieldNumber defaultValue decoded fields
  | fieldNumber `elem` fmap protoFieldNumber fields =
      maybe (Left ("invalid protobuf field: " <> fieldName)) Right decoded
  | otherwise = Right defaultValue

require :: Text -> Maybe a -> Either Text a
require fieldName =
  maybe (Left ("missing protobuf field: " <> fieldName)) Right

requirePositiveProtoWord64 :: Text -> Maybe Word64 -> Either Text Word64
requirePositiveProtoWord64 fieldName encoded = do
  value <- require fieldName encoded
  if value == 0
    then Left ("invalid protobuf field: " <> fieldName <> " must be positive")
    else Right value

requireNonEmptyProtoString :: Text -> Maybe Text -> Either Text Text
requireNonEmptyProtoString fieldName encoded = do
  value <- require fieldName encoded
  if Text.null (Text.strip value)
    then Left ("invalid protobuf field: " <> fieldName <> " must be non-empty")
    else Right value

requireParsed :: Text -> (a -> Maybe b) -> a -> Either Text b
requireParsed fieldName parseValue value =
  maybe (Left ("invalid protobuf field: " <> fieldName)) Right (parseValue value)

requireFiniteProtoDouble :: Text -> Maybe Double -> Either Text Double
requireFiniteProtoDouble fieldName encoded = do
  value <- require fieldName encoded
  if finiteDouble value
    then Right value
    else Left ("invalid protobuf field: " <> fieldName <> " must be finite")

requireFiniteProtoDoubles :: Text -> Maybe [Double] -> Either Text [Double]
requireFiniteProtoDoubles fieldName encoded = do
  values <- require fieldName encoded
  if all finiteDouble values
    then Right values
    else Left ("invalid protobuf field: " <> fieldName <> " must contain only finite values")

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

validateCheckpointDoneRL :: CheckpointDoneRL -> Either Text ()
validateCheckpointDoneRL checkpoint = do
  requireNonBlank "experiment_hash" (cdrlExperimentHash checkpoint)
  requireNonBlank "manifest_sha" (cdrlManifestSha checkpoint)
  requireNonBlank "pointer_key" (cdrlPointerKey checkpoint)
  if cdrlStep checkpoint == 0
    then Left "RL checkpoint step must be positive"
    else Right ()

requireNonBlank :: Text -> Text -> Either Text ()
requireNonBlank fieldName value
  | Text.null (Text.strip value) = Left ("empty field: " <> fieldName)
  | otherwise = Right ()

eitherToMaybe :: Either error value -> Maybe value
eitherToMaybe = either (const Nothing) Just
