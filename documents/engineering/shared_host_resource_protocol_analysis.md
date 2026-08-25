# Shared Host Resource Protocol — Review

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Engineering documentation index](README.md)
**Generated sections**: none

> **Purpose**: Record the verified findings of the 2026-08-24 review of
> [shared_host_resource_protocol.md](shared_host_resource_protocol.md), separating what that document
> states correctly from what conflicts with the authoritative external specification, this codebase,
> and [the plan](../../DEVELOPMENT_PLAN/README.md).

## Current Status

Nothing in this review is implemented. The reviewed document remains unchanged and unadopted, and no
phase in [../../DEVELOPMENT_PLAN/](../../DEVELOPMENT_PLAN/README.md) owns any remedy in
[§8](#8-recommended-disposition) — so this section cannot link owning phases, and says so rather
than omitting the requirement. Creating those phases is itself step 3 of the recommended
disposition. The findings below describe implemented behavior as of `2d10717`; §8 is a
recommendation, not a contract.

## 1. Scope and method

Every claim in the reviewed document was checked against source, chart, Dhall, test, and plan files
in this repository, and against the authoritative external specification. Claim verdicts were
produced by independent readers and then re-checked by adversarial verifiers instructed to refute
them; only findings that survived both passes appear here. File and line citations are as of
`2d10717`.

The authoritative external specification is
`hostbootstrap/documents/engineering/shared_host_resource_protocol.md`, titled **Finite Resource
Execution Authority Protocol** (854 lines; a copy marked `Authoritative source` also lives in
`amoebius`). References below to "the specification" mean that file.

## 2. Verdict summary

| Section | Claim | Verdict |
|---------|-------|---------|
| Preamble | Ledger vocabulary, `spec-version`, `Persistent`/`Transient` claim kinds | **Refuted** — absent from the specification; see [§3.1](#31-the-vocabulary-does-not-match-the-specification) |
| §1 | Host-memory prerequisite admits unconditionally on Apple hosts | **Confirmed**, and understated |
| §1 | Lock-file deletion is "the one machine-wide filesystem interaction" | **Refuted** — see [§4.2](#42-the-one-machine-wide-filesystem-interaction) |
| §2 | Retained output is charged and stays charged | **Confirmed** and consistent with the specification |
| §3 | The seam "already runs before bring-up and already refuses" | **Refuted** — see [§3.2](#32-the-named-seam-is-not-on-the-bring-up-path) |
| §3 | A claim can attach at a prerequisite node | **Refuted** — see [§3.3](#33-the-seam-is-the-wrong-shape-and-the-specification-forbids-it) |
| §4.1 | Device visibility is not allocation | **Confirmed** as fact; conflicts with closed phases as framing |
| §4.2 | Generated Jobs render no `resources:` block | **Confirmed**; genuinely unowned |
| §4.3 | "No capability is required" at engine entry points | **Partially refuted** — see [§4.3](#43-no-capability-is-required) |
| §4.4 | "Nothing to convert into a charge" | **Refuted** — see [§4.1](#41-nothing-to-convert-into-a-charge) |
| §5 | Host workload registry is process-local and non-durable | **Confirmed** |
| §5 | Container coordinates if the root is mounted "at the same path" | **Refuted** — path equality is necessary, not sufficient |
| §5 | Base charge arithmetic is undecided | **Partially refuted** — one candidate is already implemented |

## 3. Premise defects

These are not wording problems. Each invalidates a section.

### 3.1 The vocabulary does not match the specification

This repository held the 854-line specification at `eeabc7d` and replaced it, through one
intermediate draft, with the current 91-line participation record at `2d10717`. The participation
record's central nouns do not appear in the document whose authority it defers to:

| Term used in the reviewed document | Status in the specification |
|---|---|
| "claim ledger" | Absent. The specification says *host coordination root*, *layout*, *locks*, *allocation records*, *catalog*. |
| `spec-version` | Absent, and contradicted: *"Protocol version lives inside the layout and journal, never in the root or lock pathname."* |
| `Persistent` / `Transient` claim kinds | Not a taxonomy. `persistent` and `transient` are components of requirement arithmetic: *"persistent baseline plus transient work uses `persistent + maximum concurrent transient`."* |

The specification's actual chain is
`ProjectId -> ParentScopeId -> ClaimKey -> Lease -> AppliedEnvelope -> ExecutionAuthority ->
ResourceReceipt` over disjoint **resource cells**, with a closed `Strength` enumeration
(`DetectionOnly`, `AdmissionOnly`, `ReactiveTermination`, `BoundedShared`, `HardCeiling`,
`ExclusiveUse`, `ReservedAndCeilinged`, `HardwarePartitioned`).

The reviewed document promotes two arithmetic adjectives into a two-valued claim taxonomy, so §2's
argument that "`Persistent` is the only honest kind" concerns a distinction the protocol does not
make. The specification's own conformance boundary rules this out directly: *"similarly named files,
copied Markdown, or locks do not establish compatibility"*, and *"only separately reviewed Haskell
declarations own protocol constants, canonical encodings, satisfaction rules, and conformance
vectors."*

The drift is propagated into [README.md](README.md), whose index entry repeats the invented terms.
The `infernix` sister repository carries a structurally identical participation record with the same
invented vocabulary, so a correction here leaves that one inconsistent.

Nothing is installed on this host: no `/Library/Application Support/FiniteResourceAuthority`, no
`/var/lib/finite-resource-authority`, no `finite-resource-authority` group, no `layout.cbor`. The
specification is itself a target: its evidence phases in `amoebius` are `Blocked — NOT VALIDATED`,
and no source tree in the family contains `ExecutionAuthority`, `ParentScopeId`, or `epoch.lock`.

### 3.2 The named seam is not on the bring-up path

§3 states the host-memory prerequisite "already runs before bring-up and already refuses." It does
not run before bring-up.

- `runBootstrap` ([`src/JitML/App.hs:517-546`](../../src/JitML/App.hs)) calls
  `liveExecutePhasedRollout` directly.
- `runCluster ["cluster", "up"]` ([`src/JitML/App.hs:597-620`](../../src/JitML/App.hs)) does the
  same.
- `checkNode` is evaluated only from `Prerequisite.reconcilePrerequisites` and the plan builder, and
  those are reached only from `runDoctor` / `runDoctorRemediate`
  ([`src/JitML/App.hs:318,327,332,336`](../../src/JitML/App.hs)) and the read-only
  `internal list-prereqs` printer (`:259`).

So on every substrate the seam is bypassed by the two commands that create clusters. On Apple hosts
it is additionally vacuous. [cluster_topology.md](cluster_topology.md) already attributes the check
to `jitml doctor --scope cluster` rather than to bring-up.

The vacuity is also broader than §1 states. `checkMinimumHostMemory`
([`src/JitML/Prerequisite/Nodes/Cluster.hs:96-110`](../../src/JitML/Prerequisite/Nodes/Cluster.hs))
admits on three separate paths: `/proc/meminfo` absent (`:99-100`), `parseMemTotalKB` returning
`Nothing` (`:103-104`), and — because `loadClusterResourcesOrDefault "."` is working-directory
relative (`:106`) — a silent fall back to built-in defaults when run from elsewhere. Its threshold
is `nodeMemoryMiB res + 4096` (`:107-109`), which bounds one node while every kind config
materializes a control-plane node plus workers.

### 3.3 The seam is the wrong shape, and the specification forbids it

`Prerequisite` carries `checkNode :: IO Bool`
([`src/JitML/Prerequisite/Types.hs:23`](../../src/JitML/Prerequisite/Types.hs)) — a stateless
boolean probe with no return payload, no lifetime, and no release counterpart. A claim is acquired,
held for the duration of the work, and released. Those are different shapes, and §3's "at the same
point in the same sequence" understates the change to the `Prerequisite` type itself.

The specification rules out the proposed arrangement explicitly:

> A Kind cluster, VM, host daemon, validation matrix, or training service cannot borrow the invoking
> CLI's lifetime. One project-owned per-parent-scope anchor starts first and acquires every lock
> itself before creating a domain; no process unlocks and transfers custody.

Its adoption row for this project asks for exactly that: *"keep a lease anchor for persistent
clusters."* The reviewed document proposes acquisition inside the CLI process, names no release
seam, and its §3 sentence about release ("resource release happens after cleanup has established the
placement is terminal or absent") points at no code.

## 4. Factual errors in the local claims

### 4.1 "Nothing to convert into a charge"

§4's fourth bullet concludes that run budgets carry no resource dimension "so there is currently
nothing to convert into a charge." A typed resource budget already exists and is enforced at Dhall
type-check time:

- `dhall/project/Schema.dhall` defines `Budget = { cpu : Natural, memory : Natural, storage :
  Natural }` and `PodResources = { replicas : Natural, cpuLimit : Natural, memoryLimit : Natural }`,
  with `totalCpu` / `totalMemory` computed as the sum of `replicas * limit`, plus `fitsWithin` and
  `storageFitsWithin` asserted in the closed contract.
- `dhall/cluster/Schema.dhall` gives every platform component a `ComponentBudget` carrying
  `cpuRequest`, `cpuLimit`, `memoryRequest`, and `memoryLimit`.
- The Haskell mirrors are `JitML.Project.Config.Budget` / `PodResources`
  ([`src/JitML/Project/Config.hs:78-92`](../../src/JitML/Project/Config.hs)) and
  `JitML.Cluster.Resources` ([`src/JitML/Cluster/Resources.hs:42-45`](../../src/JitML/Cluster/Resources.hs)).

The bullet is true only of `TrainingBudget`
([`src/JitML/Training/Budget.hs:124-137`](../../src/JitML/Training/Budget.hs)), whose `BudgetKind`
is `SupervisedEpochBudget | RlEnvironmentStepBudget | AlphaZeroSelfPlayBudget | TuningTrialBudget`.
The document generalizes from that type to the whole repository and reaches a false conclusion.

This also partially answers §5's last open question. "Whether the claim reserves the sum of node
ceilings, the reachable workload maxima, or a measured enclosing ceiling is undecided" — the
reachable-workload-maxima candidate is implemented (`totalCpu` / `totalMemory`), and the
node-ceiling candidate is available as data (`ComponentBudget` plus `nodeMemoryMiB`).

Note that semantic-only dimensioning of `TrainingBudget` is deliberate, not accidental:
[run_contract.md](run_contract.md) records that the traditional-RL budget *"deliberately has no
optimizer-update quantity"* because the removed field could not be compared dimensionally. Adding
processor shares and resident memory to the same unit-indexed family would reintroduce that class of
incommensurable axis. Whether resource dimensions belong there is a legitimate design question —
but it is an amendment proposed against an `Authoritative source` contract, not a defect in it, and
the reviewed document raises it uncited and unowned.

### 4.2 "The one machine-wide filesystem interaction"

Two problems.

**It is not machine-wide in effect.** The deleted lock covers
`/tmp/jitml-kind-create-<substrate>.kubeconfig.lock`
([`src/JitML/Cluster/Helm.hs:179-181`](../../src/JitML/Cluster/Helm.hs),
[`src/JitML/Bootstrap.hs:2008-2016`](../../src/JitML/Bootstrap.hs)) — a path this project names and
owns, prefixed by `jitml-` and scoped by substrate. The only party it can exclude is another jitML
run on the same substrate, which makes it a self-concurrency hazard rather than the cross-project
blindness §1 presents it as. `prepareKindKubeconfigFiles` also deletes a second, repo-local lock
(`.build/jitml.kubeconfig.lock`), and it runs on the reconcile path rather than only on creation.

**It is not the only one.** `compose.yaml` bind-mounts `/var/run/docker.sock` under
`network_mode: host`; `JitML.Service.MinIOSubprocess` opens system temp files on every request; and
`JitML.Sub.Stream`, `JitML.Sub.Piped`, and `JitML.Lint.Stack` each create system temp directories.
Host-global reads include `~/.docker/config.json` and `~/.ghcup`.

**The stronger available fact is omitted.** §5 asserts the in-memory registry "cannot itself hold" a
claim, and §1 frames the repository as removing exclusion rather than acquiring it. But
`writePointerCasLocal`
([`src/JitML/Checkpoint/Store.hs:3525-3565`](../../src/JitML/Checkpoint/Store.hs)) is a working
cross-process advisory lock — `openFd` plus `waitToSetLock` / `setLock`, bracketed release, nested
`MVar` — documented as *"Cross-process local compare-and-swap."* That is the primitive shape the
specification's lock algebra needs, and the document says the repository does not have one.

### 4.3 "No capability is required"

A capability class does exist: `class (Monad m) => HasEngine m`
([`src/JitML/Engines/HasEngine.hs:47-48`](../../src/JitML/Engines/HasEngine.hs)), which
[jit_codegen_architecture.md](jit_codegen_architecture.md) calls "the current engine capability",
and the four service capability classes are catalogued in
[daemon_architecture.md → Capability Classes](daemon_architecture.md#capability-classes).

The substance survives, but the accurate statement is narrower and more actionable: `HasEngine` is a
dispatch selector rather than an admission token, and it is discharged at the boundary by three
concrete escapes — `runLinuxCpuEngine`, `runCudaEngine`, and `runAppleSiliconEngine`, each
`Env -> EngineRequest -> IO (Either Text EngineRun)`
([`src/JitML/Engines/HasEngine.hs:77-87`](../../src/JitML/Engines/HasEngine.hs)). Any caller holding
an `Env` executes on the device with no gate. Those three functions are the "raw launch paths" §5
proposes retiring, and the document never names them. `EngineRequest` carries only a `KernelFamily`
and an input vector, so it also has no field to which a granted device identity could bind.

### 4.4 Container rendezvous

§5 states that the container "coordinates with the host only if the host root is mounted at the same
path inside it." The specification requires more: *"A bind mount is accepted only when file identity
proves that it exposes the exact host objects. A guest-local file with the same pathname is never
equivalent."* Path equality is necessary, not sufficient, and the document states the insufficient
condition as though it were the test.

The framing also omits that `compose.yaml` already mounts path-preservingly (`working_dir: ${PWD}`,
`.:${PWD}`), and that per [CLAUDE.md](../../CLAUDE.md) the apple-silicon lane runs host-native, so
the container framing does not cover the lane with the most direct host contention.

## 5. Governance defects

**The all-device bullet contradicts closed phases.** `NVIDIA_VISIBLE_DEVICES=all` is a `✅ Done`
deliverable of
[phase-50](../../DEVELOPMENT_PLAN/phase-50-nvidia-runtimeclass-for-linux-cuda.md), restated in
[phase-59](../../DEVELOPMENT_PLAN/phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md),
and codified as target contract in both [cluster_topology.md](cluster_topology.md) and
[daemon_architecture.md](daemon_architecture.md). Calling it a "correctness debt" without citing
those closures, and without a phase reopening them, is the case
[../documentation_standards.md](../documentation_standards.md) governs directly: governed docs are
reconciled to the plan when current-state claims conflict. The underlying concern is sound and the
specification agrees (*"The protocol forbids an all-devices launch"*), so the remedy is to reopen or
supersede the deliverable, not to assert a debt in prose.

**The mandatory `## Current Status` section is missing.**
[../documentation_standards.md](../documentation_standards.md) makes it mandatory when implemented
behavior and target direction appear in the same document. The reviewed document mixes them
throughout: current state in §1, §4 and most of §5; target in §2 and §3. It has no such section, and
it cannot have a conforming one, because the standard requires linking the owning phases and §5
states that none exist.

**§4 and §5 are parallel status ledgers.** The standards keep mutable status, closure criteria, and
dependency order in [../../DEVELOPMENT_PLAN/](../../DEVELOPMENT_PLAN/README.md) and list a parallel
status ledger inside a topic doc as an anti-pattern. §4 is a four-item open-defect list, §5 a
four-item open-question list, and §5's first bullet is a direct negative assertion about plan
coverage. Peer documents delegate explicitly — [run_contract.md](run_contract.md) and
[product_completion_contract.md](product_completion_contract.md) each disclaim status ownership in
their own text. The reviewed document delegates nowhere and links to the plan zero times.

**The body contains no links.** Its only in-repo link is the `Referenced by` metadata field. It
paraphrases material owned by [cluster_topology.md](cluster_topology.md),
[run_contract.md](run_contract.md), and [jit_codegen_architecture.md](jit_codegen_architecture.md)
without citing any of them, against the standards' rule that owned content is cited rather than
restated. Every jitML artifact it discusses is named in English ("the workload renderer", "the
config map", "Engine entry points") rather than by module path, which is why none of its claims is
checkable without the grep work behind this review.

**The index classification is incoherent.** [README.md](README.md) files the document under
Cross-Project Contracts, a category it defines as "mirrored with sister repositories". The document
states at its head that "no dependency on another project is created by writing it".
[pulsar_ml_workflow.md](pulsar_ml_workflow.md) satisfies the category — it names its sibling file
and is shared verbatim. This one does not.

**`jitml docs check` does not catch any of the above.** The gate verifies the presence of the five
metadata field prefixes, generated-section marker consistency, naming, and taxonomy
([`src/JitML/Docs/Check.hs:310-334`](../../src/JitML/Docs/Check.hs)). It does not validate the
`Status` value against the enum, require `## Current Status`, or check link density. A passing gate
is a floor, not evidence of conformance.

## 6. What the document states correctly

- **Its own status.** "Not adopted", "no phase owns the work", and "its authority is the installed
  root, never a copy of a document in any repository" are all accurate, and the last is faithful to
  the specification's conformance boundary. No file under
  [../../DEVELOPMENT_PLAN/](../../DEVELOPMENT_PLAN/README.md) references the document.
- **§1's Apple claim.** Confirmed at
  [`src/JitML/Prerequisite/Nodes/Cluster.hs:96-110`](../../src/JitML/Prerequisite/Nodes/Cluster.hs);
  the source comment says so outright. Understated in the three ways given in [§3.2](#32-the-named-seam-is-not-on-the-bring-up-path).
- **§4's Job bullet.** Confirmed: `renderJobMountedRunConfig`
  ([`src/JitML/Service/Workload.hs:1736-1782`](../../src/JitML/Service/Workload.hs)) emits
  `restartPolicy`, runtime class, placement, containers, env, and volumes, and no `resources:` block,
  while [`chart/local/jitml-service/templates/deployment.yaml`](../../chart/local/jitml-service/templates/deployment.yaml)
  renders requests and limits. Phase 51 closed the platform half only, scoped to `chart/local/*`.
  This is the one item that is both accurate and genuinely unowned.
- **§5's registry claim.** Confirmed: `HostWorkloadRegistry` stores `TVar RegistryState`
  ([`src/JitML/Service/HostWorkloadRegistry.hs:198`](../../src/JitML/Service/HostWorkloadRegistry.hs)).
- **§2's retained-output paragraph.** Correct, and consistent with the specification's treatment of
  receipts and tombstones as storage-accounted protocol state.
- **The whole-device tradeoff in §2.** Correctly identified as a product decision this project owes.
  Worth noting the specification narrows it: strict concurrency requires distinct MIG GPU Instances,
  and on unpartitioned hardware participants take turns under a whole-device lock.

## 7. The empirical mismatch

The plan records the shared-host failures this project has actually hit, and none is within reach of
the proposed seam:

- [DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md) and
  [phase-187](../../DEVELOPMENT_PLAN/phase-187-linux-no-caveat-runtime-and-browser-lane.md): Apache
  BookKeeper went read-only under co-tenant disk pressure — worked around by raising the bookie disk
  usage threshold on the jitML clusters only, which raises this project's own tolerance rather than
  reducing its demand — and a co-tenant disk-full event was ridden out.
- [phase-65](../../DEVELOPMENT_PLAN/phase-65-reflected-dhall-schema.md): a Docker image-store rebuild
  flake attributed to this shared host.

All three are storage and image-store contention that developed during operation. A one-shot
admission check at bring-up cannot observe progressive disk exhaustion by a co-tenant, so even a
correctly attached claim at the §3 seam would not have prevented any of them.

The document also omits what the specification says about this project's primary lane. The Darwin
row states that native Darwin has no accepted aggregate descendant-RAM wall, and the Apple Metal row
offers only an exclusive device token plus admission and detection guidance, refusing any authority
that requires a hard wall. Adoption would give the Mac lane cross-project device exclusivity — a
real gain — but not a memory bound. A reader of §1 and §3 would reasonably conclude the opposite.

## 8. Recommended disposition

1. **Re-anchor on the specification.** Replace the ledger vocabulary with *host coordination root*,
   *layout*, *resource cell*, and the `ParentScopeId` / `ClaimKey` / `Lease` / `ExecutionAuthority`
   chain. Delete the `Persistent` / `Transient` taxonomy and the `spec-version` sentence. Restate §2
   as requirement derivation: persistent baseline plus maximum concurrent transient, replicas
   multiplied. Add the four adoption obligations currently omitted — lease anchor, claim
   idempotency, walls rendered from authority rather than free text, and the Windows caveat. State
   the Darwin coverage limit plainly.
2. **Correct §3.** Say that the prerequisite is `jitml doctor`-only, and name both an acquire seam
   inside the rollout path and a release seam. Cite `writePointerCasLocal` as the cross-process lock
   pattern the repository already has.
3. **Move §4 and §5 into the plan.** One phase reopening the all-device deliverable, one owning the
   Job `resources:` gap, one owning the retirement of the three `run*Engine` escapes, and one raising
   the budget-dimension question against [run_contract.md](run_contract.md) as an amendment.
4. **Correct the budget claim** per [§4.1](#41-nothing-to-convert-into-a-charge) — the arithmetic
   exists and one of the two candidate charge bases is already implemented.
5. **Close the governance gaps**: add `## Current Status` once the phases exist, add body citations,
   and reclassify in [README.md](README.md).
6. **Mirror the vocabulary correction in `infernix`**, whose participation record is a structural
   twin carrying the same invented terms.

An independently worthwhile change, needing no protocol: this repository requests the
`nvidia.com/gpu` extended resource nowhere, so no allocator exists to defeat. Requesting it and
dropping the hardcoded device environment — letting the device plugin inject the granted identity —
delivers real in-cluster allocation today, and matches the specification's rule that Kubernetes
requests and device-plugin resources are render targets of an already admitted cell. It touches the
three renderers, and the assertions in `test/integration/Main.hs` and `test/daemon-lifecycle/Main.hs`
that currently pin the environment variable's presence.
