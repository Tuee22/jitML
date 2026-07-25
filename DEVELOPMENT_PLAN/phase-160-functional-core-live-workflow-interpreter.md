# Phase 160: Functional-Core Live Workflow Interpreter

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Functional-Core Live Workflow Interpreter. Single-session phase migrated from legacy Sprint 12.16 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 160.1: Functional-Core Live Workflow Interpreter [✅ Done]

**Status**: Done (implementation started 2026-07-14; unblocked and validated
2026-07-15 after Sprint `3.7` re-closed)
**Implementation**: `src/JitML/Test/WorkflowMatrix.hs`,
`src/JitML/Test/LivePlan.hs`, `src/JitML/Test/Report.hs`,
`src/JitML/Test/{RunContract,LiveWorkflow,LiveEvidence,PulsarTransport}.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`, `src/JitML/App.hs`,
`src/JitML/Service/{Clients,Consumer,HostWorkloadRegistry,RoleLifecycle}.hs`,
`src/JitML/Service/{Runtime,RuntimeState,Workload}.hs`,
`src/JitML/Service/{InferenceBatch,LiveConfig,Logger,Retry}.hs`,
`src/JitML/Test/InferenceBatch.hs`, `src/JitML/Tune/Catalog.hs`,
`src/JitML/Bootstrap.hs`,
`src/JitML/Cluster/{Publication,PulsarBootstrap,Readiness}.hs`,
`src/JitML/Service/ConfigMap.hs`,
`src/JitML/Service/Http.hs`, `jitml.cabal`,
`test/daemon-lifecycle/{Main,SigtermRegression}.hs`,
`web/src/Panels/Stream.{purs,js}`, `playwright/jitml-demo.spec.ts`,
`chart/local/jitml-{service,demo}/templates/*.yaml`
**Docs to update**: `../README.md`,
`../documents/engineering/daemon_architecture.md`,
`../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/pulsar_ml_workflow.md`,
`../documents/engineering/training_workloads.md`,
`../documents/engineering/run_contract.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`

### Objective

Interpret every live workflow that claims protocol completion through one
resource-safe IO shell around the pure contract reducer, and report only the
invocation and evidence states that actually occurred. Public-CLI matrix cells
remain typed executable-outcome coverage when no outer correlated subscription
exists; transport/placement smokes cannot masquerade as completion. This sprint
owns the harness portions of
[Exit Definition](README.md#exit-definition) items `31`, `32`, and `33`.
The binding design is
[README.md → Typed run contracts](../README.md#typed-run-contracts).

### Deliverables

- Add one `runLiveWorkflow` interpreter that subscribes before publication,
  renders commands/topics through typed protocol and topology surfaces, and
  consumes receipt-bound decoded events into the pure reducer.
- Complete the live one-binary role interpreter: Coordinator reconciles the
  exact typed topic family at acquire, gates readiness on that evidence, serves
  without Engine compute subscriptions, owns the cluster-orchestration
  Harbor/kubectl effects currently retained by the Engine compatibility path,
  and drains its scoped loops; Engine and Webapp retain only their disjoint
  compute/browser capabilities.
- Supervise Apple host-resident Training/Tune/RL work under validated keyed
  handles so Stop cancels or drains the matching action exactly once; replace
  the Phase `5` safe Nack with successful terminal evidence only after the real
  handle is observed.
- Add dynamic LiveConfig fields only with their operational consumers:
  structured-log filtering, service retry scheduling, inference batching, and
  latency-SLO enforcement all read the atomic live snapshot and have reload
  behavior tests; no accepted field is inert.
- Require both terminal workload success and complete evidence, accepting either
  arrival order; delete no Job until both conditions are resolved.
- Replace reward lists and boolean tuples with exact key-indexed evidence that
  rejects gaps, conflicting duplicates, wrong `PlanId`, malformed values, and
  missing terminal events.
- Represent placement and job observation as closed sums (`Missing`, `Pending`,
  `Running`, `Succeeded`, `Failed`, `ProbeFailed`) with diagnostics attached.
- Scope owned subscriptions, Jobs and their per-run ConfigMaps, and ephemeral clusters with
  `bracket`/`generalBracket`; gather diagnostics before cleanup and preserve
  cleanup failures without hiding the primary failure.
- Replace hand-rendered topic names, subscription encodings, commands, hashes,
  and per-workflow collectors in `test/integration/Main.hs`.
- Model each test invocation as `Passed`, `Failed`, or `NotRun`, derive suite
  counts from those values, and retain the complete subprocess/scenario journal.

### Current Implementation State

- `runLiveWorkflow` is the single evidence-bearing live IO shell. It acquires
  correlated subscriptions before publication, folds decoded events through
  the pure contract, observes typed placement/Job state, and scopes cleanup and
  diagnostics without allowing transport smokes to mint completion evidence.
  Its journal orders diagnostics before the owned subscription and placement
  releases; independent primary, completion, and cleanup facts survive every
  release outcome.
- Exact supervised, RL, Tune, AlphaZero, GC, and inference adapters are landed;
  the former reward-list/boolean collectors and zero fallback are absent. Job
  observation is a closed diagnostic sum, and terminal success plus complete
  evidence is order-independent.
- The production role boundary is landed but not yet through the full sprint
  gate. `DaemonRuntime` retains a closed role-projected client value: Engine runs
  an opaque MinIO/Pulsar-only interpreter, Coordinator alone retains
  Harbor/kubectl settings and namespace RBAC for per-run ConfigMap/Job
  reconciliation, and Webapp retains no daemon clients, GPU runtime, device
  environment, or Kubernetes API token. The platform readiness
  gate waits for both `deployment/jitml-coordinator` and the Engine
  `deployment/jitml-service` before bootstrap may publish the cluster. The
  existing Engine Deployment selector remains app-only so Helm upgrades do not
  mutate Kubernetes' immutable selector; `jitml.role: engine` remains on the pod
  template for role-indexed diagnostics and policy.
- Engine and Coordinator have bounded five-minute startup probes, so their
  liveness probes cannot restart a healthy process while topic reconciliation,
  persistent consumer connection, and client probes are still completing.
  After applying Gateway and HTTPRoute manifests, bootstrap runs one typed,
  bounded, retrying public `/readyz` request through the Coordinator-only
  Service. Linux publication re-measures both role Deployments; Apple publication
  requires the clustered Coordinator and public edge but deliberately records no
  Engine row because its clustered Engine has zero replicas and the separately
  launched host daemon is not bootstrap evidence. Every substrate requires
  exactly one ready row for its registered components and returns a typed
  invariant failure without writing live evidence when any row is missing,
  duplicated, unexpected, or not ready.
- Apple host Starts are supervised in a keyed process-local registry. Stops
  select exact cancel or natural-drain semantics, join the matching handle, and
  retain the successful receipt for same-`EventId` redelivery when required
  terminal status publication fails. Bounded consume-once joins all registered
  handles and surfaces retained worker failures.
- Structured log filtering, retry scheduling, inference batching/latency SLO,
  dedup resize/TTL, and positive drain-deadline validation consume the atomic
  LiveConfig snapshot. Invocation and scenario journals now derive
  `Passed`/`Failed`/`NotRun`, counts, duration, and failure status from observed
  outcomes rather than declared pass rows. The live e2e scope derives diagnostic
  collection from `generalBracket`'s `ExitCase`, so exceptional, cancelled, and
  aborted exits cannot cross a mutable clean-body flag and skip pre-release
  diagnostics.
- Phase-owned temporary MinIO fixtures and every Linux workload Job/derived
  `runconfig-<jobName>` ConfigMap pair are held by exception-safe scopes.
  Cleanup attempts every resource, retains each typed deletion failure beside
  assertion or workflow failures, and never labels failed cleanup as release.
- Production Linux Training, Tune, and RL Stop programs retain the same paired
  ownership as Start: each emits ordered, indexed deletion effects for the Job
  and its derived `runconfig-<jobName>` ConfigMap. The Workload interpreter
  attempts both effects and preserves each typed outcome; exact CPU/CUDA
  builder and daemon-dispatch regressions pin the resource names and order and
  prove that a typed failure at either deletion does not skip the other.
- The warning-clean combined library/test build passes. Current source pre-gate
  suites are green: `jitml-unit` **544 / 544**,
  `jitml-daemon-lifecycle` **51 / 51**, and `jitml-e2e` **29 / 29**, including
  the actual production-binary threaded-RTS probe, repeated quiet-WebSocket
  handler release, real daemon-process signal/drain cases, role-projection
  regressions, and scoped exceptional-exit diagnostics. `jitml lint
  purescript` also passes the **611**-module frontend compile, **18** specs, and
  tidy check with the cleanup-bearing stream emitter. These checks do not
  replace the repaired-image canonical validation below.
- The first unfiltered non-Live `jitml-integration` pre-gate passed **68 / 123**
  cases and failed **55 / 123**, all in the ProductRow checkpoint matrix: **46**
  retained manifests recorded more units than their now-exact declared budget,
  and **9** retained manifests predated the refined content encoding and no
  longer matched their pointer SHA. That first gate remained failed until the
  artifacts were regenerated through the reconciled real producers; stale or
  over-budget evidence was not accepted as completion. The
  test enumeration at that checkpoint was **124** non-Live plus **20** Live
  cases. Later regressions bring the current enumeration to **125** non-Live
  plus **20** Live; final validation records the reporter's newly observed
  counts rather than reusing either historical value.
- ProductRow budget reconciliation is present for the regeneration: supervised
  rows consume their registered `5`- or `10`-epoch execution schedule, while
  traditional RL rows obtain the aggregate transition count from
  `JitML.RL.ProductBudget`, including vector-environment and indivisible
  rollout/episode granularity. The `sl_epochs=5` and `rl_steps=100_000`
  report-card knobs remain separate canonical-measurement inputs and cannot
  mint ProductRow completion. At that checkpoint the implementation state was
  not validation evidence and the retained artifacts plus unfiltered
  integration gate remained red; the later regeneration evidence below
  supersedes the retained artifacts.
- The internal ProductRow publisher and wall-clock benchmark now share one
  fail-closed filter parser. A mixed valid/invalid request reports every unknown
  row, duplicate identifiers are rejected, and neither internal command begins
  producer work or runtime probes until the complete requested set is valid.
  The focused ProductRow unit scope passes **16 / 16**; live CLI probes reported
  both unknown dotted identifiers and the repeated `PPO/cartpole` identifier
  before any producer row began.
- The first full exact-budget regeneration traversed all **55** rows and
  reported **53** eligible, **0** unsupported, and **2** errors. Every
  supervised, non-TRPO RL, AlphaZero, and tuning row published. The two red rows
  were real deterministic convergence failures: `TRPO/cartpole` produced median
  final reward **126** against its **185** bar at **1,228,800** transitions, and
  `TRPO/lunar-lander` produced **-179.21215200130655** against **155** at
  **2,400,000** transitions. That result did not satisfy the **55 / 55** gate;
  the thresholds and exact budgets remained binding while the real TRPO path
  was corrected and selectively regenerated as recorded below.
- The first independent 55-case artifact slice passed **49 / 55** and failed
  exactly those two TRPO rows plus all four AlphaZero rows. The TRPO rows then
  retained their old local over-budget pointers and had no live object. The new
  AlphaZero pointers were byte-identical locally and live, but their manifests
  were inference-ineligible because checkpoint step recorded sample count while
  `CompletedTraining` recorded generation count: connect4 **2,370 / 64**,
  othello **23,037 / 96**, hex **23,727 / 128**, and gomoku **17,475 / 128**.
  Producer `eligible` status therefore cannot substitute for the checkpoint
  refinement gate.
- The actor-side TRPO audit corrected trust-region contract violations without
  changing either product bar. The current implementation runs exactly one
  natural-gradient actor trust-region step per rollout, followed by
  **10** separate value-head-only critic passes over the configured rollout
  minibatches in both the pure and device paths. Each critic minibatch
  recomputes its gradient at the current critic parameters and threads critic
  Adam at the TRPO-specific **0.001** learning rate. Both counts are independent
  of PPO epochs, and critic gradients plus stale Adam moments cannot change
  actor parameters. The actor line search requires a strict surrogate
  improvement under exact full categorical KL and otherwise rolls back; its
  Fisher-vector product is policy curvature rather than squared
  objective-gradient entries, and the acceptance and actor objectives agree on
  zero TRPO entropy. Malformed configurations, batches, device outputs,
  gradients, and optimizer state fail closed. The current focused TRPO scope
  passes **17 / 17**, the full `jitml-unit` stanza passes **517 / 517**,
  Fourmolu is clean for the changed scope, and focused HLint reports no hints.
  The container `jitml-rl-canonicals` lane with
  `JITML_SUBSTRATE=linux-cpu` passes **40 / 40** in **225.43s**. The exact
  runtime diagnostics and selective regeneration/artifact gates now pass as
  recorded below. Thresholds and exact transition budgets remain intact; the
  unfiltered producer now passes and the full **55 / 55** artifact-refinement
  gate is still required. The first
  pre-multi-pass selective
  runtime attempt on 2026-07-15 traversed both rows but produced **0** eligible,
  **0** unsupported, and **2** errors.
  CartPole failed closed with `TRPO conjugate-gradient curvature is not finite
  and positive`. Lunar Lander completed **2,400,000** transitions and improved
  its median final reward from **-179.21215200130655** to
  **13.372352820002362**, but still failed the unchanged **155** criterion.
  Two further exact-budget controls also stayed red before the multi-pass
  change: increased update density at `max-kl = 0.002` produced
  **-39.564210179995044**, and the denser schedule at `max-kl = 0.01` produced
  **-428.10478983664495**. These diagnostics reject schedule/KL-only
  workarounds; they are not closure evidence for the current implementation.
- On 2026-07-15 the corrected immutable image passed its clean-room build and is
  live as
  `jitml:local@sha256:30eb596380d9e939ae5bd5e0a87757d557576ef7a32614e156953057eba8b813`
  with platform manifest
  `sha256:e37527306af6173e4195a291f4e20b053454b0484de0d47c5ab71268ef6bc0a0`
  and config image ID
  `sha256:560d1b72153a6d8acdf232facc986089c3a0a7f178cfb85627c2e25b34a0253a`.
  Its embedded `jitml check-code` passed, and the frontend compiled **611 /
  611** modules with **0** warnings and **0** errors. `jitml:local` and
  `jitml-demo:local` resolve to that config ID on each of the four retained Kind
  nodes. Sequential rollouts converged for all three application Deployments;
  the three Engines, Coordinator, and Webapp are Ready with zero restarts and
  the same config image ID. Public `/healthz` and `/readyz` pass, the retained
  publication still has exactly nine ready rows, and all four MinIO PVCs retain
  their prior UIDs in `Bound` state. This closes the immutable-image and rollout
  prerequisite without claiming ProductRow convergence.
- The exact no-publish CartPole diagnostic against that corrected runtime
  completed **1,228,800** transitions under the resolved **150 × 512 × 16**
  schedule. All **20** deterministic evaluation episodes reached the **500**
  step limit with reward **500.0**, so the final-tail median **500.0** passes
  the unchanged **185** bar. This is runtime convergence evidence only: it did
  not write a checkpoint or live object and therefore could not itself satisfy
  publication; the subsequent selective publisher evidence follows below. The
  corresponding Lunar Lander diagnostic completed
  **2,400,000** transitions under the resolved **150 × 1,000 × 16** schedule.
  All **20** deterministic evaluation episodes ended after **85** steps with
  reward **271.16021982**, so the final-tail median **271.16021982** passes the
  unchanged **155** bar. It likewise did not publish an artifact.
- The installed immutable publisher then ran the exact two-row filter once and
  reported **2** rows, **2** eligible, **0** unsupported, and **0** errors.
  `TRPO/cartpole` published manifest
  `57b3f858714b8777781720736e43d571adde6ad82932da5b5183d61f78a8c78b`;
  `TRPO/lunar-lander` published
  `0ae8d6a23f15dfcc0ced16ecb4fea27f60dff15f69500ea0e48ee08b86db28e6`.
  The focused artifact-refinement slice then passed **2 / 2**. For both rows,
  the local pointer equals the local manifest content SHA, the live pointer
  equals the live manifest content SHA, and all four values agree. This closes
  the selective artifact/hash gate without substituting it for the unfiltered
  producer traversal.
- The AlphaZero artifact-unit correction is landed in all three production
  writers: Apple host execution, the resolved cluster worker, and ProductRow
  publication now derive checkpoint step from completed self-play generations,
  the same unit carried by `CompletedTraining`; generated sample count remains
  diagnostic evidence only. A focused unit regression with **64** generations
  and **2,370** samples passed. On 2026-07-15 the corrected immutable image
  `sha256:c085148fcaf8c17bba1166ae0c58a175b5d81d03db84ceca6562a32b941dd5c9`
  regenerated connect4, othello, hex, and gomoku with **4** eligible, **0**
  unsupported, and **0** errors. The focused artifact-refinement slice executed
  and passed **4 / 4**. Their new manifest SHAs are respectively
  `53e8390394bd5682d53daf6f45da6d119e9d2beb9cf3e9681f158ac42cd1d1a1`,
  `bfa64783fe610ea56a21a7aa6bf88643f1f167d6c03af80648ef05bc135d0cc1`,
  `3bfd546e9061bdb986114d9cf0ee5c35b9d3643a7ddf95132f7462c912b22587`,
  and `58afa9fd0f3e8ae9e5b45e29cf444dc16fc11a37bed459831b4eef268ac1fa44`;
  each local pointer, live pointer, local manifest hash, and live manifest hash
  agrees. Checkpoint steps and completed self-play generations are exactly
  **64 / 64**, **96 / 96**, **128 / 128**, and **128 / 128**. Their observed
  arena win rates are **0.7777777777777778**, **0.8888888888888888**,
  **0.5555555555555556**, and **0.7777777777777778**, each passing the binding
  `>= 0.4` criterion.
- The installed immutable unfiltered `linux-cpu` producer then exited **0**
  after traversing all **55** ProductRows and reported **55** rows, **55**
  eligible, **0** unsupported, and **0** errors. The traversal reproduced the
  corrected TRPO and AlphaZero manifests alongside every other registered row.
  This closes the producer gate; the independent artifact evidence follows.
- The exact `integration.product` selection then exited **0** and passed
  **55 / 55** in **0.01s**. The independent four-way verifier also exited **0**
  with `canonical_rows=55`, `local_namespaces=55`, `live_namespaces=55`,
  `local_pointers=55`, `live_pointers=55`, `local_manifests=55`,
  `live_manifests=55`, `four_way_matches=55`, `missing=0`, `extra=0`,
  `duplicates=0`, and `mismatches=0`. Every canonical ProductRow therefore has
  one local namespace and one live namespace whose pointer and manifest
  content SHA agree across all four values. This closes the full artifact and
  content-SHA gate independently of producer eligibility.
- The first unfiltered integration rerun exposed a stale live supervised test
  request: **5** epochs × **4,096** training examples with **1,024** evaluation
  examples produced `test_accuracy = 0.8935546875`, below the unchanged
  **0.90** bar. The run correctly could not mint `CompletedTraining` and timed
  out with incomplete evidence. The test request now uses the existing
  registered/ProductRow-publisher MNIST schedule of **10** epochs × **7,000**
  training examples with **1,000** evaluation examples; no convergence bar was
  changed. The focused live `StartTraining` case then exited **0** and passed
  **1 / 1** in **32.54s**, including cleanup.
- The next unfiltered integration pre-gate exited **1** after **140 / 144**
  cases passed in **1,776.55s**. The corrected supervised case passed in
  **31.44s**, and the unchanged real PPO case passed in **725.51s**. The four
  failures were scoped and retained: the WorkflowMatrix inference cell and the
  exact inference workflow timed out without a result; duplicate-Start
  diagnostics selected a still-creating workload pod; and the stale two-trial,
  one-update Tune request produced two objectives of **0.5** and no
  `SweepCompleted`, below the unchanged **1.0** target with **0.05** slack.
- Broker evidence for both inference failures showed three accepted request
  messages, thousands of redeliveries, zero acknowledgements, and no result
  publication. An under-capacity batch waited through its captured **25ms**
  handler/publication-entry deadline, then skipped its handler and Nacked
  forever. The first admission now captures one immutable monotonic
  deadline, and collection closes after the smaller of **1ms** or one tenth of
  the captured latency budget. If no decision has returned by expiry, the
  transport cancels the handler and Nacks every admitted receipt; immediately
  before publication the Engine also refuses to begin a new publish at or after
  that deadline. A decision returned before timeout is settled as returned,
  without retroactive deadline reclassification, because publication may
  already be visible. The shared deadline/policy scope passes **6 / 6** and the
  complete Pulsar transport scope passes **31 / 31**, including single and
  batched cancellation during a slow failing DELETE, typed settlement failure
  during handler/policy cancellation, the under-capacity regression, and the
  real Node batch-drain race. The batch bridge flushes the private Nack for
  every raced receipt before `Drained`, the single bridge rejects unsolicited
  deliveries, and Haskell lint is clean.
- The first exact inference rerun against the rolled-out repair failed **1 / 1**
  after **120.27s**. The reply subscription released correctly, but the exact
  request remained as the sole `jitml-engine` backlog entry and no result topic
  existed. A broker peek tied message `128:2` to call
  `live-inference-call-1784179856971664-1`; through the retained evidence window
  Pulsar emitted exactly **355** negative-ack redeliveries and **355** matching
  cursor rewinds, with no acknowledgement, no unacked delivery, three connected
  Engine consumers, and no worker reconnect or completed outcome log. The new
  one-millisecond cutoff therefore reached the handler, but the inherited
  **25ms** captured handler/publication-entry fence still cancelled the real
  cold MinIO/checkpoint, oneDNN/JIT, and result-publication path. After
  capturing that evidence, only this expired subscription backlog was cleared.
- All three Engines then hot-reloaded a diagnostic **1,000ms** window through
  SIGHUP at generation **1** with zero restarts. The unchanged exact live test
  exited **0** and passed **1 / 1** in **1.17s**. Broker timestamps measured
  approximately **996ms** from request delivery to acknowledgement, and the
  Engine emitted its completed dispatch outcome at roughly **963ms**, so one
  second is not a stable production margin. The operational default and all
  checked-in Engine, Coordinator, and Webapp `LiveConfig` materializations are
  now **5,000ms**. This retains the monotonic handler-completion and
  Engine-publication-entry deadline, one-millisecond sparse-collection cap,
  complete-batch Nack when no decision returns by expiry, and unchanged CLI
  **30s** reply timeout. A returned decision is settled without a retroactive
  Nack, and no broker-ack completion deadline is claimed. It provides room for
  the observed cold path plus the configured exponential retry schedule. The
  focused source gate now passes: `jitml-unit` **535 / 535**, complete
  `jitml-daemon-lifecycle` **50 / 50**, chart/materialization integration **2 /
  2**, container Haskell lint, docs check, and `git diff --check`. The current
  non-Live integration enumeration is **125**; the unfiltered pre-gate remains
  open. All three Engines then hot-reloaded the durable **5,000ms** value at
  generation **2** with zero restarts. Two unchanged unique-checkpoint exact
  live runs exited
  **0**, passing **1 / 1** in **1.20s** and **1 / 1** in **1.14s**. The first
  request was acknowledged in approximately **982ms** and the warm repeat in
  approximately **205ms**; request backlog and unacked counts are both zero,
  the result topic records **2** publications and **2** deliveries, and its
  subscription map is empty after joined cleanup. These hot-reload results
  validate the value and lifecycle, but the final claim still requires the new
  immutable image and the complete focused/canonical rerun against it.
- The timed-out public CLI calls also exposed two stale `jitml-infer-*`
  subscriptions. The caller had delivered cancellation with `killThread` but
  neither joined the consumer nor observed the transport's typed DELETE
  result. It now supervises the worker with `Async`, cancels and joins on every
  primary exit, bounds the uninterruptible owned DELETE, de-duplicates natural
  consumer failure, preserves secondary cleanup failure beside a normal
  primary, and reports it before rethrowing the identical exceptional primary.
  Four bounded lifecycle regressions pass **4 / 4**. The live WorkflowMatrix
  now snapshots the inference-result subscription inventory before and after
  execution and rejects every newly leaked `jitml-infer-*` cursor. Rebuilt live
  proof remains pending.
- Inference reply correlation now requires both the request `callId` and
  experiment hash. A live reply startup, publication, transport, cleanup, or
  timeout failure is reported as `PulsarFailed`, not as evidence that the
  checkpoint is missing. Batched daemon dispatch commits each completed
  command's semantic event ID independently; if a later command is cancelled,
  every earlier commit survives while the interrupted command remains eligible
  for redelivery. This is bounded idempotency on an at-least-once broker, not
  exactly-once delivery. Settlement, drain, child-process, and owned-cleanup
  failures retain their typed identity.
- Duplicate-Start diagnostics now select only daemon pods with the conjunctive
  `app in (jitml-service,jitml-coordinator),jitml.role in
  (engine,coordinator)` selector, excluding workload Jobs that also carry the
  Engine role label without hiding genuine daemon-log failures. Its structural
  regression passes **1 / 1**, the exact live selector exits **0**, and Haskell
  lint is clean. The hot-reloaded full duplicate workflow now passes **1 / 1**
  in **1.37s**; exact post-immutable-rollout repetition remains pending.
- The live Tune completion fixture now derives the registered
  `hyperparameter-tuning` ProductRow and `JitML.Tune.Catalog` schedule rather
  than a test-local miniature: TPE, ASHA, MedianPruner, seed **1729**, **128**
  trials, a **1000**-optimizer-update ceiling allocated through measured
  eta-derived rungs, parallelism **1**, and exactly one promotion.
  The unchanged **1.0** target and **0.05** slack remain binding. Its non-Live
  schedule/convergence regression passes **1 / 1**. The hot-reloaded registered
  live workflow now passes **1 / 1** in **21.10s**; exact post-immutable-rollout
  repetition remains pending.
- The hot-reloaded public WorkflowMatrix passes **1 / 1** in **418.56s**,
  including the formerly timed-out inference cell and the broker-inventory
  assertion that no `jitml-infer-*` cursor leaked. Together with the duplicate,
  Tune, and two inference results above, all four repaired paths are provisionally
  green with no workload Job or `runconfig-*` ConfigMap residue. The new
  immutable image and identical post-rollout selection remain the binding gate.
- The first supported immutable-image build containing all four repairs reached
  `[251 of 261] Compiling JitML.App` and then failed closed before
  `jitml check-code`: GHC 9.12.4 reported `heap overflow` under the binding
  `+RTS -M2G -RTS` compiler limit. The host retained ample memory, so the limit
  was not weakened. The newly added higher-order reply supervisor is now
  isolated in `JitML.Service.InferenceReplyScope`; both exported entrypoints are
  `NOINLINE` so `-fexpose-all-unfoldings` cannot pull that Core back into the
  already-large CLI composition module. The ordinary container build compiles
  both modules, the direct lifecycle scope still passes **4 / 4** in **0.21s**,
  `git diff --check` is clean, and container Haskell lint passes. The supported
  retry then completed all **17 / 17** BuildKit steps in **31m37s**. Both the
  primary CUDA-enabled compile and `check-code`'s `-Werror` compile emitted
  `JitML.App.o` under the unchanged heap cap; embedded `jitml check-code`
  passed; and the frontend compiled **611 / 611** PureScript modules with **0**
  warnings and **0** errors. The resulting immutable image index is
  `sha256:0d86d6dbf1fa1f1133eacb0e9c930a5190d8f1c52bc907f86ca67906c32228d4`
  with linux/amd64 manifest
  `sha256:135a19c752e9ba0bb354804d62c2b68d563296dda91badeb5577caaea8a2563b`.
  Both shared tags were loaded into all four retained Kind nodes and resolve to
  config image
  `sha256:33fe6dd03a7d38b8e6b748bd202e63f2f52ebb10973749d25c143a3fe0b79ce5`.
  Sequential Engine, Coordinator, and Webapp rollouts converged **3 / 3**, **1 /
  1**, and **1 / 1** with zero jitML app restarts. All **16** Deployments and
  **14** StatefulSets have no readiness mismatch; public `/healthz` and
  `/readyz` return HTTP **200**; publication remains exactly **9 / 9**; and all
  **20** PVC names, UIDs, and `Bound` phases exactly match the pre-rollout
  baseline. The three expired inference commands were cleared only from the
  retained `jitml-engine` subscription, which still has three consumers and
  zero backlog. Exactly the two stale zero-consumer `jitml-infer-*` result
  subscriptions were removed. No jitML workload Job or `runconfig-*` ConfigMap
  remains. Rebuilt focused live proof remains required.
- The same audit confirmed a distinct, later-owned evaluation-contract debt:
  current ProductRow traditional-RL training uses one derived seed and its
  deterministic evaluator repeats the same standard-start greedy episode,
  whereas the binding convergence doctrine requires a fixed five-seed cohort.
  This does not authorize a Phase `12` workaround or a weaker bar; Sprint
  `25.4` remains responsible for the typed seed-cohort/evaluation correction.
  Phase `12` closes only when the honest current producer meets its existing
  fixed budget and thresholds with the corrected trust-region implementation.
- The audit also confirmed that `TrainingEvidence.updateCount` still projects
  configured or rollout counts rather than an exact count of applied optimizer
  steps, including accepted versus rolled-back TRPO actor steps. Phase `12`
  does not redefine that evidence field: the singular ProductRow-to-evidence
  projection remains open under Sprint `21.4`, after Sprint `19.4` installs the
  required ProductRow plan projection in the mandated phase order.
- The immutable-ALE replacement image is built and attested as
  `jitml:local@sha256:43d550a4b7d2353e2942e9aadba586413a3387c94f34962e9de7eb0221b9cf45`.
  Its embedded `jitml check-code` gate passed, and the frontend rebuilt all
  **611** PureScript modules with **0** warnings and **0** errors. This closes
  the image prerequisite only; no cluster or ProductRow evidence is inferred
  from a successful image build.
- The supported clean `linux-cpu` bootstrap from that image completed **133**
  rollout steps. Its publication has `evidence: live-readiness`, exactly the
  nine registered ready components, and the canonical loopback Pulsar/MinIO
  URLs; the public `/readyz` body is `ready`. Three zero-restart Engines and one
  zero-restart Coordinator are ready on `linux-cpu`, and the public Service
  selector names only the Coordinator. Harbor jobservice made two immediate
  dependency-startup attempts while `harbor-core` still refused connections,
  then remained ready; the jitML role processes did not restart.
- The fresh `jitml-datasets` bucket was empty by signed S3 inventory. All **12**
  locally pinned canonical files then passed the internal uploader's SHA-256
  check and were written under the exact typed keys: eight MNIST/Fashion-MNIST
  image/label objects plus the CIFAR-10, CIFAR-100, Tiny ImageNet, and California
  Housing archives. A second signed inventory reports all **12** keys.
- A real representative producer selection closed **4 / 4** rows with **4**
  eligible, **0** unsupported, and **0** errors: `mnist-shallow-mlp` processed
  its exact **70,000** example schedule and reached **0.915** test accuracy,
  while `PPO/cartpole`, `DQN/cartpole`, and `HER/goal-reaching` completed their
  exact registered transition schedules and published current artifacts.
- The binding immutable-image focused proof before the final Sprint `3.7`
  rebuild was green: exact inference passed twice in **1.20s** and **1.17s**,
  WorkflowMatrix passed in **432.19s**, duplicate-Start passed in **1.38s**,
  resolved Tune passed in **20.10s**, and Tune persistence/replay passed in
  **0.09s**, with no new reply cursor, workload Job, or `runconfig-*` ConfigMap.
  The final Phase `3` image superseded that image. Current-image preflight then
  exposed Pulsar's valid HTTP `307` owner redirect during owned-subscription
  deletion. Cleanup now follows at most five HTTP(S)-only redirects while
  preserving `DELETE`; the real socket regression and the complete
  `PulsarTransport` group pass **1 / 1** and **32 / 32**.
- On 2026-07-15 the redirect-safe supported build completed with embedded
  `jitml check-code: ok`; the frontend compiled **611 / 611** PureScript
  modules with **0** warnings and **0** errors. The resulting immutable image
  index is
  `sha256:0da77629209333a22f500e54cb2554da7e199b9aec9024b3f7a7384aa35dc361`,
  with linux/amd64 manifest
  `sha256:521674e7a949389752e584dc2656a73b43ecc14cde3fb68240d71d0055254e43`
  and config image ID
  `sha256:f9a63c53fea29cdfa76fce390bf246742a5a9adef2f9f3f1b54b397e117e326c`.
  The supported retained-cluster reconcile, skipping only the duplicate nested
  image build, exited **0** after **156** live rollout steps. Both application
  tags resolve to the same index, manifest, and config on all four Kind nodes;
  the three Engines, Coordinator, and Webapp are Ready with zero restarts and
  that exact config ID. The three Pulsar broker UIDs, zero-restart states, and
  StatefulSet revision are byte-identical to the Phase `3` durable baseline;
  inactive-topic deletion remains disabled in desired and runtime config; all
  **34** exact topic stats calls return objects. Publication remains exactly
  **9 / 9**, `/healthz` and `/readyz` pass on edge `:9091`, the Engine request
  subscription has zero backlog/unacked messages and three consumers, the
  result topic has no subscription, and no workload Job, workload pod, or
  `runconfig-*` ConfigMap remains. The formerly failing live
  `POST /api/checkpoints` now returns HTTP **200** with all **55** ProductRow
  selectors, then removes its owned result subscription without leaking a
  cursor. `git diff --check` is clean.
- The exact current-image focused block then passed: live inference **1 / 1** in
  **1.34s**, public WorkflowMatrix **1 / 1** in **432.83s**, duplicate-Start
  **1 / 1** in **0.34s**, resolved Tune **1 / 1** in **23.19s**, and Tune
  persistence/replay **1 / 1** in **0.09s**. A complete post-focused proof
  retained the same image/index/config tuple on every node, five Ready
  zero-restart application pods, the unchanged three-broker durable baseline,
  **34 / 34** exact topics, zero request backlog/unacked messages with three
  Engine consumers, an empty result subscription map, and no workload Job,
  workload pod, or `runconfig-*` ConfigMap. The unfiltered pre-gate is now the
  next binding command.
- The unfiltered `jitml test jitml-integration --linux-cpu` pre-gate then exited
  **0** and passed **155 / 155** in **1,658.82s**. Its live timings include
  WorkflowMatrix **424.47s**, StartTraining **32.52s**, duplicate-Start
  **0.32s**, StartRLRun **183.56s**, PPO CartPole convergence **737.15s**,
  inference **1.13s**, Tune persistence **0.09s**, resolved Tune **21.06s**,
  and AlphaZero dispatch **4.57s**. The journal-derived stanza report records
  one Passed invocation, zero Failed, and zero NotRun. A complete post-gate
  proof again retained the exact image tuple, five Ready zero-restart app pods,
  unchanged durable broker lineage, **34 / 34** topics, zero cursors/backlog,
  and no workload or ConfigMap residue. The six-command canonical block is now
  the only validation work before ledger and status closure.
- Canonical command **1 / 6**, `jitml test jitml-unit --linux-cpu`, exited **0**
  and passed **544 / 544** in **41.17s**. Its invocation journal records one
  Passed stanza, zero Failed, and zero NotRun; the redirect-following owned
  cleanup regression is included in the complete `PulsarTransport` group. The
  canonical integration rerun is next.
- Canonical command **2 / 6**, `jitml test jitml-integration --linux-cpu`,
  exited **0** and passed **155 / 155** in **1,658.23s**. The second independent
  live run remained stable: WorkflowMatrix **417.47s**, StartTraining
  **32.54s**, StartRLRun **185.64s**, PPO convergence **739.19s**, inference
  **1.13s**, resolved Tune **20.06s**, and AlphaZero dispatch **4.57s**. Its
  post-command cluster proof again records the exact image tuple, five Ready
  zero-restart app pods, unchanged durable brokers, **34 / 34** topics, and
  zero cursor/workload residue. Live e2e is next.
- The first attempt at canonical command **3 / 6**, `jitml test jitml-e2e
  --live --linux-cpu`, exited **0** after **286.10s**: the journal report
  recorded **2** Passed invocations, zero Failed, and zero NotRun; the Haskell
  body passed **28 / 28**; and the browser matrix completed all **71** cases,
  with one case succeeding on retry. That command is not accepted as Sprint
  closure evidence because the mandatory post-command cluster proof found the
  Webapp pod had restarted. Previous-container logs reported file descriptor
  **1032** outside the non-threaded `select()` range; the restarted process then
  retained **182** quiet `jitml-demo-bridge-inference` consumers and **917**
  descriptors before a second `OOMKilled` restart. Pulsar retained **380**
  inactive `jitml-demo-bridge-*` subscriptions. The exact leak was one accepted
  socket, two pipes, and two transcript files per browser bridge: the server
  observed peer loss only during writes, so a quiet handler remained blocked in
  Pulsar consumption after the page closed.
- The repair is implemented but not yet validation evidence. The production
  executable is linked with `-threaded` and the daemon-lifecycle suite now runs
  the actual built binary with `+RTS -N1`. The HTTP listener races every
  server-push handler against a read-side peer-close/EOF watcher, cancels and
  joins the scoped handler before closing the connection, and masks the
  accepted-socket handoff into its fork. A repeated quiet-close regression
  requires every handler finalizer to run and the active count to return to
  zero. On the browser side `Panels.Stream` now constructs a cleanup-bearing
  Halogen emitter; component disposal detaches callbacks and closes its
  WebSocket, with a live hash-navigation Playwright regression. The **380**
  orphaned cursors must be removed explicitly, then a new immutable image must
  be built and rolled out. Because the source/image changed, canonical commands
  **1 / 6** and **2 / 6** above remain diagnostic history and the binding block
  restarts at **1 / 6** on the repaired image.
- The first quiet-WebSocket repair image completed the supported build with
  embedded `jitml check-code: ok`; its frontend compiled **611 / 611** modules
  with zero warnings and zero errors. The immutable index is
  `sha256:5060ce86a25bb1f5869dd366e0960cd16e9f55f2fc4e187c6cd2e462120a418f`,
  with linux/amd64 manifest
  `sha256:15094c97303dba3ebf46788a24c622943b28b06378913ab5700b8781e02dbf82`
  and config image ID
  `sha256:554ecbf9f2ff0f8809441f396c3d91aa65cd679ffd168c46fb62dc5815b1fc45`.
  The installed binary accepted `+RTS -N1`; the supported retained-cluster
  rollout again completed **156** steps. Independent proof recorded the exact
  image tuple, **5 / 5** Ready application pods with zero restarts, three
  brokers, **34 / 34** topics, and zero workload residue. The fresh Webapp pod
  `c51c19bc-889d-44f4-8b68-b6094bd02795` stabilized at **14** PID-1 file
  descriptors with zero direct children, Node processes, piped-process temp
  directories, or `jitml-demo-bridge-*` cursors across all topics. The focused
  hash-navigation browser cleanup regression passed **1 / 1** in **0.077s**
  and the exact resource baseline then held for three consecutive samples.
- On that image canonical command **1 / 6** passed **544 / 544** unit tests in
  **93.715s**, followed by an exact zero-restart/zero-residue cluster proof.
  Canonical command **2 / 6** then ran every integration case for
  **1,698.420s**: **154 / 155** passed, including WorkflowMatrix **443.31s**,
  StartRLRun **200.04s**, PPO convergence **733.96s**, inference **1.13s**,
  resolved Tune **18.03s**, and AlphaZero dispatch **4.59s**. The sole failure
  sampled `jitml-coordinator` on `rl.command.linux-cpu` with `consumers: []`.
  Broker logs prove the healthy three-command consumer set hit the configured
  `webSocketSessionIdleTimeoutMillis=300000` at `20:55:00.887Z`; the failing
  stats response landed at `20:55:01.542Z`, and the bridge resubscribed at
  `20:55:01.896Z` with cursor position unchanged. Coordinator and broker UIDs
  and restart counts remained stable, later daemon dispatches succeeded, and
  the complete failed-run post-state proof again reported the exact image,
  **5 / 5** Ready apps, zero restarts, **34 / 34** topics, and zero residue.
- The role-subscription live gate now polls the entire expected route set as one
  sweep, requires two consecutive all-present sweeps, resets the streak on any
  missing subscription, empty consumer array, command failure, malformed JSON,
  or unexpected shape, and retains the last three complete sweep diagnostics on
  exhaustion. Container Haskell lint passes and the focused live assertion
  passes **1 / 1** in **12.71s**. Because this changes the test source, the
  `5060ce86…` image and its command **1 / 6** result remain diagnostic history;
  the binding image must be rebuilt and the canonical sequence restarted from
  **1 / 6**.
- The final repaired image completed the supported build with embedded
  `jitml check-code: ok`, a **611 / 611** zero-warning PureScript build, and an
  installed binary that accepts `+RTS -N1`. Its immutable index/descriptor is
  `sha256:0c94a15d1c49a6ab13e91133c2e6d16a78029be3c7d873e4397f654260bb1e0d`,
  with linux/amd64 manifest
  `sha256:0b923416bb711b02b32e6cd82f4239d57fe3ba55597db7462b0f088960d5a57e`
  and config image ID
  `sha256:2f43386ea36737c9ed87a29134c1e93e1515b6ae771b302820d0f9d1a0fb7e2b`.
  The supported retained-cluster rollout completed **156** steps. Independent
  proof records that exact tuple on every node, **5 / 5** Ready application
  pods with zero restarts, three unchanged brokers, **34 / 34** topics, and
  zero workload residue. The fresh Webapp pod
  `f89d9fc1-b3be-4e6a-8cff-e23a3befefb4` held **14** PID-1 file descriptors
  with zero direct children, Node processes, piped-process temp directories,
  or `jitml-demo-bridge-*` cursors for three consecutive samples. The focused
  role-subscription gate passed **1 / 1** in **12.77s**, the hash-navigation
  browser cleanup regression passed **1 / 1**, and the exact Webapp resource
  baseline recovered for three further consecutive samples.
- On that binding image, canonical command **1 / 6** passed **544 / 544** unit
  tests in **40.70s** (**1** Passed, zero Failed, zero NotRun), and command
  **2 / 6** passed **155 / 155** integration tests in **1,669.09s** (**1**
  Passed, zero Failed, zero NotRun). Command **3 / 6** passed all **72 / 72**
  Playwright cases and **29 / 29** Haskell e2e cases (**2** Passed, zero
  Failed, zero NotRun). Immediate before/after resource proofs retained the
  same Webapp UID, restart count zero, FD baseline **14**, zero child/Node/temp
  residue, and zero bridge cursors on all **34** topics. The immutable-image
  cluster verifier passed after each command.
- The first binding-image attempt at canonical command **4 / 6**, `jitml test
  all --live --linux-cpu`, is diagnostic history rather than closure evidence.
  The Playwright, unit, integration, supervised-learning canonicals,
  reinforcement-learning canonicals, and hyperparameter stanzas passed, but
  `jitml-backends` failed **1 / 24** at the linux-cpu LayerGraph oneDNN
  training assertion for layer-1 input-gradient tolerance. The fail-fast
  report card therefore recorded **6** Passed invocations, **1** Failed, and
  **4** NotRun. The post-failure immutable-image verifier passed with the exact
  image tuple, **5 / 5** Ready application pods, zero restarts, three unchanged
  brokers, **34 / 34** governed topics, zero workload residue, and a healthy
  edge on port `9091`. The next bullet records the resulting repair; this
  failed aggregate remains diagnostic history.
- Root-cause isolation showed that the oneDNN affine ABI received the raw layer
  input while the pure LayerGraph contract first applies the layer-kind input
  transform. Conv2D is fixture layer index `1`, so its raw `WᵀdPre` first
  exposed the missing backward transform. The oneDNN adapter now applies the
  shared LayerGraph transform before device forward/weight-gradient work and
  maps the device input gradient back through the shared inverse transform.
  The focused assertion passed **1 / 1** three consecutive times, and the full
  linux-cpu backend lane passed **24 / 24** (**1** Passed, zero Failed, zero
  NotRun). Because this is production-source change, image `0c94a15d…` and its
  canonical commands **1 / 6** through **3 / 6** remain diagnostic history. A
  new immutable image, retained-cluster rollout, resource proof, and canonical
  restart from command **1 / 6** are required.
- The post-LayerGraph-fix supported build exited **0** with embedded
  `jitml check-code: ok`, a **611 / 611** PureScript build with zero warnings
  and zero errors, and an installed binary that accepts `+RTS -N1`. The new
  immutable index/descriptor is
  `sha256:6e0d57971bf8e6a7c996530a4b434a575237a570c745710f2a150a501da42aa0`,
  with linux/amd64 manifest
  `sha256:8c3c2bb3319b18e1b927cb5e73c88e8ffc55ff756806d7a8a795844975135899`
  and config image ID
  `sha256:d647ab711f7ff277121ac82390a6b4406cedd93c80422d86b3bf360d9bead432`.
  The supported retained-cluster rollout then exited **0** after **156** steps.
  Independent proof recorded that exact tuple on all four nodes, **5 / 5**
  Ready application pods with zero restarts, three unchanged brokers, **34 /
  34** topics, zero workload residue, and healthy edge `:9091`. New Webapp UID
  `185969ce-92f2-4bed-a61d-6e91ee3129b9` stabilized at **14** PID-1 file
  descriptors with zero children, Node processes, piped-process temp
  directories, or bridge cursors for three consecutive samples. The canonical
  block restarted at command **1 / 6** on this binding image.
- On the post-LayerGraph-fix binding image, canonical command **1 / 6** passed
  **544 / 544** unit tests in **40.62s** (whole invocation
  **92.410180923s**) with a journal summary of **1** Passed, zero Failed, and
  zero NotRun. Canonical command **2 / 6** passed **155 / 155** integration
  tests in **1,660.76s** (whole invocation **1,729.499980288s**) with the same
  **1 / 0 / 0** journal outcome. Its **18 / 18** live cases included the real
  workflow matrix, supervised and reinforcement-learning launches, PPO
  convergence, checkpoint, garbage-collection, inference, tuning, AlphaZero,
  and self-play paths. The independent verifier passed after both commands,
  retaining the exact immutable image tuple, **5 / 5** Ready application pods,
  zero restarts, three brokers, **34 / 34** topics, zero workload residue, and
  the healthy edge on port `9091`.
- Canonical command **3 / 6** on that same binding image passed all **72 / 72**
  Playwright cases in **27.8s** and all **29 / 29** Haskell e2e cases in
  **0.12s**. The journal recorded **2** Passed, zero Failed, and zero NotRun in
  **32.957148353s**, with per-stanza invocations of **29.800086445s** and
  **3.157061908s**. Immediate before/after resource proofs retained Webapp UID
  `185969ce-92f2-4bed-a61d-6e91ee3129b9`, restart count zero, FD baseline
  **14**, and zero child processes, Node processes, piped-process temporary
  directories, or bridge cursors for three consecutive samples. The
  post-command immutable-image verifier again passed the exact image tuple,
  **5 / 5** Ready applications, zero restarts, three brokers, **34 / 34**
  topics, zero workload residue, and healthy edge `:9091`. Canonical command
  **4 / 6** followed on the same retained cluster.
- Canonical command **4 / 6**, `jitml test all --live --linux-cpu`, passed all
  **11 / 11** reporter invocations with **11** Passed, zero Failed, and zero
  NotRun in a whole container invocation of **2,487.430443021s**. Its executed
  cases were Playwright **72 / 72**, unit **544 / 544**, integration **155 /
  155**, supervised-learning canonicals **31 / 31**, reinforcement-learning
  canonicals **40 / 40**, hyperparameter **21 / 21**, backends **24 / 24**,
  daemon lifecycle **51 / 51**, Haskell e2e **29 / 29**, negative controls **3
  / 3**, and model convergence **111 / 111**. The integration journal again
  included all **18 / 18** Live scenarios; in particular, the repaired
  LayerGraph oneDNN case passed inside the full backend stanza rather than only
  in the focused gate. The independent post-aggregate verifier retained the
  exact immutable image tuple, **5 / 5** Ready applications, zero restarts,
  three brokers, **34 / 34** topics, zero workload residue, and healthy edge
  `:9091`. Canonical command **5 / 6**, `jitml docs check`, then exited **0**
  with `docs check: ok`; its independent verifier retained the same exact image
  and healthy zero-residue cluster state. Canonical command **6 / 6**, `jitml
  check-code`, then exited **0** with `check-code: ok`; the final independent
  verifier again retained the exact image tuple, **5 / 5** Ready applications,
  zero restarts, three brokers, **34 / 34** topics, zero workload residue, and
  healthy edge `:9091`. The complete six-command binding-image gate is green.
- Closure alignment moved exactly the three Sprint `12.16` rows to Completed,
  leaving **12** later-owned Pending Removal rows, and activated Sprint `19.4`
  in both its phase document and the Haskell status registry. Standards rule M
  then reported **0 / 44** backward edges, **0 / 284** dual-accelerator gates,
  and **0 / 20** accelerator invocations in aggregation validation. The
  post-edit parity gate passed unit **544 / 544** with **1** Passed, zero
  Failed, and zero NotRun in **178.538679068s**; docs and code quality again
  passed, and the verifier retained the same exact zero-residue cluster state.
- Phase `12` requires no Apple hardware under standards rule M. Its keyed
  registry, forwarding shape, and real daemon-process semantics are
  Linux-host-validatable; the real Metal lane and Apple journal/attestation
  refresh remain owned by Sprint `30.4`.

### Validation

```bash
docker compose run --rm jitml jitml test jitml-unit --linux-cpu
docker compose run --rm jitml jitml test jitml-integration --linux-cpu
docker compose run --rm jitml jitml test jitml-e2e --live --linux-cpu
docker compose run --rm jitml jitml test all --live --linux-cpu
docker compose run --rm jitml jitml docs check
docker compose run --rm jitml jitml check-code
```

### Remaining Work

- None.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
