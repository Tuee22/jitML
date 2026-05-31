# CLAUDE.md

## Git policy

LLMs (including Claude) are **not allowed** to perform any of the following git operations in this repository:

- `git add`
- `git commit`
- `git push`

These operations are the **exclusive domain of the human user**. The human is the sole authority for staging, committing, and publishing changes to this repository.

### What you may do

- Read files and inspect repository state (`git status`, `git diff`, `git log`, etc.).
- Edit, create, and delete files in the working tree.
- Suggest commit messages or staging strategies for the human to execute.

### What you must not do

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

## Apple Silicon Swift / Metal builds

Full Xcode is **never** installed on the host. Xcode's first-launch and license
dialogs raise interactive UI prompts that break the headless workflow this
repository requires, so installing host Xcode is forbidden. Only the Xcode
**Command Line Tools** (`swiftc`) and the OS Metal framework are used.

Apple Silicon Metal kernels are JIT-compiled **headless on the host** — no Tart
VM. The host builds the small generated Swift glue dylib with the
CommandLineTools `swift build`, and the generated launcher compiles the embedded
Metal Shading Language **at runtime, in-process**, via
`MTLDevice.makeLibrary(source:options:)` (Metal's OS runtime compiler) with
fast-math off. No offline `metal` / `metallib` CLI compiler (Xcode-only) is ever
invoked. This runtime-compile path is the only way jitML JITs on Apple Silicon
and needs neither Xcode nor a VM. Full detail:
[documents/engineering/jit_codegen_architecture.md](documents/engineering/jit_codegen_architecture.md#apple-silicon-headless-jit).
