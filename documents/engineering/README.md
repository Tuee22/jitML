# Engineering Docs

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: ../documentation_standards.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/development_plan_standards.md
**Generated sections**: none

> **Purpose**: Index of the project-specific engineering doctrine for jitML.

## Index

The engineering docs split into four **doctrine-overlap** docs (which defer to
[../../README.md](../../README.md) for the patterns it owns
and retain only project-specific elaborations) and twelve **project-specific**
docs (which own their content outright with no doctrine overlap).

### Doctrine-Overlap

| Doc | Defers to doctrine sections | Project-specific surface |
|-----|------------------------------|--------------------------|
| [cli_command_surface.md](cli_command_surface.md) | Command Topology; CommandSpec; Progressive Introspection; Output Rules; Standard Flag Families | jitML's command tree |
| [code_quality.md](code_quality.md) | Lint, Format, and Code-Quality Stack; Forbidden Surfaces; Generated Artifacts | Container-exclusive Haskell style/code-quality gate; chart-shape lint; route-registry drift; no-`allow-newer` plain-Hackage dependency model |
| [unit_testing_policy.md](unit_testing_policy.md) | Testing Doctrine; Standard Testing Stack; Test Categories; Test Organization | Eight jitML test stanzas including local SL/RL/HPO/backends Integration extensions, Linux CPU generated-kernel execution, current `jitml-e2e` scaffold/live-plan surface, and the reopened no-caveat Playwright product matrix |
| [haskell_code_guide.md](haskell_code_guide.md) | GADT-Indexed State Machines; Subprocesses as Typed Values; Plan / Apply; Prerequisites as Typed Effects; Application Environment; Error Handling; Capability Classes; Retry Policy; Long-Running Daemons; At-Least-Once Event Processing; Reconcilers | jitML's lifecycle ADTs and capability classes; the 17-variant `AppError` enumeration |

### Project-Specific

| Doc | Owns |
|-----|------|
| [determinism_contract.md](determinism_contract.md) | Per-substrate floating-point semantics, RNG split, per-experiment seed derivation, JIT cache content-addressing, bit-determinism envelope, within-substrate determinism contract (no cross-substrate guarantee) |
| [cluster_topology.md](cluster_topology.md) | Kind cluster shapes per substrate, Helm umbrella chart, Helm-values ownership, storage discipline, Envoy Gateway, route registry, no-kubeconfig-pollution invariant |
| [daemon_architecture.md](daemon_architecture.md) | `jitml service` lifecycle, BootConfig / LiveConfig, hot reload, healthz/readyz/metrics, structured logging, recoverable vs fatal errors, at-least-once Pulsar consumer |
| [durable_state_dsl.md](durable_state_dsl.md) | The closed self-validating `jitml.dhall` durable-state config: the store registry (MinIO buckets + Pulsar topics), typed retention, the closed `StoreId` selector + `contractOK` assert, `jitml project init`, and the runtime projections (`bucketNames`, topology anti-drift, registry-sourced GC retention) |
| [jit_codegen_architecture.md](jit_codegen_architecture.md) | Content-addressed cache, per-substrate compilers (Metal/oneDNN/CUDA), local kernel handle/envelope surface, Linux CPU libdnnl-linked FFI and `HasEngine` execution, guarded CUDA FFI runner boundary, Apple Silicon fixed-bridge Metal JIT, hardware auto-tuning, and live Metal/CUDA validation boundary; on Apple Silicon jitML writes `.metal.json` source metadata, calls the fixed host bridge, and the bridge JIT-compiles MSL via `MTLDevice.makeLibrary(source:)` before executing on the host GPU |
| [apple_silicon_metal_headless_builds.md](apple_silicon_metal_headless_builds.md) | True-headless Apple Silicon Metal JIT architecture: fixed host bridge, runtime MSL compilation via `MTLDevice.makeLibrary(source:options:)`, host-resident Metal workload placement, source/metadata cache artifacts, optional Swift JIT lane, and rationale for rejecting Tart, full Xcode, offline `.metallib`, and per-cache-miss Swift builds |
| [numerical_core.md](numerical_core.md) | Current local numerical catalog, Dhall mirrors, and cross-type audit |
| [training_metrics_and_splits.md](training_metrics_and_splits.md) | SL train/test/validation split discipline (validation drives selection, test held-out) + SL/RL convergence-and-performance metric definitions (real CE/MSE loss, measured-median, throughput, AlphaZero arena win-rate); the no-hardcoded-weights / no-faked-metrics invariants |
| [training_workloads.md](training_workloads.md) | Current local SL/RL/AlphaZero/tuning catalogs, RL Dhall mirror, copyright-free `KeyDoorGrid-v0` default visual RL demo coverage, optional `atari-subset` ROM policy with generated/external ALE adapter boundary, statistical convergence-assertion methodology, and the typed-failure closure for RL device updates and tuning resume decode failures |
| [checkpoint_format.md](checkpoint_format.md) | Current local checkpoint key/CAS/store/inference helpers plus target split-blob format, retention reconciler, full-family no-caveat checkpoint/inference metadata, and typed local object-key validation |
| [purescript_frontend.md](purescript_frontend.md) | Current PureScript shell, generated contracts, panel/demo-route metadata, `spec-node` smoke-test runner, demo shim, Playwright scaffold, typed live-plan step, and reopened no-caveat browser/animation/replay/Playwright product matrix |
| [pulsar_ml_workflow.md](pulsar_ml_workflow.md) | The cross-project contract shared verbatim with the `infernix` sister project: the three-role split (Engine / Coordinator / Webapp), the derived topic algebra, the `Work*` envelope family covering training and inference, the artifact + `.ready` readiness contract, the websocket snapshot/patch surface, the coordination primitives, and the forward-only-DAG + single-accelerator-per-phase phasing rules |

Each doc carries the standard `**Status**` / `**Supersedes**` / `**Referenced
by**` / `**Generated sections**:` / `> **Purpose**:` block per
[../documentation_standards.md → Required Header
Metadata](../documentation_standards.md#3-required-header-metadata).
