{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module SupervisedQualification (supervisedQualificationTests) where

import Codec.Serialise (serialise)
import Control.Concurrent (threadDelay)
import Control.Exception (evaluate)
import Data.ByteString qualified as ByteString
import Data.ByteString.Internal qualified as ByteString.Internal
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Either (isLeft, isRight)
import Data.Foldable (for_)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List qualified as List
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)
import Foreign.Concurrent qualified as Foreign
import Foreign.ForeignPtr (withForeignPtr)
import Foreign.Marshal.Alloc (free, mallocBytes)
import Foreign.Marshal.Utils (copyBytes, fillBytes)
import Foreign.Ptr (castPtr, plusPtr)
import GHC.Float (castWord64ToDouble)
import System.FilePath (takeDirectory, (</>))
import System.Mem (performGC)
import System.Mem.Weak (Weak, deRefWeak, mkWeakPtr)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Numerics.LayerGraph qualified as Graph
import JitML.Numerics.LayerGraphMetadata qualified as Metadata
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as Workload
import JitML.Product.CriterionReviewData qualified as Review
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.LaneRegistrationData qualified as Registration
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.SourceDigest (SourceStamp (..), sourceDigestAlgorithm)
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.SupervisedQualificationPolicy qualified as Policy
import JitML.SL.Canonicals qualified as Canonicals
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.InitialComparison qualified as Initial
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.Substrate (Substrate (..), renderSubstrate)

-- All fixtures below are synthetic graph/data declarations. They exercise the
-- public pure replay/refinement boundaries, never attest real dataset training
-- or admit the initial model as an eligible completed checkpoint.
supervisedQualificationTests :: TestTree
supervisedQualificationTests =
  testGroup
    "replayable compact supervised qualification"
    [ testCase "canonical portable roundtrip replays all five pairs and derives the served metric" $ do
        (plan, raw) <- expectRight (classificationFixture [True, True, True, False, False])
        refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
        qualified <- expectRight (Qualification.qualifySupervisedCohort refined)
        let bytes = Qualification.encodeSupervisedQualification refined
        reloaded <- expectRight (Qualification.decodeSupervisedQualification plan bytes)
        Qualification.encodeSupervisedQualification reloaded @?= bytes
        Qualification.supervisedQualificationSha256 reloaded
          @?= Qualification.supervisedQualificationSha256 refined
        Qualification.supervisedQualificationToRaw (Qualification.qualifiedSupervisedCohortData qualified)
          @?= raw
        Policy.supervisedCohortJointSuccessCount (Qualification.supervisedQualificationAssessment reloaded)
          @?= 3
        Qualification.supervisedQualificationIndex0Metric reloaded @?= 1
        length (Qualification.supervisedQualificationOutcomes reloaded) @?= 5
        case NonEmpty.nonEmpty (Qualification.supervisedQualificationOutcomes refined) of
          Just outcomes ->
            show refined
              @?= "SupervisedQualification "
              <> showsPrec 11 raw " "
              <> showsPrec 11 outcomes " "
              <> showsPrec 11 (Qualification.supervisedQualificationAssessment refined) ""
          Nothing -> fail "refined fixture lost its five outcomes"
    , testCase "classification and regression retain exact public bytes, predictions and decisions" $ do
        for_ [False, True] $ \regression ->
          for_ [[True, True, True, False, False], [True, True, False, False, False]] $ \successes -> do
            (plan, raw) <- expectRight (fixtureForRetention regression successes)
            refined <- assertExactPublicProjection plan raw
            let assessment = Qualification.supervisedQualificationAssessment refined
                expectedMetric = if regression then 0 else 1
            fmap
              Qualification.supervisedSeedOutcomeObservation
              (Qualification.supervisedQualificationOutcomes refined)
              @?= zipWith (expectedObservation regression) (Qualification.rawQualificationSeeds raw) successes
            Policy.supervisedCohortJointSuccessCount assessment @?= length (filter id successes)
            Policy.supervisedCohortMedian assessment
              @?= if length (filter id successes) >= 3 then expectedMetric else if regression then 1 else 0.5
            Policy.supervisedCohortServedMetric assessment @?= expectedMetric
            isRight (Qualification.qualifySupervisedCohort refined) @?= (length (filter id successes) >= 3)
    , testCase "retained qualification releases the original classification and regression feature lists" $ do
        for_ [False, True] $ \regression -> do
          (refined, weakFeatures, expected) <- retainedFeaturesWorker regression
          performGC
          collected <- traverse deRefWeak weakFeatures
          -- The later opaque IO call keeps the qualification live across GC;
          -- the worker returned no raw DTO, examples or serialized baseline.
          qualificationFingerprint refined >>= (@?= expected)
          assertBool
            "retained qualification still owns original boxed feature lists"
            (all isNothing collected)
    , testCase "retained seed and reviewed-producer bytes release their shared oversized backing buffer" $ do
        for_ [False, True] $ \supplied -> do
          (refined, released, expected) <- retainedBackingWorker supplied
          collected <- awaitBackingRelease 20 released
          qualificationFingerprint refined >>= (@?= expected)
          assertBool "retained slices still own the original oversized byte buffer" collected
    , testCase "unchanged initial/final raw weights are retained and cannot qualify as learning" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 False))
        refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
        assertRejected (Qualification.qualifySupervisedCohort refined)
        for_ (Qualification.supervisedQualificationOutcomes refined) $ \outcome -> do
          initial <-
            expectRight
              ( Initial.decodeInitialComparisonSnapshot
                  (Qualification.supervisedSeedOutcomeInitialSnapshotBytes outcome)
              )
          Initial.rawInitialComparisonJmw1Bytes (Initial.initialComparisonSnapshotToRaw initial)
            @?= Qualification.supervisedSeedOutcomeFinalJmw1Bytes outcome
        Policy.supervisedCohortJointSuccessCount (Qualification.supervisedQualificationAssessment refined)
          @?= 0
    , testCase "a winning auxiliary cannot replace the predetermined index zero" $ do
        (plan, raw) <- expectRight (classificationFixture [False, True, True, True, True])
        refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
        Policy.supervisedCohortJointSuccessCount (Qualification.supervisedQualificationAssessment refined)
          @?= 4
        Policy.supervisedCohortMedian (Qualification.supervisedQualificationAssessment refined) @?= 1
        Qualification.supervisedQualificationIndex0Metric refined @?= 0.5
        assertRejected (Qualification.qualifySupervisedCohort refined)
    , testCase
        "finite below-floor members survive portable encoding rather than becoming completed checkpoints"
        $ do
          (plan, raw) <- expectRight (classificationFixture [True, True, False, False, False])
          refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
          reloaded <-
            expectRight
              ( Qualification.decodeSupervisedQualification
                  plan
                  (Qualification.encodeSupervisedQualification refined)
              )
          fmap
            Qualification.supervisedSeedOutcomeToRaw
            (Qualification.supervisedQualificationOutcomes reloaded)
            @?= Qualification.rawQualificationSeeds raw
          Policy.supervisedCohortMedian (Qualification.supervisedQualificationAssessment reloaded) @?= 0.5
          assertRejected (Qualification.qualifySupervisedCohort reloaded)
    , testCase "missing, duplicate, reordered and substituted child plans are rejected before replay" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        first <- expectFirst (Qualification.rawQualificationSeeds raw)
        let seeds = Qualification.rawQualificationSeeds raw
        for_ [take 4 seeds, seeds <> [first], reverse seeds, first : first : drop 2 seeds] $ \invalid ->
          assertRejected
            (Qualification.refineSupervisedQualification plan raw {Qualification.rawQualificationSeeds = invalid})
        for_
          [ first {Qualification.rawSeedValue = Qualification.rawSeedValue first + 1}
          , first {Qualification.rawSeedPlanId = digest "f"}
          , first {Qualification.rawSeedPlanTransport = Qualification.rawSeedPlanTransport first <> "tampered"}
          , first {Qualification.rawSeedAttemptIdentity = "invented-receipt"}
          ]
          $ \invalid ->
            assertRejected (Qualification.refineSupervisedQualification plan (replaceFirst invalid raw))
    , testCase "producer-observed counters must match every unchanged child budget" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        first <- expectFirst (Qualification.rawQualificationSeeds raw)
        for_
          [ first {Qualification.rawSeedObservedEpochs = 0}
          , first {Qualification.rawSeedObservedExamples = Qualification.rawSeedObservedExamples first - 1}
          , first
              { Qualification.rawSeedObservedOptimizerUpdates =
                  Qualification.rawSeedObservedOptimizerUpdates first + 1
              }
          ]
          $ \invalid ->
            assertRejected (Qualification.refineSupervisedQualification plan (replaceFirst invalid raw))
    , testCase "dataset, evaluation and final descriptor identities cannot be borrowed between children" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        first <- expectFirst (Qualification.rawQualificationSeeds raw)
        for_
          [ first {Qualification.rawSeedDatasetSha256 = digest "f"}
          , first {Qualification.rawSeedEvaluationSha256 = digest "f"}
          , first {Qualification.rawSeedFinalRuntimeSha256 = digest "f"}
          , first {Qualification.rawSeedFinalGraphSha256 = digest "f"}
          ]
          $ \invalid ->
            assertRejected (Qualification.refineSupervisedQualification plan (replaceFirst invalid raw))
        assertRejected
          ( Qualification.refineSupervisedQualification
              plan
              raw {Qualification.rawQualificationDatasetSha256 = digest "f"}
          )
    , testCase "changing the shared held-out ordering cannot keep its old exact data binding" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        case Qualification.rawQualificationEvaluation raw of
          Qualification.RawClassificationEvaluation examples ->
            assertRejected
              ( Qualification.refineSupervisedQualification
                  plan
                  raw
                    { Qualification.rawQualificationEvaluation =
                        Qualification.RawClassificationEvaluation (reverse examples)
                    }
              )
          _ -> fail "classification fixture changed task"
    , testCase
        "a self-consistent final descriptor hash still cannot replace the actual initial descriptor"
        $ do
          (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
          let metadata =
                (Qualification.rawQualificationGraphMetadata raw)
                  { Metadata.layerGraphMetadataName = "substituted descriptor"
                  }
              changed =
                raw
                  { Qualification.rawQualificationGraphMetadata = metadata
                  , Qualification.rawQualificationSeeds =
                      fmap
                        ( \seed -> seed {Qualification.rawSeedFinalGraphSha256 = Qualification.qualificationGraphSha256 metadata}
                        )
                        (Qualification.rawQualificationSeeds raw)
                  }
          assertLeftContains
            "graph descriptors differ"
            (Qualification.refineSupervisedQualification plan changed)
    , testCase "a self-consistent final transform hash cannot substitute a different inference transform" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        let runtime =
              (Qualification.rawQualificationRuntime raw)
                { Runtime.rawSupervisedRuntimeOutputTransform = Runtime.RawIdentityOutput
                }
            changed =
              raw
                { Qualification.rawQualificationRuntime = runtime
                , Qualification.rawQualificationSeeds =
                    fmap
                      ( \seed ->
                          seed {Qualification.rawSeedFinalRuntimeSha256 = Qualification.qualificationRuntimeSha256 runtime}
                      )
                      (Qualification.rawQualificationSeeds raw)
                }
        assertLeftContains
          "runtime transforms differ"
          (Qualification.refineSupervisedQualification plan changed)
    , testCase "classification requires the exact layer-training backend for its projected lane" $ do
        for_ backendIdentityCases $ \(substrate, layerBackend, _mlpBackend) -> do
          (plan, raw) <- expectRight (classificationFixtureFor substrate layerBackend (replicate 5 True))
          _ <- expectRight (Qualification.refineSupervisedQualification plan raw)
          first <- expectFirst (Qualification.rawQualificationSeeds raw)
          let witness = Qualification.rawSeedDeviceWitness first
              wrongBackends =
                ["onednn", "cuda", "metal", "", "unknown-backend"]
                  <> [other | (_, other, _) <- backendIdentityCases, other /= layerBackend]
          for_ wrongBackends $ \backend ->
            assertBackendRejected
              backend
              ( Qualification.refineSupervisedQualification
                  plan
                  ( replaceFirst
                      first {Qualification.rawSeedDeviceWitness = witness {DeviceWitness.rawWitnessBackend = backend}}
                      raw
                  )
              )
    , testCase "regression retains the exact MLP backend and rejects layer-training identities" $ do
        for_ backendIdentityCases $ \(substrate, _layerBackend, mlpBackend) -> do
          (plan, raw) <- expectRight (regressionFixtureFor substrate mlpBackend (replicate 5 True))
          _ <- expectRight (Qualification.refineSupervisedQualification plan raw)
          first <- expectFirst (Qualification.rawQualificationSeeds raw)
          let witness = Qualification.rawSeedDeviceWitness first
              wrongBackends =
                [other | (_, other, _) <- backendIdentityCases]
                  <> [other | (_, _, other) <- backendIdentityCases, other /= mlpBackend]
                  <> ["", "unknown-backend"]
          for_ wrongBackends $ \backend ->
            assertBackendRejected
              backend
              ( Qualification.refineSupervisedQualification
                  plan
                  ( replaceFirst
                      first {Qualification.rawSeedDeviceWitness = witness {DeviceWitness.rawWitnessBackend = backend}}
                      raw
                  )
              )
    , testCase "wrong-lane or malformed device declarations do not pass data refinement" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        first <- expectFirst (Qualification.rawQualificationSeeds raw)
        let witness = Qualification.rawSeedDeviceWitness first
        for_
          [ witness {DeviceWitness.rawWitnessSubstrate = "apple-silicon"}
          , witness {DeviceWitness.rawWitnessBackend = "metal"}
          , witness {DeviceWitness.rawWitnessArtifactSha256 = "not-a-sha"}
          ]
          $ \invalid ->
            assertRejected
              ( Qualification.refineSupervisedQualification
                  plan
                  (replaceFirst first {Qualification.rawSeedDeviceWitness = invalid} raw)
              )
    , testCase "malformed or nonfinite initial/final parameter blobs are rejected" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        first <- expectFirst (Qualification.rawQualificationSeeds raw)
        for_
          [ first {Qualification.rawSeedInitialSnapshotBytes = "not-cbor"}
          , first
              { Qualification.rawSeedInitialSnapshotBytes =
                  Qualification.rawSeedInitialSnapshotBytes first <> ByteString.singleton 0
              }
          , first {Qualification.rawSeedFinalJmw1Bytes = "not-jmw1"}
          ]
          $ \invalid ->
            assertRejected (Qualification.refineSupervisedQualification plan (replaceFirst invalid raw))
        snapshot <-
          expectRight
            (Initial.decodeInitialComparisonSnapshot (Qualification.rawSeedInitialSnapshotBytes first))
        let nonfiniteJmw1 = LazyByteString.toStrict (WeightCodec.encodeJmw1 ((0 / 0) : replicate 19 0))
            nonfiniteInitial =
              (Initial.initialComparisonSnapshotToRaw snapshot)
                { Initial.rawInitialComparisonJmw1Bytes = nonfiniteJmw1
                }
        for_
          [ first
              { Qualification.rawSeedInitialSnapshotBytes = LazyByteString.toStrict (serialise nonfiniteInitial)
              }
          , first {Qualification.rawSeedFinalJmw1Bytes = nonfiniteJmw1}
          ]
          $ \invalid ->
            assertLeftContains
              "tensor values must be finite"
              (Qualification.refineSupervisedQualification plan (replaceFirst invalid raw))
    , testCase "canonical decoding rejects trailing, truncated and unsupported-version CBOR" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
        let bytes = Qualification.encodeSupervisedQualification refined
        assertRejected (Qualification.decodeSupervisedQualification plan (bytes <> ByteString.singleton 0))
        assertRejected (Qualification.decodeSupervisedQualification plan (ByteString.take 10 bytes))
        assertRejected
          ( Qualification.decodeSupervisedQualification
              plan
              (LazyByteString.toStrict (serialise raw {Qualification.rawQualificationVersion = 2}))
          )
    , testCase "held-out binary64 bytes preserve signed zero rather than ordinary Double equality" $ do
        let positive = Qualification.RawClassificationEvaluation [([0.0], 0)]
            negative = Qualification.RawClassificationEvaluation [([negate 0.0], 0)]
        positive @?= negative
        assertBool "signed-zero payload distinction was lost" $
          Qualification.qualificationEvaluationSha256 positive
            /= Qualification.qualificationEvaluationSha256 negative
    , testCase "packed public projection preserves signed-zero feature and regression-target bits" $ do
        bits <- newIORef (0x8000000000000000 :: Word64)
        negative <- runtimeDouble <$> readIORef bits
        for_ [False, True] $ \regression -> do
          (plan, raw) <- expectRight (fixtureForRetention regression (replicate 5 True))
          let withZero value = case Qualification.rawQualificationEvaluation raw of
                Qualification.RawClassificationEvaluation examples ->
                  Qualification.RawClassificationEvaluation (([value], 0) : withoutFirst examples)
                Qualification.RawRegressionEvaluation scale examples ->
                  Qualification.RawRegressionEvaluation scale (([value], value) : withoutFirst examples)
              positive = withZero 0
              signed = withZero negative
          positive @?= signed
          assertBool "runtime negative zero lost its binary64 sign" $
            Qualification.qualificationEvaluationSha256 positive
              /= Qualification.qualificationEvaluationSha256 signed
          _ <- assertExactPublicProjection plan (replaceEvaluation positive raw)
          _ <- assertExactPublicProjection plan (replaceEvaluation signed raw)
          pure ()
    , testCase
        "nonfinite shared inputs or a wrong evaluation count cannot be hidden behind an updated digest"
        $ do
          (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
          for_
            [ Qualification.RawClassificationEvaluation (replicate 1000 ([0 / 0], 0))
            , Qualification.RawClassificationEvaluation (replicate 1000 ([0, 0], 0))
            , Qualification.RawClassificationEvaluation [([0], 0)]
            , Qualification.RawClassificationEvaluation (replicate 1000 ([0], 10))
            ]
            $ \invalid ->
              assertRejected (Qualification.refineSupervisedQualification plan (replaceEvaluation invalid raw))
    , testCase "classification and regression artifacts cannot replace each other's evaluation channels" $ do
        (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
        assertRejected
          ( Qualification.refineSupervisedQualification
              plan
              (replaceEvaluation (Qualification.RawRegressionEvaluation 1 (replicate 1000 ([0], 0))) raw)
          )
    , testCase
        "regression replays strict initial improvement and positive skill using actual graph outputs"
        $ do
          (plan, raw) <- expectRight (regressionFixture [True, True, True, False, False])
          refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
          _ <- expectRight (Qualification.qualifySupervisedCohort refined)
          Policy.supervisedCohortJointSuccessCount (Qualification.supervisedQualificationAssessment refined)
            @?= 3
          Qualification.supervisedQualificationIndex0Metric refined @?= 0
    , testCase "a regression scale cannot be inflated independently of the serving transform" $ do
        (plan, raw) <- expectRight (regressionFixture (replicate 5 True))
        case Qualification.rawQualificationEvaluation raw of
          Qualification.RawRegressionEvaluation _ examples ->
            assertLeftContains
              "runtime target transform"
              ( Qualification.refineSupervisedQualification
                  plan
                  (replaceEvaluation (Qualification.RawRegressionEvaluation 100 examples) raw)
              )
          _ -> fail "regression fixture changed task"
    , testCase
        "source/executable/invocation identifiers are required but are never authenticated by a pure parser"
        $ do
          (plan, raw) <- expectRight (classificationFixture (replicate 5 True))
          let producer = Qualification.rawQualificationProducer raw
          for_
            [ producer {Qualification.rawQualificationSourceSha256 = ""}
            , producer {Qualification.rawQualificationExecutableSha256 = "not-a-hash"}
            , producer {Qualification.rawQualificationInvocationSha256 = "future-journal"}
            ]
            $ \invalid ->
              assertRejected
                ( Qualification.refineSupervisedQualification
                    plan
                    raw {Qualification.rawQualificationProducer = invalid}
                )
    ]

assertExactPublicProjection
  :: Cohort.SupervisedCohortPlan
  -> Qualification.RawSupervisedQualification
  -> IO Qualification.SupervisedQualification
assertExactPublicProjection plan raw = do
  refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
  let expectedWire = LazyByteString.toStrict (serialise raw)
      expectedEvaluation = serialise (Qualification.rawQualificationEvaluation raw)
  Qualification.supervisedQualificationToRaw refined @?= raw
  Qualification.encodeSupervisedQualification refined @?= expectedWire
  Qualification.supervisedQualificationSha256 refined
    @?= WeightCodec.jmw1ContentSha (LazyByteString.fromStrict expectedWire)
  Qualification.supervisedQualificationEvaluationBytes refined
    @?= LazyByteString.toStrict expectedEvaluation
  Qualification.qualificationEvaluationSha256
    (Qualification.supervisedQualificationEvaluation refined)
    @?= WeightCodec.jmw1ContentSha expectedEvaluation
  Qualification.supervisedQualificationRuntime refined @?= Qualification.rawQualificationRuntime raw
  Qualification.supervisedQualificationGraphMetadata refined
    @?= Qualification.rawQualificationGraphMetadata raw
  fmap
    Qualification.supervisedSeedOutcomeToRaw
    (Qualification.supervisedQualificationOutcomes refined)
    @?= Qualification.rawQualificationSeeds raw
  first <- expectFirst (Qualification.rawQualificationSeeds raw)
  Qualification.supervisedSeedOutcomeToRaw
    (Qualification.supervisedQualificationIndex0Outcome refined)
    @?= first
  reloaded <- expectRight (Qualification.decodeSupervisedQualification plan expectedWire)
  reloaded @?= refined
  Qualification.encodeSupervisedQualification reloaded @?= expectedWire
  Qualification.supervisedQualificationAssessment reloaded
    @?= Qualification.supervisedQualificationAssessment refined
  pure refined

expectedObservation
  :: Bool
  -> Qualification.RawSupervisedSeedOutcome
  -> Bool
  -> Policy.SupervisedSeedObservation
expectedObservation regression seed success =
  Policy.SupervisedSeedObservation
    (Qualification.rawSeedIndex seed)
    (Qualification.rawSeedValue seed)
    (Qualification.rawSeedObservedEpochs seed)
    (Qualification.rawSeedObservedExamples seed)
    (Qualification.rawSeedObservedOptimizerUpdates seed)
    ( if regression
        then
          Policy.RegressionPredictionPair
            (replicate 1000 0)
            (if success then take 1000 (cycle [-1, 1]) else replicate 1000 0)
        else Policy.ClassificationPredictionPair 500 (if success then 1000 else 500)
    )

fixtureForRetention
  :: Bool
  -> [Bool]
  -> Either Text (Cohort.SupervisedCohortPlan, Qualification.RawSupervisedQualification)
fixtureForRetention regression = if regression then regressionFixture else classificationFixture

-- The IORef read and opaque function keep each feature list out of static
-- fixtures/full-laziness sharing. Weak keys name the actual forced cons cells.
{-# NOINLINE runtimeFeatures #-}
runtimeFeatures :: Int -> Int -> [Double]
runtimeFeatures salt index = [fromIntegral (if even index then negate (salt + 1) else salt + 1)]

{-# NOINLINE runtimeDouble #-}
runtimeDouble :: Word64 -> Double
runtimeDouble = castWord64ToDouble

{-# NOINLINE qualificationFingerprint #-}
qualificationFingerprint :: Qualification.SupervisedQualification -> IO Text
qualificationFingerprint value = evaluate (Qualification.supervisedQualificationSha256 value)

{-# NOINLINE retainedFeaturesWorker #-}
retainedFeaturesWorker
  :: Bool -> IO (Qualification.SupervisedQualification, [Weak [Double]], Text)
retainedFeaturesWorker regression = do
  source <- newIORef (0 :: Int)
  salt <- readIORef source
  features <- traverse (evaluate . runtimeFeatures salt) [0 .. 999]
  weakFeatures <- traverse (`mkWeakPtr` Nothing) features
  (plan, original) <- expectRight (fixtureForRetention regression [True, True, True, False, False])
  let evaluation =
        if regression
          then Qualification.RawRegressionEvaluation 1 (zip features (take 1000 (cycle [-1, 1])))
          else Qualification.RawClassificationEvaluation (zip features (take 1000 (cycle [0, 1])))
  refined <-
    expectRight
      (Qualification.refineSupervisedQualification plan (replaceEvaluation evaluation original))
  fingerprint <- qualificationFingerprint refined
  pure (refined, weakFeatures, fingerprint)

-- All eleven payload views share one allocated buffer: a copied qualification
-- must release it while retaining byte-identical review and all ten seed blobs.
-- The finalizer observes the allocation itself, not a disposable ByteString
-- wrapper whose collection would say nothing about slice backing retention.
{-# NOINLINE retainedBackingWorker #-}
retainedBackingWorker :: Bool -> IO (Qualification.SupervisedQualification, IORef Bool, Text)
retainedBackingWorker supplied = do
  (plan, original) <- expectRight (regressionFixture [True, True, True, False, False])
  reviewBytes <- expectRight reviewedProducerFixture
  let seeds = Qualification.rawQualificationSeeds original
      payload = ByteString.concat (reviewBytes : concatMap seedBytes seeds)
      padding = 1024 * 1024
      total = padding + ByteString.length payload
  released <- newIORef False
  pointer <- mallocBytes total
  allocation <- Foreign.newForeignPtr pointer (free pointer >> writeIORef released True)
  withForeignPtr allocation $ \target -> do
    fillBytes target 0 padding
    ByteString.useAsCStringLen payload $ \(source, count) -> copyBytes (target `plusPtr` padding) (castPtr source) count
  let backing = ByteString.Internal.fromForeignPtr allocation 0 total
      view offset count = ByteString.take count (ByteString.drop offset backing)
      payloadLengths = fmap ByteString.length (reviewBytes : concatMap seedBytes seeds)
      views = zipWith view (scanl (+) padding payloadLengths) payloadLengths
  case views of
    reviewView : seedViews -> do
      slicedSeeds <- expectRight (replaceSeedSlices seeds seedViews)
      let producer = Qualification.rawQualificationProducer original
          reviewed =
            ( if supplied
                then Qualification.RawSuppliedReviewedQualificationProducer
                else Qualification.RawObservedReviewedQualificationProducer
            )
              (Qualification.rawQualificationSourceSha256 producer)
              (Qualification.rawQualificationExecutableSha256 producer)
              (Qualification.rawQualificationInvocationSha256 producer)
              reviewView
          raw =
            original
              { Qualification.rawQualificationProducer = reviewed
              , Qualification.rawQualificationSeeds = slicedSeeds
              }
      refined <- expectRight (Qualification.refineSupervisedQualification plan raw)
      fingerprint <- qualificationFingerprint refined
      Qualification.qualificationProducerReviewWasSupplied
        (Qualification.rawQualificationProducer (Qualification.supervisedQualificationToRaw refined))
        @?= supplied
      pure (refined, released, fingerprint)
    [] -> fail "backing fixture has no review payload"
 where
  seedBytes seed = [Qualification.rawSeedInitialSnapshotBytes seed, Qualification.rawSeedFinalJmw1Bytes seed]

replaceSeedSlices
  :: [Qualification.RawSupervisedSeedOutcome]
  -> [ByteString.ByteString]
  -> Either Text [Qualification.RawSupervisedSeedOutcome]
replaceSeedSlices [] [] = Right []
replaceSeedSlices (seed : rest) (initial : final : views) =
  ( seed
      { Qualification.rawSeedInitialSnapshotBytes = initial
      , Qualification.rawSeedFinalJmw1Bytes = final
      }
      :
  )
    <$> replaceSeedSlices rest views
replaceSeedSlices _ _ = Left "backing fixture payload count differs from its five seeds"

reviewedProducerFixture :: Either Text ByteString.ByteString
reviewedProducerFixture =
  Review.encodeCriterionReviewIdentityData
    ( Review.CriterionReviewIdentityData
        Review.SupervisedCriterionReview
        LinuxCPU
        source
        (Registration.SelectedLaneFileData (Text.pack selection) (digest "a") 1)
        ( Registration.SelectedLaneFileData
            (Text.pack (takeDirectory selection </> "receipt.cbor"))
            (digest "b")
            1
        )
        (digest "c")
    )
 where
  source = SourceStamp sourceDigestAlgorithm (digest "1")
  selection = Review.criterionReviewSelectionPath source LinuxCPU Review.SupervisedCriterionReview

awaitBackingRelease :: Int -> IORef Bool -> IO Bool
awaitBackingRelease remaining released = do
  performGC
  observed <- readIORef released
  if observed || remaining <= 0
    then pure observed
    else threadDelay 10000 >> awaitBackingRelease (remaining - 1) released

classificationFixture
  :: [Bool] -> Either Text (Cohort.SupervisedCohortPlan, Qualification.RawSupervisedQualification)
classificationFixture = classificationFixtureFor LinuxCPU "linux-cpu-onednn"

classificationFixtureFor
  :: Substrate
  -> Text
  -> [Bool]
  -> Either Text (Cohort.SupervisedCohortPlan, Qualification.RawSupervisedQualification)
classificationFixtureFor substrate backend successes = do
  let runtime =
        Runtime.RawSupervisedRuntime
          (Runtime.RawClassificationRuntimeTask 10)
          (Runtime.RawIdentityInput 1)
          (Runtime.RawSemanticPrefixOutput 10)
      examples = take 1000 (cycle [([-1], 0), ([1], 1)])
      initial = replicate 20 0
      final = [-1, 1] <> replicate 18 0
  fixture
    substrate
    backend
    "mnist-shallow-mlp"
    10
    runtime
    (Qualification.RawClassificationEvaluation examples)
    initial
    [if success then final else initial | success <- successes]

regressionFixture
  :: [Bool] -> Either Text (Cohort.SupervisedCohortPlan, Qualification.RawSupervisedQualification)
regressionFixture = regressionFixtureFor LinuxCPU "onednn"

regressionFixtureFor
  :: Substrate
  -> Text
  -> [Bool]
  -> Either Text (Cohort.SupervisedCohortPlan, Qualification.RawSupervisedQualification)
regressionFixtureFor substrate backend successes = do
  let runtime =
        Runtime.RawSupervisedRuntime
          (Runtime.RawRegressionRuntimeTask 1)
          (Runtime.RawIdentityInput 1)
          (Runtime.RawDestandardizeOutput [0] [1])
      examples = take 1000 (cycle [([-1], -1), ([1], 1)])
  fixture
    substrate
    backend
    "california-housing-mlp"
    1
    runtime
    (Qualification.RawRegressionEvaluation 1 examples)
    [0, 0]
    [if success then [1, 0] else [0, 0] | success <- successes]

fixture
  :: Substrate
  -> Text
  -> Text
  -> Int
  -> Runtime.RawSupervisedRuntime
  -> Qualification.RawQualificationEvaluation
  -> [Double]
  -> [[Double]]
  -> Either Text (Cohort.SupervisedCohortPlan, Qualification.RawSupervisedQualification)
fixture substrate backend rowName outputs runtime evaluation initial finals = do
  row <-
    maybe
      (Left "fixture canonical row is absent")
      Right
      (List.find ((== rowName) . Matrix.rowId) Matrix.allProductRows)
  projection <-
    case Matrix.projectProductRow substrate row of
      Plan.Success (Matrix.SomeProductProjection Plan.SupervisedTrainingWitness value) -> Right value
      _ -> Left "fixture row did not project to supervised execution"
  plan <- Cohort.mkSupervisedCohortPlan projection
  problem <-
    maybe
      (Left "fixture problem is absent")
      Right
      (List.find ((== rowName) . Canonicals.problemName) Canonicals.canonicalProblems)
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  node <-
    Graph.mkAffineLayer
      "synthetic qualification comparison"
      1
      outputs
      Graph.LinearActivation
      Graph.InferenceMode
      (Graph.LayerParameters (VU.replicate outputs 0) (VU.replicate outputs 0))
  let graph =
        Graph.LayerGraph
          "synthetic qualification graph"
          (Graph.TensorShape [1])
          (Graph.TensorShape [outputs])
          [node]
      metadata = Metadata.layerGraphMetadataFromGraph graph
      producer = Qualification.RawQualificationProducer (digest "1") (digest "2") (digest "3")
  initialSnapshot <-
    Initial.refineInitialComparisonSnapshot
      ( Initial.RawInitialComparisonSnapshot
          1
          runtime
          metadata
          (LazyByteString.toStrict (WeightCodec.encodeJmw1 initial))
      )
  let makeSeed child final =
        let workload = Cohort.supervisedSeedPlanWorkload child
            epochs = Plan.quantityValue (Workload.supervisedPlanEpochs workload)
            training = Plan.quantityValue (Workload.supervisedPlanTrainingExamples workload)
         in Qualification.RawSupervisedSeedOutcome
              { Qualification.rawSeedIndex = Policy.supervisedSeedIndexValue (Cohort.supervisedSeedPlanIndex child)
              , Qualification.rawSeedValue = Cohort.supervisedSeedPlanSeed child
              , Qualification.rawSeedPlanId = Plan.planIdText (Workload.supervisedPlanId workload)
              , Qualification.rawSeedPlanTransport = Workload.renderSupervisedPlanTransport workload
              , Qualification.rawSeedAttemptIdentity =
                  Qualification.prescribedSupervisedChildAttempt
                    (Qualification.rawQualificationInvocationSha256 producer)
                    child
              , Qualification.rawSeedObservedEpochs = epochs
              , Qualification.rawSeedObservedExamples = epochs * training
              , Qualification.rawSeedObservedOptimizerUpdates =
                  Plan.quantityValue (Workload.supervisedPlanOptimizerUpdates workload)
              , Qualification.rawSeedDatasetSha256 = datasetSha
              , Qualification.rawSeedEvaluationSha256 = Qualification.qualificationEvaluationSha256 evaluation
              , Qualification.rawSeedFinalRuntimeSha256 = Qualification.qualificationRuntimeSha256 runtime
              , Qualification.rawSeedFinalGraphSha256 = Qualification.qualificationGraphSha256 metadata
              , Qualification.rawSeedDeviceWitness = rawFixtureWitness substrate backend
              , Qualification.rawSeedInitialSnapshotBytes = Initial.encodeInitialComparisonSnapshot initialSnapshot
              , Qualification.rawSeedFinalJmw1Bytes = LazyByteString.toStrict (WeightCodec.encodeJmw1 final)
              }
      seeds = zipWith makeSeed (Cohort.supervisedCohortPlanChildren plan) finals
  refined <-
    Qualification.buildSupervisedQualification plan producer evaluation runtime metadata seeds
  Right (plan, Qualification.supervisedQualificationToRaw refined)

backendIdentityCases :: [(Substrate, Text, Text)]
backendIdentityCases =
  [ (LinuxCPU, "linux-cpu-onednn", "onednn")
  , (LinuxCUDA, "linux-cuda-cudnn", "cuda")
  , (AppleSilicon, "apple-metal-fixed-bridge", "metal")
  ]

rawFixtureWitness :: Substrate -> Text -> DeviceWitness.RawDeviceExecutionWitness
rawFixtureWitness substrate backend =
  DeviceWitness.RawDeviceExecutionWitness
    (renderSubstrate substrate)
    backend
    (digest "a")
    "declared-fixture.so"
    (digest "b")
    "declared-fixture-forward"

assertBackendRejected :: Text -> Either Text value -> IO ()
assertBackendRejected backend
  | Text.null backend = assertLeftContains "requires a backend identity"
  | otherwise = assertLeftContains "qualification device witness backend mismatch"

replaceFirst
  :: Qualification.RawSupervisedSeedOutcome
  -> Qualification.RawSupervisedQualification
  -> Qualification.RawSupervisedQualification
replaceFirst first raw =
  raw
    { Qualification.rawQualificationSeeds = first : withoutFirst (Qualification.rawQualificationSeeds raw)
    }

replaceEvaluation
  :: Qualification.RawQualificationEvaluation
  -> Qualification.RawSupervisedQualification
  -> Qualification.RawSupervisedQualification
replaceEvaluation evaluation raw =
  let identity = Qualification.qualificationEvaluationSha256 evaluation
   in raw
        { Qualification.rawQualificationEvaluation = evaluation
        , Qualification.rawQualificationEvaluationSha256 = identity
        , Qualification.rawQualificationSeeds =
            fmap
              (\seed -> seed {Qualification.rawSeedEvaluationSha256 = identity})
              (Qualification.rawQualificationSeeds raw)
        }

digest :: Text -> Text
digest = Text.replicate 64

expectRight :: Either Text value -> IO value
expectRight = either (fail . Text.unpack) pure

expectFirst :: [value] -> IO value
expectFirst (first : _) = pure first
expectFirst [] = fail "five-seed fixture became empty"

assertRejected :: Either error value -> IO ()
assertRejected = assertBool "malformed or unqualified fixture unexpectedly passed" . isLeft

assertLeftContains :: Text -> Either Text value -> IO ()
assertLeftContains fragment result =
  case result of
    Left message -> assertBool (Text.unpack message) (fragment `Text.isInfixOf` message)
    Right _ -> fail ("fixture unexpectedly passed: " <> Text.unpack fragment)

-- | Total base-only drop-one preserving the exact adversarial outcome list.
withoutFirst :: [value] -> [value]
withoutFirst [] = []
withoutFirst (_ : rest) = rest
