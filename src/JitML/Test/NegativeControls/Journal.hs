{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 281 — storage and completion journals that omit, substitute, or
-- mismatch the opaque Store-admitted artifact identity.
--
-- The only route from a stored artifact to completion evidence is Store
-- admission ("JitML.Checkpoint.Store"); the only route from admitted evidence
-- to a report is "JitML.Test.Report"; and the only route from a persisted
-- journal back to a report is the production reader in
-- "JitML.Test.ProductScenarioJournal", which re-enters that admission for every
-- row.  These controls perturb the inputs to those boundaries and call the
-- production functions, asserting the specific rejection.  Where its payloads
-- are stable the whole rejection is compared; where a payload is incidental
-- (a derived digest or identity, a temporary path, a rendered I/O error) the
-- control pins the constructor name(s) or a message fragment that names the
-- guard ('singleJournalError' also requires it to be the only error
-- reported).  None of them re-implements an admission check: a journal is
-- written by the production writer from Store-admitted evidence, then
-- corrupted on disk (or the Store beneath it is), and read back by the
-- production reader.
--
-- Two kinds of journal corruption are modelled, because they are rejected by
-- different layers:
--
-- * an /unsigned/ rewrite, made by a party without the journal key, must fail
--   HMAC authentication before anything else is looked at;
-- * a /re-signed/ rewrite, made by a holder of the key, gets past
--   authentication and must be rejected by the reader's structural checks or
--   by re-admission through the Store.
--
-- Every re-signed control first proves that re-signing the unmodified journal
-- is still admitted ('resignedIdentityReadable'), so a re-signed control can
-- never degrade into an authentication failure unnoticed.
--
-- A caller-held completion is judged at the pipeline's inference-eligibility
-- gate ('ProductPipeline.markInferenceEligible'): it must be the Store-admitted
-- completion, held under the admitted checkpoint's own experiment.
--
-- The fork-worker journal variants stay in @jitml-unit@; these controls build
-- their journals in-process.
module JitML.Test.NegativeControls.Journal
  ( journalBaselineFailures
  , journalControls
  )
where

import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isSpace)
import Data.Either (lefts)
import Data.Functor (void)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)

import JitML.Checkpoint.Format qualified as Checkpoint
import JitML.Checkpoint.Store qualified as CheckpointStore
import JitML.Checkpoint.WeightCodec qualified as WeightCodec
import JitML.Plan.Plan (Validation (..), planIdText)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Product.Pipeline qualified as ProductPipeline
import JitML.Substrate (Substrate (..))
import JitML.Test.ContractFixtures
import JitML.Test.ControlFixtures (validCompletedTraining)
import JitML.Test.JournalFixtures
import JitML.Test.NegativeControls.Core
import JitML.Test.ProductLaneJournal qualified as ProductLaneJournal
import JitML.Test.ProductScenarioJournal qualified as ProductScenarioJournal
import JitML.Test.Report qualified as Report
import JitML.Training.Budget qualified as TrainingBudget

-- | Every journal control, grouped by the boundary it exercises.
journalControls :: [NegativeControl]
journalControls =
  storeControls
    <> admissionControls
    <> eligibilityControls
    <> readerControls
    <> laneControls

journal :: Text -> Text -> IO ControlOutcome -> NegativeControl
journal = effectfulControl Journal

-- | Whether the journal baseline is itself valid: the production reader admits
-- the unmodified journal, re-signing it changes nothing, and the portable lane
-- journal derived from it is admissible.  A non-empty result means the
-- corrupted-journal controls below could be passing only because their
-- baseline was already broken.
journalBaselineFailures :: IO [Text]
journalBaselineFailures =
  withJournalScenario $ \s -> do
    read' <- readScenarioJournal s
    identity <- resignedIdentityReadable s
    pure $
      [ "the unmodified journal was rejected by the production reader: " <> Text.pack (show errors)
      | Left errors <- [void read']
      ]
        <> lefts [identity]
        <> [ "the unmodified portable lane journal was rejected: " <> Text.pack (show errors)
           | Left errors <-
               [ void
                   ( ProductLaneJournal.admitProductLaneJournal
                       (sha256Hex (laneJournalBytes s))
                       (jsBatch s)
                       (laneJournalBytes s)
                   )
               ]
           ]
        <> lefts
          [ eligibilityBaseline
              (ProductMatrix.productProjectionExperimentHash (jsProjection s))
              (jsAdmitted s)
          ]

-- | A control that needs a full journal scenario.
scenario :: Text -> Text -> (JournalScenario -> IO ControlOutcome) -> NegativeControl
scenario name description body = journal name description (withJournalScenario body)

-- Store boundary ---------------------------------------------------------------

-- | The name of a value's outermost constructor: enough to say which rejection
-- fired without pinning payloads that are themselves derived (digests, plan
-- identities).
constructorName :: (Show value) => value -> Text
constructorName = Text.takeWhile (not . isSpace) . Text.pack . show

storeControls :: [NegativeControl]
storeControls =
  [ journal
      "journal-storage-success-without-admission"
      "an artifact whose storage succeeded but which was never adopted through the latest pointer must not be admitted"
      ( withSystemTempDirectory "jitml-negative-control-candidate" $ \root -> do
          let (manifest, payloads) = candidateSnapshot productRowExperiment
          written <- CheckpointStore.writeCandidateCheckpointSnapshot root manifest payloads
          case written of
            Left err -> pure (fixtureFailed ("candidate write was refused: " <> shown err))
            Right _stored -> do
              admitted <- CheckpointStore.admitLocalLatestCheckpoint root productRowExperiment
              pure $
                rejectedWhere
                  "AdmissionPointerReadFailed at the first pointer read"
                  ( \case
                      CheckpointStore.AdmissionPointerReadFailed "P1" _ -> True
                      _ -> False
                  )
                  admitted
      )
  , journal
      "journal-candidate-checkpoint-is-inspection-only"
      "a candidate admitted at its exact address is inspection-only and must not satisfy completed-checkpoint admission"
      ( withSystemTempDirectory "jitml-negative-control-candidate" $ \root -> do
          let (manifest, payloads) = candidateSnapshot productRowExperiment
          written <- CheckpointStore.writeCandidateCheckpointSnapshot root manifest payloads
          case written of
            Left err -> pure (fixtureFailed ("candidate write was refused: " <> shown err))
            Right stored -> do
              let manifestSha = CheckpointStore.storedManifestSha (CheckpointStore.candidateStoredCheckpoint stored)
              admitted <- CheckpointStore.admitLocalCheckpointAt root productRowExperiment manifestSha
              pure $
                case admitted of
                  Left err -> fixtureFailed ("the candidate could not be admitted by address: " <> shown err)
                  Right checkpoint ->
                    rejectedWith
                      ( CheckpointStore.AdmissionCompletionInvalid
                          "supervised V1 manifest has no exact V2 runtime artifact and is inspection-only"
                      )
                      (CheckpointStore.requireAdmittedCompletedCheckpoint checkpoint)
      )
  , journal
      "journal-candidate-cannot-carry-completion"
      "a caller-held completion must not be smuggled into a candidate snapshot"
      ( withCompletionParts $ \parts root -> do
          written <-
            CheckpointStore.writeCandidateCheckpointSnapshot
              root
              (pcpManifest parts)
              (pcpPayloads parts)
          pure $
            rejectedWith
              (CheckpointStore.CheckpointWriteInvalid "candidate checkpoint cannot contain completed training")
              (void written)
      )
  , journal
      "journal-caller-held-completion-not-bound-to-manifest"
      "a caller-held completion must not be sealed with a manifest that does not carry it"
      ( withCompletionParts $ \parts root -> do
          written <-
            CheckpointStore.writeCompletedCheckpointSnapshot
              root
              (pcpCompleted parts)
              (pcpBaseManifest parts)
              (pcpPayloads parts)
              Nothing
          pure $
            rejectedWith
              ( CheckpointStore.CheckpointWriteInvalid
                  "completed checkpoint manifest does not contain the required completion witness"
              )
              (void written)
      )
  , scenario
      "journal-manifest-planted-under-foreign-row"
      "another row's manifest planted in this row's Store namespace must be refused on exact-address admission"
      ( \s -> do
          plantedSha <- plantedForeignManifestSha s
          admitted <-
            CheckpointStore.admitLocalCheckpointAt
              (jsCheckpointRoot s)
              (ProductMatrix.productProjectionExperimentHash (jsProjection s))
              plantedSha
          pure $
            rejectedWhere
              "AdmissionManifestInvalid reporting an experiment mismatch"
              ( \case
                  CheckpointStore.AdmissionManifestInvalid detail -> "experiment mismatch" `Text.isInfixOf` detail
                  _ -> False
              )
              admitted
      )
  ]
 where
  productRowExperiment = "product-row-mnist-shallow-mlp"
  shown :: (Show value) => value -> Text
  shown = Text.pack . show
  -- A supervised completion's parts, written into a fresh scratch Store.
  withCompletionParts body =
    withSystemTempDirectory "jitml-negative-control-parts" $ \root ->
      withSupervisedProductFixture $ \row problem projection -> do
        parts <- productCompletionParts row problem projection Nothing
        body parts root

-- | A minimal generic candidate snapshot for @experiment@: one weight blob, no
-- completion, no supervised runtime.
candidateSnapshot
  :: Text
  -> (Checkpoint.CheckpointManifest, [(Text, LazyByteString.ByteString)])
candidateSnapshot experiment =
  ( (Checkpoint.emptyManifest "candidate" experiment [tensor]) {Checkpoint.manifestStep = 1}
  , [(Checkpoint.tensorBlobKey tensor, payload)]
  )
 where
  payload = WeightCodec.encodeJmw1 [0.5, 0.25]
  tensor =
    Checkpoint.TensorBlob
      "candidate.weights"
      [2]
      (Checkpoint.blobKey experiment (WeightCodec.jmw1ContentSha payload))

-- Report admission boundary -----------------------------------------------------

admissionControls :: [NegativeControl]
admissionControls =
  [ journal
      "journal-cross-row-admission"
      "one row's Store-admitted completion must not satisfy another row's projection"
      ( withAdmittedProductProjection $ \_root row _projection _precondition _addressed admitted ->
          withDifferentProductProjection row $ \other ->
            pure
              ( rejectedWith
                  crossRowReasons
                  ( first
                      (fmap constructorName . NonEmpty.toList)
                      (void (Report.productScenarioCompletion other admitted))
                  )
              )
      )
  , journal
      "journal-cross-row-admission-names-both-identities"
      "a cross-row rejection must name the projected row's experiment and the admitted row's canonical identity"
      ( withAdmittedProductProjection $ \_root row projection _precondition _addressed admitted ->
          withDifferentProductProjection row $ \other ->
            let expectedExperiment =
                  Report.ProductCompletionExperimentMismatch
                    (ProductMatrix.productProjectionRowId other)
                    (ProductMatrix.productProjectionExperimentHash other)
                    (ProductMatrix.productProjectionExperimentHash projection)
                expectedCanonicalRow =
                  Report.ProductCompletionCanonicalRowMismatch
                    (ProductMatrix.productProjectionRowId other)
                    (ProductMatrix.productProjectionRowId projection)
                    (ProductMatrix.productProjectionExperimentHash projection)
             in pure
                  ( rejectedWhere
                      ( "an experiment mismatch and a canonical-row mismatch: "
                          <> Text.pack (show [expectedExperiment, expectedCanonicalRow])
                      )
                      (\errors -> expectedExperiment `elem` errors && expectedCanonicalRow `elem` errors)
                      (void (Report.productScenarioCompletion other admitted))
                  )
      )
  , journal
      "journal-cross-substrate-admission"
      "a completion admitted for the linux-cpu plan must not satisfy the linux-cuda projection of the same row"
      ( withAdmittedProductProjection $ \_root row projection _precondition _addressed admitted ->
          withProjectedRow LinuxCUDA row $ \cuda ->
            pure $
              rejectedWith
                ( Report.ProductCompletionPlanMismatch
                    (ProductMatrix.productProjectionRowId cuda)
                    (ProductMatrix.productProjectionPlanId cuda)
                    (ProductMatrix.productProjectionPlanId projection)
                    :| [ Report.ProductCompletionManifestPlanMismatch
                           (ProductMatrix.productProjectionRowId cuda)
                           (ProductMatrix.productProjectionPlanId cuda)
                           (Just (ProductMatrix.productProjectionPlanId projection))
                       ]
                )
                (void (Report.productScenarioCompletion cuda admitted))
      )
  , journal
      "journal-stale-invocation-copy"
      "a checkpoint copied from a prior invocation must not satisfy the current invocation"
      ( withSystemTempDirectory "jitml-negative-control-stale" $ \parent ->
          withSupervisedProductFixture $ \row problem projection -> do
            let staleRoot = parent </> "stale-checkpoints"
                currentRoot = parent </> "current-checkpoints"
            createDirectoryIfMissing True staleRoot
            createDirectoryIfMissing True currentRoot
            executableSha <- productScenarioFixtureExecutableSha256
            stalePrecondition <-
              expectRight
                =<< Report.observeProductScenarioPrecondition
                  "negative-control-prior-run"
                  productScenarioFixtureExecutablePath
                  executableSha
                  staleRoot
                  projection
            _stale <-
              persistAndAdmitProductCompletion
                staleRoot
                row
                problem
                projection
                (Report.productScenarioPreconditionInvocation stalePrecondition)
            currentPrecondition <-
              expectRight
                =<< Report.observeProductScenarioPrecondition
                  "negative-control-current-run"
                  productScenarioFixtureExecutablePath
                  executableSha
                  currentRoot
                  projection
            copyDirectoryContents staleRoot currentRoot
            copiedSha <-
              expectRight
                =<< CheckpointStore.readCheckpointPointer
                  currentRoot
                  (Checkpoint.latestPointerKey (ProductMatrix.productProjectionExperimentHash projection))
            case copiedSha of
              Nothing -> pure (fixtureFailed "the copied store has no latest pointer")
              Just manifestSha -> do
                addressed <-
                  expectRight
                    =<< Report.admitAddressedProductScenarioCompletion currentRoot projection manifestSha
                pure $
                  rejectedWith
                    ( Report.ProductCompletionInvocationMismatch
                        (ProductMatrix.productProjectionRowId projection)
                        (invocationDigest currentPrecondition)
                        (Just (invocationDigest stalePrecondition))
                        :| []
                    )
                    (void (Report.executedProductScenarioCompletion currentPrecondition projection addressed))
      )
  , journal
      "journal-completion-missing-invocation"
      "a completion that never bound an invocation must not satisfy an exact invocation"
      ( withSystemTempDirectory "jitml-negative-control-unbound" $ \root ->
          withSupervisedProductFixture $ \row problem projection -> do
            executableSha <- productScenarioFixtureExecutableSha256
            precondition <-
              expectRight
                =<< Report.observeProductScenarioPrecondition
                  productScenarioFixtureRunId
                  productScenarioFixtureExecutablePath
                  executableSha
                  root
                  projection
            admitted <- persistAndAdmitUnboundProductCompletion root row problem projection
            addressed <-
              expectRight
                =<< Report.admitAddressedProductScenarioCompletion
                  root
                  projection
                  ( CheckpointStore.admittedCheckpointManifestSha
                      (CheckpointStore.admittedCompletedCheckpoint admitted)
                  )
            pure $
              rejectedWith
                ( Report.ProductCompletionInvocationMismatch
                    (ProductMatrix.productProjectionRowId projection)
                    (invocationDigest precondition)
                    Nothing
                    :| []
                )
                (void (Report.executedProductScenarioCompletion precondition projection addressed))
      )
  ]
 where
  invocationDigest =
    TrainingBudget.productScenarioInvocationDigest
      . Report.productScenarioPreconditionInvocation

-- Inference eligibility ---------------------------------------------------------

-- | A model reference at the completed-training state that holds the caller's
-- own completion for @experiment@: the caller-held claim that
-- 'ProductPipeline.markInferenceEligible' must check against the opaque
-- Store-admitted identity.
callerHeldModelRef
  :: Text
  -> TrainingBudget.CompletedTraining
  -> ProductPipeline.ModelRef 'ProductMatrix.TrainingCompleted
callerHeldModelRef experiment =
  ProductPipeline.completeTraining
    ( ProductPipeline.startTraining
        (ProductPipeline.declareModel (ProductPipeline.declareExperiment experiment))
    )

-- | Whether the admitted checkpoint's own completion, held under its own
-- experiment, is accepted as inference-eligible.  Each eligibility control
-- perturbs exactly one of those two claims, so a 'Right' here proves the
-- perturbation is the only defect; a 'Left' is a broken fixture.
eligibilityBaseline
  :: Text
  -> CheckpointStore.AdmittedCompletedCheckpoint
  -> Either Text ()
eligibilityBaseline experiment admitted =
  first
    ("the matching caller-held completion was refused as ineligible: " <>)
    ( void
        ( ProductPipeline.markInferenceEligible
            admitted
            (callerHeldModelRef experiment (CheckpointStore.admittedCompletedTraining admitted))
        )
    )

eligibilityControls :: [NegativeControl]
eligibilityControls =
  [ journal
      "journal-ineligible-caller-held-completion-differs-from-admitted"
      "a caller-held completion that is not the Store-admitted one must not make a model reference inference-eligible"
      ( withAdmittedProductProjection $ \_root _row projection _precondition _addressed admitted -> do
          let experiment = ProductMatrix.productProjectionExperimentHash projection
          pure $
            withFixture (eligibilityBaseline experiment admitted) $ \() ->
              withFixture
                (validCompletedTraining planA TrainingBudget.SupervisedEpochBudget 3 (Just 7))
                $ \callerHeld ->
                  rejectedWith
                    "completed-training witness does not match model reference"
                    ( void
                        ( ProductPipeline.markInferenceEligible
                            admitted
                            (callerHeldModelRef experiment callerHeld)
                        )
                    )
      )
  , journal
      "journal-ineligible-admitted-checkpoint-of-another-row"
      "one row's Store-admitted completion must not make another row's model reference inference-eligible"
      ( withAdmittedProductProjection $ \_root row projection _precondition _addressed admitted ->
          withDifferentProductProjection row $ \other -> do
            let ownExperiment = ProductMatrix.productProjectionExperimentHash projection
                otherExperiment = ProductMatrix.productProjectionExperimentHash other
                admittedCompletion = CheckpointStore.admittedCompletedTraining admitted
            pure $
              withFixture (eligibilityBaseline ownExperiment admitted) $ \() ->
                rejectedWith
                  "completed checkpoint does not match model experiment"
                  ( void
                      ( ProductPipeline.markInferenceEligible
                          admitted
                          (callerHeldModelRef otherExperiment admittedCompletion)
                      )
                  )
      )
  ]

-- | Every reason the report boundary must give for refusing a different row's
-- admitted completion, in the order it reports them: the completion's
-- experiment, plan, canonical row, manifest plan, supervised runtime row,
-- budget, and criterion are all another row's.
crossRowReasons :: [Text]
crossRowReasons =
  [ "ProductCompletionExperimentMismatch"
  , "ProductCompletionPlanMismatch"
  , "ProductCompletionCanonicalRowMismatch"
  , "ProductCompletionManifestPlanMismatch"
  , "ProductCompletionSupervisedRuntimeRowMismatch"
  , "ProductCompletionBudgetMismatch"
  , "ProductCompletionCriterionMismatch"
  ]

-- Journal reader ---------------------------------------------------------------

-- | A journal error list, kept when it is exactly one error the predicate
-- recognises.
singleJournalError
  :: Text
  -> (ProductScenarioJournal.ProductScenarioJournalError -> Bool)
  -> Either (NonEmpty ProductScenarioJournal.ProductScenarioJournalError) report
  -> ControlOutcome
singleJournalError = rejectedOnlyWhere

-- | Rewrite the journal without the key and read it back.
unsignedRead
  :: JournalScenario
  -> (Value -> Value)
  -> IO
       ( Either
           (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
           Report.CompletedProductScenarioReport
       )
unsignedRead s tamper = do
  original <- readJournalValue (jsJournalPath s)
  writeScenarioJournalValue s (tamper original)
  outcome <- readScenarioJournal s
  writeScenarioJournalValue s original
  pure outcome

-- | Rewrite the journal as a holder of the key would, re-sign it, and read it
-- back.  'Left' is a broken fixture: the mirrored receipt material no longer
-- matches production, or the rewrite could not be signed.
resignedRead
  :: JournalScenario
  -> (Value -> Value)
  -> IO
       ( Either
           Text
           ( Either
               (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
               Report.CompletedProductScenarioReport
           )
       )
resignedRead s tamper = do
  identity <- resignedIdentityReadable s
  case identity of
    Left reason -> pure (Left reason)
    Right () -> do
      original <- readJournalValue (jsJournalPath s)
      case resignJournalValue (jsKey s) (tamper original) of
        Left err -> pure (Left err)
        Right rewritten -> do
          writeScenarioJournalValue s rewritten
          outcome <- readScenarioJournal s
          writeScenarioJournalValue s original
          pure (Right outcome)

-- | A control over a re-signed rewrite.
resigned
  :: Text
  -> Text
  -> (Value -> Value)
  -> ( JournalScenario
       -> Either
            (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
            Report.CompletedProductScenarioReport
       -> ControlOutcome
     )
  -> NegativeControl
resigned name description tamper judge =
  scenario name description $ \s -> do
    outcome <- resignedRead s tamper
    pure (withFixture outcome (judge s))

-- | A control over an unsigned rewrite.
unsigned
  :: Text
  -> Text
  -> (Value -> Value)
  -> ( Either
         (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
         Report.CompletedProductScenarioReport
       -> ControlOutcome
     )
  -> NegativeControl
unsigned name description tamper judge =
  scenario name description $ \s -> judge <$> unsignedRead s tamper

authenticationFailed
  :: Either
       (NonEmpty ProductScenarioJournal.ProductScenarioJournalError)
       Report.CompletedProductScenarioReport
  -> ControlOutcome
authenticationFailed =
  rejectedWith
    ( ProductScenarioJournal.ProductScenarioJournalAuthenticationRejected
        ProductScenarioJournal.ProductScenarioJournalAuthenticationFailed
        :| []
    )

readerControls :: [NegativeControl]
readerControls =
  [ scenario
      "journal-manifest-omitted"
      "a journal row that omits its manifest identity must be rejected as malformed"
      ( \s -> do
          outcome <- unsignedRead s (dropRowField "manifest_sha256")
          pure $
            singleJournalError
              "ProductScenarioJournalMalformed naming the missing manifest_sha256 key"
              ( \case
                  ProductScenarioJournal.ProductScenarioJournalMalformed _ detail ->
                    "manifest_sha256" `Text.isInfixOf` detail
                  _ -> False
              )
              outcome
      )
  , unsigned
      "journal-manifest-substituted-zero-unsigned"
      "a zero manifest identity written without the journal key must fail authentication"
      (setRowField "manifest_sha256" (Aeson.String zeroDigest))
      authenticationFailed
  , unsigned
      "journal-manifest-substituted-zero-and-inference-unsigned"
      "a consistent zero manifest and inference identity written without the journal key must fail authentication"
      ( setRowField "manifest_sha256" (Aeson.String zeroDigest)
          . setRowField "inference_manifest_sha256" (Aeson.String zeroDigest)
      )
      authenticationFailed
  , resigned
      "journal-manifest-substituted-zero-resigned"
      "a zero manifest identity, consistently re-signed by a key holder, must fail Store re-admission"
      ( setRowField "manifest_sha256" (Aeson.String zeroDigest)
          . setRowField "inference_manifest_sha256" (Aeson.String zeroDigest)
      )
      ( \s ->
          singleJournalError
            "a completion rejection whose Store admission could not read the zero address"
            ( \case
                ProductScenarioJournal.ProductScenarioJournalCompletionRejected
                  rowId
                  ( Report.ProductCompletionStoreAdmissionFailed
                      _
                      (CheckpointStore.AdmissionManifestReadFailed objectKey _)
                    ) ->
                    rowId == ProductMatrix.productProjectionRowId (jsProjection s)
                      && zeroDigest `Text.isInfixOf` objectKey
                _ -> False
            )
      )
  , unsigned
      "journal-manifest-inference-mismatch-unsigned"
      "an inference manifest that differs from the admitted manifest, written without the key, must fail authentication"
      (setRowField "inference_manifest_sha256" (Aeson.String zeroDigest))
      authenticationFailed
  , resigned
      "journal-manifest-inference-mismatch-resigned"
      "an inference manifest identity that differs from the manifest identity, re-signed by a key holder, must be rejected"
      (setRowField "inference_manifest_sha256" (Aeson.String zeroDigest))
      ( \s ->
          rejectedWith
            ( ProductScenarioJournal.ProductScenarioJournalInferenceManifestMismatch
                (ProductMatrix.productProjectionRowId (jsProjection s))
                (admittedManifestSha s)
                zeroDigest
                :| []
            )
      )
  , scenario
      "journal-manifest-foreign-row-address-resigned"
      "another row's admitted manifest address, re-signed into this row's journal, must not resolve under this row's Store scope"
      ( \s -> do
          foreignSha <- foreignAdmittedManifestSha s
          outcome <-
            resignedRead
              s
              ( setRowField "manifest_sha256" (Aeson.String foreignSha)
                  . setRowField "inference_manifest_sha256" (Aeson.String foreignSha)
              )
          pure $
            withFixture outcome $
              singleJournalError
                "a completion rejection whose Store admission could not find the foreign address under this row"
                ( \case
                    ProductScenarioJournal.ProductScenarioJournalCompletionRejected
                      _
                      ( Report.ProductCompletionStoreAdmissionFailed
                          _
                          (CheckpointStore.AdmissionManifestReadFailed objectKey _)
                        ) -> foreignSha `Text.isInfixOf` objectKey
                    _ -> False
                )
      )
  , scenario
      "journal-manifest-foreign-row-planted-resigned"
      "another row's manifest planted under this row's key and re-signed into its journal must be refused for recording a different experiment"
      ( \s -> do
          plantedSha <- plantedForeignManifestSha s
          outcome <-
            resignedRead
              s
              ( setRowField "manifest_sha256" (Aeson.String plantedSha)
                  . setRowField "inference_manifest_sha256" (Aeson.String plantedSha)
              )
          pure $
            withFixture outcome $
              singleJournalError
                "a completion rejection whose Store admission found a manifest recording another experiment"
                ( \case
                    ProductScenarioJournal.ProductScenarioJournalCompletionRejected
                      _
                      ( Report.ProductCompletionStoreAdmissionFailed
                          _
                          (CheckpointStore.AdmissionManifestInvalid detail)
                        ) -> "experiment mismatch" `Text.isInfixOf` detail
                    _ -> False
                )
      )
  , resigned
      "journal-invocation-not-backed-by-admitted-completion-resigned"
      "an invocation digest the Store-admitted completion does not carry, re-signed by a key holder, must be rejected"
      (setRowField "invocation_digest" (Aeson.String zeroDigest))
      ( \_ ->
          singleJournalError
            "an evidence rejection saying the invocation digest differs from the exact Store-admitted completion"
            ( \case
                ProductScenarioJournal.ProductScenarioJournalEvidenceRejected _ err ->
                  "invocation digest differs from exact Store-admitted completion"
                    `Text.isInfixOf` Text.pack (show err)
                _ -> False
            )
      )
  , resigned
      "journal-plan-identity-drift-resigned"
      "a plan identity that differs from the current projection, re-signed by a key holder, must be rejected"
      (setRowField "plan_id" (Aeson.String zeroDigest))
      ( \s ->
          singleJournalError
            "a plan mismatch naming the projection's plan"
            ( \case
                ProductScenarioJournal.ProductScenarioJournalPlanMismatch rowId expected observed ->
                  rowId == ProductMatrix.productProjectionRowId (jsProjection s)
                    && expected == planText s
                    && observed == zeroDigest
                _ -> False
            )
      )
  , resigned
      "journal-row-omitted-resigned"
      "a journal with no rows, re-signed by a key holder, must be rejected as missing the projected row"
      (setJournalField "rows" (Aeson.Array mempty))
      ( \s ->
          rejectedWith
            ( ProductScenarioJournal.ProductScenarioJournalMissingRow
                (ProductMatrix.productProjectionRowId (jsProjection s))
                (planText s)
                :| [ ProductScenarioJournal.ProductScenarioJournalRowOrderMismatch
                       [ProductMatrix.productProjectionRowId (jsProjection s)]
                       []
                   ]
            )
      )
  , resigned
      "journal-precondition-missing-resigned"
      "a journal that records no rejected precondition, re-signed by a key holder, must be rejected"
      (setRowField "precondition_rejected" (Aeson.Bool False))
      ( \s ->
          rejectedWith
            ( ProductScenarioJournal.ProductScenarioJournalPreconditionMissing
                (ProductMatrix.productProjectionRowId (jsProjection s))
                :| []
            )
      )
  , resigned
      "journal-chronology-drift-resigned"
      "a journal whose completion precedes inference, re-signed by a key holder, must be rejected"
      (setRowField "completion_sequence" (Aeson.toJSON (2 :: Int)))
      ( \s ->
          rejectedWith
            ( ProductScenarioJournal.ProductScenarioJournalChronologyInvalid
                (ProductMatrix.productProjectionRowId (jsProjection s))
                3
                7
                2
                :| []
            )
      )
  , scenario
      "journal-wrong-key-rejected"
      "a journal read with a different key than the one that signed it must fail authentication"
      ( \s -> do
          otherKey <- expectRight =<< ProductScenarioJournal.generateProductScenarioJournalKey
          outcome <-
            ProductScenarioJournal.readProductScenarioJournal
              otherKey
              (jsJournalPath s)
              (jsCheckpointRoot s)
              (jsRunId s)
              (jsExecutablePath s)
              (jsExecutableSha s)
              (jsBatch s)
          pure $
            if otherKey == jsKey s
              then fixtureFailed "two generated journal keys collided"
              else authenticationFailed outcome
      )
  , scenario
      "journal-missing-file"
      "a journal that does not exist must be rejected as missing, not read as empty"
      ( \s -> do
          let missingPath = takeDirectory (jsJournalPath s) </> "no-such-journal.json"
          outcome <-
            ProductScenarioJournal.readProductScenarioJournal
              (jsKey s)
              missingPath
              (jsCheckpointRoot s)
              (jsRunId s)
              (jsExecutablePath s)
              (jsExecutableSha s)
              (jsBatch s)
          pure (rejectedWith (ProductScenarioJournal.ProductScenarioJournalMissing missingPath :| []) outcome)
      )
  , scenario
      "journal-writer-foreign-checkpoint-root"
      "the writer must refuse to persist evidence retained under one checkpoint scope into a journal for another"
      ( \s ->
          withSystemTempDirectory "jitml-negative-control-foreign-root" $ \foreignRoot -> do
            written <-
              ProductScenarioJournal.writeProductScenarioJournalAtomic
                (jsKey s)
                (takeDirectory (jsJournalPath s) </> "foreign-root-journal.json")
                foreignRoot
                (jsRunId s)
                (jsBatch s)
                (jsReport s)
            pure $
              singleJournalError
                "ProductScenarioJournalCheckpointScopeMismatch"
                ( \case
                    ProductScenarioJournal.ProductScenarioJournalCheckpointScopeMismatch {} -> True
                    _ -> False
                )
                written
      )
  ]
 where
  admittedManifestSha s =
    CheckpointStore.admittedCheckpointManifestSha
      (CheckpointStore.admittedCompletedCheckpoint (jsAdmitted s))
  planText s = planIdText (ProductMatrix.productProjectionPlanId (jsProjection s))

-- Portable lane journal --------------------------------------------------------

-- | Admit the lane journal's (possibly rewritten) bytes, pinned to their own
-- digest, against the scenario's batch.
admitLane
  :: JournalScenario
  -> ByteString.ByteString
  -> Either
       (NonEmpty ProductLaneJournal.ProductLaneJournalError)
       ProductLaneJournal.AdmittedProductLaneJournal
admitLane s bytes =
  ProductLaneJournal.admitProductLaneJournal (sha256Hex bytes) (jsBatch s) bytes

-- | Rewrite the lane journal's JSON, keep it canonical-looking, and pin the
-- rewritten bytes to their own digest, so only the content drift is under test.
rewrittenLane
  :: JournalScenario
  -> (Value -> Value)
  -> Either Text ByteString.ByteString
rewrittenLane s rewrite =
  case Aeson.eitherDecodeStrict' (laneJournalBytes s) of
    Left err -> Left ("lane journal JSON did not decode: " <> Text.pack err)
    Right value ->
      Right (LazyByteString.toStrict (Aeson.encode (rewrite value)) <> "\n")

laneControls :: [NegativeControl]
laneControls =
  [ scenario
      "journal-lane-drift-digest-mismatch"
      "lane-journal bytes that differ from their pinned digest must be rejected before they are decoded"
      ( \s -> do
          let bytes = laneJournalBytes s
              drifted = ByteString.snoc bytes 32
          pure $
            rejectedWith
              (ProductLaneJournal.ProductLaneJournalDigestMismatch (sha256Hex bytes) (sha256Hex drifted) :| [])
              ( ProductLaneJournal.admitProductLaneJournal
                  (sha256Hex bytes)
                  (jsBatch s)
                  drifted
              )
      )
  , scenario
      "journal-lane-drift-pinned-digest-not-canonical"
      "a pinned digest that is not canonical SHA-256 must be rejected"
      ( \s ->
          pure $
            rejectedWith
              ( ProductLaneJournal.ProductLaneJournalMalformed
                  "expected lane-journal digest is not canonical SHA-256"
                  :| []
              )
              (ProductLaneJournal.admitProductLaneJournal "not-a-digest" (jsBatch s) (laneJournalBytes s))
      )
  , laneRewrite
      "journal-lane-drift-source-rejected-plan-id"
      "a lane journal whose plan identity drifted from the current projection must be rejected as a source rejection"
      (setRowField "plan_id" (Aeson.String zeroDigest))
      ( \s ->
          ProductLaneJournal.ProductLaneJournalSourceRejected
            ( ProductMatrix.productProjectionRowId (jsProjection s)
                <> ": plan_id differs from the current projection"
            )
            :| []
      )
  , laneRewrite
      "journal-lane-drift-source-rejected-inference-manifest"
      "a lane journal whose inference manifest differs from the refined completion must be rejected as a source rejection"
      (setRowField "inference_manifest_sha256" (Aeson.String zeroDigest))
      ( const
          ( ProductLaneJournal.ProductLaneJournalSourceRejected
              "inference_manifest_sha256 differs from the refined completed_training value"
              :| []
          )
      )
  , laneRewrite
      "journal-lane-drift-manifest-omitted"
      "a lane journal row that omits its admitted manifest identity must be rejected as malformed"
      (dropRowField "admitted_manifest_sha256")
      ( const
          ( ProductLaneJournal.ProductLaneJournalMalformed
              "Error in $.rows[0]: key \"admitted_manifest_sha256\" not found"
              :| []
          )
      )
  , laneRewrite
      "journal-lane-drift-unknown-field"
      "a lane journal carrying a field outside its schema must be rejected as malformed"
      (setJournalField "future_field" Aeson.Null)
      ( const
          ( ProductLaneJournal.ProductLaneJournalMalformed
              "Error in $: ProductLaneJournal contains unknown fields: future_field"
              :| []
          )
      )
  , nonCanonical
      "journal-lane-drift-non-canonical-missing-newline"
      "lane-journal bytes without the canonical trailing newline, pinned to their own digest, must be rejected"
      (\bytes -> ByteString.take (ByteString.length bytes - 1) bytes)
  , nonCanonical
      "journal-lane-drift-non-canonical-leading-whitespace"
      "lane-journal bytes with leading whitespace, pinned to their own digest, must be rejected"
      (ByteString.cons 32)
  , scenario
      "journal-lane-drift-wrong-lane"
      "a linux-cpu lane journal must not be admitted against the linux-cuda projection batch"
      ( \s ->
          pure $
            case ProductMatrix.projectProductRows LinuxCUDA [jsRow s] of
              Failure errors -> fixtureFailed ("the linux-cuda batch failed to project: " <> Text.pack (show errors))
              Success cudaBatch ->
                rejectedWhere
                  "ProductLaneJournalSourceRejected naming the lane substrate"
                  ( \errors ->
                      ProductLaneJournal.ProductLaneJournalSourceRejected
                        "lane-journal substrate differs from the projection batch"
                        `elem` NonEmpty.toList errors
                  )
                  ( ProductLaneJournal.admitProductLaneJournal
                      (sha256Hex (laneJournalBytes s))
                      cudaBatch
                      (laneJournalBytes s)
                  )
      )
  ]
 where
  -- Valid JSON with the right content whose bytes are not the canonical
  -- encoding, pinned to their own digest so only canonicality is under test.
  nonCanonical name description respell =
    scenario name description $ \s ->
      pure $
        withFixture (rewrittenLane s id) $ \bytes ->
          rejectedWith
            (ProductLaneJournal.ProductLaneJournalNonCanonical :| [])
            (admitLane s (respell bytes))
  laneRewrite name description rewrite expected =
    scenario name description $ \s ->
      pure $
        withFixture (rewrittenLane s rewrite) $ \bytes ->
          rejectedWith (expected s) (admitLane s bytes)
