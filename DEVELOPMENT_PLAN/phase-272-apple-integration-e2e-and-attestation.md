# Phase 272: Apple Integration, E2E, and Attestation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Integration, E2E, and Attestation. Single-session phase migrated from legacy Sprint 30.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-09-01 continuation checkpoint). Phase `271` closed with
complete 55-row execution-derived Metal evidence and final-source validation.
Phase `272` remains the first executable owner. Its complete ten-stanza Apple
lane is green; the separately required live e2e command, attestation refresh,
standalone gates, and final documentation/code-quality validation remain open.

## Sprint 272.1: Apple Integration, E2E, and Attestation [🔄 Active]

**Status**: Active
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/TrainerExecution.hs`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`, `../documents/engineering/training_workloads.md`

### Objective

`jitml test all --apple-silicon` runs every Apple-supported product row for real
on the Mac host, live Playwright hits the Apple edge and renders row-specific
trained artifacts, and the committed `apple-silicon` attestation records the
row-complete evidence for the lane.

### Deliverables

- `jitml test all --apple-silicon` runs every Apple-supported product row for real
  on the Mac host: real training/RL/tune/inference through host-daemon routing
  that fails closed if the host daemon or Metal runtime is absent.
- Live Playwright (`playwright/jitml-demo.spec.ts`) hits the Apple edge and
  renders row-specific trained artifacts, never a fake browser runtime or static
  generated row-name list.
- The `apple-silicon` report card includes row ids, Metal device evidence,
  integration evidence, and e2e evidence, distinguishing unsupported rows from
  failed supported rows.
- The refreshed `apple-silicon` attestation is committed under
  `DEVELOPMENT_PLAN/attestations/` for the aggregation phase to consume.

### Validation

```bash
./bootstrap/apple-silicon.sh doctor
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal run exe:jitml -- test all --apple-silicon
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal run exe:jitml -- test jitml-e2e --live --apple-silicon
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-show-details=direct --test-options='-p apple-silicon'
PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-e2e --test-show-details=direct
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- Restart and complete the explicit live Apple e2e command against the retained
  publication and host daemon, including a fresh 55-row acquisition and the
  row-complete Playwright matrix over the admitted artifacts. The interrupted
  2026-09-01 attempt is progress evidence only and cannot be resumed or counted
  as phase-closing validation.
- Refresh `DEVELOPMENT_PLAN/attestations/apple-silicon-report-card.md` from the
  completed lane evidence, then prove the committed fragment covers every row
  and records real Metal device, integration, and e2e evidence.
- Run the standalone Apple backend and non-live e2e gates, then run the
  documentation check, container-only code-quality gate, and phase-status
  guard over the final Phase `272` source.

### 2026-08-28 Validation Progress

- The first `test all --apple-silicon` attempt stopped before running a stanza:
  the required bind-mounted Linux container quality pass had replaced the shared
  `dist-newstyle` in-place package registration with Linux dependency ids, which
  the host linker correctly rejected as unusable. This is not test evidence.
- The generated 2.2 GiB Linux build tree was moved intact to
  `.build/dist-newstyle-linux-phase271` for recovery/diagnosis. The host commands
  now rebuild a fresh default `dist-newstyle`, which also governs the nested
  Cabal stanza invocations emitted by `jitml test`.
- The clean-host retry rebuilt all 305 library modules and linked the CLI, then
  ran `jitml-unit` for real. It exposed 13 / 904 failures and correctly blocked
  the nine later stanzas. All 13 failures had one portability cause: report
  contract fixtures named `/bin/true` or `/bin/false`, paths present in the
  Linux image but absent on this Apple host. The fixtures now use the stable
  `/usr/bin/true` and `/usr/bin/false` paths that exist in both environments.
  The affected `ProductScenarioReport` group then passed 15 / 15, and the whole
  `jitml-unit` stanza passed 904 / 904 in 61.86 seconds. A full-lane retry remains
  required before this result can count as phase-closing evidence.
- The next full-lane retry passed `jitml-unit` (904 / 904) and executed the real
  live WorkflowMatrix successfully in 9,014 seconds, including the canonical
  100,000-step CartPole run and 64-trial tuning sweep. `jitml-integration`
  nevertheless ended with 73 / 197 failures, so the eight later stanzas were
  correctly not run. The retained failure evidence showed the required
  host-native Engine was not running: all four `jitml-host` subscriptions were
  absent and correlated inference received no Engine reply. The supported
  `./bootstrap/apple-silicon.sh run-daemon` path is now running and reports
  Metal acquisition, four connected consumers, `ready`, and healthy probes. A
  failures-only integration rerun and then the complete lane remain required;
  the failed invocation is not closing evidence.
- The daemon-backed retry exposed a second independent fail-closed boundary
  before its already-running WorkflowMatrix could complete: the isolated
  ProductScenario workspace linked repository runtime state but not the fixed
  host bridge directory, so its first Apple publication correctly rejected the
  absent relative `.build/host` capability. The failed run was stopped after
  retaining that evidence. Apple ProductScenario acquisition now links the
  repository `.build/host` directory into its isolated workspace alongside the
  existing runtime link. An equivalent isolated `mnist-shallow-mlp` publication
  then completed real Metal training and admission (`eligible: 1`, `errors: 0`),
  and the orchestrated focused acquisition completed that first row and advanced
  to `mnist-deep-mlp`. The focused diagnostic was stopped there to avoid
  duplicating the same 55-row workload owned by the required complete-lane
  rerun; it is diagnostic evidence, not phase-closing evidence.
- The required post-fix `jitml test all --apple-silicon` rerun passed
  `jitml-unit` 904 / 904, and its authenticated ProductScenario acquisition
  finalized all eleven supervised rows plus all six PPO rows in registry order.
  Its fresh `A2C/cartpole` execution then completed the exact 1,228,800-step
  schedule but correctly failed admission: the evaluated
  `median_final_reward` was `183`, below the unchanged `435` threshold. The
  dependent Phase `262` cases consequently reported the one failed acquisition.
  The already-doomed invocation was stopped before duplicating another
  multi-hour WorkflowMatrix; it is retained diagnostic evidence, not closing
  evidence. Phase `271` had reused this row's pre-arithmetic-alignment admission
  and retrained only its eight formerly rejected rows, so this was the first
  current-source fresh execution of `A2C/cartpole`. A2C now consumes each
  rollout once instead of applying PPO's ten old-policy epochs to its unclipped
  surrogate; the fix is algorithm-specific and substrate-independent, and the
  frozen convergence bar is unchanged. A fresh isolated current-source Apple
  rerun then exited `0` with `eligible: 1`, `errors: 0`; its typed-decoded
  manifest records `median_final_reward = 500`, the exact unchanged `435` bar,
  1,228,800 observed transitions, 19,200 optimizer updates, and the real Metal
  execution witness for artifact SHA-256 prefix `a6009a819be6f7fc`. The focused
  product-update invariant passed 1 / 1. The persisted `cifar10-vit` manifest
  from the failed full run also bound the expected fixed-bridge artifact and
  digest. Fresh focused executions of the other affected cohorts also exited
  `0` and admitted: `A2C/mountain-car` measured `-124`,
  `A2C/lunar-lander` measured `271.16`, and `A2C/key-door-grid` measured `1.43`.
  Thus all four A2C product rows have current-source real-Metal evidence for the
  one-pass correction. A complete final-source lane restart remains required.
- The final-source complete-lane restart passed its 905-case `jitml-unit`
  stanza and then executed all 55 ProductScenario rows on the Apple lane. Every
  row-specific integration case passed, as did the exact 55-row admitted
  inventory, 11/39/4/1 family split, canonical order, persistent journal
  round-trip, and authenticated browser-catalogue publication. The subsequent
  Phase `263` committed-fragment comparator found one exact stale cell:
  `california-housing-mlp` was still labelled with the fixed-bridge layer-graph
  witness even though this run issued
  `device:apple-silicon:metal:mlp-forward-backward-tanh-linear:a6009a819be6f7fc`.
  The already-doomed invocation was stopped before duplicating the later
  multi-hour WorkflowMatrix. The report-card fragment now carries that exact
  live-issued cell; the named comparator and then the complete lane must pass
  before this evidence can close the phase.
  The focused committed-attestation aggregation guard subsequently passed
  `1 / 1`; the complete live comparator remains authoritative and will be
  exercised by the required final-source lane restart.
  That restart passed its 905-case `jitml-unit` stanza after a clean diff check
  and successful Apple stage-0 doctor; its fresh isolated
  `jitml-integration` ProductScenario finalized all eleven supervised rows,
  including the MLP-witnessed `california-housing-mlp`, all six PPO rows,
  all four corrected A2C rows, all four TRPO rows, all four MaskablePPO rows,
  all four RecurrentPPO rows, all three DQN rows, all three QR-DQN rows,
  `DDPG/lunar-lander`, `TD3/lunar-lander`, both SAC rows,
  `CrossQ/lunar-lander`, `TQC/lunar-lander`, all four ARS rows,
  `HER/goal-reaching`, all four AlphaZero rows, and hyperparameter tuning
  (**55 / 55** total). The committed-fragment comparator and the other
  ProductScenario assertions passed. The post-acquisition live WorkflowMatrix
  passed in 9,209.46 seconds, and the complete orchestrator then passed all ten
  stanzas (`10` passed, `0` failed, `0` not-run) in 113,237.84 seconds:
  `jitml-unit`, `jitml-integration`, `jitml-sl-canonicals`,
  `jitml-rl-canonicals`, `jitml-hyperparameter`, `jitml-backends`,
  `jitml-daemon-lifecycle`, `jitml-e2e`, `jitml-negative-controls`, and
  `jitml-model-convergence`. This is the complete-lane closing evidence; the
  separately required live e2e invocation remains incomplete at the
  2026-09-01 continuation checkpoint below.
- The Phase `272` engineering-doc updates now record the Apple full-lane,
  explicit live-browser, and A2C rollout-pass contracts in
  `documents/engineering/unit_testing_policy.md` and
  `documents/engineering/purescript_frontend.md`, and
  `documents/engineering/training_workloads.md`. Their final documentation and
  code-quality validation remains part of the phase-closing gate.
- The legacy Phase `30` fragment's declared device strings have been replaced
  by the artifact-bound cells derived from the current Metal artifacts: ten
  layer-graph rows name the typed-decoded live artifact, and the remaining 45
  rows name the current MLP artifact already exercised by the completed Phase
  `271` producer. The first live RL manifest further fixed the exact MLP backend
  identity as `metal`. A successful integration run's authenticated
  `renderProductLaneAttestationFragment` comparison remains the authority: any
  cell drift fails this lane, and only its successful issued fragment can close
  the attestation obligation.

### 2026-09-01 Continuation Checkpoint

- The separately required
  `jitml test jitml-e2e --live --apple-silicon` attempt reused the retained
  publication and healthy host daemon, then advanced its fresh isolated
  acquisition through rows 1–54 in registry order. `gomoku` completed and the
  final `hyperparameter-tuning` row remained healthy and CPU-active after about
  97 minutes when the user requested a stop. The command was interrupted
  cleanly with exit `130`; its test-worker tree exited, while the retained host
  daemon remained running. The outer 55-row assertion had not flushed and
  Playwright had not started, so this invocation is not validation evidence and
  the command must restart from the beginning in the continuation session.

2026-07-06 closing validation: the refreshed Apple backend evidence validates the
fixed-bridge Metal kernel surface that underlies the committed
`apple-silicon` fragment. The Phase `30` lane is closed on its Apple-host
obligations, and Phase `31` now consumes this committed fragment alongside the
fresh `linux-cuda` and `linux-cpu` fragments.

### Closure Evidence

- **Closed Exit-Definition obligation**: `jitml test all --apple-silicon` must run
  every Apple-supported product row for real — real training/RL/tune/inference
  through host-daemon routing, live Playwright rendering of row-specific trained
  artifacts, and a refreshed 55 / 55 `apple-silicon` attestation whose per-row
  evidence is real — only after Phases `19`–`28` close the underlying model realness
  and Sprints `30.1`–`30.2` land real Metal kernels and real device evidence.
- **Closing validation**: once the `jitml-negative-controls` stanza (Phase `32`,
  [phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map))
  and the per-model `jitml-model-convergence` suite (Phase `33`,
  [phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map)),
  governed by Phase `34`
  ([phase-34-plan-truth-governance.md](README.md#legacy-to-new-phase-map)), pass on
  `linux-cpu`, re-run `jitml test all --apple-silicon` and re-commit the refreshed
  attestation for Phase `31` aggregation — `apple-silicon` plus `linux-cpu` only,
  never `linux-cuda` in the same gate.

## Documentation Requirements

**Engineering docs to create/update:**

- `../documents/engineering/unit_testing_policy.md` — record the current Apple
  full-lane and live browser validation contract.
- `../documents/engineering/purescript_frontend.md` — record the row-complete
  Apple edge/Playwright evidence boundary.
- `../documents/engineering/training_workloads.md` — record A2C's one-pass
  old-policy rollout contract discovered by fresh Apple acquisition.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
