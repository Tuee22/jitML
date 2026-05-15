{-# LANGUAGE OverloadedStrings #-}

module JitML.Routes
    ( Route (..)
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
    }
    deriving stock (Eq, Show)

routeRegistry :: [Route]
routeRegistry =
    [ Route "demo-root" "/" "jitml-demo" 80 Nothing False
    , Route "demo-api" "/api" "jitml-demo" 80 Nothing False
    , Route "demo-ws" "/api/ws" "jitml-demo" 80 Nothing True
    , Route "tensorboard" "/tensorboard" "tensorboard" 6006 (Just "/") False
    , Route "grafana" "/grafana" "grafana" 3000 (Just "/") False
    , Route "prometheus" "/prometheus" "prometheus" 9090 (Just "/") False
    , Route "harbor-portal" "/harbor" "jitml-harbor-portal" 80 (Just "/") False
    , Route "harbor-api" "/harbor/api" "jitml-harbor-core" 80 (Just "/api") False
    , Route "minio-console" "/minio/console" "jitml-minio-console" 9090 (Just "/") False
    , Route "minio-s3" "/minio/s3" "jitml-minio" 9000 (Just "/") False
    , Route "pulsar-admin" "/pulsar/admin" "jitml-pulsar-proxy" 80 (Just "/admin") False
    , Route "pulsar-ws" "/pulsar/ws" "jitml-pulsar-proxy" 80 (Just "/ws") True
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
