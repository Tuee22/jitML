# Phase 278: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance. Single-session phase migrated from legacy Sprint 32.2 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-10-15 UTC). The final Linux unit run passes 1,503 of 1,512
cases; its nine failures require the stale Apple journal to be replaced. The
CPU backend, docs, and code-quality gates pass. Real generic CLI and focused
daemon execution plus Store re-admission validate compiled-plan binding. Open:
independently reviewed supervised anchors, the `apple-silicon` journal re-issue,
aggregate regeneration, a passing full unit gate, and final standing integration
evidence on the reviewed contracts (see Remaining Work). The current Linux
hardware audit reaches the requested stopping condition: the required fresh
Apple journal needs real Metal execution on a Mac. RTX 3090 container visibility
does not supply that evidence. Neither hardware audit claims phase validation
or closure.
Phase `276` / Sprint `276.1` remains Done on its retained join mechanism.

### Linux Hardware Boundary

The 2026-10-15 Linux host cannot fully validate Phase `278` because it cannot
execute the required `apple-silicon` journal refresh. Execution stops at this
first open phase under the user's hardware stopping condition. Sprint `278.1`
stays Active; the six dependent open sprints stay Blocked. No work on those
later sprints begins in this session.

- [Host probes](attestations/phase278-20261015-linux-hardware-audit/host-probes.json)
  retain command arguments, UTC timestamps, both streams, and exit codes. The
  host is x86_64 Linux; Docker exposes 16 CPUs and 62.7 GiB RAM. The RTX 3090
  reports 24 GiB VRAM, compute capability 8.6, and driver `595.99.02`; a cached
  CUDA container's GPU query succeeds. `./bootstrap/apple-silicon.sh doctor`
  exits `2` at its macOS requirement. These are capability diagnostics, not
  jitML backend tests or kernel execution evidence.
- The [retained-journal comparison](attestations/phase278-20261015-linux-hardware-audit/journal-inspection.json)
  reproduces all three SHA-256 pins and inventories 55 rows per file. The
  retained CPU and CUDA contract maps agree; the Apple map differs on exactly
  `PPO/key-door-grid`, `A2C/key-door-grid`, and `TRPO/cartpole`. This comparison
  does not execute the current Haskell contract projection or journal admission.
  The catalogue still explicitly requires an Apple journal and Apple execution
  context, so the missing hardware is an existing obligation independent of
  any further supervised-policy repair.
- No source, threshold, contract, journal, aggregate, validation record, or
  evidence guard changes. No project image or `.build` cache is present; no
  cold build, cluster, daemon, or phase validation gate is started after the
  hardware stopping condition is established. The earlier Linux results retain
  their original scope and are not current-host validation.
- Resume with independent policy and split-baseline review, reconcile per-lane
  repair ownership under standards `M(b)`/`M(d)`, and freeze contracts before
  spending full lane runs. A real Mac must supply the Apple diagnostics and
  complete journal described in Remaining Work. The prior Mac review's missing
  NVIDIA hardware does not describe this Linux host.

### Mac Hardware Boundary

The earlier 2026-10-15 Mac session reaches the user's stopping condition of the first
phase that cannot be fully validated with the available hardware. Phase `278`
stays Active, and the later open phases stay Blocked; their execution has not
begun. The [independent review and handoff](attestations/phase278-20261015-mac-review/README.md)
retain the policy findings, source references, and exact resumption commands.

- The host is an M1 Max with a 32-core Metal GPU and 64 GiB RAM. Apple stage-0
  doctor passes. Docker reports ARM Linux with only `runc` runtimes;
  `docker run --rm --pull=never --gpus all ubuntu:24.04 true` exits `125`
  (`could not select device driver "" with capabilities: [[gpu]]`). Raw
  commands, timestamps, both streams, and statuses are retained in
  [host-probes.json](attestations/phase278-20261015-mac-review/host-probes.json).
- The currently retained CPU/CUDA journals still admit under the unchanged row
  contracts. NVIDIA execution becomes necessary when repairing the supervised
  bars: the Tiny ImageNet source explicitly sets its threshold to clear a prior
  measured result, so retaining that floor cannot resolve the independent-anchor
  obligation. A changed bar invalidates its affected row in each substrate's
  journal, and each replacement journal requires the full fresh 55-row run.
  This host can supply Apple and Docker CPU execution, but cannot supply the
  resulting CUDA revalidation. The independent policy decision remains open
  separately from this hardware limitation.
- Cold `./bootstrap/apple-silicon.sh build` and `docker compose build jitml`
  were started, then intentionally interrupted with terminal status `130` after
  establishing that boundary. No cluster or daemon was started. No unit,
  backend, live integration, `docs check`, or `check-code` gate ran in this Mac
  session. A `docker compose run --rm --pull never jitml jitml docs check`
  attempt began an automatic image build, also stopped with exit `130` before
  the validator started; its streams are retained with the hardware probes.
  The retained Linux results below keep their original scope.
- No threshold, training recipe, product source, journal, aggregate, validation
  record, or evidence guard changes in this audit. The label-only anti-trivial
  criteria in the review are recommendations to bind before fresh runs; they
  do not certify published-model convergence or resolve the external-context
  obligation. Finalize the contracts before spending a full Apple lane, then
  arrange real CUDA execution and finish this phase before proceeding.

### Current Execution Checkpoint

- The 2026-10-14–15 session uses a dedicated Ubuntu 24.04 KVM guest inside WSL2 on
  Windows. Its configured resources are 48 GiB RAM, 16 virtual CPUs pinned to
  WSL CPUs `0-15`, and a 300 GiB virtual disk. The systemd VM service limits
  process memory to 50 GiB, CPU time to sixteen CPUs, and swap to zero. Docker
  and Compose run inside this guest; host language tools are not prerequisites.
- Windows checkout conversion had changed the retained journal bytes to CRLF.
  Restoring their original LF bytes reproduces all three registered SHA-256
  pins exactly. The repository's `.gitattributes` preserves LF on future
  checkouts, and the VM transfer restores Git-recorded executable modes and LF
  text before building.
- Parsed CPU and CUDA journals agree on all 55 row contract digests. The retained
  Apple journal differs on exactly `PPO/key-door-grid`, `A2C/key-door-grid`, and
  `TRPO/cartpole`. Its PPO reward is `-2.79` against the current `0.5` bar; its
  TRPO reward is `188` against `400`. This is a hardware-evidence gap after
  correcting line endings, not a Windows prerequisite. The Apple journal must
  be replaced by real passing execution rather than edited to match new digests.
- The final source's four Linux Validation commands run inside the guest's
  project container: `jitml test jitml-unit --linux-cpu` passes **1,503 / 1,512**
  cases in **42.96 s** and exits `1`; all nine failures are the
  `Journal-derived product aggregation (Phase 276)` cases that reject the stale
  Apple journal. `jitml test jitml-backends --linux-cpu` passes **38 / 38** in
  **2.37 s**. `jitml docs check` and `jitml check-code` both exit `0`. This is
  partial validation, not a passing full unit gate or phase closure.
- Generic RL cohort binding passes its **27** boundary controls. Its nested
  V3 completion DTO carries the actual compiled plan; refinement binds PlanId,
  transition count, and any declared seed. Admission checks the own cohort,
  RL-policy claims' transition budgets, and canonical namespace identity independently.
  The controls reject substituted metadata and preserve retained CPU/CUDA V2
  completion bytes and canonical admission before a ProductScenario invocation.
- The first real generic CLI attempt exposed a cache-root bug: source materialized
  under `--cache-dir .build/phase278-generic-rl`, while the compiler and artifact
  handle still selected `.build`. The shared loader now derives runtime paths
  from `Env.envCacheDir` and passes the actual materialized source directory to
  the compiler. Default cache paths remain unchanged. The CPU backend gate includes
  a real cold-cache MLP compile/load/run under a custom path containing spaces,
  reference-output parity, and warm artifact reuse; it passes with all 38 cases.
- The corrected public CLI executes `experiments/cartpole.dhall` on real oneDNN
  with seed **42**, **1,228,800** environment transitions, **192,000** optimizer
  updates, and median final reward **500** against its own PPO/cartpole bar of
  **450**. The inspector passes exact latest-pointer and immutable-address Store
  admission, structural generic completion validation, fetched nested V3 proof,
  plan/budget/seed binding, and the physical weight hash. The admitted manifest is
  `0bebdba14ee9b836f15083fedf73323c88fc732bd55e9dc964ccb774c2965b44`.
  This receipt validates the generic CLI path and does not establish canonical
  ProductRow eligibility.
- Real Linux bootstrap completes at **2026-10-14 23:54:18 UTC**, exits `0`,
  executes **115** steps, and reports all **8** workloads Ready with edge HTTP
  `200`. The task runtime image layers the official guest Docker Compose and
  Buildx plugins onto the base image, which lacks them; this receipt does not
  establish independent bootstrap success for the unmodified base image.
- The sole focused daemon PPO invocation completes **1 / 1** cases in
  **508.66 s**; runtime, systemd service, and inspection all exit `0`. The captured
  stopped worker's checkpoint passes physical Store admission, exact address
  re-admission, and bound nested V3 structural completion. Its planned and
  observed counts both equal **4,915,200** transitions, with **768,000** optimizer
  updates. Seed **42**, maximum episode steps **2,048**, and **200** evaluation
  episodes are bound to the compiled plan; episode keys `0-199` each retain reward
  **2,048**, and the inspector independently derives median **2,048**. The manifest
  is `541c429b0620636e327c24f565117d98c4b4cb6f2d57d61864af3abb0f4f1d00`,
  with PlanId `c8cde5d7eb7c023ed9d599fce929389e3e53f954b2dc522b8015e0e59ef22380`.
  Source digest `924e1535cc42` is identical before and after; the actual worker
  executable matches CLI SHA-256 `3b126ee3b94b` in runtime image `f709538736db`.
  Generic completion has no measured device witness by design; actual CPU
  execution provenance is retained. This is completed scoped validation, not a
  full standing integration GateTranscript or canonical ProductRow proof.
  Raw receipts are being retained at
  `attestations/phase278-20261014-linux-cpu/daemon/focused-daemon-KnZ3sZvU/`.
- Regression and tuning ProductRow bars now share their policy constructors with
  the generic metric lookup. Generic HER-success and arena bars select the existing
  canonical RL anchors. This removes duplicated values without changing numerical
  policy, threshold arithmetic, or row contracts; the final unit parity controls pass.
- Commands, both output streams, exit statuses, VM resources, inspector source,
  and the generic checkpoint snapshot are retained under
  [attestations/phase278-20261014-linux-cpu/](attestations/phase278-20261014-linux-cpu/).
  Structured unit and backend records are retained in `attestations/validation/`;
  the unit record accurately retains the `Failed` outcome. Earlier failed attempts
  remain diagnostic evidence alongside the final source's results.
- Phase `278`'s catalogue also carries `Independent supervised convergence-anchor
  review` and `Live generic RL CLI and daemon validation` as explicit open
  external-context obligations. The scoped CLI and actual daemon checks are
  complete, but the live ExternalContext remains Unproven pending replacement
  with final standing integration evidence on externally reviewed contracts and
  refreshed lanes. The primary-source review below does not establish replacement
  anchors; fresh Apple journals and a passing unit gate alone cannot resolve that
  policy or supply the final full integration GateTranscript.
  Later open phases remain Blocked under rule `M(c)`.

### External Anchor Review

The 2026-10-14 independent primary-source review finds no published replacement
bar for the current compact architectures and fixed budgets. Published accuracy
targets do not establish an acceptance floor for a different graph, dataset
sample, and training schedule:

- [He et al., Deep Residual Learning](https://arxiv.org/pdf/1512.03385) reports
  full-dataset CIFAR ResNet results after 64,000 batch-128 iterations. Those
  results do not justify the current compact graph's 320-update convergence
  floors.
- [Dosovitskiy et al., An Image Is Worth 16x16 Words](https://arxiv.org/pdf/2010.11929)
  evaluates large pretrained vision transformers, rather than the current
  compact from-scratch CIFAR row.
- [Le and Yang, Tiny ImageNet Visual Recognition](https://cs231n.stanford.edu/reports/2015/pdfs/yle_project.pdf)
  evaluates CNN/VGG models, not the current ResNet-50-labelled compact row.
- [Hernández-Lobato and Adams, Probabilistic Backpropagation](https://proceedings.mlr.press/v37/hernandez-lobatoc15.pdf)
  includes Boston Housing, not California Housing, and does not establish the
  current standardized California Housing RMSE target.

For housing, the [held-out R² definition](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.r2_score.html)
provides an independent zero-skill floor: positive R² requires RMSE strictly
below the held-out target standard deviation and rejects any constant predictor.
Dataset and split statistics can establish that floor without consulting a
model's measurement. Any stronger margin remains an explicitly reviewed project
policy, and a positive-skill gate alone does not prove convergence to a published
architecture benchmark. These findings keep the external-anchor obligation
open; no replacement threshold is selected from the retained measurements.

## Sprint 278.1: External Bars, No-Self-Referential-Gate Lint, and Exact Served-Byte Provenance [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Product/ExternalBars.hs`,
`src/JitML/Product/Convergence.hs`, `src/JitML/Product/Matrix.hs`,
`src/JitML/Product/PhaseStatus.hs`, `test/unit/JournalDerivedStatus.hs`,
`src/JitML/Product/ServedMetric.hs`, `src/JitML/Training/Budget.hs`,
`src/JitML/RL/Command.hs`, `src/JitML/Engines/Engine.hs`,
`src/JitML/Engines/Loader.hs`, `src/JitML/Lint/ProductTruth.hs`,
`src/JitML/Lint/ProductTruthBars.hs`, `src/JitML/Lint/HaskellTokens.hs`,
`src/JitML/Checkpoint/Store.hs`, `src/JitML/Checkpoint/Format.hs`,
`src/JitML/Product/Publisher/Supervised.hs`, `test/unit/Main.hs`,
`test/unit/SupervisedCheckpointV2.hs`, `test/unit/ServedMetricVerification.hs`,
`test/unit/ProductBarProvenance.hs`, `test/unit/ProductTruthScanner.hs`,
`test/unit/ProtocolCodec.hs`, `test/backends/Main.hs`, `jitml.cabal`
**Docs to update**: `../documents/engineering/product_completion_contract.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/jit_codegen_architecture.md`,
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
docker compose run --rm jitml jitml test jitml-backends --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Closure Evidence

- Implemented the module and lint and exercised the former decode-time check.
  That old re-encoded-manifest/served-weight assertion is historical and does
  not close exact V2 persistence or admission; the retained closure here is the
  external-bar and no-self-reference grader.

### Current Partial Validation

**Historical partial results (2026-09-24 through 2026-10-06).** The dated runs
below retain their original scope. Current source-bound results are recorded in
[Current Execution Checkpoint](#current-execution-checkpoint).

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
  bar. At that checkpoint the generic fallback verified what it could — the observation maximised
  the return and its threshold is a frozen external cohort anchor
  (`literatureTarget - slack`) — but it could not identify the cohort, so it accepted
  a threshold equal to any frozen anchor, including another cohort's (even the
  loosest); ProductRow completions stayed checked against their own row bar. Unit
  coverage pins the accepted anchor, the rejected non-anchor, and the rejected
  minimising goal. A strict generic path would carry `(algorithm, environment)`
  in the completion so the cohort's own bar applied; that gap remained open then.
  The 2026-10-14 implementation and CLI validation above replace this fallback;
  the 2026-10-15 focused daemon proof completes its scoped runtime validation.
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

- **Hardware handoff after contract review.** The current
  [Linux hardware audit](#linux-hardware-boundary) establishes NVIDIA container
  visibility and unavailable Apple execution. The earlier
  [Mac review](attestations/phase278-20261015-mac-review/README.md) establishes
  that separate host's available Apple/CPU execution and unavailable NVIDIA execution.
  Repair the independently unproven supervised bars and split-baseline criteria
  before refreshing journals. Changed row contracts require new CPU, CUDA, and
  Apple journals; arrange a real CUDA host for that validation. The current
  CPU/CUDA evidence is retained intact and is not claimed stale before a contract
  change. The Mac audit does not complete the independent-policy obligation.
  The current all-lane repair requirement also needs explicit per-lane ownership
  reconciled with standards `M(b)`/`M(d)` (one accelerator and one host per phase)
  before resuming closure. No second accelerator gate or forward blocker is
  added to this phase's Validation block to conceal that scope problem.

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
  Then retain and pin the Apple journal the same way as the other lanes. After
  Phase `278` closes and Phases `280` and `281` validate in order, Phase `282`
  owns the following live Apple validation:
  `jitml test jitml-integration --apple-silicon --test-options='-p Live'` once: it
  executes the Apple host-forwarding observers of Sprint `282.1`, whose Apple half
  is compile-only on Linux, and its outcome is recorded in Phase `282`.
- **Exit Definition item 26 residue.** Supervised bars that were
  set to be cleared by a measured result (for example `tiny-imagenet-resnet50`
  `0.008`, `cifar10-resnet20`, `cifar10-vit`, and California Housing's
  standardized RMSE `<= 1.0`, which a predict-the-mean model meets) remain open
  pending independent policy review. Duplicated shared metric literals are removed
  without changing their values and their final container parity controls pass.
  The generic RL fallback is removed by compiled-plan binding; container controls
  and the real CLI, focused daemon execution, and exact Store inspectors pass.
  Final full unit and standing integration validation remain open. Replacing
  the anchors with independently reviewed external anchors changes contract
  digests, so all three
  lane journals (about 6.2 h, 12.6 h, and 30 h) would be re-issued once afterwards.
  These owned obligations must be resolved before closure under standards rule
  `C`; retaining a threshold calibrated to the measurement it grades is not a
  substitute for independent external-anchor review. The scoped generic proofs
  are retained as completed work while the final contract validation remains open.
- **Evidence-derived guard obligations.** `PhaseStatus.hs` retains
  `ExternalContext "Independent supervised convergence-anchor review"` until
  independently reviewed anchors, meaningful trivial-model rejection criteria,
  and the corresponding real evidence resolve the supervised-bar obligation.
  `ExternalContext "Live generic RL CLI and daemon validation"` remains Unproven
  as a temporary formal guard after the public CLI and actual focused daemon
  checks pass. Their retained exact Store proofs validate that scoped path;
  they cannot satisfy a full standing integration GateTranscript. After the
  external-anchor decisions and affected lane refresh, replace the temporary
  guard with `GateTranscript JitmlIntegration LinuxCPU`, run the full standing
  `jitml test jitml-integration --linux-cpu` invocation on the final contracts,
  and retain its authentic result. The focused command does not mint that record.
  Each guard is removed only alongside the actual resolution and
  machine-observable evidence requirements that replace it; documenting a
  review or manually changing status is insufficient. The independent pinned
  catalogue and regression controls retain these requirements after Apple
  context removal.
- **Regenerate the aggregate and close, in this order.** Land every `src/` and
  `test/` edit first, because each validation record binds the source digest of
  `app/`, `gen/`, `src/`, `test/`, `cabal.project`, and `jitml.cabal`. A record
  taken against an older tree is
  judged `Stale`: pin the passing Apple journal in `ProductAggregation.hs` and
  remove its execution-context obligation only after the journal is admitted.
  Resolve both remaining guard obligations above before the final source gates.
  Then regenerate `attestations/product-aggregate.json` from
  `productAggregationBytes` (`loadProductAggregation`; no committed generator
  exists) and pass the four Validation commands on that tree: the nine
  `Journal-derived product aggregation (Phase 276)` cases are the only expected
  `jitml-unit` failures today and turn green once all three journals admit. Copy
  the `jitml-unit` record from `.build/runtime/validation/` into
  `attestations/validation/`. Only documentation and attestation files change
  afterwards: set this phase's headers to the status `jitml docs status` derives,
  update the tallies in `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md` (grep `Done / `), and promote Phase `280`.

## Documentation Requirements

**Engineering docs to create/update:**

- `documents/engineering/checkpoint_format.md` — nested completion-plan binding
  and compatibility with the single checkpoint envelope.
- `documents/engineering/product_completion_contract.md` — exact generic RL
  cohort grading and independent canonical namespace checks.
- `documents/engineering/training_metrics_and_splits.md` — shared metric policy
  ownership and the boundary between published targets and project policy.
- `documents/engineering/jit_codegen_architecture.md` — configured cache roots
  for runtime source, compiler inputs, artifacts, staging, and toolchain sidecars.
- The other governed documents listed under `Docs to update` retain their
  external-bar, determinism, and code-quality contracts; reconcile any changed
  claims before closure.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
