# Durable-State Dhall DSL

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](../../README.md), [documents/engineering/README.md](README.md), [DEVELOPMENT_PLAN/phase-2-bootstrap-reconciler-and-jit-cache.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [DEVELOPMENT_PLAN/phase-4-stateful-platform-services.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [DEVELOPMENT_PLAN/phase-5-jitml-service-daemon.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [DEVELOPMENT_PLAN/phase-9-rl-catalog-alphazero-and-tuning.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [DEVELOPMENT_PLAN/phase-10-checkpointing-and-inference.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map), [DEVELOPMENT_PLAN/phase-21-type-state-dsl-and-inference-eligibility.md](../../DEVELOPMENT_PLAN/README.md#legacy-to-new-phase-map)
**Generated sections**: none

> **Purpose**: The closed, self-validating `jitml.dhall` durable-state config — the single declared source for jitML's MinIO buckets, Pulsar topic family, and retention — where illegal topologies are Dhall typecheck failures.

## What this owns

The durable-state DSL is a standalone, hostbootstrap-*style* Dhall surface (it does
**not** import hostbootstrap's `Core.dhall`) that declares jitML's durable state as
pure, total Dhall. It is the source of truth that `jitml project init` materializes
and that the Haskell runtime projects from.

- **Schema vocabulary** — [`dhall/project/Schema.dhall`](../../dhall/project/Schema.dhall):
  the closed unions `StoreKind` (`ObjectBucket | MessageTopic`), `StorePhase`
  (`Live | Retired`), `RetentionPolicy` (`KeepAll | LastN | MaxAgeSeconds | MaxBytes |
  LastNWithinAge`); the records `StoreEntry`, `Budget`, `PodResources`, `StoreRef`,
  `ProjectConfig`; and the Prelude-free lemmas `fitsWithin`, `storageFitsWithin`,
  `retentionWellFormed`, `writersAreLive`, and `contractOK`. Self-contained: no
  Prelude import, no network, so it evaluates in-process via the Haskell `dhall`
  library and via `dhall type`.
- **Haskell mirror + generator** — `JitML.Project.Config`
  ([`src/JitML/Project/Config.hs`](../../src/JitML/Project/Config.hs)): the `FromDhall`
  decoders, `renderProjectConfigDhall` (emits a self-contained, self-validating
  `jitml.dhall`), `defaultProjectConfig` (the single source of truth), and
  `projectSchemaDhall` (the in-source mirror of the committed schema). A `jitml-unit`
  parity test holds `Schema.dhall` and `projectSchemaDhall` judgmentally equal.
- **CLI** — `jitml project init` (`JitML.CLI.Spec` + `JitML.App.runProjectInit`):
  writes a default `./jitml.dhall` (`--output`/`--force`); see the generated
  [CLI command reference](../cli/commands.md).

## Illegal states are typecheck failures

The generated `jitml.dhall` inlines the schema, a **closed `StoreId` union** plus an
exhaustive `merge` selector, the data, and `assert : contractOK self === True`.
Typechecking the file *is* its validation. Each illegal topology is rejected
(`jitml-unit` covers all five, plus the default-accepts and round-trip cases):

| Illegal state | Rejected by |
|---|---|
| Cluster exceeds its compute budget | `fitsWithin` (the `assert` reduces to `False`) |
| Stores exceed the storage quota | `storageFitsWithin` |
| A writer targets a `Retired` store | `writersAreLive` |
| Malformed retention (e.g. `LastN 0`) | `retentionWellFormed` |
| A write references an **undeclared** store | unnameable — no `StoreId` constructor / `merge` arm exists, so it fails to typecheck |

## Single source of truth (the runtime projections)

`defaultProjectConfig` is projected by the Haskell runtime, so the durable surfaces
cannot drift from the declared registry:

- **MinIO buckets** — `JitML.Storage.Buckets.bucketNames` is
  `[ physicalName | ObjectBucket entry ]` over `defaultProjectConfig` (the former
  hand-written `[Text]` literal is retired). See [cluster_topology.md](cluster_topology.md).
- **Pulsar topics** — `JitML.Coordinator.Topology.topologyLogicalNames` projects the
  routing graph to its substrate-stripped `workflow.phase` names; a `jitml-unit`
  anti-drift test holds the registry's `MessageTopic` set equal to it, so the
  per-substrate routing cannot diverge from the declared family. See
  [daemon_architecture.md](daemon_architecture.md).
- **Checkpoint retention** — the GC retention is read from the registry's
  `checkpoints` store via `JitML.Project.Config.lookupStoreRetention` (the former
  hardcoded `LastN 5` is retired). See [checkpoint_format.md](checkpoint_format.md).

## Inference Selector Boundary

Phase `21` extends the Dhall vocabulary to mirror the Haskell model type-state
boundary. `dhall/project/Schema.dhall` exports `ModelState`,
`DeclaredExperiment`, `CompletedTrainingWitness`, and `InferenceSelector`, so a
project-level selector names completed-training provenance instead of a bare
declared experiment. `dhall/run/Schema.dhall` exports the reflected
`TrainingEvidence`, `CompletedTrainingWitness`, and `InferenceSelector` records
accepted by `JitML.Service.RunConfig`.

`tryLoadInferenceSelectorConfig` decodes that Dhall shape and then validates the
runtime facts Dhall cannot decide by itself: selector and witness hashes must
match, provenance must be `completed-training`, convergence must pass, initial
and final weight hashes must be present and different, `updateCount` must be
positive, and `datasetShaAtRead` must be present. Declared, partial,
synthetic, seeded-demo, and failed-convergence selectors therefore report a
typed decode failure before any checkpoint or inference IO runs.

## Resolved Worker Plan Mounts

`dhall/run/Schema.dhall` also reflects the tuning and AlphaZero worker mount
boundary. `TuneRunConfig` and `AlphaZeroRunConfig` contain `planId`,
`resolvedPlan`, and `pulsarWsUrl`; sampler/scheduler/pruner and numerical budget
fields are not duplicated in those mounted records. Dhall validates the record
shape, while `JitML.Plan.Command` / `JitML.Plan.Workload` own the facts Dhall
cannot prove: supported plan version, positive unit-indexed quantities,
canonical transport, plan identity, closed tuning axes/game, substrate
placement, and equality with the originating raw command. A decode or semantic
mismatch fails before trial, game, checkpoint, or publication effects. A
Kubernetes Tune or AlphaZero worker also fails closed when the required mount is
absent; only a non-worker developer invocation may construct a local plan.

## The honest static-vs-runtime boundary

Dhall is pure, total, and IO-free. It makes "name a thing never declared" and
"write to a thing declared `Retired`" *unrepresentable*, and it keeps the declared
set internally consistent and within budget/quota. It **cannot** observe whether a
bucket or topic exists in the live broker/object-store at this instant, and it has no
`Text` equality builtin — which is exactly why the strong "undeclared is unnameable"
guarantee comes from the closed `StoreId` union + exhaustive `merge`, not a
`Text`-keyed lookup. Closing "already deleted right now" fully requires a generated
Haskell witness plus the broker/store call as the one true existence edge; the
witness layer is future work tracked beyond the current foundation.

## Status

The phase status, sprint history, and validation evidence for the DSL live in the
DEVELOPMENT_PLAN (Sprints 2.15 / 4.9 / 5.15 / 10.8 / 18.2); see
[DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md). This document
describes the current surface, not the schedule.
