{-# LANGUAGE OverloadedStrings #-}

-- Ordinary scalar comparison controls only. These records neither decode nor
-- fabricate a CompletedTraining, admitted checkpoint, parent or trained model.
module NativeParentCompletionData (nativeParentCompletionDataTests) where

import Control.Exception (evaluate)
import Data.Text (Text)
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Product.NativeParentCompletionData
import JitML.Training.Budget qualified as Training

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore nativeParentCompletionDataTests "Use drop1" -}
nativeParentCompletionDataTests :: TestTree
nativeParentCompletionDataTests =
  testGroup
    "native parent completion DATA"
    [ testCase "identical ordinary scalar records compare without minting a capability" $
        compareNativeCompletionScalarData fixture fixture @?= Right ()
    , testCase "whole PlanId substitution is rejected" $
        refused fixture {completionDataPlan = "different-whole-plan"}
    , testCase "budget kind substitution is rejected" $
        refused
          fixture
            { completionDataBudget = budget {Training.rawTrainingBudgetKind = Training.AlphaZeroSelfPlayBudget}
            }
    , testCase "budget target substitution is rejected" $
        refused fixture {completionDataBudget = budget {Training.rawTrainingBudgetTargetUnits = 65}}
    , testCase "seedless budget is distinct from actual seed42" $
        refused fixture {completionDataBudget = budget {Training.rawTrainingBudgetSeed = Nothing}}
    , testCase "another prescribed child seed cannot replace serving seed42" $
        refused fixture {completionDataBudget = budget {Training.rawTrainingBudgetSeed = Just 43}}
    , testCase "observed transition or generation count substitution is rejected" $
        refused fixture {completionDataObservedUnits = 63}
    , testCase "manifest step substitution is rejected" $
        refused fixture {completionDataManifestStep = 63}
    , testCase "initial JMW1 identity substitution is rejected" $
        refused fixture {completionDataInitialWeightHash = "another-initial"}
    , testCase "final JMW1 identity substitution is rejected" $
        refused fixture {completionDataFinalWeightHash = "another-final"}
    , testCase "actual optimizer application substitution is rejected" $
        refused fixture {completionDataUpdateCount = 6}
    , testCase "training input evidence digest substitution is rejected" $
        refused fixture {completionDataDatasetHash = "another-input"}
    , testCase "complete criterion name order is retained" $ do
        refused fixture {completionDataCriteria = reverse criteria}
        refused
          fixture
            { completionDataCriteria = firstCriterion {Training.rawCriterionName = "another"} : restCriteria
            }
    , testCase "at-least and at-most criterion directions stay distinct" $
        refused
          fixture
            { completionDataCriteria =
                firstCriterion {Training.rawCriterionRule = Training.RawCriterionAtMost} : restCriteria
            }
    , testCase "exclusion predicate cannot be removed" $
        refused
          fixture
            { completionDataCriteria =
                [ firstCriterion
                , secondCriterion
                , excludedCriterion {Training.rawCriterionRule = Training.RawCriterionAtLeast}
                ]
            }
    , testCase "criterion threshold signed zero bits are exact" $ do
        let expected =
              fixture {completionDataCriteria = [firstCriterion {Training.rawCriterionThreshold = rawDouble 0}]}
            actual =
              expected
                { completionDataCriteria = [firstCriterion {Training.rawCriterionThreshold = rawDouble signBit}]
                }
        assertSignedZero
          (Training.rawCriterionThreshold <$> completionDataCriteria expected)
          (Training.rawCriterionThreshold <$> completionDataCriteria actual)
        assertLeft (compareNativeCompletionScalarData expected actual)
    , testCase "criterion measurement signed zero bits are exact" $ do
        let expected = fixture {completionDataCriteria = [firstCriterion {Training.rawMeasurementValue = rawDouble 0}]}
            actual =
              expected
                { completionDataCriteria = [firstCriterion {Training.rawMeasurementValue = rawDouble signBit}]
                }
        assertSignedZero
          (Training.rawMeasurementValue <$> completionDataCriteria expected)
          (Training.rawMeasurementValue <$> completionDataCriteria actual)
        assertLeft (compareNativeCompletionScalarData expected actual)
    , testCase "exclusion centre and distance bits are exact" $ do
        refused
          fixture
            { completionDataCriteria =
                [ firstCriterion
                , secondCriterion
                , excludedCriterion {Training.rawCriterionRule = Training.RawCriterionAtLeastExcluding 0.25 1.0e-12}
                ]
            }
        refused
          fixture
            { completionDataCriteria =
                [ firstCriterion
                , secondCriterion
                , excludedCriterion {Training.rawCriterionRule = Training.RawCriterionAtLeastExcluding 0.5 2.0e-12}
                ]
            }
    , testCase "TensorBoard run identity and prefix are exact" $ do
        refused fixture {completionDataTensorBoard = tensorBoard {Training.tbrRunId = "another-run"}}
        refused fixture {completionDataTensorBoard = tensorBoard {Training.tbrLogPrefix = "another-prefix"}}
    , testCase "TensorBoard scalar tags preserve criterion order" $
        refused
          fixture
            { completionDataTensorBoard =
                tensorBoard {Training.tbrScalarTags = reverse (Training.tbrScalarTags tensorBoard)}
            }
    , testCase "the original scenario association cannot become direct" $
        refused fixture {completionDataInvocation = Nothing}
    , testCase "the original full invocation cannot be replaced" $
        refused fixture {completionDataInvocation = Just "another-invocation-transport"}
    , testCase "a compiled recipe ID cannot replace the whole native plan binding" $
        refused fixture {completionDataCompiledPlan = Just "another-compiled-recipe"}
    , testCase "canonical manifest metric name and order are exact" $ do
        refused fixture {completionDataManifestMetrics = reverse metrics}
        refused fixture {completionDataManifestMetrics = ("another", 0) : drop 1 metrics}
    , testCase "manifest metric signed zero survives numerical equality" $ do
        let expected = fixture {completionDataManifestMetrics = [("exact-zero", rawDouble 0)]}
            actual = expected {completionDataManifestMetrics = [("exact-zero", rawDouble signBit)]}
        assertSignedZero
          (snd <$> completionDataManifestMetrics expected)
          (snd <$> completionDataManifestMetrics actual)
        assertLeft (compareNativeCompletionScalarData expected actual)
    , testCase "nonfinite metrics on either side are rejected before equality" $
        mapM_
          (\value -> refusedBoth fixture {completionDataManifestMetrics = [("bad", rawDouble value)]})
          nonfiniteBits
    , testCase "nonfinite criterion threshold and measurement are rejected" $
        mapM_
          ( \value -> do
              refusedBoth
                fixture
                  { completionDataCriteria = [firstCriterion {Training.rawCriterionThreshold = rawDouble value}]
                  }
              refusedBoth
                fixture {completionDataCriteria = [firstCriterion {Training.rawMeasurementValue = rawDouble value}]}
          )
          nonfiniteBits
    , testCase "nonfinite exclusion centre and distance are rejected" $
        mapM_
          ( \value -> do
              refusedBoth
                fixture
                  { completionDataCriteria =
                      [ excludedCriterion
                          { Training.rawCriterionRule = Training.RawCriterionAtLeastExcluding (rawDouble value) 1.0e-12
                          }
                      ]
                  }
              refusedBoth
                fixture
                  { completionDataCriteria =
                      [ excludedCriterion
                          { Training.rawCriterionRule = Training.RawCriterionAtLeastExcluding 0.5 (rawDouble value)
                          }
                      ]
                  }
          )
          nonfiniteBits
    , testCase "the exact16 scalar bound is accepted for ordinary equal DATA" $ do
        let value =
              fixture
                { completionDataCriteria = replicate 16 firstCriterion
                , completionDataManifestMetrics = replicate 16 ("data", 1)
                , completionDataTensorBoard = tensorBoard {Training.tbrScalarTags = replicate 16 "data"}
                }
        compareNativeCompletionScalarData value value @?= Right ()
    , testCase "17 criteria refuse before demanding an element" $
        refusedBoth fixture {completionDataCriteria = replicate 17 (error "criterion must not be demanded")}
    , testCase "17 metrics refuse before demanding an element" $
        refusedBoth
          fixture {completionDataManifestMetrics = replicate 17 (error "metric must not be demanded")}
    , testCase "17 scalar tags refuse before demanding an element" $
        refusedBoth
          fixture
            { completionDataTensorBoard =
                tensorBoard {Training.tbrScalarTags = replicate 17 (error "tag must not be demanded")}
            }
    , testCase "an infinite criterion spine is bounded before traversal" $
        boundedRefusal fixture {completionDataCriteria = repeat firstCriterion}
    , testCase "an infinite metric spine is bounded before traversal" $
        boundedRefusal fixture {completionDataManifestMetrics = repeat ("data", 1)}
    , testCase "an infinite TensorBoard tag spine is bounded before traversal" $
        boundedRefusal
          fixture {completionDataTensorBoard = tensorBoard {Training.tbrScalarTags = repeat "data"}}
    , testCase "empty criterion or metric inventories are rejected on either side" $ do
        refusedBoth fixture {completionDataCriteria = []}
        refusedBoth fixture {completionDataManifestMetrics = []}
    ]

fixture :: NativeCompletionScalarData
fixture =
  NativeCompletionScalarData
    "ordinary-whole-plan"
    budget
    64
    "initial-jmw1"
    "final-jmw1"
    7
    "input-evidence"
    criteria
    tensorBoard
    (Just "ordinary-scenario-transport")
    Nothing
    64
    metrics

budget :: Training.RawTrainingBudget
budget = Training.RawTrainingBudget Training.RlEnvironmentStepBudget 64 (Just 42)

criteria :: [Training.RawConvergenceObservation]
criteria = [firstCriterion, secondCriterion, excludedCriterion]
firstCriterion, secondCriterion, excludedCriterion :: Training.RawConvergenceObservation
firstCriterion = Training.RawConvergenceObservation "at-least" Training.RawCriterionAtLeast 0.25 0.75
secondCriterion = Training.RawConvergenceObservation "at-most" Training.RawCriterionAtMost 0.75 0.25
excludedCriterion =
  Training.RawConvergenceObservation
    "excluded"
    (Training.RawCriterionAtLeastExcluding 0.5 1.0e-12)
    0.75
    1
restCriteria :: [Training.RawConvergenceObservation]
restCriteria = [secondCriterion, excludedCriterion]
tensorBoard :: Training.TensorBoardRunMetadata
tensorBoard =
  Training.TensorBoardRunMetadata
    "ordinary-experiment"
    "jitml-tensorboard/ordinary-experiment"
    (Training.rawCriterionName <$> criteria)
metrics :: [(Text, Double)]
metrics = [("at-least", 0.75), ("at-most", 0.25), ("excluded", 1)]

refused :: NativeCompletionScalarData -> Assertion
refused = assertLeft . compareNativeCompletionScalarData fixture
refusedBoth :: NativeCompletionScalarData -> Assertion
refusedBoth actual = do
  assertLeft (compareNativeCompletionScalarData actual actual)
  assertLeft (compareNativeCompletionScalarData fixture actual)
  assertLeft (compareNativeCompletionScalarData actual fixture)
assertLeft :: Either Text () -> Assertion
assertLeft actual = case actual of
  Left _ -> pure ()
  Right () -> assertFailure "invalid or substituted scalar DATA was accepted"

boundedRefusal :: NativeCompletionScalarData -> Assertion
boundedRefusal actual = do
  result <-
    timeout
      1000000
      (evaluate (case compareNativeCompletionScalarData actual actual of Left _ -> True; Right () -> False))
  result @?= Just True

assertSignedZero :: [Double] -> [Double] -> Assertion
assertSignedZero positive negative = case (positive, negative) of
  ([a], [b]) -> do
    assertBool "actual fixtures must be numerically equal" (a == b)
    castDoubleToWord64 a @?= 0
    castDoubleToWord64 b @?= signBit
  _ -> assertFailure "signed-zero fixture must contain exactly one actual scalar"
signBit :: Word64
signBit = 0x8000000000000000
nonfiniteBits :: [Word64]
nonfiniteBits = [0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000001]
rawDouble :: Word64 -> Double
rawDouble = castWord64ToDouble
{-# NOINLINE rawDouble #-}
