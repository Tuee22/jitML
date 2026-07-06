# Phase 28: Per-Model Integration & Row-Complete E2E

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-27-demo-all-model-rendering.md](phase-27-demo-all-model-rendering.md), [phase-29-linux-cuda-product-lane.md](phase-29-linux-cuda-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md), [../documents/engineering/purescript_frontend.md](../documents/engineering/purescript_frontend.md)
**Generated sections**: none

> **Purpose**: Every product row owns a named integration test and e2e test that
> exercises real training, checkpointing, and demo rendering on `linux-cpu`, and
> the coverage report fails naming any missing row/test pair.

## Phase State

✅ **Done** (reclosed 2026-07-06 after the 2026-07-05 realness audit). Phase `27` remains
Done for its owned demo-rendering surface, and Phase `25` remains re-closed
(2026-07-03) after every live RL product row produced passing
`CompletedTraining` evidence. The historical closure recorded Sprint `28.1` Done
after the row-keyed integration matrix switched from synthetic fixtures to
published ProductRow checkpoint manifests, Sprint `28.2` Done after the live
row-complete Playwright suite passed against `linux-cpu`, and Sprint `28.3`
closed on 2026-07-05 after the node-local stateful PV overlay, MinIO retry/probe
hardening, and Envoy probe hardening kept the `linux-cpu` live lane healthy
through `jitml test all --live --linux-cpu`, yielding a report card recording all
**55 / 55** ProductRows with populated `Catalog`, `Integration`, `E2E`,
`Negative`, and `Lane = linux-cpu` cells.

The same-day realness audit then **reopened** the phase: that report card attested
row/test *presence and green exit codes*, not *measured* learning and inference.
The offline `integration.product.<row>` tests are artifact-readers, not training
drivers; the "measured" RL `median_final_reward` is the expert-controller
heuristic; the live `runLiveWorkflowMatrixCell` cells assert stdout prefixes, not
measured outcomes; and `assertRlRowEvidence` (sound in isolation) was only ever
run on synthetic good/bad fixtures, never on real RL training output. Sprints
`28.1`, `28.2`, and `28.3` reclosed with the `### Closure Evidence` blocks below.
The per-model *measurement* obligation is guarded by
[Phase 33](phase-33-per-model-convergence-and-inference-tests.md)
(`jitml-model-convergence`), and the standing anti-fake gate that must reject
these fakes lives in
[Phase 32](phase-32-external-truth-realness-harness.md)
(`jitml-negative-controls`).

**Validation substrate**: `linux-cpu` only.

### Current Validation State

2026-07-03 `docker compose run --rm jitml jitml test jitml-integration
--linux-cpu` passed **137 / 137** tests, including the row-keyed
`ProductRow integration matrix` group and the live `linux-cpu` integration
cases. The matrix now validates row-id/test-id coverage against latest
publisher manifests instead of local checkpoint fixtures.

2026-07-03 `jitml internal train-and-publish-product-rows --linux-cpu` was run
against the live `linux-cpu` cluster with reduced validation budgets to expose
publisher reachability. It reported **55** rows, **8** eligible, **29**
unsupported, and **18** errors. At that point the failures were non-MNIST
supervised dataset artifacts missing from live MinIO, most RL product rows
dispatching to trainer/environment pairs that
`rlTrainerEnvironmentCompatibilityError` rejected, and supported RL rows that
did not produce passing `CompletedTraining` evidence under the validation run.
The RL dispatch/evidence portion reopened Phase `25`.

2026-07-03 follow-up: after Sprint `25.1` was fixed, a row-filtered publisher
run through the rebuilt worktree executable for
`PPO/mountain-car,DQN/key-door-grid,SAC/lunar-lander,ARS/lunar-lander` reported
**4** rows, **0** eligible, **0** unsupported, and **4** errors. The prior
`unsupported` blocker moved back to Phase `25.1` closure evidence, and the
remaining `CompletedTraining` errors moved to Phase `25.3`.

2026-07-03 Phase `25` closure follow-up: the full RL-only live product publisher
filter reported **39** rows, **39** eligible, **0** unsupported, and **0**
errors. The RL portion no longer blocks this phase.

2026-07-03 Sprint `28.1` closure: non-MNIST supervised dataset archives were
staged in live MinIO, the Envoy data-plane request was raised to
`memory: 512Mi` with a `1Gi` limit so large archive uploads stop OOM-killing the
edge, and row-filtered product publisher runs covered all **55** ProductRows:
**11 / 11** supervised rows, **39 / 39** RL rows, and **5 / 5** AlphaZero/tuning
rows reported eligible, with **0** unsupported and **0** errors. The
`ProductRow integration matrix` then passed **56 / 56** tests using latest
published manifests for real `CompletedTraining` hashes, update counts,
convergence metrics, manifest SHAs, and infer-before-completion rejection
evidence. The full `jitml-integration` executable passed **137 / 137** tests
after restarting `jitml-service` to restore held daemon consumers, and
`jitml-unit` passed **277 / 277**. `docs check` and `check-code` both passed.

2026-07-04 Sprint `28.2` implementation follow-up: the live Playwright suite is
row-generated from the ProductRow contract registry, the Webapp request/reply
paths subscribe from latest and acknowledge every consumed reply, and the route
assertions now check row-family output cardinalities against live payloads. The
canonical live `jitml-e2e` run reached the product-row matrix but exposed a
`jitml-demo` Webapp pod OOM kill under the chart's stale `128Mi`/`256Mi`
non-CUDA budget. The local chart and fallback resource profile now match the
raised Dhall budget (`512Mi` request / `3Gi` limit).

2026-07-04 Sprint `28.2` validation progress: after applying the raised
`jitml-demo` budget to the live `linux-cpu` cluster, `docker compose run --rm
jitml cabal run jitml -- test jitml-e2e --live --linux-cpu` passed. The run
selected the existing edge publication at `127.0.0.1:9091`, Playwright reported
**71 / 71** passing browser tests, including every generated
`e2e.product.*` ProductRow case, and the wrapper `jitml-e2e` Haskell suite
reported **24 / 24** passing structural tests.

2026-07-04 Sprint `28.2` closure: `docker compose run --rm jitml cabal run
jitml -- docs check` reported `docs check: ok`, and `docker compose run --rm
jitml cabal run jitml -- check-code` reported `check-code: ok` after the e2e
helper layout was formatted. All Sprint `28.2` validation gates are green.

2026-07-04 Sprint `28.3` implementation progress: `src/JitML/Test/Report.hs`
now renders a per-row report table with `Catalog`, `Integration`, `E2E`,
`Negative`, and `Lane` cells, fails naming missing rows or cells, and reports
explicit non-product rows separately instead of counting them as product
coverage. The live report-card collection attaches that table only for target
sets that include both `jitml-integration` and `jitml-e2e`, and the browser
matrix measurement now probes the live `/api/checkpoints` ProductRow selector
surface against all **55** ProductRows. A fast structural check,
`docker compose run --rm jitml cabal test jitml-e2e --test-show-details=direct`,
passed **25 / 25** after adding the report-card coverage tests. Sprint `28.3`
remained Active until the full live lane could be exercised.

2026-07-04 Sprint `28.3` validation blocker: the required
`docker compose run --rm jitml cabal run jitml -- test all --live --linux-cpu`
gate passed `jitml-unit` (**277 / 277**) and `jitml-integration`
(**137 / 137**) before failing in the pre-existing `jitml-sl-canonicals` live
section. Focused reruns reproduced live-lane instability: Harbor/Postgres/edge
pods entered crash loops or partial readiness, `/api/checkpoints` returned
`504`, and the SL live all-row staged-byte check saw MinIO
`SETransient "minioReadBytes: HTTP 503"` / missing artifact fetches. The
worktree now lowers live Cabal priority through the `jitml test --live` wrapper
and changes the SL all-row test to prefetch all staged bytes before device
training so future failures identify object-store availability instead of late
interleaved fetch loss. The `jitml-sl-canonicals --test-options='--list-tests'`
build/list pass succeeded. This was the final blocker before the live-lane
pressure fixes below.

2026-07-04 live-lane reprovision attempt: `./bootstrap/linux-cpu.sh down`
completed, then `./bootstrap/linux-cpu.sh up` rebuilt `jitml:local`, ran the
embedded `jitml check-code` successfully, loaded the image into the Kind
cluster, deployed Harbor/MinIO/Pulsar/monitoring/`jitml-service`/Envoy, and
executed **88** live phased rollout steps. The bootstrap failed at
`kubectl --kubeconfig ./.build/jitml.kubeconfig -n platform rollout status
deployment/harbor-core --timeout=300s`; stderr reported watch-stream
`http2: client connection lost`, repeated `net/http: TLS handshake timeout`,
and ended `error: timed out waiting for the condition`. Post-failure probes
still saw `kubectl` TLS handshake timeout and empty replies from
`http://127.0.0.1:9091/healthz` and `/api/checkpoints`, so
`jitml test all --live --linux-cpu` was not rerun after reprovision.

2026-07-05 Sprint `28.3` live-lane pressure fix and hardening: the bootstrap PV
preparation step binds every registered stateful PV to node-local
`/var/local/jitml-stateful-pv/...` storage on Docker-backed `linux-cpu` and
Apple Silicon live rollouts, while preserving the checked-in `.data` PV
identity and the Postgres uid/gid `26:26` normalization. This extends the
existing Postgres-only overlay to MinIO and Pulsar so high-churn object-store and
broker writes no longer run through the macOS/Colima shared mount. MinIO HTTP
paths now use bounded connect/read timeouts plus retries, the MinIO chart probes
allow slow object-store recovery, and the managed Envoy Deployment receives
readiness/startup/liveness probe tolerances for both `envoy` and
`shutdown-manager`.

2026-07-05 Sprint `28.3` closure: `docker compose build jitml` completed with
the embedded `check-code: ok` and PureScript bundle build, focused
`jitml-integration -p EnvoyProxy` passed **1 / 1**, focused
`jitml-integration -p HA` passed **3 / 3**, and focused
`jitml-sl-canonicals` passed **31 / 31** including the live materialization and
live MNIST convergence cases. The refreshed image was loaded into the live
`jitml-linux-cpu` Kind cluster, `jitml-service` and `jitml-demo` rolled out at
edge `127.0.0.1:9091`, `/healthz` returned `HTTP 200`, `/api/checkpoints`
returned **55** checkpoint rows with **55** selectors and **55** summaries, and
`jitml cluster status` reported every component ready. The required full gate
`docker compose run --rm jitml jitml test all --live --linux-cpu` passed all
**8 / 8** stanzas (`jitml-unit`, `jitml-integration`,
`jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
`jitml-backends`, `jitml-daemon-lifecycle`, and `jitml-e2e`) with
`cabal_test: passed: 8, failed: 0`, `daemon_healthz` populated, and
`browser_product_matrix: checkpoint-backed product rows 55/55 served at edge
:9091`. The validation log is
`.build/validation-logs/phase28-full-linux-cpu-20260705-after-edge-hardening.log`.

2026-07-05 realness-audit reopen: a dependency-blind read of the offline and live
suites showed the green **55 / 55** report card certifies row/test presence and
green exit codes, not measured learning or inference:

- The offline `integration.product.<row>` tests are **artifact-readers**: they
  load published ProductRow checkpoint manifests from `.build/checkpoints`
  (`test/integration/Main.hs`, `src/JitML/Test/RowAssertions.hs`) and assert over
  recorded fields; they do not drive a real training run, so a manifest with the
  right shape passes without any learning having occurred.
- The RL rows' "measured" `median_final_reward` is the **expert-controller
  heuristic**, not a trained-policy rollout — the number a green row reports is
  produced by a scripted controller, so it certifies the script, not the learned
  policy.
- The live `runLiveWorkflowMatrixCell` cells assert **stdout prefixes**
  (command-shape and presence strings), not measured convergence or inference
  outcomes, so a well-formed log line passes a cell whose model learned nothing.
- `assertRlRowEvidence` is sound in isolation but is only ever fed **synthetic
  good/bad fixtures** in the suite; it is never run against real RL training
  output, so its fail-closed strength is never exercised on the product path.

The per-model *measurement* obligation (drive real training from a random init;
assert measured convergence ≥ the external bar and a non-wall-clock
inference-performance floor) transfers to new
[Phase 33](phase-33-per-model-convergence-and-inference-tests.md)'s
`jitml-model-convergence` stanza. The standing anti-fake guard that must reject
the expert-controller reward, the artifact-read shortcut, and the stdout-prefix
cell is the [Phase 32](phase-32-external-truth-realness-harness.md)
`jitml-negative-controls` suite. Sprints `28.1`, `28.2`, and `28.3` reclosed
after those suites passed against this phase's rows on `linux-cpu`.

## Objective

Every `ProductRow` in the canonical registry is bound to one integration test id
and one e2e test id, both keyed by `rowId`, and both drive the real
training/checkpoint/inference and live-demo paths rather than a representative
smoke check. The integration matrix folds `allProductRows`, dispatches per
family (`Supervised`, `ReinforcementLearning`, `AlphaZero`, `Tuning`) to real
training-then-checkpoint-then-inference-before-completion-rejection assertions,
and the Playwright suite generates one live test per row from the same generated
registry. A green pass count without row identity does not close this phase: the
report card enumerates every row and fails on any uncovered `rowId`/`testId`
pair.

## Sprint 28.1: Row-Keyed Integration Matrix [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`, `src/JitML/Test/RowAssertions.hs`, `src/JitML/Test/Report.hs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/product_completion_contract.md`

### Objective

The integration stanza is a row-keyed matrix generated from the typed product
registry, not a hand-listed set of representative workflows. Each product row
runs the real command path for its family and asserts that learned state
actually changed.

### Deliverables

- `src/JitML/Test/RowAssertions.hs` exposes real-ML assertion primitives:
  `paramHash` (deterministic initial/final parameter hash), `assertLearnedStateChanged`
  (final hash differs from initial hash with a non-zero update count), and
  `assertRealLoss` (a real, finite, decreasing loss trajectory over the declared
  budget — no hardcoded or deterministic-scaffold summary satisfies it).
- `test/integration/Main.hs` folds `allProductRows` and dispatches per `family`:
  `Supervised`, `ReinforcementLearning`, and `AlphaZero` rows train for their
  fixed budget, write a `CompletedTraining` checkpoint, and reject inference
  before completion; `Tuning` rows drive the real hyperparameter search path and
  record the selected configuration's learned-state delta.
- Each row's `integrationTest` id is exercised by exactly the test the registry
  names; the matrix binds `rowId` → `testId` with no duplicate or orphan ids.
- `src/JitML/Test/Report.hs` collects per-row integration evidence and **fails
  naming any uncovered `rowId`/`testId` pair** — a row without a real,
  learned-state-changing integration test cannot pass.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The obligation this sprint owns — every product row bound to
an integration test that drives the **real** training/checkpoint/inference path
and asserts learned-state change — is unmet in substance:

- The `integration.product.<row>` cases **read** published checkpoint manifests
  from `.build/checkpoints` and assert over recorded fields; they do not drive a
  training run, so `assertLearnedStateChanged` / `assertRealLoss` are checked
  against a manifest rather than a live-computed trajectory
  (`test/integration/Main.hs`, `src/JitML/Test/RowAssertions.hs`).
- The RL rows' `median_final_reward` is the **expert-controller heuristic**, not
  a trained-policy rollout, so the reward evidence certifies the scripted
  controller, not the learned policy.
- `assertRlRowEvidence` is sound but is only exercised on **synthetic** good/bad
  fixtures, never on real RL training output.

Closed by: the per-model *measurement* obligation (train from a real random init;
assert measured convergence + inference performance) transfers to new
[Phase 33](phase-33-per-model-convergence-and-inference-tests.md)'s
`jitml-model-convergence` stanza, and the negative-control that must reject the
artifact-read shortcut, the expert-controller reward, and any `assertRlRowEvidence`
case never run on real output is the
[Phase 32](phase-32-external-truth-realness-harness.md) `jitml-negative-controls`
suite. This sprint returned to Done after its rows drive real training and both
suites are green on `linux-cpu`.

## Sprint 28.2: Row-Complete Playwright [✅ Done]

**Status**: Done
**Implementation**: `playwright/jitml-demo.spec.ts`, `src/JitML/Test/LivePlan.hs`, `src/JitML/App.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`, `../documents/engineering/unit_testing_policy.md`

### Objective

The live demo has one Playwright test per product row, generated from the same
generated registry the integration matrix uses, and each test renders the row's
trained artifact against a live edge with fail-closed negative coverage.

### Deliverables

- `playwright/jitml-demo.spec.ts` loads the product rows from the generated
  contract registry and generates one test per row, titled by the row's
  `prowE2eTest` id, with family-specific renderer assertions (supervised
  prediction panel, RL rollout/return panel, AlphaZero board/policy panel,
  tuning trial-table panel).
- Each generated test asserts fail-closed negatives: missing artifact, untrained
  checkpoint, partial/failed-provenance checkpoint, missing cluster, and
  unsupported substrate each render the fail-closed state instead of a stale or
  synthetic panel.
- `src/JitML/Test/LivePlan.hs` exposes a substrate-parametrized `LivePlan` and
  `src/JitML/App.hs` wires the live Playwright run into
  `jitml test jitml-e2e --live --linux-cpu`, launching or selecting the live
  cluster and binding the run to `linux-cpu`.
- A fake browser-runtime route test remains a structural test only and cannot
  satisfy a row's `e2eTest` evidence.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The obligation — one live e2e test per row that drives the
row's real trained artifact through live per-row inference — is unmet in
substance: the live `runLiveWorkflowMatrixCell` cells assert **stdout prefixes**
(command-shape and presence strings), not the row's measured inference outcome,
so a well-formed log line passes a cell whose model learned nothing. The suite
must drive live per-row inference on the trained artifact and assert a measured
value, not a prefix.

Closed by: live per-row inference-performance measurement is owned by new
[Phase 33](phase-33-per-model-convergence-and-inference-tests.md)
(`jitml-model-convergence`, inference-performance floor); the standing guard that
rejects a stdout-prefix cell as passing evidence is the
[Phase 32](phase-32-external-truth-realness-harness.md) `jitml-negative-controls`
suite. This sprint returned to Done after each live cell asserts a measured
inference outcome and both suites are green on `linux-cpu`.

## Sprint 28.3: linux-cpu Report Card [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/Report.hs`, `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`
**Docs to update**: `system-components.md`, `README.md`

### Objective

The `linux-cpu` report card is a per-row evidence table that fails on any missing
cell, and the committed attestation reflects a real, row-complete `linux-cpu`
run.

### Deliverables

- `src/JitML/Test/Report.hs` renders one row per `ProductRow` with the columns
  `Catalog` (generated matrix parity), `Integration` (real learned-state-changed
  test), `E2E` (live per-row Playwright test), `Negative` (fail-closed cases),
  and `Lane` (`linux-cpu` validated), and **fails on any missing cell**.
- The report distinguishes an explicitly non-product row from a missing-evidence
  row so a black-box/non-ANN row is never silently counted as complete.
- `DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md` is committed only
  after the phase validation passes, and it carries dated, row-keyed evidence for
  the full matrix.

### Validation

```bash
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Closure Evidence

Reopened 2026-07-05. The report card's per-row cells attest **presence and green
exit codes** (a row has an integration id, an e2e id, a negative case, a
`linux-cpu` lane) rather than **measured** outcomes: the `Integration` cell is
backed by an artifact-read, the `E2E` cell by a stdout-prefix live cell, and the
RL `median_final_reward` by the expert-controller heuristic. A **55 / 55** green
card therefore does not certify learning or inference. The report card must fail
any row whose integration/e2e evidence is not a measured training/inference
outcome.

Closed by: the per-row **measured** convergence + inference-performance evidence
the card must consume is produced by new
[Phase 33](phase-33-per-model-convergence-and-inference-tests.md)
(`jitml-model-convergence`), and the standing negative-control that the card's
gate must not pass a faked cell is the
[Phase 32](phase-32-external-truth-realness-harness.md) `jitml-negative-controls`
suite. The committed `linux-cpu` attestation is re-issued only after the card is
backed by measured per-row evidence and both suites are green on `linux-cpu`.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/unit_testing_policy.md` — row-keyed integration/e2e
  coverage ownership and the uncovered-pair failure rule.
- `documents/engineering/purescript_frontend.md` — per-row generated Playwright
  suite and fail-closed negative rendering.
- `documents/engineering/product_completion_contract.md` — integration/e2e
  evidence fields satisfied per row on `linux-cpu`.

**Product docs to create/update:**
- `README.md` — test-stanza descriptions for the row-keyed `jitml-integration`
  and `jitml-e2e` matrices.

**Cross-references to add:**
- Link the committed `linux-cpu` attestation from Phase `31`.
