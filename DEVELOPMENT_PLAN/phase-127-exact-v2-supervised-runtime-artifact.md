# Phase 127: Exact V2 Supervised Runtime Artifact

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Exact V2 Supervised Runtime Artifact. Single-session phase migrated from legacy Sprint 10.6 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 127.1: Exact V2 Supervised Runtime Artifact [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/Checkpoint/{Format,WeightCodec,Writer,Store}.hs`,
`src/JitML/Codegen/RuntimeOperations{Cpu,Cuda,Metal}.hs`,
`src/JitML/Engines/{Local,CudaLocal,MetalLocal,Loader,RuntimeOperations,RuntimeOperationsDevice,RuntimeOperationsCuda,RuntimeOperationsMetal}.hs`,
`src/JitML/Engines/Rng.hs`,
`src/JitML/SL/{Architecture,Classifier,Regression,RuntimeArtifact,TrainingExecution}.hs`,
`src/JitML/Product/{Completion,Matrix,Publisher}.hs`,
`src/JitML/{App,Service/Command}.hs`,
`test/unit/{Main,RegressionStandardization,RuntimeOperationsAccelerators,SupervisedCheckpointV2,SupervisedRuntimeArtifact}.hs`,
`test/integration/Main.hs`, `test/sl-canonicals/Main.hs`
**Docs to update**: `../documents/engineering/checkpoint_format.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`,
`../documents/engineering/determinism_contract.md`,
`../documents/engineering/jit_codegen_architecture.md`,
`../documents/engineering/apple_silicon_metal_headless_builds.md`,
`../documents/engineering/haskell_code_guide.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`

### Objective

The supervised runtime persists and reloads one byte-exact, topology-complete
V2 inference artifact before any completion or inference proof is admitted.
New supervised runtime writes use V2. A V2 artifact retains exact identities
for its final outer bytes and embedded canonical body bytes, stores exactly one
physical `supervised.weights` `.jmw1` payload, and describes node parameters as
graph-ordered virtual `Flat` slices into that payload. It is the complete
inference program actually executed by training, including preprocessing and
output decoding, not a generic-family or topology-free approximation.
Supervised V1 manifests remain decodable and inspectable but cannot be
inference eligible.

### Deliverables

- The V1 encoder and its golden bytes remain frozen for compatibility. Decode
  structurally dispatches V2, then V1, then the retained legacy form; after a
  form is structurally recognized, any validation failure is final and cannot
  fall through to another decoder.
- A V2 outer envelope carries the V2 version, the SHA-256 identity of the exact
  canonical embedded body bytes, and those body bytes. The checkpoint address
  is the SHA-256 identity of the exact final outer-envelope bytes. Address
  calculation and validation retain the fetched bytes and never substitute
  decode-and-re-encode equivalence.
- New supervised runtime writes persist the exact addressed V2 bytes and expose
  both exact identities without exporting a forgeable addressed-manifest
  constructor. Every supervised V2 manifest names exactly one physical tensor,
  `supervised.weights`, encoded as one `.jmw1`; no per-node physical weight
  object is emitted.
- The supervised V2 checkpoint is the complete runtime inference artifact. It
  records the exact graph actually executed during training; every node kind,
  attribute, shape, edge, parameter identity, and graph-ordered virtual `Flat`
  slice; the exact preprocessing and output-decoder program; canonical row and
  `PlanId` identity; dataset provenance; completion evidence; and the physical
  weights. A generic-family, topology-free, descriptive-only, or
  reconstructed-from-row-name representation is invalid.
- For the current compact `cifar10-vit` executable, that exact program records
  RGB means and positive scales fitted from the training partition only and
  repeated in pixel-major order, patch size/stride `4/4` over `32×32×3`,
  **64** non-overlapping patch tokens, and token-mixing count `64`, followed by
  the executed LayerNorm, token-mixing MLP, attention, mean-pool, and classifier
  operations. This is exact persistence of the current `[LayerSpec]` /
  `[LayerState]` Mixer executable. It does not satisfy Sprint `23.1`'s
  single-typed-graph obligation or Sprint `24.1`'s literal small-ViT obligation,
  both of which remain Blocked in their numerical order.
- Virtual `Flat` slices carry graph-ordered node/parameter identities, shapes,
  and dtype. Refinement derives each offset and element length from those
  ordered shapes with checked arithmetic; redundant offsets/lengths are not
  persisted. The derived slices are non-overlapping, in bounds, and exactly
  cover the single physical flat vector.
- California Housing is split into its exact raw training and held-out
  partitions before any statistic is fitted. Feature means/scales and target
  mean/scale are fitted from the training partition only, applied unchanged to
  training and held-out examples, and persisted exactly. Loaded inference
  applies those feature transforms and inverse-transforms predictions into the
  declared target units; held-out and inference values never influence the
  fitted statistics.
- Canonical classification training permutes only the complete materialized
  training partition once per one-based epoch. For epoch `e`, it draws exactly
  `length trainSet` words using
  `splitMixWords (length trainSet) (deriveSplitMixSeed (SplitMixSeed
  (fromIntegral clfSeed)) (fromIntegral e))`, zips each whole example with its
  word and original zero-based index, and stable-sorts ascending exactly on
  `(word, originalIndex)` before forming mini-batches. Validation and test stay
  in fixed decoded order. The permutation changes no authoritative example or
  batch quantity, batch size/count, examples-processed total, or actual
  optimizer-update count. The tuning exact-update path retains its fixed-order
  cyclic batches.
- The validated supervised ProductRow descriptor owns the exact finite,
  positive learning rate and includes it in descriptor equality, rendering,
  semantic fields, and `PlanId`. The canonical recipe is `3e-3` for
  `fashion-mnist-resnet`, `1.1e-3` for `cifar10-resnet20`, `1.5e-3` for
  `cifar10-vit`, and `1e-3` for the other eight rows. Publisher passes that
  refined value unchanged to the
  selected trainer; both classification and California Housing regression
  consume it, and no environment override or executor default may reinterpret
  it.
- V2 construction binds completion evidence to the persisted artifact. The
  completed and manifest final-weight hashes equal SHA-256 of the exact
  `supervised.weights` `.jmw1` bytes; the initial-weight hash identifies the
  exact canonical `.jmw1` encoding consumed at initialization; and the
  completion/manifest dataset digest identifies the exact canonical dataset
  artifact bytes read for the bound row, split, and plan. A missing or unequal
  hash, dataset identity, `PlanId`, observed budget, or update count is a typed
  construction failure.
- Every V2 runtime carries exactly one refined origin. Product Publisher writes
  bind the authoritative ProductRow projection and retain the strict row,
  experiment, substrate, budget, and `PlanId` checks. Generic supervised
  commands bind the exact canonical `SupervisedPlan` transport, re-refine it on
  load, reject canonicalization or identity drift, and cannot occupy a
  ProductRow experiment identity. A generic run that completes its declared
  budget below the external convergence bar returns a typed successful miss and
  publishes no checkpoint; a passing generic run persists its exact-plan V2
  artifact. Mounted service workers perform that write through in-cluster
  MinIO rather than a host publication mirror.
- The Store V2 decode/reconstruction path produces an executable only from the
  persisted graph, transforms, decoder, slices, and physical bytes. Once V2 is
  recognized, an unsupported operation, absent field, invalid slice, transform
  mismatch, decoder mismatch, or backend incompatibility fails with a typed
  error; it never falls back to V1/legacy decoding, a generic or Dense model, a
  demo network, caller-supplied topology, the pure/reference engine, or another
  substrate.
- The reconstructed artifact executes its complete graph through the selected
  real CPU, CUDA, or Metal engine. Every operation required by the eleven
  authoritative supervised ProductRows has a strict engine implementation; an
  unavailable operation fails rather than being skipped or replaced. Linux CPU
  and Linux CUDA generate content-addressed `kernel.cc` / `kernel.cu` sources
  implementing a status-returning version-`1` `double` ABI with the complete
  `0xff` capability mask. Apple Silicon generates MSL inside content-addressed
  `.metal.json`, validates the same logical ABI/capability/symbol contract, and
  dispatches through the fast-math-off fixed bridge with explicit
  `Double`↔fp32 transport. All compile, load, symbol, ABI, capability,
  contract, native-status, execution, and nested selected-backend MLP failures
  are typed; the production engine adapters install no
  `RuntimeOperations.host*` callbacks.
- For all eleven rows in `matrixFloor.floorSupervisedRows`, validation compares
  the training-returned model with the Store-loaded V2 artifact on the same
  held-out/inference inputs. Weight bytes/hashes, preprocessing, slice-to-node
  assignment, decoded output, row identity, and `PlanId` agree exactly;
  `sameSubstrateV2Tolerance` bounds maximum absolute floating-output difference
  by `1e-9` for the `double` `linux-cpu` / `linux-cuda` structural ABIs and
  `1e-5` for the fixed-bridge Metal fp32 path. These are same-substrate bounds,
  not cross-substrate equivalence. Codec-only round trips and fixture networks
  cannot satisfy the parity matrix. The successful training return carries a
  mandatory finite, dimension-checked held-out
  input/output probe produced immediately by that model, plus the observed
  optimizer-update count recorded only after all epoch/batch loops complete.
  Writer and Product Publisher consume that count and require exact equality
  with the authoritative `SupervisedPlan`, completion, and manifest rather than
  reconstructing it after training.
- Supervised V1 manifests remain available to inspection/resume code and are
  explicitly inference-ineligible. New supervised runtime writers cannot emit
  V1.

### Validation

Current Sprint `10.6` validation is `linux-cpu` only. CUDA and Metal
reattestation remains downstream in the single-accelerator product lanes; the
older accelerator results below are historical and do not validate V2.

```bash
docker compose --progress plain build jitml
```

The live portion uses the freshly built `jitml:local` image, reconciles the
retained `linux-cpu` publication onto that image, verifies both routed health
endpoints, and publishes each authoritative supervised row explicitly:

```bash
docker compose run --rm -e JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1 jitml jitml bootstrap --linux-cpu
docker compose run --rm jitml jitml cluster status
curl --fail http://127.0.0.1:9091/healthz
curl --fail http://127.0.0.1:9091/readyz
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-vit
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row mnist-shallow-mlp
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row mnist-deep-mlp
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row mnist-lenet
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row fashion-mnist-mlp
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row fashion-mnist-resnet
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-resnet20
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar10-resnet56
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row cifar100-wide-resnet
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row tiny-imagenet-resnet50
docker compose run --rm jitml jitml internal train-and-publish-product-rows --linux-cpu --row california-housing-mlp
```

Every publisher invocation must train from its exact verified staged bytes,
consume the authoritative plan's complete successful mini-batch count, write a
V2 latest target, and reload the same held-out probe through Store and the real
Linux CPU engine within `1e-9`. The eleven commands must finish with **11 / 11**
V2 rows, zero V1 supervised latest targets, zero unsupported rows, and zero
errors. `cifar10-vit` runs first. Four diagnostics missed the unchanged
**0.25** bar: the fresh-image 16×16/four-token run measured
`test_accuracy=0.173`, the deterministically permuted 16×16 rerun measured
`0.181`, the permuted 8×8/16-token rerun measured `0.227`, and the permuted
4×4/64-token rerun measured `0.237`. The then-current-source train-only
RGB-normalized rerun measured `0.266` and published one eligible V2 row before
the phase-order algebra error was discovered. That artifact is diagnostic only;
the final fresh immutable-image run must reproduce the corrected typed recipe
before any row can contribute closure evidence.

After live reconciliation and all eleven publications succeed, the canonical
test and code-quality gates run against that same image/publication:

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

Rule-M plan enforcement was re-scanned against the current phase corpus on
2026-07-19: **0** backward edges across **47** formal sprint edges, **0**
dual-accelerator gates across **282** validation sections, and **0** accelerator
invocations across the **20** validation sections in aggregation phases `17`,
`18`, and `31`. This Sprint `10.6` validation block contains **15**
Linux CPU lane invocations and **0** accelerator invocations. These are
current plan-maintenance denominators; they do not relabel or replace Sprint
`10.12`'s separately dated 2026-07-14 historical evidence. The same closure
audit passed `git diff --check` with no whitespace errors.

### Closure Validation Evidence

- ❌ On 2026-07-18, the fresh current-image
  `train-and-publish-product-rows --linux-cpu --row cifar10-vit` run completed
  its authoritative 16×16/four-token, pre-permutation schedule over **1,000**
  training examples for five epochs, batch size 128, **5,000** examples
  processed, and **40** successful optimizer updates. It measured
  `train_acc=0.199` and `test_accuracy=0.173`, below the unchanged **0.25** bar,
  and correctly published no artifact.
- ❌ The current-source rerun then retained the same 16×16/four-token
  executable and every authoritative plan quantity while applying the exact
  seed-and-one-based-epoch SplitMix permutation. It measured
  `train_acc=0.227` and `test_accuracy=0.181`; the honest failure showed that
  deterministic epoch order alone did not clear the bar.
- ❌ The next current-source diagnostic retained the exact verified bytes,
  permutation, **1,000** training examples, five epochs, batch size 128,
  **5,000** examples processed, **40** successful updates, and **0.25** bar
  while reducing the patch to 8×8. Its 16-token runtime improved to
  `train_acc=0.321` and `test_accuracy=0.227`, but still failed convergence and
  correctly published no artifact.
- ❌ The next current-source diagnostic used non-overlapping 4×4 patches over
  `32×32×3`, producing **64** tokens and reducing each patch projection to
  48 image values plus two positional values. It leaves the exact dataset,
  split membership, five epochs, batch size 128, **5,000** examples processed,
  **40** updates, seed-derived epoch order, and **0.25** bar unchanged. The
  optimized run completed with `train_acc=0.308` and
  `test_accuracy=0.237`, still below the frozen bar, and correctly published
  no artifact. The focused raw-runtime contract asserts patch size/stride
  `4/4`, token count `64`, **123,595** parameters, and contiguous full virtual
  slice coverage.
- ✅ On 2026-07-19, the pre-algebra-correction train-only RGB-normalized
  4×4/64-token diagnostic retained the exact **1,000-example**, five-epoch, batch-128,
  **5,000-example**, **40-successful-update** schedule and unchanged **0.25**
  bar. It measured `train_loss=1.7352672695605809`,
  `val_loss=2.024846793637071`, `train_acc=0.392`, and
  `test_accuracy=0.266`. RGB means and positive scales came from the training
  partition only; the same transform was applied to train, validation, and test
  model inputs, the raw `[0,1]` held-out probe was retained, and V2 persisted
  the repeated elementwise transform. The then-current production command returned **1**
  row, **1** eligible, **0** unsupported, and **0** errors and wrote manifest
  SHA-256
  `8622315fa0bcf3ea969f8f8da065f09ec75948e2d415bd091aee171d8fdf4663`.
  The later phase-order correction changed the meaning of its token-mix and
  attention operations, so this artifact is historical diagnostic evidence,
  not the current canonical Mixer artifact.
- ✅ Pre-rate-binding current-source partial gates passed: container
  `jitml-unit` **678 / 678**;
  the focused exact CIFAR ViT V2 contract **1 / 1**; and the focused canonical
  permuted-training plus fitted-transform bind→project check **1 / 1**. The
  same implementation uses boxed-vector constant-time attention indexing and
  discards each `forwardOnly` tape after projecting that layer's output. These
  focused results and the one-row publication do not close Sprint `10.6` before
  the fresh immutable-image all-row and full-suite gates pass.
- ✅ After the exact rate became descriptor-semantic, container `jitml-unit`
  passed **681 / 681**, including all eleven canonical values,
  zero/negative/NaN/infinite rejection, `PlanId` sensitivity, exact Publisher
  callback propagation, and California Housing consumption. Current-source
  `jitml check-code` also passed (`check-code: ok`). These gates validate the
  landed recipe but do not replace the pending fresh-image row publications.
- ❌ The first immutable-image `cifar10-resnet20` continuation exposed a
  phase-order regression and correctly published no artifact:
  `train_acc=0.227`, `test_accuracy=0.209`. The in-progress V2 work had changed
  token mixing and attention into residual variants even though Sprint `23.1`
  explicitly owns those still-Blocked equation corrections. Sprint `10.6` now
  freezes and executes the pre-`23.1` algebra instead: token mixing replaces its
  input with the mixed result, attention returns attended values, and only an
  explicit residual layer adds a skip. Strict shape/error checks, boxed
  indexing, native selected-engine dispatch, and ABI/capability enforcement
  remain unchanged.
- ❌ After that scope correction, the exact canonical permutation at the
  retained `1e-3` rate measured `train_acc=0.277` and
  `test_accuracy=0.249`, one of 1,000 test examples below the unchanged **0.25**
  bar, and again published no artifact. A temporary environment-override
  diagnostic at `1.1e-3` then retained the same dataset, seed, five epochs,
  batch-128 geometry, **5,000** examples, **40** updates, topology, and bar; it
  measured `train_loss=1.8407929741047941`,
  `val_loss=1.897399248354522`, `train_acc=0.319`, and
  `test_accuracy=0.293`, publishing one eligible current-source V2 artifact
  with SHA-256
  `d5c123d6f08d3891e0db6fe5def29b3769f964bc0a5778bd007f002b01692984`.
  That artifact predates descriptor/`PlanId` binding of the rate and is not
  final evidence. The measured result justified the typed canonical recipe;
  adding that recipe changes every supervised `PlanId`. The fresh-image
  reconciliation and all-eleven sequence must therefore restart from
  `cifar10-vit` after the corrected operation algebra and typed rate recipe pass
  their unit/code-quality gates.
- ✅ The corrected current-source `cifar10-resnet56` prebuild diagnostic used
  its typed `1e-3` rate, five epochs, **1,000** training examples, batch size
  128, **5,000** processed examples, and **40** successful updates. It measured
  `train_loss=1.7652791500005947`, `val_loss=1.9516668964460984`,
  `train_acc=0.368`, and `test_accuracy=0.28`, clearing the unchanged **0.20**
  bar and publishing V2 manifest SHA-256
  `cf9d3ea54c33decf317137539cd95506664f39269af79e4076375afedd2dc2b5`.
  This removes the remaining known convergence risk before image freeze but is
  still current-source diagnostic evidence, not final immutable-image evidence.
- ❌ On 2026-07-19, fresh immutable image descriptor
  `sha256:aeb82655aed67e81b30feb0c2c0c6932c0f89b01496cab70b23e03137127906a`
  passed its embedded `jitml check-code` gate and the 611-module PureScript
  build with zero warnings and zero errors. A non-no-op `linux-cpu` reconcile
  then executed **156** live steps; both repository image identities in the
  reconcile stamp matched that descriptor, all nine published components were
  Ready, and `/healthz` plus `/readyz` returned `ok` and `ready`. The mandatory
  all-eleven sequence nevertheless stopped at its first row, as required:
  corrected-algebra `cifar10-vit` retained the canonical **1,000-example**,
  five-epoch, batch-128, **5,000-example**, **40-update**, typed-`1e-3` recipe
  and unchanged **0.25** bar but measured
  `train_loss=1.9099182707321072`, `val_loss=2.1013915602250837`,
  `train_acc=0.313`, and `test_accuracy=0.226`. The publisher returned **1**
  row, **0** eligible, **0** unsupported, and **1** error and correctly minted
  no artifact. No later row ran. Sprint `10.6` remained Active at that
  diagnostic point while the typed, `PlanId`-bound ViT recipe was corrected;
  the next immutable-image sequence
  must restart at `cifar10-vit` without weakening the bar.
- ❌ A current-source one-axis diagnostic then changed only the ViT epoch
  budget from five to ten while retaining its exact **1,000-example**,
  batch-128, typed-`1e-3`, corrected-algebra, and **0.25** contracts. It
  executed the declared **10,000** examples and **80** optimizer updates, but
  validation selection retained the exact same snapshot as the five-epoch run:
  `train_loss=1.9099182707321072`, `val_loss=2.1013915602250837`,
  `train_acc=0.313`, and `test_accuracy=0.226`. The publisher again returned
  **0** eligible / **1** error and minted no artifact. The ineffective epoch
  change was reverted; the next bounded diagnostic retains five epochs and
  tests the smallest source-declared, `PlanId`-bound rate change (`1.1e-3`).
- ❌ That five-epoch `1.1e-3` current-source probe executed the same **5,000**
  examples and **40** updates and improved modestly to
  `train_loss=1.9025646335053257`, `val_loss=2.1035817069984653`,
  `train_acc=0.318`, and `test_accuracy=0.232`, but remained below **0.25**.
  The publisher returned **0** eligible / **1** error and minted no artifact.
  The next one-axis probe uses a source-declared, `PlanId`-bound `1.5e-3` rate;
  the epoch budget, data, seed, topology, preprocessing, and bar remain fixed.
- ❌ The five-epoch `1.5e-3` current-source probe again executed **5,000**
  examples / **40** updates and improved to
  `train_loss=1.8802370382416158`, `val_loss=2.1103454293014035`,
  `train_acc=0.329`, and `test_accuracy=0.242`, but still failed **0.25**.
  It returned **0** eligible / **1** error and minted no artifact. The next
  single-axis diagnostic uses the conventional typed `2e-3` Adam rate, with
  every non-rate contract unchanged.
- ❌ At `2e-3`, the same five-epoch **5,000-example** / **40-update** run
  measured `train_loss=1.853951751572561`,
  `val_loss=2.105241314216369`, `train_acc=0.346`, and
  `test_accuracy=0.239`. The higher training accuracy but lower held-out result
  shows that rate-only tuning is exhausted; the publisher returned **0**
  eligible / **1** error and minted no artifact. The next typed recipe retains
  the best observed `1.5e-3` rate and expands only the bounded training
  partition to **2,000** examples. Five epochs therefore execute **10,000**
  examples and **80** updates over twice the data while keeping the seed,
  batch size, topology, preprocessing discipline, evaluation size, and
  external **0.25** bar unchanged.
- ✅ The resulting current-source `cifar10-vit` publisher run used that exact
  **2,000-example**, five-epoch, batch-128, **10,000-example**, **80-update**,
  typed-`1.5e-3` recipe. It measured
  `train_loss=1.7761211625600088`, `val_loss=1.9528016967824382`,
  `train_acc=0.352`, and `test_accuracy=0.275`, clearing the unchanged
  **0.25** bar by 0.025. The full publisher/Store path returned **1** row,
  **1** eligible, **0** unsupported, and **0** errors and published exact
  supervised V2 manifest SHA-256
  `a05f1e235f18cfc7aa1b3baebeff8bfc1e1825e77139ccd877f9106f17001d05`.
  This locks the source-declared ViT recipe and removes the observed
  convergence blocker, but remains current-source diagnostic evidence: final
  closure still requires a new immutable image, reconcile, and the complete
  all-eleven sequence restarted at `cifar10-vit`.
- ✅ The final source-declared recipe then passed the full current-source
  `jitml-unit` stanza **682 / 682** in **39.03s**. The count includes the exact
  ViT projection assertion (**2,000** train / **1,000** evaluation / batch 128 /
  five epochs / **80** updates / `1.5e-3`) and proves both learning-rate and
  training-example-count sensitivity in semantic `PlanId` identity.
- ✅ Final current-source `jitml docs check` and `jitml check-code` both passed
  (`docs check: ok`; `check-code: ok`) after the recipe, tests, and current
  contract documentation were synchronized.
- ✅ Fresh immutable image descriptor
  `sha256:fbd0c55e8f13e82450df1f6b46c14b3d174735d2c007a6de67481a524a0a2a72`
  passed its embedded `jitml check-code` gate and the **611-module**
  PureScript build with zero warnings and zero errors. A non-no-op
  `linux-cpu` reconcile executed **156** steps. Both `jitml:local` and
  `jitml-demo:local`, both repository identities in the version-1 reconcile
  stamp, and all five Ready application Pods resolved to that image; every Pod
  had zero restarts. All nine publication components were Ready and the edge
  `/healthz` / `/readyz` probes returned `ok` / `ready`.
- ✅ That exact image then published the mandated eleven supervised rows in
  order, with every command reporting **1** eligible, **0** unsupported, and
  **0** errors. The held-out metric and exact V2 manifest identities were:

  | Row | Held-out metric | V2 manifest SHA-256 |
  | --- | ---: | --- |
  | `cifar10-vit` | accuracy `0.275` | `a05f1e235f18cfc7aa1b3baebeff8bfc1e1825e77139ccd877f9106f17001d05` |
  | `mnist-shallow-mlp` | accuracy `0.907` | `eb1b3c6e5571449f86283bd90a2cf0c14831c8140d55fd004391a0cc0685e6fb` |
  | `mnist-deep-mlp` | accuracy `0.913` | `618c471531bdc6ea60b9fab2093abf0a496e99291d52d31fab5824a99eb621a9` |
  | `mnist-lenet` | accuracy `0.332` | `39c1b5be2dae2958230401a46b9c699a7fc076d2beed70aacd4be66f31bcf903` |
  | `fashion-mnist-mlp` | accuracy `0.856` | `7f9a5fba559b43f45e3709c8051d0600bcc09d4ffb4d585a78d67b2ec1a88ca5` |
  | `fashion-mnist-resnet` | accuracy `0.835` | `e4a57492ac89aeca8c5a546f3078ee0a1208f5ff7a4eaedf50b07cde7bcd55b0` |
  | `cifar10-resnet20` | accuracy `0.293` | `01d9a88d2309266be5b6d5b227df8940f6ae0795a614220d329278959a8a08b9` |
  | `cifar10-resnet56` | accuracy `0.28` | `cf9d3ea54c33decf317137539cd95506664f39269af79e4076375afedd2dc2b5` |
  | `cifar100-wide-resnet` | accuracy `0.12` | `1a26570b5d7726a2a544e033cc268ba7ac92de998a950150d2ecd14997c9f187` |
  | `tiny-imagenet-resnet50` | accuracy `0.002` | `30f82e70138d8df31d579f398bd20bd33410639f70b0bddaf34d562c0d1d8853` |
  | `california-housing-mlp` | validation MSE `0.21983530961436884` | `d22681a4f2562469c9cfe375d60ee59fb902459796128cc8bde27460ac754665` |

  The focused live latest-pointer gate then loaded all eleven exact V2 runtime
  identities and passed **1 / 1** in **6.99s**. The full immutable-image unit
  lane also passed **682 / 682** in **39.03s**.
- ❌ The subsequent full `jitml-sl-canonicals --linux-cpu` gate exposed a
  parity-test recipe propagation defect and failed **1 / 36** after
  **1,765.22s**. Publisher had correctly trained `cifar10-resnet20` at its
  descriptor-owned `1.1e-3` rate and measured `test_accuracy=0.293`; the exact
  parity test projected the row but called the generic plan-only runner, which
  supplied `Nothing` and therefore retrained at the executor default `1e-3`.
  Its deterministic `test_accuracy=0.249` matched the earlier default-rate
  diagnostic and failed the unchanged `0.25` bar before Store parity. The
  corrected test now extracts the refined descriptor rate and calls the same
  mandatory-rate execution boundary as Publisher. It compiles, HLint and the
  supported Fourmolu check are clean, and the focused Publisher rate
  propagation regression passes **1 / 1**. Because this changes the test
  source included in the immutable image, descriptor `fbd0c55e…` is retained
  as diagnostic evidence only; the next validation attempt must build a new
  image and restart reconcile plus all eleven publications from row one.
- ✅ Corrected immutable image descriptor
  `sha256:29d5d744b86b53cf51a92447708ca4d86466bf3b364a766cc7477bd3e2ccdc3d`
  then passed its embedded `jitml check-code` and 611-module PureScript gates.
  A **156-step** non-no-op `linux-cpu` reconcile left all five application Pods
  Ready with zero restarts, all nine publication components Ready, and both
  routed probes healthy. The mandated row-one restart published all eleven
  supervised ProductRows as exact V2 artifacts; the live latest-pointer
  identity proof passed **1 / 1**, the full unit lane passed **682 / 682**, and
  the corrected all-eleven Store parity lane passed **36 / 36**.
- ❌ The mandatory integration gate against that exact image passed
  **152 / 155**. Its two generic supervised failures completed real training
  before checkpoint construction rejected their generic `PlanId` against the
  ProductRow-only V2 projection: the public workflow measured
  `test_accuracy=0.838`, and the live daemon `StartTraining` schedule completed
  its declared **10 × 7,000** training budget. The third failure was a
  spawned-binary tune test that deliberately corrupted its cluster publication
  and then retained the stale expectation that real tune execution would
  succeed. The **682 / 682** unit result, **36 / 36** SL result, eleven
  publications, and descriptor `29d5d744…` therefore remain diagnostic evidence
  only; mandatory integration did not close the sprint.
- ✅ On 2026-07-19, the corrected source passed a warning-as-error build of
  the library, executable, unit, integration, and SL-canonical targets and the
  complete unit lane passed **711 / 711** in **39.01s**. The closed generic V2
  origin is now the composite of its canonical row identity and canonical
  `SupervisedPlan` transport; admission re-refines both and binds the exact
  executed seed, canonical dataset-at-read digest, runtime bytes, completion
  observations, TensorBoard identity/tags, and current-ETag pointer CAS result.
  Product-origin publication separately binds the authoritative ProductRow and
  exact four-row metric vector. A completed generic run below its external bar
  returns a typed successful miss without consulting optional legacy weight
  projections; a passing run writes its exact-plan V2 artifact. The spawned
  tune test now treats its deliberately corrupted publication as an execution
  failure while retaining `--dry-run` render coverage. Supported Fourmolu and
  `git diff --check` are clean; the focused spawned-binary integration case
  passed **1 / 1**, and `jitml docs check` plus `jitml check-code` both exited
  `0`. Because this source differs from descriptor `29d5d744…`, the immutable
  build, reconcile, publication, and remaining full-suite gates must still run
  again.
- ✅ `docker compose build jitml` then built that exact corrected source as OCI
  descriptor
  `sha256:0147b37fafd53c01669705a5723ce91482d0fd545da4b9da523df8dacc3e9ba8`,
  with Linux/amd64 manifest
  `sha256:a8d35d46393552afb7d4616fc8af6ee6d7f976da96fc4ab678ff18a79371fa92`
  and runtime config
  `sha256:799fa6856bb3d0b81f11d761595d35ce273c969af63bffb4cb084bc6787b2805`.
  The tag identities matched the corresponding Buildx-history attachments.
  The image build's embedded `jitml check-code` passed, and its 611-module
  PureScript build completed with zero warnings and zero errors. This is the
  sole image used for Sprint 10.6 closure evidence.
- ✅ The supported `JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1` Linux CPU bootstrap
  reconciled that exact descriptor in a non-no-op **156-step** rollout.
  `jitml cluster status` reported all nine publication components Ready;
  routed `/healthz` and `/readyz` returned HTTP `200` with `ok` and `ready`.
  The reconcile stamp names descriptor `0147b37f…` for both repository app
  tags; all four kind nodes resolve both tags to that descriptor and runtime
  config `799fa685…`. The coordinator, demo, and three service Pods are all
  Running and Ready on that config with zero restarts. That identity chain
  remained unchanged through the eleven publications and focused pointer gate.
- ✅ The mandatory publication restart on descriptor `0147b37f…` is **11 / 11**
  rows complete. Every completed invocation has reported `rows: 1`,
  `eligible: 1`, `unsupported: 0`, and `errors: 0`:

  | ProductRow | held-out metric | manifest SHA-256 |
  | --- | --- | --- |
  | `cifar10-vit` | `test_accuracy=0.275` | `c54d62f618782fd9dcc06860a47b97f15fcce2ec3f0ce25d1caaa6abae1b654c` |
  | `mnist-shallow-mlp` | `test_accuracy=0.907` | `3bd862e5e2e14c173d196536ad8ddac4aeb3197cce12c5686536390e96402360` |
  | `mnist-deep-mlp` | `test_accuracy=0.913` | `7b7028344b834fa92997936c5a1d88613b561632ad2d63e6aba93b519a026ea4` |
  | `mnist-lenet` | `test_accuracy=0.332` | `7cfdeda777280c3db5e07730182fd1a38c4a195b480d148dba6d30adf3725ac0` |
  | `fashion-mnist-mlp` | `test_accuracy=0.856` | `a841e95e5ed8c57ed8fef0271a83a234d2a2c5729183ee2192d3cdf741a541eb` |
  | `fashion-mnist-resnet` | `test_accuracy=0.835` | `ae1329b859a729877b752a1fe572d3972ecf9dff31fdf5440132b722147c1531` |
  | `cifar10-resnet20` | `test_accuracy=0.293` | `e7ca913a0269ff9a8b3f0ffe801135eaaa3c30e9ced09b051ee6bf36187b8160` |
  | `cifar10-resnet56` | `test_accuracy=0.28` | `85d16ee6bad2a61c0b2f791aba4b46d2e5379f68ba74c5352e423ff6df5c7154` |
  | `cifar100-wide-resnet` | `test_accuracy=0.12` | `6a4e6017040d12364b1a2d016e1d57e5143a655bf7db7b25672f92bf3153daa8` |
  | `tiny-imagenet-resnet50` | `test_accuracy=2.0e-3` | `290f8ac63ff93e792ee4236b86c3d892cd6c2e0ab7a8854fcd8ed0b1ce8edde4` |
  | `california-housing-mlp` | `validation_mse=0.21983530961436884` | `a742554d18dc1e75f54229fac6370132af45f72b770e8627a34cd278b388a09f` |

  All eleven ordered invocations completed at `1` eligible and zero
  unsupported/errors. The focused live latest-pointer gate then passed
  **1 / 1** in **6.97s**, loading all eleven exact ProductRow-origin V2 runtime
  identities from their latest targets with no supervised V1 target. The full
  Store-parity matrix remains pending against exactly this set.
- ✅ The complete immutable-image `jitml-unit --linux-cpu` lane then passed
  **711 / 711** in **38.85s** (**44.16s** including orchestration), against the
  same descriptor and live publication.
- ✅ The complete immutable-image `jitml-sl-canonicals --linux-cpu` lane passed
  **36 / 36** in **7,164.60s** (**7,166.18s** including orchestration). Its
  production all-eleven trained-program versus Store-loaded V2 parity case
  passed in **6,871.87s** with the exact published metrics above; the embedded
  live latest-pointer proof passed again in **7.04s**, the live staged-row
  runtime case in **21.98s**, and live MNIST convergence in **263.53s**.
- ✅ The complete immutable-image `jitml-integration --linux-cpu` lane passed
  **155 / 155** in **7,082.12s** (**7,086.39s** including orchestration). The
  full live typed-executable WorkflowMatrix passed in **6,081.96s**, live PPO
  convergence in **719.40s**, live daemon training placement in **33.53s**, and
  the corrected spawned-binary matrix case passed in **0.18s**. The three
  failures that kept descriptor `29d5d744…` diagnostic are therefore closed on
  the final image and publication.
- ✅ `jitml-negative-controls --linux-cpu` passed **3 / 3** in **0.50s**
  (**3.63s** including orchestration) on that same immutable image.
- ✅ `jitml-model-convergence --linux-cpu` passed **111 / 111** in **0.50s**
  (**4.28s** including orchestration), covering every ProductRow's external
  convergence bar and non-wall-clock inference-performance floor.
- ✅ `jitml docs check` and `jitml check-code` both exited `0` in the project
  container after the final evidence updates.

### Historical Validation (retained; does not close the reopened scope)

- ✅ `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed
  197 / 197 on 2026-06-15.
- ✅ `docker compose run --rm jitml jitml test jitml-integration --linux-cpu`
  passed 71 / 71 on 2026-06-15 against the live
  `.build/runtime/cluster-publication.json`, including the 19-test `Live`
  group. The earlier non-live subset
  `cabal test jitml-integration --test-options='-p !/Live/'` passed 51 / 51.
- ✅ `docker compose run --rm jitml docker build -t jitml:local -f
  ./docker/Dockerfile .` passed on 2026-06-15 after changing the Dockerfile's
  Cabal repository URL to `https://hackage.haskell.org/`. This reproduced the
  exact bootstrap-owned legacy-builder child path, reached `check-code: ok`,
  built the PureScript bundle, and tagged `jitml:local`.
- ✅ `./bootstrap/linux-cpu.sh up` passed on 2026-06-15 after the image-build
  fix, printing `bootstrap: linux-cpu reconciled` and `bootstrap: live phased
  rollout executed 84 steps`. It wrote
  `.build/runtime/cluster-publication.json` for `linux-cpu` on edge port `9091`
  with `harbor`, `minio`, `pulsar`, `postgres`, `observability`,
  `jitml-service`, and `jitml-demo` all `ready`.
- ✅ `./bootstrap/linux-cuda.sh up` passed on 2026-06-15 after the same
  image-build fix, printing `bootstrap: linux-cuda reconciled` and
  `bootstrap: live phased rollout executed 84 steps`. It wrote
  `.build/runtime/cluster-publication.json` for `linux-cuda` on edge port
  `9092` with `harbor`, `minio`, `pulsar`, `postgres`, `observability`,
  `jitml-service`, and `jitml-demo` all `ready`.
- ✅ `docker compose run --rm jitml jitml test jitml-daemon-lifecycle --linux-cpu`
  passed 34 / 34 on 2026-06-15.
- ✅ `docker compose run --rm jitml-cuda jitml test jitml-integration --linux-cuda`
  passed 71 / 71 on 2026-06-15 against the live `linux-cuda`
  `.build/runtime/cluster-publication.json`, including the 19-test `Live`
  group. The long `WorkflowMatrix` live case completed in 899.12s, the live PPO
  cartpole convergence case completed in 117.47s, and the full stanza passed in
  1039.19s. The earlier no-publication attempt failed the 19 live cases by
  design, while the non-live cases passed 52 / 52 under
  `cabal test -fcuda jitml-integration --test-show-details=direct`.
- ✅ `./bootstrap/apple-silicon.sh up` passed on 2026-06-15 after the
  image-build fix and fixed-bridge installation, printing
  `bootstrap: live phased rollout executed 84 steps`. It wrote
  `.build/runtime/cluster-publication.json` for `apple-silicon` on edge port
  `9090` with `harbor`, `minio`, `pulsar`, `postgres`, `observability`,
  `jitml-service`, and `jitml-demo` all `ready`; routed `/healthz` returned
  `HTTP/1.1 200 OK`.
- ✅ `./.build/jitml test jitml-integration --apple-silicon` passed 71 / 71 on
  2026-06-15 against the live `apple-silicon`
  `.build/runtime/cluster-publication.json`, including the 19-test `Live`
  group.
- ✅ `docker compose run --rm jitml jitml check-code` passed on 2026-06-15.
- ✅ `docker compose run --rm jitml jitml docs check` passed on 2026-06-15.
- ✅ `git diff --check` passed on 2026-06-15.

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
