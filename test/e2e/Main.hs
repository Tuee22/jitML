{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (bracket)
import Data.ByteString.Char8 qualified as ByteString
import Data.Foldable (traverse_)
import Data.List (isInfixOf)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
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
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.Publication (defaultPublication, publicationEdgePort)
import JitML.Routes (routeRegistry, routeServiceName)
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Http (withHttpRoutesOnce)
import JitML.Storage.Buckets (bucketNames)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.LiveGate (LiveGate (..), liveGateEnvVar, liveGateFromEnv, renderLiveGate)
import JitML.Test.LivePlan (liveE2EPlan, renderLivePlan)
import JitML.Test.Report
  ( ReportCard (..)
  , knobRlSteps
  , renderReportCard
  , reportCardKnobsFromEnv
  , reportStanzas
  )
import JitML.Web.Bundle (demoRoutePath, demoRoutes)
import JitML.Web.Contracts (apiEndpoints)
import JitML.Web.Server (demoHttpRoutes)

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-e2e"
      [ testCase "edge route registry includes demo and platform services" $ do
          let services = fmap routeServiceName routeRegistry
          assertBool "demo route present" ("jitml-demo" `elem` services)
          assertBool "grafana route present" ("grafana" `elem` services)
          assertBool "pulsar route present" ("jitml-pulsar-proxy" `elem` services)
      , testCase "bucket registry includes checkpoint and tuning buckets" $ do
          assertBool "checkpoints bucket" ("jitml-checkpoints" `elem` bucketNames)
          assertBool "trials bucket" ("jitml-trials" `elem` bucketNames)
      , testCase "chart values include every typed MinIO bucket" $ do
          values <- Text.IO.readFile "chart/values.yaml"
          traverse_
            ( \bucket ->
                assertBool
                  ("missing chart bucket: " <> Text.unpack bucket)
                  (("- name: " <> bucket) `Text.isInfixOf` values)
            )
            bucketNames
      , testCase "publication leases stable per-substrate edge ports" $
          publicationEdgePort (defaultPublication LinuxCUDA) @?= 9092
      , testCase "browser contracts expose interactive surfaces" $
          length apiEndpoints @?= 7
      , testCase "demo route manifest covers edge listener paths" $
          fmap demoRoutePath demoRoutes @?= ["/", "/api", "/api/ws"]
      , testCase "demo deployment starts the jitml-demo HTTP server" $ do
          deployment <- Text.IO.readFile "chart/templates/deployment-jitml-demo.yaml"
          assertBool "jitml-demo command" ("command: [\"jitml-demo\"]" `Text.isInfixOf` deployment)
          assertBool "container port env" ("value: \"80\"" `Text.isInfixOf` deployment)
      , testCase "report card renders aggregate suite summary" $ do
          length reportStanzas @?= 10
          let rendered = renderReportCard (ReportCard 10 0 0)
          assertBool "report card title" ("jitML POC report card" `isInfixOf` Text.unpack rendered)
          assertBool "report card passed count" ("passed: 10" `isInfixOf` Text.unpack rendered)
      , testCase "report card consumes workload knob overrides" $
          knobRlSteps (reportCardKnobsFromEnv [("RL_STEPS", "12")]) @?= 12
      , testCase "live Kind/Helm validation is explicit opt-in" $ do
          liveGateFromEnv [] @?= LiveDisabled
          liveGateFromEnv [(liveGateEnvVar, "1")] @?= LiveEnabled
          renderLiveGate LiveDisabled
            @?= "live e2e: disabled; set JITML_LIVE_E2E=1 to run live Kind/Helm validation"
          assertBool "live plan starts with helm dependency build" $
            "helm-dependency-build: helm dependency build chart" `Text.isInfixOf` renderLivePlan liveE2EPlan
          assertBool "live plan includes Playwright" $
            "playwright: npx playwright test" `Text.isInfixOf` renderLivePlan liveE2EPlan
      , testCase "one-shot demo HTTP server serves the API index" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
            response <- httpGet port "/api"
            assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
            assertBool "InferenceRun in API index" ("InferenceRun" `isInfixOf` response)
      , testCase "npx playwright test runs through typed Subprocess (JITML_LIVE_E2E=1)" $ do
          liveGate <- lookupEnv "JITML_LIVE_E2E"
          case liveGate of
            Just enabled
              | Text.toLower (Text.pack enabled) `elem` ["1", "true", "yes", "on"] -> do
                  -- Live path: invokes `npx playwright test` against the
                  -- canonical panel matrix through the typed Subprocess
                  -- boundary. Requires Chromium installed (`npx playwright
                  -- install chromium`) and node_modules at the repo root.
                  let cmd = subprocess "npx" ["playwright", "test", "--reporter=line"]
                  (exitCode, stdoutText, _stderr) <-
                    runStreaming defaultSubprocessEnv cmd
                  assertBool
                    "npx playwright test exits zero"
                    (case exitCode of ExitSuccess -> True; _ -> False)
                  assertBool
                    "Playwright reports 7 passed tests"
                    ("7 passed" `Text.isInfixOf` stdoutText)
            _ -> pure () -- default path: skip when not gated
      , testCase "post-teardown leaves no jitml-e2e Kind clusters" $ do
          -- Asserts the deterministic-teardown property from Sprint 12.8
          -- post-teardown. After all live work completes, `kind get
          -- clusters` MUST NOT name any `jitml-e2e-*` cluster. The host
          -- might have other Kind clusters (`jitml-linux-cpu`, etc.); we
          -- only assert the absence of `jitml-e2e-`-prefixed ones.
          (exitCode, stdoutText, _stderr) <-
            runStreaming defaultSubprocessEnv (subprocess "kind" ["get", "clusters"])
          assertBool
            "kind get clusters exits zero"
            (case exitCode of ExitSuccess -> True; _ -> False)
          assertBool
            "no jitml-e2e-* clusters survive"
            (not ("jitml-e2e-" `Text.isInfixOf` stdoutText))
      ]

httpGet :: Int -> String -> IO String
httpGet port path =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> ioError (userError "no address for demo test client")
      addr : _ ->
        bracket (openSocket addr) close $ \client -> do
          sendAll client (ByteString.pack ("GET " <> path <> " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"))
          ByteString.unpack <$> recv client 4096

openSocket :: AddrInfo -> IO Socket
openSocket addr = do
  client <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect client (addrAddress addr)
  pure client
