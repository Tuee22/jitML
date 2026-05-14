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
- CLI doctrine: [`HASKELL_CLI_TOOL.md`](HASKELL_CLI_TOOL.md) — binding contract for the CLI surface.
