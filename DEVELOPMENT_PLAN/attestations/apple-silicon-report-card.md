# `apple-silicon` Per-Lane Attestation (Sprint 16.14)

**Status**: Authoritative source
**Referenced by**: [../README.md](../README.md),
[../phase-16-apple-silicon-closure.md](../phase-16-apple-silicon-closure.md),
[../phase-17-cross-substrate-and-handoff.md](../phase-17-cross-substrate-and-handoff.md),
[../phase-18-no-caveat-product-handoff.md](../phase-18-no-caveat-product-handoff.md)
**Generated sections**: none

> **Purpose**: The committed `apple-silicon` per-lane report-card fragment that
> Sprint `16.14` owns for the HA topology. Phase `17` (Sprint `17.10`) and Phase
> `18` (Sprint `18.5`) consume this fragment on `linux-cpu` and never re-run the
> `apple-silicon` lane (standards rule M(b)/(d)).

## Host

- Apple M1 Max, macOS 26.5, Metal 4 (64 GiB).
- Fixed host Metal bridge (`jitml internal install-metal-bridge` →
  `.build/host/apple-silicon/libJitMLMetalBridge.dylib`, `metal_bridge_probe: ok`);
  no Tart, SwiftPM, full Xcode, offline `metal`, or keychain state on the core path.
- Live HA `apple-silicon` Kind cluster (Colima aarch64 Docker; one control-plane
  plus three workers), edge `9090`.
- Validated 2026-06-29.

## HA Validation Summary

- Docker/Colima reset for the four-node HA topology: 8 CPU, 12 GiB memory,
  512 GiB disk.
- `./bootstrap/apple-silicon.sh doctor` — passed.
- `./bootstrap/apple-silicon.sh build` — passed after the wrapper selected
  Homebrew `llvm@19` for GHC-compatible `opt`/`llc`; `.build/jitml` was a real
  arm64 Mach-O binary.
- `./bootstrap/apple-silicon.sh up` — HA rollout PASS, **131** steps, edge
  `9090`, all seven publication components ready.
- `./bootstrap/apple-silicon.sh run-daemon` — host daemon acquired
  `apple.metal-runtime=yes`, `apple.metal-bridge=yes`, and the four host command
  topics (`inference`, `training`, `tune`, `rl`).
- `./bootstrap/apple-silicon.sh test` — **8 / 8** stanzas passed on the real
  Apple lane, including the `jitml-backends --apple-silicon` Metal cases.
- `jitml internal seed-demo-checkpoints` — seeded all eight demo checkpoints.
- Direct edge inference — `POST http://127.0.0.1:9090/api/inference` returned
  `HTTP 200` with `kind: InferenceResult`; Pulsar `jitml-host` backlog was `0`.
- Live Playwright product matrix — **15 / 15 PASS** against the Apple edge in
  `mcr.microsoft.com/playwright:v1.49.1-noble`.

Every measurement required for the HA lane was exercised through the real
Apple host Metal path. No Tart VM, SwiftPM-generated kernel package, full Xcode,
offline `metal`, keychain unlock, or containerized Metal execution participated
in the core cache-miss path.

## Historical Defects Fixed to Close the Earlier Lane (all in the worktree)

The live `apple-silicon` inference path (`jitml inference run`, the demo's
checkpoint-backed panels, the live `WorkflowMatrix` inference cell) was blocked by
five real defects — none a product-logic flaw:

1. **Daemon consumer crash-loop** (`Exclusive`→`Failover`,
   `src/JitML/Service/PulsarWebSocketSubprocess.hs`). An `Exclusive` Pulsar-WS
   subscription rejects a second consumer with a non-101 upgrade, so a daemon pod
   that redeploys before the broker reaps its prior consumer crash-loops
   (`hGetLine: end of file`) and serves nothing. `Failover` admits the new consumer
   as standby and promotes it cleanly.
2. **Reply-format mismatch** (`daemonWorkloadDispatcherForwardingInference`,
   `src/JitML/Service/Runtime.hs`). The cluster forwarded the request as an
   `AppleInferenceCommand` whose host reply was an `AppleInferenceEvent` carrying
   MinIO output *refs*; the CLI/Webapp parse `kind: InferenceResult` (inline
   values). The cluster now forwards the raw `RunInference` and the host Engine
   replies with an `InferenceResult` directly — the converged values model.
3. **In-process WS auto-reconnect** (`consumerWorkerScript`,
   `src/JitML/Service/PulsarWebSocketSubprocess.hs`). The long-lived consumer
   reconnects on a transient `close` instead of exiting, so a dropped WS no longer
   tears down the worker.
4. **Per-worker dedup MVar** (`startDaemonConsumerWorkers`, `src/JitML/App.hs`). The
   dispatch *compute* runs inside `modifyMVar routerRef`; a single shared MVar
   serialized every worker, so a long host Metal training/RL/tune workload blocked
   the inference worker past a client's bounded reply poll. Each worker now owns its
   dedup router (full Live suite wall-time dropped 227s→78s).
5. **Forward all inference-domain commands** (`daemonWorkloadDispatcherForwardingInference`).
   The forwarder forwarded only `RunInference`; `CheckpointCompareCommand` /
   `AdversarialMoveCommand` (the compare / connect4 panels) were dropped. The
   cluster now forwards every inference-domain command raw to the host Engine.

Plus a test-bug fix: the `jitml-sl-canonicals` live MNIST convergence cell hardcoded
the `LinuxCPU` (oneDNN) device, which cannot link on the Mac; it now trains through
the publication's substrate device, so the apple-silicon lane runs genuine live
Metal MNIST convergence. And a demo ack-kind alignment (`src/JitML/Web/Server.hs`):
the compare / connect4 async acks render their `…Result` kind (consistent with the
inference / generic / image panels) so the report-card browser probe sees every
panel serve its result kind.

The superseded `AppleInferenceCommand` / `AppleInferenceEvent` refs RPC is recorded
in [../legacy-tracking-for-deletion.md](../legacy-tracking-for-deletion.md).

## Validation Gate (all green)

| Command | Result |
|---|---|
| `./bootstrap/apple-silicon.sh up` | HA rollout PASS, 131 steps, edge `:9090`, seven publication components ready |
| `./bootstrap/apple-silicon.sh run-daemon` | host Metal daemon acquired runtime, bridge, and all four host command topics |
| `./bootstrap/apple-silicon.sh test` | 8/8 stanzas PASS on the real Apple lane |
| Direct `POST /api/inference` through edge `:9090` | `HTTP 200`, `kind: InferenceResult`; host backlog 0 |
| Live Playwright product matrix | 15/15 PASS |

`jitml-backends --apple-silicon` compiled real MSL in-process via
`MTLDevice.makeLibrary(source:)` and executed on the M1 GPU. The browser/product
surface used eight seeded demo checkpoints and the host Metal daemon as the
Engine behind the cluster-forwarding path.
