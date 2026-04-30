# TODO-20260428_osprey_sharp_stage6.md — Phase 4 Stage 6: complete the pipeline

> Continuation of `TODO-20260423_osprey_sharp_stage6.md` (which closed
> Multi-charge consensus + Cross-run reconciliation byte parity with
> Rust). This file tracks the remaining Stage 6 work plus carry-over
> items, then declares Stage 6 done and moves the workflow arrow to
> Stage 7.

## Branch Information

- **pwiz branch**: `Skyline/work/20260428_osprey_sharp_stage6` (created 2026-04-28 off master at `40c73cf1f`, pushed to origin, zero commits of its own yet). Worktree: `C:\proj\pwiz` (the `pwiz-work1` worktree from the prior sprint is now idle).
- **osprey branch**: TBD (create off main when this sprint's Rust-side changes start; the post-PR-22 main head is the base)
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-04-28
- **Status**: **Completed** — squash-merged 2026-04-29 as pwiz `1c78d32ba` (PR #4173) + osprey `b0435b0`/`c0c8059` (PR #23) + osprey `36efcb8`/`2277f5b` (PR #24)
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

## Scope

**Goal**: close the third Stage 6 box (`Second-pass re-score + Percolator SVM`)
in `pwiz_tools/OspreySharp/Osprey-workflow.html`, flip it to `st-done`,
and move the "YOU ARE HERE" arrow from there to the first Stage 7 box.
At session start the workflow HTML has Multi-charge consensus +
Cross-run reconciliation green; Second-pass re-score + Percolator SVM
gray (`st-missing`).

After this sprint, all three Stage 6 boxes are green and Stage 6 is
declared complete. The umbrella plan in `TODO-20260423_osprey_sharp.md`
moves to Step 4 (Stage 7 protein FDR parity).

## Tasks

### Priority 1 — Second-pass re-score + Percolator SVM

The Rust pipeline already does this; OspreySharp has stubs only. Mirror
the Rust flow in `osprey/crates/osprey/src/pipeline.rs` Stage 6
re-scoring block (~lines 3400-3700).

1. **Wire `ReconciliationPlanner.Plan`** into `AnalysisPipeline.Run`
   right after `CalibrationRefit.Refit` produces the refined
   per-file calibrations. **DONE in Session 2** (`pwiz 95b044f66`).
   Loads CWT candidates from each `.scores.parquet` via the new
   `LoadCwtCandidatesFromParquet`. Cross-impl byte parity proven by
   the new `OSPREY_DUMP_RECONCILIATION` dump (Stellar 172,548 rows
   match between C# and Rust). The Cross-run reconciliation box
   description in the workflow HTML says "ReconciliationPlanner
   deferred to second-pass re-score sprint" — update that note when
   the workflow HTML close-out (Priority 7) lands.
2. **Per-file re-scoring loop**. For each file, build a
   `ScoringContext.BoundaryOverrides` map from the planner output
   (entry_id -> (apex, start, end)) and re-invoke the search-engine
   path that consumes overrides (the dormant branch added in
   `16bc080f8`). Use Rust's `run_search` with `boundary_overrides`
   parameter as the reference; the C# equivalent is
   `AnalysisPipeline.ScoreCandidate` with `BoundaryOverrides` set.
3. **Gap-fill two-pass**. After re-scoring, identify
   `IdentifyGapFillTargets` precursors (peptides passing in some
   files but absent in others) and re-run the search-engine with
   gap-fill boundary overrides — first with CWT detection enabled
   (pre-filter off), then forced integration for whatever CWT misses.
4. **Single second-pass Percolator**. Train one Percolator SVM on
   the re-scored + gap-filled pool. Compute final run + experiment
   q-values at precursor + peptide levels. Write second-pass FDR
   sidecars on the Rust side; OspreySharp doesn't need to (no
   skip-Percolator path in C# yet).
5. **Parquet write-back**. Reconciled scores + RT boundaries get
   written back into the per-file `.scores.parquet` so the blib
   output stage reads the second-pass values.

### Priority 2 — Cross-impl dumps for the second-pass

Per the umbrella plan, mirror the Stage 5 dump idiom:

- `OSPREY_DUMP_RECONCILIATION` / `_ONLY` — per-(file, entry)
  `ReconcileAction` dump (action variant + apex/start/end/half_width
  fields). **DONE in Session 2** (`osprey 36efcb8` + `pwiz 95b044f66`).
  Stellar full-harness PASS at 172,548 rows.
- `OSPREY_DUMP_REFINED_FDR` / `_ONLY` — end-of-Stage-6 Percolator
  dump with the same six-column schema as the Stage 5 percolator
  dump. Lets `Compare-Stage6-Planning.ps1` (or a Stage-6-end variant)
  validate full-Stage-6 parity. **STILL PENDING** — needs the
  second-pass FDR (Priority 1.4) to land first.

Both numeric formats use `Diagnostics.FormatF64Roundtrip` (C#) /
`format_f64_roundtrip` (Rust).

### Priority 3 — Cross-impl harness

Either extend `Compare-Stage6-Planning.ps1` to include the two new
dumps, or add a sibling `Compare-Stage6-Final.ps1` that runs
end-to-Stage-6 (no `_ONLY`). Pass criterion: 3/3 files byte-identical
on Stellar + Astral for both new dumps. Stage 5 single-file gate
(`Compare-Stage5-AllFiles.ps1`) and the existing Stage 6 planning
harness (8 dumps) must remain green throughout.

### Priority 4 — Address pwiz Copilot review items from #4169

Three items flagged by Copilot but deferred to this sprint (the
prior PR was a check-point):

- **`pwiz_tools/OspreySharp/Osprey-workflow.html` line 69-74**: the
  Stage 6 introductory paragraph still says "Consensus RTs are now
  99.999% bit-identical (1 of 87,343 rows differs ...)" and "the
  refit's LOESS residual stats still diverge at ULP". Both stale
  after #4169 merged. Rewrite the paragraph to describe the
  post-merge state (all Stage 6 planning dumps byte-identical;
  Second-pass re-score is the remaining substage until this sprint
  closes it).
- **`pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs:494, :502`**:
  inline `0x7FFFFFFFu` mask used twice in the first-pass compaction
  block. Extract as a named constant (e.g. `BASE_ID_MASK`) matching
  the convention in `pwiz_tools/OspreySharp/OspreySharp.FDR/PercolatorFdr.cs`.
- **`pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs:277-280`**:
  comment in the `--join-only` calibration load says "The parquet
  stem is `<fileName>.scores`; strip the trailing `.scores` ..." but
  `fileName` was already stripped earlier in the loop. Rewrite the
  comment to describe the actual flow.

### Priority 5 — Address Copilot's --join-only re-scoring concern

`Compare-Stage6-Planning.ps1` currently relies on `--join-only` with
`--input-scores` to drive Stage 6 dumps. After #21 merged, both
`reconciliation_enabled` gates broadened to fire on `per_file_entries`,
but the downstream re-scoring loop in Rust (and the about-to-be-ported
C# equivalent) still maps `file_name -> input_file` via
`config.input_files`, which is empty in `--join-only` mode. The full
Stage 6 re-scoring this sprint is implementing therefore won't
actually run on `--join-only` invocations until a synthetic
`file_name -> synthetic_input_from_parquet(...)` mapping is built.

Two options:

(a) Build the synthetic mapping (Copilot's preferred suggestion) so
    `--join-only` multi-file can run full Stage 6 end-to-end. Adds
    code on both Rust and C# sides.
(b) Keep `--join-only` capped at the planning checkpoint dumps
    (where it already works) and require `--input-files` for full
    Stage 6 re-scoring. Document this constraint in
    `osprey-development-guide.md` and in the harness scripts.

Recommended start: option (b) is faster and matches how the harness
currently operates; option (a) is the "right" fix but is bigger
scope and only matters if production users invoke `--join-only`
end-to-end (which Skyline integration does not yet do).

### Session 2 (2026-04-28..29) — P1.1 + Priority 2 done

**P1.1 (ReconciliationPlanner.Plan wired) + Priority 2 (cross-impl
reconciliation dump) shipped end-to-end with byte parity proven on
Stellar.**

Five commits across three repos:

1. `osprey b0435b0` — `library_identity_hash`: drop directory portion,
   keep file name only. The full path was brittle (HPC node paths, drive
   letter case, slash direction); file_name + size + mtime is the
   right identity for cross-impl handoff. Mirrors the
   `reconciliation_parameter_hash` precedent.
2. `pwiz 298a17b93` — `LibraryIdentityHash`: paired drop-directory
   change so C# and Rust produce bit-identical hashes for the same
   library file. Side benefit: existing parquets can now flow either
   direction through `--no-join` / `--join-only`.
3. `osprey 36efcb8` — `dump_stage6_reconciliation` +
   `OSPREY_DUMP_RECONCILIATION` / `_ONLY` env-var pair, wired into
   `pipeline.rs` after `plan_reconciliation`. Emits non-Keep actions
   sorted by (file_name, entry_id).
4. `pwiz 95b044f66` — Stage 6 reconciliation planning + cross-impl dump.
   `AnalysisPipeline` calls `ReconciliationPlanner.Plan` after
   `CalibrationRefit.Refit`, loading per-file CWT candidates from each
   `.scores.parquet` via the new `LoadCwtCandidatesFromParquet`. New
   `OspreyDiagnostics.WriteStage6ReconciliationDump` mirrors the Rust
   format. Per-file rescore + gap-fill + second-pass FDR still pending.
5. `pwiz-ai TBD` (this commit) — `Compare-Stage6-Planning.ps1` adds the
   reconciliation pair to `$dumpSpecs`. Stellar full re-stage (9 dumps)
   PASS, with reconciliation dump byte-identical at 172,548 rows.

**Foundations landed earlier in this session** (committed before the
five above):

- `pwiz 56c9dcede` — `CwtCandidate` codec + `Parquet` round-trip
  (encoder + decoder + round-trip + Rust-parquet decode tests).
- `pwiz 191e56af7` — `ScoreCandidate` captures top-N CWT candidates;
  populates `FdrEntry.CwtCandidates` (with documented 1e-6 tolerance
  on cross-impl `area` field via Stage 1-4 divergence note below).

### Open question — Stage 1-4 ULP-level divergence surfaced by CWT capture

While wiring the CWT capture (Priority 1.1 foundations), the new
cross-impl parity test `TestCwtCandidateCrossImplParity` surfaced two
pre-existing Stage 1-4 divergences that the existing harness masks
because it loads Rust-written `.scores.parquet` for both impls via
`--input-scores`:

- **Row count gap, ~0.5%.** Stellar file 20 produces 462,802 FdrEntry
  stubs from the C# pipeline vs 464,953 from Rust (2,151-row delta).
  The two pipelines accept slightly different sets of entries through
  the CWT detection / apex-tolerance gates. `Test-Features.ps1` only
  compares matched entries (317,842 targets) so this gap stayed
  invisible.
- **Value drift, ~2% of both-CWT entries.** Per-CWT-candidate fields
  (notably `area`) show ULP-level diffs (e.g. entry 4094 candidate 2,
  area 0x4094a86882c14be0 vs ...be3, a 3-ULP gap). This is the same
  drift `Test-Features.ps1` already accepts at 1e-6: `peak_area` max
  diff is 4.4e-9 today, well inside the gate but not bit-identical.

Workflow HTML calls Stage 1-4 "bit-identical" but the actual gate is
`Test-Features.ps1` at 1e-6 absolute tolerance. The two are not the
same. Open question: chase `peak_area` to bit-identity (root-cause
the accumulation order or ref-XIC selection drift), or update the
workflow prose to say "within 1e-6" and accept the drift. Deferred
to a future sprint -- Stage 6 reconciliation parity in the harness
is unaffected because both impls read the same Rust-written parquet.

### Priority 6 — Address Astral 3-file experiment_precursor_q 1-ULP gap

168 rows in the Astral 3-file `stage5_percolator` dump (file 49,
losing entries with q ~ 0.0977) show a 1-ULP gap in
`experiment_precursor_q` cross-impl. All affected rows fail FDR
anyway (q ~ 0.0977 >> 0.01) so downstream Stage 6 dumps are
unaffected — every Stage 6 dump PASSed on Astral 3-file in
`TODO-20260423_osprey_sharp_stage6.md` Session 6.

The divergence is in the experiment-level q-value computation across
3 files, not in any data path Stage 6 work touched. Bisect the
divergence and either (a) fix the C# computation to match Rust
bit-for-bit, or (b) document as accepted with a tolerance in the
harness if the cause is acceptable f64 accumulation order.

### Priority 7 — Close out Stage 6

Once Priorities 1-3 are byte-identical on both datasets:

- `pwiz_tools/OspreySharp/Osprey-workflow.html`: flip
  `Second-pass re-score + Percolator SVM` from `st-missing` to
  `st-done`. Update the Stage 6 description block. Move the
  "YOU ARE HERE" arrow from the third Stage 6 box up to the first
  Stage 7 box (Parsimony / picked-protein / q-value assignment).
- Update the umbrella `TODO-20260423_osprey_sharp.md` "Phase History"
  to record Stage 6 complete.
- Move this TODO to `ai/todos/completed/` once the post-merge
  Copilot review is addressed and PRs are merged.

## Files expected to change

**New:**

- `OspreySharp.FDR/Reconciliation/GapFillTarget.cs` (port of
  `identify_gap_fill_targets`)
- `OspreySharp.FDR/Reconciliation/SecondPassPercolator.cs` or wire
  the existing `PercolatorFdr` for the second-pass scoring pool
- `ai/scripts/OspreySharp/Compare-Stage6-Final.ps1` (or extend
  `Compare-Stage6-Planning.ps1` with the two new dumps)

**Modified:**

- `OspreySharp/AnalysisPipeline.cs` — Stage 6 re-scoring block
  (replaces the planning-checkpoint stub at the end of Stage 6),
  plus the BASE_ID_MASK extraction and the `--join-only` calibration
  comment cleanup
- `OspreySharp/OspreyDiagnostics.cs` — two new dump methods
- `OspreySharp/Osprey-workflow.html` — close-out edits
- `OspreySharp.Scoring/...` — gap-fill driver in the search engine
  (reuses `BoundaryOverrides`)
- `crates/osprey/src/diagnostics.rs` — two new Rust dump functions
- `crates/osprey/src/pipeline.rs` — dump call wiring at the
  post-second-pass-FDR point
- `pwiz_tools/OspreySharp/OspreySharp/Osprey-workflow.html` — the
  Stage 6 description paragraph rewrite (Copilot item)

## See also

- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4 umbrella
  plan; Step 3 closes when this sprint completes, Step 4 (Stage 7)
  becomes active.
- `ai/todos/completed/TODO-20260423_osprey_sharp_stage6.md` — prior
  sprint that closed Cross-run reconciliation (planning checkpoint
  byte parity).
- `ai/docs/osprey-development-guide.md` — bisection methodology,
  env-var reference, OspreySharp project layering rule.
- `C:\proj\osprey\CLAUDE.md` — Rust-side critical invariants
  (especially "Protein FDR Scoring (Two-Pass Picked-Protein,
  Savitski 2015)" since Stage 6 second-pass FDR feeds the
  Stage 8 protein FDR pass).

## Progress log

### Session 0 (2026-04-28) — Sprint scaffolding

- Branch `Skyline/work/20260428_osprey_sharp_stage6` created in
  `C:\proj\pwiz` off master at `40c73cf1f` (the merge commit for
  pwiz #4169) and pushed to origin.
- Prior sprint TODO moved to `ai/todos/completed/`. Worktree
  `C:\proj\pwiz-work1` is now idle (its branch is merged).
- This sprint's TODO created with 7-priority plan and full file
  inventory. No code committed yet.

### Session 1 (2026-04-28) — Priority 4 + Priority 6 closed

**Priority 4 (Copilot follow-ups from #4169)** — committed at
`3bf5acd1f` on `Skyline/work/20260428_osprey_sharp_stage6`:

- `Osprey-workflow.html` Stage 6 paragraph rewritten to describe the
  post-merge state (8 of 8 planning dumps byte-identical on Stellar,
  7 of 8 on Astral with one documented 1-ULP gap, second-pass
  re-score noted as the remaining substage).
- `AnalysisPipeline.cs` extracted `private const uint BASE_ID_MASK
  = 0x7FFFFFFFu` near `NUM_PIN_FEATURES`; lines 494/502 now use it.
  (Used `const` not the PercolatorFdr.cs `static readonly` form
  since it's a literal — deliberate cleanup, per developer call.)
- `AnalysisPipeline.cs:277-280` --join-only calibration comment
  rewritten — fileName already had `.scores` stripped above; the
  old comment described an obsolete flow.

**Validation of prior sprint claims** — osprey switched from
`feature/stage6-copilot-followups` to `main` @ `a175311` (PR #22
still open and untouched). Re-ran `Compare-Stage6-Planning.ps1`
on both datasets:

- Stellar: 8 of 8 PASS (29:11). All dump pairs byte-identical.
- Astral: 7 of 8 PASS (45:55). Only `stage5_percolator` failed,
  with exactly the documented Priority 6 shape: 168 rows in file 49
  + 55 + 60 (fairly evenly distributed across all three files,
  not file-49-specific as the prior TODO suggested), 1-ULP gap in
  `experiment_precursor_q` at q approximately 0.0977.

**Priority 6 closed (formatter ambiguity, not a real divergence)**
— committed at `7dd43c2` on `pwiz-ai`:

Bisection added a temporary `OSPREY_DEBUG_EXP_PREC=1`-gated dump on
both Rust and C# sides at three layers — post-CompeteAll winners,
post-`compute_conservative_qvalues` q-array, and per-FdrEntry
`experiment_precursor_qvalue` after assignment. All three layers
proved byte-identical between Rust and C# across all 1.4M+ winners
and 5M+ entries. Re-parsing the 168 differing stage5_percolator
cells back to f64 and bit-comparing showed zero real bit
divergences — every "1-ULP gap" was the same f64 (e.g.,
`0x3fb9064000000000` = 0.097751617431640625 exactly) for which
Rust ryu emits `0.09775161743164063` and .NET 8 `R` emits
`0.09775161743164062`, both valid shortest-roundtrip forms.

Attempted to canonicalize the C# output by trim-to-shortest +
bump-up-on-tie. The trim worked, but the bump-up regressed
previously-passing dumps because Rust ryu's tie-break is
algorithm-driven (sometimes higher, sometimes lower) — no simple
post-process matches it everywhere. Reverted that attempt.

Final fix: `Compare-Stage6-Planning.ps1` now falls back from the
SHA-256 byte-equality check to a `Compare-DumpsNumerically` walk
when bytes differ. For each cell that differs textually, both
sides are parsed to f64 and bit-compared. PASS if every
difference is text-only (formatter tie-break); FAIL on any real
bit divergence. Re-ran Astral after the harness change: 8 of 8
PASS, with `stage5_percolator` now reporting "168 cell(s) differ
in text only (bit-equal; ryu/R tie-break)".

Temporary instrumentation reverted on both sides; only the harness
change is in pwiz-ai. Production Rust and C# are unchanged from
the P4 baseline.

**Status update on the priority list**:

- Priority 4: done (committed).
- Priority 6: closed (Astral 8 of 8 via harness, not by source-side
  fix). Documented in this progress entry; no source change needed.
- Priority 1, 2, 3, 5, 7: unchanged from the original plan; ready
  to start Priority 1 next.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260428_osprey_sharp_stage6.md` before starting work.
