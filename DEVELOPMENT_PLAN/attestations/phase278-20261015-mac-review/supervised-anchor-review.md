# Phase 278 Independent Supervised Anchor Review — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Phase 278](../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md)
**Generated sections**: none

> **Purpose**: Review the current supervised bars against the exact executed
> graphs and budgets, specify an independent additional trivial-model floor,
> and identify the evidence still required before Phase 278 can close.

No defensible replacement **published convergence floor for these exact compact
graphs and budgets** was identified in the primary sources reviewed below.
The proposed label-only and constant-regression criteria establish necessary
learning-signal checks; they do not replace the published-model convergence
contract. No production threshold, row contract, journal, aggregate, or phase
completion status changed in this review.

## Current declarations and comparability

The reviewed declarations are
[`SL.ConvergenceThresholds`](../../../src/JitML/SL/ConvergenceThresholds.hs),
[`Product.Matrix`](../../../src/JitML/Product/Matrix.hs), and
[`SL.Architecture`](../../../src/JitML/SL/Architecture.hs).
Every classification row evaluates the first **1,000** examples of its fixed
held-out decoder order, uses batch size **128**, and plans its one canonical
seed. Updates below are `epochs × ceil(training examples / 128)`, rather than
measured execution counts. The effective bars are decimal presentations of
`target − slack`; binary floating-point results can differ in the last place.

| Row | Target | Slack | Effective accuracy floor | Train examples × epochs | Planned updates | Executed graph family |
|---|---:|---:|---:|---:|---:|---|
| `mnist-shallow-mlp` | 0.97 | 0.07 | 0.90 | 7,000 × 10 | 560 | One affine classifier |
| `mnist-deep-mlp` | 0.98 | 0.08 | 0.90 | 7,000 × 10 | 560 | Two hidden ReLU layers, normalization, dropout, classifier |
| `mnist-lenet` | 0.99 | 0.69 | 0.30 | 7,000 × 10 | 560 | Two small 3×3 convolutions, local average pools, affine classifier |
| `fashion-mnist-mlp` | 0.89 | 0.08 | 0.81 | 7,000 × 10 | 560 | One affine classifier |
| `fashion-mnist-resnet` | 0.93 | 0.12 | 0.81 | 7,000 × 10 | 560 | Compact two-block residual mixer |
| `cifar10-resnet20` | 0.91 | 0.66 | 0.25 | 1,000 × 40 | 320 | Compact two-block residual mixer |
| `cifar10-resnet56` | 0.93 | 0.73 | 0.20 | 1,000 × 40 | 320 | Compact two-block residual mixer |
| `cifar100-wide-resnet` | 0.78 | 0.74 | 0.04 | 7,000 × 10 | 560 | Compact two-block mixer with GroupNorm |
| `cifar10-vit` | 0.93 | 0.68 | 0.25 | 2,000 × 40 | 640 | 16 patch tokens, embedding width at most 32, two-head attention, GeGLU, classifier |
| `tiny-imagenet-resnet50` | 0.64 | 0.632 | 0.008 | 8,000 × 15 | 945 | Compact two-bottleneck-block residual mixer |

The residual mixer has two strided convolutions, a local pool, projection,
residual blocks, normalization, attention, GeGLU, and a classifier. The ResNet-20
and ResNet-56 identifiers both select `resNetShape` with **two** basic blocks;
the public numeric suffix is not their executed depth. These graphs contain
real trained operators, but their architecture and schedule differ materially
from the published networks.

The production Tiny training decoder sorts JPEG paths lexicographically before
its bounded prefix selection. The
[Tiny ImageNet primary report](https://cs231n.stanford.edu/reports/2015/pdfs/yle_project.pdf)
states 500 training images per class. Together with the decoder and 8,000-example
budget, this implies training on only **16 of 200 classes**, followed by a
selection-validation prefix from subsequent classes. This is a **source-based
inference**, not an observed histogram of the pinned archive in this session.
The held-out metric uses the first 1,000 validation annotations in file order;
neither their balance nor their maximum class count follows from `1 / 200`.

Primary-source comparisons:

- [He et al., Deep Residual Learning, §4.2 and Table 6](https://arxiv.org/pdf/1512.03385)
  reports actual 20/56-layer CIFAR ResNets, 16/32/64-channel stages, augmentation,
  and 64,000 batch-128 updates. It supplies no measured acceptance floor for the
  two-block mixer trained for 320 updates on 1,000 images. A large project slack
  does not derive such a floor from those results.
- [Dosovitskiy et al., An Image Is Worth 16x16 Words, §4 and Table 2](https://arxiv.org/pdf/2010.11929)
  reports large pretrained ViTs and downstream fine-tuning. That experiment is
  not the compact from-scratch 640-update CIFAR graph.
- [Le and Yang, Tiny ImageNet Visual Recognition, §5](https://cs231n.stanford.edu/reports/2015/pdfs/yle_project.pdf)
  studies CNN/VGG configurations, augmentation, and a different training
  protocol. Its results do not license the current compact bottleneck mixer's
  0.64 target or 0.008 effective floor.
- The [Fashion-MNIST authors' benchmark description](https://github.com/zalandoresearch/fashion-mnist#benchmark)
  explicitly cautions that submitted results vary with epochs and batch size.
  Neither that collection nor a matching model-family name establishes the
  exact current affine/residual graphs' bounded-budget acceptance floors.

No row in the table has a reviewed source establishing its exact effective
floor. This is a statement about the evidence reviewed, not a claim that no
relevant experiment could ever be published. The source comment for Tiny is
stronger evidence of a defect: it explicitly says the 0.008 bar was selected to
be cleared by the observed 0.012 result. Its positive slack and above-chance
arithmetic cannot make that origin independent.

## Concrete additional classification floor

Before fresh execution, freeze a family-wise false-positive budget of
**α = 0.01** over **30 comparisons**: ten classification rows on three substrate
lanes. For the current 1,000-example evaluation, define:

- `m`: largest true-label count among the exact held-out examples;
- `q(C)`: smallest integer `k` with
  `Pr[Binomial(1000, 1/C) >= k] <= 0.01/30`;
- require correct predictions to be at least `max(m + 1, q(C))`.

The majority rule rejects **every constant classifier on that exact held-out
set**, including a constant chosen with knowledge of its labels. The random
rule bounds false acceptance of independent uniform random class predictions,
conditional on any fixed true-label sequence. Bonferroni's union bound needs no
independence between the thirty comparisons. Repeated adaptive attempts are
not thirty prespecified comparisons and must not inherit that error guarantee.
This is not a significance claim about a trained model's population accuracy,
nor a guarantee against arbitrary prediction schemes that inspect held-out
labels. The baseline definitions follow the
[official DummyClassifier documentation](https://scikit-learn.org/stable/modules/generated/sklearn.dummy.DummyClassifier.html);
the exact binomial test follows the
[NIST confidence-limit construction](https://itl.nist.gov/div898/handbook/prc/section2/prc241.htm).

Integer arithmetic in
[`calculate-supervised-anchor-inputs.py`](calculate-supervised-anchor-inputs.py)
reproduces these critical counts without an approximate tail or a model score:

| Classes | `q(C)` | Accuracy component | Exact tail at `q(C)` | Exact tail at `q(C) − 1` |
|---:|---:|---:|---:|---:|
| 10 | 135 | 0.135 | 0.0002439455071 | 0.0003486098483 |
| 100 | 23 | 0.023 | 0.0002721563482 | 0.0006518251383 |
| 200 | 15 | 0.015 | 0.0002158033635 | 0.0006718712300 |

The full upstream MNIST and Fashion test-label blobs were fetched and matched
the production SHA-256 pins before decoding. Their actual first-1,000 maximum
class counts are **126** and **115**, respectively, so the proposed additional
floor is **135 correct** for those rows. CIFAR and Tiny histograms were not
measured in this session. They must be obtained from verified pinned artifacts;
the complete-dataset balance is insufficient for a bounded prefix. The
[CIFAR dataset owner](https://www.cs.toronto.edu/~kriz/cifar.html)
describes the full test batches and binary label layout, but does not promise
that every 1,000-example prefix is balanced.

This floor must be **additional** to a defensible convergence criterion, with
the effective requirement taking the stricter bound. It cannot justify lowering
the stronger MNIST, Fashion, or CIFAR bars. Tiny's existing 0.008 already fails
the random component independently of any retained trained measurement; its
post-observation floor must be replaced, not re-described as independent.

## California Housing: reject every constant predictor

The current shared regression policy is `target 0.90 + slack 0.10`, hence
standardized **RMSE <= 1.0**. The product recipe plans 7,000 training examples,
the next 1,000 held-out examples, ten epochs, batch 128, and 560 updates.
`SL.Regression` fits the target mean and population standard deviation on the
training partition only and applies them unchanged to the held-out partition.
The model is the separate dense-regression runtime with hidden width 32.

For fixed held-out standardized targets `z`, let
`s² = mean((z − mean(z))²)`. Every constant predictor has MSE at least `s²`.
Thus **strictly positive held-out R²**, equivalently **RMSE < s**, rejects every
constant predictor. The
[official R² definition](https://scikit-learn.org/stable/modules/generated/sklearn.metrics.r2_score.html)
independently supplies this zero-skill boundary. Non-finite or zero held-out
variance must fail; a closed `<=` comparison at `s` would admit the optimum
constant and would not implement this requirement.

The complete upstream `cal_housing.tgz` matched SHA-256
`aaa5c9a6afe2225cc2aed2723682ae403280c4a3695a2ddda4ffb5d8215ea681`.
Reproducing only the production split and training-fitted target transform gives:

| Dataset-only statistic | Value |
|---|---:|
| Training target mean, raw units | 197415.45657142857 |
| Training target scale, raw units | 115643.3321388044 |
| Held-out standardized target mean | -0.2512410878696854 |
| RMSE of training-mean constant (standardized zero) | 0.5000693647502769 |
| Minimum RMSE among all held-out constant predictors | 0.43237401093012334 |

Both constant predictors pass the present `<= 1.0` bar. Positive skill on this
exact split requires RMSE **strictly below 0.43237401093012334**; the executable
policy should bind the verified target statistics and precise comparison rather
than copy a rounded decimal from this report. This is necessary but insufficient
for convergence. A larger positive R² margin is a project-policy decision that
must be stated prospectively; it is not implied by the zero-skill definition.
[Hernández-Lobato and Adams, Table 1 and §5.1](https://proceedings.mlr.press/v37/hernandez-lobatoc15.pdf)
uses Boston Housing, random repeated train/test splits, and prediction in
original target units; it supplies no California Housing standardized-RMSE floor
for this recipe.

## Reproduction and required next actions

[`supervised-anchor-inputs.json`](supervised-anchor-inputs.json) retains exact
artifact hashes, all measured label counts, housing statistics, and binomial
critical counts. The analysis script completed with exit `0`:

```sh
python3 DEVELOPMENT_PLAN/attestations/phase278-20261015-mac-review/calculate-supervised-anchor-inputs.py .build/phase278-anchor-review/datasets
```

The three input artifact URLs are
[MNIST test labels](https://ossci-datasets.s3.amazonaws.com/mnist/t10k-labels-idx1-ubyte.gz),
[Fashion test labels](https://raw.githubusercontent.com/zalandoresearch/fashion-mnist/master/data/fashion/t10k-labels-idx1-ubyte.gz),
and [California Housing](https://ndownloader.figshare.com/files/5976036).
They are dataset-only observations. No trained model outputs were read by the
analysis script, and this successful calculation is not a jitML validation gate.
Large CIFAR/Tiny archive downloads were terminated before completion; their
partial files are not verified evidence.

1. Keep the independent-anchor obligation open. Specify an independently
   justified compact-graph convergence contract, or reproduce a published graph,
   dataset selection, and schedule closely enough for its cited target to apply.
   Merely substituting the additional anti-trivial floor would weaken the
   existing obligation. Review the Tiny class-coverage confound before fixing
   its data-selection policy; changing selection also changes the recipe.
2. Bind the additional classification and positive-R² predicates to exact
   verified evaluation data, and add controls rejecting every constant
   classifier, the housing mean predictor, and equality at the regression
   zero-skill boundary. Retain actual served-byte evaluation and existing
   stronger convergence requirements. Review any needed lint/criterion schema
   changes explicitly; current constructors only admit their existing rules.
3. Once the complete policy and source are frozen, issue fresh passing
   **complete 55-row journals in all three lanes**, then pin them and regenerate
   the aggregate. A changed supervised bar changes its affected row contract
   digests; it does not imply every row digest changes. The retained complete
   journals cannot be rewritten to manufacture compatibility.
4. Run Phase 278's four validation commands and the final standing integration
   invocation on that source, retain authentic results, and only then consider
   closure and the next numerical phase.

The current Mac exposes Apple M1 Max Metal and a Linux/aarch64 Docker VM. The
VM advertises only `runc` runtimes, has no NVIDIA device nodes or kernel driver,
and `docker run --gpus all` exits **125** because no GPU-capable device driver
can be selected; see [host-probes.json](host-probes.json). This is a negative
capability diagnostic, not a failed jitML substrate test. The CPU and Apple
lanes were not validated in this session. Native/container build attempts were
interrupted with exit **130**; the documentation validator did not start. No
Phase 278 gate executed. The [session index](README.md) owns that hardware and
command handoff.

A future supervised-contract change would require fresh CUDA evidence, which
cannot be produced on this hardware. This conditional boundary does not mean
the unchanged source's already-retained CUDA journal became invalid merely
because this review was written. There is also an unresolved ownership issue:
[standards M(b)/(d)](../../development_plan_standards.md#m-forward-only-single-accelerator-numerically-ordered-phases)
requires one accelerator per phase and one-host closeability. The three-lane
reissue consequence above must be reconciled into independently owned per-lane
sessions and a CPU aggregation boundary; it is not authorization to make
Phase 278 require both accelerator runs in one session. Leave that scope
tension explicit until the plan and executable evidence requirements agree.

Phase 278 remains the first open owner, and later open phases remain blocked
under the ordered execution rule. This review resolves the diagnosis and
specifies additional controls; it does not resolve the independent
published-anchor obligation or missing execution evidence.
