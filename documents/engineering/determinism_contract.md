# Determinism Contract

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: README.md, ../documentation_standards.md, ../../DEVELOPMENT_PLAN/README.md, ../../DEVELOPMENT_PLAN/00-overview.md, ../../DEVELOPMENT_PLAN/system-components.md, ../../DEVELOPMENT_PLAN/phase-0-planning-documentation.md, ../../DEVELOPMENT_PLAN/phase-7-jit-codegen-and-substrates.md, ../../DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md, ../../DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md, ../../DEVELOPMENT_PLAN/phase-12-test-stanzas-and-cross-cluster.md, ../../DEVELOPMENT_PLAN/phase-23-general-differentiable-layer-engine.md, ../../DEVELOPMENT_PLAN/phase-262-contract-driven-live-execution-browser-and-playwright.md, checkpoint_format.md, jit_codegen_architecture.md, training_workloads.md, unit_testing_policy.md, run_contract.md
**Generated sections**: none

> **Purpose**: Project-specific bit-determinism contract for jitML — the per-
> substrate floating-point semantics, the RNG split and per-experiment seed
> derivation, the JIT cache content-addressing, and the engine envelope shape.

## Current Status

**Implemented today.** Supervised served determinism runs through the reloaded
typed `LayerGraph` executed directly by `LayerGraph.runLayerGraph` (Phases
`237`–`239`); the historical exact-V2 structural-operation ABI has been
removed. Checkpoint content addressing now covers the exact outer bytes of one
self-describing `RawCheckpointEnvelope`; its typed body is either weight-only
or supervised-graph. The frozen V1 and parallel V2/V3 checkpoint wires are
retired.

**Target, not yet true — cross-lane MLP agreement.** The contract below
guarantees *same-substrate* bit-equality and deliberately asserts no
cross-substrate numeric equivalence. The two **Linux** lanes are a narrower case
where agreement *is* the design: `src/JitML/Codegen/MlpOneDnn.hs` declares its
batched parameter-gradient reduction "matches the CUDA batch-grad reduction
order", and `src/JitML/Engines/Engine.hs` passes `--fmad=false` to nvcc solely to
stop FMA contraction rounding differently from the oneDNN lane. They do not
currently agree: the accumulation loops match, but the activation does not —
oneDNN evaluates `std::tanh` and CUDA evaluates `tanhf`, two implementations of
one function, so the gradients differ at fp32 ulp scale. Aligning them is an
owned deliverable of
[Phase 265](../../DEVELOPMENT_PLAN/phase-265-cuda-row-device-evidence.md), which
also adds the standing cross-lane bit-identity assertion; the `apple-silicon`
lane remains outside any cross-substrate numeric claim.

## The Contract

jitML guarantees **same-substrate bit-equality** when the same numerical path is
repeated on `<substrate>` against the same toolchain pin (every
codegen-toolchain fingerprint from `cabal.project` plus the
substrate-specific kernel-compiler version). Supervised reconstruction (Phase
`239`) serves the reloaded typed `LayerGraph` through the pure reference
executor, over the same frozen graph-ordered parameters, so the training-returned
and Store-loaded *serving* paths are one implementation rather than two.

**Training and serving are not the same implementation today.** Supervised
training on a real substrate device executes oneDNN `float32` kernels, while
serving executes the pure `Double` reference executor, so a `float32`-versus-
`Double` skew exists between the trained result and the served result. Phases
`233`, `241`, and `79` own closing this: see
[Phase 241](../../DEVELOPMENT_PLAN/phase-241-onednn-device-training-kernels-for-correct-operators.md)
for the device-lowering obligation. This paragraph states the current contract,
not a target. Cross-substrate bit-equality is **not** guaranteed
— RNG draws and float reduction order differ across substrates — and
cross-substrate equivalence is **not asserted**: there is no cross-substrate
numeric-parity check or tolerance band.

Reproducibility is an architectural invariant, not a debugging aid. The
contract holds across:

- parameter initialization (seeded by the experiment Dhall),
- canonical supervised learning rate (finite and positive, included in the
  ProductRow descriptor and semantic `PlanId`, then passed unchanged as `3e-3`
  for `fashion-mnist-resnet`, `1.1e-3` for `cifar10-resnet20`, `1.5e-3` for
  `cifar10-vit`, or `1e-3` for the other eight supervised rows),
- the current `cifar10-vit` fixed plan (2,000 training examples, forty epochs,
  batch size 128, 80,000 processed examples, and 640 successful optimizer
  updates),
- canonical supervised classification minibatch ordering (for each one-based
  epoch, the trainer derives a SplitMix stream from the classifier seed and
  epoch, pairs one word with every whole training example and its original
  zero-based index, stable-sorts ascending by `(word, originalIndex)`, and only then
  partitions that permutation into contiguous mini-batches),
- split isolation (only the already-materialized classification training
  partition is permuted; validation and test partitions remain in their fixed
  decoded order, and the tuning exact-update path retains its fixed-order batch
  cycle),
- optimizer state (numerical updates are deterministic),
- RL trajectories (env reset and step are seeded),
- MCTS exploration paths (per-node-expansion seed is derived
  deterministically),
- hyperparameter-trial selection (sampler state is reproducible),
- checkpoint recovery (the `.jmw1` decode + manifest reload restore identical
  state).

## Run-Protocol Determinism

The raw-to-validated workflow boundary is specified by
[Typed Run Contract](run_contract.md). Canonical plan encoding produces the same
`PlanId` for the same resolved inputs. Semantic event IDs derive from the plan,
event kind, and event key rather than broker arrival order or a client-supplied
payload hash.

Evidence reducers are pure folds over exact keyed collections. Permuting valid
delivery order or replaying an identical event produces the same progress and
completed evidence; conflicting duplicates and gaps are typed violations. The
deterministic evidence projection excludes broker receipts, wall-clock timing,
process duration, and cleanup timestamps. Those remain observable journal data
but are not inputs to numerical results, plan identity, checkpoint hashes, or
same-substrate equality assertions.

## Checkpoint GC Determinism

Checkpoint retention is independent of object-discovery order. Candidate
manifests are content-addressed and deduplicated by manifest SHA; `LastN` ranks
them by `(step descending, manifest SHA ascending)`, roots and kept identities
are sorted, and each payload object belongs to exactly one deterministic
snapshot namespace. The `snapshot-id` is
`sha256(canonical-CBOR("jitml-snapshot-v1", exact logical manifest,
sorted(original-key,payload-sha)))`; every tensor, optimizer, RNG,
replay/transcript companion, and substrate-artifact body is stored at
`snapshots/<snapshot-id>/objects/<sha256(original-full-key)>`. Each unique
`reservations/<attempt-id>.cbor` marker and the attempt-independent commit bind
that identity, the addressed manifest, and the sorted canonical-original →
exact-scoped → payload-SHA descriptor. Validation reverses the mapping to
reconstruct the logical manifest and re-derives `snapshot-id`; the common scoped
prefix is not trusted as identity. The
attempt id affects only marker ownership; it does not enter snapshot or commit
identity. No discovery order, wall clock, or process-local identifier
participates in the snapshot namespace.

The immutable writer order is coordinated by the durable `ExperimentGcFence`
at `jitml-checkpoints/<experiment-hash>/gc/coordination-fence.txt`. Its
canonical value carries a format version, bound experiment hash, monotonic
CAS revision, a separate monotonic writer/root-activity epoch, canonical full
active `WriterReservation` set, and canonical `GcFenceDecision` history. Every
reservation register/unregister increments the writer/root-activity epoch;
GC-only decision changes increment the revision but not that epoch. Absence for an event is `Open`; recorded phases are
`Planned(g,event)`, `Cancelling(g,event)`, `Cancelled(g,event)`,
`Executing(g,event)`, and permanent `Reaped`. Generations are contiguous from
zero through the latest, all prior generations are complete `Cancelled`, and
every generation binds the same byte-identical semantic intent. Only the latest
generation may be nonterminal or destructive. Experiment scope is required
because a child writer can protect a GC target in another snapshot through
`parentManifestSha`; independent per-snapshot locks cannot make that
cross-snapshot overlap atomic.
The CAS value is exactly `jitml-experiment-gc-fence-v1:` followed by lowercase
hexadecimal canonical CBOR; noncanonical text or CBOR is invalid state.
GC brackets every complete fresh root view with matching writer/root-activity
epoch observations and may move `Open` or complete `Cancelled` to `Planned`
only at that exact epoch. A GC-only revision for a sibling event therefore does
not invalidate the witness. The live reconciler converges the complete view in
a bounded loop: epoch churn restarts it, and an epoch-stable plan that discovers
an exact event absent from durable intent state persists the canonical intent
and restarts the entire view before authorization. Terminal ready/published
work first observed in the fresh view is completed and also restarts the view;
permanent published-only state is already current.

A writer selects a fixed-width lowercase-hex attempt id and CAS-registers its
full reservation before creating the separate absent-only per-attempt marker.
The registration transition inserts the reservation and atomically changes
every overlapping `Planned` event to `Cancelling`; an overlapping `Executing`
or `Reaped` event rejects the writer before marker creation. Before marker
creation or payload mutation, the writer helps every overlapping `Cancelling`
event by durably writing its byte-identical immutable cancellation artifact and
CASing it to complete `Cancelled`, without removing its semantic intent. The
intent and cancellation artifact may remain physically present across
generations; the latest exact fence phase determines logical activity, and a
delayed old helper can only repeat the same idempotent PUT. Marker conflicts still advance
the counter, so attempts never share a marker and need neither RNG nor a lease. A conflicted
attempt does not unregister its reservation: ownership of the already-present
marker cannot be proved, so the entry remains a conservative permanent root.
A resumed attempt likewise leaves an already-registered exact reservation key
in place and advances to a freshly registered attempt rather than replacing or
removing it. Only after fence registration, cancellation settlement, and marker
creation may snapshot-owned
payload objects and the manifest be written. A candidate writes the
attempt-independent commit next. A completed writer performs mutable pointer CAS
before that commit; a pointer that temporarily names an uncommitted snapshot is
ineligible and fails admission closed. Successful cleanup deletes only the
attempt's own marker and then CAS-unregisters its fence entry, in that order. A
crash can therefore leak a marker, an entry, or both; every leak remains a GC
root even after another attempt completes the matching commit. Commit never
overrides leaked protection, and a retry cannot remove state it does not own.

For a zero-payload-object logical manifest, the binding list is empty and the
same function deterministically yields
`sha256(canonical-CBOR("jitml-snapshot-v1", exact logical manifest, []))`.
Store derives the expected commit address from that identity rather than a
payload-object-key prefix. An exact matching `committed.cbor` enables admission,
retention, and GC and is the snapshot's sole GC-owned key. Without that commit,
a legacy empty manifest remains protected, ineligible, and available only for
decode/inspection; emptiness alone is never an admission proof.

Every durable GC intent carries a stable `event_id` derived from the
experiment, manifest SHA, step, and sorted unique exact snapshot-owned deletion
keys. Those keys belong to one snapshot namespace and contain exactly one
`committed.cbor` plus its payload-object keys; a zero-payload-object snapshot
therefore has one deletion key and reports `reaped-objects=1`. Discovery
order, substrate, completion time, broker receipt, and retry count do not enter
that identity. Coordination-record revision, execution generation, and helper
operation identity also do not change the semantic event or its broker payload.
Before an intent can execute, the reconciler brackets its recomputation of the
complete committed snapshot and live-root view from manifests, mutable pointer
bodies, browser-catalogue and intrinsic roots, writer reservations, the
experiment CAS fence, and durable intent/cancelled/ready/published state with
matching observations of the fence's monotonic writer/root-activity epoch. If
the epoch changes, or if an epoch-stable plan discovers and persists an exact
missing durable intent, the bounded convergence loop restarts that whole view.
Only the converged plan supplies the kept set and no-op decision. It
CAS-transitions an exact freshly revalidated event from `Open` or complete
`Cancelled` to `Planned(g,event)` only at that exact epoch; GC-only sibling
revisions do not invalidate the witness. It may move it to `Executing(g,event)` only while no active
reservation overlaps it. A writer racing a planned event wins by atomically
inserting its full reservation and changing that event to
`Cancelling(g,event)`. A coordinator, writer, or helper settles cancellation by
durably writing the byte-identical immutable
`gc/cancelled/<event-id>.cbor` and only then CASing `Cancelling(g,event)` to
complete `Cancelled(g,event)`, without deleting the semantic
`gc/intents/<event-id>.cbor`. Re-arm is forbidden until cancellation is
complete; that cancelled generation can become `Planned(g+1,event)` only after
its roots and markers are gone and a new exact epoch is witnessed. The stable
intent and cancellation artifact can span generations; the latest exact fence
phase is authoritative, so a late old-generation helper has no
generation-sensitive side effect. Helpers must re-read the exact `Executing` state before
obtaining the opaque authorization consumed by deletion. Store exposes
`executeAuthorizedGcIntents` as the only destructive execution API; no plan or
raw-intent compatibility execution remains. An absent target manifest is
recoverable only when the latest fence decision binds the byte-identical intent
in `Executing` or permanent `Reaped`; absence alone never authorizes deletion. After complete
execution they CAS it to permanent `Reaped`. Durable cancellation records are
not physically retired by authorization, and semantic-intent cleanup occurs
only after `Reaped` during ready/published terminal handling. The event's unique
snapshot namespace still scopes every authorized deletion key, but the
experiment CAS transition — not a process-local lock or a pair of listings — is
the stale-executor exclusion proof.

Substrate and completion timestamp are fixed in the first publish-ready record,
so recovery deterministically reconstructs the same broker payload and routes
it through the substrate stored in that record, not whichever cluster happens
to run the retry. The broker text form is
`jitml-gc-reaped-event-protobuf-hex-v1:` followed by lowercase hexadecimal of
the canonical protobuf bytes. Decode rejects noncanonical protobuf, forged
event/manifest identities, a key set without exactly one snapshot and one
commit, noncanonical or unsafe keys, aliases, traversal,
control characters, reserved control namespaces, and cross-experiment keys.

A permanent published tombstone is checked before and after ready promotion.
After Pulsar acknowledges publication, the tombstone is persisted before the
ready record is removed. A crash before broker acknowledgement may cause the
same stored payload to be retried at least once; a crash after tombstone
persistence cannot manufacture a second timestamp or republish that event.
See
[Checkpoint Format → Retention and GC](checkpoint_format.md#retention-and-gc).

For supervised training, the canonical plan deterministically derives the
required mini-batch update budget, but that projection is not treated as an
observation. The successful trainer return owns
`tmOptimizerUpdatesExecuted`, records it only after all requested epoch/batch
loops complete, and carries it unchanged through Writer, Product Publisher,
`CompletedTraining`, and the supervised-graph body in the single checkpoint
envelope. Every boundary requires exact equality with the plan-derived count.
An interrupted or failed run cannot manufacture a successful counter by
recalculating the plan after the fact.

The supervised-graph payload's composite origin is itself deterministic
identity. Product publication binds the payload row and
`RawProductRowProjectionOrigin` to one supported-substrate projection. Generic
supervised publication embeds
`RawGenericSupervisedExecutionOrigin(rowId, canonicalPlanTransport)`; decode
requires that row to equal the payload and authoritative canonical problem row,
reparses the exact versioned `SupervisedPlan`, requires its canonical rendering
to equal the stored text byte-for-byte, and derives the same `PlanId`, substrate,
experiment, budget, and seed. `PlanId` alone never binds canonical row
semantics. Origin choice is closed and explicit, so a loader cannot make
identical bytes mean ProductRow evidence in one context and generic evidence in
another. Because there is now one self-describing envelope, both payload
variants — weight-only and supervised-graph — derive their content address from
the exact final outer-envelope bytes; the byte-frozen V1 golden that pinned a
separate weight-only fingerprint is retired, and checkpoints are regenerated
deterministically from current source rather than reinterpreted. See
[Checkpoint Format → The Self-Describing Checkpoint Envelope](checkpoint_format.md#the-self-describing-checkpoint-envelope).

That generic seed is executed, not merely hashed or persisted. The supervised
entrypoint requires exactly one plan seed, rejects platform-`Int` overflow, and
uses it for parameter initialization and deterministic classification epoch
ordering. Local generic experiment identity combines the Dhall path with
canonical row/dataset/model, substrate, seed, epoch/training/evaluation/batch
budgets, and consequently the derived update budget. Changing any one changes
the experiment and semantic `PlanId`.

Dataset identity is equally closed. Single-envelope supervised-graph decode
derives the canonical digest of the row's exact pinned training/evaluation
reads and requires the runtime, manifest, and `CompletedTraining` fields to
equal it. Replacing all persisted copies with the same forged digest is
deterministic forgery, not admission.

Completed-checkpoint event order is deterministic with respect to Store
adoption: a live writer reads the current pointer ETag (the local writer reads
the corresponding current-body expectation), CASes that expectation, and
requires `PointerWritten` for the exact stored manifest before publication.
The ETag is concurrency state rather than numerical identity, but a conflict
cannot be rendered as a completed event for an unadopted manifest.

The canonical classification epoch permutation changes order, never work. It
retains every whole labeled training example exactly once per epoch, so the
authoritative training-example quantity, batch-example quantity, number and
sizes of batches, `slmExamplesProcessed`, and
`tmOptimizerUpdatesExecuted` remain unchanged. Validation-driven model
selection and held-out test measurement consume their original unpermuted
partitions. Hyperparameter tuning deliberately continues to call the
fixed-order selected trainer; introducing the canonical ProductRow shuffle does
not silently alter trial/rung replay.

Tuning and AlphaZero make that identity boundary concrete. Their raw commands
refine to canonical version-`1` `TuningPlan` / `AlphaZeroPlan` transports whose
`PlanId` covers the selected axes, game, substrate/placement, seed cohort, and
every dimension-specific budget. Local execution, Linux worker mounts, and
Apple host commands consume the same plan. Tuning schedules deterministic
parallel cohorts from the resolved width, gives every trial an explicit
pruned/promoted disposition, and requires the sweep's promoted count to equal
the plan. Tuning completion is keyed by the exact zero-based trial range plus
one sweep result; AlphaZero completion is
keyed by the exact zero-based generation range plus one arena result. Delivery
permutation therefore cannot change which trials or generations satisfy the
run, and worker count or arrival order cannot silently change the budget.

## Per-Substrate Floating-Point Semantics

Per [../README.md → Substrates and runtime
modes](../../README.md#substrates-and-runtime-modes), each substrate carries its
own floating-point determinism contract.

### `apple-silicon` (Metal)

- Metal compute kernels execute on the host GPU.
- Float-accumulation order is fixed by the kernel's reduction tree (no
  `-ffast-math`).
- Generated metadata reports output-count policy, threadgroup size, bridge ABI,
  source hash, and safe math mode so host buffers are sized from the same
  renderer that supplies the MSL.
- Metal compute kernels are compiled at runtime by the fixed host bridge via
  `MTLDevice.makeLibrary(source:options:)` with fast math disabled, then executed
  on the host GPU through the OS Metal framework. Determinism is fixed by the
  shader source, fixed bridge ABI, safe math option, and single-stream launch
  policy. `JitML.Engines.MetalRuntime` probes host Metal device visibility and
  the bridge probe gates execution; the core path does not require SwiftPM,
  `swiftc`, `xcrun metal`, Tart, full Xcode, or keychain state. See
  [jit_codegen_architecture.md → Apple Silicon Fixed-Bridge Metal JIT](./jit_codegen_architecture.md#apple-silicon-fixed-bridge-metal-jit).
- RNG state lives in the host daemon (`Host + SelfInference`).
- Kernel-launch ordering is single-stream by default. Single MTLCommandQueue
  with FIFO ordering; explicit barriers prevent kernel reordering.
- **Tradeoff**: single-stream launch forfeits the multi-stream concurrency
  that hides launch latency at small batch sizes — the throughput cost is
  real and is the price of the bit-determinism contract.

### `linux-cpu` (oneDNN)

- oneDNN dispatches to a per-host vector ISA detected at JIT time through
  typed subprocess probes (AVX2 baseline, AVX-512 detected and used when
  available).
- The production Linux CPU path uses generated C++ that includes oneDNN
  headers, links `-ldnnl`, and launches oneDNN primitives through the stable
  `jitml_kernel` FFI ABI.
- The oneDNN runtime/link availability probe checks `pkg-config` package
  metadata, readable oneDNN headers, and dynamic-linker `libdnnl` visibility.
- Reductions are blocked with a fixed block size so the accumulation tree is
  host-independent. The size is one constant,
  `JitML.Codegen.OneDnn.oneDnnFixedReductionBlock`: the renderer emits it into
  the generated source and the fingerprint reads it, so a block-size change
  invalidates the cache key by construction rather than by convention.
- RNG state lives in the clustered service pod.

### `linux-cuda` (CUDA C + cuBLAS / cuDNN)

- CUDA kernels are compiled without `--use_fast_math`: the flag is **omitted**
  rather than passed with a `false` value, because modern nvcc rejects that
  spelling and absence is off. `--fmad=false` *is* passed explicitly, which
  suppresses FMA contraction so a multiply-add rounds twice as the oneDNN lane
  does; without it the sub-ULP skew changes RL convergence materially.
- Per-block reductions in the generated **family** reduction kernel use a
  deterministic warp-shuffle pattern, emitting one partial per warp and avoiding
  device-side atomics; the trainer MLP kernel instead reduces sequentially
  per thread, as described in the cuBLAS/cuDNN bullet below;
  `JitML.Engines.CudaRuntime` validates the expected partial count and
  accumulates partials on the host in canonical index order.
- Generated CUDA artifacts expose a host-callable
  `jitml_kernel(float*, const float*, size_t)` FFI wrapper. The wrapper owns
  device-buffer allocation, input copy, deterministic device-kernel launch,
  synchronization, and output copyback before the Haskell side observes the
  result.
- cuBLAS and cuDNN are pinned to deterministic algorithm selections via
  `cudnnSetConvolutionMathType` plus explicit algorithm-id pinning. The
  cuDNN algorithm-id selection is restricted to the deterministic-only set.
  This pinning governs the generated **family** kernels (Conv2D / MHA / pool /
  norm), which are the only surface that dispatches through cuBLAS/cuDNN. The
  executed RL/SL trainer MLP device path does **not** use cuBLAS: it is the
  hand-written `JitML.Codegen.MlpCuda` kernel, whose determinism comes from a
  sequential per-thread reduction with no device-side atomics, so it is
  bit-deterministic without any library algorithm-id pinning.
- RNG is the host's SplitMix64 stream from `JitML.Engines.Rng`, never the GPU's
  curand. Generated CUDA source records the `host-splitmix64-no-curand` policy
  in the rendered source payload.
- **Tradeoff**: cuDNN's deterministic convolution algorithms are typically
  20–50% slower than the non-deterministic defaults on training workloads;
  this is the price of the bit-determinism contract. It is paid only on the
  surfaces that call cuDNN — the family kernels and the Sprint `264.1`
  layer-graph arm — not on the trainer MLP path.

## Supervised Serving via the Reloaded Graph

Phase `239` retired the exact V2 structural runtime. A supervised checkpoint's
sole served representation is its trained typed `LayerGraph`, persisted as
`architectureLayerGraph` metadata. There is no persisted or executed structural
layer-operation program, no per-substrate `RuntimeBackendExecutor`, and no
generated `RuntimeOperations{Cpu,Cuda,Metal}` bundle; those surfaces are deleted.

Serving reconstructs the trained `LayerGraph` from its metadata, injects the one
physical graph-ordered `supervised.weights` blob as the parameter vector, and
runs the graph through the pure reference executor
`LayerGraph.runLayerGraph`. The exact input/output transforms — feature
standardisation / unit-image ingress and the semantic-prefix / destandardize
egress — ride OUTSIDE the graph and are applied as pure deterministic functions
before and after the graph run
(`RuntimeArtifact.executeSupervisedGraphRuntime`). Selected-substrate validation
still uses the plan resolved from the persisted closed origin: the unique
ProductRow projection for product publication or the canonically reparsed exact
`SupervisedPlan` for generic publication; it never guesses substrate from a row
label or switches origins during replay.

Admission anchors the one physical `supervised.weights` blob's length to the
trained graph's parameter count (`layerGraphMetadataParameterCount`) and binds
the final-weight SHA-256 to the completed-training witness. Its snapshot-scoped
physical key is accepted only when it is the exact derivation of the canonical
logical `blobKey(experiment, final-jmw1-sha)`; an arbitrary key under the same
snapshot prefix is not equivalent. Because serving is a
pure deterministic function of the reloaded graph and input, the training-returned
and Store-loaded *serving* paths are the same reference executor over the same
frozen parameters, so there is no structural-ABI reimplementation between them.
The training path itself runs device `float32` kernels rather than that executor;
the resulting trained-versus-served skew is stated once in
[The Contract](#the-contract) and is not restated here.

## RNG Split and Per-Experiment Seed Derivation

The master seed is declared in the experiment Dhall. Per-experiment seeds are
derived deterministically by `JitML.Engines.Rng.deriveSplitMixSeed`:

```
experimentSeed = splitmix64(masterSeed, experimentIndex)
```

Canonical classification training uses the same host SplitMix implementation.
For one-based epoch `e` and classifier seed `s`, it computes exactly:

```
epochWords = splitMixWords(
  length(trainingPartition),
  deriveSplitMixSeed(SplitMixSeed(fromIntegral(s)), fromIntegral(e)))
epochOrder = stableSortAscending(zip(epochWords, [0..], trainingPartition),
                                 key = (word, originalIndex))
```

The original index is an explicit deterministic collision tie-breaker. No
feature bytes, labels, validation/test examples, worker arrival order, or
wall-clock values enter the key, and the permutation is formed only after the
authoritative training partition has been fixed.

For multi-game / multi-environment workloads (RL self-play, AlphaZero), the
per-game seed derivation is:

```
perGameSeed = splitmix64(experimentSeed, gameIndex)
```

This makes per-game output independent of worker count, scheduling order, and
worker-to-game assignment. The same property holds for hyperparameter trial
seeds and for the MCTS root-noise seed in AlphaZero.

## JIT Cache Content-Addressing

The JIT cache key is the six-tuple

```
sha256(canonical-cbor(KernelSpec) || kind || substrate || toolchain-fingerprint || rendered-source-payload || tuning-choice)
```

where:

- `KernelSpec` is the typed model shape (layer topology, dtype layouts,
  activation choices, optimizer + loss when `kind = Training`).
- `kind` ∈ `Training | Inference`. Training and inference kernels are
  separate artefacts — training carries the backward pass plus optimizer-
  step kernel; inference is forward-only with frozen-weight constant folding
  enabled.
- `substrate` ∈ `apple-silicon | linux-cpu | linux-cuda`.
- `toolchain-fingerprint` is a rendering of `ToolchainFacts`
  (`src/JitML/Engines/Fingerprint.hs`) whose every field is derived from the
  surface it describes: the compiler, its hash-free compile flags, and its link
  line come from `Engine.engineCompiler` / `engineCompileFlags` /
  `engineLinkFlags` — the same lists the compile command passes; the determinism
  knobs from `deterministicFlags`; the ABI from a typed `AbiKind` carrying
  `metalBridgeAbiVersion` on Apple; the numeric knobs from the renderers' own
  constants; the entry points from one shared list per ABI; and the emitter set
  from the vocabulary the artifact covers. A flag, link-line, bridge-ABI,
  reduction-block, threadgroup-size, or operator-vocabulary change therefore
  invalidates the artifact automatically, rather than depending on someone
  re-syncing prose. Every fingerprint carries `artifact-abi=<os>-<arch>`, so
  Darwin host artifacts and Linux container artifacts never share a cache key.
  The Apple fingerprint declares the fixed-bridge ABI and names the MSL kernels
  its `.metal.json` artifact defines; it does not claim a host C ABI, because
  the artifact is source metadata and exports no C symbols.
- `rendered-source-payload` is the canonical Haskell-rendered source bundle
  produced by `renderRuntimeSource`.
- `tuning-choice` is the selected auto-tuning choice.

A change in any input invalidates the cache key, so a re-JIT is
substrate-explicit and toolchain-explicit.

## Engine Envelope

The current local `EngineEnvelope` in `src/JitML/Engines/Engine.hs` captures
the kernel handle, input/output shape metadata, deterministic flag list, and
compile command for deterministic inspection. `JitML.Engines.Loader` records
whether that compile command was actually executed for the current cache lookup
or whether an existing content-addressed artifact was reused. Target checkpoint
manifests carry a richer typed `EngineEnvelope` block with substrate-specific
reproducibility witnesses:

| Substrate | Envelope fields |
|-----------|-----------------|
| `apple-silicon` | GPU device id, Metal version, fixed bridge ABI/version, Metal runtime policy, MSL source metadata hash |
| `linux-cpu` | Detected ISA (AVX2 / AVX-512), oneDNN version, glibc version, CPU model |
| `linux-cuda` | cuDNN version, cuBLAS version, CUDA driver version, GPU compute capability, NVCC version |

The envelope is **not** part of the cache key — two runs with equal envelopes
(same substrate, same toolchain) should produce bit-identical kernel output by
the within-substrate contract. The envelope is the forensic record consumed by
checkpoint/inference tooling to detect substrate drift rather than silently
displaying ULP-shifted floats as if they were the originator's. It is not a
cross-substrate numeric-parity check: across substrates no equivalence is
asserted.

This within-substrate-only contract is the numerical rationale for the project's
[Substrate-affinity phasing](../../README.md#substrate-affinity-phasing)
doctrine: because cross-substrate equivalence is out of contract, no development
phase gates on two accelerators at once — each accelerator lane's
within-substrate reproducibility is validated on its own host, and the
development plan binds this as
[`DEVELOPMENT_PLAN/development_plan_standards.md` rule M](../../DEVELOPMENT_PLAN/development_plan_standards.md).

## Same-Substrate Bit-Equality (RL Caveat)

For off-policy RL algorithms (DQN, DDPG, TD3, SAC, CrossQ, TQC), full-run
determinism is sensitive to scheduler order: the replay-buffer write
discipline is `Async`, so two same-substrate same-seed runs may differ in
which step pulls a particular sample. The bit-equality anchor for
off-policy algorithms is therefore the **first-N-steps prefix** (default
`rl_steps / 10` per
[../../DEVELOPMENT_PLAN/system-components.md → POC Report-Card
Knobs](../../DEVELOPMENT_PLAN/system-components.md#poc-report-card-knobs)),
asserted by comparing two fresh runs against each other — never against
a stored trajectory file.

For on-policy algorithms (PPO, A2C, TRPO, MaskablePPO, RecurrentPPO),
full-run bit-equality holds.

For SL training, full-run bit-equality holds.

For AlphaZero self-play, per-game bit-equality holds: two same-substrate,
same-seed runs of Connect 4, Othello, Hex, and Gomoku produce identical
self-play game sequences and legal-action-masked MCTS visit-count vectors.
Othello forced passes are explicit deterministic transcript events, and MCTS
value backup changes perspective only when the player to move actually changes.
The checkpoint evidence
for each game records deterministic initial/final policy-value network hashes,
the self-play generation count, and an arena win-rate observation that clears
`JitML.RL.ConvergenceThresholds.alphaZeroArenaThreshold`; replay compares fresh
runs against each other, never against committed transcript fixtures.

The current local Phase 7 executable anchor proves the Linux CPU side of the
runtime contract: `jitml-backends` runs the Linux CPU oneDNN reorder,
reduction, matmul, convolution, normalization, attention, and embedding kernels
through `JitML.Engines.Local`, verifies the loaded artifact reports the expected
`jitml_kernel_family_name` and `jitml_kernel_output_count`, and asserts
repeated identity-kernel output is bit-identical. It also exercises the local
Linux CPU `HasEngine` interpreter over the generated-family FFI path and
measures the Linux CPU benchmark candidate runner against generated FFI output
while recording a deterministic output digest. The generated CUDA source bundle
now exports the same `jitml_kernel` / family / output-count ABI and the guarded
`JitML.Engines.CudaLocal` runner consumes a positive CUDA runtime probe before
compile/load/launch; in unavailable environments it fails closed before compile.
Apple Metal source metadata carries the same family/output-count contract for
the fixed bridge. The live Apple backend lane and live CUDA lane exercise these
runtime proofs on matching hardware.

## Layer-Graph Gradient Determinism

The Phase `23` typed layer graph keeps the same within-substrate contract. The
pure oracle in `JitML.Numerics.Autodiff` is deterministic because the forward
tape records nodes in graph order, the backward pass replays them in reverse
order, all row-major parameter tensors are traversed in stable index order, and
seeded parameter initialization uses a fixed `StdGen` stream. Dropout in the
Sprint `23.1` oracle is represented as a deterministic train/inference scaling
node; stochastic masks belong to later substrate kernels only when their seed
and traversal order are explicit cache-key inputs.

`jitml-unit` asserts same-seed bit equality for a ResNet-shaped graph gradient
and finite-difference agreement — for **both** the parameter gradient and the
input gradient — for every layer kind in the graph catalog and for full
ResNet-shaped and ViT-shaped composed graphs. These
tests compare fresh computations, not committed numerical fixtures, preserving
the snapshot policy in
[unit_testing_policy.md](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).
Phase `23.2` extends this contract to oneDNN training-direction kernels; Phase
`23.3` extends it to serialized layer-graph checkpoints and inference replay.
The graph checkpoint metadata stores nodes in execution order and names
parameter tensors explicitly; reconstruction rejects missing, duplicate, or
shape-mismatched tensors, so a same-manifest reload restores the same graph
topology and row-major parameter vectors before the oneDNN forward runner
executes.

## Determinism Caveats

- **TensorBoard byte stream is not part of any bit-determinism check.** TF's
  `Event` message carries `wall_time`; shard boundaries depend on wall-clock
  flush thresholds; writer metadata varies across writer-ids. The scalar
  values themselves at each `(tag, step)` *are* deterministic — the test is
  to decode two fresh runs, project each to `[(tag, step, value)]`, sort
  canonically, and assert equality between the two run-derived sequences
  (no committed reference shard).
- **Pulsar message metadata varies across runs** (timestamps, broker-assigned
  message ids). Determinism applies to the durable message **body** only.
- **Wall-clock benchmark numbers are not reproducible.** The bit-determinism
  contract is on visit counts, model parameters, training transcripts, and
  inference outputs — not throughput. Per [unit_testing_policy.md → Snapshot
  Tests and the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures),
  no `.txt` / `.json` files of hardcoded latency, env-steps/sec, or
  gradient-updates/sec are committed; perf regression is detected by
  on-host comparison against a recent baseline computed during the same
  CI run, not by a stored fixture. `JitML.Engines.Tuning.benchmarkPlan`
  makes the candidate knob list deterministic, and `selectMeasuredTuning`
  makes selection deterministic for a fixed measurement set.
  `TuningBenchmark` collects candidate measurements in plan order and records
  output digests alongside latency before `TuningStore` persists the selected
  `TuningChoice` by substrate and base hash. Its CUDA/Metal runner entrypoints
  currently preflight runtime availability and fail closed before live FFI
  measurement, so no unavailable hardware path fabricates a timing result.
  `TuningCache` loads the persisted choice before deriving the final runtime
  source and cache key. The eventual hardware timing loop may produce different
  measurements across machines, and that selected `TuningChoice` becomes an
  explicit cache-key input.

## Metamorphic and Differential Test Discipline

Bit-determinism proves a computation is *reproducible*, not that it is *real*: a
fabricated kernel that returns a fixed buffer is perfectly bit-deterministic.
Reproducibility is therefore paired with a metamorphic/differential discipline
that a stub cannot satisfy. The pure gate-soundness slice owned by
[Phase 276](../../DEVELOPMENT_PLAN/phase-276-negative-control-suite.md) makes
`jitml-negative-controls` reject hand-built known fakes and requires
`pendingProductionControls` to remain non-empty. It does not by itself exercise
production requests, events, journals, reducers, lifecycle failures, or every
ProductRow. The production-path owners are
[Phase 279](../../DEVELOPMENT_PLAN/phase-279-runcontract-negative-controls-request-and-event-fixtures.md),
[Phase 280](../../DEVELOPMENT_PLAN/phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md),
and [Phase 281](../../DEVELOPMENT_PLAN/phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md),
as specified further in [unit_testing_policy.md](unit_testing_policy.md). Their
current status and validation evidence live only in the development plan.

The standing discipline includes these invariants; the pure gate covers the
known-fake boundary where applicable, while the production owners cover the
production-bound comparisons:

- **Differential (conv ≠ dense; retained pure gate).** On a structured input
  where a convolution and a dense layer must disagree, the convolution engine's
  output must differ from the dense engine's output. A dense layer mislabelled
  as a convolution — which is bit-deterministic and passes shape checks — is
  *rejected* by this assertion, not accepted.
- **Metamorphic provenance (trained greedy == served; production-bound).** A
  trained policy's greedy rollout must equal the rollout produced from the
  *served checkpoint* of that same policy. The reported RL number is recomputed
  from the served artifact rather than read from a stored scalar, so served
  weights that do not reproduce the trained rollout fail provenance binding.
- **Metamorphic ordering (trained > random; production-bound).** That same
  trained-policy greedy rollout must out-score a random-policy rollout on the
  same seeded environment. A policy whose rollout does not beat random has not
  learned, however reproducibly it replays.
- **Ablation sensitivity (delete the expert; production-bound).** Deleting the
  expert controller must *change* the reported RL number. If removing the
  controller leaves the metric unchanged, the number was being produced by a
  scripted stand-in rather than the learned policy, and the negative control
  fails.

The production form of these behavioral invariants compares fresh computations
(conv vs dense, trained-greedy vs served, trained vs random, with-expert vs
without) in-run rather than stored fixtures, consistent with the snapshot
policy in
[unit_testing_policy.md → Snapshot Tests and the Prohibition on Numerical Fixtures](unit_testing_policy.md#snapshot-tests-and-the-prohibition-on-numerical-fixtures).
This durable list defines the required distinctions; dated closure evidence and
current phase status remain in the owning development-plan files.

## Cross-References

- [../../README.md → Substrates and runtime modes](../../README.md#substrates-and-runtime-modes)
- [../../README.md → Bit-determinism contract](../../README.md#bit-determinism-contract)
- [jit_codegen_architecture.md](jit_codegen_architecture.md)
- [checkpoint_format.md](checkpoint_format.md)
- [run_contract.md](run_contract.md)
- [Legacy Phase 7: JIT Codegen and Per-Substrate Execution](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [Legacy Phase 12: Test Stanzas, Lint Matrix, Live Workflow Matrix](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
- [../../DEVELOPMENT_PLAN/phase-276-negative-control-suite.md](../../DEVELOPMENT_PLAN/phase-276-negative-control-suite.md) — retained pure `jitml-negative-controls` gate-soundness scope
- [../../DEVELOPMENT_PLAN/phase-279-runcontract-negative-controls-request-and-event-fixtures.md](../../DEVELOPMENT_PLAN/phase-279-runcontract-negative-controls-request-and-event-fixtures.md) — blocked production request/event controls
- [../../DEVELOPMENT_PLAN/phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md](../../DEVELOPMENT_PLAN/phase-280-runcontract-negative-controls-journal-fixtures-and-reducer-p.md) — blocked journal/reducer controls
- [../../DEVELOPMENT_PLAN/phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md](../../DEVELOPMENT_PLAN/phase-281-runcontract-negative-controls-lifecycle-and-per-row-registra.md) — blocked lifecycle and per-row controls
