{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Consumer
  ( ConsumerOutcome (..)
  , DaemonCommand (..)
  , DaemonSubscription
  , DaemonSubscriptionPlanError (..)
  , DedupCache (..)
  , EventDomain (..)
  , EventId
  , HandlerRouter (..)
  , consumerOutcomeError
  , consumerStep
  , consumerStepAt
  , consumerStepCommitted
  , consumeDaemonSubscription
  , consumeDaemonSubscriptionBatches
  , daemonSubscriptionDomain
  , daemonSubscriptionName
  , daemonSubscriptionOwnership
  , daemonSubscriptionStart
  , daemonSubscriptionTopicName
  , daemonSubscriptionsForBootConfig
  , daemonCommandDomain
  , daemonCommandEventId
  , daemonCommandPayload
  , daemonCommandPlanId
  , daemonCommandSubstrate
  , dedupCacheCapacity
  , dedupCacheExpireAt
  , dedupCacheInsert
  , dedupCacheInsertAt
  , dedupCacheKnown
  , dedupCacheKnownAt
  , emptyDedupCache
  , emptyDedupCacheWithTtl
  , emptyHandlerRouter
  , emptyHandlerRouterWithTtl
  , eventIdText
  , processAtLeastOnce
  , routeByKind
  , routeByKindAt
  , reconfigureHandlerRouter
  , reconfigureHandlerRouterAt
  , runConsumerLoop
  )
where

import Control.Concurrent.MVar (MVar, modifyMVar)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Either.Combinators (mapLeft)
import Data.IORef
  ( atomicModifyIORef'
  , modifyIORef'
  , newIORef
  , readIORef
  , writeIORef
  )
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import System.Posix.Time (epochTime)

import JitML.AppError.AppError (AppError (..))
import JitML.Coordinator.Topology
  ( ProtocolRoute (..)
  , Topic
  , TopicError
  , topicFor
  , topicName
  , topicSubstrate
  )
import JitML.Plan.Plan
  ( EventId
  , PlanError
  , PlanId
  , Validation (..)
  , deriveEventIdForPlanId
  , eventIdText
  , planIdFromCanonicalText
  )
import JitML.Proto.Inference (InferenceCommand (..), renderInferenceCommand)
import JitML.Proto.Inference qualified as Inference
import JitML.Proto.Rl (RlCommand (..), renderRlCommand)
import JitML.Proto.Rl qualified as Rl
import JitML.Proto.Training (TrainingCommand (..), renderTrainingCommand)
import JitML.Proto.Training qualified as Training
import JitML.Proto.Tune (TuneCommand (..), renderTuneCommand)
import JitML.Proto.Tune qualified as Tune
import JitML.Service.BootConfig
  ( BootConfig (..)
  , Residency (..)
  , Role (..)
  )
import JitML.Service.Capabilities
  ( ConsumerBatchDecision
  , ConsumerDecision
  , ConsumerFailure (..)
  , ConsumerSessionEvent
  , DeliveryBatch
  , Disposition
  , HasPulsar (..)
  , NackReason (..)
  , Subscription
  , SubscriptionError
  , SubscriptionOwnership (..)
  , SubscriptionStart (..)
  , ack
  , continue
  , deliveryEvent
  , done
  , mapDeliveryBatch
  , mkSubscription
  , nack
  , subscriptionName
  , subscriptionOwnership
  , subscriptionStart
  )
import JitML.Service.InferenceBatch (BatchPolicy)
import JitML.Service.Retry (ServiceError (..), serviceErrorToAppError)
import JitML.Sub.Outcome (ProcessOutcome (..))
import JitML.Substrate (Substrate (..), renderSubstrate)

processAtLeastOnce :: (Ord eventId) => [eventId] -> [eventId]
processAtLeastOnce = reverse . foldl insertIfMissing []
 where
  insertIfMissing seen eventId
    | eventId `elem` seen = seen
    | otherwise = eventId : seen

data EventDomain
  = TrainingDomain
  | TuneDomain
  | RlDomain
  | InferenceDomain
  deriving stock (Eq, Show)

-- | The closed command family accepted by daemon consumers after the topic
-- codec has succeeded.  The consumed topology route supplies the substrate;
-- downstream dispatch never reparses text or trusts a substrate embedded in a
-- payload to select placement.
data DaemonCommand
  = TrainingDaemonCommand Substrate TrainingCommand
  | TuneDaemonCommand Substrate TuneCommand
  | RlDaemonCommand Substrate RlCommand
  | InferenceDaemonCommand Substrate InferenceCommand
  deriving stock (Eq, Show)

daemonCommandDomain :: DaemonCommand -> EventDomain
daemonCommandDomain command =
  case command of
    TrainingDaemonCommand _substrate _command -> TrainingDomain
    TuneDaemonCommand _substrate _command -> TuneDomain
    RlDaemonCommand _substrate _command -> RlDomain
    InferenceDaemonCommand _substrate _command -> InferenceDomain

daemonCommandSubstrate :: DaemonCommand -> Substrate
daemonCommandSubstrate command =
  case command of
    TrainingDaemonCommand substrate _command -> substrate
    TuneDaemonCommand substrate _command -> substrate
    RlDaemonCommand substrate _command -> substrate
    InferenceDaemonCommand substrate _command -> substrate

daemonCommandPayload :: DaemonCommand -> Text
daemonCommandPayload command =
  case command of
    TrainingDaemonCommand _substrate training -> renderTrainingCommand training
    TuneDaemonCommand _substrate tune -> renderTuneCommand tune
    RlDaemonCommand _substrate rl -> renderRlCommand rl
    InferenceDaemonCommand _substrate inference -> renderInferenceCommand inference

-- | Derive the stable plan identity for a command only after the route codec
-- has produced the closed 'DaemonCommand' family.  The canonical text includes
-- the protocol version, typed domain and routed substrate as well as the
-- workload codec's canonical rendering, so alternate wire encodings of the
-- same typed command agree while any resolved command input changes the plan.
daemonCommandPlanId :: DaemonCommand -> Validation (NonEmpty PlanError) PlanId
daemonCommandPlanId command =
  planIdFromCanonicalText
    ( Text.unlines
        [ "jitml-daemon-command-version: 1"
        , "domain: " <> daemonCommandDomainText command
        , "substrate: " <> renderSubstrate (daemonCommandSubstrate command)
        , "payload:"
        ]
        <> daemonCommandPayload command
    )

-- | Semantic command identity is plan-bound and independent of Pulsar delivery
-- receipts.  Event kind and logical key come from the decoded command rather
-- than caller-controlled bytes.
daemonCommandEventId :: DaemonCommand -> Validation (NonEmpty PlanError) EventId
daemonCommandEventId command =
  case daemonCommandPlanId command of
    Failure errors -> Failure errors
    Success planId ->
      deriveEventIdForPlanId
        planId
        (daemonCommandKind command)
        (daemonCommandLogicalKey command)

daemonCommandDomainText :: DaemonCommand -> Text
daemonCommandDomainText command =
  case daemonCommandDomain command of
    TrainingDomain -> "training"
    TuneDomain -> "tune"
    RlDomain -> "rl"
    InferenceDomain -> "inference"

daemonCommandKind :: DaemonCommand -> Text
daemonCommandKind command =
  case command of
    TrainingDaemonCommand _ (TrainingStart _) -> "StartTraining"
    TrainingDaemonCommand _ (TrainingStop _) -> "StopTraining"
    TuneDaemonCommand _ (TuneStart _) -> "StartSweep"
    TuneDaemonCommand _ (TuneStop _) -> "StopSweep"
    RlDaemonCommand _ (RlStart _) -> "StartRLRun"
    RlDaemonCommand _ (RlStartAlphaZero _) -> "StartAlphaZeroRun"
    RlDaemonCommand _ (RlStop _) -> "StopRLRun"
    InferenceDaemonCommand _ (RunInference _) -> "RunInference"
    InferenceDaemonCommand _ (CompareCheckpoints _) -> "CheckpointCompareCommand"
    InferenceDaemonCommand _ (SelectAdversarialMove _) -> "AdversarialMoveCommand"
    InferenceDaemonCommand _ (ListCheckpoints _) -> "ListCheckpointsCommand"
    InferenceDaemonCommand _ (LoadTranscript _) -> "LoadTranscriptCommand"

daemonCommandLogicalKey :: DaemonCommand -> Text
daemonCommandLogicalKey command =
  case command of
    TrainingDaemonCommand _ (TrainingStart start) -> Training.stExperimentHash start
    TrainingDaemonCommand _ (TrainingStop stop) -> Training.stopExperimentHash stop
    TuneDaemonCommand _ (TuneStart start) -> Tune.ssExperimentHash start
    TuneDaemonCommand _ (TuneStop stop) -> Tune.ssStopExperimentHash stop
    RlDaemonCommand _ (RlStart start) -> Rl.srlExperimentHash start
    RlDaemonCommand _ (RlStartAlphaZero start) -> Rl.sazExperimentHash start
    RlDaemonCommand _ (RlStop stop) -> Rl.srStopExperimentHash stop
    InferenceDaemonCommand _ (RunInference request) -> Inference.irCallId request
    InferenceDaemonCommand _ (CompareCheckpoints request) -> Inference.cccCallId request
    InferenceDaemonCommand _ (SelectAdversarialMove request) -> Inference.amcCallId request
    InferenceDaemonCommand _ (ListCheckpoints request) -> Inference.lccCallId request
    InferenceDaemonCommand _ (LoadTranscript request) -> Inference.ltcCallId request

-- | An existential typed subscription.  The topic codec and subscription
-- constructor remain hidden; callers can inspect only safe projections or run
-- a rank-n action through 'consumeDaemonSubscription'.
data DaemonSubscription where
  DaemonSubscription
    :: EventDomain
    -> Topic event
    -> Subscription event
    -> (Substrate -> event -> DaemonCommand)
    -> DaemonSubscription

instance Eq DaemonSubscription where
  left == right =
    daemonSubscriptionDomain left == daemonSubscriptionDomain right
      && daemonSubscriptionTopicName left == daemonSubscriptionTopicName right
      && daemonSubscriptionName left == daemonSubscriptionName right
      && daemonSubscriptionStart left == daemonSubscriptionStart right
      && daemonSubscriptionOwnership left == daemonSubscriptionOwnership right

instance Show DaemonSubscription where
  showsPrec precedence subscription =
    showParen (precedence > 10) $
      showString "DaemonSubscription "
        . shows
          ( daemonSubscriptionDomain subscription
          , daemonSubscriptionTopicName subscription
          , daemonSubscriptionName subscription
          , daemonSubscriptionStart subscription
          , daemonSubscriptionOwnership subscription
          )

data DaemonSubscriptionPlanError
  = DaemonSubscriptionTopicError TopicError
  | DaemonSubscriptionValidationError SubscriptionError
  deriving stock (Eq, Show)

daemonSubscriptionDomain :: DaemonSubscription -> EventDomain
daemonSubscriptionDomain (DaemonSubscription domain _topic _subscription _toCommand) = domain

daemonSubscriptionTopicName :: DaemonSubscription -> Text
daemonSubscriptionTopicName (DaemonSubscription _domain topic _subscription _toCommand) = topicName topic

daemonSubscriptionName :: DaemonSubscription -> Text
daemonSubscriptionName (DaemonSubscription _domain _topic subscription _toCommand) =
  subscriptionName subscription

daemonSubscriptionStart :: DaemonSubscription -> SubscriptionStart
daemonSubscriptionStart (DaemonSubscription _domain _topic subscription _toCommand) =
  subscriptionStart subscription

daemonSubscriptionOwnership :: DaemonSubscription -> SubscriptionOwnership
daemonSubscriptionOwnership (DaemonSubscription _domain _topic subscription _toCommand) =
  subscriptionOwnership subscription

consumeDaemonSubscription
  :: (HasPulsar m)
  => DaemonSubscription
  -> (ConsumerSessionEvent -> m ())
  -> (DaemonCommand -> m (ConsumerDecision result))
  -> m (Either ConsumerFailure result)
consumeDaemonSubscription (DaemonSubscription _domain topic subscription toCommand) observe handler =
  pulsarConsumeUntil subscription observe $ \delivery ->
    handler (toCommand (topicSubstrate topic) (deliveryEvent delivery))

-- | Batch counterpart of 'consumeDaemonSubscription'.  The existential topic
-- event is decoded and mapped to the closed daemon command family without
-- exposing either the topic witness or any broker receipt.  Compatibility is
-- evaluated on the mapped command, while the handler receives the original
-- admission window through the opaque 'DeliveryBatch'.
consumeDaemonSubscriptionBatches
  :: (HasPulsar m, Eq key)
  => DaemonSubscription
  -> m BatchPolicy
  -> (DaemonCommand -> key)
  -> (ConsumerSessionEvent -> m ())
  -> (DeliveryBatch DaemonCommand -> m (ConsumerBatchDecision result))
  -> m (Either ConsumerFailure result)
consumeDaemonSubscriptionBatches
  (DaemonSubscription _domain topic subscription toCommand)
  readPolicy
  compatibilityKey
  observe
  handler =
    pulsarConsumeBatchesUntil
      readPolicy
      (compatibilityKey . toDaemonCommand)
      subscription
      observe
      (handler . mapDeliveryBatch toDaemonCommand)
   where
    toDaemonCommand = toCommand (topicSubstrate topic)

daemonSubscriptionsForBootConfig
  :: BootConfig
  -> Either DaemonSubscriptionPlanError [DaemonSubscription]
daemonSubscriptionsForBootConfig bootConfig =
  traverse buildSubscription (subscriptionRoutes bootConfig)
 where
  buildSubscription (SomeSubscriptionRoute domain route name toCommand) = do
    topic <- firstPlanError (topicFor route (bootSubstrate bootConfig))
    subscription <-
      firstSubscriptionError
        (mkSubscription topic name FromEarliest Borrowed)
    pure (DaemonSubscription domain topic subscription toCommand)

data SomeSubscriptionRoute where
  SomeSubscriptionRoute
    :: EventDomain
    -> ProtocolRoute event
    -> Text
    -> (Substrate -> event -> DaemonCommand)
    -> SomeSubscriptionRoute

subscriptionRoutes :: BootConfig -> [SomeSubscriptionRoute]
subscriptionRoutes bootConfig =
  case bootActiveRole bootConfig of
    Engine -> engineSubscriptionRoutes bootConfig
    Coordinator -> coordinatorSubscriptionRoutes bootConfig
    Webapp -> []

-- | Engine owns only substrate compute. Linux Engines consume inference; the
-- Apple host Engine consumes the four host-command families. Cluster placement
-- commands are deliberately absent from this plan.
engineSubscriptionRoutes :: BootConfig -> [SomeSubscriptionRoute]
engineSubscriptionRoutes bootConfig =
  case (bootSubstrate bootConfig, bootResidency bootConfig) of
    (AppleSilicon, Host) ->
      [ SomeSubscriptionRoute InferenceDomain InferenceHostCommandRoute "jitml-host" InferenceDaemonCommand
      , SomeSubscriptionRoute TrainingDomain TrainingHostCommandRoute "jitml-host" TrainingDaemonCommand
      , SomeSubscriptionRoute TuneDomain TuneHostCommandRoute "jitml-host" TuneDaemonCommand
      , SomeSubscriptionRoute RlDomain RlHostCommandRoute "jitml-host" RlDaemonCommand
      ]
    (AppleSilicon, Cluster) -> []
    (_, Cluster) ->
      [ SomeSubscriptionRoute InferenceDomain InferenceRequestRoute "jitml-engine" InferenceDaemonCommand
      ]
    (_, Host) -> []

-- | Coordinator owns cluster orchestration. On Linux it consumes the three
-- placement domains while the Engine retains inference. On Apple the
-- Coordinator additionally bridges inference to the host Engine.
coordinatorSubscriptionRoutes :: BootConfig -> [SomeSubscriptionRoute]
coordinatorSubscriptionRoutes bootConfig =
  case (bootSubstrate bootConfig, bootResidency bootConfig) of
    (AppleSilicon, Cluster) ->
      placementRoutes
        <> [ SomeSubscriptionRoute
               InferenceDomain
               InferenceRequestRoute
               "jitml-coordinator"
               InferenceDaemonCommand
           ]
    (_, Cluster) -> placementRoutes
    (_, Host) -> []
 where
  placementRoutes =
    [ SomeSubscriptionRoute TrainingDomain TrainingCommandRoute "jitml-coordinator" TrainingDaemonCommand
    , SomeSubscriptionRoute TuneDomain TuneCommandRoute "jitml-coordinator" TuneDaemonCommand
    , SomeSubscriptionRoute RlDomain RlCommandRoute "jitml-coordinator" RlDaemonCommand
    ]

firstPlanError :: Either TopicError value -> Either DaemonSubscriptionPlanError value
firstPlanError = mapLeft DaemonSubscriptionTopicError

firstSubscriptionError
  :: Either SubscriptionError value
  -> Either DaemonSubscriptionPlanError value
firstSubscriptionError =
  mapLeft DaemonSubscriptionValidationError

data DedupCache = DedupCache
  { dedupCacheEntries :: [(EventId, Int)]
  , dedupCacheLimit :: Int
  , dedupCacheTtlSeconds :: Int
  }
  deriving stock (Eq, Show)

emptyDedupCache :: Int -> DedupCache
emptyDedupCache limit = emptyDedupCacheWithTtl limit maxBound

emptyDedupCacheWithTtl :: Int -> Int -> DedupCache
emptyDedupCacheWithTtl limit ttlSeconds =
  DedupCache
    { dedupCacheEntries = []
    , dedupCacheLimit = max 0 limit
    , dedupCacheTtlSeconds = max 0 ttlSeconds
    }

dedupCacheCapacity :: DedupCache -> Int
dedupCacheCapacity = dedupCacheLimit

dedupCacheKnown :: EventId -> DedupCache -> Bool
dedupCacheKnown eventId cache =
  eventId `elem` fmap fst (dedupCacheEntries cache)

dedupCacheKnownAt :: Int -> EventId -> DedupCache -> Bool
dedupCacheKnownAt nowSeconds eventId cache =
  dedupCacheKnown eventId (dedupCacheExpireAt nowSeconds cache)

dedupCacheInsert :: EventId -> DedupCache -> DedupCache
dedupCacheInsert eventId cache
  | dedupCacheKnown eventId cache = cache
  | dedupCacheLimit cache <= 0 = cache {dedupCacheEntries = []}
  | otherwise =
      cache
        { dedupCacheEntries =
            take (dedupCacheLimit cache) ((eventId, 0) : dedupCacheEntries cache)
        }

dedupCacheInsertAt :: Int -> EventId -> DedupCache -> DedupCache
dedupCacheInsertAt nowSeconds eventId cache
  | dedupCacheKnown eventId freshCache = freshCache
  | dedupCacheLimit freshCache <= 0 = freshCache {dedupCacheEntries = []}
  | otherwise =
      freshCache
        { dedupCacheEntries =
            take
              (dedupCacheLimit freshCache)
              ((eventId, nowSeconds) : dedupCacheEntries freshCache)
        }
 where
  freshCache = dedupCacheExpireAt nowSeconds cache

dedupCacheExpireAt :: Int -> DedupCache -> DedupCache
dedupCacheExpireAt nowSeconds cache =
  cache
    { dedupCacheEntries =
        filter (entryIsLive nowSeconds (dedupCacheTtlSeconds cache)) (dedupCacheEntries cache)
    }

entryIsLive :: Int -> Int -> (EventId, Int) -> Bool
entryIsLive _nowSeconds ttlSeconds _entry
  | ttlSeconds <= 0 = False
entryIsLive nowSeconds ttlSeconds (_eventId, insertedAtSeconds) =
  nowSeconds - insertedAtSeconds < ttlSeconds

data HandlerRouter = HandlerRouter
  { trainingCache :: DedupCache
  , tuneCache :: DedupCache
  , rlCache :: DedupCache
  , inferenceCache :: DedupCache
  }
  deriving stock (Eq, Show)

routeByKind :: HandlerRouter -> EventDomain -> EventId -> (HandlerRouter, Bool)
routeByKind =
  routeByKindWith
    dedupCacheKnown
    dedupCacheInsert

routeByKindAt :: Int -> HandlerRouter -> EventDomain -> EventId -> (HandlerRouter, Bool)
routeByKindAt nowSeconds router =
  routeByKindWith
    (dedupCacheKnownAt nowSeconds)
    (dedupCacheInsertAt nowSeconds)
    (expireRouterAt nowSeconds router)

routeByKindWith
  :: (EventId -> DedupCache -> Bool)
  -> (EventId -> DedupCache -> DedupCache)
  -> HandlerRouter
  -> EventDomain
  -> EventId
  -> (HandlerRouter, Bool)
routeByKindWith known insert router domain eventId =
  case domain of
    TrainingDomain -> route trainingCache (\cache -> router {trainingCache = cache})
    TuneDomain -> route tuneCache (\cache -> router {tuneCache = cache})
    RlDomain -> route rlCache (\cache -> router {rlCache = cache})
    InferenceDomain -> route inferenceCache (\cache -> router {inferenceCache = cache})
 where
  route select replace =
    let cache = select router
     in if known eventId cache
          then (router, False)
          else (replace (insert eventId cache), True)

emptyHandlerRouter :: Int -> HandlerRouter
emptyHandlerRouter limit = emptyHandlerRouterWithTtl limit maxBound

emptyHandlerRouterWithTtl :: Int -> Int -> HandlerRouter
emptyHandlerRouterWithTtl limit ttlSeconds =
  HandlerRouter
    { trainingCache = emptyDedupCacheWithTtl limit ttlSeconds
    , tuneCache = emptyDedupCacheWithTtl limit ttlSeconds
    , rlCache = emptyDedupCacheWithTtl limit ttlSeconds
    , inferenceCache = emptyDedupCacheWithTtl limit ttlSeconds
    }

expireRouterAt :: Int -> HandlerRouter -> HandlerRouter
expireRouterAt nowSeconds router =
  HandlerRouter
    { trainingCache = dedupCacheExpireAt nowSeconds (trainingCache router)
    , tuneCache = dedupCacheExpireAt nowSeconds (tuneCache router)
    , rlCache = dedupCacheExpireAt nowSeconds (rlCache router)
    , inferenceCache = dedupCacheExpireAt nowSeconds (inferenceCache router)
    }

-- | Apply hot-reloaded cache bounds without discarding semantic ids that are
-- still live under the new TTL. Entries are newest-first, so shrinking the
-- capacity retains the newest valid ids and preserves at-least-once dedup
-- evidence up to the newly configured bound.
reconfigureHandlerRouter :: Int -> Int -> HandlerRouter -> IO HandlerRouter
reconfigureHandlerRouter limit ttlSeconds router = do
  nowSeconds <- currentEpochSeconds
  pure (reconfigureHandlerRouterAt nowSeconds limit ttlSeconds router)

reconfigureHandlerRouterAt :: Int -> Int -> Int -> HandlerRouter -> HandlerRouter
reconfigureHandlerRouterAt nowSeconds limit ttlSeconds router =
  HandlerRouter
    { trainingCache = reconfigureCache (trainingCache router)
    , tuneCache = reconfigureCache (tuneCache router)
    , rlCache = reconfigureCache (rlCache router)
    , inferenceCache = reconfigureCache (inferenceCache router)
    }
 where
  boundedLimit = max 0 limit
  boundedTtlSeconds = max 0 ttlSeconds
  reconfigureCache cache =
    let configured =
          cache
            { dedupCacheLimit = boundedLimit
            , dedupCacheTtlSeconds = boundedTtlSeconds
            }
        liveEntries = dedupCacheEntries (dedupCacheExpireAt nowSeconds configured)
     in configured {dedupCacheEntries = take boundedLimit liveEntries}

data ConsumerOutcome
  = ConsumerDispatched EventDomain EventId
  | ConsumerDeduplicated EventDomain EventId
  | ConsumerError ServiceError
  | ConsumerSessionError ConsumerFailure
  deriving stock (Eq, Show)

-- | Handle one already-decoded delivery.  Dispatch failure leaves the semantic
-- dedup cache untouched and requests a negative acknowledgement.  Successful
-- dispatch inserts the semantic id before returning 'ack'; the persistent
-- interpreter then settles that exact delivery receipt and confirms settlement
-- before requesting another permit.
consumerStep
  :: (MonadIO m)
  => HandlerRouter
  -> DaemonCommand
  -> (DaemonCommand -> EventId -> m (Either ServiceError ()))
  -> m (HandlerRouter, ConsumerOutcome, Disposition)
consumerStep router command dispatch = do
  nowSeconds <- liftIO currentEpochSeconds
  consumerStepAt nowSeconds router command dispatch

-- | Commit one semantic dedup transition independently of surrounding batch
-- work. If a later command is cancelled, 'modifyMVar' restores only that
-- command's input state; earlier successful commands remain visible to a
-- redelivery and cannot replay their external effects.
consumerStepCommitted
  :: MVar HandlerRouter
  -> DaemonCommand
  -> (DaemonCommand -> EventId -> IO (Either ServiceError ()))
  -> IO (ConsumerOutcome, Disposition)
consumerStepCommitted routerRef command dispatch =
  modifyMVar routerRef $ \router -> do
    (router', outcome, disposition) <- consumerStep router command dispatch
    pure (router', (outcome, disposition))

consumerStepAt
  :: (Monad m)
  => Int
  -> HandlerRouter
  -> DaemonCommand
  -> (DaemonCommand -> EventId -> m (Either ServiceError ()))
  -> m (HandlerRouter, ConsumerOutcome, Disposition)
consumerStepAt nowSeconds router command dispatch = do
  let domain = daemonCommandDomain command
      freshRouter = expireRouterAt nowSeconds router
  case daemonCommandEventId command of
    Failure planErrors ->
      let err =
            SEConflict
              ( "invalid semantic event identity: "
                  <> Text.intercalate "; " (fmap (Text.pack . show) (NonEmpty.toList planErrors))
              )
       in pure
            ( freshRouter
            , ConsumerError err
            , nack (HandlerRejected (renderServiceError err))
            )
    Success eventId ->
      if eventKnownForDomain domain eventId freshRouter
        then pure (freshRouter, ConsumerDeduplicated domain eventId, ack)
        else do
          dispatchResult <- dispatch command eventId
          case dispatchResult of
            Left err ->
              pure
                ( freshRouter
                , ConsumerError err
                , nack (HandlerRejected (renderServiceError err))
                )
            Right () ->
              let (routerAfterInsert, _wasFresh) =
                    routeByKindAt nowSeconds freshRouter domain eventId
               in pure
                    ( routerAfterInsert
                    , ConsumerDispatched domain eventId
                    , ack
                    )

eventKnownForDomain :: EventDomain -> EventId -> HandlerRouter -> Bool
eventKnownForDomain domain eventId router =
  dedupCacheKnown eventId $
    case domain of
      TrainingDomain -> trainingCache router
      TuneDomain -> tuneCache router
      RlDomain -> rlCache router
      InferenceDomain -> inferenceCache router

consumerOutcomeError :: ConsumerOutcome -> Maybe AppError
consumerOutcomeError outcome =
  case outcome of
    ConsumerError serviceErr -> Just (serviceErrorToAppError serviceErr)
    ConsumerSessionError (ConsumerTransportFailure failure) -> Just (SubprocessFailed failure)
    ConsumerSessionError (ConsumerTransportContextFailure _context failure) ->
      Just (SubprocessFailed failure)
    ConsumerSessionError (ConsumerPipedActionFailure _context (ProcessFailed failure)) ->
      Just (SubprocessFailed failure)
    ConsumerSessionError (ConsumerCleanupContextFailure primaryFailure _cleanupError) ->
      consumerOutcomeError (ConsumerSessionError primaryFailure)
    ConsumerSessionError failure -> Just (PulsarFailed (Text.pack (show failure)))
    _ -> Nothing

-- | Bounded adapter used by @--consume-once@ and lifecycle tests.  The same
-- persistent session handles every delivery; @Done@ settles the final receipt,
-- requests drain, waits for @drained@, and only then returns.
runConsumerLoop
  :: (HasPulsar m, MonadIO m)
  => DaemonSubscription
  -> HandlerRouter
  -> Int
  -> (ConsumerSessionEvent -> m ())
  -> (DaemonCommand -> EventId -> m (Either ServiceError ()))
  -> m (Either ConsumerFailure (HandlerRouter, [ConsumerOutcome]))
runConsumerLoop _subscription router0 budget _observe _dispatch
  | budget <= 0 = pure (Right (router0, []))
runConsumerLoop subscription router0 budget observe dispatch = do
  routerRef <- liftIO (newIORef router0)
  outcomesRef <- liftIO (newIORef [])
  remainingRef <- liftIO (newIORef budget)
  result <-
    consumeDaemonSubscription subscription observe $ \command -> do
      router <- liftIO (readIORef routerRef)
      (router', outcome, disposition) <-
        consumerStep router command dispatch
      liftIO $ do
        writeIORef routerRef router'
        modifyIORef' outcomesRef (outcome :)
      remaining <-
        liftIO $
          atomicModifyIORef' remainingRef $ \remaining ->
            let next = max 0 (remaining - 1)
             in (next, next)
      pure $
        if remaining == 0
          then done disposition ()
          else continue disposition
  case result of
    Left failure -> pure (Left failure)
    Right () -> do
      router <- liftIO (readIORef routerRef)
      outcomes <- reverse <$> liftIO (readIORef outcomesRef)
      pure (Right (router, outcomes))

currentEpochSeconds :: IO Int
currentEpochSeconds = do
  now <- epochTime
  pure (floor (realToFrac now :: Double))

renderServiceError :: ServiceError -> Text
renderServiceError err =
  case err of
    SEConflict message -> "conflict: " <> message
    SEUnauthorized message -> "unauthorized: " <> message
    SETimeout message -> "timeout: " <> message
    SETransient message -> "transient: " <> message
    SENotFound message -> "not-found: " <> message
