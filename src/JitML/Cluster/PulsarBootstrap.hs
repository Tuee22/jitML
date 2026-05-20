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
        , "if /pulsar/bin/pulsar-admin topics list \"$namespace\" | grep -Fx \"$topic\" >/dev/null;"
        , "then exit 0;"
        , "fi;"
        , "/pulsar/bin/pulsar-admin topics create \"$topic\""
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
    ]

appleSiliconInternalTopics :: [Topic]
appleSiliconInternalTopics =
  fmap
    Topic
    [ "persistent://public/default/inference.command.apple-silicon"
    , "persistent://public/default/inference.event.apple-silicon"
    ]
