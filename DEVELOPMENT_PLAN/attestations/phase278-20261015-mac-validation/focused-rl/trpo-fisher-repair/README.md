# Phase 278 TRPO Fisher Repair Validation — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Focused Apple RL diagnostics](../README.md)
**Generated sections**: none

> **Purpose**: Retain native build and actual-device regression receipts for
> the normalized-direction Fisher repair, with each intermediate source identity
> explicit.

The [baseline prefix measurements](../trpo-prefix/README.md) identify a shared
Float32 finite-difference precision defect. The repaired operator normalizes
the direction before applying fixed `±0.001` parameter perturbations, computes
the device gradient at that scale, and restores the direction magnitude on the
host before adding damping. A scaled norm avoids premature underflow and
overflow. The zero direction returns exact zero without a device invocation.
These numerical changes preserve the canonical budget, seed and convergence
criterion.

This package records the **historical Fisher-only recipe**. The later
[selected-device evaluation and time-limit repair](../on-policy-repair/README.md)
has its own source identities and validation; these earlier receipts remain
unchanged historical measurements.

## Final formatting source and validation

The final frozen source is
`4b5a03b80a728d60ebe7fb013e59ba6d5a133e8b1cc124dc017501a53ac29e43`
(**381** code files). Two test-only Fourmolu layout corrections distinguish it
from the source used for the full repaired canonical diagnostic below.
Production modules, numerical recipe, PlanIds and native executable remain
unchanged. The supported native build (`formatted-source4b5/receipts/20261015T225712.599073Z-trpo-format-final-native-build/result.json`)
returns `0` and `Up to date`. The
before (`formatted-source4b5/formatted-native-before.json`),
after build (`formatted-source4b5/formatted-native-after.json`) and
after gates (`formatted-source4b5/formatted-gates-after.json`) captures agree on
this source stamp and native SHA-256
`73cd7e1502bf4841a6d2a2d11d22c0ca4f84d19c4095d82cd2d675601ebbb24d`
(`180,974,592` bytes).

| Actual final-source execution | Result | Test-body duration |
|---|---|---:|
| Full Mac unit suite (`formatted-source4b5/receipts/20261015T225725.817171Z-trpo-format-final-apple-unit-full/result.json`) | **1,533 / 1,551 pass**, **18 fail**, exit `1` | `81.52 s` |
| Full Apple backend suite (`formatted-source4b5/receipts/20261015T230117.408375Z-trpo-format-final-apple-backends-full/result.json`) | **26 / 26 pass**, exit `0` | `58.54 s` |

The authentic unit (`formatted-source4b5/formatted-full-unit-validation-record.json`)
and backend (`formatted-source4b5/formatted-full-backends-validation-record.json`)
records bind this final source and native executable. The
read-only classification (`formatted-source4b5/formatted-full-unit-classification.json`)
finds the same **18** retained-evidence failures, **zero** unknown failures and
all **six** new identity/Fisher cases green inside the complete unit suite.
The real Metal Fisher regression also passes inside the complete backend
suite. The full unit gate remains **failed**; these results do not close Phase
278 or replace a complete ProductScenario journal.

The full repaired canonical diagnostic has also reached its terminal result:
**219.0 < 400.0**, exit **2**, after **1,228,800** environment transitions and
**20** evaluation episodes. It runs on the unchanged `fb45` source identified
below, with the same production/native bytes as this final formatting source.
The complete publisher receipt (`admission-source-fb45/receipts/20261015T221533.479538Z-canonical-trpo-cartpole-fisher-repaired/result.json`)
retains `22:15:33.480032`–`22:55:37.773011 UTC` and **2,404.260 s** elapsed.
The failure summary (`admission-source-fb45/canonical-failure.json`) checks raw
stream hashes and records **0** eligible rows, **0** admitted inventory entries
and manifest `none`. The postflight (`admission-source-fb45/canonical-after.json`)
verifies that source/native bytes remain unchanged and the checkpoint namespace
is absent after execution, as it was before launch. Evaluation uses the
canonical deterministic setup; these twenty repeats do not establish a sampled
generalization interval.

The corrected Fisher homogeneity controls are green, while full canonical
convergence remains failed. The normal publisher rejects completion before
trajectory/checkpoint persistence. Final weights, optimizer-update proof,
admitted PlanId and successful Store readmission are therefore unavailable for
this invocation. The compiled Store inspector remains a retained compile-only
control and is not invoked against a missing checkpoint. No bar, budget or
seed is changed, and no full-row retry follows this failure.

## Canonical-run source fb45 and validation

The repaired canonical-run source is
`fb45c2efcb8768ffea37096173411ccaff0f5e51c21939b0e0070d77b376f6e1`,
with **381** code files. The native executable remains SHA-256
`73cd7e1502bf4841a6d2a2d11d22c0ca4f84d19c4095d82cd2d675601ebbb24d`
(`180,974,592` bytes). Test-only corrections after the numerical recipe freeze
change no production source. The supported
build (`admission-source-fb45/receipts/20261015T220638.418386Z-trpo-admission-native-build/result.json`)
returns `0` and `Up to date`; before (`admission-source-fb45/native-before.json`)
and after (`admission-source-fb45/native-after.json`) captures verify the source
stamp and unchanged executable bytes.

| Actual canonical-source execution | Result | Test-body duration |
|---|---|---:|
| Two checkpoint identity controls (`admission-source-fb45/receipts/20261015T220659.389524Z-trpo-admission-identity-regressions/result.json`) | **2 / 2 pass**, exit `0` | `0.02 s` |
| Four pure Fisher controls (`admission-source-fb45/receipts/20261015T220924.780258Z-trpo-admission-pure-fisher-regressions/result.json`) | **4 / 4 pass**, exit `0` | `0.01 s` |
| Focused real Metal Fisher regression (`admission-source-fb45/receipts/20261015T220950.136330Z-trpo-admission-metal-fisher-regression/result.json`) | **1 / 1 pass**, exit `0` | `0.05 s` |
| Full Apple backend suite (`admission-source-fb45/receipts/20261015T221102.860722Z-trpo-admission-apple-backends-full/result.json`) | **26 / 26 pass**, exit `0` | `63.61 s` |
| Full Mac unit suite (`admission-source-fb45/receipts/20261015T221252.681936Z-trpo-admission-apple-unit-full/result.json`) | **1,533 / 1,551 pass**, **18 fail**, exit `1` | `77.87 s` |

The full unit gate remains **failed**. The
read-only classification (`admission-source-fb45/full-unit-classification.json`)
compares actual failure names with the earlier full Mac unit result: all
**18** are the same retained-evidence failures, with **zero** unknown failure
names. The two earlier documentation defects and all six new cases pass inside
the full run. The classification does not alter a test result or manufacture a
GateTranscript. Its first helper attempt encounters an optional `stdout=null`
field in a successful validation record and exits `1`; that helper receipt is
retained. The corrected helper uses the actual complete raw backend stdout and
returns `0`. Both real gate outcomes above remain unmodified.

The unaltered full backend (`admission-source-fb45/full-apple-backends-validation-record.json`)
and full unit (`admission-source-fb45/full-apple-unit-validation-record.json`)
validation records bind this source and executable. Scoped records separately
retain the two identity (`admission-source-fb45/two-identity-scoped-validation-record.json`),
four pure Fisher (`admission-source-fb45/four-pure-fisher-scoped-validation-record.json`)
and one Metal (`admission-source-fb45/one-metal-fisher-scoped-validation-record.json`)
commands. The final-source
independent identity comparison (`../../runtime-receipts/trpo-recipe-identity/comparison-admitted.json`)
again proves **12** changed TRPO identities, **153** unchanged other identities
and unchanged report-contract digests for all **165** projections.

The unchanged full canonical `TRPO/cartpole` command starts at
`22:15:33.480 UTC`. Its preflight (`admission-source-fb45/canonical-preflight.json`)
checks the frozen source and native executable and records the canonical
checkpoint namespace **absent** immediately before launch. A second filesystem
assertion also verifies absence. The
exact command (`admission-source-fb45/canonical-in-progress-command.json`)
retains the original launch record. The production recipe keeps seed `42`,
`150` iterations, `1,228,800` environment transitions and median criterion
`400`. The complete failed outcome and unchanged postflight are retained in the
final-source section above; the original launch record remains unmodified.

A separate ignored read-only
Store inspector (`admission-source-fb45/readmit-product-checkpoint.hs.txt`)
compiles against the current native library with exit `0`; its
compile receipt (`admission-source-fb45/receipts/20261015T221605.951822Z-trpo-final-store-readmission-build/result.json`)
retains exact package IDs and argv. The
identity record (`admission-source-fb45/store-inspector-build-identities.json`)
pins source and binary SHA-256
`d16d93fbffb970ccd94abdf3be4c191b062f070ddfc6905cd93999e1021e9e19`,
along with the native CLI and consulted production modules. It performs no
training or GPU operation. Its read-only code can independently
readmit the exact immutable address and latest pointer through production
Store, require completed admission, verify current projection PlanId/budget,
and return physical loaded weight hashes. The existing Python inspector
separately verifies physical bytes and derives PlanId from a successful fresh
manifest; it links no old library and does not claim to reimplement Store
admission. Neither inspector is invoked for the failed repaired canonical row.

## Intermediate source before recipe identity versioning

Source `52ca6aa7f59c3108da99047d8c3e47182498c0ecf3cda5059a346716b6c2fb99`
contains the numerical repair and its four pure unit cases plus a shared real
oneDNN/Metal regression. It precedes the subsequent semantic recipe identity
versioning. Its before (`intermediate-source52ca/native-before.json`) and
after (`intermediate-source52ca/native-after.json`) read-only captures retain
the exact source-file identities, all-code source stamp, native executable
identity and absent TRPO checkpoint namespace.

The supported `./bootstrap/apple-silicon.sh build` succeeds with exit `0` in
`82.292 s`; the receipt (`intermediate-source52ca/receipts/20261015T213318.312413Z-trpo-repair-native-build/result.json`)
retains both raw streams and exact argv. The native executable changes from
baseline SHA-256
`cb1806720ebd99fecf9660732956a9e112c1becc3bb9c19daf207f9ea0ee147a`
to `cfa48d201bfaf1d37d698b8ba5ff7eed185eaacb37ce50d3a4316127d3c40b77`
(`180,971,920` bytes), while the source stamp remains stable across the build.
The trainer snapshot (`intermediate-source52ca/repaired-PpoTrainer.hs.txt`) and
backend regression snapshot (`intermediate-source52ca/backend-regression.hs.txt`)
match their captured file hashes.

The first focused test invocation fails during test compilation because the
shell does not inherit the bootstrap child's LLVM `PATH`; no GPU test runs.
Its exact failure receipt (`intermediate-source52ca/receipts/20261015T213517.326475Z-trpo-repair-metal-fisher-regression/result.json`)
remains retained. With the existing LLVM 19 tools explicitly on `PATH`, the
supported CLI invocation succeeds:

```bash
.build/jitml test jitml-backends --apple-silicon --test-options='-p /apple-silicon/&&/Fisher/'
```

The actual environment wrapper and complete `PATH` are recorded in the
successful receipt (`intermediate-source52ca/receipts/20261015T213623.126611Z-trpo-repair-metal-fisher-regression-llvm/result.json`).
Exactly **1 / 1** actual Metal test passes in **0.04 s** test-body time
(`38.636 s` including Cabal compilation). The test calls the production Fisher
function on the exact baseline sparse nonzero `W2` counterexample, checks a
nonzero undamped Fisher contribution, homogeneity at scales `1e-8`, `-1e-8`
and `1e-160`, finite outputs, and exact zero for the zero direction.
The unaltered scoped validation record (`intermediate-source52ca/metal-fisher-scoped-validation-record.json`)
binds source `52ca…2fb99`, executable `cfa48…40b77`, the actual command,
output and exit status. It is a focused regression record, with no full-suite
or phase-validation claim.

At this intermediate source, full backend, full unit and long canonical
execution are held until the recipe identity patch, source refreeze and new
native build. No full canonical result is claimed for this intermediate source.

## Versioned recipe source

At the recipe identity freeze, the source is
`c4a42c3ae80951d5d4b33ee6d0981b64e385c0648ec6c8ae352423efba710625`
(`381` code files). The native build receipt (`versioned-source-c4a42/receipts/20261015T214151.764382Z-trpo-versioned-native-build/result.json`)
records exit `0`, **666.989 s**, from `21:41:51.765114` to
`21:52:58.791911 UTC`. The before (`versioned-source-c4a42/native-before.json`)
and after (`versioned-source-c4a42/native-after.json`) captures prove the same
source stamp across compilation. The signed native executable is SHA-256
`73cd7e1502bf4841a6d2a2d11d22c0ca4f84d19c4095d82cd2d675601ebbb24d`,
`180,974,592` bytes; its canonical TRPO checkpoint namespace is absent after
the build. Exact current snapshots of
PpoTrainer (`versioned-source-c4a42/PpoTrainer.hs.txt`),
Matrix (`versioned-source-c4a42/Matrix.hs.txt`), and the
checkpoint identity tests (`versioned-source-c4a42/CheckpointV1Admission.hs.txt`)
are retained.

An independent projection comparison (`../../runtime-receipts/trpo-recipe-identity/comparison.json`)
at this same frozen source verifies **12** changed TRPO identities and **153**
unchanged unrelated identities across all three substrates. Removing only the
new numerical recipe field reconstructs every independently captured old TRPO
PlanId. Report-contract digests are unchanged. Its
receipt (`../../runtime-receipts/trpo-recipe-identity/receipts/20261015T215417.375036Z-compare-trpo-recipe-projection-identities/result.json`)
and [supporting package](../../runtime-receipts/trpo-recipe-identity/README.md)
retain the actual pure execution; this comparison runs no substrate training.

The scoped identity invocation (`versioned-source-c4a42/receipts/20261015T215318.829077Z-trpo-versioned-identity-regressions/result.json`)
fails during compilation, before any test executes: the new checkpoint test
imports hidden library module `JitML.Product.Publisher.Audit` at line `42`.
The exact failure remains retained (`114.667 s`, exit `1`). No Metal, full
backend, full unit or canonical command runs at this source after that failure.
The narrow test-only correction uses the already exposed
`ProductPublisher.validateAdmittedProductCheckpoint` function and removes the
hidden import; it changes no library implementation or public API. Subsequent
validation must capture its new all-code source stamp even if the native
executable bytes remain identical.

## Test-only public boundary correction

The first test-only correction produces source
`5ed2b2c4fb2eab92aa2bfa48188431eeac8a51ff1a37899118f879c27e339537`.
The supported build (`final-source5ed/receipts/20261015T215730.594433Z-trpo-final-native-build/result.json`)
returns `0` and `Up to date`. The before (`final-source5ed/native-before.json`)
and after (`final-source5ed/native-after.json`) captures confirm stable `5ed…9537`
source with the **same** physical executable SHA-256 `73cd…bb24d`. This is a
test-source identity change, not a new training implementation or binary.

The corrected checkpoint module (`final-source5ed/CheckpointV1Admission.hs.txt`)
compiles. The next scoped unit invocation (`final-source5ed/receipts/20261015T215802.404407Z-trpo-final-identity-regressions/result.json`)
then fails during compilation of `test/unit/Main.hs`, before any test body:
the new Fisher tests use bare `forM_` at lines `14892`, `14972` and `14989`,
while `Control.Monad` is imported qualified. This exact exit `1` result
(`6.121 s`) remains retained. Qualifying those three test calls is the next
narrow correction; it changes no production source.

## Qualified unit source and actual focused outcomes

After qualifying those test-only calls, frozen source is
`d4c78c2af1dad706a53050af7522bebc9ddc17c767b181a8454e3ce4a29123f1`.
The supported native build (`qualified-source-d4c78/receipts/20261015T220051.241092Z-trpo-qualified-native-build/result.json`)
returns `0` and `Up to date`; its before (`qualified-source-d4c78/native-before.json`)
and after (`qualified-source-d4c78/native-after.json`) captures confirm the
same `73cd…bb24d` executable and stable `d4c78…123f1` source stamp.

The entire unit component now compiles. The
two identity cases (`qualified-source-d4c78/receipts/20261015T220110.105732Z-trpo-qualified-identity-regressions/result.json`)
actually execute: the scoped PlanId case passes, while the legacy completion
case fails because it expects structural `decodeAddressedManifestCbor` to reject
an old canonical PlanId (`166.007 s` including compilation, `0.01 s` body,
exit `1`). That decoder refines manifest structure; canonical completion
identity validation resides in `validateCheckpointCompletion`, which
`Store.requireAdmittedCompletedCheckpoint` invokes. The next test-only
correction must exercise that actual admission boundary. This failure is
retained, and no full backend, full unit or canonical run proceeds from it.

The separate four new pure Fisher cases (`qualified-source-d4c78/receipts/20261015T220433.225118Z-trpo-qualified-pure-fisher-regressions/result.json`)
all pass, **4 / 4**, in **0.01 s** body time (`3.606 s` including Cabal,
exit `0`). They exercise tiny and negative Float32 directions with nonzero
curvature, the two-forward/one-gradient device contract and zero-direction
zero-dispatch path, malformed/non-finite/overflowing inputs, and propagation
of device errors and non-finite results. The unaltered
scoped validation record (`qualified-source-d4c78/four-pure-fisher-scoped-validation-record.json`)
binds the real filtered command, `d4c78…123f1` source and `73cd…bb24d`
executable. It proves these four cases, not the full unit suite.
