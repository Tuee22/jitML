{-# LANGUAGE OverloadedStrings #-}

-- | Closed daemon lifecycle state shared by startup, consumer sessions,
-- signal handling, and the live readiness endpoint.
--
-- Readiness is deliberately not stored as an independent Boolean.  A daemon
-- is ready only when the 'DaemonReady' constructor carries evidence that the
-- Metal prerequisite (when applicable), every planned persistent consumer,
-- and every client probe have completed.
module JitML.Service.RuntimeState
  ( DaemonState
  , StartupStage (..)
  , MetalEvidence (..)
  , TopicFamilyEvidence (..)
  , ConsumerConnectionEvidence (..)
  , ReadyEvidence
  , DegradedCause (..)
  , initialDaemonState
  , initialDaemonStateWithTopicFamily
  , daemonStateReady
  , daemonStateDraining
  , daemonStateLabel
  , daemonStateDetail
  , daemonReadyEvidence
  , readyConsumerConnections
  , recordMetalAcquired
  , recordMetalNotRequired
  , recordMetalFailure
  , recordTopicFamilyReconciled
  , recordTopicFamilyFailure
  , recordConsumerConnected
  , recordConsumerDisconnected
  , recordClientProbesSucceeded
  , recordClientProbeFailure
  , recordRuntimeFailure
  , beginDaemonDrain
  )
where

import Data.List (sort)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)

data StartupStage
  = AwaitingMetal
  | AwaitingTopicFamily
  | AwaitingConsumerConnections
  | AwaitingClientProbes
  deriving stock (Eq, Show)

data MetalEvidence
  = MetalNotRequired
  | MetalAcquired Text
  deriving stock (Eq, Show)

data TopicFamilyEvidence
  = TopicFamilyNotRequired
  | TopicFamilyReconciled [Text]
  deriving stock (Eq, Show)

data ConsumerConnectionEvidence = ConsumerConnectionEvidence
  { connectedConsumerTopic :: Text
  , connectedConsumerGeneration :: Word64
  }
  deriving stock (Eq, Show)

data StartupProgress = StartupProgress
  { progressMetalEvidence :: Maybe MetalEvidence
  , progressExpectedTopics :: [Text]
  , progressTopicFamilyEvidence :: Maybe TopicFamilyEvidence
  , progressExpectedConsumers :: [Text]
  , progressConnectedConsumers :: [ConsumerConnectionEvidence]
  , progressExpectedClientProbes :: [Text]
  , progressSucceededClientProbes :: [Text]
  }
  deriving stock (Eq, Show)

data StartingState = StartingState
  { startingStage :: StartupStage
  , startingProgress :: StartupProgress
  }
  deriving stock (Eq, Show)

data ReadyEvidence = ReadyEvidence
  { readyMetalEvidence :: MetalEvidence
  , readyTopicFamilyEvidence :: TopicFamilyEvidence
  , readyExpectedConsumers :: [Text]
  , readyConsumerConnections :: [ConsumerConnectionEvidence]
  , readyClientProbes :: [Text]
  }
  deriving stock (Eq, Show)

data DegradedCause
  = MetalPrerequisiteFailed Text
  | TopicFamilyReconcileFailed Text
  | ConsumerConnectionLost Text Text
  | ClientProbeFailed Text Text
  | RuntimeInvariantFailed Text
  | RuntimeTransportFailed Text
  deriving stock (Eq, Show)

data DegradedEvidence = DegradedEvidence
  { degradedProgress :: StartupProgress
  , degradedCause :: DegradedCause
  }
  deriving stock (Eq, Show)

data DrainOrigin
  = DrainFromStarting StartingState
  | DrainFromReady ReadyEvidence
  | DrainFromDegraded DegradedEvidence
  deriving stock (Eq, Show)

newtype DrainingState = DrainingState
  { drainingOrigin :: DrainOrigin
  }
  deriving stock (Eq, Show)

data DaemonState
  = DaemonStarting StartingState
  | DaemonReady ReadyEvidence
  | DaemonDegraded DegradedEvidence
  | DaemonDraining DrainingState
  deriving stock (Eq, Show)

initialDaemonState :: Bool -> [Text] -> [Text] -> DaemonState
initialDaemonState metalRequired =
  initialDaemonStateWithTopicFamily
    metalRequired
    []

initialDaemonStateWithTopicFamily
  :: Bool
  -> [Text]
  -> [Text]
  -> [Text]
  -> DaemonState
initialDaemonStateWithTopicFamily metalRequired expectedTopics expectedConsumers expectedClientProbes =
  let progress =
        StartupProgress
          { progressMetalEvidence =
              if metalRequired
                then Nothing
                else Just MetalNotRequired
          , progressExpectedTopics = unique (fmap Text.strip expectedTopics)
          , progressTopicFamilyEvidence =
              if null expectedTopics
                then Just TopicFamilyNotRequired
                else Nothing
          , progressExpectedConsumers = unique expectedConsumers
          , progressConnectedConsumers = []
          , progressExpectedClientProbes = unique expectedClientProbes
          , progressSucceededClientProbes = []
          }
   in if null (progressExpectedConsumers progress)
        then
          degradeProgress progress (RuntimeInvariantFailed "daemon requires at least one planned consumer")
        else
          if null (progressExpectedClientProbes progress)
            then degradeProgress progress (RuntimeInvariantFailed "daemon requires at least one client probe")
            else promoteIfComplete progress

daemonStateReady :: DaemonState -> Bool
daemonStateReady (DaemonReady _) = True
daemonStateReady _ = False

daemonStateDraining :: DaemonState -> Bool
daemonStateDraining (DaemonDraining _) = True
daemonStateDraining _ = False

daemonReadyEvidence :: DaemonState -> Maybe ReadyEvidence
daemonReadyEvidence (DaemonReady evidence) = Just evidence
daemonReadyEvidence _ = Nothing

daemonStateLabel :: DaemonState -> Text
daemonStateLabel state =
  case state of
    DaemonStarting _ -> "starting"
    DaemonReady _ -> "ready"
    DaemonDegraded _ -> "degraded"
    DaemonDraining _ -> "draining"

daemonStateDetail :: DaemonState -> Text
daemonStateDetail state =
  case state of
    DaemonStarting starting ->
      "awaiting " <> startupStageText (startingStage starting)
    DaemonReady evidence ->
      "reconciled-topics="
        <> topicEvidenceCountText (readyTopicFamilyEvidence evidence)
        <> " connected-consumers="
        <> countText (readyConsumerConnections evidence)
        <> " client-probes="
        <> countText (readyClientProbes evidence)
    DaemonDegraded evidence -> renderDegradedCause (degradedCause evidence)
    DaemonDraining draining ->
      "draining from " <> drainOriginLabel (drainingOrigin draining)

recordMetalAcquired :: Text -> DaemonState -> DaemonState
recordMetalAcquired detail =
  updateProgress (setMetalEvidence (MetalAcquired (singleLine detail)))

recordMetalNotRequired :: DaemonState -> DaemonState
recordMetalNotRequired =
  updateProgress (setMetalEvidence MetalNotRequired)

recordMetalFailure :: Text -> DaemonState -> DaemonState
recordMetalFailure detail =
  degradeWith (MetalPrerequisiteFailed (singleLine detail))

recordTopicFamilyReconciled :: [Text] -> DaemonState -> DaemonState
recordTopicFamilyReconciled rawTopics state =
  case stateProgress state of
    Nothing -> state
    Just progress
      | isNothing (progressMetalEvidence progress) ->
          degradeProgress
            progress
            (RuntimeInvariantFailed "topic family reconciled before Metal acquisition")
      | isJust (firstDuplicate observed) ->
          degradeProgress
            progress
            (RuntimeInvariantFailed "topic reconcile evidence contains duplicate topics")
      | sort observed /= sort (progressExpectedTopics progress) ->
          degradeProgress
            progress
            (RuntimeInvariantFailed "topic reconcile evidence does not match the expected topic family")
      | otherwise ->
          promoteIfComplete
            progress
              { progressTopicFamilyEvidence =
                  Just (TopicFamilyReconciled observed)
              }
 where
  observed = fmap Text.strip rawTopics

recordTopicFamilyFailure :: Text -> DaemonState -> DaemonState
recordTopicFamilyFailure detail =
  degradeWith (TopicFamilyReconcileFailed (singleLine detail))

recordConsumerConnected :: Text -> Word64 -> DaemonState -> DaemonState
recordConsumerConnected rawTopic generation state
  | Text.null topic =
      degradeWith (RuntimeInvariantFailed "consumer connected with an empty topic") state
  | otherwise =
      case stateProgress state of
        Nothing -> state
        Just progress
          | isNothing (progressMetalEvidence progress) ->
              degradeProgress
                progress
                (RuntimeInvariantFailed ("consumer connected before Metal acquisition: " <> topic))
          | isNothing (progressTopicFamilyEvidence progress) ->
              degradeProgress
                progress
                (RuntimeInvariantFailed ("consumer connected before topic reconciliation: " <> topic))
          | topic `notElem` progressExpectedConsumers progress ->
              degradeProgress
                progress
                (RuntimeInvariantFailed ("unexpected consumer connection: " <> topic))
          | otherwise ->
              promoteIfComplete
                progress
                  { progressConnectedConsumers =
                      replaceConnection
                        ConsumerConnectionEvidence
                          { connectedConsumerTopic = topic
                          , connectedConsumerGeneration = generation
                          }
                        (progressConnectedConsumers progress)
                  }
 where
  topic = Text.strip rawTopic

recordConsumerDisconnected :: Text -> Text -> DaemonState -> DaemonState
recordConsumerDisconnected rawTopic rawReason state =
  case stateProgress state of
    Nothing -> state
    Just progress ->
      degradeProgress
        ( progress
            { progressConnectedConsumers =
                filter ((/= topic) . connectedConsumerTopic) (progressConnectedConsumers progress)
            }
        )
        (ConsumerConnectionLost topic (singleLine rawReason))
 where
  topic = Text.strip rawTopic

recordClientProbesSucceeded :: [Text] -> DaemonState -> DaemonState
recordClientProbesSucceeded probes state =
  case stateProgress state of
    Nothing -> state
    Just progress
      | not (allConsumersConnected progress) ->
          degradeProgress
            progress
            (RuntimeInvariantFailed "client probes completed before all consumers connected")
      | sort observed /= sort (progressExpectedClientProbes progress) ->
          degradeProgress
            progress
            (RuntimeInvariantFailed "client probe evidence does not match the expected probe set")
      | otherwise ->
          promoteIfComplete (progress {progressSucceededClientProbes = observed})
 where
  observed = unique (fmap Text.strip probes)

recordClientProbeFailure :: Text -> Text -> DaemonState -> DaemonState
recordClientProbeFailure probe detail =
  degradeWith (ClientProbeFailed (singleLine probe) (singleLine detail))

recordRuntimeFailure :: Text -> DaemonState -> DaemonState
recordRuntimeFailure detail =
  degradeWith (RuntimeTransportFailed (singleLine detail))

beginDaemonDrain :: DaemonState -> DaemonState
beginDaemonDrain state =
  case state of
    DaemonDraining _ -> state
    DaemonStarting starting -> DaemonDraining (DrainingState (DrainFromStarting starting))
    DaemonReady ready -> DaemonDraining (DrainingState (DrainFromReady ready))
    DaemonDegraded degraded -> DaemonDraining (DrainingState (DrainFromDegraded degraded))

updateProgress :: (StartupProgress -> StartupProgress) -> DaemonState -> DaemonState
updateProgress update state =
  case stateProgress state of
    Nothing -> state
    Just progress -> promoteIfComplete (update progress)

setMetalEvidence :: MetalEvidence -> StartupProgress -> StartupProgress
setMetalEvidence evidence progress =
  progress {progressMetalEvidence = Just evidence}

stateProgress :: DaemonState -> Maybe StartupProgress
stateProgress state =
  case state of
    DaemonStarting starting -> Just (startingProgress starting)
    DaemonReady ready -> Just (progressFromReady ready)
    DaemonDegraded degraded -> Just (degradedProgress degraded)
    DaemonDraining _ -> Nothing

progressFromReady :: ReadyEvidence -> StartupProgress
progressFromReady ready =
  StartupProgress
    { progressMetalEvidence = Just (readyMetalEvidence ready)
    , progressExpectedTopics = topicEvidenceTopics (readyTopicFamilyEvidence ready)
    , progressTopicFamilyEvidence = Just (readyTopicFamilyEvidence ready)
    , progressExpectedConsumers = readyExpectedConsumers ready
    , progressConnectedConsumers = readyConsumerConnections ready
    , progressExpectedClientProbes = readyClientProbes ready
    , progressSucceededClientProbes = readyClientProbes ready
    }

promoteIfComplete :: StartupProgress -> DaemonState
promoteIfComplete progress
  | Just metal <- progressMetalEvidence progress
  , Just topicEvidence <- progressTopicFamilyEvidence progress
  , allConsumersConnected progress
  , allClientProbesSucceeded progress =
      DaemonReady
        ReadyEvidence
          { readyMetalEvidence = metal
          , readyTopicFamilyEvidence = topicEvidence
          , readyExpectedConsumers = progressExpectedConsumers progress
          , readyConsumerConnections = progressConnectedConsumers progress
          , readyClientProbes = progressSucceededClientProbes progress
          }
  | otherwise =
      DaemonStarting
        StartingState
          { startingStage = progressStartupStage progress
          , startingProgress = progress
          }

progressStartupStage :: StartupProgress -> StartupStage
progressStartupStage progress
  | isNothing (progressMetalEvidence progress) = AwaitingMetal
  | isNothing (progressTopicFamilyEvidence progress) = AwaitingTopicFamily
  | not (allConsumersConnected progress) = AwaitingConsumerConnections
  | otherwise = AwaitingClientProbes

allConsumersConnected :: StartupProgress -> Bool
allConsumersConnected progress =
  sort (progressExpectedConsumers progress)
    == sort (fmap connectedConsumerTopic (progressConnectedConsumers progress))

allClientProbesSucceeded :: StartupProgress -> Bool
allClientProbesSucceeded progress =
  sort (progressExpectedClientProbes progress)
    == sort (progressSucceededClientProbes progress)

degradeWith :: DegradedCause -> DaemonState -> DaemonState
degradeWith cause state =
  case stateProgress state of
    Nothing -> state
    Just progress -> degradeProgress progress cause

degradeProgress :: StartupProgress -> DegradedCause -> DaemonState
degradeProgress progress cause =
  DaemonDegraded
    DegradedEvidence
      { degradedProgress = progress
      , degradedCause = cause
      }

replaceConnection
  :: ConsumerConnectionEvidence
  -> [ConsumerConnectionEvidence]
  -> [ConsumerConnectionEvidence]
replaceConnection connection connections =
  connection
    : filter
      ((/= connectedConsumerTopic connection) . connectedConsumerTopic)
      connections

unique :: (Eq value) => [value] -> [value]
unique = foldr insertUnique []
 where
  insertUnique value values
    | value `elem` values = values
    | otherwise = value : values

singleLine :: Text -> Text
singleLine = Text.unwords . Text.words

countText :: [value] -> Text
countText = Text.pack . show . length

startupStageText :: StartupStage -> Text
startupStageText stage =
  case stage of
    AwaitingMetal -> "metal"
    AwaitingTopicFamily -> "topic-family"
    AwaitingConsumerConnections -> "consumer-connections"
    AwaitingClientProbes -> "client-probes"

drainOriginLabel :: DrainOrigin -> Text
drainOriginLabel origin =
  case origin of
    DrainFromStarting _ -> "starting"
    DrainFromReady _ -> "ready"
    DrainFromDegraded _ -> "degraded"

renderDegradedCause :: DegradedCause -> Text
renderDegradedCause cause =
  case cause of
    MetalPrerequisiteFailed detail -> "metal prerequisite failed: " <> detail
    TopicFamilyReconcileFailed detail -> "topic family reconcile failed: " <> detail
    ConsumerConnectionLost topic detail ->
      "consumer disconnected: " <> topic <> ": " <> detail
    ClientProbeFailed probe detail -> "client probe failed: " <> probe <> ": " <> detail
    RuntimeInvariantFailed detail -> "runtime invariant failed: " <> detail
    RuntimeTransportFailed detail -> "runtime transport failed: " <> detail

topicEvidenceTopics :: TopicFamilyEvidence -> [Text]
topicEvidenceTopics evidence =
  case evidence of
    TopicFamilyNotRequired -> []
    TopicFamilyReconciled topics -> topics

topicEvidenceCountText :: TopicFamilyEvidence -> Text
topicEvidenceCountText = countText . topicEvidenceTopics

firstDuplicate :: (Eq value) => [value] -> Maybe value
firstDuplicate [] = Nothing
firstDuplicate (value : rest)
  | value `elem` rest = Just value
  | otherwise = firstDuplicate rest
