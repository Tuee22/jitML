{-# LANGUAGE OverloadedStrings #-}

-- | Evidence-typed report measurements.
--
-- A report value is exactly one of three things, and a value that is absent
-- can never be mistaken for one that was requested and could not be produced:
--
-- * 'NotRequested' — the run did not ask for this measurement (a non-live run,
--   or a target selection that has no stage producing it).
-- * 'Unavailable' — the run asked for it and no evidence exists, with a closed
--   'UnavailableReason' naming why.
-- * 'Available' — typed evidence that an interpreter-captured journal already
--   holds.  The evidence type is the caller's; this module never manufactures
--   one, so an @Available@ can only be built from a value the journal
--   refinements produced.
--
-- There is deliberately no free-text @Available@ and no reasonless
-- unavailable: rendering always names the reason.
module JitML.Test.Measurement
  ( Measurement (..)
  , UnavailableReason (..)
  , renderMeasurementLine
  , renderUnavailableReason
  )
where

import Data.Char (isControl)
import Data.Text (Text)
import Data.Text qualified as Text

-- | One report measurement as a projection of execution evidence.
data Measurement evidence
  = NotRequested
  | Unavailable !UnavailableReason
  | Available !evidence
  deriving stock (Eq, Functor, Show)

-- | Why a requested measurement has no evidence.  The set is closed: each
-- constructor is a different real situation in the report pipeline.
data UnavailableReason
  = -- | The live scope stopped at a failed or blocked stage before this evidence
    -- was collected.  The payload names that stage exactly as the invocation
    -- journal's blocker does for its @NOT-RUN@ rows (for example
    -- @live-e2e-test/jitml-integration@).  It is the stage that stopped
    -- collection, which is not necessarily the stage that produces this
    -- evidence: the interpreter skips its post-body collection after any failed
    -- planned invocation, so a later stanza's failure blocks an earlier
    -- stanza's evidence as well.
    UpstreamNotRun !Text
  | -- | A parent-owned journal refinement rejected its input, so the evidence
    -- it guards was not collected.  The payload is the refinement's own
    -- rejection detail, which names the journal.  One refinement can guard more
    -- than one measurement: the browser stage's final refinement also carries
    -- the ProductScenario re-read, so its rejection is the reason for both.
    EvidenceRejected !Text
  | -- | No interpreter step journals this observation, so no transcript exists
    -- to project it from.  The payload says exactly which observation and what
    -- is missing.
    NotJournaled !Text
  deriving stock (Eq, Show)

-- | The text after @unavailable@ in a report line.  It always names the
-- constructor's meaning and is forced onto one line so a multi-line rejection
-- detail cannot corrupt the line-oriented report.
renderUnavailableReason :: UnavailableReason -> Text
renderUnavailableReason reason =
  case reason of
    UpstreamNotRun stage -> "upstream not run: " <> singleLine stage
    EvidenceRejected detail -> "evidence rejected: " <> singleLine detail
    NotJournaled observation -> "not journaled: " <> singleLine observation

-- | Render one labelled measurement line inside the @measurements:@ block.
-- 'NotRequested' renders no line at all; the other two states always render
-- one, so requested-but-missing is visible in the report.
renderMeasurementLine :: Text -> (evidence -> Text) -> Measurement evidence -> [Text]
renderMeasurementLine label renderEvidence measurement =
  case measurement of
    NotRequested -> []
    Unavailable reason ->
      ["  " <> label <> ": unavailable (" <> renderUnavailableReason reason <> ")"]
    Available evidence -> ["  " <> label <> ": " <> renderEvidence evidence]

singleLine :: Text -> Text
singleLine =
  Text.unwords
    . Text.words
    . Text.map (\character -> if isControl character then ' ' else character)
