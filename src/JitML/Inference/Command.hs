{-# LANGUAGE OverloadedStrings #-}

module JitML.Inference.Command
  ( InferenceCommandRuntime (..)
  , inferenceReplyAppError
  , inferenceReplyStartupTimeoutMicros
  , inferenceReplyTimeoutMicros
  , matchingInferenceResult
  , publishAdversarialMoveCommandOnly
  , publishCheckpointCompareCommandOnly
  , publishListCheckpointsCommandOnly
  , publishLoadTranscriptCommandOnly
  , requestInferenceViaEngine
  , runInference
  )
where

import Control.Concurrent.MVar
  ( MVar
  , newEmptyMVar
  , takeMVar
  , tryPutMVar
  )
import Control.Monad (void)
import Control.Monad.Reader (liftIO)
import Data.Either.Combinators (mapLeft)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Timeout (timeout)

import JitML.AppError.AppError (AppError (..))
import JitML.Bootstrap (readExistingLivePublication)
import JitML.CLI.Output (exitWithError, writeLine)
import JitML.CLI.Parser (ParsedOption)
import JitML.Cluster.Publication qualified as Publication
import JitML.Coordinator.Topology qualified as Topology
import JitML.Env.Env (App)
import JitML.Proto.Inference qualified as Inference
import JitML.Service.Capabilities qualified as Capabilities
import JitML.Service.InferenceReplyScope qualified as InferenceReplyScope
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Substrate (Substrate)

-- | App-owned option resolution consumed by the inference command. Keeping
-- this callback explicit lets request/reply orchestration compile independently
-- without importing "JitML.App".
newtype InferenceCommandRuntime = InferenceCommandRuntime
  { inferenceCommandSelectedValue :: Text -> Text -> [ParsedOption] -> Text
  }

-- | `jitml inference run` — loads the latest checkpoint for the supplied
-- experiment hash from live MinIO and runs the selected substrate's weighted
-- checkpoint kernel over decoded `.jmw1` tensors. Without a live
-- `cluster-publication.json` there is no checkpoint source, so the command
-- fails closed with `InferenceCheckpointMissing`.
runInference :: InferenceCommandRuntime -> [ParsedOption] -> App ()
runInference runtime parsedOptions = do
  let experimentHash =
        inferenceCommandSelectedValue runtime "experiment-hash" "default" parsedOptions
      dhall =
        inferenceCommandSelectedValue
          runtime
          "experiment-dhall"
          "experiments/mnist.dhall"
          parsedOptions
  livePublication <- liftIO (readExistingLivePublication ".")
  case livePublication of
    Just publication -> do
      let edgePort = Publication.publicationEdgePort publication
          pulsarSettings = PulsarWebSocketSubprocess.pulsarSettingsForLocalEdge edgePort
          substrate = Publication.publicationSubstrate publication
      -- Sprint 11.10 — `jitml inference run` no longer computes in-process: it
      -- publishes an inference `WorkCommand` to the Engine (daemon) over
      -- `inference.request.<substrate>` and renders the streamed `WorkResult`
      -- from the reply topic. The Engine is the only role that computes (it reads
      -- the `.jmw1` checkpoint and runs the substrate kernel) and owns the
      -- `.ready` gate. The default probe input is `[1.0, 2.0]`.
      result <-
        liftIO
          (requestInferenceViaEngine pulsarSettings substrate experimentHash [1.0, 2.0])
      case result of
        Right values ->
          writeLine
            ( "inference: experiment="
                <> experimentHash
                <> " dhall="
                <> dhall
                <> " result="
                <> Text.pack (show values)
            )
        Left err ->
          exitWithError (inferenceReplyAppError experimentHash err)
    Nothing ->
      -- Sprint 10.5 — fail closed: without a live cluster publication there is
      -- no checkpoint to read, so emit a typed `InferenceCheckpointMissing`
      -- rather than the former `emptyManifest` + synthetic manifest summary.
      exitWithError (InferenceCheckpointMissing experimentHash)
{-# NOINLINE runInference #-}

-- | Sprint 11.10 (Pulsar ML-Workflow convergence) — the shared __publish a
-- @WorkCommand@ to the Engine and render the streamed @WorkResult@__ client. The
-- publisher (the @jitml inference run@ CLI; the Webapp panels) does __not__
-- compute: it publishes an inference @WorkCommand@ (the 'Inference.InferenceRequest'
-- wire form, per 'JitML.Work.Envelope') to @inference.request.<substrate>@ and
-- consumes the correlated @WorkResult@ off the reply topic. The single __Engine__
-- (daemon) is the only role that computes, and it owns the @.ready@/@ArtifactRef@
-- gate (it has the checkpoint manifest); the publisher carries no
-- 'JitML.Work.Envelope.ArtifactRef'.
requestInferenceViaEngine
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -- ^ experiment hash (the work's subject ref)
  -> [Double]
  -- ^ inference input payload
  -> IO (Either Text [Double])
requestInferenceViaEngine settings substrate experimentHash input = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-infer-" <> callId)
    callId
    ( \replyTopic ->
        Inference.RunInference
          Inference.InferenceRequest
            { Inference.irCallId = callId
            , Inference.irExperimentHash = experimentHash
            , Inference.irReplyTopic = replyTopic
            , Inference.irInput = input
            }
    )
    (matchingInferenceResult callId experimentHash)
{-# NOINLINE requestInferenceViaEngine #-}

-- | A live publication exists, so request/reply startup, transport, publish,
-- and timeout failures are broker-path failures rather than evidence that a
-- particular checkpoint is absent.
inferenceReplyAppError :: Text -> Text -> AppError
inferenceReplyAppError experimentHash detail =
  PulsarFailed
    ( "inference request/reply failed for "
        <> experimentHash
        <> ": "
        <> detail
    )

-- | Correlate a typed inference reply by both request identity fields. A
-- same-call reply for another experiment is unrelated evidence and remains on
-- the shared result stream for the owning client.
matchingInferenceResult :: Text -> Text -> Text -> Maybe [Double]
matchingInferenceResult expectedCallId expectedExperimentHash payload = do
  result <- Inference.parseInferenceResult payload
  if Inference.iresCallId result == expectedCallId
    && Inference.iresExperimentHash result == expectedExperimentHash
    then Just (Inference.iresOutput result)
    else Nothing

-- | Open an owned, from-latest reply cursor before publishing a command. The
-- persistent interpreter settles every receipt exactly once, drains the
-- matching delivery, and deletes the short-lived owned cursor on scope exit.
runInferenceCommandWithReply
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> Text
  -- ^ this call's id, so a terminal failure frame is matched to this request
  -> (Text -> Inference.InferenceCommand)
  -> (Text -> Maybe result)
  -> IO (Either Text result)
runInferenceCommandWithReply settings substrate subscriptionName callId buildCommand match =
  case inferenceRequestReplyPlan substrate subscriptionName of
    Left err -> pure (Left err)
    Right (requestTopic, replyTopic, subscription) -> do
      startupSignal <- newEmptyMVar
      resultSignal <- newEmptyMVar
      InferenceReplyScope.runInferenceReplyScope
        ( do
            consumed <-
              PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess settings $
                Capabilities.pulsarConsumeUntil
                  subscription
                  (observeReplySession startupSignal)
                  (handleReplyDelivery callId resultSignal match)
            case consumed of
              Left failure -> do
                void
                  ( tryPutMVar
                      startupSignal
                      (Left ("inference reply consumer failed: " <> Text.pack (show failure)))
                  )
                void
                  ( tryPutMVar
                      resultSignal
                      (Left ("inference reply consumer failed: " <> Text.pack (show failure)))
                  )
              Right result ->
                void (tryPutMVar resultSignal (Right result))
            pure consumed
        )
        ( do
            startup <- timeout inferenceReplyStartupTimeoutMicros (takeMVar startupSignal)
            case startup of
              Nothing -> pure (Left "inference reply consumer did not connect before the startup deadline")
              Just (Left err) -> pure (Left err)
              Just (Right ()) -> do
                published <-
                  PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
                    settings
                    ( Capabilities.pulsarPublish
                        requestTopic
                        (buildCommand (Topology.topicName replyTopic))
                    )
                case published of
                  Left err ->
                    pure (Left ("inference command publish failed: " <> Text.pack (show err)))
                  Right _ -> do
                    result <- timeout inferenceReplyTimeoutMicros (takeMVar resultSignal)
                    pure
                      ( fromMaybe
                          (Left "inference result: no matching reply received from the Engine")
                          result
                      )
        )

inferenceRequestReplyPlan
  :: Substrate
  -> Text
  -> Either
       Text
       ( Topology.Topic Inference.InferenceCommand
       , Topology.Topic Topology.InferenceResultMessage
       , Capabilities.Subscription Topology.InferenceResultMessage
       )
inferenceRequestReplyPlan substrate subscriptionName = do
  requestTopic <-
    mapLeftText "inference request topic" (Topology.topicFor Topology.InferenceRequestRoute substrate)
  replyTopic <-
    mapLeftText
      "inference reply topic"
      (Topology.topicFor Topology.InferenceResultRoute substrate)
  subscription <-
    mapLeftText
      "inference reply subscription"
      ( Capabilities.mkSubscription
          replyTopic
          subscriptionName
          Capabilities.FromLatest
          Capabilities.Owned
      )
  pure (requestTopic, replyTopic, subscription)

observeReplySession
  :: MVar (Either Text ())
  -> Capabilities.ConsumerSessionEvent
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess ()
observeReplySession startupSignal sessionEvent =
  liftIO $
    case sessionEvent of
      Capabilities.ConsumerSessionConnected _ ->
        void (tryPutMVar startupSignal (Right ()))
      Capabilities.ConsumerSessionDisconnected detail ->
        void (tryPutMVar startupSignal (Left ("inference reply disconnected: " <> detail)))
      Capabilities.ConsumerSessionDraining -> pure ()
      Capabilities.ConsumerSessionDrained -> pure ()

handleReplyDelivery
  :: Text
  -> MVar (Either Text result)
  -> (Text -> Maybe result)
  -> Capabilities.Delivery Topology.InferenceResultMessage
  -> PulsarWebSocketSubprocess.PulsarWebSocketSubprocess (Capabilities.ConsumerDecision result)
handleReplyDelivery callId resultSignal match delivery =
  let payload =
        Topology.inferenceResultMessagePayload
          (Capabilities.deliveryEvent delivery)
      -- The reply topic is shared, so a failure frame only answers THIS request
      -- when its call id matches; another call's terminal failure must not be
      -- misattributed here.
      terminalFailure =
        case Inference.parseInferenceFailure payload of
          Just failure
            | Inference.ifailCallId failure == callId ->
                Just (Inference.ifailError failure)
          _ -> Nothing
   in case terminalFailure of
        -- A terminal failure is a real answer. Complete the caller's wait with
        -- its diagnosis rather than letting the reply timeout expire; the scope
        -- then tears the cursor down as it would after any answered request.
        Just reason -> do
          liftIO (void (tryPutMVar resultSignal (Left reason)))
          pure (Capabilities.continue Capabilities.ack)
        Nothing ->
          pure $
            case match payload of
              Just result -> Capabilities.done Capabilities.ack result
              Nothing -> Capabilities.continue Capabilities.ack

mapLeftText :: (Show err) => Text -> Either err value -> Either Text value
mapLeftText context =
  mapLeft (((context <> ": ") <>) . Text.pack . show)

frameField :: Text -> Text -> Maybe Text
frameField key =
  lookup key . mapMaybe parseFrameField . Text.lines
 where
  parseFrameField line =
    case Text.breakOn ": " line of
      (field, rest)
        | not (Text.null field) && ": " `Text.isPrefixOf` rest ->
            Just (Text.strip field, Text.strip (Text.drop 2 rest))
      _ -> Nothing

inferenceReplyStartupTimeoutMicros :: Int
inferenceReplyStartupTimeoutMicros = 10000000

inferenceReplyTimeoutMicros :: Int
inferenceReplyTimeoutMicros = 30000000

-- | Sprint 11.10 — fire-and-forget publish of a checkpoint-compare @WorkCommand@;
-- the Engine runs both inferences + the delta and the panel renders the streamed
-- 'Inference.CheckpointCompareResult'.
publishCheckpointCompareCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> Text
  -> [Double]
  -> IO (Either Text ())
publishCheckpointCompareCommandOnly settings substrate baselineHash candidateHash input = do
  callId <- Text.pack . show <$> getPOSIXTime
  case inferenceRequestReplyPlan substrate ("jitml-compare-" <> callId) of
    Left err -> pure (Left err)
    Right (requestTopic, replyTopic, _unusedSubscription) -> do
      let command =
            Inference.CompareCheckpoints
              Inference.CheckpointCompareCommand
                { Inference.cccCallId = callId
                , Inference.cccBaselineExperimentHash = baselineHash
                , Inference.cccCandidateExperimentHash = candidateHash
                , Inference.cccReplyTopic = Topology.topicName replyTopic
                , Inference.cccInput = input
                }
      published <-
        PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
          settings
          (Capabilities.pulsarPublish requestTopic command)
      pure $
        case published of
          Left err -> Left ("compare command publish failed: " <> Text.pack (show err))
          Right _ -> Right ()
{-# NOINLINE publishCheckpointCompareCommandOnly #-}

-- | Sprint 11.10 / 14.3 — publish an adversarial-move @WorkCommand@ after
-- subscribing to its reply topic, then return the matching Engine
-- 'Inference.AdversarialMoveResult' frame. The same result is also visible to the
-- browser websocket bridge on its own subscription.
publishAdversarialMoveCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> Text
  -> [Int]
  -> Int
  -> Int
  -> IO (Either Text Text)
publishAdversarialMoveCommandOnly settings substrate game experimentHash moves humanIsPlayer simulations = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-move-" <> callId)
    callId
    ( \replyTopic ->
        Inference.SelectAdversarialMove
          Inference.AdversarialMoveCommand
            { Inference.amcCallId = callId
            , Inference.amcGame = game
            , Inference.amcExperimentHash = experimentHash
            , Inference.amcReplyTopic = replyTopic
            , Inference.amcMoves = moves
            , Inference.amcHumanIsPlayer = humanIsPlayer
            , Inference.amcSimulationsPerMove = simulations
            , Inference.amcInput = []
            }
    )
    (matchingKindPayload "AdversarialMoveResult" callId)
{-# NOINLINE publishAdversarialMoveCommandOnly #-}

-- | Sprint 14.1 / 27.1 / 28.2 (Feature A) — publish a checkpoint-browse
-- @WorkCommand@ after subscribing to the reply topic, then return the matching
-- @CheckpointList@ frame. The Engine still publishes the frame on the shared
-- browser stream; the POST body also carries it so browser e2e tests do not race
-- websocket subscription readiness.
publishListCheckpointsCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> IO (Either Text Text)
publishListCheckpointsCommandOnly settings substrate = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-checkpoints-" <> callId)
    callId
    ( \replyTopic ->
        Inference.ListCheckpoints
          Inference.ListCheckpointsCommand
            { Inference.lccCallId = callId
            , Inference.lccReplyTopic = replyTopic
            }
    )
    (matchingKindPayload "CheckpointList" callId)
{-# NOINLINE publishListCheckpointsCommandOnly #-}

-- | Sprint 14.1 (Feature B) — publish a transcript-replay @WorkCommand@ after
-- subscribing to its reply topic, then return the matching @TranscriptReplay@
-- frame. The Engine still owns the MinIO read; the Webapp only brokers the
-- correlated response back to the browser POST.
publishLoadTranscriptCommandOnly
  :: PulsarWebSocketSubprocess.PulsarWebSocketSettings
  -> Substrate
  -> Text
  -> IO (Either Text Text)
publishLoadTranscriptCommandOnly settings substrate transcriptId = do
  callId <- Text.pack . show <$> getPOSIXTime
  runInferenceCommandWithReply
    settings
    substrate
    ("jitml-transcript-" <> callId)
    callId
    ( \replyTopic ->
        Inference.LoadTranscript
          Inference.LoadTranscriptCommand
            { Inference.ltcCallId = callId
            , Inference.ltcTranscriptId = transcriptId
            , Inference.ltcReplyTopic = replyTopic
            }
    )
    (matchingKindPayload "TranscriptReplay" callId)
{-# NOINLINE publishLoadTranscriptCommandOnly #-}

matchingKindPayload :: Text -> Text -> Text -> Maybe Text
matchingKindPayload kind callId payload
  | frameField "kind" payload == Just kind
      && frameField "call-id" payload == Just callId =
      Just payload
  | otherwise = Nothing
