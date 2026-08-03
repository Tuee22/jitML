# Phase 261: Contract-Driven Live Execution - Integration Journal

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Integration Journal. Single-session phase migrated from legacy Sprint 28.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-08-01). The `linux-cpu` integration lane now derives
and executes all 55 `ProductRow` scenarios through the command-owned live
contract, authenticates their ordered version-3 aggregate journal, and requires
exact parent-side `Store` re-admission before reporting completion. Phase `262`
subsequently started. Current successor state lives in
[README.md → Closure Status](README.md#closure-status), not in this historical
phase snapshot.

## Sprint 261.1: Contract-Driven Live Execution - Integration Journal [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`,
`src/JitML/Test/ProductScenarioAuthorization.hs`,
`src/JitML/Test/ProductScenarioInterpreter/Internal.hs`,
`src/JitML/Test/ProductScenarioJournal.hs`,
`src/JitML/Test/ProductScenarioRunner.hs`, `src/JitML/Test/Report.hs`,
`src/JitML/Test/RunContract.hs`, `src/JitML/Test/Command.hs`,
`src/JitML/Test/LiveE2EScope.hs`, `src/JitML/Sub/Stream.hs`,
`src/JitML/Training/Budget.hs`, `src/JitML/Product/Publisher.hs`,
`src/JitML/Product/PhaseStatus.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/App.hs`
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

### Closure Evidence

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

## Documentation Requirements

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
