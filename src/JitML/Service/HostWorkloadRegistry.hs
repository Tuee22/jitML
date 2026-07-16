{-# LANGUAGE OverloadedStrings #-}

-- | Process-local ownership of host-resident Apple workloads.
--
-- A host workload is admitted under a refined @(family, experiment hash)@ key.
-- The worker cannot begin before its 'Async' handle is registered, and a key is
-- never reusable: completion leaves a terminal tombstone containing the real
-- outcome. Stop is deliberately split into an exact-once claim followed by
-- either cancel-and-join or natural-completion-and-join. Production callers
-- should normally use 'stopHostWorkload' or 'drainHostWorkload'; the split API
-- makes completion races explicit and ensures that only 'JoinedHostWorkload'
-- represents an observed stop.
module JitML.Service.HostWorkloadRegistry
  ( HostWorkloadFamily (..)
  , hostWorkloadFamilyLabel
  , HostWorkloadKey
  , hostWorkloadExperimentHash
  , hostWorkloadFamily
  , refineHostWorkloadKey
  , HostWorkloadOutcome (..)
  , HostWorkloadSnapshot (..)
  , HostWorkloadRegistryError (..)
  , renderHostWorkloadRegistryError
  , HostWorkloadRegistry
  , newHostWorkloadRegistry
  , RegisteredHostWorkload
  , registeredHostWorkloadKey
  , startHostWorkload
  , PendingHostWorkloadStop
  , beginHostWorkloadStop
  , JoinedHostWorkload
  , joinedHostWorkloadKey
  , joinedHostWorkloadOutcome
  , completeHostWorkloadStop
  , completeHostWorkloadDrain
  , stopHostWorkload
  , stopHostWorkloadForEvent
  , drainHostWorkload
  , drainHostWorkloadForEvent
  , lookupHostWorkload
  , waitHostWorkload
  , hostWorkloadRegistrySnapshots
  , activeHostWorkloadCount
  , HostWorkloadDrainReport (..)
  , drainHostWorkloadRegistry
  )
where

import Control.Concurrent.Async
  ( Async
  , AsyncCancelled
  , asyncWithUnmask
  , cancel
  , mapConcurrently
  , waitCatch
  )
import Control.Concurrent.STM
  ( STM
  , TVar
  , atomically
  , modifyTVar'
  , newEmptyTMVarIO
  , newTVarIO
  , putTMVar
  , readTVar
  , retry
  , takeTMVar
  , writeTVar
  )
import Control.Exception
  ( SomeException
  , displayException
  , fromException
  , mask
  , try
  )
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Numeric.Natural (Natural)
import System.Timeout qualified as Timeout

import JitML.Plan.Plan (EventId)

data HostWorkloadFamily
  = TrainingWorkload
  | TuneWorkload
  | RlWorkload
  deriving stock (Eq, Ord, Show)

hostWorkloadFamilyLabel :: HostWorkloadFamily -> Text
hostWorkloadFamilyLabel family =
  case family of
    TrainingWorkload -> "training"
    TuneWorkload -> "tune"
    RlWorkload -> "rl"

-- | A non-empty, whitespace-canonical experiment identity in a closed
-- workload family.  The constructor is private so registry operations cannot
-- accidentally alias malformed wire values.
data HostWorkloadKey = HostWorkloadKey
  { hostWorkloadFamily :: HostWorkloadFamily
  , hostWorkloadExperimentHash :: Text
  }
  deriving stock (Eq, Ord, Show)

refineHostWorkloadKey
  :: HostWorkloadFamily
  -> Text
  -> Either HostWorkloadRegistryError HostWorkloadKey
refineHostWorkloadKey family experimentHash
  | Text.null experimentHash =
      Left (InvalidHostWorkloadExperimentHash family experimentHash)
  | Text.strip experimentHash /= experimentHash =
      Left (InvalidHostWorkloadExperimentHash family experimentHash)
  | otherwise =
      Right
        HostWorkloadKey
          { hostWorkloadFamily = family
          , hostWorkloadExperimentHash = experimentHash
          }

data HostWorkloadOutcome
  = HostWorkloadSucceeded
  | HostWorkloadCancelled
  | HostWorkloadFailed Text
  deriving stock (Eq, Show)

data HostWorkloadSnapshot
  = HostWorkloadRunning
  | HostWorkloadStopping
  | HostWorkloadTerminal HostWorkloadOutcome
  deriving stock (Eq, Show)

data HostWorkloadRegistryError
  = InvalidHostWorkloadExperimentHash HostWorkloadFamily Text
  | DuplicateHostWorkloadStart HostWorkloadKey
  | HostWorkloadRegistryNotAcceptingStarts HostWorkloadKey
  | UnknownHostWorkload HostWorkloadKey
  | HostWorkloadStopAlreadyRequested HostWorkloadKey
  | HostWorkloadAlreadyTerminal HostWorkloadKey HostWorkloadOutcome
  | HostWorkloadCancellationLostRace HostWorkloadKey HostWorkloadOutcome
  | HostWorkloadDrainDidNotSucceed HostWorkloadKey HostWorkloadOutcome
  | HostWorkloadJoinFailed HostWorkloadKey Text
  | HostWorkloadDrainDeadlineMustBePositive
  | HostWorkloadDrainTimedOut [HostWorkloadKey]
  | HostWorkloadDrainIncomplete [HostWorkloadKey]
  deriving stock (Eq, Show)

renderHostWorkloadRegistryError :: HostWorkloadRegistryError -> Text
renderHostWorkloadRegistryError registryError =
  case registryError of
    InvalidHostWorkloadExperimentHash family experimentHash ->
      "invalid "
        <> hostWorkloadFamilyLabel family
        <> " host workload experiment hash: "
        <> Text.pack (show experimentHash)
    DuplicateHostWorkloadStart key ->
      "duplicate host workload Start for " <> renderHostWorkloadKey key
    HostWorkloadRegistryNotAcceptingStarts key ->
      "host workload registry is draining; Start rejected for "
        <> renderHostWorkloadKey key
    UnknownHostWorkload key ->
      "no host workload is registered for " <> renderHostWorkloadKey key
    HostWorkloadStopAlreadyRequested key ->
      "host workload Stop was already requested for " <> renderHostWorkloadKey key
    HostWorkloadAlreadyTerminal key outcome ->
      "host workload is already terminal for "
        <> renderHostWorkloadKey key
        <> ": "
        <> renderHostWorkloadOutcome outcome
    HostWorkloadCancellationLostRace key outcome ->
      "host workload cancellation lost the completion race for "
        <> renderHostWorkloadKey key
        <> ": "
        <> renderHostWorkloadOutcome outcome
    HostWorkloadDrainDidNotSucceed key outcome ->
      "host workload did not succeed while draining "
        <> renderHostWorkloadKey key
        <> ": "
        <> renderHostWorkloadOutcome outcome
    HostWorkloadJoinFailed key failure ->
      "host workload handle failed while joining "
        <> renderHostWorkloadKey key
        <> ": "
        <> failure
    HostWorkloadDrainDeadlineMustBePositive ->
      "host workload drain deadline must be positive"
    HostWorkloadDrainTimedOut keys ->
      "host workload drain timed out with active handles: "
        <> renderHostWorkloadKeys keys
    HostWorkloadDrainIncomplete keys ->
      "host workload drain returned before handles became terminal: "
        <> renderHostWorkloadKeys keys

newtype HostWorkloadRegistry = HostWorkloadRegistry
  { registryState :: TVar RegistryState
  }

data RegistryState = RegistryState
  { registryAdmission :: RegistryAdmission
  , registryNextGeneration :: Natural
  , registryEntries :: Map HostWorkloadKey RegistryEntry
  , registryStopReceipts :: Map HostWorkloadKey HostWorkloadStopReceipt
  }

data RegistryAdmission
  = RegistryOpen
  | RegistryDraining
  | RegistryDrained

data RegistryEntry
  = RegistryRunning WorkloadHandle
  | RegistryStopping WorkloadHandle
  | RegistryTerminal Natural HostWorkloadOutcome

data WorkloadHandle = WorkloadHandle
  { workloadGeneration :: Natural
  , workloadAsync :: Async ()
  }

newtype RegisteredHostWorkload = RegisteredHostWorkload
  { registeredHostWorkloadKey :: HostWorkloadKey
  }
  deriving stock (Eq, Show)

data PendingHostWorkloadStop = PendingHostWorkloadStop
  { pendingStopRegistry :: HostWorkloadRegistry
  , pendingStopKey :: HostWorkloadKey
  , pendingStopHandle :: WorkloadHandle
  , pendingStopReceiptIdentity :: Maybe (EventId, HostWorkloadStopKind)
  }

data JoinedHostWorkload = JoinedHostWorkload
  { joinedHostWorkloadKey :: HostWorkloadKey
  , joinedHostWorkloadOutcome :: HostWorkloadOutcome
  }
  deriving stock (Eq, Show)

newtype HostWorkloadDrainReport = HostWorkloadDrainReport
  { drainedHostWorkloads :: [(HostWorkloadKey, HostWorkloadOutcome)]
  }
  deriving stock (Eq, Show)

data DrainHandle = DrainHandle HostWorkloadKey WorkloadHandle

data HostWorkloadStopKind
  = CancelHostWorkloadStop
  | DrainHostWorkloadStop
  deriving stock (Eq, Show)

data HostWorkloadStopReceipt = HostWorkloadStopReceipt
  { stopReceiptEventId :: EventId
  , stopReceiptKind :: HostWorkloadStopKind
  , stopReceiptJoinedWorkload :: JoinedHostWorkload
  }

data HostWorkloadStopAdmission
  = AdmitNewHostWorkloadStop PendingHostWorkloadStop
  | ReplayJoinedHostWorkloadStop JoinedHostWorkload

newHostWorkloadRegistry :: IO HostWorkloadRegistry
newHostWorkloadRegistry =
  HostWorkloadRegistry
    <$> newTVarIO
      RegistryState
        { registryAdmission = RegistryOpen
        , registryNextGeneration = 0
        , registryEntries = Map.empty
        , registryStopReceipts = Map.empty
        }

-- | Register a masked worker and only then release its start gate.  Returning a
-- receipt therefore proves that the handle was visible to Stop/drain before
-- user code could execute.
startHostWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> IO ()
  -> IO (Either HostWorkloadRegistryError RegisteredHostWorkload)
startHostWorkload registry key workload =
  mask $ \_restoreCaller -> do
    generation <- atomically (allocateGeneration registry)
    startGate <- newEmptyTMVarIO
    worker <-
      asyncWithUnmask $ \unmask -> do
        workloadResult <-
          try @SomeException $ unmask $ do
            atomically (takeTMVar startGate)
            workload
        atomically
          ( completeRegisteredWorkload
              registry
              key
              generation
              (workloadOutcome workloadResult)
          )
    let handle =
          WorkloadHandle
            { workloadGeneration = generation
            , workloadAsync = worker
            }
    admission <- atomically (admitWorkload registry key handle)
    case admission of
      Left registryError -> do
        cancel worker
        _ <- waitCatch worker
        pure (Left registryError)
      Right () -> do
        atomically (putTMVar startGate ())
        pure (Right (RegisteredHostWorkload key))

-- | Claim the sole Stop transition.  The returned value is intentionally not
-- a success receipt: cancellation has not yet been observed or joined.
beginHostWorkloadStop
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> IO (Either HostWorkloadRegistryError PendingHostWorkloadStop)
beginHostWorkloadStop registry key =
  atomically $ do
    admission <- beginHostWorkloadStopAdmission registry key Nothing
    pure $
      case admission of
        Left registryError -> Left registryError
        Right (AdmitNewHostWorkloadStop pending) -> Right pending
        Right (ReplayJoinedHostWorkloadStop _joined) ->
          Left (HostWorkloadStopAlreadyRequested key)

-- | Deliver cancellation and join the exact handle claimed by
-- 'beginHostWorkloadStop'.  A successful value is only constructed when the
-- joined worker's terminal tombstone is 'HostWorkloadCancelled'.
completeHostWorkloadStop
  :: PendingHostWorkloadStop
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
completeHostWorkloadStop pending =
  mask $ \_restoreCaller -> do
    let key = pendingStopKey pending
        handle = pendingStopHandle pending
    cancel (workloadAsync handle)
    joinedWait <- waitCatch (workloadAsync handle)
    result <-
      case joinedWait of
        Left exception ->
          pure
            ( Left
                (HostWorkloadJoinFailed key (Text.pack (displayException exception)))
            )
        Right () -> do
          terminal <-
            atomically
              ( terminalOutcomeForGeneration
                  (pendingStopRegistry pending)
                  key
                  (workloadGeneration handle)
              )
          pure $ case terminal of
            Left registryError -> Left registryError
            Right HostWorkloadCancelled ->
              Right
                JoinedHostWorkload
                  { joinedHostWorkloadKey = key
                  , joinedHostWorkloadOutcome = HostWorkloadCancelled
                  }
            Right outcome ->
              Left (HostWorkloadCancellationLostRace key outcome)
    case result of
      Right joinedReceipt -> do
        recordHostWorkloadStopReceipt pending CancelHostWorkloadStop joinedReceipt
        pure (Right joinedReceipt)
      Left registryError -> pure (Left registryError)

-- | Join the exact handle claimed by 'beginHostWorkloadStop' without
-- delivering cancellation. A successful value proves the worker reached its
-- natural successful tombstone; failures and external cancellation fail
-- closed while retaining their exact terminal outcome.
completeHostWorkloadDrain
  :: PendingHostWorkloadStop
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
completeHostWorkloadDrain pending =
  mask $ \_restoreCaller -> do
    let key = pendingStopKey pending
        handle = pendingStopHandle pending
    joinedWait <- waitCatch (workloadAsync handle)
    case joinedWait of
      Left exception ->
        pure
          ( Left
              (HostWorkloadJoinFailed key (Text.pack (displayException exception)))
          )
      Right () -> do
        terminal <-
          atomically
            ( terminalOutcomeForGeneration
                (pendingStopRegistry pending)
                key
                (workloadGeneration handle)
            )
        let result =
              case terminal of
                Left registryError -> Left registryError
                Right HostWorkloadSucceeded ->
                  Right
                    JoinedHostWorkload
                      { joinedHostWorkloadKey = key
                      , joinedHostWorkloadOutcome = HostWorkloadSucceeded
                      }
                Right outcome ->
                  Left (HostWorkloadDrainDidNotSucceed key outcome)
        case result of
          Right joinedReceipt -> do
            recordHostWorkloadStopReceipt pending DrainHostWorkloadStop joinedReceipt
            pure (Right joinedReceipt)
          Left registryError -> pure (Left registryError)

stopHostWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
stopHostWorkload registry key =
  mask $ \_restoreCaller -> do
    pending <- beginHostWorkloadStop registry key
    case pending of
      Left registryError -> pure (Left registryError)
      Right claimed -> completeHostWorkloadStop claimed

-- | Event-bound cancellation used at the daemon acknowledgement boundary.
-- Once the exact event has joined successfully, a redelivery receives the same
-- receipt so it can retry required terminal publication. A different event for
-- the terminal key still fails closed as 'HostWorkloadAlreadyTerminal'.
stopHostWorkloadForEvent
  :: HostWorkloadRegistry
  -> EventId
  -> HostWorkloadKey
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
stopHostWorkloadForEvent registry eventId key =
  completeEventBoundHostWorkloadStop
    registry
    eventId
    CancelHostWorkloadStop
    key
    completeHostWorkloadStop

drainHostWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
drainHostWorkload registry key =
  mask $ \_restoreCaller -> do
    pending <- beginHostWorkloadStop registry key
    case pending of
      Left registryError -> pure (Left registryError)
      Right claimed -> completeHostWorkloadDrain claimed

-- | Event-bound natural drain counterpart of 'stopHostWorkloadForEvent'.
drainHostWorkloadForEvent
  :: HostWorkloadRegistry
  -> EventId
  -> HostWorkloadKey
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
drainHostWorkloadForEvent registry eventId key =
  completeEventBoundHostWorkloadStop
    registry
    eventId
    DrainHostWorkloadStop
    key
    completeHostWorkloadDrain

completeEventBoundHostWorkloadStop
  :: HostWorkloadRegistry
  -> EventId
  -> HostWorkloadStopKind
  -> HostWorkloadKey
  -> ( PendingHostWorkloadStop
       -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
     )
  -> IO (Either HostWorkloadRegistryError JoinedHostWorkload)
completeEventBoundHostWorkloadStop registry eventId stopKind key complete =
  mask $ \_restoreCaller -> do
    admission <-
      atomically
        ( beginHostWorkloadStopAdmission
            registry
            key
            (Just (eventId, stopKind))
        )
    case admission of
      Left registryError -> pure (Left registryError)
      Right (ReplayJoinedHostWorkloadStop joined) -> pure (Right joined)
      Right (AdmitNewHostWorkloadStop pending) -> complete pending

beginHostWorkloadStopAdmission
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> Maybe (EventId, HostWorkloadStopKind)
  -> STM (Either HostWorkloadRegistryError HostWorkloadStopAdmission)
beginHostWorkloadStopAdmission registry key receiptIdentity = do
  state <- readTVar (registryState registry)
  case Map.lookup key (registryEntries state) of
    Nothing -> pure (Left (UnknownHostWorkload key))
    Just (RegistryRunning handle) -> do
      writeTVar
        (registryState registry)
        state
          { registryEntries =
              Map.insert key (RegistryStopping handle) (registryEntries state)
          }
      pure
        ( Right
            ( AdmitNewHostWorkloadStop
                PendingHostWorkloadStop
                  { pendingStopRegistry = registry
                  , pendingStopKey = key
                  , pendingStopHandle = handle
                  , pendingStopReceiptIdentity = receiptIdentity
                  }
            )
        )
    Just (RegistryStopping _handle) ->
      pure (Left (HostWorkloadStopAlreadyRequested key))
    Just (RegistryTerminal _generation outcome) ->
      pure $
        case receiptIdentity >>= matchingStopReceipt state key outcome of
          Just receipt ->
            Right
              (ReplayJoinedHostWorkloadStop (stopReceiptJoinedWorkload receipt))
          Nothing -> Left (HostWorkloadAlreadyTerminal key outcome)

matchingStopReceipt
  :: RegistryState
  -> HostWorkloadKey
  -> HostWorkloadOutcome
  -> (EventId, HostWorkloadStopKind)
  -> Maybe HostWorkloadStopReceipt
matchingStopReceipt state key observedOutcome (eventId, stopKind) = do
  receipt <- Map.lookup key (registryStopReceipts state)
  if stopReceiptEventId receipt == eventId
    && stopReceiptKind receipt == stopKind
    && joinedHostWorkloadOutcome (stopReceiptJoinedWorkload receipt) == observedOutcome
    then Just receipt
    else Nothing

recordHostWorkloadStopReceipt
  :: PendingHostWorkloadStop
  -> HostWorkloadStopKind
  -> JoinedHostWorkload
  -> IO ()
recordHostWorkloadStopReceipt pending completedKind joined =
  case pendingStopReceiptIdentity pending of
    Just (eventId, admittedKind)
      | admittedKind == completedKind ->
          atomically
            ( modifyTVar'
                (registryState (pendingStopRegistry pending))
                ( \state ->
                    state
                      { registryStopReceipts =
                          Map.insert
                            (pendingStopKey pending)
                            HostWorkloadStopReceipt
                              { stopReceiptEventId = eventId
                              , stopReceiptKind = completedKind
                              , stopReceiptJoinedWorkload = joined
                              }
                            (registryStopReceipts state)
                      }
                )
            )
    _ -> pure ()

lookupHostWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> IO (Maybe HostWorkloadSnapshot)
lookupHostWorkload registry key =
  atomically $ do
    state <- readTVar (registryState registry)
    pure (entrySnapshot <$> Map.lookup key (registryEntries state))

waitHostWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> IO (Either HostWorkloadRegistryError HostWorkloadOutcome)
waitHostWorkload registry key =
  atomically $ do
    state <- readTVar (registryState registry)
    case Map.lookup key (registryEntries state) of
      Nothing -> pure (Left (UnknownHostWorkload key))
      Just (RegistryTerminal _generation outcome) -> pure (Right outcome)
      Just RegistryRunning {} -> retry
      Just RegistryStopping {} -> retry

hostWorkloadRegistrySnapshots
  :: HostWorkloadRegistry
  -> IO [(HostWorkloadKey, HostWorkloadSnapshot)]
hostWorkloadRegistrySnapshots registry =
  atomically $ do
    state <- readTVar (registryState registry)
    pure
      [ (key, entrySnapshot entry)
      | (key, entry) <- Map.toAscList (registryEntries state)
      ]

activeHostWorkloadCount :: HostWorkloadRegistry -> IO Int
activeHostWorkloadCount registry =
  atomically $ do
    state <- readTVar (registryState registry)
    pure (length (activeEntries (registryEntries state)))

-- | Stop admission, cancel every active worker concurrently, and join them
-- under one total deadline (microseconds).  A timed-out registry remains in
-- draining state and rejects all future starts; calling drain again safely
-- retries cancellation and joining for the retained handles.
drainHostWorkloadRegistry
  :: HostWorkloadRegistry
  -> Natural
  -> IO (Either HostWorkloadRegistryError HostWorkloadDrainReport)
drainHostWorkloadRegistry _registry 0 =
  pure (Left HostWorkloadDrainDeadlineMustBePositive)
drainHostWorkloadRegistry registry deadlineMicros =
  mask $ \_restoreCaller -> do
    handles <- atomically (beginRegistryDrain registry)
    drainResult <-
      Timeout.timeout
        (boundedMicroseconds deadlineMicros)
        (mapConcurrently drainHandle handles)
    case drainResult of
      Just joinResults ->
        case firstJoinFailure joinResults of
          Just registryError -> pure (Left registryError)
          Nothing -> finishRegistryDrain registry handles
      Nothing -> do
        activeKeys <- atomically (registryActiveKeys registry)
        if null activeKeys
          then finishRegistryDrain registry handles
          else pure (Left (HostWorkloadDrainTimedOut activeKeys))

allocateGeneration :: HostWorkloadRegistry -> STM Natural
allocateGeneration registry = do
  state <- readTVar (registryState registry)
  let generation = registryNextGeneration state
  writeTVar
    (registryState registry)
    state {registryNextGeneration = generation + 1}
  pure generation

admitWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> WorkloadHandle
  -> STM (Either HostWorkloadRegistryError ())
admitWorkload registry key handle = do
  state <- readTVar (registryState registry)
  case registryAdmission state of
    RegistryOpen ->
      if Map.member key (registryEntries state)
        then pure (Left (DuplicateHostWorkloadStart key))
        else do
          writeTVar
            (registryState registry)
            state
              { registryEntries =
                  Map.insert key (RegistryRunning handle) (registryEntries state)
              }
          pure (Right ())
    RegistryDraining ->
      pure (Left (HostWorkloadRegistryNotAcceptingStarts key))
    RegistryDrained ->
      pure (Left (HostWorkloadRegistryNotAcceptingStarts key))

completeRegisteredWorkload
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> Natural
  -> HostWorkloadOutcome
  -> STM ()
completeRegisteredWorkload registry key generation outcome =
  modifyTVar' (registryState registry) $ \state ->
    case Map.lookup key (registryEntries state) of
      Just (RegistryRunning handle)
        | workloadGeneration handle == generation ->
            terminalState state
      Just (RegistryStopping handle)
        | workloadGeneration handle == generation ->
            terminalState state
      _ -> state
 where
  terminalState state =
    state
      { registryEntries =
          Map.insert
            key
            (RegistryTerminal generation outcome)
            (registryEntries state)
      }

terminalOutcomeForGeneration
  :: HostWorkloadRegistry
  -> HostWorkloadKey
  -> Natural
  -> STM (Either HostWorkloadRegistryError HostWorkloadOutcome)
terminalOutcomeForGeneration registry key generation = do
  state <- readTVar (registryState registry)
  pure $ case Map.lookup key (registryEntries state) of
    Nothing -> Left (UnknownHostWorkload key)
    Just (RegistryTerminal terminalGeneration outcome)
      | terminalGeneration == generation -> Right outcome
    Just _entry -> Left (HostWorkloadDrainIncomplete [key])

beginRegistryDrain :: HostWorkloadRegistry -> STM [DrainHandle]
beginRegistryDrain registry = do
  state <- readTVar (registryState registry)
  let entries = registryEntries state
      stoppingEntries = fmap markStopping entries
      admission =
        if null (activeEntries entries)
          then RegistryDrained
          else RegistryDraining
  writeTVar
    (registryState registry)
    state
      { registryAdmission = admission
      , registryEntries = stoppingEntries
      }
  pure
    [ DrainHandle key handle
    | (key, handle) <- activeEntries entries
    ]
 where
  markStopping entry =
    case entry of
      RegistryRunning handle -> RegistryStopping handle
      RegistryStopping handle -> RegistryStopping handle
      RegistryTerminal generation outcome -> RegistryTerminal generation outcome

drainHandle
  :: DrainHandle
  -> IO (HostWorkloadKey, Either SomeException ())
drainHandle (DrainHandle key handle) = do
  cancel (workloadAsync handle)
  joined <- waitCatch (workloadAsync handle)
  pure (key, joined)

finishRegistryDrain
  :: HostWorkloadRegistry
  -> [DrainHandle]
  -> IO (Either HostWorkloadRegistryError HostWorkloadDrainReport)
finishRegistryDrain registry handles =
  atomically $ do
    state <- readTVar (registryState registry)
    let activeKeys = fmap fst (activeEntries (registryEntries state))
    if null activeKeys
      then do
        writeTVar
          (registryState registry)
          state {registryAdmission = RegistryDrained}
        pure
          ( Right
              HostWorkloadDrainReport
                { drainedHostWorkloads =
                    [ (key, outcome)
                    | DrainHandle key handle <- handles
                    , Just outcome <-
                        [ terminalOutcome
                            (workloadGeneration handle)
                            =<< Map.lookup key (registryEntries state)
                        ]
                    ]
                }
          )
      else pure (Left (HostWorkloadDrainIncomplete activeKeys))

registryActiveKeys :: HostWorkloadRegistry -> STM [HostWorkloadKey]
registryActiveKeys registry = do
  state <- readTVar (registryState registry)
  pure (fmap fst (activeEntries (registryEntries state)))

activeEntries :: Map HostWorkloadKey RegistryEntry -> [(HostWorkloadKey, WorkloadHandle)]
activeEntries entries =
  [ (key, handle)
  | (key, entry) <- Map.toAscList entries
  , handle <- case entry of
      RegistryRunning running -> [running]
      RegistryStopping stopping -> [stopping]
      RegistryTerminal {} -> []
  ]

entrySnapshot :: RegistryEntry -> HostWorkloadSnapshot
entrySnapshot entry =
  case entry of
    RegistryRunning _handle -> HostWorkloadRunning
    RegistryStopping _handle -> HostWorkloadStopping
    RegistryTerminal _generation outcome -> HostWorkloadTerminal outcome

terminalOutcome :: Natural -> RegistryEntry -> Maybe HostWorkloadOutcome
terminalOutcome expectedGeneration entry =
  case entry of
    RegistryTerminal generation outcome
      | generation == expectedGeneration -> Just outcome
    _ -> Nothing

workloadOutcome :: Either SomeException () -> HostWorkloadOutcome
workloadOutcome workloadResult =
  case workloadResult of
    Right () -> HostWorkloadSucceeded
    Left exception ->
      case fromException exception :: Maybe AsyncCancelled of
        Just _cancelled -> HostWorkloadCancelled
        Nothing -> HostWorkloadFailed (Text.pack (displayException exception))

firstJoinFailure
  :: [(HostWorkloadKey, Either SomeException ())]
  -> Maybe HostWorkloadRegistryError
firstJoinFailure joinResults =
  case [ HostWorkloadJoinFailed key (Text.pack (displayException exception))
       | (key, Left exception) <- joinResults
       ] of
    [] -> Nothing
    registryError : _rest -> Just registryError

boundedMicroseconds :: Natural -> Int
boundedMicroseconds microseconds =
  fromInteger
    ( min
        (toInteger (maxBound :: Int))
        (toInteger microseconds)
    )

renderHostWorkloadKey :: HostWorkloadKey -> Text
renderHostWorkloadKey key =
  hostWorkloadFamilyLabel (hostWorkloadFamily key)
    <> "/"
    <> hostWorkloadExperimentHash key

renderHostWorkloadOutcome :: HostWorkloadOutcome -> Text
renderHostWorkloadOutcome outcome =
  case outcome of
    HostWorkloadSucceeded -> "succeeded"
    HostWorkloadCancelled -> "cancelled"
    HostWorkloadFailed failure -> "failed (" <> failure <> ")"

renderHostWorkloadKeys :: [HostWorkloadKey] -> Text
renderHostWorkloadKeys = Text.intercalate ", " . fmap renderHostWorkloadKey
