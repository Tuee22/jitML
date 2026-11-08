{-# LANGUAGE OverloadedStrings #-}

module OnPolicyHorizon (onPolicyHorizonTests) where

import Control.Monad (forM_, when)
import Data.IORef (atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import System.Mem (performGC)
import System.Mem.Weak (deRefWeak, mkWeakPtr)
import System.Random qualified as Random
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.CountExploration qualified as Count
import JitML.RL.RewardShaping qualified as Shaping
import JitML.RL.Simulator qualified as Sim
import JitML.RL.VecEnv qualified as Vec

onPolicyHorizonTests :: TestTree
onPolicyHorizonTests =
  testGroup
    "on-policy time-limit bootstrap"
    [ testCase "GAE bootstraps truncation but stops lambda recurrence across the reset" $ do
        let steps =
              [ step Ppo.RolloutContinues 2.0 1.0
              , step (Ppo.RolloutTruncated 7.0) 3.0 2.0
              , step Ppo.RolloutTerminated 100.0 1.0
              ]
            (advantages, targets) = Ppo.computeAdvantages config (Ppo.Rollout steps [] 999.0)
        assertNear [5.516, 5.3, -99.0] advantages
        assertNear [7.516, 8.3, 1.0] targets
        fmap Ppo.rsDone steps @?= [False, True, True]
        let (continuing, _) = Ppo.computeAdvantages config (Ppo.Rollout [step Ppo.RolloutContinues 2.0 1.0] [] 9.0)
        assertNear [7.1] continuing
    , testCase "VecEnv separates terminal and time-limit flags without changing reset state or RNG" $
        forM_ [(False, 1, False, True), (True, 1, True, False), (False, 3, False, False)] $ \(terminated, horizon, expectedTerminal, expectedTruncated) -> do
          let current =
                environment
                  { Sim.envStep = \_ _ -> Sim.SimStep 10 1.0 terminated
                  , Sim.envTrainingStart = Just (\_ _ -> 99)
                  }
              initial = Vec.VecEnv current [Vec.VecEnvSlot 0 0.0 0]
              generator = Random.mkStdGen 42
              (after, transitions, nextGenerator) = Vec.vecEnvStep horizon initial [0] generator
              ended = expectedTerminal || expectedTruncated
              (_, afterFirstDraw) = Random.uniformR (0.0 :: Double, 1.0) generator
              (_, afterSecondDraw) = Random.uniformR (0.0 :: Double, 1.0) afterFirstDraw
          length transitions @?= 1
          transition <- case transitions of
            [value] -> pure value
            _ -> assertFailure "VecEnv changed the number of physical transitions"
          Vec.vecTransitionTerminated transition @?= expectedTerminal
          Vec.vecTransitionTruncated transition @?= expectedTruncated
          Vec.vecTransitionDone transition @?= ended
          Vec.vecTransitionNextState transition @?= 10
          Vec.vecTransitionNextObservation transition @?= VU.singleton 10.0
          fmap Vec.vecSlotState (Vec.vecEnvSlots after) @?= [if ended then 99 else 10]
          Vec.vecTransitionCompletedLength transition @?= if ended then Just 1 else Nothing
          nextGenerator @?= if ended then afterSecondDraw else generator
    , testCase "pure collector values the pre-reset truncated successor with unchanged sampling RNG" $ do
        count <- Count.newCountTable
        let generator = Random.mkStdGen 42
        (rollout, finalState, finalGenerator) <-
          Ppo.collectRolloutInEnvironment count environment config params 0 generator
        finalState @?= 0
        length (Ppo.rolloutSteps rollout) @?= 2
        Ppo.rolloutFinalValue rollout @?= 0.0
        forM_ (Ppo.rolloutSteps rollout) $ \sample -> case Ppo.rsBoundary sample of
          Ppo.RolloutTruncated value -> assertNear [5.0] [value]
          other -> assertFailure ("missing pure truncation successor: " <> show other)
        let (advantages, targets) = Ppo.computeAdvantages config rollout
            (_, afterFirstDraw) = Random.uniformR (0.0 :: Double, 1.0) generator
            (_, afterSecondDraw) = Random.uniformR (0.0 :: Double, 1.0) afterFirstDraw
        assertNear [3.5, 3.5] advantages
        assertNear [5.5, 5.5] targets
        finalGenerator @?= afterSecondDraw
    , testCase "device collector values only actual truncated successors through the same frozen device" $ do
        batches <- newIORef []
        let device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \current observations -> do
                    current @?= params
                    modifyIORef' batches (<> [fmap VU.toList observations])
                    result <- mlpdForwardBatch pureReferenceMlpDevice current observations
                    pure
                      ( fmap
                          ( zipWith
                              (\observation output -> output VU.// [(2, if observation == VU.singleton 10.0 then 7.0 else 3.0)])
                              observations
                          )
                          result
                      )
                }
        (vectorized, finalEnvironment, _) <- collect device >>= expectRight
        let rollout = Ppo.vectorizedRollout vectorized
        fmap Vec.vecSlotState (Vec.vecEnvSlots finalEnvironment) @?= [0]
        fmap Ppo.rsBoundary (Ppo.rolloutSteps rollout) @?= replicate 2 (Ppo.RolloutTruncated 7.0)
        fmap snd (Ppo.vectorizedRolloutGroups vectorized) @?= [0.0]
        readIORef batches >>= (@?= [[[0.0]], [[10.0]], [[0.0]], [[10.0]]])
        let (advantages, targets) = Ppo.computeAdvantages config rollout
        assertNear [4.3, 4.3] advantages
        assertNear [7.3, 7.3] targets
    , testCase "terminal-at-horizon has no successor bootstrap device dispatch" $ do
        calls <- newIORef (0 :: Int)
        let terminal = environment {Sim.envStep = \_ _ -> Sim.SimStep 10 0.0 True}
            device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \frozenParams observations -> modifyIORef' calls (+ 1) >> mlpdForwardBatch pureReferenceMlpDevice frozenParams observations
                }
            current = config {Ppo.ppoRolloutSteps = 1}
        count <- Count.newCountTable
        let (initial, generator) = Vec.mkVecEnv terminal 1 (Random.mkStdGen 42)
        (vectorized, _, _) <-
          Ppo.collectRolloutVectorizedOnDevice device count terminal current params initial generator
            >>= expectRight
        fmap Ppo.rsBoundary (Ppo.rolloutSteps (Ppo.vectorizedRollout vectorized))
          @?= [Ppo.RolloutTerminated]
        readIORef calls >>= (@?= 1)
        let (advantages, _) = Ppo.computeAdvantages current (Ppo.vectorizedRollout vectorized)
        assertNear [-2.0] advantages
    , testCase "mixed vector slots retain their own terminal, pre-reset and continuing bootstrap values" $ do
        batches <- newIORef []
        let mixed =
              environment
                { Sim.envStep = \state _ -> Sim.SimStep (state + 10) 1.0 (state == 0)
                , Sim.envTrainingStart = Just (\_ _ -> 99)
                }
            current = config {Ppo.ppoRolloutSteps = 1, Ppo.ppoMaxEpisodeSteps = 2}
            initial =
              Vec.VecEnv
                mixed
                [Vec.VecEnvSlot 0 0.0 1, Vec.VecEnvSlot 1 0.0 1, Vec.VecEnvSlot 2 0.0 0, Vec.VecEnvSlot 3 0.0 0]
            device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \frozen observations -> do
                    frozen @?= params
                    assertBool
                      "a reset state was incorrectly used for bootstrap"
                      (VU.singleton 99.0 `notElem` observations)
                    modifyIORef' batches (<> [fmap VU.toList observations])
                    result <- mlpdForwardBatch pureReferenceMlpDevice frozen observations
                    pure
                      ( fmap
                          (zipWith (\observation output -> output VU.// [(2, 100.0 + VU.head observation)]) observations)
                          result
                      )
                }
        count <- Count.newCountTable
        (vectorized, _, _) <-
          Ppo.collectRolloutVectorizedOnDevice device count mixed current params initial (Random.mkStdGen 42)
            >>= expectRight
        let groups = Ppo.vectorizedRolloutGroups vectorized
        fmap Ppo.rsBoundary (Ppo.rolloutSteps (Ppo.vectorizedRollout vectorized))
          @?= [Ppo.RolloutTerminated, Ppo.RolloutTruncated 111.0, Ppo.RolloutContinues, Ppo.RolloutContinues]
        fmap snd groups @?= [0.0, 0.0, 112.0, 113.0]
        readIORef batches >>= (@?= [[[0.0], [1.0], [2.0], [3.0]], [[11.0]], [[12.0], [13.0]]])
        assertNear
          [-99.0, -0.1, -0.2, -0.3]
          ( concatMap
              (\(samples, final) -> fst (Ppo.computeAdvantages current (Ppo.Rollout samples [] final)))
              groups
          )
    , testCase "true-terminal shaping ignores successor potential in pure and device collectors" $
        forM_ [VU.fromList [0.5, 0.0], VU.fromList [0.6, 1.05]] $ \successor -> do
          let current = shapingEnvironment True successor
              initial = Vec.VecEnv current [Vec.VecEnvSlot shapingStart 0.0 0]
              generator = Random.mkStdGen 42
              expectedReward = 1.0 - Shaping.shapingPotential "mountain-car" shapingStart
          pureCount <- Count.newCountTable
          (pureRollout, pureFinal, pureGenerator) <-
            Ppo.collectRolloutInEnvironment pureCount current shapingConfig shapingParams shapingStart generator
          deviceCount <- Count.newCountTable
          (vectorized, deviceFinal, deviceGenerator) <-
            Ppo.collectRolloutVectorizedOnDevice
              pureReferenceMlpDevice
              deviceCount
              current
              shapingConfig
              shapingParams
              initial
              generator
              >>= expectRight
          forM_ [pureRollout, Ppo.vectorizedRollout vectorized] $ \rollout -> do
            assertNear [expectedReward] (fmap Ppo.rsReward (Ppo.rolloutSteps rollout))
            fmap Ppo.rsBoundary (Ppo.rolloutSteps rollout) @?= [Ppo.RolloutTerminated]
            Ppo.rolloutEpisodes rollout @?= [1.0]
            Ppo.rolloutFinalValue rollout @?= 0.0
          pureFinal @?= shapingReset
          fmap Vec.vecSlotState (Vec.vecEnvSlots deviceFinal) @?= [shapingReset]
          deviceGenerator @?= pureGenerator
    , testCase "discounted terminal shaping leaves only the initial-state offset" $
        forM_ [0.0, 0.9, 1.0] $ \gamma -> do
          let successors =
                [ VU.fromList [-0.7, -0.5]
                , VU.fromList [0.1, 0.8]
                , VU.fromList [0.6, 1.05]
                ]
              observations = shapingStart : successors
              bonuses =
                zipWith3
                  (Shaping.shapingBonusForTransition "mountain-car" gamma)
                  [False, False, True]
                  observations
                  successors
              rawRewards = [2.0, -1.0, 5.0]
              discounted = sum . zipWith (*) [gamma ^ index | index <- [0 :: Int ..]]
              initialPotential = Shaping.shapingPotential "mountain-car" shapingStart
          assertNear [negate initialPotential] [discounted bonuses]
          assertNear
            [discounted rawRewards - initialPotential]
            [discounted (zipWith (+) rawRewards bonuses)]
    , testCase
        "continuation and actual VecEnv truncation preserve shaping cancellation in successor bootstrap"
        $ forM_ [1, 2]
        $ \horizon -> do
          batches <- newIORef []
          let successor = VU.fromList [0.4, 0.7]
              current = shapingEnvironment False successor
              currentConfig = shapingConfig {Ppo.ppoMaxEpisodeSteps = horizon}
              initial = Vec.VecEnv current [Vec.VecEnvSlot shapingStart 0.0 0]
              initialPotential = Shaping.shapingPotential "mountain-car" shapingStart
              successorPotential = Shaping.shapingPotential "mountain-car" successor
              successorValue = 7.0 - successorPotential
              shapedValue observation =
                (if observation == shapingStart then 3.0 else 7.0)
                  - Shaping.shapingPotential "mountain-car" observation
              device =
                pureReferenceMlpDevice
                  { mlpdForwardBatch = \frozen observations -> do
                      frozen @?= shapingParams
                      assertBool "reset observation entered shaping bootstrap" (shapingReset `notElem` observations)
                      modifyIORef' batches (<> [observations])
                      result <- mlpdForwardBatch pureReferenceMlpDevice frozen observations
                      pure
                        ( fmap
                            ( zipWith
                                (\observation output -> output VU.// [(2, shapedValue observation)])
                                observations
                            )
                            result
                        )
                  }
          count <- Count.newCountTable
          (vectorized, finalEnvironment, _) <-
            Ppo.collectRolloutVectorizedOnDevice
              device
              count
              current
              currentConfig
              shapingParams
              initial
              (Random.mkStdGen 42)
              >>= expectRight
          let rollout = Ppo.vectorizedRollout vectorized
              (advantages, targets) = Ppo.computeAdvantages currentConfig rollout
          assertNear
            [1.0 + 0.9 * successorPotential - initialPotential]
            (fmap Ppo.rsReward (Ppo.rolloutSteps rollout))
          fmap Ppo.rsBoundary (Ppo.rolloutSteps rollout)
            @?= [if horizon == 1 then Ppo.RolloutTruncated successorValue else Ppo.RolloutContinues]
          assertNear [1.0 + 0.9 * 7.0 - 3.0] advantages
          assertNear [1.0 + 0.9 * 7.0 - initialPotential] targets
          fmap Vec.vecSlotState (Vec.vecEnvSlots finalEnvironment)
            @?= [if horizon == 1 then shapingReset else successor]
          readIORef batches >>= (@?= [[shapingStart], [successor]])
    , testCase "environments without potentials retain raw rewards across every transition boundary"
        $ forM_
          ["cartpole", "lunar-lander", "gridworld-deterministic", "pendulum", "on-policy-horizon-control"]
        $ \name ->
          forM_ [False, True] $ \terminated -> do
            let rawReward = 17.0
                bonus = Shaping.shapingBonusForTransition name 0.9 terminated shapingStart shapingReset
            bonus @?= 0.0
            rawReward + bonus @?= rawReward
    , testCase "failed or malformed truncation successor output rejects the entire device rollout"
        $ forM_
          [ (Left "successor device unavailable", "device forward failed")
          , (Right [], "unexpected output count")
          , (Right [VU.fromList [0.0, 0.0]], "unexpected output width")
          , (Right [VU.fromList [0.0, 0.0, 0.0 / 0.0]], "non-finite output")
          ]
        $ \(badResult, expected) -> do
          let device =
                pureReferenceMlpDevice
                  { mlpdForwardBatch = \current observations ->
                      if observations == [VU.singleton 10.0]
                        then pure badResult
                        else mlpdForwardBatch pureReferenceMlpDevice current observations
                  }
          result <- collect device
          case result of
            Left err ->
              assertBool
                (Text.unpack err)
                ("on-policy truncation bootstrap" `Text.isInfixOf` err && expected `Text.isInfixOf` err)
            Right _ -> assertFailure "truncation bootstrap failure yielded a partial rollout"
    , testCase "completed iterations release previous parameter roots before the next rollout" $ do
        gradientSeen <- newIORef False
        previous <- newIORef Nothing
        boundaries <- newIORef (0 :: Int)
        let current =
              config
                { Ppo.ppoNumIterations = 4
                , Ppo.ppoRolloutSteps = 4
                , Ppo.ppoVectorEnvCount = 2
                , Ppo.ppoMiniBatchSize = 4
                , Ppo.ppoEpochsPerUpdate = 1
                }
            device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \frozen observations -> do
                    -- Rollout/bootstrap batches have two slots; optimizer
                    -- batches have four. Inspect only the first rollout call
                    -- after a complete optimizer pass.
                    when (length observations == 2) $ do
                      updated <- atomicModifyIORef' gradientSeen (False,)
                      when updated $ do
                        performGC
                        weak <- readIORef previous
                        forM_ weak $ \key -> do
                          alive <- deRefWeak key
                          assertBool
                            "a completed iteration still retains its previous parameter root"
                            (isNothing alive)
                        key <- mkWeakPtr frozen Nothing
                        writeIORef previous (Just key)
                        modifyIORef' boundaries (+ 1)
                    mlpdForwardBatch pureReferenceMlpDevice frozen observations
                , mlpdBatchGradient = \frozen batch -> do
                    writeIORef gradientSeen True
                    mlpdBatchGradient pureReferenceMlpDevice frozen batch
                }
        prepared <- Ppo.preparePpoOnDeviceWithEnvironment device environment current
        observed <- Ppo.continuePreparedPpoRaw prepared >>= expectRight
        result <- expectRight (Ppo.refinePpoTrainObservation observed)
        length (Ppo.resultIterations result) @?= 4
        readIORef boundaries >>= (@?= 3)
    ]

config :: Ppo.PpoTrainConfig
config =
  Ppo.defaultPpoTrainConfig
    { Ppo.ppoHiddenUnits = 1
    , Ppo.ppoObsSize = 1
    , Ppo.ppoActionCount = 2
    , Ppo.ppoRolloutSteps = 2
    , Ppo.ppoVectorEnvCount = 1
    , Ppo.ppoMaxEpisodeSteps = 1
    , Ppo.ppoGamma = 0.9
    , Ppo.ppoLambda = 0.8
    , Ppo.ppoCountBeta = 0.0
    }

params :: Mlp.MlpParams
params =
  Mlp.MlpParams
    (Mlp.MlpShape 1 1 3)
    (VU.singleton 1.0)
    (VU.singleton 0.0)
    (VU.fromList [0.0, 0.0, 3.0])
    (VU.fromList [0.0, 0.0, 2.0])

shapingConfig :: Ppo.PpoTrainConfig
shapingConfig = config {Ppo.ppoObsSize = 2, Ppo.ppoRolloutSteps = 1}

shapingParams :: Mlp.MlpParams
shapingParams = params {Mlp.paramShape = Mlp.MlpShape 2 1 3, Mlp.paramW1 = VU.fromList [1.0, 0.0]}

shapingStart :: VU.Vector Double
shapingStart = VU.fromList [-0.5, 0.0]

shapingReset :: VU.Vector Double
shapingReset = VU.fromList [-1.2, -1.05]

shapingEnvironment :: Bool -> VU.Vector Double -> Sim.SimulatedEnvironment (VU.Vector Double)
shapingEnvironment terminated successor =
  Sim.SimulatedEnvironment
    { Sim.envName = "mountain-car"
    , Sim.envInitial = shapingStart
    , Sim.envStep = \_ _ -> Sim.SimStep successor 1.0 terminated
    , Sim.envRenderFrame = \state -> Sim.RenderFrame (VU.toList state) "shaping control"
    , Sim.envActionCount = 2
    , Sim.envObservationSize = 2
    , Sim.envMaxEpisodeSteps = 3
    , Sim.envActionMask = Nothing
    , Sim.envTrainingStart = Just (\_ _ -> shapingReset)
    }

-- Explicit synthetic transition/GAE controls, not ProductRow completion.
environment :: Sim.SimulatedEnvironment Int
environment =
  Sim.SimulatedEnvironment
    { Sim.envName = "on-policy-horizon-control"
    , Sim.envInitial = 0
    , Sim.envStep = \_ _ -> Sim.SimStep 10 1.0 False
    , Sim.envRenderFrame = \state -> Sim.RenderFrame [fromIntegral state] "horizon control"
    , Sim.envActionCount = 2
    , Sim.envObservationSize = 1
    , Sim.envMaxEpisodeSteps = 3
    , Sim.envActionMask = Nothing
    , Sim.envTrainingStart = Nothing
    }

collect :: MlpDevice -> IO (Either Text (Ppo.VectorizedRollout, Vec.VecEnv Int, Random.StdGen))
collect device = do
  count <- Count.newCountTable
  let (initial, generator) = Vec.mkVecEnv environment 1 (Random.mkStdGen 42)
  Ppo.collectRolloutVectorizedOnDevice device count environment config params initial generator

step :: Ppo.RolloutBoundary -> Double -> Double -> Ppo.RolloutStep
step boundary value reward =
  Ppo.RolloutStep
    { Ppo.rsObs = VU.singleton 0.0
    , Ppo.rsAction = 0
    , Ppo.rsLogProb = log 0.5
    , Ppo.rsValue = value
    , Ppo.rsReward = reward
    , Ppo.rsBoundary = boundary
    , Ppo.rsPolicy = VU.fromList [0.5, 0.5]
    , Ppo.rsActionMask = Nothing
    , Ppo.rsRecurrentState = VU.empty
    }

assertNear :: [Double] -> [Double] -> Assertion
assertNear expected actual = do
  length actual @?= length expected
  assertBool
    ("unexpected values: " <> show actual)
    (and (zipWith (\a b -> abs (a - b) < 1.0e-7) expected actual))

expectRight :: (Show error) => Either error value -> IO value
expectRight = either (assertFailure . show) pure
