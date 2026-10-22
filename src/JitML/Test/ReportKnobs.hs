-- | Pure report-card workload configuration. Keeping this type below the
-- report/admission layer lets numerical execution consume the same knobs
-- without depending on reporting, Store, Matrix or qualification code.
module JitML.Test.ReportKnobs
  ( ReportCardKnobs (..)
  )
where

data ReportCardKnobs = ReportCardKnobs
  { knobSlEpochs :: Int
  , knobSlBatch :: Int
  , knobRlSteps :: Int
  , knobRlEvalEpisodes :: Int
  , knobAzGames :: Int
  , knobAzSims :: Int
  , knobTuneTrials :: Int
  , knobTuneBudgetPerTrial :: Int
  , knobCrossClusterKindNodes :: Int
  }
  deriving stock (Eq, Show)
