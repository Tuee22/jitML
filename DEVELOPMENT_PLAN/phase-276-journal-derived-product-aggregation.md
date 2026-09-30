# Phase 276: Journal-Derived Product Aggregation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Journal-Derived Product Aggregation. Single-session phase migrated from legacy Sprint 31.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-09-24 UTC). The CPU-only join admits the three pinned lane
journals and projects the exact **55-row / 165-cell** aggregate. All listed
validation gates passed on the live `linux-cpu` lane; neither accelerator was
rerun.

## Sprint 276.1: Journal-Derived Product Aggregation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/ProductAggregation.hs`,
`src/JitML/Test/ProductLaneJournal.hs`, `src/JitML/Test/Report.hs`,
`test/unit/ProductAggregation.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/product-aggregate.json`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Join the three committed lane journals into one product result without
reconstructing evidence from prose, test ids, or post-hoc probes. This sprint
owns the aggregation portion of
[Exit Definition](README.md#exit-definition) item `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Decode and validate each committed lane fragment as a versioned scenario
  journal whose rows carry matching `rowId`, `PlanId`, opaque Store-admitted
  artifact identity, substrate, and completed evidence.
- Join the three fragments by product-row identity and fail on missing,
  duplicated, mismatched, failed, or not-run cells.
- Derive all aggregate counts and report measurements from the joined typed
  results; no prose table or hand-edited total can manufacture coverage.
- Keep aggregation `linux-cpu` only and consume the committed accelerator
  fragments without rerunning either accelerator.
- Emit the merged report and closure input consumed by the external-truth and
  status-governance phases.

### Validation

The full integration stanza requires the real `linux-cpu` cluster. Build the
current source image, run `./bootstrap/linux-cpu.sh up`, and verify the twelve
canonical dataset objects through the published edge (upload any missing pinned
artifacts with `jitml internal upload-dataset`). Run unit and integration
against that ready publication. Record cluster health and retain this shared
CPU cluster for the following CPU phases; `./bootstrap/linux-cpu.sh down`
releases it when the live validation work ends. Retained accelerator
journals are read as evidence; no accelerator command is executed.

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Current Implementation

- `ProductAggregation` admits the three externally pinned portable journals
  against the registered path and SHA-256 pin and the complete current
  projection for each lane, then joins by row ID
  in canonical product order. Each opaque aggregate row contains exactly one
  CPU, CUDA, and Apple cell; lane-specific PlanIds remain distinct.
- The version-`1` aggregate retains source pins/run IDs, plan and admitted
  checkpoint identities, device witnesses, completion/measurement digests,
  refined completion payloads, measured counters, and convergence observations.
  Its counts and measurements are projections of admitted evidence.
- A retained aggregate is admitted only by recomputing its exact bytes from
  the pinned lane inputs. Markdown fragments remain presentation-only; their
  old freely constructible DTO and parsing/join APIs are removed.
- Unit negative fixtures cover missing/duplicate lanes and rows, row order,
  identity/substrate/manifest/contract/invocation drift, failed/not-run rows,
  malformed completion, unknown schema fields/versions, digest/canonicalization
  drift, and altered aggregate counts and source bindings. Integration reads
  the retained aggregate through the production admission path.

### Closure Evidence

- The three registered lane-journal paths and SHA-256 pins admit the current
  CPU, CUDA, and Apple fragments. Their exact join contains **55** product rows,
  **3** lanes, and **165** completed cells. The version-`1` retained aggregate
  is **532,989 bytes**, SHA-256
  `9ab0bbbfdcb8ebb98f255c386ec314252c6e521d240b42e7471e704f285a7396`.
  The focused aggregation group passed **39 / 39** adversarial tests.
- `docker compose build jitml` passed from the current source on 2026-09-23,
  producing image
  `sha256:2cb3f6cfce8c511671b5fabf75570c31f91736feee16f851543f52edcd5fa3aa`.
  `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up` passed
  **115** rollout steps. Its publication identifies `linux-cpu`, edge port
  **9091**, and all **8** components Ready. The cluster had **18** Running
  pods, **3** completed provisioning jobs, and **0** restarts.
- All **12** canonical dataset archives matched their pinned SHA-256 values
  (**629,581,277 bytes** total) and were uploaded through the published edge.
  The live integration inventory check passed for exactly those twelve
  objects and their verified bytes.
- On the current x86_64 Linux host, the full unfiltered container gates passed:
  `jitml-unit` **946 / 946**, `jitml-integration` **198 / 198** in
  **36,037.06 s**, `jitml-e2e` **27 / 27**, `jitml-negative-controls` **3 / 3**,
  and `jitml-model-convergence` **111 / 111**. Integration admitted and checked
  all **55** ProductRows, the aggregate family split and canonical order, the
  twelve-object inventory, the eight-cell live CLI WorkflowMatrix, and the
  live daemon, MinIO, Pulsar, GC, tuning, and AlphaZero cases.
- `jitml docs check`, `jitml check-code`, `git diff --check`, and the
  aggregation rule-`M` scan passed. The validation commands executed no
  accelerator lane. Current-host transcripts are retained under
  `.build/phase276-20260923/`.

The earlier arm64 CPU integration attempt observed `PPO/mountain-car` at
**−158** against the **−155** threshold and did not produce a complete
scenario journal. The current x86_64 full integration and the focused PPO
publisher both passed that row at **−151** without changing its bar, budget,
trainer, or retained lane journals. The arm64 result remains historical
machine-specific evidence; this phase's CPU aggregation and listed validation
passed on the current real `linux-cpu` lane.

## Documentation Requirements

**Engineering docs to create/update:**

- [Typed run contract](../documents/engineering/run_contract.md): registered journal authority, typed join, and canonical aggregate read-back.
- [Product completion contract](../documents/engineering/product_completion_contract.md): retained evidence and aggregate admission boundaries.
- [Unit testing policy](../documents/engineering/unit_testing_policy.md): CPU-only aggregation and adversarial admission coverage.

**Product docs to create/update:**

- [Project README](../README.md) and the plan control documents identify the current execution owner.
- `attestations/product-aggregate.json` retains the generated versioned report and closure input.

**Cross-references to add:**

- None.
