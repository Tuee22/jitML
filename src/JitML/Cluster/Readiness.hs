{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Readiness
  ( minioBucketReadinessSubprocess
  , minioBootstrapReadinessSubprocesses
  , platformReadinessSubprocesses
  , postgresReadinessSubprocesses
  , runMinioBucketReadinessIO
  , renderPostgresReadinessResource
  , renderReadinessTarget
  )
where

import Control.Concurrent (threadDelay)
import Data.Text (Text)
import System.Exit (ExitCode (..))

import JitML.Cluster.PostgresRegistry
  ( PerconaPGCluster (..)
  , postgresRegistry
  )
import JitML.Storage.Buckets (bucketNames)
import JitML.Sub.Stream (defaultSubprocessEnv, runStreaming)
import JitML.Sub.Subprocess (Subprocess, subprocess)

platformReadinessSubprocesses :: [Subprocess]
platformReadinessSubprocesses =
  fmap rolloutStatusSubprocess rolloutTargets
    <> postgresReadinessSubprocesses
    <> [minioBucketReadinessSubprocess, runtimeClassSubprocess]

-- | Sprint 4.8 / Sprint 15.22 — the bootstrap rollout blocks on the
-- distributed MinIO @statefulset/minio@ rolling-update status here; the
-- per-bucket existence check (formerly an
-- embedded @sh -c@ retry loop) moves to typed Haskell IO
-- ('runMinioBucketReadinessIO') called by 'JitML.Bootstrap.liveExecutePhasedRollout'
-- between the pre-grant and grant phases.
minioBootstrapReadinessSubprocesses :: [Subprocess]
minioBootstrapReadinessSubprocesses =
  [rolloutStatusSubprocess "statefulset/minio"]

rolloutTargets :: [Text]
rolloutTargets =
  [ "deployment/harbor-core"
  , "deployment/harbor-jobservice"
  , "deployment/harbor-portal"
  , "deployment/harbor-registry"
  , "statefulset/harbor-redis"
  , "statefulset/harbor-trivy"
  , "statefulset/minio"
  , "statefulset/pulsar-zookeeper"
  , "statefulset/pulsar-bookie"
  , "statefulset/pulsar-broker"
  , "statefulset/pulsar-proxy"
  , "statefulset/pulsar-toolset"
  , "deployment/envoy-gateway"
  , "deployment/kube-prometheus-stack-grafana"
  , "deployment/kube-prometheus-stack-kube-state-metrics"
  , "deployment/kube-prometheus-stack-operator"
  , "statefulset/prometheus-kube-prometheus-stack-prometheus"
  , "deployment/tensorboard"
  , "deployment/jitml-service"
  , "deployment/jitml-demo"
  ]

rolloutStatusSubprocess :: Text -> Subprocess
rolloutStatusSubprocess target =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "-n"
    , "platform"
    , "rollout"
    , "status"
    , target
    , "--timeout=300s"
    ]

runtimeClassSubprocess :: Subprocess
runtimeClassSubprocess =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "get"
    , "runtimeclass"
    , "nvidia"
    ]

postgresReadinessSubprocesses :: [Subprocess]
postgresReadinessSubprocesses =
  fmap postgresReadinessSubprocess postgresRegistry

postgresReadinessSubprocess :: PerconaPGCluster -> Subprocess
postgresReadinessSubprocess cluster =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "-n"
    , perconaNamespace cluster
    , "wait"
    , renderPostgresReadinessResource cluster
    , "--for=jsonpath={.status.state}=ready"
    , "--timeout=600s"
    ]

renderPostgresReadinessResource :: PerconaPGCluster -> Text
renderPostgresReadinessResource cluster =
  "perconapgcluster/" <> perconaClusterName cluster

-- | Sprint 4.9 — typed single @kubectl exec@ that lists the @jitml-minio@
-- alias root via @mc@. The MinIO server address and credentials are passed
-- through the @MC_HOST_jitml-minio@ env var so we avoid an @mc alias set@
-- prelude and the previous @sh -c@ chain entirely. Used by the final
-- 'platformReadinessSubprocesses' gate.
minioBucketReadinessSubprocess :: Subprocess
minioBucketReadinessSubprocess =
  kubectlExecMc ["ls", "jitml-minio"]

mcBucketLsSubprocess :: Text -> Subprocess
mcBucketLsSubprocess bucket = kubectlExecMc ["ls", "jitml-minio/" <> bucket]

kubectlExecMc :: [Text] -> Subprocess
kubectlExecMc mcArgs =
  subprocess
    "kubectl"
    ( [ "--kubeconfig"
      , "./.build/jitml.kubeconfig"
      , "exec"
      , "-n"
      , "platform"
      , "statefulset/minio"
      , "--"
      , "env"
      , "MC_HOST_jitml-minio=http://minio:minioadmin@minio.platform.svc.cluster.local:9000"
      , "/opt/bitnami/minio-client/bin/mc"
      ]
        <> mcArgs
    )

-- | Sprint 4.8 — typed Haskell IO retry around per-bucket existence probes.
-- Replaces the embedded @sh -c@ retry loop. Each bucket is probed with up to
-- 10 attempts at 2-second intervals; the first hard failure stops the IO step
-- and surfaces as a @Left@ for 'JitML.Bootstrap.liveExecutePhasedRollout'.
runMinioBucketReadinessIO :: IO (Either Text ())
runMinioBucketReadinessIO = goBuckets bucketNames
 where
  goBuckets [] = pure (Right ())
  goBuckets (b : rest) = do
    result <- attempt b (10 :: Int)
    case result of
      Left err -> pure (Left err)
      Right () -> goBuckets rest
  attempt bucket 0 =
    pure (Left ("minio bucket readiness " <> bucket <> ": exhausted retries"))
  attempt bucket n = do
    (code, _stdout, _stderr) <-
      runStreaming defaultSubprocessEnv (mcBucketLsSubprocess bucket)
    case code of
      ExitSuccess -> pure (Right ())
      ExitFailure _ -> do
        threadDelay 2_000_000
        attempt bucket (n - 1)

renderReadinessTarget :: Text -> Text
renderReadinessTarget target =
  "kubectl rollout status " <> target
