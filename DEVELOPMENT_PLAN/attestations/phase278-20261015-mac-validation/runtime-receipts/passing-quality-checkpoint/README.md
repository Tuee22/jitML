# Phase 278 Passing Strict Quality Checkpoint

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Retain the genuine final-source strict quality pass after the
> generated-contract and two-test formatting corrections.

| Real current-private-CLI invocation | Actual / orchestration exit | Output and elapsed time |
|---|---:|---|
| [Docs check](steps/20261015T231139.718537Z-linux-cpu-docs/result.json) | 0 / 0 | `docs check: ok`, 0.352312 s |
| [Check-code](steps/20261015T231146.910304Z-linux-cpu-check-code/result.json) | 0 / 0 | `check-code: ok`, 148.075926 s |

Both stderr streams are empty. Their exact source bindings require the complete
host and private listed tree to remain unchanged, with no receipt-only exception:
snapshot **123e60ff56fc04a42402338c13c011623f751077bdae78c830d2465a944c3644**.
The code source is `4b5…`, current Linux ELF `064aa7c9…e6640`, and pinned native
binary `73cd7e15…1ebbb24d`. The helper resolves the actual private build through
read-only `cabal list-bin`, records its identity, and invokes it directly.

The [independent checks](verification.json), raw command/stdout/stderr/result
files, before/after bindings, [source manifest](snapshot-manifest.json),
[state](state-at-passing-checkpoint.json), and
[helper snapshot](runner-at-quality-checkpoint.py.txt) retain this exact
checkpoint. The [retention script](retain-passing-quality-checkpoint.py.txt)
checks terminal exits, exact outputs, stream hashes, complete manifest equality,
and code/native identities. No gate result is synthesized.

This genuine strict pass is distinct from the earlier
[private candidate rehearsal](../pre-final-quality/README.md). The retained
checkpoint precedes the final factual index update; unchanged-tree verification
after that update is separate from these bytes. Neither quality pass changes
the eighteen stale-journal unit failures, TRPO's **219 / 230 < 400** misses,
the independent criterion/seed scope, or Phase `278`'s remaining obligations.
