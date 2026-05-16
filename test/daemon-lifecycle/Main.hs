{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Data.ByteString.Char8 qualified as ByteString
import Data.List (isInfixOf)
import Network.Socket
  ( AddrInfo (..)
  , Socket
  , SocketType (Stream)
  , close
  , connect
  , defaultHints
  , getAddrInfo
  , socket
  , withSocketsDo
  )
import Network.Socket.ByteString (recv, sendAll)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.AppError.AppError (AppError (..))
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Consumer (eventIdFromPayload, processAtLeastOnce)
import JitML.Service.Endpoints (MetricsSnapshot (..), endpointStatus, healthz, metrics, readyz)
import JitML.Service.Http (withHttpRoutesOnce)
import JitML.Service.Lifecycle (LifecyclePhase (..), lifecyclePlan)
import JitML.Service.Retry (RetryPolicy (..), ServiceError (..), retryServiceAction)
import JitML.Service.Runtime
  ( DaemonRuntime (daemonReady)
  , daemonHttpRoutes
  , defaultDaemonRuntime
  , runtimeAfterSignal
  )
import JitML.Service.Signal
  ( DaemonControlSnapshot (..)
  , DaemonSignal (..)
  , DaemonSignalAction (..)
  , applyDaemonSignal
  , daemonSignalAction
  , newDaemonControl
  , renderDaemonSignalAction
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-daemon-lifecycle"
      [ testCase "lifecycle order reaches ready before serve" $
          lifecyclePlan @?= [Load, Prereq, Acquire, Ready, Serve, Drain, Exit]
      , testCase "endpoint status codes follow readiness" $ do
          endpointStatus healthz @?= 200
          endpointStatus (readyz False) @?= 503
          endpointStatus (readyz True) @?= 200
          endpointStatus (metrics (MetricsSnapshot 0 1 0)) @?= 200
      , testCase "daemon signals map to reload and graceful drain" $ do
          daemonSignalAction DaemonSighup @?= ReloadLiveConfig
          daemonSignalAction DaemonSigterm @?= BeginGracefulDrain
          renderDaemonSignalAction BeginGracefulDrain @?= "begin-graceful-drain"
          let drainingRuntime = runtimeAfterSignal defaultDaemonRuntime DaemonSigterm
          endpointStatus (readyz True) @?= 200
          endpointStatus (readyz (daemonReady drainingRuntime)) @?= 503
      , testCase "daemon control records reload generation and drain readiness" $ do
          control <- newDaemonControl True
          reloaded <- applyDaemonSignal control DaemonSighup
          reloaded @?= DaemonControlSnapshot True False 1
          drained <- applyDaemonSignal control DaemonSigint
          drained @?= DaemonControlSnapshot False True 1
      , testCase "retry policy retries transient errors" $ do
          result <-
            retryServiceAction (LinearN 2 0) (\() -> pure (Left (SETimeout "timeout"))) ()
              :: IO (Either AppError ())
          result @?= Left (PulsarFailed "timeout: timeout")
      , testCase "message hash dedup collapses repeated messages" $ do
          let first = eventIdFromPayload (ByteString.pack "payload")
              second = eventIdFromPayload (ByteString.pack "payload")
          first @?= second
          assertBool "one side effect" (length (processAtLeastOnce [first, second]) == 1)
      , testCase "one-shot daemon HTTP server exposes healthz" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (daemonHttpRoutes defaultDaemonRuntime) $ \port -> do
            response <- httpGet port "/healthz"
            assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
            assertBool "health body" ("\r\n\r\nok\n" `isInfixOf` response)
      ]

httpGet :: Int -> String -> IO String
httpGet port path =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> ioError (userError "no address for daemon test client")
      addr : _ ->
        bracket (openSocket addr) close $ \client -> do
          sendAll client (ByteString.pack ("GET " <> path <> " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"))
          ByteString.unpack <$> recv client 4096

openSocket :: AddrInfo -> IO Socket
openSocket addr = do
  client <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect client (addrAddress addr)
  pure client
