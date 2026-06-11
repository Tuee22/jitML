{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import Data.Vector.Unboxed qualified
import JitML.Checkpoint.Format (decodeJmw1, encodeJmw1)
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Numerics.MlpDevice (probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (rlDeviceForSubstrate)
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
import JitML.RL.ALE qualified as ALE
import JitML.RL.Algorithms (algorithmCatalog, algorithmName, deterministicTrajectory)
import JitML.RL.Algorithms.A2cLoss qualified as A2cLoss
import JitML.RL.Algorithms.ArsLoss qualified as ArsLoss
import JitML.RL.Algorithms.Common
  ( AlgorithmModule (..)
  , AlgorithmRollout (..)
  , moduleRolloutGenerator
  )
import JitML.RL.Algorithms.ContinuousTrainer qualified as ContinuousTrainer
import JitML.RL.Algorithms.CrossQLoss qualified as CrossQLoss
import JitML.RL.Algorithms.DdpgLoss qualified as DdpgLoss
import JitML.RL.Algorithms.DqnLoss qualified as DqnLoss
import JitML.RL.Algorithms.HerLoss qualified as HerLoss
import JitML.RL.Algorithms.MaskablePpoLoss qualified as MaskablePpoLoss
import JitML.RL.Algorithms.PpoLoss qualified as PpoLoss
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.RL.Algorithms.QrDqnLoss qualified as QrDqnLoss
import JitML.RL.Algorithms.RecurrentPpoLoss qualified as RecurrentPpoLoss
import JitML.RL.Algorithms.Registry (algorithmModuleRegistry)
import JitML.RL.Algorithms.SacLoss qualified as SacLoss
import JitML.RL.Algorithms.Td3Loss qualified as Td3Loss
import JitML.RL.Algorithms.TqcLoss qualified as TqcLoss
import JitML.RL.Algorithms.TrpoLoss qualified as TrpoLoss
import JitML.RL.AlphaZero (gameMoves, initialConnect4, selfPlayTranscript, selfPlayTranscriptFor)
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.AlphaZero.SelfPlay qualified as SelfPlay
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
import JitML.RL.Simulator qualified as Sim
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
      , testCase "PPO CartPole trajectory regenerates deterministically without fixtures" $ do
          let first = deterministicTrajectory "PPO" 42
              second = deterministicTrajectory "PPO" 42
          first @?= second
          assertBool "trajectory is non-empty" (not (null first))
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
      , testCase "per-algorithm deterministic rollouts regenerate without fixtures" $
          mapM_ (uncurry checkRolloutDeterminism) algorithmRolloutCohorts
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
          "policy/value network gradient update reduces a synthetic policy/value loss (Sprint 13.9)"
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

checkRolloutDeterminism :: Text -> Text -> IO ()
checkRolloutDeterminism algoName envName =
  case [m | m <- algorithmModuleRegistry, algorithmName (moduleAlgorithm m) == algoName] of
    [] -> assertBool ("missing algorithm module for " <> show algoName) False
    (m : _) -> do
      let first = moduleRolloutGenerator m envName 42 8
          second = moduleRolloutGenerator m envName 42 8
      first @?= second
      assertBool
        ("rollout for " <> Text.unpack algoName <> "/" <> Text.unpack envName <> " has rewards")
        (not (null (rolloutRewards first)))

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
-- the trainer learns when the network forward/backward run on the real oneDNN
-- kernel (under `--linux-cpu`) rather than the pure-Haskell reference path. On
-- a host without the substrate toolchain the device probe returns Left and the
-- case skips with a passing message (the live-test skip convention).
assertPpoDeviceImproves :: IO ()
assertPpoDeviceImproves = do
  env <- buildEnv defaultGlobalFlags
  let device = rlDeviceForSubstrate LinuxCPU env
  probe <- probeMlpDevice device
  case probe of
    Left _ ->
      assertBool "linux-cpu JIT device unavailable; on-device PPO improvement skipped" True
    Right () -> do
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

-- | Sprint 13.9 — exercise one round of training and assert the
-- mean-squared error on a synthetic batch decreases after enough
-- gradient updates. This is the canonical "the network is actually
-- learning" sanity check for the AlphaZero policy/value seam.
assertPolicyValueTrainingReducesLoss :: IO ()
assertPolicyValueTrainingReducesLoss = do
  let net0 = PVN.initPolicyValueNet 43 7 16 22
      adam0 = PVN.initAdamFor net0
      target =
        Data.Vector.Unboxed.fromList [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0]
      sample =
        PVN.PolicyValueTrainingSample
          { PVN.sampleState = initialConnect4
          , PVN.sampleVisitDist = target
          , PVN.sampleOutcome = 0.5
          }
      lossOf net =
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
      logSafe x = if x <= 0 then -1.0e9 else log x
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
