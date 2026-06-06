{-# LANGUAGE OverloadedStrings #-}

module JitML.Generated.Paths
  ( TrackedGeneratedPath (..)
  , futureTrackingGeneratedPathPatterns
  , trackingGeneratedPaths
  )
where

import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Docs.Render
  ( renderBashCompletion
  , renderFishCompletion
  , renderManpage
  , renderMarkdownReference
  , renderZshCompletion
  )
import JitML.Observability.Grafana qualified as Grafana
import JitML.Observability.Prometheus (renderPrometheusScrapeConfig)
import JitML.Routes qualified as Routes
import JitML.Web.AdminPortals (renderPureScriptAdminPortals)
import JitML.Web.Contracts (renderPureScriptContracts)

data TrackedGeneratedPath = TrackedGeneratedPath
  { trackedKey :: Text
  , trackedPath :: FilePath
  , trackedRendered :: Text
  }
  deriving stock (Eq, Show)

trackingGeneratedPaths :: [TrackedGeneratedPath]
trackingGeneratedPaths =
  [ TrackedGeneratedPath
      { trackedKey = "cli-commands.reference"
      , trackedPath = "documents/cli/commands.md"
      , trackedRendered = renderMarkdownReference
      }
  , TrackedGeneratedPath
      { trackedKey = "cli-commands.manpage"
      , trackedPath = "share/man/man1/jitml.1"
      , trackedRendered = renderManpage
      }
  , TrackedGeneratedPath
      { trackedKey = "cli-commands.completion.bash"
      , trackedPath = "share/completion/bash/jitml"
      , trackedRendered = renderBashCompletion
      }
  , TrackedGeneratedPath
      { trackedKey = "cli-commands.completion.zsh"
      , trackedPath = "share/completion/zsh/_jitml"
      , trackedRendered = renderZshCompletion
      }
  , TrackedGeneratedPath
      { trackedKey = "cli-commands.completion.fish"
      , trackedPath = "share/completion/fish/jitml.fish"
      , trackedRendered = renderFishCompletion
      }
  ]
    <> [ TrackedGeneratedPath
           { trackedKey = "web.contracts.purescript"
           , trackedPath = "web/src/Generated/Contracts.purs"
           , trackedRendered = renderPureScriptContracts
           }
       , TrackedGeneratedPath
           { trackedKey = "web.admin-portals.purescript"
           , trackedPath = "web/src/Generated/AdminPortals.purs"
           , trackedRendered = renderPureScriptAdminPortals
           }
       ]
    <> fmap trackedRoute Routes.routeRegistry
    <> fmap trackedDashboard Grafana.dashboards
    <> [ TrackedGeneratedPath
           { trackedKey = "chart.prometheus.scrape"
           , trackedPath = "chart/templates/prometheus-scrapeconfig-jitml.yaml"
           , trackedRendered = renderPrometheusScrapeConfig
           }
       ]

futureTrackingGeneratedPathPatterns :: [FilePath]
futureTrackingGeneratedPathPatterns =
  [ "share/man/man1/jitml-*.1"
  ]

trackedRoute :: Routes.Route -> TrackedGeneratedPath
trackedRoute route =
  TrackedGeneratedPath
    { trackedKey = "chart.routes." <> Routes.routeName route
    , trackedPath = "chart/templates/httproute-" <> Text.unpack (Routes.routeName route) <> ".yaml"
    , trackedRendered = Routes.renderHTTPRoute route
    }

trackedDashboard :: Grafana.Dashboard -> TrackedGeneratedPath
trackedDashboard dashboard =
  TrackedGeneratedPath
    { trackedKey = "chart.grafana." <> Grafana.dashboardName dashboard
    , trackedPath =
        "chart/templates/grafana-dashboard-"
          <> Text.unpack (Grafana.dashboardName dashboard)
          <> ".yaml"
    , trackedRendered = Grafana.renderDashboardConfigMap dashboard
    }
