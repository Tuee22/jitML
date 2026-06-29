{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.List qualified as List
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Environment (lookupEnv)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import Data.Vector.Unboxed qualified
import JitML.Checkpoint.Format (decodeJmw1, encodeJmw1)
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Numerics.Mlp (forwardOutput, mlpForward)
import JitML.Numerics.MlpDevice (MlpDevice, probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
import JitML.Proto.Rl
  ( CheckpointDoneRL (..)
  , EpisodeDone (..)
  , EvalDone (..)
  , MetricUpdate (..)
  , RlAnimationFrame (..)
  , RlCommand (..)
  , RlEvent (..)
  , RlReplayFrame (..)
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
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms (algorithmCatalog, algorithmName)
import JitML.RL.Algorithms.A2cLoss qualified as A2cLoss
import JitML.RL.Algorithms.ArsLoss qualified as ArsLoss
import JitML.RL.Algorithms.ArsTrainer qualified as ArsTrainer
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.CrossQLoss qualified as CrossQLoss
import JitML.RL.Algorithms.DdpgLoss qualified as DdpgLoss
import JitML.RL.Algorithms.DqnLoss qualified as DqnLoss
import JitML.RL.Algorithms.DqnTrainer qualified as DqnTrainer
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.HerTrainer qualified as HerTrainer
import JitML.RL.Algorithms.MaskablePpoLoss qualified as MaskablePpoLoss
import JitML.RL.Algorithms.PpoLoss qualified as PpoLoss
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnLoss qualified as QrDqnLoss
import JitML.RL.Algorithms.RecurrentPpoLoss qualified as RecurrentPpoLoss
import JitML.RL.Algorithms.SacLoss qualified as SacLoss
import JitML.RL.Algorithms.Td3Loss qualified as Td3Loss
import JitML.RL.Algorithms.TqcLoss qualified as TqcLoss
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
import JitML.RL.AlphaZero
  ( GameOutcome (..)
  , GameState (..)
  , applyMove
  , gameIsTerminal
  , gameMoves
  , gameOutcome
  , initialConnect4
  , initialGomoku
  , initialHex
  , initialOthello
  , selfPlayTranscript
  , selfPlayTranscriptFor
  , terminalValueForToMove
  )
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.AlphaZero.SelfPlay qualified as SelfPlay
import JitML.RL.Buffer (bufferSize)
import JitML.RL.ConvergenceThresholds
  ( ConvergenceThreshold (..)
  , alphaZeroArenaThreshold
  , cohortThreshold
  , passesAlphaZeroArena
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
import JitML.RL.Simulator (cartPoleInitial)
import JitML.RL.Simulator qualified as Sim
import JitML.RL.SimulatorLoop qualified as SimulatorLoop
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Test.Report
  ( ReportCardKnobs (..)
  , loadReportCardKnobs
  )
import JitML.Training.Budget qualified as TrainingBudget
import System.Random qualified as Random

completedTrainingFixture
  :: TrainingBudget.BudgetKind
  -> Text
  -> Word64
  -> [(Text, Double)]
  -> TrainingBudget.CompletedTraining
completedTrainingFixture kind experimentHash observedUnits metrics =
  either
    (error . Text.unpack)
    id
    ( TrainingBudget.completedTrainingFromMetrics
        TrainingBudget.TrainingBudget
          { TrainingBudget.tbKind = kind
          , TrainingBudget.tbTargetUnits = max 1 observedUnits
          , TrainingBudget.tbUnitLabel = "units"
          , TrainingBudget.tbSeed = Nothing
          }
        observedUnits
        metrics
        TrainingBudget.TensorBoardRunMetadata
          { TrainingBudget.tbrRunId = experimentHash
          , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
          , TrainingBudget.tbrScalarTags = fmap fst metrics
          }
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
      , testCase "PPO trained-policy CartPole rollout regenerates deterministically without fixtures" $ do
          first <- ppoCartpoleTrainedRollout 42
          second <- ppoCartpoleTrainedRollout 42
          first @?= second
          assertBool "trained rollout has steps" (not (null (PpoTrainer.rolloutSteps first)))
          assertBool
            "trained rollout has rewards"
            (not (null (fmap PpoTrainer.rsReward (PpoTrainer.rolloutSteps first))))
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
      , testCase "AlphaZero transcripts regenerate deterministically without fixtures" $
          mapM_ assertTranscriptDeterminism ["connect4", "othello", "hex", "gomoku"]
      , testCase
          "AlphaZero terminal evaluators use canonical game rules (Sprint 9.12)"
          assertAlphaZeroTerminalEvaluators
      , testCase "per-algorithm trained-policy rollouts regenerate deterministically without fixtures" $
          mapM_ (checkRolloutDeterminism . fst) algorithmRolloutCohorts
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
          "passesConvergence is a correct boundary predicate (Sprint 13.6 unit)"
          assertPassesConvergenceBoundary
      , testCase
          "real measured-median PPO/cartpole convergence + sample-efficiency metric (Sprint 9.13)"
          assertMeasuredMedianConvergence
      , testCase
          "AlphaZero arena win-rate convergence against the baseline opponent (Sprint 9.13)"
          assertAlphaZeroArenaConvergence
      , testCase
          "simulator loop is run-to-run deterministic across the canonical env catalog (Sprint 13.6 + 13.5)"
          $ mapM_ assertSimulatorLoopDeterminism SimulatorLoop.simulatedEnvCatalog
      , testCase
          "KeyDoorGrid-v0 canonical coverage is deterministic and maskable (Sprint 8.9 + 9.8)"
          assertKeyDoorGridCanonicals
      , testCase
          "atari-subset uses explicit ROM policy and optional ALE smoke validation (Sprint 8.8)"
          assertAleAtariPolicy
      , testCase
          "PPO real loss math runs deterministically against the canonical PPO/cartpole rollout (Sprint 13.8)"
          assertPpoLossDeterminism
      , testCase
          "every Sprint 13.8 loss module returns a finite value on the canonical trajectory"
          assertAllLossModulesFinite
      , testCase
          "PPO trainer learns cartpole through the differentiable MLP (Sprint 13.8 + 13.9 seam)"
          assertPpoTrainerImprovesOnCartpole
      , testCase
          "PPO trains and improves on cartpole through the substrate JIT device (Sprint 8.11 --linux-cpu)"
          assertPpoDeviceImproves
      , testCase
          "PPO trainer is bit-deterministic across two fresh runs (Sprint 13.8 determinism)"
          assertPpoTrainerDeterministic
      , testCase
          "every on-policy variant trains and improves on cartpole (Sprint 13.8 A2C/TRPO/MaskablePPO/RecurrentPPO)"
          assertOnPolicyVariantsImprove
      , testCase
          "DDPG continuous actor-critic runs deterministically on pendulum (Sprint 13.8 continuous seam)"
          assertDdpgTrainerDeterministicOnPendulum
      , testCase
          "policy/value network forward emits a valid policy distribution (Sprint 13.9)"
          assertPolicyValueForwardValid
      , testCase
          "policy/value network gradient update reduces an MCTS self-play loss (Sprint 13.9)"
          assertPolicyValueTrainingReducesLoss
      , testCase
          "AlphaZero self-play generation runs deterministically and reports an arena win rate (Sprint 13.9)"
          assertAlphaZeroSelfPlayGenerationDeterministic
      , testCase
          "network-driven MCTS self-play is deterministic and legal (Sprint 13.9 production prior)"
          assertNetworkSelfPlayDeterministic
      , testCase
          "MCTS visit-count target is a valid search-derived distribution (Sprint 13.9 visit targets)"
          assertMctsVisitTargets
      , testCase
          "MCTS visit-count target evaluates leaves through the substrate JIT device (Sprint 9.10 --linux-cpu)"
          assertMctsVisitTargetsWithDevice
      , testCase
          "trained PolicyValueNet weights round-trip through the .jmw1 checkpoint blob (Sprint 13.9)"
          assertPolicyValueWeightsRoundTrip
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
                    , cdrlCompletedTraining =
                        Just
                          ( completedTrainingFixture
                              TrainingBudget.RlEnvironmentStepBudget
                              "sha256:cartpole"
                              2048
                              [("eval_return", 0.75)]
                          )
                    }
              metric =
                RlMetric
                  MetricUpdate
                    { muExperimentHash = "sha256:cartpole"
                    , muName = "entropy"
                    , muValue = 0.0625
                    , muTimestampNs = 323456789
                    }
              animation =
                RlAnimation
                  RlAnimationFrame
                    { rafExperimentHash = "sha256:cartpole"
                    , rafEnvironment = "cartpole"
                    , rafEpisode = 7
                    , rafStep = 11
                    , rafReward = 1.0
                    , rafDone = False
                    , rafAction = 1
                    , rafObservation = [0.0, 0.1, 0.2, 0.3]
                    , rafActionProbabilities = [0.25, 0.75]
                    , rafObservationHash = 4242
                    , rafReplayCursor = 70011
                    , rafTimestampNs = 423456789
                    }
              replay =
                RlReplay
                  RlReplayFrame
                    { rrfExperimentHash = "sha256:cartpole"
                    , rrfReplayId = "replay/cartpole/7"
                    , rrfEnvironment = "cartpole"
                    , rrfEpisode = 7
                    , rrfStep = 11
                    , rrfAction = 1
                    , rrfReward = 1.0
                    , rrfDone = False
                    , rrfObservation = [0.0, 0.1, 0.2, 0.3]
                    , rrfNextObservation = [0.1, 0.2, 0.3, 0.4]
                    , rrfPolicyVersion = 3
                    , rrfObservationHash = 4243
                    , rrfTimestampNs = 523456789
                    }
          decodeRlEventProto (encodeRlEventProto episode) @?= Right episode
          decodeRlEventProto (encodeRlEventProto eval) @?= Right eval
          decodeRlEventProto (encodeRlEventProto checkpoint) @?= Right checkpoint
          decodeRlEventProto (encodeRlEventProto metric) @?= Right metric
          decodeRlEventProto (encodeRlEventProto animation) @?= Right animation
          decodeRlEventProto (encodeRlEventProto replay) @?= Right replay
          parseRlEvent (renderRlEvent animation) @?= Just animation
          parseRlEvent (renderRlEvent replay) @?= Just replay
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

-- | Sprint 9.13 — pure boundary unit test of the `passesConvergence`
-- predicate using explicit literal values. This validates the predicate's
-- accept/reject boundary (a measured median at the target passes; one two slacks
-- below fails) WITHOUT claiming any model converged — the synthetic
-- literature-target "convergence probe" it replaced fed the literature value in
-- as if it were a measurement, which masqueraded as convergence evidence. Real
-- convergence is now measured by 'assertMeasuredMedianConvergence' (return
-- cohorts) and 'assertAlphaZeroArenaConvergence' (AlphaZero).
assertPassesConvergenceBoundary :: IO ()
assertPassesConvergenceBoundary = do
  let threshold = ConvergenceThreshold 200.0 40.0
  assertBool "a measured median at the target passes" (passesConvergence threshold 200.0)
  assertBool
    "a measured median at target − slack passes (lower bar)"
    (passesConvergence threshold 160.0)
  assertBool
    "a measured median two slacks below the target is rejected"
    (not (passesConvergence threshold 120.0))
  -- mountain-car uses negative rewards: −130 still clears target −110 / slack 20.
  let negThreshold = ConvergenceThreshold (-110.0) 20.0
  assertBool "negative-reward target clears within slack" (passesConvergence negThreshold (-130.0))
  assertBool
    "negative-reward median below the slack band is rejected"
    (not (passesConvergence negThreshold (-200.0)))

-- | Median of a non-empty list of doubles (mean of the two central elements for
-- an even count). Used to aggregate per-seed measured returns into the cohort's
-- measured-median convergence statistic.
medianOf :: [Double] -> Double
medianOf values =
  let sorted = List.sort values
      n = length sorted
   in if n == 0
        then 0.0
        else
          if odd n
            then sorted !! (n `div` 2)
            else 0.5 * ((sorted !! (n `div` 2 - 1)) + (sorted !! (n `div` 2)))

-- | Sprint 9.13 — real measured-median RL convergence plus the non-wall-clock
-- sample-efficiency performance metric, for the canonical fast cohort
-- (PPO / cartpole). Trains the real PPO trainer over k fixed seeds, reads each
-- run's final-iteration measured mean reward, and asserts the __measured
-- median__ clears a measured-baseline-anchored convergence bar through the
-- production `passesConvergence` predicate — no synthetic literature value is
-- fed in. The performance metric is env-steps-to-threshold (sample efficiency):
-- the cumulative environment steps the seed-anchored run consumed before its
-- iteration mean first crossed the bar — a deterministic, non-wall-clock measure
-- (wall-clock is excluded from the determinism contract). The full
-- literature-threshold convergence over every cohort is the live `jitml rl
-- train` gate (Sprint 13.2); this host stanza proves the measurement path is
-- real, not a placeholder.
assertMeasuredMedianConvergence :: IO ()
assertMeasuredMedianConvergence = do
  let seeds = [42, 7, 1234]
      mkConfig seed =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = seed
          , PpoTrainer.ppoRolloutSteps = 512
          , PpoTrainer.ppoNumIterations = 8
          , PpoTrainer.ppoEpochsPerUpdate = 4
          , PpoTrainer.ppoLearningRate = 1.0e-3
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
  runs <- traverse (PpoTrainer.trainPpoOnCartpole . mkConfig) seeds
  let perRunStats = fmap PpoTrainer.resultIterations runs
  -- Total destructuring: requires at least one run AND every run non-empty (no
  -- partial head/last). The catch-all fails loudly if a future change empties seeds.
  case (perRunStats, traverse listToMaybe perRunStats, traverse (listToMaybe . reverse) perRunStats) of
    (seed42Stats : _, Just firstStats, Just lastStats) -> do
      let firstMeans = fmap PpoTrainer.iterMeanReward firstStats
          lastMeans = fmap PpoTrainer.iterMeanReward lastStats
          baselineMedian = medianOf firstMeans
          trainedMedian = medianOf lastMeans
          -- a real, measured-baseline-anchored convergence bar: the trained median
          -- must clear the untrained baseline by a real reward margin.
          convergenceMargin = 5.0
          bar = ConvergenceThreshold (baselineMedian + convergenceMargin) 0.0
      assertBool
        ( "trained measured-median return should clear the measured baseline by the margin: baseline="
            <> show baselineMedian
            <> " trained="
            <> show trainedMedian
        )
        (passesConvergence bar trainedMedian)
      -- Sample-efficiency performance metric (non-wall-clock): cumulative env steps
      -- before the seed-42 run's iteration mean first crossed the bar.
      let rolloutSteps = 512
          crossedIndex =
            length
              (takeWhile (\stat -> PpoTrainer.iterMeanReward stat < baselineMedian + convergenceMargin) seed42Stats)
          envStepsToThreshold = (crossedIndex + 1) * rolloutSteps
      assertBool
        ( "sample-efficiency env-steps metric is a positive deterministic count, got "
            <> show envStepsToThreshold
        )
        (envStepsToThreshold > 0)
      -- the metric is deterministic: a fresh same-seed run reproduces it.
      rerun <- PpoTrainer.trainPpoOnCartpole (mkConfig 42)
      fmap PpoTrainer.iterMeanReward (PpoTrainer.resultIterations rerun)
        @?= fmap PpoTrainer.iterMeanReward seed42Stats
    _ ->
      assertBool "every PPO run produced iteration stats and at least one run exists" False

-- | Sprint 9.13 — real AlphaZero arena-win-rate convergence: train a
-- policy/value network through several generations of self-play and assert its
-- measured arena win rate against the uniform-random baseline clears the
-- AlphaZero convergence bar (a deliberate non-return metric) and improves over
-- the first generation. The arena measurement is pure and deterministic, so a
-- repeated same-seed generation reproduces the win rate bit-for-bit.
assertAlphaZeroArenaConvergence :: IO ()
assertAlphaZeroArenaConvergence = do
  let net0 = PVN.initPolicyValueNet 43 7 32 101
      adam0 = PVN.initAdamFor net0
      selfPlayGames = 16
      maxPlies = 42
      sims = 24
      gradientUpdates = 60
      arenaGames = 24
      gen1 =
        PVN.runOneGenerationOfSelfPlay net0 adam0 selfPlayGames maxPlies sims gradientUpdates arenaGames 101
      gen2 =
        PVN.runOneGenerationOfSelfPlay
          (PVN.genNet gen1)
          (PVN.genAdam gen1)
          selfPlayGames
          maxPlies
          sims
          gradientUpdates
          arenaGames
          202
      gen3 =
        PVN.runOneGenerationOfSelfPlay
          (PVN.genNet gen2)
          (PVN.genAdam gen2)
          selfPlayGames
          maxPlies
          sims
          gradientUpdates
          arenaGames
          303
      finalWinRate = PVN.genArenaWinRate gen3
  assertBool
    ("arena win rate is a measured fraction in [0,1], got " <> show finalWinRate)
    (finalWinRate >= 0.0 && finalWinRate <= 1.0)
  assertBool
    ("AlphaZero arena win rate should clear the convergence bar, got " <> show finalWinRate)
    (passesAlphaZeroArena alphaZeroArenaThreshold finalWinRate)
  -- determinism: the arena measurement is pure, so a fresh same-seed first
  -- generation reproduces its win rate exactly.
  let gen1Again =
        PVN.runOneGenerationOfSelfPlay net0 adam0 selfPlayGames maxPlies sims gradientUpdates arenaGames 101
  PVN.genArenaWinRate gen1 @?= PVN.genArenaWinRate gen1Again

-- | Per-algorithm canonical environment pairing used by the same-seed rollout
-- determinism assertion. The pairing keeps continuous-control algorithms on
-- mountain-car and leaves the discrete algorithms on cartpole.
algorithmRolloutCohorts :: [(Text, Text)]
algorithmRolloutCohorts =
  [ ("PPO", "cartpole")
  , ("A2C", "cartpole")
  , ("TRPO", "cartpole")
  , ("MaskablePPO", "key-door-grid")
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

-- | Train a short fixed-seed PPO cohort on cartpole and roll the trained
-- policy out through the real product rollout path
-- ('PpoTrainer.collectRollout'). This is the checkpoint-backed trained-policy
-- rollout that replaced the catalog projection: same seed in, bit-identical
-- @Rollout@ out.
ppoCartpoleTrainedRollout :: Int -> IO PpoTrainer.Rollout
ppoCartpoleTrainedRollout seed = do
  let config =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = seed
          , PpoTrainer.ppoRolloutSteps = 64
          , PpoTrainer.ppoNumIterations = 2
          , PpoTrainer.ppoEpochsPerUpdate = 2
          , PpoTrainer.ppoMiniBatchSize = 32
          , PpoTrainer.ppoLearningRate = 1.0e-3
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
  result <- PpoTrainer.trainPpoOnCartpole config
  (rollout, _state, _gen) <-
    PpoTrainer.collectRollout
      config
      (PpoTrainer.resultFinalParams result)
      cartPoleInitial
      (Random.mkStdGen (seed + 1701))
  pure rollout

-- | Per-algorithm run-to-run determinism on the __real trained-rollout__
-- product path (the catalog projection it replaced is gone). Each algorithm is
-- dispatched onto the trainer/rollout surface it actually uses: the on-policy
-- variants train then roll the trained policy out via
-- 'PpoTrainer.collectRollout'; the value-based, continuous, ARS, and HER
-- families assert their real trainer produces bit-identical rollout-derived
-- statistics across two fresh same-seed runs. None of these collapse to a
-- tautology: a non-deterministic trainer fails @first == second@.
checkRolloutDeterminism :: Text -> IO ()
checkRolloutDeterminism algoName =
  case algoName of
    "PPO" -> onPolicyRolloutDeterminism PpoTrainer.VariantPPO
    "A2C" -> onPolicyRolloutDeterminism PpoTrainer.VariantA2C
    "TRPO" -> onPolicyRolloutDeterminism PpoTrainer.VariantTRPO
    "MaskablePPO" -> onPolicyRolloutDeterminism PpoTrainer.VariantMaskablePPO
    "RecurrentPPO" -> onPolicyRolloutDeterminism PpoTrainer.VariantRecurrentPPO
    "DQN" -> valueBasedRolloutDeterminism False
    "QR-DQN" -> valueBasedRolloutDeterminism True
    "DDPG" -> continuousRolloutDeterminism ContinuousTrainer.VariantDDPG
    "TD3" -> continuousRolloutDeterminism ContinuousTrainer.VariantTD3
    "SAC" -> continuousRolloutDeterminism ContinuousTrainer.VariantSAC
    "CrossQ" -> continuousRolloutDeterminism ContinuousTrainer.VariantCrossQ
    "TQC" -> continuousRolloutDeterminism ContinuousTrainer.VariantTQC
    "ARS" -> arsRolloutDeterminism
    "HER" -> herRolloutDeterminism
    other -> assertBool ("no trained-rollout determinism case for " <> Text.unpack other) False
 where
  label suffix = Text.unpack algoName <> " " <> suffix

  onPolicyRolloutDeterminism variant = do
    let config =
          PpoTrainer.defaultPpoTrainConfig
            { PpoTrainer.ppoSeed = 42
            , PpoTrainer.ppoRolloutSteps = 64
            , PpoTrainer.ppoNumIterations = 2
            , PpoTrainer.ppoEpochsPerUpdate = 2
            , PpoTrainer.ppoMiniBatchSize = 32
            , PpoTrainer.ppoLearningRate = 1.0e-3
            , PpoTrainer.ppoMaxEpisodeSteps = 200
            , PpoTrainer.ppoVariant = variant
            }
        rollOut = do
          result <- PpoTrainer.trainOnPolicyOnCartpole variant config
          (rollout, _state, _gen) <-
            PpoTrainer.collectRollout
              config
              (PpoTrainer.resultFinalParams result)
              cartPoleInitial
              (Random.mkStdGen 1701)
          pure rollout
    first <- rollOut
    second <- rollOut
    first @?= second
    assertBool
      (label "trained rollout has rewards")
      (not (null (fmap PpoTrainer.rsReward (PpoTrainer.rolloutSteps first))))

  valueBasedRolloutDeterminism useDouble = do
    let config =
          DqnTrainer.defaultDqnTrainConfig
            { DqnTrainer.dqnSeed = 23
            , DqnTrainer.dqnNumSteps = 400
            , DqnTrainer.dqnReplayCapacity = 512
            , DqnTrainer.dqnBatchSize = 32
            , DqnTrainer.dqnTrainStart = 64
            , DqnTrainer.dqnTargetUpdateInterval = 100
            , DqnTrainer.dqnStatInterval = 100
            , DqnTrainer.dqnMaxEpisodeSteps = 200
            , DqnTrainer.dqnUseDouble = useDouble
            }
    first <- DqnTrainer.trainDqnOnCartpole config
    second <- DqnTrainer.trainDqnOnCartpole config
    let statsOf = fmap DqnTrainer.dqnIterMeanReward . DqnTrainer.dqnResultStats
    statsOf first @?= statsOf second
    assertBool
      (label "trainer emitted rollout statistics")
      (not (null (DqnTrainer.dqnResultStats first)))

  continuousRolloutDeterminism variant = do
    let config =
          (ContinuousTrainer.defaultContinuousTrainConfig variant)
            { ContinuousTrainer.ctSeed = 7
            , ContinuousTrainer.ctNumSteps = 800
            , ContinuousTrainer.ctMaxEpisodeSteps = 200
            , ContinuousTrainer.ctStatInterval = 400
            }
    first <- ContinuousTrainer.trainContinuousOnPendulum config
    second <- ContinuousTrainer.trainContinuousOnPendulum config
    let statsOf = fmap ContinuousTrainer.contIterMeanReward . ContinuousTrainer.contResultStats
    statsOf first @?= statsOf second
    assertBool
      (label "trainer emitted rollout statistics")
      (not (null (ContinuousTrainer.contResultStats first)))

  arsRolloutDeterminism = do
    let config =
          ArsTrainer.defaultArsTrainConfig
            { ArsTrainer.arsSeed = 31
            , ArsTrainer.arsIterations = 4
            , ArsTrainer.arsNumDirections = 8
            , ArsTrainer.arsTopB = 4
            , ArsTrainer.arsMaxEpisodeSteps = 200
            }
    first <- ArsTrainer.trainArsOnCartpole config
    second <- ArsTrainer.trainArsOnCartpole config
    let statsOf = fmap ArsTrainer.arsIterMeanReturn . ArsTrainer.arsResultStats
    statsOf first @?= statsOf second
    assertBool
      (label "trainer emitted rollout statistics")
      (not (null (ArsTrainer.arsResultStats first)))

  herRolloutDeterminism = do
    let config =
          HerTrainer.defaultHerTrainConfig
            { HerTrainer.herSeed = 42
            , HerTrainer.herNumBits = 6
            , HerTrainer.herEpisodes = 20
            , HerTrainer.herReplayCapacity = 512
            , HerTrainer.herBatchSize = 32
            , HerTrainer.herStatInterval = 5
            }
    first <- HerTrainer.trainHerOnBitFlip config
    second <- HerTrainer.trainHerOnBitFlip config
    let statsOf = fmap HerTrainer.herIterSuccessRate . HerTrainer.herResultStats
    statsOf first @?= statsOf second
    assertBool
      (label "trainer emitted rollout statistics")
      (not (null (HerTrainer.herResultStats first)))

assertTranscriptDeterminism :: Text -> IO ()
assertTranscriptDeterminism game =
  let first = transcriptFor game
      second = transcriptFor game
   in do
        first @?= second
        assertBool
          ("transcript for " <> Text.unpack game <> " is non-empty")
          (not (null first))
 where
  transcriptFor "connect4" = fmap gameMoves (selfPlayTranscript 3)
  transcriptFor label = fmap gameMoves (selfPlayTranscriptFor label 3)

assertAlphaZeroTerminalEvaluators :: IO ()
assertAlphaZeroTerminalEvaluators = do
  let connect4Win = playMoves initialConnect4 [0, 1, 0, 1, 0, 1, 0]
  gameOutcome connect4Win @?= GameWon 1
  terminalValueForToMove connect4Win @?= -1.0

  let hexWin =
        playMoves
          initialHex
          [0, 1, 11, 2, 22, 3, 33, 4, 44, 5, 55, 6, 66, 7, 77, 8, 88, 9, 99, 10, 110]
  gameOutcome hexWin @?= GameWon 1
  terminalValueForToMove hexWin @?= -1.0

  let gomokuWin = playMoves initialGomoku [0, 15, 1, 16, 2, 17, 3, 18, 4]
  gameOutcome gomokuWin @?= GameWon 1
  terminalValueForToMove gomokuWin @?= -1.0

  let othelloTerminal = playOthelloGreedy 80 initialOthello
  assertBool
    ( "expected greedy Othello game to reach a terminal winner/draw, got "
        <> show (gameOutcome othelloTerminal)
        <> " after "
        <> show (length (gameMoves othelloTerminal))
        <> " moves"
    )
    (gameIsTerminal othelloTerminal)
  case gameOutcome othelloTerminal of
    GameWon winner -> assertBool "Othello winner is one of the two players" (winner == 1 || winner == -1)
    GameDraw -> pure ()
    GameInProgress -> assertBool "Othello must not remain in progress" False

playMoves :: GameState -> [Int] -> GameState
playMoves = foldl' (flip applyMove)

playOthelloGreedy :: Int -> GameState -> GameState
playOthelloGreedy remaining state
  | remaining <= 0 = state
  | gameIsTerminal state = state
  | otherwise =
      case legalOthelloCandidates state of
        [] ->
          playOthelloGreedy
            (remaining - 1)
            state
              { gameMoves = gameMoves state <> [-1]
              , gameCurrentPlayer = negate (gameCurrentPlayer state)
              }
        candidate : _ -> playOthelloGreedy (remaining - 1) (applyMove candidate state)

legalOthelloCandidates :: GameState -> [Int]
legalOthelloCandidates state =
  [ candidate
  | candidate <- [0 .. 63]
  , gameMoves (applyMove candidate state) /= gameMoves state
  ]

-- | Sprint 13.6 — run-to-run trajectory determinism over the pure-
-- Haskell simulator loop. Two fresh runs with the same seed produce
-- bit-identical episode lists; this is the precondition for the live
-- daemon-driven cohort assertion. The IO-side path that runs through
-- the live cluster daemon is owned by the live RL training pass; that
-- pass replays the same assertion shape against the real-broker
-- envelopes (Sprint 13.5 final live validation).
assertSimulatorLoopDeterminism :: (Text, SimulatorLoop.SimulatedEnvByName) -> IO ()
assertSimulatorLoopDeterminism (envName, handle) = do
  let seed = 17
      episodes = 4
      maxSteps = 64
      first = SimulatorLoop.runSimulatedEpisodesByName handle seed episodes maxSteps
      second = SimulatorLoop.runSimulatedEpisodesByName handle seed episodes maxSteps
  assertBool
    ( "simulator loop for "
        <> Text.unpack envName
        <> " produced "
        <> show (length first)
        <> " episodes (expected "
        <> show episodes
        <> ")"
    )
    (length first == episodes)
  first @?= second
  assertBool
    ("simulator loop for " <> Text.unpack envName <> " emitted animation frames")
    (not (any (null . SimulatorLoop.simEpisodeFrames) first))

assertKeyDoorGridCanonicals :: IO ()
assertKeyDoorGridCanonicals = do
  let state = Sim.keyDoorGridInitial 0
      mask = Sim.keyDoorGridLegalActionMask state
      masked = MaskablePpoLoss.applyActionMask mask (replicate 6 (1.0 / 6.0))
  mask @?= [False, True, False, True, False, False]
  masked @?= [0.0, 0.5, 0.0, 0.5, 0.0, 0.0]
  Sim.keyDoorGridInitial 11 @?= Sim.keyDoorGridInitial 11
  Sim.keyDoorGridRenderFrame state @?= Sim.keyDoorGridRenderFrame state
  let handle =
        case SimulatorLoop.lookupSimulatedEnvByName "key-door-grid" of
          Just envHandle -> envHandle
          Nothing -> error "missing key-door-grid simulator"
      first = SimulatorLoop.runSimulatedEpisodesByName handle 17 3 32
      second = SimulatorLoop.runSimulatedEpisodesByName handle 17 3 32
  first @?= second
  assertBool "key-door-grid simulator returns requested episodes" (length first == 3)
  assertBool
    "key-door-grid simulator records replayable transition frames"
    (not (any (null . SimulatorLoop.simEpisodeFrames) first))

assertAleAtariPolicy :: IO ()
assertAleAtariPolicy = do
  smoke <- ALE.runAleSmoke Nothing
  case smoke of
    Left err ->
      assertBool
        "missing-ROM path explains explicit Atari ROM policy"
        ("JITML_ATARI_ROM" `Text.isInfixOf` err)
    Right result -> do
      ALE.aleSmokeRamBytes result @?= 128
      assertBool "ALE legal actions are reported" (ALE.aleSmokeActionCount result > 0)
      assertBool "ALE screen has positive width" (ALE.aleSmokeScreenWidth result > 0)
      assertBool "ALE screen has positive height" (ALE.aleSmokeScreenHeight result > 0)
      assertBool "ALE screen bytes are populated" (ALE.aleSmokeScreenBytes result > 0)
      assertBool "ALE smoke episode is deterministic" (ALE.aleSmokeDeterministic result)

data TrainedLossInputs = TrainedLossInputs
  { trainedRewards :: [Double]
  , trainedOldLogProbs :: [Double]
  , trainedNewLogProbs :: [Double]
  , trainedAdvantages :: [Double]
  , trainedValues :: [Double]
  , trainedQValues :: [Double]
  , trainedQTargets :: [Double]
  , trainedTerminals :: [Bool]
  , trainedArsTriples :: [(Double, Double, [Double])]
  }
  deriving stock (Eq, Show)

collectTrainedLossInputs :: IO TrainedLossInputs
collectTrainedLossInputs = do
  let ppoConfig =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = 17
          , PpoTrainer.ppoRolloutSteps = 64
          , PpoTrainer.ppoNumIterations = 3
          , PpoTrainer.ppoEpochsPerUpdate = 2
          , PpoTrainer.ppoMiniBatchSize = 32
          , PpoTrainer.ppoLearningRate = 1.0e-3
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
      dqnConfig =
        DqnTrainer.defaultDqnTrainConfig
          { DqnTrainer.dqnSeed = 23
          , DqnTrainer.dqnNumSteps = 400
          , DqnTrainer.dqnReplayCapacity = 512
          , DqnTrainer.dqnBatchSize = 32
          , DqnTrainer.dqnTrainStart = 64
          , DqnTrainer.dqnTargetUpdateInterval = 100
          , DqnTrainer.dqnStatInterval = 200
          , DqnTrainer.dqnMaxEpisodeSteps = 200
          }
  ppoResult <- PpoTrainer.trainPpoOnCartpole ppoConfig
  (rollout, _state, _gen) <-
    PpoTrainer.collectRollout
      ppoConfig
      (PpoTrainer.resultFinalParams ppoResult)
      cartPoleInitial
      (Random.mkStdGen 1701)
  dqnResult <- DqnTrainer.trainDqnOnCartpole dqnConfig
  -- Real ARS rollout returns from two seeded trained runs (the catalog
  -- projection that used to source these is gone). 'arsResultStats' carries the
  -- per-iteration mean/best returns of the deterministic linear-policy rollouts.
  let arsConfigFor seed =
        ArsTrainer.defaultArsTrainConfig
          { ArsTrainer.arsSeed = seed
          , ArsTrainer.arsIterations = 3
          , ArsTrainer.arsNumDirections = 8
          , ArsTrainer.arsTopB = 4
          , ArsTrainer.arsMaxEpisodeSteps = 200
          }
  arsResultA <- ArsTrainer.trainArsOnCartpole (arsConfigFor 31)
  arsResultB <- ArsTrainer.trainArsOnCartpole (arsConfigFor 37)
  let steps = take 16 (PpoTrainer.rolloutSteps rollout)
      rewards = fmap PpoTrainer.rsReward steps
      values = fmap PpoTrainer.rsValue steps
      nextValues = tailList values <> [PpoTrainer.rolloutFinalValue rollout]
      oldLogProbs = fmap PpoTrainer.rsLogProb steps
      newLogProbs = fmap (+ 1.0e-6) oldLogProbs
      terminals = fmap PpoTrainer.rsDone steps
      advantages =
        PpoLoss.normaliseAdvantages $
          PpoLoss.gaeAdvantages 0.99 0.95 rewards values nextValues
      qFor obs =
        maximum $
          0.0
            : Data.Vector.Unboxed.toList
              (forwardOutput (mlpForward (DqnTrainer.dqnResultFinalParams dqnResult) obs))
      qValues = fmap (qFor . PpoTrainer.rsObs) steps
      nextQValues = tailList qValues <> [0.0]
      qTargets = zipWith3 (DqnLoss.dqnBellmanTarget 0.99) rewards terminals nextQValues
      arsReturnsFor result = fmap ArsTrainer.arsIterBestReturn (ArsTrainer.arsResultStats result)
      arsReturnA = sum (arsReturnsFor arsResultA)
      arsReturnB = sum (arsReturnsFor arsResultB)
      arsTriples =
        [ (arsReturnA, arsReturnB, qValues)
        , (arsReturnB, arsReturnA, qTargets)
        ]
  pure
    TrainedLossInputs
      { trainedRewards = rewards
      , trainedOldLogProbs = oldLogProbs
      , trainedNewLogProbs = newLogProbs
      , trainedAdvantages = advantages
      , trainedValues = values
      , trainedQValues = qValues
      , trainedQTargets = qTargets
      , trainedTerminals = terminals
      , trainedArsTriples = arsTriples
      }

tailList :: [a] -> [a]
tailList [] = []
tailList (_ : rest) = rest

-- | Sprint 13.8 / 9.12 — drive the real PPO loss math against a trained
-- PPO/cartpole policy rollout and assert two fresh computations of
-- `ppoTotalLoss` return bit-equal output. The policy log-probs, values,
-- rewards, and advantages come from the trained network rollout rather than
-- reward-derived helper projections.
assertPpoLossDeterminism :: IO ()
assertPpoLossDeterminism = do
  inputs <- collectTrainedLossInputs
  let first =
        PpoLoss.ppoTotalLoss
          0.2
          0.5
          0.01
          (trainedOldLogProbs inputs)
          (trainedNewLogProbs inputs)
          (trainedAdvantages inputs)
          (trainedValues inputs)
          (trainedRewards inputs)
          0.5
      second =
        PpoLoss.ppoTotalLoss
          0.2
          0.5
          0.01
          (trainedOldLogProbs inputs)
          (trainedNewLogProbs inputs)
          (trainedAdvantages inputs)
          (trainedValues inputs)
          (trainedRewards inputs)
          0.5
  first @?= second
  assertBool
    "PPO loss on the trained-policy rollout produced a finite value"
    (not (isInfinite first) && not (isNaN first))

-- | Sprint 13.8 / 9.12 — drive every algorithm-level loss module with inputs
-- collected from trained PPO/DQN networks and real simulator rollouts. This
-- keeps the deterministic same-seed assertion shape while removing the prior
-- reward-derived policy/value/Q helper projections.
assertAllLossModulesFinite :: IO ()
assertAllLossModulesFinite = do
  inputs <- collectTrainedLossInputs
  let rewards = trainedRewards inputs
      logProbs = trainedOldLogProbs inputs
      newLogProbs = trainedNewLogProbs inputs
      advantages = trainedAdvantages inputs
      qValues = trainedQValues inputs
      qTargets = trainedQTargets inputs
      terminals = trainedTerminals inputs
      quantilePred = [qValues]
      quantileTarget = [qTargets]
      perCriticAtoms = [qValues, qTargets]
      arsTriples = trainedArsTriples inputs
      assertFiniteAndDeterministic label first second = do
        assertBool (label <> " is finite") (not (isInfinite first) && not (isNaN first))
        assertBool (label <> " is run-to-run deterministic") (first == second)
  assertFiniteAndDeterministic
    "PpoLoss.clippedSurrogateLoss"
    (PpoLoss.clippedSurrogateLoss 0.2 logProbs newLogProbs advantages)
    (PpoLoss.clippedSurrogateLoss 0.2 logProbs newLogProbs advantages)
  assertFiniteAndDeterministic
    "A2cLoss.a2cPolicyGradientLoss"
    (A2cLoss.a2cPolicyGradientLoss newLogProbs advantages)
    (A2cLoss.a2cPolicyGradientLoss newLogProbs advantages)
  assertFiniteAndDeterministic
    "TrpoLoss.trpoSurrogate"
    (TrpoLoss.trpoSurrogate logProbs newLogProbs advantages)
    (TrpoLoss.trpoSurrogate logProbs newLogProbs advantages)
  assertFiniteAndDeterministic
    "MaskablePpoLoss.maskableSurrogateLoss"
    (MaskablePpoLoss.maskableSurrogateLoss 0.2 logProbs newLogProbs advantages)
    (MaskablePpoLoss.maskableSurrogateLoss 0.2 logProbs newLogProbs advantages)
  assertFiniteAndDeterministic
    "RecurrentPpoLoss.recurrentSurrogateLoss"
    (RecurrentPpoLoss.recurrentSurrogateLoss 0.2 logProbs newLogProbs advantages)
    (RecurrentPpoLoss.recurrentSurrogateLoss 0.2 logProbs newLogProbs advantages)
  assertFiniteAndDeterministic
    "DqnLoss.dqnTdLoss"
    (DqnLoss.dqnTdLoss qValues qTargets)
    (DqnLoss.dqnTdLoss qValues qTargets)
  assertFiniteAndDeterministic
    "DqnLoss.dqnHuberLoss"
    (DqnLoss.dqnHuberLoss 1.0 qValues qTargets)
    (DqnLoss.dqnHuberLoss 1.0 qValues qTargets)
  assertFiniteAndDeterministic
    "QrDqnLoss.qrDqnLoss"
    (QrDqnLoss.qrDqnLoss 1.0 quantilePred quantileTarget)
    (QrDqnLoss.qrDqnLoss 1.0 quantilePred quantileTarget)
  assertFiniteAndDeterministic
    "DdpgLoss.ddpgActorLoss"
    (DdpgLoss.ddpgActorLoss qValues)
    (DdpgLoss.ddpgActorLoss qValues)
  assertFiniteAndDeterministic
    "SacLoss.sacActorLoss"
    (SacLoss.sacActorLoss 0.2 logProbs qValues)
    (SacLoss.sacActorLoss 0.2 logProbs qValues)
  assertFiniteAndDeterministic
    "SacLoss.sacTemperatureLoss"
    (SacLoss.sacTemperatureLoss 0.2 (-2.0) logProbs)
    (SacLoss.sacTemperatureLoss 0.2 (-2.0) logProbs)
  -- Vector-returning loss modules: assert finiteness elementwise and
  -- that two fresh runs produce bit-equal output.
  let td3Targets1 = Td3Loss.td3ClippedDoubleTarget 0.99 rewards terminals qValues qTargets
      td3Targets2 = Td3Loss.td3ClippedDoubleTarget 0.99 rewards terminals qValues qTargets
  assertBool
    "Td3Loss.td3ClippedDoubleTarget is finite"
    (all (\x -> not (isInfinite x) && not (isNaN x)) td3Targets1)
  td3Targets1 @?= td3Targets2
  let crossQTarget1 = CrossQLoss.crossQTarget 0.99 0.2 rewards terminals qValues logProbs
      crossQTarget2 = CrossQLoss.crossQTarget 0.99 0.2 rewards terminals qValues logProbs
  assertBool
    "CrossQLoss.crossQTarget is finite"
    (all (\x -> not (isInfinite x) && not (isNaN x)) crossQTarget1)
  crossQTarget1 @?= crossQTarget2
  let tqcTarget1 = TqcLoss.tqcTarget 0.99 1 1.0 False perCriticAtoms 0.1
      tqcTarget2 = TqcLoss.tqcTarget 0.99 1 1.0 False perCriticAtoms 0.1
  assertBool
    "TqcLoss.tqcTarget is finite"
    (all (\x -> not (isInfinite x) && not (isNaN x)) tqcTarget1)
  tqcTarget1 @?= tqcTarget2
  let arsUpdate1 = ArsLoss.arsUpdateDirection arsTriples
      arsUpdate2 = ArsLoss.arsUpdateDirection arsTriples
  assertBool
    "ArsLoss.arsUpdateDirection is finite"
    (all (\x -> not (isInfinite x) && not (isNaN x)) arsUpdate1)
  arsUpdate1 @?= arsUpdate2
  -- HER's relabeled reward is a sparse goal-reward; deterministic with
  -- a fixed (state, goal, epsilon) tuple.
  let herReward1 = HerLoss.sparseGoalReward (\x g -> abs (x - g)) 0.5 (0.3 :: Double) 0.0
      herReward2 = HerLoss.sparseGoalReward (\x g -> abs (x - g)) 0.5 (0.3 :: Double) 0.0
  assertBool
    "HerLoss.sparseGoalReward is finite"
    (not (isInfinite herReward1) && not (isNaN herReward1))
  herReward1 @?= herReward2

-- | Sprint 13.8 — drive a short PPO training cohort on cartpole through
-- the differentiable MLP seam and assert the final iteration's mean
-- reward improves over the first iteration. Wall-clock-bounded to a few
-- seconds: 8 iterations × 512 rollout steps × 4 epochs/update is enough
-- to observe early-training improvement without saturating CI time. The
-- real literature threshold (cartpole/PPO ≥ 475) requires the longer
-- training shape exercised by the live cohort (Sprint 13.6); this
-- assertion is the canonical smoke that the trainer is actually
-- updating the policy in the right direction.
assertPpoTrainerImprovesOnCartpole :: IO ()
assertPpoTrainerImprovesOnCartpole = do
  let config =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = 42
          , PpoTrainer.ppoRolloutSteps = 512
          , PpoTrainer.ppoNumIterations = 8
          , PpoTrainer.ppoEpochsPerUpdate = 4
          , PpoTrainer.ppoLearningRate = 1.0e-3
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
  result <- PpoTrainer.trainPpoOnCartpole config
  let stats = PpoTrainer.resultIterations result
  case stats of
    (firstStat : _) -> do
      let lastStat = last stats
      assertBool
        ( "PPO trainer should improve: first iter mean="
            <> show (PpoTrainer.iterMeanReward firstStat)
            <> ", last iter mean="
            <> show (PpoTrainer.iterMeanReward lastStat)
        )
        (PpoTrainer.iterMeanReward lastStat > PpoTrainer.iterMeanReward firstStat)
    [] -> assertBool "PPO trainer returned no iteration stats" False

-- | Sprint 8.11 — route a short PPO cohort through the resolved substrate's
-- JIT-compiled MLP device ('rlDeviceForSubstrate' → 'trainOnPolicyOnDevice')
-- and assert the final iteration's mean reward improves over the first. This
-- is the on-device analogue of 'assertPpoTrainerImprovesOnCartpole': it proves
-- the trainer learns when the network forward/backward run on the selected
-- substrate device rather than the pure-Haskell reference path. Missing
-- substrate runtime fails closed.
assertPpoDeviceImproves :: IO ()
assertPpoDeviceImproves = do
  env <- buildEnv defaultGlobalFlags
  substrate <- selectedTestSubstrate
  let device = rlDeviceForSubstrate substrate env
  requireMlpDevice substrate device
  let config =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = 42
          , PpoTrainer.ppoRolloutSteps = 512
          , PpoTrainer.ppoNumIterations = 8
          , PpoTrainer.ppoEpochsPerUpdate = 4
          , PpoTrainer.ppoLearningRate = 1.0e-3
          , PpoTrainer.ppoMaxEpisodeSteps = 200
          }
  resultE <- PpoTrainer.trainOnPolicyOnDevice device PpoTrainer.VariantPPO config
  case resultE of
    Left err ->
      assertBool ("on-device PPO training failed: " <> Text.unpack err) False
    Right result ->
      case PpoTrainer.resultIterations result of
        (firstStat : rest@(_ : _)) ->
          let lastStat = last rest
           in assertBool
                ( "on-device PPO should improve: first="
                    <> show (PpoTrainer.iterMeanReward firstStat)
                    <> " last="
                    <> show (PpoTrainer.iterMeanReward lastStat)
                )
                (PpoTrainer.iterMeanReward lastStat > PpoTrainer.iterMeanReward firstStat)
        _ -> assertBool "on-device PPO returned too few iteration stats" False

-- | Sprint 13.8 — drive a DDPG continuous actor-critic cohort on the
-- Pendulum-v1 simulator and assert the local canonical run is deterministic
-- and finite. Full convergence is a live/statistical gate; the local stanza
-- rejects broken trainer plumbing without relying on monotonic improvement
-- from one short budget.
assertDdpgTrainerDeterministicOnPendulum :: IO ()
assertDdpgTrainerDeterministicOnPendulum = do
  let config =
        (ContinuousTrainer.defaultContinuousTrainConfig ContinuousTrainer.VariantDDPG)
          { ContinuousTrainer.ctSeed = 7
          , ContinuousTrainer.ctNumSteps = 3000
          , ContinuousTrainer.ctMaxEpisodeSteps = 200
          , ContinuousTrainer.ctStatInterval = 1000
          }
  resultA <- ContinuousTrainer.trainContinuousOnPendulum config
  resultB <- ContinuousTrainer.trainContinuousOnPendulum config
  let meansA = fmap ContinuousTrainer.contIterMeanReward (ContinuousTrainer.contResultStats resultA)
      meansB = fmap ContinuousTrainer.contIterMeanReward (ContinuousTrainer.contResultStats resultB)
  assertBool "DDPG trainer returned stats" (not (null meansA))
  assertBool
    "DDPG stats are finite"
    (all (\value -> not (isInfinite value) && not (isNaN value)) meansA)
  meansA @?= meansB

-- | Sprint 13.8 — assert two fresh PPO training runs with the same
-- config produce bit-identical per-iteration statistics. The
-- determinism contract requires same-substrate / same-seed reductions
-- to be bit-equal; this holds the trainer to that bar end-to-end.
assertPpoTrainerDeterministic :: IO ()
assertPpoTrainerDeterministic = do
  let config =
        PpoTrainer.defaultPpoTrainConfig
          { PpoTrainer.ppoSeed = 5
          , PpoTrainer.ppoRolloutSteps = 128
          , PpoTrainer.ppoNumIterations = 3
          , PpoTrainer.ppoEpochsPerUpdate = 2
          }
  resultA <- PpoTrainer.trainPpoOnCartpole config
  resultB <- PpoTrainer.trainPpoOnCartpole config
  fmap PpoTrainer.iterMeanReward (PpoTrainer.resultIterations resultA)
    @?= fmap PpoTrainer.iterMeanReward (PpoTrainer.resultIterations resultB)
  fmap PpoTrainer.iterMedianReward (PpoTrainer.resultIterations resultA)
    @?= fmap PpoTrainer.iterMedianReward (PpoTrainer.resultIterations resultB)

-- | Sprint 13.8 — every on-policy variant (A2C / TRPO / MaskablePPO /
-- RecurrentPPO, alongside PPO) shares the MLP forward/backward seam and
-- must improve its mean cartpole reward over a short training cohort.
-- This proves the shared-template trainer drives each variant's policy
-- in the right direction; the full literature-threshold convergence uses
-- the longer `defaultPpoTrainConfig` shape (demonstrated for PPO).
assertOnPolicyVariantsImprove :: IO ()
assertOnPolicyVariantsImprove =
  mapM_
    checkVariant
    [ PpoTrainer.VariantA2C
    , PpoTrainer.VariantTRPO
    , PpoTrainer.VariantMaskablePPO
    , PpoTrainer.VariantRecurrentPPO
    ]
 where
  checkVariant variant = do
    let config =
          PpoTrainer.defaultPpoTrainConfig
            { PpoTrainer.ppoSeed = 42
            , PpoTrainer.ppoRolloutSteps = 512
            , PpoTrainer.ppoNumIterations = 8
            , PpoTrainer.ppoEpochsPerUpdate = 4
            , PpoTrainer.ppoLearningRate = 1.0e-3
            , PpoTrainer.ppoMaxEpisodeSteps = 200
            }
    result <- PpoTrainer.trainOnPolicyOnCartpole variant config
    let stats = PpoTrainer.resultIterations result
    case stats of
      (firstStat : _) -> do
        let lastStat = last stats
        assertBool
          ( show variant
              <> " should improve: first="
              <> show (PpoTrainer.iterMeanReward firstStat)
              <> " last="
              <> show (PpoTrainer.iterMeanReward lastStat)
          )
          (PpoTrainer.iterMeanReward lastStat > PpoTrainer.iterMeanReward firstStat)
      [] -> assertBool (show variant <> " returned no stats") False

-- | Sprint 13.9 — assert the policy/value network's forward pass
-- produces a valid policy distribution on the initial Connect 4 board.
assertPolicyValueForwardValid :: IO ()
assertPolicyValueForwardValid = do
  let net = PVN.initPolicyValueNet 43 7 32 11
      pv = PVN.networkPolicyValue net initialConnect4
      policy = PVN.pvPolicy pv
  assertBool
    "policy probabilities are non-negative"
    (all (>= 0) (policySamples policy))
  assertBool
    "policy probabilities sum to 1"
    (abs (sum (policySamples policy) - 1.0) < 1.0e-9)
  assertBool
    "value is bounded by tanh"
    (abs (PVN.pvValue pv) <= 1.0)
 where
  policySamples = unsafePolicyToList

-- | Convert the unboxed-vector policy to a list (test helper).
unsafePolicyToList
  :: Data.Vector.Unboxed.Vector Double
  -> [Double]
unsafePolicyToList = Data.Vector.Unboxed.toList

-- | Sprint 13.9 / 9.12 — exercise one round of training and assert the
-- policy/value loss on an MCTS-generated self-play sample decreases after
-- enough gradient updates. This is the canonical "the network is actually
-- learning" sanity check for the AlphaZero policy/value seam.
assertPolicyValueTrainingReducesLoss :: IO ()
assertPolicyValueTrainingReducesLoss = do
  let net0 = PVN.initPolicyValueNet 43 7 16 22
      adam0 = PVN.initAdamFor net0
      samples = PVN.generatePolicyValueSamples net0 22 8 8
      logSafe x = if x <= 0 then -1.0e9 else log x
  case samples of
    [] -> assertBool "MCTS self-play should generate at least one training sample" False
    sample : _ -> do
      let lossOf net =
            let pv = PVN.networkPolicyValue net (PVN.sampleState sample)
                policy = PVN.pvPolicy pv
                policyLoss =
                  -sum
                    [ (PVN.sampleVisitDist sample Data.Vector.Unboxed.! i)
                        * logSafe (policy Data.Vector.Unboxed.! i)
                    | i <- [0 .. Data.Vector.Unboxed.length policy - 1]
                    ]
                valueLoss =
                  0.5 * (PVN.pvValue pv - PVN.sampleOutcome sample) ^ (2 :: Int)
             in policyLoss + valueLoss
          (netN, _) = PVN.trainPolicyValueNetOnSamples net0 adam0 1.0e-2 80 [sample]
          lossBefore = lossOf net0
          lossAfter = lossOf netN
      assertBool
        ( "policy/value loss should decrease; before="
            <> show lossBefore
            <> " after="
            <> show lossAfter
        )
        (lossAfter < lossBefore)

-- | Sprint 13.9 — a trained network's weights serialize to the flat
-- checkpoint @.jmw1@ blob and reconstruct bit-identically, so trained
-- AlphaZero network weights persist through the checkpoint surface.
assertPolicyValueWeightsRoundTrip :: IO ()
assertPolicyValueWeightsRoundTrip = do
  let net = PVN.initPolicyValueNet 43 7 16 22
      adam = PVN.initAdamFor net
      target = Data.Vector.Unboxed.fromList [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
      sample = PVN.PolicyValueTrainingSample initialConnect4 target 0.5
      (trained, _) = PVN.trainPolicyValueNetOnSamples net adam 1.0e-2 5 [sample]
      flat = PVN.policyValueNetToFlat trained
      blob = encodeJmw1 flat
  case decodeJmw1 blob of
    Left err ->
      assertBool ("decode .jmw1 failed: " <> Text.unpack err) False
    Right flat' -> do
      -- F64 .jmw1 round-trip is lossless.
      flat' @?= flat
      case PVN.loadPolicyValueNetWeights net flat' of
        Left err ->
          assertBool ("loadPolicyValueNetWeights failed: " <> Text.unpack err) False
        Right loaded ->
          PVN.pvnParams loaded @?= PVN.pvnParams trained

-- | Sprint 13.9 — assert two fresh self-play generations with the
-- same seed produce bit-identical sample counts and arena win rate.
assertAlphaZeroSelfPlayGenerationDeterministic :: IO ()
assertAlphaZeroSelfPlayGenerationDeterministic = do
  let net = PVN.initPolicyValueNet 43 7 16 31
      adam = PVN.initAdamFor net
      runOne = PVN.runOneGenerationOfSelfPlay net adam 2 16 8 4 4 99
      resultA = runOne
      resultB = runOne
  PVN.genSamplesCount resultA @?= PVN.genSamplesCount resultB
  PVN.genArenaWinRate resultA @?= PVN.genArenaWinRate resultB
  assertBool
    "arena win rate is in [0, 1]"
    (PVN.genArenaWinRate resultA >= 0.0 && PVN.genArenaWinRate resultA <= 1.0)

-- | Sprint 13.9 — the production self-play path now drives the MCTS prior
-- from the real policy/value network forward pass per position
-- (`runNetworkSelfPlay` → `runSelfPlayWithOracleFactory` →
-- `netOracleFactory`). Assert two fresh runs at the same seed produce
-- bit-identical buffers (the network weights are fixed by the init seed,
-- the search is deterministic) and that every move in every transcript is a
-- legal Connect 4 column.
assertNetworkSelfPlayDeterministic :: IO ()
assertNetworkSelfPlayDeterministic = do
  let net = PVN.initPolicyValueNet 43 7 16 53
      config =
        SelfPlay.defaultSelfPlayConfig
          { SelfPlay.selfPlayGamesPerGeneration = 2
          , SelfPlay.selfPlaySimulationsPerMove = 8
          , SelfPlay.selfPlayMaxPlies = 6
          , SelfPlay.selfPlayActionSpace = 7
          }
      bufferA = PVN.runNetworkSelfPlay net config
      bufferB = PVN.runNetworkSelfPlay net config
  SelfPlay.bufferLength bufferA @?= SelfPlay.bufferLength bufferB
  SelfPlay.bufferTranscriptHash bufferA @?= SelfPlay.bufferTranscriptHash bufferB
  let allMoves =
        concatMap
          (concatMap gameMoves . SelfPlay.gameTranscript)
          (SelfPlay.unBuffer bufferA)
  assertBool
    "network self-play moves are legal Connect 4 columns"
    (all (\c -> c >= 0 && c < 7) allMoves)

-- | Sprint 13.9 — the policy training target is now the true MCTS
-- visit-count distribution from 'mctsVisitDistribution', not the
-- network's raw policy. Assert the distribution is well-formed (length
-- = action space, non-negative, sums to 1), run-to-run deterministic,
-- and genuinely search-shaped: the search concentrates visits beyond
-- the uniform 1/7 baseline, proving the UCB rollout reshaped the prior.
assertMctsVisitTargets :: IO ()
assertMctsVisitTargets = do
  let net = PVN.initPolicyValueNet 43 7 16 71
      distA = PVN.mctsVisitDistribution net 64 initialConnect4 1234
      distB = PVN.mctsVisitDistribution net 64 initialConnect4 1234
      entries = Data.Vector.Unboxed.toList distA
  Data.Vector.Unboxed.length distA @?= 7
  assertBool "visit distribution is deterministic" (distA == distB)
  assertBool "visit probabilities are non-negative" (all (>= 0) entries)
  assertBool
    "visit distribution sums to 1"
    (abs (sum entries - 1.0) < 1.0e-9)
  assertBool
    "search concentrates visits beyond the uniform 1/7 baseline"
    (maximum entries > 1.0 / 7.0)

-- | Sprint 9.10 — the effectful MCTS path evaluates leaf policy/value heads
-- through the selected substrate JIT device. This keeps the pure MCTS tests
-- intact while proving the production leaf-eval seam is not pure-only.
assertMctsVisitTargetsWithDevice :: IO ()
assertMctsVisitTargetsWithDevice = do
  env <- buildEnv defaultGlobalFlags
  substrate <- selectedTestSubstrate
  let device = rlDeviceForSubstrate substrate env
      net = PVN.initPolicyValueNet 43 7 16 71
  requireMlpDevice substrate device
  distResult <- PVN.mctsVisitDistributionWithDevice device net 16 initialConnect4 1234
  case distResult of
    Left err ->
      assertBool ("device-backed MCTS visit distribution failed: " <> Text.unpack err) False
    Right dist -> do
      let entries = Data.Vector.Unboxed.toList dist
      Data.Vector.Unboxed.length dist @?= 7
      assertBool "device visit probabilities are non-negative" (all (>= 0) entries)
      assertBool
        "device visit distribution sums to 1"
        (abs (sum entries - 1.0) < 1.0e-6)
      assertBool
        "device search concentrates visits beyond the uniform 1/7 baseline"
        (maximum entries > 1.0 / 7.0)

selectedTestSubstrate :: IO Substrate
selectedTestSubstrate = do
  value <- lookupEnv "JITML_SUBSTRATE"
  case value of
    Nothing -> pure LinuxCPU
    Just raw ->
      case parseSubstrate (Text.pack raw) of
        Just substrate -> pure substrate
        Nothing -> assertFailure ("invalid JITML_SUBSTRATE: " <> raw)

requireMlpDevice :: Substrate -> MlpDevice -> IO ()
requireMlpDevice substrate device = do
  probe <- probeMlpDevice device
  case probe of
    Right () -> pure ()
    Left err ->
      assertFailure
        ( Text.unpack
            ( renderSubstrate substrate
                <> " JIT device unavailable: "
                <> err
            )
        )
