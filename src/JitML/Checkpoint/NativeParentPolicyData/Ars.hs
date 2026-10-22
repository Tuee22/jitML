{-# LANGUAGE OverloadedStrings #-}

-- | Reconstruct public recorded ARS numerical DATA and audit its applied chain.
-- This cannot restore an actual origin or the old authenticated execution path.
module JitML.Checkpoint.NativeParentPolicyData.Ars (arsReturned) where

import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU

import JitML.Checkpoint.NativeParentPolicyData.Node
import JitML.Checkpoint.NativePhase.Types
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common

arsReturned
  :: Text
  -> Ars.ArsTrainConfig
  -> Digest
  -> Ars.ArsNumericalRuntime
  -> Digest
  -> Decode Ars.ArsTrainObservation
arsReturned transport config configRoot expectedRuntime root = do
  actual <- fields NRawArs root
  case actual of
    [ VText compiled
      , VRef c
      , VRef initial
      , VRef final
      , VRef statistics
      , VWord transitions
      , VWord updates
      ] -> do
        require
          (compiled == transport && c == configRoot)
          "parent ARS actual compiled transport/full config differs"
        first <- vector initial
        last_ <- vector final
        roots <-
          referenceData
            (RefElement NArsIterationObservation)
            (toInteger (Ars.arsIterations config))
            statistics
        require (length roots == Ars.arsIterations config) "parent ARS applied iteration count differs"
        iterations <- traverse iteration roots
        counters <-
          either reject pure (Common.mkObservedTrainerCounters (toInteger transitions) (toInteger updates))
        let result = Common.RawTrainerResult first last_ iterations counters config
        either reject pure (Ars.validateArsTrainObservation result)
        pure result
    _ -> reject "parent ARS raw return fields differ"
 where
  dimensions = toInteger (Ars.arsActionCount config) * toInteger (Ars.arsObsSize config)
  vector digest = do
    values <- tensor dimensions digest
    require
      (toInteger (VU.length values) == dimensions)
      "parent ARS applied vector has wrong exact width"
    pure values
  iteration digest = do
    actual <- fields NArsIterationObservation digest
    case actual of
      [VRef statistic, VRef step] -> do
        values <- fields NArsStat statistic
        stat <- case values of
          [index, mean, best] -> Ars.ArsIterationStat <$> int index <*> bits mean <*> bits best
          _ -> reject "parent ARS statistic fields differ"
        Ars.ArsIterationObservation stat <$> applied step
      _ -> reject "parent ARS iteration wrapper differs"
  applied digest = do
    actual <- fields NArsAppliedStep digest
    case actual of
      [ VRef c
        , VRef runtime
        , index
        , VRef before
        , VRef after
        , VRef sampled
        , VRef evaluated
        , VRef kept
        , noise
        , std
        , VRef direction
        , scale
        , transitions
        ] -> do
          require (c == configRoot) "parent ARS applied-step full config differs"
          runtimeFields <- fields NArsRuntime runtime
          numerical <- case runtimeFields of
            [os, arch, compiler, version, recipe] ->
              Ars.ArsNumericalRuntime <$> text os <*> text arch <*> text compiler <*> text version <*> text recipe
            _ -> reject "parent ARS numerical runtime fields differ"
          require
            (numerical == expectedRuntime)
            "parent ARS applied runtime differs from the same recorded lineage"
          directions <-
            referenceData (AliasElement TensorAlias) (toInteger (Ars.arsNumDirections config)) sampled
              >>= traverse vector
          perturbations <-
            referenceData (RefElement NArsPerturbation) (toInteger (Ars.arsNumDirections config)) evaluated
              >>= traverse perturbation
          selected <-
            referenceData (RefElement NArsKeptDirection) (toInteger (Ars.arsTopB config)) kept
              >>= traverse keptDirection
          require
            ( length directions == Ars.arsNumDirections config
                && length perturbations == Ars.arsNumDirections config
                && length selected == min (Ars.arsTopB config) (Ars.arsNumDirections config)
            )
            "parent ARS complete perturbation inventory differs"
          update <- VU.toList <$> vector direction
          Ars.ArsAppliedStep config numerical
            <$> int index
            <*> vector before
            <*> vector after
            <*> pure directions
            <*> pure perturbations
            <*> pure selected
            <*> bits noise
            <*> bits std
            <*> pure update
            <*> bits scale
            <*> magnitude transitions
      _ -> reject "parent ARS applied-step fields differ"
  perturbation digest = do
    actual <- fields NArsPerturbation digest
    case actual of
      [plus, pSteps, minus, mSteps, VRef delta] -> do
        p <- bits plus
        ps <- int pSteps
        m <- bits minus
        ms <- int mSteps
        d <- VU.toList <$> vector delta
        pure ((p, ps), (m, ms), d)
      _ -> reject "parent ARS perturbation fields differ"
  keptDirection digest = do
    actual <- fields NArsKeptDirection digest
    case actual of
      [plus, minus, VRef delta] -> (,,) <$> bits plus <*> bits minus <*> (VU.toList <$> vector delta)
      _ -> reject "parent ARS kept-direction fields differ"
