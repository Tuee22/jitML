# Phase 278 TRPO Numerical Prefix Diagnostics — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Focused Apple RL diagnostics](../README.md)
**Generated sections**: none

> **Purpose**: Retain real Metal and independent Float32 operation comparisons
> and finite-difference Fisher precision evidence without claiming canonical
> convergence, publication, or phase validation.

At the baseline source and executable identified below, the canonical
`TRPO/cartpole` publication fails its median
`400` criterion at `188`; the [parent evidence](../README.md) retains that full
execution and its absent checkpoint. These historical baseline probes predate
the normalized-direction Fisher repair. They run the complete
shared TRPO loop for explicitly short prefixes. They change only
`ppoNumIterations` from `150` to `1` or `3`. They preserve seed `42`, hidden
width `256`, vector environments `16`, rollout `512`, minibatch `64`, ten CG
iterations, damping `0.1`, ten backtracking candidates with coefficient `0.8`,
ten complete critic passes, critic learning rate `0.001`, and KL bound `0.01`.

The standalone harness source (`trpo-prefix-probe.hs.txt`) links against the
existing native library; it edits no production module and publishes no
checkpoint. Its independent Float32 forward and parameter-gradient operations
round parameters, inputs and upstream gradients at the device ABI boundary,
use ordered Float32 accumulation, and express the existing backend fixture's
glibc Float32 `tanh`/`expm1` operation sequence in Haskell. They do not call
Darwin's native Float `tanh`. Indexed vectors replace the fixture's linked-list
indexing while preserving arithmetic. Single-example and input-gradient
operations fail closed because this training path uses neither. The independent
device returns no execution witness.

Each Metal operation is shadowed against that oracle using its exact current
parameters and input. A separate complete training invocation then uses only
the independent Float32 device. Every batched operation retains its ordinal,
kind, batch size, parameter/input/upstream/output hashes in both Double and
Float byte representations, and the shadow comparison. Full-batch records also
retain parameter, output and upstream values for CG reconstruction. The
manifest (`manifest.json`) identifies all four exact ignored raw traces by path,
byte count and SHA-256; their bytes remain under `.build/phase278-mac-validation/`.
Small summaries, complete returned parameter vectors, raw command receipts and
the source snapshots are retained here. The receipt runner snapshot is
available (`run-command.py.txt`).

The exact baseline PpoTrainer source (`baseline-PpoTrainer.hs.txt`) is recovered
with read-only `git show HEAD:src/JitML/RL/Algorithms/PpoTrainer.hs`.
Its `89,151` bytes have SHA-256
`c70c20e38719dfa0d74744c7fe1a46bef5a5eec54ffdcef8056f175897754b7e`,
which exactly matches the source identity captured before both probes.
The recovery record (`baseline-source-recovery.json`) retains the command and
comparison. Other consulted production modules are identified by their captured
hashes; their complete source contents are not retained in this package.

| Prefix | Real Metal with shadow | Independent Float32 | Measured transitions / updates | Final Double-byte parameter agreement |
|---|---:|---:|---:|---|
| One iteration | `26.802 s` | `12.824 s` | `8,192 / 1,281` each | Exact: `76db3466072914a66a50bd792237b29edfa5b979b8f3f4fc8b94dc5cf1ee4277` |
| Three iterations | `80.218 s` | `38.086 s` | `24,576 / 3,843` each | Exact: `27ae5e6144725d36e2b5c673b92b997445ad38dc7ea7d515437a0a6a4c493135` |

Both invocations exit `0`. The one-iteration analysis (`one-analysis.json`) covers
`3,110` operations per device; the three-iteration analysis (`three-analysis.json`)
covers `9,330`. All operation, batch-size, parameter, input and upstream hashes
agree at every ordinal. All Metal shadow comparisons have zero numerical
difference. Gradient output bits differ only in the sign of zero in `50` and
`340` critic operations respectively. The first such event is ordinal `577`,
batch `64`, flat gradient index `1307`: oracle `-0`, Metal `+0`. The restored
actor slices and final parameter bytes agree exactly. The three rollout medians
are `15`, `18`, and `23` in both runs. This establishes numerical agreement over
these prefixes; it does not establish agreement after all `150` iterations or
identify the cause of the retained full-lane reward difference.

Source stamp `ca66f0ef7956df00d38aa6a44723b5a6f3fbd503354be8bf8abc5531ef85bb46`
and native executable SHA-256
`cb1806720ebd99fecf9660732956a9e112c1becc3bb9c19daf207f9ea0ee147a`
are stable before and after both probes. The diagnostic executable is SHA-256
`4230c5837589cda7a5a7cd358fd75f0975974aae00fff10cd7d833671052adf2`.
The one-iteration (`one-summary.json`) and three-iteration (`three-summary.json`)
summaries retain exact UTC intervals, consulted source-file hashes, the real
Metal witness and the initial parameter identity.

The minimal real Metal diagnostic separately demonstrates a finite-difference
Fisher defect in the current shared device algorithm. It uses a fixed
`4 × 1 × 3` MLP and a direction with one nonzero actor `W2` coordinate at a
nonzero weight and hidden activation. At direction norm `1`, parameter
perturbations are distinct and the undamped Fisher contribution is nonzero.
At norm `1e-8`, current epsilon remains `0.001`; both parameter perturbations
round to identical Float32 bytes, SHA-256
`137a3bb992f81d72475c618f19ba6bec17fce9d77674c599b4cdcb892aaa6834`,
and produce identical outputs. The returned operator is then damping only:
the active `W2` component is `1e-9`, whereas scaling the unscaled operator
predicts `1.2059482224285604e-9` plus nonzero cross-coordinate contributions.
The exact minimal measurement (`one-fisher-minimal.json`) retains both parameter
hash representations, all outputs and the homogeneity discrepancy.

That loss of Float32 perturbation resolution occurs during the actual canonical
prefix too. The first iteration's ten reconstructed CG directions shrink from
norm `0.1731646` to `5.27465e-7`; active-coordinate perturbation collapses grow
from `4 / 1,794` to `1,527 / 1,794`. The last direction has `13,402 / 16,384`
zero policy-logit finite differences. The final natural direction retains
positive curvature `0.015249941668064338`. All three actor searches accept
their first candidate, with categorical KL recomputed from traced logits of
`0.0094533482`, `0.0088850996`, and `0.0083280141`. Reconstructed perturbation
parameters agree within `2.8e-17` in the first iteration and candidate parameters
within `2.3e-16`. The analyses retain per-direction norms, residuals, curvature,
collapse counts, candidate indexes and reconstruction errors.

The [analysis script](../analyze-trpo-prefix.py) reconstructs those quantities
from observed operations; production exposes no CG callback. Sampled actions,
unrounded GAE advantages and critic targets are not retained by this seam, so
exact surrogate losses and critic losses are explicitly unavailable. The
observed precision defect affects the shared Float32 operator and is a concrete
repair candidate. These measurements alone do not attribute the full Metal
`188` versus retained CPU/CUDA `500` reward difference to that defect.

Exact compile and execution argv, raw stdout/stderr, UTC start/end, actual exit
codes and stream hashes are under receipts (`receipts/`). The two execution
commands are:

```bash
.build/phase278-mac-validation/trpo-prefix-probe 1 .build/phase278-mac-validation/trpo-prefix-one
.build/phase278-mac-validation/trpo-prefix-probe 3 .build/phase278-mac-validation/trpo-prefix-three
```

The output directory must be fresh. The build receipt contains exact package
IDs and the independent harness compile command. Restore the source snapshot
to its recorded `.build/phase278-mac-validation/trpo-prefix-probe.hs` path
before reproducing that compile. Raw receipts remain historical diagnostics;
the native binary, source stamp and experiment identities must be checked for
any later invocation.
