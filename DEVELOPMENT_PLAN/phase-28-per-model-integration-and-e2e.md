# Phase 28: Per-Model Integration & Row-Complete E2E

**Status**: Done
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-27-demo-all-model-rendering.md](phase-27-demo-all-model-rendering.md), [phase-29-linux-cuda-product-lane.md](phase-29-linux-cuda-product-lane.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md), [../documents/engineering/unit_testing_policy.md](../documents/engineering/unit_testing_policy.md), [../documents/engineering/purescript_frontend.md](../documents/engineering/purescript_frontend.md)
**Generated sections**: none

> **Purpose**: Every product row owns a named integration test and e2e test that
> exercises real training, checkpointing, and demo rendering on `linux-cpu`, and
> the coverage report fails naming any missing row/test pair.

## Phase State

✅ **Done**. Phase `27` remains Done for its owned demo-rendering surface, and
Phase `25` re-closed on 2026-07-03 after every live RL product row produced
passing `CompletedTraining` evidence. Sprint `28.1` is Done after the
row-keyed integration matrix switched from synthetic fixtures to published
ProductRow checkpoint manifests. Sprint `28.2` is Done after the live
row-complete Playwright suite passed against `linux-cpu`. Sprint `28.3` closed
on 2026-07-05 after the node-local stateful PV overlay, MinIO retry/probe
hardening, and Envoy probe hardening kept the `linux-cpu` live lane healthy
through `jitml test all --live --linux-cpu`. The resulting report card records
all **55 / 55** ProductRows with populated `Catalog`, `Integration`, `E2E`,
`Negative`, and `Lane = linux-cpu` cells.

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

### Remaining Work

None. The integration matrix now reads latest published ProductRow checkpoint
manifests from `.build/checkpoints`, requires inference-eligible
`CompletedTraining` witnesses, and preserves the uncovered row/test-pair
failure report.

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

### Remaining Work

None. The live Playwright suite now generates one browser test per ProductRow
from the generated registry, asserts row-family renderers and fail-closed
browser negatives, and passed through `jitml test jitml-e2e --live --linux-cpu`
with the raised Webapp resource budget.

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

### Remaining Work

None. The node-local stateful PV overlay, MinIO retry/probe hardening, and Envoy
probe hardening kept the live `linux-cpu` lane healthy through the required full
gate. The refreshed `linux-cpu` attestation records the row-complete report card
for all **55 / 55** ProductRows.

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
