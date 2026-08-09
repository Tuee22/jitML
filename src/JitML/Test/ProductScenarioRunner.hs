{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Execute one validated ProductRow projection through the live interpreter.
--
-- The caller owns the isolated working directory.  The runner deliberately
-- publishes exactly @jitml@ plus 'ProductMatrix.productProjectionCommand', but
-- executes only the caller-authorized, canonical executable identity retained
-- by the precondition.  The process therefore uses
-- @<working-directory>/.build/checkpoints@ without a second, runner-authored
-- cache argument that could drift from the projection.
-- A row is eligible to run only when the opaque Report precondition observes
-- that its latest pointer is absent.  After successful process completion, the
-- local evidence resolver admits the pointer's exact immutable manifest
-- address, proves the pointer did not move, and binds Product.Pipeline
-- inference eligibility before the report completion can be minted.
module JitML.Test.ProductScenarioRunner
  ( ProductScenarioRunError (..)
  , productScenarioWorkflowTimeoutMicros
  , renderProductScenarioRunError
  , runProductScenario
  )
where

import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (canonicalizePath, doesDirectoryExist)
import System.FilePath ((</>))

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Plan.Plan (RunKind, Validation (..), planIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , processTranscriptCommand
  , renderProcessFailure
  )
import JitML.Sub.Stream (runStreaming, subprocessEnvOverrideAndRemove)
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (renderSubstrate)
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.ProductScenarioInterpreter.Internal qualified as ProductScenarioInterpreter
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as TrainingBudget

-- | Setup, interpreter, and final report-refinement failures remain distinct.
-- The live failure rendering includes the interpreter-owned append-only
-- journal, so a failed scenario does not collapse into a green/failed bit.
data ProductScenarioRunError
  = ProductScenarioWorkingDirectoryMissing !FilePath
  | ProductScenarioPreconditionFailed !Report.ProductScenarioPreconditionError
  | ProductScenarioEventSourceInvalid !LiveWorkflow.LiveEventSourceError
  | ProductScenarioPlacementInvalid !LiveWorkflow.PlacementHandleError
  | ProductScenarioWorkflowFailed !Text
  | ProductScenarioReportEvidenceFailed !Report.ProductScenarioEvidenceError
  deriving stock (Eq, Show)

renderProductScenarioRunError :: ProductScenarioRunError -> Text
renderProductScenarioRunError runnerError =
  case runnerError of
    ProductScenarioWorkingDirectoryMissing workdir ->
      "ProductScenario working directory does not exist: " <> Text.pack workdir
    ProductScenarioPreconditionFailed preconditionError ->
      "ProductScenario pre-execution check failed: " <> Text.pack (show preconditionError)
    ProductScenarioEventSourceInvalid sourceError ->
      "ProductScenario local event source is invalid: " <> Text.pack (show sourceError)
    ProductScenarioPlacementInvalid placementError ->
      "ProductScenario host placement is invalid: " <> Text.pack (show placementError)
    ProductScenarioWorkflowFailed failure ->
      "ProductScenario live workflow failed:\n" <> failure
    ProductScenarioReportEvidenceFailed evidenceError ->
      "ProductScenario report evidence refinement failed: "
        <> Text.pack (show evidenceError)

-- | The sole local event is constructed only after the Report module has
-- coupled its opaque chronological precondition, exact Store completion, and
-- Product.Pipeline inference reference.  Its constructor is not exported.
data ProductScenarioEvent (kind :: RunKind) = ProductScenarioEvent
  { eventProjection :: !(ProductMatrix.ProductProjection kind)
  , eventManifestSha :: !Text
  , eventCompletion :: !(Report.ExecutedProductScenarioCompletion kind)
  }
  deriving stock (Eq, Show)

data ProductScenarioProgress (kind :: RunKind)
  = ProductScenarioAwaiting
  | ProductScenarioCompleted !(Report.ExecutedProductScenarioCompletion kind)
  deriving stock (Eq, Show)

data ProductScenarioViolation
  = ProductScenarioProjectionDrift
  | ProductScenarioDuplicateCompletion
  deriving stock (Eq, Show)

newtype ProductScenarioMissing = ProductScenarioMissing Text
  deriving stock (Eq, Show)

-- | Run one kind-indexed projection in an existing isolated scenario working
-- directory and return only report evidence minted from the opaque successful
-- interpreter result.
runProductScenario
  :: Text
  -> FilePath
  -> Text
  -> FilePath
  -> ProductMatrix.ProductProjection kind
  -> IO (Either ProductScenarioRunError Report.CompletedProductScenarioEvidence)
runProductScenario runId executablePath expectedExecutableSha256 rawWorkdir projection = do
  workdirExists <- doesDirectoryExist rawWorkdir
  if not workdirExists
    then pure (Left (ProductScenarioWorkingDirectoryMissing rawWorkdir))
    else do
      workdir <- canonicalizePath rawWorkdir
      let rowId = ProductMatrix.productProjectionRowId projection
          planId = ProductMatrix.productProjectionPlanId projection
          command =
            subprocess "jitml" (ProductMatrix.productProjectionCommand projection)
          checkpointRoot = workdir </> ".build" </> "checkpoints"
      observedPrecondition <-
        Report.observeProductScenarioPrecondition
          runId
          executablePath
          expectedExecutableSha256
          checkpointRoot
          projection
      case observedPrecondition of
        Left preconditionError ->
          pure (Left (ProductScenarioPreconditionFailed preconditionError))
        Right precondition ->
          runWithPrecondition
            workdir
            rowId
            planId
            command
            precondition
 where
  runWithPrecondition workdir rowId planId command precondition = do
    let invocation = Report.productScenarioPreconditionInvocation precondition
        invocationDigest = TrainingBudget.productScenarioInvocationDigest invocation
        sourceName = "product-row-" <> rowId <> "-completion"
        sourceAddress =
          Text.intercalate
            ":"
            [ "local-product-row"
            , runId
            , rowId
            , planIdText planId
            , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
            , invocationDigest
            ]
        localSource =
          LiveWorkflow.localEventSource
            sourceName
            sourceAddress
            (renderProductScenarioEvent runId invocationDigest)
        hostHandle =
          LiveWorkflow.mkHostRunHandle
            planId
            ("product-row-" <> rowId)
    case localSource of
      Left sourceError ->
        pure (Left (ProductScenarioEventSourceInvalid sourceError))
      Right eventSource ->
        case hostHandle of
          Left placementError ->
            pure (Left (ProductScenarioPlacementInvalid placementError))
          Right handle -> do
            freshnessRef <- newIORef Nothing
            outcome <-
              LiveWorkflow.runLiveWorkflow
                (scenarioWorkflow projection command eventSource)
                ( scenarioTransport
                    workdir
                    command
                    projection
                    precondition
                    freshnessRef
                )
                (scenarioBackend workdir handle)
            pure $
              case outcome of
                Left failure ->
                  Left
                    ( ProductScenarioWorkflowFailed
                        (Text.pack (show failure))
                    )
                Right completed ->
                  case Report.completedProductScenarioEvidence
                    projection
                    (ProductScenarioInterpreter.productScenarioInterpreterRun completed) of
                    Left evidenceError ->
                      Left (ProductScenarioReportEvidenceFailed evidenceError)
                    Right evidence -> Right evidence

scenarioWorkflow
  :: ProductMatrix.ProductProjection kind
  -> Subprocess
  -> LiveWorkflow.LiveEventSource Subprocess (ProductScenarioEvent kind)
  -> LiveWorkflow.LiveWorkflow
       Subprocess
       (ProductScenarioEvent kind)
       (ProductScenarioProgress kind)
       (Report.ExecutedProductScenarioCompletion kind)
       ProductScenarioViolation
       ProductScenarioMissing
scenarioWorkflow expectedProjection command eventSource =
  LiveWorkflow.LiveWorkflow
    { LiveWorkflow.liveWorkflowPlanId =
        ProductMatrix.productProjectionPlanId expectedProjection
    , LiveWorkflow.liveWorkflowCommand = LiveWorkflow.ExecutableCommand command
    , LiveWorkflow.liveWorkflowEventSource = eventSource
    , LiveWorkflow.liveWorkflowInitialProgress = ProductScenarioAwaiting
    , LiveWorkflow.liveWorkflowIngest = ingest
    , LiveWorkflow.liveWorkflowFinish = finish
    , LiveWorkflow.liveWorkflowRenderViolation = Text.pack . show
    }
 where
  ingest ProductScenarioAwaiting event
    | eventProjection event == expectedProjection =
        Right (ProductScenarioCompleted (eventCompletion event))
    | otherwise = Left ProductScenarioProjectionDrift
  ingest ProductScenarioCompleted {} _event =
    Left ProductScenarioDuplicateCompletion

  finish ProductScenarioAwaiting =
    Failure (ProductScenarioMissing "completed product-row evidence")
  finish (ProductScenarioCompleted completion) =
    Success completion

scenarioTransport
  :: FilePath
  -> Subprocess
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> IORef (Maybe (Report.ProductScenarioPrecondition kind))
  -> LiveWorkflow.LiveTransport Subprocess (ProductScenarioEvent kind)
scenarioTransport
  workdir
  expectedCommand
  projection
  observedPrecondition
  freshnessRef =
    LiveWorkflow.LocalExecutableTransport
      { LiveWorkflow.liveObserveLocalPrecondition = observePrecondition
      , LiveWorkflow.liveExecuteLocalCommand = execute
      , LiveWorkflow.liveResolveLocalEvidence = resolve
      }
   where
    experimentHash = ProductMatrix.productProjectionExperimentHash projection
    pointerKey = Checkpoint.latestPointerKey experimentHash

    observePrecondition command
      | command /= expectedCommand =
          pure
            ( Left
                (SEConflict "ProductScenario precondition command drifted from its projection")
            )
      | otherwise = do
          writeIORef freshnessRef (Just observedPrecondition)
          pure (Right (Report.renderProductScenarioPrecondition observedPrecondition))

    execute command
      | command /= expectedCommand =
          pure
            ( Left
                (SEConflict "ProductScenario executable command drifted from its projection")
            )
      | otherwise = do
          freshness <- readIORef freshnessRef
          case freshness of
            Nothing ->
              pure
                ( Left
                    ( SEConflict
                        "ProductScenario command execution preceded the freshness proof"
                    )
                )
            Just proof -> do
              beforeLaunch <- Report.revalidateProductScenarioPinnedExecutable proof
              case beforeLaunch of
                Left failure ->
                  pure
                    ( Left
                        ( SEConflict
                            ( "ProductScenario pinned executable failed its immediate pre-launch identity check: "
                                <> Text.pack (show failure)
                            )
                        )
                    )
                Right () -> do
                  let commandInScenarioDirectory =
                        command
                          { subprocessPath =
                              Report.productScenarioPreconditionPinnedExecutablePath proof
                          , subprocessWorkingDirectory = Just workdir
                          }
                      invocation =
                        Report.productScenarioPreconditionInvocation proof
                      childEnvironment =
                        subprocessEnvOverrideAndRemove
                          [
                            ( "JITML_PRODUCT_SCENARIO_INVOCATION"
                            , TrainingBudget.renderProductScenarioInvocation invocation
                            )
                          ]
                          [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
                          , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
                          , "JITML_PRODUCT_SCENARIO_RUN_ID"
                          , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
                          , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
                          ]
                  processOutcome <-
                    runStreaming childEnvironment commandInScenarioDirectory
                  case processOutcome of
                    ProcessFailed failure ->
                      pure (Left (SETransient (renderProcessFailure failure)))
                    ProcessSucceeded transcript -> do
                      afterLaunch <-
                        Report.revalidateProductScenarioPinnedExecutable proof
                      pure $ case afterLaunch of
                        Left failure ->
                          Left
                            ( SEConflict
                                ( "ProductScenario pinned executable changed during execution: "
                                    <> Text.pack (show failure)
                                )
                            )
                        Right () ->
                          Right
                            ( Report.renderProductScenarioExecutionAcknowledgement
                                proof
                                (processTranscriptCommand transcript)
                            )

    resolve command
      | command /= expectedCommand =
          pure
            ( Left
                (SEConflict "ProductScenario resolver command drifted from its projection")
            )
      | otherwise = do
          freshness <- readIORef freshnessRef
          case freshness of
            Nothing ->
              pure
                ( Left
                    ( SEConflict
                        "ProductScenario evidence resolution preceded the freshness proof"
                    )
                )
            Just precondition -> do
              let canonicalCheckpointRoot =
                    Report.productScenarioPreconditionCheckpointRoot precondition
              pointer <-
                CheckpointStore.readCheckpointPointer canonicalCheckpointRoot pointerKey
              case pointer of
                Left err ->
                  pure
                    ( Left
                        (SETransient ("ProductScenario result pointer read failed: " <> err))
                    )
                Right Nothing ->
                  pure
                    ( Left
                        ( SETransient
                            "ProductScenario command completed without publishing a latest checkpoint"
                        )
                    )
                Right (Just manifestSha) ->
                  resolveAddressedScenario
                    canonicalCheckpointRoot
                    pointerKey
                    manifestSha
                    projection
                    precondition

resolveAddressedScenario
  :: FilePath
  -> Text
  -> Text
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> IO (Either ServiceError (ProductScenarioEvent kind))
resolveAddressedScenario checkpointRoot pointerKey manifestSha projection precondition = do
  addressedResult <-
    Report.admitAddressedProductScenarioCompletion
      checkpointRoot
      projection
      manifestSha
  case addressedResult of
    Left completionErrors ->
      pure
        ( Left
            ( SEConflict
                ( "ProductScenario addressed completion admission failed: "
                    <> Text.pack (show (NonEmpty.toList completionErrors))
                )
            )
        )
    Right addressedCompletion -> do
      pointerAfterAdmission <-
        CheckpointStore.readCheckpointPointer checkpointRoot pointerKey
      case pointerAfterAdmission of
        Left err ->
          pure
            ( Left
                ( SETransient
                    ("ProductScenario post-admission pointer read failed: " <> err)
                )
            )
        Right (Just stableManifestSha)
          | stableManifestSha == manifestSha ->
              refineAddressedScenario
                projection
                precondition
                manifestSha
                addressedCompletion
        Right observed ->
          pure
            ( Left
                ( SEConflict
                    ( "ProductScenario latest pointer changed across exact-address admission: "
                        <> Text.pack (show observed)
                    )
                )
            )

refineAddressedScenario
  :: ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> Text
  -> Report.AddressedProductScenarioCompletion kind
  -> IO (Either ServiceError (ProductScenarioEvent kind))
refineAddressedScenario projection precondition manifestSha addressedCompletion =
  pure $ do
    completion <-
      mapServiceErrors
        "ProductRow completion contract"
        ( Report.executedProductScenarioCompletion
            precondition
            projection
            addressedCompletion
        )
    Right
      ProductScenarioEvent
        { eventProjection = projection
        , eventManifestSha = manifestSha
        , eventCompletion = completion
        }

renderProductScenarioEvent :: Text -> Text -> ProductScenarioEvent kind -> Text
renderProductScenarioEvent runId invocationDigest event =
  Text.intercalate
    ":"
    [ "product-row-completed"
    , runId
    , ProductMatrix.productProjectionRowId projection
    , planIdText (ProductMatrix.productProjectionPlanId projection)
    , renderSubstrate (ProductMatrix.productProjectionSubstrate projection)
    , invocationDigest
    , eventManifestSha event
    ]
 where
  projection = eventProjection event

scenarioBackend
  :: FilePath
  -> LiveWorkflow.HostRunHandle
  -> LiveWorkflow.LiveBackend ()
scenarioBackend workdir handle =
  LiveWorkflow.LiveBackend
    { LiveWorkflow.liveAcquirePlacement =
        pure (Right (LiveWorkflow.HostRun handle))
    , LiveWorkflow.liveCompletionMode =
        LiveWorkflow.ObserveIndependentWorkload
    , LiveWorkflow.liveObserveWorkload =
        \_placement ->
          pure
            ( LiveWorkflow.ProbeFailed
                (LiveWorkflow.ProbeFailure "local executable observer must not run")
            )
    , LiveWorkflow.liveGatherDiagnostics =
        \_placement ->
          pure
            ( Right
                [ LiveWorkflow.LiveDiagnostic
                    ("product scenario working directory: " <> Text.pack workdir)
                ]
            )
    , LiveWorkflow.liveReleasePlacement = \_placement -> pure []
    , LiveWorkflow.liveObservationAttempts = 1
    , LiveWorkflow.liveObservationDelayMicros = 0
    , LiveWorkflow.liveWorkflowTimeoutMicros = productScenarioWorkflowTimeoutMicros
    }

-- | Finite operational wall-clock envelope for one exact ProductScenario.
-- This bounds command execution and evidence resolution without changing the
-- projection's TrainingBudget, PlanId, or completion-equality requirements.
-- It is exported so the envelope the runner installs is the same value the
-- unit gate pins; the heaviest canonical row exceeded the former two-hour
-- envelope before it could publish completion.
productScenarioWorkflowTimeoutMicros :: Int
productScenarioWorkflowTimeoutMicros = 4 * 60 * 60 * 1_000_000

mapServiceErrors
  :: (Show valueError)
  => Text
  -> Either (NonEmpty.NonEmpty valueError) value
  -> Either ServiceError value
mapServiceErrors context =
  mapLeft
    ( SEConflict
        . ((context <> " failed: ") <>)
        . Text.pack
        . show
        . NonEmpty.toList
    )
