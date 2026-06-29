# AGENTS.md

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
