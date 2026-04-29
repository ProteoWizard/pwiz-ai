# TODO-20260429_osprey_sharp_stage6.md — Stage 6 box 3a/3b: per-file re-score + second-pass Percolator

> Continuation of `TODO-20260428_osprey_sharp_stage6.md` (which closed
> the Stage 6 reconciliation planner port + cross-impl dump byte
> parity). This sprint covers the **execution half** of Stage 6
> step 3 — what the workflow HTML now splits into "Second-pass
> re-score" (3a) and "Second-pass Percolator SVM" (3b).

## Branch Information

- **pwiz branch**: `Skyline/work/20260429_osprey_sharp_stage6` (created
  2026-04-29 off master at `1c78d32ba` — the squash-merge for pwiz
  #4173). Worktree: `C:\proj\pwiz`.
- **osprey branch**: TBD (create off `main` when this sprint's
  Rust-side changes start; post-#23/#24-merge main head is the base)
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-04-29
- **Status**: Pending — no commits yet
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

## Scope

**Goal**: implement the per-file re-scoring loop, gap-fill two-pass,
parquet write-back, and second-pass Percolator that close Stage 6
boxes 3a + 3b in `pwiz_tools/OspreySharp/Osprey-workflow.html`.
After this sprint:

- The two gray boxes (3a "Second-pass re-score" + 3b "Second-pass
  Percolator SVM") flip to `st-done`.
- The "YOU ARE HERE" arrow advances from box 3a into Stage 7
  (parsimony / picked-protein / q-value assignment).
- A new `OSPREY_DUMP_REFINED_FDR` cross-impl dump establishes
  byte-parity at the end of Stage 6 (paired with the existing
  `OSPREY_DUMP_RECONCILIATION` planning-checkpoint dump).
- Phase 4 umbrella (`TODO-20260423_osprey_sharp.md`) advances from
  Step 3 (Stage 6) to Step 4 (Stage 7).

## Tasks

### Priority 1 — Box 3a: Per-file re-scoring + gap-fill + parquet write-back

The Rust pipeline does this in `osprey/crates/osprey/src/pipeline.rs`
Stage 6 re-scoring block (~lines 3400-3775). OspreySharp has the
planner output ready (validated byte-identical at 172,548 / 248,711
rows on Stellar / Astral) but no execution path.

1. **Per-file re-scoring loop**. For each file:
   - Build `Dictionary<uint, (apex, start, end)> boundaryOverrides`
     from the planner's `ReconcileAction` map (UseCwtPeak →
     supplied bounds; ForcedIntegration → expected_rt ± half_width).
   - Build a subset `LibraryEntry` list containing only the entries
     that need re-scoring.
   - Re-invoke the search-engine path that consumes overrides
     (`AnalysisPipeline.ScoreCandidate` already has the dormant
     `BoundaryOverrides` consumer at line ~2966; the missing piece
     is a callable entry point that takes a subset library + per-file
     spectra + boundary overrides and returns re-scored entries).
   - The big architectural question: does C# refactor `ProcessFile` to
     expose `RunCoelutionScoring` independently, or build a parallel
     "rescoring path" that doesn't pull in the full first-pass
     pipeline? Estimate: 4-6 hours, with the refactor risk being the
     dominant unknown.

2. **Gap-fill two-pass** (mirrors Rust pipeline.rs:3585-3673).
   - Port `IdentifyGapFillTargets` (~150 LOC, `osprey/crates/osprey/src/reconciliation.rs:860-1023`).
   - Port `GapFillTarget` type to OspreySharp.Core.
   - Build `lib_lookup`: `Dictionary<(string ModSeq, byte Charge), (uint TargetId, uint DecoyId)>`.
   - Build `lib_precursor_mz`: `Dictionary<uint, double>`.
   - Build `per_file_isolation_mz`: `Dictionary<string, List<(double Lo, double Hi)>>`
     extracted from spectra metadata.
   - Pass 1 (CWT): re-invoke search engine with `prefilter_enabled = false`
     and no boundary overrides on a subset library of `target_id +
     decoy_id` from each `GapFillTarget`.
   - Pass 2 (Forced): for entries CWT missed, re-invoke with explicit
     boundary overrides at `expected_rt ± half_width`.
   - Append both passes' results as new `FdrEntry` stubs with
     `parquet_index = uint.MaxValue` (the gap-fill sentinel).

3. **Apply overlay back to FdrEntry**. For each re-scored entry, copy
   the new score / boundaries / features back onto the existing
   `FdrEntry` stub (or append the gap-fill stubs).

4. **Parquet write-back** (mirrors Rust pipeline.rs:3713-3774).
   - Reload the per-file `.scores.parquet`, replace re-scored entries
     by `parquet_index` (NOT Vec position — after first-pass compaction
     the two diverge), and append gap-fill rows.
   - Update each gap-fill stub's `parquet_index` to its new row position
     in the rewritten parquet.
   - Rewrite the parquet with reconciliation metadata (`osprey.reconciled
     = "true"`, `osprey.reconciliation_hash = <reconciliation_parameter_hash>`).

### Priority 2 — Box 3b: Single second-pass Percolator SVM

Smaller piece on top of existing PercolatorFdr infrastructure.

1. **Train one Percolator SVM on the re-scored + gap-filled pool**.
   - Call the existing `PercolatorFdr.RunPercolator` (or
     `RunPercolatorStreaming` for large pools) with the post-rescore
     stubs as input.
   - Use `restrict_base_ids` semantics matching Rust's
     `compute_fdr_from_stubs(per_file_entries, run_fdr,
     Some(&first_pass_base_ids))`.
   - Compute final run + experiment q-values at precursor + peptide
     levels.

2. **`OSPREY_DUMP_REFINED_FDR` cross-impl dump**.
   - Same six-column schema as the Stage 5 percolator dump (score +
     pep + 4 q-values per FdrEntry).
   - Wired into both Rust (`crates/osprey/src/diagnostics.rs` +
     `pipeline.rs`) and C# (`OspreyDiagnostics.cs` + `AnalysisPipeline.cs`).
   - `OSPREY_REFINED_FDR_ONLY` companion env-var for fast bisection.

3. **Extend harness**. Add the new dump pair to
   `Compare-Stage6-Planning.ps1` `$dumpSpecs` (will need a rename to
   `Compare-Stage6.ps1` since it now covers more than planning).

### Priority 3 — Stage 6 close-out

Once Priorities 1-2 are byte-identical on Stellar + Astral:

- `pwiz_tools/OspreySharp/Osprey-workflow.html`: flip both 3a and 3b
  to `st-done`. Move "YOU ARE HERE" arrow into Stage 7 (parsimony /
  picked-protein) box.
- Update the umbrella `TODO-20260423_osprey_sharp.md` Phase History
  to record Stage 6 complete and Step 4 (Stage 7) active.
- Move this TODO to `ai/todos/completed/`.

## Open follow-ups inherited from previous sprint

These were surfaced during the 2026-04-28 sprint and deferred:

1. **maccoss/osprey #25** — `library_identity_hash` should capture
   `(size, mtime)` at library load, not at hash time. Architectural
   refactor with a parallel OspreySharp change. Independent of the
   Stage 6 work in this sprint; can be addressed before, during, or
   after. Touches the load path on both sides.
2. **Stage 1-4 ULP-level divergence**. `Test-Features.ps1` currently
   gates at 1e-6 absolute tolerance. The new `TestCwtCandidateCrossImplParity`
   test surfaced ~0.5% row-count gap (462,802 cs vs 464,953 rust on
   Stellar 20) and ~2% per-CWT-candidate `area` ULP-level drift (max
   4.4e-9, within 1e-6 gate but not bit-identical). The workflow HTML
   prose now correctly says "1e-6 tolerance" not "bit-identical," but
   the underlying drift is open. Worth chasing if Stage 6 box 3a
   re-scoring inherits the drift in a way that affects second-pass
   FDR results.

## Files expected to change

**New in pwiz:**

- `OspreySharp.FDR/Reconciliation/GapFillTarget.cs` — type + helpers
- `OspreySharp.FDR/Reconciliation/IdentifyGapFillTargets.cs` — port
  of Rust `identify_gap_fill_targets`
- `OspreySharp.Scoring/...` — callable scoring entry point with
  subset library + boundary overrides (form depends on the refactor
  decision in Priority 1.1)

**Modified in pwiz:**

- `OspreySharp/AnalysisPipeline.cs` — Stage 6 re-scoring block
  (replaces the "Stage 6 per-file rescore: not yet implemented" log
  line at the end of the planner block)
- `OspreySharp/OspreyDiagnostics.cs` — new `WriteStage6RefinedFdrDump`
- `OspreySharp.IO/ParquetScoreCache.cs` — second-pass write-back logic
  with reconciliation metadata
- `OspreySharp/Osprey-workflow.html` — close-out edits

**New in osprey:**

- `crates/osprey/src/diagnostics.rs` — `dump_stage6_refined_fdr`
- `crates/osprey/src/pipeline.rs` — wire the new dump after second-pass FDR

**Modified in pwiz-ai:**

- `ai/scripts/OspreySharp/Compare-Stage6-Planning.ps1` (rename to
  `Compare-Stage6.ps1`?) — add the refined_fdr dump pair

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4 umbrella;
  Step 3 advances from "in progress" to "near complete" when this
  sprint lands; Step 4 (Stage 7) becomes active.
- `ai/todos/completed/TODO-20260428_osprey_sharp_stage6.md` — prior
  sprint that landed the planner port + planning-checkpoint dump
  byte parity. Open follow-ups in this TODO inherit from that one.
- `ai/docs/osprey-development-guide.md` — bisection methodology,
  env-var reference, OspreySharp project layering rule, glossary
  (CWT, ULP).
- `C:\proj\osprey\CLAUDE.md` — Rust-side critical invariants
  (especially the picked-protein FDR section since Stage 6 second-pass
  FDR feeds the Stage 7 protein FDR pass).

## Progress log

### Session 0 (2026-04-29) — Sprint scaffolding

- Branch `Skyline/work/20260429_osprey_sharp_stage6` created in
  `C:\proj\pwiz` off master at `1c78d32ba` (the squash-merge for
  pwiz #4173) and pushed to origin.
- Prior sprint TODO moved to `ai/todos/completed/`.
- This sprint's TODO created with 3-priority plan and full file
  inventory. No code committed yet.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260429_osprey_sharp_stage6.md` before starting work.
