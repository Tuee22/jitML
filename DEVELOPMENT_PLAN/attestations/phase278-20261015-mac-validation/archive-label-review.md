# Phase 278 Verified Archive Labels and Tiny Split Review — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Phase 278](../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md)
**Generated sections**: none

> **Purpose**: Close the dataset-only CIFAR/Tiny histogram gap, reproduce the
> historical Tiny class-coverage defect, and inspect the specified class-order
> repair without claiming model convergence or phase validation.

The review and reproduction script remain versioned. Generated baseline JSON,
receipt captures and copied receipt tooling are local-only diagnostics excluded
from Git and Docker contexts; historical links below require those local bytes.

The [reproduction script](calculate-archive-label-baselines.py) verifies every
complete archive against the production SHA-256 in
[`SL.Dataset`](../../../src/JitML/SL/Dataset.hs) before parsing any selected
archive. It reads no trained checkpoint, score, or lane journal. The
result (`archive-label-baselines.json`) retains exact histograms, source-byte
hashes, ordered image-path/content digests, and all calculated controls. A
second invocation reproduces the JSON byte for byte; its command/output/status
receipts and the acquisition diagnostics are in
[archive-label-receipts](archive-label-receipts/README.md).

After container formatting, two complete historical invocations exit `0` and
reproduce a 96,462-byte JSON, SHA-256
`f6915f0d6c8398a2c7527d3af8214b2b2fbbe4432ca1cf91108536627caefbf3`.
Those exact bytes, manifest, and report text remain in the
historical snapshot (`archive-label-receipts/historical-before-trpo-recipe-version/`).
Their raw receipts remain unchanged.

Two new complete invocations at frozen source
`c4a42c3ae80951d5d4b33ee6d0981b64e385c0648ec6c8ae352423efba710625`
again exit `0` and reproduce the current **96,462-byte** JSON, SHA-256
`d0b009229c4aac7dcdd7c0102752850d873f327c478a2441346027e181c24b92`.
The current comparison receipt (`archive-label-receipts/20261015T214353.112221Z-archive-label-final-source-comparison/result.json`)
proves exact reproduction and current source pins. Only the consulted
`Matrix.hs` hash changes after TRPO numerical recipe identity versioning; all
archive checks, dataset statistics, remaining source pins and diagnostic
assertions are unchanged.

## Verified artifacts and exact ordering

| Dataset archive | Bytes | Production SHA-256 |
|---|---:|---|
| `cifar-10-binary.tar.gz` | 170,052,171 | `c4a38c50a1bc5f3a1c5537f2155ab9d68f9f25eb1ed8d9ddda3db29a59bca1dd` |
| `cifar-100-binary.tar.gz` | 168,513,733 | `58a81ae192c23a4be8b1804d68e518ed807d710a4eb253b1f2a199162a40d8ec` |
| `tiny-imagenet-200.zip` | 248,100,043 | `6198c8ae015e2b3e007c7841da39ec069199b9aa3bfa943a462022fe5e43c821` |

The CIFAR origins redirect from the
[dataset owner's host](https://www.cs.toronto.edu/~kriz/cifar.html) to
`cave.cs.toronto.edu`. Slow original transfers and interrupted range diagnostics
remain in the receipts; their partial files were never parsed. Complete copies
from the [CIFAR-10 mirror](https://data.brainchip.com/dataset-mirror/cifar10/cifar-10-binary.tar.gz)
and [CIFAR-100 mirror](https://data.brainchip.com/dataset-mirror/cifar100/cifar-100-binary.tar.gz)
reproduce the production pins exactly. Tiny was obtained from its
[upstream archive](http://cs231n.stanford.edu/tiny-imagenet-200.zip).
Raw datasets remain under ignored `.build/phase278-anchor-review/datasets/`.

The label calculation follows the production decoder, rather than assuming
that a balanced full dataset gives balanced prefixes:

- [`SL.Classifier`](../../../src/JitML/SL/Classifier.hs) concatenates CIFAR-10
  `data_batch_1.bin` through `data_batch_5.bin` in that explicit order and reads
  `test_batch.bin` for evaluation. Labels are byte zero of each 3,073-byte
  record. CIFAR-100 uses `train.bin`/`test.bin` and the fine label at byte one of
  each 3,074-byte record. Record order is preserved before bounding.
- [`SL.TinyImageNet`](../../../src/JitML/SL/TinyImageNet.hs) assigns label IDs
  from `wnids.txt` line order. Its historical training order sorted all JPEG
  paths lexicographically before bounding. Final evaluation retains the first
  1,000 nonblank `val_annotations.txt` lines in file order; `TestSplit` aliases
  the validation archive. The new training contract orders classes by their
  existing label IDs, sorts paths within each class, and interleaves before
  applying the bound. The diagnostic retains both orders explicitly.
- [`SL.TrainingExecution`](../../../src/JitML/SL/TrainingExecution.hs)
  materializes `trainingExamples + floor(trainingExamples / 5)`, takes the first
  `trainingExamples` for gradient updates, and reserves the rest for model
  selection. [`Product.Matrix`](../../../src/JitML/Product/Matrix.hs) supplies
  the per-row budgets below.

## Observed bounded splits

| Row / training order | Gradient examples / classes | Selection examples / classes | Evaluation classes | Selection examples from untrained classes | Evaluation examples from untrained classes |
|---|---:|---:|---:|---:|---:|
| CIFAR-10 ResNet-20/56 | 1,000 / 10 | 200 / 10 | 10 | 0 | 0 |
| CIFAR-10 ViT | 2,000 / 10 | 400 / 10 | 10 | 0 | 0 |
| CIFAR-100 wide residual | 7,000 / 100 | 1,400 / 100 | 100 | 0 | 0 |
| Tiny historical lexicographic | 8,000 / 16 | 1,600 / 4 | 196 | 1,600 | 913 |
| Tiny class-interleaved repair | 8,000 / 200 | 1,600 / 200 | 196 | 0 | 0 |

The historical Tiny gradient set contains exactly 500 examples of each of only
16 classes. Its selection set contains 500 examples from each of three other
classes and 100 from a fourth, with **zero class overlap** with training. Only
87 of the 1,000 evaluation labels belong to classes represented in gradient
updates. This is an observed label/split confound in the pinned archive.

Class interleaving gives exactly **40 gradient and 8 selection examples per
class**, covering all 200 classes at the same total budgets. All three pairs
of repaired partitions have zero overlapping paths and zero overlapping SHA-256
identities of JPEG contents. Their held-out evaluation image order/content
digests are identical to the historical diagnostic. The old split has distinct
image paths but shares one byte-identical JPEG between gradient and selection:
`n01944390_66.JPEG` and `n01945685_164.JPEG`, SHA-256
`acdca0e4c040b031a490d66ac3f8260642193c10379fea9debab5edc2c030396`.
The diagnostic does not claim that different JPEG bytes imply different visual
content; no pixel decoding or perceptual duplicate search is performed.

## Additional trivial-model controls

The prior [independent review](../phase278-20261015-mac-review/supervised-anchor-review.md#concrete-additional-classification-floor)
specified the label-only rule before these archives were parsed: require at
least `max(m + 1, q(C))` correct answers among 1,000 examples, where `m` is the
largest actual class count and `q(C)` is the exact uniform-random binomial
critical count at `alpha = 0.01 / 30`. The script reproduces its integer tail
calculation without trained observations.

| Dataset | Largest held-out class count | Reject-every-constant minimum | Uniform-random minimum | Combined additional minimum |
|---|---:|---:|---:|---:|
| CIFAR-10 | 112 | 113 | 135 | 135 / 1,000 |
| CIFAR-100 | 16 | 17 | 23 | 23 / 1,000 |
| Tiny ImageNet | 10 | 11 | 15 | 15 / 1,000 |

These are necessary additional controls, not independently justified model
convergence bars. They do not justify reducing existing stronger requirements,
retuning a model after observing its held-out result, or treating dataset
diagnostics as a passing ProductScenario. The published-anchor obligation
remains open.

The class-interleaved repair addresses the verified Tiny selection confound
without changing evaluation labels or the example budget. Freeze its semantic
recipe identity before execution, retain controls for class order, uneven
queues, and bounding, and obtain fresh real evidence for affected contracts.
Any stronger statistical policy, different dataset selection, content
deduplication scheme, architecture, or training budget needs its own prospective
justification and contract identity. This report does not set one.

## Reproduction

```bash
python3 DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-validation/calculate-archive-label-baselines.py .build/phase278-anchor-review/datasets
```

Both retained complete invocations exit `0`. Their JSON bytes are identical.
These commands are dataset diagnostics; they do not mint a standing jitML
validation record, complete Phase 278, or release a later numerical phase.
