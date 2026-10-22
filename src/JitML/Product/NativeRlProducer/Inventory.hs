{-# LANGUAGE OverloadedStrings #-}

-- | Separate versioned allocation DATA. Parsing cannot reserve a slot, observe
-- randomness, restore a stage or construct a producer capability.
module JitML.Product.NativeRlProducer.Inventory
  ( NativeAllocationData
  , NativeAllocationChildData
  , mkNativeAllocationData
  , mkNativeAllocationChildData
  , allocationAcquisitionNonce
  , allocationChildren
  , allocationProducerRoot
  , allocationProducerPool
  , allocationChildNonce
  , allocationChildContext
  , encodeNativeAllocationData
  , decodeNativeAllocationData
  , allocationNonceDigest
  , attemptNonceDigest
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (replicateM, unless, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Set qualified as Set

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types

-- Five contexts can each consume2MiB, plus one16KiB producer closure and small
-- fixed headers/nonces. The separate16MiB bound accommodates that whole domain.
maximumAllocationBytes :: Integer
maximumAllocationBytes = 16 * 1024 * 1024

data NativeAllocationChildData = NativeAllocationChildData !ByteString !Schema.ContextData

data NativeAllocationData
  = NativeAllocationData !ByteString !Digest !Graph.NodePool ![NativeAllocationChildData]

allocationAcquisitionNonce :: NativeAllocationData -> ByteString
allocationAcquisitionNonce (NativeAllocationData value _ _ _) = value
allocationChildren :: NativeAllocationData -> [NativeAllocationChildData]
allocationChildren (NativeAllocationData _ _ _ values) = values
allocationProducerRoot :: NativeAllocationData -> Digest
allocationProducerRoot (NativeAllocationData _ value _ _) = value
allocationProducerPool :: NativeAllocationData -> Graph.NodePool
allocationProducerPool (NativeAllocationData _ _ value _) = value
allocationChildNonce :: NativeAllocationChildData -> ByteString
allocationChildNonce (NativeAllocationChildData value _) = value
allocationChildContext :: NativeAllocationChildData -> Schema.ContextData
allocationChildContext (NativeAllocationChildData _ value) = value

allocationNonceDigest :: ByteString -> Digest
allocationNonceDigest nonce = hashBytes ("jitml-native-acquisition-nonce-v1\NUL" <> nonce)
attemptNonceDigest :: ByteString -> Digest
attemptNonceDigest nonce = hashBytes ("jitml-native-attempt-nonce-v1\NUL" <> nonce)

mkNativeAllocationChildData
  :: ByteString -> Schema.ContextData -> Either CodecError NativeAllocationChildData
mkNativeAllocationChildData nonce context = do
  unless
    (BS.length nonce == 32)
    (Left (Malformed "allocation child nonce must contain32 actual recorded bytes"))
  case Schema.contextFields context of
    [_, _, _, _, _, _, _, _, _, _, _, VDigest attempt, _, _, _, _] ->
      unless
        (attempt == attemptNonceDigest nonce)
        (Left (Malformed "allocation child nonce/context digest mismatch"))
    _ -> Left (Malformed "allocation child context differs")
  pure (NativeAllocationChildData nonce context)

mkNativeAllocationData
  :: ByteString
  -> Digest
  -> Graph.NodePool
  -> [NativeAllocationChildData]
  -> Either CodecError NativeAllocationData
mkNativeAllocationData acquisition producer pool children = do
  unless
    (BS.length acquisition == 32)
    (Left (Malformed "allocation acquisition nonce must contain32 bytes"))
  count <- boundedLength SequenceFanout 5 children
  unless (count == 5) (Left (Malformed "allocation must contain exactly five children"))
  let nonces = acquisition : fmap allocationChildNonce children
  unless (Set.size (Set.fromList nonces) == 6) (Left (Malformed "allocation nonce identities repeat"))
  unless
    (Set.size (Set.fromList (fmap (attemptNonceDigest . allocationChildNonce) children)) == 5)
    (Left (Malformed "allocation attempt digest identities repeat"))
  case children of
    servingChild : _ -> do
      baseline <- commonFields (allocationChildContext servingChild)
      base <- childSeed (allocationChildContext servingChild)
      mapM_
        ( \(ordinal, child) -> do
            fields <- commonFields (allocationChildContext child)
            seed <- childSeed (allocationChildContext child)
            unless
              (fields == baseline && toInteger seed == toInteger base + ordinal)
              (Left (Malformed "allocation common pool/ordered seed fields differ"))
        )
        (zip [0 .. 4] children)
    [] -> Left (Malformed "allocation has no serving child")
  closure <- Graph.reachableNodePool [producer] pool
  _ <- Graph.producerClosureBytes producer closure
  -- Do not silently prune a caller's foreign pool into admissible claim DATA.
  unless
    (fmap first (Graph.nodePoolEntries pool) == fmap first (Graph.nodePoolEntries closure))
    (Left (Malformed "allocation producer pool contains foreign nodes"))
  mapM_ (checkChild producer (allocationNonceDigest acquisition)) (zip [0 .. 4] children)
  let value = NativeAllocationData acquisition producer closure children
  when
    (toInteger (BS.length (encodeNativeAllocationData value)) > maximumAllocationBytes)
    (Left (ResourceExceeded WholePayloadBytes maximumAllocationBytes (maximumAllocationBytes + 1)))
  pure value
 where
  first (digest, _, _) = digest
  commonFields context = case Schema.contextFields context of
    [ row
      , lane
      , parent
      , cohort
      , _
      , VList [projection, parentId, parentCommon, _, _, cohortId, _]
      , _
      , _
      , _
      , _
      , VList [kind, target, _]
      , _
      , acquisitionId
      , invocation
      , sources
      , producerRef
      ] ->
        Right
          [ row
          , lane
          , parent
          , cohort
          , projection
          , parentId
          , parentCommon
          , cohortId
          , kind
          , target
          , acquisitionId
          , invocation
          , sources
          , producerRef
          ]
    _ -> Left (Malformed "allocation shared context shape differs")
  childSeed context = case Schema.contextFields context of
    [_, _, _, _, _, _, _, _, _, VWord seed, VList [_, _, VWord budgetSeed], _, _, _, _, _] | seed == budgetSeed -> Right seed
    _ -> Left (Malformed "allocation budget and actual seed differ")
  checkChild expectedProducer expectedAcquisition (ordinal, child) = do
    _ <- mkNativeAllocationChildData (allocationChildNonce child) (allocationChildContext child)
    case Schema.contextFields (allocationChildContext child) of
      [ _
        , _
        , _
        , _
        , _
        , _
        , _
        , _
        , VWord actual
        , _
        , _
        , _
        , VDigest recordedAcquisition
        , _
        , _
        , VRef recordedProducer
        ] ->
          unless
            ( actual == ordinal
                && recordedAcquisition == expectedAcquisition
                && recordedProducer == expectedProducer
            )
            (Left (Malformed "allocation ordered context identities differ"))
      _ -> Left (Malformed "allocation child context arity differs")

encodeNativeAllocationData :: NativeAllocationData -> ByteString
encodeNativeAllocationData (NativeAllocationData acquisition producer pool children) =
  Wire.encodeStrict
    ( CBOR.encodeListLen 6
        <> CBOR.encodeString "jitml-native-planned-five-v1"
        <> CBOR.encodeWord64 1
        <> CBOR.encodeBytes acquisition
        <> CBOR.encodeBytes (digestBytes producer)
        <> CBOR.encodeListLen (fromIntegral (length entries))
        <> foldMap node entries
        <> CBOR.encodeListLen 5
        <> foldMap child children
    )
 where
  entries = Graph.nodePoolEntries pool
  node (digest, _, bytes) = CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes bytes
  child (NativeAllocationChildData nonce context) =
    CBOR.encodeListLen 2
      <> CBOR.encodeBytes nonce
      <> Wire.rawValueEncoding (VList (Schema.contextFields context))

decodeNativeAllocationData :: ByteString -> Either CodecError NativeAllocationData
decodeNativeAllocationData bytes = do
  when
    (toInteger (BS.length bytes) > maximumAllocationBytes)
    (Left (ResourceExceeded WholePayloadBytes maximumAllocationBytes (toInteger (BS.length bytes))))
  decoded <- Wire.runParser parser bytes
  unless
    (encodeNativeAllocationData decoded == bytes)
    (Left (NonCanonical "allocation encoding differs"))
  pure decoded
 where
  parser = do
    Wire.expectList 6
    domain <- Wire.getText GeneralTextBytes 64
    unless
      (domain == "jitml-native-planned-five-v1")
      (Wire.parserFailure (Malformed "allocation domain differs"))
    version <- Wire.getWord
    unless (version == 1) (Wire.parserFailure (Malformed "allocation version differs"))
    acquisition <- Wire.getBytes GeneralTextBytes 32
    producer <- Wire.getDigest
    -- The closed producer grammar has one bundle, at most two process nodes
    -- and one runtime node. Bound its physical pool before allocating a map.
    count <- Wire.getListLength PoolNodes 4
    Wire.ensureMinimumItems (fromIntegral count) 40
    pool <- nodes count Nothing Graph.emptyNodePool 0
    Wire.expectList 5
    children <- replicateM 5 child
    Wire.liftEither (mkNativeAllocationData acquisition producer pool children)
  child = do
    Wire.expectList 2
    nonce <- Wire.getBytes GeneralTextBytes 32
    context <- Schema.parseContextData
    Wire.liftEither (mkNativeAllocationChildData nonce context)
  nodes 0 _ pool _ = pure pool
  nodes count previous pool owned = do
    Wire.expectList 2
    digest <- Wire.getDigest
    case previous of
      Just before ->
        unless
          (before < digest)
          (Wire.parserFailure (NonCanonical "allocation pool order/uniqueness differs"))
      Nothing -> pure ()
    bytesValue <- Wire.getBytes ProducerBundleBytes (nativePhaseLimit ProducerBundleBytes)
    unless (hashBytes bytesValue == digest) (Wire.parserFailure (HashMismatch digest))
    let afterBytes = owned + toInteger (BS.length bytesValue)
    Wire.liftEither (checkLimit ProducerBundleBytes afterBytes)
    node <- Wire.liftEither (Schema.decodeNodeData bytesValue)
    (_, after) <- Wire.liftEither (Graph.internNode node pool)
    nodes (count - 1) (Just digest) after afterBytes
