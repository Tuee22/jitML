# Phase 278: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance. Single-session phase migrated from legacy Sprint 32.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-09-30 UTC). The implementation is complete on the Linux host:
the external-bar, anti-self-reference, and exact served-byte checks pass their
unit and container gates, and the `linux-cuda` and `linux-cpu` journals are
re-issued under the tightened bars. Open: the `apple-silicon` journal re-issue,
the aggregate regeneration, and the final gates (see Remaining Work). Phase `276`
/ Sprint `276.1` remains Done on its retained join mechanism.

## Sprint 278.1: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Product/ExternalBars.hs`,
`src/JitML/Product/ServedMetric.hs`, `src/JitML/Lint/ProductTruth.hs`,
`src/JitML/Lint/ProductTruthBars.hs`, `src/JitML/Lint/HaskellTokens.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Product/Publisher/Supervised.hs`, `test/unit/Main.hs`,
`test/unit/SupervisedCheckpointV2.hs`, `test/unit/ServedMetricVerification.hs`,
`test/unit/ProductBarProvenance.hs`, `test/unit/ProductTruthScanner.hs`
**Docs to update**: `../documents/engineering/product_completion_contract.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/code_quality.md`, `system-components.md`

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
  measured-derived record-target control. On 2026-09-24 the then-current-source
  container image, including the record-field scanner fix, passed its embedded
  `jitml check-code` gate, and the standalone
  `docker compose run --rm jitml jitml check-code` and `jitml docs check`
  commands also passed against that image; the lane evidence was still pending
  then. The 2026-09-30 tree's gates are recorded below.
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
  This closed the CUDA lane refresh on 2026-09-24; the CPU refresh (below) has
  since completed, and the Apple refresh and the three-lane aggregate remain open.
- On the real `linux-cpu` host, the existing Kind cluster was recovered and
  `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up` passed all
  **118** live rollout steps. Its publication identifies `linux-cpu`, edge
  port **9091**, and all **8** components Ready. A first Phase `261`
  ProductScenario was started against that cluster; it was superseded by the
  fresh run below, which is the one that was accepted and pinned.

- The 2026-09-30 hardening closed the gaps that needed no hardware. The
  served-metric verification has unit coverage for the regression path (matching
  and substituted weights), both tolerances at their boundaries, the small-set
  fail-closed cap, and every typed rejection, and the post-admission gate is an
  extracted, tested function; `assertConvergenceObservationsAgainstBar` requires
  exactly one observation of the bar's metric and compares its value, with a
  permanent regression net that admits the pinned `linux-cuda` journal and grades
  all **55** rows; a token-stream `ProductTruth` scanner catches multi-line record
  fields, helper-wrapped targets, renamed measured values, and split cohort
  constructors with zero findings on the tree; and an independent 55-row bar
  cross-check rebuilds every bar from the canonical tables. The three new
  `jitml-unit` groups hold **182** cases (`Served-metric verification` 62,
  `ProductTruth bar scanner` 99, `External bar provenance` 21); 96 mutants were
  run and 94 killed (round one 54/52, round two 42/42), with both survivors
  explained. The served-metric tolerance is proven on `linux-cuda` and
  `linux-cpu` (all eleven supervised rows passed the post-admission check in both
  60/60 runs) and is unproven on `apple-silicon`; the remaining residue is in
  Remaining Work.
- The fresh real `linux-cpu` ProductScenario then passed **60/60** focused
  integration assertions in **45,478.60 s** (Kind cluster `jitml-linux-cpu`, edge
  port `9091`, **115** rollout steps, all **12** datasets staged, image built at
  commit `0606cc7`), including all **55** eligible ProductRows, the **11/39/4/1**
  family split, canonical order, and exact journal round-trip.
  `PPO/key-door-grid`, `A2C/key-door-grid`, and `TRPO/cartpole` cleared the
  tightened bars on oneDNN, and every supervised row passed the post-admission
  served-metric check. The issued version-`1` journal has run ID `jitml-product-scenario-94ef228449661943`,
  source-journal SHA-256 `5bd776cfb5f690b2dde070cd3cfd9f69449744df1b1b9ca44239251134e8201a`, and retained byte SHA-256
  `438931ad8c49e1e7365e441ae519fc02df4443895416c80b599c50f89dac05ff`
  (175,168 bytes), tracked at
  [attestations/linux-cpu-product-lane-journal.json](attestations/linux-cpu-product-lane-journal.json)
  and pinned in `src/JitML/Test/ProductAggregation.hs`. All 55 contract digests
  equal the `linux-cuda` journal's, and every device witness is byte-identical to
  the superseded journal. With it,
  `JITML_SUBSTRATE=linux-cpu jitml-model-convergence` admits the lane and passes
  all **390** cases, and the aggregation group rejects only the `apple-silicon`
  lane. The `linux-cpu` re-issue is complete.

- The first full live integration pass against the `linux-cpu` cluster (raw
  `cabal test jitml-integration` excluding this matrix, run with the image built
  at `0606cc7`) found a regression in this sprint's own gate:
  `assertConvergenceObservationsExternal` rejected **every** stored RL
  `median_final_reward` with "no canonical cohort identity", so the generic
  (non-ProductRow) RL path failed closed at completed-checkpoint write. The
  Sprint `12.11` live `WorkflowMatrix` cell `jitml rl train
  experiments/cartpole.dhall --substrate linux-cpu` exited `2` after 190 s, and
  the live daemon `StartRLRun` scenario failed the same way; no unit case had
  exercised the generic path because ProductRow completions carry their row's
  bar. The generic fallback now verifies what it can — the observation maximises
  the return and its threshold is a frozen external cohort anchor
  (`literatureTarget - slack`) — but it cannot identify the cohort, so it accepts
  a threshold equal to any frozen anchor, including another cohort's (even the
  loosest); ProductRow completions remain checked against their own row bar. Unit
  coverage pins the accepted anchor, the rejected non-anchor, and the rejected
  minimising goal. A strict generic path would carry `(algorithm, environment)`
  in the completion so the cohort's own bar applies; that remains open and is
  recorded in the legacy ledger.
- The same raw live integration pass was repeated on the corrected tree (image
  rebuilt and reloaded into the Kind cluster): **138** cases in **6,739 s**, **125**
  passed. They include the 8-cell `WorkflowMatrix` (**5,259 s**, `jitml rl train`
  accepted again), the live daemon `StartTraining` (375 s), `StartRLRun` (220 s),
  PPO `cartpole` convergence through the daemon (608 s), and AlphaZero dispatch
  (34 s), which drive the establish-before-publish transport of Sprint `282.1`, and
  the reply-cursor, registry, GC, and MinIO cases. **13** failed for reasons outside
  the code under test: the `Phase 276` aggregation case (stale `apple-silicon`
  journal); **11** `Phase 262`/`Phase 263` catalogue and lane-fragment cases that
  need the same invocation's completed ProductScenario aggregate and its
  orchestrator-supplied startup capability, which a raw `cabal test` excluding the
  matrix cannot provide (they run only inside a full
  `jitml test jitml-integration --linux-cpu` lane, whose ProductScenario subtree
  alone took 12.6 h, and were not re-run); and the live Tune daemon dispatch,
  whose 180 s window was too tight on this loaded host for the registered 128-trial
  MNIST sweep (none of its trials had finished in that run; a focused rerun
  finished 81 of 128 in the window while the host was loaded by other work). With
  a 900 s window in the lane copy it passed in **232.93 s**, so the committed
  window in `test/integration/Main.hs` is now 600 s, like the `StartTraining` and
  `StartRLRun` cases (the AlphaZero case keeps 180 s and PPO convergence 7,200 s).
  Re-run with the committed 600 s window on a quieter host, the Tune case passed
  in **152.62 s** and the AlphaZero case in 4.51 s, so the 180 s failure was host
  load, not a functional defect.
- The complete orchestrated integration lane on the final tree (fresh cluster, capped
  container) passed **197 / 198** cases, including the admitted inventory, all 55 rows,
  the four aggregate cases, the eleven catalogue and lane-fragment cases, the
  8-cell `WorkflowMatrix` (5,017 s), the daemon cases, and PPO convergence; the one
  failure is the Phase `276` aggregate case, which fails while the Apple journal is
  stale. The live e2e lane built on it is recorded in Phase `289`.
- The remaining stanzas also passed on the final tree in the `linux-cpu` container,
  with their hours-long `Live` cases excluded because the integration live pass above
  covers those paths: `jitml-rl-canonicals` **47 / 47**, `jitml-hyperparameter`
  **26 / 26**, `jitml-backends` (`linux-cpu` lane) **37 / 37**, and
  `jitml-daemon-lifecycle` **49 / 49**; `jitml-sl-canonicals` passed its **32**
  non-live cases and its four `Live` cases were not run (without a cluster they fail
  by design, and with one they retrain all eleven SL rows, hours on this host).
  The first live e2e attempt is recorded in Phase `289`.

### Remaining Work

- **`apple-silicon` lane journal re-issue (Mac host only).** The retained Apple
  journal (SHA-256 `1496c863…`) carries the pre-tightening contract digests for
  `PPO/key-door-grid`, `A2C/key-door-grid`, and `TRPO/cartpole`, and its
  `TRPO/cartpole` median is **188** against the new **400** bar. Apple training is
  deterministic within a substrate, so the same source is expected to reproduce
  that result: after `./bootstrap/apple-silicon.sh up` and staging the twelve
  datasets with `jitml internal upload-dataset`, run the three changed rows singly
  first (`jitml internal train-and-publish-product-rows --apple-silicon --row <id>`)
  before spending a full lane. The Apple device MLP kernels are aligned with the
  Linux lanes (glibc `tanhf`/`expm1f` port, Phase `271`), but host-side `Double`
  math (simulator physics, softmax/log-prob, final-evaluation forward tanh) uses
  the platform libm, and `TRPO/cartpole` evaluates one deterministic trajectory
  from the exact-zero start, so a first-divergence trace between a Linux and an
  Apple run of that row is the diagnostic that separates a libm effect from a
  Metal defect. Issue the journal with the focused route
  `jitml test jitml-integration --apple-silicon --test-options='-p "Phase 261 ProductRow contract-driven integration matrix"'`;
  `bootstrap/apple-silicon.sh test` fail-fasts at the red `jitml-unit` stanza.
  Then retain and pin the Apple journal the same way as the other lanes. While the
  Apple cluster is up, also run
  `jitml test jitml-integration --apple-silicon --test-options='-p Live'` once: it
  executes the Apple host-forwarding observers of Sprint `282.1`, whose Apple half
  is compile-only on Linux, and its outcome is recorded in Phase `282`.
- **Exit Definition item 26 residue (owner decision).** Supervised bars that were
  set to be cleared by a measured result (for example `tiny-imagenet-resnet50`
  `0.008`, `cifar10-resnet20`, `cifar10-vit`, and California Housing's
  standardized RMSE `<= 1.0`, which a predict-the-mean model meets), the generic
  metric literals duplicated in `convergenceBarForMetric`, and the generic RL
  fallback that cannot identify its cohort remain open. Replacing them with
  independently reviewed external anchors changes contract digests, so all three
  lane journals (about 6.2 h, 12.6 h, and 30 h) would be re-issued once afterwards;
  the owner decides whether this sprint closes on the current bars or waits for
  that review.
- **Regenerate the aggregate and close, in this order.** Land every `src/` and
  `test/` edit first, because each validation record binds the source digest of
  `app/`, `gen/`, `src/`, and `test/`, and a record taken against an older tree is
  judged `Stale`: pin the Apple journal in `ProductAggregation.hs` and delete the
  `ExternalContext "Apple Silicon execution context"` obligation in
  `PhaseStatus.hs`. Then regenerate `attestations/product-aggregate.json` from
  `productAggregationBytes` (`loadProductAggregation`; no committed generator
  exists) and pass the three Validation commands on that tree: the nine
  `Journal-derived product aggregation (Phase 276)` cases are the only expected
  `jitml-unit` failures today and turn green once all three journals admit. Copy
  the `jitml-unit` record from `.build/runtime/validation/` into
  `attestations/validation/`. Only documentation and attestation files change
  afterwards: set this phase's headers to the status `jitml docs status` derives,
  update the tallies in `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md` (grep `Done / `), and promote Phase `280`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
