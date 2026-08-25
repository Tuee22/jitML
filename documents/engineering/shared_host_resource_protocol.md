# Shared Host Resource Protocol

**Status**: Draft
**Supersedes**: N/A
**Referenced by**: [Engineering documentation index](README.md)
**Generated sections**: none

> **Purpose**: Record how jitML would participate in the shared host claim ledger installed on a development
> machine, and the exact seam it would attach to.
> **Read this if**: you are deciding whether a cluster, a training run, or a device execution may proceed on
> a machine shared with another project.

**Not adopted.** No jitML code reads or writes the ledger, no command depends on it, and no phase owns the
work. The ledger is host configuration owned by the machine's operator; its authority is the installed root
and the `spec-version` that root carries, never a copy of a document in any repository, including this one.
This file records only what jitML would do, so no dependency on another project is created by writing it.

## Contents

- [1. The problem here](#1-the-problem-here)
- [2. What jitML would claim](#2-what-jitml-would-claim)
- [3. Where it would attach](#3-where-it-would-attach)
- [4. Local work worth doing regardless](#4-local-work-worth-doing-regardless)
- [5. Open before adoption](#5-open-before-adoption)

## 1. The problem here

Current protections are project-local: a typed cluster profile, per-node container caps, requests and limits
on platform components, placement constraints, and a process-local host workload registry. None of them is
visible to a program in another repository.

Two facts sharpen this. The host-memory prerequisite reads `/proc/meminfo` and returns success when that file
is absent, so on an Apple host it admits unconditionally. And cluster creation deletes a `kind`-owned lock
file at a fixed shared temporary path — the one machine-wide filesystem interaction in the repository, and it
removes exclusion rather than acquiring it.

## 2. What jitML would claim

- A `Persistent` claim covering the retained cluster footprint: control-plane and worker nodes, platform
  services, the object store, the message bus, observability, and the bytes those leave on disk. `Persistent`
  is the only honest kind, because a cluster outlives the command that created it and its death proves
  nothing about what remains.
- `Transient` claims for finite foreground work — tests, benchmarks, and direct runs — where process death
  genuinely returns what was charged.
- A claim holding one exact device domain for a training, tuning, inference, or benchmark execution that
  reaches an accelerator. Whole-device exclusivity is a real product tradeoff: a long training run and
  low-latency service inference cannot then share one device, and which of them takes short claims is a
  decision this project owes before adoption.

Retained output is charged and stays charged. Checkpoints, trial state, artifacts, registry layers, ledgers,
and stored objects survive the compute that produced them, so ending a run does not release their bytes.

## 3. Where it would attach

At the existing cluster host-memory prerequisite, which already runs before bring-up and already refuses.
Participation replaces a check that currently passes vacuously on Apple hosts with one that consults a shared
record, at the same point in the same sequence.

The claim wraps the existing run contract; it does not replace it. Placement, workload observation,
application evidence, cleanup, and completed results keep their authority. A granted claim is not a completed
run, and a completed checkpoint is not evidence the claim was released — resource release happens after
cleanup has established the placement is terminal or absent, and holds when that is uncertain.

## 4. Local work worth doing regardless

These are correctness debts in this repository. None depends on a ledger existing, and each is worth closing
on its own:

- Device visibility is not allocation. The service chart, the workload renderer, and the config map all set
  `NVIDIA_VISIBLE_DEVICES` to `all`, and the compose CUDA service declares `gpus: all`. Two workloads that can
  each see every device can spend the same one however carefully they were scheduled.
- Generated transient Jobs render no `resources:` block at all, while the long-lived service deployment
  renders requests and limits. The asymmetry means the heaviest work is the least bounded.
- Engine entry points take a request and probe whether a runtime is visible. No capability is required, so
  every internal caller bypasses admission by construction and checking in one command does not help.
- Semantic run budgets model epochs, trials, and games. They do not carry processor shares, peak resident
  memory, device-memory charge, exact device identity, transient compilation space, or maximum retained
  production — so there is currently nothing to convert into a charge.

## 5. Open before adoption

- No phase owns the demand projection, the record reader, the seam change, or the retirement of the raw
  launch paths above.
- Bootstrap and tests normally run inside an ephemeral container that mounts the repository and the Docker
  socket. It coordinates with the host only if the host root is mounted at the same path inside it; a
  guest-local file with that name is a different object.
- The process-local host workload registry keeps its state in memory and loses it on exit. It remains the
  right inner registry for workload handles, nested inside a claim, but it cannot itself hold one.
- Base charge arithmetic. Whether the claim reserves the sum of node ceilings, the reachable workload maxima,
  or a measured enclosing ceiling is undecided, and whichever is chosen must cover every simultaneously
  reachable demand rather than the pieces that happen to be modelled today.
