# Shared Host Resource Protocol — Analysis

**Subject**: [`documents/engineering/shared_host_resource_protocol.md`](documents/engineering/shared_host_resource_protocol.md) at `08f12d3` (584 lines), plus its two shipped artifacts `hostgrant_probe.py` and `crash_harness.py`
**Date**: 2026-08-26
**Verdict**: **Do not adopt.** Keep §6.2, §11:524, and §4.3 as standalone findings.

> **Why this file is at the repository root.** `JitML.Docs.Check.governedMarkdownPaths`
> (`src/JitML/Docs/Check.hs:117-126`) scans exactly `README.md`, `AGENTS.md`, `CLAUDE.md`,
> `DEVELOPMENT_PLAN/**`, and `documents/**`. A file here is ungoverned: it needs no metadata
> block, has no `Referenced by` obligation, and cannot perturb `jitml docs check`. This is an
> analysis artifact, not a governed document, and it should not be moved under `documents/`
> without adding the required header.

---

## 1. Scope and method

Six independent review lenses ran against the document and this repository, each finding
backed by a command or a `file:line` citation; every finding was then handed to a separate
adversarial verifier instructed to refute it and to default to *refuted* where evidence could
not be independently reproduced. 94 findings were raised, 20 refuted outright, and the rest
retained at their verified severity — several downgraded in the process.

The findings marked **[reproduced here]** below were additionally re-run directly, by hand,
outside the review, on this host (`Darwin 25.5.0 arm64`, Colima `Linux 6.8.0-100-generic
aarch64`, GHC 9.12.4). Those are the load-bearing ones. Findings without that marker rest on
the review's own measurement plus one adversarial confirmation.

**What is not established here.** No Windows host was available, so every Windows claim in the
document remains as unverified as §11 says it is, and this analysis adds nothing to it. No
network filesystem was tested. Nothing was measured about a second participant, because none
exists.

---

## 2. Verdict

The empirical core of this document is genuinely good, and the parts worth keeping are worth
keeping regardless of what happens to the protocol. §6.2's three-mechanism matrix is correct
and reproduces cell for cell. §11:524's observation — that Darwin arbitrates all three
mechanisms against each other, so a non-conforming participant *passes* on the platform
everyone develops on — is the single most useful sentence in the file. §1's falsification
ledger and §11's not-verified register are the marks of a serious document.

The protocol built on top of that evidence is not ready, for three independent reasons, any one
of which is disqualifying:

1. **It is unsound in two places.** Admission is order-dependent, and the witness is invalid in
   containers — the deployment §6.1 explicitly designs for. Both produce silent double-books,
   which is the exact failure the document exists to prevent.
2. **§9's headline crash guarantee is contradicted by §6.2's own measurement table.**
   `FD_CLOEXEC` is an exec-time flag; it does nothing for `fork`. The document measured the
   counterexample, tabulated it at :293, and then wrote the opposite guarantee at :495.
3. **It does not address the failure jitML actually had,** and on jitML's actual hardware
   topology there is no lane where a conformance run means what §11 wants it to mean.

| # | Finding | Class | Severity |
|---|---|---|---|
| A1 | Admission is order-dependent → double-book | spec | **blocker** |
| A2 | Witness is not pid-namespace safe → double-book in containers | spec | **blocker** |
| A3 | §9's no-leak guarantee is false for `fork` without `exec` | spec | **blocker** |
| B1 | jitML's recorded failure is §10-disclaimed and already solved otherwise | fit | **blocker** |
| B2 | Every containerized jitML lane owes `Unsupported`; only the undetectable lane remains | fit | **blocker** |
| E1 | Two of four sibling repos mandate `flock`, which cannot see OFD | governance | **blocker** |
| A4 | No release operation; `acquire()` cannot produce a standing claim | spec | major |
| A5 | Live standing claims are destroyed by slot reuse | spec | major |
| A6 | A freshly installed rendezvous has no defined empty-slot encoding | spec | major |
| A7 | `lock_is_free()` unspecified and descriptor-dependent | spec | major |
| A8 | Install procedure sets modes on directories and zero files | spec | major |
| C1 | OFD unreachable from `unix-2.8.8.0`; `CApiFFI` mandatory | cost | major |
| D1 | `crash_harness.py` measures a tautology and simulates no crash | evidence | major |
| A9 | Byte-0 rule cites a measurement that does not exist | spec | minor |
| A10 | A stopped holder wedges the scope with no specified recovery | spec | minor |
| E2 | Two tracked `.py` files vs `code_quality.md:85-87` | governance | minor |
| E3 | Mandatory `## Current Status` absent; no owning phase | governance | minor |

---

## Part A — Defects in the specification

### A1. Admission is order-dependent **[reproduced here]**

§5.2:194 states that `host:memory/build` "is not a sub-share of `host:memory`; it is a
different, exclusive domain." But §5.1's `conflicts()` compares by segment prefix and returns
`True` for that pair, while §5.2's admission arithmetic is an **exact** domain match
("never a prefix sum", :188). The two paths therefore disagree about whether the same two
claims conflict, and which path runs depends on which claim arrives second.

Running §5.1's `conflicts()` verbatim against §7.2's pseudocode:

```
order 1  A(host:memory 8GiB) then B(host:memory/build *):  A=True  | B=False   → Conflicted
order 2  B(host:memory/build *) then A(host:memory 8GiB):  B=True  | A=True    → BOTH GRANTED
```

The exclusive branch sees measured holders by prefix; the measured branch cannot see exclusive
holders at all, because `total()` sums only exact matches. Conflict is not symmetric, so
admission is not a function of rendezvous state — it is a function of arrival order.

This is not a corner case in an open family. `host:memory` is one of the five **reserved**
families (§5.3:206), and §5.1:176-178 names this precise class of disagreement as "the failure
this policy exists to prevent."

**Fix**: pick one. Either reject a claim on any domain that is a strict segment-extension of a
measured domain at parse time (making `host:memory/build` malformed rather than "a different,
exclusive domain"), or make `total()` prefix-aware and define what an exclusive claim
contributes to a measured sum. The document must say which; two implementations that choose
differently disagree about conflict.

### A2. The witness is not pid-namespace safe **[reproduced here]**

§4.1:94 defines the witness as `boot | pid | process-start-time`. The word "namespace" does not
appear anywhere in the document. §3:62 declares that containers share the host kernel and are
**the same scope**, and §6.1:263 has containers participate by bind-mounting one rendezvous.
Two containers therefore write pids from *different pid namespaces* into *one* rendezvous, with
no qualifier distinguishing them.

Measured, two containers on this machine's Colima kernel:

```
container A: boot_id=87b8d539-195c-42b9-87f9-1fa4600cef1f  pid 1 starttime=91546264
container B: boot_id=87b8d539-195c-42b9-87f9-1fa4600cef1f  pid 1 starttime=91546282
```

Identical `boot_id`, so §4.1's boot check passes. Both have a process at pid 1. Container B
evaluating A's live standing claim calls `os.kill(1, 0)` — **its own** pid 1 exists — then
compares start times, gets a mismatch, and returns `GONE`. The claim is ignored and B is
admitted against a resource that is still running. §4.1:110-112 argues that witness errors are
"over-conservative rather than an admission of a second claimant"; this one is exactly the
latter.

The inverse is worse. Linux `CLK_TCK` is 100, so start times are resolved to one 10 ms tick;
measured, 20 of 20 back-to-back process pairs shared an identical start-time tick. §11:560
concedes only that processes *50 ms apart* are distinguishable. Two containers started by one
`docker compose up` land inside that window, and a **dead** claim then reads `LIVE` forever,
with §4:89-90 forbidding any reclaim rule that could clear it.

§11's not-verified register lists the container-init-as-witness question (:564) but not this.

**Fix**: qualify the pid by its pid-namespace identity (`/proc/<pid>/ns/pid` device+inode), or
state that a participant inside a pid namespace MUST report `Unsupported` for standing claims.
Also fix the encoding: §7.1:359's `<starttime>` field has no defined format, and the two
platforms' tokens are not the same kind of thing — Darwin's is a wall-clock instant, Linux's is
ticks since boot.

### A3. §9's crash guarantee is false for `fork` without `exec` **[reproduced here]**

§4.3:129-131 mandates `FD_CLOEXEC` on the grant descriptor to stop inheritance, and §9:495
rests its headline row — "`SIGKILL` of a grant holder | **No leak.** … This holds because §4.3
forbids the inherited descriptor" — entirely on that mandate.

`FD_CLOEXEC` is consulted only at `execve`. It has no effect on `fork(2)`. A holder that forks
without exec leaks its grant past its own death with the flag set exactly as §4.3 requires:

```
holder takes OFD lock with FD_CLOEXEC SET, forks (no exec), then is SIGKILLed
prober after holder death:  BLOCKED 35   -> GRANT LEAKED to the forked child
```

The falsifying row is *inside the document*: §6.2:293 tabulates "`fork`, parent exits, child
keeps the descriptor | … | OFD: survived". §6.2's supporting measurement at :328 only covers
fork-**then-exec** (`holder spawns /bin/sleep`), which is why it appeared to confirm the rule.
The word `fork` appears exactly once in the whole document — in the row that contradicts §9.

Nothing releases such a lock before reboot, and §4:89-90 forbids a reclaim rule. This is the
single most consequential error in the file, because §9 is the section that makes the whole
no-cleanup design defensible.

**Fix**: §9's guarantee must be narrowed to fork+exec, and §4.3 needs a second MUST — a
participant MUST NOT `fork` while holding a grant, or MUST close the descriptor in the child
before it does anything else. For jitML this matters directly:
`System.Posix.Process.forkProcess` is fork-without-exec and is the standard daemonization
primitive.

### A4. There is no release operation, and `acquire()` cannot produce a standing claim

§4:85 requires a standing claim to be written into the owner's slot with the lock **not held**.
§7.2:406 always calls `take_ofd_lock(s)` before publishing, never sets `kind = "standing"`, and
never releases. Nothing in the document specifies how to publish a standing claim, how to
release a grant, or how to convert one into the other. `acquire()` is the only algorithm given,
and it cannot produce two of the three claim kinds §4 defines.

### A5. Live standing claims are destroyed by slot reuse

Because a standing claim rests with its lock free, a slot holding one is indistinguishable from
an unused slot to anything that tests locks. §7.2:404's `free_slot_of_mine()` is never defined,
and no text anywhere excludes a slot whose content is a live standing claim. Instrumenting the
document's own shipped harness — which selects slots exactly this way — shows **62 of its 64
standing claims destroyed by slot reuse** in a single 300-cycle run. The capacity for a
still-running VM or cluster silently becomes free.

The same hole lets a process overwrite its own live grant: re-locking an already-held OFD
through the same descriptor succeeds.

### A6. A freshly installed rendezvous has no defined empty-slot encoding

§7.1:357-361 gives exactly one slot layout: byte 0, then a `"<kind> <boot> <pid> <starttime>"`
header line, then claims. §7.2:390-392's scan has no free/unused branch — it reads every slot
and treats a parse failure as `Malformed`, which §7.2:430 makes terminal and fail-closed. A
never-claimed slot has no header line. The document's own installer writes a single `\0`
(`crash_harness.py:23`), whose payload at offset 1 is zero-length.

Whether that is "an empty slot" or "a malformed slot" is left to each implementer, and two
participants that choose differently produce cross-participant `Malformed` — again the exact
disagreement §5.1:176-178 exists to prevent. (The adversarial verifier downgraded this from
"permanently Malformed" — the byte-0-reserved rule makes the empty-payload reading at least as
natural — but the ambiguity itself is real and unresolved.)

### A7. `lock_is_free()` is unspecified and descriptor-dependent

Every grant's liveness in §7.2 turns on `lock_is_free(s)`. The name appears once, with no
definition, no syscall, and no constant — the document supplies `F_OFD_SETLK = 90/37` at :309
but never `F_OFD_GETLK`, which appears once at :336 as an aside. The only plausible
implementation is descriptor-dependent:

```
holder holds OFD write lock on fd1
  F_OFD_GETLK via the SAME fd  -> F_UNLCK  (reports FREE)
  F_OFD_GETLK via a DIFFERENT fd -> F_WRLCK (reports HELD), l_pid = -1
```

`l_pid = -1` also means §7.1:370's MUST — "A refusal MUST name … the pid recorded in the
conflicting slot" — can only be satisfied from slot content, which §7.1:368 declares
"diagnostic only" for grants. The mandated diagnostic is drawn from a field the document says
is not authoritative.

### A8. The install procedure sets modes on two directories and zero files

§6.1:255 is explicit that "Every participant needs to write `admission.lock` — an exclusive
record lock requires a writable descriptor, measured." The complete install procedure
(:241-242, :252-254) is `sudo mkdir -p` plus `sudo chmod 1777` on the root directory and on each
participant directory. It specifies no mode or owner for `admission.lock`, `capacity`,
`reserved`, `protocol-version`, or **any slot file** — all created under `sudo`, hence
root-owned and unwritable by participants.

The mode that is granted is the one nobody needs: `1777` on the participant directory confers a
create right that §7:413 forbids anyone from exercising. The mode actually needed — write on
the pre-created files — is unstated. The document is meticulous about the adjacent trap at :247
(`mkdir -m` being a no-op on an existing directory) and then omits this entirely.

### A9. The byte-0 rule cites a measurement that does not exist

§11:566-568 lists every Windows claim as unverified and then says "§6.2's byte-0 result is the
sole basis for the byte-0 reservation that shapes the slot format on every platform." §6.2
contains no byte-0 measurement. Line 322 is the MUST itself. A rule that constrains the on-disk
format on every platform rests on a self-citation.

### A10. A stopped holder wedges the scope

§4:89-90 justifies having no TTL, no reclaim rule, and no operator cleanup "because there is
nothing whose staleness has to be guessed at." A `SIGSTOP`ped or cgroup-frozen process
falsifies that: it holds its OFD locks indefinitely and is indistinguishable from a running
one. §7.2:441 concedes exactly this for `admission.lock` — "a stopped process is
indistinguishable from a running one" — but the concession is not carried into §4 or §9, and it
says nothing about a stopped **grant** holder, which wedges its domains rather than one lock.
`SIGSTOP` appears nowhere in the file, and §7.3:470 forbids the only escape it discusses.
`docker pause` and Ctrl-Z in a test lane both produce this state.

### A11. Smaller, still real

- **The refusal set is not what the document says it is.** §7.2:420 calls them "the seven
  refusals"; the pseudocode returns eight values. `VersionMismatch` is returned (:382) and never
  tabulated; `Unsupported` is tabulated (:431) and never returned.
- **Two retry classifications are wrong.** `NoSlot` is "Yes — by its own work finishing"
  (:429), but slots consumed by that participant's own standing claims free only when the
  witness dies, which for a cluster may be never. `Conflicted` is "Yes — it ends when that
  holder does" (:426), false for the same reason.
- **Incremental acquisition deadlocks.** §3:77's ordering rule applies only *across* scopes.
  There is no within-scope ordering rule and no requirement that a demand list be complete, so
  two participants acquiring in opposite orders deadlock while both retry on the document's own
  advice.
- **Cross-scope nesting has no mechanism.** §3:77 requires acquiring outermost-scope-first, but
  §2:42 says a lock arbitrates inside one scope and across none, and §6.1:260 forbids the only
  transport between the Darwin host and the Colima guest. A guest process cannot take a
  host-scope claim by any means the document describes.
- **`capacity` cannot relate guest to host.** §5.2's units are fixed per family, but nothing
  reconciles a guest's declared `host:memory` with the host's, or with the container's cgroup
  limit. On this machine the guest's declared capacity over-promises the Mac by roughly 60 GiB.
- **Slot file permissions are unspecified**, which breaks the multi-user registration story
  §6.1:252 argues for; measured, peer slots are unreadable across users at the mode the
  reference probe creates them with.
- **Darwin boot identity regressed.** `hostgrant_probe.py:cmd_boot` uses
  `sysctl -n kern.boottime` — a calendar-tied value truncated to whole seconds. A per-boot UUID
  exists on the same host and is unused: `kern.bootsessionuuid` →
  `C0CC2BEB-2EE3-493B-9C37-67E2E11EBFC2`. The superseded FREAP document specified precisely that
  (`hostbootstrap/…:328`), so this is a regression from the text being replaced, with no stated
  reason, and §11 does not list boottime stability as unverified.

---

## Part B — Where the specification and jitML do not meet

### B1. jitML's recorded failure is the one §10 disclaims

`DEVELOPMENT_PLAN/README.md:2789`:

> The originating incident is the 2026-05-29 host lockup: a cluster-wide OOM storm during
> `jitml bootstrap` (the platform stack ran with no resource limits) made the host unresponsive
> and forced a manual reboot.

That is progressive consumption in the absence of limits. §10:508 excludes it by name — "A
store that fills during a long run, a cache that grows … none is caught by a decision taken
once, and a measured claim admits a build rather than bounding it" — and adds, correctly,
"**This is the only shared-host failure these projects have actually recorded**."

It was already fixed by the right mechanism: continuous cgroup bounds in
`src/JitML/Cluster/Resources.hs`, not an admission decision. An admission protocol would not
have prevented it and would not prevent its recurrence.

The one recorded *exclusion* failure — an edge port taken by another Kind cluster — involved a
**non-participant**, sits outside all five reserved families, and already self-recovers through
`src/JitML/Cluster/EdgePort.hs`'s candidate list. §10:512 concedes non-participants are
unconstrained. So: zero recorded jitML failures would have been prevented by this protocol.

### B2. The two-kernel topology leaves no lane where conformance is meaningful **[reproduced here]**

This machine runs Darwin 25.5.0 with Colima (`Linux 6.8.0-100-generic aarch64`, virtiofs) for
Docker — §3's two-scope structure exactly. Following §6.1:263's own instruction:

```
$ ls -lad /var/lib/hostgrant
ls: /var/lib/hostgrant: No such file or directory

$ docker run --rm -v /var/lib/hostgrant:/var/lib/hostgrant alpine ls -lad /var/lib/hostgrant
drwxr-xr-x 2 root root 4096 Aug 26 02:50 /var/lib/hostgrant
```

The Mac has no such directory, yet the container got one — Colima silently auto-created the
bind-mount source **inside the guest**, root-owned `0755` rather than the `1777` §6.1 mandates.
This is precisely the failure §6.1:264 warns about ("a container runtime that auto-creates a
missing bind-mount source turns an unestablished rendezvous into an ordinary empty directory
that succeeds every time"), triggered by §6.1:263's own recommended mount.

In this specific case §6.1:266's guard catches it — the auto-created directory has no
`protocol-version`. The dangerous configuration is the one that follows correct operator
practice: once the Mac root is established per §6.1's `sudo mkdir` recipe **and** a guest root
is established per §3:63, both exist at the same absolute path, both satisfy the
`protocol-version` guard, and neither arbitrates against the other. Nothing in the document
tells a lane which of the two it is talking to.

The consequence for jitML's lane topology:

| Lane | Runs in | Resource scope | Under §3:71-74 |
|---|---|---|---|
| `--linux-cpu` | `jitml` container | guest kernel | guest-local claim is forbidden; host-owned domains → `Unsupported` |
| `--linux-cuda` | `jitml-cuda` container | guest kernel | same |
| `--apple-silicon` | Mac host | Darwin | works — and §11:524 says Darwin **cannot detect** a non-conforming participant |

There is no point in jitML's topology where a conformance run means what §11 wants it to mean.

### B3. jitML has no valid witness for its one standing resource

The kind cluster outlives its creating process — that is the whole point of
`cluster-publication.json`. §4.1:109 requires the witness to be "the narrowest process whose
death implies the resource is gone." The narrowest Mac-side candidate is `colima`/`limactl`,
measured at 10+ days of uptime and reparented to launchd: a shared daemon, which §4.1:110
explicitly calls a defect the policy "cannot detect." A standing claim witnessed by it would be
honoured for days after `jitml cluster down`. Reading `cluster-publication.json` is strictly
better. §11:564 already lists this as unverified.

### B4. jitML cannot spell `gpu:<id>`

§5.3:219 fixes the identifier: an NVIDIA `GPU-<uuid>`, a PCI address, or a Metal `registryID`.
jitML's Metal path is `MTLCreateSystemDefaultDevice()`; `registryID` appears nowhere in `src/`,
and there is no `cudaSetDevice` or `CUDA_VISIBLE_DEVICES` anywhere. §5.3:224 then mandates
`Unsupported` — for the one reserved family that is genuinely exclusive and the one device
jitML actually contends for.

### B5. Intra-jitML contention is already eliminated by construction

`src/JitML/Test/Command.hs:256` rejects more than one substrate flag, and the run model
documented at `:217-223` runs non-partitioned stanzas "one invocation at a time, so live
substrate tests do not contend over the same cluster/device". Combined with §11:577-579's own
concession that no second participant exists on these machines, the protocol's current value is
its stated arithmetic: participants minus one, which is zero.

### B6. The fixed-slot model conflicts with jitML's existing pattern

`src/JitML/Checkpoint/Store.hs:3542-3550` creates `pointerPath <> ".lock"` **at runtime**, one
lock file per resource, and publishes by rename. §7:413 forbids creating a slot at runtime;
§7.1:373 forbids rename for lock-bearing files. Adoption is not additive here — it replaces a
working pattern in two modules.

---

## Part C — Cost of adoption

### C1. OFD is unreachable from jitML's toolchain **[reproduced here]**

```
$ ghc --version                     → 9.12.4
$ ghc-pkg field unix version        → 2.8.8.0
$ strings …/System/Posix/IO.hi | grep -i OFD   → "handleToFd"   (incidental substring only)
  exported lock API: FileLock, LockRequest, getLock, setLock, waitToSetLock
```

Zero OFD symbols. `unix-2.8.8.0` exposes only classic `fcntl` record locks. Discharging §6.2's
MUST means new FFI, and a plain `foreign import ccall "fcntl"` is **unsound on Darwin arm64**
(the variadic third argument goes on the stack, not in a register) — measured by the review as
`ret=-1 errno=22` with no lock taken while a Python prober still ACQUIREd, and, in one build
where a prior correct call had primed the stack slot, as a spurious `ret=0`. It needs `capi`;
jitML has zero `capi` imports today and `CApiFFI` is not in `GHC2024`.

Add that `struct flock` differs by platform (Darwin 24 bytes `qqihh`, Linux 32 bytes
`hhqqi4x`), putting CPP or `hsc2hs` on the unconditional build path — where today CPP exists in
exactly two modules behind an off-by-default flag.

§4.1's witness needs two further primitives `unix` also lacks (boot identity and process start
time on both platforms).

### C2. §8's obligation is broad

"A function that starts governed host work MUST NOT be callable without a grant, and the grant
MUST NOT be constructible outside the module that obtained it" reaches roughly 171 call sites
across ~36 modules, and the natural device seam — `mlpDeviceForSubstrate :: Substrate -> Env ->
MlpDevice` — is a pure function, so the type-level discharge §8:484 asks for is not a local
change.

### C3. A new host prerequisite

A root-created, world-writable `/var/lib/hostgrant` is global mutable state outside the
repository that no `jitml` command can create, verify, or repair, against a doctrine in which
everything lives under `./.build` and `./.data` and the only host prerequisite is Docker
(`CLAUDE.md`). §6.1:258 concedes any local user can hold admission or wedge the scope.

### C4. What adoption *does* buy, for free

jitML's two existing lock sites (`Checkpoint/Store.hs:3549`,
`Service/FilesystemMinIO.hs:219`) use `waitToSetLock`/`setLock` — classic `fcntl`, which §6.2's
Linux matrix places in `{fcntl, OFD}` alongside OFD. §6.2:296-299's migration argument is
correct and jitML is already on the right side of it: an OFD participant would **block** these
sites rather than ignore them. Moving them to `flock` would be the mistake.

---

## Part D — Evidence quality of the shipped artifacts

### D1. `crash_harness.py` does not measure what §7.3 claims

§7.3:446 presents 300 cycles "including simulated hard crashes where the descriptor was dropped
with no cleanup whatsoever" as establishing that the file set never grows, and :459 offers the
harness "so the number can be re-derived rather than trusted." Reading it:

- **The crash branch is a no-op.** `if random.random() < 0.25: os.close(fd); crashes += 1` vs
  `else: os.close(fd)` — byte-identical behaviour. The counter has no effect on anything. No
  crash is simulated; the descriptor is closed gracefully in both paths.
- **The headline result is arithmetically unavoidable.** The only `os.open` in the cycle loop
  (`:35`) is `O_RDWR` with zero `O_CREAT` occurrences in the file, and there is no `unlink` or
  `remove` anywhere. "File count constant" is a property of the code, not a measurement of the
  protocol.
- **The rule it says it tests is never tested.** `:48` calls `ftruncate` "the v2 rule under
  test," but the harness never reads a slot back, so the stale-tail defect §7.1:365 describes is
  not exercised.
- **There is one process, not two participants**, and no admission scan at all — only lock
  acquisition (`:38`).
- **"Identical on Darwin and Linux" is circular**: `random.seed(20260825)` fixes the cycle
  sequence, so identical output is guaranteed by the seed rather than by cross-platform
  agreement.

Meanwhile the harness *does* reproduce a real protocol defect while measuring an unrelated
property — 62 of its 64 standing claims destroyed by slot reuse (A5).

### D2. `hostgrant_probe.py` and §11's pass-criterion script

- `cmd_try` opens with `O_CREAT` (`:36`), contradicting §6.2:314's "`O_CREAT` never: slots are
  pre-created" — and reproducing, inside the conformance procedure itself, the
  unestablished-rendezvous failure §6.1:264 warns about.
- §11:540's `<the participant under test> hold "$slot"` supplies neither mechanism nor
  duration; the shipped probe requires both and raises `IndexError` for either omission.
- §11:543's `kill %1` fails on the second loop iteration, because bash has advanced the job
  number — measured, the first holder survives the script:
  ```
  conf2.sh: line 8: kill: %1: no such job
  survivors still holding: 65689
  ```
- The probe carries unused and duplicated imports — hlint-class findings, in a repo where no
  gate covers `.py`.

**None of this touches §6.2's matrix**, which was re-derived independently and holds. The
problem is confined to the artifacts offered as re-derivation aids.

---

## Part E — Governance

### E1. Two of four sibling repos mandate the opposite mechanism — the finding that decays

| Repo | Document | Lines | Mandate |
|---|---|---|---|
| jitML | Shared Host Resource Protocol | 584 | **OFD** |
| infernix | Shared Host Resource Protocol | 583 | **OFD** |
| hostbootstrap | Finite Resource Execution Authority Protocol | 854 | **`flock`** |
| amoebius | Finite Resource Execution Authority Protocol (`Status: Authoritative source`) | 869 | **`flock`** |

FREAP `hostbootstrap/…:329`: *"POSIX `fcntl`/`lockf` is a different namespace and is forbidden
for protocol locks."* OFD **is** in the `fcntl` family. By jitML's own §6.2:296-299 analysis, a
`flock` participant is invisible to an OFD participant on Linux — so if hostbootstrap ships
FREAP and jitML ships this, the two will not see each other **at all, silently**, on the one
platform where §11 says the test is meaningful. FREAP names jitML on 5 lines.

jitML's header declares the FREAP document "superseded and MUST NOT be implemented" — a
statement jitML has no standing to make about a document another repository marks
`Status: Authoritative source`.

Separately, jitML's copy and infernix's differ **only** in a two-line header/link hunk —
byte-identical prose otherwise. That does not evidence §1:19's framing that "four projects
re-measured every load-bearing claim on their own hardware"; two of the four carry one text and
the other two carry its contradiction.

This is the finding that gets more expensive with time, and it is the one to act on first.

### E2. Two tracked `.py` files against the repo's own source policy

`documents/engineering/code_quality.md:85-87`: *"There is no checked-in foreign-language source
allowlist; runtime adapter shims must also be generated by Haskell into the build/cache tree or
supplied outside the repository."*

`hostgrant_probe.py` and `crash_harness.py` are the **only two tracked `.py` files in the
repository** (`git ls-files '*.py'` → 2). `jitml lint files` rejects by extension and its list
(`.cu`, `.cc`, `.cpp`, `.metal`, `.swift`, `build.sh`) does not include `.py`, so no gate
catches them — but §11:547 anticipates this case exactly ("A repository whose source policy
forbids a tracked artifact in that language generates it instead") and jitML is on the wrong
side of its own rule. They also sit outside `lint`, whitespace checks, and the container image.

### E3. Doctrine gaps

- **`## Current Status` is mandatory here and absent.** `documents/documentation_standards.md:134`:
  "When current and target mix, a **`## Current Status`** section is mandatory: it states,
  succinctly, what is implemented today versus what the owning phase(s) will make true, and
  links to the owning phase(s) in `../DEVELOPMENT_PLAN/`." This document is entirely
  current-vs-target and has no such section — and no owning phase exists to link to.
- **No plan ownership.** `grep -rn 'hostgrant|shared_host|FREAP' DEVELOPMENT_PLAN/` returns
  nothing. §1:15 delegates adoption status to the plan; the plan has no row.
- **The index blurb describes v1 semantics the document repudiates.**
  `documents/engineering/README.md:49` still reads "one grant held by the supervising process
  with **standing capacity declared as a reserve instead**" — which §4.2:123-125 explicitly
  reverses ("Anything a participant creates and destroys is a standing claim, not a reserve").
  This is the document's only inbound link.
- **Index count is stale**: `documents/engineering/README.md:14` says "fourteen
  project-specific docs" against 19 table rows less 4 doctrine-overlap and 2 cross-project = 13.
- `jitml docs check` **passes** — none of the above is mechanically gated.

---

## Part F — What is right, and should be kept regardless

- **All of §6.2.** The 3×3 mechanism matrix reproduced cell for cell on both kernels with clean
  negative controls: Darwin 9/9 BLOCKED (one family), Linux `{flock}` vs `{fcntl, OFD}`. The
  lifetime table is correct. The migration argument (:296-299) — that keeping un-migrated
  `fcntl` participants inside the family leaves them *blocked* rather than *invisible* — is the
  strongest reasoning in the document, and jitML benefits from it for free (C4).
- **§11:524-527.** Darwin arbitrates all three mechanisms against each other, so a
  non-conforming participant passes there; the discriminating cells are off-diagonal and only
  meaningful on Linux. This should survive into whatever replaces the protocol.
- **§4.3's `FD_CLOEXEC` mandate**, narrowed per A3. It is a live hazard in shipped code:
  `defaultFileFlags` leaves `cloexec` False, jitML's spawn path runs with `close_fds` false, and
  a typed-process child was measured inheriting a lock fd. `src/JitML/Test/Command.hs:1346,1374`
  already sets `cloexec = True` elsewhere, so the two lock sites are inconsistent with the
  repo's own practice.
- **§5.1's traps.** The `\A…\Z`-not-`^…$` newline trap and the segment-boundary case
  (`gpu:0` vs `gpu:01`) are correct and reproduce, and they are the kind of thing two
  implementations really do get wrong.
- **§10 and §11's registers.** Volunteering "this one currently has none" is unusual and right.

---

## Part G — Examined and dismissed

Recorded so the ground is not re-argued. Each of these was raised during review and **refuted**
on verification:

- *"§6.1's local-filesystem MUST is justified by a `flock` fact in a document that forbids
  `flock`."* The rationale at :260 is odd in isolation, but the harm does follow: merging
  families changes who is visible to whom, and the MUST is independently correct. No network
  filesystem was tested either way.
- *"584 lines violates the 300-line brevity rule."* `documentation_standards.md:325` says "ask
  whether it should split," and nine engineering docs are longer — up to 1348 lines. Not a
  defect.
- *"`Referenced by` is not reciprocated."* It is reciprocated
  (`documents/engineering/README.md:49`), and `documentation_standards.md:387` says backlink
  reciprocity is *deliberately not enforced* anyway.
- *"`jitml docs check` fails on this document."* It passes.
- *"Linux 7.0.0-28 x86_64 does not exist."* Unverifiable from this machine; no basis to assert
  it either way. The claim is simply not reproducible here, which is a provenance limitation,
  not an error.
- Sixteen further findings, mostly restatements of the above or style opinions, were dropped on
  verification.

---

## Part H — Recommendations

### Change in the document

1. **Fix the `conflicts`/`total` asymmetry (A1).** Either reject strict segment-extensions of
   measured domains at parse time, or make `total()` prefix-aware. State which; do not leave it
   to implementers.
2. **Add a pid-namespace clause to §4.1 (A2)**, or require `Unsupported` for standing claims
   inside a pid namespace. Define the `<starttime>` encoding, and note that the two platforms'
   tokens are different kinds of value.
3. **Narrow §9's guarantee to fork+exec and add the missing MUST to §4.3 (A3).** Cite :293 as
   the reason rather than leaving it as a table row that contradicts the guarantee.
4. **Specify the missing half of §7.2 (A4-A7):** publishing a standing claim, releasing a
   grant, excluding live-standing slots from `free_slot_of_mine()`, the empty-slot encoding, and
   `lock_is_free()` — including which descriptor it may be called through.
5. **Specify file modes and ownership in §6.1 (A8).** The current install procedure does not
   work for any non-root participant.
6. **Delete the §11 byte-0 self-citation (A9)** or produce the measurement.
7. **Restore `kern.bootsessionuuid`** as the Darwin boot identity, or justify the change and add
   `kern.boottime` stability to §11's unverified register.
8. **Fix or withdraw the artifacts (D1, D2).** Either make `crash_harness.py`'s crash branch a
   real descriptor leak in a child process, add a read-back that exercises `ftruncate`, and drop
   the fixed seed — or delete the "hard crashes" and "identical on Darwin and Linux" clauses
   from §7.3. Fix `hostgrant_probe.py`'s `O_CREAT`, and make §11's script runnable (`kill $pid`,
   not `kill %1`; supply mechanism and duration).
9. **Add `## Current Status` (E3)** per `documentation_standards.md:134`, and fix
   `documents/engineering/README.md:49`, which still describes the v1 semantics §4.2 repudiates.

### Do in jitML now, independent of the protocol

1. **`FD_CLOEXEC` audit.** Set `cloexec = True` at `Checkpoint/Store.hs:3546` and
   `Service/FilesystemMinIO.hs:215`, matching what `Test/Command.hs:1346` already does, and
   review `close_fds` on the spawn path. One line each; a real latent leak; free of the
   protocol.
2. **Settle the cross-repo split (E1)** before anything else. Four repos cannot hold two
   mutually-invisible lock mandates indefinitely, and `amoebius` currently marks the *other* one
   authoritative.
3. **Fix `documents/engineering/README.md:49` and `:14`**, and mark the index entry
   not-adopted with no owning phase.
4. **Close the `EdgePort.hs` TOCTOU** with a held socket or a real lease. This is jitML's one
   genuine remaining exclusion race, and §10:512 says explicitly that this protocol cannot close
   it — the counterparty is a non-participant.
5. **Do not adopt.** Revisit if and only if a second participant on this host actually
   implements it. Until then §11:577-579's own arithmetic — value proportional to participants
   minus one — is the honest answer, and E1 means the number is currently negative rather than
   zero.

---

## Appendix — Reproduction

```sh
# A1  order-dependent admission (uses §5.1's conflicts() verbatim)
#     order 2 admits both claims

# A2  pid-namespace witness collision
for n in A B; do
  docker run --rm alpine sh -c \
    'cat /proc/sys/kernel/random/boot_id; cat /proc/1/stat | sed "s/.*) //" | awk "{print \$20}"'
done            # same boot_id, both pid 1, different start times

# A3  FD_CLOEXEC does not cover fork
#     holder sets FD_CLOEXEC, takes OFD lock, forks without exec, is SIGKILLed
#     prober -> BLOCKED 35   (grant leaked)

# B2  the Colima bind-mount trap
ls -lad /var/lib/hostgrant                       # No such file or directory
docker run --rm -v /var/lib/hostgrant:/var/lib/hostgrant alpine ls -lad /var/lib/hostgrant
                                                 # drwxr-xr-x root root — auto-created in the guest

# C1  no OFD in the toolchain
ghc-pkg field unix version                       # 2.8.8.0
strings "$(ghc-pkg field unix import-dirs | awk '{print $2}')/System/Posix/IO.hi" | grep -i ofd
                                                 # only "handleToFd"

# D1  the harness cannot create a file
grep -c O_CREAT documents/engineering/crash_harness.py    # 0 in the cycle loop
python3 documents/engineering/crash_harness.py            # count constant by construction

# E1  the contradictory sibling mandate
grep -n 'forbidden for protocol locks' \
  ~/hostbootstrap/documents/engineering/shared_host_resource_protocol.md
grep -n 'Authoritative source' \
  ~/amoebius/documents/engineering/shared_host_resource_protocol.md

# E2  the only tracked Python in the repo
git ls-files '*.py'
sed -n '85,87p' documents/engineering/code_quality.md
```

Two environment notes: an empty `/var/lib/hostgrant` created inside the Colima guest during the
B2 test was removed afterwards, and nothing else on this machine was modified. `jitml docs
check` was not run in-container; the governance conclusions in E3 were evaluated statically
against `src/JitML/Docs/Check.hs`.
