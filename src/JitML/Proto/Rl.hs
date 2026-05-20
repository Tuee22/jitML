{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Rl
  ( CheckpointDoneRL (..)
  , EpisodeDone (..)
  , EvalDone (..)
  , MetricUpdate (..)
  , RlCommand (..)
  , RlEvent (..)
  , StartRLRun (..)
  , StopRLRun (..)
  , parseRlCommand
  , renderRlCommand
  , renderRlEvent
  , rlCommandTopic
  , rlEventTopic
  )
where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import Text.Read (readMaybe)

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

data RlCommand
  = RlStart StartRLRun
  | RlStop StopRLRun
  deriving stock (Eq, Show)

data RlEvent
  = RlEpisode EpisodeDone
  | RlEval EvalDone
  | RlCheckpoint CheckpointDoneRL
  | RlMetric MetricUpdate
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
        ]
    RlEval e ->
      Text.unlines
        [ "kind: EvalDone"
        , "experiment-hash: " <> evExperimentHash e
        , "epoch: " <> Text.pack (show (evEpoch e))
        , "avg-reward: " <> Text.pack (show (evAvgReward e))
        , "std-reward: " <> Text.pack (show (evStdReward e))
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
