# TODO-20260429_osprey_sharp_stage6.md — Stage 6 per-file rescore (post-restructure)

> Continuation of `TODO-20260428_osprey_sharp_stage6.md` (which closed
> the Stage 6 reconciliation planner port + cross-impl dump byte
> parity). This sprint covers what was previously called "Stage 6
> step 3" — the per-file rescore + gap-fill + parquet write-back. The
> 2026-04-30 pipeline restructure (see "Pipeline restructure" section
> below) changed stage boundaries: this sprint's work now lives in
> the new Stage 6 (per-file fan-out only); the old "Stage 6 step 3b"
> (second-pass Percolator) is a separate Stage 7 in a future sprint.

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

### Session 1 (2026-04-30) — Baseline restoration + RescorePerFile sketch + pipeline restructure

**Baseline regression diagnosed and fixed.** A clean Stellar harness
re-run came back 0/9 PASS (down from prior sprint's 9/9). Root cause:
the Copilot review on PR #4173 left a defensive
`cwtRows.Count == kvp.Value.Count` strict-equality gate at
`AnalysisPipeline.cs:678` (commit `f964cc45e`, addressing Copilot's
*first* of two suggestions). That comparison is wrong by design — the
parquet has raw Stage-4 rows (~462k) while post-compaction stubs are
~130k, and `ParquetIndex` was *built* to bridge the gap. The planner
itself indexes correctly via `ParquetIndex` (matches Rust at
`reconciliation.rs:672`), but the gate prevented it from running. Fix
applied: replaced the strict-equality with Copilot's *second*
suggestion (`maxParquetIndex < cwtRows.Count`), which actually
validates the planner's invariant. Stellar 9/9 PASS restored at
172,548 reconciliation rows. Lesson saved to
`ai/docs/osprey-development-guide.md` ("Validation before pushing to
a PR" section): cross-impl harness must be re-run after every commit
to a PR — there is no CI gate on either side.

**RescorePerFile orchestrator landed.** New private method in
`AnalysisPipeline.cs` (~line 1271) called from line 748 (the former
"Stage 6 per-file rescore: not yet implemented" site). Per file:
merges consensus + reconciliation targets (reconciliation wins on
conflict), builds boundary-override map keyed by entry_id, builds
subset library, reloads spectra fresh from disk, picks calibration
(refined → original fallback), reloads MS2/MS1 cal from saved JSON,
calls `RunCoelutionScoring` with override-aware `ScoringContext`,
overlays re-scored entries onto FdrEntry stubs by entry_id while
preserving `ParquetIndex` for future parquet write-back. Mirrors
Rust `pipeline.rs:3439-3789` (consensus + reconciliation path; gap-
fill + parquet write-back deferred).

The orchestrator is a no-op under `--join-only` because
`config.InputFiles.Count == 0` in that mode — Stellar 9/9 still PASS,
confirming no regression but also confirming the new code path isn't
exercised yet. Real validation needs either `--input-files` end-to-
end or the synthetic input mapping from `--join-only` (Rust already
has `synthetic_input_from_parquet` at `pipeline.rs:1200` for the
calibration/sidecar load, but doesn't push it into
`config.input_files` for the rescore loop — so neither side runs
Stage 6 rescore from `--join-only` today).

**Pipeline restructure agreed.** After tracing how Rust manages
memory and join points across 50+ files, restructured stage
boundaries to align with parallelism shape rather than algorithmic
ordering:

| Stage | Work | Shape |
|---|---|---|
| 1-4 | mzML parsing + calibration + scoring + per-file parquet write | Per-file (fan-out) |
| **5** | First-pass Percolator + first-pass protein FDR + compaction + multi-charge consensus + cross-run consensus RTs + per-file calibration refit + reconciliation planning | **Join** |
| **6** | Per-file rescore + gap-fill + reconciled parquet write-back | **Per-file (fan-out)** |
| **7** | Second-pass Percolator | **Join** |
| **8** | Parsimony + picked-protein FDR + .blib + report | **Join** |

What was previously called "Stage 6 planning" (multi-charge
consensus, cross-run consensus, calibration refit, reconciliation
planning) moves into Stage 5 — it's all join-phase work. Old
"Stage 6 step 3b" (second-pass Percolator) becomes Stage 7. Old
"Stage 7" (parsimony / picked-protein) and old "Stage 8" (.blib
output) merge into the new Stage 8 since they share the final
coordinator phase.

**CLI rename.** `--no-join` and `--join-only` keep their names but
become orthogonal to the entry-point selector:

- `--no-join` = run only operations that don't need all-file
  representation (per-file fan-out work).
- `--join-only` = run only operations that need all-file
  representation (join work), no per-file work.
- `--join-at-pass=<1|2>` selects entry-point parquets:
  - `1` = consume Stage 4 parquets (today's `--join-only`).
  - `2` = consume reconciled Stage 6 parquets (NEW; for HPC
    fan-back-in to Stage 7+8 only).

CLI matrix (planned final form):

| Invocation | Runs |
|---|---|
| `-i ...` (no flags) | 1 → 8 |
| `-i ... --no-join` | 1-4 |
| `--join-at-pass=1 --input-scores ...` | 5 → 8 |
| `--join-at-pass=1 --input-scores ... --join-only` | 5 only *(NEW — needs plan-file persistence)* |
| `--join-at-pass=1 --input-scores ... --no-join` | 6 only *(NEW — HPC worker; needs plan-file persistence)* |
| `--join-at-pass=2 --input-scores ...` | 7 → 8 |
| `--join-at-pass=2 --input-scores ... --join-only` | 7 → 8 (redundant; permitted) |

This-sprint scope: ship `--join-at-pass=<1|2>` as the rename of
`--join-only`, generalize `--no-join` semantics, leave plan-file
persistence to a future sprint (the two NEW rows above).

**Workflow HTML restructured.** `pwiz_tools/OspreySharp/Osprey-workflow.html`
SVG diagram redrawn to match the new stage boundaries:
Stage 5 expanded with sub-phase labels for "first-pass percolator"
and "reconciliation planning"; Stage 6 reduced to the per-file
rescore + gap-fill + parquet write-back; Stage 7 now Second-pass
Percolator SVM; Stage 8 absorbs Protein FDR + .blib output. Added
`.phase-shape-fanout` (blue "PER-FILE — N nodes") and
`.phase-shape-join` (red "JOIN — needs all-file representation")
labels on each stage container. "YOU ARE HERE" arrow moved from old
Stage 6 box 3a to new Stage 6 (per-file rescore row). viewBox grew
from 2240 → 2520.

### Sprint plan (post-restructure)

The original 3-priority list still applies with renamed scope:

**Priority 1 — finish Stage 6 (per-file rescore)**
1. ✅ `RescorePerFile` orchestrator (consensus + reconciliation overlay-back-to-stub)
2. ⬜ Wire `synthetic_input_from_parquet` through into `config.input_files` in the `--join-at-pass=1` branch (both Rust + C#) so Stage 6 rescore can run without explicit `--input-files`
3. ⬜ Port `IdentifyGapFillTargets` (`reconciliation.rs:860-1023`) into `OspreySharp.FDR/Reconciliation/`
4. ⬜ Add gap-fill two-pass to `RescorePerFile` (CWT pass with `PrefilterEnabled=false`, then forced pass with overrides)
5. ⬜ Append gap-fill stubs with `parquet_index = uint.MaxValue`; assign real `ParquetIndex` after write-back
6. ⬜ Parquet write-back: replace re-scored rows by `parquet_index`, append gap-fill, write `osprey.reconciled = "true"` + `osprey.reconciliation_hash` metadata
7. ⬜ Validation: parquet diff (cs vs rust reconciled parquets, project + sort + diff), or new `OSPREY_DUMP_REFINED_RESCORE` TSV bridge for fast iteration
8. ⬜ Workflow HTML: flip Stage 6 boxes to st-done; advance "YOU ARE HERE" into Stage 7

**Priority 2 — CLI rename (foundational, can land independently)**
1. ⬜ Add `--join-at-pass=<1|2>` flag on both sides; alias `--join-only` → `--join-at-pass=1` for one release
2. ⬜ Generalize `--no-join` semantics: stop before next join from entry point
3. ⬜ Update `Compare-Stage6-Planning.ps1` and other harness scripts to use new flag names

**Priority 3 — Stage 7 (second-pass Percolator)**
- Single Percolator pass on the reconciled + gap-filled pool
- Add `OSPREY_DUMP_REFINED_FDR` (six-column schema, mirrors Stage 5 percolator dump)
- Validate cross-impl byte-identical
- Workflow HTML: flip Stage 7 to st-done

**Out of scope (deferred to future sprint)**
- Plan-file persistence between Stage 5 and Stage 6 (enables true HPC
  fan-back-out at the join boundary)
- HPC worker plumbing (`--phase=rescore` consuming plan files)
- Stage 8 (protein FDR + .blib output) cross-impl bit-parity

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260429_osprey_sharp_stage6.md` before starting work.
