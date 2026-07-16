{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.LiveConfig
  ( LiveConfig (..)
  , LiveConfigError (..)
  , LogLevel (..)
  , defaultLiveConfig
  , liveDrainDeadlineMicros
  , liveInferenceMaxLatencyMicros
  , renderLiveConfigDhall
  , renderLiveConfigError
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

import JitML.Service.Retry
  ( RetryPolicy (..)
  , renderRetryPolicyDhall
  , retryPolicyDecoder
  )

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

data LiveConfigError
  = LiveConfigValueOutOfRange Text Natural Natural
  | LiveConfigValueMustBePositive Text
  deriving stock (Eq, Show)

data RawLiveConfig = RawLiveConfig
  { rawLogLevel :: LogLevel
  , rawRetryPolicy :: RetryPolicy
  , rawInferenceBatchSize :: Natural
  , rawInferenceMaxLatencyMillis :: Natural
  , rawDedupCacheSize :: Natural
  , rawDedupCacheTtlSeconds :: Natural
  , rawDrainDeadlineSeconds :: Natural
  }
  deriving stock (Eq, Show)

defaultLiveConfig :: LiveConfig
defaultLiveConfig =
  LiveConfig
    { liveLogLevel = Info
    , liveRetryPolicy = ExponentialN 5 50 2000
    , liveInferenceBatchSize = 64
    , liveInferenceMaxLatencyMillis = 5000
    , liveDedupCacheSize = 4096
    , liveDedupCacheTtlSeconds = 3600
    , liveDrainDeadlineSeconds = 30
    }

renderLiveConfigDhall :: LiveConfig -> Text
renderLiveConfigDhall config =
  Text.unlines
    [ "{ logLevel = " <> renderLogLevelDhall (liveLogLevel config)
    , ", retryPolicy = " <> renderRetryPolicyDhall (liveRetryPolicy config)
    , ", inferenceBatchSize = " <> Text.pack (show (liveInferenceBatchSize config))
    , ", inferenceMaxLatencyMillis = "
        <> Text.pack (show (liveInferenceMaxLatencyMillis config))
    , ", dedupCacheSize = " <> Text.pack (show (liveDedupCacheSize config))
    , ", dedupCacheTtlSeconds = " <> Text.pack (show (liveDedupCacheTtlSeconds config))
    , ", drainDeadlineSeconds = " <> Text.pack (show (liveDrainDeadlineSeconds config))
    , "}"
    ]

renderLiveConfigError :: LiveConfigError -> Text
renderLiveConfigError (LiveConfigValueOutOfRange field actual maximumValue) =
  "LiveConfig "
    <> field
    <> " must be at most "
    <> showText maximumValue
    <> ", received "
    <> showText actual
renderLiveConfigError (LiveConfigValueMustBePositive field) =
  "LiveConfig " <> field <> " must be greater than zero"

-- | Convert the validated drain budget without an overflowing intermediate.
-- Programmatically constructed configs are clamped defensively; values loaded
-- from Dhall have already passed the stricter refinement below.
liveDrainDeadlineMicros :: LiveConfig -> Int
liveDrainDeadlineMicros config =
  fromInteger
    ( min
        (toInteger (maxBound :: Int))
        (toInteger (max 0 (liveDrainDeadlineSeconds config)) * 1000 * 1000)
    )

liveInferenceMaxLatencyMicros :: LiveConfig -> Int
liveInferenceMaxLatencyMicros config =
  fromInteger
    ( min
        (toInteger (maxBound :: Int))
        (toInteger (max 0 (liveInferenceMaxLatencyMillis config)) * 1000)
    )

renderLogLevel :: LogLevel -> Text
renderLogLevel Debug = "Debug"
renderLogLevel Info = "Info"
renderLogLevel Warn = "Warn"
renderLogLevel Error = "Error"

logLevelDhallType :: Text
logLevelDhallType = "< Debug | Info | Warn | Error >"

-- | A constructor name by itself is an unbound variable in standalone Dhall.
-- Keep the compact rendering above for structured logs, but qualify mounted
-- configuration values with their union type so every generated
-- @LiveConfig.dhall@ type-checks without an ambient import or @let@ binding.
renderLogLevelDhall :: LogLevel -> Text
renderLogLevelDhall level =
  logLevelDhallType <> "." <> renderLogLevel level

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
liveConfigDecoder :: Dhall.Decoder RawLiveConfig
liveConfigDecoder =
  Dhall.record $
    RawLiveConfig
      <$> Dhall.field "logLevel" logLevelDecoder
      <*> Dhall.field "retryPolicy" retryPolicyDecoder
      <*> Dhall.field "inferenceBatchSize" Dhall.natural
      <*> Dhall.field "inferenceMaxLatencyMillis" Dhall.natural
      <*> Dhall.field "dedupCacheSize" Dhall.natural
      <*> Dhall.field "dedupCacheTtlSeconds" Dhall.natural
      <*> Dhall.field "drainDeadlineSeconds" Dhall.natural

loadLiveConfig :: FilePath -> IO LiveConfig
loadLiveConfig path = do
  raw <- Dhall.inputFile liveConfigDecoder path
  case rawToLiveConfig raw of
    Left err -> ioError (userError (Text.unpack (renderLiveConfigError err)))
    Right config -> pure config

rawToLiveConfig :: RawLiveConfig -> Either LiveConfigError LiveConfig
rawToLiveConfig raw = do
  retryPolicy <- validateRetryPolicy (rawRetryPolicy raw)
  inferenceBatchSize <- positiveBoundedInt "inferenceBatchSize" intMaximum (rawInferenceBatchSize raw)
  inferenceMaxLatencyMillis <-
    positiveBoundedInt
      "inferenceMaxLatencyMillis"
      maximumLatencyMillis
      (rawInferenceMaxLatencyMillis raw)
  dedupCacheSize <- boundedInt "dedupCacheSize" intMaximum (rawDedupCacheSize raw)
  dedupCacheTtlSeconds <-
    boundedInt "dedupCacheTtlSeconds" intMaximum (rawDedupCacheTtlSeconds raw)
  drainDeadlineSeconds <-
    positiveBoundedInt
      "drainDeadlineSeconds"
      maximumDrainDeadlineSeconds
      (rawDrainDeadlineSeconds raw)
  pure
    LiveConfig
      { liveLogLevel = rawLogLevel raw
      , liveRetryPolicy = retryPolicy
      , liveInferenceBatchSize = inferenceBatchSize
      , liveInferenceMaxLatencyMillis = inferenceMaxLatencyMillis
      , liveDedupCacheSize = dedupCacheSize
      , liveDedupCacheTtlSeconds = dedupCacheTtlSeconds
      , liveDrainDeadlineSeconds = drainDeadlineSeconds
      }

validateRetryPolicy :: RetryPolicy -> Either LiveConfigError RetryPolicy
validateRetryPolicy policy =
  case policy of
    Once -> Right Once
    LinearN attempts delayMillis -> do
      positiveBoundedNatural "retryPolicy.LinearN.attempts" intMaximum attempts
      positiveBoundedNatural "retryPolicy.LinearN.delayMillis" maximumDelayMillis delayMillis
      pure policy
    ExponentialN attempts baseMillis capMillis -> do
      positiveBoundedNatural "retryPolicy.ExponentialN.attempts" intMaximum attempts
      positiveBoundedNatural "retryPolicy.ExponentialN.baseMillis" maximumDelayMillis baseMillis
      positiveBoundedNatural "retryPolicy.ExponentialN.capMillis" maximumDelayMillis capMillis
      pure policy
    RetryUntil deadlineMillis -> do
      positiveBoundedNatural "retryPolicy.RetryUntil.deadlineMillis" maximumDelayMillis deadlineMillis
      pure policy

boundedInt :: Text -> Natural -> Natural -> Either LiveConfigError Int
boundedInt field maximumValue actual
  | actual > maximumValue = Left (LiveConfigValueOutOfRange field actual maximumValue)
  | otherwise = Right (fromIntegral actual)

positiveBoundedInt :: Text -> Natural -> Natural -> Either LiveConfigError Int
positiveBoundedInt field maximumValue actual
  | actual == 0 = Left (LiveConfigValueMustBePositive field)
  | otherwise = boundedInt field maximumValue actual

positiveBoundedNatural :: Text -> Natural -> Natural -> Either LiveConfigError ()
positiveBoundedNatural field maximumValue actual
  | actual == 0 = Left (LiveConfigValueMustBePositive field)
  | actual > maximumValue = Left (LiveConfigValueOutOfRange field actual maximumValue)
  | otherwise = Right ()

intMaximum :: Natural
intMaximum = fromIntegral (maxBound :: Int)

maximumDrainDeadlineSeconds :: Natural
maximumDrainDeadlineSeconds = intMaximum `div` (1000 * 1000)

maximumLatencyMillis :: Natural
maximumLatencyMillis = intMaximum `div` 1000

maximumDelayMillis :: Natural
maximumDelayMillis = intMaximum `div` 1000

showText :: (Show value) => value -> Text
showText = Text.pack . show
