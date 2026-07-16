{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The Coordinator's exact topic-family reconciliation boundary. Topic names
-- come only from the validated topology; successful acquisition returns opaque
-- evidence that every expected topic was observed exactly once.
module JitML.Cluster.PulsarBootstrap
  ( AnyTopic
  , TopicCreateDisposition (..)
  , TopicFamilyEvidence
  , TopicFamilyEvidenceError (..)
  , TopicReconcileError (..)
  , PulsarTopicReconcileSettings (..)
  , topicName
  , pulsarTopics
  , bootstrapPulsarTopicReconcileSettings
  , inClusterPulsarTopicReconcileSettings
  , topicFamilyEvidenceTopics
  , topicFamilyEvidenceDispositions
  , refineTopicFamilyEvidence
  , reconcileTopicFamilyWith
  , pulsarTopicCreateSubprocess
  , pulsarTopicCreateSubprocessFor
  , pulsarTopicCreateSubprocesses
  , pulsarTopicStatsSubprocess
  , pulsarTopicStatsSubprocessFor
  , renderPulsarAdminCommands
  , runCoordinatorPulsarTopicReconcileIO
  , runPulsarTopicCreatesIO
  )
where

import Control.Concurrent (threadDelay)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Coordinator.Topology (AnyTopic, anyTopicName, coordinatorTopics)
import JitML.Service.Retry
  ( RetryPolicy
  , ServiceError (..)
  , retryServiceActionEither
  )
import JitML.Sub.Outcome
  ( ProcessFailure
  , ProcessOutcome (..)
  , processFailureStderr
  , renderProcessFailure
  )
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

data TopicCreateDisposition
  = TopicCreated
  | TopicAlreadyExists
  deriving stock (Eq, Show)

newtype TopicFamilyEvidence = TopicFamilyEvidence
  { topicFamilyObservations :: [(Text, TopicCreateDisposition)]
  }
  deriving stock (Eq, Show)

data TopicFamilyEvidenceError
  = DuplicateExpectedTopic Text
  | DuplicateObservedTopic Text
  | MissingObservedTopics [Text]
  | UnexpectedObservedTopics [Text]
  deriving stock (Eq, Show)

data TopicReconcileError failure
  = InvalidTopicFamilyEvidence TopicFamilyEvidenceError
  | TopicCreateFailed Text failure
  deriving stock (Eq, Show)

data PulsarTopicReconcileSettings = PulsarTopicReconcileSettings
  { topicReconcileKubectlBinary :: FilePath
  , topicReconcileKubeconfig :: FilePath
  , topicReconcileNamespace :: Text
  , topicReconcileToolsetPod :: Text
  , topicReconcileAdminBinary :: Text
  }
  deriving stock (Eq, Show)

pulsarTopics :: [AnyTopic]
pulsarTopics = coordinatorTopics

topicName :: AnyTopic -> Text
topicName = anyTopicName

bootstrapPulsarTopicReconcileSettings :: PulsarTopicReconcileSettings
bootstrapPulsarTopicReconcileSettings =
  PulsarTopicReconcileSettings
    { topicReconcileKubectlBinary = "kubectl"
    , topicReconcileKubeconfig = "./.build/jitml.kubeconfig"
    , topicReconcileNamespace = "platform"
    , topicReconcileToolsetPod = "pulsar-toolset-0"
    , topicReconcileAdminBinary = "/pulsar/bin/pulsar-admin"
    }

inClusterPulsarTopicReconcileSettings :: PulsarTopicReconcileSettings
inClusterPulsarTopicReconcileSettings =
  bootstrapPulsarTopicReconcileSettings {topicReconcileKubeconfig = ""}

topicFamilyEvidenceTopics :: TopicFamilyEvidence -> [Text]
topicFamilyEvidenceTopics = fmap fst . topicFamilyObservations

topicFamilyEvidenceDispositions :: TopicFamilyEvidence -> [(Text, TopicCreateDisposition)]
topicFamilyEvidenceDispositions = topicFamilyObservations

-- | Refine raw observations to exact topic-family evidence. This is kept
-- separate from the IO loop so missing, duplicate, and unexpected evidence are
-- directly testable rather than inferred from a hand-maintained count.
refineTopicFamilyEvidence
  :: [AnyTopic]
  -> [(Text, TopicCreateDisposition)]
  -> Either TopicFamilyEvidenceError TopicFamilyEvidence
refineTopicFamilyEvidence expected observations = do
  case firstDuplicate expectedNames of
    Just duplicate -> Left (DuplicateExpectedTopic duplicate)
    Nothing -> Right ()
  case firstDuplicate observedNames of
    Just duplicate -> Left (DuplicateObservedTopic duplicate)
    Nothing -> Right ()
  case filter (`notElem` observedNames) expectedNames of
    missing@(_ : _) -> Left (MissingObservedTopics missing)
    [] -> Right ()
  case filter (`notElem` expectedNames) observedNames of
    unexpected@(_ : _) -> Left (UnexpectedObservedTopics unexpected)
    [] -> Right ()
  ordered <- traverse observationFor expectedNames
  pure (TopicFamilyEvidence ordered)
 where
  expectedNames = fmap topicName expected
  observedNames = fmap fst observations
  observationFor expectedName =
    case find ((== expectedName) . fst) observations of
      Just observation -> Right observation
      Nothing -> Left (MissingObservedTopics [expectedName])

-- | Invoke one typed creation action per expected topology topic and return
-- evidence only when the complete family refines successfully.
reconcileTopicFamilyWith
  :: (Monad m)
  => [AnyTopic]
  -> (AnyTopic -> m (Either failure TopicCreateDisposition))
  -> m (Either (TopicReconcileError failure) TopicFamilyEvidence)
reconcileTopicFamilyWith expected create =
  case firstDuplicate (fmap topicName expected) of
    Just duplicate ->
      pure (Left (InvalidTopicFamilyEvidence (DuplicateExpectedTopic duplicate)))
    Nothing -> go [] expected
 where
  go observations [] =
    pure $
      case refineTopicFamilyEvidence expected observations of
        Left err -> Left (InvalidTopicFamilyEvidence err)
        Right evidence -> Right evidence
  go observations (topic : rest) = do
    result <- create topic
    case result of
      Left failure -> pure (Left (TopicCreateFailed (topicName topic) failure))
      Right disposition ->
        go (observations <> [(topicName topic, disposition)]) rest

renderPulsarAdminCommands :: [Text]
renderPulsarAdminCommands =
  fmap (\topic -> "pulsar-admin topics create " <> topicName topic) pulsarTopics

pulsarTopicCreateSubprocess :: AnyTopic -> Subprocess
pulsarTopicCreateSubprocess =
  pulsarTopicCreateSubprocessFor bootstrapPulsarTopicReconcileSettings

pulsarTopicCreateSubprocessFor
  :: PulsarTopicReconcileSettings
  -> AnyTopic
  -> Subprocess
pulsarTopicCreateSubprocessFor settings topic =
  subprocess
    (topicReconcileKubectlBinary settings)
    ( kubeconfigArgs settings
        <> [ "exec"
           , "-n"
           , topicReconcileNamespace settings
           , topicReconcileToolsetPod settings
           , "--"
           , topicReconcileAdminBinary settings
           , "topics"
           , "create"
           , topicName topic
           ]
    )

pulsarTopicCreateSubprocesses :: [Subprocess]
pulsarTopicCreateSubprocesses =
  fmap pulsarTopicCreateSubprocess pulsarTopics

-- | Read-only exact-topic observation. Namespace list endpoints can omit
-- unloaded bundles, so convergence probes each topology address directly.
pulsarTopicStatsSubprocess :: AnyTopic -> Subprocess
pulsarTopicStatsSubprocess =
  pulsarTopicStatsSubprocessFor bootstrapPulsarTopicReconcileSettings

pulsarTopicStatsSubprocessFor
  :: PulsarTopicReconcileSettings
  -> AnyTopic
  -> Subprocess
pulsarTopicStatsSubprocessFor settings topic =
  subprocess
    (topicReconcileKubectlBinary settings)
    ( kubeconfigArgs settings
        <> [ "exec"
           , "-n"
           , topicReconcileNamespace settings
           , topicReconcileToolsetPod settings
           , "--"
           , topicReconcileAdminBinary settings
           , "topics"
           , "stats"
           , topicName topic
           ]
    )

runCoordinatorPulsarTopicReconcileIO
  :: RetryPolicy
  -> IO (Either (TopicReconcileError ServiceError) TopicFamilyEvidence)
runCoordinatorPulsarTopicReconcileIO retryPolicy =
  reconcileTopicFamilyWith pulsarTopics $ \topic ->
    retryServiceActionEither retryPolicy createTopic topic
 where
  createTopic topic = do
    outcome <-
      runStreaming
        defaultSubprocessEnv
        (pulsarTopicCreateSubprocessFor inClusterPulsarTopicReconcileSettings topic)
    pure $
      case classifyTopicCreateOutcome outcome of
        Right disposition -> Right disposition
        Left failure ->
          Left
            ( SETransient
                ( "Coordinator topic reconcile failed for "
                    <> topicName topic
                    <> ": "
                    <> renderProcessFailure failure
                )
            )

-- | Bootstrap compatibility entrypoint. It now returns the same exact family
-- evidence as the live Coordinator, retaining an opaque subprocess failure for
-- each failed creation attempt.
runPulsarTopicCreatesIO
  :: IO (Either (TopicReconcileError ProcessFailure) TopicFamilyEvidence)
runPulsarTopicCreatesIO =
  reconcileTopicFamilyWith pulsarTopics (attempt (5 :: Int))
 where
  attempt attemptsRemaining topic = do
    outcome <- runStreaming defaultSubprocessEnv (pulsarTopicCreateSubprocess topic)
    case classifyTopicCreateOutcome outcome of
      Right disposition -> pure (Right disposition)
      Left failure
        | attemptsRemaining <= 1 -> pure (Left failure)
        | otherwise -> do
            threadDelay 2_000_000
            attempt (attemptsRemaining - 1) topic

classifyTopicCreateOutcome
  :: ProcessOutcome
  -> Either ProcessFailure TopicCreateDisposition
classifyTopicCreateOutcome outcome =
  case outcome of
    ProcessSucceeded _ -> Right TopicCreated
    ProcessFailed failure
      | topicAlreadyExists failure -> Right TopicAlreadyExists
      | otherwise -> Left failure

topicAlreadyExists :: ProcessFailure -> Bool
topicAlreadyExists failure =
  "already exists" `Text.isInfixOf` processFailureStderr failure
    || "HTTP code: 409" `Text.isInfixOf` processFailureStderr failure

kubeconfigArgs :: PulsarTopicReconcileSettings -> [Text]
kubeconfigArgs settings =
  case topicReconcileKubeconfig settings of
    "" -> []
    kubeconfig -> ["--kubeconfig", Text.pack kubeconfig]

firstDuplicate :: (Eq value) => [value] -> Maybe value
firstDuplicate [] = Nothing
firstDuplicate (value : rest)
  | value `elem` rest = Just value
  | otherwise = firstDuplicate rest
