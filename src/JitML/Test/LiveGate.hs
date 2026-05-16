{-# LANGUAGE OverloadedStrings #-}

module JitML.Test.LiveGate
  ( LiveGate (..)
  , liveGateEnvVar
  , liveGateFromEnv
  , renderLiveGate
  )
where

import Data.Char (toLower)
import Data.Text (Text)
import Data.Text qualified as Text

data LiveGate
  = LiveDisabled
  | LiveEnabled
  deriving stock (Eq, Show)

liveGateEnvVar :: String
liveGateEnvVar =
  "JITML_LIVE_E2E"

liveGateFromEnv :: [(String, String)] -> LiveGate
liveGateFromEnv environment =
  case normalize <$> lookup liveGateEnvVar environment of
    Just value | value `elem` enabledValues -> LiveEnabled
    _ -> LiveDisabled
 where
  normalize =
    fmap toLower

  enabledValues =
    ["1", "true", "yes", "on"]

renderLiveGate :: LiveGate -> Text
renderLiveGate LiveDisabled =
  "live e2e: disabled; set " <> Text.pack liveGateEnvVar <> "=1 to run live Kind/Helm validation"
renderLiveGate LiveEnabled =
  "live e2e: enabled"
