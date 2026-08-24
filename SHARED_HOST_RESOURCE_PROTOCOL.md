# Shared Host Resource Protocol: Proposal Review

> **Document role:** Non-normative review memorandum requested at the repository root. The protocol
> under review remains the Draft
> [Finite Resource Execution Authority Protocol](documents/engineering/shared_host_resource_protocol.md),
> and current jitML behavior remains owned by the [project doctrine](README.md), the governed
> [engineering documents](documents/engineering/README.md), and the
> [development plan](DEVELOPMENT_PLAN/README.md). This review confers no runtime authority or
> conformance.

## Executive Assessment

The proposal is directionally sound and addresses a real gap shared by jitML and its sister
projects: project-local budgets, Kubernetes limits, advisory locks, and execution evidence do not
by themselves establish safe, machine-global admission. Its central chain is the right one:

```text
observed host -> validated layout -> admitted cell -> held ownership
              -> applied and read-back walls -> closed execution -> terminal receipt
```

The strongest aspects are its separation of fit, ownership, enforcement, and execution authority;
its explicit `ParticipatingProjects` versus `WholeHost` guarantee; its refusal to treat sampled
usage as a hard wall; its prepared-before-effects journal; its no-TTL recovery rule; and its honest
distinctions among whole-GPU, MIG, MPS, Metal, Linux cgroups, and reactive Darwin supervision.

The proposal should nevertheless remain a Draft. It is not yet an adoption-ready ABI, and jitML is
not close to conforming merely by adding a lock around `bootstrap`. Two protocol-level issues are
blocking: the normative inventory promises a cell lock without defining one, and the one-parent,
no-live-growth lifetime model does not explain how a persistent CPU-side cluster can later acquire
and release an accelerator while projects take turns. Several other issues—ABI release ownership,
permissions, bounded history, retained-storage arithmetic, anchor authentication, and host/guest
installation—also need resolution before implementation.

For jitML, adoption would be a major architecture program. It requires a host-native,
lease-lifetime project anchor, total physical-demand derivation, create-empty/read-back containment,
authority threaded through every material launcher and storage writer, exact device selection,
durable recovery, and cross-project live conformance tests. The sensible initial target is
`ParticipatingProjects` on the
actual supported lanes: hard Linux CPU/RAM enforcement where the host supports it, exclusive
whole-CUDA-device use, exclusive Metal with reactive Darwin memory supervision, and typed refusal
for unsupported profiles. `WholeHost`, Windows, MIG, MPS, and VM conformance should not be claimed
in the first adoption.

## Current Status

The reviewed protocol is a target architecture marked `Draft`; jitML does not currently implement
or conform to it. Today:

- Linux bootstrap runs jitML from a transient `docker compose run --rm` client, while the Kind
  cluster it creates persists after that client exits.
- Host admission checks a coarse memory amount, and Kind node caps are applied after container
  creation rather than establishing an empty enforcement domain first.
- Logical run plans and component budgets do not form a complete physical CPU, RAM, storage, file
  descriptor, process, host-memory, VRAM, or compiler-workspace requirement.
- CUDA paths expose all devices in several places, and Metal selects the system default device.
- Generic subprocess construction and execution remain broadly available, and service code can
  render and apply dynamic Kubernetes work without an outer authority.
- Persistent storage declarations are not backing-filesystem quota enforcement.
- Existing publication, evidence, locks, and process-local registries do not provide the proposed
  boot epoch, prepared-intent recovery, exact effect reconciliation, or quarantine semantics.

The current implemented contracts remain those documented in
[cluster topology](documents/engineering/cluster_topology.md),
[daemon architecture](documents/engineering/daemon_architecture.md),
[the run contract](documents/engineering/run_contract.md), and
[JIT code generation](documents/engineering/jit_codegen_architecture.md). The protocol would become
an outer authority layer around those contracts rather than replacing them.

## What the Proposal Gets Right

### Authority is more than admission

The proposal correctly distinguishes a pure proof that a requirement fits from proof that the cell
is currently owned, and distinguishes both from proof that effective walls were applied. That
prevents a common error: treating a successful capacity calculation, Kubernetes request, or
configuration value as permission to execute. Its `ExecutionAuthority` is minted only after those
facts are joined and is scoped to one exact host, epoch, project, claim, cell, requirement, and
mechanism.

This aligns well with jitML's preference for opaque validated plans and receipt-bound execution.
The outer authority should join the existing run plan and evidence lifecycle, not be reconstructed
from a publication file, environment variable, device ordinal, or free-form YAML.

### The guarantee is scoped honestly

The distinction in [The guarantee](documents/engineering/shared_host_resource_protocol.md#the-guarantee)
is essential. Cooperative closed interpreters can make a meaningful `ParticipatingProjects` claim.
They cannot constrain an administrator, an old binary, an unrelated container, or a same-privilege
process that bypasses advisory locks. `WholeHost` therefore needs separate closed-world evidence and
must refuse on an open workstation.

This is especially appropriate for developer Macs and shared CUDA workstations. The proposal also
correctly says that shared cache, memory bandwidth, storage bandwidth, PCIe, thermal, and power
effects are not constant-performance guarantees unless an actual mechanism partitions them.

### Prepared intent and quarantine are appropriate

Writing and synchronizing `Prepared` before the first external mutation is the right recovery
boundary. The explicit lifecycle and the rule that an uncertain effect is quarantined rather than
stolen are substantially stronger than PID files, stale timestamps, or absence of a current
record. The prohibition on TTL-based ownership is also correct: elapsed time does not prove that a
cgroup, process, container, mount, device context, or restarted service is absent.

### Accelerator semantics are unusually careful

The proposal does not confuse a CUDA ordinal with a stable device identity, a Compute Instance with
an independently isolated MIG GPU Instance, an MPS percentage with exclusive compute, or Apple
unified memory with separate host and device pools. These distinctions should be preserved. The
recommended first jitML profile should still be much narrower than the full matrix: one exact whole
CUDA UUID at a time and one exact Metal registry identity at a time.

### Independent implementations are the right interoperability boundary

The requirement that each project implement its own adapter avoids turning one repository or
runtime library into a privileged central scheduler. Shared canonical bytes, laws, and live tests
are enough for interoperability, provided that their release ownership and upgrade protocol are
made explicit.

## Perceived Weaknesses in the Proposal

### 1. Cell occupancy is promised but not normatively represented — Critical

The overview and acquisition algorithm refer to a per-cell lock, but the fixed lock inventory in
[Daemonless host protocol](documents/engineering/shared_host_resource_protocol.md#daemonless-host-protocol)
lists epoch, admission, parent, and physical-resource locks without defining a cell lock key or a
`cells/<identity>.lock` object.

That omission is observable for scalar CPU/RAM/storage cells. If all such cells lock the same host
domain exclusively, disjoint cells cannot run concurrently. If they lock it shared, nothing
prevents two anchors from selecting the same logical cell. A durable record is not a substitute for
lifetime kernel ownership.

The ABI needs a finite, installer-created `CellSlotLock` identity, canonical path, lock mode, order,
and relationship to ancestor/resource locks. Both base cells and accelerator-turn cells need an
unambiguous occupancy object.

### 2. Persistent clusters conflict with accelerator turn-taking — Critical

The proposal allows one live parent reservation per project, forbids expansion of a live resource
bundle, and says parallel work is split from the held parent. It also says a non-partitioned GPU can
be shared by projects taking turns. Those rules do not compose for jitML's persistent cluster:

- If the parent cell includes the GPU, the anchor monopolizes it for the cluster's lifetime.
- If the parent cell excludes the GPU, a later training or inference request cannot acquire it
  without growing the live bundle.
- If the invoking CLI attempts a second parent claim, it receives `ParentScopeBusy`.
- A child split cannot safely acquire new host-global locks independently of its parent anchor.

The protocol must choose and specify one model. The recommended model is a long-lived base lease
sized for the persistent platform plus maximum host-side transient demand, together with a
separately typed, short-lived accelerator-turn lease acquired by the same anchor. An execution
authority joins a checked base child split with that exact accelerator turn. This is not ordinary
live bundle growth and must have its own ABI transitions and recovery rules.

If the shared ABI does not adopt that model, jitML's conservative conforming behavior must hold the
whole GPU for the cluster or daemon lifetime. Local improvisation would destroy interoperability.

### 3. The anchor protocol is not sufficiently specified — High

The proposal correctly requires a project-owned anchor for persistent effects, but it does not
fully define how later clients authenticate, request child capacity, observe a same-key operation,
receive a terminal receipt, or recover after client or anchor failure. “Authenticate to the
existing anchor” is not yet an interoperable protocol.

For jitML, the minimum contract needs a host-local endpoint, OS peer-credential checks, a
parent-bound nonce, canonical request and response messages, monotonic attempt allocation,
idempotent attach/status/release operations, and explicit authorization for recovery. Lock handles
must remain noninheritable and must never be transferred from one process to another. IPC should
accept closed operation identifiers and validated plan digests, never arbitrary executable names,
arguments, callbacks, or Kubernetes YAML.

### 4. ABI governance has no named release authority — High

The [Interoperability freeze](documents/engineering/shared_host_resource_protocol.md#interoperability-freeze)
requires one semantic ABI while also saying each repository owns independently reviewed Haskell
declarations. That prevents a shared runtime dependency, but it does not by itself identify which
artifact is normative, who allocates `ProjectId` values, how a release is approved, or how a mixed
version host cuts over.

A neutral, immutable, spec-only release should own the schema, canonical CBOR bytes, constants,
project-ID registry, path grammar, satisfaction tables, crash schedule, and golden vectors. Each
project should vendor and pin its digest while implementing the semantics independently. Upgrade
must take the same permanent epoch lock, prove every cell idle and every old effect reconciled, and
refuse permissive version ranges or parallel versioned roots.

### 5. The POSIX permission model permits lock replacement — High

The proposed root uses group-writable `0770` directories. On POSIX systems, directory write
permission allows a group member to rename or unlink entries even when the files themselves are
operator-owned. That undermines the proposal's permanent file-identity and nonreplacement rules.

Immutable lock and catalog directories should be root-owned and not participant-writable. Each
project should receive a precreated allocation subtree writable only by its dedicated anchor
identity or a narrow ACL. Runtime checks must reject symlinks, remote filesystems, unexpected owner
or mode, changed root identity, and changed leaf `(device,inode)` identity.

### 6. Durable history can grow without bound — High

The proposal retains permanent lock tombstones and spent claim-key tombstones, while protocol
state itself consumes storage. A finite current layout does not bound repeated catalog mutations or
an unbounded sequence of completed claims.

The protocol should cap the number of installer-created lock slots and assign each slot's semantic
identity at most once. An assigned slot must never be rebound to another resource, even under an
epoch mutation; retirement leaves an inert tombstone and catalog exhaustion refuses further
growth. Claims should instead use monotonically increasing attempt generations under the parent
lock, with a fixed-size receipt ring plus a high-water mark. A compacted old attempt must remain
permanently spent without requiring one file per historical key. Protocol metadata and its
worst-case journal expansion must be charged to the host reserve.

### 7. Storage composition is incomplete for retained artifacts — High

Sequential maximum is appropriate for mutually exclusive transient peaks, but not for state that
survives the operation. Checkpoints, datasets, JIT objects, Docker layers, object-store data, logs,
and evidence accumulate until deletion is actually observed. A computation can fit transiently and
still overrun the host after several successful runs.

Storage admission needs separate persistent stock, maximum reachable net production, transient
scratch, and post-operation retained quota. A compute lease ending must not silently release the
storage reservation for bytes that remain. The proposal should also define how migration,
partially written objects, garbage collection, snapshots, and journal growth affect the stock.
A quota ceiling limits what a project may consume but does not reserve free physical capacity;
strict storage conformance therefore also needs a dedicated thick extent or otherwise reserved
backing pool. A host without that mechanism must advertise a weaker profile or refuse.

### 8. Host installation and guest delegation are underdesigned — High

The fixed roots require privileged installation, ownership and ACL setup, immutable lock creation,
and catalog publication. Current jitML Linux bootstrap promises Docker without sudo and begins in a
transient container. A bind mount of a pathname is insufficient, and a container cannot acquire
authority over the actual Darwin, Linux, or Windows host merely by using its guest kernel's lock.

The protocol should distinguish first installation, normal participation, catalog mutation,
binary upgrade, and uninstall. It should define which operator provisions the root, how the
host-native anchor is installed and supervised, how containers contact it, and which operations are
outside the cooperative guarantee during the initial trust bootstrap. `hostbootstrap` may perform
installation, but jitML cannot depend on another project's runtime to hold its lease.

### 9. Complete physical demand remains a project proof obligation — Medium/High

The proposal correctly leaves demand derivation to each project, but conformance can be hollow if a
project supplies precise-looking yet incomplete numbers. For jitML the demand is not merely model
weights or pod limits. It includes platform replicas, every Kind node, service overhead, compiler
and linker processes, parameters, activations, gradients, optimizer state, library workspaces,
CUDA/Metal context, pinned host memory, datasets and batches, tuning width, RL vector environments
and replay, subprocess and file-descriptor fan-out, caches, checkpoints, logs, tests, and cleanup.

The common conformance rules should require total derivation for every governed operation, checked
overflow and rounding, monotonicity properties, and conservative analytic upper bounds for every
variable. If no defensible upper bound exists, admission must refuse that requirement. Measured
peaks can calibrate or invalidate a formula, but cannot replace the pre-launch bound.

### 10. Project identity and the cooperative threat model need an OS binding — High

A typed `ProjectId` proves an in-process association; it does not authenticate the process opening
the shared coordination root. The proposal correctly limits its guarantee to cooperating closed
interpreters, but the filesystem and anchor protocols still need to bind each registered project
to an operating-system identity, peer credentials, allocation ACL, and session nonce.

The guarantee should say explicitly that it prevents accidental or buggy contention among
operator-approved participating binaries. It does not defend against a hostile administrator,
hostile same-UID process, or deliberately nonconforming binary. Old versions with bypasses are
foreign claimants, not safe participants merely because they use the same textual project name.

### 11. Nonblocking acquisition lacks an operational policy — Medium

Nonblocking locks are appropriate for safety and recovery, but repeated callers can create retry
storms or starve one project indefinitely. The ABI or conformance profile should define typed
`Busy` diagnostics, bounded retry with jitter/backoff, and the fairness guarantee, if any. Retry
policy must remain separate from ownership: it cannot introduce a TTL, lease expiry, or permission
to steal a lock after elapsed time.

### 12. Some profiles need narrower capability claims — Medium

The substrate table is admirably honest, but several mechanisms depend on host configuration that
cannot be assumed merely from an OS name. Cgroup-v2 delegation, swap behavior, cpuset control,
filesystem quota support, Docker storage drivers, NVIDIA CDI/device plumbing, APFS quotas, process
birth observation, and service restart behavior must all be observed capabilities. Unsupported
mechanisms should produce typed refusal rather than a degraded receipt under the same profile name.

For jitML, Windows, MIG, MPS, and VM profiles add substantial implementation and hardware-test
surface without helping its current three lanes. They should remain protocol capabilities, not
jitML conformance obligations, until dedicated real-hardware phases exist.

### 13. The document mixes target architecture with project-current comparison — Medium

The draft describes a broad target and compares it with current project behavior, but it lacks the
repository-required `## Current Status` boundary. At more than 800 lines it also exceeds the
documentation standard's strong preference for splitting broad material. That makes it too easy
for a reader to mistake a target mechanism for an implemented guarantee or to treat comparison
prose as a mutable status ledger.

The protocol should be split into a short architectural overview, a normative ABI and lifecycle,
substrate profiles, and the conformance corpus. The overview should state that the protocol is
Draft and unimplemented by jitML; mutable adoption order, blockers, and live evidence should remain
only in `DEVELOPMENT_PLAN/`.

## Concrete Implications for jitML

| Area | Current jitML behavior | Required implication |
|------|------------------------|----------------------|
| Bootstrap lifetime | [`bootstrap/_lib.sh`](bootstrap/_lib.sh) starts a transient Compose client; [`Bootstrap.hs`](src/JitML/Bootstrap.hs) creates persistent Kind and exits | Install a host-native `jitml` anchor before normal bootstrap; the anchor, not the CLI/container, owns locks and effects |
| Host admission | [`clusterHostMemoryPrerequisite`](src/JitML/Prerequisite/Nodes/Cluster.hs) budgets one node cap plus 4 GiB and passes when `/proc/meminfo` is absent or unparsable | Observe the actual host, sum every persistent and peak claimant, include reserve, and refuse unknown observation |
| Kind walls | [`Cluster.Resources`](src/JitML/Cluster/Resources.hs) runs `docker update` after Kind node creation and applies the profile cap to every node | Place the complete provider/daemon and all nodes inside an already-applied parent wall; read effective values before the first workload |
| Kubernetes workloads | [Dynamic Jobs](src/JitML/Service/Workload.hs) have placement controls but no complete CPU, memory, ephemeral-storage, process, or device envelope | Render all requests, limits, storage roots, and exact device identity from authority; the host wall remains the outer bound |
| CUDA | [Compose](compose.yaml) and [service/workload renderers](src/JitML/Service/ConfigMap.hs) expose `all`; [detection](src/JitML/Engines/CudaRuntime.hs) accepts textual `nvidia-smi -L` output | Observe stable UUID/capacity, acquire the whole-device turn, expose only that identity, and verify it before CUDA initialization |
| Metal | The [fixed bridge](src/JitML/Engines/MetalBridge.hs) caches a static device/queue selected by `MTLCreateSystemDefaultDevice()` | Select and verify an exact registry ID under a live turn; prevent device and queue handles from escaping its lifetime |
| Process launch | [`Subprocess(..)`](src/JitML/Sub/Subprocess.hs), [`runStreaming` and `startDetached`](src/JitML/Sub/Stream.hs), piped callbacks, and raw helper surfaces are broadly reachable | Keep process descriptions data-only, hide effectful runners, and require a closed authority-bearing interpreter |
| Dynamic service work | The coordinator can apply rendered Jobs; Apple ownership is partly process-local | Request checked children from the host anchor; remove bypass RBAC; recover the durable child ledger after restart |
| Storage | [PV capacity fields](src/JitML/Cluster/Storage.hs) and repository directories do not enforce backing usage; Docker layers and temp roots are uncharged | Pair an actually reserved backing pool or thick extent with quota-backed granted roots, migrate retained data safely, account every writer, and reconcile production/deletion in receipts |
| Recovery | [Cluster publication](src/JitML/Cluster/Publication.hs) and local evidence describe state but do not own it | Bind publication to anchor/session/epoch/receipt; recover exact cgroups, processes, containers, Jobs, mounts, quotas, and devices |
| Tests | [Live tests](src/JitML/Test/Command.hs) may borrow an existing publication and use caller-supplied process steps | Authenticate the borrowed cluster to its anchor and run every material test step under checked child authority |

### A host-native project anchor is unavoidable

This is the largest operational change. The product daemon (`jitml service`) should remain distinct
from the resource anchor. Each project has its own host-native, lease-lifetime anchor; there is no
shared scheduler. An operator or installer owns the immutable coordination root, catalog, and lock
objects. The jitML anchor validates and uses those objects, owns only jitML's allocation records,
and retains live lock and effect custody for its persistent base lease, child ledger, enforcement
domains, cleanup, and recovery. Normal CLIs and in-cluster services become clients.

The current Docker-socket mount gives the transient guest broad host-container authority. A strict
design should instead make the anchor the only client allowed to create jitML-owned Docker/provider
effects. Project-owned nodes and helpers must enter the admitted cgroup at creation. A shared host
runtime daemon is charged to host reserve; a dedicated project runtime is an optional design only
if its overhead, cgroup ancestry, supervision, and reserved data extent are justified and charged
to the project cell. Continuing to start nodes and cap them afterward cannot satisfy the proposal.

### The run planner must acquire a physical compiler

jitML's logical plans remain valuable but need deterministic physical projections. The two
capacity relationships are:

```text
project cell = persistent project baseline
             + maximum concurrently reachable project transient demand
             + project-owned runtime and cleanup overhead

observed host capacity >= host reserve + sum of catalogued project cells
```

Storage is a stock-flow calculation, not that same sum, and unified Apple memory is one aliased pool
rather than independent host and device capacities. Tuning concurrency, replicas, RL actors, test
fan-out, and JIT cache misses must be visible in the phase DAG. The ABI must assign anchor, driver,
provider, and protocol overhead to exactly one of host reserve or a project cell—never both and
never neither. Alternative smaller plans may be derived and admitted explicitly; the interpreter
must never silently shrink an already admitted plan.

### Execution authority must reach every effect boundary

Wrapping the top-level CLI is insufficient. Authority has to reach bootstrap, Docker/Kind/Helm,
service dispatch, dynamic Jobs, helper clients, SL/RL/tuning/inference execution, JIT compilation
and loading, CUDA/Metal initialization, tests, e2e, prerequisite remediation, code-quality tools,
temporary storage, checkpointing, caches, logs, and cleanup.

The migration should use a closed governed-launch registry. Pure help, version, planning, and
bounded observation can have explicit non-mutating profiles. Material programs should be closed
ADTs whose final renderer is the only module allowed to construct arbitrary process, container,
Kubernetes, or device effects. Neither a library executor nor a workload child should be able to
self-acquire host locks.

### Existing evidence remains useful but changes role

The current run journal, delivery receipt, checkpoint evidence, product rows, and cluster
publication remain inner-domain evidence. None should mint resource authority. Instead, the outer
`ResourceReceipt` should identify the observed host and epoch, selected cell and domains, requested
and offered profiles, effective wall readbacks, measured peaks, outcome, retained-storage delta,
and cleanup result. The inner run journal should reference that receipt and preserve its own richer
ML lifecycle facts.

## Recommended Initial Conformance Envelope

| Lane | Initial claim | Explicit non-claim |
|------|---------------|--------------------|
| Linux CPU | `ParticipatingProjects`; cgroup-v2 CPU/RAM/process wall; reserved backing pool or thick extent paired with an enforced quota; persistent base cell | `WholeHost`; unsupported Docker Desktop guest interpreted as native hard Linux; constant-performance guarantees; quota ceiling presented as capacity reservation |
| Linux CUDA | Linux base profile plus one exact, exclusive whole-GPU UUID turn and conservative VRAM/pinned-memory admission | MIG, MPS, fractional GPU, ordinal-only identity, or persistent all-device exposure |
| Apple Silicon | `ParticipatingProjects`; exact exclusive Metal registry identity; unified-memory accounting; pressure-triggered supervised termination | Hard aggregate descendant-RAM wall, separate VRAM pool, or `WholeHost` |
| Other profiles | Typed capability/profile refusal | Windows, VM, mediated device, MIG, or MPS conformance without a real implementation and hardware lane |

The Linux CPU functional lane may still run inside Docker on non-Linux hosts, but that does not by
itself prove native Linux host enforcement. The receipt must describe the actual outer host and
mechanism rather than infer them from the workload container's kernel.

## Changes Required Before Approval as an ABI

1. Define permanent base-cell and accelerator-turn lock identities and lock ordering.
2. Specify persistent base leases, finite child slots, accelerator turns, and their atomic join.
3. Define authenticated anchor IPC, retry/attach semantics, closed request payloads, and recovery
   authority.
4. Name the normative ABI release artifact, project-ID authority, approval policy, and exact upgrade
   transition.
5. Replace participant-writable lock directories with operator-owned immutable objects and narrow
   allocation ACLs.
6. Replace unbounded spent-key and retired-lock growth with bounded, permanently one-assignment
   slots, monotonic generations, bounded receipts, and a permanent high-water rule.
7. Define persistent-storage stock, production, deletion, migration, garbage collection, and
   protocol-state accounting.
8. State the first-install trust boundary and host/container/VM delegation protocol.
9. Make every enforcement row capability-observed and require typed refusal when the exact
   mechanism is unavailable.
10. Bind registered project identities to OS credentials and allocation permissions, and state the
    cooperative threat boundary precisely.
11. Define bounded retry/backoff, diagnostics, and any fairness expectation without turning retry
    time into ownership expiry.
12. Split current-project comparison from the normative overview and keep mutable adoption status
    in the development plan.
13. Publish a minimal conformance profile for jitML's real lanes before retaining the optional
    Windows/MIG/MPS/VM breadth.

## Recommended Adoption Order for jitML

The implementation should be scheduled as a new forward-only suffix after the current open phase
chain, following the development plan's
[numerical and single-accelerator rules](DEVELOPMENT_PLAN/development_plan_standards.md#m-forward-only-single-accelerator-numerically-ordered-phases):

1. Correct and freeze the protocol semantics, conformance scope, ABI release, installation model,
   and complete governed-launch inventory.
2. Implement the pure quantities, layouts, strength lattice, demand arithmetic, deterministic
   encoding, transition laws, golden corpus, properties, and compile-fail boundary.
3. Derive complete jitML requirements and retained-storage stock for every registered operation.
4. Implement host observation, immutable locks, journaling, crash recovery, quarantine, and the
   persistent same-binary anchor.
5. Apply and read back Linux enforcement domains, reserved backing storage with enforced quotas,
   and create-time Docker/Kind containment.
6. Thread authority through the persistent cluster, service, dynamic Jobs, JIT/device boundary,
   every ML workflow, tests, e2e, build/lint, and cleanup.
7. Delete compatibility launchers and enforce a mechanical bypass scan before making any
   conformance claim.
8. Close Linux CPU on a real Linux host, then close Linux CUDA and Apple Silicon in separate
   hardware phases.
9. Aggregate immutable per-lane attestations in a later Linux-CPU-only phase and advertise only the
   rows whose ABI, peer-contention, crash/reboot, and live-wall evidence agree.

A temporary shadow mode may compare derived demand with measured peaks and current limits, but it
must be labeled nonconforming. The enforcement cutover must cover every binary registered as a
participating project on that host: until every approved peer pins the same ABI and closes its
bypasses, older peers are foreign claimants and the cross-project guarantee cannot be advertised.
Old launchers, permissive ABI fallbacks, raw device exposure, and publication-only authority cannot
coexist with the cooperative guarantee.

## Required Validation

Protocol-level validation should include:

- canonical encoding and cross-version refusal vectors;
- checked arithmetic, hierarchy, alias, strength, storage-stock, and layout properties;
- compile-fail tests for forged brands, authority reuse, child self-acquisition, region escape, and
  unrestricted effect lifting;
- replacement, symlink, remote-filesystem, permission, stale-epoch, partial-lock, and lock-order
  negative controls;
- crash injection before and after every durable transition, plus real anchor death, provider
  restart, and reboot exercises;
- real CPU/RAM/storage wall violations and weaker-than-required readback refusal;
- exact CUDA UUID and Metal registry-ID readback before device initialization;
- independently implemented sister-project binaries contending on the same permanent host objects;
- a forbidden-surface scan proving no unregistered process, container, Kubernetes, device, or
  storage path remains; and
- the existing non-skipping substrate test lanes, documentation check, and container-only
  code-quality gate.

No single phase should require both CUDA and Apple hardware. Per-lane attestations should be
immutable inputs to a later Linux-CPU-only aggregation phase; a shared ABI or core change after a
lane closes invalidates that lane's attestation and requires a new forward-numbered revalidation.

## Recommendation

Approve the proposal as a valuable architectural direction, but do not approve it yet as a frozen
interoperability ABI or describe jitML as conforming. Retain its Draft status until the cell-lock
and persistent-base/accelerator-turn semantics are resolved, the ABI and installation owners are
named, storage and history are bounded, and a jitML integration design demonstrates that every
material effect can actually descend from a host-native, lease-lifetime anchor.

Once those conditions are met, adopt it incrementally but claim conformance only at the final
bypass-removal and live cross-project gates. A narrower truthful profile is preferable to a broad
protocol label backed by incomplete demand, late-applied walls, or ungoverned launch paths.

## References

- [Finite Resource Execution Authority Protocol](documents/engineering/shared_host_resource_protocol.md)
- [Documentation standards](documents/documentation_standards.md)
- [jitML development plan](DEVELOPMENT_PLAN/README.md)
- [jitML CLI and project doctrine](README.md)
- [Cluster topology](documents/engineering/cluster_topology.md)
- [Daemon architecture](documents/engineering/daemon_architecture.md)
- [Run contract](documents/engineering/run_contract.md)
- [JIT code-generation architecture](documents/engineering/jit_codegen_architecture.md)
