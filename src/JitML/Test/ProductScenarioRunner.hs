{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
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
  , renderNativeParentExecutionRefusal
  , runProductScenario
  )
where

import Control.Monad.Reader (runReaderT)
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (canonicalizePath, doesDirectoryExist, getCurrentDirectory)
import System.FilePath ((</>))

import Data.ByteString.Lazy qualified as LBS
import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.NativePhase.Failure qualified as NativeFailure
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Env.Build qualified as Env
import JitML.Plan.Plan (RunKind, Validation (..), planIdText)
import JitML.Product.CriterionReview qualified as Review
import JitML.Product.CriterionReviewData qualified as ReviewData
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.NativeParentEvaluationReplay qualified as NativeEvaluation
import JitML.Product.NativeParentExecution qualified as NativeParent
import JitML.Product.NativeRlCohortPlan qualified as NativeCohort
import JitML.Product.Publisher.SourceAuthority
  ( supervisedCriterionReviewEnvironment
  , supervisedQualificationSourceEnvironment
  )
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.SupervisedCohortPlan qualified as Cohort
import JitML.Product.SupervisedQualification qualified as Qualification
import JitML.Product.SupervisedQualificationReceipt qualified as Receipt
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , processTranscriptCommand
  , processTranscriptStdout
  , renderProcessFailure
  )
import JitML.Sub.Render (renderSubprocess)
import JitML.Sub.Stream (runStreaming, subprocessEnvOverrideAndRemove)
import JitML.Sub.Stream qualified as Stream
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
  sourceRoot <- getCurrentDirectory
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
            sourceRoot
            workdir
            rowId
            planId
            command
            precondition
 where
  runWithPrecondition sourceRoot workdir rowId planId command precondition = do
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
            qualificationRef <- newIORef Nothing
            nativeQualificationRef <- newIORef Nothing
            outcome <-
              LiveWorkflow.runLiveWorkflow
                (scenarioWorkflow projection command eventSource)
                ( scenarioTransport
                    sourceRoot
                    qualificationRef
                    nativeQualificationRef
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
  -> IORef
       ( Maybe
           ( Maybe Source.SourceStamp
           , Maybe Review.CapturedCriterionReview
           , Maybe Receipt.SupervisedQualificationReference
           )
       )
  -> IORef (Maybe (Source.SourceStamp, NativeParent.NativeParentExecutionCertificate))
  -> FilePath
  -> Subprocess
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> IORef (Maybe (Report.ProductScenarioPrecondition kind))
  -> LiveWorkflow.LiveTransport Subprocess (ProductScenarioEvent kind)
scenarioTransport
  sourceRoot
  qualificationRef
  nativeQualificationRef
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
                Right () ->
                  executeQualificationBoundCommand
                    sourceRoot
                    qualificationRef
                    nativeQualificationRef
                    workdir
                    projection
                    proof
                    command

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
                    qualificationRef
                    nativeQualificationRef

resolveAddressedScenario
  :: FilePath
  -> Text
  -> Text
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> IORef
       ( Maybe
           ( Maybe Source.SourceStamp
           , Maybe Review.CapturedCriterionReview
           , Maybe Receipt.SupervisedQualificationReference
           )
       )
  -> IORef (Maybe (Source.SourceStamp, NativeParent.NativeParentExecutionCertificate))
  -> IO (Either ServiceError (ProductScenarioEvent kind))
resolveAddressedScenario checkpointRoot pointerKey manifestSha projection precondition qualificationRef nativeQualificationRef = do
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
          | stableManifestSha == manifestSha -> do
              if nativeProjection projection
                then do
                  qualified <- readIORef nativeQualificationRef
                  pure $ do
                    (source, certificate) <-
                      maybe
                        (Left (SEConflict "native resolution lacks the actual owned parent execution certificate"))
                        Right
                        qualified
                    completion <-
                      mapServiceErrors
                        "ProductRow completion contract"
                        (Report.executedProductScenarioCompletion precondition projection addressedCompletion)
                    attached <-
                      mapServiceErrors
                        "ProductRow actual native parent qualification"
                        (Report.attachExecutedProductScenarioNativeCertificate source certificate completion)
                    Right (ProductScenarioEvent projection manifestSha attached)
                else do
                  qualified <- loadRunnerQualification projection precondition addressedCompletion qualificationRef
                  case qualified of
                    Left failure -> pure (Left (SEConflict failure))
                    Right publication ->
                      refineAddressedScenario
                        projection
                        precondition
                        manifestSha
                        addressedCompletion
                        publication
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
  -> Maybe Receipt.SupervisedQualificationPublication
  -> IO (Either ServiceError (ProductScenarioEvent kind))
refineAddressedScenario projection precondition manifestSha addressedCompletion qualification =
  pure $ do
    completion <-
      mapServiceErrors
        "ProductRow completion contract"
        ( Report.executedProductScenarioCompletion
            precondition
            projection
            addressedCompletion
        )
    qualifiedCompletion <-
      mapServiceErrors
        "ProductRow five-run qualification"
        (Report.attachExecutedProductScenarioQualification qualification completion)
    Right
      ProductScenarioEvent
        { eventProjection = projection
        , eventManifestSha = manifestSha
        , eventCompletion = qualifiedCompletion
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

-- | Capture the parent repository before launching the child in its isolated
-- cache directory. A child-supplied source hash is compared to this observation,
-- never treated as an authority. Incoming source overrides are always removed.
executeLegacyQualificationBoundCommand
  :: FilePath
  -> IORef
       ( Maybe
           ( Maybe Source.SourceStamp
           , Maybe Review.CapturedCriterionReview
           , Maybe Receipt.SupervisedQualificationReference
           )
       )
  -> FilePath
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> Subprocess
  -> IO (Either ServiceError Text)
executeLegacyQualificationBoundCommand sourceRoot qualificationRef workdir projection proof command = do
  sourceBefore <- captureSource
  case sourceBefore of
    Left failure -> pure (Left (SEConflict failure))
    Right (before, reviewBefore, reviewText) -> do
      let invocation = Report.productScenarioPreconditionInvocation proof
          overrides =
            [("JITML_PRODUCT_SCENARIO_INVOCATION", TrainingBudget.renderProductScenarioInvocation invocation)]
              <> maybe
                []
                (\stamp -> [(Text.pack supervisedQualificationSourceEnvironment, Source.stampSha256 stamp)])
                before
              <> maybe [] (\encoded -> [(Text.pack supervisedCriterionReviewEnvironment, encoded)]) reviewText
          childEnvironment =
            subprocessEnvOverrideAndRemove
              overrides
              ( [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
                , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
                , "JITML_PRODUCT_SCENARIO_RUN_ID"
                , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
                , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
                ]
                  <> [Text.pack supervisedQualificationSourceEnvironment | isNothing before]
                  <> [Text.pack supervisedCriterionReviewEnvironment | isNothing reviewBefore]
              )
          actualCommand =
            command
              { subprocessPath = Report.productScenarioPreconditionPinnedExecutablePath proof
              , subprocessWorkingDirectory = Just workdir
              }
      outcome <- runStreaming childEnvironment actualCommand
      case outcome of
        ProcessFailed failure -> pure (Left (SETransient (renderProcessFailure failure)))
        ProcessSucceeded transcript -> do
          binaryAfter <- Report.revalidateProductScenarioPinnedExecutable proof
          sourceAfter <- captureSource
          case binaryAfter of
            Left failure ->
              pure
                ( Left
                    ( SEConflict
                        ("ProductScenario pinned executable changed during execution: " <> Text.pack (show failure))
                    )
                )
            Right () -> case sourceAfter of
              Left failure -> pure (Left (SEConflict failure))
              Right (after, reviewAfter, _)
                | after /= before || reviewAfter /= reviewBefore ->
                    pure (Left (SEConflict "ProductScenario repository source changed during supervised execution"))
                | otherwise -> case parseQualificationLines projection (processTranscriptStdout transcript) of
                    Left failure -> pure (Left (SEConflict failure))
                    Right reference -> do
                      writeIORef qualificationRef (Just (before, reviewBefore, reference))
                      pure
                        ( Right
                            (Report.renderProductScenarioExecutionAcknowledgement proof (processTranscriptCommand transcript))
                        )
 where
  captureSource = case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedSupervisedProductPlan _ -> do
      source <- Source.computeSourceStampIn sourceRoot
      case source of
        Left reason -> pure (Left reason)
        Right stamp -> do
          captured <-
            Review.captureCriterionReviewIn
              sourceRoot
              stamp
              (ProductMatrix.productProjectionSubstrate projection)
              ReviewData.SupervisedCriterionReview
          pure $ do
            review <- mapLeft Review.renderCriterionReviewError captured
            expectedContracts <-
              Report.productScenarioReviewContractSetSha256 (ProductMatrix.productProjectionSubstrate projection)
            if ReviewData.criterionReviewContractSetSha256 (Review.capturedCriterionReviewIdentity review)
              == expectedContracts
              then Right ()
              else Left "prelaunch supervised review differs from current full55 contracts"
            encoded <-
              ReviewData.renderCriterionReviewIdentityData (Review.capturedCriterionReviewIdentity review)
            pure (Just stamp, Just review, Just encoded)
    _ -> pure (Right (Nothing, Nothing, Nothing))

-- The native branch owns its actual process, full original physical cohort,
-- independent parent checks and exact raw receipts. No callback result or
-- separately parsed child reference can mint its private certificate.
executeQualificationBoundCommand
  :: FilePath
  -> IORef
       ( Maybe
           ( Maybe Source.SourceStamp
           , Maybe Review.CapturedCriterionReview
           , Maybe Receipt.SupervisedQualificationReference
           )
       )
  -> IORef (Maybe (Source.SourceStamp, NativeParent.NativeParentExecutionCertificate))
  -> FilePath
  -> ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> Subprocess
  -> IO (Either ServiceError Text)
executeQualificationBoundCommand sourceRoot supervisedRef nativeRef workdir projection proof command
  | nativeProjection projection = do
      actualSource <- Source.computeSourceStampIn sourceRoot
      case ( actualSource
           , NativeCohort.mkCanonicalNativeRlCohorts (ProductMatrix.productProjectionSubstrate projection)
           , Report.productScenarioReviewContractSetSha256 (ProductMatrix.productProjectionSubstrate projection)
           ) of
        (Left failure, _, _) -> pure (Left (SEConflict failure))
        (_, Left failure, _) -> pure (Left (SEConflict failure))
        (_, _, Left failure) -> pure (Left (SEConflict failure))
        (Right source, Right batch, Right expectedContracts) -> do
          env <- Env.buildEnv (Env.defaultGlobalFlags {Env.globalCacheDir = Just (workdir </> ".build")})
          let request =
                NativeParent.NativeParentExecutionRequest
                  sourceRoot
                  source
                  workdir
                  (Report.productScenarioPreconditionPinnedExecutablePath proof)
                  (Report.productScenarioPreconditionInvocation proof)
          actual <-
            runReaderT (NativeParent.executeNativeParentCohortForReview expectedContracts batch request) env
          case actual of
            Left failure -> do
              reason <-
                renderNativeParentExecutionRefusal (NativeParent.nativeParentExecutionFailureReport failure)
              pure (Left (SEConflict reason))
            Right completed -> do
              let certificate = NativeParent.nativeParentExecutedCertificate completed
                  spawn = NativeParent.nativeParentCertificateSpawn certificate
                  actualCommand =
                    (subprocess (Stream.nativeSpawnExecutablePath spawn) (Stream.nativeSpawnArguments spawn))
                      { subprocessWorkingDirectory = Stream.nativeSpawnWorkingDirectory spawn
                      }
              writeIORef nativeRef (Just (source, certificate))
              pure
                (Right (Report.renderProductScenarioExecutionAcknowledgement proof (renderSubprocess actualCommand)))
  | otherwise =
      executeLegacyQualificationBoundCommand sourceRoot supervisedRef workdir projection proof command

-- | Preserve the finer actual replay stage and bounded captured refusal text.
-- This reads no report payloads/references and changes no failure classification.
renderNativeParentExecutionRefusal :: NativeParent.NativeParentExecutionReport -> IO Text
renderNativeParentExecutionRefusal report = do
  detail <- selectDetail (evaluationDetails <> parentDetails)
  pure (prefix <> evaluationStage <> maybe "" (": " <>) detail)
 where
  prefix = "actual native parent refused at " <> Text.pack (show (NativeParent.parentExecutionStage report))
  evaluation = NativeParent.parentExecutionEvaluation report
  evaluationStage = case evaluation of
    Nothing -> ""
    Just actual -> "; evaluation " <> Text.pack (show (NativeEvaluation.parentEvaluationStage actual))
  evaluationDetails = case evaluation of
    Nothing -> []
    Just actual ->
      diagnosticDetails (NativeEvaluation.parentEvaluationDiagnostic actual)
        <> refusalDetails (NativeEvaluation.parentEvaluationRefusal actual)
  parentDetails =
    diagnosticDetails (NativeParent.parentExecutionDiagnostic report)
      <> refusalDetails (NativeParent.parentExecutionRefusal report)
  diagnosticDetails Nothing = []
  diagnosticDetails (Just diagnostic) = [captureOriginal diagnostic]
  refusalDetails Nothing = []
  refusalDetails (Just reason) = [NativeFailure.captureNativeDiagnostic reason]
  captureOriginal (NativeFailure.CompleteNativeDiagnostic text) = NativeFailure.captureNativeDiagnostic text
  captureOriginal other = pure other
  selectDetail [] = pure Nothing
  selectDetail (capture : rest) = do
    captured <- capture
    case captured of
      NativeFailure.CompleteNativeDiagnostic text -> pure (Just text)
      _ -> selectDetail rest

nativeProjection :: ProductMatrix.ProductProjection kind -> Bool
nativeProjection projection =
  ProductMatrix.productProjectionFamily projection
    `elem` [ProductMatrix.ReinforcementLearning, ProductMatrix.AlphaZero]

parseQualificationLines
  :: ProductMatrix.ProductProjection kind
  -> Text
  -> Either Text (Maybe Receipt.SupervisedQualificationReference)
parseQualificationLines projection stdout =
  let candidates = filter (Text.isPrefixOf "product-supervised-qualification-") (Text.lines stdout)
   in case ProductMatrix.productProjectionResolvedPlan projection of
        ProductMatrix.ResolvedSupervisedProductPlan _ -> case candidates of
          [line] -> Just <$> Receipt.parseSupervisedQualificationReference line
          _ -> Left "supervised producer must emit exactly one strict detached qualification receipt"
        _ ->
          if null candidates
            then Right Nothing
            else Left "non-supervised producer emitted a supervised qualification receipt"

loadRunnerQualification
  :: ProductMatrix.ProductProjection kind
  -> Report.ProductScenarioPrecondition kind
  -> Report.AddressedProductScenarioCompletion kind
  -> IORef
       ( Maybe
           ( Maybe Source.SourceStamp
           , Maybe Review.CapturedCriterionReview
           , Maybe Receipt.SupervisedQualificationReference
           )
       )
  -> IO (Either Text (Maybe Receipt.SupervisedQualificationPublication))
loadRunnerQualification projection precondition addressed qualificationRef = do
  captured <- readIORef qualificationRef
  case ProductMatrix.productProjectionResolvedPlan projection of
    ProductMatrix.ResolvedSupervisedProductPlan _ ->
      case (captured, Cohort.mkSupervisedCohortPlan projection) of
        (Just (Just stamp, Just review, Just reference), Right cohort) -> do
          bytes <-
            CheckpointStore.readObject
              (Report.productScenarioPreconditionCheckpointRoot precondition)
              (Receipt.qualificationReferenceObjectKey reference)
          pure $ do
            payload <- bytes
            let invocation = Report.productScenarioPreconditionInvocation precondition
            publication <-
              case Report.addressedProductScenarioAdmittedCompletion addressed of
                Nothing -> Left "supervised resolution received host-linear actual admission"
                Just admitted ->
                  Receipt.validateSupervisedQualificationPublication
                    cohort
                    (Source.stampSha256 stamp)
                    (Report.productScenarioPreconditionExecutableSha256 precondition)
                    (TrainingBudget.productScenarioInvocationDigest invocation)
                    reference
                    (LBS.toStrict payload)
                    admitted
            let raw =
                  Qualification.supervisedQualificationToRaw
                    ( Qualification.qualifiedSupervisedCohortData
                        (Receipt.supervisedQualificationPublicationData publication)
                    )
                producer = Qualification.rawQualificationProducer raw
            observedReview <- Qualification.qualificationProducerReviewIdentity producer
            if Qualification.qualificationProducerReviewWasSupplied producer
              && observedReview == Just (Review.capturedCriterionReviewIdentity review)
              then Right (Just publication)
              else Left "supervised qualification differs from original parent prelaunch review observation"
        (_, Left failure) -> pure (Left failure)
        _ -> pure (Left "supervised resolution lacks the actual parent source/receipt observation")
    _ -> pure $ case captured of
      Just (Nothing, Nothing, Nothing) -> Right Nothing
      _ -> Left "non-supervised resolution has missing or foreign qualification observations"
