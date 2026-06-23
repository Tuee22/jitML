{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 14.1 (Feature C) — the Engine's workflow-status projector.
--
-- The daemon already observes the training / RL / tune lifecycle: it consumes
-- the @<domain>.command.<substrate>@ envelopes (and the workers publish
-- @<domain>.event.<substrate>@ progress events). This module projects those
-- observed lifecycle transitions onto a single reconciled
-- @workflow.status.<substrate>@ topic as 'WorkflowStatus' text frames, which the
-- browser workflow panel renders live off @/api/ws/workflow@.
--
-- The projection is a pure text transform ('workflowStatusFrameForCommand' /
-- 'workflowStatusFrameForEvent'); the daemon publishes the produced frame to
-- 'workflowStatusTopic'. A 'Nothing' result means the payload carried no
-- status-bearing transition (it is left for the existing per-domain handlers).
module JitML.Service.WorkflowStatus
  ( WorkflowStatusFrame (..)
  , renderWorkflowStatusFrame
  , workflowStatusFrameForCommand
  , workflowStatusFrameForEvent
  , workflowStatusTopic
  )
where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.Consumer (EventDomain (..))
import JitML.Substrate (Substrate, renderSubstrate)

-- | The reconciled per-run workflow status the projector republishes. @runId@
-- is the run's experiment hash; @status@ is one of queued / running / done /
-- failed; @detail@ is a short human-readable note.
data WorkflowStatusFrame = WorkflowStatusFrame
  { wsfRunId :: Text
  , wsfStatus :: Text
  , wsfDetail :: Text
  }
  deriving stock (Eq, Show)

-- | The Pulsar topic suffix the projector publishes onto and the workflow panel
-- streams off (via the @/api/ws/workflow@ bridge).
workflowStatusTopic :: Substrate -> Text
workflowStatusTopic substrate =
  "workflow.status." <> renderSubstrate substrate

-- | Render a 'WorkflowStatusFrame' as the text payload the
-- @Generated.Contracts.parseWorkflowStatus@ parser decodes (@panel@ /
-- @run-id@ / @status@ / @detail@ lines under a @WorkflowStatus@ @kind@).
renderWorkflowStatusFrame :: WorkflowStatusFrame -> Text
renderWorkflowStatusFrame frame =
  Text.unlines
    [ "kind: WorkflowStatus"
    , "panel: workflow-status"
    , "run-id: " <> wsfRunId frame
    , "status: " <> wsfStatus frame
    , "detail: " <> Text.replace "\n" " " (wsfDetail frame)
    ]

-- | Project an observed @<domain>.command.<substrate>@ envelope into a reconciled
-- status frame: a @Start*@ command transitions the run to @queued@, a @Stop*@
-- command transitions it to @done@. Other payloads yield 'Nothing'.
workflowStatusFrameForCommand :: EventDomain -> Text -> Maybe WorkflowStatusFrame
workflowStatusFrameForCommand domain payload = do
  let value key = lookup key (parseFields payload)
  kind <- value "kind"
  experimentHash <- value "experiment-hash"
  status <- commandStatus kind
  pure
    WorkflowStatusFrame
      { wsfRunId = experimentHash
      , wsfStatus = status
      , wsfDetail = renderEventDomainLabel domain <> " " <> kind
      }

-- | Project an observed @<domain>.event.<substrate>@ progress event into a
-- reconciled status frame: progress events transition the run to @running@,
-- failure events to @failed@, completion events to @done@.
workflowStatusFrameForEvent :: EventDomain -> Text -> Maybe WorkflowStatusFrame
workflowStatusFrameForEvent domain payload = do
  let value key = lookup key (parseFields payload)
  kind <- value "kind"
  experimentHash <- value "experiment-hash"
  status <- eventStatus kind
  pure
    WorkflowStatusFrame
      { wsfRunId = experimentHash
      , wsfStatus = status
      , wsfDetail = renderEventDomainLabel domain <> " " <> kind
      }

commandStatus :: Text -> Maybe Text
commandStatus kind =
  case kind of
    "StartTraining" -> Just "queued"
    "StartRLRun" -> Just "queued"
    "StartSweep" -> Just "queued"
    "StopTraining" -> Just "done"
    "StopRLRun" -> Just "done"
    "StopSweep" -> Just "done"
    _ -> Nothing

eventStatus :: Text -> Maybe Text
eventStatus kind =
  case kind of
    "EpochCompleted" -> Just "running"
    "RlEpisode" -> Just "running"
    "TuneTrial" -> Just "running"
    "CheckpointDone" -> Just "done"
    "SweepDone" -> Just "done"
    "TrainingFailed" -> Just "failed"
    "RlFailed" -> Just "failed"
    "SweepFailed" -> Just "failed"
    _ -> Nothing

renderEventDomainLabel :: EventDomain -> Text
renderEventDomainLabel domain =
  case domain of
    TrainingDomain -> "training"
    TuneDomain -> "tune"
    RlDomain -> "rl"
    InferenceDomain -> "inference"

parseFields :: Text -> [(Text, Text)]
parseFields =
  mapMaybe parseField . Text.lines
 where
  parseField line =
    let (key, rest) = Text.breakOn ":" line
     in if Text.null rest
          then Nothing
          else Just (Text.strip key, Text.strip (Text.drop 1 rest))
