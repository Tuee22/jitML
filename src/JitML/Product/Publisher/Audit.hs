{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.Publisher.Audit
  ( ProductArtifactReceipt (..)
  , ProductPublishDisposition (..)
  , ProductPublishResult (..)
  , productArtifactPointer
  , productPublishStatus
  , renderProductInventoryEntry
  , renderProductPublishResult
  , validateAdmittedProductCheckpoint
  , validateAdmittedProjectionIdentity
  , validateProductCompletedTrainingPlanId
  , validateProductPublishBatch
  )
where

import Data.Foldable (traverse_)
import Data.List qualified as List
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Training.Budget qualified as TrainingBudget

data ProductPublishDisposition
  = ProductPublishEligible !CheckpointStore.AdmittedCompletedCheckpoint
  | ProductPublishUnsupported !Text
  | ProductPublishError !Text
  deriving stock (Eq, Show)

data ProductArtifactReceipt = ProductArtifactReceipt
  { productArtifactExperimentHash :: !Text
  , productArtifactKind :: !Text
  , productArtifactSha :: !Text
  , productArtifactObjectKey :: !Text
  }
  deriving stock (Eq, Show)

data ProductPublishResult = ProductPublishResult
  { productPublishRowId :: !Text
  , productPublishExperimentHash :: !Text
  , productPublishDisposition :: !ProductPublishDisposition
  , productPublishArtifacts :: ![ProductArtifactReceipt]
  , productPublishMessage :: !Text
  }
  deriving stock (Eq, Show)

validateProductPublishBatch
  :: ProductMatrix.ProductProjectionBatch
  -> [ProductPublishResult]
  -> Either Text ()
validateProductPublishBatch projectedBatch results = do
  let projections = ProductMatrix.productProjectionBatchProjections projectedBatch
      expectedCount = length projections
  unlessEither
    (length results == expectedCount)
    ( "result count "
        <> Text.pack (show (length results))
        <> " differs from projected denominator "
        <> Text.pack (show expectedCount)
    )
  traverse_ validateEntry (zip projections results)
  let nonEligible =
        [ productPublishRowId result <> "=" <> productPublishStatus result
        | result <- results
        , productPublishStatus result /= "eligible"
        ]
  unlessEither
    (null nonEligible)
    ("every projected row must be admitted eligible; observed " <> Text.intercalate ", " nonEligible)
  requireUniqueProductValues
    "result row id"
    (fmap productPublishRowId results)
  requireUniqueProductValues
    "result experiment hash"
    (fmap productPublishExperimentHash results)
  requireUniqueProductValues
    "admitted manifest inventory address"
    [manifestSha | result <- results, Just manifestSha <- [productPublishManifestSha result]]
  let receipts = concatMap productPublishArtifacts results
  traverse_ validateArtifactReceipt receipts
  requireUniqueProductValues
    "companion artifact object key"
    (fmap productArtifactObjectKey receipts)
  let expectedTuningRows =
        [ ProductMatrix.productProjectionRowId projection
        | ProductMatrix.SomeProductProjection _ projection <- projections
        , ProductMatrix.productProjectionFamily projection == ProductMatrix.Tuning
        ]
      tuningReceipts =
        [ receipt
        | receipt <- receipts
        , productArtifactKind receipt == "tune-trials"
        ]
  unlessEither
    (length tuningReceipts == length expectedTuningRows)
    ( "v2 tuning transcript inventory count "
        <> Text.pack (show (length tuningReceipts))
        <> " differs from projected tuning-row count "
        <> Text.pack (show (length expectedTuningRows))
    )
 where
  validateEntry
    (ProductMatrix.SomeProductProjection _ projection, result) = do
      requireProjectedValue
        "publisher result row id"
        (ProductMatrix.productProjectionRowId projection)
        (productPublishRowId result)
      requireProjectedValue
        "publisher result experiment hash"
        (ProductMatrix.productProjectionExperimentHash projection)
        (productPublishExperimentHash result)
      traverse_
        ( requireProjectedValue
            "companion artifact experiment hash"
            (ProductMatrix.productProjectionExperimentHash projection)
            . productArtifactExperimentHash
        )
        (productPublishArtifacts result)
      case productPublishDisposition result of
        ProductPublishEligible admitted -> do
          validateAdmittedProjectionIdentity projection admitted
          let manifest =
                CheckpointStore.admittedCheckpointManifest
                  (CheckpointStore.admittedCompletedCheckpoint admitted)
              actualPointers =
                List.sortOn
                  artifactPointerIdentity
                  (Checkpoint.manifestTranscriptPointers manifest)
              expectedPointers =
                List.sortOn
                  artifactPointerIdentity
                  (fmap productArtifactPointer (productPublishArtifacts result))
          requireProjectedValue
            "admitted companion artifact inventory"
            expectedPointers
            actualPointers
          let expectedArtifactKinds =
                case ProductMatrix.productProjectionFamily projection of
                  ProductMatrix.Supervised -> []
                  ProductMatrix.ReinforcementLearning -> ["rl-trajectory"]
                  ProductMatrix.AlphaZero -> ["alphazero-transcript"]
                  ProductMatrix.Tuning -> ["tune-trials"]
          requireProjectedValue
            "projected companion artifact kinds"
            expectedArtifactKinds
            (fmap productArtifactKind (productPublishArtifacts result))
          let tuningReceiptCount =
                length
                  [ ()
                  | receipt <- productPublishArtifacts result
                  , productArtifactKind receipt == "tune-trials"
                  ]
              expectedTuningReceiptCount =
                if ProductMatrix.productProjectionFamily projection == ProductMatrix.Tuning
                  then 1
                  else 0
          requireProjectedValue
            "projected tuning transcript count"
            expectedTuningReceiptCount
            tuningReceiptCount
        ProductPublishUnsupported reason ->
          Left
            ( ProductMatrix.productProjectionRowId projection
                <> " remained unsupported after successful projection: "
                <> reason
            )
        ProductPublishError reason ->
          Left
            ( ProductMatrix.productProjectionRowId projection
                <> " failed publication: "
                <> reason
            )

  validateArtifactReceipt receipt = do
    unlessEither
      (isCanonicalSha256 (productArtifactSha receipt))
      ("artifact receipt has non-canonical SHA-256: " <> productArtifactSha receipt)
    let expectedKey =
          "jitml-checkpoints/"
            <> productArtifactExperimentHash receipt
            <> "/artifacts/"
            <> productArtifactKind receipt
            <> "/"
            <> productArtifactSha receipt
            <> ".txt"
    requireProjectedValue
      "companion artifact object key"
      expectedKey
      (productArtifactObjectKey receipt)

  artifactPointerIdentity pointer =
    ( Checkpoint.artifactPointerKind pointer
    , Checkpoint.artifactPointerObjectKey pointer
    , Checkpoint.artifactPointerSha pointer
    )
{-# NOINLINE validateProductPublishBatch #-}

validateProductCompletedTrainingPlanId
  :: ProductMatrix.ProductProjection kind
  -> TrainingBudget.CompletedTraining
  -> Either Text ()
validateProductCompletedTrainingPlanId projection completed =
  requireProjectedValue
    ("persisted CompletedTraining PlanId for " <> ProductMatrix.productProjectionRowId projection)
    (ProductMatrix.productProjectionPlanId projection)
    (TrainingBudget.completedTrainingPlanId completed)
{-# NOINLINE validateProductCompletedTrainingPlanId #-}

-- | Refine the write receipt and Store's opaque re-admission into evidence for
-- exactly one projected ProductRow.  Neither a successful write nor a
-- caller-held completion can cross this boundary on its own.
validateAdmittedProductCheckpoint
  :: ProductMatrix.ProductProjection kind
  -> TrainingBudget.CompletedTraining
  -> CheckpointStore.StoredCompletedCheckpoint
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> Either Text ()
validateAdmittedProductCheckpoint projection expectedCompleted stored admitted = do
  let storedSnapshot = CheckpointStore.completedStoredCheckpoint stored
      admittedCheckpoint = CheckpointStore.admittedCompletedCheckpoint admitted
      admittedManifest = CheckpointStore.admittedCheckpointManifest admittedCheckpoint
      admittedManifestSha = CheckpointStore.admittedCheckpointManifestSha admittedCheckpoint
      admittedCompleted = CheckpointStore.admittedCompletedTraining admitted
      expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
      expectedRowId = ProductMatrix.productProjectionRowId projection
      expectedPlanId = ProductMatrix.productProjectionPlanId projection
  requireProjectedValue
    "stored/admitted manifest address"
    (CheckpointStore.storedManifestSha storedSnapshot)
    admittedManifestSha
  requireProjectedValue
    "admitted manifest experiment"
    expectedExperiment
    (Checkpoint.manifestExperiment admittedManifest)
  requireProjectedValue
    "admitted manifest PlanId"
    (Just expectedPlanId)
    (Checkpoint.manifestPlanId admittedManifest)
  requireProjectedValue
    "admitted CompletedTraining"
    expectedCompleted
    admittedCompleted
  requireProjectedValue
    "admitted CompletedTraining PlanId"
    expectedPlanId
    (TrainingBudget.completedTrainingPlanId admittedCompleted)
  canonicalRow <-
    maybe
      (Left ("admitted experiment does not resolve to a canonical ProductRow: " <> expectedExperiment))
      Right
      (ProductMatrix.productRowForExperimentHash (Checkpoint.manifestExperiment admittedManifest))
  requireProjectedValue
    "admitted canonical ProductRow id"
    expectedRowId
    (ProductMatrix.rowId canonicalRow)
  case ProductMatrix.productProjectionFamily projection of
    ProductMatrix.Supervised ->
      case Checkpoint.manifestSupervisedRuntime admittedManifest of
        Nothing -> Left "admitted supervised ProductRow has no exact V2 runtime payload"
        Just payload -> do
          requireProjectedValue
            "admitted supervised runtime ProductRow id"
            expectedRowId
            (RuntimeArtifact.payloadRowId payload)
          requireProjectedValue
            "admitted supervised runtime origin"
            RuntimeArtifact.RawProductRowProjectionOrigin
            ( RuntimeArtifact.supervisedRuntimeOriginToRaw
                (RuntimeArtifact.payloadOrigin payload)
            )
    _ ->
      requireProjectedValue
        "non-supervised ProductRow supervised-runtime payload"
        Nothing
        (Checkpoint.manifestSupervisedRuntime admittedManifest)
{-# NOINLINE validateAdmittedProductCheckpoint #-}

validateAdmittedProjectionIdentity
  :: ProductMatrix.ProductProjection kind
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> Either Text ()
validateAdmittedProjectionIdentity projection admitted = do
  let checkpoint = CheckpointStore.admittedCompletedCheckpoint admitted
      manifest = CheckpointStore.admittedCheckpointManifest checkpoint
      completed = CheckpointStore.admittedCompletedTraining admitted
      expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
      expectedRowId = ProductMatrix.productProjectionRowId projection
      expectedPlanId = ProductMatrix.productProjectionPlanId projection
  requireProjectedValue
    "inventory manifest experiment"
    expectedExperiment
    (Checkpoint.manifestExperiment manifest)
  requireProjectedValue
    "inventory manifest PlanId"
    (Just expectedPlanId)
    (Checkpoint.manifestPlanId manifest)
  requireProjectedValue
    "inventory completion PlanId"
    expectedPlanId
    (TrainingBudget.completedTrainingPlanId completed)
  requireProjectedValue
    "inventory completion budget"
    (ProductMatrix.productProjectionTrainingBudget projection)
    (TrainingBudget.completedTrainingBudget completed)
  canonicalRow <-
    maybe
      (Left ("inventory experiment has no canonical ProductRow: " <> expectedExperiment))
      Right
      (ProductMatrix.productRowForExperimentHash (Checkpoint.manifestExperiment manifest))
  requireProjectedValue
    "inventory ProductRow id"
    expectedRowId
    (ProductMatrix.rowId canonicalRow)
  case ProductMatrix.productProjectionFamily projection of
    ProductMatrix.Supervised ->
      case Checkpoint.manifestSupervisedRuntime manifest of
        Nothing -> Left "inventory supervised row has no exact V2 runtime payload"
        Just payload -> do
          requireProjectedValue
            "inventory supervised runtime ProductRow id"
            expectedRowId
            (RuntimeArtifact.payloadRowId payload)
          requireProjectedValue
            "inventory supervised runtime origin"
            RuntimeArtifact.RawProductRowProjectionOrigin
            ( RuntimeArtifact.supervisedRuntimeOriginToRaw
                (RuntimeArtifact.payloadOrigin payload)
            )
    _ ->
      requireProjectedValue
        "inventory non-supervised runtime payload"
        Nothing
        (Checkpoint.manifestSupervisedRuntime manifest)

productArtifactPointer :: ProductArtifactReceipt -> Checkpoint.ArtifactPointer
productArtifactPointer receipt =
  Checkpoint.ArtifactPointer
    { Checkpoint.artifactPointerKind = productArtifactKind receipt
    , Checkpoint.artifactPointerObjectKey = productArtifactObjectKey receipt
    , Checkpoint.artifactPointerSha = Just (productArtifactSha receipt)
    }
{-# NOINLINE productArtifactPointer #-}

productPublishStatus :: ProductPublishResult -> Text
productPublishStatus result =
  case productPublishDisposition result of
    ProductPublishEligible _ -> "eligible"
    ProductPublishUnsupported _ -> "unsupported"
    ProductPublishError _ -> "error"
{-# NOINLINE productPublishStatus #-}

productPublishManifestSha :: ProductPublishResult -> Maybe Text
productPublishManifestSha result =
  case productPublishDisposition result of
    ProductPublishEligible admitted ->
      Just
        ( CheckpointStore.admittedCheckpointManifestSha
            (CheckpointStore.admittedCompletedCheckpoint admitted)
        )
    ProductPublishUnsupported _ -> Nothing
    ProductPublishError _ -> Nothing

renderProductPublishResult :: ProductPublishResult -> Text
renderProductPublishResult result =
  Text.intercalate
    "\t"
    [ "product-row"
    , productPublishRowId result
    , productPublishExperimentHash result
    , productPublishStatus result
    , fromMaybe "none" (productPublishManifestSha result)
    , productPublishMessage result
    ]
{-# NOINLINE renderProductPublishResult #-}

renderProductInventoryEntry :: ProductPublishResult -> [Text]
renderProductInventoryEntry result =
  case productPublishDisposition result of
    ProductPublishEligible admitted ->
      let checkpoint = CheckpointStore.admittedCompletedCheckpoint admitted
       in [ Text.intercalate
              "\t"
              [ "product-inventory"
              , productPublishRowId result
              , productPublishExperimentHash result
              , CheckpointStore.admittedCheckpointManifestSha checkpoint
              , "admitted"
              ]
          ]
            <> fmap renderArtifact (productPublishArtifacts result)
    ProductPublishUnsupported _ -> []
    ProductPublishError _ -> []
 where
  renderArtifact receipt =
    Text.intercalate
      "\t"
      [ "product-artifact"
      , productPublishRowId result
      , productArtifactExperimentHash receipt
      , productArtifactKind receipt
      , productArtifactSha receipt
      , productArtifactObjectKey receipt
      ]
{-# NOINLINE renderProductInventoryEntry #-}

requireProjectedValue :: (Eq value, Show value) => Text -> value -> value -> Either Text ()
requireProjectedValue label expected actual
  | expected == actual = Right ()
  | otherwise =
      Left
        ( label
            <> " mismatch: projected "
            <> Text.pack (show expected)
            <> ", resolved "
            <> Text.pack (show actual)
        )

unlessEither :: Bool -> Text -> Either Text ()
unlessEither condition message
  | condition = Right ()
  | otherwise = Left message

requireUniqueProductValues :: Text -> [Text] -> Either Text ()
requireUniqueProductValues label values =
  let duplicates =
        [ value
        | value <- List.nub values
        , length (filter (== value) values) > 1
        ]
   in unlessEither
        (null duplicates)
        ("duplicate " <> label <> " values: " <> Text.intercalate ", " duplicates)

isCanonicalSha256 :: Text -> Bool
isCanonicalSha256 value =
  Text.length value == 64
    && Text.all (`elem` ("0123456789abcdef" :: String)) value
