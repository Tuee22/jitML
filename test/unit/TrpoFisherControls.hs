{-# LANGUAGE OverloadedStrings #-}

-- | Local structural/numerical controls; the injected Float32 reference is not
-- real hardware convergence. Shared leaf values keep unit registration intact.
module TrpoFisherControls
  ( trpoFisherControls
  , fisherHomogeneityTest
  , fisherDeviceDispatchTest
  , fisherInvalidInputsTest
  , fisherDeviceFailureTest
  , assertLeftContains
  , failingForwardBatchDevice
  , failingBatchGradientDevice
  , mkTrpoStep
  , smallTrpoConfig
  , constantGradientLike
  , deterministicGradientLike
  , mapGradientForTest
  , gradientDotForTest
  , gradientAllFinite
  )
where

import Control.Monad qualified
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer

trpoFisherControls :: TestTree
trpoFisherControls =
  testGroup
    "TRPO normalized-direction Fisher controls"
    [ fisherHomogeneityTest
    , fisherDeviceDispatchTest
    , fisherInvalidInputsTest
    , fisherDeviceFailureTest
    ]

fisherHomogeneityTest :: TestTree
fisherHomogeneityTest =
  testCase "device TRPO Fisher preserves tiny and negative Float32 directions with nonzero curvature" $ do
    let (config, params, batch, direction) = trpoFloat32FisherFixture
        analytic = PpoTrainer.trpoFisherVectorProduct config batch params direction
        activeWeight gradient = Mlp.gradW2 gradient Data.Vector.Unboxed.! 0
    baseResult <-
      PpoTrainer.trpoFisherVectorProductDevice
        float32RoundingMlpDeviceForTest
        config
        batch
        params
        direction
    base <- either (assertFailure . Text.unpack) pure baseResult
    assertBool "Float32 Fisher lost its undamped curvature" $
      activeWeight base - PpoTrainer.ppoTrpoCgDamping config > 0.01
    assertBool "device finite difference disagrees with analytic categorical Fisher" $
      maxGradientDifferenceForTest base analytic < 5.0e-5
    Control.Monad.forM_ [1.0e-14, -1.0e-14, 1.0e-200, 1.0e-310, 1.0e200] $ \factor -> do
      scaledResult <-
        PpoTrainer.trpoFisherVectorProductDevice
          float32RoundingMlpDeviceForTest
          config
          batch
          params
          (mapGradientForTest (* factor) direction)
      scaled <- either (assertFailure . Text.unpack) pure scaledResult
      let restored = mapGradientForTest (/ factor) scaled
      assertBool ("non-finite Fisher at direction scale " <> show factor) (gradientAllFinite scaled)
      assertBool ("damping-only Fisher at direction scale " <> show factor) $
        activeWeight restored - PpoTrainer.ppoTrpoCgDamping config > 0.01
      assertBool ("Fisher homogeneity failed at direction scale " <> show factor) $
        maxGradientDifferenceForTest restored base < 1.0e-8
    -- Several nonzero coordinates also exercise the scaled L2 factor,
    -- which is exactly one for the sparse Float32 counterexample.
    let multiDirection = deterministicGradientLike params
        multiAnalytic = PpoTrainer.trpoFisherVectorProduct config batch params multiDirection
        runMulti = PpoTrainer.trpoFisherVectorProductDevice float32RoundingMlpDeviceForTest config batch params
    multiResult <- runMulti multiDirection
    multiProduct <- either (assertFailure . Text.unpack) pure multiResult
    assertBool "multi-coordinate device Fisher disagrees with analytic curvature" $
      maxGradientDifferenceForTest multiProduct multiAnalytic < 5.0e-5
    assertBool "multi-coordinate device Fisher has no undamped curvature" $
      gradientDotForTest multiDirection multiProduct
        - PpoTrainer.ppoTrpoCgDamping config * gradientDotForTest multiDirection multiDirection
        > 1.0e-6
    tinyMultiResult <- runMulti (mapGradientForTest (* 1.0e-200) multiDirection)
    tinyMulti <- either (assertFailure . Text.unpack) pure tinyMultiResult
    assertBool "multi-coordinate tiny Fisher homogeneity failed" $
      maxGradientDifferenceForTest (mapGradientForTest (/ 1.0e-200) tinyMulti) multiProduct < 1.0e-8

fisherDeviceDispatchTest :: TestTree
fisherDeviceDispatchTest =
  testCase "device TRPO Fisher uses two device forwards and one gradient, and zero uses none" $ do
    let (config, params, batch, direction) = trpoFloat32FisherFixture
        zero = constantGradientLike params 0.0
    forwardCalls <- newIORef (0 :: Int)
    gradientCalls <- newIORef (0 :: Int)
    let device =
          float32RoundingMlpDeviceForTest
            { mlpdForwardBatch = \current observations -> do
                modifyIORef' forwardCalls (+ 1)
                mlpdForwardBatch float32RoundingMlpDeviceForTest current observations
            , mlpdBatchGradient = \current samples -> do
                modifyIORef' gradientCalls (+ 1)
                mlpdBatchGradient float32RoundingMlpDeviceForTest current samples
            }
    zeroResult <- PpoTrainer.trpoFisherVectorProductDevice device config batch params zero
    zeroResult @?= Right zero
    readIORef forwardCalls >>= (@?= 0)
    readIORef gradientCalls >>= (@?= 0)
    -- Even the smallest subnormal is nonzero: it must take the device
    -- path although its undamped product may correctly round to zero.
    let smallestSubnormal = encodeFloat 1 (-1074) :: Double
    subnormalResult <-
      PpoTrainer.trpoFisherVectorProductDevice
        device
        config
        batch
        params
        (mapGradientForTest (* smallestSubnormal) direction)
    subnormal <- either (assertFailure . Text.unpack) pure subnormalResult
    assertBool "subnormal Fisher produced a non-finite result" (gradientAllFinite subnormal)
    readIORef forwardCalls >>= (@?= 2)
    readIORef gradientCalls >>= (@?= 1)

fisherInvalidInputsTest :: TestTree
fisherInvalidInputsTest =
  testCase
    "device TRPO Fisher validates zero directions and rejects invalid or overflowing inputs before dispatch"
    $ do
      let (config, params, batch, _) = trpoFloat32FisherFixture
          zero = constantGradientLike params 0.0
      calls <- newIORef (0 :: Int)
      let forbiddenDevice =
            pureReferenceMlpDevice
              { mlpdForwardBatch = \_ _ -> do
                  modifyIORef' calls (+ 1)
                  pure (Left "unexpected device call")
              , mlpdBatchGradient = \_ _ -> do
                  modifyIORef' calls (+ 1)
                  pure (Left "unexpected device call")
              }
          run = PpoTrainer.trpoFisherVectorProductDevice forbiddenDevice
      Control.Monad.forM_
        [ config {PpoTrainer.ppoTrpoCgDamping = -0.1}
        , config {PpoTrainer.ppoTrpoCgDamping = 0.0 / 0.0}
        , config {PpoTrainer.ppoTrpoCgDamping = 1.0 / 0.0}
        , config {PpoTrainer.ppoKlTarget = 0.0}
        , config {PpoTrainer.ppoVariant = PpoTrainer.VariantPPO}
        ]
        $ \invalidConfig ->
          assertLeftContains "configuration" (run invalidConfig batch params zero)
      assertLeftContains "parameters do not match" $
        run config batch (params {Mlp.paramShape = Mlp.MlpShape 4 2 3}) zero
      assertLeftContains "malformed rollout batch" (run config [] params zero)
      let malformedPolicy =
            [ (step {PpoTrainer.rsPolicy = Data.Vector.Unboxed.fromList [0.0, 0.0]}, advantage, target)
            | (step, advantage, target) <- batch
            ]
      assertLeftContains "malformed rollout batch" (run config malformedPolicy params zero)
      Control.Monad.forM_ [0.0 / 0.0, 1.0 / 0.0] $ \invalidValue ->
        assertLeftContains "direction is malformed or non-finite" $
          run config batch params (constantGradientLike params invalidValue)
      assertLeftContains "direction is malformed or non-finite" $
        run config batch params (zero {Mlp.gradW2 = Data.Vector.Unboxed.empty})
      assertLeftContains "direction norm is not representable" $
        run config batch params (constantGradientLike params 1.0e308)
      readIORef calls >>= (@?= 0)

fisherDeviceFailureTest :: TestTree
fisherDeviceFailureTest =
  testCase "device TRPO Fisher propagates device failures and rejects non-finite results" $ do
    let (config, params, batch, direction) = trpoFloat32FisherFixture
        run device = PpoTrainer.trpoFisherVectorProductDevice device config batch params
    assertLeftContains "Fisher forward unavailable" $
      run (failingForwardBatchDevice "Fisher forward unavailable") direction
    assertLeftContains "Fisher gradient unavailable" $
      run (failingBatchGradientDevice "Fisher gradient unavailable") direction
    let malformedGradientDevice =
          pureReferenceMlpDevice
            { mlpdBatchGradient = \_ _ -> pure (Right (constantGradientLike params (0.0 / 0.0)))
            }
        overflowingProductDevice =
          pureReferenceMlpDevice
            { mlpdBatchGradient = \_ _ -> pure (Right (constantGradientLike params 1.0e308))
            }
    assertLeftContains "gradient is malformed or non-finite" $
      run malformedGradientDevice direction
    assertLeftContains "product is non-finite" $
      run overflowingProductDevice (mapGradientForTest (* 10.0) direction)

assertLeftContains :: Text -> IO (Either Text a) -> Assertion
assertLeftContains expected action = do
  result <- action
  case result of
    Left err ->
      assertBool
        ("expected error to contain " <> Text.unpack expected <> ", got " <> Text.unpack err)
        (expected `Text.isInfixOf` err)
    Right _ -> assertFailure ("expected Left containing " <> Text.unpack expected)

failingForwardBatchDevice :: Text -> MlpDevice
failingForwardBatchDevice message =
  pureReferenceMlpDevice
    { mlpdForwardBatch = \_ _ -> pure (Left message)
    }

failingBatchGradientDevice :: Text -> MlpDevice
failingBatchGradientDevice message =
  pureReferenceMlpDevice
    { mlpdBatchGradient = \_ _ -> pure (Left message)
    }

mkTrpoStep
  :: PpoTrainer.PpoTrainConfig
  -> Mlp.MlpParams
  -> ([Double], Int, Double)
  -> (PpoTrainer.RolloutStep, Double, Double)
mkTrpoStep config params (observationValues, action, advantage) =
  let observation = Data.Vector.Unboxed.fromList observationValues
      output =
        Mlp.policyValueForwardWith
          Mlp.LinearValueHead
          params
          (PpoTrainer.ppoActionCount config)
          observation
      probability = Mlp.pvPolicy output Data.Vector.Unboxed.! action
   in ( PpoTrainer.RolloutStep
          { PpoTrainer.rsObs = observation
          , PpoTrainer.rsAction = action
          , PpoTrainer.rsLogProb = log probability
          , PpoTrainer.rsValue = Mlp.pvValue output
          , PpoTrainer.rsReward = 0.0
          , PpoTrainer.rsBoundary = PpoTrainer.RolloutContinues
          , PpoTrainer.rsPolicy = Mlp.pvPolicy output
          , PpoTrainer.rsActionMask = Nothing
          , PpoTrainer.rsRecurrentState = Data.Vector.Unboxed.empty
          }
      , advantage
      , 0.0
      )

gradientVector :: Int -> Double -> Data.Vector.Unboxed.Vector Double
gradientVector size scale =
  Data.Vector.Unboxed.generate
    size
    (\index -> scale * fromIntegral ((index `mod` 7) - 3))

smallTrpoConfig :: PpoTrainer.PpoTrainConfig
smallTrpoConfig =
  PpoTrainer.defaultPpoTrainConfig
    { PpoTrainer.ppoSeed = 31
    , PpoTrainer.ppoHiddenUnits = 4
    , PpoTrainer.ppoActionCount = 2
    , PpoTrainer.ppoObsSize = 4
    , PpoTrainer.ppoVariant = PpoTrainer.VariantTRPO
    }

-- A non-saturated single-hidden-unit policy gives observable Fisher curvature
-- in one actor weight. This is also the real-Metal counterexample fixture.

trpoFloat32FisherFixture
  :: ( PpoTrainer.PpoTrainConfig
     , Mlp.MlpParams
     , [(PpoTrainer.RolloutStep, Double, Double)]
     , Mlp.MlpGradient
     )
trpoFloat32FisherFixture =
  (config, params, batch, direction)
 where
  config = smallTrpoConfig {PpoTrainer.ppoHiddenUnits = 1, PpoTrainer.ppoTrpoCgDamping = 0.1}
  params =
    Mlp.MlpParams
      (Mlp.MlpShape 4 1 3)
      (Data.Vector.Unboxed.fromList [0.25, 0.0, 0.0, 0.0])
      (Data.Vector.Unboxed.singleton 0.2)
      (Data.Vector.Unboxed.fromList [0.3, -0.2, 0.1])
      (Data.Vector.Unboxed.fromList [0.1, -0.1, 0.0])
  batch = [mkTrpoStep config params ([0.4, 0.0, 0.0, 0.0], 0, 1.0)]
  direction =
    (constantGradientLike params 0.0)
      { Mlp.gradW2 = Data.Vector.Unboxed.fromList [1.0, 0.0, 0.0]
      }

-- Model the binary32 ABI boundary, without claiming to execute a substrate.
-- The production function still has to use the injected forward/gradient seam.

float32RoundingMlpDeviceForTest :: MlpDevice
float32RoundingMlpDeviceForTest =
  pureReferenceMlpDevice
    { mlpdForwardBatch = \params observations -> do
        outputs <-
          mlpdForwardBatch pureReferenceMlpDevice (roundParams params) (fmap roundVector observations)
        pure (fmap (fmap roundVector) outputs)
    , mlpdBatchGradient = \params samples -> do
        gradient <-
          mlpdBatchGradient
            pureReferenceMlpDevice
            (roundParams params)
            [(roundVector observation, roundVector upstream) | (observation, upstream) <- samples]
        pure (fmap (mapGradientForTest roundScalar) gradient)
    }
 where
  roundScalar value = realToFrac (realToFrac value :: Float)
  roundVector = Data.Vector.Unboxed.map roundScalar
  roundParams params =
    params
      { Mlp.paramW1 = roundVector (Mlp.paramW1 params)
      , Mlp.paramB1 = roundVector (Mlp.paramB1 params)
      , Mlp.paramW2 = roundVector (Mlp.paramW2 params)
      , Mlp.paramB2 = roundVector (Mlp.paramB2 params)
      }

maxGradientDifferenceForTest :: Mlp.MlpGradient -> Mlp.MlpGradient -> Double
maxGradientDifferenceForTest left right =
  maximum
    [ Data.Vector.Unboxed.foldl'
        max
        0.0
        (Data.Vector.Unboxed.zipWith (\a b -> abs (a - b)) leftValues rightValues)
    | (leftValues, rightValues) <-
        [ (Mlp.gradW1 left, Mlp.gradW1 right)
        , (Mlp.gradB1 left, Mlp.gradB1 right)
        , (Mlp.gradW2 left, Mlp.gradW2 right)
        , (Mlp.gradB2 left, Mlp.gradB2 right)
        ]
    ]

constantGradientLike :: Mlp.MlpParams -> Double -> Mlp.MlpGradient
constantGradientLike params value =
  Mlp.MlpGradient
    { Mlp.gradW1 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramW1 params)) value
    , Mlp.gradB1 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramB1 params)) value
    , Mlp.gradW2 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramW2 params)) value
    , Mlp.gradB2 = Data.Vector.Unboxed.replicate (Data.Vector.Unboxed.length (Mlp.paramB2 params)) value
    }

deterministicGradientLike :: Mlp.MlpParams -> Mlp.MlpGradient
deterministicGradientLike params =
  Mlp.MlpGradient
    { Mlp.gradW1 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramW1 params)) 0.01
    , Mlp.gradB1 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramB1 params)) 0.02
    , Mlp.gradW2 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramW2 params)) 0.015
    , Mlp.gradB2 = gradientVector (Data.Vector.Unboxed.length (Mlp.paramB2 params)) 0.025
    }

mapGradientForTest :: (Double -> Double) -> Mlp.MlpGradient -> Mlp.MlpGradient
mapGradientForTest f gradient =
  Mlp.MlpGradient
    { Mlp.gradW1 = Data.Vector.Unboxed.map f (Mlp.gradW1 gradient)
    , Mlp.gradB1 = Data.Vector.Unboxed.map f (Mlp.gradB1 gradient)
    , Mlp.gradW2 = Data.Vector.Unboxed.map f (Mlp.gradW2 gradient)
    , Mlp.gradB2 = Data.Vector.Unboxed.map f (Mlp.gradB2 gradient)
    }

gradientDotForTest :: Mlp.MlpGradient -> Mlp.MlpGradient -> Double
gradientDotForTest left right =
  Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradW1 left) (Mlp.gradW1 right))
    + Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradB1 left) (Mlp.gradB1 right))
    + Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradW2 left) (Mlp.gradW2 right))
    + Data.Vector.Unboxed.sum (Data.Vector.Unboxed.zipWith (*) (Mlp.gradB2 left) (Mlp.gradB2 right))

gradientAllFinite :: Mlp.MlpGradient -> Bool
gradientAllFinite gradient =
  all
    (Data.Vector.Unboxed.all (\value -> not (isNaN value || isInfinite value)))
    [ Mlp.gradW1 gradient
    , Mlp.gradB1 gradient
    , Mlp.gradW2 gradient
    , Mlp.gradB2 gradient
    ]
