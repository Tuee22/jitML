# Phase 19: Product Truth Gates & Registry

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-20-de-fossilization-and-scaffold-lint.md](phase-20-de-fossilization-and-scaffold-lint.md), [../README.md](../README.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md)
**Generated sections**: none

> **Purpose**: Install one typed product-truth registry and machine-checkable
> gates so no fabricated, static-fixture, or representative-only evidence can
> satisfy the documented model product contract. Deterministic seeded executions
> count only through exact completed evidence, and the ambitious model surface
> cannot be narrowed away by a later agent.

## Phase State

✅ **Done** (reopened 2026-07-12 for Sprint `19.4`; unblocked 2026-07-20
after Phase `10` Sprint `10.12` closed; re-closed 2026-07-21). The total
kind-indexed row projection, opaque projection batch, exact internal executor,
completed-scenario report admission, and training/convergence corrections are
retained. Sprint `19.4` makes both publisher eligibility and completed-scenario
report admission consume Store's opaque admitted artifact. A write receipt or
caller-held completion is insufficient: the exact persisted manifest and
physical graph are re-read, then checked against projected row/experiment,
`PlanId`, full completion identity, and family provenance. The publisher also
gained an idempotent skip-if-admitted path (`publisherReuseAdmittedCheckpoint`)
that re-admits an already-persisted checkpoint through the exact same admission
validation rather than retraining, so the mandatory 55-row run re-admits every
pre-trained row and the batch audit reports **55 eligible, 0 unsupported, 0
errors**. Closing the mandatory `jitml-integration` lane additionally fixed two
pre-existing committed-code contract gaps this sprint owns: the completed-
admission path now rejects an illegal completed manifest on manifest-structural
completion legality **before** any physical blob I/O
(`JitML.Checkpoint.Store.completionStructuralGate`), and a non-product RL
`median_final_reward` observation is validated against the frozen
`JitML.RL.ConvergenceThresholds` cohort anchors rather than a missing universal
bar. Sprints `19.1`–`19.4` are Done; all validation below passed.

### Historical Publisher Evidence (diagnostic only)

The pre-admission `linux-cpu` runs remain useful training diagnostics, not
checkpoint eligibility evidence. The complete publisher traversed all **55**
rows and reported **52 eligible**, **0 unsupported**, and **3 errors**; the
failing rows were `cifar10-resnet20`, `DQN/cartpole`, and
`DQN/mountain-car`. Focused source/image probes later cleared those frozen bars,
and the tuning row emitted its v2 transcript. Those outcomes predate the exact
V2 supervised artifact and persisted admission boundary, so neither the
reported eligible count nor the stored objects can close Sprint `19.4`.

**Historical retained closure.** ✅ **Done** (reclosed 2026-07-06 after the
2026-07-05 realness audit). The 2026-07-01 model-runtime audit reopened product
closure and chose to implement the documented surface for real rather than
narrow the docs. The then-current Phase `0`–`18` results remain historical
evidence only; Phase `10` has since reopened for Sprints `10.6`/`10.12`. The
2026-07-05 findings were covered on their retained surfaces by
Sprints `32.1` and `34.1`; those historical gates do not satisfy the separately
reopened Sprints `32.4` and `34.3`.

The retained enforcement spine remains the typed product matrix, the Phase
`19`–`34` status registry, the external convergence-bar boundary, and the
docs-check closure-claim guard that every later product phase validates against.

**Validation substrate**: `linux-cpu` only.

## Objective

The repository owns one typed product-truth registry. Every documented model
row, every generated browser contract line, every README canonical table, and
every report-card row is generated from or parity-tested against that single
registry, and each row pins its own convergence obligation. A `MatrixFloor`
holds the ambitious surface — all eleven supervised rows, seven reinforcement
learning environments, the full stable-baselines3 algorithm family plus
AlphaZero, four AlphaZero games, and hyperparameter tuning — so a future agent
cannot delete rows to make closure cheaper. A separate typed phase-status
registry is the single source of Phase `19`–`34` sprint status, and `jitml docs
check` rejects any product-closure claim in governed docs while that registry
reports an unfinished product phase.

The forbidden-scaffold import lint is *not* owned here: the worktree must first
de-fossilize its scaffold helpers, so that enforcement is owned by Phase `20`.
This phase establishes the matrix floor, the per-row convergence bars (closing
gaps G3/G4 of the approved plan), and the status-truth gate that the rest of the
chain depends on.

## Sprint 19.1: Product Matrix Authority [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/Matrix.hs`, `src/JitML/Product/Convergence.hs`, `src/JitML/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `test/unit/Main.hs`
**Docs to update**: `../README.md`, `../documents/engineering/product_completion_contract.md`, `system-components.md`

### Objective

`src/JitML/Product/Matrix.hs` holds the single `ProductRow` ADT and the
`MatrixFloor` that pins the ambitious surface. `src/JitML/Web/Contracts.hs`
(`modelMatrixLines`), `src/JitML/Test/WorkflowMatrix.hs`, the README canonical
tables, and the report card are generated from or parity-tested against this one
registry rather than hand-maintained model-name lists.

### Deliverables

- A `ProductRow` ADT whose fields are `rowId`, `family`, `rowClass`,
  `implementation`, `experimentConfig`, a per-row `ConvergenceBar`, `deviceClaim`,
  phantom-tagged evidence handles (training, device, checkpoint, demo evidence
  parameterised by model state so a `Declared` row cannot carry a
  completed-training witness), `integrationTest`, `e2eTest`, and `demoPanel`.
- `src/JitML/Product/Convergence.hs` defines `ConvergenceBar` so every row pins
  its own metric and literature target minus slack — accuracy for the image and
  MLP rows, RMSE for California Housing regression, median evaluation return per
  `(env, algo)` for RL, and arena win-rate per AlphaZero game — instead of one
  shared representative threshold (closes gaps G3/G4).
- A `MatrixFloor` pins the ambitious surface and fails any registry that drops a
  member: the eleven supervised rows (MNIST shallow MLP, MNIST deep MLP with
  BatchNorm and Dropout, MNIST LeNet-5-variant CNN, Fashion-MNIST shallow MLP,
  Fashion-MNIST small ResNet, CIFAR-10 ResNet-20, CIFAR-10 ResNet-56, CIFAR-100
  Wide ResNet-28-10, CIFAR-10 small ViT, Tiny ImageNet ResNet-50, California
  Housing tabular-regression MLP); the seven RL environments (CartPole-v1,
  MountainCar-v0, Acrobot-v1, Pendulum-v1, LunarLander-v2 discrete,
  KeyDoorGrid-v0, GridWorld-Deterministic-v0); the stable-baselines3 algorithm
  family (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC,
  CrossQ, TQC, ARS, HER) plus AlphaZero self-play; the four AlphaZero games
  (Connect 4, Othello, Hex, Gomoku); and hyperparameter tuning.
- Generated browser contracts (`web/src/Generated/Contracts.purs` via
  `modelMatrixLines`) and report-card rows read from this registry.
- A unit test fails on duplicate row ids, undocumented rows, documented-but-
  unregistered rows, rows missing an integration or e2e test id, and any
  `MatrixFloor` violation.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu  # passed, 241/241 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- The `ProductRow` ADT, the single registry, and the `MatrixFloor` are real and
  met; the caveat is confined to the per-row **convergence-bar deliverable**. The
  bar is not derived from any external target at runtime: the checkpoint writer
  constructs each bar with `mkConvergenceBar name Maximise value 0.0`
  (`src/JitML/App.hs` `convergenceObservationsForMetrics` ~line 3597), so the
  threshold equals the measured value and `evaluateConvergence` evaluates
  `value >= value` (`src/JitML/Product/Convergence.hs:104`) — a slack-0 tautology
  that passes every row. Closed by Phase `32`, which moves the literature target
  into a frozen `src/JitML/Product/ExternalBars.hs` constant never derived from
  the measured value; the negative-control validation that shuts this gap is the
  `jitml-negative-controls` suite rejecting a bar set equal to its own measured
  value, and the per-row check is exercised by the `jitml-model-convergence`
  suite (Phase `33`).

## Sprint 19.2: Phase Status Registry [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Product/PhaseStatus.hs`, `test/unit/Main.hs`
**Docs to update**: `development_plan_standards.md`, `00-overview.md`, `system-components.md`

### Objective

`src/JitML/Product/PhaseStatus.hs` is the single typed source of Phase `19`–`34`
sprint status. A parity test asserts the typed registry agrees with the `Status`
headers declared in each `phase-*.md`.

### Deliverables

- A typed `PhaseStatus` registry enumerates every product phase (Phases `19`–`34`)
  and each of its sprints with a `Done | Active | Planned | Blocked` value.
- A parity test parses the `**Status**` header of every `phase-*.md` sprint block
  and asserts it equals the typed registry entry; any drift is a failure.
- The registry exposes a total `allProductPhasesDone` predicate that later gates
  consume, defined only over Phases `19`–`34`.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu  # passed, 244/244 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- None.

## Sprint 19.3: Status Truth Enforcement [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Lint/Docs.hs`, `src/JitML/Docs/Check.hs`, `test/unit/Main.hs`
**Docs to update**: `README.md`, `00-overview.md`, `system-components.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

Governed documentation cannot claim product closure while any product phase is
unfinished. `src/JitML/Lint/Docs.hs` scans governed docs for closure language and
`src/JitML/Docs/Check.hs` rejects it through `jitml docs check` unless the typed
`PhaseStatus` registry reports every product phase (Phases `19`–`34`) Done.

### Deliverables

- `jitml docs check` scans governed docs for closure claims — for example "all
  phases done", "no-caveat product complete", and "production ready" — and
  rejects them unless `allProductPhasesDone` is true for Phases `19`–`34`.
- Dated historical-evidence blocks that explicitly describe themselves as
  historical are exempt from the closure-claim rejection.
- A unit test asserts the scanner flags closure language while a product phase is
  Active or Blocked and passes only when the registry reports full closure.

### Validation

```bash
docker compose build jitml                                      # passed, image built with embedded check-code: ok
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml test jitml-unit --linux-cpu # passed, 246/246 tests
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- **Closed obligation (reopened 2026-07-05):** the closure guard is
  non-falsifiable. `src/JitML/Docs/Check.hs` rejects a closure claim only when
  the hand-edited `src/JitML/Product/PhaseStatus.hs` registry reports an
  unfinished phase, so status is trusted from a literal rather than proven from
  evidence — an agent can flip the registry to satisfy the guard without any
  model actually converging. The guard must instead derive
  `allProductPhasesDone` from machine-checkable evidence.
- **Closed by:** Phase `34` (`phase-34-plan-truth-governance.md`, Sprint `34.1`)
  extends the typed guard through Phases `32`–`34` and keeps closure language tied
  to the standing realness gate. The product phase-status parity test now parses
  every governed product phase document, `jitml docs check` gates closure claims
  on the full Phase `19`–`34` predicate, and the required validation includes
  `jitml-negative-controls` plus `jitml-model-convergence`.

## Sprint 19.4: Product Registry Plan and Admitted Evidence Projection [✅ Done]

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
- `documents/engineering/run_contract.md` — total product-row projection into a
  validated plan, Store-admitted publisher/report boundary, and required
  evidence contract.
- `documents/engineering/checkpoint_format.md` — distinguish supervised
  V1 inspection/resume from canonical non-supervised Product V1 completed
  admission and document exact companion-pointer binding.
- `documents/engineering/product_completion_contract.md` — record the matrix
  floor, per-row convergence bars, manifest-bound publication, and admitted
  report evidence as the binding closure surface.
- `documents/engineering/unit_testing_policy.md` — ownership of the matrix parity,
  exact admission/report tests, independent inventory, phase-status parity, and
  closure-claim tests.
- `documents/engineering/training_workloads.md` — document companion-first
  RL/AlphaZero/tuning publication and the exact tuning-v2 payload.
- `system-components.md` — inventory the Store-admitted publisher, report,
  companion-pointer, and independent 55-row audit surfaces.

**Product docs to create/update:**
- `README.md` — reopened product status and the registry-backed canonical tables.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md`, plus the governed
  `documents/engineering/training_workloads.md` workload contract.
