{-# LANGUAGE OverloadedStrings #-}

-- Ordinary reference DATA only. These synthetic fields establish no current
-- Matrix membership, actual execution, fetch, ACK, receipt or authority.
module NativeQualificationReference (nativeQualificationReferenceTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Types (CodecError (Malformed))
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.SourceDigest qualified as Source
import JitML.Substrate (Substrate (AppleSilicon, LinuxCPU, LinuxCUDA))

nativeQualificationReferenceTests :: TestTree
nativeQualificationReferenceTests =
  testGroup
    "native detached qualification reference DATA"
    [ testCase "closed reference DATA roundtrips canonical bytes without authenticating execution" $ do
        actual <- right (Reference.refineNativeQualificationReference fixture)
        Reference.nativeQualificationReferenceData actual @?= fixture
        Reference.decodeNativeQualificationReference (Reference.nativeQualificationReferenceBytes actual)
          @?= Right actual
        Reference.parseNativeQualificationReference (Reference.renderNativeQualificationReference actual)
          @?= Right actual
    , testCase "independent canonical CBOR known answer pins every ordered field" $ do
        actual <- right (Reference.refineNativeQualificationReference fixture)
        Reference.renderNativeQualificationReference actual @?= Reference.nativeQualificationReceiptPrefix
          <> canonicalHex
        Reference.parseNativeQualificationReference
          (Reference.nativeQualificationReceiptPrefix <> canonicalHex)
          @?= Right actual
    , testCase "all three closed lanes and both binding tags retain their own DATA" $
        mapM_
          ( \(lane, binding) -> do
              let value = fixture {Reference.nativeReferenceLane = lane, Reference.nativeReferenceBinding = binding}
              actual <- right (Reference.refineNativeQualificationReference value)
              decoded <-
                right
                  (Reference.decodeNativeQualificationReference (Reference.nativeQualificationReferenceBytes actual))
              Reference.nativeQualificationReferenceData decoded @?= value
          )
          [ (lane, binding)
          | lane <- [LinuxCPU, LinuxCUDA, AppleSilicon]
          , binding <- [Reference.NativeReferenceDirect, Reference.NativeReferenceScenario]
          ]
    , testCase "a synthetically named row is shape DATA and claims no canonical membership" $ do
        actual <- right (Reference.refineNativeQualificationReference fixture)
        Reference.nativeReferenceRow (Reference.nativeQualificationReferenceData actual) @?= "ordinary-row"
        Reference.nativeReferenceExperiment (Reference.nativeQualificationReferenceData actual)
          @?= "product-row-ordinary-data"
    , testCase "all-zero recorded digests remain exact ordinary SHA-shaped DATA" $ do
        let value =
              fixture
                { Reference.nativeReferenceArtifact = zeroSha
                , Reference.nativeReferenceObjectKey = objectKey experiment zeroSha
                }
        actual <- right (Reference.refineNativeQualificationReference value)
        Reference.nativeReferenceArtifact (Reference.nativeQualificationReferenceData actual) @?= zeroSha
        Reference.decodeNativeQualificationReference (Reference.nativeQualificationReferenceBytes actual)
          @?= Right actual
    , testCase "row bounds reject empty spaced control nonASCII and overlong text" $
        mapM_
          ( \value ->
              malformed
                "native receipt reference row text differs"
                (Reference.refineNativeQualificationReference fixture {Reference.nativeReferenceRow = value})
          )
          ["", "with space", "\NUL", "lambda-λ", Text.replicate 129 "a"]
    , testCase "experiment namespace rejects traversal separators controls and overlong text" $
        mapM_
          ( \value ->
              malformed
                "native receipt reference experiment namespace differs"
                (Reference.refineNativeQualificationReference fixture {Reference.nativeReferenceExperiment = value})
          )
          [ ""
          , "."
          , ".."
          , "../escape"
          , "one/two"
          , "one_two"
          , "with space"
          , "a:b"
          , "λ"
          , Text.replicate 1025 "a"
          ]
    , testCase "maximum bounded experiment remains lossless through exact detached key" $ do
        let name = Text.replicate 1024 "a"
            value =
              fixture
                { Reference.nativeReferenceExperiment = name
                , Reference.nativeReferenceObjectKey = objectKey name (sha "4")
                }
        actual <- right (Reference.refineNativeQualificationReference value)
        Reference.decodeNativeQualificationReference (Reference.nativeQualificationReferenceBytes actual)
          @?= Right actual
    , testCase "every digest field independently rejects noncanonical SHA shapes" $
        mapM_
          ( \change ->
              mapM_
                ( malformed
                    "native receipt reference SHA is not canonical lowercase SHA256"
                    . Reference.refineNativeQualificationReference
                    . change
                )
                ["", Text.replicate 63 "a", Text.replicate 65 "a", Text.replicate 64 "A", Text.replicate 64 "g"]
          )
          digestChanges
    , testCase "source algorithm is checked independently of a valid source digest" $
        mapM_
          ( \algorithm ->
              malformed
                "native receipt reference source algorithm differs"
                ( Reference.refineNativeQualificationReference
                    fixture
                      { Reference.nativeReferenceSource = Source.SourceStamp algorithm zeroSha
                      }
                )
          )
          [0, 2, maxBound]
    , testCase "detached key binds exact experiment artifact kind extension and SHA" $
        mapM_
          ( \key ->
              malformed
                "native receipt reference detached key differs from exact experiment and content address"
                (Reference.refineNativeQualificationReference fixture {Reference.nativeReferenceObjectKey = key})
          )
          [ objectKey "foreign" (sha "4")
          , objectKey experiment (sha "5")
          , "../" <> objectKey experiment (sha "4")
          , "jitml-checkpoints/" <> experiment <> "/artifacts/other/" <> sha "4" <> ".cbor"
          , objectKey experiment (sha "4") <> "/extra"
          ]
    , testCase "detached byte count accepts exact closed maximum and refuses zero overflow" $ do
        let limit = fromInteger Reference.maximumNativeQualificationBytes
        _ <-
          right
            (Reference.refineNativeQualificationReference fixture {Reference.nativeReferenceObjectBytes = limit})
        mapM_
          ( \count ->
              malformed
                "native receipt reference detached byte count exceeds the closed bound"
                (Reference.refineNativeQualificationReference fixture {Reference.nativeReferenceObjectBytes = count})
          )
          [0, limit + 1, maxBound]
    , testCase "allocation key permits only the fixed canonical claim address" $
        mapM_
          ( \key ->
              malformed
                "native receipt reference allocation key differs from its exact canonical namespace"
                (Reference.refineNativeQualificationReference fixture {Reference.nativeReferenceAllocationKey = key})
          )
          [ ""
          , "../claim.cbor"
          , "jitml-checkpoints/native-rl-allocations-v1/../claim.cbor"
          , "jitml-checkpoints/native-rl-allocations-v1/" <> sha "8" <> "/phases/" <> sha "9" <> ".cbor"
          , "jitml-checkpoints/native-rl-allocations-v1/" <> Text.replicate 64 "A" <> "/claim.cbor"
          , allocationKey <> "/extra"
          ]
    , testCase "allocation envelope bytes accept exact cap and refuse zero capplusone and Word64 maximum" $ do
        let limit = fromIntegral Retain.maximumNativeRetentionPayloadBytes + 4096
        _ <-
          right
            ( Reference.refineNativeQualificationReference
                fixture {Reference.nativeReferenceAllocationBytes = limit}
            )
        mapM_
          ( \count ->
              malformed
                "native receipt reference allocation byte count exceeds its envelope bound"
                ( Reference.refineNativeQualificationReference
                    fixture {Reference.nativeReferenceAllocationBytes = count}
                )
          )
          [0, limit + 1, maxBound]
    , testCase "decode refuses oversized outer input before any CBOR parse" $
        malformed
          "native receipt reference exceeds16KiB"
          (Reference.decodeNativeQualificationReference (BS.replicate 16385 0))
    , testCase "empty truncated and extra trailing binary payloads refuse" $ withBytes $ \bytes ->
        mapM_
          (reject . Reference.decodeNativeQualificationReference)
          [ BS.empty
          , BS.take 1 bytes
          , BS.take 7 bytes
          , BS.take (BS.length bytes - 1) bytes
          , bytes <> BS.singleton 0
          ]
    , testCase "wrong outer type arity and indefinite array refuse" $ withBytes $ \bytes ->
        mapM_
          (\first -> reject (Reference.decodeNativeQualificationReference (BS.cons first (BS.drop 1 bytes))))
          [0x93, 0x95, 0x9f, 0xa0, 0xc0]
    , testCase "nonshortest array length refuses its numerically identical count" $ withBytes $ \bytes ->
        reject (Reference.decodeNativeQualificationReference (BS.pack [0x98, 20] <> BS.drop 1 bytes))
    , testCase "unknown domain and version refuse without normalizing the payload" $ withBytes $ \bytes -> do
        badDomain <- replaceOnce (text domain) (text "jitml-native-qualification-reference-v2") bytes
        malformed
          "native receipt reference domain/version differs"
          (Reference.decodeNativeQualificationReference badDomain)
        let offset = BS.length header
        malformed
          "native receipt reference domain/version differs"
          ( Reference.decodeNativeQualificationReference
              (BS.take offset bytes <> BS.singleton 2 <> BS.drop (offset + 1) bytes)
          )
    , testCase "nonshortest version integer refuses instead of canonicalizing" $ withBytes $ \bytes -> do
        let offset = BS.length header
        reject
          ( Reference.decodeNativeQualificationReference
              (BS.take offset bytes <> BS.pack [0x18, 1] <> BS.drop (offset + 1) bytes)
          )
    , testCase "unknown binding code refuses its closed enum" $ withBytes $ \bytes -> do
        changed <- replaceOnce (text (sha "a") <> word 0) (text (sha "a") <> word 2) bytes
        malformed
          "native receipt reference binding differs"
          (Reference.decodeNativeQualificationReference changed)
    , testCase "unknown lane and accepted aliases cannot survive canonical decoding" $ withBytes $ \bytes -> do
        unknown <- replaceOnce (text "linux-cpu") (text "foreign-lane") bytes
        malformed
          "native receipt reference lane differs"
          (Reference.decodeNativeQualificationReference unknown)
        alias <- replaceOnce (text "linux-cpu") (text "cpu") bytes
        reject (Reference.decodeNativeQualificationReference alias)
    , testCase "malformed UTF8 and excessive declared text length refuse" $ withBytes $ \bytes -> do
        malformedUtf8 <- replaceOnce (text "ordinary-row") (BS.pack [0x61, 0xff]) bytes
        reject (Reference.decodeNativeQualificationReference malformedUtf8)
        reject
          ( Reference.decodeNativeQualificationReference
              (BS.pack [0x94, 0x7b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff])
          )
    , testCase "wire oversized row count and source algorithm preserve refinement guards" $ withBytes $ \bytes -> do
        longRow <- replaceOnce (text "ordinary-row") (text (Text.replicate 129 "a")) bytes
        reject (Reference.decodeNativeQualificationReference longRow)
        algorithm <-
          replaceOnce
            (text (sha "6") <> word 1 <> text zeroSha)
            (text (sha "6") <> word 2 <> text zeroSha)
            bytes
        malformed
          "native receipt reference source algorithm differs"
          (Reference.decodeNativeQualificationReference algorithm)
    , testCase "wire detached count cannot bypass the ordinary bound" $ withBytes $ \bytes -> do
        changed <-
          replaceOnce
            (text (objectKey experiment (sha "4")) <> word 17)
            (text (objectKey experiment (sha "4")) <> word maxBound)
            bytes
        malformed
          "native receipt reference detached byte count exceeds the closed bound"
          (Reference.decodeNativeQualificationReference changed)
    , testCase "renderer has exact prefix lowercase hex and no newline" $ do
        actual <- right (Reference.refineNativeQualificationReference fixture)
        let rendered = Reference.renderNativeQualificationReference actual
        assertBool
          "exact prefix absent"
          (Reference.nativeQualificationReceiptPrefix `Text.isPrefixOf` rendered)
        assertBool "newline was appended" (not (Text.any (== '\n') rendered))
        Reference.parseNativeQualificationReference rendered @?= Right actual
    , testCase "hex parser rejects changed prefix empty body odd length and trailing text" $ do
        actual <- right (Reference.refineNativeQualificationReference fixture)
        let rendered = Reference.renderNativeQualificationReference actual
        mapM_
          (reject . Reference.parseNativeQualificationReference)
          [ "wrong: " <> canonicalHex
          , Reference.nativeQualificationReceiptPrefix
          , Text.dropEnd 1 rendered
          , rendered <> "\n"
          , rendered <> "  "
          ]
    , testCase "hex parser rejects uppercase nonASCII and nonhex characters" $
        mapM_
          ( \body ->
              malformed
                "native receipt reference hex is not lowercase canonical ASCII"
                (Reference.parseNativeQualificationReference (Reference.nativeQualificationReceiptPrefix <> body))
          )
          [Text.toUpper canonicalHex, "gg", "λ0", "０0"]
    , testCase "hex text cap refuses overlong body before allocation" $
        malformed
          "native receipt reference hex length differs"
          ( Reference.parseNativeQualificationReference
              (Reference.nativeQualificationReceiptPrefix <> Text.replicate 32770 "0")
          )
    , testCase "reordered complete fields do not silently normalize" $ withBytes $ \bytes -> do
        changed <- replaceOnce (text (sha "5") <> text experiment) (text experiment <> text (sha "5")) bytes
        reject (Reference.decodeNativeQualificationReference changed)
    ]

fixture :: Reference.NativeQualificationReferenceData
fixture =
  Reference.NativeQualificationReferenceData
    "ordinary-row"
    LinuxCPU
    (sha "5")
    experiment
    (sha "6")
    (Source.SourceStamp Source.sourceDigestAlgorithm zeroSha)
    (sha "1")
    (sha "2")
    (sha "3")
    (sha "4")
    (objectKey experiment (sha "4"))
    17
    (sha "a")
    Reference.NativeReferenceDirect
    allocationKey
    (sha "7")
    19

-- These changes address every separately validated SHA-shaped field.
digestChanges :: [Text -> Reference.NativeQualificationReferenceData]
digestChanges =
  [ \x -> fixture {Reference.nativeReferencePlan = x}
  , \x -> fixture {Reference.nativeReferenceManifest = x}
  , \x -> fixture {Reference.nativeReferenceSource = Source.SourceStamp Source.sourceDigestAlgorithm x}
  , \x -> fixture {Reference.nativeReferenceExecutable = x}
  , \x -> fixture {Reference.nativeReferenceInvocation = x}
  , \x -> fixture {Reference.nativeReferenceCohort = x}
  , \x -> fixture {Reference.nativeReferenceArtifact = x}
  , \x -> fixture {Reference.nativeReferencePublication = x}
  , \x -> fixture {Reference.nativeReferenceAllocationSha = x}
  ]

sha :: Text -> Text
sha = Text.replicate 64
zeroSha :: Text
zeroSha = sha "0"
experiment :: Text
experiment = "product-row-ordinary-data"
allocationKey :: Text
allocationKey = "jitml-checkpoints/native-rl-allocations-v1/" <> sha "8" <> "/claim.cbor"
objectKey :: Text -> Text -> Text
objectKey name digest = "jitml-checkpoints/" <> name <> "/artifacts/native-qualification/" <> digest <> ".cbor"
domain :: Text
domain = "jitml-native-qualification-reference-v1"
header :: BS.ByteString
header = Wire.encodeStrict (CBOR.encodeListLen 20 <> CBOR.encodeString domain)
text :: Text -> BS.ByteString
text = Wire.encodeStrict . CBOR.encodeString
word :: Word64 -> BS.ByteString
word = Wire.encodeStrict . CBOR.encodeWord64

withBytes :: (BS.ByteString -> Assertion) -> Assertion
withBytes action = do
  actual <- right (Reference.refineNativeQualificationReference fixture)
  action (Reference.nativeQualificationReferenceBytes actual)
replaceOnce :: BS.ByteString -> BS.ByteString -> BS.ByteString -> IO BS.ByteString
replaceOnce needle replacement source = do
  let (before, rest) = BS.breakSubstring needle source
  assertBool "independent mutation anchor absent" (not (BS.null rest))
  assertEqual
    "mutation anchor repeats"
    BS.empty
    (snd (BS.breakSubstring needle (BS.drop (BS.length needle) rest)))
  pure (before <> replacement <> BS.drop (BS.length needle) rest)
malformed :: Text -> Either CodecError a -> Assertion
malformed expected result = case result of
  Left (Malformed actual) -> actual @?= expected
  Left other -> assertFailure ("wrong refusal: " <> show other)
  Right _ -> assertFailure "invalid ordinary reference DATA was accepted"
reject :: Either e a -> Assertion
reject result = case result of
  Left _ -> pure ()
  Right _ -> assertFailure "invalid ordinary reference DATA was accepted"
right :: (Show e) => Either e a -> IO a
right result = case result of
  Right value -> pure value
  Left failure -> assertFailure (show failure) >> fail "unreachable"

-- Frozen independent Python shortest-CBOR encoding; no production encoder or
-- Haskell parser produced this known answer. See independent-known-answer.py.
canonicalHex :: Text
canonicalHex =
  "9478276a69746d6c2d6e61746976652d7175616c696669636174696f6e2d7265666572656e63652d7631016c6f7264696e6172792d726f77696c696e75782d637075784035353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535781970726f647563742d726f772d6f7264696e6172792d646174617840363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636360178403030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303030303078403131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313131313178403232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323232323278403333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333378403434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343478906a69746d6c2d636865636b706f696e74732f70726f647563742d726f772d6f7264696e6172792d646174612f6172746966616374732f6e61746976652d7175616c696669636174696f6e2f343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434342e63626f72117840616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161616161610078766a69746d6c2d636865636b706f696e74732f6e61746976652d726c2d616c6c6f636174696f6e732d76312f383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838383838382f636c61696d2e63626f7278403737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373737373713"
