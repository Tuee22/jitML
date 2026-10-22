# Phase 278 Production Haskell Tiny Decoder Diagnostic — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Current Mac validation](../README.md), [Supervised execution review](../supervised-execution-review.md), [Phase 278](../../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md)
**Generated sections**: none

> **Purpose**: Retain actual pinned-archive decoding through the compiled production Tiny loader and compare its fully evaluated outputs with the independent dataset calculation.

This curated summary and the decoder/comparison probe sources remain versioned.
Generated result JSON, provenance/manifests, copied receipt runner, raw
`receipts/` captures and compiler package metadata are local-only diagnostics
excluded from Git and Docker contexts. Links to those artifacts below refer to
the original local bytes, not a complete clean-checkout bundle.

The final diagnostic exits `0`. It calls the existing compiled
[`SL.TinyImageNet`](../../../../src/JitML/SL/TinyImageNet.hs) decoders on the
complete pinned ZIP, materializes all 9,600 training-prefix and 1,000 held-out
images, and forces **130,252,800 feature values** through finite checks and
deterministic scalar aggregates. This is dataset decoding on the Mac CPU.
It performs no model training, GPU execution, cluster operation, test-stanza
change, or GateTranscript issuance. It does not close Phase `278` or establish
published-model convergence.

## Exact returned data

The [decoded result](decoded-result.json) retains all label histograms, feature
counts/widths, finite checks, and ordered feature/squared-feature sums.
[`LabeledExample`](../../../../src/JitML/SL/Classifier.hs) has a strict vector
field; the retained probe additionally applies a strict vector fold to every
feature and forces the encoded summary before the final input/source checks.
The result therefore exercises JPEG decompression and pixel-vector production,
rather than extracting labels from a lazy result alone.

| Production decoder partition | Images | Represented classes | Largest class count | Forced finite features |
|---|---:|---:|---:|---:|
| First 8,000 training-prefix images: gradient partition | 8,000 | 200 | 40 | 98,304,000 |
| Next 1,600 training-prefix images: selection partition | 1,600 | 200 | 8 | 19,660,800 |
| First 1,000 held-out annotations | 1,000 | 196 | 10 | 12,288,000 |

Every image has **12,288** returned features, corresponding to 64 × 64 × 3.
All 200 gradient counts equal 40; all 200 selection counts equal eight. The
compiled `classificationMinimumCorrect` returns **15**, using the exact
held-out labels and canonical class count 200. No classifier predictions or
trained scores determine that count.

The [independent comparison](independent-comparison.json) exits `0` and checks
all three full histograms, including every class count, against the prior
[Python archive-label calculation](../archive-label-baselines.json). It also
checks the count floor, finite feature totals, and unchanged bindings.
The Python calculation reads archive metadata/labels and supplies no pixel
oracle. Feature aggregates demonstrate traversal of actual decoded pixels;
they are retained observations, not model-acceptance targets or substrate
numerical fixtures.

## Input, source, and executable identities

The archive contains **248,100,043 bytes**. Before decoding, its SHA-256 equals
the production `canonicalArtifactSha256For` pin; a separate file read after all
feature folds returns the same length and hash:

`6198c8ae015e2b3e007c7841da39ec069199b9aa3bfa943a462022fe5e43c821`.

The production source digest, algorithm `1`, is unchanged before and after:

`ca66f0ef7956df00d38aa6a44723b5a6f3fbd503354be8bf8abc5531ef85bb46`.

The decoded JSON also records before/after byte identities for the Tiny loader,
dataset pins, learning-signal policy, `jitml.cabal`, and `cabal.project`, plus
the unchanged `.build/jitml` identity. Its selection contract is
`tiny-imagenet-training-class-interleaved-v1`.

The probe is an **arm64 Mach-O** built with the installed GHC **9.12.4** through
Cabal **3.16.1.0** and the already compiled local `jitml` library. The exact
successful compiler argv names `-hide-all-packages` and explicit current-plan
package IDs, including the local `jitml-0.1.0.0-inplace` unit. The
[package registration](jitml-package.conf.txt) and
[provenance](provenance.json) retain its package/library paths, dependency IDs,
and compiled production library artifact hashes.

The diagnostic executable has **89,241,992 bytes**, SHA-256
`91bc1bd495a6a2bf6172c6741a8af44846f1b520f4268d3637ed79822c177e22`.
It remains under ignored `.build/phase278-mac-validation/tiny-production-loader`;
its large native bytes are not copied into this attestation. The exact executed
[Haskell source](tiny-production-loader.hs.txt),
[comparison source](compare-tiny-production-loader.py.txt), and
[receipt runner](run-command.py.txt) are retained as text without alteration.
No production module or pinned Mac executable is overwritten.

## Commands and authentic outcomes

The exact command vectors, cwd, timestamps, both unmodified output streams,
output hashes, and exit codes are retained in these receipt directories:

| Attempt | Exit | Exact receipt |
|---|---:|---|
| Initial package-metadata query | 1 | [Command and failure](receipts/20261015T204400.559990Z-tiny-production-loader-package/result.json) |
| Initial probe compilation | 1 | [Command and failure](receipts/20261015T204406.568217Z-tiny-production-loader-build/result.json) |
| Compilation using exact package IDs | 0 | [Successful build](receipts/20261015T204434.632741Z-tiny-production-loader-build-exact-package-ids/result.json) |
| Production loader on the actual pinned archive | 0 | [Successful decode](receipts/20261015T204447.372205Z-tiny-production-loader-actual-pinned-archive/result.json) |
| Independent full-histogram comparison | 0 | [Successful comparison](receipts/20261015T204626.879756Z-tiny-production-loader-independent-comparison/result.json) |

The first query fails because `cabal exec` supplies a package-environment option
that `ghc-pkg` does not accept. The initial compilation exposes two installed
Aeson versions and fails with an ambiguous import. The successful compilation
selects the exact already-installed package IDs from the current Cabal plan;
it installs no tool or dependency. Both failed attempts remain unchanged and
are not reported as validation passes.

The final execution command is:

```bash
# Example: reproduce the retained input-only diagnostic using its ignored native executable.
.build/phase278-mac-validation/tiny-production-loader .build/phase278-anchor-review/datasets/tiny-imagenet-200.zip .build/phase278-mac-validation/tiny-production-loader-result.json +RTS -s -RTS
```

The receipt measures **15.800 seconds** for the complete child invocation.
The runtime statistics report **14.804 seconds** of program elapsed time,
**1,032,188,784 bytes** maximum residency across six samples, and **1,908 MiB**
total runtime memory in use. Those numbers describe this decoder/summary probe,
not canonical training, GPU memory, or a general peak-memory guarantee. The
[supervised execution review](../supervised-execution-review.md) retains the
separate training recipe and its resource lower bound.

The [manifest](manifest.json) lists SHA-256 and byte lengths of the exact
retained raw artifacts. It excludes itself and this navigation page. The
independent published-anchor decision, fresh complete lane journals, and
standing phase gates remain open in [Phase 278](../../../phase-278-external-bars-no-self-referential-gate-lint-and-exact-served.md).
