# Phase 278 Bounded CPU TRPO Operator Diagnostic

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Measure the repaired Fisher/CG operator on one real captured
> initial training batch without attributing the full canonical failures.

The actual one-iteration production trainer executes **8,192 transitions** and
**1,281 observed optimizer applications**, runtime **6.350 s**, exit `0`.
These counts belong only to this prefix. Both full failed canonical runs keep
their separately reported scope; their optimizer counts are not inferred.
The source is `4b5…`, current Linux ELF `064aa7c9…e6640`, native `73cd7e15…1ebbb24d`.
Private source/executable and the host manifest stay unchanged during execution.

The original narrative (`raw/README.md.txt`), original manifest (`raw/manifest.json`),
and retention map (`retention-map.json`) retain the exact observations, source,
all four immutable attempt folders, and raw receipts. Three setup/compile
attempts fail before any training; the fourth compiles and runs. Original
package identities and compiled-library hashes remain available; no executable
or build cache is copied.

The probe binds all 513 vectorized rollout forward calls to the actual
8,192-example actor-gradient batch using packed binary64 equality. Its public
`conjugateGradientSolveDevice` / repaired `trpoFisherVectorProductDevice` replay
has **10** callbacks; every perturbed parameter, input, and output matches the
original production Fisher forwards byte-for-byte. The reconstructed recurrence
returns the identical solution. Fisher-only RolloutStep fields irrelevant to
that operator are valid placeholders, explicitly distinct from captured
actions/GAE/returns.

For individually normalized actual initial/tail directions, undamped curvature
is **1.94698 / 0.0385601**, additivity relative error **5.12e-6**, and symmetry
relative error **1.78e-6**. The recomputed residual is **7.26e-6 relative**
(**1.26e-6 absolute**), versus recursive **6.07e-10 relative**. The tail
`pᵀFp = 1.56e-21` reaches the existing truncation condition. The independent
analytic Double-Jacobian shadow differs by **3.36e-6 / 2.93e-5 relative**;
it is a diagnostic reference, not a Float32 oracle or device fallback.

This establishes the bounded operator/residual observations and continued
nonzero undamped curvature. It does not identify the cause of Metal **219** or
CPU **230**, prove full convergence, justify another production correction, or
authorize a new seed, budget, or criterion. No checkpoint, journal,
GateTranscript, or phase closure is issued by the probe.
