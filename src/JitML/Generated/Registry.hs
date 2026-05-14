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
    ( renderGeneratedSectionIndex
    , renderHelpBlocks
    , renderReadmeCommandRegistry
    , renderReadmeCommandTree
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
    ]

futureGeneratedSections :: [FutureGeneratedSection]
futureGeneratedSections =
    [ FutureGeneratedSection "cluster.routes" "documents/engineering/cluster_topology.md" "Sprint 3.4"
    , FutureGeneratedSection "numerics.layers" "documents/engineering/numerical_core.md" "Sprint 6.1"
    , FutureGeneratedSection "numerics.activations" "documents/engineering/numerical_core.md" "Sprint 6.2"
    , FutureGeneratedSection "numerics.spectral" "documents/engineering/numerical_core.md" "Sprint 6.3"
    , FutureGeneratedSection "numerics.optimizers" "documents/engineering/numerical_core.md" "Sprint 6.4"
    , FutureGeneratedSection "numerics.schedulers" "documents/engineering/numerical_core.md" "Sprint 6.5"
    , FutureGeneratedSection "numerics.losses" "documents/engineering/numerical_core.md" "Sprint 6.6"
    , FutureGeneratedSection "daemon.surface" "documents/engineering/daemon_architecture.md" "Sprint 5.3"
    , FutureGeneratedSection "training.rl.catalog" "documents/engineering/training_workloads.md" "Sprint 9.3"
    ]

startMarker :: Text -> Text
startMarker key = "<!-- jitml:" <> key <> ":start -->"

endMarker :: Text -> Text
endMarker key = "<!-- jitml:" <> key <> ":end -->"
