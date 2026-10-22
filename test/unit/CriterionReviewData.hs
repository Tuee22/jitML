{-# LANGUAGE OverloadedStrings #-}

module CriterionReviewData (criterionReviewDataTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Codec.Serialise (serialise)
import Control.Exception (AsyncException (UserInterrupt), throw, try)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Product.CriterionReview qualified as Capture
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.LaneRegistrationData (LaneRowContractData (..), SelectedLaneFileData (..))
import JitML.Product.SourceDigest (SourceStamp (..), sourceDigestAlgorithm)
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (AppleSilicon, LinuxCPU))
import System.Directory (canonicalizePath, createDirectoryIfMissing, removeFile)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Posix.Files (createSymbolicLink)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

criterionReviewDataTests :: TestTree
criterionReviewDataTests =
  testGroup
    "CriterionReviewData"
    [ testCase "review identity roundtrips without granting execution authority" $ do
        value <- expectRight identity
        bytes <- expectRight (Review.encodeCriterionReviewIdentityData value)
        Review.decodeCriterionReviewIdentityData bytes @?= Right value
    , testCase "selection and receipt retain their exact original source lane and scope" $ do
        let selected = selection
        encoded <- expectRight (Review.encodeCriterionReviewSelectionData selected)
        Review.decodeCriterionReviewSelectionData encoded @?= Right selected
        bytes <- expectRight (Review.encodeCriterionReviewReceiptData receipt)
        Review.decodeCriterionReviewReceiptData bytes @?= Right receipt
    , testCase "review selection cannot point at itself as receipt" $
        assertLeft
          ( Review.encodeCriterionReviewSelectionData
              ( selection
                  { Review.reviewSelectionReceipt = SelectedLaneFileData (Text.pack selectedPath) (sha "a") 1
                  }
              )
          )
    , testCase "review identity rejects a foreign source path" $ do
        value <- expectRight identity
        assertLeft
          ( Review.encodeCriterionReviewIdentityData
              (value {Review.criterionReviewSource = SourceStamp sourceDigestAlgorithm (sha "b")})
          )
    , testCase "review identity rejects a foreign lane path" $ do
        value <- expectRight identity
        assertLeft
          (Review.encodeCriterionReviewIdentityData (value {Review.criterionReviewSubstrate = AppleSilicon}))
    , testCase "review identity rejects control and traversal paths" $ do
        value <- expectRight identity
        mapM_
          ( \bad ->
              assertLeft
                ( Review.encodeCriterionReviewIdentityData
                    (value {Review.criterionReviewReceipt = receiptRef {selectedLaneFilePath = bad}})
                )
          )
          [rootPath <> "../receipt.cbor", rootPath <> "bad\NUL.cbor"]
    , testCase "unknown source algorithms are refused before file access" $ do
        result <-
          Capture.captureCriterionReviewIn
            (error "filesystem root must not be demanded")
            (SourceStamp 999 (sha "a"))
            LinuxCPU
            Review.NativeCriterionReview
        case result of
          Left (Capture.CriterionReviewRejected _) -> pure ()
          _ -> assertFailure "unsupported source was not rejected before filesystem root"
    , testCase "exactly55 ordered contracts are required before encoding" $
        mapM_
          ( \rows -> assertLeft (Review.encodeCriterionReviewReceiptData (receipt {Review.reviewReceiptRows = rows}))
          )
          [ []
          , take 54 contracts
          , contracts <> take 1 contracts
          , repeat (LaneRowContractData "row" (sha "a") (sha "b"))
          ]
    , testCase "duplicate contract rows do not become an approved set" $
        assertLeft
          ( Review.encodeCriterionReviewReceiptData
              (receipt {Review.reviewReceiptRows = replicate 55 (LaneRowContractData "same" (sha "a") (sha "b"))})
          )
    , testCase "empty duplicate and excessive artifact inventories refuse" $
        mapM_
          ( \refs ->
              assertLeft
                (Review.encodeCriterionReviewReceiptData (receipt {Review.reviewReceiptArtifacts = refs}))
          )
          [[], [artifactRef, artifactRef], repeat artifactRef]
    , testCase "artifact individual and cumulative byte caps are distinct" $ do
        assertLeft
          ( Review.encodeCriterionReviewReceiptData
              (receipt {Review.reviewReceiptArtifacts = [artifactRef {selectedLaneFileBytes = 4194305}]})
          )
        let refs =
              [ artifactRef {selectedLaneFilePath = rootPath <> Text.pack (show n), selectedLaneFileBytes = 4194304}
              | n <- [0 :: Int .. 4]
              ]
        assertLeft
          (Review.encodeCriterionReviewReceiptData (receipt {Review.reviewReceiptArtifacts = refs}))
    , testCase "canonical readers reject trailing bytes and indefinite arrays" $ do
        value <- expectRight identity
        bytes <- expectRight (Review.encodeCriterionReviewIdentityData value)
        assertLeft (Review.decodeCriterionReviewIdentityData (bytes <> BS.singleton 0))
        assertLeft (Review.decodeCriterionReviewIdentityData (BS.pack [159, 255]))
    , testCase "impossible receipt count refuses without materializing elements" $ do
        assertLeft (Review.decodeCriterionReviewReceiptData (BS.replicate 65537 0))
        let impossible =
              Wire.encodeStrict
                ( CBOR.encodeListLen 10
                    <> CBOR.encodeString "jitml-criterion-review-receipt-v1"
                    <> CBOR.encodeWord 1
                    <> CBOR.encodeString "native"
                    <> CBOR.encodeString "linux-cpu"
                    <> CBOR.encodeWord64 sourceDigestAlgorithm
                    <> CBOR.encodeString (sha "a")
                    <> CBOR.encodeString "finite-native-v1"
                    <> CBOR.encodeString "historical-calibrated-floors-remain-unproven;finite-canonical-claims-only"
                    <> CBOR.encodeListLen (maxBound :: Word)
                )
        assertLeft (Review.decodeCriterionReviewReceiptData impossible)
    , testCase "environment transport roundtrips exact lowercase hex only" $ do
        value <- expectRight identity
        encoded <- expectRight (Review.renderCriterionReviewIdentityData value)
        Review.parseCriterionReviewIdentityData (Text.unpack encoded) @?= Right value
        assertLeft (Review.parseCriterionReviewIdentityData "criterion-review-v1:AF")
        assertLeft (Review.parseCriterionReviewIdentityData (repeat 'a'))
    , testCase "historical unreviewed producer retains original three identifiers and bytes" $ do
        let producer = Qualification.RawQualificationProducer (sha "a") (sha "b") (sha "c")
        Qualification.qualificationProducerReviewIdentity producer @?= Right Nothing
        LBS.toStrict (serialise producer)
          @?= Wire.encodeStrict
            ( CBOR.encodeListLen 4
                <> CBOR.encodeWord 0
                <> CBOR.encodeString (sha "a")
                <> CBOR.encodeString (sha "b")
                <> CBOR.encodeString (sha "c")
            )
    , testCase "observed and supplied producer tags remain distinct even with identical identity" $ do
        value <- expectRight supervisedIdentity
        bytes <- expectRight (Review.encodeCriterionReviewIdentityData value)
        let observed = Qualification.RawObservedReviewedQualificationProducer (sha "a") (sha "b") (sha "c") bytes
            supplied = Qualification.RawSuppliedReviewedQualificationProducer (sha "a") (sha "b") (sha "c") bytes
        Qualification.qualificationProducerReviewIdentity observed @?= Right (Just value)
        Qualification.qualificationProducerReviewIdentity supplied @?= Right (Just value)
        Qualification.qualificationProducerReviewWasSupplied observed @?= False
        Qualification.qualificationProducerReviewWasSupplied supplied @?= True
        assertBool "raw producer source roles were merged" (serialise observed /= serialise supplied)
    , testCase "producer review cannot substitute its original source" $ do
        value <- expectRight supervisedIdentity
        bytes <- expectRight (Review.encodeCriterionReviewIdentityData value)
        assertLeft
          ( Qualification.qualificationProducerReviewIdentity
              (Qualification.RawSuppliedReviewedQualificationProducer (sha "d") (sha "b") (sha "c") bytes)
          )
    , testCase "producer review rejects native scope and malformed identity bytes" $ do
        value <- expectRight identity
        bytes <- expectRight (Review.encodeCriterionReviewIdentityData value)
        mapM_
          ( assertLeft
              . Qualification.qualificationProducerReviewIdentity
              . Qualification.RawSuppliedReviewedQualificationProducer (sha "a") (sha "b") (sha "c")
          )
          [bytes, BS.empty]
    , testCase "actual fixed-file capture reads every selected artifact" $ withFixture $ \directory expected -> do
        result <- capture directory
        captured <- expectRight result
        Capture.capturedCriterionReviewIdentity captured @?= expected
    , testCase "missing actual fixed selection remains a typed missing result" $ withSystemTempDirectory "criterion-missing" $ \directory -> do
        result <- capture directory
        case result of
          Left (Capture.CriterionReviewMissingFile _) -> pure ()
          _ -> assertFailure "missing FILE was not reported as missing"
    , testCase "actual receipt and artifact substitutions fail their independent pins" $ do
        withFixture $ \directory _ -> do
          BS.writeFile (directory </> Text.unpack (selectedLaneFilePath receiptRef)) "substituted"
          result <- capture directory
          assertLeft result
        withFixture $ \directory _ -> do
          BS.writeFile (directory </> Text.unpack (selectedLaneFilePath artifactRef)) "substituted"
          result <- capture directory
          assertLeft result
    , testCase "actual symbolic link artifact is refused before reading its target" $ withFixture $ \directory _ -> do
        let path = directory </> Text.unpack (selectedLaneFilePath artifactRef)
            target = directory </> "target"
        BS.writeFile target artifactBytes
        removeFile path
        createSymbolicLink target path
        result <- capture directory
        assertLeft result
    , testCase "actual selection cap reads at most cap plus one" $ withFixture $ \directory _ -> do
        BS.writeFile (directory </> selectedPath) (BS.replicate 16385 0)
        result <- capture directory
        assertLeft result
    , testCase "synchronous poisoned preflight is bounded data and asynchronous input propagates" $ do
        result <-
          Capture.captureCriterionReviewIn
            "."
            (error "criterion preflight poison")
            LinuxCPU
            Review.NativeCriterionReview
        case result of
          Left (Capture.CriterionReviewReadFailure _) -> pure ()
          _ -> assertFailure "synchronous poison was not retained"
        interrupted <-
          try
            (Capture.captureCriterionReviewIn "." (throw UserInterrupt) LinuxCPU Review.NativeCriterionReview)
        case interrupted of
          Left UserInterrupt -> pure ()
          Right _ -> assertFailure "asynchronous interruption was swallowed"
          Left _ -> assertFailure "unexpected asynchronous exception"
    ]

source :: SourceStamp
source = SourceStamp sourceDigestAlgorithm (sha "a")
sha :: Text -> Text
sha = Text.replicate 64
rootPath :: Text
rootPath =
  "DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-validation/criterion-reviews/"
    <> sha "a"
    <> "/linux-cpu/native/"
selectedPath :: FilePath
selectedPath = Review.criterionReviewSelectionPath source LinuxCPU Review.NativeCriterionReview
artifactBytes :: BS.ByteString
artifactBytes = "ordinary retained independent review artifact; no execution or pass authority"
artifactRef, receiptRef :: SelectedLaneFileData
artifactRef =
  SelectedLaneFileData
    (rootPath <> "independent-review.txt")
    (sha256Hex artifactBytes)
    (fromIntegral (BS.length artifactBytes))
receiptRef = SelectedLaneFileData (rootPath <> "receipt.cbor") (sha "d") 1
contracts :: [LaneRowContractData]
contracts =
  [ LaneRowContractData ("ordinary-row-" <> Text.pack (show n)) (sha "b") (sha "c")
  | n <- [0 :: Int .. 54]
  ]
receipt :: Review.CriterionReviewReceiptData
receipt =
  Review.CriterionReviewReceiptData
    Review.NativeCriterionReview
    LinuxCPU
    source
    contracts
    [artifactRef]
selection :: Review.CriterionReviewSelectionData
selection = Review.CriterionReviewSelectionData Review.NativeCriterionReview LinuxCPU source receiptRef
identity :: Either Text Review.CriterionReviewIdentityData
identity = do
  digest <- Review.criterionReviewReceiptContractsSha256 receipt
  pure
    ( Review.CriterionReviewIdentityData
        Review.NativeCriterionReview
        LinuxCPU
        source
        (SelectedLaneFileData (Text.pack selectedPath) (sha "e") 1)
        receiptRef
        digest
    )
supervisedIdentity :: Either Text Review.CriterionReviewIdentityData
supervisedIdentity = do
  value <- identity
  let rewrite file = file {selectedLaneFilePath = Text.replace "/native/" "/supervised/" (selectedLaneFilePath file)}
  pure
    ( value
        { Review.criterionReviewScope = Review.SupervisedCriterionReview
        , Review.criterionReviewSelection = rewrite (Review.criterionReviewSelection value)
        , Review.criterionReviewReceipt = rewrite (Review.criterionReviewReceipt value)
        }
    )
withFixture :: (FilePath -> Review.CriterionReviewIdentityData -> IO a) -> IO a
withFixture action = withSystemTempDirectory "criterion-files" $ \directory -> do
  receiptBytes <- expectRight (Review.encodeCriterionReviewReceiptData receipt)
  let actualReceipt =
        receiptRef
          { selectedLaneFileSha256 = sha256Hex receiptBytes
          , selectedLaneFileBytes = fromIntegral (BS.length receiptBytes)
          }
  selectionBytes <-
    expectRight
      ( Review.encodeCriterionReviewSelectionData
          (selection {Review.reviewSelectionReceipt = actualReceipt})
      )
  let files =
        [ (selectedPath, selectionBytes)
        , (Text.unpack (selectedLaneFilePath actualReceipt), receiptBytes)
        , (Text.unpack (selectedLaneFilePath artifactRef), artifactBytes)
        ]
  mapM_
    ( \(relative, bytes) -> do
        let path = directory </> relative
        createDirectoryIfMissing True (takeDirectory path)
        BS.writeFile path bytes
    )
    files
  digest <- expectRight (Review.criterionReviewReceiptContractsSha256 receipt)
  action
    directory
    ( Review.CriterionReviewIdentityData
        Review.NativeCriterionReview
        LinuxCPU
        source
        ( SelectedLaneFileData
            (Text.pack selectedPath)
            (sha256Hex selectionBytes)
            (fromIntegral (BS.length selectionBytes))
        )
        actualReceipt
        digest
    )
capture :: FilePath -> IO (Either Capture.CriterionReviewError Capture.CapturedCriterionReview)
capture directory = do
  canonical <- canonicalizePath directory
  Capture.captureCriterionReviewIn canonical source LinuxCPU Review.NativeCriterionReview
expectRight :: (Show e) => Either e a -> IO a
expectRight (Right value) = pure value
expectRight (Left failure) = assertFailure (show failure)
assertLeft :: (Show a) => Either e a -> IO ()
assertLeft (Left _) = pure ()
assertLeft (Right value) = assertFailure ("unexpected ordinary acceptance: " <> show value)
