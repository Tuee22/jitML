{-# LANGUAGE OverloadedStrings #-}

module JitML.Generated.Paths
  ( TrackedGeneratedPath (..)
  , futureTrackingGeneratedPathPatterns
  , trackingGeneratedPaths
  )
where

import Data.Text (Text)

import JitML.Docs.Render
  ( renderBashCompletion
  , renderFishCompletion
  , renderManpage
  , renderMarkdownReference
  , renderZshCompletion
  )

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

futureTrackingGeneratedPathPatterns :: [FilePath]
futureTrackingGeneratedPathPatterns =
  [ "share/man/man1/jitml-*.1"
  , "web/src/Generated/Contracts.purs"
  , "chart/templates/httproute-*.yaml"
  , "chart/templates/grafana-dashboard-*.yaml"
  ]
