# Execution Resources

**Status**: Authoritative source
**Canonical contracts**: execution-resources
**Supersedes**: N/A
**Referenced by**: [engineering index](README.md), [validation execution](validation_execution.md), [run contract](run_contract.md), [cluster topology](cluster_topology.md), [plan standards](../../DEVELOPMENT_PLAN/development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Define whole-host resource admission, process ownership, measurement and retirement for builds, diagnostics, training and qualification.

## TL;DR

**Target.** One explicit admission owns one heavy workload on a host. Admission accounts for
its native processes, VM, containers, helpers, compilers and observers together.
Configured limits are compared with actual runtime limits before numerical work.
Incomplete safety observations do not count as healthy reserves. CPU idle is
diagnostic; quotas and memory, swap, disk and monitoring constraints are enforced.

## Current Status

**Implemented boundary.** The repository has typed cluster resource profiles,
bounded Compose configurations and scoped operational guards. Container limits
do not constrain native Haskell/Metal processes, a separate image builder or an
interactive terminal client. Personal host guards are external emergency tools,
not repository qualification evidence.

**Target.** The unified admission, whole-family supervision and failure controls
below are obligations of reopened [Phase 29](../../DEVELOPMENT_PLAN/phase-29-dhall-cluster-resource-profile-kind-node-cap-and-host-ram-pr.md),
[Phase 43](../../DEVELOPMENT_PLAN/phase-43-live-cluster-lifecycle-and-publication-truth.md),
[Phase 51](../../DEVELOPMENT_PLAN/phase-51-per-pod-resource-limits-and-right-sized-replicas-from-the-dh.md),
[Phase 64](../../DEVELOPMENT_PLAN/phase-64-workload-placement-planner-and-apple-host-workload-dispatch.md)
and [Phase 160](../../DEVELOPMENT_PLAN/phase-160-functional-core-live-workflow-interpreter.md).
These target rules do not claim that the current runner enforces them or that
software can prevent every kernel panic. The [ordered development plan](../../DEVELOPMENT_PLAN/README.md#validation-foundation-refactor)
resolves current owners and transfers from superseded phase IDs; the older
references above retain contract provenance, not a second execution order.
Status and validation receipts belong to that plan.

## Scope and Authority

This document owns resource semantics. [Cluster topology](cluster_topology.md)
owns profile/node/pod arithmetic; [validation execution](validation_execution.md)
owns the durable supervisor; [run contract](run_contract.md) owns evidence and
admission. A resource refusal is not a scientific non-convergence verdict.

No absent shared protocol or unverified lock mechanism supplies admission.
Cross-project coordination requires an implemented, versioned protocol with
explicit participants and verified ownership; until then the operator refuses
incompatible heavy work instead of assuming another project has reserved space.

## Target Admission Contract

The owner obtains exclusive heavy-workload admission before starting a build,
test, experiment or training family. Nested helpers consume its declared budget;
they do not obtain a second independent allowance. An agent cannot bypass this
through native `nohup`, an interactive pane, or a copied launcher.

The immutable execution manifest declares:

| Domain | Required admission and observation |
|---|---|
| Host | Total memory/commit accounting, pressure, swap policy, free disk, reserved emergency capacity, unrelated standing load |
| VM | Named profile, configured CPU/memory/disk, actual identity and lifecycle owner |
| Container/node | Actual quota, memory, effective ancestor swap limit, PID and scratch/output limits; OOM/limit counters |
| Native family | Executable and process identities, runtime heap and CPU budget, measured footprint including relevant native/GPU allocations |
| Helpers/compiler | Transient overlap and scratch usage, included in the parent's aggregate allowance |
| Observer | Agent, terminal/multiplexer and monitoring costs counted in host reserve; lifetime independent of execution authority |

One configuration generates requested quotas and expected runtime comparisons.
A configured value is not proof that the OS applied it. The owner verifies
actual limits and process-family containment before releasing numerical work.
A compiler's `+RTS -M` does not cap the program it builds. Each Haskell child
must expose and apply its own runtime cap; the heap cap supplements whole-process
measurement rather than replacing it. Unbounded diagnostics are refused.

## Measurement Semantics

Measurements name the API/counter, units, timestamp, scope and uncertainty.
RSS, live Haskell heap, physical footprint, compressed accounting and Windows
commit are distinct values. Do not sum shared RSS as unique physical memory.
On macOS `top`'s `MEM` is physical footprint; adding compressed memory to it
again is not valid footprint accounting. A fallback that cannot observe the
required quantity reports an incomplete observation, not a passing reserve.

Native Metal executes on the host through the fixed bridge. Its resource
allowance includes host/native allocations and GPU/unified-memory accounting
where measurable. No VM allowance is presented as a native hard limit.

On a platform without a verified aggregate native memory ceiling, admission
requires bounded work, measured allocation growth, maximum observation and
retirement latency, and a reserve sufficient for the resulting overshoot.
Unknown growth or insufficient observation means scaling is not admitted.
A small warmup is not proof of a long SAC run's steady-state memory use.

Windows host commit and commit limit are observed separately from physical RAM.
A durable workload launched outside a multiplexer still shares the host with
its client. Heavy work unrelated to psmux acceptance uses headless bounded logs
without an attached psmux client. This is an observer-isolation policy, not a
claim to repair psmux or a new Windows lane for jitML. Native psmux acceptance
remains owned by the relevant sibling project.

## Enforcement and Retirement

CPU quotas remain explicit. Low CPU idle alone never delays, pauses or stops a
workload. Memory, swap, disk, PID, scratch/output limits and the availability of
required safety measurements remain enforced.

The manifest supplies task-specific finite observation and execution windows.
A short startup timer cannot replace a scientific deadline. Deadline changes
are prospective operational-policy changes; they cannot silently alter epochs,
examples, seeds, learning predicates or measured scientific counters.

A failed reserve records the failed sample when available, the predicate and
owned identities. An incomplete reader records its error and last observation
age; the last passing sample never substitutes for the missing failed sample.
Both conditions block launch or trigger bounded retirement of owned work.

Retirement attempts orderly cancellation, then bounded escalation against
verified owned identities. It records primary failure, secondary capture/cleanup
failures, surviving processes, preservation and final stop result. It neither
kills unrelated programs by name nor continues because a terminal is protected.
Observer loss is handled by the execution contract; safety-owner loss must not
leave uncontrolled numerical children.

## Explicit VM and Storage Lifecycle

VM start and stop are separate explicit operator actions. They are not side
effects of a test/build command or login/boot startup. The selected named profile
and context are recorded; a generic VM is not an automatic fallback.

Compiler scratch, caches, raw capture and archives use bounded disk-backed,
ignored homes. Host free space, packed archives and unpacked node storage have
separate allocations. Limits and helper overlap are checked before snapshot,
image import and restoration. Recovery data is retained until its replacement
and restoration have been verified; a documentation refactor authorizes no purge.
After terminal queries, preservation and owned helper retirement, the VM is
explicitly stopped. Analysis does not keep it idle.

## Windows Hosts through WSL2: Linux CPU Only

Windows may host Linux CPU validation through an explicitly created, dedicated
jitML WSL2 distribution/instance. Declare and verify its CPU, RAM and storage
allocation against the complete workload: Linux services, Docker containers,
Kind nodes, helpers, compiler scratch, output and retained data. Include the
Windows host's own reserve and the instance's actual memory/commit and disk
behavior in admission. A distro name alone is not proof of exclusive resource
ownership or effective quotas.

Install and verify all needed Linux dependencies inside the instance, including
Docker/Compose, Kind and the required toolchain. Start and stop the instance and
owned workloads explicitly. Bind-mount the repository from the Windows host
into WSL2 and use that mounted worktree, because agents cannot publish a detached
clone through Git push. Preserve human-only staging, commit and push authority.

Use `--linux-cpu` only. jitML performs no NVIDIA/CUDA work or GPU pass-through in
WSL2. Keep the existing Mac and native Linux NVIDIA venues for their declared
hardware phases. A WSL2 result proves Linux CPU behavior on that recorded venue;
Windows-exposed checkout/output paths still need their portability checks, and
native Windows filesystem or application acceptance needs its own declared
Windows validation. A missing current hardware set stops its phase in numerical
order rather than turning another venue's pass into equivalent evidence.

## Validation

The reopened owners supply controlled fixtures for stale/missing observations,
actual-limit mismatch, aggregate over-budget admission, bounded allocation,
output/disk refusal, owned-family cancellation, helper overlap, observer growth
and safety-owner death. Trigger fixture thresholds below safe host reserves;
do not deliberately exhaust the host to test panic prevention.

Run through existing supported commands after the implementation is present and
its explicitly started runtime is admitted:

```bash
# Example: container checks; Compose budgets/context come from the admitted manifest.
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-unit --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

Targeted controls run first under the [incremental rule](../../DEVELOPMENT_PLAN/development_plan_standards.md#o-incremental-readiness-and-complete-qualification-campaigns).
Native process controls run on the real host; final Metal/CUDA proof belongs to
its hardware owner. A successful fixture proves its named containment behavior,
not scientific readiness or immunity to unresolved OS faults.
