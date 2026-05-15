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

renderEnvoyProxy :: Text
renderEnvoyProxy =
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
        , "                  nodePort: 30090"
        ]
