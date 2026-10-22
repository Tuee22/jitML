{-# LANGUAGE OverloadedStrings #-}

-- Ordinary synthetic transport controls. No actual Root certificate, retained
-- SourceJournal, Store admission, qualification or successful Lane is created.
module NativeLaneBundleData (nativeLaneBundleDataTests, ordinaryBundleFixture) where

import Codec.CBOR.Encoding qualified as CBOR
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (chr)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types (CodecError (..), mkDigest)
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Execution.NativeParentAttemptRetention qualified as Attempt
import JitML.Plan.Plan qualified as Plan
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (..))
import JitML.Test.NativeLaneBundle qualified as Bundle
import JitML.Test.NativeScenarioJournalBindingData qualified as Binding
import JitML.Test.NativeScenarioReceiptData qualified as Receipt
import JitML.Training.Budget qualified as Training

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore nativeLaneBundleDataTests "Use drop1" -}
nativeLaneBundleDataTests :: TestTree
nativeLaneBundleDataTests =
  testGroup
    "portable native Lane bundle DATA"
    [ testCase "ordinary complete Binding19 receipt and ordered physical inventory roundtrip" $ withFixture $ \value -> do
        bytes <- right (Bundle.encodeNativeBundleRootData value)
        Bundle.decodeNativeBundleRootData bytes @?= Right value
    , testCase "independent canonical tuple agrees with every encoded field and byte" $ withFixture $ \value -> do
        bytes <- right (Bundle.encodeNativeBundleRootData value)
        pieces <- right (rootPieces value)
        bytes @?= array pieces
        (Bundle.decodeNativeBundleRootData bytes >>= Bundle.encodeNativeBundleRootData) @?= Right bytes
    , testCase "root reference binds actual canonical SHA and exact count" $ withFixture $ \value -> do
        bytes <- right (Bundle.encodeNativeBundleRootData value)
        reference <- right (Bundle.nativeBundleRootReference value)
        Bundle.nativeBundleReferenceSha256 reference @?= sha256Hex bytes
        Bundle.nativeBundleReferenceBytes reference @?= fromIntegral (BS.length bytes)
        rendered <- right (Bundle.renderNativeBundleReferenceData reference)
        Bundle.parseNativeBundleReferenceData rendered @?= Right reference
        Bundle.nativeBundleReferenceObjectKey reference
          @?= Right
            ("jitml-checkpoints/native-lane-bundles-v1/" <> sha256Hex bytes <> ".cbor")
    , testCase "zero-byte physical roles and full Word64 counts remain ordinary lossless DATA" $ withFixture $ \value -> do
        let changed = value {Bundle.nativeBundleObjects = [object "a" 0, object "b" maxBound]}
        bytes <- right (Bundle.encodeNativeBundleRootData changed)
        Bundle.decodeNativeBundleRootData bytes @?= Right changed
    , testCase "all nineteen binding fields including maximum sequence words survive" $ withFixture $ \value -> do
        let original = Bundle.nativeBundleBinding value
            binding =
              original
                { Binding.nativeScenarioBindingPreconditionRejected = False
                , Binding.nativeScenarioBindingPreconditionSequence = maxBound
                , Binding.nativeScenarioBindingInferenceSequence = 0
                , Binding.nativeScenarioBindingCompletionSequence = maxBound
                }
            changed = value {Bundle.nativeBundleBinding = binding}
        encoded <- right (Bundle.encodeNativeBundleRootData changed)
        Bundle.decodeNativeBundleRootData encoded @?= Right changed
    , testCase "every truncated complete root prefix refuses" $ withFixture $ \value -> do
        bytes <- right (Bundle.encodeNativeBundleRootData value)
        mapM_
          (\n -> reject (Bundle.decodeNativeBundleRootData (BS.take n bytes)))
          [0 .. BS.length bytes - 1]
    , testCase "closed top array rejects maps indefinite arrays and wrong arity" $ withFixture $ \value -> do
        bytes <- right (Bundle.encodeNativeBundleRootData value)
        mapM_
          (\header -> reject (Bundle.decodeNativeBundleRootData (header <> BS.drop 1 bytes)))
          [listHeader 4, listHeader 6, Wire.encodeStrict (CBOR.encodeMapLen 5), BS.singleton 0x9f]
    , testCase "domain and version are closed rather than extensible labels" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        reject (Bundle.decodeNativeBundleRootData (array (replaceAt 0 (text "foreign") parts)))
        mapM_
          (\version -> reject (Bundle.decodeNativeBundleRootData (array (replaceAt 1 (word version) parts))))
          [0, 2, maxBound]
    , testCase "shortest integer and list forms are required" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        reject (Bundle.decodeNativeBundleRootData (array (replaceAt 1 (BS.pack [0x18, 1]) parts)))
        reject (Bundle.decodeNativeBundleRootData (BS.pack [0x98, 5] <> BS.concat parts))
    , testCase "trailing bytes CBOR tags and floats in unsigned fields refuse" $ withFixture $ \value -> do
        bytes <- right (Bundle.encodeNativeBundleRootData value)
        parts <- right (rootPieces value)
        reject (Bundle.decodeNativeBundleRootData (bytes <> BS.singleton 0))
        reject (Bundle.decodeNativeBundleRootData (BS.singleton 0xc0 <> bytes))
        reject
          ( Bundle.decodeNativeBundleRootData
              (array (replaceAt 1 (Wire.encodeStrict (CBOR.encodeDouble 1)) parts))
          )
    , testCase "all 163 declared physical roles fit but a 164th refuses" $ withFixture $ \value -> do
        let roles = [object (Text.pack (show (1000 + i))) (fromIntegral i) | i <- [0 :: Int .. 162]]
            maximumRoot = value {Bundle.nativeBundleObjects = roles}
        bytes <- right (Bundle.encodeNativeBundleRootData maximumRoot)
        Bundle.decodeNativeBundleRootData bytes @?= Right maximumRoot
        reject
          (Bundle.encodeNativeBundleRootData (value {Bundle.nativeBundleObjects = roles <> [object "9999" 0]}))
    , testCase "hostile declared object count refuses before any item allocation" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        mapM_
          (\count -> reject (Bundle.decodeNativeBundleRootData (array (replaceAt 4 (listHeader count) parts))))
          [164, maxBound]
    , testCase "infinite object spine is refused before poisoned elements" $ withFixture $ \value ->
        reject
          ( Bundle.encodeNativeBundleRootData
              (value {Bundle.nativeBundleObjects = repeat (error "unforced object")})
          )
    , testCase "empty physical inventory is never a complete bundle root" $ withFixture $ \value ->
        reject (Bundle.encodeNativeBundleRootData (value {Bundle.nativeBundleObjects = []}))
    , testCase "duplicate and descending physical keys refuse instead of deduplicating" $ withFixture $ \value -> do
        reject
          ( Bundle.encodeNativeBundleRootData
              (value {Bundle.nativeBundleObjects = [object "a" 0, object "a" 0]})
          )
        reject
          ( Bundle.encodeNativeBundleRootData
              (value {Bundle.nativeBundleObjects = [object "b" 0, object "a" 0]})
          )
    , testCase "physical keys reject empty traversal separators control Unicode and backslash" $ withFixture $ \value ->
        mapM_
          ( \key -> reject (Bundle.encodeNativeBundleRootData (value {Bundle.nativeBundleObjects = [object key 0]}))
          )
          ["", "/a", "a/", "a//b", ".", "..", "a/../b", "a/./b", "a b", "a\\b", "a\n", "é"]
    , testCase "physical key UTF8 cap is exact at 4096 bytes" $ withFixture $ \value -> do
        let accepted = value {Bundle.nativeBundleObjects = [object (Text.replicate 4096 "a") 0]}
        bytes <- right (Bundle.encodeNativeBundleRootData accepted)
        Bundle.decodeNativeBundleRootData bytes @?= Right accepted
        reject
          ( Bundle.encodeNativeBundleRootData
              (value {Bundle.nativeBundleObjects = [object (Text.replicate 4097 "a") 0]})
          )
    , testCase "object hashes and destination basenames require exact lowercase SHA256" $ withFixture $ \value ->
        mapM_
          ( \hash -> do
              reject (Bundle.nativeBundleObjectBasename hash)
              reject
                ( Bundle.encodeNativeBundleRootData
                    (value {Bundle.nativeBundleObjects = [(object "a" 0) {Bundle.nativeBundleObjectSha256 = hash}]})
                )
          )
          [ ""
          , Text.replicate 63 "a"
          , Text.replicate 65 "a"
          , Text.replicate 64 "A"
          , Text.replicate 64 "g"
          , "../" <> sha "a"
          ]
    , testCase "declared raw digest length must be exactly 32 bytes" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        mapM_
          ( \count ->
              reject
                ( Bundle.decodeNativeBundleRootData
                    ( array
                        ( replaceAt
                            4
                            (array [array [text "a", bytesValue (BS.replicate count 0), word 0]])
                            parts
                        )
                    )
                )
          )
          [0, 31, 33]
    , testCase "object tuple arity count type and invalid UTF8 are closed" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        mapM_
          (\item -> reject (Bundle.decodeNativeBundleRootData (array (replaceAt 4 (array [item]) parts))))
          [ array [text "a", bytesValue (BS.replicate 32 0)]
          , array [text "a", bytesValue (BS.replicate 32 0), text "0"]
          , array [BS.pack [0x61, 0xff], bytesValue (BS.replicate 32 0), word 0]
          ]
    , testCase "root input cap is applied before its malformed body" $
        reject (Bundle.decodeNativeBundleRootData (BS.replicate 1048577 0))
    , testCase "receipt is checked closed DATA and cannot be arbitrary inline bytes" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        reject (Bundle.decodeNativeBundleRootData (array (replaceAt 3 (bytesValue "not a receipt") parts)))
        reject (Bundle.decodeNativeBundleRootData (array (replaceAt 3 (BS.pack [0x5a, 0, 2, 0, 1]) parts)))
    , testCase "binding array must retain exactly nineteen fields" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        let fields = bindingPieces (Bundle.nativeBundleBinding value)
        reject (Bundle.decodeNativeBundleRootData (array (replaceAt 2 (array (drop 1 fields)) parts)))
        reject (Bundle.decodeNativeBundleRootData (array (replaceAt 2 (array (fields <> [word 0])) parts)))
    , testCase "Boolean and all three binding sequence words preserve closed types" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        let fields = bindingPieces (Bundle.nativeBundleBinding value)
        reject
          (Bundle.decodeNativeBundleRootData (array (replaceAt 2 (array (replaceAt 15 (word 1) fields)) parts)))
        mapM_
          ( \index ->
              reject
                ( Bundle.decodeNativeBundleRootData
                    ( array
                        ( replaceAt
                            2
                            (array (replaceAt index (Wire.encodeStrict (CBOR.encodeDouble 1)) fields))
                            parts
                        )
                    )
                )
          )
          [16, 17, 18]
    , testCase "command and workflow limits are bytes and valid larger resource classes decode" $ withFixture $ \value -> do
        let binding = Bundle.nativeBundleBinding value
            changed =
              value
                { Bundle.nativeBundleBinding =
                    binding
                      { Binding.nativeScenarioBindingCommand = Text.replicate 4096 "é"
                      , Binding.nativeScenarioBindingExecutionJournalReceipt = Text.replicate 16384 "é"
                      }
                }
        bytes <- right (Bundle.encodeNativeBundleRootData changed)
        Bundle.decodeNativeBundleRootData bytes @?= Right changed
        reject
          ( Bundle.encodeNativeBundleRootData
              ( changed
                  { Bundle.nativeBundleBinding =
                      (Bundle.nativeBundleBinding changed)
                        { Binding.nativeScenarioBindingCommand = Text.replicate 4097 "é"
                        }
                  }
              )
          )
        reject
          ( Bundle.encodeNativeBundleRootData
              ( changed
                  { Bundle.nativeBundleBinding =
                      (Bundle.nativeBundleBinding changed)
                        { Binding.nativeScenarioBindingExecutionJournalReceipt = Text.replicate 16385 "é"
                        }
                  }
              )
          )
    , testCase "every individual binding text cap rejects its own one-byte excess" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        let fields = bindingPieces (Bundle.nativeBundleBinding value)
            caps = [1024, 256, 64, 32, 4096, 64, 64, 1024, 64, 8192, 64, 64, 32768, 64, 64]
        mapM_
          ( \(index, cap) ->
              reject
                ( Bundle.decodeNativeBundleRootData
                    ( array
                        ( replaceAt
                            2
                            (array (replaceAt index (text (Text.replicate (cap + 1) "x")) fields))
                            parts
                        )
                    )
                )
          )
          (zip [0 .. 14] caps)
    , testCase "oversized and infinite executable paths are bounded before Text conversion" $ withFixture $ \value -> do
        let binding = Bundle.nativeBundleBinding value
        reject
          ( Bundle.encodeNativeBundleRootData
              ( value
                  { Bundle.nativeBundleBinding =
                      binding {Binding.nativeScenarioBindingExecutablePath = replicate 4097 'x'}
                  }
              )
          )
        reject
          ( Bundle.encodeNativeBundleRootData
              ( value
                  { Bundle.nativeBundleBinding = binding {Binding.nativeScenarioBindingExecutablePath = repeat 'x'}
                  }
              )
          )
    , testCase "surrogate paths refuse while scalar Unicode paths remain lossless" $ withFixture $ \value -> do
        let binding = Bundle.nativeBundleBinding value
        mapM_
          ( \c ->
              reject
                ( Bundle.encodeNativeBundleRootData
                    ( value
                        { Bundle.nativeBundleBinding =
                            binding
                              { Binding.nativeScenarioBindingExecutablePath = ['/', chr c]
                              }
                        }
                    )
                )
          )
          [0xd800, 0xdfff]
        let changed =
              value
                { Bundle.nativeBundleBinding = binding {Binding.nativeScenarioBindingExecutablePath = "/ordinary/é/𝄞"}
                }
        bytes <- right (Bundle.encodeNativeBundleRootData changed)
        Bundle.decodeNativeBundleRootData bytes @?= Right changed
    , testCase "malformed executable-path UTF8 refuses before producing Binding DATA" $ withFixture $ \value -> do
        parts <- right (rootPieces value)
        let fields = bindingPieces (Bundle.nativeBundleBinding value)
        reject
          ( Bundle.decodeNativeBundleRootData
              (array (replaceAt 2 (array (replaceAt 4 (BS.pack [0x61, 0xff]) fields)) parts))
          )
    , testCase "reference rejects zero oversized counts uppercase SHA and noncanonical decimals" $ do
        mapM_
          (reject . Bundle.parseNativeBundleReferenceData)
          [ "native-lane-bundle-v1:" <> sha "a" <> ":0"
          , "native-lane-bundle-v1:" <> sha "a" <> ":1048577"
          , "native-lane-bundle-v1:" <> sha "A" <> ":1"
          , "native-lane-bundle-v1:" <> sha "a" <> ":01"
          , "native-lane-bundle-v1:" <> sha "a" <> ":+1"
          , "native-lane-bundle-v1:" <> sha "a" <> ":1:2"
          , "native-lane-bundle-v2:" <> sha "a" <> ":1"
          , Text.replicate 129 "a"
          ]
    , testCase "reference count endpoints use checked rendering and exact parsing" $
        mapM_
          ( \count -> do
              let reference = Bundle.NativeBundleReferenceData (sha "a") count
              line <- right (Bundle.renderNativeBundleReferenceData reference)
              Bundle.parseNativeBundleReferenceData line @?= Right reference
          )
          [1, 1048576]
    , testCase "invalid ordinary root is not silently normalized by the encoder" $ withFixture $ \value -> do
        let binding = Bundle.nativeBundleBinding value
            changed =
              value
                { Bundle.nativeBundleBinding = binding {Binding.nativeScenarioBindingRowId = Text.replicate 1025 "r"}
                }
        reject (Bundle.encodeNativeBundleRootData changed)
    ]

withFixture :: (Bundle.NativeBundleRootData -> Assertion) -> Assertion
withFixture action = right ordinaryBundleFixture >>= action
ordinaryBundleFixture :: Either CodecError Bundle.NativeBundleRootData
ordinaryBundleFixture = do
  receipt <- receiptFixture
  pure
    (Bundle.NativeBundleRootData ordinaryBinding receipt [object "ordinary/a" 0, object "ordinary/b" 7])
ordinaryBinding :: Binding.NativeScenarioJournalBindingData
ordinaryBinding =
  Binding.NativeScenarioJournalBindingData
    "ordinary-row"
    "ordinary-run"
    (sha "1")
    "linux-cpu"
    "/ordinary/jitml"
    (sha "2")
    (sha "3")
    "ordinary-data-only"
    (sha "4")
    "ordinary argv"
    (sha "5")
    (sha "6")
    "ordinary workflow"
    (sha "7")
    (sha "8")
    True
    3
    7
    9
object :: Text -> Word64 -> Bundle.NativeBundleObjectData
object key = Bundle.NativeBundleObjectData key (sha "a")

rootPieces :: Bundle.NativeBundleRootData -> Either CodecError [ByteString]
rootPieces value = do
  receipt <- Receipt.encodeNativeScenarioReceiptData (Bundle.nativeBundleReceipt value)
  pure
    [ text "jitml-native-lane-bundle-v1"
    , word 1
    , array (bindingPieces (Bundle.nativeBundleBinding value))
    , bytesValue receipt
    , array
        [ array
            [ text (Bundle.nativeBundleObjectKey item)
            , bytesValue (BS.replicate 32 0xaa)
            , word (Bundle.nativeBundleObjectBytes item)
            ]
        | item <- Bundle.nativeBundleObjects value
        ]
    ]
bindingPieces :: Binding.NativeScenarioJournalBindingData -> [ByteString]
bindingPieces value =
  map
    text
    [ Binding.nativeScenarioBindingRowId value
    , Binding.nativeScenarioBindingRunId value
    , Binding.nativeScenarioBindingPlanId value
    , Binding.nativeScenarioBindingSubstrate value
    , Text.pack (Binding.nativeScenarioBindingExecutablePath value)
    , Binding.nativeScenarioBindingExecutableSha256 value
    , Binding.nativeScenarioBindingInvocationDigest value
    , Binding.nativeScenarioBindingExperimentHash value
    , Binding.nativeScenarioBindingManifestSha256 value
    , Binding.nativeScenarioBindingCommand value
    , Binding.nativeScenarioBindingContractSha256 value
    , Binding.nativeScenarioBindingCheckpointScopeSha256 value
    , Binding.nativeScenarioBindingExecutionJournalReceipt value
    , Binding.nativeScenarioBindingExecutionJournalSha256 value
    , Binding.nativeScenarioBindingInferenceManifestSha256 value
    ]
    <> [ Wire.encodeStrict (CBOR.encodeBool (Binding.nativeScenarioBindingPreconditionRejected value))
       , word (Binding.nativeScenarioBindingPreconditionSequence value)
       , word (Binding.nativeScenarioBindingInferenceSequence value)
       , word (Binding.nativeScenarioBindingCompletionSequence value)
       ]

receiptFixture :: Either CodecError Receipt.NativeScenarioReceiptData
receiptFixture = do
  issued <- first Malformed (invocation "ordinary-run" "ordinary-row" LinuxCPU "4" "2" "6")
  let source = Source.SourceStamp Source.sourceDigestAlgorithm (sha "3")
      request =
        Parent.NativeParentExecutionRequest
          "/ordinary/source"
          source
          "/ordinary/work"
          "/ordinary/jitml"
          issued
      artifact = sha "9"
  reference <-
    Reference.refineNativeQualificationReference
      Reference.NativeQualificationReferenceData
        { Reference.nativeReferenceRow = "ordinary-row"
        , Reference.nativeReferenceLane = LinuxCPU
        , Reference.nativeReferencePlan = sha "4"
        , Reference.nativeReferenceExperiment = "ordinary-data-only"
        , Reference.nativeReferenceManifest = sha "7"
        , Reference.nativeReferenceSource = source
        , Reference.nativeReferenceExecutable = sha "2"
        , Reference.nativeReferenceInvocation = Training.productScenarioInvocationDigest issued
        , Reference.nativeReferenceCohort = sha "8"
        , Reference.nativeReferenceArtifact = artifact
        , Reference.nativeReferenceObjectKey =
            "jitml-checkpoints/ordinary-data-only/artifacts/native-qualification/" <> artifact <> ".cbor"
        , Reference.nativeReferenceObjectBytes = 1
        , Reference.nativeReferencePublication = sha "a"
        , Reference.nativeReferenceBinding = Reference.NativeReferenceScenario
        , Reference.nativeReferenceAllocationKey =
            "jitml-checkpoints/native-rl-allocations-v1/" <> sha "b" <> "/claim.cbor"
        , Reference.nativeReferenceAllocationSha = sha "b"
        , Reference.nativeReferenceAllocationBytes = 1
        }
  root <- mkDigest (BS.replicate 32 0)
  let scope = Receipt.nativeScenarioAttemptScopeData issued
      directory = "/ordinary/work/.build/native-parent-attempts/" <> Text.unpack scope
      file kind name = Attempt.NativeParentAttemptFileData kind name 0 (sha "0")
      inventory =
        Attempt.NativeParentAttemptInventory
          (file Attempt.IssuedRecordFile (directory <> "/issued.cbor"))
          (file Attempt.ParentReportFile (directory <> "/result/report.utf8"))
          (Just (file Attempt.ParentStdoutFile (directory <> "/result/stdout.bin")))
          (Just (file Attempt.ParentStderrFile (directory <> "/result/stderr.bin")))
          (file Attempt.RawAvailabilityFile (directory <> "/result/availability.cbor"))
      positions =
        [(stage, index) | index <- [0 .. 4], stage <- [Replay.InitialModelReplay, Replay.FinalModelReplay]]
          <> [(Replay.StoredFinalModelReplay, 0)]
      summary =
        Summary.NativeParentEvaluationSummaryData
          Nothing
          [ Summary.NativeParentEvaluationMatchData ordinal stage index root root Nothing
          | (ordinal, (stage, index)) <- zip [0 .. 10] positions
          ]
  Receipt.refineNativeScenarioReceiptData
    ( Receipt.NativeScenarioReceiptData
        request
        reference
        101
        99
        "/ordinary/jitml"
        ["ordinary-data-only"]
        (Just "/ordinary/work")
        [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
        , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
        , "JITML_PRODUCT_SCENARIO_RUN_ID"
        , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
        , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
        ]
        ["JITML_PRODUCT_SCENARIO_INVOCATION", "JITML_SUPERVISED_QUALIFICATION_SOURCE_SHA256"]
        scope
        inventory
        summary
        Nothing
    )

invocation
  :: Text -> Text -> Substrate -> Text -> Text -> Text -> Either Text Training.ProductScenarioInvocation
invocation run row lane plan executable challenge = do
  planId <- Plan.refinePlanIdText (sha plan)
  Training.mkProductScenarioInvocation run row planId lane (sha "5") (sha executable) (sha challenge)

sha :: Text -> Text
sha = Text.replicate 64
right :: (Show error) => Either error value -> IO value
right (Right value) = pure value
right (Left problem) = assertFailure (show problem) >> fail "ordinary DATA fixture refused"
reject :: (Show value) => Either error value -> Assertion
reject (Left _) = pure ()
reject (Right _) = assertFailure "hostile ordinary DATA accepted"
array :: [ByteString] -> ByteString
array values = listHeader (fromIntegral (length values)) <> BS.concat values
listHeader :: Word -> ByteString
listHeader = Wire.encodeStrict . CBOR.encodeListLen
word :: Word64 -> ByteString
word = Wire.encodeStrict . CBOR.encodeWord64
text :: Text -> ByteString
text = Wire.encodeStrict . CBOR.encodeString
bytesValue :: ByteString -> ByteString
bytesValue = Wire.encodeStrict . CBOR.encodeBytes
replaceAt :: Int -> value -> [value] -> [value]
replaceAt index value values = [if index == position then value else previous | (position, previous) <- zip [0 ..] values]
