{-# LANGUAGE OverloadedStrings #-}

-- | Bounded ordinary graph reads. No execution state or capability is restored.
module JitML.Checkpoint.NativeParentPolicyData.Node
  ( Decode
  , runDecode
  , reject
  , require
  , liftData
  , fields
  , ref
  , int
  , word
  , bits
  , bool
  , text
  , magnitude
  , sequenceData
  , referenceData
  , tensor
  , parameters
  , gameState
  , outcome
  , tapeEntry
  , poolFromEntries
  , closureEntries
  ) where

import Control.Monad (foldM, unless)
import Control.Monad.State.Strict (StateT, evalStateT, get, gets, lift, modify')
import Data.Bits (shiftL, (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)

import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape

data State
  = State
      !Graph.NodePool
      !(Map.Map Digest (VU.Vector Double))
      !(Map.Map Digest Mlp.MlpParams)
type Decode = StateT State (Either CodecError)

runDecode :: Graph.NodePool -> Decode a -> Either CodecError a
runDecode pool action = evalStateT action (State pool Map.empty Map.empty)
liftData :: Either CodecError a -> Decode a
liftData = lift
reject :: Text -> Decode a
reject = lift . Left . Malformed
require :: Bool -> Text -> Decode ()
require condition message = unless condition (reject message)

fields :: NodeKind -> Digest -> Decode [NodeValue]
fields kind digest = do
  pool <- gets (\(State actual _ _) -> actual)
  node <- maybe (liftData (Left (MissingReference digest))) pure (Graph.lookupNode digest pool)
  require (Schema.nodeKind node == kind) "parent DATA node has an unexpected typed kind"
  pure (Schema.nodeFields node)
ref :: NodeValue -> Decode Digest
ref (VRef actual) = pure actual
ref _ = reject "parent DATA expected a typed reference"
int :: NodeValue -> Decode Int
int (VInt actual) = do
  require
    (toInteger actual >= toInteger (minBound :: Int) && toInteger actual <= toInteger (maxBound :: Int))
    "parent signed integer exceeds this host Int"
  pure (fromIntegral actual)
int _ = reject "parent DATA expected SInt64"
word :: NodeValue -> Decode Word64
word (VWord actual) = pure actual
word _ = reject "parent DATA expected Word64"
bits :: NodeValue -> Decode Double
bits (VBits actual) = pure (castWord64ToDouble actual)
bits _ = reject "parent DATA expected exact F64 bits"
bool :: NodeValue -> Decode Bool
bool (VBool actual) = pure actual
bool _ = reject "parent DATA expected Bool"
text :: NodeValue -> Decode Text
text (VText actual) = pure actual
text _ = reject "parent DATA expected Text"
magnitude :: NodeValue -> Decode Integer
magnitude = liftData . Schema.readMagnitude

-- Count/type refusal precedes occurrence expansion, including shared DAGs.
sequenceData :: ElementKind -> Integer -> Digest -> Decode [NodeValue]
sequenceData expected cap digest = do
  actual <- fields NSequenceManifest digest
  case actual of
    [kind, VWord count, VWord height, VList children] -> do
      require
        (kind == Schema.elementKindValue expected && toInteger count <= cap)
        "parent sequence type or declared count exceeds its semantic field bound"
      require
        ((count == 0 && height == 0 && null children) || (count > 0 && height >= 1 && height <= 2))
        "parent sequence height/empty declaration differs"
      values <- concat <$> traverse (descend (height - 1)) children
      require
        (toInteger (length values) == toInteger count)
        "parent sequence expanded cardinality differs"
      pure values
    _ -> reject "parent sequence manifest fields differ"
 where
  descend 0 value = do
    digest_ <- ref value
    let pageKind = case expected of ScalarElement _ -> NScalarPage; _ -> NReferencePage
    page <- fields pageKind digest_
    case page of
      [kind, VWord count, VList values] -> do
        require
          ( kind == Schema.elementKindValue expected
              && count <= 256
              && toInteger count == toInteger (length values)
          )
          "parent sequence page type/count differs"
        pure values
      _ -> reject "parent sequence page fields differ"
  descend 1 value = do
    digest_ <- ref value
    index <- fields NSequenceIndex digest_
    case index of
      [kind, VWord 1, VWord count, VList children] -> do
        require
          (kind == Schema.elementKindValue expected && count <= 65536)
          "parent sequence index type/count differs"
        values <- concat <$> traverse (descend 0) children
        require (toInteger (length values) == toInteger count) "parent sequence index count differs"
        pure values
      _ -> reject "parent sequence index fields differ"
  descend _ _ = reject "parent sequence height exceeds the closed grammar"

referenceData :: ElementKind -> Integer -> Digest -> Decode [Digest]
referenceData kind cap digest = sequenceData kind cap digest >>= traverse ref

tensor :: Integer -> Digest -> Decode (VU.Vector Double)
tensor cap digest = do
  State pool cache _ <- get
  case Map.lookup digest cache of
    Just values -> do
      require (toInteger (VU.length values) <= cap) "parent cached tensor exceeds semantic bound"
      pure values
    Nothing -> do
      node <- maybe (liftData (Left (MissingReference digest))) pure (Graph.lookupNode digest pool)
      (count, parts) <- case (Schema.nodeKind node, Schema.nodeFields node) of
        (NTensorLeaf, [VWord count, VBytes raw]) -> pure (count, [raw])
        (NTensorManifest, [VWord count, VWord total, VList chunks]) -> do
          require
            (toInteger count <= cap && toInteger total == 8 * toInteger count)
            "parent tensor declared width/bytes exceeds semantic bound"
          raw <-
            traverse
              ( \(ordinal, value) -> do
                  chunk <- ref value >>= fields NTensorChunk
                  case chunk of
                    [VWord actual, VBytes bytes_] | actual == ordinal -> pure bytes_
                    _ -> reject "parent tensor chunk ordinal/fields differ"
              )
              (zip [0 ..] chunks)
          pure (count, raw)
        _ -> reject "parent tensor kind/fields differ"
      require
        (toInteger count <= cap && 8 * toInteger count <= toInteger (maxBound :: Int))
        "parent tensor allocation bound exceeded"
      require
        (sum (map (toInteger . BS.length) parts) == 8 * toInteger count)
        "parent tensor actual byte count differs"
      let raw = BS.concat parts
          n = fromIntegral count
          at i =
            castWord64ToDouble
              (BS.foldl' (\a b -> (a `shiftL` 8) .|. fromIntegral b) 0 (BS.take 8 (BS.drop (8 * i) raw)))
          values = VU.generate n at
      VU.length values `seq` modify' (\(State p t m) -> State p (Map.insert digest values t) m)
      pure values

parameters :: Digest -> Decode Mlp.MlpParams
parameters digest = do
  cached <- gets (\(State _ _ cache) -> Map.lookup digest cache)
  case cached of
    Just actual -> pure actual
    Nothing -> do
      actual <- fields NParams digest
      case actual of
        [VList [a, b, c], w1, b1, w2, b2] -> do
          inputs <- int a
          hidden <- int b
          outputs <- int c
          let sizes =
                [ toInteger inputs * toInteger hidden
                , toInteger hidden
                , toInteger hidden * toInteger outputs
                , toInteger outputs
                ]
          require
            (inputs > 0 && hidden > 0 && outputs > 0 && all (<= nativePhaseLimit AggregateF64Coordinates) sizes)
            "parent MLP shape is nonpositive or exceeds the declared F64 bound"
          tensors <-
            traverse
              ( \(size, value) -> do
                  vector <- ref value >>= tensor size
                  require
                    (toInteger (VU.length vector) == size)
                    "parent MLP tensor width differs from its exact shape"
                  pure vector
              )
              (zip sizes [w1, b1, w2, b2])
          case tensors of
            [v1, v2, v3, v4] -> do
              let value = Mlp.MlpParams (Mlp.MlpShape inputs hidden outputs) v1 v2 v3 v4
              modify' (\(State p t m) -> State p t (Map.insert digest value m))
              pure value
            _ -> reject "parent MLP internal tensor inventory differs"
        _ -> reject "parent MLP fields differ"

gameState :: Digest -> Decode Game.GameState
gameState digest = do
  actual <- fields NGameState digest
  case actual of
    [game, moves, current] -> do
      name <- text game
      require
        (name `elem` ["connect4", "othello", "hex", "gomoku"])
        "parent game key is outside the canonical four"
      history <-
        ref moves
          >>= sequenceData (ScalarElement ScalarInt) (2 * toInteger (Game.maxPliesFor name) + 1)
          >>= traverse int
      player <- int current
      require (player == 1 || player == -1) "parent game current player is invalid"
      pure (Game.GameState name history player)
    _ -> reject "parent game fields differ"
outcome :: NodeValue -> Decode Game.GameOutcome
outcome (VList [VWord 0]) = pure Game.GameInProgress
outcome (VList [VWord 1]) = pure Game.GameDraw
outcome (VList [VWord 2, player]) = do
  value <- int player
  require (value == 1 || value == -1) "parent winner is invalid"
  pure (Game.GameWon value)
outcome _ = reject "parent game outcome fields differ"

-- Private entry constructors are not restored: lookup the exact retained tape
-- and compare every ordinary field, including the raw unit bits.
tapeEntry :: Tape.ArenaTape -> Digest -> Decode Tape.ArenaTapeEntry
tapeEntry tape digest = do
  actual <- fields NTapeEntry digest
  case actual of
    [g, s, p, side, q, VBits unit, seed] -> do
      game <- word g
      slot <- word s
      player <- int p
      entry <-
        either
          (const (reject "parent tape address is invalid"))
          pure
          (Tape.arenaTapeLookup tape game slot player)
      side_ <- word side
      q_ <- word q
      seed_ <- int seed
      require
        ( side_ == Tape.arenaEntrySideCode entry
            && q_ == Tape.arenaEntryQ entry
            && unit == castDoubleToWord64 (Tape.arenaEntryUnit entry)
            && seed_ == Tape.arenaEntryMctsSeed entry
        )
        "parent addressed tape entry differs from its full retained tape"
      pure entry
    _ -> reject "parent tape entry fields differ"

poolFromEntries :: [(Digest, ByteString)] -> Either CodecError Graph.NodePool
poolFromEntries = foldM one Graph.emptyNodePool
 where
  one pool (expected, bytes_) = do
    node <- Schema.decodeNodeData bytes_
    (actual, next) <- Graph.internNode node pool
    unless
      (actual == expected && Schema.nodeCanonicalBytes node == bytes_)
      (Left (Malformed "parent graph node digest/canonical bytes differ"))
    pure next
closureEntries :: Digest -> Graph.NodePool -> Either CodecError [(Digest, ByteString)]
closureEntries root pool = do
  selected <- Graph.reachableNodePool [root] pool
  pure [(digest, bytes_) | (digest, _, bytes_) <- Graph.nodePoolEntries selected]
