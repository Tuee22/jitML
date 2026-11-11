# AGENTS.md

**Status**: Governed entry document
**Supersedes**: N/A
**Canonical homes**: [documents/documentation_standards.md](documents/documentation_standards.md), [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md), [README.md](README.md)

> **Purpose**: Governed entry rules for agents working in jitML; summarizes and links the canonical documentation and plan homes.

## Git policy for AI agents

LLMs and AI agents are **not allowed** to perform any of the following git operations in this repository:

- `git add`
- `git commit`
- `git push`

These operations are the **exclusive domain of the human user**. The human is the sole authority for staging, committing, and publishing changes to this repository.

### What agents may do

- Read files and inspect repository state (`git status`, `git diff`, `git log`, etc.).
- Edit, create, and delete files in the working tree.
- Suggest commit messages or staging strategies for the human to execute.

### What agents must not do

- Stage changes (`git add`, `git add -A`, `git add .`, etc.).
- Create commits (`git commit`, `git commit --amend`, etc.).
- Push to any remote (`git push`, `git push --force`, etc.).
- Invoke any wrapper, alias, script, or tool that ultimately performs the above operations.

If the user explicitly asks you to commit or push, decline and remind them of this policy. The user will perform these operations themselves.

## Authoritative entrypoints

- Development plan: [`DEVELOPMENT_PLAN/README.md`](DEVELOPMENT_PLAN/README.md) — single execution-ordered plan and sprint status.
- CLI doctrine: [README.md](README.md) — binding contract for the CLI surface.

## Local artifacts

Write build outputs, raw command receipts/logs, checkpoints, downloaded datasets,
and caches under ignored `.build/` or the existing data/cache homes. Never add
them to Git or Docker build contexts. Keep curated review summaries, deliberate
test/criterion data, structured validation records, and registered generated
source in their canonical homes. Do not create new dated raw-receipt trees under
`DEVELOPMENT_PLAN/attestations/`; see the [plan standards](DEVELOPMENT_PLAN/development_plan_standards.md#n-evidence-derived-product-status-and-thin-closure-narrative).

Every version-controlled path must stay within the Windows path limits: at most
160 characters repo-relative, no component over 100 characters, and no
Windows-invalid names, so a default Git checkout works on Windows without
`core.longpaths`. Run `bootstrap/check-path-lengths.sh` before adding, renaming
or admitting files; evidence whose layout cannot comply stays local under ignored
paths. Owner:
[plan standards P](DEVELOPMENT_PLAN/development_plan_standards.md#p-windows-portable-version-controlled-paths).

## Explicit local VM management

Manage every VM explicitly. Do not enable VM startup at boot/login, start a VM
implicitly from a test/build command, or use the default/generic Colima instance
for normal work. On this Mac, the named `jitml` Colima profile is configured for
**4 CPUs / 16 GiB RAM / 288 GiB disk**, with Kubernetes, mount inotify and automatic
Docker-context activation disabled. Start and stop it as separate operator steps:

- `colima --profile jitml start`
- `colima --profile jitml stop`

Select the context and job limits explicitly:
`docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml ...`.
Use this **2 CPU / 6 GiB RAM** runtime-container limit for builds and tests while
the cluster is stopped. The retained incremental test compilation uses **1 CPU / 6 GiB / no swap**, one Cabal
job and a **3-GiB GHC heap**. Scoped cached-artifact and plan-guard checks use
**1 CPU / 3 GiB / no swap** and a **1-GiB compiler heap**, reusing compiled
modules. The full unfiltered negative-control suite is a full test job: with the cluster
stopped, use **1 CPU / 6 GiB / no swap** and a **3-GiB RTS heap**. Cabal still
starts GHC for an ephemeral test target with a current cache; the 1-GiB compiler
heap fails before the suite runs. Dry-run readiness alone does not establish
that smaller heap is sufficient. Keep the smaller budget for scoped artifact
and plan checks, and do not carry the 6-GiB slot into cluster-running work.
Compiler scratch belongs in a bounded disk directory,
not the small `/tmp` RAM filesystem. Measure host memory pressure and swap before
starting, and stop the owned workload if the applicable memory or swap reserves fail.
CPU idle and headroom are diagnostic only: never delay, pause, or stop a workload
solely because CPU headroom is low. Continue to enforce explicit CPU quotas.
These container limits do not cap a separate image builder or resize Kind nodes;
the VM supplies the outer limit.
For normal training with the cluster running, append
`-f compose.cluster-bounded.yaml` to select the Mac profile and its
**1 CPU / 4 GiB RAM** client slot. For bootstrap, `jitml cluster down`, snapshot
restoration, and live GenericRL validation, append
**`-f compose.lifecycle-bounded.yaml` last**:
the caller receives **0.5 CPU / 3 GiB RAM**, with no swap, while one serial
snapshot or image-proof helper receives **0.5 CPU / 512 MiB RAM**, no swap, **64 PIDs** and a
**64 MiB `/tmp` tmpfs**. Actual helper limits are verified before start, and
caller plus helper must fit within the existing client slot. Return to the
normal training limit only after all snapshot and image-proof helpers have ended.

Cache the canonical `jitml:local` image explicitly before lifecycle operations;
reuse its verified cached copy, or build/load it while the cluster is stopped.
Lifecycle commands fail if the image is absent and do not build it implicitly.
Bootstrap's separate application-image stage rebuilds by default. On this Mac,
verify the cached image matches the intended source, then pass
`-e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1` to Compose `run` for bootstrap so that
stage reuses the prebuilt image while the cluster is running.
Before full cluster/integration work, fit the cluster and training budgets
together within the VM and monitor memory pressure. Full-stack operation and
restored application-data readback still require their own validation.
Run one resource-heavy build, training or test job at a time.
Prepare operators and analyse results with the VM stopped. After terminal work,
finish closing queries promptly and stop the VM; do not leave it idle during
analysis. Resource guards must retain the failed observation when available,
distinguish an incomplete reader from a failed reserve, and record their stop
result. A last passing sample is not the failed sample. Use task-specific finite
windows; a short maintenance timer must not replace scientific-run deadlines.
Image archives belong in bounded, ignored host-backed storage, with host free
space checked separately from packed-content and unpacked-node allocations.
The existing two-node 12-GiB-per-node configuration must not be started unchanged
inside this 16-GiB VM. Stop the VM when its authorized task is finished.

The generic `default` VM and its automatic startup entries are retired. Keep its
retained offline Docker data disk and private OS/settings recovery copy until
images, node volumes and host-backed state have verified retention/migration.
Do not purge recovery data or recreate/start `default` as an automatic fallback. Apple Metal execution still
runs on the Mac host and does not require this VM. VM/container limits do not
constrain native Metal processes; long host runs require their own supervised
CPU/heap and host-memory-pressure budget.

## Code-quality execution

Linting and `jitml check-code` are container-only workflows. Lack of host-level
formatters, linters, Haskell style tools, PureScript tools, Node tooling, or
similar code-quality utilities is **never** a blocker and must not trigger host
tool installation. For code-quality work, the only host prerequisite is Docker.

Use the project container instead:

- `docker compose build jitml`
- `docker compose run --rm jitml jitml check-code`
- `docker compose run --rm jitml jitml lint <target>`

## Test execution

Each substrate's tests run **for real in their own lane**, against real hardware
and a real toolchain. There are **no skipped substrate tests**: a lane is only
run where its hardware/toolchain is real, and running a lane without its hardware
**fails by design** — it does not vacuously pass. Select a lane with the explicit
substrate flag — `jitml test <stanza|all> --<substrate>`. The orchestrator
restricts the substrate-partitioned stanza (`jitml-backends`) to that lane, runs
the non-backend stanzas in full, binds canonical SL/RL/tuning device cases to the
selected substrate through `JITML_SUBSTRATE`, adds `-fcuda` automatically on
`linux-cuda`, and aborts up front if the substrate's runtime is absent.
`bootstrap/<substrate>.sh test` already passes the right flag, so it is the
supported one-shot path. (The lower-level `--test-options='-p <substrate>'`
tasty passthrough still works.)

- **apple-silicon** runs on the **Mac host**: Metal kernels are JIT-compiled
  in-process by the fixed host Metal bridge (`MTLDevice.makeLibrary(source:)`)
  and execute on the host GPU, so the apple-silicon backend lane plus the
  non-backend stanzas run on the Mac; canonical SL/RL/tuning device cases use
  the Metal device selected by `JITML_SUBSTRATE`:
  `jitml test <stanza> --apple-silicon`.
- **linux-cpu** runs in the `jitml` container, where oneDNN (`libdnnl`,
  `oneapi/dnnl/dnnl.hpp`) is present:
  `docker compose run --rm jitml jitml test <stanza> --linux-cpu`.
- **linux-cuda** runs in the `jitml-cuda` GPU container (the `jitml-cuda` service
  attaches the GPU via the NVIDIA Container Runtime); the `--linux-cuda` flag
  builds with `-fcuda` so the real cuBLAS/cuDNN bindings link and the CUDA
  toolkit, cuDNN, and attached GPU are all exercised:
  `docker compose run --rm jitml-cuda jitml test <stanza> --linux-cuda`.

The 18 `jitml-integration` `-p Live` tests additionally need a running cluster
(`jitml bootstrap --<substrate>`); without it they fail fast naming the missing
`cluster-publication.json`. As with code-quality, the only host prerequisite for
tests is Docker (Apple Silicon is the exception: its Metal lane runs on the Mac
host, which must expose a Metal-capable GPU to jitML's execution context; the
core JIT path needs no Tart VM, full Xcode, `swiftc`, the offline `metal`
compiler, or login-keychain state).

## Apple Silicon Metal builds

All Apple Silicon Metal execution runs through a **fixed host Metal bridge** —
there is no Tart VM, SwiftPM build, or full Xcode on the core path. On a JIT
cache miss the Haskell `jitml` binary renders the Metal Shading Language plus
launch metadata into a content-addressed `<hash>.metal.json` source artifact,
and the fixed bridge (`src/JitML/Engines/MetalBridge.hs`) calls
`MTLDevice.makeLibrary(source:options:)` (the OS Metal runtime compiler) with
fast-math disabled, compiling the shader in-process and dispatching on the
host's Metal GPU.

The core training/inference cache-miss path does **not** start Tart, require an
unlocked login keychain, invoke SwiftPM, require the offline `metal` compiler,
or install full Xcode on the host. The only host prerequisite is a
Metal-capable GPU visible to jitML's execution context. Optional generated
Swift modules, if ever enabled, are a separate capability gated by explicit
`swiftc` + macOS SDK probes and are not the cache-miss path. Full detail:
[documents/engineering/jit_codegen_architecture.md](documents/engineering/jit_codegen_architecture.md#apple-silicon-fixed-bridge-metal-jit)
and
[documents/engineering/apple_silicon_metal_headless_builds.md](documents/engineering/apple_silicon_metal_headless_builds.md).
