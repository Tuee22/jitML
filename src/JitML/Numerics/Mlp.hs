{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 13.8 / 13.9 — pure-Haskell differentiable MLP that closes
-- the "network forward/backward seam" the RL algorithm losses and the
-- AlphaZero PriorOracle need. The module is deliberately compact: a
-- fully-connected feed-forward network with one configurable hidden
-- layer, tanh hidden activation, and a configurable output head
-- (linear, softmax, or split policy/value heads for AlphaZero).
--
-- Why pure Haskell and not JIT-codegen backward kernels? The codegen
-- side under @src/JitML/Codegen/@ emits forward primitives only
-- (Sprint 13.11 weighted bodies). Real automatic differentiation
-- through nvcc/oneDNN-generated code is multi-week engineering. The
-- determinism contract requires the network's reductions to be
-- bit-deterministic on the same substrate; the pure LayerGraph autodiff oracle
-- satisfies that contract and produces the same gradients on every run with the
-- same seed.
--
-- Forward: @y = W2 (tanh (W1 x + b1)) + b2@
-- Backward: the two-layer MLP is lowered to "JitML.Numerics.LayerGraph" and
-- replayed through the shared Sprint 23.1 reverse-mode autodiff tape.
-- Optimizer: Adam (Kingma & Ba 2015) with bias-corrected first and
-- second moments.
--
-- All weights are stored as flat row-major @Vector Double@ for fast
-- bulk arithmetic. Same-substrate / same-seed runs produce
-- bit-identical outputs.
module JitML.Numerics.Mlp
  ( -- * Network shape
    MlpShape (..)
  , MlpParams (..)
  , mlpInit
  , mlpLayerGraph
  , mlpParamsToFlat
  , mlpParamsFromFlat

    -- * Forward / backward
  , MlpForward (..)
  , mlpForward
  , MlpGradient (..)
  , mlpBackward
  , mlpInputGradient
  , mlpZeroGradient

    -- * Adam optimizer
  , AdamConfig (..)
  , AdamState (..)
  , defaultAdamConfig
  , adamInit
  , adamStep

    -- * Policy/value heads (AlphaZero)
  , PolicyValueOutput (..)
  , ValueHeadActivation (..)
  , policyValueForward
  , policyValueForwardWith
  , policyValueFromForward
  , policyValueFromForwardWith
  , policyValueOutputGradient
  , policyValueOutputGradientWith
  , policyValueBackward
  , policyValueBackwardWith

    -- * Utility
  , softmax
  , logSoftmax
  , sampleCategorical
  )
where

import Data.Text qualified as Text
import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

import JitML.Numerics.Autodiff qualified as Autodiff
import JitML.Numerics.LayerGraph qualified as LayerGraph

-- | Network shape. The network has one hidden layer of @mlpHidden@ units;
-- inputs are @mlpInputs@-wide; outputs are @mlpOutputs@-wide.
data MlpShape = MlpShape
  { mlpInputs :: !Int
  , mlpHidden :: !Int
  , mlpOutputs :: !Int
  }
  deriving stock (Eq, Show)

-- | Network parameters. Flat row-major storage:
--
--   * @paramW1 :: Vector Double@ — @hidden × inputs@ (row-major)
--   * @paramB1 :: Vector Double@ — @hidden@
--   * @paramW2 :: Vector Double@ — @outputs × hidden@ (row-major)
--   * @paramB2 :: Vector Double@ — @outputs@
data MlpParams = MlpParams
  { paramShape :: !MlpShape
  , paramW1 :: !(Vector Double)
  , paramB1 :: !(Vector Double)
  , paramW2 :: !(Vector Double)
  , paramB2 :: !(Vector Double)
  }
  deriving stock (Eq, Show)

-- | Deterministic Glorot/Xavier-style initialization seeded by a 'StdGen'.
-- Weights are drawn uniformly from
-- @[-sqrt(6 / (fan_in + fan_out)), +sqrt(6 / (fan_in + fan_out))]@.
-- Biases are zero.
mlpInit :: MlpShape -> Int -> MlpParams
mlpInit shape seed =
  let gen0 = Random.mkStdGen seed
      hiddenLimit = sqrt (6.0 / fromIntegral (mlpInputs shape + mlpHidden shape))
      outputLimit = sqrt (6.0 / fromIntegral (mlpHidden shape + mlpOutputs shape))
      (w1, gen1) = drawUniform (mlpHidden shape * mlpInputs shape) hiddenLimit gen0
      (w2, _gen2) = drawUniform (mlpOutputs shape * mlpHidden shape) outputLimit gen1
   in MlpParams
        { paramShape = shape
        , paramW1 = w1
        , paramB1 = VU.replicate (mlpHidden shape) 0.0
        , paramW2 = w2
        , paramB2 = VU.replicate (mlpOutputs shape) 0.0
        }

-- | Sprint 13.9 — flatten the parameters to a single row-major @Double@
-- list (@W1 ++ b1 ++ W2 ++ b2@) for the checkpoint @.jmw1@ weight blob.
-- Pairs with 'mlpParamsFromFlat'; the round-trip is exact (lossless F64).
mlpParamsToFlat :: MlpParams -> [Double]
mlpParamsToFlat params =
  VU.toList (paramW1 params)
    <> VU.toList (paramB1 params)
    <> VU.toList (paramW2 params)
    <> VU.toList (paramB2 params)

-- | Reconstruct parameters from a flat @Double@ list given the network
-- shape. Fails (with a message) when the list length does not match the
-- shape's total parameter count.
mlpParamsFromFlat :: MlpShape -> [Double] -> Either String MlpParams
mlpParamsFromFlat shape flat
  | length flat /= expected =
      Left
        ( "mlpParamsFromFlat: expected "
            <> show expected
            <> " values for shape "
            <> show shape
            <> ", got "
            <> show (length flat)
        )
  | otherwise =
      Right
        MlpParams
          { paramShape = shape
          , paramW1 = VU.fromList w1
          , paramB1 = VU.fromList b1
          , paramW2 = VU.fromList w2
          , paramB2 = VU.fromList b2
          }
 where
  nW1 = mlpHidden shape * mlpInputs shape
  nB1 = mlpHidden shape
  nW2 = mlpOutputs shape * mlpHidden shape
  nB2 = mlpOutputs shape
  expected = nW1 + nB1 + nW2 + nB2
  (w1, afterW1) = splitAt nW1 flat
  (b1, afterB1) = splitAt nB1 afterW1
  (w2, b2) = splitAt nW2 afterB1

mlpLayerGraph :: MlpParams -> Either String LayerGraph.LayerGraph
mlpLayerGraph params = do
  hidden <-
    mapLeft Text.unpack $
      LayerGraph.mkAffineLayer
        "mlp-hidden"
        LayerGraph.DenseLayer
        (mlpInputs shape)
        (mlpHidden shape)
        LayerGraph.TanhActivation
        LayerGraph.TrainingMode
        LayerGraph.LayerParameters
          { LayerGraph.layerWeights = paramW1 params
          , LayerGraph.layerBias = paramB1 params
          }
  output <-
    mapLeft Text.unpack $
      LayerGraph.mkAffineLayer
        "mlp-output"
        LayerGraph.DenseLayer
        (mlpHidden shape)
        (mlpOutputs shape)
        LayerGraph.LinearActivation
        LayerGraph.TrainingMode
        LayerGraph.LayerParameters
          { LayerGraph.layerWeights = paramW2 params
          , LayerGraph.layerBias = paramB2 params
          }
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "mlp"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [mlpInputs shape]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [mlpOutputs shape]
      , LayerGraph.layerGraphNodes = [hidden, output]
      }
 where
  shape = paramShape params

mapLeft :: (err -> err') -> Either err value -> Either err' value
mapLeft f =
  either (Left . f) Right

drawUniform :: Int -> Double -> Random.StdGen -> (Vector Double, Random.StdGen)
drawUniform n limit gen0 =
  let (values, genN) = go n gen0 []
   in (VU.fromList (reverse values), genN)
 where
  go 0 g acc = (acc, g)
  go k g acc =
    let (u, g') = Random.uniformR (-limit, limit) g
     in go (k - 1) g' (u : acc)

-- | Forward-pass intermediate values captured for the backward pass.
data MlpForward = MlpForward
  { forwardInput :: !(Vector Double)
  , forwardHiddenPre :: !(Vector Double)
  , forwardHiddenAct :: !(Vector Double)
  , forwardOutput :: !(Vector Double)
  }
  deriving stock (Eq, Show)

-- | Forward pass: @y = W2 (tanh (W1 x + b1)) + b2@.
mlpForward :: MlpParams -> Vector Double -> MlpForward
mlpForward params input =
  let shape = paramShape params
      hidden = matVec (paramW1 params) (mlpHidden shape) (mlpInputs shape) input
      hiddenPre = VU.zipWith (+) hidden (paramB1 params)
      hiddenAct = VU.map tanh hiddenPre
      output = matVec (paramW2 params) (mlpOutputs shape) (mlpHidden shape) hiddenAct
      outputBiased = VU.zipWith (+) output (paramB2 params)
   in MlpForward
        { forwardInput = input
        , forwardHiddenPre = hiddenPre
        , forwardHiddenAct = hiddenAct
        , forwardOutput = outputBiased
        }

-- | Gradients with respect to each parameter block.
data MlpGradient = MlpGradient
  { gradW1 :: !(Vector Double)
  , gradB1 :: !(Vector Double)
  , gradW2 :: !(Vector Double)
  , gradB2 :: !(Vector Double)
  }
  deriving stock (Eq, Show)

mlpZeroGradient :: MlpShape -> MlpGradient
mlpZeroGradient shape =
  MlpGradient
    { gradW1 = VU.replicate (mlpHidden shape * mlpInputs shape) 0.0
    , gradB1 = VU.replicate (mlpHidden shape) 0.0
    , gradW2 = VU.replicate (mlpOutputs shape * mlpHidden shape) 0.0
    , gradB2 = VU.replicate (mlpOutputs shape) 0.0
    }

-- | Backward pass given a forward cache and the upstream gradient
-- @dL/dy@ (one entry per output unit). The MLP is the two-layer special case of
-- the Sprint 23.1 typed 'LayerGraph', so the parameter gradients are produced
-- by the shared reverse-mode autodiff tape and then projected back into the
-- historical 'MlpGradient' API.
mlpBackward :: MlpParams -> MlpForward -> Vector Double -> MlpGradient
mlpBackward params fwd dLdy =
  either (error . Text.unpack) id $ do
    graph <- mapLeft Text.pack (mlpLayerGraph params)
    tape <- mlpLayerGraphTape graph fwd
    gradient <- Autodiff.runBackward graph tape dLdy
    mlpGradientFromLayerGraph gradient

-- | Gradient of the loss with respect to the network /input/ vector,
-- @dL/dx = W1^T @ dL/dhPre@. Unlike 'mlpBackward' (which differentiates
-- the parameters), this differentiates the input — needed for the
-- deterministic-policy gradient in continuous actor-critic algorithms
-- (DDPG / TD3 / SAC / CrossQ / TQC), where @dQ/da@ is the action-slice
-- of the critic's input gradient.
mlpInputGradient :: MlpParams -> MlpForward -> Vector Double -> Vector Double
mlpInputGradient params fwd dLdy =
  either (error . Text.unpack) LayerGraph.layerGraphInputGradient $ do
    graph <- mapLeft Text.pack (mlpLayerGraph params)
    tape <- mlpLayerGraphTape graph fwd
    Autodiff.runBackward graph tape dLdy

mlpLayerGraphTape :: LayerGraph.LayerGraph -> MlpForward -> Either Text.Text Autodiff.ForwardTape
mlpLayerGraphTape graph fwd =
  case LayerGraph.layerGraphNodes graph of
    [hiddenNode, outputNode] ->
      Right
        LayerGraph.LayerGraphTape
          { LayerGraph.layerTapeInput = forwardInput fwd
          , LayerGraph.layerTapeOutput = forwardOutput fwd
          , LayerGraph.layerTapeLayers =
              [ LayerGraph.LayerForward
                  { LayerGraph.layerForwardNode = hiddenNode
                  , LayerGraph.layerForwardInput = forwardInput fwd
                  , LayerGraph.layerForwardPreActivation = forwardHiddenPre fwd
                  , LayerGraph.layerForwardOutput = forwardHiddenAct fwd
                  }
              , LayerGraph.LayerForward
                  { LayerGraph.layerForwardNode = outputNode
                  , LayerGraph.layerForwardInput = forwardHiddenAct fwd
                  , LayerGraph.layerForwardPreActivation = forwardOutput fwd
                  , LayerGraph.layerForwardOutput = forwardOutput fwd
                  }
              ]
          }
    _ -> Left "mlpLayerGraphTape: expected two graph nodes"

mlpGradientFromLayerGraph :: LayerGraph.LayerGraphGradient -> Either Text.Text MlpGradient
mlpGradientFromLayerGraph gradient =
  case LayerGraph.layerGraphLayerGradients gradient of
    [hiddenGrad, outputGrad] -> do
      hidden <- layerParametersFor "mlp-hidden" hiddenGrad
      output <- layerParametersFor "mlp-output" outputGrad
      Right
        MlpGradient
          { gradW1 = LayerGraph.layerGradWeights hidden
          , gradB1 = LayerGraph.layerGradBias hidden
          , gradW2 = LayerGraph.layerGradWeights output
          , gradB2 = LayerGraph.layerGradBias output
          }
    _ -> Left "mlpGradientFromLayerGraph: expected two layer gradients"
 where
  layerParametersFor label grad =
    case LayerGraph.layerGradientParameters grad of
      Just params -> Right params
      Nothing -> Left (label <> " did not produce a parameter gradient")

-- | Adam optimizer hyperparameters.
data AdamConfig = AdamConfig
  { adamLearningRate :: !Double
  , adamBeta1 :: !Double
  , adamBeta2 :: !Double
  , adamEpsilon :: !Double
  }
  deriving stock (Eq, Show)

defaultAdamConfig :: AdamConfig
defaultAdamConfig =
  AdamConfig
    { adamLearningRate = 3.0e-4
    , adamBeta1 = 0.9
    , adamBeta2 = 0.999
    , adamEpsilon = 1.0e-8
    }

-- | Adam first/second moment state. Step count is the bias-correction
-- denominator counter.
data AdamState = AdamState
  { adamStep_ :: !Int
  , adamM :: !MlpGradient
  , adamV :: !MlpGradient
  }
  deriving stock (Eq, Show)

adamInit :: MlpShape -> AdamState
adamInit shape =
  AdamState
    { adamStep_ = 0
    , adamM = mlpZeroGradient shape
    , adamV = mlpZeroGradient shape
    }

-- | Apply one Adam update: returns updated parameters and Adam state.
adamStep :: AdamConfig -> AdamState -> MlpParams -> MlpGradient -> (MlpParams, AdamState)
adamStep config state params grad =
  let step1 = adamStep_ state + 1
      beta1 = adamBeta1 config
      beta2 = adamBeta2 config
      epsilon = adamEpsilon config
      lr = adamLearningRate config
      mNext =
        applyToGradient
          (\m g -> beta1 * m + (1.0 - beta1) * g)
          (adamM state)
          grad
      vNext =
        applyToGradient
          (\v g -> beta2 * v + (1.0 - beta2) * g * g)
          (adamV state)
          grad
      biasCorrection1 = 1.0 - beta1 ^ step1
      biasCorrection2 = 1.0 - beta2 ^ step1
      updateGroup =
        VU.zipWith
          ( \m v ->
              let mHat = m / biasCorrection1
                  vHat = v / biasCorrection2
               in lr * mHat / (sqrt vHat + epsilon)
          )
      newW1 = VU.zipWith (-) (paramW1 params) (updateGroup (gradW1 mNext) (gradW1 vNext))
      newB1 = VU.zipWith (-) (paramB1 params) (updateGroup (gradB1 mNext) (gradB1 vNext))
      newW2 = VU.zipWith (-) (paramW2 params) (updateGroup (gradW2 mNext) (gradW2 vNext))
      newB2 = VU.zipWith (-) (paramB2 params) (updateGroup (gradB2 mNext) (gradB2 vNext))
   in ( params {paramW1 = newW1, paramB1 = newB1, paramW2 = newW2, paramB2 = newB2}
      , AdamState {adamStep_ = step1, adamM = mNext, adamV = vNext}
      )

applyToGradient
  :: (Double -> Double -> Double) -> MlpGradient -> MlpGradient -> MlpGradient
applyToGradient f a b =
  MlpGradient
    { gradW1 = VU.zipWith f (gradW1 a) (gradW1 b)
    , gradB1 = VU.zipWith f (gradB1 a) (gradB1 b)
    , gradW2 = VU.zipWith f (gradW2 a) (gradW2 b)
    , gradB2 = VU.zipWith f (gradB2 a) (gradB2 b)
    }

-- | Numerically stable softmax.
softmax :: Vector Double -> Vector Double
softmax xs
  | VU.null xs = xs
  | otherwise =
      let m = VU.maximum xs
          shifted = VU.map (\x -> exp (x - m)) xs
          z = VU.sum shifted
       in VU.map (/ z) shifted

logSoftmax :: Vector Double -> Vector Double
logSoftmax xs
  | VU.null xs = xs
  | otherwise =
      let m = VU.maximum xs
          shifted = VU.map (\x -> x - m) xs
          z = log (VU.sum (VU.map exp shifted))
       in VU.map (\x -> x - z) shifted

-- | Sample an index from a categorical distribution given a uniform
-- random Double in @[0, 1)@. Deterministic for the supplied uniform.
sampleCategorical :: Vector Double -> Double -> Int
sampleCategorical probs u = go 0 0.0
 where
  n = VU.length probs
  go !i !acc
    | i >= n = n - 1
    | acc + probs VU.! i > u = i
    | otherwise = go (i + 1) (acc + probs VU.! i)

-- | Combined policy-and-value forward pass: the policy head consumes
-- the first @actionCount@ outputs through softmax, the value head
-- consumes the last output through tanh-bounded scalar.
data PolicyValueOutput = PolicyValueOutput
  { pvForward :: !MlpForward
  , pvPolicy :: !(Vector Double) -- softmax(probs)
  , pvValue :: !Double -- value scalar (see 'ValueHeadActivation')
  }
  deriving stock (Eq, Show)

-- | How the scalar value head is activated. AlphaZero regresses toward a
-- bounded game outcome in [-1, 1] and wants 'TanhValueHead'; an actor-critic
-- (PPO/A2C/TRPO/...) critic must represent unbounded discounted returns (e.g.
-- cartpole ~50-500) and wants 'LinearValueHead' — a tanh-bounded critic clamps
-- V(s) to [-1, 1] and vanishes its own gradient once saturated, collapsing the
-- advantage signal. The forward that produces a 'PolicyValueOutput' and the
-- gradient that consumes it must use the SAME activation.
data ValueHeadActivation = LinearValueHead | TanhValueHead
  deriving stock (Eq, Show)

activateValueHead :: ValueHeadActivation -> Double -> Double
activateValueHead LinearValueHead v = v
activateValueHead TanhValueHead v = tanh v

-- | d(activated value)/d(raw value), expressed in terms of the ALREADY-activated
-- value stored in 'pvValue'.
valueHeadDeriv :: ValueHeadActivation -> Double -> Double
valueHeadDeriv LinearValueHead _ = 1.0
valueHeadDeriv TanhValueHead activated = 1.0 - activated * activated

policyValueForward :: MlpParams -> Int -> Vector Double -> PolicyValueOutput
policyValueForward = policyValueForwardWith TanhValueHead

-- | 'policyValueForward' with an explicit value-head activation.
policyValueForwardWith
  :: ValueHeadActivation -> MlpParams -> Int -> Vector Double -> PolicyValueOutput
policyValueForwardWith act params actionCount input =
  policyValueFromForwardWith act actionCount (mlpForward params input)

-- | Build the policy/value heads from a precomputed forward cache. The
-- policy head softmaxes the first @actionCount@ outputs; the value head
-- is the tanh of the next output (when present). Factored out so a
-- device-backed forward (e.g. "JitML.Numerics.MlpCuda") can produce the
-- same 'PolicyValueOutput' the pure 'policyValueForward' does.
policyValueFromForward :: Int -> MlpForward -> PolicyValueOutput
policyValueFromForward = policyValueFromForwardWith TanhValueHead

-- | 'policyValueFromForward' with an explicit value-head activation.
policyValueFromForwardWith
  :: ValueHeadActivation -> Int -> MlpForward -> PolicyValueOutput
policyValueFromForwardWith act actionCount fwd =
  let output = forwardOutput fwd
      logits = VU.take actionCount output
      valueRaw =
        if VU.length output > actionCount
          then output VU.! actionCount
          else 0.0
   in PolicyValueOutput
        { pvForward = fwd
        , pvPolicy = softmax logits
        , pvValue = activateValueHead act valueRaw
        }

-- | Assemble the network's full output gradient @dL/dy@ from the policy
-- gradient (@dL/dlogits@, one per action) and the value gradient
-- (scalar), given the total output width. Shared by the pure
-- 'policyValueBackward' and the device-backed gradient path so both route
-- the identical @dL/dy@ into their respective backward kernel.
policyValueOutputGradient
  :: Int -- total output width (@mlpOutputs@)
  -> PolicyValueOutput
  -> Vector Double -- dL/dlogits (length actionCount)
  -> Double -- dL/dvalue (scalar)
  -> Vector Double
policyValueOutputGradient = policyValueOutputGradientWith TanhValueHead

-- | 'policyValueOutputGradient' with an explicit value-head activation. Must
-- match the activation used by the forward that produced @output@.
policyValueOutputGradientWith
  :: ValueHeadActivation
  -> Int
  -> PolicyValueOutput
  -> Vector Double
  -> Double
  -> Vector Double
policyValueOutputGradientWith act outputs output dLdLogits dLdValue =
  let actionCount = VU.length dLdLogits
      valueGradPre =
        if outputs > actionCount
          then dLdValue * valueHeadDeriv act (pvValue output)
          else 0.0
      tailGrads =
        if outputs > actionCount
          then VU.cons valueGradPre (VU.replicate (outputs - actionCount - 1) 0.0)
          else VU.empty
   in dLdLogits VU.++ tailGrads

-- | Backward through policy + value heads given the policy gradient
-- (one per action) and the value gradient (scalar). Combines the two
-- upstream gradients into the network's full output gradient before
-- routing to 'mlpBackward'.
policyValueBackward
  :: MlpParams
  -> PolicyValueOutput
  -> Vector Double -- dL/dlogits (length actionCount)
  -> Double -- dL/dvalue (scalar)
  -> MlpGradient
policyValueBackward = policyValueBackwardWith TanhValueHead

-- | 'policyValueBackward' with an explicit value-head activation. Must match the
-- activation used by the forward that produced @output@.
policyValueBackwardWith
  :: ValueHeadActivation
  -> MlpParams
  -> PolicyValueOutput
  -> Vector Double
  -> Double
  -> MlpGradient
policyValueBackwardWith act params output dLdLogits dLdValue =
  mlpBackward
    params
    (pvForward output)
    (policyValueOutputGradientWith act (mlpOutputs (paramShape params)) output dLdLogits dLdValue)

-- | @y = M @ x@ where @M@ is @rows × cols@ row-major.
matVec :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVec m rows cols x = VU.generate rows go
 where
  go i =
    let !row = VU.slice (i * cols) cols m
     in VU.sum (VU.zipWith (*) row x)
