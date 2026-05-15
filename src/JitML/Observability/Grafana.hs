{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.Grafana
    ( Dashboard (..)
    , dashboards
    , renderDashboardConfigMap
    )
where

import Data.Text (Text)
import Data.Text qualified as Text

data Dashboard = Dashboard
    { dashboardName :: Text
    , dashboardMetric :: Text
    }
    deriving stock (Eq, Show)

dashboards :: [Dashboard]
dashboards =
    [ Dashboard "training-throughput" "jitml_training_examples_per_second"
    , Dashboard "rl-episode-reward" "jitml_rl_episode_reward"
    , Dashboard "alphazero-arena" "jitml_alphazero_arena_win_rate"
    , Dashboard "jit-cache" "jitml_jit_cache_hits"
    , Dashboard "pulsar-consumer-lag" "jitml_pulsar_consumer_lag"
    , Dashboard "minio-put-latency" "jitml_minio_put_latency_seconds"
    , Dashboard "daemon-health" "jitml_daemon_ready"
    ]

renderDashboardConfigMap :: Dashboard -> Text
renderDashboardConfigMap dashboard =
    Text.unlines
        [ "apiVersion: v1"
        , "kind: ConfigMap"
        , "metadata:"
        , "  name: grafana-dashboard-" <> dashboardName dashboard
        , "  namespace: platform"
        , "  labels:"
        , "    grafana_dashboard: \"1\""
        , "data:"
        , "  dashboard.json: |"
        , "    {"
        , "      \"title\": \"" <> dashboardName dashboard <> "\","
        , "      \"panels\": [{\"type\":\"timeseries\",\"targets\":[{\"expr\":\"" <> dashboardMetric dashboard <> "\"}]}]"
        , "    }"
        ]
