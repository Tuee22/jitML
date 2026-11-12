# Phase 278 Final-source Linux CPU Gates

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Retain final `4b5…` real CPU gate outcomes and unchanged producer
> record promotion after the reviewed test-only formatting correction.

The 381-file source algorithm-1 digest is
`4b5a03b80a728d60ebe7fb013e59ba6d5a133e8b1cc124dc017501a53ac29e43`.
The actual Linux ELF remains **201,949,936 bytes**, SHA-256
`064aa7c9bf1a69dfa4ce0647f640df0cfe23b2e3c9cbffeee3ef9d24178e6640`;
the pinned native binary remains `73cd7e15…1ebbb24d`.

| Genuine invocation | Actual / orchestration exit | Actual result |
|---|---:|---|
| Final build (`steps/20261015T225714.114896Z-linux-cpu-build/result.json`) | 0 / 0 | Supported source build, 6.729559 s |
| Full units (`steps/20261015T225725.777714Z-linux-cpu-unit/result.json`) | 1 / 1 | 1,533 / 1,551 pass; same 18 stale-journal failures, 49.19 s body, 230.750896 s orchestrated |
| Full backends (`steps/20261015T230202.310953Z-linux-cpu-backends/result.json`) | 0 / 0 | 39 / 39 pass; 2.23 s body, 4.631081 s orchestrated |

All six new Fisher/identity cases pass in the full suite. The
independent verification (`independent-verification.json`) checks source/ELF,
canonical schema/serialization, standing commands, exact stream hashes,
outcomes/exits, eighteen failure names, and source bindings. Unit full host and
private source remain unchanged; backend host differences are exactly the
authorized focused-receipt paths, with private source and native binary fixed.

The genuine Failed unit record (`steps/20261015T225725.777714Z-linux-cpu-unit/production-validation/jitml-unit.linux-cpu.json`)
SHA-256 is `b90428088bd3080b2b016dc53e80e048b6d4d512aa28b4c858aa2171cbaac6d9`.
The genuine Passed backend record (`steps/20261015T230202.310953Z-linux-cpu-backends/production-validation/jitml-backends.linux-cpu.json`)
SHA-256 is `f3834208d564f0266d229383fca21222daf7ffc62725d1fc67537f26f1b56306`.
Both are copied unchanged into canonical inputs only after independent checks.
The superseded fb45 canonical bytes (`superseded-fb45-validation-records/`) are
preserved first; older packages and their source stamps remain intact.

The actual unit-body observation (`provenance-receipts/20261015T225749.577256Z-final-4b5-cpu-unit-active-body-provenance/stdout.log`)
captures CLI, nested Cabal, and the real test child: no TASTY variables, with
`JITML_SUBSTRATE=linux-cpu` in nested Cabal/test. The short backend-body window
is missed by its bounded watcher; its failed observation is retained, and no
child environment capture is claimed. The full backend command and producer
streams still independently prove its selected lane. No test is rerun solely
to manufacture a process snapshot.

The helper v3 (`runner-v3.py.txt`), source snapshot (`final-snapshot-manifest.json`),
state (`state-at-final-unit-backend.json`), raw receipts/bindings and
verification script (`verify-promote-final-records.py.txt`) are retained exactly.
No full unit pass, current ProductRow journal, aggregate, or phase closure is
claimed. The separate subsequent [strict quality checkpoint](../passing-quality-checkpoint/README.md)
passes both docs/check-code with full unchanged-tree bindings.
