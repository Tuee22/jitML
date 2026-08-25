# Shared Host Resource Protocol — Review of the 2026-08-25 Rewrite

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: N/A — this file sits at the repository root and is not indexed
**Generated sections**: none

> **Purpose**: Record the verified findings of the 2026-08-25 review of
> [documents/engineering/shared_host_resource_protocol.md](documents/engineering/shared_host_resource_protocol.md)
> as rewritten at `f1d6790`, separating what that document states correctly from what conflicts
> with the authoritative external specification, this codebase, and
> [the plan](DEVELOPMENT_PLAN/README.md).

## Current Status

Nothing in this review is implemented. The reviewed document is unchanged at `f1d6790`, remains
unadopted, and no phase in [DEVELOPMENT_PLAN/](DEVELOPMENT_PLAN/README.md) owns any remedy in
[§14](#14-recommended-disposition) — so this section cannot link owning phases, and says so rather
than omitting the requirement. Creating those phases is step 2 of the recommended disposition.
Findings describe implemented behaviour as of `f1d6790`; §14 is a recommendation, not a contract.

**Placement caveat.** This file is at the repository root under an ALL-CAPS name.
`governedMarkdownPaths` ([`src/JitML/Docs/Check.hs:117-125`](src/JitML/Docs/Check.hs)) covers only
`README.md`, `AGENTS.md`, `CLAUDE.md`, `DEVELOPMENT_PLAN/**`, and `documents/**`, so nothing here is
checked by `jitml docs check`, and
[documents/documentation_standards.md](documents/documentation_standards.md) §6 permits only
`AGENTS.md`, `CLAUDE.md`, and `LICENSE` as ALL-CAPS root names. The metadata block above is
therefore a courtesy, not a satisfied gate. This is the same placement a prior review took at
`27cae53`, and it is worth knowing that the placement itself removes the file from governance.

## 1. Scope and method

Every claim in the reviewed document was checked against source, chart, Dhall, compose, test, and
plan files in this repository, and against the authoritative external specification and its two
sibling copies. Independent readers produced the verdicts; each was re-derived from the current
tree before any prior review was consulted. File and line citations are as of `f1d6790`.

**The authoritative specification** is
`amoebius/documents/engineering/shared_host_resource_protocol.md` — titled **Finite Resource
Execution Authority Protocol**, `**Status**: Authoritative source`, 869 lines, commit `d618ede`
(2026-08-24 14:38:11 -0400). A body-identical copy lives at
`hostbootstrap/documents/engineering/shared_host_resource_protocol.md` (854 lines), but it is marked
`**Status**: Draft` and is **untracked** in that repository — it has no commits. The two bodies are
identical from the `## TL;DR` heading onward; only the header block differs. References below to
"the specification" mean the amoebius copy, and line numbers are amoebius line numbers. **For the
hostbootstrap copy, subtract 15 from any line number ≥ 26.**

The specification's stated purpose names this project directly:

> Define one project-neutral, daemonless target protocol that `amoebius`, `infernix`, `jitML`, and
> `hostbootstrap` independently re-derive to reserve and enforce finite host-resource envelopes
> without importing one another's implementation.

That matters for the framing of everything below. The specification **expects** each participant to
keep its own local derivation rather than importing a shared package. The defect found here is not
that jitML holds a local record. It is that the local record diverges on every constant that has to
match for coordination to occur at all, and on four semantic properties that decide what the
protocol *is*.

## 2. Verdict summary

| Section | Claim | Verdict |
|---------|-------|---------|
| §1 | "No code in this repository reads or writes the ledger, and no command depends on it" | **Confirmed** |
| §1 | Root is `$HOME/.hostclaim` / `%UserProfile%\.hostclaim`, "a per-user root" | **Refuted** — [§3.1](#31-constants-that-must-match-and-do-not) |
| §1 | Authority is the installed root and "the `spec-version` the root carries" | **Refuted** — the specification forbids a versioned root |
| §1 | The resolution rule "admits no configuration" | **Refuted in effect** — it makes two of three lanes non-participating, [§6](#6-following-its-own-resolution-rule-produces-the-failure-it-warns-against) |
| §2 | "A per-user root holding one fixed-size record per claim, plus a budget the operator edits" | **Refuted** — [§3.1](#31-constants-that-must-match-and-do-not) |
| §2 | "There is no privileged installer, no signing ceremony, and no key custody" | **Refuted** — contradicts `root:finite-resource-authority` `0770` + installer |
| §2 | "Free is a positive value a writer must deliberately produce" | **Refuted** — no analogue; the specification's freshness rule is the opposite |
| §2 | "Conflicts are a prefix test over opaque identifiers … adding hardware costs no revision" | **Refuted** — disjoint cells + hierarchical locks; new hardware mints a new epoch |
| §2 | `Transient` / `Persistent` are the two claim kinds | **Refuted** — requirement arithmetic, not a taxonomy |
| §3 | "No limit is applied and no device is fenced" | **Refuted** — negates the specification's central guarantee |
| §3 | Advisory between cooperating programs; no defence against a non-participant | **Confirmed** as a scoped truth the specification also states |
| §4 | "Work directed at releasing a claim … is never refused" | **Refuted** — absent from the specification; cleanup is a charged phase |
| §4 | The deadlock argument itself | **Sound as design reasoning**, resolved differently upstream |
| §5 | "Admission is taken once … cannot observe progressive consumption" | **Refuted** — re-observation after locks; live bundle growth forbidden |
| §5 | Progressive contention is what a shared development machine produces most often | **Confirmed** by this project's own incident record |
| §6 | Observation binds a peer that never opted in; ledger covers processless capacity | **Confirmed** as reasoning; **both mechanisms are unimplemented here** |
| §7 | Three adoption obligations ("name the seams", "derive the charge once", "establish release evidence") | **Refuted as the obligation set** — the specification assigns jitML five different ones |
| §7 | "Derive the charge once … converts that figure rather than authoring a second one" | **Sound, and largely unmet** — [§8](#8-derive-the-charge-once-has-very-little-to-derive-from) |
| §7 | "A record nothing consults" (closing line) | **Self-describing** — [§10.3](#103-nothing-consults-it-including-by-its-own-closing-rule) |
| Header | `**Status**: Draft`; no `## Current Status`; zero body links | **Non-conforming** — [§11](#11-governance-defects) |

## 3. The document describes a different protocol

This is not a wording problem, and it is not drift. Two documents that disagree about the root path,
the record format, the conflict test, and whether limits are enforced are not two summaries of one
protocol.

### 3.1 Constants that must match, and do not

| Topic | Specification | Reviewed document |
|---|---|---|
| Noun for the shared store | "host coordination root" (L222, L263, L781, L795, L806); `ledger` × **0** | "the ledger" × **10** |
| Linux root | `/var/lib/finite-resource-authority` (L223) | `$HOME/.hostclaim` (L18) |
| Darwin root | `/Library/Application Support/FiniteResourceAuthority` (L224) | `$HOME/.hostclaim` (L18) |
| Windows root | `FOLDERID_ProgramData` via the Known Folder API + `FiniteResourceAuthority` (L225-226) | `%UserProfile%\.hostclaim` (L19) |
| Ownership | `root:finite-resource-authority`, dir `0770`, file `0660` (L228-229) | "A per-user root" (L28) |
| Installer | "The installer initializes this finite set" (L245) | "There is no privileged installer" (L30) |
| Enrolment | finite operator-reviewed `ParentScopeId` registration (L130) | "creating one directory named after it" (L30) |
| Version | "Protocol version lives inside the layout and journal, **never in the root or lock pathname**" (L256-258) | "the `spec-version` the root carries" (L20) |
| Record | deterministic CBOR (L248-250); one `allocations/parents/<digest>.cbor` per **scope** (L240); "`ClaimKey` never selects or creates a pathname" (L244-245) | "one fixed-size record per claim" (L28) |
| Locks | five classes — `epoch.lock`, `admission.lock`, `parents/<digest>.lock`, `resources/<kind>/<digest>.lock`, Windows `boot-init.lock` (L242, L345) | "a single lock that serializes admission" (L29) |
| Operator budget | no such file; an immutable `layout.cbor` catalog, changed only by epoch mutation under exclusive `epoch.lock` (L239, L197-204, L320-328) | "a budget the operator edits" (L28) |
| Conflict test | disjoint resource cells + hierarchical ancestor/leaf locks over **resolved** domains (L148-151, L266-271); "one unresolved reference rejects the layout" (L140-141) | "a prefix test over opaque identifiers" (L42) |
| New hardware | "Changing any capacity, partition identity, wall mechanism, or cell membership creates a new epoch" (L204) | "adding hardware costs no revision" (L43) |
| Claim kinds | none. `persistent`/`transient` are requirement arithmetic: "persistent baseline plus transient work uses `persistent + maximum concurrent transient`" (L186) | "Each claim declares one of two kinds" — `Transient` / `Persistent` (L45-48) |
| Core vocabulary | `ProjectId`, `ParentScopeId`, `ClaimKey`, `Lease`, `AppliedEnvelope`, `ExecutionAuthority`, `ResourceReceipt`, `HostLayout`, resource **cells**, `Phase`, `Strength`, `DomainKind` (L121-135, L481-566) | none of these appear |

Counts in the reviewed document, verified by grep: `ledger` 10, `hostclaim` 2, `spec-version` 1,
`hostbootstrap` **0**, `amoebius` **0**, `coordination root` **0**, `resource cell` **0**.

The specification's own enumerations, for contrast with the invented two-kind taxonomy:

- `data Strength = DetectionOnly | AdmissionOnly | ReactiveTermination | BoundedShared | HardCeiling | ExclusiveUse | ReservedAndCeilinged | HardwarePartitioned` (L496-497)
- `data Phase = Leased | Enforced | Running | Releasing` (L500)
- `data DomainKind = HostDomain | CpuPartition | StorageVolume | MetalDevice | CudaDevice | MigGpuInstance` (L492-494)
- durable states `Prepared -> Applied -> Running -> Releasing -> Retired`, plus `Recovering`, `Quarantined` (L299-300)

### 3.2 Four semantic contradictions

These decide what kind of thing the protocol is, and the two documents answer them oppositely.

**Enforcement.** The specification's central guarantee (L90-93):

> Participating project code cannot launch a governed operation unless the complete requirement fits
> one unallocated host cell, every lock target is an observed domain of that exact host, and a
> **matching enforcement or exclusivity mechanism has been applied and re-observed** for every
> resource the operation can consume.

and (L41-42): "A reservation without a wall and a wall without a reservation are both insufficient."

The reviewed document, §3 (L54-55): "**No limit is applied and no device is fenced.** A participant
that declares four gibibytes and then allocates twelve is not detected."

That is the negation of the guarantee. The reviewed document describes an **advisory declaration
registry**; the specification describes an **applied-and-read-back enforcement gate**.

**Progressive consumption.** The reviewed document, §5 (L75-81): "Admission is taken once, when the
claim is made. It cannot observe a participant that declares honestly and then consumes
progressively … This is a real limit, not a gap awaiting a patch."

The specification forbids exactly this and re-checks: "every lock operation is nonblocking and lock
upgrades or expansion of a live bundle are forbidden" (L258-259); `Lease` "cannot authorize … live
bundle growth" (L132); "Immediately before lock acquisition **and again after the locks are held**,
the interpreter observes physical capacity, VM pledges, foreign claimants, available storage, and
the lane's health interlocks" (L208-211); "attempted live bundle growth" is a required refusal
vector in the conformance corpus (L807); "different child authorities never sum beyond their one
held parent and cannot acquire or grow host locks" (L822).

**Release-directed work.** The reviewed document devotes §4 (L64-71) to a rule that is **absent**
from the specification: greps for `release-directed`, `always admissible`, and `deadlock` return
zero. The specification solves the same problem differently — cleanup is a **charged phase inside
the admitted requirement**, so it is pre-funded rather than exempted ("a phase DAG enumerates every
dependency-valid concurrency epoch, including separate compile, link, test, container, VM, device,
recovery, evidence-retention, and cleanup stages", L187-188) — and release runs under the
already-held lease (L295-297): "On terminal outcome, stop and reap owned work, prove each
enforcement domain empty, retire the durable record, synchronize its directory, then release
resource locks, parent-scope lock, and epoch lock in that order."

**Fail-closed decode.** The reviewed document, §2 (L34-37): "Free is a positive value a writer must
deliberately produce. A truncated file, an unfamiliar revision, and a corrupted byte all decode as
occupied." No analogue exists in the specification, whose freshness rule points the other way
(L285-287): "An unlocked record is not enough to declare a resource free: the bound cgroup, VM,
mount, process group, Job Object, or device use must be proven absent or empty."

### 3.3 The charitable reading, and why it does not rescue the document

One could read the document as describing a deliberately simpler, jitML-local mechanism rather than
summarising the Finite Resource Execution Authority Protocol. Three things foreclose that reading:

1. §1 uses the definite article for an installed artefact — "the shared host claim ledger" — and
   asserts that its authority is "that installed root", presupposing one specific installed thing.
2. The specification names `jitML` as one of four adopters and carries a jitML adoption row
   ([§4](#4-it-ignores-the-obligations-the-specification-assigns-jitml-by-name)).
3. Only one host-coordination initiative exists in this family.

If an independent mechanism *is* the intent, that is a legitimate choice — but it needs a different
filename and title, and it needs reconciling with the specification that names jitML as an adopter,
because two projects publishing incompatible root paths is the precise failure both documents say
the mechanism exists to prevent.

## 4. It ignores the obligations the specification assigns jitML by name

The specification has a **Project adoption boundaries** section (L762-775) with one row per project.
The `jitML` row (L768) reads, verbatim:

> | `jitML` | Compiled training/inference graph, replica and tuning concurrency, workload/job
> rendering, result evidence | Derive persistent plus peak-transient requirements; multiply parallel
> tuning/jobs; keep a lease anchor for persistent clusters; render every CPU/RAM/storage/GPU wall and
> exact granted device identity from authority rather than free text; advertise Windows only after
> its native adapter conforms |

Five obligations, none of which appears in the reviewed document. The specification also states this
project's current gap directly (L745):

> Logical counts are not yet folded into one physical CPU/RAM/storage/VRAM peak; local POSIX/CAS
> locks and Kubernetes values do not arbitrate the host or supply reboot epochs.

That assessment is accurate ([§8](#8-derive-the-charge-once-has-very-little-to-derive-from),
[§9](#9-the-lease-anchor-is-the-obligation-jitml-structurally-cannot-meet)).

The reviewed document's §7 instead authors three obligations of its own — "Name the seams", "Derive
the charge once", "Establish release evidence" — and prefaces them "none of them is stated here for
any particular one" (L100). Only the second loosely tracks a real obligation. The specification's
cross-cutting obligations are also absent: "No adapter exports its lease constructor, applied-wall
constructor, raw interpreter, or unrestricted spawn function" (L773-775); keep raw
process/VM/container/K8s/accelerator launch primitives behind a strict interpreter and "mechanically
reject bypasses" (L106-111); the interoperability freeze and repository-local ABI digest gate
(L777-792); the conformance corpus and live acceptance rows, where "A repository with no live row
for a mechanism advertises no conformance for that row" (L839).

## 5. It is not a jitML document

`documents/engineering/shared_host_resource_protocol.md` in this repository is **byte-identical** to
`infernix/documents/engineering/shared_host_resource_protocol.md` apart from three hunks: the
`**Supersedes**` / `**Generated sections**` metadata lines, the `**Referenced by**` target, and the
substitution of "jitML" for "Infernix" in the purpose line. The two were committed within eight
seconds of each other (jitML `f1d6790` at 07:42:04, infernix `53ad994` at 07:41:56).

The document's stated purpose is "Record what participation in the shared host claim ledger would
mean **for jitML**, and what adopting it would require." No sentence in §§2–7 concerns jitML. §7
concedes the point in its own words (L99-100): "Three obligations hold for any participant, and
**none of them is stated here for any particular one**."

The rewrite at `f1d6790` fixed the previous version's false claims about jitML by removing every
claim about jitML. The index row was de-jitML-ified in the same commit — the prior row named
concrete commitments (a `Persistent` claim for the retained cluster footprint, the cluster
host-memory prerequisite, the all-device and raw-launch debts); the new row names only generic
protocol properties.

## 6. Following its own resolution rule produces the failure it warns against

§1 (L18-24) states the rule and its rationale:

> Every participant resolves one fixed path and no other: `$HOME/.hostclaim` on Linux and Darwin,
> `%UserProfile%\.hostclaim` on Windows. … The path is never repository-relative, never
> version-suffixed, and never selected by an environment variable. Two participants that resolve
> different paths silently fail to coordinate, which is the one failure the ledger exists to
> prevent, so the resolution rule admits no configuration.

Per [CLAUDE.md](CLAUDE.md), the `linux-cpu` and `linux-cuda` lanes run inside the project container.
Its entire mount surface is two entries ([`compose.yaml:7-10`](compose.yaml)):

```yaml
  working_dir: ${PWD}
  volumes:
    - .:${PWD}
    - /var/run/docker.sock:/var/run/docker.sock
```

`$HOME` is not mounted. The image is `FROM ubuntu:24.04` with **no `USER` directive** and roots its
toolchain under `/root` ([`docker/Dockerfile:1,21`](docker/Dockerfile)), and every invocation is
`docker compose run --rm` ([`bootstrap/_lib.sh:244-271`](bootstrap/_lib.sh)). So the rule resolves:

- host: `/Users/<user>/.hostclaim`
- container: `/root/.hostclaim` — unmounted, per-invocation overlay state, destroyed by `--rm`

Two roots that never coordinate, produced by following the rule faithfully — the exact failure §1
names as the one to prevent. §1's own prohibition on environment-variable selection forecloses the
only configuration-level fix. And a `Persistent` claim taken inside the container for something that
outlives it — a Kind cluster, retained bytes — is lost with the container, which is §7's
"`Persistent` claim released without evidence is worse than no claim" case.

The specification addresses this directly (L234-238), and the reviewed document does not mention it:

> A container, WSL guest, or VM delegates leasing to a host-side project anchor. A bind mount is
> accepted only when file identity proves that it exposes the exact host objects. A guest-local file
> with the same pathname is never equivalent, and a WSL `flock` cannot arbitrate a Windows
> `LockFileEx` resource.

This repository already solved the analogous problem for its own state by mounting path-preservingly
(`.:${PWD}` plus `working_dir: ${PWD}`), recorded at
[documents/engineering/cluster_topology.md:573-575](documents/engineering/cluster_topology.md). The
previous version of the reviewed document at least raised the container question; the rewrite
deleted it.

Separately, the document mandates a Windows path for a project whose substrates are
`AppleSilicon | LinuxCPU | LinuxCUDA` ([`src/JitML/Substrate.hs:40-44`](src/JitML/Substrate.hs)).
There is no Windows lane. The specification's jitML row already handles this — "advertise Windows
only after its native adapter conforms" — which is the statement the document owed instead.

## 7. Every jitML fact that would make the argument concrete is missing

The document contains no module path, no type name, no command, and no in-repo link. Its only link
is the `**Referenced by**` metadata field. It never names `hostbootstrap`, `amoebius`, or the
specification's title, so a reader cannot reach the authority it defers to — while other governed
docs do name the owner ([documents/documentation_standards.md:24,166](documents/documentation_standards.md),
[documents/engineering/durable_state_dsl.md:12](documents/engineering/durable_state_dsl.md)).

Meanwhile the repository contains, uncited, a direct instance of nearly every abstraction it
introduces:

| The document says | This repository has |
|---|---|
| "Every claim is created inside **one short critical section**" (L38) | `writePointerCasLocal` ([`src/JitML/Checkpoint/Store.hs:3525-3581`](src/JitML/Checkpoint/Store.hs)) — `openFd` + `waitToSetLock`, `bracket` for `closeFd` and `bracket_` for `Unlock`, documented "Cross-process local compare-and-swap", plus `localPointerCasProcessLock :: MVar ()` (`:3583-3588`) for the intra-process level POSIX record locks do not supply. Second instance: `casPointerBytes` ([`src/JitML/Service/FilesystemMinIO.hs:208-241`](src/JitML/Service/FilesystemMinIO.hs)) |
| "host configuration … in the same category as an `/etc` file or **a port assignment**" (L17-18) | `leaseEdgePort` ([`src/JitML/Cluster/EdgePort.hs:41-60`](src/JitML/Cluster/EdgePort.hs)) walks `[9090, 9091, 9092]` and binds to test; its own comment (`:36-39`) says the socket closes immediately so the lease "is purely a 'this address is bindable right now' probe" — a TOCTOU-racy advisory host claim |
| "**No limit is applied and no device is fenced**" (L54) | `NVIDIA_VISIBLE_DEVICES=all` from three producers ([`src/JitML/Service/Workload.hs:1685-1692`](src/JitML/Service/Workload.hs), [`src/JitML/Service/ConfigMap.hs:154-163`](src/JitML/Service/ConfigMap.hs), [`chart/local/jitml-service/templates/deployment.yaml:81-87`](chart/local/jitml-service/templates/deployment.yaml)), with `nvidia.com/gpu` requested **nowhere** in the repository and no device plugin — so the scheduler will co-schedule unbounded CUDA pods onto one GPU node. Placement is `RuntimeClass` node-selection only |
| "Two independently authored figures **drift, and the drift is silent**" (L107) | Already true here: the `jitmlService` budget is authored in `dhall/cluster/resources.dhall`, hardcoded a second time as literal YAML in [`chart/local/jitml-service/templates/deployment.yaml:73-80`](chart/local/jitml-service/templates/deployment.yaml) (tied only by a comment), and dropped entirely by the Haskell renderer, which reads only `budgetReplicas` from `ClusterResources` ([`src/JitML/Service/ConfigMap.hs:15-19,223-231`](src/JitML/Service/ConfigMap.hs)) |
| Claims are **acquired** in a short critical section (L38) | This project's one host-global filesystem act is the reverse: `prepareKindKubeconfigFiles` ([`src/JitML/Bootstrap.hs:2008-2015`](src/JitML/Bootstrap.hs)) unconditionally **deletes** `/tmp/jitml-kind-create-<substrate>.kubeconfig.lock` — a `client-go` lock belonging to another program — on the live rollout path (sole caller `Bootstrap.hs:1746`, inside `executeRequiredReconcile`) |
| "keeps **observing the machine** and says so" — the stated fallback (L111) | **Not implemented.** No `pgrep`, `ps`, `docker stats`, `docker ps` inventory, or host memory-pressure probe at any admission point anywhere in `src/` or `app/`. Neither of §6's two mechanisms exists in this project |

That last row matters for §7's closing sentence. The document offers a fallback — a participant that
cannot meet the obligations "keeps observing the machine and says so" — that this project also does
not do.

The one host admission seam that does exist is `HostWorkloadRegistry`
([`src/JitML/Service/HostWorkloadRegistry.hs:197-199`](src/JitML/Service/HostWorkloadRegistry.hs)):
a single `TVar`, created only on Apple host Engines
([`src/JitML/Service/Command.hs:516-522`](src/JitML/Service/Command.hs)), keyed on
`(family, experiment hash)` identity rather than on capacity, and dying with the process. Two
workloads under different hashes are both admitted regardless of host RAM or GPU. It sits *above*
the engine entry points — nothing in `src/JitML/Engines/` references it. The document never mentions
it, though it is precisely the process-scoped case its `Transient`/`Persistent` distinction is about.

## 8. "Derive the charge once" has very little to derive from

§7's second obligation reads: "A participant that already computes what it needs converts that
figure rather than authoring a second one." For this project, the premise is mostly false today.

- **`TrainingBudget`** ([`src/JitML/Training/Budget.hs:124-136`](src/JitML/Training/Budget.hs)) is a
  work-completion counter. `BudgetKind = SupervisedEpochBudget | RlEnvironmentStepBudget |
  AlphaZeroSelfPlayBudget | TuningTrialBudget`; units are `"epochs"`, `"environment-steps"`,
  `"self-play-generations"`, `"trials"` (`:615-622`). No CPU, memory, storage, device, or wall-clock
  dimension. That is deliberate — [run_contract.md](documents/engineering/run_contract.md) records
  that the traditional-RL budget has no optimizer-update quantity because the removed field could
  not be compared dimensionally — so adding physical axes there is an amendment against a contract,
  not a defect in it.
- **`dhall/project/Schema.dhall:36-38`** defines `Budget = { cpu : Natural, memory : Natural, storage
  : Natural }` and `PodResources = { replicas, cpuLimit, memoryLimit }`, with `totalCpu`/`totalMemory`
  (`:99-105`), `fitsWithin`/`storageFitsWithin` (`:107-119`), conjoined in `contractOK` (`:144-149`)
  and asserted at type-check — but via the **generated** `jitml.dhall`, which inlines
  `assert : contractOK self === True` ([`src/JitML/Project/Config.hs:293`](src/JitML/Project/Config.hs)),
  not inside `Schema.dhall` itself. Every quantity is a bare `Natural` with **no unit stated
  anywhere**, so there is nothing to convert *from* without inventing one.
- **`dhall/cluster/Schema.dhall:6-27`** gives nine platform components a `ComponentBudget` carrying
  `cpuRequest`, `cpuLimit`, `memoryRequest`, `memoryLimit` — all `Text` (`"500m"`, `"2Gi"`), never
  parsed into a numeric dimension; they are decoded
  ([`src/JitML/Cluster/Resources.hs:76-81`](src/JitML/Cluster/Resources.hs)), re-rendered back into
  Dhall (`:197-210`), and never reach a rendered container spec from Haskell.
- **The one genuinely convertible figure** is `nodeMemoryMiB`, already converted:
  `nodeMemoryBytes res = toInteger (nodeMemoryMiB res) * 1048576`
  ([`src/JitML/Cluster/Resources.hs:212-214`](src/JitML/Cluster/Resources.hs)), applied as
  `docker update --memory <bytes> --memory-swap <bytes> --cpus <nodeCpus>` (`:230-245`), defaults
  `12288` MiB / `"4"` CPUs (`:106-107`).

So the specification's assessment — "logical counts are not yet folded into one physical
CPU/RAM/storage/VRAM peak" — is exactly right, and the obligation is far heavier for this project
than §7's one-sentence phrasing suggests. A correction is also owed to the *previous* version of the
document, which claimed there is "nothing to convert into a charge": that was too strong, since
`ComponentBudget` and `nodeMemoryMiB` exist; but "convert an existing figure" is too weak, since
only one of them has a unit.

A related defect, worth a phase of its own: **generated Jobs render no `resources:` block at all.**
`renderJobMountedRunConfig` ([`src/JitML/Service/Workload.hs:1737-1783`](src/JitML/Service/Workload.hs))
emits `restartPolicy`, runtime class, placement, containers, env, and volumes, and no resources — while
the installed subcharts do render requests and limits
([`chart/local/jitml-service/templates/deployment.yaml:73-80,124-130`](chart/local/jitml-service/templates/deployment.yaml)).
The heaviest work is the least bounded. (The generated root-chart Deployment
`chart/templates/deployment-jitml-service.yaml` also renders none; whether that file is ever
installed is unresolved — no `HelmRelease` in `phasedReleases`
([`src/JitML/Cluster/Helm.hs:73-96`](src/JitML/Cluster/Helm.hs)) resolves to the root `chart` path.)

## 9. The lease anchor is the obligation jitML structurally cannot meet

The specification requires "a lease anchor for persistent clusters" (L768) that outlives the
invoking CLI and acquires its own locks:

> A Kind cluster, VM, host daemon, validation matrix, or training service cannot borrow the invoking
> CLI's lifetime. One project-owned per-parent-scope anchor starts first and acquires every lock
> itself before creating a domain; no process unlocks and transfers custody.

Nothing in this repository can hold one:

- `Prerequisite` carries `checkNode :: IO Bool`
  ([`src/JitML/Prerequisite/Types.hs:17-24`](src/JitML/Prerequisite/Types.hs)) — a stateless boolean
  instant with no return payload, no handle, no lifetime, and no release counterpart.
- The only long-lived processes are in-cluster daemon Deployments
  ([documents/engineering/daemon_architecture.md](documents/engineering/daemon_architecture.md)),
  which cannot anchor the cluster that hosts them.
- `HostWorkloadRegistry` is per-process and non-durable ([§7](#7-every-jitml-fact-that-would-make-the-argument-concrete-is-missing)).
- The engine entry points take no grant:
  `runLinuxCpuEngine` / `runCudaEngine` / `runAppleSiliconEngine ::
  Env -> EngineRequest -> IO (Either Text EngineRun)`
  ([`src/JitML/Engines/HasEngine.hs:76-86`](src/JitML/Engines/HasEngine.hs)), where
  `EngineRequest = EngineRequest { engineRequestFamily :: KernelFamily, engineRequestInput :: [Float] }`
  (`:32-36`) has no field a granted device identity could bind to. The only gate is a visibility
  probe — `cudaRuntimeAvailable` ([`src/JitML/Engines/CudaLocal.hs:104-118`](src/JitML/Engines/CudaLocal.hs))
  and `metalRuntimeDeviceVisible` ([`src/JitML/Engines/MetalLocal.hs:117-131`](src/JitML/Engines/MetalLocal.hs)):
  "can I see a device", never "may I use it", and never "how much of it is free".

A `HasEngine` capability class does exist
([`src/JitML/Engines/HasEngine.hs:47-48`](src/JitML/Engines/HasEngine.hs)) and is called "the current
engine capability" by
[jit_codegen_architecture.md](documents/engineering/jit_codegen_architecture.md), but it is a
dispatch selector rather than an admission token, discharged at the boundary by the three concrete
escapes above.

## 10. Current-state claims in the document

### 10.1 Non-adoption — confirmed

Repository-wide greps (excluding `.git/`, `dist-newstyle/`, `.build/`, `node_modules/`, `.data/`)
return zero hits for `hostclaim`, `spec-version`, `ExecutionAuthority`, `FiniteResourceAuthority`,
and `ResourceReceipt` outside the document itself. Every `ledger` hit in `src/`, `chart/`, and
`dhall/` is Apache BookKeeper/Pulsar. No code reads or writes any such root; no command depends on
one. §1's claim is accurate.

Adjacent: this project resolves `$HOME`-rooted paths only to *read* foreign tooling config —
`~/.docker/config.json` ([`src/JitML/Bootstrap.hs:685-688`](src/JitML/Bootstrap.hs), which honours
`DOCKER_CONFIG`) and `~/.ghcup`
([`src/JitML/Prerequisite/Nodes/Toolchain.hs:75-83`](src/JitML/Prerequisite/Nodes/Toolchain.hs)). It
owns no `$HOME`-rooted state root of its own.

### 10.2 Nothing is implemented anywhere, and nothing is installed

No library, binary, installer, or CLI implementing the protocol exists in `amoebius`,
`hostbootstrap`, `jitML`, or `infernix`. Neither `~/.hostclaim` nor
`/Library/Application Support/FiniteResourceAuthority` exists on this machine, and no matching
binary, LaunchDaemon, or group is installed. The owning amoebius phases are all
`⏸️ Blocked — NOT VALIDATED`: phase 51 (portable fake-boundary interpreter) and phases 52–54 (Linux,
Darwin, Windows live kernel-mechanism evidence), as is their prerequisite phase 50. The
specification says as much itself (L26-27): "There is no common package, service, daemon, executable
policy document, or dependency on `hostbootstrap-core`."

Near-misses that should not be mistaken for implementations: `EngineExecutionAuthority` in infernix
is an in-process `MVar ()`; `closureClaimKey` in
[`src/JitML/Docs/Check.hs:38`](src/JitML/Docs/Check.hs) and
[`src/JitML/Lint/Docs.hs:41`](src/JitML/Lint/Docs.hs) are documentation-lint keys unrelated to the
protocol's `ClaimKey`.

### 10.3 Nothing consults it, including by its own closing rule

The document's only inbound reference in the entire repository is the index row at
[`documents/engineering/README.md:49`](documents/engineering/README.md). Four independent
zero-result greps across all 298 `DEVELOPMENT_PLAN/` entries (`hostclaim`, `host claim`,
`shared_host_resource`, `claim ledger`, `resource protocol`, `admission control`) confirm no phase
owns, mentions, or blocks on it. It is not on the plan's forward-only DAG at any position — not
Done, not Active, not Blocked, not Planned. (The 146 plan hits for "admission" are this project's own
checkpoint-store admission concept.)

Its closing sentence (L111-112) therefore describes itself:

> A participant that cannot meet these keeps observing the machine and says so, rather than writing
> a record nothing consults.

## 11. Governance defects

### 11.1 Three binding rules in this repository's own standard

[documents/documentation_standards.md](documents/documentation_standards.md) is
`**Status**: Authoritative source`. The document breaks three of its rules.

- **§4 (`:166-167`)** — "jitML **consumes** `hostbootstrap` for its host/bootstrap layer; this
  standard links to that repository for the bootstrap contract **rather than re-owning it**."
  §§2–6 re-own a foreign protocol in full.
- **§6 (`:206-208`)** — "**Never copy** configuration, source snippets, doctrine text, or the typed
  run-plan / delivery / lifecycle / evidence / journal shapes between docs — **cite the owner** … by
  section name/anchor." It copies doctrine text and cites no owner at all.
- **§3 (`:134-136`)** — "When current and target mix, a **`## Current Status`** section is
  mandatory: it states, succinctly, what is implemented today versus what the owning phase(s) will
  make true, and **links to the owning phase(s)**." §1 is a current-state claim about this
  repository; §7 is forward-looking. There is no such section, and it cannot have a conforming one,
  because no owning phase exists.

Also §6 (`:204`): "Each governed doc links to at least one other governed source." The body contains
zero links.

### 11.2 Its `Status` has no reachable terminal value

The closed set (`:88-92`) is `Authoritative source` ("This file is the canonical home (SSoT) for its
topic"), `Supporting reference` ("Index/navigation or secondary material that **links to a source of
truth**"), and `Draft` ("Not yet canonical"). `:101-103` adds: "forward/planned work is not a
document-status concept — it lives in the plan's phase status."

It cannot be `Authoritative source` — this project does not own the protocol. It fails
`Supporting reference` — it links to no source of truth. `Draft` is a transition with no defined
lifecycle, exit criteria, or dwell limit anywhere in the standard, which is itself a governance gap.
It is the **only `Draft` in the entire `documents/` tree** (18 `Authoritative source`, 4
`Supporting reference`).

### 11.3 The gate cannot catch any of this

`jitml docs check` ([`src/JitML/Docs/Check.hs:50-70`](src/JitML/Docs/Check.hs)) runs nine checks:
generated-section marker/content agreement, tracked generated paths, required metadata **prefixes**,
generated-section registry drift, a closure-phrase scan, phase-link resolution, orphaned generated
templates, `documents/` taxonomy, and `documents/` naming.

`topicRequiredFields` (`:320-327`) is a list of `(key, prefix)` pairs and the only test is prefix
presence — `headerField` (`:337-340`) returns the stripped remainder and **never compares it against
the closed `Status` enum**. `**Status**: Draft` passes; so would `**Status**: WIP`, which §12 of the
standard explicitly forbids. Note the asymmetry: `ProductSprintStatus` *does* get a parser
(`parseSprintStatus`, [`src/JitML/Product/PhaseStatus.hs:490-492`](src/JitML/Product/PhaseStatus.hs));
document `Status` gets none.

`checkDocumentPhaseLinks` (`:195-238`) keeps only link targets matching
`phase-<digits>-<lower-kebab>.md` and discards everything else; anchors are stripped and never
validated. Backlink reciprocity is deliberately not enforced (standard §13, `:387-388`). There is no
index-membership check, no `## Current Status` requirement, no link-density check, and no
cross-repo/no-duplication check.

A passing gate here is a floor, not evidence of conformance — and the standard says so: "The
mechanical documentation floor is the `JitML.Docs.Check` module."

### 11.4 Index defects

[`documents/engineering/README.md:44`](documents/engineering/README.md) files the document under
**Cross-Project Contracts**, a category the index header (`:15`) defines as "two **cross-project
contracts** mirrored with sister repositories", under a column headed "Shared contract". The row
(`:49`) reads "Not-adopted record of what participation … would mean", while the document itself
says "Writing it creates no dependency on another project." It is filed as a mirrored contract while
denying that it mirrors anything — and it *is* mirrored
([§5](#5-it-is-not-a-jitml-document)), just with infernix's copy of the same invented vocabulary
rather than with the specification.

The category's other member, [pulsar_ml_workflow.md](documents/engineering/pulsar_ml_workflow.md),
shows what the category means: `**Status**: Authoritative source`, referenced by seven documents
including plan phases, carrying a `## Current Status`, and naming its sibling file explicitly. Every
other row in both index tables describes an implemented or plan-owned subsystem, phrased as
ownership; this is the only row describing something the project does not do.

**Regression introduced by `f1d6790`:** `documents/engineering/README.md:14` still reads "fourteen
**project-specific** docs" while that table now has **13** rows. The commit deleted a row and did
not update the prose count. No check catches index/prose drift.

### 11.5 The commit history around this file

`eeabc7d` — the last substantive engineering commit (real Metal kernels: `MetalLayerTraining.hs`,
`MetalBridge.hs`, `LayerGraphDevice.hs`, phase 270/271 updates, `PhaseStatus.hs`) — also introduced
`documents/engineering/shared_host_resource_protocol.md` at **854 lines**, the external
specification's exact length. It arrived as a copy of a foreign spec bundled into an unrelated
commit, not as a phase deliverable.

Since then, the last six commits touch essentially nothing else — no source, no tests, no charts, no
plan:

| Commit | Change |
|---|---|
| `c0edaac` | 488-line `SHARED_HOST_RESOURCE_PROTOCOL.md` added at the repo root (ungoverned) |
| `70e2e61` | root file deleted; governed doc churns 1860 lines |
| `ed8364c` | 739-line `SHARED_HOST_RESOURCE_PROTOCOL_ANALYSIS.md` added at the root (ungoverned) |
| `2d10717` | 739-line analysis deleted; governed doc collapses by 1099 lines to ~91 |
| `ffe49ff` | new 350-line analysis added, correctly at `documents/engineering/…_analysis.md`, and indexed |
| `27cae53` | that analysis **renamed to the repo root**, zero content change — leaving `governedMarkdownPaths` and the doc checker's jurisdiction |
| `f1d6790` | analysis deleted outright; index row removed; protocol doc rewritten (189 lines) into its current form |

Two reviews written and removed, each with the reviewed document rewritten in the same or adjacent
commit, and a root-relocation step in between that took the second review outside governance with a
zero-content rename. The plan meanwhile stands at **59 Done / 1 Active / 0 Planned / 10 Blocked**
([DEVELOPMENT_PLAN/README.md:2825](DEVELOPMENT_PLAN/README.md), verified against
[`src/JitML/Product/PhaseStatus.hs`](src/JitML/Product/PhaseStatus.hs)), with Sprint `271.1`
"Metal Row Device Evidence" the single Active item.

The prior review's recommendations were not applied. Its verdict table marked as **Refuted** exactly
the vocabulary the rewrite retained and expanded: "Ledger vocabulary, `spec-version`,
`Persistent`/`Transient` claim kinds — absent from the specification."

## 12. What the document states correctly

- **Its own adoption status.** "No code in this repository reads or writes the ledger, and no
  command depends on it" is accurate ([§10.1](#101-non-adoption--confirmed)), as is the instinct in
  "its authority is that installed root … never a copy of a document in any repository, **including
  this one**." That sentence is faithful to the specification's conformance boundary — "similarly
  named files, copied Markdown, or locks do not establish compatibility" — and it is the sentence
  the rest of the document violates.
- **§3's declarations-versus-behaviour distinction** is honest, unusually well put, and the
  specification concedes a scoped version of it: "Advisory file locks do not constrain a
  same-privilege process that ignores the protocol" (L105-108), with a `Scope =
  ParticipatingProjects | WholeHost` index (L483). The error is applying it to the whole protocol
  rather than to the advisory-lock layer.
- **§4's deadlock argument** — that a protocol which can refuse teardown cannot release, and so
  contends with itself — is genuine design reasoning. The specification solves the same problem by
  charging cleanup at admission and releasing under the held lease, which is arguably better; but
  the problem is real and correctly identified.
- **§5's refusal to treat the progressive-consumption limit as a gap awaiting a patch** is the right
  instinct about scope discipline, even though the specification does address the participant side.
- **§6's observation-versus-declaration complementarity** is a real and useful distinction:
  observation binds a peer that never opted in but cannot see processless capacity; declaration
  covers processless capacity but not behaviour.
- **The whole-device tradeoff** raised in the previous version was correctly identified as a product
  decision this project owes. The specification narrows it: strict concurrency requires distinct MIG
  GPU Instances, and on unpartitioned hardware participants take turns under a whole-device lock.

The prose is disciplined throughout. The problem is not the writing.

## 13. The empirical mismatch

The plan records the shared-host failures this project has actually hit, and all three are
progressive storage contention that developed during operation:

- [DEVELOPMENT_PLAN/README.md:853-855](DEVELOPMENT_PLAN/README.md) and
  [phase-187:95-97](DEVELOPMENT_PLAN/phase-187-linux-no-caveat-runtime-and-browser-lane.md): Apache
  BookKeeper went read-only under co-tenant disk pressure — worked around by raising the bookie
  disk-usage threshold on the jitML clusters only, which raises this project's tolerance rather than
  reducing its demand — and a co-tenant-induced disk-full event was ridden out.
- [phase-65:114](DEVELOPMENT_PLAN/phase-65-reflected-dhall-schema.md): a Docker image-store rebuild
  flake attributed to this shared host.

§5 concedes that a one-shot admission decision cannot see contention of that shape. The
decision-relevant conclusion — that for the failures this project has actually recorded, the
mechanism as the document describes it would have prevented none — is never stated. The document has
every premise and does not draw the inference.

The real specification is stronger here (walls applied and re-observed, live bundle growth
forbidden, retained storage charged as protocol state), so the honest version of this section under
the *actual* protocol is different again — and better for this project. The document's own weakened
account of the protocol makes the case for adoption look worse than it is.

What the document omits about this project's primary lane cuts the other way. The specification's
Darwin row records no accepted aggregate descendant-RAM wall on native Darwin, and its Apple Metal
row offers an exclusive device token plus admission and detection guidance while refusing any
authority that requires a hard wall. Adoption would give the Mac lane **cross-project device
exclusivity** — a real gain, and the single clearest benefit on offer — but **not** a memory bound.
A reader of §§1–3 would reasonably conclude the opposite.

## 14. Recommended disposition

### Step 1 — Rewrite the document as an actual participation record

Replace all 112 lines with roughly 40–60 that are entirely about this project. Keep
`**Status**: Draft` only until step 2 gives it an owning phase; then `Supporting reference`.

1. **Name the owner.** Cite `amoebius/documents/engineering/shared_host_resource_protocol.md`
   ("Finite Resource Execution Authority Protocol", `d618ede`) by title, path, and commit; note the
   `hostbootstrap` copy is `Draft` and untracked; state that this project re-derives rather than
   restates it — which is what the specification asks for.
2. **Re-anchor the vocabulary.** Delete "ledger", `$HOME/.hostclaim`, `%UserProfile%\.hostclaim`,
   `spec-version`, "per-user root", "fixed-size record", "operator-edited budget", "no privileged
   installer", "prefix test over opaque identifiers", and the `Transient`/`Persistent` taxonomy.
   Use *host coordination root*, *layout*, *resource cell*, and the
   `ProjectId → ParentScopeId → ClaimKey → Lease → AppliedEnvelope → ExecutionAuthority →
   ResourceReceipt` chain. Restate demand as requirement arithmetic: persistent baseline plus
   maximum concurrent transient, replicas multiplied with checked overflow.
3. **Correct the four semantic claims** in [§3.2](#32-four-semantic-contradictions): walls are
   applied and re-observed, live bundle growth is forbidden, capacity is observed before *and* after
   locks, and cleanup is a charged phase rather than an admission exemption.
4. **Quote this project's own adoption row** (the five obligations) instead of authoring three new
   ones.
5. **State what this project can and cannot meet**, with module paths:
   - the cross-process lock primitive already exists — `writePointerCasLocal`
     ([`src/JitML/Checkpoint/Store.hs:3525-3581`](src/JitML/Checkpoint/Store.hs)) — together with the
     specification's own reason it is insufficient: it does not arbitrate the host and supplies no
     reboot epoch;
   - "derive the charge once" is largely unmet ([§8](#8-derive-the-charge-once-has-very-little-to-derive-from));
   - the lease anchor is structurally absent ([§9](#9-the-lease-anchor-is-the-obligation-jitml-structurally-cannot-meet));
   - two of three lanes run in ephemeral containers with `$HOME` unmounted, so they need the
     specification's host-side anchor plus its bind-mount file-identity rule
     ([§6](#6-following-its-own-resolution-rule-produces-the-failure-it-warns-against));
   - there is no Windows lane, so that obligation is vacuous — say so rather than restating a
     Windows path.
6. **State the cost and the benefit honestly**: adoption buys cross-project device exclusivity,
   chiefly for the host-native Metal lane, and buys no memory wall on Darwin and nothing for the
   progressive-disk contention that is the only shared-host failure this project has recorded
   ([§13](#13-the-empirical-mismatch)).
7. **Add `## Current Status`** linking the phases created in step 2, and **add body links** to
   [cluster_topology.md](documents/engineering/cluster_topology.md),
   [run_contract.md](documents/engineering/run_contract.md),
   [daemon_architecture.md](documents/engineering/daemon_architecture.md), and the plan.

### Step 2 — Create the owning `DEVELOPMENT_PLAN/` phases

Four local correctness debts need no protocol, have now been verified twice, and are currently
recorded nowhere. Mutable status belongs in the plan, not in a topic document.

- **GPU allocation.** Request the `nvidia.com/gpu` extended resource and drop the hardcoded
  all-device environment so the device plugin injects the granted identity. This is the change that
  delivers real in-cluster allocation today and matches the specification's rule that Kubernetes
  requests and device-plugin resources are render targets of an already-admitted cell. Touches
  [`src/JitML/Service/Workload.hs:1685-1692`](src/JitML/Service/Workload.hs),
  [`src/JitML/Service/ConfigMap.hs:154-163`](src/JitML/Service/ConfigMap.hs),
  [`chart/local/jitml-service/templates/deployment.yaml:81-87`](chart/local/jitml-service/templates/deployment.yaml),
  and the assertions in [`test/integration/Main.hs:6667,6673`](test/integration/Main.hs),
  [`test/daemon-lifecycle/Main.hs:1531`](test/daemon-lifecycle/Main.hs), and
  [`test/e2e/Main.hs:254`](test/e2e/Main.hs).
  **This reopens or supersedes a `✅ Done` deliverable.** `NVIDIA_VISIBLE_DEVICES=all` is a closed,
  live-validated deliverable of
  [phase-50](DEVELOPMENT_PLAN/phase-50-nvidia-runtimeclass-for-linux-cuda.md) (Sprint 50.1 `✅ Done`;
  validation gate 6 records a 2026-05-23 probe pod reaching `Succeeded` and logging
  `GPU 0: NVIDIA GeForce RTX 5090`), restated in
  [phase-59](DEVELOPMENT_PLAN/phase-59-stateless-deployment-pod-anti-affinity-per-substrate-dhall.md),
  and codified as target contract in
  [cluster_topology.md:579-584](documents/engineering/cluster_topology.md) and
  [daemon_architecture.md:75-79](documents/engineering/daemon_architecture.md). Per
  [documentation_standards.md §4](documents/documentation_standards.md), governed docs are reconciled
  to the plan — so this is a phase reopening, not a prose assertion of debt. The specification agrees
  on the substance: "The protocol forbids an all-devices launch."
- **Job resource blocks.** `renderJobMountedRunConfig` emits no `resources:` while the installed
  subcharts do ([§8](#8-derive-the-charge-once-has-very-little-to-derive-from)).
- **Budget drift.** One authored `jitmlService` budget, three divergent renderings — Dhall, hardcoded
  subchart YAML, and a Haskell renderer that drops it. This is a live instance of the very drift §7
  warns about.
- **Admission seam.** `checkMinimumHostMemory`
  ([`src/JitML/Prerequisite/Nodes/Cluster.hs:96-110`](src/JitML/Prerequisite/Nodes/Cluster.hs))
  returns `True` when `/proc/meminfo` is absent (every macOS run) and again when `MemTotal` is
  unparseable, and compares against **installed** rather than available RAM — so it cannot see a
  machine already loaded by another program, which is the entire scenario. Its threshold is
  `nodeMemoryMiB res + 4096` for one node while every kind config materializes a control-plane node
  plus workers, and `loadClusterResourcesOrDefault "."` is working-directory relative, so it silently
  falls back to built-in defaults when run from elsewhere. It is reached only from `runDoctor` /
  `runDoctorRemediate` ([`src/JitML/App.hs:318,336`](src/JitML/App.hs)); both commands that actually
  create clusters — `runBootstrap` (`App.hs:517-526`) and `cluster up` (`App.hs:598-602`) — call
  `liveExecutePhasedRollout` directly, and `grep -c Prerequisite src/JitML/Bootstrap.hs` returns `0`.
  The shell stage-0 `doctor` in `bootstrap/*.sh` is a different check and does not shell out to
  `jitml doctor`.

### Step 3 — Fix the index

In [documents/engineering/README.md](documents/engineering/README.md): correct "fourteen" →
"thirteen" (`:14`), and either move the document out of **Cross-Project Contracts** or make the row
honest about what it mirrors.

### Step 4 — Mirror the correction in `infernix`

Its copy is byte-identical ([§5](#5-it-is-not-a-jitml-document)). Correcting this repository alone
leaves a second project publishing the same non-conforming root path — which is the precise failure
both documents say the mechanism exists to prevent.

### Step 5 — Optional: raise the documentation floor

The gaps in [§11.3](#113-the-gate-cannot-catch-any-of-this) are cheap to close and would have caught
most of this class of drift: validate `Status` against the closed enum (a `parseDocumentStatus`
mirroring `parseSprintStatus`), require `## Current Status` when a document contains both
current-state and target language, and resolve all relative link targets rather than only
`phase-*.md`. Also worth considering: extend `governedMarkdownPaths` so an ALL-CAPS root Markdown
file is either governed or rejected, closing the relocation loophole `27cae53` used.

## 15. Verification

- `docker compose build jitml && docker compose run --rm jitml jitml check-code`
- `docker compose run --rm jitml jitml docs check` — note this gate validates none of the rules
  broken here; a pass is not evidence of conformance
  ([§11.3](#113-the-gate-cannot-catch-any-of-this)).
- Vocabulary, after step 1:
  `grep -ci 'ledger\|hostclaim\|spec-version' documents/engineering/shared_host_resource_protocol.md`
  → `0`; the document names `amoebius` and links at least three governed documents.
- Index, after step 3: the "thirteen"/"fourteen" prose count matches the row count in
  `documents/engineering/README.md`.
- Cross-repo, after step 4:
  `diff documents/engineering/shared_host_resource_protocol.md ../infernix/documents/engineering/shared_host_resource_protocol.md`
  shows a deliberate, reconciled delta rather than a name substitution.
- For each phase created in step 2, run its lane per [CLAUDE.md](CLAUDE.md):
  `jitml test <stanza> --apple-silicon` on the Mac host,
  `docker compose run --rm jitml jitml test <stanza> --linux-cpu`, and
  `docker compose run --rm jitml-cuda jitml test <stanza> --linux-cuda`.
