# Phase 164: Full Workflow Control Surface

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Full Workflow Control Surface. Single-session phase migrated from legacy Sprint 14.1 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 164.1: Full Workflow Control Surface [✅ Done]

**Status**: Done (`linux-cpu` scope; validated 2026-06-17, Apple M1 Max host)
**Implementation**: `src/JitML/Web/Contracts.hs`, `src/JitML/Web/Server.hs`,
`web/src/Panels/*`, `src/JitML/App.hs`, `src/JitML/Service/*`
**Previously blocked by**: Phase `13` Sprint `13.1` (Phase `11` Sprint `11.9`
and Phase `12` Sprint `12.13` are now `✅ Done`; their browser/product live
obligations are owned here in Sprint `14.1` / `14.2` per rule E)
**Docs to update**: `documents/engineering/purescript_frontend.md`,
`system-components.md`

### Objective

Expose every no-caveat runtime workflow through generated browser contracts and
the PureScript app.

### Deliverables

- Browser-generated contracts cover typed request/response/event payloads for
  training control, RL control, tuning control, checkpoint browse, inference,
  image upload, adversarial game moves, adversarial replay, and workload status.
- Training panels start every committed SL experiment, display loss/validation
  curves, throughput, device telemetry, checkpoints, TensorBoard links, and
  pause/resume/stop outcomes.
- Model interaction panels cover MNIST drawing, CIFAR/Tiny ImageNet upload,
  generic tensor inference, checkpoint swap/compare, and output visualizations
  appropriate to each model family.
- RL panels animate live environment frames, reward distributions, policy/action
  probabilities, replay-buffer state, and recorded trajectory scrub/replay.
- Adversarial game panels render Connect 4, Othello, Hex, and Gomoku boards,
  legal moves, MCTS visit distributions, value estimates, engine analysis, and
  interactive replay from persisted game transcripts.
- Hyperparameter panels launch/stop sweeps, render live frontier/heatmap/state,
  inspect trials, and promote a trial to a checkpointed run.

### Validation

This sprint closes on `linux-cpu` (single host) per standards rule M(b)/(d); the
per-accelerator browser/Playwright lanes are owned downstream by Sprint `15.20`
(`linux-cuda`) and Sprint `16.11` (`apple-silicon`).

- `docker compose run --rm jitml jitml lint purescript`
- `docker compose run --rm jitml jitml test jitml-e2e --linux-cpu`

### Remaining Work

None for the `linux-cpu` scope owned by Sprint `14.1`. The historical gaps in
checkpoint browse, workflow-state reconciliation, and persisted transcript replay
remain closed by the 2026-06-23 live Playwright expansion, and Sprint `14.3`
re-validates the broader browser matrix at **15/15** after the full-width demo
runtime replacement.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
