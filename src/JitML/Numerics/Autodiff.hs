-- | Sprint 23.1 — public reverse-mode autodiff surface over the typed
-- 'LayerGraph' IR. Backends plug into the same graph in later sprints; this
-- module names the pure oracle API used by tests and by the MLP special case.
module JitML.Numerics.Autodiff
  ( ForwardTape
  , ReverseGradient
  , runForward
  , runBackward
  , squaredErrorGradient
  , loss
  , maxFiniteDifferenceError
  , maxInputFiniteDifferenceError
  )
where

import Data.Text (Text)
import Data.Vector.Unboxed (Vector)

import JitML.Numerics.LayerGraph qualified as LayerGraph

type ForwardTape = LayerGraph.LayerGraphTape

type ReverseGradient = LayerGraph.LayerGraphGradient

runForward :: LayerGraph.LayerGraph -> Vector Double -> Either Text ForwardTape
runForward = LayerGraph.runLayerGraph

runBackward
  :: LayerGraph.LayerGraph -> ForwardTape -> Vector Double -> Either Text ReverseGradient
runBackward = LayerGraph.backwardLayerGraph

squaredErrorGradient
  :: LayerGraph.LayerGraph
  -> Vector Double
  -> Vector Double
  -> Either Text (ForwardTape, ReverseGradient)
squaredErrorGradient = LayerGraph.layerGraphSquaredErrorGradient

loss :: LayerGraph.LayerGraph -> Vector Double -> Vector Double -> Either Text Double
loss = LayerGraph.layerGraphLoss

maxFiniteDifferenceError
  :: Double -> LayerGraph.LayerGraph -> Vector Double -> Vector Double -> Either Text Double
maxFiniteDifferenceError = LayerGraph.maxFiniteDifferenceError

maxInputFiniteDifferenceError
  :: Double -> LayerGraph.LayerGraph -> Vector Double -> Vector Double -> Either Text Double
maxInputFiniteDifferenceError = LayerGraph.maxInputFiniteDifferenceError
