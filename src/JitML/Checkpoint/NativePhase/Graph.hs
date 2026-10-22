{-# LANGUAGE OverloadedStrings #-}

-- | Memoized, bounded ordinary DATA graph. No graph value is an execution or
-- retention capability. Hashes bind bytes, never their producer or source.
module JitML.Checkpoint.NativePhase.Graph
  ( NodePool
  , emptyNodePool
  , internNode
  , lookupNode
  , nodePoolEntries
  , reachableNodePool
  , validateReachableData
  , validateTypedRoots
  , producerClosureBytes
  , validateDigestTopology
  , checkGraphUsage
  , addGraphUsage
  ) where

import Control.Monad (foldM, unless, when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set

import JitML.Checkpoint.NativePhase.Schema
import JitML.Checkpoint.NativePhase.SchemaTable
import JitML.Checkpoint.NativePhase.Types

data StoredNode = StoredNode !NodeData !ByteString
data NodePool = NodePool !(Map Digest StoredNode) !Integer

emptyNodePool :: NodePool
emptyNodePool = NodePool Map.empty 0

lookupNode :: Digest -> NodePool -> Maybe NodeData
lookupNode digest (NodePool nodes _) = case Map.lookup digest nodes of
  Nothing -> Nothing
  Just (StoredNode node _) -> Just node

nodePoolEntries :: NodePool -> [(Digest, NodeData, ByteString)]
nodePoolEntries (NodePool nodes _) = [(digest, node, bytes) | (digest, StoredNode node bytes) <- Map.toAscList nodes]

-- NodeData is already schema-refined. Exact byte interning prevents Eq Double
-- from collapsing signedzero/NaN; a colliding unequal byte string is refused.
internNode :: NodeData -> NodePool -> Either CodecError (Digest, NodePool)
internNode node pool@(NodePool nodes ownedBytes) = do
  let bytes = nodeCanonicalBytes node
      digest = hashBytes bytes
  case Map.lookup digest nodes of
    Just (StoredNode _ existing)
      | existing == bytes -> Right (digest, pool)
      | otherwise -> Left (DigestCollision digest)
    Nothing -> do
      -- A builder may contain sibling roots. Its physical allocation is still
      -- bounded; phase aggregate counts are checked over the selected closure.
      checkLimit PoolNodes (toInteger (Map.size nodes) + 1)
      checkLimit WholePayloadBytes (ownedBytes + toInteger (BS.length bytes))
      let after =
            NodePool
              (Map.insert digest (StoredNode node bytes) nodes)
              (ownedBytes + toInteger (BS.length bytes))
      pure (digest, after)

requiredNode :: NodePool -> Digest -> Either CodecError NodeData
requiredNode pool digest = maybe (Left (MissingReference digest)) Right (lookupNode digest pool)

validateTarget :: NodePool -> (ReferenceTarget, Digest) -> Either CodecError ()
validateTarget pool (target, digest) = do
  node <- requiredNode pool digest
  case target of
    NodeTargets allowed ->
      unless (nodeKind node `elem` allowed) (Left (WrongReferenceType digest "node target kind differs"))
    SequenceTarget expected -> case (nodeKind node, nodeFields node) of
      (NSequenceManifest, kind : _) -> do
        actual <- readElementKind kind
        unless (actual == expected) (Left (WrongReferenceType digest "sequence element kind differs"))
      _ -> Left (WrongReferenceType digest "expected sequence manifest")

-- Validate the reference graph first, using memoized subtree heights. The
-- recursion limit is checked before descending. Repeated references count as
-- edges but never expand a shared subtree into copied data.
walkRoots :: [(ReferenceTarget, Digest)] -> NodePool -> Either CodecError (Set Digest, Integer)
walkRoots roots pool = do
  _ <- boundedLength TypedReferenceEdges (nativePhaseLimit TypedReferenceEdges) roots
  mapM_ (validateTarget pool) roots
  walkDigests (fmap snd roots) children
 where
  children digest = do
    node <- requiredNode pool digest
    references <- nodeReferences node
    mapM_ (validateTarget pool) references
    pure (fmap snd references)

-- Pure ordinary topology seam, also used by the actual checked-node walker.
-- It checks neither hashes nor node fields and cannot mint NodePool/PhaseData.
-- Exposing data adjacency makes cycles directly testable without forging SHA.
validateDigestTopology :: Map Digest [Digest] -> [Digest] -> Either CodecError Integer
validateDigestTopology adjacency roots = do
  checkLimit PoolNodes (toInteger (Map.size adjacency))
  rootCount <- boundedLength TypedReferenceEdges (nativePhaseLimit TypedReferenceEdges) roots
  counts <-
    mapM
      (boundedLength TypedReferenceEdges (nativePhaseLimit TypedReferenceEdges))
      (Map.elems adjacency)
  checkLimit TypedReferenceEdges (sum (fmap toInteger counts) + toInteger rootCount)
  (_, depth) <-
    walkDigests
      roots
      (\digest -> maybe (Left (MissingReference digest)) Right (Map.lookup digest adjacency))
  pure depth

walkDigests
  :: [Digest] -> (Digest -> Either CodecError [Digest]) -> Either CodecError (Set Digest, Integer)
walkDigests roots children = do
  (_, visited, maximumDepth) <- foldM root (Map.empty, Set.empty, 0) roots
  pure (visited, maximumDepth)
 where
  root (heights, visited, maximumDepth) digest = do
    (height, nextHeights, nextVisited) <- visit 1 Set.empty heights visited digest
    pure (nextHeights, nextVisited, max maximumDepth (height + 1))
  visit depth active heights visited digest = do
    checkLimit ReferenceDepth depth
    when (Set.member digest active) (Left (ReferenceCycle digest))
    case Map.lookup digest heights of
      Just height -> do
        checkLimit ReferenceDepth (depth + height)
        pure (height, heights, visited)
      Nothing -> do
        references <- children digest
        let nextActive = Set.insert digest active
            nextVisited = Set.insert digest visited
        (height, afterHeights, afterVisited) <-
          foldM (child depth nextActive) (0, heights, nextVisited) references
        pure (height, Map.insert digest height afterHeights, afterVisited)
  child depth active (height, heights, visited) digest = do
    (childHeight, afterHeights, afterVisited) <- visit (depth + 1) active heights visited digest
    pure (max height (childHeight + 1), afterHeights, afterVisited)

addGraphUsage :: GraphUsage -> GraphUsage -> GraphUsage
addGraphUsage left right =
  GraphUsage
    (usageNodes left + usageNodes right)
    (usageEdges left + usageEdges right)
    (usageSequenceElements left + usageSequenceElements right)
    (usageF64Coordinates left + usageF64Coordinates right)
    (max (usageReferenceDepth left) (usageReferenceDepth right))
    (usageEncodedBytes left + usageEncodedBytes right)

checkGraphUsage :: GraphUsage -> Either CodecError ()
checkGraphUsage usage = do
  checkLimit PoolNodes (usageNodes usage)
  checkLimit TypedReferenceEdges (usageEdges usage)
  checkLimit AggregateSequenceElements (usageSequenceElements usage)
  checkLimit AggregateF64Coordinates (usageF64Coordinates usage)
  checkLimit ReferenceDepth (usageReferenceDepth usage)
  checkLimit WholePayloadBytes (usageEncodedBytes usage)

-- Returns a shared-node subset, not expanded records or a restored stage.
reachableNodePool :: [Digest] -> NodePool -> Either CodecError NodePool
reachableNodePool roots pool@(NodePool nodes _) = do
  (reachable, _) <- walkRoots [(NodeTargets allNodeKinds, digest) | digest <- roots] pool
  let selected = Map.restrictKeys nodes reachable
      bytes = sum [toInteger (BS.length value) | StoredNode _ value <- Map.elems selected]
      pruned = NodePool selected bytes
  _ <- validateReachableData roots pruned
  pure pruned

validateReachableData :: [Digest] -> NodePool -> Either CodecError GraphUsage
validateReachableData roots = validateTypedRoots [(NodeTargets allNodeKinds, digest) | digest <- roots]

validateTypedRoots :: [(ReferenceTarget, Digest)] -> NodePool -> Either CodecError GraphUsage
validateTypedRoots roots pool@(NodePool nodes _) = do
  (reachable, maximumDepth) <- walkRoots roots pool
  case Set.lookupMin (Map.keysSet nodes `Set.difference` reachable) of
    Just digest -> Left (UnreachablePoolMember digest)
    Nothing -> pure ()
  usage <- foldM add emptyUsage (Map.elems nodes)
  let total =
        usage {usageEdges = usageEdges usage + toInteger (length roots), usageReferenceDepth = maximumDepth}
  checkGraphUsage total
  mapM_ (validateStructure pool . firstNode) (Map.elems nodes)
  pure total
 where
  firstNode (StoredNode node _) = node
  add acc (StoredNode node _) = do
    value <- nodeLocalUsage node
    let after = addGraphUsage acc value
    checkGraphUsage after
    pure after

-- The16KiB producer cap charges canonical node bytes in the unique reachable
-- ProducerContextBundle/RecordedProducer/RuntimeMetadata closure. Pair wrappers
-- are charged separately by the complete256MiB envelope calculation.
producerClosureBytes :: Digest -> NodePool -> Either CodecError Integer
producerClosureBytes digest pool = do
  validateTarget pool (NodeTargets [NProducerContextBundle], digest)
  pruned <- reachableNodePool [digest] pool
  let entries = nodePoolEntries pruned
      allowed = [NProducerContextBundle, NRecordedProducer, NRuntimeMetadata]
  unless
    (all (\(_, node, _) -> nodeKind node `elem` allowed) entries)
    (Left (Malformed "producer closure contains a nonproducer node"))
  let bytes = sum [toInteger (BS.length value) | (_, _, value) <- entries]
  checkLimit ProducerBundleBytes bytes
  pure bytes

validateStructure :: NodePool -> NodeData -> Either CodecError ()
validateStructure pool node = case (nodeKind node, nodeFields node) of
  (NTensorManifest, [VWord _, VWord totalBytes, VList children]) -> do
    let expected = ceilingDivide (toInteger totalBytes) (nativePhaseLimit TensorChunkBytes)
    unless (toInteger (length children) == expected) (Left (NonCanonical "tensor chunk count differs"))
    mapM_ (checkChunk totalBytes) (zip [0 :: Integer ..] children)
  (NSequenceManifest, [kind, VWord count, VWord height, VList children]) -> do
    element <- readElementKind kind
    let capacity = if height == 2 then 65536 else 256
    mapM_ (checkSequenceChild element height count capacity) (zip [0 :: Integer ..] children)
  (NSequenceIndex, [kind, _, VWord count, VList children]) -> do
    element <- readElementKind kind
    mapM_ (checkSequenceChild element 1 count 256) (zip [0 :: Integer ..] children)
  (NRawNeural, [VWord family, _, VRef expectedConfig, _, VRef actualConfig, _, _, VRef stats, _, _]) -> do
    (configKind, statKind) <- neuralKinds family
    validateTarget pool (NodeTargets [configKind], expectedConfig)
    validateTarget pool (NodeTargets [configKind], actualConfig)
    validateSequenceMembers pool stats statKind
  (NReturnPolicy, [VWord family, VRef config, VRef parameters]) -> case family of
    5 -> do
      validateTarget pool (NodeTargets [NArsConfig], config)
      validateTarget pool (NodeTargets (aliasKinds TensorAlias), parameters)
    n | n <= 3 -> do
      (configKind, _) <- neuralKinds n
      validateTarget pool (NodeTargets [configKind], config)
      validateTarget pool (NodeTargets [NParams], parameters)
    _ -> Left (Malformed "RETURN policy has unsupported family")
  (NPpoSnapshot, values) -> frameSequence "frames" values
  (NDqnSnapshot, values) -> frameField "frame" values
  (NQrSnapshot, values) -> frameField "frame" values
  (NContinuousSnapshot, values) -> frameField "observation" values
  (NArsSnapshot, values) -> frameField "initialFrame" values
  _ -> Right ()
 where
  checkChunk totalBytes (index, value) = do
    digest <- referenceValue value
    chunk <- requiredNode pool digest
    case (nodeKind chunk, nodeFields chunk) of
      (NTensorChunk, [VWord ordinal, VBytes bytes]) -> do
        let expectedBytes =
              min
                (nativePhaseLimit TensorChunkBytes)
                (toInteger totalBytes - index * nativePhaseLimit TensorChunkBytes)
        unless
          (toInteger ordinal == index && toInteger (BS.length bytes) == expectedBytes)
          (Left (NonCanonical "tensor chunk ordinal/size differs"))
      _ -> Left (WrongReferenceType digest "expected tensor chunk")
  checkSequenceChild element height total capacity (index, value) = do
    digest <- referenceValue value
    child <- requiredNode pool digest
    let expectedCount = min capacity (toInteger total - index * capacity)
    case (nodeKind child, nodeFields child) of
      (NSequenceIndex, [kind, VWord remainingHeight, VWord count, _]) | height == 2 -> do
        actual <- readElementKind kind
        unless
          (actual == element && remainingHeight == 1 && toInteger count == expectedCount)
          (Left (NonCanonical "sequence index kind/count/height differs"))
      (NReferencePage, [kind, VWord count, _]) | height == 1 -> page element kind count expectedCount False
      (NScalarPage, [kind, VWord count, _]) | height == 1 -> page element kind count expectedCount True
      _ -> Left (WrongReferenceType digest "sequence height child differs")
  page expected kind count expectedCount scalar = do
    actual <- readElementKind kind
    unless
      (actual == expected && toInteger count == expectedCount && isScalar expected == scalar)
      (Left (NonCanonical "sequence page kind/count differs"))
  isScalar (ScalarElement _) = True
  isScalar _ = False
  field name values =
    maybe
      (Left (Malformed "missing private schema field"))
      Right
      (lookup name (zip (nodeFieldNames (nodeKind node)) values))
  frameField name values = field name values >>= referenceValue >>= checkFrameTensor pool
  frameSequence name values = do
    digest <- field name values >>= referenceValue
    visitSequenceReferences pool digest (checkFrameTensor pool)

referenceValue :: NodeValue -> Either CodecError Digest
referenceValue (VRef digest) = Right digest
referenceValue _ = Left (Malformed "expected checked reference value")

ceilingDivide :: Integer -> Integer -> Integer
ceilingDivide numerator denominator = (numerator + denominator - 1) `div` denominator

neuralKinds :: (Integral a) => a -> Either CodecError (NodeKind, NodeKind)
neuralKinds family = case toInteger family of
  0 -> Right (NPpoConfig, NPpoStat)
  1 -> Right (NDqnConfig, NDqnStat)
  2 -> Right (NQrConfig, NQrStat)
  3 -> Right (NContinuousConfig, NContinuousStat)
  4 -> Right (NHerConfig, NHerStat)
  _ -> Left (Malformed "unknown neural family")

validateSequenceMembers :: NodePool -> Digest -> NodeKind -> Either CodecError ()
validateSequenceMembers pool root expected =
  visitSequenceReferences pool root (\digest -> validateTarget pool (NodeTargets [expected], digest))

-- At most two index levels; visit a shared page once rather than flattening a
-- potentially repeated logical sequence. Repeated occurrences remain in DATA.
visitSequenceReferences
  :: NodePool -> Digest -> (Digest -> Either CodecError ()) -> Either CodecError ()
visitSequenceReferences pool root action = go Set.empty root >> Right ()
 where
  go seen digest
    | Set.member digest seen = Right seen
    | otherwise = do
        node <- requiredNode pool digest
        let next = Set.insert digest seen
        case (nodeKind node, nodeFields node) of
          (NSequenceManifest, [_, _, _, VList children]) -> foldM visit next children
          (NSequenceIndex, [_, _, _, VList children]) -> foldM visit next children
          (NReferencePage, [_, _, VList elements]) -> mapM_ (referenceValue >=> action) elements >> Right next
          _ -> Left (WrongReferenceType digest "expected reference sequence page")
  visit seen value = referenceValue value >>= go seen
  (>=>) left right value = left value >>= right

checkFrameTensor :: NodePool -> Digest -> Either CodecError ()
checkFrameTensor pool digest = do
  node <- requiredNode pool digest
  bytes <- case (nodeKind node, nodeFields node) of
    (NTensorLeaf, [_, VBytes value]) -> Right (toInteger (BS.length value))
    (NTensorManifest, [_, VWord value, _]) -> Right (toInteger value)
    _ -> Left (WrongReferenceType digest "frame must be tensor")
  checkLimit FrameBytes bytes
