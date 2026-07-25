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
      220
      "Product Matrix Authority"
      "DEVELOPMENT_PLAN/phase-220-product-matrix-authority.md"
      [ sprint "220.1" "Product Matrix Authority" Done
      ]
  , productPhase
      221
      "Phase Status Registry"
      "DEVELOPMENT_PLAN/phase-221-phase-status-registry.md"
      [ sprint "221.1" "Phase Status Registry" Done
      ]
  , productPhase
      222
      "Status Truth Enforcement"
      "DEVELOPMENT_PLAN/phase-222-status-truth-enforcement.md"
      [ sprint "222.1" "Status Truth Enforcement" Done
      ]
  , productPhase
      223
      "Product Registry Plan and Admitted Evidence Projection"
      "DEVELOPMENT_PLAN/phase-223-product-registry-plan-and-admitted-evidence-projection.md"
      [ sprint "223.1" "Product Registry Plan and Admitted Evidence Projection" Done
      ]
  , productPhase
      224
      "Remove Fossils"
      "DEVELOPMENT_PLAN/phase-224-remove-fossils.md"
      [ sprint "224.1" "Remove Fossils" Done
      ]
  , productPhase
      225
      "Scaffold Lint + Reachability"
      "DEVELOPMENT_PLAN/phase-225-scaffold-lint-reachability.md"
      [ sprint "225.1" "Scaffold Lint + Reachability" Done
      ]
  , productPhase
      226
      "Non-Fabricable Training Evidence"
      "DEVELOPMENT_PLAN/phase-226-non-fabricable-training-evidence.md"
      [ sprint "226.1" "Non-Fabricable Training Evidence" Done
      ]
  , productPhase
      227
      "Type-State Pipeline (Haskell)"
      "DEVELOPMENT_PLAN/phase-227-type-state-pipeline-haskell.md"
      [ sprint "227.1" "Type-State Pipeline (Haskell)" Done
      ]
  , productPhase
      228
      "Dhall Boundary & Fail-Closed Decode"
      "DEVELOPMENT_PLAN/phase-228-dhall-boundary-fail-closed-decode.md"
      [ sprint "228.1" "Dhall Boundary & Fail-Closed Decode" Done
      ]
  , productPhase
      229
      "Phase-Specific Product Evidence Payloads"
      "DEVELOPMENT_PLAN/phase-229-phase-specific-product-evidence-payloads.md"
      [ sprint "229.1" "Phase-Specific Product Evidence Payloads" Done
      ]
  , productPhase
      230
      "Matrix Parity"
      "DEVELOPMENT_PLAN/phase-230-matrix-parity.md"
      [ sprint "230.1" "Matrix Parity" Done
      ]
  , productPhase
      231
      "Per-Row Runnable Dhall"
      "DEVELOPMENT_PLAN/phase-231-per-row-runnable-dhall.md"
      [ sprint "231.1" "Per-Row Runnable Dhall" Done
      ]
  , productPhase
      232
      "Read-Time Dataset SHA"
      "DEVELOPMENT_PLAN/phase-232-read-time-dataset-sha.md"
      [ sprint "232.1" "Read-Time Dataset SHA" Done
      ]
  , productPhase
      233
      "Typed Layer IR + Reverse-Mode Autodiff"
      "DEVELOPMENT_PLAN/phase-233-typed-layer-ir-reverse-mode-autodiff.md"
      [ sprint "233.1" "Typed Layer IR + Reverse-Mode Autodiff" Done
      ]
  , productPhase
      234
      "oneDNN Layer Kernels for Training"
      "DEVELOPMENT_PLAN/phase-234-onednn-layer-kernels-for-training.md"
      [ sprint "234.1" "oneDNN Layer Kernels for Training" Planned
      ]
  , productPhase
      235
      "Served-Path Tier-2 Wiring + Checkpoint Format Bump"
      "DEVELOPMENT_PLAN/phase-235-served-path-tier-2-wiring-checkpoint-format-bump.md"
      [ sprint "235.1" "Served-Path Tier-2 Wiring + Checkpoint Format Bump" Blocked
      ]
  , productPhase
      236
      "Layer-Graph Checkpoints + Inference"
      "DEVELOPMENT_PLAN/phase-236-layer-graph-checkpoints-inference.md"
      [ sprint "236.1" "Layer-Graph Checkpoints + Inference" Blocked
      ]
  , productPhase
      237
      "Literal Architectures - Dense, MLP, LeNet"
      "DEVELOPMENT_PLAN/phase-237-literal-architectures-dense-mlp-lenet.md"
      [ sprint "237.1" "Literal Architectures - Dense, MLP, LeNet" Blocked
      ]
  , productPhase
      238
      "Literal Architectures - ResNet Family"
      "DEVELOPMENT_PLAN/phase-238-literal-architectures-resnet-family.md"
      [ sprint "238.1" "Literal Architectures - ResNet Family" Blocked
      ]
  , productPhase
      239
      "Literal Architectures - Vision Transformer"
      "DEVELOPMENT_PLAN/phase-239-literal-architectures-vision-transformer.md"
      [ sprint "239.1" "Literal Architectures - Vision Transformer" Blocked
      ]
  , productPhase
      240
      "Convergence and Evidence"
      "DEVELOPMENT_PLAN/phase-240-convergence-and-evidence.md"
      [ sprint "240.1" "Convergence and Evidence" Blocked
      ]
  , productPhase
      241
      "CompletedTraining SL Manifests"
      "DEVELOPMENT_PLAN/phase-241-completedtraining-sl-manifests.md"
      [ sprint "241.1" "CompletedTraining SL Manifests" Blocked
      ]
  , productPhase
      242
      "Real Environments"
      "DEVELOPMENT_PLAN/phase-242-real-environments.md"
      [ sprint "242.1" "Real Environments" Done
      ]
  , productPhase
      243
      "Distinct Algorithms"
      "DEVELOPMENT_PLAN/phase-243-distinct-algorithms.md"
      [ sprint "243.1" "Distinct Algorithms" Done
      ]
  , productPhase
      244
      "Per-Row Convergence and Evidence"
      "DEVELOPMENT_PLAN/phase-244-per-row-convergence-and-evidence.md"
      [ sprint "244.1" "Per-Row Convergence and Evidence" Done
      ]
  , productPhase
      245
      "Typed RL Cohort and Action-Domain Compatibility"
      "DEVELOPMENT_PLAN/phase-245-typed-rl-cohort-and-action-domain-compatibility.md"
      [ sprint "245.1" "Typed RL Cohort and Action-Domain Compatibility" Blocked
      ]
  , productPhase
      246
      "TrainingPlan/EvaluationPlan Compiler and Trainer Migration"
      "DEVELOPMENT_PLAN/phase-246-trainingplan-evaluationplan-compiler-and-trainer-migration.md"
      [ sprint "246.1" "TrainingPlan/EvaluationPlan Compiler and Trainer Migration" Blocked
      ]
  , productPhase
      247
      "Typed Measured Counters and Evidence Separation"
      "DEVELOPMENT_PLAN/phase-247-typed-measured-counters-and-evidence-separation.md"
      [ sprint "247.1" "Typed Measured Counters and Evidence Separation" Blocked
      ]
  , productPhase
      248
      "Per-Game Self-Play"
      "DEVELOPMENT_PLAN/phase-248-per-game-self-play.md"
      [ sprint "248.1" "Per-Game Self-Play" Done
      ]
  , productPhase
      249
      "Arena Convergence + Evidence"
      "DEVELOPMENT_PLAN/phase-249-arena-convergence-evidence.md"
      [ sprint "249.1" "Arena Convergence + Evidence" Done
      ]
  , productPhase
      250
      "Train-and-Publish + Artifact Selectors"
      "DEVELOPMENT_PLAN/phase-250-train-and-publish-artifact-selectors.md"
      [ sprint "250.1" "Train-and-Publish + Artifact Selectors" Done
      ]
  , productPhase
      251
      "Row-Specific Renderers"
      "DEVELOPMENT_PLAN/phase-251-row-specific-renderers.md"
      [ sprint "251.1" "Row-Specific Renderers" Done
      ]
  , productPhase
      252
      "Browser Fail-Closed"
      "DEVELOPMENT_PLAN/phase-252-browser-fail-closed.md"
      [ sprint "252.1" "Browser Fail-Closed" Done
      ]
  , productPhase
      253
      "Row-Keyed Integration Matrix"
      "DEVELOPMENT_PLAN/phase-253-row-keyed-integration-matrix.md"
      [ sprint "253.1" "Row-Keyed Integration Matrix" Done
      ]
  , productPhase
      254
      "Row-Complete Playwright"
      "DEVELOPMENT_PLAN/phase-254-row-complete-playwright.md"
      [ sprint "254.1" "Row-Complete Playwright" Done
      ]
  , productPhase
      255
      "linux-cpu Report Card"
      "DEVELOPMENT_PLAN/phase-255-linux-cpu-report-card.md"
      [ sprint "255.1" "linux-cpu Report Card" Done
      ]
  , productPhase
      256
      "Contract-Driven Live Execution - Integration Journal"
      "DEVELOPMENT_PLAN/phase-256-contract-driven-live-execution-integration-journal.md"
      [ sprint "256.1" "Contract-Driven Live Execution - Integration Journal" Blocked
      ]
  , productPhase
      257
      "Contract-Driven Live Execution - Browser and Playwright"
      "DEVELOPMENT_PLAN/phase-257-contract-driven-live-execution-browser-and-playwright.md"
      [ sprint "257.1" "Contract-Driven Live Execution - Browser and Playwright" Blocked
      ]
  , productPhase
      258
      "Contract-Driven Live Execution - Fragment Issuance"
      "DEVELOPMENT_PLAN/phase-258-contract-driven-live-execution-fragment-issuance.md"
      [ sprint "258.1" "Contract-Driven Live Execution - Fragment Issuance" Blocked
      ]
  , productPhase
      259
      "Real cuDNN/cuBLAS Kernels"
      "DEVELOPMENT_PLAN/phase-259-real-cudnn-cublas-kernels.md"
      [ sprint "259.1" "Real cuDNN/cuBLAS Kernels" Done
      ]
  , productPhase
      260
      "CUDA Row Device Evidence"
      "DEVELOPMENT_PLAN/phase-260-cuda-row-device-evidence.md"
      [ sprint "260.1" "CUDA Row Device Evidence" Done
      ]
  , productPhase
      261
      "CUDA Integration, E2E, and Attestation"
      "DEVELOPMENT_PLAN/phase-261-cuda-integration-e2e-and-attestation.md"
      [ sprint "261.1" "CUDA Integration, E2E, and Attestation" Done
      ]
  , productPhase
      262
      "GPU Performance and Persistent Device Buffers"
      "DEVELOPMENT_PLAN/phase-262-gpu-performance-and-persistent-device-buffers.md"
      [ sprint "262.1" "GPU Performance and Persistent Device Buffers" Done
      ]
  , productPhase
      263
      "Contract-Driven CUDA Lane Revalidation"
      "DEVELOPMENT_PLAN/phase-263-contract-driven-cuda-lane-revalidation.md"
      [ sprint "263.1" "Contract-Driven CUDA Lane Revalidation" Blocked
      ]
  , productPhase
      264
      "Real Metal Kernels"
      "DEVELOPMENT_PLAN/phase-264-real-metal-kernels.md"
      [ sprint "264.1" "Real Metal Kernels" Done
      ]
  , productPhase
      265
      "Metal Row Device Evidence"
      "DEVELOPMENT_PLAN/phase-265-metal-row-device-evidence.md"
      [ sprint "265.1" "Metal Row Device Evidence" Done
      ]
  , productPhase
      266
      "Apple Integration, E2E, and Attestation"
      "DEVELOPMENT_PLAN/phase-266-apple-integration-e2e-and-attestation.md"
      [ sprint "266.1" "Apple Integration, E2E, and Attestation" Done
      ]
  , productPhase
      267
      "Contract-Driven Apple Lane Revalidation"
      "DEVELOPMENT_PLAN/phase-267-contract-driven-apple-lane-revalidation.md"
      [ sprint "267.1" "Contract-Driven Apple Lane Revalidation" Blocked
      ]
  , productPhase
      268
      "Attestation Join"
      "DEVELOPMENT_PLAN/phase-268-attestation-join.md"
      [ sprint "268.1" "Attestation Join" Done
      ]
  , productPhase
      269
      "No-Caveat Closure Guard"
      "DEVELOPMENT_PLAN/phase-269-no-caveat-closure-guard.md"
      [ sprint "269.1" "No-Caveat Closure Guard" Done
      ]
  , productPhase
      270
      "Journal-Derived Product Aggregation"
      "DEVELOPMENT_PLAN/phase-270-journal-derived-product-aggregation.md"
      [ sprint "270.1" "Journal-Derived Product Aggregation" Blocked
      ]
  , productPhase
      271
      "Negative-Control Suite"
      "DEVELOPMENT_PLAN/phase-271-negative-control-suite.md"
      [ sprint "271.1" "Negative-Control Suite" Done
      ]
  , productPhase
      272
      "External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance"
      "DEVELOPMENT_PLAN/phase-272-external-bars-no-self-referential-gate-lint-and-exact-served.md"
      [ sprint
          "272.1"
          "External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance"
          Blocked
      ]
  , productPhase
      273
      "Measured/Declared Type Split & Behavioral Scaffold Lint"
      "DEVELOPMENT_PLAN/phase-273-measured-declared-type-split-behavioral-scaffold-lint.md"
      [ sprint "273.1" "Measured/Declared Type Split & Behavioral Scaffold Lint" Done
      ]
  , productPhase
      274
      "RunContract Negative Controls - Request and Event Fixtures"
      "DEVELOPMENT_PLAN/phase-274-runcontract-negative-controls-request-and-event-fixtures.md"
      [ sprint "274.1" "RunContract Negative Controls - Request and Event Fixtures" Blocked
      ]
  , productPhase
      275
      "RunContract Negative Controls - Journal Fixtures and Reducer Properties"
      "DEVELOPMENT_PLAN/phase-275-runcontract-negative-controls-journal-fixtures-and-reducer-p.md"
      [ sprint "275.1" "RunContract Negative Controls - Journal Fixtures and Reducer Properties" Blocked
      ]
  , productPhase
      276
      "RunContract Negative Controls - Lifecycle and Per-Row Registration"
      "DEVELOPMENT_PLAN/phase-276-runcontract-negative-controls-lifecycle-and-per-row-registra.md"
      [ sprint "276.1" "RunContract Negative Controls - Lifecycle and Per-Row Registration" Blocked
      ]
  , productPhase
      277
      "Per-Model Measured Convergence"
      "DEVELOPMENT_PLAN/phase-277-per-model-measured-convergence.md"
      [ sprint "277.1" "Per-Model Measured Convergence" Done
      ]
  , productPhase
      278
      "Inference-Performance & Determinism"
      "DEVELOPMENT_PLAN/phase-278-inference-performance-determinism.md"
      [ sprint "278.1" "Inference-Performance & Determinism" Done
      ]
  , productPhase
      279
      "Contract-Driven Per-Model Evidence"
      "DEVELOPMENT_PLAN/phase-279-contract-driven-per-model-evidence.md"
      [ sprint "279.1" "Contract-Driven Per-Model Evidence" Blocked
      ]
  , productPhase
      280
      "Evidence-Derived Closure Guard"
      "DEVELOPMENT_PLAN/phase-280-evidence-derived-closure-guard.md"
      [ sprint "280.1" "Evidence-Derived Closure Guard" Done
      ]
  , productPhase
      281
      "Standing Adversarial Audit & Thin Plan"
      "DEVELOPMENT_PLAN/phase-281-standing-adversarial-audit-thin-plan.md"
      [ sprint "281.1" "Standing Adversarial Audit & Thin Plan" Done
      ]
  , productPhase
      282
      "Journal-Derived Status Registry"
      "DEVELOPMENT_PLAN/phase-282-journal-derived-status-registry.md"
      [ sprint "282.1" "Journal-Derived Status Registry" Blocked
      ]
  , productPhase
      283
      "Evidence-Typed Report Measurements"
      "DEVELOPMENT_PLAN/phase-283-evidence-typed-report-measurements.md"
      [ sprint "283.1" "Evidence-Typed Report Measurements" Blocked
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
  expectedNumbers = [220 .. 283]
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
