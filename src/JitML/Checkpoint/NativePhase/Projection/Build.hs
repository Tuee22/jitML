{-# LANGUAGE OverloadedStrings #-}

-- | Private ordinary DATA construction. No initializer, continuation or IO
-- callback can be supplied to these pure operations. Allocation refusals are
-- conservative construction bounds, not claims about unique encoded size.
module JitML.Checkpoint.NativePhase.Projection.Build
  ( Build
  , ProjectionFailure (..)
  , ProjectionDiagnostic (..)
  , projectSafely
  , emit
  , tensor
  , listTensor
  , frameTensor
  , frameListTensor
  , referenceSequence
  , scalarSequence
  , scalarSequenceWith
  , intValue
  , wordValue
  , integerValue
  , textValue
  , bitValue
  , optional
  , dataEither
  ) where

import Control.Exception (SomeException, evaluate)
import Control.Exception.Safe (displayException, tryAny)
import Control.Monad.State.Strict (StateT, get, lift, put, runStateT)
import Data.Bits (shiftR)
import Data.ByteString qualified as BS
import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.Checkpoint.NativePhase.Builder qualified as Builder
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types

data ProjectionDiagnostic
  = ProjectionDiagnosticComplete !Text
  | ProjectionDiagnosticUnavailable
  deriving stock (Eq, Show)

data ProjectionFailure
  = ProjectionDataRejected !CodecError
  | ProjectionAllocationRefused !Resource !Integer !Integer
  | ProjectionSynchronousFailure !ProjectionDiagnostic
  deriving stock (Eq, Show)

data BuildState = BuildState
  { buildingPool :: Graph.NodePool
  , allocatedByteUpper :: !Integer
  , allocatedF64Upper :: !Integer
  , allocatedSequenceUpper :: !Integer
  }

type Build = StateT BuildState (Either ProjectionFailure)

dataEither :: Either CodecError a -> Build a
dataEither = either (lift . Left . ProjectionDataRejected) pure

reserve :: Resource -> Integer -> Build ()
reserve resource amount = do
  state <- get
  let current = case resource of
        WholePayloadBytes -> allocatedByteUpper state
        AggregateF64Coordinates -> allocatedF64Upper state
        AggregateSequenceElements -> allocatedSequenceUpper state
        _ -> 0
      requested = current + amount
      cap = nativePhaseLimit resource
  if amount < 0 || requested > cap
    then lift (Left (ProjectionAllocationRefused resource cap requested))
    else put $ case resource of
      WholePayloadBytes -> state {allocatedByteUpper = requested}
      AggregateF64Coordinates -> state {allocatedF64Upper = requested}
      AggregateSequenceElements -> state {allocatedSequenceUpper = requested}
      _ -> state

-- | Fixed-size node fields are refined before canonical bytes are retained.
-- Variable text is bounded by textValue and again by the actual field schema.
emit :: NodeKind -> [NodeValue] -> Build Digest
emit kind fields = do
  node <- dataEither (Schema.mkNodeData kind fields)
  reserve AggregateF64Coordinates (sum (map inlineBits fields))
  reserve WholePayloadBytes (toInteger (BS.length (Schema.nodeCanonicalBytes node)) + 64)
  state <- get
  (digest, pool) <- dataEither (Graph.internNode node (buildingPool state))
  put state {buildingPool = pool}
  pure digest
 where
  inlineBits (VBits _) = 1
  inlineBits (VList values) = sum (map inlineBits values)
  inlineBits _ = 0

-- | Length and cumulative construction charges precede the single strict byte
-- allocation. unfoldrN has bounded state and creates no8*n-element Word8 list.
tensor :: Vector Double -> Build Digest
tensor values = do
  let n = VU.length values
      bytes = 8 * toInteger n
      chunkCap = nativePhaseLimit TensorChunkBytes
      chunks = max 1 ((bytes + chunkCap - 1) `div` chunkCap)
      overhead = chunks * 128 + if chunks > 1 then 192 + chunks * 34 else 0
  dataEither (checkLimit WholePayloadBytes bytes)
  reserve AggregateF64Coordinates (toInteger n)
  reserve WholePayloadBytes (bytes + overhead)
  let byteCount = fromInteger bytes
      step offset
        | offset >= byteCount = Nothing
        | otherwise =
            let word = castDoubleToWord64 (values VU.! (offset `div` 8))
                shift = 8 * (7 - offset `mod` 8)
             in Just (fromIntegral (word `shiftR` shift), offset + 1)
      raw = fst (BS.unfoldrN byteCount step 0)
  state <- get
  (digest, pool) <- dataEither (Builder.internTensor raw (buildingPool state))
  put state {buildingPool = pool}
  pure digest

-- ARS exposes some actual vectors as lists. Bound the spine and bytes before
-- converting, and encode directly rather than allocating a replacement Vector.
listTensor :: [Double] -> Build Digest
listTensor values = do
  n <-
    dataEither (boundedLength AggregateF64Coordinates (nativePhaseLimit AggregateF64Coordinates) values)
  let bytes = 8 * toInteger n
      chunkCap = nativePhaseLimit TensorChunkBytes
      chunks = max 1 ((bytes + chunkCap - 1) `div` chunkCap)
      overhead = chunks * 128 + if chunks > 1 then 192 + chunks * 34 else 0
  dataEither (checkLimit WholePayloadBytes bytes)
  reserve AggregateF64Coordinates (toInteger n)
  reserve WholePayloadBytes (bytes + overhead)
  let step (remaining, offset) = case remaining of
        [] -> Nothing
        value : rest ->
          let word = castDoubleToWord64 value
              shift = 8 * (7 - offset)
              next = if offset == 7 then (rest, 0) else (remaining, offset + 1)
           in Just (fromIntegral (word `shiftR` shift), next)
      raw = fst (BS.unfoldrN (fromInteger bytes) step (values, 0 :: Int))
  state <- get
  (digest, pool) <- dataEither (Builder.internTensor raw (buildingPool state))
  put state {buildingPool = pool}
  pure digest

frameTensor :: Vector Double -> Build Digest
frameTensor values = do
  dataEither (checkLimit FrameBytes (8 * toInteger (VU.length values)))
  tensor values

frameListTensor :: [Double] -> Build Digest
frameListTensor values = do
  let cap = nativePhaseLimit FrameBytes
      counted = boundedLength FrameBytes (cap `div` 8) values
  case counted of
    Left (ResourceExceeded _ _ observedCoordinates) ->
      dataEither (Left (ResourceExceeded FrameBytes cap (8 * observedCoordinates)))
    Left failure -> dataEither (Left failure)
    Right _ -> listTensor values

sequenceCharge :: Int -> Bool -> Build ()
sequenceCharge n referenced = do
  reserve AggregateSequenceElements (toInteger n)
  let leaves = (toInteger n + 255) `div` 256
      indexes = if leaves > 256 then (leaves + 255) `div` 256 else 0
      edges = leaves + indexes + if referenced then toInteger n else 0
  reserve WholePayloadBytes ((1 + leaves + indexes) * 192 + edges * 34)

-- | First bound the supplied spine, before traversing any element or building
-- its output list. The per-sequence cap also bounds a cyclic/infinite spine.
referenceSequence :: ElementKind -> (a -> Build Digest) -> [a] -> Build Digest
referenceSequence kind observe values = do
  n <- dataEither (boundedLength PerSequenceElements (nativePhaseLimit PerSequenceElements) values)
  sequenceCharge n True
  refs <- traverse (fmap VRef . observe) values
  state <- get
  (digest, pool) <- dataEither (Builder.internSequence kind refs (buildingPool state))
  put state {buildingPool = pool}
  pure digest

-- | Scalar elements remain lazy until the bounded page builder consumes them;
-- no complete additional scalar/vector array is materialized by this adapter.
scalarSequence :: ScalarKind -> [NodeValue] -> Build Digest
scalarSequence kind values = do
  n <- dataEither (boundedLength PerSequenceElements (nativePhaseLimit PerSequenceElements) values)
  scalarCharge kind n
  writeScalarSequence kind values

scalarSequenceWith :: ScalarKind -> (a -> Build NodeValue) -> [a] -> Build Digest
scalarSequenceWith kind observe values = do
  n <- dataEither (boundedLength PerSequenceElements (nativePhaseLimit PerSequenceElements) values)
  scalarCharge kind n
  observed <- traverse observe values
  writeScalarSequence kind observed

scalarCharge :: ScalarKind -> Int -> Build ()
scalarCharge kind n = do
  sequenceCharge n False
  let elementUpper = case kind of
        ScalarCountTriple -> 28
        ScalarSlotSummary -> 28
        ScalarBool -> 1
        _ -> 9
      floatUpper = case kind of
        ScalarBits -> toInteger n
        ScalarSlotSummary -> toInteger n
        _ -> 0
  reserve WholePayloadBytes (toInteger n * elementUpper)
  reserve AggregateF64Coordinates floatUpper

writeScalarSequence :: ScalarKind -> [NodeValue] -> Build Digest
writeScalarSequence kind values = do
  state <- get
  (digest, pool) <-
    dataEither (Builder.internSequence (ScalarElement kind) values (buildingPool state))
  put state {buildingPool = pool}
  pure digest

intValue :: Int -> Build NodeValue
intValue value
  | toInteger value < toInteger (minBound :: Int64) || toInteger value > toInteger (maxBound :: Int64) =
      dataEither (Left (Malformed "source Int is outside signed64"))
  | otherwise = pure (VInt (fromIntegral value))

wordValue :: Int -> Build NodeValue
wordValue value
  | value < 0 || toInteger value > toInteger (maxBound :: Word64) =
      dataEither (Left (Malformed "source Int is outside unsigned64"))
  | otherwise = pure (VWord (fromIntegral value))

integerValue :: Integer -> Build NodeValue
integerValue = dataEither . Schema.magnitudeValue

textValue :: Resource -> Text -> Build NodeValue
textValue resource value = do
  -- A strict Text has a finite backing array. UTF8 may use4 bytes per scalar;
  -- check character count first so even a refused encode allocates at most4cap.
  dataEither (checkLimit resource (toInteger (Text.length value)))
  let bytes = BS.length (TextEncoding.encodeUtf8 value)
  dataEither (checkLimit resource (toInteger bytes))
  pure (VText value)

bitValue :: Double -> NodeValue
bitValue = VBits . castDoubleToWord64

optional :: (a -> Build Digest) -> Maybe a -> Build NodeValue
optional _ Nothing = pure VNull
optional observe (Just value) = VRef <$> observe value

-- | The root closure is validated/pruned only as a temporary DATA view. The
-- complete supplied pool is retained for parent composition with sibling data;
-- unrelated roots cannot make this subtree fail phase reachability/size.
projectSafely
  :: Graph.NodePool
  -> Build Digest
  -> IO (Either ProjectionFailure (Digest, Graph.NodePool))
projectSafely pool action = do
  attempted <- tryAny (evaluate materialized)
  case attempted of
    Left exception -> Left . ProjectionSynchronousFailure <$> exceptionDiagnostic exception
    Right value -> pure value
 where
  materialized = case runStateT action (BuildState pool 0 0 0) of
    Left failure -> forceFailure failure `seq` Left failure
    Right (root, state) ->
      case Graph.reachableNodePool [root] (buildingPool state) of
        Left failure -> forceCodecError failure `seq` Left (ProjectionDataRejected failure)
        Right closure -> case Graph.validateReachableData [root] closure of
          Left failure -> forceCodecError failure `seq` Left (ProjectionDataRejected failure)
          Right usage ->
            forcePool closure `seq`
              forceUsage usage `seq`
                BS.length (digestBytes root) `seq`
                  Right (root, buildingPool state)

forcePool :: Graph.NodePool -> ()
forcePool =
  foldr
    (\(digest, _, bytes) rest -> BS.length (digestBytes digest) `seq` BS.length bytes `seq` rest)
    ()
    . Graph.nodePoolEntries

forceUsage :: GraphUsage -> ()
forceUsage value =
  usageNodes value `seq`
    usageEdges value `seq`
      usageSequenceElements value `seq`
        usageF64Coordinates value `seq`
          usageReferenceDepth value `seq`
            usageEncodedBytes value `seq`
              ()

forceCodecError :: CodecError -> ()
forceCodecError value = case value of
  Malformed detail -> Text.length detail `seq` ()
  NonCanonical detail -> Text.length detail `seq` ()
  ResourceExceeded resource cap observed -> resource `seq` cap `seq` observed `seq` ()
  UnexpectedEnd offset -> offset `seq` ()
  MissingReference digest -> BS.length (digestBytes digest) `seq` ()
  WrongReferenceType digest detail -> BS.length (digestBytes digest) `seq` Text.length detail `seq` ()
  HashMismatch digest -> BS.length (digestBytes digest) `seq` ()
  DigestCollision digest -> BS.length (digestBytes digest) `seq` ()
  ReferenceCycle digest -> BS.length (digestBytes digest) `seq` ()
  UnreachablePoolMember digest -> BS.length (digestBytes digest) `seq` ()

forceFailure :: ProjectionFailure -> ()
forceFailure failure = case failure of
  ProjectionDataRejected problem -> forceCodecError problem
  ProjectionAllocationRefused resource cap amount -> resource `seq` cap `seq` amount `seq` ()
  ProjectionSynchronousFailure diagnostic -> case diagnostic of
    ProjectionDiagnosticComplete detail -> Text.length detail `seq` ()
    ProjectionDiagnosticUnavailable -> ()

-- No truncated prefix is labelled the complete exception diagnostic. Any
-- formatting fault/oversize is explicit absence, and safe tryAny propagates
-- async exceptions both in the original projection and its formatter.
exceptionDiagnostic :: SomeException -> IO ProjectionDiagnostic
exceptionDiagnostic exception = do
  rendered <- tryAny (evaluate bounded)
  pure $ case rendered of
    Right (Just detail) -> ProjectionDiagnosticComplete detail
    _ -> ProjectionDiagnosticUnavailable
 where
  cap = nativePhaseLimit DiagnosticTextBytes
  bounded =
    let chars = take (fromInteger cap + 1) (displayException exception)
     in if toInteger (length chars) > cap
          then Nothing
          else
            let value = Text.pack chars
             in if toInteger (BS.length (TextEncoding.encodeUtf8 value)) > cap
                  then Nothing
                  else Text.length value `seq` Just value
