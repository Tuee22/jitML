{-# LANGUAGE OverloadedStrings #-}

module JitML.Cluster.Gateway
  ( renderEnvoyProxy
  , renderGateway
  , renderGatewayClass
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

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

renderEnvoyProxy :: Int -> Text
renderEnvoyProxy edgePort =
  Text.unlines
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
    , "          resources:"
    , "            requests:"
    , "              cpu: 50m"
    , "              memory: 64Mi"
    ]
