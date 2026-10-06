{-# LANGUAGE OverloadedStrings #-}

-- | The product phase catalogue and its derived status registry (Phase 288).
--
-- This module no longer holds a status literal. It holds a /catalogue/: the
-- closed set of product phases, the document each lives in, and for every sprint
-- either its legacy attestation or the obligations that must be proven before it
-- is Done. A sprint's status is projected from that catalogue plus the versioned
-- evidence "JitML.Product.StatusLoader" reads; see "JitML.Product.StatusEvidence"
-- for the relation.
--
-- Editing the catalogue is how a person changes what a sprint /owes/:
--
-- * to add an obligation, extend the sprint's list;
-- * to clear an 'ExternalContext' obligation, delete it in the same change that
--   replaces it with machine-observable obligations;
-- * to record that work has begun, flip 'Started' - the only declared status
--   input, which can never make a sprint Done;
-- * a sprint is Done only when the evidence exists. There is nothing to flip.
--
-- The legacy-attested class is frozen: 'frozenLegacyAttested' lists it, the
-- catalogue check rejects any legacy entry outside it, and a unit test pins the
-- list independently. It may shrink (a sprint reopened, or re-proven with
-- machine evidence) and can never grow.
module JitML.Product.PhaseStatus
  ( ProductPhaseStatus (..)
  , ProductSprintStatus (..)
  , SprintStatus (..)
  , firstProductPhase
  , frozenLegacyAttested
  , parseSprintStatus
  , productPhaseNumbers
  , productPhaseRange
  , productPhaseStatuses
  , productPhasesDone
  , productStandingObligations
  , productStatusCatalogue
  , projectProductStatus
  , renderSprintStatus
  , unfrozenLegacyProblems
  , validateProductPhaseStatuses
  , validateProductStatusCatalogue
  )
where

import Data.Foldable1 qualified as Foldable1
import Data.List qualified as List
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text

import JitML.Product.StatusEvidence
  ( Closure
  , EvidenceIndex
  , Obligation (..)
  , PhaseEntry (..)
  , SprintEntry (..)
  , SprintId
  , SprintProjection (..)
  , SprintStatus (..)
  , StatusReport
  , WorkState (..)
  , evidencedSprint
  , isLegacyClosure
  , legacyAttested
  , parseSprintStatus
  , projectStatusReport
  , renderSprintStatus
  , reportProjections
  , validateCatalogue
  )
import JitML.Product.ValidationRecord (ValidationGate (..))
import JitML.Substrate (Substrate (..))

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

-- | Obligations that guard the closure verdict rather than any one sprint. The
-- three gates are the standing realness gate of development-plan rule N on the
-- @linux-cpu@ aggregation lane; @jitml docs check@ and @jitml check-code@ are
-- computed when the closure is evaluated and so are not listed. The ledger must
-- have no Pending Removal row.
productStandingObligations :: [Obligation]
productStandingObligations =
  [ StandingGate JitmlUnit LinuxCPU
  , StandingGate JitmlNegativeControls LinuxCPU
  , StandingGate JitmlModelConvergence LinuxCPU
  , LedgerClear
  ]

-- | The catalogue: every product phase, one sprint each.
productStatusCatalogue :: [PhaseEntry]
productStatusCatalogue =
  [ legacyPhase
      220
      "Product Matrix Authority"
      "DEVELOPMENT_PLAN/phase-220-product-matrix-authority.md"
      "Closure Evidence"
  , legacyPhase
      221
      "Phase Status Registry"
      "DEVELOPMENT_PLAN/phase-221-phase-status-registry.md"
      "Closure Evidence"
  , legacyPhase
      222
      "Status Truth Enforcement"
      "DEVELOPMENT_PLAN/phase-222-status-truth-enforcement.md"
      "Closure Evidence"
  , legacyPhase
      223
      "Product Registry Plan and Admitted Evidence Projection"
      "DEVELOPMENT_PLAN/phase-223-product-registry-plan-and-admitted-evidence-projection.md"
      "Closure Evidence"
  , legacyPhase
      224
      "Remove Fossils"
      "DEVELOPMENT_PLAN/phase-224-remove-fossils.md"
      "Closure Evidence"
  , legacyPhase
      225
      "Scaffold Lint + Reachability"
      "DEVELOPMENT_PLAN/phase-225-scaffold-lint-reachability.md"
      "Closure Evidence"
  , legacyPhase
      226
      "Non-Fabricable Training Evidence"
      "DEVELOPMENT_PLAN/phase-226-non-fabricable-training-evidence.md"
      "Closure Evidence"
  , legacyPhase
      227
      "Type-State Pipeline (Haskell)"
      "DEVELOPMENT_PLAN/phase-227-type-state-pipeline-haskell.md"
      "Closure Evidence"
  , legacyPhase
      228
      "Dhall Boundary & Fail-Closed Decode"
      "DEVELOPMENT_PLAN/phase-228-dhall-boundary-fail-closed-decode.md"
      "Closure Evidence"
  , legacyPhase
      229
      "Phase-Specific Product Evidence Payloads"
      "DEVELOPMENT_PLAN/phase-229-phase-specific-product-evidence-payloads.md"
      "Validation"
  , legacyPhase
      230
      "Matrix Parity"
      "DEVELOPMENT_PLAN/phase-230-matrix-parity.md"
      "Validation"
  , legacyPhase
      231
      "Per-Row Runnable Dhall"
      "DEVELOPMENT_PLAN/phase-231-per-row-runnable-dhall.md"
      "Validation"
  , legacyPhase
      232
      "Read-Time Dataset SHA"
      "DEVELOPMENT_PLAN/phase-232-read-time-dataset-sha.md"
      "Validation"
  , legacyPhase
      233
      "Typed Layer IR + Reverse-Mode Autodiff"
      "DEVELOPMENT_PLAN/phase-233-typed-layer-ir-reverse-mode-autodiff.md"
      "Closure Evidence"
  , legacyPhase
      234
      "oneDNN Layer Kernels for Training"
      "DEVELOPMENT_PLAN/phase-234-onednn-layer-kernels-for-training.md"
      "Validation"
  , legacyPhase
      235
      "One Self-Describing Checkpoint Envelope"
      "DEVELOPMENT_PLAN/phase-235-one-self-describing-checkpoint-envelope.md"
      "Closure Evidence"
  , legacyPhase
      236
      "Checkpoint Admission Single-Path"
      "DEVELOPMENT_PLAN/phase-236-checkpoint-admission-single-path.md"
      "Closure Evidence"
  , legacyPhase
      237
      "Supervised Serving on the Layer-Graph IR"
      "DEVELOPMENT_PLAN/phase-237-supervised-serving-on-the-layer-graph-ir.md"
      "Closure Evidence"
  , legacyPhase
      238
      "Supervised Training on the Layer-Graph IR"
      "DEVELOPMENT_PLAN/phase-238-supervised-training-on-the-layer-graph-ir.md"
      "Closure Evidence"
  , legacyPhase
      239
      "Checkpoint Construction from the Trained Graph"
      "DEVELOPMENT_PLAN/phase-239-checkpoint-construction-from-the-trained-graph.md"
      "Closure Evidence"
  , legacyPhase
      240
      "Layer-Graph Checkpoints + Inference"
      "DEVELOPMENT_PLAN/phase-240-layer-graph-checkpoints-inference.md"
      "Closure Evidence"
  , legacyPhase
      241
      "oneDNN Device Training Kernels for Correct Operators"
      "DEVELOPMENT_PLAN/phase-241-onednn-device-training-kernels-for-correct-operators.md"
      "Validation"
  , legacyPhase
      242
      "Literal Architectures - Dense, MLP, LeNet"
      "DEVELOPMENT_PLAN/phase-242-literal-architectures-dense-mlp-lenet.md"
      "Closure Evidence"
  , legacyPhase
      243
      "Literal Architectures - ResNet Family"
      "DEVELOPMENT_PLAN/phase-243-literal-architectures-resnet-family.md"
      "Closure Evidence"
  , legacyPhase
      244
      "Literal Architectures - Vision Transformer"
      "DEVELOPMENT_PLAN/phase-244-literal-architectures-vision-transformer.md"
      "Closure Evidence"
  , legacyPhase
      245
      "Convergence and Evidence"
      "DEVELOPMENT_PLAN/phase-245-convergence-and-evidence.md"
      "Closure Evidence"
  , legacyPhase
      246
      "CompletedTraining SL Manifests"
      "DEVELOPMENT_PLAN/phase-246-completedtraining-sl-manifests.md"
      "Closure Evidence"
  , legacyPhase
      247
      "Real Environments"
      "DEVELOPMENT_PLAN/phase-247-real-environments.md"
      "Closure Evidence"
  , legacyPhase
      248
      "Distinct Algorithms"
      "DEVELOPMENT_PLAN/phase-248-distinct-algorithms.md"
      "Closure Evidence"
  , legacyPhase
      249
      "Per-Row Convergence and Evidence"
      "DEVELOPMENT_PLAN/phase-249-per-row-convergence-and-evidence.md"
      "Closure Evidence"
  , legacyPhase
      250
      "Typed RL Cohort and Action-Domain Compatibility"
      "DEVELOPMENT_PLAN/phase-250-typed-rl-cohort-and-action-domain-compatibility.md"
      "Closure Evidence"
  , legacyPhase
      251
      "TrainingPlan/EvaluationPlan Compiler and Trainer Migration"
      "DEVELOPMENT_PLAN/phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md"
      "Closure Evidence"
  , legacyPhase
      252
      "Typed Measured Counters and Evidence Separation"
      "DEVELOPMENT_PLAN/phase-252-typed-measured-counters-and-evidence-separation.md"
      "Closure Evidence"
  , legacyPhase
      253
      "Per-Game Self-Play"
      "DEVELOPMENT_PLAN/phase-253-per-game-self-play.md"
      "Closure Evidence"
  , legacyPhase
      254
      "Arena Convergence + Evidence"
      "DEVELOPMENT_PLAN/phase-254-arena-convergence-evidence.md"
      "Closure Evidence"
  , legacyPhase
      255
      "Train-and-Publish + Artifact Selectors"
      "DEVELOPMENT_PLAN/phase-255-train-and-publish-artifact-selectors.md"
      "Closure Evidence"
  , legacyPhase
      256
      "Row-Specific Renderers"
      "DEVELOPMENT_PLAN/phase-256-row-specific-renderers.md"
      "Closure Evidence"
  , legacyPhase
      257
      "Browser Fail-Closed"
      "DEVELOPMENT_PLAN/phase-257-browser-fail-closed.md"
      "Validation"
  , legacyPhase
      258
      "Row-Keyed Integration Matrix"
      "DEVELOPMENT_PLAN/phase-258-row-keyed-integration-matrix.md"
      "Closure Evidence"
  , legacyPhase
      259
      "Row-Complete Playwright"
      "DEVELOPMENT_PLAN/phase-259-row-complete-playwright.md"
      "Closure Evidence"
  , legacyPhase
      260
      "linux-cpu Report Card"
      "DEVELOPMENT_PLAN/phase-260-linux-cpu-report-card.md"
      "Closure Evidence"
  , legacyPhase
      261
      "Contract-Driven Live Execution - Integration Journal"
      "DEVELOPMENT_PLAN/phase-261-contract-driven-live-execution-integration-journal.md"
      "Closure Evidence"
  , legacyPhase
      262
      "Contract-Driven Live Execution - Browser and Playwright"
      "DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md"
      "Closure Evidence"
  , legacyPhase
      263
      "Contract-Driven Live Execution - Fragment Issuance"
      "DEVELOPMENT_PLAN/phase-263-contract-driven-live-execution-fragment-issuance.md"
      "Closure Evidence"
  , legacyPhase
      264
      "Real cuDNN/cuBLAS Kernels"
      "DEVELOPMENT_PLAN/phase-264-real-cudnn-cublas-kernels.md"
      "Closure Evidence"
  , legacyPhase
      265
      "CUDA Row Device Evidence"
      "DEVELOPMENT_PLAN/phase-265-cuda-row-device-evidence.md"
      "Validation"
  , legacyPhase
      266
      "CUDA Integration, E2E, and Attestation"
      "DEVELOPMENT_PLAN/phase-266-cuda-integration-e2e-and-attestation.md"
      "Closure Evidence"
  , legacyPhase
      267
      "GPU Performance and Persistent Device Buffers"
      "DEVELOPMENT_PLAN/phase-267-gpu-performance-and-persistent-device-buffers.md"
      "Validation"
  , legacyPhase
      268
      "Contract-Driven CUDA Lane Revalidation"
      "DEVELOPMENT_PLAN/phase-268-contract-driven-cuda-lane-revalidation.md"
      "Closure Evidence"
  , legacyPhase
      269
      "Registry:2 Migration and Harbor Deprecation"
      "DEVELOPMENT_PLAN/phase-269-registry2-migration-and-harbor-deprecation.md"
      "Validation"
  , legacyPhase
      270
      "Real Metal Kernels"
      "DEVELOPMENT_PLAN/phase-270-real-metal-kernels.md"
      "Validation"
  , legacyPhase
      271
      "Metal Row Device Evidence"
      "DEVELOPMENT_PLAN/phase-271-metal-row-device-evidence.md"
      "Validation"
  , legacyPhase
      272
      "Apple Integration, E2E, and Attestation"
      "DEVELOPMENT_PLAN/phase-272-apple-integration-e2e-and-attestation.md"
      "Closure Evidence"
  , legacyPhase
      273
      "Contract-Driven Apple Lane Revalidation"
      "DEVELOPMENT_PLAN/phase-273-contract-driven-apple-lane-revalidation.md"
      "Closure Evidence"
  , legacyPhase
      274
      "Attestation Join"
      "DEVELOPMENT_PLAN/phase-274-attestation-join.md"
      "Historical Closure Evidence"
  , legacyPhase
      275
      "No-Caveat Closure Guard"
      "DEVELOPMENT_PLAN/phase-275-no-caveat-closure-guard.md"
      "Historical Closure Evidence"
  , legacyPhase
      276
      "Journal-Derived Product Aggregation"
      "DEVELOPMENT_PLAN/phase-276-journal-derived-product-aggregation.md"
      "Closure Evidence"
  , legacyPhase
      277
      "Negative-Control Suite"
      "DEVELOPMENT_PLAN/phase-277-negative-control-suite.md"
      "Closure Evidence"
  , -- Validation: jitml-unit on linux-cpu (docs check and check-code are computed). The lane
    -- journals, the aggregate, and the Apple execution context are what keeps it open.
    evidencedPhase
      278
      "External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance"
      "DEVELOPMENT_PLAN/phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md"
      Started
      []
      ( LaneJournal LinuxCPU
          :| [ LaneJournal LinuxCUDA
             , LaneJournal AppleSilicon
             , Aggregate
             , GateTranscript JitmlUnit LinuxCPU
             , ExternalContext "Apple Silicon execution context"
             ]
      )
  , legacyPhase
      279
      "Measured/Declared Type Split & Behavioral Scaffold Lint"
      "DEVELOPMENT_PLAN/phase-279-measured-declared-type-split-behavioral-scaffold-lint.md"
      "Closure Evidence"
  , -- Validation: negative-controls and unit on linux-cpu; the pending-control list must
    -- hold nothing owned by this phase.
    evidencedPhase
      280
      "RunContract Negative Controls - Request and Event Fixtures"
      "DEVELOPMENT_PLAN/phase-280-runcontract-negative-controls-request-and-event-fixtures.md"
      Started
      ["278.1"]
      ( NoPendingControls 280
          :| [ GateTranscript JitmlNegativeControls LinuxCPU
             , GateTranscript JitmlUnit LinuxCPU
             ]
      )
  , -- Same shape as 280, for the journal fixtures and reducer properties.
    evidencedPhase
      281
      "RunContract Negative Controls - Journal Fixtures and Reducer Properties"
      "DEVELOPMENT_PLAN/phase-281-runcontract-negative-controls-journal-fixtures-and-reducer-p.md"
      Started
      ["280.1"]
      ( NoPendingControls 281
          :| [ GateTranscript JitmlNegativeControls LinuxCPU
             , GateTranscript JitmlUnit LinuxCPU
             ]
      )
  , -- Same shape as 280, for the lifecycle and per-row registration controls.
    evidencedPhase
      282
      "RunContract Negative Controls - Lifecycle and Per-Row Registration"
      "DEVELOPMENT_PLAN/phase-282-runcontract-negative-controls-lifecycle-and-per-row-registra.md"
      Started
      ["281.1"]
      ( NoPendingControls 282
          :| [ GateTranscript JitmlNegativeControls LinuxCPU
             , GateTranscript JitmlUnit LinuxCPU
             ]
      )
  , legacyPhase
      283
      "Per-Model Measured Convergence"
      "DEVELOPMENT_PLAN/phase-283-per-model-measured-convergence.md"
      "Closure Evidence"
  , legacyPhase
      284
      "Inference-Performance & Determinism"
      "DEVELOPMENT_PLAN/phase-284-inference-performance-determinism.md"
      "Closure Evidence"
  , -- Validation: model-convergence, negative-controls, and unit on linux-cpu. The stanza
    -- grades the selected lane's retained journal, so it stays unproven until that lane's
    -- journal is current.
    evidencedPhase
      285
      "Contract-Driven Per-Model Evidence"
      "DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md"
      Started
      ["282.1"]
      ( GateTranscript JitmlModelConvergence LinuxCPU
          :| [ GateTranscript JitmlNegativeControls LinuxCPU
             , GateTranscript JitmlUnit LinuxCPU
             ]
      )
  , legacyPhase
      286
      "Evidence-Derived Closure Guard"
      "DEVELOPMENT_PLAN/phase-286-evidence-derived-closure-guard.md"
      "Closure Evidence"
  , legacyPhase
      287
      "Standing Adversarial Audit & Thin Plan"
      "DEVELOPMENT_PLAN/phase-287-standing-adversarial-audit-thin-plan.md"
      "Closure Evidence"
  , -- Validation: unit and negative-controls on linux-cpu. Its upstream sprint is the
    -- last open evidence owner, so it awaits 285.1.
    evidencedPhase
      288
      "Journal-Derived Status Registry"
      "DEVELOPMENT_PLAN/phase-288-journal-derived-status-registry.md"
      Started
      ["285.1"]
      ( GateTranscript JitmlUnit LinuxCPU
          :| [GateTranscript JitmlNegativeControls LinuxCPU]
      )
  , -- Validation: unit, negative-controls, and model-convergence on linux-cpu; awaits 288.1.
    evidencedPhase
      289
      "Evidence-Typed Report Measurements"
      "DEVELOPMENT_PLAN/phase-289-evidence-typed-report-measurements.md"
      Started
      ["288.1"]
      ( GateTranscript JitmlUnit LinuxCPU
          :| [ GateTranscript JitmlNegativeControls LinuxCPU
             , GateTranscript JitmlModelConvergence LinuxCPU
             , GateTranscript JitmlE2e LinuxCPU
             ]
      )
  ]

-- | The legacy-attested class, frozen. Every 'legacyAttested' entry above must be
-- listed here, and no entry may be added: a sprint closed after machine evidence
-- existed must carry it.
frozenLegacyAttested :: [SprintId]
frozenLegacyAttested =
  [ "220.1"
  , "221.1"
  , "222.1"
  , "223.1"
  , "224.1"
  , "225.1"
  , "226.1"
  , "227.1"
  , "228.1"
  , "229.1"
  , "230.1"
  , "231.1"
  , "232.1"
  , "233.1"
  , "234.1"
  , "235.1"
  , "236.1"
  , "237.1"
  , "238.1"
  , "239.1"
  , "240.1"
  , "241.1"
  , "242.1"
  , "243.1"
  , "244.1"
  , "245.1"
  , "246.1"
  , "247.1"
  , "248.1"
  , "249.1"
  , "250.1"
  , "251.1"
  , "252.1"
  , "253.1"
  , "254.1"
  , "255.1"
  , "256.1"
  , "257.1"
  , "258.1"
  , "259.1"
  , "260.1"
  , "261.1"
  , "262.1"
  , "263.1"
  , "264.1"
  , "265.1"
  , "266.1"
  , "267.1"
  , "268.1"
  , "269.1"
  , "270.1"
  , "271.1"
  , "272.1"
  , "273.1"
  , "274.1"
  , "275.1"
  , "276.1"
  , "277.1"
  , "279.1"
  , "283.1"
  , "284.1"
  , "286.1"
  , "287.1"
  ]

-- | A phase whose single sprint was closed before machine evidence existed. The
-- last argument names the section of the phase document that records the
-- closure.
legacyPhase :: Int -> Text -> FilePath -> Text -> PhaseEntry
legacyPhase number title document section =
  singleSprintPhase number title document (legacyAttested section)

-- | A phase whose single sprint is Done only when its obligations are proven.
evidencedPhase
  :: Int
  -> Text
  -> FilePath
  -> WorkState
  -> [SprintId]
  -> NonEmpty Obligation
  -> PhaseEntry
evidencedPhase number title document work upstream obligations =
  singleSprintPhase number title document (evidencedSprint work upstream obligations)

singleSprintPhase :: Int -> Text -> FilePath -> Closure -> PhaseEntry
singleSprintPhase number title document closure =
  PhaseEntry
    { entryPhaseNumber = number
    , entryPhaseTitle = title
    , entryPhaseDocument = document
    , entrySprints =
        [ SprintEntry
            { entrySprintId = Text.pack (show number) <> ".1"
            , entrySprintTitle = title
            , entryClosure = closure
            }
        ]
    }

productPhaseNumbers :: [Int]
productPhaseNumbers = fmap entryPhaseNumber productStatusCatalogue

-- | The first product phase: Phase 220, Product Matrix Authority. The registry
-- has always started here, and the completeness checks measure the catalogue
-- against this floor rather than against its own smallest entry, so deleting the
-- first phase is a reported problem and not a smaller registry.
firstProductPhase :: Int
firstProductPhase = 220

-- | The first product phase and the last one the catalogue lists, read from the
-- catalogue rather than written into a message. The end moves when a phase is
-- appended; a phase dropped from the end is caught by the plan-document coverage
-- check in @jitml docs check@, which compares the catalogue with the phase
-- documents.
productPhaseRange :: (Int, Int)
productPhaseRange =
  case NonEmpty.nonEmpty productPhaseNumbers of
    Nothing -> (firstProductPhase, firstProductPhase)
    Just numbers -> (firstProductPhase, Foldable1.maximum numbers)

-- | Project the catalogue over an evidence index. Pure: the loader supplies the
-- index, and tests supply fixtures.
projectProductStatus :: EvidenceIndex -> StatusReport
projectProductStatus =
  projectStatusReport productStatusCatalogue productStandingObligations

-- | The registry view of a projection: phases in catalogue order, each with its
-- derived sprint statuses.
productPhaseStatuses :: StatusReport -> [ProductPhaseStatus]
productPhaseStatuses report =
  [ ProductPhaseStatus
      { phaseNumber = entryPhaseNumber phase
      , phaseTitle = entryPhaseTitle phase
      , phaseDocument = entryPhaseDocument phase
      , phaseSprints =
          [ ProductSprintStatus
              { sprintId = entrySprintId entry
              , sprintTitle = entrySprintTitle entry
              , sprintStatus = maybe Blocked projectionStatus (lookupProjection (entrySprintId entry))
              }
          | entry <- entrySprints phase
          ]
      }
  | phase <- productStatusCatalogue
  ]
 where
  lookupProjection sprint =
    List.find ((== sprint) . projectionSprint) (reportProjections report)

productPhasesDone :: [ProductPhaseStatus] -> Bool
productPhasesDone =
  all (all ((== Done) . sprintStatus) . phaseSprints)

-- | Problems in the projected registry shape: phases duplicated, missing from the
-- contiguous catalogue range, or unexpected, sprints missing or duplicated.
validateProductPhaseStatuses :: [ProductPhaseStatus] -> [Text]
validateProductPhaseStatuses phases =
  duplicatePhaseErrors
    <> phaseRangeProblems phaseNumbers
    <> concatMap validatePhase phases
 where
  phaseNumbers = fmap phaseNumber phases
  duplicatePhaseErrors =
    [ "duplicate product phase: " <> Text.pack (show number)
    | number <- duplicates phaseNumbers
    ]

-- | Phases missing from the contiguous run that starts at 'firstProductPhase' and
-- ends at the last phase listed, and phases below the first.
phaseRangeProblems :: [Int] -> [Text]
phaseRangeProblems phaseNumbers =
  [ "missing product phase: " <> Text.pack (show number)
  | number <- expectedNumbers
  , number `notElem` phaseNumbers
  ]
    <> [ "unexpected product phase: " <> Text.pack (show number)
       | number <- phaseNumbers
       , number `notElem` expectedNumbers
       ]
 where
  expectedNumbers = [firstProductPhase .. Foldable1.maximum (firstProductPhase :| phaseNumbers)]

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

-- | Problems in the catalogue itself: structural problems (duplicate ids,
-- backward or unresolved edges, blank citations), a gap in the phase run that
-- starts at 'firstProductPhase', and any legacy-attested entry outside the frozen
-- set.
validateProductStatusCatalogue :: [Text]
validateProductStatusCatalogue =
  validateCatalogue productStatusCatalogue
    <> phaseRangeProblems productPhaseNumbers
    <> unfrozenLegacyProblems frozenLegacyAttested productStatusCatalogue

-- | Every legacy-attested sprint of the catalogue that the frozen set does not
-- list. The class may shrink and can never grow, so any entry here is a problem.
unfrozenLegacyProblems :: [SprintId] -> [PhaseEntry] -> [Text]
unfrozenLegacyProblems frozen phases =
  [ "legacy attestation is frozen and shrink-only: "
      <> entrySprintId entry
      <> " is not in the frozen set"
  | phase <- phases
  , entry <- entrySprints phase
  , isLegacyClosure (entryClosure entry)
  , entrySprintId entry `notElem` frozen
  ]

duplicates :: (Ord a) => [a] -> [a]
duplicates values =
  [ value
  | value : _ : _ <- List.group (List.sort values)
  ]
