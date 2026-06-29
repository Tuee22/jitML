{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.ConfigMap
  ( renderServiceConfigMap
  , renderServiceDeployment
  , renderServiceRBAC
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.BootConfig (BootConfig, bootSubstrate, renderBootConfigDhall)
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

renderServiceDeployment :: Substrate -> Text
renderServiceDeployment substrate =
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
    , "      labels:"
    , "        app: jitml-service"
    , "        jitml.substrate: " <> renderSubstrate substrate
    , "        jitml.role: engine"
    , "        jitml.compute: " <> yamlLabelBool (substrateHasClusterCompute substrate)
    , "        jitml.compute-scope: service"
    , "    spec:"
    , "      serviceAccountName: jitml-service"
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

serviceReplicaCount :: Substrate -> Int
serviceReplicaCount AppleSilicon = 1
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
    , "  name: jitml-service"
    , "  namespace: platform"
    , "---"
    , "apiVersion: rbac.authorization.k8s.io/v1"
    , "kind: Role"
    , "metadata:"
    , "  name: jitml-service"
    , "  namespace: platform"
    , "rules:"
    , "  - apiGroups: [\"*\"]"
    , "    resources: [\"*\"]"
    , "    verbs: [\"get\", \"list\", \"watch\", \"create\", \"update\", \"patch\", \"delete\"]"
    , "---"
    , "apiVersion: rbac.authorization.k8s.io/v1"
    , "kind: RoleBinding"
    , "metadata:"
    , "  name: jitml-service"
    , "  namespace: platform"
    , "subjects:"
    , "  - kind: ServiceAccount"
    , "    name: jitml-service"
    , "    namespace: platform"
    , "roleRef:"
    , "  apiGroup: rbac.authorization.k8s.io"
    , "  kind: Role"
    , "  name: jitml-service"
    ]
