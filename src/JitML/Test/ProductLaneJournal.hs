{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Portable, content-addressed evidence projected from an authenticated
-- ProductScenario journal.
--
-- The live journal remains the authority that re-admits exact checkpoints and
-- authenticates execution receipts.  This module emits the durable subset a
-- later CPU-only aggregation can retain after that live scope disappears.  An
-- issued value can be built only from 'AuthenticatedProductScenarioReport'. A
-- persisted value is admitted only when its exact SHA-256 is supplied by the
-- caller, its JSON is canonical, and every embedded 'CompletedTraining' value
-- refines against the current ProductRow projection.
module JitML.Test.ProductLaneJournal
  ( AdmittedProductLaneJournal
  , ProductLaneJournalError (..)
  , ProductLaneJournalRow
  , IssuedProductLaneJournal
  , admitProductLaneJournal
  , admitProductLaneJournalWithQualifications
  , admitProductLaneJournalWithNativeBundles
  , productLaneJournalQualificationObjectKeys
  , issuedProductLaneJournalQualificationObjects
  , admittedProductLaneJournalRows
  , admittedProductLaneJournalRunId
  , admittedProductLaneJournalSourceDigest
  , admittedProductLaneJournalReviewBindings
  , admittedProductLaneJournalSubstrate
  , buildProductLaneJournal
  , issuedProductLaneJournalBytes
  , issuedProductLaneJournalSha256
  , productLaneJournalRowCompletedTraining
  , productLaneJournalRowContractDigest
  , productLaneJournalRowDeviceWitness
  , productLaneJournalRowExecutionProvenance
  , renderProductLaneJournalRowExecutionProvenance
  , productLaneJournalRowExperimentHash
  , productLaneJournalRowJournalDigest
  , productLaneJournalRowManifestSha
  , productLaneJournalRowMeasuredDigest
  , productLaneJournalRowPlanId
  , productLaneJournalRowRowId
  , productLaneJournalRowSubstrate
  , validateProductLaneContract
  , productLaneJournalWireVersion
  , writeProductLaneJournalAtomic
  )
where

import Control.Exception (IOException, onException, try)
import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , Value (..)
  , eitherDecodeStrict'
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types (Object, Parser, parseEither)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit, isControl)
import Data.Either.Combinators (mapLeft)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64, Word8)
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (hClose, hFlush, openBinaryTempFile)

import JitML.Checkpoint.Store qualified as Store
import JitML.Plan.Plan (PlanId, planIdText)
import JitML.Plan.Plan qualified as Plan
import JitML.Product.ArsHostReference qualified as ArsReference
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.ExecutionProvenance (ExecutionProvenance (..))
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.SupervisedQualificationReceipt qualified as Receipt
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Test.NativeLaneBundle qualified as Native
import JitML.Test.NativeScenarioJournalBindingData qualified as NativeBinding
import JitML.Test.NativeScenarioReceiptData qualified as NativeReceipt
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report qualified as Report
import JitML.Training.Budget (CompletedTraining)
import JitML.Training.Budget qualified as Budget

productLaneJournalFormat :: Text
productLaneJournalFormat = "jitml-product-lane-journal"

productLaneJournalWireVersion :: Word64
productLaneJournalWireVersion = 3

data ProductLaneJournalWire = ProductLaneJournalWire
  { wireFormat :: !Text
  , wireVersion :: !Word64
  , wireRunId :: !Text
  , wireSubstrate :: !Text
  , wireSourceJournalSha :: !Text
  , wireRows :: ![ProductLaneJournalRowWire]
  }
  deriving stock (Eq, Show)

data ProductLaneJournalRowWire = ProductLaneJournalRowWire
  { wireRowOrdinal :: !Word64
  , wireRowId :: !Text
  , wireRowPlanId :: !Text
  , wireRowSubstrate :: !Text
  , wireRowExperimentHash :: !Text
  , wireRowManifestSha :: !Text
  , wireRowInferenceManifestSha :: !Text
  , wireRowCheckpointScopeSha :: !Text
  , wireRowExecutableSha :: !Text
  , wireRowInvocationSha :: !Text
  , wireRowContractSha :: !Text
  , wireRowJournalSha :: !Text
  , wireRowMeasuredSha :: !Text
  , wireRowDeviceWitness :: !Text
  , wireRowCompletedTraining :: !Text
  , wireRowQualificationReceipt :: !Text
  , wireRowNativeBundle :: !Text
  , wireRowStatus :: !Text
  }
  deriving stock (Eq, Show)

data IssuedProductLaneJournal = IssuedProductLaneJournal
  { issuedWire :: ProductLaneJournalWire
  , issuedQualifications :: [(Text, ByteString)]
  , issuedNativeQualifications :: [(Text, ByteString)]
  , issuedNativePlans :: [Native.NativeBundleWritePlan]
  }
  deriving stock (Eq, Show)

data AdmittedProductLaneJournal = AdmittedProductLaneJournal
  { admittedWire :: !ProductLaneJournalWire
  , admittedSubstrate :: !Substrate
  , admittedRows :: ![ProductLaneJournalRow]
  }
  deriving stock (Eq, Show)

data ProductLaneJournalRow = ProductLaneJournalRow
  { admittedRowWire :: !ProductLaneJournalRowWire
  , admittedRowPlan :: !PlanId
  , admittedRowLane :: !Substrate
  , admittedRowCheckpoint :: !RetainedCheckpointIdentity
  , admittedRowExecution :: !(ExecutionProvenance ArsReference.ArsHostReference)
  , admittedRowQualification :: !(Maybe Receipt.RetainedSupervisedQualification)
  , admittedRowNativeAudit :: !(Maybe Native.NativeBundleAudit)
  , admittedRowCompleted :: !CompletedTraining
  }
  deriving stock (Eq, Show)

-- | Opaque identity of the exact checkpoint admitted while the authenticated
-- source journal still owned its live Store scope. Re-admission of the
-- portable journal can recover this value only after its pinned digest,
-- canonical encoding, current projection, and equal training/inference
-- manifest identities have all passed.
data RetainedCheckpointIdentity = RetainedCheckpointIdentity !Text !Text
  deriving stock (Eq, Show)

data ProductLaneJournalError
  = ProductLaneJournalSourceRejected !Text
  | -- | A row's @contract_sha256@ differs from the digest of the contract the
    -- current projection derives: the row id, the digest the current projection
    -- requires, and the digest the journal carries. The journal is well formed
    -- but was issued under another contract, so it is stale rather than
    -- corrupt. Read-side classification only: it rejects exactly what the
    -- untyped rejection it replaces rejected.
    ProductLaneJournalContractStale !Text !Text !Text
  | ProductLaneJournalWireStale !Word64 !Word64
  | ProductLaneJournalMalformed !Text
  | ProductLaneJournalNonCanonical
  | ProductLaneJournalDigestMismatch !Text !Text
  | ProductLaneJournalIOFailure !FilePath !Text
  deriving stock (Eq, Show)

instance ToJSON ProductLaneJournalWire where
  toJSON journal =
    object
      [ "format" .= wireFormat journal
      , "version" .= wireVersion journal
      , "run_id" .= wireRunId journal
      , "substrate" .= wireSubstrate journal
      , "source_journal_sha256" .= wireSourceJournalSha journal
      , "rows" .= wireRows journal
      ]

instance FromJSON ProductLaneJournalWire where
  parseJSON =
    withObject "ProductLaneJournal" $ \record -> do
      requireExactFields
        "ProductLaneJournal"
        [ "format"
        , "version"
        , "run_id"
        , "substrate"
        , "source_journal_sha256"
        , "rows"
        ]
        record
      ProductLaneJournalWire
        <$> record .: "format"
        <*> record .: "version"
        <*> record .: "run_id"
        <*> record .: "substrate"
        <*> record .: "source_journal_sha256"
        <*> record .: "rows"

instance ToJSON ProductLaneJournalRowWire where
  toJSON row =
    object
      [ "ordinal" .= wireRowOrdinal row
      , "row_id" .= wireRowId row
      , "plan_id" .= wireRowPlanId row
      , "substrate" .= wireRowSubstrate row
      , "experiment_hash" .= wireRowExperimentHash row
      , "admitted_manifest_sha256" .= wireRowManifestSha row
      , "inference_manifest_sha256" .= wireRowInferenceManifestSha row
      , "checkpoint_scope_sha256" .= wireRowCheckpointScopeSha row
      , "executable_sha256" .= wireRowExecutableSha row
      , "invocation_sha256" .= wireRowInvocationSha row
      , "contract_sha256" .= wireRowContractSha row
      , "completion_journal_sha256" .= wireRowJournalSha row
      , "measured_sha256" .= wireRowMeasuredSha row
      , "device_witness" .= wireRowDeviceWitness row
      , "completed_training" .= wireRowCompletedTraining row
      , "supervised_qualification_receipt" .= wireRowQualificationReceipt row
      , "native_qualification_bundle" .= wireRowNativeBundle row
      , "status" .= wireRowStatus row
      ]

instance FromJSON ProductLaneJournalRowWire where
  parseJSON =
    withObject "ProductLaneJournalRow" $ \record -> do
      requireExactFields
        "ProductLaneJournalRow"
        [ "ordinal"
        , "row_id"
        , "plan_id"
        , "substrate"
        , "experiment_hash"
        , "admitted_manifest_sha256"
        , "inference_manifest_sha256"
        , "checkpoint_scope_sha256"
        , "executable_sha256"
        , "invocation_sha256"
        , "contract_sha256"
        , "completion_journal_sha256"
        , "measured_sha256"
        , "device_witness"
        , "completed_training"
        , "supervised_qualification_receipt"
        , "native_qualification_bundle"
        , "status"
        ]
        record
      ProductLaneJournalRowWire
        <$> record .: "ordinal"
        <*> record .: "row_id"
        <*> record .: "plan_id"
        <*> record .: "substrate"
        <*> record .: "experiment_hash"
        <*> record .: "admitted_manifest_sha256"
        <*> record .: "inference_manifest_sha256"
        <*> record .: "checkpoint_scope_sha256"
        <*> record .: "executable_sha256"
        <*> record .: "invocation_sha256"
        <*> record .: "contract_sha256"
        <*> record .: "completion_journal_sha256"
        <*> record .: "measured_sha256"
        <*> record .: "device_witness"
        <*> record .: "completed_training"
        <*> record .: "supervised_qualification_receipt"
        <*> record .: "native_qualification_bundle"
        <*> record .: "status"

requireExactFields :: String -> [Text] -> Object -> Parser ()
requireExactFields label expected record =
  unless (null unexpected) $
    fail
      ( label
          <> " contains unknown fields: "
          <> Text.unpack (Text.intercalate ", " unexpected)
      )
 where
  expectedKeys = fmap AesonKey.fromText expected
  unexpected =
    List.sort
      [ AesonKey.toText key
      | key <- AesonKeyMap.keys record
      , key `notElem` expectedKeys
      ]

buildProductLaneJournal
  :: ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> Either (NonEmpty ProductLaneJournalError) IssuedProductLaneJournal
buildProductLaneJournal batch authenticated = do
  let report = ProductScenarioJournal.authenticatedProductScenarioReport authenticated
      evidence = Report.completedProductScenarioReportEntries report
      projections = ProductMatrix.productProjectionBatchProjections batch
      sourceErrors = validateAuthenticatedSource batch authenticated evidence
  case NonEmpty.nonEmpty sourceErrors of
    Just errors -> Left errors
    Nothing -> do
      nativePlans <-
        mapLeft
          (:| [])
          ( traverse
              nativePlan
              [ actual
              | entry <- evidence
              , Just actual <- [Report.completedProductScenarioRetainedNativeQualification entry]
              ]
          )
      nativeObjects <- mapLeft (:| []) (traverse nativeObject nativePlans)
      rows <-
        case traverse (buildRow nativePlans) (zip3 [0 ..] projections evidence) of
          Left err -> Left (err :| [])
          Right value -> Right value
      let journal =
            ProductLaneJournalWire
              { wireFormat = productLaneJournalFormat
              , wireVersion = productLaneJournalWireVersion
              , wireRunId =
                  ProductScenarioJournal.authenticatedProductScenarioReportRunId
                    authenticated
              , wireSubstrate =
                  renderSubstrate
                    (ProductMatrix.productProjectionBatchSubstrate batch)
              , wireSourceJournalSha =
                  ProductScenarioJournal.authenticatedProductScenarioReportSourceDigest
                    authenticated
              , wireRows = rows
              }
      let objects =
            [ ( Receipt.qualificationReferenceObjectKey
                  (Receipt.supervisedQualificationPublicationReference publication)
              , Qualification.encodeSupervisedQualification
                  ( Qualification.qualifiedSupervisedCohortData
                      (Receipt.supervisedQualificationPublicationData publication)
                  )
              )
            | completed <- evidence
            , Just publication <- [Report.completedProductScenarioQualification completed]
            ]
      case validateWire batch journal of
        [] -> Right (IssuedProductLaneJournal journal objects nativeObjects (fmap snd nativePlans))
        failure : failures -> Left (failure :| failures)
 where
  nativePlan actual = do
    plan <-
      mapLeft (ProductLaneJournalMalformed . Text.pack . show) (Native.makeNativeBundleWritePlan actual)
    pure
      ( NativeBinding.nativeScenarioBindingRowId
          (Native.nativeBundleBinding (Native.nativeBundleWritePlanRoot plan))
      , plan
      )
  nativeObject (_, plan) = do
    key <-
      mapLeft
        (ProductLaneJournalMalformed . Text.pack . show)
        (Native.nativeBundleReferenceObjectKey (Native.nativeBundleWritePlanReference plan))
    bytes <-
      mapLeft
        (ProductLaneJournalMalformed . Text.pack . show)
        (Native.encodeNativeBundleRootData (Native.nativeBundleWritePlanRoot plan))
    pure (key, bytes)
  nativeLine plans row = case lookup row plans of
    Nothing -> Right ""
    Just plan ->
      mapLeft
        (ProductLaneJournalMalformed . Text.pack . show)
        (Native.renderNativeBundleReferenceData (Native.nativeBundleWritePlanReference plan))
  buildRow nativePlans (ordinal, someProjection, evidence) =
    case someProjection of
      ProductMatrix.SomeProductProjection _ projection ->
        let rowId = ProductMatrix.productProjectionRowId projection
         in if Report.completedProductScenarioRowId evidence /= rowId
              then
                Left
                  ( ProductLaneJournalSourceRejected
                      (rowId <> ": authenticated report order differs from projection")
                  )
              else
                ( \nativeBundle ->
                    ProductLaneJournalRowWire
                      { wireRowOrdinal = ordinal
                      , wireRowId = rowId
                      , wireRowPlanId =
                          planIdText (Report.completedProductScenarioPlanId evidence)
                      , wireRowSubstrate =
                          renderSubstrate (Report.completedProductScenarioLane evidence)
                      , wireRowExperimentHash =
                          Report.completedProductScenarioExperimentHash evidence
                      , wireRowManifestSha =
                          Report.completedProductScenarioManifestSha evidence
                      , wireRowInferenceManifestSha =
                          Report.completedProductScenarioInferenceManifestSha evidence
                      , wireRowCheckpointScopeSha =
                          Report.completedProductScenarioCheckpointScopeDigest evidence
                      , wireRowExecutableSha =
                          Report.completedProductScenarioExecutableSha256 evidence
                      , wireRowInvocationSha =
                          Report.completedProductScenarioInvocationDigest evidence
                      , wireRowContractSha =
                          Report.completedProductScenarioContractDigest evidence
                      , wireRowJournalSha =
                          Report.completedProductScenarioJournalDigest evidence
                      , wireRowMeasuredSha =
                          Report.completedProductScenarioMeasuredDigest evidence
                      , wireRowDeviceWitness =
                          Report.renderCompletedProductScenarioExecutionProvenance evidence
                      , wireRowCompletedTraining =
                          Budget.renderCompletedTraining
                            (Report.completedProductScenarioCompletedTraining evidence)
                      , wireRowQualificationReceipt =
                          maybe
                            ""
                            Receipt.renderSupervisedQualificationPublication
                            (Report.completedProductScenarioQualification evidence)
                      , wireRowNativeBundle = nativeBundle
                      , wireRowStatus = "Passed"
                      }
                )
                  <$> nativeLine nativePlans rowId

validateAuthenticatedSource
  :: ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> [Report.CompletedProductScenarioEvidence]
  -> [ProductLaneJournalError]
validateAuthenticatedSource batch authenticated evidence =
  [ ProductLaneJournalSourceRejected
      ( "authenticated source coverage differs from projection batch: batch="
          <> showText (length batchRows)
          <> ", report="
          <> showText (length evidence)
      )
  | length batchRows /= length evidence
  ]
    <> [ ProductLaneJournalSourceRejected
           "authenticated source digest is not canonical SHA-256"
       | not
           ( isCanonicalSha256
               ( ProductScenarioJournal.authenticatedProductScenarioReportSourceDigest
                   authenticated
               )
           )
       ]
 where
  batchRows = ProductMatrix.productProjectionBatchRowIds batch

issuedProductLaneJournalBytes :: IssuedProductLaneJournal -> ByteString
issuedProductLaneJournalBytes = canonicalBytes . issuedWire

issuedProductLaneJournalSha256 :: IssuedProductLaneJournal -> Text
issuedProductLaneJournalSha256 = sha256Bytes . issuedProductLaneJournalBytes

writeProductLaneJournalAtomic
  :: FilePath
  -> ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> IO
       ( Either
           (NonEmpty ProductLaneJournalError)
           IssuedProductLaneJournal
       )
writeProductLaneJournalAtomic path batch authenticated =
  case buildProductLaneJournal batch authenticated of
    Left errors -> pure (Left errors)
    Right issued -> do
      objectsWritten <- writeIssuedQualificationObjects path issued
      case objectsWritten of
        Left failure -> pure (Left (failure :| []))
        Right () -> do
          written <- tryIO (writeAtomic path (issuedProductLaneJournalBytes issued))
          pure $ case written of
            Left exception ->
              Left
                ( ProductLaneJournalIOFailure path (Text.pack (show exception))
                    :| []
                )
            Right () -> Right issued

-- | Actual portable native admission. Pin/canonical/current coverage validation
-- precedes native file reads; the old pure entrypoint has no audit capability.
admitProductLaneJournalWithNativeBundles
  :: FilePath
  -> [(Text, ByteString)]
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> ByteString
  -> IO (Either (NonEmpty ProductLaneJournalError) AdmittedProductLaneJournal)
admitProductLaneJournalWithNativeBundles path objects expectedSha batch bytes =
  case parsePinnedNativeWire of
    Left failure -> pure (Left failure)
    Right journal -> do
      audits <-
        traverse auditRow (zip (ProductMatrix.productProjectionBatchProjections batch) (wireRows journal))
      pure
        ( sequence audits >>= \actual ->
            admitProductLaneJournalInternal (concat actual) objects expectedSha batch bytes
        )
 where
  parsePinnedNativeWire = do
    unless
      (isCanonicalSha256 expectedSha)
      (Left (ProductLaneJournalMalformed "expected lane-journal digest is not canonical SHA-256" :| []))
    unless
      (sha256Bytes bytes == expectedSha)
      (Left (ProductLaneJournalDigestMismatch expectedSha (sha256Bytes bytes) :| []))
    mapLeft (:| []) (rejectObsoleteLaneWire bytes)
    journal <-
      mapLeft
        (\detail -> ProductLaneJournalMalformed (Text.pack detail) :| [])
        (eitherDecodeStrict' bytes)
    unless (canonicalBytes journal == bytes) (Left (ProductLaneJournalNonCanonical :| []))
    case NonEmpty.nonEmpty (validateWire batch journal) of
      Just failures -> Left failures
      Nothing -> Right journal
  auditRow (ProductMatrix.SomeProductProjection _ projection, row)
    | nativeProjection projection =
        case Native.parseNativeBundleReferenceData (wireRowNativeBundle row) of
          Left failure -> pure (Left (ProductLaneJournalMalformed (Text.pack (show failure)) :| []))
          Right reference -> do
            actual <- Native.readNativeLaneBundle path expectedSha bytes reference projection
            pure
              ( case actual of
                  Left diagnostic ->
                    Left
                      ( ProductLaneJournalSourceRejected
                          ("native portable physical audit refused: " <> Text.pack (show diagnostic))
                          :| []
                      )
                  Right value -> Right [value]
              )
    | otherwise = pure (Right [])

admitProductLaneJournal
  :: Text
  -> ProductMatrix.ProductProjectionBatch
  -> ByteString
  -> Either (NonEmpty ProductLaneJournalError) AdmittedProductLaneJournal
admitProductLaneJournal = admitProductLaneJournalWithQualifications []

admitProductLaneJournalWithQualifications
  :: [(Text, ByteString)]
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> ByteString
  -> Either (NonEmpty ProductLaneJournalError) AdmittedProductLaneJournal
admitProductLaneJournalWithQualifications = admitProductLaneJournalInternal []

admitProductLaneJournalInternal
  :: [Native.NativeBundleAudit]
  -> [(Text, ByteString)]
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> ByteString
  -> Either (NonEmpty ProductLaneJournalError) AdmittedProductLaneJournal
admitProductLaneJournalInternal nativeAudits objects expectedSha batch bytes = do
  unless (isCanonicalSha256 expectedSha) $
    Left
      ( ProductLaneJournalMalformed
          "expected lane-journal digest is not canonical SHA-256"
          :| []
      )
  let actualSha = sha256Bytes bytes
  unless (actualSha == expectedSha) $
    Left (ProductLaneJournalDigestMismatch expectedSha actualSha :| [])
  mapLeft (:| []) (rejectObsoleteLaneWire bytes)
  journal <-
    case eitherDecodeStrict' bytes of
      Left detail -> Left (ProductLaneJournalMalformed (Text.pack detail) :| [])
      Right value -> Right value
  unless (canonicalBytes journal == bytes) $
    Left (ProductLaneJournalNonCanonical :| [])
  case NonEmpty.nonEmpty (validateWire batch journal) of
    Just failures -> Left failures
    Nothing -> do
      expectedKeys <- mapLeft (:| []) (productLaneJournalQualificationObjectKeys bytes)
      unless
        ( length (fmap fst objects) == length (List.nub (fmap fst objects))
            && List.sort (fmap fst objects) == List.sort expectedKeys
        )
        ( Left
            (ProductLaneJournalSourceRejected "qualification object map is missing, duplicate or foreign" :| [])
        )
      rows <-
        case traverse (admitRow batch nativeAudits expectedSha objects (wireRunId journal)) (wireRows journal) of
          Left failure -> Left (failure :| [])
          Right value -> Right value
      substrate <-
        case parseSubstrate (wireSubstrate journal) of
          Nothing ->
            Left
              ( ProductLaneJournalSourceRejected
                  ("unknown lane substrate: " <> wireSubstrate journal)
                  :| []
              )
          Just value -> Right value
      Right
        AdmittedProductLaneJournal
          { admittedWire = journal
          , admittedSubstrate = substrate
          , admittedRows = rows
          }

admitRow
  :: ProductMatrix.ProductProjectionBatch
  -> [Native.NativeBundleAudit]
  -> Text
  -> [(Text, ByteString)]
  -> Text
  -> ProductLaneJournalRowWire
  -> Either ProductLaneJournalError ProductLaneJournalRow
admitRow batch nativeAudits mainSha objects runId row = do
  completed <-
    maybe
      ( Left
          ( ProductLaneJournalSourceRejected
              (wireRowId row <> ": completed_training did not refine")
          )
      )
      Right
      (Budget.parseCompletedTraining (wireRowCompletedTraining row))
  let plan = Budget.completedTrainingPlanId completed
  lane <-
    maybe
      ( Left
          ( ProductLaneJournalSourceRejected
              (wireRowId row <> ": row substrate is unknown")
          )
      )
      Right
      (parseSubstrate (wireRowSubstrate row))
  execution <-
    case Budget.completedTrainingExecutionProvenance completed of
      Right (Just value) -> Right value
      _ ->
        Left
          ( ProductLaneJournalSourceRejected
              (wireRowId row <> ": completed_training has no execution provenance")
          )
  qualification <- admitQualificationRow batch objects row completed
  nativeAudit <- admitNativeRow batch nativeAudits mainSha objects row completed
  case (execution, nativeAudit) of
    (ArsHostLinearExecution _, Nothing) ->
      Left (ProductLaneJournalSourceRejected "host execution requires an actually audited native bundle")
    _ -> pure ()
  case validateCompletedRow runId row plan lane execution completed of
    [] ->
      Right
        ProductLaneJournalRow
          { admittedRowWire = row
          , admittedRowPlan = plan
          , admittedRowLane = lane
          , admittedRowCheckpoint =
              RetainedCheckpointIdentity
                (wireRowExperimentHash row)
                (wireRowManifestSha row)
          , admittedRowExecution = execution
          , admittedRowQualification = qualification
          , admittedRowNativeAudit = nativeAudit
          , admittedRowCompleted = completed
          }
    failure : _ -> Left (ProductLaneJournalSourceRejected failure)

validateCompletedRow
  :: Text
  -> ProductLaneJournalRowWire
  -> PlanId
  -> Substrate
  -> ExecutionProvenance ArsReference.ArsHostReference
  -> CompletedTraining
  -> [Text]
validateCompletedRow runId row plan lane execution completed =
  [ label <> " differs from the refined completed_training value"
  | (label, agrees) <-
      [ ("plan_id", wireRowPlanId row == planIdText plan)
      ,
        ( "measured_sha256"
        , wireRowMeasuredSha row == Report.canonicalCompletedTrainingDigest completed
        )
      ,
        ( "completed_training"
        , wireRowCompletedTraining row == Budget.renderCompletedTraining completed
        )
      ,
        ( "device_witness"
        , renderExecution execution == wireRowDeviceWitness row
        )
      , ("execution provenance substrate", executionLane execution == lane)
      ,
        ( "inference_manifest_sha256"
        , wireRowInferenceManifestSha row == wireRowManifestSha row
        )
      ]
  , not agrees
  ]
    <> case Budget.completedTrainingProductScenarioInvocation completed of
      Nothing -> [wireRowId row <> ": completed_training has no ProductScenario invocation"]
      Just invocation ->
        [ label <> " differs from the refined ProductScenario invocation"
        | (label, agrees) <-
            [ ("run_id", Budget.productScenarioInvocationRunId invocation == runId)
            , ("row_id", Budget.productScenarioInvocationRowId invocation == wireRowId row)
            ,
              ( "plan_id"
              , planIdText (Budget.productScenarioInvocationPlanId invocation)
                  == wireRowPlanId row
              )
            ,
              ( "substrate"
              , Budget.productScenarioInvocationSubstrate invocation == lane
              )
            ,
              ( "checkpoint_scope_sha256"
              , Budget.productScenarioInvocationCheckpointScopeDigest invocation
                  == wireRowCheckpointScopeSha row
              )
            ,
              ( "executable_sha256"
              , Budget.productScenarioInvocationExecutableSha256 invocation
                  == wireRowExecutableSha row
              )
            ,
              ( "invocation_sha256"
              , Budget.productScenarioInvocationDigest invocation
                  == wireRowInvocationSha row
              )
            ]
        , not agrees
        ]

nativeProjection :: ProductMatrix.ProductProjection kind -> Bool
nativeProjection projection =
  ProductMatrix.productProjectionFamily projection
    `elem` [ProductMatrix.ReinforcementLearning, ProductMatrix.AlphaZero]

admitNativeRow
  :: ProductMatrix.ProductProjectionBatch
  -> [Native.NativeBundleAudit]
  -> Text
  -> [(Text, ByteString)]
  -> ProductLaneJournalRowWire
  -> CompletedTraining
  -> Either ProductLaneJournalError (Maybe Native.NativeBundleAudit)
admitNativeRow batch audits mainSha objects row completed =
  case [ some
       | some@(ProductMatrix.SomeProductProjection _ projection) <-
           ProductMatrix.productProjectionBatchProjections batch
       , ProductMatrix.productProjectionRowId projection == wireRowId row
       ] of
    [ProductMatrix.SomeProductProjection _ projection]
      | nativeProjection projection -> do
          reference <-
            mapLeft
              (ProductLaneJournalMalformed . Text.pack . show)
              (Native.parseNativeBundleReferenceData (wireRowNativeBundle row))
          actual <- case filter
            ( (== wireRowId row)
                . NativeBinding.nativeScenarioBindingRowId
                . Native.nativeBundleBinding
                . Native.nativeBundleAuditRoot
            )
            audits of
            [value] -> Right value
            _ -> Left (ProductLaneJournalSourceRejected "native row has no unique actual portable FILE audit")
          key <-
            mapLeft
              (ProductLaneJournalMalformed . Text.pack . show)
              (Native.nativeBundleReferenceObjectKey reference)
          actualBytes <-
            mapLeft
              (ProductLaneJournalMalformed . Text.pack . show)
              (Native.encodeNativeBundleRootData (Native.nativeBundleAuditRoot actual))
          unless
            (lookup key objects == Just actualBytes)
            ( Left
                (ProductLaneJournalSourceRejected "native captured root object map differs from actual FILE audit")
            )
          let binding = Native.nativeBundleBinding (Native.nativeBundleAuditRoot actual)
              agrees =
                Native.nativeBundleAuditMainSha256 actual == mainSha
                  && Native.nativeBundleAuditReference actual == reference
                  && Budget.encodeCompletedTraining (Native.nativeBundleAuditCompleted actual)
                    == Budget.encodeCompletedTraining completed
                  && NativeBinding.nativeScenarioBindingPlanId binding == wireRowPlanId row
                  && NativeBinding.nativeScenarioBindingSubstrate binding == wireRowSubstrate row
                  && NativeBinding.nativeScenarioBindingExperimentHash binding == wireRowExperimentHash row
                  && NativeBinding.nativeScenarioBindingManifestSha256 binding == wireRowManifestSha row
                  && NativeBinding.nativeScenarioBindingInferenceManifestSha256 binding
                    == wireRowInferenceManifestSha row
                  && NativeBinding.nativeScenarioBindingCheckpointScopeSha256 binding == wireRowCheckpointScopeSha row
                  && NativeBinding.nativeScenarioBindingExecutableSha256 binding == wireRowExecutableSha row
                  && NativeBinding.nativeScenarioBindingInvocationDigest binding == wireRowInvocationSha row
                  && NativeBinding.nativeScenarioBindingContractSha256 binding == wireRowContractSha row
                  && NativeBinding.nativeScenarioBindingExecutionJournalSha256 binding == wireRowJournalSha row
          unless
            agrees
            (Left (ProductLaneJournalSourceRejected "native portable audit differs from this exact row"))
          Right (Just actual)
      | Text.null (wireRowNativeBundle row) -> Right Nothing
      | otherwise ->
          Left (ProductLaneJournalSourceRejected "non-native row carries a native portable bundle")
    _ -> Left (ProductLaneJournalSourceRejected "native portable row has no unique current projection")
validateWire
  :: ProductMatrix.ProductProjectionBatch
  -> ProductLaneJournalWire
  -> [ProductLaneJournalError]
validateWire batch journal =
  fmap ProductLaneJournalSourceRejected (aggregateFailures <> coverageFailures)
    <> concat (zipWith validateProjected projections rows)
 where
  rows = wireRows journal
  projections = ProductMatrix.productProjectionBatchProjections batch
  expectedLane = ProductMatrix.productProjectionBatchSubstrate batch
  expectedRowIds = ProductMatrix.productProjectionBatchRowIds batch
  observedRowIds = fmap wireRowId rows
  aggregateFailures =
    [ "lane-journal format mismatch"
    | wireFormat journal /= productLaneJournalFormat
    ]
      <> [ "lane-journal version mismatch"
         | wireVersion journal /= productLaneJournalWireVersion
         ]
      <> [ "lane-journal run_id is empty, untrimmed, or contains control characters"
         | invalidText (wireRunId journal)
         ]
      <> [ "lane-journal substrate differs from the projection batch"
         | wireSubstrate journal /= renderSubstrate expectedLane
         ]
      <> [ "lane-journal source digest is not canonical SHA-256"
         | not (isCanonicalSha256 (wireSourceJournalSha journal))
         ]
  coverageFailures =
    [ "lane-journal row order or coverage differs from the projection batch"
    | observedRowIds /= expectedRowIds
    ]
      <> [ "lane-journal row ordinals are not contiguous from zero"
         | fmap wireRowOrdinal rows /= expectedOrdinals
         ]
  expectedOrdinals
    | null rows = []
    | otherwise = [0 .. fromIntegral (length rows - 1)]
  validateProjected someProjection row =
    case someProjection of
      ProductMatrix.SomeProductProjection _ projection ->
        let rowId = ProductMatrix.productProjectionRowId projection
            digestFields =
              [ ("admitted_manifest_sha256", wireRowManifestSha row)
              , ("inference_manifest_sha256", wireRowInferenceManifestSha row)
              , ("checkpoint_scope_sha256", wireRowCheckpointScopeSha row)
              , ("executable_sha256", wireRowExecutableSha row)
              , ("invocation_sha256", wireRowInvocationSha row)
              , ("contract_sha256", wireRowContractSha row)
              , ("completion_journal_sha256", wireRowJournalSha row)
              , ("measured_sha256", wireRowMeasuredSha row)
              ]
         in fmap
              ProductLaneJournalSourceRejected
              ( [ rowId <> ": plan_id differs from the current projection"
                | wireRowPlanId row
                    /= planIdText (ProductMatrix.productProjectionPlanId projection)
                ]
                  <> [ rowId <> ": substrate differs from the current projection"
                     | wireRowSubstrate row
                         /= renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
                     ]
                  <> [ rowId <> ": experiment_hash differs from the current projection"
                     | wireRowExperimentHash row
                         /= ProductMatrix.productProjectionExperimentHash projection
                     ]
              )
              <> nativeWireFailures projection row
              <> either
                (: [])
                (const [])
                (validateProductLaneContract projection (wireRowContractSha row))
              <> fmap
                ProductLaneJournalSourceRejected
                ( [rowId <> ": status is not Passed" | wireRowStatus row /= "Passed"]
                    <> [ rowId <> ": device_witness is empty or untrimmed"
                       | invalidText (wireRowDeviceWitness row)
                       ]
                    <> [ rowId <> ": " <> label <> " is not canonical SHA-256"
                       | (label, value) <- digestFields
                       , not (isCanonicalSha256 value)
                       ]
                )

nativeWireFailures
  :: ProductMatrix.ProductProjection kind -> ProductLaneJournalRowWire -> [ProductLaneJournalError]
nativeWireFailures projection row
  | nativeProjection projection =
      case Native.parseNativeBundleReferenceData (wireRowNativeBundle row) of
        Left failure -> [ProductLaneJournalMalformed (Text.pack (show failure))]
        Right _ -> []
  | Text.null (wireRowNativeBundle row) = []
  | otherwise = [ProductLaneJournalSourceRejected "non-native row carries a native portable bundle"]

-- | Compare one untrusted contract digest with its current opaque projection.
-- This ordinary structural check grants no journal, source authentication,
-- checkpoint admission or model authority. The current-wire admission path uses
-- the same predicate after its independent format, coverage and identity checks.
validateProductLaneContract
  :: ProductMatrix.ProductProjection kind
  -> Text
  -> Either ProductLaneJournalError ()
validateProductLaneContract projection observed =
  if observed == current
    then Right ()
    else Left (ProductLaneJournalContractStale rowId current observed)
 where
  rowId = ProductMatrix.productProjectionRowId projection
  current = Report.productScenarioProjectionContractDigest projection

admittedProductLaneJournalRows
  :: AdmittedProductLaneJournal -> [ProductLaneJournalRow]
admittedProductLaneJournalRows = admittedRows

admittedProductLaneJournalRunId :: AdmittedProductLaneJournal -> Text
admittedProductLaneJournalRunId = wireRunId . admittedWire

admittedProductLaneJournalSourceDigest :: AdmittedProductLaneJournal -> Text
admittedProductLaneJournalSourceDigest = wireSourceJournalSha . admittedWire

admittedProductLaneJournalSubstrate :: AdmittedProductLaneJournal -> Substrate
admittedProductLaneJournalSubstrate = admittedSubstrate

productLaneJournalRowRowId :: ProductLaneJournalRow -> Text
productLaneJournalRowRowId = wireRowId . admittedRowWire

productLaneJournalRowPlanId :: ProductLaneJournalRow -> PlanId
productLaneJournalRowPlanId = admittedRowPlan

productLaneJournalRowSubstrate :: ProductLaneJournalRow -> Substrate
productLaneJournalRowSubstrate = admittedRowLane

productLaneJournalRowManifestSha :: ProductLaneJournalRow -> Text
productLaneJournalRowManifestSha row =
  case admittedRowCheckpoint row of
    RetainedCheckpointIdentity _experimentHash manifestSha -> manifestSha

productLaneJournalRowExperimentHash :: ProductLaneJournalRow -> Text
productLaneJournalRowExperimentHash row =
  case admittedRowCheckpoint row of
    RetainedCheckpointIdentity experimentHash _manifestSha -> experimentHash

productLaneJournalRowMeasuredDigest :: ProductLaneJournalRow -> Text
productLaneJournalRowMeasuredDigest = wireRowMeasuredSha . admittedRowWire

productLaneJournalRowContractDigest :: ProductLaneJournalRow -> Text
productLaneJournalRowContractDigest = wireRowContractSha . admittedRowWire

productLaneJournalRowJournalDigest :: ProductLaneJournalRow -> Text
productLaneJournalRowJournalDigest = wireRowJournalSha . admittedRowWire

productLaneJournalRowDeviceWitness
  :: ProductLaneJournalRow -> Maybe DeviceWitness.DeviceExecutionWitness
productLaneJournalRowDeviceWitness row = case admittedRowExecution row of
  NeuralDeviceExecution value -> Just value
  ArsHostLinearExecution _ -> Nothing

productLaneJournalRowExecutionProvenance
  :: ProductLaneJournalRow -> ExecutionProvenance ArsReference.ArsHostReference
productLaneJournalRowExecutionProvenance = admittedRowExecution

renderProductLaneJournalRowExecutionProvenance :: ProductLaneJournalRow -> Text
renderProductLaneJournalRowExecutionProvenance = renderExecution . admittedRowExecution

renderExecution :: ExecutionProvenance ArsReference.ArsHostReference -> Text
renderExecution (NeuralDeviceExecution value) = DeviceWitness.renderDeviceExecutionWitness value
renderExecution (ArsHostLinearExecution value) = "ars-host-linear-v1:" <> ArsReference.arsHostReferenceContentSha256 value

executionLane :: ExecutionProvenance ArsReference.ArsHostReference -> Substrate
executionLane (NeuralDeviceExecution value) = DeviceWitness.witnessSubstrate value
executionLane (ArsHostLinearExecution value) = ArsReference.arsHostReferenceLane value

productLaneJournalRowCompletedTraining
  :: ProductLaneJournalRow -> CompletedTraining
productLaneJournalRowCompletedTraining = admittedRowCompleted

canonicalBytes :: ProductLaneJournalWire -> ByteString
canonicalBytes journal = LazyByteString.toStrict (encode journal) <> "\n"

isCanonicalSha256 :: Text -> Bool
isCanonicalSha256 value =
  Text.length value == 64
    && Text.all (`elem` ("0123456789abcdef" :: String)) value

invalidText :: Text -> Bool
invalidText value =
  Text.null value || Text.strip value /= value || Text.any isControl value

sha256Bytes :: ByteString -> Text
sha256Bytes = Text.pack . concatMap hexOctet . ByteString.unpack . SHA256.hash
 where
  hexOctet :: Word8 -> String
  hexOctet byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

showText :: (Show value) => value -> Text
showText = Text.pack . show

tryIO :: IO value -> IO (Either IOException value)
tryIO = try

writeAtomic :: FilePath -> ByteString -> IO ()
writeAtomic path bytes = do
  createDirectoryIfMissing True (takeDirectory path)
  (temporaryPath, handle) <- openBinaryTempFile (takeDirectory path) (takeFileName path <> ".tmp")
  let cleanup = do
        ignoreIOException (hClose handle)
        ignoreIOException (removeFile temporaryPath)
  (ByteString.hPut handle bytes >> hFlush handle >> hClose handle >> renameFile temporaryPath path)
    `onException` cleanup

ignoreIOException :: IO value -> IO ()
ignoreIOException action = do
  _ <- tryIO action
  pure ()

issuedProductLaneJournalQualificationObjects :: IssuedProductLaneJournal -> [(Text, ByteString)]
issuedProductLaneJournalQualificationObjects issued =
  issuedQualifications issued <> issuedNativeQualifications issued

writeIssuedQualificationObjects
  :: FilePath -> IssuedProductLaneJournal -> IO (Either ProductLaneJournalError ())
writeIssuedQualificationObjects path issued = case issuedNativePlans issued of
  [] -> writeQualificationObjects path (issuedQualifications issued)
  plans -> do
    prepared <- Native.prepareNativeBundleDirectory path
    case prepared of
      Left diagnostic -> pure (Left (ProductLaneJournalIOFailure path (Text.pack (show diagnostic))))
      Right () -> do
        supervised <- writeQualificationObjects path (issuedQualifications issued)
        case supervised of
          Left failure -> pure (Left failure)
          Right () -> writePlans plans
 where
  writePlans [] = pure (Right ())
  writePlans (plan : rest) = do
    actual <- Native.writeNativeBundleObjects path plan
    case actual of
      Left diagnostic -> pure (Left (ProductLaneJournalIOFailure path (Text.pack (show diagnostic))))
      Right () -> writePlans rest

-- | Parse only canonical current wire bytes before the IO loader discovers
-- filenames. The caller still verifies its pinned main digest before IO and
-- admission repeats both checks. No untrusted path is returned.
productLaneJournalQualificationObjectKeys :: ByteString -> Either ProductLaneJournalError [Text]
productLaneJournalQualificationObjectKeys bytes = do
  rejectObsoleteLaneWire bytes
  journal <- mapLeft (ProductLaneJournalMalformed . Text.pack) (eitherDecodeStrict' bytes)
  unless (canonicalBytes journal == bytes) (Left ProductLaneJournalNonCanonical)
  unless
    ( wireFormat journal == productLaneJournalFormat
        && wireVersion journal == productLaneJournalWireVersion
    )
    (Left (ProductLaneJournalMalformed "unsupported qualification-bearing lane wire"))
  references <-
    traverse
      parseReference
      [ wireRowQualificationReceipt row
      | row <- wireRows journal
      , not (Text.null (wireRowQualificationReceipt row))
      ]
  nativeReferences <-
    traverse
      (mapLeft (ProductLaneJournalMalformed . Text.pack . show) . Native.parseNativeBundleReferenceData)
      [wireRowNativeBundle row | row <- wireRows journal, not (Text.null (wireRowNativeBundle row))]
  nativeKeys <-
    traverse
      (mapLeft (ProductLaneJournalMalformed . Text.pack . show) . Native.nativeBundleReferenceObjectKey)
      nativeReferences
  let keys = fmap Receipt.qualificationReferenceObjectKey references <> nativeKeys
  unless
    (length keys == length (List.nub keys))
    (Left (ProductLaneJournalMalformed "duplicate detached qualification object keys"))
  Right keys
 where
  parseReference = mapLeft ProductLaneJournalMalformed . Receipt.parseSupervisedQualificationReference

admitQualificationRow
  :: ProductMatrix.ProductProjectionBatch
  -> [(Text, ByteString)]
  -> ProductLaneJournalRowWire
  -> CompletedTraining
  -> Either ProductLaneJournalError (Maybe Receipt.RetainedSupervisedQualification)
admitQualificationRow batch objects row completed =
  case [ projection
       | projection@(ProductMatrix.SomeProductProjection _ value) <-
           ProductMatrix.productProjectionBatchProjections batch
       , ProductMatrix.productProjectionRowId value == wireRowId row
       ] of
    [ProductMatrix.SomeProductProjection Plan.SupervisedTrainingWitness projection] -> do
      reference <-
        mapFailure (Receipt.parseSupervisedQualificationReference (wireRowQualificationReceipt row))
      cohort <- mapFailure (Cohort.mkSupervisedCohortPlan projection)
      bytes <-
        maybe
          ( Left
              (ProductLaneJournalSourceRejected "qualification artifact is absent from the explicit object map")
          )
          Right
          (lookup (Receipt.qualificationReferenceObjectKey reference) objects)
      proof <-
        mapFailure
          ( Receipt.validateRetainedSupervisedQualification
              cohort
              reference
              bytes
              (wireRowManifestSha row)
              (wireRowExecutableSha row)
              (wireRowInvocationSha row)
              completed
          )
      Right (Just proof)
    [ProductMatrix.SomeProductProjection _ _] ->
      if Text.null (wireRowQualificationReceipt row)
        then Right Nothing
        else
          Left (ProductLaneJournalSourceRejected "non-supervised lane row carries supervised qualification")
    _ ->
      Left
        (ProductLaneJournalSourceRejected "qualification row does not have exactly one projected owner")
 where
  mapFailure = mapLeft ProductLaneJournalSourceRejected

-- | Content-addressed binary objects are created before the atomic main
-- journal. Existing bytes must agree; an interrupted write cannot leave a
-- main journal that points at absent or replaced qualification data.
writeQualificationObjects
  :: FilePath -> [(Text, ByteString)] -> IO (Either ProductLaneJournalError ())
writeQualificationObjects journalPath = go
 where
  go [] = pure (Right ())
  go ((key, bytes) : rest) = do
    let sha = sha256Bytes bytes
        filename = Text.unpack sha <> ".cbor"
        directory = journalPath <> ".qualifications"
    if not (Text.isSuffixOf ("/" <> sha <> ".cbor") key)
      then
        pure (Left (ProductLaneJournalMalformed "qualification object key differs from exact payload hash"))
      else do
        written <-
          Store.writeObjectIfAbsent directory (Text.pack filename) (LazyByteString.fromStrict bytes)
        case written of
          Left failure -> pure (Left (ProductLaneJournalIOFailure (directory </> filename) (Text.pack (show failure))))
          Right _ -> go rest

-- | An explicitly historical wire cannot establish the new contract. Preserve
-- that typed obsolescence independently of row parsing; no old bytes are
-- admitted, rewritten, or falsely described as corrupt by this classification.
rejectObsoleteLaneWire :: ByteString -> Either ProductLaneJournalError ()
rejectObsoleteLaneWire bytes =
  case (eitherDecodeStrict' bytes :: Either String Value) of
    Right (Object record) -> case parseEither (\value -> (,) <$> value .: "format" <*> value .: "version") record of
      Right (format, version)
        | format == productLaneJournalFormat && elem version ([1, 2] :: [Word64]) ->
            Left (ProductLaneJournalWireStale productLaneJournalWireVersion version)
      _ -> Right ()
    _ -> Right ()

-- Tuning has no original code-source field in the historical wire. It remains
-- fully admitted/current-contract checked but is outside either training review.
-- Missing historical review identity stays Nothing, never inferred from peers.
admittedProductLaneJournalReviewBindings
  :: AdmittedProductLaneJournal
  -> [(Text, Maybe Source.SourceStamp, Maybe (Text, Text, Text), Maybe (Text, Text, Text))]
admittedProductLaneJournalReviewBindings = map binding . admittedRows
 where
  binding row = case (admittedRowQualification row, admittedRowNativeAudit row) of
    (Just supervised, Nothing) ->
      ( wireRowId (admittedRowWire row)
      , Just (Receipt.retainedSupervisedQualificationSource supervised)
      , Review.criterionReviewIdentityTuple
          <$> Receipt.retainedSupervisedQualificationReviewIdentity supervised
      , Nothing
      )
    (Nothing, Just native) ->
      let receipt = Native.nativeBundleReceipt (Native.nativeBundleAuditRoot native)
       in ( wireRowId (admittedRowWire row)
          , Just (Parent.nativeParentRequestSource (NativeReceipt.nativeScenarioReceiptRequest receipt))
          , Nothing
          , Review.criterionReviewIdentityTuple <$> NativeReceipt.nativeScenarioReceiptCriterionReview receipt
          )
    _ -> (wireRowId (admittedRowWire row), Nothing, Nothing, Nothing)
