{-# LANGUAGE OverloadedStrings #-}

module ClusterResourceRendering (clusterResourceRenderingTests) where

import Control.Concurrent (newEmptyMVar, putMVar, takeMVar, threadDelay, tryTakeMVar)
import Control.Concurrent.Async (async, cancel, link, waitCatch, withAsync)
import Control.Exception.Safe (bracket, finally)
import Control.Monad (forM_, forever, when)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.Either (isLeft)
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.List (isInfixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import GHC.Clock (getMonotonicTimeNSec)
import Network.Socket qualified as Socket
import Network.Socket.ByteString qualified as Socket.Bytes
import Numeric (showOct)
import System.Directory (getPermissions, setOwnerExecutable, setPermissions)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Timeout (timeout)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Text.Read (readMaybe)

import JitML.Bootstrap (livePhasedRolloutSubprocesses, topicConvergenceEvidenceWith)
import JitML.Cluster.Gateway (renderEnvoyProxy)
import JitML.Cluster.Helm
  ( HelmPhase (PlatformPhase)
  , HelmRelease (..)
  , helmInstallSubprocess
  , pulsarChartPreparationRequired
  )
import JitML.Cluster.Kind
  ( kindConfigFor
  , renderKindConfig
  , renderKindConfigWithResourcePolicy
  , rewriteKubeletResourceFlags
  )
import JitML.Cluster.PulsarBootstrap qualified as Pulsar
import JitML.Cluster.PulsarChart
  ( patchPulsarChartTar
  , patchPulsarStatefulInitTar
  , preparePulsarChartArchive
  , preparedPulsarChartPath
  )
import JitML.Cluster.ReconcileStamp
  ( EvidenceScope (TopicEvidence)
  , LivePublicationObservation (LivePublicationReady)
  , ReconcileDecision (NeedsReconcile)
  , ReconcileDriftReason (EvidenceMissing)
  , ReconcileEvidence (..)
  , ReconcileObservation (..)
  , classifyReconcileObservation
  , mkDesiredInputFingerprint
  , mkReconcileStamp
  )
import JitML.Cluster.Resources
  ( ClusterResources (..)
  , ComponentBudget (..)
  , defaultClusterResources
  )
import JitML.Service.ConfigMap
  ( renderClusterResourceValues
  , renderPlatformResourceDefaults
  , renderServiceDeployment
  , renderServiceValues
  )
import JitML.Sub.Outcome
  ( ObservedProcessFailure (..)
  , ObservedProcessOutcome (..)
  , ProcessDuration (..)
  , ProcessOutcome (..)
  , ProcessTranscript (..)
  , observedProcessFailureExitCode
  , processOutcome
  )
import JitML.Sub.Subprocess (Subprocess (..), subprocess)
import JitML.Substrate (Substrate (AppleSilicon, LinuxCPU), substrateClusterName)

clusterResourceRenderingTests :: TestTree
clusterResourceRenderingTests =
  testGroup
    "Cluster resource rendering"
    [ testCase "fresh local rollout caps both nodes immediately after creation" $
        forM_ [LinuxCPU, AppleSilicon] $ \substrate ->
          case livePhasedRolloutSubprocesses substrate "chart" of
            create : controlPlane : worker : _ -> do
              subprocessPath create @?= "kind"
              forM_
                [(controlPlane, "-control-plane"), (worker, "-worker")]
                $ \(cap, suffix) -> do
                  subprocessPath cap @?= "docker"
                  subprocessArguments cap
                    @?= [ "update"
                        , "--memory"
                        , "12884901888"
                        , "--memory-swap"
                        , "12884901888"
                        , "--cpus"
                        , "4"
                        , substrateClusterName substrate <> suffix
                        ]
            _ -> assertFailure "fresh rollout omitted creation or a node cap"
    , testCase "every live Helm release has a generated resource overlay" $ do
        let names = fmap fst (renderClusterResourceValues profile)
        sort names
          @?= sort
            ( fmap
                overlayPath
                [ "minio"
                , "registry"
                , "pulsar"
                , "kube-prometheus-stack"
                , "tensorboard"
                , "jitml-service"
                , "jitml-demo"
                , "envoy-gateway"
                ]
            )
    , testCase "Pulsar rollout uses the separately prepared pinned chart" $ do
        let selected =
              filter
                ( \step ->
                    subprocessPath step == "helm"
                      && take 3 (subprocessArguments step) == ["upgrade", "--install", "pulsar"]
                )
                (livePhasedRolloutSubprocesses LinuxCPU "chart")
        fmap (take 4 . subprocessArguments) selected
          @?= [["upgrade", "--install", "pulsar", Text.pack preparedPulsarChartPath]]
        fmap pulsarChartPreparationRequired selected @?= [Right True]
    , testCase "changed Pulsar dependency cannot reuse the older prepared chart" $ do
        let alternate =
              HelmRelease "pulsar" "pulsar" PlatformPhase (Just "pulsar-3.7.0.tgz") (Just "values/pulsar.yaml")
            command = helmInstallSubprocess alternate "chart"
        take 4 (subprocessArguments command)
          @?= ["upgrade", "--install", "pulsar", "chart/charts/pulsar-3.7.0.tgz"]
        pulsarChartPreparationRequired command
          @?= Left "Pulsar rollout requires the explicitly supported prepared pulsar-3.6.0.tgz chart"
    , testCase "Pulsar correction preserves tar bytes and the legitimate BookKeeper setting" $ do
        let prefix = "tar-header\NULpadding\NUL\n"
            suffix =
              "\n            done;\nexport BOOKIE_MEM=\"-Xmx128M\"; bin/bookkeeper shell whatisinstanceid;\NULtar-padding"
            target variable =
              "export "
                <> variable
                <> "=\"-Xmx128M\";\n"
                <> "            {{- if .Values.pulsar_metadata.configurationStore }}\n"
                <> "            until timeout 15 bin/pulsar zookeeper-shell -server "
        patchPulsarChartTar (prefix <> target "BOOKIE_MEM" <> suffix)
          @?= Right (prefix <> target "PULSAR_MEM" <> suffix)
    , testCase "Pulsar correction refuses changed, absent, and multiple contexts" $ do
        let context =
              "export BOOKIE_MEM=\"-Xmx128M\";\n"
                <> "            {{- if .Values.pulsar_metadata.configurationStore }}\n"
                <> "            until timeout 15 bin/pulsar zookeeper-shell -server "
            changed =
              "export BOOKIE_MEM=\"-Xmx128M\";\n"
                <> "            {{- if .Values.pulsar_metadata.configurationStore }}\n"
                <> "            until timeout 15 bin/bookkeeper shell whatisinstanceid "
        forM_ ["", changed, context <> context] $
          assertBool "unexpected dependency context accepted" . isLeft . patchPulsarChartTar
    , testCase "Pulsar StatefulSet init correction preserves every Job and tar header" $ do
        let original = chartTestTar (statefulInitTestEntries ".Values.initContainer.resources")
            expected = chartTestTar (statefulInitTestEntries ".Values.statefulInit.resources ")
        ByteString.length expected @?= ByteString.length original
        patchPulsarStatefulInitTar original @?= Right expected
    , testCase "Pulsar StatefulSet init correction refuses changed or ambiguous tar entries" $
        case statefulInitTestEntries ".Values.initContainer.resources" of
          [] -> assertFailure "StatefulSet init tar fixture is empty"
          entries@((name, body) : remaining) -> do
            let original = chartTestTar entries
                badSize = ByteString.take 124 original <> "90000000000\NUL" <> ByteString.drop 136 original
                unsafe =
                  [ ByteString.empty
                  , ByteString.take 511 original
                  , chartTestTar remaining
                  , chartTestTar ((name, body) : entries)
                  , chartTestTar ((name, ByteString.empty) : remaining)
                  , chartTestTar ((name, body <> ".Values.initContainer.resources") : remaining)
                  , chartTestTar (statefulInitTestEntries ".Values.statefulInit.resources ")
                  , badSize
                  , original <> "unexpected data"
                  , ByteString.replicate (16 * 1024 * 1024 + 1) 0
                  ]
            forM_ unsafe $
              assertBool "unsafe StatefulSet init tar correction accepted" . isLeft . patchPulsarStatefulInitTar
    , testCase "Pulsar correction bounds its inflated input" $
        assertBool
          "oversized inflated chart accepted"
          (isLeft (patchPulsarChartTar (ByteString.replicate (16 * 1024 * 1024 + 1) 0)))
    , testCase "Pulsar archive authentication precedes gzip decoding" $ do
        preparePulsarChartArchive "not a gzip chart"
          >>= (@?= Left "pinned Pulsar chart archive size differs")
        preparePulsarChartArchive (ByteString.replicate 560310 0)
          >>= (@?= Left "pinned Pulsar chart archive SHA256 differs")
    , testCase "bounded Pulsar admin commands retain the configured transport" $ do
        topic <- case Pulsar.pulsarTopics of
          selected : _ -> pure selected
          [] -> assertFailure "canonical topic family is empty" >> fail "unreachable"
        let settings =
              Pulsar.bootstrapPulsarTopicReconcileSettings
                { Pulsar.topicReconcileKubectlBinary = "/custom/kubectl"
                , Pulsar.topicReconcileKubeconfig = "/custom/kubeconfig"
                , Pulsar.topicReconcileNamespace = "secure-platform"
                , Pulsar.topicReconcileToolsetPod = "secure-toolset-0"
                , Pulsar.topicReconcileHttpBinary = "/custom/curl"
                , Pulsar.topicReconcileAdminEndpoint = "https://admin.example.test:8443/owned/admin/v2/"
                }
        forM_
          [ ("GET", "/stats", Pulsar.pulsarTopicStatsSubprocessFor settings topic)
          , ("PUT", "", Pulsar.pulsarTopicCreateSubprocessFor settings topic)
          ]
          $ \(method, suffix, command) -> do
            subprocessPath command @?= "/custom/kubectl"
            subprocessArguments command
              @?= ( [ "--kubeconfig"
                    , "/custom/kubeconfig"
                    , "--request-timeout=23s"
                    , "exec"
                    , "-n"
                    , "secure-platform"
                    , "secure-toolset-0"
                    , "--"
                    , "/usr/bin/timeout"
                    , "--signal=TERM"
                    , "--kill-after=3s"
                    , "17s"
                    , "/usr/bin/flock"
                    , "--exclusive"
                    , "--no-fork"
                    , "/tmp/jitml-pulsar-admin.lock"
                    , "/custom/curl"
                    , "--disable"
                    , "--silent"
                    , "--show-error"
                    , "--globoff"
                    , "--noproxy"
                    , "*"
                    , "--location"
                    , "--max-redirs"
                    , "5"
                    , "--proto"
                    , "=http,https"
                    , "--proto-redir"
                    , "=http,https"
                    , "--connect-timeout"
                    , "2"
                    , "--max-time"
                    , "5"
                    , "--request"
                    , method
                    , "--write-out"
                    , "\nJITML_PULSAR_HTTP_STATUS=%{http_code}\n"
                    ]
                      <> ( if method == "PUT"
                             then ["--header", "Content-Type: application/json", "--data-binary", "{}"]
                             else []
                         )
                      <> [ "https://admin.example.test:8443/owned/admin/v2/"
                             <> Text.replace "://" "/" (Pulsar.topicName topic)
                             <> suffix
                         ]
                  )
        assertBool
          "in-cluster execution must retain ambient credentials"
          ( "--kubeconfig"
              `notElem` subprocessArguments
                (Pulsar.pulsarTopicCreateSubprocessFor Pulsar.inClusterPulsarTopicReconcileSettings topic)
          )
    , testCase "in-cluster Pulsar create and stats preserve service-account fallback" $
        case Pulsar.pulsarTopics of
          [] -> assertFailure "canonical topic family is empty"
          topic : _ ->
            forM_
              [ Pulsar.pulsarTopicCreateSubprocessFor Pulsar.inClusterPulsarTopicReconcileSettings topic
              , Pulsar.pulsarTopicStatsSubprocessFor Pulsar.inClusterPulsarTopicReconcileSettings topic
              ]
              $ \command -> do
                let arguments = subprocessArguments command
                take 5 arguments @?= ["exec", "-n", "platform", "pulsar-toolset-0", "--"]
                assertBool
                  "kubectl must select the pod service account, not an explicit kubeconfig"
                  ("--kubeconfig" `notElem` arguments)
                assertBool
                  "a global request timeout bypasses client-go's in-cluster fallback"
                  ("--request-timeout=23s" `notElem` arguments)
                assertBool
                  "in-cluster calls must keep the remote watchdog and shared HTTP admission"
                  ( [ "/usr/bin/timeout"
                    , "--signal=TERM"
                    , "--kill-after=3s"
                    , "17s"
                    , "/usr/bin/flock"
                    , "--exclusive"
                    , "--no-fork"
                    , "/tmp/jitml-pulsar-admin.lock"
                    ]
                      `isInfixOf` arguments
                  )
    , testCase "topic convergence runs one observer at a time and requires all 34 addresses" $ do
        active <- newIORef (0 :: Int)
        peak <- newIORef (0 :: Int)
        visited <- newIORef []
        let expected = fmap Pulsar.topicName Pulsar.pulsarTopics
            observe topic = do
              let arguments = subprocessArguments (Pulsar.pulsarTopicStatsSubprocess topic)
                  expectedUrl = "http://pulsar-proxy:80/admin/v2/" <> Text.replace "://" "/" (Pulsar.topicName topic) <> "/stats"
              filter (== "--request") arguments @?= ["--request"]
              take 2 (dropWhile (/= "--request") arguments) @?= ["--request", "GET"]
              take 1 (reverse arguments) @?= [expectedUrl]
              assertBool "exact stats GET must not send a request body" ("--data-binary" `notElem` arguments)
              now <- atomicModifyIORef' active (\count -> (count + 1, count + 1))
              atomicModifyIORef' peak (\previous -> (max previous now, ()))
              threadDelay 1_000
              modifyIORef' visited (<> [Pulsar.topicName topic])
              modifyIORef' active (subtract 1)
              pure True
        evidence <- topicConvergenceEvidenceWith observe
        readIORef peak >>= (@?= 1)
        readIORef visited >>= (@?= expected)
        length expected @?= 34
        reconcileEvidenceExpected evidence @?= expected
        reconcileEvidenceObserved evidence @?= [(name, True) | name <- expected]
    , testCase "unknown topic stops later launches without dropping required coverage" $ do
        visited <- newIORef []
        let expected = fmap Pulsar.topicName Pulsar.pulsarTopics
            observe topic = do
              modifyIORef' visited (<> [Pulsar.topicName topic])
              count <- length <$> readIORef visited
              pure (count < 3)
        evidence <- topicConvergenceEvidenceWith observe
        readIORef visited >>= (@?= take 3 expected)
        reconcileEvidenceExpected evidence @?= expected
        reconcileEvidenceObserved evidence
          @?= zip (take 3 expected) [True, True, False]
        fingerprint <-
          either (assertFailure . Text.unpack) pure (mkDesiredInputFingerprint (Text.replicate 64 "a"))
        stamp <-
          either
            (assertFailure . Text.unpack)
            pure
            (mkReconcileStamp LinuxCPU 9091 fingerprint (Map.singleton "jitml:local" "sha256:fixture"))
        let ready = ReconcileEvidence ["ready"] [("ready", True)]
            -- Even if every gathered result were true, missing observations
            -- must prevent convergence; no synthetic negatives are needed.
            missingOnly = ReconcileEvidence expected [(name, True) | name <- take 3 expected]
            observation =
              ReconcileObservation
                { reconcileExpectedStamp = stamp
                , reconcilePersistedStamp = Just stamp
                , reconcileLivePublication = LivePublicationReady
                , reconcileReleaseEvidence = ready
                , reconcileReadinessEvidence = ready
                , reconcileTopicEvidence = missingOnly
                , reconcileNodeImageEvidence = ready
                , reconcileAppImageEvidence = ready
                , reconcilePortAwareMaterializationUnchanged = True
                }
        classifyReconcileObservation observation
          @?= NeedsReconcile [EvidenceMissing TopicEvidence name | name <- sort (drop 3 expected)]
    , testCase "Pulsar HTTP outcomes require exact status framing and completed subprocesses" $ do
        Pulsar.classifyTopicCreateAttempt (httpOutcome "" 204) @?= Right Pulsar.TopicCreated
        Pulsar.classifyTopicCreateAttempt (httpOutcome "{\"reason\":\"exists\"}" 409)
          @?= Right Pulsar.TopicAlreadyExists
        forM_ [200, 201, 202, 301, 302, 303, 307, 308, 401, 403, 404, 412, 500, 503] $ \status ->
          assertBool "unexpected PUT status acquired topic evidence" $
            isLeft (Pulsar.classifyTopicCreateAttempt (httpOutcome "HTTP code: 409" status))
        Pulsar.classifyTopicStatsAttempt (httpOutcome "{}" 200) @?= Right "{}"
        forM_ [204, 307, 401, 403, 404, 409, 412, 500, 503] $ \status ->
          assertBool "non200 stats acquired loaded-topic evidence" $
            isLeft (Pulsar.classifyTopicStatsAttempt (httpOutcome "{}" status))
        forM_ ["", "[]", "null", "not-json", "{\"partial\":"] $ \body ->
          assertBool "nonobject/truncated stats acquired evidence" $
            isLeft (Pulsar.classifyTopicStatsAttempt (httpOutcome body 200))
        forM_
          [ ""
          , "204"
          , "HTTP code: 409"
          , "\nJITML_PULSAR_HTTP_STATUS=409"
          , "\nJITML_PULSAR_HTTP_STATUS=0409\n"
          , "\nJITML_PULSAR_HTTP_STATUS=000\n"
          , "\nJITML_PULSAR_HTTP_STATUS=409\ntrailing"
          ]
          $ \stdoutText ->
            assertBool "malformed/missing terminal framing acquired evidence" $
              isLeft (Pulsar.classifyTopicCreateAttempt (successfulAdminOutcome stdoutText))
        forM_ [1, 124, 137, 130, -15] $ \code -> do
          let partial = adminOutcomeWithStdout code "\nJITML_PULSAR_HTTP_STATUS=409\n" "error: unexpected EOF"
          assertBool "partial409/RPC/deadline acquired create evidence" $
            isLeft (Pulsar.classifyTopicCreateAttempt partial)
          assertBool "nonzero process acquired stats evidence" $
            isLeft (Pulsar.classifyTopicStatsAttempt partial)
    , testCase "actual curl protocol preserves PUT body, redirects and exact stats errors" $
        withPulsarHttpStub $ \endpoint requestsPath kubectlPath -> do
          topic <- case Pulsar.pulsarTopics of
            selected : _ -> pure selected
            [] -> assertFailure "canonical topic family is empty" >> fail "unreachable"
          let request mode makeCommand =
                let settings =
                      Pulsar.bootstrapPulsarTopicReconcileSettings
                        { Pulsar.topicReconcileKubectlBinary = kubectlPath
                        , Pulsar.topicReconcileKubeconfig = ""
                        , Pulsar.topicReconcileAdminEndpoint = endpoint <> "/" <> mode <> "/admin/v2"
                        }
                 in Pulsar.runPulsarAdminIO (makeCommand settings topic)
              create mode = request mode Pulsar.pulsarTopicCreateSubprocessFor
              stats mode = request mode Pulsar.pulsarTopicStatsSubprocessFor
          let reconcile mode =
                Pulsar.runPulsarTopicReconcileAttemptIO
                  ( Pulsar.bootstrapPulsarTopicReconcileSettings
                      { Pulsar.topicReconcileKubectlBinary = kubectlPath
                      , Pulsar.topicReconcileKubeconfig = ""
                      , Pulsar.topicReconcileAdminEndpoint = endpoint <> "/" <> mode <> "/admin/v2"
                      }
                  )
                  topic
          reconcile "created" >>= (@?= Right Pulsar.TopicCreated)
          reconcile "existing" >>= (@?= Right Pulsar.TopicAlreadyExists)
          forM_ ["existing-partitioned", "created-no-stats"] $ \mode -> do
            actual <- reconcile mode
            assertBool ("creation/conflict bypassed exact stats: " <> Text.unpack mode) (isLeft actual)
          create "created"
            >>= (\actual -> Pulsar.classifyTopicCreateAttempt actual @?= Right Pulsar.TopicCreated)
          create "existing"
            >>= (\actual -> Pulsar.classifyTopicCreateAttempt actual @?= Right Pulsar.TopicAlreadyExists)
          create "redirect"
            >>= (\actual -> Pulsar.classifyTopicCreateAttempt actual @?= Right Pulsar.TopicCreated)
          forM_
            [ "missing"
            , "unauthorized"
            , "forbidden"
            , "server-error"
            , "wrong-success"
            , "loop"
            , "partial-conflict"
            ]
            $ \mode -> do
              actual <- create mode
              assertBool
                ("actual invalid PUT accepted: " <> Text.unpack mode)
                (isLeft (Pulsar.classifyTopicCreateAttempt actual))
          stats "created"
            >>= (\actual -> Pulsar.classifyTopicStatsAttempt actual @?= Right "{\"subscriptions\":{}}")
          forM_
            [ "missing"
            , "unauthorized"
            , "forbidden"
            , "existing-partitioned"
            , "array"
            , "malformed"
            , "partial-conflict"
            ]
            $ \mode -> do
              actual <- stats mode
              assertBool
                ("actual invalid stats accepted: " <> Text.unpack mode)
                (isLeft (Pulsar.classifyTopicStatsAttempt actual))
          requests <- readIORef requestsPath
          let address = "/admin/v2/" <> Text.replace "://" "/" (Pulsar.topicName topic)
          assertBool "307 redirect did not preserve exact PUT method and JSON properties" $
            Text.intercalate "|" ["PUT", "/redirect" <> address, "{}"] `elem` requests
              && Text.intercalate "|" ["PUT", "/created" <> address, "{}"] `elem` requests
          assertBool "stats did not use exact GET address" $
            ("GET|/created" <> address <> "/stats|") `elem` requests
    , testCase "bootstrap stats and both create callers share remote admission under timeout" $ do
        topic <- case Pulsar.pulsarTopics of
          selected : _ -> pure selected
          [] -> assertFailure "canonical topic family is empty" >> fail "unreachable"
        let admission =
              [ "/usr/bin/timeout"
              , "--signal=TERM"
              , "--kill-after=3s"
              , "17s"
              , "/usr/bin/flock"
              , "--exclusive"
              , "--no-fork"
              , "/tmp/jitml-pulsar-admin.lock"
              ]
            commands =
              [ Pulsar.pulsarTopicStatsSubprocess topic
              , Pulsar.pulsarTopicCreateSubprocess topic
              , Pulsar.pulsarTopicCreateSubprocessFor Pulsar.inClusterPulsarTopicReconcileSettings topic
              ]
        forM_ commands $ \command -> do
          let arguments = subprocessArguments command
          assertBool
            "admin caller omitted or reordered its shared bounded remote admission"
            (admission `isInfixOf` arguments)
          assertBool
            "lock must survive exec and remain in the timeout process group"
            (all (`notElem` arguments) ["--close", "--foreground"])
    , testCase "local admin deadline cancels its action without fabricating an exit" $ do
        blocked <- newEmptyMVar
        retired <- newEmptyMVar
        let execute _ = takeMVar blocked `finally` putMVar retired ()
        bounded <-
          timeout 2_000_000 (Pulsar.runPulsarAdminAttemptWith 20_000 execute (subprocess "unused" []))
        case bounded of
          Just (ObservedProcessFailed failure@(ObservedProcessAttemptFailure _)) -> do
            observedProcessFailureExitCode failure @?= Nothing
            assertBool
              "local timeout became already-exists"
              (isLeft (Pulsar.classifyTopicCreateAttempt (ObservedProcessFailed failure)))
          _ -> assertFailure "local deadline did not produce a lossless attempt failure"
        tryTakeMVar retired >>= (@?= Just ())
    , testCase "external cancellation remains cancellation and retires the local action" $ do
        started <- newEmptyMVar
        blocked <- newEmptyMVar
        retired <- newEmptyMVar
        let execute _ = (putMVar started () >> takeMVar blocked) `finally` putMVar retired ()
        worker <- async (Pulsar.runPulsarAdminAttemptWith 25_000_000 execute (subprocess "unused" []))
        takeMVar started
        before <- getMonotonicTimeNSec
        joined <- timeout 1_000_000 (cancel worker >> waitCatch worker)
        after <- getMonotonicTimeNSec
        case joined of
          Just outcome -> assertBool "cancellation was converted to an ordinary outcome" (isLeft outcome)
          Nothing -> assertFailure "admin cancellation did not join within one second"
        assertBool "cancellation acquired a new retirement delay" (after - before < 1_000_000_000)
        tryTakeMVar retired >>= (@?= Just ())
    , testCase "primary and supporting container budgets reach their actual chart value paths" $
        forM_ budgetPaths $ \(release, path, selectedBudget) -> do
          rendered <- overlay release
          valueAt path rendered @?= Just (expectedResources selectedBudget)
    , testCase "direct service manifests use the selected engine and coordinator budgets" $ do
        let rendered = renderServiceDeployment profile LinuxCPU
        Text.count "          resources:\n" rendered @?= 2
        assertBool "engine CPU profile reaches direct manifest" ("cpu: \"106m\"" `Text.isInfixOf` rendered)
        assertBool
          "engine memory limit reaches direct manifest"
          ("memory: \"212Mi\"" `Text.isInfixOf` rendered)
        assertBool
          "coordinator CPU profile reaches direct manifest"
          ("cpu: \"109m\"" `Text.isInfixOf` rendered)
        assertBool
          "coordinator memory limit reaches direct manifest"
          ("memory: \"218Mi\"" `Text.isInfixOf` rendered)
    , testCase "generated service defaults carry both value maps" $ do
        let rendered = renderServiceValues profile
        assertBool "engine value map" ("resources:\n" `Text.isInfixOf` rendered)
        assertBool "coordinator value map" ("coordinatorResources:\n" `Text.isInfixOf` rendered)
        assertBool "selected coordinator budget" ("memory: \"218Mi\"" `Text.isInfixOf` rendered)
    , testCase "local service and webapp overlays carry the selected numerical BootConfig budget" $ do
        forM_ ["jitml-service", "jitml-demo"] $ \name -> do
          rendered <- overlay name
          case rendered of
            Object fields ->
              KeyMap.lookup "numericalWorkload" fields
                @?= Just
                  ( object
                      [ "replicas" .= (1 :: Int)
                      , "cpuRequest" .= ("111m" :: Text)
                      , "cpuLimit" .= ("222m" :: Text)
                      , "memoryRequest" .= ("111Mi" :: Text)
                      , "memoryLimit" .= ("222Mi" :: Text)
                      ]
                  )
            _ -> assertFailure "resource overlay is not an object"
    , testCase "webapp placement follows the explicit control-plane scheduling policy" $ do
        let demoPath = ".build/conf/cluster/resources/jitml-demo.yaml"
            overlaysFor allowed =
              renderClusterResourceValues (profile {scheduleOnControlPlane = allowed})
            demoFor allowed =
              case lookup demoPath (overlaysFor allowed) of
                Nothing -> assertFailure "webapp resource overlay is missing"
                Just rendered ->
                  either assertFailure pure $
                    Aeson.eitherDecodeStrict' (Text.Encoding.encodeUtf8 rendered)
        disabled <- demoFor False
        enabled <- demoFor True
        case (disabled, enabled) of
          (Object unrestricted, Object selected) -> do
            KeyMap.lookup "nodeSelector" unrestricted @?= Nothing
            KeyMap.lookup "nodeSelector" selected
              @?= Just (object ["node-role.kubernetes.io/control-plane" .= ("" :: Text)])
            KeyMap.delete "nodeSelector" selected @?= unrestricted
          _ -> assertFailure "webapp resource overlay is not an object"
        let otherOverlays = filter ((/= demoPath) . fst)
        otherOverlays (overlaysFor True) @?= otherOverlays (overlaysFor False)
    , testCase "platform admission defaults use supporting budgets without capping primary containers" $ do
        rendered <-
          either assertFailure pure $
            Aeson.eitherDecodeStrict' (Text.Encoding.encodeUtf8 (renderPlatformResourceDefaults profile))
        let selected = supporting profile
            expected =
              object
                [ "apiVersion" .= ("v1" :: Text)
                , "kind" .= ("List" :: Text)
                , "items"
                    .= [ object
                           [ "apiVersion" .= ("v1" :: Text)
                           , "kind" .= ("Namespace" :: Text)
                           , "metadata" .= object ["name" .= ("platform" :: Text)]
                           ]
                       , object
                           [ "apiVersion" .= ("v1" :: Text)
                           , "kind" .= ("LimitRange" :: Text)
                           , "metadata"
                               .= object
                                 [ "name" .= ("jitml-container-defaults" :: Text)
                                 , "namespace" .= ("platform" :: Text)
                                 ]
                           , "spec"
                               .= object
                                 [ "limits"
                                     .= [ object
                                            [ "type" .= ("Container" :: Text)
                                            , "defaultRequest"
                                                .= object
                                                  [ "cpu" .= budgetCpuRequest selected
                                                  , "memory" .= budgetMemoryRequest selected
                                                  ]
                                            , "default"
                                                .= object
                                                  [ "cpu" .= budgetCpuLimit selected
                                                  , "memory" .= budgetMemoryLimit selected
                                                  ]
                                            ]
                                        ]
                                 ]
                           ]
                       ]
                ]
        rendered @?= expected
    , testCase "gateway and shutdown manager use distinct profile budgets" $ do
        let rendered = renderEnvoyProxy profile 9091
        Text.count "resources:\n" rendered @?= 2
        assertBool "gateway CPU limit is explicit" ("cpu: \"220m\"" `Text.isInfixOf` rendered)
        assertBool "gateway memory profile" ("memory: \"110Mi\"" `Text.isInfixOf` rendered)
        assertBool "shutdown-manager supporting profile" ("memory: \"109Mi\"" `Text.isInfixOf` rendered)
        assertBool "edge port preserved" ("port: 9091" `Text.isInfixOf` rendered)
    , testCase "Kind defaults preserve taints and omit resource-policy overrides" $ do
        let config = kindConfigFor LinuxCPU
            rendered = renderKindConfig config
        rendered @?= renderKindConfigWithResourcePolicy False Nothing config
        assertBool "no default taint override" (not ("taints:" `Text.isInfixOf` rendered))
        assertBool "no default reservation" (not ("system-reserved:" `Text.isInfixOf` rendered))
        assertBool
          "no default allocatable override"
          (not ("enforce-node-allocatable:" `Text.isInfixOf` rendered))
    , testCase "Kind policy reserves both nodes and allows only ordinary control-plane scheduling" $ do
        let rendered = renderKindConfigWithResourcePolicy True (Just ("250m", "1024Mi")) (kindConfigFor LinuxCPU)
            (controlPlane, worker) = Text.breakOn "  - role: worker\n" rendered
        Text.count "system-reserved: \"cpu=250m,memory=1024Mi\"" rendered @?= 2
        Text.count "enforce-node-allocatable: pods" rendered @?= 2
        Text.count "taints: []" controlPlane @?= 1
        assertBool "worker taints remain unchanged" (not ("taints:" `Text.isInfixOf` worker))
        assertBool
          "control-plane stays outside the engine compute pool"
          (not ("jitml.node-role/compute=true" `Text.isInfixOf` controlPlane))
        assertBool
          "worker retains engine placement label"
          ("jitml.node-role/compute=true" `Text.isInfixOf` worker)
    , testCase "Kind reservations do not implicitly enable control-plane scheduling" $ do
        let rendered = renderKindConfigWithResourcePolicy False (Just ("100m", "512Mi")) (kindConfigFor LinuxCPU)
        Text.count "system-reserved: \"cpu=100m,memory=512Mi\"" rendered @?= 2
        assertBool "control-plane taints preserved" (not ("taints:" `Text.isInfixOf` rendered))
    , testCase "kubelet flags insert missing reservations without changing unrelated arguments" $ do
        rewriteKubeletResourceFlags
          reservation
          ( flags
              "  --container-runtime-endpoint=unix:///run/containerd/containerd.sock  --node-labels=jitml.node-role/compute=true "
          )
          @?= Right
            ( flags
                "  --container-runtime-endpoint=unix:///run/containerd/containerd.sock  --node-labels=jitml.node-role/compute=true --system-reserved=cpu=2750m,memory=12438532096 --enforce-node-allocatable=pods "
            )
    , testCase "kubelet flags replace conflicting target values in their original positions" $ do
        rewriteKubeletResourceFlags
          reservation
          ( flags
              "--enforce-node-allocatable=none --node-ip=172.18.0.2 --system-reserved=memory=1024Mi,cpu=250m --system-reserved-cgroup=/system.slice"
          )
          @?= Right
            ( flags
                "--enforce-node-allocatable=pods --node-ip=172.18.0.2 --system-reserved=cpu=2750m,memory=12438532096 --system-reserved-cgroup=/system.slice"
            )
    , testCase "correct kubelet flags are byte-preserving and rewriting is idempotent" $ do
        let correct =
              flags
                " --system-reserved=cpu=2750m,memory=12438532096   --node-ip=172.18.0.2 --enforce-node-allocatable=pods  "
            original = flags "--node-ip=172.18.0.2"
        rewriteKubeletResourceFlags reservation correct @?= Right correct
        rewritten <-
          either (assertFailure . Text.unpack) pure (rewriteKubeletResourceFlags reservation original)
        rewriteKubeletResourceFlags reservation rewritten @?= Right rewritten
    , testCase "kubelet flags preserve a present target while appending only its missing partner" $ do
        rewriteKubeletResourceFlags
          reservation
          (flags "--enforce-node-allocatable=pods --provider-id=kind://docker/local/node")
          @?= Right
            ( flags
                "--enforce-node-allocatable=pods --provider-id=kind://docker/local/node --system-reserved=cpu=2750m,memory=12438532096"
            )
    , testCase "duplicate kubelet resource flags refuse even when their values agree" $
        forM_
          [ "--system-reserved=cpu=250m,memory=1Gi --system-reserved=cpu=250m,memory=1Gi"
          , "--enforce-node-allocatable=pods --enforce-node-allocatable=none"
          ]
          (assertBool "duplicate target accepted" . isLeft . rewriteKubeletResourceFlags reservation . flags)
    , testCase "kubelet flag records reject additional assignments unsafe syntax and malformed shapes" $
        forM_
          [ flags "--node-ip=172.18.0.2" <> flags "--v=2"
          , "OTHER_ARGS=\"--v=2\"\n"
          , "KUBELET_KUBEADM_ARGS='--v=2'\n"
          , "KUBELET_KUBEADM_ARGS=\"--v=2\""
          , flags ""
          , flags "--v=2\n--node-ip=172.18.0.2"
          , flags "--v=2\t--node-ip=172.18.0.2"
          , flags "--node-ip=$(hostname)"
          , flags "--node-ip=`hostname`"
          , flags "--v=2\";echo unsafe;#"
          , flags "--node-ip=\\$HOSTNAME"
          , flags "--v=2 positional"
          , flags "--system-reserved cpu=250m,memory=1Gi"
          , flags "--enforce-node-allocatable="
          ]
          (assertBool "unsafe or unknown record accepted" . isLeft . rewriteKubeletResourceFlags reservation)
    , testCase "kubelet rewrite refuses to drop additional reserved dimensions or unknown policies" $
        forM_
          [ "--system-reserved=cpu=250m,memory=1Gi,pid=1000"
          , "--system-reserved=cpu=250m,cpu=500m"
          , "--enforce-node-allocatable=unknown"
          ]
          ( assertBool "unrecognized target shape accepted"
              . isLeft
              . rewriteKubeletResourceFlags reservation
              . flags
          )
    , testCase "kubelet rewrite requires positive ASCII milliCPU and byte reservations" $
        forM_
          [("0m", "1"), ("1", "1"), ("1.5m", "1"), ("1m", "0"), ("1m", "1Gi"), ("１m", "1"), ("1m", "1;echo")]
          ( \selected ->
              assertBool
                "invalid reserve accepted"
                (isLeft (rewriteKubeletResourceFlags selected (flags "--v=2")))
          )
    ]
 where
  reservation = ("2750m", "12438532096")
  flags arguments = "KUBELET_KUBEADM_ARGS=\"" <> arguments <> "\"\n"
  overlay name =
    case lookup (overlayPath name) (renderClusterResourceValues profile) of
      Nothing -> assertFailure ("missing overlay " <> name) >> pure Null
      Just contents ->
        either assertFailure pure (Aeson.eitherDecodeStrict' (Text.Encoding.encodeUtf8 contents))

overlayPath :: String -> FilePath
overlayPath name = ".build/conf/cluster/resources/" <> name <> ".yaml"

profile :: ClusterResources
profile =
  defaultClusterResources
    { registry = budget 101
    , minio = budget 102
    , pulsar = budget 103
    , prometheus = budget 104
    , grafana = budget 105
    , jitmlService = budget 106
    , jitmlDemo = budget 107
    , tensorboard = budget 108
    , supporting = budget 109
    , gateway = budget 110
    , numericalWorkload = budget 111
    }

budget :: Int -> ComponentBudget
budget number =
  ComponentBudget
    1
    (quantity number "m")
    (quantity (2 * number) "m")
    (quantity number "Mi")
    (quantity (2 * number) "Mi")
 where
  quantity value unit = Text.pack (show value) <> unit

expectedResources :: ComponentBudget -> Value
expectedResources selected =
  object
    [ "requests"
        .= object
          [ "cpu" .= budgetCpuRequest selected
          , "memory" .= budgetMemoryRequest selected
          ]
    , "limits"
        .= object
          [ "cpu" .= budgetCpuLimit selected
          , "memory" .= budgetMemoryLimit selected
          ]
    ]

valueAt :: [Text] -> Value -> Maybe Value
valueAt [] value = Just value
valueAt (key : rest) (Object values) = KeyMap.lookup (Key.fromText key) values >>= valueAt rest
valueAt _ _ = Nothing

budgetPaths :: [(String, [Text], ComponentBudget)]
budgetPaths =
  [ ("minio", ["resources"], minio profile)
  , ("minio", ["volumePermissions", "resources"], supporting profile)
  , ("minio", ["provisioning", "resources"], supporting profile)
  , ("registry", ["resources"], registry profile)
  , ("pulsar", ["zookeeper", "resources"], pulsar profile)
  , ("pulsar", ["bookkeeper", "resources"], pulsar profile)
  , ("pulsar", ["broker", "resources"], pulsar profile)
  , ("pulsar", ["proxy", "resources"], pulsar profile)
  , ("pulsar", ["statefulInit", "resources"], supporting profile)
  , ("pulsar", ["autorecovery", "resources"], supporting profile)
  , ("pulsar", ["toolset", "resources"], supporting profile)
  , ("kube-prometheus-stack", ["grafana", "resources"], grafana profile)
  , ("kube-prometheus-stack", ["grafana", "sidecar", "resources"], supporting profile)
  , ("kube-prometheus-stack", ["prometheus", "prometheusSpec", "resources"], prometheus profile)
  , ("kube-prometheus-stack", ["prometheusOperator", "resources"], supporting profile)
  ,
    ( "kube-prometheus-stack"
    , ["prometheusOperator", "prometheusConfigReloader", "resources"]
    , supporting profile
    )
  ,
    ( "kube-prometheus-stack"
    , ["prometheusOperator", "admissionWebhooks", "patch", "resources"]
    , supporting profile
    )
  , ("kube-prometheus-stack", ["kube-state-metrics", "resources"], supporting profile)
  , ("kube-prometheus-stack", ["crds", "upgradeJob", "resources"], supporting profile)
  , ("tensorboard", ["resources"], tensorboard profile)
  , ("tensorboard", ["syncResources"], supporting profile)
  , ("jitml-service", ["resources"], jitmlService profile)
  , ("jitml-service", ["coordinatorResources"], supporting profile)
  , ("jitml-demo", ["resources"], jitmlDemo profile)
  , ("envoy-gateway", ["deployment", "envoyGateway", "resources"], supporting profile)
  , ("envoy-gateway", ["certgen", "job", "resources"], supporting profile)
  ]

successfulAdminOutcome :: Text -> ObservedProcessOutcome
successfulAdminOutcome stdoutText =
  ObservedProcessSucceeded (adminTranscript stdoutText "")

httpOutcome :: Text -> Int -> ObservedProcessOutcome
httpOutcome body status =
  successfulAdminOutcome (body <> "\nJITML_PULSAR_HTTP_STATUS=" <> Text.pack (show status) <> "\n")

adminOutcomeWithStdout :: Int -> Text -> Text -> ObservedProcessOutcome
adminOutcomeWithStdout code stdoutText stderrText =
  case processOutcome (ExitFailure code) (adminTranscript stdoutText stderrText) of
    ProcessSucceeded transcript -> ObservedProcessSucceeded transcript
    ProcessFailed failure -> ObservedProcessFailed (ObservedProcessExitFailure failure)

adminTranscript :: Text -> Text -> ProcessTranscript
adminTranscript stdoutText stderrText =
  ProcessTranscript
    { processTranscriptCommand = "kubectl exec fixture"
    , processTranscriptStdout = stdoutText
    , processTranscriptStderr = stderrText
    , processTranscriptWorkingDirectory = Nothing
    , processTranscriptDuration = ProcessDuration 0
    }

-- | A real portable loopback HTTP server exercises the constructed command.
-- The fixture validates then strips the Linux-only remote admission prefix;
-- actual in-cluster validation separately exercises that remote watchdog/flock.
withPulsarHttpStub :: (Text -> IORef [Text] -> FilePath -> IO value) -> IO value
withPulsarHttpStub action =
  Socket.withSocketsDo $
    withSystemTempDirectory "jitml-pulsar-http" $ \directory -> do
      let kubectlPath = directory </> "kubectl-pass-through"
      Text.IO.writeFile
        kubectlPath
        ( Text.unlines
            [ "#!/bin/sh"
            , "set -eu"
            , "test \"$1\" = exec && test \"$2\" = -n && test \"$3\" = platform && test \"$4\" = pulsar-toolset-0 && test \"$5\" = -- || exit 97"
            , "shift 5"
            , "test \"$1\" = /usr/bin/timeout && test \"$2\" = --signal=TERM && test \"$3\" = --kill-after=3s && test \"$4\" = 17s || exit 98"
            , "test \"$5\" = /usr/bin/flock && test \"$6\" = --exclusive && test \"$7\" = --no-fork && test \"$8\" = /tmp/jitml-pulsar-admin.lock || exit 99"
            , "shift 8"
            , "test \"$1\" = /usr/bin/curl || exit 100"
            , "exec \"$@\""
            ]
        )
      permissions <- getPermissions kubectlPath
      setPermissions kubectlPath (setOwnerExecutable True permissions)
      requests <- newIORef []
      bracket
        (Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol)
        Socket.close
        ( \listener -> do
            Socket.bind listener (Socket.SockAddrInet 0 (Socket.tupleToHostAddress (127, 0, 0, 1)))
            Socket.listen listener 1
            address <- Socket.getSocketName listener
            port <- case address of
              Socket.SockAddrInet selected _host -> pure selected
              _ -> ioError (userError "Pulsar HTTP stub requires loopback IPv4")
            let serve =
                  forever $
                    bracket
                      (fst <$> Socket.accept listener)
                      Socket.close
                      ( \connection -> do
                          completed <- timeout 1_000_000 $ do
                            (method, target, body) <- readPulsarHttpRequest connection
                            atomicModifyIORef'
                              requests
                              (\previous -> (previous <> [Text.intercalate "|" [method, target, body]], ()))
                            Socket.Bytes.sendAll connection (pulsarHttpStubResponse method target body)
                          case completed of
                            Just () -> pure ()
                            Nothing -> ioError (userError "Pulsar HTTP stub connection exceeded one second")
                      )
            withAsync serve $ \serverWorker -> do
              link serverWorker
              action ("http://127.0.0.1:" <> Text.pack (show port)) requests kubectlPath
        )

-- Headers and the complete request are bounded independently of fragmentation.
readPulsarHttpRequest :: Socket.Socket -> IO (Text, Text, Text)
readPulsarHttpRequest connection = receiveHeaders ByteString.empty
 where
  maximumRequestBytes = 8 * 1024
  receiveMore accumulated = do
    fragment <- Socket.Bytes.recv connection 4096
    when (ByteString.null fragment) (ioError (userError "HTTP stub request ended before completion"))
    let combined = accumulated <> fragment
    when
      (ByteString.length combined > maximumRequestBytes)
      (ioError (userError "HTTP stub request exceeds8KiB"))
    pure combined
  receiveHeaders accumulated =
    case ByteString.breakSubstring "\r\n\r\n" accumulated of
      (_headers, rest) | ByteString.null rest -> receiveMore accumulated >>= receiveHeaders
      (headers, rest) -> do
        let headerLines = Text.lines (Text.pack (ByteString.Char8.unpack headers))
            lengths =
              [ Text.strip (Text.drop 1 value)
              | line <- case headerLines of
                  [] -> []
                  _requestLine : fields -> fields
              , let (name, value) = Text.breakOn ":" line
              , Text.toLower name == "content-length"
              ]
        contentLength <- case lengths of
          [] -> pure 0
          [value] -> case readMaybe (Text.unpack value) of
            Just count | count >= 0 && count <= maximumRequestBytes -> pure count
            _ -> ioError (userError "HTTP stub received invalid Content-Length")
          _ -> ioError (userError "HTTP stub received duplicate Content-Length")
        when (ByteString.length headers + 4 + contentLength > maximumRequestBytes) $
          ioError (userError "HTTP stub complete request exceeds8KiB")
        (method, target) <- case headerLines of
          firstLine : _ -> case Text.words firstLine of
            [selectedMethod, selectedTarget, _version] -> pure (selectedMethod, selectedTarget)
            _ -> ioError (userError "HTTP stub received malformed request line")
          [] -> ioError (userError "HTTP stub received no request line")
        body <- receiveBody contentLength (ByteString.drop 4 rest)
        decoded <- either (ioError . userError . show) pure (Text.Encoding.decodeUtf8' body)
        pure (method, target, decoded)
  receiveBody needed accumulated
    | ByteString.length accumulated >= needed = pure (ByteString.take needed accumulated)
    | otherwise = receiveMore accumulated >>= receiveBody needed

pulsarHttpStubResponse :: Text -> Text -> Text -> ByteString.ByteString
pulsarHttpStubResponse method target requestBody =
  Text.Encoding.encodeUtf8
    ( "HTTP/1.1 "
        <> Text.pack (show status)
        <> " Test\r\n"
        <> "Content-Type: application/json\r\n"
        <> "Content-Length: "
        <> Text.pack (show declaredLength)
        <> "\r\n"
        <> "Connection: close\r\n"
        <> (if redirect then "Location: " <> Text.replace "/redirect/" "/created/" target <> "\r\n" else "")
        <> "\r\n"
    )
    <> responseBody
 where
  mode = case Text.splitOn "/" target of
    _empty : selected : _ -> selected
    _ -> ""
  redirect = mode `elem` ["redirect", "loop"]
  status :: Int
  status
    | method == "PUT" && requestBody /= "{}" = 400
    | redirect = 307
    | mode `elem` ["existing-partitioned", "created-no-stats"] && method == "GET" = 404
    | mode == "existing" && method == "GET" = 200
    | otherwise =
        Map.findWithDefault
          (if method == "GET" || mode == "wrong-success" then 200 else 204)
          mode
          ( Map.fromList
              [ ("missing", 404)
              , ("unauthorized", 401)
              , ("forbidden", 403)
              , ("server-error", 503)
              , ("existing", 409)
              , ("existing-partitioned", 409)
              , ("partial-conflict", 409)
              ]
          )
  responseBody
    | status == 204 || redirect = ""
    | mode == "array" = "[]"
    | mode == "malformed" = "not-json"
    | status == 200 = "{\"subscriptions\":{}}"
    | otherwise = "{\"reason\":\"refused\"}"
  declaredLength = ByteString.length responseBody + if mode == "partial-conflict" then 5 else 0

statefulInitTestEntries :: ByteString.ByteString -> [(ByteString.ByteString, ByteString.ByteString)]
statefulInitTestEntries reference =
  [ ("pulsar/templates/autorecovery-statefulset.yaml", reference)
  , ("pulsar/templates/bookkeeper-statefulset.yaml", reference)
  , ("pulsar/templates/broker-statefulset.yaml", reference <> "\n" <> reference)
  , ("pulsar/templates/proxy-statefulset.yaml", reference <> "\n" <> reference)
  , ("pulsar/templates/bookkeeper-cluster-initialize.yaml", ".Values.initContainer.resources")
  ,
    ( "pulsar/templates/pulsar-cluster-initialize.yaml"
    , ".Values.initContainer.resources\n.Values.initContainer.resources"
    )
  ]

chartTestTar :: [(ByteString.ByteString, ByteString.ByteString)] -> ByteString.ByteString
chartTestTar entries = ByteString.concat (fmap (uncurry entry) entries) <> ByteString.replicate 1024 0
 where
  entry name body =
    let header =
          field 0 100 name $
            field 100 8 "0000644\NUL" $
              field 124 12 (octal 11 (ByteString.length body) <> "\NUL") $
                field 148 8 "        " $
                  field 156 1 "0" $
                    field 257 6 "ustar\NUL" $
                      field 263 2 "00" (ByteString.replicate 512 0)
        checksum = sum [fromIntegral byte :: Int | byte <- ByteString.unpack header]
        sealed = field 148 8 (octal 6 checksum <> "\NUL ") header
        padding = (512 - ByteString.length body `mod` 512) `mod` 512
     in sealed <> body <> ByteString.replicate padding 0
  field offset width value bytes =
    ByteString.take offset bytes
      <> ByteString.take width (value <> ByteString.replicate width 0)
      <> ByteString.drop (offset + width) bytes
  octal width value =
    let digits = showOct value ""
     in ByteString.Char8.pack (replicate (width - length digits) '0' <> digits)
