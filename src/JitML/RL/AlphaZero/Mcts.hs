{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 9.10 — a real Monte-Carlo tree search (replacing the prior
-- one-ply bandit). Each simulation descends from the root by the PUCT/UCB
-- rule to an unexpanded leaf, expands it with the position's network priors,
-- evaluates the leaf through the network __value head__, and backs the value
-- up the visited path with the adversarial sign flip (one player's gain is the
-- other's loss). The tree is bounded by 'mctsMaxDepth'. The position oracle
-- ('PriorOracle') is keyed by the move-path from the search root, so the search
-- evaluates the network at every descended position rather than only the root.
--
-- Substrate-backed value-head evaluation (running the leaf forward on the JIT
-- device rather than the pure-Haskell reference net) is a follow-on that
-- couples to making the search @IO@; tracked in the Phase 9 Remaining Work.
module JitML.RL.AlphaZero.Mcts
  ( MctsConfig (..)
  , MctsEdge (..)
  , MctsNode (..)
  , NodeEval (..)
  , PriorOracle
  , PriorOracleIO
  , TranspositionKey (..)
  , TranspositionTable (..)
  , defaultMctsConfig
  , defaultPriorOracle
  , emptyTranspositionTable
  , initialNode
  , runSearch
  , runSearchWithPriorIO
  , runSearchWithPrior
  , runSearchWithTable
  , runSearchWithTableAndPrior
  , selectAction
  , transpositionKey
  , transpositionLookup
  , transpositionSize
  , ucbScore
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.Char (intToDigit)
import Data.List (maximumBy)
import Data.Maybe (fromMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word8)

data MctsConfig = MctsConfig
  { mctsSimulations :: Int
  , mctsCpuct :: Double
  , mctsRootDirichletAlpha :: Double
  , mctsRootDirichletWeight :: Double
  , mctsActionSpace :: Int
  , mctsMaxDepth :: Int
  -- ^ tree depth bound: positions reached at this depth are evaluated as
  -- leaves through the value head rather than expanded further.
  }
  deriving stock (Eq, Show)

defaultMctsConfig :: Int -> MctsConfig
defaultMctsConfig actionSpace =
  MctsConfig
    { mctsSimulations = 400
    , mctsCpuct = 1.5
    , mctsRootDirichletAlpha = 0.3
    , mctsRootDirichletWeight = 0.25
    , mctsActionSpace = actionSpace
    , mctsMaxDepth = 8
    }

-- | The network's evaluation of a position reached by a move-path from the
-- search root: the per-action policy priors, the value-head estimate from the
-- to-move player's perspective, and whether the position is terminal (and so
-- must not be expanded).
data NodeEval = NodeEval
  { evalPriors :: [Double]
  , evalValue :: Double
  , evalTerminal :: Bool
  }
  deriving stock (Eq, Show)

-- | A position oracle maps the move-path from the search root to the network
-- evaluation of the position that path reaches. The production AlphaZero loop
-- ('JitML.RL.AlphaZero.PolicyValueNet.netOracleFactory') applies the path to
-- the root 'GameState' and runs the policy/value network forward.
type PriorOracle = [Int] -> NodeEval

-- | Device-backed position oracle. The shape matches 'PriorOracle', but the
-- network evaluation may compile/load/execute the substrate-selected
-- 'JitML.Numerics.MlpDevice' and can therefore fail closed.
type PriorOracleIO = [Int] -> IO (Either Text NodeEval)

-- | Neutral default for mechanics tests and non-network callers: uniform
-- priors (empty list ⇒ uniform expansion), zero value, never terminal.
defaultPriorOracle :: PriorOracle
defaultPriorOracle _ = NodeEval [] 0.0 False

data MctsEdge = MctsEdge
  { edgeAction :: Int
  , edgeVisits :: Int
  , edgeTotalValue :: Double
  , edgePrior :: Double
  , edgeChild :: Maybe MctsNode
  }
  deriving stock (Eq, Show)

data MctsNode = MctsNode
  { nodeMoves :: [Int]
  , nodeChildren :: [MctsEdge]
  , nodeVisits :: Int
  , nodeExpanded :: Bool
  }
  deriving stock (Eq, Show)

initialNode :: MctsNode
initialNode = MctsNode {nodeMoves = [], nodeChildren = [], nodeVisits = 0, nodeExpanded = False}

-- | A fresh, unexpanded node at the given move-path from the search root.
freshNode :: [Int] -> MctsNode
freshNode moves = MctsNode {nodeMoves = moves, nodeChildren = [], nodeVisits = 0, nodeExpanded = False}

-- | PUCT exploration score for one edge.
ucbScore :: MctsConfig -> Int -> MctsEdge -> Double
ucbScore config totalVisits edge =
  let qValue =
        if edgeVisits edge == 0
          then 0
          else edgeTotalValue edge / fromIntegral (edgeVisits edge)
      exploration =
        mctsCpuct config
          * edgePrior edge
          * sqrt (fromIntegral totalVisits + 1.0)
          / (fromIntegral (edgeVisits edge) + 1.0)
   in qValue + exploration

-- | The child edge with the highest PUCT score, or 'Nothing' at a leaf.
selectEdge :: MctsConfig -> MctsNode -> Maybe MctsEdge
selectEdge config node
  | null (nodeChildren node) = Nothing
  | otherwise =
      Just $
        maximumBy
          (comparing (ucbScore config (nodeVisits node)))
          (nodeChildren node)

selectAction :: MctsConfig -> MctsNode -> Maybe Int
selectAction config = fmap edgeAction . selectEdge config

-- | Expand a leaf node from its network evaluation: create one edge per action
-- with the normalised prior. Empty / all-zero priors fall back to uniform.
expandNode :: NodeEval -> MctsConfig -> MctsNode -> MctsNode
expandNode ev config node =
  let n = mctsActionSpace config
      raw = take n (evalPriors ev <> repeat 0.0)
      priors = if all (<= 0) raw then replicate n 1.0 else raw
      total = sum priors
      norm = fmap (\p -> p / (if total <= 0 then 1.0 else total)) priors
      edges =
        [ MctsEdge {edgeAction = a, edgeVisits = 0, edgeTotalValue = 0.0, edgePrior = p, edgeChild = Nothing}
        | (a, p) <- zip [0 ..] norm
        ]
   in node {nodeChildren = edges, nodeExpanded = True}

-- | One MCTS simulation from @node@ at search @depth@. Returns the updated node
-- and the value backed up to this node, from the perspective of the player to
-- move at this node. A leaf (unexpanded, terminal, or at the depth bound) is
-- evaluated through the oracle's value head; an internal node selects a child
-- by PUCT, recurses, and credits the chosen edge with the sign-flipped child
-- value.
simulate :: PriorOracle -> MctsConfig -> Int -> MctsNode -> (MctsNode, Double)
simulate oracle config depth node
  | not (nodeExpanded node) =
      let ev = oracle (nodeMoves node)
       in if evalTerminal ev || depth >= mctsMaxDepth config
            then (node {nodeVisits = nodeVisits node + 1, nodeExpanded = True}, evalValue ev)
            else
              let expanded = expandNode ev config node
               in (expanded {nodeVisits = nodeVisits node + 1}, evalValue ev)
  | null (nodeChildren node) =
      let ev = oracle (nodeMoves node)
       in (node {nodeVisits = nodeVisits node + 1}, evalValue ev)
  | otherwise =
      case selectEdge config node of
        Nothing -> (node, 0.0)
        Just edge ->
          let action = edgeAction edge
              child0 = fromMaybe (freshNode (nodeMoves node <> [action])) (edgeChild edge)
              (child', childValue) = simulate oracle config (depth + 1) child0
              backed = negate childValue
              edge' =
                edge
                  { edgeChild = Just child'
                  , edgeVisits = edgeVisits edge + 1
                  , edgeTotalValue = edgeTotalValue edge + backed
                  }
              children' =
                [ if edgeAction e == action then edge' else e
                | e <- nodeChildren node
                ]
           in (node {nodeChildren = children', nodeVisits = nodeVisits node + 1}, backed)

-- | IO analogue of 'simulate' for substrate-backed policy/value evaluation.
simulateIO :: PriorOracleIO -> MctsConfig -> Int -> MctsNode -> IO (Either Text (MctsNode, Double))
simulateIO oracle config depth node
  | not (nodeExpanded node) = do
      evResult <- oracle (nodeMoves node)
      pure $
        case evResult of
          Left err -> Left err
          Right ev ->
            if evalTerminal ev || depth >= mctsMaxDepth config
              then Right (node {nodeVisits = nodeVisits node + 1, nodeExpanded = True}, evalValue ev)
              else
                let expanded = expandNode ev config node
                 in Right (expanded {nodeVisits = nodeVisits node + 1}, evalValue ev)
  | null (nodeChildren node) = do
      evResult <- oracle (nodeMoves node)
      pure $
        case evResult of
          Left err -> Left err
          Right ev -> Right (node {nodeVisits = nodeVisits node + 1}, evalValue ev)
  | otherwise =
      case selectEdge config node of
        Nothing -> pure (Right (node, 0.0))
        Just edge -> do
          let action = edgeAction edge
              child0 = fromMaybe (freshNode (nodeMoves node <> [action])) (edgeChild edge)
          childResult <- simulateIO oracle config (depth + 1) child0
          pure $
            case childResult of
              Left err -> Left err
              Right (child', childValue) ->
                let backed = negate childValue
                    edge' =
                      edge
                        { edgeChild = Just child'
                        , edgeVisits = edgeVisits edge + 1
                        , edgeTotalValue = edgeTotalValue edge + backed
                        }
                    children' =
                      [ if edgeAction e == action then edge' else e
                      | e <- nodeChildren node
                      ]
                 in Right (node {nodeChildren = children', nodeVisits = nodeVisits node + 1}, backed)

-- | Run the real tree search for `mctsSimulations` simulations from the root
-- with the neutral default oracle.
runSearch :: MctsConfig -> Int -> MctsNode
runSearch = runSearchWithPrior defaultPriorOracle

-- | Sprint 9.10 — `runSearch` with a caller-supplied position oracle (the
-- production AlphaZero loop threads the policy/value network forward here). The
-- @seed@ argument is retained for caller compatibility; the search itself is
-- deterministic (no root noise), so same oracle + same config ⇒ same tree.
runSearchWithPrior :: PriorOracle -> MctsConfig -> Int -> MctsNode
runSearchWithPrior oracle config _seed =
  go (max 1 (mctsSimulations config)) (freshNode [])
 where
  go 0 node = node
  go n node = go (n - 1) (fst (simulate oracle config 0 node))

-- | Device-backed variant of 'runSearchWithPrior'. The search mechanics stay
-- identical to the pure path, but each leaf expansion/evaluation is supplied by
-- an effectful oracle that may run the value head through the selected JIT
-- device. Any oracle failure aborts the search with 'Left' rather than falling
-- back to the pure network.
runSearchWithPriorIO :: PriorOracleIO -> MctsConfig -> Int -> IO (Either Text MctsNode)
runSearchWithPriorIO oracle config _seed =
  go (max 1 (mctsSimulations config)) (freshNode [])
 where
  go 0 node = pure (Right node)
  go n node = do
    simulated <- simulateIO oracle config 0 node
    case simulated of
      Left err -> pure (Left err)
      Right (node', _) -> go (n - 1) node'

-- | Transposition-table key. Two distinct move sequences that lead to the
-- same position collapse to the same key. Hashing via SHA-256 keeps the key
-- fixed-width regardless of game depth.
newtype TranspositionKey = TranspositionKey
  { unTranspositionKey :: Text
  }
  deriving stock (Eq, Ord, Show)

-- | Simple assoc-list-backed transposition table that caches the canonical
-- node-per-position, keyed by move-path.
newtype TranspositionTable = TranspositionTable
  { unTranspositionTable :: [(TranspositionKey, MctsNode)]
  }
  deriving stock (Eq, Show)

emptyTranspositionTable :: TranspositionTable
emptyTranspositionTable = TranspositionTable []

transpositionKey :: [Int] -> TranspositionKey
transpositionKey moves =
  TranspositionKey . hashHex . SHA256.hash $
    Text.Encoding.encodeUtf8
      (Text.intercalate "," (fmap (Text.pack . show) moves))

transpositionLookup :: TranspositionKey -> TranspositionTable -> Maybe MctsNode
transpositionLookup key (TranspositionTable entries) = lookup key entries

transpositionInsert :: TranspositionKey -> MctsNode -> TranspositionTable -> TranspositionTable
transpositionInsert key node (TranspositionTable entries) =
  TranspositionTable ((key, node) : filter ((/= key) . fst) entries)

transpositionSize :: TranspositionTable -> Int
transpositionSize (TranspositionTable entries) = length entries

hashHex :: ByteString.ByteString -> Text
hashHex =
  Text.pack . concatMap byteHex . ByteString.unpack
 where
  byteHex :: Word8 -> String
  byteHex byte =
    [ intToDigit (fromIntegral byte `div` 16)
    , intToDigit (fromIntegral byte `mod` 16)
    ]

-- | Same as `runSearch` but threads a transposition table that caches the
-- canonical node-per-position. The table starts empty; an accumulated table
-- short-circuits the search for an already-visited position.
runSearchWithTable
  :: MctsConfig -> Int -> [Int] -> TranspositionTable -> (MctsNode, TranspositionTable)
runSearchWithTable = runSearchWithTableAndPrior defaultPriorOracle

-- | Sprint 9.10 — `runSearchWithTable` with a caller-supplied position oracle.
runSearchWithTableAndPrior
  :: PriorOracle
  -> MctsConfig
  -> Int
  -> [Int]
  -> TranspositionTable
  -> (MctsNode, TranspositionTable)
runSearchWithTableAndPrior oracle config seed moves table =
  let key = transpositionKey moves
   in case transpositionLookup key table of
        Just cached -> (cached, table)
        Nothing ->
          let result = runSearchWithPrior oracle config seed
              table' = transpositionInsert key result table
           in (result, table')
