{-# LANGUAGE OverloadedStrings #-}

module QualificationObjects (qualificationObjectsTests) where

import Data.Aeson (Value, encode, object, (.=))
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isLeft)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Product.QualificationObjects (readProductLaneQualificationObjects)
import JitML.Product.StatusEvidence qualified as Status
import JitML.Product.StatusLoader qualified as Loader
import JitML.Product.SupervisedQualificationReceipt qualified as Receipt
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Test.ProductAggregation qualified as Aggregate
import JitML.Test.ProductLaneJournal qualified as Lane

-- These are deliberately structural discovery fixtures, not qualified models,
-- producer-authenticated reports, real training or admitted lane journals.
-- The fake completion string is never offered as a successful completion.
qualificationObjectsTests :: TestTree
qualificationObjectsTests =
  testGroup
    "portable qualification object IO boundary"
    [ testCase "reads exact explicit bytes from the checked sibling SHA filename" $
        withSystemTempDirectory "jitml-qualification-objects" $ \directory -> do
          let path = directory </> "lane.json"
          writeObject path payload
          readProductLaneQualificationObjects path (wire [reference payload])
            >>= (@?= Right [(objectKey payload, payload)])
    , testCase "missing objects name the actual sibling path in a typed IO error" $
        withSystemTempDirectory "jitml-qualification-missing" $ \directory -> do
          let path = directory </> "lane.json"
          result <- readProductLaneQualificationObjects path (wire [reference payload])
          case result of
            Left (Lane.ProductLaneJournalIOFailure missing _) -> missing @?= objectPath path payload
            _ -> fail "missing qualification did not retain its actual IO path"
    , testCase "modified object bytes fail their filename binding with the actual path" $
        withSystemTempDirectory "jitml-qualification-tampered" $ \directory -> do
          let path = directory </> "lane.json"
          writeObject path payload
          ByteString.writeFile (objectPath path payload) "replaced bytes"
          result <- readProductLaneQualificationObjects path (wire [reference payload])
          case result of
            Left (Lane.ProductLaneJournalMalformed detail) ->
              assertBool
                "tamper diagnostic lost its actual path"
                (Text.pack (objectPath path payload) `Text.isInfixOf` detail)
            _ -> fail "replaced bytes were accepted under the original content filename"
    , testCase "canonical discovery rejects altered main bytes and old wire versions before IO" $
        withSystemTempDirectory "jitml-qualification-wire" $ \directory -> do
          let path = directory </> "lane.json"
          result <- readProductLaneQualificationObjects path (wire [reference payload] <> " ")
          result @?= Left Lane.ProductLaneJournalNonCanonical
          old <- readProductLaneQualificationObjects path (wireVersion 1 [reference payload])
          old @?= Left (Lane.ProductLaneJournalWireStale Lane.productLaneJournalWireVersion 1)
    , testCase "traversal, absolute and noncanonical SHA keys never become filesystem paths" $
        withSystemTempDirectory "jitml-qualification-path" $ \directory -> do
          let path = directory </> "lane.json"
              sha = sha256Hex payload
              hostile =
                [ "../../outside.cbor"
                , "/tmp/" <> sha <> ".cbor"
                , "jitml-checkpoints/../artifacts/supervised-qualification/" <> sha <> ".cbor"
                , "jitml-checkpoints/"
                    <> experiment
                    <> "/artifacts/supervised-qualification/"
                    <> Text.toUpper sha
                    <> ".cbor"
                ]
          mapM_
            ( \key ->
                readProductLaneQualificationObjects path (wire [referenceWithKey key payload])
                  >>= assertBool "unsafe discovery key was accepted" . isLeft
            )
            hostile
    , testCase "duplicate journal object references are rejected instead of silently deduplicated" $
        withSystemTempDirectory "jitml-qualification-duplicate" $ \directory -> do
          let path = directory </> "lane.json"
          result <- readProductLaneQualificationObjects path (wire [reference payload, reference payload])
          assertBool "duplicate discovery keys were accepted" (isLeft result)
    , testCase "captured object bytes are an immutable read snapshot and a later read sees replacement" $
        withSystemTempDirectory "jitml-qualification-snapshot" $ \directory -> do
          let path = directory </> "lane.json"
          writeObject path payload
          captured <- readProductLaneQualificationObjects path (wire [reference payload])
          ByteString.writeFile (objectPath path payload) "subsequent replacement"
          captured @?= Right [(objectKey payload, payload)]
          readProductLaneQualificationObjects path (wire [reference payload])
            >>= assertBool "later replacement was hidden" . isLeft
    , testCase "status loader checks main pin before discovering missing objects" $
        withSystemTempDirectory "jitml-qualification-pin-first" $ \directory -> do
          let filename = "lane.json"
              bytes = wire [reference payload]
              input = Aggregate.ProductLaneInput LinuxCPU filename (digest "f")
          ByteString.writeFile (directory </> filename) bytes
          (_, judged) <- Loader.loadLaneJournalIn directory input
          case judged of
            Status.Unproven (Status.Mismatched detail :| []) ->
              assertBool "main pin mismatch was not reported" (sha256Hex bytes `Text.isInfixOf` detail)
            _ -> fail "main pin mismatch was masked by a missing qualification"
    , testCase
        "status loader preserves missing sidecar identity instead of proving or blaming the main file"
        $ withSystemTempDirectory "jitml-qualification-status-missing"
        $ \directory -> do
          let filename = "lane.json"
              path = directory </> filename
              bytes = wire [reference payload]
              input = Aggregate.ProductLaneInput LinuxCPU filename (sha256Hex bytes)
          ByteString.writeFile path bytes
          (_, judged) <- Loader.loadLaneJournalIn directory input
          judged @?= Status.Unproven (Status.Missing (Text.pack (objectPath path payload)) :| [])
    , testCase "aggregation loader retains the typed missing sidecar error without an empty-map fallback" $
        withSystemTempDirectory "jitml-qualification-aggregate-missing" $ \directory -> do
          let path = directory </> "lane.json"
              bytes = wire [reference payload]
              input = Aggregate.ProductLaneInput LinuxCPU path (sha256Hex bytes)
          ByteString.writeFile path bytes
          loaded <- Aggregate.loadProductAggregationFrom [input]
          case loaded of
            Left
              ( Aggregate.ProductAggregationLaneRejected LinuxCPU (Lane.ProductLaneJournalIOFailure missing _ :| [])
                  :| []
                ) ->
                missing @?= objectPath path payload
            _ -> fail "aggregate loader hid its qualification IO failure"
    ]

payload :: ByteString
payload = "structural IO fixture bytes, not a qualification CBOR or execution proof"

experiment :: Text
experiment = "product-row-mnist-shallow-mlp"

objectKey :: ByteString -> Text
objectKey bytes =
  "jitml-checkpoints/"
    <> experiment
    <> "/artifacts/supervised-qualification/"
    <> sha256Hex bytes
    <> ".cbor"

objectPath :: FilePath -> ByteString -> FilePath
objectPath path bytes = (path <> ".qualifications") </> (Text.unpack (sha256Hex bytes) <> ".cbor")

writeObject :: FilePath -> ByteString -> IO ()
writeObject path bytes = do
  createDirectoryIfMissing True (path <> ".qualifications")
  ByteString.writeFile (objectPath path bytes) bytes

reference :: ByteString -> Text
reference bytes = referenceWithKey (objectKey bytes) bytes

referenceWithKey :: Text -> ByteString -> Text
referenceWithKey key bytes =
  Receipt.supervisedQualificationReceiptPrefix
    <> Encoding.decodeUtf8
      ( canonical
          ( object
              [ "version" .= (1 :: Int)
              , "row_id" .= ("mnist-shallow-mlp" :: Text)
              , "plan_id" .= digest "a"
              , "substrate" .= ("linux-cpu" :: Text)
              , "experiment_hash" .= experiment
              , "manifest_sha256" .= digest "b"
              , "source_sha256" .= digest "c"
              , "executable_sha256" .= digest "d"
              , "invocation_sha256" .= digest "e"
              , "cohort_plan_id" .= digest "f"
              , "qualification_sha256" .= sha256Hex bytes
              , "qualification_object_key" .= key
              , "initial_jmw1_sha256" .= digest "0"
              , "final_jmw1_sha256" .= digest "1"
              , "runtime_sha256" .= digest "2"
              , "graph_sha256" .= digest "3"
              , "evaluation_sha256" .= digest "4"
              , "execution_binding" .= ("product-scenario-invocation-v1" :: Text)
              ]
          )
      )

wire :: [Text] -> ByteString
wire = wireVersion (fromIntegral Lane.productLaneJournalWireVersion)

wireVersion :: Int -> [Text] -> ByteString
wireVersion version references =
  canonical
    ( object
        [ "format" .= ("jitml-product-lane-journal" :: Text)
        , "version" .= version
        , "run_id" .= ("structural-discovery-fixture" :: Text)
        , "substrate" .= ("linux-cpu" :: Text)
        , "source_journal_sha256" .= digest "5"
        , "rows" .= [row ordinal receipt | (ordinal, receipt) <- zip [0 :: Int ..] references]
        ]
    )
    <> "\n"
 where
  row ordinal receipt =
    object
      [ "ordinal" .= ordinal
      , "row_id" .= ("mnist-shallow-mlp" :: Text)
      , "plan_id" .= digest "a"
      , "substrate" .= ("linux-cpu" :: Text)
      , "experiment_hash" .= experiment
      , "admitted_manifest_sha256" .= digest "b"
      , "inference_manifest_sha256" .= digest "b"
      , "checkpoint_scope_sha256" .= digest "6"
      , "executable_sha256" .= digest "d"
      , "invocation_sha256" .= digest "e"
      , "contract_sha256" .= digest "7"
      , "completion_journal_sha256" .= digest "8"
      , "measured_sha256" .= digest "9"
      , "device_witness" .= ("structural fixture, not an execution witness" :: Text)
      , "completed_training" .= ("structural fixture, not CompletedTraining" :: Text)
      , "supervised_qualification_receipt" .= receipt
      , "native_qualification_bundle" .= ("" :: Text)
      , "status" .= ("Passed" :: Text)
      ]

canonical :: Value -> ByteString
canonical = LazyByteString.toStrict . encode

digest :: Text -> Text
digest = Text.replicate 64
