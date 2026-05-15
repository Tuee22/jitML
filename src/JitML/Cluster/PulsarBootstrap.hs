{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.PulsarBootstrap
    ( Topic (..)
    , pulsarTopics
    , renderPulsarAdminCommands
    )
where

import Data.Text (Text)

import JitML.Substrate (Substrate, allSubstrates, renderSubstrate)

newtype Topic = Topic
    { topicName :: Text
    }
    deriving stock (Eq, Show)

pulsarTopics :: [Topic]
pulsarTopics =
    concatMap substrateTopics allSubstrates
        <> fmap Topic
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

substrateTopics :: Substrate -> [Topic]
substrateTopics substrate =
    fmap
        (Topic . (<> "." <> renderSubstrate substrate))
        [ "persistent://public/default/inference.command"
        , "persistent://public/default/inference.event"
        ]
