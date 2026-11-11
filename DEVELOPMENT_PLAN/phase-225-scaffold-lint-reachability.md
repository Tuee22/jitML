# Phase 225: Scaffold Lint + Reachability

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Scaffold Lint + Reachability. Originally migrated from legacy Sprint 20.2 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `225.2`.
The earlier Sprint `225.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The new source/catalogue, runner and hardware controls remain unimplemented.
Sprint `221.2` owns reconciliation of the existing checker with these documented
targets; this documentation-only change supplies no machine-validation receipt.

## Sprint 225.2: Behavioral realness assurance before hardware qualification [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Lint/Stack.hs`, `test/negative-controls/Main.hs`.
**Blocked by**: Sprint `221.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/engineering/code_quality.md`, `../documents/engineering/product_completion_contract.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

CPU assurance rejects product paths that ignore trained values before expensive lane qualification; historical source-name denylisting is not treated as a behavioral proof.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Transfer the behavioral detector obligation from Phase `279` to this CPU foundation. Mac or NVIDIA qualification is not an upstream prerequisite for this assurance work.
- Validate a newly named constant-output fake and a trained-weight-dependent positive through direct, helper, alias and import paths; delete exemptions that make supported fake behavior invisible.
- Keep the claim bounded: output dependence is a necessary behavioral control, not a proof that an arbitrary function is a correct learning algorithm. Preserve real backend execution and scientific criteria as separate evidence.
- Keep measured/declared values and completion authority distinct across lint, reports and admission. A name, boolean or authored metric cannot mint measured or qualified evidence.

### Validation

1. Reject the renamed constant-output negative for the named behavioral reason and accept the genuine weight-dependent positive through all supported indirection forms.
2. Change trained weight bytes and observe the positive dependence control; verify declared or fabricated completion remains rejected through production admission.
3. Run the independently enumerated CPU behavioral/negative control group after its targeted failure passes; it consumes no Apple/CUDA journal. Complete negative-control transcript ownership remains downstream.

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

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Implement and independently validate the behavior controls and remove the future-owner/name-only exemptions they replace.
- Reconcile Phase `279` and product closure consumers with the ownership transfer; source-name checks alone cannot close the new sprint.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `225.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 225.1: Scaffold Lint + Reachability [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Lint/ProductTruth.hs`, `src/JitML/Lint/Stack.hs`, `src/JitML/Product/Matrix.hs`, `test/unit/Main.hs`
**Docs to update**: `../documents/engineering/code_quality.md`, `../documents/engineering/unit_testing_policy.md`, `system-components.md`

### Objective

A single lint pass forbids product code from naming or importing any scaffold
helper, and an import-edge reachability check proves the product command graph
cannot reach a fossil module.

### Deliverables

- `src/JitML/Lint/ProductTruth.hs` owns a forbidden-scaffold registry. Entries
  enforced by Sprint `20.2` — `deterministicStep`, `runRLLoop`,
  `runSimulatedEpisode*`, and `VecEnv` / `JitML.RL.VecEnv` — are scanned over
  `src/` only (`test/` is exempt so the relocated Sprint `20.1` scaffolding is
  legal).
- The same registry also carries future-owner entries for seeded
  `*-demo-weights`, identity-copy CUDA kernels, and degenerate CUDA/Metal
  convolution scaffolds. Those names feed the `ProductRow` implementation guard
  now, while hard source removal remains owned by Sprints `27.1`, `29.1`, and
  `30.1` in numerical order. Sprint `21.1` later promotes
  `completedTrainingFromMetrics` from future-owned entry to enforced removal.
- The pass adds an import-edge reachability check: starting from the
  `App.hs:runParsed` handlers, it walks the module import graph and fails when
  any product-reachable module imports a scaffold/fossil module.
- A `nonProductScaffolding` registry list plus a `test/unit/Main.hs` case
  guarantees no entry in that list is used as a `ProductRow.implementation` in
  `src/JitML/Product/Matrix.hs`.
- The pass is wired into `src/JitML/Lint/Stack.hs` alongside the existing
  `ForbiddenPaths`/`Chart`/`DhallNumerics` stages so it flows through both
  `jitml lint` and `jitml check-code`.
- The `code_quality.md` lint matrix and `system-components.md` lint inventory
  list the scaffold boundary and its reachability predicate.

The forbidden-module list is scoped to *dead* fakes: `JitML.RL.VecEnv` is
forbidden by name here only because the original module was a dead, zero-caller
fossil. When Phase `25` reintroduces a real, product-reachable, learning
`JitML.RL.VecEnv` (vectorized environments), the lint's forbidden-module entry
for that name is refined to permit the real module while the reachability walk
still fails any dead fossil. That refinement is owned by Phase `25`'s Remaining
Work and does not reopen Phase `20`.

### Validation

```bash
docker compose run --rm jitml jitml lint files                 # passed
docker compose run --rm jitml jitml test jitml-unit --linux-cpu # passed, 249/249 tests
docker compose run --rm jitml jitml docs check                  # passed
docker compose run --rm jitml jitml check-code                  # passed
```

### Closure Evidence

- **Closed obligation (Exit Definition: no product command path executes a fake).**
  As landed, `src/JitML/Lint/ProductTruth.hs` is a *name denylist* of the previous
  iteration's fossil names (`deterministicStep`, `runRLLoop`,
  `runSimulatedEpisode*`, `VecEnv` / `JitML.RL.VecEnv`) with a `FutureOwner`
  exemption that registers the seeded-`*-demo-weights` entries but never scans
  their behaviour. A new fake introduced under a new name — or hidden behind an
  exempted `FutureOwner` name — passes the lint unseen, so the pass does not prove
  the product command graph is free of fakes; it only re-checks yesterday's fossils.
- **Closing change.** Replace the name denylist with a *behavioral* detector that
  answers "does this product function's output depend on the trained weights?" over
  the product-reachable import graph, and delete the `FutureOwner` exemption so no
  name is waved through unscanned.
- **Negative-control validation.** This obligation is owned and closed by the Phase
  `32` anti-fake harness:
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map)
  Sprint `32.3` reimplements `ProductTruth.hs` as the behavioral detector and
  deletes the `FutureOwner` exemption, and the `jitml-negative-controls` suite
  (Sprint `32.1`) proves it by requiring the lint to *reject* a committed new-name
  fake (e.g. a dense layer labelled as convolution, or a stand-in whose output
  ignores the checkpoint):
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`.

The transfer remains in force. The historical statement that its stronger
behavioral half is closed is superseded by the
[Phase 279 reopening](phase-279-measured-declared-type-split-behavioral-scaffold-lint.md#phase-state):
that detector remains unmet and Blocked behind Phase `278`. Phase `225` retains
its completed source/reachability surface and does not reacquire that obligation.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/engineering/code_quality.md`.
- `../documents/engineering/product_completion_contract.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
