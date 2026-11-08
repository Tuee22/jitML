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
  , PulsarAdminFailure (..)
  , renderPulsarAdminFailure
  , classifyTopicStatsAttempt
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
  , runPulsarTopicReconcileAttemptIO
  , runPulsarAdminIO
  , runPulsarAdminAttemptWith
  , classifyTopicCreateAttempt
  )
where

import Control.Concurrent (threadDelay)
import Data.Aeson (Value (..), eitherDecodeStrict')
import Data.Char (intToDigit, toUpper)
import Data.List (find)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import System.Timeout (timeout)

import JitML.Coordinator.Topology (AnyTopic, anyTopicName, coordinatorTopics)
import JitML.Service.Retry
  ( RetryPolicy
  , ServiceError (..)
  , retryServiceActionEither
  )
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , renderObservedProcessFailure
  , renderProcessOutcome
  )
import JitML.Sub.Stream (defaultSubprocessEnv, observeProcessAction, runStreaming)
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
  , topicReconcileHttpBinary :: Text
  , topicReconcileAdminEndpoint :: Text
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
    , topicReconcileHttpBinary = "/usr/bin/curl"
    , topicReconcileAdminEndpoint = "http://pulsar-proxy:80/admin/v2"
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

-- | A completed HTTP/protocol refusal retains its genuine successful-process
-- transcript. It must not be fabricated into a nonzero subprocess exit.
data PulsarAdminFailure
  = PulsarAdminProcessFailure ObservedProcessFailure
  | PulsarAdminInvalidResult Text ProcessTranscript
  deriving stock (Eq, Show)

renderPulsarAdminFailure :: PulsarAdminFailure -> Text
renderPulsarAdminFailure (PulsarAdminProcessFailure failure) =
  renderObservedProcessFailure failure
renderPulsarAdminFailure (PulsarAdminInvalidResult message transcript) =
  message <> "\n" <> renderProcessOutcome (ProcessSucceeded transcript)

renderPulsarAdminCommands :: [Text]
renderPulsarAdminCommands =
  fmap
    (\topic -> "curl --request PUT " <> topicAdminUrl bootstrapPulsarTopicReconcileSettings topic)
    pulsarTopics

pulsarTopicCreateSubprocess :: AnyTopic -> Subprocess
pulsarTopicCreateSubprocess =
  pulsarTopicCreateSubprocessFor bootstrapPulsarTopicReconcileSettings

pulsarTopicCreateSubprocessFor
  :: PulsarTopicReconcileSettings
  -> AnyTopic
  -> Subprocess
pulsarTopicCreateSubprocessFor settings =
  topicHttpSubprocessFor settings "PUT" ""

pulsarTopicCreateSubprocesses :: [Subprocess]
pulsarTopicCreateSubprocesses =
  fmap pulsarTopicCreateSubprocess pulsarTopics

-- | Exact-topic stats retain loaded-topic evidence. Namespace lists and
-- partitioned-stats are not substitutes for this address-specific observation.
pulsarTopicStatsSubprocess :: AnyTopic -> Subprocess
pulsarTopicStatsSubprocess =
  pulsarTopicStatsSubprocessFor bootstrapPulsarTopicReconcileSettings

pulsarTopicStatsSubprocessFor
  :: PulsarTopicReconcileSettings
  -> AnyTopic
  -> Subprocess
pulsarTopicStatsSubprocessFor settings =
  topicHttpSubprocessFor settings "GET" "/stats"

topicHttpSubprocessFor
  :: PulsarTopicReconcileSettings
  -> Text
  -> Text
  -> AnyTopic
  -> Subprocess
topicHttpSubprocessFor settings method suffix topic =
  subprocess
    (topicReconcileKubectlBinary settings)
    ( kubectlTransportArgs settings
        <> [ "exec"
           , "-n"
           , topicReconcileNamespace settings
           , topicReconcileToolsetPod settings
           , "--"
           , "/usr/bin/timeout"
           , "--signal=TERM"
           , "--kill-after=3s"
           , "17s"
           , "/usr/bin/flock"
           , "--exclusive"
           , "--no-fork"
           , "/tmp/jitml-pulsar-admin.lock"
           , topicReconcileHttpBinary settings
           , "--disable"
           , "--silent"
           , "--show-error"
           , "--globoff"
           , "--noproxy"
           , "*"
           , "--location"
           , "--max-redirs"
           , "5"
           , "--proto"
           , "=http,https"
           , "--proto-redir"
           , "=http,https"
           , "--connect-timeout"
           , "2"
           , "--max-time"
           , "5"
           , "--request"
           , method
           , "--write-out"
           , "\nJITML_PULSAR_HTTP_STATUS=%{http_code}\n"
           ]
        <> ( if method == "PUT"
               then ["--header", "Content-Type: application/json", "--data-binary", "{}"]
               else []
           )
        <> [topicAdminUrl settings topic <> suffix]
    )

topicAdminUrl :: PulsarTopicReconcileSettings -> AnyTopic -> Text
topicAdminUrl settings topic =
  Text.dropWhileEnd (== '/') (topicReconcileAdminEndpoint settings)
    <> "/"
    <> Text.intercalate
      "/"
      (fmap pathSegment (Text.splitOn "/" (Text.replace "://" "/" (topicName topic))))
 where
  pathSegment = Text.concatMap encodeCharacter
  encodeCharacter character
    | character `elem` (['a' .. 'z'] <> ['A' .. 'Z'] <> ['0' .. '9'] <> "-._~") =
        Text.singleton character
    | otherwise =
        Text.concatMap
          bytePercentHex
          (Text.Encoding.decodeLatin1 (Text.Encoding.encodeUtf8 (Text.singleton character)))
  bytePercentHex character =
    let byte = fromEnum character
     in Text.pack ['%', toUpper (intToDigit (byte `div` 16)), toUpper (intToDigit (byte `mod` 16))]

-- | Both callers verify the exact nonpartitioned topic after creation/conflict.
-- Pulsar409 can also mean a partitioned-name conflict, which cannot acquire
-- family evidence without the subsequent exact HTTP200 stats object.
runPulsarTopicReconcileAttemptIO
  :: PulsarTopicReconcileSettings
  -> AnyTopic
  -> IO (Either PulsarAdminFailure TopicCreateDisposition)
runPulsarTopicReconcileAttemptIO settings topic = do
  createOutcome <- runPulsarAdminIO (pulsarTopicCreateSubprocessFor settings topic)
  case classifyTopicCreateAttempt createOutcome of
    Left failure -> pure (Left failure)
    Right disposition -> do
      statsOutcome <- runPulsarAdminIO (pulsarTopicStatsSubprocessFor settings topic)
      pure (disposition <$ classifyTopicStatsAttempt statsOutcome)

runCoordinatorPulsarTopicReconcileIO
  :: RetryPolicy
  -> IO (Either (TopicReconcileError ServiceError) TopicFamilyEvidence)
runCoordinatorPulsarTopicReconcileIO retryPolicy =
  reconcileTopicFamilyWith pulsarTopics $ \topic ->
    retryServiceActionEither retryPolicy createTopic topic
 where
  createTopic topic = do
    outcome <- runPulsarTopicReconcileAttemptIO inClusterPulsarTopicReconcileSettings topic
    pure $
      case outcome of
        Right disposition -> Right disposition
        Left failure ->
          Left
            ( SETransient
                ( "Coordinator topic reconcile failed for "
                    <> topicName topic
                    <> ": "
                    <> renderPulsarAdminFailure failure
                )
            )

-- | Bootstrap returns the same exact create-and-stats family evidence as the
-- live Coordinator. HTTP/protocol refusals retain completed transcripts, while
-- subprocess/attempt failures retain their original observed outcomes.
runPulsarTopicCreatesIO
  :: IO (Either (TopicReconcileError PulsarAdminFailure) TopicFamilyEvidence)
runPulsarTopicCreatesIO =
  reconcileTopicFamilyWith pulsarTopics (attempt (5 :: Int))
 where
  attempt attemptsRemaining topic = do
    outcome <- runPulsarTopicReconcileAttemptIO bootstrapPulsarTopicReconcileSettings topic
    case outcome of
      Right disposition -> pure (Right disposition)
      Left failure
        | attemptsRemaining <= 1 -> pure (Left failure)
        | otherwise -> do
            threadDelay 2_000_000
            attempt (attemptsRemaining - 1) topic

-- | Bound the local client independently of the watchdog inside the Pod. A
-- local deadline/runner exception has no observed exit status and must not be
-- manufactured into an ordinary command failure or an already-exists result.
runPulsarAdminAttemptWith
  :: Int
  -> (Subprocess -> IO ProcessOutcome)
  -> Subprocess
  -> IO ObservedProcessOutcome
runPulsarAdminAttemptWith deadlineMicros execute command =
  observeProcessAction command $ do
    if deadlineMicros <= 0
      then ioError (userError "Pulsar admin local deadline must be positive")
      else do
        completed <- timeout deadlineMicros (execute command)
        maybe
          ( ioError
              ( userError
                  "Pulsar admin local attempt exceeded its deadline; remote watchdog remains responsible for retirement"
              )
          )
          pure
          completed

-- | Admission belongs to the remote client's inherited flock descriptor, so
-- cancellation can propagate promptly after local runner cleanup. The remote
-- timeout bounds lock waiting plus execution even if this caller disappears.
runPulsarAdminIO :: Subprocess -> IO ObservedProcessOutcome
runPulsarAdminIO =
  runPulsarAdminAttemptWith 25_000_000 (runStreaming defaultSubprocessEnv)

-- | Curl writes this final status independently of the response body. A
-- nonzero/unknown subprocess never acquires HTTP evidence from partial output.
readHttpResponse
  :: ObservedProcessOutcome
  -> Either PulsarAdminFailure (Int, Text, ProcessTranscript)
readHttpResponse (ObservedProcessFailed failure) =
  Left (PulsarAdminProcessFailure failure)
readHttpResponse (ObservedProcessSucceeded transcript) =
  let marker = "\nJITML_PULSAR_HTTP_STATUS="
      (prefix, suffix) = Text.breakOnEnd marker (processTranscriptStdout transcript)
      invalid = Left (PulsarAdminInvalidResult "missing or malformed terminal Pulsar HTTP status" transcript)
   in case Text.stripSuffix "\n" suffix of
        Just digits
          | not (Text.null prefix)
              && Text.length digits == 3
              && Text.all (`elem` ['0' .. '9']) digits ->
              let status = Text.foldl' (\value character -> value * 10 + fromEnum character - fromEnum '0') 0 digits
               in if status >= 100 && status <= 599
                    then Right (status, Text.dropEnd (Text.length marker) prefix, transcript)
                    else invalid
        _ -> invalid

classifyTopicCreateAttempt
  :: ObservedProcessOutcome
  -> Either PulsarAdminFailure TopicCreateDisposition
classifyTopicCreateAttempt outcome = do
  (status, _body, transcript) <- readHttpResponse outcome
  case status of
    204 -> Right TopicCreated
    409 -> Right TopicAlreadyExists
    _ ->
      Left
        (PulsarAdminInvalidResult ("Pulsar topic PUT returned HTTP " <> Text.pack (show status)) transcript)

classifyTopicStatsAttempt
  :: ObservedProcessOutcome
  -> Either PulsarAdminFailure Text
classifyTopicStatsAttempt outcome = do
  (status, body, transcript) <- readHttpResponse outcome
  if status /= 200
    then
      Left
        ( PulsarAdminInvalidResult
            ("Pulsar exact-topic stats returned HTTP " <> Text.pack (show status))
            transcript
        )
    else case eitherDecodeStrict' (Text.Encoding.encodeUtf8 body) of
      Right (Object _) -> Right body
      _ ->
        Left (PulsarAdminInvalidResult "Pulsar exact-topic stats did not return a JSON object" transcript)

-- An explicit request timeout makes client-go's otherwise default REST config
-- non-default, preventing kubectl's service-account fallback. In-cluster
-- calls retain the local 25-second and remote 17-second watchdogs instead.
kubectlTransportArgs :: PulsarTopicReconcileSettings -> [Text]
kubectlTransportArgs settings =
  case topicReconcileKubeconfig settings of
    "" -> []
    kubeconfig -> ["--kubeconfig", Text.pack kubeconfig, "--request-timeout=23s"]

firstDuplicate :: (Eq value) => [value] -> Maybe value
firstDuplicate [] = Nothing
firstDuplicate (value : rest)
  | value `elem` rest = Just value
  | otherwise = firstDuplicate rest
