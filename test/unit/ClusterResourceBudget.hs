{-# LANGUAGE OverloadedStrings #-}

module ClusterResourceBudget (tests) where

import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Dhall qualified
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Cluster.ResourceBudget
  ( ResourceEnvelope (..)
  , RuntimeCapacity (..)
  , WorkloadBudget (..)
  , WorkloadPlacement (..)
  , kubeletSystemReservation
  , parseCpuMilli
  , parseMemoryBytes
  , validateResourceEnvelope
  , validateWorkloadRequests
  )
import JitML.Cluster.Resources
  ( ClusterResources (..)
  , ComponentBudget (..)
  , clusterResourcesDecoder
  , clusterResourcesPath
  , defaultClusterResources
  , resolveClusterResourcesPath
  )
import JitML.Service.BootConfig qualified as Boot
import JitML.Substrate (Substrate (LinuxCPU))

tests :: TestTree
tests =
  testGroup
    "cluster resource envelope"
    [ testCase "two 12 GiB nodes refuse a 16 GiB runtime before rollout" $
        refuses "memory exceeds" (validateResourceEnvelope runtime16 defaultClusterResources)
    , testCase "checked-in default and Small16 Dhall decode to their validated budgets" $ do
        canonical <- Dhall.inputFile clusterResourcesDecoder clusterResourcesPath
        canonical @?= defaultClusterResources
        selected <- Dhall.inputFile clusterResourcesDecoder "dhall/cluster/mac16.dhall"
        selected @?= small16
    , testCase "selected numerical Job budget survives mounted BootConfig transport" $ do
        selected <- Dhall.inputFile clusterResourcesDecoder "dhall/cluster/mac16.dhall"
        let boot =
              (Boot.defaultBootConfig LinuxCPU Boot.Cluster)
                { Boot.bootNumericalWorkload = numericalWorkload selected
                }
        withSystemTempDirectory "jitml-workload-budget" $ \directory -> do
          let path = directory </> "BootConfig.dhall"
          Text.IO.writeFile path (Boot.renderBootConfigDhall boot)
          decoded <- Boot.loadBootConfig path
          Boot.bootNumericalWorkload decoded @?= numericalWorkload selected
        assertBool "inverted mounted numerical memory budget accepted" $
          isLeft
            ( Boot.validateBootConfig
                (boot {Boot.bootNumericalWorkload = (numericalWorkload selected) {budgetMemoryRequest = "2Gi"}})
            )
        _ <- accepted (validateResourceEnvelope runtime16 selected)
        pure ()
    , testCase "profile selection preserves explicit coordinates and rejects blank overrides" $ do
        resolveClusterResourcesPath "/repo" Nothing @?= Right "/repo/dhall/cluster/resources.dhall"
        resolveClusterResourcesPath "/repo" (Just "dhall/cluster/mac16.dhall")
          @?= Right "/repo/dhall/cluster/mac16.dhall"
        resolveClusterResourcesPath "/repo" (Just "/profiles/local.dhall") @?= Right "/profiles/local.dhall"
        mapM_
          (assertBool "blank selected profile accepted" . isLeft . resolveClusterResourcesPath "/repo" . Just)
          ["", " ", " local.dhall"]
    , testCase "Small16 fits its hard nodes, caller and runtime reserve" $ do
        envelope <- accepted (validateResourceEnvelope runtime16 small16)
        envelopeNodeCount envelope @?= 2
        envelopeHardMemoryBytes envelope @?= 15872 * mib
        envelopeHardCpuMilli envelope @?= 4000
        envelopeMemoryHeadroomBytes envelope @?= 512 * mib
        envelopeNodeApplicationMemoryBytes envelope @?= 4096 * mib
        envelopeNodeApplicationCpuMilli envelope @?= 1250
    , testCase "kubelet reservations use exact observed runtime bytes rather than a configured VM label" $ do
        envelope <- accepted (validateResourceEnvelope (RuntimeCapacity 4 16733499392) small16)
        kubeletSystemReservation envelope @?= ("2750m", "12438532096")
    , testCase "default large profile excludes runtime capacity outside its hard node" $ do
        envelope <-
          accepted (validateResourceEnvelope (RuntimeCapacity 16 (64 * gib)) defaultClusterResources)
        kubeletSystemReservation envelope @?= ("12250m", "56908316672")
    , testCase "the same node profile adjusts reservations for a different observed VM" $ do
        sixteen <- accepted (validateResourceEnvelope runtime16 small16)
        thirtyTwo <- accepted (validateResourceEnvelope (RuntimeCapacity 8 (32 * gib)) small16)
        kubeletSystemReservation sixteen @?= ("2750m", "12884901888")
        kubeletSystemReservation thirtyTwo @?= ("6750m", "30064771072")
    , testCase
        "runtime capacity minus kubelet reservations equals the declared per-node application budget"
        $ mapM_
          ( \(capacity, resources) -> do
              envelope <- accepted (validateResourceEnvelope capacity resources)
              let (cpu, memory) = kubeletSystemReservation envelope
              reservedCpu <- accepted (parseCpuMilli cpu)
              reservedMemory <- accepted (parseMemoryBytes memory)
              toInteger (runtimeCpuCount capacity) * 1000
                - reservedCpu
                  @?= envelopeNodeApplicationCpuMilli envelope
              runtimeMemoryBytes capacity
                - reservedMemory
                  @?= envelopeNodeApplicationMemoryBytes envelope
          )
          [ (RuntimeCapacity 4 16733499392, small16)
          , (runtime16, small16)
          , (RuntimeCapacity 8 (32 * gib), small16)
          , (RuntimeCapacity 16 (64 * gib), defaultClusterResources)
          ]
    , testCase "actual Docker MemTotal controls admission rather than a configured VM label" $
        refuses "memory exceeds" (validateResourceEnvelope (RuntimeCapacity 4 (15 * gib)) small16)
    , testCase "individually bounded nodes cannot overbook runtime CPU with the caller" $
        refuses "CPU exceeds" (validateResourceEnvelope runtime16 (small16 {nodeCpus = "2"}))
    , testCase "CPU quantities preserve exact millicores and refuse fractional millicores" $ do
        parseCpuMilli "0.5" @?= Right 500
        parseCpuMilli "1e-3" @?= Right 1
        parseCpuMilli "1000m" @?= Right 1000
        mapM_
          (assertBool "invalid CPU quantity accepted" . isLeft . parseCpuMilli)
          ["0.0005", "500Mi", "NaN", "-1", "0", " 1"]
    , testCase "memory quantities distinguish binary and decimal units without rounding" $ do
        parseMemoryBytes "1.5Gi" @?= Right (1536 * mib)
        parseMemoryBytes "1G" @?= Right 1000000000
        parseMemoryBytes "1e6" @?= Right 1000000
        mapM_
          (assertBool "invalid memory quantity accepted" . isLeft . parseMemoryBytes)
          ["0.1", "512MB", "2 Gi", "-1Mi", "1e999999"]
    , testCase "numerical workloads must fit a node and retain serial compute cardinality" $ do
        refuses "memory limit exceeds" $
          validateResourceEnvelope
            runtime16
            (small16 {numericalWorkload = (numericalWorkload small16) {budgetMemoryLimit = "5Gi"}})
        refuses "exactly one serial worker" $
          validateResourceEnvelope
            runtime16
            (small16 {numericalWorkload = (numericalWorkload small16) {budgetReplicas = 2}})
    , testCase "component requests cannot exceed their finite limits" $
        refuses "memory request exceeds limit" $
          validateResourceEnvelope runtime16 (small16 {minio = (minio small16) {budgetMemoryLimit = "128Mi"}})
    , testCase "Engine CPU request must fit a worker after its node-system reserve" $
        refuses "jitmlService: request exceeds per-node application CPU" $
          validateResourceEnvelope
            runtime16
            (small16 {jitmlService = (jitmlService small16) {budgetCpuRequest = "1300m"}})
    , testCase "Engine replicas cannot borrow the control-plane node" $
        refuses "replicas <= workerCount" $
          validateResourceEnvelope
            runtime16
            (small16 {jitmlService = (jitmlService small16) {budgetReplicas = 2}})
    , testCase "zero replicas and reserves that consume an entire node refuse" $ do
        assertBool "zero supporting replicas accepted" $
          isLeft
            ( validateResourceEnvelope
                runtime16
                (small16 {supporting = (supporting small16) {budgetReplicas = 0}})
            )
        refuses "leaves no application capacity" $
          validateResourceEnvelope runtime16 (small16 {nodeSystemMemoryMiB = 5120})
    , testCase "aggregate pod limits can overcommit a worker while each pod fits" $ do
        envelope <- accepted (validateResourceEnvelope runtime16 small16)
        let supplied = [WorkloadBudget "worker-pods" ComputeWorkerNodes (ComponentBudget 2 "100m" "500m" "128Mi" "3Gi")]
        assertBool
          "aggregate limits must exceed the worker's hard parent cap"
          (6 * gib > envelopeNodeMemoryBytes envelope)
        validateWorkloadRequests envelope supplied @?= Right ()
        assertBool "overcommit policy hidden" (envelopePodLimitsMayOvercommit envelope)
    , testCase "one pod's limit cannot consume the node-system reserve" $ do
        refuses "memory limit exceeds per-node application memory" $
          validateResourceEnvelope
            runtime16
            (small16 {jitmlDemo = (jitmlDemo small16) {budgetMemoryLimit = "5Gi"}})
        envelope <- accepted (validateResourceEnvelope runtime16 small16)
        refuses "memory limit cannot fit one eligible node" $
          validateWorkloadRequests
            envelope
            [WorkloadBudget "oversized-pod" AnySchedulableNode (ComponentBudget 1 "100m" "500m" "128Mi" "5Gi")]
    , testCase "rendered worker-only requests cannot consume control-plane capacity" $ do
        envelope <- accepted (validateResourceEnvelope runtime16 small16)
        refuses "worker-only requests exceed" $
          validateWorkloadRequests
            envelope
            [WorkloadBudget "worker-pods" ComputeWorkerNodes (ComponentBudget 2 "100m" "500m" "3Gi" "3Gi")]
    , testCase "control-plane eligibility changes rendered aggregate request capacity" $ do
        both <- accepted (validateResourceEnvelope runtime16 small16)
        worker <- accepted (validateResourceEnvelope runtime16 (small16 {scheduleOnControlPlane = False}))
        let supplied = [WorkloadBudget "platform-pods" AnySchedulableNode (ComponentBudget 2 "100m" "500m" "3Gi" "3Gi")]
        validateWorkloadRequests both supplied @?= Right ()
        refuses "schedulable-node memory" (validateWorkloadRequests worker supplied)
    ]

runtime16 :: RuntimeCapacity
runtime16 = RuntimeCapacity 4 (16 * gib)

mib, gib :: Integer
mib = 1048576
gib = 1024 * mib

small16 :: ClusterResources
small16 =
  defaultClusterResources
    { nodeMemoryMiB = 5120
    , nodeCpus = "1.5"
    , workerCount = 1
    , jobMemoryMiB = 4096
    , jobCpus = "1"
    , systemReserveMiB = 1536
    , nodeSystemMemoryMiB = 1024
    , nodeSystemCpus = "250m"
    , scheduleOnControlPlane = True
    , registry = ComponentBudget 1 "50m" "500m" "128Mi" "512Mi"
    , minio = ComponentBudget 1 "100m" "500m" "256Mi" "1Gi"
    , pulsar = ComponentBudget 1 "50m" "500m" "128Mi" "1Gi"
    , prometheus = ComponentBudget 1 "50m" "500m" "256Mi" "1Gi"
    , grafana = ComponentBudget 1 "25m" "250m" "128Mi" "512Mi"
    , jitmlService = ComponentBudget 1 "200m" "2" "512Mi" "2Gi"
    , jitmlDemo = ComponentBudget 1 "100m" "2" "512Mi" "3Gi"
    , tensorboard = ComponentBudget 1 "25m" "250m" "128Mi" "512Mi"
    , supporting = ComponentBudget 1 "25m" "250m" "64Mi" "512Mi"
    , gateway = ComponentBudget 1 "25m" "500m" "128Mi" "1Gi"
    , numericalWorkload = ComponentBudget 1 "250m" "1" "1Gi" "1536Mi"
    }

accepted :: Either Text value -> IO value
accepted = either (assertFailure . Text.unpack) pure

refuses :: Text -> Either Text value -> Assertion
refuses fragment result = case result of
  Left reason -> assertBool ("unexpected refusal: " <> Text.unpack reason) (fragment `Text.isInfixOf` reason)
  Right _ -> assertFailure ("resource envelope accepted; expected " <> Text.unpack fragment)
