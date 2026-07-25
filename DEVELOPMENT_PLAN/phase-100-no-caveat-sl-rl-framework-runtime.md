# Phase 100: No-Caveat SL/RL Framework Runtime

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: No-Caveat SL/RL Framework Runtime. Single-session phase migrated from legacy Sprint 8.12 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 100.1: No-Caveat SL/RL Framework Runtime [✅ Done]

**Status**: Done
**Implementation**: `src/JitML/SL/Canonicals.hs`, `src/JitML/SL/Classifier.hs`,
`src/JitML/RL/Framework.hs`, `src/JitML/RL/SimulatorLoop.hs`,
`src/JitML/Proto/{Training,Rl,Tune}.hs`
**Docs to update**: `documents/engineering/training_workloads.md`,
`documents/engineering/numerical_core.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Promote the full advertised SL/RL framework surface into runtime obligations
instead of scoped Dense-MLP and text-event closure.

### Deliverables

- Every canonical SL row is either trainable through a substrate-backed
  architecture-specific forward/backward ABI or removed from the canonical
  product claim. The intended no-caveat target keeps the rows and implements the
  missing Dense-deep, Conv2D, residual, wide-residual, ResNet-50, and
  VisionTransformer training paths.
- `JitML.SL.Canonicals.denseMlpCohort` stops being the product gate; all
  canonical SL rows run against real staged dataset bytes through the
  substrate-backed architecture runtime with no synthetic dataset or curve
  fallback. Phase `13` promotes that staged-byte train/eval surface to the full
  median-convergence, checkpoint, reload, and inference matrix.
- RL command/event payloads include typed episode frames, observations/actions,
  policy probabilities, replay-buffer state, and checkpoint references required
  by browser animation and replay.
- The framework emits typed live events that `jitml-demo` can decode through
  generated browser contracts rather than free-form text frames.
- Any temporary framework helper used to keep existing tests green while this
  lands is listed in
  [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#pending-removal).

### Progress (2026-06-14)

- `src/JitML/Proto/Rl.hs` and `proto/jitml/rl.proto` now define
  `RlAnimationFrame` and `RlReplayFrame` event payloads with typed observation,
  action, reward, policy-probability, replay-cursor, and timestamp fields.
  `encodeRlEventProto` / `decodeRlEventProto` cover both new oneof cases, and
  `parseRlEvent` round-trips the rendered line envelope used by the current
  broker bridge.
- `src/JitML/RL/SimulatorLoop.hs` records deterministic per-step
  `SimulatedFrame` transitions from real environment dynamics; the worker and
  host RL publishers convert those frames into `RlAnimationFrame` events on
  `rl.event.<mode>` when an episode carries frame data.
- `src/JitML/Web/Contracts.hs` renders generated PureScript
  `RlAnimationFrame` / `RlReplayFrame` records into
  `web/src/Generated/Contracts.purs`; `web/src/Panels/Rl.purs` consumes the
  generated animation record, preserves unsigned hash/cursor/timestamp fields
  as exact strings rather than lossy browser `Int` values, and rejects the old
  catch-all `data:` placeholder. The interactive browser replay control remains
  Phase `14` work.
- `src/JitML/SL/Architecture.hs` now owns the all-row supervised architecture
  runtime. It maps every `JitML.SL.Canonicals.canonicalProblems` row to a
  substrate-backed trainable topology: the Dense and DeepDense rows are device
  MLP stacks, residual rows are device MLP residual stacks with real
  input-gradient propagation, `Conv2D` uses a shared patch-convolution stem plus
  pooled classifier, and `VisionTransformer` uses patch embeddings plus a
  trainable Q/K/V self-attention block before pooling and classification. Each
  trainable layer calls the injected `MlpDevice` batched forward,
  batch-gradient, and input-gradient ABI; device failure returns `Left` with no
  pure-Haskell fallback.
- `JitML.SL.Canonicals.trainableCanonicalCohort` is the new all-row product
  cohort. `denseMlpCohort` remains only as a named legacy compatibility helper
  while the remaining Dense-only callers are deleted under the legacy ledger.
- `jitml train` now decodes the supervised experiment Dhall through
  `JitML.SL.Canonicals.loadCanonicalProblemExperiment`, resolves the row's
  `ArchitectureSpec`, decodes staged IDX bytes once through
  `JitML.SL.Classifier.decodeBoundedDataset`, and trains through
  `Architecture.trainArchitectureWithDevice` instead of the Dense-only
  classifier entry. Rows whose real dataset artifacts are not SHA-pinned or not
  staged still fail closed before publishing.
- `JitML.SL.Dataset` now has an explicit `ArchiveArtifact` for tarball-backed
  datasets plus real upstream SHA-256 pins for the canonical Toronto
  `cifar-10-binary.tar.gz` and `cifar-100-binary.tar.gz` archives.
  `jitml internal upload-dataset --artifact archive` accepts those tarballs,
  verifies the pinned SHA, and stages them at
  `jitml-datasets/<name>/<split>/archive.tar.gz`. `JitML.SL.Archive` extracts
  regular-file payloads from the gzip tar archives, and
  `JitML.SL.Classifier` now materializes the official CIFAR-10 train/test batch
  files and CIFAR-100 train/test files into labeled 3072-feature examples, using
  CIFAR-100 fine labels as the supervised target.
- `JitML.SL.Dataset` also pins the scikit-learn/Figshare
  `cal_housing.tgz` archive, and the new `JitML.SL.Regression` module parses
  `CaliforniaHousing/cal_housing.data` directly from the archive into
  eight-feature regression examples with the raw median-house-value target and
  trains a one-output MSE regressor through the selected `MlpDevice`.
  `jitml train` now routes staged California Housing archives through that
  regression trainer. Regression checkpoint/inference/convergence gates remain
  open; the runtime no longer depends on synthetic tabular examples.
- `JitML.SL.Dataset` now pins the canonical `tiny-imagenet-200.zip` archive,
  and the new `JitML.SL.TinyImageNet` module parses the real metadata files
  (`wnids.txt`, `words.txt`, and `val_annotations.txt`), decodes JPEG pixels
  through `JuicyPixels`, and materializes train/validation labeled examples
  from the real Zip64 archive through a narrow central-directory reader that
  supports Zip64 size/offset records plus stored/deflated ZIP entries.
- `jitml train` now has archive-backed live routes for CIFAR-10, CIFAR-100, and
  California Housing, and Tiny ImageNet: it fetches the staged
  `ArchiveArtifact`, materializes the train/test rows for CIFAR through
  `JitML.SL.Archive` + `JitML.SL.Classifier`, materializes Tiny ImageNet from
  zip/JPEG bytes through `JitML.SL.TinyImageNet`, trains image classifiers
  through `JitML.SL.Architecture`, and trains California Housing through the new
  `JitML.SL.Regression` MSE path. Missing archives still fail closed before
  publishing.
- Validation on 2026-06-14 built `jitml:local` with
  `docker compose --progress plain build jitml`: the image-local gate reported
  `check-code: ok`, rebuilt the PureScript bundle with zero PureScript warnings,
  and exported the image. The focused PureScript smoke check also passed 9 / 9 in
  a disposable container before the full image rebuild.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed 28 / 28 on 2026-06-14, including the new typed
  `RlAnimationFrame` / `RlReplayFrame` proto/render/parse coverage and simulator
  transition-frame assertions.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 23 / 23 on 2026-06-14. The added Sprint `8.12` cases assert the
  trainable canonical cohort covers all eleven product rows, resolve supervised
  experiment Dhall to the canonical row, pin Fashion-MNIST train/test
  image+label artifacts to upstream gzip SHA-256 values, pin the CIFAR-10 and
  CIFAR-100 upstream binary archives to SHA-256 values computed from the
  canonical Toronto downloads, parse CIFAR binary records, pin and parse the
  California Housing archive/data row format, pin the Tiny ImageNet archive and
  materialize generated JPEGs from a real zip layout, execute one
  substrate-backed train step for every canonical architecture through oneDNN,
  and train a real regression model through the same oneDNN `MlpDevice`.
  The live MNIST convergence assertion now decodes staged train/test IDX bytes
  and, when a live publication exists, trains and evaluates through
  `JitML.SL.Architecture.trainArchitectureWithDevice` /
  `accuracyArchitectureWithDevice` on the selected `MlpDevice` rather than the
  legacy Dense-only classifier path.
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`) on
  2026-06-14 after adding the all-row SL architecture runtime, and re-passed
  after moving the live MNIST convergence assertion onto the architecture/device
  path.
- `docker compose run --rm jitml jitml docs check` passed (`docs check: ok`) on
  2026-06-14 after aligning the development plan and engineering workload docs.
- After the CIFAR archive/parser slice, `docker compose run --rm jitml cabal run
  jitml -- check-code` passed (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`) on 2026-06-14. These were run through Cabal so the
  generated-doc comparison used the current source tree rather than the
  pre-slice image binary.
- After the California Housing archive/parser slice, `docker compose run --rm
  jitml cabal run jitml -- check-code` passed (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`) on 2026-06-14.
- After the Tiny ImageNet archive/metadata parser slice, `docker compose run
  --rm jitml cabal run jitml -- check-code` passed (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check` passed
  (`docs check: ok`) on 2026-06-14.
- After the tar archive materialization slice, `docker compose run --rm jitml
  jitml test jitml-sl-canonicals --linux-cpu` still passed 22 / 22, with the
  CIFAR and California archive decoders exercised by the existing Sprint `8.12`
  parser cases.
- The tar archive materialization slice also passed `docker compose run --rm
  jitml cabal run jitml -- check-code` (`check-code: ok`) and
  `docker compose run --rm jitml cabal run jitml -- docs check`
  (`docs check: ok`) on 2026-06-14.
- After the regression-runtime slice, `docker compose run --rm jitml jitml test
  jitml-sl-canonicals --linux-cpu` passed 23 / 23, including the new
  device-backed regression convergence case.
- The regression-runtime and archive-backed `jitml train` routing slice also
  passed `docker compose run --rm jitml cabal run jitml -- check-code`
  (`check-code: ok`) and `docker compose run --rm jitml cabal run jitml -- docs
  check` (`docs check: ok`) on 2026-06-14.
- After the Tiny ImageNet zip/JPEG materialization slice, `docker compose run
  --rm jitml jitml test jitml-sl-canonicals --linux-cpu` passed 23 / 23,
  including in-memory zip archive materialization and JPEG decoding through
  `JuicyPixels`.
- The Tiny ImageNet zip/JPEG materialization slice also passed
  `docker compose run --rm jitml cabal run jitml -- check-code`
  (`check-code: ok`) and `docker compose run --rm jitml cabal run jitml -- docs
  check` (`docs check: ok`) on 2026-06-14.
- Live linux-cpu prerequisite setup on 2026-06-14 bootstrapped the cluster with
  `docker compose run --rm jitml jitml bootstrap --linux-cpu`; the published
  `.build/runtime/cluster-publication.json` reported Harbor, MinIO, Pulsar,
  PostgreSQL, observability, `jitml-service`, and `jitml-demo` ready behind edge
  port `9091`. MNIST, Fashion-MNIST, CIFAR-10, CIFAR-100, California Housing,
  and Tiny ImageNet source artifacts were staged into live MinIO through
  `jitml internal upload-dataset`, with each upload SHA-verified against the
  canonical pins in `JitML.SL.Dataset`.
- After replacing the Tiny ImageNet decoder's `zip-archive` path with the
  project-owned Zip64-aware reader, `docker compose run --rm jitml cabal test
  jitml-sl-canonicals --test-options='--pattern=8.12'` passed 9 / 9 on
  2026-06-14. That focused gate includes the live all-row SL matrix: every
  canonical row fetched its staged MinIO bytes, materialized real train/test
  examples, trained through the selected linux-cpu `MlpDevice`, and evaluated
  finite metrics through the same architecture runtime.
- After increasing the live MNIST validation budget to 60 full-batch device
  epochs at `1.0e-2` while leaving the threshold unchanged,
  `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 24 / 24 on 2026-06-14. The live MNIST convergence case cleared the
  in-code threshold through `JitML.SL.Architecture` in 393.09s, and the live
  all-row staged-byte matrix passed in 38.90s.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  re-passed 28 / 28 on 2026-06-14 after the SL live-gate fix.

### Validation

- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
- `docker compose run --rm jitml jitml check-code`
- `docker compose run --rm jitml jitml docs check`

Current validated subset (2026-06-14):

- `docker compose --progress plain build jitml` passed (`check-code: ok` and
  PureScript bundle build succeeded).
- `docker compose run --rm jitml jitml check-code` passed (`check-code: ok`)
  after the all-row SL architecture runtime landed and after the live MNIST
  convergence assertion was moved to the architecture/device runtime. The
  current-source reruns after the CIFAR, California, Tiny ImageNet metadata, tar
  materialization, regression-runtime, and Tiny ImageNet zip/JPEG slices passed
  as
  `docker compose run --rm jitml cabal run jitml -- check-code`.
- `docker compose run --rm jitml jitml docs check` passed (`docs check: ok`)
  after the Phase `8` plan and engineering docs were aligned. The current-source
  reruns after generated CLI docs and Phase `8` docs changed passed as
  `docker compose run --rm jitml cabal run jitml -- docs check`.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 23 / 23, including all-row trainable-cohort coverage, supervised
  experiment Dhall row resolution, Fashion-MNIST real-artifact SHA coverage,
  CIFAR-10/CIFAR-100 real archive SHA coverage plus binary-batch parser
  coverage, California Housing real archive SHA coverage plus regression-row
  parser coverage, Tiny ImageNet real archive SHA coverage plus zip/JPEG
  materialization coverage, the substrate-backed train-step smoke for every
  canonical SL architecture, and device-backed regression convergence through
  oneDNN. The live MNIST case remains fail-closed on missing live
  publication/staged bytes, but its real-data path now trains and evaluates
  through the same architecture/device runtime as `jitml train`.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed 28 / 28.
- `docker compose run --rm jitml cabal test jitml-sl-canonicals
  --test-options='--pattern=8.12'` passed 9 / 9 after the live linux-cpu cluster
  was bootstrapped and every canonical dataset artifact was staged in MinIO. The
  added live all-row case exercises real staged bytes for MNIST, Fashion-MNIST,
  CIFAR-10, CIFAR-100, Tiny ImageNet, and California Housing through
  `JitML.SL.Architecture` / `JitML.SL.Regression` on the linux-cpu
  `MlpDevice`.
- `docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu`
  passed 24 / 24 with the current live publication and staged dataset set. The
  live MNIST convergence case clears the unchanged threshold using a 60-epoch
  architecture/device budget, and the live all-row staged-byte train/eval smoke
  still passes.
- `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`
  passed 28 / 28 after the SL live-gate fix.
- A focused disposable-container `spago test` for `web/` passed 9 / 9 while
  fixing the typed RL browser contract parser; the authoritative project-image
  bundle build above also compiled the same PureScript surface warning-clean.

### Remaining Work

None on the Phase `8` framework/runtime surface. Phase `13` owns the full
cross-model median-convergence, checkpoint, reload, and inference matrix that
consumes this all-row SL runtime. Phase `14` owns browser replay controls and
Playwright assertions over the typed RL animation/replay payloads. The legacy
Dense-only compatibility helper is tracked for Phase `13` cleanup in
[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md#pending-removal).

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
