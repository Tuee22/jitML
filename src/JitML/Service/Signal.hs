{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Signal
  ( DaemonControl
  , DaemonControlSnapshot (..)
  , DaemonSignal (..)
  , DaemonSignalAction (..)
  , applyDaemonSignal
  , applyDaemonLiveConfig
  , daemonSignalAction
  , modifyDaemonState
  , newDaemonControl
  , newDaemonControlWithLiveConfig
  , readDaemonControl
  , renderDaemonSignal
  , renderDaemonSignalAction
  , signalPlan
  , snapshotDraining
  , snapshotLiveConfig
  , snapshotReloadGeneration
  , snapshotReady
  , withDaemonSignalHandlers
  )
where

import Control.Exception (bracket)
import Data.Foldable (traverse_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text (Text)
import System.Posix.Signals
  ( Handler (Catch)
  , Signal
  , installHandler
  , sigHUP
  , sigINT
  , sigTERM
  )

import JitML.Service.HotReload
  ( LiveConfigSnapshot
  , ReloadDecision (..)
  , handleSighupReload
  , initialSnapshot
  , snapshotConfig
  , snapshotGeneration
  )
import JitML.Service.LiveConfig (LiveConfig, defaultLiveConfig)
import JitML.Service.RuntimeState
  ( DaemonState
  , beginDaemonDrain
  , daemonStateDraining
  , daemonStateReady
  )

data DaemonSignal
  = DaemonSighup
  | DaemonSigint
  | DaemonSigterm
  deriving stock (Eq, Show)

data DaemonSignalAction
  = ReloadLiveConfig
  | BeginGracefulDrain
  deriving stock (Eq, Show)

newtype DaemonControl = DaemonControl
  { daemonControlSnapshotRef :: IORef DaemonControlSnapshot
  }

-- | One atomic control snapshot.  Readiness and draining are projections of
-- the closed daemon state, never independently writable flags.
data DaemonControlSnapshot = DaemonControlSnapshot
  { snapshotDaemonState :: DaemonState
  , snapshotLiveConfigState :: LiveConfigSnapshot
  }
  deriving stock (Eq, Show)

newDaemonControl :: DaemonState -> IO DaemonControl
newDaemonControl initialState =
  newDaemonControlWithLiveConfig initialState defaultLiveConfig

newDaemonControlWithLiveConfig :: DaemonState -> LiveConfig -> IO DaemonControl
newDaemonControlWithLiveConfig initialState liveConfig =
  DaemonControl
    <$> newIORef
      DaemonControlSnapshot
        { snapshotDaemonState = initialState
        , snapshotLiveConfigState = initialSnapshot liveConfig
        }

applyDaemonSignal :: DaemonControl -> DaemonSignal -> IO DaemonControlSnapshot
applyDaemonSignal control signal =
  atomicModifyIORef' (daemonControlSnapshotRef control) $ \snapshot ->
    let next =
          case daemonSignalAction signal of
            -- Receipt of SIGHUP is only a request. Generation changes belong
            -- to a successfully decoded, changed LiveConfig applied through
            -- 'applyDaemonLiveConfig'.
            ReloadLiveConfig -> snapshot
            BeginGracefulDrain ->
              snapshot
                { snapshotDaemonState = beginDaemonDrain (snapshotDaemonState snapshot)
                }
     in (next, next)

applyDaemonLiveConfig :: DaemonControl -> LiveConfig -> IO ReloadDecision
applyDaemonLiveConfig control nextConfig =
  atomicModifyIORef' (daemonControlSnapshotRef control) $ \snapshot ->
    let decision = handleSighupReload (snapshotLiveConfigState snapshot) nextConfig
        nextSnapshot =
          case decision of
            ReloadIgnored _reason -> snapshot
            ReloadApplied liveSnapshot ->
              snapshot {snapshotLiveConfigState = liveSnapshot}
     in (nextSnapshot, decision)

modifyDaemonState
  :: DaemonControl
  -> (DaemonState -> DaemonState)
  -> IO DaemonControlSnapshot
modifyDaemonState control transition =
  atomicModifyIORef' (daemonControlSnapshotRef control) $ \snapshot ->
    let next = snapshot {snapshotDaemonState = transition (snapshotDaemonState snapshot)}
     in (next, next)

readDaemonControl :: DaemonControl -> IO DaemonControlSnapshot
readDaemonControl =
  readIORef . daemonControlSnapshotRef

snapshotReady :: DaemonControlSnapshot -> Bool
snapshotReady =
  daemonStateReady . snapshotDaemonState

snapshotDraining :: DaemonControlSnapshot -> Bool
snapshotDraining =
  daemonStateDraining . snapshotDaemonState

snapshotLiveConfig :: DaemonControlSnapshot -> LiveConfig
snapshotLiveConfig =
  snapshotConfig . snapshotLiveConfigState

snapshotReloadGeneration :: DaemonControlSnapshot -> Int
snapshotReloadGeneration =
  snapshotGeneration . snapshotLiveConfigState

daemonSignalAction :: DaemonSignal -> DaemonSignalAction
daemonSignalAction DaemonSighup = ReloadLiveConfig
daemonSignalAction DaemonSigint = BeginGracefulDrain
daemonSignalAction DaemonSigterm = BeginGracefulDrain

signalPlan :: [(DaemonSignal, DaemonSignalAction)]
signalPlan =
  [ (DaemonSighup, ReloadLiveConfig)
  , (DaemonSigint, BeginGracefulDrain)
  , (DaemonSigterm, BeginGracefulDrain)
  ]

renderDaemonSignal :: DaemonSignal -> Text
renderDaemonSignal DaemonSighup = "SIGHUP"
renderDaemonSignal DaemonSigint = "SIGINT"
renderDaemonSignal DaemonSigterm = "SIGTERM"

renderDaemonSignalAction :: DaemonSignalAction -> Text
renderDaemonSignalAction ReloadLiveConfig = "reload-live-config"
renderDaemonSignalAction BeginGracefulDrain = "begin-graceful-drain"

withDaemonSignalHandlers :: (DaemonSignal -> IO ()) -> IO a -> IO a
withDaemonSignalHandlers callback action =
  bracket install restore (const action)
 where
  install =
    traverse
      ( \(posixSignal, daemonSignal) -> do
          previous <- installHandler posixSignal (Catch (callback daemonSignal)) Nothing
          pure (posixSignal, previous)
      )
      signalHandlers

  restore =
    traverse_ (\(posixSignal, previous) -> installHandler posixSignal previous Nothing)

signalHandlers :: [(Signal, DaemonSignal)]
signalHandlers =
  [ (sigHUP, DaemonSighup)
  , (sigINT, DaemonSigint)
  , (sigTERM, DaemonSigterm)
  ]
