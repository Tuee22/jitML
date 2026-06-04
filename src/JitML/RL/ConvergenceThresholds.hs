{-# LANGUAGE OverloadedStrings #-}

-- | In-code per-(algorithm, environment) convergence threshold table for the
-- canonical RL cohort. Each entry declares a `literatureTarget` (the mean
-- final return reported in the public literature or native jitML target) and
-- a `slack` (the additive tolerance below that mean which a `jitml rl train`
-- median over k seeds must still clear). The convergence assertion in Sprint
-- 13.6 is
--
--   median(final_reward over k seeds) >= literatureTarget - slack
--
-- The values come from the published Stable-Baselines3 zoo benchmarks
-- (`rl-baselines3-zoo` v2.5) and the standard envs (Gymnasium classic
-- control + Box2D) or from the repo-owned KeyDoorGrid-v0 success reward.
-- Where a particular algorithm doesn't naturally apply to a given environment
-- (e.g. DQN on continuous action spaces, HER on non-goal-conditioned envs),
-- the cohort is omitted — `cohortThreshold` returns `Nothing` and the test
-- stanza skips it. Atari/ALE remains optional runtime support and is not part
-- of the required convergence matrix.
--
-- These are literature anchors, not per-host empirical curves. They do
-- not vary by substrate (linux-cpu / linux-cuda / apple-silicon). No
-- per-substrate or per-host fixture file is committed; the only source of
-- ground truth is this table. Tightening or loosening a slack requires a
-- code change.
--
-- See [../README.md → Convergence and determinism checks for RL](../../../README.md#convergence-and-determinism-checks-for-rl).
module JitML.RL.ConvergenceThresholds
  ( ConvergenceThreshold (..)
  , cohortThreshold
  , cohortThresholds
  , passesConvergence
  )
where

import Data.Text (Text)

-- | Literature-anchored convergence threshold for one (algorithm, environment)
-- cohort. Both fields are in the environment's native reward units.
data ConvergenceThreshold = ConvergenceThreshold
  { literatureTarget :: Double
  -- ^ Published mean final reward from the SB3 zoo (or equivalent).
  , slack :: Double
  -- ^ Additive tolerance below the target. Picked per-algorithm based on
  --   the algorithm's known training variance; on-policy stable algorithms
  --   get tighter slack, exploration-noisy algorithms get wider slack.
  }
  deriving stock (Eq, Show)

-- | Decide whether a measured median final reward passes the convergence
-- assertion for a cohort. Higher is better for cartpole / lunar-lander /
-- key-door-grid; mountain-car uses negative rewards so the comparison is the
-- same (less negative = better, and target -110 with slack 20 means -130
-- still passes).
passesConvergence :: ConvergenceThreshold -> Double -> Bool
passesConvergence threshold measuredMedian =
  measuredMedian >= literatureTarget threshold - slack threshold

-- | Look up the threshold for a (algorithm, environment) cohort by name.
-- Returns `Nothing` for cohorts that are intentionally not part of the
-- canonical evaluation matrix (e.g. discrete-only DQN on continuous envs,
-- HER on non-goal-conditioned envs).
cohortThreshold :: Text -> Text -> Maybe ConvergenceThreshold
cohortThreshold algorithmName environmentName =
  lookup (algorithmName, environmentName) cohortThresholds

-- | The full canonical cohort table. Algorithm names match
-- `JitML.RL.Algorithms.algorithmCatalog`; environment names match
-- `JitML.RL.Environments.canonicalEnvironments`.
--
-- Coverage policy:
--
-- * On-policy (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO) — all four
--   canonical envs.
-- * Off-policy discrete (DQN, QR-DQN) — discrete-action envs only
--   (cartpole, mountain-car, key-door-grid). Lunar-lander uses the
--   continuous variant by default and is omitted.
-- * Off-policy continuous (DDPG, TD3, SAC, CrossQ, TQC) — continuous /
--   Box2D envs only (lunar-lander). Classic control + KeyDoorGrid are
--   discrete-action and are omitted.
-- * ARS (evolution strategies) — all four envs; it does not care about
--   action-space continuity in jitML's setup.
-- * HER — omitted entirely (needs a goal-conditioned env which the
--   canonical four do not provide).
-- * AlphaZero — omitted (uses an arena win-rate metric, not a return
--   threshold; tracked separately in `JitML.RL.AlphaZero.Arena`).
cohortThresholds :: [((Text, Text), ConvergenceThreshold)]
cohortThresholds =
  -- PPO (canonical on-policy baseline; tight slack on cartpole/lander,
  -- wider on mountain-car due to exploration variance).
  [ (("PPO", "cartpole"), ConvergenceThreshold 475.0 25.0)
  , (("PPO", "mountain-car"), ConvergenceThreshold (-110.0) 30.0)
  , (("PPO", "lunar-lander"), ConvergenceThreshold 200.0 40.0)
  , (("PPO", "key-door-grid"), ConvergenceThreshold 1.0 0.20)
  , -- A2C (synchronous A3C; higher variance than PPO).
    (("A2C", "cartpole"), ConvergenceThreshold 475.0 40.0)
  , (("A2C", "mountain-car"), ConvergenceThreshold (-110.0) 40.0)
  , (("A2C", "lunar-lander"), ConvergenceThreshold 200.0 60.0)
  , (("A2C", "key-door-grid"), ConvergenceThreshold 1.0 0.30)
  , -- TRPO (trust-region, conservative updates → similar variance to PPO).
    (("TRPO", "cartpole"), ConvergenceThreshold 475.0 30.0)
  , (("TRPO", "mountain-car"), ConvergenceThreshold (-110.0) 35.0)
  , (("TRPO", "lunar-lander"), ConvergenceThreshold 200.0 45.0)
  , (("TRPO", "key-door-grid"), ConvergenceThreshold 1.0 0.25)
  , -- MaskablePPO (PPO + action masking; classic control envs don't use
    -- masks but the algorithm degrades gracefully; KeyDoorGrid exercises
    -- the canonical legal-action mask path).
    (("MaskablePPO", "cartpole"), ConvergenceThreshold 475.0 25.0)
  , (("MaskablePPO", "mountain-car"), ConvergenceThreshold (-110.0) 35.0)
  , (("MaskablePPO", "lunar-lander"), ConvergenceThreshold 200.0 40.0)
  , (("MaskablePPO", "key-door-grid"), ConvergenceThreshold 1.0 0.15)
  , -- RecurrentPPO (LSTM policy; needs more env steps; wider slack).
    (("RecurrentPPO", "cartpole"), ConvergenceThreshold 475.0 40.0)
  , (("RecurrentPPO", "mountain-car"), ConvergenceThreshold (-110.0) 50.0)
  , (("RecurrentPPO", "lunar-lander"), ConvergenceThreshold 200.0 60.0)
  , (("RecurrentPPO", "key-door-grid"), ConvergenceThreshold 1.0 0.35)
  , -- DQN (discrete-only; cartpole + mountain-car + KeyDoorGrid).
    (("DQN", "cartpole"), ConvergenceThreshold 475.0 30.0)
  , (("DQN", "mountain-car"), ConvergenceThreshold (-110.0) 40.0)
  , (("DQN", "key-door-grid"), ConvergenceThreshold 1.0 0.30)
  , -- QR-DQN (quantile DQN; similar variance to DQN with marginally
    -- tighter cartpole convergence).
    (("QR-DQN", "cartpole"), ConvergenceThreshold 475.0 25.0)
  , (("QR-DQN", "mountain-car"), ConvergenceThreshold (-110.0) 35.0)
  , (("QR-DQN", "key-door-grid"), ConvergenceThreshold 1.0 0.25)
  , -- DDPG / TD3 / SAC / CrossQ / TQC (continuous-only; lunar-lander).
    (("DDPG", "lunar-lander"), ConvergenceThreshold 200.0 80.0)
  , (("TD3", "lunar-lander"), ConvergenceThreshold 200.0 60.0)
  , (("SAC", "lunar-lander"), ConvergenceThreshold 200.0 40.0)
  , (("CrossQ", "lunar-lander"), ConvergenceThreshold 200.0 40.0)
  , (("TQC", "lunar-lander"), ConvergenceThreshold 200.0 40.0)
  , -- ARS (random search; needs many seeds to stabilize → wide slack).
    (("ARS", "cartpole"), ConvergenceThreshold 475.0 75.0)
  , (("ARS", "mountain-car"), ConvergenceThreshold (-110.0) 80.0)
  , (("ARS", "lunar-lander"), ConvergenceThreshold 200.0 120.0)
  , (("ARS", "key-door-grid"), ConvergenceThreshold 1.0 0.45)
  ]
