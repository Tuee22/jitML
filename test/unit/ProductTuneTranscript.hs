{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module ProductTuneTranscript
  ( productTuneTranscriptTests
  )
where

import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan (RunKind (..), RunKindWitness (..), Validation (..), planIdText)
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher qualified as ProductPublisher
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune

data TuneFixture = TuneFixture
  { fixtureProjection :: !(ProductMatrix.ProductProjection 'HyperparameterTuning)
  , fixtureCompleted :: !TrainingBudget.CompletedTraining
  , fixtureDatasetSha :: !Text
  , fixtureExperiment :: !Tune.TuningExperiment
  , fixtureExecutions :: ![Tune.TrialExecution]
  , fixtureBest :: !Tune.TrialObjectiveResult
  }

productTuneTranscriptTests :: TestTree
productTuneTranscriptTests =
  testGroup
    "Sprint 19.4 tuning v2 transcript admission"
    [ testCase "renders exact projection/completion identity and each rung once" $ do
        fixture <- requireFixture
        payload <- requireRight (renderFixture fixture)
        let projection = fixtureProjection fixture
            executions = fixtureExecutions fixture
            expectedRungs =
              sum
                [ length (Tune.trialResultObservations (Tune.trialExecutionResult execution))
                | execution <- executions
                ]
        assertBool
          "v2 kind header is first"
          ("kind: tune-trials-v2\n" `Text.isPrefixOf` payload)
        assertBool
          "row identity is projection-derived"
          (("row-id: " <> ProductMatrix.productProjectionRowId projection <> "\n") `Text.isInfixOf` payload)
        assertBool
          "PlanId is projection-derived"
          ( ( "plan-id: "
                <> planIdText (ProductMatrix.productProjectionPlanId projection)
                <> "\n"
            )
              `Text.isInfixOf` payload
          )
        assertBool
          "experiment hash is projection-derived"
          ( ( "experiment-hash: "
                <> ProductMatrix.productProjectionExperimentHash projection
                <> "\n"
            )
              `Text.isInfixOf` payload
          )
        assertBool
          "dataset-at-read digest is completion-bound"
          (("dataset-sha-at-read: " <> fixtureDatasetSha fixture <> "\n") `Text.isInfixOf` payload)
        Text.count "trial: " payload @?= length executions
        Text.count "rung: updates=" payload @?= expectedRungs
    , testCase "rejects reordered trial identities" $ do
        fixture <- requireFixture
        assertLeftContaining
          "trial indices are not the exact contiguous range"
          (renderFixture fixture {fixtureExecutions = reverse (fixtureExecutions fixture)})
    , testCase "rejects a best result that was not promoted" $ do
        fixture <- requireFixture
        unpromoted <-
          case [ Tune.trialExecutionResult execution
               | execution <- fixtureExecutions fixture
               , not (Tune.trialExecutionPromoted execution)
               ] of
            result : _ -> pure result
            [] -> assertFailure "fixture has no unpromoted trial"
        assertLeftContaining
          "is not exactly one promoted execution"
          (renderFixture fixture {fixtureBest = unpromoted})
    , testCase "rejects an additional promoted result" $ do
        fixture <- requireFixture
        executions <-
          requireRight
            ( Tune.trialExecutions
                Tune.ASHA
                Tune.NoPruner
                2
                (fmap Tune.trialExecutionResult (fixtureExecutions fixture))
            )
        assertLeftContaining
          "is not exactly one promoted execution"
          (renderFixture fixture {fixtureExecutions = executions})
    , testCase "rejects a dataset digest substituted after completion" $ do
        fixture <- requireFixture
        assertLeftContaining
          "dataset-at-read digest"
          (renderFixture fixture {fixtureDatasetSha = Text.replicate 64 "e"})
    , testCase "rejects a substituted completed final-weight digest" $ do
        fixture <- requireFixture
        completed <-
          requireRight
            ( completionFor
                (fixtureProjection fixture)
                (fixtureDatasetSha fixture)
                (fixtureBest fixture)
                (fromIntegral (length (fixtureExecutions fixture)))
                (positiveUpdates (fixtureBest fixture))
                (Text.replicate 64 "f")
                [("best_objective", Tune.trialResultObjective (fixtureBest fixture))]
            )
        assertLeftContaining
          "best final JMW1 digest"
          (renderFixture fixture {fixtureCompleted = completed})
    , testCase "rejects a substituted completed trial count" $ do
        fixture <- requireFixture
        completed <-
          requireRight
            ( completionFor
                (fixtureProjection fixture)
                (fixtureDatasetSha fixture)
                (fixtureBest fixture)
                3
                (positiveUpdates (fixtureBest fixture))
                (bestFinalSha fixture)
                [("best_objective", Tune.trialResultObjective (fixtureBest fixture))]
            )
        assertLeftContaining
          "completed trial count"
          (renderFixture fixture {fixtureCompleted = completed})
    , testCase "rejects duplicate completed best-objective observations" $ do
        fixture <- requireFixture
        let objective = Tune.trialResultObjective (fixtureBest fixture)
        completed <-
          requireRight
            ( completionFor
                (fixtureProjection fixture)
                (fixtureDatasetSha fixture)
                (fixtureBest fixture)
                (fromIntegral (length (fixtureExecutions fixture)))
                (positiveUpdates (fixtureBest fixture))
                (bestFinalSha fixture)
                [("best_objective", objective), ("best_objective", objective)]
            )
        assertLeftContaining
          "exactly one best_objective observation"
          (renderFixture fixture {fixtureCompleted = completed})
    ]

renderFixture :: TuneFixture -> Either Text Text
renderFixture fixture =
  ProductPublisher.productTuneTrialArtifact
    (fixtureProjection fixture)
    (fixtureCompleted fixture)
    (fixtureDatasetSha fixture)
    (fixtureExperiment fixture)
    Tune.TPE
    (fixtureExecutions fixture)
    (fixtureBest fixture)

requireFixture :: IO TuneFixture
requireFixture = requireRight tuneFixture

tuneFixture :: Either Text TuneFixture
tuneFixture = do
  row <-
    maybe
      (Left "missing canonical hyperparameter-tuning ProductRow")
      Right
      (find ((== "hyperparameter-tuning") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  projection <-
    case ProductMatrix.projectProductRow LinuxCPU row of
      Failure errors -> Left (Text.pack (show errors))
      Success (ProductMatrix.SomeProductProjection HyperparameterTuningWitness value) -> Right value
      Success _ -> Left "hyperparameter-tuning projected with the wrong run-kind witness"
  results <- Tune.trialObjectiveResultsForBudget Tune.TPE 1 6 2
  executions <- Tune.trialExecutions Tune.ASHA Tune.NoPruner 1 results
  best <-
    case [ Tune.trialExecutionResult execution
         | execution <- executions
         , Tune.trialExecutionPromoted execution
         ] of
      [result] -> Right result
      promoted ->
        Left
          ("fixture expected exactly one promoted trial, observed " <> Text.pack (show (length promoted)))
  let datasetSha = Text.replicate 64 "d"
  completed <-
    completionFor
      projection
      datasetSha
      best
      (fromIntegral (length executions))
      (positiveUpdates best)
      (WeightCodec.jmw1ContentSha (WeightCodec.encodeJmw1 (Tune.trialResultWeights best)))
      [("best_objective", Tune.trialResultObjective best)]
  Right
    TuneFixture
      { fixtureProjection = projection
      , fixtureCompleted = completed
      , fixtureDatasetSha = datasetSha
      , fixtureExperiment =
          Tune.TuningExperiment
            { Tune.tuningExperimentName = "mnist-tune"
            , Tune.tuningExperimentDataset = "MNIST"
            , Tune.tuningExperimentModel = "DeepDense"
            , Tune.tuningExperimentSeed = 1729
            , Tune.tuningExperimentConfig = Nothing
            }
      , fixtureExecutions = executions
      , fixtureBest = best
      }

completionFor
  :: ProductMatrix.ProductProjection 'HyperparameterTuning
  -> Text
  -> Tune.TrialObjectiveResult
  -> Word64
  -> Word64
  -> Text
  -> [(Text, Double)]
  -> Either Text TrainingBudget.CompletedTraining
completionFor projection datasetSha best observedTrials updateCount finalSha metricRows = do
  budget <-
    TrainingBudget.mkTrainingBudget TrainingBudget.TuningTrialBudget observedTrials (Just 1729)
  let initialSha =
        WeightCodec.jmw1ContentSha
          (WeightCodec.encodeJmw1 (Tune.trialResultInitialWeights best))
  evidence <- ProductEvidence.mkTrainingEvidence initialSha finalSha updateCount datasetSha
  observations <-
    traverse
      ( \(name, value) ->
          TrainingBudget.measureCriterion
            name
            TrainingBudget.MetricMaximise
            (value - 1.0)
            value
      )
      metricRows
  TrainingBudget.completedTraining
    (ProductMatrix.productProjectionPlanId projection)
    budget
    observedTrials
    evidence
    observations
    TrainingBudget.TensorBoardRunMetadata
      { TrainingBudget.tbrRunId = ProductMatrix.productProjectionExperimentHash projection
      , TrainingBudget.tbrLogPrefix =
          "jitml-tensorboard/" <> ProductMatrix.productProjectionExperimentHash projection
      , TrainingBudget.tbrScalarTags = fmap fst metricRows
      }

bestFinalSha :: TuneFixture -> Text
bestFinalSha fixture =
  WeightCodec.jmw1ContentSha
    (WeightCodec.encodeJmw1 (Tune.trialResultWeights (fixtureBest fixture)))

positiveUpdates :: Tune.TrialObjectiveResult -> Word64
positiveUpdates = fromIntegral . max 1 . Tune.trialResultUpdatesExecuted

assertLeftContaining :: Text -> Either Text value -> Assertion
assertLeftContaining expected result =
  case result of
    Left err ->
      assertBool
        ("expected error containing " <> Text.unpack expected <> ", observed: " <> Text.unpack err)
        (expected `Text.isInfixOf` err)
    Right _ -> assertFailure ("expected failure containing " <> Text.unpack expected)

requireRight :: Either Text value -> IO value
requireRight result =
  case result of
    Left err -> assertFailure (Text.unpack err)
    Right value -> pure value
