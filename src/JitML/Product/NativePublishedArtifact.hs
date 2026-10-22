{-# LANGUAGE OverloadedStrings #-}

-- | Compact inspection certificate derived ONLY from an actual CHILD
-- publication. It can be carried by existing Eq/Show publication results
-- without retaining all in-memory training graphs. No parser or ordinary
-- reference/admission pairing can create it. It is not parent authentication.
module JitML.Product.NativePublishedArtifact
  ( NativePublishedArtifact
  , nativeChildPublishedArtifact
  , nativePublishedAdmitted
  , nativePublishedReference
  , nativePublishedCompanion
  , nativePublishedMetadataArtifact
  ) where

import Control.Monad (unless)
import Data.Text (Text)

import JitML.Checkpoint.Format qualified as Format
import JitML.Checkpoint.NativeQualificationReceiptData qualified as Metadata
import JitML.Checkpoint.NativeRetention qualified as Retain
import JitML.Checkpoint.Store qualified as Store
import JitML.Checkpoint.Writer qualified as Writer
import JitML.Product.NativeQualificationPublication qualified as Publication
import JitML.Product.NativeQualificationReference qualified as Reference
import JitML.Product.NativeRlReplayRetention qualified as Retained
import JitML.Product.NativeRlStoredServing qualified as Stored
import JitML.Training.Budget qualified as Training

data NativePublishedArtifact
  = NativePublishedArtifact
      !Store.AdmittedExecutionCheckpoint
      !Reference.NativeQualificationReference
      !Writer.StoredArtifact
      !Writer.StoredArtifact
  deriving stock (Eq, Show)

nativePublishedAdmitted :: NativePublishedArtifact -> Store.AdmittedExecutionCheckpoint
nativePublishedAdmitted (NativePublishedArtifact actual _ _ _) = actual
nativePublishedReference :: NativePublishedArtifact -> Reference.NativeQualificationReference
nativePublishedReference (NativePublishedArtifact _ actual _ _) = actual
nativePublishedCompanion :: NativePublishedArtifact -> Writer.StoredArtifact
nativePublishedCompanion (NativePublishedArtifact _ _ actual _) = actual
nativePublishedMetadataArtifact :: NativePublishedArtifact -> Writer.StoredArtifact
nativePublishedMetadataArtifact (NativePublishedArtifact _ _ _ actual) = actual

nativeChildPublishedArtifact
  :: Publication.NativeQualificationPublication -> Either Text NativePublishedArtifact
nativeChildPublishedArtifact publication = do
  let serving =
        Retained.nativeRetainedReplayServing (Publication.nativeQualificationPublicationReplays publication)
      admitted = Retain.nativeReadCheckpointEffective (Stored.nativeStoredPhysicalCheckpoint serving)
      checkpoint = Store.admittedExecutionCheckpoint admitted
      completed = Store.admittedExecutionCompletedTraining admitted
      manifest = Store.admittedCheckpointManifest checkpoint
      reference = Publication.nativeQualificationPublicationReference publication
      raw = Reference.nativeQualificationReferenceData reference
      metadata =
        Metadata.nativeQualificationReceiptFields
          (Publication.nativeQualificationPublicationMetadata publication)
      artifact = Publication.nativeQualificationPublicationArtifact publication
  require
    ( Store.admittedCheckpointManifestSha checkpoint == Reference.nativeReferenceManifest raw
        && Format.manifestExperiment manifest == Reference.nativeReferenceExperiment raw
    )
    "actual child publication and same effective admitted checkpoint identity differ"
  require
    (Training.encodeCompletedTraining completed == Metadata.nativeReceiptCompletedTrainingBytes metadata)
    "actual child publication and same effective admitted completion bytes differ"
  require
    ( Writer.storedArtifactSha artifact == Reference.nativeReferenceArtifact raw
        && Writer.storedArtifactObjectKey artifact == Reference.nativeReferenceObjectKey raw
    )
    "actual child publication metadata writer and reference addresses differ"
  pure (NativePublishedArtifact admitted reference (Stored.nativeStoredCompanion serving) artifact)

require :: Bool -> Text -> Either Text ()
require condition reason = unless condition (Left reason)
