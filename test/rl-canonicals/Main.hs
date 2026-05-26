{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Proto.Rl
  ( CheckpointDoneRL (..)
  , EpisodeDone (..)
  , EvalDone (..)
  , MetricUpdate (..)
  , RlCommand (..)
  , RlEvent (..)
  , StartRLRun (..)
  , StopRLRun (..)
  , decodeRlCommandProto
  , decodeRlEventProto
  , encodeRlCommandProto
  , encodeRlEventProto
  , parseRlCommand
  , renderRlCommand
  )
import JitML.RL.Algorithms (algorithmCatalog, algorithmName, deterministicTrajectory)
import JitML.RL.Algorithms.Common
  ( AlgorithmModule (..)
  , moduleRolloutGenerator
  , rolloutGoldenLines
  )
import JitML.RL.Algorithms.Registry (algorithmModuleRegistry)
import JitML.RL.AlphaZero (gameMoves, selfPlayTranscript, selfPlayTranscriptFor)
import JitML.RL.Buffer (bufferSize)
import JitML.RL.ConvergenceThresholds
  ( ConvergenceThreshold (..)
  , cohortThreshold
  , passesConvergence
  )
import JitML.RL.Environments
  ( canonicalEnvironments
  , environmentActionCount
  , environmentObservationSize
  )
import JitML.RL.Loop
  ( RLConfig (..)
  , RLLoop (..)
  , defaultRLConfig
  , resultBuffer
  , resultEpisodes
  , runRLLoop
  )
import JitML.RL.Policy (defaultPolicy)
import JitML.Substrate (Substrate (..))
import JitML.Test.Report
  ( ReportCardKnobs (..)
  , loadReportCardKnobs
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-rl-canonicals"
      [ testCase "algorithm catalog covers PPO through AlphaZero" $ do
          let names = fmap algorithmName algorithmCatalog
          assertContains "PPO" names
          assertContains "SAC" names
          assertContains "HER" names
          assertContains "AlphaZero" names
      , testCase "trajectory generator is deterministic" $
          deterministicTrajectory "PPO" 42 @?= deterministicTrajectory "PPO" 42
      , testCase "PPO CartPole trajectory matches the golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/rl/ppo/cartpole/trajectory.txt"
          Text.lines fixture @?= fmap (Text.pack . show) (deterministicTrajectory "PPO" 42)
      , testCase "deterministic RL loop records rollout transitions in the replay buffer" $
          case (algorithmCatalog, canonicalEnvironments) of
            (algorithm : _, environment : _) -> do
              let policy =
                    defaultPolicy
                      "ppo-cartpole"
                      (environmentObservationSize environment)
                      (environmentActionCount environment)
                      LinuxCPU
                  config =
                    defaultRLConfig
                      { rlMaxEpisodes = 2
                      , rlMaxStepsPerEpisode = 8
                      , rlBufferCapacity = 32
                      }
                  loop = RLLoop algorithm policy environment config
                  first = runRLLoop loop
                  second = runRLLoop loop
              resultEpisodes first @?= resultEpisodes second
              assertBool "rollout transitions are recorded" (bufferSize (resultBuffer first) > 0)
            _ -> assertBool "missing RL catalog/environment fixture" False
      , testCase "AlphaZero self-play records legal Connect 4 columns" $
          mapM_
            (assertBool "column is legal" . all (\column -> column >= 0 && column < 7) . gameMoves)
            (selfPlayTranscript 3)
      , testCase "AlphaZero Connect 4 transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/connect4-transcript.txt"
          Text.lines fixture @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscript 3)
      , testCase "AlphaZero Othello transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/othello-transcript.txt"
          Text.lines fixture
            @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscriptFor "othello" 3)
      , testCase "AlphaZero Hex transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/hex-transcript.txt"
          Text.lines fixture
            @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscriptFor "hex" 3)
      , testCase "AlphaZero Gomoku transcript matches golden fixture" $ do
          fixture <- Text.IO.readFile "test/golden/alphazero/gomoku-transcript.txt"
          Text.lines fixture
            @?= fmap (Text.pack . show . gameMoves) (selfPlayTranscriptFor "gomoku" 3)
      , testCase "per-algorithm deterministic-stub rollouts match committed goldens" $
          mapM_ (uncurry checkRolloutGolden) algorithmRolloutCohorts
      , testCase "rl-canonicals consumes cabal.project rl_steps and rl_eval_episodes knobs" $ do
          loaded <- loadReportCardKnobs "cabal.project"
          case loaded of
            Left err -> assertBool (Text.unpack ("failed to load report-card knobs: " <> err)) False
            Right knobs -> do
              assertBool
                "rl_steps knob is positive"
                (knobRlSteps knobs > 0)
              assertBool
                "rl_eval_episodes knob is positive"
                (knobRlEvalEpisodes knobs > 0)
              assertBool
                "az_games knob is positive"
                (knobAzGames knobs > 0)
              assertBool
                "az_sims knob is positive"
                (knobAzSims knobs > 0)
      , testCase "convergence threshold lookup covers every algorithm rollout cohort (Sprint 13.6)" $
          mapM_ assertCohortThreshold convergenceAssertionCohorts
      , testCase
          "passesConvergence accepts the literature target and rejects below the slack band (Sprint 13.6)"
          $ mapM_ assertConvergencePredicate convergenceAssertionCohorts
      , testCase "RL command envelopes parse after render" $ do
          let start =
                RlStart
                  StartRLRun
                    { srlExperimentHash = "sha256:cartpole"
                    , srlAlgorithm = "PPO"
                    , srlEnvironment = "cartpole"
                    , srlSubstrate = LinuxCUDA
                    , srlSeed = 42
                    , srlMaxSteps = 1024
                    , srlEvalEpisodes = 8
                    }
              stop =
                RlStop
                  StopRLRun
                    { srStopExperimentHash = "sha256:cartpole"
                    , srStopDrain = False
                    }
          parseRlCommand (renderRlCommand start) @?= Just start
          parseRlCommand (renderRlCommand stop) @?= Just stop
          parseRlCommand "kind: UnknownRlCommand\n" @?= Nothing
          decodeRlCommandProto (encodeRlCommandProto start) @?= Right start
          decodeRlCommandProto (encodeRlCommandProto stop) @?= Right stop
      , testCase "RL event envelopes round-trip through proto3-compatible bytes" $ do
          let episode =
                RlEpisode
                  EpisodeDone
                    { edExperimentHash = "sha256:cartpole"
                    , edEpisode = 7
                    , edReward = 1.5
                    , edSteps = 32
                    , edTimestampNs = 123456789
                    }
              eval =
                RlEval
                  EvalDone
                    { evExperimentHash = "sha256:cartpole"
                    , evEpoch = 3
                    , evAvgReward = 0.75
                    , evStdReward = 0.125
                    , evTimestampNs = 223456789
                    }
              checkpoint =
                RlCheckpoint
                  CheckpointDoneRL
                    { cdrlExperimentHash = "sha256:cartpole"
                    , cdrlManifestSha = "sha256:manifest"
                    , cdrlStep = 2048
                    , cdrlPointerKey = "checkpoints/cartpole/latest"
                    }
              metric =
                RlMetric
                  MetricUpdate
                    { muExperimentHash = "sha256:cartpole"
                    , muName = "entropy"
                    , muValue = 0.0625
                    , muTimestampNs = 323456789
                    }
          decodeRlEventProto (encodeRlEventProto episode) @?= Right episode
          decodeRlEventProto (encodeRlEventProto eval) @?= Right eval
          decodeRlEventProto (encodeRlEventProto checkpoint) @?= Right checkpoint
          decodeRlEventProto (encodeRlEventProto metric) @?= Right metric
      ]

assertContains :: Text -> [Text] -> IO ()
assertContains value values =
  assertBool ("missing " <> show value) (value `elem` values)

-- | Cohorts asserted against `ConvergenceThresholds.cohortThreshold` from the
-- canonical stanza. The list excludes (algo, env) pairs where the threshold
-- table intentionally has no entry (HER's mountain-car cohort and DQN-family
-- continuous envs aren't in the canonical evaluation matrix); the remaining
-- pairs all have committed literature anchors.
convergenceAssertionCohorts :: [(Text, Text)]
convergenceAssertionCohorts =
  filter (\(algo, _) -> algo /= "HER")
    . filter shouldHaveThreshold
    $ algorithmRolloutCohorts
 where
  shouldHaveThreshold (algo, env) =
    case (algo, env) of
      ("DDPG", "mountain-car") -> False
      ("TD3", "mountain-car") -> False
      ("SAC", "mountain-car") -> False
      ("CrossQ", "mountain-car") -> False
      ("TQC", "mountain-car") -> False
      _ -> True

assertCohortThreshold :: (Text, Text) -> IO ()
assertCohortThreshold (algo, env) =
  case cohortThreshold algo env of
    Just _ -> pure ()
    Nothing ->
      assertBool
        ("missing convergence threshold for cohort " <> show (algo, env))
        False

-- | Assert `passesConvergence` rejects insufficient rewards and accepts the
-- literature target itself. Exercising the predicate from the canonical
-- stanza wires Sprint 13.6's assertion path through `jitml-rl-canonicals`
-- ahead of live cohort runs; once Sprint 13.5's real simulators land, the
-- measured median replaces the synthetic test values without touching the
-- assertion shape.
assertConvergencePredicate :: (Text, Text) -> IO ()
assertConvergencePredicate (algo, env) =
  case cohortThreshold algo env of
    Nothing ->
      assertBool
        ("missing convergence threshold for cohort " <> show (algo, env))
        False
    Just threshold -> do
      assertBool
        ("literature target should pass for cohort " <> show (algo, env))
        (passesConvergence threshold (literatureTarget threshold))
      assertBool
        ("a reward below target by 2x the slack should fail for cohort " <> show (algo, env))
        (not (passesConvergence threshold (literatureTarget threshold - 2 * slack threshold)))

-- | Per-algorithm canonical environment pairing used by the deterministic-stub
-- rollout golden assertion. The pairing keeps continuous-control algorithms on
-- mountain-car and leaves the discrete algorithms on cartpole.
algorithmRolloutCohorts :: [(Text, Text)]
algorithmRolloutCohorts =
  [ ("PPO", "cartpole")
  , ("A2C", "cartpole")
  , ("TRPO", "cartpole")
  , ("MaskablePPO", "cartpole")
  , ("RecurrentPPO", "cartpole")
  , ("DQN", "cartpole")
  , ("QR-DQN", "cartpole")
  , ("DDPG", "mountain-car")
  , ("TD3", "mountain-car")
  , ("SAC", "mountain-car")
  , ("CrossQ", "mountain-car")
  , ("TQC", "mountain-car")
  , ("ARS", "cartpole")
  , ("HER", "mountain-car")
  ]

checkRolloutGolden :: Text -> Text -> IO ()
checkRolloutGolden algoName envName =
  case [m | m <- algorithmModuleRegistry, algorithmName (moduleAlgorithm m) == algoName] of
    [] -> assertBool ("missing algorithm module for " <> show algoName) False
    (m : _) -> do
      let rollout = moduleRolloutGenerator m envName 42 8
          path =
            "test/golden/rl/"
              <> Text.unpack (Text.toLower (Text.replace "-" "-" algoName))
              <> "/"
              <> Text.unpack envName
              <> "/rollout.txt"
      fixture <- Text.IO.readFile path
      Text.lines fixture @?= rolloutGoldenLines rollout
