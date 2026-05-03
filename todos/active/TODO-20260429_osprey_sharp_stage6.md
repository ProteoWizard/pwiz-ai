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
