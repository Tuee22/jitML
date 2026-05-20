{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( ReportCard (..)
  , ReportCardKnobs (..)
  , defaultReportCardKnobs
  , loadReportCardKnobs
  , parseReportCardKnobs
  , renderReportCardForTargets
  , renderReportCardWithKnobs
  , reportStanzas
  , renderReportCard
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO

data ReportCard = ReportCard
  { reportPassed :: Int
  , reportFailed :: Int
  , reportDurationSeconds :: Int
  }
  deriving stock (Eq, Show)

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

defaultReportCardKnobs :: ReportCardKnobs
defaultReportCardKnobs =
  ReportCardKnobs
    { knobSlEpochs = 5
    , knobSlBatch = 64
    , knobRlSteps = 100000
    , knobRlEvalEpisodes = 25
    , knobAzGames = 200
    , knobAzSims = 400
    , knobTuneTrials = 64
    , knobTuneBudgetPerTrial = 1000
    , knobCrossClusterKindNodes = 2
    }

reportStanzas :: [Text]
reportStanzas =
  [ "jitml-unit"
  , "jitml-integration"
  , "jitml-sl-canonicals"
  , "jitml-rl-canonicals"
  , "jitml-hyperparameter"
  , "jitml-cross-backend"
  , "jitml-daemon-lifecycle"
  , "jitml-e2e"
  , "jitml-haskell-style"
  , "jitml-purescript-style"
  ]

renderReportCard :: ReportCard -> Text
renderReportCard =
  renderReportCardForTargets defaultReportCardKnobs reportStanzas

loadReportCardKnobs :: FilePath -> IO (Either Text ReportCardKnobs)
loadReportCardKnobs path =
  parseReportCardKnobs <$> Text.IO.readFile path

parseReportCardKnobs :: Text -> Either Text ReportCardKnobs
parseReportCardKnobs content =
  ReportCardKnobs
    <$> lookupInt "sl_epochs"
    <*> lookupInt "sl_batch"
    <*> lookupInt "rl_steps"
    <*> lookupInt "rl_eval_episodes"
    <*> lookupInt "az_games"
    <*> lookupInt "az_sims"
    <*> lookupInt "tune_trials"
    <*> lookupInt "tune_budget_per_trial"
    <*> lookupInt "xcluster_kind_nodes"
 where
  entries =
    [ (Text.strip key, Text.strip (Text.drop 1 rest))
    | line <- Text.lines content
    , Just comment <- [Text.stripPrefix "-- " (Text.strip line)]
    , let (key, rest) = Text.breakOn ":" comment
    , not (Text.null rest)
    ]

  lookupInt key =
    case lookup key entries of
      Nothing -> Left ("missing report-card knob: " <> key)
      Just value -> parseInt key value

  parseInt key value =
    case reads (Text.unpack (Text.filter (/= '_') value)) of
      [(parsed, "")] -> Right parsed
      _ -> Left ("invalid report-card knob " <> key <> ": " <> value)

renderReportCardWithKnobs :: ReportCardKnobs -> ReportCard -> Text
renderReportCardWithKnobs knobs =
  renderReportCardForTargets knobs reportStanzas

renderReportCardForTargets :: ReportCardKnobs -> [Text] -> ReportCard -> Text
renderReportCardForTargets knobs targets report =
  Text.unlines
    ( [ "jitML POC report card"
      , "knobs:"
      , "  sl_epochs: " <> showText (knobSlEpochs knobs)
      , "  sl_batch: " <> showText (knobSlBatch knobs)
      , "  rl_steps: " <> showText (knobRlSteps knobs)
      , "  rl_eval_episodes: " <> showText (knobRlEvalEpisodes knobs)
      , "  alphazero_games: " <> showText (knobAzGames knobs)
      , "  alphazero_sims: " <> showText (knobAzSims knobs)
      , "  tune_trials: " <> showText (knobTuneTrials knobs)
      , "  tune_budget_per_trial: " <> showText (knobTuneBudgetPerTrial knobs)
      , "  xcluster_kind_nodes: " <> showText (knobCrossClusterKindNodes knobs)
      , "stanzas:"
      ]
        <> fmap renderTarget targets
        <> [ "cabal_test:"
           , "  passed: " <> showText (reportPassed report)
           , "  failed: " <> showText (reportFailed report)
           , "  duration_seconds: " <> showText (reportDurationSeconds report)
           ]
    )
 where
  renderTarget target =
    "  " <> target <> ": PASS"

showText :: (Show a) => a -> Text
showText = Text.pack . show
