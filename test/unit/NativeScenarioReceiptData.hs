{-# LANGUAGE OverloadedStrings #-}

-- Ordinary synthetic receipt DATA only. No actual certificate, process,
-- filesystem, Store, retained qualification or model is created in this tree.
module NativeScenarioReceiptData (nativeScenarioReceiptDataTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types (CodecError (..), mkDigest)
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Execution.NativeParentAttemptRetention qualified as Attempt
import JitML.Plan.Plan qualified as Plan
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.SourceDigest qualified as Source
import JitML.Substrate (Substrate (..))
import JitML.Test.NativeScenarioReceiptData qualified as Receipt
import JitML.Training.Budget qualified as Training

nativeScenarioReceiptDataTests :: TestTree
nativeScenarioReceiptDataTests =
  testGroup
    "native scenario parent receipt DATA"
    [ testCase "complete ordinary record roundtrips every retained field without creating a certificate" $
        withFixture $ \value -> do
          bytes <- right (Receipt.encodeNativeScenarioReceiptData value)
          Receipt.decodeNativeScenarioReceiptData bytes @?= Right value
    , testCase "strict rendered scalar roundtrips and contains canonical lowercase hex" $
        withFixture $ \value -> do
          line <- right (Receipt.renderNativeScenarioReceiptData value)
          Receipt.parseNativeScenarioReceiptData line @?= Right value
          case Text.stripPrefix prefix line of
            Nothing -> assertFailure "canonical prefix missing"
            Just body -> do
              assertBool "all encoded bytes retained" (not (Text.null body) && even (Text.length body))
              assertBool
                "hex is lowercase ASCII"
                (Text.all (\c -> isDigit c || c >= 'a' && c <= 'f') body)
    , testCase "independent tuple builder agrees with the complete small canonical transport" $
        withFixture $ \value -> do
          bytes <- right (Receipt.encodeNativeScenarioReceiptData value)
          fields <- right (pieces value)
          array fields @?= bytes
          (Receipt.decodeNativeScenarioReceiptData bytes >>= Receipt.encodeNativeScenarioReceiptData)
            @?= Right bytes
    , testCase "every truncated prefix of a complete receipt refuses" $
        withFixture $ \value -> do
          bytes <- right (Receipt.encodeNativeScenarioReceiptData value)
          mapM_
            (\n -> reject (Receipt.decodeNativeScenarioReceiptData (BS.take n bytes)))
            [0 .. BS.length bytes - 1]
    , testCase "top level map wrong arities and indefinite arrays refuse" $
        withFixture $ \value -> do
          bytes <- right (Receipt.encodeNativeScenarioReceiptData value)
          mapM_
            (\header -> reject (Receipt.decodeNativeScenarioReceiptData (header <> BS.drop 1 bytes)))
            [listHeader 16, listHeader 18, Wire.encodeStrict (CBOR.encodeMapLen 17), BS.singleton 0x9f]
    , testCase "unknown domains and versions refuse closed transport" $
        withFixture $ \value -> do
          fields <- right (pieces value)
          reject
            (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 0 (text "foreign-domain") fields)))
          mapM_
            ( \version -> reject (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 1 (word version) fields)))
            )
            [0, 2, maxBound]
    , testCase "nonminimal version and nonminimal top level list refuse" $
        withFixture $ \value -> do
          fields <- right (pieces value)
          reject (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 1 (BS.pack [0x18, 1]) fields)))
          reject (Receipt.decodeNativeScenarioReceiptData (BS.pack [0x98, 17] <> BS.concat fields))
    , testCase "trailing bytes tagged envelopes and floating unsigned fields refuse" $
        withFixture $ \value -> do
          bytes <- right (Receipt.encodeNativeScenarioReceiptData value)
          fields <- right (pieces value)
          reject (Receipt.decodeNativeScenarioReceiptData (bytes <> BS.singleton 0))
          reject (Receipt.decodeNativeScenarioReceiptData (BS.singleton 0xc0 <> bytes))
          reject
            ( Receipt.decodeNativeScenarioReceiptData
                (array (replaceAt 7 (Wire.encodeStrict (CBOR.encodeDouble 1)) fields))
            )
    , testCase "declared excessive argv count refuses before missing or poisoned items" $
        withFixture $ \value -> do
          fields <- right (pieces value)
          mapM_
            ( \count ->
                reject (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 10 (listHeader count) fields)))
            )
            [65, maxBound]
    , testCase "invalid UTF8 path and wrong text scalar types refuse" $
        withFixture $ \value -> do
          fields <- right (pieces value)
          reject (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 2 (BS.pack [0x61, 0xff]) fields)))
          reject (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 2 (word 0) fields)))
    , testCase "nested reference and summary must be byte strings with bounded complete codecs" $
        withFixture $ \value -> do
          fields <- right (pieces value)
          mapM_
            ( \index -> reject (Receipt.decodeNativeScenarioReceiptData (array (replaceAt index nullValue fields)))
            )
            [6, 16]
          summary <-
            right
              ( Summary.encodeNativeParentEvaluationSummaryData
                  (Receipt.nativeScenarioReceiptEvaluationSummary value)
              )
          reject
            ( Receipt.decodeNativeScenarioReceiptData
                (array (replaceAt 16 (bytesValue (summary <> BS.singleton 0)) fields))
            )
          reject
            ( Receipt.decodeNativeScenarioReceiptData
                (array (replaceAt 16 (bytesValue (BS.replicate 65537 0)) fields))
            )
    , testCase "inventory exact arity and closed file role tags refuse substitutions" $
        withFixture $ \value -> do
          fields <- right (pieces value)
          files <- right (filePieces value)
          mapM_
            ( \count ->
                reject
                  ( Receipt.decodeNativeScenarioReceiptData
                      (array (replaceAt 15 (listHeader count <> BS.concat files) fields))
                  )
            )
            [4, 6]
          case files of
            firstFile : rest -> do
              let unknown = listHeader 4 <> word 5 <> BS.drop 2 firstFile
              reject
                (Receipt.decodeNativeScenarioReceiptData (array (replaceAt 15 (array (unknown : rest)) fields)))
            [] -> assertFailure "ordinary fixture inventory unexpectedly empty"
    , testCase "whole byte cap refuses before parsing and exact cap junk remains invalid" $ do
        rejectReason "exceeds128KiB" (Receipt.decodeNativeScenarioReceiptData (BS.replicate 131073 0))
        reject (Receipt.decodeNativeScenarioReceiptData (BS.replicate 131072 0))
    , testCase "scalar prefix odd hex uppercase nonASCII and trailing whitespace refuse" $
        withFixture $ \value -> do
          line <- right (Receipt.renderNativeScenarioReceiptData value)
          let body = Text.drop (Text.length prefix) line
          mapM_
            (reject . Receipt.parseNativeScenarioReceiptData)
            [ "foreign: " <> body
            , prefix <> "0"
            , prefix <> "AA" <> Text.drop 2 body
            , prefix <> "\x0660\&0" <> Text.drop 2 body
            , line <> " "
            , line <> "\n"
            , line <> "\NUL"
            ]
          rejectReason
            "scalar exceeds"
            ( Receipt.parseNativeScenarioReceiptData
                (Text.replicate (fromInteger Receipt.maximumNativeScenarioReceiptTextCharacters + 1) "0")
            )
    , testCase "relative nonnormalized and NUL paths refuse before encoding" $
        withFixture $ \value -> do
          mapM_
            (\path -> reject (Receipt.encodeNativeScenarioReceiptData (setSourceRoot path value)))
            ["relative/source", "/ordinary//source", "/ordinary/\NUL/source", "/ordinary/\xd800/source"]
    , testCase "path cap counts actual UTF8 bytes and bounds an infinite input spine" $
        withFixture $ \value -> do
          _ <-
            right (Receipt.refineNativeScenarioReceiptData (setSourceRoot ('/' : replicate 4095 'a') value))
          reject (Receipt.refineNativeScenarioReceiptData (setSourceRoot ('/' : replicate 4096 'a') value))
          reject (Receipt.refineNativeScenarioReceiptData (setSourceRoot ('/' : replicate 2048 '\955') value))
          reject (Receipt.refineNativeScenarioReceiptData (setSourceRoot (repeat '/') value))
    , testCase "both process identifiers require positive bounded original integer DATA" $
        withFixture $ \value -> do
          mapM_
            ( \pid -> do
                reject
                  (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptProcessId = pid})
                reject
                  (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptParentProcessId = pid})
            )
            [0, -1, toInteger (maxBound :: Word64) + 1]
          _ <-
            right
              ( Receipt.refineNativeScenarioReceiptData
                  value
                    { Receipt.nativeScenarioReceiptProcessId = toInteger (maxBound :: Word64)
                    , Receipt.nativeScenarioReceiptParentProcessId = 1
                    }
              )
          pure ()
    , testCase "request source cannot substitute for the exact reference source" $
        withFixture $ \value -> do
          let request = Receipt.nativeScenarioReceiptRequest value
          reject
            ( Receipt.refineNativeScenarioReceiptData
                value
                  { Receipt.nativeScenarioReceiptRequest =
                      request
                        { Parent.nativeParentRequestSource = Source.SourceStamp Source.sourceDigestAlgorithm (sha "c")
                        }
                  }
            )
    , testCase "reference row lane plan executable and original invocation cannot substitute" $
        withFixture $ \value -> do
          let ref = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference value)
              changed =
                [ ref {Reference.nativeReferenceRow = "foreign-row"}
                , ref {Reference.nativeReferenceLane = AppleSilicon}
                , ref {Reference.nativeReferencePlan = sha "d"}
                , ref {Reference.nativeReferenceExecutable = sha "e"}
                , ref {Reference.nativeReferenceInvocation = sha "f"}
                ]
          mapM_
            ( \raw -> do
                reference <- right (Reference.refineNativeQualificationReference raw)
                reject
                  (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptReference = reference})
            )
            changed
    , testCase "direct reference cannot masquerade as scenario parent history" $
        withFixture $ \value -> do
          let raw = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference value)
          reference <-
            right
              ( Reference.refineNativeQualificationReference
                  raw {Reference.nativeReferenceBinding = Reference.NativeReferenceDirect}
              )
          reject
            (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptReference = reference})
    , testCase "actual executable and configured cwd must agree with the original request" $
        withFixture $ \value -> do
          reject
            ( Receipt.refineNativeScenarioReceiptData
                value {Receipt.nativeScenarioReceiptExecutablePath = "/ordinary/foreign-jitml"}
            )
          mapM_
            ( \cwd ->
                reject
                  (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptWorkingDirectory = cwd})
            )
            [Nothing, Just "/ordinary/foreign-work"]
    , testCase "environment edit names remain exact ordered original observations" $
        withFixture $ \value -> do
          let removals = Receipt.nativeScenarioReceiptEnvironmentRemovals value
              overrides = Receipt.nativeScenarioReceiptEnvironmentOverrideNames value
          mapM_
            ( \names ->
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      value {Receipt.nativeScenarioReceiptEnvironmentRemovals = names}
                  )
            )
            [[], reverse removals, removals <> ["FOREIGN"]]
          mapM_
            ( \names ->
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      value {Receipt.nativeScenarioReceiptEnvironmentOverrideNames = names}
                  )
            )
            [[], reverse overrides, overrides <> ["FOREIGN"]]
    , testCase "argv list count is bounded before demanding excess element values" $
        withFixture $ \value -> do
          _ <-
            right
              ( Receipt.refineNativeScenarioReceiptData
                  value {Receipt.nativeScenarioReceiptArguments = replicate 64 ""}
              )
          reject
            ( Receipt.refineNativeScenarioReceiptData
                value {Receipt.nativeScenarioReceiptArguments = replicate 65 ""}
            )
          reject
            ( Receipt.refineNativeScenarioReceiptData
                value
                  { Receipt.nativeScenarioReceiptArguments = repeat (error "excess argv elements must not be demanded")
                  }
            )
    , testCase "argv scalar boundary uses UTF8 bytes including multibyte characters" $
        withFixture $ \value -> do
          mapM_
            ( \argument -> do
                _ <-
                  right
                    (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptArguments = [argument]})
                pure ()
            )
            [Text.replicate 4096 "a", Text.replicate 1024 "\x1f642"]
          mapM_
            ( \argument ->
                reject
                  (Receipt.refineNativeScenarioReceiptData value {Receipt.nativeScenarioReceiptArguments = [argument]})
            )
            [Text.replicate 4097 "a", Text.replicate 1025 "\x1f642"]
    , testCase "individually bounded fields still refuse an excessive whole encoded receipt" $
        withFixture $ \value ->
          rejectReason
            "exceeds128KiB"
            ( Receipt.encodeNativeScenarioReceiptData
                value
                  { Receipt.nativeScenarioReceiptArguments = replicate 64 (Text.replicate 4096 "a")
                  }
            )
    , testCase "each file role and exact expected filename are independently bound" $
        withFixture $ \value -> do
          mapM_
            ( \index -> do
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      ( changeFile
                          index
                          ( \file ->
                              file {Attempt.nativeParentAttemptFileKind = foreignKind (Attempt.nativeParentAttemptFileKind file)}
                          )
                          value
                      )
                  )
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      ( changeFile
                          index
                          ( \file ->
                              file {Attempt.nativeParentAttemptFilePath = Attempt.nativeParentAttemptFilePath file <> ".foreign"}
                          )
                          value
                      )
                  )
            )
            [0 .. 4]
    , testCase "all five physical file digests require canonical lowercase ASCII SHA" $
        withFixture $ \value -> do
          mapM_
            ( \index ->
                mapM_
                  ( \digest ->
                      reject
                        ( Receipt.refineNativeScenarioReceiptData
                            (changeFile index (\file -> file {Attempt.nativeParentAttemptFileSha256 = digest}) value)
                        )
                  )
                  [Text.replicate 63 "0", Text.replicate 64 "A", Text.replicate 64 "\x0660"]
            )
            [0 .. 4]
    , testCase "all five role byte caps admit maxima and refuse plus one without allocation" $
        withFixture $ \value -> do
          mapM_
            ( \(index, cap) -> do
                _ <-
                  right
                    ( Receipt.refineNativeScenarioReceiptData
                        (changeFile index (\file -> file {Attempt.nativeParentAttemptFileBytes = cap}) value)
                    )
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      (changeFile index (\file -> file {Attempt.nativeParentAttemptFileBytes = cap + 1}) value)
                  )
            )
            [(0, 65536), (1, 4294967296), (2, 1073741824), (3, 1073741824), (4, 4096)]
    , testCase "successful receipt requires both real stream slots even when their counts are zero" $
        withFixture $ \value -> do
          let inventory = Receipt.nativeScenarioReceiptAttemptInventory value
          mapM_
            ( \changed ->
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      value {Receipt.nativeScenarioReceiptAttemptInventory = changed}
                  )
            )
            [ inventory {Attempt.nativeParentAttemptStdoutFile = Nothing}
            , inventory {Attempt.nativeParentAttemptStderrFile = Nothing}
            , inventory
                { Attempt.nativeParentAttemptStdoutFile = Nothing
                , Attempt.nativeParentAttemptStderrFile = Nothing
                }
            ]
    , testCase "fixed attempt key ignores challenge plan executable and issued payload choices" $
        withFixture $ \value -> do
          let original = Parent.nativeParentRequestInvocation (Receipt.nativeScenarioReceiptRequest value)
          changed <- right (invocation "ordinary-run" "ordinary-row" LinuxCPU "e" "f" "a")
          Receipt.nativeScenarioAttemptScopeData original @?= Receipt.nativeScenarioAttemptScopeData changed
    , testCase "fixed attempt key partitions run row and lane rather than a new challenge" $
        withFixture $ \value -> do
          let original = Parent.nativeParentRequestInvocation (Receipt.nativeScenarioReceiptRequest value)
          variants <-
            traverse
              right
              [ invocation "another-run" "ordinary-row" LinuxCPU "4" "2" "6"
              , invocation "ordinary-run" "another-row" LinuxCPU "4" "2" "6"
              , invocation "ordinary-run" "ordinary-row" AppleSilicon "4" "2" "6"
              ]
          let keys = map Receipt.nativeScenarioAttemptScopeData (original : variants)
          length (nub keys) @?= 4
    , testCase
        "checked summary encoder propagates structural refusal instead of encoding a nominal summary"
        $ withFixture
        $ \value -> do
          let summary = Receipt.nativeScenarioReceiptEvaluationSummary value
          reject
            ( Receipt.encodeNativeScenarioReceiptData
                value
                  { Receipt.nativeScenarioReceiptEvaluationSummary =
                      summary {Summary.parentSummaryMatches = repeat (error "excess match values never demanded")}
                  }
            )
    , testCase "summary exact eleven order and both expected actual roots remain binding" $
        withFixture $ \value -> do
          let summary = Receipt.nativeScenarioReceiptEvaluationSummary value
              matches = Summary.parentSummaryMatches summary
          different <- right (mkDigest (BS.replicate 32 1))
          mapM_
            ( \changed ->
                reject
                  ( Receipt.refineNativeScenarioReceiptData
                      value
                        { Receipt.nativeScenarioReceiptEvaluationSummary = summary {Summary.parentSummaryMatches = changed}
                        }
                  )
            )
            [ take 10 matches
            , reverse matches
            , mapFirst (\item -> item {Summary.parentSummaryActualRoot = different}) matches
            ]
    , testCase "opaque reference bytes survive rather than being rewritten from labels" $
        withFixture $ \value -> do
          encoded <- right (Receipt.encodeNativeScenarioReceiptData value)
          decoded <- right (Receipt.decodeNativeScenarioReceiptData encoded)
          Reference.nativeQualificationReferenceBytes (Receipt.nativeScenarioReceiptReference decoded)
            @?= Reference.nativeQualificationReferenceBytes (Receipt.nativeScenarioReceiptReference value)
    ]

-- All ordinary data here is deliberately synthetic and not current Matrix,
-- actual issued/report/stream bytes or a successful Root execution.
withFixture :: (Receipt.NativeScenarioReceiptData -> Assertion) -> Assertion
withFixture action = right fixture >>= action

fixture :: Either CodecError Receipt.NativeScenarioReceiptData
fixture = do
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

setSourceRoot :: FilePath -> Receipt.NativeScenarioReceiptData -> Receipt.NativeScenarioReceiptData
setSourceRoot path value =
  value
    { Receipt.nativeScenarioReceiptRequest =
        (Receipt.nativeScenarioReceiptRequest value) {Parent.nativeParentRequestSourceRoot = path}
    }

changeFile
  :: Int
  -> (Attempt.NativeParentAttemptFileData -> Attempt.NativeParentAttemptFileData)
  -> Receipt.NativeScenarioReceiptData
  -> Receipt.NativeScenarioReceiptData
changeFile index change value =
  let old = Receipt.nativeScenarioReceiptAttemptInventory value
      apply at item = if at == index then change item else item
      altered =
        Attempt.NativeParentAttemptInventory
          (apply 0 (Attempt.nativeParentAttemptIssuedFile old))
          (apply 1 (Attempt.nativeParentAttemptReportFile old))
          (fmap (apply 2) (Attempt.nativeParentAttemptStdoutFile old))
          (fmap (apply 3) (Attempt.nativeParentAttemptStderrFile old))
          (apply 4 (Attempt.nativeParentAttemptAvailabilityFile old))
   in value {Receipt.nativeScenarioReceiptAttemptInventory = altered}

foreignKind :: Attempt.NativeParentAttemptFileKind -> Attempt.NativeParentAttemptFileKind
foreignKind Attempt.IssuedRecordFile = Attempt.ParentReportFile
foreignKind _ = Attempt.IssuedRecordFile

pieces :: Receipt.NativeScenarioReceiptData -> Either CodecError [ByteString]
pieces value = do
  summary <-
    Summary.encodeNativeParentEvaluationSummaryData
      (Receipt.nativeScenarioReceiptEvaluationSummary value)
  files <- filePieces value
  let request = Receipt.nativeScenarioReceiptRequest value
  pure
    [ text "jitml-native-scenario-parent-receipt-v1"
    , word 1
    , text (Text.pack (Parent.nativeParentRequestSourceRoot request))
    , text (Text.pack (Parent.nativeParentRequestWorkdir request))
    , text (Text.pack (Parent.nativeParentRequestPinnedExecutable request))
    , text (Training.renderProductScenarioInvocation (Parent.nativeParentRequestInvocation request))
    , bytesValue
        (Reference.nativeQualificationReferenceBytes (Receipt.nativeScenarioReceiptReference value))
    , word (fromInteger (Receipt.nativeScenarioReceiptProcessId value))
    , word (fromInteger (Receipt.nativeScenarioReceiptParentProcessId value))
    , text (Text.pack (Receipt.nativeScenarioReceiptExecutablePath value))
    , texts (Receipt.nativeScenarioReceiptArguments value)
    , maybe nullValue (text . Text.pack) (Receipt.nativeScenarioReceiptWorkingDirectory value)
    , texts (Receipt.nativeScenarioReceiptEnvironmentRemovals value)
    , texts (Receipt.nativeScenarioReceiptEnvironmentOverrideNames value)
    , text (Receipt.nativeScenarioReceiptAttemptScope value)
    , array files
    , bytesValue summary
    ]

filePieces :: Receipt.NativeScenarioReceiptData -> Either CodecError [ByteString]
filePieces value = case Receipt.nativeScenarioReceiptAttemptInventory value of
  Attempt.NativeParentAttemptInventory issued report (Just out) (Just err) availability ->
    Right (map file [issued, report, out, err, availability])
  _ -> Left (Malformed "ordinary valid wire fixture requires five files")
 where
  file actual =
    array
      [ word (kindCode (Attempt.nativeParentAttemptFileKind actual))
      , text (Text.pack (Attempt.nativeParentAttemptFilePath actual))
      , word (Attempt.nativeParentAttemptFileBytes actual)
      , text (Attempt.nativeParentAttemptFileSha256 actual)
      ]
  kindCode Attempt.IssuedRecordFile = 0
  kindCode Attempt.ParentReportFile = 1
  kindCode Attempt.ParentStdoutFile = 2
  kindCode Attempt.ParentStderrFile = 3
  kindCode Attempt.RawAvailabilityFile = 4

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore replaceAt "Use zipWithFrom" -}
replaceAt :: Int -> a -> [a] -> [a]
replaceAt index new = zipWith (\at old -> if at == index then new else old) [0 ..]
mapFirst :: (a -> a) -> [a] -> [a]
mapFirst _ [] = []
mapFirst change (firstValue : rest) = change firstValue : rest
array :: [ByteString] -> ByteString
array values = listHeader (fromIntegral (length values)) <> BS.concat values
listHeader :: Word -> ByteString
listHeader = Wire.encodeStrict . CBOR.encodeListLen
text :: Text -> ByteString
text = Wire.encodeStrict . CBOR.encodeString
texts :: [Text] -> ByteString
texts = array . map text
word :: Word64 -> ByteString
word = Wire.encodeStrict . CBOR.encodeWord64
bytesValue :: ByteString -> ByteString
bytesValue = Wire.encodeStrict . CBOR.encodeBytes
nullValue :: ByteString
nullValue = Wire.encodeStrict CBOR.encodeNull
prefix :: Text
prefix = "native-parent-qualification-v1: "
sha :: Text -> Text
sha = Text.replicate 64
right :: (Show e) => Either e a -> IO a
right = either (\e -> assertFailure (show e) >> fail "unreachable") pure
reject :: Either CodecError a -> Assertion
reject (Left _) = pure ()
reject (Right _) = assertFailure "malformed ordinary receipt DATA accepted"
rejectReason :: Text -> Either CodecError a -> Assertion
rejectReason fragment outcome = case outcome of
  Left reason ->
    assertBool ("wrong refusal: " <> show reason) (Text.isInfixOf fragment (Text.pack (show reason)))
  Right _ -> assertFailure "expected ordinary receipt refusal"
