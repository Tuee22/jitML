# Training Workloads

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-1-haskell-cli-surface.md, ../../DEVELOPMENT_PLAN/phase-8-supervised-and-rl-framework.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-13-no-caveat-model-runtime.md, ../../DEVELOPMENT_PLAN/phase-14-interactive-demo-and-playwright-closure.md, ../../DEVELOPMENT_PLAN/phase-18-no-caveat-product-handoff.md, ../../DEVELOPMENT_PLAN/phase-19-product-truth-gates.md, ../../DEVELOPMENT_PLAN/phase-22-canonical-matrix-and-dataset-integrity.md, ../../DEVELOPMENT_PLAN/phase-24-real-supervised-architectures.md, ../../DEVELOPMENT_PLAN/phase-25-real-rl-algorithms-and-environments.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md, ../../DEVELOPMENT_PLAN/phase-272-apple-integration-e2e-and-attestation.md, product_completion_contract.md, checkpoint_format.md, numerical_core.md, training_metrics_and_splits.md, run_contract.md
**Generated sections**: training.rl.catalog, training.tune.samplers, training.tune.schedulers, training.tune.pruners

> **Purpose**: Project-specific training-workload doctrine for jitML — the
> current local SL summaries, RL metadata/framework surfaces, AlphaZero game
> helpers, and hyperparameter tuning catalogs, plus the no-caveat runtime
> surface for real train/eval/rollout/self-play/tune/checkpoint/inference
> workflows.

Phase order, implementation status, blockers, and validation evidence live only
in the [Development Plan](../../DEVELOPMENT_PLAN/README.md). This document owns
workload-specific algorithms, environments, catalogs, and metric production.
The shared raw-plan, dimensional-budget, protocol, completion-evidence, and
live-interpreter boundary is
[Typed Run Contract](run_contract.md); the row-completion bar is
[Product Completion Contract](product_completion_contract.md).

Every product workload must project its verified data, measured update counters,
finite convergence measurements, terminal checkpoint, and domain-specific
artifacts into opaque `CompletedRunEvidence`. Reportable Product completion
also requires Store's opaque `AdmittedCompletedCheckpoint` for the exact
persisted manifest, snapshot commit/descriptor, and scoped payload-object graph.
A primitive budget record,
declared metric, write receipt, caller-held completion, checkpoint pointer, or
browser event cannot independently mint completion or inference eligibility.

## Current Status

**Implemented today.** Supervised training, checkpointing, and serving use one
finite-difference-validated typed `LayerGraph` IR. The literal Phase `242`–`244`
graphs execute the Phase `241` device kernels on `linux-cpu` — spatial
convolution, affine normalization, GeGLU, multi-head attention with `W_O`, and
residual composition. Those are the only layer-graph device kernels that exist:
on `linux-cuda` and `apple-silicon` the same graphs execute these oneDNN kernels
for training and the pure host executor for serving. Phases `264` and `270` own
the per-lane kernels. The trained graph and its graph-ordered parameter vector enter the
single checkpoint envelope and the Store-reloaded inference path. The former
`[LayerSpec]` / `[LayerState]` executable and the served-operation ABI once
embedded in the supervised payload are historical only. `LayerSpec` and
`LayerState` remain as a Dense-family initialization adapter; they are not a
parallel training or serving executor.

## SL Training Loops

`src/JitML/SL/` owns the supervised-learning surface. The current worktree has
the canonical problem catalog and all-row trainable product cohort in
`src/JitML/SL/Canonicals.hs`, typed dataset references in
`src/JitML/SL/Dataset.hs`, the bounded classifier/data helpers in
`src/JitML/SL/Classifier.hs`, and the all-row substrate-backed architecture
runtime in `src/JitML/SL/Architecture.hs`. `archLayerGraph` is the literal graph
that training updates, completion carries, the checkpoint writer persists, and
Store-admitted inference reloads. The oneDNN path trains its typed operators
through the Phase `241` device kernels. The former `[LayerSpec]` / `[LayerState]`
execution path and parallel descriptive graph were retired by Phases `238` and
`244`; those types now only seed the Dense-family graph adapter.

- Current `Dataset.hs` renders pinned dataset object keys, maps them to bucket
  `jitml-datasets`, exposes `fetchDatasetRef` and
  `fetchVerifiedDatasetArtifactBytes` through the `HasMinIO` capability, and
  verifies fetched bytes against the pinned SHA-256 at the product read
  boundary. The filesystem-backed `HasMinIO` test covers the capability
  boundary; live routed MinIO fetch covers every canonical dataset/model row in
  the fixed-budget `linux-cpu` baseline.

### Canonical SL Problems

The catalog names the no-caveat architecture set. Each supervised row's claimed
`ArchitectureFeature` values in `ProductRow.rowArchitectureFeatures` are checked
against the literal `archLayerGraph`; a simplified or mislabeled topology fails
the production-path test. The same trained graph crosses completion, checkpoint
admission, reload, and inference, so a decorative feature graph cannot satisfy a
row.

The current ResNet family — `fashion-mnist-resnet`,
`cifar10-resnet20`, `cifar10-resnet56`, `cifar100-wide-resnet`, and
`tiny-imagenet-resnet50` rows are now literal mixer-ResNet layer graphs — real
`Conv2D` behind a two-conv strided stem, `BatchNorm`/`GroupNorm`, `LayerNorm`,
residual BasicBlock/Bottleneck blocks, attention, and GeGLU — trained as compact
proxies under the bounded product budget; the 2-D convolution forward is a tight
unboxed kernel.

| Current problem key | Owning module | Current literal and trained architecture |
|---------------------|---------------|------------------------------------------|
| `mnist-shallow-mlp` | `src/JitML/SL/Architecture.hs` | Dense classifier graph; trained graph publication and Store-reloaded parity are enforced. |
| `mnist-deep-mlp` | `src/JitML/SL/Architecture.hs` | Two-hidden-layer Dense graph with two real BatchNorm and two Dropout nodes. |
| `mnist-lenet` | `src/JitML/SL/Architecture.hs` | LeNet-style graph with two real Conv2D stages, pooling, and a classifier. |
| `fashion-mnist-mlp` | `src/JitML/SL/Architecture.hs` | Dense classifier graph over the verified Fashion-MNIST split. |
| `fashion-mnist-resnet` | `src/JitML/SL/Architecture.hs` | Compact mixer-ResNet graph with a two-conv spatial stem, BatchNorm, two BasicBlocks, LayerNorm, attention, and GeGLU. |
| `cifar10-resnet20` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Row-specific compact mixer-ResNet graph with real convolution, BatchNorm, two BasicBlocks, LayerNorm, attention, and GeGLU. |
| `cifar10-resnet56` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Row-specific compact mixer-ResNet graph with real convolution, BatchNorm, two BasicBlocks, LayerNorm, attention, and GeGLU. |
| `cifar100-wide-resnet` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Wide compact mixer-ResNet graph with real convolution, GroupNorm, two BasicBlocks, LayerNorm, attention, and GeGLU. |
| `cifar10-vit` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs` | Literal 8×8-patch/16-token ViT graph with affine LayerNorm, two-head attention with `W_O`, and GeGLU. |
| `tiny-imagenet-resnet50` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/TinyImageNet.hs` | Distinct compact bottleneck mixer-ResNet graph with a two-conv spatial stem, BatchNorm, two BottleneckBlocks, LayerNorm, attention, and GeGLU. |
| `california-housing-mlp` | `src/JitML/SL/Architecture.hs`, `src/JitML/SL/Archive.hs`, `src/JitML/SL/Regression.hs` | Dense regression graph with train-only fitted standardization and inverse-transformed output. |

Convergence is accepted only where the test performs the row's declared fixed
budget, verifies dataset bytes at the product read boundary, proves learned
state changed from initialization, and produces a `CompletedTraining` witness.
No per-substrate `.txt` loss-curve fixtures are committed — see
[unit_testing_policy.md → Snapshot Tests and the Prohibition on Numerical
Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).
All-row smoke or materialization coverage is not product closure.

### `jitml train` CLI

```
jitml train <experiment-dhall>
            [--resume <checkpoint-id>]
            [--dry-run | --plan-file <path>]
```

`jitml train` supports the Plan/Apply dry-run surface. On normal execution it
is **substrate-backed and fails closed** (Sprint 8.10): `JitML.App.runTrain`
delegates to `runDeviceMnistTraining`, which **requires** a live cluster
publication and a staged canonical dataset and otherwise exits with
`TrainingPrerequisiteUnmet` (exit 2) — printing and publishing nothing. There
is no synthetic summary and no pure-Haskell fallback: the staged dataset bytes
are decoded once through `JitML.SL.Classifier.decodeBoundedDataset`, the
experiment Dhall is resolved to a canonical row through
`JitML.Experiment.Product.loadSupervisedProblemByPath`, the row resolves to a
`JitML.SL.Architecture.ArchitectureSpec`, and
`JitML.SL.Architecture.trainArchitectureWithDevice` trains through the resolved
substrate's JIT-compiled `MlpDevice`, selected by
`mlpDeviceForSubstrate`. `jitml eval --checkpoint <id>` admits the named
immutable checkpoint address through Store, loads its exact `.jmw1` weights
only from opaque `AdmittedCompletedCheckpoint`, and runs the substrate-bound
weighted device forward; a missing pointer/manifest →
`InferenceCheckpointMissing`, and incompatible manifest experiment/content SHA
or tensor shape metadata fails closed before the runner is invoked. For a
supervised-graph payload, Store loads the one exact `supervised.weights` object,
reconstructs and refines the persisted graph, applies input/output transforms
outside it, and executes the shared pure `LayerGraph.runLayerGraph` serving
path. Weight-only payloads retain their substrate engine paths. Supervised
training returns the runtime task/transforms, trained graph metadata, and exact
initial/final JMW1 bytes. Publication derives architecture, preprocessing,
output decoder, and graph-ordered `Flat` layout metadata from those same values
and uses the mandatory supervised writer; it cannot reconstruct the artifact
from a tensor name or display-oriented weight list.

Before any worker or host effect, `JitML.Plan.Command.prepareStartTraining`
refines the raw `StartTraining` fields into hidden `SupervisedPlan`. The plan's
positive, unit-indexed budget contains epochs, training examples, evaluation
examples, batch examples, and optimizer updates; refinement requires optimizer
updates to equal `epochs * ceil(trainingExamples / batchExamples)`. The
producer attaches the canonical version-`1` transport and content-derived
`PlanId`. Consumers run `validateStartTraining`, re-refining both the command
fields and the transport and requiring semantic, canonical-byte, and identity
equality.

Linux worker mounts use plan-only `TrainingRunConfig`: `planId`,
`resolvedPlan`, and the operational Pulsar WebSocket endpoint. The worker
parses and re-refines that transport before a Job launch, dataset read,
training update, checkpoint write, or event publication. It does not receive a
second primitive budget record, clamp a quantity, or reconstruct semantics from
environment defaults. The Apple host-command route validates the same
plan-bearing `StartTraining` command rather than creating a Linux-style mount,
so direct execution, daemon-dispatched Linux Jobs, and host Metal execution all
execute the same plan.

That exact plan also determines the supervised-graph payload origin. ProductRow
publication uses `RawProductRowProjectionOrigin`. Public `jitml train` and
daemon `StartTraining` use
`RawGenericSupervisedExecutionOrigin(rowId, canonicalPlanTransport)`, embedding
the exact canonical problem-row identity and exact `SupervisedPlan` transport.
Checkpoint refinement requires the origin row, payload row, and authoritative
canonical problem/ProductRow to agree, reparses and canonicalizes the transport,
then binds its substrate, experiment, epoch/update budget, and seed. The
addressed composite origin binds those row semantics; `PlanId` alone does not.
The generic origin is not permitted to occupy a ProductRow experiment hash.
The complete wire and eligibility rules live in
[Checkpoint Format → The Self-Describing Checkpoint Envelope](checkpoint_format.md#the-self-describing-checkpoint-envelope).

Generic execution consumes the plan seed rather than merely persisting it.
`supervisedExecutionSeed` requires exactly one refined plan seed, rejects an
`Int` overflow, and passes that seed into classifier/regression initialization
and deterministic classification epoch permutation; the canonical problem's
default seed is not substituted. For local generic execution, the experiment
address combines the selected Dhall path with a fingerprint of canonical row,
dataset, model, substrate, seed, epoch budget, training/evaluation example
budgets, and batch budget (which fixes the derived optimizer-update budget).
Changing any one of those execution inputs changes experiment and `PlanId`
identity.

When a daemon-dispatched Linux worker has mounted `BootConfig`, it resolves the
mounted in-cluster MinIO service and writes a passing completed
supervised-graph payload directly to MinIO before emitting the
completed-checkpoint event. It does not route that durable write through a
host-local mirror. Host-side developer execution without mounted services keeps
its separately resolved local/edge path. Before the MinIO CAS, the worker reads
the current latest-pointer ETag and passes that exact `Maybe ETag` as its
expectation. Publication proceeds only when Store returns `PointerWritten` for
the exact stored manifest; conflict or another manifest acknowledgement is a
typed failure and emits no completed-checkpoint event. The Apple host path
enforces the same order.

The worker fetches `jitml-datasets/MNIST/{train,test}/{data,labels}.bin`
through `JitML.SL.Dataset.fetchVerifiedDatasetArtifactBytes`, verifies the
canonical SHA-256 for each image/label object, then gunzips
(`JitML.SL.Dataset.maybeGunzip`), IDX-parses, and trains over the verified
bytes. Corrupt, substituted, truncated, or unpinned payloads fail closed as a
typed service error before decode. Example, epoch, and evaluation quantities
enter through the raw Dhall request and must refine to positive unit-indexed
values in the resolved `RunPlan`; the worker neither clamps them nor recovers
them from environment variables. Phase `5` Sprint `5.7` retired the former
`JITML_SL_TRAIN_LIMIT` / `JITML_SL_EPOCHS` / `JITML_SL_TEST_LIMIT` env IPC in
favour of the mounted run input per the `Application Environment` doctrine.
Sprint `5.17` keeps that mount fail-closed: a present but malformed
`/etc/jitml/run/RunConfig.dhall` exits as a typed configuration error instead of
falling back to env/default caps. The measured `train_acc` / `test_acc` are
reported and the published `EpochCompleted` loss becomes the live measurement.
The `jitml-sl-canonicals` live MNIST assertion exercises the same
architecture/device runtime when the publication and staged bytes exist, so the
test does not certify a separate Dense-only path. Image + label blobs are
staged via `jitml internal upload-dataset --name MNIST --split <split>
--artifact {images,labels} --path <gz>`, SHA-verified against
`JitML.SL.Dataset.canonicalArtifactSha256For` on upload and again on read.
There is no lazy first-use download or population path: absent canonical objects
fail closed before training. On Linux, the outer Compose service mounts the
repository but not arbitrary host paths, so a blob under host `/tmp` must be
exposed explicitly (for example, `docker compose run --rm --volume
/tmp/jitml-datasets:/datasets:ro jitml ...`) and `--path` must use its
container-visible `/datasets/...` name.
Fashion-MNIST has the same train/test image+label gzip SHA-pinned surface.
CIFAR-10 and CIFAR-100 use `ArchiveArtifact` pins for the canonical Toronto
binary tarballs, staged with `--artifact archive`, verified on read, and parsed
by `JitML.SL.Classifier` from extracted CIFAR binary batch payloads into
3072-feature labeled examples through the shared `JitML.SL.Archive` tar
extractor. The parser transposes the archive's three channel-major 32x32 planes
into pixel-major interleaved RGB, which is the tensor layout consumed by
architecture patch extraction. California Housing uses an `ArchiveArtifact`
pin for `cal_housing.tgz`; after read-time verification,
`JitML.SL.Regression` parses `CaliforniaHousing/cal_housing.data` into
eight-feature rows with the raw target value. Execution splits those raw rows
into the exact training and held-out partitions first.
`RegressionStandardization` then fits feature means/scales and target
mean/scale from the raw training partition only and applies that one hidden,
refined transform unchanged to both partitions. The persisted runtime uses the
same feature transform at inference and inverse-transforms its one regression
output into declared `median-house-value` units; held-out and inference values
never influence fitted statistics. Tiny ImageNet uses `JuicyPixels` plus a
narrow Zip64-aware central-directory reader to decode JPEG tensors from the
verified pinned archive.
`jitml train` routes staged CIFAR, Tiny ImageNet, and California archives
through these archive-backed decoders before training. Canonical classification
execution then permutes only the complete materialized training partition once
per one-based epoch. Epoch `e` draws exactly `length trainSet` words from
`splitMixWords` seeded by
`deriveSplitMixSeed (SplitMixSeed (fromIntegral clfSeed)) (fromIntegral e)`,
zips each whole labeled example with its word and original zero-based index,
and stable-sorts ascending exactly on `(word, originalIndex)`. Validation and
test partitions remain in their fixed decoded order. The permutation retains
every training example exactly once, so authoritative example and batch
quantities, mini-batch sizes/counts, `tmExamplesProcessed`, and the
trainer-observed successful optimizer-update count are unchanged. The tuning
exact-update trainer deliberately retains its fixed-order cyclic batch path;
canonical ProductRow ordering does not redefine trial/rung replay.

Every successful ProductRow supervised execution returns required
`tmSupervisedRuntimeProgram` task/input/output-transform metadata,
`tmTrainedLayerGraphMetadata`, exact `tmInitialJmw1Bytes`, exact
`tmFinalJmw1Bytes`, and `tmVerifiedDatasetShaAtRead`; optional list/digest
projections are accepted only when they equal those exact values. The same
return value carries
`tmOptimizerUpdatesExecuted`, recorded only after all requested epoch/batch
loops succeed, plus a mandatory finite, dimension-checked
`tmParityProbeInput`/`tmParityProbeOutput` produced by the trained model on one
exact held-out input. Classifier probes retain the semantic numerical output;
California Housing retains a raw held-out feature row and the prediction after
the persisted target inverse-transform. For datasets with separate image/label
test objects, `datasetReadShaForArtifacts` covers the verified training and
held-out objects actually read, in deterministic order. Archive-backed rows
bind the exact verified archive from which the used partitions were
materialized.

Supervised-graph refinement independently derives the canonical pinned
training/evaluation read digest for that exact origin row. The training-returned
runtime payload, manifest, and `CompletedTraining` dataset fields must all equal
it; giving all three the same forged digest does not bypass Product or generic
admission.

The runtime payload identifies the authoritative canonical supervised row and
carries one closed origin. Product publication re-projects that addressed row
and `PlanId` to exactly one supported substrate. Generic supervised publication
binds its addressed origin row to the embedded canonical exact `SupervisedPlan`
transport, whose plan experiment must be non-product. The addressed row/origin
composite, not `PlanId` alone, authorizes the canonical runtime semantics. In
both cases the family, task, production input/output dimensions, exact topology,
preprocessing, decoder, completion budget, executed seed, selected substrate,
and manifest experiment must agree with that origin-bound plan. Publication
binds the completion/manifest initial and final weight hashes to the exact JMW1
bytes and the dataset digest to the
exact read-time bytes, then writes exactly one physical `supervised.weights`
JMW1 object through the non-optional completed-supervised writer. The snapshot
descriptor binds its canonical logical blob key to the exact scoped object key
and payload SHA; persisted admission reconstructs that logical address and
re-derives the snapshot id. Per-layer parameters are derived virtual slices, not
separately persisted objects.
Generic weight-only writers reject an authoritative supervised ProductRow,
supervised completion budget, or reserved supervised tensor identity. The
Product-only weight-only writer additionally accepts only a canonical
non-supervised ProductRow and binds the exact already-written
trajectory/AlphaZero/tuning companion pointer into its immutable manifest. The
Writer and Product Publisher consume the
training-returned optimizer-update count, compare it with the origin-bound
`SupervisedPlan`, and require the completion and manifest to retain the same
count. They do not derive a replacement count after training.

Generic decoded Workload mutations reject the Store-owned checkpoint
`manifests/`, `pointers/`, `snapshots/`, and `gc/` prefixes before `HasMinIO`.
Training commands therefore cannot bypass the Store writer to manufacture a
manifest, selector, reservation/commit, or GC record.

The ProductRow publisher likewise owns the metric projection. It requires the
observed processed-example count to equal
`epochs * supervisedPlanTrainingExamples` exactly and constructs exactly four
finite, uniquely named rows in canonical order: `train_loss`,
`validation_loss`, `examples_processed`, and the held-out metric named by that
row's convergence bar. A caller-supplied extra, reordered, duplicated, renamed,
or non-finite metric vector cannot become Product-origin completion evidence.
After writing, the publisher re-admits the exact stored immutable address and
requires its manifest SHA, row/experiment, `PlanId`, full completion, and
Product-origin supervised-graph payload to match before the supervised row is
eligible.

Generic supervised checkpoint construction distinguishes a structural failure
from a finite convergence miss. A finite run that completes its exact plan but
misses the canonical row's unchanged bar exits successfully as training and
writes no eligible supervised-graph checkpoint or completed-checkpoint event.
A passing run writes a generic-origin supervised-graph payload, but that origin
remains distinct from ProductRow publication and cannot enter ProductRow
reporting. Training summaries already emitted by the command are not promoted
into checkpoint proof. The legacy initial/final weight lists are optional
projections: their absence never gates the typed miss, while a supplied
projection must still equal the exact decoded JMW1 vector.

Protocol publication distinguishes
`TrainingCheckpoint CheckpointDone`, an inspectable/resumable candidate with no
proof, from `TrainingCompletedCheckpoint CompletedCheckpointDone`, whose hidden
wrapper carries mandatory, re-refined completion. Completion metrics include
train loss, validation loss, held-out metric, and examples processed. Completed
envelope bytes re-bind each convergence observation to one unique, equal-valued
manifest metric row; their TensorBoard run id equals the manifest experiment,
log prefix equals `jitml-tensorboard/<experiment>`, and ordered scalar tags
equal the completed convergence metric names. These protocol
variants are carried through a Store-level candidate/completed persistence
split. `writeLocalCandidateWeightCheckpoint` and
`writeMinIOCandidateWeightCheckpoint` return opaque
`StoredCandidateCheckpoint` and never publish the inference-selected `latest`
pointer. Before payload mutation, either writer CAS-registers its full
reservation in the experiment-scoped `ExperimentGcFence` at
`gc/coordination-fence.txt`, advances its monotonic writer/root-activity epoch,
moves overlapping planned work to `Cancelling`, and helps persist the
byte-identical immutable cancellation artifact and settle complete `Cancelled`
without deleting the semantic intent before creating its separate marker or
mutating payloads; executing/reaped overlap rejects the writer. Stable intent
and cancellation artifacts may span generations, with only the latest exact
fence phase logically active. Cleanup deletes the owned marker before
unregistering the owned entry and advancing the epoch again. A marker conflict cannot
prove ownership and therefore leaves the conflicted entry as conservative
protection while a freshly registered attempt advances. Completed
weight/supervised writers require `CompletedTraining`
directly and return opaque `StoredCompletedCheckpoint` only after exact pointer
CAS adoption and the attempt-independent commit; no completed persistence
boundary takes `Maybe CompletedTraining`.
Immutable create conflicts are accepted only after an exact-byte GET proves
identity. Local writes expose `CheckpointWriteError`, distinguishing invalid
input, immutable-object conflict, pointer-CAS conflict, and filesystem failure;
MinIO uses typed `ServiceError`. Latest admission performs `P1` → exact
addressed manifest outer/body → exact `P2` equality, then requires the exact
commit, validates the canonical-original → exact-scoped → payload-SHA
descriptor, reconstructs the logical manifest and snapshot id, and fetches/binds
the scoped objects. Known-address admission skips only the pointer reads. Final
completion refinement occurs after that persisted proof. Product Pipeline
consumes Store's opaque `AdmittedCompletedCheckpoint`, and Store does not import
Pipeline. Product-row evidence uses real verified data or fails closed before
training; current phase status and dated validation evidence live in the
[development plan](../../DEVELOPMENT_PLAN/README.md).
Strict supervised-graph reload reconstructs the persisted `LayerGraph`, injects
the one graph-ordered `supervised.weights` vector, refines topology, shapes,
edges, and parameter identity, applies the exact input/output transforms outside
the graph, and executes `LayerGraph.runLayerGraph`. This shared deterministic
serving path implements convolution, normalization, residual blocks,
multi-head attention with `W_O`, GeGLU, patch embedding, pooling, and Dense
operators directly from the admitted graph. The deleted `RuntimeOperations*`
callback ABI, token-runtime executor, and per-substrate structural-operation
tolerance bands are historical; no selected supervised engine can fall back to
them. Supervised serving is a pure function of the admitted checkpoint and input on
every substrate. Training is substrate-device-backed through the `MlpDevice` seam
for the MLP-backed RL, tuning, and AlphaZero rows; supervised layer-graph
training currently executes oneDNN kernels on every substrate rather than CUDA or
the fixed Metal bridge.

`src/JitML/Proto/Training.hs` defines the typed
`TrainingCommand` envelopes and deterministic text render/parse round-trips
for `StartTraining` and `StopTraining`; `encodeTrainingCommandProto` and
`decodeTrainingCommandProto` round-trip the current command oneof through
proto3-compatible bytes via `JitML.Proto.Wire`. `encodeTrainingEventProto`
and `decodeTrainingEventProto` round-trip the current `TrainingEvent` oneof,
including candidate and completed checkpoint variants, through the same local
wire helper. A completed nested payload first decodes as versioned
`RawCompletedTraining` and re-refines; generic protobuf/CBOR decoding does not
mint completion.
Generated proto-lens Haskell bindings live under `gen/Proto/Jitml/Training.hs`
and `gen/Proto/Jitml/Training_Fields.hs`. Sprint `8.12` / Phase `13` extend
the runtime to resolve and SHA-hash every supported
experiment Dhall, reconcile prerequisites, materialize the dataset, publish
`StartTraining` on `training.command.<mode>`, consume `training.event.<mode>`
through the daemon, and persist checkpoints for every canonical model family.

Product-row experiment resolution is centralized in
`JitML.Experiment.Product`. Every `ProductRow` `experimentConfig` either points
at a checked-in file under `experiments/` or is reflected from the typed product
registry into the same small Dhall record shape. The unit gate loads every
product row through that resolver, type-checks the resolved config, and fails on
missing files, malformed Dhall, unknown dataset/model keys, unknown
environment/game keys, or a generated PureScript/browser matrix constant that
has diverged from the Haskell registry.

The ProductRow publisher consumes the supervised epoch budget directly from
`JitML.Product.Matrix`: `cifar10-resnet20`, `cifar10-resnet56`, and
`cifar10-vit` execute `40` epochs; `tiny-imagenet-resnet50` executes `15`; the
other seven supervised rows execute `10`. Tiny ImageNet uses 8,000 training
examples, 1,000 evaluation examples, batch size 128, seed 1010, 120,000
processed examples, and 945 successful optimizer updates. The `sl_epochs=5`
report-card knob belongs to the canonical measurement stanza; it does not
override a ProductRow schedule and cannot produce ProductRow completion
evidence.

The `cifar10-vit` ProductRow uses an 8×8-patch/16-token literal ViT geometry
(patch embedding → LayerNorm → multi-head attention → GeGLU → linear head),
**2,000** training examples, forty epochs, batch size 128, **80,000** processed
examples, and **640** successful optimizer updates. Its RGB statistics are fitted
from the training partition only. The supervised recipe is likewise refined before execution:
`fashion-mnist-resnet` uses `3e-3`, `cifar10-resnet20` uses `1.1e-3`,
`cifar10-vit` uses `1.5e-3`, and the other eight rows use `1e-3`. The
finite-positive rate participates in `PlanId`, is
passed unchanged by Publisher, and is consumed by both classification and
California Housing regression. No environment override or executor default
reinterprets it. The pre-IR Mixer chronology is historical rather than a
current runtime contract.

The live `StartTraining` integration request uses the registered/ProductRow-
publisher MNIST schedule: **10** epochs × **7,000** training examples with
**1,000** evaluation examples and the unchanged **0.90** bar. A smaller or
otherwise substituted schedule cannot mint `CompletedTraining`; current phase
status and dated gate evidence live in the development plan.

## RL Framework Primitives

`src/JitML/RL/` owns the framework. `RLRunLifecycle` in
`src/JitML/RL/Framework.hs` indexes the legal computation phases
`RLCollect → RLComputeAdvantages → RLOptimise → RLEvaluate → RLCheckpoint`.
It is a domain projection into, not a replacement for, the placement/terminal/
evidence lifecycle in
[Typed Run Contract → Lifecycle State Machine](run_contract.md#lifecycle-state-machine).
`src/JitML/RL/Framework.hs` also owns the opaque finite `IterationSummary`,
non-empty ordered `LearningCurve`, `EpisodeOutcome`, and exact keyed
`EvaluationSet` evidence types. `src/JitML/RL/EpisodeEnvelope.hs` remains the
trajectory/animation projection; broker publication uses distinct plan-bound
`IterationSummary` telemetry and `EvaluationOutcome` evidence events. An
evaluation outcome's terminal bit is the environment's actual terminal signal,
not merely completion of the evaluator loop: reaching the planned episode-step
horizon without environment termination is preserved as `False`. The
deterministic `RLLoop` /
`runRLLoop` scaffold is test-support only under
`test/rl-canonicals/Support/Loop.hs`, where `scaffolding:`-prefixed tests keep
its historical determinism checks out of the product path.

Current local surfaces live in `src/JitML/RL/Algorithms.hs`,
`src/JitML/RL/Environments.hs`, `src/JitML/RL/Framework.hs`, and
`src/JitML/RL/{Policy,Buffer,AsyncBuffer,EpisodeEnvelope}.hs`, plus one module
per traditional algorithm under `src/JitML/RL/Algorithms/` and the AlphaZero
substack under `src/JitML/RL/AlphaZero/`. They provide catalog, environment,
run-plan, lifecycle, policy, buffer, per-algorithm module, canonical-game,
MCTS, self-play, arena, and publication-envelope helpers. Current device-backed paths
exist for the implemented workflow surface. Sprint `9.12` removes the
reward-derived algorithm-level projection helpers from canonical validation and
writes `.jmw1` checkpoints plus line-oriented replay artifacts from `jitml rl
train` / `jitml rl rollout`. Sprint `10.6` records RL policy model-family
metadata, policy-distribution output decoders, and replay/transcript pointers in
the checkpoint manifest. Product publication now writes the exact
`rl-trajectory` first, binds its canonical key and content SHA into the
completed Product weight-only manifest, and re-admits both checkpoint and
trajectory bytes before eligibility. The product contract consumes those artifacts for the
full matrix: every algorithm must train for its fixed budget, evaluate,
roll out, checkpoint, publish convergence statistics, and provide browser
replay/animation payloads before it is treated as inference-eligible.

`JitML.RL.ProductBudget` is the shared planner for traditional RL ProductRow
training and completion. Its `2,000`-transition default is a requested floor,
not the completed budget: the registered row budget is the aggregate observed
environment-transition count after vector-environment multiplicity and the
trainer's indivisible rollout, fixed-step, ARS-direction, or HER-episode
granularity are applied. The producer executes that same schedule and completion
requires exact equality with its aggregate count. The separate
`rl_steps=100_000` report-card knob parameterizes canonical measurements and
cannot mint ProductRow completion.

The successful trainer return, not this planner, owns
`MeasuredEnvironmentTransitions` and `MeasuredOptimizerUpdates`. PPO-family,
DQN, QR-DQN, continuous-control, ARS, and HER loops increment those counters at
their actual transition and learned-tensor update sites. Callers exact-check the
measured transition count against the compiled target and carry the measured
update count into `TrainingEvidence`; they never recreate either counter from
configuration. The plan intentionally omits the former heterogeneous
optimizer-update field, which mixed iterations, environment steps, and episodes
across trainer families.

### Algorithm Class Taxonomy (Type-Level)

The current `AlgorithmFamily` metadata in `src/JitML/RL/Algorithms.hs`
enumerates `OnPolicy`, `OffPolicy`, `Specialized`, and `SelfPlay`; the concrete
per-algorithm modules are aggregated by
`src/JitML/RL/Algorithms/Registry.hs`. Sprint `25.2` makes that registry carry
an `AlgorithmUpdateContract` per traditional product algorithm: a unique update
identity, trainer entry point, rollout surface, learned-artifact shape, and
update-feature list. `validateAlgorithmModuleRegistry` rejects duplicate
algorithm ids, duplicate update identities, and incomplete contracts, and the
product-row unit tests resolve every RL product algorithm through that registry.
The no-caveat runtime grows this into a GADT-indexed `Algorithm` kind with traits:

- `OnPolicy` / `OffPolicy` / `Hierarchical` / `Recurrent`
- `MaskingCapable` (algorithm supports action masks)
- `ContinuousAction` / `DiscreteAction`
- `ImageObs` / `VectorObs`

The taxonomy is used at the type level to constrain algorithm-instance
declarations.

### Policy and Environment

- Current `Policy` carries typed policy metadata, parameter references, the
  substrate binding, and the substrate-bound `KernelHandle` model id; final
  runtime work loads and executes the referenced checkpointed policy for every
  algorithm-specific train/eval/rollout path.
- Current `RLEnvironment` metadata plus `src/JitML/RL/Simulator.hs` cover native
  simulator dynamics. Default examples and required canonical tests use
  copyright-free environments only; `KeyDoorGrid-v0` is the active repo-owned
  visual discrete-control replacement for the former Atari-backed demo target.
- Current `src/JitML/RL/Environments.hs` provides local metadata for the seven
  product canonical environments: CartPole-v1, MountainCar-v0, Acrobot-v1,
  Pendulum-v1, LunarLander-v2 (discrete), KeyDoorGrid-v0, and
  GridWorld-Deterministic-v0. `src/JitML/RL/Simulator.hs` owns the native
  Haskell dynamics and render-frame projection for the same catalog; Pendulum
  remains a continuous-action environment with explicit torque bounds, with a
  discrete wrapper used only by generic test episode drivers. The old
  deterministic step helper is test-support only in
  `test/rl-canonicals/Support/DeterministicStep.hs`. `KeyDoorGrid-v0` is a
  deterministic seeded grid/key/locked-door environment with legal-action
  masks, vector/grid observations, generated render frames, and no external
  assets.
- `atari-subset` routes through `JitML.RL.ALE` only as optional runtime
  support. The project image may carry the pinned ALE library/runtime, but the
  repository no longer carries or compiles a checked-in C/C++ adapter shim. Any
  future project-owned ALE adapter must be generated by Haskell into the
  build/cache tree, or supplied explicitly outside the repository with
  `JITML_ALE_SHIM_PATH`. ROM bytes are never committed, baked into images, or
  required by default examples/tests. Optional Atari runs supply
  `RunConfig.atariRomPath`, `JITML_ATARI_ROM`, or `JITML_ALE_ROM`; without a
  ROM path, `atari-subset` fails with the explicit ROM-policy diagnostic.

### Buffers

- Current `ReplayBuffer` covers off-policy and on-policy rollout storage with
  deterministic sampling.
- Current `AsyncBuffer` provides the bounded async write discipline and drain
  boundary.
- The async sink persists through live `HasMinIO`; its commit log is keyed by
  the plan-bound semantic event ID so broker redelivery is idempotent without
  treating payload bytes as workflow identity.

### Schedules, Distributions, Noise, Targets, GAE, Callbacks, Logger, Evaluator

| Primitive | Current location |
|-----------|------------------|
| Schedules | `src/JitML/RL/Framework.hs` metadata |
| Action distributions | `src/JitML/RL/Framework.hs` metadata |
| Action noise | `src/JitML/RL/Framework.hs` metadata |
| Target networks | `src/JitML/RL/Framework.hs` metadata |
| GAE | `src/JitML/RL/Framework.hs` metadata |
| Callbacks | `src/JitML/RL/Framework.hs` metadata |
| Evaluator | `src/JitML/RL/Framework.hs` metadata |

Sprint `9.12` splits these into dedicated modules where needed and composes
them into the no-caveat `RLLoop` closure.

### `jitml rl train` CLI

```
jitml rl train <rl-experiment-dhall>
               [--resume <checkpoint-id>]
               [--dry-run | --plan-file <path>]
```

Normal execution consumes a refined RL plan. Its training plan has distinct
environment-transition, rollout-per-environment, vector-environment, and
episode-horizon quantities; its evaluation plan has a positive count of
evaluation episodes. The validated run seed and episode horizon remain distinct
from that count. Optimizer applications are measured trainer output, not a plan
quantity. Only the pure plan compiler may
derive trainer iterations. It cannot use an evaluation count as a training
iteration count or an episode horizon as a rollout length. See
[Typed Plans and Dimensional Budgets](run_contract.md#typed-plans-and-dimensional-budgets).

Every MLP-backed algorithm resolves to the selected substrate's probed JIT
device and fails closed on device error. ARS is the explicit no-MLP exception
because it performs finite-difference policy search. Trainer selection is a
closed plan choice compatible with the algorithm and environment, not a second
text field that may disagree with the algorithm.

RL completion requires opaque positive counters returned by the trainer, a
non-empty strictly ordered `IterationSummary` learning curve, an exact keyed
`EvaluationSet`, finite rewards, the terminal metric, and one completed
checkpoint. The final median consumes the full evaluation cohort, never its
tail; the plan-bound terminal `median_final_reward` event must equal the median
derived from that exact cohort. The measured physical training-transition count is both
the exact completion observation and checkpoint step, and the completed witness
must carry the same `PlanId` derived from the compiled RL plan. Final-policy
episodes and their step counts are not training iterations or completion
progress, and delivery order is not a learning curve. The reducer and completion shape are owned by
[Protocol and Evidence Contracts](run_contract.md#protocol-and-evidence-contracts).
`RlCheckpoint CheckpointDoneRL` records a candidate checkpoint;
`RlCompletedCheckpoint CompletedCheckpointDoneRL` is the distinct proof-bearing
variant with mandatory, re-refined `CompletedTraining`. Candidate persistence
alone cannot satisfy the reducer's completed-checkpoint requirement.

`src/JitML/Proto/Rl.hs` owns the raw versioned command/event codecs, including
plan-bound `IterationSummary` telemetry, keyed `EvaluationOutcome` evidence,
plan-bound `MetricUpdate` completion measurements, and animation/replay
projections. Decoding or a text/protobuf round-trip does
not validate a run. Evaluation outcomes refine against the `PlanId` and exact
keyed live protocol; iteration summaries remain publication telemetry whose
strict ordering was already enforced by the local `LearningCurve` constructor.
Generated proto-lens Haskell bindings live
under `gen/Proto/Jitml/Rl.hs` and `gen/Proto/Jitml/Rl_Fields.hs`.

Placement is substrate-specific. Linux CPU/CUDA `rl.command.<mode>` messages may
become Kubernetes Jobs because the target device runtime is present in the worker
container. Apple Silicon `rl.command.apple-silicon` messages are public
orchestration commands only: the in-cluster daemon forwards Metal-backed RL
starts to `rl.host-command.apple-silicon` and the host daemon publishes normal
`rl.event.apple-silicon` events from the completed host run. Running the same
`jitml rl train` worker in a Linux pod for `apple-silicon` is not a valid
fallback. The closed placement value and common interpreter make that host/
cluster distinction before publication or resource acquisition; see
[Lifecycle State Machine](run_contract.md#lifecycle-state-machine).

`jitml rl eval --checkpoint <id>` shares `runCheckpointEval` with `jitml eval`
(Sprint 9.9): it loads the named checkpoint and runs the substrate-bound weighted
device forward, surfacing `InferenceCheckpointMissing` when absent — no echo
stub. `jitml rl rollout --seed N` runs one real on-device PPO rollout on cartpole
through `rlDeviceForSubstrate` (`runDeviceRollout`) and prints the measured
episode rewards, failing closed with `InvalidConfig` when the substrate device
is unavailable. The trained-policy rollout surface steps real named environment
dynamics with deterministic seeded policy evaluation, not a catalog projection.
Device-backed MCTS value-head leaf evaluation and device-backed tuning trial
training are implemented through the selected `MlpDevice` and fail closed on
device errors. Sprint `8.15` applies that same typed fail-closed requirement to
post-probe off-policy/continuous trainer update failures: DQN, QR-DQN, HER, and
continuous actor-critic device trainers return `Left Text` for forward,
batch-gradient, and input-gradient faults, and `runTrainerEpisodes` stops the
run without bypassing the CLI/daemon error surface or publishing partial
episodes. DQN's pure and device update paths share one kappa-1 Huber derivative
over the Bellman TD residual, so each sample's residual-gradient contribution is
clipped to `[-1, 1]` before the minibatch mean reaches Adam. Its greedy behavior
policy and final trained-policy evaluation also use the selected fail-closed
`MlpDevice`; the pure trainer supplies `pureReferenceMlpDevice` to the same
loop. A device-trained DQN row therefore cannot select actions or publish its
convergence metric from an unrecorded host-`Double` forward path.

The same host-residency rule applies to supervised training, tuning trial
training, and AlphaZero value/policy evaluation whenever the selected substrate
is `apple-silicon`: Pulsar carries typed commands/events, MinIO carries datasets,
checkpoints, weights, and metrics, and only the host daemon calls the fixed Metal
bridge.

## RL Algorithm Catalog

<!-- jitml:training.rl.catalog:start -->
| Algorithm | Family | Replay-backed | Hyperparameters | Module |
|-----------|--------|---------------|-----------------|--------|
| `PPO` | OnPolicy | no | 10 | `src/JitML/RL/Algorithms/Ppo.hs` |
| `A2C` | OnPolicy | no | 7 | `src/JitML/RL/Algorithms/A2c.hs` |
| `TRPO` | OnPolicy | no | 10 | `src/JitML/RL/Algorithms/Trpo.hs` |
| `MaskablePPO` | OnPolicy | no | 6 | `src/JitML/RL/Algorithms/MaskablePpo.hs` |
| `RecurrentPPO` | OnPolicy | no | 6 | `src/JitML/RL/Algorithms/RecurrentPpo.hs` |
| `DQN` | OffPolicy | yes | 9 | `src/JitML/RL/Algorithms/Dqn.hs` |
| `QR-DQN` | OffPolicy | yes | 6 | `src/JitML/RL/Algorithms/QrDqn.hs` |
| `DDPG` | OffPolicy | yes | 7 | `src/JitML/RL/Algorithms/Ddpg.hs` |
| `TD3` | OffPolicy | yes | 7 | `src/JitML/RL/Algorithms/Td3.hs` |
| `SAC` | OffPolicy | yes | 7 | `src/JitML/RL/Algorithms/Sac.hs` |
| `CrossQ` | Specialized | yes | 6 | `src/JitML/RL/Algorithms/CrossQ.hs` |
| `TQC` | Specialized | yes | 6 | `src/JitML/RL/Algorithms/Tqc.hs` |
| `ARS` | Specialized | no | 5 | `src/JitML/RL/Algorithms/Ars.hs` |
| `HER` | Specialized | yes | 5 | `src/JitML/RL/Algorithms/Her.hs` |
| `AlphaZero` | SelfPlay | no | 0 | `src/JitML/RL/AlphaZero/` |
<!-- jitml:training.rl.catalog:end -->

`dhall/rl/Schema.dhall` is the current Dhall mirror for the local Haskell
algorithm catalog and is audited by `JitML.RL.Schema` plus the Haskell lint
stack. The traditional algorithms have concrete modules under
`src/JitML/RL/Algorithms/{Ppo,A2c,Trpo,MaskablePpo,RecurrentPpo,Dqn,QrDqn,Ddpg,Td3,Sac,CrossQ,Tqc,Ars,Her}.hs`
aggregated by `Registry.algorithmModuleRegistry`; each module names the
algorithm-specific update contract that product rows must resolve before
training.
Related algorithms intentionally share a trainer family without sharing one
undifferentiated update rule. `trpo` and `recurrentppo` route through the PPO
on-policy family via
`PpoTrainer.Variant{TRPO,RecurrentPPO}` in `src/JitML/App.hs`, and `sac`,
`crossq`, and `tqc` route through
the continuous actor-critic family via
`ContinuousTrainer.Variant{SAC,CrossQ,TQC}` in the same module. Their distinct
logic includes a KL-constrained TRPO natural-gradient line search for every
rollout (TRPO ignores PPO's configured epoch count), RecurrentPPO recurrent
epochs, SAC entropy terms,
CrossQ target-net removal, and the TQC pooled-quantile critic. The Sprint `25.2`
collapse guard proves the named update paths do not collapse to identical final
parameters. Per-model convergence remains a separate evidence obligation. The
product A2C contract likewise consumes each sampled rollout exactly once. A2C's
unclipped actor-critic surrogate has no PPO ratio bound that would make ten
passes over samples from the old policy safe; `productPpoEpochsPerUpdateFor`
therefore selects one pass for A2C and TRPO while preserving the configured PPO
epoch count for PPO, MaskablePPO, and RecurrentPPO. This selection is
algorithm-specific and substrate-independent. Measured optimizer counters still
record the minibatch applications that actually ran; the canonical A2C product
schedule produces 19,200 applications from its 1,228,800 observed transitions.
The current `jitml-model-convergence` suite guards case-registry coverage and bar
metadata only; [Phase 285](../../DEVELOPMENT_PLAN/phase-285-contract-driven-per-model-evidence.md)
binds each algorithm/environment case to its own completed trained-policy run.
PPO/CartPole determinism is asserted by `jitml-rl-canonicals` as
run-to-run equality on the same substrate and seed (two fresh runs compared
against each other), and Sprint `25.2` adds a trained-parameter/update-path guard
for the on-policy variants so A2C, TRPO, and RecurrentPPO cannot collapse to
PPO's final parameters while MaskablePPO must carry the mask path through
rollout. Richer Dhall types at `dhall/rl/algos/<algo>.dhall`, trained-policy
checkpoint loading, and all-algorithm update/eval/rollout closure are
implemented for the `linux-cpu` baseline.
The TRPO device line search evaluates each candidate's full categorical policy
as one substrate-backed batch and fails closed on a device error. Each rollout
executes exactly one natural-gradient actor trust-region step, followed by ten
separate value-head-only critic passes over the configured rollout minibatches.
Each critic minibatch recomputes its gradient at the current critic parameters,
threads Adam with the TRPO-specific `value-learning-rate = 0.001`, and preserves
actor isolation. Neither count is derived from PPO epochs. Exact
measured counters project the accepted actor natural-gradient applications and
value-head Adam applications into `TrainingEvidence.updateCount`; a rollout
count is never substituted for that observation. The runtime module, algorithm
catalog, and trainer default agree
on `max-kl = 0.01`, ten CG iterations, `cg-damping = 0.1`,
`cg-residual-tol = 1e-10`, ten `0.8` backtracking candidates, ten critic passes,
and the `0.001` critic learning rate. Validation counts, immutable-image
identities, and ProductRow publisher evidence live in the authoritative
[Development Plan Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status)
and the legacy-to-new map entries for owning
[Phase 12](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map) and
[Phase 19](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map).
The ProductRow resolver explicitly tightens Lunar Lander to `max-kl = 0.002`;
`JitML.RL.TrainerExecution` now derives that environment-specific choice from
the compiled traditional-RL plan rather than an `App`-local override.
Sparse-goal on-policy product rows resolve
their count-exploration coefficient by variant and environment before the
generic zero fallback, so `MaskablePPO/key-door-grid` retains phase-aware
position/key/door novelty during training while deterministic evaluation uses
the learned masked policy without a reward bonus. Mountain Car exposes no
illegal-action mask, so its MaskablePPO row retains PPO's count-exploration
strength rather than introducing a weaker variant-only training path. Current
replay evidence and the remaining refresh gates live in the
[Development Plan Closure Status](../../DEVELOPMENT_PLAN/README.md#closure-status);
the historical owner is indexed as
[legacy Phase 19](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map).
Per-algorithm trajectory `.txt` fixtures are explicitly
**not** committed — see [unit_testing_policy.md → Snapshot Tests and
the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

The convergence matrix for the catalog is model-owned, not family-owned. PPO,
A2C, TRPO, MaskablePPO, RecurrentPPO, DQN, QR-DQN, DDPG, TD3, SAC, CrossQ,
TQC, ARS, HER, and AlphaZero each require their own fixed budget, completed
training witness, convergence-statistics record, checkpoint, and UI/e2e
evidence. Family-level smoke tests do not close a model row.

The Phase `25` implementation runs these RL rollouts vectorized: roughly `16` parallel
environment instances are batched through the network in one device call per
step (reintroducing a real, product-reachable `JitML.RL.VecEnv`), and the RL
network hidden widths are raised (from `64`/`128` toward `~256`), so the
model-owned convergence bars above are re-cleared under the new vectorized
regime at the raised widths.

Phase `22` also registers the environment-floor parity rows `PPO/acrobot`,
`SAC/pendulum`, and `PPO/gridworld-deterministic` so every documented canonical
environment resolves to a product row rather than passing by representative
algorithm coverage alone. Those rows carry their own fixed budgets, convergence
bars, experiment configs, integration ids, and e2e ids in
`JitML.Product.Matrix`.

For off-policy algorithms, the bit-equality anchor is the first-N-
steps prefix per [determinism_contract.md → Same-Substrate Bit-Equality (RL
Caveat)](determinism_contract.md#same-substrate-bit-equality-rl-caveat),
again compared run-to-run rather than against a stored prefix.

## AlphaZero-Style Self-Play

The current AlphaZero surface lives in `src/JitML/RL/AlphaZero.hs` plus
`src/JitML/RL/AlphaZero/{Mcts,SelfPlay,PolicyValueNet}.hs`. It provides per-game
state/move helpers for Connect 4, Othello, Hex, and Gomoku, deterministic
transcript summaries, local game metadata, two-headed-network metadata,
persistent MCTS transposition-table helpers, self-play buffer hashing,
device-backed policy/value leaf evaluation, and arena-promotion measurement.
Every game oracle masks policy priors and visit targets to the exact legal move
set before MCTS expansion; self-play and arena opponents consume that same set,
so an illegal policy index is rejected rather than remapped to another action.
Othello represents a mandatory no-move turn with a deterministic pass marker,
normalizes that pass before policy evaluation, and backs values up according to
the actual player to move on each side of an edge.
Sprint `9.12` adds shared terminal/winner/draw evaluators for every canonical
game and writes local `.jmw1` policy/value checkpoints from
`jitml rl alphazero self-play` together with a content-addressed
`alphazero-transcript` artifact carrying the sampled states, MCTS visit
distributions, and outcome labels consumed by replay/inspection surfaces.
Product publication writes that transcript first, binds its exact pointer into
the Product weight-only manifest, and requires Store re-admission before
eligibility. Sprint `10.6` records AlphaZero policy/value model-family metadata, policy/value/MCTS
output decoders, and transcript pointers in the manifest. Phase `13` / `14`
still own full product-matrix consumption of those artifacts.

| Component | Current / target |
|-----------|------------------|
| Connect 4 helpers | Current: `src/JitML/RL/AlphaZero.hs` |
| Perfect-information game metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| Two-headed network metadata | Current: `src/JitML/RL/AlphaZero.hs` |
| MCTS with PUCT and persistent tree state | Current recursive module: `src/JitML/RL/AlphaZero/Mcts.hs`; position-aware network prior/evaluator via `PolicyValueNet.netOracleFactory`; device-backed effectful leaf evaluation via `PolicyValueNet.netOracleFactoryWithDevice` / `mctsVisitDistributionWithDevice` |
| Self-play loop and replay buffer | Current module: `src/JitML/RL/AlphaZero/SelfPlay.hs`; `jitml rl alphazero self-play` emits checkpoint keys plus an `alphazero-transcript` artifact; Phase `13` / `14` consume those artifacts across every game/browser workflow |
| Arena gating | Current measured helper: `src/JitML/RL/AlphaZero/PolicyValueNet.hs` arena win-rate evaluation; terminal/winner/draw detection flows through `GameOutcome` for Connect 4, Othello, Hex, and Gomoku; the standalone `Arena` module is deleted |

### Persistent MCTS State

The top-level `MctsState` is a small local metadata record with visit count and
a prior seed. `JitML.RL.AlphaZero.Mcts` now provides the persistent
`TranspositionTable`, `TranspositionKey`, `runSearchWithTable`, and effectful
`runSearchWithPriorIO` helpers; the production self-play path uses the real
two-headed policy/value network evaluator instead of a deterministic prior.
Sprint `26.1` threads a transposition table through each self-play game's plies,
records per-ply cache-size evidence, applies deterministic root Dirichlet noise
from the supplied seed, and resolves equal PUCT scores by the lowest action
index.

### `jitml rl alphazero self-play` CLI

```
jitml rl alphazero self-play
                            [--substrate <substrate>]
                            [--seed <word64>]
                            [--game <connect4|othello|hex|gomoku>]
                            [--generations <n>]
                            [--games <n>]
                            [--sims <n>]
                            [--max-plies <n>]
                            [--updates <n>]
                            [--arena-games <n>]
```

The command probes the selected substrate `MlpDevice`, resolves the selected
game's initial state, observation size, and action count, generates bounded
self-play samples through device-backed MCTS leaf policy/value evaluation,
trains the policy/value head on that device, and prints the sample count plus
arena win rate. The written checkpoint records a `CompletedTraining` witness
with deterministic initial/final policy-value network hashes, a positive
self-play generation count, and the fixed-budget AlphaZero metric rows
`arena_win_rate`, `legal_move_rate`, `mcts_simulations_per_move`,
`self_play_games`, `self_play_generations`, and `self_play_samples`; the
checkpoint is inference-eligible only when the arena observation passes
`JitML.RL.ConvergenceThresholds.alphaZeroArenaThreshold`. When the command runs
in a worker context, the same completion publisher emits those rows through
Pulsar. A missing substrate runtime, unknown game, or device execution error is
an `InvalidConfig` failure; there is no pure-Haskell fallback on the CLI path.

Before any of those effects, `JitML.Plan.Command.prepareStartAlphaZeroRun`
refines the raw command into a hidden `AlphaZeroPlan`. Its positive quantities
separately index generations, self-play games, MCTS simulations per move,
maximum plies, optimizer updates, and arena games. The command carries the
canonical version-`1` plan transport and content-derived `PlanId`; the direct
path, daemon-dispatched Linux Job, and Apple host-command route all validate and
execute that same plan. The Linux `AlphaZeroRunConfig` mount contains only the
plan identity, resolved plan, and operational Pulsar WebSocket endpoint.
Missing, malformed, version-incompatible, non-canonical, or identity-mismatched
plan input fails before a game, checkpoint, or event publication.

`GenerationCompleted` and `ArenaCompleted` carry the plan identity.
`JitML.Run.WorkloadContract` requires the exact zero-based generation range,
the plan-prescribed self-play-game count in every generation, and exactly one
arena result with the plan-prescribed game count and a finite win rate. It
derives semantic event identity through the shared contract algebra, making an
identical delivery idempotent while rejecting gaps, out-of-range keys,
conflicting duplicates, wrong-plan events, and budget mismatches.

### Deterministic Stochasticity

Per-game RNG seeds derive from `splitmix64(experimentSeed, gameIndex)`. The
MCTS root-noise seed is derived from the per-game seed. Same-substrate same-
seed self-play produces bit-identical game sequences and visit counts for each
canonical game; the canonical test compares fresh reruns against each other and
does not check in transcript or visit-count fixtures.

### Canonical Adversarial Games

| Game | Owning module |
|------|---------------|
| Connect 4 | `src/JitML/RL/AlphaZero.hs` metadata, `initialConnect4`, `applyMove`, transcript helper, two-headed network, and `Masked Discrete(7)` action surface |
| Othello | `src/JitML/RL/AlphaZero.hs` metadata, `initialOthello`, exact legal-move application, deterministic forced-pass normalization, transcript helper, two-headed network, and `Masked Discrete(64)` action surface |
| Hex | `src/JitML/RL/AlphaZero.hs` metadata, `initialHex`, `hexApplyMove`, transcript helper, two-headed network, and `Masked Discrete(121)` action surface |
| Gomoku | `src/JitML/RL/AlphaZero.hs` metadata, `initialGomoku`, `gomokuApplyMove`, transcript helper, two-headed network, and `Masked Discrete(225)` action surface |

Connect 4 is the canonical demo game consumed by the PureScript Connect 4
panel metadata. Per-game transcript files are explicitly **not** committed
(MCTS visit counts depend on RNG host word size, transcendental impl, and
PUCT-tie-breaking float order, all of which vary across substrates);
correctness is asserted as run-to-run equality on the same substrate / seed
plus rule-conformance properties (every emitted move is legal under
`nextLegalMove`, terminal states match `gameTerminal`, draws are detected
canonically). See [unit_testing_policy.md → Snapshot Tests and the
Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

## Hyperparameter Tuning

`src/JitML/Tune/` owns the hyperparameter tuner surface. The current local
catalog lives in `src/JitML/Tune/Catalog.hs` and follows the sampler x
scheduler x pruner shape from [../README.md → Hyperparameter tuning,
first-class](../../README.md#hyperparameter-tuning-first-class).
The checked-in `experiments/mnist-tune.dhall` file is the target-shape
`Some Tuning::{ ... }` worked example with a TPE sampler. The current Haskell
catalog below covers the full target sampler set, decodes that fixture into
the local tuning ADT, and renders a deterministic `jitml tune` plan. Trial
values are real local measured objectives (not LCG values). Live daemon-backed
trial persistence/replay is validated on the Linux lanes; substrate-device-backed
trial training is implemented by `trialObjectiveResultWithDevice` /
`deterministicTrialsWithDevice`, which train each measured trial through the
selected `MlpDevice`, return checkpointable trained weights for promotion, and
return a typed failure instead of falling back to a pure objective.
Sprint `9.15` keeps replay/resume total by recording `ResumeReadFailure` values
in `resumeReadFailures`: missing/read failures use `ResumeServiceFailure
ServiceError`, corrupt CBOR transcript bytes use `ResumeDecodeFailure Text`, and
`ResumeOutcome` `Eq` / `Show` remain total at the caller boundary. Sprint `9.16`
keeps the real-workflow rule strict: overrides that appear in CLI output are
applied before validation/artifact writing, and daemon-dispatched tuning workers
execute the sampler/scheduler/pruner already captured in their resolved
`TuningPlan` instead of re-reading primitive axis fields or enumerating the
whole catalog grid.
`jitml-hyperparameter` consumes the `tune_trials` and
`tune_budget_per_trial` report-card knobs from `cabal.project` for the local
TPE trial-budget assertion.
`src/JitML/Proto/Tune.hs` defines the typed `TuneCommand` envelopes and
deterministic text render/parse round-trips for `StartSweep` and `StopSweep`;
`encodeTuneCommandProto` and `decodeTuneCommandProto` round-trip the current
command oneof through proto3-compatible bytes via `JitML.Proto.Wire`.
`encodeTuneEventProto` and `decodeTuneEventProto` round-trip the current
`TuneEvent` oneof through the same local wire helper. That oneof separates
proof-free `TuneSweepFinished SweepFinished` from proof-bearing
`TuneSweepCompleted SweepCompleted`; the latter's hidden wrapper contains
mandatory, re-refined `CompletedTraining`. Generated proto-lens
Haskell bindings live under `gen/Proto/Jitml/Tune.hs` and
`gen/Proto/Jitml/Tune_Fields.hs`.

`TuneSweepLifecycle` indexes the domain computation phases (`Sampled →
Scheduled → Running → Pruned → Reported → Finished`). The complete tuning run
additionally uses the common placement, exact-trial evidence, terminal state,
settlement, and cleanup lifecycle in
[Typed Run Contract](run_contract.md).

CLI Dhall overrides land in Sprint `1.12`: `jitml tune --sampler …
--scheduler … --pruner … --trials … --parallelism …` substitute on the
named axis only and never replace the surrounding `Tuning` record per
[../../README.md → Hyperparameter tuning, first-class](../../README.md#hyperparameter-tuning-first-class)
line 1050. The pure resolver
`JitML.Experiment.Overrides.applyOverrides` consumes `ParsedOption`
values, returning a typed `OverrideError` on invalid flag values that the
CLI boundary surfaces through the existing `AppError` /
`exitWithError` path. `jitml train` and `jitml rl train` accept the
analogous `--substrate` / `--seed` overrides for the experiment-Dhall
substrate and seed fields, and `jitml rl train --algorithm <algorithm>` applies
an algorithm override to the resolved RL experiment without replacing the
surrounding environment/seed record. See
[Phase 15: CLI Dhall Overrides (legacy Sprint 1.12)](../../DEVELOPMENT_PLAN/phase-15-cli-dhall-overrides.md)
for the owning sprint and the doctrine-deviation interval recorded in
[../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md](../../DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md).
When `--trials` lowers the trial count without an accompanying
`--parallelism`, the resolver caps the inherited Dhall parallelism at the new
trial count before plan refinement. An explicit `--parallelism` remains
authoritative: a value larger than the resolved trial budget is rejected as an
invalid plan instead of being silently changed.
Sprint `9.16` closes the tuning integration boundary: the resolved experiment,
including CLI overrides, is the only input to local tune artifacts; daemon
workers select trials from the versioned resolved `TuningPlan` and may not
silently replace its axes with a catalog-wide product. `TuneRunConfig` carries
only that canonical transport, its `PlanId`, and the Pulsar WebSocket endpoint.

`JitML.Plan.Command.prepareStartSweepWithExecutionSpec` refines the overridden
Dhall command once into a hidden plan whose positive quantities distinguish
trials, concurrent trials, promotions, and the maximum optimizer-update budget
per trial, while its normalized execution spec binds every search, objective,
sampler, scheduler, and pruner field into the same `PlanId`. The older
`prepareStartSweep` remains the compatibility adapter for primitive command
DTOs. Local execution, Linux Jobs, and the Apple host-command route all
re-refine the transported exact spec and validate the same canonical plan and
identity before trial, checkpoint, or publication effects. Trials
execute in cohorts no wider than the resolved parallelism. Fifo without a
pruner consumes the ceiling; SuccessiveHalving and ASHA advance retained
optimizer state through eta-derived measured rungs, and an active pruner may
stop a trial at its configured measured checkpoint. Every terminal record
retains its actual update count, objective trace, and scheduler/pruner
disposition. Only trials that reached the ceiling are eligible for the exact
resolved promotion frontier and checkpoints. `TrialStarted`, `TrialFinished`,
`SweepFinished`, and `SweepCompleted` carry the same `PlanId`.
`SweepFinished` reports exact completed, pruned, and promoted counts plus a
finite best objective, but remains proof-free. `SweepCompleted` wraps those
counts together with mandatory completion evidence.
`JitML.Run.WorkloadContract` accepts completion only for the exact zero-based
trial range plus exactly one proof-bearing sweep result, with finite objectives
and the plan-prescribed completed-trial and promoted-trial counts. Identical
semantic redeliveries are idempotent; gaps, out-of-range keys, wrong-plan events,
conflicting duplicates, budget mismatches, and non-finite objectives are typed
violations.

The registered `hyperparameter-tuning` ProductRow is also the live integration
schedule; the test does not substitute a two-trial smoke fixture. It resolves
`TPE` + `ASHA` + `MedianPruner`, **128 trials**, sweep seed **1729**, an exact
**1000**-optimizer-update ceiling allocated through eta-derived measured rungs
with real scheduler/pruner early stopping, and parallelism **1** from the ProductRow,
`experiments/mnist-tune.dhall`, and the named `JitML.Tune.Catalog` defaults.
The unchanged convergence contract maximises `best_objective` against target
**1.0** with slack **0.05**, and is checked over the best promoted measured
objective. A non-live integration regression loads and executes the same
registered schedule through sampling, scheduling, pruning, promotion, and bar
evaluation so fixture drift fails before the live workflow is launched.

### Samplers

<!-- jitml:training.tune.samplers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Grid` | Generated from current Haskell catalog |
| `Sobol` | Generated from current Haskell catalog |
| `Random` | Generated from current Haskell catalog |
| `TPE` | Generated from current Haskell catalog |
| `GPBO` | Generated from current Haskell catalog |
| `GeneticAlgorithm` | Generated from current Haskell catalog |
| `NSGA2` | Generated from current Haskell catalog |
| `MuLambdaES` | Generated from current Haskell catalog |
| `CMAES` | Generated from current Haskell catalog |
| `EvolutionStrategies` | Generated from current Haskell catalog |
| `PBT` | Generated from current Haskell catalog |
<!-- jitml:training.tune.samplers:end -->

### Schedulers (tuner-side)

<!-- jitml:training.tune.schedulers:start -->
| Constructor | Current scope |
|-------------|---------------|
| `Fifo` | Generated from current Haskell catalog |
| `SuccessiveHalving` | Generated from current Haskell catalog |
| `Hyperband` | Generated from current Haskell catalog |
| `ASHA` | Generated from current Haskell catalog |
<!-- jitml:training.tune.schedulers:end -->

### Pruners

<!-- jitml:training.tune.pruners:start -->
| Constructor | Current scope |
|-------------|---------------|
| `NoPruner` | Generated from current Haskell catalog |
| `MedianPruner` | Generated from current Haskell catalog |
| `PercentilePruner` | Generated from current Haskell catalog |
<!-- jitml:training.tune.pruners:end -->

### Trial Storage and Resume

Target trial transcripts are written to MinIO bucket `jitml-trials`, content-
addressed by `sha256(resolved-dhall || trial-seed)`. Target resume reads
existing trials, recomputes the sampler state, and continues from the correct
trial index.

The current local surface in `src/JitML/Tune/Catalog.hs` exposes
`trialStorageKey`, `resumeMatchesFullRun`, and `renderTrialResumeSummary` for
deterministic key and resume-equality checks. `src/JitML/Tune/Resume.hs`
provides `persistTrialTranscript` and `replaySweep` over `HasMinIO`, validated
against the filesystem-backed instance; Sprint `9.12` / Phase `14` require live
HTTP MinIO persistence, checkpoint promotion, and browser-visible sweep state
for the no-caveat product workflow. Sampler behaviour is exercised by
`jitml-hyperparameter` as
properties (sampler state is a pure function of its seed and event log;
two runs produce bit-identical trial-spec sequences; `replaySweep` over a
recorded event log yields the same next-batch as the first-pass
dispatcher). Per-sampler `.txt` trial-value fixtures are explicitly
**not** committed — see [unit_testing_policy.md → Snapshot Tests and
the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).

### `jitml tune` CLI

```
jitml tune <tune-dhall>
           [--resume <sweep-id>]
           [--dry-run | --plan-file <path>]
```

Target normal execution decodes the tuning Dhall, applies CLI overrides before
validation, renders the selected sampler/scheduler/pruner axes from the resolved
experiment, and executes measured trial objectives through the selected device
path where available. Sprint `9.12` writes the best local
trial's trained weights as a `.jmw1` checkpoint, emits a `tune-trials` artifact,
and promotes daemon-dispatched trial weights into `jitml-checkpoints` alongside
the `jitml-trials` transcript. Sprint `10.6` records tuning model-family
metadata, objective/regression output decoders, and trial transcript pointers in
the checkpoint manifest. Product publication emits `tune-trials-v2` before the
Product weight-only checkpoint and binds its exact pointer. That transcript contains
the projected row/plan/experiment, dataset-at-read SHA, best final JMW1 SHA,
and exact ordered contiguous trials; it requires exactly one promoted best
execution, finite values, and completion-equal trial/update/objective evidence.
Store re-admission binds those bytes before the tuning row is eligible. Phase
`14` publishes browser sweep
controls/frontier state over the daemon's at-least-once `TuneHandler`. The
current proto mirror covers local text command
envelopes plus proto3-compatible byte envelopes for the command and event
oneofs.

## Report-Card Measurements

The intended reporting boundary derives workload measurements from the typed
journals produced by the scenarios that actually ran. The current `--live`
layer still launches separate post-test probes and represents optional results
through the legacy absent / `MeasurementUnavailable` /
`MeasurementAvailable Text` surface. Sprint `34.3` owns replacing those probes
with journal-bound `NotRequested`, reasoned `Unavailable`, and `Available`
evidence. Reporting must not substitute fixtures or treat those probes as Phase
`12` completion evidence. See
[Evidence Journals and Reporting](run_contract.md#evidence-journals-and-reporting).

There is no cross-substrate parity field: the determinism contract is
within-substrate bit-for-bit only, and cross-substrate equivalence is not
asserted. Numerical values are never committed as fixtures.

### Worked Example

The `Some Tuning::{ … }` Dhall constructor matches the worked example in
[../README.md → Concrete `Some Tuning::{ … }`
example](../../README.md#concrete-some-tuning--example).

## Cross-References

- [../../README.md → RL framework primitives](../../README.md#rl-framework-primitives)
- [../../README.md → RL algorithm catalog](../../README.md#rl-algorithm-catalog)
- [../../README.md → AlphaZero-style self-play and persistent MCTS state](../../README.md#alphazero-style-self-play-and-persistent-mcts-state)
- [../../README.md → Hyperparameter tuning, first-class](../../README.md#hyperparameter-tuning-first-class)
- [numerical_core.md](numerical_core.md)
- [checkpoint_format.md](checkpoint_format.md)
- [daemon_architecture.md](daemon_architecture.md)
- [run_contract.md](run_contract.md)
- [Legacy Phase 8: Supervised and RL Framework](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 9: RL Catalog, AlphaZero, and Tuning](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 13: No-Caveat Model Runtime](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 14: Interactive Demo and Playwright Closure](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
