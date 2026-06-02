# CLI Command Surface

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md
**Generated sections**: cli-commands.help-blocks

> **Purpose**: Reference mirror of the README-owned CLI command matrix for
> `jitml` and `jitml-demo`; defers to the doctrine for parser, generated
> artifact, introspection, output, and standard-flag patterns.

## Doctrine Deferrals

This doc defers to [../../README.md](../../README.md) for:

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

## Current Implementation Status

Sprint `1.1` has landed the Cabal package, the `jitml` and `jitml-demo` shims, and
the `src/JitML/App.hs` composition root. Sprint `1.2` has landed the
`CommandSpec` registry, generated parser, command tree, `commands --json`, and
focused `help <subcommand>` surfaces. Sprint `1.3` has landed the generated CLI
reference, help blocks, manpage, shell completions, and paired docs
check/generate reconciler. Sprint `1.4` has landed the lint surface and the
container-exclusive Haskell style/code-quality gate: runtime lint and
`check-code` execute only inside `jitml:local`. Sprints
`1.5` through `1.9` have landed Plan/Apply flags, typed subprocess boundary,
prerequisite registry, `Env` runner, global output flags, and structured error
rendering. Sprint `2.1`
has added `jitml bootstrap`, `jitml doctor`, `internal materialize-substrate`,
generated CLI docs for the expanded command surface, and the stage-0 script
handoff into `jitml bootstrap --<substrate>`. Sprint `2.2` has landed typed
toolchain/container/cluster prerequisite nodes, `jitml doctor --remediate`,
Homebrew remediation apply with postcondition validation, and the Apple
host-build cache-miss prerequisite root (CommandLineTools `swift`; the
`container.tart` node is removal-scheduled — Phase 2 Sprint `2.10`). The
`bootstrap` parser leaf validates
substrate selection; the full cluster apply body continues in the later Phase
`3` rollout work. Command implementations that perform daemon, cluster,
training, and substrate work remain blocked on their owning later sprints.

## jitML Command Tree

The leaves below are the jitML-specific surface; the doctrine owns the shape.

### `jitml bootstrap`

Plan/Apply substrate bootstrap. Stage-0 shell scripts delegate here after their
host gates pass.

```
jitml bootstrap --apple-silicon [--dry-run | --plan-file <path>]
jitml bootstrap --linux-cpu     [--dry-run | --plan-file <path>]
jitml bootstrap --linux-cuda    [--dry-run | --plan-file <path>]
```

### `jitml doctor`

Prerequisite registry check used by operators and by the Haskell bootstrap
reconciler after the stage-0 scripts have delegated into `jitml`.

```
jitml doctor [--scope toolchain|container|cluster] [--remediate]
```

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

Current code quality gate for in-repo hygiene, generated-doc drift,
forbidden-path scans, chart checks, Haskell primitive checks, external
Fourmolu / HLint / cabal-format checks, and the warning-clean build runner.
The same Haskell style gate runs during `jitml:local` image construction; the
CLI command rejects host execution before linting and must not install,
discover, or override host style tools.

### `jitml build`

Build the inner Haskell binary inside the substrate container; mirrors
`bootstrap/<substrate>.sh build`.

### `jitml kubectl`

Passthrough pre-bound to `./.build/jitml.kubeconfig`.

### `jitml internal materialize-substrate` / `list-prereqs`

Non-doctrine-shaped helpers for substrate materialization and bootstrap
prerequisite introspection.

### `jitml internal vm` (Apple Silicon) — **removed (Sprint 2.10, 2026-05-30)**

This command group (`bootstrap|up|down|status|exec`) managed the Tart build VM
and was **removed** under Phase 2 Sprint `2.10` (see
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md → Completed](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md#completed)).
The headless Apple Metal JIT builds the Swift glue dylib **on the host** with the
CommandLineTools `swift build` and JIT-compiles the Metal shader at runtime via
`MTLDevice.makeLibrary(source:)` — there is no Tart VM to provision, start, stop,
or exec into. See
[jit_codegen_architecture.md → Apple Silicon Headless JIT](jit_codegen_architecture.md#apple-silicon-headless-jit).

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
jitml-demo [--host <addr>] [--port <int>]
```

## Generated Help Blocks

The full `--help` text for each leaf is regenerated by `jitml docs generate`
into the marker pair below. Hand edits fail `jitml docs check`.

<!-- jitml:cli-commands.help-blocks:start -->
### `jitml bootstrap`

```text
jitml bootstrap

Bootstrap a substrate stack.

Plans and applies full substrate bootstrap: generated Dhall, Kind, Harbor-first rollout, platform services, cluster daemon, demo, and Apple host-daemon handoff.

Usage:
  jitml bootstrap [--apple-silicon] [--linux-cpu] [--linux-cuda] [--dry-run] [--plan-file <path>]

Options:
  --apple-silicon     Bootstrap the Apple Silicon substrate.
  --linux-cpu         Bootstrap the Linux CPU substrate.
  --linux-cuda        Bootstrap the Linux CUDA substrate.
  --dry-run           Print the plan without applying it.
  --plan-file <path>  Write the plan to a file.


Examples:
  jitml bootstrap --apple-silicon
      Bootstrap the Apple Silicon stack.
  jitml bootstrap --linux-cpu
      Bootstrap the Linux CPU stack.
  jitml bootstrap --linux-cuda
      Bootstrap the Linux CUDA stack.
```

### `jitml doctor`

```text
jitml doctor

Check host prerequisites.

Checks the typed prerequisite registry for the selected scope.

Usage:
  jitml doctor [--scope <toolchain|container|cluster>] [--remediate]

Options:
  --scope <toolchain|container|cluster>  Prerequisite scope to reconcile.
  --remediate                            Apply typed remediation actions for missing prerequisites.


Examples:
  jitml doctor --scope toolchain
      Check toolchain prerequisites.
```

### `jitml service`

```text
jitml service

Run the jitML daemon.

Runs the long-lived daemon using Dhall boot and live configuration.

Usage:
  jitml service [--config <path>] [--consume-once <n>] [--dry-run] [--plan-file <path>]

Options:
  -c, --config <path>  Path to the daemon Dhall config.
  --consume-once <n>   Acquire daemon subscriptions, drain n messages per subscription, dispatch them, and exit.
  --dry-run            Print the plan without applying it.
  --plan-file <path>   Write the plan to a file.


Examples:
  jitml service --config ./.build/conf/host/apple-silicon.dhall
      Run the host daemon using the Apple Silicon host config.
  jitml service --config /etc/jitml/BootConfig.dhall --consume-once 1
      Run one bounded daemon consumer batch from a service pod.
```

### `jitml cluster up`

```text
jitml cluster up

Bring the cluster up.

Materializes the selected substrate and reconciles the local cluster.

Usage:
  jitml cluster up [--substrate <substrate>] [--dry-run] [--plan-file <path>]

Options:
  --substrate <substrate>  apple-silicon, linux-cpu, or linux-cuda.
  --dry-run                Print the plan without applying it.
  --plan-file <path>       Write the plan to a file.


Examples:
  jitml cluster up --substrate apple-silicon
      Start the Apple Silicon substrate cluster.
```

### `jitml cluster down`

```text
jitml cluster down

Bring the cluster down.

Preserves stateful data while stopping the local cluster.

Usage:
  jitml cluster down



Examples:
  jitml cluster down
      Stop the local cluster.
```

### `jitml cluster status`

```text
jitml cluster status

Report cluster status.

Prints the publication state and health of the local cluster.

Usage:
  jitml cluster status



Examples:
  jitml cluster status
      Inspect the local cluster publication.
```

### `jitml cluster reset`

```text
jitml cluster reset

Destructively reset cluster state.

Removes local cluster state after an explicit confirmation flag.

Usage:
  jitml cluster reset --yes

Options:
  --yes  Confirm destructive reset.


Examples:
  jitml cluster reset --yes
      Reset all local cluster state.
```

### `jitml train`

```text
jitml train

Run a supervised training job.

Plans and applies a training job described by an experiment Dhall file.

Usage:
  jitml train <experiment-dhall> [--resume <checkpoint-id>] [--dry-run] [--plan-file <path>]

Options:
  <experiment-dhall>        Experiment Dhall file.
  --resume <checkpoint-id>  Checkpoint identifier to resume from.
  --dry-run                 Print the plan without applying it.
  --plan-file <path>        Write the plan to a file.


Examples:
  jitml train experiments/mnist.dhall
      Run a supervised training experiment.
```

### `jitml eval`

```text
jitml eval

Run deterministic evaluation.

Evaluates a trained model or policy against a deterministic cohort.

Usage:
  jitml eval <experiment-dhall> [--checkpoint <checkpoint-id>]

Options:
  <experiment-dhall>            Experiment Dhall file.
  --checkpoint <checkpoint-id>  Checkpoint identifier to evaluate.


Examples:
  jitml eval experiments/mnist.dhall --checkpoint latest
      Evaluate the latest checkpoint.
```

### `jitml tune`

```text
jitml tune

Run a hyperparameter sweep.

Plans and applies a hyperparameter sweep described by a tuning Dhall file.

Usage:
  jitml tune <tune-dhall> [--resume <sweep-id>] [--dry-run] [--plan-file <path>]

Options:
  <tune-dhall>         Tuning Dhall file.
  --resume <sweep-id>  Sweep identifier to resume.
  --dry-run            Print the plan without applying it.
  --plan-file <path>   Write the plan to a file.


Examples:
  jitml tune experiments/mnist-tune.dhall
      Run a tuning sweep.
```

### `jitml rl train`

```text
jitml rl train

Train an RL policy.

Plans and applies an RL training job.

Usage:
  jitml rl train <rl-experiment-dhall> [--resume <checkpoint-id>] [--dry-run] [--plan-file <path>]

Options:
  <rl-experiment-dhall>     RL experiment Dhall file.
  --resume <checkpoint-id>  Checkpoint identifier to resume from.
  --dry-run                 Print the plan without applying it.
  --plan-file <path>        Write the plan to a file.


Examples:
  jitml rl train experiments/cartpole.dhall
      Train an RL policy.
```

### `jitml rl eval`

```text
jitml rl eval

Evaluate an RL policy.

Runs deterministic policy evaluation.

Usage:
  jitml rl eval <rl-experiment-dhall> [--checkpoint <checkpoint-id>]

Options:
  <rl-experiment-dhall>         RL experiment Dhall file.
  --checkpoint <checkpoint-id>  Checkpoint identifier to evaluate.


Examples:
  jitml rl eval experiments/cartpole.dhall --checkpoint latest
      Evaluate an RL policy.
```

### `jitml rl rollout`

```text
jitml rl rollout

Run a fixed-seed rollout.

Runs a deterministic rollout cohort for an RL experiment.

Usage:
  jitml rl rollout <rl-experiment-dhall> [--seed <word64>]

Options:
  <rl-experiment-dhall>  RL experiment Dhall file.
  --seed <word64>        Rollout seed.


Examples:
  jitml rl rollout experiments/cartpole.dhall --seed 42
      Run a fixed-seed rollout.
```

### `jitml verify same-run`

```text
jitml verify same-run

Verify same-run determinism.

Runs the same experiment repeatedly and checks byte-equivalent outputs.

Usage:
  jitml verify same-run --experiment <experiment-dhall> --runs <int>

Options:
  --experiment <experiment-dhall>  Experiment Dhall file.
  --runs <int>                     Number of same-run repetitions.


Examples:
  jitml verify same-run --experiment experiments/mnist.dhall --runs 2
      Verify same-run determinism.
```

### `jitml verify cross-backend`

```text
jitml verify cross-backend

Verify cross-backend parity.

Runs or compares the Sprint 15.1 weighted cross-substrate cohort and checks configured tolerances.

Usage:
  jitml verify cross-backend --experiment <experiment-dhall> [--backends <list>] [--export <path>] [--compare <paths>]

Options:
  --experiment <experiment-dhall>  Experiment Dhall file.
  --backends <list>                Comma-separated substrate list to run locally.
  --export <path>                  Write the local cohort report bundle to this path.
  --compare <paths>                Comma-separated cross-host report bundle paths to compare.


Examples:
  jitml verify cross-backend --experiment experiments/mnist.dhall --backends linux-cpu,linux-cuda
      Verify backend parity.
  jitml verify cross-backend --experiment experiments/mnist.dhall --backends apple-silicon --export /tmp/jitml-apple.json
      Export an ephemeral Apple Silicon cohort report for cross-host comparison.
  jitml verify cross-backend --experiment experiments/mnist.dhall --compare /tmp/jitml-linux.json,/tmp/jitml-apple.json
      Compare ephemeral cross-host cohort reports.
```

### `jitml verify replay`

```text
jitml verify replay

Verify checkpoint replay.

Replays a checkpoint transcript and checks deterministic reproduction.

Usage:
  jitml verify replay --experiment <experiment-dhall> --checkpoint <checkpoint-id>

Options:
  --experiment <experiment-dhall>  Experiment Dhall file.
  --checkpoint <checkpoint-id>     Checkpoint identifier to replay.


Examples:
  jitml verify replay --experiment experiments/mnist.dhall --checkpoint latest
      Replay a checkpoint.
```

### `jitml inspect list`

```text
jitml inspect list

List cached manifests.

Lists cached transcripts and checkpoints.

Usage:
  jitml inspect list



Examples:
  jitml inspect list
      List cached manifests.
```

### `jitml inspect show`

```text
jitml inspect show

Show a manifest.

Shows a cached manifest, optionally with equity details.

Usage:
  jitml inspect show <manifest-sha> [--with-equity]

Options:
  <manifest-sha>  Manifest SHA.
  --with-equity   Include equity details.


Examples:
  jitml inspect show abc123 --with-equity
      Show a manifest with equity details.
```

### `jitml inspect replay`

```text
jitml inspect replay

Replay a manifest.

Replays a cached manifest transcript.

Usage:
  jitml inspect replay [<manifest-sha>] [--manifest-sha <manifest-sha>] [--experiment-hash <experiment-hash>]

Options:
  <manifest-sha>                       Manifest SHA (omit when using --manifest-sha + --experiment-hash).
  --manifest-sha <manifest-sha>        Manifest SHA (alternative to the positional).
  --experiment-hash <experiment-hash>  Override the experiment hash directly (live MinIO lookup).


Examples:
  jitml inspect replay abc123
      Replay a cached manifest from the local store.
  jitml inspect replay --manifest-sha abc123 --experiment-hash live-test-1
      Replay a live-MinIO manifest by SHA.
```

### `jitml inspect trial`

```text
jitml inspect trial

Inspect a trial.

Shows a cached hyperparameter trial.

Usage:
  jitml inspect trial <trial-hash>

Options:
  <trial-hash>  Trial hash.


Examples:
  jitml inspect trial trial123
      Inspect a tuning trial.
```

### `jitml inspect frontier`

```text
jitml inspect frontier

Inspect a tuning frontier.

Shows the Pareto frontier for a sweep.

Usage:
  jitml inspect frontier <sweep-id>

Options:
  <sweep-id>  Sweep identifier.


Examples:
  jitml inspect frontier sweep123
      Inspect a sweep frontier.
```

### `jitml bench train`

```text
jitml bench train

Benchmark training.

Runs the training benchmark harness.

Usage:
  jitml bench train <experiment-dhall>

Options:
  <experiment-dhall>  Experiment Dhall file.


Examples:
  jitml bench train experiments/mnist.dhall
      Benchmark training throughput.
```

### `jitml bench inference`

```text
jitml bench inference

Benchmark inference.

Runs the inference benchmark harness.

Usage:
  jitml bench inference <experiment-dhall> --checkpoint <checkpoint-id>

Options:
  <experiment-dhall>            Experiment Dhall file.
  --checkpoint <checkpoint-id>  Checkpoint identifier to load.


Examples:
  jitml bench inference experiments/mnist.dhall --checkpoint latest
      Benchmark inference throughput.
```

### `jitml bench env`

```text
jitml bench env

Benchmark environment stepping.

Runs the RL environment-step benchmark harness.

Usage:
  jitml bench env <rl-experiment-dhall>

Options:
  <rl-experiment-dhall>  RL experiment Dhall file.


Examples:
  jitml bench env experiments/cartpole.dhall
      Benchmark environment steps.
```

### `jitml inference run`

```text
jitml inference run

Run inference at any point.

Runs inference against latest, best/<metric>, or a manifest SHA checkpoint.

Usage:
  jitml inference run [<experiment-dhall>] [--checkpoint <latest|best/<metric>|manifest-sha>] [--trial <trial-hash>] [--experiment-hash <experiment-hash>]

Options:
  <experiment-dhall>                                Experiment Dhall file.
  --checkpoint <latest|best/<metric>|manifest-sha>  Checkpoint selector.
  --trial <trial-hash>                              Optional tuning trial hash.
  --experiment-hash <experiment-hash>               Override the experiment hash directly (live MinIO lookup).


Examples:
  jitml inference run experiments/mnist.dhall --checkpoint latest
      Run inference using the latest checkpoint.
  jitml inference run --experiment-hash abc123
      Live-MinIO inference run against a known experiment hash.
```

### `jitml test all`

```text
jitml test all

Run all test stanzas.

Runs every test-only Cabal stanza and renders the target-stanza report card.

Usage:
  jitml test all [--dry-run] [--plan-file <path>]

Options:
  --dry-run           Print the plan without applying it.
  --plan-file <path>  Write the plan to a file.


Examples:
  jitml test all --dry-run
      Print the aggregate test plan.
```

### `jitml test jitml-unit`

```text
jitml test jitml-unit

Run jitml-unit.

Runs the jitml-unit Cabal test stanza.

Usage:
  jitml test jitml-unit



Examples:
  jitml test jitml-unit
      Run jitml-unit.
```

### `jitml test jitml-integration`

```text
jitml test jitml-integration

Run jitml-integration.

Runs the jitml-integration Cabal test stanza.

Usage:
  jitml test jitml-integration



Examples:
  jitml test jitml-integration
      Run jitml-integration.
```

### `jitml test jitml-sl-canonicals`

```text
jitml test jitml-sl-canonicals

Run jitml-sl-canonicals.

Runs the jitml-sl-canonicals Cabal test stanza.

Usage:
  jitml test jitml-sl-canonicals



Examples:
  jitml test jitml-sl-canonicals
      Run jitml-sl-canonicals.
```

### `jitml test jitml-rl-canonicals`

```text
jitml test jitml-rl-canonicals

Run jitml-rl-canonicals.

Runs the jitml-rl-canonicals Cabal test stanza.

Usage:
  jitml test jitml-rl-canonicals



Examples:
  jitml test jitml-rl-canonicals
      Run jitml-rl-canonicals.
```

### `jitml test jitml-hyperparameter`

```text
jitml test jitml-hyperparameter

Run jitml-hyperparameter.

Runs the jitml-hyperparameter Cabal test stanza.

Usage:
  jitml test jitml-hyperparameter



Examples:
  jitml test jitml-hyperparameter
      Run jitml-hyperparameter.
```

### `jitml test jitml-cross-backend`

```text
jitml test jitml-cross-backend

Run jitml-cross-backend.

Runs the jitml-cross-backend Cabal test stanza.

Usage:
  jitml test jitml-cross-backend



Examples:
  jitml test jitml-cross-backend
      Run jitml-cross-backend.
```

### `jitml test jitml-daemon-lifecycle`

```text
jitml test jitml-daemon-lifecycle

Run jitml-daemon-lifecycle.

Runs the jitml-daemon-lifecycle Cabal test stanza.

Usage:
  jitml test jitml-daemon-lifecycle



Examples:
  jitml test jitml-daemon-lifecycle
      Run jitml-daemon-lifecycle.
```

### `jitml test jitml-e2e`

```text
jitml test jitml-e2e

Run jitml-e2e.

Runs the jitml-e2e Cabal test stanza.

Usage:
  jitml test jitml-e2e



Examples:
  jitml test jitml-e2e
      Run jitml-e2e.
```

### `jitml lint files`

```text
jitml lint files

Run file hygiene checks.

Run file hygiene checks.

Usage:
  jitml lint files [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint files
      Run file hygiene checks.
```

### `jitml lint docs`

```text
jitml lint docs

Run generated documentation checks.

Run generated documentation checks.

Usage:
  jitml lint docs [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint docs
      Run generated documentation checks.
```

### `jitml lint proto`

```text
jitml lint proto

Run protobuf schema lint checks.

Run protobuf schema lint checks.

Usage:
  jitml lint proto [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint proto
      Run protobuf schema lint checks.
```

### `jitml lint chart`

```text
jitml lint chart

Run Helm chart shape checks.

Run Helm chart shape checks.

Usage:
  jitml lint chart [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint chart
      Run Helm chart shape checks.
```

### `jitml lint haskell`

```text
jitml lint haskell

Run Haskell lint configuration and primitive checks.

Run Haskell lint configuration and primitive checks.

Usage:
  jitml lint haskell [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint haskell
      Run Haskell lint configuration and primitive checks.
```

### `jitml lint purescript`

```text
jitml lint purescript

Run PureScript contract and format checks.

Run PureScript contract and format checks.

Usage:
  jitml lint purescript [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint purescript
      Run PureScript contract and format checks.
```

### `jitml lint all`

```text
jitml lint all

Run every currently implemented lint check.

Runs every current lint target.

Usage:
  jitml lint all [--write]

Options:
  --write  Rewrite files for checks that support it.


Examples:
  jitml lint all --write
      Run every current lint target and apply supported rewrites.
```

### `jitml docs check`

```text
jitml docs check

Check generated docs.

Fails if generated documentation has drifted.

Usage:
  jitml docs check



Examples:
  jitml docs check
      Check generated documentation drift.
```

### `jitml docs generate`

```text
jitml docs generate

Generate docs.

Updates tracked generated documentation.

Usage:
  jitml docs generate



Examples:
  jitml docs generate
      Regenerate tracked documentation.
```

### `jitml check-code`

```text
jitml check-code

Run the code quality gate.

Runs the current in-repo hygiene, generated-doc drift, forbidden-path, chart, and Haskell primitive checks.

Usage:
  jitml check-code



Examples:
  jitml check-code
      Run the aggregate code quality gate.
```

### `jitml build`

```text
jitml build

Build inside the substrate container.

Builds the inner binary and renders the selected substrate JIT compile plan.

Usage:
  jitml build [--substrate <substrate>] [--dry-run] [--plan-file <path>]

Options:
  --substrate <substrate>  apple-silicon, linux-cpu, or linux-cuda.
  --dry-run                Print the plan without applying it.
  --plan-file <path>       Write the plan to a file.


Examples:
  jitml build --substrate linux-cpu
      Build the inner binary.
  jitml build --dry-run --substrate linux-cuda
      Render the CUDA generated-source build plan.
```

### `jitml kubectl`

```text
jitml kubectl

Run kubectl against the jitML kubeconfig.

Passes arguments to kubectl with ./.build/jitml.kubeconfig pre-bound.

Usage:
  jitml kubectl [-- <kubectl-args...>]

Options:
  -- <kubectl-args...>  Arguments passed through to kubectl.


Examples:
  jitml kubectl get pods
      List pods using the jitML kubeconfig.
```

### `jitml internal materialize-substrate`

```text
jitml internal materialize-substrate

Materialize substrate files.

Internal helper that materializes substrate-specific bootstrap files.

Usage:
  jitml internal materialize-substrate [--substrate <substrate>]

Options:
  --substrate <substrate>  Substrate to materialize.


Examples:
  jitml internal materialize-substrate --substrate linux-cpu
      Materialize Linux CPU substrate files.
```

### `jitml internal list-prereqs`

```text
jitml internal list-prereqs

List prerequisite checks.

Prints the prerequisite registry for the current substrate.

Usage:
  jitml internal list-prereqs



Examples:
  jitml internal list-prereqs
      List prerequisite checks.
```

### `jitml internal upload-dataset`

```text
jitml internal upload-dataset

Upload a real dataset blob to MinIO.

Sprint 13.4 — reads a local file, verifies its SHA-256 against the canonical SHA from JitML.SL.Dataset, and uploads it to jitml-datasets/<name>/<split>/<data|labels>.bin via the routed MinIOSubprocess. The canonical SHA is the one returned by `JitML.SL.Dataset.canonicalArtifactSha256For`; mismatches abort the upload. --artifact selects images (data.bin) or labels (labels.bin).

Usage:
  jitml internal upload-dataset [--name <name>] [--split <split>] [--artifact <artifact>] [--path <path>] [--dry-run] [--plan-file <path>]

Options:
  --name <name>          Dataset name (e.g., MNIST).
  --split <split>        Dataset split (train/validation/test).
  --artifact <artifact>  Artifact kind (images/labels); defaults to images.
  --path <path>          Local file path to upload.
  --dry-run              Print the plan without applying it.
  --plan-file <path>     Write the plan to a file.


Examples:
  jitml internal upload-dataset --name MNIST --split train --path /tmp/train-images-idx3-ubyte.gz
      Upload the canonical MNIST training images to the live MinIO bucket.
  jitml internal upload-dataset --name MNIST --split train --artifact labels --path /tmp/train-labels-idx1-ubyte.gz
      Upload the canonical MNIST training labels alongside the images.
```

### `jitml internal gc`

```text
jitml internal gc

Apply checkpoint retention.

Reconciles the experiment retention policy against the checkpoint store.

Usage:
  jitml internal gc <experiment-hash> [--dry-run] [--plan-file <path>]

Options:
  <experiment-hash>   Experiment hash.
  --dry-run           Print the plan without applying it.
  --plan-file <path>  Write the plan to a file.


Examples:
  jitml internal gc exp123
      Apply retention to an experiment.
```

### `jitml internal cache stat`

```text
jitml internal cache stat

Print cache stats.

Prints JIT cache statistics.

Usage:
  jitml internal cache stat



Examples:
  jitml internal cache stat
      Print JIT cache stats.
```

### `jitml internal cache list`

```text
jitml internal cache list

List cache entries.

Lists JIT cache entries.

Usage:
  jitml internal cache list



Examples:
  jitml internal cache list
      List cache entries.
```

### `jitml internal cache evict`

```text
jitml internal cache evict

Evict a cache entry.

Evicts a JIT cache entry by hash.

Usage:
  jitml internal cache evict <hash>

Options:
  <hash>  JIT cache hash.


Examples:
  jitml internal cache evict abc123
      Evict one cache entry.
```

### `jitml commands`

```text
jitml commands

Print the command registry.

Prints a flat list, tree rendering, or JSON schema for the command registry.

Usage:
  jitml commands [--tree] [--json]

Options:
  --tree  Render the command tree.
  --json  Render the JSON command schema.


Examples:
  jitml commands --tree
      Print the command tree.
```

### `jitml help`

```text
jitml help

Print focused command help.

Prints the same help text as passing --help to a subcommand.

Usage:
  jitml help [-- <subcommand...>]

Options:
  -- <subcommand...>  Subcommand path to show help for.


Examples:
  jitml help cluster up
      Print help for cluster up.
```
<!-- jitml:cli-commands.help-blocks:end -->

## Cross-References

- [../../README.md](../../README.md)
- [../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md](../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md)
- [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md)
