{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module SupervisedCheckpointV2
  ( supervisedCheckpointV2Tests
  , main
  )
where

import Codec.Serialise (Serialise, deserialiseOrFail, serialise)
import Control.Concurrent
  ( forkFinally
  , newEmptyMVar
  , putMVar
  , readMVar
  , takeMVar
  )
import Control.Exception (SomeException, fromException, try)
import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ReaderT, ask, runReaderT)
import Data.ByteString qualified as StrictByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (digitToInt)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find, sortOn)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Plan.Plan qualified as Plan
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher qualified as ProductPublisher
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as Runtime
import JitML.SL.TrainingExecution qualified as TrainingExecution
import JitML.Service.Capabilities
  ( HasMinIO (..)
  , ObjectRef
  )
import JitML.Service.Retry (ServiceError (..))
import JitML.Substrate qualified as Substrate
import JitML.Training.Budget qualified as TrainingBudget

supervisedCheckpointV2Tests :: TestTree
supervisedCheckpointV2Tests =
  testGroup
    "SupervisedCheckpointV2"
    [ testCase "canonical V2 retains exact addressed outer and body identities" $ do
        fixture <- expectRight makeFixture
        addressed <-
          expectRight
            (Checkpoint.decodeAddressedManifestCbor (fixtureBytes fixture))
        Checkpoint.addressedManifest addressed @?= fixtureManifest fixture
        Checkpoint.addressedManifestWireVersion addressed
          @?= Checkpoint.checkpointWireVersionV2
        Checkpoint.addressedManifestBytes addressed @?= fixtureBytes fixture
        Checkpoint.addressedManifestSha addressed
          @?= Checkpoint.manifestContentSha (fixtureManifest fixture)
        Checkpoint.addressedManifestBodyBytes addressed
          @?= Just (Checkpoint.rawCheckpointV2BodyBytes (fixtureOuter fixture))
        Checkpoint.addressedManifestBodySha addressed
          @?= Just
            ( exactSha
                (Checkpoint.rawCheckpointV2BodyBytes (fixtureOuter fixture))
            )
        Checkpoint.rawCheckpointV2BodyBytes (fixtureOuter fixture)
          @?= LazyByteString.toStrict (serialise (fixtureBody fixture))

        completion <-
          expectRight
            ( Checkpoint.validateCheckpointCompletion
                (Checkpoint.addressedManifest addressed)
            )
        Checkpoint.validatedCheckpointCompletionManifest completion
          @?= fixtureManifest fixture
        Just (Checkpoint.validatedCheckpointCompletedTraining completion)
          @?= Checkpoint.manifestCompletedTraining (fixtureManifest fixture)
    , checkpointStoreAdmissionTests
    , testCase "canonical training/evaluation dataset digest is admitted for Product and generic V2" $ do
        problem <-
          maybe
            (assertFailure "missing canonical mnist-shallow-mlp problem")
            pure
            (find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems)
        expected <- expectRight (Dataset.canonicalDatasetReadShaForProblem problem)
        expected
          @?= "835e2223df22dc754ec3283a2064c6b09be176f225ddfdc6aa0e5e4a7169b668"
        mapM_
          ( \canonicalProblem -> do
              digest <-
                expectRight
                  (Dataset.canonicalDatasetReadShaForProblem canonicalProblem)
              case SL.problemDataset canonicalProblem of
                "MNIST" -> pure ()
                "Fashion-MNIST" -> pure ()
                archiveDataset ->
                  Dataset.canonicalArtifactSha256For
                    archiveDataset
                    Dataset.TrainSplit
                    Dataset.ArchiveArtifact
                    @?= Just digest
          )
          SL.canonicalProblems
        productFixture <- expectRight makeFixture
        (genericFixture, _) <- expectRight makeGenericFixture
        mapM_
          ( \fixture -> do
              Runtime.payloadDatasetSha256 (fixturePayload fixture) @?= expected
              Checkpoint.manifestDatasetShaAtRead (fixtureManifest fixture)
                @?= Just expected
              fmap
                TrainingBudget.completedTrainingDatasetShaAtRead
                (Checkpoint.manifestCompletedTraining (fixtureManifest fixture))
                @?= Just expected
              _ <-
                expectRight
                  (Checkpoint.decodeAddressedManifestCbor (fixtureBytes fixture))
              pure ()
          )
          [productFixture, genericFixture]
    , testCase "synchronized forged dataset digest is rejected for Product and generic V2" $ do
        productFixture <- expectRight makeFixture
        (genericFixture, _) <- expectRight makeGenericFixture
        mapM_
          ( \fixture -> do
              substituted <-
                expectRight
                  ( synchronizeV2DatasetSha
                      (Text.replicate 64 "f")
                      (fixtureBody fixture)
                  )
              assertLeftDirectV2
                "runtime payload dataset SHA-256 does not equal the canonical training/evaluation read SHA-256"
                (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
          )
          [productFixture, genericFixture]
    , testCase "V2 uses one physical tensor and graph-ordered virtual slices" $ do
        fixture <- expectRight makeFixture
        let manifest = fixtureManifest fixture
            runtime = Runtime.payloadRuntime (fixturePayload fixture)
            slices = Runtime.supervisedRuntimeVirtualSlices runtime
        Checkpoint.manifestTensors manifest
          @?= [ Checkpoint.TensorBlob
                  "supervised.weights"
                  [Runtime.supervisedRuntimeParameterCount runtime]
                  ( Checkpoint.blobKey
                      (Checkpoint.manifestExperiment manifest)
                      (Runtime.payloadFinalJmw1Sha256 (fixturePayload fixture))
                  )
              ]
        fmap Runtime.runtimeVirtualSliceQualifiedName slices
          @?= [ "dense-classifier.W1"
              , "dense-classifier.b1"
              , "dense-classifier.W2"
              , "dense-classifier.b2"
              ]
        fmap Runtime.runtimeVirtualSliceOffset slices
          @?= [0, 100352, 100480, 101888]
        fmap Runtime.runtimeVirtualSliceLength slices
          @?= [100352, 128, 1408, 11]
        Checkpoint.manifestWeightLayout manifest
          @?= Checkpoint.FlatWeightLayout (virtualSliceSpecs slices)
        Checkpoint.validateSupervisedManifestShapeLayout manifest @?= []
    , testCase "canonical runtime metadata carries exact transforms and semantic decoder" $ do
        fixture <- expectRight makeFixture
        let manifest = fixtureManifest fixture
        Checkpoint.architectureInputs (Checkpoint.manifestArchitecture manifest)
          @?= [Checkpoint.TensorSpec "input" [784] "F64"]
        Checkpoint.architectureOutputs (Checkpoint.manifestArchitecture manifest)
          @?= [Checkpoint.TensorSpec "raw-output" [11] "F64"]
        fmap Checkpoint.preprocessingSteps (Checkpoint.manifestPreprocessing manifest)
          @?= [
                [ "unit-image-[0,1]"
                , "geometry=RawRuntimeImageGeometry {rawRuntimeImageWidth = 28, rawRuntimeImageHeight = 28, rawRuntimeImageChannels = 1}"
                ]
              ]
        Checkpoint.manifestOutputDecoders manifest
          @?= [ Checkpoint.OutputDecoder
                  { Checkpoint.outputDecoderName = "prediction"
                  , Checkpoint.outputDecoderKind = Checkpoint.ClassificationOutput
                  , Checkpoint.outputDecoderLabels =
                      fmap (("class-" <>) . Text.pack . show) [0 .. 9 :: Int]
                  , Checkpoint.outputDecoderUnits = Nothing
                  , Checkpoint.outputDecoderArtifactKind =
                      Just "supervised-runtime-v2/semantic-prefix/10"
                  }
              ]
    , testCase "cifar10-vit admission requires the exact repeated fitted RGB transform" $ do
        payload <- expectRight makeCifarVitPayload
        metadata <-
          expectRight
            (Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload)
        case Checkpoint.supervisedRuntimePreprocessingMetadata metadata of
          [preprocessing] ->
            case Checkpoint.preprocessingSteps preprocessing of
              "standardize" : _ -> pure ()
              steps -> assertFailure ("unexpected CIFAR ViT preprocessing steps: " <> show steps)
          preprocessing ->
            assertFailure
              ("unexpected CIFAR ViT preprocessing metadata: " <> show preprocessing)

        let rawPayload = Runtime.supervisedRuntimePayloadToRaw payload
            payloadRuntime = Runtime.rawRuntimePayloadRuntime rawPayload
            unitImagePayload =
              rawPayload
                { Runtime.rawRuntimePayloadRuntime =
                    payloadRuntime
                      { Runtime.rawSupervisedRuntimeInputTransform =
                          Runtime.RawUnitImageInput
                            (Runtime.RawRuntimeImageGeometry 32 32 3)
                      }
                }
            substitutedMeans =
              case Runtime.rawSupervisedRuntimeInputTransform payloadRuntime of
                Runtime.RawStandardizeInput (_ : rest) scales ->
                  Runtime.RawStandardizeInput (0.6 : rest) scales
                transform -> transform
            perPixelPayload =
              rawPayload
                { Runtime.rawRuntimePayloadRuntime =
                    payloadRuntime
                      { Runtime.rawSupervisedRuntimeInputTransform = substitutedMeans
                      }
                }
            outOfRangeMeanPayload =
              rawPayload
                { Runtime.rawRuntimePayloadRuntime =
                    payloadRuntime
                      { Runtime.rawSupervisedRuntimeInputTransform =
                          Runtime.RawStandardizeInput
                            (concat (replicate 1024 [1.1, 0.4, 0.3]))
                            (concat (replicate 1024 [0.2, 0.25, 0.3]))
                      }
                }
            excessiveScalePayload =
              rawPayload
                { Runtime.rawRuntimePayloadRuntime =
                    payloadRuntime
                      { Runtime.rawSupervisedRuntimeInputTransform =
                          Runtime.RawStandardizeInput
                            (concat (replicate 1024 [0.5, 0.4, 0.3]))
                            (concat (replicate 1024 [0.6, 0.25, 0.3]))
                      }
                }
        unitImage <- expectRight (Runtime.refineSupervisedRuntimePayload unitImagePayload)
        assertLeftContaining
          "must be fitted RGB standardization"
          (Checkpoint.canonicalSupervisedRuntimeManifestMetadata unitImage)
        perPixel <- expectRight (Runtime.refineSupervisedRuntimePayload perPixelPayload)
        assertLeftContaining
          "must repeat one RGB triplet per pixel"
          (Checkpoint.canonicalSupervisedRuntimeManifestMetadata perPixel)
        outOfRangeMean <-
          expectRight (Runtime.refineSupervisedRuntimePayload outOfRangeMeanPayload)
        assertLeftContaining
          "finite decoded-unit values"
          (Checkpoint.canonicalSupervisedRuntimeManifestMetadata outOfRangeMean)
        excessiveScale <-
          expectRight (Runtime.refineSupervisedRuntimePayload excessiveScalePayload)
        assertLeftContaining
          "decoded-unit population scales"
          (Checkpoint.canonicalSupervisedRuntimeManifestMetadata excessiveScale)
    , testCase "non-ViT classifiers cannot substitute fitted standardization" $ do
        fixture <- expectRight makeFixture
        let payload = Runtime.supervisedRuntimePayloadToRaw (fixturePayload fixture)
            runtime = Runtime.rawRuntimePayloadRuntime payload
            standardized =
              payload
                { Runtime.rawRuntimePayloadRuntime =
                    runtime
                      { Runtime.rawSupervisedRuntimeInputTransform =
                          Runtime.RawStandardizeInput
                            (replicate 784 0.0)
                            (replicate 784 1.0)
                      }
                }
        refined <- expectRight (Runtime.refineSupervisedRuntimePayload standardized)
        assertLeftContaining
          "classification input transform differs"
          (Checkpoint.canonicalSupervisedRuntimeManifestMetadata refined)
    , testCase "frozen V1 golden remains byte-for-byte stable" $ do
        let golden =
              Checkpoint.emptyManifest
                "v1-golden"
                "exp-v1"
                [ Checkpoint.TensorBlob
                    "weights"
                    [2]
                    "jitml-checkpoints/exp-v1/blobs/golden"
                ]
            bytes = Checkpoint.encodeManifestCbor golden
        LazyByteString.length bytes @?= 134
        Checkpoint.manifestContentSha golden
          @?= "30db4da59975960c71c1e694472eca7d6b577acc2127e6381ef15e4b4949bb4b"
        addressed <- expectRight (Checkpoint.decodeAddressedManifestCbor bytes)
        Checkpoint.addressedManifestWireVersion addressed
          @?= Checkpoint.checkpointWireVersion
        Checkpoint.addressedManifestBytes addressed @?= bytes
    , testCase "historical supervised ProductRow V1 fails completion refinement" $ do
        fixture <- expectRight makeFixture
        let historical =
              (fixtureManifest fixture)
                { Checkpoint.manifestModelFamily = Checkpoint.GenericModelFamily
                , Checkpoint.manifestArchitecture =
                    Checkpoint.defaultArchitectureMetadata Checkpoint.GenericModelFamily
                , Checkpoint.manifestSupervisedRuntime = Nothing
                }
            bytes = Checkpoint.encodeManifestCbor historical
        addressed <- expectRight (Checkpoint.decodeAddressedManifestCbor bytes)
        Checkpoint.addressedManifestWireVersion addressed
          @?= Checkpoint.checkpointWireVersion
        Checkpoint.manifestModelFamily (Checkpoint.addressedManifest addressed)
          @?= Checkpoint.GenericModelFamily
        Checkpoint.manifestSupervisedRuntime (Checkpoint.addressedManifest addressed)
          @?= Nothing
        Checkpoint.validateCheckpointCompletion
          (Checkpoint.addressedManifest addressed)
          @?= Left Checkpoint.SupervisedRuntimeArtifactMissing
    , testCase "a supervised completion budget makes generic V1 inspection-only" $ do
        fixture <- expectRight makeFixture
        let historical =
              (fixtureManifest fixture)
                { Checkpoint.manifestExperiment = "unknown-supervised-v1"
                , Checkpoint.manifestModelFamily = Checkpoint.GenericModelFamily
                , Checkpoint.manifestArchitecture =
                    Checkpoint.defaultArchitectureMetadata Checkpoint.GenericModelFamily
                , Checkpoint.manifestPreprocessing = []
                , Checkpoint.manifestOutputDecoders = []
                , Checkpoint.manifestSupervisedRuntime = Nothing
                }
            bytes = Checkpoint.encodeManifestCbor historical
        addressed <- expectRight (Checkpoint.decodeAddressedManifestCbor bytes)
        Checkpoint.validateCheckpointCompletion
          (Checkpoint.addressedManifest addressed)
          @?= Left Checkpoint.SupervisedRuntimeArtifactMissing
    , testCase "supervised architecture metadata alone makes generic V1 inspection-only" $ do
        fixture <- expectRight makeFixture
        let historical =
              (fixtureManifest fixture)
                { Checkpoint.manifestExperiment = "unknown-supervised-architecture-v1"
                , Checkpoint.manifestModelFamily = Checkpoint.GenericModelFamily
                , Checkpoint.manifestCompletedTraining = Nothing
                , Checkpoint.manifestPreprocessing = []
                , Checkpoint.manifestOutputDecoders = []
                , Checkpoint.manifestSupervisedRuntime = Nothing
                }
            bytes = Checkpoint.encodeManifestCbor historical
        addressed <- expectRight (Checkpoint.decodeAddressedManifestCbor bytes)
        Checkpoint.validateCheckpointCompletion
          (Checkpoint.addressedManifest addressed)
          @?= Left Checkpoint.SupervisedRuntimeArtifactMissing
    , testCase "outer address is derived from exact bytes rather than a caller label" $ do
        fixture <- expectRight makeFixture
        addressed <-
          expectRight
            (Checkpoint.decodeAddressedManifestCbor (fixtureBytes fixture))
        Checkpoint.addressedManifestSha addressed
          @?= exactSha (LazyByteString.toStrict (fixtureBytes fixture))
        assertBool
          "decoded address accepted a substituted caller label"
          (Checkpoint.addressedManifestSha addressed /= Text.replicate 64 "0")
    , testCase "body digest and exact body bytes are independently checked" $ do
        fixture <- expectRight makeFixture
        let outer = fixtureOuter fixture
            badDigest =
              serialise
                outer
                  { Checkpoint.rawCheckpointV2BodySha256 =
                      StrictByteString.replicate 32 0
                  }
            truncatedBody =
              StrictByteString.init (Checkpoint.rawCheckpointV2BodyBytes outer)
            badBody =
              serialise
                outer
                  { Checkpoint.rawCheckpointV2BodySha256 = shaBytes truncatedBody
                  , Checkpoint.rawCheckpointV2BodyBytes = truncatedBody
                  }
        assertLeftDirectV2
          "body SHA-256 mismatch"
          (Checkpoint.decodeAddressedManifestCbor badDigest)
        assertLeftDirectV2
          "invalid V2 checkpoint body"
          (Checkpoint.decodeAddressedManifestCbor badBody)
    , testCase "noncanonical V2 base ordering is rejected without fallback" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            noncanonical =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestMetrics =
                          [ ("z-diagnostic", 0.0)
                          , (fixtureMetricName fixture, 1.0)
                          ]
                      }
                }
        assertLeftDirectV2
          "not in canonical value order"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody noncanonical))
    , testCase "virtual-slice substitution is rejected" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            substitutedLayout =
              case Checkpoint.rawManifestWeightLayout rawManifest of
                Checkpoint.FlatWeightLayout (first : rest) ->
                  Checkpoint.FlatWeightLayout
                    ( first
                        { Checkpoint.tensorSpecName = "classifier.W1.substituted"
                        }
                        : rest
                    )
                other -> other
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestWeightLayout = substitutedLayout
                      }
                }
        assertLeftDirectV2
          "FlatWeightLayout does not equal the graph-ordered virtual slices"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testCase "physical tensor substitution is rejected" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestTensors =
                          [ Checkpoint.TensorBlob
                              "substituted.weights"
                              [fixtureParameterCount fixture]
                              ( Checkpoint.blobKey
                                  (Checkpoint.rawManifestExperiment rawManifest)
                                  (Runtime.payloadFinalJmw1Sha256 (fixturePayload fixture))
                              )
                          ]
                      }
                }
        assertLeftDirectV2
          "physical tensor must be named supervised.weights"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testGroup
        "exact runtime/completion bindings"
        ( fmap
            bindingSubstitutionTest
            [
              ( "PlanId"
              , \payload ->
                  payload
                    { Runtime.rawRuntimePayloadPlanId = Text.replicate 64 "c"
                    }
              , "PlanId does not match manifest PlanId"
              )
            ,
              ( "dataset"
              , \payload ->
                  payload
                    { Runtime.rawRuntimePayloadDatasetSha256 = Text.replicate 64 "d"
                    }
              , "dataset SHA-256 does not match manifest"
              )
            ,
              ( "initial JMW1 identity"
              , \payload ->
                  payload
                    { Runtime.rawRuntimePayloadInitialJmw1Sha256 = Text.replicate 64 "e"
                    }
              , "initial-weight SHA-256 does not match manifest"
              )
            ,
              ( "final JMW1 identity"
              , \payload ->
                  payload
                    { Runtime.rawRuntimePayloadFinalJmw1Sha256 = Text.replicate 64 "f"
                    }
              , "final-weight SHA-256 does not match manifest"
              )
            ]
        )
    , testCase "canonical PlanId uniquely derives and binds the selected substrate" $ do
        fixture <- expectRight makeFixture
        Checkpoint.validateSupervisedRuntimePlanForSubstrate
          Substrate.LinuxCPU
          (fixturePayload fixture)
          @?= Right ()
        assertLeftContaining
          "runtime selected substrate differs"
          ( Checkpoint.validateSupervisedRuntimePlanForSubstrate
              Substrate.LinuxCUDA
              (fixturePayload fixture)
          )
    , testCase "internally synchronized but noncanonical PlanId is rejected" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            bogusPlanId = Text.replicate 64 "f"
            payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            synchronizedManifest =
              rawManifest
                { Checkpoint.rawManifestPlanId = Just bogusPlanId
                , Checkpoint.rawManifestCompletedTraining =
                    fmap
                      ( \completed ->
                          completed
                            { TrainingBudget.rawCompletedTrainingPlanId = bogusPlanId
                            }
                      )
                      (Checkpoint.rawManifestCompletedTraining rawManifest)
                }
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest = synchronizedManifest
                , Checkpoint.rawCheckpointV2SupervisedRuntime =
                    payload
                      { Runtime.rawRuntimePayloadPlanId = bogusPlanId
                      }
                }
        assertLeftDirectV2
          "runtime PlanId does not equal any authoritative ProductRow substrate projection"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testCase "synchronized completion budget and manifest step substitution is rejected" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            substitutedUnits = Checkpoint.rawManifestStep rawManifest + 1
            substitutedCompleted =
              fmap
                ( \completed ->
                    completed
                      { TrainingBudget.rawCompletedTrainingBudget =
                          (TrainingBudget.rawCompletedTrainingBudget completed)
                            { TrainingBudget.rawTrainingBudgetTargetUnits =
                                substitutedUnits
                            }
                      , TrainingBudget.rawCompletedTrainingObservedUnits =
                          substitutedUnits
                      }
                )
                (Checkpoint.rawManifestCompletedTraining rawManifest)
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestStep = substitutedUnits
                      , Checkpoint.rawManifestCompletedTraining =
                          substitutedCompleted
                      }
                }
        assertLeftDirectV2
          "completed training budget target does not match the authoritative ProductRow training budget"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testCase "synchronized evidence and manifest update-count substitution is rejected" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
        completed <-
          maybe
            (assertFailure "fixture raw manifest is missing completed training")
            pure
            (Checkpoint.rawManifestCompletedTraining rawManifest)
        canonicalUpdateCount <-
          maybe
            (assertFailure "fixture raw manifest is missing its update count")
            pure
            (Checkpoint.rawManifestUpdateCount rawManifest)
        let substitutedUpdateCount = canonicalUpdateCount + 1
            evidence = TrainingBudget.rawCompletedTrainingEvidence completed
        substitutedEvidence <-
          expectRight
            ( ProductEvidence.mkTrainingEvidence
                (ProductEvidence.evidenceInitialWeightHash evidence)
                (ProductEvidence.evidenceFinalWeightHash evidence)
                substitutedUpdateCount
                (ProductEvidence.evidenceDatasetShaAtRead evidence)
            )
        let substitutedCompleted =
              completed
                { TrainingBudget.rawCompletedTrainingEvidence =
                    substitutedEvidence
                }
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestCompletedTraining =
                          Just substitutedCompleted
                      , Checkpoint.rawManifestUpdateCount =
                          Just substitutedUpdateCount
                      }
                }
        assertLeftDirectV2
          "completed-training evidence update count does not match the authoritative SupervisedPlan optimizer-update count"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testCase "manifest convergence metric is exactly bound to completed training" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestMetrics =
                          [(fixtureMetricName fixture, 0.99)]
                      }
                }
        assertLeftDirectV2
          "manifest metric differs from completed training"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testCase "duplicate manifest convergence metric is rejected" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            duplicate = (fixtureMetricName fixture, 1.0)
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestMetrics = [duplicate, duplicate]
                      }
                }
        assertLeftDirectV2
          "manifest has duplicate metric name"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testGroup
        "completed-training TensorBoard binding"
        [ tensorBoardSubstitutionTest
            "run id"
            (\metadata -> metadata {TrainingBudget.tbrRunId = "forged-run"})
            "TensorBoard run id does not match manifest experiment"
        , tensorBoardSubstitutionTest
            "log prefix"
            (\metadata -> metadata {TrainingBudget.tbrLogPrefix = "forged-prefix"})
            "TensorBoard log prefix does not match manifest experiment"
        , tensorBoardSubstitutionTest
            "scalar tags"
            (\metadata -> metadata {TrainingBudget.tbrScalarTags = ["forged-tag"]})
            "TensorBoard scalar tags do not exactly match convergence metrics"
        ]
    , testGroup
        "authoritative ProductRow runtime contract"
        [ runtimeSubstitutionTest
            "family"
            ( \runtime ->
                runtime
                  { Runtime.rawSupervisedRuntimeFamily =
                      Runtime.RawDeepDenseRuntimeFamily
                  , Runtime.rawSupervisedRuntimeLayers =
                      [ Runtime.RawDenseLayer
                          "substituted-1"
                          (Runtime.RawRuntimeMlpShape 784 4 4)
                      , Runtime.RawDenseLayer
                          "substituted-2"
                          (Runtime.RawRuntimeMlpShape 4 4 11)
                      ]
                  }
            )
            "classification runtime family differs"
        , runtimeSubstitutionTest
            "task"
            ( \runtime ->
                runtime
                  { Runtime.rawSupervisedRuntimeTask =
                      Runtime.RawClassificationRuntimeTask 9
                  , Runtime.rawSupervisedRuntimeOutputTransform =
                      Runtime.RawSemanticPrefixOutput 9
                  }
            )
            "classification runtime task differs"
        , runtimeSubstitutionTest
            "production input dimension"
            ( \runtime ->
                runtime
                  { Runtime.rawSupervisedRuntimeInputTransform =
                      Runtime.RawIdentityInput 785
                  , Runtime.rawSupervisedRuntimeLayers =
                      [ Runtime.RawDenseLayer
                          "dense-classifier"
                          (Runtime.RawRuntimeMlpShape 785 128 11)
                      ]
                  }
            )
            "classification production input width differs"
        , runtimeSubstitutionTest
            "production output dimension"
            ( \runtime ->
                runtime
                  { Runtime.rawSupervisedRuntimeLayers =
                      [ Runtime.RawDenseLayer
                          "dense-classifier"
                          (Runtime.RawRuntimeMlpShape 784 128 12)
                      ]
                  }
            )
            "classification production raw-output width differs"
        , runtimeSubstitutionTest
            "layer topology"
            ( \runtime ->
                runtime
                  { Runtime.rawSupervisedRuntimeLayers =
                      [ Runtime.RawDenseLayer
                          "renamed-classifier"
                          (Runtime.RawRuntimeMlpShape 784 128 11)
                      ]
                  }
            )
            "classification runtime topology differs"
        ]
    , testGroup
        "manifest metadata is exactly bound to the runtime projection"
        [ manifestSubstitutionTest
            "architecture"
            ( \manifest ->
                manifest
                  { Checkpoint.rawManifestArchitecture =
                      (Checkpoint.rawManifestArchitecture manifest)
                        { Checkpoint.architectureInputs =
                            [Checkpoint.TensorSpec "substituted-input" [784] "F64"]
                        }
                  }
            )
            "architecture metadata does not equal the exact runtime projection"
        , manifestSubstitutionTest
            "preprocessing"
            ( \manifest ->
                manifest
                  { Checkpoint.rawManifestPreprocessing =
                      [ Checkpoint.PreprocessingMetadata
                          "substituted-preprocessing"
                          ["identity"]
                          [Checkpoint.TensorSpec "input" [784] "F64"]
                      ]
                  }
            )
            "preprocessing metadata does not equal the exact runtime projection"
        , manifestSubstitutionTest
            "output decoder"
            ( \manifest ->
                manifest
                  { Checkpoint.rawManifestOutputDecoders =
                      [ Checkpoint.OutputDecoder
                          "prediction"
                          Checkpoint.ClassificationOutput
                          ["wrong-label"]
                          Nothing
                          (Just "supervised-runtime-v2/semantic-prefix/10")
                      ]
                  }
            )
            "output-decoder metadata does not equal the exact runtime projection"
        ]
    , testCase "runtime row and manifest experiment cannot be independently substituted" $ do
        fixture <- expectRight makeFixture
        row <-
          maybe
            (assertFailure "missing authoritative fashion-mnist-mlp ProductRow")
            pure
            (find ((== "fashion-mnist-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
        projection <- expectRight (authoritativeSupervisedProjection Substrate.LinuxCPU row)
        let body = fixtureBody fixture
            payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
            substitutedPlanId =
              Plan.planIdText (ProductMatrix.productProjectionPlanId projection)
            substitutedCompleted =
              fmap
                ( \completed ->
                    completed
                      { TrainingBudget.rawCompletedTrainingPlanId =
                          substitutedPlanId
                      }
                )
                (Checkpoint.rawManifestCompletedTraining rawManifest)
            substituted =
              body
                { Checkpoint.rawCheckpointV2Manifest =
                    rawManifest
                      { Checkpoint.rawManifestPlanId = Just substitutedPlanId
                      , Checkpoint.rawManifestCompletedTraining = substitutedCompleted
                      }
                , Checkpoint.rawCheckpointV2SupervisedRuntime =
                    payload
                      { Runtime.rawRuntimePayloadRowId = "fashion-mnist-mlp"
                      , Runtime.rawRuntimePayloadPlanId = substitutedPlanId
                      }
                }
        assertLeftDirectV2
          "manifest experiment does not equal the authoritative supervised ProductRow experiment hash"
          (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
    , testGroup
        "closed supervised V2 origin contract"
        [ testCase "canonical generic plan transport satisfies completion refinement" $ do
            (fixture, plan) <- expectRight makeGenericFixture
            addressed <-
              expectRight
                (Checkpoint.decodeAddressedManifestCbor (fixtureBytes fixture))
            completion <-
              expectRight
                ( Checkpoint.validateCheckpointCompletion
                    (Checkpoint.addressedManifest addressed)
                )
            Checkpoint.validatedCheckpointCompletionManifest completion
              @?= fixtureManifest fixture
            Runtime.supervisedRuntimeOriginToRaw
              (Runtime.payloadOrigin (fixturePayload fixture))
              @?= Runtime.RawGenericSupervisedExecutionOrigin
                "mnist-shallow-mlp"
                (WorkloadPlan.renderSupervisedPlanTransport plan)
            Checkpoint.manifestExperiment (Checkpoint.addressedManifest addressed)
              @?= Plan.runPlanExperimentId
                (WorkloadPlan.supervisedPlanRunPlan plan)
            Checkpoint.validateSupervisedRuntimePlanForSubstrate
              Substrate.LinuxCPU
              (fixturePayload fixture)
              @?= Right ()
        , testCase "malformed generic plan transport is rejected directly as V2" $ do
            (fixture, _) <- expectRight makeGenericFixture
            let body = fixtureBody fixture
                payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
                substituted =
                  body
                    { Checkpoint.rawCheckpointV2SupervisedRuntime =
                        payload
                          { Runtime.rawRuntimePayloadOrigin =
                              Runtime.RawGenericSupervisedExecutionOrigin
                                "mnist-shallow-mlp"
                                "not-a-supervised-plan-transport"
                          }
                    }
            assertLeftDirectV2
              "generic supervised runtime plan transport is invalid"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "parseable but noncanonical generic plan transport is rejected" $ do
            (fixture, plan) <- expectRight makeGenericFixture
            let body = fixtureBody fixture
                payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
                canonical = WorkloadPlan.renderSupervisedPlanTransport plan
                noncanonical =
                  Text.intercalate "|" (reverse (Text.splitOn "|" canonical))
                substituted =
                  body
                    { Checkpoint.rawCheckpointV2SupervisedRuntime =
                        payload
                          { Runtime.rawRuntimePayloadOrigin =
                              Runtime.RawGenericSupervisedExecutionOrigin
                                "mnist-shallow-mlp"
                                noncanonical
                          }
                    }
            assertLeftDirectV2
              "generic supervised runtime canonical plan transport differs"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "generic payload PlanId substitution is rejected" $ do
            (fixture, _) <- expectRight makeGenericFixture
            let body = fixtureBody fixture
                payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
                substituted =
                  body
                    { Checkpoint.rawCheckpointV2SupervisedRuntime =
                        payload
                          { Runtime.rawRuntimePayloadPlanId = Text.replicate 64 "f"
                          }
                    }
            assertLeftDirectV2
              "generic supervised runtime PlanId differs"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "generic execution-origin row substitution is rejected" $ do
            (fixture, _) <- expectRight makeGenericFixture
            let body = fixtureBody fixture
                payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
                origin = Runtime.rawRuntimePayloadOrigin payload
                substitutedOrigin =
                  case origin of
                    Runtime.RawGenericSupervisedExecutionOrigin _ transport ->
                      Runtime.RawGenericSupervisedExecutionOrigin
                        "cifar10-resnet20"
                        transport
                    Runtime.RawProductRowProjectionOrigin -> origin
                substituted =
                  body
                    { Checkpoint.rawCheckpointV2SupervisedRuntime =
                        payload
                          { Runtime.rawRuntimePayloadOrigin = substitutedOrigin
                          }
                    }
            assertLeftDirectV2
              "generic supervised execution origin row id differs"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "synchronized generic row substitution cannot retain another row's runtime" $ do
            (fixture, _) <- expectRight makeGenericFixture
            let body = fixtureBody fixture
                payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
                origin = Runtime.rawRuntimePayloadOrigin payload
                substitutedOrigin =
                  case origin of
                    Runtime.RawGenericSupervisedExecutionOrigin _ transport ->
                      Runtime.RawGenericSupervisedExecutionOrigin
                        "cifar10-resnet20"
                        transport
                    Runtime.RawProductRowProjectionOrigin -> origin
                substituted =
                  body
                    { Checkpoint.rawCheckpointV2SupervisedRuntime =
                        payload
                          { Runtime.rawRuntimePayloadRowId = "cifar10-resnet20"
                          , Runtime.rawRuntimePayloadOrigin = substitutedOrigin
                          }
                    }
            assertLeftDirectV2
              "classification production input width differs"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "generic V2 manifest cannot occupy a ProductRow experiment hash" $ do
            (genericFixture, _) <- expectRight makeGenericFixture
            productFixture <- expectRight makeFixture
            let genericBody = fixtureBody genericFixture
                genericManifest = Checkpoint.rawCheckpointV2Manifest genericBody
                productExperiment =
                  Checkpoint.rawManifestExperiment
                    (Checkpoint.rawCheckpointV2Manifest (fixtureBody productFixture))
                substituted =
                  genericBody
                    { Checkpoint.rawCheckpointV2Manifest =
                        genericManifest
                          { Checkpoint.rawManifestExperiment = productExperiment
                          }
                    }
            assertLeftDirectV2
              "generic supervised V2 manifest cannot occupy an authoritative ProductRow experiment hash"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "ProductRow payload cannot substitute generic origin" $ do
            fixture <- expectRight makeFixture
            (plan, _, _, _, _) <- expectRight makeTrainingCompletionFixture
            let body = fixtureBody fixture
                payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
                substituted =
                  body
                    { Checkpoint.rawCheckpointV2SupervisedRuntime =
                        payload
                          { Runtime.rawRuntimePayloadOrigin =
                              Runtime.RawGenericSupervisedExecutionOrigin
                                "mnist-shallow-mlp"
                                (WorkloadPlan.renderSupervisedPlanTransport plan)
                          }
                    }
            assertLeftDirectV2
              "generic supervised runtime plan occupies authoritative ProductRow experiment identity"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))
        , testCase "generic completion is bound to exact plan budget and update count" $ do
            (fixture, _) <- expectRight makeGenericFixture
            let body = fixtureBody fixture
                rawManifest = Checkpoint.rawCheckpointV2Manifest body
            completed <-
              maybe
                (assertFailure "generic fixture raw manifest is missing completed training")
                pure
                (Checkpoint.rawManifestCompletedTraining rawManifest)
            canonicalUpdateCount <-
              maybe
                (assertFailure "generic fixture raw manifest is missing its update count")
                pure
                (Checkpoint.rawManifestUpdateCount rawManifest)
            let substitutedUnits = Checkpoint.rawManifestStep rawManifest + 1
                budgetSubstitution =
                  body
                    { Checkpoint.rawCheckpointV2Manifest =
                        rawManifest
                          { Checkpoint.rawManifestStep = substitutedUnits
                          , Checkpoint.rawManifestCompletedTraining =
                              Just
                                completed
                                  { TrainingBudget.rawCompletedTrainingBudget =
                                      (TrainingBudget.rawCompletedTrainingBudget completed)
                                        { TrainingBudget.rawTrainingBudgetTargetUnits =
                                            substitutedUnits
                                        }
                                  , TrainingBudget.rawCompletedTrainingObservedUnits =
                                      substitutedUnits
                                  }
                          }
                    }
            assertLeftDirectV2
              "completed training budget target does not match the exact generic SupervisedPlan training budget"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody budgetSubstitution))

            let substitutedUpdateCount = canonicalUpdateCount + 1
                evidence = TrainingBudget.rawCompletedTrainingEvidence completed
            substitutedEvidence <-
              expectRight
                ( ProductEvidence.mkTrainingEvidence
                    (ProductEvidence.evidenceInitialWeightHash evidence)
                    (ProductEvidence.evidenceFinalWeightHash evidence)
                    substitutedUpdateCount
                    (ProductEvidence.evidenceDatasetShaAtRead evidence)
                )
            let updateSubstitution =
                  body
                    { Checkpoint.rawCheckpointV2Manifest =
                        rawManifest
                          { Checkpoint.rawManifestCompletedTraining =
                              Just
                                completed
                                  { TrainingBudget.rawCompletedTrainingEvidence =
                                      substitutedEvidence
                                  }
                          , Checkpoint.rawManifestUpdateCount =
                              Just substitutedUpdateCount
                          }
                    }
            assertLeftDirectV2
              "completed-training evidence update count does not match the authoritative SupervisedPlan optimizer-update count"
              (Checkpoint.decodeAddressedManifestCbor (wrapBody updateSubstitution))
        ]
    , testCase "California projection carries fitted transforms and explicit target unit" $ do
        payload <- expectRight makeCaliforniaPayload
        metadata <-
          expectRight
            (Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload)
        Checkpoint.architectureInputs
          (Checkpoint.supervisedRuntimeArchitectureMetadata metadata)
          @?= [Checkpoint.TensorSpec "input" [8] "F64"]
        Checkpoint.architectureOutputs
          (Checkpoint.supervisedRuntimeArchitectureMetadata metadata)
          @?= [Checkpoint.TensorSpec "raw-output" [1] "F64"]
        Checkpoint.supervisedRuntimeOutputDecoderMetadata metadata
          @?= [ Checkpoint.OutputDecoder
                  "prediction"
                  Checkpoint.RegressionOutput
                  []
                  (Just "median-house-value")
                  (Just "supervised-runtime-v2/destandardize/means=[100.0]/scales=[5.0]")
              ]
    , testCase "generic V1 writer rejects supervised identities and permits non-supervised families" $ do
        fixture <- expectRight makeFixture
        assertLeftContaining
          "cannot emit authoritative supervised ProductRow"
          ( CheckpointWriter.validateGenericV1CandidateWriterRequest
              (Checkpoint.manifestExperiment (fixtureManifest fixture))
              "weights"
          )
        assertLeftContaining
          "cannot emit reserved supervised tensor identity"
          ( CheckpointWriter.validateGenericV1CandidateWriterRequest
              "non-product-experiment"
              "legacy-row-sl-weights"
          )
        case Checkpoint.manifestCompletedTraining (fixtureManifest fixture) of
          Nothing -> assertFailure "fixture is missing completed training"
          Just completed ->
            assertLeftContaining
              "cannot emit a supervised completed-training witness"
              ( CheckpointWriter.validateGenericV1CompletedWriterRequest
                  completed
                  "non-product-experiment"
                  "weights"
              )
        case find
          ((== ProductMatrix.ReinforcementLearning) . ProductMatrix.family)
          ProductMatrix.allProductRows of
          Nothing -> assertFailure "missing authoritative RL ProductRow"
          Just rlRow ->
            CheckpointWriter.validateGenericV1CandidateWriterRequest
              (ProductMatrix.productRowExperimentHash rlRow)
              "rl-ppo-weights"
              @?= Right ()
    , testCase "supervised completion consumes the synchronized training-returned update count" $ do
        (plan, problem, metrics, experiment, metricRows) <-
          expectRight makeTrainingCompletionFixture
        (completed, _) <-
          expectRight
            ( CheckpointWriter.completedSupervisedRuntimeForTraining
                plan
                problem
                metrics
                experiment
                metricRows
            )
        TrainingBudget.completedTrainingUpdateCount completed
          @?= TrainingExecution.tmOptimizerUpdatesExecuted metrics
        TrainingExecution.tmOptimizerUpdatesExecuted metrics
          @?= Plan.quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
    , testCase "strict Product-origin completion rejects a non-authoritative experiment" $ do
        (plan, problem, metrics, _, metricRows) <-
          expectRight makeTrainingCompletionFixture
        assertLeftContaining
          "Product-origin supervised checkpoint experiment does not equal the authoritative ProductRow experiment"
          ( CheckpointWriter.completedSupervisedRuntimeForTraining
              plan
              problem
              metrics
              "not-the-product-row-experiment"
              metricRows
          )
    , testCase "strict supervised writer rejects a forged canonical problem record" $ do
        (plan, problem, metrics, experiment, metricRows) <-
          expectRight makeTrainingCompletionFixture
        let forgedProblem = problem {SL.problemSeed = SL.problemSeed problem + 1}
        assertLeftContaining
          "problem record differs from the authoritative canonical problem"
          ( CheckpointWriter.completedSupervisedRuntimeForTraining
              plan
              forgedProblem
              metrics
              experiment
              metricRows
          )
    , testCase "generic finite below-bar completion ignores absent legacy weight projections" $ do
        (productPlan, problem, metrics, _, _) <-
          expectRight makeTrainingCompletionFixture
        plan <-
          expectRight
            (genericSupervisedPlanFrom "generic-below-bar-no-lists" productPlan)
        let metricName =
              maybe
                "test_accuracy"
                ( ProductConvergence.convergenceMetricName
                    . ProductMatrix.convergenceBar
                )
                ( find
                    ((== SL.problemName problem) . ProductMatrix.rowId)
                    ProductMatrix.allProductRows
                )
            belowBar =
              metrics
                { TrainingExecution.tmHeldOutMetric = Just (metricName, 0.0)
                , TrainingExecution.tmInitialCheckpointWeights = Nothing
                , TrainingExecution.tmCheckpointWeights = Nothing
                , TrainingExecution.tmDatasetShaAtRead = Nothing
                }
            experiment =
              Plan.runPlanExperimentId
                (WorkloadPlan.supervisedPlanRunPlan plan)
        case CheckpointWriter.attemptGenericSupervisedRuntimeForTraining
          plan
          problem
          belowBar
          experiment
          (exactTrainingMetricRows belowBar) of
          Right (CheckpointWriter.SupervisedRuntimeCompletionMiss _) -> pure ()
          result ->
            assertFailure
              ("expected typed generic convergence miss, got " <> show result)
    , testCase "supervised completion rejects a substituted training-returned update count" $ do
        (plan, problem, metrics, experiment, metricRows) <-
          expectRight makeTrainingCompletionFixture
        let substituted =
              metrics
                { TrainingExecution.tmOptimizerUpdatesExecuted =
                    TrainingExecution.tmOptimizerUpdatesExecuted metrics + 1
                }
        assertLeftContaining
          "training-returned executed optimizer-update count does not match the authoritative SupervisedPlan"
          ( CheckpointWriter.completedSupervisedRuntimeForTraining
              plan
              problem
              substituted
              experiment
              metricRows
          )
    , testCase "production supervised publisher rejects a substituted executed update count" $ do
        (plan, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
        let run = supervisedPublishRunFixture metrics
        ProductPublisher.validateSupervisedPublishUpdateCount plan run @?= Right ()
        assertLeftContaining
          "training-returned executed optimizer-update count does not match the authoritative supervised ProductRow plan"
          ( ProductPublisher.validateSupervisedPublishUpdateCount
              plan
              run
                { ProductPublisher.supervisedPublishOptimizerUpdatesExecuted =
                    ProductPublisher.supervisedPublishOptimizerUpdatesExecuted run + 1
                }
          )
    , testCase "production supervised publisher owns the exact four-row metric vector" $ do
        row <-
          maybe
            (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
            pure
            (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
        (plan, _, metrics, _, metricRows) <- expectRight makeTrainingCompletionFixture
        ProductPublisher.supervisedPublishMetricRows
          row
          plan
          (supervisedPublishRunFixture metrics)
          @?= Right metricRows
    , testCase "production supervised publisher rejects an inexact processed-example observation" $ do
        row <-
          maybe
            (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
            pure
            (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
        (plan, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
        let run = supervisedPublishRunFixture metrics
        assertLeftContaining
          "processed-example count does not match epochs * training examples"
          ( ProductPublisher.supervisedPublishMetricRows
              row
              plan
              run
                { ProductPublisher.supervisedPublishExamplesProcessed =
                    ProductPublisher.supervisedPublishExamplesProcessed run + 1
                }
          )
    , testCase "production supervised publisher rejects malformed metric evidence" $ do
        row <-
          maybe
            (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
            pure
            (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
        (plan, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
        let run = supervisedPublishRunFixture metrics
            heldOutValue = maybe 1.0 snd (ProductPublisher.supervisedPublishHeldOutMetric run)
            duplicateBar =
              (ProductMatrix.convergenceBar row)
                { ProductConvergence.convergenceMetricName = "train_loss"
                }
            duplicateRow = row {ProductMatrix.convergenceBar = duplicateBar}
        assertLeftContaining
          "requires exactly one held-out metric"
          ( ProductPublisher.supervisedPublishMetricRows
              row
              plan
              run {ProductPublisher.supervisedPublishHeldOutMetric = Nothing}
          )
        assertLeftContaining
          "held-out metric name differs"
          ( ProductPublisher.supervisedPublishMetricRows
              row
              plan
              run
                { ProductPublisher.supervisedPublishHeldOutMetric =
                    Just ("substituted_metric", heldOutValue)
                }
          )
        assertLeftContaining
          "train_loss must be finite"
          ( ProductPublisher.supervisedPublishMetricRows
              row
              plan
              run {ProductPublisher.supervisedPublishTrainLoss = 0 / 0}
          )
        assertLeftContaining
          "contains duplicate metric names"
          ( ProductPublisher.supervisedPublishMetricRows
              duplicateRow
              plan
              run
                { ProductPublisher.supervisedPublishHeldOutMetric =
                    Just ("train_loss", heldOutValue)
                }
          )
    , testCase
        "ProductPublisher row boundary rejects the substituted count before completion/write callbacks"
        $ do
          row <-
            maybe
              (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
              pure
              (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          env <- buildEnv defaultGlobalFlags
          let synchronized = supervisedPublishRunFixture metrics
              substituted =
                synchronized
                  { ProductPublisher.supervisedPublishOptimizerUpdatesExecuted =
                      ProductPublisher.supervisedPublishOptimizerUpdatesExecuted synchronized + 1
                  }
              runtime = substitutedSupervisedPublisherRuntime substituted
          outcome <-
            ( try
                ( runReaderT
                    ( ProductPublisher.runTrainAndPublishProductRows
                        runtime
                        Substrate.LinuxCPU
                        [row]
                    )
                    env
                )
                :: IO (Either SomeException ())
            )
          case outcome of
            Left exception ->
              case fromException exception of
                Just (ExitFailure _) -> pure ()
                Just ExitSuccess -> assertFailure "substituted publisher unexpectedly exited successfully"
                Nothing ->
                  assertFailure
                    ( "substituted publisher reached a forbidden completion/write callback instead of yielding a row error: "
                        <> show exception
                    )
            Right () -> assertFailure "substituted publisher unexpectedly returned without a row error"
    , testCase
        "ProductPublisher row boundary rejects processed-example substitution before completion/write callbacks"
        $ do
          row <-
            maybe
              (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
              pure
              (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          env <- buildEnv defaultGlobalFlags
          let synchronized = supervisedPublishRunFixture metrics
              substituted =
                synchronized
                  { ProductPublisher.supervisedPublishExamplesProcessed =
                      ProductPublisher.supervisedPublishExamplesProcessed synchronized + 1
                  }
              runtime = substitutedSupervisedPublisherRuntime substituted
          outcome <-
            ( try
                ( runReaderT
                    ( ProductPublisher.runTrainAndPublishProductRows
                        runtime
                        Substrate.LinuxCPU
                        [row]
                    )
                    env
                )
                :: IO (Either SomeException ())
            )
          case outcome of
            Left exception ->
              case fromException exception of
                Just (ExitFailure _) -> pure ()
                Just ExitSuccess -> assertFailure "substituted publisher unexpectedly exited successfully"
                Nothing ->
                  assertFailure
                    ( "substituted publisher reached a forbidden completion/write callback instead of yielding a row error: "
                        <> show exception
                    )
            Right () -> assertFailure "substituted publisher unexpectedly returned without a row error"
    , testCase
        "ProductPublisher row boundary rejects dataset-digest substitution before completion/write callbacks"
        $ do
          row <-
            maybe
              (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
              pure
              (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
          (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
          env <- buildEnv defaultGlobalFlags
          let synchronized = supervisedPublishRunFixture metrics
              substituted =
                synchronized
                  { ProductPublisher.supervisedPublishVerifiedDatasetShaAtRead =
                      Text.replicate 64 "f"
                  }
              runtime = substitutedSupervisedPublisherRuntime substituted
          outcome <-
            ( try
                ( runReaderT
                    ( ProductPublisher.runTrainAndPublishProductRows
                        runtime
                        Substrate.LinuxCPU
                        [row]
                    )
                    env
                )
                :: IO (Either SomeException ())
            )
          case outcome of
            Left exception ->
              case fromException exception of
                Just (ExitFailure _) -> pure ()
                Just ExitSuccess -> assertFailure "substituted publisher unexpectedly exited successfully"
                Nothing ->
                  assertFailure
                    ( "substituted publisher reached a forbidden completion/write callback instead of yielding a row error: "
                        <> show exception
                    )
            Right () -> assertFailure "substituted publisher unexpectedly returned without a row error"
    , testCase "ProductPublisher passes the exact projected learning rate to supervised training" $ do
        row <-
          maybe
            (assertFailure "missing authoritative cifar10-resnet20 ProductRow")
            pure
            (find ((== "cifar10-resnet20") . ProductMatrix.rowId) ProductMatrix.allProductRows)
        (_, _, metrics, _, _) <- expectRight makeTrainingCompletionFixture
        observedRate <- newIORef Nothing
        env <- buildEnv defaultGlobalFlags
        let runtime =
              (substitutedSupervisedPublisherRuntime (supervisedPublishRunFixture metrics))
                { ProductPublisher.publisherRunSupervisedTraining =
                    \_ _ _ _ _ _ learningRate -> do
                      liftIO (writeIORef observedRate (Just learningRate))
                      pure (Left "intentional callback stop after learning-rate capture")
                }
        outcome <-
          ( try
              ( runReaderT
                  ( ProductPublisher.runTrainAndPublishProductRows
                      runtime
                      Substrate.LinuxCPU
                      [row]
                  )
                  env
              )
              :: IO (Either SomeException ())
          )
        case outcome of
          Left exception ->
            case fromException exception of
              Just (ExitFailure _) -> pure ()
              Just ExitSuccess -> assertFailure "learning-rate capture unexpectedly exited successfully"
              Nothing -> assertFailure ("unexpected learning-rate capture exception: " <> show exception)
          Right () -> assertFailure "learning-rate capture unexpectedly returned successfully"
        capturedRate <- readIORef observedRate
        capturedRate @?= Just 1.1e-3
    , testCase "a structurally selected V2 error never falls back to V1" $ do
        fixture <- expectRight makeFixture
        let unsupported =
              serialise
                (fixtureOuter fixture)
                  { Checkpoint.rawCheckpointV2Version = 99
                  }
        assertLeftDirectV2
          "unsupported V2 checkpoint version"
          (Checkpoint.decodeAddressedManifestCbor unsupported)
    ]

main :: IO ()
main = defaultMain supervisedCheckpointV2Tests

checkpointStoreAdmissionTests :: TestTree
checkpointStoreAdmissionTests =
  testGroup
    "persisted Store admission"
    [ testCase "local stable exact pointer, manifest, and blob admit completed checkpoint" $
        withSystemTempDirectory "jitml-v2-local-admission" $ \root -> do
          fixture <- expectRight makeFixture
          graph <- expectRight (fixtureAdmissionObjectGraph fixture)
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                (admissionManifestKey graph)
                (LazyByteString.fromStrict (admissionManifestBytes graph))
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                (admissionBlobKey graph)
                (LazyByteString.fromStrict (admissionBlobBytes graph))
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                (admissionPointerKey graph)
                (LazyByteString.fromStrict (admissionPointerBody graph))
          storedPointer <- CheckpointStore.readObject root (admissionPointerKey graph)
          storedManifest <- CheckpointStore.readObject root (admissionManifestKey graph)
          storedBlob <- CheckpointStore.readObject root (admissionBlobKey graph)
          storedPointer
            @?= Right (LazyByteString.fromStrict (admissionPointerBody graph))
          storedManifest
            @?= Right (LazyByteString.fromStrict (admissionManifestBytes graph))
          storedBlob
            @?= Right (LazyByteString.fromStrict (admissionBlobBytes graph))
          admittedCheckpoint <-
            expectRight
              =<< CheckpointStore.admitLocalLatestCheckpoint
                root
                (admissionExperiment graph)
          admitted <-
            expectRight
              (CheckpointStore.requireAdmittedCompletedCheckpoint admittedCheckpoint)
          let checkpoint = CheckpointStore.admittedCompletedCheckpoint admitted
          CheckpointStore.admittedCheckpointManifestSha checkpoint
            @?= admissionManifestSha graph
          CheckpointStore.admittedCompletedTraining admitted
            @?= admissionCompletedTraining graph
          fmap
            CheckpointStore.loadedWeightJmw1Bytes
            (CheckpointStore.admittedCheckpointWeights checkpoint)
            @?= [admissionBlobBytes graph]
    , testCase "stable exact P1 -> manifest -> P2 -> blob admits completed checkpoint" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        (outcome, readLog) <-
          runScriptedMinIO
            (stableAdmissionReads graph (admissionBlobBytes graph))
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        admitted <- expectRight outcome
        addressed <-
          expectRight (Checkpoint.decodeAddressedManifestCbor (fixtureBytes fixture))
        let checkpoint = CheckpointStore.admittedCompletedCheckpoint admitted
        CheckpointStore.admittedCheckpointManifestSha checkpoint
          @?= admissionManifestSha graph
        CheckpointStore.admittedCheckpointManifestBodySha checkpoint
          @?= Checkpoint.addressedManifestBodySha addressed
        CheckpointStore.admittedCompletedTraining admitted
          @?= admissionCompletedTraining graph
        fmap
          CheckpointStore.loadedWeightJmw1Bytes
          (CheckpointStore.admittedCheckpointWeights checkpoint)
          @?= [admissionBlobBytes graph]
        readLog
          @?= [ admissionPointerRef graph
              , admissionManifestRef graph
              , admissionPointerRef graph
              , admissionBlobRef graph
              ]
    , testCase "exact P1/P2 body change is retryable and performs no blob read" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let p1 = admissionPointerBody graph
            p2Sha = alternateManifestSha (admissionManifestSha graph)
            p2 = Text.Encoding.encodeUtf8 p2Sha
            readsScript =
              [ (admissionPointerRef graph, [p1, p2])
              , (admissionManifestRef graph, [admissionManifestBytes graph])
              , (admissionBlobRef graph, [admissionBlobBytes graph])
              ]
        (outcome, readLog) <-
          runScriptedMinIO
            readsScript
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        outcome
          @?= Left
            ( CheckpointStore.AdmissionPointerChanged
                (exactSha p1)
                (exactSha p2)
            )
        readLog
          @?= [ admissionPointerRef graph
              , admissionManifestRef graph
              , admissionPointerRef graph
              ]
    , testCase "known-address admission performs no pointer reads" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let readsScript =
              [ (admissionManifestRef graph, [admissionManifestBytes graph])
              , (admissionBlobRef graph, [admissionBlobBytes graph])
              ]
        (outcome, readLog) <-
          runScriptedMinIO
            readsScript
            ( CheckpointStore.admitCheckpointAt
                (admissionExperiment graph)
                (admissionManifestSha graph)
            )
        admitted <- expectRight outcome
        _ <- expectRight (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
        readLog @?= [admissionManifestRef graph, admissionBlobRef graph]
    , testCase "non-canonical known address is rejected before any object read" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let malformedAddress = Text.replicate 64 "A"
        (outcome, readLog) <-
          runScriptedMinIO
            []
            ( CheckpointStore.admitCheckpointAt
                (admissionExperiment graph)
                malformedAddress
            )
        outcome
          @?= Left
            ( CheckpointStore.AdmissionManifestAddressMalformed
                "address contains whitespace, uppercase, or non-hexadecimal bytes"
            )
        readLog @?= []
    , testCase "two concurrent local completed CAS writers have exactly one winner" $
        withSystemTempDirectory "jitml-v2-local-cas-race" $ \root -> do
          firstFixture <- expectRight makeFixture
          secondFixture <-
            expectRight
              ( makeFixtureWithFinalBytes $ \parameterCount ->
                  WeightCodec.encodeJmw1
                    (0.5 : replicate (parameterCount - 1) 0.0)
              )
          firstGraph <- expectRight (fixtureAdmissionObjectGraph firstFixture)
          secondGraph <- expectRight (fixtureAdmissionObjectGraph secondFixture)
          admissionExperiment firstGraph @?= admissionExperiment secondGraph
          assertBool
            "CAS race fixtures must address distinct completed manifests"
            (admissionManifestSha firstGraph /= admissionManifestSha secondGraph)
          let writeFixture fixture graph =
                CheckpointStore.writeCompletedCheckpointSnapshot
                  root
                  (admissionCompletedTraining graph)
                  (fixtureManifest fixture)
                  [
                    ( admissionBlobKey graph
                    , LazyByteString.fromStrict (admissionBlobBytes graph)
                    )
                  ]
                  Nothing
              pointerKey = admissionPointerKey firstGraph
          start <- newEmptyMVar
          firstResultVar <- newEmptyMVar
          secondResultVar <- newEmptyMVar
          _ <-
            forkFinally
              (readMVar start >> writeFixture firstFixture firstGraph)
              (putMVar firstResultVar)
          _ <-
            forkFinally
              (readMVar start >> writeFixture secondFixture secondGraph)
              (putMVar secondResultVar)
          putMVar start ()
          firstOutcome <- takeMVar firstResultVar
          secondOutcome <- takeMVar secondResultVar
          firstResult <-
            case firstOutcome of
              Left err ->
                assertFailure ("first CAS writer raised an exception: " <> show err)
                  >> error "unreachable"
              Right result -> pure result
          secondResult <-
            case secondOutcome of
              Left err ->
                assertFailure ("second CAS writer raised an exception: " <> show err)
                  >> error "unreachable"
              Right result -> pure result
          winningStored <-
            case (firstResult, secondResult) of
              (Right winner, Left loser) -> do
                loser
                  @?= CheckpointStore.CheckpointWritePointerConflict pointerKey
                pure (CheckpointStore.completedStoredCheckpoint winner)
              (Left loser, Right winner) -> do
                loser
                  @?= CheckpointStore.CheckpointWritePointerConflict pointerKey
                pure (CheckpointStore.completedStoredCheckpoint winner)
              other ->
                assertFailure
                  ("expected one completed CAS winner and one typed conflict, got " <> show other)
                  >> error "unreachable"
          pointer <- CheckpointStore.readCheckpointPointer root pointerKey
          pointer
            @?= Right (Just (CheckpointStore.storedManifestSha winningStored))
    , testCase "addressed malformed JMW1 fails blob admission before completion" $ do
        fixture <- expectRight (makeFixtureWithFinalBytes (const "not-jmw1"))
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        (outcome, readLog) <-
          runScriptedMinIO
            (stableAdmissionReads graph (admissionBlobBytes graph))
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        assertAdmissionBlobFailureContaining "unsupported .jmw1 magic" outcome
        readLog
          @?= [ admissionPointerRef graph
              , admissionManifestRef graph
              , admissionPointerRef graph
              , admissionBlobRef graph
              ]
    , testCase "substituted valid JMW1 bytes fail blob identity before completion" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let substituted =
              LazyByteString.toStrict
                ( WeightCodec.encodeJmw1
                    (0.5 : replicate (fixtureParameterCount fixture - 1) 0.0)
                )
        (outcome, readLog) <-
          runScriptedMinIO
            (stableAdmissionReads graph substituted)
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        assertAdmissionBlobFailureContaining "weight blob identity mismatch" outcome
        readLog
          @?= [ admissionPointerRef graph
              , admissionManifestRef graph
              , admissionPointerRef graph
              , admissionBlobRef graph
              ]
    ]

data AdmissionObjectGraph = AdmissionObjectGraph
  { admissionExperiment :: Text
  , admissionManifestSha :: Text
  , admissionPointerKey :: Text
  , admissionManifestKey :: Text
  , admissionBlobKey :: Text
  , admissionPointerBody :: StrictByteString.ByteString
  , admissionManifestBytes :: StrictByteString.ByteString
  , admissionBlobBytes :: StrictByteString.ByteString
  , admissionPointerRef :: ObjectRef
  , admissionManifestRef :: ObjectRef
  , admissionBlobRef :: ObjectRef
  , admissionCompletedTraining :: TrainingBudget.CompletedTraining
  }

fixtureAdmissionObjectGraph :: Fixture -> Either Text AdmissionObjectGraph
fixtureAdmissionObjectGraph fixture =
  case ( Checkpoint.manifestTensors manifest
       , Checkpoint.manifestCompletedTraining manifest
       ) of
    ([tensor], Just completed) ->
      Right
        AdmissionObjectGraph
          { admissionExperiment = experiment
          , admissionManifestSha = manifestSha
          , admissionPointerKey = Checkpoint.latestPointerKey experiment
          , admissionManifestKey = Checkpoint.manifestKey experiment manifestSha
          , admissionBlobKey = Checkpoint.tensorBlobKey tensor
          , admissionPointerBody = Text.Encoding.encodeUtf8 manifestSha
          , admissionManifestBytes = LazyByteString.toStrict (fixtureBytes fixture)
          , admissionBlobBytes = LazyByteString.toStrict (fixtureFinalBytes fixture)
          , admissionPointerRef =
              CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experiment)
          , admissionManifestRef =
              CheckpointStore.checkpointObjectRef
                (Checkpoint.manifestKey experiment manifestSha)
          , admissionBlobRef =
              CheckpointStore.checkpointObjectRef (Checkpoint.tensorBlobKey tensor)
          , admissionCompletedTraining = completed
          }
    (tensors, completion) ->
      Left
        ( "Store admission fixture requires one tensor and completed training; got "
            <> Text.pack (show (length tensors, void completion))
        )
 where
  manifest = fixtureManifest fixture
  experiment = Checkpoint.manifestExperiment manifest
  manifestSha = Checkpoint.manifestContentSha manifest

stableAdmissionReads
  :: AdmissionObjectGraph
  -> StrictByteString.ByteString
  -> [(ObjectRef, [StrictByteString.ByteString])]
stableAdmissionReads graph blobBytes =
  [
    ( admissionPointerRef graph
    , [admissionPointerBody graph, admissionPointerBody graph]
    )
  , (admissionManifestRef graph, [admissionManifestBytes graph])
  , (admissionBlobRef graph, [blobBytes])
  ]

alternateManifestSha :: Text -> Text
alternateManifestSha manifestSha
  | manifestSha == Text.replicate 64 "f" = Text.replicate 64 "e"
  | otherwise = Text.replicate 64 "f"

assertAdmissionBlobFailureContaining
  :: (Show value)
  => Text
  -> Either CheckpointStore.CheckpointAdmissionError value
  -> Assertion
assertAdmissionBlobFailureContaining expected outcome =
  case outcome of
    Left (CheckpointStore.AdmissionBlobInvalid detail) ->
      assertBool
        ( "expected blob admission error containing "
            <> show expected
            <> ", got "
            <> show detail
        )
        (expected `Text.isInfixOf` detail)
    Left other ->
      assertFailure
        ( "expected AdmissionBlobInvalid containing "
            <> show expected
            <> ", got "
            <> show other
        )
    Right value ->
      assertFailure
        ( "expected AdmissionBlobInvalid containing "
            <> show expected
            <> ", got Right "
            <> show value
        )

data ScriptedMinIOState = ScriptedMinIOState
  { scriptedReadQueues :: [(ObjectRef, [StrictByteString.ByteString])]
  , scriptedReadLogReversed :: [ObjectRef]
  }

newtype ScriptedMinIO value = ScriptedMinIO
  { unScriptedMinIO :: ReaderT (IORef ScriptedMinIOState) IO value
  }
  deriving newtype (Functor, Applicative, Monad)

runScriptedMinIO
  :: [(ObjectRef, [StrictByteString.ByteString])]
  -> ScriptedMinIO value
  -> IO (value, [ObjectRef])
runScriptedMinIO queues action = do
  stateRef <- newIORef (ScriptedMinIOState queues [])
  value <- runReaderT (unScriptedMinIO action) stateRef
  finalState <- readIORef stateRef
  pure (value, reverse (scriptedReadLogReversed finalState))

instance HasMinIO ScriptedMinIO where
  minioPutIfAbsent _ _ = scriptedUnexpected "minioPutIfAbsent"
  minioReadObject _ = scriptedUnexpected "minioReadObject"
  minioReadBytes objectRef =
    ScriptedMinIO $ do
      stateRef <- ask
      liftIO
        ( atomicModifyIORef' stateRef $ \state ->
            let (response, remainingQueues) =
                  dequeueScriptedRead objectRef (scriptedReadQueues state)
                nextState =
                  state
                    { scriptedReadQueues = remainingQueues
                    , scriptedReadLogReversed =
                        objectRef : scriptedReadLogReversed state
                    }
             in (nextState, response)
        )
  putBlobIfAbsent _ _ = scriptedUnexpected "putBlobIfAbsent"
  putBlobBytesIfAbsent _ _ = scriptedUnexpected "putBlobBytesIfAbsent"
  casPointer _ _ _ = scriptedUnexpected "casPointer"
  listObjects _ _ = scriptedUnexpected "listObjects"
  deleteObject _ = scriptedUnexpected "deleteObject"

scriptedUnexpected :: Text -> ScriptedMinIO (Either ServiceError value)
scriptedUnexpected operation =
  pure (Left (SETransient ("unexpected scripted HasMinIO operation: " <> operation)))

dequeueScriptedRead
  :: ObjectRef
  -> [(ObjectRef, [StrictByteString.ByteString])]
  -> (Either ServiceError StrictByteString.ByteString, [(ObjectRef, [StrictByteString.ByteString])])
dequeueScriptedRead requested queues =
  case queues of
    [] ->
      ( Left
          ( SETransient
              ( "scripted HasMinIO has no read for "
                  <> Text.pack (show requested)
              )
          )
      , []
      )
    (objectRef, responses) : rest
      | objectRef == requested ->
          case responses of
            [] ->
              ( Left
                  ( SETransient
                      ( "scripted HasMinIO exhausted reads for "
                          <> Text.pack (show requested)
                      )
                  )
              , queues
              )
            response : remaining ->
              (Right response, (objectRef, remaining) : rest)
      | otherwise ->
          let (response, remainingRest) = dequeueScriptedRead requested rest
           in (response, (objectRef, responses) : remainingRest)

data Fixture = Fixture
  { fixtureManifest :: Checkpoint.CheckpointManifest
  , fixturePayload :: Runtime.SupervisedRuntimePayload
  , fixtureBytes :: LazyByteString.ByteString
  , fixtureFinalBytes :: LazyByteString.ByteString
  , fixtureOuter :: Checkpoint.RawCheckpointEnvelopeV2
  , fixtureBody :: Checkpoint.RawCheckpointBodyV2
  , fixtureMetricName :: Text
  , fixtureParameterCount :: Int
  }

makeTrainingCompletionFixture
  :: Either
       Text
       ( WorkloadPlan.SupervisedPlan
       , SL.CanonicalProblem
       , TrainingExecution.TrainingMetrics
       , Text
       , [(Text, Double)]
       )
makeTrainingCompletionFixture = do
  row <-
    maybe
      (Left "missing authoritative mnist-shallow-mlp ProductRow")
      Right
      (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  problem <-
    maybe
      (Left "missing canonical mnist-shallow-mlp problem")
      Right
      (find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems)
  projection <- authoritativeSupervisedProjection Substrate.LinuxCPU row
  plan <-
    case ProductMatrix.productProjectionResolvedPlan projection of
      ProductMatrix.ResolvedSupervisedProductPlan value -> Right value
  runtime <- Runtime.refineSupervisedRuntime rawRuntime
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  let parameterCount = Runtime.supervisedRuntimeParameterCount runtime
      initialWeights = replicate parameterCount 0.0
      finalWeights = 0.25 : replicate (parameterCount - 1) 0.0
      initialBytes = WeightCodec.encodeJmw1 initialWeights
      finalBytes = WeightCodec.encodeJmw1 finalWeights
      experiment = ProductMatrix.productProjectionExperimentHash projection
      metricName =
        ProductConvergence.convergenceMetricName
          (ProductMatrix.productProjectionConvergenceBar projection)
      epochs = Plan.quantityValue (WorkloadPlan.supervisedPlanEpochs plan)
      trainingExamples =
        Plan.quantityValue (WorkloadPlan.supervisedPlanTrainingExamples plan)
      optimizerUpdates =
        Plan.quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
      metrics =
        TrainingExecution.TrainingMetrics
          { TrainingExecution.tmTrainLoss = 0.1
          , TrainingExecution.tmValidationLoss = 0.2
          , TrainingExecution.tmExamplesProcessed =
              fromIntegral (epochs * trainingExamples)
          , TrainingExecution.tmHeldOutMetric = Just (metricName, 1.0)
          , TrainingExecution.tmCompletedUnits = epochs
          , TrainingExecution.tmOptimizerUpdatesExecuted = optimizerUpdates
          , TrainingExecution.tmInitialCheckpointWeights = Just initialWeights
          , TrainingExecution.tmCheckpointWeights = Just finalWeights
          , TrainingExecution.tmDatasetShaAtRead = Just datasetSha
          , TrainingExecution.tmSupervisedRuntimeProgram = rawRuntime
          , TrainingExecution.tmInitialJmw1Bytes = initialBytes
          , TrainingExecution.tmFinalJmw1Bytes = finalBytes
          , TrainingExecution.tmVerifiedDatasetShaAtRead = datasetSha
          , TrainingExecution.tmParityProbeInput = replicate 784 0.0
          , TrainingExecution.tmParityProbeOutput = replicate 10 0.0
          }
      metricRows = exactTrainingMetricRows metrics
  Right (plan, problem, metrics, experiment, metricRows)

exactTrainingMetricRows
  :: TrainingExecution.TrainingMetrics
  -> [(Text, Double)]
exactTrainingMetricRows metrics =
  [ ("train_loss", TrainingExecution.tmTrainLoss metrics)
  , ("validation_loss", TrainingExecution.tmValidationLoss metrics)
  ,
    ( "examples_processed"
    , fromIntegral (TrainingExecution.tmExamplesProcessed metrics)
    )
  ]
    <> maybe [] pure (TrainingExecution.tmHeldOutMetric metrics)

makeGenericFixture :: Either Text (Fixture, WorkloadPlan.SupervisedPlan)
makeGenericFixture = do
  (productPlan, problem, metrics, _, metricRows) <-
    makeTrainingCompletionFixture
  plan <-
    genericSupervisedPlanFrom
      "generic-mnist-shallow-mlp-v2"
      productPlan
  let experiment =
        Plan.runPlanExperimentId
          (WorkloadPlan.supervisedPlanRunPlan plan)
  completion <-
    CheckpointWriter.attemptGenericSupervisedRuntimeForTraining
      plan
      problem
      metrics
      experiment
      metricRows
  (completed, artifact) <-
    case completion of
      CheckpointWriter.SupervisedRuntimeCompletionMiss observations ->
        Left
          ( "generic fixture unexpectedly missed its convergence bar: "
              <> Text.pack (show (NonEmpty.toList observations))
          )
      CheckpointWriter.SupervisedRuntimeCompleted witness runtimeArtifact ->
        Right (witness, runtimeArtifact)
  row <-
    maybe
      (Left "refined generic fixture lost its authoritative runtime row")
      Right
      ( find
          ((== Runtime.payloadRowId (Runtime.trainingArtifactPayload artifact)) . ProductMatrix.rowId)
          ProductMatrix.allProductRows
      )
  let payload = Runtime.trainingArtifactPayload artifact
      runtime = Runtime.payloadRuntime payload
      parameterCount = Runtime.supervisedRuntimeParameterCount runtime
      metricName =
        ProductConvergence.convergenceMetricName
          (ProductMatrix.convergenceBar row)
  metadata <- Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload
  let tensor =
        Checkpoint.TensorBlob
          "supervised.weights"
          [parameterCount]
          (Checkpoint.blobKey experiment (Runtime.payloadFinalJmw1Sha256 payload))
      base =
        (Checkpoint.emptyManifest "generic-mnist-complete" experiment [tensor])
          { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
          , Checkpoint.manifestArchitecture =
              Checkpoint.supervisedRuntimeArchitectureMetadata metadata
          , Checkpoint.manifestPreprocessing =
              Checkpoint.supervisedRuntimePreprocessingMetadata metadata
          , Checkpoint.manifestOutputDecoders =
              Checkpoint.supervisedRuntimeOutputDecoderMetadata metadata
          , Checkpoint.manifestWeightLayout =
              Checkpoint.FlatWeightLayout
                (virtualSliceSpecs (Runtime.supervisedRuntimeVirtualSlices runtime))
          , Checkpoint.manifestStep =
              TrainingBudget.completedTrainingObservedUnits completed
          , Checkpoint.manifestMetrics = sortOn fst metricRows
          , Checkpoint.manifestSupervisedRuntime = Just payload
          }
      manifest = Checkpoint.attachCompletedTraining completed base
      bytes = Checkpoint.encodeManifestCbor manifest
  outer <- decodeSerialised bytes
  body <-
    decodeSerialised
      ( LazyByteString.fromStrict
          (Checkpoint.rawCheckpointV2BodyBytes outer)
      )
  Right
    ( Fixture
        { fixtureManifest = manifest
        , fixturePayload = payload
        , fixtureBytes = bytes
        , fixtureFinalBytes = Runtime.trainingArtifactFinalJmw1Bytes artifact
        , fixtureOuter = outer
        , fixtureBody = body
        , fixtureMetricName = metricName
        , fixtureParameterCount = parameterCount
        }
    , plan
    )

genericSupervisedPlanFrom
  :: Text
  -> WorkloadPlan.SupervisedPlan
  -> Either Text WorkloadPlan.SupervisedPlan
genericSupervisedPlanFrom experiment sourcePlan =
  case Plan.validationToEither
    ( WorkloadPlan.resolveSupervisedPlan
        (WorkloadPlan.RawSupervisedPlan rawRun)
    ) of
    Left errors ->
      Left
        ( "generic supervised fixture plan refinement failed: "
            <> Text.pack (show errors)
        )
    Right plan -> Right plan
 where
  sourceRun = WorkloadPlan.supervisedPlanRunPlan sourcePlan
  rawRun :: Plan.RawRunRequest 'Plan.SupervisedTraining
  rawRun =
    Plan.RawRunRequest
      { Plan.rawRunVersion = Plan.runPlanVersion sourceRun
      , Plan.rawRunKind = Plan.SupervisedTrainingWitness
      , Plan.rawRunExperimentId = experiment
      , Plan.rawRunSubjectId = Plan.runPlanSubjectId sourceRun
      , Plan.rawRunArtifactId = Plan.runPlanArtifactId sourceRun
      , Plan.rawRunTopicId = Plan.runPlanTopicId sourceRun
      , Plan.rawRunSubstrate = Plan.runPlanSubstrate sourceRun
      , Plan.rawRunPlacement = Plan.runPlanPlacement sourceRun
      , Plan.rawRunSeeds =
          NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds sourceRun))
      , Plan.rawRunBudget =
          Plan.RawSupervisedBudget
            { Plan.rawSupervisedEpochs =
                toInteger
                  (Plan.quantityValue (WorkloadPlan.supervisedPlanEpochs sourcePlan))
            , Plan.rawSupervisedTrainingExamples =
                toInteger
                  ( Plan.quantityValue
                      (WorkloadPlan.supervisedPlanTrainingExamples sourcePlan)
                  )
            , Plan.rawSupervisedEvaluationExamples =
                toInteger
                  ( Plan.quantityValue
                      (WorkloadPlan.supervisedPlanEvaluationExamples sourcePlan)
                  )
            , Plan.rawSupervisedBatchExamples =
                toInteger
                  ( Plan.quantityValue
                      (WorkloadPlan.supervisedPlanBatchExamples sourcePlan)
                  )
            , Plan.rawSupervisedOptimizerUpdates =
                toInteger
                  ( Plan.quantityValue
                      (WorkloadPlan.supervisedPlanOptimizerUpdates sourcePlan)
                  )
            }
      }

supervisedPublishRunFixture
  :: TrainingExecution.TrainingMetrics
  -> ProductPublisher.SupervisedPublishRun
supervisedPublishRunFixture metrics =
  ProductPublisher.SupervisedPublishRun
    { ProductPublisher.supervisedPublishTrainLoss =
        TrainingExecution.tmTrainLoss metrics
    , ProductPublisher.supervisedPublishValidationLoss =
        TrainingExecution.tmValidationLoss metrics
    , ProductPublisher.supervisedPublishExamplesProcessed =
        TrainingExecution.tmExamplesProcessed metrics
    , ProductPublisher.supervisedPublishHeldOutMetric =
        TrainingExecution.tmHeldOutMetric metrics
    , ProductPublisher.supervisedPublishCompletedUnits =
        TrainingExecution.tmCompletedUnits metrics
    , ProductPublisher.supervisedPublishOptimizerUpdatesExecuted =
        TrainingExecution.tmOptimizerUpdatesExecuted metrics
    , ProductPublisher.supervisedPublishRuntimeProgram =
        TrainingExecution.tmSupervisedRuntimeProgram metrics
    , ProductPublisher.supervisedPublishInitialJmw1Bytes =
        TrainingExecution.tmInitialJmw1Bytes metrics
    , ProductPublisher.supervisedPublishFinalJmw1Bytes =
        TrainingExecution.tmFinalJmw1Bytes metrics
    , ProductPublisher.supervisedPublishVerifiedDatasetShaAtRead =
        TrainingExecution.tmVerifiedDatasetShaAtRead metrics
    , ProductPublisher.supervisedPublishInitialWeights =
        TrainingExecution.tmInitialCheckpointWeights metrics
    , ProductPublisher.supervisedPublishCheckpointWeights =
        TrainingExecution.tmCheckpointWeights metrics
    , ProductPublisher.supervisedPublishDatasetShaAtRead =
        TrainingExecution.tmDatasetShaAtRead metrics
    }

substitutedSupervisedPublisherRuntime
  :: ProductPublisher.SupervisedPublishRun
  -> ProductPublisher.ProductPublisherRuntime
substitutedSupervisedPublisherRuntime run =
  ProductPublisher.ProductPublisherRuntime
    { ProductPublisher.publisherRunSupervisedTraining =
        \_ _ _ _ _ _ _ -> pure (Right run)
    , ProductPublisher.publisherRunRlTraining =
        error "substituted supervised row invoked the RL training callback"
    , ProductPublisher.publisherCompleteProductRow =
        error "substituted supervised row invoked the generic completion callback"
    , ProductPublisher.publisherCompleteSupervisedProductRowWithWeightHashes =
        error "substituted supervised row invoked the supervised completion callback"
    , ProductPublisher.publisherRlCompletionMetrics =
        error "substituted supervised row invoked the RL metrics callback"
    , ProductPublisher.publisherRlCompletedTraining =
        error "substituted supervised row invoked the RL completion callback"
    , ProductPublisher.publisherRlCompletionFailure =
        error "substituted supervised row invoked the RL failure callback"
    , ProductPublisher.publisherAlphaZeroCompletedTraining =
        error "substituted supervised row invoked the AlphaZero completion callback"
    , ProductPublisher.publisherWriteCompletedWeightCheckpoint =
        error "substituted supervised row invoked the generic checkpoint writer"
    , ProductPublisher.publisherWriteCompletedSupervisedCheckpoint =
        error "substituted supervised row invoked the supervised checkpoint writer"
    , ProductPublisher.publisherAdmitCompletedCheckpoint =
        error "substituted supervised row invoked checkpoint admission"
    , ProductPublisher.publisherWriteTextArtifact =
        error "substituted supervised row invoked the artifact writer"
    , ProductPublisher.publisherLoadTuningDataset =
        error "substituted supervised row invoked the tuning dataset callback"
    }

makeFixture :: Either Text Fixture
makeFixture =
  makeFixtureWithFinalBytes
    ( \parameterCount ->
        WeightCodec.encodeJmw1
          (0.25 : replicate (parameterCount - 1) 0.0)
    )

makeFixtureWithFinalBytes
  :: (Int -> LazyByteString.ByteString)
  -> Either Text Fixture
makeFixtureWithFinalBytes finalBytesFor = do
  row <-
    maybe
      (Left "missing authoritative mnist-shallow-mlp ProductRow")
      Right
      (find ((== "mnist-shallow-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  problem <-
    maybe
      (Left "missing authoritative mnist-shallow-mlp canonical problem")
      Right
      (find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems)
  projection <- authoritativeSupervisedProjection Substrate.LinuxCPU row
  optimizerUpdates <- supervisedProjectionOptimizerUpdates projection
  runtime <- Runtime.refineSupervisedRuntime rawRuntime
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  let planId = ProductMatrix.productProjectionPlanId projection
      parameterCount = Runtime.supervisedRuntimeParameterCount runtime
      initialBytes = WeightCodec.encodeJmw1 (replicate parameterCount 0.0)
      finalBytes = finalBytesFor parameterCount
      initialSha = WeightCodec.jmw1ContentSha initialBytes
      finalSha = WeightCodec.jmw1ContentSha finalBytes
      experiment = ProductMatrix.productRowExperimentHash row
      metricName =
        ProductConvergence.convergenceMetricName (ProductMatrix.convergenceBar row)
      metrics = [(metricName, 1.0)]
      budget = ProductMatrix.trainingBudget row
      observedUnits = TrainingBudget.trainingBudgetTargetUnits budget
  payload <-
    Runtime.refineSupervisedRuntimePayload
      Runtime.RawSupervisedRuntimePayload
        { Runtime.rawRuntimePayloadRowId = ProductMatrix.rowId row
        , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
        , Runtime.rawRuntimePayloadPlanId = Plan.planIdText planId
        , Runtime.rawRuntimePayloadDatasetSha256 = datasetSha
        , Runtime.rawRuntimePayloadInitialJmw1Sha256 = initialSha
        , Runtime.rawRuntimePayloadFinalJmw1Sha256 = finalSha
        , Runtime.rawRuntimePayloadRuntime = rawRuntime
        }
  metadata <- Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload
  completed <-
    ProductCompletion.completedTrainingForProductRowWithWeightHashes
      planId
      budget
      row
      datasetSha
      experiment
      observedUnits
      optimizerUpdates
      metrics
      initialSha
      finalSha
  let slices = Runtime.supervisedRuntimeVirtualSlices runtime
      tensor =
        Checkpoint.TensorBlob
          "supervised.weights"
          [parameterCount]
          (Checkpoint.blobKey experiment finalSha)
      base =
        (Checkpoint.emptyManifest "mnist-shallow-mlp-complete" experiment [tensor])
          { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
          , Checkpoint.manifestArchitecture =
              Checkpoint.supervisedRuntimeArchitectureMetadata metadata
          , Checkpoint.manifestPreprocessing =
              Checkpoint.supervisedRuntimePreprocessingMetadata metadata
          , Checkpoint.manifestOutputDecoders =
              Checkpoint.supervisedRuntimeOutputDecoderMetadata metadata
          , Checkpoint.manifestWeightLayout =
              Checkpoint.FlatWeightLayout (virtualSliceSpecs slices)
          , Checkpoint.manifestStep = observedUnits
          , Checkpoint.manifestMetrics = metrics
          , Checkpoint.manifestSupervisedRuntime = Just payload
          }
      manifest = Checkpoint.attachCompletedTraining completed base
      bytes = Checkpoint.encodeManifestCbor manifest
  outer <- decodeSerialised bytes
  body <-
    decodeSerialised
      ( LazyByteString.fromStrict
          (Checkpoint.rawCheckpointV2BodyBytes outer)
      )
  Right
    Fixture
      { fixtureManifest = manifest
      , fixturePayload = payload
      , fixtureBytes = bytes
      , fixtureFinalBytes = finalBytes
      , fixtureOuter = outer
      , fixtureBody = body
      , fixtureMetricName = metricName
      , fixtureParameterCount = parameterCount
      }

rawRuntime :: Runtime.RawSupervisedRuntime
rawRuntime =
  Runtime.RawSupervisedRuntime
    { Runtime.rawSupervisedRuntimeFamily = Runtime.RawDenseRuntimeFamily
    , Runtime.rawSupervisedRuntimeTask = Runtime.RawClassificationRuntimeTask 10
    , Runtime.rawSupervisedRuntimeInputTransform =
        Runtime.RawUnitImageInput (Runtime.RawRuntimeImageGeometry 28 28 1)
    , Runtime.rawSupervisedRuntimeOutputTransform =
        Runtime.RawSemanticPrefixOutput 10
    , Runtime.rawSupervisedRuntimeLayers =
        [ Runtime.RawDenseLayer
            "dense-classifier"
            (Runtime.RawRuntimeMlpShape 784 128 11)
        ]
    }

makeCifarVitPayload :: Either Text Runtime.SupervisedRuntimePayload
makeCifarVitPayload = do
  problem <-
    maybe
      (Left "missing authoritative cifar10-vit canonical problem")
      Right
      (find ((== "cifar10-vit") . SL.problemName) SL.canonicalProblems)
  row <-
    maybe
      (Left "missing authoritative cifar10-vit ProductRow")
      Right
      (find ((== "cifar10-vit") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  planId <- authoritativeSupervisedPlanId Substrate.LinuxCPU row
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  let config =
        Classifier.defaultClassifierConfig
          { Classifier.clfSeed = SL.problemSeed problem
          , Classifier.clfInputs = 3072
          , Classifier.clfClasses = 10
          }
      means = concat (replicate 1024 [0.5, 0.4, 0.3])
      scales = concat (replicate 1024 [0.2, 0.25, 0.3])
  canonical <- Architecture.canonicalClassificationRuntimeContract config problem
  Runtime.refineSupervisedRuntimePayload
    Runtime.RawSupervisedRuntimePayload
      { Runtime.rawRuntimePayloadRowId = "cifar10-vit"
      , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
      , Runtime.rawRuntimePayloadPlanId = Plan.planIdText planId
      , Runtime.rawRuntimePayloadDatasetSha256 = datasetSha
      , Runtime.rawRuntimePayloadInitialJmw1Sha256 = Text.replicate 64 "c"
      , Runtime.rawRuntimePayloadFinalJmw1Sha256 = Text.replicate 64 "d"
      , Runtime.rawRuntimePayloadRuntime =
          canonical
            { Runtime.rawSupervisedRuntimeInputTransform =
                Runtime.RawStandardizeInput means scales
            }
      }

makeCaliforniaPayload :: Either Text Runtime.SupervisedRuntimePayload
makeCaliforniaPayload = do
  problem <-
    maybe
      (Left "missing authoritative California Housing canonical problem")
      Right
      (find ((== "california-housing-mlp") . SL.problemName) SL.canonicalProblems)
  row <-
    maybe
      (Left "missing authoritative California Housing ProductRow")
      Right
      (find ((== "california-housing-mlp") . ProductMatrix.rowId) ProductMatrix.allProductRows)
  planId <- authoritativeSupervisedPlanId Substrate.LinuxCPU row
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  Runtime.refineSupervisedRuntimePayload
    Runtime.RawSupervisedRuntimePayload
      { Runtime.rawRuntimePayloadRowId = "california-housing-mlp"
      , Runtime.rawRuntimePayloadOrigin = Runtime.RawProductRowProjectionOrigin
      , Runtime.rawRuntimePayloadPlanId = Plan.planIdText planId
      , Runtime.rawRuntimePayloadDatasetSha256 = datasetSha
      , Runtime.rawRuntimePayloadInitialJmw1Sha256 = Text.replicate 64 "c"
      , Runtime.rawRuntimePayloadFinalJmw1Sha256 = Text.replicate 64 "d"
      , Runtime.rawRuntimePayloadRuntime =
          Runtime.RawSupervisedRuntime
            { Runtime.rawSupervisedRuntimeFamily =
                Runtime.RawTabularRegressionRuntimeFamily
            , Runtime.rawSupervisedRuntimeTask =
                Runtime.RawRegressionRuntimeTask 1
            , Runtime.rawSupervisedRuntimeInputTransform =
                Runtime.RawStandardizeInput (replicate 8 0.0) (replicate 8 1.0)
            , Runtime.rawSupervisedRuntimeOutputTransform =
                Runtime.RawDestandardizeOutput [100.0] [5.0]
            , Runtime.rawSupervisedRuntimeLayers =
                [ Runtime.RawDenseLayer
                    "regressor"
                    (Runtime.RawRuntimeMlpShape 8 32 1)
                ]
            }
      }

authoritativeSupervisedPlanId
  :: Substrate.Substrate
  -> ProductMatrix.ProductRow state
  -> Either Text Plan.PlanId
authoritativeSupervisedPlanId substrate row =
  ProductMatrix.productProjectionPlanId
    <$> authoritativeSupervisedProjection substrate row

authoritativeSupervisedProjection
  :: Substrate.Substrate
  -> ProductMatrix.ProductRow state
  -> Either
       Text
       (ProductMatrix.ProductProjection 'Plan.SupervisedTraining)
authoritativeSupervisedProjection substrate row =
  case ProductMatrix.projectProductRow substrate row of
    Plan.Failure errors -> Left (Text.pack (show errors))
    Plan.Success
      ( ProductMatrix.SomeProductProjection
          Plan.SupervisedTrainingWitness
          projection
        ) -> Right projection
    Plan.Success _ -> Left "authoritative ProductRow projection is not supervised"

supervisedProjectionOptimizerUpdates
  :: ProductMatrix.ProductProjection 'Plan.SupervisedTraining
  -> Either Text Word64
supervisedProjectionOptimizerUpdates projection =
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedSupervisedProductPlan plan ->
      Right
        ( Plan.quantityValue
            (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
        )

virtualSliceSpecs :: [Runtime.RuntimeVirtualSlice] -> [Checkpoint.TensorSpec]
virtualSliceSpecs =
  fmap
    ( \slice ->
        Checkpoint.TensorSpec
          { Checkpoint.tensorSpecName = Runtime.runtimeVirtualSliceQualifiedName slice
          , Checkpoint.tensorSpecShape = Runtime.runtimeVirtualSliceShape slice
          , Checkpoint.tensorSpecDtype = "F64"
          }
    )

bindingSubstitutionTest
  :: ( String
     , Runtime.RawSupervisedRuntimePayload
       -> Runtime.RawSupervisedRuntimePayload
     , Text
     )
  -> TestTree
bindingSubstitutionTest (label, substitute, expectedError) =
  testCase (label <> " substitution is rejected") $ do
    fixture <- expectRight makeFixture
    let body = fixtureBody fixture
        substituted =
          body
            { Checkpoint.rawCheckpointV2SupervisedRuntime =
                substitute (Checkpoint.rawCheckpointV2SupervisedRuntime body)
            }
    assertLeftDirectV2
      expectedError
      (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))

runtimeSubstitutionTest
  :: String
  -> (Runtime.RawSupervisedRuntime -> Runtime.RawSupervisedRuntime)
  -> Text
  -> TestTree
runtimeSubstitutionTest label substitute expectedError =
  testCase (label <> " substitution is rejected") $ do
    fixture <- expectRight makeFixture
    let body = fixtureBody fixture
        payload = Checkpoint.rawCheckpointV2SupervisedRuntime body
        substituted =
          body
            { Checkpoint.rawCheckpointV2SupervisedRuntime =
                payload
                  { Runtime.rawRuntimePayloadRuntime =
                      substitute (Runtime.rawRuntimePayloadRuntime payload)
                  }
            }
    assertLeftDirectV2
      expectedError
      (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))

manifestSubstitutionTest
  :: String
  -> (Checkpoint.RawCheckpointManifest -> Checkpoint.RawCheckpointManifest)
  -> Text
  -> TestTree
manifestSubstitutionTest label substitute expectedError =
  testCase (label <> " substitution is rejected") $ do
    fixture <- expectRight makeFixture
    let body = fixtureBody fixture
        substituted =
          body
            { Checkpoint.rawCheckpointV2Manifest =
                substitute (Checkpoint.rawCheckpointV2Manifest body)
            }
    assertLeftDirectV2
      expectedError
      (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))

tensorBoardSubstitutionTest
  :: String
  -> (TrainingBudget.TensorBoardRunMetadata -> TrainingBudget.TensorBoardRunMetadata)
  -> Text
  -> TestTree
tensorBoardSubstitutionTest label substitute expectedError =
  testCase (label <> " substitution is rejected") $ do
    fixture <- expectRight makeFixture
    let body = fixtureBody fixture
        rawManifest = Checkpoint.rawCheckpointV2Manifest body
    completed <-
      maybe
        (assertFailure "V2 TensorBoard fixture is missing completed training")
        pure
        (Checkpoint.rawManifestCompletedTraining rawManifest)
    let substitutedCompleted =
          completed
            { TrainingBudget.rawCompletedTrainingTensorBoard =
                substitute
                  (TrainingBudget.rawCompletedTrainingTensorBoard completed)
            }
        substituted =
          body
            { Checkpoint.rawCheckpointV2Manifest =
                rawManifest
                  { Checkpoint.rawManifestCompletedTraining =
                      Just substitutedCompleted
                  }
            }
    assertLeftDirectV2
      expectedError
      (Checkpoint.decodeAddressedManifestCbor (wrapBody substituted))

synchronizeV2DatasetSha
  :: Text
  -> Checkpoint.RawCheckpointBodyV2
  -> Either Text Checkpoint.RawCheckpointBodyV2
synchronizeV2DatasetSha datasetSha body = do
  let rawManifest = Checkpoint.rawCheckpointV2Manifest body
  completed <-
    maybe
      (Left "V2 fixture is missing completed training")
      Right
      (Checkpoint.rawManifestCompletedTraining rawManifest)
  let evidence = TrainingBudget.rawCompletedTrainingEvidence completed
  substitutedEvidence <-
    ProductEvidence.mkTrainingEvidence
      (ProductEvidence.evidenceInitialWeightHash evidence)
      (ProductEvidence.evidenceFinalWeightHash evidence)
      (ProductEvidence.evidenceUpdateCount evidence)
      datasetSha
  let substitutedCompleted =
        completed
          { TrainingBudget.rawCompletedTrainingEvidence = substitutedEvidence
          }
      rawPayload = Checkpoint.rawCheckpointV2SupervisedRuntime body
  Right
    body
      { Checkpoint.rawCheckpointV2Manifest =
          rawManifest
            { Checkpoint.rawManifestDatasetShaAtRead = Just datasetSha
            , Checkpoint.rawManifestCompletedTraining = Just substitutedCompleted
            }
      , Checkpoint.rawCheckpointV2SupervisedRuntime =
          rawPayload
            { Runtime.rawRuntimePayloadDatasetSha256 = datasetSha
            }
      }

wrapBody :: Checkpoint.RawCheckpointBodyV2 -> LazyByteString.ByteString
wrapBody body =
  let bodyBytes = LazyByteString.toStrict (serialise body)
   in serialise
        Checkpoint.RawCheckpointEnvelopeV2
          { Checkpoint.rawCheckpointV2Version = Checkpoint.checkpointWireVersionV2
          , Checkpoint.rawCheckpointV2BodySha256 = shaBytes bodyBytes
          , Checkpoint.rawCheckpointV2BodyBytes = bodyBytes
          }

shaBytes :: StrictByteString.ByteString -> StrictByteString.ByteString
shaBytes =
  decodeHex . exactSha

exactSha :: StrictByteString.ByteString -> Text
exactSha =
  WeightCodec.jmw1ContentSha . LazyByteString.fromStrict

decodeHex :: Text -> StrictByteString.ByteString
decodeHex = StrictByteString.pack . go . Text.unpack
 where
  go (high : low : rest) =
    fromIntegral (digitToInt high * 16 + digitToInt low) : go rest
  go [] = []
  go _ = error "canonical SHA-256 hex must have an even number of digits"

decodeSerialised :: (Serialise value) => LazyByteString.ByteString -> Either Text value
decodeSerialised bytes =
  case deserialiseOrFail bytes of
    Left failure -> Left (Text.pack (show failure))
    Right value -> Right value

expectRight :: (Show error) => Either error value -> IO value
expectRight result =
  case result of
    Left err -> assertFailure (show err)
    Right value -> pure value

assertLeftContaining :: (Show value) => Text -> Either Text value -> Assertion
assertLeftContaining expected result =
  case result of
    Left err ->
      assertBool
        ( "expected error containing "
            <> show expected
            <> ", got "
            <> show err
        )
        (expected `Text.isInfixOf` err)
    Right value ->
      assertFailure
        ( "expected failure containing "
            <> show expected
            <> ", got success: "
            <> show value
        )

assertLeftDirectV2 :: (Show value) => Text -> Either Text value -> Assertion
assertLeftDirectV2 expected result =
  case result of
    Left err -> do
      assertBool
        ( "expected V2 error containing "
            <> show expected
            <> ", got "
            <> show err
        )
        (expected `Text.isInfixOf` err)
      assertBool
        ("selected V2 error fell through to an older decoder: " <> show err)
        (not ("V1 decode" `Text.isInfixOf` err))
    Right value ->
      assertFailure
        ( "expected direct V2 failure containing "
            <> show expected
            <> ", got success: "
            <> show value
        )
