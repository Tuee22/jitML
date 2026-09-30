# Phase 278: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance. Single-session phase migrated from legacy Sprint 32.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-09-24 UTC). Phase `276` / Sprint `276.1` is Done. This phase
is implementing the external-bar, anti-self-reference, and exact served-byte
checks below.

## Sprint 278.1: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Product/ExternalBars.hs`,
`src/JitML/Product/ServedMetric.hs`, `src/JitML/Lint/ProductTruth.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Product/Publisher/Supervised.hs`, `test/unit/Main.hs`,
`test/unit/SupervisedCheckpointV2.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`, `../documents/engineering/determinism_contract.md`, `system-components.md`

### Objective

Convergence bars are frozen external literature constants and a lint bans any
threshold derived from the value it checks. Persisted artifact binding is
implemented by Sprints `127.1`/`133.1`; this sprint owns the independent
external-truth predicates used to grade that boundary and, after aggregation,
the proof that a reported measurement was recomputed from the exact admitted
bytes subsequently served.

### Deliverables

- `src/JitML/Product/ExternalBars.hs` verifies ProductRow convergence against
  the immutable literature targets and project-calibrated slack declared in the
  supervised and RL threshold tables. The dataset SHAs and arena baselines stay
  in their canonical registries; none is derived from a measured result.
- A lint (`ProductTruth.hs`) statically rejects the `mkConvergenceBar … measuredValue 0.0`
  / `threshold = measured` pattern anywhere on a product path.
- The external-bar predicate re-derives `coPassed` from finite measurements
  rather than trusting a stored boolean. Current served-weight, manifest, blob,
  and dataset binding is not minted here; Sprint `133.1` exposes only an opaque
  admitted artifact for this harness to challenge.
- Bind the aggregated ProductRow claim to that opaque admitted manifest address
  and its exact served `supervised.weights` bytes, recompute the reported metric
  through the admitted runtime, and reject metadata-consistent byte
  substitution.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Closure Evidence

- Implemented the module and lint and exercised the former decode-time check.
  That old re-encoded-manifest/served-weight assertion is historical and does
  not close exact V2 persistence or admission; the retained closure here is the
  external-bar and no-self-reference grader.

### Current Partial Validation

- On 2026-09-24, the worktree's direct measured-target lint, finite and
  target/slack-consistent bar gate, cohort-specific ProductRow reward check,
  and regression controls passed `jitml-unit --linux-cpu` (**949/949**).
  `jitml docs check`, `jitml check-code`, and `git diff --check` also passed.
  These checks validate the implemented subset; the Remaining Work below is
  required before this phase can be Done.
- On the real `linux-cuda` device (RTX 5090, compute capability 12.0), a fresh
  `PPO/key-door-grid` training and publication run reproduced the retained
  failure: all 20 evaluation episodes returned `-2.79` after the full
  1,228,800-step training budget. The admitted manifest SHA was
  `ac06586d74bba55a329b9a9bee3021aa75dc8c79fa7bc4baa80a518118aada10`.
  This is diagnostic evidence for the old trainer/bar, not passing evidence for
  the tightened bar. A fresh run on the same GPU with two PPO update epochs
  (formerly ten) and otherwise identical seed and environment-step budget
  returned `1.43` in all 20 evaluation episodes, each finishing in ten steps.
  Its admitted manifest SHA was
  `6f1f0fc372e4185da5762d093930f5cd2fe363ee3f4621eeeeef093d4ac3d447`.
  These two checkpoint snapshots are preserved separately under
  `.build/phase278-20260924/`; neither is a replacement for a new lane journal
  under the tightened bar.
- The same CUDA PPO run was repeated from a fresh checkpoint with the
  worktree's tightened `0.5` key-door bar. Publication exited `0`, admitted
  manifest
  `d2af3afb725f07191be2d97f183c27347c32e29092287125fbb766e8f76fd1c8`,
  and retained the same `1.43` trajectory SHA as the focused experiment.
  `./bootstrap/linux-cuda.sh up` then passed **112** live rollout steps; its
  publication identifies `linux-cuda`, edge port **9092**, and all **8**
  components Ready. All **12** canonical dataset objects were copied byte for
  byte from the still-running CPU MinIO publication and uploaded through
  `jitml internal upload-dataset` into the CUDA publication with their pinned
  hashes. This prepares, but does not replace, a fresh 55-row CUDA journal.
- The worktree now carries the verified held-out example set from supervised
  training to a post-Store-admission `ServedMetric` check. The check prepares
  the exact admitted graph and physical weight tensor once, reruns the
  evaluation inputs through the serving runtime, and compares accuracy or RMSE
  to the reported metric before eligibility. Supervised reuse is disabled
  because a prior checkpoint has no held-out example set to verify this way.
  The focused CUDA compile and substitution controls passed; the full phase
  validation gates remain open until the lane journals are reissued.
- The first current-source `jitml-unit --linux-cuda` attempt ran **954** tests
  and failed **10**. Nine failures came from Phase `276` aggregate fixtures
  correctly rejecting the old lane journals under the new bars; they require
  fresh CPU, CUDA, and Apple journals. The tenth found that the initial
  accuracy tolerance allowed a one-example substitution to differ by a whole
  accuracy point. That tolerance is now capped at `0.01`, and separate
  coherent manifest and weight substitution controls have been added for the
  next unit run. This failed attempt is diagnostic, not validation closure.
- The focused `jitml-unit --linux-cuda --test-options='-p coherently'` rerun
  passed **3/3**, including both Phase `278` Store-admitted substitution
  controls: one changed the physical weight blob and readdressed its manifest,
  the other changed the manifest's reported metric while retaining identical
  weight bytes. In both cases Store admitted the internally coherent new
  snapshot, and the served-metric check rejected the stale measurement. A
  fresh `mnist-shallow-mlp` CUDA ProductRow then trained for the fixed
  **70,000** examples, reported **0.907** held-out test accuracy, and became
  eligible only after the admitted serving graph rederived its metric. Its
  Store-admitted manifest SHA was
  `83d719a782cd3f20d85cde8ec80b9eb169f4f613f52dd493e3137a1fd3f36f17`.
  The focused ProductTruth unit group also passed **8/8** on `linux-cuda`.
- A fresh `california-housing-mlp` CUDA ProductRow exercised the regression
  served-metric path. It completed the fixed **70,000** training examples,
  reported **0.21983530961436884** validation MSE, and became eligible only
  after its admitted graph recomputed the held-out RMSE. Store admitted manifest
  `51c55602c7cb5077f660032acc835e3aa587eed213ad2251d9e027f559228d60`.
- A fresh `cifar10-resnet20` CUDA ProductRow exercised the archive classifier
  input transform and served-metric path. It completed the fixed **40,000**
  training examples, reported **0.274** held-out test accuracy, and became
  eligible after Store admitted manifest
  `bfdce953e6582d1261f5041dc1bb0f91977cc357993b06011c67dadcbdf97eb8`.
- The first full `jitml check-code` run against the served-metric changes found
  one HLint composition hint in the new Store inference helper. The helper was
  reformatted and its focused HLint rerun returned **No hints**. The corrected
  full container `jitml check-code` rerun passed under the prior image's lint
  executable. The new image's embedded lint then found `barFromObservation`
  deriving ProductRow targets from `ConvergenceObservation` values. Its three
  ProductRow call sites now read explicit reviewed RL, HER, and AlphaZero
  target/slack constants; `barFromObservation` is removed. Focused HLint on
  the changed tables and builders returned **No hints**. The scanner also
  guards `convergenceLiteratureTarget` assignments inside record constructors;
  its focused `ProductTruth` unit group passed **9/9**, including the new
  measured-derived record-target control. The final current-source container
  image, including the record-field scanner fix, passed its embedded
  `jitml check-code` gate. The phase's standalone
  `docker compose run --rm jitml jitml check-code` and `jitml docs check`
  commands also passed against that image; the lane evidence is still pending.
- Fresh `A2C/key-door-grid` CUDA training also cleared the new `0.5` bar:
  all **20** evaluation episodes returned **1.43**, and Store admitted manifest
  `37a30367969f29c7df1901b74118548dda29e5d063fa222aa01472f44d2a66cf`.
  Fresh `TRPO/cartpole` CUDA training cleared the new `400` bar too: all
  **20** episodes returned **500**, and Store admitted manifest
  `acfe3a0c23c236fc3bd3fef228d1f7fbfa2e8a0cc7ae083981329736b1acbc7e`.
  These focused publications are diagnostic ProductRow evidence, not the
  full-scenario CUDA journal.
- The fresh real `linux-cuda` ProductScenario then passed **60/60** focused
  integration assertions in **22,344.54 s**, including all **55** eligible
  ProductRows, the **11/39/4/1** family split, canonical order, and exact
  journal round-trip. The issued version-`1` journal has run ID
  `jitml-product-scenario-9cad81b2d420996e`, source-journal SHA-256
  `15e7ed5801e992872f274410f5124aa8a8ae061a5dfa7a3b52099a74b63e1e45`,
  and retained byte SHA-256
  `5637c4dc37fdbbecc639572e75ef46887541a0769856289611f2d130faf7dd48`.
  The source pin and retained CUDA journal now carry those exact issued bytes.
  This closes the CUDA lane refresh; CPU and Apple lane refreshes and the
  three-lane aggregate remain open.
- On the real `linux-cpu` host, the existing Kind cluster was recovered and
  `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up` passed all
  **118** live rollout steps. Its publication identifies `linux-cpu`, edge
  port **9091**, and all **8** components Ready. The fresh Phase `261`
  ProductScenario is running against that cluster; no CPU journal has been
  accepted or pinned yet.

### Remaining Work

- Re-run the CPU and Apple Silicon scenarios after the focused
  exact-admitted-byte supervised checks and Store-admitted substitution
  controls. The CUDA scenario and its issued journal passed; the other two
  lanes and aggregate still need fresh evidence.
- **Retire the vacuous bars.** Three rows are unfalsifiable or near it against
  their own environments in the retained aggregate: `PPO/key-door-grid` and
  `A2C/key-door-grid` used bars of `-2.8` and `-3.3`, while `TRPO/cartpole`
  used `185` against a literature target of `475`. The worktree now declares
  `0.5` for both key-door rows and `400` for TRPO/cartpole, and CUDA's focused
  PPO experiment cleared `0.5` with a `1.43` median. These new constants and
  the trainer change still need the phase validation commands and new real
  lane evidence. The retained `A2C/key-door-grid` measurements were `1.43`
  in all lanes; `TRPO/cartpole` reported `500`, `500`, and `188` on
  `linux-cpu`, `linux-cuda`, and `apple-silicon` respectively, so Apple needs
  fresh passing TRPO training before this phase can close.
- Re-run the affected ProductRows on real CPU and Apple Silicon hardware,
  reissue those immutable lane journals, and regenerate the pinned Phase `276`
  aggregate after the bar and trainer changes. Existing admitted manifest
  hashes and completion bytes cannot be relabelled under new thresholds. This
  host is `x86_64` and exposes an NVIDIA device; access to an Apple Silicon
  execution context is pending.
- Pass the phase's three Validation commands after the remaining implementation
  and evidence work is complete.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
