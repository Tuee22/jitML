{-# LANGUAGE OverloadedStrings #-}

module JitML.Observability.Prometheus
  ( scrapeTargets
  , renderPrometheusScrapeConfig
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

scrapeTargets :: [Text]
scrapeTargets =
  ["jitml-service.platform.svc.cluster.local:8080"]

renderPrometheusScrapeConfig :: Text
renderPrometheusScrapeConfig =
  Text.unlines $
    [ "apiVersion: monitoring.coreos.com/v1alpha1"
    , "kind: ScrapeConfig"
    , "metadata:"
    , "  name: jitml"
    , "  namespace: platform"
    , "  labels:"
    , "    release: kube-prometheus-stack"
    , "spec:"
    , "  staticConfigs:"
    , "    - targets:"
    ]
      <> fmap ("        - " <>) scrapeTargets
