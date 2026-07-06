{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 33 — the per-model measured-convergence + inference-performance case
-- registry.
--
-- One case per 'JitML.Product.Matrix.ProductRow', enumerated from the registry
-- so coverage cannot silently drop (Exit Definition items 22/24). The coverage
-- assertion is real and compilable; the per-row __measurement__ is a documented
-- seam ('pendingMeasurement') that is RED by design until reopened Phases 24-26
-- make the models real and Phase 33 wires the trained-from-random-init
-- measurement through the production device seam against the external bar.
--
-- __Validation status:__ UNVALIDATED (authored without a compiler in-session).
-- Build/run in the container.
module JitML.Test.ModelConvergence
  ( ModelConvergenceCase (..)
  , modelConvergenceCases
  , assertModelConvergenceCoverage
  , pendingMeasurement
  )
where

import Data.Text (Text)

import JitML.Product.Matrix qualified as ProductMatrix

data ModelConvergenceCase = ModelConvergenceCase
  { mccRowId :: Text
  , mccFamily :: ProductMatrix.RowFamily
  , mccIntegrationTest :: Text
  }
  deriving stock (Eq, Show)

modelConvergenceCases :: [ModelConvergenceCase]
modelConvergenceCases = fmap toCase ProductMatrix.allProductRows
 where
  toCase row =
    ModelConvergenceCase
      { mccRowId = ProductMatrix.rowId row
      , mccFamily = ProductMatrix.family row
      , mccIntegrationTest = ProductMatrix.integrationTest row
      }

-- | Every ProductRow must own a model-convergence case.
assertModelConvergenceCoverage :: [Text]
assertModelConvergenceCoverage =
  [ "ProductRow missing a model-convergence case: " <> rid
  | rid <- ProductMatrix.productRowIds
  , rid `notElem` fmap mccRowId modelConvergenceCases
  ]

-- | The per-row measurement seam. Until the models are real and the measurement
-- is wired through the production device seam, every case is pending — so the
-- measurement group is RED by design (the red-first baseline the harness
-- installs). Wiring this to real training is owned by Phase 33 and the reopened
-- Phases 24-26.
pendingMeasurement :: ModelConvergenceCase -> Text
pendingMeasurement mcc =
  "pending real training + measured convergence for row "
    <> mccRowId mcc
    <> " (owned by Phase 33 / reopened Phases 24-26): train from a real random init "
    <> "through the production device seam and assert the measured metric clears its "
    <> "external bar and its inference-performance floor, reproduced bit-identically."
