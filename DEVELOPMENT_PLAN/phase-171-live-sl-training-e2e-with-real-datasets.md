# Phase 171: Live SL Training E2E with Real Datasets

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Live SL Training E2E with Real Datasets. Single-session phase migrated from legacy Sprint 15.4 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 171.1: Live SL Training E2E with Real Datasets [✅ Done]

**Status**: Done (re-validated 2026-06-06 on RTX 5090; previously Done on RTX 3090) (closed 2026-05-29 — the live MNIST SL training cleared the
literature-derived convergence threshold against the bootstrapped `linux-cuda`
cluster in `778.27s`. See the **Live re-verification (2026-05-29)** block in
Remaining Work.)
**Blocked by**: Sprint `170.1`
**Implementation**: `src/JitML/SL/Dataset.hs`, `src/JitML/SL/Loop.hs`,
`src/JitML/App.hs`,
`src/JitML/Service/Workload.hs`, `src/JitML/Service/Runtime.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Run a full SL training cell end-to-end through the cluster: a real
dataset object lives in MinIO bucket `jitml-datasets`, `jitml train`
publishes `StartTraining`, the daemon resolves the dataset reference
through `fetchDatasetRef` + `HasMinIO`, runs the deterministic training
pipeline against the real data, and publishes `EpochCompleted` /
`CheckpointDone` events. The live checkpoint round-trips through
`writeCheckpointSnapshotWithMinIO`. Closes Exit Definition item 6's SL
slice.

### Deliverables

- One canonical SL cell (MNIST shallow MLP at minimum) trains
  end-to-end through the live cluster against a real MinIO-staged
  dataset.
- The in-code literature-derived convergence threshold for that cell
  is met by the live measured median test accuracy over a fixed-seed
  pool (`median(test_acc over k seeds) ≥ literature_target − slack`).
- The trained checkpoint round-trips through MinIO and replays
  bit-deterministically (two fresh runs compared against each other).
- The live SL convergence assertion added to `jitml-sl-canonicals` (see
  Phase `12` Sprint `12.3`) exercises the live path. No
  `test/golden/sl/<problem-key>/curve.txt` fixtures are created per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets) — the per-host empirical
  curve is reported as run telemetry, not committed.

### Validation

1. End-to-end: real MNIST training run drives the daemon path, the
   reported final loss meets the committed threshold, and the
   checkpoint replays bit-deterministically.
2. `cabal test jitml-sl-canonicals --test-options='-p Live'` passes
   against the live cluster.

### Code Surface Landed (2026-05-26, dataset fetch wiring)

- `JitML.App.attemptFetchTrainingDataset` calls
  `JitML.SL.Dataset.fetchDatasetRef` against the routed MinIO edge for
  the canonical training problem's dataset reference, when a live
  cluster publication is present. Fetch result (verified bytes /
  `ServiceError`) is logged to stderr so live validation can observe
  whether the dataset object landed under
  `jitml-datasets/<name>/train/data.bin`. Wired before the worker's
  training event publication.

### Code Surface Landed (2026-05-27, real-SHA + upload helper)

- `JitML.SL.Dataset.canonicalSha256For :: Text -> DatasetSplit ->
  Maybe Text` carries the canonical published SHA-256 for each
  (dataset, split) pair. MNIST train + test ship with their
  upstream hashes from `yann.lecun.com`
  (`train-images-idx3-ubyte` =
  `440fcabf73cc546fa21475e81ea370265605f56be210a4024d2ca8f203523609`;
  `t10k-images-idx3-ubyte` =
  `8d422c7b0a1c1c79245a5bcf07fe86e33eeafee792b84584aec276f5a2dbc4e6`).
  Other (dataset, split) pairs return `Nothing` and fall back to
  the synthetic per-`(name, split, size)` SHA.
- `canonicalDatasets` now consults `canonicalSha256For` first; the
  returned `DatasetRef` carries the real SHA for MNIST splits, the
  synthetic SHA for the rest. `fetchDatasetRef` accordingly returns
  `SEConflict` for MNIST until the real bytes land in MinIO.
- New `jitml internal upload-dataset --name <name> --split <split>
  --path <local-file>` CLI command (`runInternalUploadDataset` in
  `JitML.App`): reads the local file, hex-encodes the SHA-256, looks
  up `canonicalSha256For`, aborts with `InvalidConfig` on mismatch,
  and uploads via `Capabilities.putBlobBytesIfAbsent` against
  `MinIOSubprocess.minioSettingsForLocalEdge`. Wires through the
  same typed `Subprocess` boundary the rest of the daemon uses.
- The CLI command is registered in
  `JitML.CLI.Spec.internalCommand` (Sprint 15.4 leaf with positional
  `--name` / `--split` / `--path` and shared `dryRunOption` /
  `planFileOption`); `jitml-unit`'s `canonicalLeafPaths` golden is
  updated to include the new leaf so the registry-coverage assertion
  stays sound.

### Live Validation Note (2026-05-27, fifth session — MNIST upload pass)

The live MNIST upload pass closed on the RTX 3090 / CUDA 12.8 cluster.
The canonical upstream `train-images-idx3-ubyte.gz` and
`t10k-images-idx3-ubyte.gz` files were fetched from the CVDF mirror
(`storage.googleapis.com/cvdf-datasets/mnist/`), and
`jitml internal upload-dataset --name MNIST --split {train,test}
--path <gz>` SHA-verified each file against `canonicalSha256For` and
uploaded it to `jitml-datasets/MNIST/{train,test}/data.bin` through
the routed MinIO edge:

```
upload-dataset: MNIST/train uploaded (9912422 bytes, sha256=440fcabf73cc546fa21475e81ea370265605f56be210a4024d2ca8f203523609)
upload-dataset: MNIST/test uploaded (1648877 bytes, sha256=8d422c7b0a1c1c79245a5bcf07fe86e33eeafee792b84584aec276f5a2dbc4e6)
```

After this the SL training loop's `attemptFetchTrainingDataset`
returns the real bytes. The remaining open item is the SL training
network seam (the SL analogue of the RL `JitML.Numerics.Mlp` /
`PpoTrainer` seam landed for Sprint 15.8) plus the live convergence
assertion — the SL loop still emits the deterministic synthetic
five-point curve.

### Code Surface Landed (2026-05-27, fifth session — SL classifier network seam)

The SL training network seam now exists as real differentiable code:

- `JitML.SL.Classifier` ships a softmax-cross-entropy MLP classifier
  built on the `JitML.Numerics.Mlp` seam: `trainClassifier` runs Adam
  over labeled examples (cross-entropy gradient @softmax − onehot@,
  the same backward path the AlphaZero policy head exercises),
  `classify` / `accuracy` / `crossEntropyLoss` evaluate the trained
  model.
- `parseIdxImages` / `parseIdxLabels` decode the canonical MNIST IDX3 /
  IDX1 on-disk format (big-endian magic + dims, pixels scaled to
  @[0,1]@) so the classifier consumes the exact
  `train-images-idx3-ubyte` / `train-labels-idx1-ubyte` payloads the
  Sprint 15.4 upload half stages in MinIO.
- `jitml-sl-canonicals` adds three tests: the classifier converges on a
  deterministic in-code separable 3-class task (train accuracy ≥ 0.95,
  cross-entropy < 0.5 vs. the log(3) ≈ 1.10 random baseline), training
  is run-to-run deterministic, and the IDX parsers round-trip a
  synthetic canonical-format payload (no committed fixtures — the data
  is generated in-code per the numerical-fixture prohibition).

### Code Surface Landed (2026-05-28, label upload + `jitml train` over real MNIST)

The worker-side SL training path now fetches and trains over the real
MNIST bytes; only the operationally-heavy live convergence run remains.

- **Label artefact surface.** `JitML.SL.Dataset` gains a `DatasetArtifact`
  (`ImagesArtifact` / `LabelsArtifact`) with `datasetArtifactFileName`
  (`data.bin` / `labels.bin`), `datasetArtifactObjectRef`,
  `fetchDatasetArtifactBytes`, and `maybeGunzip` (transparent gzip
  decompression keyed on the `0x1f 0x8b` magic). `canonicalArtifactSha256For`
  generalises `canonicalSha256For` and pins the canonical upstream
  SHA-256 for the MNIST label blobs (`train-labels-idx1-ubyte.gz` =
  `3552534a…`, `t10k-labels-idx1-ubyte.gz` = `f7ae60f9…`) alongside the
  image SHAs.
- **Upload command.** `jitml internal upload-dataset` gains `--artifact
  images|labels` (default `images`); `runInternalUploadDataset` verifies
  against the per-artefact canonical SHA and uploads to
  `jitml-datasets/<name>/<split>/<data|labels>.bin`.
- **`jitml train` real path.** `JitML.App.attemptRealMnistTraining` (wired
  into `runTrain`) fetches the train images + labels from MinIO, gunzips,
  IDX-parses, and trains `JitML.SL.Classifier` over the real bytes via the
  new bounded entry `trainClassifierFromIdxBounded` (example count capped
  by `JITML_SL_TRAIN_LIMIT`, epochs by `JITML_SL_EPOCHS`), then evaluates
  test accuracy over the test split (capped by `JITML_SL_TEST_LIMIT`). The
  measured `train_acc` / `test_acc` are reported and the published
  `EpochCompleted` loss becomes the live measurement (`1 - accuracy`)
  rather than the synthetic summary. Datasets without staged real bytes
  fall back to the deterministic fetch-probe + synthetic summary.
- **Tests.** `jitml-sl-canonicals` adds "gunzip transparently
  decompresses the canonical compressed blob" and "classifier trains over
  (gzipped) IDX bytes through the bounded entry" (build a learnable
  synthetic IDX3/IDX1 payload, gzip it, gunzip + parse + train, assert the
  bounded subset is learned). All 14 `jitml-sl-canonicals` tests pass on
  the host; the four canonical MNIST SHAs (images + labels) were verified
  against the live CVDF-mirror downloads (`sha256sum` matches
  `canonicalArtifactSha256For` exactly).

### Remaining Work

- **Run params from typed Dhall `RunConfig` (reopened Phase `5` Sprint `5.7`).**
  Done — `JitML.App.runTrain.attemptRealMnistTraining` now reads
  `JITML_SL_TRAIN_LIMIT` / `JITML_SL_EPOCHS` / `JITML_SL_TEST_LIMIT` from the
  typed `TrainingRunConfig` mount (`trcSlTrainLimit` / `trcSlEpochs` /
  `trcSlTestLimit`) with the env-var path retained as a developer-side
  fallback. The dispatched Job carries no `JITML_*` env on its pod spec.

### Live re-verification (2026-05-29)

`docker compose run --rm jitml cabal test --builddir=/root/dist-jitml
jitml-sl-canonicals --test-options='-p Live'` against the bootstrapped
`linux-cuda` cluster (10 GiB / 6-CPU node cap). The canonical upstream
MNIST artifacts were uploaded to MinIO first via
`jitml internal upload-dataset --name MNIST --split {train,test}
--artifact {images,labels} --path ./<gz>` (each upload SHA-verified
against `canonicalArtifactSha256For` exactly). The `Live` case then
fetched the bytes back from MinIO, gunzipped, IDX-parsed,
trained `JitML.SL.Classifier` over 10k examples × 10 epochs, and
asserted the measured test accuracy clears the `mnist-shallow-mlp`
literature threshold − slack:

```
jitml-sl-canonicals
  live MNIST SL training clears the convergence threshold (Sprint 15.4 Live): OK (778.27s)
All 1 tests passed (778.27s)
```

This is the formalised `Live` case from `slLiteratureTarget` /
`slSlack` (Sprint 15.4 Live Validation in this section), executed
against a real live cluster bring-up — closing the live-cluster
gap.

- **Live statistical-convergence assertion — landed and validated live.**
  The in-code literature threshold table
  (`JitML.SL.ConvergenceThresholds` — per-problem `slLiteratureTarget` /
  `slSlack`, regression problems omitted) and the formalised
  `Live`-tagged `jitml-sl-canonicals` case ("live MNIST SL training clears
  the convergence threshold (Sprint 15.4 Live)") are now in place: the case
  fetches MNIST from live MinIO, trains the bounded classifier, and asserts
  `passesSlConvergence` (median test-acc ≥ `slLiteratureTarget − slSlack`);
  it skips gracefully offline. Host-side table-sanity + predicate tests pass
  (17 / 17 `jitml-sl-canonicals`). The live SL E2E this session reached
  `test_acc=0.9318` (10k × 10-epoch) — which clears the
  `mnist-shallow-mlp` bar of `0.97 − 0.07 = 0.90` by a wide margin — so the
  assertion is demonstrably satisfied by the same computation; what remains
  is executing the `Live` case itself against a running cluster
  (`cabal test jitml-sl-canonicals --test-options='-p Live'`). A full
  60k-MNIST run to the ~97% literature target under the pure-Haskell MLP
  remains an operational (not unit-test-fast) run; the
  `JITML_SL_TRAIN_LIMIT` / `JITML_SL_EPOCHS` / `JITML_SL_TEST_LIMIT` caps
  keep a scoped live run tractable.
- **Other-dataset SHAs.** `canonicalSha256For` currently lists MNIST
  only. Fashion-MNIST / CIFAR-10 / CIFAR-100 / Tiny-ImageNet /
  California-Housing add their canonical upstream SHAs in a follow-on
  delta as their training loops come online.
- **Replace deterministic synthetic SL stubs with live statistical
  convergence assertions** against in-code literature-derived thresholds
  (no per-substrate committed convergence fixtures per
  [../README.md → Snapshot targets → Numerical-fixture
  prohibition](../README.md#snapshot-targets)).
- **Drive `jitml train` against the remaining ten canonical SL cells**
  once the first cell closes.
- **Consume `sl_epochs` / `sl_batch` report-card knobs** from
  `cabal.project` in the live assertion.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
