# Legacy Tracking for Development

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-15-cross-substrate-and-handoff.md](phase-15-cross-substrate-and-handoff.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Track newly identified reopened-phase development obligations
> that expand or redirect the current implementation but are not cleanup or
> deletion rows.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

This ledger tracks primary development scope discovered after a phase was
previously closed. It does not track compatibility helpers, deprecated paths, or
temporary scaffolds; those remain in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

No development rows are currently active. The copyright-free
`KeyDoorGrid-v0` replacement row closed on 2026-06-04 after Phase `8`
Sprint `8.9` landed the native environment/default example path and Phase `9`
Sprint `9.8` retargeted the algorithm/convergence matrix.

## Pending Development

None.

## Completed

| Item | Completed In | Notes |
|------|--------------|-------|
| Copyright-free visual RL demo replacement (`KeyDoorGrid-v0`) | Phase `8` Sprint `8.9`; Phase `9` Sprint `9.8` | `KeyDoorGrid-v0` is implemented in `src/JitML/RL/Simulator.hs` / `src/JitML/RL/Environments.hs`, routed through `src/JitML/RL/SimulatorLoop.hs`, covered by `test/unit/Main.hs` and `test/rl-canonicals/Main.hs`, and available through `experiments/key-door-grid.dhall`. The convergence matrix now targets `key-door-grid` where visual discrete-control coverage is required. Validation on 2026-06-04: `docker compose run --rm jitml jitml check-code` passed during image construction, `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' jitml cabal test jitml-unit jitml-rl-canonicals --jobs=2` passed (`jitml-unit` 184 / 184, `jitml-rl-canonicals` 27 / 27), and `docker compose run --rm -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' -e JITML_ENVIRONMENT=key-door-grid jitml jitml rl train experiments/key-door-grid.dhall` exited `0` without a ROM path. |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [development_plan_standards.md](development_plan_standards.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md)
