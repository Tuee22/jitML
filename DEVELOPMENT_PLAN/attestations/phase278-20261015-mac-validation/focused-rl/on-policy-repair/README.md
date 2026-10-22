# Phase 278 On-Policy Device Evaluation and Time-Limit Bootstrap — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Focused Apple RL diagnostics](../README.md)
**Generated sections**: none

> **Purpose**: Retain actual Mac builds, unit and real Metal controls for the
> selected-device evaluator and pre-reset time-limit GAE correction, preserving
> failed intermediate attempts and the independently verified canonical result.

## Current frozen source and gates

The final source is
`a145173f28f63e345793df791684e81f57defa7b328cad5f3182bd5e66cd897a`
(**383** code files). The [supported native build](receipts/20261016T001813.046557Z-on-policy-golden-native-build/result.json)
returns **0**, `Up to date`. Its [before](golden-native-before.json) and
[after](golden-native-after.json) captures agree on native SHA-256
`4fcec9579ab0f0d456bc01dc3acd11dbbcfae474d6dca0adc9bcc35e3dc06ba9`
(**181,076,096 bytes**) and this source stamp.

| Actual Mac execution | Result | Test-body duration |
|---|---|---:|
| [Full Apple backend suite](receipts/20261016T001834.853765Z-on-policy-golden-apple-backends-full/result.json) | **28 / 28 pass**, exit **0** | **62.32 s** |
| [Full Mac unit suite](receipts/20261016T002003.127464Z-on-policy-golden-apple-unit-full/result.json) | **1,551 / 1,569 pass**, **18 fail**, exit **1** | **80.28 s** |

The authentic [unit](golden-full-unit-validation-record.json) and
[backend](golden-full-backends-validation-record.json) producer records bind
these current source and native identities. The [read-only classification](golden-full-unit-classification.json)
finds exactly the same **18** retained-evidence failures, **zero** unknown
failures, no prior retained failure resolved, and all **37** scoped controls
green inside the full suite. The full unit gate remains **Failed**.

The full Metal suite executes all three real-device controls: selected-device
final-policy evaluation, pre-reset successor-value bootstrap, and normalized
Fisher homogeneity. The evaluator fixture delegates **eight** actual forward
calls; the bootstrap fixture delegates **four** actual batches with frozen
parameters and distinguishes the pre-reset value from the reset-state value.
These are synthetic device controls, not ProductRow convergence measurements.
The [gate summary](final-gates-summary.json) records the authentic scope.
Fresh current validation covers the CLI build and unit/backends stanzas on
real Apple and CPU lanes; it does not assert that every other stanza ran.

## Corrected contracts

Production final on-policy reward uses the **same selected MlpDevice** as
training. Every greedy decision crosses its forward seam; a device error,
wrong output width, non-finite result, invalid input or invalid action mask
rejects the entire evaluation. Fixed evaluation start, legal masks, lowest-index
argmax ties, episode count, reward semantics and horizon are preserved. The
existing pure evaluator remains an explicit compatibility/reference API.

Rollouts distinguish continuing transitions, true terminals and horizon-only
truncations. GAE bootstraps a truncation using the **actual pre-reset successor**
value from the same device and old parameters, while stopping lambda recursion
across either episode boundary. True terminal bootstrap is zero. Continuing
endpoint slots retain their own successor values; reset slots are not valued
as prior-episode successors. The pure collector uses its matching pure value
path. Environment reset state, RNG consumption, transition count and horizons
are preserved.

`RolloutStep` construction now uses the typed `rsBoundary` sum; the exported
`rsDone` accessor remains for observers and returns true at either reset
boundary. This is a constructor-level source change. The retained
[twelve changed source files](source/manifest.json) and captures retain exact
bytes, including the shared test modules. The [local preservation metadata](preserved-a145-local-identities.json)
also records an ignored exact copy of all **383** source files, the executing
native binary and linked library before subsequent authorized changes. The
large binary copies remain local and are not added to tracked evidence.

Separate producer-owned tokens version evaluation and rollout semantics for
exactly **22 on-policy rows per lane**, **66** identities in total. Independent
projection and generated-contract comparisons establish **99** unaffected
identities and unchanged report-only digests. Stripping only these two new
fields reconstructs all prior identities while preserving the existing TRPO
Fisher token. Current checkpoint admission rejects the old completions. These
are identity controls, not substitutes for fresh training or lane journals.
The [parent Mac session](../../README.md) retains the independent proof and
real CPU counterpart.

## Honest intermediate validation

The first [native build](receipts/20261015T235223.808919Z-on-policy-repair-native-build/result.json)
on source `dad8365b06db40cdae745ff3ab946975446bacb446baadc6c3b3980b2f5df4a1`
passes, with native SHA-256
`a0049ea7b9dd444fa06e744e897033defa97c89e22d0181696e7f4abe37051c5`.
Its compiler type-default warning and the CPU compilation's callback-shadowing
warning are fixed before the next build; container Fourmolu/HLint checks pass.
CPU-owned quote/style attempts are retained in the parent runtime evidence.

The [warning-free b519 build](receipts/20261016T000759.130915Z-on-policy-final-native-build/result.json)
passes and produces current native `4fce`. The [focused unit run](receipts/20261016T000945.018763Z-on-policy-final-focused-unit/result.json)
passes **37 / 37** (**0.19 s** body). Its [focused Metal invocation](receipts/20261016T001353.514388Z-on-policy-final-focused-metal/result.json)
passes **2 / 2** (**0.04 s**): bootstrap and Fisher. The filter misses the
final-evaluator case; the later full **28**-case suite executes it.

The [b519 full unit run](receipts/20261016T001432.736872Z-on-policy-final-apple-unit-full/result.json)
authentically fails **19 / 1,569** (**78.43 s** body). Its
[classification](b519-full-unit-classification.json) identifies the same
**18** evidence failures plus one stale representative PlanId golden.
The [exact correction](golden-correction-diff.patch.txt) changes only the three
PPO/cartpole expected PlanId literals, using the independently captured current
identities. All other source bytes, semantic/budget/seed assertions, unrelated
goldens and evidence pins remain unchanged. The final full unit run resolves
this extra failure without disguising the **18** remaining failed checks.

## Fresh canonical Metal publication and readback

The [complete fresh publisher receipt](receipts/20261016T002352.534624Z-canonical-trpo-cartpole-device-evaluation-gae/result.json)
returns **0** at **2026-10-16 01:01:13.283262 UTC**, after
**2,240.661 seconds** from **00:23:52.536295 UTC**. It publishes **1 / 1**
eligible admitted row, with no checkpoint reuse. The [terminal summary](canonical-terminal-summary.json)
records median final reward **497.0** against the unchanged **400.0** bar,
average **497.00000000000017**, **1,228,800** actual environment transitions,
**192,150** optimizer updates and **20** evaluation episodes. Each trajectory
episode returns **497** over **498** steps. Seed **42**, **150** iterations,
training budget, evaluation count and convergence criterion are unchanged.

The [preflight](canonical-before.json), [publisher postflight](canonical-after.json)
and [final readback guard](readback-after.json) prove source `a145` and native
`4fce` stay byte-identical throughout, with the canonical TRPO namespace absent
before execution and present after this fresh publication. The earlier
[at-start gate summary](final-gates-summary.json) explicitly observed a pending
canonical; this terminal summary supplies its later outcome. Prior
[Fisher-only 219](../trpo-fisher-repair/README.md) and baseline 188 failures
remain historical measurements of their different recipes.

The [physical inspection](canonical-physical.json) and
[production Store readmission](canonical-store-readmission.json) both return
**0**. The [full independent comparison](canonical-readback-comparison-v3.json)
also returns **0**, checking current projection, manifest and completion PlanIds,
exact immutable manifest address, completed budget, latest pointer, metrics,
device witness and physical weight shape/bytes/hash. The actual identities are:

- Current Apple PlanId: `64f3d41c00fc97046e50652def2eb18c0102ec12af10cc16e364595706f5c4fc`.
- Manifest SHA-256: `3067f535b3c666e54ec8521735d3c2b90eb99afd6d6ff22f75998d93a316833e`.
- Physical final weight SHA-256: `31bb7e0dc46b24464282d36b53ada374ee59c28310ee0f5ad7452fae108ecd9e` (**2,051** values, **16,425** JMW1 bytes).
- Physical trajectory SHA-256: `3d74cdb904b3e0f79a38f30f87e28e5f763fa088e40e92d729a03fef750db385`.

The exact [checkpoint namespace](checkpoint-snapshot/jitml-checkpoints/product-row-TRPO.cartpole/pointers/latest)
and [executed device source artifact](device-artifacts/0f36a73630756e54d0e381d0353434defde3f2ab4e27ab0fc52dacac158170d5.metal.json)
are retained with byte hashes. The [fresh inspector build](receipts/20261016T002437.364087Z-on-policy-final-store-readmission-build/result.json)
and [source/native/library identities](store-inspector-build-identities.json)
identify the actual current library used for readmission; the prior inspector
binary remains preserved locally and is not reused.

Two failed supplemental comparison attempts are retained honestly. The
[first comparison](receipts/20261016T010147.716064Z-on-policy-canonical-independent-comparison/result.json)
incorrectly assumes that the public optional body-identity accessor is present
for V1 weight-only manifests. The producer and physical decoder already verify
the mandatory embedded envelope-body digest; the V1 public accessor deliberately
returns `Nothing`. The [second comparison](receipts/20261016T010346.908346Z-on-policy-canonical-independent-comparison-v2/result.json)
fixes that distinction but compares Store metric pairs directly with a map.
The [corrected v3 invocation](receipts/20261016T010411.568442Z-on-policy-canonical-independent-comparison-v3/result.json)
validates unique pair keys and exact metric-map equality, requires V1 plus the
absent optional V2 identity, and preserves the independent envelope-body check
and same immutable manifest address. It passes every remaining comparison.
Both failed helper sources and raw receipts remain unchanged. No producer,
source, native executable, checkpoint byte, reward bar, seed or training budget
changes between these read-only attempts.

This authentic Metal **497** result and the independently verified CPU **500**
result both exceed the same **400** criterion. Their learned weights are not
claimed to be bit-identical, and the combined correctness changes are not an
isolated causal experiment attributing either prior failure to one defect.
This is a focused single-row publication, not a full **55**-row lane journal.

Twenty canonical deterministic evaluation repeats do not establish an
independent-seed generalization interval. The complete lane journals,
independent supervised-policy obligations, RL served-artifact metric replay,
and remaining phase requirements are not supplied by these focused controls.
No floor, budget or seed is changed to obtain a diagnostic pass.

The [evidence manifest](manifest.json) records byte identities. README files
and the manifest itself are excluded from its recursive file hash set.
