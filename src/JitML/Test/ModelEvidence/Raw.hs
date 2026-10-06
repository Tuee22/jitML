-- | The forgeable raw boundary of the per-model evidence layer.
--
-- 'RawModelEvidence' is a deliberately constructible view of one lane-journal
-- row, 'refineModelRowEvidence' mints evidence from it after re-checking every
-- field against the validated projection, and 'joinModelEvidence' does so for a
-- whole projection batch with the typed missing/duplicate/orphan/cross-plan/
-- wrong-lane/stale-contract failures. 'refineSeedCohort' is the per-seed half of
-- that refinement (cohort coverage against the plan's seeds, finite
-- measurements, each payload on its own channel), exposed so that a cohort
-- larger than one, which no ProductRow plans today, can be exercised end to end.
-- 'loadLaneJournalIn' is the loader with its pins and registry as arguments, so
-- that a tampered, missing, or unregistered journal can be offered to the same
-- fail-closed path 'JitML.Test.ModelEvidence.loadLaneJournal' runs.
--
-- Evidence produced through a hand-built value has no journal behind it, so this
-- module exists only for mutation controls that corrupt one field of a real,
-- admitted row and assert the specific typed rejection. Production code and every
-- other stanza obtain evidence through "JitML.Test.ModelEvidence", never from
-- here.
--
-- The barrier is enforced by the compiler, not by convention. The module
-- carries a warning in the @x-model-evidence-raw@ category, so every importer,
-- whatever its import syntax, is reported, and the @-Werror@ build that
-- @jitml check-code@ runs turns the report into an error. A module that may
-- import it says so with an @OPTIONS_GHC@ pragma naming
-- @-Wno-x-model-evidence-raw@; the model-convergence stanza asserts that
-- exactly its own control modules do.
module JitML.Test.ModelEvidence.Raw
  {-# WARNING in "x-model-evidence-raw"
    "builds evidence from hand-built values that no admitted lane journal backs; only the model-convergence mutation controls may import it (they opt out with -Wno-x-model-evidence-raw)"
    #-}
  ( EvidenceChannel (..)
  , EvidenceSlot (..)
  , RawCompletionIdentity (..)
  , RawFinalQuality (..)
  , RawInvocationIdentity (..)
  , RawLearningTelemetry (..)
  , RawModelEvidence (..)
  , RawSeedEvidence (..)
  , rawModelEvidenceFromJournal
  , rawModelEvidenceFromJournalRow
  , joinModelEvidence
  , loadLaneJournalIn
  , refineModelRowEvidence
  , refineSeedCohort
  )
where

import JitML.Test.ModelEvidence.Internal
