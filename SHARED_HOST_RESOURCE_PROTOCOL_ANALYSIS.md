# Shared Host Resource Protocol Analysis

> Review memorandum for
> [`documents/engineering/shared_host_resource_protocol.md`](documents/engineering/shared_host_resource_protocol.md).
> This file records an architectural assessment of the draft as it relates to
> jitML. It is not protocol authority, an implementation-status source, or a
> substitute for the development plan.

**Review date:** 2026-08-24  
**Review scope:** protocol topology, jitML resource planning, cluster and host
placement, accelerator access, lifecycle custody, durable recovery, trust,
versioning, conformance, and adoption sequencing.

## Executive Summary

The Shared Host Resource Protocol has a strong conceptual core. In particular,
it correctly distinguishes cooperative admission, enforced containment, and
recoverable execution authority; separates persistent base capacity from
short-lived accelerator turns; treats unified memory and retained storage as
real capacity aliases; and refuses to treat cleanup uncertainty as permission
to reuse a resource.

Those properties fit jitML's needs. jitML operates persistent Kind and service
infrastructure while also launching finite training, tuning, reinforcement
learning, inference, benchmark, and test work on CPU, CUDA, and Metal. Its
current protections are project-local: a typed Dhall cluster profile, Docker
container caps, Kubernetes requests and limits for platform components,
placement constraints, application lifecycle brackets, and a process-local
Apple workload registry. None of those mechanisms arbitrates physical host
resources with another repository.

The draft is not yet ready to be frozen or treated as an executable jitML
contract, however. The principal reasons are:

1. jitML does not currently derive a complete physical-resource requirement
   from a validated workload.
2. CUDA and Metal execution can be reached without a host-resource authority,
   and current CUDA deployment surfaces expose all visible devices rather than
   one admitted physical identity.
3. jitML has no persistent, host-level anchor that can retain base and turn
   custody across the lifetime of a Kind cluster or other persistent effect.
4. The artifact-enrollment language is stronger than the principal-based
   enforcement described by the protocol can establish on a normal development
   host.
5. Several details that define actual interoperability—native lock primitives,
   crash-safe catalog publication, exact journal writes, nested turn ordering,
   and version interaction—are deferred to a later freeze record.
6. The rejection of a minimal host admission broker is asserted rather than
   demonstrated. The proposed direct-lock topology still requires a privileged
   installer and multiple persistent project anchors, so both shapes deserve an
   explicit trade study.
7. No jitML development-plan phase currently owns adoption, migration, or
   conformance. That is consistent with the document's `Draft` status, but it
   means the proposal is not actionable project policy yet.

The recommended disposition is to keep the protocol as a draft, preserve its
resource and assurance algebra, and validate a much smaller cooperative release
against two real projects before committing to the full governance and recovery
topology. In parallel, jitML should close its own resource-boundary gaps because
those changes are useful even if the neutral protocol changes shape.

## What Was Reviewed

The assessment compared the draft with these current jitML surfaces:

- the protocol's ownership, resource, admission, anchor, recovery, versioning,
  and conformance sections;
- [`JitML.Cluster.Resources`](src/JitML/Cluster/Resources.hs), which decodes the
  cluster resource profile and applies per-Kind-node Docker caps;
- [`JitML.Prerequisite.Nodes.Cluster`](src/JitML/Prerequisite/Nodes/Cluster.hs),
  which performs the current host-memory prerequisite;
- [`JitML.Plan.Plan`](src/JitML/Plan/Plan.hs) and
  [`JitML.Plan.Workload`](src/JitML/Plan/Workload.hs), which own semantic run
  budgets and resolved workload plans;
- [`JitML.Service.Workload`](src/JitML/Service/Workload.hs), which chooses
  cluster versus host placement and renders workload Jobs;
- [`JitML.Service.HostWorkloadRegistry`](src/JitML/Service/HostWorkloadRegistry.hs),
  which owns process-local Apple workload handles;
- [`JitML.Engines.HasEngine`](src/JitML/Engines/HasEngine.hs),
  [`JitML.Engines.CudaLocal`](src/JitML/Engines/CudaLocal.hs), and
  [`JitML.Engines.MetalLocal`](src/JitML/Engines/MetalLocal.hs), which expose
  current device-execution entry points;
- [`documents/engineering/run_contract.md`](documents/engineering/run_contract.md),
  which owns jitML's application-level placement, observation, cleanup, and
  evidence lifecycle;
- [`documents/engineering/cluster_topology.md`](documents/engineering/cluster_topology.md)
  and [`documents/engineering/daemon_architecture.md`](documents/engineering/daemon_architecture.md),
  which own current cluster and daemon topology; and
- [`compose.yaml`](compose.yaml) and the jitML service chart, which show the
  actual host/container and accelerator exposure boundaries.

This was a read-only architectural review. No protocol implementation or live
cross-project conformance test exists in this repository.

## Strong Parts of the Protocol

### Honest assurance levels

The most valuable part of the draft is the separation of:

- `CooperativeCellLease`, which proves participating-project exclusion but no
  scalar wall;
- `EnforcedCellLease`, which additionally proves required walls were applied
  and read back; and
- `RecoverableExecutionAuthority`, which additionally covers durable intent,
  fencing, recovery, quarantine, and terminal cleanup.

This prevents a common category error: treating a file lock, Kubernetes
request, container limit, or free-memory observation as proof of complete host
authority. The resource-indexed mechanism strengths are similarly sound. GPU
exclusivity, CPU ceilings, reactive memory observation, and hardware partitions
are not forced into a false single ordering.

### Correct outer/inner lifecycle boundary

The protocol keeps resource admission and custody outside product-specific
lifecycle meaning. That is the right direction for jitML. jitML already has a
rich, typed run lifecycle that distinguishes placement, workload observation,
application evidence, cleanup, and completed results. A neutral protocol should
not reinterpret checkpoint completion, Pulsar delivery, Kubernetes Job status,
or model evidence.

The natural composition is:

```text
validated jitML plan
  -> jitML host-requirement projection
  -> shared-host execution authority
  -> jitML placement and runLiveWorkflow
  -> jitML terminal result plus resource receipt
```

This preserves the authority of the typed run contract while ensuring that no
placement or device launch begins before resource admission.

### Base and turn separation

A persistent base plus transient turns fits jitML better than a single
monolithic allocation:

- the base can conservatively reserve the Kind control plane, worker nodes,
  MinIO, Pulsar, observability, daemon roles, JIT metadata, and persistent
  storage overhead;
- a turn can reserve a whole CUDA or Metal device for a finite training, test,
  benchmark, inference, or tuning interval; and
- later mechanisms could replace whole-device turns with admitted MIG or MPS
  sharing without changing jitML's semantic run plans.

This also exposes a real product tradeoff. Under initial whole-device
exclusivity, a long training Job and low-latency service inference cannot execute
on the same GPU concurrently. jitML must decide whether service inference takes
short per-batch turns, whether training holds the device for its full Job
lifetime, and what user-facing behavior occurs while the device is busy. MIG or
MPS cannot be assumed as an immediate answer because the draft correctly defers
their stronger claims until they have separate mechanism evidence.

### Conservative aliasing and recovery

The resource graph, unified-memory charging, retained-storage stock-flow, delayed
external-effect fencing, and non-expiring quarantine rules address failure modes
that simple process locks miss. This is especially relevant to:

- Apple unified memory;
- CUDA whole-device versus future partition conflicts;
- retained MinIO/checkpoint output after compute terminates;
- asynchronous Kubernetes or Docker operations that may complete after an
  absence observation; and
- persistent clusters and containers that survive the initiating process.

### Meaningful conformance requirements

The draft requires more than pure or serialization tests. Its cross-project
contention, crash-prefix, changed-subject, physical-device, stale-record, and
reboot cases are appropriate for a protocol whose purpose is coordination among
independently built programs. In particular, absent hardware is treated as no
claim rather than a vacuous pass, matching jitML's real-substrate testing
doctrine.

## Current jitML-to-Protocol Mapping

| Protocol concern | Current jitML surface | Assessment |
|---|---|---|
| Persistent base capacity | Dhall `ClusterResources`, per-component budgets, and per-node Docker caps | Useful project-local input, but not host-global admission and not yet a complete base-offer calculation |
| Workload demand | `RunPlan` and workload-specific plans | Strong semantic workload budgets, but no physical CPU, RAM, storage, process, or exact-device requirement |
| Cluster placement | `WorkloadPlacement = WorkloadClusterJob | WorkloadHostCommand` | Correct closed placement shape, but placement is not gated by shared-host authority |
| Linux workload containment | Kind-node cgroups and Kubernetes component requests/limits | Real local mechanisms, but generated transient workload Jobs lack their own resource requests and limits |
| CUDA identity | NVIDIA RuntimeClass plus `NVIDIA_VISIBLE_DEVICES=all`; Compose uses `gpus: all` | Runtime availability, not admission to one exact physical GPU |
| Metal identity | Runtime probes and the fixed host Metal bridge | Real device execution, but no exclusive host turn or authority is required by the launch API |
| Apple workload custody | Process-local `HostWorkloadRegistry` | Good exact-once in-process handle discipline; not durable, host-global, or recoverable after daemon loss |
| Application cleanup | `runLiveWorkflow`, ownership brackets, diagnostics, placement release, typed cleanup issues | Strong inner lifecycle that should remain project-owned and be nested inside outer resource custody |
| Durable application evidence | MinIO, Pulsar, checkpoint admission, and typed execution journals | Rich product evidence, but not a host-resource journal and not a substitute for cell custody |
| Artifact identity | executable hashes in selected test/evidence paths; mutable local image/tag elsewhere | Partial provenance evidence, not a general enforced participant identity |

## Detailed Findings

### Critical: jitML has no complete host-demand projection

`RawRunBudget` and `RunPlan` model epochs, examples, transitions, vector
environments, trials, promotions, games, simulations, and optimizer work. Those
are semantic and reproducibility-relevant quantities. They do not determine or
carry:

- CPU shares or ceilings;
- peak resident memory;
- Apple unified-memory charge;
- CUDA device-memory charge;
- exact accelerator identity;
- process or descriptor count;
- transient JIT compilation space;
- maximum checkpoint, TensorBoard, trial, or transcript production; or
- retained storage after compute ends.

The cluster resource profile provides static component budgets, but it is not a
total workload adapter. Generated Training, RL, AlphaZero, and Tune Jobs render
placement, image, command, configuration mounts, RuntimeClass, and NVIDIA
environment variables without rendering workload-specific `resources`.

The adapter should therefore produce a separate opaque value, conceptually:

```haskell
deriveHostRequirement
  :: ObservedJitMLProfile
  -> ValidatedWorkload kind
  -> Validation (NonEmpty HostRequirementError) HostRequirement
```

This projection should be derived exactly once from the validated workload,
model shape, dataset/runtime requirements, tuning parallelism, JIT/toolchain
overhead, storage-retention policy, placement, and selected substrate. It should
retain the semantic `PlanId`, but operator cell selection and host-specific
capacity should not silently change that `PlanId`.

The first implementation can use conservative upper bounds. Exact utilization
prediction is not required for safety, but every unmodeled source of growth must
be assigned to a reserve or cause refusal.

### Critical: production accelerator execution is not authority-gated

Current engine interfaces accept an environment and kernel request or runtime
source. They probe whether CUDA or Metal is visible and then compile or execute.
No `TurnLease`, `ExecutionAuthority`, admitted device identity, or equivalent
capability is required.

This is broader than the daemon Job renderer:

- public and daemon inference paths call weighted CUDA/Metal execution;
- training and product publication have direct in-process execution paths;
- tuning benchmarks call low-level kernel functions;
- backend and product tests execute devices directly; and
- `docker compose run` validation exposes all GPUs.

A conforming design must make the authority a prerequisite of the effectful
launch boundary. Merely checking admission in a CLI command is insufficient
because internal callers could bypass that command. Low-level FFI and bridge
functions may remain internal implementation details, but production modules
should reach them only through an authority-indexed interpreter. Explicitly
scoped test-only raw access may remain for mechanism conformance, provided it
cannot enter product or ordinary workflow paths.

### Critical: exact CUDA allocation is currently absent

The service chart and workload renderer use the NVIDIA RuntimeClass and expose
`NVIDIA_VISIBLE_DEVICES=all`. The Compose CUDA service likewise declares
`gpus: all`. Generated transient Jobs contain no exact `nvidia.com/gpu`
allocation or other binding to a protocol-admitted physical domain.

The protocol requires more than device visibility. Admission, the container or
pod's visible device set, runtime readback, and the engine's selected CUDA
identity must all agree. For an immediate whole-device profile, the following
must be bound together:

1. catalog CUDA domain identity;
2. acquired domain lock;
3. device exposed to the container or Job;
4. device identity observed inside the workload;
5. device identity recorded in the resource receipt; and
6. device provenance recorded by jitML's application evidence where required.

The existing service/workload compute scopes intentionally allow a service
Engine and transient workload Job on the same node. That is a scheduling
property, not GPU exclusion. If both can see every GPU, scoped anti-affinity does
not prevent them from spending the same physical accelerator.

### Critical: persistent custody has no current owner

The protocol says a Kind cluster, VM, daemon, persistent service, or retained
turn needs a project-local anchor that holds its own kernel handles for the
effect's lifetime. jitML currently has no such host-level component.

The Apple host Engine is long-lived when an operator starts it, and its
`HostWorkloadRegistry` provides disciplined in-process workload ownership. Its
registry state is nevertheless stored in a `TVar`; daemon exit loses the map,
generation, tombstones, and stop receipts. The persistent Kind cluster also has
a lifetime independent of that registry.

On Linux, bootstrap and tests normally run inside an ephemeral Compose
container. That container mounts the repository and Docker socket, not the
proposed fixed host protocol root. Kind, Docker containers, volumes, and the
clustered services can outlive the invocation that created them. A guest-local
file at `/var/lib/shared-host-resource-protocol` would explicitly be invalid
under the proposal.

Before adoption, jitML needs a concrete answer to all of the following:

- Which host-native or host-bound process owns the base lease?
- How is it installed, started, authenticated, upgraded, and stopped?
- How does a bootstrap invocation ask it to acquire before creating Kind?
- How does it recover or quarantine after its own crash?
- How does it observe the exact Docker/Kind/cgroup domain it owns?
- How do Linux containers access an admitted turn without inheriting protocol
  write privileges or lock handles?
- How does an auto-restarted service reacquire the same attempt and cell before
  resuming compute?

Until those questions are answered, the immediate cooperative profile can
cover foreground `jitml test`, benchmark, or direct command scopes, but it
cannot honestly cover the ordinary persistent jitML stack.

### High: current host-capacity arithmetic is not the proposed capacity law

`clusterNodeCapSubprocesses` applies the configured CPU and memory ceiling to
every materialized Kind node. The supported topology contains a control-plane
node plus a worker. The current `cluster.host-memory` prerequisite compares
physical RAM with one `nodeMemoryMiB` value plus a 4 GiB reserve.

That check is useful protection against the historical OOM incident, but it is
not a proof of the draft's host capacity law. The protocol adapter must decide
whether a base offer reserves:

- the sum of every Kind-node ceiling;
- the sum of reachable pod/workload maxima by placement;
- a measured enclosing Docker/VM ceiling; or
- another conservative, externally enforced aggregate.

Whichever model is selected must include all simultaneously reachable
control-plane, worker, platform, workload, compiler, anchor, observer, journal,
and host-reserve demand. The calculation must also account for multiple projects
using the same physical host.

### High: artifact enrollment is not presently an enforcement boundary

The draft says enrollment binds a `ProjectId` and operating-system principal to
an exact artifact digest or trusted signing policy, while a pathname, argument
vector, or self-reported digest is not artifact identity. That is a reasonable
provenance requirement, but the enforcement described later is based on
filesystem permissions granted to operating-system principals.

On typical developer machines:

- multiple repositories run as the same human account;
- local Haskell rebuilds frequently change executable bytes;
- Apple builds may be ad-hoc signed rather than signed by a stable enrollment
  authority;
- Linux images use mutable local tags such as `jitml:local`; and
- container processes may share the same host-visible user identity.

A process authorized as the principal can generally perform the same filesystem
operations regardless of which binary image it came from. The protocol itself
excludes a hostile same-principal process, confirming that artifact digest
enrollment is not by itself a mandatory-access-control mechanism.

The protocol should make one of two claims:

1. **Cooperative participant claim.** Trusted enrolled binaries verify their own
   exact release and follow the protocol. Artifact identity is provenance and
   conformance metadata, while the OS principal limits accidental exposure.
2. **Enforced artifact claim.** The platform supplies measured launch, verified
   code-signing enforcement, image-digest admission, mandatory access control,
   or another external mechanism proving that only the enrolled artifact can
   access protocol authority.

The first claim is feasible for jitML's initial development-host use. The second
requires an additional security architecture and should not be implied by the
initial release.

### High: the no-daemon decision is insufficiently demonstrated

The draft rejects a host-global daemon because it would combine policy,
scheduling, lifecycle, recovery, upgrades, and release cadence. That is one
possible daemon design, but it is not the only one.

A minimal host admission broker could own only:

- catalog verification;
- lock acquisition and custody tokens;
- serialized journal mutation;
- mechanism application/readback; and
- status and quarantine administration.

Project adapters could still own demand derivation, waiting policy, lifecycle,
cleanup interpretation, and application results. Such a broker introduces a
service availability dependency, but it removes multi-principal shared record
writes and can centralize privileged native operations. Conversely, the direct
lock design avoids a broker availability dependency but requires every project
anchor to implement or consume secure native object access and recovery
correctly.

Because the proposed topology already requires an administrator-installed root
and one persistent anchor per project, the operational comparison is not simply
"daemon versus no daemon." It is:

- one deliberately narrow shared custodian; versus
- several project custodians sharing files, locks, and journals directly.

The decision should be supported by a prototype comparing crash behavior,
upgrade behavior, privilege, observability, host startup, and failure recovery.

### High: freeze-level storage and locking semantics remain unspecified

The draft intentionally defers exact constants and platform primitives to the
core-freeze governance record. That is acceptable while the document remains a
proposal, but the missing choices are the protocol—not implementation trivia.

Before a release, the specification and vectors must settle at least:

- POSIX locking primitive and semantics (`flock`, process-associated `fcntl`, or
  open-file-description locks);
- Windows native-object or file-lock semantics and namespace selection;
- inheritance behavior across fork/exec and process creation;
- safe open rules for every root component and leaf, including link, mount,
  replacement, and filesystem-identity checks;
- fixed-page size, byte order, canonical CBOR requirements, checksum domain,
  generation-link format, and exact rejection rules;
- write offset, short-write handling, data synchronization, and platform-specific
  durability calls;
- atomic publication and recovery for the separate `catalog.cbor` and
  `catalog.sig` files;
- root and catalog behavior across offline migration;
- reader behavior while another process publishes the inactive page; and
- exact crash schedules for every write and migration prefix.

There is also a versioning inconsistency to resolve. Admission says every client
takes the epoch lock shared and retains it. The version section says
incompatible core majors contend on that object. Shared holders do not contend
with one another; an incompatible client instead appears to refuse because the
catalog's exact core major does not match. The conformance law and wording should
state the actual mechanism.

The term "Core ABI" should also be clarified. A version-pinned Haskell package
is normally compiled into each participant and does not provide a stable GHC
binary ABI across arbitrary compiler and build combinations. The interoperable
surface is the protocol wire/object/locking ABI. Calling it that would prevent
confusion about dynamic linking or compiler ABI compatibility.

### High: nested turn acquisition needs a stronger ordering law

The protocol permits an anchor to retain a base lease and later acquire a turn.
It also requires canonical all-or-nothing lock acquisition. Because the anchor
already holds its base locks, a requested turn might contain a lock that sorts
before one of the retained base locks.

Nonblocking acquisition prevents a conventional blocking deadlock, but it does
not by itself define safe canonical composition or avoid repeated livelock. The
catalog and core need an explicit law such as:

- every legal turn lock orders strictly after all locks retained by its base;
- a combined base-plus-turn lock plan is prevalidated and turn acquisition uses
  a specified suffix; or
- the base is represented by a parent object whose child-turn locking order is
  structurally separate.

The law must cover multi-domain turns and concurrent anchors attempting
different legal extensions.

### High: quarantine is safe but operationally severe

The immediate state machine sends unexpected holder death, reboot, torn state,
or uncertain cleanup to non-expiring quarantine. For a production safety
boundary that is defensible. On a development workstation, ordinary process
cancellation, forced termination, laptop reboot, or debugger failure can
otherwise make a CUDA or Metal cell unavailable until privileged intervention.

Therefore installation without complete operator tooling would be worse than no
adoption. The first usable release needs:

- status that explains the exact cell, domain, holder, record generation, and
  reason for quarantine;
- read-only diagnostics safe for unprivileged participants;
- a privileged, audited recovery or clear operation;
- exact per-mechanism absence checks;
- a controlled reprovisioning procedure; and
- tests proving that clearing one cell cannot clear an overlapping live domain.

The design should also consider whether a narrowly defined foreground workload
may move from stale `Held` to `Free` after exact enclosing-domain absence is
proved and retained output is already charged. If that is intentionally
forbidden, the operational cost should be stated explicitly.

### Medium: the initial release scope is too broad

The proposal simultaneously discusses Linux, Darwin, Windows, CPU, memory,
storage, CUDA, Metal, Neural Engine, cgroups, Job Objects, filesystem quota,
MIG, MPS, signed catalogs, isolation certificates, clean-room re-derivation,
and later ownership transfer.

The generic algebra should remain capable of expressing those extensions, but
the first release does not need to implement or validate all of them. jitML's
supported substrates require Darwin and Linux, CPU/RAM accounting, storage
reservation, whole CUDA devices, and Metal. Windows, Neural Engine, MIG, and MPS
can remain explicit unsupported rows until a participating project has a real
adoption need and real hardware evidence.

### Medium: plan and documentation ownership are intentionally incomplete

The file is correctly marked `Draft` and explicitly says it does not establish
implementation status or semantic release authority. It is indexed as a
cross-project target, but no jitML development-plan phase currently owns:

- neutral-repository governance;
- host catalog installation;
- demand-adapter implementation;
- engine authority gating;
- persistent anchor implementation;
- migration of existing clusters;
- cross-project conformance; or
- retirement of raw launch paths.

This is acceptable for review, but the document must remain non-canonical until
those responsibilities are assigned. A future phase should link to the exact
neutral release and define only jitML's adapter, migration, and evidence work;
it should not reproduce the neutral protocol's implementation plan.

## Consequences for jitML Architecture

### The run contract should remain the inner authority

The shared protocol should wrap, not replace, jitML's existing placement and
evidence interpreter. A successful resource acquisition is not model completion,
and a completed checkpoint is not proof that the host cell was safely released.
The combined result needs both:

```text
ResourceReceipt
  + CompletedRunEvidence (or typed jitML failure)
  + terminal placement cleanup observation
```

Resource cleanup must occur after jitML has gathered diagnostics and established
that its owned placement is terminal or absent. If application cleanup is
uncertain, the outer protocol must retain or quarantine the allocation rather
than turning a failed `kubectl delete`, failed host join, or unreachable provider
into `Free`.

### Product and test in-process paths must participate

The current product publisher uses `InProcessRun` on every substrate, and
backend tests deliberately execute real hardware. Conformance cannot be achieved
by wrapping only daemon-dispatched Jobs. The eventual authority boundary must
cover:

- `jitml service` Engine inference;
- daemon-dispatched Training/RL/AlphaZero/Tune Jobs;
- Apple host-dispatched workloads;
- direct product publication and training;
- benchmarks and auto-tuning that execute kernels; and
- substrate test lanes.

Compilation that does not execute an accelerator may require only base CPU,
memory, and storage capacity. Any benchmark or runtime probe that launches a
kernel requires the relevant turn.

### The cluster profile becomes adapter input, not shared policy

`dhall/cluster/resources.dhall` should remain jitML-owned. The neutral catalog
should offer cells; it should not know the names or semantics of MinIO, Pulsar,
TensorBoard, ProductRows, training budgets, or jitML roles. jitML's one adapter
should conservatively convert the profile and selected workload into generic
capacity dimensions and acceptable mechanisms.

This preserves DRYness:

- jitML owns one derivation from its domain to physical demand;
- the neutral kernel owns one admission and custody implementation; and
- application lifecycle evidence remains in jitML.

### Storage requires a deliberate settlement model

jitML's output is not automatically released when compute ends. Checkpoints,
trial state, TensorBoard data, JIT artifacts, registry layers, Pulsar ledgers,
and MinIO objects can persist. The adapter must distinguish:

- transient scratch released with the workload;
- retained project stock already covered by the persistent base;
- maximum new retained production reachable during a turn; and
- garbage collection that reduces stock only after exact deletion evidence.

The protocol record should track host-capacity ownership, not duplicate
checkpoint manifests or application evidence. jitML should settle the physical
stock delta from its authoritative storage operations before the resource turn
is retired.

## Recommended Adoption Sequence

### Stage 0: governance and topology decision

Before code adoption:

1. identify the actual participating projects and first host configurations;
2. assign neutral maintainers, review authority, release keys, and namespace
   ownership;
3. define the threat model as cooperative participant security or specify a real
   artifact-enforcement mechanism;
4. prototype direct locks and a minimal admission broker against the same
   failure scenarios;
5. select exact native primitives and durable record rules; and
6. define operator installation, status, recovery, migration, and decommission
   commands.

No jitML conformance claim should precede this stage.

### Stage 1: close jitML-local resource gaps

These changes are valuable independently of the neutral implementation:

1. add one total `HostRequirement` projection from validated jitML workloads;
2. include transient Job CPU/memory requests and limits;
3. remove all-device CUDA exposure from ordinary conforming paths;
4. bind workload/device evidence to an exact selected GPU;
5. gate production CUDA and Metal launches on an opaque authority;
6. inventory and classify every direct engine, benchmark, test, and in-process
   product path; and
7. correct host-capacity arithmetic so all reachable Kind-node and workload
   demand is conservatively represented.

This stage should preserve the existing semantic `PlanId` and run evidence
contracts.

### Stage 2: minimal cooperative cross-project release

Use the smallest release capable of proving the central value:

- Linux and Darwin only;
- preinstalled fixed root and catalog;
- conservative base cells;
- whole-device CUDA and Metal turns;
- foreground non-detaching operations;
- exact `Busy`, `Unsupported`, and `Quarantined` outcomes;
- no automatic persistent recovery claim; and
- contention tests between at least two independently built real project
  artifacts on the same host objects and physical device.

jitML test, benchmark, and finite direct-run paths are the best first consumers.

### Stage 3: enforced local-host profile

After cooperative exclusion is proven:

- apply and read back Linux enclosing CPU and RAM walls;
- validate actual cgroup hierarchy and effective values;
- give Darwin only the strengths it can demonstrate;
- settle exact CUDA/Metal device visibility; and
- add changed-subject live negatives for every advertised mechanism.

An `EnforcedCellLease` must remain impossible when any required dimension has
only admission or reactive evidence.

### Stage 4: recoverable persistent jitML base

Only this stage can cover the ordinary persistent cluster:

- implement and install the jitML project anchor;
- acquire the base before Kind or persistent services are created;
- persist Prepared/Applied/Running/Releasing/Recovering state;
- fence Docker, Kind, Kubernetes, mount, and storage effects;
- authenticate later clients attaching to the same attempt;
- recover after anchor death and host reboot;
- require exact cleanup or quarantine before reuse; and
- migrate existing clusters through an explicit offline boundary.

The process-local Apple registry remains useful as the inner workload handle
registry, nested inside this durable outer authority.

### Stage 5: extensions and ownership cutover

MIG, MPS, Neural Engine, Windows, stronger storage mechanisms, clean-room
amoebius implementation, and eventual ownership transfer should follow only
after the minimal kernel and jitML adapter have accumulated real operational
evidence. Each should be an independent extension or migration, not a reason to
delay correction of the immediate device-exclusion problem.

## Proposed jitML Conformance Gates

A future jitML adoption phase should not close until all applicable gates below
are met:

1. Every production CUDA or Metal execution path requires a live opaque
   authority for the exact physical domain.
2. Direct production launch APIs that omit authority are absent or unreachable;
   any raw mechanism-test access is explicitly test-only.
3. Generated CUDA service and workload manifests bind one admitted device and
   do not rely on `NVIDIA_VISIBLE_DEVICES=all` as allocation.
4. The base calculation conservatively covers the full reachable Kind/platform
   footprint, anchor overhead, protocol metadata, and persistent storage stock.
5. One jitML workload and one independently built participating-project workload
   contend on the same real CUDA or Metal domain and exactly one is admitted.
6. Disjoint cells or partitions proceed when the registered graph proves them
   compatible.
7. Holder death cannot turn a nonterminal or uncertain effect into a reusable
   cell.
8. Persistent Kind ownership survives CLI exit through the project anchor.
9. Anchor death, reboot, delayed provider completion, and auto-restart follow the
   documented recovery or quarantine transition.
10. Catalog, root, signer, principal, family, mechanism, device, wall, and record
    substitutions each have a changed-subject negative.
11. Quarantine status and privileged recovery give an operator enough evidence
    to act without weakening a different cell or overlapping domain.
12. The final jitML result joins its application lifecycle outcome with the exact
    resource receipt; neither receipt can manufacture the other.

## Final Assessment

The protocol is directionally valuable for jitML because it addresses a real
gap: current resource controls are local to jitML's cluster, containers, and
processes and do not prevent another project from using the same physical host
capacity or accelerator. Its resource graph, progressive assurance, base/turn
split, outer/inner lifecycle boundary, and crash conservatism should be retained.

The proposed solution is nevertheless larger and less settled than its
"minimal kernel" description suggests. For jitML, meaningful conformance reaches
deep into workload planning, Kubernetes rendering, device selection, engine
interfaces, product execution, substrate tests, persistent cluster ownership,
artifact provenance, and operator tooling. The normal persistent stack cannot
be covered by the easy profile; it requires the recoverable profile and a new
host-level custody component.

Accordingly:

- keep `shared_host_resource_protocol.md` as `Draft`;
- do not freeze the core or describe jitML as conforming yet;
- close the local all-device, resource-demand, and raw-launch gaps;
- prototype the smallest cooperative whole-device protocol with two real
  projects;
- compare direct locks with a narrowly scoped admission broker;
- design persistent anchor and recovery operations before governing Kind; and
- create development-plan ownership only after the neutral release authority,
  primitives, and migration boundary are concrete.

That path preserves the draft's strongest safety properties without making
jitML depend prematurely on an unproven cross-project operating model.
