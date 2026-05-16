{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Signal
  ( DaemonControl
  , DaemonControlSnapshot (..)
  , DaemonSignal (..)
  , DaemonSignalAction (..)
  , applyDaemonSignal
  , daemonSignalAction
  , newDaemonControl
  , readDaemonControl
  , renderDaemonSignal
  , renderDaemonSignalAction
  , signalPlan
  , withDaemonSignalHandlers
  )
where

import Control.Exception (bracket)
import Data.Foldable (traverse_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.Text (Text)
import System.Posix.Signals
  ( Handler (Catch)
  , Signal
  , installHandler
  , sigHUP
  , sigINT
  , sigTERM
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

data DaemonControl = DaemonControl
  { controlReady :: IORef Bool
  , controlDraining :: IORef Bool
  , controlReloadGeneration :: IORef Int
  }

data DaemonControlSnapshot = DaemonControlSnapshot
  { snapshotReady :: Bool
  , snapshotDraining :: Bool
  , snapshotReloadGeneration :: Int
  }
  deriving stock (Eq, Show)

newDaemonControl :: Bool -> IO DaemonControl
newDaemonControl ready = do
  readyRef <- newIORef ready
  drainingRef <- newIORef False
  reloadRef <- newIORef 0
  pure
    DaemonControl
      { controlReady = readyRef
      , controlDraining = drainingRef
      , controlReloadGeneration = reloadRef
      }

applyDaemonSignal :: DaemonControl -> DaemonSignal -> IO DaemonControlSnapshot
applyDaemonSignal control signal = do
  case daemonSignalAction signal of
    ReloadLiveConfig ->
      atomicModifyIORef' (controlReloadGeneration control) $ \generation ->
        (generation + 1, ())
    BeginGracefulDrain -> do
      writeIORef (controlReady control) False
      writeIORef (controlDraining control) True
  readDaemonControl control

readDaemonControl :: DaemonControl -> IO DaemonControlSnapshot
readDaemonControl control =
  DaemonControlSnapshot
    <$> readIORef (controlReady control)
    <*> readIORef (controlDraining control)
    <*> readIORef (controlReloadGeneration control)

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
