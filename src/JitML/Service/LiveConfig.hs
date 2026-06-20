{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.LiveConfig
  ( LiveConfig (..)
  , LogLevel (..)
  , defaultLiveConfig
  , renderLiveConfigDhall
  , renderLogLevel
  , liveConfigDecoder
  , logLevelDecoder
  , loadLiveConfig
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import Numeric.Natural (Natural)

import JitML.Service.Retry (RetryPolicy (..), renderRetryPolicyDhall, retryPolicyDecoder)

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
    , "}"
    ]

renderLogLevel :: LogLevel -> Text
renderLogLevel Debug = "Debug"
renderLogLevel Info = "Info"
renderLogLevel Warn = "Warn"
renderLogLevel Error = "Error"

-- | Sprint 5.12 — decode the @logLevel@ union; constructor order mirrors
-- @dhall/service/LiveConfig.dhall@.
logLevelDecoder :: Dhall.Decoder LogLevel
logLevelDecoder =
  Dhall.union $
    Dhall.constructor "Debug" (Debug <$ Dhall.unit)
      <> Dhall.constructor "Info" (Info <$ Dhall.unit)
      <> Dhall.constructor "Warn" (Warn <$ Dhall.unit)
      <> Dhall.constructor "Error" (Error <$ Dhall.unit)

-- | Sprint 5.12 — decode 'LiveConfig' from Dhall so the daemon's SIGHUP
-- hot-reload reads the real config file (not just a renderer) and so the
-- reflected schema in 'JitML.Service.DhallSchema' is derived from this decoder.
-- Field order mirrors @dhall/service/LiveConfig.dhall@.
liveConfigDecoder :: Dhall.Decoder LiveConfig
liveConfigDecoder =
  Dhall.record $
    LiveConfig
      <$> Dhall.field "logLevel" logLevelDecoder
      <*> Dhall.field "retryPolicy" retryPolicyDecoder
      <*> natField "inferenceBatchSize"
      <*> natField "inferenceMaxLatencyMillis"
      <*> natField "dedupCacheSize"
      <*> natField "dedupCacheTtlSeconds"
      <*> natField "drainDeadlineSeconds"
 where
  natField name = fmap naturalToInt (Dhall.field name Dhall.natural)

loadLiveConfig :: FilePath -> IO LiveConfig
loadLiveConfig = Dhall.inputFile liveConfigDecoder

naturalToInt :: Natural -> Int
naturalToInt = fromIntegral
