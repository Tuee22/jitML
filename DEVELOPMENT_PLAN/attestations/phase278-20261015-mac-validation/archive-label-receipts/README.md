# Phase 278 Archive Diagnostic Receipts — 2026-10-15

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Archive label review](../archive-label-review.md)
**Generated sections**: none

> **Purpose**: Preserve exact command arguments, working directories, UTC
> timestamps, raw stdout/stderr, signal outcomes, and actual process exit
> statuses for archive acquisition and dataset-only split calculations.

Only this curated summary remains versioned. The receipt payloads, inventories
and copied runner referenced below are local-only diagnostics excluded from Git
and Docker contexts.

[manifest.json](manifest.json) indexes the receipts and pins the diagnostic
script and retained JSON. Every invocation directory contains `command.json`,
`result.json`, `stdout.log`, and `stderr.log`. The
[local runner snapshot](run-command.py.txt) describes capture and signal
forwarding. These receipts do not mint jitML GateTranscripts.

| Invocation | Exit | Interpretation |
|---|---:|---|
| [Original CIFAR-10 download](20261015T194731.908048Z-cifar10-download/result.json) | 143 | Slow incomplete origin transfer stopped after verified mirror acquisition; never parsed |
| [Original CIFAR-100 download](20261015T194733.047973Z-cifar100-download/result.json) | 143 | Slow incomplete origin transfer stopped after verified mirror acquisition; never parsed |
| [Tiny upstream download](20261015T194734.203011Z-tiny-imagenet-download/result.json) | 0 | Complete production-pinned archive |
| [MXNet mirror probe](20261015T194921.261226Z-cifar10-mirror-head/result.json) | 60 | Certificate hostname mismatch; certificate verification was retained |
| [CIFAR-100 origin headers](20261015T194921.261226Z-cifar100-origin-head/result.json) | 0 | Official redirect, length, and byte-range diagnostic |
| [CIFAR-10 range probe](20261015T194943.812897Z-cifar10-range-probe/result.json) | 0 | Exactly 1,024 diagnostic bytes; never parsed as a dataset |
| [Parallel range attempt](20261015T195014.427401Z-cifar-ranged-download/result.json) | 130 | Connection resets; interrupted without admitting any partial artifact |
| [Bounded range retry](20261015T195035.760964Z-cifar-ranged-download-bounded-retry/result.json) | 143 | Stalled connections; interrupted without admitting any partial artifact |
| [Origin HTTP headers](20261015T195114.095065Z-cifar-cave-http-head/result.json) | 0 | HTTPS redirect diagnostic |
| [CIFAR-10 mirror download](20261015T195144.695014Z-cifar10-brainchip-download/result.json) | 0 | Complete archive; exact production SHA checked separately |
| [CIFAR-100 mirror headers](20261015T195145.850682Z-cifar100-brainchip-head/result.json) | 0 | Length diagnostic |
| [CIFAR-100 mirror download](20261015T195200.026497Z-cifar100-brainchip-download/result.json) | 0 | Complete archive; exact production SHA checked separately |
| [Verify and promote CIFAR copies](20261015T195220.867638Z-verify-promote-cifar-mirrors/result.json) | 0 | Reads current production pins, verifies complete archive hashes, then promotes local filenames |
| [Superseded source assertion](20261015T195252.915332Z-archive-label-baselines/result.json) | 1 | Diagnostic's historical-source assertion correctly ceased matching after the concurrent Tiny repair; no archive parsed |
| [Historical first calculation](20261015T195444.792969Z-archive-label-baselines-verified/result.json) | 0 | Complete production-pinned label and image-identity diagnostic before formatting |
| [Historical second invocation](20261015T195505.021441Z-archive-label-baselines-reproduction/result.json) | 0 | Repeats the complete calculation from archives before formatting |
| [Historical byte comparison](20261015T195613.211943Z-archive-label-reproduction-comparison/result.json) | 0 | Both historical stdout payloads and retained JSON are byte-identical: 96,462 bytes, SHA-256 `f6915f0d6c8398a2c7527d3af8214b2b2fbbe4432ca1cf91108536627caefbf3` |
| [Historical formatted-tree calculation](20261015T200932.019690Z-archive-label-baselines-formatted/result.json) | 0 | Complete archive calculation after container formatting |
| [Historical formatted-tree reproduction](20261015T200939.929801Z-archive-label-baselines-formatted-reproduction/result.json) | 0 | Second complete archive calculation after formatting |
| [Historical comparison and source pins](20261015T201000.872900Z-archive-label-formatted-comparison/result.json) | 0 | At that time both payloads equal the preserved historical JSON byte for byte, and all five consulted source hashes match that formatted tree |


The final frozen source `c4a42c3ae80951d5d4b33ee6d0981b64e385c0648ec6c8ae352423efba710625`
changes only the consulted `Matrix.hs` hash after TRPO recipe identity versioning.
Two new complete dataset calculations both exit `0` and reproduce the current
**96,462-byte** JSON, SHA-256
`d0b009229c4aac7dcdd7c0102752850d873f327c478a2441346027e181c24b92`.
All dataset statistics and the other four consulted source hashes are unchanged;
no diagnostic assertion adjustment is necessary. The previous JSON, manifest
and report text are preserved under
[historical-before-trpo-recipe-version](historical-before-trpo-recipe-version/).
The older raw receipts retain their exact original bytes.

| Current frozen-source invocation | Exit | Interpretation |
|---|---:|---|
| [Complete calculation](20261015T214309.276954Z-archive-label-baselines-final-source/result.json) | 0 | Production archive SHA checks before parsing; current consulted source hashes |
| [Complete reproduction](20261015T214309.276903Z-archive-label-baselines-final-source-reproduction/result.json) | 0 | Independent complete invocation with identical stdout bytes |
| [Byte comparison and source checks](20261015T214353.112221Z-archive-label-final-source-comparison/result.json) | 0 | Exact current equality, historical bytes preserved, only Matrix pin changed, all dataset statistics unchanged |

All raw dataset bytes and incomplete transfers remain outside the tracked
attestation tree. A complete hash match is required before parsing; failed
transport probes and intentional interruptions are diagnostics, not passing
dataset calculations or substrate tests.
