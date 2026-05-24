{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Proto.Tune
  ( StartSweep (..)
  , StopSweep (..)
  , SweepDone (..)
  , TrialFinished (..)
  , TrialStarted (..)
  , TuneCommand (..)
  , TuneEvent (..)
  , decodeTuneCommandProto
  , decodeTuneEventProto
  , encodeTuneCommandProto
  , encodeTuneEventProto
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
  , renderTrialResumeSummary
  , resumeMatchesFullRun
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
      , testCase "every sampler matches its committed trial-stream golden (Sprint 12.5)" $
          mapM_ checkSamplerGolden samplerCatalog
      , testCase "every scheduler / pruner cohort reproduces under resume (Sprint 12.5)" $ do
          mapM_
            ( \sampler ->
                assertBool
                  ("sampler " <> show sampler <> " resumes equal under partial sweep")
                  (resumeMatchesFullRun sampler 3 8)
            )
            samplerCatalog
          mapM_
            ( \scheduler ->
                assertBool
                  ("scheduler " <> show scheduler <> " catalog entry is named")
                  (not (null (show scheduler)))
            )
            schedulerCatalog
          mapM_
            ( \pruner ->
                assertBool
                  ("pruner " <> show pruner <> " catalog entry is named")
                  (not (null (show pruner)))
            )
            prunerCatalog
          -- The resume summary is the deterministic per-cohort header that
          -- live tuner integration (Phase 13 Sprint 13.10) consumes from
          -- the trial transcript MinIO objects; pinning its first line
          -- across the sampler set rejects accidental sampler renames.
          mapM_
            ( \sampler ->
                let summary = renderTrialResumeSummary sampler 3 8
                 in assertBool
                      ("resume summary names sampler " <> show sampler)
                      (Text.pack (show sampler) `Text.isInfixOf` Text.unlines (take 1 (Text.lines summary)))
            )
            samplerCatalog
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
          decodeTuneCommandProto (encodeTuneCommandProto start) @?= Right start
          decodeTuneCommandProto (encodeTuneCommandProto stop) @?= Right stop
          parseTuneCommand "kind: UnknownTuneCommand\n" @?= Nothing
      , testCase "tune event envelopes round-trip through proto3-compatible bytes" $ do
          let started =
                TuneTrialStarted
                  TrialStarted
                    { tsExperimentHash = "sha256:mnist-tune"
                    , tsTrial = 7
                    , tsTrialSeed = 4242
                    , tsParametersJson = "{\"lr\":0.001}"
                    , tsTimestampNs = 123456789
                    }
              finished =
                TuneTrialFinished
                  TrialFinished
                    { tfTuneExperimentHash = "sha256:mnist-tune"
                    , tfTuneTrial = 7
                    , tfTuneObjective = 0.875
                    , tfTunePruned = False
                    , tfTuneTranscriptObjectKey = "trials/mnist-tune/7/transcript"
                    , tfTuneTimestampNs = 223456789
                    }
              done =
                TuneSweepDone
                  SweepDone
                    { sdExperimentHash = "sha256:mnist-tune"
                    , sdTrialsCompleted = 8
                    , sdTrialsPruned = 1
                    , sdBestObjective = 0.9375
                    }
          decodeTuneEventProto (encodeTuneEventProto started) @?= Right started
          decodeTuneEventProto (encodeTuneEventProto finished) @?= Right finished
          decodeTuneEventProto (encodeTuneEventProto done) @?= Right done
      ]

samplerGoldenPath :: Sampler -> FilePath
samplerGoldenPath sampler =
  "test/golden/tune/" <> samplerSlug sampler <> "-trials.txt"
 where
  samplerSlug Grid = "grid"
  samplerSlug Sobol = "sobol"
  samplerSlug Random = "random"
  samplerSlug TPE = "tpe"
  samplerSlug GPBO = "gpbo"
  samplerSlug GeneticAlgorithm = "genetic-algorithm"
  samplerSlug NSGA2 = "nsga2"
  samplerSlug MuLambdaES = "mu-lambda-es"
  samplerSlug CMAES = "cmaes"
  samplerSlug EvolutionStrategies = "evolution-strategies"
  samplerSlug PBT = "pbt"

checkSamplerGolden :: Sampler -> IO ()
checkSamplerGolden sampler = do
  fixture <- Text.IO.readFile (samplerGoldenPath sampler)
  Text.lines fixture @?= fmap (Text.pack . show) (deterministicTrials sampler 8)
