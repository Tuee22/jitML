{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module CheckpointV1Admission
  ( checkpointV1AdmissionTests
  )
where

import Control.Monad (void)
import Control.Monad.Reader (runReaderT)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (find)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
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
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher qualified as ProductPublisher
import JitML.Substrate (Substrate (LinuxCPU))
import JitML.Training.Budget qualified as TrainingBudget

checkpointV1AdmissionTests :: TestTree
checkpointV1AdmissionTests =
  testGroup
    "canonical ProductRow V1 admission"
    [ testCase "non-supervised Product V1 binds transcript bytes and re-admits its exact stored address" $
        withSystemTempDirectory "jitml-product-v1-admission" $ \cacheRoot -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          env <-
            buildEnv
              defaultGlobalFlags
                { globalCacheDir = Just cacheRoot
                }
          artifact <-
            runReaderT
              ( CheckpointWriter.writeTextArtifact
                  (v1Experiment fixture)
                  "rl-trajectory"
                  "exact product transcript"
              )
              env
          let transcriptPointer =
                Checkpoint.ArtifactPointer
                  { Checkpoint.artifactPointerKind = "rl-trajectory"
                  , Checkpoint.artifactPointerObjectKey =
                      CheckpointWriter.storedArtifactObjectKey artifact
                  , Checkpoint.artifactPointerSha =
                      Just (CheckpointWriter.storedArtifactSha artifact)
                  }
          stored <-
            runReaderT
              ( CheckpointWriter.writeLocalCompletedProductWeightCheckpoint
                  (v1Completed fixture)
                  (v1Experiment fixture)
                  (v1TensorName fixture)
                  (v1Step fixture)
                  (v1Metrics fixture)
                  (v1FinalWeights fixture)
                  [transcriptPointer]
              )
              env
          admitted <-
            expectRight
              =<< runReaderT
                ( CheckpointWriter.admitLocalStoredCompletedCheckpoint
                    (v1Experiment fixture)
                    stored
                )
                env
          let checkpoint = CheckpointStore.admittedCompletedCheckpoint admitted
              storedSnapshot = CheckpointStore.completedStoredCheckpoint stored
          CheckpointStore.admittedCheckpointManifestSha checkpoint
            @?= CheckpointStore.storedManifestSha storedSnapshot
          case Checkpoint.manifestTranscriptPointers
            (CheckpointStore.admittedCheckpointManifest checkpoint) of
            [storedTranscript] -> do
              Checkpoint.artifactPointerKind storedTranscript
                @?= Checkpoint.artifactPointerKind transcriptPointer
              Checkpoint.artifactPointerSha storedTranscript
                @?= Checkpoint.artifactPointerSha transcriptPointer
              assertBool
                "admitted transcript is isolated in the checkpoint snapshot"
                ( "/snapshots/"
                    `Text.isInfixOf` Checkpoint.artifactPointerObjectKey storedTranscript
                )
            pointers ->
              assertFailure
                ("expected one admitted transcript pointer, got " <> show (length pointers))
          CheckpointStore.admittedCompletedTraining admitted
            @?= v1Completed fixture
          exactProjection <- expectRight (rlProjectionForRowId "DQN/cartpole")
          ProductPublisher.validateAdmittedProductCheckpoint
            exactProjection
            (v1Completed fixture)
            stored
            admitted
            @?= Right ()
          substitutedProjection <-
            expectRight (rlProjectionForRowId "DQN/mountain-car")
          assertLeft
            ( ProductPublisher.validateAdmittedProductCheckpoint
                substitutedProjection
                (v1Completed fixture)
                stored
                admitted
            )
    , testCase "non-product V1 remains inspectable but cannot refine to completed evidence" $
        withSystemTempDirectory "jitml-non-product-v1-admission" $ \root -> do
          fixture <-
            expectRight
              (makeV1Fixture "DQN/cartpole" (Just "non-product-v1-experiment"))
          manifestSha <- stageAddressedV1 root fixture
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          CheckpointStore.requireAdmittedCompletedCheckpoint admitted
            @?= Left
              ( CheckpointStore.AdmissionCompletedV1ProductRowRequired
                  (v1Experiment fixture)
              )
    , testCase
        "canonical non-supervised Product V1 without its companion cannot refine to completed evidence"
        $ withSystemTempDirectory "jitml-product-v1-missing-companion"
        $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          manifestSha <- stageAddressedV1 root fixture
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "expected exactly one rl-trajectory transcript pointer"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase
        "generic completed V1 writer cannot create an admitted ProductRow completion without a companion"
        $ withSystemTempDirectory "jitml-product-v1-generic-writer"
        $ \cacheRoot -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          env <-
            buildEnv
              defaultGlobalFlags
                { globalCacheDir = Just cacheRoot
                }
          stored <-
            runReaderT
              ( CheckpointWriter.writeLocalCompletedWeightCheckpoint
                  (v1Completed fixture)
                  (v1Experiment fixture)
                  (v1TensorName fixture)
                  (v1Step fixture)
                  (v1Metrics fixture)
                  (v1FinalWeights fixture)
              )
              env
          outcome <-
            runReaderT
              ( CheckpointWriter.admitLocalStoredCompletedCheckpoint
                  (v1Experiment fixture)
                  stored
              )
              env
          assertCompanionAdmissionFailureContaining
            "expected exactly one rl-trajectory transcript pointer"
            outcome
    , testCase "wrong-family Product V1 companion kind is completion-rejected" $
        withSystemTempDirectory "jitml-product-v1-wrong-companion-kind" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let (pointer, artifactPayload) =
                v1Artifact (v1Experiment fixture) "tune-trials" "wrong family companion"
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestTranscriptPointers = [pointer]
                  }
          manifestSha <-
            stageAddressedV1Graph root fixture manifest [artifactPayload]
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "expected companion kind rl-trajectory"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase "Product V1 manifest model family must match its canonical row family" $
        withSystemTempDirectory "jitml-product-v1-wrong-manifest-family" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let (pointer, artifactPayload) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" "exact trajectory"
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestModelFamily =
                      Checkpoint.HyperparameterTuningFamily
                  , Checkpoint.manifestTranscriptPointers = [pointer]
                  }
          manifestSha <-
            stageAddressedV1Graph root fixture manifest [artifactPayload]
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "manifest model family"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase "Product V1 architecture family must match its canonical row family" $
        withSystemTempDirectory "jitml-product-v1-wrong-architecture-family" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let (pointer, artifactPayload) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" "exact trajectory"
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestArchitecture =
                      (Checkpoint.manifestArchitecture (v1Manifest fixture))
                        { Checkpoint.architectureModelFamily =
                            Checkpoint.HyperparameterTuningFamily
                        }
                  , Checkpoint.manifestTranscriptPointers = [pointer]
                  }
          manifestSha <-
            stageAddressedV1Graph root fixture manifest [artifactPayload]
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "manifest architecture family"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase "multiple distinct Product V1 companion pointers are completion-rejected" $
        withSystemTempDirectory "jitml-product-v1-extra-companion" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let (pointerA, artifactPayloadA) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" "first trajectory"
              (pointerB, artifactPayloadB) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" "second trajectory"
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestTranscriptPointers = [pointerA, pointerB]
                  }
          manifestSha <-
            stageAddressedV1Graph
              root
              fixture
              manifest
              [artifactPayloadA, artifactPayloadB]
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "expected exactly one rl-trajectory transcript pointer"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase "duplicate Product V1 companion pointers fail before persistence" $
        withSystemTempDirectory "jitml-product-v1-duplicate-companion" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let (pointer, artifactPayload) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" "duplicate trajectory"
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestTranscriptPointers = [pointer, pointer]
                  }
          outcome <-
            CheckpointStore.writeCompletedCheckpointSnapshot
              root
              (v1Completed fixture)
              manifest
              [(v1BlobKey fixture, v1FinalBytes fixture), artifactPayload]
              Nothing
          case outcome of
            Left (CheckpointStore.CheckpointWriteInvalid reason) ->
              assertBool
                ("unexpected duplicate-pointer diagnostic: " <> Text.unpack reason)
                ("duplicate physical object key declarations" `Text.isInfixOf` reason)
            other ->
              assertFailure
                ("duplicate companion pointers unexpectedly persisted: " <> show other)
    , testCase "Product V1 rejects replay-pointer residue in addition to its exact companion" $
        withSystemTempDirectory "jitml-product-v1-replay-pointer" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let (trajectoryPointer, trajectoryPayload) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" "exact trajectory"
              (replayPointer, replayPayload) =
                v1Artifact (v1Experiment fixture) "rl-replay" "orphan replay"
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestReplayPointers = [replayPointer]
                  , Checkpoint.manifestTranscriptPointers = [trajectoryPointer]
                  }
          manifestSha <-
            stageAddressedV1Graph
              root
              fixture
              manifest
              [trajectoryPayload, replayPayload]
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "expected no replay pointers"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase "Product V1 rejects a snapshot-scoped companion derived from a substituted original key" $
        withSystemTempDirectory "jitml-product-v1-substituted-companion-key" $ \root -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          let payload = "substituted trajectory address"
              (canonicalPointer, _) =
                v1Artifact (v1Experiment fixture) "rl-trajectory" payload
              substitutedKey =
                "jitml-checkpoints/"
                  <> v1Experiment fixture
                  <> "/artifacts/substituted/"
                  <> fromMaybe "missing" (Checkpoint.artifactPointerSha canonicalPointer)
                  <> ".txt"
              pointer =
                canonicalPointer
                  { Checkpoint.artifactPointerObjectKey = substitutedKey
                  }
              manifest =
                (v1Manifest fixture)
                  { Checkpoint.manifestTranscriptPointers = [pointer]
                  }
          manifestSha <-
            stageAddressedV1Graph
              root
              fixture
              manifest
              [(substitutedKey, payload)]
          admitted <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          assertCompanionAdmissionFailureContaining
            "is not the exact snapshot-scoped canonical content address"
            (CheckpointStore.requireAdmittedCompletedCheckpoint admitted)
    , testCase "historical supervised ProductRow V1 is exact-inspectable but completion-rejected" $
        withSystemTempDirectory "jitml-supervised-v1-inspection" $ \root -> do
          fixture <- expectRight (makeV1Fixture "mnist-shallow-mlp" Nothing)
          manifestSha <- stageAddressedV1 root fixture
          addressed <-
            expectRight
              =<< CheckpointStore.admitLocalCheckpointAt
                root
                (v1Experiment fixture)
                manifestSha
          case CheckpointStore.requireAdmittedCompletedCheckpoint addressed of
            Left (CheckpointStore.AdmissionCompletionInvalid reason) ->
              assertBool
                ("unexpected supervised V1 diagnostic: " <> Text.unpack reason)
                ("inspection-only" `Text.isInfixOf` reason)
            Left other ->
              assertFailure
                ("expected supervised V1 completion rejection, got " <> show other)
            Right _ ->
              assertFailure "supervised V1 unexpectedly refined to completed evidence"
    , testCase "legacy unscoped V1 remains readable for inspection but is not admission evidence" $
        withSystemTempDirectory "jitml-v1-legacy-unscoped-inspection" $ \root -> do
          fixture <-
            expectRight
              (makeV1Fixture "DQN/cartpole" (Just "legacy-unscoped-v1-experiment"))
          let manifest = v1Manifest fixture
              manifestSha = Checkpoint.manifestContentSha manifest
              manifestKey =
                Checkpoint.manifestKey (v1Experiment fixture) manifestSha
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                (v1BlobKey fixture)
                (v1FinalBytes fixture)
          _ <-
            expectRight
              =<< CheckpointStore.writeObjectIfAbsent
                root
                manifestKey
                (Checkpoint.encodeManifestCbor manifest)
          inspected <-
            expectRight
              =<< CheckpointStore.readCheckpointManifest
                root
                (v1Experiment fixture)
                manifestSha
          inspected @?= manifest
          admission <-
            CheckpointStore.admitLocalCheckpointAt
              root
              (v1Experiment fixture)
              manifestSha
          assertSnapshotCommitFailureContaining
            "legacy unscoped manifests are readable but cannot be admitted"
            admission
    , testCase "tampered transcript bytes violate commit-bound Product V1 re-admission" $
        withSystemTempDirectory "jitml-product-v1-transcript-tamper" $ \cacheRoot -> do
          fixture <- expectRight (makeV1Fixture "DQN/cartpole" Nothing)
          env <-
            buildEnv
              defaultGlobalFlags
                { globalCacheDir = Just cacheRoot
                }
          artifact <-
            runReaderT
              ( CheckpointWriter.writeTextArtifact
                  (v1Experiment fixture)
                  "rl-trajectory"
                  "exact product transcript"
              )
              env
          let artifactKey = CheckpointWriter.storedArtifactObjectKey artifact
              transcriptPointer =
                Checkpoint.ArtifactPointer
                  { Checkpoint.artifactPointerKind = "rl-trajectory"
                  , Checkpoint.artifactPointerObjectKey = artifactKey
                  , Checkpoint.artifactPointerSha =
                      Just (CheckpointWriter.storedArtifactSha artifact)
                  }
          stored <-
            runReaderT
              ( CheckpointWriter.writeLocalCompletedProductWeightCheckpoint
                  (v1Completed fixture)
                  (v1Experiment fixture)
                  (v1TensorName fixture)
                  (v1Step fixture)
                  (v1Metrics fixture)
                  (v1FinalWeights fixture)
                  [transcriptPointer]
              )
              env
          let storedSnapshot = CheckpointStore.completedStoredCheckpoint stored
              checkpointRoot = cacheRoot </> "checkpoints"
          storedManifest <-
            expectRight
              =<< CheckpointStore.readCheckpointManifest
                checkpointRoot
                (v1Experiment fixture)
                (CheckpointStore.storedManifestSha storedSnapshot)
          storedArtifactKey <-
            case Checkpoint.manifestTranscriptPointers storedManifest of
              [storedPointer] ->
                pure (Checkpoint.artifactPointerObjectKey storedPointer)
              pointers ->
                assertFailure
                  ( "expected one snapshot-scoped transcript pointer, got "
                      <> show (length pointers)
                  )
                  >> error "unreachable"
          assertBool
            "tamper target must be the committed snapshot copy"
            ("/snapshots/" `Text.isInfixOf` storedArtifactKey)
          artifactPath <-
            expectRight
              (CheckpointStore.objectPathForKey checkpointRoot storedArtifactKey)
          LazyByteString.writeFile artifactPath "tampered transcript"
          outcome <-
            runReaderT
              ( CheckpointWriter.admitLocalStoredCompletedCheckpoint
                  (v1Experiment fixture)
                  stored
              )
              env
          assertAdmissionBlobFailureContaining
            "writer-commit SHA-256 mismatch"
            outcome
    ]

data V1Fixture = V1Fixture
  { v1Experiment :: !Text
  , v1TensorName :: !Text
  , v1BlobKey :: !Text
  , v1Step :: !Word64
  , v1Metrics :: ![(Text, Double)]
  , v1FinalWeights :: ![Double]
  , v1FinalBytes :: !LazyByteString.ByteString
  , v1Completed :: !TrainingBudget.CompletedTraining
  , v1Manifest :: !Checkpoint.CheckpointManifest
  }

makeV1Fixture :: Text -> Maybe Text -> Either Text V1Fixture
makeV1Fixture rowId experimentOverride = do
  row <-
    maybe
      (Left ("missing canonical ProductRow " <> rowId))
      Right
      (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)
  planId <- productPlanId row
  let experiment =
        fromMaybe (ProductMatrix.productRowExperimentHash row) experimentOverride
      tensorName =
        case ProductMatrix.family row of
          ProductMatrix.Supervised -> "legacy-supervised-weights"
          ProductMatrix.ReinforcementLearning -> "rl-dqn-weights"
          ProductMatrix.AlphaZero -> "alphazero-weights"
          ProductMatrix.Tuning -> "tune-promoted-weights"
      initialWeights = [0.0, 0.0]
      finalWeights = [0.25, 0.5]
      initialBytes = WeightCodec.encodeJmw1 initialWeights
      finalBytes = WeightCodec.encodeJmw1 finalWeights
      finalSha = WeightCodec.jmw1ContentSha finalBytes
      blobKey = Checkpoint.blobKey experiment finalSha
      bar = ProductMatrix.convergenceBar row
      metrics =
        [
          ( ProductConvergence.convergenceMetricName bar
          , ProductConvergence.convergenceThreshold bar
          )
        ]
      budget = ProductMatrix.trainingBudget row
      step = TrainingBudget.trainingBudgetTargetUnits budget
  completed <-
    ProductCompletion.completedTrainingForProductRowWithWeightHashes
      planId
      budget
      row
      (Text.replicate 64 "d")
      experiment
      step
      1
      metrics
      (WeightCodec.jmw1ContentSha initialBytes)
      finalSha
  let tensor = Checkpoint.TensorBlob tensorName [length finalWeights] blobKey
      modelFamily = checkpointFamilyForRow row
      manifest =
        Checkpoint.attachCompletedTraining completed $
          (Checkpoint.emptyManifest "product-v1-completed" experiment [tensor])
            { Checkpoint.manifestModelFamily = modelFamily
            , Checkpoint.manifestArchitecture =
                Checkpoint.defaultArchitectureMetadata modelFamily
            , Checkpoint.manifestStep = step
            , Checkpoint.manifestMetrics = metrics
            }
  addressed <- Checkpoint.decodeAddressedManifestCbor (Checkpoint.encodeManifestCbor manifest)
  if Checkpoint.addressedManifestWireVersion addressed == Checkpoint.checkpointWireVersion
    then Right ()
    else Left "V1 fixture unexpectedly encoded with a non-V1 wire version"
  Right
    V1Fixture
      { v1Experiment = experiment
      , v1TensorName = tensorName
      , v1BlobKey = blobKey
      , v1Step = step
      , v1Metrics = metrics
      , v1FinalWeights = finalWeights
      , v1FinalBytes = finalBytes
      , v1Completed = completed
      , v1Manifest = manifest
      }

productPlanId
  :: ProductMatrix.ProductRow state
  -> Either Text Plan.PlanId
productPlanId row =
  case ProductMatrix.projectProductRow LinuxCPU row of
    Plan.Success (ProductMatrix.SomeProductProjection _ projection) ->
      Right (ProductMatrix.productProjectionPlanId projection)
    Plan.Failure errors ->
      Left ("ProductRow projection failed: " <> Text.pack (show errors))

rlProjectionForRowId
  :: Text
  -> Either
       Text
       (ProductMatrix.ProductProjection 'Plan.ReinforcementLearning)
rlProjectionForRowId rowId = do
  row <-
    maybe
      (Left ("missing canonical RL ProductRow " <> rowId))
      Right
      (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)
  case ProductMatrix.projectProductRow LinuxCPU row of
    Plan.Success
      ( ProductMatrix.SomeProductProjection
          Plan.ReinforcementLearningWitness
          projection
        ) -> Right projection
    Plan.Success _ -> Left ("ProductRow is not RL: " <> rowId)
    Plan.Failure errors ->
      Left ("ProductRow projection failed: " <> Text.pack (show errors))

checkpointFamilyForRow
  :: ProductMatrix.ProductRow state
  -> Checkpoint.ModelFamily
checkpointFamilyForRow row =
  case ProductMatrix.family row of
    ProductMatrix.Supervised -> Checkpoint.GenericModelFamily
    ProductMatrix.ReinforcementLearning ->
      Checkpoint.ReinforcementLearningPolicyFamily
    ProductMatrix.AlphaZero -> Checkpoint.AlphaZeroPolicyValueFamily
    ProductMatrix.Tuning -> Checkpoint.HyperparameterTuningFamily

stageAddressedV1 :: FilePath -> V1Fixture -> IO Text
stageAddressedV1 root fixture =
  stageAddressedV1Graph root fixture (v1Manifest fixture) []

stageAddressedV1Graph
  :: FilePath
  -> V1Fixture
  -> Checkpoint.CheckpointManifest
  -> [(Text, LazyByteString.ByteString)]
  -> IO Text
stageAddressedV1Graph root fixture manifest extraPayloads = do
  let experiment = v1Experiment fixture
      pointerKey = Checkpoint.latestPointerKey experiment
  prepared <-
    expectRight
      ( CheckpointStore.prepareCheckpointSnapshot
          CheckpointStore.WriterCompletedSnapshot
          (CheckpointStore.WriterLatestPointerIntent pointerKey)
          manifest
          ((v1BlobKey fixture, v1FinalBytes fixture) : extraPayloads)
      )
  mapM_
    ( \(objectKey, payload) ->
        void (expectRight =<< CheckpointStore.writeObjectIfAbsent root objectKey payload)
    )
    (CheckpointStore.preparedSnapshotPayloads prepared)
  let manifestSha = CheckpointStore.preparedSnapshotManifestSha prepared
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
          pointerKey
          (LazyByteString.fromStrict (Text.Encoding.encodeUtf8 manifestSha))
    )
  pure manifestSha

v1Artifact
  :: Text
  -> Text
  -> LazyByteString.ByteString
  -> (Checkpoint.ArtifactPointer, (Text, LazyByteString.ByteString))
v1Artifact experimentHash kind payload =
  let sha = WeightCodec.jmw1ContentSha payload
      objectKey =
        "jitml-checkpoints/"
          <> experimentHash
          <> "/artifacts/"
          <> kind
          <> "/"
          <> sha
          <> ".txt"
   in ( Checkpoint.ArtifactPointer
          { Checkpoint.artifactPointerKind = kind
          , Checkpoint.artifactPointerObjectKey = objectKey
          , Checkpoint.artifactPointerSha = Just sha
          }
      , (objectKey, payload)
      )

assertCompanionAdmissionFailureContaining
  :: Text
  -> Either CheckpointStore.CheckpointAdmissionError value
  -> Assertion
assertCompanionAdmissionFailureContaining expected outcome =
  case outcome of
    Left (CheckpointStore.AdmissionCompletedV1CompanionInvalid reason) ->
      assertBool
        ( "expected Product V1 companion diagnostic containing "
            <> Text.unpack expected
            <> ", got "
            <> Text.unpack reason
        )
        (expected `Text.isInfixOf` reason)
    Left other ->
      assertFailure
        ("expected AdmissionCompletedV1CompanionInvalid, got " <> show other)
    Right _ ->
      assertFailure "invalid Product V1 companion unexpectedly passed completion admission"

assertAdmissionBlobFailureContaining
  :: Text
  -> Either CheckpointStore.CheckpointAdmissionError value
  -> Assertion
assertAdmissionBlobFailureContaining expected outcome =
  case outcome of
    Left (CheckpointStore.AdmissionBlobInvalid reason) ->
      assertBool
        ( "expected blob admission diagnostic containing "
            <> Text.unpack expected
            <> ", got "
            <> Text.unpack reason
        )
        (expected `Text.isInfixOf` reason)
    Left other ->
      assertFailure
        ("expected AdmissionBlobInvalid, got " <> show other)
    Right _ ->
      assertFailure "tampered transcript unexpectedly passed exact admission"

assertSnapshotCommitFailureContaining
  :: Text
  -> Either CheckpointStore.CheckpointAdmissionError value
  -> Assertion
assertSnapshotCommitFailureContaining expected outcome =
  case outcome of
    Left (CheckpointStore.AdmissionSnapshotCommitInvalid reason) ->
      assertBool
        ( "expected snapshot-commit diagnostic containing "
            <> Text.unpack expected
            <> ", got "
            <> Text.unpack reason
        )
        (expected `Text.isInfixOf` reason)
    Left other ->
      assertFailure
        ("expected AdmissionSnapshotCommitInvalid, got " <> show other)
    Right _ ->
      assertFailure "legacy unscoped checkpoint unexpectedly passed admission"

assertLeft :: Either err value -> Assertion
assertLeft outcome =
  case outcome of
    Left _ -> pure ()
    Right _ -> assertFailure "expected Left, got Right"

expectRight :: (Show err) => Either err value -> IO value
expectRight outcome =
  case outcome of
    Left err -> assertFailure ("expected Right, got Left " <> show err) >> error "unreachable"
    Right value -> pure value
