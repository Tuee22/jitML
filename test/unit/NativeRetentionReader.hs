{-# LANGUAGE OverloadedStrings #-}

-- Ordinary independently assembled wire fixtures only. These physical-byte
-- comparisons mint no actual write/ACK/cursor/producer/authentication capsule.
module NativeRetentionReader (nativeRetentionReaderTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types
  ( CodecError (ResourceExceeded)
  , Resource (WholePayloadBytes)
  )
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.NativeRetentionReader qualified as Reader
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)

nativeRetentionReaderTests :: TestTree
nativeRetentionReaderTests =
  testGroup
    "native retained envelope DATA controls"
    [ testCase "allocation preserves exact scope publication and opaque payload DATA" $ do
        let bytes = claimBytes scope local "actual payload"
        decoded <- mustRight (Reader.decodeNativeAllocationEnvelope (claimRef scope local bytes) bytes)
        assertEqual "scope" scope (Reader.decodedAllocationScope decoded)
        assertEqual "publication" local (Reader.decodedAllocationPublication decoded)
        assertEqual "actual opaque bytes" "actual payload" (Reader.decodedAllocationPayload decoded)
    , testCase "phase zero and one bind their exact physical predecessors in order" $ do
        (allocation, first, second) <- twoPhases
        mustRight
          ( Reader.validateNativeRetentionPhaseLink
              allocation
              (Reader.decodedAllocationObject allocation)
              0
              first
          )
        mustRight
          (Reader.validateNativeRetentionPhaseLink allocation (Reader.decodedPhaseObject first) 1 second)
        assertEqual
          "labels"
          ["reference-calibration", "child-0.started"]
          (fmap Reader.decodedPhaseLabel [first, second])
        assertEqual
          "opaque phase payloads"
          ["references", "started"]
          (fmap Reader.decodedPhasePayload [first, second])
    , testCase "configured and explicit publication identities remain distinct exact DATA" $ do
        let publication = Retain.NativeConfiguredPublication (Retain.NativeExplicitPublicationResolution h1) h0 h1 True
            bytes = claimBytes scope publication BS.empty
        decoded <-
          mustRight (Reader.decodeNativeAllocationEnvelope (claimRef scope publication bytes) bytes)
        assertEqual "configured scope" publication (Reader.decodedAllocationPublication decoded)
    , testCase
        "full legal 256MiB payload accepts its larger retention envelope without widening child parser"
        $ do
          let cap = fromIntegral Retain.maximumNativeRetentionPayloadBytes
              payload = BS.replicate cap 0xa5
              bytes = claimBytes scope local payload
          assertBool "outer envelope exceeds the unchanged child whole-payload cap" (BS.length bytes > cap)
          decoded <- mustRight (Reader.decodeNativeAllocationEnvelope (claimRef scope local bytes) bytes)
          assertEqual "complete payload length" cap (BS.length (Reader.decodedAllocationPayload decoded))
          assertEqual
            "complete actual payload SHA"
            (sha256Hex payload)
            (sha256Hex (Reader.decodedAllocationPayload decoded))
          reject (Wire.runParser Wire.getNull bytes)
    , testCase "truncated and trailing payload refuse even with updated physical SHA and byte count" $ do
        let bytes = claimBytes scope local "actual payload"
        mapM_
          (\changed -> reject (Reader.decodeNativeAllocationEnvelope (claimRef scope local changed) changed))
          [BS.init bytes, bytes <> BS.singleton 0]
    , testCase "oversized declared payload refuses its header before absent body allocation" $ do
        let declared = fromIntegral Retain.maximumNativeRetentionPayloadBytes + 1 :: Word64
            -- Independently assembled shortest bytestring header for 256MiB+1.
            bytes = claimPrefix scope local <> BS.pack [0x5a, 0x10, 0x00, 0x00, 0x01]
        case Reader.decodeNativeAllocationEnvelope (claimRef scope local bytes) bytes of
          Left (Reader.NativeRetentionEnvelopeCodec (ResourceExceeded WholePayloadBytes cap seen)) -> do
            assertEqual "fixed raw payload cap" (toInteger Retain.maximumNativeRetentionPayloadBytes) cap
            assertEqual "actual declared size" (toInteger declared) seen
          _ -> assertFailure "declared size did not refuse before the missing body"
    , testCase "recorded physical count and SHA mismatches refuse independently" $ do
        let bytes = claimBytes scope local "actual payload"
            reference = claimRef scope local bytes
        reject
          ( Reader.decodeNativeAllocationEnvelope
              (reference {Retain.nativeRetainedObjectBytes = Retain.nativeRetainedObjectBytes reference + 1})
              bytes
          )
        reject
          (Reader.decodeNativeAllocationEnvelope (reference {Retain.nativeRetainedObjectSha256 = h0}) bytes)
    , testCase "mutated recorded scope cannot keep the selected fixed claim address" $ do
        let changed = scope {Retain.nativeAllocationRow = "foreign-row"}
            bytes = claimBytes changed local BS.empty
            expected = claimRef scope local bytes
        reject (Reader.decodeNativeAllocationEnvelope expected bytes)
    , testCase "source algorithm and malformed scope digests refuse through the actual public refiner" $ do
        let badAlgorithm = scope {Retain.nativeAllocationSource = Source.SourceStamp 2 h0}
            badRecipe = scope {Retain.nativeAllocationRecipeSha256 = "not-a-sha"}
        mapM_
          ( \changed ->
              let bytes = claimBytes changed local BS.empty
               in reject (Reader.decodeNativeAllocationEnvelope (claimRef scope local bytes) bytes)
          )
          [badAlgorithm, badRecipe]
    , testCase "publication relabeling cannot borrow the same outer bytes" $ do
        let bytes = claimBytes scope local BS.empty
            reference = claimRef scope local bytes
            foreignPublication = Retain.NativeConfiguredPublication Retain.NativeDefaultPublicationResolution h0 h1 False
        reject
          ( Reader.decodeNativeAllocationEnvelope
              (reference {Retain.nativeRetainedObjectPublication = foreignPublication})
              bytes
          )
    , testCase "foreign claim and skipped ordinal fail explicit whole-chain DATA binding" $ do
        (allocation, first, second) <- twoPhases
        let foreignScope = scope {Retain.nativeAllocationAcquisitionId = "different-slot"}
            bytes = claimBytes foreignScope local BS.empty
        foreignAllocation <-
          mustRight (Reader.decodeNativeAllocationEnvelope (claimRef foreignScope local bytes) bytes)
        reject
          ( Reader.validateNativeRetentionPhaseLink
              foreignAllocation
              (Reader.decodedAllocationObject foreignAllocation)
              0
              first
          )
        reject
          (Reader.validateNativeRetentionPhaseLink allocation (Reader.decodedPhaseObject first) 2 second)
    , testCase "wrong previous SHA and later jump back to claim refuse" $ do
        (allocation, first, _) <- twoPhases
        let claim = Reader.decodedAllocationObject allocation
            claimKey = Retain.nativeRetainedObjectKey claim
            bytes =
              phaseBytes claimKey (Retain.nativeRetainedObjectSha256 claim) local 0 claimKey h1 "started" BS.empty
        changed <-
          mustRight (Reader.decodeNativeRetentionPhaseEnvelope (phaseRef claimKey local bytes) bytes)
        reject (Reader.validateNativeRetentionPhaseLink allocation claim 0 changed)
        let jumped =
              phaseBytes
                claimKey
                (Retain.nativeRetainedObjectSha256 claim)
                local
                1
                claimKey
                (Retain.nativeRetainedObjectSha256 claim)
                "started"
                BS.empty
        later <-
          mustRight (Reader.decodeNativeRetentionPhaseEnvelope (phaseRef claimKey local jumped) jumped)
        reject (Reader.validateNativeRetentionPhaseLink allocation claim 1 later)
        reject
          (Reader.validateNativeRetentionPhaseLink allocation (Reader.decodedPhaseObject first) 1 later)
    , testCase "claim and predecessor path traversal or foreign allocation namespace refuse" $ do
        let claim = claimKeyFor scope
            bytes1 =
              phaseBytes
                "jitml-checkpoints/native-rl-allocations-v1/../claim.cbor"
                h0
                local
                0
                claim
                h0
                "started"
                BS.empty
            bytes2 =
              phaseBytes
                claim
                h0
                local
                1
                ("jitml-checkpoints/native-rl-allocations-v1/" <> h1 <> "/phases/" <> h0 <> ".cbor")
                h0
                "started"
                BS.empty
        reject (Reader.decodeNativeRetentionPhaseEnvelope (phaseRef claim local bytes1) bytes1)
        reject (Reader.decodeNativeRetentionPhaseEnvelope (phaseRef claim local bytes2) bytes2)
    , testCase "physical phase filename must contain the same exact outer object SHA" $ do
        let claim = claimKeyFor scope
            bytes = phaseBytes claim h0 local 0 claim h0 "started" BS.empty
            reference = phaseRef claim local bytes
        reject
          ( Reader.decodeNativeRetentionPhaseEnvelope
              (reference {Retain.nativeRetainedObjectKey = phaseNamespace claim <> "/phases/" <> h0 <> ".cbor"})
              bytes
          )
    , testCase "wrong envelope domain and nonshortest outer array heads refuse" $ do
        let bytes = claimBytes scope local BS.empty
            nonshortest = BS.pack [0x98, 0x04] <> BS.drop 1 bytes
            foreignDomain =
              Wire.encodeStrict
                ( CBOR.encodeListLen 4
                    <> CBOR.encodeString "wrong-domain"
                    <> CBOR.encodeBytes (scopeEncoding scope)
                    <> CBOR.encodeBytes (publicationEncoding local)
                    <> CBOR.encodeBytes BS.empty
                )
        mapM_
          (\changed -> reject (Reader.decodeNativeAllocationEnvelope (claimRef scope local changed) changed))
          [foreignDomain, nonshortest]
    , testCase "closed phase label alphabet and writer-exhausted ordinal refuse" $ do
        let claim = claimKeyFor scope
        mapM_
          ( \(ordinal, label) ->
              let bytes = phaseBytes claim h0 local ordinal claim h0 label BS.empty
               in reject (Reader.decodeNativeRetentionPhaseEnvelope (phaseRef claim local bytes) bytes)
          )
          [(0, ""), (0, "ContainsUppercase"), (0, "bad/label"), (maxBound, "started")]
    , testCase "local publication cannot claim an endpoint or mounted service" $ do
        let malformedPublication =
              Wire.encodeStrict
                ( CBOR.encodeListLen 7
                    <> CBOR.encodeString "jitml-native-retention-publication-v1"
                    <> CBOR.encodeString "jitml-checkpoints"
                    <> CBOR.encodeBytes (resolutionEncoding Retain.NativeDefaultPublicationResolution)
                    <> CBOR.encodeString "local"
                    <> CBOR.encodeString h0
                    <> CBOR.encodeString h1
                    <> CBOR.encodeBool True
                )
            bytes = claimWithPublicationBytes scope malformedPublication BS.empty
        reject (Reader.decodeNativeAllocationEnvelope (claimRef scope local bytes) bytes)
    , testCase "nested trailing publication data and malformed resolution identity refuse" $ do
        let malformed = Retain.NativeLocalPublication (Retain.NativeExplicitPublicationResolution "bad") h0
            bytes1 = claimWithPublicationBytes scope (publicationEncoding local <> BS.singleton 0) BS.empty
            bytes2 = claimBytes scope malformed BS.empty
        mapM_
          (\bytes -> reject (Reader.decodeNativeAllocationEnvelope (claimRef scope local bytes) bytes))
          [bytes1, bytes2]
    , testCase "bounded prefix consumes only the header while whole parser still rejects trailing bytes" $ do
        let bytes = Wire.encodeStrict (CBOR.encodeBytes "abc") <> BS.singleton 0
        (declared, offset) <-
          mustRight (Wire.runParserPrefix (Wire.getBytesLength WholePayloadBytes 3) bytes)
        assertEqual "actual declared payload" 3 declared
        assertEqual "shortest bytestring head only" 1 offset
        reject (Wire.runParser (Wire.getBytes WholePayloadBytes 3) bytes)
        reject (Wire.runParserPrefix (Wire.getBytesLength WholePayloadBytes 3) (BS.pack [0x58, 0x03]))
    ]

mustRight :: (Show e) => Either e a -> IO a
mustRight value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable"

reject :: Either e a -> IO ()
reject value = case value of
  Left _ -> pure ()
  Right _ -> assertFailure "malformed ordinary envelope DATA was accepted"

h0, h1 :: Text
h0 = Text.replicate 64 "0"
h1 = Text.replicate 64 "1"

scope :: Retain.NativeAllocationScope
scope =
  Retain.NativeAllocationScope
    (Retain.NativeSuppliedScenarioDigest h0)
    "DQN/cartpole"
    (Source.SourceStamp 1 h0)
    h1
    "actual-fixed-invocation-slot"

local :: Retain.NativePublicationData
local = Retain.NativeLocalPublication Retain.NativeDefaultPublicationResolution h0

claimKeyFor :: Retain.NativeAllocationScope -> Text
claimKeyFor actual = case Retain.mkNativeAllocationAddress actual of
  Left _ -> error "test attempted to construct an invalid reference address"
  Right address -> Retain.nativeAllocationAddressKey address

claimRef
  :: Retain.NativeAllocationScope
  -> Retain.NativePublicationData
  -> ByteString
  -> Retain.NativeRetainedObjectData
claimRef actual publication bytes =
  Retain.NativeRetainedObjectData
    (claimKeyFor actual)
    (sha256Hex bytes)
    (fromIntegral (BS.length bytes))
    publication

phaseNamespace :: Text -> Text
phaseNamespace claim = case Text.stripSuffix "/claim.cbor" claim of
  Just prefix -> prefix
  Nothing -> error "test reference claim has no suffix"

phaseRef :: Text -> Retain.NativePublicationData -> ByteString -> Retain.NativeRetainedObjectData
phaseRef claim publication bytes =
  Retain.NativeRetainedObjectData
    (phaseNamespace claim <> "/phases/" <> sha256Hex bytes <> ".cbor")
    (sha256Hex bytes)
    (fromIntegral (BS.length bytes))
    publication

scopeEncoding :: Retain.NativeAllocationScope -> ByteString
scopeEncoding actual =
  Wire.encodeStrict
    ( CBOR.encodeListLen 8
        <> CBOR.encodeString "jitml-native-allocation-scope-v1"
        <> ( case Retain.nativeAllocationContext actual of
               Retain.NativeSuppliedScenarioDigest value -> CBOR.encodeString "supplied-scenario" <> CBOR.encodeString value
               Retain.NativeDirectLocalAcquisition value -> CBOR.encodeString "direct-local" <> CBOR.encodeString value
           )
        <> CBOR.encodeString (Retain.nativeAllocationRow actual)
        <> CBOR.encodeWord64 (Source.stampAlgorithm (Retain.nativeAllocationSource actual))
        <> CBOR.encodeString (Source.stampSha256 (Retain.nativeAllocationSource actual))
        <> CBOR.encodeString (Retain.nativeAllocationRecipeSha256 actual)
        <> CBOR.encodeString (Retain.nativeAllocationAcquisitionId actual)
    )

resolutionEncoding :: Retain.NativePublicationResolution -> ByteString
resolutionEncoding actual =
  Wire.encodeStrict
    ( CBOR.encodeListLen 2 <> case actual of
        Retain.NativeDefaultPublicationResolution -> CBOR.encodeString "default" <> CBOR.encodeString ""
        Retain.NativeExplicitPublicationResolution value -> CBOR.encodeString "explicit-filesystem" <> CBOR.encodeString value
    )

publicationEncoding :: Retain.NativePublicationData -> ByteString
publicationEncoding actual =
  Wire.encodeStrict
    ( CBOR.encodeListLen 7 <> CBOR.encodeString "jitml-native-retention-publication-v1" <> CBOR.encodeString "jitml-checkpoints" <> case actual of
        Retain.NativeLocalPublication resolution root ->
          CBOR.encodeBytes (resolutionEncoding resolution)
            <> CBOR.encodeString "local"
            <> CBOR.encodeString root
            <> CBOR.encodeString ""
            <> CBOR.encodeBool False
        Retain.NativeConfiguredPublication resolution root endpoint fromBoot ->
          CBOR.encodeBytes (resolutionEncoding resolution)
            <> CBOR.encodeString "configured"
            <> CBOR.encodeString root
            <> CBOR.encodeString endpoint
            <> CBOR.encodeBool fromBoot
    )

claimPrefix :: Retain.NativeAllocationScope -> Retain.NativePublicationData -> ByteString
claimPrefix actual publication =
  Wire.encodeStrict
    ( CBOR.encodeListLen 4
        <> CBOR.encodeString "jitml-native-allocation-claim-v1"
        <> CBOR.encodeBytes (scopeEncoding actual)
        <> CBOR.encodeBytes (publicationEncoding publication)
    )

claimWithPublicationBytes :: Retain.NativeAllocationScope -> ByteString -> ByteString -> ByteString
claimWithPublicationBytes actual publication payload =
  Wire.encodeStrict
    ( CBOR.encodeListLen 4
        <> CBOR.encodeString "jitml-native-allocation-claim-v1"
        <> CBOR.encodeBytes (scopeEncoding actual)
        <> CBOR.encodeBytes publication
        <> CBOR.encodeBytes payload
    )

claimBytes
  :: Retain.NativeAllocationScope -> Retain.NativePublicationData -> ByteString -> ByteString
claimBytes actual publication = claimWithPublicationBytes actual (publicationEncoding publication)

phaseBytes
  :: Text
  -> Text
  -> Retain.NativePublicationData
  -> Word64
  -> Text
  -> Text
  -> Text
  -> ByteString
  -> ByteString
phaseBytes claim claimSha publication ordinal previous previousSha label payload =
  Wire.encodeStrict
    ( CBOR.encodeListLen 9
        <> CBOR.encodeString "jitml-native-retention-phase-v1"
        <> CBOR.encodeString claim
        <> CBOR.encodeString claimSha
        <> CBOR.encodeBytes (publicationEncoding publication)
        <> CBOR.encodeWord64 ordinal
        <> CBOR.encodeString previous
        <> CBOR.encodeString previousSha
        <> CBOR.encodeString label
        <> CBOR.encodeBytes payload
    )

twoPhases
  :: IO
       ( Reader.NativeDecodedAllocation
       , Reader.NativeDecodedRetentionPhase
       , Reader.NativeDecodedRetentionPhase
       )
twoPhases = do
  let claim = claimBytes scope local "planned five DATA"
      claimObject = claimRef scope local claim
      key = Retain.nativeRetainedObjectKey claimObject
      sha = Retain.nativeRetainedObjectSha256 claimObject
      first = phaseBytes key sha local 0 key sha "reference-calibration" "references"
      firstObject = phaseRef key local first
      second =
        phaseBytes
          key
          sha
          local
          1
          (Retain.nativeRetainedObjectKey firstObject)
          (Retain.nativeRetainedObjectSha256 firstObject)
          "child-0.started"
          "started"
  allocation <- mustRight (Reader.decodeNativeAllocationEnvelope claimObject claim)
  a <- mustRight (Reader.decodeNativeRetentionPhaseEnvelope firstObject first)
  b <- mustRight (Reader.decodeNativeRetentionPhaseEnvelope (phaseRef key local second) second)
  pure (allocation, a, b)
