# Phase 262: Contract-Driven Live Execution - Browser and Playwright

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Contract-Driven Live Execution - Browser and Playwright. Single-session phase migrated from legacy Sprint 28.5 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (2026-08-11). Phase 261 (Sprint 261.1) closed on 2026-08-01. Browser
and Playwright evidence is implemented against the authenticated completed-row
journal through the staged producer/catalogue/reporter refinement, and its
closure gate passed against the single-worker local topology owned by the
now-closed Phase 42 → Phase 53 → Phase 69 chain. The aligned `jitml:local`
image, the live `linux-cpu` gate, the unit, negative-control,
model-convergence, and daemon-lifecycle standing gates, the docs check, and the
container code-quality gate all passed from one source and image state on
2026-08-11; see [Current Validation State](#current-validation-state).

## Sprint 262.1: Contract-Driven Live Execution - Browser and Playwright [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/App.hs`,
`src/JitML/Checkpoint/Format.hs`,
`src/JitML/Checkpoint/Store.hs`,
`src/JitML/Checkpoint/Writer.hs`,
`src/JitML/Product/BrowserCatalogue.hs`,
`src/JitML/Product/Matrix.hs`,
`src/JitML/Product/PhaseStatus.hs`,
`src/JitML/Service/Workload.hs`,
`src/JitML/Service/Capabilities.hs`,
`src/JitML/Service/InferenceReplyScope.hs`,
`src/JitML/Service/MinIOSubprocess.hs`,
`src/JitML/Service/PulsarWebSocketSubprocess.hs`,
`src/JitML/Proto/Gc.hs`, `proto/jitml/gc.proto`,
`src/JitML/Inference/Command.hs`, `src/JitML/Routes.hs`,
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
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/checkpoint_format.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/cli_command_surface.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/haskell_code_guide.md`,
`../documents/engineering/pulsar_ml_workflow.md`,
`README.md`, `00-overview.md`, `development_plan_standards.md`,
`phase-71-receipt-bound-delivery-and-total-settlement.md`,
`phase-124-bit-determinism-contract-and-retention-reconciler.md`,
`phase-160-functional-core-live-workflow-interpreter.md`,
`phase-174-live-minio-checkpoint-round-trip-and-retention.md`,
`phase-277-negative-control-suite.md`,
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
- Sign every MinIO request over the caller's exact key bytes (`--path-as-is`),
  so a key spelled with `.` or `..` path segments is refused rather than
  silently written to the address S3 collapses it onto. S3 resolves those
  segments server-side, so such a key cannot round-trip verbatim; in a
  content-addressed store a silent collapse is object substitution. Dots inside
  a name (`a.b/..c/key.txt`) are ordinary characters and must survive
  unchanged. The live capability gate proves both halves: the dot-segment write
  is refused and leaves nothing under the collapsed address, and the
  legal dotted-name key round-trips and lists exactly.
- Reject generic weighted and unweighted `JitML.Service.Workload` mutations of
  noncanonical bucket/key references and Store-owned checkpoint `manifests/`,
  `pointers/`, `snapshots/`, and `gc/` prefixes before `HasMinIO`, while
  continuing to permit ordinary canonical data keys. Filesystem-normalizing
  dot, dot-dot, empty-segment, absolute, backslash, control, and bucket aliases
  must fail before the capability call.
- Answer a permanently unsatisfiable inference-family command on its reply
  topic instead of negatively acknowledging it. Every `RunInference`,
  `CompareCheckpoints`, `SelectAdversarialMove`, `ListCheckpoints`, and
  `LoadTranscript` command shares the one durable `jitml-engine` subscription,
  so a command that can never succeed and is only nacked returns to that
  subscription forever and starves every unrelated command behind it. A load
  failure is terminal exactly when its operands are immutable — the checkpoint
  is proved ABSENT, or the admitted runtime rejects the request's own input —
  and is then published as a call-id-keyed `InferenceFailure` frame that both
  settles the delivery and gives the requester a diagnosis instead of a reply
  timeout. Every other failure, including any runner-side execution failure,
  stays transient and still nacks, because a redelivery can legitimately
  succeed once the underlying condition clears.
- Hold the `CheckpointList` wire form to one field set at both ends. The Engine
  renders the authenticated catalogue's provenance — run, substrate, catalogue
  digest, and source-journal digest — because the browser renders artifact
  cards only from an authenticated catalogue, and the generated browser
  contract requires exactly those fields. The topology validator permits and
  requires the same set. A narrower validator does not make the frame stricter:
  it makes the Engine's own reply unpublishable, which the Engine can only
  report as a failed publication and therefore as a command that never
  succeeds. A standing unit case binds the validator's field list to the
  generated contract's.
- Make "publish a correlated request before its reply cursor exists"
  unrepresentable. A consumer whose socket is open is not yet a consumer the
  broker will deliver to: the reply subscription starts from the latest position,
  so its cursor is planted at the topic tail when the broker creates the
  subscription, and a reply published before that creation sits permanently
  behind the cursor and cannot be replayed. Readiness is therefore a proved fact,
  not an observed lifecycle event. An opaque `ReplyCursor` carries that proof:
  its constructor is hidden and it is minted only from an acknowledged Pulsar
  admin subscription CREATE, mirroring the admin DELETE the owned cursor already
  issues. The correlated publish takes that token and reads both the request
  topic and the reply-topic text out of it, so a request cannot be published
  before its cursor exists and cannot name a reply topic its subscription does
  not cover. `ConsumerSessionConnected` returns to being purely diagnostic and
  gates nothing.
- Give the demo API edge route a budget that outlasts the webapp's own reply
  budget. The webapp brokers request/reply work through the Engine, so an edge
  timeout shorter than that budget returns a gateway error for a request the
  webapp would have answered, and the browser never observes the typed result or
  the typed fail-closed reason. The route registry carries the value explicitly
  rather than inheriting the gateway default, and a standing unit case holds it
  above the webapp's reply-consumer startup plus reply deadline.
- Cancel a command against the inference batch window only when that window is
  the right clock for it. The window is a batching target: it bounds how long a
  batch may wait to accumulate, and with it the latency of the forward passes it
  coalesces. Admitting the authenticated 55-row catalogue takes seconds longer
  than that target by design, so measuring `ListCheckpoints` against it produces
  a command that can never fit its own deadline — cancelled, nacked
  `RetryRequested`, redelivered, cancelled again, without ever recording an
  outcome error. The subscription is `Failover`, so that one command then blocks
  every command behind it and the whole inference surface goes silent. Control
  commands therefore dispatch without the batching deadline; their work stays
  bounded by the retry policy and the drain deadline.
- Answer a `ListCheckpoints` command whose catalogue cannot be admitted instead
  of negatively acknowledging it, on the same reasoning
  `LoadTranscript` already uses. Before any catalogue is published the selector
  object is simply absent, and no catalogue appears because a browse request
  was redelivered; nacking parks an unanswerable command on the shared
  subscription and starves every inference command behind it. The reply is a
  call-id-keyed `InferenceFailure` carrying the admission diagnosis, so the
  panel fails closed with a reason rather than waiting out its deadline.
- Submit browser-panel inputs inside the input domain the compared or served
  trained runtime declares. A trained classification row declares a unit-image
  transform, so a panel bound to such a row submits values in `[0,1]`; the
  wider standardized-regression vector belongs only to a regression row. An
  out-of-domain default is unanswerable by construction, and the standing unit
  gate reads the panel source to keep the submitted default and the compared
  rows' declared domain in agreement.

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

Build the final `jitml:local` image, bring up a matching
single-worker `linux-cpu` publication, and stage the exact 12 canonical dataset
objects before the live gate. The topology prerequisite is one control-plane
node, one numerical worker, one clustered Engine pod, and the single-instance
platform services owned by Phases 42, 53, and 69; explicit multi-worker or
node-failover evidence is not part of this phase's closure. Dataset staging and
publication-derived edge-port rules are the same as
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
docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

The correlated-cursor cases are additionally runnable on their own against the
same live publication, so the reply-loss obligation does not require a second
full-matrix lane to observe:

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu \
  --test-options='-p "correlated reply"'
```

The `jitml-daemon-lifecycle` stanza is part of this phase's gate because it owns
the executable proof that generic weighted and unweighted
`JitML.Service.Workload` mutations reject noncanonical bucket/key references and
the Store-owned `manifests/`, `pointers/`, `snapshots/`, and `gc/` prefixes
before `HasMinIO`, while still permitting ordinary canonical data keys.

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

The 2026-08-05 live attempt under the four-hour envelope cleared the whole
integration stanza — **193 / 193** in 36,899s, including the complete 55-row
producer and every Phase `261` and Phase `262` aggregate- and
catalogue-dependent case — and then failed closed in Playwright: **14 passed /
9 failed / 54 did not run**, exit `1`. Every failure was an Engine-answered
panel (`mnist`, generic inference, `cifar` upload, checkpoint compare,
`connect4`, adversarial selectors, checkpoint browse, transcript replay); every
panel the webapp answers alone passed. The retained transcript is the
gitignored `.build/gate-logs/final262-e2e-run2.log`.

The 2026-08-07 live attempt against immutable image
`jitml:local@sha256:61d1cf72b6e845b8006f2a0cc2b100feb7c04765ab65c8f6822fc1aa49562460`
and cluster-publication file SHA-256
`fb1655ec0b4148f889cf682a25f36d6321a98899c7fcc0d13e3e961f06897e87` — built from
a purged cluster, a fresh nine-component publication, and the exact 12
SHA-verified dataset objects — passed integration **192 / 194** in 36,572s and
failed closed before Playwright. Every standing gate on that same image passed:
`jitml-unit`, `jitml-negative-controls`, `jitml-model-convergence`,
`jitml-daemon-lifecycle`, `jitml docs check`, and `jitml check-code`. The two
integration failures were both consequences of the settlement work above rather
than of the surfaces this phase owns:

- `Tune replay reports corrupt transcripts as typed decode failures` asserted the
  pre-existing `SEUnauthorized` for an absent object. Absence is now the
  distinct `SENotFound` that terminal settlement is decided on, so the fixture
  asserts the typed value the store actually reports.
- `live unsatisfiable inference request never starves the shared Engine
  subscription` proved its own invariant against a second starvation source. The
  Engine answered the absent-checkpoint request terminally, but the unrelated
  `ListCheckpoints` that follows it did not return within 15s. The Engine logs
  show why: with no catalogue published yet, `ListCheckpoints` failed with
  `CatalogueSelectorReadFailed … (SENotFound "minioReadBytes: object missing")`,
  classified that as transient, and nacked it back onto the shared
  subscription. Auditing that path also found the `CheckpointList` frame's field
  set had drifted: the Engine renders the catalogue's `run-id`, `substrate`,
  `catalogue-sha256`, and `source-journal-sha256`, and the generated browser
  contract requires them, but the topology validator still carried the narrower
  pre-catalogue set — so a successful browse reply was unpublishable and would
  have starved the same subscription once a catalogue existed. Both are closed
  above, and a standing unit case now binds the validator's field list to the
  generated contract's.

The 2026-08-07 re-run of the live gate against the same image and publication
passed integration **194 / 194** in 36,761s and every standing gate, and ran
Playwright for the first time this cycle: **20 passed / 3 failed / 54 did not
run**. The settlement work above is confirmed live — no redelivery loop occurred
across the whole run, and six previously failing panels now pass. The three
remaining failures are `checkpoint browse`, `transcript replay`, and the
`e2e.product.*` matrix that depends on the browse artifacts.

Their single cause was isolated against the warm cluster rather than inferred.
`POST /api/checkpoints` returned `504 upstream request timeout` at exactly
15.000s at the edge and, bypassing the edge, exhausted the webapp's own 30s
reply deadline with `no matching reply received from the Engine`. The Engine
logged `dispatched inference` for the command and no error; the reply topic held
its published `CheckpointList` frames; and the request topic's `jitml-engine`
subscription sat at backlog 11 with 0 unacked behind a head-of-line
`ListCheckpoints`. Raising `inferenceMaxLatencyMillis` from `5000` to `120000`
on the live daemon and restarting it made the same browse succeed **5 / 5 in
6.5–9.9s**; the value was then reverted. A catalogue browse therefore
legitimately exceeds the batching budget it was being measured against, which is
the defect closed above. An earlier probe appeared to refute this and was a
false negative: it ran while the daemon was still replaying the stuck backlog,
so the probe queued behind the very messages under test.

The 2026-08-09 run against immutable image
`jitml:local@sha256:fa76aa99fea6e870b80a1c9c93c5787425c81b8288a587f06781113277d4e43b`
passed integration **194 / 194** in 36,305s and every standing gate, and
Playwright returned **75 passed / 1 failed / 1 flaky**. The batch-deadline fix
is confirmed: the whole 55-row `e2e.product.*` matrix executes, where 54 of its
cases previously never ran. The edge-budget fix is confirmed in the cluster —
the deployed `demo-api` HTTPRoute carries
`{"request":"80s","backendRequest":"80s"}` — and the browse failure moved from
exactly `15.0s` to exactly `30.2s`, which is the webapp's own reply deadline
rather than the gateway's.

The residual failure is a request/reply readiness race, not a latency problem.
Three identical browse requests against the idle warm cluster returned
`4.98s`, `4.77s`, and then a full `30s` timeout, so roughly one reply in three
is lost outright. `runInferenceCommandWithReply` treats
`ConsumerSessionConnected` — emitted when the bridge's WebSocket opens — as
readiness, and publishes the command immediately afterwards. The reply consumer
runs in `pullMode` with `subscriptionInitialPosition=Latest`, so the broker
does not establish its cursor until the parent sends its first `permit`. A
reply published inside that window has no cursor to land on and cannot be
replayed, and the caller then waits out its full deadline. The Engine is not
implicated: it logs `dispatched inference` with no error, and its published
`CheckpointList` frames are present on `inference.result.linux-cpu`.

Closing this requires readiness to be a proved fact rather than an observed
lifecycle event, which is the `ReplyCursor` obligation in the deliverables
above. A permitted-session event was considered and rejected: the bridge calls
`permitOne()` synchronously in the same socket-open handler that emits
`connected`, so such an event would arrive microseconds later, would still carry
no evidence, and would swap one lucky-timing signal for another.

This phase's image build also raised the `exe:jitml` GHC heap cap in
`docker/Dockerfile` from `-M2G` to `-M6G`. Phase `160` recorded the same cap as
deliberately preserved when it isolated the reply supervisor behind `NOINLINE`
boundaries; that remains the right structural fix and is unchanged. The cap had
since become the binding constraint on the generated `Proto.Jitml.Rl` module
under `-O2 -fexpose-all-unfoldings`, so the same source built on one run and
failed with a GHC `heap overflow` panic on the next. Serialisation (`jobs: 1`)
is what keeps the layer within host memory; the cap is a runaway guard, and it
now leaves the headroom that guard was meant to leave.

The diagnosis is recorded here because it defines the phase's remaining scope
rather than closing it. The `checkpoint-compare-lab` panel carried a
`[0.25, -0.5, 1.0, 2.0]` default input left over from its retired
generic-tensor target while now comparing two MNIST rows, whose trained
runtime declares a unit-image transform admitting only `[0,1]`. The resulting
`RunInference` command could never be served. The Engine classified that
refusal as transient and negatively acknowledged it, so Pulsar redelivered the
identical command onto the one durable `jitml-engine` subscription
indefinitely — **3,808** recorded redeliveries across the following 13 hours —
and every other inference command starved behind it. A live probe against the
still-running cluster reproduced it exactly: `jitml inference run
--experiment-hash product-row-mnist-deep-mlp` returned `no matching reply
received from the Engine` for a checkpoint the same run had admitted, and
`pulsar-admin topics peek-messages` recovered the poisoned `kind:
RunInference` command verbatim. Both halves are therefore in scope: the panel
submits inside the declared domain, and an unsatisfiable command settles by
being answered rather than by starving its subscription.

On 2026-08-09 the remaining correlated-reply source change was implemented but
is not yet closure evidence. `runInferenceCommandWithReply` now obtains an
opaque `ReplyCursor` only after an acknowledged, bounded Pulsar admin
subscription `PUT` at `MessageId.latest`; HTTP `409` is admitted as an existing
cursor. The token owns both command and reply topic identity, is the only input
to correlated publication, supplies a borrowed consumer view, and is explicitly
released after the consumer is cancelled and joined on every ordinary or
exceptional scope exit. The readiness `MVar` and
`ConsumerSessionConnected` publication gate are gone. Offline transport and
scope cases cover the exact admin rendering, success/`409`/failure
classification, token-bound publication, release before consumer readiness, a
discarded pre-cursor reply followed by a delivered post-cursor reply, strict
CREATE-before-publish-before-delivery ordering, and failed creation with no
publisher invocation;
the live correlated-reply case publishes a negative-control reply before cursor
creation, requires only the post-cursor reply, records CREATE-before-publish-
before-delivery ordering, and verifies subscription removal. Repeated
integration and Playwright catalogue requests require typed answers rather than
accepting the no-reply sentinel. The aligned image build and every prescribed
gate below are still pending, so the phase remains Active.

The 2026-08-09 focused offline cursor gate passed against
`jitml:local@sha256:da71b40c6354b4942c4fe8dacb8fcff344d43fc0aaaffe1ed7ed60f02756bc1f`.
The filtered `PulsarTransport` group passed **37 / 37** in **4.35s**, including
the no-cursor negative control, pre-created-cursor delivery, strict
CREATE/publish/delivery ordering, `409` admission, token-bound publication,
explicit early release, and creation-failure/no-publish cases. Its containing
`jitml-unit` orchestrator invocation passed **1 / 1** in **1,522.51s**, including
the one-time optimized test build. The same image build completed its baked
container-only `jitml check-code` gate with `check-code: ok`. This is focused
pre-live evidence only; the phase remains Active pending the live and standing
gates below.

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

### Closure Evidence

The 2026-08-10 attempt against image
`jitml:local@sha256:821196e55011c0d61c68e9737b6c71a102c781560083c73449e4c660b0ad1301`
executed the complete 55-row producer and failed closed at **3 of 196**
integration cases in 37,225.50s, leaving Playwright correctly `NotRun`. All
three were narrow defects rather than missing surface, and all three are closed:

- `latestMessageIdJson` rendered the admin subscription CREATE body as
  `{"ledgerId":-1,"entryId":-1,"partitionIndex":-1}`. That is Pulsar's
  `MessageId.earliest`, not `MessageId.latest`, so every minted `ReplyCursor`
  was planted at the head of its reply topic and replayed each message already
  published there. Probing the live broker on a topic holding three messages
  returned `msgBacklog=3` for that body and `msgBacklog=0` for
  `MessageId.latest`. This supersedes the readiness-race diagnosis recorded
  above as the cause of the lost browse replies: an `earliest` cursor must
  replay a whole reply topic before reaching the correlated reply, so reply loss
  grows with topic depth, which is what the 2026-08-09 browse timings showed.
  The `ReplyCursor` design was correct; its message-id encoding was not.
- The offline transport case asserted that same `-1,-1,-1` body, so it passed
  **37 / 37** while the live case failed. It now pins the `MessageId.latest`
  encoding and additionally rejects the `MessageId.earliest` sentinel, so the
  offline case can no longer agree with a broken cursor.
- `handleReplyDelivery` surfaced only `ifailError` from a terminal
  `InferenceFailure` and discarded the frame's `ifailExperimentHash`, so the
  diagnosis never named the operand it refused. The surfaced reason now carries
  that exact hash.
- `writeTextFileIfChanged` did not create parent directories, so materializing
  the single-worker `chart/local/jitml-service/values.yaml` failed in a
  temporary root. It now creates them, matching `JitML.Docs.Generate`.

The 2026-08-11 closure run passed from one source and image state. Image
`jitml:local@sha256:e36d6ca11f4cc75c231ac8ba2e7f238b1e1ce68623b550b55c94be075ad599e7`
completed its baked container-only gate with `check-code: ok`. The cluster was
purged and rebuilt to a fresh nine-component single-worker `linux-cpu`
publication — one control-plane node, one numerical worker, one clustered Engine
pod, and single-instance platform services — with cluster-publication file
SHA-256 `6e57383cbcb8bd89b1ec08a6bd876651075e74707965f2fe31f0a1e3b28f1806`, edge
port `9090` read from that publication, and the exact 12 SHA-verified canonical
dataset objects staged before the gate.

`jitml test jitml-e2e --live --linux-cpu` exited `0` in 39,301.38s:
**3 passed / 0 failed / 0 NotRun**. `jitml-integration` passed **196 / 196** in
39,185.49s, including the complete fresh 55-row producer and every Phase `261`
aggregate-dependent and Phase `262` catalogue-dependent case. Playwright passed
**77 / 77** in 37.8s with zero failed, zero flaky, and zero did-not-run,
covering the whole `e2e.product.*` matrix across all 55 rows, the
checkpoint-browse and transcript-replay panels, and the `CheckpointList`
fail-closed contract fixtures. The Haskell `jitml-e2e` suite passed **30 / 30**.
The retained transcript is the gitignored
`.build/gate-logs/phase262-closure-gate.log`, SHA-256
`a2bbabc1cb6558ccf7dde394a15a751b1cee17533abbe96af8df8c287e509be9`.

Every standing gate passed against that same image and publication:
`jitml-unit` **828 / 828**, `jitml-negative-controls` **3 / 3**,
`jitml-model-convergence` **111 / 111**, `jitml-daemon-lifecycle` **54 / 54**,
`jitml docs check` ok, and `jitml check-code` ok. The Rule-M enforcement scans
report 0 dual-accelerator validation gates and 0 accelerator invocations across
the linux-cpu-only validation blocks.

One reproducibility note on the Validation sequence above: `docker compose build
jitml` produces only the `jitml:local` tag, while the rollout's expected
reconcile stamp inspects both `jitml:local` and `jitml-demo:local`. On a host
that has just rebuilt the image, `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1` therefore
fails until `jitml-demo:local` exists — the same retag the rollout's own
`mirrorBuildSteps` performs.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/purescript_frontend.md`
- `../documents/engineering/daemon_architecture.md`
- `../documents/engineering/pulsar_ml_workflow.md`
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
- `phase-277-negative-control-suite.md`
- `system-components.md`
- `legacy-tracking-for-deletion.md`
- `../README.md`

**Cross-references to add:**

- Add the Phase `262` backlink to `training_workloads.md`,
  `training_metrics_and_splits.md`, and `checkpoint_format.md`.
