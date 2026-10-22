{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 278 unit coverage for the external-bar predicates over real data.
--
-- * The retained CUDA lane journal is the regression net for the observation
--   gate: it is admitted through the production journal reader, and every one
--   of its 55 rows' completed observations must pass the gate against that
--   row's own bar. The gate may therefore only ever get stricter about
--   duplicated or substituted observations, never about a genuine run.
-- * The bar cross-check rebuilds every ProductRow bar from the canonical
--   threshold tables without calling the code that builds it, so an edit to a
--   registry constant that is not an edit to the table it claims to read fails.
module ProductBarProvenance (productBarProvenanceTests) where

import Codec.CBOR.Encoding qualified as CborEncoding
import Codec.CBOR.Write qualified as CborWrite
import Codec.Serialise (encode)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (for_)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
  ( assertBool
  , assertEqual
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.Convergence (ConvergenceBar (..))
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as Product
import JitML.Substrate (Substrate (..))
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Training.Budget (MetricGoal (..))
import JitML.Training.Budget qualified as Budget

import ProductBarLocalControls
  ( assertManifestAccepted
  , assertManifestRejected
  , assertMentions
  , barCrossCheckTests
  , completionGateTests
  , gate
  , genericRlManifest
  , genericRlPlan
  , genericRlPrefixCases
  , genericRlSuffixCases
  , measure
  , observationGateTests
  , rowNamed
  , unboundRlCompletion
  )
import SupervisedCheckpointV2 (expectRight)

productBarProvenanceTests :: TestTree
productBarProvenanceTests =
  testGroup
    "External bar provenance (Phase 278)"
    [ retainedCudaJournalTests
    , observationGateTests
    , completionGateTests
    , genericRlCompletionTests
    , barCrossCheckTests
    ]

-- ---------------------------------------------------------------------------
-- The retained CUDA journal as a regression net

-- | The retained CUDA journal, admitted through the production reader against
-- the current linux-cuda projection. Path and pin come from the aggregation's
-- own registry, so a re-issued journal is followed rather than contradicted.
admittedCudaRows :: IO [Lane.ProductLaneJournalRow]
admittedCudaRows = admittedLaneRows LinuxCUDA

admittedLaneRows :: Substrate -> IO [Lane.ProductLaneJournalRow]
admittedLaneRows substrate = do
  input <-
    maybe
      ( assertFailure ("the aggregation registers no " <> show substrate <> " journal")
          >> fail "unreachable"
      )
      pure
      (find ((== substrate) . Aggregate.productLaneInputSubstrate) Aggregate.productLaneInputs)
  bytes <- ByteString.readFile (Aggregate.productLaneInputPath input)
  batch <-
    case Product.projectProductRows substrate Product.allProductRows of
      Failure errors -> assertFailure (show errors) >> fail "unreachable"
      Success projected -> pure projected
  case Lane.admitProductLaneJournal (Aggregate.productLaneInputSha256 input) batch bytes of
    Left errors -> assertFailure (show errors) >> fail "unreachable"
    Right admitted -> pure (Lane.admittedProductLaneJournalRows admitted)

retainedCudaJournalTests :: TestTree
retainedCudaJournalTests =
  testGroup
    "retained linux-cuda journal (pinned, admitted through the production reader)"
    [ testCase "all 55 rows are admitted in product order" $ do
        rows <- admittedCudaRows
        fmap Lane.productLaneJournalRowRowId rows @?= Product.productRowIds
        length rows @?= 55
    , testCase "every row's completed observations pass the gate against that row's own bar" $ do
        rows <- admittedCudaRows
        for_ rows $ \laneRow -> do
          row <- rowNamed (Lane.productLaneJournalRowRowId laneRow)
          let observations =
                Budget.completedTrainingMetrics (Lane.productLaneJournalRowCompletedTraining laneRow)
          assertEqual
            (Text.unpack (Product.rowId row) <> ": gate failures")
            []
            (ExternalBars.assertConvergenceObservationsAgainstBar (Product.convergenceBar row) observations)
    , testCase "every row carries exactly one observation of its bar's metric, and it passed" $ do
        rows <- admittedCudaRows
        for_ rows $ \laneRow -> do
          row <- rowNamed (Lane.productLaneJournalRowRowId laneRow)
          let metric = convergenceMetricName (Product.convergenceBar row)
              observations =
                Budget.completedTrainingMetrics (Lane.productLaneJournalRowCompletedTraining laneRow)
              barObservations = filter ((== metric) . Budget.coMetricName) observations
          assertEqual
            (Text.unpack (Product.rowId row) <> ": observations of " <> Text.unpack metric)
            1
            (length barObservations)
          assertBool
            (Text.unpack (Product.rowId row) <> ": the bar observation passed")
            (all Budget.convergencePassed barObservations)
    , testCase "duplicating a real row's observation is rejected for every one of the 55 rows" $ do
        rows <- admittedCudaRows
        for_ rows $ \laneRow -> do
          row <- rowNamed (Lane.productLaneJournalRowRowId laneRow)
          let bar = Product.convergenceBar row
              metric = convergenceMetricName bar
              observations =
                Budget.completedTrainingMetrics (Lane.productLaneJournalRowCompletedTraining laneRow)
          assertMentions
            (Text.unpack (Product.rowId row))
            ("exactly one observation of " <> metric <> ", found 2")
            (gate bar (observations <> filter ((== metric) . Budget.coMetricName) observations))
    ]

-- ---------------------------------------------------------------------------
-- The observation gate on constructed observations

-- | A passing observation of the row's own metric, evaluated against its own
-- goal and threshold.
genericRlCompletionTests :: TestTree
genericRlCompletionTests =
  testGroup
    "generic RL checkpoint cohort identity"
    ( genericRlPrefixCases
        <> [ testCase "a forged canonical PPO PlanId with a real device witness cannot enter A2C's namespace" $
               for_ [LinuxCPU, LinuxCUDA] $ \substrate -> do
                 retained <- retainedRlCompletion substrate "PPO/cartpole"
                 assertBool "the retained PPO completion has a device execution witness" $
                   case Budget.completedTrainingDeviceWitness retained of
                     Right (Just _) -> True
                     _ -> False
                 plan <- genericRlPlan "ppo" "cartpole"
                 borrowed <- measure "median_final_reward" MetricMaximise 435 440
                 generic <- unboundRlCompletion plan [borrowed]
                 let forgedRaw =
                       (Budget.completedTrainingToRaw generic)
                         { Budget.rawCompletedTrainingPlanId = planIdText (Budget.completedTrainingPlanId retained)
                         , Budget.rawCompletedTrainingEvidence = Budget.completedTrainingEvidence retained
                         }
                 forged <- expectRight (Budget.refineCompletedTraining forgedRaw)
                 a2c <- rowNamed "A2C/cartpole"
                 gate (Product.convergenceBar a2c) (Budget.completedTrainingMetrics forged) @?= []
                 assertManifestRejected
                   ( (genericRlManifest forged)
                       { Checkpoint.manifestExperiment = Product.productRowExperimentHash a2c
                       }
                   )
           , testCase "canonical CPU and CUDA RL publisher completions admit before an invocation is attached" $
               for_ [LinuxCPU, LinuxCUDA] $ \substrate -> do
                 retained <- retainedRlCompletion substrate "PPO/cartpole"
                 let raw = Budget.completedTrainingToRaw retained
                 Budget.rawCompletedTrainingVersion raw @?= 2
                 completed <-
                   expectRight
                     ( Budget.refineCompletedTraining
                         raw {Budget.rawCompletedTrainingProductScenarioInvocation = Nothing}
                     )
                 Budget.completedTrainingProductScenarioInvocation completed @?= Nothing
                 Budget.completedTrainingRlPlan completed @?= Nothing
                 Budget.completedTrainingDeviceWitness completed @?= Budget.completedTrainingDeviceWitness retained
                 Budget.completedTrainingPlanId completed @?= Budget.completedTrainingPlanId retained
                 ppo <- rowNamed "PPO/cartpole"
                 assertManifestAccepted
                   ( (genericRlManifest completed)
                       { Checkpoint.manifestExperiment = Product.productRowExperimentHash ppo
                       }
                   )
           ]
        <> genericRlSuffixCases
        <> [ testCase "retained CPU and CUDA completions retain their exact V2 tuple encoding" $
               for_ [LinuxCPU, LinuxCUDA] $ \substrate -> do
                 rows <- admittedLaneRows substrate
                 for_ rows $ \row -> do
                   let completed = Lane.productLaneJournalRowCompletedTraining row
                       raw = Budget.completedTrainingToRaw completed
                   Budget.rawCompletedTrainingVersion raw @?= 2
                   Budget.rawCompletedTrainingRlPlan raw @?= Nothing
                   assertEqual
                     (show substrate <> "/" <> Text.unpack (Lane.productLaneJournalRowRowId row))
                     (legacyV2CompletionBytes raw)
                     (Budget.encodeCompletedTraining completed)
           ]
    )

-- No trainer runs in these boundary tests. The real plan compiler supplies an
-- executable schedule; the completion's count, seed, and PlanId all follow it.
retainedRlCompletion :: Substrate -> Text -> IO Budget.CompletedTraining
retainedRlCompletion substrate name = do
  rows <- admittedLaneRows substrate
  maybe
    ( assertFailure ("missing retained " <> show substrate <> "/" <> Text.unpack name)
        >> fail "unreachable"
    )
    (pure . Lane.productLaneJournalRowCompletedTraining)
    (find ((== name) . Lane.productLaneJournalRowRowId) rows)

legacyV2CompletionBytes :: Budget.RawCompletedTraining -> ByteString.ByteString
legacyV2CompletionBytes raw =
  LazyByteString.toStrict
    ( CborWrite.toLazyByteString
        ( CborEncoding.encodeListLen 11
            <> CborEncoding.encodeWord 0
            <> encode (2 :: Word)
            <> encode (Budget.rawCompletedTrainingPlanId raw)
            <> encode (Budget.rawCompletedTrainingBudget raw)
            <> encode (Budget.rawCompletedTrainingObservedKind raw)
            <> encode (Budget.rawCompletedTrainingObservedUnits raw)
            <> encode (Budget.rawCompletedTrainingObservedUnitLabel raw)
            <> encode (Budget.rawCompletedTrainingEvidence raw)
            <> encode (Budget.rawCompletedTrainingMeasurements raw)
            <> encode (Budget.rawCompletedTrainingTensorBoard raw)
            <> encode (Budget.rawCompletedTrainingProductScenarioInvocation raw)
        )
    )

-- ---------------------------------------------------------------------------
-- Bar cross-check

-- | The bar of one ProductRow rebuilt from the canonical threshold tables.
-- 'Product.mkConvergenceBar' and the registry's row builders are deliberately
-- not used, so this is a second derivation rather than a restatement. The
-- regression and tuning rows have no cohort table: their reference constants
-- are stated here, so changing either registry constant requires changing this
-- pin too.
