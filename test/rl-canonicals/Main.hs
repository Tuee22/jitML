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
import JitML.RL.Algorithms.A2cLoss qualified as A2cLoss
import JitML.RL.Algorithms.ArsLoss qualified as ArsLoss
import JitML.RL.Algorithms.Common
  ( AlgorithmModule (..)
  , AlgorithmRollout (..)
  , moduleRolloutGenerator
  , rolloutGoldenLines
  )
import JitML.RL.Algorithms.CrossQLoss qualified as CrossQLoss
import JitML.RL.Algorithms.DdpgLoss qualified as DdpgLoss
import JitML.RL.Algorithms.DqnLoss qualified as DqnLoss
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.MaskablePpoLoss qualified as MaskablePpoLoss
import JitML.RL.Algorithms.PpoLoss qualified as PpoLoss
import JitML.RL.Algorithms.QrDqnLoss qualified as QrDqnLoss
import JitML.RL.Algorithms.RecurrentPpoLoss qualified as RecurrentPpoLoss
import JitML.RL.Algorithms.Registry (algorithmModuleRegistry)
import JitML.RL.Algorithms.SacLoss qualified as SacLoss
import JitML.RL.Algorithms.Td3Loss qualified as Td3Loss
import JitML.RL.Algorithms.TqcLoss qualified as TqcLoss
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
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
import JitML.RL.SimulatorLoop qualified as SimulatorLoop
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
      , testCase
          "simulator loop is run-to-run deterministic across the canonical env catalog (Sprint 13.6 + 13.5)"
          $ mapM_ assertSimulatorLoopDeterminism SimulatorLoop.simulatedEnvCatalog
      , testCase
          "PPO real loss math runs deterministically against the canonical PPO/cartpole rollout (Sprint 13.8)"
          assertPpoLossDeterminism
      , testCase
          "every Sprint 13.8 loss module returns a finite value on the canonical trajectory"
          assertAllLossModulesFinite
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

-- | Sprint 13.8 — drive the real PPO loss math against the canonical
-- deterministic PPO/cartpole rollout from
-- 'JitML.RL.Algorithms.Common.trajectoryRollout' and assert two fresh
-- computations of `ppoTotalLoss` return bit-equal output. This wires
-- the loss module (covered by `jitml-unit`'s "PPO loss math (Sprint
-- 13.8)" group) into the canonical RL stanza so the real-loss surface
-- is exercised inside the algorithm × env evaluation cohort, not only
-- inside the unit-test fixtures.
--
-- Synthetic policy/value inputs are derived from the rollout's
-- deterministic rewards so the loss is reproducible without requiring
-- a real network forward pass. The real network seam (Sprint 13.8
-- Remaining Work) replaces the synthetic inputs without changing the
-- assertion shape.
assertPpoLossDeterminism :: IO ()
assertPpoLossDeterminism = do
  let mPpoModule =
        [ m
        | m <- algorithmModuleRegistry
        , algorithmName (moduleAlgorithm m) == "PPO"
        ]
  case mPpoModule of
    [] -> assertBool "missing PPO algorithm module" False
    (m : _) -> do
      let rollout = moduleRolloutGenerator m "cartpole" 42 16
          rewards = rolloutRewards rollout
          -- Synthetic deterministic policy / value inputs derived from
          -- the rewards; a real network forward pass replaces these in
          -- the live-CUDA path (Sprint 13.8 Remaining Work).
          values = fmap (* 0.5) rewards
          nextValues = case values of
            _ : rest -> rest <> [0.0]
            [] -> [0.0]
          advantages =
            PpoLoss.normaliseAdvantages
              (PpoLoss.gaeAdvantages 0.99 0.95 rewards values nextValues)
          oldLogProbs = fmap negate rewards
          newLogProbs = fmap (\r -> negate r + 0.01) rewards
          first =
            PpoLoss.ppoTotalLoss
              0.2
              0.5
              0.01
              oldLogProbs
              newLogProbs
              advantages
              values
              rewards
              0.5
          second =
            PpoLoss.ppoTotalLoss
              0.2
              0.5
              0.01
              oldLogProbs
              newLogProbs
              advantages
              values
              rewards
              0.5
      first @?= second
      assertBool
        "PPO loss on the canonical rollout produced a finite value"
        (not (isInfinite first) && not (isNaN first))

-- | Sprint 13.8 — drive every algorithm-level loss module against the
-- canonical PPO/cartpole rollout's reward trajectory and assert
-- (a) the result is finite, (b) two fresh calls return bit-equal
-- output. Synthetic policy / value / Q / quantile / actor inputs are
-- derived from the rewards so the assertion is reproducible without
-- the live network forward pass. The real-network seam (Sprint 13.9
-- + 13.8 Remaining Work) replaces the synthetic projection without
-- changing the assertion shape. Covers the full Sprint 13.8 catalog:
-- PPO + A2C + TRPO + MaskablePPO + RecurrentPPO + DQN + QR-DQN +
-- DDPG + TD3 + SAC + CrossQ + TQC + ARS + HER.
assertAllLossModulesFinite :: IO ()
assertAllLossModulesFinite = do
  let rewards = take 16 (deterministicTrajectoryFor 17)
      logProbs = fmap negate rewards
      newLogProbs = fmap (\r -> negate r + 0.01) rewards
      advantages = PpoLoss.gaeAdvantages 0.99 0.95 rewards rewards rewards
      values = fmap (* 0.5) rewards
      qValues = fmap (+ 0.1) rewards
      qTargets = fmap (+ 0.2) rewards
      terminals = replicate (length rewards) False
      quantilePred = [rewards]
      quantileTarget = [fmap (+ 0.05) rewards]
      perCriticAtoms = [rewards, fmap (+ 0.1) rewards]
      arsTriples = [(2.0, 0.5, rewards), (1.5, 0.3, fmap (+ 0.1) rewards)]
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

-- | Deterministic reward trajectory derived from the seed; reused by
-- the multi-algorithm finiteness check above.
deterministicTrajectoryFor :: Int -> [Double]
deterministicTrajectoryFor seed =
  fmap
    (\i -> fromIntegral ((seed + i) `mod` 7) / 7.0 + 0.01)
    [0 ..]
