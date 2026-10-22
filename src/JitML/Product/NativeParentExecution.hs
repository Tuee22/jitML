{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Owned actual native child launch and independent physical/numerical
-- parent checks. Ordinary request fields are not a Report precondition or an
-- authenticated journal. No runtime, evaluator, trainer, reader or result
-- callback is accepted. Loaded-image/source-build coherence remains external.
module JitML.Product.NativeParentExecution
  ( NativeParentExecutionRequest (..)
  , NativeParentExecutableFileData (..)
  , NativeParentExecutionStage (..)
  , NativeParentExecutionReport (..)
  , NativeParentExecutedCohort
  , NativeParentExecutionFailure
  , NativeParentExecutionCertificate
  , nativeParentExecutedCertificate
  , nativeParentCertificateRequest
  , nativeParentCertificateReference
  , nativeParentCertificateAdmitted
  , nativeParentCertificateSpawn
  , nativeParentCertificateAttemptInventory
  , nativeParentCertificateAttemptScope
  , nativeParentCertificateEvaluationSummary
  , nativeParentCertificateCriterionReview
  , executeNativeParentCohort
  , executeNativeParentCohortForReview
  , nativeParentExecutedRequest
  , nativeParentExecutedReference
  , nativeParentExecutedPhysical
  , nativeParentExecutedEvaluations
  , nativeParentExecutionReport
  , nativeParentExecutionFailureReport
  ) where

import Codec.CBOR.Encoding qualified as CBOR
import Codec.CBOR.Write qualified as CBOR
import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Trans.Class (lift)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Char (intToDigit)
import Data.Either.Combinators (mapLeft)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.List (find)
import Data.Maybe (catMaybes, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as UTF8
import Data.Word (Word64)
import System.Directory (canonicalizePath, pathIsSymbolicLink)
import System.FilePath (isAbsolute, (</>))
import System.IO (IOMode (ReadMode), withBinaryFile)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativeParentPhysicalRead qualified as Physical
import JitML.Checkpoint.NativeParentPolicyData qualified as Policy
import JitML.Checkpoint.NativeParentPolicyData.Lineage qualified as Lineage
import JitML.Checkpoint.NativePhase.Codec qualified as Phase
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
  ( NodeValue (VRef)
  , Resource (PathTextBytes)
  , boundedLength
  , nativePhaseLimit
  )
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Env.Env (App)
import JitML.Execution.NativeParentAttemptRetention qualified as Attempt
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.CriterionReview qualified as Review
import JitML.Product.CriterionReviewData qualified as ReviewData
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeParentEvaluationReplay qualified as Evaluation
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlProducer.Inventory qualified as Inventory
import JitML.Product.Publisher.SourceAuthority (supervisedQualificationSourceEnvironment)
import JitML.Product.SourceDigest qualified as Source
import JitML.Sub.Outcome qualified as Outcome
import JitML.Sub.Stream qualified as Stream
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Training.Budget qualified as Training

-- These fields are ordinary checked DATA. The Report caller must additionally
-- bind this exact request to its actual private chronological precondition.
data NativeParentExecutionRequest = NativeParentExecutionRequest
  { nativeParentRequestSourceRoot :: !FilePath
  , nativeParentRequestSource :: !Source.SourceStamp
  , nativeParentRequestWorkdir :: !FilePath
  , nativeParentRequestPinnedExecutable :: !FilePath
  , nativeParentRequestInvocation :: !Training.ProductScenarioInvocation
  }
  deriving stock (Eq, Show)
data NativeParentExecutableFileData = NativeParentExecutableFileData
  { parentExecutableFilePath :: !FilePath
  , parentExecutableFileSha256 :: !Text
  , parentExecutableFileBytes :: !Word64
  }
  deriving stock (Eq, Show)
data NativeParentExecutionStage
  = ParentExecutionInput
  | ParentExecutionIdentity
  | ParentExecutionBefore
  | ParentExecutionReserve
  | ParentExecutionRetain
  | ParentExecutionLaunch
  | ParentExecutionAfterChild
  | ParentExecutionReference
  | ParentExecutionPhysical
  | ParentExecutionBinding
  | ParentExecutionPolicy
  | ParentExecutionEvaluation
  | ParentExecutionAfterParent
  | ParentExecutionFinished
  deriving stock (Eq, Show)
data NativeParentExecutionReport = NativeParentExecutionReport
  { parentExecutionStage :: !NativeParentExecutionStage
  , parentExecutionRequest :: !(Maybe NativeParentExecutionRequest)
  , parentExecutionCriterionReview :: !(Maybe ReviewData.CriterionReviewIdentityData)
  , parentExecutionAllocationKey :: !(Maybe Text)
  , parentExecutionSourceBefore :: !(Maybe Source.SourceStamp)
  , parentExecutionSourceAfterChild :: !(Maybe Source.SourceStamp)
  , parentExecutionSourceAfterParent :: !(Maybe Source.SourceStamp)
  , parentExecutionExecutableBefore :: !(Maybe NativeParentExecutableFileData)
  , parentExecutionExecutableAfterChild :: !(Maybe NativeParentExecutableFileData)
  , parentExecutionExecutableAfterParent :: !(Maybe NativeParentExecutableFileData)
  , parentExecutionProcessBefore :: !(Maybe Process.RecordedProducerObservation)
  , parentExecutionProcessAfter :: !(Maybe Process.RecordedProducerObservation)
  , parentExecutionAttemptDirectory :: !(Maybe FilePath)
  , parentExecutionAttemptIssued :: !(Maybe Attempt.NativeParentAttemptFileData)
  , parentExecutionAttemptInventory :: !(Maybe Attempt.NativeParentAttemptInventory)
  , parentExecutionAttemptFailure :: !(Maybe Attempt.NativeParentAttemptFailure)
  , parentExecutionActualSpawn :: !(Maybe Stream.NativeProcessSpawnResult)
  , parentExecutionLaunchDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  , parentExecutionPointerAfterChild :: !(Maybe Text)
  , parentExecutionPointerAfterParent :: !(Maybe Text)
  , parentExecutionReference :: !(Maybe Reference.NativeQualificationReference)
  , parentExecutionPhysical :: !(Maybe Physical.NativeParentReadReport)
  , parentExecutionPolicyFailure :: !(Maybe Policy.NativeParentPolicyFailure)
  , parentExecutionEvaluation :: !(Maybe Evaluation.NativeParentEvaluationReport)
  , parentExecutionRefusal :: !(Maybe Text)
  , parentExecutionDiagnostic :: !(Maybe Failure.NativeDiagnosticData)
  }
  deriving stock (Eq, Show)
data NativeParentExecutedCohort
  = NativeParentExecutedCohort
      !NativeParentExecutionRequest
      !Reference.NativeQualificationReference
      !Physical.NativeParentPhysicalPayloads
      !Evaluation.NativeParentEvaluatedCohort
      !NativeParentExecutionReport
      !NativeParentExecutionCertificate
newtype NativeParentExecutionFailure = NativeParentExecutionFailure NativeParentExecutionReport

-- Compact, privately IO-created inspection certificate for Report to attach
-- to its OWN precondition. It has no parser/ordinary admission-pair factory.
-- It is not an authenticated journal or loaded-source/build observation.
data NativeParentExecutionCertificate
  = NativeParentExecutionCertificate
      !NativeParentExecutionRequest
      !Reference.NativeQualificationReference
      !Store.AdmittedExecutionCheckpoint
      !Stream.NativeProcessSpawnObservation
      !Attempt.NativeParentAttemptInventory
      !Text
      !Summary.NativeParentEvaluationSummaryData
      !ReviewData.CriterionReviewIdentityData
  deriving stock (Eq, Show)
nativeParentExecutedCertificate :: NativeParentExecutedCohort -> NativeParentExecutionCertificate
nativeParentExecutedCertificate (NativeParentExecutedCohort _ _ _ _ _ actual) = actual
nativeParentCertificateRequest :: NativeParentExecutionCertificate -> NativeParentExecutionRequest
nativeParentCertificateRequest (NativeParentExecutionCertificate actual _ _ _ _ _ _ _) = actual
nativeParentCertificateReference
  :: NativeParentExecutionCertificate -> Reference.NativeQualificationReference
nativeParentCertificateReference (NativeParentExecutionCertificate _ actual _ _ _ _ _ _) = actual
nativeParentCertificateAdmitted
  :: NativeParentExecutionCertificate -> Store.AdmittedExecutionCheckpoint
nativeParentCertificateAdmitted (NativeParentExecutionCertificate _ _ actual _ _ _ _ _) = actual
nativeParentCertificateSpawn
  :: NativeParentExecutionCertificate -> Stream.NativeProcessSpawnObservation
nativeParentCertificateSpawn (NativeParentExecutionCertificate _ _ _ actual _ _ _ _) = actual
nativeParentCertificateAttemptInventory
  :: NativeParentExecutionCertificate -> Attempt.NativeParentAttemptInventory
nativeParentCertificateAttemptInventory (NativeParentExecutionCertificate _ _ _ _ actual _ _ _) = actual
nativeParentCertificateAttemptScope :: NativeParentExecutionCertificate -> Text
nativeParentCertificateAttemptScope (NativeParentExecutionCertificate _ _ _ _ _ actual _ _) = actual
nativeParentCertificateEvaluationSummary
  :: NativeParentExecutionCertificate -> Summary.NativeParentEvaluationSummaryData
nativeParentCertificateEvaluationSummary (NativeParentExecutionCertificate _ _ _ _ _ _ actual _) = actual
nativeParentCertificateCriterionReview
  :: NativeParentExecutionCertificate -> ReviewData.CriterionReviewIdentityData
nativeParentCertificateCriterionReview (NativeParentExecutionCertificate _ _ _ _ _ _ _ actual) = actual

nativeParentExecutedRequest :: NativeParentExecutedCohort -> NativeParentExecutionRequest
nativeParentExecutedRequest (NativeParentExecutedCohort actual _ _ _ _ _) = actual
nativeParentExecutedReference
  :: NativeParentExecutedCohort -> Reference.NativeQualificationReference
nativeParentExecutedReference (NativeParentExecutedCohort _ actual _ _ _ _) = actual
nativeParentExecutedPhysical :: NativeParentExecutedCohort -> Physical.NativeParentPhysicalPayloads
nativeParentExecutedPhysical (NativeParentExecutedCohort _ _ actual _ _ _) = actual
nativeParentExecutedEvaluations
  :: NativeParentExecutedCohort -> Evaluation.NativeParentEvaluatedCohort
nativeParentExecutedEvaluations (NativeParentExecutedCohort _ _ _ actual _ _) = actual
nativeParentExecutionReport :: NativeParentExecutedCohort -> NativeParentExecutionReport
nativeParentExecutionReport (NativeParentExecutedCohort _ _ _ _ actual _) = actual
nativeParentExecutionFailureReport :: NativeParentExecutionFailure -> NativeParentExecutionReport
nativeParentExecutionFailureReport (NativeParentExecutionFailure actual) = actual

emptyReport :: NativeParentExecutionReport
emptyReport =
  NativeParentExecutionReport
    { parentExecutionStage = ParentExecutionInput
    , parentExecutionRequest = Nothing
    , parentExecutionCriterionReview = Nothing
    , parentExecutionAllocationKey = Nothing
    , parentExecutionSourceBefore = Nothing
    , parentExecutionSourceAfterChild = Nothing
    , parentExecutionSourceAfterParent = Nothing
    , parentExecutionExecutableBefore = Nothing
    , parentExecutionExecutableAfterChild = Nothing
    , parentExecutionExecutableAfterParent = Nothing
    , parentExecutionProcessBefore = Nothing
    , parentExecutionProcessAfter = Nothing
    , parentExecutionAttemptDirectory = Nothing
    , parentExecutionAttemptIssued = Nothing
    , parentExecutionAttemptInventory = Nothing
    , parentExecutionAttemptFailure = Nothing
    , parentExecutionActualSpawn = Nothing
    , parentExecutionLaunchDiagnostic = Nothing
    , parentExecutionPointerAfterChild = Nothing
    , parentExecutionPointerAfterParent = Nothing
    , parentExecutionReference = Nothing
    , parentExecutionPhysical = Nothing
    , parentExecutionPolicyFailure = Nothing
    , parentExecutionEvaluation = Nothing
    , parentExecutionRefusal = Nothing
    , parentExecutionDiagnostic = Nothing
    }
type Program = ExceptT Text App

executeNativeParentCohort
  :: Cohort.NativeRlCohortBatch
  -> NativeParentExecutionRequest
  -> App (Either NativeParentExecutionFailure NativeParentExecutedCohort)
-- Historical unreviewed entry: preserves signature but cannot satisfy a current review-bound run.
executeNativeParentCohort = executeNativeParentCohortForReview ""

executeNativeParentCohortForReview
  :: Text
  -> Cohort.NativeRlCohortBatch
  -> NativeParentExecutionRequest
  -> App (Either NativeParentExecutionFailure NativeParentExecutedCohort)
executeNativeParentCohortForReview expectedContracts batch request = do
  env <- ask
  liftIO $ do
    report <- newIORef emptyReport
    reservation <- newIORef Nothing
    attempted <-
      tryAny (runReaderT (runExceptT (program expectedContracts report reservation batch request)) env)
    completed <- case attempted of
      Left exception -> do
        diagnostic <- Failure.captureNativeExceptionDiagnostic exception
        modifyIORef'
          report
          ( \actual ->
              actual
                { parentExecutionRefusal = Just "synchronous actual native parent execution failure"
                , parentExecutionDiagnostic = Just diagnostic
                }
          )
        pure Nothing
      Right (Left reason) -> do
        diagnostic <- Failure.captureNativeDiagnostic reason
        modifyIORef'
          report
          ( \actual ->
              actual
                { parentExecutionRefusal = Just reason
                , parentExecutionDiagnostic = case parentExecutionDiagnostic actual of
                    Nothing -> Just diagnostic
                    Just original -> Just original
                }
          )
        pure Nothing
      Right (Right actual) -> pure (Just actual)
    reserved <- readIORef reservation
    retained <- case reserved of
      Nothing -> pure Nothing
      Just owned -> do
        -- Persist a pre-retention report snapshot; its later inventory cannot
        -- include its own hash. Exact raw capture is independent of Text.
        modifyIORef'
          report
          ( \actual ->
              actual
                { parentExecutionStage = case completed of
                    Just _ -> ParentExecutionRetain
                    Nothing -> parentExecutionStage actual
                }
          )
        snapshot <- readIORef report
        let raw =
              (\actual -> (Stream.nativeSpawnResultStdoutBytes actual, Stream.nativeSpawnResultStderrBytes actual))
                <$> parentExecutionActualSpawn snapshot
        saved <- Attempt.retainNativeParentAttemptResult owned (show snapshot) raw
        case saved of
          Left failure -> do
            modifyIORef'
              report
              ( \actual ->
                  actual
                    { parentExecutionAttemptFailure = Just failure
                    , parentExecutionRefusal = case parentExecutionRefusal actual of
                        Nothing -> Just "actual parent result retention refused"
                        Just original -> Just original
                    }
              )
            pure Nothing
          Right actual -> do
            modifyIORef'
              report
              ( \value ->
                  value {parentExecutionAttemptInventory = Just (Attempt.retainedNativeParentAttemptInventory actual)}
              )
            pure (Just actual)
    case (completed, retained) of
      (Just (reference, physical, evaluated, spawn, summary, review), Just saved) -> do
        modifyIORef' report (\value -> value {parentExecutionStage = ParentExecutionFinished})
        actual <- readIORef report
        let certificate =
              NativeParentExecutionCertificate
                request
                reference
                (Evaluation.nativeParentEvaluatedCheckpoint evaluated)
                spawn
                (Attempt.retainedNativeParentAttemptInventory saved)
                (Attempt.reservedNativeParentAttemptScopeSha256 (Attempt.retainedNativeParentAttemptReserved saved))
                summary
                review
        pure (Right (NativeParentExecutedCohort request reference physical evaluated actual certificate))
      _ -> Left . NativeParentExecutionFailure <$> readIORef report

program
  :: Text
  -> IORef NativeParentExecutionReport
  -> IORef (Maybe Attempt.ReservedNativeParentAttempt)
  -> Cohort.NativeRlCohortBatch
  -> NativeParentExecutionRequest
  -> Program
       ( Reference.NativeQualificationReference
       , Physical.NativeParentPhysicalPayloads
       , Evaluation.NativeParentEvaluatedCohort
       , Stream.NativeProcessSpawnObservation
       , Summary.NativeParentEvaluationSummaryData
       , ReviewData.CriterionReviewIdentityData
       )
program expectedContracts report reservation batch request = do
  _ <- liftIO (evaluate request)
  _ <- liftIO (evaluate batch)
  update report (\actual -> actual {parentExecutionRequest = Just request})
  stage report ParentExecutionIdentity
  checkedBatch <-
    checked
      ( Cohort.refineNativeRlCohortBatch
          (Cohort.nativeRlCohortBatchSubstrate batch)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  require
    (checkedBatch == batch)
    "actual parent requires the complete current canonical native lane batch"
  let invocation = nativeParentRequestInvocation request
      row = Training.productScenarioInvocationRowId invocation
      source = nativeParentRequestSource request
      workdir = nativeParentRequestWorkdir request
      sourceRoot = nativeParentRequestSourceRoot request
      executable = nativeParentRequestPinnedExecutable request
      executableSha = Training.productScenarioInvocationExecutableSha256 invocation
  _ <- codec (Context.digestFromCanonicalText executableSha)
  _ <- codec (Context.digestFromCanonicalText (Source.stampSha256 source))
  require
    (Source.stampAlgorithm source == Source.sourceDigestAlgorithm)
    "actual parent source algorithm differs"
  cohort <-
    maybe
      (throwError "actual parent invocation row is absent from full canonical batch")
      pure
      ( find
          ((== row) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  let singleton = Cohort.nativeRlSeedPlanSingleton (Cohort.nativeRlCohortServingChild cohort)
      experiment = Singleton.nativeSingletonExperiment singleton
      checkpointRoot = workdir </> ".build" </> "checkpoints"
  require
    ( Training.productScenarioInvocationSubstrate invocation == Cohort.nativeRlCohortBatchSubstrate batch
        && Training.productScenarioInvocationPlanId invocation == Singleton.nativeSingletonPlanId singleton
    )
    "actual parent original invocation differs from current serving lane or whole PlanId"
  mapM_ canonical [sourceRoot, workdir, executable]
  actualRoot <- lift Writer.localCheckpointRoot
  canonicalRoot <- liftIO (canonicalizePath actualRoot)
  require
    (canonicalRoot == checkpointRoot)
    "actual parent Env cache differs from owned canonical child checkpoint root"
  address <-
    checked
      ( Retain.mkNativeAllocationAddress
          ( Retain.NativeAllocationScope
              (Retain.NativeSuppliedScenarioDigest (Training.productScenarioInvocationDigest invocation))
              row
              source
              (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
              (Training.productScenarioInvocationDigest invocation)
          )
      )
  update
    report
    (\actual -> actual {parentExecutionAllocationKey = Just (Retain.nativeAllocationAddressKey address)})

  _ <- codec (Context.digestFromCanonicalText expectedContracts)
  capturedReview <-
    liftIO
      ( Review.captureCriterionReviewIn
          sourceRoot
          source
          (Cohort.nativeRlCohortBatchSubstrate batch)
          ReviewData.NativeCriterionReview
      )
      >>= checked . mapLeft Review.renderCriterionReviewError
  let review = Review.capturedCriterionReviewIdentity capturedReview
  require
    (ReviewData.criterionReviewContractSetSha256 review == expectedContracts)
    "prelaunch native review differs from actual parent expected full55 contracts"
  reviewBytes <- checked (ReviewData.encodeCriterionReviewIdentityData review)
  update report (\actual -> actual {parentExecutionCriterionReview = Just review})

  stage report ParentExecutionReserve
  reservedResult <-
    liftIO
      ( Attempt.reserveNativeParentAttempt
          workdir
          invocation
          (issuedRecord cohort request (Retain.nativeAllocationAddressKey address) reviewBytes)
      )
  reserved <- case reservedResult of
    Left failure -> do
      update report (\actual -> actual {parentExecutionAttemptFailure = Just failure})
      throwError "actual parent fixed run/row/lane attempt reservation refused"
    Right actual -> pure actual
  liftIO (writeIORef reservation (Just reserved))
  update
    report
    ( \actual ->
        actual
          { parentExecutionAttemptDirectory = Just (Attempt.reservedNativeParentAttemptDirectory reserved)
          , parentExecutionAttemptIssued = Just (Attempt.reservedNativeParentAttemptIssued reserved)
          }
    )

  stage report ParentExecutionBefore
  sourceBefore <- sourceObservation sourceRoot
  pinBefore <- pinObservation executable
  processBefore <- processObservation
  update
    report
    ( \actual ->
        actual
          { parentExecutionSourceBefore = Just sourceBefore
          , parentExecutionExecutableBefore = Just pinBefore
          , parentExecutionProcessBefore = Just (Process.recordedProducerObservation processBefore)
          }
    )
  require
    ( sourceBefore == source
        && parentExecutableFileSha256 pinBefore == executableSha
        && parentExecutableFileBytes pinBefore > 0
    )
    "actual parent source or pinned executable FILE identity differs from the exact expected generation"
  initialPointer <- pointer checkpointRoot experiment
  require
    (isNothing initialPointer)
    "actual parent child latest pointer already exists before owned launch"
  let arguments = case Cohort.nativeRlCohortPlanProjection cohort of
        Matrix.SomeProductProjection _ projection -> Matrix.productProjectionCommand projection
      command = (subprocess executable arguments) {subprocessWorkingDirectory = Just workdir}
      overrides =
        [ ("JITML_PRODUCT_SCENARIO_INVOCATION", Training.renderProductScenarioInvocation invocation)
        , (Text.pack supervisedQualificationSourceEnvironment, Source.stampSha256 source)
        ]
      removals =
        [ "JITML_PRODUCT_SCENARIO_JOURNAL_KEY_FILE"
        , "JITML_PRODUCT_SCENARIO_JOURNAL_PATH"
        , "JITML_PRODUCT_SCENARIO_RUN_ID"
        , "JITML_PRODUCT_SCENARIO_EXECUTABLE"
        , "JITML_PRODUCT_SCENARIO_EXECUTABLE_SHA256"
        ]
      environment = Stream.subprocessEnvOverrideAndRemove overrides removals
  stage report ParentExecutionLaunch
  launched <- liftIO (tryAny (Stream.runStreamingWithSpawnObservation environment command))
  case launched of
    Right actual -> update report (\value -> value {parentExecutionActualSpawn = Just actual})
    Left exception -> do
      diagnostic <- liftIO (Failure.captureNativeExceptionDiagnostic exception)
      update
        report
        ( \actual ->
            actual
              { parentExecutionLaunchDiagnostic = Just diagnostic
              , parentExecutionDiagnostic = Just diagnostic
              }
        )
  -- Observe these even after a synchronous launch/capture exception or real
  -- nonzero exit. No status/stream/PID is invented for unavailable capture.
  stage report ParentExecutionAfterChild
  sourceAfterChild <- sourceObservation sourceRoot
  pinAfterChild <- pinObservation executable
  update
    report
    ( \actual ->
        actual
          { parentExecutionSourceAfterChild = Just sourceAfterChild
          , parentExecutionExecutableAfterChild = Just pinAfterChild
          }
    )
  require
    (sourceAfterChild == sourceBefore && pinAfterChild == pinBefore)
    "actual parent source or pinned executable FILE identity changed during owned child"
  spawned <-
    either
      (const (throwError "actual owned child launch or capture raised a synchronous exception"))
      pure
      launched
  spawn <-
    maybe
      (throwError "actual owned child supplied no process-handle PID observation")
      pure
      (Stream.nativeSpawnResultObservation spawned)
  require
    ( Stream.nativeSpawnExecutablePath spawn == executable
        && Stream.nativeSpawnArguments spawn == arguments
        && Stream.nativeSpawnWorkingDirectory spawn == Just workdir
        && Stream.nativeSpawnEnvironmentRemovals spawn == removals
        && Stream.nativeSpawnEnvironmentOverrideNames spawn == map fst overrides
    )
    "actual owned native child launch configuration differs"
  require
    (Stream.nativeSpawnParentProcessId spawn == Process.producerProcessId processBefore)
    "actual owned native child was not launched by the independently observed parent process"
  transcript <- case Stream.nativeSpawnResultOutcome spawned of
    Outcome.ProcessSucceeded actual -> pure actual
    Outcome.ProcessFailed _ -> throwError "actual native child returned a genuine nonzero process outcome"
  stage report ParentExecutionReference
  reference <- checked (parseReference (Outcome.processTranscriptStdout transcript))
  update report (\actual -> actual {parentExecutionReference = Just reference})
  let raw = Reference.nativeQualificationReferenceData reference
  require
    (Reference.nativeReferenceAllocationKey raw == Retain.nativeAllocationAddressKey address)
    "actual child receipt allocation differs from original parent-issued fixed invocation slot"
  manifest <-
    pointer checkpointRoot experiment
      >>= maybe (throwError "actual owned native child published no latest pointer") pure
  update report (\actual -> actual {parentExecutionPointerAfterChild = Just manifest})
  require
    (Reference.nativeReferenceManifest raw == manifest)
    "actual child reference differs from exact observed latest manifest"

  stage report ParentExecutionPhysical
  physicalResult <- lift (Physical.readNativeParentQualificationPayloads workdir reference)
  physical <- case physicalResult of
    Left failure -> do
      update
        report
        (\actual -> actual {parentExecutionPhysical = Just (Physical.nativeParentReadFailureReport failure)})
      throwError "actual parent local/configured-remote full acquisition or checkpoint admission refused"
    Right actual -> do
      update
        report
        (\value -> value {parentExecutionPhysical = Just (Physical.nativeParentPhysicalReport actual)})
      pure actual
  let admitted = Physical.nativeParentPhysicalAdmitted physical
      completed = Store.admittedExecutionCompletedTraining admitted
      expected =
        Binding.NativeParentExpectedData
          source
          executableSha
          invocation
          manifest
          (Training.encodeCompletedTraining completed)
  stage report ParentExecutionBinding
  binding <-
    checked
      ( Binding.checkNativeParentBindingData
          batch
          row
          expected
          reference
          (Physical.nativeParentPhysicalPayloads physical)
      )
  checked
    ( checkActualProducerBindings
        pinBefore
        spawn
        (Process.recordedProducerObservation processBefore)
        binding
    )
  executableDigest <- codec (Context.digestFromCanonicalText executableSha)
  let numericalExpected =
        Policy.NativeParentExpectations
          source
          executableDigest
          (Context.SuppliedScenarioContext invocation)
          (Context.NativeContextSources Nothing (Just source))
          (Stream.nativeSpawnProcessId spawn, Stream.nativeSpawnParentProcessId spawn)
  stage report ParentExecutionPolicy
  policyResult <- liftIO (Policy.verifyNativeParentPolicyData batch numericalExpected binding)
  policy <- case policyResult of
    Left failure -> do
      update report (\actual -> actual {parentExecutionPolicyFailure = Just failure})
      throwError "actual parent recorded policy/lineage/mathematical cohort verification refused"
    Right actual -> pure actual
  checked
    ( checkDedicatedArsProducerBindings
        pinBefore
        spawn
        (Process.recordedProducerObservation processBefore)
        policy
    )
  stage report ParentExecutionEvaluation
  evaluationResult <- lift (Evaluation.replayNativeParentPolicyEvaluations policy admitted)
  evaluated <- case evaluationResult of
    Left failure -> do
      update
        report
        ( \actual ->
            actual {parentExecutionEvaluation = Just (Evaluation.nativeParentEvaluationFailureReport failure)}
        )
      throwError "actual parent selected-device and physical serving replay refused"
    Right actual -> do
      update
        report
        (\value -> value {parentExecutionEvaluation = Just (Evaluation.nativeParentEvaluationReport actual)})
      pure actual
  summary <- checked (evaluationSummary evaluated)
  stage report ParentExecutionAfterParent
  sourceAfterParent <- sourceObservation sourceRoot
  pinAfterParent <- pinObservation executable
  processAfter <- processObservation
  manifestAfterParent <- pointer checkpointRoot experiment
  update
    report
    ( \actual ->
        actual
          { parentExecutionSourceAfterParent = Just sourceAfterParent
          , parentExecutionExecutableAfterParent = Just pinAfterParent
          , parentExecutionProcessAfter = Just (Process.recordedProducerObservation processAfter)
          , parentExecutionPointerAfterParent = manifestAfterParent
          }
    )
  either
    (const (throwError "actual parent process FILE/kernel/build identity changed during full validation"))
    pure
    (Process.compareProducerProcessObservations processBefore processAfter)
  require
    ( sourceAfterParent == sourceBefore
        && pinAfterParent == pinBefore
        && manifestAfterParent == Just manifest
    )
    "actual parent source, pin or exact latest pointer changed during full parent validation"
  stage report ParentExecutionFinished
  reviewAfter <-
    liftIO
      ( Review.captureCriterionReviewIn
          sourceRoot
          source
          (Cohort.nativeRlCohortBatchSubstrate batch)
          ReviewData.NativeCriterionReview
      )
      >>= checked . mapLeft Review.renderCriterionReviewError
  require
    (Review.capturedCriterionReviewIdentity reviewAfter == review)
    "selected criterion review FILE identity changed during owned execution"
  pure (reference, physical, evaluated, spawn, summary, review)

-- A compact ordinary summary is projected only from the actual evaluated
-- success, before terminal report retention and certificate construction.
-- Neither a parsed summary nor an authenticated historical receipt can create
-- this original owned-execution certificate.
evaluationSummary
  :: Evaluation.NativeParentEvaluatedCohort -> Either Text Summary.NativeParentEvaluationSummaryData
evaluationSummary evaluated = do
  let actual = Evaluation.nativeParentEvaluationReport evaluated
  requireData
    ( Evaluation.parentEvaluationStage actual == Evaluation.ParentEvaluationFinished
        && isNothing (Evaluation.parentEvaluationRefusal actual)
        && isNothing (Evaluation.parentEvaluationDiagnostic actual)
    )
    "actual parent evaluation summary requires a complete successful report"
  reference <- case Evaluation.parentEvaluationArenaReferenceStatus actual of
    Evaluation.ParentReferenceNotApplicable -> Right Nothing
    Evaluation.ParentReferenceMatched root -> Right (Just root)
    Evaluation.ParentReferenceNotChecked -> Left "actual parent evaluation summary lacks its reference check"
  matches <- traverse match (Evaluation.parentEvaluationItems actual)
  mapLeft
    (Text.pack . show)
    ( Summary.refineNativeParentEvaluationSummaryData
        (Summary.NativeParentEvaluationSummaryData reference matches)
    )
 where
  match actual = do
    requireData
      (Evaluation.parentEvaluationStatus actual == Evaluation.ParentEvaluationMatched)
      "actual parent evaluation summary contains a nonmatched item"
    root <- case Evaluation.parentEvaluationActualCapture actual of
      Just (Evaluation.NativeParentEvaluationCapture captured _) -> Right captured
      Nothing -> Left "actual parent evaluation summary has no actual canonical capture"
    device <- case Evaluation.parentEvaluationDevice actual of
      Evaluation.ParentEvaluationHostNoMlp -> Right Nothing
      Evaluation.ParentEvaluationDeviceObserved witness -> Right (Just (Witness.deviceExecutionWitnessToRaw witness))
      _ -> Left "actual parent evaluation summary has no actual selected device or host observation"
    pure
      ( Summary.NativeParentEvaluationMatchData
          (fromIntegral (Evaluation.parentEvaluationOrdinal actual))
          (Evaluation.parentEvaluationExpectedStage actual)
          (fromIntegral (Evaluation.parentEvaluationExpectedIndex actual))
          (Evaluation.parentEvaluationExpectedRoot actual)
          root
          device
      )

-- Expected path/count/PID/runtime fields come from this parent's actual FILE,
-- process and owned typed-process observations, never from the child record.
-- These comparisons remain DATA checks and cannot restore an observation.
checkActualProducerBindings
  :: NativeParentExecutableFileData
  -> Stream.NativeProcessSpawnObservation
  -> Process.RecordedProducerObservation
  -> Binding.NativeParentBindingData
  -> Either Text ()
checkActualProducerBindings pinned spawn parent binding = do
  let acquisition = Binding.nativeParentBindingAcquisition binding
      allocation = Acquisition.acquisitionAllocation acquisition
      phaseRecords =
        concatMap
          (map snd . Acquisition.acquisitionChildPhases)
          (Acquisition.acquisitionChildren acquisition)
  original <-
    fromCodec
      ( Lineage.decodeProducerBundle
          (Inventory.allocationProducerPool allocation)
          (Inventory.allocationProducerRoot allocation)
      )
  requireData
    (case original of (Just _, Nothing) -> True; _ -> False)
    "actual parent allocation lacks its exact original before-only producer bundle"
  mapM_ check (present original)
  mapM_
    ( \phase -> do
        producer <- case reverse (Schema.contextFields (Phase.phaseDataContext phase)) of
          VRef actual : _ -> Right actual
          _ -> Left "actual parent phase has no producer reference"
        records <- fromCodec (Lineage.decodeProducerBundle (Phase.phaseDataPool phase) producer)
        mapM_ check (present records)
    )
    phaseRecords
 where
  fromCodec = mapLeft (Text.pack . show)
  present (before, after) = catMaybes [before, after]
  check = checkActualRecordedProducerBinding pinned spawn parent

-- Dedicated ARS begun/origin bundles are distinct from typed phase contexts.
-- Check every original child's before AND optional after through the SAME
-- actual parent FILE/process/runtime comparison, including auxiliary runs.
checkDedicatedArsProducerBindings
  :: NativeParentExecutableFileData
  -> Stream.NativeProcessSpawnObservation
  -> Process.RecordedProducerObservation
  -> Policy.NativeParentPolicyData
  -> Either Text ()
checkDedicatedArsProducerBindings pinned spawn parent policy = mapM_ child (Policy.nativeParentPolicyChildren policy)
 where
  child (Policy.NativeParentReturnChild _ _ _ _ _ _ lineages) = mapM_ lineage lineages
  child _ = Right ()
  lineage actual =
    mapM_
      (checkActualRecordedProducerBinding pinned spawn parent)
      (Lineage.nativeLineageBefore actual : catMaybes [Lineage.nativeLineageAfter actual])

checkActualRecordedProducerBinding
  :: NativeParentExecutableFileData
  -> Stream.NativeProcessSpawnObservation
  -> Process.RecordedProducerObservation
  -> Process.RecordedProducerObservation
  -> Either Text ()
checkActualRecordedProducerBinding pinned spawn parent actual =
  requireData
    ( Process.recordedExecutableFilePath actual == parentExecutableFilePath pinned
        && Process.recordedExecutableFileSha256 actual == parentExecutableFileSha256 pinned
        && Process.recordedExecutableFileByteCount actual == parentExecutableFileBytes pinned
        && Process.recordedProcessId actual == Stream.nativeSpawnProcessId spawn
        && Process.recordedParentProcessId actual == Stream.nativeSpawnParentProcessId spawn
        && Process.recordedKernelOperatingSystem actual == Process.recordedKernelOperatingSystem parent
        && Process.recordedKernelMachine actual == Process.recordedKernelMachine parent
        && Process.recordedKernelRelease actual == Process.recordedKernelRelease parent
        && Process.recordedBuildOperatingSystem actual == Process.recordedBuildOperatingSystem parent
        && Process.recordedBuildArchitecture actual == Process.recordedBuildArchitecture parent
        && Process.recordedBuildCompiler actual == Process.recordedBuildCompiler parent
        && Process.recordedBuildCompilerVersion actual == Process.recordedBuildCompilerVersion parent
        && isNothing (Process.recordedObservedSource actual)
    )
    "original child producer FILE/path/count/PID/kernel/build/source role differs from actual parent-owned observations"

processObservation :: Program Process.ObservedProducerProcess
processObservation = do
  actual <- liftIO (Process.observeProducerProcess Process.NoSourceObservation)
  either (const (throwError "actual native parent process observation failed")) pure actual

-- Strict one native reference; malformed/duplicate/foreign qualification lines
-- cannot silently supply a different alternative. Ordinary parsing grants no
-- execution or authentication capability by itself.
parseReference :: Text -> Either Text Reference.NativeQualificationReference
parseReference stdout = do
  requireData
    ( null
        [ line
        | line <- Text.lines stdout
        , "product-supervised-qualification-" `Text.isPrefixOf` Text.stripStart line
        ]
    )
    "native child emitted a foreign supervised qualification line"
  case [line | line <- Text.lines stdout, "native-qualification" `Text.isPrefixOf` Text.stripStart line] of
    [line] ->
      either
        (const (Left "native child qualification line is not exact canonical reference DATA"))
        Right
        (Reference.parseNativeQualificationReference line)
    _ -> Left "native child must emit exactly one strict native qualification reference"

sourceObservation :: FilePath -> Program Source.SourceStamp
sourceObservation root = liftIO (Source.computeSourceStampIn root) >>= checked
canonical :: FilePath -> Program ()
canonical path = do
  _ <- codec (boundedLength PathTextBytes (nativePhaseLimit PathTextBytes) path)
  require
    ( toInteger (BS.length (UTF8.encodeUtf8 (Text.pack path))) <= nativePhaseLimit PathTextBytes
        && '\0' `notElem` path
    )
    "actual native parent path exceeds its UTF8 byte bound or contains NUL"
  require (isAbsolute path) "actual native parent path is not absolute"
  actual <- liftIO (canonicalizePath path)
  require (actual == path) "actual native parent path is not physically canonical"

-- Canonical issued DATA describes the ORIGINAL request/configuration. It is
-- written before source/pin reads or launch, not inferred from a result.
issuedRecord
  :: Cohort.NativeRlCohortPlan -> NativeParentExecutionRequest -> Text -> BS.ByteString -> BS.ByteString
issuedRecord cohort request allocationKey reviewBytes =
  LBS.toStrict
    ( CBOR.toLazyByteString
        ( CBOR.encodeListLen 13
            <> CBOR.encodeString "jitml-native-parent-issued-request-v2"
            <> CBOR.encodeWord 2
            <> CBOR.encodeString (Text.pack (nativeParentRequestSourceRoot request))
            <> CBOR.encodeString (Text.pack (nativeParentRequestWorkdir request))
            <> CBOR.encodeString (Text.pack (nativeParentRequestPinnedExecutable request))
            <> CBOR.encodeWord64 (Source.stampAlgorithm (nativeParentRequestSource request))
            <> CBOR.encodeString (Source.stampSha256 (nativeParentRequestSource request))
            <> CBOR.encodeString (Training.renderProductScenarioInvocation (nativeParentRequestInvocation request))
            <> CBOR.encodeString (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
            <> CBOR.encodeString allocationKey
            <> CBOR.encodeString "supplied-source-only"
            <> CBOR.encodeBytes reviewBytes
            <> case Cohort.nativeRlCohortPlanProjection cohort of
              Matrix.SomeProductProjection _ projection ->
                let arguments = Matrix.productProjectionCommand projection
                 in CBOR.encodeListLen (fromIntegral (length arguments)) <> foldMap CBOR.encodeString arguments
        )
    )
pointer :: FilePath -> Text -> Program (Maybe Text)
pointer root experiment = liftIO (Store.readCheckpointPointer root (Format.latestPointerKey experiment)) >>= checked

-- Chunked FILE observation only, with a separate operational1GiB cap. It is
-- not an atomic inode or loaded-image observation. No caller size is trusted.
pinObservation :: FilePath -> Program NativeParentExecutableFileData
pinObservation path = do
  symbolic <- liftIO (pathIsSymbolicLink path)
  require (not symbolic) "actual parent pinned executable is a symbolic link"
  canonical path
  (digest, count) <- liftIO (withBinaryFile path ReadMode (loop SHA256.init 0))
  pure (NativeParentExecutableFileData path digest count)
 where
  loop !context !count handle = do
    chunk <- BS.hGetSome handle 65536
    if BS.null chunk
      then pure (hex (SHA256.finalize context), fromInteger count)
      else do
        let next = count + toInteger (BS.length chunk)
        if next > 1024 * 1024 * 1024
          then ioError (userError "actual parent executable exceeds separate1GiB FILE observation cap")
          else loop (SHA256.update context chunk) next handle
  hex =
    Text.pack
      . concatMap
        (\octet -> [intToDigit (fromIntegral octet `div` 16), intToDigit (fromIntegral octet `mod` 16)])
      . BS.unpack

stage :: IORef NativeParentExecutionReport -> NativeParentExecutionStage -> Program ()
stage report value = update report (\actual -> actual {parentExecutionStage = value})
update
  :: IORef NativeParentExecutionReport
  -> (NativeParentExecutionReport -> NativeParentExecutionReport)
  -> Program ()
update report = liftIO . modifyIORef' report
require :: Bool -> Text -> Program ()
require condition reason = unless condition (throwError reason)
requireData :: Bool -> Text -> Either Text ()
requireData condition reason = unless condition (Left reason)
checked :: Either Text a -> Program a
checked = either throwError pure
codec :: (Show e) => Either e a -> Program a
codec = checked . mapLeft (Text.pack . show)
