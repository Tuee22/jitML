{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.TensorBoard
  ( TensorBoardEvent (..)
  , canonicalProjection
  , checkpointSidecarKey
  , renderTensorBoardDeployment
  , shardKey
  )
where

import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as Text

data TensorBoardEvent = TensorBoardEvent
  { tbTag :: Text
  , tbStep :: Int
  , tbValue :: Double
  }
  deriving stock (Eq, Show)

canonicalProjection :: [TensorBoardEvent] -> [(Text, Int, Double)]
canonicalProjection =
  fmap project . sortOn (\event -> (tbTag event, tbStep event))
 where
  project event = (tbTag event, tbStep event, tbValue event)

shardKey :: Text -> Int -> Text
shardKey experimentHash shardSeq =
  "jitml-tensorboard/" <> experimentHash <> "/events/" <> Text.pack (show shardSeq) <> ".tfevents"

checkpointSidecarKey :: Text -> Int -> Text -> Text
checkpointSidecarKey experimentHash step manifestSha =
  "jitml-tensorboard/"
    <> experimentHash
    <> "/checkpoints/"
    <> Text.pack (show step)
    <> "-"
    <> manifestSha
    <> ".cbor"

renderTensorBoardDeployment :: Text
renderTensorBoardDeployment =
  Text.unlines
    [ "apiVersion: apps/v1"
    , "kind: Deployment"
    , "metadata:"
    , "  name: tensorboard"
    , "  namespace: platform"
    , "spec:"
    , "  replicas: 1"
    , "  selector:"
    , "    matchLabels:"
    , "      app: tensorboard"
    , "  template:"
    , "    metadata:"
    , "      labels:"
    , "        app: tensorboard"
    , "    spec:"
    , "      containers:"
    , "        - name: tensorboard"
    , "          image: tensorboard:local"
    , "          args: [\"--logdir\", \"s3://jitml-tensorboard\"]"
    ]
