{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , TuneCommand (..)
  , parseTuneCommand
  , renderTuneCommand
  )
import JitML.Substrate (Substrate (..))
import JitML.Test.Report
  ( ReportCardKnobs (..)
  , parseReportCardKnobs
  )
import JitML.Tune.Catalog
  ( Pruner (..)
  , Sampler (..)
  , Scheduler (..)
  , deterministicTrials
  , loadTuningExperiment
  , prunerCatalog
  , samplerCatalog
  , samplerFromText
  , schedulerCatalog
  , tuningConfigPruner
  , tuningConfigSampler
  , tuningConfigScheduler
  , tuningExperimentConfig
  , tuningPrunerKind
  , tuningSamplerKind
  , tuningSchedulerKind
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-hyperparameter"
      [ testCase "sampler scheduler pruner axes are populated" $ do
          length samplerCatalog @?= 11
          assertBool "Grid sampler is available" (Grid `elem` samplerCatalog)
          assertBool "TPE sampler is available" (TPE `elem` samplerCatalog)
          assertBool "PBT sampler is available" (PBT `elem` samplerCatalog)
          length schedulerCatalog @?= 4
          length prunerCatalog @?= 3
      , testCase "target sampler labels decode into local constructors" $
          mapM_
            ( \(label, sampler) ->
                samplerFromText label @?= Just sampler
            )
            [ ("Grid", Grid)
            , ("Sobol", Sobol)
            , ("Random", Random)
            , ("TPE", TPE)
            , ("GPBO", GPBO)
            , ("GP-BO", GPBO)
            , ("GA", GeneticAlgorithm)
            , ("GeneticAlgorithm", GeneticAlgorithm)
            , ("NSGA2", NSGA2)
            , ("NSGA-II", NSGA2)
            , ("MuLambdaES", MuLambdaES)
            , ("CMAES", CMAES)
            , ("CMA-ES", CMAES)
            , ("EvolutionStrategies", EvolutionStrategies)
            , ("PBT", PBT)
            ]
      , testCase "trial generation is deterministic per sampler" $
          mapM_
            ( \sampler ->
                deterministicTrials sampler 8 @?= deterministicTrials sampler 8
            )
            samplerCatalog
      , testCase "trial values are normalized" $
          mapM_
            ( \sampler ->
                mapM_
                  (\value -> assertBool "value is [0,1)" (value >= 0 && value < 1))
                  (deterministicTrials sampler 8)
            )
            samplerCatalog
      , testCase "Sobol and GA trial streams match golden fixtures" $ do
          sobol <- Text.IO.readFile "test/golden/tune/sobol-trials.txt"
          ga <- Text.IO.readFile "test/golden/tune/genetic-algorithm-trials.txt"
          Text.lines sobol @?= fmap (Text.pack . show) (deterministicTrials Sobol 8)
          Text.lines ga @?= fmap (Text.pack . show) (deterministicTrials GeneticAlgorithm 8)
      , testCase "mnist TPE tuning Dhall decodes into the Haskell tuning ADT" $ do
          loaded <- loadTuningExperiment "experiments/mnist-tune.dhall"
          case loaded >>= maybe (Left "missing tuning block") Right . tuningExperimentConfig of
            Left message ->
              assertBool ("expected tuning decode, got: " <> Text.unpack message) False
            Right config -> do
              tuningSamplerKind (tuningConfigSampler config) @?= TPE
              tuningSchedulerKind (tuningConfigScheduler config) @?= ASHA
              tuningPrunerKind (tuningConfigPruner config) @?= MedianPruner
      , testCase "report-card tuning knobs drive the local trial budget" $ do
          cabalProject <- Text.IO.readFile "cabal.project"
          case parseReportCardKnobs cabalProject of
            Left message ->
              assertBool ("expected report-card knobs, got: " <> Text.unpack message) False
            Right knobs -> do
              length (deterministicTrials TPE (knobTuneTrials knobs)) @?= knobTuneTrials knobs
              assertBool "budget per trial is positive" (knobTuneBudgetPerTrial knobs > 0)
      , testCase "tune command envelopes parse after render" $ do
          let start =
                TuneStart
                  StartSweep
                    { ssExperimentHash = "sha256:mnist-tune"
                    , ssDhallObjectKey = "experiments/mnist-tune.dhall"
                    , ssSubstrate = LinuxCUDA
                    , ssSweepSeed = 42
                    , ssTrialBudget = 64
                    , ssBudgetPerTrial = 1000
                    , ssSampler = "TPE"
                    , ssScheduler = "ASHA"
                    , ssPruner = "MedianPruner"
                    }
              stop =
                TuneStop
                  StopSweep
                    { ssStopExperimentHash = "sha256:mnist-tune"
                    }
          parseTuneCommand (renderTuneCommand start) @?= Just start
          parseTuneCommand (renderTuneCommand stop) @?= Just stop
          parseTuneCommand "kind: UnknownTuneCommand\n" @?= Nothing
      ]
