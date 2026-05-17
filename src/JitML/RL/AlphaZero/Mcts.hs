module JitML.RL.AlphaZero.Mcts
  ( MctsConfig (..)
  , MctsEdge (..)
  , MctsNode (..)
  , defaultMctsConfig
  , expand
  , initialNode
  , priorFor
  , runSearch
  , selectAction
  , ucbScore
  )
where

import Data.List (maximumBy, sortOn)
import Data.Ord (comparing)

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
-- tree is end-to-end testable.
priorFor :: Int -> Int -> Double
priorFor seed action =
  let raw = ((seed * 2654435761 + action * 41) `mod` 9973) + 1
   in fromIntegral raw / 9973.0

expand :: MctsConfig -> Int -> MctsNode -> MctsNode
expand config seed node =
  let actions = [0 .. mctsActionSpace config - 1]
      priors = [priorFor seed action | action <- actions]
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
runSearch config seed =
  go (mctsSimulations config) (expand config seed initialNode)
 where
  go 0 node = node
  go n node = go (n - 1) (simulate config seed node)

simulate :: MctsConfig -> Int -> MctsNode -> MctsNode
simulate config seed node =
  case selectAction config node of
    Nothing -> node
    Just action ->
      let value = priorFor (seed + 7919) action
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
