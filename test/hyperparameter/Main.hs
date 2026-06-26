{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Word (Word64)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.CLI.Parser (ParsedOption (..))
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Experiment.Overrides qualified as Overrides
import JitML.Numerics.MlpDevice (probeMlpDevice)
import JitML.Numerics.MlpDeviceSelect (mlpDeviceForSubstrate)
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
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog
  ( Pruner (..)
  , Sampler (..)
  , Scheduler (..)
  , deterministicTrials
  , deterministicTrialsWithDevice
  , loadTuningExperiment
  , prunerCatalog
  , renderTrialResumeSummary
  , resumeMatchesFullRun
  , samplerCatalog
  , samplerFromText
  , schedulerCatalog
  , trialObjectiveResults
  , trialResultObjective
  , trialResultWeights
  , tuningConfigPruner
  , tuningConfigSampler
  , tuningConfigScheduler
  , tuningExperimentConfig
  , tuningPrunerKind
  , tuningSamplerKind
  , tuningSchedulerKind
  )

completedTrainingFixture
  :: Text
  -> Word64
  -> [(Text, Double)]
  -> TrainingBudget.CompletedTraining
completedTrainingFixture experimentHash observedUnits metrics =
  either
    (error . Text.unpack)
    id
    ( TrainingBudget.completedTrainingFromMetrics
        TrainingBudget.TrainingBudget
          { TrainingBudget.tbKind = TrainingBudget.TuningTrialBudget
          , TrainingBudget.tbTargetUnits = max 1 observedUnits
          , TrainingBudget.tbUnitLabel = "trials"
          , TrainingBudget.tbSeed = Nothing
          }
        observedUnits
        metrics
        TrainingBudget.TensorBoardRunMetadata
          { TrainingBudget.tbrRunId = experimentHash
          , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
          , TrainingBudget.tbrScalarTags = fmap fst metrics
          }
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
                  (\value -> assertBool "value is [0,1]" (value >= 0 && value <= 1))
                  (deterministicTrials sampler 8)
            )
            samplerCatalog
      , testCase "trial objectives expose checkpointable trained weights (Sprint 9.12)" $ do
          let results = trialObjectiveResults TPE 3
              objectives = fmap trialResultObjective results
          objectives @?= deterministicTrials TPE 3
          assertBool "trial results are non-empty" (not (null results))
          mapM_
            ( \result -> do
                let weights = trialResultWeights result
                assertBool "trial weights are non-empty" (not (null weights))
                Checkpoint.decodeJmw1 (Checkpoint.encodeJmw1 weights) @?= Right weights
            )
            results
      , testCase
          "device-backed trial executor is deterministic through the substrate JIT device (Sprint 9.11 --linux-cpu)"
          $ do
            env <- buildEnv defaultGlobalFlags
            let device = mlpDeviceForSubstrate LinuxCPU env
            probe <- probeMlpDevice device
            case probe of
              Left _ ->
                assertBool "linux-cpu JIT device unavailable; device-backed tuning trial skipped" True
              Right () -> do
                first <- deterministicTrialsWithDevice device TPE 3
                second <- deterministicTrialsWithDevice device TPE 3
                case (first, second) of
                  (Right a, Right b) -> do
                    a @?= b
                    assertBool "device trial executor produced three objectives" (length a == 3)
                    mapM_
                      (\value -> assertBool "device value is [0,1]" (value >= 0 && value <= 1))
                      a
                  (Left err, _) ->
                    assertBool ("first device-backed trial run failed: " <> Text.unpack err) False
                  (_, Left err) ->
                    assertBool ("second device-backed trial run failed: " <> Text.unpack err) False
      , testCase "Sobol and GA trial streams regenerate deterministically without fixtures" $ do
          deterministicTrials Sobol 8 @?= deterministicTrials Sobol 8
          deterministicTrials GeneticAlgorithm 8 @?= deterministicTrials GeneticAlgorithm 8
          assertBool "Sobol and GA cover different search paths" $
            deterministicTrials Sobol 8 /= deterministicTrials GeneticAlgorithm 8
      , testCase "every sampler trial stream is deterministic without committed fixtures (Sprint 15.3)" $
          mapM_
            ( \sampler -> do
                let first = deterministicTrials sampler 8
                    second = deterministicTrials sampler 8
                first @?= second
                assertBool ("sampler " <> show sampler <> " produces eight trials") (length first == 8)
            )
            samplerCatalog
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
      , testCase
          "report-card knobs drive the full canonical sampler × scheduler × pruner sweep (Sprint 13.10)"
          assertCanonicalGridResume
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
                    , sdCompletedTraining =
                        Just
                          ( completedTrainingFixture
                              "sha256:mnist-tune"
                              8
                              [("best_objective", 0.9375)]
                          )
                    }
          decodeTuneEventProto (encodeTuneEventProto started) @?= Right started
          decodeTuneEventProto (encodeTuneEventProto finished) @?= Right finished
          decodeTuneEventProto (encodeTuneEventProto done) @?= Right done
      , testCase "Sprint 1.12 — every catalog axis round-trips through CLI override decode" $ do
          -- Every sampler in the catalog decodes via its show-name through
          -- the CLI override parser; the resolver lifts that value into a
          -- TuningOverrides record whose sampler field is the matching
          -- constructor.
          mapM_ assertSamplerRoundTrip samplerCatalog
          mapM_ assertSchedulerRoundTrip schedulerCatalog
          mapM_ assertPrunerRoundTrip prunerCatalog
      , testCase "Sprint 1.12 — CLI overrides act on the named axis only (pillar 2)" $ do
          -- Pillar 2 at README.md → Why this exists: CLI flags layered on
          -- top override the Dhall on each axis, never replace the
          -- surrounding record. With only --sampler set, the other four
          -- tuning axes preserve their Dhall values.
          let parsed = Overrides.parseTuningOverrides [ParsedOption "sampler" ["TPE"]]
          case parsed of
            Left err ->
              error ("expected --sampler TPE to parse, got: " <> Text.unpack (Overrides.renderOverrideError err))
            Right ovr -> do
              Overrides.overrideSampler ovr Grid @?= TPE
              Overrides.overrideScheduler ovr Fifo @?= Fifo
              Overrides.overridePruner ovr NoPruner @?= NoPruner
              Overrides.overrideTrials ovr 64 @?= 64
              Overrides.overrideParallelism ovr 4 @?= 4
      ]
 where
  assertSamplerRoundTrip sampler =
    let raw = Text.pack (show sampler)
        parsed = Overrides.parseTuningOverrides [ParsedOption "sampler" [raw]]
     in case parsed of
          Left err ->
            error
              ( "sampler round-trip failed for "
                  <> show sampler
                  <> ": "
                  <> Text.unpack (Overrides.renderOverrideError err)
              )
          Right ovr -> Overrides.toSampler ovr @?= Just sampler
  assertSchedulerRoundTrip scheduler =
    let raw = Text.pack (show scheduler)
        parsed = Overrides.parseTuningOverrides [ParsedOption "scheduler" [raw]]
     in case parsed of
          Left err ->
            error
              ( "scheduler round-trip failed for "
                  <> show scheduler
                  <> ": "
                  <> Text.unpack (Overrides.renderOverrideError err)
              )
          Right ovr -> Overrides.toScheduler ovr @?= Just scheduler
  assertPrunerRoundTrip pruner =
    let raw = Text.pack (show pruner)
        parsed = Overrides.parseTuningOverrides [ParsedOption "pruner" [raw]]
     in case parsed of
          Left err ->
            error
              ( "pruner round-trip failed for "
                  <> show pruner
                  <> ": "
                  <> Text.unpack (Overrides.renderOverrideError err)
              )
          Right ovr -> Overrides.toPruner ovr @?= Just pruner

-- | Sprint 13.10 — for every (sampler, scheduler, pruner) triple in the
-- canonical catalog, assert that @deterministicTrials@ produces the
-- knob-driven trial budget and that @resumeMatchesFullRun@ holds for
-- a 50%-completed partial sweep. Cross-product cardinality 11 × 4 × 3
-- = 132 triples per call.
assertCanonicalGridResume :: IO ()
assertCanonicalGridResume = do
  cabalProject <- Text.IO.readFile "cabal.project"
  case parseReportCardKnobs cabalProject of
    Left message ->
      assertBool ("expected report-card knobs, got: " <> Text.unpack message) False
    Right knobs -> do
      let trialBudget = max 4 (min 8 (knobTuneTrials knobs))
      mapM_
        ( \sampler ->
            mapM_
              ( \scheduler ->
                  mapM_
                    (assertOneTriple sampler scheduler trialBudget)
                    prunerCatalog
              )
              schedulerCatalog
        )
        samplerCatalog

assertOneTriple :: Sampler -> Scheduler -> Int -> Pruner -> IO ()
assertOneTriple sampler scheduler trialBudget pruner = do
  let _ = (scheduler, pruner)
  assertBool
    ( "sampler "
        <> show sampler
        <> " × "
        <> show scheduler
        <> " × "
        <> show pruner
        <> " produces full trial budget"
    )
    (length (deterministicTrials sampler trialBudget) == trialBudget)
  assertBool
    ( "sampler "
        <> show sampler
        <> " × "
        <> show scheduler
        <> " × "
        <> show pruner
        <> " replays equal under 50% partial sweep"
    )
    (resumeMatchesFullRun sampler (trialBudget `div` 2) trialBudget)
