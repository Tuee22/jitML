{-# LANGUAGE OverloadedStrings #-}

-- | Sprint 2.8 — typed cluster resource profile. A single Dhall-sourced budget
-- bounds the kind cluster so an over-budget bootstrap cannot exhaust the host
-- (the 2026-05-29 OOM-storm incident). The profile carries the kind-node
-- memory/CPU cap and per-component pod budgets/replica counts; it is decoded
-- from @dhall/cluster/resources.dhall@ via 'Dhall.inputFile' the same way
-- 'JitML.Service.BootConfig.loadBootConfig' and 'JitML.Numerics.Schema' read
-- their typed Dhall, and materialized to @./.build/conf/cluster/Resources.dhall@
-- for visibility. The node cap is applied by the bootstrap reconciler through a
-- typed @docker update@ subprocess after @kind create@.
module JitML.Cluster.Resources
  ( ClusterResources (..)
  , ComponentBudget (..)
  , clusterResourcesPath
  , clusterResourcesDecoder
  , defaultClusterResources
  , loadClusterResourcesOrDefault
  , renderClusterResourcesDhall
  , nodeMemoryBytes
  , clusterNodeCapSubprocess
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import JitML.Sub.Subprocess (Subprocess, subprocess)
import JitML.Substrate (Substrate, substrateClusterName)

-- | Per-component pod budget: replica count plus Kubernetes resource
-- requests/limits in k8s quantity strings (e.g. @"250m"@, @"512Mi"@).
data ComponentBudget = ComponentBudget
  { budgetReplicas :: Int
  , budgetCpuRequest :: Text
  , budgetCpuLimit :: Text
  , budgetMemoryRequest :: Text
  , budgetMemoryLimit :: Text
  }
  deriving stock (Eq, Show)

-- | The whole-cluster resource profile. @nodeMemoryMiB@ / @nodeCpus@ bound the
-- single kind node container; the per-component budgets size the platform pods
-- so their sum stays under the node cap.
data ClusterResources = ClusterResources
  { nodeMemoryMiB :: Int
  , nodeCpus :: Text
  , harbor :: ComponentBudget
  , minio :: ComponentBudget
  , pulsar :: ComponentBudget
  , postgres :: ComponentBudget
  , prometheus :: ComponentBudget
  , grafana :: ComponentBudget
  , jitmlService :: ComponentBudget
  , jitmlDemo :: ComponentBudget
  , tensorboard :: ComponentBudget
  }
  deriving stock (Eq, Show)

-- | Repo-relative path to the checked-in source profile.
clusterResourcesPath :: FilePath
clusterResourcesPath = "dhall/cluster/resources.dhall"

componentBudgetDecoder :: Dhall.Decoder ComponentBudget
componentBudgetDecoder =
  Dhall.record $
    ComponentBudget
      <$> fmap fromIntegral (Dhall.field "replicas" Dhall.natural)
      <*> Dhall.field "cpuRequest" Dhall.strictText
      <*> Dhall.field "cpuLimit" Dhall.strictText
      <*> Dhall.field "memoryRequest" Dhall.strictText
      <*> Dhall.field "memoryLimit" Dhall.strictText

clusterResourcesDecoder :: Dhall.Decoder ClusterResources
clusterResourcesDecoder =
  Dhall.record $
    ClusterResources
      <$> fmap fromIntegral (Dhall.field "nodeMemoryMiB" Dhall.natural)
      <*> Dhall.field "nodeCpus" Dhall.strictText
      <*> Dhall.field "harbor" componentBudgetDecoder
      <*> Dhall.field "minio" componentBudgetDecoder
      <*> Dhall.field "pulsar" componentBudgetDecoder
      <*> Dhall.field "postgres" componentBudgetDecoder
      <*> Dhall.field "prometheus" componentBudgetDecoder
      <*> Dhall.field "grafana" componentBudgetDecoder
      <*> Dhall.field "jitmlService" componentBudgetDecoder
      <*> Dhall.field "jitmlDemo" componentBudgetDecoder
      <*> Dhall.field "tensorboard" componentBudgetDecoder

-- | Fallback profile used when the source Dhall is absent and for the pure
-- plan/dry-run path. Sized for a ~16 GiB single-node host: a ~10 GiB node cap
-- with the heavy subcharts right-sized so the sum of pod limits stays under it.
defaultClusterResources :: ClusterResources
defaultClusterResources =
  ClusterResources
    { nodeMemoryMiB = 10240
    , nodeCpus = "6"
    , harbor = ComponentBudget 1 "100m" "500m" "256Mi" "512Mi"
    , minio = ComponentBudget 1 "100m" "500m" "512Mi" "1Gi"
    , pulsar = ComponentBudget 1 "100m" "500m" "512Mi" "1Gi"
    , postgres = ComponentBudget 1 "200m" "500m" "512Mi" "1Gi"
    , prometheus = ComponentBudget 1 "100m" "500m" "512Mi" "1Gi"
    , grafana = ComponentBudget 1 "50m" "250m" "256Mi" "512Mi"
    , jitmlService = ComponentBudget 1 "500m" "2" "1Gi" "2Gi"
    , jitmlDemo = ComponentBudget 1 "50m" "250m" "128Mi" "256Mi"
    , tensorboard = ComponentBudget 1 "50m" "250m" "256Mi" "512Mi"
    }

-- | Load the source profile from @<repoRoot>/dhall/cluster/resources.dhall@,
-- falling back to 'defaultClusterResources' when the file is absent.
loadClusterResourcesOrDefault :: FilePath -> IO ClusterResources
loadClusterResourcesOrDefault repoRoot = do
  let path = repoRoot </> clusterResourcesPath
  present <- doesFileExist path
  if present
    then Dhall.inputFile clusterResourcesDecoder path
    else pure defaultClusterResources

-- | Render a profile back to a Dhall record literal (used to materialize the
-- resolved snapshot under @./.build/conf/cluster/@).
renderClusterResourcesDhall :: ClusterResources -> Text
renderClusterResourcesDhall res =
  Text.unlines
    [ "{ nodeMemoryMiB = " <> Text.pack (show (nodeMemoryMiB res))
    , ", nodeCpus = " <> quote (nodeCpus res)
    , ", harbor = " <> renderBudget (harbor res)
    , ", minio = " <> renderBudget (minio res)
    , ", pulsar = " <> renderBudget (pulsar res)
    , ", postgres = " <> renderBudget (postgres res)
    , ", prometheus = " <> renderBudget (prometheus res)
    , ", grafana = " <> renderBudget (grafana res)
    , ", jitmlService = " <> renderBudget (jitmlService res)
    , ", jitmlDemo = " <> renderBudget (jitmlDemo res)
    , ", tensorboard = " <> renderBudget (tensorboard res)
    , "}"
    ]
 where
  quote t = "\"" <> t <> "\""
  renderBudget b =
    Text.concat
      [ "{ replicas = "
      , Text.pack (show (budgetReplicas b))
      , ", cpuRequest = "
      , quote (budgetCpuRequest b)
      , ", cpuLimit = "
      , quote (budgetCpuLimit b)
      , ", memoryRequest = "
      , quote (budgetMemoryRequest b)
      , ", memoryLimit = "
      , quote (budgetMemoryLimit b)
      , " }"
      ]

-- | Node cap in bytes (docker @--memory@ takes raw bytes).
nodeMemoryBytes :: ClusterResources -> Integer
nodeMemoryBytes res = toInteger (nodeMemoryMiB res) * 1048576

-- | Typed @docker update@ that caps the kind node container's memory and CPU
-- from the profile. @--memory-swap == --memory@ disables swap thrash so an
-- over-budget cluster OOM-kills its own pods inside the node cgroup rather than
-- taking down the host. Runs after @kind create@; the reconciler stops at the
-- first failed step, so a cap that cannot be applied fails the bootstrap closed.
clusterNodeCapSubprocess :: Substrate -> ClusterResources -> Subprocess
clusterNodeCapSubprocess substrate res =
  subprocess
    "docker"
    [ "update"
    , "--memory"
    , bytes
    , "--memory-swap"
    , bytes
    , "--cpus"
    , nodeCpus res
    , substrateClusterName substrate <> "-control-plane"
    ]
 where
  bytes = Text.pack (show (nodeMemoryBytes res))
