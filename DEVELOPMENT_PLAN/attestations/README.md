# Attestation Retention

**Status**: Supporting reference
**Supersedes**: N/A
**Referenced by**: [Plan standards](../development_plan_standards.md#n-evidence-derived-product-status-and-thin-closure-narrative)
**Generated sections**: none

> **Purpose**: Distinguish deliberate versioned evidence and review data from
> local execution artifacts that must stay outside Git and Docker contexts.

Keep this directory selectively versioned. Both ignore files exclude new
attestation payloads by default and explicitly admit the families and review
inputs below. Ignoring the entire directory without those exceptions would
remove data that the current status and admission code reads from a clean
checkout. File extensions alone do not identify disposable data: selected
criterion artifacts use `.bin` and `.cbor` for ordinary review data, while raw
execution output can also use `.json`.

Git admits the documented file families; Docker lists their current deliberate
files as literal paths. Update that list whenever retained evidence changes.
Wildcard exceptions disable excluded-directory pruning in the current
[BuildKit filesystem filter](https://github.com/tonistiigi/fsutil/blob/a2aa163d723f/filter.go#L123-L127),
which can make unreadable local artifacts break context transfer. Literal paths
keep ignored build and data directories outside that traversal.

| Family | Retention | Reason |
|---|---|---|
| `validation/` | Versioned | Structured gate records read by `Product.StatusLoader` and named by `Product.ValidationRecord` |
| Per-substrate product lane journals and `product-aggregate.json` | Versioned | Inputs to the evidence-derived product status projection |
| Admitted journals' sibling `journal.json.qualifications/*.cbor` objects, including canonical lane journal siblings | Versioned | Exact portable qualification objects read and SHA-checked by `Product.QualificationObjects` during journal admission |
| `product-lane-registrations/` when a generation is admitted | Versioned | Registration, generation and journal identities consumed by `Product.LaneRegistrationData` and the admission reader |
| `criterion-reviews/` (all sources, current and historical) | Required runtime input; must move to a short root | Repo-relative paths of 179-249 characters exceed the Windows checkout limit ([plan standards P](../development_plan_standards.md#p-windows-portable-version-controlled-paths)); the selection and receipt data embeds each path, so the layout changes together with its identities. Product rows read the tree for the current source stamp at runtime and the image build context must include it, so it cannot simply be dropped: land the short-root layout with the next reviewed source, then untrack the old tree |
| Curated review rationale, mathematical inputs, reproducibility sources and summaries | Versioned | Explain and reproduce the accepted criteria and their limits |
| Raw receipts, stdout/stderr, compiler/package probes, generated diagnostic JSON, logs, checkpoints, archives and caches | Local only | Execution artifacts; new outputs belong under ignored `.build/` |
| Copied source snapshots, superseded criterion source trees/review archives and generated retention metadata | Local only | Historical duplicates; retain a curated summary when needed for navigation |

The consumers are implemented in
[`StatusLoader.hs`](../../src/JitML/Product/StatusLoader.hs),
[`ValidationRecord.hs`](../../src/JitML/Product/ValidationRecord.hs),
[`LaneRegistrationData.hs`](../../src/JitML/Product/LaneRegistrationData.hs),
[`CriterionReviewData.hs`](../../src/JitML/Product/CriterionReviewData.hs), and
[`QualificationObjects.hs`](../../src/JitML/Product/QualificationObjects.hs).
Structured validation records retain the fields required by their evidence
contract, including failure details; they are deliberate admission records, not
a copy of every diagnostic run. Complete stdout/stderr embedded in a failed
`jitml-validation-record` remain versioned with that record and their verified
digests. The local-only rule applies to loose raw logs and compiled payloads;
it does not authorize deleting required failure streams or the failed record.

The `criterion-reviews/` trees stay local: both ignore files exclude them, and
existing local copies are unaffected by that exclusion. A future admitted
registration that needs a criterion source in a clean checkout first requires a
short-root layout (at most 160 repo-relative characters) with its selection and
receipt data and pinned identities regenerated together; only then is that
source's complete selection/receipt/artifact closure admitted in both ignore
files. Never remove files needed to read an intentionally retained admitted
generation.

Older ignored payloads can remain at their original local paths. Historical
Markdown links or manifests may inventory those bytes; they do not promise that
a clean checkout contains the payloads. A summary cannot substitute for the
committed evidence required to close a phase.

Promote evidence deliberately after checking its source identity, scope and
completeness, and add any needed exception to both ignore files. Do not copy an
entire run directory into this tree. Keep both
`.gitignore` and `.dockerignore` aligned; registered generated source outside
this directory remains governed by its existing registry.
