# Phase 89: Local Supervised Canonical Summaries

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Local Supervised Canonical Summaries. Single-session phase migrated from legacy Sprint 8.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 89.1: Local Supervised Canonical Summaries [✅ Done]

**Status**: Done
**Owned obligations after refactor**: code-surface only. Live dataset
fetching through `JitML.Service.MinIOSubprocess`, daemon-backed training
loop on real hardware, live measured convergence fixtures, and the live
SL convergence assertion in `jitml-sl-canonicals` migrated to Phase `15`
Sprint `15.4`. See
[phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map).
**Implementation**: `src/JitML/SL/Canonicals.hs`,
`test/sl-canonicals/Main.hs`
**Docs to update**: `documents/engineering/training_workloads.md`

### Objective

Stand up the supervised-learning catalog, dataset references, and local
canonical test surface. Real dataset loaders, daemon-backed training loops,
MinIO dataset access, and live statistical convergence assertions against
in-code thresholds are closed by the later no-caveat runtime and per-lane
closure phases (no per-substrate `.txt` curve fixtures will be committed per
[../README.md → Snapshot targets → Numerical-fixture
prohibition](../README.md#snapshot-targets)).

### Deliverables

- `src/JitML/SL/Canonicals.hs` declares the eleven current canonical cells:
  `mnist-shallow-mlp`, `mnist-deep-mlp`, `mnist-lenet`,
  `fashion-mnist-mlp`, `fashion-mnist-resnet`, `cifar10-resnet20`,
  `cifar10-resnet56`, `cifar100-wide-resnet`, `cifar10-vit`,
  `tiny-imagenet-resnet50`, and `california-housing-mlp`.
- `denseMlpCohort` names the current device-trainable Dense-MLP subset
  (`mnist-shallow-mlp`, `fashion-mnist-mlp`, `california-housing-mlp`), while
  the non-Dense rows remain target architecture entries until their
  forward/backward JIT codegen lands.
- `test/sl-canonicals/Main.hs` verifies the catalog is populated, the
  Dense-MLP cohort is stable and catalog-backed, and no committed numerical
  curve fixtures are required.
- `src/JitML/SL/Dataset.hs` declares the typed `DatasetRef` / `DatasetSplit`
  surface, the `canonicalDatasets` registry covering MNIST,
  Fashion-MNIST, CIFAR-10, CIFAR-100, Tiny ImageNet, and California
  Housing, the deterministic `expectedSha256` derivation,
  `datasetObjectRef`, `verifyDatasetBytes`, and `fetchDatasetRef` through
  the `HasMinIO` capability boundary.
- Live Pulsar training events backed by real `HasPulsar` and real
  MinIO-staged datasets are owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprints `15.2`, `15.3`, and `15.4` once the cluster is up.

### Validation

1. `cabal test jitml-sl-canonicals` exercises the eleven-cell canonical
   catalog, the Dense-MLP cohort, dataset refs, classifier training, and
   the local convergence-threshold helpers.
2. `jitml train experiments/mnist.dhall` routes through the substrate-backed
   device path once a live publication and staged dataset are present; offline
   execution fails closed with `TrainingPrerequisiteUnmet`.
3. Transferred live validation: a real training run against MNIST clears the
   in-code convergence threshold (`median(test_acc over k seeds) ≥
   literature_target − slack`), the trained checkpoint round-trips, and
   two fresh same-substrate / same-seed runs produce bit-identical
   `sha256(weights.bin)` compared against each other. No `test/golden/sl/`
   fixture is created per [../README.md → Snapshot targets →
   Numerical-fixture prohibition](../README.md#snapshot-targets).

### Remaining Work

- No sprint-owned code-surface Remaining Work remains. The live training
  path (`fetchDatasetRef` plumbing into `TrainingHandler`, daemon-backed
  loop, and the live SL statistical convergence assertion against the
  in-code literature-target threshold) is owned by
  [phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map)
  Sprint `15.4`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
