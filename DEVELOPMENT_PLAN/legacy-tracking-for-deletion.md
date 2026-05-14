# Legacy Tracking

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-0-planning-documentation.md](phase-0-planning-documentation.md),
[phase-1-haskell-cli-surface.md](phase-1-haskell-cli-surface.md),
[phase-2-bootstrap-reconciler-and-jit-cache.md](phase-2-bootstrap-reconciler-and-jit-cache.md),
[phase-3-cluster-substrate-and-routing.md](phase-3-cluster-substrate-and-routing.md),
[phase-4-stateful-platform-services.md](phase-4-stateful-platform-services.md),
[phase-5-jitml-service-daemon.md](phase-5-jitml-service-daemon.md),
[phase-6-numerical-core.md](phase-6-numerical-core.md),
[phase-7-jit-codegen-and-substrates.md](phase-7-jit-codegen-and-substrates.md),
[phase-8-supervised-and-rl-framework.md](phase-8-supervised-and-rl-framework.md),
[phase-9-rl-catalog-alphazero-and-tuning.md](phase-9-rl-catalog-alphazero-and-tuning.md),
[phase-10-checkpointing-and-inference.md](phase-10-checkpointing-and-inference.md),
[phase-11-purescript-frontend-and-demo.md](phase-11-purescript-frontend-and-demo.md),
[phase-12-test-stanzas-and-cross-cluster.md](phase-12-test-stanzas-and-cross-cluster.md),
[../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
**Generated sections**: none

> **Purpose**: Record every surviving compatibility helper, deprecated path,
> doctrine deviation, and tooling residue still slated for deletion.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

Phase `0` closed with no doctrine-audit residue. Sprint `1.1` introduced one
toolchain compatibility helper in `cabal.project` so the doctrine-mandated `dhall`
dependency builds under pinned GHC `9.14.1`; that row remains pending until the
upstream package bounds no longer need local override and must be retired before
the Phase `12` closure gate.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented code
   does not yet honour against an in-scope doctrine section, scheduled through the
   owning sprint per standards rule L.
2. **Stand-in residue.** Any temporary scaffolding (placeholder kernel, smoke
   subprocess, in-memory MinIO stub, etc.) used to keep CI green while the real
   implementation lands. Each stand-in must name the sprint that retires it.

The doctrine envelope at [00-overview.md → Doctrine Scope](00-overview.md#doctrine-
scope) admits no out-of-scope-but-implemented sections at write time — when
the `Smart Constructors for Paired Resources` doctrine section becomes in-scope
(any future PV/PVC pair, DNS/cert pair, or analogous coupled resources), that
opening event itself enqueues a row here naming the originating sprint.

## Pending Removal

| Item | Location | Reason | Owning Sprint |
|------|----------|--------|---------------|
| Scoped `allow-newer` for Dhall / CBOR transitive package bounds | `cabal.project` | Upstream `dhall`, `cborg`, `cborg-json`, and `serialise` releases have not yet relaxed bounds for GHC `9.14.1`'s `base`, `template-haskell`, `containers`, `bytestring`, and `time`; remove once Hackage releases support the pinned toolchain without overrides | Sprint 12.9 |

## Pending Removal Notes

Each pending-removal row resolves on the closure of the owning sprint listed in the
relevant phase document. Each row will move to `Completed` when the owning sprint
closes and the doctrine-required replacement is verified.

The expected populating events are:

- **Phase 1.** Any doctrine-adoption gap surfaced by Sprint `0.2`'s grep audit
  enqueues here under its owning Phase `1`–`12` sprint. The audit's job is to
  ensure no gap is silently adopted; the ledger is where unowned gaps would become
  visible.
- **Phase 5.** Any temporary in-memory or single-replica fake of `HasMinIO` /
  `HasPulsar` / `HasHarbor` / `HasKubectl` introduced before the real chart is up
  enqueues here under Sprint `5.4`.
- **Phase 7.** Any per-substrate codegen path that bypasses the
  `Subprocess`/`Plan`/`apply` discipline (for example, an in-process Metal compile
  that skips the typed boundary) enqueues here under the Phase `7` sprint that
  owns that substrate.
- **Phase 10.** If the checkpoint store's `If-Match`-CAS retry harness adopts any
  extra-doctrine retry shape beyond the typed `RetryPolicy` from Sprint `5.4`, the
  deviation enqueues here.
- **Phase 11.** Any hand-edited HTTPRoute, Grafana dashboard, or PureScript
  contract file that bypasses the generated-section / `trackingGeneratedPaths`
  registry enqueues here under the originating sprint until the renderer covers it.
- **Phase 12.** If the Pulumi-orchestrated cross-cluster stanza (`jitml-cross-
  cluster`) leaks state outside the ephemeral Kind stack (orphaned PVs, dangling
  Harbor projects, residual Docker volumes), the leak enqueues here under Sprint
  `12.4` until the teardown reconciler is deterministic.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| _(empty at write time)_ | — | — |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../HASKELL_CLI_TOOL.md](../HASKELL_CLI_TOOL.md)
