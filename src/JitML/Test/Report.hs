{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , ReportCardKnobs (..)
  , defaultReportCardKnobs
  , emptyReportMeasurements
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
  , reportMeasurements :: ReportMeasurements
  }
  deriving stock (Eq, Show)

data ReportMeasurement
  = MeasurementAvailable Text
  | MeasurementUnavailable
  deriving stock (Eq, Show)

data ReportMeasurements = ReportMeasurements
  { measuredSlFinalLoss :: Maybe ReportMeasurement
  , measuredRlFinalReward :: Maybe ReportMeasurement
  , measuredAlphaZeroArenaWinRate :: Maybe ReportMeasurement
  , measuredTuneBestObjective :: Maybe ReportMeasurement
  , measuredJitCacheHitRate :: Maybe ReportMeasurement
  , measuredDaemonHealthz :: Maybe ReportMeasurement
  , measuredCrossSubstrateParity :: Maybe ReportMeasurement
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

emptyReportMeasurements :: ReportMeasurements
emptyReportMeasurements =
  ReportMeasurements
    { measuredSlFinalLoss = Nothing
    , measuredRlFinalReward = Nothing
    , measuredAlphaZeroArenaWinRate = Nothing
    , measuredTuneBestObjective = Nothing
    , measuredJitCacheHitRate = Nothing
    , measuredDaemonHealthz = Nothing
    , measuredCrossSubstrateParity = Nothing
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
        <> renderMeasurements (reportMeasurements report)
        <> [ "cabal_test:"
           , "  passed: " <> showText (reportPassed report)
           , "  failed: " <> showText (reportFailed report)
           , "  duration_seconds: " <> showText (reportDurationSeconds report)
           ]
    )
 where
  renderTarget target =
    "  " <> target <> ": PASS"

renderMeasurements :: ReportMeasurements -> [Text]
renderMeasurements measurements
  | not (hasMeasurements measurements) = []
  | otherwise =
      [ "measurements:"
      ]
        <> measurementLine "sl_final_loss" (measuredSlFinalLoss measurements)
        <> measurementLine "rl_final_reward" (measuredRlFinalReward measurements)
        <> measurementLine "alphazero_arena_win_rate" (measuredAlphaZeroArenaWinRate measurements)
        <> measurementLine "tune_best_objective" (measuredTuneBestObjective measurements)
        <> measurementLine "jit_cache_hit_rate" (measuredJitCacheHitRate measurements)
        <> measurementLine "daemon_healthz" (measuredDaemonHealthz measurements)
        <> measurementLine "cross_substrate_parity" (measuredCrossSubstrateParity measurements)

hasMeasurements :: ReportMeasurements -> Bool
hasMeasurements measurements =
  any
    isMeasured
    [ measuredSlFinalLoss measurements
    , measuredRlFinalReward measurements
    , measuredAlphaZeroArenaWinRate measurements
    , measuredTuneBestObjective measurements
    , measuredJitCacheHitRate measurements
    , measuredDaemonHealthz measurements
    , measuredCrossSubstrateParity measurements
    ]
 where
  isMeasured Nothing = False
  isMeasured (Just _) = True

measurementLine :: Text -> Maybe ReportMeasurement -> [Text]
measurementLine _ Nothing = []
measurementLine label (Just measurement) =
  ["  " <> label <> ": " <> renderMeasurement measurement]

renderMeasurement :: ReportMeasurement -> Text
renderMeasurement (MeasurementAvailable value) = value
renderMeasurement MeasurementUnavailable = "unavailable"

showText :: (Show a) => a -> Text
showText = Text.pack . show
