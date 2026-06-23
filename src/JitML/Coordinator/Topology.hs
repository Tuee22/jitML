{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 5.13 (Pulsar ML-Workflow convergence) — the __Coordinator__ owns the
-- Pulsar topic lifecycle, and every topic name is __derived__ from a typed
-- topology descriptor plus a __validated routing graph__. Hand-written topic
-- strings are forbidden (see @documents/engineering/pulsar_ml_workflow.md@ →
-- /Topic algebra/); this module replaces the former hardcoded list in
-- @JitML.Cluster.PulsarBootstrap@.
--
-- @
-- topicFor :: Tenant -> Namespace -> Workflow -> Phase -> Lane -> TopicName
-- @
--
-- The descriptor 'jitmlTopology' is the single source of truth: a new workflow
-- or lane edits the descriptor, never a topic literal. 'validateTopology'
-- rejects an unroutable graph (a one-sided command with no event/result, or a
-- duplicate topic); 'coordinatorTopics' is the exact derived set the coordinator
-- reconciles at startup.
module JitML.Coordinator.Topology
  ( Topic (..)
  , Workflow (..)
  , Phase (..)
  , RouteEntry (..)
  , Tenant (..)
  , Namespace (..)
  , defaultTenant
  , defaultNamespace
  , topicFor
  , jitmlTopology
  , topologyTopics
  , coordinatorTopics
  , validateTopology
  )
where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)

import JitML.Substrate (Substrate (..), allSubstrates, renderSubstrate)

-- | A fully-qualified Pulsar topic name. The only legal way to construct one is
-- through 'topicFor' (and the derivations built on it).
newtype Topic = Topic
  { topicName :: Text
  }
  deriving stock (Eq, Ord, Show)

-- | The jitML workflow set (the contract's project-supplied @Workflow@).
data Workflow
  = Train
  | Tune
  | Rl
  | Infer
  | Gc
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Topic phase. @Command@/@Request@/@HostCommand@ are inputs (work arriving at
-- an Engine); @Event@/@Result@ are reports (progress / outputs). @HostCommand@
-- is the Apple host-resident forwarding leg; @Request@/@Result@ are the
-- inference legs.
data Phase
  = Command
  | Event
  | Result
  | Request
  | HostCommand
  deriving stock (Eq, Ord, Show, Enum, Bounded)

newtype Tenant = Tenant Text
  deriving stock (Eq, Ord, Show)

newtype Namespace = Namespace Text
  deriving stock (Eq, Ord, Show)

defaultTenant :: Tenant
defaultTenant = Tenant "public"

defaultNamespace :: Namespace
defaultNamespace = Namespace "default"

-- | One edge of the routing graph: a (workflow, phase) topic published on each
-- of the named lanes (substrates).
data RouteEntry = RouteEntry
  { reWorkflow :: Workflow
  , rePhase :: Phase
  , reLanes :: [Substrate]
  }
  deriving stock (Eq, Show)

-- | The contract's @topicFor@. The lane is the jitML routing key (substrate).
topicFor :: Tenant -> Namespace -> Workflow -> Phase -> Substrate -> Topic
topicFor (Tenant tenant) (Namespace namespace) workflow phase lane =
  Topic $
    "persistent://"
      <> tenant
      <> "/"
      <> namespace
      <> "/"
      <> workflowSegment workflow
      <> "."
      <> phaseSegment phase
      <> "."
      <> renderSubstrate lane

workflowSegment :: Workflow -> Text
workflowSegment Train = "training"
workflowSegment Tune = "tune"
workflowSegment Rl = "rl"
workflowSegment Infer = "inference"
workflowSegment Gc = "gc"

phaseSegment :: Phase -> Text
phaseSegment Command = "command"
phaseSegment Event = "event"
phaseSegment Result = "result"
phaseSegment Request = "request"
phaseSegment HostCommand = "host-command"

-- | The jitML topology descriptor — the single source of truth for the Pulsar
-- topic family. The common product family is published on every substrate; the
-- Apple-only internal/host-command legs are published only on @apple-silicon@
-- (where the cluster daemon forwards Metal-backed work to the host daemon).
jitmlTopology :: [RouteEntry]
jitmlTopology =
  [ RouteEntry Train Command allSubstrates
  , RouteEntry Train Event allSubstrates
  , RouteEntry Tune Command allSubstrates
  , RouteEntry Tune Event allSubstrates
  , RouteEntry Rl Command allSubstrates
  , RouteEntry Rl Event allSubstrates
  , RouteEntry Infer Request allSubstrates
  , RouteEntry Infer Result allSubstrates
  , RouteEntry Gc Event allSubstrates
  , RouteEntry Infer Command [AppleSilicon]
  , RouteEntry Train HostCommand [AppleSilicon]
  , RouteEntry Tune HostCommand [AppleSilicon]
  , RouteEntry Rl HostCommand [AppleSilicon]
  ]

-- | Derive the exact topic set for a routing graph.
topologyTopics :: [RouteEntry] -> [Topic]
topologyTopics entries =
  [ topicFor defaultTenant defaultNamespace (reWorkflow entry) (rePhase entry) lane
  | entry <- entries
  , lane <- reLanes entry
  ]

-- | The coordinator's reconciled topic set, derived from 'jitmlTopology'.
coordinatorTopics :: [Topic]
coordinatorTopics = topologyTopics jitmlTopology

-- | Validate the routing graph. A graph is unroutable when it contains a
-- duplicate topic, an entry with no lanes, or a __one-sided link__: an input
-- topic (command/request/host-command) on a lane with no report (event/result)
-- on that same lane, or a report on a lane with no producing input (the @Gc@
-- workflow is emit-only and exempt).
validateTopology :: [RouteEntry] -> Either [Text] ()
validateTopology entries =
  case duplicateErrors <> emptyLaneErrors <> oneSidedErrors of
    [] -> Right ()
    errs -> Left errs
 where
  names = fmap topicName (topologyTopics entries)
  duplicateErrors =
    [ "duplicate topic: " <> n
    | (n, count) <- Map.toList (Map.fromListWith (+) [(x, 1 :: Int) | x <- names])
    , count > 1
    ]
  emptyLaneErrors =
    [ "routing entry has no lanes: "
        <> workflowSegment (reWorkflow e)
        <> "."
        <> phaseSegment (rePhase e)
    | e <- entries
    , null (reLanes e)
    ]
  -- (workflow, lane) -> phases present
  pairs =
    [ (reWorkflow e, lane, rePhase e)
    | e <- entries
    , lane <- reLanes e
    ]
  workflowLanes = nubOrd [(w, l) | (w, l, _) <- pairs]
  phasesFor w l = [p | (w', l', p) <- pairs, w' == w, l' == l]
  oneSidedErrors =
    concat
      [ checkPair w l (phasesFor w l)
      | (w, l) <- workflowLanes
      ]
  checkPair w l phases =
    let inputs = filter isInput phases
        reports = filter isReport phases
        label = workflowSegment w <> ".*." <> renderSubstrate l
     in ["one-sided routing (input with no event/result): " <> label | not (null inputs) && null reports]
          ++ [ "one-sided routing (report with no command/request): " <> label
             | null inputs && not (null reports) && w /= Gc
             ]
  isInput p = p `elem` [Command, Request, HostCommand]
  isReport p = p `elem` [Event, Result]

nubOrd :: (Ord a) => [a] -> [a]
nubOrd = Set.toList . Set.fromList
