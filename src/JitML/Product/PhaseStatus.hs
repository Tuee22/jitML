{-# LANGUAGE OverloadedStrings #-}

module JitML.Product.PhaseStatus
  ( ProductPhaseStatus (..)
  , ProductSprintStatus (..)
  , SprintStatus (..)
  , allProductPhaseStatuses
  , allProductPhasesDone
  , parseSprintStatus
  , productPhaseNumbers
  , productPhasesDone
  , renderSprintStatus
  , validateProductPhaseStatuses
  )
where

import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text

data SprintStatus
  = Done
  | Active
  | Planned
  | Blocked
  deriving stock (Eq, Ord, Show)

data ProductSprintStatus = ProductSprintStatus
  { sprintId :: Text
  , sprintTitle :: Text
  , sprintStatus :: SprintStatus
  }
  deriving stock (Eq, Show)

data ProductPhaseStatus = ProductPhaseStatus
  { phaseNumber :: Int
  , phaseTitle :: Text
  , phaseDocument :: FilePath
  , phaseSprints :: [ProductSprintStatus]
  }
  deriving stock (Eq, Show)

allProductPhaseStatuses :: [ProductPhaseStatus]
allProductPhaseStatuses =
  [ productPhase
      19
      "Product Truth Gates & Registry"
      "DEVELOPMENT_PLAN/phase-19-product-truth-gates.md"
      [ sprint "19.1" "Product Matrix Authority" Done
      , sprint "19.2" "Phase Status Registry" Done
      , sprint "19.3" "Status Truth Enforcement" Done
      ]
  , productPhase
      20
      "De-Fossilization & Scaffold Lint"
      "DEVELOPMENT_PLAN/phase-20-de-fossilization-and-scaffold-lint.md"
      [ sprint "20.1" "Remove Fossils" Done
      , sprint "20.2" "Scaffold Lint + Reachability" Done
      ]
  , productPhase
      21
      "Type-State DSL and Inference Eligibility"
      "DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md"
      [ sprint "21.1" "Non-Fabricable Training Evidence" Done
      , sprint "21.2" "Type-State Pipeline (Haskell)" Done
      , sprint "21.3" "Dhall Boundary & Fail-Closed Decode" Done
      ]
  , productPhase
      22
      "Canonical Matrix and Dataset Integrity"
      "DEVELOPMENT_PLAN/phase-22-canonical-matrix-and-dataset-integrity.md"
      [ sprint "22.1" "Matrix Parity" Done
      , sprint "22.2" "Per-Row Runnable Dhall" Done
      , sprint "22.3" "Read-Time Dataset SHA" Done
      ]
  , productPhase
      23
      "General Differentiable Layer Engine"
      "DEVELOPMENT_PLAN/phase-23-general-differentiable-layer-engine.md"
      [ sprint "23.1" "Typed Layer IR + Reverse-Mode Autodiff" Done
      , sprint "23.2" "oneDNN Layer Kernels for Training" Done
      , sprint "23.3" "Layer-Graph Checkpoints + Inference" Done
      ]
  , productPhase
      24
      "Real Supervised Architectures"
      "DEVELOPMENT_PLAN/phase-24-real-supervised-architectures.md"
      [ sprint "24.1" "Literal Architectures" Done
      , sprint "24.2" "Convergence and Evidence" Done
      , sprint "24.3" "CompletedTraining SL Manifests" Done
      ]
  , productPhase
      25
      "Real RL Algorithms and Environments"
      "DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md"
      [ sprint "25.1" "Real Environments" Done
      , sprint "25.2" "Distinct Algorithms" Done
      , sprint "25.3" "Per-Row Convergence and Evidence" Done
      ]
  , productPhase
      26
      "AlphaZero Real Self-Play Per Game"
      "DEVELOPMENT_PLAN/phase-26-alphazero-real-self-play.md"
      [ sprint "26.1" "Per-Game Self-Play" Done
      , sprint "26.2" "Arena Convergence + Evidence" Done
      ]
  , productPhase
      27
      "Demo All-Model Rendering"
      "DEVELOPMENT_PLAN/phase-27-demo-all-model-rendering.md"
      [ sprint "27.1" "Train-and-Publish + Artifact Selectors" Done
      , sprint "27.2" "Row-Specific Renderers" Done
      , sprint "27.3" "Browser Fail-Closed" Done
      ]
  , productPhase
      28
      "Per-Model Integration and E2E"
      "DEVELOPMENT_PLAN/phase-28-per-model-integration-and-e2e.md"
      [ sprint "28.1" "Row-Keyed Integration Matrix" Done
      , sprint "28.2" "Row-Complete Playwright" Done
      , sprint "28.3" "linux-cpu Report Card" Done
      ]
  , productPhase
      29
      "Linux CUDA Product Lane"
      "DEVELOPMENT_PLAN/phase-29-linux-cuda-product-lane.md"
      [ sprint "29.1" "Real cuDNN/cuBLAS Kernels" Done
      , sprint "29.2" "CUDA Row Device Evidence" Done
      , sprint "29.3" "CUDA Integration, E2E, and Attestation" Done
      ]
  , productPhase
      30
      "Apple Silicon Product Lane"
      "DEVELOPMENT_PLAN/phase-30-apple-silicon-product-lane.md"
      [ sprint "30.1" "Real Metal Kernels" Done
      , sprint "30.2" "Metal Row Device Evidence" Done
      , sprint "30.3" "Apple Integration, E2E, and Attestation" Done
      ]
  , productPhase
      31
      "No-Caveat Product Aggregation"
      "DEVELOPMENT_PLAN/phase-31-no-caveat-product-aggregation.md"
      [ sprint "31.1" "Attestation Join" Done
      , sprint "31.2" "No-Caveat Closure" Done
      ]
  ]

productPhaseNumbers :: [Int]
productPhaseNumbers = fmap phaseNumber allProductPhaseStatuses

allProductPhasesDone :: Bool
allProductPhasesDone = productPhasesDone allProductPhaseStatuses

productPhasesDone :: [ProductPhaseStatus] -> Bool
productPhasesDone =
  all (all ((== Done) . sprintStatus) . phaseSprints)

renderSprintStatus :: SprintStatus -> Text
renderSprintStatus Done = "Done"
renderSprintStatus Active = "Active"
renderSprintStatus Planned = "Planned"
renderSprintStatus Blocked = "Blocked"

parseSprintStatus :: Text -> Maybe SprintStatus
parseSprintStatus value =
  case Text.strip value of
    "Done" -> Just Done
    "Active" -> Just Active
    "Planned" -> Just Planned
    "Blocked" -> Just Blocked
    _ -> Nothing

validateProductPhaseStatuses :: [ProductPhaseStatus] -> [Text]
validateProductPhaseStatuses phases =
  duplicatePhaseErrors
    <> missingPhaseErrors
    <> unexpectedPhaseErrors
    <> concatMap validatePhase phases
 where
  phaseNumbers = fmap phaseNumber phases
  expectedNumbers = [19 .. 31]
  duplicatePhaseErrors =
    [ "duplicate product phase: " <> Text.pack (show number)
    | number <- duplicates phaseNumbers
    ]
  missingPhaseErrors =
    [ "missing product phase: " <> Text.pack (show number)
    | number <- expectedNumbers
    , number `notElem` phaseNumbers
    ]
  unexpectedPhaseErrors =
    [ "unexpected product phase: " <> Text.pack (show number)
    | number <- phaseNumbers
    , number `notElem` expectedNumbers
    ]

validatePhase :: ProductPhaseStatus -> [Text]
validatePhase phase =
  noSprintErrors <> duplicateSprintErrors
 where
  sprints = phaseSprints phase
  ids = fmap sprintId sprints
  prefix = "phase " <> Text.pack (show (phaseNumber phase))
  noSprintErrors =
    [prefix <> " has no sprints" | null sprints]
  duplicateSprintErrors =
    [ prefix <> " duplicate sprint id: " <> sprintId'
    | sprintId' <- duplicates ids
    ]

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]

productPhase :: Int -> Text -> FilePath -> [ProductSprintStatus] -> ProductPhaseStatus
productPhase number title document sprints =
  ProductPhaseStatus
    { phaseNumber = number
    , phaseTitle = title
    , phaseDocument = document
    , phaseSprints = sprints
    }

sprint :: Text -> Text -> SprintStatus -> ProductSprintStatus
sprint sprintId' title status =
  ProductSprintStatus
    { sprintId = sprintId'
    , sprintTitle = title
    , sprintStatus = status
    }
