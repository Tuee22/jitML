# Phase 24: Real Supervised Architectures

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [development_plan_standards.md](development_plan_standards.md), [phase-23-general-differentiable-layer-engine.md](phase-23-general-differentiable-layer-engine.md), [phase-25-real-rl-algorithms-and-environments.md](phase-25-real-rl-algorithms-and-environments.md), [../documents/engineering/training_workloads.md](../documents/engineering/training_workloads.md), [../documents/engineering/training_metrics_and_splits.md](../documents/engineering/training_metrics_and_splits.md), [../documents/engineering/checkpoint_format.md](../documents/engineering/checkpoint_format.md), [../documents/engineering/product_completion_contract.md](../documents/engineering/product_completion_contract.md)
**Generated sections**: none

> **Purpose**: Every canonical supervised row is its literal named architecture,
> assembled from the Phase `23` layer engine, and trains to its
> literature-anchored convergence bar on `linux-cpu`.

## Phase State

⏸️ **Blocked** at Sprint `24.1`, which is blocked by Sprint `23.3`. The
2026-07-18 audit found that the widened patch/MLP-Mixer execution path is not
the literal named LeNet, ResNet, WideResNet, ResNet-50, or ViT architecture
promised by the registry, and the prior feature comparison inspected a
different decorative graph. Sprint `24.2` is blocked by `24.1`; Sprint `24.3`
is blocked by `24.2`.

Completed Sprint `10.6` persists the exact current Mixer executable, including
the compact `cifar10-vit` patch size/stride `4/4` and 64-token mixing count.
That bounded convergence correction is not a literal two-head ViT with the
declared LayerNorm/GeGLU structure, does not make `archLayerGraph` executable,
and transfers none of Sprint `24.1`'s ownership; this phase remains Blocked.

### Historical Closure Context

The 2026-07-10 `linux-cpu` results (`jitml-sl-canonicals` 31/31,
`jitml-negative-controls` 3/3, `jitml-model-convergence` 111/111, `jitml-unit`
278/278, and `jitml-integration` 137/137) remain dated evidence for the models
that actually ran. They do not prove the literal named architectures or their
exact completion inputs and therefore cannot close the reopened sprints.

**Validation substrate**: `linux-cpu` only.

## Objective

Every documented supervised-learning row is its literal named architecture, built
as a typed layer graph over the Phase `23` layer engine: LeNet-5, a deep MLP with
BatchNorm and Dropout, a small ResNet, ResNet-20, ResNet-56, WideResNet-28-10, a
small ViT, ResNet-50, and the tabular MLP. No simplified topology satisfies a row
that names BatchNorm, Dropout, Conv2D, ResNet, WideResNet, ViT, or GroupNorm — the
implemented block counts, widths, residual connections, normalization, and
attention match the documented model. Each row trains on a real three-way split
with real losses (cross-entropy for classification, MSE/RMSE for regression),
records deterministic init/final weight hashes, update count, examples seen, and
throughput, and clears `median(k=5) >= literature_target - slack`. Each row
produces measured completion evidence and the exact executed graph needed by
the checkpoint writer. Phase `24` does not claim that an in-memory completion
value or historically stored manifest is inference eligible.

## Sprint 24.1: Literal Architectures [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/Architecture.hs`, `src/JitML/Product/Matrix.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `23.3`
**Docs to update**: `../documents/engineering/training_workloads.md`, `../documents/engineering/numerical_core.md`, `../README.md`

### Objective

Every supervised `ProductRow` is constructed as a literal layer graph over the
Phase `23` typed layer engine, so the implemented model is the named architecture
rather than a shared flat topology standing in for many rows.

### Deliverables

- LeNet-5, the deep MLP with BatchNorm and Dropout, the small ResNet, ResNet-20,
  ResNet-56, WideResNet-28-10, the small ViT, ResNet-50, and the tabular MLP are
  each built in `src/JitML/SL/Architecture.hs` as literal layer graphs with the
  documented block counts, channel widths, residual connections, normalization
  (BatchNorm / GroupNorm), Dropout, Conv2D/pooling, and attention blocks.
- Each supervised row in `src/JitML/Product/Matrix.hs` binds to the constructing
  function and records the concrete architectural features it claims (BatchNorm,
  Dropout, Conv2D, GroupNorm, residual, attention).
- A test rejects any row whose documented feature set exceeds the implemented
  layer graph; no simplified topology satisfies a row naming BatchNorm, Dropout,
  Conv2D, ResNet, WideResNet, ViT, or GroupNorm.

### Remaining Work

- Implement every canonical supervised row as its literal named architecture
  on the single executable Sprint `23.3` graph, including real convolution,
  pooling, normalization, residual/bottleneck depth, width, patch, and attention
  structure rather than a shared patch/MLP approximation.
- Bind the registry's claimed features and block counts to that executed graph,
  and make a simplified or mislabeled topology fail the production-path test.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation

Historical validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 28 / 28 on 2026-07-02, including the
ProductRow feature-parity, literal topology block-count, simplified-topology
negative case, and live SL materialization/training tests. `docker compose run
--rm jitml jitml test jitml-unit --linux-cpu` passed 270 / 270, `jitml docs
check` passed, and `docker compose run --rm jitml cabal run exe:jitml --
check-code` passed after formatting the Sprint `24.1` Haskell edits.

2026-07-05 realness-audit finding, closed 2026-07-06: the layer graph previously built and trained
by `layersForFamily` (`src/JitML/SL/Architecture.hs`~`249`) is a residual-MLP
over flattened pixels for every ResNet, WideResNet, ResNet-50, and LeNet row — a
`Dense` stem, `N` two-layer `ResidualSpec` blocks (`Architecture.hs`:`261`), and
a `Dense` classifier — with no `Conv2D`, pooling, normalization, or attention on
the trained path, and `ResNet-50` (`familyForModel "ResidualBlock50"`,
`Architecture.hs`:`445`) reuses the `ResNet-20`/`ResNet-56` residual-MLP template
with no bottleneck topology. The simplified-topology negative case passes only
because it inspects `architectureLayerGraphForFamily`
(`Architecture.hs`:`484`,`:492`), which is never trained or served, so no
rejection actually guards the model that runs.

### Historical Closure Evidence (withdrawn by the 2026-07-18 audit)

- **Target Exit-Definition obligation**: each supervised row must be its literal
  named architecture on the *trained* path — real `Conv2D`/pooling and
  BatchNorm for LeNet-5, real residual convolutional blocks at the documented
  depths/widths for the small ResNet, ResNet-20, ResNet-56, and WideResNet-28-10,
  a genuinely distinct ResNet-50 bottleneck, and real patch-embedding plus
  self-attention for the ViT — not a residual-MLP over flattened pixels shared
  across families.
- Build the real topology in `src/JitML/SL/Architecture.hs` and train *that*
  graph, retiring the untrained `architectureLayerGraphForFamily` parity
  stand-in so the completion boundary receives the graph that training
  executed.
- **Closing validation**: the "dense layer labelled as convolution must be
  rejected" differential control and the untrained-graph controls in the
  `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](phase-32-external-truth-realness-harness.md))
  must reject the current MLP-for-conv stand-in, exercised via
  `docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu`.

Historical 2026-07-10 closure claim: the trained architecture path implemented
the widened Mixer blocks and raised clamps then treated as the expanded end
state, and
`jitml-sl-canonicals --linux-cpu` passed **31 / 31**. The contemporaneous served
path claim is historical. Sprint `10.6` revalidates trained-versus-loaded V2
parity only for the exact current executable; it does not restore the withdrawn
literal-architecture claim.

## Sprint 24.2: Convergence and Evidence [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `test/sl-canonicals/Main.hs`, `src/JitML/Test/RowAssertions.hs`
**Blocked by**: Sprint `24.1`
**Docs to update**: `../documents/engineering/training_metrics_and_splits.md`, `../documents/engineering/numerical_core.md`

### Objective

Each supervised row trains a real train/validation/test split to its
literature-anchored convergence bar and records machine-checkable learning
evidence, so a row cannot pass on a static, degenerate, or smoke-threshold run.

### Deliverables

- Each supervised row records a deterministic initial-weight hash, final-weight
  hash, update count, examples seen, and throughput (examples/sec).
- Classification rows optimize real cross-entropy; regression rows optimize real
  MSE and report RMSE — `1 - accuracy` is not a loss.
- Training uses a real three-way split and the reported figure is the held-out
  test metric, which clears `median(k=5) >= literature_target - slack`.
- `src/JitML/Test/RowAssertions.hs` fails a row when final weights equal
  initialization, gradients are zero or NaN, or the row clears only a smoke
  threshold; a deliberately underpowered 2-step model FAILS its bar.

### Remaining Work

- Train and measure each literal Sprint `24.1` graph from its real random
  initialization against the frozen external bar; evidence from the replaced
  approximation cannot be reused.
- Prove exact train/validation/test partitioning, train-only fitted regression
  statistics, finite learning, nonzero weight movement, and observed budgets
  for the graph that produced each metric.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
```

### Historical Validation

Historical validation: `docker compose run --rm jitml jitml test
jitml-sl-canonicals --linux-cpu` passed 31 / 31 on 2026-07-02, including the
measured supervised row evidence assertion, invalid/smoke evidence rejection,
and underpowered two-step negative case. `docker compose run --rm jitml jitml
test jitml-integration --linux-cpu` passed 79 / 79 against the live linux-cpu
cluster. `jitml docs check` and `jitml check-code` passed after the Sprint
`24.2` module/docs update.

2026-07-05 realness-audit finding, closed 2026-07-06: the recorded convergence, weight-update,
and learning-evidence figures are all measured on the residual-MLP that
`layersForFamily` trains, not on the named convolutional/attention architecture,
and the bar each row clears is self-authored rather than a frozen external
literature constant — so a passing row does not demonstrate the documented model
learning.

### Closure Evidence

- **Closed Exit-Definition obligation**: each row's held-out convergence metric
  must be *measured on the real named architecture* and cleared against a frozen
  external literature bar, not on the shared flattened-pixel residual-MLP against
  a self-authored threshold.
- **Closing validation**: the per-model `jitml-model-convergence` suite (Phase
  `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](phase-33-per-model-convergence-and-inference-tests.md)),
  which trains each `ProductRow` from a real random init through the production
  device seam and asserts the measured held-out test metric ≥ the Phase `32`
  `ExternalBars` target, must pass for every supervised row via
  `docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu`.

2026-07-10 closure: the standing `jitml-model-convergence --linux-cpu` gate
passed **111 / 111**, including the deep-SL rows measured on the widened
architecture.

## Sprint 24.3: CompletedTraining SL Manifests [⏸️ Blocked]

**Status**: Blocked
**Implementation**: `src/JitML/SL/{Architecture,TrainingExecution}.hs`,
`src/JitML/Product/Completion.hs`, `test/sl-canonicals/Main.hs`
**Blocked by**: Sprint `24.2`
**Docs to update**: `../documents/engineering/training_workloads.md`,
`../documents/engineering/training_metrics_and_splits.md`

### Objective

Every supervised row hands the checkpoint boundary its exact executed graph,
initial and final flat weights, verified dataset-at-read digest, measured update
count, exact plan identity/budget, and passing convergence observations. This
sprint owns production of those training/completion inputs. Sprint `10.6` owns
their exact V2 persistence and trained-versus-loaded parity; Sprint `10.12`
alone admits a persisted artifact as inference eligible.

### Deliverables

- Every supervised row produces non-optional completion inputs carrying exact
  `PlanId`, completed budget, convergence measurements, dataset-at-read digest,
  initial/final weight hashes, and positive measured update count.
- The architecture value paired with those inputs is the graph actually
  executed by training, with deterministic graph order and parameter flattening
  suitable for Sprint `10.6`'s virtual `Flat` slices.
- Partial, synthetic, non-finite, untrained, unchanged-weight, wrong-plan, and
  wrong-dataset training results cannot construct the completion input.
- No Phase `24` constructor mints structural checkpoint completion, an admitted
  artifact, or inference eligibility from those in-memory values.

### Remaining Work

- Produce non-optional completion inputs for the exact Sprint `24.2` run:
  canonical `PlanId`, exact dataset-at-read identity, measured budget/update
  count, passing observations, and exact initial/final JMW1 identities.
- Prove the completed supervised manifest and the model later served describe
  the same literal graph and bytes. V2 encoding remains Sprint `10.6`, and only
  Sprint `10.12` may admit persisted eligibility.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-sl-canonicals --linux-cpu
docker compose run --rm jitml jitml check-code
```

### Historical Validation (completion-input surface)

`docker compose run --rm jitml jitml test
jitml-integration --linux-cpu` passed 81 / 81 on 2026-07-02, including the
supervised completed-manifest graph/layout/evidence cases and fail-closed
partial/synthetic/untrained/malformed manifest loader cases. `docker compose
run --rm jitml jitml test jitml-sl-canonicals --linux-cpu` passed 31 / 31,
including the live MNIST and all-canonical-row supervised materialization and
training checks. `docker compose run --rm jitml jitml check-code` passed after
formatting the Sprint `24.3` integration test wrapping.

### Retained Closure Boundary

- Phase `24` closes only with each real literal trained architecture and its
  measured, non-forgeable completion inputs. Exact persistence of the current
  Mixer executable does not meet that boundary, and this phase does not own
  persistence or loaded execution.
- The 2026-07-02 and 2026-07-10 checkpoint-reader results exercised the prior
  named-tensor format. They remain historical diagnostics and do not satisfy
  Sprint `10.6`'s V2 one-blob/virtual-slice parity or Sprint `10.12`'s persisted
  proof admission.

2026-07-10 validation showed the widened training path produced completion
values and passed `jitml-negative-controls --linux-cpu` **3 / 3** plus
`jitml-integration` **137 / 137**. Its contemporaneous claim that the stored
manifests were inference eligible is historical only; the current exact
artifact and admission gates are Sprints `10.6` and `10.12`.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/training_workloads.md` — distinguish the exact current
  `[LayerSpec]` / `[LayerState]` Mixer executable and its V2 persistence from
  the literal per-row architectures this Blocked phase must assemble over the
  single Phase `23` graph. The current `cifar10-vit` contract is 4×4/64 tokens;
  it is not the literal small-ViT completion.
- `documents/engineering/training_metrics_and_splits.md` — three-way splits, real
  cross-entropy / MSE-RMSE losses, frozen literature-anchored convergence bars,
  and fresh measurements from the literal Sprint `24.1` graphs; measurements
  from the current Mixer approximation cannot be reused for closure.
- `documents/engineering/numerical_core.md` — state both representations
  honestly: the current executable Mixer primitives persisted by Sprint `10.6`
  and the one differentiable typed graph plus literal layer semantics still
  owned by Sprints `23.1` and `24.1`.
- `documents/engineering/checkpoint_format.md` — the supervised completion
  inputs supplied by whichever graph actually trained; Sprint `10.6` owns exact
  V2 persistence of the current executable, Sprint `10.12` owns inference
  admission, and neither makes the current Mixer a literal Phase `24` model.

**Product docs to create/update:**
- `README.md` — canonical supervised learning problems distinguish the intended
  literal architecture from the current executed approximation until this
  phase closes.

**Cross-references to add:**
- Add this phase to `README.md`, `00-overview.md`, `system-components.md`, and
  `development_plan_standards.md`.
- Link supervised convergence and checkpoint evidence from
  `../documents/engineering/product_completion_contract.md`.
