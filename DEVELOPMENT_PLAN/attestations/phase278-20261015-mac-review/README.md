# Phase 278 Mac Review and Hardware Handoff — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Plan status](../../README.md#closure-status), [Phase 278](../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md#mac-hardware-boundary)
**Generated sections**: none

> **Purpose**: Retain the independent supervised-bar findings, host capability
> diagnostics, and resumption boundary without claiming phase validation.

Phase `278` remains Active. The open chain remains
`278 → 280 → 281 → 282 → 285 → 288 → 289`; no later phase began in this session.
The user's stopping condition is reached because necessary supervised-contract
repair requires subsequent fresh CUDA evidence that this Mac cannot produce.
The independent policy decision itself remains unresolved, separately from the
hardware limitation.

## Findings and evidence

- [Independent anchor review](supervised-anchor-review.md): published model
  results do not justify the exact compact graphs' acceptance floors. Tiny's
  source explicitly selects its current floor to clear an observed score.
  Dataset-only housing analysis proves that constant predictors pass its
  current RMSE bar. The proposed additional anti-trivial predicates do not
  substitute for independently justified convergence.
- [Dataset-only calculation](supervised-anchor-inputs.json) and
  [reproduction script](calculate-supervised-anchor-inputs.py): three complete
  upstream inputs match their production SHA-256 pins. An independent second
  invocation exits `0` and reproduces the JSON byte for byte. Partial downloads
  are excluded. No trained outputs determine the proposed controls.
- [Raw host diagnostics](host-probes.json): command arguments, UTC timestamps,
  stdout, stderr, and exit codes. Apple stage-0 doctor passes on the M1 Max;
  Docker reports ARM Linux with only `runc` runtimes. A Docker GPU capability
  request exits `125`. It is not a jitML CUDA test result.
- [Review checks](review-checks.json): reproduction and working-tree whitespace
  checks. These are diagnostic checks, not standing GateTranscripts.

The existing CPU/CUDA journals remain admissible under the unchanged contracts.
Correcting an affected row's bar changes that row's contract digest in every
lane; each replacement journal must come from a fresh complete 55-row run.
This host has the Apple hardware and Docker needed to prepare its Apple/CPU
execution, but no NVIDIA execution context. Neither CPU nor Metal execution
substitutes for the missing CUDA evidence.

Cold native and project-container builds were intentionally interrupted with
exit `130` once the boundary was established. The explicit container docs-check
attempt also began an automatic image build and was interrupted with exit `130`
before the validator started; the earlier unsupported `--no-build` option is
retained as a diagnostic error. No phase validation gate executed, and no cluster
or daemon was started. No production/test source, thresholds, journals,
aggregates, validation records, evidence pins, or status guards changed.

## Resumption

First resolve the convergence-policy and exact split-baseline decisions in the
review. Reconcile the required cross-lane repair with standards `M(b)`/`M(d)`
(one accelerator and one host per phase) through explicit per-lane ownership;
do not add a gate requiring both accelerators or waive retained evidence.
Freeze the resulting source and contracts before issuing replacement journals.

The cheapest Apple diagnostics need the native build and installed fixed bridge,
but no live cluster or dataset staging:

```bash
# Example: fresh local RL diagnostics on the Mac host.
./bootstrap/apple-silicon.sh build
.build/jitml internal install-metal-bridge
.build/jitml internal train-and-publish-product-rows --apple-silicon --row 'PPO/key-door-grid'
.build/jitml internal train-and-publish-product-rows --apple-silicon --row 'A2C/key-door-grid'
.build/jitml internal train-and-publish-product-rows --apple-silicon --row 'TRPO/cartpole'
```

These commands may reuse matching admitted RL checkpoints. This session created
none; any later diagnostic must establish fresh training rather than mistake
reuse for execution evidence. If TRPO still fails its bar, investigate the
host-Double versus Metal numerical boundary described in Phase `278`.

For the full Apple journal, bootstrap the live cluster, stage all twelve pinned
canonical dataset artifacts, start the host daemon, and use the focused route
that bypasses the currently red aggregate unit cases:

```bash
# Example: complete authenticated Apple journal after runtime preparation.
.build/jitml test jitml-integration --apple-silicon --test-options='-p "Phase 261 ProductRow contract-driven integration matrix"'
```

Retain `.build/runtime/product-lane-journals/apple-silicon.json` only after that
invocation completes successfully. Arrange actual NVIDIA execution for the
changed-contract CUDA journal and real CPU execution for its CPU counterpart.
Then admit and pin the journals, regenerate the aggregate, and pass Phase `278`'s
four Validation commands plus final full standing integration on the frozen
source. Only the evidence-derived status can close this phase and release the
next numerical phase.
