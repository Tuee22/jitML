# Phase 262: Contract-Driven Live Execution - Browser and Playwright

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Browser and Playwright. Single-session phase migrated from legacy Sprint 28.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active**. Phase 261 (Sprint 261.1) closed on 2026-08-01. Browser and
Playwright evidence is now implemented against the authenticated completed-row
journal through the staged producer/catalogue/reporter refinement. Closure still
requires the final aligned `jitml:local` image, live `linux-cpu` gate, unit,
negative-control, and model-convergence standing gates, docs check, and container
code-quality gate below.

## Sprint 262.1: Contract-Driven Live Execution - Browser and Playwright [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/Checkpoint/Writer.hs`,
`src/JitML/Product/BrowserCatalogue.hs`,
`src/JitML/Product/Matrix.hs`,
`src/JitML/Product/PhaseStatus.hs`,
`src/JitML/Service/Workload.hs`,
`src/JitML/Service/Capabilities.hs`,
`src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Proto/Gc.hs`, `proto/jitml/gc.proto`,
`src/JitML/SL/Architecture.hs`,
`src/JitML/Test/BrowserEvidenceJournal.hs`,
`src/JitML/Test/Command.hs`, `src/JitML/Test/LiveE2EScope.hs`,
`src/JitML/Test/LivePlan.hs`, `src/JitML/Test/ProductScenarioJournal.hs`,
`src/JitML/Test/ProductScenarioRunner.hs`,
`src/JitML/Test/Report.hs`, `src/JitML/Web/Contracts.hs`,
`src/JitML/Test/NegativeControls.hs`,
`src/JitML/Service/FilesystemMinIO.hs`,
`web/src/Generated/Contracts.purs`, `web/src/Panels/Checkpoints.purs`,
`playwright/jitml-demo.spec.ts`, `playwright/playwright.config.ts`,
`playwright/jitml-browser-evidence-reporter.ts`, `test/unit/Main.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`,
`test/negative-controls/Main.hs`,
`test/daemon-lifecycle/SigtermRegression.hs`
**Docs to update**: `../documents/engineering/purescript_frontend.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/cli_command_surface.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/haskell_code_guide.md`,
`README.md`, `00-overview.md`, `development_plan_standards.md`,
`phase-124-bit-determinism-contract-and-retention-reconciler.md`,
`phase-174-live-minio-checkpoint-round-trip-and-retention.md`,
`phase-276-negative-control-suite.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`, `../README.md`

### Objective

This sprint owns the browser/e2e portions of Exit Definition obligations `24`,
`31`, `33`, and `34`: exact per-row integration/e2e identity, pure refinement of
authenticated evidence, lossless `Passed | Failed | NotRun` suite outcomes, and
journal-derived handoff. It adopts the binding project doctrine sections
`Typed Run Contracts`, `Architecture — Subprocesses as Typed Values`, `Tests`,
and `Test Organization` from [the project README](../README.md#doctrine-scope).

The live Playwright suite consumes the completed row artifact and measured result
published by each scenario and emits authenticated per-row browser-result cells
as explicit `Passed`, `Failed`, or `NotRun`, bound to the same `rowId` and
`PlanId`. The UI renders artifact cards only from a completely admitted
all-`Passed` source catalogue and rejects the complete live view on any missing,
mismatched, `Failed`, or `NotRun` source row, so no stdout-prefix or presence
check stands in for a measured browser outcome.

### Deliverables

- Make Playwright assertions consume the completed row artifact and measured
  result published by that scenario.
- Publish explicit `Passed`, `Failed`, and reasoned `NotRun` browser-result cells
  in the authenticated parent report, keyed to the same `rowId`/`PlanId` as the
  integration journal.
- Render live artifact cards only after the complete all-`Passed` source frame
  refines; reject the entire card set on missing, mismatched, `Failed`, or
  `NotRun` source evidence rather than rendering a partial Passed fallback.
- Publish the immutable browser catalogue only after exact live Store admission,
  write its append-only per-row archival GC roots before selector CAS, and keep
  the selector limited to choosing the current UI view. GC never reaps a
  content-addressed blob while any retained or archival-root manifest still
  references it.
- Harden the explicit `jitml internal gc` reconciler around that publication
  boundary: complete fail-closed paginated listing; canonical
  `(step descending, manifest SHA ascending)` retention; completed canonical
  ProductRow intrinsic roots; full tensor/optimizer/RNG/replay/transcript/
  substrate-artifact object coverage in one uniquely owned snapshot namespace; a
  global manifest-delete barrier; idempotent exact-key DELETE; and exact
  per-event execution outcomes.
- Give every new checkpoint transaction one deterministic snapshot namespace:
  derive `snapshot-id` as SHA-256 of canonical CBOR over
  `jitml-snapshot-v1`, the logical manifest, and sorted
  `(original-key,payload-sha)` pairs; bind every canonical original key to its
  exact
  `snapshots/<snapshot-id>/objects/<sha256(original-full-key)>` scoped key and
  payload SHA; and validate that mapping by reconstructing the logical manifest
  and re-deriving the snapshot id.
- Coordinate writers and GC through the canonical mutable `ExperimentGcFence`
  at `jitml-checkpoints/<experiment-hash>/gc/coordination-fence.txt`. It carries
  a format version, bound experiment hash, monotonic CAS revision, a separate
  monotonic writer/root-activity epoch, canonical full active
  `WriterReservation` set, and canonical `GcFenceDecision` history. Every
  reservation registration and unregister increments the writer/root-activity
  epoch; GC-only decision revisions do not.
  Absence for an event is `Open`; recorded phases are `Planned(g,event)`,
  `Cancelling(g,event)`, `Cancelled(g,event)`, `Executing(g,event)`, and
  permanent `Reaped`. Generations are contiguous from zero through the latest,
  every prior generation is complete `Cancelled`, every generation binds the
  same byte-identical semantic intent, and only the latest may be nonterminal or
  destructive. Experiment scope is required because a child
  reservation can protect another snapshot's reap target through
  `parentManifestSha`; independent per-snapshot locks lose that overlap. MinIO
  stores the exact `jitml-experiment-gc-fence-v1:` plus lowercase-hex canonical
  CBOR text envelope and must obtain those exact bytes and ETag atomically before
  CAS. GC brackets its complete fresh root view with matching observations of
  the writer/root-activity epoch, and the exact witnessed epoch is required when
  `Open` or complete `Cancelled` becomes `Planned`. GC-only revisions for sibling
  events therefore do not invalidate an otherwise-current root witness. The
  live reconciler converges this whole view in a bounded loop: epoch churn
  restarts it, and an epoch-stable fresh plan that discovers an absent exact
  durable intent persists that intent and restarts the entire view. Late ready
  publication or published-transient cleanup also counts as work and restarts
  the complete view; permanent published-only state is already current. A local
  process lock or a pair of listings is not the exclusion proof.
- Before creating its separate marker, a writer CAS-registers its full
  reservation. That transition atomically inserts the reservation and changes
  every overlapping `Planned` event to `Cancelling`; an overlapping `Executing`
  or permanent `Reaped` event rejects before marker creation. Before marker
  creation or payload mutation, the writer helps durably write each cancellation
  record and CAS the event to complete `Cancelled`. The semantic intent and
  cancellation artifact are immutable and may remain physically present across
  generations; the latest exact fence phase determines their logical activity,
  and a delayed helper can only repeat the same byte-identical PUT. Allocate the
  fixed-width lowercase-hex `attempt-id` through absent-only marker creation,
  incrementing on every conflict even for identical bytes, with no RNG/lease and
  no shared marker;
  embed the full snapshot descriptor plus attempt id in the uniquely owned
  `snapshots/<snapshot-id>/reservations/<attempt-id>.cbor` marker before any
  payload-object write; write the manifest; commit candidates directly and
  completed snapshots only after latest-pointer CAS. Successful cleanup deletes
  only that attempt's marker and then CAS-unregisters only its full fence entry,
  in that order. A marker conflict cannot prove ownership of the extant marker,
  so it leaves that attempt's entry as conservative permanent protection and
  advances through a freshly registered attempt; an already-registered exact
  reservation is likewise neither replaced nor removed. Make commit identity attempt-independent. Exact
  retry uses a fresh marker and repairs a pointer-already-final or other partial
  snapshot, but never deletes earlier state. Every crashed/leaked marker or full
  fence entry remains an active root forever even if the matching commit exists;
  commit does not override its protection. Require the exact commit for
  admission and GC eligibility, and require persisted
  commit/descriptor/payload-object admission before final completion refinement
  can construct `AdmittedCompletedCheckpoint`.
- For a zero-payload-object logical manifest, derive
  `snapshot-id = sha256(canonical-CBOR("jitml-snapshot-v1", exact logical
  manifest, []))` without inferring identity from a payload-object-key prefix. Treat
  its exact derived `committed.cbor` as the sole GC-owned key: that commit
  enables admission, retention, and GC, while a commitless legacy empty
  manifest stays decode/inspection-only, protected, and ineligible. Because GC
  object counts include the commit, reaping this zero-payload-object snapshot
  reports `reaped-objects=1`.
- Persist every complete deletion set before mutation at
  `jitml-checkpoints/<experiment>/gc/intents/<event-id>.cbor`, then, only after
  the exact fence decision is permanent `Reaped`, promote each exact completion to
  `jitml-checkpoints/<experiment>/gc/ready/<event-id>.cbor`. The stable
  `event_id` binds the experiment, manifest SHA, step, and sorted unique
  `reaped_object_keys`; those keys belong to exactly one snapshot and contain
  exactly one `committed.cbor` plus its payload-object keys. The ready event's
  substrate/timestamp are fixed once,
  publication retries are byte-stable, and broker success is followed by the
  permanent published tombstone before post-`Reaped` ready/intent cleanup. The live summary
  reports `reaped-objects`.
- After initial-plan intent persistence, converge a fresh complete view of manifests, mutable
  pointer bodies, catalogue and intrinsic roots, marker reservations, full
  experiment-fence reservations and event generations, ready records, and
  published tombstones, bracketed by matching observations of the fence's
  writer/root-activity epoch. Bound convergence to 4,096 complete-view attempts
  and fail closed if the view cannot stabilize. Epoch churn restarts the entire view. When an
  epoch-stable fresh plan discovers an exact event absent from durable intent
  state, persist its canonical intent and restart the entire complete view before
  authorization. Only the converged plan supplies the live `kept` count and
  no-op decision; creating an exact initial-plan or fresh-plan intent counts as
  reconciliation work. CAS the exact revalidated event `Open` →
  `Planned(g,event)` only at that exact epoch, then permit `Planned` → `Executing`
  only with no overlapping active entry. Cancellation first CASes
  `Planned(g,event)` to
  `Cancelling(g,event)`; coordinators, writers, or helpers then durably write
  the byte-identical `gc/cancelled/<event-id>.cbor` and CAS to complete
  `Cancelled(g,event)`. Neither cancellation nor authorization deletes the
  semantic intent or physically retires the cancellation artifact. Those stable
  objects may span generations, with only the latest exact fence phase deciding
  logical activity, so delayed old helpers have no generation-sensitive mutation
  to perform. Re-arm is forbidden until cancellation settlement completes, and
  only then can the event become `Planned(g+1,event)` after every protecting root
  and marker is gone and at the exact newly witnessed writer/root-activity epoch.
  Executors and helpers must
  re-read exact `Executing` state and consume Store's opaque authorization.
  `executeAuthorizedGcIntents` is Store's only destructive execution API; no
  plan or raw-`GcIntent` compatibility execution export remains. An absent
  target manifest remains recoverable only when the latest fence decision
  binds the byte-identical intent in `Executing` or permanent `Reaped`;
  manifest absence without that history cannot mint authority. A
  complete execution CASes to permanent `Reaped`. Persist whole-intent
  `gc/cancelled/<event-id>.cbor` state and never execute a filtered subset.
  Semantic-intent cleanup occurs only after `Reaped`, during ready/published
  terminal handling.
  The unique snapshot namespace scopes each authorized deletion key, while the
  experiment CAS prevents stale execution. Promotion checks permanent
  `gc/published/<event-id>.cbor` before and after ready PUT; publication uses the
  ready record's stored substrate through the current edge, then writes the
  exact published tombstone before post-`Reaped` ready/intent cleanup.
- Require ListObjectsV2 page one to omit continuation-token echo, every later
  page to echo the exact requested token, and keys to be globally strictly
  ascending across pages. Encode broker text as
  `jitml-gc-reaped-event-protobuf-hex-v1:` plus lowercase hex of canonical
  protobuf bytes; reject noncanonical protobuf, unsafe/aliased/cross-experiment
  keys, a key set without exactly one snapshot and one commit, forged manifest
  SHA, and forged semantic event id.
- Reject generic weighted and unweighted `JitML.Service.Workload` mutations of
  noncanonical bucket/key references and Store-owned checkpoint `manifests/`,
  `pointers/`, `snapshots/`, and `gc/` prefixes before `HasMinIO`, while
  continuing to permit ordinary canonical data keys. Filesystem-normalizing
  dot, dot-dot, empty-segment, absolute, backslash, control, and bucket aliases
  must fail before the capability call.

### Catalogue Retention Policy

Every authenticated and live-admitted immutable catalogue publication attempt
is archival. Its per-row browser-catalogue roots deliberately override ordinary
`LastN` retention and survive both selector changes and failed selector CAS
attempts. GC also treats every structurally completed manifest for a current
canonical ProductRow experiment hash as an intrinsic root. That intrinsic rule
closes the completion-to-catalogue-publication race; append-only catalogue roots
remain the durable audit/index surface and protect against later registry drift.
Inline root moves or deletion are forbidden because they can expose a selected
catalogue without roots or race a concurrent publisher. If bounded retention is
required later, an independently synchronized external lifecycle policy must
own it.

### Validation

Build the final `jitml:local` image, bring up a matching `linux-cpu` publication,
and stage the exact 12 canonical dataset objects before the live gate. Dataset
staging and publication-derived edge-port rules are the same as
[Phase 261 → Validation](phase-261-contract-driven-live-execution-integration-journal.md#validation):
the edge port comes from `.build/runtime/cluster-publication.json` and is never
hardcoded. The e2e driver borrows that healthy same-substrate publication,
runs a fresh 55-row producer inside its command-owned scope, authenticates and
re-admits the aggregate, publishes the exact browser-safe catalogue, and only
then starts Playwright. A different-substrate or incomplete publication fails
closed.

```bash
docker compose build jitml
JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 ./bootstrap/linux-cpu.sh up
```

Stage the exact canonical inventory from one host directory. This sequence is
the reproducible 12-object set; every invocation verifies the pinned SHA before
uploading, and the first live integration case fails unless the bucket contains
exactly these 12 object addresses and every fetched body verifies again.

```bash
stage_dataset() {
  docker compose run --rm \
    --volume /tmp/jitml-canonical-datasets:/datasets:ro \
    jitml jitml internal upload-dataset \
    --name "$1" --split "$2" --artifact "$3" --path "/datasets/$4"
}

stage_dataset "MNIST" train images mnist-train-images.gz
stage_dataset "MNIST" train labels mnist-train-labels.gz
stage_dataset "MNIST" test images mnist-test-images.gz
stage_dataset "MNIST" test labels mnist-test-labels.gz
stage_dataset "Fashion-MNIST" train images fashion-train-images.gz
stage_dataset "Fashion-MNIST" train labels fashion-train-labels.gz
stage_dataset "Fashion-MNIST" test images fashion-test-images.gz
stage_dataset "Fashion-MNIST" test labels fashion-test-labels.gz
stage_dataset "CIFAR-10" train archive cifar-10-binary.tar.gz
stage_dataset "CIFAR-100" train archive cifar-100-binary.tar.gz
stage_dataset "Tiny ImageNet" train archive tiny-imagenet-200.zip
stage_dataset "California Housing" train archive cal_housing.tgz
```

```bash
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Current Validation State

The 2026-08-02 live attempt against immutable image
`jitml:local@sha256:906c2e33b423ae2c586fed18af018786d604990da73236c6be458b30e1dbdd5d`
and cluster-publication file SHA-256
`fb1655ec0b4148f889cf682a25f36d6321a98899c7fcc0d13e3e961f06897e87`
failed closed after executing every integration test.
`tiny-imagenet-resnet50`, row 10, exceeded the former two-hour ProductScenario
operational envelope before it could publish completion; the prior nine roots
are partial-run diagnostics and are not closure evidence. That one missing row
caused the expected 60 Phase `261` aggregate-dependent and 10 Phase `262`
catalogue-dependent failures. One independent integration assertion still
inspected the pre-refactor Workload facade for Store calls now owned by
`BrowserCatalogue`. No other tests failed: all 20 Live-subtree cases passed.
The integration result was **100 Passed / 71 Failed / 0 NotRun (171 total)**.
The outer e2e wrapper was **0 Passed / 1 Failed / 2 NotRun**, with Playwright and
Haskell e2e correctly `NotRun` after integration refinement, and exited `1`.
The locally retained, gitignored transcript is
`.build/runtime/phase262-live-gate-20260801.log`, SHA-256
`b5f203eea58c077a370132571a7d4775e74701f7070a0f2acb6b97524f999553`;
it retains the invocation's combined stdout and stderr. The filename records
the 2026-08-01 invocation start label, while the terminal result was recorded
on 2026-08-02.

After each row's precondition succeeds, the ProductScenario runner uses one
uniform bounded four-hour command-and-evidence-resolution envelope. This changes
no `TrainingBudget`, `PlanId`, seed, dataset quantity, optimizer-update count,
ordering, niceness, or completion equality. Closure starts a new command-owned
scope and executes all 55 rows; it neither resumes row 10 nor reuses the nine
partial roots.

Pre-outbox historical source-mounted validation passed the focused shared-blob GC
regression (**1 / 1**), the complete `jitml-unit` stanza (**785 / 785**), and
`jitml-negative-controls` (**3 / 3**), `jitml docs check`, and `jitml
check-code`. Rule-M scan 3 inspected the mapped **20 / 20** `linux-cpu`
aggregation validation blocks and found **0** CUDA/Apple accelerator
invocations; `git diff --check` also passed. The GC regression proves both that
a blob referenced by an always-live archival manifest is not reaped and that a
blob shared only by two discarded manifests is named for deletion exactly once.
These are pre-build checks only; the prescribed aligned-image gates remain the
closure evidence.

The subsequent GC durability audit invalidated the first intent/ready design as
closure evidence: shared payload-object addresses allowed a paused executor to race a
new writer, recovered intents were not freshly proved against current roots,
ready acknowledgement could recreate the same event with a new timestamp, and
the old delimiter text form could not safely carry arbitrary keys. The active
remediation contract is the snapshot-scoped writer with non-shared per-attempt
reservation markers, one experiment-scoped full-reservation/per-event-generation
CAS fence with its separate monotonic writer/root-activity epoch,
attempt-independent commit, permanent leaked-entry/marker roots,
committed-only admission/GC eligibility, complete revalidation bracketed by
matching epoch observations, exact-epoch planning unaffected by sibling GC-only
revisions, bounded complete-view restart on epoch churn or newly persisted
fresh-plan intent, converged-plan-only kept/no-op accounting with exact
initial/fresh intent creation counted as work, atomic `Planned` → `Cancelling`
writer insertion, and durable
byte-identical immutable cancellation-artifact settlement without semantic-intent
deletion to complete `Cancelled` before re-arm. Stable intent/cancellation
objects may span generations, the latest exact fence phase is logically
authoritative, and delayed helpers only repeat idempotent PUTs. The contract also
requires `executeAuthorizedGcIntents` as the sole destructive execution API,
with raw-plan/raw-intent compatibility execution absent, and opaque executing
authorization without cancellation-artifact retirement,
post-`Reaped` semantic-intent cleanup, permanent reaped
state, permanent published tombstone, stored-substrate replay, exact token
echo/global ordering, and canonical protobuf-hex wire described above. Its
focused crash, race,
pagination, codec, recovery, and live broker tests still belong to the final
aligned-image validation; this paragraph records current scope, not closure
evidence or a completed removal.

### Remaining Work

- The owned browser/e2e portions of Exit Definition obligations `24`, `31`,
  `33`, and `34` remain unmet until the fresh full live gate and every standing
  gate below pass from the same final source/image state.
- Revalidate the four-hour operational envelope, BrowserCatalogue-owned
  Store-admission assertion, deterministic scoped namespace and exact
  experiment-scoped CAS-fence → per-attempt-marker →
  attempt-independent-commit writer order, every writer crash/retry interval,
  committed-only admission, protection from every leaked full reservation entry
  or marker even beside a matching commit, cross-snapshot parent-manifest
  overlap, complete
  payload-object graph, intrinsic ProductRow roots, fresh pointer/catalogue/
  reservation-marker/outbox revalidation, atomic writer registration plus
  a writer/root-activity epoch bracket around the complete root view, exact-epoch
  `Open`/`Cancelled` → `Planned`, bounded whole-view restart on epoch churn or
  epoch-stable discovery and persistence of an absent exact durable intent,
  converged-plan-only `kept`/no-op accounting with initial/fresh intent creation
  counted as work, `Planned` → `Cancelling`, durable immutable
  cancellation-record settlement without intent deletion,
  `Cancelling` → complete `Cancelled`, `Planned` → `Executing` only with no overlap,
  generation-incremented re-arm, helpable exact-`Executing` authorization through
  the sole destructive `executeAuthorizedGcIntents` API with no raw plan/intent
  execution compatibility export, fence-proven exact `Executing`/`Reaped`
  recovery for an already-absent target with every other absent-target intent
  cancelled,
  permanent `Reaped`, whole-intent cancellation, stale-executor CAS exclusion,
  descriptor reconstruction/snapshot-id re-derivation,
  Store-owned Workload namespace rejection, exact continuation-token
  echo/global ordering, one-snapshot/one-commit GC event keys, global
  deletion barrier, idempotent retry, exact outcomes, permanent published
  tombstone, stored-substrate replay, and strict protobuf-hex codec against the
  final image; build that aligned
  `jitml:local` image, publish the matching live `linux-cpu` cluster with the
  exact dataset objects, and pass the prescribed fresh full live `jitml-e2e`
  gate.
- Validate the experiment fence through atomic byte-plus-ETag reads and CAS on
  the real MinIO interpreter. Prove that a process-local lock or pre/post listing
  cannot substitute for the durable transition, a writer rejects overlapping
  `Executing`/`Reaped` before marker creation, marker deletion precedes entry
  unregister, a leaked or marker-conflicted entry remains a root, an
  already-registered exact reservation is not replaced or removed, writers
  settle `Cancelling` before marker creation or payload mutation, re-arm waits
  for complete `Cancelled` and a newly witnessed exact writer/root-activity
  epoch, each reservation register/unregister advances that epoch, GC-only
  sibling revisions do not invalidate a witness, delayed cancellation helpers
  perform only byte-identical PUTs, and authorization never retires the stable
  cancellation artifact or deletes the semantic intent. Prove the 4,096-attempt
  convergence bound fails closed if it cannot stabilize, fresh intent persistence
  restarts every component of the complete view before authorization, late
  ready publication or published-transient cleanup also counts as work and
  restarts the whole view, and only the converged plan determines `kept` and
  exit `3`.
- Validate the implemented zero-payload-object snapshot rule with focused
  admission and GC cases: exact derivation from `jitml-snapshot-v1`, the exact
  logical manifest, and the empty binding list; `committed.cbor` as the sole
  GC-owned key and `reaped-objects=1`; exact-commit
  admission/retention/GC eligibility before completion refinement; and a
  commitless legacy empty manifest remaining protected, ineligible, and
  decode/inspection-only.
- In that live gate, stage the matching permanent `Reaped` decision in the
  canonical `ExperimentGcFence` together with its exact durable ready record
  before invoking the CLI. Prove `jitml internal gc` publishes the exact
  protobuf-hex event on the record's stored-substrate Pulsar topic and, before
  acknowledging broker success, re-reads that exact ready record and matching
  permanent `Reaped` decision. It then persists the identical published
  tombstone, removes transient ready/intent state only from that already-`Reaped`
  terminal flow, and does not republish or recreate the timestamp on the
  steady-state retry; an absent ready record is accepted only when the exact
  published tombstone already exists.
- Run `jitml docs generate` after the `src/JitML/CLI/Spec.hs` GC description is
  final so the generated command Markdown, manpages, completions/help fixtures,
  and README command mirrors are updated only from `CommandSpec`; do not
  hand-edit those generated artifacts.
- Pass the documentation checker and full container-only code-quality gate
  plus the unit, negative-control, and model-convergence standing gates against
  that same final source/image state, then record the exact closure evidence in
  the canonical development-plan status surfaces.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/purescript_frontend.md`
- `../documents/engineering/unit_testing_policy.md`
- `../documents/engineering/run_contract.md`
- `../documents/engineering/product_completion_contract.md`
- `../documents/engineering/checkpoint_format.md`
- `../documents/engineering/determinism_contract.md`
- `../documents/engineering/cli_command_surface.md`
- `../documents/engineering/training_metrics_and_splits.md`
- `../documents/engineering/training_workloads.md`
- `../documents/engineering/haskell_code_guide.md`

**Product docs to create/update:**

- `README.md`
- `00-overview.md`
- `development_plan_standards.md`
- `phase-124-bit-determinism-contract-and-retention-reconciler.md`
- `phase-174-live-minio-checkpoint-round-trip-and-retention.md`
- `phase-276-negative-control-suite.md`
- `system-components.md`
- `legacy-tracking-for-deletion.md`
- `../README.md`

**Cross-references to add:**

- Add the Phase `262` backlink to `training_workloads.md`,
  `training_metrics_and_splits.md`, and `checkpoint_format.md`.
