{-# LANGUAGE OverloadedStrings #-}

module JitML.Routes
  ( Route (..)
  , adminPortalRoutes
  , renderHTTPRoute
  , renderRouteTable
  , routeRegistry
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

data Route = Route
  { routeName :: Text
  , routePathPrefix :: Text
  , routeServiceName :: Text
  , routeServicePort :: Int
  , routeRewritePrefix :: Maybe Text
  , routeWebSocket :: Bool
  , routeAdminPortalLabel :: Maybe Text
  }
  deriving stock (Eq, Show)

routeRegistry :: [Route]
routeRegistry =
  [ Route "demo-root" "/" "jitml-demo" 80 Nothing False Nothing
  , Route "demo-api" "/api" "jitml-demo" 80 Nothing False Nothing
  , Route "demo-ws" "/api/ws" "jitml-demo" 80 Nothing True Nothing
  , Route "jitml-service-healthz" "/healthz" "jitml-service" 8080 Nothing False Nothing
  , Route "jitml-service-readyz" "/readyz" "jitml-service" 8080 Nothing False Nothing
  , Route "jitml-service-metrics" "/metrics" "jitml-service" 8080 Nothing False Nothing
  , Route "tensorboard" "/tensorboard" "tensorboard" 80 (Just "/") False (Just "TensorBoard")
  , Route "grafana" "/grafana" "kube-prometheus-stack-grafana" 80 (Just "/") False (Just "Grafana")
  , Route
      "prometheus"
      "/prometheus"
      "kube-prometheus-stack-prometheus"
      9090
      (Just "/")
      False
      (Just "Prometheus")
  , Route "harbor-portal" "/harbor" "harbor" 80 (Just "/") False (Just "Harbor")
  , Route "harbor-api" "/harbor/api" "harbor" 80 (Just "/api") False Nothing
  , Route "harbor-registry" "/v2" "harbor" 80 Nothing False Nothing
  , Route "harbor-service" "/service" "harbor" 80 Nothing False Nothing
  , Route "minio-console" "/minio/console" "minio" 9001 (Just "/") False (Just "MinIO console")
  , Route "minio-s3" "/minio/s3" "minio" 9000 (Just "/") False Nothing
  , Route "pulsar-admin" "/pulsar/admin" "pulsar-proxy" 80 (Just "/admin") False (Just "Pulsar admin")
  , Route "pulsar-ws" "/pulsar/ws" "pulsar-broker" 8080 (Just "/ws") True Nothing
  ]

-- | Route registry entries that surface as user-facing admin portals.
-- Order is the display order on the SPA portals home page.
adminPortalRoutes :: [(Route, Text)]
adminPortalRoutes =
  [ (route, label)
  | portalName <- adminPortalDisplayOrder
  , route <- routeRegistry
  , routeName route == portalName
  , Just label <- [routeAdminPortalLabel route]
  ]

adminPortalDisplayOrder :: [Text]
adminPortalDisplayOrder =
  [ "grafana"
  , "prometheus"
  , "tensorboard"
  , "harbor-portal"
  , "minio-console"
  , "pulsar-admin"
  ]

renderRouteTable :: Text
renderRouteTable =
  Text.unlines $
    [ "| Prefix | Service | Port | Rewrite | WebSocket |"
    , "|--------|---------|------|---------|-----------|"
    ]
      <> fmap renderRouteRow routeRegistry

renderHTTPRoute :: Route -> Text
renderHTTPRoute route =
  Text.unlines $
    [ "apiVersion: gateway.networking.k8s.io/v1"
    , "kind: HTTPRoute"
    , "metadata:"
    , "  name: " <> routeName route
    , "  namespace: platform"
    , "  labels:"
    , "    app.kubernetes.io/part-of: jitml"
    , "spec:"
    , "  parentRefs:"
    , "    - name: jitml-edge"
    , "      namespace: platform"
    , "  rules:"
    , "    - matches:"
    , "        - path:"
    , "            type: PathPrefix"
    , "            value: " <> routePathPrefix route
    ]
      <> rewriteFilter
      <> [ "      backendRefs:"
         , "        - name: " <> routeServiceName route
         , "          port: " <> Text.pack (show (routeServicePort route))
         ]
 where
  rewriteFilter =
    case routeRewritePrefix route of
      Nothing -> []
      Just prefix ->
        [ "      filters:"
        , "        - type: URLRewrite"
        , "          urlRewrite:"
        , "            path:"
        , "              type: ReplacePrefixMatch"
        , "              replacePrefixMatch: " <> prefix
        ]

renderRouteRow :: Route -> Text
renderRouteRow route =
  Text.intercalate
    " | "
    [ "| `" <> routePathPrefix route <> "`"
    , "`" <> routeServiceName route <> "`"
    , Text.pack (show (routeServicePort route))
    , maybe "`-`" (\rewrite -> "`" <> rewrite <> "`") (routeRewritePrefix route)
    , if routeWebSocket route then "yes |" else "no |"
    ]
