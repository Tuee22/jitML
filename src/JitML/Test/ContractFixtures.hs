{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Shared, production-constructed fixtures for the typed run contract.
--
-- Everything here builds its values through the same smart constructors,
-- reducers, and Store admission the product path uses: plan identities come
-- from 'planIdFromCanonicalText', evidence events from 'evidenceEvent', and
-- the admitted checkpoint from a real 'CheckpointStore' write plus exact
-- admission.  The unit-test tree ("JitML.Test.RunContract") and the standing
-- negative-control stanza ("JitML.Test.NegativeControls") both import these
-- builders so a known-invalid fixture is always a single-field perturbation of
-- the same valid baseline the positive tests use.
module JitML.Test.ContractFixtures
  ( AtLeastTextContract
  , ProductCompletionParts (..)
  , ExactIntContract
  , ExactlyTextContract
  , assertProductCompletionError
  , assertProductMatrixError
  , assertProductReportError
  , checkpointEventId
  , copyDirectoryContents
  , curveEventId
  , curveMeasurement
  , evaluationEvent0
  , eventId
  , expectEitherRight
  , expectRight
  , expectSuccess
  , expectTextRight
  , fileSha256
  , finalMeasurement
  , ingestAll
  , isCompletionCanonicalRowMismatch
  , isCompletionExperimentMismatch
  , isCompletionInvocationMismatch
  , isCompletionManifestPlanMismatch
  , isCompletionPlanMismatch
  , isCompletionUpdateCountOverflow
  , oneOptimizerUpdate
  , persistAndAdmitProductCompletion
  , persistAndAdmitProductCompletionWithInvocation
  , persistAndAdmitUnboundProductCompletion
  , planA
  , planB
  , productCompletionParts
  , productScenarioFixtureExecutablePath
  , productScenarioFixtureExecutableSha256
  , productScenarioFixtureRunId
  , refinedEvidence
  , reportFixtureDeviceWitness
  , reportFixtureRuntime
  , rlCompletedCheckpointEvent
  , runProductScenarioWorkflow
  , runProductScenarioWorkflowAtPlan
  , secondCheckpointEventId
  , supervisedCompletedCheckpointEvent
  , supervisedEpochEvent
  , telemetryEvent0
  , trainingBudgetFixture
  , trainingCheckpointEvent
  , trainingEventEpoch
  , trainingEvidenceEvent
  , updateEventId
  , withAdmittedProductProjection
  , withDifferentProductProjection
  , withDifferentSupervisedProductProjection
  , withFirstProductProjection
  , withProjectedRow
  , withSupervisedProductFixture
  )
where

import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Foldable (traverse_)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32, Word64)
import Numeric (showHex)
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , listDirectory
  )
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty.HUnit (assertBool, assertFailure)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Numerics.LayerGraphMetadata
  ( layerGraphMetadataFromGraph
  , layerGraphMetadataParameterCount
  )
import JitML.Plan.Plan
  ( EventId
  , FiniteMeasurement
  , PlanId
  , Quantity
  , RunKind (..)
  , RunKindWitness (..)
  , Unit (..)
  , Validation (..)
  , deriveEventIdForPlanId
  , mkFiniteMeasurement
  , mkQuantity
  , planIdFromCanonicalText
  , planIdText
  , quantityValue
  )
import JitML.Plan.Workload qualified as WorkloadPlan
import JitML.Product.Completion qualified as ProductCompletion
import JitML.Product.Convergence qualified as ProductConvergence
import JitML.Product.DeviceWitness qualified as DeviceWitness
import JitML.Product.Evidence qualified as ProductEvidence
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Run.Contract
import JitML.SL.Architecture qualified as Architecture
import JitML.SL.Canonicals qualified as SL
import JitML.SL.Classifier qualified as Classifier
import JitML.SL.Dataset qualified as Dataset
import JitML.SL.RuntimeArtifact qualified as RuntimeArtifact
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (..), renderSubstrate)
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.ProductScenarioInterpreter.Internal qualified as ProductScenarioInterpreter
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as TrainingBudget

-- The report boundary deliberately accepts no caller-built completion.  Unit
-- tests therefore persist and re-admit one exact ProductRow V2 graph instead
-- of using a privileged constructor or a decoded-manifest shortcut.
productScenarioFixtureRunId :: Text
productScenarioFixtureRunId = "phase-261-run-contract"

productScenarioFixtureExecutablePath :: FilePath
productScenarioFixtureExecutablePath = "/usr/bin/true"

productScenarioFixtureExecutableSha256 :: IO Text
productScenarioFixtureExecutableSha256 =
  fileSha256 productScenarioFixtureExecutablePath

fileSha256 :: FilePath -> IO Text
fileSha256 path =
  hexBytes . SHA256.hash <$> ByteString.readFile path
 where
  hexBytes = Text.pack . concatMap byteHex . ByteString.unpack
  byteHex byte =
    case showHex byte "" of
      [low] -> ['0', low]
      pair -> pair

copyDirectoryContents :: FilePath -> FilePath -> IO ()
copyDirectoryContents source target = do
  createDirectoryIfMissing True target
  entries <- listDirectory source
  traverse_
    ( \entry -> do
        let sourcePath = source </> entry
            targetPath = target </> entry
        isDirectory <- doesDirectoryExist sourcePath
        if isDirectory
          then copyDirectoryContents sourcePath targetPath
          else copyFile sourcePath targetPath
    )
    entries

withAdmittedProductProjection
  :: ( FilePath
       -> ProductMatrix.ProductRow 'ProductMatrix.Declared
       -> ProductMatrix.ProductProjection 'SupervisedTraining
       -> Report.ProductScenarioPrecondition 'SupervisedTraining
       -> Report.AddressedProductScenarioCompletion 'SupervisedTraining
       -> CheckpointStore.AdmittedCompletedCheckpoint
       -> IO result
     )
  -> IO result
withAdmittedProductProjection action =
  withSystemTempDirectory "jitml-report-admission" $ \root ->
    withSupervisedProductFixture $ \row problem projection -> do
      precondition <-
        productScenarioFixtureExecutableSha256 >>= \executableSha256 ->
          Report.observeProductScenarioPrecondition
            productScenarioFixtureRunId
            productScenarioFixtureExecutablePath
            executableSha256
            root
            projection
            >>= expectRight
      admitted <-
        persistAndAdmitProductCompletion
          root
          row
          problem
          projection
          (Report.productScenarioPreconditionInvocation precondition)
      let manifestSha =
            CheckpointStore.admittedCheckpointManifestSha
              (CheckpointStore.admittedCompletedCheckpoint admitted)
      addressed <-
        Report.admitAddressedProductScenarioCompletion root projection manifestSha
          >>= expectRight
      action root row projection precondition addressed admitted

withSupervisedProductFixture
  :: ( ProductMatrix.ProductRow 'ProductMatrix.Declared
       -> SL.CanonicalProblem
       -> ProductMatrix.ProductProjection 'SupervisedTraining
       -> IO result
     )
  -> IO result
withSupervisedProductFixture action = do
  row <-
    maybe
      (assertFailure "missing authoritative mnist-shallow-mlp ProductRow")
      pure
      ( find
          ((== "mnist-shallow-mlp") . ProductMatrix.rowId)
          ProductMatrix.allProductRows
      )
  problem <-
    maybe
      (assertFailure "missing canonical mnist-shallow-mlp problem")
      pure
      (find ((== "mnist-shallow-mlp") . SL.problemName) SL.canonicalProblems)
  projection <-
    case ProductMatrix.projectProductRow LinuxCPU row of
      Failure errors ->
        assertFailure ("ProductRow projection failed: " <> show errors)
      Success
        ( ProductMatrix.SomeProductProjection
            SupervisedTrainingWitness
            exactProjection
          ) -> pure exactProjection
      Success _ ->
        assertFailure "mnist-shallow-mlp projection is not supervised"
  action row problem projection

persistAndAdmitProductCompletion
  :: FilePath
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> SL.CanonicalProblem
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> TrainingBudget.ProductScenarioInvocation
  -> IO CheckpointStore.AdmittedCompletedCheckpoint
persistAndAdmitProductCompletion root row problem projection invocation =
  persistAndAdmitProductCompletionWithInvocation
    root
    row
    problem
    projection
    (Just invocation)

persistAndAdmitUnboundProductCompletion
  :: FilePath
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> SL.CanonicalProblem
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> IO CheckpointStore.AdmittedCompletedCheckpoint
persistAndAdmitUnboundProductCompletion root row problem projection =
  persistAndAdmitProductCompletionWithInvocation
    root
    row
    problem
    projection
    Nothing

persistAndAdmitProductCompletionWithInvocation
  :: FilePath
  -> ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> SL.CanonicalProblem
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> Maybe TrainingBudget.ProductScenarioInvocation
  -> IO CheckpointStore.AdmittedCompletedCheckpoint
persistAndAdmitProductCompletionWithInvocation root row problem projection invocation = do
  parts <- productCompletionParts row problem projection invocation
  _ <-
    expectRight
      =<< CheckpointStore.writeCompletedCheckpointSnapshot
        root
        (pcpCompleted parts)
        (pcpManifest parts)
        (pcpPayloads parts)
        Nothing
  admittedCheckpoint <-
    expectRight
      =<< CheckpointStore.admitLocalLatestCheckpoint root (pcpExperiment parts)
  expectRight
    (CheckpointStore.requireAdmittedCompletedCheckpoint admittedCheckpoint)

-- | Everything a completed supervised checkpoint is made of, before any of it
-- is written: the refined completion, its manifest (with and without the
-- completion attached), and the exact weight payloads.  The negative controls
-- take the parts apart to write a candidate, to attach a completion the
-- manifest does not carry, or to substitute one row's identity for another's;
-- 'persistAndAdmitProductCompletionWithInvocation' writes them whole.
data ProductCompletionParts = ProductCompletionParts
  { pcpExperiment :: Text
  , pcpCompleted :: TrainingBudget.CompletedTraining
  , pcpBaseManifest :: Checkpoint.CheckpointManifest
  -- ^ The manifest before 'Checkpoint.attachCompletedTraining'.
  , pcpManifest :: Checkpoint.CheckpointManifest
  , pcpPayloads :: [(Text, LazyByteString.ByteString)]
  }

productCompletionParts
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> SL.CanonicalProblem
  -> ProductMatrix.ProductProjection 'SupervisedTraining
  -> Maybe TrainingBudget.ProductScenarioInvocation
  -> IO ProductCompletionParts
productCompletionParts row problem projection invocation = do
  datasetSha <- expectRight (Dataset.canonicalDatasetReadShaForProblem problem)
  fixtureSpec <-
    expectRight
      ( Architecture.architectureSpecForProblem
          Classifier.defaultClassifierConfig
            { Classifier.clfInputs = 784
            , Classifier.clfClasses = 10
            , Classifier.clfSeed = SL.problemSeed problem
            }
          problem
      )
  let plan =
        case ProductMatrix.productProjectionResolvedPlan projection of
          ProductMatrix.ResolvedSupervisedProductPlan resolved -> resolved
      -- Phase 239: the fixture checkpoint is the trained dense mnist-shallow-mlp
      -- graph.  Its graph-ordered parameter count anchors the synthetic weight
      -- blobs, the flat weight layout, and admission.
      graphMeta =
        layerGraphMetadataFromGraph (Architecture.archLayerGraph fixtureSpec)
      parameterCount = layerGraphMetadataParameterCount graphMeta
      initialBytes = WeightCodec.encodeJmw1 (replicate parameterCount 0.0)
      finalBytes =
        WeightCodec.encodeJmw1
          (0.25 : replicate (parameterCount - 1) 0.0)
      initialSha = WeightCodec.jmw1ContentSha initialBytes
      finalSha = WeightCodec.jmw1ContentSha finalBytes
      experiment = ProductMatrix.productProjectionExperimentHash projection
      planId = ProductMatrix.productProjectionPlanId projection
      budget = ProductMatrix.productProjectionTrainingBudget projection
      observedUnits = TrainingBudget.trainingBudgetTargetUnits budget
      optimizerUpdates =
        quantityValue (WorkloadPlan.supervisedPlanOptimizerUpdates plan)
      bar = ProductMatrix.productProjectionConvergenceBar projection
      metrics =
        [
          ( ProductConvergence.convergenceMetricName bar
          , ProductConvergence.convergenceThreshold bar
          )
        ]
  payload <-
    expectRight
      ( RuntimeArtifact.refineSupervisedRuntimePayload
          RuntimeArtifact.RawSupervisedRuntimePayload
            { RuntimeArtifact.rawRuntimePayloadRowId = ProductMatrix.rowId row
            , RuntimeArtifact.rawRuntimePayloadOrigin =
                RuntimeArtifact.RawProductRowProjectionOrigin
            , RuntimeArtifact.rawRuntimePayloadPlanId = planIdText planId
            , RuntimeArtifact.rawRuntimePayloadDatasetSha256 = datasetSha
            , RuntimeArtifact.rawRuntimePayloadInitialJmw1Sha256 = initialSha
            , RuntimeArtifact.rawRuntimePayloadFinalJmw1Sha256 = finalSha
            , RuntimeArtifact.rawRuntimePayloadRuntime = reportFixtureRuntime
            , RuntimeArtifact.rawRuntimePayloadLayerGraphMetadata = Just graphMeta
            }
      )
  metadata <-
    expectRight (Checkpoint.canonicalSupervisedRuntimeManifestMetadata payload)
  fixtureWitness <- reportFixtureDeviceWitness
  unboundCompleted <-
    expectRight
      ( ProductCompletion.completedTrainingForProductRowWithWeightHashes
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
          (Just fixtureWitness)
      )
  completed <- case invocation of
    Nothing -> pure unboundCompleted
    Just invoked ->
      expectRight
        ( TrainingBudget.bindCompletedTrainingToProductScenarioInvocation
            invoked
            unboundCompleted
        )
  let tensor =
        Checkpoint.TensorBlob
          "supervised.weights"
          [parameterCount]
          (Checkpoint.blobKey experiment finalSha)
      baseManifest =
        (Checkpoint.emptyManifest "report-admission" experiment [tensor])
          { Checkpoint.manifestModelFamily = Checkpoint.SupervisedModelFamily
          , Checkpoint.manifestArchitecture =
              Checkpoint.supervisedRuntimeArchitectureMetadata metadata
          , Checkpoint.manifestPreprocessing =
              Checkpoint.supervisedRuntimePreprocessingMetadata metadata
          , Checkpoint.manifestOutputDecoders =
              Checkpoint.supervisedRuntimeOutputDecoderMetadata metadata
          , Checkpoint.manifestWeightLayout =
              Checkpoint.FlatWeightLayout
                [ Checkpoint.TensorSpec
                    { Checkpoint.tensorSpecName = "supervised.weights"
                    , Checkpoint.tensorSpecShape = [parameterCount]
                    , Checkpoint.tensorSpecDtype = "F64"
                    }
                ]
          , Checkpoint.manifestStep = observedUnits
          , Checkpoint.manifestMetrics = metrics
          , Checkpoint.manifestSupervisedRuntime = Just payload
          }
  pure
    ProductCompletionParts
      { pcpExperiment = experiment
      , pcpCompleted = completed
      , pcpBaseManifest = baseManifest
      , pcpManifest = Checkpoint.attachCompletedTraining completed baseManifest
      , pcpPayloads = [(Checkpoint.tensorBlobKey tensor, finalBytes)]
      }

reportFixtureRuntime :: RuntimeArtifact.RawSupervisedRuntime
reportFixtureRuntime =
  RuntimeArtifact.RawSupervisedRuntime
    { RuntimeArtifact.rawSupervisedRuntimeTask =
        RuntimeArtifact.RawClassificationRuntimeTask 10
    , RuntimeArtifact.rawSupervisedRuntimeInputTransform =
        RuntimeArtifact.RawUnitImageInput
          (RuntimeArtifact.RawRuntimeImageGeometry 28 28 1)
    , RuntimeArtifact.rawSupervisedRuntimeOutputTransform =
        RuntimeArtifact.RawSemanticPrefixOutput 10
    }

withDifferentProductProjection
  :: ProductMatrix.ProductRow 'ProductMatrix.Declared
  -> (forall kind. ProductMatrix.ProductProjection kind -> IO result)
  -> IO result
withDifferentProductProjection admittedRow action =
  case filter ((/= ProductMatrix.rowId admittedRow) . ProductMatrix.rowId) ProductMatrix.allProductRows of
    [] -> assertFailure "ProductRow registry needs at least two rows"
    row : _ -> withProjectedRow LinuxCPU row action

withDifferentSupervisedProductProjection
  :: ProductMatrix.ProductProjection 'SupervisedTraining
  -> (ProductMatrix.ProductProjection 'SupervisedTraining -> IO result)
  -> IO result
withDifferentSupervisedProductProjection admittedProjection action =
  findDifferent
    ( ProductMatrix.productProjectionBatchProjections
        (expectSuccess (ProductMatrix.projectProductRows LinuxCPU ProductMatrix.allProductRows))
    )
 where
  findDifferent projections =
    case projections of
      [] -> assertFailure "ProductRow registry needs two supervised projections"
      ProductMatrix.SomeProductProjection SupervisedTrainingWitness projection : rest
        | projection /= admittedProjection -> action projection
        | otherwise -> findDifferent rest
      _other : rest -> findDifferent rest

withFirstProductProjection
  :: ( forall kind
        . ProductMatrix.ProductRow 'ProductMatrix.Declared
       -> ProductMatrix.ProductProjection kind
       -> IO result
     )
  -> IO result
withFirstProductProjection action =
  case ProductMatrix.allProductRows of
    [] -> assertFailure "ProductRow registry is unexpectedly empty"
    row : _ -> withProjectedRow LinuxCPU row (action row)

withProjectedRow
  :: Substrate
  -> ProductMatrix.ProductRow state
  -> (forall kind. ProductMatrix.ProductProjection kind -> IO result)
  -> IO result
withProjectedRow substrate row action =
  case ProductMatrix.projectProductRow substrate row of
    Failure errors ->
      assertFailure ("ProductRow projection failed: " <> show errors)
    Success (ProductMatrix.SomeProductProjection _witness projection) ->
      action projection

trainingBudgetFixture
  :: TrainingBudget.BudgetKind
  -> Word64
  -> Maybe Word64
  -> TrainingBudget.TrainingBudget
trainingBudgetFixture kind target seed =
  expectTextRight
    "product training budget"
    (TrainingBudget.mkTrainingBudget kind target seed)

expectEitherRight :: (Show error) => Either error value -> value
expectEitherRight result =
  case result of
    Left err -> error ("expected Right, got Left " <> show err)
    Right value -> value

assertProductCompletionError
  :: (Report.ProductScenarioCompletionError -> Bool)
  -> Either
       (NonEmpty Report.ProductScenarioCompletionError)
       (Report.ProductScenarioCompletion kind)
  -> IO ()
assertProductCompletionError predicate result =
  case result of
    Left errors -> assertBool "expected typed product-completion error" (any predicate errors)
    Right _ -> assertFailure "misbound admitted checkpoint minted ProductScenarioCompletion"

assertProductMatrixError
  :: (ProductMatrix.ProductMatrixError -> Bool)
  -> Validation (NonEmpty ProductMatrix.ProductMatrixError) ProductMatrix.ProductProjectionBatch
  -> IO ()
assertProductMatrixError predicate result =
  case result of
    Failure errors -> assertBool "expected typed product-matrix error" (any predicate errors)
    Success _ -> assertFailure "invalid ProductRow registry minted ProductProjectionBatch"

assertProductReportError
  :: (Report.ProductScenarioReportError -> Bool)
  -> Either
       (NonEmpty Report.ProductScenarioReportError)
       Report.CompletedProductScenarioReport
  -> IO ()
assertProductReportError predicate result =
  case result of
    Left errors -> assertBool "expected typed product-report error" (any predicate errors)
    Right _ -> assertFailure "invalid evidence minted CompletedProductScenarioReport"

isCompletionPlanMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionPlanMismatch Report.ProductCompletionPlanMismatch {} = True
isCompletionPlanMismatch _ = False

isCompletionExperimentMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionExperimentMismatch Report.ProductCompletionExperimentMismatch {} = True
isCompletionExperimentMismatch _ = False

isCompletionCanonicalRowMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionCanonicalRowMismatch Report.ProductCompletionCanonicalRowMismatch {} = True
isCompletionCanonicalRowMismatch _ = False

isCompletionManifestPlanMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionManifestPlanMismatch Report.ProductCompletionManifestPlanMismatch {} = True
isCompletionManifestPlanMismatch _ = False

isCompletionInvocationMismatch :: Report.ProductScenarioCompletionError -> Bool
isCompletionInvocationMismatch Report.ProductCompletionInvocationMismatch {} = True
isCompletionInvocationMismatch _ = False

isCompletionUpdateCountOverflow :: Report.ProductScenarioCompletionError -> Bool
isCompletionUpdateCountOverflow Report.ProductCompletionUpdateCountOverflow {} = True
isCompletionUpdateCountOverflow _ = False

runProductScenarioWorkflow
  :: FilePath
  -> Text
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> Report.ExecutedProductScenarioCompletion kind
  -> IO
       ( ProductScenarioInterpreter.ProductScenarioInterpreterRun
           Text
           (Report.ExecutedProductScenarioCompletion kind)
           Text
           Text
       )
runProductScenarioWorkflow checkpointRoot manifestSha projection =
  runProductScenarioWorkflowAtPlan
    (ProductMatrix.productProjectionPlanId projection)
    checkpointRoot
    manifestSha
    projection

runProductScenarioWorkflowAtPlan
  :: PlanId
  -> FilePath
  -> Text
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> Report.ExecutedProductScenarioCompletion kind
  -> IO
       ( ProductScenarioInterpreter.ProductScenarioInterpreterRun
           Text
           (Report.ExecutedProductScenarioCompletion kind)
           Text
           Text
       )
runProductScenarioWorkflowAtPlan
  livePlanId
  _checkpointRoot
  manifestSha
  projection
  precondition
  scenarioCompletion = do
    source <-
      expectRight
        ( LiveWorkflow.localEventSource
            sourceName
            sourceAddress
            ( \observed ->
                if observed == scenarioCompletion
                  then evidencePayload
                  else "product-scenario-unit-evidence-drift"
            )
        )
    handle <-
      expectRight
        ( LiveWorkflow.mkHostRunHandle
            livePlanId
            ("product-row-" <> rowId)
        )
    let command =
          subprocess
            "jitml"
            (ProductMatrix.productProjectionCommand projection)
        workdir =
          takeDirectory
            ( takeDirectory
                (Report.productScenarioPreconditionCheckpointRoot precondition)
            )
        executedCommand =
          command
            { subprocessPath =
                Report.productScenarioPreconditionPinnedExecutablePath precondition
            , subprocessWorkingDirectory = Just workdir
            }
        transport =
          LiveWorkflow.LocalExecutableTransport
            { LiveWorkflow.liveObserveLocalPrecondition =
                const
                  ( pure
                      (Right (Report.renderProductScenarioPrecondition precondition))
                  )
            , LiveWorkflow.liveExecuteLocalCommand =
                const
                  ( pure
                      ( Right
                          ( Report.renderProductScenarioExecutionAcknowledgement
                              precondition
                              (renderSubprocess executedCommand)
                          )
                      )
                  )
            , LiveWorkflow.liveResolveLocalEvidence =
                const (pure (Right scenarioCompletion))
            }
        workflow =
          LiveWorkflow.LiveWorkflow
            { LiveWorkflow.liveWorkflowPlanId =
                livePlanId
            , LiveWorkflow.liveWorkflowCommand =
                LiveWorkflow.ExecutableCommand command
            , LiveWorkflow.liveWorkflowEventSource = source
            , LiveWorkflow.liveWorkflowInitialProgress = Nothing
            , LiveWorkflow.liveWorkflowIngest = \_progress event ->
                if event == scenarioCompletion
                  then Right (Just event)
                  else Left "product scenario evidence changed in transit"
            , LiveWorkflow.liveWorkflowFinish = \case
                Just completed -> Success completed
                Nothing -> Failure "product scenario evidence missing"
            , LiveWorkflow.liveWorkflowRenderViolation = id
            }
        backend =
          LiveWorkflow.LiveBackend
            { LiveWorkflow.liveAcquirePlacement =
                pure (Right (LiveWorkflow.HostRun handle))
            , LiveWorkflow.liveCompletionMode =
                LiveWorkflow.ObserveIndependentWorkload
            , LiveWorkflow.liveObserveWorkload =
                const
                  ( pure
                      ( LiveWorkflow.ProbeFailed
                          (LiveWorkflow.ProbeFailure "local executable must not poll workload state")
                      )
                  )
            , LiveWorkflow.liveGatherDiagnostics =
                const
                  ( pure
                      ( Right
                          [ LiveWorkflow.LiveDiagnostic
                              ( "product scenario working directory: "
                                  <> Text.pack workdir
                              )
                          ]
                      )
                  )
            , LiveWorkflow.liveReleasePlacement = const (pure [])
            , LiveWorkflow.liveObservationAttempts = 1
            , LiveWorkflow.liveObservationDelayMicros = 0
            , LiveWorkflow.liveWorkflowTimeoutMicros = 1_000_000
            }
    completed <-
      LiveWorkflow.runLiveWorkflow workflow transport backend >>= expectRight
    pure (ProductScenarioInterpreter.productScenarioInterpreterRun completed)
   where
    rowId = ProductMatrix.productProjectionRowId projection
    invocation = Report.productScenarioPreconditionInvocation precondition
    runId = TrainingBudget.productScenarioInvocationRunId invocation
    invocationDigest = TrainingBudget.productScenarioInvocationDigest invocation
    sourceName = "product-row-" <> rowId <> "-completion"
    sourceAddress =
      Text.intercalate
        ":"
        [ "local-product-row"
        , runId
        , rowId
        , planIdText (ProductMatrix.productProjectionPlanId projection)
        , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
        , invocationDigest
        ]
    evidencePayload =
      Text.intercalate
        ":"
        [ "product-row-completed"
        , runId
        , rowId
        , planIdText (ProductMatrix.productProjectionPlanId projection)
        , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
        , invocationDigest
        , manifestSha
        ]

type ExactlyTextContract =
  Contract
    (EvidenceEvent () Text)
    (RequirementState () Text)
    (ExactlyOne Text)

type AtLeastTextContract =
  Contract
    (EvidenceEvent Int Text)
    (RequirementState Int Text)
    (AtLeastOne Int Text)

type ExactIntContract =
  Contract
    (EvidenceEvent Int Double)
    (RequirementState Int Double)
    (ExactKeyed Int Double)

ingestAll
  :: Contract event progress evidence
  -> [event]
  -> IO progress
ingestAll contract = go (initialProgress contract)
 where
  go progress [] = pure progress
  go progress (event : rest) = do
    next <- expectRight (ingestEvent contract progress event)
    go next rest

-- | A fixture device execution witness minted over a real on-disk artifact.
--
-- 'DeviceWitness.witnessDeviceExecution' exposes no pure constructor, so even a
-- fixture cannot conjure a witness: it has to materialise an artifact and let
-- the mint read and digest it. That is deliberate — it keeps the fixture path
-- and the production path agreeing about what a witness costs.
reportFixtureDeviceWitness :: IO DeviceWitness.DeviceExecutionWitness
reportFixtureDeviceWitness =
  withSystemTempDirectory "jitml-fixture-artifact" $ \dir -> do
    let artifact = dir </> "kernel.so"
    ByteString.writeFile artifact "jitml-report-fixture-artifact"
    minted <-
      DeviceWitness.witnessDeviceExecution
        LinuxCPU
        "onednn"
        (Text.replicate 64 "0")
        artifact
        "jitml_matmul_forward"
    expectRight minted

expectRight :: (Show error) => Either error value -> IO value
expectRight result =
  case result of
    Right value -> pure value
    Left err -> assertFailure ("expected Right, got Left " <> show err) >> error "unreachable"

expectSuccess :: (Show error) => Validation error value -> value
expectSuccess result =
  case result of
    Success value -> value
    Failure err -> error ("expected Success, got Failure " <> show err)

supervisedEpochEvent :: Text -> Word32 -> Double -> Training.TrainingEvent
supervisedEpochEvent experimentHash epoch loss =
  Training.TrainingEpoch
    Training.EpochCompleted
      { Training.ecExperimentHash = experimentHash
      , Training.ecEpoch = epoch
      , Training.ecLoss = loss
      , Training.ecValidationLoss = loss
      , Training.ecTimestampNs = fromIntegral epoch + 1
      }

supervisedCompletedCheckpointEvent
  :: PlanId
  -> Word32
  -> Text
  -> Training.TrainingEvent
supervisedCompletedCheckpointEvent completionPlanId epoch experimentHash =
  Training.TrainingCompletedCheckpoint
    ( expectTextRight "completed supervised checkpoint" $ do
        budget <-
          TrainingBudget.mkTrainingBudget
            TrainingBudget.SupervisedEpochBudget
            (fromIntegral epoch)
            (Just 7)
        evidence <-
          ProductEvidence.mkTrainingEvidence
            "supervised-initial-weights"
            "supervised-final-weights"
            (fromIntegral epoch)
            "supervised-dataset-at-read"
        measurement <-
          TrainingBudget.measureCriterion
            "accuracy"
            TrainingBudget.MetricMaximise
            0.5
            0.9
        completed <-
          TrainingBudget.completedTraining
            completionPlanId
            budget
            (fromIntegral epoch)
            evidence
            [measurement]
            TrainingBudget.TensorBoardRunMetadata
              { TrainingBudget.tbrRunId = "supervised-live-run"
              , TrainingBudget.tbrLogPrefix = "tensorboard/supervised-live-run"
              , TrainingBudget.tbrScalarTags = ["accuracy"]
              }
        Training.completeCheckpointDone
          (trainingCheckpointEvent epoch experimentHash)
          completed
    )

rlCompletedCheckpointEvent
  :: PlanId
  -> Word64
  -> Text
  -> Rl.RlEvent
rlCompletedCheckpointEvent completionPlanId step experimentHash =
  Rl.RlCompletedCheckpoint
    ( expectTextRight "completed RL checkpoint" $ do
        budget <-
          TrainingBudget.mkTrainingBudget
            TrainingBudget.RlEnvironmentStepBudget
            step
            (Just 7)
        evidence <-
          ProductEvidence.mkTrainingEvidence
            "rl-live-initial-weights"
            "rl-live-final-weights"
            1
            "rl-live-dataset-at-read"
        measurement <-
          TrainingBudget.measureCriterion
            "median_final_reward"
            TrainingBudget.MetricMaximise
            0.0
            2.0
        completed <-
          TrainingBudget.completedTraining
            completionPlanId
            budget
            step
            evidence
            [measurement]
            TrainingBudget.TensorBoardRunMetadata
              { TrainingBudget.tbrRunId = "rl-live-run"
              , TrainingBudget.tbrLogPrefix = "tensorboard/rl-live-run"
              , TrainingBudget.tbrScalarTags = ["median_final_reward"]
              }
        Rl.completeCheckpointDoneRL
          Rl.CheckpointDoneRL
            { Rl.cdrlExperimentHash = experimentHash
            , Rl.cdrlManifestSha = "rl-live-manifest"
            , Rl.cdrlStep = step
            , Rl.cdrlPointerKey = "checkpoints/rl-live/latest"
            }
          completed
    )

trainingCheckpointEvent :: Word32 -> Text -> Training.CheckpointDone
trainingCheckpointEvent epoch experimentHash =
  Training.CheckpointDone
    { Training.cdExperimentHash = experimentHash
    , Training.cdManifestSha = "supervised-live-manifest"
    , Training.cdStep = fromIntegral epoch
    , Training.cdPointerKey = "checkpoints/supervised-live/latest"
    , Training.cdEpoch = epoch
    , Training.cdTrialSha = Nothing
    , Training.cdRunUuid = "supervised-live-run"
    , Training.cdMetricsAtStep = [("accuracy", 0.9)]
    }

expectTextRight :: Text -> Either Text value -> value
expectTextRight label result =
  case result of
    Left failure ->
      error (Text.unpack (label <> ": " <> failure))
    Right value -> value

trainingEvidenceEvent :: Word32 -> Double -> Training.TrainingEvent
trainingEvidenceEvent =
  supervisedEpochEvent "late-evidence"

trainingEventEpoch :: Training.TrainingEvent -> Word32
trainingEventEpoch event =
  case event of
    Training.TrainingEpoch epoch -> Training.ecEpoch epoch
    _ -> 0

refinedEvidence
  :: (Show key)
  => PlanId
  -> Text
  -> key
  -> value
  -> EvidenceEvent key value
refinedEvidence plan kind key value =
  expectSuccess (evidenceEvent plan kind key value)

planA :: PlanId
planA = expectSuccess (planIdFromCanonicalText "run-contract-plan-a")

planB :: PlanId
planB = expectSuccess (planIdFromCanonicalText "run-contract-plan-b")

eventId :: PlanId -> Text -> Text -> EventId
eventId plan kind key =
  expectSuccess (deriveEventIdForPlanId plan kind key)

checkpointEventId :: EventId
checkpointEventId = eventId planA "checkpoint" "()"

secondCheckpointEventId :: EventId
secondCheckpointEventId = eventId planA "checkpoint-alternate" "()"

telemetryEvent0 :: EventId
telemetryEvent0 = eventId planA "telemetry" "0"

evaluationEvent0 :: EventId
evaluationEvent0 = eventId planA "evaluation" "0"

updateEventId :: EventId
updateEventId = eventId planA "training-progress" "1"

curveEventId :: EventId
curveEventId = eventId planA "learning-curve" "1"

oneOptimizerUpdate :: Quantity 'OptimizerUpdate
oneOptimizerUpdate = expectSuccess (mkQuantity "optimizer-update" 1)

curveMeasurement :: FiniteMeasurement
curveMeasurement = expectSuccess (mkFiniteMeasurement "training-loss" 0.75)

finalMeasurement :: FiniteMeasurement
finalMeasurement = expectSuccess (mkFiniteMeasurement "final-return" 42.0)
