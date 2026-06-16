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
  , substratePartitionedStanzas
  , substrateTestInvocations
  , renderReportCard
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO

import JitML.Substrate (Substrate (..), renderSubstrate)

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
  , measuredBrowserProductMatrix :: Maybe ReportMeasurement
  -- ^ No-caveat browser/product matrix (Sprint 12.13): the live Playwright
  -- product run over every model/product interaction cell. Reports
  -- 'MeasurementUnavailable' until Phase `17` exercises the matrix live, so a
  -- live report card that has not proven the browser product surface fails the
  -- no-caveat handoff rather than vacuously omitting the row.
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
    , measuredBrowserProductMatrix = Nothing
    }

reportStanzas :: [Text]
reportStanzas =
  [ "jitml-unit"
  , "jitml-integration"
  , "jitml-sl-canonicals"
  , "jitml-rl-canonicals"
  , "jitml-hyperparameter"
  , "jitml-backends"
  , "jitml-daemon-lifecycle"
  , "jitml-e2e"
  ]

-- | Stanzas whose cases are partitioned into per-substrate tasty lanes (named
-- @linux-cpu …@ / @linux-cuda …@ / @apple-silicon …@) and that fail when run on
-- the wrong substrate. Under an explicit substrate selector these run with
-- @--test-options '-p <substrate>'@; every other stanza runs in full so that a
-- substrate selector never silently drops pure-logic coverage.
substratePartitionedStanzas :: [Text]
substratePartitionedStanzas =
  ["jitml-backends"]

-- | Build the ordered list of @cabal test@ argument vectors for a run. Each
-- element is the arguments passed after the @cabal@ executable.
--
-- Without a substrate selector, one invocation runs every target with the
-- optional user @--test-options@ string (the legacy behavior). With a
-- substrate, 'substratePartitionedStanzas' run under @-p \<substrate\>@ (and
-- @-fcuda@ on @linux-cuda@, so the cuBLAS/cuDNN bindings link) while every other
-- stanza runs unfiltered — this keeps pure-logic coverage instead of letting a
-- substrate-wide @-p@ vacuously match zero tests. Either group is omitted when
-- it has no targets, so single-stanza commands work too.
substrateTestInvocations :: Maybe Substrate -> [Text] -> Maybe Text -> [[Text]]
substrateTestInvocations Nothing targets userOptions =
  ["test" : targets <> testOptionArgs userOptions]
substrateTestInvocations (Just substrate) targets userOptions =
  restInvocation <> partitionedInvocation
 where
  cudaArgs = ["-fcuda" | substrate == LinuxCUDA]
  partitioned = filter (`elem` substratePartitionedStanzas) targets
  rest = filter (`notElem` substratePartitionedStanzas) targets
  restInvocation = ["test" : cudaArgs <> rest <> testOptionArgs userOptions | not (null rest)]
  laneOption = "-p " <> renderSubstrate substrate
  partitionedOptions =
    case userOptions of
      Just opts | not (Text.null opts) -> laneOption <> " " <> opts
      _ -> laneOption
  partitionedInvocation =
    [ "test" : cudaArgs <> partitioned <> ["--test-options", partitionedOptions]
    | not (null partitioned)
    ]

testOptionArgs :: Maybe Text -> [Text]
testOptionArgs Nothing = []
testOptionArgs (Just opts)
  | Text.null opts = []
  | otherwise = ["--test-options", opts]

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
        <> measurementLine "browser_product_matrix" (measuredBrowserProductMatrix measurements)

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
    , measuredBrowserProductMatrix measurements
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
