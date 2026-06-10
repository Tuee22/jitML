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
  , liveInferenceBatchSize :: Int
  , liveInferenceMaxLatencyMillis :: Int
  , liveDedupCacheSize :: Int
  , liveDedupCacheTtlSeconds :: Int
  , liveDrainDeadlineSeconds :: Int
  , liveBuildVmCpuCount :: Int
  -- ^ Sprint 5.9 — resources the Apple Silicon daemon assigns to the
  -- jitml-managed Tart build VM, and how long it may sit idle before being
  -- stopped. Ignored on non-Apple substrates (no build VM).
  , liveBuildVmMemoryMib :: Int
  , liveBuildVmDiskGib :: Int
  , liveBuildVmIdleTimeoutSeconds :: Maybe Int
  }
  deriving stock (Eq, Show)

defaultLiveConfig :: LiveConfig
defaultLiveConfig =
  LiveConfig
    { liveLogLevel = Info
    , liveRetryPolicy = ExponentialN 5 50 2000
    , liveInferenceBatchSize = 64
    , liveInferenceMaxLatencyMillis = 25
    , liveDedupCacheSize = 4096
    , liveDedupCacheTtlSeconds = 3600
    , liveDrainDeadlineSeconds = 30
    , liveBuildVmCpuCount = 4
    , liveBuildVmMemoryMib = 8192
    , liveBuildVmDiskGib = 50
    , liveBuildVmIdleTimeoutSeconds = Just 1800
    }

renderLiveConfigDhall :: LiveConfig -> Text
renderLiveConfigDhall config =
  Text.unlines
    [ "{ logLevel = " <> renderLogLevel (liveLogLevel config)
    , ", retryPolicy = " <> renderRetryPolicyDhall (liveRetryPolicy config)
    , ", inferenceBatchSize = " <> Text.pack (show (liveInferenceBatchSize config))
    , ", inferenceMaxLatencyMillis = " <> Text.pack (show (liveInferenceMaxLatencyMillis config))
    , ", dedupCacheSize = " <> Text.pack (show (liveDedupCacheSize config))
    , ", dedupCacheTtlSeconds = " <> Text.pack (show (liveDedupCacheTtlSeconds config))
    , ", drainDeadlineSeconds = " <> Text.pack (show (liveDrainDeadlineSeconds config))
    , ", buildVmCpu = " <> Text.pack (show (liveBuildVmCpuCount config))
    , ", buildVmMemoryMib = " <> Text.pack (show (liveBuildVmMemoryMib config))
    , ", buildVmDiskGib = " <> Text.pack (show (liveBuildVmDiskGib config))
    , ", buildVmIdleTimeout = " <> renderOptionalNatural (liveBuildVmIdleTimeoutSeconds config)
    , "}"
    ]

renderOptionalNatural :: Maybe Int -> Text
renderOptionalNatural Nothing = "None Natural"
renderOptionalNatural (Just value) = "Some " <> Text.pack (show value)

renderLogLevel :: LogLevel -> Text
renderLogLevel Debug = "Debug"
renderLogLevel Info = "Info"
renderLogLevel Warn = "Warn"
renderLogLevel Error = "Error"
