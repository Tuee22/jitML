{-# LANGUAGE OverloadedStrings #-}

-- | Raw snapshot/replay predicates only. These fixtures assert no training,
-- producer authentication, eligible completion, or real-device convergence.
module InitialComparison (initialComparisonTests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Either (isLeft)
import Data.Foldable (for_)
import Data.Text (Text)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Numerics.LayerGraph qualified as Graph
import JitML.Numerics.LayerGraphMetadata qualified as Metadata
import JitML.Product.LearningSignal qualified as Signal
import JitML.SL.InitialComparison qualified as Comparison
import JitML.SL.RuntimeArtifact qualified as Runtime

import InitialSnapshotOwnership qualified

initialComparisonTests :: TestTree
initialComparisonTests =
  testGroup
    "actual-initial supervised comparison"
    [ snapshotTests
    , descriptorTests
    , replayTests
    , InitialSnapshotOwnership.initialSnapshotOwnershipTests
    ]

snapshotTests :: TestTree
snapshotTests =
  testGroup
    "canonical raw snapshot refinement"
    [ testCase "canonical snapshot roundtrips exact descriptor transforms and initial JMW1" $ do
        snapshot <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
        Comparison.initialComparisonSnapshotToRaw snapshot @?= rawSnapshot
        let encoded = Comparison.encodeInitialComparisonSnapshot snapshot
        decoded <- expectRight (Comparison.decodeInitialComparisonSnapshot encoded)
        decoded @?= snapshot
        Comparison.initialComparisonSnapshotSha256 snapshot
          @?= WeightCodec.jmw1ContentSha (LBS.fromStrict encoded)
        Comparison.initialComparisonJmw1Sha256 snapshot
          @?= WeightCodec.jmw1ContentSha (LBS.fromStrict initialBytes)
    , testCase "unknown snapshot versions reject before becoming a refined snapshot" $
        for_ [0, 2, -1, maxBound] $
          \version ->
            assertRejected
              ( Comparison.refineInitialComparisonSnapshot
                  (rawSnapshot {Comparison.rawInitialComparisonVersion = version})
              )
    , testCase "wrong counts malformed weights and nonfinite initial payloads reject"
        $ for_
          [ jmw1 []
          , jmw1 [1, 2]
          , jmw1 [1, 2, 3, 4]
          , jmw1 [0 / 0, 2, 0.5]
          , jmw1 [1 / 0, 2, 0.5]
          , jmw1 [1, negate (1 / 0), 0.5]
          , "not-jmw1"
          , initialBytes <> "trailing"
          ]
        $ \bytes ->
          assertRejected
            ( Comparison.refineInitialComparisonSnapshot
                (rawSnapshot {Comparison.rawInitialComparisonJmw1Bytes = bytes})
            )
    , testCase "invalid runtime transforms and invalid graph geometry reject" $ do
        let badRuntimes =
              [ runtime {Runtime.rawSupervisedRuntimeInputTransform = Runtime.RawStandardizeInput [1, 2] [2, 0]}
              , runtime {Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawDestandardizeOutput [10] [0]}
              , runtime {Runtime.rawSupervisedRuntimeInputTransform = Runtime.RawIdentityInput 0}
              ]
        for_ badRuntimes $ \invalid ->
          assertRejected
            ( Comparison.refineInitialComparisonSnapshot
                (rawSnapshot {Comparison.rawInitialComparisonRuntime = invalid})
            )
        assertRejected
          ( Comparison.refineInitialComparisonSnapshot
              ( rawSnapshot
                  { Comparison.rawInitialComparisonGraphMetadata =
                      metadata {Metadata.layerGraphMetadataInputShape = [0]}
                  }
              )
          )
    , testCase "valid runtime ingress transforms must still match the actual graph input width" $ do
        for_ [Runtime.RawIdentityInput 3, Runtime.RawStandardizeInput [0, 0, 0] [1, 1, 1]] $ \transform -> do
          let incompatible = runtime {Runtime.rawSupervisedRuntimeInputTransform = transform}
          _ <- expectRight (Runtime.refineSupervisedRuntime incompatible)
          Comparison.refineInitialComparisonSnapshot
            (rawSnapshot {Comparison.rawInitialComparisonRuntime = incompatible})
            @?= Left "initial comparison runtime input width differs from its graph"
    , testCase "identity and fitted output transforms require exact semantic graph width" $ do
        for_ [Runtime.RawIdentityOutput, Runtime.RawDestandardizeOutput [0, 0] [1, 1]] $ \transform -> do
          let incompatible =
                runtime
                  { Runtime.rawSupervisedRuntimeTask = Runtime.RawRegressionRuntimeTask 2
                  , Runtime.rawSupervisedRuntimeOutputTransform = transform
                  }
          _ <- expectRight (Runtime.refineSupervisedRuntime incompatible)
          Comparison.refineInitialComparisonSnapshot
            (rawSnapshot {Comparison.rawInitialComparisonRuntime = incompatible})
            @?= Left "initial comparison graph output width differs from its semantic runtime"
    , testCase "semantic prefixes permit an explicit surplus output but reject a narrower graph" $ do
        let classifier =
              runtime
                { Runtime.rawSupervisedRuntimeTask = Runtime.RawClassificationRuntimeTask 2
                , Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawSemanticPrefixOutput 2
                }
            threeOutputs =
              metadata
                { Metadata.layerGraphMetadataOutputShape = [3]
                , Metadata.layerGraphMetadataNodes = [node {Metadata.layerGraphNodeOutputShape = [3]}]
                }
            bytes = jmw1 [1, 0, 0, 1, 2, 2, 0, 0, 10]
        snapshot <-
          expectRight
            ( Comparison.refineInitialComparisonSnapshot
                (Comparison.RawInitialComparisonSnapshot 1 classifier threeOutputs bytes)
            )
        comparison <-
          expectRight (Comparison.prepareSupervisedComparison snapshot classifier threeOutputs bytes)
        Comparison.comparisonInitialInference comparison [3, 6] @?= Right [1, 1]
        Comparison.comparisonFinalInference comparison [3, 6] @?= Right [1, 1]
        Comparison.refineInitialComparisonSnapshot
          (rawSnapshot {Comparison.rawInitialComparisonRuntime = classifier})
          @?= Left "initial comparison graph output is narrower than its semantic prefix"
    , testCase "trailing and noncanonical CBOR cannot acquire the canonical snapshot identity" $ do
        snapshot <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
        let encoded = Comparison.encodeInitialComparisonSnapshot snapshot
        assertRejected (Comparison.decodeInitialComparisonSnapshot (encoded <> BS.singleton 0))
        -- Replace the canonical definite outer CBOR array with an indefinite
        -- array carrying identical items. Decoders may reject it directly; a
        -- permissive decoder must still fail the canonical re-encoding check.
        case BS.uncons encoded of
          Just (header, remainder)
            | header >= 128 && header <= 151 ->
                assertRejected
                  (Comparison.decodeInitialComparisonSnapshot (BS.singleton 159 <> remainder <> BS.singleton 255))
          _ -> assertFailure "generic snapshot encoding has no definite outer array"
    ]

descriptorTests :: TestTree
descriptorTests =
  testGroup
    "exact initial-final descriptor binding"
    [ testCase "different final parameters retain exact descriptor and both snapshot payloads" $ do
        comparison <- makeComparison finalBytes
        Comparison.initialComparisonSnapshotToRaw (Comparison.comparisonInitialSnapshot comparison)
          @?= rawSnapshot
        Comparison.comparisonFinalJmw1Bytes comparison @?= finalBytes
    , testCase
        "initial and final identical weights remain raw outcomes but cannot pass paired improvement"
        $ do
          comparison <- makeComparison initialBytes
          initial <- expectRight (Comparison.comparisonInitialInference comparison [3, 6])
          final <- expectRight (Comparison.comparisonFinalInference comparison [3, 6])
          initial @?= final
          Signal.assertRegressionImprovement 1 [20, 21] (initial <> initial) (final <> final)
            @?= Left "final regressor does not strictly improve over its initial predictor"
    , testCase "any fitted transform substitution rejects even when both runtime DTOs refine" $ do
        snapshot <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
        for_
          [ runtime {Runtime.rawSupervisedRuntimeInputTransform = Runtime.RawStandardizeInput [0, 2] [2, 4]}
          , runtime {Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawDestandardizeOutput [11] [3]}
          ]
          $ \changed -> do
            _ <- expectRight (Runtime.refineSupervisedRuntime changed)
            Comparison.prepareSupervisedComparison snapshot changed metadata finalBytes
              @?= Left "initial and final comparison runtime transforms differ"
    , testCase
        "names modes operators activations shapes and tensor layout all participate in descriptor equality"
        $ do
          snapshot <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
          let nodeChanges =
                [ node {Metadata.layerGraphNodeName = "substituted"}
                , node {Metadata.layerGraphNodeMode = Metadata.LayerGraphTrainingMode}
                , node {Metadata.layerGraphNodeActivation = Metadata.LayerGraphTanhActivation}
                , node {Metadata.layerGraphNodeOp = Graph.IdentityOp}
                , node {Metadata.layerGraphNodeInputShape = [1, 2]}
                , node {Metadata.layerGraphNodeWeightTensor = Just "other.weights"}
                , node {Metadata.layerGraphNodeBiasTensor = Just "other.bias"}
                ]
              metadataChanges =
                [ metadata {Metadata.layerGraphMetadataName = "other-graph"}
                , metadata {Metadata.layerGraphMetadataOutputShape = [1, 1]}
                ]
                  <> fmap (\changed -> metadata {Metadata.layerGraphMetadataNodes = [changed]}) nodeChanges
          for_ metadataChanges $ \changed ->
            Comparison.prepareSupervisedComparison snapshot runtime changed finalBytes
              @?= Left "initial and final comparison graph descriptors differ"
    , testCase "malformed count or nonfinite final payloads cannot hide behind a valid initial snapshot" $ do
        snapshot <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
        for_ [jmw1 [1, 2], jmw1 [1, 2, 3, 4], jmw1 [1, 2, 0 / 0], "invalid", finalBytes <> "trailing"] $ \bytes ->
          assertRejected (Comparison.prepareSupervisedComparison snapshot runtime metadata bytes)
    , testCase "payload and descriptor substitutions change the canonical snapshot address" $ do
        original <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
        changedWeights <-
          expectRight
            ( Comparison.refineInitialComparisonSnapshot
                (rawSnapshot {Comparison.rawInitialComparisonJmw1Bytes = finalBytes})
            )
        changedName <-
          expectRight
            ( Comparison.refineInitialComparisonSnapshot
                ( rawSnapshot
                    { Comparison.rawInitialComparisonGraphMetadata =
                        metadata {Metadata.layerGraphMetadataName = "renamed"}
                    }
                )
            )
        assertBool
          "weight substitution retained snapshot SHA"
          ( Comparison.initialComparisonSnapshotSha256 original
              /= Comparison.initialComparisonSnapshotSha256 changedWeights
          )
        assertBool
          "descriptor substitution retained snapshot SHA"
          ( Comparison.initialComparisonSnapshotSha256 original
              /= Comparison.initialComparisonSnapshotSha256 changedName
          )
        Comparison.initialComparisonJmw1Sha256 original
          @?= Comparison.initialComparisonJmw1Sha256 changedName
    ]

replayTests :: TestTree
replayTests =
  testGroup
    "initial and final replay through the serving runtime"
    [ testCase "each replay uses its own actual parameters with the identical fitted transforms" $ do
        comparison <- makeComparison finalBytes
        -- [3,6] standardizes to [1,1]. Initial affine=3.5, final=2;
        -- the exact common output transform is 10+3*y.
        Comparison.comparisonInitialInference comparison [3, 6] @?= Right [20.5]
        Comparison.comparisonFinalInference comparison [3, 6] @?= Right [16]
        Comparison.comparisonInitialInference comparison [1, 2] @?= Right [11.5]
        Comparison.comparisonFinalInference comparison [1, 2] @?= Right [13]
    , testCase "each example is replayed on its own features and fixed targets determine improvement" $ do
        comparison <- makeComparison finalBytes
        initial <-
          expectRight (traverse (Comparison.comparisonInitialInference comparison) [[3, 6], [1, 2]])
        final <- expectRight (traverse (Comparison.comparisonFinalInference comparison) [[3, 6], [1, 2]])
        let initialPredictions = concat initial
            finalPredictions = concat final
        Signal.assertRegressionImprovement 1 [16, 13] initialPredictions finalPredictions @?= Right ()
        assertRejected
          (Signal.assertRegressionImprovement 1 [20.5, 11.5] initialPredictions finalPredictions)
    , testCase "wrong input counts and nonfinite inputs fail both initial and final replay" $ do
        comparison <- makeComparison finalBytes
        for_ [[], [3], [3, 6, 9], [0 / 0, 6], [3, 1 / 0]] $ \input -> do
          assertRejected (Comparison.comparisonInitialInference comparison input)
          assertRejected (Comparison.comparisonFinalInference comparison input)
    , testCase "runtime and graph output mismatch is rejected before snapshot refinement" $ do
        let incompatible =
              runtime
                { Runtime.rawSupervisedRuntimeTask = Runtime.RawRegressionRuntimeTask 2
                , Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawIdentityOutput
                }
        _ <- expectRight (Runtime.refineSupervisedRuntime incompatible)
        Comparison.refineInitialComparisonSnapshot
          (rawSnapshot {Comparison.rawInitialComparisonRuntime = incompatible})
          @?= Left "initial comparison graph output width differs from its semantic runtime"
    ]

rawSnapshot :: Comparison.RawInitialComparisonSnapshot
rawSnapshot = Comparison.RawInitialComparisonSnapshot 1 runtime metadata initialBytes

runtime :: Runtime.RawSupervisedRuntime
runtime =
  Runtime.RawSupervisedRuntime
    { Runtime.rawSupervisedRuntimeTask = Runtime.RawRegressionRuntimeTask 1
    , Runtime.rawSupervisedRuntimeInputTransform = Runtime.RawStandardizeInput [1, 2] [2, 4]
    , Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawDestandardizeOutput [10] [3]
    }

metadata :: Metadata.LayerGraphMetadata
metadata =
  Metadata.LayerGraphMetadata
    { Metadata.layerGraphMetadataName = "initial-comparison-fixture"
    , Metadata.layerGraphMetadataInputShape = [2]
    , Metadata.layerGraphMetadataOutputShape = [1]
    , Metadata.layerGraphMetadataNodes = [node]
    }

node :: Metadata.LayerGraphNodeMetadata
node =
  Metadata.LayerGraphNodeMetadata
    { Metadata.layerGraphNodeName = "linear"
    , Metadata.layerGraphNodeKind = Metadata.LayerGraphDenseLayer
    , Metadata.layerGraphNodeInputShape = [2]
    , Metadata.layerGraphNodeOutputShape = [1]
    , Metadata.layerGraphNodeMode = Metadata.LayerGraphInferenceMode
    , Metadata.layerGraphNodeActivation = Metadata.LayerGraphLinearActivation
    , Metadata.layerGraphNodeWeightTensor = Just "linear.weights"
    , Metadata.layerGraphNodeBiasTensor = Just "linear.bias"
    , Metadata.layerGraphNodeOp = Graph.DenseOp
    }

initialBytes :: BS.ByteString
initialBytes = jmw1 [1, 2, 0.5]

finalBytes :: BS.ByteString
finalBytes = jmw1 [2, -1, 1]

jmw1 :: [Double] -> BS.ByteString
jmw1 = LBS.toStrict . WeightCodec.encodeJmw1

makeComparison :: BS.ByteString -> IO Comparison.SupervisedComparison
makeComparison final = do
  snapshot <- expectRight (Comparison.refineInitialComparisonSnapshot rawSnapshot)
  expectRight (Comparison.prepareSupervisedComparison snapshot runtime metadata final)

assertRejected :: (Show value) => Either Text value -> Assertion
assertRejected value = assertBool ("expected rejection, got " <> show value) (isLeft value)

expectRight :: (Show err) => Either err value -> IO value
expectRight = either (assertFailure . show) pure
