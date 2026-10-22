{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary complete-acquisition DATA checks. Callers supply physical bytes;
-- this module performs no fetch, training, ACK, origin or authentication. A
-- successful value cannot restore a producer, cursor, candidate or publication.
module JitML.Checkpoint.NativeAcquisitionData
  ( NativeAcquisitionData
  , NativeAcquisitionDataError (..)
  , NativeAcquisitionChildData
  , checkNativeAcquisitionData
  , acquisitionAllocation
  , acquisitionReferences
  , acquisitionPhases
  , acquisitionChildren
  , acquisitionChildIndex
  , acquisitionChildAttempt
  , acquisitionChildPhases
  ) where

import Control.Monad (replicateM, unless, when, zipWithM)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (find)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativePhase.CBOR qualified as Wire
import JitML.Checkpoint.NativePhase.Codec qualified as Phase
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Graph qualified as Graph
import JitML.Checkpoint.NativePhase.Schema qualified as Schema
import JitML.Checkpoint.NativePhase.Types
import JitML.Checkpoint.NativeReferences qualified as References
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.NativeRetentionReader qualified as Envelope
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.NativeRlProducer.Inventory qualified as Inventory
import JitML.Training.Budget qualified as Training

data NativeAcquisitionDataError
  = NativeAcquisitionDataRejected !Text
  | NativeAcquisitionDataCodec !CodecError
  | NativeAcquisitionDataEnvelope !Envelope.NativeRetentionEnvelopeError
  deriving stock (Eq, Show)

data NativeAcquisitionChildData
  = NativeAcquisitionChildData
      !Int
      !Digest
      ![(Text, Phase.PhaseData)]

data NativeAcquisitionData
  = NativeAcquisitionData
      !Inventory.NativeAllocationData
      !References.NativeReferenceData
      ![Envelope.NativeDecodedRetentionPhase]
      ![NativeAcquisitionChildData]

data ChildKind = NeuralChildKind !Bool | HostChildKind | ArenaChildKind

acquisitionAllocation :: NativeAcquisitionData -> Inventory.NativeAllocationData
acquisitionAllocation (NativeAcquisitionData actual _ _ _) = actual
acquisitionReferences :: NativeAcquisitionData -> References.NativeReferenceData
acquisitionReferences (NativeAcquisitionData _ actual _ _) = actual
acquisitionPhases :: NativeAcquisitionData -> [Envelope.NativeDecodedRetentionPhase]
acquisitionPhases (NativeAcquisitionData _ _ actual _) = actual
acquisitionChildren :: NativeAcquisitionData -> [NativeAcquisitionChildData]
acquisitionChildren (NativeAcquisitionData _ _ _ actual) = actual
acquisitionChildIndex :: NativeAcquisitionChildData -> Int
acquisitionChildIndex (NativeAcquisitionChildData actual _ _) = actual
acquisitionChildAttempt :: NativeAcquisitionChildData -> Digest
acquisitionChildAttempt (NativeAcquisitionChildData _ actual _) = actual
acquisitionChildPhases :: NativeAcquisitionChildData -> [(Text, Phase.PhaseData)]
acquisitionChildPhases (NativeAcquisitionChildData _ _ actual) = actual

-- The explicit list is the entire selected chain, in ordinal order, excluding
-- the claim and including reference prelude and terminal. Exhaustiveness of a
-- parent's issued invocations remains an independent authenticated obligation.
checkNativeAcquisitionData
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> Context.NativeContextAssociation
  -> Context.NativeContextSources
  -> Retain.NativeRetainedObjectData
  -> ByteString
  -> [(Retain.NativeRetainedObjectData, ByteString)]
  -> Either NativeAcquisitionDataError NativeAcquisitionData
checkNativeAcquisitionData batch row association sources claimObject claimBytes objects = do
  _ <- codec (boundedLength AggregateSequenceElements 128 objects)
  checked <-
    rejected
      ( Cohort.refineNativeRlCohortBatch
          (Cohort.nativeRlCohortBatchSubstrate batch)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  require (checked == batch) "acquisition complete canonical batch differs"
  cohort <-
    maybe
      (Left (NativeAcquisitionDataRejected "acquisition row is absent from whole canonical batch"))
      Right
      ( find
          ((== row) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  kind <- childKind (Cohort.nativeRlCohortPlanRow cohort)
  claim <- envelope (Envelope.decodeNativeAllocationEnvelope claimObject claimBytes)
  allocation <- codec (Inventory.decodeNativeAllocationData (Envelope.decodedAllocationPayload claim))
  let acquisition = Inventory.allocationNonceDigest (Inventory.allocationAcquisitionNonce allocation)
      producer = Inventory.allocationProducerRoot allocation
      scope = Envelope.decodedAllocationScope claim
  checkScope cohort row acquisition association sources scope
  planned <-
    zipWithM
      (checkPlanned acquisition producer)
      Cohort.nativeSeedIndices
      (Inventory.allocationChildren allocation)
  phases <-
    traverse
      (\(object, bytes) -> envelope (Envelope.decodeNativeRetentionPhaseEnvelope object bytes))
      objects
  let references = fmap fst objects
      keys = fmap Retain.nativeRetainedObjectKey references
      expectedLabels = ["reference-calibration"] <> concatMap (childLabels kind) [0 .. 4] <> ["cohort-terminal"]
  require
    (length phases == length expectedLabels && fmap Envelope.decodedPhaseLabel phases == expectedLabels)
    "acquisition full reference child and terminal chronology differs"
  require (Set.size (Set.fromList keys) == length keys) "acquisition repeats a physical phase address"
  mapM_
    ( \(ordinal, previous, phase) ->
        envelope
          (Envelope.validateNativeRetentionPhaseLink claim previous ordinal phase)
    )
    (zip3 [0 ..] (claimObject : references) phases)
  case phases of
    referencePhase : rest -> do
      referenceData <-
        codec (References.decodeNativeReferenceData (Envelope.decodedPhasePayload referencePhase))
      checkReferenceRow (Cohort.nativeRlCohortPlanRow cohort) referenceData
      require
        ( References.nativeReferenceDataCohortId referenceData
            == Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)
            && References.nativeReferenceDataCohortTransport referenceData
              == Cohort.nativeRlCohortPlanTransport cohort
        )
        "acquisition reference prelude differs from the complete canonical cohort"
      (children, terminal) <- readChildren referenceData kind planned rest
      codec (checkTerminal (Inventory.allocationChildren allocation) children terminal)
      pure (NativeAcquisitionData allocation referenceData phases (fmap fst children))
    [] -> Left (NativeAcquisitionDataRejected "acquisition has no actual reference prelude")
 where
  checkPlanned acquisition producer index child = do
    let attempt = Inventory.attemptNonceDigest (Inventory.allocationChildNonce child)
    expected <-
      codec
        (Context.nativePhaseContextValues batch row index association sources attempt acquisition producer)
    require
      (Schema.contextFields (Inventory.allocationChildContext child) == expected)
      "acquisition allocated child differs from its full current plan context"
    pure (index, attempt, acquisition)
  readChildren referenceData kind planned phases = go planned phases []
   where
    go [] [terminal] accumulated = pure (reverse accumulated, terminal)
    go ((index, attempt, acquisition) : remaining) pending accumulated = do
      let ordinal = Cohort.nativeSeedIndexValue index
          labels = childLabels kind ordinal
          (selected, rest) = splitAt (length labels) pending
      decoded <- traverse (checkPhase referenceData kind index attempt acquisition) selected
      let typed = [(Envelope.decodedPhaseLabel phase, actual) | (phase, Just actual) <- zip selected decoded]
      firstFinal <-
        maybe
          (Left (NativeAcquisitionDataRejected "acquisition child final phase is absent"))
          Right
          (lookup (childPrefix ordinal <> "final") typed)
      lastFinal <-
        maybe
          (Left (NativeAcquisitionDataRejected "acquisition child after-process phase is absent"))
          Right
          (lookup (childPrefix ordinal <> "after-process") typed)
      require
        (Phase.phaseDataRoot firstFinal == Phase.phaseDataRoot lastFinal)
        "acquisition after-process body differs from the same child's final body"
      go
        remaining
        rest
        ( (NativeAcquisitionChildData ordinal attempt typed, fmap Envelope.decodedPhaseObject selected)
            : accumulated
        )
    go _ _ _ = Left (NativeAcquisitionDataRejected "acquisition terminal or child count differs")
  checkPhase referenceData kind index attempt acquisition phase = do
    let label = Envelope.decodedPhaseLabel phase
        suffix = Text.drop (Text.length (childPrefix (Cohort.nativeSeedIndexValue index))) label
    case expectedPhase kind suffix of
      Nothing -> pure Nothing -- Dedicated device/ARS DATA is retained verbatim.
      Just expectedTag -> do
        actual <- codec (Phase.decodePhaseData (Envelope.decodedPhasePayload phase))
        require
          (Phase.phaseDataPhase actual == expectedTag)
          "acquisition phase tag differs from its ordered phase label"
        previous <- codec (Context.digestFromCanonicalText (Envelope.decodedPhasePreviousSha256 phase))
        require
          (Phase.phaseDataPrevious actual == Just previous)
          "acquisition child DATA predecessor differs from its physical envelope predecessor"
        producer <- contextProducer (Phase.phaseDataContext actual)
        expected <-
          codec
            (Context.nativePhaseContextValues batch row index association sources attempt acquisition producer)
        require
          (Schema.contextFields (Phase.phaseDataContext actual) == expected)
          "acquisition phase whole plan context or original attempt differs"
        when (suffix `elem` ["initial", "final", "after-process"]) $ do
          spec <- evaluationSpec actual
          require
            (spec == References.nativeReferenceDataSpecRoot referenceData)
            "acquisition evaluation uses different fixed cases from the reference prelude"
        pure (Just actual)

checkScope
  :: Cohort.NativeRlCohortPlan
  -> Text
  -> Digest
  -> Context.NativeContextAssociation
  -> Context.NativeContextSources
  -> Retain.NativeAllocationScope
  -> Either NativeAcquisitionDataError ()
checkScope cohort row acquisition association sources scope = do
  require
    ( Retain.nativeAllocationRow scope == row
        && Retain.nativeAllocationRecipeSha256 scope == Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)
    )
    "acquisition scope row or complete cohort identity differs"
  source <- case (Context.nativeContextObservedSource sources, Context.nativeContextSuppliedSource sources) of
    (Just actual, _) -> pure actual
    (_, Just actual) -> pure actual
    _ ->
      Left (NativeAcquisitionDataRejected "acquisition has no selected observed or supplied source DATA")
  require
    (Retain.nativeAllocationSource scope == source)
    "acquisition scope source differs from its actual selected coverage DATA"
  case association of
    Context.DirectLocalContext actual -> do
      require (actual == acquisition) "acquisition direct context differs from its recorded nonce digest"
      case Retain.nativeAllocationContext scope of
        Retain.NativeDirectLocalAcquisition identity -> do
          value <- codec (Context.digestFromCanonicalText identity)
          require
            (value == acquisition && Retain.nativeAllocationAcquisitionId scope == identity)
            "acquisition direct fixed address differs from its recorded identity"
        _ -> Left (NativeAcquisitionDataRejected "acquisition direct context was relabeled as supplied")
    Context.SuppliedScenarioContext invocation -> do
      let identity = Training.productScenarioInvocationDigest invocation
      require
        ( Retain.nativeAllocationContext scope == Retain.NativeSuppliedScenarioDigest identity
            && Retain.nativeAllocationAcquisitionId scope == identity
        )
        "acquisition supplied context differs from its fixed original invocation slot"

contextProducer :: Schema.ContextData -> Either NativeAcquisitionDataError Digest
contextProducer actual = case reverse (Schema.contextFields actual) of
  VRef producer : _ -> pure producer
  _ -> Left (NativeAcquisitionDataRejected "acquisition phase has no recorded producer bundle")

evaluationSpec :: Phase.PhaseData -> Either NativeAcquisitionDataError Digest
evaluationSpec phase = do
  root <- node (Phase.phaseDataRoot phase)
  case (Schema.nodeKind root, Schema.nodeFields root) of
    (NReturnEvaluation, VRef spec : _) -> pure spec
    (NHerEvaluation, VRef schedule : _) -> pure schedule
    (NArenaEvaluation, VRef input : _) -> do
      actual <- node input
      case (Schema.nodeKind actual, Schema.nodeFields actual) of
        (NArenaInput, _ : VRef spec : _) -> pure spec
        _ -> Left (NativeAcquisitionDataRejected "acquisition arena evaluation has no complete fixed spec")
    _ -> Left (NativeAcquisitionDataRejected "acquisition evaluation body kind differs")
 where
  node digest =
    maybe
      (Left (NativeAcquisitionDataRejected "acquisition evaluation reference is missing"))
      Right
      (Graph.lookupNode digest (Phase.phaseDataPool phase))

-- These are family/row anchors only. The subsequent semantic replay still
-- owns whole canonical spec/schedule/tape, arithmetic and source authentication.
checkReferenceRow
  :: Matrix.ProductRow state
  -> References.NativeReferenceData
  -> Either NativeAcquisitionDataError ()
checkReferenceRow row references = do
  root <-
    maybe
      (Left (NativeAcquisitionDataRejected "acquisition reference spec root is absent"))
      Right
      (Graph.lookupNode (References.nativeReferenceDataSpecRoot references) pool)
  case ( Matrix.rowClass row
       , References.nativeReferenceDataFamily references
       , Schema.nodeKind root
       , Schema.nodeFields root
       ) of
    ( Matrix.RlAlgorithmEnvironment algorithm environment
      , References.ReturnReferenceFamily
      , NReturnSpec
      , VText identity : VText observedAlgorithm : VText observedEnvironment : _
      ) ->
        require
          (identity == Matrix.rowId row && algorithm == observedAlgorithm && environment == observedEnvironment)
          "acquisition RETURN reference row algorithm or environment differs"
    (Matrix.RlGoalConditioned _, References.HerReferenceFamily, NHerSchedule, VRef spec : _) -> do
      actual <-
        maybe
          (Left (NativeAcquisitionDataRejected "acquisition HER spec is absent"))
          Right
          (Graph.lookupNode spec pool)
      case (Schema.nodeKind actual, Schema.nodeFields actual) of
        (NHerSpec, VText identity : _) -> require (identity == Matrix.rowId row) "acquisition HER reference row differs"
        _ -> Left (NativeAcquisitionDataRejected "acquisition HER reference spec kind differs")
    (Matrix.AlphaZeroGame game, References.ArenaReferenceFamily, NArenaSpec, VText identity : _) ->
      require
        (identity == game && identity == Matrix.rowId row)
        "acquisition arena reference game differs"
    _ ->
      Left
        ( NativeAcquisitionDataRejected
            "acquisition reference family or spec kind differs from its whole canonical row"
        )
 where
  pool = References.nativeReferenceDataSpecPool references

childPrefix :: Int -> Text
childPrefix index = "child" <> Text.pack (show index) <> "."

childKind :: Matrix.ProductRow state -> Either NativeAcquisitionDataError ChildKind
childKind row = case Matrix.rowClass row of
  Matrix.RlAlgorithmEnvironment "ARS" _ -> pure HostChildKind
  Matrix.RlAlgorithmEnvironment algorithm _ -> pure (NeuralChildKind (algorithm `elem` ["DDPG", "TD3", "SAC", "CrossQ", "TQC"]))
  Matrix.RlGoalConditioned _ -> pure (NeuralChildKind False)
  Matrix.AlphaZeroGame _ -> pure ArenaChildKind
  _ -> Left (NativeAcquisitionDataRejected "acquisition excludes non-native product rows")

childLabels :: ChildKind -> Int -> [Text]
childLabels kind index = fmap (childPrefix index <>) suffixes
 where
  suffixes = case kind of
    HostChildKind ->
      [ "started"
      , "ars-begun"
      , "prepared"
      , "initial"
      , "raw"
      , "final"
      , "ars-origin"
      , "device-observation"
      , "after-process"
      ]
    ArenaChildKind -> ["started", "prepared", "initial", "raw", "final", "device-observation", "after-process"]
    NeuralChildKind _ ->
      [ "started"
      , "prepared"
      , "effective"
      , "initial"
      , "raw"
      , "final"
      , "device-observation"
      , "after-process"
      ]

expectedPhase :: ChildKind -> Text -> Maybe PhaseTag
expectedPhase kind suffix = case suffix of
  "started" -> Just StartedPhase
  "prepared" -> Just (case kind of NeuralChildKind True -> ColdSnapshotPhase; _ -> EffectiveSnapshotPhase)
  "effective" -> Just EffectiveSnapshotPhase
  "initial" -> Just InitialEvaluationPhase
  "raw" -> Just RawReturnPhase
  "final" -> Just FinalEvaluationPhase
  "after-process" -> Just FinalEvaluationPhase
  _ -> Nothing

checkTerminal
  :: [Inventory.NativeAllocationChildData]
  -> [(NativeAcquisitionChildData, [Retain.NativeRetainedObjectData])]
  -> Envelope.NativeDecodedRetentionPhase
  -> Either CodecError ()
checkTerminal planned children terminal = do
  let bytes = Envelope.decodedPhasePayload terminal
  unless (BS.length bytes <= 131072) (Left (Malformed "acquisition terminal DATA exceeds128KiB"))
  recorded <- Wire.runParser parser bytes
  let expected =
        [ (fromIntegral index, attempt, fmap pointer refs)
        | (NativeAcquisitionChildData index attempt _, refs) <- children
        ]
      nonces = fmap (Inventory.attemptNonceDigest . Inventory.allocationChildNonce) planned
  unless
    (fmap (\(_, attempt, _) -> attempt) recorded == nonces && recorded == expected)
    ( Left
        ( Malformed
            "acquisition terminal is not the exact five completed original children and full ordered object lists"
        )
    )
 where
  pointer actual =
    ( Retain.nativeRetainedObjectKey actual
    , Retain.nativeRetainedObjectSha256 actual
    , Retain.nativeRetainedObjectBytes actual
    )
  parser = do
    Wire.expectList 3
    domain <- Wire.getText GeneralTextBytes 64
    unless
      (domain == "jitml-native-five-terminal-v1")
      (Wire.parserFailure (Malformed "acquisition terminal domain differs"))
    version <- Wire.getWord
    unless (version == 1) (Wire.parserFailure (Malformed "acquisition terminal version differs"))
    Wire.expectList 5
    replicateM 5 child
  child = do
    Wire.expectList 4
    index <- Wire.getWord
    attempt <- Wire.getDigest
    disposition <- Wire.getWord
    unless
      (disposition == 0)
      (Wire.parserFailure (Malformed "acquisition terminal contains a failed incomplete or not-run child"))
    count <- Wire.getListLength AggregateSequenceElements 16
    refs <- replicateM count object
    pure (index, attempt, refs)
  object = do
    Wire.expectList 3
    key <- Wire.getText GeneralTextBytes 256
    sha <- Wire.getText GeneralTextBytes 64
    count <- Wire.getWord
    pure (key, sha, count)

codec :: Either CodecError a -> Either NativeAcquisitionDataError a
codec = first NativeAcquisitionDataCodec
envelope :: Either Envelope.NativeRetentionEnvelopeError a -> Either NativeAcquisitionDataError a
envelope = first NativeAcquisitionDataEnvelope
rejected :: Either Text a -> Either NativeAcquisitionDataError a
rejected = first NativeAcquisitionDataRejected
require :: Bool -> Text -> Either NativeAcquisitionDataError ()
require condition detail = unless condition (Left (NativeAcquisitionDataRejected detail))
