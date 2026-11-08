{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Gateway
  ( renderEnvoyProxy
  , renderGateway
  , renderGatewayClass
  )
where

import Data.Aeson qualified as Aeson
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding

import JitML.Cluster.Resources (ClusterResources (..), ComponentBudget (..))

renderGatewayClass :: Text
renderGatewayClass =
  Text.unlines
    [ "apiVersion: gateway.networking.k8s.io/v1"
    , "kind: GatewayClass"
    , "metadata:"
    , "  name: jitml-gateway"
    , "spec:"
    , "  controllerName: gateway.envoyproxy.io/gatewayclass-controller"
    , "  parametersRef:"
    , "    group: gateway.envoyproxy.io"
    , "    kind: EnvoyProxy"
    , "    name: jitml-edge"
    , "    namespace: platform"
    ]

renderGateway :: Int -> Text
renderGateway edgePort =
  Text.unlines
    [ "apiVersion: gateway.networking.k8s.io/v1"
    , "kind: Gateway"
    , "metadata:"
    , "  name: jitml-edge"
    , "  namespace: platform"
    , "spec:"
    , "  gatewayClassName: jitml-gateway"
    , "  listeners:"
    , "    - name: http"
    , "      protocol: HTTP"
    , "      port: " <> Text.pack (show edgePort)
    , "      allowedRoutes:"
    , "        namespaces:"
    , "          from: All"
    ]

renderEnvoyProxy :: ClusterResources -> Int -> Text
renderEnvoyProxy resources edgePort =
  Text.unlines $
    [ "apiVersion: gateway.envoyproxy.io/v1alpha1"
    , "kind: EnvoyProxy"
    , "metadata:"
    , "  name: jitml-edge"
    , "  namespace: platform"
    , "spec:"
    , "  provider:"
    , "    type: Kubernetes"
    , "    kubernetes:"
    , "      envoyService:"
    , "        type: NodePort"
    , "        externalTrafficPolicy: Cluster"
    , "        patch:"
    , "          value:"
    , "            spec:"
    , "              ports:"
    , "                - name: http"
    , "                  port: " <> Text.pack (show edgePort)
    , "                  nodePort: 30090"
    , "      envoyDeployment:"
    , "        container:"
    ]
      <> resourceLines 10 (gateway resources)
      <> [ "        patch:"
         , "          type: StrategicMerge"
         , "          value:"
         , "            spec:"
         , "              template:"
         , "                spec:"
         , "                  containers:"
         , "                    - name: envoy"
         , "                      readinessProbe:"
         , "                        failureThreshold: 12"
         , "                        periodSeconds: 5"
         , "                        timeoutSeconds: 10"
         , "                      startupProbe:"
         , "                        failureThreshold: 60"
         , "                        periodSeconds: 10"
         , "                        timeoutSeconds: 10"
         , "                    - name: shutdown-manager"
         ]
      <> resourceLines 22 (supporting resources)
      <> [ "                      livenessProbe:"
         , "                        failureThreshold: 12"
         , "                        periodSeconds: 10"
         , "                        timeoutSeconds: 5"
         , "                      readinessProbe:"
         , "                        failureThreshold: 12"
         , "                        periodSeconds: 10"
         , "                        timeoutSeconds: 5"
         , "                      startupProbe:"
         , "                        failureThreshold: 60"
         , "                        periodSeconds: 10"
         , "                        timeoutSeconds: 5"
         ]

resourceLines :: Int -> ComponentBudget -> [Text]
resourceLines width budget =
  fmap
    (Text.replicate width " " <>)
    [ "resources:"
    , "  requests:"
    , "    cpu: " <> quantity (budgetCpuRequest budget)
    , "    memory: " <> quantity (budgetMemoryRequest budget)
    , "  limits:"
    , "    cpu: " <> quantity (budgetCpuLimit budget)
    , "    memory: " <> quantity (budgetMemoryLimit budget)
    ]
 where
  quantity = Text.Encoding.decodeUtf8 . LazyByteString.toStrict . Aeson.encode
