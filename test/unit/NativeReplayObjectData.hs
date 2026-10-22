{-# LANGUAGE OverloadedStrings #-}

-- Ordinary replay-object DATA controls. The sole simulator fixture uses the
-- actual fixed evaluator and source projector; no trainer or capability runs.
module NativeReplayObjectData (nativeReplayObjectDataTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (newIORef, readIORef)
import Data.List (sort)
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativePhase.Builder qualified as Builder
import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Project
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.NativeReturnEvaluation qualified as Evaluation
import JitML.RL.NativeReturnReferences qualified as Ref

data Fixture = Fixture
  { fixtureEvaluation :: !Evaluation.RawNativeReturnEvaluation
  , fixtureRoot :: !Digest
  , fixturePool :: !Graph.NodePool
  , fixtureEntries :: ![(Digest, ByteString)]
  , fixtureNegativeRoot :: !Digest
  , fixtureNegativePool :: !Graph.NodePool
  , fixtureNegativeEntries :: ![(Digest, ByteString)]
  , fixtureRejectedRoot :: !Digest
  , fixtureRejectedEntries :: ![(Digest, ByteString)]
  }

nativeReplayObjectDataTests :: TestTree
nativeReplayObjectDataTests = withResource acquire (const (pure ())) $ \get ->
  testGroup
    "native evaluation replay object DATA"
    [ testCase "actual fixed evaluator projection roundtrips a closed replay object" $ do
        actual <- get
        object <- positive actual Replay.InitialModelReplay 0
        Replay.decodeNativeReplayObjectData (Replay.nativeReplayObjectBytes object) @?= Right object
        Replay.nativeReplayObjectRoot object @?= fixtureRoot actual
        Replay.nativeReplayObjectEntries object @?= fixtureEntries actual
    , testCase "source fixture retains every actual keyed case and measured evaluation transition" $ do
        actual <- fixtureEvaluation <$> get
        Evaluation.nativeEvaluationStatus actual @?= Evaluation.NativeEvaluationComplete
        map Ref.nativeReturnEpisodeId (Evaluation.nativeEvaluationEpisodes actual) @?= [0 .. 19]
        let work = sum (map (toInteger . Ref.nativeReturnEpisodeSteps) (Evaluation.nativeEvaluationEpisodes actual))
        assertBool "actual simulator work is nonempty" (work > 0)
        Evaluation.nativeEvaluationWork actual @?= Evaluation.NativeCompleteWork work
        Evaluation.nativeEvaluationForwards actual @?= []
    , testCase "all three closed stages retain their own exact stage at index zero" $ do
        actual <- get
        mapM_
          ( \stage -> do
              object <- positive actual stage 0
              decoded <- right (Replay.decodeNativeReplayObjectData (Replay.nativeReplayObjectBytes object))
              Replay.nativeReplayObjectStage decoded @?= stage
          )
          [Replay.InitialModelReplay, Replay.FinalModelReplay, Replay.StoredFinalModelReplay]
    , testCase "initial and final DATA retain all five original indices without executing children" $ do
        actual <- get
        mapM_
          ( \(stage, index) -> do
              object <- positive actual stage index
              Replay.nativeReplayObjectIndex object @?= index
              Replay.decodeNativeReplayObjectData (Replay.nativeReplayObjectBytes object) @?= Right object
          )
          [(stage, index) | stage <- [Replay.InitialModelReplay, Replay.FinalModelReplay], index <- [0 .. 4]]
    , testCase "allocation and attempt digests are distinct exact DATA fields without authentication" $ do
        actual <- get
        let allocation = hashBytes "ordinary allocation"
            attempt = hashBytes "ordinary attempt"
        assertBool "independent byte labels differ" (allocation /= attempt)
        object <-
          right
            ( Replay.refineNativeReplayObjectData
                Replay.FinalModelReplay
                4
                allocation
                attempt
                (fixtureRoot actual)
                (fixtureEntries actual)
            )
        Replay.nativeReplayObjectAllocation object @?= allocation
        Replay.nativeReplayObjectAttempt object @?= attempt
        Replay.nativeReplayObjectRoot object @?= fixtureRoot actual
    , testCase "a genuine rejected evaluator observation remains serializable ordinary DATA" $ do
        actual <- get
        object <-
          right
            ( Replay.refineNativeReplayObjectData
                Replay.InitialModelReplay
                0
                allocationDigest
                attemptDigest
                (fixtureRejectedRoot actual)
                (fixtureRejectedEntries actual)
            )
        Replay.decodeNativeReplayObjectData (Replay.nativeReplayObjectBytes object) @?= Right object
        assertBool
          "rejected and complete source observations differ"
          (fixtureRejectedRoot actual /= fixtureRoot actual)
    , testCase "runtime signed zero remains numeric zero with distinct retained Float64 bits" $ do
        actual <- get
        positiveBits <- thetaBytes (fixtureRoot actual) (fixturePool actual)
        negativeBits <- thetaBytes (fixtureNegativeRoot actual) (fixtureNegativePool actual)
        positiveBits @?= BS.replicate 64 0
        negativeBits @?= Wire.word64Bytes 0x8000000000000000 <> BS.replicate 56 0
        assertBool
          "bit-distinct parameters bind different actual evaluation nodes"
          (fixtureNegativeRoot actual /= fixtureRoot actual)
        object <-
          right
            ( Replay.refineNativeReplayObjectData
                Replay.FinalModelReplay
                0
                allocationDigest
                attemptDigest
                (fixtureNegativeRoot actual)
                (fixtureNegativeEntries actual)
            )
        decoded <- right (Replay.decodeNativeReplayObjectData (Replay.nativeReplayObjectBytes object))
        Replay.nativeReplayObjectEntries decoded @?= fixtureNegativeEntries actual
    , testCase "source-projected pool is unique sorted hash-bound and exactly root reachable" $ do
        actual <- get
        let entries = fixtureEntries actual
            digests = map fst entries
        assertBool "real projection owns multiple graph nodes" (length entries > 2)
        digests @?= sort digests
        mapM_ (\(digest, bytes) -> hashBytes bytes @?= digest) entries
        selected <- right (Graph.reachableNodePool [fixtureRoot actual] (fixturePool actual))
        poolEntries selected @?= entries
    , testCase "out-of-range child index refuses before demanding supplied entries" $
        malformed
          "replay object child index is outside the original five"
          ( Replay.refineNativeReplayObjectData
              Replay.InitialModelReplay
              5
              allocationDigest
              attemptDigest
              allocationDigest
              (error "invalid index must not inspect the entry spine")
          )
    , testCase "stored final index refuses before demanding supplied entries" $
        malformed
          "stored final replay object must describe serving index zero"
          ( Replay.refineNativeReplayObjectData
              Replay.StoredFinalModelReplay
              1
              allocationDigest
              attemptDigest
              allocationDigest
              (error "invalid stored index must not inspect the entry spine")
          )
    , testCase "unbounded supplied entry spine refuses at the node cap before decoding elements" $
        case Replay.refineNativeReplayObjectData
          Replay.InitialModelReplay
          0
          allocationDigest
          attemptDigest
          allocationDigest
          (repeat (error "bounded spine must precede decoding any entry")) of
          Left (ResourceExceeded PoolNodes cap count) -> do
            cap @?= nativePhaseLimit PoolNodes
            count @?= cap + 1
          other -> unexpected "node cap refusal" other
    , testCase "shared supplied buffers exceed exact envelope budget before any node decode" $ do
        let bytes = BS.replicate 1048576 0xff
            entries = replicate 257 (allocationDigest, bytes)
        -- The list shares one 1MiB malformed buffer. No 257MiB output is built.
        case Replay.refineNativeReplayObjectData
          Replay.InitialModelReplay
          0
          allocationDigest
          attemptDigest
          allocationDigest
          entries of
          Left (ResourceExceeded WholePayloadBytes cap count) -> do
            cap @?= nativePhaseLimit WholePayloadBytes
            assertBool "exact cumulative framing crosses the whole-buffer bound" (count > cap)
          other -> unexpected "pre-encoding cumulative byte refusal" other
    , testCase "reversed complete pool refuses noncanonical node ordering" $ do
        actual <- get
        noncanonicalPool actual (reverse (fixtureEntries actual))
    , testCase "duplicate reachable entry refuses instead of silently deduplicating" $ do
        actual <- get
        case fixtureEntries actual of
          [] -> assertFailure "actual projection unexpectedly empty"
          first : _ -> noncanonicalPool actual (first : fixtureEntries actual)
    , testCase "an extra valid tensor node refuses as unreachable rather than disappearing" $ do
        actual <- get
        (extra, pool) <-
          right (Builder.internTensor (Wire.word64Bytes 0x7ff8000000000042) (fixturePool actual))
        assertBool
          "new tensor is outside original closure"
          (extra `notElem` map fst (fixtureEntries actual))
        noncanonicalPool actual (poolEntries pool)
    , testCase "absent root refuses before any evaluation-kind assumption" $ do
        actual <- get
        missing
          (fixtureRoot actual)
          ( Replay.refineNativeReplayObjectData
              Replay.InitialModelReplay
              0
              allocationDigest
              attemptDigest
              (fixtureRoot actual)
              []
          )
    , testCase "omitting an actual referenced child refuses incomplete graph DATA" $ do
        actual <- get
        root <- requiredNode (fixtureRoot actual) (fixturePool actual)
        references <- right (Schema.nodeReferences root)
        case references of
          [] -> assertFailure "actual evaluation has no referenced data"
          (_, child) : _ ->
            missing
              child
              ( Replay.refineNativeReplayObjectData
                  Replay.InitialModelReplay
                  0
                  allocationDigest
                  attemptDigest
                  (fixtureRoot actual)
                  (filter ((/= child) . fst) (fixtureEntries actual))
              )
    , testCase "entry digest cannot be relabelled independently of its canonical bytes" $ do
        actual <- get
        case fixtureEntries actual of
          [] -> assertFailure "actual projection unexpectedly empty"
          (_, bytes) : rest ->
            malformed
              "replay object node SHA differs from its bytes"
              (refine actual ((hashBytes "wrong digest label", bytes) : rest))
    , testCase "malformed node bytes refuse before graph insertion" $ do
        actual <- get
        case fixtureEntries actual of
          [] -> assertFailure "actual projection unexpectedly empty"
          (digest, _) : rest -> reject (refine actual ((digest, BS.singleton 0xff) : rest))
    , testCase "trailing bytes inside an otherwise canonical node refuse" $ do
        actual <- get
        case fixtureEntries actual of
          [] -> assertFailure "actual projection unexpectedly empty"
          (digest, bytes) : rest -> reject (refine actual ((digest, bytes <> BS.singleton 0) : rest))
    , testCase "a schema-valid tensor root cannot masquerade as evaluation DATA" $ do
        (root, pool) <- right (Builder.internTensor BS.empty Graph.emptyNodePool)
        malformed
          "replay object root is not an evaluation"
          ( Replay.refineNativeReplayObjectData
              Replay.InitialModelReplay
              0
              allocationDigest
              attemptDigest
              root
              (poolEntries pool)
          )
    , testCase "an evaluation root cannot rebind its typed spec edge to a tensor" $ do
        actual <- get
        rootNode <- requiredNode (fixtureRoot actual) (fixturePool actual)
        (tensor, withTensor) <- right (Builder.internTensor BS.empty (fixturePool actual))
        fields <- case Schema.nodeFields rootNode of
          [] -> fail "actual source evaluation fields unexpectedly empty"
          _ : rest -> pure (VRef tensor : rest)
        rebound <- right (Schema.mkNodeData NReturnEvaluation fields)
        (root, pool) <- right (Graph.internNode rebound withTensor)
        case Replay.refineNativeReplayObjectData
          Replay.InitialModelReplay
          0
          allocationDigest
          attemptDigest
          root
          (poolEntries pool) of
          Left (WrongReferenceType digest detail) -> do
            digest @?= tensor
            detail @?= "node target kind differs"
          other -> unexpected "actual typed evaluation edge refusal" other
    , testCase "empty truncated and trailing outer payloads refuse" $ withBytes get $ \bytes ->
        mapM_
          (reject . Replay.decodeNativeReplayObjectData)
          [BS.empty, BS.take 1 bytes, BS.take (BS.length bytes - 1) bytes, bytes <> BS.singleton 0]
    , testCase "wrong outer type arity and indefinite arrays refuse" $ withBytes get $ \bytes ->
        mapM_
          (\first -> reject (Replay.decodeNativeReplayObjectData (BS.cons first (BS.drop 1 bytes))))
          [0x87, 0x89, 0x9f, 0xa0, 0xc0, 0xfb]
    , testCase "nonshortest outer array length refuses equal numeric arity" $ withBytes get $ \bytes ->
        reject (Replay.decodeNativeReplayObjectData (BS.pack [0x98, 8] <> BS.drop 1 bytes))
    , testCase "wrong domain and version refuse before graph materialization" $ do
        actual <- get
        malformed
          "replay object domain differs"
          ( Replay.decodeNativeReplayObjectData
              ( envelope
                  "foreign-domain"
                  1
                  0
                  0
                  allocationDigest
                  attemptDigest
                  (fixtureRoot actual)
                  (fixtureEntries actual)
              )
          )
        malformed
          "replay object version differs"
          ( Replay.decodeNativeReplayObjectData
              (envelope domain 2 0 0 allocationDigest attemptDigest (fixtureRoot actual) (fixtureEntries actual))
          )
    , testCase "unknown stage codes including Word64 maximum refuse the closed enum" $ do
        actual <- get
        mapM_
          ( \code ->
              malformed
                "unknown replay object stage"
                ( Replay.decodeNativeReplayObjectData
                    (envelope domain 1 code 0 allocationDigest attemptDigest (fixtureRoot actual) (fixtureEntries actual))
                )
          )
          [3, maxBound]
    , testCase "wire child index and stored-only-zero rules precede pool parsing" $
        mapM_
          ( \(stage, index) ->
              malformed
                "replay object child index differs"
                ( Replay.decodeNativeReplayObjectData
                    (prefix domain 1 stage index allocationDigest attemptDigest allocationDigest <> BS.singleton 0xff)
                )
          )
          [(0, 5), (1, maxBound), (2, 1), (2, 4)]
    , testCase "all three digest positions reject short and overlong byte strings" $ do
        actual <- get
        mapM_
          ( \position ->
              mapM_
                ( \size ->
                    reject
                      ( Replay.decodeNativeReplayObjectData
                          (rawDigests position (BS.replicate size 0) actual)
                      )
                )
                [31, 33]
          )
          [0, 1, 2]
    , testCase "declared pool above cap refuses before any entry allocation" $
        case Replay.decodeNativeReplayObjectData
          ( prefix domain 1 0 0 allocationDigest attemptDigest allocationDigest
              <> Wire.encodeStrict (CBOR.encodeListLen (fromInteger (nativePhaseLimit PoolNodes + 1)))
          ) of
          Left (ResourceExceeded PoolNodes cap count) -> do
            cap @?= nativePhaseLimit PoolNodes
            count @?= cap + 1
          other -> unexpected "wire pool cap refusal" other
    , testCase "impossible declared pool uses byte floor before decoding its first entry" $ do
        let before =
              prefix domain 1 0 0 allocationDigest attemptDigest allocationDigest
                <> Wire.encodeStrict (CBOR.encodeListLen 2)
        case Replay.decodeNativeReplayObjectData (before <> BS.replicate 71 0xff) of
          Left (UnexpectedEnd offset) -> offset @?= BS.length before
          other -> unexpected "entry byte-floor refusal before the first malformed entry" other
    , testCase "entry array arity and digest width cannot bypass inner parsing" $ do
        actual <- get
        let before =
              prefix domain 1 0 0 allocationDigest attemptDigest (fixtureRoot actual)
                <> Wire.encodeStrict (CBOR.encodeListLen 1)
        mapM_
          (\entry -> reject (Replay.decodeNativeReplayObjectData (before <> entry <> BS.replicate 64 0)))
          [ Wire.encodeStrict (CBOR.encodeListLen 1)
          , Wire.encodeStrict (CBOR.encodeListLen 3)
          , Wire.encodeStrict (CBOR.encodeListLen 2 <> CBOR.encodeBytes (BS.replicate 31 0))
          ]
    , testCase "declared node byte buffer above cap refuses without supplying that buffer" $ do
        nativePhaseLimit WholePayloadBytes @?= 268435456
        -- Definite CBOR byte-string length 0x10000001, with no such buffer.
        case Replay.decodeNativeReplayObjectData
          ( prefix domain 1 0 0 allocationDigest attemptDigest allocationDigest
              <> Wire.encodeStrict
                (CBOR.encodeListLen 1 <> CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes allocationDigest))
              <> BS.pack [0x5a, 0x10, 0, 0, 1]
              <> BS.replicate 40 0
          ) of
          Left (ResourceExceeded WholePayloadBytes cap count) -> do
            cap @?= nativePhaseLimit WholePayloadBytes
            count @?= cap + 1
          other -> unexpected "node byte cap refusal" other
    , testCase "nonshortest scalar encodings refuse without canonicalizing stage or version" $ withBytes get $ \bytes -> do
        let offset = BS.length (Wire.encodeStrict (CBOR.encodeListLen 8 <> CBOR.encodeString domain))
            changeAt at replacement = BS.take at bytes <> replacement <> BS.drop (at + 1) bytes
        reject (Replay.decodeNativeReplayObjectData (changeAt offset (BS.pack [0x18, 1])))
        reject (Replay.decodeNativeReplayObjectData (changeAt (offset + 1) (BS.pack [0x18, 0])))
    , testCase "indefinite map tag and primitive float node buffers never become typed nodes" $ do
        actual <- get
        case fixtureEntries actual of
          [] -> assertFailure "actual projection unexpectedly empty"
          (digest, _) : rest ->
            mapM_
              (\bytes -> reject (refine actual ((digest, bytes) : rest)))
              [ BS.pack [0x9f, 0xff]
              , BS.singleton 0xa0
              , BS.pack [0xc0, 0x00]
              , BS.pack [0xfb, 0, 0, 0, 0, 0, 0, 0, 0]
              ]
    ]

acquire :: IO Fixture
acquire = do
  spec <- right (Ref.canonicalNativeReturnSpec "ARS" "cartpole")
  count <- case Ref.nativeReturnSpecDomain spec of
    Ref.NativeUnmaskedDiscrete value -> pure value
    _ -> fail "actual ARS cartpole source domain differs"
  let config =
        Ars.defaultArsTrainConfig
          { Ars.arsObsSize = Ref.nativeReturnSpecObservationSize spec
          , Ars.arsActionCount = count
          , Ars.arsMaxEpisodeSteps = Ref.nativeReturnSpecHorizon spec
          }
      dimensions = count * Ref.nativeReturnSpecObservationSize spec
      theta = VU.replicate dimensions 0
      actual = Evaluation.evaluateNativeArsReturnPolicy spec config theta
  Evaluation.nativeEvaluationStatus actual @?= Evaluation.NativeEvaluationComplete
  (root, pool) <- project actual
  source <- newIORef (0x8000000000000000 :: Word64)
  word <- readIORef source
  let negative = fromRuntimeBits word
  assertBool "signed-zero mutation is genuinely numeric zero" (negative == 0)
  castDoubleToWord64 negative @?= word
  assertBool "actual parameter tensor is nonempty" (dimensions > 0)
  let negativeTheta = VU.generate dimensions (\index -> if index == 0 then negative else 0)
  assertBool "signed-zero edit preserves numeric parameter values" (negativeTheta == theta)
  VU.map castDoubleToWord64 negativeTheta @?= VU.cons word (VU.replicate (dimensions - 1) 0)
  (negativeRoot, negativePool) <-
    project (Evaluation.evaluateNativeArsReturnPolicy spec config negativeTheta)
  let rejected = Evaluation.evaluateNativeArsReturnPolicy spec config VU.empty
  case Evaluation.nativeEvaluationStatus rejected of
    Evaluation.NativeEvaluationRejected _ -> pure ()
    other -> fail ("actual malformed-policy rejection differs: " <> show other)
  (rejectedRoot, rejectedPool) <- project rejected
  pure
    ( Fixture
        actual
        root
        pool
        (poolEntries pool)
        negativeRoot
        negativePool
        (poolEntries negativePool)
        rejectedRoot
        (poolEntries rejectedPool)
    )
 where
  project actual = Project.projectReturnEvaluationData Graph.emptyNodePool actual >>= right

{-# NOINLINE fromRuntimeBits #-}
fromRuntimeBits :: Word64 -> Double
fromRuntimeBits = castWord64ToDouble

poolEntries :: Graph.NodePool -> [(Digest, ByteString)]
poolEntries = map (\(digest, _, bytes) -> (digest, bytes)) . Graph.nodePoolEntries

thetaBytes :: Digest -> Graph.NodePool -> IO ByteString
thetaBytes root pool = do
  evaluation <- requiredNode root pool
  policyDigest <- case Schema.nodeFields evaluation of
    VRef _ : VRef policy : _ -> pure policy
    _ -> fail "source evaluation fields differ"
  policy <- requiredNode policyDigest pool
  tensorDigest <- case Schema.nodeFields policy of
    [VWord 5, VRef _, VRef tensor] -> pure tensor
    _ -> fail "actual host-linear policy fields differ"
  tensor <- requiredNode tensorDigest pool
  case (Schema.nodeKind tensor, Schema.nodeFields tensor) of
    (NTensorLeaf, [VWord 8, VBytes bytes]) -> pure bytes
    _ -> fail "actual cartpole parameter tensor is not an eight-coordinate leaf"

requiredNode :: Digest -> Graph.NodePool -> IO Schema.NodeData
requiredNode digest pool = case Graph.lookupNode digest pool of
  Nothing -> fail ("missing actual projection node: " <> show digest)
  Just node -> pure node

allocationDigest, attemptDigest :: Digest
allocationDigest = hashBytes "ordinary replay allocation label"
attemptDigest = hashBytes "ordinary replay attempt label"

positive :: Fixture -> Replay.NativeReplayObjectStage -> Word64 -> IO Replay.NativeReplayObjectData
positive actual stage index =
  right
    ( Replay.refineNativeReplayObjectData
        stage
        index
        allocationDigest
        attemptDigest
        (fixtureRoot actual)
        (fixtureEntries actual)
    )

refine :: Fixture -> [(Digest, ByteString)] -> Either CodecError Replay.NativeReplayObjectData
refine actual =
  Replay.refineNativeReplayObjectData
    Replay.InitialModelReplay
    0
    allocationDigest
    attemptDigest
    (fixtureRoot actual)

noncanonicalPool :: Fixture -> [(Digest, ByteString)] -> Assertion
noncanonicalPool actual = malformedAsNoncanonical . refine actual
 where
  malformedAsNoncanonical value = case value of
    Left (NonCanonical "replay object entries are not the complete sorted unique reachable pool") -> pure ()
    other -> unexpected "sorted unique complete pool refusal" other

domain :: Text
domain = "jitml-native-evaluation-replay-object-v1"

-- Independent envelope construction is used only to reach malformed transport
-- guards. Actual node bytes always come from the source projector above.
prefix :: Text -> Word64 -> Word64 -> Word64 -> Digest -> Digest -> Digest -> ByteString
prefix name version stage index allocation attempt root =
  Wire.encodeStrict
    ( CBOR.encodeListLen 8
        <> CBOR.encodeString name
        <> CBOR.encodeWord64 version
        <> CBOR.encodeWord64 stage
        <> CBOR.encodeWord64 index
        <> CBOR.encodeBytes (digestBytes allocation)
        <> CBOR.encodeBytes (digestBytes attempt)
        <> CBOR.encodeBytes (digestBytes root)
    )

envelope
  :: Text
  -> Word64
  -> Word64
  -> Word64
  -> Digest
  -> Digest
  -> Digest
  -> [(Digest, ByteString)]
  -> ByteString
envelope name version stage index allocation attempt root entries =
  prefix name version stage index allocation attempt root
    <> Wire.encodeStrict (CBOR.encodeListLen (fromIntegral (length entries)) <> foldMap entry entries)
 where
  entry (digest, bytes) = CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes

rawDigests :: Int -> ByteString -> Fixture -> ByteString
rawDigests position replacement actual =
  Wire.encodeStrict
    ( CBOR.encodeListLen 8
        <> CBOR.encodeString domain
        <> CBOR.encodeWord64 1
        <> CBOR.encodeWord64 0
        <> CBOR.encodeWord64 0
        <> foldMap
          (\(index, digest) -> CBOR.encodeBytes (if index == position then replacement else digestBytes digest))
          (zip [0 ..] [allocationDigest, attemptDigest, fixtureRoot actual])
        <> CBOR.encodeListLen (fromIntegral (length (fixtureEntries actual)))
        <> foldMap
          ( \(digest, bytes) -> CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes
          )
          (fixtureEntries actual)
    )

withBytes :: IO Fixture -> (ByteString -> Assertion) -> Assertion
withBytes get action = do
  actual <- get
  object <- positive actual Replay.InitialModelReplay 0
  action (Replay.nativeReplayObjectBytes object)

right :: (Show error) => Either error value -> IO value
right value = case value of
  Left failure -> do
    _ <- assertFailure (show failure)
    fail "assertFailure unexpectedly returned"
  Right actual -> pure actual

reject :: (Show value) => Either CodecError value -> Assertion
reject value = case value of
  Left _ -> pure ()
  Right actual -> assertFailure ("expected DATA refusal, received " <> show actual)

malformed :: (Show value) => Text -> Either CodecError value -> Assertion
malformed expected value = case value of
  Left (Malformed actual) -> actual @?= expected
  other -> unexpected "specific malformed DATA refusal" other

missing :: (Show value) => Digest -> Either CodecError value -> Assertion
missing expected value = case value of
  Left (MissingReference actual) -> actual @?= expected
  other -> unexpected "missing actual reference refusal" other

unexpected :: (Show value) => String -> value -> Assertion
unexpected expected actual = assertFailure ("expected " <> expected <> ", received " <> show actual)
