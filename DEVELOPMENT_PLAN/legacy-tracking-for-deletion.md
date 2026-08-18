# Legacy Tracking

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md),
[development_plan_standards.md](development_plan_standards.md),
[00-overview.md](00-overview.md), [system-components.md](system-components.md),
[phase-0-planning-documentation.md](README.md#legacy-to-new-phase-map),
[phase-1-haskell-cli-surface.md](README.md#legacy-to-new-phase-map),
[phase-2-bootstrap-reconciler-and-jit-cache.md](README.md#legacy-to-new-phase-map),
[phase-3-cluster-substrate-and-routing.md](README.md#legacy-to-new-phase-map),
[phase-4-stateful-platform-services.md](README.md#legacy-to-new-phase-map),
[phase-5-jitml-service-daemon.md](README.md#legacy-to-new-phase-map),
[phase-6-numerical-core.md](README.md#legacy-to-new-phase-map),
[phase-7-jit-codegen-and-substrates.md](README.md#legacy-to-new-phase-map),
[phase-8-supervised-and-rl-framework.md](README.md#legacy-to-new-phase-map),
[phase-9-rl-catalog-alphazero-and-tuning.md](README.md#legacy-to-new-phase-map),
[phase-10-checkpointing-and-inference.md](README.md#legacy-to-new-phase-map),
[phase-11-purescript-frontend-and-demo.md](README.md#legacy-to-new-phase-map),
[phase-12-test-stanzas-and-cross-cluster.md](README.md#legacy-to-new-phase-map),
[phase-13-no-caveat-model-runtime.md](README.md#legacy-to-new-phase-map),
[phase-14-interactive-demo-and-playwright-closure.md](README.md#legacy-to-new-phase-map),
[phase-15-linux-cuda-and-cluster-closure.md](README.md#legacy-to-new-phase-map),
[phase-16-apple-silicon-closure.md](README.md#legacy-to-new-phase-map),
[phase-17-cross-substrate-and-handoff.md](README.md#legacy-to-new-phase-map),
[phase-18-no-caveat-product-handoff.md](README.md#legacy-to-new-phase-map),
[phase-19-product-truth-gates.md](README.md#legacy-to-new-phase-map),
[phase-20-de-fossilization-and-scaffold-lint.md](README.md#legacy-to-new-phase-map),
[phase-21-type-state-dsl-and-inference-eligibility.md](README.md#legacy-to-new-phase-map),
[phase-22-canonical-matrix-and-dataset-integrity.md](README.md#legacy-to-new-phase-map),
[phase-23-general-differentiable-layer-engine.md](README.md#legacy-to-new-phase-map),
[phase-24-real-supervised-architectures.md](README.md#legacy-to-new-phase-map),
[phase-25-real-rl-algorithms-and-environments.md](README.md#legacy-to-new-phase-map),
[phase-26-alphazero-real-self-play.md](README.md#legacy-to-new-phase-map),
[phase-27-demo-all-model-rendering.md](README.md#legacy-to-new-phase-map),
[phase-28-per-model-integration-and-e2e.md](README.md#legacy-to-new-phase-map),
[phase-29-linux-cuda-product-lane.md](README.md#legacy-to-new-phase-map),
[phase-30-apple-silicon-product-lane.md](README.md#legacy-to-new-phase-map),
[phase-31-no-caveat-product-aggregation.md](README.md#legacy-to-new-phase-map),
[phase-32-external-truth-realness-harness.md](README.md#legacy-to-new-phase-map),
[phase-33-per-model-convergence-and-inference-tests.md](README.md#legacy-to-new-phase-map),
[phase-34-plan-truth-governance.md](README.md#legacy-to-new-phase-map),
[../documents/engineering/run_contract.md](../documents/engineering/run_contract.md),
[../README.md](../README.md)
**Generated sections**: none

> **Purpose**: Record every surviving compatibility helper, deprecated path,
> doctrine deviation, and tooling residue still slated for deletion.

> **Authoritative Reference**:
> [development_plan_standards.md → I. Explicit Cleanup and Removal Ledger](development_plan_standards.md#i-explicit-cleanup-and-removal-ledger)

## Ledger Status

This ledger tracks **doctrine deviations and compatibility helpers**, not
unmet primary Exit-Definition obligations. Primary unmet obligations live in
the owning sprint's `### Remaining Work` block per
[development_plan_standards.md → C. Honest Completion Tracking](development_plan_standards.md#c-honest-completion-tracking).

**2026-08-16 — documentation-truth pass.** Measuring the `linux-cuda` lane for
Sprint `265.1` surfaced governed-doc claims that measurement contradicts, and the
docs are reconciled to the measurements rather than the reverse. Phases `266` and
`267` reopened `Blocked` by Sprint `265.1` (their row-complete counts are
withdrawn and [Exit Definition](README.md#exit-definition) item `29` is unmet),
and Phase `78` reopened `Active` (`profileDeterminism` feeds the toolchain
fingerprint with a flag the compile line omits and algorithms the executed MLP
kernel does not use). The convergence-bar provenance is restated across
`documents/` and the root `README.md` as *externally anchored* —
`literatureTarget` external, `slack` project-calibrated — rather than a wholly
external constant, and item `26` now records that only its slack-positivity half
is enforced. Pending Removal now has **14** rows; Completed has **152**.

**2026-08-10 — single-worker local topology closed.** The three-worker Kind
default, independent manual-PV cardinality, replicated platform values and
higher-index PV manifests, and three-Engine Linux default have been removed.
Pending Removal now has **8** rows; Completed has **144**. Phases `42`, `53`,
and `69` are Done, and Phase `262` is Active.

**2026-08-02 — Phase `262` adversarial GC audit; primary remediation was
Active at that checkpoint.** The audit rejected the first shared-address intent/ready implementation
as closure evidence: a paused executor could race a writer that reused a
physical key, recovered intents lacked a fresh complete root proof, deletion of
the ready record could permit timestamp recreation, replay used the current
publication substrate, pagination did not bind the echoed request token/global
order, and delimiter text could not safely encode arbitrary object keys. This
finding remains historical non-closure evidence only. The replacement contract,
current implementation state, and the validation obligations that closed them
live exclusively in
[Phase 262 → Current Validation State](phase-262-contract-driven-live-execution-browser-and-playwright.md#current-validation-state)
and [Phase 262 → Closure Evidence](phase-262-contract-driven-live-execution-browser-and-playwright.md#closure-evidence).
No compatibility-ledger row changed, no superseded unsafe surface is recorded
as Completed, and the Pending Removal and Completed counts below are unchanged.

**2026-08-01 — Phase `261` integration-journal closure and stale-row
reconciliation.** The command-owned integration boundary passed **161 / 161**
tests and authenticated all **55 / 55** projection-ordered ProductRow records
before exact parent-side Store re-admission. Its legacy Sprint `28.4` row moved
to Completed. The already-closed Phase `229` / legacy Sprint `21.4` and Phase
`238` / legacy Sprint `23.2` rows were also reconciled to their dated closure
evidence without rewriting those historical snapshots. Pending Removal now has
**6** rows, Completed has **142**, and the open suffix begins with Active Phase
`262`.

**2026-07-26 — IR-single-owner + one-envelope redesign; ledger reopened for the
supervised checkpoint/runtime surfaces.** The redesign makes the typed
`LayerGraph` IR the single owner of supervised training/serving/serialization and
collapses the checkpoint wire to one self-describing envelope. The following
surfaces enter Pending Removal, each owned by the phase (in the post-2026-07-26
`+4` numbering) that removes it:

- **V1/V2/V3 checkpoint wire versions + the frozen-V1 byte-freeze golden**
  (`src/JitML/Checkpoint/Format.hs`; the SHA-256 `30db4da5…` / 134-byte golden in
  `test/unit/SupervisedCheckpointV2.hs`) — replaced by one self-describing
  envelope with a typed payload sum; checkpoints are regenerated deterministically,
  so no persisted bytes are reinterpreted and the byte-freeze is retired. Owner:
  Phase `235`.
- **The parallel `canonicalManifest` / `canonicalManifestV2` canonicalizers and
  the dead `RawV3*` DTOs / `encodeV3Checkpoint` / `decodeV3Checkpoint`**
  (`src/JitML/Checkpoint/Format.hs`) — collapsed to one canonicalizer; the V3
  encoder had no production caller. Owner: Phase `235`.
- **The version-gated admission path, the dormant `layerGraphFromCheckpoint` /
  `rebuildLayerGraph` helpers, and the V2 `SupervisedRuntime` load path**
  (`src/JitML/Checkpoint/Store.hs`) — superseded by one payload-classifying
  admission path. Owner: Phase `236`.
- **The V2 `SupervisedRuntime` served-operator ABI**
  (`src/JitML/SL/RuntimeArtifact.hs`, `src/JitML/Codegen/RuntimeOperationsCpu.hs`,
  the per-substrate device operators, and the nine-operation served set) — removed
  because the reloaded typed `LayerGraph` is executed directly. Owner: Phase `237`
  (read side) and Phase `239` (construction / ABI removal).
- **The decorative `archLayerGraph` beside the parallel executable
  `[LayerSpec]` / `[LayerState]` program** (`src/JitML/SL/Architecture.hs`,
  `src/JitML/Numerics/LayerGraph.hs`) — the IR becomes the single executor. This
  repoints the pre-existing decorative-graph residue row (previously owned by
  legacy Sprint `23.2`) to Phase `238`.

These are doctrine-deviation / duplicate-surface removals; the primary redesign
obligations live in the owning phases' `### Deliverables` / `### Remaining Work`.
Each row moves to Completed when its owning phase lands its `### Validation` gate.

**2026-07-18 — checkpoint persistence and executable-graph audit; ledger
reopened at Sprint `10.6`.** The frozen V1 checkpoint writer publishes
name-derived supervised tensors as `GenericModelFamily` and cannot preserve the
runtime family, transforms, dataset/plan identity, exact initial/final JMW1
hashes, or graph-ordered parameter interpretation required for strict reload.
The same audit found that the claimed layer-graph closure still has a parallel
executable `[LayerSpec]` / `[LayerState]` path and that external provenance is
not yet bound to the exact served artifact bytes. At the audit point those
three concrete residue surfaces entered Pending Removal under Sprints `10.6`,
`23.1`, and `32.2`. The corrected numerical suffix begins at Active Sprint
`10.6`; all later owners are Blocked until their direct predecessor closes.

**2026-07-18 — name-derived supervised writer replacement landed.** At that
boundary, supervised ProductRow publication required the refined
training-returned V2 artifact and non-optional completion, wrote one physical
`supervised.weights` JMW1 object, and derived its virtual slices from graph
order. Generic V1 writing was retained only as a guarded non-supervised
compatibility surface. At that audit
point the row remained Pending until Sprint `10.6` passed its full validation.

**2026-07-18 — selected-engine host structural callbacks removed.** The
then-current production `Local`, `CudaLocal`, and `MetalLocal` V2 executors no
longer installed `RuntimeOperations.host*` for transforms or graph operations.
Linux CPU and Linux CUDA used generated content-addressed native ABI kernels;
Apple Silicon used generated MSL through the fixed bridge with explicit fp32
transport. The replacement validated ABI/capabilities/symbols and failed
through typed errors. At that audit point the cleanup row remained Pending
until the canonical image, production parity/republishing, and full validation
gates passed.

**2026-07-19 — Sprint `10.6` exact-V2 cleanup closed.** Both landed replacement
rows moved to Completed after immutable descriptor `0147b37f…`, the non-no-op
**156-step** reconcile, **11 / 11** exact-V2 publications, focused pointer proof
**1 / 1**, unit **711 / 711**, SL **36 / 36**, integration **155 / 155**,
negative controls **3 / 3**, model convergence **111 / 111**, docs,
code-quality, whitespace, and Rule-M gates all passed.

**2026-07-19 — Sprint `10.12` persisted-admission implementation landed;
validation remained open at that point.** Store now owns opaque `AdmittedCheckpoint` /
`AdmittedCompletedCheckpoint`, exact `P1` → addressed manifest → `P2` selection
before independent blob binding, known-address admission, split opaque
candidate/completed writer results, and typed local `CheckpointWriteError`
object/pointer conflicts. Product Pipeline consumes Store rather than Store
importing Pipeline, and the raw generic snapshot writers and pure
`InferenceEligibleCheckpoint` / `CompletedCheckpoint` eligibility surface are
no longer public APIs. These are primary Sprint `10.12` obligations, so no
Pending Removal row is created or prematurely moved; the sprint remained Active
until its canonical validation and governed-document gates passed on 2026-07-20.

**2026-07-20 — Sprint `10.12` persisted-admission closure.** Unit passed
**719 / 719**, SL passed **36 / 36**, RL passed **40 / 40**, and hyperparameter
passed **26 / 26**; the focused Store/conflict regressions, docs, code-quality,
whitespace, and Rule-M gates also passed. Phase `10` and Sprint `10.12` are Done,
and the open suffix now begins with Active Sprint `19.4`.

**2026-07-12 — typed workflow-contract and test-truth audit; ledger
reopened.** The live PPO investigation retained all 200 expected episode
indices with finite rewards above the convergence bar, while the wrapper lost
the failing Tasty assertion and the live collector could still discard,
duplicate, or incompletely classify delivery evidence. The broader audit found
the same invalid-state pattern in subprocess outcomes, Pulsar settlement,
per-run planning, completion witnesses, report-card synthesis, negative
controls, model-convergence tests, and the product phase-status guard. The
primary work — the validated `RunPlan`, pure `RunContract` reducer, receipt-bound
interpreter, refined completion proofs, and journal-derived suite evidence —
was assigned to the owning sprints' `### Remaining Work`. The 2026-07-14
structural prefix through Sprint `10.12` closed that earlier assigned slice;
the later persisted-admission obligation under the same sprint remained Active
until its 2026-07-20 closure as primary work. The rows below name only concrete compatibility, duplicate,
doctrine-deviation, and stand-in surfaces, not open primary obligations.

**2026-07-14 — Sprint `10.12` structural completion/checkpoint cleanup slice
closed.** The
primitive supervised `TrainingRunConfig`, optional completed-checkpoint event,
and forgeable completion/verdict rows moved to `Completed`. Supervised workers
now consume one canonical resolved plan / `PlanId`, and versioned raw
completion/checkpoint DTOs must re-refine into hidden proof values. The ledger
remains open for the independently owned primitive traditional-RL adapter,
shared live-interpreter helpers, and later product-evidence/reporting residue.

**2026-07-14 — Sprint `12.16` implementation staged; validation remains
open.** The shared live interpreter and exact supervised/RL reducers have
replaced the former ad-hoc list/tuple collectors in the main Linux cluster live
scenarios. The test runner now records `Passed`, `Failed`, and `NotRun` rows and
derives aggregate status/count/duration from its invocation journal. Per the
ledger rule below, those two removal rows remain in Pending Removal until the
owning sprint's full validation passes; they must then move to `Completed` with
the observed evidence. The live-lifecycle row now implements its permitted
scoped-smoke disposition: WorkflowMatrix cells are typed executable-outcome
coverage, Apple forwarding matches the exact decoded command, and dedup remains
an explicitly labelled delivery/placement smoke. None can mint completion
evidence. That row remains in Pending Removal until the owning sprint's full
validation passes, then moves with the other Sprint `12.16` rows.

**2026-07-15 — retained-cluster reconciler regression closed.** Sprints `2.9`
and `3.7` restored the typed Kind existence branch, retained edge-port
authority, fail-closed recovery publication, exact live-image and topic
evidence, and steady-state exit-`3` no-op result. The exact retained-cluster
command first exited `0` after a 157-step mutating reconcile, retained all 34
authoritative topics beyond the broker inactivity window, and then exited `3`
on an identical second invocation without changing live identities. No
compatibility-helper row was added: this was primary phase work. The open
suffix then began with Active Sprint `12.16`; its three validation-pending rows
remained below until that sprint's canonical gate passed.

**2026-07-15 — Sprint `12.16` live-interpreter cleanup closed.** Every
evidence-bearing Linux live scenario now uses the bracketed interpreter, the
former RL list/tuple collectors and zero fallback are absent, and suite status
and duration derive from append-only invocation journals with explicit
Passed/Failed/NotRun outcomes. Immutable descriptor `6e0d5797…` passed unit
**544 / 544**, integration **155 / 155** including **18 / 18** Live, e2e
Playwright **72 / 72** plus Haskell **29 / 29**, and the full aggregate's **11
/ 11** reporter invocations with zero Failed or NotRun; docs and code quality
also passed. The three owned rows therefore moved to Completed. At that
historical checkpoint, Pending Removal contained **12** later-owned rows and
the open suffix began with Active Sprint `19.4`. The 2026-07-18 audit above
supersedes that current-status statement without rewriting its dated evidence.

**2026-07-01 — product-truth reopen; ledger reopened.** The product-truth audit
reopened no-caveat closure and the maintainer elected to implement the full
documented model surface for real rather than narrow it. The forward chain is
renumbered and extended to Phases `19`–`31` (new Phase `20` De-Fossilization &
Scaffold Lint, Phase `23` General Differentiable Layer Engine, and Phase `26`
AlphaZero Real Self-Play inserted). Sprint `20.1` has moved the legacy fake-ML
fossils out of the product path; the remaining accelerator-kernel scaffolds are
enqueued under Pending Removal below, each naming the sprint that deletes or
replaces it. The primary "implement it for real" obligations are not ledger rows
— they live in the owning sprints' `### Remaining Work` per rule C.

**2026-06-30 — real cluster/tuning/runtime-config audit; ledger reopened.** A
follow-up documentation/codebase audit found five doctrine deviations that can
make a workflow look real while bypassing live state or selected configuration.
Sprint `3.7` closed the two cluster rows: `cluster up` is now the live Kind/Helm
lifecycle command and publication/status readiness requires live evidence.
Sprint `5.17` closed mounted worker `RunConfig` decode failures. Sprint `9.16`
closed display-only tuning CLI overrides and daemon tuning workers ignoring
their `TuneRunConfig` axes. The ledger is empty again; Phase `18` Sprint `18.7`
has passed the final live `linux-cpu` aggregation, `docs check`, and
`check-code`.

**2026-06-29 — typed-failure and docs-governance audit; ledger reopened.** A
full documentation/codebase audit found doctrine deviations that are cleanup
rows under standards rule I/L: docs metadata enforcement was documented but not
implemented, residual CLI integer parsing silently coerces malformed user input,
several fail-closed runtime paths use `error` bottoms instead of typed failures,
and one local checkpoint key guard terminates instead of returning validation
data. Sprints `0.3`, `1.17`, `8.15`, `9.15`, and `10.11` have moved the docs
metadata, typed numeric CLI, RL device-failure, tuning resume decode-failure,
and checkpoint object-key rows to `Completed`. The Pending Removal ledger is
empty again. Phase `18` Sprint `18.6` re-aggregated the final handoff on
2026-06-30 with the full live `linux-cpu` report-card gate green.

**2026-06-29 — HA topology live revalidation closed; ledger was empty before the
typed-failure audit.** The remaining primary HA obligations closed without
adding ledger debt: Phase `16` revalidated the real Apple Silicon HA lane after
the host LLVM and Docker/Colima capacity blockers were removed; Phase `17`
aggregated the refreshed lane fragments on `linux-cpu`; and Phase `18`
re-closed the final product handoff. The compact-topology rows remain in
`Completed`.

**2026-06-28 — HA topology implementation rows closed; ledger empty.** The
compact single-node/right-sized implementation deviations found on 2026-06-27
have moved to `Completed`: HA Kind nodes/manual PVs, HA platform service values,
and scoped one-numerical-worker-per-node scheduling are now implemented. Phase
`15` is re-closed on the real Linux/NVIDIA HA live lane; Phase `16` has cleared
the Apple host-native `-fllvm` build prerequisite but is blocked by current
Docker/Colima capacity for the four-node HA Apple Kind topology; Phases `17` and
`18` remain blocked on that refreshed Apple fragment and downstream aggregation.

**2026-06-27 — HA topology audit; ledger reopened.** Documentation became the
source of truth for the targeted HA topology, but the worktree still carried
compact single-node/right-sized implementation paths in Kind materialization,
manual PVs, chart values, and service scheduling. Phases `3`, `4`, and `5`
reopened; Phases `15`, `16`, `17`, and `18` blocked until HA implementation and
live revalidation could close. Those temporary compact-topology rows closed on
2026-06-28.

**2026-06-26 — fixed-budget all-model trained-artifact audit; ledger
re-closed for the `linux-cpu` baseline.** The no-caveat model/product chain
reopened because representative convergence, seeded demo checkpoints,
workflow-category smoke, and fake local browser runtimes could not prove that
every documented model trains to a fixed terminating budget before inference.
The worktree then carried the fixed-budget `CompletedTraining` witness and the
then-current pure `InferenceEligibleCheckpoint` boundary, completed seeded demo manifests,
all-model checkpoint/UI evidence, and live Playwright/product validation for
the historical `linux-cpu` baseline. Phases `8`–`14` were marked Done for that
baseline; Phase `15` revalidated the real `linux-cuda` lane, Phase `16`
revalidated the real `apple-silicon` lane, Phase `17` aggregated the fragments,
and Phase `18` re-closed that historical handoff on 2026-06-26. The rows
introduced by this audit have moved to `Completed` below.

**2026-06-14 — no-caveat end-to-end product target (reopened; ledger
non-empty).** The product bar is now explicit: every supported SL/RL/AlphaZero
/ tuning workflow must run end to end with real training, checkpointing,
inference, browser interaction, RL animation, adversarial-game rendering,
interactive replay, and Playwright evidence. Phase `8` reopened and re-closed
for its local framework/runtime surface, and Phase `9` re-closed on 2026-06-15
after the linux-cuda validation pair passed. Phase `10` has re-closed after the
Linux CPU, Linux CUDA, and Apple Silicon integration lanes passed. Phase `11`
Sprint `11.9` has removed the current panel marker/default parsers and
generated typed browser payload decoders; it has also replaced the static
command acknowledgement with request-aware command publication when a live
cluster publication exists and added injected checkpoint-runtime REST routes
for the current MNIST/generic/CIFAR/checkpoint-compare/Connect 4 panels and
generated browser-visible workflow status. Live all-substrate REST proof, live
command publication proof plus lifecycle-operation expansion, expanded product
visualizations, and Playwright product proof remain open. Phases `11`–`12` are Active again, Phases `15`–`17`
are Blocked again, and Phases `13`, `14`, and `18` are added for the full runtime,
browser/Playwright, and final handoff closure. The primary
obligations live in those phases' `### Remaining Work` blocks; the rows below
track only temporary compatibility helpers, placeholder parsers/renderers, and
stub-like validation helpers that must be deleted or replaced before final
handoff.

**2026-06-13 — Apple Silicon host-resident workload placement (reopened and
re-closed; ledger empty).** The live Apple lifecycle exposed a stale placement
path where Apple Metal-backed Training/RL/Tune starts could become Kubernetes
Jobs in the Linux `jitml:local` image. Phase `5` Sprint `5.11` replaced that path
with workload placement planning and Apple host-command Pulsar topics; Phase
`12` Sprint `12.12` added failed-Job observation plus Apple no-workload-Job
assertions; Phase `16` Sprint `16.10` passed the full Apple lane; and Phase `17`
Sprint `17.7` moved the stale placement row to `Completed`.

**2026-06-12 — true-headless Apple Metal fixed-bridge doctrine (reopened and
re-closed; ledger empty).** The Apple Silicon Metal path redirected away from
the Tart-VM Swift build architecture toward the fixed host Metal bridge described
in
[../documents/engineering/apple_silicon_metal_headless_builds.md](../documents/engineering/apple_silicon_metal_headless_builds.md).
The core cache-miss path renders MSL plus launch metadata into
`<hash>.metal.json`, calls a fixed bridge that runtime-compiles the source with
`MTLDevice.makeLibrary(source:options:)`, and dispatches on the host GPU. Tart,
Virtualization HostKey state, unlocked login keychains, SwiftPM, generated Swift
packages, full Xcode, and the offline `metal` compiler are outside the core
training/inference JIT path. This reopened Phases `1`, `2`, `5`, `7`, and `16`;
all fixed-bridge cleanup rows moved to `Completed` after Sprints `7.11` and
`16.9` validated the replacement and the live apple-silicon lane headlessly.

**2026-06-10 — real-workflow refactor (reopened and re-closed; ledger
empty).** A realness audit found that every user-facing workload and the demo
used a synthetic, echo, or pure-Haskell-only stand-in instead of the substrate
JIT path (`MlpDevice` → compile → load → real `jitml_mlp_*` kernels) that
already exists and is backend-tested in the `jitml-backends` lane. The refactor
reopened Phases `8`–`12` (code) and `15`–`17` (live validation) and enqueued
Pending Removal rows — each a concrete synthetic value or dead symbol the
refactor deletes. The primary obligations (route each surface through
`MlpDevice`, build the non-Dense2D weighted bodies, add Conv2D/ResNet/ViT
codegen) were not ledger rows — they lived in the owning sprints' `### Remaining
Work` per rule C. As of 2026-06-12, the cleanup rows introduced by this refactor
have moved to `Completed`; the final handoff also re-closed after Phase `16`
Sprint `16.9` validated the fixed-bridge Apple lane.

**2026-06-10 — Apple Silicon Tart-VM build-JIT doctrine reversal (historical,
superseded; reopened and re-closed the same day).** Apple Silicon Swift/Metal
builds temporarily moved back into a `jitml`-managed Tart VM (build in the VM,
copy the dylib out to the host, execute on the host GPU), reversing the
2026-05-30 headless-host-build doctrine. This reopened Phases `1` / `2` / `5` /
`7` / `16` and enqueued six Pending Removal rows covering the then-legacy
headless-host build surface. **All six rows moved to `Completed` on
2026-06-10** once the replacement was verified working: the live apple-silicon
`jitml-backends` lane ran end-to-end through the Tart-VM-built path on Apple M1
(`jitml test jitml-backends --apple-silicon`, 17 / 17, in-VM `swift build` +
copy-out + host Metal execution, no skip sentinels). With those rows closed the
ledger was empty again and final handoff was complete as of 2026-06-10; that
doctrine was superseded by the 2026-06-12 fixed-bridge closure above. The prior
environment block
(the "Tart guest agent unreachable / `tart exec` control-socket GRPC error"
symptom) traced to a stale host `ctkd` (CryptoTokenKit) daemon deadlocking the
Virtualization.framework auxiliary-storage decryption — a host-ops condition, not
a code defect — cleared by restarting `ctkd` and running the build VM in the host
GUI launchd session. The 2026-05-30 `Completed` rows that recorded the original
Tart deletion stay as historical fact; the 2026-06-10 rows track the reversal.

On 2026-06-08 the cross-substrate numeric parity surface removal reopened
Phases `1` / `12` / `15` / `16` / `17` and enqueued six Pending Removal rows: the
cross-substrate per-layer-family tolerance band, the cross-substrate parity
cohort / drift / report-bundle module, the `jitml verify cross-backend` CLI
command, the report-card `cross_substrate_parity` field, the `CrossSubstrate`
weighted-drift and cross-substrate tolerance-band test groups, and the test
skip-antipattern guards. The reproducibility contract is now within-substrate
bit-for-bit reproducible with no cross-substrate equivalence asserted. On
2026-06-09 the full source/code removal landed and **all six rows moved to
`Completed`** (validated by a clean host + container build, `jitml check-code`,
`jitml docs check`, `jitml-unit` 193 / 193, the `apple-silicon` lane 4 / 4, and
the `linux-cpu` lane 10 / 10). The last of the six — the `linux-cuda` half of the
skip-guard removal — closed the same day when its live GPU re-run landed on the
NVIDIA GeForce RTX 5090 host (Sprint `15.16`): `docker compose run --rm jitml-cuda
cabal test -fcuda jitml-cross-backend --test-options '-p linux-cuda'` passed
19 / 19 with no skip-sentinels. **The ledger was empty and Exit Definition
item 18 (empty legacy ledger) was met and the final handoff complete as of
2026-06-09; both reopened on 2026-06-10 by the Tart-VM build-JIT doctrine
reversal noted above, then re-closed, and were superseded again by the
2026-06-12 fixed-bridge closure.** The 2026-06-05 Sprint `11.7`
doctrine-deviation row covering the SPA discoverability gap closed the
same day: the generated `Generated.AdminPortals` artifact, the
`Chrome.Header` / `PanelRegistry` / `Panels.Portals` modules, the
hash-router disposal path, and the live Playwright home/header/portal
matrix landed and validated against the Apple Silicon edge route. The
Sprint `1.12` doctrine-deviation
row that opened 2026-06-04 (missing CLI Dhall overrides on `train`,
`rl train`, `tune`) closed the same day after the
`JitML.Experiment.Overrides.applyOverrides` resolver, the new flag surface
on `CommandSpec`, and the regenerated CLI mirror landed; the row now lives
in the `Completed` table below. Sprint `1.11` downgraded the project to
the single GHC `9.12.4` baseline, removed the source-repository package pins
and local `third_party/haskell/lens-family-*` compatibility packages, and
validated a plain-Hackage solve. The former dependency source-pin/vendor helper
and the superseded reopened-phase development ledger now live in the
`Completed` table. Reopened Phase `11` Sprint `11.3` retired the deprecated
PureScript generic `runSpec` Node runner alias on 2026-06-04 by moving
`web/test/Main.purs` to the `spec-node` `runSpecAndExitProcess` API. Three rows
added 2026-05-29 record
doctrine deviations scheduled by the reopened Phases `2` / `4` / `5` after the
cluster OOM-storm incident: the `JITML_*` run-parameter env IPC and the duplicate
`JITML_SUBSTRATE` / `JITML_PULSAR_WS` reads (both retired by the typed Dhall
`RunConfig` + BootConfig mount in Phase 5 Sprint `5.7`), and the embedded `sh -c`
reconciler control-flow (retired by Phase 2 Sprint `2.9` + Phase 4 Sprint `4.8`).
The 2026-05-30 headless Apple Metal JIT removals — the `src/JitML/Tart/*` modules,
the `jitml internal vm` command group, the `container.tart` prerequisite node,
`LiveConfig.tartIdleTimeout`, and the offline `.metallib` codegen path — **closed
the same day** (Sprints `7.8` / `2.10` / `5.8`) and now live in the `Completed`
table.
Cleanup rows have closed and live in the `Completed` table:
Sprint `1.4` removed lint-time host `ghcup` style-tool bootstrap and moved the
style GHC/tool install plus `jitml check-code` gate into `jitml:local` image
construction and made lint/check-code execution container-only;
Sprint `3.5` removed the
`jitml-mirror` Helm placeholder and inserts the Docker build / explicit Kind
image-load phase directly in the live typed rollout; Sprint `4.3` folded the
standalone MinIO values fragment into `chart/values.yaml`; Sprint `7.7`
removed the static checked-in JIT source/build scaffold (JIT compiler inputs
are generated on demand by the Haskell binary; documented non-JIT runtime
adapters are not JIT compiler inputs) and removed the default runtime-source
placeholder fixture; Sprint `8.7` replaced the flat `RunPhase`
enum with the phase-indexed `RLRunLifecycle` GADT so all three jitML
lifecycles share doctrine-aligned shape; Sprint `8.8` retired the
deterministic atari-subset RAM-state stub with an explicit ROM-policy boundary,
and the later 2026-06-04 static-foreign-source correction removed the checked-in
ALE C++ shim and its Dockerfile/lint exception; the 2026-06-03 Phase `17` pass
removed the synthetic MCTS `priorFor`, replaced the target-stanza-only report
card with `jitml test all --live` measured fields, deleted the committed
numerical fixture tree under `test/golden/`, closed the Metal
kernel-family validation residue with a headless Apple weighted export, and
retired the demo placeholder shell/local stream/offline Playwright fallback
paths after live Playwright validation; and
the 2026-05-28 Pulumi-removal cleanup deleted the `infra/pulumi/`
ephemeral-Kind orchestrator (added in error), its `toolchain.pulumi`
prerequisite, and the Pulumi-only Kind name-override surface, leaving the
`jitml bootstrap` + `jitml cluster down` path as the ephemeral-cluster e2e
orchestration.

Two classes of entries populate this ledger over time:

1. **Doctrine-deviation residue.** Any worktree behavior that the implemented
   code does not yet honour against an in-scope doctrine section, scheduled
   through the owning sprint per standards rule L.
2. **Stand-in residue.** Any temporary scaffolding (placeholder kernel, smoke
   subprocess, in-memory MinIO stub, etc.) used to keep CI green while the
   real implementation lands. Each stand-in must name the sprint that retires
   it.

The doctrine envelope at [00-overview.md → Doctrine Scope](00-overview.md#doctrine-scope)
admits no out-of-scope-but-implemented sections at write time — when the
`Smart Constructors for Paired Resources` doctrine section becomes in-scope
(any future PV/PVC pair, DNS/cert pair, or analogous coupled resources), that
opening event itself enqueues a row here naming the originating sprint.

## Pending Removal

**Current state (2026-08-16): Pending Removal is open with 14 rows; Completed
has 152.** The 2026-08-16 documentation-truth pass added five rows: the
vestigial `onPolicyTuning` fan-out, the unused cuBLAS/cuDNN macros and link
flags on the RL MLP artifact, the `profileDeterminism` entries no compile line
passes, the dead `policySubstrate` field, and the broken `ExternalBars`
references. Each is residue or a doctrine deviation; the defects that reopened
Phases `266`, `267`, and `78` — the withdrawn row-complete CUDA counts, the
unmet every-row wall-clock obligation, and the fingerprint that attests another
kernel's determinism — are primary unmet obligations and stay in their owning
sprints' `### Remaining Work` per rule `C`, not here. The 2026-08-12 execution-architecture reopen added six rows for duplicated per-substrate surfaces: three operator vocabularies, three engine drivers, the scattered `Substrate` branches, the duplicate `Substrate` ADT, the hand-written fingerprint prose, and the repeated codegen wrapper text. Phase `72` closed the first of those six on 2026-08-13 — `LayerOp` is now the single vocabulary that the node kind, the catalog, and the Dhall surface all project from, and the dead `familyForLayer` bridge is deleted — so that row has moved to `Completed`. Those are deletion targets. The defects that reopened the phases — the fail-open catch-alls, the missing per-substrate IR execution, the declaration-derived device evidence, and the unimplemented Dhall layer DSL — are primary unmet obligations and stay in their owning sprints' `### Remaining Work` per rule `C`, not here. Phase `263` removed the provenance-free `CheckpointList` renderer
row that Phase `262`'s wire-form audit had added: proving the authenticated
frame's field set also proved that the parallel renderer emits frames neither
end of the wire accepts, and the renderer had no production caller. The
readiness-from-diagnostic-event row that the correlated-reply audit added
remains open and has been **transferred from Sprint `263.1` to Sprint `281.1`**
under standards rule `M(a)`: its replacement is a transport redesign, not a
deletion. `establishReplyCursor` admits only a `FromLatest`/`Owned`
subscription and mints its token from a broker admin CREATE, while
`JitML.Test.LiveWorkflow` must keep running over the non-broker
`LocalEventSource`, so publishing through the token requires an establishment
step the harness transport does not have — work outside Phase `263`'s
Implementation surface. The open chain begins with Planned Phase `263`; the
prior topology owners and Phase `262` are Done.

The Completed count is restated as **146** rather than 145 because the stated
144 on 2026-08-10 was one below the table's physical row count; the header is
reconciled to the table here rather than carried forward wrong.
Earlier counts are historical snapshots, not the
current ledger. Phase `261` moved its validated integration-journal replacement
to Completed and reconciled the already-closed Phase `229` and Phase `238`
rows. The Phase `262` GC protocol remediation remains primary Active work and
does not change these ledger counts. These are deletion targets, not substitutes for the primary
implementation obligations in the owning sprint documents.

| Item | Location | Reason for removal | Owning sprint | Replacement |
|------|----------|--------------------|---------------|-------------|
| Broken `ExternalBars` doc references | `src/JitML/Product/ExternalBars.hs` (module docstring links) | The relative links resolve one directory too high, and they cite `DEVELOPMENT_PLAN/phase-32-external-truth-realness-harness.md`, which the 2026-07-24 renumber renamed to `phase-277-external-bars-no-self-referential-gate-lint-and-exact-served.md`. | Sprint `277.1` | Correct relative depth and the current phase filename. |
| Unprobed `linux-cpu` benchmark-lane kernel entries | `src/JitML/Engines/Local.hs` (`runLinuxCpuKernel`, `runLinuxCpuWeightedKernel`), `src/JitML/Engines/TuningBenchmark.hs` (`linuxCpuBenchmarkCandidateRunner`, `linuxCpuWeightedBenchmarkCandidateRunner`) | Sprint `79.1` gave the `linux-cpu` family-kernel entries the availability probe its CUDA and Metal siblings already had, but the generic drivers and the two tuning-benchmark candidate runners still launch unprobed. These fail closed rather than fail open, so this is asymmetry rather than a defect. | Sprint `84.1` | `…WithProbe` variants for the benchmark candidate runners, matching `TuningBenchmark.hs`'s CUDA and Metal shape, so every lane probes before launching. |
| Hand-written per-family CUDA wrappers | `src/JitML/Codegen/Cuda.hs` (13 `extern "C"` wrapper copies across the unweighted and weighted family renderers) | Sprint `84.1` collapsed the oneDNN and Metal renderers to "signature once, body as data" but left CUDA hand-writing each wrapper, so one of three renderers still repeats its framing. | Sprint `264.1` | One `cudaWrapper` / `cudaWeightedWrapper` taking the launcher call as data, folded into the CUDA lowering that sprint already owns. |
| Prose/table ProductRow lane-fragment aggregation | Phase `29` / `30` attestation tables and `src/JitML/Test/Report.hs` attestation parsing/join helpers | The final join consumes separately authored report fragments rather than a typed lane journal whose rows are bound to `PlanId` and completed evidence. | Sprint `31.3` | Journal-derived product aggregation over committed typed lane journals; aggregation performs no accelerator rerun. |
| Metadata-only external-bar and provenance binding | `src/JitML/Product/ExternalBars.hs`, `src/JitML/Product/Completion.hs`, `src/JitML/Checkpoint/Format.hs` | Current checks compare declared/stored identities and reconstructed weight metadata, but do not bind the measured claim to the exact admitted artifact bytes subsequently served. A metadata-consistent substitute can therefore satisfy the provenance surface without proving the served object. | Sprint `32.2` | Bind provenance to the verified persisted manifest address and exact served blob bytes, then recompute the reported metric from that admitted artifact before comparing it with the frozen external bar. |
| Pure-gate-only negative-control stand-in and pass-on-pending sentinel | `src/JitML/Test/NegativeControls.hs` (`pendingProductionControls` and the explicit production-hook gap), `test/negative-controls/Main.hs` | Phase `276` is Done for retaining the hand-built pure gate-soundness records, while the test deliberately keeps the production-path controls pending; it does not prove the real workflow rejects a mutated artifact. | Phases `279`–`281` (legacy Sprints `32.4`–`32.6`) | Phase `279` adds request/event mutations, Phase `280` adds journal/reducer fixtures and properties, and Phase `281` adds lifecycle failures plus mandatory per-`ProductRow` registration through the validated workflow contract; a pending control is `NotRun`/failure, never a green production-coverage assertion. |
| Metadata-only model-convergence stand-in | `src/JitML/Test/ModelConvergence.hs`, `test/model-convergence/Main.hs` | The purported per-model runner validates declared bar/floor metadata (including a literal `1.0` family floor) and never trains from random initialization or runs inference, contrary to the Phase `33` contract. | Sprint `33.3` | One real resolved-plan scenario per `ProductRow`, yielding measured convergence and inference evidence from the executed artifact. |
| Post-test global measurement probes | `src/JitML/App.hs` (`collectLiveReportMeasurements`, `measureSlFinalLoss`, `measureRlFinalReward`, `measureAlphaZeroArenaWinRate`, `measureTuneBestObjective`, related probes) | Reporting launches new work or secondary probes after the tested invocation, so its values are not evidence from the tests it labels and failures collapse to undifferentiated `unavailable`. | Sprint `34.3` | Report only from invocation/scenario/lane journals, with `NotRequested`, reasoned `Unavailable`, and validated `Available` evidence. |
| Literal product phase-status registry used as “evidence-derived” closure | `src/JitML/Product/PhaseStatus.hs`, `src/JitML/Docs/Check.hs` (`allProductPhasesDone` closure-claim input) | The hand-maintained registry consumes neither suite results nor the deletion ledger, and a future literal edit could authorize an unsupported closure claim. | Sprint `34.3` | Keep any provisional literal synchronized while it exists, then derive closure from validated scenario journals / attestations, plan status, and an empty Pending Removal ledger. |
| Readiness derived from the diagnostic `ConsumerSessionConnected` event | `src/JitML/Test/LiveWorkflow.hs` (the observer that releases the publish gate), `test/integration/Main.hs` (the two live observers that publish from inside `ConsumerSessionConnected`) | A correlated request is published on the strength of a socket-open lifecycle event, which is not evidence that the broker created the reply cursor. Phase `262` retires this shape on the production inference client by requiring an opaque `ReplyCursor`; these harness call sites retain the superseded pattern and are latently subject to the same lost-reply race. | Sprint `281.1` (transferred from Sprint `263.1` on 2026-08-11) | Publish through the `ReplyCursor` token, so the harnesses exercise the same establishment contract as production. |

Rows move to `Completed` only after their replacement is implemented, every
old constructor/helper/call site is removed, and the owning sprint's validation
passes. Synthetic clients and deliberately structural fixtures remain valid
test harnesses when their types prevent them from satisfying production
evidence; they are not deletion rows merely because they are synthetic.


## Pending Removal Notes

Pending-removal rows normally resolve on the closure of the owning sprint
listed in the relevant phase document. Rows whose blocker is an external
upstream release still name the originating sprint, but resolve at the final
handoff toolchain refresh. Each row moves to `Completed` only when the
replacement is verified in the worktree.

On 2026-07-28 Sprint `239.1` deleted the superseded V2 `SupervisedRuntime`
projection and its nine-operation served ABI, now that the trained typed
`LayerGraph` is the sole supervised served representation (Phases `237`–`238`).
Removed surfaces:

- `src/JitML/SL/RuntimeArtifact.hs`: `executeLoadedRuntime` and the nine
  `RuntimeLayerOperation` executors, `RuntimeBackendExecutor` and every executor
  type alias, `RuntimeLayerOperation` / `RuntimeLayer` / `RuntimeMlpShape` /
  `RuntimeRepresentation` / `RuntimeLayerKind` / `RuntimeFamily` /
  `RuntimeVirtualSlice` / `LoadedRuntime`, and the `RawRuntimeFamily` /
  `RawRuntimeMlpShape` / `RawRuntimeLayer` wire DTOs plus their
  refinement/projection/accessor surfaces. `RawSupervisedRuntime` /
  `SupervisedRuntime` are slimmed to the task and the input/output transforms;
  serving is `executeSupervisedGraphRuntime` over the reconstructed graph with
  pure `applyRuntimeInputTransform` / `applyRuntimeOutputTransform`.
- Deleted whole modules: `src/JitML/Codegen/RuntimeOperations{Cpu,Cuda,Metal}.hs`,
  `src/JitML/Engines/RuntimeOperations{,Device,Cuda,Metal}.hs` (and their
  `jitml.cabal` entries); the engine `*RuntimeBackend` builders in
  `Local`/`CudaLocal`/`MetalLocal`.
- `src/JitML/SL/Architecture.hs`: `projectTrainedArchitectureRuntime` (and its
  `runtimeLayerContract` / `rawRuntimeFamily` / `exactArchitectureFamilyForModel`
  helpers); `canonicalClassificationRuntimeContract` slimmed to task + transforms.
- `src/JitML/SL/TrainingExecution.hs`: `exactRuntimeWeightBytes` replaced by the
  graph-parameter-count `exactGraphWeightBytes`.
- `src/JitML/Checkpoint/Store.hs`: `loadSupervisedRuntimeFromCheckpoint` reduced
  to graph-count admission; `runSupervisedGraphCheckpointInference` no longer
  takes a backend. `src/JitML/Checkpoint/Format.hs`: `validateAuthoritativeRuntime`
  / `validateClassificationRuntimeContract` / `validateClassificationInputTransform`
  / `validateCaliforniaRuntime` / `classificationProductionDimensions` removed;
  `encodeManifestCbor` selects the supervised body on `architectureLayerGraph`;
  admission anchors the weight blob to `layerGraphMetadataParameterCount` and the
  `FlatWeightLayout` to one graph-ordered spec.
- Deleted unit modules `test/unit/SupervisedRuntimeArtifact.hs` and
  `test/unit/RuntimeOperationsAccelerators.hs`; migrated
  `test/unit/SupervisedCheckpointV2.hs` fixtures onto the trained dense graph.

Validated on host: `cabal build lib:jitml --ghc-options='-fasm -Werror'` clean;
`jitml-unit` 743 / 743. The `jitml-backends` / `check-code` / `docs check`
container lanes and the `jitml-sl-canonicals` token-family coherence lane
(Phase `245`) run in their own substrate/container contexts.

On 2026-06-11 Sprint `11.8` closed the demo endpoint and browser-value
assertion rows on the CUDA machine. `Web.Server` now renders policy/value output
for `/api/inference`, MCTS output for `/api/connect4/move`, and a policy-network
top-k response for `/api/images`; the PureScript panels issue live fetches and
parse the replies; and the Playwright Docker image ran the live edge suite
**9 / 9** after the rebuilt `jitml:local` / `jitml-demo:local` images were
loaded into the `linux-cuda` Kind cluster and both deployments were
rollout-restarted. The same rebuilt source passed `docker compose build jitml`
(`check-code: ok` plus PureScript bundle) and
`docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda`
(**20 / 20**).

On 2026-06-10 the Phase 8 SL/RL substrate-routing session landed and verified
the code removal for four of the synthetic rows; they moved to `Completed`
below after the `jitml:local` container `--linux-cpu` boundary run confirmed the
device replacement executing the real oneDNN kernel. The 2026-06-11 source
cleanup removed the residual SL synthetic helpers and production trajectory LCG,
then revalidated the narrowed canonical stanzas (`check-code: ok`,
`jitml-sl-canonicals` 15 / 15 with the device-convergence case `OK (0.75s)`,
`jitml-rl-canonicals` 27 / 27 with the on-device PPO case `OK (0.75s)`):

- The `final_loss` synthetic print + `fromMaybe (SL.finalLoss …)` publish
  fallback, `attemptRealMnistTraining` / `attemptFetchTrainingDataset`, and the
  `runEval` echo stub are deleted from `src/JitML/App.hs`; `jitml train` now
  routes through `runDeviceMnistTraining` (mandatory live publication + staged
  dataset + `trainClassifierWithDevice`, fail-closed `TrainingPrerequisiteUnmet`)
  and `runEval` runs the substrate weighted device forward.
- The `"simulator"` scripted default trainer is removed from the `runRl`
  dispatch (default → `ppo`, unknown → `InvalidConfig`); `runTrainerEpisodes`
  routes every MLP-backed trainer through `rlDeviceForSubstrate` behind a
  fail-closed `probeMlpDevice` gate.

On 2026-06-11 the residual synthetic SL symbols and dead deterministic SL
pipeline were deleted as source, and the old trajectory-helper assertion moved
to the registered real-environment rollout surface.

On 2026-06-08 the cross-substrate numeric parity surface removal reopened
Phases `1` / `12` / `15` / `16` / `17` and enqueued six Pending Removal rows.
The reproducibility contract is clarified to within-substrate bit-for-bit
reproducible with no cross-substrate equivalence asserted, so the cross-substrate
numeric parity surface (tolerance band, parity module, `jitml verify
cross-backend`, the report-card `cross_substrate_parity` field, the weighted-drift
and tolerance-band test groups, and the test skip-antipattern guards) leaves the
contract. On 2026-06-09 the **entire source/code removal landed and was
validated**: five of the six rows moved to `Completed` (tolerance band, parity
module, `jitml verify cross-backend`, the report-card field, and the
weighted-drift / tolerance-band test groups), each verified by a clean host +
container build, `jitml check-code`, `jitml docs check`, `jitml-unit` 193 / 193,
the `apple-silicon` lane (4 / 4) and the `linux-cpu` lane (10 / 10). The **sixth
and final row** — the `linux-cuda` half of the skip-guard removal — closed the
same day (Sprint `15.16`): the live GPU re-run landed on the NVIDIA GeForce RTX
5090 host via the GPU-attached `jitml-cuda` compose service
(`docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend
--test-options '-p linux-cuda'` → 19 / 19, no skip-sentinels). **All six rows are
`Completed`, the ledger is empty, Exit Definition item 18 is met, and the final
handoff is complete.**

Current dependency validation: on 2026-06-04, the project uses GHC `9.12.4`,
`cabal.project` contains no `allow-newer` stanza and no `source-repository-package`
entries, and the local `third_party/haskell/lens-family-*` packages have been
removed. A container-local `cabal build all --dry-run --jobs=2` solves against
plain Hackage with `serialise-0.2.6.1`, `cborg-0.2.10.0`, `dhall-1.42.3`,
`lens-family-2.1.3`, and `lens-family-core-2.1.3`.

This ledger never holds primary unmet Exit-Definition obligations. Live
Kind/Helm rollout, real Pulsar/MinIO/Harbor clients, real per-substrate
kernel execution, real Playwright runs, and similar primary obligations live
in the owning sprint's `### Remaining Work` block per standards rule C —
not here. Rows here are exclusively for: an implemented behaviour that does
not yet honour an in-scope doctrine section (enqueued by the owning sprint
per standards rule L), or a temporary scaffold (placeholder kernel, smoke
subprocess, in-memory client stub) introduced to keep CI green while the
real implementation lands (with the retiring sprint named on the row).
Filesystem-backed `HasMinIO` interpreters and synthetic broker/client states
used as durable test harnesses are not pending-removal rows unless a sprint
explicitly schedules their deletion.

## Completed

| Item | Removed In | Notes |
|------|------------|-------|
| Vestigial `onPolicyTuning` substrate fan-out | `src/JitML/RL/TrainerExecution.hs` | Phase `265` / Sprint `265.1` (2026-08-17) | The three arms all returned `(10, 5.0e-4)`, so the fan-out was retained shape with no retained behaviour — and it invited exactly the per-substrate retune its own comment warned against (a more aggressive CUDA pair previously left PPO/MaskablePPO cartpole stuck at ~210). It is now one substrate-independent constant, so diverging an RL hyperparameter per lane means deliberately replacing the constant. There is also no longer a numerical motive to: the two Linux lanes' MLP kernels agree bit-for-bit. |
| Unused cuBLAS/cuDNN macros and link flags on the RL MLP artifact | `src/JitML/Engines/Engine.hs`, `src/JitML/Codegen/RuntimeSource.hs`, `src/JitML/Numerics/{MlpOneDnn,MlpCuda,MlpMetal,LayerGraphDevice}.hs`, `src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs` | Phase `265` / Sprint `265.1` (2026-08-17) | The libraries an artifact links now follow the __program__ rather than the substrate. A typed `KernelProgram` (`FamilyProgram` / `MlpProgram` / `LayerTrainingProgram`) is carried on `RuntimeSource`, and `compileSubprocess` reads it off the rendered source rather than taking it as a second argument, so a compile command cannot name libraries for a different program than the one it compiles. `programCudaLibraries` is total over the three programs: the family and layer-training programs keep cuBLAS and cuDNN, which they really call, and the MLP program — hand-written elementwise CUDA including only `cuda_runtime.h` — gets neither, so its `.so` stops carrying two `DT_NEEDED` entries it never enters and its cache key stops naming two libraries it does not use. The three fingerprints each pass their own program, so the cache key and the compile line stay one source of truth. Guarded by a standing unit case; `jitml test jitml-backends --linux-cuda` passes **27 / 27** with the MLP artifact compiling and executing on the RTX 5090 without either library. |
| Dead `policySubstrate` field | `src/JitML/RL/Policy.hs` | Phase `265` / Sprint `265.1` (2026-08-17) | Set by `defaultPolicy` and read nowhere in `src/` or `test/`; it implied a per-substrate policy distinction the codebase does not have. Deleted along with the now-unused `Substrate` import, and `defaultPolicy` lost its substrate parameter — where a policy executes is a property of the run, not of the policy. |
| `profileDeterminism` entries that no compile line passes | `src/JitML/Substrate.hs`, `src/JitML/Engines/Engine.hs`, `src/JitML/Engines/Fingerprint.hs`, `src/JitML/Codegen/{Cuda,MlpCuda,CudaLayerTraining}.hs` | Phase `78` / Sprint `78.1` (2026-08-17) | The four `linux-cuda` entries are gone and the facts are read off the surfaces that establish them. `Engine.engineCompileFlagSpecs` tags each compile argument with its role, so `engineCompileFlags` (what nvcc is given) and the new `compileLineDeterminism` (what the cache key advertises) are two projections of one list; the `fast-math=absent` entry is derived from the absence of any fast-math argument in that list, so it flips — invalidating every artifact on the lane — the moment one is added, and it can no longer name `--use_fast_math=false`, which no compile line passes. `cudnn-explicit-algorithm-id` and `warp-shuffle-deterministic` were substrate-wide claims about two specific kernels: the trainer MLP artifact keyed on both while reducing per thread with neither. Kernel bodies already reach the key through the rendered-source payload, so those claims are not relocated; the one library-level choice that must also be keyed is now `CudaLayerTraining.cudaLayerTrainingDeterminismChoices`, named once, spliced into the generated source, and read from there by `layerTrainingKnobs`. The two generated-source `// determinism:` comments that restated `--use_fast_math=false` state only what their own bodies establish. Validation on `linux-cpu`: `jitml-unit`, `jitml docs check`, and `jitml check-code`; the measured counts are recorded in [phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md](phase-78-kernelspec-cache-key-inputs-ffi-loader-surface.md). |
| Repeated codegen wrapper text | `src/JitML/Codegen/{Cuda,OneDnn,Metal}.hs` | Phase `84` / Sprint `84.1` (2026-08-14) | Each renderer now emits its kernel signature once and takes the family-specific part as data. `OneDnn.familyImpl` collapsed nine copies of the same `extern "C"` wrapper into one, with `unweightedFamilyNote` / `unweightedFamilyCall` / `unweightedPreamble` supplying the differences. `Metal.unweightedBody` collapsed nine copies of the same six-line signature block, with `unweightedGridParameter` / `unweightedPrologue` / `unweightedFamilyCompute` supplying the differences — and that decomposition is what made the reduction's bounds behaviour expressible, since a reduction must *not* take the shared `id >= n` early return. Every `KernelFamily` wildcard in all three renderers is gone: `weightedFamilyImpl`, `cudnnDeterministicAlgorithm`, and `kernelOutputCountFunction` on CUDA; `weightedFamilyCompute`, `metalOutputCountFor`, and `metalOutputCountKind` on Metal; `weightedFamilyCall` and `kernelOutputCountFunction` on oneDNN (Sprint `80.1`). A tenth family is now a build failure in every renderer. |
| Scattered `Substrate` branches superseded by one profile record | `src/JitML/Substrate.hs`, `src/JitML/Engines/Engine.hs`, `src/JitML/Engines/Loader.hs`, `src/JitML/Service/{ConfigMap,Workload}.hs`, `src/JitML/Plan/Command.hs`, `src/JitML/Cluster/Publication.hs`, `src/JitML/Bootstrap.hs` | Phase `79` / Sprint `79.1` (2026-08-14) | `SubstrateProfile` and a total `profileFor` — one equation per constructor, no wildcard — now own every substrate-varying fact: backend, artifact extension, determinism knobs, `KernelLaunch`, `ArtifactFill`, cluster-compute, edge port, and runtime class. `engineForSubstrate` and `deterministicFlags` are projections of it, so the engine record cannot disagree with the profile. `substrateHasClusterCompute` had existed in five shapes across four modules and is now one definition; `substrateRuntimeClass`'s `_ -> Nothing` wildcard is gone, so a fourth substrate is a build failure rather than a silent "no runtime class". `Loader.ensureKernelArtifact`'s `_ -> do` compile arm became a total two-arm `case` on `ArtifactFill`. |
| Three near-identical per-substrate engine drivers | `src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs` | Phase `79` / Sprint `79.1` (2026-08-14) | The shared halves are now single-source: `JitML.Engines.LoadableKernel` owns the four FFI type aliases, the four `foreign import ccall "dynamic"` declarations, and both `loadAndRun` / `loadAndRunWeighted` helpers, which were byte-identical between the CPU and CUDA modules apart from one comment word. `renderBool` went from six identical copies to one in `JitML.Sub.Render` (the two copies with a different codomain, in `Web/Server.hs` and `Numerics/LayerDhall.hs`, are deliberately untouched). `Local.runSupervisedGraphDeviceInference`, a line-for-line re-implementation of `Checkpoint.Store.runSupervisedGraphCheckpointInference`, is deleted so all three engines share the one supervised serving path — which also un-drifts `documents/engineering/jit_codegen_architecture.md`. `MetalLocal.familyNameText`, a byte-identical copy of `KernelFamily.familyName`, is deleted. The three modules fell from 1,162 lines to 938, with the removed code replaced by 106 shared lines rather than a fourth copy. |
| Hand-written toolchain-fingerprint prose | `src/JitML/Engines/{Local,CudaLocal,MetalLocal}.hs`, `src/JitML/Numerics/{MlpOneDnn,MlpCuda,MlpMetal}.hs`, `src/JitML/Numerics/LayerGraphOneDnn.hs`, `src/JitML/App.hs` | Phase `78` / Sprint `78.1` (2026-08-14) | All eight hand-written fingerprints are deleted and replaced by `JitML.Engines.Fingerprint`, which renders one `ToolchainFacts` record per artifact. Every field is read off the surface it describes: the compiler, flags, and link line come from the new hash-free `Engine.engineCompiler` / `engineCompileFlags` / `engineLinkFlags` that `compileSubprocess` itself passes; determinism from `deterministicFlags`; the ABI from a typed `AbiKind` that carries `metalBridgeAbiVersion`, so the token can no longer be hardcoded at one site and interpolated at another; the numeric knobs from `oneDnnFixedReductionBlock` and `threadgroupSizeFor`; and the emitter set from `kernelFamilies` / `allLayerKinds`. `buildToolchainFingerprint` is total over `Substrate` with no shared literal, and equals the per-substrate family fingerprint, closing the split where `jitml build` installed at one cache key while the benchmark candidate runners measured at another. Two ABI misstatements were corrected in the process: the Apple MLP fingerprint claimed `abi=cdecl-host-buffers` plus five C prototypes for an artifact that exports no C symbols (it now names its ten MSL kernels), and the Apple family fingerprint named `jitml_kernel_family_name` / `jitml_kernel_output_count`, which are `.metal.json` metadata fields rather than kernels. A standing unit case asserts every named entry point appears in the source its lane renders. Validation on `linux-cpu`: `jitml-unit` **864 / 864** including the nine-case "Derived toolchain fingerprints (Phase 78)" group, `jitml docs check`, and `jitml check-code`. |
| Duplicate `Substrate` ADT and its parallel renderer | `src/JitML/Cache/Key.hs`, bridged by `src/JitML/Engines/TuningCache.hs` | Phase `78` / Sprint `78.1` (2026-08-14) | The second structurally identical `Substrate` is deleted. `JitML.Substrate` now owns the type, its `Serialise` instance, and its JSON codec; `JitML.Cache.Key` re-exports it and defines `substrateText = renderSubstrate`, so one closed set has one renderer. `TuningCache.cacheSubstrateFor`, the bridge between the two types, is deleted. The on-disk rendering is unchanged, so the cache-key golden and every persisted manifest still decode. |
| Three parallel operator vocabularies and the dead catalog bridge | Phase `72` / Sprint `72.1` (2026-08-13) | `LayerOp` is now the single vocabulary. `LayerNode` no longer stores a kind beside its operator — `layerNodeKind` is the `opKind` projection — so the oneDNN switch key is the executed operator by construction and a node cannot claim an operator it did not run. `Catalog.Layer` was reduced to the eleven executed operators, `layerCatalog` is `[minBound .. maxBound]` over that type, and `dhall/numerics/Layer.dhall` plus the generated `numerics.layers` table are projections of it. `opLayer`, `layerOpTemplate`, and `layerKindWitnessOp` are total in both directions under `-Werror=incomplete-patterns` (Sprint `7.1`). The dead `familyForLayer` bridge is deleted from `src/JitML/Codegen/KernelFamily.hs`. Validation on `linux-cpu`: `jitml-unit` **846 / 846** including the seven-case "One operator vocabulary (Phase 72)" group, `jitml-backends` and `jitml-sl-canonicals` green, `jitml docs check`, and `jitml check-code`. |
| Provenance-free `CheckpointList` renderers | Phase `263` (2026-08-11, legacy Sprint `28.6`) | `renderCheckpointListResult`, `renderCheckpointListResultWithSelectors`, and `checkpointSelectorState` are deleted from `src/JitML/Service/Workload.hs` along with their exports. They had no production caller: `renderAdmittedProductBrowserCatalogue` is the sole producer of the frame the Engine publishes, and the retired renderer omitted the `run-id`, `substrate`, `catalogue-sha256`, and `source-journal-sha256` fields that the topology validator requires and the generated browser contract parses. Their two fabricated-frame fixtures are retired with them; the authenticated frame's field set stays pinned by the Phase `262` validator/contract unit case and by the live browse cases, because `AdmittedProductBrowserCatalogue` is abstract and cannot be forged offline. |
| Hardcoded three-Engine Linux default and explicit multi-worker acceptance shape | Phase `69` / Sprint `5.16` (2026-08-10) | The loaded `ClusterResources.jitmlService` budget now drives root Deployment and local Helm-value rendering; topology validation rejects a positive Engine count above `workerCount`. The checked-in local default is one Engine, Apple retains zero clustered Engines plus one host Engine, and required hostname anti-affinity preserves at most one Engine per node. Validation: canonical image build; cardinality **1 / 1**; daemon lifecycle **54 / 54**; docs, chart lint, and code quality passed. |
| Replicated local platform values, higher-index PV manifests, quorum settings, and HA assertions | Phase `53` / Sprint `4.10` (2026-08-10) | Replaced by standalone MinIO; one ZooKeeper, BookKeeper, Broker, and Proxy with single-node ledger quorums; six replica-zero stateful PVs; one Postgres/pgBouncer/pgBackRest; and one instance of every local platform/application role. Validation: local topology **7 / 7**, clean destructive live rollout **135 / 135** steps, docs, chart lint, and code quality passed. |
| Three-worker Kind default and hard-coded manual-PV renderer cardinality | Phase `42` / Sprint `3.6` (2026-08-10) | The typed profile, Haskell fallback, and all three checked-in Kind fixtures now materialize one control-plane plus one worker while retaining positive expanded renderability. Manual PVs derive MinIO, Pulsar, and Postgres cardinality from the supplied `ClusterResources`; a focused one-instance profile proves the exact six replica-zero PVs. Phase `53` retains ownership of reducing actual platform counts and deleting higher-index manifests. |
| Per-row artifact-reader and declared-test-id integration cells | Phase `261` (2026-08-01, legacy Sprint `28.4`) | Replaced by the command-owned, projection-ordered ProductScenario boundary: the integration child consumes a one-use `0600` HMAC capability before Tasty, executes every projected row, emits one authenticated version-`3` aggregate, and the parent authenticates it and re-admits every exact Store address. Validation on `linux-cpu`: integration **161 / 161**, including the Phase `261` subtree **60 / 60** and all **55 / 55** ordered ProductRow records; unit **772 / 772**; `jitml docs check` and `jitml check-code` both passed. No artifact-only read, declared id, or green child exit can mint the report. |
| Decorative `archLayerGraph` beside a parallel executable layer/state path | Phase `238` (2026-07-28, formerly Sprint `23.2`) | The parallel `[LayerSpec]` / `[LayerState]` executable and its projection are deleted. Supervised training, serving, graph-ordered parameter identity, and serialization now share the typed `LayerGraph` IR; the training path uses the batched oneDNN loop over `graphParameterVector`. Validation: `jitml-backends --linux-cpu` **27 / 27**, `jitml-unit --linux-cpu` **777 / 777**, and `jitml check-code` passed. |
| Phase-indexed product rows carrying every phase's optional evidence | Phase `229` (2026-07-22, formerly Sprint `21.4`) | `ProductRow` no longer carries the four optional evidence handles, and hidden-constructor state-specific `ModelRef` values make contradictory evidence payloads unconstructible. Validation: `jitml-unit` **739 / 739**, `jitml-negative-controls` **3 / 3**, `jitml-model-convergence` **111 / 111**, `jitml-integration` **156 / 156**, `jitml docs check`, and `jitml check-code` all passed. |
| Overloaded and silently repaired RL budget arguments — measured-counter half | Phase `252` (2026-07-31, formerly Sprint `25.6`) | Every production trainer returns opaque positive measured environment-transition and optimizer-update counters in the units owned by its executed algorithm result; `TrainerExecution` consumes those counters directly, and caller reconstruction of alleged updates is gone. Shared Phase `252` validation, all green on `linux-cpu`: `jitml-rl-canonicals` **47 / 47**, `jitml-unit` **757 / 757**, `jitml-model-convergence` **111 / 111**, `cabal build test:jitml-integration --jobs=1`, `jitml docs check`, and `jitml check-code`. |
| Partially trained `TrainerRun` represented by independent optional weights and evidence | Phase `252` (2026-07-31, formerly Sprint `25.6`) | The contradictory optional shape is replaced by `EvaluationOnly | Trained TrainedArtifact`; the trained constructor carries weights, measured counters, the ordered learning curve, the exact keyed final-evaluation set, and `TrainingEvidence` together. The same six-command Phase `252` closure gate passed: RL canonicals **47 / 47**, unit **757 / 757**, model convergence **111 / 111**, integration target build/link, docs check, and check-code. |
| Primitive traditional-RL `RunConfig` execution adapter | Phase `251` (2026-07-31, formerly Sprint `25.5`) | `RlRunConfig` now carries only one canonical resolved-plan transport (`rlcResolvedPlan`) plus its derived `rlcPlanId` — alongside `rlcExperimentHash`, `rlcAtariRomPath`, and `rlcPulsarWsUrl` — matching the supervised/tune/AlphaZero mounts; the primitive per-field trainer transport and the worker-side execution-semantics reconstruction (and the `Service/Workload.hs` + `App.hs` adapters) are gone. A pure `compileRlPlan` refines a validated `TrainingPlan` plus a separate `EvaluationPlan` into a `CompiledRlPlan` (the `ceil(total transitions / (rollout ticks per env * vector env count))` arithmetic lives only there, and evaluation episode count can no longer determine training dimensions), and every production trainer consumes it through `runTrainerEpisodesForPlan` — the positional `runTrainerEpisodes` adapter and the `App.hs` `max 1` budget clamps are deleted. The serialized plan + `PlanId` are the worker's only semantic execution input. All 39 canonical RL budget targets are byte-identical. The remaining measured-counter obligation subsequently closed in Phase `252`. Validation on `linux-cpu`, all green 2026-07-31: `jitml test jitml-rl-canonicals`, `jitml test jitml-unit` (incl. the Phase 221 registry guard), `jitml test jitml-daemon-lifecycle` (compiled-plan admission fixture), and `jitml check-code`. |
| Duplicated RL algorithm/trainer selector axes | Phase `250` (2026-07-30, formerly Sprint `25.4`) | An abstract typed `RLCohort` (in `RL/Framework.hs` + `RL/Algorithms/Registry.hs`; only the `mkCohort` smart constructor mints one, so an incompatible discrete/continuous/goal-conditioned pair is unconstructable) is action-domain-indexed. The redundant `rlcTrainerKind` field is removed from `RlRunConfig` and from the `dhall/run/Schema.dhall` `RunConfig` schema; dispatch flows through the cohort, and the former forward/reverse mappings (`rlTrainerForAlgorithm`, `trainerKindForAlgorithm`, `algorithmNameForTrainer`, `rlTrainerEnvironmentCompatibilityError`) delegate to it. The exact lowercase trainer strings are rendered byte-identically from the cohort, so content-addressed checkpoint identity (`rlEvidenceReadHash`, `rl-<trainerKind>-weights` tensor names) is unchanged; `lunar-lander`'s per-algorithm dual domain (discrete for on-policy/ARS, continuous for DDPG-family) is preserved. Validation: `jitml test jitml-rl-canonicals --linux-cpu` (incl. the cohort reject/accept + golden cases), `jitml test jitml-unit --linux-cpu` (incl. the reflected Dhall schema parity), `jitml check-code`, and `jitml docs check` all green. |
| Dormant checkpoint layer-graph reconstruction + version-gated admission | Sprint `236.1` (2026-07-27) | The store's per-version admission allow-list (`decodeAddressedForAdmission`) and the `validateCompletedAdmissionScope` V1/V2 split collapsed to a single decode-then-classify on the payload variant (weight-only vs supervised-graph); a supervised-graph checkpoint carrying a companion pointer was thereafter rejected on that single path. The dormant `layerGraphFromCheckpoint` / `rebuildLayerGraph` reconstruction chain (with its `layerKind`/`Mode`/`Activation`/`ParametersFromMetadata` helpers), the `JitML.Engines.LayerGraphCheckpoint` module, and the `Local.hs` graph-rebuild serving fallback were deleted — they never fired for real product rows, whose `architectureLayerGraph` was `Nothing`. The then-live V2 `SupervisedRuntime` read/serving path (`loadSupervisedRuntimeFromCheckpoint`, used by the Local/CUDA/Metal engines) was **not** removed in Phase `236`: that removal transferred to Phase `237` (supervised serving on the IR), where serving was rewired off it (rule M(a)). Validation: `jitml test jitml-unit --linux-cpu` PASS (incl. the supervised-graph companion-rejection test), `jitml check-code` ok, `jitml docs check` ok. |
| Multi-version checkpoint wire, byte-freeze golden, and parallel canonicalizer | Sprint `235.1` (2026-07-27) | The three accreted checkpoint wire versions collapsed into one self-describing `RawCheckpointEnvelope` carrying the typed `RawCheckpointBody` payload sum (weight-only vs supervised-graph). The byte-frozen V1 golden fixture (134 bytes, SHA-256 `30db4da5…`) and its `LazyByteString.length`/`manifestContentSha` golden test are gone; the dead V3 `LayerGraph` encoder (`RawCheckpointBodyV3`, `RawV3Graph`, `RawV3LayerNode`, `encodeV3Checkpoint`, `decodeV3Checkpoint`, `layerGraphToRawV3`, `rawV3ToLayerGraph`, `checkpointWireVersionV3`) is deleted; the retained pre-Sprint-`10.12` `LegacyCheckpointManifest` decoder cascade (`decodeAddressedLegacy`/`refineLegacy*`) and the separate `RawCheckpointEnvelopeV2` outer are removed; and `canonicalManifest` / `canonicalManifestV2` merged into one canonicalizer. `encodeManifestCbor` is a single arm and `decodeAddressedManifestCbor` a single decode that dispatches on the payload sum with no version fall-through. Checkpoints are regenerated deterministically from current source. Validation: `jitml test jitml-unit --linux-cpu` **771 / 771** (weight-only + supervised-graph round-trip and admission tests included); `jitml check-code` and `jitml docs check` pass in this same closure. |
| Registry-derived ProductRow live-report bridge | Phase `223` / formerly Sprint `19.4` (2026-07-21) | `JitML.App.productRowReportEvidenceForTargets`, `productRowReportEvidence`, and their live-report call sites are gone. Product scenario completion now consumes Store's opaque `AdmittedCompletedCheckpoint`, exact projection/manifest/completion identity, and retains the admitted manifest SHA; declaration labels cannot populate `ReportMeasurements`. The freely constructible seven-column `ProductRowReportEvidence` DTO remains only for legacy Sprint `31.3` lane-fragment parsing/rendering and cannot cross this boundary; its removal is separately tracked by the pending “Prose/table ProductRow lane-fragment aggregation” row. Phase `223` closed Done after the aligned-image 55-row publisher, unit, integration, negative-control, model-convergence, docs, and code-quality gates passed; its phase document records the exact evidence. |
| Shared host structural-operation callbacks in selected V2 engines | Sprint `10.6` (2026-07-19) | `Local`, `CudaLocal`, and `MetalLocal` no longer install `RuntimeOperations.host*` callbacks. Haskell-generated, content-addressed CPU/CUDA native kernels and Metal MSL implement the status-returning ABI version `1` / capability `0xff` boundary while retaining only the selected substrate's real MLP callback. Validation on immutable descriptor `0147b37f…` included the **156-step** reconcile, all-eleven exact-V2 Store parity, unit **711 / 711**, SL **36 / 36**, integration **155 / 155**, negative controls **3 / 3**, model convergence **111 / 111**, docs, and code quality. |
| Name-derived generic supervised checkpoint writer | Sprint `10.6` (2026-07-19) | At that historical boundary, authoritative supervised publication required the refined training-returned V2 artifact and non-optional completion, one physical `supervised.weights` JMW1 object, graph-derived virtual slices, and exact plan/seed/update/dataset/weight/evidence binding; generic V1 writers were retained for non-supervised compatibility only. The final immutable-image run published **11 / 11** exact Product-origin V2 rows, passed the focused pointer proof **1 / 1**, and passed the same full Sprint `10.6` validation gate. Phase `235` subsequently superseded that wire nomenclature and compatibility surface with one self-describing `RawCheckpointEnvelope` whose typed body is weight-only or supervised-graph; current writes do not use parallel V1/V2 checkpoint formats. |
| Residual hand-built live workflow lifecycle | Sprint `12.16` (2026-07-15) | Every evidence-bearing Linux Training, RL, Tune, AlphaZero, garbage-collection, and inference scenario routes through `runLiveWorkflow`, whose hidden `CompletedRunEvidence` is minted only after terminal success, complete exact evidence, and cleanup. WorkflowMatrix remains explicitly executable-outcome-only; exact Apple forwarding and duplicate-delivery placement checks are labelled smokes and cannot mint completion. Validation on immutable descriptor `6e0d5797…`: integration **155 / 155** including **18 / 18** Live, e2e Playwright **72 / 72** plus Haskell **29 / 29**, aggregate **11 / 11** reporter invocations with zero Failed or NotRun, docs, and code quality. |
| Ad-hoc RL list/tuple evidence collectors and total-looking zero fallback | Sprint `12.16` (2026-07-15) | `collectRlEventEvidence`, `collectRlEpisodeRewards`, `parseEpisodeIndex`, `parseEpisodeReward`, `nonDecreasingInts`, `medianDouble`, and `sortOnSafe` are absent. Typed protocol decode, semantic event identity, exact plan-correlated keyed maps, `NonEmpty (Finite Double)`, and distinct learning/evaluation evidence replace them without a generic zero fallback. Validation: unit **544 / 544**, integration **155 / 155** including the live PPO convergence scenario, and the same **11 / 11** aggregate pass. |
| Fabricated test-suite outcome surface | Sprint `12.16` (2026-07-15) | `InvocationResult = Passed | Failed | NotRun`, a hidden append-only `InvocationJournal`, and journal-derived `SuiteResult` status/count/duration replace declared pass counts, unconditional PASS labels, zeroed durations, and an unrepresentable fail-fast suffix. The binding aggregate reported **11** Passed, zero Failed, and zero NotRun; canonical docs and code-quality commands exited `0`. The independently owned post-test measurement probes remain Pending under Sprint `34.3`. |
| Primitive supervised `TrainingRunConfig` execution adapter | Sprint `10.12` (2026-07-14) | `TrainingRunConfig` now contains only canonical versioned `SupervisedPlan` transport, its derived `PlanId`, and the operational Pulsar endpoint. Local, Linux worker, and Apple host routes consume exact positive epoch, training-example, evaluation-example, batch-example, and derived optimizer-update quantities from that plan; mounted workers re-refine and reject malformed, non-canonical, version-incompatible, or identity-mismatched transport before effects. Traditional RL remains a separate Sprint `25.4` row. Validation: `jitml-unit` **411 / 411**, `jitml-sl-canonicals` **31 / 31**, `jitml-rl-canonicals` **40 / 40**, and `jitml-hyperparameter` **21 / 21**. |
| Optional completed-training proof on checkpoint protocol events | Sprint `10.12` (2026-07-14) | Training and RL protocols now separate proof-free `CheckpointDone` / `CheckpointDoneRL` candidates from `TrainingCompletedCheckpoint` / `RlCompletedCheckpoint` events whose smart constructors require a refined `CompletedTraining`. Tuning likewise separates `TuneSweepFinished` from mandatory-proof `TuneSweepCompleted`; versioned text/proto decoders re-refine the embedded completion bytes. The former `CheckpointDoneRL.cdrlCompletedTraining :: Maybe CompletedTraining` shape and its parse/publication callers are gone. Validation is shared with the Sprint `10.12` four-stanza pass above; the focused `ProtocolCodec` unit group passed **12 / 12**. |
| Forgeable budget, convergence, completion, and checkpoint proof payloads | Sprint `10.12` (2026-07-14) | `TrainingBudget`, finite `ConvergenceObservation`, criterion-indexed `PassedMeasurement`, and `CompletedTraining` constructors remain hidden. Versioned `RawCompletedTraining` / `RawCheckpointEnvelope` decode paths re-run structural refinement, derive unit labels from the closed budget kind, require exact observed-budget equality plus non-empty passing finite measurements, bind `PlanId`, and reject corrupt CBOR, non-finite values, unit mismatch, incomplete budgets, missing criteria, forged verdicts, evidence mismatch, or manifest-step mismatch. The later persisted-admission hardening removed the pure public `CompletedCheckpoint` / `InferenceEligibleCheckpoint` surface entirely: Format exposes only structural `ValidatedCheckpointCompletion`, while Store alone returns opaque `AdmittedCompletedCheckpoint` after exact persisted-byte admission. The 2026-07-14 four-stanza pass remains evidence for the original structural-refinement removal; the persisted-admission gate subsequently passed on 2026-07-20 and is recorded in Phase `10`'s current closure evidence. |
| Primitive Tune `RunConfig` axes/budgets and AlphaZero worker-side raw-command reinterpretation | Sprint `9.17` (2026-07-14) | `TuneRunConfig` and `AlphaZeroRunConfig` now carry only the canonical versioned resolved plan, derived `PlanId`, and operational Pulsar endpoint. Loaders re-refine and reject missing, malformed, version-incompatible, non-canonical, or identity-mismatched transports before effects; Linux and Apple routes execute the same plan and exact completion events reduce through `JitML.Run.WorkloadContract`. Validation: `jitml-hyperparameter` **21 / 21**, `jitml-rl-canonicals` **40 / 40**, `jitml-unit` **400 / 400**, `jitml-integration` **138 / 138** including **20 / 20** Live, `jitml docs check`, and `jitml check-code`. |
| Payload-derived semantic event identity | Sprint `8.16` (2026-07-12) | Removed `eventIdFromPayload`, public identity unwrapping, and payload-byte SHA identity from production/test callers. Strictly decoded daemon commands derive an opaque canonical `PlanId`, then an `EventId` from plan, command kind, and logical key; reordered text and protobuf encodings agree, while broker `DeliveryReceipt` remains the separate settlement identity. Validation: `jitml-unit` **367 / 367**, `jitml-daemon-lifecycle` **43 / 43**, `jitml-sl-canonicals` **31 / 31**, `jitml-rl-canonicals` **39 / 39**, docs, and code quality. |
| Lossy tuple subprocess outcomes and three-field `SubprocessFailed` in `src/JitML/Sub/Stream.hs`, `src/JitML/AppError/AppError.hs`, and their production/test callers | Sprint `1.18` (2026-07-12) | Replaced by `JitML.Sub.Outcome`: `runStreaming` / `capture` return `ProcessSucceeded ProcessTranscript` or `ProcessFailed ProcessFailure`; opaque failures retain a genuinely non-zero exit plus command, stdout, stderr, working directory, and monotonic duration, and `SubprocessFailed` carries that failure directly. Cabal, Playwright, bootstrap, lint, engine, capability, integration, and e2e callers preserve or render the complete outcome. Validation: `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed **284 / 284**; `docker compose run --rm jitml jitml docs check` exited `0`; `docker compose run --rm jitml jitml check-code` exited `0`. |
| Forgeable topic and subscription identifiers | Sprint `5.18` (2026-07-12) | `Topic event` and `Subscription event` constructors are hidden; the validated Coordinator topology and smart constructors are the only creation boundary. Newline and malformed identifiers are rejected before the broker interpreter. |
| Payload-keyed one-shot Pulsar acknowledgement and caller-owned settlement callbacks | Sprint `5.18` (2026-07-12) | Replaced by opaque receipt-bearing `Delivery event` values and one persistent scoped `pulsarConsumeUntil` interpreter. A handler returns exactly one `Disposition`; the interpreter alone settles, reconnects, drains, and deletes owned subscriptions. |
| Parallel string topic helpers outside the Coordinator topology | Sprint `5.18` (2026-07-12) | Protocol, workload, application, bootstrap, and integration callers consume the same opaque topology-derived routes. Workload-local topic renderers and raw topic wrappers/literals are removed. |
| Untyped `WorkloadEffect` / result pairing and malformed-command empty-effect fallback | Sprint `5.18` (2026-07-12) | Workload effects/results are kind-indexed and carried existentially as `SomeWorkloadEffect` / `SomeWorkloadOutcome`; strict decode yields an error or a `NonEmpty` effect program, never a successful empty fallback. |
| Redundant mutable `daemonReady :: Bool` field | Sprint `5.18` (2026-07-12) | Mutable readiness storage is removed. Closed `Starting`, `Ready`, `Degraded`, and `Draining` states carry the evidence from which the retained pure `daemonReady` accessor derives its answer. |
| No-caller legacy env-rendered RL Job (`_renderRlJobLegacyEnv`) | Sprint `5.18` (2026-07-12) | The compatibility renderer is deleted, so the retired `JITML_*` Job IPC is no longer constructible. Supervised training, tuning, and AlphaZero now use serialized resolved plans; the surviving primitive traditional-RL mounted adapter is tracked separately under Pending Removal. Shared validation for these six removals: `jitml-unit` **343 / 343**, `jitml-daemon-lifecycle` **41 / 41**, Phase-`5` integration **81 / 81**, `jitml docs check`, and `jitml check-code`; a clean `linux-cpu` bootstrap executed **130** steps. |
| Identity-copy CUDA generic-family kernels and degenerate 1×1 weighted Conv2D/Conv3D plus misleading "cuBLAS/cuDNN scaffold" comments in `src/JitML/Codegen/Cuda.hs` | Sprint `29.1` (2026-07-10) | Replaced by generated cuBLAS/cuDNN Dense/MHA/Conv2D/Conv3D/BatchNorm/LayerNorm family paths and source/runtime guards. Validation: `docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda` passed **22 / 22** on the RTX 5090; the broader Phase `29` lane passed `jitml test all --linux-cuda` **10 / 10** stanzas. |
| Dead cuBLAS/cuDNN bindings (`src/JitML/Engines/CublasBindings.hs`, `CudnnBindings.hs`) linked and version-probed but never invoked | Sprint `29.1` (2026-07-10) | The bindings are exercised by the real CUDA generated-family kernels instead of sitting as an unused link/probe surface. Validation: `docker compose run --rm jitml-cuda jitml test jitml-backends --linux-cuda` passed **22 / 22**, including cuBLAS/cuDNN execution coverage. |
| Per-call cudaMalloc + host-to-device weight copy + cudaFree in the executed MLP CUDA kernel path (`src/JitML/Codegen/MlpCuda.hs` `jitml_mlp_*`) | Sprint `29.4` (2026-07-10) | Replaced by persistent device weight buffers reused across fixed-parameter phases plus per-weight batch-gradient kernels. Validation: `docker compose run --rm jitml-cuda sh -lc 'cabal run -fcuda exe:jitml -- internal benchmark-product-row-wall-clock'` passed with **55 / 55** ProductRows faster on `linux-cuda` than `linux-cpu`. |
| Identity-copy Metal generic-family kernels and degenerate 1×1 weighted conv in `src/JitML/Codegen/Metal.hs` | Sprint `30.1` (2026-07-06) | Replaced with windowed Conv2D/Conv3D Metal source and source/runtime guards. Validation: `./bootstrap/apple-silicon.sh doctor` passed; `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal run exe:jitml -- internal install-metal-bridge` built and probed the fixed bridge; focused Apple backend source and multi-tap tests passed; full `PATH=/opt/homebrew/opt/llvm@19/bin:$PATH cabal test jitml-backends --test-options='--color=never --hide-successes -p apple-silicon' --test-show-details=direct` passed **20 / 20**. |
| **Expert-controller RL reward** and **HER constant reward** in `src/JitML/App.hs` | Sprint `25.x` (2026-07-06) | Removed hardcoded expert-controller reward reporting and constant HER reward artifacts; evaluation now comes from the trained policy paths. Validation: `docker compose run --rm jitml cabal test jitml-hyperparameter --test-options='--color=never --hide-successes' --test-show-details=direct` passed **19 / 19**, `docker compose run --rm jitml cabal test jitml-negative-controls --test-options='--color=never --hide-successes' --test-show-details=direct` passed **3 / 3**, and `docker compose run --rm jitml cabal test jitml-rl-canonicals --test-options='--color=never --hide-successes' --test-show-details=direct` passed **37 / 37**. |
| **RL algorithm stand-ins**: TRPO, RecurrentPPO, SAC, TQC, and CrossQ placeholder mechanisms | Sprint `25.x` (2026-07-06) | TRPO uses conjugate-gradient trust-region line search; recurrent PPO carries recurrent state into updates; SAC adapts temperature and includes entropy in actor gradients; TQC drops top quantile atoms; CrossQ uses batch statistics. Validation: `jitml-rl-canonicals` passed **37 / 37** and `jitml-negative-controls` passed **3 / 3**. |
| **Decorative RL/tuning hyperparameters** and **non-adaptive tuning search** | Sprint `25.x` (2026-07-06) | Declared trainer/tuning knobs now drive trainer updates and trial selection; TPE adapts to prior objectives, ASHA promotes by measured rungs, and MedianPruner filters measured trials. Validation: `jitml-hyperparameter` passed **19 / 19**. |
| **AlphaZero product-path truncation** and untrained random-init policy/value panel artifacts | Sprint `26.x` (2026-07-06) | AlphaZero product training uses full per-game `maxPlies`, multi-generation self-play, device-backed updates, and a strict arena threshold that rejects the all-draw `0.5` sentinel. Validation: focused `AlphaZero per-game arena evidence` passed **1 / 1**, full `jitml-rl-canonicals` passed **37 / 37**, and `jitml-negative-controls` passed **3 / 3**. |
| **`FutureOwner` scaffold-lint exemption** in `src/JitML/Lint/ProductTruth.hs` | Sprint `20.x` (2026-07-06) | Removed the `FutureOwner` status path; `seeded-demo-weights` is now an active registry entry rather than an exempt future-owned scaffold. Validation: `jitml-unit` passed **277 / 277** and the product-truth unit guard rejects a reintroduced `mnist-demo-weights` scaffold. |
| **Tautological convergence bar** derived from the measured value | Sprints `19.x` / `21.x` (2026-07-06) | Product convergence observations now derive from external constants in `JitML.Product.ExternalBars`; inference eligibility re-checks completed metrics against those bars and AlphaZero arena evidence uses the strict non-draw predicate. Validation: `jitml-negative-controls` passed **3 / 3**, `jitml-unit` passed **277 / 277**, and `jitml-rl-canonicals` passed **37 / 37**. |
| **All-zeros weight-movement evidence** in checkpoint completion | Sprint `21.x` (2026-07-06) | Removed the synthetic all-zero initial-weight fallback and the internal seed-demo checkpoint writer; completed training evidence now requires explicit real training evidence instead of auto-minting from checkpoint bytes. Validation: `jitml-unit` passed **277 / 277** and `jitml-negative-controls` passed **3 / 3**. |
| Product-path seeded demo checkpoints (`seededDemoCheckpoints`, `*-demo-weights`) in `src/JitML/App.hs` | Sprint `27.1` (2026-07-02) | Retired from the product publish path. Product-row demo artifacts are now produced by `jitml internal train-and-publish-product-rows`; checkpoint browse groups artifacts by `ProductRow`, and row selectors expose `eligible`, `training-required`, `unsupported`, or `error` state. Validation: `jitml-unit --linux-cpu` 276 / 276 and `jitml-e2e --linux-cpu` 23 / 23. |
| Fabricated `coPassed = True` / `coThreshold = Nothing` completion witness in `JitML.Training.Budget.completedTrainingFromMetrics` | Sprint `21.1` (2026-07-02 ledger move; reclosed 2026-07-06) | The 2026-07-05 audit found the original closure incomplete because the tautology had moved to the checkpoint writer. The 2026-07-06 "Tautological convergence bar" row above closes that reopened defect with external bars and decode-time rechecks. |
| Dead deterministic RL scaffold `src/JitML/RL/VecEnv.hs` | Sprint `20.1` (2026-07-01) | Deleted the zero-product-caller module and removed it from `jitml.cabal` exposed modules. Validation: `jitml-unit --linux-cpu` 246/246, `jitml-rl-canonicals --linux-cpu` 31/31, `docs check: ok`, and `check-code: ok`. |
| Fake non-learned RL loop `src/JitML/RL/Loop.hs` plus `deterministicStep` in `src/JitML/RL/Environments.hs` | Sprint `20.1` (2026-07-01) | Removed the library module and product `deterministicStep`; relocated `runRLLoop`, `runOneEpisode`, and the deterministic step helper to `test/rl-canonicals/Support/` with `scaffolding:` test titles. No product module imports them. Validation: `jitml-unit --linux-cpu` 246/246, `jitml-rl-canonicals --linux-cpu` 31/31, `docs check: ok`, and `check-code: ok`. |
| Fake-policy simulator runners from `src/JitML/RL/SimulatorLoop.hs` | Sprint `20.1` (2026-07-01) | Removed the product simulator-loop module, moved `runSimulatedEpisode*` and the simulator catalog to `test/rl-canonicals/Support/SimulatorLoop.hs`, and split the product `SimulatedEpisode` / `SimulatedFrame` projection types into `src/JitML/RL/EpisodeEnvelope.hs` for real trainer publication. Validation: `jitml-unit --linux-cpu` 246/246, `jitml-rl-canonicals --linux-cpu` 31/31, `docs check: ok`, and `check-code: ok`. |
| Stale `runTrainerEpisodes` docstring claiming a deterministic-simulator fallback | Sprint `20.1` (2026-07-01) | Reworded `src/JitML/App.hs` and `src/JitML/Service/Workload.hs` to describe fail-closed real-trainer dispatch, changed unknown algorithm trainer selection away from the old `"simulator"` sentinel, and kept `EpisodeEnvelope` as the projection boundary. Validation: `jitml-unit --linux-cpu` 246/246, `jitml-rl-canonicals --linux-cpu` 31/31, `docs check: ok`, and `check-code: ok`. |
| File-only `jitml cluster up` implementation in `src/JitML/App.hs` | Sprint `3.7` (2026-06-30) | `runCluster ["cluster","up"]` now materializes the selected substrate files and executes `JitML.Bootstrap.liveExecutePhasedRollout`, so the command performs the documented live Kind/Helm lifecycle: dependency build, Kind create/export, Docker image build, explicit Kind image load, Helm/local apply, readiness, Pulsar topic creation, and measured publication write. Validation: `docker compose run --rm jitml jitml cluster up --substrate linux-cpu` completed a live 107-step rollout, and `docker compose run --rm jitml jitml test jitml-integration --linux-cpu` passed 77/77 including 19/19 `Live` cases. |
| Ready `defaultPublication` written or synthesized without live evidence (`src/JitML/Bootstrap.hs`, `src/JitML/Cluster/Publication.hs`, `src/JitML/App.hs`) | Sprint `3.7` (2026-06-30) | Bootstrap materialization no longer writes `cluster-publication.json`; measured live publications carry `evidence: live-readiness`; `cluster status` exits through typed configuration failure for missing, corrupt, or no-live-evidence publications instead of synthesizing ready state. Validation: spawned-binary integration regressions cover missing publication, corrupt bytes, and default all-ready publication without evidence; live `cluster status` reports `evidence: live-readiness`. |
| Mounted `RunConfig.dhall` decode failure treated as missing in `src/JitML/Service/RunConfig.hs` and worker callers | Sprint `5.17` (2026-06-30) | `RunConfig.tryLoadFile` now distinguishes `RunConfigMissing`, `RunConfigLoaded`, and `RunConfigDecodeFailed`; worker Training/Tune/RL entrypoints, broker-target lookup, and experiment-hash lookup route present-but-malformed mounts to `InvalidConfig` before workflow side effects. Env/default fallback remains only when no mounted file exists for developer-local invocations. Validation: `jitml-unit --linux-cpu` 239/239 includes malformed mounted Training/Tune/RL regressions; `jitml-daemon-lifecycle --linux-cpu` 32/32; live `jitml-integration --linux-cpu` 77/77; `check-code: ok`. |
| Display-only tuning CLI overrides in local tune execution (`src/JitML/App.hs`) | Sprint `9.16` (2026-06-30) | `runTune` applies `JitML.Experiment.Overrides.applyOverrides` before rendering/validation and passes the resolved experiment into local artifact writing, so sampler/trial overrides drive `tune-trials` artifacts and best-trial checkpoint promotion. Validation: `jitml-hyperparameter --linux-cpu` 17/17; live `jitml-integration --linux-cpu` 77/77. |
| Daemon tuning worker catalog-product fallback that ignored the selected axes (`src/JitML/App.hs`, `src/JitML/Service/Workload.hs`) | Sprint `9.16` (2026-06-30) | The worker uses the selected sampler/scheduler/pruner rather than silently enumerating the catalog. Sprint `9.16` originally proved this through primitive `TuneRunConfig` axis fields; Sprint `9.17` preserves the behavior while replacing that intermediate transport with a canonical resolved `TuningPlan` / `PlanId`. Historical validation: live `jitml-integration --linux-cpu` 77/77, including daemon `StartSweep` placement. |
| Untyped local checkpoint object-key guard in `JitML.Checkpoint.Store.safeRelativePath` | Sprint `10.11` (2026-06-30) | Local object-key-to-path conversion now returns `Either Text FilePath`; empty, absolute, and parent-traversing keys are rejected before filesystem path construction. Local checkpoint write/read/list helpers propagate typed validation failures, app write sites render them as `InvalidConfig`, and spawned local `jitml internal gc ../escape` exits through `InvalidConfig` rather than process termination. Validation: `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed 237/237; `docker compose run --rm jitml jitml test jitml-integration --linux-cpu` passed 77/77 including 19/19 `Live`; `docker compose run --rm jitml jitml check-code` passed. |
| Untyped tuning resume decode bottom in `JitML.Tune.Resume.replaySweep` | Sprint `9.15` (2026-06-30) | `ResumeOutcome.resumeReadFailures` now carries `(trial-key, ResumeReadFailure)`, with `ResumeServiceFailure ServiceError` for missing/read failures and `ResumeDecodeFailure Text` for corrupt transcript bytes. `ResumeOutcome` `Show` / `Eq` are total, so corrupt transcripts remain structured data at the caller boundary. Validation: `docker compose run --rm jitml jitml test jitml-hyperparameter --linux-cpu` passed 17/17; after a fresh image build and `jitml bootstrap --linux-cpu` 105-step rollout, `docker compose run --rm jitml jitml test jitml-integration --linux-cpu` passed 77/77 including 19/19 `Live`; `docker compose run --rm jitml jitml check-code` passed. |
| Untyped RL device-failure bottoms in DQN / QR-DQN / HER / continuous trainer update helpers | Sprint `8.15` (2026-06-29) | `trainDqnOnDevice`, `trainQrDqnOnDevice`, `trainHerOnDevice`, and `trainContinuousOnDevice` now return `Either Text` and propagate forward, batch-gradient, and input-gradient failures through `runTrainerEpisodes` without partial episode projection or publication. ARS remains the only no-MLP exception; no pure fallback was reintroduced. Unit regressions inject failing `MlpDevice` operations. Validation: `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`, `docker compose run --rm jitml jitml test jitml-rl-canonicals --linux-cpu`, `docker compose run --rm jitml jitml test jitml-backends --linux-cpu`, and `docker compose run --rm jitml jitml check-code` all passed. |
| Silent user-facing numeric CLI coercion through `readInt` | Sprint `1.17` (2026-06-29) | `service --consume-once`, `rl rollout --seed`, and AlphaZero self-play `--games` / `--sims` / `--max-plies` / `--updates` / `--arena-games` now parse through `parseUserIntOptionAtLeast`, returning typed `InvalidConfig` on malformed or below-bound values instead of silently coercing through `readInt` to `0` or `1`. Unit coverage asserts every listed flag. Validation: `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`, `docker compose run --rm jitml jitml docs check`, and `docker compose run --rm jitml jitml check-code` all passed. |
| Documentation metadata enforcement gap | Sprint `0.3` (2026-06-29) | `JitML.Docs.Check` now validates governed Markdown headers for `Status`, `Supersedes`, `Referenced by`, `Generated sections`, and `Purpose`; generated-section metadata is reconciled with physical markers and the `GeneratedSectionRule` registry; failures surface through `DocsCheckDrift` / `jitml lint docs` with metadata-specific remedies. Validation: `docker compose run --rm jitml jitml docs check`, `docker compose run --rm jitml jitml lint docs`, and `docker compose run --rm jitml jitml check-code` all passed. |
| Compact single-node/right-sized local topology | Sprints `3.6` / `4.10` (2026-06-28) | Replaced the single-control-plane/no-worker Kind fixtures and right-sized service/storage materialization with the HA topology: `JitML.Cluster.Kind` and `kind/cluster-*.yaml` render one control-plane plus three workers, resource caps/mount prep covers every materialized node, `JitML.Cluster.Storage` and PV templates cover HA storage counts, `chart/values/minio.yaml` is distributed with 4 replicas, `chart/values/pulsar.yaml` is 3x ZooKeeper/BookKeeper/Broker/Proxy, and registered Postgres renders 3 instances plus pgBackRest. Validation: `cabal build exe:jitml --ghc-options=-fasm`; materialized all three substrates; `jitml-integration -p HA`; `jitml-integration -p distributed`. Live HA lane revalidation remains Phase `15`/`16` work, not ledger debt. |
| Ambiguous numerical worker cardinality under HA scaling | Sprint `5.16` (2026-06-28) | Encoded the one-numerical-worker-per-Kubernetes-node invariant in `src/JitML/Service/ConfigMap.hs`, `src/JitML/Service/Workload.hs`, and `chart/local/jitml-service`: Linux Engine pods and daemon-spawned Linux workload Jobs share `jitml.compute="true"`, compute-node selectors, required hostname anti-affinity, and hard topology spread; Apple cluster pods remain non-compute forwarders. Validation: `jitml-integration -p cardinality`; `jitml-daemon-lifecycle -p cardinality`. |
| Placeholder top-level `jitml verify` command group | Sprint `1.16` (2026-06-27) | Removed `verify same-run` and `verify replay` from `CommandSpec`, parser/help/generated docs, completions/manpage, canonical leaf tests, and `App.hs` dispatch. Same-run/replay obligations remain covered by substrate-partitioned Cabal stanzas, checkpoint/inference tests, and `jitml inference run`; no user-facing placeholder `verify` surface remains. |
| Placeholder top-level `jitml inspect` command group | Sprint `1.16` (2026-06-27) | Removed `inspect list/show/replay/trial/frontier` from `CommandSpec`, generated docs, completions/manpage, canonical leaf tests, and `App.hs` dispatch. The old `inspect replay` manifest branch and helpers were deleted; checkpoint replay/inference verification is owned by `jitml inference run`, checkpoint loaders, and the live test lanes. |
| Placeholder top-level `jitml bench` command group | Sprint `1.16` (2026-06-27) | Removed `bench train/inference/env` from `CommandSpec`, generated docs, completions/manpage, canonical leaf tests, and `App.hs` dispatch. Benchmark/report-card telemetry remains on `jitml test all --live`, `/metrics`, and backend measurement tests. |
| User-facing `jitml kubectl` passthrough command | Sprint `1.16` (2026-06-27) | Removed the top-level `kubectl` passthrough from `CommandSpec`, generated docs, completions/manpage, canonical leaf tests, and `App.hs` dispatch. Kubernetes effects remain behind typed bootstrap subprocesses and the daemon `HasKubectl` capability; no public passthrough command is documented or implemented. |
| Seeded demo checkpoint catalog and seeded experiment list | Sprints `10.10` / `14.4` (2026-06-26; reclosed 2026-07-06) | The 2026-07-05 audit found this closure incomplete because untrained AlphaZero panel artifacts could decode as inference-eligible and serving relied on an ad-hoc `demo-weights` suffix filter. The 2026-07-06 AlphaZero product-path and type-state rows above close the reopened defect by retiring the internal seed-demo checkpoint writer, requiring external bars at decode, and training AlphaZero product artifacts through the real path. |
| Seeded AlphaZero policy/value panel tensors | Sprints `9.14` / `14.4` (2026-06-26) | The Connect 4, Othello, Hex, and Gomoku demo checkpoints are seeded as completed policy/value manifests with self-play metrics (`arena_win_rate`, `legal_move_rate`, `mcts_simulations_per_move`, `self_play_samples`) and are rendered through the all-model matrix. Validation: live Playwright exercises all adversarial selectors and checkpoint browse rejects partial/untrained/smoke/fake evidence. |
| Hardcoded WorkflowMatrix checkpoint staging | Sprints `12.15` / `13.3` (2026-06-26) | `stageWorkflowMatrixCheckpoint` now stages completed checkpoint manifests for transport/eval coverage, while infer-before-complete rejection is covered separately and product proof comes from live completed artifacts. The helper remains test scaffolding, not no-caveat product evidence. |
| Local fake browser runtime | Sprints `12.15` / `14.4` (2026-06-26) | `fakeBrowserRuntime` stays as a local route/contract harness only. The product claim is the live Playwright run against a bootstrapped `linux-cpu` edge with completed checkpoint manifests, direct live endpoint probes, and all-model checkpoint UI assertions. |
| Dense-only SL compatibility cohort | Sprint `8.14` (2026-06-26) | The product cohort is `trainableCanonicalCohort`; `denseMlpCohort` / `isDenseMlpProblem` no longer exist in source or tests. Validation: residual-symbol grep over `src` and `test` returns no matches, `jitml-sl-canonicals` 24/24, and the full live `linux-cpu` aggregation passed. |
| Faked SL loss (`1 − accuracy`; `ecValidationLoss = finalLoss`) | Sprint `8.13` (2026-06-24) | The SL training runners (`runDeviceMnistTrainingWithLimits`, `runDeviceArchiveClassifierTraining`, `runDeviceCaliforniaHousingTraining`) and both training-event publishers (`publishWorkerTrainingEvent`, `publishTrainingEpoch`) in `src/JitML/App.hs` now publish a real mean softmax cross-entropy / MSE training loss (`crossEntropyArchitectureWithDevice` / `meanSquaredErrorWithDevice`) and a distinct real held-out **validation** loss from the carved validation partition (`splitTrainValidation` + `trainArchitectureWithDeviceSelected`'s lowest-validation-loss selection). Validation: `jitml-sl-canonicals` --apple-silicon 24/24 (real Metal device) + --linux-cpu 24/24 (real oneDNN), `docs check` + `check-code` green. |
| Synthetic RL convergence probes (`literatureTarget ± slack`) | Sprint `9.13` (2026-06-24) | Removed `assertConvergencePredicate` (which fed the literature target in as if measured) from `test/rl-canonicals/Main.hs`; replaced with `assertMeasuredMedianConvergence` (real `trainPpoOnCartpole` over k seeds → measured median through the production `passesConvergence`, plus the env-steps-to-threshold sample-efficiency metric) and `assertAlphaZeroArenaConvergence` (real self-play → arena win-rate through the new typed `AlphaZeroArenaThreshold` / `passesAlphaZeroArena` in `src/JitML/RL/ConvergenceThresholds.hs`); a pure `assertPassesConvergenceBoundary` keeps the predicate unit test. Validation: `jitml-rl-canonicals` --apple-silicon 31/31 + --linux-cpu 31/31, `check-code` green. |
| Synthetic `demoWeights` ramp (byte-identical across all 5 seeds) | Sprint `10.9` (2026-06-25) | Removed the hardcoded `demoWeights = [0.05 + ((i*7+3) mod 11)/20 | i in 0..255]` ramp from `runInternalSeedDemoCheckpoints`; replaced it with `seededDemoCheckpoints`, one distinct provenance-tagged, self-describing seeded fixture checkpoint per demo family (per-layer `W1`/`b1`/`W2`/`b2` tensor shapes + class-count output spec). Validation: grep-clean, the `jitml-unit` "demo checkpoints (Sprint 10.9)" distinctness/self-describing case, `jitml-e2e` 23/23, `check-code` green in the rebuilt `jitml:local` image, and a live `linux-cpu` proof: 109-step bootstrap, `jitml internal seed-demo-checkpoints`, then sequential `jitml inference run` for `mnist-deep-mlp`, `generic-tensor-demo`, `generic-tensor-demo-candidate`, `cifar-imagenet`, and `connect4-alphazero`, all returning family-distinct outputs. |
| Single fixed-vector Dense2D demo forward (collapses every family; output width = input length) | Sprint `14.3` (2026-06-26) | The demo checkpoint runtime now detects self-describing `W1`/`b1`/`W2`/`b2` checkpoint tensors and routes them through the real substrate MLP forward on `oneDNN`, CUDA, or Metal (`JitML.Engines.MlpCheckpoint`, `Local`, `CudaLocal`, `MetalLocal`) before trimming to the semantic output width. The seeded demo set expanded to eight typed fixture checkpoints (`mnist-deep-mlp`, `generic-tensor-demo`, `generic-tensor-demo-candidate`, `cifar-imagenet`, `connect4-alphazero`, `othello-alphazero`, `hex-alphazero`, `gomoku-alphazero`). Validation: `jitml-unit` 222/222, `spago test` 17/17, `jitml check-code: ok`, `docker compose build jitml` green (embedded `check-code` + PureScript warnings/errors 0/0), live endpoint probes returned full-width outputs (`MNIST` 10, image top-k 10, generic 3, compare 3/3, adversarial move + replay), and live Playwright passed 15/15. |
| Constant panel inputs (ignore user input) | Sprint `14.3` (2026-06-26) | The PureScript panels now send user-derived input: MNIST uses the ink control to fill the 784-value request, CIFAR/ImageNet uses upload token state with a 3072-value request, generic inference and checkpoint compare use panel numeric inputs, and adversarial selectors submit the selected game/checkpoint hash. POST ack handlers parse full Engine-backed result frames directly, removing the websocket race that previously left empty output lists. Validation is shared with the Sprint `14.3` row above: unit 222/222, web tests 17/17, image build green, direct live POST probes with non-empty outputs, and Playwright 15/15. |
| Stale committed `hlint` hints + tree-wide `fourmolu` drift (durable-state DSL closure residue) | Sprints `8.13`/`9.13` (2026-06-24) | The container `check-code` gate (fourmolu + hlint + `cabal build all -Werror` + cabal format) was red on **committed** code: 3 stale `hlint` hints (`Project/Config.hs` eta-reduce, `Storage/Buckets.hs` unused `OverloadedStrings`, `DurableStateTopology.hs` use-`void`) and `fourmolu` drift in `CLI/Spec.hs` / `Project/Config.hs`. All fixed (8 hlint hints total + `fourmolu --mode inplace` over `src`/`app`/`test`, pinned `fourmolu-0.19.0.1`); the `jitml:local` image now builds with `check-code` green again. |
| Incomplete visualization and replay renderers (transcript-backed adversarial replay) | `web/src/Panels/Replay.purs` (new), `web/src/Panels/Connect4.purs`, `src/JitML/Service/Transcript.hs` (new), `src/JitML/Service/Workload.hs` | Sprint `14.1` (2026-06-23) | The adversarial replay is now **transcript-backed from recorded engine transcripts**: the Engine persists every adversarial game's full move sequence + analysis to the `jitml-transcripts` MinIO bucket (content-addressed CBOR, `JitML.Service.Transcript`), keying the result frame to the **real** MinIO object key (the synthesized fallback is used only if the write genuinely fails); a `LoadTranscriptCommand` Engine workflow reads it back and publishes a `TranscriptReplay` frame; and `web/src/Panels/Replay.purs` scrubs the persisted moves move-by-move (reusing the Connect4 board reconstruction). The Connect4 panel surfaces the real transcript id at `#connect4-human-vs-alphazero-transcript`. **Live-validated:** `linux-cpu` Playwright "transcript replay scrubs a persisted adversarial game" passes (the persisted object is confirmed in MinIO). A robustness fix makes a missing/unreadable transcript publish an empty reply (ack) rather than NACK-retry forever. |
| Browser product-contract expansion gap (checkpoint browse + workflow-state reconciliation) | `src/JitML/Web/Contracts.hs`, `web/src/Generated/Contracts.purs`, `web/src/Panels/{Checkpoints,Workflow}.purs` (new), `src/JitML/Service/{Workload,WorkflowStatus}.hs` | Sprint `14.1` (2026-06-23) | The generated contract surface now covers the no-caveat product instead of route-only/published-ack placeholders: **checkpoint browse** is a real `ListCheckpoints` Engine workflow (`CheckpointList`/`CheckpointSummary` contracts → lists the seeded checkpoints from MinIO via `listCheckpointManifestsMinIO` → `Checkpoints.purs` panel), and **live-backed workflow-state reconciliation** publishes reconciled `WorkflowStatus` frames to `workflow.status.<substrate>` from the Engine's command-lifecycle projector (`JitML.Service.WorkflowStatus`), bridged to the browser over a new `/api/ws/workflow` and rendered live by `Workflow.purs`. **Live-validated:** `linux-cpu` Playwright "checkpoint browse panel lists seeded checkpoints" and "workflow status panel renders a live status table" pass. Validation across both rows (host-native + live): `cabal build --ghc-options=-Werror` clean, `jitml lint haskell`/`lint purescript`/`docs check` ok, `jitml-unit` 209 + `jitml-e2e` 23 + `jitml-daemon-lifecycle` 32, in-image `check-code` ok, and the full `linux-cpu` Playwright matrix **14/14** (exit 0). |
| Dense-only SL classifier as the tuning objective | Sprint `13.1` (2026-06-23) | The tuning objective no longer trains the Dense-only `Classifier.trainClassifier` / `trainClassifierWithDevice` — it trains the fixed Dense `CanonicalProblem` through the production `JitML.SL.Architecture` seam (`trainArchitectureWithDevice`), the offline sweep via a new toolchain-free `pureReferenceMlpDevice` (`JitML.Numerics.MlpDevice`, built on pure `mlpForward`/`mlpBackward`/`mlpInputGradient`) so `deterministicTrials` stays pure, and the device sweep + report card via the real substrate device; trial weights come from `Architecture.trainedArchitectureWeights`. **Validated:** host-native `cabal build all` clean + `jitml-hyperparameter` 16/16; **live on `linux-cpu`** — `jitml test all --live --linux-cpu` ran the migrated `deterministicTrialsWithDevice` through the substrate device and measured `tune_best_objective: TPE=1.0`, **unchanged** (the deterministic separable tuning dataset still admits a 100%-accuracy trial), so the committed `apple-silicon`/`linux-cuda` `TPE=1.0` fragments stay consistent and no per-lane re-baseline is needed. The product stand-in (the tuning objective *being* the Dense-only classifier) is removed; the now-test-only `trainClassifier`/`accuracy`/`trainClassifierWithDevice` are **retained as legitimate pure-numerics `jitml-sl-canonicals` coverage** of the pure MLP classifier path — not a removable stand-in. (Their optional physical deletion is a test-redesign with no product impact.) |
| Hand-written numerics/RL catalog Dhall schema (reflected emission) | Phase `5` (2026-06-23) | The numerics and RL catalog `.dhall` leaves are now **reflected-emitted** from the Haskell catalogs by `JitML.Service.CatalogSchema` (rendered from the same `expectedNumericsCatalog` / `expectedRlCatalogSchema` mirror data the decoders read), exposed by `jitml internal dhall-schema --catalog numerics|rl|all`, and parity-tested in `jitml-unit` ("every numerics/RL catalog Dhall leaf equals the emitted catalog" — `canonicalDhallType` file ≡ emitted on both sides; the RL `Algorithm.dhall` emission is byte-identical to the checked-in file). This complements the existing decode-and-compare mirror (file → Haskell) so drift now fails in **both** directions. The `experiments/*.dhall` files are instance/data fixtures (no hand-written schema *type* file to drift) and are validated by typed decode through their Haskell decoders in `jitml-sl-canonicals` / `jitml-unit` / `jitml-integration` (`loadCanonicalProblemExperiment "experiments/mnist.dhall"`, etc.); the two aggregator `dhall/{numerics,rl}/Schema.dhall` records carry only file imports and stay hand-written. Validation (host-native): `cabal build lib:jitml exe:jitml` clean, `jitml-unit` catalog-parity case PASS, `jitml docs check: ok` after `jitml docs generate` regenerated the `--catalog` CLI surface. |
| Docker Hub image pre-pull credential path (adopted as owned; no longer pending) | Sprint `2.13` (2026-06-23) | The authenticated host pre-pull of `docker.io/*` chart images before `kind load` (`src/JitML/Bootstrap.hs` `cachedThirdPartyRolloutImages`, the `bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh` host pre-pull loop, `jitml internal third-party-images`) plus the Sprint `2.14` in-cluster `imagePullSecret` projected from the host Docker Hub credential are now **jitML's own self-contained Docker Hub credential path**, owned by the project. jitML is treated as self-contained — there is no external foundation this path transfers to — so the row leaves Pending Removal as an adopted owned mechanism, not a deletion. The host-dependent containerd-image-store `kind load` behavior (colima `io.containerd.snapshotter.v1`: `ctr import --all-platforms` digest mismatch; a plain `docker save` then `ctr import` loads them) is a known characteristic the owned path accommodates; on a classic overlay2 store the `kind load` path works directly. |
| Catalog rollout compatibility helper | Sprint `13.1` (2026-06-22) | Deleted the deterministic catalog-projection rollout — `trajectoryRollout`, `AlgorithmRollout`, `renderRollout`, and the `moduleRolloutGenerator` field of `AlgorithmModule` (`src/JitML/RL/Algorithms/Common.hs`) plus the field from all 14 algorithm-module registrations, and the now-orphaned `realRolloutByName`/`realRollout` (`src/JitML/RL/SimulatorLoop.hs`, verified no other callers). `test/rl-canonicals/Main.hs` is **migrated onto the checkpoint-backed trained-policy product path**: the per-algorithm and PPO run-to-run determinism cases now train the real trainer for each of the 14 families (on-policy via `PpoTrainer.trainOnPolicyOnCartpole` + `collectRollout`; DQN/QR-DQN via `DqnTrainer`; DDPG/TD3/SAC/CrossQ/TQC via `ContinuousTrainer`; ARS via `ArsTrainer`; HER via `HerTrainer`) twice with a fixed seed and assert bit-identical rollouts/statistics (an unhandled algorithm hard-fails — no vacuous assertion). The deterministic catalog seam is gone; the tests now exercise the real product. Validation (host-native): `cabal build all --ghc-options=-Werror` EXIT 0, `jitml-rl-canonicals` 29/29, fourmolu + hlint clean, residual-symbol grep over `src/`+`test/` returns 0. |
| Superseded Apple inference refs RPC (`AppleInferenceCommand` / `AppleInferenceEvent`) | Sprint `16.12` (2026-06-22) | Deleted `src/JitML/Service/AppleInferenceRpc.hs` (`appleInferenceRpcPlan`, `handleAppleInferenceCommand`, `publishAppleInferenceEvent`, `correlateAppleInferenceEvent`) + its `jitml.cabal` entry; deleted the `AppleInferenceCommand`/`AppleInferenceEvent` types, render/parse helpers, and `appleInferenceEventTopic` from `src/JitML/Proto/Inference.hs` (kept the live `appleInferenceCommandTopic`); deleted `appleHostInferenceRunner` from `src/JitML/App.hs`; collapsed `daemonWorkloadDispatcherForwardingInference` to the values-model legs and reduced `daemonWorkloadDispatcherHostingAppleInference` to a weighted-dispatch alias (`src/JitML/Service/Runtime.hs`); dropped the `(Infer, Event)` subscription (`src/JitML/Service/Consumer.hs`) and the `RouteEntry Infer Event [AppleSilicon]` route (`src/JitML/Coordinator/Topology.hs`); removed the Apple-RPC `jitml-daemon-lifecycle` cases and `inference.event.apple-silicon` from the `jitml-daemon-lifecycle` / `jitml-integration` / `jitml-unit` topic assertions; and updated `daemon_architecture.md` / `cluster_topology.md` to the values-model forward. The converged values model (cluster forwards raw `RunInference`/`CheckpointCompareCommand`/`AdversarialMoveCommand` → host Engine replies `InferenceResult`/`CheckpointCompareResult`/`AdversarialMoveResult` on the reply-topic) is now the only Apple inference path. Validation (host-native): `cabal build --ghc-options=-Werror lib:jitml exe:jitml` clean, `jitml-unit` 208/208, `jitml-daemon-lifecycle` 32/32, fourmolu + hlint clean, residual-symbol grep over `src/`+`test/` returns 0. |
| Two-binary `jitml-demo` split | Sprint `11.10` | `exe:jitml-demo`, `app/Demo.hs`, `JitML.App.demoMain` (+ orphaned `DemoArgs`/`parseDemoArgs`/`readMaybeInt` helpers), the `Demo.hs` build/`cp` in `docker/Dockerfile`, and the `JITML_DEMO_*` env selection are deleted. The demo is now the one-binary **Webapp** role: `jitml service` with typed Dhall `activeRole = Webapp` (`runWebappRole` in `src/JitML/App.hs`), configured by a `jitml-webapp-config` ConfigMap; the `jitml-demo` chart deployment runs `jitml service --config /etc/jitml/BootConfig.dhall`. **Live-validated** on `linux-cpu`: the pod logs `webapp: serving 0.0.0.0:80`, and the routed edge serves `/` (the demo HTML) and `/bundle/main.js` (the 340 KB Halogen bundle) with HTTP 200. |
| Demo in-process inference compute | Sprint `11.10` | `demoBrowserRuntimeHandler` (which ran `engineWeightedInference` in-process) is deleted; the Webapp's browser-runtime handler now **publishes** an inference `WorkCommand` to the Engine via `requestInferenceViaEngine` and renders the streamed result — the **Engine** (daemon) is the only role that computes, per the [pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md) contract. (All five browser panels are now async via `subscribeStream "/api/ws/inference"` — see the "Synchronous inference REST + PureScript fetch panels" Completed row.) |
| Synchronous inference REST + PureScript fetch panels | Sprint `11.10` | All five inference panels are now **asynchronous to the browser** and the **Engine is the only role that computes**. Single-inference panels (Mnist/GenericInference/Cifar) publish fire-and-forget and render the Engine-decoded `DecodedInference`; **CheckpointCompare** and **Connect4** became new **Engine workflows** (riding the inference topics with `CheckpointCompareCommand` / `AdversarialMoveCommand` kinds): the daemon computes the compare **delta** (`runCheckpointCompareRequestWithWeightedInference`) and the **MCTS** move (`runAdversarialMoveRequestWithWeightedInference` + the pure `JitML.Inference.AdversarialMove`, relocated from the webapp). All five panels `subscribeStream "/api/ws/inference"` and render the streamed frame matched by `experiment-hash`; the webapp publishes commands via `BrowserCommandPublishers` (the synchronous handler path remains only as the no-publisher test fallback). Validation: `cabal build all` clean, hlint/fourmolu clean, `spago build` 0 errors + `spago test` 16/16, `jitml lint purescript: ok`, `jitml-unit` 208/208, `jitml-e2e` 23/23, `jitml-daemon-lifecycle` 35/35. Live Playwright product proof is downstream (Sprints `14.2` / `16.11`). |
| Triplicated inference `pick-runner→run-kernel` logic | Sprint `10.7` | The per-substrate weighted-checkpoint runner dispatch (`run{LinuxCpu,Cuda,Metal}WeightedCheckpointInference`) is no longer copied across the demo HTTP handler, the `jitml inference run` CLI, and the daemon consumer. All three route through the single `engineWeightedInference` (`src/JitML/App.hs`) — the only site that picks the substrate runner and runs the kernel. Validation: `jitml-unit` 206/206, `jitml-daemon-lifecycle` 35/35, behavior-preserving (warning-clean `-Wall`). The remaining "demo/CLI **publish-only** so only the **Engine** computes" routing is the async websocket behavior tracked by the "Demo in-process inference compute" / "Synchronous inference REST + PureScript fetch panels" rows (Phase `11` Sprint `11.10`) and Sprint `10.7` Remaining Work (CLI publishes a `WorkCommand`). |
| Hardcoded Pulsar topic list | Sprint `5.13` | The hand-written `pulsarTopics` / `substrateTopics` / `appleSiliconInternalTopics` literals are deleted from `src/JitML/Cluster/PulsarBootstrap.hs`. Every topic now derives from the Coordinator's typed topology descriptor + validated routing graph in `JitML.Coordinator.Topology` (`topicFor`, `jitmlTopology`, `validateTopology`, `coordinatorTopics`); `PulsarBootstrap` and the daemon subscription plan (`daemonSubscriptionsForBootConfig`) both consume the derived set, producing byte-identical topic names. Validation: `jitml-unit` 203/203 (historical derived family + routing-graph validator), `jitml-daemon-lifecycle` 35/35, the offline `jitml-integration` topic-family case, and `check-code` (in-container build). Sprint `12.16` validates the separate live Coordinator reconcile-at-acquire path with exact-family readiness evidence. |
| Demo marker parsers, static command ack, and default display values | Sprint `11.9` (2026-06-15) | `src/JitML/Web/Contracts.hs` now renders typed PureScript REST request envelopes, payload records/parsers for inference, generic tensor inference, image inference, checkpoint comparison, adversarial moves, training frames, RL animation/replay frames, tuning trial/sweep frames, workflow command acknowledgements, `WorkflowStatus`, and browser command envelopes. `web/src/Panels/{Mnist,GenericInference,Cifar,CheckpointCompare,Connect4,Rl,Training,Tune}.purs` consume those generated parsers/renderers instead of text markers or catch-all `data:` defaults, and training/RL/tune controls send generated daemon-compatible command envelopes instead of bare command words while rendering generated queued/running/failed/done status. `JitML.Service.Http` passes POST bodies to route handlers, and `JitML.Web.Server` publishes valid command envelopes when a live cluster publication exists while failing closed with `503` otherwise; it also accepts an injected checkpoint runtime handler for typed REST panel requests. `web/test/Main.purs` rejects the old `prediction: value=0`, `image: topK=0,1,2`, `move: 3`, and `data: placeholder` payloads. Validation: `jitml lint purescript` passed; `jitml-e2e --linux-cpu` passed 22 / 22; current-source `docs check` and `check-code` passed. |
| Demo-only inline model responses | Sprint `10.6` (2026-06-15) | Removed `renderInferenceResponse`, `renderImageResponse`, and `renderConnect4Response` from `src/JitML/Web/Server.hs` along with the inline `PolicyValueNet` / initial-board imports. Sprint `11.9` later restored `/api/inference`, `/api/images`, and `/api/connect4/move` through an injected checkpoint runtime handler that fails closed with `503 checkpoint-required` when absent. Validation: `jitml-unit --linux-cpu` passed 197 / 197, non-live `jitml-integration` passed 51 / 51, and `jitml-daemon-lifecycle --linux-cpu` passed 34 / 34. |
| Algorithm-level reward-derived projection helpers | Sprint `9.12` (2026-06-14) | Deleted the unused `JitML.RL.Algorithms.Ppo.ppoLossForRollout` helper and replaced the `jitml-rl-canonicals` all-loss validation inputs with trained PPO/DQN network outputs over real simulator rollouts. The AlphaZero policy/value loss test now trains against an MCTS-generated self-play sample instead of a fixed target row. Validation: focused `jitml-rl-canonicals --pattern=loss` passed. |
| AlphaZero placeholder arena terminal evaluator | Sprint `9.12` (2026-06-14) | Added shared `GameOutcome` / `gameOutcome` / `terminalValueForToMove` rules for Connect 4, Othello, Hex, and Gomoku, including pass-aware Othello replay, and wired `PolicyValueNet` MCTS leaf evaluation, sample outcome labeling, and `arenaWinRateAgainstUniform` through those rules. Validation: focused `jitml-rl-canonicals --pattern=terminal` passed. |
| Apple Metal-backed Kubernetes Job placement path for Training/RL/Tune commands | Sprints `5.11` / `12.12` / `16.10` / `17.7` (2026-06-13) | `JitML.Service.Workload.planWorkloadPlacement` now maps Apple Metal-backed Training/RL/Tune starts to `training.host-command.apple-silicon`, `rl.host-command.apple-silicon`, and `tune.host-command.apple-silicon` instead of Kubernetes Jobs; Linux CPU/CUDA Training/RL/Tune placement remains Job-backed. `JitML.Test.WorkflowMatrix.workflowPlacementExpectation` and `jitml-integration` assert Apple host-command/no-Job placement and Linux Job placement. Validation: focused Linux CPU live dispatch and PPO selectors passed with legal Jobs; focused Apple live Training/RL/Tune/PPO selectors passed with host-command forwarding and no workload Jobs; `bootstrap/apple-silicon.sh run-daemon --consume-once 0` acquired all host-command subscriptions; `bootstrap/apple-silicon.sh test` passed all eight report stanzas, including `jitml-integration` 71 / 71 and `jitml-backends` 17 / 17; final `kubectl get jobs -n platform` showed only platform init/backup Jobs. |
| Tart lifecycle/exec modules outside the core prerequisite path | Sprint `7.11` (2026-06-12) | Deleted `src/JitML/Tart/{Lifecycle,Exec}.hs`, removed their Cabal entries, and removed all core codegen/cache-miss callers. The Apple core path now has no VM lifecycle dependency. Validation: targeted residue search over `src/JitML/Engines`, `src/JitML/Codegen`, `src/JitML/Cache`, and `jitml.cabal` returned no `JitML.Tart` / `tartExecSubprocess` / `ensureBuildVm` / `guestSourcePath` callers; host build, unit, daemon-lifecycle, and apple-silicon backend validation passed. |
| Per-kernel generated Swift package and VM `swift build` cache-miss path | Sprint `7.11` (2026-06-12) | `GeneratedMetalPackage` / `renderMetalFamilyPackage` left the core runtime-source surface; Apple cache misses now write `./.build/jit/apple-silicon/<hash>.metal.json` source metadata and execute through `JitML.Engines.MetalBridge`. `JitML.Codegen.MlpMetal` emits MSL source metadata, and `MlpDevice` routes Metal MLP operations through fixed-bridge multi-function entrypoints. Validation: `cabal run exe:jitml -- internal install-metal-bridge` probe `ok`; `jitml test jitml-backends --apple-silicon` passed 17 / 17 through the fixed bridge, including MLP/RL/AlphaZero cases. |
| Apple per-kernel stable-dylib symlink surface | Sprint `7.11` (2026-06-12) | Deleted `src/JitML/Cache/Symlink.hs`, removed `appleSymlinkPath`, and removed Apple generated-dylib `dlopen` publication/repointing from the cache-miss path. Linux shared-object loading remains unchanged. Validation: Apple identity, weighted Dense2D, tuning, MLP, and trainer cases pass through the fixed bridge; the Apple artifact extension is `.metal.json`. |
| Tart/keychain doctrine residue in Apple validation docs and tests | Sprint `16.9` (2026-06-12) | Target docs and tests now state that the supported Apple core path uses `apple.metal-runtime` + `apple.metal-bridge`, not Tart, SwiftPM, full Xcode, offline `metal`, or keychain unlocks. The stale `test --apple-silicon` runtime error and Metal MLP "unverified" comments were updated after live validation. Historical Tart references remain explicitly dated evidence only. Validation: `bootstrap --apple-silicon` completed 84 live rollout steps; `jitml test jitml-e2e --apple-silicon` passed 20 / 20; `jitml test jitml-integration --apple-silicon --test-options '-p WorkflowMatrix'` passed 1 / 1 against the live Apple publication. |
| Daemon build-VM configuration and acquire hook | Sprint `5.10` (2026-06-12) | Removed the `buildVmCpu`, `buildVmMemoryMib`, `buildVmDiskGib`, and `buildVmIdleTimeout` fields from `src/JitML/Service/LiveConfig.hs`, `dhall/service/LiveConfig.dhall`, and `chart/templates/configmap-jitml-service.yaml`; removed the `ensureHostBuildVm` Tart lifecycle call from `src/JitML/App.hs`; added daemon startup acquisition of `apple.metal-runtime` plus the fixed `apple.metal-bridge`; and rendered `apple_metal_acquire` in `DaemonRuntime`. Validation: host `cabal build lib:jitml test:jitml-unit test:jitml-daemon-lifecycle`; host `cabal test jitml-unit jitml-daemon-lifecycle` passed 197 / 197 and 33 / 33; an Apple host fail-closed smoke with a stub Metal runtime and missing bridge exited `2`, reported `prerequisite unmet: apple.metal-bridge`, and did not invoke a temporary `tart` stub; `docker compose build jitml` passed (`check-code: ok` plus PureScript bundle); container `jitml test jitml-unit --linux-cpu` passed 197 / 197, `jitml test jitml-daemon-lifecycle --linux-cpu` passed 33 / 33, non-live `jitml-integration` passed 49 / 49, and the isolated chart regression passed 1 / 1; `docker compose run --rm jitml jitml docs check` and `git diff --check` passed. |
| Core `container.tart` prerequisite and bootstrap Tart VM cleanup | Sprint `2.12` (2026-06-12) | `src/JitML/Prerequisite/Nodes/Container.hs` removes `container.tart` from the registry and points `container.apple-silicon.jit-cache-miss` at `apple.metal-runtime` + `apple.metal-bridge`; optional `apple.swiftc` / `apple.macos-sdk` remain non-core. `bootstrap/_lib.sh` no longer invokes `tart delete` or any Tart helper during `purge`, and `JitML.Engines.MetalRuntime` no longer invokes `swift` or `xcrun -find` for the core runtime probe. `src/JitML/Cache/Layout.hs` adds the `<hash>.metal.json` Apple metadata path. Validation: `cabal build lib:jitml test:jitml-unit`; `docker compose build jitml` (`check-code: ok` plus PureScript bundle); `docker compose run --rm jitml jitml internal list-prereqs` shows the fixed-bridge nodes and no `container.tart`; static residue assertions over `bootstrap/`, `src/`, and `JitML.Engines.MetalRuntime`; `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed 197 / 197 from a clean container build directory; `docker compose run --rm jitml jitml docs check` passed; `git diff --check` passed. Sprint `7.11` later completed the generated Swift/codegen residue. |
| `jitml internal vm` command group and generated CLI mirrors | Sprint `1.15` (2026-06-12) | Removed the `internal vm create/up/down/status/delete/exec` leaves from `src/JitML/CLI/Spec.hs`, deleted their `src/JitML/App.hs` dispatch handlers, regenerated README command regions, `documents/cli/commands.md`, `documents/engineering/cli_command_surface.md`, manpage, and bash/zsh/fish completions, and updated the parser/canonical-leaf unit surface. Validation: `cabal run exe:jitml -- docs generate`; `docker compose build jitml` passed including in-image `jitml check-code`; `docker compose run --rm jitml jitml docs check`; command-tree assertion confirmed no `internal vm` leaf and retained `internal list-prereqs`; `docker compose run --rm jitml jitml test jitml-unit --linux-cpu` passed 196 / 196. |
| Vacuous-pass integration `-p Live` asserts + model-less e2e asserts | Sprint `12.11` (2026-06-12) | `JitML.Test.WorkflowMatrix` is the DRY enumeration of the eight reopened workflows × every substrate, each with its canonical command. `test/integration/Main.hs` now has a `Live` case that loads the current publication, filters to the current substrate, stages the required dataset/checkpoint state, and runs every command through the freshly built `jitml` executable; without a publication it fails closed. `test/e2e/Main.hs` intentionally owns structural workflow × substrate coverage plus the typed live e2e plan, not duplicate matrix command execution. The AlphaZero cell runs the canonical `jitml rl alphazero self-play` CLI leaf. Validated: non-live `jitml-integration -p !/Live/` **49 / 49**, `jitml-e2e` **20 / 20**, `docs check: ok`, `check-code: ok`, and live `linux-cpu` `jitml-integration -p WorkflowMatrix` **1 / 1** after the bootstrap/edge fixes. The remaining Apple live run is a primary Phase `16` obligation, not a ledger row. |
| Demo endpoint `/api/images` placeholder and live-cluster round-trip residue | Sprint `11.8` / Phase `15` (2026-06-11) | At Sprint `11.8` closure, `src/JitML/Web/Server.hs` routed `/api/images` to `renderImageResponse`, which returned the policy-network top-k vector rather than an upload acknowledgement. Sprint `10.6` later removed that inline response function, and Sprint `11.9` replaced the fail-closed route with an injected checkpoint runtime handler for typed browser image requests. After `docker compose build jitml` passed `check-code: ok` and rebuilt the PureScript bundle, `jitml:local` and `jitml-demo:local` were loaded into the `linux-cuda` Kind cluster, `jitml-service` / `jitml-demo` were rollout-restarted, and the Playwright Docker image passed **9 / 9** against the published edge. |
| DOM-only Playwright panel assertions | Sprint `11.8` / Phase `15` (2026-06-11) | `playwright/jitml-demo.spec.ts` now clicks the MNIST, CIFAR/ImageNet, and Connect 4 controls, waits for `POST /api/inference`, `POST /api/images`, and `POST /api/connect4/move`, and asserts rendered value updates instead of only panel visibility. The live CUDA edge run passed **9 / 9**, and `docker compose run --rm jitml-cuda jitml test jitml-e2e --linux-cuda` passed **20 / 20** after the same rebuild. |
| PureScript panel no-fetch / raw-stream cleanup | Sprint `11.8` (2026-06-11) | Added `web/src/Panels/Api.{purs,js}` for real text requests, wired MNIST / CIFAR / Connect4 button actions to `/api/inference`, `/api/images`, and `/api/connect4/move`, removed raw `LiveFrame String` storage from the RL/training/tune panels, and changed `web/src/Panels/Stream.js` to report WebSocket errors through typed actions instead of swallowing them. Validated with `docker compose run --rm jitml jitml lint purescript` (`ok`). |
| `inferFromManifest` faithful read and default manifest-only inference helpers | Sprint `10.5` (2026-06-11) | Deleted `inferFromManifest` from `src/JitML/Checkpoint/Format.hs`; removed `Checkpoint.Store`'s default `inferFromLatestCheckpoint`, `inferWeightsOnlyFromLatestCheckpoint`, and `loadInferenceCheckpoint` wrappers; changed `Service.Workload` default inference to fail closed with `weighted inference runner required`; and kept only explicit injected-runner / weighted APIs (`loadInferenceCheckpointWith`, `loadInferenceCheckpointWithWeights`). Validated in the container: `jitml test jitml-unit --linux-cpu` 196 / 196, `jitml test jitml-daemon-lifecycle --linux-cpu` 31 / 31, and focused offline `jitml-integration` cases for `loadInferenceCheckpointWithWeights` and HasMinIO conditional checkpoint writes passed. |
| Synthetic SL final loss + convergence curve (`finalLoss` / `convergenceCurve` / `baseLoss`) and dead deterministic SL pipeline (`SL.Train` / `SL.Loop`) | Sprint `8.10` (2026-06-11) | Removed the closed-form geometric loss helpers from `src/JitML/SL/Canonicals.hs`, deleted `src/JitML/SL/Train.hs` and `src/JitML/SL/Loop.hs`, removed them from `jitml.cabal`, and rewired `jitml-sl-canonicals` away from deterministic-curve assertions to the canonical catalog, Dense-MLP device-trainable cohort, classifier, and report-card knob checks. The published training path already routes through `runDeviceMnistTraining` and `trainClassifierWithDevice`. |
| `rl rollout` `deterministicTrajectory` production LCG helper | Sprint `9.9` (2026-06-11) | Removed `deterministicTrajectory` from `src/JitML/RL/Algorithms.hs` and changed the canonical PPO rollout determinism test to use the registered `moduleRolloutGenerator` over `JitML.RL.Algorithms.Common.trajectoryRollout`, which steps real named environment dynamics. The CLI `rl rollout` already runs `runDeviceRollout` through the selected substrate device and fails closed when unavailable. |
| `trajectoryRollout` / `moduleRolloutGenerator` LCG rollout registry | Sprint `9.9` (2026-06-11) | `JitML.RL.Algorithms.Common.trajectoryRollout` (the generator every algorithm module registers) now steps the **real** named environment dynamics via `JitML.RL.SimulatorLoop.realRolloutByName` for the rollout horizon with a deterministic seeded policy, returning the real per-step actions + rewards — replacing the shared per-algorithm LCG. Deterministic given the seed. Host lib type-checks; the `jitml-rl-canonicals` per-algorithm rollout cases (determinism + non-empty rewards) hold under real env dynamics. Phase 15 later validated the substrate-device-backed trained-policy rollout through the linux-cpu/linux-cuda live lanes. |
| Per-trainer mid-run pure device fallback (`dqnUpdateDevice` and peers) | Sprint `8.11` (2026-06-11) | The four device updaters (`DqnTrainer` / `QrDqnTrainer` / `ContinuousTrainer` / `HerTrainer`) no longer silently fall back to the pure update on a mid-run device `Left` — they fail closed with a descriptive error. The dispatch-level `probeMlpDevice` gate confirms the kernel runs before training, so the branch is unreachable in practice; removing it leaves no pure-Haskell fallback on any runtime path. Host lib type-checks; container `check-code` validated. |
| AlphaZero one-ply MCTS bandit + dead `Arena` / `EnginePrior`, and the `Tune.deterministicTrials` LCG objective | Sprints `9.10` / `9.11` (2026-06-10 / extended 2026-06-11) | `src/JitML/RL/AlphaZero/Mcts.hs` is rewritten as a real recursive tree search: each simulation descends from the root by PUCT to an unexpanded leaf, expands it with the position's network priors, evaluates the leaf through the network __value head__, and backs the value up the path with the adversarial sign flip (depth-bounded). The `PriorOracle` is now position-aware (`[Int] -> NodeEval`), with `PriorOracleIO` / `runSearchWithPriorIO` for substrate-backed leaf evaluation; `PolicyValueNet.netOracleFactory` roots the pure path at the search position, and `mctsVisitDistributionWithDevice` runs leaf policy/value forwards through the selected JIT `MlpDevice`. `src/JitML/RL/AlphaZero/Arena.hs` and `EnginePrior.hs` (dead modules) are deleted and dropped from the cabal. `Tune.deterministicTrials` now returns __real measured objectives__ by training the reference classifier with the sampled hyperparameters and returning train accuracy for the worked example's `valAcc:Maximise` direction; `Tune.deterministicTrialsWithDevice` runs the same trial stream through `trainClassifierWithDevice`, not a per-sampler LCG. **Verified working**: host `jitml-unit` 196/196 (migrated MCTS oracle case); linux-cpu `jitml-rl-canonicals` 28/28 (including device-backed MCTS leaf evaluation); linux-cpu `jitml-hyperparameter` 15/15 (including device-backed trial execution); earlier container `check-code: ok`. |
| SL/RL synthetic CLI surfaces — `final_loss` print + `fromMaybe (SL.finalLoss …)` publish, `attemptRealMnistTraining` / `attemptFetchTrainingDataset` Maybe-fallback, `runEval` echo stub, and the `"simulator"` scripted non-learning default trainer | Sprints `8.10` / `8.11` (2026-06-10) | `src/JitML/App.hs` `runTrain` now delegates to `runDeviceMnistTraining` (mandatory live publication + staged dataset + `JitML.SL.Classifier.trainClassifierWithDevice` through `mlpDeviceForSubstrate`, fail-closed `TrainingPrerequisiteUnmet`); `runEval` runs the substrate weighted device forward (missing checkpoint → `InferenceCheckpointMissing`); `runRl` defaults the trainer to `ppo` and dispatches every MLP-backed trainer through `rlDeviceForSubstrate` behind a fail-closed `probeMlpDevice` gate (unknown trainer → `InvalidConfig`). **Verified working** in `jitml:local`: `check-code: ok`, `jitml test jitml-sl-canonicals --linux-cpu` 15 / 15 (device-convergence case `OK (0.75s)` ran the real oneDNN kernel after residual SL helper deletion), `jitml test jitml-rl-canonicals --linux-cpu` 27 / 27 (on-device PPO case `OK (0.75s)` after production rollout-LCG deletion); host `jitml-unit` 196 / 196 and the `jitml-integration` offline-`jitml train` fail-closed assertion pass. ARS remains the lone no-MLP exception. |
| Host `swift build` for the Apple glue dylib | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/Engine.hs` `compileSubprocess` `AppleSilicon` now dispatches `swift build` into the `jitml`-managed Tart VM via `tartExecSubprocess` against the shared-mount `guestSourcePath`. Verified working: the live apple-silicon lane built each Metal kernel family in the VM (Xcode 16 `swift-build`) and the host executed the copied-out dylib (`jitml test jitml-backends --apple-silicon`, 17 / 17). |
| Host-side artifact read | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/Loader.hs` `publishAppleArtifact` copies `libJitMLMetal.dylib` **out of the VM's** `.build/release/` (host-visible via the shared mount) into the content-addressed cache (atomic `tmp + rename`) and repoints the stable FFI symlink. Verified by the live lane's first cache-miss case (39.55s) producing a working host dylib. |
| Host-based Metal toolchain fingerprint | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/MetalLocal.hs` `metalToolchainFingerprint` keys on `metal-build-vm-runtime-makelibrary` (VM-based) rather than the host toolchain. |
| Host `swiftc`/`metal` requirement in the runtime probe | Sprint `7.10` (2026-06-10) | `src/JitML/Engines/MetalRuntime.hs` `metalRuntimeAvailable` gates on a visible host Metal device only (no host `swiftc`/`metal`). The `jitml test --apple-silicon` device-only precondition probe passed on Apple M1, and `jitml-unit`'s Metal-probe regression (device-visible + no host toolchain ⇒ available) is green. |
| `container.apple-silicon.jit-cache-miss` → `container.tart` dependency | Sprint `2.11` (2026-06-10) | `src/JitML/Prerequisite/Nodes/Container.hs` cache-miss node depends on the reinstated `container.tart` node + VM lifecycle (the `container.tart` closure flip is unit-validated and the live VM lifecycle ran for the apple-silicon lane). |
| Delete-only Tart cleanup | Sprint `2.11` (2026-06-10) | `bootstrap/_lib.sh` `purge_state` performs the full Tart VM lifecycle (create/start/stop/delete) rather than a delete-only residue. |
| Test skip-antipattern guards — `linux-cuda` half re-validation | Sprint `15.16` (2026-06-09) | The skip branches (`probeCudaRuntime` / `cudaRuntimeAvailable`, `appleLiveReady`, `cublasBindingsCompiledIn` / `cudnnBindingsCompiledIn`) and the integration-probe oneDNN-availability assertion were deleted from `test/cross-backend/Main.hs` and `test/integration/Main.hs` on 2026-06-08/09; a missing toolchain now fails by design. The final gate — the live `linux-cuda` re-run on real NVIDIA hardware — landed 2026-06-09 on the NVIDIA GeForce RTX 5090 host (UUID `GPU-e764ef97-32d7-4981-c348-029983c64073`) via the GPU-attached `jitml-cuda` compose service: `docker compose run --rm jitml-cuda cabal test -fcuda jitml-cross-backend --test-options '-p linux-cuda'` passed **19 / 19 (12.26s, no skip-sentinels)**, every within-substrate CUDA case a real device PASS (`nvidia-smi -L` reported the matching RTX 5090). With the guards removed, a build without `-fcuda` would hard-FAIL the cuBLAS / cuDNN cases rather than skip them. This was the last open Pending Removal row; with it closed the ledger is empty and Exit Definition item 18 is met. |
| Cross-substrate per-layer-family tolerance band | Sprint `17.4` (2026-06-09) | `src/JitML/Engines/Tolerance.hs` deleted and removed from `jitml.cabal`. Cross-substrate numeric parity left the contract (within-substrate bit-for-bit only; cross-substrate equivalence is not asserted). Validation: project + all test stanzas compile/link clean host-native and under the in-container `-fcuda` library build; container `jitml check-code` and `jitml docs check` green. |
| Cross-substrate parity cohort / drift / report-bundle module | Sprint `17.4` (2026-06-09) | `src/JitML/CrossBackend/Parity.hs` deleted and removed from `jitml.cabal`; the last consumers (`App.hs` `measureCrossSubstrateParity`, the cross-backend `CrossSubstrate` group) were removed in the same change. Validation: `jitml check-code` + `jitml docs check` green; `jitml-unit` 193 / 193. |
| `jitml verify cross-backend` CLI command | Sprint `1.13` (2026-06-09) | The `verify` → `cross-backend` leaf removed from `src/JitML/CLI/Spec.hs` and `runVerifyCrossBackend` + helpers removed from `src/JitML/App.hs`. `jitml docs generate` regenerated the README registry/tree, `documents/cli/commands.md`, `documents/engineering/cli_command_surface.md`, the manpage, and the bash/zsh/fish completions with no `verify cross-backend` leaf. Validation: `jitml docs check` (host + container) and container `jitml check-code` green; `jitml-unit` 193 / 193 (leaf-path enumeration drops the leaf). |
| Report-card `cross_substrate_parity` field | Sprint `12.10` (2026-06-09) | `measuredCrossSubstrateParity` removed from `ReportMeasurements` (`src/JitML/Test/Report.hs`) and `measureCrossSubstrateParity` plus its call site removed from `src/JitML/App.hs`. The `jitml test all --live` report card no longer renders a `cross_substrate_parity` line. Validation: `jitml-unit` 193 / 193; container `jitml check-code` green; the `apple-silicon` (4 / 4) and `linux-cpu` (10 / 10) report cards render without the field. |
| `CrossSubstrate` weighted-drift test group + cross-substrate tolerance-band unit test group | Sprint `12.10` (2026-06-09) | The `CrossSubstrate weighted drift assertions` group removed from `test/cross-backend/Main.hs`; the `Cross-substrate tolerance bands` group removed from `test/unit/Main.hs`; the two substrate-agnostic cross-backend cases relocated into the `jitml-unit` `Backend-agnostic engine + manifest invariants` group. Validation: `jitml-unit` 193 / 193 (incl. the relocated group); `apple-silicon` lane 4 / 4 and `linux-cpu` lane 10 / 10 each select only their substrate's cases with no skip-sentinels. |
| MNIST as default empty-hash landing; absent SPA discoverability for Envoy-routed admin portals | Reopened Phase 11 Sprint `11.7` (2026-06-05) | `src/JitML/Routes.hs` now carries `routeAdminPortalLabel` metadata and `adminPortalRoutes` for the six Envoy-routed admin portals. `src/JitML/Web/AdminPortals.hs` renders the tracked `web/src/Generated/AdminPortals.purs` artifact. `web/src/Chrome/Header.purs`, `web/src/PanelRegistry.purs`, and `web/src/Panels/Portals.purs` add the shared header, SPA-side panel registry, and default portals home. `web/src/Main.purs` routes empty / unmatched hashes to the portals home and runs the previous Halogen disposer before mounting a new hash route. Existing panels prepend `Chrome.Header.render`; `web/test/Main.purs` covers the generated portal array; live Playwright covers the empty-hash home, admin-portal hrefs, shared header across panels, and six panel hashes. Validation: `docker compose build jitml`, `jitml docs check`, `jitml-unit`, `jitml-integration`, `spago test`, `jitml check-code`, Apple Silicon `./bootstrap/apple-silicon.sh up` + `run-daemon`, and live Playwright 9 / 9 against `127.0.0.1:9091` pass. |
| Missing CLI Dhall overrides on `train`, `rl train`, `tune` | Reopened Phase 1 Sprint `1.12` (2026-06-04) | `src/JitML/CLI/Spec.hs` now accepts `--substrate` / `--seed` on `trainCommand` and the `rl train` subcommand, and `--sampler` / `--scheduler` / `--pruner` / `--trials` / `--parallelism` on `tuneCommand`. Values resolve through the pure `JitML.Experiment.Overrides.applyOverrides` (new module `src/JitML/Experiment/Overrides.hs`) before validation, substituting on the named axis only per README pillar 2. The substrate parser at `src/JitML/Substrate.hs` rejects bare `cpu` / `cuda` aliases; the canonical identifiers `apple-silicon` / `linux-cpu` / `linux-cuda` are the only accepted forms. `jitml docs generate` regenerated the README registry/tree blocks, `documents/cli/commands.md`, the `cli-commands.help-blocks` and `cli-commands.reference` sections in `documents/engineering/cli_command_surface.md`, `share/man/man1/jitml.1`, and the bash/zsh/fish completions. The two stale README example forms (`inspect frontier --tuning-run/--pareto`, `--backends cpu,cuda`) were repaired in the same change. Validation: `jitml docs check` exits 0; 195/195 `jitml-unit` (11 new Sprint 1.12 cases); 14/14 `jitml-hyperparameter` (2 new cases including the catalog round-trip and pillar-2 axis-only substitution); the `jitml-integration` spawned-binary matrix exercises `train`/`tune` override summaries and rejects bare `--substrate cpu`; the container `jitml check-code` gate passes. |
| Tart VM build/lifecycle/exec modules, `jitml internal vm` command group, `container.tart` prerequisite, `LiveConfig.tartIdleTimeout`, and the offline `.metallib` codegen path | Sprints `7.8` + `2.10` + `5.8` (2026-05-30) | The headless Apple Metal JIT (host CommandLineTools `swift build` + runtime `MTLDevice.makeLibrary(source:)`, validated headless on Apple M1) superseded the Tart-VM build. Deleted `src/JitML/Tart/{Build,Lifecycle,Exec}.hs`; removed the `jitml internal vm bootstrap\|up\|down\|status\|exec` command group from `CommandSpec` + `App.hs` handlers (commands.md/man/completions regenerated); removed the `container.tart` prerequisite node + its `jit-cache-miss` dependency; removed `LiveConfig.tartIdleTimeout` from the Dhall schema + Haskell record + `daemon.surface` table; dropped the `.process("Kernels.metal")` resource, the `<hash>.metallib` publication, and the `JITML_METALLIB_PATH` env hand-off. `cabal build all` clean; 183 `jitml-unit` + 30 `jitml-daemon-lifecycle` + the Apple `jitml-cross-backend` cases pass. |
| Lint-time host `ghcup` style-tool bootstrap | Sprint 1.4 | Removed runtime `ensureStyleTools` / `installStyleToolsSubprocess` bootstrap from `src/JitML/Lint/Stack.hs`; `docker/Dockerfile` now builds pinned `fourmolu` / `hlint` with the same image-local GHC `9.12.4`, stamps the `jitml:local` code-quality domain, and runs `jitml check-code` during image construction. |
| Scoped `allow-newer` for Dhall / CBOR / lens-family transitive package bounds | Sprint `1.10` (2026-06-04) | Removed the `allow-newer` stanza from `cabal.project`. The temporary source-pin/vendor replacement used to keep the package set solving was removed by Sprint `1.11`; the current `cabal.project` solves from plain Hackage under GHC `9.12.4`. |
| Dependency source-pin/vendor helper for the GHC `9.12.4` downgrade | Sprint `1.11` / Phase `17` Sprint `17.3` (2026-06-04) | Removed the upstream `cborg` / `dhall-haskell` source-repository pins from `cabal.project`, deleted the local `third_party/haskell/lens-family-*` packages, and changed the package baseline to GHC `9.12.4` / `base-4.21`. Plain Hackage now solves for `serialise`, `cborg`, `dhall`, and `lens-family`; the helper no longer gates final handoff. |
| Reopened-phase development ledger | Sprint `1.11` / Phase `17` Sprint `17.3` (2026-06-04) | Deleted the superseded development ledger and folded reopened-phase status back into the owning phase documents and the top-level plan. The deletion ledger remains the only explicit legacy ledger. |
| Deprecated PureScript generic `runSpec` Node runner alias | Reopened Phase `11` Sprint `11.3` (2026-06-04) | Replaced `Test.Spec.Runner.runSpec` plus `launchAff_` in `web/test/Main.purs` with `Test.Spec.Runner.Node.runSpecAndExitProcess`, added `spec-node` to `web/spago.yaml`, ignored the runner's `.spec-results` state in `web/.gitignore`, and validated `docker compose run --rm jitml sh -lc 'cd web && spago test'` at 7 / 7 with zero PureScript warnings. |
| `jitml-mirror` Helm release placeholder | Sprint 3.5 | Removed the stand-in `HelmRelease "jitml-mirror" "jitml-images"` row from `JitML.Cluster.Helm.phasedReleases`; `JitML.Bootstrap.livePhasedRolloutSubprocesses` now inserts the Docker build / explicit Kind image-load subprocesses directly before final services. |
| Static JIT source/build scaffolds | Sprint 7.7 | Removed checked-in substrate build scripts and kernel source scaffolds; Haskell renderers emit compiler inputs under `./.build/jit-src/<substrate>/<hash>/`. The static-source lint rejects future native compiler inputs and adapter shims; there is no checked-in foreign-source allowlist. |
| Default runtime-source placeholder | Sprint 7.7 | Removed `defaultRuntimeSourcePayload` and the `runtime-source:phase-2-placeholder` marker from `src/JitML/Cache/Key.hs`; cache-key snapshot now derives its `RuntimeSourcePayload` from `renderRuntimeSource`, and `test/snapshots/cache/kernel-key.txt` was refreshed to the rendered-source-backed hash. |
| Deterministic atari-subset RAM-state stub | Reopened Phase 8 Sprint `8.8` (2026-06-04) | Removed the deterministic 128-byte RAM-state production stand-in from `src/JitML/RL/Simulator.hs` and routed `atari-subset` through `JitML.RL.ALE` with typed `RunConfig.atariRomPath`, explicit `JITML_ATARI_ROM` / `JITML_ALE_ROM` fallbacks, ignored `./.roms/` local ROM storage, and a fail-closed no-ROM diagnostic. The checked-in C++ adapter used during the first ALE validation was later removed by the static-foreign-source correction below. ROM-backed ALE smoke is optional/manual and was not part of required validation. |
| Checked-in ALE C++ shim and lint exception | Static-foreign-source correction (2026-06-04) | Deleted `csrc/jitml_ale_shim.cpp`, removed the Dockerfile compile step that produced `/usr/local/lib/libjitml_ale_shim.so` from checked-in source, removed the one-file `src/JitML/Lint/Stack.hs` allowlist, and updated `src/JitML/RL/ALE.hs` to describe a generated or externally supplied runtime shim. The repository now has no checked-in C/C++ ALE adapter source; any future project-owned adapter must be generated by Haskell into the build/cache tree. Validation: `docker compose run --rm jitml jitml check-code` passes after this correction. |
| Standalone MinIO values fragment | Sprint 4.3 | Folded MinIO subchart values into `chart/values.yaml`, removed `chart/minio-values.yaml`, and made bootstrap delete legacy standalone values files during materialization. |
| RL run sequencing as a `RunPhase` enum instead of an `RLRunLifecycle` GADT | Sprint 8.7 | Replaced the flat `RunPhase` enum with the `RLRunPhase` data kind plus the phase-indexed singleton GADT `RLRunLifecycle` in `src/JitML/RL/Framework.hs`; updated `rlRunPlan`, `renderRLRunPhase`, and the `jitml-unit` consumer; `cabal test jitml-unit` keeps 57/57 passing. |
| Non-production Metal kernel-family scaffolds | Phase 16 Sprint `16.5` / Phase 17 validation sweep (2026-06-03) | Apple-side per-family weighted Metal bodies now run through the headless host path: CommandLineTools `swift build`, runtime `MTLDevice.makeLibrary(source:)`, no Tart VM and no full Xcode. The Apple export `jitml verify cross-backend --experiment experiments/mnist.dhall --backends apple-silicon --export /tmp/jitml-apple.json` produced the Sprint `17.1` weighted bundle with 8 tensor families (`identity`, `dense`, `conv2d`, `conv3d`, `batchnorm`, `layernorm`, `mha`, `embedding`), and the 2026-06-03 Linux/Apple report-bundle comparison passed every weighted family against the in-code tolerance table. |
| Deterministic MCTS prior stub | Phase 17 Sprint `17.3` cleanup (2026-06-03) | Removed `priorFor` from `JitML.RL.AlphaZero.Mcts`. `defaultPriorOracle` is now a neutral uniform mechanics oracle; production self-play and engine-backed paths continue to consume the position-dependent policy/value `netOracleFactory`. Unit coverage now asserts neutral default priors separately from a biased custom oracle. |
| Target-stanza-only report card | Phase 17 Sprint `17.2` implementation (2026-06-03 / validated 2026-06-04) | `JitML.Test.Report.ReportCard` now carries typed `ReportMeasurements`, and `jitml test all --live` appends SL/RL/AlphaZero/tune/cache/daemon/cross-substrate fields after Cabal stanzas pass. Unreachable live sources render as `unavailable`; parser/e2e coverage and generated CLI docs/manpage were updated. The 2026-06-04 fresh Apple live aggregate passed all eight report stanzas and captured populated measured fields for RL reward, AlphaZero win rate, tuning objective, JIT cache hit rate, and daemon health. |
| Numerical-content golden fixtures under `test/golden/` | Phase 17 Sprint `17.3` cleanup (2026-06-03) | Deleted the committed numerical fixture tree under `test/golden/{sl,rl,alphazero,tune}` and moved pure renderer snapshots to `test/snapshots/{cache,cli,cluster,observability,prerequisite}/`. SL/RL/AlphaZero/tune tests now assert run-to-run determinism, finite/non-empty summaries, and property invariants instead of golden numeric files; `forbiddenPathRegistry` rejects `test/golden/`. |
| Demo placeholder shell, local stream frames, and inline DOM stubs | Phase 17 Sprint `17.3` cleanup (2026-06-04) | Removed Playwright's inline DOM fallback; `playwright/jitml-demo.spec.ts` now requires live `cluster-publication.json` and drives the real browser bundle through the published edge route. `JitML.Web.Server` no longer renders the placeholder manifest shell, no longer serves deterministic `/api/ws*` HTTP frames, serves only the browser-loadable `web/dist/Main/bundle.js`, returns `503` for plain HTTP stream GETs that lack a WebSocket upgrade, and emits a terminal error frame when no live publication exists. `JitML.Service.Http` now forks one worker per accepted connection so held-open stream sockets do not block HTTP/bundle routes. Validation: `jitml-e2e` passed 19 / 19, `jitml check-code` passed, `jitml:local` rebuilt, `jitml-demo:local` was loaded into the live Apple Silicon Kind cluster, and the live Playwright matrix passed 7 / 7 against `127.0.0.1:9091`. |
| `JITML_*` run-parameter env-var IPC | Sprint `5.7` (closed 2026-05-29) | The daemon round-tripped typed run records (`StartTraining` / `StartSweep` / `StartRLRun`) through ~20 stringly-typed `JITML_*` Job env vars. Sprint `5.7` introduced typed `dhall/run/Schema.dhall` + `JitML.Service.RunConfig` and changed `JitML.Service.Workload.renderTrainingJob` / `renderTuneJob` / `renderRlJob` to emit a per-run ConfigMap + Job pair: the Job mounts `RunConfig.dhall` at `/etc/jitml/run/`. The worker (`JitML.App.runRl` / `runTune` / `attemptRealMnistTraining`) loads the typed config via `RunConfig.tryLoad{Rl,Tune,Training}RunConfig`, falling back to the legacy env vars for developer-side CLI runs outside a Job pod. Application Environment doctrine alignment. |
| Duplicate `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env reads vs `BootConfig` | Sprint `5.7` (closed 2026-05-29) | `JitML.App.workerBrokerTarget` now mounts the shared `jitml-service-config` ConfigMap at `/etc/jitml/service/`, loads `BootConfig.dhall` for the substrate, and reads the Pulsar WebSocket URL from any mounted `RunConfig.dhall` variant. The legacy `JITML_SUBSTRATE` / `JITML_PULSAR_WS` env reads survive only as the developer-side CLI fallback. |
| Embedded `sh -c` retry/poll/existence control-flow (reconciler + readiness halves) | Sprints `2.9` + `4.8` (closed 2026-05-29) | Sprint `2.9` retired the reconciler half: `JitML.Cluster.Helm.kindCreateSubprocess` / `kindDeleteSubprocess` / `helmDependencyBuildSubprocess` became typed single-command subprocesses, and the postgres schema grant moved to typed Haskell IO in `JitML.Bootstrap.postgresSchemaGrantIO` (typed `kubectl` capture + typed `psql` exec). Sprint `4.8` retired the readiness half: `JitML.Cluster.Readiness.runMinioBucketReadinessIO` + `JitML.Cluster.PulsarBootstrap.runPulsarTopicCreatesIO` perform bounded retries in Haskell over typed leaf `kubectl exec ... mc` / `... pulsar-admin` subprocesses; the final-gate `minioBucketReadinessSubprocess` is a typed single command using the `MC_HOST_jitml-minio` env hand-off. `JitML.Bootstrap.liveExecutePhasedRollout` runs all four IO steps (minio buckets / postgres grants / pulsar topics) between the typed subprocess phases. |
| Pulumi ephemeral-Kind orchestrator + `toolchain.pulumi` prerequisite | Pulumi-removal cleanup (2026-05-28) | Pulumi was added in error — the project needs no external IaC orchestrator. Removed completely: deleted `infra/pulumi/` (`index.ts`, `package.json`, `Pulumi.yaml`); rewrote `JitML.Test.LivePlan.liveE2EPlan` to the Pulumi-free sequence `helm dependency build chart` → `jitml bootstrap` → `npx playwright test` → `jitml cluster down`; removed the `toolchain.pulumi` prerequisite node and its unit tests; deleted the Pulumi-only `JitML.Cluster.Kind.kindConfigForNamed` / `kindConfigForEdgePortNamed` and the `jitml internal render-kind-config` CLI command (the renderer uses the substrate-default cluster name); dropped the `infra/pulumi/node_modules/` lint-skip entry. Renamed the doctrine test category "Pulumi-Orchestrated Infrastructure" → "Ephemeral-Cluster Infrastructure" across the project README, `DEVELOPMENT_PLAN/`, and `documents/engineering/`. The ephemeral-cluster e2e orchestration is now the `jitml bootstrap` + `jitml cluster down` path (Sprints 15.1 / 15.14). |

## Related Documents

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md)
- [../README.md](../README.md)
