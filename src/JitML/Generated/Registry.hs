{-# LANGUAGE OverloadedStrings #-}

module JitML.Generated.Registry
  ( FutureGeneratedSection (..)
  , GeneratedSectionRule (..)
  , endMarker
  , futureGeneratedSections
  , generatedSectionRules
  , startMarker
  )
where

import Data.Text (Text)

import JitML.Docs.Render
  ( renderClusterRoutes
  , renderDaemonSurface
  , renderGeneratedSectionIndex
  , renderHelpBlocks
  , renderNumericsActivations
  , renderNumericsLayers
  , renderNumericsLosses
  , renderNumericsOptimizers
  , renderNumericsSchedulers
  , renderNumericsSpectral
  , renderReadmeCommandRegistry
  , renderReadmeCommandTree
  , renderTrainingRlCatalog
  , renderTrainingTunePruners
  , renderTrainingTuneSamplers
  , renderTrainingTuneSchedulers
  )

data GeneratedSectionRule = GeneratedSectionRule
  { ruleKey :: Text
  , rulePath :: FilePath
  , ruleRendered :: Text
  }
  deriving stock (Eq, Show)

data FutureGeneratedSection = FutureGeneratedSection
  { futureKey :: Text
  , futurePath :: FilePath
  , futureOwningSprint :: Text
  }
  deriving stock (Eq, Show)

generatedSectionRules :: [GeneratedSectionRule]
generatedSectionRules =
  [ GeneratedSectionRule
      { ruleKey = "command-tree"
      , rulePath = "README.md"
      , ruleRendered = renderReadmeCommandTree
      }
  , GeneratedSectionRule
      { ruleKey = "command-registry"
      , rulePath = "README.md"
      , ruleRendered = renderReadmeCommandRegistry
      }
  , GeneratedSectionRule
      { ruleKey = "cli-commands.help-blocks"
      , rulePath = "documents/engineering/cli_command_surface.md"
      , ruleRendered = renderHelpBlocks
      }
  , GeneratedSectionRule
      { ruleKey = "documentation-standards.generated-section-index"
      , rulePath = "documents/documentation_standards.md"
      , ruleRendered = renderGeneratedSectionIndex
      }
  , GeneratedSectionRule
      { ruleKey = "cluster.routes"
      , rulePath = "documents/engineering/cluster_topology.md"
      , ruleRendered = renderClusterRoutes
      }
  , GeneratedSectionRule
      { ruleKey = "daemon.surface"
      , rulePath = "documents/engineering/daemon_architecture.md"
      , ruleRendered = renderDaemonSurface
      }
  , GeneratedSectionRule
      { ruleKey = "numerics.layers"
      , rulePath = "documents/engineering/numerical_core.md"
      , ruleRendered = renderNumericsLayers
      }
  , GeneratedSectionRule
      { ruleKey = "numerics.activations"
      , rulePath = "documents/engineering/numerical_core.md"
      , ruleRendered = renderNumericsActivations
      }
  , GeneratedSectionRule
      { ruleKey = "numerics.spectral"
      , rulePath = "documents/engineering/numerical_core.md"
      , ruleRendered = renderNumericsSpectral
      }
  , GeneratedSectionRule
      { ruleKey = "numerics.optimizers"
      , rulePath = "documents/engineering/numerical_core.md"
      , ruleRendered = renderNumericsOptimizers
      }
  , GeneratedSectionRule
      { ruleKey = "numerics.schedulers"
      , rulePath = "documents/engineering/numerical_core.md"
      , ruleRendered = renderNumericsSchedulers
      }
  , GeneratedSectionRule
      { ruleKey = "numerics.losses"
      , rulePath = "documents/engineering/numerical_core.md"
      , ruleRendered = renderNumericsLosses
      }
  , GeneratedSectionRule
      { ruleKey = "training.rl.catalog"
      , rulePath = "documents/engineering/training_workloads.md"
      , ruleRendered = renderTrainingRlCatalog
      }
  , GeneratedSectionRule
      { ruleKey = "training.tune.samplers"
      , rulePath = "documents/engineering/training_workloads.md"
      , ruleRendered = renderTrainingTuneSamplers
      }
  , GeneratedSectionRule
      { ruleKey = "training.tune.schedulers"
      , rulePath = "documents/engineering/training_workloads.md"
      , ruleRendered = renderTrainingTuneSchedulers
      }
  , GeneratedSectionRule
      { ruleKey = "training.tune.pruners"
      , rulePath = "documents/engineering/training_workloads.md"
      , ruleRendered = renderTrainingTunePruners
      }
  ]

futureGeneratedSections :: [FutureGeneratedSection]
futureGeneratedSections =
  [ FutureGeneratedSection
      "cross-language-types.*"
      "documents/engineering/purescript_frontend.md"
      "Sprint 11.2"
  ]

startMarker :: Text -> Text
startMarker key = "<!-- jitml:" <> key <> ":start -->"

endMarker :: Text -> Text
endMarker key = "<!-- jitml:" <> key <> ":end -->"
