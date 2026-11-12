# Phase 3: Governed-Document Metadata Enforcement

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Governed-Document Metadata Enforcement. Originally migrated from legacy Sprint 0.3 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `3.2` → [291](phase-291-governed-authority.md), [292](phase-292-generated-output-portability.md), [318](phase-318-cuda-runtime-engineering.md), [319](phase-319-apple-runtime-engineering.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** for the expanded validation foundation in Sprint `3.2`.
The earlier Sprint `3.1` record below is retained on its original source and
scope; it does not validate this target or a current hardware lane. The execution
order and transition authority are [the validation-foundation refactor](README.md#validation-foundation-refactor).

The foundation catalogue, runner and hardware controls remain unimplemented.
Partial documentation-check and generated-path controls are recorded below;
they do not close this sprint. Sprint `221.2` owns reconciliation of the
existing status checker with the documented dependency and evidence targets.

## Sprint 3.2: Canonical doctrine ownership and executable documentation governance [⏸️ Blocked]

**Status**: Blocked
**Implementation**: Target changes to `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Docs.hs`, `src/JitML/Product/PlanDoc.hs`.
**Blocked by**: Sprint `221.2`.
**Docs to update**: `../documents/engineering/execution_resources.md`, `../documents/engineering/validation_execution.md`, `../documents/documentation_standards.md`, `../documents/engineering/code_quality.md`, `README.md`, `system-components.md`, `legacy-tracking-for-deletion.md`.

### Objective

The documentation checker enforces one canonical owner per durable contract, current-versus-target boundaries, valid links and anchors, and evidence-backed phase state. Root authority migration remains explicit work; the partial root diary cleanup below does not transfer a binding contract.

The target contracts are [execution resources](../documents/engineering/execution_resources.md)
and [validation execution](../documents/engineering/validation_execution.md).
Their acceptance requirements below are planned work, not implemented behavior.

### Deliverables

- Reconcile the plan and documentation standards through an authority-transfer inventory: contract, old root anchor, canonical topic owner, consumer changes, replacement link, and acceptance check. Keep the existing root CLI contract binding until its transfer is implemented and verified.
- Check relative link targets and section anchors, required metadata, generated-region ownership, and portable paths. A missing shared resource protocol must fail; an index cannot mint an implemented contract.
- Migrate root incident diaries and duplicate architecture to their canonical homes only in a subsequent change authorized to edit `README.md`, `AGENTS.md`, and `CLAUDE.md`; retain useful curated history and temporary redirect anchors with deletion owners.
- Reconcile actual derived sprint status and the explicit dependency graph after `221.2`; no Markdown declaration is proof that the new operational contracts exist.
- Inventory generated build, cache, data, download, test and runtime path
  producers and their roots, including ignored outputs and third-party tools.
  Classify Windows-host and host-mounted paths separately from Linux-only VM or
  container filesystems. Define supported Windows root budgets and ownership for
  generated layouts; shorten owned paths, configure external tools where possible,
  and provide actionable failure or explicit support boundaries where not.
  Implement a repeatable generated-output guard independent of Git ignore rules;
  retain the tracked-path guard's separate checkout scope.

### Authority-transfer inventory (in progress)

This inventory identifies candidate transfers; it does not transfer authority.
The root CLI contract remains binding, and the execution documents distinguish
implemented behavior from targets. References and consumers must be reconciled
before any old anchor is retired. This first inventory is incomplete: the
remaining root sections, historical incident diaries, generated regions and
individual inbound references still need enumeration.

| Contract and current root entry | Intended topic owner | Consumer changes and acceptance |
|---|---|---|
| [Toolchain pinning](../README.md#toolchain-pinning) and [prerequisites as typed effects](../README.md#prerequisites-as-typed-effects) | Candidate split: [JIT code generation](../documents/engineering/jit_codegen_architecture.md) for substrate toolchains and [Haskell code guide](../documents/engineering/haskell_code_guide.md) for prerequisite effects; a single pin registry is not yet identified | Inventory actual Docker, Cabal, bootstrap and prerequisite-node pins, distinguish installed package versions from fixed versions, and reconcile the consumers and negative prerequisite controls before moving any binding statement. |
| [Substrates and runtime modes](../README.md#substrates-and-runtime-modes), [substrate-affinity phasing](../README.md#substrate-affinity-phasing) and [Apple Silicon hybrid pattern](../README.md#apple-silicon-hybrid-pattern) | Candidate split: [cluster topology](../documents/engineering/cluster_topology.md), [determinism contract](../documents/engineering/determinism_contract.md), and [plan standards](development_plan_standards.md) | Reconcile current residency and determinism behavior, target cluster shapes and the phase-order rule against actual lane selectors and tests. Preserve the root rule until every cross-reference and conflicting dependency has been resolved. |
| [Bootstrap scripts](../README.md#bootstrap-scripts) and [built-artifact and JIT-cache discipline](../README.md#built-artifact-and-jit-cache-discipline) | Candidate split: [cluster topology](../documents/engineering/cluster_topology.md), [JIT code generation](../documents/engineering/jit_codegen_architecture.md), and [execution resources](../documents/engineering/execution_resources.md) | Trace script entrypoints, image/cache identity, lifecycle preservation and destructive reset semantics to their implementations and owned controls; keep operator-specific resource limits authoritative in the root entry. |
| [CLI command topology](../README.md#cli-command-topology-typed), flags and generated reference | [CLI command surface](../documents/engineering/cli_command_surface.md) | Move the binding contract only when command parser/help, generated reference, root links and checks agree; preserve old anchors until inbound references migrate. |
| [Typed run contracts](../README.md#typed-run-contracts) | [Run contract](../documents/engineering/run_contract.md) | Reconcile root descriptions, plan and code consumers against the typed contract and its current/target labels; verify all replacement links and contract tests. |
| [Container builds](../README.md#outer-container-linux-builds) and [VM management](../AGENTS.md#explicit-local-vm-management) | [Execution resources](../documents/engineering/execution_resources.md), with operator-specific limits retained in the governed entry until transferred | Reconcile Compose/build callers, helper admission and root operator instructions; verify effective limits and linked replacement instructions before retiring an entry. |
| [Test-suite stanzas](../README.md#test-suite-stanzas) and [test execution](../AGENTS.md#test-execution) | [Unit testing policy](../documents/engineering/unit_testing_policy.md) and [validation execution](../documents/engineering/validation_execution.md) | Reconcile CLI selectors, real substrate lanes, test inventories and target campaign claims; verify scoped commands and hardware requirements. |
| [Code-quality execution](../AGENTS.md#code-quality-execution) and [lint matrix](../README.md#lint-matrix) | [Code quality](../documents/engineering/code_quality.md) | Align the root entries, container gate and actual checker registration; exercise a passing case and the owned negative controls. |
| [Cluster topology](../README.md#cluster-topology-and-kind) and storage/network sections | [Cluster topology](../documents/engineering/cluster_topology.md) | Reconcile manifests, generated sections and links; verify generated-region ownership and actual topology checks. |
| [MinIO object store](../README.md#minio-object-store), [TensorBoard event storage](../README.md#tensorboard-event-storage) and [PostgreSQL](../README.md#postgresql) | Candidate split: [checkpoint format](../documents/engineering/checkpoint_format.md), [cluster topology](../documents/engineering/cluster_topology.md), and [training metrics](../documents/engineering/training_metrics_and_splits.md) | Inventory object layout, event encoding, retention, sidecar and no-Postgres consumers separately; reconcile generated chart and registry controls and live-versus-target behavior before replacing root text. |
| [TensorBoard, Prometheus and Grafana](../README.md#tensorboard-prometheus-grafana-as-first-class) | No single confirmed observability owner; evaluate [cluster topology](../documents/engineering/cluster_topology.md) and [training metrics](../documents/engineering/training_metrics_and_splits.md) | Trace typed scrape and dashboard renderers, generated fixtures, routes and event consumers. Identify a durable owner and verify renderer drift controls before any transfer. |
| [JIT compilation](../README.md#jit-compilation-architecture) and [Apple Metal builds](../AGENTS.md#apple-silicon-metal-builds) | [JIT code generation](../documents/engineering/jit_codegen_architecture.md) and [Apple Metal builds](../documents/engineering/apple_silicon_metal_headless_builds.md) | Reconcile source, host-bridge prerequisites and substrate consumers; verify links and real lane evidence without recasting historical results. |
| [Checkpointing](../README.md#checkpointing) and [checkpoint object layout](../README.md#checkpoint-object-layout) | [Checkpoint format](../documents/engineering/checkpoint_format.md) | Reconcile storage, inference and generated consumers with current versus target format; verify format, readback and links before removing root detail. |
| [Product completion](../README.md#product-completion-contract) and [current status](../README.md#current-status) | [Product completion contract](../documents/engineering/product_completion_contract.md) for durable contract; [plan closure status](README.md#closure-status) for mutable status | Separate criteria from dated evidence, preserve useful history, and check every status claim against the evidence-derived projection. |
| [Numerical core](../README.md#numerical-core), catalogs and Dhall example | [Numerical core](../documents/engineering/numerical_core.md) | Reconcile registered generated regions, Dhall mirrors and code consumers; verify catalog parity and every replacement anchor before removing root material. |
| [Hyperparameter tuning](../README.md#hyperparameter-tuning-first-class), [RL framework](../README.md#rl-framework-primitives), [RL catalog](../README.md#rl-algorithm-catalog) and [AlphaZero](../README.md#alphazero-style-self-play-and-persistent-mcts-state) | [Training workloads](../documents/engineering/training_workloads.md) and [run contract](../documents/engineering/run_contract.md) | Reconcile current catalog and target execution claims against their code, generated regions, plan owners and test selectors; preserve worked examples and link migrations. |
| [Supervised problems](../README.md#canonical-supervised-learning-problems), [RL environments](../README.md#canonical-reinforcement-learning-environments) and [RL convergence](../README.md#convergence-and-determinism-checks-for-rl) | [Training workloads](../documents/engineering/training_workloads.md) and [training metrics and splits](../documents/engineering/training_metrics_and_splits.md) | Trace dataset policies, split and criterion consumers to their current owners; independently check criterion provenance and avoid presenting historical results as current evidence. |
| Selected-device evaluation and native learning summary in [root current status](../README.md#current-status) | [Training metrics current status](../documents/engineering/training_metrics_and_splits.md#current-status) and its [native RL qualification target](../documents/engineering/training_metrics_and_splits.md#target-native-rl-learning-qualification) | The root now summarizes and links the existing detailed contracts. Selected Linux fixture controls passed **12 / 12** on-policy boundary cases and **27 / 27** arena comparison cases; they are not live training or qualification. The two changed/cited documents had **0** missing targets, broken anchors or missing phase targets in the scoped check. |
| [PureScript frontend](../README.md#purescript-frontend), generated contracts, panels and browser tests | [PureScript frontend](../documents/engineering/purescript_frontend.md) | Align route and generated-contract registries, browser consumers and root references; verify generated ownership and live-versus-target labels. |
| [Pulsar control plane](../README.md#pulsar-as-the-control-plane--data-plane-bus) and workflow surfaces | [Pulsar ML workflow](../documents/engineering/pulsar_ml_workflow.md) | Reconcile both projects' shared contract and jitML-specific consumers before changing the root; verify topic and envelope registries and preserve cross-project ownership. |
| [Daemon environment](../README.md#daemon-environment-env-bootconfig-liveconfig), capability classes and retry policy | [Daemon architecture](../documents/engineering/daemon_architecture.md) and [Haskell code guide](../documents/engineering/haskell_code_guide.md) | Reconcile actual service configuration, error and retry consumers, while keeping untransferred CLI rules binding; run owned controls and verify replacement links. |
| Worker publication in [root current status](../README.md#current-status) | [Worker publication](../documents/engineering/daemon_architecture.md#worker-publication) and [remote artifact publication](../documents/engineering/checkpoint_format.md#remote-artifact-publication) | Root now links to the service-coordinate and exact-byte readback contracts. The selected Linux unit group passed **19 / 19** using temporary files and the filesystem MinIO interpreter; it did not exercise a live service. The three changed documents had **0** missing targets, broken anchors or missing phase targets in the scoped check. |
| [Benchmarks](../README.md#benchmarks), [backend tuning](../README.md#compiler-runtime-and-backend-tuning) and [build/run](../README.md#build-and-run) | [JIT code generation](../documents/engineering/jit_codegen_architecture.md), [execution resources](../documents/engineering/execution_resources.md) and [CLI command surface](../documents/engineering/cli_command_surface.md) | Identify each operational command and its actual substrate, retain active entry instructions until a tested replacement exists, and distinguish resource targets from implementation. |
| [Repository layout](../README.md#repository-layout-target) and [doctrine scope](../README.md#doctrine-scope) | Candidate split: [documentation standards](../documents/documentation_standards.md) and [Haskell code guide](../documents/engineering/haskell_code_guide.md); repository layout is expressly a target | Reconcile actual paths and doctrine precedence with their owners and generated registries; retain the target label and verify all inbound references before retiring either entry. |
| [Git policy](../AGENTS.md#git-policy-for-ai-agents), [local artifacts](../AGENTS.md#local-artifacts), and the corresponding [CLAUDE entry](../CLAUDE.md#git-policy) | [Plan standards](development_plan_standards.md) and [documentation standards](../documents/documentation_standards.md), subject to the governed root entry | Preserve the human-only Git authority and artifact/path rules; align both entries and consumers without weakening the existing policy, and verify every replacement reference. |

### Generated-output inventory (in progress)

These are source-identified producers, not measured maximum paths or a Windows
support claim. A repository-relative root may be host-exposed when the checkout
is on the host or bind-mounted; the same spelling inside an image or VM is not
by itself evidence that the host can see it. Caller-selected roots and system
temporary directories require their own boundary classification. This table is
not yet exhaustive and does not replace the generated-output guard.

| Producer and root | Exposure and unresolved boundary |
|---|---|
| [`Env.Build`](../src/JitML/Env/Build.hs) defaults cache to `.build` and data to `.data`, resolving caller overrides. | Checkout-host or mounted paths depend on the selected root. No supported Windows root budget or overlong-root behavior is established. |
| [`Cache.Layout`](../src/JitML/Cache/Layout.hs) writes `jit/<substrate>/<hash>.<ext>` below the cache root; [`RuntimeSource`](../src/JitML/Codegen/RuntimeSource.hs) uses `jit-src/<substrate>/<hash>/` and nested source files. | A 64-character hash and nested generated names consume part of the actual root budget; measure each substrate and extension, including temporary publication paths. |
| [`Cache.Manifest`](../src/JitML/Cache/Manifest.hs) atomically replaces `jit/manifest.json` through a same-directory `.tmp` file. | The selected cache root can be host-exposed; its final and temporary path lengths depend on the actual caller root. Compiled artifacts and other cache writers need separate coverage. |
| [`bootstrap/_lib.sh`](../bootstrap/_lib.sh) copies the native executable to `.build/jitml`; [`MetalBridge`](../src/JitML/Engines/MetalBridge.hs) names fixed bridge artifacts under `.build/host/apple-silicon/`. | Apple host output is separate from Linux VM/container paths. Verify actual bridge and compiler intermediates, not only the displayed artifact name. |
| [`Bootstrap`](../src/JitML/Bootstrap.hs), [`Cluster.Helm`](../src/JitML/Cluster/Helm.hs) and [`PulsarChart`](../src/JitML/Cluster/PulsarChart.hs) use `.build/runtime`, `.build/conf/cluster`, the kubeconfig and downloaded chart staging. | The repository mount can expose these files to the host; chart archive, extracted dependencies, temporary names and tool-created paths need separate measurement. |
| [`NativeParentExecution`](../src/JitML/Product/NativeParentExecution.hs) uses a working-directory `.build/checkpoints`; [`ProductScenarioJournal`](../src/JitML/Test/ProductScenarioJournal.hs) and [`ProductLaneJournal`](../src/JitML/Test/ProductLaneJournal.hs) create temporary files alongside journal outputs. | Working-directory and caller-supplied journal roots may be outside the checkout. Include nested checkpoint keys, temporary names and external roots in actual producer tests. |
| [`Test.Command`](../src/JitML/Test/Command.hs) creates retained `jitml-product-scenario-` attempts below a caller root and browser evidence below `.build/runtime/jitml-browser-evidence-.../`, with `input` and `scope` children and a separate system-temporary parent. | The browser runtime tree can be bind-mounted into Playwright; the system-temporary parent and caller-selected scenario root are separate exposures. Actual randomized directory suffixes, nested filenames, cleanup and permissions require real producer observation; a checkout-relative budget alone does not cover the other roots. |
| [`ValidationRecord`](../src/JitML/Product/ValidationRecord.hs), [`BrowserEvidenceJournal`](../src/JitML/Test/BrowserEvidenceJournal.hs), and [`ProductLaneJournal`](../src/JitML/Test/ProductLaneJournal.hs) create same-directory temporary files using the destination filename plus `.tmp`; [`ProductScenarioJournal`](../src/JitML/Test/ProductScenarioJournal.hs) uses `.tmp.`. | `openBinaryTempFile` adds a tool-generated suffix to the prefix. Final-name measurements alone omit the publication path; destination and caller roots, suffix maxima, failed publication and actual host support need separate checks. |
| [`Checkpoint.Store`](../src/JitML/Checkpoint/Store.hs) creates `.jitml-object.tmp...` beside the final object and uses a hard link for publication; [`FilesystemMinIO`](../src/JitML/Service/FilesystemMinIO.hs) creates `.jitml-minio-object.tmp...` and `.jitml-minio-pointer.tmp...` beside objects. | The checkpoint root and filesystem interpreter root are independently selected. The latter is also a test interpreter, not evidence of routed MinIO operation. Their hard-link, lock and permission behavior is a filesystem/platform requirement beyond path length; Windows operation is not established by Linux tests. |
| [`MinIOSubprocess`](../src/JitML/Service/MinIOSubprocess.hs) creates payload and response files in the system temporary directory; [`NativeLaneBundle.Write`](../src/JitML/Test/NativeLaneBundle/Write.hs) creates `.native-bundle-copy...` beside bundle objects. | These are distinct temporary roots and object-copy paths. Their actual names, live lifetime and filesystem exposure must be captured with the producer; inspecting an already quiescent tree alone can miss them. |
| [`Test.Command`](../src/JitML/Test/Command.hs), [`Sub.Stream`](../src/JitML/Sub/Stream.hs) and [`Lint.Stack`](../src/JitML/Lint/Stack.hs) use system or selected temporary directories. | `TMPDIR` and platform defaults determine exposure; compiler scratch and test fixture paths must be measured independently of `.gitignore`. |
| Cabal/GHC `dist-newstyle`, frontend `web/.spago`, `web/output`, `web/dist`, Node dependencies, and Playwright results are ignored by [`.gitignore`](../.gitignore); the [Dockerfile](../docker/Dockerfile) also builds a separate image-local checkout. | Tool-controlled nested paths and configured locations must be inventoried on each claimed host workflow; image-only outputs are distinct from bind-mounted outputs. |
| [`RL.ALE`](../src/JitML/RL/ALE.hs) accepts user-supplied ROM paths and suggests ignored `.roms/`; dataset staging accepts local input paths. | These are external input boundaries, not generated portable names. The guard must distinguish unsupported user roots and third-party content from paths jitML owns. |

The remaining audit must enumerate all producer families and external tools,
define root budgets and failure behavior, implement the guard, and capture real
representative outputs—including ignored, nested and temporary paths. None of
those obligations is satisfied by this source inventory alone.

### Checkpoint local-path shortening boundary (investigated, not implemented)

The long snapshot path is a durable logical object key, not merely a disposable
filename. The [checkpoint contract](../documents/engineering/checkpoint_format.md#storage-layout)
requires the exact experiment/snapshot/original-key digest derivation in
manifests, reservations and commits; admission re-derives it. Changing that key
would therefore be a storage-format change, including remote MinIO data, rather
than a safe spelling-only cleanup.

A local-only physical mapping could retain the logical key, but it cannot simply
replace [`objectPathForKey`](../src/JitML/Checkpoint/Store.hs): local writes,
reads, conflict checks, deletion and pointer locking all use physical paths;
manifest/reservation and [native GC](../src/JitML/Checkpoint/NativeQualificationGc.hs)
also enumerate directories, while [native retention](../src/JitML/Checkpoint/NativeRetention.hs)
opens mapped paths directly. A viable implementation must specify an injective,
Windows-safe mapping for files **and prefixes**, preserve exact logical keys in
the wire and remote interpreter, and handle legacy trees without silently
choosing between conflicting copies. It must exercise both layouts through
publication, readback, listing, retention, GC and interrupted migration, with
collision and tamper negatives and real target-filesystem evidence. This is an
open design constraint, not approval to move or delete retained data.

### Validation

1. A missing target, broken anchor, duplicate canonical owner, generated-marker mismatch, and target phrased as implemented each fail their owned checker controls.
2. Valid metadata, a target labeled with its implementation owner, and an intentional historical evidence section pass without manufacturing reciprocal backlinks.
3. Check the root-authority inventory and all changed references before retiring any old binding anchor.
4. Exercise representative real output producers for each inventoried family and
   supported substrate/filesystem boundary, including nested and temporary files;
   record roots, longest paths and components, units and coverage, including
   Windows UTF-16 code units where applicable. Check actual
   Windows-exposed paths against the declared root budget and Windows naming rules.
   Include synthetic boundary, overlong root, ignored overlong output, invalid name
   and third-party overflow controls; a Linux-only pass is not a Windows-host pass.
   Verify on a Windows host with traditional path limits where that host workflow
   is claimed supported, or leave that claim and its acceptance explicitly open.
   Run `bootstrap/check-path-lengths.sh` separately on the clean tracked/unignored
   inventory; a known criterion migration failure remains owned by `278.2`.

Closure requires the owned targeted/hermetic controls listed above, with a
nonempty independently enumerated test inventory and exact scoped transcripts.
The implementation publishes actual selectable groups in the existing stanzas
and uses the supported `--test-options` passthrough; no invented selector or
unfiltered full-matrix acquisition is an acceptable substitute. A scoped result
is recorded as scoped, never as a passing full stanza. Resource/live controls
also require the actual owned runtime observations named above.

Complete evidence-dependent unit/integration/negative-control transcripts belong
to Sprints `277.2` and `280.2`; cross-family convergence belongs to `283.2` and
`285.2`. Those downstream records are not prerequisites for this foundation or
readiness closure. Every original case remains registered with an explicit owner.
The documentation/code-quality commands below run after source parity is
implemented, inside the admitted profile. The container-only code-quality gate
also runs the standalone generated-path guard controls; that does not replace
the owned stanza controls or establish producer and Windows coverage.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Cluster-running jobs use the separately admitted cluster/lifecycle overlays
instead of the stopped-cluster build profile. A real hardware lane is never
claimed by CPU fixtures; absent required runtime capability fails that lane.

### Remaining Work

- Reran the composed `jitml docs check` against this worktree after the owner,
  metadata, anchor and marker changes, using a freshly linked executable in a
  bounded Linux diagnostic container. It again exited **1** with **52**
  findings: **44** plan-structure and **8** status-projection findings. No
  other finding category was reported. These remain the `221.2` status and
  catalogue transition, not a passing documentation gate or canonical-image
  validation.
- Registered four explicitly owned topic contracts: durable-state configuration,
  checkpoint storage, product completion proof, and training metrics and splits.
  The selected execution-boundary registration control passed **1 / 1**, and a
  scoped scan of **392** governed documents found **0** metadata, owner,
  declaration or registered-boundary findings for all **8** registered
  contracts. Scoped Fourmolu, HLint and Cabal-format comparison passed. The
  registry remains incomplete and cannot identify unmarked prose claims; the
  root CLI contract and the composed documentation gate remain unchanged.
- Registered the existing authoritative plan-maintenance standards as
  `development-plan-standards`, without changing the root CLI authority. The
  selected execution-boundary registration control passed **1 / 1**, and a
  scoped **392**-document scan found **0** metadata, owner, declaration or
  registered-boundary findings for the four registered contracts. Scoped
  Fourmolu, HLint and Cabal-format comparison passed after formatting fixes.
  Other contract ownership and the composed gate remain open.
- Added the already-authoritative documentation standards to the canonical
  owner registry and separated execution-only target-boundary checks from the
  general registry. The selected registration control passed **1 / 1**; a
  scoped scan of **392** governed documents found **0** metadata, owner,
  declaration or registered target-boundary findings. Scoped Fourmolu, HLint
  and Cabal-format comparison passed after formatting corrections. This is not
  an exhaustive contract inventory, root CLI authority transfer or full gate.
- The CLI topic reference still named Command Line Tools `swift` as the Apple
  cache-miss prerequisite. Corrected it to match the fixed Metal bridge and
  runtime prerequisite graph, with Swift/SDK probes limited to optional module
  work. The root remains the binding CLI authority; this correction is not an
  authority transfer or native hardware validation.
- The checkout guard now refuses a failed Git inventory instead of allowing a
  successful pipeline consumer to mask it. Independent controls inject both
  the primary inventory failure and a Unicode-inventory failure; the full
  standalone group passed **25 / 25** in the Linux container. The real worktree
  check still exited **1** on the existing **516** path violations among
  **1,787** paths. This does not establish Windows-host behavior or a passing
  checkout guard.
- The checkout path guard now checks case collisions at every path prefix,
  including different parent directories, and uses conservative Unicode
  case-folding when Python is available. Without Python it fails closed on
  non-ASCII paths instead of silently accepting them. The standalone controls
  passed **24 / 24** in the Linux container, including ASCII/Unicode directory
  collisions and the no-Python fallback. The current worktree had no non-ASCII
  paths; its actual check still failed with **516** existing criterion-review
  violations across **1,787** paths. Case-folding is conservative and this is
  not a Windows-host checkout validation.
- After the expanded guard controls were registered with their checkout-script
  dependency, the scoped code-quality action accepted the real controls and
  rejected a deliberately broken generated-path guard. Scoped Fourmolu, HLint
  and Cabal-format comparison passed. The actual tracked/unignored checkout
  guard still exited **1** with **516** violations among **1,787** paths; this
  is the existing criterion-review path debt assigned to `278.2`, not a pass.
  Neither scoped check is the full `jitml check-code` gate.
- Both generated-output and checkout guards now conservatively reject device
  stems padded with spaces before an extension; the checkout guard also checks
  superscript COM/LPT digits, console device names and leading spaces. The
  normalization follows the approach documented in the [Go Windows path
  implementation](https://go.googlesource.com/go/+/master/src/internal/filepathlite/path_windows.go)
  while retaining the stricter cross-version device-name policy. Standalone
  controls passed **20 / 20** in the Linux container, including a temporary Git
  worktree and valid near-miss names. This is not Windows-host validation or a
  fix for the separate existing overlong tracked paths.
- Planned-path preflight now detects conservative case collisions and
  file/directory conflicts between supplied paths and existing output entries,
  while allowing exact existing-file reuse. The standalone controls passed
  **18 / 18**, and the real snapshot-path preflight again accepted the short
  root and rejected the longer example. Unenumerated paths, concurrent changes
  and platform-specific case behavior are still outside this evidence.
- The generated-output guard can now preflight repeatable caller-supplied
  future paths, checking Windows component rules, path length and the optional
  suffix reserve even when the existing inspection directory is empty. It
  explicitly reports that no outputs were observed; an empty tree without a
  planned path still fails. The standalone controls passed **16 / 16**. Using
  the real snapshot object's relative path, preflight accepted the illustrative
  short checkpoint root and rejected `C:\Users\someone\jitML\.build\checkpoints`
  before any output was created. The caller must supply complete future names;
  collisions, producer enumeration, host mapping, suffix bounds and Windows
  execution are not established. Registration at actual producer admission
  and supported-root policy remain open.
- The real local checkpoint object writer created and read back a synthetic
  snapshot-addressed object using two 64-character identifiers and the
  generated 64-character physical-key digest. In the bounded Linux container,
  inotify observed its temporary creation and final hard link. Under the
  illustrative root `C:\jitml\.build\checkpoints`, the temporary path was
  **216** and the final path **259** UTF-16 units including NUL; the guard
  inspected **6** retained entries successfully. The final relative path is
  **230** units, leaving only a **28**-unit absolute root under the 260-unit
  model. This is a real layout risk for longer roots, not a Windows-host pass or
  a complete producer maximum. Any shortening must preserve or explicitly
  migrate the snapshot object-key and retained-data contracts before use.
- For the retained filesystem-MinIO sidecar fixture below, the final relative
  path is **202** UTF-16 units. The generated-output guard accepted an
  illustrative **56**-unit absolute Windows root at exactly **260** units
  including separator and NUL; it rejected a root one unit longer, a 259-unit
  path limit, and an 88-unit component limit for the observed 89-unit final
  component. These **4 / 4** boundary controls ran in the Linux container over
  the real retained fixture. The 56-unit figure applies only to that final
  sample and 260-unit model, not to all producer inputs, temporary names or
  supported Windows roots.
- A real TensorBoard sidecar adapter wrote and read back matching CBOR bytes
  through the filesystem-MinIO interpreter in the bounded Linux container.
  The fixture used 64-character experiment and manifest identifiers and a
  19-digit step; inotify observed the temporary creation and final hard-link
  publication. Under illustrative root `C:\jitml\.build\filesystem-minio`,
  those paths measured **174** and **236** UTF-16 units including NUL, with an
  **89**-unit final component. The observed local path contains both the
  `jitml-tensorboard` bucket and the same prefix in the object key; the
  quiescent guard passed its **5** entries. This is a filesystem fixture, not
  routed MinIO or a Windows-host test, and it does not establish maximum input
  lengths or a supported root budget.
- The validation-record producer measurement was expanded to all **10**
  registered gates and **3** substrate labels: **30 / 30** synthetic records
  were written and re-admitted, with **30** temporary creations and **30**
  distinct final renames observed. Under the same illustrative Windows mapping
  below, the largest observed temporary path was **87** UTF-16 units including
  NUL and the largest final path was **78**; the quiescent guard inspected all
  **30** final files successfully. The longer temporary observation supersedes
  the earlier single sample as the observed maximum, but still does not bound
  future randomized suffixes, prove Windows filesystem behavior, or validate
  any substrate hardware.
- The actual validation-record writer produced and re-admitted a synthetic
  `jitml-model-convergence.apple-silicon.json` fixture in a bounded Linux
  container. An inotify observer captured its temporary creation and final
  rename. Under the illustrative mapping `C:\jitml\.build\runtime\validation`,
  the observed temporary and final paths measured **86** and **78** UTF-16
  units including NUL; the quiescent-tree guard passed the final output. The
  temporary suffix was observed once, not bounded, and the guard did not
  inspect it while live. The fixture is not an Apple hardware validation, a
  qualification record, or a Windows-host test.
- Expanded the generated-output inventory for scenario/browser namespaces,
  validation and journal atomic writes, checkpoint and filesystem-MinIO
  publication, subprocess temporary files and native-bundle copies. A read-only
  source check confirmed **15** named facts in **9** cited producer files; no
  producer was executed. Randomized temporary names, real host mappings,
  hard-link/permission support and Windows validation remain open.
- Section replacement now also refuses orphaned, reversed or duplicate markers
  in a different region before writing, closing a malformed-neighbor case not
  covered by the valid-pair overlap check. The selected generated-section group
  passed **3 / 3** with those controls, and a read-only replacement check
  accepted all **16 / 16** registered sections in the current worktree.
  Scoped Fourmolu, HLint and Cabal-format comparison passed after formatting
  corrections. This does not establish the full documentation gate.
- Required metadata fields now reject empty values and duplicate declarations;
  header values with permitted leading whitespace are read correctly. The
  selected metadata group passed **7 / 7**, and a scoped scan of **392**
  governed documents found **0** metadata or canonical-declaration findings.
  Scoped Fourmolu, HLint and Cabal-format comparison passed after corrections.
  This does not prove semantic accuracy of all header values or the composed
  documentation gate.
- The metadata gate and section replacement now reject nested and crossing
  generated regions with unique, correctly ordered marker pairs. The selected
  generated-section group passed **3 / 3**, covering nested, crossing and
  separate regions, and the scoped **392**-document metadata/declaration scan
  found **0** findings. Scoped Fourmolu, HLint and Cabal-format comparison
  passed. Other malformed marker combinations and the composed documentation
  gate remain open.
- The metadata gate now rejects repeated generated-section start/end markers
  and an end marker preceding its unique start. The selected metadata group
  passed **6 / 6**, including three new negative cases, and a scoped scan of
  **392** governed documents found **0** metadata or canonical-declaration
  findings. Scoped Fourmolu, HLint and Cabal-format comparison passed after
  formatting and lint corrections. The overlap controls are recorded above;
  this is not a composed documentation-gate pass.
- Corrected the root TensorBoard checkpoint cross-link description to label
  end-to-end event and frontend integration as target behavior, matching the
  checkpoint-format boundary. Source inspection also found that the topic
  document named two absent dispatcher functions and claimed daemon wiring;
  it now describes the actual sidecar adapter and direct filesystem fixture,
  with event wiring and live publication unproven. This correction does not
  transfer root authority or establish live integration.
- Metadata and canonical-contract declarations now use parsed top-level
  Markdown nodes rather than raw lines, excluding fenced and nested examples
  before the first second-level section. The selected metadata group passed
  **5 / 5**, including fenced-header and fenced-owner negative controls; a
  scoped scan of **392** governed documents found **0** metadata or canonical
  declaration findings. Scoped Fourmolu, HLint and Cabal-format comparison
  passed after a formatting correction. This is not a complete header-shape or
  composed documentation-gate validation.
- Expanded the candidate authority inventory to cover toolchains,
  prerequisites, substrate rules, bootstrap and cache discipline, storage,
  observability, repository layout and doctrine scope. A read-only check found
  all **13** cited root headings and **9** candidate topic files; it did not
  independently validate rendered fragment slugs or enumerate inbound links.
  Some topics still lack a confirmed single owner, and no binding authority was
  transferred by this inventory.
- The composed `jitml docs check` was run against the current worktree using a
  freshly linked executable in the bounded Linux diagnostic container; it
  returned **1** with **52** findings: **30** unregistered sprint blocks,
  **7** undeclared edges, **5** backward-edge findings, **2** validation
  obligation findings and **8** status-projection findings. There were no
  link, anchor, metadata, canonical-owner or target-boundary findings in that
  invocation. The status/catalogue transition remains owned by `221.2`; this
  failed diagnostic is not a canonical-image or full quality-gate pass.
- Generated-marker metadata scanning now uses the Markdown parser to exclude
  fenced examples, including mixed fence characters and shorter closing fences,
  while still detecting unowned markers outside the example. The selected
  Linux-container metadata group passed **4 / 4** controls. Scoped Fourmolu,
  HLint and Cabal-format comparison passed after correcting a formatting
  failure; neither result is a full documentation or quality gate.
- Generated-section replacement now uses parsed source positions for standalone
  marker comments. A previous key-only check could accept a marker in a block
  quote and then replace a same-named fenced example; the replacement now selects
  the actual source lines and preserves the example. An initial position check
  failed **2 / 2** controls because the parser's HTML-block end positions did not
  match the assumed range; after matching the parsed comment to its source line,
  replacement controls passed **2 / 2** and metadata controls passed **4 / 4**.
  A read-only diagnostic accepted all **16** registered sections in this
  worktree. Scoped Fourmolu, HLint and Cabal-format comparison passed after an
  initial formatting failure. These results do not establish the composed
  documentation gate.
- A duplicate-marker guard and focused control are present in the working tree.
  A cold `jitml:local` build compiled the library and executable but failed its
  code-quality stage on the existing status-transition mismatch and a test HLint
  hint; the hint was corrected and its scoped HLint check subsequently passed
  in a diagnostic container from the failed build. A selected `jitml-unit`
  invocation then exhausted its 3-GiB GHC heap compiling the existing unit
  entry point; the selected test did not run. After correcting its partial
  function warning, scoped HLint passed and three separate diagnostic marker
  cases passed against the compiled module in that container. The
  canonical image was not produced. The status mismatch is owned by `221.2`.
- A second selected-unit attempt with GHC's compacting collector still exhausted
  the 3-GiB compiler heap in the unit entry point after compiling the other 120
  modules. The selected case did not run. Both attempts remain failures. The
  test-entry remediation requests
  `-O1` without aggressive specialisation or exposed unfoldings; product
  library flags and registered cases are unchanged. In the retained diagnostic
  container, the 3-GiB heap compilation then completed and the selected marker
  test passed **1 / 1**. This scoped result is not a full-stanza pass or a
  canonical-image validation; verify the broader harness and quality gates.
- Implement the new link/authority checks and reconcile their source registration with the documentation targets.
- The composed documentation checker initially added a partial canonical-owner
  registry for two ownership boundaries named in the documentation standard:
  execution resources and validation execution. It reports missing, duplicate or
  unexpected registrations and unreadable or non-authoritative owner documents.
  The selected Linux unit control passed **1 / 1** with six cases, and a
  read-only worktree check of those two registered documents found **0** drifts.
  Scoped Fourmolu, HLint and Cabal-format comparison passed after correcting a
  formatting failure. Explicit canonical-contract headers now allow the check
  to find a conflicting declaration in another governed document and require
  each registered owner to declare its key. The selected ownership controls
  passed **2 / 2**, and a separate scan of **392** governed documents found
  **0** declaration drifts. Scoped Fourmolu, HLint and Cabal-format comparison
  passed after correcting formatting and HLint failures. The registry does not
  enumerate every durable contract, detect unmarked claims in prose, transfer
  root authority, or establish that any target protocol is implemented; those
  obligations remain open, as does the composed documentation gate.
- The execution-resources and validation-execution summaries stated target
  behavior without a target label; both now label it. A scoped checker requires
  those summaries and current-status sections to distinguish implemented and
  target boundaries and cite a target phase, while ignoring fenced example
  headings. The selected control passed **1 / 1** after a first passing run
  emitted warnings that were corrected; a read-only check of both documents
  reported **0** boundary drifts. Scoped Fourmolu, HLint and Cabal-format
  comparison passed after formatting and HLint corrections. This structural
  check neither classifies arbitrary target prose nor proves the cited phase
  owns or implements the described contract.
- The scoped target-boundary check now inspects parsed Markdown paragraphs:
  labels in fenced or inline code do not count, and the phase link must appear
  in the target paragraph itself. The expanded selected control passed **1 / 1**
  and the two registered execution documents reported **0** boundary drifts.
  Scoped Fourmolu, HLint and Cabal-format comparison passed after formatting
  and HLint corrections. This remains a structural check rather than semantic
  proof of implementation or a full documentation-gate pass.
- Parsed relative file and directory targets are now checked during `docs check`,
  including percent-decoded paths; external and root-absolute URLs are excluded.
  The focused controls passed **2 / 2** after formatting in the Linux diagnostic
  container; the existing phase-link selection passed **4 / 4**. Scoped
  Fourmolu, HLint and Cabal-format comparison passed after correcting an initial
  formatting failure. A read-only invocation of the new target check over
  **392** governed Markdown documents reported **569** missing or invalid
  destinations in this worktree, including links to absent `.build` receipts;
  all 569 resolved to Git-ignored local paths. Converted **576** occurrences in
  **59** documents to code-form paths while preserving their labels and historical
  claims. The same scoped check then reported **0** missing or invalid relative
  destinations across **392** documents. This was not the complete composed
  `docs check`. A subsequent change adds raw HTML `a`/`img` destinations and
  Markdown fragment checks, including explicit HTML anchors and duplicate
  headings. The selected anchor controls passed **2 / 2**, the relative-link
  controls **3 / 3**, and the phase-link controls **4 / 4** in the Linux
  diagnostic container. Scoped Fourmolu, HLint and Cabal-format comparison
  passed after an initial formatting failure was corrected; the new HTML parser
  dependency emitted GHC warnings. An independent scoped scan reported three
  broken fragments across **392** documents; after correcting those citations,
  the same scan reported **0**, and the relative-target scan including HTML
  reported **0**. Generated heading slugs fail closed on Unicode characters
  outside the then-verified set. The pinned Unicode implementation and its
  scoped validation are recorded below; renderer parity, other HTML forms and
  the complete Markdown/root authority contract remain open.
- Raw HTML destination checking now also covers single-URL media, source,
  script, stylesheet/link, frame, embed and object attributes. The selected
  relative-link controls passed **3 / 3**, including external URLs, application
  form actions and fenced examples; a scoped scan of **392** governed documents
  found **0** missing or invalid targets. Scoped Fourmolu, HLint and Cabal-format
  comparison passed after a formatting correction. Other HTML forms,
  non-Markdown fragments and the full composed documentation gate remain open.
- The checker now extracts `srcset` and `imagesrcset` candidate URLs using the
  [HTML token-boundary rules](https://html.spec.whatwg.org/multipage/images.html#parsing-a-srcset-attribute),
  including commas inside data URLs and parenthesized descriptors. It checks
  candidates conservatively without claiming full descriptor validation. The
  selected link controls passed **4 / 4** and a scoped scan of **392** governed
  documents found **0** missing or invalid targets. Scoped Fourmolu, HLint and
  Cabal-format comparison passed. Other HTML forms, non-Markdown fragments and
  the composed documentation gate remain open.
- A documentation-check invocation now shares parsed anchor indexes across
  links to the same target, with a fresh cache on each invocation. The selected
  anchor controls passed **3 / 3**, including changed-target observation on a
  later invocation. A scoped comparison across **392** governed documents found
  identical individual and batched results, with **0** drifts in each. The
  single observed passes took approximately **4.19 s** and **3.69 s**
  respectively; the second benefited from prior filesystem access, so this is
  not an independent performance benchmark. Scoped Fourmolu, HLint and
  Cabal-format comparison passed after formatting and HLint corrections. This
  does not establish the full composed documentation gate.
- A Linux-container inventory evaluated every non-ASCII Unicode scalar in the
  retained `github-slugger` 2.0.0 reference under Node **22.16.0 / Unicode 16.0**:
  **977,435** produced an empty slug, **133,132** were unchanged and **1,369**
  mapped to different output, including one multi-code-point result. This is
  characterization of isolated characters, not parity for whole headings:
  contextual case mapping, renderer/version differences and independently
  maintained reproducible tables still needed validation at that checkpoint.
- The checker now uses hash-pinned generated tables from `github-slugger` 2.0.0
  and Node **22.16.0 / Unicode 16.0**, including contextual final sigma. The
  generator checks both upstream source hashes and the Node/Unicode versions;
  reproduction matched byte-for-byte and a modified reference was rejected.
  The compiled Haskell output matched the reference SHA-256 for **3,336,192**
  inputs covering every Unicode scalar alone and on both sides of sigma. A
  separate reference model also matched **3,436,203** scalar, contextual and
  deterministic random inputs. Selected anchor controls passed **3 / 3**,
  pinned-source missing/modified controls passed **1 / 1**, and both individual
  and batched checks found **0** anchor drifts across **392** governed documents.
  Scoped Fourmolu, HLint and Cabal-format comparison passed after corrections.
  This pins one reference/version rather than proving every GitHub renderer or
  every possible heading; the full composed documentation gate remains open.
  The tracked/unignored path guard still reported the pre-existing **516**
  criterion-review violations across **1,787** paths, with no new violation.
- Fragment checking now indexes explicit IDs and named anchors in retained HTML
  and SVG targets, including case-insensitive file extensions. The selected
  anchor controls passed **4 / 4**, including valid and missing IDs and an
  unsupported PDF fragment. Individual and batched checks agreed with **0**
  findings across **392** governed documents. Scoped Fourmolu, HLint and
  Cabal-format comparison passed after correcting formatting and lint findings.
  Other document formats and browser-specific rendering remain outside this
  evidence; the full composed documentation gate is still blocked.
- The existing phase-link scanner now ignores fenced examples, including longer
  closing fences. Its selected unit control passed **1 / 1** using the retained
  diagnostic container and a 3-GiB heap. A preceding cached attempt with a
  1-GiB compiler heap overflowed before running the case and remains failed.
  The grouped phase-link controls subsequently passed **3 / 3**, and existing
  metadata controls passed **3 / 3**, in the same diagnostic-image scope.
  Scoped Fourmolu passed for the changed Haskell files with the project's
  `--no-cabal` and GHC2024 options; an earlier invocation omitting those options
  failed to parse the Cabal version and remains a failed invocation. A scoped HLint
  and standalone fenced-link diagnostic pass against the changed module in the
  diagnostic container. The first standalone attempt failed because the command
  omitted the project's GHC2024 language setting; the corrected attempt passed.
  The diagnostic was rerun after adding over-indented and invalid backtick-info
  cases; both scoped HLint and the expanded diagnostic passed.
  A subsequent change replaces the hand-written scan with a GFM parser and adds
  controls for inline code, escaped backticks, reference links and tables. The
  expanded phase-link selection passed **4 / 4** in the Linux diagnostic
  container; the new dependency emitted GHC warnings. Scoped Fourmolu, HLint
  and `cabal format` comparison passed after an initial format invocation failed
  because its configured scratch directory did not exist. General targets and
  anchors still need the broader checker and validation; this partial change
  does not close that requirement. A prior narrow inline-span experiment was
  discarded because it did not handle escapes and paragraph boundaries safely.
- Seven historical Source `9b90cf0f…` paragraphs were removed from the root
  status narrative only after their complete whitespace-normalized text was
  verified in the [plan overview](00-overview.md); the root now links to that
  record. A scoped check of the root README found **0** missing relative
  destinations and **0** broken local anchors. This is a partial diary cleanup,
  not a transfer of CLI or other binding doctrine. Finish the remaining root
  diary audit and authority-transfer inventory, enumerate inbound consumers and
  validate replacements before retiring any binding anchor.
- The next root status paragraph contained details not reproduced verbatim in
  the plan. Its full historical text was retained in the
  [Phase 278 historical record](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#former-root-status-narrative),
  with its plan link rebased, before the root copy was replaced by a concise
  pointer. A scoped check of the root and Phase 278 documents found **0** missing
  relative destinations, **0** broken anchors and **0** missing phase targets.
  The remaining root narrative and authority transfers are still open; the
  moved narrative is historical evidence, not current execution authority.
- A mixed root paragraph retained its current contract statements while its
  source-specific recovery chronology was moved intact to the
  [Phase 278 record](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#former-root-source-and-recovery-chronology).
  A scoped check of both changed documents reported **0** missing relative
  destinations, **0** broken anchors and **0** missing phase targets. The
  remaining root approval text was then reviewed separately.
- The full fixed-trial authorization, constraints and outcome narrative is now
  retained in the [Phase 278 record](phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#retained-fixed-trial-authorization-and-outcomes),
  with its two plan links rebased. The root keeps the authorization's fixed
  parameters, links all retained constraints, and preserves the user's NVIDIA
  handoff and no adaptive retry/row-splicing boundary. This move authorizes no
  new run. A scoped check of both documents reported **0** missing relative
  destinations, **0** broken anchors and **0** missing phase targets.
- The root's Apple qualification chronology was likewise retained in the
  [Phase 272 historical record](phase-272-apple-integration-e2e-and-attestation.md#retained-root-apple-chronology),
  with its plan link rebased, and replaced by a root pointer. A scoped check of
  both changed documents found **0** missing relative destinations, **0**
  broken anchors and **0** missing phase targets. Historical outcomes and
  reopenings keep their original scope; this relocation does not close a gate.
- Inventory and remediate generated path producers, implement the separate guard,
  document supported roots and external-tool boundaries, and obtain the scoped
  portability evidence above. Existing output coverage and Windows operation are
  not established by the documentation change.
- A caller-scoped generated-output guard and nine independent CLI controls are
  in the working tree. The guard inspects ignored entries and rejects links,
  invalid names, including superscript-digit COM/LPT names documented by
  [Microsoft](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file),
  conservative case collisions and UTF-16 budget violations for
  an explicitly supplied Windows mapping. It reports the mapping, entry count
  and observed UTF-16 maxima, and refuses an empty tree. All **8 / 8** current
  CLI controls passed in the Linux diagnostic container before the reserved-name
  extension; the expanded set passed **9 / 9**. A selected **1 / 1**
  unit wrapper for the earlier seven-control version also passed,
  but was removed after review because requiring host `python3` in every unit
  lane would add an Apple Metal host prerequisite. Registered, portable unit
  coverage remains open. The guard has not yet been registered for all actual
  producer roots or verified on Windows; neither its presence nor a synthetic
  result establishes Phase 3 portability coverage.
- The guard also refuses leading-space components, `CONIN$`/`CONOUT$` console
  device names and unsupported filesystem objects. Microsoft documents
  [leading-space normalization](https://learn.microsoft.com/en-us/troubleshoot/windows-client/shell-experience/file-folder-name-whitespace-characters)
  and [DOS console device names](https://learn.microsoft.com/en-us/windows/win32/devnotes/rtlisdosdevicename_u).
  The expanded standalone CLI controls passed **11 / 11** in the Linux
  diagnostic container, including a FIFO refusal. These remain synthetic
  controls and do not validate the guard or its test fixtures on Windows.
- The quiescent-tree guard accepts an explicit `--file-suffix-units` length
  reserve and checks it against both path and component budgets for regular
  files. Its standalone Linux controls passed **13 / 13**, including exact
  path/component boundaries and a negative reserve. Against the previously
  observed runtime-source tree, a nine-unit reserve passed a **130**-unit path
  budget and failed at **129**. This matches that observed temporary suffix,
  but neither proves a maximum suffix nor validates temporary names, collisions,
  concurrent writes or a Windows host. A caller must establish its own reserve;
  producer registration and supported root budgets remain open.
- `jitml check-code` now runs the standalone generated-output guard controls in
  its container-only lane, and the guard and controls are included in Cabal
  source distributions. A scoped diagnostic compiled the changed library and
  verified that the registered action accepts the real controls and reports a
  finding for a deliberately broken guard. Its first invocation performed both
  assertions but failed during temporary-directory cleanup; the corrected
  diagnostic exited **0**. Scoped Fourmolu, HLint and Cabal-format comparison
  passed. This registration adds no Python prerequisite to native substrate
  tests and does not replace the required selectable stanza controls, the full
  code-quality gate, or Windows-host validation.
- A scoped Linux-container diagnostic invoked the real CPU runtime-source
  materializer with a fixed 64-character test hash and produced one `kernel.cc`
  in a host-backed ignored tree. A repeat inspected four file/directory entries.
  Under the hypothetical `C:\jitml\.build`
  mapping its longest observed final path was **109 UTF-16 units including
  NUL**, with a **64-unit** longest component. The guard accepted a 260-unit
  budget and rejected an 80-unit budget. This did not observe the transient
  staging name, execute a kernel, establish final-source or Windows-host evidence,
  or cover other producers and substrates.
- A subsequent Linux-container diagnostic invoked the same materializer for
  CPU, CUDA and Metal source variants in a host-backed ignored tree. Linux
  inotify observed each temporary creation and final rename; queue overflow or
  missing events failed the diagnostic. For the hypothetical
  `C:\jitml\.build` mapping, observed temporary/final lengths in UTF-16 units
  including NUL were **118 / 109** (CPU), **119 / 110** (CUDA) and **130 / 121**
  (Metal). The final-tree guard accepted all **10** observed entries, with a
  64-unit longest component. Process and unique-number suffixes vary, so these
  observations are not maximum lengths or declared root budgets. Rendering
  source for CUDA and Metal on Linux does not execute either GPU or validate
  their native filesystems; other producer families and Windows remain open.
- A separate Linux-container diagnostic wrote an empty cache manifest through
  the real atomic writer and read it back. Linux inotify observed the temporary
  creation and final rename. For the same hypothetical `C:\jitml\.build`
  mapping, the temporary and final paths measured **38** and **34** UTF-16 units
  including NUL; the final-tree guard accepted **2** entries. This covers one
  selected caller root and manifest shape, not other cache writers, longer
  actual roots, concurrent writers, or Windows-host operation.
- The tracked/unignored path guard was run against this worktree and returned
  exit 1, reporting 516 violations across 1,783 checked paths; after adding the
  output guard and its CLI controls it again reported 516 across 1,785. The reported
  overlong criterion-review paths remain owned by `278.2`; this failure is not
  a generated-output portability pass and does not close either obligation.

## Retained Historical Scope

The following state, commands, measurements and closure statements describe the
original Sprint `3.1` surface only. New execution rules and acceptance
above supersede any conflicting operational instruction; old receipts are not
reinterpreted as current readiness.

### Historical Phase State

✅ **Done**.

## Sprint 3.1: Governed-Document Metadata Enforcement [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Docs/Check.hs`, `src/JitML/Lint/Stack.hs`,
`DEVELOPMENT_PLAN/attestations/*.md`,
`documents/documentation_standards.md`
**Docs to update**: `README.md`, `DEVELOPMENT_PLAN/README.md`,
`DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`,
`DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`,
`documents/engineering/code_quality.md`

### Objective

Make the documentation metadata contract executable instead of aspirational.
Owns the project-doctrine `Generated Artifacts` and documentation-standard
surfaces for governed Markdown files.

### Deliverables

- `jitml docs check` validates the required governed-document header fields:
  `Status`, `Supersedes`, `Referenced by`, `Generated sections`, and `Purpose`.
- The `Generated sections` metadata must agree with physical generated-region
  markers and with the `GeneratedSectionRule` registry.
- The three per-lane attestation documents carry `**Supersedes**: N/A`, matching
  [../documents/documentation_standards.md](../documents/documentation_standards.md).
- Documentation status lives in `DEVELOPMENT_PLAN/README.md`; engineering docs
  explain architecture and link back instead of maintaining a competing status
  ledger.

### Validation

- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml lint docs`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/execution_resources.md`.
- `../documents/engineering/validation_execution.md`.
- `../documents/documentation_standards.md`.
- `../documents/engineering/code_quality.md`.

**Product docs to create/update:**

- [Development-plan entry](README.md#validation-foundation-refactor), [component inventory](system-components.md), and [deletion ledger](legacy-tracking-for-deletion.md).

**Cross-references to add:**

- Link the target contracts, exact sprint dependencies and evidence pointers together when source implementation lands; update root summaries only in an authorized root-file change.
