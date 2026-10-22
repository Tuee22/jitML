{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Ordinary DATA controls. Tiny lower schedules are explicitly noncanonical;
-- synthetic evaluation DTOs are not claimed as actual execution or authority.
-- No capsule/result constructor, restoration, provider or qualification seam.
module NativePhaseProjection (nativePhaseProjectionTests) where

import Control.Exception (AsyncException (ThreadKilled), evaluate, throw, try)
import Control.Monad (forM_, void, (>=>))
import Data.Bits (xor)
import Data.ByteString qualified as BS
import Data.IORef (newIORef, readIORef)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import System.Random qualified as Random
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Numerics.MlpDevice (MlpDevice (..), pureReferenceMlpDevice)
import JitML.RL.Algorithms.ArsTrainer qualified as Ars
import JitML.RL.Algorithms.Common qualified as Common
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.HerTrainer qualified as Her
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.AlphaZero qualified as Game
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.PolicyValueNet qualified as Net
import JitML.RL.AlphaZero.PreparedTrainer qualified as AZ
import JitML.RL.NativeHerEvaluation qualified as HerEval
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef
import JitML.RL.PreparedNeuralAttempt qualified as Low
import JitML.RL.ProductBudget qualified as Plan
import JitML.RL.Simulator qualified as Sim

right :: (Show e) => Either e a -> IO a
right value = case value of
  Right actual -> pure actual
  Left reason -> assertFailure (show reason) >> fail "unreachable"

nodeAt :: Graph.NodePool -> Digest -> IO Schema.NodeData
nodeAt pool digest = case Graph.lookupNode digest pool of
  Just value -> pure value
  Nothing -> assertFailure "projected digest missing" >> fail "unreachable"

field :: Schema.NodeData -> Text -> IO NodeValue
field node name = case lookup name (zip (Schema.nodeFieldNames (Schema.nodeKind node)) (Schema.nodeFields node)) of
  Just value -> pure value
  Nothing -> assertFailure ("missing field " <> Text.unpack name) >> fail "unreachable"

ref :: NodeValue -> IO Digest
ref (VRef digest) = pure digest
ref other = assertFailure ("expected reference: " <> show other) >> fail "unreachable"

child :: Graph.NodePool -> Schema.NodeData -> Text -> IO Schema.NodeData
child pool parent name = field parent name >>= ref >>= nodeAt pool

projected
  :: IO (Either ProjectionFailure (Digest, Graph.NodePool)) -> IO (Schema.NodeData, Graph.NodePool)
projected action = do
  (root, pool) <- action >>= right
  closure <- right (Graph.reachableNodePool [root] pool)
  void (right (Graph.validateReachableData [root] closure))
  forM_ (Graph.nodePoolEntries closure) $ \(_, actual, bytes) -> do
    decoded <- right (Schema.decodeNodeData bytes)
    Schema.nodeFields decoded @?= Schema.nodeFields actual
  actual <- nodeAt pool root
  pure (actual, pool)

sequenceValues :: Graph.NodePool -> Schema.NodeData -> IO [NodeValue]
sequenceValues pool node = case Schema.nodeKind node of
  NSequenceManifest -> field node "children" >>= descend
  NSequenceIndex -> field node "children" >>= descend
  NReferencePage -> array "elements"
  NScalarPage -> array "elements"
  _ -> assertFailure "expected sequence node" >> fail "unreachable"
 where
  array name =
    field node name >>= \case
      VList items -> pure items
      _ -> assertFailure "expected sequence array" >> fail "unreachable"
  descend (VList children) = concat <$> traverse (\value -> ref value >>= nodeAt pool >>= sequenceValues pool) children
  descend _ = assertFailure "expected sequence children" >> fail "unreachable"

sequenceField :: Graph.NodePool -> Schema.NodeData -> Text -> IO [NodeValue]
sequenceField pool node name = child pool node name >>= sequenceValues pool

tensorBits :: Graph.NodePool -> Schema.NodeData -> IO [Word64]
tensorBits pool node = case Schema.nodeKind node of
  NTensorLeaf -> field node "rawF64Bytes" >>= decode
  NTensorChunk -> field node "rawF64Bytes" >>= decode
  NTensorManifest -> do
    value <- field node "chunks"
    case value of
      VList refs -> concat <$> traverse (\value_ -> ref value_ >>= nodeAt pool >>= tensorBits pool) refs
      _ -> assertFailure "tensor manifest chunks" >> fail "unreachable"
  _ -> assertFailure "expected tensor" >> fail "unreachable"
 where
  decode (VBytes bytes) =
    pure
      [ BS.foldl' (\n b -> n * 256 + fromIntegral b) 0 (BS.take 8 (BS.drop i bytes))
      | i <- [0, 8 .. BS.length bytes - 1]
      ]
  decode _ = assertFailure "expected tensor bytes" >> fail "unreachable"

paramsBits :: Graph.NodePool -> Schema.NodeData -> IO [[Word64]]
paramsBits pool node = traverse (child pool node >=> tensorBits pool) ["w1", "b1", "w2", "b2"]

actualParamsBits :: Mlp.MlpParams -> [[Word64]]
actualParamsBits value =
  map
    (map castDoubleToWord64 . VU.toList)
    [Mlp.paramW1 value, Mlp.paramB1 value, Mlp.paramW2 value, Mlp.paramB2 value]

assertParams :: Graph.NodePool -> Schema.NodeData -> Text -> Mlp.MlpParams -> Assertion
assertParams pool node name expected = do
  p <- child pool node name
  paramsBits pool p >>= (@?= actualParamsBits expected)
  field p "shape"
    >>= ( @?=
            VList
              [ VInt (fromIntegral (Mlp.mlpInputs shape))
              , VInt (fromIntegral (Mlp.mlpHidden shape))
              , VInt (fromIntegral (Mlp.mlpOutputs shape))
              ]
        )
 where
  shape = Mlp.paramShape expected

-- Real lower capsules; only the returned immutable observations are pooled.
data NeuralFixture = NeuralFixture Text Low.NeuralSnapshot Low.NeuralReturnedData

boundaryPlan :: Text -> Text -> IO Plan.CompiledRlPlan
boundaryPlan kind environment = do
  base <-
    right
      ( Plan.compileRlPlan
          (Plan.TrainingPlan kind environment 42 1 1 (Just 1) Nothing Nothing)
          (Plan.EvaluationPlan 1)
      )
  bounded <- case Plan.compiledRlSchedule base of
    Just Plan.OnPolicyTrainingSchedule {} -> pure (Plan.OnPolicyTrainingSchedule 0 0 1 1 1)
    Just Plan.FixedStepTrainingSchedule {} -> pure (Plan.FixedStepTrainingSchedule 0 0 1)
    Just Plan.HerTrainingSchedule {} -> pure (Plan.HerTrainingSchedule 0 0 6)
    _ -> assertFailure "unexpected fixture family" >> fail "unreachable"
  pure (base {Plan.compiledRlSchedule = Just bounded})

neuralFixtures :: IO [NeuralFixture]
neuralFixtures =
  traverse
    make
    [ ("ppo", "cartpole")
    , ("dqn", "cartpole")
    , ("qrdqn", "cartpole")
    , ("ddpg", "pendulum")
    , ("her", "goal-reaching")
    ]
 where
  make (kind, environment) = do
    plan <- boundaryPlan kind environment
    initialResult <- Low.prepareNeuralAttempt pureReferenceMlpDevice plan
    initial <- case initialResult of
      Low.NeuralPreparationReady actual -> pure actual
      Low.NeuralPreparationFailed failure -> assertFailure (show failure) >> fail "unreachable"
    effectiveResult <- Low.initializePreparedNeural initial
    effective <- case effectiveResult of
      Low.NeuralInitializationReady actual -> pure actual
      Low.NeuralInitializationFailed failure -> assertFailure (show failure) >> fail "unreachable"
    result <- Low.runPreparedNeuralRaw effective
    returned <- case result of
      Low.NeuralTrainingReturned pending -> pure (Low.neuralPendingReturnedData pending)
      _ -> assertFailure "bounded fixture did not return materialized data" >> fail "unreachable"
    pure (NeuralFixture kind (Low.neuralEffectiveSnapshot effective) returned)

smallArs :: Ars.ArsTrainConfig
smallArs =
  Ars.defaultArsTrainConfig
    { Ars.arsIterations = 1
    , Ars.arsNumDirections = 2
    , Ars.arsTopB = 1
    , Ars.arsMaxEpisodeSteps = 1
    }

smallDqn :: Dqn.DqnTrainConfig
smallDqn = Dqn.defaultDqnTrainConfig {Dqn.dqnHiddenUnits = 2, Dqn.dqnNumSteps = 0}

returnFixture :: IO Return.RawNativeReturnEvaluation
returnFixture = do
  spec <- right (ReturnRef.canonicalNativeReturnSpec "DQN" "cartpole")
  let params = Mlp.mlpInit (Mlp.MlpShape 4 2 2) 42
  pure
    ( Return.RawNativeReturnEvaluation
        spec
        (Return.NativeNeuralEvaluation (Return.NativeDqn smallDqn params))
        []
        []
        Return.NativeEvaluationComplete
        (Return.NativeCompleteWork 0)
        Nothing
    )

herFixture :: IO HerEval.RawNativeHerEvaluation
herFixture = do
  spec <- right HerRef.canonicalNativeHerReferenceSpec
  schedule <- right (HerRef.generateNativeHerGoalSchedule spec)
  let config = Her.defaultHerTrainConfig {Her.herHiddenUnits = 2}
  pure
    ( HerEval.RawNativeHerEvaluation
        schedule
        config
        (Her.initialHerParams config)
        []
        []
        HerEval.NativeHerEvaluationComplete
        (HerEval.NativeHerCompleteWork 0)
        Nothing
    )

-- Runtime read + NOINLINE bit operation prevents literal floating CSE from
-- turning the intended negative-zero/NaN fixture into a numeric no-op.
{-# NOINLINE fromRuntimeWord #-}
fromRuntimeWord :: Word64 -> Double
fromRuntimeWord = castWord64ToDouble
{-# NOINLINE toggleRuntimeSign #-}
toggleRuntimeSign :: Double -> Double
toggleRuntimeSign value = castWord64ToDouble (castDoubleToWord64 value `xor` 0x8000000000000000)

runtimeDouble :: Word64 -> IO Double
runtimeDouble word = newIORef word >>= readIORef >>= evaluate . fromRuntimeWord

nativePhaseProjectionTests :: TestTree
nativePhaseProjectionTests =
  testGroup
    "bounded public native phase DATA projections"
    [ withResource neuralFixtures (const (pure ())) $ \fixtures ->
        testGroup
          "actual five-family bounded observations"
          [ testCase
              "all five prepared snapshots retain actual initial parameter bits and distinct family kinds"
              $ do
                values <- fixtures
                length values @?= 5
                forM_ (zip values [NPpoSnapshot, NDqnSnapshot, NQrSnapshot, NContinuousSnapshot, NHerSnapshot]) $ \(NeuralFixture _ snapshot _, expectedKind) -> do
                  (node, pool) <- projected (projectNeuralSnapshotData Graph.emptyNodePool snapshot)
                  Schema.nodeKind node @?= expectedKind
                  let name = if expectedKind == NContinuousSnapshot then "actor" else "initialParams"
                  assertParams pool node name (Low.neuralSnapshotInitialParams snapshot)
          , testCase "all five zero-work raw returns remain uncensored data with full compiled transport" $ do
              values <- fixtures
              forM_ values $ \(NeuralFixture _ _ raw) -> do
                (node, pool) <- projected (projectNeuralReturnedData Graph.emptyNodePool raw)
                Schema.nodeKind node @?= NRawNeural
                field node "actualLowBoundCompiledTransport"
                  >>= (@?= VText (Plan.renderCompiledRlPlanTransport (Low.neuralReturnedPlan raw)))
                field node "observedTransitions" >>= (@?= VWord 0)
                field node "observedUpdates" >>= (@?= VWord 0)
                sequenceField pool node "statistics" >>= (@?= [])
          , testCase
              "expected and actual initial parameters remain separate fields even when exact values intern together"
              $ do
                values <- fixtures
                forM_ values $ \(NeuralFixture _ _ raw) -> do
                  (node, pool) <- projected (projectNeuralReturnedData Graph.emptyNodePool raw)
                  assertParams pool node "expectedInitial" (Low.neuralReturnedExpectedInitialParams raw)
                  field node "expectedInitial" >>= \expected -> field node "actualInitial" >>= (@?= expected)
                  field node "actualInitial" >>= \initial -> field node "actualFinal" >>= (@?= initial)
          , testCase "reprojection into an ambient pool is byte deterministic and adds no duplicate nodes" $ do
              values <- fixtures
              forM_ values $ \(NeuralFixture _ snapshot _) -> do
                first@(root, pool) <- projectNeuralSnapshotData Graph.emptyNodePool snapshot >>= right
                second <- projectNeuralSnapshotData pool snapshot >>= right
                fst second @?= root
                map (\(d, _, b) -> (d, b)) (Graph.nodePoolEntries (snd second))
                  @?= map (\(d, _, b) -> (d, b)) (Graph.nodePoolEntries (snd first))
          , testCase
              "captured immutable snapshot still projects original parameters after its actual continuation returned"
              $ do
                values <- fixtures
                forM_ values $ \(NeuralFixture _ snapshot raw) -> do
                  actualParamsBits (Low.neuralSnapshotInitialParams snapshot)
                    @?= actualParamsBits (Low.neuralReturnedExpectedInitialParams raw)
          ]
    , testCase
        "recurrent KeyDoor prepared frames retain actual127 coordinates and independent slot summaries"
        $ do
          let config =
                Ppo.defaultPpoTrainConfig
                  { Ppo.ppoVariant = Ppo.VariantRecurrentPPO
                  , Ppo.ppoHiddenUnits = 2
                  , Ppo.ppoVectorEnvCount = 4
                  , Ppo.ppoObsSize = 127
                  , Ppo.ppoActionCount = 6
                  , Ppo.ppoNumIterations = 0
                  }
          prepared <-
            Ppo.preparePpoOnDeviceWithEnvironment pureReferenceMlpDevice Sim.keyDoorGridEnvironment config
          let snapshot = Ppo.preparedPpoSnapshot prepared
          (node, pool) <- projected (projectPpoSnapshotData Graph.emptyNodePool snapshot)
          frames <- sequenceField pool node "frames"
          actualFrames <- traverse (\value -> ref value >>= nodeAt pool >>= tensorBits pool) frames
          actualFrames @?= map (map castDoubleToWord64 . VU.toList) (Ppo.ppoPreparedFrames snapshot)
          map length actualFrames @?= replicate 4 127
          slots <- sequenceField pool node "vectorSlots"
          length slots @?= 4
          field node "singleState" >>= (@?= VList [VWord 0])
    , testCase "single-state PPO marks presence without inventing a resumable simulator codec" $ do
        prepared <-
          Ppo.preparePpoInEnvironment
            Sim.cartPoleEnvironment
            (Ppo.defaultPpoTrainConfig {Ppo.ppoHiddenUnits = 2, Ppo.ppoNumIterations = 0})
        (node, pool) <-
          projected (projectPpoSnapshotData Graph.emptyNodePool (Ppo.preparedPpoSnapshot prepared))
        field node "singleState" >>= (@?= VList [VWord 1])
        sequenceField pool node "vectorSlots" >>= (@?= [])
        sequenceField pool node "countEntries" >>= (@?= [])
    , testCase "actual DQN prepared RNG records exactly the public two-word SeedGen projection" $ do
        prepared <- Dqn.prepareDqnOnCartpole smallDqn
        let snapshot = Dqn.preparedDqnSnapshot prepared
        (node, pool) <- projected (projectDqnSnapshotData Graph.emptyNodePool snapshot)
        generator <- child pool node "generator"
        field generator "words"
          >>= (@?= VList (map VWord (NE.toList (Random.toSeed64 (Dqn.dqnPreparedGenerator snapshot)))))
        field generator "representation" >>= (@?= VText "stdgen-seedgen-toSeed64-v1")
        field node "state" >>= (@?= VList [VWord 0])
    , testCase
        "actual SAC cold and effective snapshots retain warm Adam count and target presence separately"
        $ do
          let config =
                (Continuous.defaultContinuousTrainConfig Continuous.VariantSAC)
                  { Continuous.ctHidden = 2
                  , Continuous.ctNumSteps = 0
                  , Continuous.ctEnvName = "pendulum"
                  }
          cold <-
            Continuous.prepareContinuousOnDeviceWithEnvironment
              pureReferenceMlpDevice
              Sim.pendulumEnvironment
              config
          let coldSnapshot = Continuous.preparedContinuousColdSnapshot cold
          (before, _) <- projected (projectContinuousSnapshotData Graph.emptyNodePool coldSnapshot)
          field before "stage" >>= (@?= VWord 0)
          field before "targetActor" >>= (@?= VNull)
          field before "warmUpdateCount" >>= (@?= VInt 0)
          effective <- Continuous.continuePreparedContinuousInitialization cold >>= right
          let snapshot = Continuous.preparedContinuousSnapshot effective
          (after, pool) <- projected (projectContinuousSnapshotData Graph.emptyNodePool snapshot)
          field after "stage" >>= (@?= VWord 1)
          field after "warmUpdateCount"
            >>= (@?= VInt (fromIntegral (Continuous.continuousPreparedWarmUpdateCount snapshot)))
          Continuous.continuousPreparedWarmUpdateCount snapshot @?= 340000
          warm <- child pool after "warmAdam"
          field warm "step" >>= (@?= VInt 340000)
          assertParams pool after "coldActor" (Continuous.continuousPreparedColdActor snapshot)
          assertParams pool after "actor" (Continuous.continuousPreparedActor snapshot)
    , testCase "actual HER prepared replay and optimizer state are retained before goal sampling" $ do
        prepared <-
          Her.prepareHerOnBitFlip (Her.defaultHerTrainConfig {Her.herHiddenUnits = 2, Her.herEpisodes = 0})
        let snapshot = Her.preparedHerSnapshot prepared
        (node, pool) <- projected (projectHerSnapshotData Graph.emptyNodePool snapshot)
        sequenceField pool node "replay" >>= (@?= [])
        sequenceField pool node "recentSuccesses" >>= (@?= [])
        optimizer <- child pool node "adam"
        field optimizer "step" >>= (@?= VInt 0)
        field node "initialParams" >>= \p -> field node "targetParams" >>= (@?= p)
    , testCase "actual tiny ARS raw retains sampled directions applied-step trace and observed counters" $ do
        prepared <-
          Ars.prepareArsOnEnvironment (Sim.SomeSimulatedEnvironment Sim.cartPoleEnvironment) smallArs
        let snapshot = Ars.preparedArsSnapshot prepared
        (initial, pool0) <- projected (projectArsSnapshotData Graph.emptyNodePool snapshot)
        child pool0 initial "initialTheta"
          >>= tensorBits pool0
          >>= (@?= map castDoubleToWord64 (VU.toList (Ars.arsPreparedInitialParams snapshot)))
        raw <- Ars.continuePreparedArsRaw prepared >>= right
        supplied <-
          right
            ( Plan.compileRlPlan
                (Plan.TrainingPlan "ars" "cartpole" 42 1 1 (Just 1) Nothing Nothing)
                (Plan.EvaluationPlan 1)
            )
        (node, pool) <- projected (projectArsReturnedData pool0 supplied raw)
        field node "observedTransitions"
          >>= (@?= VWord (Common.observedEnvironmentTransitionCount (Common.rawTrainerCounters raw)))
        field node "observedUpdates" >>= (@?= VWord 1)
        iterations <- sequenceField pool node "iterations"
        length iterations @?= 1
        iteration <- case iterations of
          first : _ -> ref first >>= nodeAt pool
          [] -> assertFailure "missing actual iteration" >> fail "unreachable"
        applied <- child pool iteration "appliedStep"
        sequenceField pool applied "sampledDirections" >>= \directions -> length directions @?= 2
        sequenceField pool applied "evaluatedPerturbations" >>= \perturbations -> length perturbations @?= 2
        sequenceField pool applied "keptDirections" >>= \kept -> length kept @?= 1
    , testCase "actual zero-generation AlphaZero retains initial and final net Adam and empty samples" $ do
        prepared <- AZ.prepareAlphaZeroWithDevice pureReferenceMlpDevice "connect4" 2 42 0 1 1 1 1
        (initial, _) <-
          projected (projectAlphaZeroSnapshotData Graph.emptyNodePool (AZ.preparedAlphaZeroSnapshot prepared))
        field initial "generationTarget" >>= (@?= VInt 0)
        raw <- AZ.continuePreparedAlphaZeroRaw prepared >>= right
        (node, pool) <- projected (projectAlphaZeroReturnedData Graph.emptyNodePool raw)
        field node "generationCount" >>= (@?= VInt (fromIntegral (AZ.alphaZeroObservedGenerationCount raw)))
        field node "initialNet" >>= \p -> field node "finalNet" >>= (@?= p)
        field node "initialAdam" >>= \p -> field node "finalAdam" >>= (@?= p)
        sequenceField pool node "samples" >>= (@?= [])
    , testCase "actual rejected lower preparation failure projects only its safely retained facts" $ do
        plan <- boundaryPlan "ppo" "cartpole"
        let invalid =
              plan
                { Plan.compiledRlTraining = (Plan.compiledRlTraining plan) {Plan.trainingPlanTrainerKind = "unknown"}
                }
            device =
              pureReferenceMlpDevice
                { mlpdForwardBatch = \_ _ -> assertFailure "rejected context probed" >> fail "unreachable"
                }
        result <- Low.prepareNeuralAttempt device invalid
        failure <- case result of
          Low.NeuralPreparationFailed actual -> pure actual
          _ -> assertFailure "invalid context acquired capsule" >> fail "unreachable"
        (node, pool) <- projected (projectLowNeuralFailureData Graph.emptyNodePool failure)
        field node "stage" >>= (@?= VWord 0)
        facts <- child pool node "facts"
        field facts "initialParams" >>= (@?= VNull)
    , testCase
        "RETURN DTO preserves exact completed prefix and Unknown failed-case work without substituting forwards"
        $ do
          base <- returnFixture
          let raw =
                base
                  { Return.nativeEvaluationEpisodes = [ReturnRef.NativeReturnEpisode 0 3.5 7 True]
                  , Return.nativeEvaluationStatus =
                      Return.NativeEvaluationFailed 1 Return.NativeDelegatedLeft "raw failure"
                  , Return.nativeEvaluationWork = Return.NativeFailedWork 7 Nothing
                  , Return.nativeEvaluationFailedReturnedEpisodes = Just [Common.EvaluationEpisodeResult 2.5 3 False]
                  }
          (node, pool) <- projected (projectReturnEvaluationData Graph.emptyNodePool raw)
          field node "work" >>= (@?= VList [VWord 2, VList [VWord 0, VBytes (BS.singleton 7)], VNull])
          episodes <- sequenceField pool node "episodes"
          length episodes @?= 1
          failed <- child pool node "failedReturnedEpisodes" >>= sequenceValues pool
          length failed @?= 1
    , testCase "nonfinite evaluation payloads are retained as raw bits rather than filtered or completed" $ do
        nan <- runtimeDouble 0x7ff8000000001234
        castDoubleToWord64 nan @?= 0x7ff8000000001234
        base <- returnFixture
        let raw =
              base
                { Return.nativeEvaluationEpisodes = [ReturnRef.NativeReturnEpisode 0 nan 0 False]
                , Return.nativeEvaluationStatus =
                    Return.NativeEvaluationFailed 0 Return.NativeInvalidReturnedEpisodes "nonfinite"
                }
        (node, pool) <- projected (projectReturnEvaluationData Graph.emptyNodePool raw)
        episodes <- sequenceField pool node "episodes"
        case episodes of
          first : _ -> do
            episode <- ref first >>= nodeAt pool
            field episode "reward" >>= (@?= VBits 0x7ff8000000001234)
          [] -> assertFailure "nonfinite raw episode was dropped"
    , testCase "two thousand identical actual-policy parameter records reuse one parameter subtree" $ do
        base <- returnFixture
        let params = Mlp.mlpInit (Mlp.MlpShape 4 4096 2) 42
            forward i =
              Return.NativeForwardObservation
                0
                i
                params
                (VU.replicate 4 0)
                (Return.NativeForwardReturned (Right (VU.replicate 2 0)))
            raw =
              base
                { Return.nativeEvaluationPolicy =
                    Return.NativeNeuralEvaluation (Return.NativeDqn (smallDqn {Dqn.dqnHiddenUnits = 4096}) params)
                , Return.nativeEvaluationForwards = map forward [0 .. 1999]
                }
        (node, pool) <- projected (projectReturnEvaluationData Graph.emptyNodePool raw)
        policy <- child pool node "policy"
        fixed <- field policy "parametersOrTheta"
        forwards <- sequenceField pool node "forwards"
        length forwards @?= 2000
        forM_ forwards $ \value -> ref value >>= nodeAt pool >>= \item -> field item "params" >>= (@?= fixed)
        length [() | (_, item, _) <- Graph.nodePoolEntries pool, Schema.nodeKind item == NParams] @?= 1
    , testCase
        "a signed-zero-different actual forward policy is preserved instead of nominal parameter substitution"
        $ do
          base <- returnFixture
          zero <- runtimeDouble 0
          let original = Mlp.mlpInit (Mlp.MlpShape 4 2 2) 42
              policyParams = original {Mlp.paramB2 = VU.replicate 2 zero}
              actual = policyParams {Mlp.paramB2 = VU.map toggleRuntimeSign (Mlp.paramB2 policyParams)}
          assertBool
            "fixture actual parameter bits differ"
            (actualParamsBits policyParams /= actualParamsBits actual)
          Mlp.paramB2 actual @?= Mlp.paramB2 policyParams
          let raw =
                base
                  { Return.nativeEvaluationPolicy =
                      Return.NativeNeuralEvaluation (Return.NativeDqn smallDqn policyParams)
                  , Return.nativeEvaluationForwards =
                      [ Return.NativeForwardObservation
                          0
                          0
                          actual
                          (VU.replicate 4 0)
                          (Return.NativeForwardReturned (Left "retained"))
                      ]
                  }
          (node, pool) <- projected (projectReturnEvaluationData Graph.emptyNodePool raw)
          forwards <- sequenceField pool node "forwards"
          case forwards of
            first : _ -> do
              item <- ref first >>= nodeAt pool
              assertParams pool item "params" actual
              policy <- child pool node "policy"
              field item "params" >>= \a -> field policy "parametersOrTheta" >>= \b -> assertBool "different data not replaced" (a /= b)
            [] -> assertFailure "missing signedzero record"
    , testCase "HER supplied opaque schedule preserves all20 ordered cases and exact goal bits" $ do
        raw <- herFixture
        (node, pool) <- projected (projectHerEvaluationData Graph.emptyNodePool raw)
        schedule <- child pool node "schedule"
        cases <- sequenceField pool schedule "cases"
        length cases @?= 20
        actual <-
          traverse
            ( \value ->
                ref value >>= nodeAt pool >>= \item -> do
                  identity <- field item "caseId"
                  goal <- child pool item "goal" >>= tensorBits pool
                  pure (identity, goal)
            )
            cases
        actual
          @?= [ ( VInt (fromIntegral (HerRef.rawNativeHerCaseId c))
                , map castDoubleToWord64 (VU.toList (HerRef.rawNativeHerGoal c))
                )
              | c <- HerRef.nativeHerScheduleCases (HerEval.nativeHerEvaluationSchedule raw)
              ]
    , testCase "HER failed progress retains actions state known prefix and Unknown transition remainder" $ do
        base <- herFixture
        let goal = VU.replicate 6 1
            progress = HerEval.NativeHerCaseProgress 3 goal (VU.replicate 6 0) [2, 5] 2 HerEval.NativeHerCheckingOutput
            raw =
              base
                { HerEval.nativeHerEvaluationFailedProgress = Just progress
                , HerEval.nativeHerEvaluationStatus =
                    HerEval.NativeHerEvaluationFailed 3 HerEval.NativeHerInvalidOutput "bad output"
                , HerEval.nativeHerEvaluationWork = HerEval.NativeHerFailedWork 9 2 Nothing
                }
        (node, pool) <- projected (projectHerEvaluationData Graph.emptyNodePool raw)
        item <- child pool node "failedProgress"
        sequenceField pool item "actions" >>= (@?= [VInt 2, VInt 5])
        child pool item "goal" >>= tensorBits pool >>= (@?= replicate 6 (castDoubleToWord64 1))
        field node "work"
          >>= ( @?=
                  VList
                    [VWord 2, VList [VWord 0, VBytes (BS.singleton 9)], VList [VWord 0, VBytes (BS.singleton 2)], VNull]
              )
    , testCase
        "real one-game one-ply arena fixture retains exact tape bytes and actual decision observations"
        $ do
          spec <- right (Tape.mkArenaTapeSpec "connect4" 42 1 1)
          let tape = Tape.materializeArenaTape spec
          let net = Net.initPolicyValueNet (Game.observationSizeFor "connect4") (Game.actionCountFor "connect4") 2 42
          raw <- Arena.evaluateNativeArenaPolicyFixture Game.initialConnect4 pureReferenceMlpDevice tape net
          Arena.nativeArenaEvaluationStatus raw @?= Arena.NativeArenaEvaluationComplete
          (node, pool) <- projected (projectArenaEvaluationData Graph.emptyNodePool raw)
          input <- child pool node "input"
          tapeNode <- child pool input "tape"
          field tapeNode "canonicalBytes" >>= (@?= VBytes (Tape.arenaTapeBytes tape))
          episodes <- sequenceField pool node "episodes"
          length episodes @?= length (Arena.nativeArenaEvaluationEpisodes raw)
          case episodes of
            first : _ -> do
              item <- ref first >>= nodeAt pool
              decisions <- sequenceField pool item "decisions"
              length decisions @?= 1
            [] -> assertFailure "actual arena fixture returned no game"
    , testCase "arena partial DATA retains signed role pass history and Unknown unfinished search" $ do
        let state = Game.GameState "othello" [-1, 19] (-1)
            progress = Arena.NativeArenaCaseProgress 2 1 state []
            raw =
              Arena.RawNativeArenaEvaluation
                Nothing
                []
                (Just progress)
                (Arena.NativeArenaForwardSummary 7 [] Nothing)
                (Arena.NativeArenaEvaluationFailed 2 1 Arena.NativeArenaSearchException "search failed")
                (Arena.NativeArenaEvaluationWork 11 1 5 Arena.UnknownUnfinishedArenaSearch)
        (node, pool) <- projected (projectArenaEvaluationData Graph.emptyNodePool raw)
        item <- child pool node "progress"
        game <- child pool item "state"
        field game "currentPlayer" >>= (@?= VInt (-1))
        sequenceField pool game "moves" >>= (@?= [VInt (-1), VInt 19])
        work <- field node "work"
        case work of
          VList [_, _, _, unknown] -> unknown @?= VWord 1
          _ -> assertFailure "missing arena work fields"
    , testCase "ambient sibling roots are retained without making the selected subtree unreachable" $ do
        base <- returnFixture
        (first, p1) <- projectReturnEvaluationData Graph.emptyNodePool base >>= right
        raw <- herFixture
        (second, p2) <- projectHerEvaluationData p1 raw >>= right
        assertBool "two distinct evaluation roots" (first /= second)
        assertBool
          "first root retained for future parent composition"
          (case Graph.lookupNode first p2 of Just _ -> True; Nothing -> False)
        closure <- right (Graph.reachableNodePool [second] p2)
        void (right (Graph.validateReachableData [second] closure))
        assertBool
          "unrelated prior root pruned in temporary view"
          (case Graph.lookupNode first closure of Nothing -> True; Just _ -> False)
    , testCase "an actual prepared frame above8MiB refuses before tensor materialization" $ do
        let base = Sim.cartPoleEnvironment
            wide =
              base
                { Sim.envRenderFrame = \state -> (Sim.envRenderFrame base state) {Sim.renderObservation = replicate (8388608 `div` 8 + 1) 0}
                }
        prepared <- Ars.prepareArsOnEnvironment (Sim.SomeSimulatedEnvironment wide) smallArs
        result <- projectArsSnapshotData Graph.emptyNodePool (Ars.preparedArsSnapshot prepared)
        refusalResource FrameBytes result
    , testCase "UTF8 diagnostic size refusal uses bytes and never returns a truncated complete diagnostic" $ do
        base <- returnFixture
        let raw =
              base
                { Return.nativeEvaluationStatus = Return.NativeEvaluationRejected (Text.replicate 262145 "\x10000")
                }
        result <- projectReturnEvaluationData Graph.emptyNodePool raw
        refusalResource DiagnosticTextBytes result
    , testCase "infinite forward spine refuses before forcing a poisoned element" $ do
        base <- returnFixture
        result <-
          projectReturnEvaluationData
            Graph.emptyNodePool
            (base {Return.nativeEvaluationForwards = repeat (error "element must remain undemanded")})
        refusalResource PerSequenceElements result
    , testCase "a bottom supplied DTO becomes a typed synchronous projection failure" $ do
        result <- projectReturnEvaluationData Graph.emptyNodePool (error "supplied DTO bottom")
        synchronous result
    , testCase "a lazy callback Left diagnostic is forced within the projection catcher" $ do
        base <- returnFixture
        let params = Mlp.mlpInit (Mlp.MlpShape 4 2 2) 42
            raw =
              base
                { Return.nativeEvaluationForwards =
                    [ Return.NativeForwardObservation
                        0
                        0
                        params
                        (VU.replicate 4 0)
                        (Return.NativeForwardReturned (Left (error "lazy callback detail")))
                    ]
                }
        projectReturnEvaluationData Graph.emptyNodePool raw >>= synchronous
    , testCase "a lazy callback Right vector element is forced within the projection catcher" $ do
        base <- returnFixture
        let params = Mlp.mlpInit (Mlp.MlpShape 4 2 2) 42
            raw =
              base
                { Return.nativeEvaluationForwards =
                    [ Return.NativeForwardObservation
                        0
                        0
                        params
                        (VU.replicate 4 0)
                        (Return.NativeForwardReturned (Right (VU.generate 2 (\_ -> error "lazy output element"))))
                    ]
                }
        projectReturnEvaluationData Graph.emptyNodePool raw >>= synchronous
    , testCase "async cancellation propagates instead of becoming an ordinary DATA failure" $ do
        result <-
          try (projectReturnEvaluationData Graph.emptyNodePool (throw ThreadKilled))
            :: IO (Either AsyncException (Either ProjectionFailure (Digest, Graph.NodePool)))
        case result of
          Left ThreadKilled -> pure ()
          _ -> assertFailure "async exception was swallowed"
    ]

refusalResource :: Resource -> Either ProjectionFailure a -> Assertion
refusalResource resource value = case value of
  Left (ProjectionDataRejected (ResourceExceeded actual _ _)) -> actual @?= resource
  Left (ProjectionAllocationRefused actual _ _) -> actual @?= resource
  Left other -> assertFailure ("wrong refusal: " <> show other)
  Right _ -> assertFailure "oversized source DATA was accepted"

synchronous :: Either ProjectionFailure a -> Assertion
synchronous value = case value of
  Left (ProjectionSynchronousFailure (ProjectionDiagnosticComplete detail)) -> assertBool "actual diagnostic retained" (Text.length detail > 0)
  Left (ProjectionSynchronousFailure ProjectionDiagnosticUnavailable) -> pure ()
  Left other -> assertFailure ("wrong failure: " <> show other)
  Right _ -> assertFailure "poisonous input produced data"
