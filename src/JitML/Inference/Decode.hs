{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 11.10 / 10.7 (Pulsar ML-Workflow convergence) — __pure output
-- decoding__ for inference. The contract makes the __Engine__ the only role that
-- computes, and the checkpoint format already models per-family output decoding
-- ('JitML.Checkpoint.Format.OutputDecoder' / 'OutputDecoderKind'). This module
-- lifts a raw kernel output vector into a __typed, decoded result__
-- ('DecodedInference') via a single pure function — so the Engine decodes once,
-- the decoded value travels the @Work*@ result wire, the
-- purescript-bridge-compatible renderer reflects the same type into PureScript,
-- and the browser panels render it with __zero compute__ (neither the webapp nor
-- PureScript re-derives argmax/softmax). One pure type, one pure decode, one pure
-- render.
module JitML.Inference.Decode
  ( DecodedInference (..)
  , decodeInference
  , decodeManifestOutput
  , firstOutputDecoder
  , renderDecodedInference
  , softmax
  , argmax
  )
where

import Data.List (maximumBy)
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , OutputDecoder (..)
  , OutputDecoderKind (..)
  )

-- | A decoded inference result, one variant per 'OutputDecoderKind'. This is the
-- single typed value the Engine emits and the browser renders — the panels carry
-- no decoding logic.
data DecodedInference
  = -- | argmax class, its probability, the full softmax distribution, labels
    DecodedClassification Int Double [Double] [Text]
  | -- | regression values + optional units
    DecodedRegression [Double] (Maybe Text)
  | -- | policy distribution (softmax) + action labels
    DecodedPolicy [Double] [Text]
  | -- | scalar value estimate
    DecodedValue Double
  | -- | normalized MCTS visit distribution
    DecodedMctsVisits [Double]
  | -- | replay artifact payload (passed through)
    DecodedReplay [Double]
  | -- | generic raw output (passed through)
    DecodedGeneric [Double]
  deriving stock (Eq, Show)

-- | Decode a raw kernel output vector against the checkpoint's output decoder.
-- Pure: this is the one place argmax/softmax/normalization happen, and it runs in
-- the Engine.
decodeInference :: OutputDecoder -> [Double] -> DecodedInference
decodeInference decoder output =
  case outputDecoderKind decoder of
    ClassificationOutput ->
      let probabilities = softmax output
          top = argmax probabilities
       in DecodedClassification top (valueAt top probabilities) probabilities (outputDecoderLabels decoder)
    RegressionOutput -> DecodedRegression output (outputDecoderUnits decoder)
    PolicyDistributionOutput -> DecodedPolicy (softmax output) (outputDecoderLabels decoder)
    ValueEstimateOutput ->
      DecodedValue (case output of v : _ -> v; [] -> 0)
    MctsVisitDistributionOutput -> DecodedMctsVisits (normalizeSum output)
    ReplayArtifactOutput -> DecodedReplay output
    GenericOutput -> DecodedGeneric output

-- | The output decoder the Engine applies to a manifest's inference output —
-- the first declared decoder, or a 'GenericOutput' pass-through when none is
-- declared.
firstOutputDecoder :: CheckpointManifest -> OutputDecoder
firstOutputDecoder manifest =
  case manifestOutputDecoders manifest of
    decoder : _ -> decoder
    [] -> OutputDecoder "generic" GenericOutput [] Nothing Nothing

-- | Decode a raw output against a manifest's output decoder (the Engine's
-- one-call output-decoding step).
decodeManifestOutput :: CheckpointManifest -> [Double] -> DecodedInference
decodeManifestOutput manifest = decodeInference (firstOutputDecoder manifest)

-- | Render a 'DecodedInference' as @decoded-*@ wire lines, appended to the
-- inference @WorkResult@ so the browser panels render the decoded value without
-- computing. The base @kind/call-id/experiment-hash/output@ lines are untouched,
-- so existing (raw-output) consumers like @jitml inference run@ are unaffected.
renderDecodedInference :: DecodedInference -> [Text]
renderDecodedInference decoded =
  case decoded of
    DecodedClassification top confidence probabilities labels ->
      [ "decoded-kind: classification"
      , "decoded-top-class: " <> showInt top
      , "decoded-confidence: " <> showDouble confidence
      , "decoded-probabilities: " <> renderDoubles probabilities
      , "decoded-labels: " <> Text.intercalate "," labels
      ]
    DecodedRegression values units ->
      [ "decoded-kind: regression"
      , "decoded-values: " <> renderDoubles values
      , "decoded-units: " <> fromMaybe "" units
      ]
    DecodedPolicy probabilities labels ->
      [ "decoded-kind: policy"
      , "decoded-probabilities: " <> renderDoubles probabilities
      , "decoded-labels: " <> Text.intercalate "," labels
      ]
    DecodedValue value ->
      ["decoded-kind: value", "decoded-value: " <> showDouble value]
    DecodedMctsVisits visits ->
      ["decoded-kind: mcts", "decoded-visits: " <> renderDoubles visits]
    DecodedReplay output ->
      ["decoded-kind: replay", "decoded-output: " <> renderDoubles output]
    DecodedGeneric output ->
      ["decoded-kind: generic", "decoded-output: " <> renderDoubles output]
 where
  showInt = Text.pack . show
  showDouble = Text.pack . show
  renderDoubles = Text.intercalate "," . fmap (Text.pack . show)

-- | Numerically-stable softmax (matches the prior webapp @probabilityVector@).
softmax :: [Double] -> [Double]
softmax [] = []
softmax values =
  let shifted = fmap (\value -> exp (value - maximum values)) values
      total = sum shifted
   in if total <= 0 then replicate (length values) 0 else fmap (/ total) shifted

-- | Index of the maximum element (matches the prior webapp @topIndex@).
argmax :: [Double] -> Int
argmax [] = 0
argmax values = fst (maximumBy (comparing snd) (zip [0 ..] values))

valueAt :: Int -> [Double] -> Double
valueAt index values =
  case drop index values of
    v : _ -> v
    [] -> 0

normalizeSum :: [Double] -> [Double]
normalizeSum [] = []
normalizeSum values =
  let total = sum values
   in if total <= 0 then values else fmap (/ total) values
