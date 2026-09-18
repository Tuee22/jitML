# Phase 273: Contract-Driven Apple Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Apple Lane Revalidation. Single-session phase migrated from legacy Sprint 30.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-09-17). The real Apple lifecycle passed all ten test
stanzas, retained the exact portable 55-row journal, admitted it through the
production reader, proved host Metal placement, and completed daemon drain,
cluster teardown, docs, and container code-quality gates. The evidence-retention
obligation that reopened this phase is met in the worktree; staging and
committing remain exclusively the human user's responsibility under `AGENTS.md`.

### Historical Phase State

✅ **Done** (2026-09-08). The prescribed real Apple lifecycle completed from
the final Phase `273` source, produced the authenticated 55-row journal and
unchanged committed lane fragment, passed all ten Apple stanzas, and shut down
the host daemon and Kind workload.

## Sprint 273.1: Contract-Driven Apple Lane Revalidation [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md`,
`DEVELOPMENT_PLAN/attestations/apple-silicon-product-lane-journal.json`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/apple_silicon_metal_headless_builds.md`,
`system-components.md`

### Objective

Revalidate the full row-complete workflow contract on the real Apple host and
replace the `apple-silicon` fragment with journal-derived evidence. This sprint
owns the Apple-lane portions of
[Exit Definition](README.md#exit-definition) items `31`, `32`, and `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Run every supported Apple product scenario through the validated plan, exact
  evidence reducer, and scoped lifecycle while preserving host-resident Metal
  placement.
- Prove each completed row journal carries the Apple/Metal device witness,
  host-command placement evidence, exact terminal evidence, trained artifact
  hash, and measured inference result.
- Assert no Metal-backed training, RL, or tuning workload Job is created in the
  cluster; failures retain host-daemon and cluster-forwarder diagnostics.
- Replace the committed `apple-silicon` fragment only after the complete live
  lifecycle passes, with explicit failed/not-run cells otherwise.
- Keep this phase independent of `linux-cuda` execution: validation uses only
  `apple-silicon` plus the host's `linux-cpu` support surface.

### Validation

After `up`, stage all twelve canonical artifacts through `jitml internal
upload-dataset` as described in [Dataset sources](../README.md#dataset-sources).
Build and probe the fixed bridge with `./.build/jitml internal
install-metal-bridge` on a fresh build tree. Start
`./bootstrap/apple-silicon.sh run-daemon` in a separate foreground session and
wait for real Metal readiness and all four consumers before running `test`.
Keep that daemon available throughout the test lane, then stop it before `down`.

```bash
./bootstrap/apple-silicon.sh up
./bootstrap/apple-silicon.sh test
./bootstrap/apple-silicon.sh down
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Completion Evidence

- `./bootstrap/apple-silicon.sh up` exited `0` against immutable image
  `sha256:d9105907767618e1af564a4a5fbe23535e87c3c71c803d0c49ae83d60473101e`;
  the bootstrap executed **113** live rollout steps, and the host daemon
  reported `apple.metal-runtime=yes`, `apple.metal-bridge=yes`,
  `connected-consumers=4`, and `ready`.
- `./bootstrap/apple-silicon.sh test` exited `0` after **106,546.281929 s**.
  All **10 / 10** stanzas passed with **0** failed and **0** not-run: unit
  **906 / 906**, integration **197 / 197**, SL canonicals **36 / 36**, RL
  canonicals **47 / 47**, hyperparameter **26 / 26**, backends **25 / 25**,
  daemon lifecycle **54 / 54**, e2e **30 / 30**, negative controls **3 / 3**,
  and model convergence **111 / 111**.
- The authenticated version-`3` journal records run
  `jitml-product-scenario-45c81e636039819c`, substrate `apple-silicon`, exactly
  **55 / 55** rows, checkpoint-scope digest
  `7c94acc7f1bc6124b3bfcaff2cf706f71c37587a10dfeed2b47f0e1b114fe0d8`,
  projection-batch digest
  `d0b5713f59df3ea3090bab7c2615d6fcd796f4fae30c063a91213ffa308be607`,
  and retained-file SHA-256
  `67134e1e47efe819b041c38830bda4a73809d0fd7146adadd7a11c6154e2fef3`.
  The in-suite comparator re-minted the exact committed row cells.
- The live closing snapshot contained only the three expected platform
  provisioning/init Jobs (`minio-provisioning`, `pulsar-bookie-init`, and
  `pulsar-pulsar-init`), no Metal training/RL/tuning workload Job; every running
  pod was Ready with zero restarts. Isolated edge-probe misses during sustained
  load recovered on the immediately following sample without a test or daemon
  restart, and the final edge snapshot was Ready.
- `./bootstrap/apple-silicon.sh down` exited `0`; the two Kind nodes were
  deleted, no Kind cluster or Docker container remained, and no Phase `273`
  test or daemon process/session remained. The final Apple build tree is
  preserved at `.build/dist-newstyle-apple-phase273-final-20260908`; the saved
  Linux tree is restored as `dist-newstyle` for the CUDA-machine handoff.

### Closure Evidence

- **2026-09-16 Apple Silicon Mac attempt:** `./bootstrap/apple-silicon.sh doctor`
  exited `0`; the host is macOS `arm64`, and Docker `29.2.1` is available with
  33,585,676,288 bytes of VM memory. The previous Linux-host prerequisite gap
  does not apply to this session. `system_profiler SPDisplaysDataType` reports
  the 32-core Apple M1 Max and Metal support. Real kernel validation is
  recorded separately below.
- The initial `./bootstrap/apple-silicon.sh up` attempt exited `1` after its
  duplicate in-rollout image build was intentionally cancelled.
  Its native GHC `9.12.4` build completed and produced the signed `.build/jitml`;
  all **18 / 18** platform images were pulled and both Kind nodes were created.
  MinIO and Registry v2 reached Ready and are retained. The initial attempt is
  not closing evidence.
- `docker compose build jitml` exited `0`, including its embedded
  `check-code: ok` gate and browser bundle build. The immutable image is
  `sha256:7a99fd6655af56f6f3a47aad83d4e21f3640f6b271ce4e14d82ffb74dd652bf4`.
  Byte comparisons confirm its application, generated Haskell, test, Dhall,
  bootstrap, browser source, and Cabal inputs match the worktree.
  `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/apple-silicon.sh up`
  exited `0`, executing **110** live rollout steps with that image. The
  supported status command reports every component Ready and the published
  `apple-silicon` edge at port `9090`.
- During the resumed rollout, the pinned kube-state-metrics and Grafana
  sidecar pulls initially timed out inside Kind. A host-image import attempt
  exited `1` on an unavailable multi-platform content digest; its separate
  logs are retained as diagnostic evidence. The normal rollout recovered:
  Pulsar, Grafana, kube-state-metrics, the Prometheus operator, and Prometheus
  reached Ready with zero restarts. The resumed bootstrap subsequently passed.
- `./bootstrap/apple-silicon.sh run-daemon` acquired
  `apple.metal-runtime=yes`, `apple.metal-bridge=yes`, and all **4** consumers,
  then reported `ready`. It remained available throughout the live Apple validation.
- The focused `jitml test jitml-backends --apple-silicon` gate
  exited `1`: **20 / 25** cases failed because this fresh build tree did not
  yet contain the fixed Metal bridge dylib. `jitml internal install-metal-bridge`
  then exited `0` with `metal_bridge_probe: ok`; the complete focused backend
  rerun exited `0`, **25 / 25** tests in **91.37 s**, with an empty stderr.
  This proves real Metal execution on the current host, but does not replace
  the full live lane. Separate stdout/stderr logs and terminal exit-code
  files are retained under `.build/phase273-20260916/`; a command without its
  terminal exit-code file has no recorded terminal result and supplies no
  closing evidence.
- `./bootstrap/apple-silicon.sh test` exited `0` on **2026-09-17** after
  **101,310.162505 s**. All **10 / 10** stanzas passed, **0** failed and **0**
  not-run: unit **907 / 907**, integration **197 / 197**, SL canonicals
  **36 / 36**, RL canonicals **47 / 47**, hyperparameter **26 / 26**, backends
  **25 / 25**, daemon lifecycle **54 / 54**, e2e **30 / 30**, negative controls
  **3 / 3**, and model convergence **111 / 111**. The invocation transcript,
  separate stderr, and terminal exit code are retained in `apple-full-lane.*`.
- Integration passed all **55 / 55** ProductRow assertions for run
  `jitml-product-scenario-4d8721b4dc58ac19`, the exact **11 / 39 / 4 / 1**
  family split, canonical order, persistent aggregate journal round-trip, and
  Phase `263` comparison with the committed Apple lane fragment. The live CLI
  workflow matrix passed in **8,184.92 s**. The comparator reproduced the
  existing fragment exactly, so no fragment rewrite is required.
- The parent's portable version-`1` journal is retained byte-for-byte at
  `DEVELOPMENT_PLAN/attestations/apple-silicon-product-lane-journal.json`
  (**177,591 bytes**) with SHA-256
  `1496c8632bb62d616ea99990774b2c5c2e2d95e148834a3932b6aae5e31d7621`.
  Its authenticated source-journal SHA-256 is
  `355ab2d8def1c1fe9347099a4bd988008d617ad2bf624bad0c1ff14ad28c3c1e`.
  The production `admitProductLaneJournal` reader exited `0`, admitting the
  exact current Apple projection with **55 / 55** ordered rows and Metal
  execution witnesses. Retention and admission logs are in
  `apple-journal-retention.json` and `apple-journal-admission.*`.
- The **2026-09-17 21:42 UTC** closing placement snapshot contains **17**
  running pods, all Ready with **0** container restarts, and only
  `minio-provisioning`, `pulsar-bookie-init`, and `pulsar-pulsar-init` Jobs.
  No Metal-backed workload Job exists. The host daemon drained after SIGTERM
  and exited `0`; `./bootstrap/apple-silicon.sh down` exited `0`, deleting both
  Kind nodes. Final resource verification found no owned Kind cluster, node
  container, test process, or daemon process. The retained journal digest is
  unchanged after teardown. `docker compose run --rm jitml jitml docs check`
  and `docker compose run --rm jitml jitml check-code` both exited `0`.
- The focused Mac `jitml test jitml-unit --apple-silicon
  --test-options='-p "Product phase status registry"'` gate exited `0`,
  **6 / 6**, with an empty stderr. It verifies all 70 registered phase
  documents against the typed statuses, forward-only dependencies, concrete
  validation gates, and single-accelerator validation.
- The initial and running-lane checkpoint
  `docker compose run --rm jitml jitml docs check` invocations exited `0`.
  The container rule-M scan reports **0** backward edges, **0** missing gates,
  **0** dual-accelerator gates across all 70 registered phases, and **0**
  accelerator invocations across the 20 aggregation validation blocks.
- The running-lane cluster snapshot has every running pod Ready with zero
  restarts and only the three expected provisioning/init Jobs. This snapshot
  is retained as `running-lane-pods-jobs.txt`; the closing snapshot and resource
  verification are retained as `closing-pods-jobs.*`, `closing-health.json`,
  and `teardown-verification.json`.
- Dataset preparation verifies each original archive against
  `canonicalArtifactSha256For` before live upload. All **12 / 12** original
  artifacts match their pins; their identities, byte counts, source URLs, and
  digests are retained in `.build/phase273-20260916/datasets/verified-datasets.json`.
  All **12 / 12** uploads through `jitml internal upload-dataset` exited `0`;
  their separate logs and `dataset-upload-results.json` are retained alongside
  the manifest. The focused native live inventory test exited `0`, **1 / 1**
  in **5.82 s**, reading exactly twelve objects through the published edge and
  verifying each canonical digest. The old README California Housing URL
  returned HTTP `504` on all three attempts; the README now points to
  scikit-learn's Figshare source, whose downloaded bytes match the existing
  `aaa5c9a6afe2225cc2aed2723682ae403280c4a3695a2ddda4ffb5d8215ea681` pin.

- After the status transition, the container `jitml test jitml-unit --linux-cpu
  --test-options='-p "Product phase status registry"'` gate exited `0`,
  **6 / 6**. The updated docs check passed and the rule-M scan again reported
  **0** backward edges, **0** missing gates, **0** dual-accelerator gates, and
  **0** accelerator invocations across **20** aggregation validation blocks.
  Closure-bookkeeping logs use the `*-closure.*` names in the evidence directory.

### Remaining Work

- None. All phase-owned obligations are met and validated in the worktree.

## Documentation Requirements

**Engineering docs to create/update:**

- [Typed run contract](../documents/engineering/run_contract.md) and
  [unit testing policy](../documents/engineering/unit_testing_policy.md) identify
  the retained portable-journal path and its production-reader admission gate.

**Product docs to create/update:**

- [Project README](../README.md): retained-journal status and the verified
  California Housing source URL.
- Plan control documents: Phase `273` closure and the next numerical owner.

**Cross-references to add:**

- None.
