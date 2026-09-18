# Phase 276: Journal-Derived Product Aggregation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Journal-Derived Product Aggregation. Single-session phase migrated from legacy Sprint 31.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

🔄 **Active** (2026-09-18 UTC; session paused). Phases `261`, `268`, and `273` have retained
and admitted their exact typed lane journals. All prerequisites are Done; this
phase consumes those three inputs on `linux-cpu` without an accelerator rerun.
The implementation and several gates pass, but the current full integration
invocation has encountered a convergence failure. No closure is claimed.

## Sprint 276.1: Journal-Derived Product Aggregation [🔄 Active]

**Status**: Active
**Implementation**: `src/JitML/Test/ProductAggregation.hs`,
`src/JitML/Test/ProductLaneJournal.hs`, `src/JitML/Test/Report.hs`,
`test/unit/ProductAggregation.hs`, `test/integration/Main.hs`,
`DEVELOPMENT_PLAN/attestations/product-aggregate.json`
**Docs to update**: `../README.md`,
`../documents/engineering/product_completion_contract.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/run_contract.md`, `system-components.md`

### Objective

Join the three committed lane journals into one product result without
reconstructing evidence from prose, test ids, or post-hoc probes. This sprint
owns the aggregation portion of
[Exit Definition](README.md#exit-definition) item `34`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Decode and validate each committed lane fragment as a versioned scenario
  journal whose rows carry matching `rowId`, `PlanId`, opaque Store-admitted
  artifact identity, substrate, and completed evidence.
- Join the three fragments by product-row identity and fail on missing,
  duplicated, mismatched, failed, or not-run cells.
- Derive all aggregate counts and report measurements from the joined typed
  results; no prose table or hand-edited total can manufacture coverage.
- Keep aggregation `linux-cpu` only and consume the committed accelerator
  fragments without rerunning either accelerator.
- Emit the merged report and closure input consumed by the external-truth and
  status-governance phases.

### Validation

The full integration stanza requires the real `linux-cpu` cluster. Build the
current source image, run `./bootstrap/linux-cpu.sh up`, and verify the twelve
canonical dataset objects through the published edge (upload any missing pinned
artifacts with `jitml internal upload-dataset`). Run unit and integration
against that ready publication. Record cluster health and retain this shared
CPU cluster for the following CPU phases; `./bootstrap/linux-cpu.sh down`
releases it when the live validation work ends. Retained accelerator
journals are read as evidence; no accelerator command is executed.

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-e2e --linux-cpu
docker compose run --rm jitml jitml test jitml-negative-controls --linux-cpu
docker compose run --rm jitml jitml test jitml-model-convergence --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Current Implementation

- `ProductAggregation` admits the three externally pinned portable journals
  against the registered path and SHA-256 pin and the complete current
  projection for each lane, then joins by row ID
  in canonical product order. Each opaque aggregate row contains exactly one
  CPU, CUDA, and Apple cell; lane-specific PlanIds remain distinct.
- The version-`1` aggregate retains source pins/run IDs, plan and admitted
  checkpoint identities, device witnesses, completion/measurement digests,
  refined completion payloads, measured counters, and convergence observations.
  Its counts and measurements are projections of admitted evidence.
- A retained aggregate is admitted only by recomputing its exact bytes from
  the pinned lane inputs. Markdown fragments remain presentation-only; their
  old freely constructible DTO and parsing/join APIs are removed.
- Unit negative fixtures cover missing/duplicate lanes and rows, row order,
  identity/substrate/manifest/contract/invocation drift, failed/not-run rows,
  malformed completion, unknown schema fields/versions, digest/canonicalization
  drift, and altered aggregate counts and source bindings. Integration reads
  the retained aggregate through the production admission path.

### Current Validation State

- The first container build compiled the new library and unit-test modules,
  then exited `1`: the live fragment comparator still imported the removed
  Markdown input-path list. The presentation-only list is retained as
  `productLaneFragmentPaths`; the prose DTO and aggregation API remain removed.
  The corrected build and focused tests subsequently passed, as recorded below.
- The first formatter invocation exited `1` because the container's pinned
  formatter is under `/opt/jitml-style-tools/bin`, outside the default PATH.
  A direct retry then exited `102` because it omitted the project
  formatter's `--no-cabal`/`-XGHC2024` options. Formatting now uses the
  supported container `jitml lint haskell --write` command. The tool already
  exists in the image; no host installation is needed. The supported
  `docker compose run --rm jitml jitml lint haskell --write` gate then exited
  `0`, with formatting, HLint, and Cabal formatting accepted.

- The corrected library build and first production generation/read-back exited
  `0`: **55** product rows, **3** lanes, **165** completed cells. The canonical
  `attestations/product-aggregate.json` is **532,989 bytes**, SHA-256
  `9ab0bbbfdcb8ebb98f255c386ec314252c6e521d240b42e7471e704f285a7396`.
  The subsequent aggregate authority check requires the registered path and
  pin; callers cannot substitute their own digest. The focused
  `jitml test jitml-unit --linux-cpu --test-options='-p "Journal-derived product aggregation"'`
  gate exited `0`, **39 / 39** tests in **0.83 s**. The full CPU unit retry
  subsequently passed; live integration and final closure checks remain open.
- The first full CPU unit gate exited `1`: **4 / 946** cases failed while
  mirroring artifacts to the retained Apple publication at `127.0.0.1:9090`
  after its cluster had been torn down. The original stdout/stderr and terminal
  result are retained as `jitml-unit.*`; the subsequent full unit retry passed
  against the real CPU bootstrap's ready endpoint, as recorded below. No phase closure is
  claimed from that failed invocation.

- The corrected integration, e2e, negative-control, and model-convergence
  executables build successfully. The updated docs check, focused HLint check,
  and rule-M scan pass: **0** backward edges, missing gates, dual-accelerator
  gates, or accelerator invocations in the **20** aggregation validation blocks.

- The secondary CPU gates exited `0`: e2e **27 / 27**, negative controls
  **3 / 3**, and model convergence **111 / 111**. The three retired e2e
  prose-aggregation tests are replaced by the **39-case** typed admission group
  and the standing integration reader. Separate transcripts and exit files are
  retained under `.build/phase276-20260917/secondary-gates/`.

- Container `docker compose run --rm jitml jitml check-code` exited `0`
  before bootstrap (**153.99 s**). All **12** local canonical dataset artifacts
  (**629,581,277 bytes**) match their pinned sizes and SHA-256 digests; their
  live published inventory is verified after CPU bootstrap.

- The source image build exited `0`, including its embedded `check-code` and
  browser bundle build. The immutable image is
  `sha256:42475ed9bcdd818f0639045ecfba33505a3bd65f916f224c322e2440237f60da`;
  **311** runtime source/build inputs match the worktree with **0** mismatches.
  The current tests run from the mounted worktree. CPU bootstrap used this
  already-built image (`JITML_BOOTSTRAP_SKIP_IMAGE_BUILD=1`).

- CPU bootstrap reached the monitoring rollout, where the operator and
  kube-state-metrics pods encountered registry network timeouts. The exact
  pinned images are present in the local Docker cache; their explicit Kind
  load is captured in `monitoring-image-load.*`. That diagnostic load exited
  `1` on a missing cached platform digest; its stderr is preserved. The
  monitoring pods subsequently became Ready with **0** restarts and bootstrap
  advanced to Envoy. No image pin or rollout gate was weakened. Bootstrap
  readiness subsequently passed, as recorded below.

- CPU bootstrap exited `0`: **114** live rollout steps in **944.57 s**,
  finishing **2026-09-17 23:41 UTC**. The retained publication identifies
  `linux-cpu`, edge **9091**, all **8** components Ready, and present readiness
  evidence. The stale Apple endpoint is no longer selected. All **12** dataset
  uploads exited `0` through `jitml internal upload-dataset`; the live
  inventory read-back passed **1 / 1** tests in **3.72 s**, confirming exactly
  twelve objects and every pinned SHA-256 through the published edge. Initial
  cluster health records **18** running pods, all Ready, **3** completed
  provisioning jobs, and **0** restarts.

- The full CPU unit retry exited `0`: **946 / 946** tests in **43.41 s**,
  including all four earlier mirror failures and the **39** aggregation cases.
  The successful invocation is preserved under `after-bootstrap/jitml-unit.*`;
  the first failed invocation remains intact.

- The full `jitml test jitml-integration --linux-cpu` invocation began at
  **2026-09-17 23:44:19 UTC** in `jitml-phase276-integration`. The new retained
  aggregate integration case passed (**0.10 s**), but the shared ProductScenario
  acquisition failed on `PPO/mountain-car`. Its publisher exited **2** after
  **142.558 s** with **1,228,800** environment steps and **20** evaluation
  episodes: `median_final_reward=-158.0`, required threshold `-155.0`,
  `passed=false`; average reward was `-158.00000000000006`. Publication correctly
  refused to mint passing `CompletedTraining` evidence. The cause of the
  training shortfall has not been investigated; this is not established as
  transient, an aggregation defect, or a substrate-specific defect.
- At **2026-09-18 02:46:38 UTC**, the captured Tasty output contained **71**
  failed assertions, all with the same `PPO/mountain-car` acquisition exception.
  These are dependent fixture failures, not evidence that 71 independent
  workloads ran and failed. The complete 55-row scenario and its journal were
  not produced. The suite continued through other tests: the live twelve-object
  inventory passed (**3.70 s**), then the live CLI WorkflowMatrix was still
  running `jitml tune experiments/mnist-tune.dhall`. No full-suite terminal
  status was available at the snapshot; this invocation cannot close the phase.

### Session Save Point

Work is paused at the user's request. Phase `276` remains **Active**; Phase
`278` and the later open phases remain **Blocked**, with the existing typed
registry count unchanged (**62 Done / 1 Active / 0 Planned / 7 Blocked**).
The current session has not started Phase `278` or changed any convergence bar.
All source and documentation changes remain in the working tree; agents have
not staged, committed, or pushed them.

- **Evidence directory:** `.build/phase276-20260917/`. Completed gate logs and
  exit files are retained there, including `after-bootstrap/jitml-unit.*` and
  `secondary-gates/`. Save-point documentation/quality checks are captured as
  `pause-docs-check.*`, `pause-plan-scan.*`, and `pause-check-code.*`; consult
  their `.exit` files for terminal outcomes. `full-integration.invocation.json`
  records the running
  command and start time; `full-integration.exit` is absent at the snapshot.
  The wrapper writes the final stdout/stderr, timing, and exit when the process
  terminates. Empty outer stdout while it runs is not an empty test result:
  `jitml` captures the child test output until its subprocess completes.
- **Preserved partial transcript:** `pause-snapshot.integration.stdout.log`
  (**444,710 bytes**, SHA-256
  `f3ebd44b7e0345c8dbcb20e1da0d24c69b817ad9313c531ecdd594b39ffca4d9`),
  `pause-snapshot.integration.stderr.log` (**0 bytes**), and
  `pause-snapshot.json` retain the observed failures and timestamp outside the
  disposable container. These are explicitly partial evidence, not a terminal
  invocation result. The live child streams at this snapshot are
  `/tmp/jitml-subprocess-ec00961d658fe62a/{stdout,stderr}` inside the test
  container. Do not copy or disclose the scenario's temporary `journal.key`.
- **Process and cluster:** the existing integration process and
  `jitml-linux-cpu` Kind cluster were left running. No test cancellation,
  cluster teardown, or new training invocation was performed for this save
  point. First inspect `full-integration.exit` and the actual container state
  when resuming; do not assume the process is still running. Cluster publication
  is `.build/runtime/cluster-publication.json`, CPU edge **9091**. The last
  recorded health check had **18** running pods Ready and **0** restarts.
- **Machine handoff:** Phase `273` is fully closed; its Metal daemon and Apple
  Kind cluster were torn down. The remaining open chain uses Linux CPU/Docker.
  This current validation is Linux **arm64** on the Mac's Docker host and needs
  no Metal device. Preserve the working tree, new untracked source/attestation
  files, and ignored `.build/phase273-20260916/` and
  `.build/phase276-20260917/` evidence before moving machines. Ignored logs are
  not preserved by a source-only checkout. An interrupted scenario cannot be
  resumed from its partial test output; a fresh complete integration gate is
  required after remediation. Retain the registered lane journal pins; this
  failed run cannot replace the earlier admitted CPU journal.

### Remaining Work

1. On resume, collect the existing integration invocation's final result if it
   has finished, retaining both output streams and any further failures. Keep
   the failed invocation and partial snapshot intact.
2. Investigate the `PPO/mountain-car` measured convergence shortfall on real
   `linux-cpu` using the exact current projection, seed, budget, and image.
   Relevant boundaries are `src/JitML/Product/Publisher/RL.hs`,
   `src/JitML/Product/Matrix.hs`, `src/JitML/RL/ConvergenceThresholds.hs`, and
   `test/integration/Main.hs`'s shared ProductScenario acquisition. Diagnose
   the cause before changing training behavior; lowering the bar or declaring
   this fixture passed does not validate the obligation.
3. Validate any necessary remediation in its focused CPU gate, then pass a
   fresh full `jitml test jitml-integration --linux-cpu` invocation on a ready
   current-source CPU cluster with all twelve verified datasets. Rebuild and
   reconcile the image if runtime source changes. Preserve distinct retry logs.
4. Pass final docs, container code quality, and plan-rule scans before closing
   Phase `276`. The full unit, affected e2e, negative-control, and
   model-convergence gates already passed for the current implementation;
   rerun affected gates if remediation changes that implementation.
5. Move the obsolete prose-aggregation entry to Completed only after its
   replacement has passed all required validation, then update the registry and
   control documents before starting Phase `278`. Retain the CPU cluster for
   subsequent CPU phases, or use the supported `down` command when live work is
   intentionally ended; a future run must verify actual publication/readiness.

## Documentation Requirements

**Engineering docs to create/update:**

- [Typed run contract](../documents/engineering/run_contract.md): registered journal authority, typed join, and canonical aggregate read-back.
- [Product completion contract](../documents/engineering/product_completion_contract.md): retained evidence and aggregate admission boundaries.
- [Unit testing policy](../documents/engineering/unit_testing_policy.md): CPU-only aggregation and adversarial admission coverage.

**Product docs to create/update:**

- [Project README](../README.md) and the plan control documents identify the current execution owner.
- `attestations/product-aggregate.json` retains the generated versioned report and closure input.

**Cross-references to add:**

- None.
