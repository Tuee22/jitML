{-# LANGUAGE OverloadedStrings #-}

-- | Phase 33 — the per-model convergence + inference-performance case registry.
--
-- One case per 'JitML.Product.Matrix.ProductRow', enumerated from the registry
-- so coverage cannot silently drop (Exit Definition items 22/24). Heavy
-- train-from-random-init execution stays in the existing product-row
-- integration/publisher lanes; this stanza is the standing lightweight guard
-- that every row owns a convergence case, an externally anchored bar, named
-- integration/e2e evidence, and a non-wall-clock inference-performance floor.
module JitML.Test.ModelConvergence
  ( ModelConvergenceCase (..)
  , modelConvergenceCases
  , assertModelConvergenceCoverage
  , assertModelConvergenceCase
  , assertModelPerformanceCase
  )
where

import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.ExternalBars qualified as ExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Training.Budget (MetricGoal (..))

data ModelConvergenceCase = ModelConvergenceCase
  { mccRowId :: Text
  , mccFamily :: ProductMatrix.RowFamily
  , mccIntegrationTest :: Text
  , mccE2ETest :: Text
  , mccConvergenceMetric :: Text
  , mccConvergenceGoal :: MetricGoal
  , mccConvergenceTarget :: Double
  , mccConvergenceThreshold :: Double
  , mccConvergenceSlack :: Double
  , mccPerformanceMetric :: Text
  , mccPerformanceFloor :: Double
  }
  deriving stock (Eq, Show)

modelConvergenceCases :: [ModelConvergenceCase]
modelConvergenceCases = fmap toCase ProductMatrix.allProductRows
 where
  toCase row =
    let bar = ProductMatrix.convergenceBar row
     in ModelConvergenceCase
          { mccRowId = ProductMatrix.rowId row
          , mccFamily = ProductMatrix.family row
          , mccIntegrationTest = ProductMatrix.integrationTest row
          , mccE2ETest = ProductMatrix.e2eTest row
          , mccConvergenceMetric = ProductConvergence.convergenceMetricName bar
          , mccConvergenceGoal = ProductConvergence.convergenceMetricGoal bar
          , mccConvergenceTarget = ProductConvergence.convergenceLiteratureTarget bar
          , mccConvergenceThreshold = ProductConvergence.convergenceThreshold bar
          , mccConvergenceSlack = ProductConvergence.convergenceSlack bar
          , mccPerformanceMetric = performanceMetricFor (ProductMatrix.family row)
          , mccPerformanceFloor = performanceFloorFor (ProductMatrix.family row)
          }

-- | Every ProductRow must own a model-convergence case.
assertModelConvergenceCoverage :: [Text]
assertModelConvergenceCoverage =
  missingFailures <> duplicateFailures <> orphanFailures
 where
  expectedIds = ProductMatrix.productRowIds
  observedIds = fmap mccRowId modelConvergenceCases
  missingFailures =
    [ "ProductRow missing a model-convergence case: " <> rid
    | rid <- expectedIds
    , rid `notElem` observedIds
    ]
  duplicateFailures =
    [ "duplicate model-convergence case: " <> rid
    | rid <- duplicates observedIds
    ]
  orphanFailures =
    [ "model-convergence case is not a ProductRow: " <> rid
    | rid <- observedIds
    , rid `notElem` expectedIds
    ]

assertModelConvergenceCase :: ModelConvergenceCase -> [Text]
assertModelConvergenceCase mcc =
  concat
    [ requiredText "row id" mccRowId
    , requiredText "integration test" mccIntegrationTest
    , requiredText "e2e test" mccE2ETest
    , requiredText "convergence metric" mccConvergenceMetric
    , finiteMetric "convergence target" mccConvergenceTarget
    , finiteMetric "convergence threshold" mccConvergenceThreshold
    , positiveFinite "convergence slack" mccConvergenceSlack
    , externalBarFailures
    ]
 where
  requiredText label selector =
    [ label <> " is required for row " <> mccRowId mcc
    | Text.null (Text.strip (selector mcc))
    ]
  finiteMetric label selector =
    [ label <> " must be finite for row " <> mccRowId mcc
    | not (finiteDouble (selector mcc))
    ]
  positiveFinite label selector =
    [ label <> " must be finite and positive for row " <> mccRowId mcc
    | let value = selector mcc
    , not (finiteDouble value) || value <= 0.0
    ]
  externalBarFailures =
    fmap
      (\msg -> mccRowId mcc <> ": " <> msg)
      ( ExternalBars.assertProductBarExternal
          ( ProductConvergence.mkConvergenceBar
              (mccConvergenceMetric mcc)
              (mccConvergenceGoal mcc)
              (mccConvergenceTarget mcc)
              (mccConvergenceSlack mcc)
          )
          (mccConvergenceTarget mcc)
      )

assertModelPerformanceCase :: ModelConvergenceCase -> [Text]
assertModelPerformanceCase mcc =
  requiredText "performance metric" mccPerformanceMetric
    ++ positiveFinite "performance floor" mccPerformanceFloor
 where
  requiredText label selector =
    [ label <> " is required for row " <> mccRowId mcc
    | Text.null (Text.strip (selector mcc))
    ]
  positiveFinite label selector =
    [ label <> " must be finite and positive for row " <> mccRowId mcc
    | let value = selector mcc
    , not (finiteDouble value) || value <= 0.0
    ]

performanceMetricFor :: ProductMatrix.RowFamily -> Text
performanceMetricFor rowFamily =
  case rowFamily of
    ProductMatrix.Supervised -> "examples_per_second"
    ProductMatrix.ReinforcementLearning -> "env_steps_to_threshold"
    ProductMatrix.AlphaZero -> "arena_nodes_per_inference"
    ProductMatrix.Tuning -> "objective_evaluations_per_trial"

performanceFloorFor :: ProductMatrix.RowFamily -> Double
performanceFloorFor rowFamily =
  case rowFamily of
    ProductMatrix.Supervised -> 1.0
    ProductMatrix.ReinforcementLearning -> 1.0
    ProductMatrix.AlphaZero -> 1.0
    ProductMatrix.Tuning -> 1.0

finiteDouble :: Double -> Bool
finiteDouble value =
  not (isNaN value) && not (isInfinite value)

duplicates :: [Text] -> [Text]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]
