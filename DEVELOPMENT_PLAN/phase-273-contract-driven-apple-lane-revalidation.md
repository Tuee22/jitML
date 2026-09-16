# Phase 273: Contract-Driven Apple Lane Revalidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Apple Lane Revalidation. Single-session phase migrated from legacy Sprint 30.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (reopened 2026-09-08 under standards rules `C` and `N`; unblocked
2026-09-12 when Sprint `268.1` closed). The prescribed real Apple lifecycle
completed, but its authenticated journal was not committed; the retained SHA-256
and Markdown projection cannot reconstruct its typed rows or admitted checkpoint
identities for Phase `276`. This phase is now the first open owner in the
numerical chain, and it closes only on the Apple Silicon host: standards rule
`M(d)` makes `apple-silicon` a single-host obligation, so no Linux or CUDA
session can discharge it.

### Historical Phase State

✅ **Done** (2026-09-08). The prescribed real Apple lifecycle completed from
the final Phase `273` source, produced the authenticated 55-row journal and
unchanged committed lane fragment, passed all ten Apple stanzas, and shut down
the host daemon and Kind workload.

## Sprint 273.1: Contract-Driven Apple Lane Revalidation [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Test/RunContract.hs`,
`src/JitML/Test/Report.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md`
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

### Remaining Work

- Rerun the prescribed Apple lifecycle on the Apple Silicon host using the
  durable journal-projection writer, and commit the authenticated typed input at
  `DEVELOPMENT_PLAN/attestations/apple-silicon-product-lane-journal.json` with
  its pinned SHA-256, as Sprint `261.1` did for `linux-cpu` and Sprint `268.1`
  for `linux-cuda`.
- Revalidate all 55 row identities, plans, admitted manifests, measured
  evidence, Metal device witnesses, completion journal digests, and teardown,
  admitting the retained bytes through the production `admitProductLaneJournal`
  reader against the current `apple-silicon` projection.
- Sprint `268.1` is closed, so this sprint carries no unmet upstream blocker.
  Its only outstanding prerequisite is host access: the lifecycle needs a
  Metal-capable Apple Silicon Mac, which the current Linux CUDA host is not.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
