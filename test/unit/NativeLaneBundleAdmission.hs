{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- These use ordinary current projection/wire DATA and actual failing FILE
-- preflights. There is no positive native qualification or forged audit cap.
module NativeLaneBundleAdmission (nativeLaneBundleAdmissionTests) where

import Control.Exception (AsyncException (ThreadKilled), throw, try)
import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.QualificationObjects qualified as Objects
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.NativeLaneBundle qualified as Bundle
import JitML.Test.ProductLaneJournal qualified as Lane
import JitML.Test.Report qualified as Report
import NativeLaneBundleData (ordinaryBundleFixture)

nativeLaneBundleAdmissionTests :: TestTree
nativeLaneBundleAdmissionTests =
  testGroup
    "portable native Lane admission boundary"
    [ testCase "current nonnative discovery retains an explicitly empty native field" $
        withProjection Matrix.Tuning $ \_ projection ->
          Lane.productLaneJournalQualificationObjectKeys (wire projection "") @?= Right []
    , testCase "previous wire two is typed stale rather than a native compatibility path" $
        withProjection Matrix.Tuning $ \_ projection ->
          Lane.productLaneJournalQualificationObjectKeys (wireVersion 2 projection "")
            @?= Left (Lane.ProductLaneJournalWireStale Lane.productLaneJournalWireVersion 2)
    , testCase "native reference discovery returns only the exact checked root key" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
          key <- right (Bundle.nativeBundleReferenceObjectKey ordinaryReference)
          Lane.productLaneJournalQualificationObjectKeys (wire projection reference) @?= Right [key]
    , testCase "native discovery rejects uppercase or traversal-bearing reference labels" $
        withProjection Matrix.ReinforcementLearning $ \_ projection ->
          mapM_
            (reject . Lane.productLaneJournalQualificationObjectKeys . wire projection)
            [ "native-lane-bundle-v1:" <> digest "A" <> ":1"
            , "../../foreign"
            , "native-lane-bundle-v1:" <> digest "a" <> ":0"
            ]
    , testCase "missing native bundle is rejected at current wire validation before completion parsing" $
        withProjection Matrix.ReinforcementLearning $ \batch projection -> do
          let bytes = wire projection ""
          case Lane.admitProductLaneJournal (sha256Hex bytes) batch bytes of
            Left (Lane.ProductLaneJournalMalformed _ :| _) -> pure ()
            _ -> assertFailure "missing native reference did not fail at wire validation"
    , testCase "nonnative rows cannot carry native bundle identity" $
        withProjection Matrix.Tuning $ \batch projection -> do
          reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
          let bytes = wire projection reference
          case Lane.admitProductLaneJournal (sha256Hex bytes) batch bytes of
            Left (Lane.ProductLaneJournalSourceRejected reason :| _) ->
              assertBool "native object was not rejected on nonnative row" ("non-native" `Text.isInfixOf` reason)
            _ -> assertFailure "nonnative bundle identity was accepted"
    , testCase "a scalar reference and current native plan cannot create a qualified completion" $
        withProjection Matrix.ReinforcementLearning $ \batch projection -> do
          reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
          let bytes = wire projection reference
          reject (Lane.admitProductLaneJournalWithQualifications [] (sha256Hex bytes) batch bytes)
    , testCase "actual native IO checks the external main pin before any missing sidecar" $
        withProjection Matrix.ReinforcementLearning $ \batch projection -> do
          reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
          let bytes = wire projection reference
          actual <-
            Lane.admitProductLaneJournalWithNativeBundles
              "absent/ordinary-lane.json"
              []
              (digest "f")
              batch
              bytes
          case actual of
            Left (Lane.ProductLaneJournalDigestMismatch wanted observed :| []) ->
              (wanted, observed) @?= (digest "f", sha256Hex bytes)
            _ -> assertFailure "actual native pin mismatch was masked by a FILE read"
    , testCase "actual native IO refuses noncanonical main bytes before missing sidecar" $
        withProjection Matrix.ReinforcementLearning $ \batch projection -> do
          reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
          let bytes = wire projection reference <> " "
          actual <-
            Lane.admitProductLaneJournalWithNativeBundles
              "absent/ordinary-lane.json"
              []
              (sha256Hex bytes)
              batch
              bytes
          actual @?= Left (Lane.ProductLaneJournalNonCanonical :| [])
    , testCase "actual native IO records missing root failure without a private audit" $
        withSystemTempDirectory "jitml-native-lane-missing" $ \directory ->
          withProjection Matrix.ReinforcementLearning $ \batch projection -> do
            reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
            let bytes = wire projection reference
            actual <-
              Lane.admitProductLaneJournalWithNativeBundles
                (directory </> "lane.json")
                []
                (sha256Hex bytes)
                batch
                bytes
            case actual of
              Left (Lane.ProductLaneJournalSourceRejected reason :| _) ->
                assertBool
                  "actual portable refusal detail absent"
                  ("native portable physical audit refused" `Text.isInfixOf` reason)
              _ -> assertFailure "missing root produced native admission"
    , testCase "ordinary canonical root file can be discovered but is not current native evidence" $
        withSystemTempDirectory "jitml-native-root-data" $ \directory ->
          withProjection Matrix.ReinforcementLearning $ \batch projection -> do
            value <- right ordinaryBundleFixture
            rootBytes <- right (Bundle.encodeNativeBundleRootData value)
            reference <- right (Bundle.nativeBundleRootReference value)
            line <- right (Bundle.renderNativeBundleReferenceData reference)
            key <- right (Bundle.nativeBundleReferenceObjectKey reference)
            let path = directory </> "lane.json"
                bytes = wire projection line
            createDirectoryIfMissing True (path <> ".qualifications")
            BS.writeFile
              ( (path <> ".qualifications") </> Text.unpack (Bundle.nativeBundleReferenceSha256 reference)
                  <> ".cbor"
              )
              rootBytes
            Objects.readProductLaneQualificationObjects path bytes >>= (@?= Right [(key, rootBytes)])
            actual <-
              Lane.admitProductLaneJournalWithNativeBundles path [(key, rootBytes)] (sha256Hex bytes) batch bytes
            assertBool "ordinary DATA root manufactured actual native evidence" (isLeft actual)
    , testCase "root FILE capture checks its content SHA instead of trusting a canonical filename" $
        withSystemTempDirectory "jitml-native-root-corrupt" $ \directory ->
          withProjection Matrix.ReinforcementLearning $ \_ projection -> do
            reference <- right (Bundle.renderNativeBundleReferenceData ordinaryReference)
            let path = directory </> "lane.json"
            createDirectoryIfMissing True (path <> ".qualifications")
            BS.writeFile ((path <> ".qualifications") </> Text.unpack (digest "a") <> ".cbor") "x"
            Objects.readProductLaneQualificationObjects path (wire projection reference)
              >>= assertBool "wrong content SHA accepted" . isLeft
    , testCase "root reader catches lazy path failure inside actual safe boundary" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          result <-
            Bundle.readNativeLaneBundle
              (error "portable-path-poison")
              (sha256Hex "main")
              "main"
              ordinaryReference
              projection
          case result of
            Left (Failure.CompleteNativeDiagnostic detail) -> assertBool "input exception detail lost" ("portable-path-poison" `Text.isInfixOf` detail)
            _ -> assertFailure "lazy input was not a complete recorded refusal"
    , testCase "root reader catches lazy projection input inside actual safe boundary" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          let poisoned = error "portable-projection-poison" `asTypeOf` projection
          result <-
            Bundle.readNativeLaneBundle
              "ordinary-lane.json"
              (sha256Hex "main")
              "main"
              ordinaryReference
              poisoned
          assertBool "poisoned projection escaped as a successful audit" (isLeft result)
    , testCase "root reader catches lazy captured main bytes before any root FILE read" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          result <-
            Bundle.readNativeLaneBundle
              "ordinary-lane.json"
              (digest "a")
              (error "portable-main-poison")
              ordinaryReference
              projection
          assertBool "poisoned bytes manufactured a private audit" (isLeft result)
    , testCase "root reader propagates asynchronous input failure without a refusal replacement" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          actual <-
            try
              ( Bundle.readNativeLaneBundle
                  (throw ThreadKilled)
                  (sha256Hex "main")
                  "main"
                  ordinaryReference
                  projection
              )
          case actual of
            Left ThreadKilled -> pure ()
            Right _ -> assertFailure "async input was swallowed"
            Left other -> assertFailure (show other)
    , testCase "root reader path preflight refuses an infinite ordinary path" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          actual <-
            Bundle.readNativeLaneBundle (repeat 'x') (sha256Hex "main") "main" ordinaryReference projection
          assertBool "infinite path reached FILE IO" (isLeft actual)
    , testCase "root reader invalid reference refuses before ordinary missing file" $
        withProjection Matrix.ReinforcementLearning $ \_ projection -> do
          actual <-
            Bundle.readNativeLaneBundle
              "ordinary-lane.json"
              (sha256Hex "main")
              "main"
              (Bundle.NativeBundleReferenceData (digest "a") 0)
              projection
          case actual of
            Left (Failure.CompleteNativeDiagnostic detail) -> assertBool "reference bound not retained" ("outside its bound" `Text.isInfixOf` detail)
            _ -> assertFailure "invalid reference was not recorded as refusal"
    ]

-- Current public row selection creates only projection DATA. The completion
-- field below is deliberately invalid and can never become qualified evidence.
withProjection
  :: Matrix.RowFamily
  -> (forall kind. Matrix.ProductProjectionBatch -> Matrix.ProductProjection kind -> Assertion)
  -> Assertion
withProjection family action = case [row | row <- Matrix.allProductRows, Matrix.family row == family] of
  [] -> assertFailure "required canonical row family absent"
  row : _ -> case Matrix.projectProductRows LinuxCPU [row] of
    Failure problems -> assertFailure (show problems)
    Success batch -> case Matrix.productProjectionBatchProjections batch of
      [Matrix.SomeProductProjection _ projection] -> action batch projection
      _ -> assertFailure "singleton public projection coverage differs"
wire :: Matrix.ProductProjection kind -> Text -> ByteString
wire = wireVersion (fromIntegral Lane.productLaneJournalWireVersion)
wireVersion :: Int -> Matrix.ProductProjection kind -> Text -> ByteString
wireVersion version projection native =
  canonical
    ( object
        [ "format" .= ("jitml-product-lane-journal" :: Text)
        , "version" .= version
        , "run_id" .= ("ordinary-run" :: Text)
        , "substrate" .= ("linux-cpu" :: Text)
        , "source_journal_sha256" .= digest "5"
        , "rows" .= [row]
        ]
    )
    <> "\n"
 where
  row =
    object
      [ "ordinal" .= (0 :: Int)
      , "row_id" .= Matrix.productProjectionRowId projection
      , "plan_id" .= planIdText (Matrix.productProjectionPlanId projection)
      , "substrate" .= ("linux-cpu" :: Text)
      , "experiment_hash" .= Matrix.productProjectionExperimentHash projection
      , "admitted_manifest_sha256" .= digest "b"
      , "inference_manifest_sha256" .= digest "b"
      , "checkpoint_scope_sha256" .= digest "6"
      , "executable_sha256" .= digest "d"
      , "invocation_sha256" .= digest "e"
      , "contract_sha256" .= Report.productScenarioProjectionContractDigest projection
      , "completion_journal_sha256" .= digest "8"
      , "measured_sha256" .= digest "9"
      , "device_witness" .= ("ordinary DATA, no execution witness" :: Text)
      , "completed_training" .= ("ordinary DATA, no CompletedTraining" :: Text)
      , "supervised_qualification_receipt" .= ("" :: Text)
      , "native_qualification_bundle" .= native
      , "status" .= ("Passed" :: Text)
      ]
canonical :: Value -> ByteString
canonical = LBS.toStrict . encode
ordinaryReference :: Bundle.NativeBundleReferenceData
ordinaryReference = Bundle.NativeBundleReferenceData (digest "a") 1
digest :: Text -> Text
digest = Text.replicate 64
right :: (Show error) => Either error value -> IO value
right (Right value) = pure value
right (Left problem) = assertFailure (show problem) >> fail "ordinary fixture refused"
reject :: (Show value) => Either error value -> Assertion
reject (Left _) = pure ()
reject (Right _) = assertFailure "ordinary unqualified input was accepted"
