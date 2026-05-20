{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.ConfigMap
  ( renderServiceConfigMap
  , renderServiceDeployment
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Service.BootConfig (BootConfig, bootSubstrate, renderBootConfigDhall)
import JitML.Service.LiveConfig (LiveConfig, renderLiveConfigDhall)
import JitML.Substrate (Substrate, renderSubstrate, substrateRuntimeClass)

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
    , "  replicas: 1"
    , "  selector:"
    , "    matchLabels:"
    , "      app: jitml-service"
    , "  template:"
    , "    metadata:"
    , "      labels:"
    , "        app: jitml-service"
    , "        jitml.substrate: " <> renderSubstrate substrate
    , "    spec:"
    ]
      <> runtimeClassLines
      <> [ "      affinity:"
         , "        podAntiAffinity:"
         , "          requiredDuringSchedulingIgnoredDuringExecution:"
         , "            - topologyKey: kubernetes.io/hostname"
         , "              labelSelector:"
         , "                matchLabels:"
         , "                  app: jitml-service"
         , "      containers:"
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

indentBlock :: Text -> Text
indentBlock =
  Text.unlines . fmap ("    " <>) . Text.lines

_bootConfigSubstrate :: BootConfig -> Substrate
_bootConfigSubstrate = bootSubstrate
