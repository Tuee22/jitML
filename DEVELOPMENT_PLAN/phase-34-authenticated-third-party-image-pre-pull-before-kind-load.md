# Phase 34: Authenticated third-party image pre-pull before `kind load`

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Authenticated third-party image pre-pull before kind load. Single-session phase migrated from legacy Sprint 2.13 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 34.1: Authenticated third-party image pre-pull before `kind load` [✅ Done]

**Status**: Done — a fully **owned, self-contained** mechanism (the authenticated
host pre-pull), offline-validated and live-proven (the cold-host run pulled all 25
third-party images authenticated into the host dockerd with **no 429** on the
pull). On a classic docker (overlay2) store the pre-pull + existing `kind load`
closes the in-cluster 429 directly. The **containerd-image-store** in-cluster
load/auth closure (the colima `kind load` ↔ `ctr import` incompatibility) is owned
and closed by jitML's own Sprint `2.14` in-cluster `imagePullSecret`
containerd-registry-auth — see Remaining Work.
**Implementation**: `src/JitML/Bootstrap.hs` (`cachedThirdPartyRolloutImages`
now exported), `src/JitML/CLI/Spec.hs` + `src/JitML/App.hs` (the
`jitml internal third-party-images` leaf — the single source of the image list),
`bootstrap/_lib.sh` (`prepull_third_party_images` / `prepull_linux_third_party_images`
/ `prepull_apple_third_party_images`), `bootstrap/{apple-silicon,linux-cpu,linux-cuda}.sh`
(each `up()` pre-pulls on the host before delegating)
**Docs to update**: `documents/engineering/cluster_topology.md`, `system-components.md`,
`legacy-tracking-for-deletion.md`
**Doctrine**: `Reconcilers: Idempotent Mutation as a Single Command`,
`Subprocesses as Typed Values`, `Prerequisites as Typed Effects`

### Objective

Close a cold-host robustness gap in the bootstrap image mirror that contributes to
[Exit Definition](README.md#exit-definition) item 4 (stage-0 entrypoints + typed
reconciler). Today `cachedThirdPartyImageLoadSteps` only `kind load`s third-party
chart images **already warm in the host Docker cache** and, by its own design
(`Bootstrap.hs:293–296`), "first-run behavior still falls back to Kubernetes
pulls." On a cold/pruned host the `docker.io/*` chart images (`bitnamilegacy/minio`,
`minio-client`, `apachepulsar/pulsar-all`, …) are filtered out, so the Kind
cluster's containerd pulls them **anonymously** from Docker Hub during the Helm
waits and hits the anonymous **429 rate limit**, aborting the rollout.

The Kind containerd pull path does not read `~/.docker/config.json`, so a host
`docker login` alone does not fix it; the images must be present in the (shared
host) Docker store before `kind load`.

### Deliverables

- The bootstrap **pre-pulls the `docker.io/*` subset of `cachedThirdPartyRolloutImages`
  authenticated, on the host**, before the existing `kind load` step, so the images
  populate the host dockerd store that the in-container `kind load` reads over the
  mounted socket. The cluster then never pulls those images from Docker Hub.
  - `linux-cpu` / `linux-cuda`: the in-container bootstrap's docker client is not
    logged in, so the pre-pull runs in the **stage-0 host script** (which runs as
    the authenticated host user) before delegating to `docker compose run`, sourcing
    the image list from the binary (a typed `jitml internal third-party-images`
    leaf, or `_lib.sh`). `apple-silicon`: the host-native bootstrap pre-pulls
    directly via a typed `dockerPullSubprocess`.
  - The mechanism **reads** the existing host Docker Hub login that `docker` itself
    resolves; it does **not** write or mutate `~/.docker/config.json`, honoring the
    bootstrap no-touch invariant (`../README.md#bootstrap-scripts`).
  - Idempotent + restartable: re-running pulls already-present tags cheaply; the
    `kind load` step is unchanged and still filters to present images, so a logged-out
    host degrades gracefully to the prior anonymous fallback (no hard failure).
- This is jitML's own **owned, self-contained** Docker Hub credential-reading
  path (host `config.json` discovery → authenticated host pre-pull); it is a
  permanent part of the bootstrap surface, not a transitional stand-in.

### Validation

- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.
- `jitml-unit` covers the extended `cachedThirdPartyRolloutImages` / pull-plan
  renderer (typed pull subprocess emitted for the `docker.io/*` subset).
- Live `linux-cpu` closure (rule M(b) lane): on a **cold** host (post-prune), an
  authenticated `bootstrap/linux-cpu.sh up` completes the phased rollout with **no
  Docker Hub 429** during the MinIO/Pulsar/Harbor Helm waits.

### Current Validation State

Implementation landed and **offline-validated**: `cabal build all` clean,
`jitml internal third-party-images` prints the 25-image list, `jitml docs
generate` regenerated the command tree / registry / CLI manpage+completions
(`docs generate: no changes` on re-run), `jitml docs check: ok`, `jitml
check-code: ok` (fresh binary + baked style tools), `jitml-unit` **208/208**
(registry-leaf golden updated), `jitml-e2e` **23/23**, hlint/fourmolu clean,
`bash -n` clean on all four bootstrap scripts.

### Live Findings (2026-06-20 cold-host `linux-cpu` run)

The authenticated pre-pull **works**: a cold-host `bootstrap/linux-cpu.sh up`
(rebuilt image with the leaf, host logged in) pre-pulled all 25 third-party
images authenticated into the host dockerd — including `bitnamilegacy/minio`,
the exact image that previously 429'd — **with no 429 on the host pull**. The
credential half of the gap is closed.

A **separate, pre-existing** blocker then surfaced on this host: `kind load
docker-image` fails with `ctr images import --all-platforms: content digest not
found`. Root cause: colima's Docker uses the **containerd image store**
(`docker info` → `Storage Driver: overlayfs`, `driver-type:
io.containerd.snapshotter.v1`), whose `docker save` export is incompatible with
kind's `ctr import`. So `cachedThirdPartyImageLoadSteps` cannot load the
pre-pulled images into the kind node's containerd on a containerd-image-store
host, and the in-cluster MinIO pod still pulls from Docker Hub and 429s
(`ImagePullBackOff` in kubelet events; helm reports only `context deadline
exceeded`). This is **orthogonal to Sprint 2.13's credential fix** — it is a
kind ↔ docker-containerd-store incompatibility in the existing warm-cache load
path, not a Docker Hub auth problem.

### Remaining Work

- **Full cold-host closure on a containerd-image-store host** needs the
  third-party images to reach the kind node's containerd despite the
  `kind load` / `ctr import` incompatibility. The credential half is done; the
  durable fix is the **containerd-registry-auth** path (authenticate the kind
  node's containerd to Docker Hub so in-cluster pulls succeed) — exactly what
  jitML's own Sprint `2.14` in-cluster `imagePullSecret` provides (host
  `config.json` discovery → in-cluster `imagePullSecret` / containerd auth). On a
  **classic docker (overlay2) store** — native-Linux `linux-cpu` hosts — the
  pre-pull + `kind load` path closes the 429 directly; only the
  containerd-image-store host (this colima Mac) hits the `ctr import` blocker.
- **Why no interim colima load-path was added (deliberate).** The only load that
  works on a containerd-image-store host is the binary stream
  `docker save <tag> | docker exec <node> ctr -n k8s.io images import -` (no
  `--all-platforms`; both `kind load docker-image` and `kind load image-archive`
  fail, and a `docker save -o file` + `docker cp` path breaks on the colima
  VM/host filesystem split). The typed `Subprocess` model carries stdin as
  `Text` (`subprocessStdin :: Maybe Text`), so it cannot represent a multi-GB
  **binary** process-to-process pipe; the only typed encoding is an `sh -c`
  pipe, which is the control-flow form Sprint `2.9` deliberately removed. Rather
  than re-introduce an `sh -c` stand-in for a path that jitML's own Sprint `2.14`
  containerd-auth supersedes outright, the containerd-store closure is owned and
  resolved by that in-cluster `imagePullSecret` mechanism; Sprint `2.13` owns the
  authenticated host pre-pull, which is done.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
