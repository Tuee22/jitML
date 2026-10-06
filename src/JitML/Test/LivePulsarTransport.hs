{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The broker transports of the live workflow harness.
--
-- Both transports establish the event source before anything is published: the
-- broker's admin CREATE of the @Owned@, @FromLatest@ subscription is
-- acknowledged first, and only that acknowledgement mints the
-- 'LiveWorkflow.EstablishedEventSource' the interpreter needs to publish,
-- consume, and release.  A socket-open lifecycle event is not evidence that the
-- broker holds a cursor, so a reply published right after it could be missed;
-- the acknowledged CREATE is.  The consumer then attaches to the established
-- (@Borrowed@) view and never owns the subscription's deletion: the release
-- hook of the token issues the single bounded admin DELETE.
--
-- These live in the library, rather than in the integration stanza, so the
-- offline fake-node and fake-admin harness in "JitML.Test.PulsarTransport"
-- exercises exactly the transports the live workflows use.
module JitML.Test.LivePulsarTransport
  ( livePulsarTransport
  , liveSubprocessTransport
  )
where

import Control.Exception (uninterruptibleMask_)
import Control.Monad.IO.Class (liftIO)
import Data.Text (Text)

import JitML.Coordinator.Topology (Topic)
import JitML.Service.Capabilities
  ( ConsumerDecision
  , ConsumerFailure (..)
  , ConsumerSessionEvent
  , Delivery
  , HasPulsar (..)
  )
import JitML.Service.PulsarWebSocketSubprocess
  ( PulsarWebSocketSettings
  )
import JitML.Service.PulsarWebSocketSubprocess qualified as PulsarWebSocketSubprocess
import JitML.Service.Retry (ServiceError (..))
import JitML.Sub.Outcome
  ( ProcessOutcome (..)
  , ProcessTranscript (..)
  , renderProcessOutcome
  )
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess)
import JitML.Test.LiveWorkflow
  ( EstablishedEventSource
  , LiveCommand (..)
  , LiveEventSource
  , LiveTransport (..)
  )
import JitML.Test.LiveWorkflow qualified as LiveWorkflow

-- | Transport for protocol commands.  The reply cursor is established with the
-- command's request topic, and the command is published through that cursor.  A
-- typed executable has no request topic and is rejected here, before any
-- broker state exists; 'liveSubprocessTransport' owns that shape.
livePulsarTransport
  :: PulsarWebSocketSettings
  -> LiveTransport command event
livePulsarTransport settings =
  LiveTransport
    { liveEstablishEventSource = \command source ->
        case command of
          ProtocolCommand topic _event ->
            establishCorrelated settings topic source
          ExecutableCommand _ ->
            pure
              ( Left
                  ( SETransient
                      ( "Pulsar transport cannot execute typed command: "
                          <> LiveWorkflow.liveCommandCanonicalText command
                      )
                  )
              )
    , liveConsumeEvents = consumeEstablished settings
    }

-- | Transport for typed executables whose result is an event on a broker
-- topic.  There is no request topic, so establishment is subscription-only: the
-- cursor exists before the executable runs, and the executable's own
-- publication cannot land ahead of it.  Protocol commands share the correlated
-- path of 'livePulsarTransport'.
liveSubprocessTransport
  :: PulsarWebSocketSettings
  -> LiveTransport Subprocess event
liveSubprocessTransport settings =
  LiveTransport
    { liveEstablishEventSource = \command source ->
        case command of
          ProtocolCommand topic _event ->
            establishCorrelated settings topic source
          ExecutableCommand _ ->
            establishSubscriptionOnly settings source
    , liveConsumeEvents = consumeEstablished settings
    }

-- | Establish the reply cursor for a protocol command and publish through it.
--
-- The admin CREATE is a single bounded call (curl carries connect and total
-- deadlines), and whether the broker completed it is unobservable if it is
-- interrupted.  It therefore runs uninterruptibly: a cancellation that arrives
-- meanwhile is delivered once the token exists, where the interpreter releases
-- it, instead of orphaning a subscription that no token names.
establishCorrelated
  :: PulsarWebSocketSettings
  -> Topic command
  -> LiveEventSource command event
  -> IO (Either ServiceError (EstablishedEventSource command event))
establishCorrelated settings requestTopic source =
  case LiveWorkflow.liveEventSourceSubscription source of
    Nothing -> pure (Left (localSourceRefusal source))
    Just subscription -> do
      established <-
        uninterruptibleMask_
          ( PulsarWebSocketSubprocess.establishReplyCursor
              settings
              requestTopic
              subscription
          )
      pure
        ( fmap
            ( \cursor ->
                LiveWorkflow.establishedEventSource
                  ( LiveWorkflow.pulsarEventSource
                      (PulsarWebSocketSubprocess.replyCursorSubscription cursor)
                  )
                  (publishThroughCursor settings cursor)
                  (PulsarWebSocketSubprocess.releaseReplyCursor settings cursor)
            )
            established
        )

-- | The correlated publication.  Both topics come out of the cursor, so the
-- topic carried by the command is not consulted; a typed executable is not a
-- publication on this path.
publishThroughCursor
  :: PulsarWebSocketSettings
  -> PulsarWebSocketSubprocess.ReplyCursor command event
  -> LiveCommand command
  -> IO (Either ServiceError Text)
publishThroughCursor settings cursor command =
  case command of
    ProtocolCommand _topic event ->
      PulsarWebSocketSubprocess.publishWithReplyCursor
        settings
        cursor
        (const event)
    ExecutableCommand _ ->
      pure
        ( Left
            ( SETransient
                ( "Pulsar cursor cannot publish typed command: "
                    <> LiveWorkflow.liveCommandCanonicalText command
                )
            )
        )

-- | Establish the subscription for a typed executable.  Same uninterruptible
-- CREATE as 'establishCorrelated'; the executable itself runs under the
-- interpreter's ordinary interruptibility once the token exists.
establishSubscriptionOnly
  :: PulsarWebSocketSettings
  -> LiveEventSource Subprocess event
  -> IO (Either ServiceError (EstablishedEventSource Subprocess event))
establishSubscriptionOnly settings source =
  case LiveWorkflow.liveEventSourceSubscription source of
    Nothing -> pure (Left (localSourceRefusal source))
    Just subscription -> do
      established <-
        uninterruptibleMask_
          (PulsarWebSocketSubprocess.establishSubscription settings subscription)
      pure
        ( fmap
            ( \cursor ->
                LiveWorkflow.establishedEventSource
                  ( LiveWorkflow.pulsarEventSource
                      (PulsarWebSocketSubprocess.establishedSubscriptionConsumerView cursor)
                  )
                  runTypedExecutable
                  (PulsarWebSocketSubprocess.releaseEstablishedSubscription settings cursor)
            )
            established
        )

runTypedExecutable :: LiveCommand Subprocess -> IO (Either ServiceError Text)
runTypedExecutable command =
  case command of
    ExecutableCommand executable -> do
      outcome <- runStreaming defaultSubprocessEnv executable
      pure $ case outcome of
        ProcessSucceeded transcript ->
          Right (processTranscriptStdout transcript)
        ProcessFailed _ ->
          Left
            ( SETransient
                ("live subprocess failed:\n" <> renderProcessOutcome outcome)
            )
    ProtocolCommand _topic _payload ->
      pure
        ( Left
            ( SETransient
                ( "typed executable transport cannot publish protocol command: "
                    <> LiveWorkflow.liveCommandCanonicalText command
                )
            )
        )

-- | Consume the established (borrowed) view.  Consuming it never deletes
-- anything: release belongs to the token.
consumeEstablished
  :: PulsarWebSocketSettings
  -> EstablishedEventSource command event
  -> (ConsumerSessionEvent -> IO ())
  -> (Delivery event -> IO (ConsumerDecision result))
  -> IO (Either ConsumerFailure result)
consumeEstablished settings established observe handle =
  case LiveWorkflow.liveEventSourceSubscription view of
    Nothing ->
      pure
        ( Left
            ( ConsumerProtocolFailure
                ( "Pulsar transport cannot consume local evidence source "
                    <> LiveWorkflow.liveEventSourceName view
                )
            )
        )
    Just subscription ->
      PulsarWebSocketSubprocess.runPulsarWebSocketSubprocess
        settings
        ( pulsarConsumeUntil
            subscription
            (liftIO . observe)
            (liftIO . handle)
        )
 where
  view = LiveWorkflow.establishedEventSourceView established

localSourceRefusal :: LiveEventSource command event -> ServiceError
localSourceRefusal source =
  SEConflict
    ( "Pulsar transport cannot establish local evidence source "
        <> LiveWorkflow.liveEventSourceName source
    )
