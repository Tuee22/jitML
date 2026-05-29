{-# LANGUAGE BangPatterns #-}

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
-- bit-deterministic on the same substrate; manual reverse-mode
-- backprop in Haskell trivially satisfies that contract and produces
-- the same gradients on every run with the same seed.
--
-- Forward: @y = W2 (tanh (W1 x + b1)) + b2@
-- Backward: standard manual reverse-mode through the chain rule.
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
  , policyValueForward
  , policyValueFromForward
  , policyValueOutputGradient
  , policyValueBackward

    -- * Utility
  , softmax
  , logSoftmax
  , sampleCategorical
  )
where

import Data.Vector.Unboxed (Vector)
import Data.Vector.Unboxed qualified as VU
import System.Random qualified as Random

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
-- @dL/dy@ (one entry per output unit). Returns gradients with respect
-- to every parameter. The input gradient is not returned (the input is
-- not differentiated for an RL policy).
mlpBackward :: MlpParams -> MlpForward -> Vector Double -> MlpGradient
mlpBackward params fwd dLdy =
  let shape = paramShape params
      -- dL/dz2 = dL/dy (output is linear)
      gradB2vec = dLdy
      -- dL/dW2 = outer(dLdy, hiddenAct)
      gradW2vec = outerProduct dLdy (forwardHiddenAct fwd)
      -- dL/dhAct = W2^T @ dLdy
      dHiddenAct =
        matVecTransposed
          (paramW2 params)
          (mlpOutputs shape)
          (mlpHidden shape)
          dLdy
      -- dL/dhPre = dL/dhAct * (1 - tanh^2(hPre))
      dHiddenPre =
        VU.zipWith
          (\dAct h -> dAct * (1.0 - h * h))
          dHiddenAct
          (forwardHiddenAct fwd)
      gradB1vec = dHiddenPre
      gradW1vec = outerProduct dHiddenPre (forwardInput fwd)
   in MlpGradient
        { gradW1 = gradW1vec
        , gradB1 = gradB1vec
        , gradW2 = gradW2vec
        , gradB2 = gradB2vec
        }

-- | Gradient of the loss with respect to the network /input/ vector,
-- @dL/dx = W1^T @ dL/dhPre@. Unlike 'mlpBackward' (which differentiates
-- the parameters), this differentiates the input — needed for the
-- deterministic-policy gradient in continuous actor-critic algorithms
-- (DDPG / TD3 / SAC / CrossQ / TQC), where @dQ/da@ is the action-slice
-- of the critic's input gradient.
mlpInputGradient :: MlpParams -> MlpForward -> Vector Double -> Vector Double
mlpInputGradient params fwd dLdy =
  let shape = paramShape params
      dHiddenAct =
        matVecTransposed
          (paramW2 params)
          (mlpOutputs shape)
          (mlpHidden shape)
          dLdy
      dHiddenPre =
        VU.zipWith
          (\dAct h -> dAct * (1.0 - h * h))
          dHiddenAct
          (forwardHiddenAct fwd)
   in matVecTransposed
        (paramW1 params)
        (mlpHidden shape)
        (mlpInputs shape)
        dHiddenPre

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
  , pvValue :: !Double -- tanh-bounded scalar
  }
  deriving stock (Eq, Show)

policyValueForward :: MlpParams -> Int -> Vector Double -> PolicyValueOutput
policyValueForward params actionCount input =
  policyValueFromForward actionCount (mlpForward params input)

-- | Build the policy/value heads from a precomputed forward cache. The
-- policy head softmaxes the first @actionCount@ outputs; the value head
-- is the tanh of the next output (when present). Factored out so a
-- device-backed forward (e.g. "JitML.Numerics.MlpCuda") can produce the
-- same 'PolicyValueOutput' the pure 'policyValueForward' does.
policyValueFromForward :: Int -> MlpForward -> PolicyValueOutput
policyValueFromForward actionCount fwd =
  let output = forwardOutput fwd
      logits = VU.take actionCount output
      valueRaw =
        if VU.length output > actionCount
          then output VU.! actionCount
          else 0.0
   in PolicyValueOutput
        { pvForward = fwd
        , pvPolicy = softmax logits
        , pvValue = tanh valueRaw
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
policyValueOutputGradient outputs output dLdLogits dLdValue =
  let actionCount = VU.length dLdLogits
      valueGradPre =
        if outputs > actionCount
          then dLdValue * (1.0 - pvValue output * pvValue output)
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
policyValueBackward params output dLdLogits dLdValue =
  mlpBackward
    params
    (pvForward output)
    (policyValueOutputGradient (mlpOutputs (paramShape params)) output dLdLogits dLdValue)

-- | @y = M @ x@ where @M@ is @rows × cols@ row-major.
matVec :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVec m rows cols x = VU.generate rows go
 where
  go i =
    let !row = VU.slice (i * cols) cols m
     in VU.sum (VU.zipWith (*) row x)

-- | @y = M^T @ x@ where @M@ is @rows × cols@ row-major.
matVecTransposed :: Vector Double -> Int -> Int -> Vector Double -> Vector Double
matVecTransposed m rows cols x = VU.generate cols go
 where
  go j =
    VU.sum
      ( VU.generate
          rows
          ( \i ->
              (m VU.! (i * cols + j)) * (x VU.! i)
          )
      )

-- | Outer product: @M = u v^T@; returns @length u * length v@ row-major.
outerProduct :: Vector Double -> Vector Double -> Vector Double
outerProduct u v =
  let lenV = VU.length v
   in VU.generate (VU.length u * lenV) $ \k ->
        let (i, j) = k `divMod` lenV
         in u VU.! i * v VU.! j
