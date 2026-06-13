{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

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

import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate, allSubstrates, renderSubstrate)

newtype Topic = Topic
  { topicName :: Text
  }
  deriving stock (Eq, Show)

pulsarTopics :: [Topic]
pulsarTopics =
  concatMap substrateTopics allSubstrates
    <> appleSiliconInternalTopics

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

substrateTopics :: Substrate -> [Topic]
substrateTopics substrate =
  fmap
    (Topic . (<> "." <> renderSubstrate substrate))
    [ "persistent://public/default/training.command"
    , "persistent://public/default/training.event"
    , "persistent://public/default/tune.command"
    , "persistent://public/default/tune.event"
    , "persistent://public/default/rl.command"
    , "persistent://public/default/rl.event"
    , "persistent://public/default/inference.request"
    , "persistent://public/default/inference.result"
    , -- Sprint 13.7: gc_reaped events emitted by `jitml internal gc` after
      -- each MinIO `deleteObject` succeeds. One topic per substrate so
      -- consumers can scope auditing to a specific cohort's reconciler.
      "persistent://public/default/gc.event"
    ]

appleSiliconInternalTopics :: [Topic]
appleSiliconInternalTopics =
  fmap
    Topic
    [ "persistent://public/default/inference.command.apple-silicon"
    , "persistent://public/default/inference.event.apple-silicon"
    , "persistent://public/default/training.host-command.apple-silicon"
    , "persistent://public/default/tune.host-command.apple-silicon"
    , "persistent://public/default/rl.host-command.apple-silicon"
    ]
