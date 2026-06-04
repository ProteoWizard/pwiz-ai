# TODO: ~9% C# Astral perf regression introduced in the PR-A/B sprint (stage1to4)

**Status**: Backlog — filed 2026-06-04 during PR-C perf gating.
**Priority**: Medium — ~9% C# total wall regression on Astral; not a correctness issue.
**Type**: Performance regression. NOT in PR-C (byproduct context); located in master HEAD,
i.e. PR-A (#4264) and/or PR-B (#4266).

## Finding

A single-run Astral side-by-side (C#, straight-through, net8.0, this machine, 2026-06-04)
showed master HEAD ~9% slower than the pre-sprint published baseline, while Rust (unchanged)
was flat — so it is a real C# regression, environment-controlled, and reproduced across two
C# runs today.

| stage    | Rust pub | Rust today | C# pub | C# master today | C# PR-C today |
|----------|---------:|-----------:|-------:|----------------:|--------------:|
| stage1to4| 549      | 546.6      | 437    | 504.1           | 510.3         |
| stage5   | 102      | 89.5       | 74     | 67.0            | 66.3          |
| stage6   | 478      | 566.3      | 295    | 343.9           | 328.5         |
| stage7   | 194      | 181.6      | 150    | 136.1           | 137.3         |
| blib     | 113      | 72.6       | 9      | 8.7             | 9.0           |
| **total**| **1466** | **1464.7** | **970**| **1064.8**      | **1057.9**    |

(Published numbers: Osprey-workflow.html Astral table, pre-sprint `svm_stage5_perf` branch,
3-run medians. Today's: `ai/.tmp/measure-pipeline/{rust,master,prc}_astral/`.)

## Attribution

- **Environment is stable**: Rust today total **1464.7s** ≈ published **1466s** (0.1%). The
  machine matches the published-capture state, so absolute comparisons are valid.
- **Not PR-C**: PR-C **1057.9** ≈ master **1064.8** (PR-C marginally faster). The byproduct
  context refactor added no measurable cost.
- **Sprint regression ~+9.8%**: master C# **1064.8** vs published **970**. Normalizing each
  stage by the per-stage Rust drift, the excess concentrates almost entirely in **stage1to4**
  (per-file scoring): ~+69s after environment; stage5/6/7/blib are environment-explained.

So the regression is in **per-file scoring (Stages 1-4)**, introduced by PR-A (#4264,
SearchIdentity + RunPlan) and/or PR-B (#4266, declarative dataflow). PR-B's Run/Rehydrate
split + IsIncluded + the driver loop touch the per-file path's orchestration; PR-A added
SearchIdentity hashing. Either could carry the cost.

## Caveats / how to confirm

- Single run per binary today (the published baseline was a 3-run median). The Rust total
  matching to 0.1% and two C# runs both clustering ~1060 make the ~9% credible, but a
  multi-run confirmation is the proper gate before chasing code.
- Per-stage environment normalization leans on Rust as a per-stage proxy; Rust's own per-stage
  numbers shifted a lot today (stage6 +18%, blib -36%) while the total held, so per-stage
  attribution is softer than the total. Treat "it's in stage1to4" as the leading hypothesis,
  not proven.

## Next steps

1. Multi-run (3x) Astral C# on master HEAD vs the pre-sprint base (parent of #4264) to confirm
   the ~9% and the stage1to4 localization with medians.
2. If confirmed, bisect the sprint: measure #4264 (PR-A) and #4266 (PR-B) to pin which PR
   regressed stage1to4.
3. Profile the per-file scoring path on the regressed commit (dotTrace / the XcorrScratchPool +
   ProcessFile hot path) to find the added cost.

Harness: `pwsh -File ai/scripts/OspreySharp/Measure-Pipeline.ps1 -Dataset Astral -Tool CSharp -Repeats 3`
(build the target commit first; Rust can be reused via the existing target/release binary).

## Related
- `ai/todos/active/TODO-20260604_ospreysharp_byproduct_context_prc.md` (PR-C — where this surfaced)
- `Osprey-workflow.html` perf table (the pre-sprint published baseline)
