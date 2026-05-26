{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.PulsarBootstrap
  ( Topic (..)
  , pulsarTopics
  , pulsarTopicCreateSubprocess
  , pulsarTopicCreateSubprocesses
  , renderPulsarAdminCommands
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

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

-- | Subprocess that creates a single Pulsar topic through the chart's toolset pod.
-- Retries a transient `pulsar-admin topics create` failure up to 5 times with
-- 2-second backoff to ride out the broker's first-minute readiness window,
-- and treats a non-zero create that names an already-existing topic as success
-- (`HTTP code: 409`) so the script is idempotent regardless of who created the
-- topic first (auto-create on subscribe vs explicit admin call).
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
    , "sh"
    , "-c"
    , Text.unwords
        [ "topic=\"$1\";"
        , "namespace=\"${topic#persistent://}\";"
        , "namespace=\"${namespace%/*}\";"
        , "for attempt in 1 2 3 4 5; do"
        , "if /pulsar/bin/pulsar-admin topics list \"$namespace\" 2>/dev/null | grep -Fx \"$topic\" >/dev/null;"
        , "then exit 0;"
        , "fi;"
        , "out=$(/pulsar/bin/pulsar-admin topics create \"$topic\" 2>&1);"
        , "rc=$?;"
        , "if [ $rc -eq 0 ]; then exit 0; fi;"
        , "case \"$out\" in *\"already exists\"*|*\"HTTP code: 409\"*) exit 0;; esac;"
        , "sleep 2;"
        , "done;"
        , "echo \"$out\" 1>&2;"
        , "exit 1"
        ]
    , "jitml-topic-create"
    , topicName topic
    ]

pulsarTopicCreateSubprocesses :: [Subprocess]
pulsarTopicCreateSubprocesses =
  fmap pulsarTopicCreateSubprocess pulsarTopics

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
    ]
