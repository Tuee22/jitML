{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.ConfigMap
  ( renderServiceConfigMap
  , renderServiceConfigMaps
  , renderServiceDeployment
  , renderServiceRBAC
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.BootConfig
  ( BootConfig (..)
  , Role (Coordinator)
  , renderBootConfigDhall
  )
import JitML.Service.LiveConfig (LiveConfig, renderLiveConfigDhall)
import JitML.Substrate (Substrate (..), renderSubstrate, substrateRuntimeClass)

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

renderServiceDeployment :: Substrate -> Text
renderServiceDeployment substrate =
  renderEngineDeployment substrate
    <> "---\n"
    <> renderCoordinatorDeployment substrate

renderEngineDeployment :: Substrate -> Text
renderEngineDeployment substrate =
  Text.unlines $
    [ "apiVersion: apps/v1"
    , "kind: Deployment"
    , "metadata:"
    , "  name: jitml-service"
    , "  namespace: platform"
    , "spec:"
    , "  replicas: " <> Text.pack (show (serviceReplicaCount substrate))
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
         , "          readinessProbe:"
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

renderCoordinatorDeployment :: Substrate -> Text
renderCoordinatorDeployment substrate =
  Text.unlines
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
    , "          readinessProbe:"
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

serviceReplicaCount :: Substrate -> Int
serviceReplicaCount AppleSilicon = 0
serviceReplicaCount LinuxCPU = 3
serviceReplicaCount LinuxCUDA = 3

substrateHasClusterCompute :: Substrate -> Bool
substrateHasClusterCompute AppleSilicon = False
substrateHasClusterCompute LinuxCPU = True
substrateHasClusterCompute LinuxCUDA = True

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
