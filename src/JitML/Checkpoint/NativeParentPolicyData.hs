{-# LANGUAGE OverloadedStrings #-}

-- | Independent recorded numerical/lineage DATA checks. Success is neither a
-- producer/parent capability nor Store, journal or qualification admission.
module JitML.Checkpoint.NativeParentPolicyData
  ( NativeParentPolicyData
  , NativeParentPolicyFailure (..)
  , NativeParentExpectations (..)
  , NativeDeviceObservationData (..)
  , NativeParentComparisonData (..)
  , NativeParentChildPolicyData (..)
  , verifyNativeParentPolicyData
  , nativeParentPolicyBinding
  , nativeParentPolicyComparison
  , nativeParentPolicyChildren
  , nativeParentPolicyFindings
  , nativeParentNeedsSelectedDeviceReevaluation
  , nativeParentPreparationPhaseForConfiguration
  ) where

import Control.Exception (evaluate)
import Control.Exception.Safe (tryAny)
import Control.Monad (unless, zipWithM, zipWithM_)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString qualified as BS
import Data.Either.Combinators (mapLeft)
import Data.List (find)
import Data.Maybe (catMaybes, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import Data.Word (Word64)

import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentPolicyData.ArenaRaw qualified as ArenaRaw
import JitML.Checkpoint.NativeParentPolicyData.Ars qualified as ArsRead
import JitML.Checkpoint.NativeParentPolicyData.Evaluation qualified as Evaluation
import JitML.Checkpoint.NativeParentPolicyData.Lineage
import JitML.Checkpoint.NativeParentPolicyData.Neural qualified as NeuralRead
import JitML.Checkpoint.NativeParentPolicyData.Node qualified as Node
import JitML.Checkpoint.NativeParentPolicyData.References qualified as ReferenceRead
import JitML.Checkpoint.NativeParentPolicyData.ReturnReplay qualified as ReturnReplay
import JitML.Checkpoint.NativePhase.Codec qualified as Phase
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Failure qualified as Failure
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Projection
import JitML.Checkpoint.NativePhase.Projection.Build qualified as Build
import JitML.Checkpoint.NativePhase.Projection.Cases qualified as Cases
import JitML.Checkpoint.NativePhase.Projection.Values qualified as Values
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReferences qualified as References
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.NativeRetentionReader qualified as Envelope
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeArenaLearningPolicy qualified as ArenaPolicy
import JitML.Product.NativeHerLearningPolicy qualified as HerPolicy
import JitML.Product.NativePreparedAlphaZeroAttempt qualified as ArenaChild
import JitML.Product.NativeReturnLearningPolicy qualified as ReturnPolicy
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlProducer.Inventory qualified as Inventory
import JitML.Product.SourceDigest qualified as Source
import JitML.RL.Algorithms.ContinuousTrainer qualified as Continuous
import JitML.RL.Algorithms.DqnTrainer qualified as Dqn
import JitML.RL.Algorithms.PpoTrainer qualified as Ppo
import JitML.RL.Algorithms.QrDqnTrainer qualified as Qr
import JitML.RL.AlphaZero.ArenaTape qualified as Tape
import JitML.RL.AlphaZero.NativeArenaEvaluation qualified as Arena
import JitML.RL.AlphaZero.NativeArenaReferences qualified as ArenaRef
import JitML.RL.ArsHostTrace qualified as ArsTrace
import JitML.RL.EpisodeEnvelope qualified as Episode
import JitML.RL.NativeHerEvaluation qualified as Her
import JitML.RL.NativeHerReferences qualified as HerRef
import JitML.RL.NativeReturnEvaluation qualified as Return
import JitML.RL.NativeReturnReferences qualified as ReturnRef
import JitML.RL.ProductBudget qualified as Product
import JitML.RL.TrainerConfiguration qualified as Config
import JitML.RL.TrainerObservation qualified as Observation
import JitML.Training.Budget qualified as Training

data NativeParentPolicyFailure
  = NativeParentPolicyRejected !CodecError
  | NativeParentPolicyProjectionRejected !Build.ProjectionFailure
  | NativeParentPolicySynchronousFailure !Failure.NativeDiagnosticData
  deriving stock (Eq, Show)
data NativeParentComparisonData
  = NativeParentReturnComparison !ReturnPolicy.NativeReturnCohortComparison
  | NativeParentHerComparison !HerPolicy.NativeHerCohortComparison
  | NativeParentArenaComparison !ArenaPolicy.NativeArenaCohortComparisonData
  deriving stock (Eq, Show)
data NativeParentChildPolicyData
  = NativeParentReturnChild
      !Int
      !Word64
      !Return.RawNativeReturnEvaluation
      !Return.RawNativeReturnEvaluation
      !Observation.ReturnedPolicy
      !NativeDeviceObservationData
      ![NativeArsLineageData]
  | NativeParentHerChild
      !Int
      !Word64
      !Her.RawNativeHerEvaluation
      !Her.RawNativeHerEvaluation
      !Observation.ReturnedPolicy
      !NativeDeviceObservationData
  | NativeParentArenaChild
      !Int
      !Word64
      !Arena.RawNativeArenaEvaluation
      !Arena.RawNativeArenaEvaluation
      !ArenaRaw.NativeArenaRawData
      !NativeDeviceObservationData
  deriving stock (Eq, Show)
data NativeParentPolicyData
  = NativeParentPolicyData
      !Binding.NativeParentBindingData
      !NativeParentComparisonData
      ![NativeParentChildPolicyData]
nativeParentPolicyBinding :: NativeParentPolicyData -> Binding.NativeParentBindingData
nativeParentPolicyBinding (NativeParentPolicyData value _ _) = value
nativeParentPolicyComparison :: NativeParentPolicyData -> NativeParentComparisonData
nativeParentPolicyComparison (NativeParentPolicyData _ value _) = value
nativeParentPolicyChildren :: NativeParentPolicyData -> [NativeParentChildPolicyData]
nativeParentPolicyChildren (NativeParentPolicyData _ _ value) = value
nativeParentPolicyFindings :: NativeParentPolicyData -> [Text]
nativeParentPolicyFindings value = case nativeParentPolicyComparison value of
  NativeParentReturnComparison actual -> ReturnPolicy.nativeReturnComparisonFailures actual
  NativeParentHerComparison actual -> HerPolicy.nativeHerComparisonFailures actual
  NativeParentArenaComparison actual -> ArenaPolicy.nativeArenaDataFindings actual

-- Recorded numeric outputs are not independently recomputed for neural/AZ
-- cases here. A real parent selected-lane reevaluation remains mandatory in
-- final authentication; a decoded witness is never a substitute for it.
nativeParentNeedsSelectedDeviceReevaluation :: NativeParentPolicyData -> Bool
nativeParentNeedsSelectedDeviceReevaluation = any one . nativeParentPolicyChildren
 where
  one (NativeParentReturnChild _ _ _ _ _ NativeHostNoMlpData _) = False
  one _ = True

-- Ordinary finite family classification used by the actual snapshot checks.
-- Every continuous recipe owns a cold token; only some perform warm updates.
nativeParentPreparationPhaseForConfiguration :: Config.NeuralTrainerConfiguration -> PhaseTag
nativeParentPreparationPhaseForConfiguration (Config.ContinuousConfiguration _) = ColdSnapshotPhase
nativeParentPreparationPhaseForConfiguration _ = EffectiveSnapshotPhase

type Program = ExceptT NativeParentPolicyFailure IO
codec :: Either CodecError a -> Program a
codec = either (throwError . NativeParentPolicyRejected) pure
mathematical :: Either Text a -> Program a
mathematical = codec . mapLeft Malformed
require :: Bool -> Text -> Program ()
require condition message = unless condition (throwError (NativeParentPolicyRejected (Malformed message)))

-- No actual observations/fetches, source acquisition, callbacks or training.
-- Explicit expected identity DATA must come from the parent's own precondition;
-- equal invented records are still DATA, never authenticated parent authority.
verifyNativeParentPolicyData
  :: Cohort.NativeRlCohortBatch
  -> NativeParentExpectations
  -> Binding.NativeParentBindingData
  -> IO (Either NativeParentPolicyFailure NativeParentPolicyData)
verifyNativeParentPolicyData batch expected binding = do
  attempted <- tryAny $ do
    result <- runExceptT (verify batch expected binding)
    case result of
      Left problem -> evaluate (length (show problem)) >> pure (Left problem)
      Right actual -> do
        _ <- evaluate (sum (map Text.length (nativeParentPolicyFindings actual)))
        pure (Right actual)
  case attempted of
    Right result -> pure result
    Left exception ->
      Left . NativeParentPolicySynchronousFailure <$> Failure.captureNativeExceptionDiagnostic exception

-- Keep total base-only drop; the suggested drop1 adds an unneeded package.
{- HLINT ignore verify "Use drop1" -}
verify
  :: Cohort.NativeRlCohortBatch
  -> NativeParentExpectations
  -> Binding.NativeParentBindingData
  -> Program NativeParentPolicyData
verify batch expected binding = do
  checked <-
    mathematical
      ( Cohort.refineNativeRlCohortBatch
          (Cohort.nativeRlCohortBatchSubstrate batch)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  require (checked == batch) "parent policy complete current batch differs"
  let cohort = Binding.nativeParentBindingCohort binding
      acquisition = Binding.nativeParentBindingAcquisition binding
      reference = Acquisition.acquisitionReferences acquisition
      metadata = Metadata.nativeQualificationReceiptFields (Binding.nativeParentBindingMetadata binding)
      replays = Binding.nativeParentBindingReplays binding
      canonical =
        filter
          ((== Cohort.nativeRlCohortPlanId cohort) . Cohort.nativeRlCohortPlanId)
          (Cohort.nativeRlCohortBatchPlans batch)
      sources = nativeParentExpectedSources expected
      plans = Cohort.nativeRlCohortPlanChildren cohort
      children = Acquisition.acquisitionChildren acquisition
  require
    ( canonical == [cohort]
        && References.nativeReferenceDataCohortTransport reference == Cohort.nativeRlCohortPlanTransport cohort
    )
    "parent policy whole current canonical cohort/reference transport differs"
  require
    ( Metadata.nativeReceiptObservedSource metadata == Context.nativeContextObservedSource sources
        && Metadata.nativeReceiptSuppliedSource metadata == Context.nativeContextSuppliedSource sources
    )
    "parent policy original observed/supplied source roles differ"
  require
    ( Source.stampAlgorithm (nativeParentExpectedSource expected) == Source.sourceDigestAlgorithm
        && all
          (== nativeParentExpectedSource expected)
          (catMaybes [Context.nativeContextObservedSource sources, Context.nativeContextSuppliedSource sources])
        && not
          ( isNothing (Context.nativeContextObservedSource sources)
              && isNothing (Context.nativeContextSuppliedSource sources)
          )
    )
    "parent policy source expectations are absent or differ from its independently expected source"
  case (nativeParentExpectedAssociation expected, Metadata.nativeReceiptAssociation metadata) of
    (Context.DirectLocalContext digest, Metadata.NativeReceiptDirectData actual) -> require (digest == actual) "parent policy direct original association differs"
    (Context.SuppliedScenarioContext invocation, Metadata.NativeReceiptScenarioData actual) ->
      require
        (Training.renderProductScenarioInvocation invocation == actual)
        "parent policy exact original issued invocation differs"
    _ -> require False "parent policy original association role differs"
  _ <- codec (boundedLength AggregateSequenceElements 11 replays)
  require
    ( length replays == 11
        && length plans == 5
        && map Acquisition.acquisitionChildIndex children == [0 .. 4]
    )
    "parent policy requires the original five children and exactly eleven replay objects"
  allocation <-
    codec
      ( Context.digestFromCanonicalText
          (Retain.nativeRetainedObjectSha256 (Metadata.nativeReceiptAllocation metadata))
      )
  zipWithM_
    (bindReplay allocation acquisition)
    ( [(i, stage) | i <- [0 .. 4], stage <- [Replay.InitialModelReplay, Replay.FinalModelReplay]]
        <> [(0, Replay.StoredFinalModelReplay)]
    )
    replays
  case (drop 1 replays, drop 10 replays) of
    (final0 : _, [stored]) ->
      require
        ( Replay.nativeReplayObjectRoot stored == Replay.nativeReplayObjectRoot final0
            && Replay.nativeReplayObjectEntries stored == Replay.nativeReplayObjectEntries final0
        )
        "parent stored-final replay is not the same exact child0 final graph"
    _ -> require False "parent policy serving replay allocation differs"
  -- All producer bundles, including raw/prepared/initial/final/after-process,
  -- are compared to EXPLICIT parent expected FILE/PID/source identity DATA.
  zipWithM_ (verifyChildProducers expected cohort batch) plans children
  let row = Matrix.rowClass (Cohort.nativeRlCohortPlanRow cohort)
  (comparison, decoded) <- case row of
    Matrix.RlAlgorithmEnvironment algorithm environment -> do
      spec <- mathematical (ReturnRef.canonicalNativeReturnSpec algorithm environment)
      let root = References.nativeReferenceDataSpecRoot reference
      expectProjection (References.nativeReferenceDataSpecPool reference) root (Cases.returnSpec spec)
      refs <- codec (ReferenceRead.returnReferences spec reference)
      models <- zipWithM (decodeReturnChild batch expected cohort acquisition spec root) plans children
      observations <- traverse returnObservation models
      compared <- mathematical (ReturnPolicy.compareNativeReturnCohort refs observations)
      pure (NativeParentReturnComparison compared, models)
    Matrix.RlGoalConditioned _ -> do
      let root = References.nativeReferenceDataSpecRoot reference
      schedule <-
        codec
          (Node.runDecode (References.nativeReferenceDataSpecPool reference) (Evaluation.herSchedule root))
      expectProjection
        (References.nativeReferenceDataSpecPool reference)
        root
        (Cases.herSchedule schedule)
      refs <- codec (ReferenceRead.verifyHerReferences schedule reference)
      models <- zipWithM (decodeHerChild batch cohort acquisition schedule root) plans children
      observations <- traverse herObservation models
      compared <- mathematical (HerPolicy.compareNativeHerCohort refs observations)
      pure (NativeParentHerComparison compared, models)
    Matrix.AlphaZeroGame game -> do
      spec <- mathematical (ArenaRef.canonicalNativeArenaSpec game)
      let root = References.nativeReferenceDataSpecRoot reference
      expectProjection (References.nativeReferenceDataSpecPool reference) root (Cases.arenaSpec spec)
      rowData <-
        either
          (mathematical . Left . ArenaChild.nativeAlphaZeroFailureDetail)
          pure
          (ArenaChild.selectNativeAlphaZeroRowData batch game)
      let tape = ArenaChild.nativeAlphaZeroRowTape rowData
      refs <- codec (ReferenceRead.arenaReferences spec tape reference)
      models <- zipWithM (decodeArenaChild batch cohort acquisition spec root tape rowData) plans children
      observations <- traverse arenaObservation models
      compared <- mathematical (ArenaPolicy.compareNativeArenaCohortData spec tape refs observations)
      pure (NativeParentArenaComparison compared, models)
    _ -> throwError (NativeParentPolicyRejected (Malformed "parent policy excludes non-native rows"))
  pure (NativeParentPolicyData binding comparison decoded)

phaseAt :: Text -> Acquisition.NativeAcquisitionChildData -> Program Phase.PhaseData
phaseAt suffix child =
  maybe
    (throwError (NativeParentPolicyRejected (Malformed "parent required typed child phase is absent")))
    pure
    ( lookup
        (label (Acquisition.acquisitionChildIndex child) suffix)
        (Acquisition.acquisitionChildPhases child)
    )
label :: Int -> Text -> Text
label index suffix = "child" <> Text.pack (show index) <> "." <> suffix
physicalAt :: Acquisition.NativeAcquisitionData -> Int -> Text -> Program BS.ByteString
physicalAt acquisition index suffix =
  maybe
    ( throwError
        (NativeParentPolicyRejected (Malformed "parent required dedicated child envelope is absent"))
    )
    (pure . Envelope.decodedPhasePayload)
    ( find
        ((== label index suffix) . Envelope.decodedPhaseLabel)
        (Acquisition.acquisitionPhases acquisition)
    )

bindReplay
  :: Digest
  -> Acquisition.NativeAcquisitionData
  -> (Int, Replay.NativeReplayObjectStage)
  -> Replay.NativeReplayObjectData
  -> Program ()
bindReplay allocation acquisition (index, stage) replay = do
  child <-
    maybe
      (throwError (NativeParentPolicyRejected (Malformed "parent replay original child is absent")))
      pure
      (find ((== index) . Acquisition.acquisitionChildIndex) (Acquisition.acquisitionChildren acquisition))
  require
    ( Replay.nativeReplayObjectIndex replay == fromIntegral index
        && Replay.nativeReplayObjectStage replay == stage
        && Replay.nativeReplayObjectAllocation replay == allocation
        && Replay.nativeReplayObjectAttempt replay == Acquisition.acquisitionChildAttempt child
    )
    "parent replay role/index/attempt/physical-allocation differs"
  phase <- phaseAt (if stage == Replay.InitialModelReplay then "initial" else "final") child
  entries <- codec (Node.closureEntries (Phase.phaseDataRoot phase) (Phase.phaseDataPool phase))
  require
    ( Replay.nativeReplayObjectRoot replay == Phase.phaseDataRoot phase
        && Replay.nativeReplayObjectEntries replay == entries
    )
    "parent replay root/full canonical byte closure differs from the physical source phase"

verifyChildProducers
  :: NativeParentExpectations
  -> Cohort.NativeRlCohortPlan
  -> Cohort.NativeRlCohortBatch
  -> Cohort.NativeRlSeedPlan
  -> Acquisition.NativeAcquisitionChildData
  -> Program ()
verifyChildProducers expected cohort batch plan child = do
  let phases = Acquisition.acquisitionChildPhases child
  records <-
    traverse
      ( \(_, phase) -> do
          let values = Schema.contextFields (Phase.phaseDataContext phase)
          producer <- case reverse values of
            VRef actual : _ -> pure actual
            _ -> throwError (NativeParentPolicyRejected (Malformed "parent phase producer reference absent"))
          acquisition <- case drop 12 values of
            VDigest actual : _ -> pure actual
            _ -> throwError (NativeParentPolicyRejected (Malformed "parent phase acquisition field absent"))
          expectedContext <-
            codec
              ( Context.nativePhaseContextValues
                  batch
                  (Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort))
                  (Cohort.nativeRlSeedPlanIndex plan)
                  (nativeParentExpectedAssociation expected)
                  (nativeParentExpectedSources expected)
                  (Acquisition.acquisitionChildAttempt child)
                  acquisition
                  producer
              )
          require (values == expectedContext) "parent phase original full canonical context differs"
          (before, after) <- codec (decodeProducerBundle (Phase.phaseDataPool phase) producer)
          actualBefore <-
            maybe
              (throwError (NativeParentPolicyRejected (Malformed "parent phase original before-process is absent")))
              pure
              before
          codec (verifyProducer expected actualBefore)
          case after of
            Nothing -> pure ()
            Just actualAfter -> do
              codec (verifyProducer expected actualAfter)
              require
                (Process.compareRecordedProducerObservationData actualBefore actualAfter == Right ())
                "parent phase before/after full FILE/process/source DATA differs"
          pure actualBefore
      )
      phases
  case records of
    first : rest ->
      mapM_
        ( \actual ->
            require
              (Process.compareRecordedProducerObservationData first actual == Right ())
              "parent child phases changed the original complete process/source record"
        )
        rest
    [] -> require False "parent child phases are absent"
  final <- phaseAt "after-process" child
  producer <- case reverse (Schema.contextFields (Phase.phaseDataContext final)) of
    VRef actual : _ -> pure actual
    _ -> throwError (NativeParentPolicyRejected (Malformed "parent after-process producer absent"))
  (_, after) <- codec (decodeProducerBundle (Phase.phaseDataPool final) producer)
  require
    (case after of Just _ -> True; _ -> False)
    "parent child after-process observation is absent"

expectProjection :: Graph.NodePool -> Digest -> Build.Build Digest -> Program ()
expectProjection pool root action = do
  projected <- liftIO (Build.projectSafely Graph.emptyNodePool action)
  (expected, canonical) <- either (throwError . NativeParentPolicyProjectionRejected) pure projected
  left <- codec (Node.closureEntries root pool)
  right <- codec (Node.closureEntries expected canonical)
  require
    (root == expected && left == right)
    "parent full canonical typed projection differs from recorded bytes"
canonicalConfig :: Graph.NodePool -> Digest -> Config.NeuralTrainerConfiguration -> Program ()
canonicalConfig pool root actual = expectProjection pool root (Values.neuralConfiguration actual)

snapshotInitial :: Config.NeuralTrainerConfiguration -> Digest -> Phase.PhaseData -> Program Digest
snapshotInitial config configRoot phase =
  codec
    ( Node.runDecode (Phase.phaseDataPool phase) $ do
        let kind = case config of
              Config.OnPolicyConfiguration _ -> NPpoSnapshot
              Config.DqnConfiguration _ -> NDqnSnapshot
              Config.QrDqnConfiguration _ -> NQrSnapshot
              Config.ContinuousConfiguration _ -> NContinuousSnapshot
              Config.HerConfiguration _ -> NHerSnapshot
        actual <- Node.fields kind (Phase.phaseDataRoot phase)
        case (config, actual) of
          (Config.ContinuousConfiguration _, VWord 1 : VRef c : _ : VRef actor : _) -> Node.require (c == configRoot) "parent effective continuous config differs" >> pure actor
          (_, VRef c : VRef initial : _) -> Node.require (c == configRoot) "parent effective neural config differs" >> pure initial
          _ -> Node.reject "parent effective snapshot family/stage differs"
    )

-- Re-projecting the complete public evaluation forces every actual field and
-- demands full sorted closure equality, including signed zero/NaN bit payloads.
reproject
  :: Phase.PhaseData -> IO (Either Build.ProjectionFailure (Digest, Graph.NodePool)) -> Program ()
reproject phase action = do
  actual <- liftIO action
  (root, pool) <- either (throwError . NativeParentPolicyProjectionRejected) pure actual
  expected <- codec (Node.closureEntries (Phase.phaseDataRoot phase) (Phase.phaseDataPool phase))
  observed <- codec (Node.closureEntries root pool)
  require
    (root == Phase.phaseDataRoot phase && observed == expected)
    "parent decoded evaluation lossless re-projection differs"

deviceFor
  :: Cohort.NativeRlCohortBatch
  -> Acquisition.NativeAcquisitionData
  -> Acquisition.NativeAcquisitionChildData
  -> Bool
  -> Program NativeDeviceObservationData
deviceFor batch acquisition child host =
  physicalAt acquisition (Acquisition.acquisitionChildIndex child) "device-observation"
    >>= codec . verifyDevice (Cohort.nativeRlCohortBatchSubstrate batch) host

decodeReturnChild
  :: Cohort.NativeRlCohortBatch
  -> NativeParentExpectations
  -> Cohort.NativeRlCohortPlan
  -> Acquisition.NativeAcquisitionData
  -> ReturnRef.NativeReturnReferenceSpec
  -> Digest
  -> Cohort.NativeRlSeedPlan
  -> Acquisition.NativeAcquisitionChildData
  -> Program NativeParentChildPolicyData
decodeReturnChild batch expected cohort acquisition spec specRoot plan child = do
  compiled <-
    maybe
      (throwError (NativeParentPolicyRejected (Malformed "parent RETURN compiled child absent")))
      pure
      (Cohort.nativeRlSeedPlanCompiledReturn plan)
  prepared <- effectiveSnapshot child
  raw <- phaseAt "raw" child
  initial <- phaseAt "initial" child
  final <- phaseAt "final" child
  let host = Product.compiledRlTrainerKind compiled == "ars"
  (configuration, configRoot, initialRoot, lineage, policy) <-
    if host
      then do
        (_, config) <- mathematical (ArsTrace.resolveArsHostPlanData compiled)
        roots <-
          codec
            ( Node.runDecode (Phase.phaseDataPool prepared) $ do
                actual <- Node.fields NArsSnapshot (Phase.phaseDataRoot prepared)
                case actual of
                  [VRef c, VRef p, _, _] -> pure (c, p)
                  _ -> Node.reject "parent ARS prepared fields differ"
            )
        let (c, p) = roots
        expectProjection (Phase.phaseDataPool prepared) c (Values.arsConfig config)
        begunBytes <- physicalAt acquisition (Acquisition.acquisitionChildIndex child) "ars-begun"
        originBytes <- physicalAt acquisition (Acquisition.acquisitionChildIndex child) "ars-origin"
        begun <- codec (decodeArsLineage False begunBytes)
        origin <- codec (decodeArsLineage True originBytes)
        let nonce =
              Inventory.allocationNonceDigest
                (Inventory.allocationAcquisitionNonce (Acquisition.acquisitionAllocation acquisition))
        runtime <-
          codec
            (verifyArsLineage expected cohort plan (Acquisition.acquisitionChildAttempt child) nonce begun origin)
        observed <-
          codec
            ( Node.runDecode
                (Phase.phaseDataPool raw)
                ( ArsRead.arsReturned
                    (Product.renderCompiledRlPlanTransport compiled)
                    config
                    c
                    runtime
                    (Phase.phaseDataRoot raw)
                )
            )
        rawFields <-
          codec (Node.runDecode (Phase.phaseDataPool raw) (Node.fields NRawArs (Phase.phaseDataRoot raw)))
        require
          (case rawFields of _ : _ : VRef actual : _ -> actual == p; _ -> False)
          "parent ARS actual initial differs from prepared theta"
        pure (Evaluation.ArsConfiguration config, c, p, [begun, origin], Observation.ReturnedArs observed)
      else do
        recipe <- mathematical (Config.resolveNeuralTrainerRecipe compiled)
        let config = Config.neuralTrainerConfiguration recipe
        c <- snapshotConfig config prepared
        canonicalConfig (Phase.phaseDataPool prepared) c config
        validateNeuralSnapshots config c child
        p <- snapshotInitial config c prepared
        observed <-
          codec
            ( Node.runDecode
                (Phase.phaseDataPool raw)
                ( NeuralRead.neuralReturned
                    (Product.renderCompiledRlPlanTransport compiled)
                    config
                    c
                    p
                    (Phase.phaseDataRoot raw)
                )
            )
        pure (Evaluation.NeuralConfiguration config, c, p, [], observed)
  first <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool initial)
          (Evaluation.returnEvaluation spec specRoot configuration configRoot (Phase.phaseDataRoot initial))
      )
  last_ <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool final)
          (Evaluation.returnEvaluation spec specRoot configuration configRoot (Phase.phaseDataRoot final))
      )
  bindEvaluationPolicies initial final raw initialRoot False
  reproject initial (Projection.projectReturnEvaluationData Graph.emptyNodePool first)
  reproject final (Projection.projectReturnEvaluationData Graph.emptyNodePool last_)
  mapM_
    ( \value -> do
        audited <- liftIO (ReturnReplay.auditReturnEvaluationData value)
        either (throwError . NativeParentPolicyProjectionRejected) pure audited
    )
    [first, last_]
  validateBudget compiled policy (returnRawEvaluation last_)
  device <- deviceFor batch acquisition child host
  pure
    ( NativeParentReturnChild
        (Acquisition.acquisitionChildIndex child)
        (Cohort.nativeRlSeedPlanSeed plan)
        first
        last_
        policy
        device
        lineage
    )

-- Absence is handled explicitly; no exception/retry or alternate execution.
effectiveSnapshot :: Acquisition.NativeAcquisitionChildData -> Program Phase.PhaseData
effectiveSnapshot child = case lookup
  (label (Acquisition.acquisitionChildIndex child) "effective")
  (Acquisition.acquisitionChildPhases child) of
  Just actual -> pure actual
  Nothing -> phaseAt "prepared" child
snapshotConfig :: Config.NeuralTrainerConfiguration -> Phase.PhaseData -> Program Digest
snapshotConfig config phase =
  codec
    ( Node.runDecode (Phase.phaseDataPool phase) $ do
        let kind = case config of
              Config.OnPolicyConfiguration _ -> NPpoSnapshot
              Config.DqnConfiguration _ -> NDqnSnapshot
              Config.QrDqnConfiguration _ -> NQrSnapshot
              Config.ContinuousConfiguration _ -> NContinuousSnapshot
              Config.HerConfiguration _ -> NHerSnapshot
        actual <- Node.fields kind (Phase.phaseDataRoot phase)
        case (config, actual) of
          (Config.ContinuousConfiguration _, _ : VRef c : _) -> pure c
          (_, VRef c : _) -> pure c
          _ -> Node.reject "parent prepared config reference absent"
    )

-- All continuous families own a real cold/effective stage, including the
-- variants whose actual warm optimizer is absent. No warm count is inferred.
validateNeuralSnapshots
  :: Config.NeuralTrainerConfiguration -> Digest -> Acquisition.NativeAcquisitionChildData -> Program ()
validateNeuralSnapshots config configRoot child = do
  prepared <- phaseAt "prepared" child
  effective <- phaseAt "effective" child
  require
    (Phase.phaseDataPhase prepared == nativeParentPreparationPhaseForConfiguration config)
    "parent prepared phase differs from its actual lower family preparation stage"
  case config of
    Config.ContinuousConfiguration c -> do
      require
        ( Phase.phaseDataPhase prepared == ColdSnapshotPhase
            && Phase.phaseDataPhase effective == EffectiveSnapshotPhase
        )
        "parent continuous preparation requires actual cold then effective phases"
      cold <-
        codec
          ( Node.runDecode
              (Phase.phaseDataPool prepared)
              (Node.fields NContinuousSnapshot (Phase.phaseDataRoot prepared))
          )
      warm <-
        codec
          ( Node.runDecode
              (Phase.phaseDataPool effective)
              (Node.fields NContinuousSnapshot (Phase.phaseDataRoot effective))
          )
      case (cold, warm) of
        (VWord 0 : VRef c0 : VRef coldActor : VRef coldActual : _, VWord 1 : VRef c1 : VRef sameCold : _) ->
          require
            (c0 == configRoot && c1 == configRoot && coldActor == coldActual && coldActor == sameCold)
            "parent continuous cold/effective recipe or cold actor binding differs"
        _ -> require False "parent continuous cold/effective snapshot field matrix differs"
      coldCount <- codec (Node.runDecode (Phase.phaseDataPool prepared) (field 25 cold >>= Node.int))
      warmCount <- codec (Node.runDecode (Phase.phaseDataPool effective) (field 25 warm >>= Node.int))
      require (coldCount == 0 && warmCount >= 0) "parent continuous actual warm count is invalid"
      coldWarm <- codec (Node.runDecode (Phase.phaseDataPool prepared) (field 13 cold))
      effectiveWarm <- codec (Node.runDecode (Phase.phaseDataPool effective) (field 13 warm))
      case (coldWarm, effectiveWarm) of
        (VNull, VNull) ->
          require
            ( warmCount == 0
                && not (Continuous.ctVariant c == Continuous.VariantSAC && Continuous.ctEnvName c == "pendulum")
            )
            "parent absent warm optimizer has a nonzero count or an applicable warm recipe"
        (VRef a, VRef b) -> do
          beforeStep <- adamStep prepared a
          afterStep <- adamStep effective b
          require
            ( beforeStep == 0
                && afterStep == warmCount
                && Continuous.ctVariant c == Continuous.VariantSAC
                && Continuous.ctEnvName c == "pendulum"
            )
            "parent actual warm Adam/count or applicable recipe differs"
        _ -> require False "parent continuous warm optimizer presence changed"
      codec
        ( Node.runDecode
            (Phase.phaseDataPool effective)
            (field 23 warm >>= Node.ref >>= frame (Continuous.ctObsSize c))
        )
    _ -> do
      before <- codec (Node.closureEntries (Phase.phaseDataRoot prepared) (Phase.phaseDataPool prepared))
      after <- codec (Node.closureEntries (Phase.phaseDataRoot effective) (Phase.phaseDataPool effective))
      require
        ( Phase.phaseDataPhase prepared == EffectiveSnapshotPhase
            && Phase.phaseDataRoot prepared == Phase.phaseDataRoot effective
            && before == after
        )
        "parent already-effective neural preparation changed its actual snapshot"
  codec
    ( Node.runDecode (Phase.phaseDataPool effective) $ case config of
        Config.OnPolicyConfiguration c -> do
          actual <- Node.fields NPpoSnapshot (Phase.phaseDataRoot effective)
          roots <-
            field 6 actual
              >>= Node.ref
              >>= Node.referenceData (AliasElement TensorAlias) (toInteger (max 1 (Ppo.ppoVectorEnvCount c)))
          Node.require
            (length roots == max 1 (Ppo.ppoVectorEnvCount c))
            "parent prepared vector frame slot count differs"
          mapM_ (frame (Ppo.ppoObsSize c)) roots
        Config.DqnConfiguration c -> oneFrame (Phase.phaseDataRoot effective) NDqnSnapshot (Dqn.dqnObsSize c)
        Config.QrDqnConfiguration c -> oneFrame (Phase.phaseDataRoot effective) NQrSnapshot (Qr.qrObsSize c)
        _ -> pure ()
    )
 where
  field n values = case drop n values of value : _ -> pure value; _ -> Node.reject "parent snapshot field absent"
  frame width root = do
    Node.require
      (width > 0 && 8 * toInteger width <= nativePhaseLimit FrameBytes)
      "parent prepared frame exceeds8MiB cap"
    values <- Node.tensor (toInteger width) root
    Node.require (VU.length values == width) "parent prepared frame does not have exact canonical width"
  oneFrame root kind width = Node.fields kind root >>= field 16 >>= Node.ref >>= frame width
  adamStep phase root =
    codec
      ( Node.runDecode (Phase.phaseDataPool phase) $ do
          actual <- Node.fields NAdam root
          field 0 actual >>= Node.int
      )

decodeHerChild
  :: Cohort.NativeRlCohortBatch
  -> Cohort.NativeRlCohortPlan
  -> Acquisition.NativeAcquisitionData
  -> HerRef.NativeHerGoalSchedule
  -> Digest
  -> Cohort.NativeRlSeedPlan
  -> Acquisition.NativeAcquisitionChildData
  -> Program NativeParentChildPolicyData
decodeHerChild batch _cohort acquisition schedule scheduleRoot plan child = do
  compiled <-
    maybe
      (throwError (NativeParentPolicyRejected (Malformed "parent HER compiled plan absent")))
      pure
      (Cohort.nativeRlSeedPlanCompiledReturn plan)
  recipe <- mathematical (Config.resolveNeuralTrainerRecipe compiled)
  let config = Config.neuralTrainerConfiguration recipe
  herConfig <- case config of
    Config.HerConfiguration actual -> pure actual
    _ -> throwError (NativeParentPolicyRejected (Malformed "parent HER canonical recipe family differs"))
  prepared <- phaseAt "effective" child
  c <- snapshotConfig config prepared
  canonicalConfig (Phase.phaseDataPool prepared) c config
  validateNeuralSnapshots config c child
  p <- snapshotInitial config c prepared
  raw <- phaseAt "raw" child
  initial <- phaseAt "initial" child
  final <- phaseAt "final" child
  policy <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool raw)
          ( NeuralRead.neuralReturned
              (Product.renderCompiledRlPlanTransport compiled)
              config
              c
              p
              (Phase.phaseDataRoot raw)
          )
      )
  first <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool initial)
          (Evaluation.herEvaluation schedule scheduleRoot herConfig c (Phase.phaseDataRoot initial))
      )
  last_ <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool final)
          (Evaluation.herEvaluation schedule scheduleRoot herConfig c (Phase.phaseDataRoot final))
      )
  bindEvaluationPolicies initial final raw p True
  reproject initial (Projection.projectHerEvaluationData Graph.emptyNodePool first)
  reproject final (Projection.projectHerEvaluationData Graph.emptyNodePool last_)
  validateBudget
    compiled
    policy
    ( Observation.HerEvaluationReturned
        [ ( HerRef.nativeHerOutcomeSuccess value
          , HerRef.nativeHerOutcomeNormalizedDistance value
          , HerRef.nativeHerOutcomeSteps value
          )
        | value <- Her.nativeHerEvaluationOutcomes last_
        ]
    )
  device <- deviceFor batch acquisition child False
  pure
    ( NativeParentHerChild
        (Acquisition.acquisitionChildIndex child)
        (Cohort.nativeRlSeedPlanSeed plan)
        first
        last_
        policy
        device
    )

decodeArenaChild
  :: Cohort.NativeRlCohortBatch
  -> Cohort.NativeRlCohortPlan
  -> Acquisition.NativeAcquisitionData
  -> ArenaRef.NativeArenaSpec
  -> Digest
  -> Tape.ArenaTape
  -> ArenaChild.NativeAlphaZeroRowData
  -> Cohort.NativeRlSeedPlan
  -> Acquisition.NativeAcquisitionChildData
  -> Program NativeParentChildPolicyData
decodeArenaChild batch _cohort acquisition spec specRoot tape rowData plan child = do
  selected <-
    either
      (mathematical . Left . ArenaChild.nativeAlphaZeroFailureDetail)
      pure
      (ArenaChild.selectNativeAlphaZeroChildData rowData (Cohort.nativeRlSeedPlanIndex plan))
  prepared <- phaseAt "prepared" child
  raw <- phaseAt "raw" child
  initial <- phaseAt "initial" child
  final <- phaseAt "final" child
  preparedFields <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool prepared)
          (Node.fields NAlphaZeroSnapshot (Phase.phaseDataRoot prepared))
      )
  observed <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool raw)
          (ArenaRaw.arenaRaw selected preparedFields (Phase.phaseDataRoot raw))
      )
  first <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool initial)
          (Evaluation.arenaEvaluation spec specRoot tape (Phase.phaseDataRoot initial))
      )
  last_ <-
    codec
      ( Node.runDecode
          (Phase.phaseDataPool final)
          (Evaluation.arenaEvaluation spec specRoot tape (Phase.phaseDataRoot final))
      )
  bindEvaluationPolicies initial final raw (Phase.phaseDataRoot prepared) False
  reproject initial (Projection.projectArenaEvaluationData Graph.emptyNodePool first)
  reproject final (Projection.projectArenaEvaluationData Graph.emptyNodePool last_)
  device <- deviceFor batch acquisition child False
  pure
    ( NativeParentArenaChild
        (Acquisition.acquisitionChildIndex child)
        (Cohort.nativeRlSeedPlanSeed plan)
        first
        last_
        observed
        device
    )

-- These checks use the actual typed root fields; no complete-status bit is
-- accepted as policy/snapshot/return correspondence proof.
bindEvaluationPolicies
  :: Phase.PhaseData -> Phase.PhaseData -> Phase.PhaseData -> Digest -> Bool -> Program ()
bindEvaluationPolicies initial final raw initialPolicy her = do
  rawNode <-
    codec
      ( maybe
          (Left (MissingReference (Phase.phaseDataRoot raw)))
          Right
          (Graph.lookupNode (Phase.phaseDataRoot raw) (Phase.phaseDataPool raw))
      )
  (first, last_) <- case (Schema.nodeKind rawNode, Schema.nodeFields rawNode) of
    (NRawNeural, _ : _ : _ : VRef expected : _ : VRef actual : VRef returned : _) -> do
      require
        (expected == initialPolicy && actual == initialPolicy)
        "parent actual/expected raw initial differs"
      pure (initialPolicy, returned)
    (NRawArs, _ : _ : VRef actual : VRef returned : _) -> require (actual == initialPolicy) "parent ARS raw initial differs" >> pure (actual, returned)
    (NRawAlphaZero, _ : VRef firstNet : _ : VRef lastNet : _) -> pure (firstNet, lastNet)
    _ -> throwError (NativeParentPolicyRejected (Malformed "parent raw policy reference matrix differs"))
  zipWithM_
    ( \phase expected -> do
        root <-
          codec
            ( Node.runDecode (Phase.phaseDataPool phase) $ do
                node <-
                  maybe
                    (Node.liftData (Left (MissingReference (Phase.phaseDataRoot phase))))
                    pure
                    (Graph.lookupNode (Phase.phaseDataRoot phase) (Phase.phaseDataPool phase))
                case (Schema.nodeKind node, Schema.nodeFields node) of
                  (NHerEvaluation, _ : _ : VRef p : _) | her -> pure p
                  (NReturnEvaluation, _ : VRef policy : _) -> do
                    fields_ <- Node.fields NReturnPolicy policy
                    case fields_ of [_, _, VRef p] -> pure p; _ -> Node.reject "parent RETURN policy reference absent"
                  (NArenaEvaluation, VRef input : _) -> do
                    fields_ <- Node.fields NArenaInput input
                    case fields_ of
                      [_, _, _, _, VRef p] -> pure p
                      _ -> Node.reject "parent arena policy reference absent"
                  _ -> Node.reject "parent initial/final evaluation policy kind differs"
            )
        require
          (root == expected)
          "parent evaluation did not score its exact prepared initial or actual returned final policy"
    )
    [initial, final]
    [first, last_]

returnRawEvaluation :: Return.RawNativeReturnEvaluation -> Observation.RawEvaluation
returnRawEvaluation actual =
  Observation.EvaluationReturned
    [ Episode.SimulatedEpisode
        (ReturnRef.nativeReturnEpisodeId value)
        (ReturnRef.nativeReturnEpisodeSteps value)
        (ReturnRef.nativeReturnEpisodeReward value)
        (ReturnRef.nativeReturnEpisodeTerminated value)
        []
    | value <- Return.nativeEvaluationEpisodes actual
    ]
validateBudget
  :: Product.CompiledRlPlan -> Observation.ReturnedPolicy -> Observation.RawEvaluation -> Program ()
validateBudget plan policy evaluation = do
  _ <-
    mathematical
      ( Observation.refineBudgetCompleteTrainerObservation
          (Observation.RawTrainerObservation plan policy evaluation)
      )
  pure ()
returnObservation :: NativeParentChildPolicyData -> Program ReturnPolicy.NativeReturnSeedObservation
returnObservation (NativeParentReturnChild index seed initial final _ _ _) =
  pure
    ( ReturnPolicy.NativeReturnSeedObservation
        index
        seed
        (Return.nativeEvaluationEpisodes initial)
        (Return.nativeEvaluationEpisodes final)
    )
returnObservation _ = throwError (NativeParentPolicyRejected (Malformed "parent RETURN family mismatch"))
herObservation :: NativeParentChildPolicyData -> Program HerPolicy.NativeHerSeedObservation
herObservation (NativeParentHerChild index seed initial final _ _) = pure (HerPolicy.NativeHerSeedObservation index seed initial final)
herObservation _ = throwError (NativeParentPolicyRejected (Malformed "parent HER family mismatch"))
arenaObservation :: NativeParentChildPolicyData -> Program ArenaPolicy.NativeArenaSeedObservation
arenaObservation (NativeParentArenaChild index seed initial final _ _) = pure (ArenaPolicy.NativeArenaSeedObservation index seed initial final)
arenaObservation _ = throwError (NativeParentPolicyRejected (Malformed "parent arena family mismatch"))
