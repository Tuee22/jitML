# Phase 278 Current CPU TRPO Publication

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Retain one fresh canonical CPU TRPO result and independent
> physical/public-Store verification on the corrected on-policy recipe.

The current Linux CPU `TRPO/cartpole` production publisher succeeds on source
`a145173f…897a`, using unchanged seed **42**, **150 × 512 × 16 = 1,228,800**
transitions and return bar **400**. Its twenty selected-device evaluation
trajectories each return **500** in **500 steps**. The stored median/average is
**500**; the actual completion reports **192,150 optimizer applications**.
The single fresh invocation exits **0** in **320.600 s**, publishes one eligible
checkpoint, and admits exactly one inventory entry. No seed, budget, bar or
architecture retune occurs.

The [physical inspection](raw/source-and-runtime-packet/readmission/physical-readback.json)
and newly compiled [production Store re-admission](raw/source-and-runtime-packet/readmission/store-readmission.json)
both execute and pass. The latter calls exact-address admission, completed-scope
refinement and latest-pointer admission, and compares the actual current typed
PlanId and training budget. The current PlanId is
`140b0d1e6a970b0261e92119288a28cb288c7ebc99ff9aa7ac0452235b885d7e`;
the immutable manifest address is
`4f6735db07b4c826bde04839ac3379b4160c7a9bee0df8cb743ca01f2b4f42b9`.
The [physical-byte copies](raw/source-and-runtime-packet/readmission/actual-physical-bytes/manifest.cbor)
include the original CBOR, latest pointer, learned JMW1 weights and evaluation
trajectory, all verified against their actual addresses. The learned-weight
JMW1 hash is `3baa6fbd80a2cd092cbad4b81135924be1eba9b88168d061ba8a30013aa5a398`.

The [execution binding](raw/source-and-runtime-packet/run-binding.json) and
[readback binding](raw/source-and-runtime-packet/readmission/readback-binding.json)
retain unchanged full private/host inventories, source/CLI/compiled-library
identities, native binary binding and the fresh namespace preflight. The active
process loads the actual CPU JIT MLP artifact. This lane's small MLP uses
deterministic C++ float loops; that observation does not claim a `libdnnl`
primitive call. The full backend tests separately cover those primitives.
The current CPU ELF is `8724adb5…e6a98fd`; native `4fcec957…06ba9` stays fixed.
Inspector sources, actual package IDs, compilation, exact argv, timestamps,
stdout/stderr, exit codes and inspector ELF identity remain in the raw packet;
executable caches are excluded.

This is **one passing current CPU row**, not a complete 55-row lane journal,
another substrate's result, a full unit-suite pass, or Phase 278 closure. Earlier
`4b5…` CPU **230** / Metal **219** results and the separate full-budget diagnostic
remain historical evidence without a causal attribution or retroactive rewrite.
The [raw narrative](raw/README.md.txt), [summary](raw/summary.json),
[manifest](raw/manifest.json) and [retention map](retention-map.json) preserve the
original ignored packet byte for byte. The runtime index owns standing-gate and
other-substrate evidence separately.
