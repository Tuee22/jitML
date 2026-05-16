{-# LANGUAGE OverloadedStrings #-}

module JitML.Storage.Buckets
  ( bucketNames
  )
where

import Data.Text (Text)

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
