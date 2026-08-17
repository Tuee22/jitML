# Checkpoint Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md, determinism_contract.md, training_workloads.md, durable_state_dsl.md, training_metrics_and_splits.md, numerical_core.md, product_completion_contract.md, run_contract.md
**Generated sections**: none

> **Purpose**: Project-specific checkpoint format for jitML — split-blob
> layout, `.jmw1` dense weight blob wire format, typed CBOR manifest, write-
> once + If-Match CAS protocol, retention reconciler, inference-only read
> path, inference request/result protobuf envelopes, and the architecture-aware
> checkpoint target for every model family, including the trained-artifact
> witness required before inference.

**Durable-state retention:** checkpoint GC retention is a typed
`RetentionPolicy` sourced from the durable-state registry's `checkpoints` store
(`JitML.Project.Config.lookupStoreRetention`), replacing the former hardcoded
`LastN 5` literal. See [durable_state_dsl.md](durable_state_dsl.md).

**Snapshot concurrency:** the snapshot-scoped writer plus experiment-scoped
writer/GC CAS protocol below is the binding contract. Phase status,
implementation sequencing, and
validation evidence remain in the
[development plan](../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md).

**Typed local object-key validation:** local filesystem
object-key validation returns data, not bottoms. `objectPathForKey` /
`safeRelativePath` reject empty, absolute, and parent-traversing keys as
`Left Text` before path construction. Read/list helpers retain that validation
result; write transactions convert it to `CheckpointWriteInvalid`, while
immutable-object and pointer collisions use distinct typed conflict
constructors. User-facing commands such as local `jitml internal gc
--experiment-hash ...` report a typed error instead of terminating.

**Structural completion and persisted admission are distinct.** Each payload
variant inside the single envelope contains a forgeable
`RawCheckpointManifest` and, when present, a versioned
`RawCompletedTraining`. Decoding re-refines those raw fields before a domain
manifest exists. `ValidatedCheckpointCompletion` is deliberately named and
documented as a structural result only: it makes no persistence claim. Store
alone constructs `AdmittedCheckpoint` / `AdmittedCompletedCheckpoint` after an
exact stable-address read and commit/descriptor/payload-object binding. Pipeline consumes that
opaque Store result and cannot promote a caller-built or merely decoded
manifest.

**Real trained weights only.** Checkpoint payloads carry weights produced by the
declared training workflow with correct per-tensor shapes; synthetic,
zero-padded, byte-identical-across-models, randomly initialized, or untrained
weight payloads are prohibited. Seeded and smoke checkpoints are not enough:
inference requires a trained-artifact witness refined from completed run
evidence. See
[Typed Run Contract](run_contract.md) and
[Training Metrics and Data Splits](training_metrics_and_splits.md).

## Current Status

**Implemented today.** The checkpoint wire is
**one self-describing envelope**: a payload-variant version, the raw 32-byte
SHA-256 of the exact canonical body bytes, and those body bytes. The body is the
typed `RawCheckpointBody` payload sum with two variants — **weight-only** (the
bare canonical manifest, for RL, AlphaZero, tuning, and non-supervised generic
rows) and **supervised-graph** (the manifest plus exact runtime task/transforms
and trained-graph metadata, for supervised rows). A single `encodeManifestCbor` arm, a single
`decodeAddressedManifestCbor` that dispatches on the payload sum (no version
cascade or fall-through), and one `canonicalManifest` serve every row. The
byte-frozen V1 golden fixture, the dead V3 `LayerGraph` encoder, the retained
pre-Sprint-`10.12` legacy decoder, and the parallel `canonicalManifestV2` were
all retired; checkpoints are regenerated deterministically from current source,
so no persisted bytes are reinterpreted. Store admission is likewise **one
path**: a decode with no per-version allow-list, then a
single classify-on-payload-variant — a supervised-graph checkpoint is admissible
only with no companion pointer, a weight-only checkpoint routes through the
authoritative non-supervised ProductRow companion rules. The dormant legacy-V3
graph reconstruction helpers were deleted; the current supervised reader
reconstructs the trained graph from the one envelope as described below.

**The supervised-graph payload is the trained `LayerGraph`.** Its served representation is the trained
typed `LayerGraph` (persisted as `architectureLayerGraph` metadata). Phase `239`
deleted the embedded V2 `SupervisedRuntime` served layer-operation program and
its per-substrate `RuntimeBackendExecutor` structural ABI. The runtime payload
that rides alongside the graph is slimmed to the task and the exact input/output
transforms; serving reconstructs the graph, injects the one physical
graph-ordered `supervised.weights` blob, runs `LayerGraph.runLayerGraph`, and
applies the transforms outside the graph.

## The Self-Describing Checkpoint Envelope

Every checkpoint serializes through one outer envelope: a payload-variant
version, the raw 32-byte SHA-256 of the exact canonical body bytes, and those
body bytes. The body is the typed `RawCheckpointBody` payload sum, and decode
dispatches on that sum — there is no version cascade and no fall-through.

The **weight-only** payload is the bare canonical manifest, carried at the
weight-only variant tag. It serves the RL, AlphaZero, tuning, and generic rows,
has no embedded supervised runtime, and is categorically inference-ineligible on
the supervised path. Generic weight-only writing rejects an authoritative
supervised ProductRow, a supervised completion budget, or a reserved supervised
tensor name. The Product-only weight-only writer narrows that surface further:
completed publication accepts only a canonical non-supervised ProductRow and
binds already-persisted companion evidence into the immutable manifest before
advancing `latest`. Store may refine such an exact weight-only graph into
`AdmittedCompletedCheckpoint`; non-product and every supervised weight-only
manifest remain inspection/resume-only at the completed Product boundary.

The **supervised-graph** payload (the eleven supervised rows) carries, in one
canonical body:

1. the raw manifest plus the refined supervised runtime DTO; the outer envelope
   stores the raw 32-byte SHA-256 of those exact body bytes and those same body
   bytes; and
2. the object address is SHA-256 of the exact final outer-envelope bytes.

`AddressedCheckpointManifest` retains the exact fetched outer bytes and, for the
supervised-graph payload, exact body bytes plus both identities behind a hidden
constructor. Decoding checks canonical outer bytes, the embedded raw body digest,
canonical body bytes, semantic refinement, and cross-field bindings. A structural
decode is permanent: once the payload sum selects a variant, a semantic failure
never falls through to another decoder.

Phase `239` replaced the embedded served layer-operation program with the
trained `LayerGraph` metadata; the supervised-graph runtime payload now carries
only the task, the exact input/output transforms, and that graph metadata.

The supervised-graph body carries the trained model returned by training: the
task, the exact input/output transforms, the trained typed `LayerGraph` metadata
(`architectureLayerGraph`), authoritative canonical supervised-row identity, and
one member of the closed runtime-origin sum:

- `RawProductRowProjectionOrigin` binds the payload row and `PlanId` to exactly
  one supported-substrate projection of that authoritative ProductRow. Its
  manifest experiment must be the ProductRow experiment hash.
- `RawGenericSupervisedExecutionOrigin(rowId, canonicalPlanTransport)` carries
  the authoritative canonical problem-row identity together with the complete
  canonical versioned `SupervisedPlan` transport. Refinement requires the
  origin row, payload row, and canonical problem/ProductRow identity to agree,
  then reparses and re-refines that transport, requires byte-for-byte equality
  with its canonical rendering, requires its derived `PlanId` to equal the
  payload identity, requires its selected substrate to equal the execution
  request, and requires the manifest experiment to equal the plan experiment.
  A generic plan whose experiment is any authoritative ProductRow experiment
  hash is rejected.

There is no unspecified/default origin and no origin coercion. The addressed
supervised-graph body's composite origin—canonical row identity plus either the
authoritative projection or exact generic execution transport—binds the canonical row
semantics; `PlanId` alone never does. The canonical row owns the runtime family,
task, production dimensions, topology, transforms, decoder, convergence
criterion, and canonical dataset-read digest. The origin owns which exact plan,
budget, seed, substrate, and experiment may be bound to those semantics.
The supervised descriptor's finite-positive learning rate is part of semantic
`PlanId`: `3e-3` for `fashion-mnist-resnet`, `1.1e-3` for
`cifar10-resnet20`, `1.5e-3` for `cifar10-vit`, and `1e-3` for the other eight
supervised rows. The manifest architecture (including the trained
`architectureLayerGraph`), preprocessing, output decoder, physical tensor, and
weight layout are derived from that same refined payload. For classification,
labels are deterministic `class-0` through the row's semantic class width.
California Housing declares regression output units `median-house-value` and
persists the fitted feature transform plus target inverse-transform.

Every supervised-graph checkpoint contains exactly one physical tensor,
`supervised.weights`, whose bytes are one canonical JMW1 vector — the
graph-ordered parameter vector of the trained `LayerGraph`. Its length is
anchored to the graph's parameter count (`layerGraphMetadataParameterCount`), and
the `FlatWeightLayout` is one graph-ordered spec of that length. There is no
per-layer `W1`/`b1`/`W2`/`b2` virtual-slice decomposition: the graph metadata is
the parameter layout, so new supervised writes emit neither name-derived generic
manifests nor per-node physical weight objects.

The origin field is mandatory in the supervised-graph body and participates in
the exact canonical body, outer envelope, and object address. Decode never
guesses a missing origin or reinterprets pre-origin or retired multi-version
bytes. Checkpoints from before this closed-origin contract must be republished
from current source rather than retained as eligible artifacts.

Both origins also close dataset provenance against the canonical pinned read
contract. `canonicalDatasetReadShaForProblem` derives the deterministic digest
of the exact pinned training and evaluation artifacts for the canonical row;
the runtime payload, manifest `datasetShaAtRead`, and `CompletedTraining` must
all equal that digest. Synchronously substituting the same forged digest into
all three fields is therefore rejected for both Product and generic
supervised-graph payloads.

## Inference Eligibility

A checkpoint manifest can be loaded for inspection at any step, but only a
Store-minted `AdmittedCompletedCheckpoint` may flow to `jitml eval`, `jitml
inference run`, demo inference routes, RL evaluation/rollout, or AlphaZero game
endpoints. Store establishes the exact persisted snapshot before final
completion refinement: it validates the required immutable commit and its
descriptor, reconstructs and re-derives snapshot identity, and binds every
scoped payload object before `requireAdmittedCompletedCheckpoint` may construct
the completed admitted value. A pure structural completion precheck may reject
an impossible manifest before payload-object I/O, but it is not persisted admission.
Final completion refinement requires all of the following:

- the raw completion payload refines into opaque `CompletedTraining`, including
  its exact unit-indexed budget and originating `PlanId`;
- the manifest carries that same `PlanId`, and a supervised-graph payload
  identifies an authoritative canonical supervised row plus a valid closed
  origin: either one exact ProductRow substrate projection or the canonically
  reparsed generic `SupervisedPlan` transport;
- the manifest mirrors the witness's `initialWeightHash`, `finalWeightHash`,
  positive `updateCount`, and `datasetShaAtRead`, and those fields match the
  witness exactly;
- the completed observed units equal the declared fixed-budget target exactly,
  and the manifest step equals that observed count exactly;
- every `CompletedTraining` convergence observation has one unique, exactly
  equal manifest metric row, with no duplicate manifest metric names;
- a supervised manifest contains the exact refined supervised runtime payload,
  trained graph, one physical `supervised.weights` tensor, and the graph-derived
  `FlatWeightLayout`; every supervised weight-only payload remains
  inspection-only;
- a completed weight-only payload resolves to one canonical non-supervised ProductRow,
  contains no supervised runtime payload, and binds each required RL
  trajectory, AlphaZero transcript, or tuning-v2 transcript through an
  exact-SHA artifact pointer whose fetched bytes Store verifies; and
- the runtime family, task, production dimensions, topology, transforms,
  decoder, ProductRow, manifest experiment, completion fields, and physical
  tensor identity agree exactly; and
- `CompletedTraining` TensorBoard metadata binds its run id to the manifest
  experiment, its log prefix to `jitml-tensorboard/<experiment>`, and its
  ordered scalar tags exactly to the completed convergence metric names.

This boundary is not a best-effort convention. CBOR decode retains exact
outer/body identities and revalidates completion, finite measurements, runtime
metadata, and mirrored fields, but generic deserialization never constructs a
persisted-admission proof. `admitLatestCheckpoint` reads the exact pointer body
`P1`, fetches and verifies the addressed manifest envelope and embedded body,
reads the exact pointer body `P2`, and continues only when `P1 == P2`. Blob I/O
starts after that stability interval. Store then requires the exact commit,
validates its original/scoped/payload-SHA descriptor, reconstructs the logical
manifest, and re-derives the snapshot id before it verifies every declared
payload-object key, exact fetched bytes, byte length and content SHA, canonical
JMW1 encoding, flat element count, virtual-slice reconstruction, plan identity,
and final-weight identity. `admitCheckpointAt` performs the same immutable-graph
binding for a known manifest address without pointer reads.

The inference loaders accept only the resulting opaque admitted-completed
value before selected-engine execution. The selected CPU, CUDA, or Metal engine
also requires its substrate to equal the substrate of the origin-bound plan.
Raw manifest listing and manifest reads remain available for inspection,
resume, and GC.

Generic supervised completion is an explicit attempt, not a relabelling as a
ProductRow projection. A structurally exact finite run that misses the canonical
row's unchanged convergence bar returns a typed successful-training miss: no
eligible supervised-graph checkpoint is written and no completed-checkpoint
event is emitted. When the same exact generic plan passes that bar, its
generic-origin supervised-graph payload may become inference eligible after the
ordinary checks above, but its generic origin and non-product experiment
identity remain intact and cannot satisfy ProductRow report admission. See
[Product Completion Contract](product_completion_contract.md#type-state-dsl-contract).

There is no decoder-only legacy checkpoint fallback. Every current checkpoint
must decode canonically through the single outer envelope and typed body sum.
At completed admission, the weight-only case is restricted to a canonical
non-supervised ProductRow with its exact persisted completion, JMW1 bytes, and
companion artifact bytes.

The browser checkpoint-list selector uses the same Store admission boundary:
it admits each known manifest address and requires an admitted completion before
emitting an eligible `CheckpointSummary`. Incomplete or physically invalid
manifests remain inspectable by lower-level tooling but are omitted from model
selection. When no eligible rows remain, the daemon emits
`selector-state: fail-closed:no-inference-eligible-artifact` in the
`CheckpointList` frame and the browser renders that state instead of
substituting a seeded or synthetic artifact.

## No-Caveat Checkpoint Target

The supervised-graph payload owns the runtime families of the eleven
authoritative canonical supervised rows: Dense, DeepDense, Conv2D/LeNet,
residual, wide-residual, ResNet-50, VisionTransformer, and California
regression. Both authoritative ProductRow publication and exact generic
supervised commands use that payload through their distinct closed origins. The
weight-only payload owns RL policies, AlphaZero policy/value nets, tuning trial
checkpoints, and applicable non-supervised generic artifacts; the Product
writer persists companion evidence first and binds its exact content-addressed
pointer into the completed manifest. The two variants cannot be mislabeled.
Across those families,
the broader manifest still carries architecture, preprocessing, decoding,
replay/transcript, substrate-artifact, completion, convergence, and TensorBoard
metadata so user-facing readers reject missing, partial, smoke, or incompatible
artifacts instead of substituting an inline demo model.

## Storage Layout

The `jitml-checkpoints` MinIO bucket uses a fixed prefix schema. The current
local key renderers live in `src/JitML/Checkpoint/Format.hs` so paths are typed
values rather than stringly-typed call sites:

```
jitml-checkpoints/
  <experiment-hash>/                      -- sha256(resolved-dhall || substrate-fingerprint)
    snapshots/<snapshot-id>/
      reservations/<attempt-id>.cbor      -- immutable marker owned by one write attempt
      committed.cbor                      -- immutable admission/GC eligibility marker
      objects/<sha256(original-full-key)> -- snapshot-owned payload-object bytes
    manifests/<sha256>.cbor               -- write-once, content-addressed, CBOR manifest objects
    gc/
      coordination-fence.txt              -- mutable experiment-scoped writer/GC CAS record
      intents/<event-id>.cbor             -- immutable deletion set; cleanup only after Reaped
      cancelled/<event-id>.cbor           -- stable immutable whole-intent cancellation artifact
      ready/<event-id>.cbor               -- byte-stable Pulsar publication outbox
      published/<event-id>.cbor           -- permanent exact-event tombstone
    pointers/
      latest                              -- mutable, ETag-CAS; body = 64-byte lowercase SHA-256 text
      best/<metric>                       -- mutable, ETag-CAS; body = 64-byte lowercase SHA-256 text
      trial/<trial-hash>/latest           -- per-HPO-trial latest pointer
      trial/<trial-hash>/best/<metric>    -- per-HPO-trial best pointer
      browser-catalogues/<catalogue-sha>  -- immutable archival manifest root
```

Store also maintains one canonical experiment-scoped writer/GC coordination
record outside every snapshot deletion set. It is a mutable CAS object, not an
immutable snapshot payload or a GC event key. Experiment scope is essential: a
child snapshot reservation can protect another snapshot's reap target through
its `parentManifestSha`, so independent per-snapshot locks would miss a
cross-snapshot overlap.

`experiment-hash = sha256(resolved-dhall || substrate-fingerprint)`.
For new writes,
`snapshot-id = sha256(canonical-CBOR("jitml-snapshot-v1", exact logical manifest,
sorted(original-key,payload-sha)))`. Each reservation and commit descriptor
contains the sorted canonical-original → exact-scoped → payload-SHA table.
For every row, the original key must be canonical and outside `snapshots/`; the
scoped key must equal
`jitml-checkpoints/<experiment>/snapshots/<snapshot-id>/objects/<sha256(original-full-key)>`;
and persisted admission requires the payload SHA to equal the exact stored
bytes. Admission and GC reverse that mapping to restore every original key in the persisted manifest, reconstruct
the exact logical manifest, and re-derive `snapshot-id` from the logical manifest
and sorted original-key/payload-SHA pairs. A shared path prefix alone is not a
snapshot-identity proof. Legacy unscoped manifests remain readable, but every
new write is scoped and only exact committed snapshots are eligible for
admission, retention, or GC.

Scoping does not relax the logical address contract. The stored address must be
the exact snapshot derivation of the canonical original address, not merely any
key below the same snapshot prefix. In particular, the supervised-graph body retains
`blobKey(experiment, final-jmw1-sha)` as the logical `supervised.weights`
address, and Product weight-only companion evidence retains its family-specific
content address; admission rejects a coherently substituted original/scoped
pair that does not preserve those semantics.

For a zero-payload-object logical manifest, the sorted binding list is exactly
empty, so Store derives
`snapshot-id = sha256(canonical-CBOR("jitml-snapshot-v1",
exact logical manifest, []))` without relying on a payload-object-key prefix. The
exact derived `snapshots/<snapshot-id>/committed.cbor` is the sole GC-owned key.
When that commit exactly binds the manifest and empty ownership map, the
manifest is admissible as an exact persisted snapshot (with zero loaded
weights) and eligible for retention/GC; this does not refine it into a
completed or inference-eligible weighted model. A legacy empty manifest
without the exact commit remains decode/inspection-only, protected, and
ineligible; neither admission nor GC infers eligibility from emptiness alone.

For every payload variant, `manifest-sha` is SHA-256 of the exact canonical
outer-envelope bytes; the envelope independently carries SHA-256 of its exact
canonical body bytes. Neither identity is defined as decode-and-re-encode
equivalence.

`src/JitML/Checkpoint/Format.hs` owns the envelope/manifest codec and logical
object-key semantics alongside `deriveExperimentHash`, `blobKey`, `manifestKey`,
`latestPointerKey`, `bestPointerKey`, `trialPointerKey`, deterministic
`encodeManifestCbor` / `decodeManifestCbor` / `manifestContentSha`, typed
`AdvancePredicate`, pure `applyPointerWrite` CAS decisions,
and the explicitly structural `validateCheckpointCompletion` refinement.
`src/JitML/Checkpoint/Store.hs` owns deterministic snapshot preparation,
canonical descriptor validation and snapshot-id re-derivation, the
experiment-scoped writer/GC CAS state machine, per-attempt marker allocation,
scoped object rendering, commit records, the local
filesystem-backed interpreter, latest-pointer CAS, retention planning, durable
GC storage state, separate candidate/completed checkpoint transactions, and the
exact persisted-admission loaders. `src/JitML/App.hs` owns live GC recovery,
fresh revalidation, deletion orchestration, promotion, publication, and summary
rendering; `src/JitML/Service/MinIOSubprocess.hs` owns complete S3 listing and
idempotent DELETE; `src/JitML/Proto/Gc.hs` and `proto/jitml/gc.proto` own the
event codec. The Product weight-only writer
resolves
each supplied companion pointer from this same object store before writing the
manifest, and known-address re-admission checks that the returned stored
manifest key/SHA and admitted SHA are identical. A `StoredCheckpoint` exposes the
exact outer SHA and `storedManifestBodySha :: Maybe Text`: supervised-graph
writes return the embedded-body identity and weight-only writes return
`Nothing`. This write result is useful identity evidence but is not persisted
admission. Only
`AdmittedCheckpoint` / `AdmittedCompletedCheckpoint` carry that claim. Store-level
`checkpointObjectRef` adapts the bucket-prefixed key renderers to live
`HasMinIO` calls by carrying bucket `jitml-checkpoints` separately and using
keys relative to that bucket.
The local interpreter must treat object-key-to-path conversion as validation:
empty, absolute, or parent-traversing keys are typed failures, not exceptions.
That boundary is `objectPathForKey :: FilePath -> Text -> Either Text FilePath`;
object and pointer reads plus manifest listing propagate its `Left` result,
while write transactions preserve it as `CheckpointWriteInvalid` until the app
boundary renders the typed failure.
`JitML.Service.MinIOSubprocess` provides the live HTTP MinIO
`HasMinIO` interpreter. `If-None-Match: *` duplicate writes and stale
`If-Match` pointer CAS surface as `SEConflict` through the routed `/minio/s3`
edge. For immutable objects other
than per-attempt reservation allocation, both local and MinIO writers follow a
collision with an exact byte comparison: identical bytes are idempotent;
different or unreadable bytes are a typed conflict. Reservation allocation
instead advances its counter on every conflict, including identical bytes.

The checkpoint write/read paths cross the `HasMinIO` capability boundary
through the distinct candidate/completed writers and Store admission. The
supervised path uses
`writeLocalCompletedSupervisedCheckpoint` /
`writeMinIOCompletedSupervisedCheckpoint`; both require non-optional completion
plus a refined `TrainingRuntimeArtifact`. Generic weight-only writers remain for
non-supervised artifacts and fail closed for authoritative supervised
requests. A daemon-dispatched worker with mounted `BootConfig` resolves the
in-cluster MinIO service and invokes the MinIO completed-supervised writer
directly before publishing its completed-checkpoint event; it does not write a
host-local checkpoint mirror and then pretend that path is cluster durability.
Host-side commands without the mounted service context retain their separately
resolved local/edge path. Later workload layers do not invent parallel
supervised persistence paths around this boundary.

Generic decoded effects in `JitML.Service.Workload` may mutate ordinary
checkpoint-bucket data keys, but both weighted and unweighted dispatch reject
any noncanonical bucket/key `ObjectRef` and the Store-owned control prefixes
`manifests/`, `pointers/`, `snapshots/`, and `gc/` before invoking `HasMinIO`.
Dot, dot-dot, empty-segment, absolute, backslash, control-character, and bucket
path aliases therefore cannot normalize onto Store state. Reservation, commit,
manifest, selector, and GC state can be mutated only through Store's validated
transaction protocol.

Completed publication has a stricter commit prerequisite than candidate
persistence. The local writer reads the current latest-pointer expectation;
mounted and Apple-host MinIO writers read the current pointer ETag and pass that
exact expectation into the CAS. The completed Store writer returns
`StoredCompletedCheckpoint` only after the exact pointer names the final
manifest and the immutable snapshot commit record has been installed. A pointer
already naming that exact final manifest is idempotent retry success; another
manifest is a typed conflict. The transient pointer-to-uncommitted state fails
reader admission closed. Only after the committed result may the worker or host
publisher construct and publish the completed-checkpoint event.

## Snapshot-Scoped Immutable Objects and Mutable Selection

### Experiment-Scoped Writer/GC CAS Fence

The Store-owned `ExperimentGcFence` lives at
`jitml-checkpoints/<experiment-hash>/gc/coordination-fence.txt`. Its canonical
value carries a format version, the bound experiment hash, a monotonically
increasing CAS revision, a separate monotonically increasing
writer/root-activity epoch, every full active `WriterReservation`, and the
canonical `GcFenceDecision` history. Every reservation registration and
unregister increments the writer/root-activity epoch; GC-only decisions advance
the revision but not that epoch. Absence for an event means `Open`; recorded phases
are `Planned(g,event)`, `Cancelling(g,event)`, `Cancelled(g,event)`,
`Executing(g,event)`, and permanent `Reaped`. An event's generations are
contiguous from zero through the latest, every earlier generation is complete
`Cancelled`, every generation binds the same byte-identical semantic intent,
and only the latest generation may be nonterminal or destructive.
The object bytes are the exact text prefix `jitml-experiment-gc-fence-v1:` plus
lowercase hexadecimal canonical CBOR; noncanonical text or CBOR is rejected.
MinIO reads the record's exact bytes and ETag from one response and updates it
with compare-and-swap; the filesystem interpreter provides the equivalent
atomic byte/version transition. A process-local lock or a pre/post listing is
not distributed exclusion proof.
GC brackets its complete fresh root view with matching writer/root-activity
epoch observations. Only that exact witnessed epoch may move `Open` or complete
`Cancelled` to `Planned`; GC-only revisions for sibling events therefore do not
invalidate the witness. The live reconciler repeats that complete view in a
bounded convergence loop. Epoch churn restarts it; if an epoch-stable plan
discovers an exact event whose canonical intent is absent from durable state, GC
persists that intent and restarts the entire view before authorization.

Before creating its separate marker, a writer CAS-registers the full reservation
in this experiment record. The same atomic transition changes every overlapping
`Planned` event to `Cancelling` while inserting the reservation. The writer
helps settle every resulting or pre-existing overlapping `Cancelling` event to
complete `Cancelled` by durably writing the byte-identical immutable
cancellation artifact, without deleting the semantic intent, before marker
creation or payload mutation. Intent and artifact may remain physical across
generations; the latest exact fence phase determines logical activity and a
delayed helper has only the same idempotent PUT to repeat. Any overlap with
`Executing` or `Reaped` rejects the writer before marker creation. Full
reservations are required because overlap includes manifest, parent-manifest,
commit, and payload-object identity; an attempt id or snapshot id alone loses
the cross-snapshot parent relationship.

GC first persists the exact initial-plan intent, then converges a complete fresh
root view in a bounded loop with matching epoch observations. Epoch churn
restarts the whole view. An epoch-stable fresh plan that discovers an exact
event absent from durable intent state persists the canonical intent and also
restarts the whole view. Only after convergence may GC CAS-transition an event
from `Open` or complete `Cancelled` to `Planned(g,event)` at that exact epoch. It may transition `Planned` to
`Executing` only when no active reservation overlaps the event. Cancellation
first CASes `Planned` to `Cancelling(g,event)`. Coordinators, writers, or helpers
that encounter that subphase durably write the byte-identical immutable
`cancelled/<event-id>.cbor` and only then CAS `Cancelling` to complete
`Cancelled`, without deleting the semantic `intents/<event-id>.cbor`. Re-arm as
`Planned(g+1,event)` is forbidden until that completion, every protecting root
and marker is gone, and a new exact writer/root-activity epoch is witnessed.
The stable physical objects may span generations and only the latest exact
fence phase is logically active, so a late old-generation helper can only repeat
the same PUT. Helpers re-read the exact `Executing` value and can execute only the
opaque authorization Store derives from it. Store's sole destructive execution
API is `executeAuthorizedGcIntents`; no plan or raw-`GcIntent` compatibility
execution export remains. Complete deletion advances the
entry to permanent `Reaped`. Authorization never physically retires the
cancellation artifact or deletes the semantic intent. Intent cleanup occurs
only after `Reaped` during ready/published terminal handling.

### `snapshots/<snapshot-id>/reservations/<attempt-id>.cbor` — Write-Ahead Ownership

Each writer chooses a fixed-width lowercase-hex attempt id, CAS-registers its
full reservation in the experiment fence, and then creates the marker
absent-only, advancing on every marker conflict even if the existing bytes are
identical. Attempts never share a marker and allocation uses neither RNG nor a
lease. The marker's canonical bytes embed the attempt id and full snapshot
descriptor and bind the attempt,
snapshot id and experiment, candidate/completed transaction kind, final
manifest SHA and exact bytes hash, parent, sorted mapping of original full
logical keys to scoped keys and payload hashes, and the intended pointer
operation. An exact retry uses a fresh marker; it neither reuses nor acquires
ownership of an earlier attempt's marker. Every create conflict advances the
counter without treating even byte-identical existing content as success. The
conflicted attempt's reservation entry is not unregistered: ownership of the
existing marker cannot be proved, so that entry remains conservative permanent
protection. A resumed attempt that encounters an already-registered exact
reservation key also leaves it intact and advances through a fresh registration
attempt before trying the next marker.

The fence entry protects the interval before marker creation; the separate
marker makes partial snapshot writes explicit and still precedes every payload
write. A crash before fence registration leaves nothing. A crash afterward can
leak the entry, the marker, or both, and each leak remains active protection
forever whether or not that attempt or a later one reaches commit. There is no
time-based cleanup and commit overrides neither form of protection. A successful
attempt deletes only its own marker and then CAS-unregisters only its own full
fence entry, in that order. An exact retry uses a fresh marker to repair
immutable state but cannot delete a marker or entry leaked by another attempt.

### `snapshots/<snapshot-id>/objects/*` — Snapshot-Owned Payload Objects

Every persisted payload object is written at the scoped address derived from
`sha256(original-full-key)`, and its exact payload SHA must equal the
attempt marker's map, the attempt-independent commit, and the bytes read at
admission. The scoped path must
also rederive from the canonical logical address required by the payload
variant; sharing the right snapshot prefix is insufficient. This includes weights, optimizer state, RNG state, replay or
exploration state, RL trajectory evidence, AlphaZero self-play transcripts,
tuning transcripts, and substrate artifacts. PUTs use `If-None-Match: *` or the
atomic local-filesystem equivalent; only absent or byte-identical content
succeeds. Cross-snapshot deduplication is intentionally traded for exclusive
ownership, which prevents a snapshot-owned key from being reused by a different
snapshot. The experiment CAS authorization, rather than namespace ownership
alone, excludes a paused or stale GC executor while a writer holds overlapping
state.

The `tune-trials-v2` companion payload still binds the projected `row-id`,
semantic `plan-id`, experiment hash, dataset-at-read SHA, best trial's final
JMW1 SHA, and the exact ordered contiguous trial executions. Construction
requires one and only one promoted execution equal to the selected best trial,
finite hyperparameters/objectives/observations/weights, completed trial and
update counts equal to the observed execution, and exactly one
`best_objective` completion measurement equal to that best trial.

### `snapshots/<snapshot-id>/committed.cbor` — Immutable Eligibility

The commit identity and canonical bytes are independent of every attempt id.
After all owned objects and the final manifest exist, a candidate writes the
exact absent-or-identical commit record, deletes only its own marker, and then
CAS-unregisters its full experiment-fence entry. A completed writer instead
performs latest-pointer CAS, writes the same attempt-independent commit, and
uses that same marker-first/fence-entry-second cleanup. A crash after
pointer CAS is repaired by a fresh attempt recognizing the already-final
pointer and completing the commit. A crash after commit but before marker
deletion leaves an eligible snapshot and a permanent protective root: commit
does not take precedence over, cancel, or weaken a leaked marker or fence entry. Admission,
retention, and GC consider only snapshots whose manifest, canonical original-
to-scoped ownership map, payload hashes, re-derived identity, and exact commit
agree; GC additionally protects every extant attempt marker.
For a zero-payload-object snapshot, that ownership map is empty, the snapshot
id is derived from the exact logical manifest and empty binding list, and the
commit is the sole GC-owned key. A commitless legacy empty manifest stays
protected and decode/inspection-only rather than becoming admissible by
vacuous ownership.

### `manifests/<sha256>.cbor` — Write-Once Content-Addressed CBOR Manifests

Each manifest names the scoped object addresses and hashes that constitute one
logical checkpoint plus the metadata needed to interpret them. The supervised-
graph variant additionally embeds and independently identifies the exact
supervised runtime body. Manifest objects use the same absent-or-byte-identical
write-once protocol.

The manifest's SHA is the canonical *checkpoint id* used by candidate and
completed checkpoint events, RPC envelopes, and `--resume <checkpoint-id>`.

### `pointers/*` — The Only Mutable Objects

Each pointer's body is a manifest SHA. Updates use S3 conditional PUT with
`If-Match: <etag>` compare-and-swap. It is the mutable selection point, not the
immutable eligibility proof: exact `committed.cbor` supplies the latter. ETags
are writer-CAS tokens, not reader snapshot identity. Candidate writers do not
update `latest` and return only `StoredCandidateCheckpoint`. Completed writers
require non-optional `CompletedTraining`; a stale expectation naming another
manifest is a typed conflict and cannot be relabelled as completed persistence.

## `.jmw1` Dense Weight Blob Format

`JitML.Checkpoint.WeightCodec` owns the frozen JMW1 vector codec independently
of manifest versions. The format starts with magic bytes, a little-endian CBOR
header length, the CBOR header, then packed little-endian values:

```
offset   field         type             notes
0        magic         4 bytes          "JMW1"
4        header_len    uint32 LE        size of CBOR header in bytes
8        header_cbor   bytes            CBOR canonical form
8+H      payload       bytes            packed dense tensors, no padding
```

The implemented header contains dtype `F64` and the flat element count. The
decoder requires exactly that many IEEE-754 doubles, rejects truncation,
trailing bytes, unsupported dtype, and non-finite values, and never pads or
trims. `jmw1ContentSha` hashes the exact observed bytes without decode/re-encode.

For the supervised-graph payload, this one flat vector is the complete physical
parameter payload. Tensor names, shapes, layer association, and derived offsets
live in the runtime/manifest binding; they are not duplicated inside JMW1. The
runtime's graph-order prefix sums must consume the decoded vector exactly. The
initial and final hashes in completion evidence are SHA-256 of the exact JMW1
bytes consumed at initialization and returned at training completion.

## CBOR Manifest

The domain `CheckpointManifest` carries manifest/experiment identity, model
family, architecture, preprocessing, output decoders, weight layout,
replay/transcript and substrate artifacts, physical tensor/optimizer/RNG
objects, step, metrics, `PlanId`, refined completion, mirrored
initial/final/update/dataset evidence, parent identity, and the optional exact
supervised runtime payload. The CBOR boundary does not serialize that refined
domain value directly. Its persisted values are forgeable raw DTOs which must
be refined on decode.

The one self-describing envelope carries a typed payload sum:

```haskell
-- File: src/JitML/Checkpoint/Format.hs
data RawCheckpointEnvelope = RawCheckpointEnvelope
  { rawCheckpointVersion    :: !Word64      -- payload-variant tag (1 weight-only, 2 supervised-graph)
  , rawCheckpointBodySha256 :: !ByteString  -- raw 32-byte SHA-256 of the exact body bytes
  , rawCheckpointBodyBytes  :: !ByteString  -- serialise (RawCheckpointBody)
  }

data RawCheckpointBody
  = RawWeightOnlyBody RawCheckpointManifest
  | RawSupervisedGraphBody RawCheckpointBodyV2

data RawCheckpointManifest = RawCheckpointManifest
  { rawManifestPlanId            :: !(Maybe Text)
  , rawManifestCompletedTraining :: !(Maybe RawCompletedTraining)
  -- candidate checkpoint metadata, blobs, metrics, evidence mirrors, lineage
}
```

The weight-only body is the bare `RawCheckpointManifest`; the supervised-graph
body is a canonical `RawCheckpointBodyV2` containing that raw manifest plus
`RawSupervisedRuntimePayload`. Both are wrapped in the one envelope above, whose
`rawCheckpointBodySha256` independently identifies the exact body bytes.

The optional fields make candidate and partial checkpoints representable for
inspection and resume. They do not make completion optional at the completed
writer or inference boundary: structural refinement can construct only
`ValidatedCheckpointCompletion`, while Store constructs an
`AdmittedCompletedCheckpoint` only after exact persisted admission.

`TensorSpec`, `ArchitectureMetadata`,
`PreprocessingMetadata`, `OutputDecoder`, `WeightLayout`, `ArtifactPointer`,
and `SubstrateArtifact` are part of the serialized manifest contract.
`encodeManifestCbor` canonicalizes tensor order by `tensorName`, optimizer
order by `optimizerKind`, RNG order by `rngStreamId`, metrics by name,
architecture input/output specs by name, preprocessing inputs by name,
weight-layout tensors by name, output decoders by name, and artifact pointers
by their identity fields; the format decoder round-trips a versioned raw
representation, semantic refinement constructs the domain manifest, and
`manifestContentSha` hashes the exact encoded outer bytes. A supervised-graph
checkpoint's `FlatWeightLayout` is one graph-ordered `supervised.weights` spec of
the trained graph's parameter count.
Persisted admission requires every replay/transcript `ArtifactPointer` to carry
an exact SHA and rejects duplicate payload-object keys. For Product publication, the
supervised-graph payload has no companion pointer; each RL weight-only row has
one `rl-trajectory`, each AlphaZero weight-only row one
`alphazero-transcript`, and the tuning weight-only row one `tune-trials`
pointer.

Completed manifests are populated only from opaque completion evidence; the
checkpoint projection writes the completion `PlanId` into the manifest and
mirrors its smart-constructed weight-delta evidence into the raw fields. Product
origin derives the exact ProductRow plan/budget from the unique substrate
projection. Generic origin derives the exact plan/budget/seed from the
canonically reparsed embedded transport. In both cases the completion, runtime,
manifest, selected substrate, experiment, epoch count, and optimizer-update
count must agree with that single origin-bound plan.
`RawCompletedTraining` itself is versioned and re-refines its budget kind,
target, observed kind/count/unit, typed finite criteria, non-empty passing
measurements, and training evidence while retaining the TensorBoard metadata.
Training evidence now includes the run's `DeviceExecutionWitness` — the
substrate, the backend and executed identity read back out of the compiled
artifact, the content-addressed cache key, the artifact path, and the SHA-256 of
the artifact bytes. The manifest stores only the four observations
(initial/final weight hash, update count, dataset SHA at read), so the
manifest-versus-completion cross-check compares observations
(`evidenceObservationsMatch`) rather than whole evidence records; the witness
travels inside the embedded completion. `requireAdmittedCompletedCheckpoint`
rejects a completion carrying no witness, making
`admittedCompletedDeviceWitness` total.
That witness field is a wire migration, and the decoder states it rather than
assuming it. Training evidence persisted before the witness existed carries five
fields where the current shape carries six; the decoder accepts that pre-witness
shape and fills the witness with `Nothing`. This does not weaken the contract —
witnessless evidence is exactly what admission rejects — so a checkpoint written
before the witness fails at the admission gate naming the missing device
execution witness rather than at CBOR with a field count that says nothing about
why the artifact is inadmissible. Reading such a checkpoint is therefore
possible; admitting it is not, and the live store must be re-issued from a
witnessed run before its rows can become inference-eligible again.
The current encoder emits V2, whose optional ProductScenario invocation binds
one exact command-owned run, row, plan, substrate, canonical checkpoint scope,
executable digest, and fresh challenge. The exact V1 nine-field tuple remains
decodable as a completion with no ProductScenario invocation; it stays
inspectable through the checkpoint and nested protocol boundaries but cannot
satisfy the Phase `261` execution-evidence boundary, which requires equality
with the current invocation.
That persisted invocation is necessary but not independently sufficient for a
cross-process ProductScenario report. Journal version `3` HMAC-authenticates the
exact current-run aggregate and its projection-ordered row fields; the parent
authenticates the journal before requiring invocation equality and re-admitting
each recorded manifest address through Store. Thus neither a copied checkpoint
carrying a V2 `RawCompletedTraining` DTO, an authenticated journal row naming a
different address, nor a
successful child exit can substitute for the joined persisted identities.
The persisted form contains no authoritative pass boolean; structural
completion validation requires TensorBoard scalar tags and rejects a manifest
that lacks mirrored evidence, carries invalid/non-finite evidence, names
another plan, differs from the completed witness, or whose manifest step is not
exactly the completed observed budget. Persisted admission then independently
binds that validated structure to its exact fetched bytes.
Each completed convergence observation must also appear exactly once with the
same value in the manifest metrics. TensorBoard run id, log prefix, and ordered
scalar tags are re-bound to the manifest experiment and completed convergence
metric names rather than trusted as independent display metadata.
For supervised-graph rows, `manifestDatasetShaAtRead` is the observed digest
from the verified dataset read boundary. Image/label or archive bytes are
fetched through `JitML.SL.Dataset.fetchVerifiedDatasetArtifactBytes`, checked
against their canonical pins before decode, and combined through
`datasetReadShaForArtifacts` in deterministic artifact order. Where training
and test splits are separate objects, the digest covers the exact verified
train and held-out artifacts actually read; archive-backed rows cover the exact
verified archive from which both partitions are materialized. That digest is
mirrored into completion, the runtime payload, and the manifest. Upload-time
SHA claims alone cannot supply it.

Successful supervised execution also returns
`tmOptimizerUpdatesExecuted` only after every requested epoch and mini-batch
loop completes. `completedSupervisedRuntimeForTraining`,
`attemptGenericSupervisedRuntimeForTraining`, and the ProductRow publisher carry
that observed count through the Writer/Publisher boundary, require it to equal
the origin-bound `SupervisedPlan` optimizer-update quantity, and require the
resulting completion and manifest update counts to remain identical. No caller
may re-mint the count from plan metadata after training; substitution is a typed
construction failure.

The legacy `tmInitialCheckpointWeights` and `tmCheckpointWeights` lists are
optional projections only. If present they must equal the decoded exact JMW1
vectors, but absence never blocks a generic finite below-bar completion miss.
The required exact initial/final JMW1 bytes and their hashes remain mandatory
for both miss assessment and passing supervised-graph construction.

`TrainingMetrics` additionally carries one mandatory
`tmParityProbeInput`/`tmParityProbeOutput` pair produced immediately by the
training-returned model. Classifier rows use an exact held-out example and its
semantic numerical model output; California Housing uses an exact raw held-out
feature row and the prediction after the persisted target inverse-transform.
The pair is finite and dimension-checked against the refined runtime. It lets
the production parity gate compare the Store-loaded supervised graph with the model
that actually trained, without reconstructing a model, inventing an input, or
using a codec-only round trip as execution evidence.

## Concurrency Model

Trainer/reader races are removed at the object protocol layer. MinIO uses
conditional object operations and an atomic byte-plus-ETag read followed by CAS
for the experiment coordination record. The local interpreter uses atomic
hard-link publication for immutable objects and locked atomic compare/replace
for mutable records. That local lock is an implementation of CAS semantics; it
is not the writer/GC proof. The durable experiment-fence transition is the proof,
and no lease or separate lock service is required.

| Hazard | Boundary |
|--------|----------|
| Writer/GC across snapshots in one experiment | A writer atomically CAS-registers its full reservation, advances the writer/root-activity epoch, cancels every overlapping `Planned` event in the same transition, and rejects overlap with `Executing`/`Reaped`; unregister advances the epoch again. GC brackets the complete fresh root view with matching epoch observations and reaches `Executing` only through an exact-epoch freshly revalidated `Planned` generation with no overlapping entry. Sibling GC-only revisions do not invalidate the witness. Full reservations retain `parentManifestSha`, so a child writer and another snapshot's reap target contend on the same record. |
| Write/write on per-attempt reservation markers | After fence registration and cancellation settlement, allocation uses absent-only create and increments the fixed-width lowercase-hex counter on every conflict, including byte-identical content; attempts never share a marker. Because a conflict cannot prove ownership of the existing marker, its registered entry remains conservative protection while a freshly registered attempt advances. Successful cleanup deletes the owned marker before CAS-unregistering the matching fence entry. |
| Write/write on snapshot objects, the attempt-independent commit, and manifests | Deterministic scoped keys use `If-None-Match: *`; every interpreter accepts a pre-existing object only after exact byte comparison. |
| Write/read on immutable snapshot state | Atomic object publication plus exact commit, address, length, content, and complete ownership checks reject torn, partial, or substituted snapshots before admission. Every extant marker or active experiment-fence entry remains separate GC protection. |
| Write/write on `pointers/*` | MinIO `If-Match: <etag>` and the locked local compare/rename interval are exact writer CAS operations. Another final manifest is a typed conflict; the exact already-final manifest is retry success completed by commit. |
| Write/read on `pointers/*` | Store reads exact body `P1`, verifies the addressed committed manifest, reads exact body `P2`, and starts scoped-object binding only when the bodies match. ETag equality is deliberately irrelevant to reader stability. |

## Typed Advance Predicates

The pointer-CAS retry harness applies the typed `AdvancePredicate` ADT in
`src/JitML/Checkpoint/Format.hs` through `applyAdvancePredicate`:

| Predicate | Meaning |
|-----------|---------|
| `advanceLatest` | `cmStep new > cmStep cur` |
| `advanceBestMaximised` | `lookupMetric m new > lookupMetric m cur` |
| `advanceBestMinimised` | `lookupMetric m new < lookupMetric m cur` |

Trainers pick `Maximised` vs `Minimised` from the experiment Dhall's
`metrics[i].direction` field. The direction is part of the resolved-Dhall
hash, so flipping a metric's direction defines a *different experiment*.
The current worktree has `AdvanceLatest`, `AdvanceBestMaximised`, and
`AdvanceBestMinimised` constructors, pure `applyAdvancePredicate`, a pure
`PointerWrite` / `applyPointerWrite` decision surface, and local/MinIO Store
interpreters. The separate candidate/completed transactions apply the
experiment-fence registration → unique attempt marker → scoped objects →
manifest → candidate-commit or completed-pointer-CAS → completed-commit → delete
only that attempt's marker → CAS-unregister only that fence entry protocol
through the live HTTP
implementation in `JitML.Service.MinIOSubprocess` or the exact filesystem
equivalent.

## Retention and GC

For a live publication, the durable-state registry's typed `checkpoints`
retention is enforced by the explicit
`jitml internal gc <experiment-hash>` reconciler. Trainers do not invoke the
command; an operator or external scheduler owns its cadence. Re-running live
`gc` after deletion and durable-outbox recovery reach steady state is a no-op
(exit code `3`). Without a live publication, the command scans the local
checkpoint tree and reports the deterministic plan but does not delete local
objects.

- **Complete fail-closed listing.** MinIO discovery follows every
  ListObjectsV2 continuation page for manifests, commits/reservation markers, catalogue
  roots, intents, cancelled records, ready records, and published tombstones.
  Page one must omit `ContinuationToken`; every later response must echo exactly
  the token requested. A malformed response, missing/empty/repeated/mismatched
  continuation token, duplicate or non-globally-strictly-ascending key,
  bucket/prefix/key mismatch, or transport failure on any page rejects the
  complete listing; GC never plans from a partial page prefix.
- **Root set.** In every `buildGcPlan`, a structurally completed manifest whose
  experiment hash belongs to a canonical ProductRow is an intrinsic always-live
  root. This closes the race in which a ProductRow completes after a GC snapshot
  but before catalogue publication. On the live branch, every immutable
  browser-catalogue root is also append-only and resolves against the exact
  listed manifest set; malformed, unreadable, or unresolved roots fail closed.
  `walkLiveSet` retains each root or selected manifest plus its immediate
  `cmParentManifest` reference.
- **`LastN k` semantics.** `LastN k` keeps the `k` highest-step candidate
  manifests in canonical `(step descending, manifest SHA ascending)` rank.
  Intrinsic ProductRow and append-only browser-catalogue roots override
  `LastN`.
- **Committed snapshot ownership.** A manifest is retention/GC eligible only
  when its exact `snapshots/<snapshot-id>/committed.cbor` binds the manifest and
  the sorted canonical-original → exact-scoped → payload-SHA descriptor.
  Store reverses that mapping to reconstruct the exact logical manifest and
  re-derives `snapshot-id`; it also requires each payload SHA to bind the exact
  payload-object bytes. The non-empty scoped keys must share exactly one snapshot
  namespace. For the zero-object case, Store derives the
  snapshot id from canonical CBOR over `jitml-snapshot-v1`, the exact logical
  manifest, and the empty binding list; `committed.cbor` is the sole GC-owned
  key. Without that commit, a legacy empty manifest is protected and ineligible.
  Every extant per-attempt reservation marker and every active full reservation
  in the experiment coordination record is a root, even when the matching commit
  exists, so crashed writer state is never collected by age and commit never
  overrides leaked protection. The owned set covers every tensor, optimizer, RNG, replay pointer,
  transcript pointer, and present substrate-artifact payload object. A supervised-graph
  manifest owns one physical `supervised.weights` object; graph-ordered flat
  slices remain derived metadata. Snapshot-exclusive addresses scope the exact
  deletion keys; the experiment CAS fence provides stale-executor exclusion.
- **Durable intent, fresh proof, and cancellation.** `buildGcPlan` is
  independent of listing order and produces one event per reap target with
  sorted, unique snapshot-owned deletion keys: every payload object plus exactly
  one `committed.cbor` from one snapshot namespace. Before mutation the complete plan is canonical
  CBOR at `jitml-checkpoints/<experiment>/gc/intents/<event-id>.cbor`. The
  executor then takes a fresh complete view of manifests, mutable pointer
  bodies, browser-catalogue and intrinsic roots, marker reservations, the full
  reservations and per-event generations in the experiment coordination record,
  ready records, and published tombstones, bracketed by matching observations of
  the fence's monotonic writer/root-activity epoch. The complete view is a
  bounded convergence loop: epoch churn restarts it, and an epoch-stable fresh
  plan that discovers an exact event absent from durable intent state first
  persists the canonical intent and then restarts the entire view. Late
  unpublished ready events are published and acknowledged, while a published
  event is acknowledged again only when its transient ready/intent state
  remains; either case counts as work and restarts the complete view. If the target or any exact owned key
  is now live or the commit/ownership proof differs, it persists
  `gc/cancelled/<event-id>.cbor` and performs none of that intent's deletes.
  Cancellation is whole-intent rather than key filtering, so the semantic event
  id can never describe a set different from the one executed.
- **CAS authorization and helpable execution.** Freshly revalidated work moves
  `Open` or complete `Cancelled` to `Planned(g,event)` in the experiment record
  only at the exact witnessed writer/root-activity epoch; sibling GC-only
  revisions do not invalidate the witness. A writer insertion that
  overlaps a planned event atomically records the full reservation and changes
  the event to `Cancelling(g,event)`; overlap with `Executing` or permanent
  `Reaped` rejects the writer before marker creation. Writers and coordinators
  help `Cancelling` by durably writing the byte-identical immutable cancellation
  artifact and CASing to complete `Cancelled`, without removing the semantic
  intent, before writer mutation or re-arm. GC moves `Planned` → `Executing`
  only with no overlapping active entry. `Cancelled(g,event)` can re-arm at
  generation `g+1` only after its roots and markers disappear and a new exact
  epoch is witnessed. The stable intent/artifact may span generations; the
  latest exact fence phase determines logical activity and delayed helpers only
  repeat the same PUT.
  Executors and helpers re-read exact `Executing` state and delete only through
  Store's opaque authorization. `executeAuthorizedGcIntents` is the only
  destructive execution API; raw-plan and raw-intent compatibility exports do
  not exist. If an earlier partial execution already removed the manifest,
  revalidation requires the latest fence decision to bind the byte-identical
  intent in `Executing` or permanent `Reaped`; absence without that history is
  cancelled and cannot create a witness. Successful completion CASes to permanent
  `Reaped`. Authorization never physically retires cancellation artifacts or
  deletes semantic intents; semantic-intent cleanup occurs only after `Reaped`
  during ready/published terminal handling.
- **Global manifest barrier and retry.** After CAS authorization, execution first
  requests deletion of every reap-target manifest. Only when every manifest
  deletion is acknowledged does it touch any snapshot-owned deletion key; one
  manifest failure defers all snapshot-owned deletes in that pass. DELETE of an already-absent
  object is success, so the exact retained intent is safely retryable. An event
  completes only when its manifest and every assigned snapshot-owned object
  have acknowledged deletion and its experiment-fence event becomes permanent
  `Reaped`. Exact successes are promoted even when an unrelated event fails.
- **Durable publish outbox and permanent tombstone.** Promotion checks
  `gc/published/<event-id>.cbor` before writing ready and again after the ready
  PUT, only after the fence decision is permanent `Reaped`. If published already
  exists, recovery cleans transient intent/ready state from that terminal flow
  without republishing. Otherwise the first ready record fixes the stable
  `event_id`, substrate, completion timestamp, and sorted exact
  `reaped_object_keys`. Publication uses the stored substrate's
  `gc.event.<substrate>` topic through the current edge. After broker success,
  acknowledgement re-reads the matching permanent `Reaped` fence decision, the
  exact durable ready bytes, and any existing published tombstone. It may create
  `gc/published/<event-id>.cbor` only while that exact ready record still exists;
  when ready is absent, only an already-existing byte-identical published
  tombstone makes retry acknowledgement succeed. Any other missing or mismatched
  state fails closed. The exact `GcReadyEvent` is persisted absent-or-identical
  under `gc/published/` before ready and intent are deleted from the
  already-`Reaped` terminal flow. A crash before the tombstone may retry the
  identical broker payload at least once; after it exists, no retry can
  manufacture a new timestamp or payload.
- **Canonical broker codec and strict keys.** `renderGcReapedEvent` emits
  `jitml-gc-reaped-event-protobuf-hex-v1:` plus lowercase hexadecimal of the
  canonical protobuf bytes. Parse decodes and re-encodes for exact canonical
  equality. It rejects malformed/unknown fields, forged event or manifest
  identity, a key set that does not contain exactly one snapshot and exactly one
  `committed.cbor`, unsorted/duplicate deletion keys, non-full aliases, dot/dot-dot or
  control segments, reserved control prefixes, and cross-experiment keys.

The current store exposes `RetentionPolicy{KeepAll,LastN}`, `walkLiveSet`,
`applyRetentionPolicy`, `buildGcPlan`, `listCheckpointManifests`,
`listCheckpointManifestsMinIO`, durable experiment-fence and
intent/cancelled/ready/published operations,
`executeAuthorizedGcIntents` as its sole destructive execution API, and
exact per-event outcomes over the typed
`HasMinIO` boundary. `jitml internal gc <experiment-hash>` detects the live
cluster publication
(`./.build/runtime/cluster-publication.json`) and routes the live half through
the durable coordination and intent/cancelled/ready/published state,
`listCheckpointManifestsMinIO`, committed-snapshot admission and writer
marker/entry protection, `buildGcPlan`, intent persistence, fresh
recovered-plus-new intent revalidation through bounded complete-view
convergence, CAS authorization, exact execution,
ready promotion, and broker-success tombstoning
via `JitML.Service.MinIOSubprocess`; the live interpreter treats a missing
DELETE target as idempotent success. The
offline branch only plans from
`<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/` and
does not execute deletions.
`JitML.Product.BrowserCatalogue` writes the per-row immutable archival roots
before selector CAS, so selector changes and selector-CAS losers remain rooted.
The live GC calls `loadProductBrowserCatalogueGcRoots` before `buildGcPlan` and
aborts rather than reaping when root listing, shape, payload, or exact manifest
resolution fails. Offline GC has no browser-catalogue object-store roots.
Unsafe offline experiment-hash-derived prefixes fail as typed validation before
filesystem path construction and render through `InvalidConfig`.
The stdout reports
`gc: <experiment-hash> kept=<n> reaped=<n> reaped-objects=<n>` (live) or
`gc: <experiment-hash> kept=<n> reaped=<n>` (offline) and exits `3`
only when the converged fresh plan is a no-op and there was no reconciliation or
recovered-outbox work. Persisting an exact intent discovered by either the
initial plan or a fresh plan counts as work; only the converged plan supplies
the live `kept` count and no-op decision. Late ready publication or
published-transient cleanup also counts as work and forces a fresh pass.

`JitML.App.publishGcReadyEvents` publishes one `GcReapedEvent` per durable,
not-yet-published ready record, selecting the topic from that record's stored
substrate rather than the current publication substrate. Its post-broker
acknowledgement path re-reads that exact durable ready record and the matching
permanent `Reaped` fence decision before writing the exact published tombstone
and cleaning ready/intent state; if ready is already absent, only an exact
existing published tombstone permits idempotent acknowledgement. The envelope
carries `event_id`, `experiment_hash`,
`manifest_sha`, repeated exact `reaped_object_keys`, `step_at_reap`, the ready
record's stored `substrate`, and `timestamp_ns`; strict text and proto3 codecs live in
`JitML.Proto.Gc`. `reaped` counts exact fully completed manifest events, while
`reaped-objects` counts all assigned snapshot-owned delete acknowledgements:
the payload-object keys plus the exact `committed.cbor`, including idempotent
already-absent acknowledgements. A zero-payload-object snapshot therefore
contributes `reaped-objects=1`. The manifest is represented by `manifest_sha`,
not duplicated in `reaped_object_keys`.

## Inference-Only Read Path

`loadInferenceCheckpointWithWeights` calls Store's stable latest admission,
requires an admitted completion, and invokes an explicit runner with the exact
bound weight payloads. `loadInferenceCheckpointDecodedWithWeights` applies the
manifest-bound decoder after that runner. A caller which already holds a known
address uses `admitCheckpointAt` followed by
`requireAdmittedCompletedCheckpoint`; this performs the same exact immutable
manifest/scoped-object/commit binding without a pointer lookup.

For a supervised-graph checkpoint, `loadSupervisedRuntimeFromCheckpoint` accepts
only one `supervised.weights` object and verifies its flat shape and exact bytes
against the trained graph's parameter count
(`layerGraphMetadataParameterCount`). Serving reconstructs the trained
`LayerGraph` from `architectureLayerGraph`, injects that one physical
graph-ordered vector as the parameter vector, runs `LayerGraph.runLayerGraph`,
and applies the exact input/output transforms outside the graph
(`runSupervisedGraphCheckpointInference` /
`RuntimeArtifact.executeSupervisedGraphRuntime`). Phase `239` deleted the
per-substrate structural-operation ABI, the `RuntimeBackendExecutor`, and the
served layer-operation program: there is no fall back to a legacy layer graph,
Dense/MLP shortcut, demo topology, caller-supplied model, or another substrate.
The loader resolves the closed origin first, reconstructs its exact bound plan,
and validates that plan's substrate rather than assuming every supervised
checkpoint is a ProductRow publication. Weight-only payloads remain on their
isolated non-supervised engine paths and cannot enter supervised execution.

The exact per-row served topology (`cifar10-vit` and the other token families) is
the trained typed `LayerGraph`; its end-to-end coherence is validated on the
`jitml-sl-canonicals` lane. The one physical `supervised.weights` vector is the
graph-ordered parameter vector whose length is the graph's parameter count. Fresh
publication uses the supervised descriptor's exact finite-positive learning rate
as part of semantic `PlanId` identity: `3e-3` for `fashion-mnist-resnet`,
`1.1e-3` for `cifar10-resnet20`, `1.5e-3` for `cifar10-vit`, and `1e-3` for the
other eight rows.

Serving runs the pure `LayerGraph.runLayerGraph` reference executor over the
frozen graph-ordered parameters, so there is no structural-ABI reimplementation
between the training-returned and Store-loaded serving paths. The
trained-versus-served relationship — including the current device `float32`
training path — is owned by
[determinism_contract.md](determinism_contract.md#the-contract) and is not
restated here.

The pointer-selected loader reads `P1`, verifies the exact addressed manifest,
reads `P2`, requires the exact commit and descriptor, and only then fetches and
binds scoped payload-object bytes. A changed exact
pointer body returns `AdmissionPointerChanged` without blob I/O. The completed
inference boundary consumes only the resulting opaque Store-admitted artifact.

`JitML.Service.Runtime.daemonWorkloadDispatcherWithInference`
keeps that explicit injected-runner hook available for tests. Production
`jitml service` self-inference selects
`daemonWorkloadDispatcherWithWeightedInference`, which uses
`loadInferenceCheckpointWithWeights` to load the weight-only `.jmw1` blobs
through `HasMinIO`, decode them, and pass them to the selected substrate's
weighted checkpoint runner. The `jitml-demo` REST inference/generic/image/
checkpoint-compare/Connect 4 routes now accept generated browser request
envelopes and call an injected checkpoint runtime handler when a live
publication is available; without that handler they fail closed with
`503 checkpoint-required`.

The inference topic contract is declared in `proto/jitml/inference.proto`.
`JitML.Proto.Inference` mirrors the `InferenceRequest` and `InferenceResult`
messages with text render/parse helpers plus proto3-compatible byte codecs;
the input/output vectors are encoded as packed repeated doubles.

## TensorBoard Sidecar

Target `CheckpointDone` events also write a CBOR sidecar at
`jitml-tensorboard/<experiment-hash>/checkpoints/<step>-<manifest-sha>.cbor`:

```haskell
-- File: src/JitML/Observability/TensorBoard.hs
data TbCheckpointMarker = TbCheckpointMarker
  { tcmStep          :: !Word64
  , tcmEpoch         :: !Word64
  , tcmManifestSha   :: !Hash32     -- references the checkpoint manifest in jitml-checkpoints
  , tcmExperimentSha :: !Hash32
  , tcmTrialSha      :: !(Maybe Hash32)
  , tcmRunUuid       :: !Uuid
  , tcmMetricsAtStep :: ![(Text, Double)]   -- mirror of the manifest's metric snapshot
  }
```

CBOR canonical-form, content-addressed-style, written with `If-None-Match:
*`. The PureScript frontend lists the `checkpoints/` prefix once at panel-
load and overlays clickable markers on the TB iframe's loss curve — clicking
opens the inference panel pre-loaded with that manifest SHA.

The current local sidecar surface includes
`JitML.Observability.TensorBoard.checkpointSidecarKey`,
`TbCheckpointMarker`, `encodeTbCheckpointMarker`, and
`JitML.Observability.TbSidecar.{writeCheckpointSidecar,dispatchCheckpointDone,dispatchCheckpointPayload}`
over `HasMinIO`, with filesystem-backed integration coverage.
`JitML.Service.Runtime.daemonTensorBoardDispatcher` wires rendered
`CheckpointDone` payloads into that sidecar writer before ack, and
`JitML.Service.MinIOSubprocess` persists the CBOR object in MinIO.

## Bit-Determinism

Target same-substrate same-toolchain reproduction of a checkpoint produces a
byte-identical `.jmw1` payload and a byte-identical manifest SHA. Cross-substrate
bit-equality is **not** guaranteed and not asserted (RNG draws + float reduction
order differ across substrates) per
[determinism_contract.md → The Contract](determinism_contract.md#the-contract).
The supervised-graph reload-parity assertions compare a training-returned model
output with its Store-loaded execution; they do not relax byte identity for the
persisted weights or manifest.

## Cross-References

- [../../README.md → Checkpointing](../../README.md#checkpointing)
- [../../README.md → Concurrency model](../../README.md#concurrency-model)
- [determinism_contract.md](determinism_contract.md)
- [training_workloads.md](training_workloads.md)
- [run_contract.md](run_contract.md)
- [Phase 262: Contract-Driven Live Execution — Browser and Playwright](../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md)
- [Legacy Phase 10: Checkpointing and Inference](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 13: No-Caveat Model Runtime](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 18: No-Caveat Product Handoff](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
