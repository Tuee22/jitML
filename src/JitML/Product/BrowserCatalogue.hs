{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Authenticated, content-addressed ProductRow catalogue for browser serving.
--
-- A catalogue can be built only from the authentication-preserving scenario
-- journal result.  Publication re-admits every exact mirrored MinIO checkpoint
-- before writing immutable catalogue/root objects and advances the substrate
-- selector with CAS last.  Roots are an append-only evidence archive for every
-- authenticated, live-admitted catalogue publication attempt, including an
-- attempt that later loses selector CAS; deleting them on CAS failure would
-- race another publisher of the same content and could expose a selected
-- catalogue without its checkpoint roots.  Selection uses a stable
-- P1/object/P2 read and again re-admits every exact address against the current
-- 55-row projection.
module JitML.Product.BrowserCatalogue
  ( AdmittedProductBrowserCatalogue
  , AdmittedProductBrowserCatalogueRow
  , ProductBrowserCatalogue
  , ProductBrowserCatalogueError (..)
  , ProductBrowserCatalogueRow
  , PublishedProductBrowserCatalogue
  , admittedProductBrowserCatalogue
  , admittedProductBrowserCatalogueRowBudget
  , admittedProductBrowserCatalogueRowCatalogueRow
  , admittedProductBrowserCatalogueRowMeasuredResult
  , admittedProductBrowserCatalogueRowModelFamily
  , admittedProductBrowserCatalogueRowStep
  , admittedProductBrowserCatalogueRowTensorBoardPrefix
  , admittedProductBrowserCatalogueRowTensorCount
  , admittedProductBrowserCatalogueRows
  , buildProductBrowserCatalogue
  , loadProductBrowserCatalogueGcRoots
  , productBrowserCatalogueBytes
  , productBrowserCatalogueObjectRef
  , productBrowserCatalogueRowContractDigest
  , productBrowserCatalogueRowDemoPanel
  , productBrowserCatalogueRowE2ETest
  , productBrowserCatalogueRowExperimentHash
  , productBrowserCatalogueRowJournalDigest
  , productBrowserCatalogueRowManifestSha
  , productBrowserCatalogueRowMeasuredDigest
  , productBrowserCatalogueRowMeasuredResult
  , productBrowserCatalogueRowOrdinal
  , productBrowserCatalogueRowPlanId
  , productBrowserCatalogueRowRowId
  , productBrowserCatalogueRowStatus
  , productBrowserCatalogueRows
  , productBrowserCatalogueRunId
  , productBrowserCatalogueSelectorRef
  , productBrowserCatalogueSha256
  , productBrowserCatalogueSourceJournalDigest
  , productBrowserCatalogueSubstrate
  , publishProductBrowserCatalogue
  , publishedProductBrowserCatalogue
  , publishedProductBrowserCatalogueSelectorETag
  , readSelectedProductBrowserCatalogue
  , renderProductBrowserCatalogueInput
  )
where

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
import Data.Char (isControl, isDigit)
import Data.Either (lefts, rights)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)

import JitML.Checkpoint.Format
  ( CheckpointManifest (..)
  , ModelFamily (..)
  , manifestContentSha
  )
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Service.Capabilities
  ( BucketName (..)
  , ETag
  , HasMinIO (..)
  , ObjectKey (..)
  , ObjectRef (..)
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report qualified as Report
import JitML.Training.Budget
  ( completedTrainingBudget
  , completedTrainingPlanId
  , completedTrainingProductScenarioInvocation
  , completedTrainingTensorBoard
  , productScenarioInvocationPlanId
  , productScenarioInvocationRowId
  , productScenarioInvocationRunId
  , productScenarioInvocationSubstrate
  , renderTrainingBudget
  , tbrLogPrefix
  )

catalogueFormat :: Text
catalogueFormat = "jitml-product-browser-catalogue"

catalogueInputFormat :: Text
catalogueInputFormat = "jitml-browser-catalogue-input"

catalogueWireVersion :: Word64
catalogueWireVersion = 1

canonicalProductRowCount :: Int
canonicalProductRowCount = 55

catalogueBucket :: BucketName
catalogueBucket = BucketName "jitml-artifacts"

data ProductBrowserCatalogueWire = ProductBrowserCatalogueWire
  { wireFormat :: !Text
  , wireVersion :: !Word64
  , wireRunId :: !Text
  , wireSubstrate :: !Text
  , wireSourceJournalSha :: !Text
  , wireRows :: ![ProductBrowserCatalogueRowWire]
  }
  deriving stock (Eq, Show)

data ProductBrowserCatalogueRowWire = ProductBrowserCatalogueRowWire
  { wireRowOrdinal :: !Word64
  , wireRowId :: !Text
  , wireRowPlanId :: !Text
  , wireRowExperimentHash :: !Text
  , wireRowManifestSha :: !Text
  , wireRowContractSha :: !Text
  , wireRowJournalSha :: !Text
  , wireRowMeasuredSha :: !Text
  , wireRowE2ETest :: !Text
  , wireRowDemoPanel :: !Text
  , wireRowMeasuredResult :: !Text
  , wireRowStatus :: !Text
  }
  deriving stock (Eq, Show)

data ProductBrowserCatalogue = ProductBrowserCatalogue
  { catalogueWireValue :: !ProductBrowserCatalogueWire
  , catalogueBytesValue :: !ByteString
  , catalogueShaValue :: !Text
  , catalogueSubstrateValue :: !Substrate
  }
  deriving stock (Eq, Show)

newtype ProductBrowserCatalogueRow = ProductBrowserCatalogueRow
  { catalogueRowWireValue :: ProductBrowserCatalogueRowWire
  }
  deriving stock (Eq, Show)

data PublishedProductBrowserCatalogue = PublishedProductBrowserCatalogue
  { publishedCatalogueValue :: !ProductBrowserCatalogue
  , publishedSelectorETagValue :: !ETag
  }
  deriving stock (Eq, Show)

data AdmittedProductBrowserCatalogueRow = AdmittedProductBrowserCatalogueRow
  { admittedCatalogueRowValue :: !ProductBrowserCatalogueRow
  , admittedCatalogueCompletionValue :: !CheckpointStore.AdmittedCompletedCheckpoint
  }
  deriving stock (Eq, Show)

data AdmittedProductBrowserCatalogue = AdmittedProductBrowserCatalogue
  { admittedCatalogueValue :: !ProductBrowserCatalogue
  , admittedCatalogueRowsValue :: ![AdmittedProductBrowserCatalogueRow]
  }
  deriving stock (Eq, Show)

data ProductBrowserCatalogueError
  = CatalogueCurrentProjectionRejected !Text
  | CatalogueSourceCoverageRejected !Text
  | CatalogueWireMalformed !Text
  | CatalogueWireNonCanonical
  | CatalogueContentAddressMismatch !Text !Text
  | CatalogueObjectReadFailed !ObjectRef !ServiceError
  | CatalogueImmutableWriteFailed !ObjectRef !ServiceError
  | CatalogueImmutableObjectConflict !ObjectRef
  | CatalogueSelectorReadFailed !ObjectRef !ServiceError
  | CatalogueSelectorMalformed !Text
  | CatalogueSelectorChanged !Text !Text
  | CatalogueSelectorCasFailed !ObjectRef !ServiceError
  | CatalogueLiveAdmissionRejected
      !Text
      !CheckpointStore.CheckpointAdmissionError
  | CatalogueLiveEvidenceMismatch !Text !Text
  | CatalogueGcRootListingFailed !Text !ServiceError
  | CatalogueGcRootMalformed !ObjectRef !Text
  | CatalogueGcRootReadFailed !ObjectRef !ServiceError
  | CatalogueGcRootMissingManifest !ObjectRef !Text
  deriving stock (Eq, Show)

instance ToJSON ProductBrowserCatalogueWire where
  toJSON catalogue =
    object
      [ "format" .= wireFormat catalogue
      , "version" .= wireVersion catalogue
      , "run_id" .= wireRunId catalogue
      , "substrate" .= wireSubstrate catalogue
      , "source_journal_sha256" .= wireSourceJournalSha catalogue
      , "rows" .= wireRows catalogue
      ]

instance FromJSON ProductBrowserCatalogueWire where
  parseJSON =
    withObject "ProductBrowserCatalogue" $ \record -> do
      requireExactFields
        "ProductBrowserCatalogue"
        [ "format"
        , "version"
        , "run_id"
        , "substrate"
        , "source_journal_sha256"
        , "rows"
        ]
        record
      ProductBrowserCatalogueWire
        <$> record .: "format"
        <*> record .: "version"
        <*> record .: "run_id"
        <*> record .: "substrate"
        <*> record .: "source_journal_sha256"
        <*> record .: "rows"

instance ToJSON ProductBrowserCatalogueRowWire where
  toJSON row =
    object
      [ "ordinal" .= wireRowOrdinal row
      , "row_id" .= wireRowId row
      , "plan_id" .= wireRowPlanId row
      , "experiment_hash" .= wireRowExperimentHash row
      , "manifest_sha256" .= wireRowManifestSha row
      , "contract_sha256" .= wireRowContractSha row
      , "journal_sha256" .= wireRowJournalSha row
      , "measured_sha256" .= wireRowMeasuredSha row
      , "e2e_test" .= wireRowE2ETest row
      , "demo_panel" .= wireRowDemoPanel row
      , "measured_result" .= wireRowMeasuredResult row
      , "status" .= wireRowStatus row
      ]

instance FromJSON ProductBrowserCatalogueRowWire where
  parseJSON =
    withObject "ProductBrowserCatalogueRow" $ \record -> do
      requireExactFields
        "ProductBrowserCatalogueRow"
        [ "ordinal"
        , "row_id"
        , "plan_id"
        , "experiment_hash"
        , "manifest_sha256"
        , "contract_sha256"
        , "journal_sha256"
        , "measured_sha256"
        , "e2e_test"
        , "demo_panel"
        , "measured_result"
        , "status"
        ]
        record
      ProductBrowserCatalogueRowWire
        <$> record .: "ordinal"
        <*> record .: "row_id"
        <*> record .: "plan_id"
        <*> record .: "experiment_hash"
        <*> record .: "manifest_sha256"
        <*> record .: "contract_sha256"
        <*> record .: "journal_sha256"
        <*> record .: "measured_sha256"
        <*> record .: "e2e_test"
        <*> record .: "demo_panel"
        <*> record .: "measured_result"
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

-- | Pure trust projection.  It accepts only the opaque authentication-
-- preserving journal result and the exact current 55-row batch.
buildProductBrowserCatalogue
  :: ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> Either (NonEmpty ProductBrowserCatalogueError) ProductBrowserCatalogue
buildProductBrowserCatalogue batch authenticated = do
  let report = ProductScenarioJournal.authenticatedProductScenarioReport authenticated
      evidence = Report.completedProductScenarioReportEntries report
      projections = ProductMatrix.productProjectionBatchProjections batch
      sourceErrors = validateSource batch authenticated evidence
  case NonEmpty.nonEmpty sourceErrors of
    Just errors -> Left errors
    Nothing -> do
      rows <-
        case traverse sourceRow (zip3 [0 ..] projections evidence) of
          Left err -> Left (err :| [])
          Right value -> Right value
      let wire =
            ProductBrowserCatalogueWire
              { wireFormat = catalogueFormat
              , wireVersion = catalogueWireVersion
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
      case NonEmpty.nonEmpty (validateWireAgainstCurrent batch wire) of
        Just errors -> Left errors
        Nothing ->
          Right
            ( catalogueFromWire
                (ProductMatrix.productProjectionBatchSubstrate batch)
                wire
            )
 where
  sourceRow (ordinal, someProjection, evidence) =
    case someProjection of
      ProductMatrix.SomeProductProjection _ projection ->
        let rowId = ProductMatrix.productProjectionRowId projection
            failures =
              [ "source report row order differs from current projection"
              | Report.completedProductScenarioRowId evidence /= rowId
              ]
                <> [ "source report PlanId differs from current projection"
                   | Report.completedProductScenarioPlanId evidence
                       /= ProductMatrix.productProjectionPlanId projection
                   ]
                <> [ "source report substrate differs from current projection"
                   | Report.completedProductScenarioLane evidence
                       /= ProductMatrix.productProjectionSubstrate projection
                   ]
                <> [ "source report run differs from authenticated aggregate"
                   | Report.completedProductScenarioRunId evidence
                       /= ProductScenarioJournal.authenticatedProductScenarioReportRunId
                         authenticated
                   ]
         in case failures of
              failure : _ ->
                Left (CatalogueSourceCoverageRejected (rowId <> ": " <> failure))
              [] ->
                Right
                  ProductBrowserCatalogueRowWire
                    { wireRowOrdinal = ordinal
                    , wireRowId = rowId
                    , wireRowPlanId =
                        planIdText (ProductMatrix.productProjectionPlanId projection)
                    , wireRowExperimentHash =
                        ProductMatrix.productProjectionExperimentHash projection
                    , wireRowManifestSha =
                        Report.completedProductScenarioManifestSha evidence
                    , wireRowContractSha =
                        Report.completedProductScenarioContractDigest evidence
                    , wireRowJournalSha =
                        Report.completedProductScenarioJournalDigest evidence
                    , wireRowMeasuredSha =
                        Report.completedProductScenarioMeasuredDigest evidence
                    , wireRowE2ETest =
                        ProductMatrix.productProjectionE2ETest projection
                    , wireRowDemoPanel =
                        ProductMatrix.productProjectionDemoPanel projection
                    , wireRowMeasuredResult =
                        Report.completedProductScenarioMeasuredSummary evidence
                    , wireRowStatus = "Passed"
                    }

validateSource
  :: ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> [Report.CompletedProductScenarioEvidence]
  -> [ProductBrowserCatalogueError]
validateSource batch authenticated evidence =
  [ CatalogueSourceCoverageRejected
      ( "catalogue requires exactly 55 current ProductRows, got registry="
          <> showText (length ProductMatrix.allProductRows)
          <> ", batch="
          <> showText (length batchRows)
          <> ", report="
          <> showText (length evidence)
      )
  | length ProductMatrix.allProductRows /= canonicalProductRowCount
      || length batchRows /= canonicalProductRowCount
      || length evidence /= canonicalProductRowCount
  ]
    <> [ CatalogueSourceCoverageRejected
           "projection batch is not the exact current registry order"
       | batchRows /= ProductMatrix.productRowIds
       ]
    <> [ CatalogueSourceCoverageRejected
           "authenticated source journal digest is not canonical SHA-256"
       | not
           ( canonicalSha256
               ( ProductScenarioJournal.authenticatedProductScenarioReportSourceDigest
                   authenticated
               )
           )
       ]
 where
  batchRows = ProductMatrix.productProjectionBatchRowIds batch

catalogueFromWire
  :: Substrate
  -> ProductBrowserCatalogueWire
  -> ProductBrowserCatalogue
catalogueFromWire substrate wire =
  ProductBrowserCatalogue
    { catalogueWireValue = wire
    , catalogueBytesValue = bytes
    , catalogueShaValue = sha256Bytes bytes
    , catalogueSubstrateValue = substrate
    }
 where
  bytes = LazyByteString.toStrict (encode wire)

-- | Publish transaction.  Every exact live address is admitted first;
-- immutable catalogue and archival GC-root objects follow; selector CAS is
-- last.  The roots intentionally outlive selector changes and failed selector
-- CAS attempts: they preserve authenticated browser evidence, rather than
-- representing only the currently selected UI projection.
publishProductBrowserCatalogue
  :: (HasMinIO m)
  => Maybe ETag
  -> ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> m
       ( Either
           (NonEmpty ProductBrowserCatalogueError)
           PublishedProductBrowserCatalogue
       )
publishProductBrowserCatalogue expectedSelectorETag batch authenticated =
  case buildProductBrowserCatalogue batch authenticated of
    Left errors -> pure (Left errors)
    Right catalogue -> do
      liveResult <- admitSourceRows batch authenticated catalogue
      case liveResult of
        Left errors -> pure (Left errors)
        Right _ -> do
          objectResult <-
            putImmutableText
              (productBrowserCatalogueObjectRef catalogue)
              (Text.Encoding.decodeUtf8 (productBrowserCatalogueBytes catalogue))
          case objectResult of
            Left err -> pure (Left (err :| []))
            Right () -> do
              rootResult <- writeCatalogueRoots catalogue
              case rootResult of
                Left errors -> pure (Left errors)
                Right () -> do
                  selected <-
                    casPointer
                      ( productBrowserCatalogueSelectorRef
                          (productBrowserCatalogueSubstrate catalogue)
                      )
                      expectedSelectorETag
                      (productBrowserCatalogueSha256 catalogue)
                  pure $
                    case selected of
                      Left err ->
                        Left
                          ( CatalogueSelectorCasFailed
                              ( productBrowserCatalogueSelectorRef
                                  (productBrowserCatalogueSubstrate catalogue)
                              )
                              err
                              :| []
                          )
                      Right etag ->
                        Right
                          PublishedProductBrowserCatalogue
                            { publishedCatalogueValue = catalogue
                            , publishedSelectorETagValue = etag
                            }
 where
  putImmutableText ref payload = do
    written <- putBlobIfAbsent ref payload
    case written of
      Right _ -> pure (Right ())
      Left (SEConflict _) -> do
        existing <- minioReadObject ref
        pure $
          case existing of
            Right exact | exact == payload -> Right ()
            Right _ -> Left (CatalogueImmutableObjectConflict ref)
            Left err -> Left (CatalogueObjectReadFailed ref err)
      Left err -> pure (Left (CatalogueImmutableWriteFailed ref err))

  writeCatalogueRoots catalogue = do
    results <-
      traverse
        ( \row ->
            putImmutableText
              (catalogueGcRootRef catalogue row)
              (productBrowserCatalogueRowManifestSha row)
        )
        (productBrowserCatalogueRows catalogue)
    pure $
      case NonEmpty.nonEmpty (lefts results) of
        Just errors -> Left errors
        Nothing -> Right ()

admitSourceRows
  :: (HasMinIO m)
  => ProductMatrix.ProductProjectionBatch
  -> ProductScenarioJournal.AuthenticatedProductScenarioReport
  -> ProductBrowserCatalogue
  -> m
       ( Either
           (NonEmpty ProductBrowserCatalogueError)
           [AdmittedProductBrowserCatalogueRow]
       )
admitSourceRows batch authenticated catalogue = do
  let projections = ProductMatrix.productProjectionBatchProjections batch
      evidence =
        Report.completedProductScenarioReportEntries
          (ProductScenarioJournal.authenticatedProductScenarioReport authenticated)
      rows = productBrowserCatalogueRows catalogue
  results <- traverse admitOne (zip3 projections evidence rows)
  pure (sequenceNonEmptyErrors results)
 where
  admitOne (someProjection, evidence, row) =
    case someProjection of
      ProductMatrix.SomeProductProjection _ projection -> do
        admitted <- admitExactRow row
        pure $ do
          completion <- admitted
          case Report.validateCompletedProductScenarioLiveAdmission
            projection
            evidence
            completion of
            Left detail ->
              Left
                ( CatalogueLiveEvidenceMismatch
                    (productBrowserCatalogueRowRowId row)
                    detail
                    :| []
                )
            Right () ->
              Right
                AdmittedProductBrowserCatalogueRow
                  { admittedCatalogueRowValue = row
                  , admittedCatalogueCompletionValue = completion
                  }

-- | Stable P1/object/P2 selected reader with strict current-projection and live
-- completion re-admission.  There is no loose object scan fallback.
readSelectedProductBrowserCatalogue
  :: (HasMinIO m)
  => Substrate
  -> m
       ( Either
           (NonEmpty ProductBrowserCatalogueError)
           AdmittedProductBrowserCatalogue
       )
readSelectedProductBrowserCatalogue substrate =
  case currentProductProjectionBatch substrate of
    Left err -> pure (Left (err :| []))
    Right batch -> do
      let selectorRef = productBrowserCatalogueSelectorRef substrate
      p1Result <- minioReadObject selectorRef
      case p1Result of
        Left err ->
          pure (Left (CatalogueSelectorReadFailed selectorRef err :| []))
        Right p1 ->
          case parseCataloguePointer p1 of
            Left err -> pure (Left (err :| []))
            Right catalogueSha -> do
              let objectRef = catalogueObjectRefForSha substrate catalogueSha
              payloadResult <- minioReadObject objectRef
              case payloadResult of
                Left err ->
                  pure (Left (CatalogueObjectReadFailed objectRef err :| []))
                Right payload ->
                  case decodeAndValidateCatalogue batch catalogueSha payload of
                    Left errors -> pure (Left errors)
                    Right catalogue -> do
                      admittedRows <- admitDecodedRows batch catalogue
                      case admittedRows of
                        Left errors -> pure (Left errors)
                        Right rows -> do
                          p2Result <- minioReadObject selectorRef
                          pure $ do
                            p2 <-
                              case p2Result of
                                Left err ->
                                  Left (CatalogueSelectorReadFailed selectorRef err :| [])
                                Right value -> Right value
                            p2Sha <-
                              case parseCataloguePointer p2 of
                                Left err -> Left (err :| [])
                                Right value -> Right value
                            if p2Sha /= catalogueSha
                              then
                                Left
                                  ( CatalogueSelectorChanged catalogueSha p2Sha
                                      :| []
                                  )
                              else
                                Right
                                  AdmittedProductBrowserCatalogue
                                    { admittedCatalogueValue = catalogue
                                    , admittedCatalogueRowsValue = rows
                                    }

decodeAndValidateCatalogue
  :: ProductMatrix.ProductProjectionBatch
  -> Text
  -> Text
  -> Either (NonEmpty ProductBrowserCatalogueError) ProductBrowserCatalogue
decodeAndValidateCatalogue batch expectedSha payload = do
  let payloadBytes = Text.Encoding.encodeUtf8 payload
      actualSha = sha256Bytes payloadBytes
  if actualSha /= expectedSha
    then
      Left
        (CatalogueContentAddressMismatch expectedSha actualSha :| [])
    else Right ()
  wire <-
    case eitherDecodeStrict' payloadBytes of
      Left detail -> Left (CatalogueWireMalformed (Text.pack detail) :| [])
      Right value -> Right value
  let canonical = LazyByteString.toStrict (encode wire)
  if canonical /= payloadBytes
    then Left (CatalogueWireNonCanonical :| [])
    else Right ()
  case NonEmpty.nonEmpty (validateWireAgainstCurrent batch wire) of
    Just errors -> Left errors
    Nothing ->
      Right
        ProductBrowserCatalogue
          { catalogueWireValue = wire
          , catalogueBytesValue = payloadBytes
          , catalogueShaValue = actualSha
          , catalogueSubstrateValue =
              ProductMatrix.productProjectionBatchSubstrate batch
          }

validateWireAgainstCurrent
  :: ProductMatrix.ProductProjectionBatch
  -> ProductBrowserCatalogueWire
  -> [ProductBrowserCatalogueError]
validateWireAgainstCurrent batch wire =
  topErrors <> rowErrors
 where
  projections = ProductMatrix.productProjectionBatchProjections batch
  rows = wireRows wire
  expectedSubstrate = ProductMatrix.productProjectionBatchSubstrate batch
  topErrors =
    [ CatalogueWireMalformed "catalogue format mismatch"
    | wireFormat wire /= catalogueFormat
    ]
      <> [ CatalogueWireMalformed "catalogue version mismatch"
         | wireVersion wire /= catalogueWireVersion
         ]
      <> [ CatalogueWireMalformed "catalogue run_id is not a safe non-empty token"
         | not (safeToken (wireRunId wire))
         ]
      <> [ CatalogueWireMalformed "catalogue source journal digest is not canonical SHA-256"
         | not (canonicalSha256 (wireSourceJournalSha wire))
         ]
      <> [ CatalogueWireMalformed "catalogue substrate differs from selected lane"
         | parseSubstrate (wireSubstrate wire) /= Just expectedSubstrate
         ]
      <> [ CatalogueWireMalformed "catalogue is not the exact current 55-row projection"
         | length ProductMatrix.allProductRows /= canonicalProductRowCount
             || length projections /= canonicalProductRowCount
             || length rows /= canonicalProductRowCount
             || ProductMatrix.productProjectionBatchRowIds batch
               /= ProductMatrix.productRowIds
         ]
      <> [ CatalogueWireMalformed
             ("catalogue contains duplicate manifest identity: " <> duplicate)
         | duplicate <- duplicates (fmap wireRowManifestSha rows)
         ]
      <> [ CatalogueWireMalformed
             ("catalogue contains duplicate e2e identity: " <> duplicate)
         | duplicate <- duplicates (fmap wireRowE2ETest rows)
         ]
  rowErrors =
    if length rows /= length projections
      then []
      else concatMap validateRow (zip3 [0 ..] projections rows)

  validateRow (ordinal, someProjection, row) =
    case someProjection of
      ProductMatrix.SomeProductProjection _ projection ->
        let rowId = ProductMatrix.productProjectionRowId projection
            malformed detail = CatalogueWireMalformed (rowId <> ": " <> detail)
         in [malformed "ordinal/order mismatch" | wireRowOrdinal row /= ordinal]
              <> [malformed "row_id/order mismatch" | wireRowId row /= rowId]
              <> [ malformed "PlanId differs from current projection"
                 | wireRowPlanId row
                     /= planIdText (ProductMatrix.productProjectionPlanId projection)
                 ]
              <> [ malformed "experiment differs from current projection"
                 | wireRowExperimentHash row
                     /= ProductMatrix.productProjectionExperimentHash projection
                 ]
              <> [ malformed "contract digest differs from current projection"
                 | wireRowContractSha row
                     /= Report.productScenarioProjectionContractDigest projection
                 ]
              <> [ malformed "e2e test differs from current projection"
                 | wireRowE2ETest row
                     /= ProductMatrix.productProjectionE2ETest projection
                 ]
              <> [ malformed "demo panel differs from current projection"
                 | wireRowDemoPanel row
                     /= ProductMatrix.productProjectionDemoPanel projection
                 ]
              <> [ malformed "manifest digest is not canonical SHA-256"
                 | not (canonicalSha256 (wireRowManifestSha row))
                 ]
              <> [ malformed "contract digest is not canonical SHA-256"
                 | not (canonicalSha256 (wireRowContractSha row))
                 ]
              <> [ malformed "journal digest is not canonical SHA-256"
                 | not (canonicalSha256 (wireRowJournalSha row))
                 ]
              <> [ malformed "measured digest is not canonical SHA-256"
                 | not (canonicalSha256 (wireRowMeasuredSha row))
                 ]
              <> [ malformed "measured result is empty or contains control characters"
                 | not (safeToken (wireRowMeasuredResult row))
                 ]
              <> [malformed "source status is not Passed" | wireRowStatus row /= "Passed"]

admitDecodedRows
  :: (HasMinIO m)
  => ProductMatrix.ProductProjectionBatch
  -> ProductBrowserCatalogue
  -> m
       ( Either
           (NonEmpty ProductBrowserCatalogueError)
           [AdmittedProductBrowserCatalogueRow]
       )
admitDecodedRows batch catalogue = do
  results <-
    traverse
      admitOne
      ( zip
          (ProductMatrix.productProjectionBatchProjections batch)
          (productBrowserCatalogueRows catalogue)
      )
  pure (sequenceNonEmptyErrors results)
 where
  runId = productBrowserCatalogueRunId catalogue
  substrate = productBrowserCatalogueSubstrate catalogue
  admitOne (someProjection, row) =
    case someProjection of
      ProductMatrix.SomeProductProjection _ projection -> do
        admitted <- admitExactRow row
        pure $ do
          completion <- admitted
          let completed = CheckpointStore.admittedCompletedTraining completion
              invocation = completedTrainingProductScenarioInvocation completed
              failures =
                [ "live completed PlanId differs from catalogue/current projection"
                | completedTrainingPlanId completed
                    /= ProductMatrix.productProjectionPlanId projection
                ]
                  <> [ "live completed measured digest differs from catalogue"
                     | Report.canonicalCompletedTrainingDigest completed
                         /= productBrowserCatalogueRowMeasuredDigest row
                     ]
                  <> [ "live completed measured result differs from catalogue"
                     | Report.canonicalCompletedTrainingSummary completed
                         /= productBrowserCatalogueRowMeasuredResult row
                     ]
                  <> [ "live completion has no ProductScenario invocation"
                     | isNothing invocation
                     ]
                  <> [ "live invocation run differs from catalogue"
                     | (productScenarioInvocationRunId <$> invocation) /= Just runId
                     ]
                  <> [ "live invocation row differs from catalogue"
                     | (productScenarioInvocationRowId <$> invocation)
                         /= Just (productBrowserCatalogueRowRowId row)
                     ]
                  <> [ "live invocation PlanId differs from current projection"
                     | (productScenarioInvocationPlanId <$> invocation)
                         /= Just (ProductMatrix.productProjectionPlanId projection)
                     ]
                  <> [ "live invocation substrate differs from selected catalogue"
                     | (productScenarioInvocationSubstrate <$> invocation)
                         /= Just substrate
                     ]
          case failures of
            failure : _ ->
              Left
                ( CatalogueLiveEvidenceMismatch
                    (productBrowserCatalogueRowRowId row)
                    failure
                    :| []
                )
            [] ->
              Right
                AdmittedProductBrowserCatalogueRow
                  { admittedCatalogueRowValue = row
                  , admittedCatalogueCompletionValue = completion
                  }

admitExactRow
  :: (HasMinIO m)
  => ProductBrowserCatalogueRow
  -> m
       ( Either
           (NonEmpty ProductBrowserCatalogueError)
           CheckpointStore.AdmittedCompletedCheckpoint
       )
admitExactRow row = do
  admitted <-
    CheckpointStore.admitCheckpointAt
      (productBrowserCatalogueRowExperimentHash row)
      (productBrowserCatalogueRowManifestSha row)
  pure $
    case admitted >>= CheckpointStore.requireAdmittedCompletedCheckpoint of
      Left err ->
        Left
          ( CatalogueLiveAdmissionRejected
              (productBrowserCatalogueRowRowId row)
              err
              :| []
          )
      Right completion -> Right completion

sequenceNonEmptyErrors
  :: [Either (NonEmpty error) value]
  -> Either (NonEmpty error) [value]
sequenceNonEmptyErrors results =
  case NonEmpty.nonEmpty (concatMap (either NonEmpty.toList (const [])) results) of
    Just errors -> Left errors
    Nothing -> Right (rights results)

currentProductProjectionBatch
  :: Substrate
  -> Either ProductBrowserCatalogueError ProductMatrix.ProductProjectionBatch
currentProductProjectionBatch substrate =
  case ProductMatrix.projectProductRows substrate ProductMatrix.allProductRows of
    Failure errors ->
      Left (CatalogueCurrentProjectionRejected (Text.pack (show errors)))
    Success batch -> Right batch

parseCataloguePointer
  :: Text
  -> Either ProductBrowserCatalogueError Text
parseCataloguePointer pointer
  | canonicalSha256 pointer = Right pointer
  | otherwise = Left (CatalogueSelectorMalformed pointer)

-- | Load all immutable catalogue root markers for one experiment and resolve
-- them against the exact candidate manifest set.  A malformed marker or a
-- reference to an absent manifest fails the GC boundary closed.
loadProductBrowserCatalogueGcRoots
  :: (HasMinIO m)
  => Text
  -> [CheckpointManifest]
  -> m
       ( Either
           (NonEmpty ProductBrowserCatalogueError)
           [CheckpointManifest]
       )
loadProductBrowserCatalogueGcRoots experimentHash manifests = do
  let prefix = catalogueGcRootPrefix experimentHash
      bucket = BucketName "jitml-checkpoints"
  listed <- listObjects bucket prefix
  case listed of
    Left err ->
      pure
        ( Left
            (CatalogueGcRootListingFailed experimentHash err :| [])
        )
    Right refs -> do
      roots <- traverse (loadRoot prefix) refs
      pure (fmap List.nub (sequenceNonEmptyErrors roots))
 where
  loadRoot prefix ref =
    case validateRootRef prefix ref of
      Left err -> pure (Left (err :| []))
      Right () -> do
        payload <- minioReadObject ref
        pure $ do
          manifestSha <-
            case payload of
              Left err -> Left (CatalogueGcRootReadFailed ref err :| [])
              Right value
                | canonicalSha256 value -> Right value
                | otherwise ->
                    Left
                      ( CatalogueGcRootMalformed
                          ref
                          "root payload is not one canonical manifest SHA-256"
                          :| []
                      )
          case List.find ((== manifestSha) . manifestContentSha) manifests of
            Nothing ->
              Left (CatalogueGcRootMissingManifest ref manifestSha :| [])
            Just manifest -> Right manifest

  validateRootRef prefix ref
    | objectBucket ref /= BucketName "jitml-checkpoints" =
        Left (CatalogueGcRootMalformed ref "wrong bucket")
    | Just suffix <- Text.stripPrefix prefix (unObjectKey (objectKey ref))
    , canonicalSha256 suffix =
        Right ()
    | otherwise =
        Left
          ( CatalogueGcRootMalformed
              ref
              "root key is not prefix plus one canonical catalogue SHA-256"
          )

productBrowserCatalogueRunId :: ProductBrowserCatalogue -> Text
productBrowserCatalogueRunId = wireRunId . catalogueWireValue

productBrowserCatalogueSubstrate :: ProductBrowserCatalogue -> Substrate
productBrowserCatalogueSubstrate = catalogueSubstrateValue

productBrowserCatalogueSourceJournalDigest :: ProductBrowserCatalogue -> Text
productBrowserCatalogueSourceJournalDigest =
  wireSourceJournalSha . catalogueWireValue

productBrowserCatalogueSha256 :: ProductBrowserCatalogue -> Text
productBrowserCatalogueSha256 = catalogueShaValue

productBrowserCatalogueBytes :: ProductBrowserCatalogue -> ByteString
productBrowserCatalogueBytes = catalogueBytesValue

productBrowserCatalogueRows :: ProductBrowserCatalogue -> [ProductBrowserCatalogueRow]
productBrowserCatalogueRows =
  fmap ProductBrowserCatalogueRow . wireRows . catalogueWireValue

productBrowserCatalogueRowOrdinal :: ProductBrowserCatalogueRow -> Word64
productBrowserCatalogueRowOrdinal = wireRowOrdinal . catalogueRowWireValue

productBrowserCatalogueRowRowId :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowRowId = wireRowId . catalogueRowWireValue

productBrowserCatalogueRowPlanId :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowPlanId = wireRowPlanId . catalogueRowWireValue

productBrowserCatalogueRowExperimentHash :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowExperimentHash = wireRowExperimentHash . catalogueRowWireValue

productBrowserCatalogueRowManifestSha :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowManifestSha = wireRowManifestSha . catalogueRowWireValue

productBrowserCatalogueRowContractDigest :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowContractDigest = wireRowContractSha . catalogueRowWireValue

productBrowserCatalogueRowJournalDigest :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowJournalDigest = wireRowJournalSha . catalogueRowWireValue

productBrowserCatalogueRowMeasuredDigest :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowMeasuredDigest = wireRowMeasuredSha . catalogueRowWireValue

productBrowserCatalogueRowE2ETest :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowE2ETest = wireRowE2ETest . catalogueRowWireValue

productBrowserCatalogueRowDemoPanel :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowDemoPanel = wireRowDemoPanel . catalogueRowWireValue

productBrowserCatalogueRowMeasuredResult :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowMeasuredResult = wireRowMeasuredResult . catalogueRowWireValue

productBrowserCatalogueRowStatus :: ProductBrowserCatalogueRow -> Text
productBrowserCatalogueRowStatus = wireRowStatus . catalogueRowWireValue

publishedProductBrowserCatalogue
  :: PublishedProductBrowserCatalogue
  -> ProductBrowserCatalogue
publishedProductBrowserCatalogue = publishedCatalogueValue

publishedProductBrowserCatalogueSelectorETag
  :: PublishedProductBrowserCatalogue
  -> ETag
publishedProductBrowserCatalogueSelectorETag = publishedSelectorETagValue

admittedProductBrowserCatalogue
  :: AdmittedProductBrowserCatalogue
  -> ProductBrowserCatalogue
admittedProductBrowserCatalogue = admittedCatalogueValue

admittedProductBrowserCatalogueRows
  :: AdmittedProductBrowserCatalogue
  -> [AdmittedProductBrowserCatalogueRow]
admittedProductBrowserCatalogueRows = admittedCatalogueRowsValue

admittedProductBrowserCatalogueRowCatalogueRow
  :: AdmittedProductBrowserCatalogueRow
  -> ProductBrowserCatalogueRow
admittedProductBrowserCatalogueRowCatalogueRow = admittedCatalogueRowValue

admittedProductBrowserCatalogueRowStep
  :: AdmittedProductBrowserCatalogueRow
  -> Word64
admittedProductBrowserCatalogueRowStep =
  manifestStep . admittedRowManifest

admittedProductBrowserCatalogueRowModelFamily
  :: AdmittedProductBrowserCatalogueRow
  -> Text
admittedProductBrowserCatalogueRowModelFamily =
  renderModelFamily . manifestModelFamily . admittedRowManifest

admittedProductBrowserCatalogueRowTensorCount
  :: AdmittedProductBrowserCatalogueRow
  -> Int
admittedProductBrowserCatalogueRowTensorCount =
  length . manifestTensors . admittedRowManifest

admittedProductBrowserCatalogueRowBudget
  :: AdmittedProductBrowserCatalogueRow
  -> Text
admittedProductBrowserCatalogueRowBudget =
  renderTrainingBudget
    . completedTrainingBudget
    . CheckpointStore.admittedCompletedTraining
    . admittedCatalogueCompletionValue

admittedProductBrowserCatalogueRowMeasuredResult
  :: AdmittedProductBrowserCatalogueRow
  -> Text
admittedProductBrowserCatalogueRowMeasuredResult =
  Report.canonicalCompletedTrainingSummary
    . CheckpointStore.admittedCompletedTraining
    . admittedCatalogueCompletionValue

admittedProductBrowserCatalogueRowTensorBoardPrefix
  :: AdmittedProductBrowserCatalogueRow
  -> Text
admittedProductBrowserCatalogueRowTensorBoardPrefix =
  tbrLogPrefix
    . completedTrainingTensorBoard
    . CheckpointStore.admittedCompletedTraining
    . admittedCatalogueCompletionValue

admittedRowManifest
  :: AdmittedProductBrowserCatalogueRow
  -> CheckpointManifest
admittedRowManifest =
  CheckpointStore.admittedCheckpointManifest
    . CheckpointStore.admittedCompletedCheckpoint
    . admittedCatalogueCompletionValue

productBrowserCatalogueSelectorRef :: Substrate -> ObjectRef
productBrowserCatalogueSelectorRef substrate =
  ObjectRef
    catalogueBucket
    ( ObjectKey
        ( catalogueBasePrefix substrate
            <> "/selected"
        )
    )

productBrowserCatalogueObjectRef :: ProductBrowserCatalogue -> ObjectRef
productBrowserCatalogueObjectRef catalogue =
  catalogueObjectRefForSha
    (productBrowserCatalogueSubstrate catalogue)
    (productBrowserCatalogueSha256 catalogue)

catalogueObjectRefForSha :: Substrate -> Text -> ObjectRef
catalogueObjectRefForSha substrate catalogueSha =
  ObjectRef
    catalogueBucket
    ( ObjectKey
        ( catalogueBasePrefix substrate
            <> "/objects/"
            <> catalogueSha
            <> ".json"
        )
    )

catalogueBasePrefix :: Substrate -> Text
catalogueBasePrefix substrate =
  "product-browser-catalogues/v1/" <> renderSubstrate substrate

catalogueGcRootPrefix :: Text -> Text
catalogueGcRootPrefix experimentHash =
  experimentHash <> "/pointers/browser-catalogues/"

catalogueGcRootRef
  :: ProductBrowserCatalogue
  -> ProductBrowserCatalogueRow
  -> ObjectRef
catalogueGcRootRef catalogue row =
  ObjectRef
    (BucketName "jitml-checkpoints")
    ( ObjectKey
        ( catalogueGcRootPrefix (productBrowserCatalogueRowExperimentHash row)
            <> productBrowserCatalogueSha256 catalogue
        )
    )

-- | Exact browser-process input envelope.  Unlike the immutable catalogue
-- object, this transport envelope can include the already-computed external
-- content address without creating a self-hash paradox.
renderProductBrowserCatalogueInput :: ProductBrowserCatalogue -> Text
renderProductBrowserCatalogueInput catalogue =
  Text.Encoding.decodeUtf8
    ( LazyByteString.toStrict
        ( encode
            ( object
                [ "format" .= catalogueInputFormat
                , "version" .= catalogueWireVersion
                , "run_id" .= productBrowserCatalogueRunId catalogue
                , "substrate"
                    .= renderSubstrate (productBrowserCatalogueSubstrate catalogue)
                , "catalogue_sha256" .= productBrowserCatalogueSha256 catalogue
                , "source_journal_sha256"
                    .= productBrowserCatalogueSourceJournalDigest catalogue
                , "rows" .= wireRows (catalogueWireValue catalogue)
                ]
            )
        )
    )

renderModelFamily :: ModelFamily -> Text
renderModelFamily family =
  case family of
    GenericModelFamily -> "generic"
    SupervisedModelFamily -> "supervised"
    ReinforcementLearningPolicyFamily -> "rl"
    AlphaZeroPolicyValueFamily -> "alphazero"
    HyperparameterTuningFamily -> "tuning"

canonicalSha256 :: Text -> Bool
canonicalSha256 value =
  Text.length value == 64
    && Text.all
      ( \character ->
          isDigit character
            || (character >= 'a' && character <= 'f')
      )
      value

safeToken :: Text -> Bool
safeToken value =
  not (Text.null value)
    && Text.length value <= 4096
    && Text.strip value == value
    && not (Text.any isControl value)

duplicates :: [Text] -> [Text]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]

sha256Bytes :: ByteString -> Text
sha256Bytes =
  Text.pack
    . concatMap byteHex
    . ByteString.unpack
    . SHA256.hash
 where
  byteHex byte =
    let digits = "0123456789abcdef"
        value = fromIntegral byte
     in [digits !! (value `div` 16), digits !! (value `mod` 16)]

showText :: (Show value) => value -> Text
showText = Text.pack . show
