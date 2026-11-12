# Phase 278 On-policy Recipe Identity Proof

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md)
**Generated sections**: none

> **Purpose**: Retain independently executed native identity captures and
> generated-contract review for the selected-device evaluation and GAE repairs.

The final comparison (`projection-identity-comparison-on-policy-final.json`)
binds the observed source
`a145173f28f63e345793df791684e81f57defa7b328cad5f3182bd5e66cd897a`.
It captures all 165 production projections and proves exactly **66 changed /
99 unchanged** relative to the earlier identities: 22 rows per lane, comprising
PPO's six rows and four each for A2C, TRPO, MaskablePPO and RecurrentPPO.

The native harness (`projection-identities-on-policy.hs.txt`) removes only the
producer-owned evaluation and rollout semantic fields, then resolves real
`RawRunRequest` values. All 66 reconstructions recover their independently
captured prior PlanIds; all 12 TRPO Fisher recipe fields remain present. All
165 report-only contract digests stay unchanged. These are structural identity
checks, not model measurements, hardware execution or a GateTranscript.

The prior capture binds `fb45…`. Its 165 identities independently match the
preserved pre-candidate generated contracts from `4b5…`, whose intervening
change affected only test formatting. The native harness is compiled against
the supported final production library at `b519…`; the exact three-golden
test-only correction leaves production unchanged. A separate actual final
`a145…` execution recomputes source before/after and proves every identity,
subject and report digest equal to the preserved `b519…` capture. Both
generations and their raw receipts remain distinct.

The independent generated-contract review (`on-policy-generated-contract-independent-review.json`)
parses all 165 rows and proves that only those 66 PlanId values change. Replacing
only PlanId values makes the entire before/after files byte-identical. The full
private source inventory changes only `web/src/Generated/Contracts.purs`, while
the host remains unchanged during generation. All 165 generated identities
agree with the independent native capture. Supported generator output and raw
inventories remain under the original packet (`raw/generated-contract-packet/`).

The old-identity reference scan (`old-on-policy-id-reference-review.json`)
finds only three stale current literals in the preserved representative golden.
The exact correction (`raw/representative-golden-correction/changes.json`)
updates those PPO/cartpole values, preserving all other bytes. After correction,
none of the 66 old identities remains in current `src`, `test` or `experiments`;
legacy negative tests reconstruct the prior identities structurally.

Actual receipts (`raw/receipts/`), exact comparison scripts,
retention-time observations (`retention-time-observations.json`),
retention map (`retention-map.json`) and manifest (`MANIFEST.json`) preserve their
original source and outcome scope. The subsequent artifact observations are
labelled as such. No old numerical measurement or trained artifact becomes
current because of this identity proof.
