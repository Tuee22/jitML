# CLI Command Surface

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md
**Generated sections**: cli-commands.help-blocks

> **Purpose**: Reference mirror of the README-owned CLI command matrix for
> `jitml` and `jitml-demo`; defers to the doctrine for parser, generated
> artifact, introspection, output, and standard-flag patterns.

## Doctrine Deferrals

This doc defers to [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for:

- **Command Topology** — commands as ordinary Haskell ADTs.
- **CommandSpec** — record fields (`name`, `summary`, `description`,
  `children`, `options`, `examples`, `longName`, `shortName`, `metavar`,
  `required`); the parser is a renderer of the spec, not the source of truth.
- **Progressive Introspection** — `jitml commands [--tree|--json]`,
  `jitml help <subcommand>`.
- **Standard Flag Families** — Plan/Apply (`--dry-run`, `--plan-file`),
  Daemon (`--config`, `--no-daemon`), Output (`--format`, `--color`,
  `--no-color`).
- **Output Rules** — stdout primary, stderr diagnostics; default `table` on
  TTY else `plain`.
- **Generated Artifacts** — paired `jitml docs check` /
  `jitml docs generate`; `GeneratedSectionRule` registry;
  `trackingGeneratedPaths`.

This doc does not duplicate the doctrine's prose. The authoritative command
snapshot lives in [../../README.md → CLI command topology, typed](../../README.md#cli-command-topology-typed);
the tree below is the engineering reference mirror.

## jitML Command Tree

The leaves below are the jitML-specific surface; the doctrine owns the shape.

### `jitml service`

Long-running daemon. Parameterised entirely by Dhall config (`BootConfig` +
`LiveConfig`). No separate `host-service` verb.

```
jitml service [--config <path/to/config.dhall>]
              [--dry-run | --plan-file <path>]
```

### `jitml cluster`

Cluster lifecycle.

```
jitml cluster up [--substrate apple-silicon|linux-cpu|linux-cuda]
                 [--dry-run | --plan-file <path>]
jitml cluster down
jitml cluster status
jitml cluster reset --yes
```

### `jitml train`

Plan/Apply training run.

```
jitml train <experiment-dhall>
            [--resume <checkpoint-id>]
            [--dry-run | --plan-file <path>]
```

### `jitml eval`

Deterministic evaluation run.

```
jitml eval <experiment-dhall> [--checkpoint <checkpoint-id>]
```

### `jitml tune`

Plan/Apply hyperparameter sweep.

```
jitml tune <tune-dhall>
           [--resume <sweep-id>]
           [--dry-run | --plan-file <path>]
```

### `jitml rl`

RL lifecycle.

```
jitml rl train <rl-experiment-dhall>
               [--resume <checkpoint-id>]
               [--dry-run | --plan-file <path>]
jitml rl eval <rl-experiment-dhall> [--checkpoint <checkpoint-id>]
jitml rl rollout <rl-experiment-dhall> [--seed <word64>]
```

### `jitml verify`

Determinism verification.

```
jitml verify same-run --experiment <experiment-dhall> --runs <int>
jitml verify cross-backend --experiment <experiment-dhall> --backends <list>
jitml verify replay --experiment <experiment-dhall> --checkpoint <checkpoint-id>
```

### `jitml inspect`

Inspect cached transcripts and checkpoints.

```
jitml inspect list
jitml inspect show <manifest-sha> [--with-equity]
jitml inspect replay <manifest-sha>
jitml inspect trial <trial-hash>
jitml inspect frontier <sweep-id>
```

### `jitml bench`

Benchmark harnesses.

```
jitml bench train <experiment-dhall>
jitml bench inference <experiment-dhall> --checkpoint <checkpoint-id>
jitml bench env <rl-experiment-dhall>
```

### `jitml inference run`

Inference-at-any-point.

```
jitml inference run <experiment-dhall>
                    --checkpoint latest|best/<metric>|<manifest-sha>
                    [--trial <trial-hash>]
```

### `jitml test`

Plan/Apply test orchestrator.

```
jitml test all [--dry-run | --plan-file <path>]
jitml test <stanza>
```

### `jitml lint`

Lint stack (paired with `jitml docs check`).

```
jitml lint files
jitml lint docs
jitml lint proto
jitml lint haskell
jitml lint purescript
jitml lint chart
jitml lint all [--write]
```

### `jitml docs`

Generated-section reconciler.

```
jitml docs check
jitml docs generate
```

### `jitml commands`

Command tree introspection.

```
jitml commands
jitml commands --tree
jitml commands --json
```

### `jitml help`

Equivalent to `<subcommand> --help`.

```
jitml help <subcommand>
```

### `jitml check-code`

Code quality gate (formatter + hlint + warning-clean build + forbidden-path
scan + chart lint + route-registry-drift check).

### `jitml build`

Build the inner Haskell binary inside the substrate container; mirrors
`bootstrap/<substrate>.sh build`.

### `jitml kubectl`

Passthrough pre-bound to `./.build/jitml.kubeconfig`.

### `jitml internal materialize-substrate` / `list-prereqs`

Non-doctrine-shaped helpers for substrate materialization and bootstrap
prerequisite introspection.

### `jitml internal vm` (Apple Silicon only)

```
jitml internal vm bootstrap
jitml internal vm up
jitml internal vm down
jitml internal vm status
jitml internal vm exec -- <cmd>
```

Pass-through to `tart ssh`. Apple-only escape hatch for debugging Swift build
failures. Rejected on Linux substrates with `AppError UnknownCommand`.

### `jitml internal cache`

JIT cache introspection.

```
jitml internal cache stat
jitml internal cache list
jitml internal cache evict <hash>
```

### `jitml internal gc`

Retention reconciler (exit `3` on no-op).

```
jitml internal gc <experiment-hash>
                  [--dry-run | --plan-file <path>]
```

### `jitml-demo`

Sibling binary serving the PureScript bundle plus the inference REST surface.

```
jitml-demo [--port <int>] [--bundle-path <dir>]
```

## Generated Help Blocks

The full `--help` text for each leaf is regenerated by `jitml docs generate`
into the marker pair below. Hand edits fail `jitml docs check`.

<!-- jitml:cli-commands.help-blocks:start -->
_(Generated by Sprint 1.3; see
[../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md → Sprint
1.3](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md).)_
<!-- jitml:cli-commands.help-blocks:end -->

## Cross-References

- [../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)
