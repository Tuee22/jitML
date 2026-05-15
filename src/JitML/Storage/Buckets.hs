{-# LANGUAGE OverloadedStrings #-}

module JitML.Storage.Buckets
    ( bucketNames
    , renderMinioValues
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

bucketNames :: [Text]
bucketNames =
    [ "harbor-registry"
    , "jitml-checkpoints"
    , "jitml-datasets"
    , "jitml-transcripts"
    , "jitml-trials"
    , "jitml-tensorboard"
    , "jitml-artifacts"
    ]

renderMinioValues :: Text
renderMinioValues =
    Text.unlines $
        [ "mode: distributed"
        , "replicas: 4"
        , "image:"
        , "  tag: RELEASE.2024-08-26T15-33-07Z"
        , "persistence:"
        , "  storageClass: jitml-manual"
        , "provisioning:"
        , "  enabled: true"
        , "  buckets:"
        ]
            <> fmap renderBucket bucketNames
  where
    renderBucket bucket =
        "    - name: " <> bucket
