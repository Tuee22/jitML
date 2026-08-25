# Analysis: `documents/engineering/shared_host_resource_protocol.md`

**Reviewed at**: `186c252` (363 lines, `**Status**: Draft`, mtime 2026-08-25)
**Date**: 2026-08-25
**Standing**: This file is *not* a governed document. It sits at the repository root, outside
`jitml docs check`'s scan set (`src/JitML/Docs/Check.hs:125` collects `README.md`, `AGENTS.md`,
`CLAUDE.md`, `DEVELOPMENT_PLAN/**` and `documents/**` only), so it carries no metadata block and
perturbs no gate. It is a review artifact, not a contract.

> **Purpose**: A detailed, evidence-tagged assessment of the Shared Host Resource Protocol as it
> relates to jitML — what it gets right, what is measurably wrong, what adopting it would cost in
> this toolchain, and what to do instead.

---

## 0. Method, and how to read the tags

Findings were produced by six independent investigations (lock measurement on Darwin, lock
measurement across the Colima kernel boundary, document-internal consistency, jitML resource fit,
Haskell adoption cost, cross-repo governance), then each candidate finding was put through an
adversarial verifier whose default verdict was *refuted*. **100 candidates were raised; 42 survived
verification and 58 were refuted.** Only survivors appear below. A completeness critic then went
back over the document for sections nobody had scrutinised.

Every claim carries its evidence class:

- **[MEASURED]** — a probe was run on this machine and the transcript is reproduced or summarised.
  Negative controls were run before every contended cell.
- **[SOURCE]** — read out of a file in this repo or a sibling repo, cited `file:line`.
- **[REASONED]** — argued, not observed. Treated as weaker than the other two.

Constraints observed throughout: no `sudo`, no builds (`cabal`, `docker compose build`, `jitml test`
were all prohibited — a container rebuild costs ~40 minutes), no git writes, no interactive
interpreters piped into early-exit consumers. Working tree is clean; no containers or probe
processes were left running.

**Nothing in jitML implements this protocol.** `grep -rn 'hostgrant|admission\.lock|F_OFD' src/ app/
test/` returns nothing. Every consequence stated below is therefore *prospective* — a defect in the
specification and in the adoption case, not a live bug in shipped code.

---

## 1. Verdict

**Do not adopt, in any form, this quarter.**

The document's empirical core is the strongest engineering artifact in this review — its lock-family
measurements are correct and reproduce cell-for-cell on this hardware. Three independent facts sink
adoption-as-written:

1. It mandates a lock mechanism (`OFD`) and a rendezvous path (`/var/lib/hostgrant`) that **cannot
   arbitrate** with the Finite Resource Execution Authority Protocol still live in `hostbootstrap`
   and `amoebius` — which names jitML as an implementer — and it never records that the conflict
   exists.
2. Its `SIGKILL` crash guarantee is **measurably false** under its own `FD_CLOEXEC` mandate, on both
   platforms, in exactly the process shape jitML uses.
3. By its own §10 it covers **none** of the four shared-host failures jitML has actually recorded.

Do two cheap things now — reconcile the document against FREAP, and give it an honest status — and
spend the engineering budget on the recorded failures instead. Revisit only if the four projects
agree one spec, or if a device-exclusion incident is ever recorded. §6.2's measurements should
survive intact into whatever that spec becomes.

---

## 2. What the document gets right

This is not a hatchet job. Several findings below are only possible *because* the document is
precise enough to test.

- **§6.2's lock-family measurements are correct and reproduce exactly.** Independently reproduced
  all nine Darwin cells (all BLOCKED, errno 35 EAGAIN) and all nine Linux cells (two families,
  `{flock}` and `{fcntl, OFD}`), plus both lifetime rows on both platforms, with a negative control
  before every cell. Full transcripts in Appendix A. The "three mechanisms exist, not two"
  observation is the kind of thing most protocols get wrong silently. **[MEASURED]**
- **§6.2's asymmetry argument (lines 189-198) is the best reasoning in the file.** "A participant
  that has not migrated yet is **blocked rather than ignored** … moving it to `flock` would instead
  take it *out* of the family and make it invisible to everyone else" is the right criterion for
  choosing a mechanism in a mixed deployment, and it is derived from measurement rather than taste.
- **§3's thesis — "the unit of coordination is a kernel, not a machine" — is true, load-bearing, and
  diagnoses two real jitML weaknesses.** `leaseEdgePort` (`src/JitML/Cluster/EdgePort.hs:41-58`)
  probes `127.0.0.1` guest-locally for a port that also surfaces on the Mac;
  `checkMinimumHostMemory` (`src/JitML/Prerequisite/Nodes/Cluster.hs:97-101`) passes vacuously on
  Darwin because `/proc/meminfo` is absent. **Keep §3 as a review lens even if nothing else is
  adopted.** **[SOURCE]**
- **§4's one-grant-kind simplification** — a resource only contends while something runs; whatever
  runs holds the lock; anything standing is *declared* instead — eliminates reclaim rules, TTLs and
  boot identity in one move. The reserve/grant seam is the right one.
- **§7's pre-created-slot invariant** (zero files created per run, nothing to orphan) is why the
  crash story is as short as it is. Genuine design win.
- **§10 and §11 are unusually honest.** §10 concedes that progressive consumption is invisible and
  that it "is the only shared-host failure two of these projects have actually recorded" — the
  document argues against its own adoption case, in print. §11 concedes that Darwin passes
  non-conforming implementations, i.e. that the platform the authors develop on cannot detect the
  defect.
- **§1's rejected-alternatives table** is good practice: four falsified claims and two
  self-corrections recorded so the same ground is not re-argued. The `rename(2)` row in particular
  is a real bug caught before it shipped.
- **§8 does not overclaim.** "A granted lock is coordination, not evidence… Existing enforcement is
  unaffected and is not replaced" is exactly right, and it is why B4 below is a defect in the
  adoption case rather than in the document.

---

## 3. Blocking problems

### B1. The mandate cannot arbitrate with the family protocol still on disk in two sibling repos, and the document never says so — [MEASURED + SOURCE]

§6.2: "**OFD is mandated** … Moving it to `flock` would instead take it *out* of the family and make
it invisible to everyone else."

FREAP, `hostbootstrap/documents/engineering/shared_host_resource_protocol.md:329`: "Use the same
no-follow, close-on-exec … BSD `flock` protocol … POSIX `fcntl`/`lockf` is a different namespace and
is **forbidden** for protocol locks."

FREAP — *Finite Resource Execution Authority Protocol* — is the current text in `hostbootstrap`
(854 lines, untracked, mtime 2026-08-24 14:18:49) and in `amoebius` (869 lines, last touched
`d618ede` 2026-08-24 14:38:11, and the only copy of anything in this family marked `**Status**:
Authoritative source`). It names jitML on five lines, including a per-project gap row (`:730`) and an adoption row
(`:753` — "keep a lease anchor for persistent clusters; render every CPU/RAM/storage/GPU wall and
exact granted device identity from authority rather than free text"). The jitML document
contains **zero** occurrences of `FREAP`, `hostbootstrap`, `amoebius` or `infernix`, and its header
says `**Supersedes**: N/A` even though this same path held FREAP in this repo at `eeabc7d`.

Measured in the Colima guest (`Linux 6.8.0-100-generic aarch64`), negative control before every cell:

```
flock holder vs OFD   prober -> ACQUIRED
OFD   holder vs flock prober -> ACQUIRED
```

Two participants would each be granted the same GPU / disk / memory domain, silently, with no error
on either side.

The divergence is not only mechanism:

| | This document | FREAP |
|---|---|---|
| POSIX root | `/var/lib/hostgrant` | `/var/lib/finite-resource-authority` |
| Darwin root | `/var/lib/hostgrant` | `/Library/Application Support/FiniteResourceAuthority` |
| Mechanism | OFD (`fcntl` family) | BSD `flock`; `fcntl`/`lockf` **forbidden** |
| Ownership | `1777`, world-writable | `root:finite-resource-authority`, 0770/0660 |
| CLOEXEC | MUST be **clear** | `O_CLOEXEC` |

By §6.1's own rule — "A path that is not a bind mount is a different inode and arbitrates with
nobody" — switching jitML to `flock` would still not fix it, because the roots differ too.

**Consequence for jitML:** adopting this document commits jitML to a rendezvous incompatible with
the spec that names it, and §11's sole conformance criterion — behavioural contention between two
independently built participants — is *unsatisfiable* against `hostbootstrap` and `amoebius` as
written. "Coordinating with the family" is currently false in both directions.

### B2. §11's only shipped conformance artifact cannot detect B1 — [MEASURED]

§6.2:201 states a MUST that can only be discharged empirically: "the family it lands in is a
property of that library's build and **MUST be established by measurement** rather than assumed —
see the conformance test."

§11's shipped cell is `try … ofd`, `hold … ofd &`, `try … ofd`. It is a **same-mechanism
self-contention test**. Mechanism is a parameter, and every mechanism passes, because every
mechanism excludes itself. Measured on Linux, running §11's block verbatim with the mechanism as its
argument:

```
mech=ofd    -> ACQUIRED / HOLDING / BLOCKED(11)
mech=flock  -> ACQUIRED / HOLDING / BLOCKED(11)
```

**A `flock` participant — the one family §6.2 says is "invisible to everyone else" — passes the
conformance test.** The discriminating off-diagonal cells (`flock` holder vs OFD prober → ACQUIRED;
`flock` holder vs `fcntl` prober → ACQUIRED) are never shipped and carry no stated pass criterion,
though the comment "One cell of the conformance matrix" implies a matrix that does not appear
anywhere in the document.

jitML is exactly the participant §6.2:201 is written about — it reaches locking through
`unix-2.8.8.0`, not a syscall. A gate that passes unconditionally is worse than no gate in a repo
whose stated doctrine is that a lane without its hardware **fails by design rather than vacuously
passing** (`CLAUDE.md`, Test execution).

Separately: §11 invokes `python3 hostgrant_probe.py`, and no such file exists in the repository —
untracked, and absent from every commit. Run verbatim it exits 2 with `Errno 2`.

### B3. §9's crash guarantee is false under §6.2's own mandate — [MEASURED, Darwin **and** Linux]

§9: "| `SIGKILL` of a grant holder | **No resource leaks.** The kernel releases the lock; domains are
free immediately |"
§6.2:219: "`FD_CLOEXEC` MUST be clear on the grant descriptor."

An OFD lock lives on the *open file description* and is released when the **last** descriptor
referencing it closes — not when the acquiring process dies. Clearing `FD_CLOEXEC` guarantees every
`fork`+`exec` child inherits the grant descriptor. Measured on Darwin 25.5.0 / APFS, with the
`FD_CLOEXEC`-set control ACQUIRING as expected:

```
HOLDER pid=44231 took OFD grant (FD_CLOEXEC=False)
HOLDER forked+exec'd /bin/sleep 600 as pid=44235 (inherits fd 3)
contended probe (holder alive):        BLOCKED(errno=35 EAGAIN)
>>> kill -9 44231
holder 44231 alive?                    NO
sleeper 44235:  44235  1 /bin/sleep 600        <- reparented to launchd
lsof: sleep 44235 ... 3u REG 1,15 0 222724253 .../slots_participant_0
PROBE AFTER HOLDER SIGKILLED:          BLOCKED(errno=35 EAGAIN)   <-- grant STILL HELD
probe after sleeper killed too:        ACQUIRED
```

Reproduced identically on Linux (errno 11). Across mechanisms, after `SIGKILL` of the holder with a
child holding the fd: **OFD BLOCKED, flock BLOCKED, fcntl ACQUIRED** — classic `fcntl`, the
mechanism the document rejects, is the *only* one that delivers §9's promise.

A plain `fork()` child that never execs reproduces the leak with `FD_CLOEXEC` **set**, so §9's row is
false for forked children under any flag setting; §6.2's mandate merely extends it to the
`fork`+`exec` shape jitML actually uses. §6.2's own lifetime table already measures this ("`fork`,
parent exits, child keeps the descriptor | **OFD** | SURVIVED") and no section reconciles the two
rows. §4's "MUST NOT rely on inheriting a grant across process creation" does not cure it: that
constrains what a child may *assume*, not what the kernel does.

The same construction **wedges `admission.lock` permanently**: measured, a helper spawned before the
admission window keeps the lock after the holder is SIGKILLed, so every participant on the machine
gets `Busy` forever — precisely the non-terminating retry loop §7 claims its taxonomy prevents.

**Consequence for jitML.** Every subprocess spawn funnels through `JitML.Sub.Stream` /
`JitML.Sub.Piped` (lint-enforced at `src/JitML/Lint/Stack.hs:595`), both built on `Typed.proc`.
`System.Process.proc` sets `close_fds = False`, and `typed-process-0.2.13.0` defaults
`pcCloseFds = False` (`Internal.hs:183`). A grant fd therefore reaches every `kind` / `docker` /
`helm` / `kubectl` child. Exposure is bounded by the child's remaining runtime — minutes to tens of
minutes for `kind create cluster` or `docker build` — and becomes **unbounded** the moment
`Stream.hs:120 startDetached`, written for "a process that outlives the caller" and currently
uncalled, gains its first call site. §4 has renounced every recovery route: "no reclaim rule, no
time-to-live, no boot identity and no operator escape hatch." (Recovery is not literally impossible
— `lsof` names the orphan and killing it frees the domain immediately — but the document forbids
exactly that escape hatch.)

**Minimum fix.** Make the rule conditional on process model: a participant that *replaces itself*
with `exec` MUST clear `FD_CLOEXEC`; a participant that spawns children while retaining the grant
MUST set it. Measured: keeping `FD_CLOEXEC` set and clearing it immediately before `execve` gives
both properties at once. Then condition §9's row on "no surviving descendant holds the grant
descriptor," and do the same for the `admission.lock` row.

### B4. Version 1 covers none of jitML's recorded failures — [SOURCE]

§10: "**Progressive consumption is invisible.** … This is the only shared-host failure two of these
projects have actually recorded."

Independently confirmed against the plan. All four recorded shared-host failures in jitML's history
are progressive consumption or a fixed-quantity ceiling:

| Incident | Recorded at |
|---|---|
| BookKeeper read-only under co-tenant disk pressure | `DEVELOPMENT_PLAN/README.md:853-855`, `phase-187:95-98` |
| Co-tenant disk-full event | same |
| 2026-05-29 bootstrap OOM host lockup | `DEVELOPMENT_PLAN/README.md:2789-2791` |
| Docker image-store / `-M2G` rebuild flake | `phase-65:114` |

**Zero device-exclusion incidents exist anywhere in `DEVELOPMENT_PLAN/` or `documents/`.** All four
were fixed with quantity budgets or serialisation — `jobs: 1` + `-M6G` (`docker/Dockerfile:171-188`),
Dhall `nodeMemoryMiB`/`nodeCpus` plus the `cluster.host-memory` preflight (`phase-29`,
`src/JitML/Prerequisite/Nodes/Cluster.hs:85-110`).

§5 puts the only thing that would have helped behind a version bump: "A new *quantity* costs a
revision."

This is **not** a defect in the document — §8:300-301 explicitly says "Existing enforcement is
unaffected and is not replaced," so the protocol is proposed as orthogonal, not as a replacement. It
is a defect in the **adoption case**: the engineering cost is paid against a failure class jitML has
never recorded, while the four it has recorded stay uncovered.

---

## 4. Correctness defects in the specification

Nineteen survivors, ordered by what an implementer would get wrong first.

**1. Slot writes never truncate. [MEASURED]**
§7: "Content is written **in place** … no checksum and no fixed-size padding are needed." The word
*truncate* appears nowhere in 363 lines. Slots are permanent fixtures reused run after run, so a
shorter demand leaves the previous run's tail readable. Writing `["gpu:0"]` over a slot holding four
domains reads back as all four; a mid-line splice fabricates a domain that passes §5's own regex
verbatim (`["gpu:0","gpu:1"]` then `["gpu:12"]` → `['gpu:12','pu:1']`, both valid). Holding
`admission.lock` prevents a *torn* read, not a *stale tail*.
**Fix:** "after writing, the participant MUST truncate the slot to `1 + len(payload)`" — stopping at
offset 1 to preserve §6.2's reserved byte 0.

**2. Slot payload framing is unspecified. [MEASURED]**
"a slot: OFD lock + domain list as content" is the entire format statement. No separator, no
encoding, no terminator rule; `grep -niE 'utf|encod|newline|separator|delimit'` finds two incidental
hits. §5's grammar excludes every plausible separator byte, so LF, NUL and SPACE are all defensible
readings. Every writer/reader mismatch among {LF, NUL, SPACE, CRLF} yields
`conflicts-with-gpu:0 = False` — silent double admission, **failing open**. Matched framings all
yield True. One sentence fixes it.

**3. §5's reference validator contradicts §5's prose. [MEASURED]**
Prose: "trailing whitespace is a malformed domain." The shipped regex is `^…$` with `re.match`, and
`valid("gpu:0\n") = True` while `valid("gpu:0 ") = False`. Then
`segments("gpu:0\n") = ['gpu','0\n']`, so `conflicts("gpu:0","gpu:0\n") = False`. Since §4 calls
`reserved` "line-oriented" and no normalization step exists anywhere, a participant reading that file
with an ordinary line reader validates `gpu:0\n` and then **grants `gpu:0` against a reserve** —
demonstrated end to end using the document's own two snippets. Cross-engine: Python `$`/Perl say
True; `fullmatch`, `\A…\Z` and JavaScript say False.
**Fix:** `\A…\Z`, a normalization rule, and `assert not valid("gpu:0\n")`.

**4. Operator retirement voids a live grant. [MEASURED]**
§7 sanctions "Its directory remains until an **operator** removes it" with no precondition that the
participant be idle. Unlinking a slot does not release its OFD lock, but §7's scan enumerates *by
path*:

```
scan with directory intact -> [('slots/p1/0', ['gpu:0'])]   p2 -> Conflicted
rm -rf slots/p1 (holder still alive)
scan -> []                                                   p2 -> GRANTED
```

This is the one silent double-admission the protocol produces through an action it explicitly
authorises. The same shape reaches jitML by accident: the guest rendezvous lives on the Colima VM
root disk and does not survive `colima delete`.

**5. `reserved` has a writer that takes no lock. [MEASURED]**
§9: "| Crash mid-write | **No torn read.** Content is written under `admission.lock`, which every
reader holds first |" — but §4:70 names one writer that provably does not: "edited by the operator
and by nobody else." With a reader holding a real OFD lock on `admission.lock`, a
truncate-then-write edit shows `reserved = ''`: the entire reserve set vanishes for the editor's
write latency, and admission then grants against the reserved GPU. §5's malformed-domain rule is no
backstop — of 47 byte-prefixes of a 4-line file, 24 are well-formed and still admit a reserved
demand.
**Fix:** `reserved` MUST be installed by `rename(2)` — it carries no lock to orphan (measured
torn-read-free over 22,970 concurrent reads) — and an unparseable `reserved` MUST fail closed with a
distinct refusal. §7:240's "never by rename" and §7:267's "No temporary files exist at any point"
must be scoped to lock-bearing slot files.

**6. `acquire()` has no `NoSlot` branch and no error exits. [SOURCE]**
§7 defines `NoSlot` in prose and calls it "the one an implementation could plausibly get wrong,"
then omits it from the algorithm: "pick a free slot of my own" is unconditional, with no `unlock`.
Same for a malformed `reserved`, an unreadable peer slot, or an I/O error — each leaks
`admission.lock` until process exit.
**Fix:** add `if no free slot of my own: unlock; return NoSlot`, or state the invariant "every
non-Grant exit releases `admission.lock`."

**7. The version gate has no writer, no refusal class and no upgrade path. [SOURCE]**
§7: "A participant MUST read `<root>/protocol-version` before anything else and **refuse every
operation** if it does not implement that exact revision. This is the only compatibility mechanism."
Nobody is named as the writer. An absent file is a fourth unhandled state. The four refusal classes
(`Busy`, `Conflicted`, `NoSlot`, `Unsupported`) contain no name for a version mismatch. And because
there is one file per rendezvous, a bump is a **machine-wide flag day** — every not-yet-updated
project's governed work stops until it ships a release, with no override (§4: "no operator escape
hatch"). That is a hard cross-project release coupling §6.2's cost discussion never mentions.

**8. Multi-scope demand has no composition rule, and there is no release operation. [SOURCE]**
§3:54-55 explicitly contemplates "work inside a guest that creates something on the host," but
`<root>` is never parameterized, `acquire(demand)` takes no scope argument and returns one
`Grant(fd)`, and `grep -niE 'release|revoke|amend'` finds no release operation — only
"`# released by the kernel when this process dies`". A participant refused in scope B after
succeeding in scope A can only exit or hold A's domains idle for life. **This is jitML's normal
topology**: `bootstrap/_lib.sh:271-290` runs `docker compose run --rm jitml jitml …` from the Mac
while `compose.yaml` bind-mounts the repo, so one invocation owes grants in two scopes and can take
only one.

**9. No re-entrancy rule; OFD makes a participant conflict with itself. [MEASURED, both platforms]**
§7's scan is over `<root>/slots/*/*` with no self-exemption. An OFD lock probed from any descriptor
other than the holding one reports HELD, whereas classic `F_SETLK` reports the same process's own
lock as free — so migrating a participant that probes its own slots from `fcntl` to OFD **silently
flips self-visibility**, which also qualifies §6.2's "a change of one call." jitML's exposed site is
`src/JitML/Service/HostWorkloadRegistry.hs`, which runs several host workloads concurrently in one
process, each reaching Metal at its own call site (`Service/Command.hs:1818, 2004, 2047`) with no
common hoist point.

**10. The reserved families have no identifier derivation rule, so §5:134's "costs nothing" is false. [MEASURED]**
`gpu:<id>`, `disk:<fs-id>`, `vm:<name>` — the placeholders are expanded nowhere. All ten pairs among
`gpu:0`, `gpu:metal-default`, `gpu:0x1000003ab`, `gpu:Apple-M1`, `gpu:apple/0` return
`conflicts() = False`, so two participants naming one physical GPU differently are both admitted. The
operator's `reserved` file does not patch it — a reserve is matched by the same algebra. `disk:/` is
not even encodable (`valid("disk:/") = False`), so a Linux root filesystem has no legal name. This
directly contradicts §5:114: "Two participants that disagree about well-formedness disagree about
conflict, which is the failure this policy exists to prevent."

**11. `Busy` cannot be distinguished from a wedge, and has no progress guarantee. [MEASURED]**
§9 justifies "**No wedge.** Kernel-released" from `SIGKILL` alone. A merely `SIGSTOP`ped holder is
byte-identical to a running one: `F_OFD_GETLK → l_type=F_WRLCK l_pid=-1`, `F_OFD_SETLK → EAGAIN`, on
both platforms. §7 gives `Busy` no backoff, no bound and no fairness
(`grep -niE 'retry|backoff|fair|queue|starv|timeout'` finds "retry" at :286-287 and nothing else).
Neither §10 nor §11 records this as a non-guarantee. (`lsof` *does* name the holder — the diagnostic
exists, §4 just forbids using it.)

**12. Naive FFI returns EINVAL on Apple Silicon and works in both container lanes. [MEASURED, GHC 9.12.4]**
`fcntl(2)` is variadic, and Darwin arm64 passes varargs on the stack.

```
foreign import ccall unsafe "fcntl"            -> rc=-1 errno=22 (EINVAL)
foreign import capi "fcntl.h fcntl" (CApiFFI)  -> rc=0
```

Both forms return 0 on Linux aarch64. GHC warns at neither `-Wall -Wcompat -O2`. Isolated in plain
C, the callee saw the decoy `0x1122334455667788` instead of the real pointer. This is not
OFD-specific — classic `F_SETLK` (cmd 8) breaks identically, so `Store.hs:3543` would break the same
way if hand-ported. **The failure is inverted relative to the asymmetry §6.2 argues from:** it hides
in the two containerised lanes and lands on `--apple-silicon`, the only lane that actually contends
for the Mac GPU. §11's "the conformance test is only meaningful on Linux" makes it worse.

**13. The Linux `struct flock` pack is four bytes short. [MEASURED]**
`struct.pack("hhqqi", …)` is 28 bytes; the kernel reads 32. Guard-page probe in the guest: the
32-byte buffer ending at an unmapped page returns rc=0; the document's 28-byte buffer at the same
position returns `EFAULT(14)`. It works in CPython only because `fcntl.fcntl` copies into a
1024-byte buffer. Rust and Go are unaffected (their `flock` is header-generated); hand-rolled FFI —
jitML's only option — is not.
**Fix:** `"hhqqixxxx"`, plus "implementers MUST size the buffer from `sizeof(struct flock)`."

**14. Ownership and modes are specified for one of seven paths. [MEASURED]**
`sudo mkdir -p -m 1777 /var/lib/hostgrant` is the file's only mode statement. The sticky bit is **not
inherited** — a 1777 root's `slots/` comes out `drwxr-xr-x` — so §6.1's "the sticky bit stops one
user removing another's" protects only the root's direct children, not `<root>/slots/<participant>/<n>`
where §7 actually puts them. Under umask 022 the first participant creates `slots/` and
`admission.lock` owned by itself; measured on Linux with two uids, a second unprivileged uid then
gets **EACCES** opening `admission.lock` `O_RDWR` and cannot take the lock at all. An exclusive
record lock requires a writable fd (measured: `O_RDONLY` → EBADF for both `fcntl` and OFD), so
`admission.lock` must be writable by every participant — and any uid that can write it can hold it
indefinitely, an availability failure §9 does not analyse. On jitML's Linux lanes the container is
uid 0 in the *same kernel scope* as the operator (`compose.yaml` sets no `user:`), so
root-in-container establishing the rendezvous first permanently excludes the operator.

**15. No bound on domain count or payload size. [MEASURED]**
§7 offers "held for milliseconds" as the reason `admission.lock` can be a global non-blocking mutex.
6 slots at 15-byte payloads → **0.235 ms/scan**; the same 6 slots with one 4,288,891-byte slot of
well-formed `gpu:<n>` domains → **18.724 ms/scan**, an 80× regression with no upper bound and no
refusal class for an oversized peer slot.

**16. §8's obligation is triggered by an undefined term. [SOURCE]**
"A function that starts **governed host work** MUST NOT be callable without a grant" — the phrase
appears once in 363 lines and is defined nowhere. §2's six-term glossary omits it, along with "slot"
and "admission." Is a build governed? A lint that spawns a container? `lint docs`, which is pure file
work? Each answer changes which of jitML's ~55 CLI leaves must be gated — which is the entire cost
of adoption. The failure is asymmetric and silent; §10 already concedes "A declaration is not
behaviour."

**17. Two "Measured" transcripts were not captured from where they claim. [MEASURED]**
§6.1's `ls -ld` block omits the date column BSD `ls -ld` always emits. `/var/lib/hostgrant` does not
exist on this host, and `/private/var/lib` has mtime `2026-04-30 15:33:17` — unchanged since four
months before the document's first commit (verified by control: creating *or* removing a child bumps
the parent's mtime). §9's "Measured end to end on the real rendezvous" therefore cannot mean the
mandated location; its three behaviours are real and were reproduced here, but on a scratch path.
This matters only because §11:330 says "Matching prose and matching digests establish nothing," and
the reader has no way to separate captured transcripts from composed ones.

**18. §7's install inventory does not add up. [MEASURED]**
"files after install: 8" against a specified layout of **9** regular files for "two participants with
three slots each" (measured: files 9, dirs 4, entries 13). Two readings fit — one metadata file was
omitted from the install, or one was excluded from the count (`find … ! -name 'admission.lock'`
yields exactly 8). The constancy result is unaffected, but the counting convention should be stated:
under the first reading, **the reserve-conflict branch of `acquire` was never exercised by any
measurement in the document** — and the reserve is this revision's one new idea.

**19. Minor. [REASONED]**
§6.1's NFS rationale names the wrong hazard: `flock`-emulated-as-`fcntl` *merges* families, which is
*more* exclusion and is a conformance-test problem (§11 scopes it correctly). The deployment hazard
that justifies the MUST is lost locks over a network partition with no `SIGLOST`, which would
falsify §9's "Liveness is the held lock" — and it appears nowhere. Also: three of nine code fences
(the ABNF grammar, the `<root>/` layout, the `acquire` pseudocode — the three most normative
artifacts) carry no language tag.

---

## 5. Fit with jitML

### 5.1 What jitML actually contends for, and whether §5 can name it

| Resource | Grounded at | §5 mapping |
|---|---|---|
| Metal GPU | `Engines/MetalBridge.hs:761` `MTLCreateSystemDefaultDevice()` | **No.** No enumerated id anywhere in the 1307-line bridge; `gpu:<id>` has no derivation rule |
| CUDA GPU(s) | `compose.yaml:22` `gpus: all` | **Partly.** Unnamed, all-devices; same id problem |
| Host memory | 2026-05-29 OOM; fixed by a Dhall quantity | **No.** `host:memory` is opaque and all-or-nothing; quantities cost a revision |
| Host CPU | `docker/Dockerfile:171-188` `jobs: 1` | Same |
| Disk | `/dev/disk3s5` on the Mac, `virtiofs` in the guest | **No.** Two ids for one volume; `disk:/` is not even valid |
| Docker image store | 76 GB images, 30 GB build cache | Open family at best; exclusive-only makes it unusable |
| Edge ports 9090-9092 | `Cluster/EdgePort.hs:33-58` | **Yes** — the one clean fit, as an open family |
| kind cluster | `Cluster/Helm.hs:189`, `bootstrap/_lib.sh:358` | A **reserve** per §4 — but see 5.2 |
| `.build/jitml`, `.build/jit/manifest.json`, `cluster-publication.json` | `Cache/Manifest.hs:83-90` | **Cross-scope; unarbitrable** [MEASURED] |

The domain algebra expresses **one** of jitML's nine contended resources cleanly. Everything else is
a quantity, and §5 puts quantities behind a revision.

### 5.2 The reserve has no write side — [SOURCE]

§4 nominates "a continuously-running cluster" as the reserve case. But jitML creates and destroys the
cluster *programmatically* — `kindCreateSubprocess` from `Bootstrap.hs:381`, `kindDeleteSubprocess`
from `App.hs:627` — and no jitML process survives to hold a grant. The document gives no operation to
declare, retract or verify a reserve, so `jitml cluster up` and `jitml cluster down` would bracket a
**human edit** to `/var/lib/hostgrant/reserved` in the *guest* scope. It is once per up/down cycle
rather than per bootstrap, and a stale line blocks only that domain — but the operation is missing
from the specification, not merely inconvenient.

### 5.3 Which lanes could ever hold a valid grant — [MEASURED]

**No POSIX lock mechanism crosses the Colima/virtiofs boundary in either direction.** 18/18 cells
ACQUIRED with clean negative and post-release controls, on a file proven to be the same file (a line
written inside a container was read on the Mac; both sides reported `size=19` at the same instant).
Inode identity is *not* preserved across the boundary — Mac `dev=16777231 ino=222724099`, guest
`dev=37 ino=993551` — which is also why §6.1's "different inode" phrasing cannot be turned into a
test.

The decisive positive control: a container holds OFD on the shared file; at that instant a **second
container** probing `fcntl` and `ofd` is BLOCKED(EAGAIN) while the **Mac host** probing `flock`,
`fcntl` and `ofd` all ACQUIRE. Reverse direction likewise.

Under §3's own MUST, therefore, **a jitML container lane consuming Mac GPU / memory / disk must
report `Unsupported`, never a grant.** Counting test-case literals per suite (`testCase`,
`testProperty`, `goldenVsString`; static grep, nothing executed): non-backend subtotal 900, plus
`jitml-backends` partitioned 8 `linux-cpu` / 6 `linux-cuda` / 2 `apple-silicon`. Per-lane totals:
linux-cpu 908, linux-cuda 906, apple-silicon 902 — **1814 of 2716 case-executions (66.8%) run inside
a container** and must report `Unsupported` on a Darwin host. Restricted to lanes actually runnable
on this machine (`ls /dev/nvidia*` and `ls /dev/dri` both return nothing inside a container, so
`linux-cuda` cannot run here at all), it is **908 of 1810 (50.2%)**.

Two caveats for the record. On a *Linux* host §3's table is right — containers share the host kernel
and the protocol would work for `linux-cpu`/`linux-cuda` there. The failure is specific to Darwin,
which is jitML's documented developer machine. And: a host path Colima does not share **silently
becomes an empty VM-local ext4 directory** rather than an error — the §6.1 "not a bind mount" hazard,
live and undetectable without an explicit probe.

### 5.4 Two lanes racing one GPU is not currently a jitML risk

The substrates are mutually exclusive per machine, and within one invocation
`unit_testing_policy.md:173` / `phase-153:50` already serialize stanzas. Across *processes* there is
nothing — that is the real gap, and it is intra-jitML, not cross-project.

### 5.5 One real exposure the mechanism would cover, on the platform where it works

`installFixedMetalBridge` (`Engines/MetalBridge.hs:216-247`) writes and clang-links the dylib
straight to `defaultFixedMetalBridgePath` with no staging, while `runMetalSource` `dlopen`s that same
fixed path. `writeManifestAtomic` (`Cache/Manifest.hs:83-90`) uses a fixed `<path>.tmp`. Both are
single-scope Darwin races, fixable in ~20 lines with the staging pattern `Engines/Loader.hs:167-190`
already uses. Neither needs a cross-project protocol.

---

## 6. Adoption cost in this toolchain

§6.2: "Moving such a participant to OFD is a change of one call." **False for jitML, twice over.**
[MEASURED]

- jitML has exactly **two** record-lock sites — `Checkpoint/Store.hs:3543-3550` and
  `Service/FilesystemMinIO.hs:213-220` — and **neither arbitrates host capacity**. Both are per-object
  pointer CAS on a sidecar `<path>.lock` (and `FilesystemMinIO`'s `runFilesystemMinIO` has no caller
  outside `test/`). So jitML *is* in `{fcntl, OFD}` as the survey claims, but **there is nothing to
  migrate**: every grant site is new construction, and the consoling "until it is made the
  participant is still excluded correctly" does not apply — a lock on `<checkpoint>.lock` is a
  different inode and contends with nobody.
- `unix-2.8.8.0` — bundled with the GHC 9.12.4 pinned in `cabal.project`, and the same version inside
  `jitml:local` — exposes **no OFD API at all**. `ghc --show-iface` over all 53 interface files:
  exact-case `grep -c OFD` = **0**. `System.Posix.IO` exports only `getLock` / `setLock` /
  `waitToSetLock`; the Core passes literal cmd `8`/`9` on Darwin and `6`/`7` on Linux — classic
  `F_SETLK`/`F_SETLKW`. `jitml.cabal` has no `filelock`-style dependency. §11's bullet hedges toward
  "at least one such backend is reported to prefer OFD on Linux"; the measured answer for GHC is that
  it exposes no OFD command whatsoever.

**Honest cost:**

1. **A new FFI module** with `{-# LANGUAGE CApiFFI #-}` — 0 occurrences in `src` today. `capi` is
   *required*, not preferred (defect 12). No cabal change if `capi` is used; a `c-sources` shim would
   be a first for this repo (`jitml.cabal` has no `c-sources` / `include-dirs` / `hsc2hs` /
   `cc-options`; all 49 foreign imports are `ccall "dynamic"` + `dlopen`). Per-platform `struct flock`
   layouts differ in **field order and in the lock-type constants** — Darwin 24 bytes, `l_start@0`,
   `WriteLock=3`; Linux 32 bytes, `l_type@0`, `WriteLock=1`. Measured: a transposed layout fails
   **loudly** on Darwin (EINVAL) and **silently** on Linux — parent ACQUIRED *and* child ACQUIRED,
   mutual exclusion gone with no error. `hsc2hs` or `lukko` would resolve the layout from real headers
   instead; `lukko`'s revised 0.1.2 allows the `base` GHC 9.12.4 ships, and gives real OFD on Linux
   with `flock` on Darwin — behaviourally conforming, since Darwin is one family.
2. **Classify and gate ~40 governed leaves** among the 55 registered commands, threading an
   unconstructible token through `runParsed` (`App.hs:216`, 30 arms) and `class HasEngine`
   (`Engines/HasEngine.hs:47`). The blocker is not scatter — it is `type App = ReaderT Env IO` with
   361 `liftIO` uses, plus 4 shell call sites (`bootstrap/_lib.sh:297,358,376,386-389`) that no type
   system reaches. §8 is fair about technique, and the repo already ships a working
   hidden-constructor module (`HostWorkloadRegistry`).
3. **Install in two scopes, not one.** `sudo mkdir -m 1777 /var/lib/hostgrant` on the Mac *and*
   inside the Colima guest — the Mac's `/var/lib` is not visible in the VM (Lima exports exactly one
   directory, `~`, per `~/.colima/_lima/colima/lima.yaml:13-16`), the guest root lives on `/dev/root`
   and does not survive `colima delete`, and `grep -rn colima bootstrap docker` finds nothing, so
   stage-0 has no place for it today. Plus one `compose.yaml` volume line (both services inherit the
   `x-jitml-service` anchor). `kind extraMounts` and pod `hostPath` are optional, since §3 already
   mandates `Unsupported` where the root is unreachable. The guest step *can* be automated without
   sudo via an unprivileged `docker run -v /var/lib:/hvl alpine mkdir` [MEASURED], so "the repo cannot
   ship it" would be too strong.
4. **Three rules the document does not supply**, each of which a sibling project may invent
   differently and undetectably: a multi-scope composition rule (defect 8), a retry/backoff policy
   (defect 11), and a `gpu:<id>` naming convention (defect 10).

---

## 7. Governance

### 7.1 Standing vs `documentation_standards.md` — [SOURCE]

All five metadata elements are present and formally correct, and **`jitml docs check` passes the
file** — `checkDocs`'s eight checks were traced against its content without building. The gate
validates five literal prefixes, generated-marker reconciliation, the closure scan,
`phase-N-slug.md` link resolution, taxonomy and snake_case naming, **and nothing else**. It would
catch none of this review.

What it misses here: §3 of the standard says "A **target statement must never read as an
already-implemented claim**," and the boundary is labelled in exactly one place — two subjunctive
clauses in the Purpose ("the policy jitML **would** implement"). The body carries ~15 real `MUST`
clauses and nine affirmative "Measured" transcripts, of which §6.1's install block and §7's "files
after install: 8" read as descriptions of *this machine*.

**Every prior revision carried an explicit non-adoption statement.** `2d10717:13`: "**Not adopted.**
No jitML code reads or writes the ledger, no command depends on it, and no phase owns the work." It
was removed at **`c4ee241`** (2026-08-25 15:51:08) when §1 was rewritten, and not restored.
`documents/engineering/README.md:49` indexes the file under "Cross-Project Contracts" in unqualified
present tense, so the only navigational route in frames it as an active contract. It has no
`## Current Status`; 13 of the 19 non-README engineering docs do. (The missing `## Validation` is
**not** a violation — §2's trigger is conditional on a gate proving the contract, and none exists.)

Also stale and unrelated: `documents/engineering/README.md:14` says "fourteen **project-specific**
docs" against a 13-row table, since `f1d6790`.

### 7.2 Four repos, two live drafts — [SOURCE]

| Repo | File | Lines | Title | Last touched |
|---|---|---|---|---|
| jitML | `documents/engineering/shared_host_resource_protocol.md` | 363 | Shared Host Resource Protocol | `186c252` 2026-08-25 16:04:16 |
| infernix | same path | 361 | Shared Host Resource Protocol | `54463ba` 2026-08-25 16:04:11 |
| hostbootstrap | same path | 854 | **Finite Resource Execution Authority Protocol** | untracked, mtime 2026-08-24 14:18 |
| amoebius | same path | 869 | **Finite Resource Execution Authority Protocol** (`Status: Authoritative source`) | `d618ede` 2026-08-24 14:38 |

jitML's and infernix's copies are the same text: the diff is a **single 12-line header hunk**.

§1's "Independent review in each project falsified it on four counts" describes revisions of *this
file* — accurate as to "earlier revisions", since `f1d6790:18` does contain `$HOME/.hostclaim` — but
**the rewrite reached only the two repos that already agreed with each other**, and neither of the
other two has any record of it. There is no precedence mechanism in any of the four repos, so a jitML
engineer today cannot determine which document is authoritative.

### 7.3 The deleted analysis — [SOURCE]

`documents/engineering/shared_host_resource_protocol_analysis.md` was added at `ffe49ff` (2026-08-24
23:08:38), renamed at `27cae53`, and deleted at `f1d6790`. A superseding 745-line review at `0120bcc`
re-derived its items before being consumed at `186c252`.

Most of its six disposition items are legitimately discharged or moot — the rewrite is a genre change
to a project-neutral policy, which structurally precludes jitML `src/` citations. **One item is not,
and is real at HEAD:** `renderJobMountedRunConfig` (`src/JitML/Service/Workload.hs:1736`) emits no
`resources:` block for generated transient Jobs, while
`chart/local/jitml-service/templates/deployment.yaml:74,130` renders requests and limits. Phase-51 is
✅ Done with deliverables scoped to `chart/values/*`, `chart/local/*` and `renderPerconaPGCluster`,
and no plan file mentions `renderJobMountedRunConfig`. **That defect was verified twice and is now
recorded in no governed document and no phase.**

### 7.4 No owning phase — [SOURCE]

`grep -rn 'shared_host_resource_protocol|hostgrant|Finite Resource' DEVELOPMENT_PLAN/` → nothing,
across 296 entries. This is the only one of the 20 files in `documents/engineering/` with **zero**
plan references (every other has 10-298) and the only one marked `Draft`. Not a standards violation —
nothing requires a governed doc to have an owning phase — but nothing will ever surface it as stale,
and a reader cannot tell a live proposal from an abandoned one.

---

## 8. Recommendation

**Do not adopt. Do these five things, in order.**

**1. Restore the non-adoption statement and the status boundary.** Add a `## Current Status` section
stating: no jitML code reads or writes the rendezvous, no command depends on it, no phase owns the
work. Change `documents/engineering/README.md:49` so the index entry does not read as an active
contract. Fix `documents/engineering/README.md:14` ("fourteen" → "thirteen") while there. Cost:
minutes. **This is the only blocking issue that costs something to leave alone.**

**2. Reconcile against FREAP, in the document.** Add a subsection naming the Finite Resource
Execution Authority Protocol, set `**Supersedes**` to it rather than `N/A`, state which repos have
migrated and which have not, and state the three MUST-level conflicts (root path, mechanism, CLOEXEC)
plus the measured consequence: a `flock` participant and an OFD participant **do not arbitrate at
all** on Linux. Do **not** change the OFD mandate — the measurements support it. Until the four
projects agree one spec, this document should not be described as a cross-project contract anywhere.

**3. Register the proposal in `DEVELOPMENT_PLAN/`** — one phase owning adoption or retirement. Open
one *separate* phase for the `renderJobMountedRunConfig` Job `resources:` gap, which is a real defect
at HEAD, unowned by any phase, and unrelated to this protocol.

**4. Spend the budget on the recorded failures instead.** All four are quantity, and jitML already
has the instrument:

- **(a)** A **disk-headroom preflight** alongside the existing `cluster.host-memory` node — `df` on
  the Docker data root and the repo volume, refuse below a Dhall-configured floor. Covers two of the
  four recorded incidents directly.
- **(b)** An **image-store budget check in the doctor path** — `docker system df` against a
  Dhall-configured ceiling, with a stated prune action. Covers the rebuild flake.
- **(c)** **Two single-writer advisory locks using the `fcntl` API jitML already has**
  (`System.Posix.IO.setLock`): one around `installFixedMetalBridge`
  (`Engines/MetalBridge.hs:216-247`), one around `writeManifestAtomic` (`Cache/Manifest.hs:83-90`).
  Real intra-jitML Darwin races, where all three lock families interoperate anyway. ~20 lines, no new
  dependency, no FFI.

**5. If the document is kept alive as a specification, make these exact edits.** Each fixes a
numbered defect in §4 above.

- §7: add "after writing, the participant MUST truncate the slot to `1 + len(payload)`". *(1)*
- §7: state the payload framing — UTF-8, single `LF` between domains, trailing `LF` required,
  terminator counted from offset 1. *(2)*
- §5: change the validator to `\A…\Z` (or `fullmatch`), add a normalization rule for line-terminated
  reads, add `assert not valid("gpu:0\n")`. *(3)*
- §6.2/§9: make the `FD_CLOEXEC` rule conditional on process model; add "a participant MUST NOT let
  the grant descriptor be inherited by children it spawns"; condition §9's `SIGKILL` row — and the
  `admission.lock` row — on "no surviving descendant holds the grant descriptor". *(B3)*
- §7: add `if no free slot of my own: unlock; return NoSlot`, and one error exit. *(6)*
- §7: add the retirement precondition — "an operator MUST NOT remove a participant directory while
  any of its slots is locked" — and a §9 row for rendezvous mutation. *(4)*
- §7/§9: `reserved` MUST be installed by `rename(2)`; scope "never by rename" and "no temporary
  files" to lock-bearing slot files; add a fail-closed refusal for unparseable `reserved`. *(5)*
- §5: give each reserved family a normative identifier derivation (Metal `registryID` lowercase hex,
  CUDA `GPU-<uuid>`, colons normalized), and delete or qualify "costs **nothing** … no agreement".
  *(10)*
- §6.1/§7: one paragraph on ownership, modes and who registers a participant — group-owned and
  group-writable root and `slots/`, group-writable `admission.lock`, operator-owned read-only
  `protocol-version` and `reserved`. *(14)*
- §7: name the writer of `protocol-version`, add a fifth refusal class for version mismatch, and
  state a convergent upgrade rule (higher version refuses, lower may still arbitrate). *(7)*
- §3/§7: state whether multi-scope acquisition is permitted; if so give a total order over scopes and
  an explicit release operation; if not, mandate `Unsupported`. *(8)*
- §6.2: `struct.pack("hhqqixxxx", …)` on Linux, plus "implementers MUST size the buffer from
  `sizeof(struct flock)`, not the pack width," and a note that a participant reaching `fcntl` through
  an FFI MUST use an import form that sees the real variadic prototype. *(12, 13)*
- §6.2: qualify "a change of one call" to participants calling `fcntl(2)` directly, and record in §11
  that at least one runtime (GHC's `unix`) exposes **no** OFD command at all. *(§6)*
- §11: ship the six off-diagonal conformance cells with a stated pass criterion; add a Darwin control
  cell (uncontended `try` MUST print `ACQUIRED`); say plainly that the diagonal cell establishes
  nothing about family; and either check a probe into the repo or stop naming `hostgrant_probe.py` as
  if it exists. *(B2)*
- §2: define "governed host work" (or state that the boundary is each project's and the protocol
  cannot check it); add "slot" and "admission" to the glossary. *(16)*
- §5/§7: bound domain length and domains-per-slot; treat an oversized peer slot as a stated refusal.
  *(15)*
- §6.1: replace the NFS rationale with the lost-lock reason. §6.1/§9: either state the path actually
  exercised or move the `/var/lib` establishment into §11's "Not verified". §7: state the file-count
  convention. *(17, 18, 19)*
- Tag the three untagged fences ```` ```text ````. *(19)*

---

## 9. The strongest case *for* adoption, and whether it holds

Stated as the document's author would state it:

> *This Mac runs jitML, infernix, hostbootstrap and amoebius, plus a Colima VM holding 48 of 64 GiB
> and 9 of 10 CPUs. Nothing today stops two `jitml test` runs, or a jitml run and an infernix engine,
> from landing on the one Metal GPU, the one kind cluster, or the remaining host memory. jitML's
> serialization exists only inside a single orchestrator process (`unit_testing_policy.md:173`,
> `phase-153:50`); across processes there is nothing. The failure this prevents is silent and
> undiagnosable after the fact — a slow run, a flaky test, an OOM, and no signal. The cost is four
> files, one operator `mkdir`, one lock, and a newtype the repo already has the idiom for
> (`HostWorkloadRegistry`). The measurement work is done and reproduces on your hardware. And because
> a non-migrated participant is blocked rather than ignored, partial adoption cannot make anything
> worse.*

**It partly holds.** The mechanism claims hold — every one this review depends on was re-measured.
Three legs do not:

1. **The incremental-safety leg does not apply to jitML.** jitML has no host-capacity lock site to
   migrate, so adoption is new construction — and `unix-2.8.8.0` exposes no OFD call at all, so it is
   new *FFI* construction (§6).
2. **The hazard is real in kind but unrecorded in fact.** All four shared-host failures in the repo's
   history are quantity/progressive-consumption, which §10 disclaims, and the Metal and CUDA lanes
   are mutually exclusive per machine (§5.4).
3. **Adoption forks from the family.** It commits jitML to a rendezvous and a lock family that
   contradict the FREAP spec still on disk in hostbootstrap and amoebius — which names jitML as an
   implementer (B1).

---

## 10. What this review did not verify

Mirroring the document's own §11, and held to the same standard.

- **`sudo mkdir -p -m 1777 /var/lib/hostgrant` and the SIP claim.** `sudo` was out of scope.
  `/private/var/lib` exists (`drwxr-xr-x root wheel`, contains only `postfix`), carries no
  `restricted` flag, and is absent from `/System/Library/Sandbox/rootless.conf` — which makes the
  claim plausible, but **unreproduced**. [REASONED]
- **Every Windows claim** — `LockFileEx`, `msvcrt.locking`, `ERROR_LOCK_VIOLATION`,
  `FOLDERID_ProgramData`, `CreateProcess` handle inheritance, cross-user delete denial. No Windows
  host. Worth flagging: §6.2's byte-0 mandatory-locking result is the sole empirical basis for
  "**Windows scopes MUST lock exactly one byte, byte 0**" and, transitively, for the byte-0
  reservation that shapes the slot format on **every** platform — and unlike six weaker Windows
  claims it is **not** in §11's not-verified register.
- **§7's "cycles=300 grants=300 simulated-crashes=76" harness.** The file arithmetic was checked
  (defect 18); the crash result itself was not reproduced. It is a property of the pre-created-slot
  design and there is no reason to doubt it.
- **§1's "measurement then falsified two of my own corrections."** No such measurement appears
  anywhere in the document.
- **NFS `flock` emulation** (§6.1, §11). No NFS mount available.
- **Persistence of a guest-side `/var/lib/hostgrant` across `colima stop/start/delete`.** Stopping
  Colima was out of bounds. Relevant because §7 calls slots "permanent fixtures" and the guest is a
  rebuildable VM with no operator install step anywhere in `bootstrap/*.sh`.
- **The `linux-cuda` lane end to end.** No NVIDIA device on this machine.
- **Anything requiring a build.** All test-case counts are static greps and are labelled approximate.

---

## Appendix A — measurement transcripts

Environment: host `Darwin 25.5.0 arm64` (M1 Max, 64 GiB, 10 CPUs), macOS 26.5 (25F71), SIP enabled,
scratch on `/dev/disk3s5 … (apfs, local, journaled)`. Guest: Colima under
macOS Virtualization.framework, `mountType: virtiofs`, `Linux 6.8.0-100-generic aarch64`, docker
29.2.1. Probes: independent Python, `flock` via `fcntl.flock(LOCK_EX|LOCK_NB)`, classic via
`F_SETLK/F_WRLCK`, OFD via `F_OFD_SETLK` (Darwin 90 / Linux 37), packs `"qqihh"` / `"hhqqi"`.

**Constants verified against the real SDK header, not assumed:**

```text
$(xcrun --show-sdk-path)/usr/include/sys/fcntl.h:309:#define F_OFD_SETLK  90
struct flock { off_t l_start; off_t l_len; pid_t l_pid; short l_type; short l_whence; };
struct.calcsize("qqihh") = 24   (== sizeof(struct flock) on Darwin)
```

Linux `F_OFD_SETLK = 37` verified behaviourally with a control: cmd=37 accepted, bogus cmd=137 →
`EINVAL`.

**A.1 Darwin 3×3 — negative control before EVERY cell (all controls ACQUIRED):**

```text
holder=flock prober=flock | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=flock prober=fcntl | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=flock prober=ofd   | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=fcntl prober=flock | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=fcntl prober=fcntl | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=fcntl prober=ofd   | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=ofd   prober=flock | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=ofd   prober=fcntl | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
holder=ofd   prober=ofd   | control=ACQUIRED  contended=BLOCKED(errno=35 EAGAIN)
```

**CONFIRMS the document: all nine cells BLOCK on Darwin. "One family" checks out.**

**A.2 Linux 3×3 (guest, reproduced twice independently — `/tmp` overlayfs and the virtiofs mount,
byte-for-byte identical):**

```text
holder=flock  prober=flock -> BLOCKED    fcntl -> ACQUIRED   ofd -> ACQUIRED
holder=fcntl  prober=flock -> ACQUIRED   fcntl -> BLOCKED    ofd -> BLOCKED
holder=ofd    prober=flock -> ACQUIRED   fcntl -> BLOCKED    ofd -> BLOCKED
```

**CONFIRMS the document cell-for-cell — two families, `{flock}` and `{fcntl, OFD}`.** All BLOCKED
cells errno 11 EAGAIN. Note the document says ext4; the container's `/tmp` is overlayfs and the guest
root is ext4 — same result on both. All three mechanisms also succeed *on virtiofs from inside the
guest*; none is silently emulated, and the two families stay distinct.

**A.3 Lifetime — CONFIRMS the document, on both platforms:**

| Test | flock | fcntl | OFD |
|---|---|---|---|
| Second fd to same file opened and closed (Darwin) | survived | **LOST** | survived |
| Second fd to same file opened and closed (Linux) | survived | **LOST** | survived |
| `fork`, parent exits, child keeps fd (Darwin) | survived | **LOST** | survived |
| `fork`, parent exits, child keeps fd (Linux) | survived | **LOST** | survived |

**A.4 `FD_CLOEXEC` at `exec` — CONFIRMS the document, and generalises to Darwin (the document claimed
Linux only):**

```text
ofd   CLOEXEC=1 -> after exec: ACQUIRED (released)   CLOEXEC=0 -> BLOCKED (retained)
flock CLOEXEC=1 -> ACQUIRED                          CLOEXEC=0 -> BLOCKED
fcntl CLOEXEC=1 -> ACQUIRED                          CLOEXEC=0 -> BLOCKED
```

**A.5 Cross-kernel (the decisive experiment).** 18/18 cells ACQUIRED in both directions, with
negative and post-release controls green on every cell. File identity proven: a line written from
inside a container was read on the Mac, both sides reporting `size=19` at the same instant. Inode
identity is *not* preserved — Mac `dev=16777231 ino=222724099`, guest `dev=37 ino=993551`.

Simultaneous positive control: container holds OFD → a **second container** probing `fcntl`/`ofd` is
BLOCKED(EAGAIN), while the **Mac host** probing `flock`/`fcntl`/`ofd` all ACQUIRE. Reverse: Mac host
holds OFD → a second Mac process BLOCKED on all three (errno 35), container ACQUIRES all three.

**A.6 The `SIGKILL` inheritance leak (B3):** transcript reproduced in §3 above. Reproduced identically
on Linux (errno 11). Cross-mechanism, after SIGKILL of the holder with a child holding the fd:
**ofd BLOCKED, flock BLOCKED, fcntl ACQUIRED.**

**A.7 The document's own §6.2 snippet, run verbatim.** Extracted doc lines 204-217; `diff` against
the file: IDENTICAL. `take_grant()` **works as printed** on Darwin — succeeds uncontended, raises
`OSError` contended. But `_lk()` decodes to `l_start=0 l_len=0` = **whole file**, and while it holds,
probes at byte 0, byte 1 and byte 100 all BLOCK — against the prose that byte 0 is reserved and "the
domain list starts at offset 1 everywhere, so the slot format is identical across scopes". The
snippet also never clears `FD_CLOEXEC`, which Python sets by default (`os.open()` → `FD_CLOEXEC =
True`, measured), violating the mandate printed two lines below it.

**A.8 Retirement voids a live grant (defect 4), admission scan cost (defect 15), framing divergence
(defect 2):** transcripts inline in §4.

**A.9 Rendezvous location:**

```text
/var                 -> private/var (symlink)
/var/lib              drwxr-xr-x  3 root  wheel  96  Apr 30 15:33   (contains only postfix)
                      mode=755 uid=0  W_OK=False for uid 501
/var/lib/hostgrant    ls: No such file or directory
csrutil status:       System Integrity Protection status: enabled.
```

Exclusive record locks require a writable fd (measured: `O_RDONLY ofd → EBADF`,
`O_RDONLY fcntl → EBADF`, `O_RDONLY flock → OK`), so in a `1777` root every slot and `admission.lock`
must be world-writable — letting any local uid hold admission forever, plant a bogus
`protocol-version` (§7: "refuse every operation"), or write `reserved` (§4: "permanently held"). The
sticky bit blocks deletion, not creation or locking.

**Methodology note recorded against ourselves.** The first run of the §6.2 snippet printed
all-ACQUIRED; that was traced to block-buffered stdout in the harness letting the timing loop outrun
the holder's sleep. Every result above comes from the corrected harness, with explicit `flush=True`
and a live `ps` liveness check before every probe.
