{-# LANGUAGE OverloadedStrings #-}

module JitML.Routes
  ( Route (..)
  , adminPortalRoutes
  , demoApiRouteTimeoutSeconds
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
  , routeTimeoutSeconds :: Maybe Int
  , routeAdminPortalLabel :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | Edge budget for the demo API.
--
-- The webapp brokers request/reply work through the Engine: it waits up to
-- @inferenceReplyStartupTimeoutMicros@ for its broker-admin reply-cursor CREATE
-- and then up to @inferenceReplyTimeoutMicros@ for the Engine's answer. The edge
-- must outlast that sum, so that whatever the webapp concludes — a result, or
-- its typed fail-closed reason — is what the browser observes, rather than a
-- gateway timeout that discards it. @JitML.Routes@ cannot import the inference
-- command module (it sits below @JitML.Bootstrap@, which imports this module),
-- so the relationship is held by a @jitml-unit@ case instead of by
-- construction.
demoApiRouteTimeoutSeconds :: Int
demoApiRouteTimeoutSeconds = 80

routeRegistry :: [Route]
routeRegistry =
  [ Route "demo-root" "/" "jitml-demo" 80 Nothing False Nothing Nothing
  , -- The demo API brokers request/reply work through the Engine, so the edge
    -- must outlast the webapp's own reply budget: a shorter edge timeout
    -- returns a gateway error for a request the webapp would have answered,
    -- and the browser never sees the typed result or the typed fail-closed
    -- reason. Browsing the authenticated 55-row catalogue is the heaviest of
    -- those reads and took 6.5-9.9s measured live, well past the gateway's
    -- 15s default. See `demoApiRouteTimeoutSeconds`.
    Route "demo-api" "/api" "jitml-demo" 80 Nothing False (Just demoApiRouteTimeoutSeconds) Nothing
  , Route "demo-ws" "/api/ws" "jitml-demo" 80 Nothing True Nothing Nothing
  , Route "jitml-service-healthz" "/healthz" "jitml-service" 8080 Nothing False Nothing Nothing
  , Route "jitml-service-readyz" "/readyz" "jitml-service" 8080 Nothing False Nothing Nothing
  , Route "jitml-service-metrics" "/metrics" "jitml-service" 8080 Nothing False Nothing Nothing
  , Route "tensorboard" "/tensorboard" "tensorboard" 80 (Just "/") False Nothing (Just "TensorBoard")
  , Route
      "grafana"
      "/grafana"
      "kube-prometheus-stack-grafana"
      80
      (Just "/")
      False
      Nothing
      (Just "Grafana")
  , Route
      "prometheus"
      "/prometheus"
      "kube-prometheus-stack-prometheus"
      9090
      (Just "/")
      False
      Nothing
      (Just "Prometheus")
  , -- `registry:2` serves the Docker Registry v2 API and nothing else: there is
    -- no portal, no project API, and no token endpoint, so `/v2` is the whole
    -- public surface. The 120s timeout is kept because layer uploads, not the
    -- API calls around them, are what run long.
    Route "registry" "/v2" "registry" 5000 Nothing False (Just 120) Nothing
  , Route "minio-console" "/minio/console" "minio" 9001 (Just "/") False Nothing (Just "MinIO console")
  , Route "minio-s3" "/minio/s3" "minio" 9000 (Just "/") False Nothing Nothing
  , Route
      "pulsar-admin"
      "/pulsar/admin"
      "pulsar-proxy"
      80
      (Just "/admin")
      False
      Nothing
      (Just "Pulsar admin")
  , Route "pulsar-ws" "/pulsar/ws" "pulsar-broker" 8080 (Just "/ws") True Nothing Nothing
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
      <> timeoutBlock
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
  timeoutBlock =
    case routeTimeoutSeconds route of
      Nothing -> []
      Just seconds ->
        let value = Text.pack (show seconds) <> "s"
         in [ "      timeouts:"
            , "        request: " <> value
            , "        backendRequest: " <> value
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
