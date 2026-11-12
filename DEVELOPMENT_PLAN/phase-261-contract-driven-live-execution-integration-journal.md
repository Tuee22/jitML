# Phase 261: Contract-Driven Live Execution - Integration Journal

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Integration Journal. Originally migrated from legacy Sprint 28.4 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `261.2` → [306](phase-306-campaign-protocol.md).
- Former sprint `261.3` → [320](phase-320-qualification-epoch-freeze.md), [321](phase-321-cpu-qualification.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** on the expanded campaign obligations below. Historical closure
remains scoped to the execution and implementation it actually proved.

The [validation foundation refactor](README.md#validation-foundation-refactor)
owns the current execution order. Sprint `221.2` first updates the source
catalogue/checkers for the reopened sprint graph; those source changes are not
part of this documentation-only revision. Current machine projection still
reflects the old catalogue and must not be reported as validating these targets.

The [execution contract](../documents/engineering/validation_execution.md) and
[resource contract](../documents/engineering/execution_resources.md) state the
new targets. Atomic row recovery is not implemented or authorized by prose: until
`261.2` passes, existing qualification remains non-resumable. No historical partial
attempt, diagnostic review copy or readiness ledger is adopted as qualification.

## Sprint 261.2: Atomic row campaign protocol and authority [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `160.2`, Sprint `225.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

The production integration boundary issues an immutable campaign and commits only complete authenticated row cohorts. This protocol implementation precedes the real CPU campaign and does not require a completed Apple or CUDA lane.

### Deliverables

- Bind the full source stamp, executable/image/toolchain, ordered row contracts, dataset identities, substrate/device, independent criterion identity and execution policy in an immutable manifest.
- Persist campaign authority in an owned private nonlink scope outside row-child mounts and diagnostics. Define key retention, loss, rotation refusal, atomic writes/fsync, exclusive ownership and restart verification; document the trusted local issuer boundary.
- Commit a row only after all prescribed five outcomes, authentic initial/final evidence, fixed seeds and served index zero, measured counters, exact Store/replay and required preservation proofs pass. A completed seed or checkpoint alone is not a resumable unit.
- Make individual-row selection exercise the same producer and admission path as the complete campaign. Selecting one row must not silently acquire/traverse 55; listing tests starts no training.
- Append every attempt, scientific refusal and interruption. Restart verifies prior committed objects and reruns an unfinished whole row; no mid-seed trainer resume, historical prefix adoption, mixed epochs, omitted failure or favorable-seed substitution. A scientific refusal blocks admission rather than permitting a silent same-epoch retry search.
- Own durable retention pins and a bounded disk/lifetime reservation for each row's weights, companions, outcomes, journal and Store snapshots across GC, pause and VM restart. Release only after portable/downstream retention duties or explicit recorded abandonment.
- Bind finite infrastructure retries and absolute campaign expiry; owner classification records its predicate, ambiguous partial execution refuses retry, and reconnect/new identifiers cannot reset attempts or conceal scientific refusal.
- Final admission reopens/rechecks every object and exactly joins all 55 rows; aggregate integration and preservation operate on admitted objects without retraining completed rows. Full-source invalidation remains conservative.

### Validation

Closure requires the owned targeted/hermetic controls listed above, with a
nonempty independently enumerated test inventory and exact scoped transcripts.
The implementation publishes actual selectable groups in the existing stanzas
and uses the supported `--test-options` passthrough; no invented selector or
unfiltered full-matrix acquisition is an acceptable substitute. A scoped result
is recorded as scoped, never as a passing full stanza. Resource/live controls
also require the actual owned runtime observations named above.

Complete evidence-dependent unit/integration/negative-control transcripts belong
to Sprints `277.2` and `280.2`; cross-family convergence belongs to `283.2` and
`285.2`. Those downstream records are not prerequisites for this foundation or
readiness closure. Every original case remains registered with an explicit owner.
The existing documentation/code-quality commands below run after source parity
is implemented, inside the admitted profile; they do not execute these controls.


These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Use controlled fixtures for crashes before/after row commit and final commit, truncated writes, concurrent owner, source/device/policy mismatch, foreign receipt, replay/rollback, lost authority, artifact replacement, reordered seeds and omitted failures.
2. Verify that missing after-state proof leaves a row unqualified; earlier sealed rows survive only when their exact evidence and preservation boundary verify.
3. Demonstrate observer disconnect/reconnect with the same owned execution, bounded capture and unchanged result; supervisor or safety-reader loss retires owned work.
4. Exercise GC/pause/VM restart with committed row pins, disk refusal, retry exhaustion, campaign expiry and a new-identifier refusal bypass. Measure aggregate retention/publication over a complete 55 fixture; test real completed row objects through the same readers before hardware qualification. No fixture certifies scientific memory fit.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement the deliverables after the listed prerequisites; retain every failed or incomplete observation in its original scope.
- Complete the listed acceptance in its declared evidence scope, retain the required records, and reconcile the source status catalogue before claiming closure.

## Sprint 261.3: Current CPU qualification campaign [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`, Sprint `115.2`, Sprint `245.2`, Sprint `249.2`, Sprint `254.2`, Sprint `278.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Execute the complete current linux-cpu scientific campaign through the qualified protocol. Protocol readiness and all known scientific failures precede acquisition.

### Deliverables

- Freeze source/image/toolchain, independent reviews, approved recipes and acceptance predicates, resources, deadlines and dataset/Store identities before qualifying work.
- Acquire every required CPU row with real oneDNN and full cohort evidence; sealed rows may survive observer/session changes only through the new verified campaign protocol.
- Admit combined numerical, launcher, helper, capture and retained-result memory fit; verify final complete 55 aggregation and original data/preservation boundaries.
- Keep the retained 40/55 mixed-source readiness result historical. It is not final-source qualification and cannot seed this campaign.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Complete real CPU backend, scientific matrix, full journal/readmission and accumulation checks with no known unresolved readiness failure.
2. Retain every failure with the triggering resource sample, original streams, terminal result and stop/preservation outcome; no automatic source rebinding.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-backends --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-integration --linux-cpu --test-options='-p "Phase 261 ProductRow contract-driven integration matrix"'
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement 261.2 and independently bind final-source criteria under 278.2 before enabling resumable row qualification. Until then current acquisition remains non-resumable.
- Repair every known science/resource failure through its owner, then run and admit a fresh complete CPU campaign.
- Retain all original failed attempts literally and complete the original data, state, publication and cleanup checks.

## Retained Historical Contract and Evidence

The remainder records prior implementation, commands, status and failures. Its
claims retain their original source, policy and date. Superseded launch ordering,
resource rules and uninterrupted-process requirements do not override the current
sprints above. Preserve these receipts; do not execute a historical recipe as a
current authorized campaign.

## Retained Historical Phase State

✅ **Done** (re-closed 2026-09-08). The `linux-cpu` integration lane derives and
executes all 55 `ProductRow` scenarios, authenticates the version-3 aggregate
before its temporary scope disappears, and atomically retains the canonical
version-1 portable typed projection. The exact 175,172-byte journal is tracked
at [attestations/linux-cpu-product-lane-journal.json](attestations/linux-cpu-product-lane-journal.json)
with pinned SHA-256
`f1bdb6d7941327e44ab9045c45d6f73dfaa96aa37e01234eb4f3969f8e5eb273`.
That 2026-09-08 journal and digest are historical: Phase `278` tightened three
convergence bars, and its fresh `linux-cpu` run of this sprint's subtree
replaced the retained journal with the 175,168-byte artifact pinned by SHA-256
`438931ad8c49e1e7365e441ae519fc02df4443895416c80b599c50f89dac05ff`; see
[Phase 278 → Current Partial Validation](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#current-partial-validation).

## Sprint 261.1: Contract-Driven Live Execution - Integration Journal [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`,
`src/JitML/Test/ProductScenarioAuthorization.hs`,
`src/JitML/Test/ProductScenarioInterpreter/Internal.hs`,
`src/JitML/Test/ProductScenarioJournal.hs`,
`src/JitML/Test/ProductLaneJournal.hs`,
`src/JitML/Test/ProductScenarioRunner.hs`, `src/JitML/Test/Report.hs`,
`src/JitML/Test/RunContract.hs`, `src/JitML/Test/Command.hs`,
`src/JitML/Test/LiveE2EScope.hs`, `src/JitML/Sub/Stream.hs`,
`src/JitML/Training/Budget.hs`, `src/JitML/Product/Publisher.hs`,
`src/JitML/Product/PhaseStatus.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/App.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cpu-product-lane-journal.json`
**Docs to update**: `../README.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/checkpoint_format.md`, `README.md`, `00-overview.md`,
`development_plan_standards.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`,
`phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md`,
`phase-252-typed-measured-counters-and-evidence-separation.md`,
`phase-262-contract-driven-live-execution-browser-and-playwright.md`,
`phase-268-contract-driven-cuda-lane-revalidation.md`

### Objective

Derive one scenario per `ProductRow` from the Phase `220` plan projection and
execute it through Sprint `160.1`'s `runLiveWorkflow` interpreter, so every
`linux-cpu` integration row cell closes only from measured completed evidence
rather than an artifact-only read, stdout prefix, declared test id, or green
exit code. This sprint owns the integration-side per-row portion of
[Exit Definition](README.md#exit-definition) items `31` and `34`. The binding
design is [README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Derive one scenario per `ProductRow` from the Phase `220` plan projection and
  execute it through Sprint `160.1`'s `runLiveWorkflow` interpreter.
- Require integration row reports to consume the completed evidence journal, not
  an artifact-only read, stdout prefix, declared test id, or green exit code.
- Bind training, checkpoint, inference, and negative-control evidence to the same
  `rowId`, `PlanId`, artifact hash, and substrate.

### Validation

The live integration gate has explicit operational prerequisites. Build the
final `jitml:local` image, invoke the script's `up` verb, and manually stage all
12 canonical dataset artifacts (MNIST and Fashion-MNIST train/test images and
labels, plus the CIFAR-10, CIFAR-100, Tiny ImageNet, and California Housing
archives) through `jitml internal upload-dataset`. Dataset first use never
downloads or populates MinIO. When the source files live under host `/tmp`, the
outer Linux Compose container must receive an explicit read-only bind and
`--path` must name the mounted container path, for example:

```bash
JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up
docker compose run --rm \
  --volume /tmp/jitml-datasets:/datasets:ro \
  jitml jitml internal upload-dataset \
  --name MNIST --split train --artifact images \
  --path /datasets/mnist/train-images-idx3-ubyte.gz
```

For a fresh `linux-cpu` cluster without a persisted coordinate, bootstrap
prefers edge port `9091`, then the remaining members of the finite
`9090`/`9091`/`9092` candidate set. Consume the selected port from
`.build/runtime/cluster-publication.json`; do not hardcode it.

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
docker compose run --rm jitml jitml docs check
```

### Historical Closure Evidence

Validated 2026-08-01 in the project container against immutable image
`sha256:051ddff67e55e0d480a4ab7324cb0d5893330186451db35ef7ae81e207ddd72a`;
every closure gate exited zero:

- `jitml test jitml-integration --linux-cpu` — all 161 tests passed, including
  all 60 tests in the Phase `261` subtree.
- The live scenario run completed all 55 ordered `ProductRow` records, produced
  an authenticated version-3 aggregate journal, and passed exact parent-side
  `Store` re-admission.
- `jitml test jitml-unit --linux-cpu` — all 772 tests passed.
- `jitml check-code` — `check-code: ok`.
- `jitml docs check` — `docs check: ok`.

The validated cluster publication reported all nine components live-ready, and
the staged dataset inventory contained exactly the 12 canonical artifacts.

### Closure Evidence

Validated 2026-09-08 against immutable image
`sha256:da16ed8cf65cac1bfd6803798c7fd31b2324dbf980b160529dd795840c7dbe22`:

- `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up` passed all
  115 rollout steps; all 12 governed datasets were staged with their canonical
  SHA-256 identities.
- `jitml test jitml-integration --linux-cpu` exited `0`, completed all 55
  ordered ProductScenario rows, authenticated their exact current-run source
  journal, and wrote the portable candidate.
- The tracked file is byte-identical to that candidate. Its pinned SHA-256 is
  `f1bdb6d7941327e44ab9045c45d6f73dfaa96aa37e01234eb4f3969f8e5eb273`;
  the production `admitProductLaneJournal` reader admitted all 55 rows against
  the current `linux-cpu` projection.
- `jitml test jitml-unit --linux-cpu` passed all **907 / 907** tests, including
  canonical encoding, expected-digest, identity-drift, manifest-drift, typed
  completion, and phase-status controls.
- `jitml check-code`, `jitml docs check`, and `git diff --check` passed.

## Historical Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/unit_testing_policy.md`
- `../documents/engineering/product_completion_contract.md`
- `../documents/engineering/run_contract.md`
- `../documents/engineering/checkpoint_format.md`

**Product docs to create/update:**

- `../README.md`
- `README.md`
- `00-overview.md`
- `development_plan_standards.md`
- `system-components.md`
- `legacy-tracking-for-deletion.md`
- `phase-251-trainingplan-evaluationplan-compiler-and-trainer-migration.md`
- `phase-252-typed-measured-counters-and-evidence-separation.md`
- `phase-262-contract-driven-live-execution-browser-and-playwright.md`
- `phase-268-contract-driven-cuda-lane-revalidation.md`

**Cross-references to add:**

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- [Validation execution](../documents/engineering/validation_execution.md),
  [execution resources](../documents/engineering/execution_resources.md),
  [run contract](../documents/engineering/run_contract.md), and
  [testing policy](../documents/engineering/unit_testing_policy.md).

**Product docs to create/update:**

- [Plan](README.md#validation-foundation-refactor), [overview](00-overview.md),
  [component inventory](system-components.md), and the corresponding lane
  report/portable evidence after actual qualification.

**Cross-references to add:**

- The current typed catalogue and [legacy removal ledger](legacy-tracking-for-deletion.md)
  name every changed owner and deprecated active path; original evidence is retained.
