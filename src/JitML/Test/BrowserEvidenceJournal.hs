{-# LANGUAGE OverloadedStrings #-}

-- | Authenticated cross-process results for the live ProductRow browser gate.
--
-- The browser receives a fresh, command-owned signing capability that is
-- independent of the ProductScenario integration capability.  Its output is
-- treated as an untrusted wire value: the parent authenticates the exact
-- length-delimited material and then joins every row against the already
-- validated browser catalogue.  Only the opaque 'BrowserEvidenceReport' can
-- cross that refinement boundary.
module JitML.Test.BrowserEvidenceJournal
  ( BrowserEvidenceExpectation
  , BrowserEvidenceExpectedRow (..)
  , BrowserEvidenceJournalError (..)
  , BrowserEvidenceJournalKey
  , BrowserEvidenceObservation (..)
  , BrowserEvidenceReport
  , BrowserEvidenceResult
  , BrowserEvidenceStatus (..)
  , browserEvidenceCanonicalRowCount
  , browserEvidenceExpectation
  , browserEvidenceExpectedCatalogueSha256
  , browserEvidenceExpectedRows
  , browserEvidenceExpectedRunId
  , browserEvidenceExpectedSourceJournalSha256
  , browserEvidenceExpectedSubstrate
  , browserEvidenceJournalWireVersion
  , browserEvidenceReportAllPassed
  , browserEvidenceReportEntries
  , browserEvidenceResultDetail
  , browserEvidenceResultE2ETest
  , browserEvidenceResultExperimentHash
  , browserEvidenceResultManifestSha256
  , browserEvidenceResultOrdinal
  , browserEvidenceResultPlanId
  , browserEvidenceResultRowId
  , browserEvidenceResultStatus
  , generateBrowserEvidenceJournalKey
  , parseBrowserEvidenceJournalKey
  , readBrowserEvidenceJournal
  , renderBrowserEvidenceJournalKey
  , renderBrowserEvidenceStatus
  , writeBrowserEvidenceJournalAtomic
  , writeInitialBrowserEvidenceJournalAtomic
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
import Data.Bits (xor, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isControl, isDigit, ord)
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64, Word8)
import System.Directory
  ( createDirectoryIfMissing
  , removeFile
  , renameFile
  )
import System.FilePath (takeDirectory, takeFileName)
import System.IO
  ( IOMode (ReadMode)
  , hClose
  , hFlush
  , openBinaryTempFile
  , withBinaryFile
  )
import System.IO.Error (isDoesNotExistError)

import JitML.Substrate (Substrate, parseSubstrate, renderSubstrate)

browserEvidenceJournalWireVersion :: Word64
browserEvidenceJournalWireVersion = 1

browserEvidenceCanonicalRowCount :: Int
browserEvidenceCanonicalRowCount = 55

browserEvidenceJournalFormat :: Text
browserEvidenceJournalFormat = "jitml-browser-result-journal"

data BrowserEvidenceStatus
  = BrowserPassed
  | BrowserFailed
  | BrowserNotRun
  deriving stock (Eq, Show)

renderBrowserEvidenceStatus :: BrowserEvidenceStatus -> Text
renderBrowserEvidenceStatus BrowserPassed = "Passed"
renderBrowserEvidenceStatus BrowserFailed = "Failed"
renderBrowserEvidenceStatus BrowserNotRun = "NotRun"

parseBrowserEvidenceStatus :: Text -> Maybe BrowserEvidenceStatus
parseBrowserEvidenceStatus "Passed" = Just BrowserPassed
parseBrowserEvidenceStatus "Failed" = Just BrowserFailed
parseBrowserEvidenceStatus "NotRun" = Just BrowserNotRun
parseBrowserEvidenceStatus _ = Nothing

data BrowserEvidenceExpectedRow = BrowserEvidenceExpectedRow
  { expectedBrowserOrdinal :: !Word64
  , expectedBrowserRowId :: !Text
  , expectedBrowserPlanId :: !Text
  , expectedBrowserExperimentHash :: !Text
  , expectedBrowserManifestSha256 :: !Text
  , expectedBrowserE2ETest :: !Text
  }
  deriving stock (Eq, Show)

data BrowserEvidenceExpectation = BrowserEvidenceExpectation
  { expectedBrowserRunIdValue :: !Text
  , expectedBrowserSubstrateValue :: !Substrate
  , expectedBrowserCatalogueSha256Value :: !Text
  , expectedBrowserSourceJournalSha256Value :: !Text
  , expectedBrowserRowsValue :: ![BrowserEvidenceExpectedRow]
  }
  deriving stock (Eq, Show)

data BrowserEvidenceObservation = BrowserEvidenceObservation
  { browserObservationStatus :: !BrowserEvidenceStatus
  , browserObservationDetail :: !Text
  }
  deriving stock (Eq, Show)

data BrowserEvidenceResult = BrowserEvidenceResult
  { browserResultOrdinalValue :: !Word64
  , browserResultRowIdValue :: !Text
  , browserResultPlanIdValue :: !Text
  , browserResultExperimentHashValue :: !Text
  , browserResultManifestSha256Value :: !Text
  , browserResultE2ETestValue :: !Text
  , browserResultStatusValue :: !BrowserEvidenceStatus
  , browserResultDetailValue :: !Text
  }
  deriving stock (Eq, Show)

newtype BrowserEvidenceReport = BrowserEvidenceReport [BrowserEvidenceResult]
  deriving stock (Eq, Show)

newtype BrowserEvidenceJournalKey = BrowserEvidenceJournalKey ByteString
  deriving stock (Eq)

data BrowserEvidenceJournalError
  = BrowserEvidenceJournalMissing !FilePath
  | BrowserEvidenceJournalIOFailure !FilePath !Text
  | BrowserEvidenceJournalMalformed !FilePath !Text
  | BrowserEvidenceJournalFormatMismatch !Text
  | BrowserEvidenceJournalVersionMismatch !Word64 !Word64
  | BrowserEvidenceJournalRunIdMismatch !Text !Text
  | BrowserEvidenceJournalSubstrateMismatch !Substrate !Text
  | BrowserEvidenceJournalCatalogueMismatch !Text !Text
  | BrowserEvidenceJournalSourceMismatch !Text !Text
  | BrowserEvidenceJournalAuthenticationTagInvalid !Text
  | BrowserEvidenceJournalAuthenticationFailed
  | BrowserEvidenceJournalKeyReadFailed !Text
  | BrowserEvidenceJournalKeyLengthInvalid !Int
  | BrowserEvidenceJournalKeyEncodingInvalid !Text
  | BrowserEvidenceJournalRowCountMismatch !Int !Int
  | BrowserEvidenceJournalRowOrderMismatch ![Text] ![Text]
  | BrowserEvidenceJournalMissingRow !Text !Text
  | BrowserEvidenceJournalDuplicateRow !Text
  | BrowserEvidenceJournalOrphanRow !Text !Text
  | BrowserEvidenceJournalOrdinalMismatch !Text !Word64 !Word64
  | BrowserEvidenceJournalPlanMismatch !Text !Text !Text
  | BrowserEvidenceJournalExperimentMismatch !Text !Text !Text
  | BrowserEvidenceJournalManifestMismatch !Text !Text !Text
  | BrowserEvidenceJournalE2ETestMismatch !Text !Text !Text
  | BrowserEvidenceJournalStatusInvalid !Word64 !Text
  | BrowserEvidenceJournalDetailInvalid !Word64 !Text
  | BrowserEvidenceExpectationIdentityInvalid !Text !Text
  deriving stock (Eq, Show)

data BrowserEvidenceJournalWire = BrowserEvidenceJournalWire
  { wireFormat :: !Text
  , wireVersion :: !Word64
  , wireRunId :: !Text
  , wireSubstrate :: !Text
  , wireCatalogueSha256 :: !Text
  , wireSourceJournalSha256 :: !Text
  , wireRunReceiptHmacSha256 :: !Text
  , wireRows :: ![BrowserEvidenceJournalRowWire]
  }
  deriving stock (Eq, Show)

data BrowserEvidenceJournalRowWire = BrowserEvidenceJournalRowWire
  { wireRowOrdinal :: !Word64
  , wireRowId :: !Text
  , wireRowPlanId :: !Text
  , wireRowExperimentHash :: !Text
  , wireRowManifestSha256 :: !Text
  , wireRowE2ETest :: !Text
  , wireRowStatus :: !Text
  , wireRowDetail :: !Text
  }
  deriving stock (Eq, Show)

instance ToJSON BrowserEvidenceJournalWire where
  toJSON journal =
    object
      [ "format" .= wireFormat journal
      , "version" .= wireVersion journal
      , "run_id" .= wireRunId journal
      , "substrate" .= wireSubstrate journal
      , "catalogue_sha256" .= wireCatalogueSha256 journal
      , "source_journal_sha256" .= wireSourceJournalSha256 journal
      , "run_receipt_hmac_sha256" .= wireRunReceiptHmacSha256 journal
      , "rows" .= wireRows journal
      ]

instance FromJSON BrowserEvidenceJournalWire where
  parseJSON =
    withObject "BrowserEvidenceJournal" $ \record -> do
      requireExactFields
        "BrowserEvidenceJournal"
        [ "format"
        , "version"
        , "run_id"
        , "substrate"
        , "catalogue_sha256"
        , "source_journal_sha256"
        , "run_receipt_hmac_sha256"
        , "rows"
        ]
        record
      BrowserEvidenceJournalWire
        <$> record .: "format"
        <*> record .: "version"
        <*> record .: "run_id"
        <*> record .: "substrate"
        <*> record .: "catalogue_sha256"
        <*> record .: "source_journal_sha256"
        <*> record .: "run_receipt_hmac_sha256"
        <*> record .: "rows"

instance ToJSON BrowserEvidenceJournalRowWire where
  toJSON row =
    object
      [ "ordinal" .= wireRowOrdinal row
      , "row_id" .= wireRowId row
      , "plan_id" .= wireRowPlanId row
      , "experiment_hash" .= wireRowExperimentHash row
      , "manifest_sha256" .= wireRowManifestSha256 row
      , "e2e_test" .= wireRowE2ETest row
      , "status" .= wireRowStatus row
      , "detail" .= wireRowDetail row
      ]

instance FromJSON BrowserEvidenceJournalRowWire where
  parseJSON =
    withObject "BrowserEvidenceJournalRow" $ \record -> do
      requireExactFields
        "BrowserEvidenceJournalRow"
        [ "ordinal"
        , "row_id"
        , "plan_id"
        , "experiment_hash"
        , "manifest_sha256"
        , "e2e_test"
        , "status"
        , "detail"
        ]
        record
      BrowserEvidenceJournalRowWire
        <$> record .: "ordinal"
        <*> record .: "row_id"
        <*> record .: "plan_id"
        <*> record .: "experiment_hash"
        <*> record .: "manifest_sha256"
        <*> record .: "e2e_test"
        <*> record .: "status"
        <*> record .: "detail"

requireExactFields :: String -> [Text] -> Object -> Parser ()
requireExactFields label expected record =
  unless (null unexpected) $
    fail
      ( label
          <> " has unexpected fields: "
          <> show unexpected
      )
 where
  expectedKeys = fmap AesonKey.fromText expected
  unexpected =
    List.sort
      [ AesonKey.toText key
      | key <- AesonKeyMap.keys record
      , key `notElem` expectedKeys
      ]

browserEvidenceExpectation
  :: Text
  -> Substrate
  -> Text
  -> Text
  -> [BrowserEvidenceExpectedRow]
  -> Either (NonEmpty BrowserEvidenceJournalError) BrowserEvidenceExpectation
browserEvidenceExpectation runId substrate catalogueSha sourceJournalSha rows =
  case NonEmpty.nonEmpty failures of
    Just errors -> Left errors
    Nothing ->
      Right
        BrowserEvidenceExpectation
          { expectedBrowserRunIdValue = runId
          , expectedBrowserSubstrateValue = substrate
          , expectedBrowserCatalogueSha256Value = catalogueSha
          , expectedBrowserSourceJournalSha256Value = sourceJournalSha
          , expectedBrowserRowsValue = rows
          }
 where
  failures =
    identityFailures "run_id" runId
      <> digestFailures "catalogue_sha256" catalogueSha
      <> digestFailures "source_journal_sha256" sourceJournalSha
      <> [ BrowserEvidenceJournalRowCountMismatch
             browserEvidenceCanonicalRowCount
             (length rows)
         | length rows /= browserEvidenceCanonicalRowCount
         ]
      <> concat
        [ expectedRowFailures index row
        | (index, row) <- zip [(0 :: Word64) ..] rows
        ]
      <> [ BrowserEvidenceJournalDuplicateRow rowId
         | rowId <- repeatedTexts (fmap expectedBrowserRowId rows)
         ]

expectedRowFailures
  :: Word64
  -> BrowserEvidenceExpectedRow
  -> [BrowserEvidenceJournalError]
expectedRowFailures index row =
  [ BrowserEvidenceJournalOrdinalMismatch
      (expectedBrowserRowId row)
      index
      (expectedBrowserOrdinal row)
  | expectedBrowserOrdinal row /= index
  ]
    <> identityFailures "row_id" (expectedBrowserRowId row)
    <> digestFailures "plan_id" (expectedBrowserPlanId row)
    <> identityFailures "experiment_hash" (expectedBrowserExperimentHash row)
    <> digestFailures "manifest_sha256" (expectedBrowserManifestSha256 row)
    <> identityFailures "e2e_test" (expectedBrowserE2ETest row)

identityFailures :: Text -> Text -> [BrowserEvidenceJournalError]
identityFailures label value =
  [ BrowserEvidenceExpectationIdentityInvalid label value
  | Text.null value
      || Text.length value > 4096
      || Text.strip value /= value
      || Text.any isControl value
  ]

digestFailures :: Text -> Text -> [BrowserEvidenceJournalError]
digestFailures label value =
  [ BrowserEvidenceExpectationIdentityInvalid label value
  | not (isSha256 value)
  ]

browserEvidenceExpectedRunId :: BrowserEvidenceExpectation -> Text
browserEvidenceExpectedRunId = expectedBrowserRunIdValue

browserEvidenceExpectedSubstrate :: BrowserEvidenceExpectation -> Substrate
browserEvidenceExpectedSubstrate = expectedBrowserSubstrateValue

browserEvidenceExpectedCatalogueSha256 :: BrowserEvidenceExpectation -> Text
browserEvidenceExpectedCatalogueSha256 = expectedBrowserCatalogueSha256Value

browserEvidenceExpectedSourceJournalSha256 :: BrowserEvidenceExpectation -> Text
browserEvidenceExpectedSourceJournalSha256 = expectedBrowserSourceJournalSha256Value

browserEvidenceExpectedRows
  :: BrowserEvidenceExpectation
  -> [BrowserEvidenceExpectedRow]
browserEvidenceExpectedRows = expectedBrowserRowsValue

browserEvidenceReportEntries :: BrowserEvidenceReport -> [BrowserEvidenceResult]
browserEvidenceReportEntries (BrowserEvidenceReport rows) = rows

browserEvidenceReportAllPassed :: BrowserEvidenceReport -> Bool
browserEvidenceReportAllPassed (BrowserEvidenceReport rows) =
  length rows == browserEvidenceCanonicalRowCount
    && all ((== BrowserPassed) . browserEvidenceResultStatus) rows

browserEvidenceResultOrdinal :: BrowserEvidenceResult -> Word64
browserEvidenceResultOrdinal = browserResultOrdinalValue

browserEvidenceResultRowId :: BrowserEvidenceResult -> Text
browserEvidenceResultRowId = browserResultRowIdValue

browserEvidenceResultPlanId :: BrowserEvidenceResult -> Text
browserEvidenceResultPlanId = browserResultPlanIdValue

browserEvidenceResultExperimentHash :: BrowserEvidenceResult -> Text
browserEvidenceResultExperimentHash = browserResultExperimentHashValue

browserEvidenceResultManifestSha256 :: BrowserEvidenceResult -> Text
browserEvidenceResultManifestSha256 = browserResultManifestSha256Value

browserEvidenceResultE2ETest :: BrowserEvidenceResult -> Text
browserEvidenceResultE2ETest = browserResultE2ETestValue

browserEvidenceResultStatus :: BrowserEvidenceResult -> BrowserEvidenceStatus
browserEvidenceResultStatus = browserResultStatusValue

browserEvidenceResultDetail :: BrowserEvidenceResult -> Text
browserEvidenceResultDetail = browserResultDetailValue

generateBrowserEvidenceJournalKey
  :: IO (Either BrowserEvidenceJournalError BrowserEvidenceJournalKey)
generateBrowserEvidenceJournalKey = do
  generated <-
    try
      ( withBinaryFile "/dev/urandom" ReadMode $ \handle ->
          ByteString.hGet handle browserEvidenceJournalKeyBytes
      )
  pure $
    case generated of
      Left exception ->
        Left
          ( BrowserEvidenceJournalKeyReadFailed
              (Text.pack (show (exception :: IOException)))
          )
      Right bytes
        | ByteString.length bytes == browserEvidenceJournalKeyBytes ->
            Right (BrowserEvidenceJournalKey bytes)
        | otherwise ->
            Left (BrowserEvidenceJournalKeyLengthInvalid (ByteString.length bytes))

renderBrowserEvidenceJournalKey :: BrowserEvidenceJournalKey -> Text
renderBrowserEvidenceJournalKey (BrowserEvidenceJournalKey bytes) = hexBytes bytes

parseBrowserEvidenceJournalKey
  :: Text
  -> Either BrowserEvidenceJournalError BrowserEvidenceJournalKey
parseBrowserEvidenceJournalKey encoded
  | Text.length encoded /= browserEvidenceJournalKeyBytes * 2 =
      Left (BrowserEvidenceJournalKeyLengthInvalid (Text.length encoded))
  | not (Text.all isLowerHex encoded) =
      Left
        ( BrowserEvidenceJournalKeyEncodingInvalid
            "browser journal key must contain only lowercase hexadecimal characters"
        )
  | otherwise =
      BrowserEvidenceJournalKey . ByteString.pack
        <$> traverse decodePair (pairs (Text.unpack encoded))
 where
  decodePair [high, low] = Right (hexNibble high * 16 + hexNibble low)
  decodePair _ =
    Left
      ( BrowserEvidenceJournalKeyEncodingInvalid
          "browser journal key contains an incomplete hexadecimal byte"
      )

writeInitialBrowserEvidenceJournalAtomic
  :: BrowserEvidenceJournalKey
  -> FilePath
  -> BrowserEvidenceExpectation
  -> IO (Either (NonEmpty BrowserEvidenceJournalError) ())
writeInitialBrowserEvidenceJournalAtomic key path expectation =
  writeBrowserEvidenceJournalAtomic
    key
    path
    expectation
    ( replicate
        browserEvidenceCanonicalRowCount
        ( BrowserEvidenceObservation
            BrowserNotRun
            "Playwright invocation did not produce a final row result"
        )
    )

writeBrowserEvidenceJournalAtomic
  :: BrowserEvidenceJournalKey
  -> FilePath
  -> BrowserEvidenceExpectation
  -> [BrowserEvidenceObservation]
  -> IO (Either (NonEmpty BrowserEvidenceJournalError) ())
writeBrowserEvidenceJournalAtomic key path expectation observations =
  case NonEmpty.nonEmpty failures of
    Just errors -> pure (Left errors)
    Nothing -> do
      let unsigned =
            BrowserEvidenceJournalWire
              { wireFormat = browserEvidenceJournalFormat
              , wireVersion = browserEvidenceJournalWireVersion
              , wireRunId = browserEvidenceExpectedRunId expectation
              , wireSubstrate =
                  renderSubstrate (browserEvidenceExpectedSubstrate expectation)
              , wireCatalogueSha256 =
                  browserEvidenceExpectedCatalogueSha256 expectation
              , wireSourceJournalSha256 =
                  browserEvidenceExpectedSourceJournalSha256 expectation
              , wireRunReceiptHmacSha256 = ""
              , wireRows = zipWith expectedRowWire expectedRows observations
              }
          journal =
            unsigned
              { wireRunReceiptHmacSha256 =
                  signBrowserEvidenceJournal key (browserEvidenceJournalMaterial unsigned)
              }
      written <- writeJournalAtomic path (encode journal)
      pure $
        case written of
          Left err -> Left (err :| [])
          Right () -> Right ()
 where
  expectedRows = browserEvidenceExpectedRows expectation
  failures =
    [ BrowserEvidenceJournalRowCountMismatch
        (length expectedRows)
        (length observations)
    | length observations /= length expectedRows
    ]
      <> concat
        [ observationFailures ordinal observation
        | (ordinal, observation) <- zip [(0 :: Word64) ..] observations
        ]

expectedRowWire
  :: BrowserEvidenceExpectedRow
  -> BrowserEvidenceObservation
  -> BrowserEvidenceJournalRowWire
expectedRowWire expected observation =
  BrowserEvidenceJournalRowWire
    { wireRowOrdinal = expectedBrowserOrdinal expected
    , wireRowId = expectedBrowserRowId expected
    , wireRowPlanId = expectedBrowserPlanId expected
    , wireRowExperimentHash = expectedBrowserExperimentHash expected
    , wireRowManifestSha256 = expectedBrowserManifestSha256 expected
    , wireRowE2ETest = expectedBrowserE2ETest expected
    , wireRowStatus = renderBrowserEvidenceStatus (browserObservationStatus observation)
    , wireRowDetail = browserObservationDetail observation
    }

readBrowserEvidenceJournal
  :: BrowserEvidenceJournalKey
  -> FilePath
  -> BrowserEvidenceExpectation
  -> IO
       ( Either
           (NonEmpty BrowserEvidenceJournalError)
           BrowserEvidenceReport
       )
readBrowserEvidenceJournal key path expectation = do
  loaded <- try (LazyByteString.readFile path)
  case loaded of
    Left exception
      | isDoesNotExistError exception ->
          pure (Left (BrowserEvidenceJournalMissing path :| []))
      | otherwise ->
          pure
            ( Left
                ( BrowserEvidenceJournalIOFailure
                    path
                    (Text.pack (show (exception :: IOException)))
                    :| []
                )
            )
    Right bytes ->
      case eitherDecode bytes of
        Left err ->
          pure
            ( Left
                ( BrowserEvidenceJournalMalformed path (Text.pack err)
                    :| []
                )
            )
        Right journal -> pure (refineBrowserEvidenceJournal key expectation journal)

refineBrowserEvidenceJournal
  :: BrowserEvidenceJournalKey
  -> BrowserEvidenceExpectation
  -> BrowserEvidenceJournalWire
  -> Either (NonEmpty BrowserEvidenceJournalError) BrowserEvidenceReport
refineBrowserEvidenceJournal key expectation journal =
  case NonEmpty.nonEmpty failures of
    Just errors -> Left errors
    Nothing ->
      case traverse refineRow (wireRows journal) of
        Nothing ->
          Left
            ( BrowserEvidenceJournalMalformed
                "<refined>"
                "validated status unexpectedly failed to refine"
                :| []
            )
        Just rows -> Right (BrowserEvidenceReport rows)
 where
  expectedRows = browserEvidenceExpectedRows expectation
  observedRows = wireRows journal
  expectedRowIds = fmap expectedBrowserRowId expectedRows
  observedRowIds = fmap wireRowId observedRows
  failures =
    topLevelFailures key expectation journal
      <> [ BrowserEvidenceJournalRowCountMismatch
             (length expectedRows)
             (length observedRows)
         | length observedRows /= length expectedRows
         ]
      <> [ BrowserEvidenceJournalRowOrderMismatch expectedRowIds observedRowIds
         | observedRowIds /= expectedRowIds
         ]
      <> [ BrowserEvidenceJournalMissingRow
             (expectedBrowserRowId expected)
             (expectedBrowserPlanId expected)
         | expected <- expectedRows
         , expectedBrowserRowId expected `notElem` observedRowIds
         ]
      <> [ BrowserEvidenceJournalDuplicateRow rowId
         | rowId <- repeatedTexts observedRowIds
         ]
      <> [ BrowserEvidenceJournalOrphanRow
             (wireRowId observed)
             (wireRowPlanId observed)
         | observed <- observedRows
         , wireRowId observed `notElem` expectedRowIds
         ]
      <> concat
        [ observedRowFailures expected observed
        | (expected, observed) <- zip expectedRows observedRows
        ]
      <> concatMap wireObservationFailures observedRows

topLevelFailures
  :: BrowserEvidenceJournalKey
  -> BrowserEvidenceExpectation
  -> BrowserEvidenceJournalWire
  -> [BrowserEvidenceJournalError]
topLevelFailures key expectation journal =
  [ BrowserEvidenceJournalFormatMismatch (wireFormat journal)
  | wireFormat journal /= browserEvidenceJournalFormat
  ]
    <> [ BrowserEvidenceJournalVersionMismatch
           browserEvidenceJournalWireVersion
           (wireVersion journal)
       | wireVersion journal /= browserEvidenceJournalWireVersion
       ]
    <> [ BrowserEvidenceJournalRunIdMismatch
           (browserEvidenceExpectedRunId expectation)
           (wireRunId journal)
       | wireRunId journal /= browserEvidenceExpectedRunId expectation
       ]
    <> [ BrowserEvidenceJournalSubstrateMismatch
           (browserEvidenceExpectedSubstrate expectation)
           (wireSubstrate journal)
       | parseSubstrate (wireSubstrate journal)
           /= Just (browserEvidenceExpectedSubstrate expectation)
       ]
    <> [ BrowserEvidenceJournalCatalogueMismatch
           (browserEvidenceExpectedCatalogueSha256 expectation)
           (wireCatalogueSha256 journal)
       | wireCatalogueSha256 journal
           /= browserEvidenceExpectedCatalogueSha256 expectation
       ]
    <> [ BrowserEvidenceJournalSourceMismatch
           (browserEvidenceExpectedSourceJournalSha256 expectation)
           (wireSourceJournalSha256 journal)
       | wireSourceJournalSha256 journal
           /= browserEvidenceExpectedSourceJournalSha256 expectation
       ]
    <> authenticationFailures key journal

authenticationFailures
  :: BrowserEvidenceJournalKey
  -> BrowserEvidenceJournalWire
  -> [BrowserEvidenceJournalError]
authenticationFailures key journal
  | not (isSha256 observedTag) =
      [ BrowserEvidenceJournalAuthenticationTagInvalid
          "browser journal HMAC must be exactly 64 lowercase hexadecimal characters"
      ]
  | constantTimeEqual
      (Text.Encoding.encodeUtf8 expectedTag)
      (Text.Encoding.encodeUtf8 observedTag) =
      []
  | otherwise = [BrowserEvidenceJournalAuthenticationFailed]
 where
  observedTag = wireRunReceiptHmacSha256 journal
  expectedTag = signBrowserEvidenceJournal key (browserEvidenceJournalMaterial journal)

observedRowFailures
  :: BrowserEvidenceExpectedRow
  -> BrowserEvidenceJournalRowWire
  -> [BrowserEvidenceJournalError]
observedRowFailures expected observed =
  [ BrowserEvidenceJournalOrdinalMismatch
      (expectedBrowserRowId expected)
      (expectedBrowserOrdinal expected)
      (wireRowOrdinal observed)
  | wireRowOrdinal observed /= expectedBrowserOrdinal expected
  ]
    <> [ BrowserEvidenceJournalPlanMismatch
           (expectedBrowserRowId expected)
           (expectedBrowserPlanId expected)
           (wireRowPlanId observed)
       | wireRowPlanId observed /= expectedBrowserPlanId expected
       ]
    <> [ BrowserEvidenceJournalExperimentMismatch
           (expectedBrowserRowId expected)
           (expectedBrowserExperimentHash expected)
           (wireRowExperimentHash observed)
       | wireRowExperimentHash observed /= expectedBrowserExperimentHash expected
       ]
    <> [ BrowserEvidenceJournalManifestMismatch
           (expectedBrowserRowId expected)
           (expectedBrowserManifestSha256 expected)
           (wireRowManifestSha256 observed)
       | wireRowManifestSha256 observed /= expectedBrowserManifestSha256 expected
       ]
    <> [ BrowserEvidenceJournalE2ETestMismatch
           (expectedBrowserRowId expected)
           (expectedBrowserE2ETest expected)
           (wireRowE2ETest observed)
       | wireRowE2ETest observed /= expectedBrowserE2ETest expected
       ]

wireObservationFailures
  :: BrowserEvidenceJournalRowWire
  -> [BrowserEvidenceJournalError]
wireObservationFailures row =
  case parseBrowserEvidenceStatus (wireRowStatus row) of
    Nothing ->
      [ BrowserEvidenceJournalStatusInvalid
          (wireRowOrdinal row)
          (wireRowStatus row)
      ]
    Just status -> observationFailures (wireRowOrdinal row) (BrowserEvidenceObservation status (wireRowDetail row))

observationFailures
  :: Word64
  -> BrowserEvidenceObservation
  -> [BrowserEvidenceJournalError]
observationFailures ordinal observation =
  [ BrowserEvidenceJournalDetailInvalid ordinal detail
  | not (validDetail (browserObservationStatus observation) detail)
  ]
 where
  detail = browserObservationDetail observation

validDetail :: BrowserEvidenceStatus -> Text -> Bool
validDetail BrowserPassed detail = Text.null detail
validDetail BrowserFailed detail = validFailureDetail detail
validDetail BrowserNotRun detail = validFailureDetail detail

validFailureDetail :: Text -> Bool
validFailureDetail detail =
  not (Text.null detail)
    && detail == Text.strip detail
    && Text.length detail <= 4096
    && not (Text.any isControl detail)

refineRow :: BrowserEvidenceJournalRowWire -> Maybe BrowserEvidenceResult
refineRow row = do
  status <- parseBrowserEvidenceStatus (wireRowStatus row)
  pure
    BrowserEvidenceResult
      { browserResultOrdinalValue = wireRowOrdinal row
      , browserResultRowIdValue = wireRowId row
      , browserResultPlanIdValue = wireRowPlanId row
      , browserResultExperimentHashValue = wireRowExperimentHash row
      , browserResultManifestSha256Value = wireRowManifestSha256 row
      , browserResultE2ETestValue = wireRowE2ETest row
      , browserResultStatusValue = status
      , browserResultDetailValue = wireRowDetail row
      }

browserEvidenceJournalMaterial :: BrowserEvidenceJournalWire -> Text
browserEvidenceJournalMaterial journal =
  Text.concat
    ( [ materialField "domain" "jitml-browser-result-journal-hmac-v1"
      , materialField "format" (wireFormat journal)
      , materialField "version" (showText (wireVersion journal))
      , materialField "run_id" (wireRunId journal)
      , materialField "substrate" (wireSubstrate journal)
      , materialField "catalogue_sha256" (wireCatalogueSha256 journal)
      , materialField "source_journal_sha256" (wireSourceJournalSha256 journal)
      , materialField "row_count" (showText (length (wireRows journal)))
      ]
        <> concatMap rowMaterial (wireRows journal)
    )
 where
  rowMaterial row =
    [ materialField "ordinal" (showText (wireRowOrdinal row))
    , materialField "row_id" (wireRowId row)
    , materialField "plan_id" (wireRowPlanId row)
    , materialField "experiment_hash" (wireRowExperimentHash row)
    , materialField "manifest_sha256" (wireRowManifestSha256 row)
    , materialField "e2e_test" (wireRowE2ETest row)
    , materialField "status" (wireRowStatus row)
    , materialField "detail" (wireRowDetail row)
    ]

materialField :: Text -> Text -> Text
materialField label value =
  label
    <> "="
    <> showText (ByteString.length (Text.Encoding.encodeUtf8 value))
    <> ":"
    <> value
    <> "\n"

signBrowserEvidenceJournal :: BrowserEvidenceJournalKey -> Text -> Text
signBrowserEvidenceJournal (BrowserEvidenceJournalKey key) material =
  hexBytes (hmacSha256 key (Text.Encoding.encodeUtf8 material))

writeJournalAtomic
  :: FilePath
  -> LazyByteString.ByteString
  -> IO (Either BrowserEvidenceJournalError ())
writeJournalAtomic path bytes = do
  let directory = takeDirectory path
  attempted <-
    try $ do
      createDirectoryIfMissing True directory
      (temporaryPath, handle) <- openBinaryTempFile directory (takeFileName path <> ".tmp")
      let cleanup = do
            hClose handle
            removeFile temporaryPath
      (do LazyByteString.hPut handle bytes; hFlush handle; hClose handle)
        `onException` cleanup
      renameFile temporaryPath path
  pure $
    case attempted of
      Left exception ->
        Left
          ( BrowserEvidenceJournalIOFailure
              path
              (Text.pack (show (exception :: IOException)))
          )
      Right () -> Right ()

browserEvidenceJournalKeyBytes :: Int
browserEvidenceJournalKeyBytes = 32

sha256BlockBytes :: Int
sha256BlockBytes = 64

hmacSha256 :: ByteString -> ByteString -> ByteString
hmacSha256 key message =
  SHA256.hash (outerPad <> SHA256.hash (innerPad <> message))
 where
  blockKey =
    ByteString.take
      sha256BlockBytes
      (key <> ByteString.replicate sha256BlockBytes 0)
  innerPad = ByteString.map (`xor` 0x36) blockKey
  outerPad = ByteString.map (`xor` 0x5c) blockKey

constantTimeEqual :: ByteString -> ByteString -> Bool
constantTimeEqual left right =
  ByteString.length left == ByteString.length right
    && List.foldl' (.|.) (0 :: Word8) (ByteString.zipWith xor left right) == 0
{-# NOINLINE constantTimeEqual #-}

isSha256 :: Text -> Bool
isSha256 value = Text.length value == 64 && Text.all isLowerHex value

isLowerHex :: Char -> Bool
isLowerHex character =
  isDigit character || ('a' <= character && character <= 'f')

hexNibble :: Char -> Word8
hexNibble character
  | isDigit character = fromIntegral (ord character - ord '0')
  | otherwise = fromIntegral (ord character - ord 'a' + 10)

pairs :: [value] -> [[value]]
pairs [] = []
pairs (first : second : remaining) = [first, second] : pairs remaining
pairs remaining = [remaining]

repeatedTexts :: [Text] -> [Text]
repeatedTexts values =
  [ value
  | group@(value : _) <- List.group (List.sort values)
  , length group > 1
  ]

showText :: (Show value) => value -> Text
showText = Text.pack . show

hexBytes :: ByteString -> Text
hexBytes = Text.pack . concatMap byteHex . ByteString.unpack
 where
  byteHex byte =
    let alphabet = "0123456789abcdef"
        value = fromIntegral byte
     in [ alphabet !! (value `div` 16)
        , alphabet !! (value `mod` 16)
        ]
