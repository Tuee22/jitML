{-# LANGUAGE OverloadedStrings #-}

-- | Closed schema refinement of ordinary recorded DATA. It deliberately does
-- not reconstruct checked source plans/specs, random engines or capabilities.
module JitML.Checkpoint.NativePhase.Schema
  ( NodeData
  , mkNodeData
  , nodeKind
  , nodeFields
  , nodeFieldNames
  , nodeCanonicalBytes
  , decodeNodeData
  , nodeReferences
  , nodeLocalUsage
  , ContextData
  , mkContextData
  , contextFields
  , contextCanonicalBytes
  , contextReferences
  , parseContextData
  , elementKindValue
  , readElementKind
  , magnitudeValue
  , readMagnitude
  , validateValue
  , parseValue
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Control.Monad (unless, when, zipWithM, zipWithM_)
import Data.Bits (shiftL, shiftR, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (ord)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.SchemaTable
import JitML.Checkpoint.NativePhase.Types

data NodeData = NodeData !NodeKind ![NodeValue]
  deriving stock (Eq, Show)

nodeKind :: NodeData -> NodeKind
nodeKind (NodeData value _) = value

nodeFields :: NodeData -> [NodeValue]
nodeFields (NodeData _ values) = values

nodeFieldNames :: NodeKind -> [Text]
nodeFieldNames = fmap fst . fieldTypes

-- Ordinary schema DATA only; no public record labels permit refining by update.
-- Preserve the strict constructor boundary; newtype changes bottom semantics.
{- HLINT ignore ContextData "Use newtype instead of data" -}
data ContextData = ContextData ![NodeValue]
  deriving stock (Eq, Show)

contextFields :: ContextData -> [NodeValue]
contextFields (ContextData values) = values

elementKindValue :: ElementKind -> NodeValue
elementKindValue kind = case kind of
  RefElement value -> VList [VWord 0, VWord (nodeTag value)]
  ScalarElement value -> VList [VWord 1, VWord (scalarTag value)]
  AliasElement value -> VList [VWord 2, VWord (aliasTag value)]

readElementKind :: NodeValue -> Either CodecError ElementKind
readElementKind value = do
  kind <- case value of
    VList [VWord 0, VWord tag] -> RefElement <$> nodeKindFromTag tag
    VList [VWord 1, VWord tag] -> ScalarElement <$> scalarFromTag tag
    VList [VWord 2, VWord tag] -> AliasElement <$> aliasFromTag tag
    _ -> Left (Malformed "invalid closed element kind")
  unless
    (kind `elem` sequenceElementKinds)
    (Left (Malformed "sequence element kind is absent from the closed schema"))
  pure kind

magnitudeValue :: Integer -> Either CodecError NodeValue
magnitudeValue value
  | abs value > (2 ^ (256 :: Int)) - 1 = Left (Malformed "integer magnitude exceeds32 bytes")
  | otherwise =
      let bytes = BS.reverse (BS.unfoldr step (abs value))
          sign = if value < 0 then 1 else 0
       in Right (VList [VWord sign, VBytes bytes])
 where
  step 0 = Nothing
  step n = Just (fromInteger (n .&. 255), n `shiftR` 8)

readMagnitude :: NodeValue -> Either CodecError Integer
readMagnitude value = do
  validateValue TMagnitude value
  case value of
    VList [VWord sign, VBytes bytes] ->
      let n = BS.foldl' (\acc byte -> (acc `shiftL` 8) .|. toInteger byte) 0 bytes
       in Right (if sign == 0 then n else -n)
    _ -> Left (Malformed "invalid magnitude integer")

named :: Text -> Either CodecError FieldType
named name = maybe (Left (Malformed "unknown frozen field type")) Right (namedType name)

exactLength :: Int -> [a] -> Either CodecError ()
exactLength expected values = do
  count <- boundedLength SequenceFanout (toInteger expected) values
  unless (count == expected) (Left (Malformed "wrong fixed field arity"))

textBound :: Resource -> Integer -> Text -> Either CodecError ()
textBound resource cap text = do
  -- Bound before producing an encoded buffer. Text's current buffer is supplied
  -- data; at most cap characters are traversed by the UTF8-size fold below.
  when
    (toInteger (Text.length text) > cap)
    (Left (ResourceExceeded resource cap (toInteger (Text.length text))))
  let size = Text.foldl' (\n char -> n + utf8Width (ord char)) 0 text
  when (size > cap) (Left (ResourceExceeded resource cap size))
  let bytes = UTF8.encodeUtf8 text
  case UTF8.decodeUtf8' bytes of
    Right decoded | decoded == text -> Right ()
    _ -> Left (Malformed "text UTF8 roundtrip differs")
 where
  utf8Width n
    | n < 128 = 1
    | n < 2048 = 2
    | n < 65536 = 3
    | otherwise = 4

validateValue :: FieldType -> NodeValue -> Either CodecError ()
validateValue spec value = case (spec, value) of
  (TNamed name, _) -> named name >>= (`validateValue` value)
  (TWord, VWord _) -> Right ()
  (TInt, VInt _) -> Right ()
  (TBits, VBits _) -> Right ()
  (TBool, VBool _) -> Right ()
  (TDigest, VDigest _) -> Right ()
  (TText resource cap, VText text) -> textBound resource cap text
  (TBytes resource cap, VBytes bytes) ->
    when
      (toInteger (BS.length bytes) > cap)
      (Left (ResourceExceeded resource cap (toInteger (BS.length bytes))))
  (TExactWord expected, VWord actual) -> unless (expected == actual) (Left (Malformed "wrong fixed scalar"))
  (TExactText expected, VText actual) ->
    textBound ProducerComponentBytes 256 actual
      >> unless (expected == actual) (Left (Malformed "wrong representation literal"))
  (TEnum allowed, VWord actual) -> unless (actual `elem` allowed) (Left (Malformed "unknown closed enum"))
  (TReference _, VRef _) -> Right ()
  (TOptional _, VNull) -> Right ()
  (TOptional inner, _) -> validateValue inner value
  (TTuple fields, VList values) -> exactLength (length fields) values >> zipWithM_ validateValue fields values
  (TSum choices, VList (VWord tag : values)) -> do
    fields <- maybe (Left (Malformed "unknown inline sum tag")) Right (lookup tag choices)
    exactLength (length fields) values
    zipWithM_ validateValue fields values
  (TArray inner, VList values) -> do
    _ <- boundedLength SequenceFanout (nativePhaseLimit SequenceFanout) values
    mapM_ (validateValue inner) values
  (TElementKind, _) -> readElementKind value >> Right ()
  (TMagnitude, VList [VWord sign, VBytes bytes]) -> do
    checkLimit IntegerMagnitudeBytes (toInteger (BS.length bytes))
    unless
      (sign <= 1 && (BS.null bytes && sign == 0 || not (BS.null bytes) && BS.index bytes 0 /= 0))
      (Left (NonCanonical "integer negativezero/sign/leadingzero"))
  _ -> Left (Malformed "field has wrong closed wire type")

parseValue :: FieldType -> Wire.Parser NodeValue
parseValue spec = case spec of
  TNamed name -> Wire.liftEither (named name) >>= parseValue
  TWord -> VWord <$> Wire.getWord
  TInt -> VInt <$> Wire.getInt64
  TBits -> VBits <$> Wire.getBits
  TBool -> VBool <$> Wire.getBool
  TDigest -> VDigest <$> Wire.getDigest
  TText resource cap -> VText <$> Wire.getText resource cap
  TBytes resource cap -> VBytes <$> Wire.getBytes resource cap
  TExactWord _expected -> checked spec . VWord =<< Wire.getWord
  TExactText _ -> checked spec . VText =<< Wire.getText ProducerComponentBytes 256
  TEnum _ -> checked spec . VWord =<< Wire.getWord
  TReference _ -> VRef <$> Wire.getDigest
  TOptional inner -> do
    absent <- Wire.nextIsNull
    if absent then Wire.getNull >> pure VNull else parseValue inner
  TTuple fields -> Wire.expectList (length fields) >> VList <$> mapM parseValue fields
  TSum choices -> do
    actual <- Wire.getListLength SequenceFanout 32
    when (actual == 0) (Wire.parserFailure (Malformed "inline sum is empty"))
    tag <- Wire.getWord
    fields <- maybe (Wire.parserFailure (Malformed "unknown inline sum tag")) pure (lookup tag choices)
    unless (actual == length fields + 1) (Wire.parserFailure (Malformed "inline sum arity differs"))
    values <- mapM parseValue fields
    pure (VList (VWord tag : values))
  TArray inner -> do
    count <- Wire.getListLength SequenceFanout (nativePhaseLimit SequenceFanout)
    VList <$> parseMany count (parseValue inner)
  TElementKind -> do
    Wire.expectList 2
    tag <- Wire.getWord
    value <- Wire.getWord
    checked TElementKind (VList [VWord tag, VWord value])
  TMagnitude -> do
    Wire.expectList 2
    sign <- Wire.getWord
    bytes <- Wire.getBytes IntegerMagnitudeBytes (nativePhaseLimit IntegerMagnitudeBytes)
    checked TMagnitude (VList [VWord sign, VBytes bytes])
  _ -> Wire.parserFailure (Malformed "unresolved dynamic page field")
 where
  checked kind value = Wire.liftEither (validateValue kind value) >> pure value

parseMany :: Int -> Wire.Parser a -> Wire.Parser [a]
parseMany count action = go count []
 where
  go 0 acc = pure (reverse acc)
  go remaining acc = do
    value <- action
    go (remaining - 1) (value : acc)

resolveDynamic :: [NodeValue] -> FieldType -> Either CodecError FieldType
resolveDynamic prefix spec = case spec of
  TDynamicRefs -> do
    element <- firstElement prefix
    TArray . TReference <$> elementTarget element
  TDynamicScalars -> do
    element <- firstElement prefix
    case element of
      ScalarElement kind -> Right (TArray (scalarType kind))
      _ -> Left (Malformed "scalar page has reference element kind")
  _ -> Right spec
 where
  firstElement values = case values of
    first : _ -> readElementKind first
    _ -> Left (Malformed "dynamic page missing element kind")

resolvedFields :: NodeKind -> [NodeValue] -> Either CodecError [FieldType]
resolvedFields kind values = mapM (resolveDynamic values . snd) (fieldTypes kind)

mkNodeData :: NodeKind -> [NodeValue] -> Either CodecError NodeData
mkNodeData kind values = do
  exactLength (length (fieldTypes kind)) values
  specs <- resolvedFields kind values
  zipWithM_ validateValue specs values
  validateLocal kind values
  pure (NodeData kind values)

nodeCanonicalBytes :: NodeData -> ByteString
nodeCanonicalBytes (NodeData kind values) =
  Wire.encodeStrict
    ( CBOR.encodeListLen (fromIntegral (length values + 1))
        <> CBOR.encodeWord64 (nodeTag kind)
        <> foldMap Wire.rawValueEncoding values
    )

decodeNodeData :: ByteString -> Either CodecError NodeData
decodeNodeData bytes = do
  node <- Wire.runParser parser bytes
  unless
    (nodeCanonicalBytes node == bytes)
    (Left (NonCanonical "node bytes differ from canonical encoder"))
  pure node
 where
  parser = do
    count <- Wire.getListLength SequenceFanout 29
    when (count == 0) (Wire.parserFailure (Malformed "node array is empty"))
    kind <- Wire.getWord >>= Wire.liftEither . nodeKindFromTag
    let fields = fieldTypes kind
    unless (count == length fields + 1) (Wire.parserFailure (Malformed "node tag arity mismatch"))
    values <- parseFields [] fields
    Wire.liftEither (mkNodeData kind values)
  parseFields acc [] = pure (reverse acc)
  parseFields acc ((_, spec) : rest) = do
    resolved <- Wire.liftEither (resolveDynamic (reverse acc) spec)
    value <- parseValue resolved
    parseFields (value : acc) rest

mkContextData :: [NodeValue] -> Either CodecError ContextData
mkContextData values = do
  exactLength 16 values
  zipWithM_ validateValue (fmap snd contextTypes) values
  let context = ContextData values
  checkLimit ContextBytes (toInteger (BS.length (contextCanonicalBytes context)))
  pure context

contextCanonicalBytes :: ContextData -> ByteString
contextCanonicalBytes (ContextData values) = Wire.encodeStrict (Wire.rawValueEncoding (VList values))

parseContextData :: Wire.Parser ContextData
parseContextData = Wire.withinSpan ContextBytes $ do
  Wire.expectList 16
  values <- mapM (parseValue . snd) contextTypes
  Wire.liftEither (mkContextData values)

collectReferences :: FieldType -> NodeValue -> Either CodecError [(ReferenceTarget, Digest)]
collectReferences spec value = case (spec, value) of
  (TNamed name, _) -> named name >>= (`collectReferences` value)
  (TReference target, VRef digest) -> Right [(target, digest)]
  (TOptional _, VNull) -> Right []
  (TOptional inner, _) -> collectReferences inner value
  (TTuple fields, VList values) -> concat <$> zipWithM collectReferences fields values
  (TSum choices, VList (VWord tag : values)) -> do
    fields <- maybe (Left (Malformed "unknown inline ref sum")) Right (lookup tag choices)
    concat <$> zipWithM collectReferences fields values
  (TArray inner, VList values) -> concat <$> mapM (collectReferences inner) values
  _ -> Right []

nodeReferences :: NodeData -> Either CodecError [(ReferenceTarget, Digest)]
nodeReferences (NodeData kind values) = do
  specs <- resolvedFields kind values
  concat <$> zipWithM collectReferences specs values

contextReferences :: ContextData -> Either CodecError [(ReferenceTarget, Digest)]
contextReferences (ContextData values) = concat <$> zipWithM collectReferences (fmap snd contextTypes) values

nodeLocalUsage :: NodeData -> Either CodecError GraphUsage
nodeLocalUsage node@(NodeData kind values) = do
  refs <- nodeReferences node
  let tensorCoordinates = case (kind, values) of
        (NTensorLeaf, [_, VBytes bytes]) -> toInteger (BS.length bytes `div` 8)
        (NTensorChunk, [_, VBytes bytes]) -> toInteger (BS.length bytes `div` 8)
        _ -> 0
      sequenceElements = case (kind, values) of
        (NSequenceManifest, [_, VWord count, _, _]) -> toInteger count
        _ -> 0
      bits value = case value of
        VBits _ -> 1
        VList nested -> sum (fmap bits nested)
        _ -> 0
  pure
    ( GraphUsage
        1
        (toInteger (length refs))
        sequenceElements
        (tensorCoordinates + sum (fmap bits values))
        0
        (toInteger (BS.length (nodeCanonicalBytes node)))
    )

validateLocal :: NodeKind -> [NodeValue] -> Either CodecError ()
validateLocal kind values = case (kind, values) of
  (NTensorLeaf, [VWord count, VBytes bytes]) ->
    unless
      (BS.length bytes `mod` 8 == 0 && toInteger count * 8 == toInteger (BS.length bytes))
      (Left (Malformed "tensor leaf coordinate/byte counts differ"))
  (NTensorChunk, [_, VBytes bytes]) ->
    unless
      (not (BS.null bytes) && BS.length bytes `mod` 8 == 0)
      (Left (NonCanonical "empty or partial tensor chunk"))
  (NTensorManifest, [VWord count, VWord bytes, VList children]) -> do
    unless
      ( toInteger count * 8 == toInteger bytes
          && toInteger bytes > nativePhaseLimit TensorChunkBytes
          && not (null children)
      )
      (Left (NonCanonical "tensor manifest must describe a large nonempty tensor"))
    unless
      (toInteger (length children) == ceilingDivide (toInteger bytes) (nativePhaseLimit TensorChunkBytes))
      (Left (NonCanonical "tensor manifest chunk count differs"))
  (NSequenceManifest, [_, VWord count, VWord height, VList children]) -> do
    checkLimit PerSequenceElements (toInteger count)
    let expectedHeight
          | count == 0 = 0
          | count <= 65536 = 1
          | otherwise = 2
        capacity = if height == 2 then 65536 else 256
    unless
      (height == expectedHeight && toInteger (length children) == ceilingDivide (toInteger count) capacity)
      (Left (NonCanonical "sequence root height/count/fanout differs"))
  (NSequenceIndex, [_, _, VWord count, VList children]) ->
    unless
      (count > 0 && count <= 65536 && toInteger (length children) == ceilingDivide (toInteger count) 256)
      (Left (NonCanonical "sequence index count/fanout differs"))
  (NReferencePage, [_, VWord count, VList elements]) -> pageCount count elements
  (NScalarPage, [_, VWord count, VList elements]) -> pageCount count elements
  ( NSafeFailure
    , [ VWord family
        , stage
        , failureKind
        , diagnostic
        , _
        , _
        , VList coverage
        , snapshot
        , cold
        , raw
        , initial
        , current
        , low
        ]
    ) -> do
      let payloads = [snapshot, cold, raw, initial, current, low]
          present item = case item of VNull -> False; _ -> True
          exactly item = case item of VList [VWord 0] -> True; _ -> False
      unless
        (and (zipWith (\coverageItem payload -> exactly coverageItem == present payload) coverage payloads))
        (Left (Malformed "failure payload coverage differs from optional refs"))
      let category
            | family <= 4 = 0
            | family == 5 = 1
            | otherwise = 2
          categoryMatches item = case item of
            VList [VWord 0, VList (VWord observed : _)] -> observed == category
            _ -> True
      unless
        (categoryMatches stage && categoryMatches failureKind)
        (Left (Malformed "failure family/stage or kind disagree"))
      let diagnosticBytes = case diagnostic of
            VList [VWord 0, VText text] -> toInteger (BS.length (UTF8.encodeUtf8 text))
            _ -> 0
          headerBytes = toInteger (BS.length (nodeCanonicalBytes (NodeData kind values))) - diagnosticBytes
      unless
        (headerBytes <= nativePhaseSafeFailureHeaderBytes)
        (Left (Malformed "SafeFailure scalar/reference header exceeds8192 bytes"))
  _ -> Right ()
 where
  ceilingDivide 0 _ = 0
  ceilingDivide numerator denominator = (numerator + denominator - 1) `div` denominator
  pageCount count elements =
    unless
      (count > 0 && count <= 256 && toInteger count == toInteger (length elements))
      (Left (NonCanonical "sequence page count differs"))
