# Phase 278 Current On-Policy Quality Checkpoint

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Runtime index](../README.md), [Mac validation](../../README.md)
**Generated sections**: none

> **Purpose**: Retain the first genuine strict documentation/code-quality pass
> after the on-policy corrections, before later factual status incorporation.

The current private Linux CPU CLI executes `docs check` and `check-code`
directly and both exit **0**, producing exactly `docs check: ok` and
`check-code: ok` with empty stderr. Actual command and orchestration exits agree.
The summary (`raw/summary.json`) identifies both exact raw receipts and durations.
The captured full host manifest is
`923a8c7d66321d3451ea1bab7bd5b3208e75c24261926830c53ac7aac985cccc`.
It stays unchanged during both commands; every listed private source file stays
unchanged too. Haskell source `a145173f…897a` (**383 files**), native
`4fcec957…06ba9` and current private CPU ELF `8724adb5…e6a98fd` retain their
verified identities. The commands use the resolved current private build, not
the image's baked-in executable.

The independent full private inventory binding (`raw/quality-context/final-binding.json`)
records only two newly created ignored tool outputs: `web/.spec-results` and
`web/spago.lock`. Their exact bytes and actual ignore-rule matches are retained.
The companion correction note (`raw/quality-context/postprocessing-note.json`)
records an initial read-only parser assumption of `.spec-results.json`, which
raises `AssertionError`; the actual filename is `.spec-results`. This corrects
the companion classification without changing any source, helper guard, output
byte or genuine gate result. The inline parser failure is not mislabeled as a
successful raw invocation.

The raw narrative (`raw/README.md.txt`), manifest (`raw/manifest.json`) and
retention map (`retention-map.json`) preserve the original ignored packet byte for
byte: raw argv/timestamps/stdout/stderr/codes, helper/state copies, exact source
manifest, full inventories and native/CLI bindings. No tracked files are written
during either gate. This checkpoint precedes subsequent factual documentation
and Metal-outcome incorporation; final quiet verification remains pending and
will run separately. This checkpoint does not close Phase 278 or attest a complete all-model lane.
