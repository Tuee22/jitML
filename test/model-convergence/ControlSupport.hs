{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wno-x-model-evidence-raw #-}

-- | Shared support for the Phase 285 mutation controls.
--
-- Every control starts from the /real/ rows of the retained @linux-cuda@ lane
-- journal (admitted through the production reader) and minimally corrupts one
-- field at the forgeable raw boundary. This module owns that baseline and the
-- mutation and grading helpers the control modules share, so each control module
-- states only what it corrupts and which typed failure it expects. The control
-- modules are the only ones that may import the raw evidence boundary, and each
-- says so with the @-Wno-x-model-evidence-raw@ option above.
module ControlSupport
  ( Baseline (..)
  , alphaZeroCriterion
  , baselineBatch
  , criterion
  , editedEvidence
  , finalQualityAfter
  , gradedEvidence
  , joinRejections
  , joinedSet
  , learningAfter
  , loadBaseline
  , mutateFinal
  , mutateLearning
  , mutateRow
  , mutateSeeds
  , performanceAfter
  , ppoCartpoleCriterion
  , projectionFor
  , rawRow
  , reanchorTo
  , registryRow
  , rowAssertionsAfter
  , rowRejection
  , setValue
  , someProjectionExperiment
  , someProjectionPlanId
  , someProjectionRowId
  , threeSeedCohort
  , withBaseline
  )
where

import Data.List (find)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty.HUnit (assertFailure)

import JitML.Plan.Plan qualified as Plan
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate (..))
import JitML.Test.ModelEvidence
import JitML.Test.ModelEvidence.Raw
import JitML.Test.Report qualified as Report
import JitML.Test.RowAssertions qualified as RowAssertions
import JitML.Training.Budget qualified as Budget

-- ---------------------------------------------------------------------------
-- Baseline: the retained linux-cuda journal, admitted by the production reader

data Baseline = Baseline
  { baselineLane :: LoadedLane
  -- ^ The validated projection batch and the admitted journal it was read against.
  , baselineRaw :: [RawModelEvidence]
  }

baselineBatch :: Baseline -> ProductMatrix.ProductProjectionBatch
baselineBatch = loadedLaneBatch . baselineLane

loadBaseline :: IO (Either String Baseline)
loadBaseline = do
  loaded <- loadLaneJournal LinuxCUDA
  pure $
    case loaded of
      Left err ->
        Left
          ( "control baseline (the retained linux-cuda journal) is unavailable: "
              <> Text.unpack (renderModelEvidenceLoadError err)
          )
      Right lane ->
        Right
          Baseline
            { baselineLane = lane
            , baselineRaw = rawModelEvidenceFromJournal (loadedLaneJournal lane)
            }

withBaseline :: IO (Either String Baseline) -> (Baseline -> IO ()) -> IO ()
withBaseline loaded body = loaded >>= either assertFailure body

rawRow :: Baseline -> Text -> IO RawModelEvidence
rawRow baseline rowId =
  maybe
    (assertFailure ("baseline has no row " <> Text.unpack rowId))
    pure
    (find ((== rowId) . rmeRowId) (baselineRaw baseline))

projectionFor :: Baseline -> Text -> IO ProductMatrix.SomeProductProjection
projectionFor baseline rowId =
  maybe
    (assertFailure ("baseline has no projection for row " <> Text.unpack rowId))
    pure
    ( find
        ((== rowId) . someProjectionRowId)
        (ProductMatrix.productProjectionBatchProjections (baselineBatch baseline))
    )

someProjectionRowId :: ProductMatrix.SomeProductProjection -> Text
someProjectionRowId (ProductMatrix.SomeProductProjection _ projection) =
  ProductMatrix.productProjectionRowId projection

someProjectionPlanId :: ProductMatrix.SomeProductProjection -> Plan.PlanId
someProjectionPlanId (ProductMatrix.SomeProductProjection _ projection) =
  ProductMatrix.productProjectionPlanId projection

someProjectionExperiment :: ProductMatrix.SomeProductProjection -> Text
someProjectionExperiment (ProductMatrix.SomeProductProjection _ projection) =
  ProductMatrix.productProjectionExperimentHash projection

-- ---------------------------------------------------------------------------
-- Mutation and grading helpers

mutateRow
  :: Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> [RawModelEvidence]
  -> [RawModelEvidence]
mutateRow rowId mutation =
  fmap (\raw -> if rmeRowId raw == rowId then mutation raw else raw)

mutateSeeds :: (RawSeedEvidence -> RawSeedEvidence) -> RawModelEvidence -> RawModelEvidence
mutateSeeds mutation raw = raw {rmeSeeds = fmap mutation (rmeSeeds raw)}

mutateFinal
  :: ([Budget.RawConvergenceObservation] -> [Budget.RawConvergenceObservation])
  -> RawModelEvidence
  -> RawModelEvidence
mutateFinal mutation =
  mutateSeeds $ \seed ->
    seed
      { rseFinalQuality =
          (rseFinalQuality seed)
            { rfqObservations = mutation (rfqObservations (rseFinalQuality seed))
            }
      }

mutateLearning
  :: (RawLearningTelemetry -> RawLearningTelemetry)
  -> RawModelEvidence
  -> RawModelEvidence
mutateLearning mutation =
  mutateSeeds (\seed -> seed {rseLearning = mutation (rseLearning seed)})

setValue :: Double -> Budget.RawConvergenceObservation -> Budget.RawConvergenceObservation
setValue value observation = observation {Budget.rawMeasurementValue = value}

joinRejections :: Baseline -> [RawModelEvidence] -> IO [ModelEvidenceError]
joinRejections baseline raws =
  case joinModelEvidence (baselineBatch baseline) raws of
    Left errors -> pure (NonEmpty.toList errors)
    Right _ -> assertFailure "mutated evidence was admitted by the typed join"

joinedSet :: Baseline -> [RawModelEvidence] -> IO ModelEvidenceSet
joinedSet baseline raws =
  case joinModelEvidence (baselineBatch baseline) raws of
    Left errors ->
      assertFailure
        ( "unexpected join rejection: "
            <> Text.unpack (Text.intercalate "; " (fmap renderModelEvidenceError (NonEmpty.toList errors)))
        )
    Right set -> pure set

-- | The single row-level rejection a mutation of one row must produce.
rowRejection
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO [RowEvidenceError]
rowRejection baseline rowId mutation = do
  failures <- joinRejections baseline (mutateRow rowId mutation (baselineRaw baseline))
  case failures of
    [RowEvidenceRejected observedRow errors]
      | observedRow == rowId -> pure (NonEmpty.toList errors)
    other ->
      assertFailure
        ( "expected exactly one row rejection for "
            <> Text.unpack rowId
            <> ", observed "
            <> show other
        )

gradedEvidence
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO SomeModelRowEvidence
gradedEvidence baseline rowId mutation = do
  set <- joinedSet baseline (mutateRow rowId mutation (baselineRaw baseline))
  maybe
    (assertFailure ("joined evidence has no row " <> Text.unpack rowId))
    pure
    (lookupModelEvidence rowId set)

-- | The raw view re-anchored to a projection that edits its registry row: every
-- identity the mint compares takes the projection's own value (row id, PlanId,
-- experiment hash, contract digest, and the plan, experiment, and invocation
-- identities the completion records). Lane, manifest, digests, and every
-- measurement stay the real row's, so a control built on it differs from the
-- real evidence only where the edit reached.
reanchorTo :: ProductMatrix.ProductProjection kind -> RawModelEvidence -> RawModelEvidence
reanchorTo projection raw =
  raw
    { rmeRowId = rowId
    , rmePlanId = planId
    , rmeExperimentHash = experiment
    , rmeContractDigest = Report.productScenarioProjectionContractDigest projection
    , rmeCompletion =
        (rmeCompletion raw)
          { rciPlanId = planId
          , rciExperimentHash = experiment
          , rciInvocation =
              fmap
                (\invocation -> invocation {riiRowId = rowId, riiPlanId = planId})
                (rciInvocation (rmeCompletion raw))
          }
    }
 where
  rowId = ProductMatrix.productProjectionRowId projection
  planId = ProductMatrix.productProjectionPlanId projection
  experiment = ProductMatrix.productProjectionExperimentHash projection

-- | Evidence minted for an /edited/ registry row: the row is edited, projected
-- for the baseline lane, and the real journal row's raw view is re-anchored to
-- that projection ('reanchorTo') and minted against it. The identity of the edit
-- (a renamed row, another experiment configuration) is the only thing that
-- separates it from the real evidence, so @editedEvidence baseline rowId id@ is
-- the unedited baseline every edited control proves clean first.
editedEvidence
  :: Baseline
  -> Text
  -> (ProductMatrix.ProductRow 'ProductMatrix.Declared -> ProductMatrix.ProductRow 'ProductMatrix.Declared)
  -> IO SomeModelRowEvidence
editedEvidence baseline rowId edit = do
  raw <- rawRow baseline rowId
  row <- registryRow rowId
  case ProductMatrix.projectProductRow LinuxCUDA (edit row) of
    Plan.Failure errors -> assertFailure ("edited row did not project: " <> show errors)
    Plan.Success (ProductMatrix.SomeProductProjection witness projection) ->
      case refineModelRowEvidence projection (reanchorTo projection raw) of
        Left errors -> assertFailure ("edited row's evidence was refused: " <> show errors)
        Right evidence -> pure (SomeModelRowEvidence witness evidence)

finalQualityAfter
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO [FinalQualityFailure]
finalQualityAfter baseline rowId mutation = do
  graded <- gradedEvidence baseline rowId mutation
  case graded of
    SomeModelRowEvidence _ evidence -> pure (assertModelConvergence evidence)

learningAfter
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO [LearningFailure]
learningAfter baseline rowId mutation = do
  graded <- gradedEvidence baseline rowId mutation
  case graded of
    SomeModelRowEvidence _ evidence -> pure (assertModelLearning evidence)

performanceAfter
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO [PerformanceFailure]
performanceAfter baseline rowId mutation = do
  graded <- gradedEvidence baseline rowId mutation
  case graded of
    SomeModelRowEvidence _ evidence -> pure (assertModelPerformance evidence)

rowAssertionsAfter
  :: Baseline
  -> Text
  -> (RawModelEvidence -> RawModelEvidence)
  -> IO [Text]
rowAssertionsAfter baseline rowId mutation = do
  graded <- gradedEvidence baseline rowId mutation
  case graded of
    SomeModelRowEvidence _ evidence -> pure (RowAssertions.assertCompletedRowEvidence evidence)

-- | Expected criteria are written as literals (target minus slack) rather than
-- read from the tables under test.
criterion
  :: Text
  -> Budget.RawCriterionRule
  -> Double
  -> ExternalBars.ExternalCriterion
criterion = ExternalBars.ExternalCriterion

ppoCartpoleCriterion :: ExternalBars.ExternalCriterion
ppoCartpoleCriterion = criterion "median_final_reward" Budget.RawCriterionAtLeast (475.0 - 25.0)

alphaZeroCriterion :: ExternalBars.ExternalCriterion
alphaZeroCriterion =
  criterion "arena_win_rate" (Budget.RawCriterionAtLeastExcluding 0.5 1.0e-12) (0.45 - 0.05)

registryRow :: Text -> IO (ProductMatrix.ProductRow 'ProductMatrix.Declared)
registryRow rowId =
  maybe
    (assertFailure ("registry has no row " <> Text.unpack rowId))
    pure
    (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)

-- | A real multi-seed plan cohort resolved through the plan contract.
threeSeedCohort :: IO Plan.SeedCohort
threeSeedCohort =
  case Plan.resolveRun request of
    Plan.Failure errors -> assertFailure ("three-seed plan did not resolve: " <> show errors)
    Plan.Success plan -> pure (Plan.runPlanSeeds plan)
 where
  request =
    Plan.RawRunRequest
      { Plan.rawRunVersion = 1
      , Plan.rawRunKind = Plan.SupervisedTrainingWitness
      , Plan.rawRunExperimentId = "cohort-fixture"
      , Plan.rawRunSubjectId = "cohort-fixture"
      , Plan.rawRunArtifactId = "cohort-fixture"
      , Plan.rawRunTopicId = "training.command.linux-cpu"
      , Plan.rawRunSubstrate = LinuxCPU
      , Plan.rawRunPlacement = Plan.ClusterRun
      , Plan.rawRunSeeds = [3, 1, 2]
      , Plan.rawRunBudget = Plan.RawSupervisedBudget 2 10 5 5 4
      }
