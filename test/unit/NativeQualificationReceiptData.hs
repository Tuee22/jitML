{-# LANGUAGE OverloadedStrings #-}

-- Ordinary metadata fixtures only: not actual allocation/replay/completion or
-- qualification evidence. No execution or authority capability is fabricated.
module NativeQualificationReceiptData (nativeQualificationReceiptDataTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64, Word8)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Q
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as R
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Substrate (Substrate (LinuxCPU))

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore nativeQualificationReceiptDataTests "Use drop1" -}
nativeQualificationReceiptDataTests :: TestTree
nativeQualificationReceiptDataTests =
  testGroup
    "native qualification bounded metadata DATA"
    [ testCase "ordinary direct metadata roundtrips without restoring its opaque payloads" $ do
        value <- right (Q.refineNativeQualificationReceiptData fixture)
        actual <- right (Q.decodeNativeQualificationReceiptData (Q.nativeQualificationReceiptBytes value))
        assertEqual "all raw DATA fields" fixture (Q.nativeQualificationReceiptFields actual)
        assertEqual
          "exact canonical bytes"
          (Q.nativeQualificationReceiptBytes value)
          (Q.nativeQualificationReceiptBytes actual)
        assertEqual
          "existing versioned publication digest"
          (R.nativePublicationDigest publication)
          (Q.nativeQualificationReceiptPublicationDigest actual)
    , testCase "all publication alternatives retain the complete common descriptor" $
        mapM_
          ( \pub -> do
              let fields = withPublication pub fixture
              actual <- roundtrip fields
              assertEqual "lossless descriptor" pub (Q.nativeReceiptPublication actual)
              assertBool
                "all restored ordinary refs use that descriptor"
                ( all
                    ((== pub) . R.nativeRetainedObjectPublication)
                    ( Q.nativeReceiptAllocation actual
                        : Q.nativeReceiptPhases actual <> fmap Q.nativeReceiptReplayObject (Q.nativeReceiptReplays actual)
                    )
                )
          )
          publications
    , testCase "equal observed and supplied sources remain two present roles" $ do
        actual <- roundtrip fixture
        assertEqual "observed tag" (Just stamp) (Q.nativeReceiptObservedSource actual)
        assertEqual "supplied tag" (Just stamp) (Q.nativeReceiptSuppliedSource actual)
    , testCase "each individual source role keeps its independent absence tag" $
        mapM_
          (\fields -> roundtrip fields >>= assertEqual "role and absence equality" fields)
          [ fixture {Q.nativeReceiptObservedSource = Nothing}
          , fixture {Q.nativeReceiptSuppliedSource = Nothing}
          ]
    , testCase "supplied invocation stays exact Unicode text DATA without a parser factory" $ do
        let text = "ordinary invocation TEXT λ🙂\nnot an issued invocation"
        actual <- roundtrip (fixture {Q.nativeReceiptAssociation = Q.NativeReceiptScenarioData text})
        assertEqual
          "exact supplied text only"
          (Q.NativeReceiptScenarioData text)
          (Q.nativeReceiptAssociation actual)
    , testCase "opaque cohort and completion bytes retain every byte without semantic decoding" $ do
        let fields =
              fixture
                { Q.nativeReceiptCohortTransport = BS.pack [0, 255, 128, 0]
                , Q.nativeReceiptCompletedTrainingBytes = BS.pack [249, 128, 0, 255]
                }
        actual <- roundtrip fields
        assertEqual
          "opaque cohort"
          (Q.nativeReceiptCohortTransport fields)
          (Q.nativeReceiptCohortTransport actual)
        assertEqual
          "opaque completed bytes"
          (Q.nativeReceiptCompletedTrainingBytes fields)
          (Q.nativeReceiptCompletedTrainingBytes actual)
    , testCase "another original replay role or index order refuses" $
        case Q.nativeReceiptReplays fixture of
          a : b : rest -> reject (fixture {Q.nativeReceiptReplays = b : a : rest})
          _ -> assertFailure "fixture omitted actual DATA roles"
    , testCase "missing extra and infinite replay lists refuse before element traversal" $ do
        reject (fixture {Q.nativeReceiptReplays = drop 1 (Q.nativeReceiptReplays fixture)})
        reject
          ( fixture
              { Q.nativeReceiptReplays = Q.nativeReceiptReplays fixture <> [error "extra replay must not be forced"]
              }
          )
        reject
          (fixture {Q.nativeReceiptReplays = repeat (error "unbounded replay heads must not be forced")})
    , testCase "initial and final pair must retain the same original attempt" $
        reject (editReplay 1 (\value -> value {Q.nativeReceiptReplayAttempt = dig 200}) fixture)
    , testCase "two prescribed children cannot share one attempt even with internally matched pairs" $
        reject
          ( editReplay
              3
              (\value -> value {Q.nativeReceiptReplayAttempt = dig 10})
              (editReplay 2 (\value -> value {Q.nativeReceiptReplayAttempt = dig 10}) fixture)
          )
    , testCase "stored final replay must retain serving index zero attempt" $ do
        reject (editReplay 10 (\value -> value {Q.nativeReceiptReplayAttempt = dig 201}) fixture)
        reject (editReplay 10 (\value -> value {Q.nativeReceiptReplayIndex = 1}) fixture)
    , testCase "detached replay namespace must match its closed role" $
        reject
          ( editReplay
              10
              ( \value ->
                  value
                    { Q.nativeReceiptReplayObject =
                        (Q.nativeReceiptReplayObject value)
                          { R.nativeRetainedObjectKey =
                              Text.replace
                                "native-store-loaded-replay"
                                "native-evaluation-replay"
                                (R.nativeRetainedObjectKey (Q.nativeReceiptReplayObject value))
                          }
                    }
              )
              fixture
          )
    , testCase "one physical replay address cannot fill two roles" $
        case Q.nativeReceiptReplays fixture of
          a : _ ->
            reject
              (editReplay 1 (\value -> value {Q.nativeReceiptReplayObject = Q.nativeReceiptReplayObject a}) fixture)
          _ -> assertFailure "fixture has no DATA reference"
    , testCase "different supplied ref publication refuses before descriptor omission" $
        reject
          ( fixture
              { Q.nativeReceiptAllocation =
                  (Q.nativeReceiptAllocation fixture)
                    { R.nativeRetainedObjectPublication =
                        R.NativeLocalPublication R.NativeDefaultPublicationResolution (hashId 90)
                    }
              }
          )
    , testCase "malformed publication root endpoint and explicit identity refuse" $
        mapM_
          (reject . (`withPublication` fixture))
          [ R.NativeLocalPublication R.NativeDefaultPublicationResolution "bad"
          , R.NativeConfiguredPublication R.NativeDefaultPublicationResolution (hashId 1) "bad" False
          , R.NativeLocalPublication (R.NativeExplicitPublicationResolution "bad") (hashId 1)
          ]
    , testCase "missing both sources and wrong algorithm or SHA refuse" $ do
        reject (fixture {Q.nativeReceiptObservedSource = Nothing, Q.nativeReceiptSuppliedSource = Nothing})
        mapM_
          (\bad -> reject (fixture {Q.nativeReceiptObservedSource = Just bad}))
          [ Source.SourceStamp (Source.sourceDigestAlgorithm + 1) (hashId 1)
          , Source.SourceStamp Source.sourceDigestAlgorithm "bad"
          ]
    , testCase "empty excessive and infinite phase lists refuse before element traversal" $ do
        reject (fixture {Q.nativeReceiptPhases = []})
        reject
          (fixture {Q.nativeReceiptPhases = replicate 129 (error "oversized phase heads must not be forced")})
        reject (fixture {Q.nativeReceiptPhases = repeat (error "unbounded phase heads must not be forced")})
    , testCase "phase scope filename and duplicate physical addresses refuse" $
        case Q.nativeReceiptPhases fixture of
          a : b : _ -> do
            reject (fixture {Q.nativeReceiptPhases = [a, a]})
            reject
              ( fixture
                  { Q.nativeReceiptPhases =
                      [a, b {R.nativeRetainedObjectKey = Text.replace scope (hashId 99) (R.nativeRetainedObjectKey b)}]
                  }
              )
            reject (fixture {Q.nativeReceiptPhases = [a, b {R.nativeRetainedObjectSha256 = hashId 99}]})
          _ -> assertFailure "fixture missing phase DATA"
    , testCase "allocation foreign key traversal and malformed physical SHA refuse" $
        mapM_
          (\value -> reject (fixture {Q.nativeReceiptAllocation = value}))
          [ (Q.nativeReceiptAllocation fixture) {R.nativeRetainedObjectKey = "../claim.cbor"}
          , (Q.nativeReceiptAllocation fixture) {R.nativeRetainedObjectSha256 = "bad"}
          ]
    , testCase "positive closed physical byte counts cannot be zero or exceed their caps" $ do
        mapM_
          ( \count ->
              reject
                ( fixture
                    { Q.nativeReceiptAllocation =
                        (Q.nativeReceiptAllocation fixture) {R.nativeRetainedObjectBytes = count}
                    }
                )
          )
          [0, physicalCap + 1]
        mapM_
          ( \count ->
              reject
                ( editReplay
                    0
                    ( \value ->
                        value
                          { Q.nativeReceiptReplayObject =
                              (Q.nativeReceiptReplayObject value)
                                { R.nativeRetainedObjectBytes = count
                                }
                          }
                    )
                    fixture
                )
          )
          [0, physicalCap + 1]
    , testCase "maximum opaque fields and full128 phase inventory fit without cross-field sharing" $ do
        let fields =
              fixture
                { Q.nativeReceiptCohortTransport = BS.replicate 1048576 0
                , Q.nativeReceiptCompletedTrainingBytes = BS.replicate 1048576 255
                , Q.nativeReceiptAssociation = Q.NativeReceiptScenarioData (Text.replicate 8192 "x")
                , Q.nativeReceiptPhases = fmap phase [0 .. 127]
                }
        value <- right (Q.refineNativeQualificationReceiptData fields)
        assertBool
          "conservative metadata reservation"
          ( toInteger (BS.length (Q.nativeQualificationReceiptBytes value))
              < Q.maximumNativeQualificationReceiptBytes
          )
        actual <- right (Q.decodeNativeQualificationReceiptData (Q.nativeQualificationReceiptBytes value))
        assertEqual
          "all maximum opaque bits and references"
          fields
          (Q.nativeQualificationReceiptFields actual)
    , testCase "empty and cap plus one opaque fields refuse before encoding" $ do
        mapM_
          (\bytes -> reject (fixture {Q.nativeReceiptCohortTransport = bytes}))
          [BS.empty, BS.replicate 1048577 0]
        mapM_
          (\bytes -> reject (fixture {Q.nativeReceiptCompletedTrainingBytes = bytes}))
          [BS.empty, BS.replicate 1048577 0]
    , testCase "scenario UTF8 cap is bytes and never truncates Unicode" $ do
        let exact = Text.replicate 4096 "λ"
        actual <- roundtrip (fixture {Q.nativeReceiptAssociation = Q.NativeReceiptScenarioData exact})
        assertEqual
          "all8192 UTF8 bytes"
          (Q.NativeReceiptScenarioData exact)
          (Q.nativeReceiptAssociation actual)
        reject
          (fixture {Q.nativeReceiptAssociation = Q.NativeReceiptScenarioData (Text.replicate 4097 "λ")})
        reject (fixture {Q.nativeReceiptAssociation = Q.NativeReceiptScenarioData ""})
    , testCase "oversized whole metadata is refused before CBOR parsing" $
        rejectBytes (BS.replicate (4 * 1024 * 1024 + 1) 0)
    , testCase "wrong whole arity domain and version refuse" $ do
        bytes <- encoded
        rejectBytes (BS.cons 0x88 (BS.drop 1 bytes))
        rejectBytes
          (replaceOnce "jitml-native-qualification-metadata-v1" "kitml-native-qualification-metadata-v1" bytes)
        rejectBytes (replaceAt versionOffset (BS.singleton 2) bytes)
    , testCase "nonshortest array and floating version refuse" $ do
        bytes <- encoded
        rejectBytes (BS.pack [0x98, 9] <> BS.drop 1 bytes)
        rejectBytes (replaceAt versionOffset (Wire.encodeStrict (CBOR.encodeDouble 1)) bytes)
    , testCase "truncation and trailing bytes cannot borrow a canonical body" $ do
        bytes <- encoded
        mapM_ rejectBytes [BS.take 1 bytes, BS.take (BS.length bytes - 1) bytes, bytes <> BS.singleton 0]
    , testCase "impossible phase declaration refuses before list allocation" $ do
        bytes <- encoded
        let firstPhase = phase 1
            marker = Wire.encodeStrict (CBOR.encodeListLen 2 <> refEncoding firstPhase)
            hostile =
              BS.pack [0x9b, 255, 255, 255, 255, 255, 255, 255, 255] <> Wire.encodeStrict (refEncoding firstPhase)
        rejectBytes (replaceOnce marker hostile bytes)
    , testCase "impossible reference text declaration refuses before text allocation" $ do
        bytes <- encoded
        let key = R.nativeRetainedObjectKey (Q.nativeReceiptAllocation fixture)
        rejectBytes
          ( replaceOnce
              (Wire.encodeStrict (CBOR.encodeString key))
              (BS.pack [0x7b, 255, 255, 255, 255, 255, 255, 255, 255])
              bytes
          )
    , testCase "unknown association and replay alternatives refuse as closed DATA" $ do
        bytes <- encoded
        let association =
              Wire.encodeStrict
                (CBOR.encodeListLen 2 <> CBOR.encodeWord64 0 <> CBOR.encodeBytes (digestBytes (dig 4)))
            badAssociation =
              Wire.encodeStrict
                (CBOR.encodeListLen 2 <> CBOR.encodeWord64 3 <> CBOR.encodeBytes (digestBytes (dig 4)))
            replay =
              Wire.encodeStrict
                ( CBOR.encodeListLen 4
                    <> CBOR.encodeWord64 0
                    <> CBOR.encodeWord64 0
                    <> CBOR.encodeBytes (digestBytes (dig 10))
                )
            badReplay =
              Wire.encodeStrict
                ( CBOR.encodeListLen 4
                    <> CBOR.encodeWord64 3
                    <> CBOR.encodeWord64 0
                    <> CBOR.encodeBytes (digestBytes (dig 10))
                )
        rejectBytes (replaceOnce association badAssociation bytes)
        rejectBytes (replaceOnce replay badReplay bytes)
    ]

fixture :: Q.NativeQualificationReceiptFields
fixture =
  Q.NativeQualificationReceiptFields
    "ordinary-row"
    LinuxCPU
    (dig 1)
    experiment
    (dig 2)
    "opaque cohort DATA"
    (dig 3)
    "opaque completed DATA"
    publication
    (Q.NativeReceiptDirectData (dig 4))
    (Just stamp)
    (Just stamp)
    allocation
    [phase 1, phase 2]
    replays
publication :: R.NativePublicationData
publication = R.NativeLocalPublication R.NativeDefaultPublicationResolution (hashId 1)
publications :: [R.NativePublicationData]
publications =
  [ publication
  , R.NativeLocalPublication (R.NativeExplicitPublicationResolution (hashId 2)) (hashId 1)
  , R.NativeConfiguredPublication R.NativeDefaultPublicationResolution (hashId 1) (hashId 3) False
  , R.NativeConfiguredPublication
      (R.NativeExplicitPublicationResolution (hashId 2))
      (hashId 1)
      (hashId 3)
      True
  ]
stamp :: Source.SourceStamp
stamp = Source.SourceStamp Source.sourceDigestAlgorithm (hashId 4)
experiment :: Text
experiment = "product-row-DATA"
scope :: Text
scope = hashId 5
allocation :: R.NativeRetainedObjectData
allocation =
  R.NativeRetainedObjectData
    ("jitml-checkpoints/native-rl-allocations-v1/" <> scope <> "/claim.cbor")
    (hashId 6)
    256
    publication
phase :: Word8 -> R.NativeRetainedObjectData
phase n =
  R.NativeRetainedObjectData
    ("jitml-checkpoints/native-rl-allocations-v1/" <> scope <> "/phases/" <> hashId n <> ".cbor")
    (hashId n)
    256
    publication

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore replays "Use zipWithFrom" -}
replays :: [Q.NativeReceiptReplayReference]
replays =
  zipWith
    entry
    [20 ..]
    ( concatMap
        (\index -> [(Replay.InitialModelReplay, index), (Replay.FinalModelReplay, index)])
        [0 .. 4]
        <> [(Replay.StoredFinalModelReplay, 0)]
    )
 where
  entry n (stage, index) =
    let kind =
          if stage == Replay.StoredFinalModelReplay
            then R.NativeStoreLoadedReplayArtifact
            else R.NativeEvaluationReplayArtifact
        sha = hashId n
        key = either (error . show) id (R.nativeDetachedArtifactKey kind experiment sha)
     in Q.NativeReceiptReplayReference
          stage
          index
          (dig (10 + fromIntegral index))
          (R.NativeRetainedObjectData key sha 256 publication)
dig :: Word8 -> Digest
dig n = either (error . show) id (mkDigest (BS.replicate 32 n))
hashId :: Word8 -> Text
hashId = sha256Hex . BS.singleton
physicalCap :: Word64
physicalCap = fromIntegral R.maximumNativeRetentionPayloadBytes + 4096
withPublication
  :: R.NativePublicationData -> Q.NativeQualificationReceiptFields -> Q.NativeQualificationReceiptFields
withPublication pub fields =
  fields
    { Q.nativeReceiptPublication = pub
    , Q.nativeReceiptAllocation = ref (Q.nativeReceiptAllocation fields)
    , Q.nativeReceiptPhases = fmap ref (Q.nativeReceiptPhases fields)
    , Q.nativeReceiptReplays =
        fmap
          (\value -> value {Q.nativeReceiptReplayObject = ref (Q.nativeReceiptReplayObject value)})
          (Q.nativeReceiptReplays fields)
    }
 where
  ref value = value {R.nativeRetainedObjectPublication = pub}

-- Keep this exact base-only list traversal; no extra dependency for the hint.
{- HLINT ignore editReplay "Use zipWithFrom" -}
editReplay
  :: Int
  -> (Q.NativeReceiptReplayReference -> Q.NativeReceiptReplayReference)
  -> Q.NativeQualificationReceiptFields
  -> Q.NativeQualificationReceiptFields
editReplay index edit fields =
  fields
    { Q.nativeReceiptReplays =
        zipWith
          (\i value -> if i == index then edit value else value)
          [0 ..]
          (Q.nativeReceiptReplays fields)
    }
roundtrip :: Q.NativeQualificationReceiptFields -> IO Q.NativeQualificationReceiptFields
roundtrip fields = do
  actual <- right (Q.refineNativeQualificationReceiptData fields)
  decoded <- right (Q.decodeNativeQualificationReceiptData (Q.nativeQualificationReceiptBytes actual))
  pure (Q.nativeQualificationReceiptFields decoded)
encoded :: IO BS.ByteString
encoded = Q.nativeQualificationReceiptBytes <$> right (Q.refineNativeQualificationReceiptData fixture)
versionOffset :: Int
versionOffset =
  BS.length
    ( Wire.encodeStrict
        (CBOR.encodeListLen 9 <> CBOR.encodeString "jitml-native-qualification-metadata-v1")
    )
replaceAt :: Int -> BS.ByteString -> BS.ByteString -> BS.ByteString
replaceAt offset bytes source = BS.take offset source <> bytes <> BS.drop (offset + 1) source
replaceOnce :: BS.ByteString -> BS.ByteString -> BS.ByteString -> BS.ByteString
replaceOnce old new source =
  let (before, after) = BS.breakSubstring old source
   in if BS.null after
        then error "DATA mutation anchor absent"
        else before <> new <> BS.drop (BS.length old) after
refEncoding :: R.NativeRetainedObjectData -> CBOR.Encoding
refEncoding value =
  CBOR.encodeListLen 3
    <> CBOR.encodeString (R.nativeRetainedObjectKey value)
    <> CBOR.encodeBytes (digestBytes (digSha (R.nativeRetainedObjectSha256 value)))
    <> CBOR.encodeWord64 (R.nativeRetainedObjectBytes value)
 where
  digSha text =
    either
      (error . show)
      id
      ( Wire.runParser
          Wire.getDigest
          (Wire.encodeStrict (CBOR.encodeBytes (BS.pack (pairs (Text.unpack text)))))
      )
  pairs (a : b : rest) = (digit a * 16 + digit b) : pairs rest
  pairs _ = []
  digit c
    | c <= '9' = fromIntegral (fromEnum c - fromEnum '0')
    | otherwise = fromIntegral (fromEnum c - fromEnum 'a' + 10)
right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable"
reject :: Q.NativeQualificationReceiptFields -> Assertion
reject fields = case Q.refineNativeQualificationReceiptData fields of
  Left _ -> pure ()
  Right _ -> assertFailure "malformed metadata DATA accepted"
rejectBytes :: BS.ByteString -> Assertion
rejectBytes bytes = case Q.decodeNativeQualificationReceiptData bytes of
  Left _ -> pure ()
  Right _ -> assertFailure "malformed metadata wire accepted"
