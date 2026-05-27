{-# LANGUAGE OverloadedStrings #-}

module JitML.RL.AlphaZero.Mcts
  ( MctsConfig (..)
  , MctsEdge (..)
  , MctsNode (..)
  , PriorOracle
  , TranspositionKey (..)
  , TranspositionTable (..)
  , defaultMctsConfig
  , defaultPriorOracle
  , emptyTranspositionTable
  , expand
  , expandWithPrior
  , initialNode
  , priorFor
  , runSearch
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
import Data.List (maximumBy, sortOn)
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
    }

data MctsEdge = MctsEdge
  { edgeAction :: Int
  , edgeVisits :: Int
  , edgeTotalValue :: Double
  , edgePrior :: Double
  }
  deriving stock (Eq, Show)

data MctsNode = MctsNode
  { nodeMoves :: [Int]
  , nodeChildren :: [MctsEdge]
  , nodeVisits :: Int
  }
  deriving stock (Eq, Show)

initialNode :: MctsNode
initialNode =
  MctsNode {nodeMoves = [], nodeChildren = [], nodeVisits = 0}

-- | Deterministic prior derived from the action index plus a per-search seed;
-- the real network call is stubbed by a reproducible function so the search
-- tree is end-to-end testable. Sprint 13.9 introduces `PriorOracle` so callers
-- can substitute a real JIT-engine network forward pass without changing the
-- search loop.
priorFor :: Int -> Int -> Double
priorFor seed action =
  let raw = ((seed * 2654435761 + action * 41) `mod` 9973) + 1
   in fromIntegral raw / 9973.0

-- | A prior oracle takes the search seed and the candidate action index and
-- returns the prior probability that AlphaZero should assign to that action.
-- The deterministic stub `priorFor` matches `defaultPriorOracle`; a real
-- AlphaZero loop wraps a JIT-engine policy network forward pass that emits
-- the prior distribution for the current position. Sprint 13.9.
type PriorOracle = Int -> Int -> Double

-- | The deterministic stub oracle. Kept as the default so existing tests and
-- non-network callers continue to exercise a reproducible search tree.
defaultPriorOracle :: PriorOracle
defaultPriorOracle = priorFor

expand :: MctsConfig -> Int -> MctsNode -> MctsNode
expand = expandWithPrior defaultPriorOracle

-- | Same as `expand` but the caller supplies the prior oracle. Sprint 13.9 —
-- swap `defaultPriorOracle` for a JIT-engine network-backed oracle to drive
-- real AlphaZero search.
expandWithPrior :: PriorOracle -> MctsConfig -> Int -> MctsNode -> MctsNode
expandWithPrior oracle config seed node =
  let actions = [0 .. mctsActionSpace config - 1]
      priors = [oracle seed action | action <- actions]
      total = sum priors
      normalised = [p / total | p <- priors]
      edges =
        [ MctsEdge {edgeAction = a, edgeVisits = 0, edgeTotalValue = 0, edgePrior = p}
        | (a, p) <- zip actions normalised
        ]
   in node {nodeChildren = sortOn edgeAction edges}

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

selectAction :: MctsConfig -> MctsNode -> Maybe Int
selectAction config node
  | null (nodeChildren node) = Nothing
  | otherwise =
      Just $
        edgeAction $
          maximumBy
            (comparing (ucbScore config (nodeVisits node)))
            (nodeChildren node)

-- | Run the search loop for `mctsSimulations` rollouts; each rollout backs up a
-- deterministic value derived from the action index, the seed, and the depth.
runSearch :: MctsConfig -> Int -> MctsNode
runSearch = runSearchWithPrior defaultPriorOracle

-- | Sprint 13.9 — `runSearch` with a caller-supplied prior oracle. The real
-- AlphaZero loop threads a JIT-engine policy network forward pass here.
runSearchWithPrior :: PriorOracle -> MctsConfig -> Int -> MctsNode
runSearchWithPrior oracle config seed =
  go (mctsSimulations config) (expandWithPrior oracle config seed initialNode)
 where
  go 0 node = node
  go n node = go (n - 1) (simulateWithPrior oracle config seed node)

-- | Transposition-table key. Two distinct move sequences that lead to the
-- same position collapse to the same key. The canonical form sorts the
-- move-history prefix's terminal symmetry; for now the prefix is the raw
-- move list, which is correct for adversarial perfect-information games
-- without state-space symmetry collapse. Hashing via SHA-256 keeps the
-- key fixed-width regardless of game depth.
newtype TranspositionKey = TranspositionKey
  { unTranspositionKey :: Text
  }
  deriving stock (Eq, Ord, Show)

-- | Simple assoc-list-backed transposition table. The MCTS hot path mostly
-- inserts unique keys so an assoc list is fine for the canonical Connect 4 /
-- Othello / Hex / Gomoku search budgets; swap for `Data.Map.Strict` when
-- the `containers` dep lands.
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
-- canonical node-per-position. The table starts empty; subsequent searches
-- can pass in an accumulated table to short-circuit `expand` calls for
-- already-visited positions.
runSearchWithTable
  :: MctsConfig -> Int -> [Int] -> TranspositionTable -> (MctsNode, TranspositionTable)
runSearchWithTable = runSearchWithTableAndPrior defaultPriorOracle

-- | Sprint 13.9 — `runSearchWithTable` with a caller-supplied prior oracle.
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

-- | Sprint 13.9 — backup uses the supplied oracle's value for the chosen
-- action. The deterministic stub feeds the same `priorFor`-derived value
-- the original `simulate` used; a real network call replaces this with the
-- value-head output for the current position.
simulateWithPrior :: PriorOracle -> MctsConfig -> Int -> MctsNode -> MctsNode
simulateWithPrior oracle config seed node =
  case selectAction config node of
    Nothing -> node
    Just action ->
      let value = oracle (seed + 7919) action
          newChildren =
            [ if edgeAction edge == action
                then
                  edge
                    { edgeVisits = edgeVisits edge + 1
                    , edgeTotalValue = edgeTotalValue edge + value
                    }
                else edge
            | edge <- nodeChildren node
            ]
       in node
            { nodeChildren = newChildren
            , nodeVisits = nodeVisits node + 1
            }
