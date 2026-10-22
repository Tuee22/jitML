# Phase 278 Full-Budget CPU TRPO Evaluation Diagnostic

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Retain one unchanged canonical-budget training capture and paired
> pure/selected-device evaluation without attributing the convergence failure.

The diagnostic uses the preserved `4b5…` implementation, real Linux CPU lane,
and seed **42** for **150 × 512 × 16 = 1,228,800** transitions. Public production
descriptor/schedule/budget values and all adapter configuration fields agree.
The public trainer returns **150** rollout summaries, **2,051** learned
parameters, and **192,150 actual optimizer applications** in **308.216 s**.
Those counters belong to this diagnostic capture. They do not retroactively
attest the separately retained focused CLI failure.

Both the unchanged public pure evaluator and the real selected CPU device
produce **230** in every one of **20** deterministic evaluation episodes:
**231 steps**, environment termination, and terminal-transition reward **0**.
The diagnostic pure trace exactly reproduces the public evaluator. The
independent decoder checks all **4,620 events per path**: paired observation
bytes and chosen actions match throughout every trajectory. Pure/device logits
differ numerically from the all-zero initial observation, but **no action
divergence** occurs. Exact observations, outputs, actions, binary64 bytes, and
the full final parameter vector remain in the raw evidence. Evaluation
precision therefore does not explain this run's **230** result. This does not
waive the independently required selected-device evaluation contract.

The largest rollout-summary mean/median occurs at iteration **87**:
**380.272727 / 358**. The final iteration **149** reports **222.342105 / 211.5**.
Seventeen iteration summaries contain a completed episode with `max_reward=500`
(indices **9, 10, 74, 79, 85, 87, 88, 89, 104, 108, 111, 124, 125, 126, 127,
130, 145**). This demonstrates horizon-reaching rollout episodes, not captured
per-step GAE targets or a proven cause of the CPU **230** / Metal **219** misses.
The complete 150-point statistics and descriptive ten-iteration blocks support
further method review without a seed, budget, threshold, or field retune.

The [original narrative](raw/README.md.txt), [original manifest](raw/manifest.json),
and [retention map](retention-map.json) preserve every reviewed original byte.
The first setup attempt fails compilation before training; the second is the
only full-budget execution, exits **0**, and passes all source/runtime bindings.
All **29** raw receipt stream pairs are independently rehashed. The source-as-text,
package IDs, compiled-library/ELF identities, actual process/JIT mapping, and
before/after inventories remain intact. Large binaries remain ignored.

The private source `4b5…`, CLI `064aa7c9…e6640`, compiled libraries/configuration,
and complete listed private tree stay unchanged. Native `73cd7e15…1ebbb24d`
stays untouched and the canonical checkpoint namespace remains absent. The
thirteen separately authorized host source/documentation changes are explicitly
listed in the [execution binding](raw/attempts/20261015T232642.850436Z/binding.json);
this is not an unchanged-host claim. No checkpoint, CompletedTraining,
publication, eligibility evidence, lane journal, GateTranscript, or phase
closure is issued by this diagnostic.
