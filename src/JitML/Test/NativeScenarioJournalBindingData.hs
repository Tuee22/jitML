{-# LANGUAGE OverloadedStrings #-}

-- | Ordinary semantic row DATA shared by the source journal, its native
-- retention audit and Report. No parser/refiner here grants any authority.
module JitML.Test.NativeScenarioJournalBindingData
  ( NativeScenarioJournalBindingData (..)
  , nativeScenarioJournalBindingMaterial
  ) where

import Data.Text (Text)
import Data.Word (Word64)

import JitML.Test.ProductScenarioAuthorization qualified as Authorization

-- Projection digest and inference-experiment identity remain independently
-- authenticated by the entire aggregate wire material, as in the old journal.
-- These are exactly the19 semantic fields consumed by Report's row boundary.
data NativeScenarioJournalBindingData = NativeScenarioJournalBindingData
  { nativeScenarioBindingRowId :: !Text
  , nativeScenarioBindingRunId :: !Text
  , nativeScenarioBindingPlanId :: !Text
  , nativeScenarioBindingSubstrate :: !Text
  , nativeScenarioBindingExecutablePath :: !FilePath
  , nativeScenarioBindingExecutableSha256 :: !Text
  , nativeScenarioBindingInvocationDigest :: !Text
  , nativeScenarioBindingExperimentHash :: !Text
  , nativeScenarioBindingManifestSha256 :: !Text
  , nativeScenarioBindingCommand :: !Text
  , nativeScenarioBindingContractSha256 :: !Text
  , nativeScenarioBindingCheckpointScopeSha256 :: !Text
  , nativeScenarioBindingExecutionJournalReceipt :: !Text
  , nativeScenarioBindingExecutionJournalSha256 :: !Text
  , nativeScenarioBindingInferenceManifestSha256 :: !Text
  , nativeScenarioBindingPreconditionRejected :: !Bool
  , nativeScenarioBindingPreconditionSequence :: !Word64
  , nativeScenarioBindingInferenceSequence :: !Word64
  , nativeScenarioBindingCompletionSequence :: !Word64
  }
  deriving stock (Eq, Show)

-- | The native receipt must be its strict canonical rendered line, bound as
-- an opaque scalar by the shared HMAC material. Native rows carry no supervised
-- qualification. This function does not validate, issue or restore a receipt.
nativeScenarioJournalBindingMaterial :: NativeScenarioJournalBindingData -> Text -> Text
nativeScenarioJournalBindingMaterial binding nativeReceipt =
  Authorization.productScenarioJournalEvidenceMaterialWithNativeQualification
    nativeReceipt
    ""
    (nativeScenarioBindingRowId binding)
    (nativeScenarioBindingRunId binding)
    (nativeScenarioBindingPlanId binding)
    (nativeScenarioBindingSubstrate binding)
    (nativeScenarioBindingExecutablePath binding)
    (nativeScenarioBindingExecutableSha256 binding)
    (nativeScenarioBindingInvocationDigest binding)
    (nativeScenarioBindingExperimentHash binding)
    (nativeScenarioBindingManifestSha256 binding)
    (nativeScenarioBindingCommand binding)
    (nativeScenarioBindingContractSha256 binding)
    (nativeScenarioBindingCheckpointScopeSha256 binding)
    (nativeScenarioBindingExecutionJournalReceipt binding)
    (nativeScenarioBindingExecutionJournalSha256 binding)
    (nativeScenarioBindingInferenceManifestSha256 binding)
    (nativeScenarioBindingPreconditionRejected binding)
    (nativeScenarioBindingPreconditionSequence binding)
    (nativeScenarioBindingInferenceSequence binding)
    (nativeScenarioBindingCompletionSequence binding)
