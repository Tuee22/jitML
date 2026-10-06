{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Phase 282 — workflow lifecycle: settlement, timeout, cleanup, and terminal
-- ordering of the live interpreter.
--
-- Each control runs the production interpreter
-- ('JitML.Test.LiveWorkflow.runLiveWorkflow') over a scripted scenario
-- ("JitML.Test.LifecycleFixtures") that makes exactly one thing go wrong, and
-- asserts that the interpreter refuses to mint completion for the specific
-- reason the control names.  The verdict compares a whole 'Rejection': the
-- primary failure with its payload, the placement kept, the completion facts
-- that survived, the diagnostics, the retained cleanup issues, the hooks the
-- interpreter drove, and the milestone order of its journal.  A control
-- therefore also proves the run was not rejected for some other reason, and an
-- interpreter that completes the run is reported as having accepted a
-- known-invalid scenario.
--
-- The scenarios come in two kinds of forced order.  Where the outcome depends on
-- which of the workload terminal and the completed evidence arrives first, the
-- scenario fixes it with gates (the observer waits for the evidence to be
-- recorded, or the consumer waits until the observer thread has finished), so
-- the order is a fact of the scenario and not of the scheduler.  Where only the
-- outcome matters, the scenario removes the race instead (a workload that never
-- terminates, a consumer that fails before any evidence exists).
--
-- __Closed-sum coverage.__  The interpreter's failure vocabulary is a family of
-- closed sums, and every constructor must be provoked and pinned by at least one
-- control:
--
-- * 'PrimaryKind' — one kind per constructor of the run's primary failure
--   ('primaryKind' is total, so a new constructor does not compile until it is
--   classified, and a new 'PrimaryKind' without a control fails
--   'lifecycleCoverageFailures');
-- * 'ObservationKind' — the six workload states;
-- * 'ConsumerFailureKind' — the eleven transport failures, as the run reports
--   them;
-- * 'CleanupSite' — placement, event source, owned object, diagnostics;
-- * 'DispositionKind' — successful and failed settlement;
-- * 'JoinErrorKind' — the two conflicts of the terminal/evidence join.
--
-- A control's coverage is /derived/ from what it pins or provokes (the primary
-- failure, the workload states, the dispositions, the scripted consumer failure,
-- the resource whose cleanup the scenario makes fail, the conflict the join
-- returns), never declared beside it, so the table cannot claim more than the
-- verdicts check.  The coverage is read from the specs, so
-- 'lifecycleCommitmentFailures' binds the specs to the committed control list the
-- standing stanza really runs: a control dropped from that list is reported
-- instead of still counting as covered.
module JitML.Test.NegativeControls.Lifecycle
  ( CleanupSite (..)
  , ConsumerFailureKind (..)
  , Coverage (..)
  , DispositionKind (..)
  , JoinErrorKind (..)
  , LifecycleSpec (..)
  , PrimaryKind (..)
  , allCoverage
  , consumerFailureKind
  , dispositionKind
  , joinErrorKind
  , lifecycleBaselineFailures
  , lifecycleCommitmentFailures
  , lifecycleControls
  , lifecycleCoverageFailures
  , lifecycleHarnessFailures
  , lifecycleOrderingFailures
  , lifecycleSpecs
  , primaryKind
  , renderCoverage
  , specControl
  )
where

import Control.Concurrent (myThreadId)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, readMVar)
import Data.Bifunctor (first)
import Data.Function ((&))
import Data.Functor (void)
import Data.List (sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import System.Exit (ExitCode (..))

import JitML.Coordinator.Topology (TopicDecodeError (..))
import JitML.Service.Capabilities (ConsumerFailure (..))
import JitML.Service.Pulsar.Internal qualified as PulsarInternal
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessDuration (..)
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , mkProcessFailure
  )
import JitML.Test.LifecycleFixtures
import JitML.Test.LiveWorkflow qualified as LiveWorkflow
import JitML.Test.NegativeControls.Core

-- Closed-sum classifiers -------------------------------------------------------

-- | One kind per constructor of the run's primary failure.
data PrimaryKind
  = PrimaryAcquireFailed
  | PrimaryPlacementPlanMismatch
  | PrimaryEstablishFailed
  | PrimaryPublishFailed
  | PrimaryConsumerFailed
  | PrimaryReducerRejected
  | PrimaryLocalPreconditionFailed
  | PrimaryLocalEvidenceFailed
  | PrimaryLocalEvidenceIncomplete
  | PrimaryCompletionBoundaryMismatch
  | PrimaryWorkloadFailed
  | PrimaryProbeFailed
  | PrimaryObservationExhausted
  | PrimaryTimedOut
  | PrimaryInterpreterException
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Total over the interpreter's primary failures.  A constructor added to
-- 'LiveWorkflow.LivePrimaryFailure' is an incomplete pattern here, which the
-- library's @-Werror=incomplete-patterns@ turns into a build failure until the
-- new failure is given a kind, and therefore a control.
primaryKind :: LiveWorkflow.LivePrimaryFailure terminal violation missing -> PrimaryKind
primaryKind primary =
  case primary of
    LiveWorkflow.LiveAcquireFailed _ -> PrimaryAcquireFailed
    LiveWorkflow.LivePlacementPlanMismatch _ _ -> PrimaryPlacementPlanMismatch
    LiveWorkflow.LiveEstablishFailed _ -> PrimaryEstablishFailed
    LiveWorkflow.LivePublishFailed _ -> PrimaryPublishFailed
    LiveWorkflow.LiveConsumerFailed _ -> PrimaryConsumerFailed
    LiveWorkflow.LiveReducerRejected _ -> PrimaryReducerRejected
    LiveWorkflow.LiveLocalPreconditionFailed _ -> PrimaryLocalPreconditionFailed
    LiveWorkflow.LiveLocalEvidenceFailed _ -> PrimaryLocalEvidenceFailed
    LiveWorkflow.LiveLocalEvidenceIncomplete _ -> PrimaryLocalEvidenceIncomplete
    LiveWorkflow.LiveCompletionBoundaryMismatch _ -> PrimaryCompletionBoundaryMismatch
    LiveWorkflow.LiveWorkloadFailed _ -> PrimaryWorkloadFailed
    LiveWorkflow.LiveProbeFailed _ -> PrimaryProbeFailed
    LiveWorkflow.LiveObservationExhausted _ -> PrimaryObservationExhausted
    LiveWorkflow.LiveTimedOut _ _ -> PrimaryTimedOut
    LiveWorkflow.LiveInterpreterException _ -> PrimaryInterpreterException

-- | One kind per constructor of the transport's consumer failure.
data ConsumerFailureKind
  = ConsumerDecode
  | ConsumerHandler
  | ConsumerPermit
  | ConsumerSettlement
  | ConsumerProtocol
  | ConsumerTransport
  | ConsumerTransportContext
  | ConsumerTransportExit
  | ConsumerPipedAction
  | ConsumerCleanup
  | ConsumerCleanupContext
  deriving stock (Eq, Ord, Show, Enum, Bounded)

consumerFailureKind :: ConsumerFailure -> ConsumerFailureKind
consumerFailureKind failure =
  case failure of
    ConsumerDecodeFailure _ -> ConsumerDecode
    ConsumerHandlerFailure _ -> ConsumerHandler
    ConsumerPermitFailure _ -> ConsumerPermit
    ConsumerSettlementFailure _ _ -> ConsumerSettlement
    ConsumerProtocolFailure _ -> ConsumerProtocol
    ConsumerTransportFailure _ -> ConsumerTransport
    ConsumerTransportContextFailure _ _ -> ConsumerTransportContext
    ConsumerTransportExited _ -> ConsumerTransportExit
    ConsumerPipedActionFailure _ _ -> ConsumerPipedAction
    ConsumerCleanupFailure _ -> ConsumerCleanup
    ConsumerCleanupContextFailure _ _ -> ConsumerCleanupContext

-- | Where a cleanup can fail: the four resources a run owns.
data CleanupSite
  = CleanupPlacement
  | CleanupEventSource
  | CleanupOwnedObject
  | CleanupDiagnostics
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | Successful and failed settlement of a delivery.
data DispositionKind
  = DispositionAck
  | DispositionNack
  deriving stock (Eq, Ord, Show, Enum, Bounded)

dispositionKind :: PulsarInternal.Disposition -> DispositionKind
dispositionKind disposition =
  case disposition of
    PulsarInternal.AckInternal -> DispositionAck
    PulsarInternal.NackInternal _ -> DispositionNack

-- | The two ways the terminal/evidence join can refuse a fact.
data JoinErrorKind
  = JoinConflictingTerminal
  | JoinConflictingEvidence
  deriving stock (Eq, Ord, Show, Enum, Bounded)

joinErrorKind :: LiveWorkflow.CompletionJoinError -> JoinErrorKind
joinErrorKind failure =
  case failure of
    LiveWorkflow.ConflictingTerminalObservation -> JoinConflictingTerminal
    LiveWorkflow.ConflictingCompletedEvidence -> JoinConflictingEvidence

-- | A fact about the interpreter's failure vocabulary that a control provokes
-- and pins.
data Coverage
  = CoversPrimary PrimaryKind
  | CoversObservation ObservationKind
  | CoversConsumerFailure ConsumerFailureKind
  | CoversCleanup CleanupSite
  | CoversDisposition DispositionKind
  | CoversJoinError JoinErrorKind
  deriving stock (Eq, Ord, Show)

-- | Everything that must be covered: every constructor of every closed sum.
allCoverage :: [Coverage]
allCoverage =
  fmap CoversPrimary [minBound ..]
    <> fmap CoversObservation [minBound ..]
    <> fmap CoversConsumerFailure [minBound ..]
    <> fmap CoversCleanup [minBound ..]
    <> fmap CoversDisposition [minBound ..]
    <> fmap CoversJoinError [minBound ..]

renderCoverage :: Coverage -> Text
renderCoverage = Text.pack . show

-- | One lifecycle control and what it covers.
data LifecycleSpec = LifecycleSpec
  { specName :: Text
  , specDescription :: Text
  , specCovers :: [Coverage]
  , specCheck :: ControlCheck
  }

specControl :: LifecycleSpec -> NegativeControl
specControl spec =
  NegativeControl
    { ncName = specName spec
    , ncCategory = Lifecycle
    , ncDescription = specDescription spec
    , ncCheck = specCheck spec
    }

-- | Every lifecycle control.
lifecycleControls :: [NegativeControl]
lifecycleControls = fmap specControl lifecycleSpecs

-- | The coverage the specs fail to provide: every constructor of every closed
-- sum without a control that provokes and pins it.  An empty result means a new
-- failure constructor cannot go unexercised.
lifecycleCoverageFailures :: [LifecycleSpec] -> [Text]
lifecycleCoverageFailures specs =
  [ "no lifecycle control covers " <> renderCoverage coverage
  | coverage <- allCoverage
  , coverage `notElem` covered
  ]
 where
  covered = concatMap specCovers specs

-- | The lifecycle specs and the lifecycle controls of a committed control list
-- (the list the standing stanza runs) must be the same set: a spec whose control
-- the list lost is reported, and so is a lifecycle control the list carries that
-- no spec describes.  'lifecycleCoverageFailures' reads the specs themselves, so
-- without this comparison a control dropped from the committed list would still
-- count as covered while the stanza no longer ran it.
lifecycleCommitmentFailures :: [NegativeControl] -> [Text]
lifecycleCommitmentFailures committed =
  [ "lifecycle spec has no committed control: " <> name
  | name <- specNames
  , name `notElem` committedNames
  ]
    <> [ "committed lifecycle control names no spec: " <> name
       | name <- committedNames
       , name `notElem` specNames
       ]
 where
  specNames = fmap specName lifecycleSpecs
  committedNames = [ncName control | control <- committed, ncCategory control == Lifecycle]

renderShown :: (Show value) => value -> Text
renderShown = Text.pack . show

-- Expectation and verdict ------------------------------------------------------

-- | What a rejected run must look like.  The optional fields are the ones that
-- depend on thread scheduling in some scenarios; a control pins them only where
-- the scenario makes them deterministic.
data Expectation = Expectation
  { expectPrimary :: Maybe ScenarioPrimary
  , expectPlacement :: Maybe Text
  , expectCompletion :: Maybe (LiveWorkflow.LiveTerminalFact Text, ScenarioEvidence)
  , expectDiagnostics :: [Text]
  , expectCleanup :: [Text]
  , expectHooks :: [Text]
  , expectSpine :: [Text]
  , expectConsumer :: Maybe [ConsumerEvent]
  , expectConsumerTrace :: Maybe [Text]
  , expectWorkload :: Maybe [ObservationKind]
  , expectPolls :: Maybe Int
  }

-- | The observed rejection, in the same shape as an 'Expectation' with every
-- field filled.
data Rejection = Rejection
  { rejPrimary :: Maybe ScenarioPrimary
  , rejPlacement :: Maybe Text
  , rejCompletion :: Maybe (LiveWorkflow.LiveTerminalFact Text, ScenarioEvidence)
  , rejDiagnostics :: [Text]
  , rejCleanup :: [Text]
  , rejHooks :: [Text]
  , rejSpine :: [Text]
  , rejConsumer :: [ConsumerEvent]
  , rejConsumerTrace :: [Text]
  , rejWorkload :: [ObservationKind]
  , rejPolls :: Int
  }
  deriving stock (Eq, Show)

rejectionOf :: Observation -> ScenarioFailure -> Rejection
rejectionOf observation failure =
  Rejection
    { rejPrimary = LiveWorkflow.liveFailurePrimary failure
    , rejPlacement = renderPlacement <$> LiveWorkflow.liveFailurePlacement failure
    , rejCompletion = LiveWorkflow.liveFailureCompletion failure
    , rejDiagnostics = fmap LiveWorkflow.unLiveDiagnostic (LiveWorkflow.liveFailureDiagnostics failure)
    , rejCleanup = fmap LiveWorkflow.unCleanupIssue (LiveWorkflow.liveFailureCleanupIssues failure)
    , rejHooks = obsInterpreterHooks observation
    , rejSpine = traceSpine trace
    , rejConsumer = obsConsumerLog observation
    , rejConsumerTrace = traceConsumer trace
    , rejWorkload = traceWorkload trace
    , rejPolls = obsPolls observation
    }
 where
  trace = traceOfJournal (LiveWorkflow.liveFailureJournal failure)

-- | The expectation as a rejection, taking the observed value for every field
-- the control leaves unpinned.  A retained cleanup issue names the event source
-- the interpreter labels it with, so the expected texts write the source as
-- @{label}@.
expectedRejection :: Text -> Expectation -> Rejection -> Rejection
expectedRejection label expectation observedRejection =
  Rejection
    { rejPrimary = expectPrimary expectation
    , rejPlacement = expectPlacement expectation
    , rejCompletion = expectCompletion expectation
    , rejDiagnostics = expectDiagnostics expectation
    , rejCleanup = fmap (Text.replace "{label}" label) (expectCleanup expectation)
    , rejHooks = expectHooks expectation
    , rejSpine = expectSpine expectation
    , rejConsumer = fromMaybe (rejConsumer observedRejection) (expectConsumer expectation)
    , rejConsumerTrace = fromMaybe (rejConsumerTrace observedRejection) (expectConsumerTrace expectation)
    , rejWorkload = fromMaybe (rejWorkload observedRejection) (expectWorkload expectation)
    , rejPolls = fromMaybe (rejPolls observedRejection) (expectPolls expectation)
    }

-- | A run that completed is a known-invalid scenario the interpreter accepted.
judge :: Text -> Expectation -> Observation -> ControlOutcome
judge label expectation observation =
  case obsResult observation of
    Right _completed -> Accepted
    Left failure ->
      let observedRejection = rejectionOf observation failure
       in rejectedWith
            (expectedRejection label expectation observedRejection)
            (Left observedRejection :: Either Rejection ())

-- | The coverage an expectation pins.
expectationCoverage :: Expectation -> [Coverage]
expectationCoverage expectation =
  maybe [] (\primary -> [CoversPrimary (primaryKind primary)]) (expectPrimary expectation)
    <> maybe [] (fmap CoversObservation) (expectWorkload expectation)
    <> [ CoversDisposition (dispositionKind disposition)
       | Just events <- [expectConsumer expectation]
       , ConsumerSettled disposition <- events
       ]

-- | A rejected run with this primary failure (or none, for a cleanup-only
-- failure).  The defaults describe a run that reached the workload and tore
-- down in order; a control overrides what differs.
failing :: Maybe ScenarioPrimary -> Expectation
failing primary =
  Expectation
    { expectPrimary = primary
    , expectPlacement = Just clusterJob
    , expectCompletion = Nothing
    , expectDiagnostics = [scriptedDiagnostics]
    , expectCleanup = []
    , expectHooks = hooksRan
    , expectSpine = spineRan
    , expectConsumer = Nothing
    , expectConsumerTrace = Nothing
    , expectWorkload = Nothing
    , expectPolls = Nothing
    }

clusterJob :: Text
clusterJob = "cluster-job:jitml-lifecycle-control"

requestReply :: Text
requestReply = "request-reply:lifecycle-request"

hostRun :: Text
hostRun = "host-run:lifecycle-host"

scriptedDiagnostics :: Text
scriptedDiagnostics = "scripted diagnostics"

-- | The hooks of a run that acquired, established, published, and tore down.
hooksRan :: [Text]
hooksRan = ["acquire", "establish", "publish", "diagnostics", "release", "placement"]

-- | The journal milestones of the same run.
spineRan :: [Text]
spineRan =
  [ "placement-acquired"
  , "source-established"
  , "publication-started"
  , "published"
  , "diagnostics"
  , "source-released"
  , "placement-released"
  ]

-- | A run that ended at the completion-boundary check: nothing was established.
hooksRefused :: [Text]
hooksRefused = ["acquire", "diagnostics", "placement"]

spineRefused :: [Text]
spineRefused = ["placement-acquired", "diagnostics", "placement-released"]

-- | The consumer trace of a delivery that completes the evidence.
completingDelivery :: [Text]
completingDelivery = ["delivery-observed", "evidence-accepted", "ack", "evidence-completed"]

-- | The completion facts that survive a failure after the terminal and the
-- evidence both arrived: the workload's terminal, and the evidence the
-- baseline's one delivery completed.
survivingCompletion :: (LiveWorkflow.LiveTerminalFact Text, ScenarioEvidence)
survivingCompletion =
  (LiveWorkflow.IndependentWorkloadSucceeded terminalName, [epochLabel 1])

-- Spec constructors ------------------------------------------------------------

-- | A control over a broker scenario built without gates.
broker :: Text -> Text -> BrokerScenario -> Expectation -> LifecycleSpec
broker name description scenario = brokerWith name description (pure scenario)

-- | A control over a broker scenario whose gates are created per run.
brokerWith :: Text -> Text -> IO BrokerScenario -> Expectation -> LifecycleSpec
brokerWith name description mkScenario expectation =
  observedRun name description expectation (mkScenario >>= runBrokerScenario)

-- | A control over a local scenario.
local :: Text -> Text -> LocalScenario -> Expectation -> LifecycleSpec
local name description scenario expectation =
  observedRun name description expectation (runLocalScenario scenario)

-- | A control over any run that yields an 'Observation'.
observedRun :: Text -> Text -> Expectation -> IO Observation -> LifecycleSpec
observedRun name description expectation run =
  LifecycleSpec
    { specName = name
    , specDescription = description
    , specCovers = expectationCoverage expectation
    , specCheck =
        EffectfulCheck $ do
          label <- sourceLabel
          judge label expectation <$> boundedRun run
    }

-- | Add coverage that the expectation does not carry.
covering :: [Coverage] -> LifecycleSpec -> LifecycleSpec
covering extra spec = spec {specCovers = specCovers spec <> extra}

-- | Every lifecycle spec, grouped by the failure family it provokes.
lifecycleSpecs :: [LifecycleSpec]
lifecycleSpecs =
  acquireSpecs
    <> establishmentSpecs
    <> boundarySpecs
    <> settlementSpecs
    <> consumerFailureSpecs
    <> workloadSpecs
    <> timeoutSpecs
    <> localSpecs
    <> cleanupSpecs
    <> joinSpecs

-- Acquisition --------------------------------------------------------------------

acquireSpecs :: [LifecycleSpec]
acquireSpecs =
  [ broker
      "lifecycle-acquire-failure-mints-nothing"
      "a placement that cannot be acquired must fail the run before anything is established, published, or released"
      baselineWorkload
        { scenarioAcquire = pure (Left (LiveWorkflow.ResourceFailure "no schedulable node"))
        }
      (failing (Just (LiveWorkflow.LiveAcquireFailed (LiveWorkflow.ResourceFailure "no schedulable node"))))
        { expectPlacement = Nothing
        , expectDiagnostics = []
        , expectHooks = ["acquire"]
        , expectSpine = []
        }
  , broker
      "lifecycle-acquire-exception-is-an-interpreter-failure"
      "an acquisition that throws is an interpreter failure with no placement, never a completed run"
      baselineWorkload {scenarioAcquire = ioError (userError "kubectl exploded")}
      (failing (Just (LiveWorkflow.LiveInterpreterException "user error (kubectl exploded)")))
        { expectPlacement = Nothing
        , expectDiagnostics = []
        , expectHooks = ["acquire"]
        , expectSpine = []
        }
  , broker
      "lifecycle-foreign-plan-placement-is-refused-before-establishment"
      "a placement owned by another plan must be released without establishing or publishing anything"
      baselineWorkload {scenarioPlacementPlan = ForeignPlan}
      (failing (Just (LiveWorkflow.LivePlacementPlanMismatch ownPlan foreignPlan)))
        { expectHooks = hooksRefused
        , expectSpine = spineRefused
        }
  ]

-- Establishment and publication ----------------------------------------------------

establishmentSpecs :: [LifecycleSpec]
establishmentSpecs =
  [ broker
      "lifecycle-establishment-refusal-never-publishes"
      "a refused event-source establishment must never publish, consume, or release a source that does not exist"
      baselineWorkload {scenarioEstablish = pure (Left (SEConflict "cursor CREATE refused"))}
      (failing (Just (LiveWorkflow.LiveEstablishFailed (SEConflict "cursor CREATE refused"))))
        { expectHooks = ["acquire", "establish", "diagnostics", "placement"]
        , expectSpine =
            ["placement-acquired", "source-establishment-failed", "diagnostics", "placement-released"]
        , expectConsumer = Just []
        }
  , broker
      "lifecycle-establishment-exception-never-publishes"
      "an establishment hook that throws is an interpreter failure, and nothing is published or consumed"
      baselineWorkload {scenarioEstablish = ioError (userError "CREATE exploded")}
      (failing (Just (LiveWorkflow.LiveInterpreterException "user error (CREATE exploded)")))
        { expectHooks = ["acquire", "establish", "diagnostics", "placement"]
        , expectSpine = ["placement-acquired", "diagnostics", "placement-released"]
        , expectConsumer = Just []
        }
  , broker
      "lifecycle-publication-refusal-releases-the-source-once"
      "a refused publication must fail the run and still release the established source once, after diagnostics"
      baselineWorkload {scenarioPublish = pure (Left publicationRefusal)}
      publicationRefusalExpectation
  ]

-- | The publication the broker refuses.
publicationRefusal :: ServiceError
publicationRefusal = SETransient "broker refused the publish"

-- | A refused publication fails the run, and the established source is still
-- released once, after the diagnostics and before the placement.
publicationRefusalExpectation :: Expectation
publicationRefusalExpectation =
  (failing (Just (LiveWorkflow.LivePublishFailed publicationRefusal)))
    { expectSpine =
        [ "placement-acquired"
        , "source-established"
        , "publication-started"
        , "publication-failed"
        , "diagnostics"
        , "source-released"
        , "placement-released"
        ]
    }

-- Completion boundary ---------------------------------------------------------------

boundarySpecs :: [LifecycleSpec]
boundarySpecs =
  [ observedRun
      "lifecycle-boundary-broker-source-on-local-transport"
      "a broker evidence source paired with a local executable transport must be refused before any hook runs"
      (refusedAt hostRun "Pulsar evidence source cannot use a local executable transport")
      runBrokerSourceOnLocalTransport
  , observedRun
      "lifecycle-boundary-local-source-on-broker-transport"
      "a local evidence source paired with a broker transport must be refused before anything is established"
      ( (refusedAt hostRun "local evidence source cannot use a broker transport")
          { expectConsumer = Just []
          }
      )
      runLocalSourceOnBrokerTransport
  , broker
      "lifecycle-boundary-request-placement-claims-a-workload-terminal"
      "a request/reply placement cannot claim an independently observed workload terminal"
      baselineWorkload {scenarioPlacement = RequestPlacement}
      (refusedAt requestReply "RequestReply placement cannot claim an independent workload terminal")
  , broker
      "lifecycle-boundary-response-completion-needs-a-request-placement"
      "response-completes-request needs a request/reply placement, not a cluster job"
      baselineWorkload {scenarioCompletion = LiveWorkflow.ResponseCompletesRequest}
      (refusedAt clusterJob "request/response completion requires a RequestReply placement")
  , local
      "lifecycle-boundary-executable-command-needs-a-host-placement"
      "a typed executable command must run on a host placement, never a cluster job"
      baselineLocal {localPlacement = ClusterPlacement}
      (refusedAt clusterJob "typed executable command requires a HostRun placement")
  ]
 where
  refusedAt placement detail =
    (failing (Just (LiveWorkflow.LiveCompletionBoundaryMismatch detail)))
      { expectPlacement = Just placement
      , expectHooks = hooksRefused
      , expectSpine = spineRefused
      }

-- Settlement ----------------------------------------------------------------------------

settlementSpecs :: [LifecycleSpec]
settlementSpecs =
  [ broker
      "lifecycle-reducer-rejection-nacks"
      "evidence the reducer rejects must be nacked, journalled as rejected, and end the run without completion"
      (neverTerminal baselineWorkload) {scenarioRejectedEpoch = Just 1}
      (failing (Just (LiveWorkflow.LiveReducerRejected "rejected epoch 1")))
        { expectConsumer =
            Just
              [ ConsumerAttached
              , ConsumerSettled (PulsarInternal.NackInternal (PulsarInternal.HandlerRejected "rejected epoch 1"))
              ]
        , expectConsumerTrace =
            Just ["consumer-session", "delivery-observed", "evidence-rejected", "nack"]
        }
  , broker
      "lifecycle-settlement-failure-before-completion"
      "a settlement failure while the evidence is still incomplete must end the run, not leave it waiting"
      (neverTerminal baselineWorkload)
        { scenarioRequired = 2
        , scenarioAfterDeliveries = FailNow settlementFailure
        }
      (failing (Just (LiveWorkflow.LiveConsumerFailed settlementFailure)))
        { expectConsumer = Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal]
        , expectConsumerTrace =
            Just ["consumer-session", "delivery-observed", "evidence-accepted", "evidence-incomplete", "ack"]
        }
      & covering [CoversConsumerFailure (consumerFailureKind settlementFailure)]
  , broker
      "lifecycle-settlement-failure-of-the-final-ack-withholds-completion"
      "a final acknowledgement that cannot be settled must withhold completion although the evidence and the terminal both arrived"
      baselineWorkload {scenarioAfterDeliveries = ReportOnStop finalAckFailure}
      (failing (Just (LiveWorkflow.LiveConsumerFailed finalAckFailure)))
        { expectCompletion = Just survivingCompletion
        , expectConsumer =
            Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal, ConsumerStopped]
        , expectConsumerTrace = Just ("consumer-session" : completingDelivery)
        }
      & covering [CoversConsumerFailure (consumerFailureKind finalAckFailure)]
  , broker
      "lifecycle-late-evidence-after-completion-is-rejected"
      "evidence delivered after the evidence completed must still be checked: an invalid late delivery is nacked and fails the run even though the workload never terminates"
      (neverTerminal baselineWorkload)
        { scenarioDeliveries = [delivery 1, delivery 2]
        , scenarioRejectedEpoch = Just 2
        }
      (failing (Just (LiveWorkflow.LiveReducerRejected "rejected epoch 2")))
        { expectConsumer =
            Just
              [ ConsumerAttached
              , ConsumerSettled PulsarInternal.AckInternal
              , ConsumerSettled (PulsarInternal.NackInternal (PulsarInternal.HandlerRejected "rejected epoch 2"))
              ]
        , expectConsumerTrace =
            Just
              ( "consumer-session"
                  : completingDelivery
                    <> ["delivery-observed", "evidence-rejected", "nack"]
              )
        }
  , broker
      "lifecycle-consumer-exception-is-an-interpreter-failure"
      "a consumer that throws is an interpreter failure, and the run never completes"
      (neverTerminal baselineWorkload)
        { scenarioDeliveries = []
        , scenarioAfterDeliveries = RaiseNow "consumer exploded"
        }
      (failing (Just (LiveWorkflow.LiveInterpreterException "user error (consumer exploded)")))
        { expectConsumer = Just [ConsumerAttached]
        , expectCleanup =
            ["consumer stopped with an exception for {label}: user error (consumer exploded)"]
        , expectSpine = withCleanupBeforeRelease spineRan
        }
  ]
 where
  settlementFailure =
    ConsumerSettlementFailure "lifecycle-delivery-1" (SETransient "ack settlement failed")
  finalAckFailure =
    ConsumerSettlementFailure "lifecycle-delivery-1" (SETransient "final ack unconfirmed at drain")

-- | The transport failures, one representative per constructor.
consumerFailureSpecs :: [LifecycleSpec]
consumerFailureSpecs =
  case representatives of
    Left detail ->
      [ LifecycleSpec
          "lifecycle-consumer-failure-representatives"
          "the consumer-failure fixtures must be constructible"
          []
          (EffectfulCheck (pure (fixtureFailed detail)))
      ]
    Right failures -> fmap consumerFailureSpec failures
 where
  consumerFailureSpec failure =
    broker
      ("lifecycle-consumer-failure-" <> renderConsumerFailureKind (consumerFailureKind failure))
      "a transport failure must end the run as a consumer failure, never a completed run"
      (neverTerminal baselineWorkload)
        { scenarioDeliveries = []
        , scenarioAfterDeliveries = FailNow failure
        }
      (failing (Just (LiveWorkflow.LiveConsumerFailed failure)))
        { expectConsumer = Just [ConsumerAttached]
        , expectCleanup = retained
        , expectSpine = if null retained then spineRan else withCleanupBeforeRelease spineRan
        }
      & covering [CoversConsumerFailure (consumerFailureKind failure)]
   where
    retained = retainedCleanup failure
  representatives :: Either Text [ConsumerFailure]
  representatives = do
    let transcript =
          ProcessTranscript
            { processTranscriptCommand = "lifecycle-bridge"
            , processTranscriptStdout = ""
            , processTranscriptStderr = "bridge exited"
            , processTranscriptWorkingDirectory = Nothing
            , processTranscriptDuration = ProcessDuration 1
            }
    processFailure <-
      maybe
        (Left "a non-zero exit status must build a process failure")
        Right
        (mkProcessFailure (ExitFailure 31) transcript)
    Right
      [ ConsumerDecodeFailure (TopicDecodeError "lifecycle-topic" "undecodable payload")
      , ConsumerHandlerFailure "handler exploded"
      , ConsumerPermitFailure (SETransient "permit refused")
      , ConsumerSettlementFailure "lifecycle-delivery-1" (SETransient "ack settlement failed")
      , ConsumerProtocolFailure "bridge spoke garbage"
      , ConsumerTransportFailure processFailure
      , ConsumerTransportContextFailure (ConsumerProtocolFailure "bridge lost sync") processFailure
      , ConsumerTransportExited transcript
      , ConsumerPipedActionFailure "publish" (ProcessFailed processFailure)
      , ConsumerCleanupFailure (SETransient "cursor DELETE returned 500")
      , ConsumerCleanupContextFailure
          (ConsumerProtocolFailure "consumer lost sync")
          (SETransient "cursor DELETE returned 500")
      ]

-- | The name a consumer failure's control carries.  Total over the kinds.
renderConsumerFailureKind :: ConsumerFailureKind -> Text
renderConsumerFailureKind kind =
  case kind of
    ConsumerDecode -> "decode"
    ConsumerHandler -> "handler"
    ConsumerPermit -> "permit"
    ConsumerSettlement -> "settlement"
    ConsumerProtocol -> "protocol"
    ConsumerTransport -> "transport"
    ConsumerTransportContext -> "transport-context"
    ConsumerTransportExit -> "transport-exit"
    ConsumerPipedAction -> "piped-action"
    ConsumerCleanup -> "cleanup"
    ConsumerCleanupContext -> "cleanup-context"

-- | The cleanup issue the interpreter retains beside a consumer failure that
-- names a cleanup.  Total over the consumer failures, so a new constructor must
-- be classified here as retaining a cleanup or not.
retainedCleanup :: ConsumerFailure -> [Text]
retainedCleanup failure =
  case failure of
    ConsumerDecodeFailure _ -> []
    ConsumerHandlerFailure _ -> []
    ConsumerPermitFailure _ -> []
    ConsumerSettlementFailure _ _ -> []
    ConsumerProtocolFailure _ -> []
    ConsumerTransportFailure _ -> []
    ConsumerTransportContextFailure _ _ -> []
    ConsumerTransportExited _ -> []
    ConsumerPipedActionFailure _ _ -> []
    ConsumerCleanupFailure cleanup -> [cleanupIssueText cleanup]
    ConsumerCleanupContextFailure _ cleanup -> [cleanupIssueText cleanup]
 where
  cleanupIssueText cleanup =
    "subscription cleanup failed for {label}: " <> Text.pack (show cleanup)

-- | A cleanup retained while the consumer is joined is journalled after the
-- diagnostics and before the event source is released.
withCleanupBeforeRelease :: [Text] -> [Text]
withCleanupBeforeRelease =
  concatMap (\label -> if label == "source-released" then ["cleanup-recorded", label] else [label])

-- Workload observation ----------------------------------------------------------------------

workloadSpecs :: [LifecycleSpec]
workloadSpecs =
  [ brokerWith
      "lifecycle-workload-failure-after-evidence-never-completes"
      "a workload that fails after its evidence completed must never complete the run"
      ( do
          evidenceProcessed <- newEmptyMVar
          pure
            baselineWorkload
              { scenarioObserve = \_ -> do
                  readMVar evidenceProcessed
                  pure (LiveWorkflow.Failed (LiveWorkflow.WorkloadFailure "container OOMKilled"))
              , scenarioDeliveries = [(delivery 1) {deliveryAfter = putMVar evidenceProcessed ()}]
              }
      )
      ( failing
          (Just (LiveWorkflow.LiveWorkloadFailed (LiveWorkflow.WorkloadFailure "container OOMKilled")))
      )
        { expectConsumer =
            Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal, ConsumerStopped]
        , expectConsumerTrace = Just ("consumer-session" : completingDelivery)
        , expectWorkload = Just [ObservedFailed]
        , expectPolls = Just 1
        }
  , broker
      "lifecycle-workload-failure-without-evidence"
      "a workload that fails before any evidence exists must end the run as a workload failure"
      baselineWorkload
        { scenarioDeliveries = []
        , scenarioObserve = \_ ->
            pure (LiveWorkflow.Failed (LiveWorkflow.WorkloadFailure "container OOMKilled"))
        }
      ( failing
          (Just (LiveWorkflow.LiveWorkloadFailed (LiveWorkflow.WorkloadFailure "container OOMKilled")))
      )
        { expectWorkload = Just [ObservedFailed]
        , expectPolls = Just 1
        }
  , broker
      "lifecycle-probe-failure-is-not-absence"
      "a workload probe that fails is a probe failure, never treated as an absent workload and retried"
      baselineWorkload
        { scenarioDeliveries = []
        , scenarioObserve = \_ ->
            pure (LiveWorkflow.ProbeFailed (LiveWorkflow.ProbeFailure "kubectl get job: connection refused"))
        , scenarioAttempts = 5
        }
      ( failing
          ( Just
              (LiveWorkflow.LiveProbeFailed (LiveWorkflow.ProbeFailure "kubectl get job: connection refused"))
          )
      )
        { expectWorkload = Just [ObservedProbeFailed]
        , expectPolls = Just 1
        }
  , exhausted
      "lifecycle-absent-workload-exhausts-observation"
      "a workload that is never found is not a success: the observation budget is exhausted"
      (LiveWorkflow.Missing (LiveWorkflow.LiveDiagnostic "job not found"))
      ObservedMissing
  , exhausted
      "lifecycle-pending-workload-exhausts-observation"
      "a workload that never starts is not a success: the observation budget is exhausted"
      (LiveWorkflow.Pending (LiveWorkflow.LiveDiagnostic "waiting for a node"))
      ObservedPending
  , exhausted
      "lifecycle-running-workload-exhausts-observation"
      "a workload that never finishes is not a success: the observation budget is exhausted"
      (LiveWorkflow.Running (LiveWorkflow.LiveDiagnostic "still running"))
      ObservedRunning
  , broker
      "lifecycle-evidence-without-terminal-exhausts-observation"
      "completed evidence does not stand in for the workload terminal: a workload that never finishes still exhausts the observation budget"
      baselineWorkload
        { scenarioObserve = \_ -> pure (LiveWorkflow.Running (LiveWorkflow.LiveDiagnostic "still running"))
        , scenarioAttempts = 3
        , scenarioDelayMicros = 1_000
        }
      ( failing
          ( Just
              ( LiveWorkflow.LiveObservationExhausted
                  (LiveWorkflow.Running (LiveWorkflow.LiveDiagnostic "still running"))
              )
          )
      )
        { expectWorkload = Just [ObservedRunning]
        , expectPolls = Just 3
        }
  ]
 where
  exhausted name description observation kind =
    broker
      name
      description
      baselineWorkload
        { scenarioDeliveries = []
        , scenarioObserve = \_ -> pure observation
        , scenarioAttempts = 3
        , scenarioDelayMicros = 1_000
        }
      (failing (Just (LiveWorkflow.LiveObservationExhausted observation)))
        { expectWorkload = Just [kind]
        , expectPolls = Just 3
        }

-- Timeouts --------------------------------------------------------------------------------------

timeoutSpecs :: [LifecycleSpec]
timeoutSpecs =
  [ broker
      "lifecycle-timeout-terminal-without-evidence"
      "a workload that succeeded but whose evidence never arrived must time out, naming the missing evidence"
      baselineWorkload
        { scenarioDeliveries = []
        , scenarioTimeoutMicros = 500_000
        }
      ( failing
          ( Just
              ( LiveWorkflow.LiveTimedOut
                  (Just "evidence incomplete: 0 of 1")
                  (Just (LiveWorkflow.Succeeded terminalName))
              )
          )
      )
        { expectWorkload = Just [ObservedSucceeded]
        , expectPolls = Just 1
        }
  , brokerWith
      "lifecycle-timeout-evidence-without-terminal"
      "completed evidence whose workload never reached a terminal state must time out on the workload, not complete"
      ( do
          evidenceProcessed <- newEmptyMVar
          pure
            (neverTerminal baselineWorkload)
              { scenarioObserve = \_ -> do
                  readMVar evidenceProcessed
                  pure (LiveWorkflow.Running (LiveWorkflow.LiveDiagnostic "still running"))
              , scenarioDeliveries = [(delivery 1) {deliveryAfter = putMVar evidenceProcessed ()}]
              , scenarioTimeoutMicros = 1_000_000
              }
      )
      ( failing
          ( Just
              ( LiveWorkflow.LiveTimedOut
                  Nothing
                  (Just (LiveWorkflow.Running (LiveWorkflow.LiveDiagnostic "still running")))
              )
          )
      )
        { expectConsumer =
            Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal, ConsumerStopped]
        , expectConsumerTrace = Just ("consumer-session" : completingDelivery)
        , expectWorkload = Just [ObservedRunning]
        }
  , broker
      "lifecycle-timeout-response-never-arrives"
      "a request whose validated response never arrives must time out without inventing a workload"
      baselineRequest
        { scenarioDeliveries = []
        , scenarioTimeoutMicros = 500_000
        }
      (failing (Just (LiveWorkflow.LiveTimedOut (Just "evidence incomplete: 0 of 1") Nothing)))
        { expectPlacement = Just requestReply
        , expectWorkload = Just []
        , expectPolls = Just 0
        }
  , local
      "lifecycle-timeout-local-command-never-returns"
      "a host command that never returns must time out, having started but never completed"
      baselineLocal
        { localExecute = newEmptyMVar >>= readMVar
        , localTimeoutMicros = 500_000
        }
      (failing (Just (LiveWorkflow.LiveTimedOut (Just "evidence incomplete: 0 of 1") Nothing)))
        { expectPlacement = Just hostRun
        , expectHooks = ["acquire", "observe-precondition", "execute", "diagnostics", "placement"]
        , expectSpine =
            [ "placement-acquired"
            , "local-source-ready"
            , "local-precondition-observed"
            , "publication-started"
            , "diagnostics"
            , "placement-released"
            ]
        , expectConsumerTrace = Just []
        , expectWorkload = Just []
        , expectPolls = Just 0
        }
  ]

-- Local evidence --------------------------------------------------------------------------------

localSpecs :: [LifecycleSpec]
localSpecs =
  [ local
      "lifecycle-local-precondition-failure-never-executes"
      "a precondition that cannot be observed must fail the run before the command is started"
      baselineLocal {localPrecondition = pure (Left (SETransient "precondition probe failed"))}
      ( localFailing
          (Just (LiveWorkflow.LiveLocalPreconditionFailed (SETransient "precondition probe failed")))
      )
        { expectHooks = ["acquire", "observe-precondition", "diagnostics", "placement"]
        , expectSpine =
            [ "placement-acquired"
            , "local-source-ready"
            , "local-precondition-failed"
            , "diagnostics"
            , "placement-released"
            ]
        , expectConsumerTrace = Just []
        }
  , local
      "lifecycle-local-command-refusal-is-a-publication-failure"
      "a host command that fails must fail the run as a refused publication and resolve no evidence"
      baselineLocal {localExecute = pure (Left (SETransient "command exited 1"))}
      (localFailing (Just (LiveWorkflow.LivePublishFailed (SETransient "command exited 1"))))
        { expectHooks = ["acquire", "observe-precondition", "execute", "diagnostics", "placement"]
        , expectSpine =
            [ "placement-acquired"
            , "local-source-ready"
            , "local-precondition-observed"
            , "publication-started"
            , "publication-failed"
            , "diagnostics"
            , "placement-released"
            ]
        , expectConsumerTrace = Just []
        }
  , local
      "lifecycle-local-evidence-resolution-failure"
      "evidence that cannot be resolved after a successful command must fail the run"
      baselineLocal {localResolve = pure (Left (SETransient "evidence object missing"))}
      (localFailing (Just (LiveWorkflow.LiveLocalEvidenceFailed (SETransient "evidence object missing"))))
        { expectSpine =
            [ "placement-acquired"
            , "local-source-ready"
            , "local-precondition-observed"
            , "publication-started"
            , "published"
            , "local-resolution-started"
            , "local-resolution-failed"
            , "diagnostics"
            , "placement-released"
            ]
        , expectConsumerTrace = Just []
        }
  , local
      "lifecycle-local-evidence-incomplete"
      "resolved evidence that does not complete the contract must fail the run, naming what is missing"
      baselineLocal {localRequired = 2}
      (localFailing (Just (LiveWorkflow.LiveLocalEvidenceIncomplete "evidence incomplete: 1 of 2")))
        { expectConsumerTrace = Just ["evidence-accepted", "evidence-incomplete"]
        }
  , local
      "lifecycle-local-reducer-rejection-has-no-settlement"
      "local evidence the reducer rejects must fail the run, and no delivery is settled because none exists"
      baselineLocal {localRejectsEvidence = True}
      (localFailing (Just (LiveWorkflow.LiveReducerRejected "rejected local evidence")))
        { expectConsumerTrace = Just ["evidence-rejected"]
        }
  ]
 where
  -- A local run reached the evidence stage unless a control says otherwise.
  localFailing primary =
    (failing primary)
      { expectPlacement = Just hostRun
      , expectHooks =
          ["acquire", "observe-precondition", "execute", "resolve", "diagnostics", "placement"]
      , expectSpine =
          [ "placement-acquired"
          , "local-source-ready"
          , "local-precondition-observed"
          , "publication-started"
          , "published"
          , "local-resolution-started"
          , "local-evidence-observed"
          , "diagnostics"
          , "placement-released"
          ]
      , expectConsumer = Just []
      , expectWorkload = Just []
      , expectPolls = Just 0
      }

-- Cleanup ---------------------------------------------------------------------------------------

-- | How a cleanup fails: it reports a leftover, or it throws.
data CleanupFailure
  = CleanupReports
  | CleanupThrows
  deriving stock (Eq, Show, Enum, Bounded)

-- | Make one site's cleanup fail in the given way.  Total over the sites, and
-- the only place a cleanup is made to fail: the site a control claims is the
-- resource its scenario makes fail, by construction.
failCleanupAt :: CleanupSite -> CleanupFailure -> BrokerScenario -> BrokerScenario
failCleanupAt site failure scenario =
  case site of
    CleanupPlacement ->
      scenario
        { scenarioReleasePlacement =
            case failure of
              CleanupReports ->
                pure [LiveWorkflow.CleanupIssue "job jitml-lifecycle-control still present"]
              CleanupThrows -> ioError (userError "kubectl delete exploded")
        }
    CleanupEventSource ->
      scenario
        { scenarioReleaseSource =
            case failure of
              CleanupReports ->
                pure (Left (ConsumerCleanupFailure (SETransient "cursor DELETE returned 500")))
              CleanupThrows -> ioError (userError "cursor DELETE exploded")
        }
    CleanupOwnedObject ->
      scenario
        { scenarioOwnedCleanup =
            Just $
              case failure of
                CleanupReports ->
                  pure [LiveWorkflow.CleanupIssue "bucket lifecycle-fixture still exists"]
                CleanupThrows -> ioError (userError "bucket delete exploded")
        }
    CleanupDiagnostics ->
      scenario
        { scenarioDiagnostics =
            case failure of
              CleanupReports -> pure (Left (LiveWorkflow.CleanupIssue "kubectl logs failed"))
              CleanupThrows -> ioError (userError "kubectl logs exploded")
        }

-- | The cleanup issue the interpreter retains for a failed cleanup; the event
-- source is written @{label}@.  Total over the pairs.
retainedIssue :: CleanupSite -> CleanupFailure -> Text
retainedIssue site failure =
  case (site, failure) of
    (CleanupPlacement, CleanupReports) -> "job jitml-lifecycle-control still present"
    (CleanupPlacement, CleanupThrows) -> "placement cleanup threw: user error (kubectl delete exploded)"
    (CleanupEventSource, CleanupReports) ->
      "subscription cleanup failed for {label}: SETransient \"cursor DELETE returned 500\""
    (CleanupEventSource, CleanupThrows) ->
      "subscription release threw for {label}: user error (cursor DELETE exploded)"
    (CleanupOwnedObject, CleanupReports) -> "bucket lifecycle-fixture still exists"
    (CleanupOwnedObject, CleanupThrows) -> "owned-resource cleanup threw: user error (bucket delete exploded)"
    (CleanupDiagnostics, CleanupReports) -> "kubectl logs failed"
    (CleanupDiagnostics, CleanupThrows) -> "diagnostics threw: user error (kubectl logs exploded)"

-- | Where a failed cleanup lands in the journal of an otherwise complete run: a
-- release that fails is journalled as a retained cleanup issue and never as a
-- release, and a failed diagnostics gather is a retained issue in place of the
-- diagnostics record.  An owned object is cleaned after the interpreter returns,
-- so its issue is appended.
cleanupSpine :: CleanupSite -> [Text]
cleanupSpine site =
  case site of
    CleanupPlacement -> filter (/= "placement-released") spineRan <> ["cleanup-recorded"]
    CleanupEventSource -> replaceLabel "source-released" spineRan
    CleanupOwnedObject -> spineRan <> ["cleanup-recorded"]
    CleanupDiagnostics -> replaceLabel "diagnostics" spineRan
 where
  replaceLabel target =
    fmap (\label -> if label == target then "cleanup-recorded" else label)

renderCleanupSite :: CleanupSite -> Text
renderCleanupSite site =
  case site of
    CleanupPlacement -> "placement"
    CleanupEventSource -> "source"
    CleanupOwnedObject -> "owned-object"
    CleanupDiagnostics -> "diagnostics"

-- | The resource a cleanup site names, for the control's description.
describeCleanupSite :: CleanupSite -> Text
describeCleanupSite site =
  case site of
    CleanupPlacement -> "placement release"
    CleanupEventSource -> "event-source release"
    CleanupOwnedObject -> "owned-object cleanup"
    CleanupDiagnostics -> "diagnostics gather"

renderCleanupFailure :: CleanupFailure -> Text
renderCleanupFailure failure =
  case failure of
    CleanupReports -> "failure"
    CleanupThrows -> "exception"

-- | A run that completed except for one cleanup: the completion facts survive,
-- no primary failure is reported, and only the cleanup makes the run a failure.
completedExcept :: [Text] -> [Text] -> Expectation
completedExcept issues spine =
  (failing Nothing)
    { expectCompletion = Just survivingCompletion
    , expectCleanup = issues
    , expectSpine = spine
    , expectConsumer =
        Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal, ConsumerStopped]
    , expectConsumerTrace = Just ("consumer-session" : completingDelivery)
    , expectWorkload = Just [ObservedSucceeded]
    , expectPolls = Just 1
    }

-- | A run that completed except for one cleanup, which must be retained, must
-- never mint completion, and must never replace the primary failure.  One control
-- per resource the run owns and per way its cleanup can fail, and one for a
-- cleanup failure beside a primary failure.
cleanupSpecs :: [LifecycleSpec]
cleanupSpecs =
  [ cleanupSpec site failure
  | site <- [minBound ..]
  , failure <- [minBound ..]
  ]
    <> [cleanupBesidePrimary]
 where
  cleanupSpec site failure =
    broker
      ( "lifecycle-"
          <> renderCleanupSite site
          <> "-cleanup-"
          <> renderCleanupFailure failure
          <> "-never-mints-completion"
      )
      ( "the "
          <> describeCleanupSite site
          <> (case failure of CleanupReports -> " reports a failure"; CleanupThrows -> " throws")
          <> ": it must be retained as a cleanup issue, and the run must not mint completion"
      )
      (failCleanupAt site failure baselineWorkload)
      ( (completedExcept [retainedIssue site failure] (cleanupSpine site))
          { expectDiagnostics = [scriptedDiagnostics | site /= CleanupDiagnostics]
          }
      )
      & covering [CoversCleanup site]
  -- The workload fails after its evidence completed, and the placement release
  -- fails too: the workload failure stays the primary and the cleanup is retained.
  cleanupBesidePrimary =
    brokerWith
      "lifecycle-cleanup-failure-never-replaces-the-primary"
      "a cleanup failure beside a workload failure must be retained without displacing the workload failure"
      ( do
          evidenceProcessed <- newEmptyMVar
          pure
            ( failCleanupAt
                CleanupPlacement
                CleanupReports
                baselineWorkload
                  { scenarioObserve = \_ -> do
                      readMVar evidenceProcessed
                      pure (LiveWorkflow.Failed (LiveWorkflow.WorkloadFailure "container OOMKilled"))
                  , scenarioDeliveries = [(delivery 1) {deliveryAfter = putMVar evidenceProcessed ()}]
                  }
            )
      )
      ( ( failing
            (Just (LiveWorkflow.LiveWorkloadFailed (LiveWorkflow.WorkloadFailure "container OOMKilled")))
        )
          { expectCleanup = [retainedIssue CleanupPlacement CleanupReports]
          , expectSpine = cleanupSpine CleanupPlacement
          , expectWorkload = Just [ObservedFailed]
          }
      )
      & covering [CoversCleanup CleanupPlacement]

-- Terminal/evidence join ------------------------------------------------------------------------

-- | The pure join of the workload terminal and the completed evidence.
joinSpecs :: [LifecycleSpec]
joinSpecs =
  [ join
      "lifecycle-join-conflicting-terminal-observation"
      "a second, different terminal observation must not replace the first"
      ( LiveWorkflow.completionJoinTerminal "terminal-a" LiveWorkflow.emptyCompletionJoin
          >>= LiveWorkflow.completionJoinTerminal "terminal-b"
      )
      LiveWorkflow.ConflictingTerminalObservation
  , join
      "lifecycle-join-conflicting-terminal-after-completion"
      "a different terminal observation must be refused even after the join completed"
      ( LiveWorkflow.completionJoinTerminal "terminal-a" LiveWorkflow.emptyCompletionJoin
          >>= LiveWorkflow.completionJoinEvidence "evidence-a"
          >>= LiveWorkflow.completionJoinTerminal "terminal-b"
      )
      LiveWorkflow.ConflictingTerminalObservation
  , join
      "lifecycle-join-conflicting-completed-evidence"
      "a second, different completed evidence must not replace the first"
      ( LiveWorkflow.completionJoinEvidence "evidence-a" LiveWorkflow.emptyCompletionJoin
          >>= LiveWorkflow.completionJoinEvidence "evidence-b"
      )
      LiveWorkflow.ConflictingCompletedEvidence
  , join
      "lifecycle-join-conflicting-evidence-after-completion"
      "different completed evidence must be refused even after the join completed"
      ( LiveWorkflow.completionJoinEvidence "evidence-a" LiveWorkflow.emptyCompletionJoin
          >>= LiveWorkflow.completionJoinTerminal "terminal-a"
          >>= LiveWorkflow.completionJoinEvidence "evidence-b"
      )
      LiveWorkflow.ConflictingCompletedEvidence
  , lone
      "lifecycle-join-terminal-alone-never-completes"
      "a terminal observation without completed evidence must not join into a completion"
      (LiveWorkflow.completionJoinTerminal "terminal-a" LiveWorkflow.emptyCompletionJoin)
  , lone
      "lifecycle-join-evidence-alone-never-completes"
      "completed evidence without a terminal observation must not join into a completion"
      (LiveWorkflow.completionJoinEvidence "evidence-a" LiveWorkflow.emptyCompletionJoin)
  ]
 where
  join
    :: Text
    -> Text
    -> Either LiveWorkflow.CompletionJoinError (LiveWorkflow.CompletionJoin Text Text)
    -> LiveWorkflow.CompletionJoinError
    -> LifecycleSpec
  join name description joined expected =
    LifecycleSpec
      { specName = name
      , specDescription = description
      , specCovers = [CoversJoinError (joinErrorKind expected)]
      , specCheck = PureCheck (rejectedWith expected (void joined))
      }
  lone
    :: Text
    -> Text
    -> Either LiveWorkflow.CompletionJoinError (LiveWorkflow.CompletionJoin Text Text)
    -> LifecycleSpec
  lone name description joined =
    LifecycleSpec
      { specName = name
      , specDescription = description
      , specCovers = []
      , specCheck =
          PureCheck $
            withFixture (first (Text.pack . show) joined) $ \state ->
              rejectedWith
                ("a single fact is not a completion" :: Text)
                ( maybe
                    (Left "a single fact is not a completion")
                    (const (Right ()))
                    (LiveWorkflow.joinedCompletion state)
                )
      }

-- Harness ---------------------------------------------------------------------------------------

-- | The verdict logic on the inputs it must and must not pass.  A control is
-- only as sound as 'judge': a run the interpreter completed must be reported as
-- accepted, a run rejected for another reason must not pass, and only the exact
-- rejection may, including the completion facts (the terminal and the evidence)
-- that survived a cleanup failure.  A non-empty result means the lifecycle
-- controls could be passing for any reason.
lifecycleHarnessFailures :: IO [Text]
lifecycleHarnessFailures = do
  label <- sourceLabel
  completed <- boundedRun (runBrokerScenario baselineWorkload)
  refused <-
    boundedRun (runBrokerScenario baselineWorkload {scenarioPublish = pure (Left publicationRefusal)})
  -- A run that completed on two deliveries and then failed its placement cleanup:
  -- its surviving evidence is not the one the baseline controls pin, so a verdict
  -- that ignored the observed evidence could not pass for it.
  cleanedUp <-
    boundedRun
      ( runBrokerScenario
          ( failCleanupAt
              CleanupPlacement
              CleanupReports
              baselineWorkload {scenarioDeliveries = [delivery 1, delivery 2], scenarioRequired = 2}
          )
      )
  comparison <- completionComparisonFailures
  let verdict = judge label
      otherReason = failing (Just (LiveWorkflow.LiveEstablishFailed (SEConflict "not the refusal")))
      extraDefect = publicationRefusalExpectation {expectCleanup = ["an unexpected cleanup issue"]}
      survivors =
        (completedExcept [retainedIssue CleanupPlacement CleanupReports] (cleanupSpine CleanupPlacement))
          { expectCompletion = Just (LiveWorkflow.IndependentWorkloadSucceeded terminalName, orderedEvidence)
          , expectDiagnostics = [scriptedDiagnostics]
          , expectConsumer = Nothing
          , expectConsumerTrace = Nothing
          }
      otherEvidence =
        survivors
          { expectCompletion = Just (LiveWorkflow.IndependentWorkloadSucceeded terminalName, [epochLabel 1])
          }
      otherTerminal =
        survivors {expectCompletion = Just (LiveWorkflow.RequestResponseCompleted, orderedEvidence)}
  pure . concat $
    [ [ "a run the interpreter completed was reported as " <> renderShown outcome
      | let outcome = verdict publicationRefusalExpectation completed
      , outcome /= Accepted
      ]
    , [ "a run rejected for a different primary failure was reported as " <> renderShown outcome
      | let outcome = verdict otherReason refused
      , not (isWrongReason outcome)
      ]
    , [ "a run with an unexpected extra defect was reported as " <> renderShown outcome
      | let outcome = verdict extraDefect refused
      , not (isWrongReason outcome)
      ]
    , [ "the exact rejection was reported as " <> renderShown outcome
      | let outcome = verdict publicationRefusalExpectation refused
      , outcome /= Rejected
      ]
    , [ "the exact surviving completion was reported as " <> renderShown outcome
      | let outcome = verdict survivors cleanedUp
      , outcome /= Rejected
      ]
    , [ "a run whose surviving evidence differs was reported as " <> renderShown outcome
      | let outcome = verdict otherEvidence cleanedUp
      , not (isWrongReason outcome)
      ]
    , [ "a run whose surviving terminal fact differs was reported as " <> renderShown outcome
      | let outcome = verdict otherTerminal cleanedUp
      , not (isWrongReason outcome)
      ]
    , comparison
    ]
 where
  isWrongReason outcome =
    case outcome of
      RejectedForWrongReason _ _ -> True
      Rejected -> False
      Accepted -> False
      FixtureFailed _ -> False

-- | The completion comparison of the ordering guard ('completionDifferences') on
-- the inputs it must and must not flag.  A completion is never different from
-- itself, and each variant below differs from the reference run in known facts,
-- which the comparison must name exactly: one that cannot flag a fact (the
-- evidence, say) or that flags one that is the same would make the ordering
-- guard pass for any pair of orders.  A non-empty result means the comparison is
-- not sound.
completionComparisonFailures :: IO [Text]
completionComparisonFailures = do
  reference <- completionOf "the reference run" <$> boundedRun (runBrokerScenario baselineWorkload)
  variants <-
    traverse
      ( \(label, scenario, differing) -> do
          run <- completionOf label <$> boundedRun (runBrokerScenario scenario)
          pure (label, run, differing)
      )
      variantRuns
  pure $
    case reference of
      Left detail -> [detail]
      Right referenceRun ->
        [ "the comparison reported a completion as different from itself: " <> renderShown differences
        | let differences = completionDifferences referenceRun referenceRun
        , not (null differences)
        ]
          <> concat
            [ case run of
                Left detail -> [detail]
                Right variantRun ->
                  [ "the comparison of "
                      <> label
                      <> " reported "
                      <> renderShown differences
                      <> " instead of "
                      <> renderShown differing
                  | let differences = completionDifferences referenceRun variantRun
                  , differences /= differing
                  ]
            | (label, run, differing) <- variants
            ]
 where
  completionOf label observation =
    case obsResult observation of
      Left failure -> Left (label <> " did not complete: " <> renderShown failure)
      Right completedRun -> Right completedRun
  -- Every variant completes; the third field is what the comparison against the
  -- reference (one delivery, a cluster job on the baseline workload, one
  -- acknowledgement) must report, in the comparison's order.
  variantRuns =
    [
      ( "a run that accepted a second delivery"
      , baselineWorkload {scenarioDeliveries = [delivery 1, delivery 2], scenarioRequired = 2}
      , ["evidence", "set of journal records"]
      )
    ,
      ( "a request/reply run"
      , baselineRequest
      , ["placement", "terminal fact", "set of journal records"]
      )
    ,
      ( "a run on a host placement"
      , baselineWorkload {scenarioPlacement = HostPlacement}
      , ["placement", "set of journal records"]
      )
    ,
      ( "a run with other diagnostics"
      , baselineWorkload
          { scenarioDiagnostics = pure (Right [LiveWorkflow.LiveDiagnostic "other diagnostics"])
          }
      , ["diagnostics", "set of journal records"]
      )
    ,
      ( "a run with another publication acknowledgement"
      , baselineWorkload {scenarioPublish = pure (Right "another-ack")}
      , ["set of journal records"]
      )
    ]

-- Baselines and orderings (positive) --------------------------------------------------------------

-- | Whether the reference runs themselves complete, with the journal, settlement
-- and evidence the controls assume.  A non-empty result means the controls above
-- could be passing only because their baseline was already broken.
lifecycleBaselineFailures :: IO [Text]
lifecycleBaselineFailures = do
  workload <- boundedRun (runBrokerScenario baselineWorkload)
  request <- boundedRun (runBrokerScenario baselineRequest)
  localRun <- boundedRun (runLocalScenario baselineLocal)
  pure $
    completedAs
      "the independent-workload baseline"
      (LiveWorkflow.IndependentWorkloadSucceeded terminalName)
      [epochLabel 1]
      spineRan
      (Just ("consumer-session" : completingDelivery))
      (Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal, ConsumerStopped])
      hooksRan
      1
      workload
      <> completedAs
        "the request/reply baseline"
        LiveWorkflow.RequestResponseCompleted
        [epochLabel 1]
        spineRan
        (Just ("consumer-session" : completingDelivery))
        (Just [ConsumerAttached, ConsumerSettled PulsarInternal.AckInternal, ConsumerStopped])
        hooksRan
        0
        request
      <> completedAs
        "the local baseline"
        (LiveWorkflow.ExecutableCommandSucceeded "executed")
        ["resolved-evidence"]
        [ "placement-acquired"
        , "local-source-ready"
        , "local-precondition-observed"
        , "publication-started"
        , "published"
        , "local-resolution-started"
        , "local-evidence-observed"
        , "diagnostics"
        , "placement-released"
        ]
        (Just ["evidence-accepted", "evidence-completed"])
        Nothing
        ["acquire", "observe-precondition", "execute", "resolve", "diagnostics", "placement"]
        0
        localRun
 where
  completedAs label terminal evidence spine consumerTrace consumer hooks polls observation =
    case obsResult observation of
      Left failure -> [label <> " did not complete: " <> Text.pack (show failure)]
      Right completed ->
        let trace = completedTrace completed
         in [ label
                <> " completed with terminal "
                <> Text.pack (show (LiveWorkflow.completedRunTerminal completed))
            | LiveWorkflow.completedRunTerminal completed /= terminal
            ]
              <> [ label
                     <> " completed with evidence "
                     <> Text.pack (show (LiveWorkflow.completedRunEvidence completed))
                 | LiveWorkflow.completedRunEvidence completed /= evidence
                 ]
              <> [ label <> " journalled " <> Text.pack (show (traceSpine trace))
                 | traceSpine trace /= spine
                 ]
              <> [ label <> " settled " <> Text.pack (show (traceConsumer trace))
                 | Just expected <- [consumerTrace]
                 , traceConsumer trace /= expected
                 ]
              <> [ label <> " consumed " <> Text.pack (show (obsConsumerLog observation))
                 | Just events <- [consumer]
                 , obsConsumerLog observation /= events
                 ]
              <> [ label <> " drove " <> Text.pack (show (obsInterpreterHooks observation))
                 | obsInterpreterHooks observation /= hooks
                 ]
              <> [ label <> " observed the workload " <> Text.pack (show (obsPolls observation)) <> " times"
                 | obsPolls observation /= polls
                 ]
              <> [ label <> " kept the diagnostics " <> Text.pack (show diagnostics)
                 | let diagnostics = fmap LiveWorkflow.unLiveDiagnostic (LiveWorkflow.completedRunDiagnostics completed)
                 , diagnostics /= [scriptedDiagnostics]
                 ]

-- | The facts in which two completed runs differ, named in the order they are
-- compared.  Two arrival orders of the same facts must mint the same completion,
-- so the comparison covers everything a completion carries: the placement, the
-- terminal fact, the evidence (the accepted events, a real value, so a different
-- evidence is a difference), the diagnostics, and the set of journal records
-- (their order is the one thing that legitimately differs between arrival
-- orders).
completionDifferences :: ScenarioCompleted -> ScenarioCompleted -> [Text]
completionDifferences left right =
  [ label
  | (label, same) <-
      [
        ( "placement"
        , LiveWorkflow.completedRunPlacement left == LiveWorkflow.completedRunPlacement right
        )
      ,
        ( "terminal fact"
        , LiveWorkflow.completedRunTerminal left == LiveWorkflow.completedRunTerminal right
        )
      ,
        ( "evidence"
        , LiveWorkflow.completedRunEvidence left == LiveWorkflow.completedRunEvidence right
        )
      ,
        ( "diagnostics"
        , LiveWorkflow.completedRunDiagnostics left == LiveWorkflow.completedRunDiagnostics right
        )
      ,
        ( "set of journal records"
        , sort (fmap show (journalEvents left)) == sort (fmap show (journalEvents right))
        )
      ]
  , not same
  ]
 where
  journalEvents = fmap LiveWorkflow.liveJournalEvent . LiveWorkflow.completedRunJournal

-- | The two arrival orders of the workload terminal and the completed evidence,
-- forced by gates, must mint the same completion: the same placement, terminal
-- fact, evidence, diagnostics, and set of journal records ('completionDifferences'),
-- and each must mint the evidence the scenario delivered, so two orders that are
-- equally wrong are not the same completion either.  The journals differ only in
-- the order in which they record the two facts, which is the point: the order
-- each scenario forced is checked against the journal.
lifecycleOrderingFailures :: IO [Text]
lifecycleOrderingFailures = do
  terminalFirst <- terminalFirstScenario >>= boundedRun . runBrokerScenario
  evidenceFirst <- evidenceFirstScenario >>= boundedRun . runBrokerScenario
  pure $
    case (obsResult terminalFirst, obsResult evidenceFirst) of
      (Right terminalRun, Right evidenceRun) ->
        [ "the terminal-first run did not journal the terminal before the first delivery"
        | before isWorkload isDelivery terminalRun /= Just True
        ]
          <> [ "the evidence-first run did not journal the evidence as completed before the terminal"
             | before isCompletion isWorkload evidenceRun /= Just True
             ]
          <> [ "the "
                 <> order
                 <> " run minted the evidence "
                 <> Text.pack (show (LiveWorkflow.completedRunEvidence run))
                 <> " instead of the accepted deliveries "
                 <> Text.pack (show orderedEvidence)
             | (order, run) <- [("terminal-first", terminalRun), ("evidence-first", evidenceRun)]
             , LiveWorkflow.completedRunEvidence run /= orderedEvidence
             ]
          <> [ "the two orders minted a different " <> label
             | label <- completionDifferences terminalRun evidenceRun
             ]
      (Left failure, _) -> ["the terminal-first run did not complete: " <> Text.pack (show failure)]
      (_, Left failure) -> ["the evidence-first run did not complete: " <> Text.pack (show failure)]
 where
  -- Whether the first journal record matching the first predicate was written
  -- before the first one matching the second, or 'Nothing' when either is missing.
  before earlier later completed =
    (<)
      <$> firstSequence earlier journal
      <*> firstSequence later journal
   where
    journal = LiveWorkflow.completedRunJournal completed
  firstSequence predicate journal =
    case [ LiveWorkflow.liveJournalSequence record
         | record <- journal
         , predicate (LiveWorkflow.liveJournalEvent record)
         ] of
      [] -> Nothing
      sequences -> Just (minimum sequences :: Word64)
  isWorkload event = fst (classifyJournalEvent event) == ObserverLane
  isDelivery event = classifyJournalEvent event == (ConsumerLane, "delivery-observed")
  isCompletion event = classifyJournalEvent event == (ConsumerLane, "evidence-completed")

-- | The two ordering scenarios deliver the same two epochs and the evidence
-- completes only with the second, so the completed evidence is a value that
-- depends on what was delivered and in which order, not a unit.  The first
-- delivery waits for the given action before it is handed to the interpreter; the
-- given action runs once the last delivery has been handled, so its evidence is
-- already recorded.
orderedDeliveries :: IO () -> IO () -> [ScriptedDelivery]
orderedDeliveries beforeFirst afterLast =
  [ (delivery 1) {deliveryBefore = beforeFirst}
  , (delivery 2) {deliveryAfter = afterLast}
  ]

-- | The evidence those two deliveries complete.
orderedEvidence :: ScenarioEvidence
orderedEvidence = [epochLabel 1, epochLabel 2]

-- | The terminal is observed, and its observer thread has finished, before any
-- evidence is delivered.  The evidence needs two deliveries, so completion is
-- the last of several facts to arrive, as it is in a real run.
terminalFirstScenario :: IO BrokerScenario
terminalFirstScenario = do
  observerThread <- newEmptyMVar
  pure
    baselineWorkload
      { scenarioObserve = \_ -> do
          myThreadId >>= putMVar observerThread
          pure (LiveWorkflow.Succeeded terminalName)
      , scenarioDeliveries =
          orderedDeliveries (readMVar observerThread >>= awaitThreadFinished) (pure ())
      , scenarioRequired = length orderedEvidence
      }

-- | The evidence is delivered and recorded as complete (its last delivery
-- handled) before the workload is observed at all.
evidenceFirstScenario :: IO BrokerScenario
evidenceFirstScenario = do
  evidenceProcessed <- newEmptyMVar
  pure
    baselineWorkload
      { scenarioObserve = \_ -> do
          readMVar evidenceProcessed
          pure (LiveWorkflow.Succeeded terminalName)
      , scenarioDeliveries = orderedDeliveries (pure ()) (putMVar evidenceProcessed ())
      , scenarioRequired = length orderedEvidence
      }
