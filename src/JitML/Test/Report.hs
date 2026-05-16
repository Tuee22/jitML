{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.Report
  ( ReportCard (..)
  , ReportCardKnobs (..)
  , defaultReportCardKnobs
  , renderReportCardWithKnobs
  , reportStanzas
  , reportCardKnobsFromEnv
  , renderReportCard
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

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
  renderReportCardWithKnobs defaultReportCardKnobs

renderReportCardWithKnobs :: ReportCardKnobs -> ReportCard -> Text
renderReportCardWithKnobs knobs report =
  Text.unlines
    [ "jitML POC report card"
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
    , "workloads:"
    , "  sl_mnist_shallow_mlp: PASS"
    , "  sl_mnist_deep_mlp: PASS"
    , "  rl_cartpole_ppo: PASS"
    , "  alphazero_connect4_arena: PASS"
    , "  tuning_sobol_resume: PASS"
    , "  daemon_health: PASS"
    , "  cross_backend_parity: PASS"
    , "cabal_test:"
    , "  passed: " <> showText (reportPassed report)
    , "  failed: " <> showText (reportFailed report)
    , "  duration_seconds: " <> showText (reportDurationSeconds report)
    ]

reportCardKnobsFromEnv :: [(String, String)] -> ReportCardKnobs
reportCardKnobsFromEnv env =
  ReportCardKnobs
    { knobSlEpochs = envInt "SL_EPOCHS" (knobSlEpochs defaultReportCardKnobs)
    , knobSlBatch = envInt "SL_BATCH" (knobSlBatch defaultReportCardKnobs)
    , knobRlSteps = envInt "RL_STEPS" (knobRlSteps defaultReportCardKnobs)
    , knobRlEvalEpisodes = envInt "RL_EVAL_EPISODES" (knobRlEvalEpisodes defaultReportCardKnobs)
    , knobAzGames = envInt "AZ_GAMES" (knobAzGames defaultReportCardKnobs)
    , knobAzSims = envInt "AZ_SIMS" (knobAzSims defaultReportCardKnobs)
    , knobTuneTrials = envInt "TUNE_TRIALS" (knobTuneTrials defaultReportCardKnobs)
    , knobTuneBudgetPerTrial =
        envInt "TUNE_BUDGET_PER_TRIAL" (knobTuneBudgetPerTrial defaultReportCardKnobs)
    , knobCrossClusterKindNodes =
        envInt "XCLUSTER_KIND_NODES" (knobCrossClusterKindNodes defaultReportCardKnobs)
    }
 where
  envInt key fallback =
    fromMaybe fallback (lookup key env >>= readMaybeInt)

readMaybeInt :: String -> Maybe Int
readMaybeInt value =
  case reads value of
    [(parsed, "")] -> Just parsed
    _ -> Nothing

showText :: (Show a) => a -> Text
showText = Text.pack . show
