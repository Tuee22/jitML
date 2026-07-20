{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent qualified
import Control.Concurrent.Async (AsyncCancelled (..))
import Control.Exception qualified
import Control.Exception.Safe qualified as SafeException
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Aeson (eitherDecode)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Bifunctor qualified as Bifunctor
import Data.Either (lefts)
import Data.Functor (void)
import Data.List qualified as List
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Unique (hashUnique, newUnique)
import Data.Word (Word32, Word64)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout qualified as Timeout
import Test.Tasty (TestTree, defaultMain, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import Data.ByteString.Lazy qualified as ByteString.Lazy
import Data.Foldable (for_, traverse_)
import Data.IORef (modifyIORef', newIORef, readIORef, writeIORef)
import Data.Text.Encoding qualified as Text.Encoding
import Data.Vector.Unboxed qualified as VU

import Data.ByteString qualified
import JitML.App qualified as App
import JitML.Bootstrap
  ( AppPodImagePollDecision (..)
  , KindClusterPresence (..)
  , LiveKindAction (..)
  , LiveStepFailure (..)
  , TopicStatsPollDecision (..)
  , appPodImageEvidenceMatchesLoadedImage
  , appPodImagePollDecision
  , appRolloutMatchesLoadedImage
  , bootstrapPlanSteps
  , hostBootConfigForPublication
  , livePhasedRolloutSubprocesses
  , materializeBootstrapFilesForPort
  , parseAppPodImageEvidence
  , parseContainerdImageListDigest
  , prepareLiveKindRecovery
  , publicReadyzSubprocessForPort
  , readExistingLivePublication
  , resolveKindClusterPresence
  , selectLiveKindRecovery
  , selectLiveLease
  , topicStatsPollDecision
  , uniformImageId
  )
import JitML.CLI.Output qualified as Output
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Cluster.DockerImage qualified as DockerImage
import JitML.Cluster.EdgePort qualified as EdgePort
import JitML.Cluster.Gateway qualified as Gateway
import JitML.Cluster.Helm qualified as Helm
import JitML.Cluster.Kind
  ( kindConfigFor
  , renderKindConfig
  )
import JitML.Cluster.PostgresRegistry qualified as PostgresRegistry
import JitML.Cluster.Publication qualified as Publication
import JitML.Cluster.PulsarBootstrap qualified as PulsarBootstrap
import JitML.Cluster.Readiness qualified as Readiness
import JitML.Cluster.Storage qualified as Storage
import JitML.Coordinator.Topology
  ( ProtocolRoute (..)
  , Topic
  , encodeTopicPayload
  , topicFor
  , topicName
  )
import JitML.Engines.CpuFeatures (CpuFeatures (..), detectCpuFeatures, microKernelChoice)
import JitML.Engines.CudaRuntime qualified as CudaRuntime
import JitML.Engines.Local qualified as Local
import JitML.Engines.MetalLocal qualified as MetalLocal
import JitML.Engines.MetalRuntime qualified as MetalRuntime
import JitML.Engines.OneDnnRuntime qualified as OneDnnRuntime
import JitML.Env.Build (buildEnv, defaultGlobalFlags)
import JitML.Env.Env (Env)
import JitML.Numerics.LayerGraph qualified as LayerGraph
import JitML.Numerics.Schema qualified as Numerics
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.ExternalBars qualified as ProductExternalBars
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Project.Config qualified as ProjectConfig
import JitML.RL.AlphaZero.PolicyValueNet qualified as PVN
import JitML.RL.AlphaZero.SelfPlay qualified as SelfPlay
import JitML.RL.ConvergenceThresholds
  ( ConvergenceThreshold (..)
  , cohortThreshold
  , passesConvergence
  )
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact

import JitML.Observability.TbSidecar qualified as TbSidecar
import JitML.Observability.TensorBoard qualified as TensorBoard
import JitML.Plan.Command qualified as PlanCommand
import JitML.Plan.Plan
  ( PlanId
  , Validation (..)
  , finiteMeasurementValue
  , planIdFromCanonicalText
  , planIdText
  , quantityValue
  , refinePlanIdText
  , runPlanExperimentId
  )
import JitML.Plan.Workload
  ( AlphaZeroPlan
  , SupervisedPlan
  , TuningPlan
  , alphaZeroPlanId
  , supervisedPlanId
  , tuningPlanId
  , tuningPlanParallelism
  , tuningPlanPerTrialUpdates
  , tuningPlanPromotions
  , tuningPlanRunPlan
  , tuningPlanTrials
  )
import JitML.Proto.Gc qualified as ProtoGc
import JitML.Proto.Rl qualified as ProtoRl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as ProtoTune
import JitML.RL.AsyncBuffer qualified as AsyncBuffer
import JitML.RL.Buffer qualified as Buffer
import JitML.Routes (renderHTTPRoute, renderRouteTable, routeRegistry)
import JitML.Run.Contract (finishContract, initialProgress)
import JitML.Run.Contract qualified as RunContract
import JitML.Run.WorkloadContract
  ( TuningCompletion (..)
  , TuningSweepCompletion (..)
  , alphaZeroCompletionContract
  , ingestAlphaZeroEvent
  , ingestTuneEvent
  , tuningCompletionContract
  )
import JitML.SL.Architecture qualified as SLArchitecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier (ClassifierConfig (..), defaultClassifierConfig)
import JitML.Service.BootConfig qualified as BootConfig
import JitML.Service.Capabilities
  ( BucketName (..)
  , ConsumerSessionEvent (..)
  , ETag (..)
  , HasHarbor (..)
  , HasMinIO (..)
  , HasPulsar (..)
  , ImageRef (..)
  , KubeResource (..)
  , NackReason (..)
  , ObjectKey (..)
  , ObjectRef (..)
  , Subscription
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , ack
  , continue
  , deliveryEvent
  , deliveryReceipt
  , deliveryReceiptFingerprint
  , deliveryRedeliveryCount
  , done
  , mkSubscription
  , nack
  )
import JitML.Service.Clients qualified as ServiceClients
import JitML.Service.ConfigMap qualified as ServiceConfigMap
import JitML.Service.Consumer
  ( DaemonCommand (..)
  , daemonCommandEventId
  , daemonSubscriptionName
  , daemonSubscriptionTopicName
  , daemonSubscriptionsForBootConfig
  , eventIdText
  )
import JitML.Service.FilesystemMinIO (runFilesystemMinIO)
import JitML.Service.HarborSubprocess qualified as HarborSubprocess
import JitML.Service.KubectlSubprocess (KubectlSettings (..), defaultKubectlSettings)
import JitML.Service.LiveConfig qualified as LiveConfig
import JitML.Service.MinIOSubprocess qualified as MinIOSubprocess
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Service.Workload qualified as Workload
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , processFailureExitCode
  , processFailureTranscript
  , renderProcessOutcome
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess, subprocessWithStdin)
import JitML.Sub.Subprocess qualified
import JitML.Substrate (Substrate (..))
import JitML.Test.LiveEvidence qualified as LiveEvidence
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.Report qualified as TestReport
import JitML.Test.WorkflowMatrix qualified as WorkflowMatrix
import JitML.Training.Budget qualified as TrainingBudget
import JitML.Tune.Catalog qualified as Tune
import JitML.Tune.Resume qualified as TuneResume
import Network.Socket qualified as Socket
import System.Directory (createDirectoryIfMissing, doesFileExist, listDirectory, makeAbsolute)
import System.FilePath ((</>))
import System.Info qualified as SystemInfo

-- | A completed legacy generic V1 fixture. Its non-supervised budget is
-- deliberate: a supervised completion budget categorically makes V1
-- inspection-only, while these fixtures own generic Store and engine coverage.
completedCheckpointManifest
  :: Text
  -> Text
  -> [Checkpoint.TensorBlob]
  -> Word64
  -> [(Text, Double)]
  -> Checkpoint.CheckpointManifest
completedCheckpointManifest =
  completedCheckpointManifestWithBudget
    TrainingBudget.RlEnvironmentStepBudget

completedCheckpointManifestWithBudget
  :: TrainingBudget.BudgetKind
  -> Text
  -> Text
  -> [Checkpoint.TensorBlob]
  -> Word64
  -> [(Text, Double)]
  -> Checkpoint.CheckpointManifest
completedCheckpointManifestWithBudget budgetKind manifestId experimentHash tensors step metrics =
  let evidence =
        either
          (error . Text.unpack)
          id
          ( ProductEvidence.mkTrainingEvidence
              ("integration-initial-" <> experimentHash)
              ("integration-final-" <> experimentHash <> "-" <> Text.pack (show step))
              (max 1 step)
              ("integration-dataset-" <> experimentHash)
          )
      observations =
        either
          (error . Text.unpack)
          id
          (convergenceObservationsFixture metrics)
      completed =
        either
          (error . Text.unpack)
          id
          ( TrainingBudget.completedTraining
              integrationFixturePlanId
              ( either
                  (error . Text.unpack)
                  id
                  ( TrainingBudget.mkTrainingBudget
                      budgetKind
                      (max 1 step)
                      Nothing
                  )
              )
              step
              evidence
              observations
              TrainingBudget.TensorBoardRunMetadata
                { TrainingBudget.tbrRunId = experimentHash
                , TrainingBudget.tbrLogPrefix = "jitml-tensorboard/" <> experimentHash
                , TrainingBudget.tbrScalarTags = fmap fst metrics
                }
          )
      manifest =
        (Checkpoint.emptyManifest manifestId experimentHash tensors)
          { Checkpoint.manifestStep = step
          , Checkpoint.manifestMetrics = metrics
          }
   in Checkpoint.attachCompletedTraining completed manifest

-- | Build one internally consistent legacy completed transaction. The exact
-- fetched JMW1 SHA is the tensor address and completed final-weight identity.
-- Store may persist/adopt it for inspection, but completed V1 admission is
-- reserved for canonical non-supervised ProductRow identities.
completedLegacySnapshotForPayload
  :: Text
  -> Text
  -> Text
  -> [Int]
  -> Word64
  -> [(Text, Double)]
  -> ByteString.Lazy.ByteString
  -> ( Checkpoint.CheckpointManifest
     , TrainingBudget.CompletedTraining
     , Text
     )
completedLegacySnapshotForPayload manifestId experimentHash tensorName shape step metrics payload =
  let finalWeightSha = WeightCodec.jmw1ContentSha payload
      blobObjectKey = Checkpoint.blobKey experimentHash finalWeightSha
      evidence =
        either
          (error . Text.unpack)
          id
          ( ProductEvidence.mkTrainingEvidence
              ("integration-initial-" <> experimentHash)
              finalWeightSha
              (max 1 step)
              ("integration-dataset-" <> experimentHash)
          )
      observations =
        either
          (error . Text.unpack)
          id
          (convergenceObservationsFixture metrics)
      completed =
        either
          (error . Text.unpack)
          id
          ( TrainingBudget.completedTraining
              integrationFixturePlanId
              ( either
                  (error . Text.unpack)
                  id
                  ( TrainingBudget.mkTrainingBudget
                      TrainingBudget.RlEnvironmentStepBudget
                      (max 1 step)
                      Nothing
                  )
              )
              step
              evidence
              observations
              TrainingBudget.TensorBoardRunMetadata
                { TrainingBudget.tbrRunId = experimentHash
                , TrainingBudget.tbrLogPrefix =
                    "jitml-tensorboard/" <> experimentHash
                , TrainingBudget.tbrScalarTags = fmap fst metrics
                }
          )
      manifest =
        ( Checkpoint.emptyManifest
            manifestId
            experimentHash
            [Checkpoint.TensorBlob tensorName shape blobObjectKey]
        )
          { Checkpoint.manifestStep = step
          , Checkpoint.manifestMetrics = metrics
          }
   in (Checkpoint.attachCompletedTraining completed manifest, completed, blobObjectKey)

integrationFixturePlanId :: PlanId
integrationFixturePlanId =
  either (error . Text.unpack) id (refinePlanIdText (Text.replicate 64 "d"))

convergenceObservationsFixture
  :: [(Text, Double)]
  -> Either Text [TrainingBudget.ConvergenceObservation]
convergenceObservationsFixture =
  ProductExternalBars.convergenceObservationsForMetrics

productRowIntegrationTest :: ProductMatrix.ProductRow 'ProductMatrix.Declared -> TestTree
productRowIntegrationTest row =
  testCase (Text.unpack (ProductMatrix.integrationTest row)) $ do
    evidence <- productRowIntegrationEvidence row
    TestReport.rowIntegrationCoverageFailures [row] [evidence] @?= []

assertProductRowIntegrationReportCoverage :: IO ()
assertProductRowIntegrationReportCoverage = do
  let rows = ProductMatrix.allProductRows
      evidence = fmap coverageFixtureRowReportEvidence rows
  case rows of
    [] -> assertFailure "ProductRow registry is unexpectedly empty"
    firstRow : _ -> do
      TestReport.rowIntegrationCoverageFailures rows evidence @?= []
      let firstEvidence = coverageFixtureRowReportEvidence firstRow
          missingEvidence =
            filter ((/= ProductMatrix.rowId firstRow) . TestReport.rieRowId) evidence
          missingFailures = TestReport.rowIntegrationCoverageFailures rows missingEvidence
          duplicateFailures =
            TestReport.rowIntegrationCoverageFailures rows (firstEvidence : evidence)
          orphan =
            firstEvidence
              { TestReport.rieRowId = "orphan-row"
              , TestReport.rieIntegrationTest = "integration.product.orphan-row"
              }
          orphanFailures = TestReport.rowIntegrationCoverageFailures rows (orphan : evidence)
      assertBool
        "missing coverage failure names the row id"
        ( any
            ( ( "missing integration evidence: rowId="
                  <> ProductMatrix.rowId firstRow
              )
                `Text.isInfixOf`
            )
            missingFailures
        )
      assertBool
        "missing coverage failure names the test id"
        ( any
            (ProductMatrix.integrationTest firstRow `Text.isInfixOf`)
            missingFailures
        )
      assertBool
        "duplicate coverage is rejected"
        (any ("duplicate integration evidence:" `Text.isPrefixOf`) duplicateFailures)
      assertBool
        "orphan coverage is rejected"
        (any ("orphan integration evidence: rowId=orphan-row" `Text.isPrefixOf`) orphanFailures)

data ExpectedProductRowInventory = ExpectedProductRowInventory
  { expectedInventoryRowId :: !Text
  , expectedInventoryFamily :: !ProductMatrix.RowFamily
  , expectedInventoryExperimentHash :: !Text
  , expectedInventoryPlanId :: !PlanId
  }
  deriving stock (Eq, Show)

-- | This projection is deliberately constructible only from Store's opaque
-- admitted-completed value. Store admission has therefore already re-read and
-- hash-checked every physical transcript object named by the manifest before
-- this independent inventory layer checks its ProductRow association.
data AdmittedProductRowInventory = AdmittedProductRowInventory
  { admittedInventoryRowId :: !Text
  , admittedInventoryExperimentHash :: !Text
  , admittedInventoryManifestPlanId :: !(Maybe PlanId)
  , admittedInventoryCompletedPlanId :: !PlanId
  , admittedInventoryManifestSha :: !Text
  , admittedInventoryManifestBodySha :: !(Maybe Text)
  , admittedInventoryReplayPointers :: ![Checkpoint.ArtifactPointer]
  , admittedInventoryTranscriptPointers :: ![Checkpoint.ArtifactPointer]
  , admittedInventoryRuntimePayload :: !(Maybe RuntimeArtifact.RawSupervisedRuntimePayload)
  , admittedInventoryDatasetShaAtRead :: !Text
  , admittedInventoryInitialJmw1Sha :: !Text
  , admittedInventoryFinalJmw1Sha :: !Text
  }
  deriving stock (Eq, Show)

data LoadedAdmittedProductRowCheckpoint = LoadedAdmittedProductRowCheckpoint
  { loadedProductManifestSha :: !Text
  , loadedProductAdmittedCheckpoint :: !CheckpointStore.AdmittedCheckpoint
  , loadedProductAdmittedCompleted :: !CheckpointStore.AdmittedCompletedCheckpoint
  }

expectedProductRowInventory
  :: ProductMatrix.ProductRow state
  -> ProductMatrix.ProductProjection kind
  -> ExpectedProductRowInventory
expectedProductRowInventory row projection =
  ExpectedProductRowInventory
    { expectedInventoryRowId = ProductMatrix.rowId row
    , expectedInventoryFamily = ProductMatrix.family row
    , expectedInventoryExperimentHash =
        ProductMatrix.productProjectionExperimentHash projection
    , expectedInventoryPlanId = ProductMatrix.productProjectionPlanId projection
    }

admittedProductRowInventory
  :: ProductMatrix.ProductRow state
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> AdmittedProductRowInventory
admittedProductRowInventory row admittedCompleted =
  let admittedCheckpoint =
        CheckpointStore.admittedCompletedCheckpoint admittedCompleted
      manifest = CheckpointStore.admittedCheckpointManifest admittedCheckpoint
      completed = CheckpointStore.admittedCompletedTraining admittedCompleted
   in AdmittedProductRowInventory
        { admittedInventoryRowId = ProductMatrix.rowId row
        , admittedInventoryExperimentHash = Checkpoint.manifestExperiment manifest
        , admittedInventoryManifestPlanId = Checkpoint.manifestPlanId manifest
        , admittedInventoryCompletedPlanId =
            TrainingBudget.completedTrainingPlanId completed
        , admittedInventoryManifestSha =
            CheckpointStore.admittedCheckpointManifestSha admittedCheckpoint
        , admittedInventoryManifestBodySha =
            CheckpointStore.admittedCheckpointManifestBodySha admittedCheckpoint
        , admittedInventoryReplayPointers = Checkpoint.manifestReplayPointers manifest
        , admittedInventoryTranscriptPointers =
            Checkpoint.manifestTranscriptPointers manifest
        , admittedInventoryRuntimePayload =
            RuntimeArtifact.supervisedRuntimePayloadToRaw
              <$> Checkpoint.manifestSupervisedRuntime manifest
        , admittedInventoryDatasetShaAtRead =
            TrainingBudget.completedTrainingDatasetShaAtRead completed
        , admittedInventoryInitialJmw1Sha =
            TrainingBudget.completedTrainingInitialWeightHash completed
        , admittedInventoryFinalJmw1Sha =
            TrainingBudget.completedTrainingFinalWeightHash completed
        }

admittedProductRowInventoryFailures
  :: ExpectedProductRowInventory
  -> AdmittedProductRowInventory
  -> [Text]
admittedProductRowInventoryFailures expected inventory =
  concat
    [ exactTextFailure
        "row id"
        (expectedInventoryRowId expected)
        (admittedInventoryRowId inventory)
    , exactTextFailure
        "manifest experiment hash"
        (expectedInventoryExperimentHash expected)
        (admittedInventoryExperimentHash inventory)
    , exactMaybePlanIdFailure
        "manifest PlanId"
        (expectedInventoryPlanId expected)
        (admittedInventoryManifestPlanId inventory)
    , exactPlanIdFailure
        "completed PlanId"
        (expectedInventoryPlanId expected)
        (admittedInventoryCompletedPlanId inventory)
    , canonicalShaFailures
        "manifest SHA"
        (admittedInventoryManifestSha inventory)
    , [ "orphan replay pointer inventory for row "
          <> expectedInventoryRowId expected
      | not (null (admittedInventoryReplayPointers inventory))
      ]
    , transcriptPointerFailures expected (admittedInventoryTranscriptPointers inventory)
    , runtimeInventoryFailures expected inventory
    ]

transcriptPointerFailures
  :: ExpectedProductRowInventory
  -> [Checkpoint.ArtifactPointer]
  -> [Text]
transcriptPointerFailures expected pointers =
  case expectedTranscriptKind (expectedInventoryFamily expected) of
    Nothing ->
      [ "orphan transcript pointer inventory for supervised row "
          <> expectedInventoryRowId expected
      | not (null pointers)
      ]
    Just expectedKind ->
      case pointers of
        [] ->
          [ "missing "
              <> expectedKind
              <> " transcript pointer for row "
              <> expectedInventoryRowId expected
          ]
        [pointer] -> transcriptPointerIdentityFailures expected expectedKind pointer
        _ ->
          [ "duplicate/multiple transcript pointers for row "
              <> expectedInventoryRowId expected
              <> ": expected exactly one "
              <> expectedKind
              <> ", got "
              <> Text.pack (show (length pointers))
          ]
            <> concatMap
              (transcriptPointerIdentityFailures expected expectedKind)
              pointers

transcriptPointerIdentityFailures
  :: ExpectedProductRowInventory
  -> Text
  -> Checkpoint.ArtifactPointer
  -> [Text]
transcriptPointerIdentityFailures expected expectedKind pointer =
  let rowId = expectedInventoryRowId expected
      experimentHash = expectedInventoryExperimentHash expected
      pointerKind = Checkpoint.artifactPointerKind pointer
      pointerKey = Checkpoint.artifactPointerObjectKey pointer
   in [ "substituted transcript pointer kind for row "
          <> rowId
          <> ": expected "
          <> expectedKind
          <> ", got "
          <> pointerKind
      | pointerKind /= expectedKind
      ]
        <> case Checkpoint.artifactPointerSha pointer of
          Nothing ->
            [ "missing exact transcript SHA for row " <> rowId
            ]
          Just pointerSha ->
            canonicalShaFailures ("transcript SHA for row " <> rowId) pointerSha
              <> [ "substituted/orphan transcript pointer key for row "
                     <> rowId
                     <> ": expected "
                     <> canonicalProductArtifactKey experimentHash expectedKind pointerSha
                     <> ", got "
                     <> pointerKey
                 | pointerKey
                     /= canonicalProductArtifactKey experimentHash expectedKind pointerSha
                 ]

runtimeInventoryFailures
  :: ExpectedProductRowInventory
  -> AdmittedProductRowInventory
  -> [Text]
runtimeInventoryFailures expected inventory =
  case expectedInventoryFamily expected of
    ProductMatrix.Supervised ->
      case admittedInventoryRuntimePayload inventory of
        Nothing ->
          [ "supervised row is missing its exact Product-origin V2 runtime: "
              <> expectedInventoryRowId expected
          ]
        Just payload ->
          [ "supervised Product-origin V2 manifest body SHA is absent for row "
              <> expectedInventoryRowId expected
          | isNothing (admittedInventoryManifestBodySha inventory)
          ]
            <> maybe
              []
              (canonicalShaFailures "supervised V2 manifest body SHA")
              (admittedInventoryManifestBodySha inventory)
            <> exactTextFailure
              "supervised V2 runtime row id"
              (expectedInventoryRowId expected)
              (RuntimeArtifact.rawRuntimePayloadRowId payload)
            <> [ "supervised V2 runtime does not have ProductRow projection origin for row "
                   <> expectedInventoryRowId expected
               | RuntimeArtifact.rawRuntimePayloadOrigin payload
                   /= RuntimeArtifact.RawProductRowProjectionOrigin
               ]
            <> exactTextFailure
              "supervised V2 runtime PlanId"
              (planIdText (expectedInventoryPlanId expected))
              (RuntimeArtifact.rawRuntimePayloadPlanId payload)
            <> exactTextFailure
              "supervised V2 runtime dataset SHA"
              (admittedInventoryDatasetShaAtRead inventory)
              (RuntimeArtifact.rawRuntimePayloadDatasetSha256 payload)
            <> exactTextFailure
              "supervised V2 runtime initial JMW1 SHA"
              (admittedInventoryInitialJmw1Sha inventory)
              (RuntimeArtifact.rawRuntimePayloadInitialJmw1Sha256 payload)
            <> exactTextFailure
              "supervised V2 runtime final JMW1 SHA"
              (admittedInventoryFinalJmw1Sha inventory)
              (RuntimeArtifact.rawRuntimePayloadFinalJmw1Sha256 payload)
    _ ->
      [ "non-supervised ProductRow unexpectedly carries a V2 supervised runtime: "
          <> expectedInventoryRowId expected
      | isJust (admittedInventoryRuntimePayload inventory)
      ]
        <> [ "non-supervised ProductRow is not the canonical V1 inventory shape: "
               <> expectedInventoryRowId expected
           | isJust (admittedInventoryManifestBodySha inventory)
           ]

expectedTranscriptKind :: ProductMatrix.RowFamily -> Maybe Text
expectedTranscriptKind family =
  case family of
    ProductMatrix.Supervised -> Nothing
    ProductMatrix.ReinforcementLearning -> Just "rl-trajectory"
    ProductMatrix.AlphaZero -> Just "alphazero-transcript"
    ProductMatrix.Tuning -> Just "tune-trials"

canonicalProductArtifactKey :: Text -> Text -> Text -> Text
canonicalProductArtifactKey experimentHash kind sha =
  "jitml-checkpoints/"
    <> experimentHash
    <> "/artifacts/"
    <> kind
    <> "/"
    <> sha
    <> ".txt"

canonicalShaFailures :: Text -> Text -> [Text]
canonicalShaFailures label sha =
  [ label <> " is not one canonical lowercase SHA-256: " <> sha
  | not (isCanonicalSha256 sha)
  ]

isCanonicalSha256 :: Text -> Bool
isCanonicalSha256 value =
  Text.length value == 64
    && Text.all (`elem` ("0123456789abcdef" :: String)) value

exactTextFailure :: Text -> Text -> Text -> [Text]
exactTextFailure label expected actual =
  [ label <> " mismatch: expected " <> expected <> ", got " <> actual
  | expected /= actual
  ]

exactPlanIdFailure :: Text -> PlanId -> PlanId -> [Text]
exactPlanIdFailure label expected actual =
  exactTextFailure label (planIdText expected) (planIdText actual)

exactMaybePlanIdFailure :: Text -> PlanId -> Maybe PlanId -> [Text]
exactMaybePlanIdFailure label expected actual =
  case actual of
    Nothing -> [label <> " is missing"]
    Just actualPlanId -> exactPlanIdFailure label expected actualPlanId

productRowInventoryAggregateFailures
  :: [ExpectedProductRowInventory]
  -> [AdmittedProductRowInventory]
  -> [Text]
productRowInventoryAggregateFailures expectedEntries inventoryEntries =
  [ "admitted ProductRow inventory count mismatch: expected "
      <> Text.pack (show (length expectedEntries))
      <> ", got "
      <> Text.pack (show (length inventoryEntries))
  | length inventoryEntries /= length expectedEntries
  ]
    <> duplicateInventoryFailures
      "row id"
      (fmap admittedInventoryRowId inventoryEntries)
    <> duplicateInventoryFailures
      "experiment hash"
      (fmap admittedInventoryExperimentHash inventoryEntries)
    <> duplicateInventoryFailures
      "manifest PlanId"
      ( fmap
          (maybe "<missing>" planIdText . admittedInventoryManifestPlanId)
          inventoryEntries
      )
    <> duplicateInventoryFailures
      "manifest SHA"
      (fmap admittedInventoryManifestSha inventoryEntries)
    <> duplicateInventoryFailures
      "transcript pointer object key"
      [ Checkpoint.artifactPointerObjectKey pointer
      | inventory <- inventoryEntries
      , pointer <- admittedInventoryTranscriptPointers inventory
      ]
    <> [ "orphan admitted ProductRow inventory row: "
           <> admittedInventoryRowId inventory
       | inventory <- inventoryEntries
       , admittedInventoryRowId inventory `notElem` expectedRowIds
       ]
    <> concatMap exactRowFailures expectedEntries
 where
  expectedRowIds = fmap expectedInventoryRowId expectedEntries

  exactRowFailures expected =
    case filter
      ((== expectedInventoryRowId expected) . admittedInventoryRowId)
      inventoryEntries of
      [] ->
        [ "missing admitted ProductRow inventory row: "
            <> expectedInventoryRowId expected
        ]
      [inventory] -> admittedProductRowInventoryFailures expected inventory
      duplicates ->
        [ "duplicate admitted ProductRow inventory rows for "
            <> expectedInventoryRowId expected
            <> ": "
            <> Text.pack (show (length duplicates))
        ]

duplicateInventoryFailures :: Text -> [Text] -> [Text]
duplicateInventoryFailures label values =
  [ "duplicate admitted ProductRow inventory " <> label <> ": " <> value
  | value <- List.nub values
  , length (filter (== value) values) > 1
  ]

loadAdmittedProductRowCheckpoint
  :: FilePath
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> IO LoadedAdmittedProductRowCheckpoint
loadAdmittedProductRowCheckpoint checkpointRoot row = do
  let rowId = ProductMatrix.rowId row
      experimentHash = ProductMatrix.productRowExperimentHash row
      pointerKey = Checkpoint.latestPointerKey experimentHash
  pointerResult <- CheckpointStore.readCheckpointPointer checkpointRoot pointerKey
  manifestSha <-
    case pointerResult of
      Left err ->
        assertFailure
          ( "ProductRow checkpoint pointer read failed for "
              <> Text.unpack rowId
              <> ": "
              <> Text.unpack err
          )
      Right Nothing ->
        assertFailure
          ( "missing published ProductRow checkpoint pointer for "
              <> Text.unpack rowId
              <> " at "
              <> (checkpointRoot </> Text.unpack pointerKey)
              <> "; run `jitml internal train-and-publish-product-rows --linux-cpu` first"
          )
      Right (Just sha) -> pure sha
  admittedCheckpoint <-
    CheckpointStore.admitLocalCheckpointAt checkpointRoot experimentHash manifestSha
      >>= \case
        Left err ->
          assertFailure
            ( "ProductRow checkpoint Store admission failed for "
                <> Text.unpack rowId
                <> ": "
                <> Text.unpack (CheckpointStore.renderCheckpointAdmissionError err)
            )
        Right admitted -> pure admitted
  admittedCompleted <-
    case CheckpointStore.requireAdmittedCompletedCheckpoint admittedCheckpoint of
      Left err ->
        assertFailure
          ( "ProductRow checkpoint completed Store admission failed for "
              <> Text.unpack rowId
              <> ": "
              <> Text.unpack (CheckpointStore.renderCheckpointAdmissionError err)
          )
      Right admitted -> pure admitted
  pure
    LoadedAdmittedProductRowCheckpoint
      { loadedProductManifestSha = manifestSha
      , loadedProductAdmittedCheckpoint = admittedCheckpoint
      , loadedProductAdmittedCompleted = admittedCompleted
      }

assertAdmittedProductRowInventory
  :: FilePath
  -> ExpectedProductRowInventory
  -> AdmittedProductRowInventory
  -> Assertion
assertAdmittedProductRowInventory checkpointRoot expected inventory = do
  case admittedProductRowInventoryFailures expected inventory of
    [] -> pure ()
    failures ->
      assertFailure
        ( "admitted ProductRow inventory failed for "
            <> Text.unpack (expectedInventoryRowId expected)
            <> ":\n"
            <> Text.unpack (Text.unlines (fmap ("- " <>) failures))
        )
  case expectedInventoryFamily expected of
    ProductMatrix.Tuning ->
      case admittedInventoryTranscriptPointers inventory of
        [pointer] -> assertCanonicalTuneV2Transcript checkpointRoot expected inventory pointer
        pointers ->
          assertFailure
            ( "validated tuning inventory did not retain exactly one pointer: "
                <> show pointers
            )
    _ -> pure ()

assertCanonicalTuneV2Transcript
  :: FilePath
  -> ExpectedProductRowInventory
  -> AdmittedProductRowInventory
  -> Checkpoint.ArtifactPointer
  -> Assertion
assertCanonicalTuneV2Transcript checkpointRoot expected inventory pointer = do
  payload <-
    CheckpointStore.readObject
      checkpointRoot
      (Checkpoint.artifactPointerObjectKey pointer)
      >>= \case
        Left err ->
          assertFailure
            ( "independent tuning transcript read failed for "
                <> Text.unpack (expectedInventoryRowId expected)
                <> ": "
                <> Text.unpack err
            )
        Right bytes -> pure bytes
  case Checkpoint.artifactPointerSha pointer of
    Nothing -> assertFailure "validated tuning transcript pointer lost its exact SHA"
    Just expectedSha -> WeightCodec.jmw1ContentSha payload @?= expectedSha
  transcript <-
    case Text.Encoding.decodeUtf8' (ByteString.Lazy.toStrict payload) of
      Left err ->
        assertFailure
          ("tuning v2 transcript is not UTF-8: " <> show err)
      Right value -> pure value
  let expectedHeaders =
        [ "kind: tune-trials-v2"
        , "row-id: " <> expectedInventoryRowId expected
        , "plan-id: " <> planIdText (expectedInventoryPlanId expected)
        , "experiment-hash: " <> expectedInventoryExperimentHash expected
        , "dataset-sha-at-read: " <> admittedInventoryDatasetShaAtRead inventory
        , "best-final-jmw1-sha: " <> admittedInventoryFinalJmw1Sha inventory
        ]
      transcriptLines = Text.lines transcript
  take (length expectedHeaders) transcriptLines @?= expectedHeaders
  for_ expectedHeaders $ \header ->
    length (filter (== header) transcriptLines) @?= 1

assertProductRowAdmittedInventory :: Assertion
assertProductRowAdmittedInventory = do
  checkpointRoot <- makeAbsolute (".build" </> "checkpoints")
  let rows = ProductMatrix.allProductRows
  ProductMatrix.productRowCount @?= 55
  length rows @?= 55
  expectedAndInventory <-
    traverse
      ( \row -> do
          projection <-
            case ProductMatrix.projectProductRow LinuxCPU row of
              Failure errors ->
                assertFailure
                  ( "ProductRow LinuxCPU inventory projection failed for "
                      <> Text.unpack (ProductMatrix.rowId row)
                      <> ": "
                      <> show errors
                  )
              Success value -> pure value
          case projection of
            ProductMatrix.SomeProductProjection _witness exactProjection -> do
              loaded <- loadAdmittedProductRowCheckpoint checkpointRoot row
              let expected = expectedProductRowInventory row exactProjection
                  inventory =
                    admittedProductRowInventory
                      row
                      (loadedProductAdmittedCompleted loaded)
              assertAdmittedProductRowInventory checkpointRoot expected inventory
              pure (expected, inventory)
      )
      rows
  let expectedEntries = fmap fst expectedAndInventory
      inventoryEntries = fmap snd expectedAndInventory
      transcriptPointers =
        concatMap admittedInventoryTranscriptPointers inventoryEntries
      familyCount family =
        length (filter ((== family) . expectedInventoryFamily) expectedEntries)
  case productRowInventoryAggregateFailures expectedEntries inventoryEntries of
    [] -> pure ()
    failures ->
      assertFailure
        ( "full ProductRow admitted inventory audit failed:\n"
            <> Text.unpack (Text.unlines (fmap ("- " <>) failures))
        )
  fmap
    familyCount
    [ ProductMatrix.Supervised
    , ProductMatrix.ReinforcementLearning
    , ProductMatrix.AlphaZero
    , ProductMatrix.Tuning
    ]
    @?= [11, 39, 4, 1]
  length transcriptPointers @?= 44
  length (List.nub (fmap Checkpoint.artifactPointerObjectKey transcriptPointers))
    @?= 44
  assertInventoryNegativeCases expectedEntries inventoryEntries

assertInventoryNegativeCases
  :: [ExpectedProductRowInventory]
  -> [AdmittedProductRowInventory]
  -> Assertion
assertInventoryNegativeCases expectedEntries inventoryEntries = do
  (nonSupervisedExpected, nonSupervisedInventory, pointer) <-
    case [ (expected, inventory, exactPointer)
         | (expected, inventory) <- zip expectedEntries inventoryEntries
         , expectedInventoryFamily expected /= ProductMatrix.Supervised
         , [exactPointer] <- [admittedInventoryTranscriptPointers inventory]
         ] of
      [] -> assertFailure "full inventory has no non-supervised transcript pointer fixture"
      fixture : _ -> pure fixture
  (supervisedExpected, supervisedInventory) <-
    case [ (expected, inventory)
         | (expected, inventory) <- zip expectedEntries inventoryEntries
         , expectedInventoryFamily expected == ProductMatrix.Supervised
         ] of
      [] -> assertFailure "full inventory has no supervised pointer-free fixture"
      fixture : _ -> pure fixture
  assertInventoryFailureContains
    "missing"
    ( admittedProductRowInventoryFailures
        nonSupervisedExpected
        nonSupervisedInventory
          { admittedInventoryTranscriptPointers = []
          }
    )
  assertInventoryFailureContains
    "duplicate/multiple"
    ( admittedProductRowInventoryFailures
        nonSupervisedExpected
        nonSupervisedInventory
          { admittedInventoryTranscriptPointers = [pointer, pointer]
          }
    )
  assertInventoryFailureContains
    "substituted/orphan"
    ( admittedProductRowInventoryFailures
        nonSupervisedExpected
        nonSupervisedInventory
          { admittedInventoryTranscriptPointers =
              [ pointer
                  { Checkpoint.artifactPointerObjectKey =
                      "jitml-checkpoints/substituted/artifacts/foreign/deadbeef.txt"
                  }
              ]
          }
    )
  assertInventoryFailureContains
    "orphan"
    ( admittedProductRowInventoryFailures
        supervisedExpected
        supervisedInventory
          { admittedInventoryTranscriptPointers = [pointer]
          }
    )
  let orphanInventory =
        nonSupervisedInventory
          { admittedInventoryRowId = "orphan-row"
          }
  assertInventoryFailureContains
    "orphan admitted ProductRow inventory row"
    ( productRowInventoryAggregateFailures
        expectedEntries
        (inventoryEntries <> [orphanInventory])
    )

assertInventoryFailureContains :: Text -> [Text] -> Assertion
assertInventoryFailureContains expected failures =
  assertBool
    ( "expected inventory rejection containing "
        <> Text.unpack expected
        <> ", got "
        <> show failures
    )
    (any (expected `Text.isInfixOf`) failures)

productRowIntegrationEvidence
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> IO TestReport.RowIntegrationEvidence
productRowIntegrationEvidence row = do
  checkpointRoot <- makeAbsolute (".build" </> "checkpoints")
  let rowId = ProductMatrix.rowId row
      integrationId = ProductMatrix.integrationTest row
      experimentHash = ProductMatrix.productRowExperimentHash row
  loaded <- loadAdmittedProductRowCheckpoint checkpointRoot row
  let manifestSha = loadedProductManifestSha loaded
      admittedCheckpoint = loadedProductAdmittedCheckpoint loaded
      admittedCompleted = loadedProductAdmittedCompleted loaded
  let manifestFromStore =
        CheckpointStore.admittedCheckpointManifest admittedCheckpoint
  Checkpoint.manifestExperiment manifestFromStore @?= experimentHash
  CheckpointStore.admittedCheckpointManifestSha admittedCheckpoint @?= manifestSha
  let completed = CheckpointStore.admittedCompletedTraining admittedCompleted
      completedMetrics = TrainingBudget.completedTrainingMetrics completed
      rejectedBeforeCompletion =
        case Checkpoint.validateCheckpointCompletion beforeCompletionManifest of
          Left Checkpoint.MissingCompletedTraining -> True
          Left _ -> True
          Right _ -> False
      beforeCompletionManifest =
        manifestFromStore
          { Checkpoint.manifestCompletedTraining = Nothing
          }
  projection <-
    case ProductMatrix.projectProductRow LinuxCPU row of
      Failure errors ->
        assertFailure
          ( "ProductRow LinuxCPU projection failed for "
              <> Text.unpack rowId
              <> ": "
              <> show errors
          )
      Success projected -> pure projected
  case projection of
    ProductMatrix.SomeProductProjection _witness exactProjection -> do
      let expectedInventory = expectedProductRowInventory row exactProjection
          inventory = admittedProductRowInventory row admittedCompleted
      assertAdmittedProductRowInventory checkpointRoot expectedInventory inventory
      TrainingBudget.completedTrainingPlanId completed
        @?= ProductMatrix.productProjectionPlanId exactProjection
      case App.validateProductCompletedTrainingPlanId exactProjection completed of
        Left err ->
          assertFailure
            ( "persisted CompletedTraining did not match the projected ProductRow PlanId for "
                <> Text.unpack rowId
                <> ": "
                <> Text.unpack err
            )
        Right () -> pure ()
      case TestReport.productScenarioCompletion exactProjection admittedCompleted of
        Left errors ->
          assertFailure
            ( "persisted CompletedTraining did not satisfy the exact ProductRow completion contract for "
                <> Text.unpack rowId
                <> ": "
                <> show errors
            )
        Right _completion -> pure ()
      wrongCompleted <-
        case TrainingBudget.completedTraining
          (wrongProductPlanId (ProductMatrix.productProjectionPlanId exactProjection))
          (TrainingBudget.completedTrainingBudget completed)
          (TrainingBudget.completedTrainingObservedUnits completed)
          (TrainingBudget.completedTrainingEvidence completed)
          completedMetrics
          (TrainingBudget.completedTrainingTensorBoard completed) of
          Left err -> assertFailure ("could not construct wrong-plan completion fixture: " <> Text.unpack err)
          Right value -> pure value
      case App.validateProductCompletedTrainingPlanId exactProjection wrongCompleted of
        Left err ->
          assertBool
            "wrong/stale persisted ProductRow PlanIds are rejected"
            ("PlanId" `Text.isInfixOf` err && "mismatch" `Text.isInfixOf` err)
        Right () -> assertFailure "wrong/stale persisted ProductRow PlanId was accepted"
  pure
    TestReport.RowIntegrationEvidence
      { TestReport.rieRowId = rowId
      , TestReport.rieIntegrationTest = integrationId
      , TestReport.rieFamily = renderProductRowFamily (ProductMatrix.family row)
      , TestReport.rieInitialParamHash =
          TrainingBudget.completedTrainingInitialWeightHash completed
      , TestReport.rieFinalParamHash =
          TrainingBudget.completedTrainingFinalWeightHash completed
      , TestReport.rieUpdateCount =
          TrainingBudget.completedTrainingUpdateCount completed
      , TestReport.rieObservedUnits =
          TrainingBudget.completedTrainingObservedUnits completed
      , TestReport.rieCompletedMetricNames =
          fmap TrainingBudget.coMetricName completedMetrics
      , TestReport.rieCompletedTrainingPassed =
          all TrainingBudget.convergencePassed completedMetrics
      , TestReport.rieDatasetShaAtRead =
          TrainingBudget.completedTrainingDatasetShaAtRead completed
      , TestReport.rieManifestSha = manifestSha
      , TestReport.rieRejectedBeforeCompletion = rejectedBeforeCompletion
      }

wrongProductPlanId :: PlanId -> PlanId
wrongProductPlanId expected =
  if candidateD /= expected then candidateD else candidateE
 where
  candidateD = either (error . Text.unpack) id (refinePlanIdText (Text.replicate 64 "d"))
  candidateE = either (error . Text.unpack) id (refinePlanIdText (Text.replicate 64 "e"))

coverageFixtureRowReportEvidence
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> TestReport.RowIntegrationEvidence
coverageFixtureRowReportEvidence row =
  TestReport.RowIntegrationEvidence
    { TestReport.rieRowId = ProductMatrix.rowId row
    , TestReport.rieIntegrationTest = ProductMatrix.integrationTest row
    , TestReport.rieFamily = renderProductRowFamily (ProductMatrix.family row)
    , TestReport.rieInitialParamHash = "coverage-fixture-initial:" <> ProductMatrix.rowId row
    , TestReport.rieFinalParamHash = "coverage-fixture-final:" <> ProductMatrix.rowId row
    , TestReport.rieUpdateCount = max 1 (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row))
    , TestReport.rieObservedUnits =
        max 1 (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget row))
    , TestReport.rieCompletedMetricNames = ["coverage_fixture_metric"]
    , TestReport.rieCompletedTrainingPassed = True
    , TestReport.rieDatasetShaAtRead = "coverage-fixture-dataset:" <> ProductMatrix.rowId row
    , TestReport.rieManifestSha =
        "coverage-fixture-manifest:" <> ProductMatrix.productRowExperimentHash row
    , TestReport.rieRejectedBeforeCompletion = True
    }

renderProductRowFamily :: ProductMatrix.RowFamily -> Text
renderProductRowFamily family =
  case family of
    ProductMatrix.Supervised -> "Supervised"
    ProductMatrix.ReinforcementLearning -> "ReinforcementLearning"
    ProductMatrix.AlphaZero -> "AlphaZero"
    ProductMatrix.Tuning -> "Tuning"

data ProcessStream
  = ProcessStdout
  | ProcessStderr

assertProcessExitCode :: String -> ExitCode -> ProcessOutcome -> Assertion
assertProcessExitCode label expected outcome
  | processExitCode outcome == expected = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected exit "
            <> show expected
            <> ", got:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

assertProcessNotSuccessful :: String -> ProcessOutcome -> Assertion
assertProcessNotSuccessful label outcome
  | processExitCode outcome /= ExitSuccess = pure ()
  | otherwise =
      assertFailure
        (label <> ": expected a non-zero exit, got:\n" <> Text.unpack (renderProcessOutcome outcome))

assertProcessStreamEquals :: String -> ProcessStream -> Text -> ProcessOutcome -> Assertion
assertProcessStreamEquals label stream expected outcome
  | processStream stream outcome == expected = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected "
            <> streamLabel stream
            <> " "
            <> show expected
            <> ", got:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

assertProcessStreamContains :: String -> ProcessStream -> Text -> ProcessOutcome -> Assertion
assertProcessStreamContains label stream needle outcome
  | needle `Text.isInfixOf` processStream stream outcome = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected "
            <> streamLabel stream
            <> " to contain "
            <> show needle
            <> ", got:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

assertProcessStreamNotContains :: String -> ProcessStream -> Text -> ProcessOutcome -> Assertion
assertProcessStreamNotContains label stream needle outcome
  | not (needle `Text.isInfixOf` processStream stream outcome) = pure ()
  | otherwise =
      assertFailure
        ( label
            <> ": expected "
            <> streamLabel stream
            <> " not to contain "
            <> show needle
            <> ", got:\n"
            <> Text.unpack (renderProcessOutcome outcome)
        )

requireProcessSuccess :: String -> ProcessOutcome -> IO ProcessTranscript
requireProcessSuccess _ (ProcessSucceeded transcript) = pure transcript
requireProcessSuccess label outcome@(ProcessFailed failure) = do
  _ <- assertFailure (label <> ":\n" <> Text.unpack (renderProcessOutcome outcome))
  pure (processFailureTranscript failure)

renderHelmLiveConfigChecksums
  :: FilePath
  -> FilePath
  -> Text
  -> IO [Text]
renderHelmLiveConfigChecksums sourceChart probeChart replacementLatency = do
  let probeTemplates = probeChart </> "templates"
      renderSourceFile relativePath =
        Text.IO.readFile (sourceChart </> relativePath)
      writeProbeFile relativePath =
        Text.IO.writeFile (probeChart </> relativePath)
  createDirectoryIfMissing True probeTemplates
  chartYaml <- renderSourceFile "Chart.yaml"
  valuesYaml <- renderSourceFile "values.yaml"
  deployment <- renderSourceFile ("templates" </> "deployment.yaml")
  configMap <- renderSourceFile ("templates" </> "configmap.yaml")
  let changedConfigMap =
        Text.replace
          "inferenceMaxLatencyMillis = 5000"
          ("inferenceMaxLatencyMillis = " <> replacementLatency)
          configMap
  assertBool
    "checksum probe must replace at least one LiveConfig latency value"
    (changedConfigMap /= configMap || replacementLatency == "5000")
  writeProbeFile "Chart.yaml" chartYaml
  writeProbeFile "values.yaml" valuesYaml
  writeProbeFile ("templates" </> "deployment.yaml") deployment
  writeProbeFile ("templates" </> "configmap.yaml") changedConfigMap
  outcome <-
    runStreaming
      defaultSubprocessEnv
      (subprocess "helm" ["template", "checksum-probe", Text.pack probeChart])
  transcript <- requireProcessSuccess "render Helm LiveConfig checksum probe" outcome
  pure (liveConfigChecksumValues (processTranscriptStdout transcript))

liveConfigChecksumValues :: Text -> [Text]
liveConfigChecksumValues rendered =
  fmap
    ( Text.dropAround (== '"')
        . Text.strip
        . Text.drop (Text.length liveConfigChecksumPrefix)
        . Text.strip
    )
    (filter (Text.isPrefixOf liveConfigChecksumPrefix . Text.strip) (Text.lines rendered))
 where
  liveConfigChecksumPrefix = "checksum/live-config:"

processExitCode :: ProcessOutcome -> ExitCode
processExitCode (ProcessSucceeded _) = ExitSuccess
processExitCode (ProcessFailed failure) = processFailureExitCode failure

processTranscript :: ProcessOutcome -> ProcessTranscript
processTranscript (ProcessSucceeded transcript) = transcript
processTranscript (ProcessFailed failure) = processFailureTranscript failure

processStream :: ProcessStream -> ProcessOutcome -> Text
processStream ProcessStdout = processTranscriptStdout . processTranscript
processStream ProcessStderr = processTranscriptStderr . processTranscript

streamLabel :: ProcessStream -> String
streamLabel ProcessStdout = "stdout"
streamLabel ProcessStderr = "stderr"

topologyTopic :: ProtocolRoute event -> Substrate -> Topic event
topologyTopic route substrate =
  case topicFor route substrate of
    Left err -> error ("integration topology invariant failed: " <> show err)
    Right topic -> topic

topologySubscription :: ProtocolRoute event -> Substrate -> Text -> (Text, Text)
topologySubscription route substrate subscriptionName =
  (topicName (topologyTopic route substrate), subscriptionName)

subscriptionFixture
  :: Topic event
  -> Text
  -> SubscriptionStart
  -> SubscriptionOwnership
  -> Subscription event
subscriptionFixture topic name start ownership =
  case mkSubscription topic name start ownership of
    Left err -> error ("invalid integration subscription fixture: " <> show err)
    Right subscription -> subscription

-- | A synchronous scenario failure and every typed cleanup failure remain
-- visible together.  When cleanup succeeds, the original exception is
-- rethrown unchanged.  This is the assertion-level counterpart to
-- 'LiveWorkflow.withOwnedCleanup' for live fixtures that do not themselves
-- produce a typed workflow result.  An asynchronous primary is never wrapped;
-- concurrent cleanup issues go to an explicit observer before the exact async
-- exception is rethrown.
data OwnedScenarioCleanupFailure = OwnedScenarioCleanupFailure
  { ownedScenarioLabel :: Text
  , ownedScenarioPrimary :: Maybe Control.Exception.SomeException
  , ownedScenarioCleanupIssues :: [LiveWorkflow.CleanupIssue]
  }

instance Show OwnedScenarioCleanupFailure where
  show failure =
    Text.unpack
      ( Text.unlines
          ( [ownedScenarioLabel failure <> " owned-resource cleanup failed"]
              <> maybe
                []
                (\primary -> ["primary failure: " <> Text.pack (show primary)])
                (ownedScenarioPrimary failure)
              <> fmap
                (\issue -> "cleanup failure: " <> LiveWorkflow.unCleanupIssue issue)
                (ownedScenarioCleanupIssues failure)
          )
      )

instance Control.Exception.Exception OwnedScenarioCleanupFailure

withOwnedScenarioCleanup
  :: Text
  -> IO [LiveWorkflow.CleanupIssue]
  -> IO value
  -> IO value
withOwnedScenarioCleanup ownerLabel =
  withOwnedScenarioCleanupObserved
    (reportAsyncCleanupIssues ownerLabel)
    ownerLabel

withOwnedScenarioCleanupObserved
  :: ([LiveWorkflow.CleanupIssue] -> IO ())
  -> Text
  -> IO [LiveWorkflow.CleanupIssue]
  -> IO value
  -> IO value
withOwnedScenarioCleanupObserved observeAsyncCleanup ownerLabel cleanup action = do
  (actionResult, cleanupIssues) <-
    SafeException.generalBracket
      (pure ())
      (\() _exitCase -> safeCleanup)
      (\() -> tryAnyIntegration action)
  case (actionResult, cleanupIssues) of
    (Right value, []) -> pure value
    (Left primary, issues)
      | Just _asyncException <-
          (Control.Exception.fromException primary :: Maybe Control.Exception.SomeAsyncException) -> do
          case issues of
            [] -> pure ()
            _ -> do
              -- Cancellation identity wins.  The cleanup evidence remains
              -- observable through the caller-selected side channel rather
              -- than being hidden inside a replacement exception.
              _ <- tryAnyIntegration (observeAsyncCleanup issues)
              pure ()
          Control.Exception.throwIO primary
    (Left primary, []) -> Control.Exception.throwIO primary
    (Right _value, issues) ->
      Control.Exception.throwIO
        OwnedScenarioCleanupFailure
          { ownedScenarioLabel = ownerLabel
          , ownedScenarioPrimary = Nothing
          , ownedScenarioCleanupIssues = issues
          }
    (Left primary, issues) ->
      Control.Exception.throwIO
        OwnedScenarioCleanupFailure
          { ownedScenarioLabel = ownerLabel
          , ownedScenarioPrimary = Just primary
          , ownedScenarioCleanupIssues = issues
          }
 where
  safeCleanup = do
    attempted <- tryAnyIntegration cleanup
    case attempted of
      Left exception ->
        case Control.Exception.fromException exception of
          Just asyncException ->
            Control.Exception.throwIO
              (asyncException :: Control.Exception.SomeAsyncException)
          Nothing ->
            pure
              [ LiveWorkflow.CleanupIssue
                  ( ownerLabel
                      <> " cleanup threw: "
                      <> Text.pack (show exception)
                  )
              ]
      Right issues -> pure issues

reportAsyncCleanupIssues
  :: Text
  -> [LiveWorkflow.CleanupIssue]
  -> IO ()
reportAsyncCleanupIssues ownerLabel =
  traverse_
    ( \issue ->
        Output.writeErrorLineIO
          ( ownerLabel
              <> " asynchronous cleanup failure: "
              <> LiveWorkflow.unCleanupIssue issue
          )
    )

tryAnyIntegration
  :: IO value
  -> IO (Either Control.Exception.SomeException value)
tryAnyIntegration = Control.Exception.try

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-integration"
      [ testCase "runStreaming captures a fixture process" $ do
          outcome <- runStreaming defaultSubprocessEnv (subprocess "/bin/echo" ["subprocess-ok"])
          assertProcessExitCode "echo fixture" ExitSuccess outcome
          assertProcessStreamEquals "echo fixture" ProcessStdout "subprocess-ok\n" outcome
          assertProcessStreamEquals "echo fixture" ProcessStderr "" outcome
      , testCase "runStreaming does not wait on descendant-held stdout pipes" $ do
          result <-
            Timeout.timeout 1_000_000 $
              runStreaming
                defaultSubprocessEnv
                (subprocess "sh" ["-c", "(sleep 2 &) ; printf parent-out ; printf parent-err >&2"])
          case result of
            Nothing ->
              assertFailure "runStreaming waited for a descendant process that inherited stdout/stderr"
            Just outcome -> do
              assertProcessExitCode "descendant-pipe fixture" ExitSuccess outcome
              assertProcessStreamEquals "descendant-pipe fixture" ProcessStdout "parent-out" outcome
              assertProcessStreamEquals "descendant-pipe fixture" ProcessStderr "parent-err" outcome
      , testCase "failed Job observation renders status, pod states, and logs (Sprint 12.12)" $ do
          let observation =
                JobFailureObservation
                  { failedJobName = "jitml-rl-synthetic"
                  , failedJobStatus = "Failed:True:BackoffLimitExceeded"
                  , failedJobDescribe = "job condition Failed=True reason=BackoffLimitExceeded"
                  , failedJobPods =
                      [ JobPodObservation
                          { observedPodName = "pod/jitml-rl-synthetic-abcde"
                          , observedPodDescribe = "State: Terminated\nReason: Error"
                          , observedPodLogs = "missing Metal runtime in Linux pod"
                          }
                      ]
                  }
              rendered = renderJobFailureObservation observation
          jobStatusIndicatesFailure "Failed:True:BackoffLimitExceeded" @?= True
          assertBool
            "failure summary should include the failed Job name"
            ("jitml-rl-synthetic" `Text.isInfixOf` rendered)
          assertBool
            "failure summary should include pod container state"
            ("State: Terminated" `Text.isInfixOf` rendered)
          assertBool
            "failure summary should include pod logs"
            ("missing Metal runtime in Linux pod" `Text.isInfixOf` rendered)
      , testCase "daemon log collection spans both command roles after the role split" $ do
          let rendered = renderSubprocess (daemonLogSubprocess (Just "2m"))
          assertBool
            "daemon logs omit an Engine or Coordinator command-role pod"
            ("jitml.role in (engine,coordinator)" `Text.isInfixOf` rendered)
          assertBool
            "daemon logs are not restricted to the two daemon Deployments"
            ("app in (jitml-service,jitml-coordinator)" `Text.isInfixOf` rendered)
          assertBool
            "daemon logs still use the removed single-deployment selector"
            (not ("app=jitml-service" `Text.isInfixOf` rendered))
      , testCase "temporary Kubernetes Job cleanup owns its RunConfig ConfigMap" $ do
          fmap renderSubprocess (temporaryKubernetesJobCleanupCommands "jitml-train-fixture")
            @?= [ "kubectl --kubeconfig ./.build/jitml.kubeconfig delete job jitml-train-fixture -n platform --ignore-not-found"
                , "kubectl --kubeconfig ./.build/jitml.kubeconfig delete configmap runconfig-jitml-train-fixture -n platform --ignore-not-found"
                ]
      , testCase "owned scenario cleanup retains assertion and typed deletion failures" $ do
          let cleanupIssue =
                LiveWorkflow.CleanupIssue
                  "temporary MinIO deletion returned SETransient"
          attempted <-
            Control.Exception.try
              ( withOwnedScenarioCleanup
                  "owned-cleanup-regression"
                  (pure [cleanupIssue])
                  (assertFailure "representative assertion failed before cleanup")
              )
              :: IO (Either OwnedScenarioCleanupFailure ())
          case attempted of
            Right () -> assertFailure "owned cleanup regression unexpectedly succeeded"
            Left failure -> do
              ownedScenarioCleanupIssues failure @?= [cleanupIssue]
              case ownedScenarioPrimary failure of
                Nothing -> assertFailure "the assertion primary was discarded"
                Just primary ->
                  assertBool
                    "the assertion primary detail was discarded"
                    ( "representative assertion failed before cleanup"
                        `Text.isInfixOf` Text.pack (show primary)
                    )
          cleanupOnly <-
            Control.Exception.try
              ( withOwnedScenarioCleanup
                  "owned-cleanup-only-regression"
                  (pure [cleanupIssue])
                  (pure ())
              )
              :: IO (Either OwnedScenarioCleanupFailure ())
          case cleanupOnly of
            Right () -> assertFailure "typed deletion failure was discarded"
            Left failure -> do
              case ownedScenarioPrimary failure of
                Nothing -> pure ()
                Just primary ->
                  assertFailure
                    ("cleanup-only failure gained a primary: " <> show primary)
              ownedScenarioCleanupIssues failure @?= [cleanupIssue]
          observedAsyncCleanup <- newIORef []
          asyncCleanup <-
            Control.Exception.try
              ( withOwnedScenarioCleanupObserved
                  (writeIORef observedAsyncCleanup)
                  "owned-async-cleanup-regression"
                  (pure [cleanupIssue])
                  (Control.Exception.throwIO AsyncCancelled)
              )
              :: IO (Either AsyncCancelled ())
          case asyncCleanup of
            Right () -> assertFailure "asynchronous cancellation was replaced by success"
            Left _sameAsyncType -> pure ()
          readIORef observedAsyncCleanup >>= (@?= [cleanupIssue])
      , testCase "workflow placement keeps Apple Metal starts host-resident (Sprint 12.12)" $ do
          let trainingHostTopic =
                "persistent://public/default/training.host-command.apple-silicon"
              rlHostTopic =
                "persistent://public/default/rl.host-command.apple-silicon"
              tuneHostTopic =
                "persistent://public/default/tune.host-command.apple-silicon"
              (trainingStart, trainingPlan) =
                preparedStartTraining
                  Training.StartTraining
                    { Training.stExperimentHash = "placement-training"
                    , Training.stDhallObjectKey = "experiments/mnist.dhall"
                    , Training.stSubstrate = AppleSilicon
                    , Training.stSeed = 42
                    , Training.stEpochs = 1
                    , Training.stBatchSize = 32
                    , Training.stPlanId = ""
                    , Training.stResolvedPlan = ""
                    , Training.stTrainingExamples = 64
                    , Training.stEvaluationExamples = 16
                    }
              rlStart substrate =
                ProtoRl.StartRLRun
                  { ProtoRl.srlExperimentHash = "placement-rl"
                  , ProtoRl.srlAlgorithm = "PPO"
                  , ProtoRl.srlEnvironment = "cartpole"
                  , ProtoRl.srlSubstrate = substrate
                  , ProtoRl.srlSeed = 7
                  , ProtoRl.srlMaxSteps = 64
                  , ProtoRl.srlEvalEpisodes = 2
                  }
              (tuneStart, tunePlan) =
                preparedStartSweep
                  ProtoTune.StartSweep
                    { ProtoTune.ssExperimentHash = "placement-tune"
                    , ProtoTune.ssDhallObjectKey = "experiments/mnist-tune.dhall"
                    , ProtoTune.ssSubstrate = AppleSilicon
                    , ProtoTune.ssSweepSeed = 17
                    , ProtoTune.ssTrialBudget = 4
                    , ProtoTune.ssBudgetPerTrial = 100
                    , ProtoTune.ssSampler = "TPE"
                    , ProtoTune.ssScheduler = "ASHA"
                    , ProtoTune.ssPruner = "MedianPruner"
                    , ProtoTune.ssParallelism = 1
                    , ProtoTune.ssPromotions = 1
                    , ProtoTune.ssPlanId = ""
                    , ProtoTune.ssResolvedPlan = ""
                    }
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.SlTrain AppleSilicon
            @?= WorkflowMatrix.WorkflowHostCommandExpected trainingHostTopic
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.RlTrain AppleSilicon
            @?= WorkflowMatrix.WorkflowHostCommandExpected rlHostTopic
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.Tune AppleSilicon
            @?= WorkflowMatrix.WorkflowHostCommandExpected tuneHostTopic
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.SlTrain LinuxCPU
            @?= WorkflowMatrix.WorkflowClusterJobExpected
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.RlTrain LinuxCUDA
            @?= WorkflowMatrix.WorkflowClusterJobExpected
          case Workload.planWorkloadPlacement
            BootConfig.Cluster
            (Workload.ResolvedTrainingLaunch trainingStart trainingPlan) of
            Right (Workload.WorkloadHostCommand spec) -> do
              Workload.hostCommandSpecTopicName spec @?= trainingHostTopic
              Workload.hostCommandSpecPayload spec
                @?= Training.renderTrainingCommand (Training.TrainingStart trainingStart)
            other -> assertFailure ("expected typed training host placement, got " <> show other)
          case Workload.planWorkloadPlacement
            BootConfig.Cluster
            (Workload.RlLaunch (rlStart AppleSilicon)) of
            Right (Workload.WorkloadHostCommand spec) -> do
              Workload.hostCommandSpecTopicName spec @?= rlHostTopic
              Workload.hostCommandSpecPayload spec
                @?= ProtoRl.renderRlCommand (ProtoRl.RlStart (rlStart AppleSilicon))
            other -> assertFailure ("expected typed RL host placement, got " <> show other)
          case Workload.planWorkloadPlacement
            BootConfig.Cluster
            (Workload.TuneLaunch tuneStart tunePlan) of
            Right (Workload.WorkloadHostCommand spec) -> do
              Workload.hostCommandSpecTopicName spec @?= tuneHostTopic
              Workload.hostCommandSpecPayload spec
                @?= ProtoTune.renderTuneCommand (ProtoTune.TuneStart tuneStart)
            other -> assertFailure ("expected typed tune host placement, got " <> show other)
          case Workload.planWorkloadPlacement
            BootConfig.Cluster
            (Workload.RlLaunch (rlStart LinuxCPU)) of
            Right (Workload.WorkloadClusterJob spec) -> do
              Workload.clusterJobResource spec @?= KubeResource "job/jitml-rl-placement-rl"
              assertBool
                "cluster placement retains the rendered Job manifest"
                ("name: jitml-rl-placement-rl" `Text.isInfixOf` Workload.clusterJobManifest spec)
            other -> assertFailure ("expected evidence-bearing cluster Job placement, got " <> show other)
      , testCase "live Tune fixture matches the registered ProductRow publisher schedule" $ do
          loaded <-
            Tune.loadTuningExperiment (Text.unpack (ProductMatrix.experimentConfig registeredTuningRow))
          config <-
            case loaded
              >>= maybe (Left "registered tuning experiment has no tuning config") Right . Tune.tuningExperimentConfig of
              Left err -> assertFailureWithIO ("cannot load registered tuning schedule: " <> Text.unpack err)
              Right value -> pure value
          let raw = registeredTuningStartSweep LinuxCPU "tune-schedule-regression"
              (prepared, plan) = preparedStartSweep raw
              trialCount = fromIntegral (ProtoTune.ssTrialBudget prepared)
              parallelism = fromIntegral (ProtoTune.ssParallelism prepared)
              updates = fromIntegral (ProtoTune.ssBudgetPerTrial prepared)
              promotions = fromIntegral (ProtoTune.ssPromotions prepared)
          ProtoTune.ssSweepSeed prepared @?= registeredTuningSeed
          ProtoTune.ssTrialBudget prepared @?= registeredTuningTrialBudget
          ProtoTune.ssBudgetPerTrial prepared
            @?= registeredTuningPerTrialBudget
          ProtoTune.ssParallelism prepared
            @?= fromIntegral Tune.tuningObjectiveParallelism
          quantityValue (tuningPlanTrials plan)
            @?= fromIntegral registeredTuningTrialBudget
          quantityValue (tuningPlanParallelism plan)
            @?= fromIntegral Tune.tuningObjectiveParallelism
          quantityValue (tuningPlanPerTrialUpdates plan)
            @?= fromIntegral registeredTuningPerTrialBudget
          fromIntegral (Tune.tuningConfigTrials config)
            @?= registeredTuningTrialBudget
          results <-
            case Tune.trialObjectiveResultsForBudget
              (Tune.tuningSamplerKind (Tune.tuningConfigSampler config))
              parallelism
              updates
              trialCount of
              Left err -> assertFailureWithIO ("registered tuning schedule failed: " <> Text.unpack err)
              Right values -> pure values
          executions <-
            case Tune.trialExecutions
              (Tune.tuningSchedulerKind (Tune.tuningConfigScheduler config))
              (Tune.tuningPrunerKind (Tune.tuningConfigPruner config))
              promotions
              results of
              Left err -> assertFailureWithIO ("registered tuning execution failed: " <> Text.unpack err)
              Right values -> pure values
          case [ Tune.trialResultObjective (Tune.trialExecutionResult execution)
               | execution <- executions
               , Tune.trialExecutionPromoted execution
               ] of
            [] -> assertFailure "registered tuning schedule produced no promoted objective"
            promotedObjectives ->
              case ProductConvergence.evaluateConvergence
                (ProductMatrix.convergenceBar registeredTuningRow)
                (ProductConvergence.MeasuredMetrics [("best_objective", maximum promotedObjectives)]) of
                Left err -> assertFailure ("registered tuning bar evaluation failed: " <> Text.unpack err)
                Right observation ->
                  assertBool
                    "registered tuning publisher schedule does not clear its unchanged convergence bar"
                    (TrainingBudget.convergencePassed observation)
      , testCase
          "ProductRow admitted-inventory-55 is exact and unique (Sprint 19.4)"
          assertProductRowAdmittedInventory
      , testGroup
          "ProductRow integration matrix (Sprint 28.1)"
          ( testCase
              "row integration report fails naming uncovered row/test pairs"
              assertProductRowIntegrationReportCoverage
              : fmap productRowIntegrationTest ProductMatrix.allProductRows
          )
      , testCase "bootstrap plan includes Harbor-first publication" $
          bootstrapPlanSteps LinuxCPU
            @?= [ "reconcile prerequisite graph for cluster"
                , "render kind/cluster-linux-cpu.yaml"
                , "prepare Helm dependencies with helm dependency build chart"
                , "create/export Kind kubeconfig and copy it to ./.build/jitml.kubeconfig"
                , "raise Kind-node inotify caps for multi-cluster host readiness"
                , "prepare substrate-specific stateful PV storage"
                , "apply jitml-manual StorageClass and manual PVs"
                , "install MinIO and Percona storage for Harbor"
                , "install Harbor bootstrap phase"
                , "build jitml:local, retag jitml-demo:local, and load them into Kind"
                , "install Pulsar, Envoy Gateway, observability, jitml-service, jitml-demo"
                , "reconcile app pods to the loaded image identities"
                , "prove Engine, Coordinator, and public edge readiness"
                , "write ./.build/runtime/cluster-publication.json"
                ]
      , testCase "app image reconcile requires the complete loaded identity set" $ do
          let loadedImage = "sha256:loaded"
          appRolloutMatchesLoadedImage 3 loadedImage (replicate 3 loadedImage) @?= True
          appRolloutMatchesLoadedImage 0 loadedImage [] @?= False
          appRolloutMatchesLoadedImage 3 loadedImage [loadedImage, loadedImage] @?= False
          appRolloutMatchesLoadedImage 3 loadedImage [loadedImage, loadedImage, "sha256:stale"]
            @?= False
      , testCase "app image evidence waits for deletion-marked rollout residue" $ do
          let loadedImage = "sha256:" <> Text.replicate 64 "a"
              staleImage = "sha256:" <> Text.replicate 64 "b"
              pod metadata ready imageId =
                "{\"metadata\":{"
                  <> metadata
                  <> "},\"status\":{\"containerStatuses\":[{\"ready\":"
                  <> ready
                  <> ",\"imageID\":\""
                  <> imageId
                  <> "\"}]}}"
              activeLoaded = pod "" "true" loadedImage
              activeStale = pod "" "true" staleImage
              terminatingStale =
                pod "\"deletionTimestamp\":\"2026-07-16T12:41:13Z\"" "true" staleImage
              notReady = pod "" "false" loadedImage
              podList pods = "{\"items\":[" <> Text.intercalate "," pods <> "]}"
              parsed pods =
                case parseAppPodImageEvidence (podList pods) of
                  Nothing -> error "test fixture did not parse"
                  Just evidence -> evidence
              exactEvidence = parsed [activeLoaded]
              deletingEvidence = parsed [activeLoaded, terminatingStale]
              mixedEvidence = parsed [activeLoaded, activeStale]
              notReadyEvidence = parsed [notReady]
          appPodImageEvidenceMatchesLoadedImage 1 loadedImage exactEvidence @?= True
          appPodImagePollDecision 1 loadedImage 60 exactEvidence
            @?= AppPodImageConverged
          appPodImageEvidenceMatchesLoadedImage 1 loadedImage deletingEvidence @?= False
          appPodImagePollDecision 1 loadedImage 60 deletingEvidence
            @?= AppPodImageRetry
          appPodImagePollDecision 1 loadedImage 1 deletingEvidence
            @?= AppPodImageExhausted
          appPodImageEvidenceMatchesLoadedImage 1 loadedImage mixedEvidence @?= False
          appPodImageEvidenceMatchesLoadedImage 1 loadedImage notReadyEvidence @?= False
      , testCase "Kind node image evidence parses one exact OCI target digest" $ do
          let digest = "sha256:" <> Text.replicate 64 "a"
              header = "REF TYPE DIGEST SIZE PLATFORMS LABELS"
              row =
                "docker.io/library/jitml:local application/vnd.oci.image.index.v1+json "
                  <> digest
                  <> " 6.5GiB linux/amd64 managed"
          parseContainerdImageListDigest (Text.unlines [header, row])
            @?= Just digest
          parseContainerdImageListDigest header @?= Nothing
          parseContainerdImageListDigest (Text.unlines [header, row, row]) @?= Nothing
          parseContainerdImageListDigest
            (Text.unlines [header, Text.replace digest "sha256:short" row])
            @?= Nothing
      , testCase "Kind node config evidence requires one uniform non-empty identity" $ do
          let loadedImage = "sha256:" <> Text.replicate 64 "b"
              staleImage = "sha256:" <> Text.replicate 64 "c"
          uniformImageId [Just loadedImage, Just loadedImage] @?= Just loadedImage
          uniformImageId [Just loadedImage, Nothing] @?= Nothing
          uniformImageId [Just loadedImage, Just staleImage] @?= Nothing
          uniformImageId [] @?= Nothing
          uniformImageId [Just ""] @?= Nothing
      , testCase "kind config render carries repo mounts for non-CUDA substrates" $ do
          let appleConfig = renderKindConfig (kindConfigFor AppleSilicon)
              cpuConfig = renderKindConfig (kindConfigFor LinuxCPU)
          assertBool
            "apple-silicon mounts build cache"
            ("containerPath: /jitml/.build" `Text.isInfixOf` appleConfig)
          assertBool "linux-cpu mounts data root" ("containerPath: /jitml/.data" `Text.isInfixOf` cpuConfig)
          assertBool
            "apple-silicon does not configure NVIDIA containerd"
            (not ("runtimes.nvidia" `Text.isInfixOf` appleConfig))
          assertBool
            "linux-cpu does not mount NVIDIA toolkit"
            (not ("nvidia-container-runtime" `Text.isInfixOf` cpuConfig))
      , testCase "kind config renders HA control-plane plus mounted workers (Sprint 3.6)" $ do
          let cpuConfig = renderKindConfig (kindConfigFor LinuxCPU)
              controlPlaneCount =
                length (Text.breakOnAll "  - role: control-plane" cpuConfig)
              workerCount =
                length (Text.breakOnAll "  - role: worker" cpuConfig)
          controlPlaneCount @?= 1
          workerCount @?= 3
          assertBool
            "worker nodes are labelled as compute-capable"
            ("jitml.node-role/compute=true" `Text.isInfixOf` cpuConfig)
          assertBool
            "every HA node has the repo build mount"
            (length (Text.breakOnAll "containerPath: /jitml/.build" cpuConfig) == 4)
      , testCase "linux-cuda Kind config wires NVIDIA runtime handler (Sprint 4.7)" $ do
          let cudaConfig = renderKindConfig (kindConfigFor LinuxCUDA)
          assertBool
            "linux-cuda worker nodes carry the GPU node label"
            ( "jitml.substrate/linux-cuda=true,jitml.node-role/compute=true,jitml.runtime/gpu=true"
                `Text.isInfixOf` cudaConfig
            )
          assertBool
            "linux-cuda configures containerd patches"
            ("containerdConfigPatches:" `Text.isInfixOf` cudaConfig)
          assertBool "linux-cuda registers the nvidia runtime" ("runtimes.nvidia" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda runtime uses the NVIDIA binary"
            ("BinaryName = \"/usr/bin/nvidia-container-runtime\"" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the repo-owned runtime config"
            ("containerPath: /etc/nvidia-container-runtime" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the runtime binary"
            ("containerPath: /usr/bin/nvidia-container-runtime" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the host driver root"
            ("containerPath: /run/nvidia/driver" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the container CLI library"
            ("containerPath: /usr/lib/x86_64-linux-gnu/libnvidia-container.so.1" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts the container CLI Go support library"
            ("containerPath: /usr/lib/x86_64-linux-gnu/libnvidia-container-go.so.1" `Text.isInfixOf` cudaConfig)
          assertBool
            "linux-cuda mounts NVML for the NVIDIA container CLI"
            ("containerPath: /usr/lib/x86_64-linux-gnu/libnvidia-ml.so.1" `Text.isInfixOf` cudaConfig)
      , testCase "route registry renders HTTPRoute manifests" $
          length (fmap renderHTTPRoute routeRegistry) @?= length routeRegistry
      , testCase "Harbor registry route allows real blob upload finalization" $ do
          case filter
            (Text.isInfixOf "  name: harbor-registry")
            (fmap renderHTTPRoute routeRegistry) of
            [routeYaml] -> do
              assertBool
                "Harbor registry route has a request timeout above Envoy's default"
                ("        request: 120s" `Text.isInfixOf` routeYaml)
              assertBool
                "Harbor registry route has a backend request timeout above Envoy's default"
                ("        backendRequest: 120s" `Text.isInfixOf` routeYaml)
            other ->
              assertFailure
                ( "expected exactly one rendered harbor-registry route, got "
                    <> show (length other)
                )
      , testCase "EnvoyProxy renderer pins local data-plane resource requests" $ do
          let envoyProxy = Gateway.renderEnvoyProxy 9091
          assertBool
            "Envoy data-plane CPU request stays local-friendly"
            ("cpu: 50m" `Text.isInfixOf` envoyProxy)
          assertBool
            "Envoy data-plane memory request stays local-friendly"
            ("memory: 512Mi" `Text.isInfixOf` envoyProxy)
          assertBool
            "Envoy data-plane memory limit keeps archive uploads bounded"
            ("memory: 1Gi" `Text.isInfixOf` envoyProxy)
          assertBool
            "Envoy readiness tolerates saturated local Kind workers"
            ( "readinessProbe:\n                        failureThreshold: 12\n                        periodSeconds: 5\n                        timeoutSeconds: 10"
                `Text.isInfixOf` envoyProxy
            )
          assertBool
            "Envoy startup tolerates slow xDS recovery"
            ( "startupProbe:\n                        failureThreshold: 60\n                        periodSeconds: 10\n                        timeoutSeconds: 10"
                `Text.isInfixOf` envoyProxy
            )
          assertBool
            "shutdown-manager liveness tolerates loaded VM probes"
            ( "livenessProbe:\n                        failureThreshold: 12\n                        periodSeconds: 10\n                        timeoutSeconds: 5"
                `Text.isInfixOf` envoyProxy
            )
      , testCase "route table matches golden fixture" $ do
          expected <- Text.IO.readFile "test/snapshots/cluster/route-table.md"
          renderRouteTable @?= expected
      , testCase "filesystem HasMinIO honours putBlobIfAbsent and pointer CAS" $
          withSystemTempDirectory "jitml-fs-minio" $ \root ->
            runFilesystemMinIO root $ do
              let bucket = BucketName "jitml-checkpoints"
                  blobRef = ObjectRef bucket (ObjectKey "blobs/abc.bin")
                  pointerRef = ObjectRef bucket (ObjectKey "pointers/latest")
              first <- putBlobIfAbsent blobRef "weights:v1"
              case first of
                Right (ETag _) -> pure ()
                Left err ->
                  liftIO (assertFailure ("expected first putBlobIfAbsent OK, got: " <> show err))
              second <- putBlobIfAbsent blobRef "weights:v1"
              case second of
                Left (SEConflict _) -> pure ()
                _ -> liftIO (assertFailure "expected SEConflict on second putBlobIfAbsent")
              ptr1 <- casPointer pointerRef Nothing "manifest:sha-1"
              case ptr1 of
                Right (ETag etag1) -> do
                  ptr2 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-2"
                  case ptr2 of
                    Right (ETag _) -> pure ()
                    Left err ->
                      liftIO (assertFailure ("expected pointer CAS OK, got: " <> show err))
                  ptr3 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-3"
                  case ptr3 of
                    Left (SEConflict _) -> pure ()
                    _ -> liftIO (assertFailure "expected SEConflict on stale-ETag pointer CAS")
                Left err ->
                  liftIO (assertFailure ("expected first casPointer OK, got: " <> show err))
      , testCase "verified canonical dataset artifact rejects corrupt bytes before decode (Sprint 22.3)" $
          withSystemTempDirectory "jitml-corrupt-dataset" $ \root ->
            runFilesystemMinIO root $ do
              let ref = Dataset.DatasetRef "MNIST" Dataset.TrainSplit 0 "ignored"
                  payload = Text.Encoding.encodeUtf8 "not the canonical MNIST train image gzip"
              _ <- putBlobBytesIfAbsent (Dataset.datasetArtifactObjectRef ref Dataset.ImagesArtifact) payload
              result <- Dataset.fetchVerifiedDatasetArtifactBytes ref Dataset.ImagesArtifact
              liftIO $
                case result of
                  Left (SEConflict message) ->
                    assertBool
                      "SHA verification should fail before any dataset decoder runs"
                      ("dataset SHA mismatch for MNIST/train/images" `Text.isInfixOf` message)
                  Left err ->
                    assertFailure ("expected SHA conflict, got " <> show err)
                  Right _ ->
                    assertFailure "corrupt canonical dataset bytes unexpectedly verified"
      , testCase "candidate checkpoint transaction is pointer-free and detects byte conflicts" $
          withSystemTempDirectory "jitml-checkpoint-hasminio" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-write-minio"
                  payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
                  blobObjectKey =
                    Checkpoint.blobKey
                      experimentHash
                      (WeightCodec.jmw1ContentSha payload)
                  manifest =
                    ( Checkpoint.emptyManifest
                        "m1"
                        experimentHash
                        [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
                    )
                      { Checkpoint.manifestStep = 1
                      , Checkpoint.manifestMetrics = [("validation_accuracy", 0.9)]
                      }
              firstWrite <-
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  manifest
                  [(blobObjectKey, payload)]
              case firstWrite of
                Left err ->
                  liftIO (assertFailure ("expected checkpoint write OK, got: " <> show err))
                Right candidate -> do
                  let stored = CheckpointStore.candidateStoredCheckpoint candidate
                  liftIO $
                    CheckpointStore.storedPointerResult stored
                      @?= Checkpoint.PointerNotWritten
                        (Checkpoint.latestPointerKey experimentHash)
              pointerRead <-
                minioReadBytes
                  ( CheckpointStore.checkpointObjectRef
                      (Checkpoint.latestPointerKey experimentHash)
                  )
              liftIO $
                case pointerRead of
                  Left _ -> pure ()
                  Right _ -> assertFailure "candidate unexpectedly published latest pointer"
              secondWrite <-
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  manifest
                  [(blobObjectKey, payload)]
              case secondWrite of
                Left err ->
                  liftIO (assertFailure ("expected idempotent object writes, got: " <> show err))
                Right candidate ->
                  liftIO $
                    CheckpointStore.storedPointerResult
                      (CheckpointStore.candidateStoredCheckpoint candidate)
                      @?= Checkpoint.PointerNotWritten
                        (Checkpoint.latestPointerKey experimentHash)

              let conflictExperiment = "exp-write-minio-conflict"
                  intendedPayload = Checkpoint.encodeJmw1 [5.0, 6.0]
                  conflictBlobKey =
                    Checkpoint.blobKey
                      conflictExperiment
                      (WeightCodec.jmw1ContentSha intendedPayload)
                  conflictManifest =
                    Checkpoint.emptyManifest
                      "m-conflict"
                      conflictExperiment
                      [Checkpoint.TensorBlob "dense.weight" [2] conflictBlobKey]
              _ <-
                putBlobBytesIfAbsent
                  (CheckpointStore.checkpointObjectRef conflictBlobKey)
                  "different-existing-bytes"
              conflict <-
                CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                  conflictManifest
                  [(conflictBlobKey, intendedPayload)]
              liftIO $
                case conflict of
                  Left (SEConflict _) -> pure ()
                  other ->
                    assertFailure
                      ("expected exact existing-different-byte conflict, got: " <> show other)
      , testCase "MinIOSubprocess renders signed S3 conditional-write commands" $ do
          let settings = MinIOSubprocess.minioSettingsForLocalEdge 9091
              ref = ObjectRef (BucketName "jitml-checkpoints") (ObjectKey "pointers/latest")
              putCommand =
                MinIOSubprocess.minioPutObjectSubprocess
                  settings
                  ref
                  "/tmp/payload"
                  "/tmp/body"
                  "/tmp/etag"
                  Nothing
              listCommand =
                MinIOSubprocess.minioListObjectsSubprocess
                  settings
                  (BucketName "jitml-checkpoints")
                  "pointers/"
                  "/tmp/body"
          assertBool
            "MinIO PUT uses curl AWS SigV4"
            ("--aws-sigv4 aws:amz:us-east-1:s3" `Text.isInfixOf` renderSubprocess putCommand)
          assertBool
            "MinIO PUT uses local demo credentials explicitly"
            ("--user minio:minioadmin" `Text.isInfixOf` renderSubprocess putCommand)
          assertBool
            "MinIO PUT bounds connect and operation time"
            ( "--connect-timeout 10 --max-time 300"
                `Text.isInfixOf` renderSubprocess putCommand
            )
          assertBool
            "MinIO PUT enforces If-None-Match"
            ("--header 'If-None-Match: *'" `Text.isInfixOf` renderSubprocess putCommand)
          assertBool
            "MinIO list retries transient routed edge failures"
            ( "--retry 5 --retry-delay 2 --retry-max-time 120 --retry-connrefused --retry-all-errors"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          assertBool
            "MinIO PUT signs the canonical S3 object URL"
            ( "http://127.0.0.1:9091/jitml-checkpoints/pointers/latest"
                `Text.isInfixOf` renderSubprocess putCommand
            )
          assertBool
            "MinIO PUT sends the routed Envoy request target"
            ( "--request-target /minio/s3/jitml-checkpoints/pointers/latest"
                `Text.isInfixOf` renderSubprocess putCommand
            )
          assertBool
            "MinIO list uses S3 list-type query"
            ( "'http://127.0.0.1:9091/jitml-checkpoints?list-type=2&prefix=pointers%2F'"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          assertBool
            "MinIO list sends the routed Envoy request target"
            ( "'/minio/s3/jitml-checkpoints?list-type=2&prefix=pointers%2F'"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          MinIOSubprocess.parseListObjectsResponse
            (BucketName "jitml-checkpoints")
            "<ListBucketResult><Contents><Key>pointers/latest</Key></Contents></ListBucketResult>"
            @?= [ObjectRef (BucketName "jitml-checkpoints") (ObjectKey "pointers/latest")]
      , testCase "PulsarWebSocketSubprocess renders the persistent receipt bridge" $ do
          let settings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge 9091
              topic = topologyTopic TrainingCommandRoute LinuxCPU
              (trainingStart, _) =
                preparedStartTraining
                  Training.StartTraining
                    { Training.stExperimentHash = "pulsar-command-render"
                    , Training.stDhallObjectKey = "experiments/mnist.dhall"
                    , Training.stSubstrate = LinuxCPU
                    , Training.stSeed = 42
                    , Training.stEpochs = 1
                    , Training.stBatchSize = 32
                    , Training.stPlanId = ""
                    , Training.stResolvedPlan = ""
                    , Training.stTrainingExamples = 64
                    , Training.stEvaluationExamples = 16
                    }
              command = Training.TrainingStart trainingStart
              borrowedSubscription =
                subscriptionFixture topic "jitml-live" FromLatest Borrowed
              ownedSubscription =
                subscriptionFixture topic "jitml-live-owned" FromEarliest Owned
              publishCommand =
                PulsarWebSocketSubprocess.pulsarPublishSubprocess settings topic command
              consumerCommand =
                PulsarWebSocketSubprocess.pulsarConsumerSubprocess settings borrowedSubscription
              deleteCommand =
                PulsarWebSocketSubprocess.pulsarDeleteSubscriptionSubprocess settings ownedSubscription
              consumerScript = PulsarWebSocketSubprocess.pulsarConsumerBridgeScript
          PulsarWebSocketSubprocess.pulsarAdminEndpoint settings
            @?= "http://127.0.0.1:9091/pulsar/admin/v2"
          assertBool
            "typed Pulsar producer targets the topology-owned route"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/producer/persistent/public/default/training.command.linux-cpu"
                `Text.isInfixOf` renderSubprocess publishCommand
            )
          JitML.Sub.Subprocess.subprocessStdin publishCommand
            @?= Just (Training.renderTrainingCommand command)
          assertBool
            "persistent consumer targets the typed topic and opaque subscription name"
            ( "ws://127.0.0.1:9091/pulsar/ws/v2/consumer/persistent/public/default/training.command.linux-cpu/jitml-live"
                `Text.isInfixOf` renderSubprocess consumerCommand
            )
          assertBool
            "persistent consumer requests one pull-mode delivery"
            ( "receiverQueueSize=1&pullMode=true&subscriptionInitialPosition=Latest"
                `Text.isInfixOf` renderSubprocess consumerCommand
            )
          assertBool
            "persistent consumer has no broker ack timeout"
            (not ("ackTimeoutMillis" `Text.isInfixOf` renderSubprocess consumerCommand))
          assertBool
            "bridge keeps broker message ids only in its private receipt map"
            ( "const receiptToMessageId = new Map();" `Text.isInfixOf` consumerScript
                && "receiptToMessageId.set(deliveryId, { receipt, messageId: message.messageId });"
                  `Text.isInfixOf` consumerScript
            )
          assertBool
            "bridge emits receipt tokens rather than broker message ids"
            ( "emit({ type: 'delivery', receipt, payloadBase64: message.payload, redeliveryCount });"
                `Text.isInfixOf` consumerScript
            )
          assertBool
            "bridge grants exactly one explicit permit at a time"
            ( "socket.send(JSON.stringify({ type: 'permit', permitMessages: 1 }));"
                `Text.isInfixOf` consumerScript
            )
          assertBool
            "bridge accepts one NDJSON settlement from the parent"
            ( "process.stdin.on('data'" `Text.isInfixOf` consumerScript
                && "if (command.type === 'settle')" `Text.isInfixOf` consumerScript
                && "emit({ type: 'settled', receipt, settlement });" `Text.isInfixOf` consumerScript
            )
          assertBool
            "bridge supports negative acknowledgement and terminal drain"
            ( "negativeAcknowledge" `Text.isInfixOf` consumerScript
                && "emit({ type: 'drained' });" `Text.isInfixOf` consumerScript
            )
          PulsarWebSocketSubprocess.subscriptionCleanupSubprocess settings borrowedSubscription
            @?= Nothing
          fmap
            renderSubprocess
            (PulsarWebSocketSubprocess.subscriptionCleanupSubprocess settings ownedSubscription)
            @?= Just (renderSubprocess deleteCommand)
          assertBool
            "owned cleanup uses the Pulsar admin endpoint"
            ( "http://127.0.0.1:9091/pulsar/admin/v2/persistent/public/default/training.command.linux-cpu/subscription/jitml-live-owned?force=true"
                `Text.isInfixOf` renderSubprocess deleteCommand
            )
          assertBool
            "owned cleanup follows bounded HTTP(S) redirects"
            ( all
                (`elem` JitML.Sub.Subprocess.subprocessArguments deleteCommand)
                ["--location", "--max-redirs", "5", "--proto-redir", "=http,https"]
            )
          assertBool
            "newline subscription encodings are rejected"
            ( case mkSubscription topic "jitml-live\nforged" FromLatest Owned of
                Left _ -> True
                Right _ -> False
            )
      , testCase "Pulsar bootstrap registers the substrate-scoped topic family (Sprint 5.5)" $ do
          let topics = fmap PulsarBootstrap.topicName PulsarBootstrap.pulsarTopics
              statsCommands =
                fmap
                  (renderSubprocess . PulsarBootstrap.pulsarTopicStatsSubprocess)
                  PulsarBootstrap.pulsarTopics
              logicalStores =
                fmap
                  ProjectConfig.storeLogicalName
                  (ProjectConfig.projectStores ProjectConfig.defaultProjectConfig)
          -- The 31 retained protocol topics plus workflow.status in all three
          -- substrate lanes are derived from the Coordinator topology.
          length topics @?= 34
          length statsCommands @?= 34
          assertBool
            "every exact topic probe uses read-only stats rather than a namespace list"
            (all ("topics stats persistent://public/default/" `Text.isInfixOf`) statsCommands)
          topicStatsPollDecision 3 (Just "{\"subscriptions\":{}}")
            @?= TopicStatsObserved
          topicStatsPollDecision 3 (Just "not-json") @?= TopicStatsRetry
          topicStatsPollDecision 3 (Just "[]") @?= TopicStatsRetry
          topicStatsPollDecision 3 Nothing @?= TopicStatsRetry
          topicStatsPollDecision 1 Nothing @?= TopicStatsExhausted
          traverse_
            ( \topic ->
                assertBool
                  ("registered topic " <> Text.unpack topic)
                  (topic `elem` topics)
            )
            [ "persistent://public/default/training.command.apple-silicon"
            , "persistent://public/default/training.event.apple-silicon"
            , "persistent://public/default/tune.command.apple-silicon"
            , "persistent://public/default/tune.event.apple-silicon"
            , "persistent://public/default/rl.command.apple-silicon"
            , "persistent://public/default/rl.event.apple-silicon"
            , "persistent://public/default/inference.request.apple-silicon"
            , "persistent://public/default/inference.result.apple-silicon"
            , "persistent://public/default/training.command.linux-cpu"
            , "persistent://public/default/tune.command.linux-cpu"
            , "persistent://public/default/rl.command.linux-cpu"
            , "persistent://public/default/inference.request.linux-cpu"
            , "persistent://public/default/training.command.linux-cuda"
            , "persistent://public/default/tune.command.linux-cuda"
            , "persistent://public/default/rl.command.linux-cuda"
            , "persistent://public/default/inference.request.linux-cuda"
            , "persistent://public/default/inference.command.apple-silicon"
            , "persistent://public/default/training.host-command.apple-silicon"
            , "persistent://public/default/tune.host-command.apple-silicon"
            , "persistent://public/default/rl.host-command.apple-silicon"
            , "persistent://public/default/gc.event.apple-silicon"
            , "persistent://public/default/gc.event.linux-cpu"
            , "persistent://public/default/gc.event.linux-cuda"
            , "persistent://public/default/workflow.status.apple-silicon"
            , "persistent://public/default/workflow.status.linux-cpu"
            , "persistent://public/default/workflow.status.linux-cuda"
            ]
          assertBool
            "project store registry declares workflow.status"
            ("workflow.status" `elem` logicalStores)
          assertBool
            "no retired cluster topic"
            ("persistent://public/default/training.command.cluster" `notElem` topics)
          assertBool
            "no retired host topic"
            ("persistent://public/default/inference.request.host" `notElem` topics)
      , testCase "BootConfig Dhall loader round-trips the rendered cluster config" $
          withSystemTempDirectory "jitml-boot-config" $ \root -> do
            let bootConfig = BootConfig.defaultBootConfig LinuxCUDA BootConfig.Cluster
                bootConfigPath = root </> "BootConfig.dhall"
            Text.IO.writeFile bootConfigPath (BootConfig.renderBootConfigDhall bootConfig)
            loadedConfig <- BootConfig.loadBootConfig bootConfigPath
            loadedConfig @?= bootConfig
      , testCase "BootConfig Dhall loader round-trips the rendered Apple host config" $
          withSystemTempDirectory "jitml-host-boot-config" $ \root -> do
            let bootConfig =
                  (BootConfig.defaultBootConfig AppleSilicon BootConfig.Host)
                    { BootConfig.bootPulsarServiceUrl = "pulsar://127.0.0.1:9090/pulsar"
                    , BootConfig.bootPulsarAdminUrl = "http://127.0.0.1:9090/pulsar/admin"
                    , BootConfig.bootMinioEndpoint = "http://127.0.0.1:9090/minio/s3"
                    , BootConfig.bootHarborRegistry = "127.0.0.1:9090/library"
                    }
                bootConfigPath = root </> "BootConfig.dhall"
            Text.IO.writeFile bootConfigPath (BootConfig.renderBootConfigDhall bootConfig)
            loadedConfig <- BootConfig.loadBootConfig bootConfigPath
            loadedConfig @?= bootConfig
      , testCase "daemon subscriptions follow the disjoint Engine/Coordinator role topology (Sprint 12.16)" $ do
          let linuxEngine =
                BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster
              linuxCoordinator =
                linuxEngine {BootConfig.bootActiveRole = BootConfig.Coordinator}
              appleCoordinator =
                (BootConfig.defaultBootConfig AppleSilicon BootConfig.Cluster)
                  { BootConfig.bootActiveRole = BootConfig.Coordinator
                  }
              appleHostEngine =
                BootConfig.defaultBootConfig AppleSilicon BootConfig.Host
              projectSubscriptions =
                fmap
                  (\subscription -> (daemonSubscriptionTopicName subscription, daemonSubscriptionName subscription))
              expectPlan config =
                case daemonSubscriptionsForBootConfig config of
                  Left err -> assertFailure ("invalid daemon subscription plan: " <> show err) >> pure []
                  Right subscriptions -> pure (projectSubscriptions subscriptions)

          linuxEnginePlan <- expectPlan linuxEngine
          linuxEnginePlan
            @?= [topologySubscription InferenceRequestRoute LinuxCPU "jitml-engine"]

          linuxCoordinatorPlan <- expectPlan linuxCoordinator
          linuxCoordinatorPlan
            @?= [ topologySubscription TrainingCommandRoute LinuxCPU "jitml-coordinator"
                , topologySubscription TuneCommandRoute LinuxCPU "jitml-coordinator"
                , topologySubscription RlCommandRoute LinuxCPU "jitml-coordinator"
                ]

          appleCoordinatorPlan <- expectPlan appleCoordinator
          appleCoordinatorPlan
            @?= [ topologySubscription TrainingCommandRoute AppleSilicon "jitml-coordinator"
                , topologySubscription TuneCommandRoute AppleSilicon "jitml-coordinator"
                , topologySubscription RlCommandRoute AppleSilicon "jitml-coordinator"
                , topologySubscription InferenceRequestRoute AppleSilicon "jitml-coordinator"
                ]

          appleHostPlan <- expectPlan appleHostEngine
          appleHostPlan
            @?= [ topologySubscription InferenceHostCommandRoute AppleSilicon "jitml-host"
                , topologySubscription TrainingHostCommandRoute AppleSilicon "jitml-host"
                , topologySubscription TuneHostCommandRoute AppleSilicon "jitml-host"
                , topologySubscription RlHostCommandRoute AppleSilicon "jitml-host"
                ]
      , testCase "Coordinator client settings derive in-cluster endpoints from BootConfig (Sprint 12.16)" $ do
          let settings =
                ServiceClients.coordinatorClientSettingsForBootConfig
                  ( (BootConfig.defaultBootConfig LinuxCPU BootConfig.Cluster)
                      { BootConfig.bootActiveRole = BootConfig.Coordinator
                      }
                  )
              minioSettings = ServiceClients.daemonMinIOSettings settings
              pulsarSettings = ServiceClients.daemonPulsarSettings settings
              harborSettings = ServiceClients.daemonHarborSettings settings
              kubectlSettings = ServiceClients.daemonKubectlSettings settings
          MinIOSubprocess.minioEndpoint minioSettings
            @?= "http://minio.platform.svc.cluster.local:9000"
          MinIOSubprocess.minioRequestPathPrefix minioSettings @?= ""
          PulsarWebSocketSubprocess.pulsarWebSocketEndpoint pulsarSettings
            @?= "ws://pulsar-broker.platform.svc.cluster.local:8080/ws"
          PulsarWebSocketSubprocess.pulsarAdminEndpoint pulsarSettings
            @?= "http://pulsar-proxy.platform.svc.cluster.local:80/admin/v2"
          HarborSubprocess.harborRegistry harborSettings
            @?= "harbor-registry.platform.svc.cluster.local:5000"
          HarborSubprocess.harborApiBaseUrl harborSettings
            @?= "http://harbor.platform.svc.cluster.local/api"
          kubectlKubeconfig kubectlSettings @?= ""
      , testCase
          "Engine client settings retain only Apple host artifact and messaging endpoints (Sprint 12.16)"
          $ do
            let lease = EdgePort.EdgePortLease {EdgePort.leasedPort = 9092, EdgePort.leasedHost = "127.0.0.1"}
                publication = Publication.publicationWithLeasedPort lease (Publication.defaultPublication AppleSilicon)
                hostConfig = hostBootConfigForPublication publication
                settings = ServiceClients.engineClientSettingsForBootConfig hostConfig
                minioSettings = ServiceClients.engineMinIOSettings settings
                pulsarSettings = ServiceClients.enginePulsarSettings settings
                rendered = ServiceClients.renderEngineClientSettings settings
            MinIOSubprocess.minioEndpoint minioSettings @?= "http://127.0.0.1:9092"
            MinIOSubprocess.minioRequestPathPrefix minioSettings @?= "/minio/s3"
            PulsarWebSocketSubprocess.pulsarWebSocketEndpoint pulsarSettings
              @?= "ws://127.0.0.1:9092/pulsar/ws"
            assertBool "Engine settings omit Harbor" (not ("harbor" `Text.isInfixOf` Text.toLower rendered))
            assertBool "Engine settings omit kubectl" (not ("kubectl" `Text.isInfixOf` Text.toLower rendered))
      , testCase "CpuFeatures detection picks the right oneDNN micro-kernel knob" $ do
          features <- detectCpuFeatures
          assertBool
            "detected vendor is one of the known classes"
            (cpuVendor features `elem` ["apple-silicon", "intel-or-amd", "intel", "amd", "unknown"])
          let knob = microKernelChoice features
          assertBool
            "selected knob is one of the linuxCpuKnobs micro-kernel axis choices"
            (knob `elem` ["onednn-jit-avx512", "onednn-jit-avx2", "onednn-reference"])
      , testCase "oneDNN runtime probe reports pkg-config and link visibility" $ do
          probe <- OneDnnRuntime.probeOneDnnRuntime
          let rendered = OneDnnRuntime.renderOneDnnRuntimeProbe probe
          assertBool
            "probe render includes oneDNN runtime section"
            ("onednn_runtime:" `Text.isInfixOf` rendered)
          assertBool
            "probe records pkg-config attempts"
            (any ("pkg-config --modversion" `Text.isInfixOf`) (OneDnnRuntime.oneDnnRuntimeProbeLog probe))
          assertBool
            "probe records header visibility attempts"
            (any ("test -r /usr/include" `Text.isInfixOf`) (OneDnnRuntime.oneDnnRuntimeProbeLog probe))
          assertBool
            "probe records dynamic-linker visibility"
            (any ("ldconfig -p:" `Text.isInfixOf`) (OneDnnRuntime.oneDnnRuntimeProbeLog probe))
      , testCase "CUDA runtime probe reports toolchain, device, and link visibility attempts" $ do
          probe <- CudaRuntime.probeCudaRuntime
          let rendered = CudaRuntime.renderCudaRuntimeProbe probe
          assertBool
            "probe render includes CUDA runtime section"
            ("cuda_runtime:" `Text.isInfixOf` rendered)
          assertBool
            "probe records nvcc attempt"
            (any ("nvcc --version:" `Text.isInfixOf`) (CudaRuntime.cudaRuntimeProbeLog probe))
          assertBool
            "probe records nvidia-smi attempt"
            (any ("nvidia-smi -L:" `Text.isInfixOf`) (CudaRuntime.cudaRuntimeProbeLog probe))
          assertBool
            "probe records dynamic-linker visibility"
            (any ("ldconfig -p:" `Text.isInfixOf`) (CudaRuntime.cudaRuntimeProbeLog probe))
      , testCase "Metal runtime probe avoids Swift/Xcode compiler attempts" $ do
          probe <- MetalRuntime.probeMetalRuntime
          let rendered = MetalRuntime.renderMetalRuntimeProbe probe
          assertBool
            "probe render includes Metal runtime section"
            ("metal_runtime:" `Text.isInfixOf` rendered)
          assertBool
            "probe does not invoke swift"
            (not (any ("swift --version:" `Text.isInfixOf`) (MetalRuntime.metalRuntimeProbeLog probe)))
          assertBool
            "probe does not invoke xcrun"
            (not (any ("xcrun -find" `Text.isInfixOf`) (MetalRuntime.metalRuntimeProbeLog probe)))
          assertBool
            "probe records Metal device visibility attempt"
            ( any
                ("system_profiler SPDisplaysDataType:" `Text.isInfixOf`)
                (MetalRuntime.metalRuntimeProbeLog probe)
            )
      , testCase "spawned ./.build/jitml binary matrix against a real workdir" $
          -- Spawns the real `jitml` binary in a temp workdir, exercising the
          -- typed Subprocess boundary against the actual executable (not the
          -- library API). Covers the canonical Sprint 12.2 matrix: --help,
          -- bootstrap --dry-run, cluster up --dry-run, service --help,
          -- train --dry-run experiments/mnist.dhall, and the Sprint 9.7
          -- TPE tuning Dhall render path.
          withSystemTempDirectory "jitml-spawned-bin" $ \workdir -> do
            jitmlBinary <- locateJitmlBinary
            case jitmlBinary of
              Nothing ->
                assertFailure
                  "jitml binary not found; spawned-binary integration matrix requires a built executable"
              Just binary -> do
                let runJitml args = do
                      let cmd =
                            (subprocess binary args)
                              { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just workdir
                              }
                      runStreaming defaultSubprocessEnv cmd
                -- --help
                helpOutcome <- runJitml ["--help"]
                assertProcessExitCode "--help" ExitSuccess helpOutcome
                assertProcessStreamContains "--help mentions Usage" ProcessStdout "Usage:" helpOutcome
                -- bootstrap --linux-cpu --dry-run
                bootOutcome <- runJitml ["bootstrap", "--linux-cpu", "--dry-run"]
                assertProcessExitCode "bootstrap --dry-run" ExitSuccess bootOutcome
                assertProcessStreamContains
                  "bootstrap --dry-run emits the typed Plan"
                  ProcessStdout
                  "Command: jitml bootstrap"
                  bootOutcome
                -- cluster up --substrate linux-cpu --dry-run
                clusterOutcome <-
                  runJitml ["cluster", "up", "--substrate", "linux-cpu", "--dry-run"]
                assertProcessExitCode "cluster up --dry-run" ExitSuccess clusterOutcome
                assertProcessStreamContains
                  "cluster up --dry-run emits the typed Plan"
                  ProcessStdout
                  "Command: jitml cluster up"
                  clusterOutcome
                -- Sprint 3.7 — status must fail closed when no live
                -- publication with readiness evidence exists.
                missingStatusOutcome <- runJitml ["cluster", "status"]
                assertProcessExitCode "missing cluster status" (ExitFailure 2) missingStatusOutcome
                assertProcessStreamContains
                  "missing publication is not reported ready"
                  ProcessStderr
                  "cluster publication is missing"
                  missingStatusOutcome
                let runtimeRoot = workdir </> ".build" </> "runtime"
                    publicationPath = runtimeRoot </> "cluster-publication.json"
                createDirectoryIfMissing True runtimeRoot
                ByteString.Lazy.writeFile
                  publicationPath
                  (Aeson.encode (Publication.defaultPublication LinuxCPU))
                defaultStatusOutcome <- runJitml ["cluster", "status"]
                assertProcessExitCode "default cluster status" (ExitFailure 2) defaultStatusOutcome
                assertProcessStreamContains
                  "default-ready publication without evidence is rejected"
                  ProcessStderr
                  "no live readiness evidence"
                  defaultStatusOutcome
                ByteString.Lazy.writeFile publicationPath "not-json"
                corruptStatusOutcome <- runJitml ["cluster", "status"]
                assertProcessExitCode "corrupt cluster status" (ExitFailure 2) corruptStatusOutcome
                assertProcessStreamContains
                  "corrupt publication is rejected"
                  ProcessStderr
                  "cluster publication is corrupt"
                  corruptStatusOutcome
                -- internal gc <hash> exits 3 on no-op
                gcOutcome <- runJitml ["internal", "gc", "some-experiment-hash"]
                assertProcessExitCode "gc no-op" (ExitFailure 3) gcOutcome
                -- Unsafe user-supplied experiment hashes must render through
                -- InvalidConfig, not the local object-key guard.
                badGcOutcome <- runJitml ["internal", "gc", "../escape"]
                assertProcessExitCode "unsafe gc hash" (ExitFailure 2) badGcOutcome
                assertProcessStreamContains
                  "unsafe gc hash renders invalid config"
                  ProcessStderr
                  "invalid config: gc manifest scan: unsafe object key"
                  badGcOutcome
                -- service --help prints the daemon usage line
                serviceOutcome <- runJitml ["service", "--help"]
                assertProcessExitCode "service --help" ExitSuccess serviceOutcome
                assertProcessStreamContains
                  "service --help mentions the daemon"
                  ProcessStdout
                  "Run the jitML daemon"
                  serviceOutcome
                assertProcessStreamContains
                  "service --help exposes the bounded consumer validation mode"
                  ProcessStdout
                  "--consume-once"
                  serviceOutcome
                -- train --dry-run experiments/mnist.dhall emits the typed Plan
                -- (resolve the path against the repo root, not the temp workdir).
                experimentPath <- makeAbsolute "experiments/mnist.dhall"
                trainOutcome <- runJitml ["train", "--dry-run", Text.pack experimentPath]
                assertProcessExitCode "train --dry-run" ExitSuccess trainOutcome
                assertProcessStreamContains
                  "train --dry-run emits the decode-experiment step"
                  ProcessStdout
                  "decode-experiment"
                  trainOutcome
                tunePath <- makeAbsolute "experiments/mnist-tune.dhall"
                tuneOfflineOutcome <- runJitml ["tune", Text.pack tunePath]
                assertProcessExitCode "offline tune" (ExitFailure 2) tuneOfflineOutcome
                assertProcessStreamContains
                  "offline tune requires a live cluster publication"
                  ProcessStderr
                  "no live cluster publication"
                  tuneOfflineOutcome
                tunePlanOutcome <-
                  runJitml ["tune", Text.pack tunePath, "--dry-run"]
                assertProcessExitCode "tune --dry-run" ExitSuccess tunePlanOutcome
                assertProcessStreamContains
                  "TPE Dhall tune --dry-run emits the typed decode step"
                  ProcessStdout
                  "decode-tuning"
                  tunePlanOutcome
                assertProcessStreamContains
                  "TPE Dhall tune --dry-run preserves the selected config path"
                  ProcessStdout
                  (Text.pack tunePath)
                  tunePlanOutcome
                -- Sprint 8.10 — `jitml train` is substrate-backed and fails
                -- closed offline: with no live cluster publication it exits
                -- non-zero with a typed `TrainingPrerequisiteUnmet` diagnostic
                -- and prints no synthetic summary. The `--substrate` / `--seed`
                -- override parse still runs first (the invalid-substrate case
                -- below proves the parser path); a valid offline run no longer
                -- prints a summary because there is nothing real to report.
                trainOfflineOutcome <-
                  runJitml
                    [ "train"
                    , Text.pack experimentPath
                    , "--substrate"
                    , "linux-cpu"
                    , "--seed"
                    , "42"
                    ]
                assertProcessNotSuccessful "offline train fails closed" trainOfflineOutcome
                assertProcessStreamNotContains
                  "offline train prints no synthetic final_loss summary"
                  ProcessStdout
                  "final_loss"
                  trainOfflineOutcome
                assertProcessStreamContains
                  "offline train diagnostic names the unmet training prerequisite"
                  ProcessStderr
                  "training prerequisite unmet"
                  trainOfflineOutcome
                -- Sprint 1.12 — tune with --sampler / --trials overrides
                -- preserves those CLI inputs in the side-effect-free typed
                -- Plan/Apply rendering. Executed trial artifacts remain a
                -- live-cluster-only surface.
                tuneOverrideOutcome <-
                  runJitml
                    [ "tune"
                    , Text.pack tunePath
                    , "--sampler"
                    , "Sobol"
                    , "--trials"
                    , "2"
                    , "--dry-run"
                    ]
                assertProcessExitCode "tune overrides --dry-run" ExitSuccess tuneOverrideOutcome
                assertProcessStreamContains
                  "tune rendered plan uses overridden sampler"
                  ProcessStdout
                  "sampler: Sobol"
                  tuneOverrideOutcome
                assertProcessStreamContains
                  "tune rendered plan uses overridden trial count"
                  ProcessStdout
                  "trials: 2"
                  tuneOverrideOutcome
                -- Trial-only overrides normalize inherited/default
                -- parallelism to a possible cohort. An explicit invalid
                -- parallelism remains authoritative and must fail plan
                -- refinement rather than being silently rewritten.
                explicitInvalidParallelismOutcome <-
                  runJitml
                    [ "tune"
                    , Text.pack tunePath
                    , "--trials"
                    , "2"
                    , "--parallelism"
                    , "8"
                    ]
                assertProcessNotSuccessful
                  "explicit invalid tune parallelism fails closed"
                  explicitInvalidParallelismOutcome
                assertProcessStreamContains
                  "explicit invalid tune parallelism names the execution-spec invariant"
                  ProcessStderr
                  "tuning parallelism exceeds trial count"
                  explicitInvalidParallelismOutcome
                -- Sprint 1.12 — bare substrate aliases (cpu, cuda) fail
                -- closed with a typed diagnostic naming the canonical
                -- identifiers per Plan Standards rule B.
                badSubstrateOutcome <-
                  runJitml
                    [ "train"
                    , Text.pack experimentPath
                    , "--substrate"
                    , "cpu"
                    ]
                assertProcessNotSuccessful "invalid --substrate exits non-zero" badSubstrateOutcome
                let diagnostic = processStream ProcessStderr badSubstrateOutcome
                if "apple-silicon" `Text.isInfixOf` diagnostic
                  || "linux-cpu" `Text.isInfixOf` diagnostic
                  then pure ()
                  else
                    assertFailure
                      ( "invalid --substrate diagnostic names no canonical identifier:\n"
                          <> Text.unpack (renderProcessOutcome badSubstrateOutcome)
                      )
      , testCase "SelfPlayBuffer round-trips through filesystem HasMinIO (Sprint 9.5)" $
          -- Writes a deterministic SelfPlayBuffer to the typed `HasMinIO`
          -- filesystem instance, reads it back, and asserts the
          -- transcript hash is stable across the round-trip. Closes the
          -- MinIO checkpoint round-trip half of Sprint 9.5.
          withSystemTempDirectory "jitml-selfplay-roundtrip" $ \root ->
            runFilesystemMinIO root $ do
              let buffer =
                    SelfPlay.runSelfPlay
                      ( SelfPlay.defaultSelfPlayConfig
                          { SelfPlay.selfPlayGamesPerGeneration = 3
                          , SelfPlay.selfPlaySimulationsPerMove = 2
                          }
                      )
                  bucket = BucketName "jitml-checkpoints"
                  bufferKey = ObjectRef bucket (ObjectKey ("selfplay/" <> SelfPlay.bufferTranscriptHash buffer <> ".cbor"))
                  -- Serialise the buffer by its transcript hash (the canonical
                  -- content-addressed key it would land at in MinIO).
                  payload = "selfplay-buffer:" <> SelfPlay.bufferTranscriptHash buffer
              first <- putBlobIfAbsent bufferKey payload
              case first of
                Right (ETag _) -> pure ()
                Left err ->
                  liftIO (assertFailure ("expected first putBlobIfAbsent OK, got: " <> show err))
              -- Re-derive the buffer with the same seed and assert hash equality.
              let buffer2 =
                    SelfPlay.runSelfPlay
                      ( SelfPlay.defaultSelfPlayConfig
                          { SelfPlay.selfPlayGamesPerGeneration = 3
                          , SelfPlay.selfPlaySimulationsPerMove = 2
                          }
                      )
              liftIO $
                SelfPlay.bufferTranscriptHash buffer @?= SelfPlay.bufferTranscriptHash buffer2
              liftIO $
                SelfPlay.bufferLength buffer @?= 3
      , testCase "SelfPlayBuffer CBOR round-trip via writeSelfPlayBuffer / readSelfPlayBuffer (Sprint 13.9)" $
          -- Sprint 13.9 — write a deterministic SelfPlayBuffer through the
          -- new `writeSelfPlayBuffer` helper (CBOR-encoded via
          -- `Codec.Serialise`) and read it back via `readSelfPlayBuffer`.
          -- Asserts the round-tripped buffer is structurally equal to the
          -- original (not just hash-equal). Validates the CBOR codec for
          -- `SelfPlayBuffer`, `SelfPlayGame`, and `GameState` against the
          -- typed `HasMinIO` filesystem boundary.
          withSystemTempDirectory "jitml-selfplay-cbor" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-selfplay-cbor"
                  buffer =
                    SelfPlay.runSelfPlay
                      ( SelfPlay.defaultSelfPlayConfig
                          { SelfPlay.selfPlayGamesPerGeneration = 3
                          , SelfPlay.selfPlaySimulationsPerMove = 2
                          }
                      )
                  contentHash = SelfPlay.bufferTranscriptHash buffer
              writeResult <- SelfPlay.writeSelfPlayBuffer experimentHash buffer
              liftIO $ case writeResult of
                Right (ETag _) -> pure ()
                Left err ->
                  assertFailure ("expected writeSelfPlayBuffer OK, got: " <> show err)
              readResult <- SelfPlay.readSelfPlayBuffer experimentHash contentHash
              liftIO $ case readResult of
                Right buffer' -> do
                  buffer' @?= buffer
                  SelfPlay.bufferTranscriptHash buffer' @?= contentHash
                Left err ->
                  assertFailure ("expected readSelfPlayBuffer OK, got: " <> Text.unpack err)
      , testCase "GC reaping deletes manifests + blobs through HasMinIO (Sprint 10.3)" $
          withSystemTempDirectory "jitml-gc-reap" $ \root ->
            runFilesystemMinIO root $ do
              -- Seed three manifests; LastN 1 should reap the older two.
              let experimentHash = "exp-gc"
                  mkManifest tag step =
                    ( Checkpoint.emptyManifest
                        tag
                        experimentHash
                        [Checkpoint.TensorBlob ("t-" <> tag) [1] ("blob-" <> tag)]
                    )
                      { Checkpoint.manifestStep = step
                      }
                  manifests =
                    [ mkManifest "old1" 1
                    , mkManifest "old2" 2
                    , mkManifest "fresh" 3
                    ]
              -- Seed manifest + blob objects in MinIO.
              mapM_
                ( \m -> do
                    let manifestSha = Checkpoint.manifestContentSha m
                        manifestObjRef =
                          CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experimentHash manifestSha)
                    _ <-
                      putBlobIfAbsent
                        manifestObjRef
                        (Text.pack (show m))
                    case Checkpoint.manifestTensors m of
                      [tensor] -> do
                        let blobObjRef =
                              CheckpointStore.checkpointObjectRef
                                (Checkpoint.blobKey experimentHash (Checkpoint.tensorBlobKey tensor))
                        _ <- putBlobIfAbsent blobObjRef "weights"
                        pure ()
                      tensors ->
                        liftIO $
                          assertFailure
                            ("expected one tensor in seeded GC manifest, got: " <> show (length tensors))
                )
                manifests
              let plan = CheckpointStore.buildGcPlan experimentHash (CheckpointStore.LastN 1) manifests []
              liftIO (length (CheckpointStore.gcReapEvents plan) @?= 2)
              result <- CheckpointStore.executeGcPlan plan
              liftIO $ do
                CheckpointStore.gcExecutedReapedManifests result @?= 2
                CheckpointStore.gcExecutedReapedBlobs result @?= 2
                CheckpointStore.gcExecutedDeleteFailures result @?= []
      , testCase
          "legacy generic loadInferenceCheckpointWithWeights via HasMinIO round-trips (Sprint 10.4/10.5)"
          $ withSystemTempDirectory "jitml-inference-load"
          $ \root -> do
            env <- buildEnv defaultGlobalFlags
            runFilesystemMinIO root $ do
              let experimentHash = "exp-inf"
                  blobObjectKey = Checkpoint.blobKey experimentHash "blob-weights"
                  manifest =
                    completedCheckpointManifest
                      "m1"
                      experimentHash
                      [Checkpoint.TensorBlob "dense" [2, 2] blobObjectKey]
                      1
                      [("validation_accuracy", 0.91)]
                  manifestSha = Checkpoint.manifestContentSha manifest
                  bucket = BucketName "jitml-checkpoints"
                  manifestRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experimentHash manifestSha)
                  pointerRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experimentHash)
                  blobRef = CheckpointStore.checkpointObjectRef blobObjectKey
                  manifestBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor manifest)
                  weightBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0])
              liftIO $
                CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experimentHash)
                  @?= ObjectRef bucket (ObjectKey (experimentHash <> "/pointers/latest"))
              _ <- putBlobBytesIfAbsent blobRef weightBytes
              _ <- putBlobBytesIfAbsent manifestRef manifestBytes
              _ <- casPointer pointerRef Nothing manifestSha
              ffiInferred <-
                CheckpointStore.loadInferenceCheckpointWith
                  (\_modelRef loadedManifest values -> liftIO (runVisibleCheckpointInference env loadedManifest values))
                  experimentHash
                  [1.0, 2.0, 3.0]
              liftIO $
                ffiInferred @?= Right [1.0, 2.0, 3.0]
              weightedInferred <-
                CheckpointStore.loadInferenceCheckpointWithWeights
                  ( \_modelRef loadedManifest loadedWeights values ->
                      liftIO
                        ( runVisibleWeightedCheckpointInference
                            env
                            loadedManifest
                            loadedWeights
                            values
                        )
                  )
                  experimentHash
                  [1.0, 2.0, 3.0]
              -- Sprint 13.11 — the weighted runner now drives a real
              -- oneDNN Dense2D GEMM `out = input · W` against the
              -- caller-supplied weights, not the prior smoke-fixture
              -- identity+bias. The staged weight buffer [1,2,3,4]
              -- is reshaped as a 3×3 row-major matrix (n=3 from the
              -- input length, padded with zeros to fill the matmul
              -- shape):
              --   W = [[1, 2, 3], [4, 0, 0], [0, 0, 0]]
              -- and input [1, 2, 3] × W produces [9, 2, 3].
              liftIO $
                weightedInferred @?= Right [9.0, 2.0, 3.0]
              graph <- liftIO (either (assertFailure . Text.unpack) pure layerGraphCheckpointFixture)
              let graphExperimentHash = "exp-inf-layergraph"
                  graphWeightKey = Checkpoint.blobKey graphExperimentHash "graph-dense-weights"
                  graphBiasKey = Checkpoint.blobKey graphExperimentHash "graph-dense-bias"
                  graphTensors =
                    [ Checkpoint.TensorBlob "graph-dense.weights" [2, 3] graphWeightKey
                    , Checkpoint.TensorBlob "graph-dense.bias" [2] graphBiasKey
                    ]
                  graphManifest =
                    -- This exercises the legacy generic LayerGraph loader;
                    -- canonical supervised execution is covered by exact V2
                    -- runtime-artifact tests, never by a V1 graph fixture.
                    ( completedCheckpointManifest
                        "m-layergraph"
                        graphExperimentHash
                        graphTensors
                        1
                        [("validation_accuracy", 0.91)]
                    )
                      { Checkpoint.manifestModelFamily = Checkpoint.GenericModelFamily
                      , Checkpoint.manifestArchitecture =
                          (Checkpoint.defaultArchitectureMetadata Checkpoint.GenericModelFamily)
                            { Checkpoint.architectureName = "graph-dense"
                            , Checkpoint.architectureInputs = [Checkpoint.TensorSpec "input" [3] "F64"]
                            , Checkpoint.architectureOutputs = [Checkpoint.TensorSpec "logits" [2] "F64"]
                            , Checkpoint.architectureLayerGraph =
                                Just (Checkpoint.layerGraphMetadataFromGraph graph)
                            }
                      , Checkpoint.manifestWeightLayout =
                          Checkpoint.NamedTensorWeightLayout (fmap Checkpoint.tensorSpecFromBlob graphTensors)
                      }
                  graphManifestSha = Checkpoint.manifestContentSha graphManifest
                  graphManifestRef =
                    CheckpointStore.checkpointObjectRef
                      (Checkpoint.manifestKey graphExperimentHash graphManifestSha)
                  graphPointerRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey graphExperimentHash)
              _ <-
                putBlobBytesIfAbsent
                  (CheckpointStore.checkpointObjectRef graphWeightKey)
                  (ByteString.Lazy.toStrict (Checkpoint.encodeJmw1 [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]))
              _ <-
                putBlobBytesIfAbsent
                  (CheckpointStore.checkpointObjectRef graphBiasKey)
                  (ByteString.Lazy.toStrict (Checkpoint.encodeJmw1 [0.5, -0.5]))
              _ <-
                putBlobBytesIfAbsent
                  graphManifestRef
                  (ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor graphManifest))
              _ <- casPointer graphPointerRef Nothing graphManifestSha
              graphInferred <-
                CheckpointStore.loadInferenceCheckpointWithWeights
                  ( \_modelRef loadedManifest loadedWeights values ->
                      liftIO
                        ( runVisibleWeightedCheckpointInference
                            env
                            loadedManifest
                            loadedWeights
                            values
                        )
                  )
                  graphExperimentHash
                  [1.0, 2.0, 3.0]
              liftIO $
                graphInferred @?= Right [1.5, 1.5]
              let partialExperimentHash = "exp-inf-partial"
                  partialBlobObjectKey = Checkpoint.blobKey partialExperimentHash "blob-weights"
                  partialManifest =
                    Checkpoint.emptyManifest
                      "m-partial"
                      partialExperimentHash
                      [Checkpoint.TensorBlob "dense" [2, 2] partialBlobObjectKey]
                  partialManifestSha = Checkpoint.manifestContentSha partialManifest
                  partialManifestRef =
                    CheckpointStore.checkpointObjectRef
                      (Checkpoint.manifestKey partialExperimentHash partialManifestSha)
                  partialPointerRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey partialExperimentHash)
                  partialBlobRef = CheckpointStore.checkpointObjectRef partialBlobObjectKey
                  partialManifestBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor partialManifest)
              _ <- putBlobBytesIfAbsent partialBlobRef weightBytes
              _ <- putBlobBytesIfAbsent partialManifestRef partialManifestBytes
              _ <- casPointer partialPointerRef Nothing partialManifestSha
              partialInference <-
                CheckpointStore.loadInferenceCheckpointWithWeights
                  ( \_modelRef loadedManifest loadedWeights values ->
                      liftIO
                        ( runVisibleWeightedCheckpointInference
                            env
                            loadedManifest
                            loadedWeights
                            values
                        )
                  )
                  partialExperimentHash
                  [1.0, 2.0, 3.0]
              liftIO $
                case partialInference of
                  Left err ->
                    assertBool
                      "partial checkpoint rejected before weight inference"
                      ("not inference eligible" `Text.isInfixOf` err)
                  Right values ->
                    assertFailure ("partial checkpoint unexpectedly inferred: " <> show values)
              let badExperimentHash = "exp-inf-shape-mismatch"
                  badBlobObjectKey = Checkpoint.blobKey badExperimentHash "blob-weights"
                  badManifest =
                    completedCheckpointManifest
                      "m-bad"
                      badExperimentHash
                      [Checkpoint.TensorBlob "dense" [2, 3] badBlobObjectKey]
                      1
                      [("validation_accuracy", 0.91)]
                  badManifestSha = Checkpoint.manifestContentSha badManifest
                  badManifestRef =
                    CheckpointStore.checkpointObjectRef
                      (Checkpoint.manifestKey badExperimentHash badManifestSha)
                  badPointerRef =
                    CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey badExperimentHash)
                  badBlobRef = CheckpointStore.checkpointObjectRef badBlobObjectKey
                  badManifestBytes =
                    ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor badManifest)
              _ <- putBlobBytesIfAbsent badBlobRef weightBytes
              _ <- putBlobBytesIfAbsent badManifestRef badManifestBytes
              _ <- casPointer badPointerRef Nothing badManifestSha
              shapeMismatch <-
                CheckpointStore.loadInferenceCheckpointWithWeights
                  ( \_modelRef loadedManifest loadedWeights values ->
                      liftIO
                        ( runVisibleWeightedCheckpointInference
                            env
                            loadedManifest
                            loadedWeights
                            values
                        )
                  )
                  badExperimentHash
                  [1.0, 2.0, 3.0]
              liftIO $
                case shapeMismatch of
                  Left err ->
                    assertBool
                      "shape mismatch should fail closed"
                      ("weight blob incompatible for dense" `Text.isInfixOf` err)
                  Right values ->
                    assertFailure
                      ("expected shape mismatch failure, got: " <> show values)
      , testCase "inference loader rejects illegal manifests before weight or runner IO (Sprint 21.3)" $
          withSystemTempDirectory "jitml-inference-fail-closed" $ \root ->
            runFilesystemMinIO root $ do
              let tensorFor experimentHash label =
                    Checkpoint.TensorBlob
                      ("dense-" <> label)
                      [2, 2]
                      (Checkpoint.blobKey experimentHash ("blob-" <> label))
                  declaredManifest experimentHash =
                    Checkpoint.emptyManifest
                      "m-declared"
                      experimentHash
                      [tensorFor experimentHash "declared"]
                  partialManifest experimentHash =
                    ( Checkpoint.emptyManifest
                        "m-partial"
                        experimentHash
                        [tensorFor experimentHash "partial"]
                    )
                      { Checkpoint.manifestStep = 1
                      , Checkpoint.manifestMetrics = [("accuracy", 0.75)]
                      }
                  syntheticManifest experimentHash =
                    ( completedCheckpointManifest
                        "m-synthetic"
                        experimentHash
                        [tensorFor experimentHash "synthetic"]
                        1
                        [("validation_accuracy", 0.95)]
                    )
                      { Checkpoint.manifestInitialWeightHash = Nothing
                      , Checkpoint.manifestFinalWeightHash = Nothing
                      , Checkpoint.manifestUpdateCount = Nothing
                      , Checkpoint.manifestDatasetShaAtRead = Nothing
                      }
                  seededManifest experimentHash =
                    ( Checkpoint.emptyManifest
                        "m-seeded"
                        experimentHash
                        [tensorFor experimentHash "seeded"]
                    )
                      { Checkpoint.manifestStep = 1
                      , Checkpoint.manifestMetrics =
                          [ ("panel_seeded_policy_value", 1.0)
                          , ("seed", 2006.0)
                          ]
                      }
                  failedManifest experimentHash =
                    ( Checkpoint.emptyManifest
                        "m-failed"
                        experimentHash
                        [tensorFor experimentHash "failed"]
                    )
                      { Checkpoint.manifestStep = 1
                      , Checkpoint.manifestMetrics = [("accuracy", 0.0)]
                      }
                  stage experimentHash manifest = do
                    let manifestSha = Checkpoint.manifestContentSha manifest
                        manifestRef =
                          CheckpointStore.checkpointObjectRef
                            (Checkpoint.manifestKey experimentHash manifestSha)
                        pointerRef =
                          CheckpointStore.checkpointObjectRef
                            (Checkpoint.latestPointerKey experimentHash)
                        manifestBytes =
                          ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor manifest)
                    _ <- putBlobBytesIfAbsent manifestRef manifestBytes
                    _ <- casPointer pointerRef Nothing manifestSha
                    pure ()
                  rejectCase (label, experimentHash, manifest, expected) = do
                    stage experimentHash manifest
                    runnerInvoked <- liftIO (newIORef False)
                    result <-
                      CheckpointStore.loadInferenceCheckpointWithWeights
                        ( \_modelRef _manifest _weights _values -> do
                            liftIO (modifyIORef' runnerInvoked (const True))
                            pure (Right [])
                        )
                        experimentHash
                        [1.0, 2.0, 3.0]
                    invoked <- liftIO (readIORef runnerInvoked)
                    liftIO $ do
                      invoked @?= False
                      case result of
                        Left err ->
                          assertBool
                            (Text.unpack label)
                            (expected `Text.isInfixOf` err)
                        Right values ->
                          assertFailure
                            ( "illegal manifest inferred for "
                                <> Text.unpack label
                                <> ": "
                                <> show values
                            )
              traverse_
                rejectCase
                [
                  ( "declared manifest"
                  , "exp-21-declared"
                  , declaredManifest "exp-21-declared"
                  , "no completed-training witness"
                  )
                ,
                  ( "partial manifest"
                  , "exp-21-partial"
                  , partialManifest "exp-21-partial"
                  , "no completed-training witness"
                  )
                ,
                  ( "synthetic manifest"
                  , "exp-21-synthetic"
                  , syntheticManifest "exp-21-synthetic"
                  , "missing weight-delta evidence"
                  )
                ,
                  ( "seeded manifest"
                  , "exp-21-seeded"
                  , seededManifest "exp-21-seeded"
                  , "no completed-training witness"
                  )
                ,
                  ( "failed-training manifest"
                  , "exp-21-failed"
                  , failedManifest "exp-21-failed"
                  , "no completed-training witness"
                  )
                ]
      , testCase
          "supervised V1 manifests retain inspection evidence but fail completion refinement (Sprint 24.3)"
          $ do
            let manifests =
                  [ supervisedCompletedManifestFor
                      ("exp-24-3-complete-" <> SL.problemName problem)
                      problem
                  | problem <- SL.canonicalProblems
                  ]
            traverse_
              ( \manifest -> do
                  Checkpoint.validateSupervisedManifestShapeLayout manifest @?= []
                  case Checkpoint.manifestCompletedTraining manifest of
                    Nothing ->
                      assertFailure
                        ( "missing CompletedTraining for "
                            <> Text.unpack (Checkpoint.manifestId manifest)
                        )
                    Just completed -> do
                      Checkpoint.manifestInitialWeightHash manifest
                        @?= Just (TrainingBudget.completedTrainingInitialWeightHash completed)
                      Checkpoint.manifestFinalWeightHash manifest
                        @?= Just (TrainingBudget.completedTrainingFinalWeightHash completed)
                      Checkpoint.manifestUpdateCount manifest
                        @?= Just (TrainingBudget.completedTrainingUpdateCount completed)
                      Checkpoint.manifestDatasetShaAtRead manifest
                        @?= Just (TrainingBudget.completedTrainingDatasetShaAtRead completed)
                      assertBool
                        "supervised manifest records convergence metrics"
                        (not (null (TrainingBudget.completedTrainingMetrics completed)))
                      case Checkpoint.validateCheckpointCompletion manifest of
                        Left Checkpoint.SupervisedRuntimeArtifactMissing -> pure ()
                        Left err ->
                          assertFailure
                            ( "expected categorical supervised V1 inspection-only rejection, got: "
                                <> Text.unpack (Checkpoint.renderCheckpointCompletionValidationError err)
                            )
                        Right _ ->
                          assertFailure
                            "supervised V1 manifest unexpectedly satisfied completion refinement"
              )
              manifests
      , testCase
          "supervised V1 loader categorically rejects all historical family manifests before IO (Sprint 24.3)"
          $ withSystemTempDirectory "jitml-supervised-manifest-reject"
          $ \root ->
            runFilesystemMinIO root $
              traverse_
                ( \problem ->
                    traverse_
                      (rejectSupervisedManifestCase problem)
                      (supervisedIllegalManifestCases problem)
                )
                SL.canonicalProblems
      , testCase "checkpoint browse serving selection requires Store admission" $ do
          let experimentHash = "exp-checkpoint-browser-negative"
              completeBlob = Checkpoint.blobKey experimentHash "blob-complete"
              partialBlob = Checkpoint.blobKey experimentHash "blob-partial"
              syntheticBlob = Checkpoint.blobKey experimentHash "blob-synthetic"
              seededBlob = Checkpoint.blobKey experimentHash "blob-seeded"
              failedBlob = Checkpoint.blobKey experimentHash "blob-failed"
              completedManifest =
                completedCheckpointManifest
                  "m-complete"
                  experimentHash
                  [Checkpoint.TensorBlob "dense" [2, 2] completeBlob]
                  3
                  [("validation_accuracy", 0.95)]
              partialManifest =
                ( Checkpoint.emptyManifest
                    "m-partial"
                    experimentHash
                    [Checkpoint.TensorBlob "dense" [2, 2] partialBlob]
                )
                  { Checkpoint.manifestStep = 3
                  , Checkpoint.manifestMetrics = [("accuracy", 0.95)]
                  }
              syntheticManifest =
                ( completedCheckpointManifest
                    "m-synthetic"
                    experimentHash
                    [Checkpoint.TensorBlob "dense" [2, 2] syntheticBlob]
                    3
                    [("validation_accuracy", 0.95)]
                )
                  { Checkpoint.manifestInitialWeightHash = Nothing
                  , Checkpoint.manifestFinalWeightHash = Nothing
                  , Checkpoint.manifestUpdateCount = Nothing
                  , Checkpoint.manifestDatasetShaAtRead = Nothing
                  }
              seededManifest =
                ( Checkpoint.emptyManifest
                    "m-seeded"
                    experimentHash
                    [Checkpoint.TensorBlob "dense" [2, 2] seededBlob]
                )
                  { Checkpoint.manifestStep = 3
                  , Checkpoint.manifestMetrics =
                      [ ("panel_seeded_policy_value", 1.0)
                      , ("seed", 2006.0)
                      ]
                  }
              failedManifest =
                ( Checkpoint.emptyManifest
                    "m-failed"
                    experimentHash
                    [Checkpoint.TensorBlob "dense" [2, 2] failedBlob]
                )
                  { Checkpoint.manifestStep = 3
                  , Checkpoint.manifestMetrics = [("accuracy", 0.0)]
                  }
              completedSha = Checkpoint.manifestContentSha completedManifest
              partialSha = Checkpoint.manifestContentSha partialManifest
              syntheticSha = Checkpoint.manifestContentSha syntheticManifest
              seededSha = Checkpoint.manifestContentSha seededManifest
              failedSha = Checkpoint.manifestContentSha failedManifest
              summaries =
                [ Text.intercalate
                    "\t"
                    [ experimentHash
                    , experimentHash
                    , completedSha
                    , "3"
                    , "generic"
                    , "1"
                    , "eligible"
                    , "test-budget"
                    , "validation_accuracy=0.95"
                    , "jitml-tensorboard/test"
                    ]
                ]
              failClosedFrame =
                Workload.renderCheckpointListResult
                  "call-empty"
                  []
          source <- Text.IO.readFile "src/JitML/Service/Workload.hs"
          assertBool
            "serving browse does not re-admit immutable manifest addresses"
            ("CheckpointStore.admitCheckpointAt" `Text.isInfixOf` source)
          assertBool
            "serving browse does not require completed Store admission"
            ("CheckpointStore.requireAdmittedCompletedCheckpoint" `Text.isInfixOf` source)
          assertBool
            "serving browse bypasses Store via structural completion refinement"
            (not ("validateCheckpointCompletion" `Text.isInfixOf` source))
          length summaries @?= 1
          assertBool
            "completed checkpoint appears in browser selector summary"
            (any (completedSha `Text.isInfixOf`) summaries)
          assertBool
            "partial checkpoint is hidden from browser selector summary"
            (not (any (partialSha `Text.isInfixOf`) summaries))
          assertBool
            "synthetic checkpoint is hidden from browser selector summary"
            (not (any (syntheticSha `Text.isInfixOf`) summaries))
          assertBool
            "seeded checkpoint is hidden from browser selector summary"
            (not (any (seededSha `Text.isInfixOf`) summaries))
          assertBool
            "failed-training checkpoint is hidden from browser selector summary"
            (not (any (failedSha `Text.isInfixOf`) summaries))
          assertBool
            "selector summary carries the eligibility marker"
            (any ("\teligible\t" `Text.isInfixOf`) summaries)
          assertBool
            "empty selector frame is explicit fail-closed state"
            ("selector-state: fail-closed:no-inference-eligible-artifact" `Text.isInfixOf` failClosedFrame)
          assertBool
            "empty selector frame reports zero eligible checkpoints"
            ("count: 0" `Text.isInfixOf` failClosedFrame)
      , testCase "Dhall numerics schema decodes against the full Haskell catalog" $ do
          -- Decodes dhall/numerics/Schema.dhall through `Dhall.inputFile`
          -- and asserts the resulting NumericsCatalog matches the
          -- expected catalog generated from `JitML.Numerics.Catalog`. This
          -- is the Sprint 12.2 Dhall-to-typed-record decode coverage.
          catalog <- Numerics.loadNumericsCatalog "."
          Numerics.validateNumericsCatalog catalog @?= Right ()
      , testCase "Subprocess stdin pipes payload to the child process" $ do
          -- `cat` echoes stdin to stdout. The typed boundary's stdin
          -- payload (subprocessWithStdin) feeds bytes into the child.
          outcome <-
            runStreaming
              defaultSubprocessEnv
              (JitML.Sub.Subprocess.subprocessWithStdin "/bin/cat" [] "stdin-ok\n")
          assertProcessExitCode "stdin fixture" ExitSuccess outcome
          assertProcessStreamEquals "stdin fixture" ProcessStdout "stdin-ok\n" outcome
      , testCase "writeCheckpointSidecar puts TbCheckpointMarker via HasMinIO (Sprint 4.6)" $
          withSystemTempDirectory "jitml-tb-sidecar" $ \root ->
            runFilesystemMinIO root $ do
              let marker =
                    TensorBoard.TbCheckpointMarker
                      { TensorBoard.tcmStep = 200
                      , TensorBoard.tcmEpoch = 5
                      , TensorBoard.tcmManifestSha = "sha-tb-1"
                      , TensorBoard.tcmExperimentSha = "exp-tb"
                      , TensorBoard.tcmTrialSha = Nothing
                      , TensorBoard.tcmRunUuid = "run-tb"
                      , TensorBoard.tcmMetricsAtStep = [("loss", 0.42)]
                      }
              writeResult <-
                TbSidecar.writeCheckpointSidecar "exp-tb" 200 "sha-tb-1" marker
              case writeResult of
                Right _ -> pure ()
                Left err ->
                  liftIO (assertFailure ("expected sidecar PUT OK, got: " <> show err))
              let bucket = BucketName "jitml-tensorboard"
                  key = TensorBoard.checkpointSidecarKey "exp-tb" 200 "sha-tb-1"
                  ref = ObjectRef bucket (ObjectKey key)
              readback <- minioReadBytes ref
              liftIO $
                case readback of
                  Right bytes ->
                    assertBool
                      "TbCheckpointMarker round-trip CBOR is non-empty"
                      (Data.ByteString.length bytes > 0)
                  Left err ->
                    assertFailure ("expected sidecar read OK, got: " <> show err)
      , testCase "leaseEdgePort binds 127.0.0.1 on the first available candidate (Sprint 3.5)" $ do
          lease <- EdgePort.leaseEdgePort [49997, 49998, 49999]
          case lease of
            Just l -> do
              assertBool
                "leased port is one of the candidates"
                (EdgePort.leasedPort l `elem` [49997, 49998, 49999])
              EdgePort.leasedHost l @?= "127.0.0.1"
            Nothing -> assertFailure "expected at least one port to be bindable"
      , testCase "publicationWithLeasedPort rewrites edge_port + pulsar/minio URLs (Sprint 3.5)" $ do
          -- The bridge from `leaseEdgePort`'s probe to the JSON
          -- publication consumed by downstream substrates. The default
          -- per-substrate publication uses the canonical 9090; after
          -- the lease binds 9092, the publication's edge_port + Pulsar
          -- URL + MinIO URL all reflect the leased port.
          let lease = EdgePort.EdgePortLease {EdgePort.leasedPort = 9092, EdgePort.leasedHost = "127.0.0.1"}
              base = Publication.defaultPublication LinuxCPU
              relocated = Publication.publicationWithLeasedPort lease base
          Publication.publicationEdgePort relocated @?= 9092
          assertBool
            "pulsar URL carries the leased port"
            (":9092/pulsar" `Text.isInfixOf` Publication.publicationPulsarUrl relocated)
          assertBool
            "minio URL carries the leased port"
            (":9092/minio/s3" `Text.isInfixOf` Publication.publicationMinioUrl relocated)
          -- Substrate identity preserved.
          Publication.publicationSubstrate relocated @?= LinuxCPU
      , testCase "live publication requires exact role and public-edge readiness evidence" $ do
          let linuxBase = Publication.defaultPublication LinuxCPU
              linuxLive = Publication.markPublicationLive linuxBase
              missingCoordinator =
                linuxLive
                  { Publication.publicationComponents =
                      filter
                        ((/= "jitml-coordinator") . fst)
                        (Publication.publicationComponents linuxLive)
                  }
              duplicateCoordinator =
                linuxLive
                  { Publication.publicationComponents =
                      ("jitml-coordinator", "ready")
                        : Publication.publicationComponents linuxLive
                  }
              edgeNotReady =
                linuxLive
                  { Publication.publicationComponents =
                      [ if name == "edge" then (name, "not-ready") else (name, status)
                      | (name, status) <- Publication.publicationComponents linuxLive
                      ]
                  }
              appleBase = Publication.defaultPublication AppleSilicon
              appleLive = Publication.markPublicationLive appleBase
              appleWithFalseClusterEngine =
                appleLive
                  { Publication.publicationComponents =
                      ("jitml-engine", "ready")
                        : Publication.publicationComponents appleLive
                  }
          fmap fst (Publication.publicationComponents linuxBase)
            @?= Publication.requiredPublicationComponents LinuxCPU
          fmap fst (Publication.publicationComponents appleBase)
            @?= Publication.requiredPublicationComponents AppleSilicon
          assertBool
            "exact Engine, Coordinator, and edge rows should mint live evidence"
            (Publication.publicationHasLiveEvidence linuxLive)
          assertBool
            "a missing Coordinator row must invalidate a forged live marker"
            (not (Publication.publicationHasLiveEvidence missingCoordinator))
          assertBool
            "a duplicate Coordinator row must invalidate a forged live marker"
            (not (Publication.publicationHasLiveEvidence duplicateCoordinator))
          assertBool
            "a not-ready public edge row must invalidate a forged live marker"
            (not (Publication.publicationHasLiveEvidence edgeNotReady))
          validateLivePublication linuxLive @?= Right linuxLive
          traverse_
            ( \(label, invalidPublication) ->
                assertBool
                  (Text.unpack label <> " must fail the Live test publication gate")
                  ( case validateLivePublication invalidPublication of
                      Left _ -> True
                      Right _ -> False
                  )
            )
            [ ("missing Coordinator evidence", missingCoordinator)
            , ("duplicate Coordinator evidence", duplicateCoordinator)
            , ("not-ready public edge evidence", edgeNotReady)
            ]
          Publication.publicationEvidence (Publication.markPublicationLive edgeNotReady)
            @?= Nothing
          assertBool
            "Apple cluster publication should require Coordinator and edge readiness"
            (Publication.publicationHasLiveEvidence appleLive)
          assertBool
            "Apple publication must not claim the zero-replica clustered Engine"
            ( "jitml-engine"
                `notElem` fmap fst (Publication.publicationComponents appleLive)
            )
          assertBool
            "an extra false-ready Apple Engine row must invalidate live evidence"
            (not (Publication.publicationHasLiveEvidence appleWithFalseClusterEngine))
      , testCase "typed Kind presence probe matches the exact target cluster (Sprint 2.9 reopened)" $ do
          renderSubprocess Helm.kindGetClustersSubprocess @?= "kind get clusters"
          presentOutcome <-
            runStreaming
              defaultSubprocessEnv
              (subprocess "printf" ["jitml-linux-cpu\\njitml-linux-cuda\\n"])
          resolveKindClusterPresence LinuxCPU presentOutcome
            @?= Right KindClusterPresent
          similarlyNamedOutcome <-
            runStreaming
              defaultSubprocessEnv
              (subprocess "printf" ["jitml-linux-cpu-backup\\n"])
          resolveKindClusterPresence LinuxCPU similarlyNamedOutcome
            @?= Right KindClusterAbsent
          emptyOutcome <-
            runStreaming
              defaultSubprocessEnv
              (subprocess "printf" ["No kind clusters found.\\n"])
          resolveKindClusterPresence LinuxCPU emptyOutcome
            @?= Right KindClusterAbsent
          failedOutcome <-
            runStreaming defaultSubprocessEnv (subprocess "false" [])
          case resolveKindClusterPresence LinuxCPU failedOutcome of
            Left (LiveStepProcessFailure label _failure) ->
              label @?= "kind get clusters"
            observed ->
              assertFailure
                ( "expected typed Kind probe process failure, got: "
                    <> show observed
                )
      , testCase
          "retained Kind recovery reuses its occupied edge port and clears stale live evidence (Sprint 2.9 reopened)"
          $ withOccupiedLoopbackPort
          $ \edgePort ->
            withSystemTempDirectory "jitml-kind-recovery" $ \root -> do
              let lease =
                    EdgePort.EdgePortLease
                      { EdgePort.leasedPort = edgePort
                      , EdgePort.leasedHost = "127.0.0.1"
                      }
                  livePublication =
                    Publication.markPublicationLive $
                      Publication.publicationWithLeasedPort
                        lease
                        (Publication.defaultPublication LinuxCPU)
                  publicationPath =
                    root </> ".build" </> "runtime" </> "cluster-publication.json"
              createDirectoryIfMissing True (root </> ".build" </> "runtime")
              ByteString.Lazy.writeFile publicationPath (Aeson.encode livePublication)
              firstRecovery <-
                prepareLiveKindRecovery root LinuxCPU KindClusterPresent
              case firstRecovery of
                Left failure ->
                  assertFailure ("retained Kind recovery failed: " <> show failure)
                Right (kindAction, recoveredLease, recoveryPublication) -> do
                  kindAction @?= ReuseLiveKindCluster
                  EdgePort.leasedPort recoveredLease @?= edgePort
                  Publication.publicationEvidence recoveryPublication @?= Nothing
                  assertBool
                    "recovery publication reports every component as reconciling"
                    ( all
                        ((== "reconciling") . snd)
                        (Publication.publicationComponents recoveryPublication)
                    )
              liveAfterRecovery <- readExistingLivePublication root
              liveAfterRecovery @?= Nothing
              persistedBytes <- ByteString.Lazy.readFile publicationPath
              persistedRecovery <-
                case eitherDecode persistedBytes of
                  Left err ->
                    assertFailureWithIO
                      ("failed to decode persisted Kind recovery publication: " <> err)
                  Right publication -> pure publication
              Publication.publicationEdgePort persistedRecovery @?= edgePort
              Publication.publicationEvidence persistedRecovery @?= Nothing
              retryRecovery <-
                prepareLiveKindRecovery root LinuxCPU KindClusterPresent
              case retryRecovery of
                Left failure ->
                  assertFailure
                    ("evidence-free retained Kind retry failed: " <> show failure)
                Right (kindAction, recoveredLease, _) -> do
                  kindAction @?= ReuseLiveKindCluster
                  EdgePort.leasedPort recoveredLease @?= edgePort
      , testCase
          "retained Kind selection is non-mutating and port-aware materialization is stable (Sprint 3.7)"
          $ withSystemTempDirectory "jitml-kind-port-aware"
          $ \root -> do
            let edgePort = 19091
                lease =
                  EdgePort.EdgePortLease
                    { EdgePort.leasedPort = edgePort
                    , EdgePort.leasedHost = "127.0.0.1"
                    }
                livePublication =
                  Publication.markPublicationLive $
                    Publication.publicationWithLeasedPort
                      lease
                      (Publication.defaultPublication LinuxCPU)
                runtimeRoot = root </> ".build" </> "runtime"
                publicationPath = runtimeRoot </> "cluster-publication.json"
                kindPath = root </> "kind" </> "cluster-linux-cpu.yaml"
                gatewayPath = root </> "chart" </> "templates" </> "gateway-jitml-edge.yaml"
                envoyPath = root </> "chart" </> "templates" </> "envoyproxy-jitml-edge.yaml"
            createDirectoryIfMissing True runtimeRoot
            ByteString.Lazy.writeFile publicationPath (Aeson.encode livePublication)
            before <- ByteString.Lazy.readFile publicationPath
            selected <- selectLiveKindRecovery root LinuxCPU KindClusterPresent
            case selected of
              Left failure ->
                assertFailure ("retained Kind selection failed: " <> show failure)
              Right (kindAction, recoveredLease, recoveryPublication) -> do
                kindAction @?= ReuseLiveKindCluster
                EdgePort.leasedPort recoveredLease @?= edgePort
                Publication.publicationEvidence recoveryPublication @?= Nothing
            ByteString.Lazy.readFile publicationPath >>= (@?= before)
            first <- materializeBootstrapFilesForPort root LinuxCPU edgePort
            second <- materializeBootstrapFilesForPort root LinuxCPU edgePort
            first @?= True
            second @?= False
            rendered <-
              Text.concat
                <$> traverse Text.IO.readFile [kindPath, gatewayPath, envoyPath]
            assertBool
              "every live edge-coordinate-bearing materialization uses the recovered port"
              (Text.count (Text.pack (show edgePort)) rendered >= 3)
            ByteString.Lazy.readFile publicationPath >>= (@?= before)
      , testCase
          "retained Kind recovery rejects mismatched state without rewriting its authority (Sprint 2.9 reopened)"
          $ withSystemTempDirectory "jitml-kind-recovery-mismatch"
          $ \root -> do
            let lease =
                  EdgePort.EdgePortLease
                    { EdgePort.leasedPort = 9092
                    , EdgePort.leasedHost = "127.0.0.1"
                    }
                mismatchedPublication =
                  Publication.markPublicationLive $
                    Publication.publicationWithLeasedPort
                      lease
                      (Publication.defaultPublication AppleSilicon)
                publicationPath =
                  root </> ".build" </> "runtime" </> "cluster-publication.json"
            createDirectoryIfMissing True (root </> ".build" </> "runtime")
            ByteString.Lazy.writeFile publicationPath (Aeson.encode mismatchedPublication)
            before <- ByteString.Lazy.readFile publicationPath
            mismatchResult <-
              prepareLiveKindRecovery root LinuxCPU KindClusterPresent
            case mismatchResult of
              Left (LiveStepInvariantFailure label message) -> do
                assertBool
                  "failure identifies retained-cluster recovery"
                  ("kind cluster recovery" `Text.isPrefixOf` label)
                assertBool
                  "failure names the persisted substrate mismatch"
                  ("apple-silicon" `Text.isInfixOf` message)
              observed ->
                assertFailure
                  ("expected typed mismatched-recovery failure, got: " <> show observed)
            after <- ByteString.Lazy.readFile publicationPath
            after @?= before
      , testCase
          "retained Kind recovery rejects missing, corrupt, or inconsistent coordinates (Sprint 2.9 reopened)"
          $ withSystemTempDirectory "jitml-kind-recovery-invalid"
          $ \root -> do
            let missingRoot = root </> "missing"
                missingPath =
                  missingRoot </> ".build" </> "runtime" </> "cluster-publication.json"
            missingResult <-
              prepareLiveKindRecovery missingRoot LinuxCPU KindClusterPresent
            case missingResult of
              Left (LiveStepInvariantFailure _ message) ->
                assertBool
                  "missing recovery authority is named"
                  ("missing" `Text.isInfixOf` message)
              observed ->
                assertFailure
                  ("expected missing recovery authority failure, got: " <> show observed)
            missingWasCreated <- doesFileExist missingPath
            missingWasCreated @?= False

            let corruptRoot = root </> "corrupt"
                corruptPath =
                  corruptRoot </> ".build" </> "runtime" </> "cluster-publication.json"
                corruptBytes = "{not-json"
            createDirectoryIfMissing True (corruptRoot </> ".build" </> "runtime")
            ByteString.Lazy.writeFile corruptPath corruptBytes
            corruptResult <-
              prepareLiveKindRecovery corruptRoot LinuxCPU KindClusterPresent
            case corruptResult of
              Left (LiveStepInvariantFailure _ message) ->
                assertBool
                  "corrupt recovery authority is named"
                  ("invalid" `Text.isInfixOf` message)
              observed ->
                assertFailure
                  ("expected corrupt recovery authority failure, got: " <> show observed)
            ByteString.Lazy.readFile corruptPath >>= (@?= corruptBytes)

            let inconsistentRoot = root </> "inconsistent"
                inconsistentPath =
                  inconsistentRoot </> ".build" </> "runtime" </> "cluster-publication.json"
                lease =
                  EdgePort.EdgePortLease
                    { EdgePort.leasedPort = 9092
                    , EdgePort.leasedHost = "127.0.0.1"
                    }
                inconsistentPublication =
                  ( Publication.markPublicationLive $
                      Publication.publicationWithLeasedPort
                        lease
                        (Publication.defaultPublication LinuxCPU)
                  )
                    { Publication.publicationPulsarUrl =
                        "pulsar://127.0.0.1:9091/pulsar"
                    }
                inconsistentBytes = Aeson.encode inconsistentPublication
            createDirectoryIfMissing True (inconsistentRoot </> ".build" </> "runtime")
            ByteString.Lazy.writeFile inconsistentPath inconsistentBytes
            inconsistentResult <-
              prepareLiveKindRecovery inconsistentRoot LinuxCPU KindClusterPresent
            case inconsistentResult of
              Left (LiveStepInvariantFailure _ message) ->
                assertBool
                  "inconsistent recovery URL is named"
                  ("Pulsar URL" `Text.isInfixOf` message)
              observed ->
                assertFailure
                  ("expected inconsistent recovery failure, got: " <> show observed)
            ByteString.Lazy.readFile inconsistentPath >>= (@?= inconsistentBytes)
      , testCase "selectLiveLease skips a stale occupied publication port (Sprint 15.2)" $
          withOccupiedLoopbackPort $ \stalePort ->
            withSystemTempDirectory "jitml-stale-publication" $ \root -> do
              let staleLease =
                    EdgePort.EdgePortLease
                      { EdgePort.leasedPort = stalePort
                      , EdgePort.leasedHost = "127.0.0.1"
                      }
                  stalePublication =
                    Publication.markPublicationLive $
                      Publication.publicationWithLeasedPort
                        staleLease
                        (Publication.defaultPublication AppleSilicon)
                  runtimeRoot = root </> ".build" </> "runtime"
              createDirectoryIfMissing True runtimeRoot
              ByteString.Lazy.writeFile
                (runtimeRoot </> "cluster-publication.json")
                (Aeson.encode stalePublication)
              lease <- selectLiveLease root AppleSilicon
              assertBool
                "selected lease must not trust an occupied stale publication port"
                (EdgePort.leasedPort lease /= stalePort)
              EdgePort.leasedHost lease @?= "127.0.0.1"
      , testCase "dispatchCheckpointDone routes a marker through HasMinIO (Sprint 4.6)" $
          -- The Consumer-domain entry point: given a typed
          -- `TbCheckpointMarker` (the in-memory sidecar shape derived from a
          -- typed CheckpointDone training event), `dispatchCheckpointDone` derives the
          -- sidecar key from the marker's own fields and writes the
          -- CBOR bytes through `HasMinIO.putBlobBytesIfAbsent`.
          withSystemTempDirectory "jitml-dispatch-ckpt" $ \root ->
            runFilesystemMinIO root $ do
              let marker =
                    TensorBoard.TbCheckpointMarker
                      { TensorBoard.tcmStep = 1234
                      , TensorBoard.tcmEpoch = 5
                      , TensorBoard.tcmManifestSha = "sha-abc"
                      , TensorBoard.tcmExperimentSha = "exp-xyz"
                      , TensorBoard.tcmTrialSha = Nothing
                      , TensorBoard.tcmRunUuid = "run-1"
                      , TensorBoard.tcmMetricsAtStep = [("loss", 0.5)]
                      }
              result <- TbSidecar.dispatchCheckpointDone marker
              case result of
                Right _ -> pure ()
                Left err -> liftIO (assertFailure ("dispatch failed: " <> show err))
              -- Verify the sidecar landed at the canonical key.
              let expectedKey = TensorBoard.checkpointSidecarKey "exp-xyz" 1234 "sha-abc"
                  ref =
                    ObjectRef
                      (BucketName "jitml-tensorboard")
                      (ObjectKey expectedKey)
              bytesResult <- minioReadBytes ref
              case bytesResult of
                Right bytes ->
                  liftIO $
                    assertBool
                      "dispatched sidecar is non-empty"
                      (Data.ByteString.length bytes > 0)
                Left err ->
                  liftIO (assertFailure ("expected sidecar read OK: " <> show err))
      , testCase "typed CheckpointDone writes a TensorBoard sidecar (Sprint 4.6)" $
          withSystemTempDirectory "jitml-daemon-tb-dispatch" $ \root -> do
            let checkpoint =
                  Training.CheckpointDone
                    { Training.cdExperimentHash = "exp-daemon"
                    , Training.cdManifestSha = "manifest-daemon"
                    , Training.cdStep = 77
                    , Training.cdPointerKey = "jitml-checkpoints/exp-daemon/latest"
                    , Training.cdEpoch = 3
                    , Training.cdTrialSha = Just "trial-1"
                    , Training.cdRunUuid = "run-daemon"
                    , Training.cdMetricsAtStep = [("loss", 0.125)]
                    }
                expectedKey =
                  TensorBoard.checkpointSidecarKey
                    "exp-daemon"
                    77
                    "manifest-daemon"
                ref =
                  ObjectRef
                    (BucketName "jitml-tensorboard")
                    (ObjectKey expectedKey)
            (dispatchResult, readResult) <-
              runFilesystemMinIO root $ do
                result <-
                  void
                    <$> TbSidecar.dispatchCheckpointDone
                      (TbSidecar.checkpointDoneToMarker checkpoint)
                bytes <- minioReadBytes ref
                pure (result, bytes)
            dispatchResult @?= Right ()
            case readResult of
              Right bytes ->
                assertBool
                  "daemon dispatcher wrote a non-empty sidecar"
                  (Data.ByteString.length bytes > 0)
              Left err ->
                assertFailure ("expected daemon sidecar read OK: " <> show err)
      , testCase "TensorBoard writer flushes TFRecord shards through HasMinIO (Sprint 4.6)" $
          withSystemTempDirectory "jitml-tb-writer" $ \root -> do
            let state0 = TensorBoard.emptyTensorBoardWriterState "exp-writer" "writer-a" 0 10
                event =
                  TensorBoard.TensorBoardEvent
                    { TensorBoard.tbWallTime = 10
                    , TensorBoard.tbStep = 1
                    , TensorBoard.tbTag = "loss"
                    , TensorBoard.tbValue = 0.5
                    }
                limits =
                  TensorBoard.defaultShardRotationLimits
                    { TensorBoard.shardExplicitFlush = True
                    }
                ref = TensorBoard.tensorBoardShardObjectRef state0
            (writeResult, readResult, duplicateResult) <-
              runFilesystemMinIO root $ do
                written <- TensorBoard.writeTensorBoardEvent 10 limits state0 event
                bytes <- minioReadBytes ref
                duplicate <- TensorBoard.writeTensorBoardEvent 10 limits state0 event
                pure (written, bytes, duplicate)
            case writeResult of
              Right (Just (TensorBoard.TensorBoardFlushStored storedRef _), state1) -> do
                storedRef @?= ref
                TensorBoard.tbwsShardSeq state1 @?= 1
              other ->
                assertFailure ("expected stored shard, got: " <> show other)
            case readResult of
              Right bytes ->
                assertBool
                  "TFRecord shard includes TensorBoard file-version event"
                  (Text.Encoding.encodeUtf8 "brain.Event:2" `Data.ByteString.isInfixOf` bytes)
              Left err ->
                assertFailure ("expected TensorBoard shard read OK: " <> show err)
            case duplicateResult of
              Right (Just (TensorBoard.TensorBoardFlushAlreadyPresent duplicateRef), _) ->
                duplicateRef @?= ref
              other ->
                assertFailure ("expected duplicate shard to be idempotent, got: " <> show other)
      , testCase "dockerMirrorPlan emits build + tag + push subprocesses (Sprint 3.5)" $ do
          let localTag = "jitml:local"
              harborTag = "127.0.0.1:9091/library/jitml:dev"
              plan = DockerImage.dockerMirrorPlan localTag "." harborTag
              rendered = fmap renderSubprocess plan
          length plan @?= 3
          assertBool
            "first step builds"
            (any ("docker build" `Text.isPrefixOf`) rendered)
          assertBool
            "second step tags to harbor"
            (any (harborTag `Text.isInfixOf`) rendered)
          assertBool
            "third step pushes"
            (any ("docker push" `Text.isInfixOf`) rendered)
      , testCase "dockerBuildAndKindLoadPlan emits explicit Kind image load subprocesses (Sprint 3.5)" $ do
          let plan = DockerImage.dockerBuildAndKindLoadPlan LinuxCPU "jitml:local" "."
              rendered = fmap renderSubprocess plan
          length plan @?= 2
          assertBool
            "first step builds the local image"
            (any ("docker build -t jitml:local" `Text.isInfixOf`) rendered)
          assertBool
            "second step loads the image into the substrate Kind cluster"
            (any ("kind load docker-image jitml:local --name jitml-linux-cpu" `Text.isInfixOf`) rendered)
      , testCase "helm phased rollout installs packaged dependency archives (Sprint 3.5)" $ do
          let rendered = Text.unlines (fmap renderSubprocess (Helm.helmPhasedRolloutPlan "chart"))
          assertBool
            "harbor install uses dependency archive"
            ("chart/charts/harbor-1.16.2.tgz" `Text.isInfixOf` rendered)
          assertBool
            "Harbor install uses direct subchart values"
            ("--values chart/values/harbor.yaml" `Text.isInfixOf` rendered)
          assertBool
            "MinIO install uses direct subchart values"
            ("--values chart/values/minio.yaml" `Text.isInfixOf` rendered)
          assertBool
            "Pulsar install uses direct subchart values"
            ("--values chart/values/pulsar.yaml" `Text.isInfixOf` rendered)
          assertBool
            "Helm installs use an explicit wait timeout for slow HA rollouts"
            ("--wait --timeout=900s" `Text.isInfixOf` rendered)
          assertBool
            "Envoy install uses gateway-helm dependency archive"
            ("chart/charts/gateway-helm-1.2.6.tgz" `Text.isInfixOf` rendered)
          assertBool
            "jitml-service install uses checked-in local chart"
            ("chart/local/jitml-service" `Text.isInfixOf` rendered)
          assertBool
            "retired mirror placeholder is absent from the Helm release plan"
            (not ("jitml-mirror" `Text.isInfixOf` rendered))
      , testCase "Pulsar HA manual PVs match chart-generated PVC names (Sprint 15.22)" $ do
          let renderedPVs = Text.unlines (fmap Storage.renderManualPV Storage.manualPVs)
          assertBool
            "BookKeeper journal PVC claimRef"
            ("name: pulsar-bookie-journal-pulsar-bookie-0" `Text.isInfixOf` renderedPVs)
          assertBool
            "BookKeeper ledgers PVC claimRef"
            ("name: pulsar-bookie-ledgers-pulsar-bookie-0" `Text.isInfixOf` renderedPVs)
          assertBool
            "ZooKeeper data PVC claimRef"
            ("name: pulsar-zookeeper-data-pulsar-zookeeper-0" `Text.isInfixOf` renderedPVs)
          assertBool
            "stale single-volume BookKeeper claimRefs are absent"
            (not ("data-pulsar-bookkeeper" `Text.isInfixOf` renderedPVs))
          pulsarValues <- Text.IO.readFile "chart/values/pulsar.yaml"
          assertBool
            "ZooKeeper storage class is set at the chart's data-volume leaf"
            ("    data:\n      size: 10Gi\n      storageClassName: jitml-manual" `Text.isInfixOf` pulsarValues)
          assertBool
            "BookKeeper journal storage class is set at the chart's journal leaf"
            ("    journal:\n      size: 10Gi\n      storageClassName: jitml-manual" `Text.isInfixOf` pulsarValues)
          assertBool
            "BookKeeper ledgers storage class is set at the chart's ledgers leaf"
            ("    ledgers:\n      size: 20Gi\n      storageClassName: jitml-manual" `Text.isInfixOf` pulsarValues)
      , testCase "jitml-service local chart carries current Dhall config surface" $ do
          configMap <- Text.IO.readFile "chart/local/jitml-service/templates/configmap.yaml"
          deployment <- Text.IO.readFile "chart/local/jitml-service/templates/deployment.yaml"
          rbac <- Text.IO.readFile "chart/local/jitml-service/templates/rbac.yaml"
          service <- Text.IO.readFile "chart/local/jitml-service/templates/service.yaml"
          assertBool
            "local chart renders typed Residency constructors"
            ("residency = < Cluster | Host >.Cluster" `Text.isInfixOf` configMap)
          assertBool
            "local chart gives Engine and Coordinator disjoint service accounts"
            ( "serviceAccountName: jitml-engine" `Text.isInfixOf` deployment
                && "serviceAccountName: jitml-coordinator" `Text.isInfixOf` deployment
            )
          assertBool
            "local chart preserves the immutable app-only Engine selector"
            ( "selector:\n    matchLabels:\n      app: jitml-service\n  template:"
                `Text.isInfixOf` deployment
            )
          Text.count "jitml.role: engine" deployment @?= 1
          assertBool
            "local chart does not mount a Kubernetes API token into Engine"
            ("automountServiceAccountToken: false" `Text.isInfixOf` deployment)
          Text.count "automountServiceAccountToken: false" deployment @?= 1
          Text.count "startupProbe:" deployment @?= 2
          Text.count
            "startupProbe:\n            httpGet:\n              path: /healthz\n              port: 8080\n            periodSeconds: 5\n            timeoutSeconds: 2\n            failureThreshold: 60"
            deployment
            @?= 2
          assertBool
            "local chart exposes HA engine replica values"
            (".Values.engineReplicas" `Text.isInfixOf` deployment)
          assertBool
            "local chart labels Engine pods as numerical compute"
            ( "jitml.compute: {{ if eq .Values.substrate \"apple-silicon\" }}\"false\"{{ else }}\"true\"{{ end }}"
                `Text.isInfixOf` deployment
            )
          assertBool
            "local chart scopes service Engine anti-affinity"
            ("jitml.compute-scope: service" `Text.isInfixOf` deployment)
          assertBool
            "local chart pins Linux Engine pods to compute nodes"
            ("jitml.node-role/compute: \"true\"" `Text.isInfixOf` deployment)
          assertBool
            "local chart grants namespace-scoped daemon kubectl access"
            ( "kind: RoleBinding" `Text.isInfixOf` rbac
                && not ("resources: [\"*\"]" `Text.isInfixOf` rbac)
                && not ("verbs: [\"*\"]" `Text.isInfixOf` rbac)
            )
          assertBool
            "Coordinator Role can reconcile each per-run ConfigMap and Job"
            ( "  - apiGroups: [\"batch\"]\n    resources: [\"jobs\"]\n    verbs: [\"get\", \"list\", \"watch\", \"create\", \"update\", \"patch\", \"delete\"]"
                `Text.isInfixOf` rbac
                && "  - apiGroups: [\"\"]\n    resources: [\"configmaps\"]\n    verbs: [\"get\", \"list\", \"watch\", \"create\", \"update\", \"patch\", \"delete\"]"
                  `Text.isInfixOf` rbac
            )
          assertBool
            "Coordinator alone is bound to the namespace Role"
            ( "subjects:\n  - kind: ServiceAccount\n    name: jitml-coordinator"
                `Text.isInfixOf` rbac
                && Text.count "name: jitml-engine" rbac == 1
            )
          assertBool
            "local chart exposes the Coordinator HTTP endpoint"
            ( "app: jitml-coordinator" `Text.isInfixOf` service
                && "jitml.role: coordinator" `Text.isInfixOf` service
            )
          assertBool
            "local chart renders typed InferenceMode constructors"
            ("< SelfInference | ForwardToHost >.SelfInference" `Text.isInfixOf` configMap)
          assertBool
            "local chart restores the operational dynamic retry policy"
            ( ">.ExponentialN { attempts = 5, baseMillis = 50, capMillis = 2000 }"
                `Text.isInfixOf` configMap
            )
          assertBool
            "local chart restores the operational dynamic log filter"
            ("logLevel = < Debug | Info | Warn | Error >.Info" `Text.isInfixOf` configMap)
          assertBool
            "local chart restores operational inference batching and latency controls"
            ( "inferenceBatchSize = 64" `Text.isInfixOf` configMap
                && "inferenceMaxLatencyMillis = 5000" `Text.isInfixOf` configMap
            )
          assertBool
            "local chart uses current dedup cache size field"
            ("dedupCacheSize = 4096" `Text.isInfixOf` configMap)
          assertBool
            "local chart uses current dedup cache ttl field"
            ("dedupCacheTtlSeconds = 3600" `Text.isInfixOf` configMap)
          assertBool
            "build VM fields are absent from current LiveConfig"
            (not ("buildVm" `Text.isInfixOf` configMap))
          assertBool
            "old unqualified Residency value is absent"
            (not ("residency = Cluster" `Text.isInfixOf` configMap))
          assertBool
            "retired structural retry record remains absent"
            (not ("retry = { maxAttempts" `Text.isInfixOf` configMap))
          Text.count
            "checksum/live-config: {{ include (print $.Template.BasePath \"/configmap.yaml\") . | sha256sum | quote }}"
            deployment
            @?= 2
      , testCase "Helm pod-template checksums change with rendered LiveConfig" $
          withSystemTempDirectory "jitml-live-config-checksum" $ \root -> do
            let serviceProbe = root </> "service"
                changedServiceProbe = root </> "service-changed"
                demoProbe = root </> "demo"
                changedDemoProbe = root </> "demo-changed"
            serviceChecksums <-
              renderHelmLiveConfigChecksums
                "chart/local/jitml-service"
                serviceProbe
                "5000"
            changedServiceChecksums <-
              renderHelmLiveConfigChecksums
                "chart/local/jitml-service"
                changedServiceProbe
                "5001"
            demoChecksums <-
              renderHelmLiveConfigChecksums
                "chart/local/jitml-demo"
                demoProbe
                "5000"
            changedDemoChecksums <-
              renderHelmLiveConfigChecksums
                "chart/local/jitml-demo"
                changedDemoProbe
                "5001"
            length serviceChecksums @?= 2
            length changedServiceChecksums @?= 2
            length demoChecksums @?= 1
            length changedDemoChecksums @?= 1
            assertBool
              "Engine and Coordinator receive deterministic SHA-256 annotations"
              (all ((== 64) . Text.length) (serviceChecksums <> changedServiceChecksums))
            assertBool
              "Webapp receives a deterministic SHA-256 annotation"
              (all ((== 64) . Text.length) (demoChecksums <> changedDemoChecksums))
            assertBool
              "changing only service LiveConfig changes both app pod templates"
              (and (zipWith (/=) serviceChecksums changedServiceChecksums))
            assertBool
              "changing only Webapp LiveConfig changes its pod template"
              (and (zipWith (/=) demoChecksums changedDemoChecksums))
      , testCase "checked-in service manifests equal one substrate materialization" $ do
          configMap <- Text.IO.readFile "chart/templates/configmap-jitml-service.yaml"
          deployment <- Text.IO.readFile "chart/templates/deployment-jitml-service.yaml"
          rbac <- Text.IO.readFile "chart/templates/rbac-jitml-service.yaml"
          let materializedPair substrate =
                ( ServiceConfigMap.renderServiceConfigMaps
                    (BootConfig.defaultBootConfig substrate BootConfig.Cluster)
                    LiveConfig.defaultLiveConfig
                , ServiceConfigMap.renderServiceDeployment substrate
                )
              validMaterializations =
                fmap materializedPair [AppleSilicon, LinuxCPU, LinuxCUDA]
          assertBool
            "ConfigMap and Deployment come from the same substrate materialization"
            ((configMap, deployment) `elem` validMaterializations)
          Text.count
            "checksum/live-config: {{ include (print $.Template.BasePath \"/configmap-jitml-service.yaml\") . | sha256sum | quote }}"
            deployment
            @?= 2
          rbac @?= ServiceConfigMap.renderServiceRBAC
      , testCase "Pulsar direct values are wait-safe for local Kind" $ do
          directValues <- Text.IO.readFile "chart/values/pulsar.yaml"
          umbrellaValues <- Text.IO.readFile "chart/values.yaml"
          assertBool
            "direct Pulsar values avoid LoadBalancer waits"
            ("type: ClusterIP" `Text.isInfixOf` directValues)
          assertBool
            "umbrella Pulsar values avoid LoadBalancer waits"
            ("type: ClusterIP" `Text.isInfixOf` umbrellaValues)
          assertBool
            "direct Pulsar values do not request a LoadBalancer"
            (not ("type: LoadBalancer" `Text.isInfixOf` directValues))
          assertBool
            "direct Pulsar preserves the reconciled topology while topics are idle"
            ("brokerDeleteInactiveTopicsEnabled: \"false\"" `Text.isInfixOf` directValues)
          assertBool
            "umbrella Pulsar preserves the reconciled topology while topics are idle"
            ("brokerDeleteInactiveTopicsEnabled: \"false\"" `Text.isInfixOf` umbrellaValues)
          assertBool
            "direct Pulsar rolls retained brokers when their config changes"
            ("restartPodsOnConfigMapChange: true" `Text.isInfixOf` directValues)
          assertBool
            "umbrella Pulsar rolls retained brokers when their config changes"
            ("restartPodsOnConfigMapChange: true" `Text.isInfixOf` umbrellaValues)
      , testCase "HA platform service values use distributed MinIO and 3x Pulsar (Sprint 4.10)" $ do
          minioValues <- Text.IO.readFile "chart/values/minio.yaml"
          pulsarValues <- Text.IO.readFile "chart/values/pulsar.yaml"
          umbrellaValues <- Text.IO.readFile "chart/values.yaml"
          assertBool "direct MinIO is distributed" ("mode: distributed" `Text.isInfixOf` minioValues)
          assertBool "direct MinIO has four replicas" ("replicas: 4" `Text.isInfixOf` minioValues)
          assertBool
            "direct MinIO liveness is tolerant of local live-test load"
            ( "livenessProbe:\n  enabled: true\n  initialDelaySeconds: 30\n  periodSeconds: 10\n  timeoutSeconds: 20\n  failureThreshold: 12"
                `Text.isInfixOf` minioValues
            )
          assertBool
            "direct MinIO readiness is tolerant of local live-test load"
            ( "readinessProbe:\n  enabled: true\n  periodSeconds: 10\n  timeoutSeconds: 10\n  failureThreshold: 12"
                `Text.isInfixOf` minioValues
            )
          assertBool
            "direct MinIO uses manual persistent storage"
            ("storageClass: jitml-manual" `Text.isInfixOf` minioValues)
          assertBool
            "direct distributed MinIO uses provisioning buckets"
            ("provisioning:\n  enabled: true\n  buckets:" `Text.isInfixOf` minioValues)
          assertBool
            "direct distributed MinIO does not use standalone defaultBuckets"
            (not ("defaultBuckets:" `Text.isInfixOf` minioValues))
          assertBool
            "direct MinIO provisions the Harbor registry bucket"
            ("- name: harbor-registry" `Text.isInfixOf` minioValues)
          assertBool
            "direct MinIO bucket provisioning does not issue versioning commands"
            ("versioning: Unchanged" `Text.isInfixOf` minioValues)
          assertBool
            "direct Pulsar has 3x ZooKeeper"
            ("zookeeper:\n  replicaCount: 3" `Text.isInfixOf` pulsarValues)
          assertBool
            "direct Pulsar has 3x BookKeeper"
            ("bookkeeper:\n  replicaCount: 3" `Text.isInfixOf` pulsarValues)
          assertBool
            "direct Pulsar has 3x Broker"
            ("broker:\n  replicaCount: 3" `Text.isInfixOf` pulsarValues)
          assertBool
            "direct Pulsar has 3x Proxy"
            ("proxy:\n  replicaCount: 3" `Text.isInfixOf` pulsarValues)
          assertBool
            "umbrella values retain distributed MinIO"
            ("minio:\n  mode: distributed\n  replicas: 4" `Text.isInfixOf` umbrellaValues)
          assertBool
            "umbrella values retain 3x Pulsar broker"
            ("broker:\n    replicaCount: 3" `Text.isInfixOf` umbrellaValues)
      , testCase
          "live phased rollout wires the explicit Kind image load phase before final services (Sprint 3.5)"
          $ do
            let rendered = fmap renderSubprocess (livePhasedRolloutSubprocesses LinuxCPU "chart")
                commandText = Text.unlines rendered
                appleCommandText =
                  Text.unlines (fmap renderSubprocess (livePhasedRolloutSubprocesses AppleSilicon "chart"))
                publicReadyzProbe =
                  renderSubprocess (publicReadyzSubprocessForPort 9091)
            assertBool
              "live rollout creates Kind first"
              ("kind create cluster --name jitml-linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout writes the Kind create-time kubeconfig outside the repo-local bind mount"
              ("--kubeconfig /tmp/jitml-kind-create-linux-cpu.kubeconfig" `Text.isInfixOf` commandText)
            assertBool
              "live rollout uses the repo-local kubeconfig for downstream kubectl steps"
              ("--kubeconfig ./.build/jitml.kubeconfig" `Text.isInfixOf` commandText)
            assertBool
              "live rollout raises the Kind node inotify cap before Helm waits"
              ( "docker exec jitml-linux-cpu-control-plane sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_queued_events=65536"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout raises worker inotify caps before Helm waits"
              ( "docker exec jitml-linux-cpu-worker sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_queued_events=65536"
                  `Text.isInfixOf` commandText
                  && "docker exec jitml-linux-cpu-worker3 sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_queued_events=65536"
                    `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout caps every HA Kind node"
              ( "docker update --memory 12884901888 --memory-swap 12884901888 --cpus 4 jitml-linux-cpu-control-plane"
                  `Text.isInfixOf` commandText
                  && "docker update --memory 12884901888 --memory-swap 12884901888 --cpus 4 jitml-linux-cpu-worker3"
                    `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout restarts kube-proxy after the inotify cap is applied"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig delete pod -n kube-system -l k8s-app=kube-proxy --ignore-not-found"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "linux-cpu live rollout binds stateful PVs to node-local storage before Harbor"
              ( "docker exec jitml-linux-cpu-control-plane sh -c 'set -e; mkdir -p /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/ /jitml/.data/platform/minio/pv_0/; mountpoint -q /jitml/.data/platform/minio/pv_0/ || mount --bind /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/ /jitml/.data/platform/minio/pv_0/; chmod 0777 /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/;"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "linux-cpu live rollout preserves registered Postgres ownership"
              ( "chown -R 26:26 /var/local/jitml-stateful-pv/jitml/.data/platform/harbor-pg/pv_0/"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "linux-cpu live rollout prepares worker-local stateful PV storage"
              ( "docker exec jitml-linux-cpu-worker sh -c 'set -e; mkdir -p /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/"
                  `Text.isInfixOf` commandText
                  && "docker exec jitml-linux-cpu-worker3 sh -c 'set -e; mkdir -p /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/"
                    `Text.isInfixOf` commandText
              )
            assertBool
              "apple-silicon live rollout binds stateful PVs to node-local storage before Harbor"
              ( "docker exec jitml-apple-silicon-control-plane sh -c 'set -e; mkdir -p /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/ /jitml/.data/platform/minio/pv_0/; mountpoint -q /jitml/.data/platform/minio/pv_0/ || mount --bind /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/ /jitml/.data/platform/minio/pv_0/; chmod 0777 /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/;"
                  `Text.isInfixOf` appleCommandText
              )
            assertBool
              "live rollout can warm-load the cached Percona operator image before Helm waits"
              ( "kind load docker-image percona/percona-postgresql-operator:2.5.1 --name jitml-linux-cpu"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout can warm-load the cached Harbor component images before Helm waits"
              ( "kind load docker-image goharbor/harbor-core:v2.12.2 --name jitml-linux-cpu"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies manual storage manifests"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/storageclass-jitml-manual.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the GatewayClass before the Gateway"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/gatewayclass-jitml.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the generated Gateway"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/gateway-jitml-edge.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies generated HTTPRoutes"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-demo-api.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the Harbor registry route"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-harbor-registry.yaml"
                  `Text.isInfixOf` commandText
              )
            publicReadyzProbe
              @?= "curl --fail --silent --show-error --connect-timeout 5 --max-time 10 --retry 30 --retry-delay 2 --retry-max-time 180 --retry-connrefused --retry-all-errors http://127.0.0.1:9091/readyz"
            assertBool
              "live rollout executes the bounded public Coordinator readiness probe"
              (publicReadyzProbe `Text.isInfixOf` commandText)
            let (beforePublicReadyz, _fromPublicReadyz) =
                  Text.breakOn publicReadyzProbe commandText
            assertBool
              "public Coordinator readiness is checked only after its HTTPRoute is applied"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/httproute-jitml-service-readyz.yaml"
                  `Text.isInfixOf` beforePublicReadyz
              )
            assertBool
              "live rollout builds jitml image"
              ("docker build -t jitml:local" `Text.isInfixOf` commandText)
            assertBool
              "live rollout loads jitml image into Kind"
              ("kind load docker-image jitml:local --name jitml-linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout retags jitml:local as jitml-demo:local instead of rebuilding"
              ("docker tag jitml:local jitml-demo:local" `Text.isInfixOf` commandText)
            assertBool
              "live rollout does not run a second docker build for jitml-demo:local"
              (not ("docker build -t jitml-demo:local" `Text.isInfixOf` commandText))
            assertBool
              "live rollout loads demo image into Kind"
              ("kind load docker-image jitml-demo:local --name jitml-linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout threads substrate into local charts"
              ("--set substrate=linux-cpu" `Text.isInfixOf` commandText)
            assertBool
              "live rollout applies generated Grafana dashboards"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/grafana-dashboard-daemon-health.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies the generated Prometheus ScrapeConfig"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/prometheus-scrapeconfig-jitml.yaml"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout gives Harbor an explicit localhost externalURL"
              ("--set-string externalURL=http://127.0.0.1:9091" `Text.isInfixOf` commandText)
            assertBool
              "live rollout passes Harbor's external database values"
              ("--values chart/values/harbor.yaml" `Text.isInfixOf` commandText)
            let (beforeHarbor, _fromHarbor) =
                  Text.breakOn "helm upgrade --install harbor chart/charts/harbor-1.16.2.tgz" commandText
            assertBool
              "live rollout installs MinIO before Harbor so the registry bucket exists"
              ("helm upgrade --install minio chart/charts/minio-14.8.5.tgz" `Text.isInfixOf` beforeHarbor)
            assertBool
              "live rollout warm-loads cached third-party images before the first Helm release"
              ( "kind load docker-image percona/percona-postgresql-operator:2.5.1 --name jitml-linux-cpu"
                  `Text.isInfixOf` beforeHarbor
              )
            assertBool
              "live rollout applies the inotify cap before the first Helm release"
              ( "docker exec jitml-linux-cpu-control-plane sysctl -w fs.inotify.max_user_instances=1024"
                  `Text.isInfixOf` beforeHarbor
              )
            let (beforeManualStorage, _fromManualStorage) =
                  Text.breakOn
                    "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/storageclass-jitml-manual.yaml"
                    commandText
            assertBool
              "live rollout prepares node-local stateful PV storage before applying manual storage"
              ( "docker exec jitml-linux-cpu-control-plane sh -c 'set -e; mkdir -p /var/local/jitml-stateful-pv/jitml/.data/platform/minio/pv_0/"
                  `Text.isInfixOf` beforeManualStorage
              )
            -- Sprint 4.8: the Harbor-registry bucket existence probe moved
            -- from a `mc ls ... >/dev/null` chain in the rendered subprocess
            -- list to typed Haskell IO (`runMinioBucketReadinessIO`).
            -- `liveExecutePhasedRollout` runs the IO step between the
            -- pre-grant and grant phases, before Harbor installs.
            assertBool
              "live rollout waits for harbor-pg before installing Harbor"
              ( "wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready'"
                  `Text.isInfixOf` beforeHarbor
              )
            -- Sprint 2.9: the postgres schema grant moved from an embedded `sh
            -- -c` subprocess to a typed Haskell IO step in
            -- `JitML.Bootstrap.postgresSchemaGrantIO`, so it no longer appears
            -- in the rendered subprocess list. Ordering is preserved by
            -- `liveExecutePhasedRollout`, which runs the grant between the
            -- pre-grant and post-grant subprocess phases.
            let (beforeFinalService, _fromFinalService) =
                  Text.breakOn "helm upgrade --install jitml-service chart/local/jitml-service" commandText
            assertBool
              "live rollout loads local images before installing final workloads"
              ("kind load docker-image jitml-demo:local --name jitml-linux-cpu" `Text.isInfixOf` beforeFinalService)
            let serviceInstall =
                  listToMaybe
                    [ renderedCommand
                    | renderedCommand <- rendered
                    , "helm upgrade --install jitml-service chart/local/jitml-service"
                        `Text.isInfixOf` renderedCommand
                    ]
                demoInstall =
                  listToMaybe
                    [ renderedCommand
                    | renderedCommand <- rendered
                    , "helm upgrade --install jitml-demo chart/local/jitml-demo"
                        `Text.isInfixOf` renderedCommand
                    ]
            for_ [serviceInstall, demoInstall] $ \case
              Nothing -> assertFailure "live rollout omitted a repo-owned app Helm release"
              Just installCommand ->
                assertBool
                  "repo-owned app Helm applies without waiting on a stale same-tag pod"
                  (not ("--wait" `Text.isInfixOf` installCommand))
            let (beforeEngineReadiness, _fromEngineReadiness) =
                  Text.breakOn "rollout status deployment/jitml-service" commandText
            assertBool
              "repo-owned app Helm apply precedes the explicit rollout readiness phase"
              ( "helm upgrade --install jitml-demo chart/local/jitml-demo"
                  `Text.isInfixOf` beforeEngineReadiness
              )
            let (beforeObservabilityManifests, _fromObservabilityManifests) =
                  Text.breakOn
                    "kubectl --kubeconfig ./.build/jitml.kubeconfig apply -f chart/templates/grafana-dashboard-training-throughput.yaml"
                    commandText
            assertBool
              "live rollout installs kube-prometheus-stack before applying dashboard ConfigMaps"
              ( "helm upgrade --install kube-prometheus-stack"
                  `Text.isInfixOf` beforeObservabilityManifests
              )
            assertBool
              "live rollout installs jitml-service before applying Prometheus scrape config"
              ( "helm upgrade --install jitml-service chart/local/jitml-service"
                  `Text.isInfixOf` beforeObservabilityManifests
              )
            -- Sprint 4.8: the per-bucket MinIO readiness check and the Pulsar
            -- topic create loop moved from `sh -c` subprocesses in the rollout
            -- list to typed Haskell IO (`runMinioBucketReadinessIO` /
            -- `runPulsarTopicCreatesIO`). `liveExecutePhasedRollout` runs them
            -- between the pre-grant / grant / post-grant subprocess phases,
            -- so they no longer appear in the rendered subprocess text.
            assertBool
              "live rollout waits for MinIO deployment readiness before topic bootstrap"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status statefulset/minio --timeout=300s"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout waits for Pulsar broker readiness through the platform readiness phase"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status statefulset/pulsar-broker --timeout=300s"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "live rollout applies registered PerconaPGCluster manifests"
              ("kubectl --kubeconfig ./.build/jitml.kubeconfig apply -n platform -f -" `Text.isInfixOf` commandText)
            assertBool
              "live rollout waits for the registered service Postgres cluster"
              ( "kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready' --timeout=600s"
                  `Text.isInfixOf` commandText
              )
            assertBool
              "retired mirror placeholder chart is not executed by the live path"
              (not ("helm upgrade --install jitml-mirror" `Text.isInfixOf` commandText))
            assertBool
              "live rollout does not rely on the in-cluster Harbor DNS name for local image publication"
              (not ("docker push harbor.platform.svc.cluster.local" `Text.isInfixOf` commandText))
      , testCase "HarborSubprocess uses explicit local registry settings (Sprint 4.1)" $ do
          let settings =
                (HarborSubprocess.harborSettingsForLocalEdge 9091)
                  { HarborSubprocess.harborDockerHost = Just "unix:///explicit/docker.sock"
                  }
              imageRef = ImageRef "127.0.0.1:9091/library/jitml:phase4"
              loginCommand = HarborSubprocess.harborLoginSubprocess settings
              listCommand = HarborSubprocess.harborListRepositoriesSubprocess settings "library"
              artifactCommand = HarborSubprocess.harborArtifactStatusSubprocess settings "library" "jitml" "phase4"
              tagCommand = HarborSubprocess.harborCreateTagSubprocess settings "library" "jitml" "phase4" "ready"
          renderSubprocess loginCommand
            @?= "docker --host unix:///explicit/docker.sock --config ./.build/docker/harbor login --username admin --password-stdin 127.0.0.1:9091"
          JitML.Sub.Subprocess.subprocessStdin loginCommand @?= Just "Harbor12345"
          renderSubprocess (HarborSubprocess.harborManifestInspectSubprocess settings imageRef)
            @?= "docker --host unix:///explicit/docker.sock --config ./.build/docker/harbor manifest inspect 127.0.0.1:9091/library/jitml:phase4"
          assertBool
            "Harbor API base path is explicit"
            ( "http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories?page_size=100"
                `Text.isInfixOf` renderSubprocess listCommand
            )
          assertBool
            "Harbor artifact existence uses the API, not docker manifest inspect"
            ( "http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories/jitml/artifacts/phase4"
                `Text.isInfixOf` renderSubprocess artifactCommand
            )
          assertBool
            "Harbor same-repository promotion uses the API tag endpoint"
            ( "http://127.0.0.1:9091/harbor/api/v2.0/projects/library/repositories/jitml/artifacts/phase4/tags"
                `Text.isInfixOf` renderSubprocess tagCommand
            )
          assertBool
            "Harbor tag promotion sends the target tag as JSON"
            ("{\"name\":\"ready\"}" `Text.isInfixOf` renderSubprocess tagCommand)
      , testCase "cluster down uses the typed Kind delete subprocess (Sprint 2.9)" $ do
          let rendered = renderSubprocess (Helm.kindDeleteSubprocess LinuxCPU)
          -- Sprint 2.9: kindDelete is now a typed single command; the prior
          -- existence-check + exit-3 no-op lived in `sh -c`. The caller (cluster
          -- down) handles the missing-cluster error path.
          assertBool
            "cluster down deletes the substrate Kind cluster"
            ("kind delete cluster --name jitml-linux-cpu" `Text.isInfixOf` rendered)
      , testCase "platform readiness checks cover Phase 4 service rollouts" $ do
          let rendered = Text.unlines (fmap renderSubprocess Readiness.platformReadinessSubprocesses)
          assertBool "Harbor readiness" ("rollout status deployment/harbor-core" `Text.isInfixOf` rendered)
          assertBool "MinIO readiness" ("rollout status statefulset/minio" `Text.isInfixOf` rendered)
          assertBool "Pulsar readiness" ("rollout status statefulset/pulsar-broker" `Text.isInfixOf` rendered)
          assertBool
            "Prometheus readiness"
            ("rollout status statefulset/prometheus-kube-prometheus-stack-prometheus" `Text.isInfixOf` rendered)
          assertBool
            "TensorBoard readiness"
            ("rollout status deployment/tensorboard" `Text.isInfixOf` rendered)
          assertBool
            "jitML Engine service readiness"
            ("rollout status deployment/jitml-service" `Text.isInfixOf` rendered)
          assertBool
            "jitML Coordinator readiness"
            ("rollout status deployment/jitml-coordinator" `Text.isInfixOf` rendered)
          assertBool
            "PerconaPGCluster readiness"
            ("wait perconapgcluster/harbor-pg '--for=jsonpath={.status.state}=ready'" `Text.isInfixOf` rendered)
          assertBool
            "NVIDIA RuntimeClass check"
            ("get runtimeclass nvidia" `Text.isInfixOf` rendered)
          assertBool
            "MinIO bucket readiness exec"
            ("exec -n platform statefulset/minio" `Text.isInfixOf` rendered)
          -- Sprint 4.8: the typed final-gate `minioBucketReadinessSubprocess`
          -- runs a single `kubectl exec statefulset/minio -- env
          -- MC_HOST_jitml-minio=... mc ls jitml-minio` (no in-pod shell). The
          -- bootstrap-time per-bucket retry loop moved to typed Haskell IO in
          -- `JitML.Cluster.Readiness.runMinioBucketReadinessIO`, called by
          -- `JitML.Bootstrap.liveExecutePhasedRollout` between the pre-grant
          -- and grant phases.
          assertBool
            "MinIO readiness gate uses the typed env-var alias hand-off"
            ("MC_HOST_jitml-minio=http://minio:minioadmin@" `Text.isInfixOf` rendered)
          assertBool
            "MinIO readiness gate calls mc against jitml-minio"
            ("/opt/bitnami/minio-client/bin/mc ls jitml-minio" `Text.isInfixOf` rendered)
      , testCase "jitml-service cardinality is one numerical worker per Kubernetes node (Sprint 5.16)" $ do
          let appleDeployment = ServiceConfigMap.renderServiceDeployment AppleSilicon
              cpuDeployment = ServiceConfigMap.renderServiceDeployment LinuxCPU
              cudaDeployment = ServiceConfigMap.renderServiceDeployment LinuxCUDA
          assertBool
            "apple-silicon does not request the NVIDIA RuntimeClass"
            (not ("runtimeClassName: nvidia" `Text.isInfixOf` appleDeployment))
          assertBool
            "linux-cpu does not request the NVIDIA RuntimeClass"
            (not ("runtimeClassName: nvidia" `Text.isInfixOf` cpuDeployment))
          assertBool
            "linux-cuda requests the NVIDIA RuntimeClass"
            ("runtimeClassName: nvidia" `Text.isInfixOf` cudaDeployment)
          assertBool
            "linux-cuda asks the NVIDIA runtime for visible devices"
            ("NVIDIA_VISIBLE_DEVICES" `Text.isInfixOf` cudaDeployment)
          assertBool
            "linux-cuda restricts NVIDIA driver capabilities to compute and utility"
            ("NVIDIA_DRIVER_CAPABILITIES" `Text.isInfixOf` cudaDeployment)
          assertBool
            "linux-cpu does not set NVIDIA runtime environment"
            (not ("NVIDIA_VISIBLE_DEVICES" `Text.isInfixOf` cpuDeployment))
          assertBool
            "linux-cpu service has one Engine replica per HA worker"
            ("replicas: 3" `Text.isInfixOf` cpuDeployment)
          assertBool
            "apple-silicon has no cluster Engine and one non-compute Coordinator"
            ( "name: jitml-service\n  namespace: platform\nspec:\n  replicas: 0" `Text.isInfixOf` appleDeployment
                && "name: jitml-coordinator" `Text.isInfixOf` appleDeployment
                && "replicas: 1" `Text.isInfixOf` appleDeployment
                && "jitml.compute: \"false\"" `Text.isInfixOf` appleDeployment
            )
          assertBool
            "jitml-service labels Linux Engine pods as numerical compute"
            ("jitml.compute: \"true\"" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service labels Linux Engine pods with service compute scope"
            ("jitml.compute-scope: service" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service pins Linux Engine pods to compute nodes"
            ("jitml.node-role/compute: \"true\"" `Text.isInfixOf` cpuDeployment)
          assertBool
            "apple-silicon service does not pin to in-cluster compute workers"
            (not ("nodeSelector:" `Text.isInfixOf` appleDeployment))
          assertBool
            "jitml-service uses required pod anti-affinity for one compute pod per node"
            ("requiredDuringSchedulingIgnoredDuringExecution" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service rolling update avoids surge over compute cardinality"
            ("maxSurge: 0" `Text.isInfixOf` cpuDeployment && "maxUnavailable: 1" `Text.isInfixOf` cpuDeployment)
          assertBool
            "Engine and Coordinator pin their disjoint service accounts"
            ( "serviceAccountName: jitml-engine" `Text.isInfixOf` cpuDeployment
                && "serviceAccountName: jitml-coordinator" `Text.isInfixOf` cpuDeployment
            )
          assertBool
            "rendered Engine selector remains app-only across chart upgrades"
            ( "selector:\n    matchLabels:\n      app: jitml-service\n  template:"
                `Text.isInfixOf` cpuDeployment
            )
          Text.count "jitml.role: engine" cpuDeployment @?= 1
          Text.count "startupProbe:" cpuDeployment @?= 2
          Text.count "livenessProbe:" cpuDeployment @?= 2
          Text.count "failureThreshold: 60" cpuDeployment @?= 2
          assertBool
            "jitml-service anti-affinity is keyed by hostname"
            ("topologyKey: kubernetes.io/hostname" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service anti-affinity matches service-scope compute pods"
            ("jitml.compute-scope: service" `Text.isInfixOf` cpuDeployment)
          assertBool
            "jitml-service uses hard topology spread for HA compute workers"
            ( "topologySpreadConstraints:" `Text.isInfixOf` cpuDeployment
                && "whenUnsatisfiable: DoNotSchedule" `Text.isInfixOf` cpuDeployment
            )
          assertBool
            "jitml-service does not rely on advisory anti-affinity"
            (not ("preferredDuringSchedulingIgnoredDuringExecution" `Text.isInfixOf` cpuDeployment))
      , testCase "Apple host BootConfig is patched from cluster publication (Sprint 3.5)" $ do
          let lease = EdgePort.EdgePortLease {EdgePort.leasedPort = 9092, EdgePort.leasedHost = "127.0.0.1"}
              publication = Publication.publicationWithLeasedPort lease (Publication.defaultPublication AppleSilicon)
              hostConfig = hostBootConfigForPublication publication
          BootConfig.bootPulsarServiceUrl hostConfig @?= Publication.publicationPulsarUrl publication
          BootConfig.bootMinioEndpoint hostConfig @?= Publication.publicationMinioUrl publication
          BootConfig.bootPulsarAdminUrl hostConfig @?= "http://127.0.0.1:9092/pulsar/admin"
          BootConfig.bootHarborRegistry hostConfig @?= "127.0.0.1:9092/library"
      , testCase "Tune resume-from-partial-sweep via HasMinIO (Sprint 9.7)" $
          withSystemTempDirectory "jitml-tune-resume" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-tune-resume"
                  transcripts =
                    zipWith
                      ( \seed trialIndex ->
                          Tune.terminalTrialTranscript
                            experimentHash
                            seed
                            (Tune.trialObjectiveResult Tune.Grid trialIndex)
                      )
                      [1, 2, 3]
                      [0 ..]
              mapM_ TuneResume.persistTrialTranscript transcripts
              outcome <- TuneResume.replaySweep experimentHash [1, 2, 3]
              liftIO $ do
                TuneResume.resumedSeeds outcome @?= [1, 2, 3]
                length (TuneResume.resumedTrials outcome) @?= 3
                TuneResume.resumeReadFailures outcome @?= []
                TuneResume.resumedTrials outcome @?= transcripts
                assertBool
                  "replayed terminal transcripts retain ordered rung evidence"
                  (not (any (null . Tune.transcriptObservations) (TuneResume.resumedTrials outcome)))
      , testCase "Tune replay reports corrupt transcripts as typed decode failures (Sprint 9.15)" $
          withSystemTempDirectory "jitml-tune-resume-corrupt" $ \root ->
            runFilesystemMinIO root $ do
              let experimentHash = "exp-tune-resume-corrupt"
                  corruptSeed = 7
                  missingSeed = 8
                  corruptKey = Tune.trialStorageKey experimentHash corruptSeed
                  missingKey = Tune.trialStorageKey experimentHash missingSeed
                  corruptRef = ObjectRef (BucketName "jitml-trials") (ObjectKey corruptKey)
              written <- putBlobBytesIfAbsent corruptRef (Data.ByteString.pack [0, 1, 2, 3])
              liftIO $ case written of
                Right _ -> pure ()
                Left err -> assertFailure ("failed to write corrupt transcript fixture: " <> show err)
              outcome <- TuneResume.replaySweep experimentHash [corruptSeed, missingSeed]
              liftIO $ do
                TuneResume.resumedSeeds outcome @?= [corruptSeed, missingSeed]
                TuneResume.resumedTrials outcome @?= []
                case TuneResume.resumeReadFailures outcome of
                  [ (keyA, TuneResume.ResumeDecodeFailure message)
                    , (keyB, TuneResume.ResumeServiceFailure (SEUnauthorized _))
                    ] -> do
                      keyA @?= corruptKey
                      keyB @?= missingKey
                      assertBool "decode failure message is concrete" (not (Text.null message))
                  other -> assertFailure ("unexpected resume failures: " <> show other)
      , testCase "AsyncBuffer sink writes transcripts through HasMinIO (Sprint 8.4)" $
          withSystemTempDirectory "jitml-async-minio-sink" $ \root -> do
            -- Build an AsyncSink that closes over a per-batch counter and
            -- writes each batch's content-hashed payload through
            -- `HasMinIO.putBlobBytesIfAbsent` via the filesystem instance.
            counter <- newIORef (0 :: Int)
            let bucket = BucketName "jitml-transcripts"
                experimentHash = "exp-async"
                sink =
                  AsyncBuffer.AsyncSink
                    ( \batch -> do
                        seqNum <- readIORef counter
                        modifyIORef' counter (+ 1)
                        let payload =
                              Text.Encoding.encodeUtf8
                                ( Text.pack
                                    ("transcript:" <> show (length batch))
                                )
                            ref =
                              ObjectRef
                                bucket
                                ( ObjectKey
                                    ( "jitml-transcripts/"
                                        <> experimentHash
                                        <> "/"
                                        <> Text.pack (show seqNum)
                                        <> ".cbor"
                                    )
                                )
                        result <-
                          runFilesystemMinIO root $
                            putBlobBytesIfAbsent ref payload
                        case result of
                          Right _ ->
                            pure
                              ( AsyncBuffer.AsyncWriteOk
                                  ( "jitml-transcripts/"
                                      <> experimentHash
                                      <> "/"
                                      <> Text.pack (show seqNum)
                                      <> ".cbor"
                                  )
                              )
                          Left err ->
                            pure (AsyncBuffer.AsyncWriteFailed (Text.pack (show err)))
                    )
            buffer <- AsyncBuffer.newAsyncBuffer Buffer.OffPolicyReplay 16 sink
            let mkT n =
                  Buffer.Transition
                    { Buffer.transitionStep = n
                    , Buffer.transitionAction = n
                    , Buffer.transitionReward = fromIntegral n
                    , Buffer.transitionObservation = n
                    , Buffer.transitionDone = False
                    }
            mapM_ (AsyncBuffer.insertAsync buffer . mkT) [0, 1, 2]
            results <- AsyncBuffer.drainAsync buffer
            length results @?= 3
            mapM_
              ( \case
                  AsyncBuffer.AsyncWriteOk _ -> pure ()
                  AsyncBuffer.AsyncWriteFailed err ->
                    assertFailure ("async sink write failed: " <> Text.unpack err)
              )
              results
            -- Verify the blob landed in MinIO.
            readback <-
              runFilesystemMinIO root $
                minioReadBytes
                  ( ObjectRef
                      bucket
                      (ObjectKey "jitml-transcripts/exp-async/0.cbor")
                  )
            case readback of
              Right bytes ->
                assertBool
                  "MinIO holds the first transcript batch"
                  ("transcript:" `Text.isPrefixOf` Text.Encoding.decodeUtf8 bytes)
              Left err ->
                assertFailure ("expected MinIO read OK, got: " <> show err)
      , testCase "kubectlApply carries PerconaPGCluster YAML through explicit stdin command" $ do
          cluster <-
            case PostgresRegistry.postgresRegistry of
              [value] -> pure value
              values ->
                assertFailure
                  ("expected exactly one PerconaPGCluster registry entry, got: " <> show (length values))
          let yaml = PostgresRegistry.renderPerconaPGCluster cluster
              cmd =
                JitML.Sub.Subprocess.subprocessWithStdin
                  "kubectl"
                  [ "--kubeconfig"
                  , "./.build/jitml.kubeconfig"
                  , "apply"
                  , "--dry-run=client"
                  , "--validate=false"
                  , "-f"
                  , "-"
                  ]
                  yaml
          renderSubprocess cmd
            @?= "kubectl --kubeconfig ./.build/jitml.kubeconfig apply --dry-run=client --validate=false -f -"
          JitML.Sub.Subprocess.subprocessStdin cmd @?= Just yaml
          assertBool "rendered PerconaPGCluster names harbor-pg" ("harbor-pg" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster includes required pgBackRest repo"
            ("    pgbackrest:" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins the Postgres image"
            ("2.5.1-ppg16.8-postgres" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins the PgBouncer image"
            ("2.5.1-ppg16.8-pgbouncer1.24.0" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins the pgBackRest image"
            ("2.5.1-ppg16.8-pgbackrest2.54.2" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster pins manual storage class"
            ("storageClassName: jitml-manual" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster binds a manual PV by volumeName"
            ("volumeName: platform-harbor-pg-pv-0" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster binds every HA instance PV by volumeName"
            ("volumeName: platform-harbor-pg-pv-2" `Text.isInfixOf` yaml)
          assertBool
            "rendered PerconaPGCluster binds a manual backup PV by volumeName"
            ("volumeName: platform-harbor-pg-repo1-pv-0" `Text.isInfixOf` yaml)
      , testCase "KubectlSubprocess settings pin the repo-local kubeconfig explicitly" $ do
          kubectlBinary defaultKubectlSettings @?= "kubectl"
          kubectlKubeconfig defaultKubectlSettings @?= "./.build/jitml.kubeconfig"
          kubectlNamespace defaultKubectlSettings @?= "platform"
      , testGroup
          -- Sprint 13.2 — exercises HasMinIO / HasPulsar through the routed
          -- Envoy edge against a live Kind cluster brought up by Sprint 13.1.
          -- Select with `cabal test jitml-integration --test-options='-p Live'`.
          -- Skipped by default with `-p '!/Live/'` when running on a host
          -- without a cluster up. Tests fail with a clear message when the
          -- cluster-publication.json is missing.
          "Live"
          [ testCase
              "live typed-executable WorkflowMatrix executes every current-substrate CLI cell fail-closed (Sprint 12.11)"
              $ do
                publication <- requireLivePublication
                jitmlBinary <- locateJitmlBinary
                binary <- case jitmlBinary of
                  Nothing ->
                    assertFailure
                      "jitml binary not found — needed for Sprint 12.11 WorkflowMatrix live execution"
                  Just path -> pure path
                repoRoot <- makeAbsolute "."
                let substrate = Publication.publicationSubstrate publication
                    cells =
                      filter
                        ((== substrate) . WorkflowMatrix.cellSubstrate)
                        WorkflowMatrix.workflowMatrix
                    inferenceReplyTopic = topologyTopic InferenceResultRoute substrate
                length cells @?= length WorkflowMatrix.allWorkflows
                inferenceSubscriptionsBefore <-
                  pulsarSubscriptionNamesWithPrefix inferenceReplyTopic "jitml-infer-"
                traverse_ (runTypedExecutableWorkflowMatrixCell repoRoot binary publication) cells
                inferenceSubscriptionsAfter <-
                  pulsarSubscriptionNamesWithPrefix inferenceReplyTopic "jitml-infer-"
                let leakedSubscriptions =
                      filter (`notElem` inferenceSubscriptionsBefore) inferenceSubscriptionsAfter
                leakedSubscriptions @?= []
          , testCase "live HasMinIO conditional writes round-trip on jitml-checkpoints" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              -- Use a unique key per run so a re-run on the same cluster
              -- starts from a clean state for the conflict assertion.
              uniqueSuffix <- pickRandomSuffix
              let bucket = BucketName "jitml-checkpoints"
                  blobKey = "live-test/blob-" <> uniqueSuffix <> ".bin"
                  pointerKey = "live-test/pointer-" <> uniqueSuffix
                  blobRef = ObjectRef bucket (ObjectKey blobKey)
                  pointerRef = ObjectRef bucket (ObjectKey pointerKey)
              withTemporaryMinioObjects
                settings
                "live HasMinIO conditional writes"
                [blobRef, pointerRef]
                ( MinIOSubprocess.runMinIOSubprocess settings $ do
                    first <- putBlobIfAbsent blobRef "weights:v1"
                    case first of
                      Right (ETag _) -> pure ()
                      Left err ->
                        liftIO
                          ( assertFailure
                              ("expected first putBlobIfAbsent OK, got: " <> show err)
                          )
                    second <- putBlobIfAbsent blobRef "weights:v1"
                    case second of
                      Left (SEConflict _) -> pure ()
                      other ->
                        liftIO
                          ( assertFailure
                              ("expected SEConflict on second putBlobIfAbsent, got: " <> show other)
                          )
                    ptr1 <- casPointer pointerRef Nothing "manifest:sha-1"
                    case ptr1 of
                      Right (ETag etag1) -> do
                        ptr2 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-2"
                        case ptr2 of
                          Right (ETag _) -> pure ()
                          Left err ->
                            liftIO
                              ( assertFailure
                                  ("expected pointer CAS OK, got: " <> show err)
                              )
                        ptr3 <- casPointer pointerRef (Just (ETag etag1)) "manifest:sha-3"
                        case ptr3 of
                          Left (SEConflict _) -> pure ()
                          other ->
                            liftIO
                              ( assertFailure
                                  ("expected SEConflict on stale-ETag pointer CAS, got: " <> show other)
                              )
                      Left err ->
                        liftIO
                          ( assertFailure
                              ("expected pointer CAS OK on first write, got: " <> show err)
                          )
                )
          , testCase "live HasMinIO listObjects sees a freshly written object" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                  bucket = BucketName "jitml-checkpoints"
              uniqueSuffix <- pickRandomSuffix
              let ref = ObjectRef bucket (ObjectKey ("live-test/list-" <> uniqueSuffix))
              withTemporaryMinioObjects
                settings
                "live HasMinIO listObjects"
                [ref]
                ( MinIOSubprocess.runMinIOSubprocess settings $ do
                    writeResult <- putBlobIfAbsent ref "hello"
                    requireTemporaryObjectWrite ref writeResult
                    result <- listObjects bucket "live-test/list-"
                    liftIO $ case result of
                      Right refs ->
                        assertBool
                          ( "expected listObjects to include "
                              <> show ref
                              <> " under prefix live-test/list-; got: "
                              <> show refs
                          )
                          (ref `elem` refs)
                      Left err ->
                        assertFailure ("listObjects failed live: " <> show err)
                )
          , testCase "live receipt-bound Pulsar redelivery and equal-payload settlement" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                  substrate = Publication.publicationSubstrate publication
                  -- Exercise receipt settlement on an event topic.  Publishing
                  -- a synthetic command here would also feed the borrowed
                  -- production daemon subscription and make this transport
                  -- test mutate (or repeatedly Nack) a real workload.
                  topic = topologyTopic TrainingEventRoute substrate
              uniqueSuffix <- pickRandomSuffix
              let subscriptionName = "live-receipt-" <> uniqueSuffix
                  subscription = subscriptionFixture topic subscriptionName FromLatest Owned
                  event =
                    Training.TrainingEpoch
                      Training.EpochCompleted
                        { Training.ecExperimentHash =
                            Text.take 16 ("receipt" <> uniqueSuffix <> "0123456789abcdef")
                        , Training.ecEpoch = 1
                        , Training.ecLoss = 0.25
                        , Training.ecValidationLoss = 0.5
                        , Training.ecTimestampNs = 1
                        }
                  expectedWire = encodeTopicPayload topic event
              phaseRef <- newIORef (0 :: Int)
              publishedFirstRef <- newIORef False
              observationsRef <- newIORef ([] :: [(Text, Int)])
              consumeTimed <-
                Timeout.timeout 45_000_000 $
                  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $
                    pulsarConsumeUntil
                      subscription
                      ( \case
                          ConsumerSessionConnected _ -> do
                            published <- liftIO (readIORef publishedFirstRef)
                            if published
                              then pure ()
                              else do
                                liftIO (writeIORef publishedFirstRef True)
                                publishResult <- pulsarPublish topic event
                                liftIO $
                                  case publishResult of
                                    Right _ -> pure ()
                                    Left err ->
                                      assertFailure
                                        ("initial typed Pulsar publish failed live: " <> show err)
                          _ -> pure ()
                      )
                      ( \delivery -> do
                          liftIO (deliveryEvent delivery @?= event)
                          let fingerprint =
                                deliveryReceiptFingerprint (deliveryReceipt delivery)
                              redeliveryCount = deliveryRedeliveryCount delivery
                          liftIO
                            (modifyIORef' observationsRef ((fingerprint, redeliveryCount) :))
                          phase <- liftIO (readIORef phaseRef)
                          case phase of
                            0 -> do
                              liftIO (writeIORef phaseRef 1)
                              pure (continue (nack (RetryRequested "live redelivery proof")))
                            1 -> do
                              -- This delivery necessarily follows the Nack:
                              -- the byte-equal second publication is issued
                              -- only below.  Pulsar 3.0.7's WebSocket handler
                              -- can return the same broker message id here
                              -- while still reporting redeliveryCount = 0, so
                              -- receipt freshness and phase ordering are the
                              -- truthful transport-level redelivery proof.
                              publishResult <- pulsarPublish topic event
                              liftIO $
                                case publishResult of
                                  Right _ -> pure ()
                                  Left err ->
                                    assertFailure
                                      ("second byte-equal typed Pulsar publish failed live: " <> show err)
                              liftIO (writeIORef phaseRef 2)
                              pure (continue ack)
                            _ -> pure (done ack expectedWire)
                      )
              consumedWire <-
                case consumeTimed of
                  Nothing ->
                    assertFailureWithIO
                      "timed out waiting for Nack redelivery and the second equal payload"
                  Just (Left err) ->
                    assertFailureWithIO
                      ("receipt-bound Pulsar consumer failed live: " <> show err)
                  Just (Right payload) -> pure payload
              consumedWire @?= expectedWire
              observations <- reverse <$> readIORef observationsRef
              case observations of
                [(firstReceipt, firstCount), (redeliveredReceipt, redeliveryCount), (secondReceipt, secondCount)] -> do
                  firstCount @?= 0
                  assertBool
                    "broker redelivery count remains non-negative"
                    (redeliveryCount >= 0)
                  secondCount @?= 0
                  assertBool
                    "redelivery receives a fresh opaque receipt"
                    (firstReceipt /= redeliveredReceipt)
                  assertBool
                    "byte-equal publications receive distinct opaque receipts"
                    (firstReceipt /= secondReceipt && redeliveredReceipt /= secondReceipt)
                other ->
                  assertFailure
                    ("expected three receipt observations, got " <> show other)
              assertPulsarSubscriptionAbsent
                topic
                subscriptionName
                15
          , testCase
              "live role-correct daemon subscriptions are held after Coordinator topic reconciliation (Sprint 12.16)"
              $ do
                publication <- requireLivePublication
                let substrate = Publication.publicationSubstrate publication
                    clusterSubscriptions =
                      [ topologySubscription TrainingCommandRoute substrate "jitml-coordinator"
                      , topologySubscription TuneCommandRoute substrate "jitml-coordinator"
                      , topologySubscription RlCommandRoute substrate "jitml-coordinator"
                      ]
                        <> case substrate of
                          AppleSilicon ->
                            [topologySubscription InferenceRequestRoute substrate "jitml-coordinator"]
                          LinuxCPU ->
                            [topologySubscription InferenceRequestRoute substrate "jitml-engine"]
                          LinuxCUDA ->
                            [topologySubscription InferenceRequestRoute substrate "jitml-engine"]
                    appleHostSubscriptions =
                      case substrate of
                        AppleSilicon ->
                          [ topologySubscription InferenceHostCommandRoute AppleSilicon "jitml-host"
                          , topologySubscription TrainingHostCommandRoute AppleSilicon "jitml-host"
                          , topologySubscription TuneHostCommandRoute AppleSilicon "jitml-host"
                          , topologySubscription RlHostCommandRoute AppleSilicon "jitml-host"
                          ]
                        LinuxCPU -> []
                        LinuxCUDA -> []
                    daemonSubscriptions = clusterSubscriptions <> appleHostSubscriptions
                -- Readiness is withheld until the Coordinator has reconciled
                -- the exact topology. Every role-owned route must then have
                -- its named durable subscription and at least one held-open
                -- consumer; Linux Engine owns inference only, while the Apple
                -- host Engine retains the four host-command routes. Pulsar may
                -- briefly expose an empty consumer array while a healthy
                -- WebSocket consumer reconnects, so require two consecutive
                -- full-set attached sweeps within a bounded poll window rather
                -- than accepting or rejecting one instantaneous sample.
                assertPulsarSubscriptionsStablyHaveConsumers
                  daemonSubscriptions
                  2
                  5
          , testCase "live HasHarbor same-repository tag promotion round-trip (Sprint 13.2 Harbor)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = HarborSubprocess.harborSettingsForLocalEdge edgePort
                  registry = HarborSubprocess.harborRegistry settings
              uniqueSuffix <- pickRandomSuffix
              let repository = "library/jitml-harbor-test-" <> uniqueSuffix
                  initialRef = ImageRef (registry <> "/" <> repository <> ":initial")
                  currentRef = ImageRef (registry <> "/" <> repository <> ":current")
              case Publication.publicationSubstrate publication of
                AppleSilicon ->
                  seedHarborOciArtifact settings repository "initial"
                _ -> do
                  -- Linux lanes validate the Docker-backed live push path with
                  -- a tiny single-platform image built directly under the
                  -- unique Harbor tag. Avoid a cached multi-arch docker.io
                  -- source image here: failed routed pushes can leave local
                  -- RepoDigests that make later retries skip required blobs.
                  buildLocalHarborTestImage settings initialRef uniqueSuffix
                  HarborSubprocess.runHarborSubprocess settings $ do
                    pushResult <- harborPushImage initialRef
                    liftIO $ case pushResult of
                      Right _ -> pure ()
                      Left err ->
                        assertFailure ("harborPushImage initial failed: " <> show err)
              -- Drive the live exists/promote flow through HasHarbor.
              HarborSubprocess.runHarborSubprocess settings $ do
                existsInitial <- harborImageExists initialRef
                liftIO $ case existsInitial of
                  Right True -> pure ()
                  other ->
                    assertFailure
                      ( "harborImageExists initial expected Right True, got "
                          <> show other
                      )
                promotionResult <- harborPromoteImage initialRef currentRef
                liftIO $ case promotionResult of
                  Right promoted -> promoted @?= currentRef
                  Left err ->
                    assertFailure ("harborPromoteImage failed: " <> show err)
                existsCurrent <- harborImageExists currentRef
                liftIO $ case existsCurrent of
                  Right True -> pure ()
                  other ->
                    assertFailure
                      ( "harborImageExists current expected Right True, got "
                          <> show other
                      )
              -- Cleanup: remove the test repository through the Harbor API
              -- via curl so a future test run can re-create the same name.
              cleanupOutcome <-
                runStreaming
                  defaultSubprocessEnv
                  ( subprocess
                      "curl"
                      [ "-s"
                      , "-u"
                      , HarborSubprocess.harborUsername settings
                          <> ":"
                          <> HarborSubprocess.harborPassword settings
                      , "-X"
                      , "DELETE"
                      , HarborSubprocess.harborApiBaseUrl settings
                          <> "/v2.0/projects/library/repositories/"
                          <> Text.drop (Text.length "library/") repository
                      ]
                  )
              assertProcessExitCode
                "Harbor live-test repository cleanup"
                ExitSuccess
                cleanupOutcome
          , testCase "live daemon places StartTraining by substrate (Sprint 13.3 / 12.12)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                  substrate = Publication.publicationSubstrate publication
                  topic = topologyTopic TrainingCommandRoute substrate
                  eventTopic = topologyTopic TrainingEventRoute substrate
              uniqueSuffix <- pickRandomSuffix
              -- 16 hex chars used as the experiment hash so the rendered Job
              -- name `jitml-train-<hash>` stays well under the K8s 63-char
              -- limit. `JitML.Service.Workload.workloadName` uses the full
              -- experiment-hash as the suffix (no truncation), so the
              -- expected Job name matches verbatim here.
              let experimentHash =
                    Text.take 16 ("liveint" <> uniqueSuffix <> "abcdef0123456789")
                  (trainingStart, trainingPlan) =
                    -- The live completion contract uses the unchanged ProductRow
                    -- convergence bar, so execute the same registered MNIST
                    -- schedule as the publisher.  The former 5 x 4096 smoke
                    -- produced 0.8935546875 against the binding 0.90 bar and
                    -- correctly could not mint CompletedTraining.
                    preparedStartTraining
                      Training.StartTraining
                        { Training.stExperimentHash = experimentHash
                        , Training.stDhallObjectKey = "experiments/mnist.dhall"
                        , Training.stSubstrate = substrate
                        , Training.stSeed = 1001
                        , Training.stEpochs = 10
                        , Training.stBatchSize = 64
                        , Training.stPlanId = ""
                        , Training.stResolvedPlan = ""
                        , Training.stTrainingExamples = 7000
                        , Training.stEvaluationExamples = 1000
                        }
                  command = Training.TrainingStart trainingStart
                  expectedJobName = "jitml-train-" <> experimentHash
              case substrate of
                AppleSilicon -> do
                  assertAppleHostForwardingSmoke
                    pulsarSettings
                    (topologyTopic TrainingHostCommandRoute AppleSilicon)
                    ("live-training-host-command-sub-" <> uniqueSuffix)
                    experimentHash
                    command
                    (publishOrFail pulsarSettings topic command "StartTraining")
                    20
                  assertJobDoesNotAppear expectedJobName 5
                _ -> do
                  contract <-
                    case LiveEvidence.supervisedLiveContract
                      (supervisedPlanId trainingPlan)
                      (Training.stEpochs trainingStart) of
                      Left err ->
                        assertFailureWithIO
                          ("invalid live supervised evidence contract: " <> show err)
                      Right value -> pure value
                  let eventSubscription =
                        subscriptionFixture
                          eventTopic
                          ("live-training-event-sub-" <> uniqueSuffix)
                          FromLatest
                          Owned
                      workflow =
                        LiveWorkflow.LiveWorkflow
                          { LiveWorkflow.liveWorkflowPlanId = supervisedPlanId trainingPlan
                          , LiveWorkflow.liveWorkflowCommand =
                              LiveWorkflow.ProtocolCommand topic command
                          , LiveWorkflow.liveWorkflowEventSubscription = eventSubscription
                          , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                          , LiveWorkflow.liveWorkflowIngest =
                              LiveEvidence.ingestSupervisedLiveEvent
                                (supervisedPlanId trainingPlan)
                                experimentHash
                                contract
                          , LiveWorkflow.liveWorkflowFinish = finishContract contract
                          , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                          }
                      backend =
                        clusterJobBackend
                          (supervisedPlanId trainingPlan)
                          expectedJobName
                          600
                          600
                  result <-
                    LiveWorkflow.runLiveWorkflow
                      workflow
                      (livePulsarTransport pulsarSettings)
                      backend
                  completed <-
                    requireCompletedLiveWorkflow "live supervised workflow" result
                  Map.keys
                    ( LiveEvidence.supervisedTerminalEpochSnapshot
                        (LiveWorkflow.completedRunEvidence completed)
                    )
                    @?= [Training.stEpochs trainingStart]
          , testCase
              "live duplicate StartTraining transport smoke produces one daemon-side dedup-skip (Sprint 13.3 dedup)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    pulsarSettings =
                      PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    topic = topologyTopic TrainingCommandRoute substrate
                uniqueSuffix <- pickRandomSuffix
                let experimentHash =
                      Text.take 16 ("dedup" <> uniqueSuffix <> "abcdef0123456789")
                    (trainingStart, _) =
                      preparedStartTraining
                        Training.StartTraining
                          { Training.stExperimentHash = experimentHash
                          , Training.stDhallObjectKey = "experiments/mnist.dhall"
                          , Training.stSubstrate = substrate
                          , Training.stSeed = 42
                          , Training.stEpochs = 1
                          , Training.stBatchSize = 32
                          , Training.stPlanId = ""
                          , Training.stResolvedPlan = ""
                          , Training.stTrainingExamples = 64
                          , Training.stEvaluationExamples = 16
                          }
                    command = Training.TrainingStart trainingStart
                    expectedJobName = "jitml-train-" <> experimentHash
                withTemporaryKubernetesJobs
                  "live duplicate StartTraining"
                  [expectedJobName]
                  ( do
                      eventId <-
                        expectValidationSuccess
                          (daemonCommandEventId (TrainingDaemonCommand substrate command))
                      -- Publish the identical typed StartTraining command twice.
                      -- Its plan-bound semantic EventId is stable, so the daemon's
                      -- per-domain DedupCache skips dispatch on the second consume.
                      case substrate of
                        AppleSilicon -> do
                          assertAppleHostForwardingSmoke
                            pulsarSettings
                            (topologyTopic TrainingHostCommandRoute AppleSilicon)
                            ("live-training-dedup-host-command-sub-" <> uniqueSuffix)
                            experimentHash
                            command
                            ( do
                                publishOrFail
                                  pulsarSettings
                                  topic
                                  command
                                  "first duplicate StartTraining"
                                publishOrFail
                                  pulsarSettings
                                  topic
                                  command
                                  "second duplicate StartTraining"
                            )
                            20
                          assertJobDoesNotAppear expectedJobName 5
                        _ -> do
                          publishOrFail
                            pulsarSettings
                            topic
                            command
                            "first duplicate StartTraining"
                          publishOrFail
                            pulsarSettings
                            topic
                            command
                            "second duplicate StartTraining"
                          -- The daemon consumes the first envelope (dispatches the
                          -- Kubernetes Job, acks) and consumes the second envelope
                          -- (dedup-skips, acks). Wait briefly for the Job to appear
                          -- as evidence the first consume reached the dispatcher.
                          jobAppeared <- waitForJob expectedJobName 30
                          assertBool
                            ( "expected Job "
                                <> Text.unpack expectedJobName
                                <> " to be applied by the daemon's first consume"
                            )
                            jobAppeared
                      -- Drain a recent HA-wide command-role log window across both
                      -- Engine and Coordinator pods, then assert at least one
                      -- "deduplicated training <event-id>" line matches the command.
                      -- The EventId is unique to this test, so a time window is more
                      -- stable than byte-slicing one Deployment log stream.
                      let waitForDedup :: Int -> IO ProcessOutcome
                          waitForDedup remaining = do
                            logOutcome <- daemonLogStream (Just "2m")
                            logTranscript <- requireProcessSuccess "daemon log stream" logOutcome
                            let tail' = processTranscriptStdout logTranscript
                                needle =
                                  "deduplicated training "
                                    <> eventIdText eventId
                            if needle `Text.isInfixOf` tail' || remaining <= 0
                              then pure logOutcome
                              else do
                                Control.Concurrent.threadDelay 1_000_000
                                waitForDedup (remaining - 1)
                      finalLogOutcome <- waitForDedup 30
                      assertProcessStreamContains
                        "daemon deduplication log within 30s"
                        ProcessStdout
                        ("deduplicated training " <> eventIdText eventId)
                        finalLogOutcome
                  )
          , testCase
              "live daemon places StartRLRun by substrate and Linux emits rl.event episodes (Sprint 13.5/13.6/12.12)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    pulsarSettings =
                      PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    commandTopic = topologyTopic RlCommandRoute substrate
                    eventTopic = topologyTopic RlEventRoute substrate
                uniqueSuffix <- pickRandomSuffix
                let experimentHash =
                      Text.take 16 ("liverl" <> uniqueSuffix <> "abcdef0123456789")
                    subscription = "live-rl-event-sub-" <> uniqueSuffix
                    evalEpisodes = 2 :: Int
                    command =
                      ProtoRl.RlStart
                        ProtoRl.StartRLRun
                          { ProtoRl.srlExperimentHash = experimentHash
                          , ProtoRl.srlAlgorithm = "PPO"
                          , ProtoRl.srlEnvironment = "cartpole"
                          , ProtoRl.srlSubstrate = substrate
                          , ProtoRl.srlSeed = 7
                          , ProtoRl.srlMaxSteps = 64
                          , ProtoRl.srlEvalEpisodes = fromIntegral evalEpisodes
                          }
                    expectedJobName = "jitml-rl-" <> experimentHash
                case substrate of
                  AppleSilicon -> do
                    assertAppleHostForwardingSmoke
                      pulsarSettings
                      (topologyTopic RlHostCommandRoute AppleSilicon)
                      ("live-rl-host-command-sub-" <> uniqueSuffix)
                      experimentHash
                      command
                      (publishOrFail pulsarSettings commandTopic command "StartRLRun")
                      20
                    assertJobDoesNotAppear expectedJobName 5
                  _ -> do
                    contractPlanId <-
                      expectValidationSuccess
                        ( planIdFromCanonicalText
                            (encodeTopicPayload commandTopic command)
                        )
                    contract <-
                      case LiveEvidence.rlLiveContract contractPlanId (fromIntegral evalEpisodes) of
                        Left err ->
                          assertFailureWithIO
                            ("invalid live RL evidence contract: " <> show err)
                        Right value -> pure value
                    let eventSubscription =
                          subscriptionFixture eventTopic subscription FromLatest Owned
                        workflow =
                          LiveWorkflow.LiveWorkflow
                            { LiveWorkflow.liveWorkflowPlanId = contractPlanId
                            , LiveWorkflow.liveWorkflowCommand =
                                LiveWorkflow.ProtocolCommand commandTopic command
                            , LiveWorkflow.liveWorkflowEventSubscription = eventSubscription
                            , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                            , LiveWorkflow.liveWorkflowIngest =
                                LiveEvidence.ingestRlLiveEvent
                                  contractPlanId
                                  Nothing
                                  experimentHash
                                  contract
                            , LiveWorkflow.liveWorkflowFinish = finishContract contract
                            , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                            }
                        backend =
                          clusterJobBackend contractPlanId expectedJobName 600 600
                    result <-
                      LiveWorkflow.runLiveWorkflow
                        workflow
                        (livePulsarTransport pulsarSettings)
                        backend
                    completed <- requireCompletedLiveWorkflow "live RL workflow" result
                    let evidence = LiveWorkflow.completedRunEvidence completed
                    Map.keys (LiveEvidence.rlCompletedEpisodes evidence)
                      @?= [0 .. fromIntegral evalEpisodes - 1]
          , testCase
              "live PPO cartpole convergence through daemon dispatch clears the literature threshold (Sprint 13.6)"
              $ do
                -- Sprint 13.6 closure for the PPO/cartpole cohort. Publishes a
                -- StartRLRun with a real convergence budget (80 PPO iterations
                -- × 1024 rollout steps), waits for the daemon-dispatched Job to
                -- complete, collects per-iteration EpisodeDone rewards off
                -- rl.event.<substrate>, and asserts the median of the latter
                -- half clears the in-code literature threshold − slack for
                -- (PPO, cartpole). No committed reward fixtures — the bar is
                -- the in-code threshold table and the data is the live
                -- daemon-dispatched run.
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    pulsarSettings =
                      PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    commandTopic = topologyTopic RlCommandRoute substrate
                    eventTopic = topologyTopic RlEventRoute substrate
                uniqueSuffix <- pickRandomSuffix
                let experimentHash =
                      Text.take 16 ("livecv" <> uniqueSuffix <> "abcdef0123456789")
                    subscription = "live-rl-convergence-sub-" <> uniqueSuffix
                    evalEpisodes = 200 :: Int
                    maxSteps = 2048 :: Int
                    command =
                      ProtoRl.RlStart
                        ProtoRl.StartRLRun
                          { ProtoRl.srlExperimentHash = experimentHash
                          , ProtoRl.srlAlgorithm = "PPO"
                          , ProtoRl.srlEnvironment = "cartpole"
                          , ProtoRl.srlSubstrate = substrate
                          , ProtoRl.srlSeed = 42
                          , ProtoRl.srlMaxSteps = fromIntegral maxSteps
                          , ProtoRl.srlEvalEpisodes = fromIntegral evalEpisodes
                          }
                    expectedJobName = "jitml-rl-" <> experimentHash
                threshold <-
                  case cohortThreshold "PPO" "cartpole" of
                    Just t -> pure t
                    Nothing ->
                      assertFailure
                        "missing PPO/cartpole entry in JitML.RL.ConvergenceThresholds"
                        >> pure (ConvergenceThreshold 0 0)
                case substrate of
                  AppleSilicon -> do
                    assertAppleHostForwardingSmoke
                      pulsarSettings
                      (topologyTopic RlHostCommandRoute AppleSilicon)
                      ("live-rl-convergence-host-command-sub-" <> uniqueSuffix)
                      experimentHash
                      command
                      ( publishOrFail
                          pulsarSettings
                          commandTopic
                          command
                          "StartRLRun convergence"
                      )
                      20
                    assertJobDoesNotAppear expectedJobName 5
                  _ -> do
                    contractPlanId <-
                      expectValidationSuccess
                        ( planIdFromCanonicalText
                            (encodeTopicPayload commandTopic command)
                        )
                    contract <-
                      case LiveEvidence.rlLiveContract contractPlanId (fromIntegral evalEpisodes) of
                        Left err ->
                          assertFailureWithIO
                            ("invalid live convergence evidence contract: " <> show err)
                        Right value -> pure value
                    let eventSubscription =
                          subscriptionFixture eventTopic subscription FromLatest Owned
                        workflow =
                          LiveWorkflow.LiveWorkflow
                            { LiveWorkflow.liveWorkflowPlanId = contractPlanId
                            , LiveWorkflow.liveWorkflowCommand =
                                LiveWorkflow.ProtocolCommand commandTopic command
                            , LiveWorkflow.liveWorkflowEventSubscription = eventSubscription
                            , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                            , LiveWorkflow.liveWorkflowIngest =
                                LiveEvidence.ingestRlLiveEvent
                                  contractPlanId
                                  Nothing
                                  experimentHash
                                  contract
                            , LiveWorkflow.liveWorkflowFinish = finishContract contract
                            , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                            }
                        backend =
                          clusterJobBackend contractPlanId expectedJobName 7200 7200
                    result <-
                      LiveWorkflow.runLiveWorkflow
                        workflow
                        (livePulsarTransport pulsarSettings)
                        backend
                    completed <-
                      requireCompletedLiveWorkflow "live PPO convergence workflow" result
                    let evidence = LiveWorkflow.completedRunEvidence completed
                        medianTail =
                          finiteMeasurementValue
                            (LiveEvidence.rlCompletedMedianReward evidence)
                        episodeCount =
                          Map.size (LiveEvidence.rlCompletedEpisodes evidence)
                    assertBool
                      ( "live PPO/cartpole median(tail) = "
                          <> show medianTail
                          <> " must clear "
                          <> show (literatureTarget threshold - slack threshold)
                          <> " ("
                          <> show episodeCount
                          <> " exact evaluation episodes collected)"
                      )
                      (passesConvergence threshold medianTail)
          , testCase "live checkpoint snapshot round-trip through MinIOSubprocess (Sprint 13.7)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-ckpt-" <> uniqueSuffix
                  payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
                  blobObjectKey =
                    Checkpoint.blobKey
                      experimentHash
                      (WeightCodec.jmw1ContentSha payload)
                  manifest =
                    ( Checkpoint.emptyManifest
                        "m1"
                        experimentHash
                        [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
                    )
                      { Checkpoint.manifestStep = 1
                      , Checkpoint.manifestMetrics = [("validation_accuracy", 0.9)]
                      }
                  ownedObjects =
                    [ CheckpointStore.checkpointObjectRef blobObjectKey
                    , CheckpointStore.checkpointObjectRef
                        ( Checkpoint.manifestKey
                            experimentHash
                            (Checkpoint.manifestContentSha manifest)
                        )
                    ]
              withTemporaryMinioObjects
                settings
                "live checkpoint snapshot"
                ownedObjects
                ( MinIOSubprocess.runMinIOSubprocess settings $ do
                    first <-
                      CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                        manifest
                        [(blobObjectKey, payload)]
                    liftIO $ case first of
                      Left err ->
                        assertFailure
                          ("expected live checkpoint write OK, got: " <> show err)
                      Right candidate ->
                        CheckpointStore.storedPointerResult
                          (CheckpointStore.candidateStoredCheckpoint candidate)
                          @?= Checkpoint.PointerNotWritten
                            (Checkpoint.latestPointerKey experimentHash)
                    -- A second identical write must idempotently succeed on the
                    -- blob + manifest writes without publishing latest.
                    second <-
                      CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
                        manifest
                        [(blobObjectKey, payload)]
                    liftIO $ case second of
                      Left err ->
                        assertFailure
                          ("expected idempotent live re-write, got: " <> show err)
                      Right candidate ->
                        CheckpointStore.storedPointerResult
                          (CheckpointStore.candidateStoredCheckpoint candidate)
                          @?= Checkpoint.PointerNotWritten
                            (Checkpoint.latestPointerKey experimentHash)
                )
          , testCase "live GC: listCheckpointManifestsMinIO + executeGcPlan reap (Sprint 13.7)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-gc-" <> uniqueSuffix
                  blobObjectKeyForStep stepIdx =
                    Checkpoint.blobKey experimentHash ("blob-step-" <> Text.pack (show stepIdx))
                  manifestFor stepIdx =
                    (Checkpoint.emptyManifest "m" experimentHash [])
                      { Checkpoint.manifestStep = fromIntegral (stepIdx :: Int)
                      , Checkpoint.manifestTensors =
                          [ Checkpoint.TensorBlob
                              ("dense.weight.step" <> Text.pack (show stepIdx))
                              [1]
                              (blobObjectKeyForStep stepIdx)
                          ]
                      }
                  steps = [1, 2, 3] :: [Int]
                  manifests = fmap manifestFor steps
                  payloadFor stepIdx = Checkpoint.encodeJmw1 [fromIntegral stepIdx]
                  ownedObjects =
                    fmap
                      (CheckpointStore.checkpointObjectRef . blobObjectKeyForStep)
                      steps
                      <> fmap
                        ( CheckpointStore.checkpointObjectRef
                            . Checkpoint.manifestKey experimentHash
                            . Checkpoint.manifestContentSha
                        )
                        manifests
              withTemporaryMinioObjects
                settings
                "live GC plan fixture"
                ownedObjects
                ( MinIOSubprocess.runMinIOSubprocess settings $ do
                    -- Stage three manifests + blobs without advancing the latest
                    -- pointer (this is a controlled fixture for GC, not a real
                    -- training run).
                    mapM_
                      ( \(stepIdx, manifest) -> do
                          let blobRef =
                                CheckpointStore.checkpointObjectRef
                                  (blobObjectKeyForStep stepIdx)
                              manifestRef =
                                CheckpointStore.checkpointObjectRef
                                  ( Checkpoint.manifestKey
                                      experimentHash
                                      (Checkpoint.manifestContentSha manifest)
                                  )
                          blobWrite <-
                            putBlobBytesIfAbsent
                              blobRef
                              (ByteString.Lazy.toStrict (payloadFor stepIdx))
                          requireTemporaryObjectWrite blobRef blobWrite
                          manifestWrite <-
                            putBlobBytesIfAbsent
                              manifestRef
                              ( ByteString.Lazy.toStrict
                                  (Checkpoint.encodeManifestCbor manifest)
                              )
                          requireTemporaryObjectWrite manifestRef manifestWrite
                      )
                      (zip steps manifests)
                    -- Live list: assert the three manifests are visible through
                    -- the routed S3 list-objects call.
                    listing <- CheckpointStore.listCheckpointManifestsMinIO experimentHash
                    liftIO $ case listing of
                      Left err ->
                        assertFailure
                          ("listCheckpointManifestsMinIO failed live: " <> show err)
                      Right ms ->
                        length ms @?= 3
                    -- Build a LastN 2 plan: should reap exactly one manifest
                    -- (the one with the lowest step).
                    let listed = case listing of
                          Right ms -> ms
                          _ -> []
                        plan =
                          CheckpointStore.buildGcPlan
                            experimentHash
                            (CheckpointStore.LastN 2)
                            listed
                            []
                    liftIO $ do
                      CheckpointStore.gcNoOp plan @?= False
                      length (CheckpointStore.gcReapEvents plan) @?= 1
                    executed <- CheckpointStore.executeGcPlan plan
                    liftIO $ do
                      CheckpointStore.gcExecutedReapedManifests executed @?= 1
                      CheckpointStore.gcExecutedReapedBlobs executed @?= 1
                      CheckpointStore.gcExecutedDeleteFailures executed @?= []
                    -- A second list should now show only 2 manifests.
                    listingAfter <-
                      CheckpointStore.listCheckpointManifestsMinIO experimentHash
                    liftIO $ case listingAfter of
                      Left err ->
                        assertFailure
                          ("post-GC list failed: " <> show err)
                      Right ms ->
                        length ms @?= 2
                )
          , testCase "live jitml internal gc reaps from live MinIO (Sprint 13.7 CLI)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-cli-gc-" <> uniqueSuffix
                  steps = [1 .. 6] :: [Int]
                  blobObjectKeyForStep stepIdx =
                    Checkpoint.blobKey experimentHash ("blob-step-" <> Text.pack (show stepIdx))
                  manifestFor stepIdx =
                    (Checkpoint.emptyManifest "m" experimentHash [])
                      { Checkpoint.manifestStep = fromIntegral stepIdx
                      , Checkpoint.manifestTensors =
                          [ Checkpoint.TensorBlob
                              ("dense.weight.step" <> Text.pack (show stepIdx))
                              [1]
                              (blobObjectKeyForStep stepIdx)
                          ]
                      }
                  manifests = fmap manifestFor steps
                  payloadFor stepIdx = Checkpoint.encodeJmw1 [fromIntegral stepIdx]
                  ownedObjects =
                    fmap
                      (CheckpointStore.checkpointObjectRef . blobObjectKeyForStep)
                      steps
                      <> fmap
                        ( CheckpointStore.checkpointObjectRef
                            . Checkpoint.manifestKey experimentHash
                            . Checkpoint.manifestContentSha
                        )
                        manifests
              withTemporaryMinioObjects
                settings
                "live CLI GC fixture"
                ownedObjects
                ( do
                    -- Stage six manifests + blobs so that the CLI's hardcoded
                    -- `LastN 5` retention reaps exactly one (the lowest step).
                    MinIOSubprocess.runMinIOSubprocess settings $
                      mapM_
                        ( \(stepIdx, manifest) -> do
                            let blobRef =
                                  CheckpointStore.checkpointObjectRef
                                    (blobObjectKeyForStep stepIdx)
                                manifestRef =
                                  CheckpointStore.checkpointObjectRef
                                    ( Checkpoint.manifestKey
                                        experimentHash
                                        (Checkpoint.manifestContentSha manifest)
                                    )
                            blobWrite <-
                              putBlobBytesIfAbsent
                                blobRef
                                (ByteString.Lazy.toStrict (payloadFor stepIdx))
                            requireTemporaryObjectWrite blobRef blobWrite
                            manifestWrite <-
                              putBlobBytesIfAbsent
                                manifestRef
                                ( ByteString.Lazy.toStrict
                                    (Checkpoint.encodeManifestCbor manifest)
                                )
                            requireTemporaryObjectWrite manifestRef manifestWrite
                        )
                        (zip steps manifests)
                    jitmlBinary <- locateJitmlBinary
                    case jitmlBinary of
                      Nothing ->
                        assertFailure
                          "jitml binary not found — needed for Sprint 13.7 CLI gc live test"
                      Just binary -> do
                        repoRoot <- makeAbsolute "."
                        let gcCmd =
                              (subprocess binary ["internal", "gc", experimentHash])
                                { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
                                }
                        -- First invocation should reap 1 manifest (LastN 5 of 6).
                        firstOutcome <- runStreaming defaultSubprocessEnv gcCmd
                        assertProcessExitCode "jitml internal gc first run" ExitSuccess firstOutcome
                        assertProcessStreamContains
                          "jitml internal gc first run"
                          ProcessStdout
                          "reaped=1"
                          firstOutcome
                        assertProcessStreamContains
                          "jitml internal gc first run"
                          ProcessStdout
                          "reaped-blobs=1"
                          firstOutcome
                        -- Second invocation against the same store: 5 manifests
                        -- remain → kept=5, reaped=0 → gcNoOp → exit 3.
                        secondOutcome <- runStreaming defaultSubprocessEnv gcCmd
                        assertProcessExitCode "jitml internal gc second run" (ExitFailure 3) secondOutcome
                )
          , testCase
              "live jitml internal gc publishes GcReapedEvent on gc.event.<substrate> (Sprint 13.7 events)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                    pulsarSettings =
                      PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    topic = topologyTopic GcEventRoute substrate
                uniqueSuffix <- pickRandomSuffix
                let experimentHash = "live-gce-" <> uniqueSuffix
                    subscription = "live-gc-event-sub-" <> uniqueSuffix
                    steps = [1 .. 6] :: [Int]
                    blobKeyFor stepIdx =
                      Checkpoint.blobKey experimentHash ("blob-step-" <> Text.pack (show stepIdx))
                    manifestFor stepIdx =
                      (Checkpoint.emptyManifest "gce" experimentHash [])
                        { Checkpoint.manifestStep = fromIntegral stepIdx
                        , Checkpoint.manifestTensors =
                            [ Checkpoint.TensorBlob
                                ("dense.weight.step" <> Text.pack (show stepIdx))
                                [1]
                                (blobKeyFor stepIdx)
                            ]
                        }
                    manifests = fmap manifestFor steps
                    payloadFor stepIdx = Checkpoint.encodeJmw1 [fromIntegral stepIdx]
                    lowestStepSha = Checkpoint.manifestContentSha (manifestFor 1)
                -- Establish the broker cursor before running GC. Publishing
                -- before a WebSocket subscription exists can place the event
                -- before the cursor even when the requested initial position
                -- is Earliest.
                binary <-
                  locateJitmlBinary >>= \case
                    Nothing ->
                      assertFailureWithIO
                        "jitml binary not found — needed for Sprint 13.7 events live test"
                    Just value -> pure value
                repoRoot <- makeAbsolute "."
                let gcCmd =
                      (subprocess binary ["internal", "gc", experimentHash])
                        { JitML.Sub.Subprocess.subprocessWorkingDirectory =
                            Just repoRoot
                        }
                    executableCommand = LiveWorkflow.ExecutableCommand gcCmd
                    renderedGcCommand =
                      LiveWorkflow.liveCommandCanonicalText executableCommand
                contractPlanId <-
                  expectValidationSuccess (planIdFromCanonicalText renderedGcCommand)
                let contract =
                      RunContract.exactlyOne
                        "gc-reaped-event"
                        contractPlanId
                    gcSubscription =
                      subscriptionFixture topic subscription FromLatest Owned
                    ingestGcEvent progress envelope
                      | ProtoGc.gcEventExperimentHash envelope /= experimentHash =
                          Right progress
                      | otherwise =
                          case RunContract.evidenceEvent
                            contractPlanId
                            "gc-reaped-event"
                            ()
                            envelope of
                            Failure errors -> Left (Text.pack (show errors))
                            Success event ->
                              Bifunctor.first
                                (Text.pack . show)
                                (RunContract.ingestEvent contract progress event)
                    workflow =
                      LiveWorkflow.LiveWorkflow
                        { LiveWorkflow.liveWorkflowPlanId = contractPlanId
                        , LiveWorkflow.liveWorkflowCommand = executableCommand
                        , LiveWorkflow.liveWorkflowEventSubscription = gcSubscription
                        , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                        , LiveWorkflow.liveWorkflowIngest = ingestGcEvent
                        , LiveWorkflow.liveWorkflowFinish = finishContract contract
                        , LiveWorkflow.liveWorkflowRenderViolation = id
                        }
                    backend =
                      executableCommandBackend
                        contractPlanId
                        ("gc-" <> experimentHash)
                        60
                    blobRefs =
                      fmap
                        (CheckpointStore.checkpointObjectRef . blobKeyFor)
                        steps
                    manifestRefs =
                      fmap
                        ( CheckpointStore.checkpointObjectRef
                            . Checkpoint.manifestKey experimentHash
                            . Checkpoint.manifestContentSha
                        )
                        manifests
                    ownedObjects = blobRefs <> manifestRefs
                    stageObjects =
                      MinIOSubprocess.runMinIOSubprocess minioSettings $
                        mapM_
                          ( \(stepIdx, manifest) -> do
                              let blobRef =
                                    CheckpointStore.checkpointObjectRef
                                      (blobKeyFor stepIdx)
                                  manifestRef =
                                    CheckpointStore.checkpointObjectRef
                                      ( Checkpoint.manifestKey
                                          experimentHash
                                          (Checkpoint.manifestContentSha manifest)
                                      )
                              blobWrite <-
                                putBlobBytesIfAbsent
                                  blobRef
                                  (ByteString.Lazy.toStrict (payloadFor stepIdx))
                              requireTemporaryObjectWrite blobRef blobWrite
                              manifestWrite <-
                                putBlobBytesIfAbsent
                                  manifestRef
                                  ( ByteString.Lazy.toStrict
                                      (Checkpoint.encodeManifestCbor manifest)
                                  )
                              requireTemporaryObjectWrite manifestRef manifestWrite
                          )
                          (zip steps manifests)
                    cleanupObjects =
                      cleanupMinioObjects
                        minioSettings
                        "live GC event fixture"
                        ownedObjects
                result <-
                  LiveWorkflow.withOwnedCleanup cleanupObjects $ do
                    -- Stage six manifests + blobs inside the cleanup scope so
                    -- a partial write or later assertion cannot leak them.
                    stageObjects
                    LiveWorkflow.runLiveWorkflow
                      workflow
                      (liveSubprocessTransport pulsarSettings)
                      backend
                completed <- requireCompletedLiveWorkflow "live GC workflow" result
                let envelope =
                      RunContract.exactlyOneValue
                        (LiveWorkflow.completedRunEvidence completed)
                ProtoGc.gcEventExperimentHash envelope @?= experimentHash
                ProtoGc.gcEventManifestSha envelope @?= lowestStepSha
                ProtoGc.gcEventStepAtReap envelope @?= 1
                ProtoGc.gcEventSubstrate envelope
                  @?= substrate
          , testCase
              "live non-product V1 checkpoint is adopted but rejected by completed admission"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    minioSettings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                uniqueSuffix <- pickRandomSuffix
                let experimentHash = "live-inference-" <> uniqueSuffix
                    payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
                    (manifest, completedWitness, blobObjectKey) =
                      completedLegacySnapshotForPayload
                        "m1"
                        experimentHash
                        "dense.weight"
                        [2, 2]
                        1
                        [("validation_accuracy", 0.9)]
                        payload
                    stageCheckpoint =
                      MinIOSubprocess.runMinIOSubprocess minioSettings $ do
                        writeResult <-
                          CheckpointStore.writeCompletedCheckpointSnapshotWithMinIO
                            Nothing
                            completedWitness
                            manifest
                            [(blobObjectKey, payload)]
                        liftIO $ case writeResult of
                          Left err ->
                            assertFailure ("checkpoint write failed: " <> show err)
                          Right _ -> pure ()
                    cleanupCheckpoint =
                      cleanupMinioObjects
                        minioSettings
                        "live inference checkpoint fixture"
                        [ CheckpointStore.checkpointObjectRef blobObjectKey
                        , CheckpointStore.checkpointObjectRef
                            ( Checkpoint.manifestKey
                                experimentHash
                                (Checkpoint.manifestContentSha manifest)
                            )
                        , CheckpointStore.checkpointObjectRef
                            (Checkpoint.latestPointerKey experimentHash)
                        ]
                withOwnedScenarioCleanup
                  "live legacy completed checkpoint"
                  cleanupCheckpoint
                  $ do
                    stageCheckpoint
                    admission <-
                      MinIOSubprocess.runMinIOSubprocess
                        minioSettings
                        (CheckpointStore.admitLatestCompletedCheckpoint experimentHash)
                    case admission of
                      Left
                        ( CheckpointStore.AdmissionCompletedV1ProductRowRequired
                            rejectedExperiment
                          )
                          | rejectedExperiment == experimentHash -> pure ()
                      Left err ->
                        assertFailure
                          ("expected non-product V1 admission rejection, got: " <> show err)
                      Right _ ->
                        assertFailure
                          "legacy V1 checkpoint unexpectedly became inference-admitted"
          , testCase "live tune trial persist + replay round-trip (Sprint 13.10)" $ do
              publication <- requireLivePublication
              let edgePort = Publication.publicationEdgePort publication
                  settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
              uniqueSuffix <- pickRandomSuffix
              let experimentHash = "live-tune-" <> uniqueSuffix
                  seeds = [101, 102, 103]
                  transcripts =
                    zipWith
                      ( \seed trialIndex ->
                          Tune.terminalTrialTranscript
                            experimentHash
                            seed
                            (Tune.trialObjectiveResult Tune.Grid trialIndex)
                      )
                      seeds
                      [0 ..]
                  trialRefs =
                    fmap
                      ( ObjectRef (BucketName "jitml-trials")
                          . ObjectKey
                          . Tune.trialStorageKey experimentHash
                      )
                      seeds
              withTemporaryMinioObjects
                settings
                "live Tune replay fixture"
                trialRefs
                ( MinIOSubprocess.runMinIOSubprocess settings $ do
                    -- Persist each trial transcript through the production
                    -- HasMinIO instance; the resulting ETag is opaque and just
                    -- needs to be `Right`.
                    mapM_
                      ( \transcript -> do
                          written <- TuneResume.persistTrialTranscript transcript
                          liftIO $ case written of
                            Right _ -> pure ()
                            Left err ->
                              assertFailure
                                ( "persistTrialTranscript failed live for seed "
                                    <> show (Tune.transcriptTrialSeed transcript)
                                    <> ": "
                                    <> show err
                                )
                      )
                      transcripts
                    -- Replay the sweep and assert the round-trip matches.
                    outcome <- TuneResume.replaySweep experimentHash seeds
                    liftIO $ do
                      TuneResume.resumedSeeds outcome @?= seeds
                      TuneResume.resumeReadFailures outcome @?= []
                      TuneResume.resumedTrials outcome @?= transcripts
                )
          , testCase
              "live daemon dispatches resolved Tune plan and emits contract-complete events (Sprint 9.17 / 13.10 / 12.12)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    commandTopic = topologyTopic TuneCommandRoute substrate
                    eventTopic = topologyTopic TuneEventRoute substrate
                uniqueSuffix <- pickRandomSuffix
                let experimentHash =
                      Text.take 16 ("tune" <> uniqueSuffix <> "abcdef0123456789")
                    subscription = "live-tune-event-sub-" <> uniqueSuffix
                    (start, plan) =
                      -- Completion is held to the unchanged ProductRow
                      -- best-objective bar, so execute the registered MNIST
                      -- schedule used by the product publisher. The former
                      -- two-trial, one-update smoke produced two 0.5 objectives
                      -- and correctly could not mint CompletedTraining.
                      preparedStartSweep
                        (registeredTuningStartSweep substrate experimentHash)
                    command = ProtoTune.TuneStart start
                    expectedJobName = "jitml-tune-" <> experimentHash
                    expectedPlanId = planIdText (tuningPlanId plan)
                    expectedPromotions = quantityValue (tuningPlanPromotions plan)
                    expectedTrials = quantityValue (tuningPlanTrials plan)
                ProtoTune.ssPlanId start @?= expectedPlanId
                ProtoTune.ssExperimentHash start
                  @?= runPlanExperimentId (tuningPlanRunPlan plan)
                fromIntegral (ProtoTune.ssTrialBudget start) @?= expectedTrials
                fromIntegral (ProtoTune.ssPromotions start) @?= expectedPromotions
                assertBool
                  "prepared StartSweep must carry a canonical resolved plan"
                  (not (Text.null (ProtoTune.ssResolvedPlan start)))
                case substrate of
                  AppleSilicon -> do
                    assertAppleHostForwardingSmoke
                      pulsarSettings
                      (topologyTopic TuneHostCommandRoute AppleSilicon)
                      ("live-tune-host-command-sub-" <> uniqueSuffix)
                      experimentHash
                      command
                      (publishOrFail pulsarSettings commandTopic command "StartSweep")
                      20
                    assertJobDoesNotAppear expectedJobName 5
                  _ -> do
                    let contract = tuningCompletionContract plan
                        eventSubscription =
                          subscriptionFixture eventTopic subscription FromLatest Owned
                        workflow =
                          LiveWorkflow.LiveWorkflow
                            { LiveWorkflow.liveWorkflowPlanId = tuningPlanId plan
                            , LiveWorkflow.liveWorkflowCommand =
                                LiveWorkflow.ProtocolCommand commandTopic command
                            , LiveWorkflow.liveWorkflowEventSubscription = eventSubscription
                            , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                            , LiveWorkflow.liveWorkflowIngest = ingestTuneEvent plan
                            , LiveWorkflow.liveWorkflowFinish = finishContract contract
                            , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                            }
                        backend =
                          clusterJobBackend
                            (tuningPlanId plan)
                            expectedJobName
                            180
                            180
                    result <-
                      LiveWorkflow.runLiveWorkflow
                        workflow
                        (livePulsarTransport pulsarSettings)
                        backend
                    completed <- requireCompletedLiveWorkflow "live Tune workflow" result
                    let completion = LiveWorkflow.completedRunEvidence completed
                        sweep = tuningCompletedSweep completion
                    Map.size (tuningCompletedTrials completion)
                      @?= fromIntegral expectedTrials
                    fromIntegral (tuningSweepTrialsPromoted sweep)
                      @?= expectedPromotions
                    fromIntegral (tuningSweepTrialsCompleted sweep)
                      @?= expectedTrials
          , testCase
              "live daemon dispatches resolved AlphaZero plan and emits contract-complete events (Sprint 9.17)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    pulsarSettings =
                      PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
                    substrate = Publication.publicationSubstrate publication
                    commandTopic = topologyTopic RlCommandRoute substrate
                    eventTopic = topologyTopic RlEventRoute substrate
                uniqueSuffix <- pickRandomSuffix
                let experimentHash =
                      Text.take 16 ("liveaz" <> uniqueSuffix <> "abcdef0123456789")
                    subscription = "live-alphazero-event-sub-" <> uniqueSuffix
                    (start, plan) =
                      preparedStartAlphaZero
                        ProtoRl.StartAlphaZeroRun
                          { ProtoRl.sazSubstrate = substrate
                          , ProtoRl.sazExperimentHash = experimentHash
                          , ProtoRl.sazPlanId = ""
                          , ProtoRl.sazResolvedPlan = ""
                          , ProtoRl.sazGame = "connect4"
                          , ProtoRl.sazGenerations = 1
                          , ProtoRl.sazSelfPlayGames = 1
                          , ProtoRl.sazMctsSimulationsPerMove = 1
                          , ProtoRl.sazMaxPlies = 2
                          , ProtoRl.sazOptimizerUpdates = 1
                          , ProtoRl.sazArenaGames = 1
                          , ProtoRl.sazSeed = 23
                          }
                    command = ProtoRl.RlStartAlphaZero start
                    expectedJobName = "jitml-alphazero-" <> experimentHash
                case substrate of
                  AppleSilicon -> do
                    assertAppleHostForwardingSmoke
                      pulsarSettings
                      (topologyTopic RlHostCommandRoute AppleSilicon)
                      ("live-alphazero-host-command-sub-" <> uniqueSuffix)
                      experimentHash
                      command
                      (publishOrFail pulsarSettings commandTopic command "StartAlphaZeroRun")
                      20
                    assertJobDoesNotAppear expectedJobName 5
                  _ -> do
                    let contract = alphaZeroCompletionContract plan
                        eventSubscription =
                          subscriptionFixture eventTopic subscription FromLatest Owned
                        workflow =
                          LiveWorkflow.LiveWorkflow
                            { LiveWorkflow.liveWorkflowPlanId = alphaZeroPlanId plan
                            , LiveWorkflow.liveWorkflowCommand =
                                LiveWorkflow.ProtocolCommand commandTopic command
                            , LiveWorkflow.liveWorkflowEventSubscription = eventSubscription
                            , LiveWorkflow.liveWorkflowInitialProgress = initialProgress contract
                            , LiveWorkflow.liveWorkflowIngest = ingestAlphaZeroEvent plan
                            , LiveWorkflow.liveWorkflowFinish = finishContract contract
                            , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
                            }
                        backend =
                          clusterJobBackend
                            (alphaZeroPlanId plan)
                            expectedJobName
                            180
                            180
                    result <-
                      LiveWorkflow.runLiveWorkflow
                        workflow
                        (livePulsarTransport pulsarSettings)
                        backend
                    _ <- requireCompletedLiveWorkflow "live AlphaZero workflow" result
                    pure ()
          , testCase
              "live SelfPlayBuffer MinIO round-trip via writeSelfPlayBuffer / readSelfPlayBuffer (Sprint 13.9)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                uniqueSuffix <- pickRandomSuffix
                let experimentHash = "live-selfplay-" <> uniqueSuffix
                    -- Use a tiny self-play config so the buffer write
                    -- finishes in milliseconds on the live cluster.
                    config =
                      SelfPlay.defaultSelfPlayConfig
                        { SelfPlay.selfPlayGamesPerGeneration = 2
                        , SelfPlay.selfPlaySimulationsPerMove = 4
                        , SelfPlay.selfPlayMaxPlies = 6
                        , SelfPlay.selfPlaySeed = 17
                        , SelfPlay.selfPlayActionSpace = 7
                        }
                    buffer = SelfPlay.runSelfPlay config
                    contentHash = SelfPlay.bufferTranscriptHash buffer
                    bufferRef =
                      ObjectRef
                        (BucketName "jitml-checkpoints")
                        (ObjectKey ("jitml-checkpoints/" <> experimentHash <> "/selfplay/" <> contentHash <> ".cbor"))
                withTemporaryMinioObjects
                  settings
                  "live SelfPlay buffer fixture"
                  [bufferRef]
                  ( MinIOSubprocess.runMinIOSubprocess settings $ do
                      writeResult <- SelfPlay.writeSelfPlayBuffer experimentHash buffer
                      liftIO $ case writeResult of
                        Right _ -> pure ()
                        Left err ->
                          assertFailure
                            ("writeSelfPlayBuffer failed live: " <> show err)
                      readResult <- SelfPlay.readSelfPlayBuffer experimentHash contentHash
                      liftIO $ case readResult of
                        Right roundTripped -> roundTripped @?= buffer
                        Left err ->
                          assertFailure
                            ("readSelfPlayBuffer failed live: " <> Text.unpack err)
                  )
          , testCase
              "live AlphaZero generation drive: self-play + training, then .jmw1 weight checkpoint round-trips through live MinIO (Sprint 13.9)"
              $ do
                publication <- requireLivePublication
                let edgePort = Publication.publicationEdgePort publication
                    settings = MinIOSubprocess.minioSettingsForLocalEdge edgePort
                uniqueSuffix <- pickRandomSuffix
                -- Run one real generation: self-play sample generation +
                -- gradient training + an arena evaluation against the uniform
                -- opponent. Small knobs keep it to a few seconds on the live
                -- cluster while exercising the production generation loop.
                let net0 = PVN.initPolicyValueNet 43 7 16 29
                    adam0 = PVN.initAdamFor net0
                    generation = PVN.runOneGenerationOfSelfPlay net0 adam0 2 6 4 4 4 31
                    trainedFlat = PVN.policyValueNetToFlat (PVN.genNet generation)
                    experimentHash = "live-azgen-" <> uniqueSuffix
                    objectKey = Checkpoint.blobKey experimentHash "azgen-weights"
                    weightRef = CheckpointStore.checkpointObjectRef objectKey
                    blob = ByteString.Lazy.toStrict (Checkpoint.encodeJmw1 trainedFlat)
                assertBool
                  "generation produced self-play training samples"
                  (PVN.genSamplesCount generation > 0)
                assertBool
                  "arena win rate is a probability in [0, 1]"
                  ( PVN.genArenaWinRate generation >= 0.0
                      && PVN.genArenaWinRate generation <= 1.0
                  )
                withTemporaryMinioObjects
                  settings
                  "live AlphaZero generation checkpoint"
                  [weightRef]
                  ( MinIOSubprocess.runMinIOSubprocess settings $ do
                      writeResult <- putBlobBytesIfAbsent weightRef blob
                      requireTemporaryObjectWrite weightRef writeResult
                      readResult <- minioReadBytes weightRef
                      liftIO $ case readResult of
                        Left err ->
                          assertFailure
                            ("live AlphaZero weight checkpoint read failed: " <> show err)
                        Right bytes ->
                          case Checkpoint.decodeJmw1 (ByteString.Lazy.fromStrict bytes) of
                            Left err ->
                              assertFailure
                                ("decode .jmw1 from live MinIO failed: " <> Text.unpack err)
                            Right reloadedFlat -> do
                              -- The trained weights survive the live MinIO
                              -- round-trip bit-for-bit and reload into the network.
                              reloadedFlat @?= trainedFlat
                              case PVN.loadPolicyValueNetWeights net0 reloadedFlat of
                                Left err ->
                                  assertFailure
                                    ("loadPolicyValueNetWeights failed: " <> Text.unpack err)
                                Right loaded ->
                                  PVN.policyValueNetToFlat loaded @?= trainedFlat
                  )
          ]
      ]

-- | Sprint 12.11's matrix is public-CLI execution coverage.  Each cell is a
-- typed executable command whose successful process outcome and documented
-- stdout are the contract; it is deliberately not given a fabricated broker
-- subscription or workload terminal witness.  Protocol completion is covered
-- by the dedicated daemon-dispatch scenarios below through 'runLiveWorkflow'.
runTypedExecutableWorkflowMatrixCell
  :: FilePath
  -> FilePath
  -> Publication.ClusterPublication
  -> WorkflowMatrix.WorkflowCell
  -> IO ()
runTypedExecutableWorkflowMatrixCell repoRoot binary publication cell =
  case WorkflowMatrix.cellWorkflow cell of
    WorkflowMatrix.SlTrain -> do
      assertWorkflowMatrixDatasetVerified minioSettings
      runWorkflowCommandExpecting ["train:", "substrate=" <> substrateUrlSegment substrate]
    WorkflowMatrix.SlEval ->
      withWorkflowMatrixCheckpoint
        minioSettings
        "workflow-matrix-eval"
        runWorkflowCommandExpectingAdmissionFailure
    WorkflowMatrix.RlTrain ->
      runWorkflowCommandExpecting ["rl train:", "avg-reward:", "rl-replay-artifact-key:"]
    WorkflowMatrix.RlEval ->
      withWorkflowMatrixCheckpoint
        minioSettings
        "workflow-matrix-eval"
        runWorkflowCommandExpectingAdmissionFailure
    WorkflowMatrix.RlRollout ->
      runWorkflowCommandExpecting ["rl rollout:", "rewards=", "rl-rollout-artifact-key:"]
    WorkflowMatrix.Tune ->
      runWorkflowCommandExpecting
        [ "sampler: TPE"
        , "objectives:"
        , "trial-checkpoint-manifest-sha:"
        , "tune-trials-artifact-key:"
        ]
    WorkflowMatrix.Inference ->
      withWorkflowMatrixCheckpoint
        minioSettings
        "workflow-matrix-inference"
        runWorkflowCommandExpectingAdmissionFailure
    WorkflowMatrix.AlphaZeroSelfPlay ->
      runWorkflowCommandExpecting
        [ "rl alphazero self-play:"
        , "samples:"
        , "arena-win-rate:"
        , "checkpoint-manifest-sha:"
        , "alphazero-transcript-artifact-key:"
        ]
 where
  substrate = Publication.publicationSubstrate publication
  minioSettings =
    MinIOSubprocess.minioSettingsForLocalEdge (Publication.publicationEdgePort publication)
  runWorkflowCommandExpecting snippets = do
    let command =
          (subprocess binary (WorkflowMatrix.cellCommand cell))
            { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
            }
        executableCommand = LiveWorkflow.ExecutableCommand command
        canonicalCommand = LiveWorkflow.liveCommandCanonicalText executableCommand
    outcome <- runStreaming defaultSubprocessEnv command
    assertProcessExitCode
      ("WorkflowMatrix cell " <> Text.unpack canonicalCommand)
      ExitSuccess
      outcome
    traverse_
      ( \snippet ->
          assertProcessStreamContains
            ("WorkflowMatrix cell " <> Text.unpack canonicalCommand)
            ProcessStdout
            snippet
            outcome
      )
      snippets
  runWorkflowCommandExpectingAdmissionFailure = do
    let command =
          (subprocess binary (WorkflowMatrix.cellCommand cell))
            { JitML.Sub.Subprocess.subprocessWorkingDirectory = Just repoRoot
            }
    outcome <- runStreaming defaultSubprocessEnv command
    assertProcessNotSuccessful
      "WorkflowMatrix candidate checkpoint is not inference-admitted"
      outcome

withWorkflowMatrixCheckpoint
  :: MinIOSubprocess.MinIOSettings
  -> Text
  -> IO value
  -> IO value
withWorkflowMatrixCheckpoint settings experimentHash action = do
  let payload = Checkpoint.encodeJmw1 [1.0, 2.0, 3.0, 4.0]
      blobObjectKey =
        Checkpoint.blobKey
          experimentHash
          (WeightCodec.jmw1ContentSha payload)
      manifest =
        ( Checkpoint.emptyManifest
            "workflow-matrix"
            experimentHash
            [Checkpoint.TensorBlob "dense.weight" [2, 2] blobObjectKey]
        )
          { Checkpoint.manifestStep = 1
          , Checkpoint.manifestMetrics = [("validation_accuracy", 0.9)]
          }
      manifestSha = Checkpoint.manifestContentSha manifest
      blobRef = CheckpointStore.checkpointObjectRef blobObjectKey
      manifestRef =
        CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experimentHash manifestSha)
      ownedObjects = [manifestRef, blobRef]
      ownerLabel = "WorkflowMatrix checkpoint " <> experimentHash
  withTemporaryMinioObjects settings ownerLabel ownedObjects $ do
    staleCleanupIssues <- cleanupMinioObjects settings ownerLabel ownedObjects
    case staleCleanupIssues of
      [] -> pure ()
      issues ->
        Control.Exception.throwIO
          OwnedScenarioCleanupFailure
            { ownedScenarioLabel = ownerLabel
            , ownedScenarioPrimary = Nothing
            , ownedScenarioCleanupIssues = issues
            }
    MinIOSubprocess.runMinIOSubprocess settings $ do
      written <-
        CheckpointStore.writeCandidateCheckpointSnapshotWithMinIO
          manifest
          [(blobObjectKey, payload)]
      liftIO $ case written of
        Right _ -> pure ()
        Left err ->
          assertFailure
            ( "WorkflowMatrix checkpoint staging failed for "
                <> Text.unpack experimentHash
                <> ": "
                <> show err
            )
    action

assertWorkflowMatrixDatasetVerified :: MinIOSubprocess.MinIOSettings -> IO ()
assertWorkflowMatrixDatasetVerified settings =
  MinIOSubprocess.runMinIOSubprocess settings $ do
    results <-
      traverse
        (uncurry Dataset.fetchVerifiedDatasetArtifactBytes)
        [ (trainRef, Dataset.ImagesArtifact)
        , (trainRef, Dataset.LabelsArtifact)
        , (testRef, Dataset.ImagesArtifact)
        , (testRef, Dataset.LabelsArtifact)
        ]
    liftIO $
      case lefts results of
        [] -> pure ()
        err : _ ->
          assertFailure
            ( "WorkflowMatrix SL training requires real canonical MNIST bytes staged through "
                <> "`jitml internal upload-dataset`; synthetic canonical-key payloads are forbidden. Got: "
                <> show err
            )
 where
  trainRef = Dataset.DatasetRef "MNIST" Dataset.TrainSplit 0 "ignored"
  testRef = trainRef {Dataset.datasetSplit = Dataset.TestSplit}

-- | Read the live cluster publication artifact written by
-- `JitML.Bootstrap.liveExecutePhasedRollout`. Used by Sprint 13.2's `Live`
-- tests so each capability-class assertion targets the actually-leased edge
-- port and the actually-bootstrapped substrate. Fails the test with a clear
-- message when the file is missing — `-p Live` is an explicit opt-in and
-- silently passing without a cluster up would defeat the validation.
requireLivePublication :: IO Publication.ClusterPublication
requireLivePublication = do
  let path = ".build/runtime/cluster-publication.json"
  exists <- doesFileExist path
  if not exists
    then
      assertFailureWithIO
        ( "cluster-publication.json not found at "
            <> path
            <> "; bring the cluster up via `jitml bootstrap --<substrate>` "
            <> "before running `-p Live` tests"
        )
    else do
      bytes <- ByteString.Lazy.readFile path
      case eitherDecode bytes of
        Left err -> assertFailureWithIO ("failed to decode cluster-publication.json: " <> err)
        Right publication ->
          case validateLivePublication publication of
            Left err -> assertFailureWithIO err
            Right livePublication -> pure livePublication

-- | Fail closed after JSON decoding: a syntactically valid publication is not
-- sufficient authority to run the live integration suite. The bootstrap must
-- have published its marker together with exactly one ready row for every
-- required component.
validateLivePublication
  :: Publication.ClusterPublication
  -> Either String Publication.ClusterPublication
validateLivePublication publication
  | Publication.publicationHasLiveEvidence publication = Right publication
  | otherwise =
      Left
        ( "cluster-publication.json does not contain complete live-readiness evidence; "
            <> "bring the cluster up via `jitml bootstrap --<substrate>` before running `-p Live` tests"
        )

-- | Per-run unique suffix so a re-run on the same cluster does not collide
-- with a still-present object/subscription from a prior run.
pickRandomSuffix :: IO Text
pickRandomSuffix = do
  micros <- round . (* 1_000_000) <$> getPOSIXTime :: IO Integer
  unique <- hashUnique <$> newUnique
  pure (Text.pack (show micros <> "-" <> show unique))

runVisibleCheckpointInference
  :: Env -> Checkpoint.CheckpointManifest -> [Double] -> IO (Either Text [Double])
runVisibleCheckpointInference env manifest values = do
  metalProbe <- MetalRuntime.probeMetalRuntime
  if MetalRuntime.metalRuntimeDeviceVisible metalProbe
    then MetalLocal.runMetalCheckpointInference env manifest values
    else Local.runLinuxCpuCheckpointInference env manifest values

runVisibleWeightedCheckpointInference
  :: Env
  -> Checkpoint.CheckpointManifest
  -> [CheckpointStore.LoadedWeightTensor]
  -> [Double]
  -> IO (Either Text [Double])
runVisibleWeightedCheckpointInference env manifest weights values = do
  metalProbe <- MetalRuntime.probeMetalRuntime
  if MetalRuntime.metalRuntimeDeviceVisible metalProbe
    then MetalLocal.runMetalWeightedCheckpointInference env manifest weights values
    else Local.runLinuxCpuWeightedCheckpointInference env manifest weights values

layerGraphCheckpointFixture :: Either Text LayerGraph.LayerGraph
layerGraphCheckpointFixture = do
  node <-
    LayerGraph.mkAffineLayer
      "graph-dense"
      LayerGraph.DenseLayer
      3
      2
      LayerGraph.LinearActivation
      LayerGraph.InferenceMode
      LayerGraph.LayerParameters
        { LayerGraph.layerWeights = VU.fromList [1.0, 0.0, 0.0, 0.0, 1.0, 0.0]
        , LayerGraph.layerBias = VU.fromList [0.5, -0.5]
        }
  pure
    LayerGraph.LayerGraph
      { LayerGraph.layerGraphName = "graph-checkpoint-fixture"
      , LayerGraph.layerGraphInputShape = LayerGraph.TensorShape [3]
      , LayerGraph.layerGraphOutputShape = LayerGraph.TensorShape [2]
      , LayerGraph.layerGraphNodes = [node]
      }

supervisedCompletedManifestFor :: Text -> SL.CanonicalProblem -> Checkpoint.CheckpointManifest
supervisedCompletedManifestFor experimentHash problem =
  let config = supervisedManifestConfig problem
      spec = SLArchitecture.architectureSpecForProblem config problem
      graph = SLArchitecture.archLayerGraph spec
      graphMetadata = Checkpoint.layerGraphMetadataFromGraph graph
      tensors = supervisedLayerGraphTensors experimentHash graph
      manifest =
        completedCheckpointManifestWithBudget
          TrainingBudget.SupervisedEpochBudget
          ("m-" <> SL.problemName problem)
          experimentHash
          tensors
          5
          [("test_accuracy", 0.95)]
   in manifest
        { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
        , Checkpoint.manifestArchitecture =
            Checkpoint.ArchitectureMetadata
              { Checkpoint.architectureName = SL.problemName problem
              , Checkpoint.architectureModelFamily = Checkpoint.SupervisedModelFamily
              , Checkpoint.architectureInputs =
                  [Checkpoint.TensorSpec "input" [clfInputs config] "F64"]
              , Checkpoint.architectureOutputs =
                  [ Checkpoint.TensorSpec
                      "output"
                      (LayerGraph.unTensorShape (LayerGraph.layerGraphOutputShape graph))
                      "F64"
                  ]
              , Checkpoint.architectureLayerGraph = Just graphMetadata
              }
        , Checkpoint.manifestOutputDecoders = [supervisedOutputDecoder problem config]
        , Checkpoint.manifestWeightLayout =
            Checkpoint.NamedTensorWeightLayout (fmap Checkpoint.tensorSpecFromBlob tensors)
        }

supervisedManifestConfig :: SL.CanonicalProblem -> ClassifierConfig
supervisedManifestConfig problem =
  case SL.problemDataset problem of
    "MNIST" ->
      defaultClassifierConfig {clfInputs = 784, clfHidden = 128, clfClasses = 10}
    "Fashion-MNIST" ->
      defaultClassifierConfig {clfInputs = 784, clfHidden = 128, clfClasses = 10}
    "CIFAR-10" ->
      defaultClassifierConfig {clfInputs = 3072, clfHidden = 192, clfClasses = 10}
    "CIFAR-100" ->
      defaultClassifierConfig {clfInputs = 3072, clfHidden = 256, clfClasses = 100}
    "Tiny ImageNet" ->
      defaultClassifierConfig {clfInputs = 12288, clfHidden = 384, clfClasses = 200}
    "California Housing" ->
      defaultClassifierConfig {clfInputs = 8, clfHidden = 24, clfClasses = 0}
    _ ->
      defaultClassifierConfig

supervisedOutputDecoder :: SL.CanonicalProblem -> ClassifierConfig -> Checkpoint.OutputDecoder
supervisedOutputDecoder problem config =
  if SL.problemDataset problem == "California Housing"
    then
      Checkpoint.OutputDecoder
        { Checkpoint.outputDecoderName = "prediction"
        , Checkpoint.outputDecoderKind = Checkpoint.RegressionOutput
        , Checkpoint.outputDecoderLabels = []
        , Checkpoint.outputDecoderUnits = Just "median-house-value"
        , Checkpoint.outputDecoderArtifactKind = Nothing
        }
    else
      Checkpoint.OutputDecoder
        { Checkpoint.outputDecoderName = "prediction"
        , Checkpoint.outputDecoderKind = Checkpoint.ClassificationOutput
        , Checkpoint.outputDecoderLabels =
            fmap (("class-" <>) . Text.pack . show) [0 .. clfClasses config - 1]
        , Checkpoint.outputDecoderUnits = Nothing
        , Checkpoint.outputDecoderArtifactKind = Nothing
        }

supervisedLayerGraphTensors :: Text -> LayerGraph.LayerGraph -> [Checkpoint.TensorBlob]
supervisedLayerGraphTensors experimentHash graph =
  concatMap nodeTensors (LayerGraph.layerGraphNodes graph)
 where
  nodeTensors node =
    case LayerGraph.layerParameters node of
      Nothing -> []
      Just _ ->
        let inputWidth = product (LayerGraph.unTensorShape (LayerGraph.layerInputShape node))
            outputWidth = product (LayerGraph.unTensorShape (LayerGraph.layerOutputShape node))
            weightName = LayerGraph.layerNodeName node <> ".weights"
            biasName = LayerGraph.layerNodeName node <> ".bias"
         in [ Checkpoint.TensorBlob
                weightName
                [outputWidth, inputWidth]
                (Checkpoint.blobKey experimentHash ("sha-" <> weightName))
            , Checkpoint.TensorBlob
                biasName
                [outputWidth]
                (Checkpoint.blobKey experimentHash ("sha-" <> biasName))
            ]

supervisedIllegalManifestCases
  :: SL.CanonicalProblem -> [(Text, Text, Checkpoint.CheckpointManifest, Text)]
supervisedIllegalManifestCases problem =
  [ mkCase
      "partial"
      ( \manifest ->
          manifest
            { Checkpoint.manifestCompletedTraining = Nothing
            , Checkpoint.manifestInitialWeightHash = Nothing
            , Checkpoint.manifestFinalWeightHash = Nothing
            , Checkpoint.manifestUpdateCount = Nothing
            , Checkpoint.manifestDatasetShaAtRead = Nothing
            }
      )
      supervisedV1AdmissionDiagnostic
  , mkCase
      "synthetic"
      ( \manifest ->
          manifest
            { Checkpoint.manifestInitialWeightHash = Nothing
            , Checkpoint.manifestFinalWeightHash = Nothing
            , Checkpoint.manifestUpdateCount = Nothing
            , Checkpoint.manifestDatasetShaAtRead = Nothing
            }
      )
      supervisedV1AdmissionDiagnostic
  , mkCase
      "untrained"
      (\manifest -> manifest {Checkpoint.manifestStep = 0})
      supervisedV1AdmissionDiagnostic
  , mkCase
      "malformed-layout"
      ( \manifest ->
          manifest
            { Checkpoint.manifestWeightLayout = Checkpoint.NamedTensorWeightLayout []
            }
      )
      supervisedV1AdmissionDiagnostic
  ]
 where
  mkCase suffix mutate expected =
    let experimentHash = "exp-24-3-" <> SL.problemName problem <> "-" <> suffix
     in ( suffix
        , experimentHash
        , mutate (supervisedCompletedManifestFor experimentHash problem)
        , expected
        )

supervisedV1AdmissionDiagnostic :: Text
supervisedV1AdmissionDiagnostic =
  CheckpointStore.renderCheckpointAdmissionError
    ( CheckpointStore.AdmissionCompletionInvalid
        "supervised V1 manifest has no exact V2 runtime artifact and is inspection-only"
    )

rejectSupervisedManifestCase
  :: (HasMinIO m, MonadIO m)
  => SL.CanonicalProblem
  -> (Text, Text, Checkpoint.CheckpointManifest, Text)
  -> m ()
rejectSupervisedManifestCase problem (label, experimentHash, manifest, expected) = do
  let manifestSha = Checkpoint.manifestContentSha manifest
      manifestRef =
        CheckpointStore.checkpointObjectRef (Checkpoint.manifestKey experimentHash manifestSha)
      pointerRef = CheckpointStore.checkpointObjectRef (Checkpoint.latestPointerKey experimentHash)
      manifestBytes = ByteString.Lazy.toStrict (Checkpoint.encodeManifestCbor manifest)
  _ <- putBlobBytesIfAbsent manifestRef manifestBytes
  _ <- casPointer pointerRef Nothing manifestSha
  runnerInvoked <- liftIO (newIORef False)
  result <-
    CheckpointStore.loadInferenceCheckpointWithWeights
      ( \_modelRef _manifest _weights _values -> do
          liftIO (modifyIORef' runnerInvoked (const True))
          pure (Right [])
      )
      experimentHash
      [1.0]
  invoked <- liftIO (readIORef runnerInvoked)
  liftIO $ do
    invoked @?= False
    case result of
      Left err ->
        assertBool
          (Text.unpack (SL.problemName problem <> " " <> label))
          (expected `Text.isInfixOf` err)
      Right values ->
        assertFailure
          ( "illegal supervised manifest inferred for "
              <> Text.unpack (SL.problemName problem)
              <> " "
              <> Text.unpack label
              <> ": "
              <> show values
          )

data JobFailureObservation = JobFailureObservation
  { failedJobName :: Text
  , failedJobStatus :: Text
  , failedJobDescribe :: Text
  , failedJobPods :: [JobPodObservation]
  }
  deriving stock (Eq, Show)

data JobPodObservation = JobPodObservation
  { observedPodName :: Text
  , observedPodDescribe :: Text
  , observedPodLogs :: Text
  }
  deriving stock (Eq, Show)

renderJobFailureObservation :: JobFailureObservation -> Text
renderJobFailureObservation observation =
  Text.unlines $
    [ "Kubernetes Job "
        <> failedJobName observation
        <> " failed before the live test completed."
    , "Job status:"
    , indentBlock (failedJobStatus observation)
    , "Job describe:"
    , indentBlock (failedJobDescribe observation)
    , "Owning pods:"
    ]
      <> podSections
 where
  podSections =
    case failedJobPods observation of
      [] -> ["  <none>"]
      pods -> concatMap renderPod pods
  renderPod pod =
    [ "  " <> observedPodName pod
    , "  Pod describe:"
    , indentBlock (observedPodDescribe pod)
    , "  Pod logs:"
    , indentBlock (observedPodLogs pod)
    ]

indentBlock :: Text -> Text
indentBlock block =
  Text.unlines (fmap ("  " <>) (Text.lines (Text.strip block)))

jobStatusIndicatesFailure :: Text -> Bool
jobStatusIndicatesFailure statusText =
  "Failed:True" `Text.isInfixOf` statusText
    || "BackoffLimitExceeded" `Text.isInfixOf` statusText
    || "DeadlineExceeded" `Text.isInfixOf` statusText

kubectl :: [Text] -> IO ProcessOutcome
kubectl args =
  runStreaming
    defaultSubprocessEnv
    ( subprocess
        "kubectl"
        (["--kubeconfig", "./.build/jitml.kubeconfig"] <> args)
    )

kubectlOutput :: ProcessOutcome -> Text
kubectlOutput = renderProcessOutcome

observeFailedJob :: Text -> IO (Maybe JobFailureObservation)
observeFailedJob jobName = do
  statusOutcome <-
    kubectl
      [ "get"
      , "job"
      , jobName
      , "-n"
      , "platform"
      , "--ignore-not-found"
      , "-o"
      , "jsonpath={range .status.conditions[*]}{.type}:{.status}:{.reason}{\"\\n\"}{end}"
      ]
  case statusOutcome of
    ProcessFailed _ -> do
      _ <-
        assertFailure
          ( "kubectl failed while observing Job status for "
              <> Text.unpack jobName
              <> ":\n"
              <> Text.unpack (renderProcessOutcome statusOutcome)
          )
      pure Nothing
    ProcessSucceeded statusTranscript ->
      if not (jobStatusIndicatesFailure (processTranscriptStdout statusTranscript))
        then pure Nothing
        else do
          describeOutcome <- kubectl ["describe", "job", jobName, "-n", "platform"]
          podOutcome <-
            kubectl
              [ "get"
              , "pods"
              , "-n"
              , "platform"
              , "-l"
              , "job-name=" <> jobName
              , "-o"
              , "name"
              ]
          let podNames =
                case podOutcome of
                  ProcessSucceeded transcript ->
                    filter
                      (not . Text.null)
                      (fmap Text.strip (Text.lines (processTranscriptStdout transcript)))
                  ProcessFailed _ -> []
          podObservations <- traverse observeJobPod podNames
          let podListing =
                if processExitCode podOutcome == ExitSuccess
                  then ""
                  else "\nPod listing failed:\n" <> kubectlOutput podOutcome
          pure
            ( Just
                JobFailureObservation
                  { failedJobName = jobName
                  , failedJobStatus = kubectlOutput statusOutcome
                  , failedJobDescribe = kubectlOutput describeOutcome <> podListing
                  , failedJobPods = podObservations
                  }
            )

observeJobPod :: Text -> IO JobPodObservation
observeJobPod podName = do
  describeOutcome <- kubectl ["describe", podName, "-n", "platform"]
  logsOutcome <-
    kubectl
      [ "logs"
      , podName
      , "-n"
      , "platform"
      , "--all-containers=true"
      , "--tail=200"
      ]
  pure
    JobPodObservation
      { observedPodName = podName
      , observedPodDescribe = kubectlOutput describeOutcome
      , observedPodLogs = kubectlOutput logsOutcome
      }

assertWatchedJobNotFailed :: Text -> IO ()
assertWatchedJobNotFailed jobName = do
  failed <- observeFailedJob jobName
  case failed of
    Nothing -> pure ()
    Just observation ->
      assertFailure (Text.unpack (renderJobFailureObservation observation))

-- | Poll `kubectl get job <name> -n platform` until the resource exists or
-- the deadline passes. Used by the Sprint 13.3 daemon-dispatch live test.
waitForJob :: Text -> Int -> IO Bool
waitForJob jobName remaining
  | remaining <= 0 = pure False
  | otherwise = do
      exists <- kubectlJobExists jobName
      if exists
        then do
          assertWatchedJobNotFailed jobName
          pure True
        else do
          assertWatchedJobNotFailed jobName
          Control.Concurrent.threadDelay 1_000_000
          waitForJob jobName (remaining - 1)

assertJobDoesNotAppear :: Text -> Int -> IO ()
assertJobDoesNotAppear jobName remaining
  | remaining <= 0 = pure ()
  | otherwise = do
      exists <- kubectlJobExists jobName
      if exists
        then do
          failed <- observeFailedJob jobName
          case failed of
            Just observation ->
              assertFailure
                ( Text.unpack
                    ( "unexpected Apple host-resident workload Job appeared:\n"
                        <> renderJobFailureObservation observation
                    )
                )
            Nothing -> do
              describeOutcome <- kubectl ["describe", "job", jobName, "-n", "platform"]
              assertFailure
                ( Text.unpack
                    ( Text.unlines
                        [ "unexpected Apple host-resident workload Job appeared: " <> jobName
                        , kubectlOutput describeOutcome
                        ]
                    )
                )
        else do
          Control.Concurrent.threadDelay 1_000_000
          assertJobDoesNotAppear jobName (remaining - 1)

publishOrFail
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Topic event
  -> event
  -> Text
  -> IO ()
publishOrFail settings topic event label = do
  result <-
    PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
      settings
      (pulsarPublish topic event)
  case result of
    Right _ -> pure ()
    Left err ->
      assertFailure
        ( Text.unpack
            (label <> " publish failed live on " <> topicName topic <> ": " <> Text.pack (show err))
        )

cleanupMinioObjects
  :: MinIOSubprocess.MinIOSettings
  -> Text
  -> [ObjectRef]
  -> IO [LiveWorkflow.CleanupIssue]
cleanupMinioObjects settings ownerLabel refs =
  concat <$> traverse cleanupOne refs
 where
  cleanupOne ref = do
    attempted <-
      Control.Exception.try
        ( MinIOSubprocess.runMinIOSubprocess
            settings
            (deleteObject ref)
        )
        :: IO
             ( Either
                 Control.Exception.SomeException
                 (Either ServiceError ())
             )
    case attempted of
      Left exception ->
        case Control.Exception.fromException exception of
          Just asyncException ->
            Control.Exception.throwIO
              (asyncException :: Control.Exception.SomeAsyncException)
          Nothing ->
            pure
              [ LiveWorkflow.CleanupIssue
                  ( ownerLabel
                      <> " failed to delete temporary object "
                      <> renderObjectRef ref
                      <> ": "
                      <> Text.pack (show exception)
                  )
              ]
      Right (Left failure) ->
        pure
          [ LiveWorkflow.CleanupIssue
              ( ownerLabel
                  <> " failed to delete temporary object "
                  <> renderObjectRef ref
                  <> ": "
                  <> Text.pack (show failure)
              )
          ]
      Right (Right ()) -> pure []

withTemporaryMinioObjects
  :: MinIOSubprocess.MinIOSettings
  -> Text
  -> [ObjectRef]
  -> IO value
  -> IO value
withTemporaryMinioObjects settings ownerLabel refs =
  withOwnedScenarioCleanup
    ownerLabel
    (cleanupMinioObjects settings ownerLabel refs)

renderObjectRef :: ObjectRef -> Text
renderObjectRef ref =
  unBucketName (objectBucket ref)
    <> "/"
    <> unObjectKey (objectKey ref)

requireTemporaryObjectWrite
  :: (MonadIO m)
  => ObjectRef
  -> Either ServiceError ETag
  -> m ()
requireTemporaryObjectWrite ref result =
  liftIO $ case result of
    Left failure ->
      assertFailure
        ( "failed to stage temporary object "
            <> Text.unpack (renderObjectRef ref)
            <> ": "
            <> show failure
        )
    Right _etag -> pure ()

livePulsarTransport
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> LiveWorkflow.LiveTransport command event
livePulsarTransport settings =
  LiveWorkflow.LiveTransport
    { LiveWorkflow.livePublishCommand = \case
        LiveWorkflow.ProtocolCommand topic event ->
          PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
            settings
            (pulsarPublish topic event)
        command@LiveWorkflow.ExecutableCommand {} ->
          pure
            ( Left
                ( SETransient
                    ( "Pulsar transport cannot execute typed command: "
                        <> LiveWorkflow.liveCommandCanonicalText command
                    )
                )
            )
    , LiveWorkflow.liveConsumeEvents = \subscription observe handle ->
        PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
          settings
          ( pulsarConsumeUntil
              subscription
              (liftIO . observe)
              (liftIO . handle)
          )
    }

liveSubprocessTransport
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> LiveWorkflow.LiveTransport Subprocess event
liveSubprocessTransport settings =
  LiveWorkflow.LiveTransport
    { LiveWorkflow.livePublishCommand = \case
        LiveWorkflow.ProtocolCommand topic command ->
          PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
            settings
            (pulsarPublish topic command)
        LiveWorkflow.ExecutableCommand command -> do
          outcome <- runStreaming defaultSubprocessEnv command
          pure $ case outcome of
            ProcessSucceeded transcript ->
              Right (processTranscriptStdout transcript)
            ProcessFailed _ ->
              Left
                ( SETransient
                    ("live subprocess failed:\n" <> renderProcessOutcome outcome)
                )
    , LiveWorkflow.liveConsumeEvents = \subscription observe handle ->
        PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
          settings
          ( pulsarConsumeUntil
              subscription
              (liftIO . observe)
              (liftIO . handle)
          )
    }

clusterJobBackend
  :: PlanId
  -> Text
  -> Int
  -> Int
  -> LiveWorkflow.LiveBackend Text
clusterJobBackend planId jobName observationAttempts timeoutSeconds =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement =
        pure
          ( Bifunctor.first
              (LiveWorkflow.ResourceFailure . Text.pack . show)
              (LiveWorkflow.ClusterJob <$> LiveWorkflow.mkJobHandle planId jobName)
          )
    , LiveWorkflow.liveCompletionMode =
        LiveWorkflow.ObserveIndependentWorkload
    , LiveWorkflow.liveObserveWorkload = observeLivePlacement
    , LiveWorkflow.liveGatherDiagnostics = gatherLivePlacementDiagnostics
    , LiveWorkflow.liveReleasePlacement = releaseLivePlacement
    , LiveWorkflow.liveObservationAttempts = max 1 observationAttempts
    , LiveWorkflow.liveObservationDelayMicros = 1_000_000
    , LiveWorkflow.liveWorkflowTimeoutMicros = max 1 timeoutSeconds * 1_000_000
    }

executableCommandBackend
  :: PlanId
  -> Text
  -> Int
  -> LiveWorkflow.LiveBackend Text
executableCommandBackend planId runKey timeoutSeconds =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement =
        pure
          ( Bifunctor.first
              (LiveWorkflow.ResourceFailure . Text.pack . show)
              (LiveWorkflow.HostRun <$> LiveWorkflow.mkHostRunHandle planId runKey)
          )
    , LiveWorkflow.liveCompletionMode =
        LiveWorkflow.ObserveIndependentWorkload
    , LiveWorkflow.liveObserveWorkload = \placement ->
        pure
          ( LiveWorkflow.ProbeFailed
              ( LiveWorkflow.ProbeFailure
                  ( "typed executable unexpectedly requested a workload observation for "
                      <> Text.pack (show placement)
                  )
              )
          )
    , LiveWorkflow.liveGatherDiagnostics = \placement ->
        pure (Right [LiveWorkflow.LiveDiagnostic (Text.pack (show placement))])
    , LiveWorkflow.liveReleasePlacement = const (pure [])
    , LiveWorkflow.liveObservationAttempts = 1
    , LiveWorkflow.liveObservationDelayMicros = 0
    , LiveWorkflow.liveWorkflowTimeoutMicros = max 1 timeoutSeconds * 1_000_000
    }

requestReplyBackend
  :: PlanId
  -> Text
  -> Int
  -> LiveWorkflow.LiveBackend Text
requestReplyBackend planId requestKey timeoutSeconds =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement =
        pure
          ( Bifunctor.first
              (LiveWorkflow.ResourceFailure . Text.pack . show)
              ( LiveWorkflow.RequestReply
                  <$> LiveWorkflow.mkRequestHandle planId requestKey
              )
          )
    , LiveWorkflow.liveCompletionMode =
        LiveWorkflow.ResponseCompletesRequest
    , LiveWorkflow.liveObserveWorkload = \placement ->
        pure
          ( LiveWorkflow.ProbeFailed
              ( LiveWorkflow.ProbeFailure
                  ( "request/reply workflow unexpectedly requested a workload observation for "
                      <> Text.pack (show placement)
                  )
              )
          )
    , LiveWorkflow.liveGatherDiagnostics = \placement ->
        pure (Right [LiveWorkflow.LiveDiagnostic (Text.pack (show placement))])
    , LiveWorkflow.liveReleasePlacement = const (pure [])
    , LiveWorkflow.liveObservationAttempts = 1
    , LiveWorkflow.liveObservationDelayMicros = 0
    , LiveWorkflow.liveWorkflowTimeoutMicros = max 1 timeoutSeconds * 1_000_000
    }

observeLivePlacement :: LiveWorkflow.Placement -> IO (LiveWorkflow.WorkloadObservation Text)
observeLivePlacement placement =
  case placement of
    LiveWorkflow.HostRun handle ->
      pure
        ( LiveWorkflow.ProbeFailed
            ( LiveWorkflow.ProbeFailure
                ( "cluster observer received host handle "
                    <> LiveWorkflow.hostRunHandleKey handle
                )
            )
        )
    LiveWorkflow.RequestReply handle ->
      pure
        ( LiveWorkflow.ProbeFailed
            ( LiveWorkflow.ProbeFailure
                ( "cluster observer received request handle "
                    <> LiveWorkflow.requestHandleKey handle
                )
            )
        )
    LiveWorkflow.ClusterJob handle -> observeLiveJob (LiveWorkflow.jobHandleName handle)

observeLiveJob :: Text -> IO (LiveWorkflow.WorkloadObservation Text)
observeLiveJob jobName = do
  outcome <-
    kubectl
      [ "get"
      , "job"
      , jobName
      , "-n"
      , "platform"
      , "--ignore-not-found"
      , "-o"
      , Text.concat
          [ "jsonpath={.metadata.name}{\"\\n\"}"
          , "{range .status.conditions[*]}{.type}:{.status}:{.reason}{\"\\n\"}{end}"
          , "active={.status.active}{\"\\n\"}"
          , "succeeded={.status.succeeded}{\"\\n\"}"
          , "failed={.status.failed}{\"\\n\"}"
          ]
      ]
  case outcome of
    ProcessFailed _ ->
      pure
        ( LiveWorkflow.ProbeFailed
            (LiveWorkflow.ProbeFailure (renderProcessOutcome outcome))
        )
    ProcessSucceeded transcript -> do
      let status = Text.strip (processTranscriptStdout transcript)
          diagnostic = LiveWorkflow.LiveDiagnostic status
      if Text.null status
        then pure (LiveWorkflow.Missing (LiveWorkflow.LiveDiagnostic ("missing Job " <> jobName)))
        else
          if jobStatusIndicatesFailure status || statusFieldPositive "failed" status
            then
              pure
                ( LiveWorkflow.Failed
                    (LiveWorkflow.WorkloadFailure status)
                )
            else
              if "Complete:True" `Text.isInfixOf` status
                || statusFieldPositive "succeeded" status
                then pure (LiveWorkflow.Succeeded status)
                else
                  if statusFieldPositive "active" status
                    then pure (LiveWorkflow.Running diagnostic)
                    else pure (LiveWorkflow.Pending diagnostic)

statusFieldPositive :: Text -> Text -> Bool
statusFieldPositive fieldName status =
  any positiveLine (Text.lines status)
 where
  prefix = fieldName <> "="
  positiveLine line =
    case reads (Text.unpack (Text.drop (Text.length prefix) line)) of
      [(value :: Int, "")] -> prefix `Text.isPrefixOf` line && value > 0
      _ -> False

gatherLivePlacementDiagnostics
  :: LiveWorkflow.Placement
  -> IO (Either LiveWorkflow.CleanupIssue [LiveWorkflow.LiveDiagnostic])
gatherLivePlacementDiagnostics placement =
  case placement of
    LiveWorkflow.HostRun handle ->
      pure
        ( Right
            [ LiveWorkflow.LiveDiagnostic
                ("host-run-key: " <> LiveWorkflow.hostRunHandleKey handle)
            ]
        )
    LiveWorkflow.RequestReply handle ->
      pure
        ( Right
            [ LiveWorkflow.LiveDiagnostic
                ("request-key: " <> LiveWorkflow.requestHandleKey handle)
            ]
        )
    LiveWorkflow.ClusterJob handle -> do
      let jobName = LiveWorkflow.jobHandleName handle
      describeOutcome <- kubectl ["describe", "job", jobName, "-n", "platform"]
      podOutcome <-
        kubectl
          [ "get"
          , "pods"
          , "-n"
          , "platform"
          , "-l"
          , "job-name=" <> jobName
          , "-o"
          , "name"
          ]
      let podNames =
            case podOutcome of
              ProcessSucceeded transcript ->
                filter
                  (not . Text.null)
                  (fmap Text.strip (Text.lines (processTranscriptStdout transcript)))
              ProcessFailed _ -> []
      pods <- traverse observeJobPod podNames
      pure
        ( Right
            ( LiveWorkflow.LiveDiagnostic (renderProcessOutcome describeOutcome)
                : LiveWorkflow.LiveDiagnostic (renderProcessOutcome podOutcome)
                : fmap
                  (LiveWorkflow.LiveDiagnostic . renderJobPodDiagnostic)
                  pods
            )
        )

renderJobPodDiagnostic :: JobPodObservation -> Text
renderJobPodDiagnostic pod =
  Text.unlines
    [ observedPodName pod
    , observedPodDescribe pod
    , observedPodLogs pod
    ]

releaseLivePlacement
  :: LiveWorkflow.Placement
  -> IO [LiveWorkflow.CleanupIssue]
releaseLivePlacement placement =
  case placement of
    LiveWorkflow.HostRun _ -> pure []
    LiveWorkflow.RequestReply _ -> pure []
    LiveWorkflow.ClusterJob handle -> do
      let jobName = LiveWorkflow.jobHandleName handle
      cleanupTemporaryKubernetesJob "live workflow placement" jobName

assertSubscribeBeforePublish
  :: (Show terminal, Show violation, Show missing)
  => LiveWorkflow.CompletedRunEvidence terminal evidence violation missing
  -> Assertion
assertSubscribeBeforePublish completed = do
  let entries = LiveWorkflow.completedRunJournal completed
      subscriptionSequences =
        [ LiveWorkflow.liveJournalSequence entry
        | entry <- entries
        , LiveWorkflow.SubscriptionReady _ _ <- [LiveWorkflow.liveJournalEvent entry]
        ]
      publicationSequences =
        [ LiveWorkflow.liveJournalSequence entry
        | entry <- entries
        , LiveWorkflow.CommandPublished {} <- [LiveWorkflow.liveJournalEvent entry]
        ]
  case (subscriptionSequences, publicationSequences) of
    (subscriptionSequence : _, publicationSequence : _) ->
      assertBool
        "live workflow subscription must become ready before command publication"
        (subscriptionSequence < publicationSequence)
    _ ->
      assertFailure
        ("live workflow journal lacks subscribe/publish evidence: " <> show entries)

requireCompletedLiveWorkflow
  :: (Show terminal, Show evidence, Show violation, Show missing)
  => Text
  -> Either
       (LiveWorkflow.LiveRunFailure terminal evidence violation missing)
       (LiveWorkflow.CompletedRunEvidence terminal evidence violation missing)
  -> IO (LiveWorkflow.CompletedRunEvidence terminal evidence violation missing)
requireCompletedLiveWorkflow label result =
  case result of
    Left failure ->
      assertFailureWithIO
        (Text.unpack label <> " failed:\n" <> show failure)
    Right completed -> do
      assertSubscribeBeforePublish completed
      pure completed

-- | Apple placement smoke only: prove the Coordinator forwarded the exact
-- decoded typed command to the host route.  This helper intentionally does not
-- claim host workload completion; evidence-bearing Apple workflows must use a
-- terminal/event scenario on an Apple runner.
assertAppleHostForwardingSmoke
  :: (Eq command)
  => PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Topic command
  -> Text
  -> Text
  -> command
  -> IO ()
  -> Int
  -> IO ()
assertAppleHostForwardingSmoke settings topic subscriptionName experimentHash expectedCommand startAction attempts = do
  startedRef <- newIORef False
  let subscription = subscriptionFixture topic subscriptionName FromLatest Owned
  consumed <-
    Timeout.timeout (max 1 attempts * 5_000_000) $
      PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $
        pulsarConsumeUntil
          subscription
          ( \case
              ConsumerSessionConnected _ -> do
                started <- liftIO (readIORef startedRef)
                if started
                  then pure ()
                  else do
                    liftIO (writeIORef startedRef True)
                    liftIO startAction
              _ -> pure ()
          )
          ( \delivery -> do
              if deliveryEvent delivery == expectedCommand
                then pure (done ack ())
                else pure (continue ack)
          )
  case consumed of
    Nothing ->
      assertFailure
        ( "timed out waiting for host workload command for "
            <> Text.unpack experimentHash
            <> " on "
            <> Text.unpack (topicName topic)
        )
    Just (Left err) ->
      assertFailure
        ( "host workload consumer failed on "
            <> Text.unpack (topicName topic)
            <> ": "
            <> show err
        )
    Just (Right ()) -> pure ()

nonFinite :: Double -> Bool
nonFinite value = isNaN value || isInfinite value

kubectlJobExists :: Text -> IO Bool
kubectlJobExists jobName = do
  let command =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "get"
          , "job"
          , jobName
          , "-n"
          , "platform"
          , "--ignore-not-found"
          , "-o"
          , "name"
          ]
  outcome <- runStreaming defaultSubprocessEnv command
  case outcome of
    ProcessSucceeded transcript ->
      pure (not (Text.null (Text.strip (processTranscriptStdout transcript))))
    ProcessFailed _ -> do
      _ <-
        assertFailure
          ( "kubectl failed while checking whether Job exists: "
              <> Text.unpack jobName
              <> "\n"
              <> Text.unpack (renderProcessOutcome outcome)
          )
      pure False

-- | Drain the HA-wide command-role daemon logs. Training/Tune/RL deduplication
-- is Coordinator-owned after the role split, while inference remains
-- Engine-owned. Workload Jobs also carry @jitml.role: engine@, so the role
-- selector alone can make @kubectl logs@ fail on a newly created workload pod.
-- Intersect it with the two daemon Deployment app labels: the selector still
-- covers every Engine replica plus the Coordinator, and any genuine log error
-- from one of those daemon pods remains a failing subprocess outcome.
daemonLogStream :: Maybe Text -> IO ProcessOutcome
daemonLogStream =
  runStreaming defaultSubprocessEnv . daemonLogSubprocess

daemonLogSubprocess :: Maybe Text -> Subprocess
daemonLogSubprocess sinceArg =
  let baseArgs =
        [ "--kubeconfig"
        , "./.build/jitml.kubeconfig"
        , "logs"
        , "-n"
        , "platform"
        , "-l"
        , "app in (jitml-service,jitml-coordinator),jitml.role in (engine,coordinator)"
        , "--tail=-1"
        , "--max-log-requests=10"
        ]
      args = baseArgs <> maybe [] (\s -> ["--since=" <> s]) sinceArg
   in subprocess "kubectl" args

withTemporaryKubernetesJobs
  :: Text
  -> [Text]
  -> IO value
  -> IO value
withTemporaryKubernetesJobs ownerLabel jobNames =
  withOwnedScenarioCleanup
    ownerLabel
    (concat <$> traverse (cleanupTemporaryKubernetesJob ownerLabel) jobNames)

cleanupTemporaryKubernetesJob
  :: Text
  -> Text
  -> IO [LiveWorkflow.CleanupIssue]
cleanupTemporaryKubernetesJob ownerLabel jobName =
  concat
    <$> traverse
      cleanupResource
      (zip resourceLabels (temporaryKubernetesJobCleanupCommands jobName))
 where
  resourceLabels =
    [ "temporary Job " <> jobName
    , "temporary RunConfig ConfigMap runconfig-" <> jobName
    ]
  cleanupResource (resourceLabel, command) = do
    attempted <- tryAnyIntegration (runStreaming defaultSubprocessEnv command)
    case attempted of
      Left exception ->
        case Control.Exception.fromException exception of
          Just asyncException ->
            Control.Exception.throwIO
              (asyncException :: Control.Exception.SomeAsyncException)
          Nothing ->
            pure
              [ LiveWorkflow.CleanupIssue
                  ( ownerLabel
                      <> " failed to delete "
                      <> resourceLabel
                      <> ": "
                      <> Text.pack (show exception)
                  )
              ]
      Right (ProcessSucceeded _) -> pure []
      Right failed@ProcessFailed {} ->
        pure
          [ LiveWorkflow.CleanupIssue
              ( ownerLabel
                  <> " failed to delete "
                  <> resourceLabel
                  <> ":\n"
                  <> renderProcessOutcome failed
              )
          ]

temporaryKubernetesJobCleanupCommands :: Text -> [Subprocess]
temporaryKubernetesJobCleanupCommands jobName =
  fmap
    ( \(resourceType, resourceName) ->
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "delete"
          , resourceType
          , resourceName
          , "-n"
          , "platform"
          , "--ignore-not-found"
          ]
    )
    [ ("job", jobName)
    , ("configmap", "runconfig-" <> jobName)
    ]

-- | Map `Substrate` to the lower-case URL segment used in Pulsar topic
-- names (`training.command.linux-cuda`, etc).
substrateUrlSegment :: Substrate -> Text
substrateUrlSegment = \case
  AppleSilicon -> "apple-silicon"
  LinuxCPU -> "linux-cpu"
  LinuxCUDA -> "linux-cuda"

-- | `assertFailure` raises an exception inside `IO`. Wrap it so the type
-- checker accepts it where the caller expects a plain `IO a`.
assertFailureWithIO :: String -> IO a
assertFailureWithIO message = assertFailure message >> error "unreachable"

expectValidationSuccess :: (Show err) => Validation err value -> IO value
expectValidationSuccess validation =
  case validation of
    Failure err -> assertFailureWithIO ("expected successful validation, got " <> show err)
    Success value -> pure value

assertPulsarSubscriptionAbsent :: Topic event -> Text -> Int -> IO ()
assertPulsarSubscriptionAbsent topic subscriptionName =
  go
 where
  go remaining = do
    let statsCommand =
          subprocess
            "kubectl"
            [ "--kubeconfig"
            , "./.build/jitml.kubeconfig"
            , "exec"
            , "-n"
            , "platform"
            , "pulsar-toolset-0"
            , "--"
            , "/pulsar/bin/pulsar-admin"
            , "topics"
            , "stats"
            , topicName topic
            ]
    outcome <- runStreaming defaultSubprocessEnv statsCommand
    case outcome of
      ProcessSucceeded transcript ->
        case eitherDecode
          (ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
          Right (Aeson.Object objectValue)
            | Just (Aeson.Object subscriptions) <-
                AesonKeyMap.lookup "subscriptions" objectValue
            , not (AesonKeyMap.member (AesonKey.fromText subscriptionName) subscriptions) ->
                pure ()
          _
            | remaining > 0 -> do
                Control.Concurrent.threadDelay 1_000_000
                go (remaining - 1)
          parsed ->
            assertFailure
              ( "owned Pulsar subscription was not cleaned up: "
                  <> Text.unpack subscriptionName
                  <> " on "
                  <> Text.unpack (topicName topic)
                  <> "; stats parse was "
                  <> show parsed
                  <> "\n"
                  <> Text.unpack (renderProcessOutcome outcome)
              )
      ProcessFailed _
        | remaining > 0 -> do
            Control.Concurrent.threadDelay 1_000_000
            go (remaining - 1)
      ProcessFailed _ ->
        assertFailure
          ( "failed to verify owned Pulsar subscription cleanup for "
              <> Text.unpack subscriptionName
              <> ":\n"
              <> Text.unpack (renderProcessOutcome outcome)
          )

pulsarSubscriptionNamesWithPrefix :: Topic event -> Text -> IO [Text]
pulsarSubscriptionNamesWithPrefix topic prefix = do
  let statsCommand =
        subprocess
          "kubectl"
          [ "--kubeconfig"
          , "./.build/jitml.kubeconfig"
          , "exec"
          , "-n"
          , "platform"
          , "pulsar-toolset-0"
          , "--"
          , "/pulsar/bin/pulsar-admin"
          , "topics"
          , "stats"
          , topicName topic
          ]
  outcome <- runStreaming defaultSubprocessEnv statsCommand
  case outcome of
    ProcessSucceeded transcript ->
      case eitherDecode
        (ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
        Right (Aeson.Object objectValue)
          | Just (Aeson.Object subscriptions) <-
              AesonKeyMap.lookup "subscriptions" objectValue ->
              pure
                [ subscriptionName
                | subscriptionKey <- AesonKeyMap.keys subscriptions
                , let subscriptionName = AesonKey.toText subscriptionKey
                , prefix `Text.isPrefixOf` subscriptionName
                ]
        parsed ->
          assertFailureWithIO
            ( "failed to decode Pulsar subscription inventory for "
                <> Text.unpack (topicName topic)
                <> ": "
                <> show parsed
            )
    ProcessFailed _
      | pulsarTopicAbsentFromStats topic outcome -> pure []
      | otherwise ->
          assertFailureWithIO
            ( "failed to inspect Pulsar subscription inventory for "
                <> Text.unpack (topicName topic)
                <> ":\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )

-- | Pulsar may auto-delete a non-partitioned result topic after the last owned
-- reply subscription closes.  For a prefix inventory that absence is exactly
-- the empty-cursor state; every other admin failure remains fail-closed.
pulsarTopicAbsentFromStats :: Topic event -> ProcessOutcome -> Bool
pulsarTopicAbsentFromStats topic outcome =
  ("Topic " <> topicName topic <> " not found")
    `Text.isInfixOf` renderProcessOutcome outcome

-- | Require a role-owned Pulsar subscription to retain an attached consumer
-- across consecutive observations. A single empty consumer array is a valid
-- broker-side view during WebSocket reconnect, but a consumer that does not
-- recover and remain present within the bounded window fails closed with the
-- final complete @pulsar-admin@ transcript.
assertPulsarSubscriptionsStablyHaveConsumers :: [(Text, Text)] -> Int -> Int -> IO ()
assertPulsarSubscriptionsStablyHaveConsumers
  expectedSubscriptions
  requiredConsecutive
  maxSweeps
    | null expectedSubscriptions =
        assertFailure "stable Pulsar consumer assertion requires at least one subscription"
    | requiredConsecutive <= 0 =
        assertFailure "stable Pulsar consumer observations must be positive"
    | maxSweeps < requiredConsecutive =
        assertFailure "Pulsar consumer poll budget is smaller than the stable observation target"
    | otherwise = go 0 0 maxSweeps []
   where
    go bestStreak consecutive remaining history = do
      observations <- traverse probeSubscription expectedSubscriptions
      let allPresent = all subscriptionPresent observations
          nextConsecutive = if allPresent then consecutive + 1 else 0
          nextBestStreak = max bestStreak nextConsecutive
          sweepNumber = maxSweeps - remaining + 1
          nextHistory =
            take 3 (renderSubscriptionSweep sweepNumber observations : history)
      if nextConsecutive >= requiredConsecutive
        then pure ()
        else
          if remaining <= 1
            then
              assertFailure
                ( "role-owned Pulsar subscriptions did not all retain consumers for "
                    <> show requiredConsecutive
                    <> " consecutive sweeps within "
                    <> show maxSweeps
                    <> " sweeps; best streak: "
                    <> show nextBestStreak
                    <> "; final sweep history:\n"
                    <> unlines (reverse nextHistory)
                )
            else do
              Control.Concurrent.threadDelay 1_000_000
              go nextBestStreak nextConsecutive (remaining - 1) nextHistory

    probeSubscription (topic, expectedSubscription) = do
      outcome <- runStreaming defaultSubprocessEnv (statsCommand topic)
      let observation =
            case outcome of
              ProcessFailed _ ->
                Left
                  ( "pulsar-admin topics stats failed for "
                      <> Text.unpack topic
                      <> ":\n"
                      <> Text.unpack (renderProcessOutcome outcome)
                  )
              ProcessSucceeded transcript ->
                case eitherDecode
                  ( ByteString.Lazy.fromStrict
                      (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))
                  ) of
                  Left parseErr ->
                    Left
                      ( "pulsar-admin topics stats JSON parse failed for "
                          <> Text.unpack topic
                          <> ": "
                          <> parseErr
                          <> "\n"
                          <> Text.unpack (renderProcessOutcome outcome)
                      )
                  Right (statsValue :: Aeson.Value) ->
                    case subscriptionConsumerObservation
                      topic
                      expectedSubscription
                      statsValue of
                      Left details ->
                        Left
                          ( details
                              <> "\n"
                              <> Text.unpack (renderProcessOutcome outcome)
                          )
                      Right () -> Right ()
      pure (topic, expectedSubscription, observation)

    subscriptionPresent (_, _, observation) =
      case observation of
        Right () -> True
        Left _ -> False

    renderSubscriptionSweep sweepNumber observations =
      unlines
        ( ("sweep " <> show sweepNumber <> ":")
            : fmap renderSubscriptionObservation observations
        )

    renderSubscriptionObservation (topic, expectedSubscription, observation) =
      "  "
        <> Text.unpack topic
        <> " as "
        <> Text.unpack expectedSubscription
        <> ": "
        <> case observation of
          Right () -> "consumer present"
          Left details -> details

    statsCommand topic =
      subprocess
        "kubectl"
        [ "--kubeconfig"
        , "./.build/jitml.kubeconfig"
        , "exec"
        , "-n"
        , "platform"
        , "pulsar-toolset-0"
        , "--"
        , "/pulsar/bin/pulsar-admin"
        , "topics"
        , "stats"
        , topic
        ]

subscriptionConsumerObservation :: Text -> Text -> Aeson.Value -> Either String ()
subscriptionConsumerObservation topic expectedSubscription statsValue =
  case statsValue of
    Aeson.Object o ->
      case AesonKeyMap.lookup "subscriptions" o of
        Just (Aeson.Object subs) ->
          case AesonKeyMap.lookup (AesonKey.fromText expectedSubscription) subs of
            Nothing ->
              Left
                ( "topic "
                    <> Text.unpack topic
                    <> " has no "
                    <> Text.unpack expectedSubscription
                    <> " subscription"
                )
            Just (Aeson.Object subInfo) ->
              case AesonKeyMap.lookup "consumers" subInfo of
                Just (Aeson.Array consumers)
                  | not (null consumers) -> Right ()
                other ->
                  Left
                    ( Text.unpack expectedSubscription
                        <> " subscription on "
                        <> Text.unpack topic
                        <> " has no consumers; got: "
                        <> show other
                    )
            Just other ->
              Left
                ( Text.unpack expectedSubscription
                    <> " subscription entry has unexpected shape on "
                    <> Text.unpack topic
                    <> ": "
                    <> show other
                )
        other ->
          Left
            ( "topic "
                <> Text.unpack topic
                <> " stats has unexpected subscriptions field: "
                <> show other
            )
    other ->
      Left
        ( "topic "
            <> Text.unpack topic
            <> " stats decoded to non-object: "
            <> show other
        )

seedHarborOciArtifact :: HarborSubprocess.HarborSettings -> Text -> Text -> IO ()
seedHarborOciArtifact settings repository tag = do
  token <- harborRegistryToken settings repository "push,pull"
  let configPayload =
        "{\"architecture\":\"amd64\",\"os\":\"linux\",\"rootfs\":{\"type\":\"layers\",\"diff_ids\":[]},\"config\":{}}"
  configDigest <- ociDigest configPayload
  let configSize =
        Text.pack (show (Data.ByteString.length (Text.Encoding.encodeUtf8 configPayload)))
      manifestPayload =
        Text.concat
          [ "{\"schemaVersion\":2"
          , ",\"mediaType\":\"application/vnd.oci.image.manifest.v1+json\""
          , ",\"config\":{\"mediaType\":\"application/vnd.oci.image.config.v1+json\""
          , ",\"digest\":\""
          , configDigest
          , "\",\"size\":"
          , configSize
          , "}"
          , ",\"layers\":[]}"
          ]
  uploadLocation <- startHarborBlobUpload settings token repository
  putHarborBlob settings token uploadLocation configDigest configPayload
  putHarborManifest settings token repository tag manifestPayload

harborRegistryToken
  :: HarborSubprocess.HarborSettings -> Text -> Text -> IO Text
harborRegistryToken settings repository actions = do
  let tokenUrl =
        "http://"
          <> HarborSubprocess.harborRegistry settings
          <> "/service/token?service=harbor-registry&scope=repository:"
          <> repository
          <> ":"
          <> actions
  outcome <-
    runStreaming
      defaultSubprocessEnv
      ( subprocess
          (HarborSubprocess.harborCurlBinary settings)
          [ "--fail"
          , "--silent"
          , "--show-error"
          , "--user"
          , HarborSubprocess.harborUsername settings
              <> ":"
              <> HarborSubprocess.harborPassword settings
          , tokenUrl
          ]
      )
  case outcome of
    ProcessFailed failure ->
      assertFailure
        ( "Harbor token request failed:\n"
            <> Text.unpack (renderProcessOutcome (ProcessFailed failure))
        )
    ProcessSucceeded transcript ->
      case eitherDecode
        (ByteString.Lazy.fromStrict (Text.Encoding.encodeUtf8 (processTranscriptStdout transcript))) of
        Right (Aeson.Object objectValue)
          | Just (Aeson.String token) <- AesonKeyMap.lookup "token" objectValue ->
              pure token
        Right other ->
          assertFailure
            ( "Harbor token response missing token string: "
                <> show other
                <> "\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )
        Left err ->
          assertFailure
            ( "Harbor token response JSON parse failed: "
                <> err
                <> "\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )

startHarborBlobUpload
  :: HarborSubprocess.HarborSettings -> Text -> Text -> IO Text
startHarborBlobUpload settings token repository = do
  let uploadUrl =
        "http://"
          <> HarborSubprocess.harborRegistry settings
          <> "/v2/"
          <> repository
          <> "/blobs/uploads/"
  outcome <-
    runStreaming
      defaultSubprocessEnv
      ( subprocess
          (HarborSubprocess.harborCurlBinary settings)
          [ "--fail"
          , "--silent"
          , "--show-error"
          , "--dump-header"
          , "-"
          , "--output"
          , "/dev/null"
          , "--request"
          , "POST"
          , "--header"
          , "Authorization: Bearer " <> token
          , uploadUrl
          ]
      )
  case outcome of
    ProcessFailed failure ->
      assertFailure
        ( "Harbor blob upload start failed:\n"
            <> Text.unpack (renderProcessOutcome (ProcessFailed failure))
        )
    ProcessSucceeded transcript ->
      case responseHeader "location" (processTranscriptStdout transcript) of
        Just location -> pure (resolveHarborLocation settings location)
        Nothing ->
          assertFailure
            ( "Harbor blob upload start response lacks Location header:\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )

putHarborBlob
  :: HarborSubprocess.HarborSettings -> Text -> Text -> Text -> Text -> IO ()
putHarborBlob settings token uploadLocation digest payload =
  assertCurlSuccess
    "Harbor blob PUT"
    ( subprocessWithStdin
        (HarborSubprocess.harborCurlBinary settings)
        [ "--fail"
        , "--silent"
        , "--show-error"
        , "--request"
        , "PUT"
        , "--header"
        , "Authorization: Bearer " <> token
        , "--header"
        , "Content-Type: application/octet-stream"
        , "--data-binary"
        , "@-"
        , appendDigestQuery uploadLocation digest
        ]
        payload
    )

putHarborManifest
  :: HarborSubprocess.HarborSettings -> Text -> Text -> Text -> Text -> IO ()
putHarborManifest settings token repository tag payload =
  assertCurlSuccess
    "Harbor manifest PUT"
    ( subprocessWithStdin
        (HarborSubprocess.harborCurlBinary settings)
        [ "--fail"
        , "--silent"
        , "--show-error"
        , "--request"
        , "PUT"
        , "--header"
        , "Authorization: Bearer " <> token
        , "--header"
        , "Content-Type: application/vnd.oci.image.manifest.v1+json"
        , "--data-binary"
        , "@-"
        , "http://"
            <> HarborSubprocess.harborRegistry settings
            <> "/v2/"
            <> repository
            <> "/manifests/"
            <> tag
        ]
        payload
    )

assertCurlSuccess :: String -> Subprocess -> IO ()
assertCurlSuccess label command = do
  outcome <- runStreaming defaultSubprocessEnv command
  case outcome of
    ProcessSucceeded _ -> pure ()
    ProcessFailed failure ->
      assertFailure
        ( label
            <> " failed:\n"
            <> Text.unpack (renderProcessOutcome (ProcessFailed failure))
        )

responseHeader :: Text -> Text -> Maybe Text
responseHeader headerName headers =
  listToMaybe
    [ Text.strip value
    | line <- Text.lines headers
    , let (name, valueWithColon) = Text.breakOn ":" line
    , Text.toCaseFold name == Text.toCaseFold headerName
    , not (Text.null valueWithColon)
    , let value = Text.drop 1 valueWithColon
    ]

resolveHarborLocation :: HarborSubprocess.HarborSettings -> Text -> Text
resolveHarborLocation settings location
  | "http://" `Text.isPrefixOf` location || "https://" `Text.isPrefixOf` location =
      location
  | "/" `Text.isPrefixOf` location =
      "http://" <> HarborSubprocess.harborRegistry settings <> location
  | otherwise =
      "http://" <> HarborSubprocess.harborRegistry settings <> "/" <> location

appendDigestQuery :: Text -> Text -> Text
appendDigestQuery location digest
  | "?" `Text.isInfixOf` location = location <> "&digest=" <> digest
  | otherwise = location <> "?digest=" <> digest

ociDigest :: Text -> IO Text
ociDigest payload = do
  outcome <-
    runStreaming
      defaultSubprocessEnv
      (subprocessWithStdin "shasum" ["-a", "256"] payload)
  case outcome of
    ProcessSucceeded transcript ->
      case Text.words (processTranscriptStdout transcript) of
        digest : _ -> pure ("sha256:" <> digest)
        [] ->
          assertFailure
            ( "shasum produced no digest for Harbor OCI seed payload:\n"
                <> Text.unpack (renderProcessOutcome outcome)
            )
    ProcessFailed failure ->
      assertFailure
        ( "shasum failed:\n"
            <> Text.unpack (renderProcessOutcome (ProcessFailed failure))
        )

buildLocalHarborTestImage
  :: HarborSubprocess.HarborSettings
  -> ImageRef
  -> Text
  -> IO ()
buildLocalHarborTestImage settings (ImageRef imageRef) uniqueSuffix = do
  createDirectoryIfMissing True (HarborSubprocess.harborDockerConfigDir settings)
  let dockerfile =
        Text.unlines
          [ "FROM scratch"
          , "LABEL org.opencontainers.image.title=\"jitml-harbor-live-test\""
          , "LABEL org.opencontainers.image.revision=\"" <> uniqueSuffix <> "\""
          ]
      buildCommand =
        subprocessWithStdin
          (HarborSubprocess.harborDockerBinary settings)
          (harborDockerCliArgs settings ["build", "--pull=false", "-t", imageRef, "-"])
          dockerfile
  outcome <- runStreaming defaultSubprocessEnv buildCommand
  case outcome of
    ProcessSucceeded _ -> pure ()
    ProcessFailed failure ->
      assertFailure
        ( "docker build Harbor test image failed:\n"
            <> Text.unpack (renderProcessOutcome (ProcessFailed failure))
        )

harborDockerCliArgs :: HarborSubprocess.HarborSettings -> [Text] -> [Text]
harborDockerCliArgs settings args =
  maybe
    []
    (\dockerHost -> ["--host", dockerHost])
    (HarborSubprocess.harborDockerHost settings)
    <> ["--config", Text.pack (HarborSubprocess.harborDockerConfigDir settings)]
    <> args

locateJitmlBinary :: IO (Maybe FilePath)
locateJitmlBinary = do
  let preferred =
        "dist-newstyle/build/"
          <> currentArchDir
          <> "/ghc-9.12.4/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist preferred
  if exists
    then Just <$> makeAbsolute preferred
    else do
      base <-
        (Just <$> listDirectory "dist-newstyle/build")
          `Control.Exception.catch` (\(_ :: IOError) -> pure Nothing)
      case base of
        Just archEntries -> do
          built <- searchForBinary (filter matchesCurrentPlatform archEntries)
          case built of
            Just path -> pure (Just path)
            Nothing -> installedFallback
        Nothing -> installedFallback
 where
  installedFallback = do
    installed <- doesFileExist installedBinaryPath
    traverse makeAbsolute (if installed then Just installedBinaryPath else Nothing)

installedBinaryPath :: FilePath
installedBinaryPath = "/usr/local/bin/jitml"

withOccupiedLoopbackPort :: (Int -> IO a) -> IO a
withOccupiedLoopbackPort action =
  Control.Exception.bracket openSocket Socket.close $ \sock -> do
    socketName <- Socket.getSocketName sock
    case socketName of
      Socket.SockAddrInet port _ ->
        action (fromIntegral port)
      other ->
        assertFailure ("expected IPv4 loopback socket, got: " <> show other)
 where
  openSocket = do
    sock <- Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol
    Socket.bind sock (Socket.SockAddrInet 0 (Socket.tupleToHostAddress (127, 0, 0, 1)))
    pure sock

preparedStartSweep :: ProtoTune.StartSweep -> (ProtoTune.StartSweep, TuningPlan)
preparedStartSweep raw =
  case PlanCommand.prepareStartSweep raw of
    Right prepared -> prepared
    Left message -> error ("invalid StartSweep integration fixture: " <> Text.unpack message)

registeredTuningRow :: ProductMatrix.ProductRow 'ProductMatrix.Declared
registeredTuningRow =
  case filter ((== "hyperparameter-tuning") . ProductMatrix.rowId) ProductMatrix.allProductRows of
    [row] -> row
    rows ->
      error
        ( "expected exactly one registered hyperparameter-tuning ProductRow, found "
            <> show (length rows)
        )

registeredTuningTrialBudget :: Word32
registeredTuningTrialBudget =
  checkedWord32
    "registered tuning trial budget"
    (TrainingBudget.tbTargetUnits (ProductMatrix.trainingBudget registeredTuningRow))

registeredTuningSeed :: Word64
registeredTuningSeed =
  case TrainingBudget.tbSeed (ProductMatrix.trainingBudget registeredTuningRow) of
    Nothing -> error "registered tuning ProductRow is missing its sweep seed"
    Just seed -> seed

registeredTuningPerTrialBudget :: Word32
registeredTuningPerTrialBudget =
  checkedWord32
    "registered tuning per-trial optimizer-update ceiling"
    ( fromIntegral
        ( Tune.tuningSchedulerMaxBudget
            (Tune.tuningExecutionScheduler Tune.canonicalMnistTuningExecutionSpec)
        )
    )

registeredTuningStartSweep :: Substrate -> Text -> ProtoTune.StartSweep
registeredTuningStartSweep substrate experimentHash =
  ProtoTune.StartSweep
    { ProtoTune.ssExperimentHash = experimentHash
    , ProtoTune.ssDhallObjectKey = ProductMatrix.experimentConfig registeredTuningRow
    , ProtoTune.ssSubstrate = substrate
    , ProtoTune.ssSweepSeed = registeredTuningSeed
    , ProtoTune.ssTrialBudget = registeredTuningTrialBudget
    , ProtoTune.ssBudgetPerTrial = registeredTuningPerTrialBudget
    , ProtoTune.ssSampler = "TPE"
    , ProtoTune.ssScheduler = "ASHA"
    , ProtoTune.ssPruner = "MedianPruner"
    , ProtoTune.ssParallelism = fromIntegral Tune.tuningObjectiveParallelism
    , ProtoTune.ssPromotions = 1
    , ProtoTune.ssPlanId = ""
    , ProtoTune.ssResolvedPlan = ""
    }

checkedWord32 :: String -> Word64 -> Word32
checkedWord32 label value
  | value > fromIntegral (maxBound :: Word32) =
      error (label <> " exceeds the StartSweep Word32 range: " <> show value)
  | otherwise = fromIntegral value

preparedStartTraining
  :: Training.StartTraining
  -> (Training.StartTraining, SupervisedPlan)
preparedStartTraining raw =
  case PlanCommand.prepareStartTraining raw of
    Right prepared -> prepared
    Left message -> error ("invalid StartTraining integration fixture: " <> Text.unpack message)

preparedStartAlphaZero
  :: ProtoRl.StartAlphaZeroRun
  -> (ProtoRl.StartAlphaZeroRun, AlphaZeroPlan)
preparedStartAlphaZero raw =
  case PlanCommand.prepareStartAlphaZeroRun raw of
    Right prepared -> prepared
    Left message -> error ("invalid AlphaZero integration fixture: " <> Text.unpack message)

-- | Cabal's @dist-newstyle@ arch directory suffix for the current host.
-- macOS reports @darwin@ from 'SystemInfo.os', but cabal writes @osx@; Linux
-- uses @linux@ verbatim.
currentArchDir :: FilePath
currentArchDir = SystemInfo.arch <> "-" <> cabalOsSuffix
 where
  cabalOsSuffix = case SystemInfo.os of
    "darwin" -> "osx"
    other -> other

-- | Reject @dist-newstyle@ arch directories that don't match the running
-- host, so a Linux container running the test stanza ignores the macOS
-- binary the host bind-mount exposes (and vice versa).
matchesCurrentPlatform :: FilePath -> Bool
matchesCurrentPlatform arch = arch == currentArchDir

searchForBinary :: [FilePath] -> IO (Maybe FilePath)
searchForBinary [] = pure Nothing
searchForBinary (arch : rest) = do
  let path = "dist-newstyle/build" </> arch </> "ghc-9.12.4/jitml-0.1.0.0/x/jitml/build/jitml/jitml"
  exists <- doesFileExist path
  if exists
    then Just <$> makeAbsolute path
    else searchForBinary rest
