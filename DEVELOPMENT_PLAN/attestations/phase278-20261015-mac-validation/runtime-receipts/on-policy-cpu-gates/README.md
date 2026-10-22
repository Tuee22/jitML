# Phase 278 On-policy Repair CPU Gates

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md)
**Generated sections**: none

> **Purpose**: Preserve the actual current CPU gate records, intermediate failed
> attempts and exact source/process bindings, with unchanged canonical promotion.

The final 383-file source stamp is
`a145173f28f63e345793df791684e81f57defa7b328cad5f3182bd5e66cd897a`.
The producer CLI is the Linux ELF
`8724adb5ec97f4c743ee842cf012f005ab0c02de0239c91416bd2dae1e6a98fd`;
the pinned native executable is
`4fcec9579ab0f0d456bc01dc3acd11dbbcfae474d6dca0adc9bcc35e3dc06ba9`.

| Genuine final invocation | Actual / orchestration exit | Result |
|---|---:|---|
| [Supported build](raw/cpu-steps/20261016T001812.622150Z-linux-cpu-build/result.json) | 0 / 0 | Warm supported build, 0.245 s |
| [Full unit suite](raw/cpu-steps/20261016T001918.990137Z-linux-cpu-unit/result.json) | 1 / 1 | 1,551 / 1,569 pass; exactly the prior 18 stale-journal failures, 48.18 s body |
| [Full CPU backend lane](raw/cpu-steps/20261016T001827.616005Z-linux-cpu-backends/result.json) | 0 / 0 | 41 / 41 pass, 2.26 s body |

The [unit verification](independent-verification/jitml-unit/verification.json)
and [backend verification](independent-verification/jitml-backends/verification.json)
independently check canonical serialization, exact standing commands, source and
executable identities, actual exits and complete source bindings. Exact
subprocess streams are recovered from the CLI's fixed display indentation;
producer hashes select the terminal-newline form. Failed unit streams also match
the producer's embedded bytes. Both gates retain unchanged complete host/private
inventories and native identity during their actual execution.

The [actual unit-body observation](raw/cpu-steps/20261016T001915.062753Z-on-policy-final-active-jitml-unit/stdout.log)
captures PID 13363, and the [actual backend-body observation](raw/cpu-steps/20261016T001822.777073Z-on-policy-final-active-jitml-backends/stdout.log)
captures PID 12279. Both have `JITML_SUBSTRATE=linux-cpu` and no TASTY variables.
The unit argv is unfiltered; backend argv contains only the required `-p linux-cpu`.

The genuine [Failed unit producer record](raw/cpu-steps/20261016T001918.990137Z-linux-cpu-unit/production-validation/jitml-unit.linux-cpu.json)
has SHA-256 `a453401a042757144715f03aa0b214692dd165e375f942f5ddf541d02d21e232`.
The genuine [Passed backend record](raw/cpu-steps/20261016T001827.616005Z-linux-cpu-backends/production-validation/jitml-backends.linux-cpu.json)
has SHA-256 `9b653a8e5cca0987911c963c23c757cbfcf5d4cb798cd6285ef992f5e73e5573`.
[Promotion](promotion.json) copies those exact bytes into canonical inputs only
after preserving both [superseded 4b5 records](superseded-4b5-validation-records/).
Failed remains Failed. No transcript or passing gate is synthesized.

The [historical b519 failure](historical-b519-failed-unit/verification.json)
retains the actual 1,550 / 1,569 result: the same 18 journal failures plus the
representative PPO PlanId golden. That genuine Failed record is preserved at
SHA-256 `5e1b618d88fb183e4da1080642885e50dd6275ff174acdd3173b52d5afafc889`.
The first independent recovery verifier counted Cabal's suite summary as another
case; its failed receipt and exact script are retained separately from the
corrected successful recovery. Neither attempt reruns or changes a test.

The 194 terminal helper receipts and preparation packets retain the earlier
source generations, formatting/compile attempts, source-sync guards and genuine
outcomes as recorded. A copied `production-validation` directory can contain
earlier incidental records; only the two final producer paths identified above
prove the current gate pair. Historical records are not relabelled by retention.
Current CPU TRPO publication is retained separately in
[its canonical execution package](../on-policy-cpu-trpo/README.md).

[Retention-time observations](retention-time-observations.json) record actual
native/harness and source-file hashes after execution; they do not pretend to
have been captured before each run. The exact helper and verifier snapshots,
[retention map](retention-map.json) and [local manifest](MANIFEST.json) identify
all retained bytes. Raw code and Markdown suffix changes are explicit in the
map; contents remain byte-identical. These results do not close Phase 278.
