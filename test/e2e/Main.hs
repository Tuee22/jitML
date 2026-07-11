{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (bracket, finally)
import Data.ByteString.Char8 qualified as ByteString
import Data.Foldable (traverse_)
import Data.List (isInfixOf)
import Data.Text (Text)
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
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.Timeout (timeout)
import Test.Tasty (defaultMain, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))

import JitML.Cluster.Publication (defaultPublication, publicationEdgePort)
import JitML.Product.Matrix qualified as ProductMatrix
import JitML.Routes (routeRegistry, routeServiceName)
import JitML.Service.BootConfig (HttpListener (..))
import JitML.Service.Endpoints (EndpointResponse (..))
import JitML.Service.Http
  ( HttpRoute (..)
  , WebSocketRoute (..)
  , withHttpRoutesOnce
  , withHttpRoutesWithWebSockets
  )
import JitML.Storage.Buckets (bucketNames)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (subprocess)
import JitML.Substrate (Substrate (..), allSubstrates)
import JitML.Test.LivePlan (liveE2EPlan, liveE2EPlanFor, renderLivePlan)
import JitML.Test.Report
  ( ProductRowReportEvidence (..)
  , ReportCard (..)
  , ReportMeasurement (..)
  , ReportMeasurements (..)
  , aggregateProductLaneAttestations
  , defaultReportCardKnobs
  , emptyReportMeasurements
  , loadAggregatedProductLaneAttestations
  , parseReportCardKnobs
  , productLaneAttestationFailures
  , productRowReportCoverageFailures
  , renderProductRowReportEvidence
  , renderReportCard
  , reportStanzas
  )
import JitML.Test.WorkflowMatrix qualified as WorkflowMatrix
import JitML.Web.Bundle (demoRoutePath, demoRoutes)
import JitML.Web.Contracts (apiEndpoints)
import JitML.Web.Server
  ( BrowserRuntimeRequest (..)
  , BrowserRuntimeResult (..)
  , BrowserRuntimeSurface (..)
  , bundleEntryPath
  , demoHttpRoutes
  , demoHttpRoutesWithBundle
  , demoHttpRoutesWithRuntime
  , loadBundleEntry
  )

main :: IO ()
main =
  defaultMain $
    testGroup
      "jitml-e2e"
      [ testCase "workflow matrix covers every reopened workflow on every substrate (Sprint 12.11)" $ do
          -- The DRY WorkflowMatrix is the single enumeration the integration /
          -- e2e Live tests iterate; here we assert it covers every reopened real
          -- workflow on every substrate and that each cell carries a canonical
          -- command. The fail-closed live execution of each cell is owned by
          -- Phases 13/14/15 (needs a live cluster + per-substrate hardware).
          let cells = WorkflowMatrix.workflowMatrix
          length cells @?= length WorkflowMatrix.allWorkflows * length allSubstrates
          assertBool
            "every workflow × substrate cell is present"
            ( and
                [ any
                    ( \c ->
                        WorkflowMatrix.cellWorkflow c == w && WorkflowMatrix.cellSubstrate c == s
                    )
                    cells
                | w <- WorkflowMatrix.allWorkflows
                , s <- allSubstrates
                ]
            )
          assertBool
            "every cell carries a canonical jitml command"
            (not (any (null . WorkflowMatrix.cellCommand) cells))
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.SlTrain AppleSilicon
            @?= WorkflowMatrix.WorkflowHostCommandExpected
              "persistent://public/default/training.host-command.apple-silicon"
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.RlTrain AppleSilicon
            @?= WorkflowMatrix.WorkflowHostCommandExpected
              "persistent://public/default/rl.host-command.apple-silicon"
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.Tune AppleSilicon
            @?= WorkflowMatrix.WorkflowHostCommandExpected
              "persistent://public/default/tune.host-command.apple-silicon"
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.SlTrain LinuxCPU
            @?= WorkflowMatrix.WorkflowClusterJobExpected
          WorkflowMatrix.workflowPlacementExpectation WorkflowMatrix.RlTrain LinuxCUDA
            @?= WorkflowMatrix.WorkflowClusterJobExpected
      , testCase
          "browser product matrix enumerates every no-caveat interaction on every substrate (Sprint 12.13)"
          $ do
            let cells = WorkflowMatrix.browserProductMatrix
            length cells
              @?= length WorkflowMatrix.allBrowserProductInteractions
              * length allSubstrates
            assertBool
              "every browser/product interaction x substrate cell is present"
              ( and
                  [ (interaction, substrate) `elem` cells
                  | interaction <- WorkflowMatrix.allBrowserProductInteractions
                  , substrate <- allSubstrates
                  ]
              )
            assertBool
              "every browser/product interaction carries a non-empty label"
              ( not
                  ( any
                      (Text.null . WorkflowMatrix.browserProductInteractionLabel)
                      WorkflowMatrix.allBrowserProductInteractions
                  )
              )
            length WorkflowMatrix.browserAdversarialGames @?= 4
      , testCase "edge route registry includes demo and platform services" $ do
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
          -- Sprint 14.1 — +3 endpoints: checkpoint browse (`/api/checkpoints`),
          -- the workflow-status stream (`/api/ws/workflow`), and transcript
          -- replay (`/api/transcripts/replay`).
          length apiEndpoints @?= 14
      , testCase "demo route manifest covers edge listener paths" $
          fmap demoRoutePath demoRoutes
            @?= [ "/"
                , "/api"
                , "/api/runs/{runId}/command"
                , "/api/inference"
                , "/api/inference/generic"
                , "/api/images"
                , "/api/checkpoints/compare"
                , "/api/connect4/move"
                , "/api/ws"
                , "/api/ws/training"
                , "/api/ws/rl"
                , "/api/ws/tune"
                , "/api/ws/inference"
                ]
      , testCase "demo HTTP routes cover generated stream endpoints" $
          fmap httpRoutePath demoHttpRoutes
            @?= [ "/"
                , "/api"
                , "/api/runs/{runId}/command"
                , "/api/inference"
                , "/api/inference/generic"
                , "/api/images"
                , "/api/checkpoints/compare"
                , "/api/connect4/move"
                , -- Sprint 14.1 — checkpoint browse + transcript replay POST surfaces.
                  "/api/checkpoints"
                , "/api/transcripts/replay"
                , "/api/ws"
                , "/api/ws/training"
                , "/api/ws/rl"
                , "/api/ws/tune"
                , "/api/ws/inference"
                , -- Sprint 14.1 — workflow-status stream upgrade surface.
                  "/api/ws/workflow"
                ]
      , testCase "gateway class attaches the local EnvoyProxy service shape" $ do
          gatewayClass <- Text.IO.readFile "chart/templates/gatewayclass-jitml.yaml"
          assertBool "EnvoyProxy parametersRef kind" ("kind: EnvoyProxy" `Text.isInfixOf` gatewayClass)
          assertBool "EnvoyProxy parametersRef name" ("name: jitml-edge" `Text.isInfixOf` gatewayClass)
          assertBool
            "EnvoyProxy parametersRef namespace"
            ("namespace: platform" `Text.isInfixOf` gatewayClass)
      , testCase "demo deployment starts the Webapp role through jitml service" $ do
          deployment <- Text.IO.readFile "chart/local/jitml-demo/templates/deployment.yaml"
          assertBool
            "webapp service command"
            ( "command: [\"jitml\", \"service\", \"--config\", \"/etc/jitml/BootConfig.dhall\"]"
                `Text.isInfixOf` deployment
            )
          assertBool
            "uses typed webapp config"
            ("mountPath: /etc/jitml" `Text.isInfixOf` deployment)
      , testCase "service deployment starts the jitml daemon binary" $ do
          deployment <- Text.IO.readFile "chart/templates/deployment-jitml-service.yaml"
          assertBool "jitml command" ("command: [\"jitml\"]" `Text.isInfixOf` deployment)
          assertBool
            "explicit service config arg"
            ("args: [\"service\", \"--config\", \"/etc/jitml/BootConfig.dhall\"]" `Text.isInfixOf` deployment)
      , testCase "report card renders aggregate suite summary" $ do
          let passed = length reportStanzas
              rendered = renderReportCard (ReportCard passed 0 0 emptyReportMeasurements)
          assertBool "report card title" ("jitML POC report card" `isInfixOf` Text.unpack rendered)
          assertBool "report card passed count" (("passed: " <> show passed) `isInfixOf` Text.unpack rendered)
          assertBool "report card default knobs" ("rl_steps: 100000" `isInfixOf` Text.unpack rendered)
          assertBool "report card lists actual stanzas" ("jitml-unit: PASS" `isInfixOf` Text.unpack rendered)
          assertBool
            "report card lists e2e stanza"
            ("jitml-e2e: PASS" `isInfixOf` Text.unpack rendered)
      , testCase "live report card renders measured values and unavailable sources (Sprint 15.2)" $ do
          let measurements =
                emptyReportMeasurements
                  { measuredSlFinalLoss = Just (MeasurementAvailable "mnist-shallow-mlp=0.125")
                  , measuredDaemonHealthz = Just MeasurementUnavailable
                  , measuredBrowserProductMatrix = Just MeasurementUnavailable
                  }
              rendered = renderReportCard (ReportCard (length reportStanzas) 0 0 measurements)
          assertBool "measurements block" ("measurements:" `isInfixOf` Text.unpack rendered)
          assertBool
            "available measurement"
            ("sl_final_loss: mnist-shallow-mlp=0.125" `isInfixOf` Text.unpack rendered)
          assertBool
            "unavailable measurement"
            ("daemon_healthz: unavailable" `isInfixOf` Text.unpack rendered)
          assertBool
            "no-caveat browser product matrix row"
            ("browser_product_matrix: unavailable" `isInfixOf` Text.unpack rendered)
      , testCase "linux-cpu report card renders per-row evidence and rejects missing cells (Sprint 28.3)" $ do
          let rows = ProductMatrix.allProductRows
              nonProducts = ProductMatrix.nonProductRows
              evidence = fmap completeProductRowReportEvidence rows
              rendered = renderProductRowReportEvidence rows nonProducts evidence
          assertBool
            "row report header"
            ("row_id\tCatalog\tIntegration\tE2E\tNegative\tDeviceEvidence\tLane" `Text.isInfixOf` rendered)
          assertBool
            "row report includes ProductRow"
            ("mnist-shallow-mlp\tgenerated-matrix" `Text.isInfixOf` rendered)
          assertBool
            "row report includes non-product classification"
            ("tic-tac-toe\tnon-product:" `Text.isInfixOf` rendered)
          productRowReportCoverageFailures rows nonProducts evidence @?= []
          case (rows, evidence) of
            ([], _) -> assertFailure "ProductRow registry is unexpectedly empty"
            (_, []) -> assertFailure "ProductRow report evidence is unexpectedly empty"
            (firstRow : _, first : rest) -> do
              let missingRowFailures = productRowReportCoverageFailures rows nonProducts rest
              assertBool
                "missing product row is named"
                ( ("missing product-row report evidence row: rowId=" <> ProductMatrix.rowId firstRow)
                    `elem` missingRowFailures
                )
              let missingCell = first {prreE2E = ""}
                  missingCellFailures = productRowReportCoverageFailures rows nonProducts (missingCell : rest)
              assertBool
                "missing E2E cell is named"
                ( ("missing report evidence cell: rowId=" <> prreRowId first <> " column=E2E")
                    `elem` missingCellFailures
                )
              let nonProductEvidence =
                    ProductRowReportEvidence
                      { prreRowId = "tic-tac-toe"
                      , prreCatalog = "generated-matrix"
                      , prreIntegration = "integration"
                      , prreE2E = "e2e"
                      , prreNegative = "fail-closed"
                      , prreDeviceEvidence = "device:linux-cpu:oneDNN"
                      , prreLane = "linux-cpu"
                      }
                  nonProductFailures = productRowReportCoverageFailures rows nonProducts (evidence <> [nonProductEvidence])
              assertBool
                "non-product row is not silently counted as complete"
                ( any
                    ("non-product row supplied as product evidence: rowId=tic-tac-toe" `Text.isPrefixOf`)
                    nonProductFailures
                )
      , testCase "product-lane attestation aggregation requires every row on every lane (Phase 31.1)" $ do
          let rows = ProductMatrix.allProductRows
              nonProducts = ProductMatrix.nonProductRows
              lanes = ["linux-cpu", "linux-cuda", "apple-silicon"]
              evidenceFor lane =
                fmap
                  ( \row ->
                      (completeProductRowReportEvidence row)
                        { prreLane = lane
                        , prreDeviceEvidence =
                            "device:" <> lane <> ":fixed-bridge-or-runtime:update-critical"
                        }
                  )
                  rows
              allEvidence = concatMap evidenceFor lanes
              failures = productLaneAttestationFailures lanes rows nonProducts allEvidence
          failures @?= []
          case rows of
            [] -> assertFailure "ProductRow registry is unexpectedly empty"
            firstRow : _ -> do
              let missingApple =
                    filter
                      ( \evidence ->
                          not
                            ( prreLane evidence == "apple-silicon"
                                && prreRowId evidence == ProductMatrix.rowId firstRow
                            )
                      )
                      allEvidence
                  missingFailures =
                    productLaneAttestationFailures lanes rows nonProducts missingApple
              assertBool
                "missing Apple row is named"
                ( ("missing product-lane evidence row: lane=apple-silicon rowId=" <> ProductMatrix.rowId firstRow)
                    `elem` missingFailures
                )
              let renderedInputs =
                    [ (lane, renderProductRowReportEvidence rows nonProducts (evidenceFor lane))
                    | lane <- lanes
                    ]
              case aggregateProductLaneAttestations renderedInputs of
                Left err -> assertFailure (Text.unpack err)
                Right parsed -> length parsed @?= length allEvidence
      , testCase "committed product-lane attestations aggregate without drift (Phase 31.1)" $ do
          aggregated <- loadAggregatedProductLaneAttestations
          case aggregated of
            Left err -> assertFailure (Text.unpack err)
            Right parsed ->
              length parsed
                @?= length ProductMatrix.allProductRows
                * length (["linux-cpu", "linux-cuda", "apple-silicon"] :: [Text])
      , testCase "cabal.project report-card knob block matches typed defaults (Sprint 12.9)" $ do
          cabalProject <- Text.IO.readFile "cabal.project"
          parseReportCardKnobs cabalProject @?= Right defaultReportCardKnobs
      , testCase "live Kind/Helm validation is an explicit typed plan" $ do
          let livePlanText = renderLivePlan liveE2EPlan
          assertBool "live plan starts with helm dependency build" $
            "helm-dependency-build:" `Text.isInfixOf` livePlanText
          assertBool "live plan invokes helm dependency build" $
            "helm dependency build chart" `Text.isInfixOf` livePlanText
          assertBool "live plan includes pinned Playwright image" $
            "playwright: docker run --rm --network host -v .:/work:ro -w /work -e JITML_SUBSTRATE=linux-cpu -e PLAYWRIGHT_TEST_RESULTS_DIR=/tmp/jitml-playwright-test-results mcr.microsoft.com/playwright:v1.49.1-noble"
              `Text.isInfixOf` livePlanText
          assertBool "live plan installs the pinned test package in the browser container" $
            "@playwright/test@1.49.1" `Text.isInfixOf` livePlanText
          assertBool "live plan points at the repo Playwright config" $
            "playwright/playwright.config.ts" `Text.isInfixOf` livePlanText
          assertBool "live plan is substrate parametrized" $
            "jitml bootstrap --linux-cuda" `Text.isInfixOf` renderLivePlan (liveE2EPlanFor LinuxCUDA)
      , testCase "one-shot demo HTTP server serves the API index" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
            response <- httpGet port "/api"
            assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
            assertBool "InferenceRun in API index" ("InferenceRun" `isInfixOf` response)
      , testCase "plain demo stream HTTP route requires WebSocket upgrade (Sprint 15.3)" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
            response <- httpGet port "/api/ws"
            assertBool "HTTP 503" ("HTTP/1.1 503 Service Unavailable" `isInfixOf` response)
            assertBool "upgrade required" ("live stream requires WebSocket upgrade" `isInfixOf` response)
      , testCase "open WebSocket bridge does not block HTTP routes (Sprint 15.3)" $ do
          release <- newEmptyMVar
          let routes =
                [ HttpRoute
                    { httpRouteMethod = "GET"
                    , httpRoutePath = "/fast"
                    , httpRouteContentType = "text/plain; charset=utf-8"
                    , httpRouteHandler = \_request -> pure (EndpointResponse 200 "fast\n")
                    }
                ]
              wsRoutes =
                [ WebSocketRoute
                    { webSocketRoutePath = "/api/ws"
                    , webSocketRouteHandler = \writeFrame -> do
                        _ <- writeFrame "event: open\n\n"
                        takeMVar release
                    }
                ]
          withHttpRoutesWithWebSockets (HttpListener "127.0.0.1" 0) routes wsRoutes $ \port ->
            bracket (openWebSocketClient port "/api/ws") close $ \client ->
              ( do
                  handshake <- timeout 2000000 (ByteString.unpack <$> recv client 4096)
                  case handshake of
                    Nothing -> assertFailure "timed out waiting for WebSocket upgrade"
                    Just response ->
                      assertBool "WebSocket 101" ("HTTP/1.1 101 Switching Protocols" `isInfixOf` response)
                  httpResponse <- timeout 2000000 (httpGet port "/fast")
                  case httpResponse of
                    Nothing -> assertFailure "HTTP route blocked behind an open WebSocket bridge"
                    Just response -> do
                      assertBool "HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` response)
                      assertBool "HTTP body" ("fast" `isInfixOf` response)
              )
                `finally` putMVar release ()
      , testCase "demo server serves the compiled Halogen bundle when present (Sprint 11.5)" $ do
          -- Read the browser-loadable bundle entry; if the Docker/web
          -- build has produced it, the demo routes include the
          -- /bundle/main.js route serving the JS bytes.
          bundle <- loadBundleEntry
          let routes = demoHttpRoutesWithBundle bundle
          case bundle of
            Just _ -> do
              assertBool
                "demo route table includes /bundle/main.js when bundle present"
                (length routes > length demoHttpRoutes)
              assertBool
                "bundle entry path is the canonical browser-loadable Halogen bundle"
                ("web/dist/Main/bundle.js" `isInfixOf` bundleEntryPath)
            Nothing ->
              assertBool
                "demo route table omits /bundle/main.js when bundle is missing"
                (length routes == length demoHttpRoutes)
      , testCase "demo command route requires live publication and reads POST bodies (Sprint 11.9)" $
          withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
            response <-
              httpPost
                port
                "/api/runs/training-demo/command"
                "kind: StopTraining\nexperiment-hash: training-demo\ndrain: True\n"
            assertBool "HTTP 503" ("HTTP/1.1 503 Service Unavailable" `isInfixOf` response)
            assertBool "live publication required" ("cluster publication required" `isInfixOf` response)
      , testCase
          "demo REST routes parse browser envelopes and call checkpoint runtime handler (Sprint 11.9)"
          $ do
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (demoHttpRoutesWithRuntime fakeBrowserRuntime) $ \port -> do
              inference <- httpPost port "/api/inference" productInferenceBody
              assertBool "inference HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` inference)
              assertBool "typed inference result" ("kind: InferenceResult" `isInfixOf` inference)
              assertBool "checkpoint sha" ("checkpoint-sha: sha256:browser-runtime" `isInfixOf` inference)
              assertBool "top class from runtime output" ("top-class: 1" `isInfixOf` inference)
              fieldItemCount "probabilities" inference @?= 10
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (demoHttpRoutesWithRuntime fakeBrowserRuntime) $ \port -> do
              generic <- httpPost port "/api/inference/generic" productGenericBody
              assertBool "generic HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` generic)
              assertBool "typed generic result" ("kind: GenericInferenceResult" `isInfixOf` generic)
              assertBool
                "generic checkpoint sha"
                ("checkpoint-sha: sha256:product-row-california-housing-mlp" `isInfixOf` generic)
              fieldItemCount "output" generic @?= 3
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (demoHttpRoutesWithRuntime fakeBrowserRuntime) $ \port -> do
              image <- httpPost port "/api/images" productImageBody
              assertBool "image HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` image)
              assertBool "typed image result" ("kind: ImageInferenceResult" `isInfixOf` image)
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (demoHttpRoutesWithRuntime fakeBrowserRuntime) $ \port -> do
              compareResp <- httpPost port "/api/checkpoints/compare" productCompareBody
              assertBool "compare HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` compareResp)
              assertBool "typed compare result" ("kind: CheckpointCompareResult" `isInfixOf` compareResp)
              assertBool "compare max delta" ("max-abs-delta: 0.5" `isInfixOf` compareResp)
              fieldItemCount "baseline-output" compareResp @?= 3
              fieldItemCount "candidate-output" compareResp @?= 3
              assertBool "compare mean delta" ("mean-abs-delta: 0.16666666666666666" `isInfixOf` compareResp)
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) (demoHttpRoutesWithRuntime fakeBrowserRuntime) $ \port -> do
              move <- httpPost port "/api/connect4/move" productConnect4Body
              assertBool "move HTTP 200" ("HTTP/1.1 200 OK" `isInfixOf` move)
              assertBool "typed move result" ("kind: AdversarialMoveResult" `isInfixOf` move)
      , testCase
          "demo product REST routes fail closed for missing or invalid product artifacts (Sprint 27.3)"
          $ do
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
              missingCluster <- httpPost port "/api/inference" productInferenceBody
              assertFailClosed "missing cluster" "checkpoint-backed runtime publication required" missingCluster
            withHttpRoutesOnce (HttpListener "127.0.0.1" 0) demoHttpRoutes $ \port -> do
              seededArtifact <- httpPost port "/api/inference" seededDemoArtifactBody
              assertFailClosed "seeded artifact" "seeded demo artifact rejected" seededArtifact
            traverse_
              ( \(label, reason) ->
                  withHttpRoutesOnce
                    (HttpListener "127.0.0.1" 0)
                    (demoHttpRoutesWithRuntime (failingBrowserRuntime reason))
                    $ \port -> do
                      response <- httpPost port "/api/inference" productInferenceBody
                      assertFailClosed label (Text.unpack reason) response
              )
              [ ("missing artifact", "pointer read failed: missing latest pointer")
              , ("untrained artifact", "manifest not inference eligible: completed training witness missing")
              , ("partial checkpoint", "manifest not inference eligible: partial checkpoint")
              , ("unsupported substrate", "unsupported substrate: apple-silicon")
              ]
      , testCase "post-teardown leaves no jitml-e2e Kind clusters" $ do
          -- Asserts the deterministic-teardown property from Sprint 12.8
          -- post-teardown. After all live work completes, `kind get
          -- clusters` MUST NOT name any `jitml-e2e-*` cluster. The host
          -- might have other Kind clusters (`jitml-linux-cpu`, etc.); we
          -- only assert the absence of `jitml-e2e-`-prefixed ones.
          kind <- findExecutable "kind"
          case kind of
            Nothing ->
              assertFailure "kind is absent; post-teardown no-leak check cannot run"
            Just _ -> do
              docker <- findExecutable "docker"
              case docker of
                Nothing ->
                  assertFailure "docker is absent; post-teardown no-leak check cannot run"
                Just _ -> do
                  (dockerExitCode, _dockerStdout, dockerStderr) <-
                    runStreaming defaultSubprocessEnv (subprocess "docker" ["info"])
                  case dockerExitCode of
                    ExitSuccess -> do
                      (exitCode, stdoutText, _stderr) <-
                        runStreaming defaultSubprocessEnv (subprocess "kind" ["get", "clusters"])
                      assertBool
                        "kind get clusters exits zero"
                        (case exitCode of ExitSuccess -> True; _ -> False)
                      assertBool
                        "no jitml-e2e-* clusters survive"
                        (not ("jitml-e2e-" `Text.isInfixOf` stdoutText))
                    _ ->
                      assertFailure
                        ( "Docker context is unavailable; post-teardown no-leak check cannot run: "
                            <> Text.unpack dockerStderr
                        )
      ]

productInferenceBody :: String
productInferenceBody =
  unlines
    [ "kind: BrowserInferenceRequest"
    , "panel: mnist-live-inference"
    , "model-id: mnist-deep-mlp"
    , "experiment-hash: product-row-mnist-deep-mlp"
    , "input: 1.0,2.0"
    ]

productGenericBody :: String
productGenericBody =
  unlines
    [ "kind: BrowserGenericInferenceRequest"
    , "panel: generic-inference-lab"
    , "experiment-hash: product-row-california-housing-mlp"
    , "input: 1.0,2.0"
    ]

productImageBody :: String
productImageBody =
  unlines
    [ "kind: BrowserImageRequest"
    , "panel: cifar-imagenet-upload"
    , "dataset: CIFAR-10"
    , "experiment-hash: product-row-cifar10-resnet20"
    , "image-base64: "
    , "input: 1.0,2.0"
    ]

productCompareBody :: String
productCompareBody =
  unlines
    [ "kind: BrowserCheckpointCompareRequest"
    , "panel: checkpoint-compare-lab"
    , "baseline-experiment-hash: product-row-mnist-shallow-mlp"
    , "candidate-experiment-hash: product-row-mnist-deep-mlp"
    , "input: 1.0,2.0"
    ]

productConnect4Body :: String
productConnect4Body =
  unlines
    [ "kind: BrowserAdversarialMoveRequest"
    , "panel: connect4-human-vs-alphazero"
    , "game: connect4"
    , "experiment-hash: product-row-connect4"
    , "moves: 3"
    , "human-is-player: 1"
    , "simulations-per-move: 3"
    ]

seededDemoArtifactBody :: String
seededDemoArtifactBody =
  unlines
    [ "kind: BrowserInferenceRequest"
    , "panel: mnist-live-inference"
    , "model-id: mnist-deep-mlp"
    , "experiment-hash: mnist-demo-weights"
    , "input: 1.0,2.0"
    ]

assertFailClosed :: String -> String -> String -> IO ()
assertFailClosed label reason response = do
  assertBool (label <> " HTTP 503") ("HTTP/1.1 503 Service Unavailable" `isInfixOf` response)
  assertBool (label <> " checkpoint required") ("checkpoint-required: inference" `isInfixOf` response)
  assertBool (label <> " reason") (reason `isInfixOf` response)
  assertBool
    (label <> " selector state")
    ("selector-state: fail-closed:no-inference-eligible-artifact" `isInfixOf` response)

fieldItemCount :: Text -> String -> Int
fieldItemCount key payload =
  let prefix = key <> ": "
   in case [ Text.drop (Text.length prefix) line
           | line <- Text.lines (Text.pack payload)
           , prefix `Text.isPrefixOf` line
           ] of
        [raw]
          | Text.null (Text.strip raw) -> 0
          | otherwise -> length (Text.splitOn "," raw)
        _ -> -1

completeProductRowReportEvidence
  :: ProductMatrix.ProductRow state
  -> ProductRowReportEvidence
completeProductRowReportEvidence row =
  ProductRowReportEvidence
    { prreRowId = ProductMatrix.rowId row
    , prreCatalog = "generated-matrix"
    , prreIntegration = ProductMatrix.integrationTest row
    , prreE2E = ProductMatrix.e2eTest row
    , prreNegative = "checkpoint-required-fail-closed"
    , prreDeviceEvidence = "device:linux-cpu:oneDNN:ffi:dispatch"
    , prreLane = "linux-cpu"
    }

failingBrowserRuntime :: Text -> BrowserRuntimeRequest -> IO (Either Text BrowserRuntimeResult)
failingBrowserRuntime reason _request =
  pure (Left reason)

fakeBrowserRuntime :: BrowserRuntimeRequest -> IO (Either Text BrowserRuntimeResult)
fakeBrowserRuntime request =
  pure $
    Right
      BrowserRuntimeResult
        { browserRuntimeCheckpointSha =
            case browserRuntimeSurface request of
              BrowserRuntimeGeneric ->
                "sha256:" <> browserRuntimeExperimentHash request
              _ ->
                "sha256:browser-runtime"
        , browserRuntimeOutput =
            case browserRuntimeSurface request of
              BrowserRuntimeInference -> [0.1, 1.1, 0.2]
              BrowserRuntimeGeneric -> genericOutput
              BrowserRuntimeCompare -> genericOutput
              BrowserRuntimeImage -> [0.1, 1.1, 0.2, 0.4, 0.3]
              BrowserRuntimeAdversarial -> [0.1, 0.2, 0.7, 0.3, 0.2, 0.1, 0.1, 0.5]
        }
 where
  genericOutput =
    if "product-row-mnist-deep-mlp" == browserRuntimeExperimentHash request
      then [0.75, 0.5]
      else [0.25, 0.5]

httpGet :: Int -> String -> IO String
httpGet port path =
  httpRequest port ("GET " <> path <> " HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")

httpPost :: Int -> String -> String -> IO String
httpPost port path body =
  httpRequest
    port
    ( "POST "
        <> path
        <> " HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: "
        <> show (length body)
        <> "\r\n\r\n"
        <> body
    )

httpRequest :: Int -> String -> IO String
httpRequest port request =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> ioError (userError "no address for demo test client")
      addr : _ ->
        bracket (openSocket addr) close $ \client -> do
          sendAll client (ByteString.pack request)
          ByteString.unpack <$> recv client 4096

openSocket :: AddrInfo -> IO Socket
openSocket addr = do
  client <- socket (addrFamily addr) (addrSocketType addr) (addrProtocol addr)
  connect client (addrAddress addr)
  pure client

openWebSocketClient :: Int -> String -> IO Socket
openWebSocketClient port path =
  withSocketsDo $ do
    addresses <-
      getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just "127.0.0.1") (Just (show port))
    case addresses of
      [] -> ioError (userError "no address for WebSocket test client")
      addr : _ -> do
        client <- openSocket addr
        sendAll
          client
          ( ByteString.pack
              ( "GET "
                  <> path
                  <> " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
              )
          )
        pure client
