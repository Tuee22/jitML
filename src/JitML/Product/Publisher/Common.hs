{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Common
  ( admitPublishedProductCheckpoint
  , bindProductScenarioCompletion
  , productPublishEligible
  , productPublishError
  , productPublishUnsupported
  , reuseProductPublishResult
  , validateProductScenarioInvocation
  , writeProductTextArtifact
  )
where

import Data.Bifunctor (first)
import Data.Maybe (fromMaybe)
import Data.Text (Text)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Env.Env (App)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher.Audit
  ( ProductArtifactReceipt (..)
  , ProductPublishDisposition (..)
  , ProductPublishResult (..)
  , validateAdmittedProductCheckpoint
  )
import JitML.Product.Publisher.Runtime (ProductPublisherRuntime (..))
import JitML.Training.Budget qualified as TrainingBudget

reuseProductPublishResult
  :: ProductMatrix.ProductProjection kind
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> ProductPublishResult
reuseProductPublishResult projection admitted =
  productPublishEligible
    projection
    admitted
    reuseReceipts
    "reused admitted product-row checkpoint"
 where
  manifest =
    CheckpointStore.admittedCheckpointManifest
      (CheckpointStore.admittedCompletedCheckpoint admitted)
  -- A receipt carries the __logical__ content address of its companion
  -- artifact; the batch audit rebases it into the manifest's storage-snapshot
  -- namespace before comparing inventories, and
  -- 'CheckpointStore.canonicalProductCompanionObjectKey' is the one owner of
  -- that derivation (the admission check in `Checkpoint.Store` reads it too).
  --
  -- The manifest's own pointers are already __physical__, so copying them here
  -- made a reused receipt disagree with a freshly published one: the audit
  -- scoped an already-scoped key and compared `SHA256(physical)` against the
  -- manifest's `SHA256(logical)`. Same snapshot, same payload SHA, different
  -- object address. Deriving the logical key instead makes a reused receipt
  -- byte-identical to the one a fresh publish produces, which is exactly what
  -- reuse claims to be.
  reuseReceipts =
    [ ProductArtifactReceipt
        { productArtifactExperimentHash = experimentHash
        , productArtifactKind = kind
        , productArtifactSha = sha
        , productArtifactObjectKey =
            CheckpointStore.canonicalProductCompanionObjectKey experimentHash kind sha
        }
    | pointer <- Checkpoint.manifestTranscriptPointers manifest
    , let kind = Checkpoint.artifactPointerKind pointer
    , let sha = fromMaybe "" (Checkpoint.artifactPointerSha pointer)
    ]
  experimentHash = ProductMatrix.productProjectionExperimentHash projection

validateProductScenarioInvocation
  :: ProductMatrix.ProductProjection kind
  -> TrainingBudget.ProductScenarioInvocation
  -> Either Text ()
validateProductScenarioInvocation projection invocation = do
  requireInvocationField
    "row identity"
    (ProductMatrix.productProjectionRowId projection)
    (TrainingBudget.productScenarioInvocationRowId invocation)
  requireInvocationField
    "PlanId"
    (ProductMatrix.productProjectionPlanId projection)
    (TrainingBudget.productScenarioInvocationPlanId invocation)
  requireInvocationField
    "substrate"
    (ProductMatrix.productProjectionSubstrate projection)
    (TrainingBudget.productScenarioInvocationSubstrate invocation)
 where
  requireInvocationField label expected observed
    | expected == observed = Right ()
    | otherwise = Left (label <> " differs from the exact ProductProjection")

bindProductScenarioCompletion
  :: Maybe TrainingBudget.ProductScenarioInvocation
  -> ProductMatrix.ProductProjection kind
  -> TrainingBudget.CompletedTraining
  -> Either Text TrainingBudget.CompletedTraining
bindProductScenarioCompletion Nothing _projection completed = Right completed
bindProductScenarioCompletion (Just invocation) projection completed = do
  validateProductScenarioInvocation projection invocation
  TrainingBudget.bindCompletedTrainingToProductScenarioInvocation invocation completed

admitPublishedProductCheckpoint
  :: ProductPublisherRuntime
  -> ProductMatrix.ProductProjection kind
  -> TrainingBudget.CompletedTraining
  -> CheckpointStore.StoredCompletedCheckpoint
  -> App (Either Text CheckpointStore.AdmittedCompletedCheckpoint)
admitPublishedProductCheckpoint runtime projection completed stored = do
  admission <-
    publisherAdmitCompletedCheckpoint
      runtime
      (ProductMatrix.productProjectionExperimentHash projection)
      stored
  pure $ do
    admitted <- first CheckpointStore.renderCheckpointAdmissionError admission
    validateAdmittedProductCheckpoint projection completed stored admitted
    Right admitted

writeProductTextArtifact
  :: ProductPublisherRuntime
  -> Text
  -> Text
  -> Text
  -> App ProductArtifactReceipt
writeProductTextArtifact runtime experimentHash kind payload = do
  (sha, objectKey) <- publisherWriteTextArtifact runtime experimentHash kind payload
  pure
    ProductArtifactReceipt
      { productArtifactExperimentHash = experimentHash
      , productArtifactKind = kind
      , productArtifactSha = sha
      , productArtifactObjectKey = objectKey
      }

productPublishEligible
  :: ProductMatrix.ProductProjection kind
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> [ProductArtifactReceipt]
  -> Text
  -> ProductPublishResult
productPublishEligible projection admitted artifacts message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.productProjectionRowId projection
    , productPublishExperimentHash = ProductMatrix.productProjectionExperimentHash projection
    , productPublishDisposition = ProductPublishEligible admitted
    , productPublishArtifacts = artifacts
    , productPublishMessage = message
    }

productPublishUnsupported :: ProductMatrix.ProductProjection kind -> Text -> ProductPublishResult
productPublishUnsupported projection message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.productProjectionRowId projection
    , productPublishExperimentHash = ProductMatrix.productProjectionExperimentHash projection
    , productPublishDisposition = ProductPublishUnsupported message
    , productPublishArtifacts = []
    , productPublishMessage = message
    }

productPublishError :: ProductMatrix.ProductProjection kind -> Text -> ProductPublishResult
productPublishError projection message =
  ProductPublishResult
    { productPublishRowId = ProductMatrix.productProjectionRowId projection
    , productPublishExperimentHash = ProductMatrix.productProjectionExperimentHash projection
    , productPublishDisposition = ProductPublishError message
    , productPublishArtifacts = []
    , productPublishMessage = message
    }

{-# NOINLINE admitPublishedProductCheckpoint #-}
{-# NOINLINE bindProductScenarioCompletion #-}
{-# NOINLINE productPublishEligible #-}
{-# NOINLINE productPublishError #-}
{-# NOINLINE productPublishUnsupported #-}
{-# NOINLINE reuseProductPublishResult #-}
{-# NOINLINE validateProductScenarioInvocation #-}
{-# NOINLINE writeProductTextArtifact #-}
