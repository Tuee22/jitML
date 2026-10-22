{-# LANGUAGE OverloadedStrings #-}

-- These are ordinary wire/graph fixtures. None is a trained model, canonical
-- source plan, recorded actual process, retained ACK or eligible completion.
module NativePhaseCodec (nativePhaseCodecTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Int (Int64)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.Builder
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Codec
import JitML.Checkpoint.NativePhase.Graph
import JitML.Checkpoint.NativePhase.Schema
import JitML.Checkpoint.NativePhase.Types

-- Keep this total base-only list operation; no extra package is required.
{- HLINT ignore nativePhaseCodecTests "Use drop1" -}
nativePhaseCodecTests :: TestTree
nativePhaseCodecTests =
  testGroup
    "bounded canonical native phase DATA codec"
    [ testCase "canonical Started phase roundtrips the exact reachable DATA pool" $ do
        phase <- mustRight startedFixture
        decoded <- mustRight (decodePhaseData (encodePhaseData phase))
        assertEqual "phase" StartedPhase (phaseDataPhase decoded)
        assertEqual "actual body bytes identity" (phaseDataRoot phase) (phaseDataRoot decoded)
        assertEqual
          "context DATA"
          (contextFields (phaseDataContext phase))
          (contextFields (phaseDataContext decoded))
        assertEqual "canonical whole bytes" (encodePhaseData phase) (encodePhaseData decoded)
        assertEqual
          "full byte accounting"
          (toInteger (BS.length (encodePhaseData decoded)))
          (usageEncodedBytes (phaseDataUsage decoded))
    , testCase "empty tensor has an independent exact canonical CBOR known answer" $ do
        node <- mustRight (mkNodeData NTensorLeaf [VWord 0, VBytes BS.empty])
        assertEqual
          "RFC8949 definite array unsigneds empty bytes"
          (BS.pack [0x83, 0, 0, 0x40])
          (nodeCanonicalBytes node)
        decoded <- mustRight (decodeNodeData (BS.pack [0x83, 0, 0, 0x40]))
        assertEqual "exact node" node decoded
    , testCase "all73 node tags keep the frozen protocol inventory and arities" $ do
        let expectedTags =
              [ 0
              , 1
              , 2
              , 3
              , 4
              , 5
              , 6
              , 7
              , 8
              , 9
              , 10
              , 11
              , 12
              , 13
              , 14
              , 20
              , 21
              , 22
              , 23
              , 24
              , 25
              , 30
              , 31
              , 32
              , 33
              , 34
              , 35
              , 40
              , 41
              , 42
              , 43
              , 44
              , 45
              , 46
              , 47
              , 50
              , 51
              , 52
              , 53
              , 54
              , 55
              , 56
              , 57
              , 60
              , 61
              , 62
              , 70
              , 71
              , 72
              , 73
              , 74
              , 75
              , 80
              , 81
              , 82
              , 83
              , 84
              , 85
              , 86
              , 87
              , 88
              , 89
              , 90
              , 91
              , 92
              , 93
              , 94
              , 95
              , 96
              , 97
              , 98
              , 99
              , 100
              ]
            expectedArities =
              [ 3
              , 6
              , 5
              , 4
              , 4
              , 4
              , 3
              , 5
              , 5
              , 4
              , 4
              , 5
              , 4
              , 11
              , 14
              , 27
              , 19
              , 20
              , 29
              , 15
              , 10
              , 6
              , 5
              , 4
              , 5
              , 3
              , 4
              , 6
              , 4
              , 14
              , 3
              , 6
              , 6
              , 6
              , 4
              , 2
              , 15
              , 18
              , 18
              , 27
              , 12
              , 5
              , 12
              , 11
              , 8
              , 14
              , 8
              , 9
              , 7
              , 14
              , 6
              , 5
              , 11
              , 4
              , 5
              , 6
              , 8
              , 3
              , 3
              , 10
              , 6
              , 7
              , 9
              , 2
              , 6
              , 7
              , 4
              , 13
              , 8
              , 5
              , 4
              , 8
              , 4
              ]
        assertEqual "73 exact tags" expectedTags (fmap nodeTag allNodeKinds)
        assertEqual
          "all declared arities"
          expectedArities
          (fmap ((+ 1) . length . nodeFieldNames) allNodeKinds)
    , testCase "raw F64 signedzero and distinct NaN payloads remain byte distinct" $ do
        let wordsToKeep = [0, 0x8000000000000000, 0x7ff8000000001234, 0x7ff8000000001235, 0x7ff0000000000000]
        digests <-
          mapM
            ( \word -> do
                node <- mustRight (mkNodeData NTensorLeaf [VWord 1, VBytes (Wire.word64Bytes word)])
                decoded <- mustRight (decodeNodeData (nodeCanonicalBytes node))
                assertEqual "all original bits" (nodeFields node) (nodeFields decoded)
                (digest, _) <- mustRight (internNode decoded emptyNodePool)
                pure digest
            )
            wordsToKeep
        assertEqual
          "all five bit identities distinct"
          5
          (Map.size (Map.fromList [(digest, ()) | digest <- digests]))
    , testCase "non-shortest unsigned CBOR is rejected" $
        refusal isNonCanonical (decodeNodeData (BS.pack [0x83, 0x18, 0, 0, 0x40]))
    , testCase "indefinite arrays and reserved length arguments are rejected" $ do
        refusal isNonCanonical (decodeNodeData (BS.pack [0x9f, 0, 0, 0x40, 0xff]))
        refusal isNonCanonical (decodeNodeData (BS.pack [0x9c]))
    , testCase "trailing node and phase bytes are rejected" $ do
        refusal isNonCanonical (decodeNodeData (BS.pack [0x83, 0, 0, 0x40, 0]))
        phase <- mustRight startedFixture
        refusal isNonCanonical (decodePhaseData (encodePhaseData phase <> BS.singleton 0))
    , testCase "unknown node tag and wrong fixed arity fail before graph admission" $ do
        refusal isMalformed (decodeNodeData (BS.pack [0x81, 0x0f]))
        refusal isMalformed (decodeNodeData (BS.pack [0x82, 0, 0x40]))
    , testCase "CBOR floats cannot substitute for raw F64 bit bytes" $
        refusal
          isMalformed
          ( decodeNodeData
              ( Wire.encodeStrict
                  ( CBOR.encodeListLen 4
                      <> CBOR.encodeWord64 35
                      <> CBOR.encodeInt64 0
                      <> CBOR.encodeDouble 1
                      <> CBOR.encodeBytes (Wire.word64Bytes 0)
                  )
              )
          )
    , testCase "signed64 extrema roundtrip and positive overflow rejects" $ do
        forM_ [minBound :: Int64, maxBound] $ \n -> do
          let bytes = Wire.encodeStrict (CBOR.encodeInt64 n)
          actual <- mustRight (Wire.runParser Wire.getInt64 bytes)
          assertEqual "exact signed64" n actual
        refusal
          isMalformed
          (Wire.runParser Wire.getInt64 (Wire.encodeStrict (CBOR.encodeWord64 0x8000000000000000)))
    , testCase "bignum tags cannot bypass uint64 and magnitude rules" $
        refusal isMalformed (Wire.runParser Wire.getWord (BS.pack [0xc2, 0x49, 1, 0, 0, 0, 0, 0, 0, 0, 0]))
    , testCase "malformed UTF8 is rejected before text DATA is returned" $
        refusal isMalformed (Wire.runParser (Wire.getText GeneralTextBytes 1024) (BS.pack [0x61, 0xc0]))
    , testCase "text limits count UTF8 bytes rather than characters" $ do
        phase <- mustRight startedFixture
        let values = contextFields (phaseDataContext phase)
        case values of
          _ : rest ->
            refusal (isResource GeneralTextBytes) (mkContextData (VText (Text.replicate 1024 "\x10000") : rest))
          [] -> assertFailure "fixture context unexpectedly empty"
    , testCase "oversized declared byte lengths refuse without their payload" $
        refusal
          (isResource TensorChunkBytes)
          (decodeNodeData (BS.pack [0x83, 0, 0, 0x5a, 0xff, 0xff, 0xff, 0xff]))
    , testCase "oversized and impossible declared arrays refuse before allocation" $ do
        refusal
          (isResource SequenceFanout)
          (Wire.runParser (Wire.getListLength SequenceFanout 256) (BS.pack [0x9a, 0xff, 0xff, 0xff, 0xff]))
        refusal
          isUnexpectedEnd
          (Wire.runParser (Wire.getListLength SequenceFanout 256) (BS.pack [0x98, 0x80]))
    , testCase "unknown closed enum and inline sum tags are rejected" $ do
        refusal isMalformed (mkNodeData NStarted [VWord 2])
        refusal
          isMalformed
          ( mkNodeData
              NArenaEpisode
              [VInt 0, VRef d0, VRef d0, VList [VWord 9], VList [VWord 0], VBool False, VRef d0]
          )
    , testCase "mathematical signed magnitude is exact and canonical" $ do
        forM_ [0, -1, 1, 2 ^ (256 :: Int) - 1, -(2 ^ (256 :: Int) - 1)] $ \n -> do
          value <- mustRight (magnitudeValue n)
          actual <- mustRight (readMagnitude value)
          assertEqual "full exact Integer" n actual
        refusal isNonCanonical (readMagnitude (VList [VWord 1, VBytes BS.empty]))
        refusal isNonCanonical (readMagnitude (VList [VWord 0, VBytes (BS.pack [0, 1])]))
        refusal isMalformed (magnitudeValue (2 ^ (256 :: Int)))
    , testCase "RNG records preserve two exact words but never restore an engine" $ do
        let fields =
              [ VText "stdgen-seedgen-toSeed64-v1"
              , VText "recorded-package-version-only"
              , VWord 2
              , VList [VWord maxBound, VWord 0]
              ]
        node <- mustRight (mkNodeData NGeneratorState fields)
        decoded <- mustRight (decodeNodeData (nodeCanonicalBytes node))
        assertEqual "recorded words/version unchanged" fields (nodeFields decoded)
        refusal
          isMalformed
          ( mkNodeData
              NGeneratorState
              [VText "unknown-engine-representation", VText "recorded", VWord 2, VList [VWord 0, VWord 0]]
          )
        refusal
          isMalformed
          ( mkNodeData
              NGeneratorState
              [VText "stdgen-seedgen-toSeed64-v1", VText "recorded", VWord 3, VList [VWord 0, VWord 0]]
          )
    , testCase "tensor coordinate count partial bytes and empty chunks reject" $ do
        refusal isMalformed (mkNodeData NTensorLeaf [VWord 2, VBytes (Wire.word64Bytes 0)])
        refusal isMalformed (internTensor (BS.singleton 0) emptyNodePool)
        refusal isNonCanonical (mkNodeData NTensorChunk [VWord 0, VBytes BS.empty])
    , testCase "large tensors use deterministic ordered full chunks and replay exactly" $ do
        (boundary, boundaryPool) <- mustRight (internTensor (BS.replicate 1048576 0) emptyNodePool)
        boundaryNode <- lookupRequired boundary boundaryPool
        assertEqual "exact1MiB remains one leaf" NTensorLeaf (nodeKind boundaryNode)
        let bytes = BS.replicate (1048576 + 8) 0
        (root, pool) <- mustRight (internTensor bytes emptyNodePool)
        usage <- mustRight (validateReachableData [root] pool)
        node <- lookupRequired root pool
        assertEqual "large tensor manifest" NTensorManifest (nodeKind node)
        assertEqual
          "unique tensor coordinates"
          (toInteger (BS.length bytes `div` 8))
          (usageF64Coordinates usage)
        forM_ (nodePoolEntries pool) $ \(_, item, encoded) -> do
          decoded <- mustRight (decodeNodeData encoded)
          assertEqual "exact canonical chunks" item decoded
    , testCase "swapped tensor ordinals and short nonfinal chunks reject" $ do
        (first, p1) <- mustRight (add NTensorChunk [VWord 1, VBytes (BS.replicate 1048576 0)] emptyNodePool)
        (lastChunk, p2) <- mustRight (add NTensorChunk [VWord 0, VBytes (BS.replicate 8 0)] p1)
        (root, p3) <-
          mustRight (add NTensorManifest [VWord 131073, VWord 1048584, VList [VRef first, VRef lastChunk]] p2)
        refusal isNonCanonical (validateReachableData [root] p3)
        (short, q1) <- mustRight (add NTensorChunk [VWord 0, VBytes (BS.replicate 8 0)] emptyNodePool)
        (long, q2) <- mustRight (add NTensorChunk [VWord 1, VBytes (BS.replicate 1048576 0)] q1)
        (other, q3) <-
          mustRight (add NTensorManifest [VWord 131073, VWord 1048584, VList [VRef short, VRef long]] q2)
        refusal isNonCanonical (validateReachableData [other] q3)
    , testCase "empty and256-boundary sequences have canonical minimal trees" $ do
        forM_ [0, 1, 256, 257] $ \count -> do
          (root, pool) <-
            mustRight (internSequence (ScalarElement ScalarInt) (replicate count (VInt 7)) emptyNodePool)
          usage <- mustRight (validateReachableData [root] pool)
          assertEqual "complete element count" (toInteger count) (usageSequenceElements usage)
          node <- lookupRequired root pool
          let expectedHeight = if count == 0 then 0 else 1
          case nodeFields node of
            [_, VWord actual, VWord height, _] -> assertEqual "count and height" (fromIntegral count, expectedHeight) (actual, height)
            _ -> assertFailure "manifest fixture fields differ"
    , testCase "shared pages preserve65536 logical elements without graph expansion" $ do
        (root, pool) <-
          mustRight (internSequence (ScalarElement ScalarBits) (replicate 65536 (VBits 0)) emptyNodePool)
        usage <- mustRight (validateReachableData [root] pool)
        assertEqual "root and one shared physical page" 2 (usageNodes usage)
        assertEqual "one logical root count" 65536 (usageSequenceElements usage)
        assertEqual "stored F64 occurrences only once" 256 (usageF64Coordinates usage)
        assertEqual "every repeated page edge plus root" 257 (usageEdges usage)
    , testCase "65537 elements introduce exactly the minimal second index level" $ do
        (root, pool) <-
          mustRight (internSequence (ScalarElement ScalarInt) (replicate 65537 (VInt 0)) emptyNodePool)
        usage <- mustRight (validateReachableData [root] pool)
        assertEqual "two distinct pages two indices one root" 5 (usageNodes usage)
        assertEqual "depth includes body reference" 3 (usageReferenceDepth usage)
        assertEqual "all logical elements retained" 65537 (usageSequenceElements usage)
    , testCase "sequence height count and scalar-reference kind substitutions reject" $ do
        refusal
          isNonCanonical
          ( mkNodeData
              NSequenceManifest
              [elementKindValue (ScalarElement ScalarInt), VWord 1, VWord 2, VList [VRef d0]]
          )
        refusal
          isMalformed
          (mkNodeData NScalarPage [elementKindValue (AliasElement TensorAlias), VWord 1, VList [VRef d0]])
        refusal
          isMalformed
          (mkNodeData NReferencePage [elementKindValue (ScalarElement ScalarInt), VWord 1, VList [VRef d0]])
        (page, p1) <-
          mustRight
            ( add
                NScalarPage
                [elementKindValue (ScalarElement ScalarBits), VWord 1, VList [VBits 0]]
                emptyNodePool
            )
        (root, p2) <-
          mustRight
            ( add
                NSequenceManifest
                [elementKindValue (ScalarElement ScalarInt), VWord 1, VWord 1, VList [VRef page]]
                p1
            )
        refusal isNonCanonical (validateReachableData [root] p2)
    , testCase "nested sequence and unused alias element kinds cannot extend the schema" $ do
        refusal isMalformed (internSequence (RefElement NSequenceManifest) [] emptyNodePool)
        refusal
          isMalformed
          ( mkNodeData
              NSequenceManifest
              [elementKindValue (AliasElement SnapshotAlias), VWord 0, VWord 0, VList []]
          )
    , testCase "a short nonfinal sequence page cannot hide an equal total count" $ do
        (short, p1) <-
          mustRight
            (add NScalarPage [elementKindValue (ScalarElement ScalarInt), VWord 1, VList [VInt 0]] emptyNodePool)
        (long, p2) <-
          mustRight
            ( add
                NScalarPage
                [elementKindValue (ScalarElement ScalarInt), VWord 256, VList (replicate 256 (VInt 0))]
                p1
            )
        (root, p3) <-
          mustRight
            ( add
                NSequenceManifest
                [elementKindValue (ScalarElement ScalarInt), VWord 257, VWord 1, VList [VRef short, VRef long]]
                p2
            )
        refusal isNonCanonical (validateReachableData [root] p3)
    , testCase "over-limit sequence count refuses a tiny manifest before expansion" $
        refusal
          (isResource PerSequenceElements)
          ( mkNodeData
              NSequenceManifest
              [elementKindValue (ScalarElement ScalarInt), VWord 4000001, VWord 2, VList []]
          )
    , testCase "five small shared DAG roots cannot hide twenty million sequence elements" $ do
        (roots, pool) <- mustRight compactManySequences
        four <- mustRight (reachableNodePool (take 4 roots) pool)
        usage <- mustRight (validateReachableData (take 4 roots) four)
        assertEqual "four complete distinct manifests" 16000000 (usageSequenceElements usage)
        assertBool "memoized pool never expands sixteen million scalars" (usageNodes usage < 30)
        refusal (isResource AggregateSequenceElements) (validateReachableData roots pool)
    , testCase "exact byte interning shares repeated tensors and counts every edge" $ do
        (tensor, p1) <- mustRight (internTensor (Wire.word64Bytes 0) emptyNodePool)
        (same, p2) <- mustRight (internTensor (Wire.word64Bytes 0) p1)
        assertEqual "same exact bytes same digest" tensor same
        (params, p3) <-
          mustRight
            ( add
                NParams
                [VList [VInt (-1), VInt 0, VInt 0], VRef tensor, VRef tensor, VRef tensor, VRef tensor]
                p2
            )
        usage <- mustRight (validateReachableData [params] p3)
        assertEqual
          "malformed ordinary dimension preserved"
          [VList [VInt (-1), VInt 0, VInt 0], VRef tensor, VRef tensor, VRef tensor, VRef tensor]
          . nodeFields
          =<< lookupRequired params p3
        assertEqual "unique nodes" 2 (usageNodes usage)
        assertEqual "one stored coordinate" 1 (usageF64Coordinates usage)
        assertEqual "four stored refs plus root" 5 (usageEdges usage)
    , testCase "missing references and wrong target kinds fail on the actual graph path" $ do
        (params, p1) <-
          mustRight
            (add NParams [VList [VInt 1, VInt 1, VInt 1], VRef d0, VRef d0, VRef d0, VRef d0] emptyNodePool)
        refusal isMissing (validateReachableData [params] p1)
        (other, q1) <- mustRight (add NStarted [VWord 0] emptyNodePool)
        (bad, q2) <-
          mustRight
            (add NParams [VList [VInt 1, VInt 1, VInt 1], VRef other, VRef other, VRef other, VRef other] q1)
        refusal isWrongType (validateReachableData [bad] q2)
    , testCase "pruned validation leaves sibling roots intact but exact phases reject extras" $ do
        (root, p1) <- mustRight (internTensor BS.empty emptyNodePool)
        (_, p2) <- mustRight (add NStarted [VWord 0] p1)
        refusal isUnreachable (validateReachableData [root] p2)
        pruned <- mustRight (reachableNodePool [root] p2)
        _ <- mustRight (validateReachableData [root] pruned)
        assertEqual "full supplied pool remains2" 2 (length (nodePoolEntries p2))
        assertEqual "ordinary pruned view1" 1 (length (nodePoolEntries pruned))
    , testCase "shared topology checker rejects genuine data cycles without forged SHA" $ do
        let a = hashBytes "topology-a"; b = hashBytes "topology-b"
        refusal isCycle (validateDigestTopology (Map.fromList [(a, [b]), (b, [a])]) [a])
        depth <- mustRight (validateDigestTopology (Map.fromList [(a, [b, b]), (b, [])]) [a])
        assertEqual "shared ordinary topology depth" 2 depth
    , testCase "actual topology walker accepts depth14 and refuses depth15" $ do
        let nodes = [hashBytes (BS.pack [n]) | n <- [0 .. 14]]
            chain keys = Map.fromList (zip keys (fmap pure (drop 1 keys) <> [[]]))
        depth <- mustRight (validateDigestTopology (chain (take 14 nodes)) (take 1 nodes))
        assertEqual "exact maximum" 14 depth
        refusal (isResource ReferenceDepth) (validateDigestTopology (chain nodes) (take 1 nodes))
    , testCase "all cumulative budget predicates refuse their own exact overrun" $ do
        let cases =
              [ (PoolNodes, \n -> emptyUsage {usageNodes = n})
              , (TypedReferenceEdges, \n -> emptyUsage {usageEdges = n})
              , (AggregateSequenceElements, \n -> emptyUsage {usageSequenceElements = n})
              , (AggregateF64Coordinates, \n -> emptyUsage {usageF64Coordinates = n})
              , (ReferenceDepth, \n -> emptyUsage {usageReferenceDepth = n})
              , (WholePayloadBytes, \n -> emptyUsage {usageEncodedBytes = n})
              ]
        forM_ cases $ \(resource, update) -> do
          _ <- mustRight (checkGraphUsage (update (nativePhaseLimit resource)))
          refusal (isResource resource) (checkGraphUsage (update (nativePhaseLimit resource + 1)))
    , testCase "pool key corruption is rejected against actual canonical node bytes" $ do
        phase <- mustRight startedFixture
        let entries = nodePoolEntries (phaseDataPool phase)
            changed =
              [ (digest, if digest == phaseDataRoot phase then BS.pack [0x82, 0x18, 0x32, 1] else bytes)
              | (digest, _, bytes) <- entries
              ]
        refusal isHashMismatch (decodePhaseData (rawEnvelope phase 0 canonicalCoverage changed))
    , testCase "duplicate and descending pool keys reject even identical node bytes" $ do
        phase <- mustRight startedFixture
        let entries = [(digest, bytes) | (digest, _, bytes) <- nodePoolEntries (phaseDataPool phase)]
        refusal isNonCanonical (decodePhaseData (rawEnvelope phase 0 canonicalCoverage (reverse entries)))
        case entries of
          first : rest ->
            refusal
              isNonCanonical
              (decodePhaseData (rawEnvelope phase 0 canonicalCoverage (first : first : rest)))
          [] -> assertFailure "fixture pool empty"
    , testCase "missing or foreign pool members cannot enter a refined phase" $ do
        phase <- mustRight startedFixture
        let entries = [(digest, bytes) | (digest, _, bytes) <- nodePoolEntries (phaseDataPool phase)]
        refusal
          isMissing
          ( decodePhaseData
              (rawEnvelope phase 0 canonicalCoverage (filter ((/= phaseDataRoot phase) . fst) entries))
          )
        (extra, pool) <- mustRight (add NStarted [VWord 1] (phaseDataPool phase))
        assertBool "distinct foreign DATA" (extra /= phaseDataRoot phase)
        refusal
          isUnreachable
          (mkPhaseData StartedPhase (phaseDataContext phase) Nothing (phaseDataRoot phase) pool)
    , testCase "unknown phase authority coverage and wrong body kind fail closed" $ do
        phase <- mustRight startedFixture
        let entries = [(digest, bytes) | (digest, _, bytes) <- nodePoolEntries (phaseDataPool phase)]
        refusal isMalformed (decodePhaseData (rawEnvelope phase 7 canonicalCoverage entries))
        refusal
          isMalformed
          (decodePhaseData (rawEnvelope phase 0 (VList [VWord 0, VWord 0, VWord 0, VWord 1]) entries))
        refusal
          isWrongType
          ( mkPhaseData
              RawReturnPhase
              (phaseDataContext phase)
              Nothing
              (phaseDataRoot phase)
              (phaseDataPool phase)
          )
    , testCase "nested ForwardOutcome Right reference is counted and cannot go missing" $ do
        (params, input, pool) <- mustRight baseParams
        (root, p1) <-
          mustRight
            (add NReturnForward [VInt 0, zeroMagnitude, VRef params, VRef input, VList [VWord 0, VRef d0]] pool)
        refusal isMissing (validateReachableData [root] p1)
        (output, p2) <- mustRight (internTensor (Wire.word64Bytes 1) pool)
        (actual, p3) <-
          mustRight
            (add NReturnForward [VInt 0, zeroMagnitude, VRef params, VRef input, VList [VWord 0, VRef output]] p2)
        usage <- mustRight (validateReachableData [actual] p3)
        assertEqual "four parameter refs and three forward refs plus root" 8 (usageEdges usage)
    , testCase "raw zero counters and nonfinite parameter bits remain ordinary uncensored DATA" $ do
        (root, pool) <- mustRight (rawHerFixture False)
        _ <- mustRight (validateReachableData [root] pool)
        node <- lookupRequired root pool
        decoded <- mustRight (decodeNodeData (nodeCanonicalBytes node))
        assertEqual "full raw fields unchanged without eligibility" (nodeFields node) (nodeFields decoded)
    , testCase "RawNeural config and statistic family substitutions reject" $ do
        (root, pool) <- mustRight (rawHerFixture True)
        refusal isWrongType (validateReachableData [root] pool)
        (good, q1) <- mustRight (rawHerFixture False)
        goodNode <- lookupRequired good q1
        case nodeFields goodNode of
          _ : rest -> do
            (wrong, q2) <- mustRight (add NRawNeural (VWord 0 : rest) q1)
            refusal isWrongType (reachableNodePool [wrong] q2)
          [] -> assertFailure "raw fixture empty"
    , testCase "failure payload coverage cannot advertise omitted data as present" $ do
        let absent = VList [VWord 1]
            coverage = VList (VList [VWord 0] : replicate 5 absent)
            fields =
              [ VWord 5
              , VList [VWord 1, VWord 6]
              , VList [VWord 1, VList [VWord 0]]
              , VList [VWord 2]
              , VWord 0
              , VList [VWord 0]
              , coverage
              , VNull
              , VNull
              , VNull
              , VNull
              , VNull
              , VNull
              ]
        refusal isMalformed (mkNodeData NSafeFailure fields)
    , testCase "complete duplicated capture-status strings remain independently lossless" $ do
        let statusA = VList [VWord 1, VText (Text.replicate 1024 "a"), VText (Text.replicate 1024 "b")]
            statusB = VList [VWord 1, VText (Text.replicate 1024 "c"), VText (Text.replicate 1024 "d")]
            fields =
              [ VWord 5
              , VList [VWord 1, VWord 6]
              , VList [VWord 1, statusA]
              , VList [VWord 2]
              , VWord 0
              , statusB
              , VList (replicate 6 (VList [VWord 1]))
              , VNull
              , VNull
              , VNull
              , VNull
              , VNull
              , VNull
              ]
        node <- mustRight (mkNodeData NSafeFailure fields)
        assertBool
          "all four paths need more than the old4096 reservation"
          (BS.length (nodeCanonicalBytes node) > 4096)
        assertBool
          "full scalar/reference header fits8192"
          (toInteger (BS.length (nodeCanonicalBytes node)) <= nativePhaseSafeFailureHeaderBytes)
        decoded <- mustRight (decodeNodeData (nodeCanonicalBytes node))
        assertEqual "all four full1024-byte strings retained" fields (nodeFields decoded)
    , testCase "the entire unique producer closure must fit16KiB" $ do
        zero <- mustRight (magnitudeValue 0)
        let producer suffix =
              [VText (Text.replicate 4095 "p" <> suffix), VDigest d0, VWord 1, zero, zero]
                <> replicate 7 (VText (Text.replicate 256 "o"))
                <> [VList [VText (Text.replicate 4096 "s"), VList [VWord 1, VDigest d0]]]
        (before, p1) <- mustRight (add NRecordedProducer (producer "a") emptyNodePool)
        (after, p2) <- mustRight (add NRecordedProducer (producer "b") p1)
        (bundle, p3) <- mustRight (add NProducerContextBundle [VRef before, VRef after, VNull] p2)
        refusal (isResource ProducerBundleBytes) (producerClosureBytes bundle p3)
    , testCase "all five snapshot routes enforce8MiB frames independently of whole size" $ do
        (frame, pool) <- mustRight (internTensor (BS.replicate (8388608 + 8) 0) emptyNodePool)
        (roots, full) <- mustRight (snapshotFixtures frame pool)
        assertEqual "all five contextual frame routes" 5 (length roots)
        forM_ roots $ \root -> refusal (isResource FrameBytes) (reachableNodePool [root] full)
    ]

lookupRequired :: Digest -> NodePool -> IO NodeData
lookupRequired digest pool = case lookupNode digest pool of
  Just node -> pure node
  Nothing -> assertFailure ("fixture node missing: " <> show digest) >> fail "unreachable assertion failure"

mustRight :: Either CodecError a -> IO a
mustRight value = case value of
  Right actual -> pure actual
  Left errorValue -> assertFailure (show errorValue) >> fail "unreachable assertion failure"

refusal :: (CodecError -> Bool) -> Either CodecError a -> Assertion
refusal predicate value = case value of
  Left errorValue -> assertBool ("wrong refusal reason: " <> show errorValue) (predicate errorValue)
  Right _ -> assertFailure "unexpected accepted ordinary DATA"

isMalformed
  , isNonCanonical
  , isMissing
  , isWrongType
  , isUnreachable
  , isCycle
  , isHashMismatch
  , isUnexpectedEnd
    :: CodecError -> Bool
isMalformed (Malformed _) = True
isMalformed _ = False
isNonCanonical (NonCanonical _) = True
isNonCanonical _ = False
isMissing (MissingReference _) = True
isMissing _ = False
isWrongType (WrongReferenceType _ _) = True
isWrongType _ = False
isUnreachable (UnreachablePoolMember _) = True
isUnreachable _ = False
isCycle (ReferenceCycle _) = True
isCycle _ = False
isHashMismatch (HashMismatch _) = True
isHashMismatch _ = False
isUnexpectedEnd (UnexpectedEnd _) = True
isUnexpectedEnd _ = False

isResource :: Resource -> CodecError -> Bool
isResource expected (ResourceExceeded actual _ _) = actual == expected
isResource _ _ = False

d0 :: Digest
d0 = hashBytes "ordinary-protocol-fixture-not-source-or-authority"

zeroMagnitude :: NodeValue
zeroMagnitude = VList [VWord 0, VBytes BS.empty]

add :: NodeKind -> [NodeValue] -> NodePool -> Either CodecError (Digest, NodePool)
add kind fields pool = mkNodeData kind fields >>= (`internNode` pool)

contextFixture :: Digest -> Either CodecError ContextData
contextFixture producer =
  mkContextData
    [ VText "ordinary-fixture"
    , VWord 0
    , VText "recorded-parent"
    , VText "recorded-cohort"
    , VText "recorded-child"
    , VList (replicate 6 (VDigest d0) <> [VNull])
    , VDigest d0
    , VList [VWord 0]
    , VWord 0
    , VWord 42
    , VList [VWord 1, VWord 1, VWord 42]
    , VDigest d0
    , VDigest d0
    , VList [VWord 0, VDigest d0]
    , VList [VNull, VNull]
    , VRef producer
    ]

startedFixture :: Either CodecError PhaseData
startedFixture = do
  (producer, p1) <- add NProducerContextBundle [VNull, VNull, VNull] emptyNodePool
  (body, p2) <- add NStarted [VWord 0] p1
  context <- contextFixture producer
  mkPhaseData StartedPhase context Nothing body p2

canonicalCoverage :: NodeValue
canonicalCoverage = VList [VWord 0, VWord 0, VWord 0, VWord 0]

-- Deliberately unvalidated wire fixture constructor, not a result/capability
-- factory. Callers alter ordering/keys/tag/coverage to attack the real parser.
rawEnvelope :: PhaseData -> Word64 -> NodeValue -> [(Digest, ByteString)] -> ByteString
rawEnvelope phase tag coverage entries =
  Wire.encodeStrict
    ( CBOR.encodeListLen 8
        <> CBOR.encodeString "jitml-native-rl-phase-data"
        <> CBOR.encodeWord64 1
        <> CBOR.encodeWord64 tag
        <> Wire.rawValueEncoding (VList (contextFields (phaseDataContext phase)))
        <> Wire.rawValueEncoding coverage
        <> CBOR.encodeNull
        <> CBOR.encodeBytes (digestBytes (phaseDataRoot phase))
        <> CBOR.encodeListLen (fromIntegral (length entries))
        <> foldMap
          ( \(digest, bytes) -> CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes
          )
          entries
    )

baseParams :: Either CodecError (Digest, Digest, NodePool)
baseParams = do
  (tensor, p1) <- internTensor (Wire.word64Bytes 0x7ff8000000001234) emptyNodePool
  (params, p2) <-
    add NParams [VList [VInt 0, VInt 0, VInt 0], VRef tensor, VRef tensor, VRef tensor, VRef tensor] p1
  pure (params, tensor, p2)

rawHerFixture :: Bool -> Either CodecError (Digest, NodePool)
rawHerFixture wrongStat = do
  (params, _, p1) <- baseParams
  (config, p2) <- add NHerConfig herConfigFields p1
  (statistics, p3) <-
    if wrongStat
      then do
        (stat, q1) <- add NPpoStat [VInt 0, VBits 0, VBits 0, VBits 0, VInt 0] p2
        internSequence (AliasElement NeuralStatAlias) [VRef stat] q1
      else internSequence (AliasElement NeuralStatAlias) [] p2
  add
    NRawNeural
    [ VWord 4
    , VText "raw-unbound-public-transport-fixture"
    , VRef config
    , VRef params
    , VRef config
    , VRef params
    , VRef params
    , VRef statistics
    , VWord 0
    , VWord 0
    ]
    p3

-- One fixed wire attack: each of five distinct roots describes4,000,000
-- scalars via61 full65536 indices plus one2304 index. The first page differs
-- per root; every other physical node is shared. No logical sequence is built.
compactManySequences :: Either CodecError ([Digest], NodePool)
compactManySequences = do
  let kind = elementKindValue (ScalarElement ScalarInt)
  (page, p1) <- add NScalarPage [kind, VWord 256, VList (replicate 256 (VInt 0))] emptyNodePool
  (full, p2) <- add NSequenceIndex [kind, VWord 1, VWord 65536, VList (replicate 256 (VRef page))] p1
  (lastIndex, p3) <-
    add NSequenceIndex [kind, VWord 1, VWord 2304, VList (replicate 9 (VRef page))] p2
  makeRoots kind page full lastIndex [1 .. 5] [] p3
 where
  makeRoots _ _ _ _ [] roots pool = Right (reverse roots, pool)
  makeRoots kind page full lastIndex (n : rest) roots pool = do
    (special, p1) <- add NScalarPage [kind, VWord 256, VList (replicate 255 (VInt 0) <> [VInt n])] pool
    (first, p2) <-
      add NSequenceIndex [kind, VWord 1, VWord 65536, VList (VRef special : replicate 255 (VRef page))] p1
    (root, p3) <-
      add
        NSequenceManifest
        [kind, VWord 4000000, VWord 2, VList ([VRef first] <> replicate 60 (VRef full) <> [VRef lastIndex])]
        p2
    makeRoots kind page full lastIndex rest (root : roots) p3

herConfigFields :: [NodeValue]
herConfigFields = replicate 6 (VInt 0) <> [VBits 0, VBits 0, VInt 0, VBits 0, VBool False, VWord 0, VInt 0, VInt 0]

-- Structurally valid zero-valued protocol configurations, never public trainer
-- plans or numerical recipes. The target controls are contextual frame caps.
snapshotFixtures :: Digest -> NodePool -> Either CodecError ([Digest], NodePool)
snapshotFixtures frame pool = do
  (tensor, p1) <- internTensor BS.empty pool
  (params, p2) <-
    add NParams [VList [VInt 0, VInt 0, VInt 0], VRef tensor, VRef tensor, VRef tensor, VRef tensor] p1
  (gradient, p3) <- add NGradient (replicate 4 (VRef tensor)) p2
  (adam, p4) <- add NAdam [VInt 0, VRef gradient, VRef gradient] p3
  (generator, p5) <-
    add
      NGeneratorState
      [ VText "stdgen-seedgen-toSeed64-v1"
      , VText "unit-DATA-not-restored"
      , VWord 2
      , VList [VWord 0, VWord 0]
      ]
      p4
  (recent, p6) <- internSequence (ScalarElement ScalarBits) [] p5
  (counts, p7) <- internSequence (ScalarElement ScalarCountTriple) [] p6
  (slots, p8) <- internSequence (ScalarElement ScalarSlotSummary) [] p7
  (frames, p9) <- internSequence (AliasElement TensorAlias) [VRef frame] p8
  (discrete, p10) <- internSequence (RefElement NDiscreteReplay) [] p9
  (continuous, p11) <- internSequence (RefElement NContinuousReplay) [] p10
  (ppoStats, p12) <- internSequence (RefElement NPpoStat) [] p11
  (dqnStats, p13) <- internSequence (RefElement NDqnStat) [] p12
  (qrStats, p14) <- internSequence (RefElement NQrStat) [] p13
  (contStats, p15) <- internSequence (RefElement NContinuousStat) [] p14
  (ppoCfg, p16) <-
    add
      NPpoConfig
      ( replicate 7 (VInt 0)
          <> replicate 6 (VBits 0)
          <> replicate 3 (VInt 0)
          <> [VBits 0, VWord 0, VBits 0, VInt 0, VBits 0, VInt 0, VBits 0, VInt 0, VBits 0, VInt 0]
      )
      p15
  (dqnCfg, p17) <-
    add
      NDqnConfig
      ( replicate 5 (VInt 0)
          <> [VBits 0, VBits 0, VInt 0, VBits 0, VBits 0]
          <> replicate 7 (VInt 0)
          <> [VBool False]
      )
      p16
  (qrCfg, p18) <-
    add
      NQrConfig
      (replicate 6 (VInt 0) <> replicate 3 (VBits 0) <> [VInt 0, VBits 0, VBits 0] <> replicate 7 (VInt 0))
      p17
  (contCfg, p19) <-
    add
      NContinuousConfig
      ( [VWord 0]
          <> replicate 5 (VInt 0)
          <> replicate 4 (VBits 0)
          <> [VInt 0]
          <> replicate 7 (VBits 0)
          <> replicate 5 (VInt 0)
          <> [VBits 0, VBits 0, VInt 0, VText "protocol-fixture", VBits 0]
      )
      p18
  (arsCfg, p20) <-
    add NArsConfig (replicate 4 (VInt 0) <> [VBits 0, VBits 0] <> replicate 3 (VInt 0)) p19
  (ppo, p21) <-
    add
      NPpoSnapshot
      [ VRef ppoCfg
      , VRef params
      , VRef adam
      , VRef generator
      , VList [VWord 0]
      , VRef slots
      , VRef frames
      , VRef counts
      , VRef ppoStats
      , VInt 0
      , zeroMagnitude
      , VText "protocol-fixture"
      , VInt 0
      , VInt 0
      ]
      p20
  let discreteSnapshot cfg stats =
        [ VRef cfg
        , VRef params
        , VRef params
        , VRef params
        , VRef adam
        , VRef generator
        , VRef discrete
        , VInt 0
        , VList [VWord 0]
        , VInt 0
        , VBits 0
        , VRef recent
        , VRef stats
        , VText "protocol-fixture"
        , VInt 0
        , VInt 0
        , VRef frame
        ]
  (dqn, p22) <- add NDqnSnapshot (discreteSnapshot dqnCfg dqnStats) p21
  (qr, p23) <- add NQrSnapshot (discreteSnapshot qrCfg qrStats) p22
  (cont, p24) <-
    add
      NContinuousSnapshot
      ( [VWord 0, VRef contCfg]
          <> replicate 4 (VRef params)
          <> replicate 3 VNull
          <> [VBits 0]
          <> replicate 3 (VRef adam)
          <> [ VNull
             , VRef generator
             , VRef continuous
             , VInt 0
             , VList [VWord 0]
             , VInt 0
             , VBits 0
             , VRef recent
             , VRef contStats
             , VText "protocol-fixture"
             , VRef frame
             , VRef counts
             , VInt 0
             ]
      )
      p23
  (ars, p25) <- add NArsSnapshot [VRef arsCfg, VRef tensor, VRef generator, VRef frame] p24
  pure ([ppo, dqn, qr, cont, ars], p25)
