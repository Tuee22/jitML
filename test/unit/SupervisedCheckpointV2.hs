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
import Data.Maybe (isJust)
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
import JitML.Numerics.LayerGraphMetadata qualified as LayerGraphMetadata
import JitML.Numerics.Mlp (MlpShape (..), mlpInit, mlpLayerGraph)
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
  ( BucketName (..)
  , HasMinIO (..)
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
          @?= Just (Checkpoint.rawCheckpointBodyBytes (fixtureOuter fixture))
        Checkpoint.addressedManifestBodySha addressed
          @?= Just
            ( exactSha
                (Checkpoint.rawCheckpointBodyBytes (fixtureOuter fixture))
            )
        Checkpoint.rawCheckpointBodyBytes (fixtureOuter fixture)
          @?= LazyByteString.toStrict
            (serialise (Checkpoint.RawSupervisedGraphBody (fixtureBody fixture)))

        completion <-
          expectRight
            ( Checkpoint.validateCheckpointCompletion
                (Checkpoint.addressedManifest addressed)
            )
        Checkpoint.validatedCheckpointCompletionManifest completion
          @?= fixtureManifest fixture
        Just (Checkpoint.validatedCheckpointCompletedTraining completion)
          @?= Checkpoint.manifestCompletedTraining (fixtureManifest fixture)
    , testCase "CompletedTraining V1 remains readable inside an exact supervised-graph checkpoint" $ do
        fixture <- expectRight makeFixture
        let body = fixtureBody fixture
            rawManifest = Checkpoint.rawCheckpointV2Manifest body
        currentCompletion <-
          maybe
            (assertFailure "fixture supervised manifest has no raw completion")
            pure
            (Checkpoint.rawManifestCompletedTraining rawManifest)
        let legacyCompletion =
              currentCompletion
                { TrainingBudget.rawCompletedTrainingVersion = 1
                , TrainingBudget.rawCompletedTrainingProductScenarioInvocation = Nothing
                }
            legacyBytes =
              wrapBody
                body
                  { Checkpoint.rawCheckpointV2Manifest =
                      rawManifest
                        { Checkpoint.rawManifestCompletedTraining =
                            Just legacyCompletion
                        }
                  }
        addressed <-
          expectRight (Checkpoint.decodeAddressedManifestCbor legacyBytes)
        Checkpoint.addressedManifest addressed @?= fixtureManifest fixture
        TrainingBudget.completedTrainingProductScenarioInvocation
          <$> Checkpoint.manifestCompletedTraining
            (Checkpoint.addressedManifest addressed)
            @?= Just Nothing
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
    , testCase "V2 uses one physical tensor and a graph-ordered flat layout" $ do
        fixture <- expectRight makeFixture
        let manifest = fixtureManifest fixture
        Checkpoint.manifestTensors manifest
          @?= [ Checkpoint.TensorBlob
                  "supervised.weights"
                  [fixtureParameterCount fixture]
                  ( Checkpoint.blobKey
                      (Checkpoint.manifestExperiment manifest)
                      (Runtime.payloadFinalJmw1Sha256 (fixturePayload fixture))
                  )
              ]
        Checkpoint.manifestWeightLayout manifest
          @?= Checkpoint.FlatWeightLayout
            (supervisedWeightsLayout (fixtureParameterCount fixture))
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
    , testCase "weight-only payload round-trips through the one envelope (Sprint 235.1)" $ do
        let manifest =
              Checkpoint.emptyManifest
                "weight-only-row"
                "exp-weight-only"
                [ Checkpoint.TensorBlob
                    "weights"
                    [2]
                    "jitml-checkpoints/exp-weight-only/blobs/w"
                ]
            bytes = Checkpoint.encodeManifestCbor manifest
        addressed <- expectRight (Checkpoint.decodeAddressedManifestCbor bytes)
        -- The self-describing envelope round-trips the weight-only payload at the
        -- weight-only variant tag, with no embedded body identity.
        Checkpoint.addressedManifestWireVersion addressed
          @?= Checkpoint.checkpointWireVersion
        Checkpoint.addressedManifest addressed @?= manifest
        Checkpoint.addressedManifestBytes addressed @?= bytes
        Checkpoint.addressedManifestBodyBytes addressed @?= Nothing
        Checkpoint.addressedManifestBodySha addressed @?= Nothing
        Checkpoint.manifestSupervisedRuntime (Checkpoint.addressedManifest addressed)
          @?= Nothing
    , testCase
        "supervised-graph payload round-trips and is never mis-decoded as weight-only (Sprint 235.1)"
        $ do
          fixture <- expectRight makeFixture
          addressed <-
            expectRight
              (Checkpoint.decodeAddressedManifestCbor (fixtureBytes fixture))
          -- The supervised-graph payload round-trips at the supervised variant tag,
          -- carrying its embedded body identity.
          Checkpoint.addressedManifestWireVersion addressed
            @?= Checkpoint.checkpointWireVersionV2
          Checkpoint.addressedManifest addressed @?= fixtureManifest fixture
          assertBool
            "supervised-graph payload lost its embedded body identity"
            (isJust (Checkpoint.addressedManifestBodySha addressed))
          assertBool
            "supervised-graph payload lost its runtime program"
            ( isJust
                ( Checkpoint.manifestSupervisedRuntime
                    (Checkpoint.addressedManifest addressed)
                )
            )
          -- A weight-only envelope decodes at the weight-only variant tag, so the
          -- two payload variants can never be mis-classified as one another.
          let weightOnly =
                Checkpoint.emptyManifest
                  "wo-row"
                  "exp-wo"
                  [ Checkpoint.TensorBlob
                      "weights"
                      [2]
                      "jitml-checkpoints/exp-wo/blobs/w"
                  ]
          weightAddressed <-
            expectRight
              ( Checkpoint.decodeAddressedManifestCbor
                  (Checkpoint.encodeManifestCbor weightOnly)
              )
          Checkpoint.addressedManifestWireVersion weightAddressed
            @?= Checkpoint.checkpointWireVersion
          assertBool
            "weight-only and supervised-graph payloads must carry distinct variant tags"
            ( Checkpoint.addressedManifestWireVersion weightAddressed
                /= Checkpoint.addressedManifestWireVersion addressed
            )
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
                  { Checkpoint.rawCheckpointBodySha256 =
                      StrictByteString.replicate 32 0
                  }
            truncatedBody =
              StrictByteString.init (Checkpoint.rawCheckpointBodyBytes outer)
            badBody =
              serialise
                outer
                  { Checkpoint.rawCheckpointBodySha256 = shaBytes truncatedBody
                  , Checkpoint.rawCheckpointBodyBytes = truncatedBody
                  }
        assertLeftDirectV2
          "body SHA-256 mismatch"
          (Checkpoint.decodeAddressedManifestCbor badDigest)
        assertLeftDirectV2
          "invalid checkpoint body"
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
              "manifest architecture metadata does not equal the exact runtime projection"
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
    , testCase "a structurally selected supervised-graph error never falls back" $ do
        fixture <- expectRight makeFixture
        let unsupported =
              serialise
                (fixtureOuter fixture)
                  { Checkpoint.rawCheckpointVersion = 99
                  }
        assertLeftDirectV2
          "supervised-graph checkpoint payload carries version 99"
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
          written <-
            expectRight
              =<< CheckpointStore.writeCompletedCheckpointSnapshot
                root
                (admissionCompletedTraining graph)
                (fixtureManifest fixture)
                [
                  ( admissionLogicalBlobKey graph
                  , LazyByteString.fromStrict (admissionBlobBytes graph)
                  )
                ]
                Nothing
          let stored = CheckpointStore.completedStoredCheckpoint written
          CheckpointStore.storedManifestSha stored @?= admissionManifestSha graph
          storedPointer <- CheckpointStore.readObject root (admissionPointerKey graph)
          storedManifest <- CheckpointStore.readObject root (admissionManifestKey graph)
          storedBlob <- CheckpointStore.readObject root (admissionBlobKey graph)
          storedCommit <- CheckpointStore.readObject root (admissionCommitKey graph)
          storedPointer
            @?= Right (LazyByteString.fromStrict (admissionPointerBody graph))
          storedManifest
            @?= Right (LazyByteString.fromStrict (admissionManifestBytes graph))
          storedBlob
            @?= Right (LazyByteString.fromStrict (admissionBlobBytes graph))
          storedCommit
            @?= Right (LazyByteString.fromStrict (admissionCommitBytes graph))
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
    , testCase "legacy unscoped V2 is readable for inspection but cannot satisfy admission" $
        withSystemTempDirectory "jitml-v2-legacy-unscoped" $ \root -> do
          fixture <- expectRight makeFixture
          let manifest = fixtureManifest fixture
              experiment = Checkpoint.manifestExperiment manifest
              manifestSha = Checkpoint.manifestContentSha manifest
              manifestKey = Checkpoint.manifestKey experiment manifestSha
          tensor <-
            case Checkpoint.manifestTensors manifest of
              [value] -> pure value
              tensors ->
                assertFailure
                  ("expected one legacy fixture tensor, got " <> show (length tensors))
                  >> error "unreachable"
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                (Checkpoint.tensorBlobKey tensor)
                (fixtureFinalBytes fixture)
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                manifestKey
                (fixtureBytes fixture)
          inspected <-
            expectRight
              =<< CheckpointStore.readCheckpointManifest root experiment manifestSha
          inspected @?= manifest
          admission <-
            CheckpointStore.admitLocalCheckpointAt root experiment manifestSha
          assertSnapshotCommitFailureContaining
            "legacy unscoped manifests are readable but cannot be admitted"
            admission
    , testCase
        "supervised-graph checkpoint carrying a companion pointer is admission-rejected (Sprint 236.1)"
        $ withSystemTempDirectory "jitml-supervised-companion-reject"
        $ \root -> do
          fixture <- expectRight makeFixture
          let experiment = Checkpoint.manifestExperiment (fixtureManifest fixture)
              companionPayload = "stray supervised companion transcript"
              companionSha = exactSha (LazyByteString.toStrict companionPayload)
              companionKey =
                "jitml-checkpoints/"
                  <> experiment
                  <> "/artifacts/rl-trajectory/"
                  <> companionSha
                  <> ".txt"
              companionPointer =
                Checkpoint.ArtifactPointer
                  { Checkpoint.artifactPointerKind = "rl-trajectory"
                  , Checkpoint.artifactPointerObjectKey = companionKey
                  , Checkpoint.artifactPointerSha = Just companionSha
                  }
              manifest =
                (fixtureManifest fixture)
                  { Checkpoint.manifestTranscriptPointers = [companionPointer]
                  }
          tensor <-
            case Checkpoint.manifestTensors manifest of
              [t] -> pure t
              other ->
                assertFailure
                  ("expected one supervised tensor, got " <> show (length other))
          prepared <-
            expectRight
              ( CheckpointStore.prepareCheckpointSnapshot
                  CheckpointStore.WriterCompletedSnapshot
                  ( CheckpointStore.WriterLatestPointerIntent
                      (Checkpoint.latestPointerKey experiment)
                  )
                  manifest
                  [ (Checkpoint.tensorBlobKey tensor, fixtureFinalBytes fixture)
                  , (companionKey, companionPayload)
                  ]
              )
          stagePreparedCommittedSnapshotLocal root prepared
          admittedCheckpoint <-
            expectRight
              =<< CheckpointStore.admitLocalLatestCheckpoint root experiment
          case CheckpointStore.requireAdmittedCompletedCheckpoint admittedCheckpoint of
            Left (CheckpointStore.AdmissionCompletedV1CompanionInvalid reason) ->
              assertBool
                ("unexpected companion rejection reason: " <> Text.unpack reason)
                ("must not carry a companion pointer" `Text.isInfixOf` reason)
            other ->
              assertFailure
                ( "expected supervised-graph companion rejection through the single"
                    <> " admission path, got "
                    <> show other
                )
    , testCase "stable exact P1 -> manifest -> P2 -> commit -> blob admits completed checkpoint" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        (outcome, operationLog) <-
          runScriptedMinIO
            (admissionCommitListings graph)
            (stableAdmissionReads graph (admissionBlobBytes graph))
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        admitted <- expectRight outcome
        addressed <-
          expectRight
            ( Checkpoint.decodeAddressedManifestCbor
                (LazyByteString.fromStrict (admissionManifestBytes graph))
            )
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
        operationLog @?= stableAdmissionOperationLog graph
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
        (outcome, operationLog) <-
          runScriptedMinIO
            (admissionCommitListings graph)
            readsScript
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        outcome
          @?= Left
            ( CheckpointStore.AdmissionPointerChanged
                (exactSha p1)
                (exactSha p2)
            )
        operationLog
          @?= [ ScriptedRead (admissionPointerRef graph)
              , ScriptedRead (admissionManifestRef graph)
              , ScriptedRead (admissionPointerRef graph)
              ]
    , testCase "known-address admission performs no pointer reads" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let readsScript =
              [ (admissionManifestRef graph, [admissionManifestBytes graph])
              , (admissionCommitRef graph, [admissionCommitBytes graph])
              , (admissionBlobRef graph, [admissionBlobBytes graph])
              ]
        (outcome, operationLog) <-
          runScriptedMinIO
            (admissionCommitListings graph)
            readsScript
            ( CheckpointStore.admitCheckpointAt
                (admissionExperiment graph)
                (admissionManifestSha graph)
            )
        admitted <- expectRight outcome
        _ <- expectRight (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
        operationLog
          @?= [ ScriptedRead (admissionManifestRef graph)
              , admissionCommitListOperation graph
              , ScriptedRead (admissionCommitRef graph)
              , ScriptedRead (admissionBlobRef graph)
              ]
    , testCase "non-canonical known address is rejected before any object read" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let malformedAddress = Text.replicate 64 "A"
        (outcome, operationLog) <-
          runScriptedMinIO
            []
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
        operationLog @?= []
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
                    ( admissionLogicalBlobKey graph
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
    , testCase "commit-bound malformed replacement fails exact blob identity before JMW1 decode" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let malformed = "not-jmw1"
        (outcome, operationLog) <-
          runScriptedMinIO
            (admissionCommitListings graph)
            (stableAdmissionReads graph malformed)
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        assertAdmissionBlobFailureContaining "writer-commit SHA-256 mismatch" outcome
        operationLog @?= stableAdmissionOperationLog graph
    , testCase "substituted valid JMW1 bytes fail blob identity before completion" $ do
        fixture <- expectRight makeFixture
        graph <- expectRight (fixtureAdmissionObjectGraph fixture)
        let substituted =
              LazyByteString.toStrict
                ( WeightCodec.encodeJmw1
                    (0.5 : replicate (fixtureParameterCount fixture - 1) 0.0)
                )
        (outcome, operationLog) <-
          runScriptedMinIO
            (admissionCommitListings graph)
            (stableAdmissionReads graph substituted)
            (CheckpointStore.admitLatestCompletedCheckpoint (admissionExperiment graph))
        assertAdmissionBlobFailureContaining "writer-commit SHA-256 mismatch" outcome
        operationLog @?= stableAdmissionOperationLog graph
    ]

data AdmissionObjectGraph = AdmissionObjectGraph
  { admissionExperiment :: Text
  , admissionManifestSha :: Text
  , admissionPointerKey :: Text
  , admissionManifestKey :: Text
  , admissionLogicalBlobKey :: Text
  , admissionBlobKey :: Text
  , admissionCommitKey :: Text
  , admissionPointerBody :: StrictByteString.ByteString
  , admissionManifestBytes :: StrictByteString.ByteString
  , admissionBlobBytes :: StrictByteString.ByteString
  , admissionCommitBytes :: StrictByteString.ByteString
  , admissionPointerRef :: ObjectRef
  , admissionManifestRef :: ObjectRef
  , admissionBlobRef :: ObjectRef
  , admissionCommitRef :: ObjectRef
  , admissionCompletedTraining :: TrainingBudget.CompletedTraining
  }

fixtureAdmissionObjectGraph :: Fixture -> Either Text AdmissionObjectGraph
fixtureAdmissionObjectGraph fixture = do
  case ( Checkpoint.manifestTensors manifest
       , Checkpoint.manifestCompletedTraining manifest
       ) of
    ([logicalTensor], Just completed) -> do
      prepared <-
        CheckpointStore.prepareCheckpointSnapshot
          CheckpointStore.WriterCompletedSnapshot
          ( CheckpointStore.WriterLatestPointerIntent
              (Checkpoint.latestPointerKey experiment)
          )
          manifest
          [(Checkpoint.tensorBlobKey logicalTensor, fixtureFinalBytes fixture)]
      preparedTensor <-
        case Checkpoint.manifestTensors (CheckpointStore.preparedSnapshotManifest prepared) of
          [tensor] -> Right tensor
          tensors ->
            Left
              ( "prepared Store admission fixture requires one tensor, got "
                  <> Text.pack (show (length tensors))
              )
      let manifestSha = CheckpointStore.preparedSnapshotManifestSha prepared
          manifestKey = Checkpoint.manifestKey experiment manifestSha
          commit = CheckpointStore.preparedSnapshotCommit prepared
          commitKey = CheckpointStore.writerCommitObjectKey commit
      Right
        AdmissionObjectGraph
          { admissionExperiment = experiment
          , admissionManifestSha = manifestSha
          , admissionPointerKey = Checkpoint.latestPointerKey experiment
          , admissionManifestKey = manifestKey
          , admissionLogicalBlobKey = Checkpoint.tensorBlobKey logicalTensor
          , admissionBlobKey = Checkpoint.tensorBlobKey preparedTensor
          , admissionCommitKey = commitKey
          , admissionPointerBody = Text.Encoding.encodeUtf8 manifestSha
          , admissionManifestBytes =
              LazyByteString.toStrict
                (CheckpointStore.preparedSnapshotManifestBytes prepared)
          , admissionBlobBytes = LazyByteString.toStrict (fixtureFinalBytes fixture)
          , admissionCommitBytes = CheckpointStore.encodeWriterCommit commit
          , admissionPointerRef =
              CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experiment)
          , admissionManifestRef = CheckpointStore.checkpointObjectRef manifestKey
          , admissionBlobRef =
              CheckpointStore.checkpointObjectRef (Checkpoint.tensorBlobKey preparedTensor)
          , admissionCommitRef = CheckpointStore.checkpointObjectRef commitKey
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

stagePreparedCommittedSnapshotLocal
  :: FilePath
  -> CheckpointStore.PreparedCheckpointSnapshot
  -> IO ()
stagePreparedCommittedSnapshotLocal root prepared = do
  mapM_
    ( \(objectKey, payload) ->
        void (expectRight =<< CheckpointStore.writeObjectIfAbsent root objectKey payload)
    )
    (CheckpointStore.preparedSnapshotPayloads prepared)
  let manifest = CheckpointStore.preparedSnapshotManifest prepared
      experiment = Checkpoint.manifestExperiment manifest
      manifestSha = CheckpointStore.preparedSnapshotManifestSha prepared
      commit = CheckpointStore.preparedSnapshotCommit prepared
  void
    ( expectRight
        =<< CheckpointStore.writeObjectIfAbsent
          root
          (Checkpoint.manifestKey experiment manifestSha)
          (CheckpointStore.preparedSnapshotManifestBytes prepared)
    )
  void
    ( expectRight
        =<< CheckpointStore.writeObjectIfAbsent
          root
          (CheckpointStore.writerCommitObjectKey commit)
          (LazyByteString.fromStrict (CheckpointStore.encodeWriterCommit commit))
    )
  void
    ( expectRight
        =<< CheckpointStore.writeObjectIfAbsent
          root
          (Checkpoint.latestPointerKey experiment)
          (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 manifestSha))
    )

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
  , (admissionCommitRef graph, [admissionCommitBytes graph])
  , (admissionBlobRef graph, [blobBytes])
  ]

admissionCommitListings
  :: AdmissionObjectGraph
  -> [((BucketName, Text), [ObjectRef])]
admissionCommitListings graph =
  [
    ( (BucketName "jitml-checkpoints", admissionExperiment graph <> "/snapshots/")
    , [admissionCommitRef graph]
    )
  ]

admissionCommitListOperation :: AdmissionObjectGraph -> ScriptedMinIOOperation
admissionCommitListOperation graph =
  ScriptedList
    (BucketName "jitml-checkpoints")
    (admissionExperiment graph <> "/snapshots/")

stableAdmissionOperationLog
  :: AdmissionObjectGraph
  -> [ScriptedMinIOOperation]
stableAdmissionOperationLog graph =
  [ ScriptedRead (admissionPointerRef graph)
  , ScriptedRead (admissionManifestRef graph)
  , ScriptedRead (admissionPointerRef graph)
  , admissionCommitListOperation graph
  , ScriptedRead (admissionCommitRef graph)
  , ScriptedRead (admissionBlobRef graph)
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

assertSnapshotCommitFailureContaining
  :: (Show value)
  => Text
  -> Either CheckpointStore.CheckpointAdmissionError value
  -> Assertion
assertSnapshotCommitFailureContaining expected outcome =
  case outcome of
    Left (CheckpointStore.AdmissionSnapshotCommitInvalid detail) ->
      assertBool
        ( "expected snapshot-commit error containing "
            <> show expected
            <> ", got "
            <> show detail
        )
        (expected `Text.isInfixOf` detail)
    Left other ->
      assertFailure
        ( "expected AdmissionSnapshotCommitInvalid containing "
            <> show expected
            <> ", got "
            <> show other
        )
    Right value ->
      assertFailure
        ( "expected AdmissionSnapshotCommitInvalid containing "
            <> show expected
            <> ", got Right "
            <> show value
        )

data ScriptedMinIOOperation
  = ScriptedRead ObjectRef
  | ScriptedList BucketName Text
  deriving stock (Eq, Show)

data ScriptedMinIOState = ScriptedMinIOState
  { scriptedListResults :: [((BucketName, Text), [ObjectRef])]
  , scriptedReadQueues :: [(ObjectRef, [StrictByteString.ByteString])]
  , scriptedOperationLogReversed :: [ScriptedMinIOOperation]
  }

newtype ScriptedMinIO value = ScriptedMinIO
  { unScriptedMinIO :: ReaderT (IORef ScriptedMinIOState) IO value
  }
  deriving newtype (Functor, Applicative, Monad)

runScriptedMinIO
  :: [((BucketName, Text), [ObjectRef])]
  -> [(ObjectRef, [StrictByteString.ByteString])]
  -> ScriptedMinIO value
  -> IO (value, [ScriptedMinIOOperation])
runScriptedMinIO listings queues action = do
  stateRef <- newIORef (ScriptedMinIOState listings queues [])
  value <- runReaderT (unScriptedMinIO action) stateRef
  finalState <- readIORef stateRef
  pure (value, reverse (scriptedOperationLogReversed finalState))

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
                    , scriptedOperationLogReversed =
                        ScriptedRead objectRef : scriptedOperationLogReversed state
                    }
             in (nextState, response)
        )
  putBlobIfAbsent _ _ = scriptedUnexpected "putBlobIfAbsent"
  putBlobBytesIfAbsent _ _ = scriptedUnexpected "putBlobBytesIfAbsent"
  casPointer _ _ _ = scriptedUnexpected "casPointer"
  listObjects bucket prefix =
    ScriptedMinIO $ do
      stateRef <- ask
      liftIO
        ( atomicModifyIORef' stateRef $ \state ->
            let request = (bucket, prefix)
                response =
                  maybe
                    ( Left
                        ( SETransient
                            ( "scripted HasMinIO has no list result for "
                                <> Text.pack (show request)
                            )
                        )
                    )
                    Right
                    (lookup request (scriptedListResults state))
                nextState =
                  state
                    { scriptedOperationLogReversed =
                        ScriptedList bucket prefix
                          : scriptedOperationLogReversed state
                    }
             in (nextState, response)
        )
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
  , fixtureOuter :: Checkpoint.RawCheckpointEnvelope
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
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  let parameterCount = mnistFixtureParameterCount
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
          , TrainingExecution.tmTrainedLayerGraphMetadata = Just fixtureGraphMetadata
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
      parameterCount = mnistFixtureParameterCount
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
              Checkpoint.FlatWeightLayout (supervisedWeightsLayout parameterCount)
          , Checkpoint.manifestStep =
              TrainingBudget.completedTrainingObservedUnits completed
          , Checkpoint.manifestMetrics = sortOn fst metricRows
          , Checkpoint.manifestSupervisedRuntime = Just payload
          }
      manifest = Checkpoint.attachCompletedTraining completed base
      bytes = Checkpoint.encodeManifestCbor manifest
  outer <- decodeSerialised bytes
  body <- decodeFixtureSupervisedBody outer
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
    , ProductPublisher.supervisedPublishLayerGraphMetadata =
        TrainingExecution.tmTrainedLayerGraphMetadata metrics
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
    , ProductPublisher.publisherReuseAdmittedCheckpoint =
        \_ -> pure Nothing
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
  datasetSha <- Dataset.canonicalDatasetReadShaForProblem problem
  let planId = ProductMatrix.productProjectionPlanId projection
      parameterCount = mnistFixtureParameterCount
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
        , Runtime.rawRuntimePayloadLayerGraphMetadata = Just fixtureGraphMetadata
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
  let tensor =
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
              Checkpoint.FlatWeightLayout (supervisedWeightsLayout parameterCount)
          , Checkpoint.manifestStep = observedUnits
          , Checkpoint.manifestMetrics = metrics
          , Checkpoint.manifestSupervisedRuntime = Just payload
          }
      manifest = Checkpoint.attachCompletedTraining completed base
      bytes = Checkpoint.encodeManifestCbor manifest
  outer <- decodeSerialised bytes
  body <- decodeFixtureSupervisedBody outer
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
    { Runtime.rawSupervisedRuntimeTask = Runtime.RawClassificationRuntimeTask 10
    , Runtime.rawSupervisedRuntimeInputTransform =
        Runtime.RawUnitImageInput (Runtime.RawRuntimeImageGeometry 28 28 1)
    , Runtime.rawSupervisedRuntimeOutputTransform =
        Runtime.RawSemanticPrefixOutput 10
    }

-- | Phase 239: the dense mnist-shallow-mlp trained graph is the fixture's sole
-- representation.  Its graph-ordered parameter count anchors the synthetic
-- weight blobs, the flat weight layout, and admission.
mnistShallowMlpProblem :: SL.CanonicalProblem
mnistShallowMlpProblem =
  case find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems of
    Just problem -> problem
    Nothing -> error "missing canonical mnist-shallow-mlp problem"

fixtureGraphMetadata :: LayerGraphMetadata.LayerGraphMetadata
fixtureGraphMetadata =
  LayerGraphMetadata.layerGraphMetadataFromGraph
    ( Architecture.archLayerGraph
        ( Architecture.architectureSpecForProblem
            ( Classifier.defaultClassifierConfig
                { Classifier.clfInputs = 784
                , Classifier.clfClasses = 10
                }
            )
            mnistShallowMlpProblem
        )
    )

mnistFixtureParameterCount :: Int
mnistFixtureParameterCount =
  LayerGraphMetadata.layerGraphMetadataParameterCount fixtureGraphMetadata

-- | The graph-ordered flat weight layout: one spec of the graph parameter
-- count.  Both checkpoint construction and admission key on this single spec.
supervisedWeightsLayout :: Int -> [Checkpoint.TensorSpec]
supervisedWeightsLayout parameterCount =
  [ Checkpoint.TensorSpec
      { Checkpoint.tensorSpecName = "supervised.weights"
      , Checkpoint.tensorSpecShape = [parameterCount]
      , Checkpoint.tensorSpecDtype = "F64"
      }
  ]

californiaFixtureGraphMetadata :: LayerGraphMetadata.LayerGraphMetadata
californiaFixtureGraphMetadata =
  case mlpLayerGraph (mlpInit (MlpShape 8 32 1) 0) of
    Right graph -> LayerGraphMetadata.layerGraphMetadataFromGraph graph
    Left err -> error ("california fixture graph metadata: " <> err)

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
            { Runtime.rawSupervisedRuntimeTask =
                Runtime.RawRegressionRuntimeTask 1
            , Runtime.rawSupervisedRuntimeInputTransform =
                Runtime.RawStandardizeInput (replicate 8 0.0) (replicate 8 1.0)
            , Runtime.rawSupervisedRuntimeOutputTransform =
                Runtime.RawDestandardizeOutput [100.0] [5.0]
            }
      , Runtime.rawRuntimePayloadLayerGraphMetadata =
          Just californiaFixtureGraphMetadata
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

-- | Extract the supervised-graph body from a decoded fixture envelope.  Every
-- fixture in this module builds a supervised (V2) checkpoint, so a weight-only
-- payload is a fixture construction error.
decodeFixtureSupervisedBody
  :: Checkpoint.RawCheckpointEnvelope -> Either Text Checkpoint.RawCheckpointBodyV2
decodeFixtureSupervisedBody outer = do
  bodySum <-
    decodeSerialised
      (LazyByteString.fromStrict (Checkpoint.rawCheckpointBodyBytes outer))
  case bodySum of
    Checkpoint.RawSupervisedGraphBody body -> Right body
    Checkpoint.RawWeightOnlyBody _ ->
      Left "fixture body is not a supervised-graph payload"

wrapBody :: Checkpoint.RawCheckpointBodyV2 -> LazyByteString.ByteString
wrapBody body =
  let bodyBytes =
        LazyByteString.toStrict (serialise (Checkpoint.RawSupervisedGraphBody body))
   in serialise
        Checkpoint.RawCheckpointEnvelope
          { Checkpoint.rawCheckpointVersion = Checkpoint.checkpointWireVersionV2
          , Checkpoint.rawCheckpointBodySha256 = shaBytes bodyBytes
          , Checkpoint.rawCheckpointBodyBytes = bodyBytes
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
