{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Logger
    ( LogEvent (..)
    , renderLogEvent
    )
where

import Data.Aeson (encode, object, (.=))
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text.Encoding qualified as Text.Encoding

import JitML.Service.Lifecycle (LifecyclePhase, renderLifecyclePhase)
import JitML.Service.LiveConfig (LogLevel, renderLogLevel)

data LogEvent = LogEvent
    { logTimestamp :: Text
    , logLevel :: LogLevel
    , logMessage :: Text
    , logLifecyclePhase :: LifecyclePhase
    , logDaemonId :: Text
    }
    deriving stock (Eq, Show)

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
