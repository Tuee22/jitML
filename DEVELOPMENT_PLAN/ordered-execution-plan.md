# Ordered Execution Plan

**Status**: Authoritative source
**Supersedes**: The higher-numbered-prerequisite execution graph; historical phase identities and evidence remain retained.
**Referenced by**: [README](README.md), [plan standards](development_plan_standards.md), [transfer register](ordered-plan-transfers.md)
**Generated sections**: none

> **Purpose**: Define the one current numerically executable plan and its phase-local validation boundaries.

## Current scope

Phases **290–335** are the current execution sequence. Phases **1–289** are
historical planning/evidence records with explicit ownership transfers. They are
not earlier open gates blocked on 290: supersession changes current ownership,
not software completion. No sprint became Done through this documentation edit.
The first current owner is **290.1**; all subsequent sprints are Blocked by their
immediate numerical predecessor. Implement, validate and close each phase before
starting the next. Missing required hardware stops execution at that phase.

## Validation contract

1. Dependencies name only lower phase numbers or earlier sprints in the same phase. No cycles, self-edges, future implementation, future records or future full-suite results may block an earlier phase's retained validation.
2. Every original assertion is inventoried as engineering, selected-hardware or real-input acceptance. Engineering closes on independently issued hermetic fixtures and its own actual runtime probes. Later full-lane and aggregate assertions stay mandatory under their named owners; they do not retroactively gate engineering.
3. Later phases extend completed contracts and execute predeclared acceptance. They cannot undo an earlier promise or quietly change its schemas, CLI, evidence, criteria or semantics. A discovered defect reopens the earliest affected owner and explicitly invalidates dependent results before work resumes.
4. Phases 290–319 implement all producers, consumer/issuer/browser/report/aggregate/closure/status machinery and fixture controls. Phase 320 freezes one common source/criterion/recipe/policy epoch with predeclared per-lane build/toolchain requirements and immutable lane executable seals. Phases 321–335 produce and admit evidence without executable-source/schema/recipe edits. A needed fix returns to its engineering owner and creates a new epoch; it cannot preserve stale lane qualifications.
5. Each phase requires linux-cpu and at most one additional specific OS/device profile. CPU aggregation reads retained hardware records without launching either accelerator. Hardware-specific phases include their own CPU support, never the other device's tests.
6. Linux CPU validation may run on native Linux, the admitted Linux container/VM, or a dedicated right-sized WSL2 distribution with Docker, Kind and needed Linux dependencies, the host repository bind-mounted, and no NVIDIA execution. WSL2 is an execution venue for linux-cpu, not a CUDA or Windows-native numerical lane. Phase 292 separately verifies Windows-host filesystem exposure; it is the first specific-host wall.
7. Sprint packages target 2–4 engineer-days, separately budgeting compute. Scientific qualification uses fixed groups of at most four whole row cohorts in canonical order. Split excessive scope prospectively, never science or its assertions. Qualification preserves all 55 rows and all prescribed seeds.
8. Phase 290 implements scoped gate projection and source-catalogue migration before any successor uses it. Current source checks still reflect the old catalogue. Documentation structural validation can establish this plan's consistency; it cannot claim software, full docs/check-code, WSL2, Windows, CUDA, Metal or qualification passes.

## Numerical sequence

| Phase | Work | Hardware | Sprints | Change boundary |
|---|---|---|---|---|
| [290](phase-290-ordered-plan-and-validation-foundation.md) | Ordered plan and validation foundation | linux-cpu | 290.1–290.3 | Engineering |
| [291](phase-291-governed-authority.md) | Governed authority | linux-cpu | 291.1–291.3 | Engineering |
| [292](phase-292-generated-output-portability.md) | Generated output portability | windows+linux-cpu | 292.1–292.3 | Engineering |
| [293](phase-293-owned-process-families.md) | Owned process families | linux-cpu | 293.1–293.2 | Engineering |
| [294](phase-294-terminal-outcomes.md) | Terminal outcomes | linux-cpu | 294.1–294.2 | Engineering |
| [295](phase-295-host-resource-admission.md) | Host resource admission | linux-cpu | 295.1–295.3 | Engineering |
| [296](phase-296-lifecycle-preservation.md) | Lifecycle preservation | linux-cpu | 296.1–296.2 | Engineering |
| [297](phase-297-node-pod-fit.md) | Node pod fit | linux-cpu | 297.1–297.2 | Engineering |
| [298](phase-298-portable-workload-placement.md) | Portable workload placement | linux-cpu | 298.1–298.2 | Engineering |
| [299](phase-299-durable-diagnostic-supervisor.md) | Durable diagnostic supervisor | linux-cpu | 299.1–299.3 | Engineering |
| [300](phase-300-behavioral-realness.md) | Behavioral realness | linux-cpu | 300.1–300.2 | Engineering |
| [301](phase-301-prospective-criteria.md) | Prospective criteria | linux-cpu | 301.1–301.3 | Engineering |
| [302](phase-302-tuning-readiness.md) | Tuning readiness | linux-cpu | 302.1–302.2 | Engineering |
| [303](phase-303-supervised-readiness.md) | Supervised readiness | linux-cpu | 303.1–303.2 | Engineering |
| [304](phase-304-rl-readiness.md) | RL readiness | linux-cpu | 304.1–304.3 | Engineering |
| [305](phase-305-arena-readiness.md) | Arena readiness | linux-cpu | 305.1–305.2 | Engineering |
| [306](phase-306-campaign-protocol.md) | Campaign protocol | linux-cpu | 306.1–306.4 | Engineering |
| [307](phase-307-campaign-report-machinery.md) | Campaign report machinery | linux-cpu | 307.1–307.2 | Engineering |
| [308](phase-308-browser-consumer-machinery.md) | Browser consumer machinery | linux-cpu | 308.1–308.2 | Engineering |
| [309](phase-309-fragment-issuer-machinery.md) | Fragment issuer machinery | linux-cpu | 309.1–309.2 | Engineering |
| [310](phase-310-campaign-negative-controls.md) | Campaign negative controls | linux-cpu | 310.1–310.2 | Engineering |
| [311](phase-311-journal-reducer-controls.md) | Journal reducer controls | linux-cpu | 311.1–311.2 | Engineering |
| [312](phase-312-lifecycle-registration-controls.md) | Lifecycle registration controls | linux-cpu | 312.1–312.2 | Engineering |
| [313](phase-313-aggregate-reader-machinery.md) | Aggregate reader machinery | linux-cpu | 313.1–313.2 | Engineering |
| [314](phase-314-provenance-audit-machinery.md) | Provenance audit machinery | linux-cpu | 314.1–314.2 | Engineering |
| [315](phase-315-evidence-projection-machinery.md) | Evidence projection machinery | linux-cpu | 315.1–315.3 | Engineering |
| [316](phase-316-closure-machinery.md) | Closure machinery | linux-cpu | 316.1–316.2 | Engineering |
| [317](phase-317-status-audit-report-machinery.md) | Status audit report machinery | linux-cpu | 317.1–317.3 | Engineering |
| [318](phase-318-cuda-runtime-engineering.md) | CUDA runtime engineering | nvidia+linux-cpu | 318.1–318.3 | Engineering |
| [319](phase-319-apple-runtime-engineering.md) | Apple runtime engineering | macos+linux-cpu | 319.1–319.3 | Engineering |
| [320](phase-320-qualification-epoch-freeze.md) | Qualification epoch freeze | linux-cpu | 320.1–320.2 | Shared freeze |
| [321](phase-321-cpu-qualification.md) | CPU qualification | linux-cpu | 321.1–321.15 | Frozen evidence |
| [322](phase-322-cpu-browser-and-fragment.md) | CPU browser and fragment | linux-cpu | 322.1–322.2 | Frozen evidence |
| [323](phase-323-cuda-qualification.md) | CUDA qualification | nvidia+linux-cpu | 323.1–323.15 | Frozen evidence |
| [324](phase-324-apple-qualification.md) | Apple qualification | macos+linux-cpu | 324.1–324.15 | Frozen evidence |
| [325](phase-325-real-lane-join.md) | Real lane join | linux-cpu | 325.1–325.1 | Frozen evidence |
| [326](phase-326-real-provenance-audit.md) | Real provenance audit | linux-cpu | 326.1–326.2 | Frozen evidence |
| [327](phase-327-real-product-aggregation.md) | Real product aggregation | linux-cpu | 327.1–327.1 | Frozen evidence |
| [328](phase-328-complete-standing-engineering.md) | Complete standing engineering | linux-cpu | 328.1–328.3 | Frozen evidence |
| [329](phase-329-real-convergence-projections.md) | Real convergence projections | linux-cpu | 329.1–329.1 | Frozen evidence |
| [330](phase-330-real-performance-determinism.md) | Real performance determinism | linux-cpu | 330.1–330.1 | Frozen evidence |
| [331](phase-331-complete-per-model-evidence.md) | Complete per model evidence | linux-cpu | 331.1–331.1 | Frozen evidence |
| [332](phase-332-real-closure-admission.md) | Pre-handoff closure admission | linux-cpu | 332.1–332.1 | Frozen evidence |
| [333](phase-333-standing-final-audit.md) | Standing final audit | linux-cpu | 333.1–333.1 | Frozen evidence |
| [334](phase-334-final-derived-status.md) | Final derived status | linux-cpu | 334.1–334.1 | Frozen evidence |
| [335](phase-335-final-report-handoff.md) | Final report handoff | linux-cpu | 335.1–335.1 | Frozen evidence |

## Completion and compatibility

Each phase inherits the full retained contracts identified by the
[transfer register](ordered-plan-transfers.md), including detailed historical
Remaining Work, scientific failures, cleanup and preservation duties. Historical
Done remains valid only for its original evidence scope. Old .1/.2/.3 wrappers
are not substitutes for their detailed contracts. The deletion ledger owns
retirement of superseded authority/callers after replacement validation; no raw
receipt, recovery disk, dataset or retained model is deleted by this refactor.

The scoped first-phase foundation must reject higher-numbered prerequisites,
missing/duplicate owners, missing scope transfers and a gate that acquires a
future fixture/journal. It must accept a valid lower-only plan with future
sprints still unimplemented, while deriving those future sprints as Blocked.
No blanket allowlist or fake evidence may turn the existing stale catalogue
into a pass.

## Hardware and final-decision partitions

292 closes CPU/Windows-exposed portability and the mechanical criterion layout;
318/319 separately close actual NVIDIA/Metal/native producer and OS controls.
The common core freeze 320 is separate from authenticated per-lane binary seals
made before each lane's first seed. CPU bootstrap 290.1 validates its own minimal
gate before 290.2/.3 extend it. Pre-handoff admission 332 correctly leaves later
audit/status/handoff Pending;335 owns the final non-circular complete decision.
