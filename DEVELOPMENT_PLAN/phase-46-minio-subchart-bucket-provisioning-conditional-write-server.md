# Phase 46: MinIO Subchart, Bucket Provisioning, Conditional-Write Server

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: MinIO Subchart, Bucket Provisioning, Conditional-Write Server. Single-session phase migrated from legacy Sprint 4.3 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 46.1: MinIO Subchart, Bucket Provisioning, Conditional-Write Server [✅ Done]

**Status**: Done
**Implementation**: `chart/values.yaml`,
`src/JitML/Storage/Buckets.hs`,
`src/JitML/Cluster/Readiness.hs`,
`src/JitML/Service/MinIOSubprocess.hs`
**Docs to update**: `documents/engineering/cluster_topology.md`,
`documents/engineering/checkpoint_format.md`

### Objective

Install MinIO in distributed mode (4 replicas), provision the seven jitML
buckets, and pin the server to a release with S3 conditional-write support
(`If-None-Match`, `If-Match`) — `RELEASE.2024-08-26T15-33-07Z` or later.

### Deliverables

- `minio` subchart at the conditional-write-supporting pin in
  `chart/Chart.yaml`.
- Distributed mode with 4 replicas, each backed by a manual PV under
  `./.data/platform/minio/pv_<i>/` (Sprint `3.2`).
- `provisioning.buckets` block creates the seven buckets enumerated in
  [system-components.md → MinIO Bucket
  Layout](system-components.md#minio-bucket-layout): `harbor-registry`,
  `jitml-checkpoints`, `jitml-datasets`, `jitml-transcripts`, `jitml-trials`,
  `jitml-tensorboard`, `jitml-artifacts`.
- `src/JitML/Storage/Buckets.hs` is the typed source for the bucket layout;
  `chart/values.yaml` carries the Helm `minio.provisioning.buckets` block.
- Bootstrap materialization removes legacy standalone MinIO values fragments
  from `chart/templates/minio-values.yaml` and `chart/minio-values.yaml` so the
  chart has one values owner.
- HTTPRoutes for `/minio/console` and `/minio/s3` (Sprint `3.4`).
- `JitML.Service.MinIOSubprocess` is the live HTTP-backed `HasMinIO`
  interpreter. It uses `curl --aws-sigv4`, signs the canonical path-style S3
  object URL, sends routed edge requests with `--request-target /minio/s3/...`
  so Envoy can rewrite to MinIO's upstream path, and maps MinIO `412` responses
  to the doctrine's `SEConflict`.

### Validation

1. `src/JitML/Storage/Buckets.hs` enumerates the seven current bucket names.
2. `chart/values.yaml` includes each typed bucket under
   `minio.provisioning.buckets`.
3. `materializeBootstrapFiles` removes legacy standalone MinIO values files
   and remains idempotent on the second pass.
4. The cleanup row in
   [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is
   marked completed for the standalone values fragment.
5. Live Linux CPU validation on 2026-05-18 confirms the installed MinIO rollout
   reaches Ready.
6. Live Linux CPU validation on 2026-05-18 confirms all seven typed buckets
   exist through `JitML.Cluster.Readiness.minioBucketReadinessSubprocess`,
   which runs the Bitnami in-pod MinIO client (`mc`) against the local service
   endpoint and checks every bucket from `JitML.Storage.Buckets.bucketNames`.
7. `cabal test jitml-integration` covers the rendered
   `JitML.Service.MinIOSubprocess` command surface: explicit local demo
   credentials, `curl --aws-sigv4`, `If-None-Match: *`, canonical signed S3
   URLs, routed Envoy `--request-target /minio/s3/...`, and list-response XML
   parsing.
8. Live Linux CPU validation on 2026-05-19 exercises the `HasMinIO`
   capability class against the running MinIO service, both through a direct
   service port-forward and through the routed
   `http://127.0.0.1:9091/minio/s3` edge surface: first write returns an
   `ETag`, duplicate `If-None-Match: *` write returns `SEConflict`, pointer
   CAS from the current ETag succeeds, stale-Etag CAS returns `SEConflict`,
   `minioReadObject` returns the updated pointer body, `listObjects` returns
   the written keys, and `deleteObject` removes them.

### Closure State

- The typed `HasMinIO` capability class exposes the full conditional-write
  surface (`putBlobIfAbsent`, `casPointer`, `listObjects`,
  `deleteObject`) with `ETag` newtype. `JitML.Service.FilesystemMinIO`
  honours the same conditional semantics in local tests, and
  `JitML.Service.MinIOSubprocess` is the subprocess-backed live HTTP S3
  implementation for running MinIO.
- `JitML.Service.MinIOSubprocess.minioSettingsForLocalEdge` models the routed
  Envoy surface by signing the upstream path-style S3 URL and passing
  `--request-target /minio/s3/...` to curl. This keeps SigV4 canonical paths
  aligned with the path that MinIO sees after the HTTPRoute rewrite.
- `JitML.Cluster.Readiness.minioBucketReadinessSubprocess` is wired into
  `platformReadinessSubprocesses` after the MinIO rollout check and before
  Pulsar topic bootstrap. It executes the Bitnami in-pod `mc` binary from
  `statefulset/minio`, aliases `http://minio.platform.svc.cluster.local:9000` with
  the chart's explicit local demo credentials, and checks every bucket from
  `JitML.Storage.Buckets.bucketNames` with a bounded retry loop so the command
  survives MinIO's setup-server to final-server transition. Live Linux CPU
  validation confirmed the seven buckets on 2026-05-18, and the retry-hardened
  command passed against the 2026-05-19 live cluster after an initial transient
  `connection refused` during that transition.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
