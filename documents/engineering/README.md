# Engineering Docs

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../documentation_standards.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/development_plan_standards.md
**Generated sections**: none

> **Purpose**: Index of the project-specific engineering doctrine for jitML.

## Index

The engineering docs split into four **doctrine-overlap** docs (which defer to
[../../HASKELL_CLI_TOOL.md](../../HASKELL_CLI_TOOL.md) for the patterns it owns
and retain only project-specific elaborations) and eight **project-specific**
docs (which own their content outright with no doctrine overlap).

### Doctrine-Overlap

| Doc | Defers to doctrine sections | Project-specific surface |
|-----|------------------------------|--------------------------|
| [cli_command_surface.md](cli_command_surface.md) | Command Topology; CommandSpec; Progressive Introspection; Output Rules; Standard Flag Families | jitML's command tree |
| [code_quality.md](code_quality.md) | Lint, Format, and Code-Quality Stack; Forbidden Surfaces; Generated Artifacts | Chart-shape lint; route-registry drift |
| [unit_testing_policy.md](unit_testing_policy.md) | Testing Doctrine; Standard Testing Stack; Test Categories; Test Organization | Ten jitML stanzas including project-specific SL/RL/HPO/cross-backend Integration extensions, split haskell/purescript style stanzas, and Pulumi-orchestrated `jitml-e2e` |
| [haskell_code_guide.md](haskell_code_guide.md) | GADT-Indexed State Machines; Subprocesses as Typed Values; Plan / Apply; Prerequisites as Typed Effects; Application Environment; Error Handling; Capability Classes; Retry Policy; Long-Running Daemons; At-Least-Once Event Processing; Reconcilers | jitML's lifecycle ADTs and capability classes; the 17-variant `AppError` enumeration |

### Project-Specific

| Doc | Owns |
|-----|------|
| [determinism_contract.md](determinism_contract.md) | Per-substrate floating-point semantics, RNG split, per-experiment seed derivation, JIT cache content-addressing, bit-determinism envelope, cross-substrate tolerance methodology |
| [cluster_topology.md](cluster_topology.md) | Kind cluster shapes per substrate, Helm umbrella chart, storage discipline, Envoy Gateway, route registry, no-kubeconfig-pollution invariant |
| [daemon_architecture.md](daemon_architecture.md) | `jitml service` lifecycle, BootConfig / LiveConfig, hot reload, healthz/readyz/metrics, structured logging, recoverable vs fatal errors, at-least-once Pulsar consumer |
| [jit_codegen_architecture.md](jit_codegen_architecture.md) | Content-addressed cache, per-substrate compilers (Metal/oneDNN/CUDA), Apple Silicon hybrid pattern, hardware auto-tuning, FFI boundary |
| [numerical_core.md](numerical_core.md) | Layer catalog, activations (real+complex), spectral ops, optimizers, schedulers, losses, Dhall types |
| [training_workloads.md](training_workloads.md) | SL training loops, RL framework primitives, RL algorithm catalog, AlphaZero / MCTS state, hyperparameter tuning |
| [checkpoint_format.md](checkpoint_format.md) | Split-blob layout, `.jmw1` wire format, manifest, inference-only read path, retention reconciler |
| [purescript_frontend.md](purescript_frontend.md) | `src/JitML/Web/Contracts.hs` as source for `purescript-bridge`, Halogen panels, REST surfaces, Playwright E2E, demo HTTP server |

Each doc carries the standard `**Status**` / `**Supersedes**` / `**Referenced
by**` / `**Generated sections**:` / `> **Purpose**:` block per
[../documentation_standards.md → Required Header
Metadata](../documentation_standards.md#3-required-header-metadata).
