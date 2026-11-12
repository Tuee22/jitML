# Phase 278 TRPO Recipe Identity Diagnostic — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime receipts](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Preserve exact semantic projection identities before/after the
> scoped TRPO numerical-recipe version without treating identity as training.

The pure harness (`projection-identities.hs.txt`) compiles against the existing
native library before the version token is added. Its retained
build (`receipts/20261015T213754.765139Z-pre-token-projection-identity-build/result.json`)
and execution (`receipts/20261015T213759.678228Z-pre-token-projection-identities/result.json`)
receipts both exit `0`. The captured identities (`before.json`) contain exactly
**165** unique `(substrate, row)` pairs: all **55** rows projected independently
for each of the three lanes. Source stamps before and after execution both equal
`52ca6aa7f59c3108da99047d8c3e47182498c0ecf3cda5059a346716b6c2fb99`.
No GPU, training, cluster, journal issuance, or phase gate runs in this diagnostic.

Actual registry inspection finds **four** TRPO rows in each lane: `cartpole`,
`mountain-car`, `lunar-lander`, and `key-door-grid`. The token must change exactly
**12** plan identities while preserving the other **153**.

The post-token build (`receipts/20261015T215326.398255Z-post-token-projection-identity-build/result.json`),
capture (`receipts/20261015T215335.450816Z-post-token-projection-identities/result.json`),
and comparison (`receipts/20261015T215417.375036Z-compare-trpo-recipe-projection-identities/result.json`)
all exit `0`. The after capture (`after.json`) binds stable before/after source
`c4a42c3ae80951d5d4b33ee6d0981b64e385c0648ec6c8ae352423efba710625`.
The comparison result (`comparison.json`) proves exactly **12** changed TRPO
PlanIds and **153** unchanged unrelated identities/subjects. All **165**
report-only contract digests remain unchanged; lane admission checks PlanId
separately.

The post-token harness (`projection-identities-after.hs.txt`) also reconstructs
each old TRPO plan through the public raw request/resolver after removing only
the numerical-recipe field. All twelve reconstructed PlanIds exactly equal the
independently captured pre-token identities. Every changed subject differs only
by that one length-prefixed field pair. The comparison script (`compare-projection-identities.py.txt`)
asserts complete unique coverage and each equality; this is stronger than
checking for a token string or observing a nonzero changed count.

The post-capture executable observations (`after-executable-observation.json`)
record actual observed byte counts/hashes for the pure harness and native
`jitml`. The native executable is `73cd7e15…1ebbb24d`; observations are explicitly
after the capture, while the native build has its own receipt in the separate
[focused repair index](../../focused-rl/trpo-fisher-repair/README.md).
No numerical result, ProductRow completion, or phase status is inferred.

These structural identities are canonical-plan observations, not frozen model
measurements or expected numerical outputs. Permanent synthetic unit controls
reconstruct the old TRPO plan through the public raw resolver, require the
specific old-PlanId completion-refinement rejection, and physically Store-admit a
current positive fixture. No opaque admitted value or successful trainer run
is fabricated for the negative control.

## Test-only import correction (`5ed…`)

The first scoped unit build finds a hidden-module import in the new test; that
compiler failure is retained by the focused repair index. The correction uses
the existing public completed-checkpoint validator and changes no production
module, PlanId, or native executable. The supported native build is up to date;
that source stamp becomes
`5ed2b2c4fb2eab92aa2bfa48188431eeac8a51ff1a37899118f879c27e339537`.

The same compiled pure harness is executed again (`receipts/20261015T215748.358491Z-final-test-fixed-projection-identities/result.json`)
against that stable before/after source stamp, exit `0`. The
5ed comparison invocation (`receipts/20261015T215756.178418Z-compare-final-trpo-recipe-identities/result.json`)
also exits `0`; its result (`comparison-final.json`) again proves **12 changed
TRPO PlanIds**, **153 unchanged unrelated identities**, **165 unchanged report
contract digests**, and exact reconstruction of all twelve previous PlanIds.
The 5ed capture (`after-final.json`) and 5ed comparison script (`compare-projection-identities-final.py.txt`)
are additional files; earlier `c4a42…` captures, comparisons, and raw receipts
remain unchanged. This rebinding is a pure structural diagnostic, not a new
hardware run or full test gate.

Subsequent actual test compilation catches three unqualified loop calls in the
new Fisher unit controls; qualifying those calls changes only test source.
Actual identity execution then confirms the PlanId scope control passes, but
exposes an incorrect negative-test assumption: generic manifest decoding permits
historical inspection and does not perform completed-checkpoint admission.
The test is corrected to require successful structural decode followed by the
typed canonical PlanId rejection from `validateCheckpointCompletion`, the guard
Store invokes before minting `AdmittedCompletedCheckpoint`. The physical current
positive remains intact. No production guard or schema changes in these test
corrections. Their original failed receipts and final green controls are
preserved in the [scoped unit validation index](../trpo-unit-control-validation/README.md).

## Current completed-admission correction (`fb45…`)

The final test-only boundary correction produces source stamp
`fb45c2efcb8768ffea37096173411ccaff0f5e51c21939b0e0070d77b376f6e1`.
Production Matrix/Fisher code and the native executable remain unchanged from
the `c4a42…` build. Both final identity tests pass, including successful generic
structural decoding followed by the specific typed completed-refinement
rejection for the old PlanId, and physical Store write/read of the current
positive fixture. All four pure Fisher controls also pass. These filtered
invocations do not substitute for the full standing unit gate.

The unchanged compiled harness is executed under the final source stamp (`receipts/20261015T220953.093659Z-admitted-final-projection-identities/result.json`),
exit `0`, with stable source observations before and after. The
final comparison invocation (`receipts/20261015T221020.497968Z-compare-admitted-trpo-recipe-identities/result.json`)
exits `0`. The additional capture (`after-admitted.json`),
comparison result (`comparison-admitted.json`), and
comparison script (`compare-projection-identities-admitted.py.txt`) again prove
**12 changed TRPO PlanIds**, **153 unchanged unrelated projections**, **165
unchanged report-only contract digests**, and exact reconstruction of all twelve
old PlanIds through the public raw resolver. Earlier captures and receipts
remain byte-for-byte intact. This observation binds the final test source; it
adds no training, numerical convergence, or phase closure claim.
