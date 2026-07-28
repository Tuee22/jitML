# Checkpoint Format

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md, determinism_contract.md, training_workloads.md, durable_state_dsl.md, training_metrics_and_splits.md, numerical_core.md, product_completion_contract.md, run_contract.md
**Generated sections**: none

> **Purpose**: Project-specific checkpoint format for jitML — split-blob
> layout, `.jmw1` dense weight blob wire format, typed CBOR manifest, write-
> once + If-Match CAS protocol, retention reconciler, inference-only read
> path, inference request/result protobuf envelopes, and the architecture-aware
> checkpoint target for every model family, including the trained-artifact
> witness required before inference.

**Durable-state retention (Sprint 10.8):** the checkpoint GC retention is a typed
`RetentionPolicy` sourced from the durable-state registry's `checkpoints` store
(`JitML.Project.Config.lookupStoreRetention`), replacing the former hardcoded
`LastN 5` literal. See [durable_state_dsl.md](durable_state_dsl.md).

**Typed local object-key validation (Sprint 10.11):** local filesystem
object-key validation returns data, not bottoms. `objectPathForKey` /
`safeRelativePath` reject empty, absolute, and parent-traversing keys as
`Left Text` before path construction. Read/list helpers retain that validation
result; write transactions convert it to `CheckpointWriteInvalid`, while
immutable-object and pointer collisions use distinct typed conflict
constructors. User-facing commands such as local `jitml internal gc
--experiment-hash ...` report a typed error instead of terminating.

**Structural completion and persisted admission are distinct.** The V1 body
contains a forgeable `RawCheckpointManifest` and, when present, a versioned
`RawCompletedTraining`. Decoding re-refines those raw fields before a domain
manifest exists. `ValidatedCheckpointCompletion` is deliberately named and
documented as a structural result only: it makes no persistence claim. Store
alone constructs `AdmittedCheckpoint` / `AdmittedCompletedCheckpoint` after an
exact stable-address read and physical-payload binding. Pipeline consumes that
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

**Implemented today (Phase `235` closed 2026-07-27).** The checkpoint wire is
**one self-describing envelope**: a payload-variant version, the raw 32-byte
SHA-256 of the exact canonical body bytes, and those body bytes. The body is the
typed `RawCheckpointBody` payload sum with two variants — **weight-only** (the
bare canonical manifest, for the RL, AlphaZero, tuning, and generic rows) and
**supervised-graph** (the manifest plus the exact supervised runtime program, for
the eleven supervised rows). A single `encodeManifestCbor` arm, a single
`decodeAddressedManifestCbor` that dispatches on the payload sum (no version
cascade or fall-through), and one `canonicalManifest` serve every row. The
byte-frozen V1 golden fixture, the dead V3 `LayerGraph` encoder, the retained
pre-Sprint-`10.12` legacy decoder, and the parallel `canonicalManifestV2` were
all retired; checkpoints are regenerated deterministically from current source,
so no persisted bytes are reinterpreted. Store admission is likewise **one path**
(Phase `236` closed 2026-07-27): a decode with no per-version allow-list, then a
single classify-on-payload-variant — a supervised-graph checkpoint is admissible
only with no companion pointer, a weight-only checkpoint routes through the
authoritative non-supervised ProductRow companion rules. The dormant
`LayerGraph`-from-checkpoint reconstruction helpers were deleted.

**Target (Phases `237`–`245`, see [DEVELOPMENT_PLAN](../../DEVELOPMENT_PLAN/README.md)).**
The supervised-graph payload becomes the trained `LayerGraph` itself (Phases
`237`–`239`), replacing the embedded `SupervisedRuntime` served representation
described below; the V2 `SupervisedRuntime` read/serving path
(`loadSupervisedRuntimeFromCheckpoint`) is removed in Phase `237` when serving is
rewired onto the IR. Until those phases close, the supervised-graph payload carries
that `SupervisedRuntime` program; the reader/serving migration onto the IR is a
target contract, not yet a current claim.

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

The supervised-graph runtime program and its closed origin contract (immediately
below) are the artifact formerly serialized as the "supervised V2" body; where
the prose that follows says "supervised V2" it means this supervised-graph
payload. Phases `237`–`239` will later replace that embedded `SupervisedRuntime`
program with the trained `LayerGraph` itself.

The supervised V2 body carries the complete executable program returned by
training: runtime family and task, exact input/output transforms, ordered
layers and their attributes and representation transitions, authoritative
canonical supervised-row identity, and one member of the closed runtime-origin
sum:

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

There is no unspecified/default origin and no origin coercion. The addressed V2
body's composite origin—canonical row identity plus either the authoritative
projection or exact generic execution transport—binds the canonical row
semantics; `PlanId` alone never does. The canonical row owns the runtime family,
task, production dimensions, topology, transforms, decoder, convergence
criterion, and canonical dataset-read digest. The origin owns which exact plan,
budget, seed, substrate, and experiment may be bound to those semantics.
The supervised descriptor's finite-positive learning rate is part of semantic
`PlanId`: `3e-3` for `fashion-mnist-resnet`, `1.1e-3` for
`cifar10-resnet20`, `1.5e-3` for `cifar10-vit`, and `1e-3` for the other eight
supervised rows. The manifest architecture, preprocessing, output decoder,
physical tensor, and weight layout are derived from that same refined payload.
For classification, labels are deterministic `class-0` through the row's
semantic class width. California Housing declares regression output units
`median-house-value` and persists the fitted feature transform plus target
inverse-transform.

Every supervised V2 checkpoint contains exactly one physical tensor,
`supervised.weights`, whose bytes are one canonical JMW1 vector. Parameterized
layers contribute `W1`, `b1`, `W2`, and `b2` virtual slices in graph order.
Offsets and element lengths are not serialized: refinement derives them as
checked prefix sums of the persisted shapes, proves complete non-overlapping
coverage of the physical vector, and exposes them as `FlatWeightLayout`
metadata. New supervised writes therefore emit neither name-derived generic
manifests nor per-node physical weight objects.

The retained `LayerGraphMetadata`/`NamedTensorWeightLayout` decoder remains for
older non-V2 manifests. It is not the supervised V2 representation. Later
Sprint `23.1` still owns removal of the parallel decorative layer-graph versus
executable layer/state paths in the general training engine; V2 records and
strictly replays the exact supervised runtime program currently returned by
training without claiming that later graph unification is already complete.

The origin field is a required V2 body field, not a compatibility default.
Adding it changes the exact canonical body, outer envelope, and object address,
while frozen V1 bytes and their decoder remain unchanged. Every supervised V2
manifest and pointer produced before this closed-origin contract must therefore
be republished from current source; a loader must not guess an origin for old V2
bytes or retain a pointer to them as an eligible artifact.

Both origins also close dataset provenance against the canonical pinned read
contract. `canonicalDatasetReadShaForProblem` derives the deterministic digest
of the exact pinned training and evaluation artifacts for the canonical row;
the runtime payload, manifest `datasetShaAtRead`, and `CompletedTraining` must
all equal that digest. Synchronously substituting the same forged digest into
all three fields is therefore rejected for both Product and generic V2.

## Inference Eligibility

A checkpoint manifest can be loaded for inspection at any step, but only a
Store-minted `AdmittedCompletedCheckpoint` may flow to `jitml eval`, `jitml
inference run`, demo inference routes, RL evaluation/rollout, or AlphaZero game
endpoints. Admission first establishes one exact persisted snapshot; structural
completion validation then requires all of the following:

- the raw completion payload refines into opaque `CompletedTraining`, including
  its exact unit-indexed budget and originating `PlanId`;
- the manifest carries that same `PlanId`, and a supervised V2 payload
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
- a supervised manifest contains the exact refined V2 runtime, one physical
  `supervised.weights` tensor, and the graph-derived `FlatWeightLayout`; any
  supervised V1, including a historical `GenericModelFamily` ProductRow
  snapshot, fails as inspection-only;
- a completed V1 manifest resolves to one canonical non-supervised ProductRow,
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
starts after that stability interval. Store then verifies every declared
physical object key, exact fetched bytes, byte length and content SHA, canonical
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
eligible V2 checkpoint is written and no completed-checkpoint event is emitted.
When the same exact generic plan passes that bar, its V2 may become inference
eligible after the ordinary checks above, but its generic origin and non-product
experiment identity remain intact and cannot satisfy ProductRow report
admission. See [Product Completion Contract](product_completion_contract.md#type-state-dsl-contract).

Decoder-only support for older V1/legacy manifests preserves inspection/resume
behavior.
The legacy stored verdict is recomputed from a typed finite criterion and
checked for contradiction, then discarded. Because the legacy wire has no
canonical `PlanId`, its completion payload is stripped from the returned domain
manifest; it cannot become inference eligible. Supervised V1 with a later
`PlanId` or completion witness is also rejected because it lacks the exact V2
runtime payload. The only V1 completion exception is the canonical
non-supervised ProductRow scope above; admission still requires its exact
persisted manifest, completion, final JMW1 bytes, and companion artifact bytes.

The browser checkpoint-list selector uses the same Store admission boundary:
it admits each known manifest address and requires an admitted completion before
emitting an eligible `CheckpointSummary`. Incomplete or physically invalid
manifests remain inspectable by lower-level tooling but are omitted from model
selection. When no eligible rows remain, the daemon emits
`selector-state: fail-closed:no-inference-eligible-artifact` in the
`CheckpointList` frame and the browser renders that state instead of
substituting a seeded or synthetic artifact.

## No-Caveat Checkpoint Target

Strict V2 currently owns the runtime families of the eleven authoritative
canonical supervised rows: Dense, DeepDense, Conv2D/LeNet, residual,
wide-residual, ResNet-50, VisionTransformer, and California regression. Both
authoritative ProductRow publication and exact generic supervised commands use
that V2 format through their distinct closed origins. RL policies, AlphaZero
policy/value nets, tuning trial checkpoints, and other non-supervised generic
artifacts retain their V1 compatibility writers and separately owned runtime
contracts; the Product writer persists the companion evidence first and binds
its exact content-addressed pointer into the completed V1 manifest. They cannot
be mislabeled as supervised V2. Across those families,
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
    blobs/<sha256>                        -- write-once, content-addressed, opaque bytes
    artifacts/<kind>/<sha256>.txt         -- write-once Product companion evidence
    manifests/<sha256>                    -- write-once, content-addressed, CBOR manifest objects
    pointers/
      latest                              -- mutable, ETag-CAS; body = 64-byte lowercase SHA-256 text
      best/<metric>                       -- mutable, ETag-CAS; body = 64-byte lowercase SHA-256 text
      trial/<trial-hash>/latest           -- per-HPO-trial latest pointer
      trial/<trial-hash>/best/<metric>    -- per-HPO-trial best pointer
```

`experiment-hash = sha256(resolved-dhall || substrate-fingerprint)`.
For V1, `manifest-sha = sha256(exact V1 envelope bytes)`. For V2,
`manifest-sha = sha256(exact V2 outer-envelope bytes)` and the outer envelope
independently carries `sha256(exact canonical body bytes)`. Neither identity is
defined as decode-and-re-encode equivalence.

Current local helpers cover `deriveExperimentHash`, `blobKey`, `manifestKey`,
`latestPointerKey`, `bestPointerKey`, `trialPointerKey`, deterministic
`encodeManifestCbor` / `decodeManifestCbor` / `manifestContentSha`, typed
`AdvancePredicate`, pure `applyPointerWrite` CAS decisions,
and the explicitly structural `validateCheckpointCompletion` refinement.
`JitML.Checkpoint.Store` provides the local filesystem-backed interpreter for
write-once object writes, manifest writes/reads, latest-pointer CAS, retention
planning, local manifest discovery for `jitml internal gc`, GC execution
through `HasMinIO`, separate candidate/completed checkpoint transactions, and
the exact persisted-admission inference loaders. The Product V1 writer resolves
each supplied companion pointer from this same object store before writing the
manifest, and known-address re-admission checks that the returned stored
manifest key/SHA and admitted SHA are identical. A `StoredCheckpoint` exposes the
exact outer SHA and `storedManifestBodySha :: Maybe Text`: V2 writes return the
embedded-body identity and V1/legacy writes return `Nothing`. This write result
is useful identity evidence but is not persisted admission. Only
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
`HasMinIO` interpreter; 2026-05-19 live Linux CPU validation confirms
`If-None-Match: *` duplicate writes and stale `If-Match` pointer CAS surface as
`SEConflict` through the routed `/minio/s3` edge. Both local and MinIO object
writers follow a collision with an exact byte comparison: identical bytes are
idempotent; different or unreadable bytes are a typed conflict.

The checkpoint write/read paths cross the `HasMinIO` capability boundary
through the distinct candidate/completed writers and Store admission. The
supervised path uses
`writeLocalCompletedSupervisedCheckpoint` /
`writeMinIOCompletedSupervisedCheckpoint`; both require non-optional completion
plus a refined `TrainingRuntimeArtifact`. Generic V1 writers remain for
non-supervised compatibility and fail closed for authoritative supervised
requests. A daemon-dispatched worker with mounted `BootConfig` resolves the
in-cluster MinIO service and invokes the MinIO completed-supervised writer
directly before publishing its completed-checkpoint event; it does not write a
host-local checkpoint mirror and then pretend that path is cluster durability.
Host-side commands without the mounted service context retain their separately
resolved local/edge path. Later workload layers do not invent parallel
supervised persistence paths around this boundary.

Completed publication has a stricter commit prerequisite than candidate
persistence. The local writer reads the current latest-pointer expectation;
mounted and Apple-host MinIO writers read the current pointer ETag and pass that
exact expectation into the CAS. The completed Store writer returns
`StoredCompletedCheckpoint` only for `PointerWritten manifestSha` where
`manifestSha` is the exact stored manifest address. `PointerConflict`, or
acknowledgement of another manifest, is a typed failure. Only after that exact
completed result may the worker or host publisher construct and publish the
completed-checkpoint event.

## Four Object Classes, Two Write Protocols

### `blobs/<sha256>` — Write-Once Content-Addressed Payloads

Each blob's key *is* `sha256(its bytes)`. PUTs use `If-None-Match: *` or the
atomic local-filesystem equivalent. A collision is followed by an exact byte
comparison in both interpreters. Only absent or byte-identical content
succeeds; unreadable, address-mismatched, or different existing content is a
typed hard conflict. A `412` or pre-existing pathname alone is never proof of
equality.

One checkpoint produces one blob per checkpoint part: weights, optimizer
state, RNG state, and, for RL workloads, replay buffer and exploration
cache. Part-level content addressing makes unchanged state deduplicate
automatically across consecutive checkpoints.

### `artifacts/<kind>/<sha256>.txt` — Write-Once Companion Evidence

The Product publisher writes the exact RL trajectory, AlphaZero self-play
transcript, or tuning-v2 trial transcript before it writes the corresponding
non-supervised V1 checkpoint. The receipt fixes the artifact kind, canonical
`jitml-checkpoints/<experiment>/artifacts/<kind>/<sha>.txt` key, and SHA.
The checkpoint manifest carries that receipt as an `ArtifactPointer`, and
Store fetches the named object and verifies its exact bytes against the pointer
SHA before completed admission succeeds. Publisher batch validation separately
requires the canonical key form and exactly one family-appropriate pointer for
every non-supervised ProductRow.

The `tune-trials-v2` text payload additionally binds the projected `row-id`,
semantic `plan-id`, experiment hash, dataset-at-read SHA, best trial's final
JMW1 SHA, and the exact ordered contiguous trial executions. Construction
requires one and only one promoted execution equal to the selected best trial,
finite hyperparameters/objectives/observations/weights, completed trial and
update counts equal to the observed execution, and exactly one
`best_objective` completion measurement equal to that best trial.

### `manifests/<sha256>` — Write-Once Content-Addressed CBOR Manifests

Each manifest names the blob SHAs that constitute one logical checkpoint plus
the metadata needed to interpret them. V2 additionally embeds the exact
supervised runtime body and independently identifies it. Manifest objects use
the same absent-or-byte-identical write-once protocol.

The manifest's SHA is the canonical *checkpoint id* used by candidate and
completed checkpoint events, RPC envelopes, and `--resume <checkpoint-id>`.

### `pointers/*` — The Only Mutable Objects

Each pointer's body is a manifest SHA. Updates use S3 conditional PUT with
`If-Match: <etag>` compare-and-swap. The
`pointers/latest` update is the **single atomic commit point** for a
checkpoint: part-level blob writes can happen in any order and may even
leave orphans on failure, but the manifest is only adopted as HEAD when its
pointer update succeeds. ETags are writer-CAS tokens, not reader snapshot
identity. Candidate writers do not update `latest` and return only
`StoredCandidateCheckpoint`. Completed writers require non-optional
`CompletedTraining`, perform exact CAS, and return `StoredCompletedCheckpoint`
only when the pointer adopts that exact manifest address; a stale expectation
is a typed conflict and cannot be relabelled as completed persistence.

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

For supervised V2, this one flat vector is the complete physical parameter
payload. Tensor names, shapes, layer association, and derived offsets live in
the V2 runtime/manifest binding; they are not duplicated inside JMW1. The
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
`manifestContentSha` hashes the exact encoded outer bytes. V2 preserves graph
order for `FlatWeightLayout` instead of name-sorting the virtual slices.
Persisted admission requires every replay/transcript `ArtifactPointer` to carry
an exact SHA and rejects duplicate physical keys. For Product publication,
supervised V2 has no companion pointer; each RL V1 row has one
`rl-trajectory`, each AlphaZero V1 row one `alphazero-transcript`, and the
tuning V1 row one `tune-trials` pointer.

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
For supervised V2 rows, `manifestDatasetShaAtRead` is the observed digest
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
for both miss assessment and passing V2 construction.

`TrainingMetrics` additionally carries one mandatory
`tmParityProbeInput`/`tmParityProbeOutput` pair produced immediately by the
training-returned model. Classifier rows use an exact held-out example and its
semantic numerical model output; California Housing uses an exact raw held-out
feature row and the prediction after the persisted target inverse-transform.
The pair is finite and dimension-checked against the refined runtime. It lets
the production parity gate compare the Store-loaded V2 program with the model
that actually trained, without reconstructing a model, inventing an input, or
using a codec-only round trip as execution evidence.

## Concurrency Model

Trainer/reader races are removed at the object protocol layer. MinIO uses
conditional object operations; the local interpreter uses atomic hard-link
publication for immutable objects and a POSIX advisory lock across each exact
pointer read/compare/atomic-rename interval. No lease or separate lock service
is required.

| Hazard | Boundary |
|--------|----------|
| Write/write on `blobs/*` and `manifests/*` | Keys are content-addressed; MinIO PUT uses `If-None-Match: *`; local publication is atomic. Every interpreter accepts a pre-existing object only after exact byte comparison. |
| Write/read on `blobs/*` and `manifests/*` | Object publication is atomic, and exact address/length/content checks reject a torn or substituted object. Store binds every physical declaration before admission succeeds. |
| Write/write on `pointers/*` | MinIO `If-Match: <etag>` and the locked local compare/rename interval are exact writer CAS operations. A losing completed writer receives a typed conflict and no completed result. |
| Write/read on `pointers/*` | Store reads exact body `P1`, verifies the addressed manifest, reads exact body `P2`, and starts blob binding only when the bodies match. ETag equality is deliberately irrelevant to reader stability. |

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
interpreters. The separate candidate/completed transactions apply
`HasMinIO.putBlobBytesIfAbsent` and `HasMinIO.casPointer` through the live HTTP
implementation in `JitML.Service.MinIOSubprocess` or the exact filesystem
equivalent.

## Retention and GC

Target retention (`retain = Checkpoint.Retention.LastN k` in the experiment
Dhall) is enforced by a reconciler — `jitml internal gc <experiment-hash>` —
invoked by the trainer at training-end. Per doctrine `Reconcilers`,
re-running `gc` on a steady-state experiment is a no-op (exit code `3`).

- **Live set.** The reconciler reads `pointers/latest`, every
  `pointers/best/<metric>` for the metrics declared in the experiment Dhall,
  every `pointers/trial/<trial-hash>/*` reachable from the experiment, and
  follows `cmParentManifest` along the lineage chain from those tips. The
  transitive closure is the live set.
- **`LastN k` semantics.** `LastN k` keeps the `k` most-recent manifests on
  the `latest` chain (by `cmStep`). `pointers/best/<m>` target manifests are
  always live regardless of `LastN`.
- **Blob GC.** A blob is reapable iff no live manifest references it.
  A supervised V2 manifest roots its one physical `supervised.weights` object;
  derived virtual slices are neither objects nor independent GC roots.
- **Audit trail.** GC emits a structured `gc_reaped` event per doctrine
  `At-Least-Once Event Processing`, naming every reaped manifest and blob
  SHA so the audit trail survives the deletion.

The current store exposes `RetentionPolicy{KeepAll,LastN}`, `walkLiveSet`,
`applyRetentionPolicy`, `buildGcPlan`, `listCheckpointManifests`,
`listCheckpointManifestsMinIO`, and `executeGcPlan` over the typed
`HasMinIO` boundary. The current `jitml internal gc <experiment-hash>`
detects the live cluster publication
(`./.build/runtime/cluster-publication.json`) and routes the live half
through `listCheckpointManifestsMinIO + buildGcPlan + executeGcPlan` via
`JitML.Service.MinIOSubprocess`; the offline half scans
`<cache-dir>/checkpoints/jitml-checkpoints/<experiment-hash>/manifests/`.
Unsafe offline experiment-hash-derived prefixes fail as typed validation before
filesystem path construction and render through `InvalidConfig`.
The stdout reports
`gc: <experiment-hash> kept=<n> reaped=<n> reaped-blobs=<n>` (live) or
`gc: <experiment-hash> kept=<n> reaped=<n>` (offline) and exits `3`
when the plan is a no-op.

After the live reaper completes, `JitML.App.publishGcReapedEvents`
publishes a `GcReapedEvent` envelope on
`persistent://public/default/gc.event.<substrate>` for each successfully
reaped manifest. The envelope carries `experiment_hash`, `manifest_sha`,
the addressed `reaped_blob_shas`, the reaped manifest's `step_at_reap`,
the live `substrate`, and the reap `timestamp_ns`; text + proto3 codecs
live in `JitML.Proto.Gc`. Publication failures surface a stderr line
but do not roll back the MinIO delete and do not short-circuit the
reconciler — at-least-once handles the missed event on a subsequent
run.

## Inference-Only Read Path

`loadInferenceCheckpointWithWeights` calls Store's stable latest admission,
requires an admitted completion, and invokes an explicit runner with the exact
bound weight payloads. `loadInferenceCheckpointDecodedWithWeights` applies the
manifest-bound decoder after that runner. A caller which already holds a known
address uses `admitCheckpointAt` followed by
`requireAdmittedCompletedCheckpoint`; this performs the same exact immutable
manifest/blob binding without a pointer lookup.

For supervised V2, `loadSupervisedRuntimeFromCheckpoint` accepts only one
`supervised.weights` object, verifies its flat shape and exact bytes, derives
all graph-order parameter slices, and constructs an executable solely from the
persisted runtime. A recognized V2 cannot fall back to a legacy layer graph,
Dense/MLP shortcut, demo topology, caller-supplied model, pure/reference
engine, or another substrate. The loader resolves the closed origin first,
reconstructs its exact bound plan, and validates that plan's substrate rather
than assuming every supervised V2 is a ProductRow publication. Unsupported
operations, shapes, transforms, decoders, origins, and substrate/`PlanId`
combinations fail with typed text before a result is returned. Historical V1
remains on the isolated compatibility path and supervised V1 fails before
execution.

The current `cifar10-vit` V2 body contract is intentionally exact about the
executable that exists now. Its `RawStandardizeInput` carries RGB means and
positive scales
fitted from the raw training partition only and repeated in pixel-major order
across all 3,072 inputs; validation and test values cannot influence those
statistics, and loaded inference applies the transform to the retained raw
`[0,1]` probe. The body then records input geometry `32×32×3`, patch
size/stride `4/4`, a patch-projection MLP with 50 inputs, and token-mixing count
`64`, followed by the executed LayerNorm, 64→128→64 token-mixing MLP,
LayerNorm, 128-wide single-head attention/QKV MLP, mean pool, and 128-wide
classifier. Its one physical `supervised.weights` vector contains **123,595**
values; graph-order slice ends are **23,040**, **39,616**, **105,664**, and
**123,595**, so refinement proves exact cover without persisted offsets. A V2
artifact with the older 16×16/four-token, 8×8/16-token, or unit-image
4×4/64-token contract is not equal to this current canonical runtime. Fresh
publication also uses the supervised descriptor's exact
finite-positive learning rate as part of semantic `PlanId` identity: `3e-3`
for `fashion-mnist-resnet`, `1.1e-3` for `cifar10-resnet20`, `1.5e-3` for
`cifar10-vit`, and `1e-3` for the other eight rows. Its exact plan fixes
**2,000** training examples, five epochs, batch size 128, **10,000** processed
examples, and **80** successful optimizer updates. This byte-exact Mixer
persistence does not satisfy Blocked
Sprint `23.1`'s single typed graph or Blocked Sprint `24.1`'s literal small-ViT
topology. Measured chronology and validation evidence live in Sprint `10.6`.

Boxed-vector constant-time indexing in attention backward and immediate
per-layer tape projection in `forwardOnly` do not change this persisted runtime
or its parameter order. `forwardOnly` may transiently construct the current
layer's tape through `forwardLayer`, but it never accumulates those tapes across
the graph. Neither execution correction is a new checkpoint field.

`RuntimeBackendExecutor` makes the selected engine's complete operation surface
explicit: input transform, output transform, MLP, residual add, LayerNorm,
token mixing, patch extraction, attention, and mean pooling are mandatory
callbacks. Linux CPU renders a content-addressed `kernel.cc`, and Linux CUDA
renders a content-addressed `kernel.cu`; both implement version `1` of the
status-returning `double`-buffer runtime-operation C ABI. Before dispatch, the
loader compiles and loads the selected artifact, resolves the ABI-version and
capability probes plus the required operation symbols, and requires capability
mask `0xff`. The eight capability bits cover input transform, output transform,
residual add, LayerNorm, token mixing, patch extraction, attention, and mean
pooling. Token mixing uses native pack/merge around the selected MLP callback;
the merge replaces the token input with the mixed result. Attention uses that
same selected MLP for QKV projection and native scaled-softmax attended-value
assembly. Only `RawResidualLayer` adds a skip. Those are the frozen pre-Sprint-
`23.1` V2 equations; the deferred Sprint `23.1` residual corrections require
distinguishable operation/version metadata and cannot reinterpret existing V2
bytes.

Apple Silicon renders content-addressed `.metal.json` metadata containing the
generated MSL, ABI version `1`, capability mask `0xff`, all nine operation
symbols (token mixing has separate pack and merge symbols), and fast-math-off
compile metadata. `JitML.Engines.RuntimeOperationsMetal` checks the metadata
contract, exact fp32-representability for integer arguments, finite/range/shape
preconditions, and output shape before dispatching through the fixed bridge.
The bridge performs explicit `Double`↔fp32 transport and compiles with
`MTLDevice.makeLibrary(source:options:)` on the visible Metal device. Metal
does not pretend to provide fp64 execution.

Parameterized MLP calls remain the selected real oneDNN, CUDA, or fixed-bridge
Metal implementation. Structural operations do not call
`RuntimeOperations.host*` in any selected production engine. Compile, load,
symbol, ABI, capability, contract, native-status, dispatch/execution, and
nested selected-backend MLP failures remain typed and fail closed; none selects
a host/reference operation or another substrate.

V2 trained-versus-Store numerical parity has an explicit substrate-local
precision policy, encoded by `sameSubstrateV2Tolerance` in
`test/sl-canonicals/Main.hs`. The `linux-cpu` and `linux-cuda` structural ABIs
compute in `double`, so their maximum absolute output difference must be at
most `1e-9`. Apple Metal computes in fp32 through the fixed bridge, so its
declared bound is `1e-5`. These are within-substrate bounds, not
cross-substrate equivalence.
Sprint `10.6` closes only on `linux-cpu`; the real Apple hardware retest and any
evidence-driven adjustment of the fp32 bound belong to the downstream
`apple-silicon` product lane and are not claimed here.

The pointer-selected loader reads `P1`, verifies the exact addressed manifest,
reads `P2`, and only then fetches and binds physical payloads. A changed exact
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
`CheckpointDone` payloads into that sidecar writer before ack. Live Linux CPU
validation on 2026-05-19 also writes a marker through
`JitML.Service.MinIOSubprocess` and confirms MinIO stores the CBOR object.

## Bit-Determinism

Target same-substrate same-toolchain reproduction of a checkpoint produces a
byte-identical `.jmw1` payload and a byte-identical manifest SHA. Cross-substrate
bit-equality is **not** guaranteed and not asserted (RNG draws + float reduction
order differ across substrates) per
[determinism_contract.md → The Contract](determinism_contract.md#the-contract).
The V2 numerical bounds above compare a training-returned model output with its
Store-loaded execution; they do not relax byte identity for the persisted
weights or manifest.

## Cross-References

- [../../README.md → Checkpointing](../../README.md#checkpointing)
- [../../README.md → Concurrency model](../../README.md#concurrency-model)
- [determinism_contract.md](determinism_contract.md)
- [training_workloads.md](training_workloads.md)
- [run_contract.md](run_contract.md)
- [../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md](../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md)
- [../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md](../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md)
- [../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md](../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md)
