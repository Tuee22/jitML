{-# LANGUAGE OverloadedStrings #-}

-- | Recorded graph equality and original identity DATA. This deliberately
-- does not call the same-host numerical Policy verifier or any evaluator.
module JitML.Test.NativeLaneBundle.Recorded
  ( checkRecordedEvaluationClosure
  , checkRecordedServingWeights
  , checkRecordedServingTrace
  ) where

import Control.Monad (unless, void, when, zipWithM_)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as LBS
import Data.Either.Combinators (mapLeft)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Vector.Unboxed qualified as VU
import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativeParentBindingData qualified as Binding
import JitML.Checkpoint.NativeParentEvaluationSummaryData qualified as Summary
import JitML.Checkpoint.NativeParentPolicyData.Lineage qualified as Lineage
import JitML.Checkpoint.NativeParentPolicyData.Node qualified as Node
import JitML.Checkpoint.NativePhase.Codec qualified as Phase
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Projection qualified as Projection
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReferences qualified as References
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetentionReader qualified as Envelope
import JitML.Checkpoint.WeightCodec qualified as Weight
import JitML.Execution.ProducerObservation qualified as Process
import JitML.Numerics.Mlp qualified as Mlp
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.DeviceWitness qualified as Witness
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeParentExecution qualified as Parent
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.RL.ArsHostTrace qualified as Trace
import JitML.RL.ProductBudget qualified as Product
import JitML.Substrate (renderSubstrate)
import JitML.Test.NativeScenarioReceiptData qualified as Receipt
import JitML.Training.Budget qualified as Training

-- The installed base list API has no drop1; retain the existing total drop.
{- HLINT ignore checkRecordedEvaluationClosure "Use drop1" -}
checkRecordedEvaluationClosure
  :: Cohort.NativeRlCohortBatch
  -> Receipt.NativeScenarioReceiptData
  -> Binding.NativeParentBindingData
  -> Either CodecError ()
checkRecordedEvaluationClosure batch receipt binding = do
  let acquisition = Binding.nativeParentBindingAcquisition binding
      children = Acquisition.acquisitionChildren acquisition
      cohort = Binding.nativeParentBindingCohort binding
      plans = Cohort.nativeRlCohortPlanChildren cohort
      metadata = Metadata.nativeQualificationReceiptFields (Binding.nativeParentBindingMetadata binding)
      source = Parent.nativeParentRequestSource (Receipt.nativeScenarioReceiptRequest receipt)
      rawReference = Reference.nativeQualificationReferenceData (Receipt.nativeScenarioReceiptReference receipt)
      association =
        Context.SuppliedScenarioContext
          (Parent.nativeParentRequestInvocation (Receipt.nativeScenarioReceiptRequest receipt))
      sources =
        Context.NativeContextSources
          (Metadata.nativeReceiptObservedSource metadata)
          (Metadata.nativeReceiptSuppliedSource metadata)
      replays = Binding.nativeParentBindingReplays binding
  executable <- Context.digestFromCanonicalText (Reference.nativeReferenceExecutable rawReference)
  allocation <-
    Context.digestFromCanonicalText
      (Reference.nativeReferenceAllocationSha rawReference)
  let expected =
        Lineage.NativeParentExpectations
          source
          executable
          association
          sources
          ( Receipt.nativeScenarioReceiptProcessId receipt
          , Receipt.nativeScenarioReceiptParentProcessId receipt
          )
  require
    ( map Acquisition.acquisitionChildIndex children == [0 .. 4]
        && length plans == 5
        && length replays == 11
    )
    "portable native bundle lacks the original five children and eleven replays"
  zipWithM_ (checkChildProducers expected batch cohort) plans children
  zipWithM_
    (bindReplay allocation acquisition)
    ( [(i, stage) | i <- [0 .. 4], stage <- [Replay.InitialModelReplay, Replay.FinalModelReplay]]
        <> [(0, Replay.StoredFinalModelReplay)]
    )
    replays
  case (drop 1 replays, drop 10 replays) of
    (original : _, [stored]) ->
      require
        ( Replay.nativeReplayObjectRoot stored == Replay.nativeReplayObjectRoot original
            && Replay.nativeReplayObjectEntries stored == Replay.nativeReplayObjectEntries original
        )
        "portable stored-final is not the exact original serving final graph"
    _ -> Left (Malformed "portable serving replay positions differ")
  devices <- traverse (childDevice batch acquisition cohort expected) (zip plans children)
  let expectedDevices =
        concatMap (\device -> [device, device]) devices
          <> case devices of first : _ -> [first]; [] -> []
      isArena = Matrix.family (Cohort.nativeRlCohortPlanRow cohort) == Matrix.AlphaZero
  referenceRoot <-
    if isArena
      then
        Just
          <$> Context.digestFromCanonicalText
            (sha256Hex (References.nativeReferenceDataBytes (Acquisition.acquisitionReferences acquisition)))
      else Right Nothing
  Summary.checkNativeParentEvaluationSummaryData
    replays
    expectedDevices
    referenceRoot
    (Receipt.nativeScenarioReceiptEvaluationSummary receipt)

bindReplay
  :: Digest
  -> Acquisition.NativeAcquisitionData
  -> (Int, Replay.NativeReplayObjectStage)
  -> Replay.NativeReplayObjectData
  -> Either CodecError ()
bindReplay allocation acquisition (index, stage) replay = do
  child <-
    maybe
      (Left (Malformed "portable replay child is absent"))
      Right
      (find ((== index) . Acquisition.acquisitionChildIndex) (Acquisition.acquisitionChildren acquisition))
  require
    ( Replay.nativeReplayObjectIndex replay == fromIntegral index
        && Replay.nativeReplayObjectStage replay == stage
        && Replay.nativeReplayObjectAllocation replay == allocation
        && Replay.nativeReplayObjectAttempt replay == Acquisition.acquisitionChildAttempt child
    )
    "portable replay allocation attempt stage or index differs"
  phase <- childPhase (if stage == Replay.InitialModelReplay then "initial" else "final") child
  entries <- Node.closureEntries (Phase.phaseDataRoot phase) (Phase.phaseDataPool phase)
  require
    ( Replay.nativeReplayObjectRoot replay == Phase.phaseDataRoot phase
        && Replay.nativeReplayObjectEntries replay == entries
    )
    "portable replay differs from the complete physical source evaluation bytes"

checkChildProducers
  :: Lineage.NativeParentExpectations
  -> Cohort.NativeRlCohortBatch
  -> Cohort.NativeRlCohortPlan
  -> Cohort.NativeRlSeedPlan
  -> Acquisition.NativeAcquisitionChildData
  -> Either CodecError ()
checkChildProducers expected batch cohort plan child = do
  originals <- traverse one (Acquisition.acquisitionChildPhases child)
  case originals of
    first : rest ->
      mapM_
        ( \actual ->
            require
              (Process.compareRecordedProducerObservationData first actual == Right ())
              "portable child phase original process/source identity changed"
        )
        rest
    [] -> Left (Malformed "portable child has no phase records")
  final <- childPhase "after-process" child
  producer <- contextProducer final
  (_, after) <- Lineage.decodeProducerBundle (Phase.phaseDataPool final) producer
  require
    (case after of Just _ -> True; Nothing -> False)
    "portable child has no original after-process observation"
 where
  one (_, phase) = do
    producer <- contextProducer phase
    acquisition <- case drop 12 (Schema.contextFields (Phase.phaseDataContext phase)) of
      VDigest value : _ -> Right value
      _ -> Left (Malformed "portable phase acquisition identity is absent")
    context <-
      Context.nativePhaseContextValues
        batch
        (Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort))
        (Cohort.nativeRlSeedPlanIndex plan)
        (Lineage.nativeParentExpectedAssociation expected)
        (Lineage.nativeParentExpectedSources expected)
        (Acquisition.acquisitionChildAttempt child)
        acquisition
        producer
    require
      (Schema.contextFields (Phase.phaseDataContext phase) == context)
      "portable full phase context differs from current canonical association"
    (before, after) <- Lineage.decodeProducerBundle (Phase.phaseDataPool phase) producer
    original <- maybe (Left (Malformed "portable phase before-process is absent")) Right before
    Lineage.verifyProducer expected original
    case after of
      Nothing -> pure ()
      Just actual -> do
        Lineage.verifyProducer expected actual
        require
          (Process.compareRecordedProducerObservationData original actual == Right ())
          "portable original before/after full process/source DATA differs"
    pure original

childDevice
  :: Cohort.NativeRlCohortBatch
  -> Acquisition.NativeAcquisitionData
  -> Cohort.NativeRlCohortPlan
  -> Lineage.NativeParentExpectations
  -> (Cohort.NativeRlSeedPlan, Acquisition.NativeAcquisitionChildData)
  -> Either CodecError (Maybe Witness.RawDeviceExecutionWitness)
childDevice batch acquisition cohort expected (plan, child) = do
  let host =
        maybe
          False
          ((== "ars") . Product.compiledRlTrainerKind)
          (Cohort.nativeRlSeedPlanCompiledReturn plan)
  bytes <- dedicated acquisition child "device-observation"
  device <- Lineage.verifyDevice (Cohort.nativeRlCohortBatchSubstrate batch) host bytes
  when host $ do
    begun <- dedicated acquisition child "ars-begun" >>= Lineage.decodeArsLineage False
    origin <- dedicated acquisition child "ars-origin" >>= Lineage.decodeArsLineage True
    final <- childPhase "after-process" child
    acquisitionDigest <- case drop 12 (Schema.contextFields (Phase.phaseDataContext final)) of
      VDigest value : _ -> Right value
      _ -> Left (Malformed "portable ARS acquisition identity is absent")
    void $
      Lineage.verifyArsLineage
        expected
        cohort
        plan
        (Acquisition.acquisitionChildAttempt child)
        acquisitionDigest
        begun
        origin
  pure
    ( case device of
        Lineage.NativeHostNoMlpData -> Nothing
        Lineage.NativeRecordedDeviceData value -> Just value
    )

-- The physical serving trace is a second recorded object. Bind its entire
-- context/runtime to the same dedicated original lineage, then project its
-- actual retained observation and compare every reachable canonical raw node.
-- Projection performs no Gaussian replay, trainer step or evaluator call.
checkRecordedServingTrace
  :: Receipt.NativeScenarioReceiptData
  -> Binding.NativeParentBindingData
  -> Maybe Trace.ArsHostTrace
  -> IO (Either CodecError ())
checkRecordedServingTrace receipt binding supplied =
  case expected of
    Left problem -> pure (Left problem)
    Right Nothing -> pure (Right ())
    Right (Just (compiled, child, trace)) -> do
      projected <-
        Projection.projectArsReturnedData
          Graph.emptyNodePool
          compiled
          (Trace.arsHostTraceObservation trace)
      pure $ do
        (root, pool) <- mapLeft (Malformed . Text.pack . show) projected
        raw <- childPhase "raw" child
        actualEntries <- Node.closureEntries root pool
        expectedEntries <- Node.closureEntries (Phase.phaseDataRoot raw) (Phase.phaseDataPool raw)
        require
          (root == Phase.phaseDataRoot raw && actualEntries == expectedEntries)
          "portable physical ARS trace differs from the complete original raw iteration graph"
 where
  expected = do
    let acquisition = Binding.nativeParentBindingAcquisition binding
        cohort = Binding.nativeParentBindingCohort binding
        plan = Cohort.nativeRlCohortServingChild cohort
        compiled = Cohort.nativeRlSeedPlanCompiledReturn plan
        host = maybe False ((== "ars") . Product.compiledRlTrainerKind) compiled
    if not host
      then do
        require
          (case supplied of Nothing -> True; _ -> False)
          "portable non-ARS snapshot contains a host trace"
        pure Nothing
      else do
        actualPlan <- maybe (Left (Malformed "portable serving ARS recipe is absent")) Right compiled
        trace <- maybe (Left (Malformed "portable serving ARS physical trace is absent")) Right supplied
        child <- case Acquisition.acquisitionChildren acquisition of
          first : _ | Acquisition.acquisitionChildIndex first == 0 -> Right first
          _ -> Left (Malformed "portable serving ARS child0 is absent")
        begun <- dedicated acquisition child "ars-begun" >>= Lineage.decodeArsLineage False
        origin <- dedicated acquisition child "ars-origin" >>= Lineage.decodeArsLineage True
        let before = Lineage.nativeLineageBefore origin
            request = Receipt.nativeScenarioReceiptRequest receipt
            singleton = Cohort.nativeRlSeedPlanSingleton plan
            context =
              Trace.RawArsHostContext
                { Trace.rawArsHostRowId = Matrix.rowId (Cohort.nativeRlCohortPlanRow cohort)
                , Trace.rawArsHostExperiment = Singleton.nativeSingletonExperiment singleton
                , Trace.rawArsHostPlanId = Plan.planIdText (Singleton.nativeSingletonPlanId singleton)
                , Trace.rawArsHostCompiledTransport = Product.renderCompiledRlPlanTransport actualPlan
                , Trace.rawArsHostLane = renderSubstrate (Singleton.nativeSingletonSubstrate singleton)
                , Trace.rawArsHostSourceSha256 = Source.stampSha256 (Parent.nativeParentRequestSource request)
                , Trace.rawArsHostExecutableSha256 = Process.recordedExecutableFileSha256 before
                , Trace.rawArsHostInvocationSha256 =
                    Training.productScenarioInvocationDigest (Parent.nativeParentRequestInvocation request)
                , Trace.rawArsHostExecutionBinding = "product-scenario-invocation-v1"
                , Trace.rawArsHostKernelOS = Process.recordedKernelOperatingSystem before
                , Trace.rawArsHostKernelMachine = Process.recordedKernelMachine before
                , Trace.rawArsHostKernelRelease = Process.recordedKernelRelease before
                , Trace.rawArsHostSimulatorContract =
                    "jitml-known-discrete-simulator-ars-v1:" <> Product.compiledRlEnvironment actualPlan
                , Trace.rawArsHostProcessId = Text.pack (show (Process.recordedProcessId before))
                , Trace.rawArsHostAttemptId = Lineage.nativeLineageInnerAttempt origin
                }
        require
          ( Lineage.nativeLineageInnerAttempt begun == Lineage.nativeLineageInnerAttempt origin
              && Trace.arsHostContextToRaw (Trace.arsHostTraceContext trace) == context
              && Lineage.nativeLineageRuntime origin == Just (Trace.arsHostTraceRuntime trace)
          )
          "portable physical ARS trace context/runtime differs from original serving lineage"
        pure (Just (actualPlan, child, trace))

-- Direct final bytes comparison preserves every binary64 payload, including
-- signed zero. It performs no forward pass or reinitialization.
checkRecordedServingWeights :: Binding.NativeParentBindingData -> ByteString -> Either CodecError ()
checkRecordedServingWeights binding jmw1 = do
  child <- case Acquisition.acquisitionChildren (Binding.nativeParentBindingAcquisition binding) of
    first : _ | Acquisition.acquisitionChildIndex first == 0 -> Right first
    _ -> Left (Malformed "portable serving child0 is absent")
  raw <- childPhase "raw" child
  values <- Node.runDecode (Phase.phaseDataPool raw) $ do
    node <-
      maybe
        (Node.reject "portable raw root is absent")
        pure
        (Graph.lookupNode (Phase.phaseDataRoot raw) (Phase.phaseDataPool raw))
    case (Schema.nodeKind node, Schema.nodeFields node) of
      ( NRawNeural
        , [ _family
            , _transport
            , _expectedConfig
            , _expectedInitial
            , _actualConfig
            , _actualInitial
            , VRef final
            , _stats
            , _transitions
            , _updates
            ]
        ) ->
          Mlp.mlpParamsToFlat <$> Node.parameters final
      (NRawArs, [_transport, _config, _initial, VRef final, _iterations, _transitions, _updates]) ->
        VU.toList <$> Node.tensor (nativePhaseLimit AggregateF64Coordinates) final
      ( NRawAlphaZero
        , [ _state
            , _initialNet
            , _initialAdam
            , VRef finalNet
            , _finalAdam
            , _samples
            , _count
            , _target
            , _games
            , _simulations
            , _plies
            , _updates
            , _seed
            ]
        ) -> do
          fields <- Node.fields NPVN finalNet
          case fields of
            [VRef params, _actions, _observations] -> Mlp.mlpParamsToFlat <$> Node.parameters params
            _ -> Node.reject "portable raw final PVN field matrix differs"
      _ -> Node.reject "portable raw return family field matrix differs"
  require
    (LBS.toStrict (Weight.encodeJmw1 values) == jmw1)
    "portable original serving raw parameters differ from exact physical JMW1 bytes"

childPhase :: Text -> Acquisition.NativeAcquisitionChildData -> Either CodecError Phase.PhaseData
childPhase suffix child =
  maybe
    (Left (Malformed "portable child phase is absent"))
    Right
    (lookup (label child suffix) (Acquisition.acquisitionChildPhases child))
dedicated
  :: Acquisition.NativeAcquisitionData
  -> Acquisition.NativeAcquisitionChildData
  -> Text
  -> Either CodecError ByteString
dedicated acquisition child suffix =
  maybe
    (Left (Malformed "portable dedicated child record is absent"))
    (Right . Envelope.decodedPhasePayload)
    ( find
        ((== label child suffix) . Envelope.decodedPhaseLabel)
        (Acquisition.acquisitionPhases acquisition)
    )
label :: Acquisition.NativeAcquisitionChildData -> Text -> Text
label child suffix = "child" <> Text.pack (show (Acquisition.acquisitionChildIndex child)) <> "." <> suffix
contextProducer :: Phase.PhaseData -> Either CodecError Digest
contextProducer phase = case reverse (Schema.contextFields (Phase.phaseDataContext phase)) of
  VRef value : _ -> Right value
  _ -> Left (Malformed "portable phase producer root is absent")
require :: Bool -> Text -> Either CodecError ()
require condition message = unless condition (Left (Malformed message))
