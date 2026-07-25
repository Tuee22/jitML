# Phase 155: DRY Real-Workflow Matrix, Fail-Closed

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: DRY Real-Workflow Matrix, Fail-Closed. Single-session phase migrated from legacy Sprint 12.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 155.1: DRY Real-Workflow Matrix, Fail-Closed [✅ Done]

**Status**: Done
**Implementation**: a new `JitML.Test.WorkflowMatrix` enumeration consumed by
`test/integration/Main.hs` and `test/e2e/Main.hs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`system-components.md`

### Objective

Run every reopened real workflow (SL train, SL eval, RL train, RL eval, RL
rollout, tune, inference, AlphaZero self-play) per substrate behind one DRY
matrix that **fails closed** without a live cluster, replacing the vacuous-pass
`-p Live` asserts (which called the pure trainer and asserted stdout prefixes,
passing even offline) and the model-less e2e asserts. Owns the test-surface
slice of [Exit Definition](README.md#exit-definition) item 17.

### Deliverables

- `JitML.Test.WorkflowMatrix` is the single typed enumeration of
  `(workflow, substrate)` cells with the canonical command + the expected
  real-output assertion for each; the integration `Live` runner iterates it
  rather than re-deriving per-workflow asserts, and `jitml-e2e` asserts the
  full matrix shape alongside the typed live e2e plan.
- Each cell **fails closed** without a live `cluster-publication.json` (no
  vacuous pass); a cell passes only when the real workflow produced real
  measured output on the resolved substrate.

### Validation

- Offline: the matrix fails closed (no live cluster → typed failure, not a
  vacuous pass); host-validatable.
- Structural e2e: `jitml-e2e` verifies complete workflow × substrate matrix
  coverage and the typed live e2e plan.
- Live workflow executor: `jitml-integration -p WorkflowMatrix` runs every
  current-substrate matrix cell against a live cluster.

### Current Validation State

Landed: `JitML.Test.WorkflowMatrix` enumerates the 8 reopened workflows × every
substrate (`workflowMatrix`), each cell carrying its canonical `jitml` command
(`workflowCommand`) with real positional experiment arguments and stable
checkpoint / experiment hashes for eval and inference. `test/e2e/Main.hs`
asserts the matrix covers every workflow × substrate and that each cell carries
a command (host-validatable coverage).

`test/integration/Main.hs` now adds the matrix-driven `Live` case. It loads the
current live publication, filters `WorkflowMatrix.workflowMatrix` to the current
substrate, asserts exactly one cell per workflow, stages minimal MNIST IDX
training data when missing, stages stable eval / inference checkpoints in
MinIO, and runs the canonical CLI command for every cell with real-output
snippets. The AlphaZero cell executes `jitml rl alphazero self-play`, which
probes the selected substrate `MlpDevice`, generates MCTS self-play samples
through device-backed leaf policy/value evaluation, trains the policy/value
head on-device, and reports sample count plus arena win rate.

Current local validation (2026-06-11 / 2026-06-12):

- `docker compose run --rm jitml cabal run jitml -- rl alphazero self-play
  --substrate linux-cpu --seed 31` passed and printed
  `rl alphazero self-play: substrate=linux-cpu`, `samples: 12`, and
  `arena-win-rate: 0.5`.
- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  **196 / 196** after the CLI parser / canonical leaf update.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed **28 / 28** after the device-backed AlphaZero sample-generation path
  landed.
- `docker compose run --rm jitml cabal test jitml-e2e` passed **20 / 20**.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p !/Live/'` passed **49 / 49**,
  compiling the new
  integration code while excluding the live group.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p WorkflowMatrix'` failed closed
  with no publication, as expected, with a `cluster-publication.json not found
  at .build/runtime/cluster-publication.json` failure that instructs the
  operator to run `jitml bootstrap --<substrate>` before `-p Live` tests.
- `docker compose run --rm jitml cabal run jitml -- docs check` passed after
  regenerating the CLI command docs / man page / completions for
  `jitml rl alphazero self-play`.
- `docker compose run --rm jitml cabal run jitml -- check-code` passed
  (`check-code: ok`) after the final HLint cleanup in the live binary locator.

Resolved live-validation failures on this host (2026-06-11 / 2026-06-12):

- `docker compose run --rm jitml cabal run jitml -- bootstrap --linux-cpu`
  failed at the Harbor Helm wait after **23** rollout steps on the preserved
  `.data` tree. Harbor core logged `Dirty database version 15. Fix and force
  version.`
- The failed cluster was torn down through `jitml cluster down`, the dirty
  `.data` tree was preserved as `.data-preserved-phase12-20260611-204433`, and
  `docker compose run --rm jitml cabal run jitml -- bootstrap --linux-cpu` was
  retried against a clean `.data` tree. The clean retry failed at the same
  Harbor Helm wait after **22** rollout steps; Harbor core logged
  `Dirty database version 1. Fix and force version.`
- While that failed cluster was up, the live `WorkflowMatrix` selector reached
  the published edge but failed during dataset staging because `/healthz` and
  `/minio/s3` returned `curl: (52) Empty reply from server`; this matches the
  incomplete Harbor/Gateway rollout rather than an AlphaZero matrix-code
  failure.
- The failed retry was torn down through `jitml cluster down`; `kind get
  clusters` then reported no Kind clusters.
- The bootstrap path was then fixed so `linux-cpu` uses the same node-local
  Percona Postgres PV overlay as Apple Silicon on Docker Desktop, while
  `linux-cuda` keeps direct `.data` ownership normalization on real Linux GPU
  hosts.
- The Harbor schema grant now makes the Harbor database owned by the `harbor`
  role before granting privileges on `public`, preventing migration writes from
  inheriting the wrong owner on fresh local clusters.
- `liveExecutePhasedRollout` removes stale
  `.build/runtime/cluster-publication.json` before selecting and publishing a
  fresh live coordinate, so a failed or cross-substrate publication cannot send
  validation traffic to the wrong edge.
- `EnvoyProxy/jitml-edge` now pins the managed Envoy data-plane request to
  `cpu: 50m` / `memory: 512Mi` with a `1Gi` memory limit, allowing the local
  Kind stack to schedule the proxy while keeping large dataset/archive uploads
  inside a bounded data-plane envelope.
- The live WorkflowMatrix runner now prefers the freshly built
  `dist-newstyle/.../jitml` executable over the container image's installed
  fallback, so newly added CLI leaves are exercised by the test binary that was
  just built.

Linux live validation is no longer blocked on this machine:

- `docker compose run --rm jitml cabal run jitml -- bootstrap --linux-cpu`
  passed **83** live rollout steps against a clean `linux-cpu` cluster on
  2026-06-12.
- `curl -i --max-time 10 http://127.0.0.1:9091/healthz` returned
  `HTTP/1.1 200 OK`, and `Gateway/jitml-edge` reported `Programmed=True`.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct --test-options='-p WorkflowMatrix'` passed
  **1 / 1** against that live `linux-cpu` cluster on 2026-06-12, and passed
  again after the binary-locator HLint cleanup.
- `docker compose run --rm jitml cabal test jitml-integration
  --test-show-details=direct` passed **67 / 67** against a clean
  `linux-cpu` cluster on 2026-06-11.
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu` passed
  **20 / 20** on 2026-06-11.
- `docker compose run --rm jitml-cuda cabal test -fcuda jitml-integration
  --test-show-details=direct` passed **67 / 67** against a fresh
  `linux-cuda` cluster on 2026-06-11.
- `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
  passed **20 / 20** on 2026-06-11.

### Remaining Work

None. The integration `Live` group is the sprint-owned real-workflow matrix
executor; `jitml-e2e` remains the structural/browser/live-plan stanza. The
Apple matrix execution belongs to Phase `16`, and final handoff belongs to
Phase `17`. The later failed-Job observation gap is owned by Sprint `12.12`.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
