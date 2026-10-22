{-# LANGUAGE OverloadedStrings #-}

-- Protocol DATA positives and actual public pre-execution refusal controls.
-- No fixture is an observed process, reserved slot, acknowledged write, device
-- execution, trained model or producer capability. Positive production runs
-- require actual selected hardware/services and full canonical schedules.
module NativeRlProducer (nativeRlProducerTests) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Exception (AsyncException (ThreadKilled), throw, try)
import Control.Monad.Reader (runReaderT)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (isNothing)
import Data.Word (Word64)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertEqual, assertFailure, testCase)

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Env.Env (Env)
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlProducer qualified as Producer
import JitML.Product.NativeRlProducer.Inventory qualified as Inventory
import JitML.Substrate (Substrate (LinuxCPU))

data Fixture = Fixture
  { allocationFixture :: Inventory.NativeAllocationData
  , batchFixture :: Cohort.NativeRlCohortBatch
  }

nativeRlProducerTests :: TestTree
nativeRlProducerTests = withResource setup (const (pure ())) $ \getFixture ->
  testGroup
    "native producer allocation and pre-execution controls"
    [ testCase "wholefive allocation roundtrips exact contexts and recorded nonce identities" $ do
        fixture <- allocationFixture <$> getFixture
        actual <-
          mustRight (Inventory.decodeNativeAllocationData (Inventory.encodeNativeAllocationData fixture))
        assertEqual
          "exact canonical bytes"
          (Inventory.encodeNativeAllocationData fixture)
          (Inventory.encodeNativeAllocationData actual)
        assertEqual
          "all five nonce records"
          (fmap Inventory.allocationChildNonce (Inventory.allocationChildren fixture))
          (fmap Inventory.allocationChildNonce (Inventory.allocationChildren actual))
        assertEqual
          "every context field"
          ( fmap
              (Schema.contextFields . Inventory.allocationChildContext)
              (Inventory.allocationChildren fixture)
          )
          (fmap (Schema.contextFields . Inventory.allocationChildContext) (Inventory.allocationChildren actual))
    , testCase "ordinary plan labels remain unchanged without becoming opaque plans" $ do
        fixture <- allocationFixture <$> getFixture
        parsed <-
          mustRight (Inventory.decodeNativeAllocationData (Inventory.encodeNativeAllocationData fixture))
        mapM_
          ( \child -> case Schema.contextFields (Inventory.allocationChildContext child) of
              _ : _ : VText parent : _ ->
                assertEqual
                  "not normalized or parsed into an executable plan"
                  "ordinary-unbound-parent-label"
                  parent
              _ -> assertFailure "context field shape changed"
          )
          (Inventory.allocationChildren parsed)
    , testCase "acquisition nonce size and duplicate child identities refuse" $ do
        fixture <- allocationFixture <$> getFixture
        reject isMalformed (rebuild fixture BS.empty (Inventory.allocationChildren fixture))
        case Inventory.allocationChildren fixture of
          first : rest -> reject isMalformed (rebuild fixture (Inventory.allocationChildNonce first) (first : rest))
          [] -> assertFailure "fixture children missing"
    , testCase "four or six children cannot replace the prescribed five" $ do
        fixture <- allocationFixture <$> getFixture
        reject
          isMalformed
          ( rebuild
              fixture
              (Inventory.allocationAcquisitionNonce fixture)
              (take 4 (Inventory.allocationChildren fixture))
          )
        case Inventory.allocationChildren fixture of
          first : rest ->
            reject
              (isResource SequenceFanout)
              (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) (first : first : rest))
          [] -> assertFailure "fixture children missing"
    , testCase "duplicate actual recorded child nonce cannot be hidden by a new context" $ do
        fixture <- allocationFixture <$> getFixture
        case Inventory.allocationChildren fixture of
          first : second : rest -> do
            alteredContext <-
              mustRight
                ( Schema.mkContextData
                    ( replace
                        11
                        (VDigest (Inventory.attemptNonceDigest (Inventory.allocationChildNonce first)))
                        (Schema.contextFields (Inventory.allocationChildContext second))
                    )
                )
            duplicate <-
              mustRight
                (Inventory.mkNativeAllocationChildData (Inventory.allocationChildNonce first) alteredContext)
            reject
              isMalformed
              (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) (first : duplicate : rest))
          _ -> assertFailure "fixture five children missing"
    , testCase "attempt digest must bind that exact recorded nonce" $ do
        fixture <- allocationFixture <$> getFixture
        first <- firstChild fixture
        let nonce = Inventory.allocationChildNonce first
        assertBool "the mutation changes this digest" (d0 /= Inventory.attemptNonceDigest nonce)
        context <-
          mustRight
            ( Schema.mkContextData
                (replace 11 (VDigest d0) (Schema.contextFields (Inventory.allocationChildContext first)))
            )
        reject isMalformed (Inventory.mkNativeAllocationChildData nonce context)
    , testCase "acquisition digest substitution cannot keep the same fixed pool" $ do
        fixture <- allocationFixture <$> getFixture
        changed <- mutateChild fixture 2 12 (VDigest d0)
        reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) changed)
    , testCase "reordered child contexts and skipped ordinal refuse" $ do
        fixture <- allocationFixture <$> getFixture
        reject
          isMalformed
          ( rebuild
              fixture
              (Inventory.allocationAcquisitionNonce fixture)
              (reverse (Inventory.allocationChildren fixture))
          )
        changed <- mutateChild fixture 2 8 (VWord 4)
        reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) changed)
    , testCase "seed gap rejects even when its own budget seed matches" $ do
        fixture <- allocationFixture <$> getFixture
        step1 <- mutateChild fixture 2 9 (VWord 99)
        step2 <- mutateChildren step1 2 10 (VList [VWord 1, VWord 2000, VWord 99])
        reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) step2)
    , testCase "budget seed cannot disagree with the retained actual child seed" $ do
        fixture <- allocationFixture <$> getFixture
        changed <- mutateChild fixture 2 10 (VList [VWord 1, VWord 2000, VWord 9])
        reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) changed)
    , testCase "Word64 seed wrap cannot masquerade as a consecutive five pool" $ do
        fixture <- allocationFixture <$> getFixture
        changed <-
          sequence
            [ do
                let seed = case n of 0 -> maxBound; _ -> fromIntegral (n - 1)
                initial <- modifyChild child 9 (VWord seed)
                modifyChild initial 10 (VList [VWord 1, VWord 2000, VWord seed])
            | (n, child) <- zip [0 :: Int ..] (Inventory.allocationChildren fixture)
            ]
        reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) changed)
    , testCase "foreign row cohort source and whole-budget substitutions refuse" $ do
        fixture <- allocationFixture <$> getFixture
        mapM_
          ( \(position, value) -> do
              changed <- mutateChild fixture 2 position value
              reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) changed)
          )
          [ (0, VText "different-row")
          , (3, VText "different-whole-cohort")
          , (14, VList [VNull, VList [VWord 1, VDigest d0]])
          , (10, VList [VWord 1, VWord 2001, VWord 44])
          ]
    , testCase "each child producer reference must be the claimed shared producer" $ do
        fixture <- allocationFixture <$> getFixture
        changed <- mutateChild fixture 2 15 (VRef d0)
        reject isMalformed (rebuild fixture (Inventory.allocationAcquisitionNonce fixture) changed)
    , testCase "foreign and missing producer pool members refuse" $ do
        fixture <- allocationFixture <$> getFixture
        (_, pool) <- mustRight (add NStarted [VWord 0] (Inventory.allocationProducerPool fixture))
        reject
          isMalformed
          ( Inventory.mkNativeAllocationData
              (Inventory.allocationAcquisitionNonce fixture)
              (Inventory.allocationProducerRoot fixture)
              pool
              (Inventory.allocationChildren fixture)
          )
        reject
          isMissing
          ( Inventory.mkNativeAllocationData
              (Inventory.allocationAcquisitionNonce fixture)
              (Inventory.allocationProducerRoot fixture)
              Graph.emptyNodePool
              (Inventory.allocationChildren fixture)
          )
    , testCase "nonproducer node cannot be promoted by an allocation root label" $ do
        fixture <- allocationFixture <$> getFixture
        (wrong, pool) <- mustRight (add NStarted [VWord 0] Graph.emptyNodePool)
        reject
          isWrongType
          ( Inventory.mkNativeAllocationData
              (Inventory.allocationAcquisitionNonce fixture)
              wrong
              pool
              (Inventory.allocationChildren fixture)
          )
    , testCase "trailing bytes and nonshortest version refuse" $ do
        fixture <- allocationFixture <$> getFixture
        reject
          isNonCanonical
          ( Inventory.decodeNativeAllocationData
              (Inventory.encodeNativeAllocationData fixture <> BS.singleton 0)
          )
        reject
          isNonCanonical
          ( Inventory.decodeNativeAllocationData
              (rawAllocation fixture (BS.pack [0x18, 0x01]) (poolPairs fixture))
          )
    , testCase "wrong allocation domain and version refuse" $ do
        fixture <- allocationFixture <$> getFixture
        reject
          isMalformed
          ( Inventory.decodeNativeAllocationData
              (rawAllocation fixture (Wire.encodeStrict (CBOR.encodeWord64 2)) (poolPairs fixture))
          )
        let bytes = Inventory.encodeNativeAllocationData fixture
            -- Same-length ASCII mutation, preserving all other wire structure.
            changed = BS.map (\byte -> if byte == 106 then 107 else byte) (BS.take 30 bytes) <> BS.drop 30 bytes
        assertBool "domain mutation changes bytes" (bytes /= changed)
        reject isMalformed (Inventory.decodeNativeAllocationData changed)
    , testCase "pool hash mismatch refuses the actual changed node bytes" $ do
        fixture <- allocationFixture <$> getFixture
        case poolPairs fixture of
          (digest, bytes) : rest ->
            reject
              isHashMismatch
              ( Inventory.decodeNativeAllocationData
                  (rawAllocation fixture versionOne ((digest, bytes <> BS.singleton 0) : rest))
              )
          [] -> assertFailure "fixture pool missing"
    , testCase "duplicate or descending physical pool keys refuse" $ do
        fixture <- allocationFixture <$> getFixture
        reject
          isNonCanonical
          ( Inventory.decodeNativeAllocationData
              (rawAllocation fixture versionOne (reverse (poolPairs fixture)))
          )
        case poolPairs fixture of
          first : rest ->
            reject
              isNonCanonical
              (Inventory.decodeNativeAllocationData (rawAllocation fixture versionOne (first : first : rest)))
          [] -> assertFailure "fixture pool missing"
    , testCase "producer grammar rejects a declared fifth physical node before payload allocation" $ do
        fixture <- allocationFixture <$> getFixture
        let prefix =
              CBOR.encodeListLen 6
                <> CBOR.encodeString "jitml-native-planned-five-v1"
                <> CBOR.encodeWord64 1
                <> CBOR.encodeBytes (Inventory.allocationAcquisitionNonce fixture)
                <> CBOR.encodeBytes (digestBytes (Inventory.allocationProducerRoot fixture))
                <> CBOR.encodeListLen 5
        reject (isResource PoolNodes) (Inventory.decodeNativeAllocationData (Wire.encodeStrict prefix))
    , testCase "oversized declared producer node bytes refuse without materializing them" $ do
        fixture <- allocationFixture <$> getFixture
        let prefix =
              Wire.encodeStrict
                ( CBOR.encodeListLen 6
                    <> CBOR.encodeString "jitml-native-planned-five-v1"
                    <> CBOR.encodeWord64 1
                    <> CBOR.encodeBytes (Inventory.allocationAcquisitionNonce fixture)
                    <> CBOR.encodeBytes (digestBytes (Inventory.allocationProducerRoot fixture))
                    <> CBOR.encodeListLen 1
                    <> CBOR.encodeListLen 2
                    <> CBOR.encodeBytes (digestBytes d0)
                )
            claimedBytes = BS.pack [0x59, 0x40, 0x01]
        -- 40-byte floor is satisfied so this targets the node byte cap.
        reject
          (isResource ProducerBundleBytes)
          (Inventory.decodeNativeAllocationData (prefix <> claimedBytes <> BS.replicate 40 0))
    , testCase "unknown row rejects before source observation environment and allocation" $ do
        batch <- batchFixture <$> getFixture
        result <-
          runReaderT
            ( Producer.produceNativeRlCohort
                batch
                "foreign-producer-row"
                (Producer.DirectNativeProducer "missing-source-must-not-be-read")
            )
            unavailableEnvironment
        assertStoppedBeforeClaim result
    , testCase "lazy batch failure returns a preclaim failure rather than escaping" $ do
        result <-
          runReaderT
            ( Producer.produceNativeRlCohort
                (error "actual lazy input fault")
                "ordinary"
                (Producer.DirectNativeProducer "missing-source-must-not-be-read")
            )
            unavailableEnvironment
        assertStoppedBeforeClaim result
    , testCase "asynchronous input cancellation propagates and mints no producer result" $ do
        attempted <-
          try
            ( runReaderT
                ( Producer.produceNativeRlCohort
                    (throw ThreadKilled)
                    "ordinary"
                    (Producer.DirectNativeProducer "missing-source-must-not-be-read")
                )
                unavailableEnvironment
            )
            :: IO (Either AsyncException Producer.NativeProducerResult)
        case attempted of
          Left ThreadKilled -> pure ()
          Left other -> assertFailure ("unexpected async exception " <> show other)
          Right _ -> assertFailure "async cancellation was turned into a producer result"
    ]

setup :: IO Fixture
setup = do
  allocation <- mustRight allocationDataFixture
  batch <-
    either
      (\detail -> assertFailure (show detail) >> fail "unreachable fixture assertion")
      pure
      (Cohort.mkCanonicalNativeRlCohorts LinuxCPU)
  pure (Fixture allocation batch)

unavailableEnvironment :: Env
unavailableEnvironment = error "pre-execution refusal must not force the App environment"

assertStoppedBeforeClaim :: Producer.NativeProducerResult -> Assertion
assertStoppedBeforeClaim actual = do
  assertEqual
    "no successful retained run"
    Producer.NativeProducerStoppedStatus
    (Producer.nativeProducerStatus actual)
  assertBool "no allocation ACK invented" (isNothing (Producer.nativeProducerAllocation actual))
  assertBool "no reference prelude ACK invented" (null (Producer.nativeProducerPreludeObjects actual))
  assertBool "no child started" (null (Producer.nativeProducerChildReports actual))
  assertBool "no retained inventory" (isNothing (Producer.nativeProducerRetainedInventory actual))
  assertBool "no produced cohort" (isNothing (Producer.nativeProducerProducedCohort actual))
  case Producer.nativeProducerFailure actual of
    Just Producer.NativeProducerRejected {} -> pure ()
    _ -> assertFailure "expected actual public preclaim rejection"

mustRight :: Either CodecError a -> IO a
mustRight value = case value of
  Right actual -> pure actual
  Left failure -> assertFailure (show failure) >> fail "unreachable fixture assertion"

reject :: (CodecError -> Bool) -> Either CodecError a -> Assertion
reject predicate value = case value of
  Left failure -> assertBool ("unexpected refusal " <> show failure) (predicate failure)
  Right _ -> assertFailure "unexpected accepted DATA"

isMalformed, isMissing, isWrongType, isNonCanonical, isHashMismatch :: CodecError -> Bool
isMalformed Malformed {} = True
isMalformed _ = False
isMissing MissingReference {} = True
isMissing _ = False
isWrongType WrongReferenceType {} = True
isWrongType _ = False
isNonCanonical NonCanonical {} = True
isNonCanonical _ = False
isHashMismatch HashMismatch {} = True
isHashMismatch _ = False
isResource :: Resource -> CodecError -> Bool
isResource resource (ResourceExceeded actual _ _) = resource == actual
isResource _ _ = False

d0 :: Digest
d0 = case mkDigest (BS.replicate 32 0) of
  Right value -> value
  Left _ -> error "fixed32-byte ordinary fixture invariant"

zeroMagnitude :: NodeValue
zeroMagnitude = VList [VWord 0, VBytes BS.empty]

add :: NodeKind -> [NodeValue] -> Graph.NodePool -> Either CodecError (Digest, Graph.NodePool)
add kind fields pool = Schema.mkNodeData kind fields >>= (`Graph.internNode` pool)

allocationDataFixture :: Either CodecError Inventory.NativeAllocationData
allocationDataFixture = do
  let acquisition = BS.replicate 32 0
  (record, p1) <-
    add
      NRecordedProducer
      ( [VText "ordinary-not-executed", VDigest d0, VWord 0, zeroMagnitude, zeroMagnitude]
          <> replicate 7 (VText "recorded-only")
          <> [VNull]
      )
      Graph.emptyNodePool
  (producer, pool) <- add NProducerContextBundle [VRef record, VNull, VNull] p1
  children <-
    sequence
      [ do
          let nonce = BS.replicate 32 (fromIntegral ordinal + 1)
              seed = 42 + ordinal
          context <-
            Schema.mkContextData
              [ VText "ordinary-row"
              , VWord 0
              , VText "ordinary-unbound-parent-label"
              , VText "ordinary-unbound-whole-cohort-label"
              , VText "ordinary-unbound-child-label"
              , VList (replicate 6 (VDigest d0) <> [VNull])
              , VDigest d0
              , VList [VWord 0]
              , VWord ordinal
              , VWord seed
              , VList [VWord 1, VWord 2000, VWord seed]
              , VDigest (Inventory.attemptNonceDigest nonce)
              , VDigest (Inventory.allocationNonceDigest acquisition)
              , VList [VWord 0, VDigest (Inventory.allocationNonceDigest acquisition)]
              , VList [VNull, VNull]
              , VRef producer
              ]
          Inventory.mkNativeAllocationChildData nonce context
      | ordinal <- [0 .. 4 :: Word64]
      ]
  Inventory.mkNativeAllocationData acquisition producer pool children

firstChild :: Inventory.NativeAllocationData -> IO Inventory.NativeAllocationChildData
firstChild fixture = case Inventory.allocationChildren fixture of
  first : _ -> pure first
  [] -> assertFailure "fixture child missing" >> fail "unreachable fixture assertion"

-- Keep the base-only indexed traversal and its lazy tail.
{- HLINT ignore replace "Use zipWithFrom" -}
replace :: Int -> a -> [a] -> [a]
replace target replacement = zipWith (\index original -> if index == target then replacement else original) [0 ..]

modifyChild
  :: Inventory.NativeAllocationChildData -> Int -> NodeValue -> IO Inventory.NativeAllocationChildData
modifyChild child position value = do
  context <-
    mustRight
      ( Schema.mkContextData
          (replace position value (Schema.contextFields (Inventory.allocationChildContext child)))
      )
  mustRight (Inventory.mkNativeAllocationChildData (Inventory.allocationChildNonce child) context)

mutateChild
  :: Inventory.NativeAllocationData
  -> Int
  -> Int
  -> NodeValue
  -> IO [Inventory.NativeAllocationChildData]
mutateChild fixture = mutateChildren (Inventory.allocationChildren fixture)

mutateChildren
  :: [Inventory.NativeAllocationChildData]
  -> Int
  -> Int
  -> NodeValue
  -> IO [Inventory.NativeAllocationChildData]
mutateChildren children target position value =
  sequence
    [ if index == target then modifyChild child position value else pure child
    | (index, child) <- zip [0 :: Int ..] children
    ]

rebuild
  :: Inventory.NativeAllocationData
  -> ByteString
  -> [Inventory.NativeAllocationChildData]
  -> Either CodecError Inventory.NativeAllocationData
rebuild fixture acquisition =
  Inventory.mkNativeAllocationData
    acquisition
    (Inventory.allocationProducerRoot fixture)
    (Inventory.allocationProducerPool fixture)

versionOne :: ByteString
versionOne = Wire.encodeStrict (CBOR.encodeWord64 1)

poolPairs :: Inventory.NativeAllocationData -> [(Digest, ByteString)]
poolPairs =
  map (\(digest, _, bytes) -> (digest, bytes))
    . Graph.nodePoolEntries
    . Inventory.allocationProducerPool

rawAllocation
  :: Inventory.NativeAllocationData -> ByteString -> [(Digest, ByteString)] -> ByteString
rawAllocation fixture encodedVersion entries =
  Wire.encodeStrict
    (CBOR.encodeListLen 6 <> CBOR.encodeString "jitml-native-planned-five-v1")
    <> encodedVersion
    <> Wire.encodeStrict
      ( CBOR.encodeBytes (Inventory.allocationAcquisitionNonce fixture)
          <> CBOR.encodeBytes (digestBytes (Inventory.allocationProducerRoot fixture))
          <> CBOR.encodeListLen (fromIntegral (length entries))
          <> foldMap pair entries
          <> CBOR.encodeListLen 5
          <> foldMap child (Inventory.allocationChildren fixture)
      )
 where
  pair (digest, bytes) = CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes
  child value =
    CBOR.encodeListLen 2
      <> CBOR.encodeBytes (Inventory.allocationChildNonce value)
      <> Wire.rawValueEncoding (VList (Schema.contextFields (Inventory.allocationChildContext value)))
