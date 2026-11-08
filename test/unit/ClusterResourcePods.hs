{-# LANGUAGE OverloadedStrings #-}

module ClusterResourcePods (tests) where

import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as Lazy
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Cluster.ResourceBudget
  ( ResourceEnvelope
  , RuntimeCapacity (..)
  , validateResourceEnvelope
  )
import JitML.Cluster.ResourcePods
  ( NodePodBudget (..)
  , PodBudgetReport (..)
  , validateAdmittedPodBudgets
  )
import JitML.Cluster.Resources (ClusterResources (..), defaultClusterResources)
import JitML.Substrate (Substrate (LinuxCPU))

-- Keep the large JSON fixtures out of the monolithic unit Main optimizer.
{-# NOINLINE tests #-}
tests :: TestTree
tests =
  testGroup
    "actual admitted Pod resource budgets"
    [ testCase "actual four-field admission values are accepted without guessing defaults" $ do
        report <- accepted [app]
        podBudgetObservedPodUids report @?= ["uid-app"]
        node <- workerBudget report
        nodePodRequestedCpuMilli node @?= 100
        nodePodRequestedMemoryBytes node @?= mib 128
    , testCase "Grafana-style regular sidecars sum into one Pod" $ do
        let side name = container name "25m" "64Mi" "250m" "512Mi"
            main = container "grafana" "25m" "128Mi" "250m" "512Mi"
        report <- accepted [pod "grafana" "platform" worker [side "dashboard", side "datasource", main] []]
        node <- workerBudget report
        nodePodRequestedCpuMilli node @?= 75
        nodePodRequestedMemoryBytes node @?= mib 256
        nodePodPlatformMemoryLimitsBytes node @?= mib 1536
    , testCase "combined Pod memory limit cannot hide behind individually fitting containers" $
        refuses "effective Pod memory limit" [pod "large" "platform" worker [large "a", large "b"] []]
    , testCase "ordinary sequential init containers use resource-wise maxima" $ do
        let firstInit = container "first" "900m" "3Gi" "1" "3Gi"
            secondInit = container "second" "800m" "2Gi" "1" "2Gi"
        report <- accepted [pod "init" "platform" worker [mainContainer] [firstInit, secondInit]]
        node <- workerBudget report
        nodePodRequestedCpuMilli node @?= 900
        nodePodRequestedMemoryBytes node @?= mib 3072
    , testCase "native sidecars overlap later init stages and remain with the app" $ do
        let side = set ["restartPolicy"] (String "Always") (container "side" "100m" "64Mi" "250m" "128Mi")
            later = set ["restartPolicy"] (String "Always") (container "later" "50m" "32Mi" "100m" "64Mi")
            initWork = container "init" "900m" "256Mi" "1" "1Gi"
            main = container "main" "200m" "128Mi" "500m" "512Mi"
        ordered <- accepted [pod "ordered" "platform" worker [main] [side, initWork, later]]
        orderedNode <- workerBudget ordered
        nodePodRequestedCpuMilli orderedNode @?= 1000
        nodePodRequestedMemoryBytes orderedNode @?= mib 320
        nodePodPlatformMemoryLimitsBytes orderedNode @?= mib 1152
        reversed <- accepted [pod "reordered" "platform" worker [main] [initWork, side, later]]
        reversedNode <- workerBudget reversed
        nodePodRequestedCpuMilli reversedNode @?= 900
        nodePodRequestedMemoryBytes reversedNode @?= mib 256
    , testCase "Pod overhead is added to requests and finite Pod memory limit" $ do
        report <-
          accepted
            [set ["spec", "overhead"] (object ["cpu" .= ("25m" :: Text), "memory" .= ("64Mi" :: Text)]) app]
        node <- workerBudget report
        nodePodRequestedCpuMilli node @?= 125
        nodePodRequestedMemoryBytes node @?= mib 192
        nodePodPlatformMemoryLimitsBytes node @?= mib 320
    , testCase "per-node CPU overbooking refuses despite enough pooled cluster CPU" $
        refuses "CPU requests exceed" [withMain "one" "800m" "128Mi", withMain "two" "800m" "128Mi"]
    , testCase "per-node memory overbooking includes all regular Pods" $
        refuses "memory requests exceed" [withMain "one" "100m" "3Gi", withMain "two" "100m" "3Gi"]
    , testCase "system requests reduce platform headroom and are not subtracted twice as reserve" $
        refuses
          "CPU requests exceed"
          [ withMain "app" "1200m" "128Mi"
          , pod "dns" "kube-system" worker [container "dns" "100m" "70Mi" "200m" "170Mi"] []
          ]
    , testCase "missing system requests are zero while missing inner limits are reported" $ do
        report <- accepted [app, pod "proxy" "kube-system" worker [object ["name" .= ("proxy" :: Text)]] []]
        node <- workerBudget report
        nodePodRequestedCpuMilli node @?= 100
        podBudgetSystemContainersBoundedOnlyByNode report @?= ["kube-system/proxy/proxy"]
    , testCase "unassigned platform and system Pods both refuse unscheduled demand" $ do
        refuses "unscheduled demand" [set ["spec", "nodeName"] (String "") app]
        refuses "unscheduled demand" [app, pod "dns" "kube-system" "" [mainContainer] []]
    , testCase "all active infrastructure Pods must be Running and uniquely Ready" $ do
        refuses "not Running" [set ["status", "phase"] (String "Pending") app]
        refuses "Ready=True" [notReady app]
        refuses "Ready=True" [app, notReady (pod "dns" "kube-system" controlPlane [mainContainer] [])]
        refuses "Ready=True" [set ["status", "conditions"] (Aeson.toJSON [ready, ready]) app]
    , testCase "terminating demand still counts and cannot satisfy final convergence" $ do
        let terminating =
              set
                ["metadata", "deletionTimestamp"]
                (String "2026-10-31T00:00:00Z")
                (withMain "old" "800m" "128Mi")
        refuses "CPU requests exceed" [withMain "new" "800m" "128Mi", terminating]
        refuses
          "terminating nonterminal"
          [set ["metadata", "deletionTimestamp"] (String "2026-10-31T00:00:00Z") app]
    , testCase "completed Job Pods are excluded only with their actual controller owner" $ do
        let done = set ["status", "phase"] (String "Succeeded") (withMain "done" "2" "3Gi")
            job = set ["metadata", "ownerReferences"] (Aeson.toJSON [jobOwner]) done
        report <- accepted [app, job]
        podBudgetTerminalPodUids report @?= ["uid-done"]
        node <- workerBudget report
        nodePodRequestedCpuMilli node @?= 100
        refuses "actual controller Job owner" [app, done]
    , testCase "failed platform attempts explicitly refuse even when they are terminal" $ do
        let failed = set ["status", "phase"] (String "Failed") app
        refuses "failed platform Pod" [failed]
        refuses "failed platform Pod" [set ["metadata", "ownerReferences"] (Aeson.toJSON [jobOwner]) failed]
        report <-
          accepted
            [ app
            , set ["status", "phase"] (String "Failed") (pod "old-system" "kube-system" worker [mainContainer] [])
            ]
        length (podBudgetTerminalPodUids report) @?= 1
    , testCase "managed init and regular containers need admitted positive finite caps" $ do
        refuses
          "missing admitted"
          [pod "missing" "platform" worker [object ["name" .= ("main" :: Text)]] []]
        let requestsOnly =
              object
                [ "name" .= ("init" :: Text)
                , "resources"
                    .= object ["requests" .= object ["cpu" .= ("100m" :: Text), "memory" .= ("256Mi" :: Text)]]
                ]
        refuses "missing admitted" [pod "init-missing" "platform" worker [mainContainer] [requestsOnly]]
        refuses "positive" [pod "zero" "platform" worker [container "main" "0" "128Mi" "250m" "256Mi"] []]
    , testCase "request greater than limit and malformed resource JSON refuse" $ do
        refuses
          "request exceeds limit"
          [pod "order" "platform" worker [container "main" "500m" "128Mi" "250m" "256Mi"] []]
        refuses
          "invalid admitted Pods JSON"
          [ set
              ["spec", "containers"]
              (Aeson.toJSON [set ["resources", "requests", "cpu"] (Aeson.toJSON (100 :: Int)) mainContainer])
              app
          ]
        refuses "memory:" [pod "unit" "platform" worker [container "main" "100m" "128MB" "250m" "256Mi"] []]
    , testCase "ordinary status resource fields match numerically without inventing resize state" $ do
        let fields = resources "100m" "128Mi" "250m" "256Mi"
            observed =
              object
                [ "name" .= ("main" :: Text)
                , "resources" .= fields
                , "allocatedResources" .= object ["cpu" .= ("0.1" :: Text), "memory" .= ("134217728" :: Text)]
                ]
            normal = set ["status", "containerStatuses"] (Aeson.toJSON [observed]) app
        _ <- accepted [normal]
        refuses
          "divergent allocated resources"
          [ set
              ["status", "containerStatuses"]
              (Aeson.toJSON [set ["allocatedResources", "memory"] (String "256Mi") observed])
              app
          ]
        refuses
          "divergent container status"
          [ set
              ["status", "containerStatuses"]
              (Aeson.toJSON [set ["resources", "limits", "memory"] (String "512Mi") observed])
              app
          ]
    , testCase "Pod-level budgets resize transitions and ephemeral containers refuse explicitly" $ do
        refuses
          "Pod-level resources"
          [set ["spec", "resources"] (resources "100m" "128Mi" "250m" "256Mi") app]
        let resize = object ["type" .= ("PodResizePending" :: Text), "status" .= ("True" :: Text)]
        refuses "in-place resize" [set ["status", "conditions"] (Aeson.toJSON [ready, resize]) app]
        refuses
          "ephemeral containers"
          [set ["spec", "ephemeralContainers"] (Aeson.toJSON [object ["name" .= ("debug" :: Text)]]) app]
    , testCase "extended resource fields are explicitly outside the CPU and RAM proof" $ do
        let gpu =
              set
                ["resources", "limits", "nvidia.com/gpu"]
                (String "1")
                (set ["resources", "requests", "nvidia.com/gpu"] (String "1") mainContainer)
        report <- accepted [pod "gpu" "platform" worker [gpu] []]
        podBudgetExtendedResourcesOutsideScope report @?= ["platform/gpu/nvidia.com/gpu"]
    , testCase "actual node bounds duplicates and unexpected assignment cannot be bypassed" $ do
        refuses "duplicate Pod UIDs" [app, app]
        refuses "unexpected node" [set ["spec", "nodeName"] (String "foreign") app]
        let compute =
              set
                ["spec", "nodeSelector"]
                (object ["jitml.node-role/compute" .= ("true" :: Text)])
                (set ["spec", "nodeName"] (String controlPlane) app)
        refuses "not assigned to a compute worker" [compute]
        envelope <- checkedEnvelope
        let smaller = nodesWith "500m" "4Gi"
        expectRefusal
          "CPU requests exceed"
          ( validateAdmittedPodBudgets
              LinuxCPU
              profile
              envelope
              (encoded smaller)
              (inventory [withMain "app" "600m" "128Mi"])
          )
    , testCase "aggregate memory limits may overcommit parents when individual Pods fit" $ do
        report <-
          accepted [pod "one" "platform" worker [large "a"] [], pod "two" "platform" worker [large "b"] []]
        podBudgetLimitsOvercommitNodes report @?= True
    , testCase "a Pod limit must fit lower observed memory even when its request and profile fit" $ do
        envelope <- checkedEnvelope
        let actual = encoded (nodesWith "1250m" "3Gi")
            selected = pod "selected" "platform" worker [container "main" "100m" "128Mi" "2" "3584Mi"] []
            bounded = pod "bounded" "platform" worker [container "main" "100m" "128Mi" "2" "3Gi"] []
        expectRefusal
          "effective Pod memory limit"
          (validateAdmittedPodBudgets LinuxCPU profile envelope actual (inventory [selected]))
        _ <-
          either
            (assertFailure . Text.unpack)
            pure
            (validateAdmittedPodBudgets LinuxCPU profile envelope actual (inventory [bounded]))
        pure ()
    , testCase "aggregate limit overcommit is reported against lower observed memory" $ do
        envelope <- checkedEnvelope
        let actual = encoded (nodesWith "1250m" "3Gi")
            individuallyFitting name = pod name "platform" worker [container "main" "100m" "128Mi" "2" "2Gi"] []
        report <-
          either (assertFailure . Text.unpack) pure $
            validateAdmittedPodBudgets
              LinuxCPU
              profile
              envelope
              actual
              (inventory [individuallyFitting "one", individuallyFitting "two"])
        podBudgetLimitsOvercommitNodes report @?= True
    ]

profile :: ClusterResources
profile =
  defaultClusterResources
    { nodeMemoryMiB = 5120
    , nodeCpus = "1.5"
    , jobMemoryMiB = 4096
    , jobCpus = "1"
    , scheduleOnControlPlane = True
    }

checkedEnvelope :: IO ResourceEnvelope
checkedEnvelope =
  either
    (assertFailure . Text.unpack)
    pure
    (validateResourceEnvelope (RuntimeCapacity 4 (16 * 1073741824)) profile)

accepted :: [Value] -> IO PodBudgetReport
accepted pods = do
  envelope <- checkedEnvelope
  either
    (assertFailure . Text.unpack)
    pure
    (validateAdmittedPodBudgets LinuxCPU profile envelope (encoded nodes) (inventory pods))

refuses :: Text -> [Value] -> Assertion
refuses fragment pods = do
  envelope <- checkedEnvelope
  expectRefusal
    fragment
    (validateAdmittedPodBudgets LinuxCPU profile envelope (encoded nodes) (inventory pods))

expectRefusal :: Text -> Either Text value -> Assertion
expectRefusal fragment result = case result of
  Left reason -> assertBool ("unexpected refusal: " <> Text.unpack reason) (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure ("expected resource refusal: " <> Text.unpack fragment)

workerBudget :: PodBudgetReport -> IO NodePodBudget
workerBudget report = maybe (assertFailure "worker budget missing") pure (Map.lookup worker (podBudgetPerNode report))

controlPlane, worker :: Text
controlPlane = "jitml-linux-cpu-control-plane"
worker = "jitml-linux-cpu-worker"

nodes :: Value
nodes = nodesWith "1250m" "4Gi"

nodesWith :: Text -> Text -> Value
nodesWith cpu memory =
  object
    [ "apiVersion" .= ("v1" :: Text)
    , "kind" .= ("List" :: Text)
    , "items" .= [node controlPlane False, node worker True]
    ]
 where
  node name compute =
    object
      [ "metadata"
          .= object
            [ "name" .= name
            , "labels" .= object ["jitml.node-role/compute" .= if compute then ("true" :: Text) else "false"]
            ]
      , "spec" .= object []
      , "status"
          .= object ["allocatable" .= object ["cpu" .= cpu, "memory" .= memory], "conditions" .= [ready]]
      ]

app :: Value
app = pod "app" "platform" worker [mainContainer] []

withMain :: Text -> Text -> Text -> Value
withMain name cpu memory = pod name "platform" worker [container "main" cpu memory "2" memory] []

mainContainer :: Value
mainContainer = container "main" "100m" "128Mi" "250m" "256Mi"

large :: Text -> Value
large name = container name "100m" "128Mi" "1" "2560Mi"

container :: Text -> Text -> Text -> Text -> Text -> Value
container name cpu memory cpuLimit memoryLimit = object ["name" .= name, "resources" .= resources cpu memory cpuLimit memoryLimit]

resources :: Text -> Text -> Text -> Text -> Value
resources cpu memory cpuLimit memoryLimit =
  object
    [ "requests" .= object ["cpu" .= cpu, "memory" .= memory]
    , "limits" .= object ["cpu" .= cpuLimit, "memory" .= memoryLimit]
    ]

pod :: Text -> Text -> Text -> [Value] -> [Value] -> Value
pod name namespace node containers initial =
  object
    [ "apiVersion" .= ("v1" :: Text)
    , "kind" .= ("Pod" :: Text)
    , "metadata" .= object ["name" .= name, "namespace" .= namespace, "uid" .= ("uid-" <> name)]
    , "spec" .= object ["nodeName" .= node, "containers" .= containers, "initContainers" .= initial]
    , "status" .= object ["phase" .= ("Running" :: Text), "conditions" .= [ready]]
    ]

ready :: Value
ready = object ["type" .= ("Ready" :: Text), "status" .= ("True" :: Text)]

notReady :: Value -> Value
notReady =
  set
    ["status", "conditions"]
    (Aeson.toJSON [object ["type" .= ("Ready" :: Text), "status" .= ("False" :: Text)]])

jobOwner :: Value
jobOwner =
  object
    [ "kind" .= ("Job" :: Text)
    , "name" .= ("completed" :: Text)
    , "uid" .= ("uid-job" :: Text)
    , "controller" .= True
    ]

set :: [Key] -> Value -> Value -> Value
set [] replacement _ = replacement
set (key : rest) replacement (Object values) =
  Object
    (KeyMap.insert key (set rest replacement (fromMaybe (object []) (KeyMap.lookup key values))) values)
set _ _ value = value

encoded :: Value -> Text
encoded = Encoding.decodeUtf8 . Lazy.toStrict . Aeson.encode

inventory :: [Value] -> Text
inventory pods = encoded (object ["apiVersion" .= ("v1" :: Text), "kind" .= ("PodList" :: Text), "items" .= pods])

mib :: Integer -> Integer
mib = (* 1048576)
