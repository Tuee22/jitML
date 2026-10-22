# Phase 278 Focused Apple RL Diagnostics — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Mac session](../README.md)
**Generated sections**: none

> **Purpose**: Retain sequential real Metal execution of the three changed
> canonical RL rows, fresh-publication outcomes, and supplemental physical
> checkpoint inspection without claiming a complete lane journal or phase
> validation.

Curated summaries and the two analysis scripts remain versioned. Copied source
snapshots, one-off capture/readmission helpers, raw receipts and checkpoints are
local-only diagnostics excluded from Git and Docker contexts. Historical links
to these local files do not imply that a clean checkout contains them.

The first three executions and linked numerical prefixes are **baseline evidence**
from source stamp
`ca66f0ef7956df00d38aa6a44723b5a6f3fbd503354be8bf8abc5531ef85bb46`
and native executable
`cb1806720ebd99fecf9660732956a9e112c1becc3bb9c19daf207f9ea0ee147a`.
They predate the normalized-direction Fisher repair and remain exact historical
receipts. They do not validate a subsequently rebuilt native executable.

The root session observed no `.build/checkpoints` before execution. The
[initial state](initial-state.json) independently captures its continued
absence at `2026-10-15T20:15:37.290512Z`, while the first row is running, along
with the absence of a live cluster publication. The executing host binary is
SHA-256 `cb1806720ebd99fecf9660732956a9e112c1becc3bb9c19daf207f9ea0ee147a`.
No retained product checkpoint is substituted for fresh training.

Each command runs through the local receipt runner, which retains exact argv,
working directory, UTC start/end, both raw streams, actual exit status and
output hashes. The commands run in this order on the Mac host:

```bash
.build/jitml internal train-and-publish-product-rows --apple-silicon --row PPO/key-door-grid
.build/jitml internal train-and-publish-product-rows --apple-silicon --row A2C/key-door-grid
.build/jitml internal train-and-publish-product-rows --apple-silicon --row TRPO/cartpole
```

| Row | Historical baseline execution |
|---|---|
| `PPO/key-door-grid` | Fresh eligible publication, exit `0`, **620.815 s**; `20:15:14.458535`–`20:25:35.271936 UTC` |
| `A2C/key-door-grid` | Fresh eligible publication, exit `0`, **358.534 s**; `20:29:00.803998`–`20:34:59.336694 UTC` |
| `TRPO/cartpole` | Failed convergence, exit `2`, **2,251.441 s**; `20:35:10.729402`–`21:12:42.221901 UTC`; no checkpoint published |

The [A2C preflight](a2c-preflight.json) confirms its canonical checkpoint
namespace is absent immediately before launch and the executable still matches
the initial binary hash. The intervening Apple backend and canonical
architecture gates belong to the [parent Mac session](../README.md).
The [TRPO preflight](trpo-preflight.json) independently confirms its namespace
is absent and the same executable hash is selected before its launch.

The PPO [publisher receipt](receipts/20261015T201514.457948Z-canonical-ppo-key-door-grid/result.json)
contains the fresh admitted message and **1 / 1** eligible inventory entry.
The [physical result](ppo-key-door-grid.json) and
[inspection receipt](receipts/20261015T202634.413826Z-inspect-canonical-ppo-key-door-grid-final/result.json)
cross-check manifest SHA-256
`6e91bd7587c44991b9cae6916f001df0b72549513044ae3647f319ca61d729a0`,
PlanId `d672dd1f583df04c413b37dd8c3ace9f22eda5d7b3a0f0c10bc6db930795231e`,
**1,228,800** observed transitions and **38,400** optimizer applications.
All **20** trajectory episodes have reward **1.43** and **10** steps; their
independently derived median equals the admitted metric and clears its **0.5**
criterion. The final physical weight SHA-256 is
`21ce1a8c316e1f023d0ce330d0e92c1da896c536e6f7662d2aa54cc07c57d992`.
The latest pointer remains stable through inspection. The exact local
checkpoint namespace, including committed snapshot, physical weight blob and
trajectory, is retained under `checkpoint-snapshot/`; its Metal source artifact
is retained under `device-artifacts/`. The inspector also checks that the
device artifact bytes match the embedded executed witness.

The A2C [publisher receipt](receipts/20261015T202900.803463Z-canonical-a2c-key-door-grid/result.json),
[inspection receipt](receipts/20261015T203511.894078Z-inspect-canonical-a2c-key-door-grid/result.json)
and [physical result](a2c-key-door-grid.json) retain another fresh eligible
publication. Manifest SHA-256 is
`d041057f7b7a056de50fcd8f2338cde221f8890c94070dcd2d623feed864fd36`;
PlanId is `3aaa1d9a17309e5ce444a85739b61d065435c1afa21721b848ef2b34b9f39ffc`.
It records **1,228,800** transitions, **19,200** optimizer applications and
**20** evaluation episodes, each returning **1.43** over **10** steps with
seed **42**, clearing the admitted **0.5** bar. Its physical final weight hash
is `947f3250df179ae6d507129d7a7f3de0189b49b4290bf1131650af4f4b88e34c`.
The inspector verifies stable pointer, matching physical artifacts and exact
completion bindings; this namespace is retained beside PPO's snapshot.

The fresh TRPO [command receipt](receipts/20261015T203510.728952Z-canonical-trpo-cartpole/result.json)
and [failure summary](trpo-cartpole-failure.json) reproduce median final reward
**188.0** against the unchanged **400.0** criterion, after **1,228,800**
environment transitions and **20** evaluation episodes. The publisher exits
`2` with **0** eligible rows, **1** publication error, **0** admitted inventory
entries and manifest `none`. Its canonical local checkpoint namespace is still
absent after execution. Completion fails before trajectory/checkpoint
persistence, so no admitted manifest, PlanId, physical final-weight hash or
optimizer-count proof is claimed for this failed row.

All three requested focused commands have reached their real terminal result:
two fresh eligible publications and one convergence failure. The
[evidence manifest](manifest.json) records receipt and retained physical-object
hashes. The reproduced **188** result is a historical convergence failure. The later
numerical prefixes and Fisher repair are retained separately below; the
repaired full canonical diagnostic also fails, at **219** against **400**.

The normal fresh RL publisher invokes production exact Store admission,
requires the stored and admitted manifest identity to match, and validates the
projected PlanId and completion before rendering an eligible inventory row.
The [physical inspector](inspect-physical-publication.py) supplements a
successful fresh publisher receipt: it decodes the narrow weight-only envelope,
checks its physical hashes, stable latest pointer, weight bytes and trajectory
metrics. It does not reimplement Store admission or completion refinement.

These commands are focused diagnostic publications. They do not execute the
complete 55-row ProductScenario, mint its authenticated journal, replace a
standing integration GateTranscript, resolve the independent supervised-anchor
obligation, or release a later numerical phase. No bar or training recipe is
changed to make a diagnostic pass.

The [TRPO numerical prefix diagnostics](trpo-prefix/README.md) retain real Metal
and independent aligned Float32 comparisons through one and three complete
iterations, an observed finite-difference Fisher homogeneity failure, actual CG
perturbation-collapse measurements, and raw receipts pinned to the unchanged
source and native binary. They establish no full-run convergence or phase
closure.

The [Fisher repair validation](trpo-fisher-repair/README.md) retains the
normalized-direction repair, scoped identity and pure controls, actual Metal
homogeneity regression, all intermediate compiler/test failures, and final
source `4b5a03b80a728d60ebe7fb013e59ba6d5a133e8b1cc124dc017501a53ac29e43`.
Its full Apple backends pass **26 / 26**; the full Mac unit suite remains
failed with **1,533 / 1,551** passing and the same **18** retained-evidence
failures. The unchanged full-budget repaired `TRPO/cartpole` diagnostic returns
**219 < 400**, exit **2**, after **2,404.260 s**, with no checkpoint publication.
The preflight/postflight prove a fresh absent namespace and unchanged native
SHA-256 `73cd7e1502bf4841a6d2a2d11d22c0ca4f84d19c4095d82cd2d675601ebbb24d`.
No successful Store readmission, convergence or phase closure is claimed for
that failed invocation.

The [on-policy evaluation and time-limit repair](on-policy-repair/README.md)
retains the current source `a145` and native `4fce`: full real Metal backends
**28 / 28 pass**; full Mac units **1,551 / 1,569 pass**, with the same **18**
retained-evidence failures and **zero** unknown failures. It preserves the
intermediate **19**-failure stale-golden result and exact correction. A fresh
full-budget Metal TRPO/cartpole run now **passes**, median **497** against the
unchanged **400** bar, with **1,228,800** transitions and **192,150** updates.
Its actual fresh publisher, exact/current/completed/latest Store readmission
and physical-byte comparison pass. The checkpoint, device source artifact,
failed helper comparisons and successful correction are retained. The preceding
**188** and **219** results remain historical measurements of their respective
recipes. Neither this single-row result nor CPU **500** replaces a complete
lane journal or closes Phase 278.
