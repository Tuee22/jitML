{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Logger
  ( DaemonLogger
  , LogEvent (..)
  , emitLogEvent
  , emitDaemonLog
  , logLevelAllows
  , newDaemonLogger
  , renderLogEvent
  )
where

import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time.Clock (getCurrentTime)
import GHC.Clock (getMonotonicTimeNSec)
import System.Posix.Process (getProcessID)

import JitML.CLI.Output qualified as Output
import JitML.Service.Lifecycle (LifecyclePhase, renderLifecyclePhase)
import JitML.Service.LiveConfig
  ( LiveConfig
  , LogLevel
  , liveLogLevel
  , renderLogLevel
  )

data LogEvent = LogEvent
  { logTimestamp :: Text
  , logLevel :: LogLevel
  , logMessage :: Text
  , logLifecyclePhase :: LifecyclePhase
  , logDaemonId :: Text
  }
  deriving stock (Eq, Show)

newtype DaemonLogger = DaemonLogger
  { daemonLoggerId :: Text
  }

-- | Generate one process identity at daemon acquisition. It is stable for the
-- lifetime of this logger and does not rely on caller-provided context fields.
newDaemonLogger :: IO DaemonLogger
newDaemonLogger = do
  processId <- getProcessID
  startedNs <- getMonotonicTimeNSec
  pure
    ( DaemonLogger
        ( "jitml-"
            <> Text.pack (show processId)
            <> "-"
            <> Text.pack (show startedNs)
        )
    )

renderLogEvent :: LogEvent -> Text
renderLogEvent event =
  Text.Encoding.decodeUtf8 (LazyByteString.toStrict encoded)
 where
  encoded =
    encode $
      object
        [ "ts" .= logTimestamp event
        , "level" .= renderLogLevel (logLevel event)
        , "msg" .= logMessage event
        , "lifecyclePhase" .= renderLifecyclePhase (logLifecyclePhase event)
        , "daemonId" .= logDaemonId event
        ]

logLevelAllows :: LogLevel -> LogLevel -> Bool
logLevelAllows configured eventLevel =
  eventLevel >= configured

-- | Operational structured stderr sink. The current atomic LiveConfig snapshot
-- is supplied for every call, so a SIGHUP level change takes effect without
-- rebuilding the logger. The Bool records whether the event crossed the
-- filter, which keeps reload behavior directly testable.
emitLogEvent :: LiveConfig -> LogEvent -> IO Bool
emitLogEvent liveConfig event
  | logLevelAllows (liveLogLevel liveConfig) (logLevel event) = do
      Output.writeErrorLineIO (renderLogEvent event)
      pure True
  | otherwise = pure False

-- | Emit with a freshly read LiveConfig snapshot. Supplying the atomic reader
-- rather than a captured config makes a SIGHUP threshold change effective on
-- the very next event.
emitDaemonLog
  :: DaemonLogger
  -> IO LiveConfig
  -> LogLevel
  -> LifecyclePhase
  -> Text
  -> IO Bool
emitDaemonLog logger readLiveConfig eventLevel phase message = do
  liveConfig <- readLiveConfig
  timestamp <- Text.pack . show <$> getCurrentTime
  emitLogEvent
    liveConfig
    LogEvent
      { logTimestamp = timestamp
      , logLevel = eventLevel
      , logMessage = message
      , logLifecyclePhase = phase
      , logDaemonId = daemonLoggerId logger
      }
