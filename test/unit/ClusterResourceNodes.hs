{-# LANGUAGE OverloadedStrings #-}

module ClusterResourceNodes (tests) where

import Data.Aeson (Value, object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))

import JitML.Cluster.ResourceBudget
  ( ResourceEnvelope
  , RuntimeCapacity (..)
  , validateResourceEnvelope
  )
import JitML.Cluster.ResourceNodes (validateNodeAllocatable, validateNodeHardCaps)
import JitML.Cluster.Resources (ClusterResources (..), defaultClusterResources)
import JitML.Substrate (Substrate (LinuxCPU))

tests :: TestTree
tests =
  testGroup
    "observed node resource capacity"
    [ testCase "exact ready nodes with capped allocatable resources pass" $ do
        envelope <- checkedEnvelope profile
        validateNodeAllocatable LinuxCPU profile envelope (inventory [controlPlane, worker]) @?= Right ()
    , testCase "allocatable resources below the ceiling are accepted without rewriting them" $ do
        envelope <- checkedEnvelope profile
        let smaller = worker {cpu = "3000m", memory = "10Gi"}
        validateNodeAllocatable LinuxCPU profile envelope (inventory [controlPlane, smaller]) @?= Right ()
    , testCase "VM-wide CPU cannot masquerade as a capped node" $ do
        envelope <- checkedEnvelope profile
        refuses "allocatable CPU exceeds" envelope [controlPlane, worker {cpu = "8"}]
    , testCase "VM-wide memory cannot masquerade as a capped node" $ do
        envelope <- checkedEnvelope profile
        refuses "allocatable memory exceeds" envelope [controlPlane, worker {memory = "32Gi"}]
    , testCase "missing duplicate and unexpected nodes refuse" $ do
        envelope <- checkedEnvelope profile
        refuses "exact selected Kind topology" envelope [worker]
        refuses "duplicate names" envelope [controlPlane, worker, worker]
        refuses "exact selected Kind topology" envelope [controlPlane, worker {name = "foreign-worker"}]
    , testCase "worker compute ownership is required and cannot move onto the control-plane" $ do
        envelope <- checkedEnvelope profile
        refuses "worker must carry" envelope [controlPlane, worker {compute = False}]
        refuses "control-plane must not carry" envelope [controlPlane {compute = True}, worker]
    , testCase "workers must remain ready and uncordoned" $ do
        envelope <- checkedEnvelope profile
        refuses "Ready=True" envelope [controlPlane, worker {ready = "False"}]
        refuses "cordoned" envelope [controlPlane, worker {unschedulable = True}]
    , testCase "NoSchedule and NoExecute taints prevent worker admission" $ do
        envelope <- checkedEnvelope profile
        mapM_
          (\effect -> refuses "taint" envelope [controlPlane, worker {taints = [effect]}])
          ["NoSchedule", "NoExecute"]
    , testCase "control-plane scheduling must agree with the selected profile" $ do
        envelope <- checkedEnvelope profile
        refuses "scheduling eligibility" envelope [controlPlane {taints = ["NoSchedule"]}, worker]
        refuses "scheduling eligibility" envelope [controlPlane {unschedulable = True}, worker]
        let taintedProfile = profile {scheduleOnControlPlane = False}
        taintedEnvelope <- checkedEnvelope taintedProfile
        validateNodeAllocatable
          LinuxCPU
          taintedProfile
          taintedEnvelope
          (inventory [controlPlane {taints = ["NoSchedule"]}, worker])
          @?= Right ()
        refusesWith taintedProfile "scheduling eligibility" taintedEnvelope [controlPlane, worker]
    , testCase "PreferNoSchedule does not become an absolute placement prohibition" $ do
        envelope <- checkedEnvelope profile
        validateNodeAllocatable
          LinuxCPU
          profile
          envelope
          (inventory [controlPlane, worker {taints = ["PreferNoSchedule"]}])
          @?= Right ()
    , testCase "missing duplicate or unknown Ready conditions refuse" $ do
        envelope <- checkedEnvelope profile
        refuses "Ready=True" envelope [controlPlane, worker {conditionCount = 0}]
        refuses "Ready=True" envelope [controlPlane, worker {conditionCount = 2}]
        refuses "Ready=True" envelope [controlPlane, worker {ready = "Unknown"}]
    , testCase "zero and malformed allocatable quantities refuse" $ do
        envelope <- checkedEnvelope profile
        refuses "allocatable CPU" envelope [controlPlane, worker {cpu = "0"}]
        refuses "allocatable memory" envelope [controlPlane, worker {memory = "512MB"}]
    , testCase "malformed inventory and null optional fields refuse instead of defaulting" $ do
        envelope <- checkedEnvelope profile
        let valid = inventory [controlPlane, worker]
        refusesRaw "invalid node inventory JSON" envelope "{}"
        refusesRaw
          "invalid node inventory JSON"
          envelope
          (Text.replace "\"unschedulable\":false" "\"unschedulable\":null" valid)
        refusesRaw
          "invalid node inventory JSON"
          envelope
          (Text.replace "\"cpu\":\"3750m\"" "\"cpu\":3750" valid)
    , testCase "selected Docker node caps pass with exact memory CPU and no swap" $ do
        validateNodeHardCaps LinuxCPU profile (capInventory [workerCaps, controlPlaneCaps]) @?= Right ()
    , testCase "removed raised or stale Docker memory caps refuse" $
        mapM_
          (\amount -> refusesCaps "Docker Memory differs" [controlPlaneCaps, workerCaps {capMemory = amount}])
          [0, 12884901889, 12884901887]
    , testCase "unlimited enabled or mismatched Docker swap refuses" $
        mapM_
          (\amount -> refusesCaps "MemorySwap" [controlPlaneCaps, workerCaps {capMemorySwap = amount}])
          [-1, 0, 25769803776]
    , testCase "removed raised or stale Docker CPU caps refuse" $
        mapM_
          (\amount -> refusesCaps "NanoCpus" [controlPlaneCaps, workerCaps {capNanoCpus = amount}])
          [0, 8000000000, 3999999999]
    , testCase "Docker cap names must exactly cover the selected nodes once" $ do
        refusesCaps "exact selected Kind topology" [workerCaps]
        refusesCaps "duplicate names" [controlPlaneCaps, workerCaps, workerCaps]
        mapM_
          ( \changedName ->
              refusesCaps "exact selected Kind topology" [controlPlaneCaps, workerCaps {capName = changedName}]
          )
          ["foreign-worker", Text.drop 1 (capName workerCaps), "/" <> capName workerCaps]
    , testCase "Docker cap fields must be present non-null integer JSON values" $ do
        let valid = capInventory [controlPlaneCaps, workerCaps]
        mapM_
          ( \(before, after) -> refusesCapsRaw "invalid Docker node inspect JSON" (Text.replace before after valid)
          )
          [ ("\"Memory\":12884901888", "\"Memory\":null")
          , ("\"Memory\":12884901888", "\"Memory\":\"12884901888\"")
          , ("\"Memory\":12884901888", "\"Memory\":12884901888.5")
          , ("\"NanoCpus\":4000000000", "\"other\":4000000000")
          , ("\"MemorySwap\":12884901888", "\"MemorySwap\":false")
          ]
        refusesCapsRaw "invalid Docker node inspect JSON" "[]\n"
    , testCase "Docker cap evidence rejects blank empty and partially malformed receipts" $ do
        refusesCapsRaw "evidence is empty" ""
        refusesCapsRaw "blank lines" (capInventory [controlPlaneCaps] <> "\n" <> capInventory [workerCaps])
        refusesCapsRaw
          "invalid Docker node inspect JSON on line 2"
          (capInventory [controlPlaneCaps] <> "{broken}\n")
    , testCase "selected fractional CPU budget determines the exact Docker NanoCpus" $ do
        let fractional = profile {nodeCpus = "1250m"}
            caps = fmap (\selected -> selected {capNanoCpus = 1250000000}) [controlPlaneCaps, workerCaps]
        validateNodeHardCaps LinuxCPU fractional (capInventory caps) @?= Right ()
        expectRefusal
          "NanoCpus"
          (validateNodeHardCaps LinuxCPU fractional (capInventory [controlPlaneCaps, workerCaps]))
    , testCase "stopped paused or restarting Docker nodes cannot pass on stale Kubernetes readiness" $
        mapM_
          (\changed -> refusesCaps "Docker node must be running" [controlPlaneCaps, changed])
          [ workerCaps {capRunning = False}
          , workerCaps {capPaused = True}
          , workerCaps {capRestarting = True}
          ]
    , testCase "Docker node state requires a positive live PID" $
        mapM_
          (\pid -> refusesCaps "positive PID" [controlPlaneCaps {capPid = pid}, workerCaps])
          [0, -1]
    , testCase "all Docker live-state fields are mandatory and strictly typed" $ do
        let valid = capInventory [controlPlaneCaps, workerCaps]
        mapM_
          ( \(before, after) -> refusesCapsRaw "invalid Docker node inspect JSON" (Text.replace before after valid)
          )
          [ ("\"Running\":true", "\"Running\":null")
          , ("\"Running\":true", "\"Running\":\"true\"")
          , ("\"Paused\":false", "\"Paused\":0")
          , ("\"Restarting\":false", "\"other\":false")
          , ("\"Pid\":42", "\"Pid\":\"42\"")
          , ("\"Pid\":42", "\"Pid\":42.5")
          ]
    ]

profile :: ClusterResources
profile = defaultClusterResources {scheduleOnControlPlane = True}

checkedEnvelope :: ClusterResources -> IO ResourceEnvelope
checkedEnvelope resources =
  either (assertFailure . Text.unpack) pure $
    validateResourceEnvelope (RuntimeCapacity 16 (64 * 1024 * 1024 * 1024)) resources

data Fixture = Fixture
  { name :: Text
  , compute :: Bool
  , cpu :: Text
  , memory :: Text
  , ready :: Text
  , unschedulable :: Bool
  , taints :: [Text]
  , conditionCount :: Int
  }

controlPlane, worker :: Fixture
controlPlane = Fixture "jitml-linux-cpu-control-plane" False "3750m" "11Gi" "True" False [] 1
worker = Fixture "jitml-linux-cpu-worker" True "3750m" "11Gi" "True" False [] 1

inventory :: [Fixture] -> Text
inventory nodes =
  Text.Encoding.decodeUtf8 . LazyByteString.toStrict . Aeson.encode $
    object ["apiVersion" .= ("v1" :: Text), "kind" .= ("List" :: Text), "items" .= fmap fixture nodes]

fixture :: Fixture -> Value
fixture node =
  object
    [ "metadata"
        .= object
          [ "name" .= name node
          , "labels"
              .= object ["jitml.node-role/compute" .= if compute node then ("true" :: Text) else "false"]
          ]
    , "spec"
        .= object
          [ "unschedulable" .= unschedulable node
          , "taints" .= fmap (\effect -> object ["key" .= ("test" :: Text), "effect" .= effect]) (taints node)
          ]
    , "status"
        .= object
          [ "allocatable" .= object ["cpu" .= cpu node, "memory" .= memory node]
          , "conditions"
              .= replicate (conditionCount node) (object ["type" .= ("Ready" :: Text), "status" .= ready node])
          ]
    ]

refuses :: Text -> ResourceEnvelope -> [Fixture] -> Assertion
refuses = refusesWith profile

refusesWith :: ClusterResources -> Text -> ResourceEnvelope -> [Fixture] -> Assertion
refusesWith resources fragment envelope nodes =
  expectRefusal fragment (validateNodeAllocatable LinuxCPU resources envelope (inventory nodes))

refusesRaw :: Text -> ResourceEnvelope -> Text -> Assertion
refusesRaw fragment envelope raw =
  expectRefusal fragment (validateNodeAllocatable LinuxCPU profile envelope raw)

expectRefusal :: Text -> Either Text () -> Assertion
expectRefusal fragment result =
  case result of
    Left reason -> assertBool ("unexpected refusal: " <> Text.unpack reason) (fragment `Text.isInfixOf` reason)
    Right () -> assertFailure ("node scheduler guard accepted; expected " <> Text.unpack fragment)

data CapFixture = CapFixture
  { capName :: Text
  , capMemory :: Integer
  , capMemorySwap :: Integer
  , capNanoCpus :: Integer
  , capRunning :: Bool
  , capPaused :: Bool
  , capRestarting :: Bool
  , capPid :: Integer
  }

controlPlaneCaps, workerCaps :: CapFixture
controlPlaneCaps =
  CapFixture "/jitml-linux-cpu-control-plane" 12884901888 12884901888 4000000000 True False False 42
workerCaps = CapFixture "/jitml-linux-cpu-worker" 12884901888 12884901888 4000000000 True False False 43

capInventory :: [CapFixture] -> Text
capInventory =
  Text.unlines . fmap (Text.Encoding.decodeUtf8 . LazyByteString.toStrict . Aeson.encode . capFixture)
 where
  capFixture selected =
    object
      [ "Name" .= capName selected
      , "Memory" .= capMemory selected
      , "MemorySwap" .= capMemorySwap selected
      , "NanoCpus" .= capNanoCpus selected
      , "Running" .= capRunning selected
      , "Paused" .= capPaused selected
      , "Restarting" .= capRestarting selected
      , "Pid" .= capPid selected
      ]

refusesCaps :: Text -> [CapFixture] -> Assertion
refusesCaps fragment = refusesCapsRaw fragment . capInventory

refusesCapsRaw :: Text -> Text -> Assertion
refusesCapsRaw fragment raw = expectRefusal fragment (validateNodeHardCaps LinuxCPU profile raw)
