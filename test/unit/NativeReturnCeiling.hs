{-# LANGUAGE OverloadedStrings #-}

-- Actual public-simulator proof replay and explicitly arithmetic policy DATA.
-- No fixture below is a trained policy, device result or qualified cohort.
module NativeReturnCeiling (nativeReturnCeilingTests) where

import Control.Monad (foldM, forM_)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Float (castDoubleToWord64, castWord64ToDouble)
import Test.Tasty (TestTree, testGroup, withResource)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Product.NativeReturnLearningPolicy qualified as Policy
import JitML.RL.NativeReturnCeiling qualified as C
import JitML.RL.NativeReturnReferences qualified as Ref
import JitML.RL.Simulator qualified as Sim

right :: (Show error) => Either error value -> IO value
right value = case value of
  Left reason -> assertFailure (show reason) >> fail "unreachable"
  Right actual -> pure actual
present :: Maybe value -> IO value
present value = case value of
  Nothing ->
    assertFailure "required canonical proof or complete frontier node is absent" >> fail "unreachable"
  Just actual -> pure actual
reject :: Text -> Either Text value -> Assertion
reject fragment value = case value of
  Left reason -> assertBool "wrong structural rejection" (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure "invalid above-bound observations were compared"

type Fixture = (Ref.NativeReturnReferenceSpec, C.NativeReturnCeiling, Ref.NativeReturnReferenceSet)
fixture :: IO Fixture
fixture = do
  spec <- right (Ref.canonicalNativeReturnSpec "PPO" "key-door-grid")
  proof <- present =<< right (C.proveCanonicalNativeReturnCeiling spec)
  references <- right (Ref.evaluateCanonicalNativeReturnReferences spec)
  pure (spec, proof, references)

episodes :: Double -> [Ref.NativeReturnEpisode]
episodes reward = [Ref.NativeReturnEpisode index reward 10 True | index <- [0 .. 19]]
seeds :: Double -> [Policy.NativeReturnSeedObservation]
seeds score =
  [ Policy.NativeReturnSeedObservation index (42 + fromIntegral index) (episodes 0) (episodes score)
  | index <- [0 .. 4]
  ]
hasFailure :: Text -> Policy.NativeReturnCohortComparison -> Assertion
hasFailure fragment result =
  assertBool
    "required learning failure disappeared"
    (any (Text.isInfixOf fragment) (Policy.nativeReturnComparisonFailures result))
mapReferences
  :: (Ref.NativeReturnEpisode -> Ref.NativeReturnEpisode)
  -> Ref.NativeReturnReferenceSet
  -> Ref.NativeReturnReferenceSet
mapReferences change references =
  references
    { Ref.nativeReturnObservedReferences =
        map
          ( \observed ->
              observed {Ref.nativeReturnObservedEpisodes = map change (Ref.nativeReturnObservedEpisodes observed)}
          )
          (Ref.nativeReturnObservedReferences references)
    }
allEdges :: C.NativeReturnCeiling -> [(Int, C.NativeReturnCeilingNode, C.NativeReturnCeilingEdge)]
allEdges proof =
  [ (C.nativeCeilingLayerTime layer, node, edge)
  | layer <- C.nativeReturnCeilingLayers proof
  , node <- C.nativeCeilingLayerNodes layer
  , edge <- C.nativeCeilingNodeEdges node
  ]
terminal :: C.NativeReturnCeilingEdge -> Bool
terminal edge = C.nativeCeilingEdgeNativeDone edge || C.nativeCeilingEdgeHorizonDone edge

nativeReturnCeilingTests :: TestTree
nativeReturnCeilingTests = withResource fixture (const (pure ())) $ \get ->
  testGroup
    "native return proven maximum comparison"
    [ testCase "all eight canonical KeyDoor scopes produce exact current simulator bounds" $ do
        specs <- right Ref.allCanonicalNativeReturnSpecs
        let selected = filter ((== "key-door-grid") . Ref.nativeReturnSpecEnvironment) specs
        length selected @?= 8
        forM_ selected $ \spec -> do
          proof <- present =<< right (C.proveCanonicalNativeReturnCeiling spec)
          C.nativeReturnCeilingSpec proof @?= spec
          C.nativeReturnCeilingMaximumBits proof @?= 4609118966639786721
          C.nativeReturnCeilingUpperBound proof @?= toRational (castWord64ToDouble 4609118966639786721)
    , testCase "unsupported canonical return tasks have no supplied or inferred tie exception" $ do
        forM_ [("PPO", "cartpole"), ("DQN", "mountain-car"), ("SAC", "pendulum")] $ \(algorithm, environment) -> do
          spec <- right (Ref.canonicalNativeReturnSpec algorithm environment)
          actual <- right (C.proveCanonicalNativeReturnCeiling spec)
          actual @?= Nothing
    , testCase "complete actual proof retains all frontiers legal edges and terminal alternatives" $ do
        (_, proof, _) <- get
        let layers = C.nativeReturnCeilingLayers proof
        map C.nativeCeilingLayerTime layers @?= [0 .. 63]
        sum (map (length . C.nativeCeilingLayerNodes) layers) @?= 1790
        length (allEdges proof) @?= 4478
        length [() | (_, _, edge) <- allEdges proof, terminal edge] @?= 160
        case layers of
          first : _ -> case C.nativeCeilingLayerNodes first of
            [node] -> do
              C.nativeCeilingNodeState node @?= Sim.envInitial Sim.keyDoorGridEnvironment
              C.nativeCeilingNodePrefixBits node @?= castDoubleToWord64 0
              C.nativeCeilingNodeActions node @?= []
            _ -> assertFailure "proof has a substituted or duplicate initial frontier"
          [] -> assertFailure "proof omitted its initial layer"
    , testCase "each recorded legal edge agrees with the actual public simulator and binary64 addition" $ do
        (spec, proof, _) <- get
        forM_ (C.nativeReturnCeilingLayers proof) $ \layer ->
          forM_ (C.nativeCeilingLayerNodes layer) $ \node -> do
            let state = C.nativeCeilingNodeState node
            maskFor <- present (Sim.envActionMask Sim.keyDoorGridEnvironment)
            C.nativeCeilingNodeLegalMask node @?= maskFor state
            map C.nativeCeilingEdgeAction (C.nativeCeilingNodeEdges node)
              @?= [action | (action, True) <- zip [0 :: Int ..] (maskFor state)]
            Sim.keyDoorGridStepCount state @?= C.nativeCeilingLayerTime layer
            forM_ (C.nativeCeilingNodeEdges node) $ \edge -> do
              let actual = Sim.envStep Sim.keyDoorGridEnvironment state (C.nativeCeilingEdgeAction edge)
                  prefix = castWord64ToDouble (C.nativeCeilingNodePrefixBits node)
              C.nativeCeilingEdgePostState edge @?= Sim.simStepState actual
              C.nativeCeilingEdgeRewardBits edge @?= castDoubleToWord64 (Sim.simStepReward actual)
              C.nativeCeilingEdgeCandidateBits edge @?= castDoubleToWord64 (prefix + Sim.simStepReward actual)
              C.nativeCeilingEdgeNativeDone edge @?= Sim.simStepDone actual
              C.nativeCeilingEdgeHorizonDone edge
                @?= (C.nativeCeilingLayerTime layer + 1 >= Ref.nativeReturnSpecHorizon spec)
    , testCase
        "independent certificate coverage retains every successor maximum and a predecessor witness"
        $ do
          (_, proof, _) <- get
          let layers = C.nativeReturnCeilingLayers proof
          forM_ layers $ \layer -> do
            let outgoing =
                  [ (node, edge)
                  | node <- C.nativeCeilingLayerNodes layer
                  , edge <- C.nativeCeilingNodeEdges node
                  , not (terminal edge)
                  ]
                next =
                  maybe
                    []
                    C.nativeCeilingLayerNodes
                    (find ((== C.nativeCeilingLayerTime layer + 1) . C.nativeCeilingLayerTime) layers)
            C.nativeCeilingLayerNextCount layer @?= length next
            -- This checks the returned certificate relation without implementing
            -- the production Map-based solver or copying simulator dynamics.
            forM_ outgoing $ \(_, edge) -> do
              target <- present (find ((== C.nativeCeilingEdgePostState edge) . C.nativeCeilingNodeState) next)
              assertBool
                "successor frontier discarded a larger legal prefix"
                ( castWord64ToDouble (C.nativeCeilingEdgeCandidateBits edge)
                    <= castWord64ToDouble (C.nativeCeilingNodePrefixBits target)
                )
            forM_ next $ \target ->
              assertBool
                "successor prefix/path has no actual predecessor witness"
                ( any
                    ( \(node, edge) ->
                        C.nativeCeilingEdgePostState edge == C.nativeCeilingNodeState target
                          && C.nativeCeilingEdgeCandidateBits edge == C.nativeCeilingNodePrefixBits target
                          && C.nativeCeilingNodeActions target
                            == C.nativeCeilingNodeActions node <> [C.nativeCeilingEdgeAction edge]
                    )
                    outgoing
                )
          let ending =
                [ castWord64ToDouble (C.nativeCeilingEdgeCandidateBits edge)
                | (_, _, edge) <- allEdges proof
                , terminal edge
                ]
          assertBool
            "reported maximum omits a better complete terminal path"
            (all ((<= C.nativeReturnCeilingUpperBound proof) . toRational) ending)
          assertBool
            "reported maximum has no terminal witness"
            (any ((== C.nativeReturnCeilingMaximumBits proof) . castDoubleToWord64) ending)
    , testCase "the retained maximizing path is actually legal terminal and attains the exact bound" $ do
        (_, proof, _) <- get
        (_, reward, done) <-
          foldM
            ( \(state, prefix, finished) action -> do
                assertBool "maximizing path continued after termination" (not finished)
                maskFor <- present (Sim.envActionMask Sim.keyDoorGridEnvironment)
                assertBool
                  "maximizing path used an illegal action"
                  (action `elem` [index | (index, True) <- zip [0 :: Int ..] (maskFor state)])
                let actual = Sim.envStep Sim.keyDoorGridEnvironment state action
                pure (Sim.simStepState actual, prefix + Sim.simStepReward actual, Sim.simStepDone actual)
            )
            (Sim.envInitial Sim.keyDoorGridEnvironment, 0, False)
            (C.nativeReturnCeilingMaximizingActions proof)
        done @?= True
        castDoubleToWord64 reward @?= C.nativeReturnCeilingMaximumBits proof
    , testCase
        "a maximum reference tie retains the proof five outcomes and unchanged quality restrictions"
        $ do
          (spec, proof, references) <- get
          let score = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof); observations = seeds score
          result <- right (Policy.compareNativeReturnCohort references observations)
          Policy.nativeReturnComparisonObservations result @?= observations
          Policy.nativeReturnComparisonReferences result @?= references
          Policy.nativeReturnComparisonJointCount result @?= 5
          Policy.nativeReturnComparisonMedianQuality result @?= score
          Policy.nativeReturnComparisonFailures result @?= []
          retained <- present (Policy.nativeReturnComparisonCeiling result)
          C.nativeReturnCeilingSpec retained @?= spec
          C.nativeReturnCeilingLayers retained @?= C.nativeReturnCeilingLayers proof
    , testCase "a maximum reference tie cannot replace strict authentic initialization improvement" $ do
        (_, proof, references) <- get
        let score = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof)
            observations = map (\seed -> seed {Policy.nativeReturnObservedInitialEpisodes = episodes score}) (seeds score)
        result <- right (Policy.compareNativeReturnCohort references observations)
        Policy.nativeReturnComparisonJointCount result @?= 0
        hasFailure "initial observation" result
        Policy.nativeReturnComparisonObservations result @?= observations
    , testCase "arithmetic equality below the actual maximum remains a failed reference comparison" $ do
        (_, proof, references) <- get
        let score = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof) - 0.25
            rawFixture = mapReferences (\episode -> episode {Ref.nativeReturnEpisodeReward = score}) references
        result <- right (Policy.compareNativeReturnCohort rawFixture (seeds score))
        Policy.nativeReturnComparisonJointCount result @?= 0
        hasFailure "every fixed task reference" result
    , testCase "a single above-maximum final episode cannot hide below the whole episode median" $ do
        (_, proof, references) <- get
        let maximumValue = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof)
            impossible = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof + 1)
            observations =
              map
                ( \seed ->
                    seed
                      { Policy.nativeReturnObservedFinalEpisodes =
                          [ episode
                              { Ref.nativeReturnEpisodeReward =
                                  if Ref.nativeReturnEpisodeId episode == 0 then impossible else maximumValue
                              }
                          | episode <- episodes maximumValue
                          ]
                      }
                )
                (seeds maximumValue)
        reject "exceeds the independently proved" (Policy.compareNativeReturnCohort references observations)
    , testCase
        "above-maximum initial episodes are structurally invalid rather than counted as failed learners"
        $ do
          (_, proof, references) <- get
          let maximumValue = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof)
              impossible = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof + 1)
              observations =
                map
                  (\seed -> seed {Policy.nativeReturnObservedInitialEpisodes = episodes impossible})
                  (seeds maximumValue)
          reject "exceeds the independently proved" (Policy.compareNativeReturnCohort references observations)
    , testCase "an impossible reference reward cannot manufacture a larger task maximum" $ do
        (_, proof, references) <- get
        let maximumValue = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof)
            impossible = castWord64ToDouble (C.nativeReturnCeilingMaximumBits proof + 1)
            corrupted =
              mapReferences
                ( \episode ->
                    episode
                      { Ref.nativeReturnEpisodeReward =
                          if Ref.nativeReturnEpisodeId episode == 0 then impossible else Ref.nativeReturnEpisodeReward episode
                      }
                )
                references
        reject
          "exceeds the independently proved"
          (Policy.compareNativeReturnCohort corrupted (seeds maximumValue))
    ]
