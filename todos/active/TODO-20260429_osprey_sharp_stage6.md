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

### Session 2 (2026-04-30) — PR 1 merged, PR 2 started

**PR 1 (CLI rename) merged.** `--join-at-pass=<1|2>` is now the
canonical entry-point flag on both sides; `--no-join` and
`--join-only` are repurposed as orthogonal phase-shape modifiers.
Sprint branch rebased onto post-merge masters; the CLI rename pieces
folded into base, leaving only the genuine sprint diffs (workflow
HTML restructure + `RescorePerFile` orchestrator + planner-gate fix).

**PR 2 design agreed.** Schema for the Stage 5 → Stage 6 boundary:

| File | Format | Content |
|---|---|---|
| `<stem>.<phase>-pass.fdr_scores.bin` | binary, versioned | SVM score + 4 q-values + PEP per entry |
| `<stem>.reconciliation.json` | JSON, pretty | per-(file, entry) actions + gap-fill targets + refined RT cal |

Naming refined: stayed with the existing `.fdr_scores.bin` family
(extending the format rather than adding a `_qvalues.bin` sibling)
because Storey-Tibshirani q-value estimation is what makes the
calibrated value a true FDR score in the first place — the
uncalibrated SVM discriminant and the calibrated outputs belong
together. Reconciliation envelope drops the `1st-pass.` prefix
since there's only one reconciliation in the pipeline.

**PR 2 work in progress (uncommitted PRs; checkpoint commits only):**

1. ✅ v2 binary format for `.fdr_scores.bin` on Rust side
   (`maccoss/osprey:feature/stage5-boundary-persistence`,
   commit `7eef9e9`). 32-byte header + 48-byte records (SVM score +
   4 q-values + PEP), positional + post-compaction.
2. ✅ v2 binary format on C# side
   (`ProteoWizard/pwiz:Skyline/work/20260430_stage5_boundary`,
   commit `b3b18ef0b`). New `FdrScoresSidecar` class in
   `OspreySharp.IO`.
3. ✅ Cross-impl byte parity for `.fdr_scores.bin` hand-verified:
   same hardcoded test inputs on both sides → SHA-256-identical
   176-byte sidecars (`OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT` test hook).
4. ✅ `<stem>.reconciliation.json` envelope on Rust side
   (`maccoss/osprey:feature/stage5-boundary-persistence`,
   commit `fae0b0e`). New `reconciliation_io` module with
   serde-backed read+write; non-Keep actions split into two
   homogeneous arrays (`use_cwt_peak_actions` +
   `forced_integration_actions`) keyed by entry_id; gap-fill
   targets; refined RT calibration (LOESS model parameters).
   Alphabetical field order at every nesting level.
5. ✅ `<stem>.reconciliation.json` on C# side
   (`ProteoWizard/pwiz:Skyline/work/20260430_stage5_boundary`,
   commit `45a886a86`). New `ReconciliationFile` class in
   `OspreySharp.IO` using Newtonsoft.Json; CRLF normalized to LF
   so cross-impl byte parity holds.
6. ✅ Cross-impl byte parity for `.reconciliation.json`
   hand-verified: identical 1070 bytes
   (`OSPREY_CROSS_IMPL_RECONCILIATION_OUT` test hook).
7. ✅ Wire `--join-at-pass=1 --join-only` to write both sidecars
   and exit (Rust `feature/stage5-boundary-persistence` commit
   `ca9676a`; pwiz `Skyline/work/20260430_stage5_boundary` commit
   `f3dd424ca`). Per-record `entry_id` added to fdr_scores.bin v2
   (record size 48 → 52 bytes) so a Stage 6 worker can join
   parquet stubs against the sidecar set. Pre-compaction format
   matches Rust's existing `persist_fdr_scores` semantics.
8. ✅ Cross-impl harness `Compare-Stage5-Boundary.ps1`. Runs both
   tools, snapshots outputs to `rust_outputs/` + `cs_outputs/`
   subdirs, and SHA-256-compares each pair. Stellar 3-file run
   today: **3/6 PASS** — all 3 fdr_scores.bin pairs byte-identical;
   all 3 reconciliation.json pairs differ ONLY on
   `gap_fill_targets` (with-it-stripped JSON is structurally
   identical). PR 2 lockdown bar = 6/6 PASS.
9. ✅ Ported `IdentifyGapFillTargets` to C# (Session 3, 2026-05-01).
   `OspreySharp.FDR.Reconciliation.GapFillTargetIdentifier` plus
   algorithm POCO `GapFillTarget` (mirroring the Rust
   `reconciliation.rs` / `reconciliation_io.rs` split). Wired
   into `WriteReconciliationFiles` with `lib_lookup` +
   `lib_precursor_mz` built from `fullLibrary` (decoy convention
   `target_id | 0x80000000`). Per-file isolation-window m/z
   filter is plumbed through but not yet populated on the C#
   side (Stellar/Astral don't surface `isolation_scheme` in
   `calibration.json` today, so the filter is a no-op and Rust
   matches; future GPF/HRMS datasets will need
   `IsolationSchemeJson` extended with the `windows` array).
10. ⬜ Wire `--join-at-pass=1 --no-join`: read both sidecars, run
    Stage 6 only, exit (currently also errors as "not yet
    implemented"). PR 3 work, after PR 2 lands.
11. ⬜ Stage 6-rescore harness mode that exercises the boundary on
    real data — single-file + 3-file Stellar. PR 3 work.

### Session 3 (2026-05-01) — PR 2 filed, Stage 5 boundary locked

**6/6 byte parity achieved on both Stellar and Astral.**
`Compare-Stage5-Boundary.ps1` now reports 6/6 sidecar pairs
byte-identical on Stellar (3 files, 03:39 total) and on Astral
(3 files, 08:50 total). The Stage 5 → Stage 6 boundary is locked
down; the future PR-3 worker can be developed against frozen
reference outputs.

**Two distinct issues had to land for 6/6**, only one of which
the Session-2 handoff anticipated:

1. **Anticipated — port `IdentifyGapFillTargets`** (item 9 above).
   First C# run with the port: gap_fill_targets counts matched
   Rust exactly (Stellar 280/264/278) and per-entry JSON values
   were structurally identical. Algorithm correctness validated.
   But the harness was still 3/6 — pointing at the second issue.

2. **Unanticipated — JSON f64 format mismatch.** With
   `gap_fill_targets` no longer the dominant diff,
   `refined_rt_calibration.abs_residuals` exposed a
   Newtonsoft-vs-`ryu` threshold disagreement: Newtonsoft's
   default flips to scientific at `< 1e-4` while Rust `ryu`
   flips at `< 1e-5`, so a value like `4.583863410978495e-5`
   was emitted as `4.583863410978495E-05` (C#) vs
   `0.00004583863410978495` (Rust). The Session-2 handoff had
   flagged this as an Astral risk, but it actually fired on
   Stellar too — the previous "structurally identical" check
   had been a parse-and-re-serialize comparison, not byte-level,
   which hid the format divergence behind the more visible
   `gap_fill_targets` count diff.

   Fix: route every JSON f64 through
   `osprey_core::diagnostics::format_f64_roundtrip` /
   `OspreySharp.Core.Diagnostics.FormatF64Roundtrip` on both
   sides — the same shortest-roundtrip helper that's already
   the canonical formatter for cross-impl TSV diagnostic dumps.
   Always-decimal, no scientific notation, byte-identical across
   runtimes regardless of magnitude. Implemented as:
   - **Rust**: `RoundtripPrettyFormatter` wrapping
     `serde_json::ser::PrettyFormatter`, overriding `write_f64`
     and delegating layout (incl. `end_object_value` for the
     PrettyFormatter `has_value` tracking — easy gotcha;
     missing it makes every object collapse to `<value>}` with
     no indent).
   - **C#**: `RoundtripDoubleConverter : JsonConverter<double>`
     calling `Diagnostics.FormatF64Roundtrip` via
     `WriteRawValue`; wired into `ReconciliationFile.Save`.

   This establishes a new project invariant: **every f64 in
   cross-impl JSON files routes through `format_f64_roundtrip`
   on both sides**. Future Stage-N boundary envelopes inherit
   the property.

**PRs filed and pushed:**

- maccoss/osprey #27 (`feature/stage5-boundary-persistence` →
  `main`): https://github.com/maccoss/osprey/pull/27
  - 4 commits: fdr_scores v2; reconciliation_io module; CLI
    wire-up; RoundtripPrettyFormatter.
- ProteoWizard/pwiz #4181
  (`Skyline/work/20260430_stage5_boundary` → `master`):
  https://github.com/ProteoWizard/pwiz/pull/4181
  - 4 commits: FdrScoresSidecar v2; ReconciliationFile JSON I/O;
    boundary writes + workflow.html restructure;
    GapFillTargetIdentifier + RoundtripDoubleConverter.

PRs cross-link each other in their bodies. Both will squash-merge.

### Sprint plan (post-PR-2)

**Priority 1 — finish Stage 6 (per-file rescore)**, status updates:
1. ✅ `RescorePerFile` orchestrator — landed in Session 1; still
   stashed on the sprint branch (`Skyline/work/20260429_osprey_sharp_stage6`),
   to be replayed onto post-PR-2 master.
2. ⬜ Wire `synthetic_input_from_parquet` through into
   `config.input_files` in the `--join-at-pass=1` branch (both
   Rust + C#) so Stage 6 rescore can run without explicit
   `--input-files`.
3. ✅ `IdentifyGapFillTargets` ported to C# (Session 3 above) —
   ready for Stage 6 to consume from `reconciliation.json` directly.
4. ⬜ Add gap-fill two-pass to `RescorePerFile` (CWT pass with
   `PrefilterEnabled=false`, then forced pass with overrides).
5. ⬜ Append gap-fill stubs with `parquet_index = uint.MaxValue`;
   assign real `ParquetIndex` after write-back.
6. ⬜ Parquet write-back: replace re-scored rows by
   `parquet_index`, append gap-fill, write `osprey.reconciled =
   "true"` + `osprey.reconciliation_hash` metadata.
7. ⬜ Validation: parquet diff (cs vs rust reconciled parquets,
   project + sort + diff), or new `OSPREY_DUMP_REFINED_RESCORE`
   TSV bridge for fast iteration.
8. ⬜ Workflow HTML: flip Stage 6 boxes to st-done; advance
   "YOU ARE HERE" into Stage 7.

**Priority 3 — Stage 7 (second-pass Percolator)**: unchanged.

**New follow-up surfaced this session**: extend C#
`IsolationSchemeJson` to carry the `windows` array (matching
the Rust struct field). Today the C# side has only summary
stats (`num_windows`, `mz_min`, `mz_max`, `typical_width`,
`uniform_width`); the Rust side serializes the full `(center,
width)` pairs into `calibration.json` when the mzML extracts
isolation windows. Stellar/Astral happen to omit
`isolation_scheme` from their calibration.json today (probably
because the calibration code doesn't populate it), so the
gap-fill m/z filter is a no-op for both sides on those
datasets and parity holds. But for GPF datasets where the
filter MUST fire (per the Rust comment at
`reconciliation.rs:917-924`), C# would have to silently emit
extra gap-fill targets that don't satisfy the m/z constraint.
Track this when the first GPF dataset is added to the harness.

**Next session handoff**: PR 3 — `--join-at-pass=1 --no-join`.
Sprint branch (`Skyline/work/20260429_osprey_sharp_stage6`) has
the `RescorePerFile` orchestrator stashed; rebase on post-PR-2
master and `git stash pop`. The Stage 6 worker reads both
sidecars (`*.1st-pass.fdr_scores.bin` + `*.reconciliation.json`),
runs Stage 6 only, exits.

### Session 4 (2026-05-01) — Copilot review feedback addressed

Copilot posted 9 inline review comments on pwiz #4181 (osprey #27
got 0 inline comments). All 9 were valid; an audit of the Rust
side found 5 of them mirrored on Rust too. Both sides got a
follow-up commit:

- **osprey** `feature/stage5-boundary-persistence` `59634e6`
- **pwiz** `Skyline/work/20260430_stage5_boundary` `7aa56c75c`

Coverage:

| Comment | Fix on each side |
|---|---|
| #1 single-file `--join-at-pass=1 --join-only` writes nothing | Validate file count >= 2 + reconciliation enabled — file count goes in CLI parsing (`validate_hpc_args` / `ValidateArgs`), reconciliation-enabled in pipeline-entry (`run_analysis` / start of `Run`). Errors fast instead of silently producing nothing. **No empty-placeholder envelopes** (per user guidance: error rather than write incorrect values that pass through and create confusing results) |
| #2 `RoundtripDoubleConverter.ReadJson` accepts null/non-numeric | C#-only — added `JsonSerializationException` on bad token (Rust serde_json is strict by default) |
| #3, #5 atomic-rename comment overclaim | Both sides — softened doc to acknowledge the delete-then-rename pattern is not strictly atomic on overwrite |
| #4 `pass` byte ignored on read | Both sides — `load_fdr_scores_sidecar` / `TryRead` now take an expected pass and reject mismatches; new `pass_mismatch_rejected` test added on each side |
| #6 stale `NormalizeHpcArgs` doc | C#-only — Rust `normalize_hpc_args` doc was already current |
| #7 silent partial-success on `StopAfterStage5` | Both sides — write loops return failure counts; on `stop_after_stage5` mode any failure escalates to a fatal config error (Rust) / non-zero exit + LogError (C#) instead of a misleading "boundary files written" success log |
| #8 O(files × actions) action filtering | Both sides — pre-group `reconciliation_actions` by file once before the per-file emit loop. Rust adds `from_planner_output_pre_grouped`; C# `BuildReconciliationFile` signature simplified to take pre-grouped slice |
| #9 pre- vs post-compaction class doc | Both sides — same defect on both. Doc now describes the actual pre-compaction semantics and positional load (vs the speculative post-compaction-with-entry_id-join story the Session 2 v2 format leftover) |

**Validation after the review-fix commits:**
- Rust: `Build-OspreyRust.ps1 -Fmt -Clippy -RunTests` clean
- C#: `Build-OspreySharp.ps1 -RunInspection -RunTests` clean (3 new tests added: `TestValidateJoinOnlyModifierRejectsSingleFile`, `TestValidateJoinOnlyModifierRequiresReconciliationEnabled`, `TestValidateJoinOnlyPlainAcceptsSingleFile`, `TestFdrScoresSidecarPassMismatchRejected`)
- Stellar harness: still **6/6 byte-identical** (3:37) — fixes didn't regress the lockdown

PRs ready for re-review.

### Session 5 (2026-05-02) — Stage 6 worker hydration + rescore engine

Picked up after the Stage 5 → Stage 6 boundary PRs merged. Goal:
the `--join-at-pass=1 --no-join` worker that reads the boundary
files + parquet from disk and produces reconciled
`.scores.parquet` files matching what an in-process Stage 6 run
would produce. Working only on `maccoss/osprey` for this sprint;
**`ProteoWizard/pwiz` deliberately untouched** until Rust-side
behavior is validated and ready for Mike's review.

**Branches:**
- `osprey` `feature/stage6-worker` (off `main` at `1a18bc8`)
- `pwiz` `Skyline/work/20260429_osprey_sharp_stage6` set up but
  empty (parked at master HEAD; will pick up the C# port after
  the Rust side passes its tests)

**What landed (osprey):**

`ca97eca` — Per-file rescore worker hydration layer:
- New `crates/osprey/src/rescore.rs` module with
  `RescoreInputs` + `hydrate_for_rescore()` + `hydrate_and_log()`.
  Loads stubs from parquet via `load_fdr_stubs_from_parquet`,
  overlays SVM scores + 4 q-values + PEP from
  `.1st-pass.fdr_scores.bin` via `load_fdr_scores_sidecar` (with
  `expected_pass=1`), parses `.reconciliation.json` into
  `HashMap<(file, vec_idx), ReconcileAction>` (entry_id → vec_idx
  join from the loaded stubs) + `Vec<GapFillTarget>` per file +
  refined `RTCalibration` per file via `from_model_params`.
- CLI/validate plumbing: `--join-at-pass=1 --no-join` is wired
  past the previous "not yet implemented" bail; new tests for
  the precondition checks (require `--input-scores`, reject
  `--input`, require `--library` + `--output`).
- New `pub mod rescore` in lib.rs.
- Visibility bumps to `pub(crate)` on
  `load_fdr_stubs_from_parquet`, `load_fdr_scores_sidecar`,
  `synthetic_input_from_parquet`, `fdr_scores_path_pass1`.

`e14fe55` — Worker invocation + extracted rescore loop:
- `config.input_files` is synthesized from `--input-scores` at
  the top of `run_analysis` (idempotent); fixes the pre-existing
  no-op behavior where `--join-at-pass=1` skipped Stage 6
  entirely because `file_name_to_idx` was empty.
- The inline per-file rescore + gap-fill + parquet write-back
  block (~280 lines) is lifted into
  `pub(crate) rescore_per_file_loop` in `pipeline.rs` with no
  body changes; the original call site becomes a one-line call.
- `crate::rescore::run_rescore` hydrates state +
  loads `per_file_calibrations` from sibling
  `.calibration.json` + builds `file_name_to_idx` +
  `per_file_cache_paths` + calls `rescore_per_file_loop`.
  Worker writes reconciled per-file `.scores.parquet` ready for
  a downstream `--join-at-pass=2` second join.

**Validation harness:**

New `pwiz-ai/scripts/OspreySharp/Compare-Stage6-Worker.ps1`
implements an HPC-portability gate. Three phases per dataset:

1. **Phase A — In-process baseline.** Stage 4 parquets + mzML +
   library staged in `_stage6_worker/<dataset>_A/`. Run osprey
   `--join-at-pass=1` (no modifier) to do Stages 5-8 in one
   process; snapshot the SHA-256 of each reconciled
   `.scores.parquet`.
2. **Phase B — Persist Stage 5 boundary.** Restore Stage 4
   parquets in `_A/`. Run `--join-at-pass=1 --join-only` to
   write boundary files sibling to each parquet.
3. **Phase C — Worker on RENAMED folder.** Restore Stage 4
   parquets in `_A/`. **Rename `_A/` → `_B/`** (different
   absolute path). Run `--join-at-pass=1 --no-join` from `_B/`.
   Worker reads relocated boundary + parquet + sibling mzML /
   calibration JSON / spectra cache, runs Stage 6, writes
   reconciled `.scores.parquet` in place at `_B/`. Snapshot
   hashes.

PASS criterion: Phase A reconciled parquets are byte-identical
to Phase C reconciled parquets. Catches absolute-path leaks,
host-name dependencies, and any in-memory-vs-disk-rehydrate
divergence in one shot.

**Findings (validation OPEN — root cause not yet identified):**

- **Both flows are individually deterministic.** 5 consecutive
  worker runs against the same boundary + parquet are
  byte-identical; 2 consecutive in-process runs are byte-identical.
- **In-process vs worker diverge on a small subset of rows.**
  Out of 463362 rows in the file_20 reconciled parquet, 324
  rows differ in their `median_polish_*` and `sg_weighted_*`
  feature values (~0.07%). Peak boundaries (`apex_rt`,
  `start_rt`, `end_rt`), single-scan scoring features (`xcorr`,
  `peak_*`, `mass_accuracy_*`, `ms1_*`), and entry identity
  columns are byte-identical across all 463362 rows.
- The differences look like real value drift — not ULP noise —
  e.g. `median_polish_cosine` of `0.964` vs `0.983` for the
  same `entry_id`.
- Confirmed input-layer divergence: `per_file_entries` going
  into `rescore_per_file_loop` is ~462k pre-compaction stubs
  in the worker but ~130k post-compaction stubs in the
  in-process flow (compaction at `pipeline.rs:3852` drops
  non-FDR-passing entries before Stage 6). Both produce the
  same final 463k-row parquet because the loop's
  `load_scores_parquet → overlay → write` pattern uses the
  original parquet as the row template.
- The differences cluster on multi-scan features specifically.
  Not yet known how the entry-list-size difference propagates
  into multi-scan scoring of those 324 entries.

**Next steps (next session):**

1. **Bisect the divergence.** Add diagnostic dumps to both
   flows at points along the multi-scan feature path
   (`tukey_median_polish` inputs, `extract_fragment_xics`
   outputs, `sg_weighted_*` intermediate state) and find the
   first computation where in-process and worker disagree on
   the 324 entries. This is the methodology that worked for
   Stage 5 cross-impl bisection — same approach here.
2. **Set up `osprey_mm` clone** at `C:\proj\osprey_mm` for
   `maccoss/osprey:main` — the historical baseline for
   bit-parity comparisons.
3. **Once bisection finds root cause + fix lands and worker is
   bit-identical to in-process**, port hydration to C#
   (currently parked) and add a corresponding harness pass.
4. **PR for Mike's review** once both sides pass the
   portability gate (`Compare-Stage6-Worker.ps1` 3/3 PASS on
   Stellar + same on Astral).

**Worker is functional today** (writes valid reconciled
parquets that pass downstream metadata checks); it just isn't
proven byte-identical to in-process yet, so we won't ship
without the bisection result.

### Session 5 — Bisection finding (ROOT CAUSE IDENTIFIED)

Added `OSPREY_DUMP_MP_INPUTS=<path>` diagnostic dump in
`crates/osprey/src/diagnostics.rs::dump_mp_inputs` and wired it
into `pipeline.rs` at the per-entry `tukey_median_polish` call
site. The dump captures `(entry_id, apex_scan, frag_pos,
frag_idx, scan_idx, rt, intensity)` for every median-polish
input, thread-safe append behind a `Mutex<File>`, gated by env
var so it's a no-op in production runs.

Ran in-process and worker on Stellar 3-file with the dump
enabled and diffed:

**Result of the bisection:**

- For the 89,555 entry_ids scored on BOTH sides, the median-
  polish inputs are byte-identical (**0 differences across
  7,488,834 dump rows**).
- The worker scores **926 additional entry_ids** that the
  in-process flow doesn't (89,555 shared + 926 worker-only =
  90,481 worker total; 0 in-process-only).
- The 324 file_20 output rows that diverge in `median_polish_*`
  / `sg_weighted_*` are precisely entries from the 926 extra
  set — their parquet rows have Stage-4-original values in
  the in-process output (because in-process never re-scored
  them) and Stage-6-recomputed values in the worker output
  (because the worker re-scored them).

**Why the worker scores extras:** `pipeline.rs:3835-3873` runs
a compaction step BEFORE Stage 6 in the in-process flow:
`per_file_entries.retain(|e| first_pass_base_ids.contains(&(e.entry_id & 0x7FFF_FFFF)))`
where `first_pass_base_ids` = base_ids of targets passing
EITHER `e.run_peptide_qvalue <= reconciliation_compaction_fdr`
(default 0.01) OR `e.run_protein_qvalue <= config.protein_fdr`
(default 0.01). Compaction drops ~462k → ~130k entries. The
worker skips this step and runs Stage 6 on all ~462k
pre-compaction entries hydrated from the parquet.

**This is a worker bug, not an in-process bug.** Those
non-passing entries can't make it into the blib (failed
peptide-level FDR), so re-scoring them is wasted work AND it
overwrites their Stage 4 features in the parquet, producing
the 324-row divergence.

### Required fix: compaction in the worker (next session)

The fix has two parts; both are needed to achieve parity:

**(A) Peptide-level compaction** — Apply
`e.run_peptide_qvalue <= reconciliation_compaction_fdr`
filter to hydrated `per_file_entries` before calling
`rescore_per_file_loop`. The `.fdr_scores.bin` v2 sidecar
already carries `run_peptide_qvalue`, so no schema change for
this branch.

**(B) Protein-rescue compaction** — The compaction predicate
is `(peptide OR protein-rescue)`. The protein-rescue branch
needs `run_protein_qvalue`, which is **NOT in the v2
sidecar**. Sidecar v2 has only the 4 q-values
(run/experiment × precursor/peptide) + SVM score + PEP +
entry_id. Need to **extend to v3** by adding
`run_protein_qvalue` (one extra f64 per record → record size
52 → 60 bytes) so the worker can apply the same protein-
rescue logic.

Extending the sidecar format means:
- Bump `FDR_SIDECAR_VERSION` to 3 in
  `crates/osprey/src/pipeline.rs` (Rust) and
  `OspreySharp.IO/FdrScoresSidecar.cs` (C# — to be touched
  later when porting to OspreySharp).
- Update writer to include `run_protein_qvalue` between PEP
  and end-of-record.
- Update reader to consume the new field.
- Update header comment + class doc on both sides.
- Update tests (round-trip + pass-mismatch tests already in
  place; add a v3-format test that exercises the new field).
- Re-run cross-impl byte parity for the existing
  `OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT` test hook.

Per the user's framing: **this is exactly what the
"rename-the-folder" portability test was designed to catch — a
gap in what the sidecar persists that prevents the rehydrated
path from reproducing the in-memory path.** The protein
q-value is the gap; v3 closes it.

**After the fix lands**, expected validation result:
`Compare-Stage6-Worker.ps1 -Dataset Stellar` should produce
3/3 byte-identical reconciled parquets between Phase A
(in-process) and Phase C (renamed-folder worker). Same for
Astral.

### Diagnostic infrastructure preserved

`OSPREY_DUMP_MP_INPUTS=<path>` is now a permanent bisection
tool in the codebase. Future Stage 7+ cross-impl divergences
can use the same pattern (declare the in-memory state at the
seam, dump it via env var, sort + diff, find first byte that
differs). Workflow is documented in the dump function's
module-level comment.

### Session 5 — Both compaction fixes landed (uncommitted)

**Sidecar v3.** `crates/osprey/src/pipeline.rs` —
`FDR_SIDECAR_VERSION` 2 → 3, `FDR_SIDECAR_RECORD_LEN` 52 → 60
bytes (added `run_protein_qvalue` f64 in `[52..60]`). Writer +
reader updated. The `persist_fdr_scores` call in `run_analysis`
moved from the bottom of the first-pass FDR block to **after**
the first-pass protein FDR + `propagate_protein_qvalues` call,
so the persisted sidecar carries real protein q-values rather
than the default `1.0`. Existing test
`fdr_scores_sidecar_v2_round_trip` renamed to
`fdr_scores_sidecar_v3_round_trip`; added distinct
`run_protein_qvalue` values per entry to catch any writer that
drops the new field. Cross-impl byte-parity test hook
(`OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT`) still in place; the C#
side will need the same v3 update when we port.

**Worker compaction.** `crates/osprey/src/rescore.rs::run_rescore`
— after `hydrate_for_rescore` returns, build
`first_pass_base_ids` using the same predicate the in-process
pipeline uses
(`run_peptide_qvalue <= reconciliation_compaction_fdr` OR
`run_protein_qvalue <= protein_fdr`), retain entries by
`base_id`, and **re-key** `reconciliation_actions` from the
hydration's pre-compaction `(file, vec_idx)` keys to
post-compaction `(file, new_vec_idx)` keys (via an
intermediate `(file, entry_id)` round-trip).

### Bisection re-run after fixes — MP inputs now byte-identical

Reran `OSPREY_DUMP_MP_INPUTS=<path>` for both in-process
(`--join-at-pass=1`, no modifier) and worker
(`--join-at-pass=1 --no-join`) against the same Stage 4
parquets + boundary file pair. Results:

| Metric | Before fixes | After fixes |
|---|---|---|
| inproc dump rows | 7,488,835 | **7,488,835** |
| worker dump rows | 7,535,149 | **7,488,835** |
| inproc entry_ids | 89,555 | **89,555** |
| worker entry_ids | 90,481 | **89,555** |
| sorted-dump SHA-256 match | NO (worker had 926 extras) | **YES** (identical) |

The two dumps are now byte-identical when sorted by
`(entry_id, apex_scan, frag_pos, scan_idx)`. Tukey's median
polish receives the SAME inputs in BOTH code paths.

Common SHA-256:
`d488e2c8dae7e2e5ffde94934e4dfae0fb641f140a435b87a7a8dc6d14062277`

Implication: every value computed downstream of
`tukey_median_polish` from these inputs (`median_polish_*` +
the `sg_weighted_*` features that depend on them) should now
also match between the two paths. Verification still needed at
the parquet content layer.

### Next steps

1. **Content-diff the reconciled parquets** between in-process
   and worker. If 0 columns differ at the value level: bit
   parity of the worker is achieved at the algorithmic layer,
   and any remaining file-size differences (~25-40 bytes per
   parquet seen post-fix) are parquet/ZSTD compression
   non-determinism unrelated to our scoring. If a non-zero
   column diff remains: add the next bisection diagnostic at
   the next layer down (e.g., where `sg_weighted_*` is
   computed, or in second-pass FDR if compaction-time decoy
   pairing is involved).
2. **Address parquet compression non-determinism** if the
   25-40 byte file-size delta blocks the harness from
   reporting PASS. Likely a ZSTD multi-thread block layout
   thing; deterministic compression knob may need to be set
   in `WriterProperties`. Worth deferring until content-diff
   shows we're otherwise clean.
3. **Commit both fixes** (Sidecar v3 + worker compaction +
   MP-inputs diagnostic) once content-diff confirms parity.
4. **Then port to C#** (Sidecar v3 reader/writer in
   `OspreySharp.IO.FdrScoresSidecar`, hydration + compaction
   in OspreySharp's worker). Worker C# port was always
   planned; parity validation on the Rust side first.

### Files modified this session (uncommitted on `feature/stage6-worker`)

- `crates/osprey/src/diagnostics.rs` — added
  `dump_mp_inputs(...)` + module-level workflow comment
- `crates/osprey/src/pipeline.rs` — sidecar v3 (header doc,
  consts, writer, reader, test renamed); moved
  `persist_fdr_scores` call to after first-pass protein FDR;
  added `crate::diagnostics::dump_mp_inputs(...)` call right
  before each `tukey_median_polish` invocation
- `crates/osprey/src/rescore.rs` — worker compaction +
  reconciliation_actions re-keying after hydrate

### Content-diff result after compaction fix

Reconciled `.scores.parquet` byte-comparison
(in-process Phase A vs worker Phase C) on file_20:

| Column family | Pre-fix | Post-fix |
|---|---|---|
| Identity (entry_id, modseq, charge, …) | 0 differ | **0 differ** |
| Peak boundaries (apex_rt, start_rt, end_rt) | 0 differ | **0 differ** |
| Single-scan scoring (xcorr, peak_*, mass_accuracy_*, ms1_*) | 0 differ | **0 differ** |
| `median_polish_*` family | 324 differ | **0 differ** |
| `sg_weighted_*` family | 324 differ | **0 differ** |
| `median_polish_min_fragment_r2` | 50 differ | **0 differ** |
| `median_polish_residual_correlation` | 321 differ | **0 differ** |
| `rt_deviation` / `abs_rt_deviation` | 0 differ | **13,400 differ** (ULP only) |

So 38 of 40 columns are now bit-identical. The only remaining
divergence is `rt_deviation` / `abs_rt_deviation`, and it is
**1-ULP-level floating-point noise**:
- max abs delta: **7.1e-15**
- median abs delta: **1.8e-15** (literally 1 ULP at f64
  precision)
- 95th percentile abs delta: 3.6e-15

Sample:
```
entry_id=29
  inproc rt_dev=0.120818237147187
  worker rt_dev=0.120818237147184
  delta       =3.553e-15
```

Functionally identical; only the last decimal place
flickers.

### Open question for next session

`rt_deviation = peak.apex_rt - ctx.expected_rt`. `apex_rt`
matches bit-exactly across all 463k rows. `expected_rt =
rt_calibration.predict(entry.retention_time)`. The
in-process flow uses the live `RTCalibration` object built by
Stage 5 LOESS refit; the worker reconstructs it from the
JSON envelope via `RTCalibration::from_model_params(params,
residual_sd)`.

`predict()` only touches `library_rts` + `fitted_values`
arrays (verified by reading the function); both are
serialized as `library_rts` / `fitted_rts` in the JSON
envelope using `format_f64_roundtrip`, which is supposed to
preserve f64 bits exactly. So in theory predict's inputs
should be bit-identical between the two paths.

**Next step**: add a diagnostic dump at `predict()` entry
(or where rt_deviation is computed) capturing
`(library_rt_input, library_rts_array_hash,
fitted_values_array_hash, predicted_output)` and find which
of those drifts. If `library_rts` / `fitted_values` arrays
differ bit-wise → JSON round-trip isn't truly lossless for
some values → fix the serialization. If arrays match but
output differs → some HIDDEN state in `RTCalibration` is
affecting `predict()` in ways the codebase doesn't suggest.

This is a much smaller investigation than the median-polish
one. Once it's resolved, parquet content-diff should be 0
columns differing across all 40, and remaining file-size
delta of 25-40 bytes is parquet/ZSTD encoding non-determinism
(separate concern, may be deterministic with the right
WriterProperties knob).

### Session 5 — rt_deviation root cause + fix

Bisection diagnostic added in `crates/osprey/src/diagnostics.rs`
(gated by `OSPREY_DUMP_PREDICT_RT=<path>`):
- `dump_predict_rt_arrays` — once per file, writes the cal's
  `library_rts` and `fitted_values` arrays.
- `dump_predict_rt_call` — every `cal.predict()` call, writes
  `(entry_id, library_rt_input, expected_rt_output)`.

Wired into the rescore search path right at the
`expected_rt = cal.predict(entry.retention_time)` call site
(`pipeline.rs` ~7000), and at the top of the rescore per-file
loop (where `rt_cal` is selected).

Diff between in-process and worker dumps showed:
- **Cal arrays differ**: 79,598 lines differ between the two
  dumps. Specifically, `fitted_values[1012]` for file_20 was
  `3.1575921556296254` in-process vs `3.157592155629626` in
  the worker — a 1-ULP difference.
- **Predict outputs differ**: 81,428 lines (consistent with
  arrays differing).

Wrote a focused round-trip test
(`crates/osprey/src/bin/rt_roundtrip_test.rs`) to confirm
where the lossy step is. Found:

> `serde_json::from_str("3.1575921556296254")` returns
> `0x400942bfad144878` (off by 1 ULP) while
> `f64::from_str("3.1575921556296254")` returns the correct
> `0x400942bfad144877`.

So serde_json's default f64 parser is *not* correctly rounded.
Our `RoundtripPrettyFormatter` writes the correct shortest
round-trip string (via Rust ryu's `format!("{}", v)`), and
`f64::from_str` reads it back exactly — but **serde_json's
default parser doesn't**.

**Fix.** Enabled the `float_roundtrip` feature on serde_json
in the workspace `Cargo.toml`:

```toml
serde_json = { version = "1.0", features = ["raw_value", "float_roundtrip"] }
```

The serde_json docs describe this exactly: *"Use sufficient
precision when parsing fixed precision floats from JSON to
ensure that they maintain accuracy when round-tripped through
JSON."* Approximately 2x slower for f64 parsing, which is fine
— our hot paths don't parse JSON.

After re-running `rt_roundtrip_test`: all six test values
round-trip bit-exactly through serde_json. Fix confirmed at
the unit level.

### Stellar portability gate: 3/3 PASS

After the float_roundtrip fix:

```
$ pwsh Compare-Stage6-Worker.ps1 -Dataset Stellar -Clean

Phase A: in-process Stages 5-8 (--join-at-pass=1)         162s
Phase B: persist boundary (--join-at-pass=1 --join-only)   75s
Phase C: rename folder, run worker (--no-join)             19s
Comparing reconciled .scores.parquet (A vs C)...

Stellar Ste-...20  PASS   267002094 bytes
Stellar Ste-...21  PASS   267332776 bytes
Stellar Ste-...22  PASS   267832763 bytes

3/3 reconciled parquets byte-identical between in-process and
worker (post-rename).  Total: 04:50

Stage 6 worker output is portable: hydrate-from-disk after a
folder rename produces byte-identical reconciled parquets to
an in-process Stage 6. HPC fan-out unblocked.
```

Full content-diff also clean (40/40 columns match, 0 rows
differ). SHA-256:
`6f7cfe9808c04a0237975734f516e36f2a91e30e36c455a246cba794e50b422d`
on both Phase A and Phase C parquets for file_20.

### Status summary

- ✅ Hydration end-to-end (Sidecar v3, reconciliation.json,
  calibration.json, parquet stubs)
- ✅ Worker invocation drives in-process `rescore_per_file_loop`
- ✅ HPC portability verified (folder rename works)
- ✅ Worker is deterministic (5/5 byte-identical reruns)
- ✅ In-process is deterministic (2/2 byte-identical reruns)
- ✅ Median-polish-input bisection: byte-identical
- ✅ All scoring feature columns (40/40): 0 rows differ
- ✅ Stellar `Compare-Stage6-Worker.ps1`: **3/3 PASS** (folder
  rename portability + content + bytes all clean)
- ⏸ Astral `Compare-Stage6-Worker.ps1` (next, larger dataset
  + GPF-style; expected to PASS now that the fundamentals
  hold)
- ⏸ Regression test against `osprey-mm` clone at `main` HEAD
  (cloned to `C:\proj\osprey-mm` for end-to-end comparison —
  ensure our changes don't perturb the in-process pipeline's
  output for runs that don't use the worker)
- ⏸ Clean up + commit + push (uncommitted on
  `feature/stage6-worker`: float_roundtrip Cargo.toml,
  predict + MP-inputs diagnostics, sidecar v3, worker
  compaction + re-keying, rt_roundtrip_test bin)
- ⏸ C# port (deferred until full Rust parity validated;
  C# will need same Sidecar v3 read/write + JSON
  float_roundtrip equivalent — Newtonsoft.Json's f64 parser
  may have the same bug, worth checking when we get there)
- ⏸ PR for Mike's review

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260502_stage6_worker.md` before starting work.

### Session 6 (2026-05-03) — Astral worker portability + osprey-mm baseline regression

Picked up after the Stellar Stage 6 worker portability gate locked.
Goal: close the remaining validation gates so the Rust PR can ship.

**Astral Stage 6 worker portability — 3/3 PASS** (24:51 wall-clock).
`Compare-Stage6-Worker.ps1 -Dataset Astral -Clean -Threads 16`. All
three reconciled `.scores.parquet` files are byte-identical between
Phase A (in-process) and Phase C (renamed-folder worker), including
the largest at 815 MB. The fundamentals that locked Stellar (sidecar
v3, worker compaction, serde_json `float_roundtrip`) hold on the
larger GPF-style dataset without further fixes.

| Dataset | File | Bytes | Status |
|---|---|---|---|
| Astral | Ast-...49 | 795,656,065 | PASS |
| Astral | Ast-...55 | 815,174,283 | PASS |
| Astral | Ast-...60 | 774,734,630 | PASS |

**Rust full build gate clean.** `Build-OspreyRust.ps1 -Fmt -Clippy
-RunTests` on `feature/stage6-worker`: fmt clean, all 463 unit tests
pass across 14 test binaries, clippy clean at `-D warnings`. CI on
the maccoss/osprey side will reproduce the same gate.

**osprey-mm baseline regression — new harness +
hypothesis-driven validation.**

The handoff called for an end-to-end regression vs `osprey-mm @ main
1a18bc8` to prove that the changes in `feature/stage6-worker` do not
perturb the in-process pipeline output. Wrote
`ai/scripts/OspreySharp/Compare-Baseline.ps1` (companion to
`Compare-Stage6-Worker.ps1`): stages mzML + library into two parallel
work dirs, runs each binary `osprey -i mzML -l lib -o blib`
end-to-end, byte-compares produced `.scores.parquet`. The harness
catches any cross-tree drift in Stage 5-8 output for users who run
without the worker.

Stellar end-to-end regression: **3/3 PASS** in 9:13 (no extra fixes
needed; both binaries produce byte-identical reconciled parquets on
all three Stellar files).

Astral end-to-end regression first attempt: **2/3 PASS** in 51:11.
File `Ast-...49` diverged. `Ast-...55` and `Ast-...60` byte-identical.

Bisection via `parquet_diff.py` (Session 5 content-diff tool):
- Row count identical (1,690,708 / 40 columns).
- 39 of 40 columns byte-identical, including all peak boundaries,
  all single-scan scoring, all multi-scan rescoring features, and
  even `mass_accuracy_deviation_mean` (signed mean) byte-identical.
- One column differed: `abs_mass_accuracy_deviation_mean` on 4,873
  rows (0.29% of total), every difference exactly 1 ULP at f64
  precision (e.g., `5.8849676905429815` vs `5.884967690542981`).

Hypothesis: the divergence comes from `pipeline.rs:2890-2897`'s
`load_calibration` call inside `rescore_per_file_loop`, which reads
`.calibration.json` back from disk in BOTH end-to-end and worker
modes (shared code path). Baseline reads with serde_json's default
f64 parser, which is 1-ULP-off on shortest-roundtrip strings;
feature reads with `float_roundtrip` enabled, which is bit-exact.
The 1-ULP drift in the cal coefficients ripples into mass m/z
corrections and shows up in `abs_mass_accuracy_deviation_mean` (the
sum of absolute errors accumulates the per-fragment ε without
cancellation, while the signed sum sees ε terms cancel to within 1
ULP and round to byte-identical).

Hypothesis test: enabled `float_roundtrip` in `osprey-mm/Cargo.toml`
(diagnostic-only working-tree edit, not committed), rebuilt
`osprey-mm` release, re-ran the harness.

Astral end-to-end regression second attempt: **3/3 PASS** in 47:14.
All three files byte-identical. Hypothesis confirmed.

| Dataset | File | Status |
|---|---|---|
| Astral | Ast-...49 | PASS |
| Astral | Ast-...55 | PASS |
| Astral | Ast-...60 | PASS |

The reverted `osprey-mm` clone is back to clean tracking
`maccoss/osprey:main` at `1a18bc8`. The diagnostic was confirmation
that the only cross-tree drift is the serde_json fix, NOT any
algorithmic change in feature/stage6-worker. Reasonable due
diligence: feature/stage6-worker is *more correct* than baseline for
end-to-end runs that hit the cal JSON round-trip path; baseline was
silently using lossy-parsed cal coefficients in Stage 6.

**Validation matrix (final):**

| Gate | Stellar | Astral | Status |
|---|---|---|---|
| Stage 6 worker portability (`Compare-Stage6-Worker.ps1`) | 3/3 PASS | 3/3 PASS | locked |
| End-to-end baseline regression (`Compare-Baseline.ps1`, after enabling `float_roundtrip` on baseline) | 3/3 PASS | 3/3 PASS | locked |
| Rust fmt + clippy + 463 unit tests (`Build-OspreyRust.ps1 -Fmt -Clippy -RunTests`) | clean | n/a | locked |

### Next steps

1. **Commit `Compare-Baseline.ps1` + this TODO update on `pwiz-ai`** so Mike can reproduce the regression check.
2. **Push `feature/stage6-worker` to `maccoss/osprey`** (3 commits since `1a18bc8`).
3. **PR filed**: https://github.com/maccoss/osprey/pull/28
   (`cli: --join-at-pass=1 --no-join Stage 6 rescore worker`).
   Body covers the three fixes, the bisection methodology, the
   validation matrix, and the reproduction steps. Open question for
   Mike: keep three commits to preserve the methodology trail, or
   squash to one?
4. **Begin C# port** on parked `pwiz:Skyline/work/20260429_osprey_sharp_stage6`, smallest validatable segment first:
   1. Newtonsoft.Json f64 round-trip unit test (does it have the same bug as serde_json default? if so, find the equivalent fix or write a custom converter).
   2. `FdrScoresSidecar` v2 → v3 (add `RunProteinQvalue`, bump version, writer + reader). Validate via existing `OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT` cross-impl byte parity test against Rust v3 output.
   3. C# hydration helper mirroring `rescore.rs::hydrate_for_rescore`. Validate by adding a small new diagnostic test hook that dumps in-memory state at the seam.
   4. Worker compaction + `reconciliation_actions` re-keying (mirror `rescore::run_rescore`). Validate via `OSPREY_DUMP_MP_INPUTS` cross-impl byte-identity check.
   5. Wire `--join-at-pass=1 --no-join` into `AnalysisPipeline`. Validate via `Compare-Stage6-Worker.ps1` Stellar 3/3 PASS for the C# binary.

**Files added/modified this session:**

- `ai/scripts/OspreySharp/Compare-Baseline.ps1` (NEW) — end-to-end baseline regression harness. Runs both binaries `osprey -i mzML -l lib -o blib` from clean staged work dirs, byte-compares reconciled `.scores.parquet`. Designed for ongoing cross-tree regression coverage; pairs with `Compare-Stage6-Worker.ps1` to cover both worker portability and in-process unperturbed-ness.
- `ai/todos/active/TODO-20260429_osprey_sharp_stage6.md` (this file) — Session 6 progress log entry.

No code changes on `osprey/feature/stage6-worker` this session.

### Session 7 (2026-05-03) — C# port of the Stage 6 worker foundation + Copilot follow-up

**Rust PR #28 review feedback addressed.** Copilot posted six inline
comments; one was a real bug (`--input-scores` was accepted without
`--join-at-pass=1`, would silently route end-to-end runs into the
join path), four were doc/comment drift between the codebase and the
docstrings, one was a perf nit (O(num_actions × num_files) in the
worker compaction re-key — cheap to fix as a `file_name → entries`
hashmap, runtime impact negligible at observed file counts since the
loop is dominated by spectra I/O). All six addressed in
`feature/stage6-worker @ 4599a4f` with a regression test for the CLI
guard. CI green on macOS / Ubuntu / Windows after a fmt fixup
(`a9c6c06`) — the original three commits had been pushed without a
local `cargo fmt` run; root-caused to `Build-OspreyRust.ps1 -Fmt`
silently in-place reformatting via `cargo fmt` instead of failing
fast via `cargo fmt --check`. Fixed in pwiz-ai master `3c76585`:
`-Fmt` now runs `cargo fmt -- --check` (matches CI) and a new
`-FmtFix` flag does the in-place reformat for the rare case it's
wanted.

**C# port: foundation pieces (segments 1-5) on parked branch
`pwiz:Skyline/work/20260429_osprey_sharp_stage6`** — local commits,
not yet pushed:

| Segment | Commit | Validation |
|---|---|---|
| 1. Newtonsoft.Json f64 round-trip test | `27e8735cd` | `TestNewtonsoftJsonF64RoundtripIsBitExact` proves .NET's `double.Parse` is correctly rounded for the same six tricky values that broke serde_json's default parser. **No fix needed for the C# port** — Newtonsoft is bit-exact. |
| 2. `FdrScoresSidecar` v2 → v3 | `a0f08edf2` | Cross-impl byte parity verified via the existing `OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT` test hook: same hardcoded inputs (entry_id 100/101/102, run_protein_qvalue 0.0042/0.0123/0.95) on both sides → SHA-256-identical 212-byte file `f42b4ab2…c3037`. |
| 3. Hydration helper (`RescoreHydration.HydrateForRescore`) | `ccce64dde` | `TestRescoreHydrationRoundTrip` writes a synthetic boundary triple (parquet + sidecar + reconciliation.json), hydrates it, asserts every field round-trips. `TestRescoreHydrationRejectsActionEntryIdNotInStubs` covers the parquet-drift error path. |
| 4. Worker compaction + `reconciliation_actions` re-keying (`RescoreCompaction.Apply`) | `0a0f03c18` | `TestRescoreCompactionRekeysActionsAndDropsNonpassing` covers the full predicate path (peptide pass + protein-rescue + decoy-by-base_id retention + action re-keying + dropped-action accounting); `TestRescoreCompactionWithoutProteinFdrSkipsRescue` covers the protein-fdr-disabled branch. |
| 5. Wire `--join-at-pass=1 --no-join` through to a worker entry point (`RescoreWorker.Run`) | `8c7a975bb` | `Program.NormalizeHpcArgs` no longer rejects the flag combination; `Program.ValidateArgs` grew a new branch under `config.NoJoin && hasInputScores` requiring `--library` + `--output`; `Main` dispatches to `RescoreWorker.Run`. The worker today does hydration + compaction only and exits with a clear "rescore engine not yet ported" message. All 298 OspreySharp tests still pass; inspection clean (0 warnings, 0 errors). |

The per-file rescore engine itself (boundary-overrides search +
gap-fill two-pass + reconciled parquet write-back) is **not yet
ported**. The in-process pipeline at `AnalysisPipeline.Run` also
stubs that out with the same "Stage 6 per-file rescore: not yet
implemented" message. Both sides will lift together once the C#
rescore engine port lands (future sprint).

**Hydration + compaction validation against Rust on real Stellar
data** (work dir
`D:\test\osprey-runs\stellar\_stage6_worker\Stellar_B`):

| Metric | Rust worker | C# worker | Match? |
|---|---|---|---|
| Pre-compaction stubs | 1,388,872 | 1,388,872 | ✅ |
| Reconciliation actions hydrated | 172,548 | 172,548 | ✅ |
| Gap-fill candidates hydrated | 822 | 822 | ✅ |
| Refined RT calibrations | 3 | 3 | ✅ |
| Post-compaction entries | 391,180 | **397,198** | ❌ +6,018 |
| Surviving base_ids | 66,727 | **67,737** | ❌ +1,010 |
| Reconciliation actions retained | 172,548 | 172,548 | ✅ |

Hydration is bit-identical at the cardinality level (file count,
stub count, action count, gap-fill count, cal count). Compaction
diverges by 6,018 entries / 1,010 base_ids (C# retains MORE).
Predicate on paper is identical: `RunPeptideQvalue ≤ peptideGate
OR (proteinGate.HasValue AND RunProteinQvalue ≤ proteinGate.Value)`,
where both gates are 0.01 by default and were 0.01 in the test
invocation (`--protein-fdr 0.01`).

**Bisection plan** (Session 8 — using existing `OSPREY_DUMP_PERCOLATOR`
diagnostic, the same one Mike's PR validated against in-process):

1. Wired `OspreyDiagnostics.WriteStage5PercolatorDump` into
   `RescoreWorker.Run` immediately after hydration. The C# worker
   under `OSPREY_DUMP_PERCOLATOR=1` now writes
   `cs_stage5_percolator.tsv` (file_name, entry_id, charge,
   modified_sequence, is_decoy, score, pep, run_precursor_q,
   run_peptide_q, experiment_precursor_q, experiment_peptide_q —
   one row per hydrated stub).
2. Need to wire `dump_stage5_percolator` into Rust
   `rescore::run_rescore` in the same way (it currently fires only
   from in-process `pipeline.rs` post-Percolator, before the
   sidecar is even written). Then run BOTH workers with
   `OSPREY_DUMP_PERCOLATOR=1` against the same boundary files →
   diff `rust_stage5_percolator.tsv` vs `cs_stage5_percolator.tsv`.
3. **If the diff is empty**, hydration is bit-identical and the
   compaction divergence is in the predicate or the gates. Likely
   suspects: `RunFdr` is not the same value used by Rust's
   `reconciliation_compaction_fdr` (the Rust field doesn't have a C#
   equivalent yet); some signed/unsigned conversion in the base_id
   mask; an `IsDecoy` flag that's true on one side and false on the
   other.
4. **If the diff is non-empty**, hydration is wrong somewhere.
   Likely suspects: `FdrScoresSidecar.TryRead` is reading
   `RunProteinQvalue` from the wrong byte offset (unlikely — the
   round-trip cross-impl test caught this kind of bug); the
   `LoadFdrStubsFromParquet` order doesn't match what the sidecar
   expects (the sidecar TryRead validates this with per-position
   `EntryId` checks, and would have failed loud).
5. The bisection methodology that worked for the Rust side also
   applies here: dump intermediate state at successively narrower
   seams using the existing `format_f64_roundtrip` formatter and
   `Compare-Percolator.ps1`-style diff.

**Files added/modified this session:**

- `pwiz_tools/OspreySharp/OspreySharp.Test/IOTest.cs` —
  `TestNewtonsoftJsonF64RoundtripIsBitExact`,
  `TestRescoreHydrationRoundTrip`,
  `TestRescoreHydrationRejectsActionEntryIdNotInStubs`,
  `TestRescoreCompactionRekeysActionsAndDropsNonpassing`,
  `TestRescoreCompactionWithoutProteinFdrSkipsRescue`,
  plus the v3 round-trip changes in `TestFdrScoresSidecarRoundTrip`.
- `pwiz_tools/OspreySharp/OspreySharp.IO/FdrScoresSidecar.cs` — v2 → v3.
- `pwiz_tools/OspreySharp/OspreySharp/RescoreHydration.cs` (NEW).
- `pwiz_tools/OspreySharp/OspreySharp/RescoreCompaction.cs` (NEW).
- `pwiz_tools/OspreySharp/OspreySharp/RescoreWorker.cs` (NEW).
- `pwiz_tools/OspreySharp/OspreySharp/Program.cs` — CLI dispatch +
  `ValidateArgs` worker-mode branch.
- `pwiz_tools/OspreySharp/OspreySharp.Test/ProgramTests.cs` — test
  rename + two new worker-mode validation tests.
- `crates/osprey/src/{diagnostics.rs,main.rs,pipeline.rs,rescore.rs}`
  on `osprey/feature/stage6-worker` — Copilot review fixes.
- `ai/scripts/OspreySharp/Build-OspreyRust.ps1` on `pwiz-ai/master` —
  `-Fmt` now `--check`, new `-FmtFix` for the rare in-place case.

### Session 8 (2026-05-03) — C# Stage 6 rescore engine: Phase 1 + Phase 2 byte-identical to Rust

PR #28 merged to `maccoss/osprey:main`; tagged v26.5.0. Bumped
OspreySharp `VERSION` to 26.5.0 (`c5f555ae7`) after auditing the
v26.5.0 release notes against C# state — every format-affecting
change (sidecar v3, reconciliation.json, dump column adds,
Gauss-Jordan tolerance, PEP non-determinism, RT cal JSON
round-trip, library_identity_hash file-name-only,
OSPREY_LOESS_CLASSICAL_ROBUST in Stage 6 refit, etc.) was already
mirrored in C# from prior PRs; only the version string needed the
bump.

**Cross-impl harness restructured for tight Stage 6 iteration:**

- `Build-Stage6Fixture.ps1` (NEW) — one-time-per-version-bump
  fixture build. Confirms Stage 4 Snappy parquets exist, runs
  `Compare-Stage5-Boundary.ps1` to verify Stage 5 byte parity at
  current binary versions (refuses if drifted), snapshots the
  verified-good state into `<testDir>/_stage6_fixture/<dataset>/`,
  stamps `.fixture-version`. Stellar fixture: 9 GB, ~5 min build.
- `Compare-Stage6-Crossimpl.ps1` (RESTRUCTURED) — per-iteration
  loop. Materializes a fresh per-tool workdir from the fixture,
  runs only `--join-at-pass=1 --no-join` on each binary against
  byte-identical inputs, hands off to `Compare-Percolator.ps1`.
  Stellar iteration: ~6 min wall-clock, ~3 min of which is the
  2x9 GB workdir copy; Rust worker 79s, C# worker 25s.

**Phase 1 + Phase 2 of the C# Stage 6 rescore engine ported:**

- `AnalysisPipeline.Stage6Rescore.cs` (NEW partial class file).
  - `RescoreStats` POCO mirroring Rust's struct.
  - `RunWorker(config)`: top-level entry point for the worker —
    synthesizes `config.InputFiles` from `--input-scores`, loads
    the spectral library + decoys, calls
    `RescoreHydration.HydrateForRescore`, applies
    `RescoreCompaction.Apply`, computes per-file multi-charge
    consensus targets via `MultiChargeConsensus.SelectRescoreTargets`,
    builds the per-file original RT cal map by loading each
    sibling `.calibration.json`, then dispatches to
    `ExecuteStage6Rescore`. Mirrors Rust `rescore::run_rescore`.
  - `ExecuteStage6Rescore`: per-file rescore loop. Pre-groups
    reconciliation actions by file, merges consensus +
    reconciliation (reconciliation wins), builds boundary_overrides
    + entry_id->idx + subset_library, loads spectra (cache or mzML
    fallback) + sibling .calibration.json mass cals, picks
    refined-or-original RT cal, calls `RunCoelutionScoring` with
    override-aware `ScoringContext`, overlays results back to
    `fdr_entries` by `entry_id` while preserving `ParquetIndex`.
    Phase 2 (gap-fill two-pass) runs after the existing-entry
    overlay: builds `gap_fill_library` from each gap-fill target's
    `TargetEntryId + DecoyEntryId`; CWT pass with
    `PrefilterEnabled=false` and no boundary overrides; tracks
    `cwtHitIds`; appends CWT results as new stubs with
    `ParquetIndex = uint.MaxValue`; forced pass for entries CWT
    missed (target or decoy) at `expected_rt +/- half_width`;
    appends forced results the same way.
  - **Score-reset on overlay** (mirrors Rust `to_fdr_entry`
    semantics): post-rescore stubs carry default Score (0.0),
    q-values (1.0), Pep (1.0); Stage 7 second-pass Percolator
    recomputes them from the new Features. Without this reset the
    OspreySharp `ScoreCandidate`'s `Score = coelutionSum`
    initializer (AnalysisPipeline.cs ~line 4088) bled through and
    produced 173k rows of post-rescore divergence vs the Rust
    worker.

- `AnalysisPipeline.cs` — Stage 6 stub at line 803 replaced with
  a real `ExecuteStage6Rescore` call. `LoadLibrary` and
  `GenerateDecoys` promoted `private` -> `internal` so the partial
  Stage6Rescore file can call them. `partial` keyword added.
- `RescoreWorker.cs` — collapsed from a 75-line implementation to
  a thin facade that instantiates `AnalysisPipeline` and delegates
  to `RunWorker`. Keeps `Program.Main`'s dispatch unchanged.

**Cross-impl bisection diagnostic ladder:**

- `dump_stage5_percolator` / `WriteStage5PercolatorDump`: extended
  to include `run_protein_q` column. Wired into `rescore::run_rescore`
  (Rust) and `RescoreWorker.Run` (C#) so both produce
  `*_stage5_percolator.tsv` for the post-hydration parity check.
- `dump_stage6_rescored` / `WriteStage6RescoredDump`: NEW high-level
  dump fired AFTER the rescore loop completes. Same column shape
  as Stage 5 percolator dump so `Compare-Percolator.ps1` reuses
  for the diff. Wired from BOTH in-process Run + worker RunWorker
  on both languages. Catches Stage 6 output divergence at the
  high-level seam before drilling into the inner-loop ladder.
- `OSPREY_DUMP_MP_INPUTS` and `OSPREY_DUMP_PREDICT_RT` (Rust-only
  v26.5.0 additions for the rescore inner-loop bisection): NOT
  yet mirrored in C#. Tracked for the pre-PR cleanup.

**One real bug caught and fixed during Phase 1+2 validation:**

`WriteStage6RescoredDump` originally used `List<T>.Sort` which is
UNSTABLE. Rust `Vec::sort_by` is stable. With duplicate
`(file_name, EntryId)` keys (a decoy paired with a target that
already passed first-pass FDR — so the post-compaction stub AND the
gap-fill stub end up in the dump), unstable sort shuffled the
dup-pair non-deterministically, and the last-write-wins comparator
in `Compare-Percolator.ps1` showed 116 false-positive divergences.
Switched to LINQ `OrderBy().ThenBy()` (stable). Rust order
preserved end-to-end.

**Validation matrix (Stellar 3-file fixture, locked at v26.5.0):**

| Seam | Rust v C# |
|---|---|
| Stage 5 boundary file pair (`Compare-Stage5-Boundary`) | 6/6 PASS |
| Post-hydration / pre-compaction dump (`OSPREY_DUMP_PERCOLATOR`) | 7/7 cols x 1,388,872 rows max_diff=0 |
| Post-rescore dump (`OSPREY_DUMP_RESCORED`) | 7/7 cols x 392,029 rows max_diff=0 |

**Runtimes (Stellar):**

- C# worker hydrate + compact + rescore + gap-fill: ~25 s
- Rust worker hydrate + compact + rescore + gap-fill + parquet
  write-back: ~80 s (includes Phase 3 not yet ported in C#)

**Open work to reach end-of-Stage-6 byte parity:**

1. **Phase 3 — reconciled `.scores.parquet` write-back.** After
   gap-fill appends complete, reload the original parquet, replace
   re-scored rows by `ParquetIndex` (NOT vec position; post-
   compaction Vec position diverges from Parquet row), append
   gap-fill rows, reassign gap-fill `ParquetIndex` to actual row,
   write back via `WriteScoresParquet` with reconciliation metadata
   (`osprey.reconciled = "true"` + `osprey.reconciliation_hash`).
   Validation gate: extend `Compare-Stage6-Crossimpl.ps1` with a
   parquet content-diff phase; PASS = byte-identical reconciled
   `.scores.parquet`.

2. **B (pre-PR) — mirror `OSPREY_DUMP_MP_INPUTS` +
   `OSPREY_DUMP_PREDICT_RT` in C#.** Drill-down ladder for any
   future divergence that the high-level `OSPREY_DUMP_RESCORED`
   gate might surface. Not blocking the per-iteration loop, but
   Mike will reasonably want the matched bisection plumbing on
   both sides before merging the C# Stage 6 PR.

3. **Astral validation pass.** After Phase 3 lands, re-run
   `Build-Stage6Fixture` + `Compare-Stage6-Crossimpl` for Astral
   (GPF-style, ~3-4x larger). Expected to PASS without further
   fixes if Stellar passes.

4. **PR for Mike.** Single PR against `maccoss/osprey:main` for
   the Rust-side dump column extension + new dump
   (`feature/stage5-percolator-dump-protein-q`). Single PR against
   `ProteoWizard/pwiz` master for the C# port + harness updates.

**Files added/modified this session:**

Rust on `feature/stage5-percolator-dump-protein-q`:
- `crates/osprey/src/diagnostics.rs` — `dump_stage6_rescored` added;
  `dump_stage5_percolator` extended with `run_protein_q` column.
- `crates/osprey/src/pipeline.rs` — `dump_stage5_percolator` +
  `dump_stage6_rescored` calls in `run_analysis`'s Stage 6 block.
- `crates/osprey/src/rescore.rs` — same dump calls in
  `rescore::run_rescore` for the worker entry point.

OspreySharp on `pwiz/Skyline/work/20260429_osprey_sharp_stage6`:
- `pwiz_tools/OspreySharp/OspreySharp/Program.cs` — VERSION
  26.4.0 -> 26.5.0.
- `pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs` —
  partial; LoadLibrary/GenerateDecoys promoted to internal; Stage 6
  stub replaced with `ExecuteStage6Rescore` call + post-rescore
  dump call.
- `pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.Stage6Rescore.cs`
  (NEW) — `RescoreStats`, `RunWorker`, `ExecuteStage6Rescore`,
  `LoadSpectraForRescore`, `LoadMassCalibrations`,
  `LoadOriginalRtCalibration`, `AddIfNotNull`. Phases 1 + 2.
- `pwiz_tools/OspreySharp/OspreySharp/RescoreCompaction.cs` —
  decoy-skip in predicate (matches Rust `!is_decoy &&`).
- `pwiz_tools/OspreySharp/OspreySharp/RescoreWorker.cs` — thin
  facade (delegates to `AnalysisPipeline.RunWorker`).
- `pwiz_tools/OspreySharp/OspreySharp/OspreyDiagnostics.cs` —
  `WriteStage5PercolatorDump` +1 column;
  `WriteStage6RescoredDump` (NEW); LINQ stable sort.
- `pwiz_tools/OspreySharp/OspreySharp.Test/IOTest.cs` — new
  `TestRescoreCompactionSkipsDecoysInPredicate` regression test.

pwiz-ai master:
- `ai/scripts/OspreySharp/Build-Stage6Fixture.ps1` (NEW).
- `ai/scripts/OspreySharp/Compare-Stage6-Crossimpl.ps1` —
  restructured; uses fixture; runs only Stage 6; two-pass diff
  (post-hydration + post-rescore).
- `ai/scripts/OspreySharp/Compare-Percolator.ps1` —
  `run_protein_q` added to numeric column list.
- `ai/scripts/OspreySharp/Compare-Stage5-AllFiles.ps1` (no change
  but referenced from documentation in this session).

**Next session handoff**: continue with Phase 3 (reconciled
parquet write-back) on `pwiz/Skyline/work/20260429_osprey_sharp_stage6`.
The fixture at `D:\test\osprey-runs\stellar\_stage6_fixture\Stellar\`
is locked; per-iteration loop is `Compare-Stage6-Crossimpl.ps1
-Dataset Stellar`. After Phase 3 + Astral validation + B, file
the two PRs.
