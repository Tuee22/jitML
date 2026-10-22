# Phase 278 TRPO Scoped Unit Validation — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime receipts](../README.md), [TRPO identity diagnostic](../trpo-recipe-identity/README.md)
**Generated sections**: none

> **Purpose**: Preserve failed test-development attempts and the actual corrected
> unit bodies without converting filtered invocations into full gate evidence.

The current source is
`fb45c2efcb8768ffea37096173411ccaff0f5e51c21939b0e0070d77b376f6e1`
(381 files, source algorithm 1). The final
[source observation](final-source-freeze.json),
[pre-build observation](native-before.json), and
[post-build observation](native-after.json) bind the unchanged native executable
`73cd7e1502bf4841a6d2a2d11d22c0ca4f84d19c4095d82cd2d675601ebbb24d`
(180,974,592 bytes). The supported
[native build](receipts/20261015T220638.418386Z-trpo-admission-native-build/result.json)
exits `0`, reports Up to date, and leaves that executable unchanged.

| Actual invocation | Exit | Outcome |
|---|---:|---|
| [Initial identity compilation](receipts/20261015T215318.829077Z-trpo-versioned-identity-regressions/result.json) | 1 | Hidden `Product.Publisher.Audit` import; no unit bodies run |
| [Public validator compilation](receipts/20261015T215802.404407Z-trpo-final-identity-regressions/result.json) | 1 | Three unqualified `forM_` calls in the new Fisher controls; no unit bodies run |
| [Qualified identity bodies](receipts/20261015T220110.105732Z-trpo-qualified-identity-regressions/result.json) | 1 | Scope control passes; old-PlanId control exposes an incorrect generic-decoder assertion, 1 / 2 pass, 0.01 s |
| [Qualified pure Fisher bodies](receipts/20261015T220433.225118Z-trpo-qualified-pure-fisher-regressions/result.json) | 0 | 4 / 4 pass, 0.01 s, before the final test-only boundary correction |
| [Current identity bodies](receipts/20261015T220659.389524Z-trpo-admission-identity-regressions/result.json) | 0 | 2 / 2 pass, 0.02 s, final `fb45…` source |
| [Current pure Fisher bodies](receipts/20261015T220924.780258Z-trpo-admission-pure-fisher-regressions/result.json) | 0 | 4 / 4 pass, 0.01 s, final `fb45…` source |

Generic `decodeAddressedManifestCbor` intentionally permits historical structural
inspection. The corrected negative test first requires successful decoding,
then the specific `CompletedTrainingExternalBarMismatch` from
`validateCheckpointCompletion` stating that the canonical RL completion PlanId
differs from its row's device-substrate projection. Store invokes that existing
completion guard before minting `AdmittedCompletedCheckpoint`. The current
positive fixture is physically written, read through Store, and checked through
the public product checkpoint validator. These are synthetic schema/predicate
controls; they do not represent trained model evidence.

The Fisher controls exercise Float32 quantization, analytic parity, nonzero
undamped curvature, multi-coordinate normalization, positive/negative tiny and
huge scales, subnormal direction dispatch, validated exact-zero dispatch, and
fail-closed configuration/device-result errors. The selected callbacks are
controlled unit fixtures; the separate [focused repair index](../../focused-rl/trpo-fisher-repair/README.md)
owns actual real-device regression receipts.

Each raw command/result/stdout/stderr file is copied unchanged. The
[retention script](retain-trpo-final-diagnostics.py.txt) validates raw capture
hashes before copying and verifies all files indexed in the parent
[manifest](../manifest.json). No passing GateTranscript, lane journal, model
checkpoint, or phase Done status is synthesized. Both current unit invocations
contain explicit Tasty filters and therefore cannot discharge the full unit
obligation.
