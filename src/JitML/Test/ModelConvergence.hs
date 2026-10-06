{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | Phase 285 — the per-model convergence stanza's contract-driven core.
--
-- Every per-row case here consumes an opaque
-- 'JitML.Test.ModelEvidence.ModelRowEvidence' minted from the validated
-- projection of the selected lane and the row of that lane's admitted,
-- pinned journal ('JitML.Test.ModelEvidence.admitModelEvidence'). There is no
-- case built from a registry row's own bar, and no measurement is ever the
-- target it is compared with. A missing, stale, altered, or inadmissible lane
-- journal fails every case closed with the typed diagnostic, by design.
--
-- The stanza trains nothing and serves nothing: heavy execution stays in the
-- ProductScenario integration lane that issues the journals, and the deterministic
-- work counts graded here are the ones that journal retains.
module JitML.Test.ModelConvergence
  ( RowCheck (..)
  , allRowChecks
  , assertLaneEvidenceCoverage
  , assertRegistryCoverage
  , assertRegistryCoverageOf
  , modelConvergenceRowIds
  , renderRowCheck
  , rowCheckFailures
  , selectedModelConvergenceSubstrate
  )
where

import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import System.Environment (lookupEnv)

import JitML.Plan.Plan (Validation (..))
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate (..), parseSubstrate, renderSubstrate)
import JitML.Test.ModelEvidence
  ( LaneEvidence (..)
  , LoadedLane (..)
  , ModelRowEvidence
  , SomeModelRowEvidence (..)
  , assertModelConvergence
  , assertModelLearning
  , assertModelPerformance
  , assertReceiptBinding
  , assertSomeModelBinding
  , lookupModelEvidence
  , modelEvidenceRowId
  , modelEvidenceSetRows
  , modelPerformanceReceipts
  , renderBindingFailure
  , renderFinalQualityFailure
  , renderLearningFailure
  , renderPerformanceFailure
  , renderReceiptBindingFailure
  , someModelEvidenceRowId
  )
import JitML.Test.ProductLaneJournal qualified as Lane

-- | The lane whose retained journal the stanza grades: @JITML_SUBSTRATE@
-- (exported by @jitml test --<substrate>@), defaulting to @linux-cpu@.
selectedModelConvergenceSubstrate :: IO (Either Text Substrate)
selectedModelConvergenceSubstrate = do
  raw <- lookupEnv "JITML_SUBSTRATE"
  pure $
    case raw of
      Nothing -> Right LinuxCPU
      Just value ->
        maybe
          (Left ("invalid JITML_SUBSTRATE: " <> Text.pack value))
          Right
          (parseSubstrate (Text.pack value))

-- | The registry's product rows, in order. The stanza's case tree is built
-- from this list; 'assertRegistryCoverage' proves the validated projection
-- covers exactly these rows.
modelConvergenceRowIds :: [Text]
modelConvergenceRowIds = ProductMatrix.productRowIds

-- | The four per-row assertion families, each a separate case per row.
data RowCheck
  = ConvergenceCheck
  | LearningCheck
  | PerformanceCheck
  | BindingCheck
  deriving stock (Eq, Show, Enum, Bounded)

allRowChecks :: [RowCheck]
allRowChecks = [minBound .. maxBound]

renderRowCheck :: RowCheck -> Text
renderRowCheck check =
  case check of
    ConvergenceCheck -> "final-quality convergence against the independent external criterion"
    LearningCheck -> "learning telemetry (budget exhausted, updates applied, weights moved)"
    PerformanceCheck -> "deterministic non-wall-clock performance bounds bound to the artifact"
    BindingCheck -> "plan, experiment, manifest, contract and seed-cohort binding"

-- | The registry must project, for the lane, to exactly its raw rows in
-- order: a row silently dropped by projection would otherwise vanish from the
-- stanza's coverage.
assertRegistryCoverage :: Substrate -> [Text]
assertRegistryCoverage lane = assertRegistryCoverageOf lane ProductMatrix.allProductRows

-- | 'assertRegistryCoverage' over an explicit registry slice, so a duplicate,
-- unprojectable, or missing row can be exercised against the same guard.
assertRegistryCoverageOf :: Substrate -> [ProductMatrix.ProductRow state] -> [Text]
assertRegistryCoverageOf lane rows =
  case ProductMatrix.projectProductRows lane rows of
    Failure errors ->
      fmap
        ( (("registry does not project for " <> renderSubstrate lane <> ": ") <>)
            . ProductMatrix.renderProductMatrixError
        )
        (NonEmpty.toList errors)
    Success batch ->
      let projected = ProductMatrix.productProjectionBatchRowIds batch
       in [ "projection dropped ProductRow " <> rowId
          | rowId <- ProductMatrix.productRowIds
          , rowId `notElem` projected
          ]
            <> [ "projection invented row " <> rowId
               | rowId <- projected
               , rowId `notElem` ProductMatrix.productRowIds
               ]
            <> [ "projection row order differs from the registry"
               | projected /= ProductMatrix.productRowIds
               , all (`elem` projected) ProductMatrix.productRowIds
               , all (`elem` ProductMatrix.productRowIds) projected
               ]

-- | Minted evidence must cover the lane's validated projection exactly once,
-- in registry order.
assertLaneEvidenceCoverage :: LaneEvidence -> [Text]
assertLaneEvidenceCoverage laneEvidence =
  [ "evidence set row order or coverage differs from the validated projection"
  | evidenceRows /= projectedRows
  ]
 where
  evidenceRows =
    fmap someModelEvidenceRowId (modelEvidenceSetRows (laneEvidenceSet laneEvidence))
  projectedRows =
    ProductMatrix.productProjectionBatchRowIds
      (loadedLaneBatch (laneEvidenceLoaded laneEvidence))

-- | Rendered failures of one assertion family for one row of a lane. A row
-- with no evidence or no projection is itself a failure.
rowCheckFailures :: RowCheck -> LaneEvidence -> Text -> [Text]
rowCheckFailures check laneEvidence rowIdentity =
  case ( lookupModelEvidence rowIdentity (laneEvidenceSet laneEvidence)
       , lookupProjection rowIdentity
       ) of
    (Nothing, _) -> ["no admitted evidence for row " <> rowIdentity]
    (Just _, Nothing) -> ["no validated projection for row " <> rowIdentity]
    (Just evidence, Just projection) ->
      case check of
        ConvergenceCheck ->
          withEvidence evidence (fmap renderFinalQualityFailure . assertModelConvergence)
        LearningCheck ->
          withEvidence evidence (fmap renderLearningFailure . assertModelLearning)
        PerformanceCheck ->
          withEvidence
            evidence
            ( \rowEvidence ->
                fmap renderPerformanceFailure (assertModelPerformance rowEvidence)
                  <> receiptBindingFailures laneEvidence rowEvidence
            )
        BindingCheck ->
          fmap renderBindingFailure (assertSomeModelBinding projection evidence)
 where
  batch = loadedLaneBatch (laneEvidenceLoaded laneEvidence)
  lookupProjection rowId =
    List.find
      ( \(ProductMatrix.SomeProductProjection _ projection) ->
          ProductMatrix.productProjectionRowId projection == rowId
      )
      (ProductMatrix.productProjectionBatchProjections batch)

-- | Apply a kind-polymorphic assertion to evidence of any run kind.
withEvidence
  :: SomeModelRowEvidence
  -> (forall kind. ModelRowEvidence kind -> result)
  -> result
withEvidence (SomeModelRowEvidence _ evidence) assertion = assertion evidence

-- | The deterministic performance measurement must be bound to the completed
-- artifact and plan of the /same/ admitted journal row, read back through the
-- journal's own accessors rather than through the evidence value: a receipt
-- for any other row, plan, experiment, or manifest is a failure, and so is a row
-- with no receipt ('assertReceiptBinding' owns the comparison).
receiptBindingFailures :: LaneEvidence -> ModelRowEvidence kind -> [Text]
receiptBindingFailures laneEvidence evidence =
  case journalRow of
    Nothing -> ["no admitted journal row for " <> rowIdentity]
    Just row ->
      fmap
        renderReceiptBindingFailure
        (assertReceiptBinding row (modelPerformanceReceipts evidence))
 where
  rowIdentity = modelEvidenceRowId evidence
  journalRow =
    List.find
      ((== rowIdentity) . Lane.productLaneJournalRowRowId)
      ( Lane.admittedProductLaneJournalRows
          (loadedLaneJournal (laneEvidenceLoaded laneEvidence))
      )
