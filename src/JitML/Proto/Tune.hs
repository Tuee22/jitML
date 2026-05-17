{-# LANGUAGE OverloadedStrings #-}

module JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , SweepDone (..)
  , TrialFinished (..)
  , TrialStarted (..)
  , TuneCommand (..)
  , TuneEvent (..)
  , renderTuneCommand
  , renderTuneEvent
  , tuneCommandTopic
  , tuneEventTopic
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)

import JitML.Substrate (Substrate, renderSubstrate)

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
