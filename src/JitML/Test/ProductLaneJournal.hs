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
  , admittedProductLaneJournalRows
  , admittedProductLaneJournalRunId
  , admittedProductLaneJournalSourceDigest
  , admittedProductLaneJournalSubstrate
  , buildProductLaneJournal
  , issuedProductLaneJournalBytes
  , issuedProductLaneJournalSha256
  , productLaneJournalRowCompletedTraining
  , productLaneJournalRowContractDigest
  , productLaneJournalRowDeviceWitness
  , productLaneJournalRowExperimentHash
  , productLaneJournalRowJournalDigest
  , productLaneJournalRowManifestSha
  , productLaneJournalRowMeasuredDigest
  , productLaneJournalRowPlanId
  , productLaneJournalRowRowId
  , productLaneJournalRowSubstrate
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
  , eitherDecodeStrict'
  , encode
  , object
  , withObject
  , (.:)
  , (.=)
  )
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types (Object, Parser)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (intToDigit, isControl)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64, Word8)
import System.Directory (createDirectoryIfMissing, removeFile, renameFile)
import System.FilePath (takeDirectory, takeFileName)
import System.IO (hClose, hFlush, openBinaryTempFile)

import JitML.Plan.Plan (PlanId, planIdText)
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report qualified as Report
import JitML.Training.Budget (CompletedTraining)
import JitML.Training.Budget qualified as Budget

productLaneJournalFormat :: Text
productLaneJournalFormat = "jitml-product-lane-journal"

productLaneJournalWireVersion :: Word64
productLaneJournalWireVersion = 1

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
  , wireRowStatus :: !Text
  }
  deriving stock (Eq, Show)

newtype IssuedProductLaneJournal = IssuedProductLaneJournal
  { issuedWire :: ProductLaneJournalWire
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
  , admittedRowDevice :: !DeviceWitness.DeviceExecutionWitness
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
      rows <-
        case traverse buildRow (zip3 [0 ..] projections evidence) of
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
      case validateWire batch journal of
        [] -> Right (IssuedProductLaneJournal journal)
        failure : failures ->
          Left
            ( fmap
                ProductLaneJournalSourceRejected
                (failure :| failures)
            )
 where
  buildRow (ordinal, someProjection, evidence) =
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
                Right
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
                        DeviceWitness.renderDeviceExecutionWitness
                          (Report.completedProductScenarioDeviceWitness evidence)
                    , wireRowCompletedTraining =
                        Budget.renderCompletedTraining
                          (Report.completedProductScenarioCompletedTraining evidence)
                    , wireRowStatus = "Passed"
                    }

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
      written <- tryIO (writeAtomic path (issuedProductLaneJournalBytes issued))
      pure $
        case written of
          Left exception ->
            Left
              ( ProductLaneJournalIOFailure path (Text.pack (show exception))
                  :| []
              )
          Right () -> Right issued

admitProductLaneJournal
  :: Text
  -> ProductMatrix.ProductProjectionBatch
  -> ByteString
  -> Either (NonEmpty ProductLaneJournalError) AdmittedProductLaneJournal
admitProductLaneJournal expectedSha batch bytes = do
  unless (isCanonicalSha256 expectedSha) $
    Left
      ( ProductLaneJournalMalformed
          "expected lane-journal digest is not canonical SHA-256"
          :| []
      )
  let actualSha = sha256Bytes bytes
  unless (actualSha == expectedSha) $
    Left (ProductLaneJournalDigestMismatch expectedSha actualSha :| [])
  journal <-
    case eitherDecodeStrict' bytes of
      Left detail -> Left (ProductLaneJournalMalformed (Text.pack detail) :| [])
      Right value -> Right value
  unless (canonicalBytes journal == bytes) $
    Left (ProductLaneJournalNonCanonical :| [])
  case NonEmpty.nonEmpty (validateWire batch journal) of
    Just failures ->
      Left (fmap ProductLaneJournalSourceRejected failures)
    Nothing -> do
      rows <-
        case traverse (admitRow (wireRunId journal)) (wireRows journal) of
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
  :: Text
  -> ProductLaneJournalRowWire
  -> Either ProductLaneJournalError ProductLaneJournalRow
admitRow runId row = do
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
  witness <-
    case Budget.completedTrainingDeviceWitness completed of
      Right (Just value) -> Right value
      _ ->
        Left
          ( ProductLaneJournalSourceRejected
              (wireRowId row <> ": completed_training has no device witness")
          )
  case validateCompletedRow runId row plan lane witness completed of
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
          , admittedRowDevice = witness
          , admittedRowCompleted = completed
          }
    failure : _ -> Left (ProductLaneJournalSourceRejected failure)

validateCompletedRow
  :: Text
  -> ProductLaneJournalRowWire
  -> PlanId
  -> Substrate
  -> DeviceWitness.DeviceExecutionWitness
  -> CompletedTraining
  -> [Text]
validateCompletedRow runId row plan lane witness completed =
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
        , DeviceWitness.renderDeviceExecutionWitness witness
            == wireRowDeviceWitness row
        )
      , ("device_witness substrate", DeviceWitness.witnessSubstrate witness == lane)
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
validateWire
  :: ProductMatrix.ProductProjectionBatch
  -> ProductLaneJournalWire
  -> [Text]
validateWire batch journal =
  aggregateFailures <> coverageFailures <> concat (zipWith validateProjected projections rows)
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
         in [ rowId <> ": plan_id differs from the current projection"
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
              <> [ rowId <> ": contract_sha256 differs from the current projection"
                 | wireRowContractSha row
                     /= Report.productScenarioProjectionContractDigest projection
                 ]
              <> [rowId <> ": status is not Passed" | wireRowStatus row /= "Passed"]
              <> [ rowId <> ": device_witness is empty or untrimmed"
                 | invalidText (wireRowDeviceWitness row)
                 ]
              <> [ rowId <> ": " <> label <> " is not canonical SHA-256"
                 | (label, value) <- digestFields
                 , not (isCanonicalSha256 value)
                 ]

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
  :: ProductLaneJournalRow -> DeviceWitness.DeviceExecutionWitness
productLaneJournalRowDeviceWitness = admittedRowDevice

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
