# Phase 96: ALE Boundary and ROM Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: ALE Boundary and ROM Policy. Single-session phase migrated from legacy Sprint 8.8 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 96.1: ALE Boundary and ROM Policy [✅ Done]

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/JitML/RL/ALE.hs`,
`src/JitML/RL/Simulator.hs`,
`src/JitML/RL/Environments.hs`, `test/rl-canonicals/Main.hs`,
`test/integration/Main.hs`
**Docs to update**: `README.md`,
`documents/engineering/jit_codegen_architecture.md`,
`documents/engineering/code_quality.md`,
`documents/engineering/training_workloads.md`,
`documents/engineering/unit_testing_policy.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`DEVELOPMENT_PLAN/system-components.md`

### Objective

Remove the deterministic `atari-subset` RAM-state production stub and preserve
the current action/observation contract consumed by `AlgorithmModule`, `VecEnv`,
`RLLoop`, and the daemon-backed RL path through an explicit ROM-policy boundary.

### Deliverables

- `jitml:local` may build the ALE library/runtime from a pinned upstream tag or
  source SHA during image construction; do not depend on an Ubuntu `libale-dev`
  package, because the 2026-06-04 Ubuntu 24.04 image validation found no such
  package candidate.
- The Haskell FFI boundary lives behind `JitML.RL.ALE` rather than binding
  directly to C++ symbols from simulator code. The repository carries no
  checked-in C/C++ adapter source. If optional ALE execution is retained, the
  adapter operations Haskell needs (create/destroy, load ROM, reset, act,
  game-over, get RAM, get screen, legal actions, and seed) must come from a
  Haskell-generated build/cache artifact or an operator-supplied external
  library path.
- ROM inputs are explicit and uncommitted: `RunConfig.atariRomPath`,
  `JITML_ATARI_ROM`, or compatibility `JITML_ALE_ROM` names a local file,
  with developer ROMs kept under ignored `./.roms/`. No commercial ROM bytes
  enter the repository or image.
- `atari-subset` in the production training path no longer uses the
  deterministic RAM-state implementation as a production fallback. If an ALE
  runtime shim is unavailable, the path fails closed rather than using a static
  checked-in native source file.
- The `Deterministic atari-subset RAM-state stub` row moves from Pending
  Removal to Completed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

### Validation

1. `docker compose build jitml` builds the image and runs the container-only
   `jitml check-code` gate without compiling any checked-in C/C++ adapter
   source.
2. `cabal test jitml-unit jitml-rl-canonicals` validates the explicit
   no-ROM policy without committing ROM bytes. A separate manual ALE smoke run
   may validate same-seed determinism, legal action reporting, RAM dimension,
   screen dimension, reset, and a short episode when an operator supplies a ROM
   they are allowed to use.
3. `jitml rl train` with `envName = "atari-subset"` fails closed with the
   ROM-policy diagnostic when no explicit ROM is present, and no required
   validation depends on a ROM or checked-in adapter source.

2026-06-04 validation evidence:

- `docker compose build jitml` passed. The Docker image built ALE
  `v0.12.0` / commit `94c24368664b8539c53857522e50652ddcc44b20`, built
  the then-current `exe:jitml` / `exe:jitml-demo` pair, ran image-local
  `jitml check-code` with `check-code: ok`, built the PureScript bundle, and
  exported `jitml:local`. Sprint `11.10` later folded `jitml-demo` into the
  one-binary Webapp role.
- `docker compose run --rm jitml jitml check-code` passed with
  `check-code: ok`.
- `docker compose run --rm jitml cabal test jitml-unit jitml-rl-canonicals
  --jobs=2` passed: `jitml-unit` 183 / 183 and `jitml-rl-canonicals` 26 / 26.
  ROM-backed ALE smoke is optional/manual and was not part of required
  validation.
- The production no-ROM assertion passed by running `jitml rl train` with
  `JITML_ENVIRONMENT=atari-subset`, `JITML_MAX_STEPS=4`,
  `JITML_EVAL_EPISODES=1`, and no ROM env vars; the command failed closed and
  printed the ROM-policy diagnostic naming `JITML_ATARI_ROM`, `JITML_ALE_ROM`,
  and `RunConfig.atariRomPath`.
- The 2026-06-04 static-foreign-source correction deleted
  `csrc/jitml_ale_shim.cpp`, removed the Dockerfile compile step for
  `/usr/local/lib/libjitml_ale_shim.so`, and removed the lint allowlist. The
  remaining Haskell `JitML.RL.ALE` path requires a generated or externally
  supplied runtime shim for optional manual ALE execution.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
