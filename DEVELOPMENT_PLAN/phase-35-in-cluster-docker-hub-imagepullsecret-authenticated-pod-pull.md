# Phase 35: In-cluster Docker Hub `imagePullSecret` (authenticated pod pulls)

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: In-cluster Docker Hub imagePullSecret (authenticated pod pulls). Single-session phase migrated from legacy Sprint 2.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 35.1: In-cluster Docker Hub `imagePullSecret` (authenticated pod pulls) [✅ Done]

**Status**: Done — the live Apple cluster bring-up **completed** with the regcred
imagePullSecret. On the M1 Max host, `bootstrap/apple-silicon.sh up` ran the full
**110-step** phased rollout to a ready `cluster-publication.json` (all components
`"ready"`, every pod Running/Completed) with the `regcred`-bound `platform`
default ServiceAccount — **no blocking 429** (the same rollout previously died at
MinIO step 40 on a cold host). Two transient `ImagePullBackOff` events
(grafana, kube-state-metrics — pods that pull via non-default SAs) self-recovered
and ended Running; a follow-up may widen regcred coverage beyond the default SA,
but it did not block the rollout. Offline-validated: `cabal build` clean
host-native, `jitml-unit` 208/208, `jitml-integration -p rollout` 3/3,
hlint/fourmolu clean, `docs check: ok`, `regcred.yaml` docker.io-only + gitignored.
**Implementation**: `src/JitML/Bootstrap.hs` (`discoverHostDockerHubRegcred`,
`renderRegcredManifest`, `regcredManifestPath`, materialize in
`materializeBootstrapFiles`, apply step in `livePreGrantSubprocessesForPort`)
**Docs to update**: `documents/engineering/cluster_topology.md`,
`system-components.md`, `legacy-tracking-for-deletion.md`
**Doctrine**: `Reconcilers: Idempotent Mutation as a Single Command`,
`Subprocesses as Typed Values`

### Objective

Make the Kind cluster's pods pull Docker Hub images **authenticated**, closing the
cold-host **429** at the layer that actually pulls — the node's containerd /
kubelet — rather than via `kind load` (which Sprint `2.13` showed is broken on a
containerd-image-store host). This is the durable fix the live `apple-silicon`
(and colima `linux-cpu`) clusters need, contributing to
[Exit Definition](README.md#exit-definition) item 4.

### Deliverables

- The bootstrap materializes an in-cluster **`regcred`** `dockerconfigjson` Secret
  from the host's Docker Hub login — the minimal `docker.io`-only `auths`
  projection (private-registry / Harbor creds are filtered out) — into the
  **gitignored** `.build/runtime/regcred.yaml`
  (the credential never enters the repo tree), and binds it to the `platform`
  namespace's `default` ServiceAccount (`imagePullSecrets`), applied **before** any
  release pulls. Every pod in `platform` then pulls Docker Hub authenticated.
- Reads — never writes — `~/.docker/config.json` (honors the bootstrap no-touch
  invariant). Graceful: when the host is not logged in, only the namespace is
  declared (anonymous fallback, no failure). Idempotent (`kubectl apply`).
- **Relationship to Sprint `2.13`:** this supersedes the pre-pull as the *primary*
  429 fix on any docker store (it needs no `kind load`); the Sprint `2.13` host
  pre-pull remains a warm-cache optimization on classic overlay2 hosts. It is
  jitML's own, self-contained containerd-auth mechanism, which can later be
  extended in-place (credential-helper resolution, cred forwarding into the
  in-container `linux` bootstrap).
  - Scope note: the host-native `apple-silicon` bootstrap reads the host login
    directly; the **in-container** `linux-cpu` / `linux-cuda` bootstrap's docker
    client is logged out, so `regcred` is empty there until a future jitML
    enhancement forwards the host cred into the container frame.

### Validation

- `cabal build exe:jitml` clean (host-native); `jitml-unit` **208/208**,
  `jitml-integration -p rollout` **3/3** (host-native); hlint/fourmolu clean
  (baked tools); `jitml docs check: ok`. `regcred.yaml` materializes with the
  `docker.io`-only auth, no Harbor leak, and is `git check-ignore`d.
- **Live `apple-silicon` closure (in progress):** `bootstrap/apple-silicon.sh up`
  on this M1 Max host completes the phased rollout with the `regcred`-bound default
  SA and **no Docker Hub 429** during the MinIO/Pulsar/Harbor Helm waits.

### Remaining Work

- None for the owned obligation (authenticated in-cluster pulls; live Apple bring-up
  completed). **Follow-up (minor):** widen regcred beyond the `platform` default
  ServiceAccount so pods using chart-specific ServiceAccounts (grafana,
  kube-state-metrics) also pull authenticated — they transiently `ImagePullBackOff`
  on docker.io before self-recovering; harmless to the rollout but worth closing.
  This is a self-contained extension of jitML's own `imagePullSecret` mechanism.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
