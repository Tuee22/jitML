{-# LANGUAGE OverloadedStrings #-}

-- | Separate versioned reference-family DATA. Decoding cannot construct an
-- actual calibration, plan, capsule, ACK, origin, qualification or restoration.
module JitML.Checkpoint.NativeReferences
  ( NativeReferenceData
  , ReferenceFamily (..)
  , NativeReferenceFailureData
  , decodeNativeReferenceFailureData
  , nativeReferenceFailureDataFields
  , nativeReferenceFailureDataBytes
  , nativeReferenceDataBytes
  , nativeReferenceDataFamily
  , nativeReferenceDataCohortId
  , nativeReferenceDataCohortTransport
  , nativeReferenceDataSpecRoot
  , nativeReferenceDataSpecPool
  , nativeReferenceDataBody
  , checkNativeReferenceInput
  , encodeNativeReturnReferencesData
  , encodeNativeHerReferencesData
  , encodeNativeArenaReferencesData
  , decodeNativeReferenceData
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReferences.Body
import JitML.RL.AlphaZero.NativeArenaReferences qualified as Arena
import JitML.RL.NativeHerReferences qualified as Her
import JitML.RL.NativeReturnReferences qualified as Return

bodyCap, headerCap, cohortCap, chunkCap, envelopeCap :: Integer
bodyCap = 128 * 1024 * 1024
headerCap = 65536
cohortCap = 1024 * 1024
chunkCap = 1024 * 1024
envelopeCap = bodyCap + cohortCap + headerCap + 8192

data NativeReferenceData
  = NativeReferenceData
      !ReferenceFamily
      !Text
      !ByteString
      !Digest
      !Graph.NodePool
      !ByteString
      !ByteString

nativeReferenceDataFamily :: NativeReferenceData -> ReferenceFamily
nativeReferenceDataFamily (NativeReferenceData x _ _ _ _ _ _) = x
nativeReferenceDataCohortId :: NativeReferenceData -> Text
nativeReferenceDataCohortId (NativeReferenceData _ x _ _ _ _ _) = x
nativeReferenceDataCohortTransport :: NativeReferenceData -> ByteString
nativeReferenceDataCohortTransport (NativeReferenceData _ _ x _ _ _ _) = x
nativeReferenceDataSpecRoot :: NativeReferenceData -> Digest
nativeReferenceDataSpecRoot (NativeReferenceData _ _ _ x _ _ _) = x
nativeReferenceDataSpecPool :: NativeReferenceData -> Graph.NodePool
nativeReferenceDataSpecPool (NativeReferenceData _ _ _ _ x _ _) = x
nativeReferenceDataBody :: NativeReferenceData -> ByteString
nativeReferenceDataBody (NativeReferenceData _ _ _ _ _ x _) = x
nativeReferenceDataBytes :: NativeReferenceData -> ByteString
nativeReferenceDataBytes (NativeReferenceData _ _ _ _ _ _ x) = x

require :: Bool -> Text -> Either CodecError ()
require predicate detail = unless predicate (Left (Malformed detail))
capBytes :: Integer -> ByteString -> Either CodecError ()
capBytes cap bytes =
  when
    (toInteger (BS.length bytes) > cap)
    (Left (ResourceExceeded WholePayloadBytes cap (toInteger (BS.length bytes))))
nodeAt :: Graph.NodePool -> Digest -> Either CodecError Schema.NodeData
nodeAt pool digest = maybe (Left (MissingReference digest)) Right (Graph.lookupNode digest pool)

-- The header reuses existing public spec/schedule node projections without
-- adding a node kind or constructing a child phase/context. Exact closure only.
specBytes :: Digest -> Graph.NodePool -> Either CodecError ByteString
specBytes root pool = do
  _ <- boundedLength PoolNodes 64 (Graph.nodePoolEntries pool)
  let ownedUpper = sum [toInteger (BS.length bytes) + 64 | (_, _, bytes) <- Graph.nodePoolEntries pool]
  when (ownedUpper > headerCap) (Left (ResourceExceeded WholePayloadBytes headerCap ownedUpper))
  closure <- Graph.reachableNodePool [root] pool
  require
    (fmap key (Graph.nodePoolEntries pool) == fmap key (Graph.nodePoolEntries closure))
    "reference spec pool has foreign nodes"
  let entries = Graph.nodePoolEntries closure
  require (length entries <= 64) "reference spec header has more than64 nodes"
  _ <- dimensions closure root
  let bytes =
        Wire.encodeStrict
          ( CBOR.encodeListLen 2
              <> CBOR.encodeBytes (digestBytes root)
              <> CBOR.encodeListLen (fromIntegral (length entries))
              <> foldMap
                ( \(digest, _, value) -> CBOR.encodeListLen 2 <> CBOR.encodeBytes (digestBytes digest) <> CBOR.encodeBytes value
                )
                entries
          )
  capBytes headerCap bytes
  pure bytes
 where
  key (digest, _, _) = digest

-- Keep the protocol's lowercase ASCII hex predicate.
{- HLINT ignore checkNativeReferenceInput "Use isDigit" -}
checkNativeReferenceInput :: Text -> ByteString -> Digest -> Graph.NodePool -> Either CodecError ()
checkNativeReferenceInput identity transport root pool = do
  require
    (Text.length identity == 64 && Text.all (\c -> c >= '0' && c <= '9' || c >= 'a' && c <= 'f') identity)
    "reference cohort ID is not canonical lowercase hex"
  capBytes cohortCap transport
  require (not (BS.null transport)) "reference whole cohort transport is absent"
  case UTF8.decodeUtf8' transport of
    Left _ -> Left (Malformed "reference whole cohort is not UTF8")
    Right _ -> Right ()
  _ <- specBytes root pool
  pure ()

encodeNativeReturnReferencesData
  :: Text
  -> ByteString
  -> Digest
  -> Graph.NodePool
  -> Return.NativeReturnReferenceSet
  -> Either CodecError NativeReferenceData
encodeNativeReturnReferencesData identity transport root pool actual = do
  checkNativeReferenceInput identity transport root pool
  shape <- dimensions pool root
  body <- encodeReturnBody shape actual
  makeData ReturnReferenceFamily identity transport root pool body
encodeNativeHerReferencesData
  :: Text
  -> ByteString
  -> Digest
  -> Graph.NodePool
  -> Her.NativeHerReferenceFamily
  -> Either CodecError NativeReferenceData
encodeNativeHerReferencesData identity transport root pool actual = do
  checkNativeReferenceInput identity transport root pool
  require
    ((Schema.nodeKind <$> nodeAt pool root) == Right NHerSchedule)
    "HER reference header kind differs"
  body <- encodeHerBody actual
  makeData HerReferenceFamily identity transport root pool body
encodeNativeArenaReferencesData
  :: Text
  -> ByteString
  -> Digest
  -> Graph.NodePool
  -> Arena.NativeArenaReferenceSet
  -> Either CodecError NativeReferenceData
encodeNativeArenaReferencesData identity transport root pool actual = do
  checkNativeReferenceInput identity transport root pool
  shape <- dimensions pool root
  body <- encodeArenaBody shape actual
  makeData ArenaReferenceFamily identity transport root pool body

makeData
  :: ReferenceFamily
  -> Text
  -> ByteString
  -> Digest
  -> Graph.NodePool
  -> ByteString
  -> Either CodecError NativeReferenceData
makeData family identity transport root pool body = do
  checkNativeReferenceInput identity transport root pool
  shape <- dimensions pool root
  require (family == familyFor shape) "reference body/header family differs"
  validateBody shape body
  header <- specBytes root pool
  capBytes bodyCap body
  let bytes = envelope family identity transport header body
  capBytes envelopeCap bytes
  pure (NativeReferenceData family identity transport root pool body bytes)

envelope :: ReferenceFamily -> Text -> ByteString -> ByteString -> ByteString -> ByteString
envelope family identity transport header body =
  Wire.encodeStrict
    ( CBOR.encodeListLen 9
        <> CBOR.encodeString "jitml-native-reference-data-v1"
        <> CBOR.encodeWord64 1
        <> CBOR.encodeWord64 (fromIntegral (fromEnum family))
        <> CBOR.encodeString identity
        <> CBOR.encodeBytes transport
        <> CBOR.encodeBytes header
        <> CBOR.encodeWord64 (fromIntegral (BS.length body))
        <> CBOR.encodeListLen (fromIntegral (length chunks))
        <> foldMap CBOR.encodeBytes chunks
        <> CBOR.encodeBytes (SHA256.hash body)
    )
 where
  chunks = partitionBytes body
  partitionBytes bytes | BS.null bytes = []
  partitionBytes bytes = let (first, rest) = BS.splitAt (fromInteger chunkCap) bytes in first : partitionBytes rest

decodeNativeReferenceData :: ByteString -> Either CodecError NativeReferenceData
decodeNativeReferenceData bytes = do
  capBytes envelopeCap bytes
  actual <- Wire.runParser parse bytes
  require (nativeReferenceDataBytes actual == bytes) "noncanonical reference envelope"
  pure actual
 where
  parse = do
    Wire.expectList 9
    domain <- Wire.getText GeneralTextBytes 64
    Wire.liftEither (require (domain == "jitml-native-reference-data-v1") "unknown reference domain")
    version <- Wire.getWord
    Wire.liftEither (require (version == 1) "unknown reference version")
    tag <- Wire.getWord
    family <- case tag of
      0 -> pure ReturnReferenceFamily
      1 -> pure HerReferenceFamily
      2 -> pure ArenaReferenceFamily
      _ -> Wire.parserFailure (Malformed "unknown reference family")
    identity <- Wire.getText GeneralTextBytes 64
    transport <- Wire.getBytes WholePayloadBytes cohortCap
    header <- Wire.getBytes WholePayloadBytes headerCap
    (root, pool) <- Wire.liftEither (decodeSpec header)
    declared <- Wire.getWord
    Wire.liftEither
      (require (declared > 0 && toInteger declared <= bodyCap) "reference body size is outside scope")
    count <- Wire.getListLength AggregateSequenceElements 128
    let expected = (toInteger declared + chunkCap - 1) `div` chunkCap
    Wire.liftEither (require (toInteger count == expected) "reference chunk count differs")
    chunks <-
      mapM
        ( \ordinal -> do
            part <- Wire.getBytes WholePayloadBytes chunkCap
            let wanted = if ordinal == count - 1 then toInteger declared - toInteger ordinal * chunkCap else chunkCap
            Wire.liftEither
              (require (toInteger (BS.length part) == wanted) "reference chunk has nonminimal size")
            pure part
        )
        [0 .. count - 1]
    checksum <- Wire.getBytes GeneralTextBytes 32
    let body = BS.concat chunks
    Wire.liftEither
      (require (BS.length checksum == 32 && SHA256.hash body == checksum) "reference body checksum differs")
    Wire.liftEither (makeData family identity transport root pool body)

decodeSpec :: ByteString -> Either CodecError (Digest, Graph.NodePool)
decodeSpec bytes = do
  capBytes headerCap bytes
  result@(root, pool) <- Wire.runParser parse bytes
  encoded <- specBytes root pool
  require (encoded == bytes) "reference spec header is not canonical"
  pure result
 where
  parse = do
    Wire.expectList 2
    root <- Wire.getDigest
    count <- Wire.getListLength PoolNodes 64
    Wire.ensureMinimumItems (fromIntegral count) 40
    pool <- nodes count Nothing Graph.emptyNodePool 0
    pure (root, pool)
  nodes 0 _ pool _ = pure pool
  nodes count previous pool owned = do
    Wire.expectList 2
    digest <- Wire.getDigest
    Wire.liftEither
      (require (maybe True (< digest) previous) "reference spec keys are not ordered unique")
    bytesValue <- Wire.getBytes WholePayloadBytes headerCap
    let after = owned + toInteger (BS.length bytesValue)
    Wire.liftEither (require (after <= headerCap) "reference spec cumulative bytes exceed cap")
    Wire.liftEither (require (hashBytes bytesValue == digest) "reference spec node checksum differs")
    node <- Wire.liftEither (Schema.decodeNodeData bytesValue)
    (_, next) <- Wire.liftEither (Graph.internNode node pool)
    nodes (count - 1) (Just digest) next after

familyFor :: ReferenceDimensions -> ReferenceFamily
familyFor ReturnDimensions {} = ReturnReferenceFamily
familyFor HerDimensions = HerReferenceFamily
familyFor ArenaDimensions {} = ArenaReferenceFamily

-- Exact source-public header shapes; no current plan/refinement/capsule factory
-- is invoked by the decoder. Bounds only, never an authenticity declaration.
dimensions :: Graph.NodePool -> Digest -> Either CodecError ReferenceDimensions
dimensions pool root = do
  node <- nodeAt pool root
  case (Schema.nodeKind node, Schema.nodeFields node) of
    (NReturnSpec, [_, _, _, _, _, _, VInt cases, VInt horizon, _, VList domain]) -> do
      require
        (cases == 20 && horizon > 0 && horizon <= 1000)
        "RETURN header dimensions exceed canonical scope"
      controls <- case domain of
        [VWord 0, VInt actions] -> do
          require (actions > 0 && actions <= 6) "RETURN discrete actions exceed scope"
          pure (fromIntegral actions)
        [VWord 1, VInt actions] -> do
          require (actions > 0 && actions <= 6) "RETURN masked actions exceed scope"
          pure (fromInteger (product [1 .. toInteger actions]))
        [VWord 2, VBits _, VBits _] -> pure 3
        _ -> Left (Malformed "RETURN action domain differs")
      pure (ReturnDimensions controls (fromIntegral cases) (fromIntegral horizon))
    (NHerSchedule, [VRef spec, VRef cases]) -> do
      definition <- nodeAt pool spec
      case (Schema.nodeKind definition, Schema.nodeFields definition) of
        (NHerSpec, [_, VInt bits, VInt horizon, VInt count, _, _, _]) -> require (bits == 6 && horizon == 6 && count == 20) "HER header dimensions differ"
        _ -> Left (Malformed "HER spec shape differs")
      -- Reject a generic shared sequence's declared count before expanding
      -- occurrence references. The canonical HER schedule has exactly20.
      manifest <- nodeAt pool cases
      case (Schema.nodeKind manifest, Schema.nodeFields manifest) of
        (NSequenceManifest, [kind, VWord 20, _, _]) ->
          require (kind == Schema.elementKindValue (RefElement NHerGoalCase)) "HER case element kind differs"
        _ -> Left (Malformed "HER header case manifest must declare exactly20")
      values <- sequenceRefs pool cases
      require (length values == 20) "HER header must retain20 cases"
      mapM_
        ( \(ordinal, digest) -> do
            actual <- nodeAt pool digest
            case (Schema.nodeKind actual, Schema.nodeFields actual) of
              (NHerGoalCase, [VInt i, VRef tensor]) -> do
                require (i == fromIntegral ordinal) "HER header case order differs"
                goal <- nodeAt pool tensor
                case (Schema.nodeKind goal, Schema.nodeFields goal) of
                  (NTensorLeaf, [VWord n, VBytes raw]) -> require (n == 6 && BS.length raw == 48) "HER header goal width differs"
                  _ -> Left (Malformed "HER header goal is not a six-coordinate leaf")
              _ -> Left (Malformed "HER header case kind differs")
        )
        (zip [0 :: Int ..] values)
      pure HerDimensions
    ( NArenaSpec
      , [_, _, _, VInt actions, _, VInt horizon, _, VList [_, _, VWord games, VWord plies, _, VWord bytes]]
      ) -> do
        require
          ( actions > 0
              && actions <= 225
              && horizon > 0
              && horizon <= 225
              && games == 9
              && toInteger plies == toInteger horizon
              && bytes > 0
              && bytes <= 262144
          )
          "arena header dimensions exceed scope"
        pure (ArenaDimensions (fromIntegral actions) (fromIntegral horizon) (fromIntegral bytes))
    _ -> Left (Malformed "reference header root is not a supported spec/schedule")

sequenceRefs :: Graph.NodePool -> Digest -> Either CodecError [Digest]
sequenceRefs pool root = do
  node <- nodeAt pool root
  let field name =
        maybe
          (Left (Malformed "reference sequence field absent"))
          Right
          (lookup name (zip (Schema.nodeFieldNames (Schema.nodeKind node)) (Schema.nodeFields node)))
  case Schema.nodeKind node of
    NSequenceManifest -> field "children" >>= descend
    NSequenceIndex -> field "children" >>= descend
    NReferencePage -> field "elements" >>= refs
    _ -> Left (Malformed "reference schedule requires a reference sequence")
 where
  refs (VList values) =
    traverse
      ( \case
          VRef digest -> Right digest
          _ -> Left (Malformed "reference sequence has a non-reference")
      )
      values
  refs _ = Left (Malformed "reference sequence field is not an array")
  descend value = refs value >>= fmap concat . traverse (sequenceRefs pool)

-- A separate ordinary failure view, never an actual failure/capture capsule.
data NativeReferenceFailureData = NativeReferenceFailureData ![NodeValue] !ByteString
nativeReferenceFailureDataFields :: NativeReferenceFailureData -> [NodeValue]
nativeReferenceFailureDataFields (NativeReferenceFailureData fields _) = fields
nativeReferenceFailureDataBytes :: NativeReferenceFailureData -> ByteString
nativeReferenceFailureDataBytes (NativeReferenceFailureData _ bytes) = bytes

-- Keep the protocol's lowercase ASCII hex predicate.
{- HLINT ignore decodeNativeReferenceFailureData "Use isDigit" -}
decodeNativeReferenceFailureData :: ByteString -> Either CodecError NativeReferenceFailureData
decodeNativeReferenceFailureData bytes = do
  capBytes (2 * 1024 * 1024 + 4096) bytes
  fields <- Wire.runParser parse bytes
  require
    (Wire.encodeStrict (Wire.rawValueEncoding (VList fields)) == bytes)
    "noncanonical reference failure DATA"
  pure (NativeReferenceFailureData fields bytes)
 where
  parse = do
    Wire.expectList 6
    domain <- Wire.getText GeneralTextBytes 64
    Wire.liftEither
      (require (domain == "jitml-native-reference-failure-v1") "unknown reference failure domain")
    version <- Wire.getWord
    Wire.liftEither (require (version == 1) "unknown reference failure version")
    stage <- Wire.getWord
    Wire.liftEither (require (stage <= 2) "unknown reference capture stage")
    absent <- Wire.nextIsNull
    context <-
      if absent
        then Wire.getNull >> pure VNull
        else do
          Wire.expectList 2
          identity <- Wire.getText GeneralTextBytes 64
          transport <- Wire.getBytes WholePayloadBytes cohortCap
          Wire.liftEither
            ( require
                (Text.length identity == 64 && Text.all (\c -> c >= '0' && c <= '9' || c >= 'a' && c <= 'f') identity)
                "failure cohort ID differs"
            )
          Wire.liftEither (require (not (BS.null transport)) "failure cohort transport is absent")
          case UTF8.decodeUtf8' transport of
            Left _ -> Wire.parserFailure (Malformed "failure cohort is not UTF8")
            Right _ -> pure ()
          pure (VList [VText identity, VBytes transport])
    diagnostic <- parseDiagnostic
    work <- Wire.getText GeneralTextBytes 64
    Wire.liftEither
      (require (work == "unknown-failed-reference-work") "failed work is not explicitly Unknown")
    pure [VText domain, VWord version, VWord stage, context, diagnostic, VText work]
  parseDiagnostic = do
    count <- Wire.getListLength SequenceFanout 2
    tag <- Wire.getWord
    case (tag, count) of
      (0, 2) -> do
        detail <- Wire.getText DiagnosticTextBytes (nativePhaseLimit DiagnosticTextBytes)
        pure (VList [VWord 0, VText detail])
      (1, 2) -> do
        sizeCount <- Wire.getListLength SequenceFanout 2
        kind <- Wire.getWord
        size <- case (kind, sizeCount) of
          (0, 2) -> do n <- Wire.getWord; pure (VList [VWord 0, VWord n])
          (1, 2) -> do n <- Wire.getWord; pure (VList [VWord 1, VWord n])
          (2, 1) -> pure (VList [VWord 2])
          _ -> Wire.parserFailure (Malformed "reference diagnostic size knowledge differs")
        pure (VList [VWord 1, size])
      (2, 1) -> pure (VList [VWord 2])
      _ -> Wire.parserFailure (Malformed "unknown reference diagnostic/arity")
