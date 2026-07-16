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
-- The projection is a pure transform over the decoded daemon command; the
-- daemon publishes the produced frame via
-- the validated Coordinator topology. A 'Nothing' result means the payload carried no
-- status-bearing transition (it is left for the existing per-domain handlers).
module JitML.Service.WorkflowStatus
  ( WorkflowStatusFrame (..)
  , renderWorkflowStatusFrame
  , workflowStatusFrameForDaemonCommand
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune qualified as Tune
import JitML.Service.Consumer (DaemonCommand (..), EventDomain (..))

-- | The reconciled per-run workflow status the projector republishes. @runId@
-- is the run's experiment hash; @status@ is one of queued / running / done /
-- failed; @detail@ is a short human-readable note.
data WorkflowStatusFrame = WorkflowStatusFrame
  { wsfRunId :: Text
  , wsfStatus :: Text
  , wsfDetail :: Text
  }
  deriving stock (Eq, Show)

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

-- | Project one already-decoded daemon command into the reconciled workflow
-- status stream. Inference commands have no workflow lifecycle transition.
workflowStatusFrameForDaemonCommand :: DaemonCommand -> Maybe WorkflowStatusFrame
workflowStatusFrameForDaemonCommand command =
  case command of
    TrainingDaemonCommand _substrate training ->
      case training of
        Training.TrainingStart start ->
          Just (commandFrame TrainingDomain (Training.stExperimentHash start) "queued" "StartTraining")
        Training.TrainingStop stop ->
          Just (commandFrame TrainingDomain (Training.stopExperimentHash stop) "done" "StopTraining")
    TuneDaemonCommand _substrate tune ->
      case tune of
        Tune.TuneStart start ->
          Just (commandFrame TuneDomain (Tune.ssExperimentHash start) "queued" "StartSweep")
        Tune.TuneStop stop ->
          Just (commandFrame TuneDomain (Tune.ssStopExperimentHash stop) "done" "StopSweep")
    RlDaemonCommand _substrate rl ->
      case rl of
        Rl.RlStart start ->
          Just (commandFrame RlDomain (Rl.srlExperimentHash start) "queued" "StartRLRun")
        Rl.RlStartAlphaZero start ->
          Just
            ( commandFrame
                RlDomain
                (Rl.sazExperimentHash start)
                "queued"
                "StartAlphaZeroRun"
            )
        Rl.RlStop stop ->
          Just (commandFrame RlDomain (Rl.srStopExperimentHash stop) "done" "StopRLRun")
    InferenceDaemonCommand _substrate _inference -> Nothing

commandFrame :: EventDomain -> Text -> Text -> Text -> WorkflowStatusFrame
commandFrame domain experimentHash status kind =
  WorkflowStatusFrame
    { wsfRunId = experimentHash
    , wsfStatus = status
    , wsfDetail = renderEventDomainLabel domain <> " " <> kind
    }

renderEventDomainLabel :: EventDomain -> Text
renderEventDomainLabel domain =
  case domain of
    TrainingDomain -> "training"
    TuneDomain -> "tune"
    RlDomain -> "rl"
    InferenceDomain -> "inference"
