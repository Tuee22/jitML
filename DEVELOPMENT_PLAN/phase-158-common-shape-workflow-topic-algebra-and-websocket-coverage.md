# Phase 158: Common-Shape Workflow, Topic-Algebra, and Websocket Coverage

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)
**Generated sections**: none

> **Purpose**: Common-Shape Workflow, Topic-Algebra, and Websocket Coverage. Single-session phase migrated from legacy Sprint 12.14 in the 2026-07-24 phase-per-session renumber; see the old→new map in [README.md](README.md).

## Phase State

✅ **Done**.

## Sprint 158.1: Common-Shape Workflow, Topic-Algebra, and Websocket Coverage [✅ Done]

**Status**: Done
**Validation State**: Coverage landed + validated. The `Work*`/topic-algebra/
`.ready` unit coverage landed with Sprints `5.13`/`5.14`/`10.7`; this sprint
added the remaining websocket snapshot/patch + composite-command coverage now
that `11.10` is Done:
- **`test/unit/Main.hs`** — `DecodedInference` decode + the composite Engine
  commands (`CheckpointCompareCommand`/`AdversarialMoveCommand` render→parse
  round-trip) + MCTS move-legality.
- **`web/test/Main.purs`** — `parseDecodedInference` + `parseCompareFrame` +
  `parseMoveFrame`: the Engine-computed websocket snapshot frames apply
  mechanically in the browser, with no panel compute.

Validated (offline closure gate): `jitml-unit` **208/208**,
`jitml-daemon-lifecycle` **35/35**, `jitml-e2e` **23/23**, `spago test`
**17/17**, `jitml lint purescript: ok`, `jitml docs check: ok`, `jitml
check-code: ok`. The `jitml-integration` `-p Live` lane (live `linux-cpu`
cluster) is the runtime gate per rule M(b); offline integration is green
(52/52), the Live subset re-validates against a freshly bootstrapped cluster.
**Implementation**: `test/unit/Main.hs`, `test/daemon-lifecycle/Main.hs`,
`test/integration/Main.hs`, `test/e2e/Main.hs`, `web/test/Main.purs`
**Docs to update**: `../documents/engineering/unit_testing_policy.md`,
`../documents/engineering/pulsar_ml_workflow.md`, `system-components.md`

### Objective

Add the test coverage for the common Pulsar ML-workflow shape so the convergence
deltas are gated, per the
[../documents/engineering/pulsar_ml_workflow.md](../documents/engineering/pulsar_ml_workflow.md)
`Conformance checklist`. Adopts `Test Organization` and `At-Least-Once Event
Processing` from [../README.md](../README.md).

### Deliverables

- `Work*` envelope coverage: training and inference share `WorkCommand →
  WorkEvent* → WorkResult` correlated by `callId`; producer-side dedup keyed by
  `callId` is a pure fold over the work log (offline, no broker).
- Topic-algebra coverage: the coordinator's reconciled topic set **equals** the
  validated routing graph's derived set; the validator rejects an unroutable
  descriptor and one-sided command↔event links.
- `.ready` readiness-gate coverage: infer-before-ready yields a typed rejection;
  a serveable `ArtifactRef` is mintable only from a completed training derivation.
- Websocket coverage: snapshot/patch frames apply mechanically in the browser
  (`web/test`), and inference is asynchronous to the browser (no synchronous
  compute-and-return).

### Validation

- `docker compose run --rm jitml jitml test jitml-unit --linux-cpu`,
  `jitml-daemon-lifecycle --linux-cpu`, `jitml-integration --linux-cpu`,
  `jitml-e2e --linux-cpu` (per standards rule M(b), the `linux-cpu` lane is the
  closure gate; accelerator lanes are attested in Phases `15`/`16`).
- `jitml lint purescript` for the `web/test` snapshot/patch spec.
- `docker compose run --rm jitml jitml docs check` and `jitml check-code`.

### Remaining Work

- None. The `Work*`, topic-algebra, `.ready`, and websocket snapshot/patch test
  groups have landed (unit + `web/test`); the live `linux-cpu` integration lane is
  the standard runtime gate (rule M(b)), exercised on a bootstrapped cluster.

## Documentation Requirements

**Engineering docs to create/update:**

- None (single-session phase migrated in the 2026-07-24 renumber; evidence lives in the Validation gate above).

**Product docs to create/update:**

- None.

**Cross-references to add:**

- None.
