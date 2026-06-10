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
restricts the substrate-partitioned stanzas (`jitml-backends`) to that lane, runs
the pure-logic stanzas in full, adds `-fcuda` automatically on `linux-cuda`, and
aborts up front if the substrate's runtime is absent. `bootstrap/<substrate>.sh
test` already passes the right flag, so it is the supported one-shot path. (The
lower-level `--test-options='-p <substrate>'` tasty passthrough still works.)

- **apple-silicon** runs on the **Mac host**: Metal kernels build in the
  `jitml`-managed Tart VM and execute on the host GPU, so the
  apple-silicon cases plus the six pure-logic stanzas (`jitml-unit`,
  `jitml-sl-canonicals`, `jitml-rl-canonicals`, `jitml-hyperparameter`,
  `jitml-daemon-lifecycle`, `jitml-e2e`) run on the Mac:
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
host and additionally needs the `jitml`-managed Tart build VM, which the binary
provisions — `brew install`ing Tart if absent).

## Apple Silicon Swift / Metal builds

All Apple Silicon Swift/Metal builds run inside a `jitml`-managed **Tart VM**. The
`jitml` binary owns the VM lifecycle: it `brew install`s Tart if it is absent,
creates/starts/stops/deletes the build VM, and assigns its CPU/memory/storage from
the host Dhall config (the limits are Dhall-configurable). The VM is a standard
macOS image carrying the full Apple toolchain (`swiftc`, Xcode, `metal`).

Full Xcode is **never** installed on the **host** — the host carries no Swift/Metal
toolchain at all; that toolchain lives only in the VM. On a JIT cache miss the
daemon ensures the VM is up, builds the generated Swift glue dylib with the VM's
`swift build`, and copies `libJitMLMetal.dylib` out of the VM to the host. Execution
is host-native: the host `dlopen`s the dylib and the generated launcher compiles the
embedded Metal Shading Language at load, in-process, via
`MTLDevice.makeLibrary(source:options:)` (the OS Metal runtime compiler) with
fast-math off, dispatching on the host's Metal GPU. Full detail:
[documents/engineering/jit_codegen_architecture.md](documents/engineering/jit_codegen_architecture.md#apple-silicon-tart-vm-build-jit).
