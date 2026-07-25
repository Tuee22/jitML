# Phase 223: Product Registry Plan and Admitted Evidence Projection

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Product Registry Plan and Admitted Evidence Projection. Single-session phase migrated from legacy Sprint 19.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 223.1: Product Registry Plan and Admitted Evidence Projection [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/{Matrix,Convergence,Evidence,Publisher,Completion,Benchmark}.hs`,
`src/JitML/Checkpoint/{Store,Writer}.hs`,
`src/JitML/Plan/{Plan,Workload}.hs`,
`src/JitML/{App,CLI/Spec,Inference/Command,RL/ProductBudget,RL/TrainerExecution,SL/TrainingExecution,Service/Command,Test/Command,Tune/Command}.hs`,
`src/JitML/RL/Command.hs`, `src/JitML/RL/Command/{AlphaZero,Options,Types}.hs`,
`src/JitML/RL/Algorithms/{DqnLoss,DqnTrainer}.hs`,
`src/JitML/SL/{Classifier,TrainingExecution}.hs`,
`src/JitML/Test/{WorkflowMatrix,Report,RunContract}.hs`,
`test/{unit,integration,e2e,sl-canonicals}/Main.hs`
**Docs to update**: `../README.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/training_workloads.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`phase-10-checkpointing-and-inference.md`

### Objective

The canonical product registry projects every row into one exact executable
plan and accepts checkpoint evidence only as the opaque persisted artifact
admitted by Sprint `10.12`. This sprint consumes admission; it does not define
the checkpoint wire format, persist checkpoint objects, verify pointer/blob
stability, or mint completion/inference eligibility. It owns the registry
portions of
[Exit Definition](README.md#exit-definition) items `30`, `31`, and `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Every product row has a kind-indexed descriptor that projects through one total
  function to a validated `RunPlan kind` or a typed configuration error.
- Row capability is a closed sum, so a declared/unsupported row cannot carry
  measured completion handles and a real row cannot omit its plan, criterion,
  integration contract, or evidence requirements.
- Workflow-matrix cells, report identity, and publisher identity derive from
  the same projection and reject duplicate, orphaned, or unprojectable rows.
- A publisher row counts as eligible only after Sprint `10.12` returns the
  opaque Store-admitted artifact for that row's exact `rowId`, `PlanId`,
  completed-training identity, and persisted artifact. Storage success and
  caller-held or in-memory proof values do not increment the eligible count.
- Supervised rows require their exact Product-origin V2 runtime. Canonical
  non-supervised ProductRows retain V1, but the publisher writes the exact RL
  trajectory, AlphaZero transcript, or tuning-v2 transcript first and binds its
  content-addressed pointer into the manifest before Store re-admission.
- Product report evidence is minted only from that opaque Store-admitted
  completion and retains the admitted manifest SHA. Exact manifest experiment,
  canonical row, `PlanId`, complete completion witness, budget/evidence kind,
  criterion, every dimensionally defined update-count relation, and family
  provenance must match the projection. Traditional RL retains the measured
  positive trainer update count from the admitted completion, but does not
  equate that count with the current overloaded RL descriptor; Sprint `25.4`
  owns the typed transition/update projection that makes that comparison exact.
- The full publisher and independent audit require exact agreement among all
  55 projected rows, admitted artifacts, inventory entries, and the v2 tuning
  transcript. The independent family inventory is 11 supervised V2, 39 RL V1,
  four AlphaZero V1, and one tuning V1, with 44 unique companion pointers.
- Matrix membership and public row identity remain stable while downstream state
  payloads migrate in Sprint `21.4`.

### Validation

```bash
docker compose --progress plain build jitml
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-resnet20
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row DQN/cartpole
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row DQN/mountain-car
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Validated on `linux-cpu` (live Kind cluster; 154-step rollout, all nine
components ready) on 2026-07-21 against immutable image `jitml:local`
`sha256:b9e84a80…`, its `check-code` embedded and green:

- **Datasets staged.** All 12 canonical dataset artifacts (MNIST ×4,
  Fashion-MNIST ×4, CIFAR-10, CIFAR-100, California Housing, Tiny ImageNet) were
  downloaded, SHA-256-verified against `JitML.SL.Dataset.canonicalArtifactSha256For`,
  and `jitml internal upload-dataset`'d into live MinIO (the publisher fail-closes
  without them).
- **Mandatory 55-row publisher.** `jitml internal train-and-publish-product-rows
  --linux-cpu` reported **rows 55, eligible 55, unsupported 0, errors 0**,
  admitted-inventory-entries 55, and one v2 tuning transcript. Each result is the
  opaque Store-admitted artifact for the exact projected `rowId`, `PlanId`,
  completed-training identity, and persisted manifest. The three historically-
  erroring focused rows (`cifar10-resnet20`, `DQN/cartpole`, `DQN/mountain-car`)
  each re-ran eligible.
- **Idempotent reuse.** The publisher's `publisherReuseAdmittedCheckpoint`
  re-admits an already-persisted checkpoint through the exact same
  `admitLatestCheckpoint`/`requireAdmittedCompletedCheckpoint` validation
  (companion receipts reconstructed from the admitted manifest's transcript
  pointers), so pre-training the rows in parallel then re-running the full
  publisher yields the same 55-eligible audit without retraining.
- **Suites.** `jitml-unit` **739 / 739**, `jitml-integration` **156 / 156**
  (incl. the live `-p Live` cases through daemon dispatch on the aligned cluster
  image), `jitml-negative-controls` **3 / 3** (the anti-self-referential-bar
  control still rejects), `jitml-model-convergence` **111 / 111**. `jitml docs
  check` and `jitml check-code` both exited `0`; the three zero-tolerance Rule-M
  scans hold.
- **Two committed-code contract gaps fixed (owned here).** (1)
  `JitML.Checkpoint.Store.completionStructuralGate` runs the pure
  manifest-completion legality check on the pointer-stable addressed manifest
  **before** any physical blob I/O, so an illegal completed manifest is rejected
  with its exact legality reason (`no completed-training witness`; supervised V1
  `inspection-only`) fail-closed; valid checkpoints — including all 55 product
  rows — still bind and admit exactly as before. (2) A non-product RL
  `median_final_reward` observation is externally anchored against the frozen
  `JitML.RL.ConvergenceThresholds` cohort set in `JitML.Product.ExternalBars`
  (env rewards are per-cohort, so the universal bar table intentionally has no
  single entry), unblocking `jitml rl train` / live-daemon RL checkpoint writes
  without weakening the anti-self-referential invariant.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
