{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.LiveConfig
    ( LiveConfig (..)
    , LogLevel (..)
    , defaultLiveConfig
    , renderLiveConfigDhall
    , renderLogLevel
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.Retry (RetryPolicy (..), renderRetryPolicyDhall)

data LogLevel
    = Debug
    | Info
    | Warn
    | Error
    deriving stock (Eq, Ord, Show)

data LiveConfig = LiveConfig
    { liveLogLevel :: LogLevel
    , liveRetryPolicy :: RetryPolicy
    , liveTartIdleTimeoutSeconds :: Maybe Int
    , liveInferenceBatchSize :: Int
    , liveInferenceMaxLatencyMillis :: Int
    , liveDrainDeadlineSeconds :: Int
    }
    deriving stock (Eq, Show)

defaultLiveConfig :: LiveConfig
defaultLiveConfig =
    LiveConfig
        { liveLogLevel = Info
        , liveRetryPolicy = ExponentialN 5 50 2000
        , liveTartIdleTimeoutSeconds = Just 1800
        , liveInferenceBatchSize = 64
        , liveInferenceMaxLatencyMillis = 25
        , liveDrainDeadlineSeconds = 30
        }

renderLiveConfigDhall :: LiveConfig -> Text
renderLiveConfigDhall config =
    Text.unlines
        [ "{ logLevel = " <> renderLogLevel (liveLogLevel config)
        , ", retryPolicy = " <> renderRetryPolicyDhall (liveRetryPolicy config)
        , ", tartIdleTimeout = " <> renderOptionalNatural (liveTartIdleTimeoutSeconds config)
        , ", inferenceBatchSize = " <> Text.pack (show (liveInferenceBatchSize config))
        , ", inferenceMaxLatencyMillis = " <> Text.pack (show (liveInferenceMaxLatencyMillis config))
        , ", drainDeadlineSeconds = " <> Text.pack (show (liveDrainDeadlineSeconds config))
        , "}"
        ]

renderLogLevel :: LogLevel -> Text
renderLogLevel Debug = "Debug"
renderLogLevel Info = "Info"
renderLogLevel Warn = "Warn"
renderLogLevel Error = "Error"

renderOptionalNatural :: Maybe Int -> Text
renderOptionalNatural Nothing = "None Natural"
renderOptionalNatural (Just value) = "Some " <> Text.pack (show value)
