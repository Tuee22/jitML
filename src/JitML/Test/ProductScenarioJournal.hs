{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Cross-process persistence for completed ProductRow scenarios.
--
-- The writer accepts only the opaque aggregate minted by
-- 'Report.projectCompletedProductScenarioReport'.  The reader treats the JSON
-- as an untrusted receipt: it checks the exact current run, checkpoint scope,
-- substrate, ordered projection batch, row contracts, and execution receipts
-- before re-admitting every immutable checkpoint address through
-- 'Report.admitAddressedProductScenarioCompletion'.  Only that scope-bound
-- completion can cross back into the opaque report types.
module JitML.Test.ProductScenarioJournal
  ( AuthenticatedProductScenarioReport
  , ProductScenarioAuthorizationError (..)
  , ProductScenarioJournalError (..)
  , ProductScenarioJournalKey
  , authenticatedProductScenarioReport
  , authenticatedProductScenarioReportRunId
  , authenticatedProductScenarioReportSourceDigest
  , generateProductScenarioJournalKey
  , parseProductScenarioJournalKey
  , productScenarioJournalWireVersion
  , readAuthenticatedProductScenarioJournal
  , readProductScenarioJournal
  , renderProductScenarioJournalKey
  , writeProductScenarioJournalAtomic
  )
where

import Control.Exception (IOException, onException, try)
import Control.Monad (unless)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (..)
  , ToJSON (..)
  , eitherDecode
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types (Object, Parser)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isControl, ord)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , removeFile
  , renameFile
  )
import System.FilePath (isAbsolute, normalise, takeDirectory, takeFileName)
import System.IO (Handle, hClose, hFlush, openBinaryTempFile)
import System.IO.Error (isDoesNotExistError)

import JitML.Plan.Plan (planIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Test.ProductScenarioAuthorization
  ( ProductScenarioAuthorizationError (..)
  , ProductScenarioJournalKey
  , generateProductScenarioJournalKey
  , parseProductScenarioJournalKey
  , renderProductScenarioJournalKey
  )
import JitML.Test.ProductScenarioAuthorization qualified as Authorization
import JitML.Test.Report qualified as Report

-- | An exact report paired with the opaque authentication token that admitted
-- its aggregate journal.  Keeping the constructor private prevents a plain
-- completed report from being relabelled as authenticated at later publishing
-- boundaries.
data AuthenticatedProductScenarioReport
  = AuthenticatedProductScenarioReport
      !Authorization.AuthenticatedProductScenarioJournal
      !Report.CompletedProductScenarioReport
  deriving stock (Eq, Show)

authenticatedProductScenarioReport
  :: AuthenticatedProductScenarioReport
  -> Report.CompletedProductScenarioReport
authenticatedProductScenarioReport
  (AuthenticatedProductScenarioReport _ report) = report

authenticatedProductScenarioReportRunId
  :: AuthenticatedProductScenarioReport
  -> Text
authenticatedProductScenarioReportRunId
  (AuthenticatedProductScenarioReport token _) =
    Authorization.authenticatedProductScenarioJournalRunId token

-- | SHA-256 of the exact canonical aggregate material accepted by HMAC
-- authentication.  This is the public source-journal binding; the HMAC key
-- and tag never leave the journal boundary.
authenticatedProductScenarioReportSourceDigest
  :: AuthenticatedProductScenarioReport
  -> Text
authenticatedProductScenarioReportSourceDigest
  (AuthenticatedProductScenarioReport token _) =
    Authorization.authenticatedProductScenarioJournalMaterialDigest token

-- | Version of the strict JSON shape below.  Version 3 authenticates the
-- canonical checkpoint scope, full execution receipt, executable identity,
-- and every other persisted field with a fresh per-run HMAC capability.
productScenarioJournalWireVersion :: Word64
productScenarioJournalWireVersion = 3

productScenarioJournalFormat :: Text
productScenarioJournalFormat = "jitml-product-scenario-journal"

data ProductScenarioJournalError
  = ProductScenarioJournalMissing !FilePath
  | ProductScenarioJournalIOFailure !FilePath !Text
  | ProductScenarioJournalMalformed !FilePath !Text
  | ProductScenarioJournalFormatMismatch !Text
  | ProductScenarioJournalVersionMismatch !Word64 !Word64
  | ProductScenarioJournalRunIdMismatch !Text !Text
  | ProductScenarioJournalSubstrateMismatch !Substrate !Text
  | ProductScenarioJournalBatchMismatch !Text !Text
  | ProductScenarioJournalCheckpointScopeMismatch !Text !Text
  | ProductScenarioJournalAuthenticationRejected
      !Authorization.ProductScenarioAuthorizationError
  | ProductScenarioJournalRowOrderMismatch ![Text] ![Text]
  | ProductScenarioJournalMissingRow !Text !Text
  | ProductScenarioJournalDuplicateRow !Text
  | ProductScenarioJournalOrphanRow !Text !Text
  | ProductScenarioJournalPlanMismatch !Text !Text !Text
  | ProductScenarioJournalRowSubstrateMismatch !Text !Substrate !Text
  | ProductScenarioJournalExperimentMismatch !Text !Text !Text
  | ProductScenarioJournalProjectionMismatch !Text !Text !Text
  | ProductScenarioJournalCommandMismatch !Text !Text !Text
  | ProductScenarioJournalRowRunIdMismatch !Text !Text !Text
  | ProductScenarioJournalExpectedExecutablePathInvalid !FilePath
  | ProductScenarioJournalExecutablePathInvalid !Text !FilePath
  | ProductScenarioJournalExecutablePathMismatch !Text !FilePath !FilePath
  | ProductScenarioJournalExecutableShaMismatch !Text !Text !Text
  | ProductScenarioJournalExecutionReceiptDigestMismatch !Text !Text !Text
  | ProductScenarioJournalInferenceExperimentMismatch !Text !Text !Text
  | ProductScenarioJournalInferenceManifestMismatch !Text !Text !Text
  | ProductScenarioJournalPreconditionMissing !Text
  | ProductScenarioJournalChronologyInvalid !Text !Word64 !Word64 !Word64
  | ProductScenarioJournalCompletionRejected
      !Text
      !Report.ProductScenarioCompletionError
  | ProductScenarioJournalEvidenceRejected
      !Text
      !Report.ProductScenarioEvidenceError
  | ProductScenarioJournalReportRejected
      !Report.ProductScenarioReportError
  deriving stock (Eq, Show)

-- Private wire values contain no opaque evidence constructors.  They are
-- accepted only after validation and scope-bound Store re-admission.
data ProductScenarioJournalWire = ProductScenarioJournalWire
  { wireFormat :: !Text
  , wireVersion :: !Word64
  , wireRunId :: !Text
  , wireSubstrate :: !Text
  , wireProjectionBatchSha :: !Text
  , wireCheckpointScopeSha :: !Text
  , wireRunReceiptHmacSha :: !Text
  , wireRows :: ![ProductScenarioJournalRowWire]
  }
  deriving stock (Eq, Show)

data ProductScenarioJournalRowWire = ProductScenarioJournalRowWire
  { wireRowId :: !Text
  , wireRowRunId :: !Text
  , wireRowPlanId :: !Text
  , wireRowSubstrate :: !Text
  , wireRowExecutablePath :: !FilePath
  , wireRowExecutableSha :: !Text
  , wireRowInvocationDigest :: !Text
  , wireRowExperimentHash :: !Text
  , wireRowManifestSha :: !Text
  , wireRowProjectionSha :: !Text
  , wireRowCommand :: !Text
  , wireRowContractSha :: !Text
  , wireRowExecutionJournalReceipt :: !Text
  , wireRowExecutionJournalSha :: !Text
  , wireRowInferenceExperimentHash :: !Text
  , wireRowInferenceManifestSha :: !Text
  , wireRowPreconditionRejected :: !Bool
  , wireRowPreconditionSequence :: !Word64
  , wireRowInferenceSequence :: !Word64
  , wireRowCompletionSequence :: !Word64
  }
  deriving stock (Eq, Show)

instance ToJSON ProductScenarioJournalWire where
  toJSON journal =
    object
      [ "format" .= wireFormat journal
      , "version" .= wireVersion journal
      , "run_id" .= wireRunId journal
      , "substrate" .= wireSubstrate journal
      , "projection_batch_sha256" .= wireProjectionBatchSha journal
      , "checkpoint_scope_sha256" .= wireCheckpointScopeSha journal
      , "run_receipt_hmac_sha256" .= wireRunReceiptHmacSha journal
      , "rows" .= wireRows journal
      ]

instance FromJSON ProductScenarioJournalWire where
  parseJSON =
    withObject "ProductScenarioJournal" $ \record -> do
      requireExactFields
        "ProductScenarioJournal"
        [ "format"
        , "version"
        , "run_id"
        , "substrate"
        , "projection_batch_sha256"
        , "checkpoint_scope_sha256"
        , "run_receipt_hmac_sha256"
        , "rows"
        ]
        record
      ProductScenarioJournalWire
        <$> record .: "format"
        <*> record .: "version"
        <*> record .: "run_id"
        <*> record .: "substrate"
        <*> record .: "projection_batch_sha256"
        <*> record .: "checkpoint_scope_sha256"
        <*> record .: "run_receipt_hmac_sha256"
        <*> record .: "rows"

instance ToJSON ProductScenarioJournalRowWire where
  toJSON row =
    object
      [ "row_id" .= wireRowId row
      , "run_id" .= wireRowRunId row
      , "plan_id" .= wireRowPlanId row
      , "substrate" .= wireRowSubstrate row
      , "executable_path" .= wireRowExecutablePath row
      , "executable_sha256" .= wireRowExecutableSha row
      , "invocation_digest" .= wireRowInvocationDigest row
      , "experiment_hash" .= wireRowExperimentHash row
      , "manifest_sha256" .= wireRowManifestSha row
      , "projection_sha256" .= wireRowProjectionSha row
      , "command" .= wireRowCommand row
      , "contract_sha256" .= wireRowContractSha row
      , "execution_journal_receipt" .= wireRowExecutionJournalReceipt row
      , "execution_journal_sha256" .= wireRowExecutionJournalSha row
      , "inference_experiment_hash" .= wireRowInferenceExperimentHash row
      , "inference_manifest_sha256" .= wireRowInferenceManifestSha row
      , "precondition_rejected" .= wireRowPreconditionRejected row
      , "precondition_sequence" .= wireRowPreconditionSequence row
      , "inference_sequence" .= wireRowInferenceSequence row
      , "completion_sequence" .= wireRowCompletionSequence row
      ]

instance FromJSON ProductScenarioJournalRowWire where
  parseJSON =
    withObject "ProductScenarioJournalRow" $ \record -> do
      requireExactFields
        "ProductScenarioJournalRow"
        [ "row_id"
        , "run_id"
        , "plan_id"
        , "substrate"
        , "executable_path"
        , "executable_sha256"
        , "invocation_digest"
        , "experiment_hash"
        , "manifest_sha256"
        , "projection_sha256"
        , "command"
        , "contract_sha256"
        , "execution_journal_receipt"
        , "execution_journal_sha256"
        , "inference_experiment_hash"
        , "inference_manifest_sha256"
        , "precondition_rejected"
        , "precondition_sequence"
        , "inference_sequence"
        , "completion_sequence"
        ]
        record
      ProductScenarioJournalRowWire
        <$> record .: "row_id"
        <*> record .: "run_id"
        <*> record .: "plan_id"
        <*> record .: "substrate"
        <*> record .: "executable_path"
        <*> record .: "executable_sha256"
        <*> record .: "invocation_digest"
        <*> record .: "experiment_hash"
        <*> record .: "manifest_sha256"
        <*> record .: "projection_sha256"
        <*> record .: "command"
        <*> record .: "contract_sha256"
        <*> record .: "execution_journal_receipt"
        <*> record .: "execution_journal_sha256"
        <*> record .: "inference_experiment_hash"
        <*> record .: "inference_manifest_sha256"
        <*> record .: "precondition_rejected"
        <*> record .: "precondition_sequence"
        <*> record .: "inference_sequence"
        <*> record .: "completion_sequence"

requireExactFields :: String -> [Text] -> Object -> Parser ()
requireExactFields label expected record =
  unless (null unexpected) $ fail message
 where
  expectedKeys = fmap AesonKey.fromText expected
  unexpected =
    List.sort
      [ AesonKey.toText key
      | key <- AesonKeyMap.keys record
      , key `notElem` expectedKeys
      ]
  message =
    label
      <> " contains unknown fields: "
      <> Text.unpack (Text.intercalate ", " unexpected)

-- | Persist one complete current-run aggregate with a same-directory temporary
-- file and atomic rename.  The explicit checkpoint root must be the exact
-- canonical scope already retained by every opaque evidence row.
writeProductScenarioJournalAtomic
  :: Authorization.ProductScenarioJournalKey
  -> FilePath
  -> FilePath
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> Report.CompletedProductScenarioReport
  -> IO (Either (NonEmpty ProductScenarioJournalError) ())
writeProductScenarioJournalAtomic key path checkpointRoot runId batch report = do
  canonicalRootResult <- tryIO (canonicalCheckpointRoot checkpointRoot)
  case canonicalRootResult of
    Left exception ->
      pure
        ( Left
            ( ProductScenarioJournalIOFailure
                checkpointRoot
                (Text.pack (show exception))
                :| []
            )
        )
    Right canonicalRoot -> writeAtCanonicalRoot canonicalRoot
 where
  substrate = ProductMatrix.productProjectionBatchSubstrate batch
  evidence = Report.completedProductScenarioReportEntries report

  writeAtCanonicalRoot canonicalRoot = do
    let checkpointScopeSha =
          Report.productScenarioCheckpointScopeDigest canonicalRoot
        validationErrors =
          validateRunId path runId
            <> validateEvidenceCoverage batch evidence
            <> validateEvidenceReportContract batch evidence
            <> concatMap
              ( uncurry
                  ( validateEvidenceForProjection
                      path
                      runId
                      checkpointScopeSha
                  )
              )
              (matchedEvidence batch evidence)
    case NonEmpty.nonEmpty validationErrors of
      Just errors -> pure (Left errors)
      Nothing ->
        case rowsForReport batch evidence of
          Nothing ->
            pure
              ( Left
                  ( ProductScenarioJournalMalformed
                      path
                      "validated report could not be ordered by the current projection batch"
                      :| []
                  )
              )
          Just rows -> do
            let unsignedJournal =
                  ProductScenarioJournalWire
                    { wireFormat = productScenarioJournalFormat
                    , wireVersion = productScenarioJournalWireVersion
                    , wireRunId = runId
                    , wireSubstrate = renderSubstrate substrate
                    , wireProjectionBatchSha = projectionBatchSha batch
                    , wireCheckpointScopeSha = checkpointScopeSha
                    , wireRunReceiptHmacSha = ""
                    , wireRows = rows
                    }
                journal =
                  unsignedJournal
                    { wireRunReceiptHmacSha =
                        Authorization.signProductScenarioJournal
                          key
                          (runReceiptMaterial unsignedJournal)
                    }
                payload = encode journal <> "\n"
            written <- tryIO (writeAtomic path payload)
            pure $
              case written of
                Left exception ->
                  Left
                    ( ProductScenarioJournalIOFailure
                        path
                        (Text.pack (show exception))
                        :| []
                    )
                Right () -> Right ()

-- | Read and validate the aggregate for one exact run and checkpoint scope.
-- Latest-pointer reads are intentionally absent: every row re-enters Report's
-- explicit immutable-address admission boundary.
readProductScenarioJournal
  :: Authorization.ProductScenarioJournalKey
  -> FilePath
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournalError)
           Report.CompletedProductScenarioReport
       )
readProductScenarioJournal
  key
  path
  checkpointRoot
  expectedRunId
  expectedExecutablePath
  expectedExecutableSha
  batch =
    fmap authenticatedProductScenarioReport
      <$> readAuthenticatedProductScenarioJournal
        key
        path
        checkpointRoot
        expectedRunId
        expectedExecutablePath
        expectedExecutableSha
        batch

-- | Authentication-preserving reader for consumers that must publish a
-- derivative trust artifact.  The compatibility reader above projects only
-- the completed report for older callers.
readAuthenticatedProductScenarioJournal
  :: Authorization.ProductScenarioJournalKey
  -> FilePath
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournalError)
           AuthenticatedProductScenarioReport
       )
readAuthenticatedProductScenarioJournal
  key
  path
  checkpointRoot
  expectedRunId
  expectedExecutablePath
  expectedExecutableSha
  batch = do
    canonicalRootResult <- tryIO (canonicalCheckpointRoot checkpointRoot)
    case canonicalRootResult of
      Left exception ->
        pure
          ( Left
              ( ProductScenarioJournalIOFailure
                  checkpointRoot
                  (Text.pack (show exception))
                  :| []
              )
          )
      Right canonicalRoot ->
        readProductScenarioJournalAtCanonicalRoot
          key
          path
          canonicalRoot
          expectedRunId
          expectedExecutablePath
          expectedExecutableSha
          batch

readProductScenarioJournalAtCanonicalRoot
  :: Authorization.ProductScenarioJournalKey
  -> FilePath
  -> FilePath
  -> Text
  -> FilePath
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournalError)
           AuthenticatedProductScenarioReport
       )
readProductScenarioJournalAtCanonicalRoot
  key
  path
  canonicalRoot
  expectedRunId
  expectedExecutablePath
  expectedExecutableSha
  batch = do
    let checkpointScopeSha =
          Report.productScenarioCheckpointScopeDigest canonicalRoot
    payloadResult <- tryIO (LazyByteString.readFile path)
    case payloadResult of
      Left exception
        | isDoesNotExistError exception ->
            pure (Left (ProductScenarioJournalMissing path :| []))
        | otherwise ->
            pure
              ( Left
                  ( ProductScenarioJournalIOFailure
                      path
                      (Text.pack (show exception))
                      :| []
                  )
              )
      Right payload ->
        case eitherDecode payload of
          Left detail ->
            pure
              ( Left
                  ( ProductScenarioJournalMalformed path (Text.pack detail)
                      :| []
                  )
              )
          Right journal ->
            case Authorization.authenticateProductScenarioJournal
              key
              (wireRunId journal)
              (runReceiptMaterial journal)
              (wireRunReceiptHmacSha journal) of
              Left authenticationError ->
                pure
                  ( Left
                      ( ProductScenarioJournalAuthenticationRejected
                          authenticationError
                          :| []
                      )
                  )
              Right authenticatedJournal ->
                case NonEmpty.nonEmpty
                  ( validateJournal
                      path
                      expectedRunId
                      expectedExecutablePath
                      expectedExecutableSha
                      checkpointScopeSha
                      batch
                      journal
                  ) of
                  Just errors -> pure (Left errors)
                  Nothing -> do
                    rehydrated <-
                      mapM
                        ( rehydrateProjection
                            authenticatedJournal
                            (runReceiptMaterial journal)
                            canonicalRoot
                            checkpointScopeSha
                            (wireRows journal)
                        )
                        (ProductMatrix.productProjectionBatchProjections batch)
                    let rowErrors =
                          concatMap (either NonEmpty.toList (const [])) rehydrated
                    case NonEmpty.nonEmpty rowErrors of
                      Just errors -> pure (Left errors)
                      Nothing ->
                        case traverse eitherEvidence rehydrated of
                          Nothing ->
                            pure
                              ( Left
                                  ( ProductScenarioJournalMalformed
                                      path
                                      "validated row rehydration produced no evidence"
                                      :| []
                                  )
                              )
                          Just completedEvidence ->
                            pure $
                              case Report.projectCompletedProductScenarioReport
                                batch
                                completedEvidence of
                                Left reportErrors ->
                                  Left
                                    ( fmap
                                        ProductScenarioJournalReportRejected
                                        reportErrors
                                    )
                                Right completedReport ->
                                  Right
                                    ( AuthenticatedProductScenarioReport
                                        authenticatedJournal
                                        completedReport
                                    )

eitherEvidence
  :: Either
       (NonEmpty ProductScenarioJournalError)
       Report.CompletedProductScenarioEvidence
  -> Maybe Report.CompletedProductScenarioEvidence
eitherEvidence (Left _) = Nothing
eitherEvidence (Right evidence) = Just evidence

rehydrateProjection
  :: Authorization.AuthenticatedProductScenarioJournal
  -> Text
  -> FilePath
  -> Text
  -> [ProductScenarioJournalRowWire]
  -> ProductMatrix.SomeProductProjection
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournalError)
           Report.CompletedProductScenarioEvidence
       )
rehydrateProjection
  authenticatedJournal
  aggregateMaterial
  checkpointRoot
  checkpointScopeSha
  rows
  someProjection =
    case someProjection of
      ProductMatrix.SomeProductProjection _witness projection ->
        case rowsForId rowId rows of
          [row] ->
            case Authorization.authenticateProductScenarioJournalRow
              authenticatedJournal
              aggregateMaterial
              (authenticatedEvidenceMaterial checkpointScopeSha row) of
              Left authenticationError ->
                pure
                  ( Left
                      ( ProductScenarioJournalAuthenticationRejected authenticationError
                          :| []
                      )
                  )
              Right authenticatedRow -> do
                addressedResult <-
                  Report.admitAddressedProductScenarioCompletion
                    checkpointRoot
                    projection
                    (wireRowManifestSha row)
                pure $ do
                  addressed <-
                    case addressedResult of
                      Left completionErrors ->
                        Left
                          ( fmap
                              (ProductScenarioJournalCompletionRejected rowId)
                              completionErrors
                          )
                      Right value -> Right value
                  case Report.journaledProductScenarioEvidence
                    authenticatedRow
                    projection
                    (wireRowRunId row)
                    (wireRowExecutablePath row)
                    (wireRowExecutableSha row)
                    (wireRowInvocationDigest row)
                    (wireRowExperimentHash row)
                    (wireRowManifestSha row)
                    (wireRowCommand row)
                    (wireRowContractSha row)
                    checkpointScopeSha
                    (wireRowExecutionJournalReceipt row)
                    (wireRowExecutionJournalSha row)
                    (wireRowInferenceManifestSha row)
                    (wireRowPreconditionRejected row)
                    (wireRowPreconditionSequence row)
                    (wireRowInferenceSequence row)
                    (wireRowCompletionSequence row)
                    addressed of
                    Left evidenceError ->
                      Left
                        ( ProductScenarioJournalEvidenceRejected rowId evidenceError
                            :| []
                        )
                    Right evidence -> Right evidence
          _ ->
            pure
              ( Left
                  ( ProductScenarioJournalMalformed
                      "<validated-product-scenario-journal>"
                      ("row cardinality changed during rehydration: " <> rowId)
                      :| []
                  )
              )
       where
        rowId = ProductMatrix.productProjectionRowId projection

authenticatedEvidenceMaterial
  :: Text
  -> ProductScenarioJournalRowWire
  -> Text
authenticatedEvidenceMaterial checkpointScopeSha row =
  Authorization.productScenarioJournalEvidenceMaterial
    (wireRowId row)
    (wireRowRunId row)
    (wireRowPlanId row)
    (wireRowSubstrate row)
    (wireRowExecutablePath row)
    (wireRowExecutableSha row)
    (wireRowInvocationDigest row)
    (wireRowExperimentHash row)
    (wireRowManifestSha row)
    (wireRowCommand row)
    (wireRowContractSha row)
    checkpointScopeSha
    (wireRowExecutionJournalReceipt row)
    (wireRowExecutionJournalSha row)
    (wireRowInferenceManifestSha row)
    (wireRowPreconditionRejected row)
    (wireRowPreconditionSequence row)
    (wireRowInferenceSequence row)
    (wireRowCompletionSequence row)

validateJournal
  :: FilePath
  -> Text
  -> FilePath
  -> Text
  -> Text
  -> ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournalWire
  -> [ProductScenarioJournalError]
validateJournal
  path
  expectedRunId
  expectedExecutablePath
  expectedExecutableSha
  expectedScope
  batch
  journal =
    validateRunId path expectedRunId
      <> validateExpectedExecutableIdentity
        path
        expectedExecutablePath
        expectedExecutableSha
      <> validateRunId path (wireRunId journal)
      <> [ ProductScenarioJournalFormatMismatch (wireFormat journal)
         | wireFormat journal /= productScenarioJournalFormat
         ]
      <> [ ProductScenarioJournalVersionMismatch
             productScenarioJournalWireVersion
             (wireVersion journal)
         | wireVersion journal /= productScenarioJournalWireVersion
         ]
      <> [ ProductScenarioJournalRunIdMismatch expectedRunId (wireRunId journal)
         | wireRunId journal /= expectedRunId
         ]
      <> validateAggregateSubstrate path batch (wireSubstrate journal)
      <> validateDigest path "projection_batch_sha256" Nothing (wireProjectionBatchSha journal)
      <> [ ProductScenarioJournalBatchMismatch
             (projectionBatchSha batch)
             (wireProjectionBatchSha journal)
         | canonicalSha256 (wireProjectionBatchSha journal)
         , wireProjectionBatchSha journal /= projectionBatchSha batch
         ]
      <> validateDigest path "checkpoint_scope_sha256" Nothing (wireCheckpointScopeSha journal)
      <> [ ProductScenarioJournalCheckpointScopeMismatch
             expectedScope
             (wireCheckpointScopeSha journal)
         | canonicalSha256 (wireCheckpointScopeSha journal)
         , wireCheckpointScopeSha journal /= expectedScope
         ]
      <> concatMap (validateWireRowShape path) (wireRows journal)
      <> concatMap
        (validateWireExpectedExecutable expectedExecutablePath expectedExecutableSha)
        (wireRows journal)
      <> validateWireCoverage batch (wireRows journal)
      <> concatMap
        (uncurry (validateWireRow expectedRunId))
        (matchedRows batch (wireRows journal))

validateAggregateSubstrate
  :: FilePath
  -> ProductMatrix.ProductProjectionBatch
  -> Text
  -> [ProductScenarioJournalError]
validateAggregateSubstrate path batch observed =
  case parseSubstrate observed of
    Nothing ->
      [ ProductScenarioJournalMalformed
          path
          ("invalid substrate: " <> observed)
      ]
    Just parsed
      | parsed == expected -> []
      | otherwise -> [ProductScenarioJournalSubstrateMismatch expected observed]
 where
  expected = ProductMatrix.productProjectionBatchSubstrate batch

validateWireCoverage
  :: ProductMatrix.ProductProjectionBatch
  -> [ProductScenarioJournalRowWire]
  -> [ProductScenarioJournalError]
validateWireCoverage batch rows =
  missingErrors <> duplicateErrors <> orphanErrors <> orderErrors
 where
  expected = expectedProjectionIdentities batch
  expectedIds = fmap fst expected
  observedIds = fmap wireRowId rows
  missingErrors =
    [ ProductScenarioJournalMissingRow rowId planId
    | (rowId, planId) <- expected
    , rowId `notElem` observedIds
    ]
  duplicateErrors =
    [ ProductScenarioJournalDuplicateRow rowId
    | rowId <- repeatedTexts observedIds
    ]
  orphanErrors =
    [ ProductScenarioJournalOrphanRow (wireRowId row) (wireRowPlanId row)
    | row <- rows
    , wireRowId row `notElem` expectedIds
    ]
  orderErrors =
    [ ProductScenarioJournalRowOrderMismatch expectedIds observedIds
    | observedIds /= expectedIds
    ]

validateWireRow
  :: Text
  -> ProductMatrix.SomeProductProjection
  -> ProductScenarioJournalRowWire
  -> [ProductScenarioJournalError]
validateWireRow
  expectedRunId
  someProjection
  row =
    case someProjection of
      ProductMatrix.SomeProductProjection _witness projection ->
        [ ProductScenarioJournalPlanMismatch
            rowId
            expectedPlanId
            (wireRowPlanId row)
        | canonicalSha256 (wireRowPlanId row)
        , wireRowPlanId row /= expectedPlanId
        ]
          <> [ ProductScenarioJournalRowRunIdMismatch
                 rowId
                 expectedRunId
                 (wireRowRunId row)
             | wireRowRunId row /= expectedRunId
             ]
          <> validateRowSubstrateMismatch rowId expectedSubstrate (wireRowSubstrate row)
          <> [ ProductScenarioJournalExperimentMismatch
                 rowId
                 expectedExperiment
                 (wireRowExperimentHash row)
             | wireRowExperimentHash row /= expectedExperiment
             ]
          <> [ ProductScenarioJournalProjectionMismatch
                 rowId
                 expectedProjectionSha
                 (wireRowProjectionSha row)
             | canonicalSha256 (wireRowProjectionSha row)
             , wireRowProjectionSha row /= expectedProjectionSha
             ]
          <> [ ProductScenarioJournalCommandMismatch
                 rowId
                 expectedCommand
                 (wireRowCommand row)
             | not (Text.null (Text.strip (wireRowCommand row)))
             , wireRowCommand row /= expectedCommand
             ]
          <> [ ProductScenarioJournalInferenceExperimentMismatch
                 rowId
                 expectedExperiment
                 (wireRowInferenceExperimentHash row)
             | wireRowInferenceExperimentHash row /= expectedExperiment
             ]
          <> [ ProductScenarioJournalInferenceManifestMismatch
                 rowId
                 (wireRowManifestSha row)
                 (wireRowInferenceManifestSha row)
             | canonicalSha256 (wireRowManifestSha row)
             , canonicalSha256 (wireRowInferenceManifestSha row)
             , wireRowInferenceManifestSha row /= wireRowManifestSha row
             ]
       where
        rowId = ProductMatrix.productProjectionRowId projection
        expectedPlanId = planIdText (ProductMatrix.productProjectionPlanId projection)
        expectedSubstrate = ProductMatrix.productProjectionSubstrate projection
        expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
        expectedProjectionSha = projectionSha someProjection
        expectedCommand = projectionCommand projection

validateWireRowShape
  :: FilePath
  -> ProductScenarioJournalRowWire
  -> [ProductScenarioJournalError]
validateWireRowShape path row =
  validateTextIdentity path rowId "row_id" rowId
    <> validateTextIdentity path rowId "run_id" (wireRowRunId row)
    <> validateDigest path "plan_id" (Just rowId) (wireRowPlanId row)
    <> validateRowSubstrateShape path rowId (wireRowSubstrate row)
    <> validateExecutablePath path row
    <> validateDigest
      path
      "executable_sha256"
      (Just rowId)
      (wireRowExecutableSha row)
    <> validateDigest
      path
      "invocation_digest"
      (Just rowId)
      (wireRowInvocationDigest row)
    <> validateTextIdentity path rowId "experiment_hash" (wireRowExperimentHash row)
    <> validateDigest path "manifest_sha256" (Just rowId) (wireRowManifestSha row)
    <> validateDigest path "projection_sha256" (Just rowId) (wireRowProjectionSha row)
    <> validateTextIdentity path rowId "command" (wireRowCommand row)
    <> validateDigest path "contract_sha256" (Just rowId) (wireRowContractSha row)
    <> validateExecutionReceipt path row
    <> validateTextIdentity
      path
      rowId
      "inference_experiment_hash"
      (wireRowInferenceExperimentHash row)
    <> validateDigest
      path
      "inference_manifest_sha256"
      (Just rowId)
      (wireRowInferenceManifestSha row)
    <> validateChronology row
 where
  rowId = wireRowId row

validateExecutionReceipt
  :: FilePath
  -> ProductScenarioJournalRowWire
  -> [ProductScenarioJournalError]
validateExecutionReceipt path row =
  [ ProductScenarioJournalMalformed
      path
      ("row " <> rowId <> " execution_journal_receipt must be non-empty")
  | Text.null receipt
  ]
    <> validateDigest
      path
      "execution_journal_sha256"
      (Just rowId)
      observedDigest
    <> [ ProductScenarioJournalExecutionReceiptDigestMismatch
           rowId
           expectedDigest
           observedDigest
       | canonicalSha256 observedDigest
       , observedDigest /= expectedDigest
       ]
 where
  rowId = wireRowId row
  receipt = wireRowExecutionJournalReceipt row
  expectedDigest = sha256Text receipt
  observedDigest = wireRowExecutionJournalSha row

validateExecutablePath
  :: FilePath
  -> ProductScenarioJournalRowWire
  -> [ProductScenarioJournalError]
validateExecutablePath journalPath row =
  [ ProductScenarioJournalExecutablePathInvalid rowId executablePath
  | not (validExecutablePath executablePath)
  ]
    <> [ ProductScenarioJournalMalformed
           journalPath
           ("row " <> rowId <> " executable_path contains invalid text")
       | '\NUL' `elem` executablePath
       ]
 where
  rowId = wireRowId row
  executablePath = wireRowExecutablePath row

validateExpectedExecutableIdentity
  :: FilePath
  -> FilePath
  -> Text
  -> [ProductScenarioJournalError]
validateExpectedExecutableIdentity journalPath executablePath executableSha =
  [ ProductScenarioJournalExpectedExecutablePathInvalid executablePath
  | not (validExecutablePath executablePath)
  ]
    <> validateDigest
      journalPath
      "expected executable SHA-256"
      Nothing
      executableSha

validExecutablePath :: FilePath -> Bool
validExecutablePath executablePath =
  not (Text.null executableText)
    && Text.strip executableText == executableText
    && not (Text.any isControl executableText)
    && isAbsolute executablePath
    && normalise executablePath == executablePath
 where
  executableText = Text.pack executablePath

validateEvidenceCoverage
  :: ProductMatrix.ProductProjectionBatch
  -> [Report.CompletedProductScenarioEvidence]
  -> [ProductScenarioJournalError]
validateEvidenceCoverage batch evidence =
  missingErrors <> duplicateErrors <> orphanErrors <> orderErrors
 where
  expected = expectedProjectionIdentities batch
  expectedIds = fmap fst expected
  observedIds = fmap Report.completedProductScenarioRowId evidence
  missingErrors =
    [ ProductScenarioJournalMissingRow rowId planId
    | (rowId, planId) <- expected
    , rowId `notElem` observedIds
    ]
  duplicateErrors =
    [ ProductScenarioJournalDuplicateRow rowId
    | rowId <- repeatedTexts observedIds
    ]
  orphanErrors =
    [ ProductScenarioJournalOrphanRow
        (Report.completedProductScenarioRowId row)
        (planIdText (Report.completedProductScenarioPlanId row))
    | row <- evidence
    , Report.completedProductScenarioRowId row `notElem` expectedIds
    ]
  orderErrors =
    [ ProductScenarioJournalRowOrderMismatch expectedIds observedIds
    | observedIds /= expectedIds
    ]

validateEvidenceReportContract
  :: ProductMatrix.ProductProjectionBatch
  -> [Report.CompletedProductScenarioEvidence]
  -> [ProductScenarioJournalError]
validateEvidenceReportContract batch evidence =
  case Report.projectCompletedProductScenarioReport batch evidence of
    Left errors ->
      fmap ProductScenarioJournalReportRejected (NonEmpty.toList errors)
    Right _report -> []

validateEvidenceForProjection
  :: FilePath
  -> Text
  -> Text
  -> ProductMatrix.SomeProductProjection
  -> Report.CompletedProductScenarioEvidence
  -> [ProductScenarioJournalError]
validateEvidenceForProjection path expectedRunId expectedScope someProjection evidence =
  case someProjection of
    ProductMatrix.SomeProductProjection _witness projection ->
      [ ProductScenarioJournalPlanMismatch rowId expectedPlan observedPlan
      | observedPlan /= expectedPlan
      ]
        <> [ ProductScenarioJournalRowRunIdMismatch
               rowId
               expectedRunId
               observedRunId
           | observedRunId /= expectedRunId
           ]
        <> [ ProductScenarioJournalRowSubstrateMismatch
               rowId
               expectedSubstrate
               (renderSubstrate observedSubstrate)
           | observedSubstrate /= expectedSubstrate
           ]
        <> [ ProductScenarioJournalExperimentMismatch
               rowId
               expectedExperiment
               observedExperiment
           | observedExperiment /= expectedExperiment
           ]
        <> [ ProductScenarioJournalCommandMismatch
               rowId
               expectedCommand
               observedCommand
           | observedCommand /= expectedCommand
           ]
        <> [ ProductScenarioJournalCheckpointScopeMismatch
               expectedScope
               observedScope
           | observedScope /= expectedScope
           ]
        <> validateDigest path "manifest_sha256" (Just rowId) observedManifest
        <> [ ProductScenarioJournalExecutablePathInvalid rowId observedExecutablePath
           | not (validExecutablePath observedExecutablePath)
           ]
        <> validateDigest
          path
          "executable_sha256"
          (Just rowId)
          observedExecutableSha
        <> validateDigest
          path
          "invocation_digest"
          (Just rowId)
          observedInvocationDigest
        <> validateDigest path "contract_sha256" (Just rowId) observedContractSha
        <> validateEvidenceExecutionReceipt path evidence
        <> validateDigest
          path
          "inference_manifest_sha256"
          (Just rowId)
          observedInferenceManifest
        <> [ ProductScenarioJournalInferenceManifestMismatch
               rowId
               observedManifest
               observedInferenceManifest
           | observedInferenceManifest /= observedManifest
           ]
        <> validateEvidenceChronology evidence
     where
      rowId = ProductMatrix.productProjectionRowId projection
      expectedPlan = planIdText (ProductMatrix.productProjectionPlanId projection)
      observedPlan = planIdText (Report.completedProductScenarioPlanId evidence)
      observedRunId = Report.completedProductScenarioRunId evidence
      expectedSubstrate = ProductMatrix.productProjectionSubstrate projection
      observedSubstrate = Report.completedProductScenarioLane evidence
      expectedExperiment = ProductMatrix.productProjectionExperimentHash projection
      observedExperiment = Report.completedProductScenarioExperimentHash evidence
      expectedCommand = projectionCommand projection

      observedCommand = Report.completedProductScenarioCommand evidence
      observedExecutablePath = Report.completedProductScenarioExecutablePath evidence
      observedExecutableSha = Report.completedProductScenarioExecutableSha256 evidence
      observedInvocationDigest =
        Report.completedProductScenarioInvocationDigest evidence
      observedScope = Report.completedProductScenarioCheckpointScopeDigest evidence
      observedManifest = Report.completedProductScenarioManifestSha evidence
      observedContractSha = Report.completedProductScenarioContractDigest evidence
      observedInferenceManifest =
        Report.completedProductScenarioInferenceManifestSha evidence

validateWireExpectedExecutable
  :: FilePath
  -> Text
  -> ProductScenarioJournalRowWire
  -> [ProductScenarioJournalError]
validateWireExpectedExecutable expectedExecutablePath expectedExecutableSha row =
  [ ProductScenarioJournalExecutablePathMismatch
      (wireRowId row)
      expectedExecutablePath
      (wireRowExecutablePath row)
  | wireRowExecutablePath row /= expectedExecutablePath
  ]
    <> [ ProductScenarioJournalExecutableShaMismatch
           (wireRowId row)
           expectedExecutableSha
           (wireRowExecutableSha row)
       | wireRowExecutableSha row /= expectedExecutableSha
       ]

validateEvidenceExecutionReceipt
  :: FilePath
  -> Report.CompletedProductScenarioEvidence
  -> [ProductScenarioJournalError]
validateEvidenceExecutionReceipt path evidence =
  [ ProductScenarioJournalMalformed
      path
      ("row " <> rowId <> " execution journal receipt must be non-empty")
  | Text.null receipt
  ]
    <> validateDigest
      path
      "execution_journal_sha256"
      (Just rowId)
      observedDigest
    <> [ ProductScenarioJournalExecutionReceiptDigestMismatch
           rowId
           expectedDigest
           observedDigest
       | observedDigest /= expectedDigest
       ]
 where
  rowId = Report.completedProductScenarioRowId evidence
  receipt = Report.completedProductScenarioJournalReceipt evidence
  expectedDigest = sha256Text receipt
  observedDigest = Report.completedProductScenarioJournalDigest evidence

validateChronology
  :: ProductScenarioJournalRowWire
  -> [ProductScenarioJournalError]
validateChronology row =
  [ ProductScenarioJournalPreconditionMissing rowId
  | not (wireRowPreconditionRejected row)
  ]
    <> [ ProductScenarioJournalChronologyInvalid rowId precondition inference completion
       | (precondition, inference, completion) /= (3, 7, 9)
       ]
 where
  rowId = wireRowId row
  precondition = wireRowPreconditionSequence row
  inference = wireRowInferenceSequence row
  completion = wireRowCompletionSequence row

validateEvidenceChronology
  :: Report.CompletedProductScenarioEvidence
  -> [ProductScenarioJournalError]
validateEvidenceChronology evidence =
  [ ProductScenarioJournalPreconditionMissing rowId
  | not (Report.completedProductScenarioPreconditionRejected evidence)
  ]
    <> [ ProductScenarioJournalChronologyInvalid rowId precondition inference completion
       | (precondition, inference, completion) /= (3, 7, 9)
       ]
 where
  rowId = Report.completedProductScenarioRowId evidence
  precondition = Report.completedProductScenarioPreconditionSequence evidence
  inference = Report.completedProductScenarioInferenceSequence evidence
  completion = Report.completedProductScenarioCompletionSequence evidence

validateRowSubstrateShape
  :: FilePath
  -> Text
  -> Text
  -> [ProductScenarioJournalError]
validateRowSubstrateShape path rowId observed =
  case parseSubstrate observed of
    Nothing ->
      [ ProductScenarioJournalMalformed
          path
          ("invalid row substrate for " <> rowId <> ": " <> observed)
      ]
    Just _parsed -> []

validateRowSubstrateMismatch
  :: Text
  -> Substrate
  -> Text
  -> [ProductScenarioJournalError]
validateRowSubstrateMismatch rowId expected observed =
  case parseSubstrate observed of
    Nothing -> []
    Just parsed
      | parsed == expected -> []
      | otherwise ->
          [ProductScenarioJournalRowSubstrateMismatch rowId expected observed]

validateRunId :: FilePath -> Text -> [ProductScenarioJournalError]
validateRunId path runId =
  [ ProductScenarioJournalMalformed path "run_id must be non-empty and trimmed"
  | Text.null runId || Text.strip runId /= runId
  ]
    <> [ ProductScenarioJournalMalformed path "run_id exceeds 256 characters"
       | Text.length runId > 256
       ]
    <> [ ProductScenarioJournalMalformed path "run_id contains a control character"
       | Text.any isControl runId
       ]

validateTextIdentity
  :: FilePath
  -> Text
  -> Text
  -> Text
  -> [ProductScenarioJournalError]
validateTextIdentity path rowId label value =
  [ ProductScenarioJournalMalformed
      path
      ("row " <> rowId <> " has empty or untrimmed " <> label)
  | Text.null value || Text.strip value /= value
  ]

validateDigest
  :: FilePath
  -> Text
  -> Maybe Text
  -> Text
  -> [ProductScenarioJournalError]
validateDigest path label maybeRowId value =
  [ ProductScenarioJournalMalformed path detail
  | not (canonicalSha256 value)
  ]
 where
  detail =
    maybe "" (\rowId -> "row " <> rowId <> " ") maybeRowId
      <> label
      <> " must be exactly 64 lowercase hexadecimal characters"

rowsForReport
  :: ProductMatrix.ProductProjectionBatch
  -> [Report.CompletedProductScenarioEvidence]
  -> Maybe [ProductScenarioJournalRowWire]
rowsForReport batch evidence =
  traverse rowFor (ProductMatrix.productProjectionBatchProjections batch)
 where
  rowFor someProjection =
    case someProjection of
      ProductMatrix.SomeProductProjection _witness projection ->
        case [ completed
             | completed <- evidence
             , Report.completedProductScenarioRowId completed
                 == ProductMatrix.productProjectionRowId projection
             ] of
          [completed] -> Just (wireRowFromEvidence someProjection completed)
          _ -> Nothing

wireRowFromEvidence
  :: ProductMatrix.SomeProductProjection
  -> Report.CompletedProductScenarioEvidence
  -> ProductScenarioJournalRowWire
wireRowFromEvidence someProjection evidence =
  ProductScenarioJournalRowWire
    { wireRowId = Report.completedProductScenarioRowId evidence
    , wireRowRunId = Report.completedProductScenarioRunId evidence
    , wireRowPlanId = planIdText (Report.completedProductScenarioPlanId evidence)
    , wireRowSubstrate = renderSubstrate (Report.completedProductScenarioLane evidence)
    , wireRowExecutablePath =
        Report.completedProductScenarioExecutablePath evidence
    , wireRowExecutableSha =
        Report.completedProductScenarioExecutableSha256 evidence
    , wireRowInvocationDigest =
        Report.completedProductScenarioInvocationDigest evidence
    , wireRowExperimentHash = Report.completedProductScenarioExperimentHash evidence
    , wireRowManifestSha = Report.completedProductScenarioManifestSha evidence
    , wireRowProjectionSha = projectionSha someProjection
    , wireRowCommand = Report.completedProductScenarioCommand evidence
    , wireRowContractSha = Report.completedProductScenarioContractDigest evidence
    , wireRowExecutionJournalReceipt =
        Report.completedProductScenarioJournalReceipt evidence
    , wireRowExecutionJournalSha =
        Report.completedProductScenarioJournalDigest evidence
    , wireRowInferenceExperimentHash =
        Report.completedProductScenarioExperimentHash evidence
    , wireRowInferenceManifestSha =
        Report.completedProductScenarioInferenceManifestSha evidence
    , wireRowPreconditionRejected =
        Report.completedProductScenarioPreconditionRejected evidence
    , wireRowPreconditionSequence =
        Report.completedProductScenarioPreconditionSequence evidence
    , wireRowInferenceSequence =
        Report.completedProductScenarioInferenceSequence evidence
    , wireRowCompletionSequence =
        Report.completedProductScenarioCompletionSequence evidence
    }

matchedRows
  :: ProductMatrix.ProductProjectionBatch
  -> [ProductScenarioJournalRowWire]
  -> [(ProductMatrix.SomeProductProjection, ProductScenarioJournalRowWire)]
matchedRows batch rows =
  [ (projection, row)
  | projection <- ProductMatrix.productProjectionBatchProjections batch
  , row <- rows
  , someProjectionRowId projection == wireRowId row
  ]

matchedEvidence
  :: ProductMatrix.ProductProjectionBatch
  -> [Report.CompletedProductScenarioEvidence]
  -> [(ProductMatrix.SomeProductProjection, Report.CompletedProductScenarioEvidence)]
matchedEvidence batch evidence =
  [ (projection, completed)
  | projection <- ProductMatrix.productProjectionBatchProjections batch
  , completed <- evidence
  , someProjectionRowId projection
      == Report.completedProductScenarioRowId completed
  ]

expectedProjectionIdentities
  :: ProductMatrix.ProductProjectionBatch
  -> [(Text, Text)]
expectedProjectionIdentities batch =
  [ ( ProductMatrix.productProjectionRowId projection
    , planIdText (ProductMatrix.productProjectionPlanId projection)
    )
  | ProductMatrix.SomeProductProjection _witness projection <-
      ProductMatrix.productProjectionBatchProjections batch
  ]

someProjectionRowId :: ProductMatrix.SomeProductProjection -> Text
someProjectionRowId
  (ProductMatrix.SomeProductProjection _witness projection) =
    ProductMatrix.productProjectionRowId projection

rowsForId :: Text -> [ProductScenarioJournalRowWire] -> [ProductScenarioJournalRowWire]
rowsForId rowId = filter ((== rowId) . wireRowId)

repeatedTexts :: [Text] -> [Text]
repeatedTexts values =
  [ value
  | group@(value : _) <- List.group (List.sort values)
  , length group > 1
  ]

projectionCommand :: ProductMatrix.ProductProjection kind -> Text
projectionCommand projection =
  renderSubprocess
    (subprocess "jitml" (ProductMatrix.productProjectionCommand projection))

projectionBatchSha :: ProductMatrix.ProductProjectionBatch -> Text
projectionBatchSha batch =
  sha256Text
    ( "jitml-product-projection-batch-v1\NUL"
        <> Text.pack (show batch)
    )

projectionSha :: ProductMatrix.SomeProductProjection -> Text
projectionSha projection =
  sha256Text
    ( "jitml-product-projection-v1\NUL"
        <> Text.pack (show projection)
    )

-- | Canonical length-delimited material prevents field concatenation
-- ambiguity while keeping authentication independent of Aeson object
-- ordering.  The HMAC field itself is deliberately excluded.
runReceiptMaterial :: ProductScenarioJournalWire -> Text
runReceiptMaterial journal =
  Text.concat
    ( [ receiptField "domain" "jitml-product-scenario-run-receipt-hmac-v1"
      , receiptField "format" (wireFormat journal)
      , receiptField "version" (showText (wireVersion journal))
      , receiptField "run_id" (wireRunId journal)
      , receiptField "substrate" (wireSubstrate journal)
      , receiptField "projection_batch_sha256" (wireProjectionBatchSha journal)
      , receiptField "checkpoint_scope_sha256" (wireCheckpointScopeSha journal)
      , receiptField "row_count" (showText (length (wireRows journal)))
      ]
        <> concat
          [ receiptField "row_index" (showText index)
              : runReceiptRowFields row
          | (index, row) <- zip [(0 :: Int) ..] (wireRows journal)
          ]
    )

runReceiptRowFields :: ProductScenarioJournalRowWire -> [Text]
runReceiptRowFields row =
  [ receiptField "row_id" (wireRowId row)
  , receiptField "run_id" (wireRowRunId row)
  , receiptField "plan_id" (wireRowPlanId row)
  , receiptField "row_substrate" (wireRowSubstrate row)
  , receiptField "executable_path" (Text.pack (wireRowExecutablePath row))
  , receiptField "executable_sha256" (wireRowExecutableSha row)
  , receiptField "invocation_digest" (wireRowInvocationDigest row)
  , receiptField "experiment_hash" (wireRowExperimentHash row)
  , receiptField "manifest_sha256" (wireRowManifestSha row)
  , receiptField "projection_sha256" (wireRowProjectionSha row)
  , receiptField "command" (wireRowCommand row)
  , receiptField "contract_sha256" (wireRowContractSha row)
  , receiptField "execution_journal_receipt" (wireRowExecutionJournalReceipt row)
  , receiptField "execution_journal_sha256" (wireRowExecutionJournalSha row)
  , receiptField "inference_experiment_hash" (wireRowInferenceExperimentHash row)
  , receiptField "inference_manifest_sha256" (wireRowInferenceManifestSha row)
  , receiptField "precondition_rejected" (showText (wireRowPreconditionRejected row))
  , receiptField "precondition_sequence" (showText (wireRowPreconditionSequence row))
  , receiptField "inference_sequence" (showText (wireRowInferenceSequence row))
  , receiptField "completion_sequence" (showText (wireRowCompletionSequence row))
  ]

receiptField :: Text -> Text -> Text
receiptField label value =
  label
    <> "="
    <> showText (Text.length value)
    <> ":"
    <> value
    <> "\n"

sha256Text :: Text -> Text
sha256Text =
  hexBytes
    . SHA256.hash
    . Text.Encoding.encodeUtf8

hexBytes :: ByteString.ByteString -> Text
hexBytes = Text.pack . concatMap byteHex . ByteString.unpack
 where
  byteHex byte =
    let alphabet = "0123456789abcdef"
        value = fromIntegral byte
     in [ alphabet !! (value `div` 16)
        , alphabet !! (value `mod` 16)
        ]

canonicalSha256 :: Text -> Bool
canonicalSha256 value =
  Text.length value == 64 && Text.all lowerHex value
 where
  lowerHex character =
    let codepoint = ord character
     in (codepoint >= ord '0' && codepoint <= ord '9')
          || (character >= 'a' && character <= 'f')

canonicalCheckpointRoot :: FilePath -> IO FilePath
canonicalCheckpointRoot root = do
  createDirectoryIfMissing True root
  canonicalizePath root

showText :: (Show value) => value -> Text
showText = Text.pack . show

writeAtomic :: FilePath -> LazyByteString.ByteString -> IO ()
writeAtomic path payload = do
  let directory = takeDirectory path
      prefix = takeFileName path <> ".tmp."
  createDirectoryIfMissing True directory
  (temporaryPath, handle) <- openBinaryTempFile directory prefix
  let cleanup = cleanupTemporary temporaryPath handle
  ( do
      LazyByteString.hPut handle payload
      hFlush handle
      hClose handle
      renameFile temporaryPath path
    )
    `onException` cleanup

cleanupTemporary :: FilePath -> Handle -> IO ()
cleanupTemporary path handle = do
  ignoreIOException (hClose handle)
  ignoreIOException (removeFile path)

ignoreIOException :: IO value -> IO ()
ignoreIOException action = do
  _result <- tryIO action
  pure ()

tryIO :: IO value -> IO (Either IOException value)
tryIO = try
