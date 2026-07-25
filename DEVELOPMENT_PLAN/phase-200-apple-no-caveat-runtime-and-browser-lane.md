# Phase 200: Apple No-Caveat Runtime and Browser Lane

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Apple No-Caveat Runtime and Browser Lane. Single-session phase migrated from legacy Sprint 16.11 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 200.1: Apple No-Caveat Runtime and Browser Lane [✅ Done]

**Status**: Done (re-closed 2026-06-22 on the live `apple-silicon` M1 Max lane —
8/8 stanzas, 20/20 live integration, report card 7/7, Playwright 11/11; the
committed fragment is
[attestations/apple-silicon-report-card.md](attestations/apple-silicon-report-card.md)).
**Implementation**: `src/JitML/Service/PulsarWebSocketSubprocess.hs`
(`Failover` subscription + in-process WS auto-reconnect),
`src/JitML/Service/Runtime.hs` (`daemonWorkloadDispatcherForwardingInference`
raw + all-inference-command forward), `src/JitML/App.hs`
(`startDaemonConsumerWorkers` per-worker dedup router), `src/JitML/Web/Server.hs`
(compare/connect4 ack `…Result` kind), `test/sl-canonicals/Main.hs` (live MNIST
convergence on the publication substrate), `playwright/jitml-demo.spec.ts` +
`playwright/playwright.config.ts` (async-contract timeouts + retries),
`bootstrap/apple-silicon.sh`.
**Docs to update**: `documents/engineering/apple_silicon_metal_headless_builds.md`,
`documents/engineering/purescript_frontend.md`,
`documents/engineering/training_workloads.md`, `system-components.md`

### Objective

Validate the full no-caveat product on Apple Silicon through the fixed host
Metal bridge and host-resident workload placement.

### Deliverables

- `bootstrap/apple-silicon.sh test` runs every no-caveat SL/RL/AlphaZero/tuning
  workflow through the host Metal bridge, persists/reloads checkpoints, serves
  the demo, and passes the full Playwright product matrix.
- Apple Metal-backed training, RL, tuning, inference, and AlphaZero work remains
  host-resident; no Linux Kubernetes worker Job attempts to execute Metal work.
- The lane fails fast on missing datasets, missing checkpoints, missing host
  command events, placeholder browser data, synthetic report-card rows, or
  absent Playwright product assertions.
- This sprint **owns and commits the `apple-silicon` per-lane report-card
  fragment** (within-substrate reproducibility + measured no-caveat rows)
  produced on the Mac host. The Phase `17` aggregation (Sprint `17.8`) and the
  Phase `18` handoff consume this committed fragment on `linux-cpu`; they never
  re-run the `apple-silicon` lane (standards rule M(b)/(d)).

### Validation

- `bootstrap/apple-silicon.sh test`
- `jitml test all --apple-silicon`
- `jitml test jitml-e2e --apple-silicon`
- `docker compose run --rm jitml jitml docs check`
- `docker compose run --rm jitml jitml check-code`

### Remaining Work

- **Host Apple Metal lane re-validated (2026-06-20, Apple M1 Max, macOS 26.5,
  Metal 4) on the current worktree** — i.e. after the Pulsar ML-Workflow
  convergence (Phases `5`/`10`/`11`/`12`) and Phase `2` Sprint `2.13` landed, a
  no-regression check. Host-native (GHC `9.12.4`): fixed Metal bridge installed
  (`jitml internal install-metal-bridge` → `libJitMLMetalBridge.dylib`,
  `metal_bridge_probe: ok`); **`jitml-backends --apple-silicon` 17/17** (real MSL
  compiled in-process via `MTLDevice.makeLibrary` and dispatched on the M1 GPU,
  `38.2s`); pure-logic stanzas host-native `jitml-unit 208/208`,
  `jitml-daemon-lifecycle 35/35`, `jitml-e2e 23/23`. The Apple Mac-hardware
  blocker the plan cited is **resolved**.
- **Live cluster up + 18/20 live integration green (2026-06-21).** With Phase `2`
  Sprint `2.14`'s regcred imagePullSecret, `bootstrap/apple-silicon.sh up`
  **completed** the 110-step rollout on the M1 Max to a ready cluster (no blocking
  429). `cabal test jitml-integration -p Live` against it: **18/20 pass** — live
  MinIO/Pulsar/Harbor round-trips, daemon command-topic subscriptions, daemon
  placement (Training/RL/Tune by substrate), PPO cartpole convergence, checkpoint
  snapshot + GC, tune persist/replay, AlphaZero self-play. **2 fail** (`live jitml
  inference run`, `live WorkflowMatrix`): both `inference result: no matching reply
  received from the Engine`. **Root cause (2026-06-21, definitive):** the host
  Metal daemon is healthy (`activeRole = Engine`, Metal bridge ok, edge MinIO ok —
  the seeded checkpoints `live-inference-…` and `workflow-matrix-inference` are
  confirmed present in `jitml-checkpoints`), but its **Pulsar-WS subscription
  acquisition is unreliable**. The host daemon subscribes to exactly four topics —
  `inference.command`, `training.host-command`, `tune.host-command`,
  `rl.host-command` (all `.apple-silicon`, as `jitml-host`) — and **every one
  intermittently fails with `pulsarSubscribe: node exit 1: Received network error
  or non-101 status code`** (the WebSocket upgrade through the Envoy edge is
  rejected). The daemon records these as `failed transient` **but does not retry to
  success**, so `acquiredSubscriptionIds` omits them, **no `daemonConsumerWorkerLoop`
  is spawned** for them, `inference.command` deliveries are never consumed by a
  worker (no `service: …` outcome is logged during the test), and `readyz` stays
  `503`. The apple inference RPC flows over **`inference.command`** (not the
  `inference.request` Work\* consumer), so a dropped `inference.command` worker = no
  reply = the CLI's "no matching reply". (The single passing Pulsar round-trips in
  `jitml-integration` open one WS at a time; the daemon opens four concurrently at
  startup, which is what trips the edge.)
  - **Secondary issue (`src/JitML/Service/Workload.hs:491`):** even once the
    subscription is fixed, `runInferenceRequestWithWeightedInference` publishes a
    reply only on `Right`; on `Left` it returns `Left (SETransient …)` and publishes
    nothing, so a genuine load/Metal error would still surface as a CLI timeout
    rather than a clear error. Worth fixing alongside (publish a visible error reply
    / log the `ServiceError`).
  - **Fix landed (2026-06-22) — host-daemon subscription acquisition retry.**
    `subscribeDaemonTopics` (`src/JitML/Service/Consumer.hs`) now retries transient/
    timeout acquisition failures (`daemonSubscriptionAcquireAttempts = 8`; the node
    WS subprocess spawn latency spaces the attempts, so no `MonadIO`/delay and the
    `HasPulsar`-only constraint is preserved). **Validated:** host-native `jitml-unit`
    208/208, `jitml-daemon-lifecycle` 35/35, hlint + fourmolu clean; on the live M1
    Max host the restarted daemon now acquires **all four** host subscriptions
    (`inference.command` + `training/tune/rl.host-command` each show 1 broker
    consumer). This removes the host-side acquisition flakiness.
  - **Remaining root cause (2026-06-22, definitive) — the cluster daemon does not
    forward.** With the host daemon healthy, the apple inference still fails because
    the **in-cluster `jitml-service` (`Cluster + ForwardToHost`) consumes
    `inference.request.apple-silicon` (broker `msgInCounter = 2`) but never publishes
    to `inference.command.apple-silicon` (`msgInCounter = 0`)** — so the host daemon's
    now-healthy `inference.command` consumer never receives anything. Its pod logs
    spam `service: consumer worker error: pulsarConsumerWorker: fd:N:
    Data.ByteString.hGetLine: end of file` — the in-cluster node Pulsar-WS consumer
    subprocess dies repeatedly. So the forward leg in
    `daemonWorkloadDispatcherForwardingInference` (`Runtime.hs:660` →
    `publishAppleInferenceRpcCommand`) never completes. Note the cluster pod runs the
    pre-fix `jitml:local` image, so the host-side retry does not reach it.
  - **Exhaustive static verification (2026-06-22) — every forward step is correct,
    so the remaining unknown is runtime-only.** Checked against code + live broker:
    (a) the request **is consumed and acked** (`msgBacklog = 0`, `unackedMessages = 0`,
    `msgRateRedeliver = 0`); (b) `renderInferenceRequest`↔`parseInferenceRequest`
    **round-trip cleanly** — `inferenceRequestFromFields` requires exactly the
    `call-id`/`experiment-hash`/`reply-topic`/`input` fields `renderInferenceRequest`
    emits; (c) `parseAppleInferenceEvent` requires an `envelope:` line a `RunInference`
    payload lacks, so it does **not** false-match; (d) the forward target is the
    correct `inference.command.apple-silicon`; (e) **`invokeNode` propagates exit
    codes** — a producer/consumer subprocess failure returns `Left` (→ NACK →
    backlog/redeliver > 0), and the producer only exits 0 *after* the broker
    publish-ack. **Correction:** an earlier note here speculated the producer "returns
    success without landing" — point (e) rules that out (a real publish either lands,
    or `Left`→NACKs and shows backlog). The consistent reading is instead that the
    **forward never invokes the producer**: the message is acked via the non-forwarding
    path while `inference.command` stays `0` and `inference.result` stays `0`. Pinning
    which of {the WS-delivered payload differs from clean text so `parseInferenceRequest`
    returns `Nothing` and it falls through; the delivery is mis-routed; the consumer
    `hGetLine: EOF` crash-loop drops this specific delivery} is true requires
    **runtime instrumentation inside the cluster daemon** (log the delivered payload +
    the dispatch branch), which needs a `jitml:local` rebuild + cluster redeploy.
  - **Fix direction (focused next pass):** (1) add dispatch-branch + delivered-payload
    logging to `daemonWorkloadDispatcherForwardingInference`, rebuild + reload
    `jitml:local`, restart the `jitml-service` pod, re-run the 2 Live inference cases,
    and read which branch fires; (2) fix the localized cause (payload framing /
    routing / consumer `hGetLine: EOF` resilience); (3) fix the `Workload.hs:491`
    silent-`Left` (publish a visible error reply). This needs a cluster image redeploy
    cycle — deferred to a focused pass. The host-daemon acquisition retry above is the
    first installment and is already landed + validated.
### Live Closure (2026-06-22, Apple M1 Max)

The live `apple-silicon` lane closed. The "cluster daemon does not forward" /
`hGetLine: end of file` symptom in the dated notes above was root-caused — on the
**live cluster** — to a chain of five real daemon/forwarding defects (none a
product-logic flaw), all fixed in the worktree, plus a test-bug fix and a demo
ack-kind alignment:

1. **`Exclusive`→`Failover` daemon consumer subscription**
   (`PulsarWebSocketSubprocess.hs`). An `Exclusive` subscription rejects a second
   consumer with a non-101 WS upgrade, so a redeployed pod crash-loops
   (`hGetLine: EOF`) before the broker reaps the prior consumer; `Failover` admits
   the new consumer as standby and promotes it cleanly. (This was the actual cause
   of the 28-hour crash-loop the dated notes mis-read as "not forwarding"; a `scale
   0→1` cleared the wedge and the daemon then forwarded `inference.command` 0→1.)
2. **Raw `RunInference` forward, not `AppleInferenceCommand`**
   (`daemonWorkloadDispatcherForwardingInference`, `Runtime.hs`). The host now
   replies with an `InferenceResult` (inline values) the CLI/Webapp parse — the
   `AppleInferenceEvent` refs reply never matched. (Superseded RPC → legacy ledger.)
3. **In-process WS auto-reconnect** in `consumerWorkerScript` — a transient WS
   `close` reconnects instead of exiting the worker.
4. **Per-worker dedup MVar** (`startDaemonConsumerWorkers`, `App.hs`). The dispatch
   compute ran inside one shared `modifyMVar routerRef`, so a long host Metal
   training/RL/tune workload blocked the inference worker past a client's bounded
   reply poll (the deterministic 1/20 Live failure). Per-worker routers removed the
   head-of-line blocking (Live-suite wall-time 227s→78s).
5. **Forward every inference-domain command** (`Runtime.hs`). The forwarder
   forwarded only `RunInference`; `CheckpointCompareCommand`/`AdversarialMoveCommand`
   (the compare/connect4 panels) were dropped. The cluster now forwards all
   inference-domain commands raw to the host Engine.

Plus: `test/sl-canonicals/Main.hs` live MNIST convergence trained the publication's
substrate device (was a hardcoded `LinuxCPU` oneDNN device that cannot link on the
Mac), so the apple-silicon lane runs real Metal MNIST convergence (`OK 252s`,
clears threshold); `Web/Server.hs` renders the compare/connect4 async acks with
their `…Result` kind (consistent with the inference panels), so the report-card
browser probe sees every panel serve its result kind; and `playwright/*` raises the
async `expect` timeouts + `retries` for the Webapp→host-Metal-Engine websocket
round trip.

Validation (live `apple-silicon` cluster + host Metal daemon, M1 Max):
`jitml test all --apple-silicon` **8/8 stanzas** (`jitml-backends` 17/17 on the M1
GPU); `cabal test jitml-integration -p /Live/` **20/20** (both inference cases
green); live report card **7/7 measured rows** (`sl_final_loss=0.65`,
`rl_final_reward=131.25`, `alphazero_arena_win_rate=0.75`, `tune_best_objective=1.0`,
`jit_cache_hit_rate=1.0`, `daemon_healthz=200`, `browser_product_matrix=5/5`);
`measureBrowserProductMatrix` **5/5** (all five panels serve their result kind);
live Playwright **11/11** (8 first-try + 3 retried-and-passed for async-latency
wobble); `docker compose build jitml` `check-code: ok`. The committed fragment is
[attestations/apple-silicon-report-card.md](attestations/apple-silicon-report-card.md).
The historical "remaining slice" notes below predate this closure.

- **(superseded) Remaining for full Sprint `16.11` closure:** fix the host-daemon inference
  reply path (the 2 Live inference cases), then run the `measureBrowserProductMatrix`
  + Playwright product matrix (host tooling present: node v22 / `npx`), and commit
  the `apple-silicon` per-lane report-card fragment for Phases `17`/`18`.
- **Superseded note (now resolved):** the earlier "live slice needs the
  cluster-pull foundation" blocker is closed by Sprint `2.14` (the live Apple
  cluster now comes up authenticated). The original text follows for history — the
  cluster-pull blocker it describes
  (colima containerd-image-store ↔ `kind load` / Docker Hub 429). The durable fix
  is jitML's own Phase `2` Sprint `2.14` in-cluster `imagePullSecret`
  containerd-auth mechanism. **Technical finding (2026-06-20):** authenticating
  the kind node's pulls cannot be a quick `containerdConfigPatches` hack — the CRI
  `registry.configs.<host>.auth` form is deprecated in containerd 1.7 and removed
  in 2.x (modern kind nodes use `config_path`/`hosts.toml`, which carries
  mirrors/TLS but **not** auth), so reliable authenticated in-cluster pulls require
  Kubernetes **`imagePullSecret`** wiring across the chart namespaces (or a
  containerd credential setup) — exactly the owned, self-contained mechanism Sprint
  `2.14` lands. This sprint flips to `✅ Done` (and commits the `apple-silicon`
  per-lane report-card fragment for Phases `17`/`18`) now that that mechanism has
  landed and the live slice runs green.
- **Apple non-live surface re-validated (2026-06-16, Apple M1 Max host).** The
  fixed Metal bridge built and its probe succeeded; host-native stanzas passed:
  `jitml-unit 197/197` (after the stale demo-panel golden fix), `jitml-rl-canonicals
  29/29`, `jitml-hyperparameter 16/16`, `jitml-daemon-lifecycle 34/34`,
  `jitml-sl-canonicals 24/24` (offline), and `jitml-backends --apple-silicon`
  `17/17` (real MSL compiled in-process via `MTLDevice.makeLibrary` and dispatched
  on the M1 GPU, `91.9s`). The live `apple-silicon` cluster lane
  (`bootstrap/apple-silicon.sh test`, live `jitml-integration` / `jitml-e2e` /
  Playwright) was **not** re-exercised this session; it remains blocked by Phases
  `13`/`14` (the same checkpoint-backed browser surface and per-family checkpoint
  serving that block `linux-cpu` Playwright) regardless of the Apple hardware
  being present.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
