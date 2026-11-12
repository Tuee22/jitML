# Phase 278 Current Linux CPU Gates After Fisher Repair — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime receipts](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Retain actual final-source CPU gate outcomes and independent
> unchanged record promotion while preserving failed attempts and older bytes.

This is the preserved `fb45…` checkpoint before the two test-format changes.
The later [final-source gates](../linux-cpu-final-format/README.md) bind `4b5…`;
these producer and receipt bytes retain their original source identity.

The current 381-file algorithm-1 source stamp is
`fb45c2efcb8768ffea37096173411ccaff0f5e51c21939b0e0070d77b376f6e1`.
The real aarch64 Linux ELF is **201,949,936 bytes**, SHA-256
`064aa7c9bf1a69dfa4ce0647f640df0cfe23b2e3c9cbffeee3ef9d24178e6640`.
The pinned Mac executable remains `73cd7e15…1ebbb24d`; the unchanged image is
`sha256:ae1ae623b9c2fbcea72feeaf19ea1a0ce65d51a49f38940a3c280f93aec4b555`.

| Genuine final invocation | Actual / orchestration exit | Result |
|---|---:|---|
| Warm production build (`steps/20261015T221002.530831Z-linux-cpu-build/result.json`) | 0 / 0 | Up to date; private and full host manifests unchanged |
| Full CPU unit (`steps/20261015T221007.461716Z-linux-cpu-unit/result.json`) | 1 / 1 | 1,533 / 1,551 pass; 18 retained-journal failures, 48.26 s body, 276.242875 s orchestrated |
| Full CPU backends (`steps/20261015T221511.588860Z-linux-cpu-backends/result.json`) | 0 / 0 | 39 / 39 pass, 2.80 s body, 33.026824 s orchestrated |

All six new Fisher/identity tests pass inside the unfiltered full unit suite.
The eighteen failing names exactly match the earlier `ca66…` suite's
retained-journal controls. The independent verification (`independent-verification.json`)
checks this equality, source/executable identity, canonical schema and bytes,
standing commands, actual exits, private source stability, and accepted host
differences. During units, only the two authorized receipt subtrees change;
the backend host manifest remains unchanged. No difference is relabelled as an
unchanged full tree.

| Exact genuine producer bytes, copied unchanged to canonical inputs | Outcome | SHA-256 |
|---|---|---|
| Unit record (`steps/20261015T221007.461716Z-linux-cpu-unit/production-validation/jitml-unit.linux-cpu.json`) | Failed | `6dcace8df26afb185f05919621da73d8a8e90bed53b1286547e725471fdcb6e8` |
| Backend record (`steps/20261015T221511.588860Z-linux-cpu-backends/production-validation/jitml-backends.linux-cpu.json`) | Passed | `ec7c916bf06d1c6827f7270a3168578797e206b9c00195136faf870623e3a32e` |

The superseded ca66 canonical files (`superseded-ca66-validation-records/`)
are saved before replacement; the older baseline package and its own prior
bytes are unchanged. Failed remains Failed. The
verification/promotion script (`verify-promote-final-records.py.txt`) creates no
validation record and modifies none of the producer's fields or digests.
Exact subprocess output is independently recovered from the CLI's fixed display
indentation and checked against the producer's stdout/stderr hashes. The Failed
unit record embeds the same streams; the Passed backend retains their hashes.

The compilation-stage unit observation (`provenance-receipts/20261015T221019.290506Z-trpo-final-cpu-unit-build-provenance/stdout.log`)
captures the actual CLI and nested Cabal invocation: neither has TASTY variables,
and nested Cabal has `JITML_SUBSTRATE=linux-cpu`. The unit test-child execution
window was missed; no child-process environment observation is claimed. The
unfiltered standing command, complete 1,551-test output, and source-bound
producer record remain available. The
actual backend-body observation (`provenance-receipts/20261015T221535.737921Z-trpo-final-cpu-backends-active-provenance/stdout.log`)
also captures the test child with the required `-p linux-cpu` partition,
`JITML_SUBSTRATE=linux-cpu`, and no TASTY variables. That substrate partition is
CLI-owned; no user filter is supplied for either full gate.

The helper v3 snapshot (`runner-v3.py.txt`),
final snapshot manifest (`final-snapshot-manifest.json`),
final state (`state-at-final-unit-backend.json`), source bindings, earlier
snapshots, and explicit append-only Mac-binary transitions are retained.
The intermediate `52ca…` CPU build passes without CPU test gates. The later
`c4a42…` private build returns actual `0` but orchestration `125` because two
authorized host test-source corrections occur; it is build-only evidence.
The first final sync attempt rejects a concurrent receipt-archive race and is
retried honestly. The succeeding final sync and warm build bind `fb45…`; no
strict source guard is loosened. Older producer files copied during intermediate
builds retain their original source stamps and are not presented as fresh gates.

The parent manifest (`../manifest.json`) hashes all 300 retained package artifacts;
source tar files and build caches are excluded. This checkpoint proves current
CPU gate outcomes only. It issues no ProductRow journal, aggregate, convergence
result, or phase closure. Docs/check-code have separate subsequent invocations.
