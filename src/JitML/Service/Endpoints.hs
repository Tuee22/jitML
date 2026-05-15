{-# LANGUAGE OverloadedStrings #-}

module JitML.Service.Endpoints
    ( EndpointResponse (..)
    , MetricsSnapshot (..)
    , healthz
    , metrics
    , readyz
    , renderEndpointResponse
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

data EndpointResponse = EndpointResponse
    { endpointStatus :: Int
    , endpointBody :: Text
    }
    deriving stock (Eq, Show)

data MetricsSnapshot = MetricsSnapshot
    { metricConsumerLag :: Int
    , metricJitCacheHits :: Int
    , metricJitCacheMisses :: Int
    }
    deriving stock (Eq, Show)

healthz :: EndpointResponse
healthz = EndpointResponse 200 "ok\n"

readyz :: Bool -> EndpointResponse
readyz ready =
    if ready
        then EndpointResponse 200 "ready\n"
        else EndpointResponse 503 "not ready\n"

metrics :: MetricsSnapshot -> EndpointResponse
metrics snapshot =
    EndpointResponse 200 $
        Text.unlines
            [ "# HELP jitml_pulsar_consumer_lag Pulsar consumer lag."
            , "# TYPE jitml_pulsar_consumer_lag gauge"
            , "jitml_pulsar_consumer_lag " <> Text.pack (show (metricConsumerLag snapshot))
            , "# HELP jitml_jit_cache_hits JIT cache hits."
            , "# TYPE jitml_jit_cache_hits counter"
            , "jitml_jit_cache_hits " <> Text.pack (show (metricJitCacheHits snapshot))
            , "# HELP jitml_jit_cache_misses JIT cache misses."
            , "# TYPE jitml_jit_cache_misses counter"
            , "jitml_jit_cache_misses " <> Text.pack (show (metricJitCacheMisses snapshot))
            ]

renderEndpointResponse :: EndpointResponse -> Text
renderEndpointResponse response =
    Text.unlines
        [ "status: " <> Text.pack (show (endpointStatus response))
        , endpointBody response
        ]
