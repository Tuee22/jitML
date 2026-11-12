# Phase 263: Contract-Driven Live Execution - Fragment Issuance

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Fragment Issuance. Originally migrated from legacy Sprint 28.6 in the 2026-07-24 phase renumber; see the old→new map in [README.md](README.md).

## Current execution ownership

**Historical record; no current execution gate.** Phases 1–289 retain their
original contracts, statuses and receipts below. Their former order, dependencies
and current-sounding statements are historical. They do not gate the new
[numerical execution sequence](ordered-execution-plan.md). No historical failure
is erased and no historical Done is promoted to current qualification.

Unfinished scope is **transferred, not completed**:

- Former sprint `263.2` → [309](phase-309-fragment-issuer-machinery.md).
- Former sprint `263.3` → [322](phase-322-cpu-browser-and-fragment.md).

The [transfer register](ordered-plan-transfers.md) assigns implementation and
real-input acceptance separately. The complete retained contract is inherited;
examples or wrappers do not replace its detailed unmet requirements.

## Historical plan and evidence

## Phase State

⏸️ **Blocked** on the expanded campaign obligations below. Historical closure
remains scoped to the execution and implementation it actually proved.

The [validation foundation refactor](README.md#validation-foundation-refactor)
owns the current execution order. Sprint `221.2` first updates the source
catalogue/checkers for the reopened sprint graph; those source changes are not
part of this documentation-only revision. Current machine projection still
reflects the old catalogue and must not be reported as validating these targets.

The [execution contract](../documents/engineering/validation_execution.md) and
[resource contract](../documents/engineering/execution_resources.md) state the
new targets. Atomic row recovery is not implemented or authorized by prose: until
`261.2` passes, existing qualification remains non-resumable. No historical partial
attempt, diagnostic review copy or readiness ledger is adopted as qualification.

## Sprint 263.2: Common campaign fragment issuer [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.2`, Sprint `260.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

The common fragment issuer consumes the authenticated complete-campaign capability. Its protocol proof is available to every lane without requiring prior CPU scientific admission.

### Deliverables

- Produce no fragment from a row count, narrative table, diagnostic ledger, partial campaign or unverified persisted receipt.
- Bind issued fragments to exact source/criterion/contract and lane/device evidence with portable objects required for later admission.
- Verify clean-checkout portable layout and Git/Docker retention of deliberate evidence inputs; source-keyed criterion storage is runtime-critical.

### Validation

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
The existing documentation/code-quality commands below run after source parity
is implemented, inside the admitted profile; they do not execute these controls.


These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Reject foreign/stale source, diagnostic authority, missing rows/objects, substituted device evidence and a manually authored green table.
2. Round-trip the complete authenticated issuer input with exact identities and preserve prior historical fragment bytes without relabeling them current.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement the deliverables after the listed prerequisites; retain every failed or incomplete observation in its original scope.
- Complete the listed acceptance in its declared evidence scope, retain the required records, and reconcile the source status catalogue before claiming closure.

## Sprint 263.3: CPU lane admission and issued fragment [⏸️ Blocked]

**Status**: Blocked
**Blocked by**: Sprint `261.3`, Sprint `262.2`, Sprint `263.2`
**Docs to update**: `../documents/engineering/validation_execution.md`, `../documents/engineering/execution_resources.md`, `../documents/engineering/run_contract.md`, `../documents/engineering/unit_testing_policy.md`, `README.md`, `system-components.md`

### Objective

Close the CPU lane by exact admission, real aggregate/browser checks and fragment issuance from the completed current campaign. This is the CPU execution result, not a prerequisite for unrelated Apple/CUDA hardware availability.

### Deliverables

- Reopen every retained qualifying object through production Store and campaign readers before issuing the CPU fragment.
- Run the complete required CPU integration/browser/preservation lifecycle and retain the authenticated ordered55 journal, index-zero artifacts and all attempts.
- Finish original data readback, safe retirement and explicit named-VM stop; a missing required closing proof blocks admission.

### Validation

These are acceptance requirements for the target implementation. They are not
passes from this documentation change. Targeted failing controls run first; the
complete applicable stanzas run only after their actual evidence prerequisites
exist. Commands use the explicit named context and task-specific approved bounds;
cluster-running work uses the separately admitted cluster/lifecycle profile.

1. Pass the real live CPU consumer path using the current frozen campaign; establish complete coverage with no unsupported or NotRun cells.
2. Complete unfiltered CPU integration when its catalogue and live prerequisites exist; filtered acquisition is not an unfiltered standing pass.

```bash
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-integration --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml docs check
docker --context colima-jitml compose -f compose.yaml -f compose.vm-bounded.yaml run --rm jitml jitml check-code
```

### Remaining Work

- Implement the deliverables after the listed prerequisites; retain every failed or incomplete observation in its original scope.
- Complete the listed acceptance in its declared evidence scope, retain the required records, and reconcile the source status catalogue before claiming closure.

## Retained Historical Contract and Evidence

The remainder records prior implementation, commands, status and failures. Its
claims retain their original source, policy and date. Superseded launch ordering,
resource rules and uninterrupted-process requirements do not override the current
sprints above. Preserve these receipts; do not execute a historical recipe as a
current authorized campaign.

## Retained Historical Phase State

✅ **Done** (closed 2026-08-16). The committed `linux-cpu` lane fragment is issued
only from the completed scenario journal, its `DeviceEvidence` column is the 55
measured device witnesses rather than a declaration, and a run that read the
fragment *after* issuance confirmed it with zero drift.

## Sprint 263.1: Contract-Driven Live Execution - Fragment Issuance [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Test/Report.hs`, `src/JitML/Product/Matrix.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Test/RunContract.hs`,
`test/integration/Main.hs`, `test/unit/Main.hs`,
`DEVELOPMENT_PLAN/attestations/linux-cpu-report-card.md`
**Docs to update**: `system-components.md`, `../README.md`

### Objective

The committed `linux-cpu` lane fragment is issued only from the completed
scenario journal produced by the full live matrix run, so no prose table or
hand-edited totals can attest a row cell the live lane did not prove.

### Deliverables

- Issue the committed `linux-cpu` lane fragment only from the completed scenario
  journal — no prose table or hand-edited totals.
- Prove every row cell through the full-matrix live run before the fragment is
  re-issued.

### Validation

```bash
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Historical Validation

`jitml test all --live --linux-cpu` passed **11 / 11 invocations, 0 failed,
0 NotRun** in 43,940.53s on 2026-08-12 against image
`jitml:local@sha256:e36d6ca11f4cc75c231ac8ba2e7f238b1e1ce68623b550b55c94be075ad599e7`
and the nine-component single-worker `linux-cpu` publication
`6e57383cbcb8bd89b1ec08a6bd876651075e74707965f2fe31f0a1e3b28f1806`:
`jitml-integration` **197 / 197**, Playwright **77 passed**, `jitml-e2e`
**30 / 30**, `jitml-unit` **829 / 829**, `jitml-sl-canonicals` **36 / 36**,
`jitml-rl-canonicals` **47 / 47**, `jitml-hyperparameter` **26 / 26**,
`jitml-backends` **35 / 35**, `jitml-daemon-lifecycle` **54 / 54**,
`jitml-negative-controls` **3 / 3**, and `jitml-model-convergence` **111 / 111**.
`jitml docs check` and `jitml check-code` passed on the same source state. The
retained transcript is the gitignored
`.build/gate-logs/phase263-closure-gate.log`, SHA-256
`8c409f5c72477c752f7bd2ef97b5f301f49aab280428a7c66470d54efc3efc8a`.

Issuance is now derived rather than transcribed. `renderProductLaneAttestationFragment`
builds every product cell from the opaque `CompletedProductScenarioReport` — row
id, `generated-matrix:` catalog address, integration and e2e test identities, the
negative-control cell guarded by the journal-enforced pre-completion rejection
flag, the claim-level device evidence, and the executing lane — with no
`MISSING` branch, because coverage, duplicates, orphans, plan identity, lane
identity, and contract staleness already fail closed in
`projectCompletedProductScenarioReport`. `productLaneAttestationFragmentDrift`
extracts the committed table with the same predicate the legacy parser uses, so
the comparator and the parser cannot disagree about which lines are the table.
The live case `Phase 263 issues the committed lane fragment from the completed
scenario journal` renders from the **journal** report rather than the executed
one, making the comparison a cross-process re-mint from persisted HMAC-bound
rows, and reports drift per row and column.

The committed table required no edit: the run reported zero drift, so its cells
are unchanged. That is the expected outcome, not evidence the work was vacuous.
Before this phase the `DeviceEvidence` column was unverified prose that merely
happened to match — `productRowDeviceEvidenceForSubstrate` had no caller
anywhere in the repository. It is now a wrapper over the claim-level
`deviceEvidenceForClaim`, which the issuer calls and which a standing unit case
pins against the row-level composer for all 55 rows across all three substrates.

Retirement: the provenance-free `CheckpointList` renderers
(`renderCheckpointListResult`, `renderCheckpointListResultWithSelectors`,
`checkpointSelectorState`) are deleted with their exports and their two
fabricated-frame fixtures. They had no production caller;
`renderAdmittedProductBrowserCatalogue` is the sole producer of the frame the
Engine publishes, and the retired renderer omitted the `run-id`, `substrate`,
`catalogue-sha256`, and `source-journal-sha256` fields the topology validator
requires. The authenticated frame's field set stays pinned by the Phase `262`
validator/contract unit case and by the live browse cases, because
`AdmittedProductBrowserCatalogue` is abstract and cannot be forged offline.

Scope note: this phase retains the fragment-issuance surface and transfers the
harness half of the readiness contract — publishing a correlated request through
an established reply cursor instead of the diagnostic `ConsumerSessionConnected`
event — forward to Sprint `282.1` under standards rule `M(a)`. That residue is a
transport redesign rather than a deletion: `establishReplyCursor` admits only a
`FromLatest`/`Owned` subscription minted from a broker admin CREATE, while
`JitML.Test.LiveWorkflow` must keep running over the non-broker
`LocalEventSource`. The legacy prose parser, `ProductRowReportEvidence`, and the
cross-lane round-trip tests are deliberately retained for Phase `276`, which owns
retiring them; changing the fragment's wire shape here would strand the
`linux-cuda` and `apple-silicon` lanes behind the Phase `273` hardware boundary.

### Closure Evidence

`jitml test all --live --linux-cpu` passed **11 / 11 invocations, 0 failed,
0 NotRun** in 46,414.96s on 2026-08-16 against image
`jitml:local@sha256:7c83829d1fa4f67e5ea06e85082290339ea0689ccde2d45b890e9aeaf890a90b`
and a nine-component single-worker `linux-cpu` publication with
`evidence: live-readiness`: `jitml-integration` **197 / 197**, Playwright
**77 passed**, `jitml-e2e` **30 / 30**, `jitml-unit` **887 / 887**,
`jitml-sl-canonicals` **36 / 36**, `jitml-rl-canonicals` **47 / 47**,
`jitml-hyperparameter` **26 / 26**, `jitml-backends` **36 / 36**,
`jitml-daemon-lifecycle` **54 / 54**, `jitml-negative-controls` **3 / 3**, and
`jitml-model-convergence` **111 / 111**. `jitml docs check` and
`jitml check-code` passed on the same source state. The retained transcript is
the gitignored `.build/gate-logs/phase263-confirm-gate.log`, SHA-256
`d3ca4497aae5817716138855b30c73ca62576c07ae3ab2dd02260d032bc15d5a`.

The obligation this run closed is the one the 2026-08-12 issuance could not: a
fragment is proved by a run that reads it **after** issuance. The standing live
case `Phase 263 issues the committed lane fragment from the completed scenario
journal` re-mints the committed table from the persisted HMAC-bound journal in a
separate process and reports drift per row and per column; on 2026-08-15 it
reported all 55 rows' `DeviceEvidence` cells as drift, which was the
measurement, and on this run it reported **zero drift** against the re-issued
fragment, which is the proof.

The `DeviceEvidence` column is now measured rather than declared. The ten
layer-graph supervised rows carry
`device:linux-cpu:linux-cpu-onednn:onednn_matmul_forward_training:7a7009a55176f879`,
and `california-housing-mlp` plus the 44 RL / HER / AlphaZero / tuning rows
carry `device:linux-cpu:onednn:mlp-forward-backward-tanh-linear:ef7ebe1dc3f02cbb`
— two lanes of execution with different backends, executed identities, and
artifact digests, where the retired declaration-derived cell was one constant
string per row class.

Refreshing the in-cluster image for this run required rebuilding the lane. The
Kind nodes' `extraMounts` for `./.build` and `./.data` pointed at deleted
inodes, so the platform PVs (`/jitml/.data/platform/minio`,
`.../pulsar-bookie-*`, `.../pulsar-zookeeper-data`) existed only inside orphaned
directories and `jitml-service` could not mount `/opt/build` at all. A cluster
whose state is unreachable from the host cannot attest anything, so the lane was
purged and re-bootstrapped from `jitml bootstrap --linux-cpu` (111 steps, nine
components Ready) and the twelve canonical dataset objects were re-staged.

> **Note for Sprint `264.1`** — the re-issued cells pin
> `Text.take 16` of the compiled artifact's SHA-256, so any change to the
> rendered `kernel.cc` text re-breaks this drift gate. A shared operator layer
> that concatenates as `primitives <> operators` does **not** reproduce the
> current interleaved emission order (measured: 941 literals become 943, with
> 228 relocated) and would silently restamp this lane's attested digest for a
> CUDA-only feature. Sprint `264.1` splits the shared layer into positional
> chunks each backend splices at its own offsets, keeping the `linux-cpu` text
> byte-identical.

### Historical Phase State

> ✅ **Done** (2026-08-12). The committed `linux-cpu` lane fragment is issued only
> from the completed scenario journal, and a standing live case fails closed on any
> drift between the committed table and that issuance.

*(Retained as historical evidence for the surface it exercised; superseded by the 2026-08-12 reopen above.)*

## Historical Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- [Validation execution](../documents/engineering/validation_execution.md),
  [execution resources](../documents/engineering/execution_resources.md),
  [run contract](../documents/engineering/run_contract.md), and
  [testing policy](../documents/engineering/unit_testing_policy.md).

**Product docs to create/update:**

- [Plan](README.md#validation-foundation-refactor), [overview](00-overview.md),
  [component inventory](system-components.md), and the corresponding lane
  report/portable evidence after actual qualification.

**Cross-references to add:**

- The current typed catalogue and [legacy removal ledger](legacy-tracking-for-deletion.md)
  name every changed owner and deprecated active path; original evidence is retained.
