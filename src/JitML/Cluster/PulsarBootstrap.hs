{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 5.13 — the topic /family/ is no longer a hardcoded list here. The
-- Coordinator owns the topic algebra in 'JitML.Coordinator.Topology'; this module
-- keeps only the typed creation mechanics (@pulsar-admin topics create@ through
-- the toolset pod) and sources its topics from the validated routing graph via
-- 'coordinatorTopics'.
module JitML.Cluster.PulsarBootstrap
  ( Topic (..)
  , pulsarTopics
  , pulsarTopicCreateSubprocess
  , pulsarTopicCreateSubprocesses
  , renderPulsarAdminCommands
  , runPulsarTopicCreatesIO
  )
where

import Control.Concurrent (threadDelay)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Exit (ExitCode (..))

import JitML.Coordinator.Topology (Topic (..), coordinatorTopics)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

-- | The derived topic family the bootstrap rollout creates, sourced from the
-- Coordinator's validated routing graph ('coordinatorTopics').
pulsarTopics :: [Topic]
pulsarTopics = coordinatorTopics

renderPulsarAdminCommands :: [Text]
renderPulsarAdminCommands =
  fmap (\topic -> "pulsar-admin topics create " <> topicName topic) pulsarTopics

-- | Sprint 4.8 — typed single @kubectl exec ... pulsar-admin topics create@.
-- The previous @sh -c@ retry loop with grep-based existence check and
-- "already exists" / @HTTP code: 409@ tolerance now lives in typed Haskell
-- IO ('runPulsarTopicCreatesIO'), which the bootstrap rollout calls after the
-- subprocess phases complete.
pulsarTopicCreateSubprocess :: Topic -> Subprocess
pulsarTopicCreateSubprocess topic =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "exec"
    , "-n"
    , "platform"
    , "pulsar-toolset-0"
    , "--"
    , "/pulsar/bin/pulsar-admin"
    , "topics"
    , "create"
    , topicName topic
    ]

pulsarTopicCreateSubprocesses :: [Subprocess]
pulsarTopicCreateSubprocesses =
  fmap pulsarTopicCreateSubprocess pulsarTopics

-- | Sprint 4.8 — typed Haskell IO retry that creates every Pulsar topic in
-- 'pulsarTopics' through the chart's toolset pod, with bounded retries and
-- "already exists" / HTTP 409 tolerance. Each topic is attempted up to 5 times
-- with 2-second backoff to ride out the broker's first-minute readiness
-- window; the first hard failure stops the IO step and surfaces as 'Left'.
runPulsarTopicCreatesIO :: IO (Either Text ())
runPulsarTopicCreatesIO = goTopics pulsarTopics
 where
  goTopics [] = pure (Right ())
  goTopics (t : rest) = do
    result <- attempt t (5 :: Int)
    case result of
      Left err -> pure (Left err)
      Right () -> goTopics rest
  attempt topic 0 =
    pure (Left ("pulsar topic create " <> topicName topic <> ": exhausted retries"))
  attempt topic n = do
    (code, _stdout, stderr) <-
      runStreaming defaultSubprocessEnv (pulsarTopicCreateSubprocess topic)
    case code of
      ExitSuccess -> pure (Right ())
      ExitFailure _
        | "already exists" `Text.isInfixOf` stderr
            || "HTTP code: 409" `Text.isInfixOf` stderr ->
            pure (Right ())
        | otherwise -> do
            threadDelay 2_000_000
            attempt topic (n - 1)
