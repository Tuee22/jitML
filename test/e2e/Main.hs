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
import System.Directory (doesPathExist, findExecutable)
import System.Exit (ExitCode (..))
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, testCase, (@?=))

import JitML.Cluster.Publication (defaultPublication, publicationEdgePort)
import JitML.Routes (routeRegistry, routeServiceName)
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Http (HttpRoute (..), withHttpRoutesOnce)
import JitML.Storage.Buckets (bucketNames)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..))
import JitML.Test.LivePlan (liveE2EPlan, renderLivePlan)
import JitML.Test.Report
  ( ReportCard (..)
  , defaultReportCardKnobs
  , parseReportCardKnobs
  , renderReportCard
  , reportStanzas
  )
import JitML.Web.Bundle (demoRoutePath, demoRoutes)
import JitML.Web.Contracts (apiEndpoints)
import JitML.Web.Server (bundleEntryPath, demoHttpRoutes, demoHttpRoutesWithBundle, loadBundleEntry)

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-e2e"
      [ testCase "edge route registry includes demo and platform services" $ do
          let services = fmap routeServiceName routeRegistry
          assertBool "demo route present" ("jitml-demo" `elem` services)
          assertBool "grafana route present" ("kube-prometheus-stack-grafana" `elem` services)
          assertBool "pulsar route present" ("pulsar-proxy" `elem` services)
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
          fmap demoRoutePath demoRoutes
            @?= [ "/"
                , "/api"
                , "/api/inference"
                , "/api/images"
                , "/api/connect4/move"
                , "/api/ws"
                , "/api/ws/training"
                , "/api/ws/tune"
                ]
      , testCase "demo HTTP routes cover generated stream endpoints" $
          fmap httpRoutePath demoHttpRoutes
            @?= [ "/"
                , "/api"
                , "/api/inference"
                , "/api/images"
                , "/api/connect4/move"
                , "/api/ws"
                , "/api/ws/training"
                , "/api/ws/tune"
                ]
      , testCase "gateway class attaches the local EnvoyProxy service shape" $ do
          gatewayClass <- Text.IO.readFile "chart/templates/gatewayclass-jitml.yaml"
          assertBool "EnvoyProxy parametersRef kind" ("kind: EnvoyProxy" `Text.isInfixOf` gatewayClass)
          assertBool "EnvoyProxy parametersRef name" ("name: jitml-edge" `Text.isInfixOf` gatewayClass)
          assertBool
            "EnvoyProxy parametersRef namespace"
            ("namespace: platform" `Text.isInfixOf` gatewayClass)
      , testCase "demo deployment starts the jitml-demo HTTP server" $ do
          deployment <- Text.IO.readFile "chart/templates/deployment-jitml-demo.yaml"
          assertBool "jitml-demo command" ("command: [\"jitml-demo\"]" `Text.isInfixOf` deployment)
          assertBool
            "explicit container listener args"
            ("args: [\"--host\", \"0.0.0.0\", \"--port\", \"80\"]" `Text.isInfixOf` deployment)
      , testCase "service deployment starts the jitml daemon binary" $ do
          deployment <- Text.IO.readFile "chart/templates/deployment-jitml-service.yaml"
          assertBool "jitml command" ("command: [\"jitml\"]" `Text.isInfixOf` deployment)
          assertBool
            "explicit service config arg"
            ("args: [\"service\", \"--config\", \"/etc/jitml/BootConfig.dhall\"]" `Text.isInfixOf` deployment)
      , testCase "report card renders aggregate suite summary" $ do
          length reportStanzas @?= 10
          let rendered = renderReportCard (ReportCard 10 0 0)
          assertBool "report card title" ("jitML POC report card" `isInfixOf` Text.unpack rendered)
          assertBool "report card passed count" ("passed: 10" `isInfixOf` Text.unpack rendered)
          assertBool "report card default knobs" ("rl_steps: 100000" `isInfixOf` Text.unpack rendered)
          assertBool "report card lists actual stanzas" ("jitml-unit: PASS" `isInfixOf` Text.unpack rendered)
          assertBool "report card lists style stanza" ("jitml-purescript-style: PASS" `isInfixOf` Text.unpack rendered)
      , testCase "cabal.project report-card knob block matches typed defaults (Sprint 12.9)" $ do
          cabalProject <- Text.IO.readFile "cabal.project"
          parseReportCardKnobs cabalProject @?= Right defaultReportCardKnobs
      , testCase "live Kind/Helm validation is an explicit typed plan" $ do
          assertBool "live plan starts with helm dependency build" $
            "helm-dependency-build:" `Text.isInfixOf` renderLivePlan liveE2EPlan
          assertBool "live plan invokes helm dependency build" $
            "helm dependency build chart" `Text.isInfixOf` renderLivePlan liveE2EPlan
          assertBool "live plan includes Playwright" $
            "playwright: npx playwright test" `Text.isInfixOf` renderLivePlan liveE2EPlan
      , testCase "one-shot demo HTTP server serves the API index" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
            response <- httpGet port "/api"
            assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
            assertBool "InferenceRun in API index" ("InferenceRun" `isInfixOf` response)
      , testCase "demo server serves the compiled Halogen bundle when present (Sprint 11.5)" $ do
          -- Read the bundle entry from web/dist/Main/index.js; if spago
          -- has built it, the demo routes include the /bundle/main.js
          -- route serving the JS bytes.
          bundle <- loadBundleEntry
          let routes = demoHttpRoutesWithBundle bundle
          case bundle of
            Just _ -> do
              assertBool
                "demo route table includes /bundle/main.js when bundle present"
                (length routes > length demoHttpRoutes)
              assertBool
                "bundle entry path is the canonical Halogen Main module"
                ("web/dist/Main/index.js" `isInfixOf` bundleEntryPath)
            Nothing ->
              assertBool
                "demo route table falls back to placeholder when bundle missing"
                (length routes == length demoHttpRoutes)
      , testCase "post-teardown leaves no jitml-e2e Kind clusters" $ do
          -- Asserts the deterministic-teardown property from Sprint 12.8
          -- post-teardown. After all live work completes, `kind get
          -- clusters` MUST NOT name any `jitml-e2e-*` cluster. The host
          -- might have other Kind clusters (`jitml-linux-cpu`, etc.); we
          -- only assert the absence of `jitml-e2e-`-prefixed ones.
          kind <- findExecutable "kind"
          case kind of
            Nothing ->
              assertBool "kind is absent; live no-leak check is skipped locally" True
            Just _ -> do
              hasDockerSocket <- doesPathExist "/var/run/docker.sock"
              if hasDockerSocket
                then do
                  (exitCode, stdoutText, _stderr) <-
                    runStreaming defaultSubprocessEnv (subprocess "kind" ["get", "clusters"])
                  assertBool
                    "kind get clusters exits zero"
                    (case exitCode of ExitSuccess -> True; _ -> False)
                  assertBool
                    "no jitml-e2e-* clusters survive"
                    (not ("jitml-e2e-" `Text.isInfixOf` stdoutText))
                else
                  assertBool "Docker socket is absent; live no-leak check is skipped locally" True
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
