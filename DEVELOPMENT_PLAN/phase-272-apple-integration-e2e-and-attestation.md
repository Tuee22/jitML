# Phase 272: Apple Integration, E2E, and Attestation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple Integration, E2E, and Attestation. Single-session phase migrated from legacy Sprint 30.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done** (closed 2026-09-07). Phase `271` closed with complete 55-row
execution-derived Metal evidence and final-source validation. Phase `272`'s final-source explicit live
Apple e2e command is green. The final-source complete ten-stanza Apple lane is
still open because its earlier `10 / 10` result predates the shared Pulsar
batch-transport fix. A final-source rerun was interrupted at the user's stop
request and is not closing evidence. The next clean-host rerun passed
`jitml-unit` but exited `1` in `jitml-integration`: the rebuilt cluster's live
canonical-dataset inventory was empty (`[]` rather than the governed twelve
objects), so the WorkflowMatrix reported a missing MinIO object and the shared
ProductScenario acquisition failed closed. The next continuation restored the
cluster and host daemon: bootstrap passed, all twelve verified datasets were
staged, the focused live inventory gate passed, and the real Metal daemon
reached readiness. Its fresh complete lane passed `jitml-unit`, completed five
ProductScenario rows, and reached `cifar10-resnet20` before it was intentionally
interrupted at the user's stop request without a terminal status. The lane,
daemon, and Kind cluster were stopped; that attempt is not closing evidence.
The latest continuation rebuilt immutable image
`sha256:550cab9db6cc1f835e1b938b9a57a3ffa7d32f44d822c2d62fdbb2441b6bf5e3`,
completed all **111** bootstrap steps, restaged and live-verified all twelve
datasets, and restored the ready four-consumer Metal daemon. Its fresh complete
lane passed `jitml-unit`, completed eight ProductScenario rows, and reached
`cifar10-vit` before it was intentionally interrupted at the user's stop
request without a terminal status. The lane, daemon, and Kind cluster were
stopped; this attempt is not closing evidence. A fresh full-lane rerun,
attestation refresh, and the standalone, documentation, code-quality, and
phase-status gates remain open. The final continuation used immutable image
`sha256:55975f2ec4db8eaf9dacee5b125ea1ed4dfb028c88a44b78a1ee232a1189ea6f`:
bootstrap completed all **111** steps, all twelve exact dataset objects passed
the focused live gate, and the real-Metal daemon reached readiness with four
connected consumers. Its fresh complete lane passed `jitml-unit`, completed
eight ProductScenario rows through `cifar100-wide-resnet`, and reached
`cifar10-vit` before the user's stop request. The intentional interrupt produced
terminal status `2`; it is not closing evidence. The lane and daemon are
stopped, the Kind cluster is deleted, and a fresh full-lane rerun remains open.
The latest continuation used immutable image
`sha256:2365ac55ef5fc8accee708acba8243d95d6d8248b6a52a11d92ce19ec51f66d7`:
bootstrap passed all **111** steps, doctor passed, all seven components reported
ready, edge readiness passed, all twelve exact datasets passed the focused live gate **1 / 1** in
5.74 seconds, and the real-Metal daemon reached readiness with four consumers.
The fresh complete lane passed `jitml-unit` and
`jitml-integration` completed `mnist-shallow-mlp`, `mnist-deep-mlp`,
`mnist-lenet`, `fashion-mnist-mlp`, `fashion-mnist-resnet`,
`cifar10-resnet20`, `cifar10-resnet56`, and `cifar100-wide-resnet`, then
advanced to the ProductScenario `cifar10-vit` row. At the user's stop request,
the intentional interrupt produced terminal status `2` before that row
returned. The attempt is not closing evidence; the lane and daemon are stopped,
the Kind cluster is deleted, and the complete ten-stanza rerun remains open.
The final continuation ran from that checkpoint on immutable image
`sha256:d4094b5ac0a70b2aa7bf3748e987e48516b237394521cbf7c0effdbfd550f27e`.
The clean Apple host build compiled all **305 / 305** library modules; the image
build completed in 45m26s; bootstrap passed all **111** rollout steps; doctor,
all seven component statuses, and edge readiness passed; all twelve exact
dataset artifacts matched their governed SHA-256 pins and uploaded with exact
accepted bytes; and the focused live inventory/body gate passed **1 / 1** in
5.72 seconds. The real-Metal daemon reached readiness with four consumers. The fresh
complete lane passed `jitml-unit`; `jitml-integration` completed
the first eight ProductScenario rows through `cifar100-wide-resnet`, then
advanced to `cifar10-vit`. At the user's stop request, the lane was intentionally
interrupted before that row returned and wrote terminal status `2`; neither the
partial integration stanza nor the invocation is closing evidence. The lane and
daemon are stopped, the Kind cluster is deleted, and the complete ten-stanza
rerun remains open. A subsequent continuation rebuilt immutable image
`sha256:e06058d13cdc208ab3f2625fad23319c8cc1b43dd203a5a76b97ad7da204c91e`
in 45m18s and completed all **111** rollout steps. Doctor, all seven component
statuses, edge readiness, the twelve exact dataset uploads, and the focused
live inventory/body gate (**1 / 1** in 5.70 seconds) are green. The
four-consumer real-Metal daemon reached readiness. The fresh complete lane passed
`jitml-unit`; `jitml-integration` completed all ten supervised ProductScenario
rows, including the 1h49m `cifar10-vit` and 1h12m
`tiny-imagenet-resnet50` rows, plus `PPO/cartpole`, `PPO/mountain-car`, and
`PPO/acrobot`, then advanced to `PPO/lunar-lander`. The user's stop request
intentionally interrupted the lane before that row returned; the wrapper
recorded terminal status `2`, so neither the partial integration stanza nor the
invocation is closing evidence. The lane and daemon are stopped, the Kind
cluster is deleted, and a fresh complete-lane rerun remains required. At the
user's subsequent direction, work resumed from the preserved Apple host build
tree as the `resume7` lifecycle. It ran from the same final source and exited
`0`: all **55 / 55** ProductScenario rows returned, the authenticated journal
re-minted the exact committed fragment, and all ten stanzas passed with `0`
failed and `0` not-run in 116,396.918861 seconds. The standalone Apple backend
gate also passed **25 / 25** and non-live e2e passed **30 / 30**. The final
container documentation and code-quality gates passed, the focused phase-status
registry passed **6 / 6**, and the aggregation no-rerun scan inspected **20 /
20** mapped CPU-only validation blocks with **0** accelerator invocations.
Phase `272` closed and, at that closure checkpoint, Phase `273` was the first
executable owner. The later evidence-retention audit does not invalidate this
phase's runtime result; it reopens the downstream journal-retention owners.

## Sprint 272.1: Apple Integration, E2E, and Attestation [✅ Done]

**Status**: Done
**Implementation**: `test/integration/Main.hs`, `test/e2e/Main.hs`, `playwright/jitml-demo.spec.ts`, `src/JitML/RL/Algorithms/PpoTrainer.hs`, `src/JitML/RL/TrainerExecution.hs`, `src/JitML/Service/InferenceBatch.hs`, `src/JitML/Service/PulsarWebSocketSubprocess.hs`, `src/JitML/Service/Consumer.hs`, `DEVELOPMENT_PLAN/attestations/`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`, `../documents/engineering/purescript_frontend.md`, `../documents/engineering/training_workloads.md`, `../documents/engineering/daemon_architecture.md`, `../documents/engineering/pulsar_ml_workflow.md`

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

- None.

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
  `./bootstrap/apple-silicon.sh run-daemon` path was then started and reported
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
  `jitml-model-convergence`. This was complete-lane evidence for that source
  revision; the later shared Pulsar batch-transport correction described in the
  2026-09-01 continuation checkpoint requires one final-source complete-lane
  rerun. The separately required live e2e invocation also remained incomplete at
  that checkpoint.
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
- The continuation first restored the stale retained Kind publication through
  the supported `./bootstrap/apple-silicon.sh up` path. Docker had restarted
  while the retained Pulsar pods still carried five-day-old sandbox identities;
  replacing only those four controller-owned pods and replaying the chart's two
  idempotent metadata-init jobs restored the same retained volumes without
  purging data. The reconcile then completed all `113` steps, proved all `34`
  topics and every component Ready, and published immutable application image
  digest
  `sha256:3b43ac364eaa867837eafc27962c90abd276b21f21a0a02f0d435ecc9f65f8df`.
  The fixed host daemon reacquired Metal and all four Pulsar subscriptions and
  returned healthy `readyz` evidence.
- The first uninterrupted post-recovery live-e2e restart then failed closed, as
  required, before Playwright: integration observed an empty canonical-dataset
  inventory and rejected all affected product and WorkflowMatrix requests
  rather than substituting fixture data. The exact twelve Phase `262` canonical
  objects were re-downloaded from their governed upstreams, checked against the
  repository SHA-256 declarations, and staged through `jitml internal
  upload-dataset` with exact accepted byte counts and digests. This failed
  invocation is diagnostic progress only.
- The inventory-restored live-e2e restart completed all 55 ProductScenario rows,
  the additional live CartPole and MNIST tuning commands, and every integration
  assertion. Its Playwright stage then reported `20` passed, `3` failed, and
  `54` not run: repeated checkpoint browsing returned non-2xx responses, the
  Connect4 transcript id never arrived, and the first serial ProductRow could
  not load checkpoint artifacts. The browser failure is diagnostic evidence,
  not phase-closing evidence.
- Live request and daemon receipt traces isolated one cause shared by all three
  browser failures. The daemon correctly classified catalogue, adversarial, and
  transcript operations as control commands with no inference batch deadline,
  but the lower Pulsar batch transport still cancelled the whole handler at the
  configured five-second forward-pass fence. Exact 55-row re-admission routinely
  straddled that boundary, so the command was nacked and redelivered, the owned
  reply cursor timed out, and later controls starved behind it. The transport now
  carries a typed deadline mode as part of batch compatibility: forward passes
  remain deadline-enforced, while isolated controls execute under their existing
  request, retry, and drain bounds. The bounded late-publication regression, the
  new over-deadline control regression, and the complete daemon-lifecycle suite
  pass. After restarting the host Engine from the fixed binary, the pending
  over-five-second control settled successfully; five consecutive authenticated
  checkpoint requests returned HTTP `200` with the exact `40,801`-byte catalogue
  in 4–5 seconds, and live Connect4 move plus transcript replay requests both
  returned HTTP `200` with a persisted `transcripts/<sha256>.cbor` id. The pinned
  Playwright container then passed all `77 / 77` tests against the exact retained
  catalogue, including the five-request checkpoint proof, transcript replay, and
  complete 55-row serial artifact matrix. This is focused post-fix evidence; a
  fresh complete live-e2e command remains required on this final source.

### 2026-09-03 Validation Continuation

- The next exact live-e2e invocation completed a second fresh authenticated
  **55 / 55** ProductScenario acquisition. Its retained journal has run id
  `jitml-product-scenario-2c85130a2202f041`, checkpoint-scope SHA-256
  `86db4b829ca174421a8bef8d079babfc5ae1e8005d7bd2fcd42d948d9192b38f`,
  projection-batch SHA-256
  `d0b5713f59df3ea3090bab7c2615d6fcd796f4fae30c063a91213ffa308be607`,
  and file SHA-256
  `3842085a033cf0ddd6f6402a8252b992616c38483fb985ceb9adda39114e3d7b`.
  All preceding integration assertions printed `OK`, after which the command
  entered the live typed-executable WorkflowMatrix. At 08:44 the tool-owned
  execution sessions and host daemon were terminated together; the retained
  stdout ends on the still-running WorkflowMatrix case with no test failure.
  This is complete acquisition evidence but an externally interrupted command,
  so it does not close the live gate.
- A direct-session restart was stopped after one hour when a detached-process
  probe proved ordinary child jobs are reaped with their tool session. A
  `launchd` retry then failed closed before acquisition because that service
  context could not see the Metal device. The unchanged exact command was then
  restarted under the temporary `codex-phase272` tmux session, whose user-
  session context acquired the real Metal runtime and fixed bridge and connected
  all four host consumers. Its daemon, live-command, and terminal-status evidence
  was flushed under `.build/runtime/phase272-launchd-{daemon,live}.log` and
  `.build/runtime/phase272-launchd.status`; its completed result is recorded in
  the 2026-09-04 stop checkpoint below.

### 2026-09-04 Validation Continuation

- The exact final-source
  `jitml test jitml-e2e --live --apple-silicon` invocation completed with wrapper
  status `0` after `80,579.180341` seconds. `jitml-integration` passed
  **197 / 197** (`80,483.29` seconds in the test body), the pinned Playwright
  container passed **77 / 77** (`73.187756` seconds), and the Haskell
  `jitml-e2e` suite passed **30 / 30** (`0.61` seconds in the test body). The
  authenticated browser-result refinement accepted all **55 / 55** ProductRow
  results as `Passed`, including the checkpoint catalogue, transcript replay,
  and serial artifact matrix that had failed before the typed control-command
  deadline correction. A live process sample during measurement collection
  showed `jitml_metal_bridge_mlp_batch_gradient`, `jitml_commit`, and
  `MTLCommandBuffer waitUntilCompleted`, confirming real host Metal execution.
  The retained transcript is
  `.build/runtime/phase272-launchd-live.log`, and
  `.build/runtime/phase272-launchd.status` contains `0`.
- `./bootstrap/apple-silicon.sh doctor` passes on the current source. At the
  user-requested stop checkpoint no Phase `272` validation process or host daemon
  remained running.
- The active-goal continuation restored the supported host daemon in the
  `codex-phase272-daemon` tmux session. It acquired the existing real Metal
  bridge and runtime, connected all four Pulsar consumers, and reached `ready`.
  The required final-source
  `cabal run exe:jitml -- test all --apple-silicon` invocation then started in
  `codex-phase272-full`. Cabal's stanza log records `jitml-unit: PASS`; the
  orchestrator advanced to `jitml-integration` and was executing the isolated
  ProductScenario `mnist-lenet` row when the user requested a stop after about
  twelve minutes. The invocation was interrupted before it wrote
  `.build/runtime/phase272-full-final.status`, so neither that partial stanza nor
  the invocation is closing evidence. The next session must rerun the complete
  ten-stanza command from the beginning.
- The full-lane tmux session, host daemon, and monitor were stopped, then
  `./bootstrap/apple-silicon.sh down` deleted the retained Kind cluster. No Phase
  `272` validation process or daemon remained running at that stop checkpoint.
- Work then resumed by running `./bootstrap/apple-silicon.sh up`. Its first
  immutable-image build compiled the current source but failed closed when
  `jitml check-code` reported Fourmolu drift in four modified Haskell files. The
  project container applied only those formatter changes, after which
  `docker compose run --rm jitml jitml check-code` passed. The next bootstrap
  attempt correctly rejected the container-written Linux Cabal package
  registration during its host link. The generated 2.9 GiB tree is preserved at
  `.build/dist-newstyle-linux-phase272-format`; a clean Apple host build and the
  idempotent bootstrap retry are now the active prerequisite to restarting the
  full lane. These failed bootstrap attempts are diagnostic evidence, not lane
  evidence. Phase `273` remains blocked and no status transition occurred.
- The clean-host retry then passed `./bootstrap/apple-silicon.sh up` after
  **111** live rollout steps. `doctor` passes; `status` reports registry, MinIO,
  Pulsar, observability, coordinator, demo, and edge all `ready`; the edge
  `/readyz` returns `ready`; and immutable image
  `sha256:3471160fa15dfde5a2e1beb754120d06273c8ca5994555599579759f5cc59698`
  is loaded. The supported host daemon acquired `apple.metal-runtime=yes` and
  `apple.metal-bridge=yes`, connected all four consumers, and reached `ready`.
  The fresh
  `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal run exe:jitml -- test all --apple-silicon`
  invocation then ran from the beginning. Its transcript and terminal status
  paths are
  `.build/runtime/phase272-full-final-resume.log` and
  `.build/runtime/phase272-full-final-resume.status`; the status contains `1`.
  The fresh `jitml-unit` stanza passed. `jitml-integration` then failed
  **73 / 197** cases after the live canonical-dataset inventory returned `[]`
  instead of twelve objects. The live WorkflowMatrix reported
  `SENotFound "minioReadBytes: object missing"`, and the shared
  `mnist-shallow-mlp` ProductScenario acquisition consequently failed closed,
  cascading through its dependent product and aggregation assertions. The
  eight later stanzas were not run. This is diagnostic evidence, not closing
  evidence; it does not invalidate the separately completed final-source live
  e2e gate. At the user's stop request the host daemon was stopped and
  `./bootstrap/apple-silicon.sh down` deleted the Kind cluster. No Phase `272`
  validation process, daemon, or cluster remains running. Phase `273` remains
  blocked and no status transition occurred.
- The latest continuation rebuilt immutable image
  `sha256:550cab9db6cc1f835e1b938b9a57a3ffa7d32f44d822c2d62fdbb2441b6bf5e3`
  and completed all **111** Apple bootstrap steps. Doctor, component status,
  edge `/readyz`, and the embedded image `jitml check-code` gate passed. All
  twelve retained dataset artifacts again matched their repository SHA-256
  pins, all twelve uploads succeeded, and the focused live inventory/body gate
  passed **1 / 1** in 5.72 seconds. The supported host daemon reports
  `apple.metal-runtime=yes`, `apple.metal-bridge=yes`, four connected consumers,
  and `ready`. A new complete lane ran from the beginning in
  `codex-phase272-full2`; its intended transcript and terminal status paths were
  `.build/runtime/phase272-final-resume2-full.log` and
  `.build/runtime/phase272-final-resume2-full.status`. Cabal records
  `jitml-unit: PASS`; `jitml-integration` completed `mnist-shallow-mlp`,
  `mnist-deep-mlp`, `mnist-lenet`, `fashion-mnist-mlp`, and
  `fashion-mnist-resnet`, `cifar10-resnet20`, `cifar10-resnet56`, and
  `cifar100-wide-resnet`, clearing the prior stop boundary, then advanced to the
  CPU-active `cifar10-vit` ProductScenario. At the user's stop request the lane
  was intentionally interrupted before that row returned. Buffered output did
  not reach the transcript and no terminal status file was produced, so this
  invocation is not closing evidence. The test and daemon process trees were
  stopped, and `./bootstrap/apple-silicon.sh down` deleted the Kind cluster. No
  Phase `272` validation process, daemon, or cluster remains running. Phase
  `273` remains blocked and no status transition occurred.
- Work resumed from that documented boundary on immutable image
  `sha256:55975f2ec4db8eaf9dacee5b125ea1ed4dfb028c88a44b78a1ee232a1189ea6f`.
  `./bootstrap/apple-silicon.sh up` rebuilt the current source, passed the
  embedded `jitml check-code` gate, and completed all **111** live rollout
  steps. Doctor, all seven component statuses, and edge `/readyz` are green.
  All twelve retained artifacts again match the repository SHA-256 pins, and
  all twelve uploads returned their exact accepted byte counts and digests.
  The focused live inventory/body gate passed **1 / 1** in 5.56 seconds. The
  supported host daemon acquired `apple.metal-runtime=yes` and
  `apple.metal-bridge=yes`, connected all four consumers, and reached `ready`.
  A fresh complete lane ran from the beginning in
  `codex-phase272-full3`; its live transcript and terminal status paths are
  `.build/runtime/phase272-final-resume3-full.log` and
  `.build/runtime/phase272-final-resume3-full.status`. Cabal records
  `jitml-unit: PASS`; `jitml-integration` completed `mnist-shallow-mlp` and
  `mnist-deep-mlp`, `mnist-lenet`, `fashion-mnist-mlp`, and
  `fashion-mnist-resnet`, `cifar10-resnet20`, `cifar10-resnet56`, and
  `cifar100-wide-resnet`, then advanced to the CPU-active `cifar10-vit`
  ProductScenario. At the user's stop request the lane was intentionally
  interrupted before that row returned; the terminal status file contains `2`,
  so neither the partial integration stanza nor the invocation is closing
  evidence. The lane and daemon process trees are stopped,
  `./bootstrap/apple-silicon.sh down` deleted the Kind cluster, and no Phase
  `272` validation process, daemon, or cluster remains running. Phase `273`
  remains blocked and no status transition occurred. At the stop checkpoint,
  `docker compose run --rm jitml jitml docs check` and
  `docker compose run --rm jitml jitml check-code` both passed. The latter's
  1.9 GiB Linux build tree is preserved intact at
  `.build/dist-newstyle-linux-phase272-stop-20260905`; the default
  `dist-newstyle` path is absent so the next Apple session starts from a clean
  host build. These checkpoint gates do not replace the final post-lane gates
  required for Phase `272` closure.
- The next continuation rebuilt and reconciled the current source through
  `./bootstrap/apple-silicon.sh up`; the immutable image build's embedded
  `jitml check-code` passed and bootstrap completed all **111** rollout steps.
  Image `jitml:local` now resolves to
  `sha256:2893b9efdae0201d32cd49557dff03aeb9b02a396e1714af43b0e7feff710290`.
  All twelve retained upstream artifacts were rechecked against the repository
  SHA-256 pins, copied into the Compose-visible ignored runtime area, and staged
  through `jitml internal upload-dataset` with exact accepted byte counts and
  digests. The focused live inventory and body-verification case passed **1 /
  1** in 5.86 seconds. The supported host daemon acquired
  `apple.metal-runtime=yes` and `apple.metal-bridge=yes`, connected all four
  consumers, and reached `ready`. A fresh complete-lane invocation then ran
  from the beginning in `codex-phase272-full`; its transcript path is
  `.build/runtime/phase272-restored-full.log`. The fresh `jitml-unit` stanza
  passed; `jitml-integration` completed `mnist-shallow-mlp`,
  `mnist-deep-mlp`, `mnist-lenet`, `fashion-mnist-mlp`, and
  `fashion-mnist-resnet`, then advanced to the CPU-active
  `cifar10-resnet20` ProductScenario, proving the previously missing dataset
  boundary is restored. At the user's stop request the lane was intentionally
  interrupted; it produced no `.build/runtime/phase272-restored-full.status`
  terminal status and is not closing evidence. The host daemon was stopped and
  `./bootstrap/apple-silicon.sh down` deleted the Kind cluster. No Phase `272`
  validation process, daemon, or cluster remains running. Phase `273` remains
  blocked and no status transition occurred.
### 2026-09-05 Stop Checkpoint

- Work resumed after the preceding documented stop checkpoint. The Linux build tree left
  by the container quality gate was preserved intact at
  `.build/dist-newstyle-linux-phase272-stop-20260904`, and a clean host build
  compiled all 305 library modules and linked/signed the Mac `jitml` binary.
  `./bootstrap/apple-silicon.sh up` then built immutable image
  `sha256:2365ac55ef5fc8accee708acba8243d95d6d8248b6a52a11d92ce19ec51f66d7`
  and completed all **111** rollout steps. Doctor passed, all seven component
  statuses reported `ready`, and edge `/readyz` returned `200 ready`. All twelve
  retained dataset artifacts again
  match the repository SHA-256 pins; all twelve uploads returned their exact
  accepted byte counts and digests; and the focused live inventory/body gate
  passed **1 / 1** in 5.74 seconds. The supported host daemon acquired
  `apple.metal-runtime=yes` and `apple.metal-bridge=yes`, connected all four
  consumers, and reached `ready`. A fresh complete lane ran from the beginning
  in `codex-phase272-full4`; its transcript and terminal status
  paths are `.build/runtime/phase272-final-resume4-full.log` and
  `.build/runtime/phase272-final-resume4-full.status`. Cabal records
  `jitml-unit: PASS`;
  `jitml-integration` completed `mnist-shallow-mlp`, `mnist-deep-mlp`, and
  `mnist-lenet`, `fashion-mnist-mlp`, and `fashion-mnist-resnet`, then advanced
  through `cifar10-resnet20`, `cifar10-resnet56`, and `cifar100-wide-resnet`,
  clearing the prior stop boundary and advancing to the CPU-active
  `cifar10-vit` ProductScenario. At the user's stop request the lane was
  intentionally interrupted before that row returned; the terminal status file
  contains `2`, so neither the partial integration stanza nor the invocation is
  closing evidence. The lane and daemon process trees are stopped,
  `./bootstrap/apple-silicon.sh down` deleted the Kind cluster, and no Phase
  `272` validation process, daemon, or cluster remains running. Phase `273`
  remains blocked and no status transition occurred.

### 2026-09-05 Validation Resume

- Work resumed from the stop checkpoint with a clean default `dist-newstyle`.
  The Apple host build compiled all **305 / 305** library modules and
  linked/signed `.build/jitml`; all 18 authenticated third-party image pulls
  succeeded; and BuildKit completed the immutable application image in 45m26s.
  Image `jitml:local` resolves to
  `sha256:d4094b5ac0a70b2aa7bf3748e987e48516b237394521cbf7c0effdbfd550f27e`.
  Bootstrap completed all **111** rollout steps; doctor passed; registry,
  MinIO, Pulsar, observability, coordinator, demo, and edge all reported
  `ready`; and edge `/readyz` returned `200 ready`.
- All twelve retained dataset artifacts again matched their repository SHA-256
  pins, and all twelve uploads returned exact accepted byte counts and digests.
  The focused live inventory/body gate passed **1 / 1** in 5.72 seconds. The
  supported host daemon acquired `apple.metal-runtime=yes` and
  `apple.metal-bridge=yes`, connected all four consumers, and reached `ready`.
  A fresh complete lane passed `jitml-unit` and ran `jitml-integration` from the
  beginning in
  `codex-phase272-full5`; its transcript and terminal status paths are
  `.build/runtime/phase272-final-resume5-full.log` and
  `.build/runtime/phase272-final-resume5-full.status`. `jitml-integration`
  completed the first eight ProductScenario rows through
  `cifar100-wide-resnet`, then advanced to `cifar10-vit`. At the user's stop
  request, the lane was intentionally interrupted before that row returned; the
  terminal status file contains `2`, so neither the partial integration stanza
  nor the invocation is closing evidence. The lane and daemon process trees are
  stopped, `./bootstrap/apple-silicon.sh down` deleted the Kind cluster, and no
  Phase `272` validation process, daemon, or cluster remains running. Phase
  `273` remains blocked and no status transition occurred.
- At this stop checkpoint, `docker compose run --rm jitml jitml docs check` and
  `docker compose run --rm jitml jitml check-code` pass. The focused Product
  phase-status registry passes **6 / 6**, including the forward-only,
  concrete-validation, and single-accelerator guards, and the documented
  aggregation no-rerun scan reports `0` accelerator invocations for every
  identified CPU-only aggregation phase. The Apple host build tree is preserved
  at `.build/dist-newstyle-apple-phase272-stop-20260905-resume5`, the refreshed
  Linux container tree is preserved at
  `.build/dist-newstyle-linux-phase272-stop-20260905-finaldocs`, and the default
  `dist-newstyle` path is absent. These checkpoint gates do not replace the
  final post-lane gates required for Phase `272` closure.
- Work then resumed from the preserved Apple tree. The host binary rebuilt and
  re-signed, all 18 authenticated third-party image pulls succeeded, and
  BuildKit produced immutable image
  `sha256:e06058d13cdc208ab3f2625fad23319c8cc1b43dd203a5a76b97ad7da204c91e`
  in 45m18s. Bootstrap completed all **111** rollout steps; doctor, all seven
  component statuses, and edge `/readyz` passed. All twelve retained artifacts
  again matched the governed SHA-256 pins and uploaded with exact accepted byte
  counts and digests; the focused live inventory/body gate passed **1 / 1** in
  5.70 seconds. The supported host daemon acquired
  `apple.metal-runtime=yes` and `apple.metal-bridge=yes`, connected all four
  consumers, and reached `ready`. The fresh complete lane passed `jitml-unit`;
  `jitml-integration` completed all ten supervised ProductScenario rows,
  including the 1h49m `cifar10-vit` and 1h12m `tiny-imagenet-resnet50` rows,
  plus `PPO/cartpole`, `PPO/mountain-car`, and `PPO/acrobot`, then advanced to
  `PPO/lunar-lander`. At the user's stop request, the lane was intentionally
  interrupted before that row returned. Its transcript and terminal status
  paths are
  `.build/runtime/phase272-final-resume6-full.log` and
  `.build/runtime/phase272-final-resume6-full.status`; the wrapper recorded
  status `2`, so neither the partial integration stanza nor the invocation is
  closing evidence. The lane and daemon process trees are stopped,
  `./bootstrap/apple-silicon.sh down` deleted the Kind cluster, and no Phase
  `272` validation process, daemon, or cluster remains running. Phase `273`
  remains blocked and no status transition occurred. The resumable Apple host
  build tree is preserved at
  `.build/dist-newstyle-apple-phase272-stop-20260905-resume6`; the validated
  Linux container tree is restored at the default `dist-newstyle` path for the
  checkpoint documentation gate. At this final stop checkpoint,
  `docker compose run --rm jitml jitml docs check` passes and the focused
  Product phase-status registry passes **6 / 6**, including the forward-only,
  concrete-validation, and single-accelerator guards. These checkpoint checks
  do not replace the final post-lane closure gates.
- At the user's direction, the same final source resumed as lifecycle
  `resume7`. Bootstrap used immutable image
  `sha256:f148146e34e886508917b64b5294ff79af612c57f1a76cca4160a0156124bafe`,
  completed all **111** rollout steps, passed doctor, reported all seven
  components ready, and served `200 ready` at the edge. All twelve exact dataset
  artifacts were SHA-256 verified, uploaded, and accepted by the focused live
  inventory/body gate (**1 / 1** in 6.04 seconds). The host daemon acquired the
  Metal runtime and fixed bridge, connected four consumers, and reached
  readiness.
- The exact final-source command
  `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal run exe:jitml -- test all --apple-silicon`
  exited `0` and passed all ten stanzas, with `0` failed and `0` not-run, in
  116,396.918861 seconds: unit **906 / 906** (61.08s), integration **197 / 197**
  (94,531.73s), SL canonicals **36 / 36** (20,315.91s), RL canonicals **47 /
  47** (165.20s), hyperparameter **26 / 26** (3.58s), backends **25 / 25**
  (59.49s), daemon lifecycle **54 / 54** (8.73s), e2e **30 / 30** (0.70s),
  negative controls **3 / 3** (0.51s), and model convergence **111 / 111**
  (0.56s). The terminal transcript and status are retained at
  `.build/runtime/phase272-final-resume7-full.log` and
  `.build/runtime/phase272-final-resume7-full.status`.
- All **55 / 55** ProductScenario rows returned. The retained authenticated
  version-`3` journal identifies run
  `jitml-product-scenario-59e64ce033bfc105`; its committed-fragment comparator
  passed inside the complete integration stanza. Its preserved bytes at
  `.build/runtime/phase272-final-resume7-product-scenario-journal.json` verify
  against SHA-256
  `01291c3508c8129170005cf79a6bcb93aa7af16fc8d0ce0699377df6814ed5f8`.
  The final arm64 executable has SHA-256
  `3078abad38d656d83a26e220dd8792694dda0e7c55522acaa1cc6aa1ce22a26f`.
  The earlier explicit live-e2e final-source gate remains green at integration
  **197 / 197**, Playwright **77 / 77**, and Haskell e2e **30 / 30**, with
  terminal status `0` retained beside
  `.build/runtime/phase272-launchd-live.log`.
- The two standalone Apple gates then passed from the same source:
  `jitml-backends --apple-silicon` **25 / 25** in 66.20 seconds and non-live
  `jitml-e2e` **30 / 30** in 0.64 seconds. Their transcripts are retained at
  `.build/runtime/phase272-final-resume7-standalone-backends.log` and
  `.build/runtime/phase272-final-resume7-standalone-e2e.log`. The attestation's
  current metadata and evidence summary now describe this final-source run; its
  exact 55 row cells are unchanged because the live journal-derived comparator
  proved them byte-for-byte.
- The final container build produced `jitml:local` manifest
  `sha256:f304574e0875f739c6643e7596ef00e9591f1ffd422c84320fa6ef020d159553`
  after compiling all **305 / 305** Haskell modules, passing its embedded
  `jitml check-code`, and building the **611 / 611** PureScript modules plus the
  browser bundle. The explicit mounted-worktree `jitml docs check` and
  `jitml check-code` commands exited `0`; the focused product phase-status
  registry passed **6 / 6**; the mapped **20 / 20** aggregation validation
  blocks contained **0** accelerator invocations; and `git diff --check`
  passed. These terminal gates close Phase `272` on the final source.

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
- `../documents/engineering/daemon_architecture.md` — record the typed
  per-command Pulsar batch-deadline selection.
- `../documents/engineering/pulsar_ml_workflow.md` — distinguish the inference
  forward-pass fence from isolated control request/retry/drain bounds.

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
