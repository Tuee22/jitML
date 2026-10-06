-- | Phase 285 — opaque, contract-driven per-model completed-run evidence.
--
-- A 'ModelRowEvidence' is the evidence a per-model convergence, learning,
-- performance, or binding assertion consumes. It is kind-indexed by the same
-- 'JitML.Plan.Plan.RunKind' as the row's
-- 'JitML.Product.Matrix.ProductProjection', its constructor is hidden, and the
-- only way to obtain one through this module is 'admitModelEvidence' (or
-- 'admitLaneEvidence' over a 'LoadedLane'): both mint evidence only from
--
--   (a) the validated projection of the row for the lane, and
--   (b) the corresponding row of an /admitted/ lane journal.
--
-- The lane journal is the committed, authenticated, versioned completed-run
-- evidence: its pinned SHA-256, canonical JSON, and validation against the
-- current projection are enforced by
-- 'JitML.Test.ProductLaneJournal.admitProductLaneJournal', the same reader the
-- aggregation phase uses. This module only consumes admitted rows. It adds no
-- journal wire and no new live measurement.
--
-- The forgeable raw view of a journal row and the refinement that mints
-- evidence from it live in "JitML.Test.ModelEvidence.Raw", which exists so that
-- mutation controls can corrupt one field of a real row. Ordinary code must not
-- import it: the module carries a compile-time warning that the @-Werror@ build
-- turns into an error for every importer that has not opted out, and the
-- model-convergence stanza asserts that only its controls have.
--
-- What is checked, and where:
--
-- * the typed join mirrors "JitML.Test.Report" (missing, duplicate, orphan,
--   wrong-plan, wrong-lane, stale-contract) and then mints one evidence value
--   per row;
-- * minting binds identity: row id, PlanId, lane, experiment hash, admitted and
--   inference manifest identities, contract digest, the completion's own
--   plan/experiment/invocation/device identities, exact coverage of the plan's
--   seed cohort ('JitML.Plan.Plan.runPlanSeeds'), finite measurements, and that
--   each measurement arrived on its own evidence channel;
-- * 'assertModelConvergence' grades the final-quality channel against an
--   /independent/ criterion re-derived from the canonical threshold tables
--   ('JitML.Product.ExternalBars.externalCriteriaFor'), never from the registry
--   bar;
-- * 'assertModelLearning' grades the learning-telemetry channel (budget
--   exhausted exactly, updates were applied, weights moved). It is a distinct
--   type with a distinct failure sum from final quality; neither can stand in
--   for the other, and 'RowChannelSubstituted' rejects the attempt at the raw
--   boundary;
-- * 'assertModelPerformance' grades committed
--   'JitML.Product.ExternalBars.PerformanceBound's over deterministic
--   non-wall-clock work counts, bound to the same plan, experiment, and
--   admitted manifest identity; 'assertReceiptBinding' compares each
--   performance receipt with the admitted journal row it came from, one
--   identity at a time.
--
-- What a lane journal cannot carry: it retains no per-iteration learning curve
-- and no per-episode evaluation set (only the refined
-- 'JitML.Training.Budget.CompletedTraining' with its observed units, update
-- count, weight hashes and passed cohort measurements), no checkpoint bytes, and
-- no served-artifact inference measurement. The types keep the two RL channels
-- apart so that a later journal version can retain the curve and the keyed
-- evaluation set without changing any assertion; today only their scalar
-- summaries exist.
module JitML.Test.ModelEvidence
  ( -- * Opaque evidence
    ModelRowEvidence
  , SomeModelRowEvidence (..)
  , ModelEvidenceSet
  , SeedEvidence
  , LearningTelemetry
  , FinalQuality
  , modelEvidenceContractDigest
  , modelEvidenceExperimentHash
  , modelEvidenceFamily
  , modelEvidenceLane
  , modelEvidenceManifestSha
  , modelEvidencePlanId
  , modelEvidenceRowClass
  , modelEvidenceRowId
  , modelEvidenceSeeds
  , modelEvidenceSeedEvidence
  , modelEvidenceSetLane
  , modelEvidenceSetRows
  , lookupModelEvidence
  , modelEvidenceFromJournalRow
  , someModelEvidenceRowId
  , seedEvidenceSeed
  , seedEvidenceLearning
  , seedEvidenceFinalQuality
  , learningTelemetryBudgetKind
  , learningTelemetryObservedUnits
  , learningTelemetryUpdateCount
  , finalQualityObservations

    -- * Typed failures
  , BindingField (..)
  , BindingFailure (..)
  , FinalQualityFailure (..)
  , LearningFailure (..)
  , ModelAssertionFailure (..)
  , ModelEvidenceError (..)
  , ModelEvidenceLoadError (..)
  , PerformanceFailure (..)
  , ReceiptBindingFailure (..)
  , RowEvidenceError (..)
  , SeedCoverageIssue (..)
  , renderBindingFailure
  , renderFinalQualityFailure
  , renderLearningFailure
  , renderModelAssertionFailure
  , renderModelEvidenceError
  , renderModelEvidenceLoadError
  , renderModelEvidenceLoadHeadline
  , renderPerformanceFailure
  , renderReceiptBindingFailure
  , renderRowEvidenceError

    -- * Seed cohort coverage
  , checkSeedCoverage

    -- * Assertions
  , PerformanceReceipt (..)
  , assertModelBinding
  , assertModelConvergence
  , assertModelLearning
  , assertModelPerformance
  , assertModelRowEvidence
  , assertReceiptBinding
  , assertSomeModelBinding
  , assertSomeModelRowEvidence
  , cohortMedian
  , gradeCohortCriteria
  , gradePerformanceObservations
  , modelPerformanceReceipts
  , registryBarDrift

    -- * Loading admitted lane journals
  , LaneEvidence (..)
  , LoadedLane (..)
  , admitLaneEvidence
  , admitModelEvidence
  , loadLaneJournal
  )
where

import JitML.Test.ModelEvidence.Internal
