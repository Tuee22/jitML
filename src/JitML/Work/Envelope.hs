{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 10.7 (Pulsar ML-Workflow convergence) — the @Work*@ envelope family.
-- Training and inference are the __same__ request → events → result shape,
-- correlated by 'CallId' (see @documents/engineering/pulsar_ml_workflow.md@ →
-- /The Work\* envelope family/ + /Artifact + readiness contract/):
--
-- @
-- WorkCommand { callId, workflow, lane, subjectRef, artifactRef?, payload, replyTopic }
-- WorkEvent   { callId, workflow, progress }
-- WorkResult  { callId, status, outputRefs }
-- @
--
-- Two domain invariants are enforced /in the types/:
--
--   * __Parse, don't validate, at the wire boundary.__ A malformed command is
--     always possible on the wire; 'parseWorkCommand' returns either a validated
--     'WorkCommand' or a typed 'WorkRejection' — never a silent bad state.
--   * __A serveable 'ArtifactRef' is unrepresentable unless it comes from a
--     completed derivation.__ 'ArtifactRef' is opaque; the only way to obtain one
--     is 'mintArtifactRef', which yields 'Just' only when a checkpoint manifest
--     has @step ≥ 1@ (the coordinator writes the 'readinessSentinelKey' last).
module JitML.Work.Envelope
  ( -- * Correlation + addressing
    CallId (..)
  , SubjectRef (..)
  , Workflow (..)

    -- * Derived-artifact readiness gate
  , ArtifactRef
  , artifactRefExperiment
  , artifactRefStep
  , mintArtifactRef
  , readinessSentinelKey

    -- * The Work* family
  , WorkCommand (..)
  , WorkEvent (..)
  , WorkResult (..)
  , WorkStatus (..)

    -- * Wire boundary (parse, don't validate)
  , WorkRejection (..)
  , parseWorkCommand
  , renderWorkRejection

    -- * Pure folds over the work log
  , dedupByCallId
  , correlateResult
  )
where

import Data.Maybe (isJust, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

import JitML.Checkpoint.Format
  ( CheckpointManifest
  , latestPointerKey
  , manifestCompletedTraining
  , manifestExperiment
  , manifestStep
  )
import JitML.Coordinator.Topology (Workflow (..))
import JitML.Substrate (Substrate)

-- | Correlates a command with its events and result. Effectively the broker
-- dedup key (see 'dedupByCallId').
newtype CallId = CallId {unCallId :: Text}
  deriving stock (Eq, Ord, Show)

-- | The durable subject a result routes back to (jitML: an experiment/run).
newtype SubjectRef = SubjectRef {unSubjectRef :: Text}
  deriving stock (Eq, Ord, Show)

-- | A reference to a __derived__ artifact (a trained checkpoint). The
-- constructor is intentionally not exported: the only way to obtain an
-- 'ArtifactRef' is 'mintArtifactRef' from a completed training derivation, so
-- "infer over an underived/untrained model" is unrepresentable in the domain.
data ArtifactRef = ArtifactRef
  { arExperiment :: Text
  , arStep :: Word64
  }
  deriving stock (Eq, Show)

artifactRefExperiment :: ArtifactRef -> Text
artifactRefExperiment = arExperiment

artifactRefStep :: ArtifactRef -> Word64
artifactRefStep = arStep

-- | Mint a serveable 'ArtifactRef' from a completed training derivation. Returns
-- 'Just' only when the checkpoint manifest has advanced at least one step
-- (@step ≥ 1@) — i.e. real training happened. A @step 0@ / untrained manifest
-- yields 'Nothing', so it can never back a served inference.
mintArtifactRef :: CheckpointManifest -> Maybe ArtifactRef
mintArtifactRef manifest
  | manifestStep manifest >= 1
      && isJust (manifestCompletedTraining manifest) =
      Just ArtifactRef {arExperiment = manifestExperiment manifest, arStep = manifestStep manifest}
  | otherwise = Nothing

-- | The MinIO object key for the @.ready@ sentinel the coordinator writes
-- __last__, next to the experiment's @latest@ pointer. Its presence is the
-- readiness witness that an 'ArtifactRef' is serveable.
readinessSentinelKey :: Text -> Text
readinessSentinelKey experiment = latestPointerKey experiment <> ".ready"

-- | A unit of work. Training and inference share this shape; @workflow@ selects
-- which. @artifactRef@ is present when the work consumes a derived artifact
-- (inference over a trained checkpoint).
data WorkCommand = WorkCommand
  { wcCallId :: CallId
  , wcWorkflow :: Workflow
  , wcLane :: Substrate
  , wcSubjectRef :: SubjectRef
  , wcArtifactRef :: Maybe ArtifactRef
  , wcPayload :: Text
  , wcReplyTopic :: Text
  }
  deriving stock (Eq, Show)

-- | A progress event. @Train@: epoch/loss; @Infer@: token/batch/none.
data WorkEvent = WorkEvent
  { weCallId :: CallId
  , weWorkflow :: Workflow
  , weProgress :: Text
  }
  deriving stock (Eq, Show)

-- | The terminal outcome. @Train@: checkpoint refs; @Infer@: output refs.
data WorkResult = WorkResult
  { wrCallId :: CallId
  , wrStatus :: WorkStatus
  , wrOutputRefs :: [Text]
  }
  deriving stock (Eq, Show)

data WorkStatus
  = WorkSucceeded
  | WorkFailed Text
  deriving stock (Eq, Show)

-- | A typed rejection emitted at the wire boundary instead of a silent bad
-- state.
data WorkRejection
  = MissingCallId
  | MissingReplyTopic
  | -- | inference (and any artifact-consuming workflow) requires a serveable
    -- 'ArtifactRef' minted from a completed derivation
    ArtifactNotReady Workflow
  deriving stock (Eq, Show)

renderWorkRejection :: WorkRejection -> Text
renderWorkRejection MissingCallId = "work command rejected: missing callId"
renderWorkRejection MissingReplyTopic = "work command rejected: missing replyTopic"
renderWorkRejection (ArtifactNotReady workflow) =
  "work command rejected: " <> Text.pack (show workflow) <> " requires a ready derived artifact"

-- | Parse a raw (already-field-extracted) wire command into a validated
-- 'WorkCommand', or a typed 'WorkRejection'. The @artifactRef@ is supplied as a
-- pre-minted 'Maybe ArtifactRef' (minting happens against the live manifest via
-- 'mintArtifactRef'); an artifact-consuming workflow with no ready artifact is
-- rejected rather than silently served from an untrained model.
parseWorkCommand
  :: Workflow
  -> Substrate
  -> Text
  -- ^ raw callId
  -> Text
  -- ^ raw subjectRef
  -> Maybe ArtifactRef
  -- ^ minted artifact ref, if the derivation is ready
  -> Text
  -- ^ payload
  -> Text
  -- ^ reply topic
  -> Either WorkRejection WorkCommand
parseWorkCommand workflow lane rawCallId rawSubject artifactRef payload replyTopic
  | Text.null (Text.strip rawCallId) = Left MissingCallId
  | Text.null (Text.strip replyTopic) = Left MissingReplyTopic
  | consumesArtifact workflow && isNothing artifactRef = Left (ArtifactNotReady workflow)
  | otherwise =
      Right
        WorkCommand
          { wcCallId = CallId rawCallId
          , wcWorkflow = workflow
          , wcLane = lane
          , wcSubjectRef = SubjectRef rawSubject
          , wcArtifactRef = artifactRef
          , wcPayload = payload
          , wcReplyTopic = replyTopic
          }

-- | Workflows that may only run against a ready derived artifact. Inference
-- serves a trained checkpoint; training/tuning/RL derive one.
consumesArtifact :: Workflow -> Bool
consumesArtifact Infer = True
consumesArtifact _ = False

-- | Producer-side dedup keyed by 'CallId' as a __pure fold__ over the work log,
-- so at-least-once delivery becomes effectively-once. Returns the commands in
-- first-seen order with later duplicates dropped.
dedupByCallId :: [WorkCommand] -> [WorkCommand]
dedupByCallId = reverse . snd . foldl' step (Set.empty, [])
 where
  step :: (Set CallId, [WorkCommand]) -> WorkCommand -> (Set CallId, [WorkCommand])
  step (seen, kept) command
    | wcCallId command `Set.member` seen = (seen, kept)
    | otherwise = (Set.insert (wcCallId command) seen, command : kept)

-- | Find the (first) result correlated to a command by 'CallId'.
correlateResult :: WorkCommand -> [WorkResult] -> Maybe WorkResult
correlateResult command =
  foldr (\result acc -> if wrCallId result == wcCallId command then Just result else acc) Nothing
