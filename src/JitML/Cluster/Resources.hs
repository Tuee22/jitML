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
  , componentBudgetDecoder
  , renderComponentBudgetDhall
  , clusterResourcesPath
  , clusterResourcesEnvironment
  , resolveClusterResourcesPath
  , clusterResourcesDecoder
  , defaultClusterResources
  , loadClusterResourcesOrDefault
  , renderClusterResourcesDhall
  , validateEngineTopology
  , validateLocalPlatformTopology
  , nodeMemoryBytes
  , clusterNodeCapSubprocess
  , clusterNodeCapSubprocesses
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Dhall qualified
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath (isAbsolute, (</>))

import JitML.Cluster.Kind (substrateKindNodeContainerNames)
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

-- | The whole-cluster resource profile. @workerCount@ sets the Kind worker
-- node count. @nodeMemoryMiB@ / @nodeCpus@ bound each materialized Kind node
-- container; the per-component budgets size the platform pods that schedule
-- across those nodes.
data ClusterResources = ClusterResources
  { nodeMemoryMiB :: Int
  , nodeCpus :: Text
  , workerCount :: Int
  , jobMemoryMiB :: Int
  , jobCpus :: Text
  , systemReserveMiB :: Int
  , nodeSystemMemoryMiB :: Int
  , nodeSystemCpus :: Text
  , scheduleOnControlPlane :: Bool
  , registry :: ComponentBudget
  , minio :: ComponentBudget
  , pulsar :: ComponentBudget
  , postgres :: ComponentBudget
  , prometheus :: ComponentBudget
  , grafana :: ComponentBudget
  , jitmlService :: ComponentBudget
  , jitmlDemo :: ComponentBudget
  , tensorboard :: ComponentBudget
  , supporting :: ComponentBudget
  , gateway :: ComponentBudget
  , numericalWorkload :: ComponentBudget
  }
  deriving stock (Eq, Show)

-- | Repo-relative path to the checked-in source profile.
clusterResourcesPath :: FilePath
clusterResourcesPath = "dhall/cluster/resources.dhall"

-- | Explicit operator selection, inherited by every lifecycle subprocess.
-- An invalid or missing selected file fails closed instead of using defaults.
clusterResourcesEnvironment :: String
clusterResourcesEnvironment = "JITML_CLUSTER_RESOURCES"

resolveClusterResourcesPath :: FilePath -> Maybe FilePath -> Either Text FilePath
resolveClusterResourcesPath root Nothing = Right (root </> clusterResourcesPath)
resolveClusterResourcesPath root (Just selected)
  | null selected || Text.strip (Text.pack selected) /= Text.pack selected =
      Left "JITML_CLUSTER_RESOURCES must name a nonempty resource-profile file"
  | isAbsolute selected = Right selected
  | otherwise = Right (root </> selected)

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
      <*> fmap fromIntegral (Dhall.field "workerCount" Dhall.natural)
      <*> fmap fromIntegral (Dhall.field "jobMemoryMiB" Dhall.natural)
      <*> Dhall.field "jobCpus" Dhall.strictText
      <*> fmap fromIntegral (Dhall.field "systemReserveMiB" Dhall.natural)
      <*> fmap fromIntegral (Dhall.field "nodeSystemMemoryMiB" Dhall.natural)
      <*> Dhall.field "nodeSystemCpus" Dhall.strictText
      <*> Dhall.field "scheduleOnControlPlane" Dhall.bool
      <*> Dhall.field "registry" componentBudgetDecoder
      <*> Dhall.field "minio" componentBudgetDecoder
      <*> Dhall.field "pulsar" componentBudgetDecoder
      <*> Dhall.field "postgres" componentBudgetDecoder
      <*> Dhall.field "prometheus" componentBudgetDecoder
      <*> Dhall.field "grafana" componentBudgetDecoder
      <*> Dhall.field "jitmlService" componentBudgetDecoder
      <*> Dhall.field "jitmlDemo" componentBudgetDecoder
      <*> Dhall.field "tensorboard" componentBudgetDecoder
      <*> Dhall.field "supporting" componentBudgetDecoder
      <*> Dhall.field "gateway" componentBudgetDecoder
      <*> Dhall.field "numericalWorkload" componentBudgetDecoder

-- | Fallback profile used when the source Dhall is absent and for the pure
-- plan/dry-run path. It represents the supported local target: one
-- control-plane plus one worker and one instance of each platform service.
defaultClusterResources :: ClusterResources
defaultClusterResources =
  ClusterResources
    { nodeMemoryMiB = 12288
    , nodeCpus = "4"
    , workerCount = 1
    , jobMemoryMiB = 4096
    , jobCpus = "2"
    , systemReserveMiB = 1536
    , nodeSystemMemoryMiB = 1024
    , nodeSystemCpus = "250m"
    , scheduleOnControlPlane = False
    , registry = ComponentBudget 1 "100m" "500m" "256Mi" "512Mi"
    , minio = ComponentBudget 1 "100m" "500m" "512Mi" "1Gi"
    , pulsar = ComponentBudget 1 "100m" "500m" "512Mi" "1Gi"
    , postgres = ComponentBudget 1 "200m" "500m" "512Mi" "1Gi"
    , prometheus = ComponentBudget 1 "100m" "500m" "512Mi" "1Gi"
    , grafana = ComponentBudget 1 "50m" "250m" "256Mi" "512Mi"
    , jitmlService = ComponentBudget 1 "500m" "2" "1Gi" "2Gi"
    , jitmlDemo = ComponentBudget 1 "250m" "2" "512Mi" "4Gi"
    , tensorboard = ComponentBudget 1 "50m" "250m" "256Mi" "512Mi"
    , supporting = ComponentBudget 1 "25m" "250m" "64Mi" "512Mi"
    , gateway = ComponentBudget 1 "50m" "500m" "128Mi" "1Gi"
    , numericalWorkload = ComponentBudget 1 "1" "2" "2Gi" "4Gi"
    }

-- | Phase 53 drift guard for the repository-supported local rollout. The
-- runtime materializer consumes this profile, so rejecting a count mismatch
-- here prevents a Dhall/runtime overlay from silently restoring HA counts.
-- Engine cardinality remains owned by Phase 69 and is intentionally excluded.
validateLocalPlatformTopology :: ClusterResources -> Either Text ()
validateLocalPlatformTopology resources =
  case filter ((/= 1) . budgetReplicas . snd) platformBudgets of
    [] -> Right ()
    mismatches ->
      Left
        ( "local platform topology requires exactly one replica for: "
            <> Text.intercalate ", " (fmap fst mismatches)
        )
 where
  platformBudgets =
    [ ("registry", registry resources)
    , ("minio", minio resources)
    , ("pulsar", pulsar resources)
    , ("postgres", postgres resources)
    , ("prometheus", prometheus resources)
    , ("grafana", grafana resources)
    , ("jitmlDemo", jitmlDemo resources)
    , ("tensorboard", tensorboard resources)
    ]

-- | Phase 69 cardinality guard. A Linux Engine deployment must be positive,
-- and required hostname anti-affinity means it cannot exceed the number of
-- compute workers available in the same typed profile.
validateEngineTopology :: ClusterResources -> Either Text ()
validateEngineTopology resources
  | workerCount resources < 1 =
      Left "engine topology requires at least one compute worker"
  | engineReplicas < 1 =
      Left "engine topology requires at least one Linux Engine replica"
  | engineReplicas > workerCount resources =
      Left
        ( "engine topology requires replicas <= workerCount ("
            <> Text.pack (show engineReplicas)
            <> " > "
            <> Text.pack (show (workerCount resources))
            <> ")"
        )
  | otherwise = Right ()
 where
  engineReplicas = budgetReplicas (jitmlService resources)

-- | Load the source profile from @<repoRoot>/dhall/cluster/resources.dhall@,
-- falling back to 'defaultClusterResources' when the file is absent.
loadClusterResourcesOrDefault :: FilePath -> IO ClusterResources
loadClusterResourcesOrDefault repoRoot = do
  selected <- lookupEnv clusterResourcesEnvironment
  path <-
    either (ioError . userError . Text.unpack) pure (resolveClusterResourcesPath repoRoot selected)
  present <- doesFileExist path
  if present
    then Dhall.inputFile clusterResourcesDecoder path
    else case selected of
      Nothing -> pure defaultClusterResources
      Just _ -> ioError (userError ("selected cluster resource profile is absent: " <> path))

-- | Render a profile back to a Dhall record literal (used to materialize the
-- resolved snapshot under @./.build/conf/cluster/@).
renderClusterResourcesDhall :: ClusterResources -> Text
renderClusterResourcesDhall res =
  Text.unlines
    [ "{ nodeMemoryMiB = " <> Text.pack (show (nodeMemoryMiB res))
    , ", nodeCpus = " <> quote (nodeCpus res)
    , ", workerCount = " <> Text.pack (show (workerCount res))
    , ", jobMemoryMiB = " <> Text.pack (show (jobMemoryMiB res))
    , ", jobCpus = " <> quote (jobCpus res)
    , ", systemReserveMiB = " <> Text.pack (show (systemReserveMiB res))
    , ", nodeSystemMemoryMiB = " <> Text.pack (show (nodeSystemMemoryMiB res))
    , ", nodeSystemCpus = " <> quote (nodeSystemCpus res)
    , ", scheduleOnControlPlane = " <> if scheduleOnControlPlane res then "True" else "False"
    , ", registry = " <> renderBudget (registry res)
    , ", minio = " <> renderBudget (minio res)
    , ", pulsar = " <> renderBudget (pulsar res)
    , ", postgres = " <> renderBudget (postgres res)
    , ", prometheus = " <> renderBudget (prometheus res)
    , ", grafana = " <> renderBudget (grafana res)
    , ", jitmlService = " <> renderBudget (jitmlService res)
    , ", jitmlDemo = " <> renderBudget (jitmlDemo res)
    , ", tensorboard = " <> renderBudget (tensorboard res)
    , ", supporting = " <> renderBudget (supporting res)
    , ", gateway = " <> renderBudget (gateway res)
    , ", numericalWorkload = " <> renderBudget (numericalWorkload res)
    , "}"
    ]
 where
  quote t = "\"" <> t <> "\""
  renderBudget = renderComponentBudgetDhall

renderComponentBudgetDhall :: ComponentBudget -> Text
renderComponentBudgetDhall b =
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
 where
  quote t = "\"" <> t <> "\""

-- | Node cap in bytes (docker @--memory@ takes raw bytes).
nodeMemoryBytes :: ClusterResources -> Integer
nodeMemoryBytes res = toInteger (nodeMemoryMiB res) * 1048576

-- | Typed @docker update@ that caps a Kind node container's memory and CPU from
-- the profile. @--memory-swap == --memory@ disables swap thrash so an
-- over-budget cluster OOM-kills its own pods inside the node cgroup rather than
-- taking down the host. Runs after @kind create@; the reconciler stops at the
-- first failed step, so a cap that cannot be applied fails the bootstrap closed.
clusterNodeCapSubprocess :: Substrate -> ClusterResources -> Subprocess
clusterNodeCapSubprocess substrate res =
  clusterNodeCapSubprocessFor res (substrateClusterName substrate <> "-control-plane")

clusterNodeCapSubprocesses :: Substrate -> ClusterResources -> [Subprocess]
clusterNodeCapSubprocesses substrate res =
  fmap
    (clusterNodeCapSubprocessFor res)
    (substrateKindNodeContainerNames substrate (workerCount res))

clusterNodeCapSubprocessFor :: ClusterResources -> Text -> Subprocess
clusterNodeCapSubprocessFor res nodeName =
  subprocess
    "docker"
    [ "update"
    , "--memory"
    , bytes
    , "--memory-swap"
    , bytes
    , "--cpus"
    , nodeCpus res
    , nodeName
    ]
 where
  bytes = Text.pack (show (nodeMemoryBytes res))
