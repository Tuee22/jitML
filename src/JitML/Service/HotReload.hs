{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.HotReload
  ( LiveConfigSnapshot (..)
  , ReloadDecision (..)
  , initialSnapshot
  , handleSighupReload
  , renderReloadDecision
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.LiveConfig (LiveConfig)

data LiveConfigSnapshot = LiveConfigSnapshot
  { snapshotGeneration :: Int
  , snapshotConfig :: LiveConfig
  }
  deriving stock (Eq, Show)

data ReloadDecision
  = ReloadApplied LiveConfigSnapshot
  | ReloadIgnored Text
  deriving stock (Eq, Show)

initialSnapshot :: LiveConfig -> LiveConfigSnapshot
initialSnapshot config =
  LiveConfigSnapshot
    { snapshotGeneration = 0
    , snapshotConfig = config
    }

handleSighupReload :: LiveConfigSnapshot -> LiveConfig -> ReloadDecision
handleSighupReload current nextConfig
  | snapshotConfig current == nextConfig =
      ReloadIgnored "live config unchanged"
  | otherwise =
      ReloadApplied
        current
          { snapshotGeneration = snapshotGeneration current + 1
          , snapshotConfig = nextConfig
          }

renderReloadDecision :: ReloadDecision -> Text
renderReloadDecision (ReloadIgnored reason) =
  "reload: ignored; reason=" <> reason
renderReloadDecision (ReloadApplied snapshot) =
  "reload: applied; generation=" <> Text.pack (show (snapshotGeneration snapshot))
