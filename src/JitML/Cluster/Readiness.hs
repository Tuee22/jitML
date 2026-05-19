{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Readiness
  ( minioBucketReadinessSubprocess
  , minioBootstrapReadinessSubprocesses
  , platformReadinessSubprocesses
  , postgresReadinessSubprocesses
  , renderMinioBucketReadinessCommand
  , renderPostgresReadinessResource
  , renderReadinessTarget
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Cluster.PostgresRegistry
  ( PerconaPGCluster (..)
  , postgresRegistry
  )
import JitML.Storage.Buckets (bucketNames)
import JitML.Sub.Subprocess (Subprocess, subprocess)

platformReadinessSubprocesses :: [Subprocess]
platformReadinessSubprocesses =
  fmap rolloutStatusSubprocess rolloutTargets
    <> postgresReadinessSubprocesses
    <> [minioBucketReadinessSubprocess, runtimeClassSubprocess]

minioBootstrapReadinessSubprocesses :: [Subprocess]
minioBootstrapReadinessSubprocesses =
  [ rolloutStatusSubprocess "deployment/minio"
  , minioBucketReadinessSubprocess
  ]

rolloutTargets :: [Text]
rolloutTargets =
  [ "deployment/harbor-core"
  , "deployment/harbor-jobservice"
  , "deployment/harbor-portal"
  , "deployment/harbor-registry"
  , "statefulset/harbor-redis"
  , "statefulset/harbor-trivy"
  , "deployment/minio"
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

minioBucketReadinessSubprocess :: Subprocess
minioBucketReadinessSubprocess =
  subprocess
    "kubectl"
    [ "--kubeconfig"
    , "./.build/jitml.kubeconfig"
    , "exec"
    , "-n"
    , "platform"
    , "deploy/minio"
    , "--"
    , "sh"
    , "-c"
    , renderMinioBucketReadinessCommand
    ]

renderMinioBucketReadinessCommand :: Text
renderMinioBucketReadinessCommand =
  "for attempt in 1 2 3 4 5 6 7 8 9 10; do "
    <> bucketReadinessAttempt
    <> " && exit 0; sleep 2; done; "
    <> bucketReadinessAttempt
 where
  minioClient = "/opt/bitnami/minio-client/bin/mc"
  bucketReadinessAttempt =
    Text.intercalate
      " && "
      ( [ minioClient
            <> " alias set jitml-minio http://minio.platform.svc.cluster.local:9000 minio minioadmin >/dev/null"
        ]
          <> fmap bucketCheck bucketNames
      )
  bucketCheck bucket =
    minioClient <> " ls jitml-minio/" <> bucket <> " >/dev/null"

renderReadinessTarget :: Text -> Text
renderReadinessTarget target =
  "kubectl rollout status " <> target
