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
    <> fmap
      Topic
      [ "persistent://public/default/training.command.cluster"
      , "persistent://public/default/training.event.cluster"
      , "persistent://public/default/tune.command.cluster"
      , "persistent://public/default/tune.event.cluster"
      , "persistent://public/default/rl.command.cluster"
      , "persistent://public/default/rl.event.cluster"
      , "persistent://public/default/inference.request.cluster"
      , "persistent://public/default/inference.result.cluster"
      , "persistent://public/default/inference.request.host"
      , "persistent://public/default/inference.result.host"
      ]

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
    [ "persistent://public/default/inference.command"
    , "persistent://public/default/inference.event"
    ]
