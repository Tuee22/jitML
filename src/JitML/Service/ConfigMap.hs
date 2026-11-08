{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.ConfigMap
  ( renderServiceConfigMap
  , renderServiceConfigMaps
  , renderServiceDeployment
  , renderServiceRBAC
  , renderServiceValues
  , renderClusterResourceValues
  , renderPlatformResourceDefaults
  , resourceLines
  )
where

import Data.Aeson (object, (.=))
import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding

import JitML.Cluster.Resources
  ( ClusterResources (..)
  , ComponentBudget (..)
  )
import JitML.Service.BootConfig
  ( BootConfig (..)
  , Role (Coordinator)
  , renderBootConfigDhall
  )
import JitML.Service.LiveConfig (LiveConfig, renderLiveConfigDhall)
import JitML.Substrate
  ( Substrate (..)
  , renderSubstrate
  , substrateHasClusterCompute
  , substrateRuntimeClass
  )

-- | Admission defaults cover upstream helpers that omit resource fields.
-- Explicit primary-container budgets remain unchanged by this LimitRange.
renderPlatformResourceDefaults :: ClusterResources -> Text
renderPlatformResourceDefaults resources =
  Text.Encoding.decodeUtf8 (LazyByteString.toStrict (Aeson.encode manifests)) <> "\n"
 where
  budget = supporting resources
  manifests =
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
                                        [ "cpu" .= budgetCpuRequest budget
                                        , "memory" .= budgetMemoryRequest budget
                                        ]
                                  , "default"
                                      .= object
                                        [ "cpu" .= budgetCpuLimit budget
                                        , "memory" .= budgetMemoryLimit budget
                                        ]
                                  ]
                              ]
                       ]
                 ]
             ]
      ]

renderServiceConfigMap :: BootConfig -> LiveConfig -> Text
renderServiceConfigMap bootConfig liveConfig =
  Text.unlines
    [ "apiVersion: v1"
    , "kind: ConfigMap"
    , "metadata:"
    , "  name: jitml-service-config"
    , "  namespace: platform"
    , "data:"
    , "  BootConfig.dhall: |"
    ]
    <> indentBlock (renderBootConfigDhall bootConfig)
    <> Text.unlines ["  LiveConfig.dhall: |"]
    <> indentBlock (renderLiveConfigDhall liveConfig)

renderServiceConfigMaps :: BootConfig -> LiveConfig -> Text
renderServiceConfigMaps engineBootConfig liveConfig =
  renderServiceConfigMap engineBootConfig liveConfig
    <> "---\n"
    <> renderCoordinatorConfigMap
      (engineBootConfig {bootActiveRole = Coordinator})
      liveConfig

renderCoordinatorConfigMap :: BootConfig -> LiveConfig -> Text
renderCoordinatorConfigMap bootConfig liveConfig =
  Text.unlines
    [ "apiVersion: v1"
    , "kind: ConfigMap"
    , "metadata:"
    , "  name: jitml-coordinator-config"
    , "  namespace: platform"
    , "data:"
    , "  BootConfig.dhall: |"
    ]
    <> indentBlock (renderBootConfigDhall bootConfig)
    <> Text.unlines ["  LiveConfig.dhall: |"]
    <> indentBlock (renderLiveConfigDhall liveConfig)

renderServiceDeployment :: ClusterResources -> Substrate -> Text
renderServiceDeployment resources substrate =
  renderEngineDeployment resources substrate
    <> "---\n"
    <> renderCoordinatorDeployment resources substrate

renderEngineDeployment :: ClusterResources -> Substrate -> Text
renderEngineDeployment resources substrate =
  Text.unlines $
    [ "apiVersion: apps/v1"
    , "kind: Deployment"
    , "metadata:"
    , "  name: jitml-service"
    , "  namespace: platform"
    , "spec:"
    , "  replicas: " <> Text.pack (show (serviceReplicaCount resources substrate))
    , "  strategy:"
    , "    type: RollingUpdate"
    , "    rollingUpdate:"
    , "      maxSurge: 0"
    , "      maxUnavailable: 1"
    , "  selector:"
    , "    matchLabels:"
    , "      app: jitml-service"
    , "  template:"
    , "    metadata:"
    , "      annotations:"
    , "        checksum/live-config: {{ include (print $.Template.BasePath \"/configmap-jitml-service.yaml\") . | sha256sum | quote }}"
    , "      labels:"
    , "        app: jitml-service"
    , "        jitml.substrate: " <> renderSubstrate substrate
    , "        jitml.role: engine"
    , "        jitml.compute: " <> yamlLabelBool (substrateHasClusterCompute substrate)
    , "        jitml.compute-scope: service"
    , "    spec:"
    , "      serviceAccountName: jitml-engine"
    , "      automountServiceAccountToken: false"
    ]
      <> runtimeClassLines
      <> clusterComputePlacementLines substrate
      <> [ "      containers:"
         , "        - name: jitml-service"
         , "          image: jitml:local"
         , "          imagePullPolicy: IfNotPresent"
         , "          command: [\"jitml\"]"
         , "          args: [\"service\", \"--config\", \"/etc/jitml/BootConfig.dhall\"]"
         ]
      <> resourceLines 10 "resources" (jitmlService resources)
      <> [ "          readinessProbe:"
         , "            httpGet:"
         , "              path: /readyz"
         , "              port: 8080"
         , "          startupProbe:"
         , "            httpGet:"
         , "              path: /healthz"
         , "              port: 8080"
         , "            periodSeconds: 5"
         , "            timeoutSeconds: 2"
         , "            failureThreshold: 60"
         , "          livenessProbe:"
         , "            httpGet:"
         , "              path: /healthz"
         , "              port: 8080"
         ]
      <> nvidiaEnvLines
      <> [ "          volumeMounts:"
         , "            - name: jit-cache"
         , "              mountPath: /opt/build"
         , "            - name: service-config"
         , "              mountPath: /etc/jitml"
         , "      volumes:"
         , "        - name: jit-cache"
         , "          hostPath:"
         , "            path: /jitml/.build"
         , "        - name: service-config"
         , "          configMap:"
         , "            name: jitml-service-config"
         ]
 where
  runtimeClassLines =
    case substrateRuntimeClass substrate of
      Nothing -> []
      Just runtimeClass ->
        ["      runtimeClassName: " <> runtimeClass]

  nvidiaEnvLines =
    case substrateRuntimeClass substrate of
      Nothing -> []
      Just _ ->
        [ "          env:"
        , "            - name: NVIDIA_VISIBLE_DEVICES"
        , "              value: all"
        , "            - name: NVIDIA_DRIVER_CAPABILITIES"
        , "              value: compute,utility"
        ]

renderCoordinatorDeployment :: ClusterResources -> Substrate -> Text
renderCoordinatorDeployment resources substrate =
  Text.unlines $
    [ "apiVersion: apps/v1"
    , "kind: Deployment"
    , "metadata:"
    , "  name: jitml-coordinator"
    , "  namespace: platform"
    , "spec:"
    , "  replicas: 1"
    , "  strategy:"
    , "    type: Recreate"
    , "  selector:"
    , "    matchLabels:"
    , "      app: jitml-coordinator"
    , "  template:"
    , "    metadata:"
    , "      annotations:"
    , "        checksum/live-config: {{ include (print $.Template.BasePath \"/configmap-jitml-service.yaml\") . | sha256sum | quote }}"
    , "      labels:"
    , "        app: jitml-coordinator"
    , "        jitml.substrate: " <> renderSubstrate substrate
    , "        jitml.role: coordinator"
    , "        jitml.compute: \"false\""
    , "    spec:"
    , "      serviceAccountName: jitml-coordinator"
    , "      containers:"
    , "        - name: jitml-coordinator"
    , "          image: jitml:local"
    , "          imagePullPolicy: IfNotPresent"
    , "          command: [\"jitml\"]"
    , "          args: [\"service\", \"--config\", \"/etc/jitml/BootConfig.dhall\"]"
    ]
      <> resourceLines 10 "resources" (supporting resources)
      <> [ "          readinessProbe:"
         , "            httpGet:"
         , "              path: /readyz"
         , "              port: 8080"
         , "          startupProbe:"
         , "            httpGet:"
         , "              path: /healthz"
         , "              port: 8080"
         , "            periodSeconds: 5"
         , "            timeoutSeconds: 2"
         , "            failureThreshold: 60"
         , "          livenessProbe:"
         , "            httpGet:"
         , "              path: /healthz"
         , "              port: 8080"
         , "          volumeMounts:"
         , "            - name: service-config"
         , "              mountPath: /etc/jitml"
         , "      volumes:"
         , "        - name: service-config"
         , "          configMap:"
         , "            name: jitml-coordinator-config"
         ]

serviceReplicaCount :: ClusterResources -> Substrate -> Int
serviceReplicaCount _ AppleSilicon = 0
serviceReplicaCount resources LinuxCPU = budgetReplicas (jitmlService resources)
serviceReplicaCount resources LinuxCUDA = budgetReplicas (jitmlService resources)

renderServiceValues :: ClusterResources -> Text
renderServiceValues resources =
  Text.unlines $
    [ "substrate: linux-cpu"
    , "edgePort: 9090"
    , "engineReplicas: " <> Text.pack (show (budgetReplicas (jitmlService resources)))
    , ""
    , "image:"
    , "  repository: jitml"
    , "  tag: local"
    ]
      <> resourceLines 0 "resources" (jitmlService resources)
      <> resourceLines 0 "coordinatorResources" (supporting resources)
      <> numericalWorkloadLines (numericalWorkload resources)

-- | Runtime-only Helm overlays. Every release receives its effective profile
-- after the authored values, so local and upstream charts share the same
-- budgets without rewriting their image, storage, protocol, or JVM settings.
-- JSON objects are valid YAML and preserve resource quantities as strings.
renderClusterResourceValues :: ClusterResources -> [(FilePath, Text)]
renderClusterResourceValues resources =
  [ overlay "minio" $
      object
        [ "resources" .= componentResources (minio resources)
        , "volumePermissions" .= resourcesFor (supporting resources)
        , "provisioning" .= resourcesFor (supporting resources)
        ]
  , overlay "registry" (resourcesFor (registry resources))
  , overlay "pulsar" $
      object
        [ "zookeeper" .= resourcesFor (pulsar resources)
        , "bookkeeper" .= resourcesFor (pulsar resources)
        , "broker" .= resourcesFor (pulsar resources)
        , "proxy" .= resourcesFor (pulsar resources)
        , "autorecovery" .= resourcesFor (supporting resources)
        , "toolset" .= resourcesFor (supporting resources)
        , -- StatefulSet init requests remain reserved after initialization.
          -- The prepared chart redirects only those long-lived Pods; completed
          -- initialization Job templates retain their original resource fields.
          "statefulInit" .= resourcesFor (supporting resources)
        ]
  , overlay "kube-prometheus-stack" $
      object
        [ "grafana"
            .= object
              [ "resources" .= componentResources (grafana resources)
              , "sidecar" .= resourcesFor (supporting resources)
              ]
        , "prometheus"
            .= object
              [ "prometheusSpec" .= resourcesFor (prometheus resources)
              ]
        , "prometheusOperator"
            .= object
              [ "resources" .= componentResources (supporting resources)
              , "prometheusConfigReloader" .= resourcesFor (supporting resources)
              , "admissionWebhooks"
                  .= object
                    [ "patch" .= resourcesFor (supporting resources)
                    ]
              ]
        , "kube-state-metrics" .= resourcesFor (supporting resources)
        , "crds"
            .= object
              [ "upgradeJob" .= resourcesFor (supporting resources)
              ]
        ]
  , overlay "tensorboard" $
      object
        [ "resources" .= componentResources (tensorboard resources)
        , "syncResources" .= componentResources (supporting resources)
        ]
  , overlay "jitml-service" $
      object
        [ "resources" .= componentResources (jitmlService resources)
        , "coordinatorResources" .= componentResources (supporting resources)
        , "numericalWorkload" .= numericalWorkloadValues (numericalWorkload resources)
        ]
  , overlay "jitml-demo" $
      object $
        [ "resources" .= componentResources (jitmlDemo resources)
        , "numericalWorkload" .= numericalWorkloadValues (numericalWorkload resources)
        ]
          <> [ "nodeSelector"
                 .= object ["node-role.kubernetes.io/control-plane" .= ("" :: Text)]
             | scheduleOnControlPlane resources
             ]
  , overlay "envoy-gateway" $
      object
        [ "deployment"
            .= object
              [ "envoyGateway" .= resourcesFor (supporting resources)
              ]
        , "certgen"
            .= object
              [ "job" .= resourcesFor (supporting resources)
              ]
        ]
  ]
 where
  overlay name value =
    ( ".build/conf/cluster/resources/" <> name <> ".yaml"
    , Text.Encoding.decodeUtf8 (LazyByteString.toStrict (Aeson.encode value)) <> "\n"
    )
  resourcesFor budget = object ["resources" .= componentResources budget]

numericalWorkloadValues :: ComponentBudget -> Aeson.Value
numericalWorkloadValues budget =
  object
    [ "replicas" .= budgetReplicas budget
    , "cpuRequest" .= budgetCpuRequest budget
    , "cpuLimit" .= budgetCpuLimit budget
    , "memoryRequest" .= budgetMemoryRequest budget
    , "memoryLimit" .= budgetMemoryLimit budget
    ]

numericalWorkloadLines :: ComponentBudget -> [Text]
numericalWorkloadLines budget =
  [ "numericalWorkload:"
  , "  replicas: " <> Text.pack (show (budgetReplicas budget))
  , "  cpuRequest: " <> quoted (budgetCpuRequest budget)
  , "  cpuLimit: " <> quoted (budgetCpuLimit budget)
  , "  memoryRequest: " <> quoted (budgetMemoryRequest budget)
  , "  memoryLimit: " <> quoted (budgetMemoryLimit budget)
  ]
 where
  quoted = Text.Encoding.decodeUtf8 . LazyByteString.toStrict . Aeson.encode

componentResources :: ComponentBudget -> Aeson.Value
componentResources budget =
  object
    [ "requests"
        .= object
          [ "cpu" .= budgetCpuRequest budget
          , "memory" .= budgetMemoryRequest budget
          ]
    , "limits"
        .= object
          [ "cpu" .= budgetCpuLimit budget
          , "memory" .= budgetMemoryLimit budget
          ]
    ]

resourceLines :: Int -> Text -> ComponentBudget -> [Text]
resourceLines width key budget =
  fmap
    (Text.replicate width " " <>)
    [ key <> ":"
    , "  requests:"
    , "    cpu: " <> quantity (budgetCpuRequest budget)
    , "    memory: " <> quantity (budgetMemoryRequest budget)
    , "  limits:"
    , "    cpu: " <> quantity (budgetCpuLimit budget)
    , "    memory: " <> quantity (budgetMemoryLimit budget)
    ]
 where
  quantity = Text.Encoding.decodeUtf8 . LazyByteString.toStrict . Aeson.encode

yamlLabelBool :: Bool -> Text
yamlLabelBool True = "\"true\""
yamlLabelBool False = "\"false\""

clusterComputePlacementLines :: Substrate -> [Text]
clusterComputePlacementLines substrate
  | not (substrateHasClusterCompute substrate) = []
  | otherwise =
      [ "      nodeSelector:"
      , "        jitml.node-role/compute: \"true\""
      , "      affinity:"
      , "        podAntiAffinity:"
      , "          requiredDuringSchedulingIgnoredDuringExecution:"
      , "            - topologyKey: kubernetes.io/hostname"
      , "              labelSelector:"
      , "                matchLabels:"
      , "                  jitml.compute: \"true\""
      , "                  jitml.compute-scope: service"
      , "      topologySpreadConstraints:"
      , "        - maxSkew: 1"
      , "          topologyKey: kubernetes.io/hostname"
      , "          whenUnsatisfiable: DoNotSchedule"
      , "          labelSelector:"
      , "            matchLabels:"
      , "              jitml.compute: \"true\""
      , "              jitml.compute-scope: service"
      ]

indentBlock :: Text -> Text
indentBlock =
  Text.unlines . fmap ("    " <>) . Text.lines

_bootConfigSubstrate :: BootConfig -> Substrate
_bootConfigSubstrate = bootSubstrate

renderServiceRBAC :: Text
renderServiceRBAC =
  Text.unlines
    [ "apiVersion: v1"
    , "kind: ServiceAccount"
    , "metadata:"
    , "  name: jitml-engine"
    , "  namespace: platform"
    , "---"
    , "apiVersion: v1"
    , "kind: ServiceAccount"
    , "metadata:"
    , "  name: jitml-coordinator"
    , "  namespace: platform"
    , "---"
    , "apiVersion: rbac.authorization.k8s.io/v1"
    , "kind: Role"
    , "metadata:"
    , "  name: jitml-coordinator"
    , "  namespace: platform"
    , "rules:"
    , "  - apiGroups: [\"batch\"]"
    , "    resources: [\"jobs\"]"
    , "    verbs: [\"get\", \"list\", \"watch\", \"create\", \"update\", \"patch\", \"delete\"]"
    , "  - apiGroups: [\"\"]"
    , "    resources: [\"configmaps\"]"
    , "    verbs: [\"get\", \"list\", \"watch\", \"create\", \"update\", \"patch\", \"delete\"]"
    , "  - apiGroups: [\"\"]"
    , "    resources: [\"pods\"]"
    , "    verbs: [\"get\", \"list\", \"watch\"]"
    , "  - apiGroups: [\"\"]"
    , "    resources: [\"pods/exec\"]"
    , "    verbs: [\"create\"]"
    , "---"
    , "apiVersion: rbac.authorization.k8s.io/v1"
    , "kind: RoleBinding"
    , "metadata:"
    , "  name: jitml-coordinator"
    , "  namespace: platform"
    , "subjects:"
    , "  - kind: ServiceAccount"
    , "    name: jitml-coordinator"
    , "    namespace: platform"
    , "roleRef:"
    , "  apiGroup: rbac.authorization.k8s.io"
    , "  kind: Role"
    , "  name: jitml-coordinator"
    ]
