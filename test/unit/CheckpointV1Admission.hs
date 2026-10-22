{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module CheckpointV1Admission
  ( checkpointV1AdmissionTests
  )
where

import Control.Monad (forM_, void)
import Control.Monad.Reader (runReaderT)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (find)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Word (Word64)
import System.Directory (canonicalizePath, getCurrentDirectory)
import System.Environment (getEnvironment, getExecutablePath, lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit
  ( Assertion
  , assertBool
  , assertFailure
  , testCase
  , (@?=)
  )

import JitML.CLI.Output (writeLineIO)
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Checkpoint.Writer qualified as CheckpointWriter
import JitML.Env.Build (GlobalFlags (..), buildEnv, defaultGlobalFlags)
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Publisher qualified as ProductPublisher
import JitML.RL.Algorithms.PpoTrainer qualified as PpoTrainer
import JitML.Sub.Outcome (ProcessOutcome (..), ProcessTranscript (..), renderProcessFailure)
import JitML.Sub.Stream (runStreaming, subprocessEnvOverrideAndRemove)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.DeviceWitnessFixture qualified as DeviceWitnessFixture
import JitML.Test.ValidationEvidence qualified as ValidationEvidence
import JitML.Training.Budget qualified as TrainingBudget

-- These offline fixtures exercise the real writer and admission path. Give each
-- action its own process working directory so an ambient live publication cannot
-- turn fixture writes into attempted cluster publication. The child keeps the
-- complete original action and acknowledges only after every assertion passes.
isolatedCheckpointWriterCase :: String -> Assertion -> TestTree
isolatedCheckpointWriterCase caseName action =
  testCase caseName $ do
    childCase <- lookupEnv isolatedCheckpointCaseVariable
    childRoot <- lookupEnv isolatedCheckpointRootVariable
    case (childCase, childRoot) of
      (Nothing, Nothing) ->
        withSystemTempDirectory "jitml-checkpoint-v1-isolated" $ \temporaryRoot -> do
          root <- canonicalizePath temporaryRoot
          executable <- getExecutablePath >>= canonicalizePath
          inherited <- getEnvironment
          let environment =
                subprocessEnvOverrideAndRemove
                  [ (Text.pack isolatedCheckpointCaseVariable, Text.pack caseName)
                  , (Text.pack isolatedCheckpointRootVariable, Text.pack root)
                  ]
                  (ValidationEvidence.runAlteringEnvironment inherited)
              -- Tasty string literals use Haskell's string reader, so show
              -- escapes the exact name rather than building a regex or shell.
              selector =
                "$NF == "
                  <> Text.pack (show caseName)
                  <> " && $(NF - 1) == "
                  <> Text.pack (show ("canonical ProductRow V1 admission" :: String))
              command =
                (subprocess executable ["--pattern", selector, "--num-threads=1", "--quiet"])
                  { subprocessWorkingDirectory = Just root
                  }
          result <- timeout 60000000 (runStreaming environment command)
          case result of
            Nothing -> assertFailure "isolated checkpoint writer child timed out"
            Just (ProcessFailed failure) ->
              assertFailure (Text.unpack (renderProcessFailure failure))
            Just (ProcessSucceeded transcript) ->
              assertBool
                ( "isolated checkpoint writer child did not acknowledge exactly one completed action: "
                    <> show transcript
                )
                ( length
                    ( filter
                        (== isolatedCheckpointAcknowledgement caseName root)
                        (Text.lines (processTranscriptStdout transcript))
                    )
                    == 1
                )
      (Just selectedCase, Just root) -> do
        selectedCase @?= caseName
        canonicalRoot <- canonicalizePath root
        workingDirectory <- getCurrentDirectory >>= canonicalizePath
        assertBool
          "isolated checkpoint writer child is outside its canonical private root"
          (root == canonicalRoot && workingDirectory == canonicalRoot)
        action
        writeLineIO (isolatedCheckpointAcknowledgement caseName root)
      _ -> assertFailure "isolated checkpoint writer child markers are incomplete"

isolatedCheckpointCaseVariable :: String
isolatedCheckpointCaseVariable = "JITML_CHECKPOINT_V1_ADMISSION_CHILD_CASE"

isolatedCheckpointRootVariable :: String
isolatedCheckpointRootVariable = "JITML_CHECKPOINT_V1_ADMISSION_CHILD_ROOT"

isolatedCheckpointAcknowledgement :: String -> FilePath -> Text
isolatedCheckpointAcknowledgement caseName root =
  "JITML_CHECKPOINT_V1_ADMISSION_COMPLETE "
    <> WeightCodec.jmw1ContentSha
      ( LazyByteString.fromStrict
          (Text.Encoding.encodeUtf8 (Text.pack caseName <> "\NUL" <> Text.pack root))
      )

checkpointV1AdmissionTests :: TestTree
checkpointV1AdmissionTests =
  testGroup
    "canonical ProductRow V1 admission"
    [ testCase "TRPO numerical recipe changes all four row identities in each lane" $ do
        forM_ [LinuxCPU, LinuxCUDA, AppleSilicon] $ \lane -> do
          let trpoRows =
                [ row
                | row <- ProductMatrix.allProductRows
                , ProductMatrix.RlAlgorithmEnvironment "TRPO" _ <- [ProductMatrix.rowClass row]
                ]
          length trpoRows @?= 4
          forM_ trpoRows $ \row -> do
            projection <- expectRight (rlProjectionForRowIdIn lane (ProductMatrix.rowId row))
            legacyPlanId <- expectRight (preNormalizationTrpoPlanId projection)
            assertBool
              ( "TRPO numerical recipe did not change PlanId for "
                  <> show lane
                  <> "/"
                  <> Text.unpack (ProductMatrix.rowId row)
              )
              (legacyPlanId /= ProductMatrix.productProjectionPlanId projection)
    , testCase "on-policy evaluation and rollout recipes version exactly 22 rows in each lane" $ do
        let affected row = case ProductMatrix.rowClass row of
              ProductMatrix.RlAlgorithmEnvironment algorithm _ -> algorithm `elem` ["PPO", "A2C", "TRPO", "MaskablePPO", "RecurrentPPO"]
              _ -> False
            onPolicyRows = filter affected ProductMatrix.allProductRows
            otherRows = filter (not . affected) ProductMatrix.allProductRows
        length onPolicyRows @?= 22
        length otherRows @?= 33
        forM_ [LinuxCPU, LinuxCUDA, AppleSilicon] $ \lane -> do
          forM_ onPolicyRows $ \row -> do
            projection <- expectRight (rlProjectionForRowIdIn lane (ProductMatrix.rowId row))
            previous <- expectRight (preDeviceOnPolicyPlanId projection)
            assertBool
              "on-policy execution recipes did not change the semantic PlanId"
              (previous /= ProductMatrix.productProjectionPlanId projection)
          forM_ otherRows $ \row -> case ProductMatrix.projectProductRow lane row of
            Plan.Success (ProductMatrix.SomeProductProjection _ projection) -> do
              let subject = Plan.runPlanSubjectId (ProductMatrix.productProjectionRunPlan projection)
              assertBool
                "on-policy evaluator recipe escaped to an unrelated row"
                (not (PpoTrainer.onPolicyEvaluationContract `Text.isInfixOf` subject))
              assertBool
                "on-policy rollout recipe escaped to an unrelated row"
                (not (PpoTrainer.onPolicyRolloutContract `Text.isInfixOf` subject))
            Plan.Failure errors -> assertFailure (show errors)
    , testCase "pre-device-evaluation on-policy completion cannot bypass current checkpoint admission" $ do
        let onPolicyRows =
              [ row
              | row <- ProductMatrix.allProductRows
              , ProductMatrix.RlAlgorithmEnvironment algorithm _ <- [ProductMatrix.rowClass row]
              , algorithm `elem` ["PPO", "A2C", "TRPO", "MaskablePPO", "RecurrentPPO"]
              ]
        forM_ onPolicyRows $ \row -> do
          -- Synthetic admission-boundary controls only, never trainer evidence.
          fixture <- expectRight =<< makeV1Fixture (ProductMatrix.rowId row) Nothing
          projection <- expectRight (rlProjectionForRowId (ProductMatrix.rowId row))
          previous <- expectRight (preDeviceOnPolicyPlanId projection)
          legacyCompleted <-
            expectRight $
              TrainingBudget.refineCompletedTraining
                ( (TrainingBudget.completedTrainingToRaw (v1Completed fixture))
                    { TrainingBudget.rawCompletedTrainingPlanId = Plan.planIdText previous
                    }
                )
          let legacyManifest = Checkpoint.attachCompletedTraining legacyCompleted (v1Manifest fixture)
          addressed <-
            expectRight (Checkpoint.decodeAddressedManifestCbor (Checkpoint.encodeManifestCbor legacyManifest))
          case Checkpoint.validateCheckpointCompletion (Checkpoint.addressedManifest addressed) of
            Left err@(Checkpoint.CompletedTrainingExternalBarMismatch _) ->
              assertBool
                ("unexpected old evaluator completion rejection: " <> show err)
                ( "canonical RL completion PlanId differs from its row's device-substrate projection"
                    `Text.isInfixOf` Checkpoint.renderCheckpointCompletionValidationError err
                )
            Left err -> assertFailure ("unexpected admission boundary: " <> show err)
            Right _ -> assertFailure "old on-policy evaluator/truncation completion entered current admission"
          _ <- expectRight (Checkpoint.validateCheckpointCompletion (v1Manifest fixture))
          pure ()
    , isolatedCheckpointWriterCase
        "pre-normalization TRPO completion cannot enter current canonical checkpoint admission"
        $ withSystemTempDirectory "jitml-trpo-recipe-identity"
        $ \cacheRoot -> do
          -- Synthetic boundary fixture only: no trainer or convergence evidence.
          fixture <- expectRight =<< makeV1Fixture "TRPO/cartpole" Nothing
          projection <- expectRight (rlProjectionForRowId "TRPO/cartpole")
          legacyPlanId <- expectRight (preNormalizationTrpoPlanId projection)
          legacyCompleted <-
            expectRight $
              TrainingBudget.refineCompletedTraining
                ( (TrainingBudget.completedTrainingToRaw (v1Completed fixture))
                    { TrainingBudget.rawCompletedTrainingPlanId = Plan.planIdText legacyPlanId
                    }
                )
          let legacyManifest = Checkpoint.attachCompletedTraining legacyCompleted (v1Manifest fixture)
          decodedLegacy <-
            expectRight $
              Checkpoint.decodeAddressedManifestCbor (Checkpoint.encodeManifestCbor legacyManifest)
          -- Structural decoding deliberately permits historical inspection.
          -- Completion refinement is the guard Store invokes before it can mint
          -- an opaque AdmittedCompletedCheckpoint for publication/reuse.
          case Checkpoint.validateCheckpointCompletion (Checkpoint.addressedManifest decodedLegacy) of
            Left err@(Checkpoint.CompletedTrainingExternalBarMismatch _) ->
              assertBool
                ( "unexpected legacy TRPO completion rejection: "
                    <> Text.unpack (Checkpoint.renderCheckpointCompletionValidationError err)
                )
                ( "canonical RL completion PlanId differs from its row's device-substrate projection"
                    `Text.isInfixOf` Checkpoint.renderCheckpointCompletionValidationError err
                )
            Left err ->
              assertFailure
                ( "legacy TRPO completion failed at an unexpected boundary: "
                    <> Text.unpack (Checkpoint.renderCheckpointCompletionValidationError err)
                )
            Right _ -> assertFailure "pre-normalization TRPO checkpoint passed current completed-checkpoint admission"
          env <- buildEnv defaultGlobalFlags {globalCacheDir = Just cacheRoot}
          artifact <-
            runReaderT
              ( CheckpointWriter.writeTextArtifact
                  (v1Experiment fixture)
                  "rl-trajectory"
                  "synthetic current TRPO admission fixture"
              )
              env
          let pointer =
                Checkpoint.ArtifactPointer
                  { Checkpoint.artifactPointerKind = "rl-trajectory"
                  , Checkpoint.artifactPointerObjectKey = CheckpointWriter.storedArtifactObjectKey artifact
                  , Checkpoint.artifactPointerSha = Just (CheckpointWriter.storedArtifactSha artifact)
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
                  [pointer]
              )
              env
          admitted <-
            expectRight
              =<< runReaderT
                (CheckpointWriter.admitLocalStoredCompletedCheckpoint (v1Experiment fixture) stored)
                env
          ProductPublisher.validateAdmittedProductCheckpoint projection (v1Completed fixture) stored admitted
            @?= Right ()
    , isolatedCheckpointWriterCase
        "non-supervised Product V1 binds transcript bytes and re-admits its exact stored address"
        $ withSystemTempDirectory "jitml-product-v1-admission"
        $ \cacheRoot -> do
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
    , isolatedCheckpointWriterCase
        "a reused product publish receipt carries the logical companion address (Phase 266)"
        $ withSystemTempDirectory "jitml-product-v1-reuse-receipt"
        $ \cacheRoot ->
          forM_
            [("DQN/cartpole", "rl-trajectory"), ("hyperparameter-tuning", "tune-trials")]
            $ \(rowId, companionKind) -> do
              -- Ordinary V1 admission is structural fixture DATA. Native rows
              -- refuse legacy callback eligibility; tuning still exercises the
              -- logical companion address and exactly-once snapshot rebasing.
              fixture <- expectRight =<< makeV1Fixture rowId Nothing
              env <- buildEnv defaultGlobalFlags {globalCacheDir = Just cacheRoot}
              artifact <-
                runReaderT
                  ( CheckpointWriter.writeTextArtifact
                      (v1Experiment fixture)
                      companionKind
                      "exact product transcript"
                  )
                  env
              let transcriptPointer =
                    Checkpoint.ArtifactPointer
                      { Checkpoint.artifactPointerKind = companionKind
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
              row <-
                maybe
                  (assertFailure ("missing canonical ProductRow " <> Text.unpack rowId))
                  pure
                  (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)
              result <-
                case ProductMatrix.projectProductRow LinuxCPU row of
                  Plan.Success (ProductMatrix.SomeProductProjection _ projection) ->
                    pure (ProductPublisher.reuseProductPublishResult projection admitted)
                  Plan.Failure errors -> assertFailure (show errors)
              let manifest =
                    CheckpointStore.admittedCheckpointManifest
                      (CheckpointStore.admittedCompletedCheckpoint admitted)
                  receipts = ProductPublisher.productPublishArtifacts result
              if rowId == "DQN/cartpole"
                then do
                  ProductPublisher.productPublishDisposition result
                    @?= ProductPublisher.ProductPublishError
                      "native ProductRow cannot use legacy callback checkpoint eligibility"
                  receipts @?= []
                else do
                  case ProductPublisher.productPublishDisposition result of
                    ProductPublisher.ProductPublishEligible _ -> pure ()
                    other -> assertFailure ("expected structural tuning reuse eligibility, got " <> show other)
                  length receipts @?= 1
                  -- A receipt addresses its companion artifact logically; the batch
                  -- audit rebases that address into the manifest's storage-snapshot
                  -- namespace before comparing inventories. The reuse path used to copy
                  -- the manifest's own pointers, which are already snapshot-scoped, so
                  -- the audit scoped an already-scoped key: same snapshot, same payload
                  -- SHA, different object address. A reused receipt must be exactly the
                  -- receipt a fresh publish would have produced.
                  snapshotId <-
                    expectRight (CheckpointStore.checkpointStorageSnapshotId manifest)
                  -- Every reused receipt is the canonical logical content address.
                  [ ProductPublisher.productArtifactObjectKey receipt
                    | receipt <- receipts
                    ]
                    @?= [ CheckpointStore.canonicalProductCompanionObjectKey
                            (ProductPublisher.productArtifactExperimentHash receipt)
                            (ProductPublisher.productArtifactKind receipt)
                            (ProductPublisher.productArtifactSha receipt)
                        | receipt <- receipts
                        ]
                  assertBool
                    "a reused receipt must not carry an already snapshot-scoped address"
                    ( not
                        ( any
                            ( Text.isInfixOf "/snapshots/"
                                . ProductPublisher.productArtifactObjectKey
                            )
                            receipts
                        )
                    )
                  -- Scoping each receipt exactly once reproduces the admitted manifest's
                  -- own pointers, which is the equality the batch audit asserts.
                  fmap
                    ( ProductPublisher.snapshotScopedPointer manifest snapshotId
                        . receiptPointer
                    )
                    receipts
                    @?= Checkpoint.manifestTranscriptPointers manifest
    , testCase "non-product V1 remains inspectable but cannot refine to completed evidence" $
        withSystemTempDirectory "jitml-non-product-v1-admission" $ \root -> do
          fixture <-
            expectRight
              =<< makeV1Fixture "DQN/cartpole" (Just "non-product-v1-experiment")
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
    , isolatedCheckpointWriterCase
        "generic completed V1 writer cannot create an admitted ProductRow completion without a companion"
        $ withSystemTempDirectory "jitml-product-v1-generic-writer"
        $ \cacheRoot -> do
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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
          fixture <- expectRight =<< makeV1Fixture "mnist-shallow-mlp" Nothing
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
              =<< makeV1Fixture "DQN/cartpole" (Just "legacy-unscoped-v1-experiment")
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
    , isolatedCheckpointWriterCase
        "tampered transcript bytes violate commit-bound Product V1 re-admission"
        $ withSystemTempDirectory "jitml-product-v1-transcript-tamper"
        $ \cacheRoot -> do
          fixture <- expectRight =<< makeV1Fixture "DQN/cartpole" Nothing
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

-- | Build the V1 admission fixture.
--
-- The completion now requires a device execution witness, and a witness cannot
-- be constructed purely, so the fixture mints one over a real on-disk artifact
-- before assembling the manifest.
makeV1Fixture :: Text -> Maybe Text -> IO (Either Text V1Fixture)
makeV1Fixture rowId experimentOverride = do
  witnessResult <-
    case ProductMatrix.rowClass <$> find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows of
      Just (ProductMatrix.SupervisedClassification _ _) ->
        DeviceWitnessFixture.fixtureClassificationDeviceExecutionWitnessFor LinuxCPU
      _ -> DeviceWitnessFixture.fixtureDeviceExecutionWitness
  pure (witnessResult >>= \deviceWitness -> makeV1FixtureWith deviceWitness rowId experimentOverride)

makeV1FixtureWith
  :: DeviceWitness.DeviceExecutionWitness
  -> Text
  -> Maybe Text
  -> Either Text V1Fixture
makeV1FixtureWith deviceWitness rowId experimentOverride = do
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
      (Just deviceWitness)
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
rlProjectionForRowId = rlProjectionForRowIdIn LinuxCPU

rlProjectionForRowIdIn
  :: Substrate
  -> Text
  -> Either Text (ProductMatrix.ProductProjection 'Plan.ReinforcementLearning)
rlProjectionForRowIdIn lane rowId = do
  row <-
    maybe
      (Left ("missing canonical RL ProductRow " <> rowId))
      Right
      (find ((== rowId) . ProductMatrix.rowId) ProductMatrix.allProductRows)
  case ProductMatrix.projectProductRow lane row of
    Plan.Success
      ( ProductMatrix.SomeProductProjection
          Plan.ReinforcementLearningWitness
          projection
        ) -> Right projection
    Plan.Success _ -> Left ("ProductRow is not RL: " <> rowId)
    Plan.Failure errors ->
      Left ("ProductRow projection failed: " <> Text.pack (show errors))

-- Reconstruct the previous semantic plan through the public raw boundary.
-- This pins no numerical fixture or opaque SHA literal: only the new recipe
-- field is removed, and every other observed plan input is retained.
preNormalizationTrpoPlanId
  :: ProductMatrix.ProductProjection 'Plan.ReinforcementLearning
  -> Either Text Plan.PlanId
preNormalizationTrpoPlanId = withoutRlRecipeFields [("numerical-recipe", PpoTrainer.trpoFisherNumericalContract)]

preDeviceOnPolicyPlanId
  :: ProductMatrix.ProductProjection 'Plan.ReinforcementLearning
  -> Either Text Plan.PlanId
preDeviceOnPolicyPlanId =
  withoutRlRecipeFields
    [ ("evaluation-recipe", PpoTrainer.onPolicyEvaluationContract)
    , ("rollout-recipe", PpoTrainer.onPolicyRolloutContract)
    ]

withoutRlRecipeFields
  :: [(Text, Text)]
  -> ProductMatrix.ProductProjection 'Plan.ReinforcementLearning
  -> Either Text Plan.PlanId
withoutRlRecipeFields recipes projection = do
  let plan = ProductMatrix.productProjectionRunPlan projection
      field value = Text.pack (show (Text.length value)) <> ":" <> value <> "|"
      fields = [field key <> field value | (key, value) <- recipes]
      recipeFields = Text.concat fields
      subject = Plan.runPlanSubjectId plan
      (transitions, rollout, environments, horizon, episodes) = Plan.runPlanRlBudget plan
      units = toInteger . Plan.quantityValue
  if all (\recipe -> Text.count recipe subject == 1) fields
    then Right ()
    else Left "projection does not carry exactly one occurrence of each required recipe field"
  legacy <-
    case Plan.resolveRun
      Plan.RawRunRequest
        { Plan.rawRunVersion = Plan.runPlanVersion plan
        , Plan.rawRunKind = Plan.ReinforcementLearningWitness
        , Plan.rawRunExperimentId = Plan.runPlanExperimentId plan
        , Plan.rawRunSubjectId = Text.replace recipeFields "" subject
        , Plan.rawRunArtifactId = Plan.runPlanArtifactId plan
        , Plan.rawRunTopicId = Plan.runPlanTopicId plan
        , Plan.rawRunSubstrate = Plan.runPlanSubstrate plan
        , Plan.rawRunPlacement = Plan.runPlanPlacement plan
        , Plan.rawRunSeeds = NonEmpty.toList (Plan.seedCohortValues (Plan.runPlanSeeds plan))
        , Plan.rawRunBudget =
            Plan.RawRlBudget
              (units transitions)
              (units rollout)
              (units environments)
              (units horizon)
              (units episodes)
        } of
      Plan.Failure errors -> Left (Text.pack (show errors))
      Plan.Success resolved -> Right resolved
  Right (Plan.runPlanId legacy)

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

-- | The logical 'Checkpoint.ArtifactPointer' a publish receipt denotes.
receiptPointer :: ProductPublisher.ProductArtifactReceipt -> Checkpoint.ArtifactPointer
receiptPointer receipt =
  Checkpoint.ArtifactPointer
    { Checkpoint.artifactPointerKind = ProductPublisher.productArtifactKind receipt
    , Checkpoint.artifactPointerObjectKey = ProductPublisher.productArtifactObjectKey receipt
    , Checkpoint.artifactPointerSha = Just (ProductPublisher.productArtifactSha receipt)
    }
