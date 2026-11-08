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
| Current selected `criterion-reviews/` source and its complete FILE closure | Versioned | Review selections, receipts and their exact selected artifacts read by `Product.CriterionReview`; both ignore files name the deliberately retained source |
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

The current selected criterion source is `75aad7e7…`. Its four CPU/Apple scope
selections require **56** files: **4** selectors, **4** receipts and **48** exact
review artifacts. Each scope is self-contained. The older **280** criterion files
remain local; no retained registration or journal requires those source trees.
The existing canonical journals are legacy records without criterion references.
If a future admitted registration requires another source, retain its complete
selection/receipt/artifact closure explicitly in both ignore files. Never remove
files needed to read an intentionally retained admitted generation.

Older ignored payloads can remain at their original local paths. Historical
Markdown links or manifests may inventory those bytes; they do not promise that
a clean checkout contains the payloads. A summary cannot substitute for the
committed evidence required to close a phase.

Promote evidence deliberately after checking its source identity, scope and
completeness, and add any needed exception to both ignore files. Do not copy an
entire run directory into this tree. Keep both
`.gitignore` and `.dockerignore` aligned; registered generated source outside
this directory remains governed by its existing registry.
