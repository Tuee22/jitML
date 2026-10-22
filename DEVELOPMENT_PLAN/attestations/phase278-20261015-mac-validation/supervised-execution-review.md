# Phase 278 Mac Supervised Execution Review — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Current validation index](README.md), [Phase 278](../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md)
**Generated sections**: none

> **Purpose**: Specify the supported next Mac supervised diagnostics, correct historical plan arithmetic, and distinguish execution feasibility from unresolved convergence policy.

## Current Status

This is a source and resource review, not a training receipt. No supervised
training or cluster bootstrap runs as part of this review. The
[current validation index](README.md) owns actual test outcomes; Phase `278`
remains the first open phase under the
[numerical execution rule](../../development_plan_standards.md#m-forward-only-single-accelerator-numerically-ordered-phases).
Complete replacement journals wait for policy and source to be frozen. A
passing diagnostic below cannot close the independently reviewed convergence
obligation or release the next phase.

Read-only host inspection reports 68,719,476,736 bytes of physical memory
(64 GiB), ten CPUs, no running Docker containers, and no
`.build/runtime/cluster-publication.json`. These are preparation observations,
not standing GateTranscripts. The three complete CIFAR/Tiny archives are under
ignored `.build/phase278-anchor-review/datasets/`; their exact sizes and verified
production hashes are retained in the [archive-label review](archive-label-review.md).
Its partial download files remain excluded. Preparing all eleven rows also
requires the eight original MNIST/Fashion IDX artifacts and the California
Housing archive; this review does not claim they are staged or locally present.

## Plan arithmetic correction

The historical
[supervised-anchor review](../phase278-20261015-mac-review/supervised-anchor-review.md#current-declarations-and-comparability)
incorrectly lists **560** updates for each 7,000-example, ten-epoch,
batch-128 recipe, including its housing discussion. Its historical bytes are
preserved. The authoritative relation in
[`Plan.validateDerivedOptimizerUpdates`](../../../src/JitML/Plan/Plan.hs) is
`epochs × ceil(training examples / batch size)`. Thus these rows require
`10 × ceil(7000 / 128) = 10 × 55 = 550` updates. This is an arithmetic
correction to the review, not a new runtime measurement or a budget change.

The current quantities come from
[`Product.Matrix`](../../../src/JitML/Product/Matrix.hs); every row has batch
size 128, final evaluation size 1,000, and one canonical seed.

| Rows | Rows in group | Gradient examples per row | Epochs | Updates per row | Processed gradient examples per row |
|---|---:|---:|---:|---:|---:|
| Three MNIST rows, two Fashion rows, CIFAR-100, California Housing | 7 | 7,000 | 10 | 550 | 70,000 |
| CIFAR-10 ResNet-20 and ResNet-56 | 2 | 1,000 | 40 | 320 | 40,000 |
| CIFAR-10 ViT | 1 | 2,000 | 40 | 640 | 80,000 |
| Tiny ImageNet | 1 | 8,000 | 15 | 945 | 120,000 |
| **All supervised rows** | **11** | — | — | **6,075 total** | **770,000 total** |

Tiny's 945 updates are `15 × ceil(8000 / 128) = 15 × 63`; its last batch
contains 64 examples. The new selection order changes which images enter the
gradient and selection partitions, not these quantities. The verified archive
gives 40 gradient and eight selection images per class, with 200 classes in
both partitions. The held-out annotation order remains unchanged.

## Metal execution and resource envelope

[`SL.Architecture`](../../../src/JitML/SL/Architecture.hs) sends real substrate
execution to `trainLayerGraphClassifierEpochDevice`, rather than the pure
reference-device branch. Its named families construct their actual compact
graphs: affine/deep dense, LeNet, residual/basic or bottleneck mixers, wide
residual, and ViT. The Tiny graph is the two-block compact bottleneck mixer,
not a published 50-layer ResNet training schedule.

[`Numerics.LayerGraphDevice`](../../../src/JitML/Numerics/LayerGraphDevice.hs)
selects `MetalLayerTraining` for `apple-silicon`, probes the visible device and
fixed bridge, then dispatches generated Metal kernels for affine, convolution,
normalization, pooling, attention, and related operators. Residual blocks
compose the device primitives; their elementwise glue runs on the host. This
supports the current graphs without a CUDA runtime, Tart, SwiftPM, or the
offline Metal compiler. It does not predict whether a fresh canonical row
passes convergence or served-byte parity.

Tiny materializes 9,600 training-archive images, reserving the last 1,600 for
model selection, then decodes 1,000 held-out images. At 64 × 64 × 3 channels
and eight bytes per unboxed `Double`, these features alone total
**1,042,022,400 bytes**, about **0.97 GiB**. The 248,100,043-byte compressed
archive, JPEG/ZIP metadata, boxed held-out serving inputs, graph activations,
gradient/optimizer buffers, and the live cluster are additional costs. This is
a lower bound on working data, not a measured peak-resident-memory guarantee.
The publisher executes rows sequentially, so eleven rows do not require all
eleven decoded datasets concurrently. No reliable wall-clock estimate for the
repaired full-resolution Tiny run is available from this review.

## Supported diagnostic sequence

After the active RL diagnostics finish, the cheapest additional device check
requires neither datasets nor a cluster:

```bash
# Example: exercise every canonical graph family through the selected real Metal device.
.build/jitml test jitml-sl-canonicals --apple-silicon --test-options='-p "all canonical SL architectures execute a substrate-backed train step"'
```

This existing test runs one epoch on a small synthetic 4 × 4 image task.
Its result can establish operator execution in that fixture geometry; it is
not full-resolution Tiny training, a production publication, or a convergence
claim. The test name retains its historical `--linux-cpu` suffix, but
`selectedTestSubstrate` reads the explicit Apple selection.

Real supervised publication requires live storage. In
[`App.workerLiveContext`](../../../src/JitML/App.hs), host execution normally
resolves the leased edge from `.build/runtime/cluster-publication.json`;
mounted worker boot configuration is the other supported resolver. The
[`TrainingExecution`](../../../src/JitML/SL/TrainingExecution.hs) entry fails
up front without that context. A file on the host does not substitute for a
staged, SHA-verified MinIO artifact.

After a separate decision to run a fresh canonical diagnostic, the supported
Tiny preparation and execution commands are:

```bash
# Example: prepare live storage and publish one fresh canonical Tiny row on the Mac.
.build/jitml bootstrap --apple-silicon
.build/jitml internal upload-dataset --name 'Tiny ImageNet' --split train --artifact archive --path .build/phase278-anchor-review/datasets/tiny-imagenet-200.zip
env -u JITML_PRODUCT_ROW_FILTER .build/jitml internal train-and-publish-product-rows --apple-silicon --row tiny-imagenet-resnet50
```

Bootstrap builds/loads the project service image and starts the governed local
cluster; it is materially more work than the cluster-free check. Upload verifies
the canonical hash before its create-only write. The exact object is bucket
`jitml-datasets`, key `Tiny ImageNet/train/archive.tar.gz`, despite the source
file being a ZIP. Training reads and verifies that same artifact again.
The direct internal publisher trains in its own host process and therefore
does not require the separate host service daemon merely to execute this row.
Its local checkpoint root is `.build/checkpoints` under the default cache
configuration, and available live storage receives its mirrored artifacts.

All supervised publication is fresh:
[`Publisher.Orchestrator`](../../../src/JitML/Product/Publisher/Orchestrator.hs)
disables checkpoint reuse for supervised rows because old manifests do not
contain the exact held-out examples needed by the new serving check. The
publisher completes the fixed recipe, applies its existing convergence bar,
writes/admit-checks the checkpoint, recomputes the held-out metric through the
exact admitted graph/weights, and applies the additional learning-signal guard.
For the verified Tiny prefix that guard requires at least **15 actual served
correct classifications out of 1,000**; the held-out maximum class count is
ten. A failure remains a failure; its measured score cannot set a new bar.

Once all twelve governed original artifacts are staged, the supported
eleven-row diagnostic uses the environment filter, rather than passing a
comma-separated list to the single-row `--row` option:

```bash
# Example: execute the canonical supervised slice with unchanged per-row recipes.
JITML_PRODUCT_ROW_FILTER='mnist-shallow-mlp,mnist-deep-mlp,mnist-lenet,fashion-mnist-mlp,fashion-mnist-resnet,cifar10-resnet20,cifar10-resnet56,cifar100-wide-resnet,cifar10-vit,tiny-imagenet-resnet50,california-housing-mlp' \
  .build/jitml internal train-and-publish-product-rows --apple-silicon
```

The eight IDX objects occupy MNIST/Fashion train/test `data.bin` and
`labels.bin` keys. CIFAR-10, CIFAR-100, Tiny, and California Housing each occupy
their dataset's train `archive.tar.gz` key. The live integration test named
`live canonical dataset inventory is exactly 12 SHA-verified objects` checks
their exact inventory and hashes. The
[CLI registry](../../../README.md#cli-command-topology-typed) and
[`SL.Dataset`](../../../src/JitML/SL/Dataset.hs) own staging syntax and keys.

These direct internal invocations produce diagnostic publications, not a
replacement authenticated 55-row lane journal. Journal issuance additionally
needs the ready host daemon and the complete ProductScenario run described in
the [Phase 278 handoff](../phase278-20261015-mac-review/README.md#resumption).
An eleven-row run cannot be joined with old records to manufacture a fresh
complete journal.

## Remaining convergence-policy decision

The [independent review](../phase278-20261015-mac-review/supervised-anchor-review.md)
still supplies no defensible published-model convergence floor for the exact
compact graphs and schedules. The extra classifier controls and exact positive
held-out R-squared guard reject trivial predictors; they do not supply that
missing model/schedule comparison. Tiny's historical target/slack source
explicitly chose its old floor to clear a measured result. Interleaving classes
does not make that origin independent, and a newly observed score must not be
used to retune it.

Before issuing closing evidence, settle an independently justified convergence
contract for these exact compact recipes, or reproduce a published graph,
dataset selection, and schedule closely enough that its cited convergence
criterion applies. Preserve stronger existing requirements while resolving
that decision. Then freeze policy, recipe, source, and identities; obtain real
complete journals through their separate lane owners, reconcile the aggregate,
and run the owning phase's standing gates. The Mac can prepare and execute its
Apple work; it cannot produce NVIDIA execution evidence for changed CUDA
contracts.
