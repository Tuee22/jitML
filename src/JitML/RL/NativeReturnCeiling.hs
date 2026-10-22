{-# LANGUAGE OverloadedStrings #-}

-- | Finite mathematical bounds through the actual native simulator. These
-- values confer no training, device, parent, retention or eligibility authority.
module JitML.RL.NativeReturnCeiling
  ( NativeReturnCeiling
  , NativeReturnCeilingLayer (..)
  , NativeReturnCeilingNode (..)
  , NativeReturnCeilingEdge (..)
  , nativeReturnCeilingContract
  , proveCanonicalNativeReturnCeiling
  , nativeReturnCeilingSpec
  , nativeReturnCeilingUpperBound
  , nativeReturnCeilingMaximumBits
  , nativeReturnCeilingLayers
  , nativeReturnCeilingMaximizingActions
  ) where

import Control.Monad (foldM, unless)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64)

import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.Simulator qualified as Sim

nativeReturnCeilingContract :: Text
nativeReturnCeilingContract =
  "native-keydoor-full-state-finite-dp-v1:actual-legal-envStep;canonical-start;binary64-prefix-addition;all-terminal-or-horizon-paths;no-training-or-provenance-authority"

-- All nine actual state fields occur in the dominance key. Positional
-- reconstruction makes a changed public state constructor a compile-time gap.
data StateKey = StateKey Int (Int, Int) (Int, Int) (Int, Int) (Int, Int) [(Int, Int)] Bool Bool Int
  deriving stock (Eq, Ord, Show)
data Node = Node !Sim.KeyDoorGridState !Double ![Int]

-- Replayable DATA contains every frontier node and every actual legal edge.
-- Binary64 values are transported as bits, with no decimal-rounding tolerance.
data NativeReturnCeilingEdge = NativeReturnCeilingEdge
  { nativeCeilingEdgeAction :: !Int
  , nativeCeilingEdgeRewardBits :: !Word64
  , nativeCeilingEdgeCandidateBits :: !Word64
  , nativeCeilingEdgePostState :: !Sim.KeyDoorGridState
  , nativeCeilingEdgeNativeDone :: !Bool
  , nativeCeilingEdgeHorizonDone :: !Bool
  }
  deriving stock (Eq, Show)
data NativeReturnCeilingNode = NativeReturnCeilingNode
  { nativeCeilingNodeState :: !Sim.KeyDoorGridState
  , nativeCeilingNodePrefixBits :: !Word64
  , nativeCeilingNodeActions :: ![Int]
  , nativeCeilingNodeLegalMask :: ![Bool]
  , nativeCeilingNodeEdges :: ![NativeReturnCeilingEdge]
  }
  deriving stock (Eq, Show)
data NativeReturnCeilingLayer = NativeReturnCeilingLayer
  { nativeCeilingLayerTime :: !Int
  , nativeCeilingLayerNodes :: ![NativeReturnCeilingNode]
  , nativeCeilingLayerNextCount :: !Int
  }
  deriving stock (Eq, Show)

-- Only the complete actual solver constructs this mathematical certificate.
-- Portable DATA cannot restore this value, an executable capsule or a receipt.
data NativeReturnCeiling
  = NativeReturnCeiling
      !Ref.NativeReturnReferenceSpec
      !Double
      ![Int]
      ![NativeReturnCeilingLayer]
  deriving stock (Eq, Show)

nativeReturnCeilingSpec :: NativeReturnCeiling -> Ref.NativeReturnReferenceSpec
nativeReturnCeilingSpec (NativeReturnCeiling spec _ _ _) = spec
nativeReturnCeilingUpperBound :: NativeReturnCeiling -> Rational
nativeReturnCeilingUpperBound (NativeReturnCeiling _ value _ _) = toRational value
nativeReturnCeilingMaximumBits :: NativeReturnCeiling -> Word64
nativeReturnCeilingMaximumBits (NativeReturnCeiling _ value _ _) = castDoubleToWord64 value
nativeReturnCeilingMaximizingActions :: NativeReturnCeiling -> [Int]
nativeReturnCeilingMaximizingActions (NativeReturnCeiling _ _ actions _) = actions
nativeReturnCeilingLayers :: NativeReturnCeiling -> [NativeReturnCeilingLayer]
nativeReturnCeilingLayers (NativeReturnCeiling _ _ _ layers) = layers

-- | Unsupported return tasks retain strict reference comparison. The supported
-- KeyDoor proof is recomputed from the current compiled simulator; a historical
-- observed constant or a caller-supplied numerical ceiling cannot authorize a tie.
proveCanonicalNativeReturnCeiling
  :: Ref.NativeReturnReferenceSpec -> Either Text (Maybe NativeReturnCeiling)
proveCanonicalNativeReturnCeiling spec = do
  canonical <-
    Ref.canonicalNativeReturnSpec
      (Ref.nativeReturnSpecAlgorithm spec)
      (Ref.nativeReturnSpecEnvironment spec)
  require (spec == canonical) "native ceiling requires the complete current canonical return spec"
  if Ref.nativeReturnSpecEnvironment spec /= "key-door-grid"
    then pure Nothing
    else do
      allSpecs <- Ref.allCanonicalNativeReturnSpecs
      let owned = filter ((== "key-door-grid") . Ref.nativeReturnSpecEnvironment) allSpecs
          environment = Sim.keyDoorGridEnvironment
          initial = Sim.envInitial environment
      require
        ( length owned == 8
            && all sameScope owned
            && Sim.envName environment == "key-door-grid"
            && Sim.envActionCount environment == 6
            && Sim.envMaxEpisodeSteps environment == 64
            && Sim.keyDoorGridStepCount initial == 0
            && stateFor (keyFor initial) == initial
        )
        "native KeyDoor ceiling scope or complete state contract differs"
      (winner, layers) <- solve (Ref.nativeReturnSpecHorizon spec) environment
      let Node _ maximumValue actions = winner
      pure (Just (NativeReturnCeiling spec maximumValue actions layers))
 where
  sameScope row =
    Ref.nativeReturnSpecDomain row == Ref.NativeMaskedDiscrete 6
      && Ref.nativeReturnSpecHorizon row == 200
      && Ref.nativeReturnSpecEpisodeCount row == 20

-- Prefix dominance is sound because a full Markov state/time fixes all future
-- legal transitions and finite correctly rounded binary64 addition is monotone.
-- Every non-dominated frontier path is expanded without sampling, discretizing,
-- a guessed reward formula or an arbitrary search/node cutoff.
solve
  :: Int
  -> Sim.SimulatedEnvironment Sim.KeyDoorGridState
  -> Either Text (Node, [NativeReturnCeilingLayer])
solve horizon environment = go 0 (Map.singleton (keyFor initial) (Node initial 0 [])) Nothing []
 where
  initial = Sim.envInitial environment
  go time frontier best layers
    | Map.null frontier = case best of
        Nothing -> Left "native ceiling exhausted its frontier without a terminal path"
        Just winner -> Right (winner, reverse layers)
    | otherwise = do
        require (time < horizon) "native ceiling has an unprocessed horizon frontier"
        (next, newBest, nodes) <- foldM (expand time) (Map.empty, best, []) (Map.toAscList frontier)
        let layer = NativeReturnCeilingLayer time (reverse nodes) (Map.size next)
        go (time + 1) next newBest (layer : layers)
  expand time (next, best, nodes) (key, Node state reward actions) = do
    require
      ( key == keyFor state
          && stateFor key == state
          && Sim.keyDoorGridStepCount state == time
          && finite reward
      )
      "native ceiling full state/time or finite prefix binding differs"
    mask <- case Sim.envActionMask environment of
      Nothing -> Left "native ceiling actual legal-action mask is absent"
      Just maskFor -> Right (maskFor state)
    require
      (length mask == Sim.envActionCount environment && or mask)
      "native ceiling actual legal-action mask is malformed"
    let legal = [action | (action, True) <- zip [0 :: Int ..] mask]
    (newNext, newBest, edges) <- foldM (edge time state reward actions) (next, best, []) legal
    let node = NativeReturnCeilingNode state (castDoubleToWord64 reward) actions mask (reverse edges)
    pure (newNext, newBest, node : nodes)
  edge time state reward actions (next, best, edges) action = do
    let transition = Sim.envStep environment state action
        post = Sim.simStepState transition
        increment = Sim.simStepReward transition
        candidate = reward + increment
        nativeDone = Sim.simStepDone transition
        horizonDone = time + 1 >= horizon
        node = Node post candidate (actions <> [action])
        observation =
          NativeReturnCeilingEdge
            action
            (castDoubleToWord64 increment)
            (castDoubleToWord64 candidate)
            post
            nativeDone
            horizonDone
    require
      ( finite increment
          && finite candidate
          && stateFor (keyFor post) == post
          && Sim.keyDoorGridStepCount post == time + 1
      )
      "native ceiling actual transition is nonfinite or loses full state/time"
    pure $
      if nativeDone || horizonDone
        then (next, Just (maybe node (choose node) best), observation : edges)
        else (Map.insertWith choose (keyFor post) node next, best, observation : edges)

choose :: Node -> Node -> Node
choose new@(Node _ newValue _) old@(Node _ oldValue _) = if newValue > oldValue then new else old
keyFor :: Sim.KeyDoorGridState -> StateKey
keyFor state =
  StateKey
    (Sim.keyDoorGridSeed state)
    (position (Sim.keyDoorGridAgent state))
    (position (Sim.keyDoorGridKey state))
    (position (Sim.keyDoorGridDoor state))
    (position (Sim.keyDoorGridGoal state))
    (map position (Sim.keyDoorGridWalls state))
    (Sim.keyDoorGridHasKey state)
    (Sim.keyDoorGridDoorOpen state)
    (Sim.keyDoorGridStepCount state)
stateFor :: StateKey -> Sim.KeyDoorGridState
stateFor (StateKey seed agent key door goal walls hasKey open steps) =
  Sim.KeyDoorGridState
    seed
    (fromPosition agent)
    (fromPosition key)
    (fromPosition door)
    (fromPosition goal)
    (map fromPosition walls)
    hasKey
    open
    steps
position :: Sim.KeyDoorGridPosition -> (Int, Int)
position value = (Sim.keyDoorGridRow value, Sim.keyDoorGridCol value)
fromPosition :: (Int, Int) -> Sim.KeyDoorGridPosition
fromPosition (row, col) = Sim.KeyDoorGridPosition row col
finite :: Double -> Bool
finite value = not (isNaN value || isInfinite value)
require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
