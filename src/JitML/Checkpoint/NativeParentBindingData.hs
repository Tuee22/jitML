{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Pure recorded identity/topology comparisons only. Expected values are
-- ordinary DATA; this function does not observe a source/executable, issue or
-- authenticate an invocation, admit a checkpoint, fetch bytes, replay numeric
-- policy, or mint a parent qualification. The actual parent must own all of
-- those observations and never substitute a child's declarations for them.
module JitML.Checkpoint.NativeParentBindingData
  ( NativeParentExpectedData (..)
  , NativeParentPayloadData (..)
  , NativeParentBindingData
  , checkNativeParentBindingData
  , nativeParentBindingCohort
  , nativeParentBindingMetadata
  , nativeParentBindingAcquisition
  , nativeParentBindingReplays
  ) where

import Control.Monad (unless, zipWithM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.Either.Combinators (mapLeft)
import Data.List (find)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Checkpoint.NativeAcquisitionData qualified as Acquisition
import JitML.Checkpoint.NativePhase.Context qualified as Context
import JitML.Checkpoint.NativePhase.Types
  ( CodecError
  , Digest
  , Resource (AggregateSequenceElements)
  , boundedLength
  , digestBytes
  )
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeReplayObjectData qualified as Replay
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.NativeRetentionReader qualified as Envelope
import JitML.Plan.NativeSingletonPlan qualified as Singleton
import JitML.Plan.Plan qualified as Plan
import JitML.Product.Matrix qualified as Matrix
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlCohortPlan qualified as Cohort
import JitML.Product.SourceDigest qualified as Source
import JitML.Product.ValidationRecord (sha256Hex)
import JitML.Training.Budget qualified as Training

-- In the concrete parent, these come from its own source observation, pinned
-- executable/precondition, issued challenge and actual addressed Store result.
-- A public constructor here makes no assertion that those actions occurred.
data NativeParentExpectedData = NativeParentExpectedData
  { parentExpectedSource :: !Source.SourceStamp
  , parentExpectedExecutable :: !Text
  , parentExpectedInvocation :: !Training.ProductScenarioInvocation
  , parentExpectedManifest :: !Text
  , parentExpectedCompletedBytes :: !ByteString
  }

-- Full ordered original inventories, not a selected passing subset. Physical
-- readers must bound/hash each object independently before calling this check.
data NativeParentPayloadData = NativeParentPayloadData
  { parentMetadataBytes :: !ByteString
  , parentAllocationBytes :: !ByteString
  , parentPhaseBytes :: ![ByteString]
  , parentReplayBytes :: ![ByteString]
  }

data NativeParentBindingData
  = NativeParentBindingData
      !Cohort.NativeRlCohortPlan
      !Metadata.NativeQualificationReceiptData
      !Acquisition.NativeAcquisitionData
      ![Replay.NativeReplayObjectData]

nativeParentBindingCohort :: NativeParentBindingData -> Cohort.NativeRlCohortPlan
nativeParentBindingCohort (NativeParentBindingData actual _ _ _) = actual
nativeParentBindingMetadata :: NativeParentBindingData -> Metadata.NativeQualificationReceiptData
nativeParentBindingMetadata (NativeParentBindingData _ actual _ _) = actual
nativeParentBindingAcquisition :: NativeParentBindingData -> Acquisition.NativeAcquisitionData
nativeParentBindingAcquisition (NativeParentBindingData _ _ actual _) = actual
nativeParentBindingReplays :: NativeParentBindingData -> [Replay.NativeReplayObjectData]
nativeParentBindingReplays (NativeParentBindingData _ _ _ actual) = actual

checkNativeParentBindingData
  :: Cohort.NativeRlCohortBatch
  -> Text
  -> NativeParentExpectedData
  -> Reference.NativeQualificationReference
  -> NativeParentPayloadData
  -> Either Text NativeParentBindingData
checkNativeParentBindingData batch row expected reference payload = do
  -- Bound hostile spines before inspecting elements or expanding graphs.
  phaseCount <- codec (boundedLength AggregateSequenceElements 128 (parentPhaseBytes payload))
  replayCount <- codec (boundedLength AggregateSequenceElements 11 (parentReplayBytes payload))
  require
    (phaseCount > 0 && replayCount == 11)
    "parent requires full phase and exactly eleven replay payloads"
  checked <-
    Cohort.refineNativeRlCohortBatch
      (Cohort.nativeRlCohortBatchSubstrate batch)
      (Cohort.nativeRlCohortBatchPlans batch)
  require (checked == batch) "parent complete current canonical batch differs"
  cohort <-
    maybe
      (Left "parent selected row is absent from complete current canonical batch")
      Right
      ( find
          ((== row) . Matrix.rowId . Cohort.nativeRlCohortPlanRow)
          (Cohort.nativeRlCohortBatchPlans batch)
      )
  metadata <- codec (Metadata.decodeNativeQualificationReceiptData (parentMetadataBytes payload))
  let fields = Metadata.nativeQualificationReceiptFields metadata
      invocation = parentExpectedInvocation expected
      source = parentExpectedSource expected
      executable = parentExpectedExecutable expected
      served = Cohort.nativeRlCohortServingChild cohort
      singleton = Cohort.nativeRlSeedPlanSingleton served
      lane = Singleton.nativeSingletonSubstrate singleton
      whole = Singleton.nativeSingletonPlanId singleton
      experiment = Singleton.nativeSingletonExperiment singleton
      allocation = Metadata.nativeReceiptAllocation fields
      phases = Metadata.nativeReceiptPhases fields
      replayReferences = Metadata.nativeReceiptReplays fields
      publication = Metadata.nativeReceiptPublication fields
  _ <- codec (Context.digestFromCanonicalText executable)
  _ <- codec (Context.digestFromCanonicalText (parentExpectedManifest expected))
  _ <- codec (Context.digestFromCanonicalText (Source.stampSha256 source))
  require
    (Source.stampAlgorithm source == Source.sourceDigestAlgorithm)
    "parent expected source algorithm differs"
  require
    ( Training.productScenarioInvocationRowId invocation == row
        && Training.productScenarioInvocationSubstrate invocation == lane
        && Training.productScenarioInvocationPlanId invocation == whole
        && Training.productScenarioInvocationExecutableSha256 invocation == executable
    )
    "parent own issued invocation differs from current canonical serving identity"
  -- Checks the exact full-budget child associations; no training stage is
  -- restored and no association supplied by the receipt is trusted.
  mapM_
    (Cohort.nativeRlSeedAssociation cohort invocation)
    Cohort.nativeSeedIndices
  case Cohort.nativeRlCohortPlanProjection cohort of
    Matrix.SomeProductProjection _ projection ->
      require
        ( Matrix.productProjectionRowId projection == row
            && Matrix.productProjectionSubstrate projection == lane
            && Matrix.productProjectionPlanId projection == whole
            && Matrix.productProjectionExperimentHash projection == experiment
        )
        "parent whole current canonical projection differs"
  require
    ( Metadata.nativeReceiptRow fields == row
        && Metadata.nativeReceiptLane fields == lane
        && hexDigest (Metadata.nativeReceiptWholePlan fields) == Plan.planIdText whole
        && Metadata.nativeReceiptExperiment fields == experiment
        && hexDigest (Metadata.nativeReceiptCohortId fields)
          == Plan.planIdText (Cohort.nativeRlCohortPlanId cohort)
        && Metadata.nativeReceiptCohortTransport fields == Cohort.nativeRlCohortPlanTransport cohort
    )
    "native metadata differs from whole current canonical cohort"
  require
    ( hexDigest (Metadata.nativeReceiptManifest fields) == parentExpectedManifest expected
        && Metadata.nativeReceiptCompletedTrainingBytes fields == parentExpectedCompletedBytes expected
    )
    "native metadata differs from parent addressed manifest or exact admitted completion bytes"
  require
    ( Metadata.nativeReceiptAssociation fields
        == Metadata.NativeReceiptScenarioData (Training.renderProductScenarioInvocation invocation)
    )
    "native metadata is not bound to the exact parent issued scenario invocation"
  let observed = Metadata.nativeReceiptObservedSource fields
      supplied = Metadata.nativeReceiptSuppliedSource fields
  require (isJust observed || isJust supplied) "native metadata has no original source role"
  require
    (all (maybe True (== source)) [observed, supplied])
    "native metadata original source roles differ from parent own observation"
  let expectedReference =
        Reference.NativeQualificationReferenceData
          row
          lane
          (Plan.planIdText whole)
          experiment
          (parentExpectedManifest expected)
          source
          executable
          (Training.productScenarioInvocationDigest invocation)
          (Plan.planIdText (Cohort.nativeRlCohortPlanId cohort))
          (sha256Hex (parentMetadataBytes payload))
          ( "jitml-checkpoints/"
              <> experiment
              <> "/artifacts/native-qualification/"
              <> sha256Hex (parentMetadataBytes payload)
              <> ".cbor"
          )
          (fromIntegral (BS.length (parentMetadataBytes payload)))
          (Retain.nativePublicationDigest publication)
          Reference.NativeReferenceScenario
          (Retain.nativeRetainedObjectKey allocation)
          (Retain.nativeRetainedObjectSha256 allocation)
          (Retain.nativeRetainedObjectBytes allocation)
  canonicalReference <- codec (Reference.refineNativeQualificationReference expectedReference)
  require
    (reference == canonicalReference)
    "native reference differs from exact metadata and parent own expected identities"
  require (length phases == phaseCount) "native metadata and actual full phase payload counts differ"
  require
    (length replayReferences == replayCount)
    "native metadata and actual replay payload counts differ"
  acquisition <-
    mapLeft
      (Text.pack . show)
      ( Acquisition.checkNativeAcquisitionData
          batch
          row
          (Context.SuppliedScenarioContext invocation)
          (Context.NativeContextSources observed supplied)
          allocation
          (parentAllocationBytes payload)
          (zip phases (parentPhaseBytes payload))
      )
  require
    (map Envelope.decodedPhaseObject (Acquisition.acquisitionPhases acquisition) == phases)
    "parent checked acquisition differs from exact original ordered metadata phase references"
  zipWithM_
    checkPhysical
    (map Metadata.nativeReceiptReplayObject replayReferences)
    (parentReplayBytes payload)
  replays <- traverse (codec . Replay.decodeNativeReplayObjectData) (parentReplayBytes payload)
  allocationDigest <-
    codec (Context.digestFromCanonicalText (Retain.nativeRetainedObjectSha256 allocation))
  zipWithM_ (checkReplay allocationDigest) replayReferences replays
  -- Mathematical policy, device/ARS lineage and original/loaded graph-root
  -- equality are independent checks. This result must not bypass them.
  pure (NativeParentBindingData cohort metadata acquisition replays)

checkPhysical :: Retain.NativeRetainedObjectData -> ByteString -> Either Text ()
checkPhysical reference bytes =
  require
    ( toInteger (BS.length bytes) == toInteger (Retain.nativeRetainedObjectBytes reference)
        && sha256Hex bytes == Retain.nativeRetainedObjectSha256 reference
    )
    "parent actual replay bytes differ from original physical count or content address"

checkReplay
  :: Digest -> Metadata.NativeReceiptReplayReference -> Replay.NativeReplayObjectData -> Either Text ()
checkReplay allocation reference actual =
  require
    ( Replay.nativeReplayObjectStage actual == Metadata.nativeReceiptReplayStage reference
        && Replay.nativeReplayObjectIndex actual == Metadata.nativeReceiptReplayIndex reference
        && Replay.nativeReplayObjectAttempt actual == Metadata.nativeReceiptReplayAttempt reference
        && Replay.nativeReplayObjectAllocation actual == allocation
    )
    "parent replay DATA differs from original stage index attempt or physical allocation binding"

require :: Bool -> Text -> Either Text ()
require condition detail = unless condition (Left detail)

codec :: Either CodecError value -> Either Text value
codec = mapLeft (Text.pack . show)

hexDigest :: Digest -> Text
hexDigest =
  Text.pack
    . concatMap
      (\byte -> [intToDigit (fromIntegral byte `div` 16), intToDigit (fromIntegral byte `mod` 16)])
    . BS.unpack
    . digestBytes
