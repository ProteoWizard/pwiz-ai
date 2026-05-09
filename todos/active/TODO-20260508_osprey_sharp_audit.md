# TODO-20260508_osprey_sharp_audit.md — Phase 5: parity audit + perf benchmarks

> **Pipeline diagram**:
> [`pwiz_tools/OspreySharp/Osprey-workflow.html`](../../../pwiz/pwiz_tools/OspreySharp/Osprey-workflow.html)
> — open this first; this sprint's deliverable is partially the
> set of updated annotations on that diagram.

## Branch Information

- **Branch**: `Skyline/work/20260508_osprey_sharp_audit` (created
  in `C:\proj\pwiz` 2026-05-08, off pwiz/master `764d0a5577` —
  the Stage 7 .blib end-to-end-parity squash-merge)
- **Companion Rust branch**: TBD (likely
  `feature/perf-audit-stage6-rescore` or per-fix branches as
  needed; create in `C:\proj\osprey` off main `b90800f` — the
  flate2 zlib-default merge — when a Rust-side change is needed)
- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-05-08
- **Status**: In Progress — branches synced and ready
- **GitHub Issue**: (none — tool work, no Skyline integration yet)
- **PR**: (pending)

### Predecessors

| Predecessor | What it shipped |
|---|---|
| `ai/todos/completed/TODO-20260507_osprey_sharp_stage8.md` | Stage 7 `.blib` cross-impl PASS on Stellar + Astral — **first end-to-end OspreySharp port at full cross-impl parity** (pwiz #4195, maccoss/osprey #32) |
| `ai/todos/completed/TODO-20260507_osprey_sharp_stage7.md` | Stage 7 protein FDR cross-impl PASS (pwiz #4192, maccoss/osprey #31) |
| `ai/todos/completed/TODO-20260429_osprey_sharp_stage6.md` | Stage 6 byte-parity end-to-end (pwiz #4187) |
| `ai/todos/completed/TODO-20260507_ospreysharp_missing_scoring_columns.md` | Six allowlisted parquet columns now round-trip byte-for-byte (pwiz #4188) |

End-to-end cross-impl parity reached on Stellar 3-file (45153
RefSpectra) and Astral 3-file (129352 RefSpectra). Every
documented per-stage gate is GREEN.

## Objective

Now that Stages 1-7 are end-to-end cross-impl GREEN, walk back
through the pipeline applying a more rigorous lens. The goal is
**hardening, not porting** — the C# code is complete; this sprint
audits what we already shipped.

Three deliverables:

1. **Numeric-tolerance audit + tightening attempts.** Every
   per-stage gate uses some tolerance (1e-6 on Stages 1-4 PIN
   features; 1e-9 on Stages 5/6/7). Catalog every gate, document
   the max observed diff, attempt to tighten, and clearly flag any
   residual that resists tightening with the underlying reason.
   The bit-parity memory
   (`feedback_bit_parity_tolerance.md`) is the philosophical
   backbone here — every tolerance is provisional until either
   tightened to bit-parity OR signed off explicitly with a written
   rationale.
2. **Per-stage performance matrix** on Stellar + Astral, single
   file + 3-file, both implementations. Annotate
   `Osprey-workflow.html` with the latest numbers. The diagram's
   footer carries pre-Stage-6 evidence numbers from earlier
   sprints — those need refreshing through the full Stage 7 path.
3. **Address performance outliers**, particularly the C# Stage 6
   reconciliation rescore (~12 min Astral vs Rust ~2:35,
   roughly 5× gap, observed during Stage 8 sub-sprint).

## Strategy

### Step 1: Bit-parity audit catalog

Build `ai/.tmp/bit_parity_audit.md` enumerating every gate
shipped in the Stage 1-7 walk:

| Gate | Script + invocation | Default tolerance | Max observed diff | Tightening status |
|---|---|---|---|---|
| Stages 1-4 PIN features | `Test-Features.ps1` | 1e-6 absolute | TBD per dataset | TBD |
| Stage 5 first-pass FDR dump | `Compare-Percolator.ps1` | 1e-9 absolute | TBD | TBD |
| Stage 5 reconciliation planning | (parquet content diff in `Compare-Stage6-Crossimpl.ps1` Stage E) | (allowlist empty) | (per-column) | TBD |
| Stage 6 rescore q-values | `Compare-Stage6-Crossimpl.ps1` Stages D.1 + D.2 | 1e-9 absolute per column | TBD | TBD |
| Stage 7 protein FDR dump | `Compare-Stage7-Crossimpl.ps1` | 1e-9 absolute | 1.776e-15 (Stellar) | could attempt 1e-12 |
| Stage 7 `.blib` SQL row+column | `Compare-Blib-Crossimpl.ps1` | 1e-9 absolute, blob byte-equality | 0 (most numeric); blobs byte-identical | TBD |

For each gate the catalog entry should include:
- the actual cross-impl values that produced the max diff (so
  there's a concrete row to investigate)
- whether the diff is upstream-bisectable (e.g., does Stage 5
  see the same divergence?) or terminal-stage-only
- whether tightening is "free" (just lowering the threshold and
  re-running) or "expensive" (requires upstream bisection /
  algorithm fix)

### Step 2: Tightening attempts, per gate

For each gate:

1. Run with tolerance progressively lowered (1e-9 → 1e-10 →
   1e-12 → 1e-15 → 0). Record where it breaks.
2. If 1e-15 (effectively bit-parity within IEEE-754 noise) holds,
   tighten the gate's default in the harness script.
3. If it breaks before 1e-15, identify the divergent rows and
   bisect upstream. The bisection methodology from the Stage 6
   and Stage 7 sub-sprints (env-var-gated TSV dumps, externally
   joined against the other side's output) is the model.
4. For numeric drift that resolves to math-library / FMA / BLAS
   ordering differences (e.g., the 1.776e-15 max diff on Stage 7
   `best_peptide_score`), document the root cause and choose a
   defensible tolerance with the user. Don't unilaterally
   loosen back.

Tightening focus areas (highest likely yield):

- **Stage 7 `Compare-Stage7-Crossimpl.ps1` (protein FDR)** —
  max diff 1.776e-15. Tighten to 1e-12 or 1e-13.
- **`Compare-Blib-Crossimpl.ps1` numeric columns** — max diffs
  not yet enumerated; almost all PASSed at 1e-9 with max_diff=0
  per the Stage 8 final run, so likely already at full bit
  parity. Verify by re-running at 1e-15.
- **`Compare-Stage6-Crossimpl.ps1` parquet content diff** —
  the per-column tolerances may be tunable.

### Step 3: SHA-256 and content-equality slip-through audit

Several gates accept "content equality" rather than file-byte
equality — for good reasons (SQLite engine differences, different
zlib library output choices, etc.). Walk every one and write down
WHAT'S NOT BIT-IDENTICAL and WHY:

- `.blib` SQLite file SHA-256 differs (Rust 39 MB / C# 38.8 MB on
  Stellar, Rust 105 MB / C# 104 MB on Astral). Rusqlite vs
  System.Data.SQLite produce different page layouts /
  autoincrement / index ordering for identical logical content.
  The `Compare-Blib-Crossimpl.ps1` row+column gate is what
  actually validates parity.
- Reconciled `.scores.parquet` file SHA-256: investigate. Stage 6
  cross-impl already validated per-column equality but the parquet
  files themselves likely differ at the byte level due to
  Parquet.Net vs the Rust `parquet` crate making different page
  layout / dictionary encoding choices for identical logical
  content. Confirm with `Diff-Parquet.ps1`.
- Diagnostic dump TSVs: those should be byte-identical — they go
  through `format_f64_roundtrip` on both sides. If any aren't,
  that's a real bug.

For each "content-equality but not byte-equality" gate, document:
- Why byte-equality isn't achievable today.
- What would be needed to close it (e.g., port Skyline's BlibData
  to a shared `Shared/BiblioSpec` so both Skyline and OspreySharp
  use the same C# code; the longer-term direction).
- The risk if this doesn't close: a future change in either
  SQLite / Parquet library could silently shift byte patterns
  without breaking the row+column gate. Acceptable risk given
  the mitigation of the row+column gate, but documented.

### Step 4: Per-stage performance matrix

Build a benchmark matrix for the full pipeline:

| Dataset | File count | Stage 1-4 | Stage 5 | Stage 6 | Stage 7 | Total | Peak RAM |
|---|---|---|---|---|---|---|---|
| Stellar | 1-file | C#: ___ / Rust: ___ | ... | ... | ... | ... | ... |
| Stellar | 3-file | ... | ... | ... | ... | ... | ... |
| Astral  | 1-file | ... | ... | ... | ... | ... | ... |
| Astral  | 3-file | ... | ... | ... | ... | ... | ... |

Capture method: `Bench-AllStages.ps1` (new — extend existing
`Bench-Scoring.ps1` pattern) drives 5-iteration warm-cache wall
clock per stage per implementation; logs per-stage [TIMING]
markers from each tool's log are aggregated. Peak RAM via
`Get-Process` / Rust's resident-set tracking.

Existing footer of `Osprey-workflow.html` has Stellar +
Astral perf numbers from Sessions 14-16 of the original Phase 1-3
sprint (single-file C# vs Rust and 3-file ratios). Those are
correct for Stages 1-4 but pre-date the Stage 5/6/7 work and the
post-Stage 7 .blib write — refresh.

### Step 5: Address C# Stage 6 reconciliation rescore perf gap

Observed during the Stage 8 sub-sprint: on Astral 3-file with
non-trivial reconciliation (125548 target + 89986 decoy consensus
peptides, 4662 entries needing re-scoring), C# total time was
~12 minutes vs Rust ~2:35. The Stage-6 rescore portion is the
dominant gap.

Plan:

1. Profile the C# rescore loop with dotTrace (or built-in
   `[TIMING]` markers).
2. Compare against the Rust rescore loop's timing breakdown.
   Rust uses `run_search()` with `boundary_overrides` and
   per-window XCorr preprocessing optimization
   (`preprocess_spectrum_for_xcorr` called once per window); the
   C# port may not have this optimization.
3. If the C# rescore is already algorithmically equivalent,
   investigate parallelism (Rust runs sequentially by file but
   parallel within file across windows).
4. Implement the missing optimization or document the
   architectural tradeoff (e.g., if sequential rescore is required
   to bound peak RAM the way Stage 6 needs).

### Step 6: Annotate Osprey-workflow.html

After Steps 4 + 5, update the diagram with:

- Per-stage `[TIMING]` annotation in each stage box (Rust /
  OspreySharp, single-file + 3-file ratios).
- Per-stage parity tolerance + max observed diff badge.
- Footer evidence section refreshed with the latest dataset
  totals.
- Any new performance optimizations note.

### Step 7: Test rigor — uncovered configurations

Walk through configurations the cross-impl gates haven't
exercised:

- Single-file runs through every stage (Stage 5/6 has
  `is_single_file` shortcut paths).
- Larger experiments (>3 files; e.g., the 24+ file Astral runs).
- Different libraries (currently DiannTsv only on Stellar +
  Astral fixtures; check elib + blib library loaders).
- `--fdr-level` variants: `Precursor` (default; tested),
  `Peptide` (untested), `Both` (untested). Note: C#'s
  `FdrLevel` enum lacks the Rust `Protein` variant — call out
  if that matters for users.
- `--shared-peptides` variants: `All` (default), `Razor`,
  `Unique`. Razor mode in particular has determinism rules that
  warrant cross-impl validation.
- Workers: HPC modes via `--no-join` per-file then
  `--join-at-pass=1` separate process. Has been used during
  development but no automated cross-impl gate runs through it.

For each uncovered config: either add it to a cross-impl gate or
document why it's out of scope (e.g., depends on a feature not
yet ported).

## Tasks

### Priority 1: Bit-parity audit catalog (Step 1)

- [ ] Enumerate all current cross-impl gates with their tolerance
      defaults
- [ ] Run each gate at the current tolerance, record max diff +
      first divergent row per column
- [ ] Dump the catalog into `ai/.tmp/bit_parity_audit.md`

### Priority 2: Tightening attempts (Step 2)

- [ ] `Compare-Stage7-Crossimpl.ps1`: try 1e-12 → 1e-13 → 1e-15
- [ ] `Compare-Blib-Crossimpl.ps1`: try 1e-12 → 1e-15 on numeric
      columns; verify blob byte-equality holds
- [ ] `Compare-Percolator.ps1` (Stage 5): try 1e-12 → 1e-15
- [ ] `Compare-Stage6-Crossimpl.ps1`: tighten per-column
      tolerances if free
- [ ] Where tightening breaks before 1e-15, root-cause + document

### Priority 3: SHA-256 / content-equality audit (Step 3)

- [ ] Catalog every gate that doesn't enforce file byte equality
- [ ] Document why and what would be needed to close
- [ ] Capture the diagnostic-dump TSVs that SHOULD be
      byte-identical and verify they are

### Priority 4: Performance matrix (Step 4)

- [ ] `Bench-AllStages.ps1` written, drives 5-iter warm-cache
- [ ] Stellar single-file + 3-file numbers captured
- [ ] Astral single-file + 3-file numbers captured
- [ ] Peak RAM per stage captured

### Priority 5: Stage 6 rescore performance (Step 5)

- [ ] Profile C# rescore loop on Astral 3-file
- [ ] Identify dominant cost vs Rust
- [ ] Port missing optimization OR document tradeoff
- [ ] Re-bench, confirm gap closed or scoped

### Priority 6: Workflow.html annotations (Step 6)

- [ ] Per-stage [TIMING] annotations on diagram
- [ ] Per-stage parity tolerance + max diff badges
- [ ] Footer evidence refreshed
- [ ] Diagram passes a "fresh visitor" sniff test (a developer
      with no context should be able to see what works, what
      doesn't, where parity is bit-exact vs tolerance-based)

### Priority 7: Test rigor (Step 7)

- [ ] Single-file gate runs added
- [ ] `--fdr-level peptide` + `--fdr-level both` cross-impl runs
      added (or documented as unsupported on the C# side and
      route the warning back to the user)
- [ ] `--shared-peptides razor` cross-impl run added (determinism
      regression test)
- [ ] Larger-experiment test (>= 6 files) cross-impl run

## Gate for PR

- All numeric tolerances either tightened to bit-parity or
  documented with rationale.
- Per-stage perf numbers in `Osprey-workflow.html` refreshed.
- Stage 6 rescore C#/Rust perf gap closed OR scoped to a future
  TODO with concrete handoff.
- New harness scripts (`Bench-AllStages.ps1` and any tightened
  Compare-* defaults) committed.
- No regressions on existing gates: every Stage 1-7 gate still
  GREEN at its pre-sprint-or-tighter tolerance.

## Notes

- This is a hardening sprint. Resist the temptation to add new
  features — Stages 1-7 are the goal.
- The `feedback_bit_parity_tolerance.md` memory is the
  philosophical backbone. Every tolerance gets explicit user
  sign-off either implicitly (by being tightened to bit-parity)
  or explicitly (by being documented with rationale and flagged).
- The `feedback_pwiz_worktree_preference.md` memory says new
  feature branches go in `C:\proj\pwiz`, not `pwiz-work1/2`.
  Honor it for this sprint.
- Astral runs take ~10-12 minutes for the C# pipeline. Don't
  re-run the full pipeline if a single-stage perf measurement
  suffices — use `--join-at-pass=1` with cached parquets when
  measuring Stages 5+.
- The `OSPREY_TRACE_PEPTIDE` env-var diagnostic
  (osprey/docs/17-peptide-trace.md) and the parquet metadata
  hashing for cache invalidation
  (`osprey.search_hash` / `osprey.library_hash` /
  `osprey.reconciliation_hash`) are existing tools that may
  speed up the audit work; both are documented in the Rust
  CLAUDE.md.

## See also

- `ai/todos/completed/TODO-20260507_osprey_sharp_stage8.md` —
  Stage 7 .blib sub-sprint (immediate predecessor; documents the
  10 commits that closed the .blib gate).
- `ai/todos/active/TODO-20260423_osprey_sharp.md` — Phase 4
  umbrella (Stages 6-7).
- `pwiz_tools/OspreySharp/Osprey-workflow.html` — pipeline
  diagram; this sprint refreshes its annotations.
- `ai/scripts/OspreySharp/` — all `Compare-*` and `Bench-*`
  scripts; this sprint adds `Bench-AllStages.ps1` and may
  tighten existing Compare-* defaults.

## Progress log

### 2026-05-08 — Session 0 (setup; no audit work yet)

Both predecessor PRs are merged:
- ProteoWizard/pwiz#4195 → master `764d0a557` (Stage 7 .blib
  end-to-end cross-impl parity).
- maccoss/osprey#32 → main `b90800f41` (flate2 zlib-default
  backend).

Branches synced and the audit branch is created in `C:\proj\pwiz`
off pwiz/master:HEAD per WORKFLOW.md (NOT in pwiz-work2 — see
`feedback_pwiz_worktree_preference.md`). osprey on main, ready for
a feature branch when a Rust-side change is needed.

`mcp__status__set_active_project` set to `C:\proj\pwiz` so
`/pw-continue` and the statusline pick up the right worktree.

No audit work yet — picking up at Priority 1 (bit-parity audit
catalog) in the next session.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260508_osprey_sharp_audit.md` before starting
work.

### 2026-05-08 — Session 1 (audit + Test-Regression.ps1)

The "Phase 5: hardening" framing was wrong: a skeptical audit
showed that every Stage 5/6/7/.blib parity claim from prior
sprints was conditional on shared Rust Stage 1-4 input via
`--input-scores`. Each stage had been declared bit-parity
against the previous stage's locked fixture, masking the
genuine end-to-end divergence. Stage 6 reconciliation in
particular silently no-op'd on every end-to-end run because
its CWT-candidate input was not persisted.

**What landed (across pwiz and ai)**:

- `pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs`:
  always build `noJoinMetadata` and populate
  `perFileParquetPaths` outside `--input-scores` mode, so
  Stage 6 reconciliation finds CWT candidates end-to-end.
  Stellar 1-file goes from 0 reconciliation actions to ~57k
  (matches Rust's ~57k).
- `pwiz_tools/OspreySharp/OspreySharp/Program.cs`: corrected
  `--fdr-level` help text default (`precursor`, not `both` —
  matches `OspreyConfig.cs:100` and `CoreTypesTest.cs:395`).
- `ai/scripts/OspreySharp/Build-OspreySharp.ps1`: pass
  `/restore` to MSBuild so the script doesn't fail on a clean
  package cache.
- `ai/scripts/OspreySharp/Test-Regression.ps1`: new end-to-end
  cross-impl regression test. Marches stage1to4 -> 5 -> 6 ->
  7 -> blib, fail-fast, freezes per-stage inputs for tight
  bisection cycles. Subsumes the per-stage Compare-* gates
  for the most-common regression workflow. Default cycle on
  Stellar 1-file: ~1 min stage1to4 (`--no-join` end-to-end on
  both sides), ~30s for any single re-iterated stage.
- `ai/scripts/OspreySharp/inspect_parquet.py`: parquet
  inspector + diff helper; aligns rows by `entry_id` and
  reports per-column max abs diff with row-set deltas
  (handles row-count mismatches that `Diff-Parquet.ps1`
  silently passes).

**What Test-Regression.ps1 surfaces today (Stellar 1-file)**:

- `stage1to4`: FAIL. C# admits 2151 (precursor, charge) pairs
  Rust does not score (0.46% of all entries). Sample:
  entry_id 531 = `AAELLQDEYSGR`, charge 3, target,
  `xcorr=-0.02` (weak peak Rust rejects pre-scoring).
  `xcorr` and `sg_weighted_xcorr` also drift on ~90% of rows
  at max diff 5.1e-7 / 3.1e-7 (well under the 1e-6 PIN gate;
  same drift `Test-Features.ps1` already catalogs). Every
  other column of `.scores.parquet` is bit-identical (38 of
  40 columns, including all CWT/fragment blobs and peak
  selections).
- Stage 5 logic: bit-parity given identical input (verified
  earlier in this session via the now-superseded
  `Audit-Stage5.ps1`). All 4 sub-dumps (standardizer,
  subsample, svm_weights, percolator) byte-identical.
- Stage 6 reconciliation: now runs with ~175k actions per
  side, but the breakdown differs (Rust 36k use_cwt + 22k
  forced; C# 1-4k use_cwt + 56k forced). Likely a planner
  CWT-acceptance criterion difference, not a CWT-data
  difference (C# now populates CWT on 100% of rows).

**Pre-existing test failures (kept after this session)**:

- `TestCwtCandidateCrossImplParity` and
  `TestCsScoringPopulatesCwtCandidates` in
  `OspreySharp.Test/CwtCandidateCodecTest.cs` — both depend
  on a stale May-7 `.scores.cs.parquet` fixture in
  `_stage5_3file/`. With this session's fix, a freshly-built
  `.scores.parquet` has CWT candidates on 100% of rows; the
  failing tests are pinned to the stale fixture and
  effectively test for a bug that no longer exists. Either
  regenerate the fixture or rewrite the tests to drive a
  fresh parquet through `Test-Regression.ps1` style
  end-to-end.

**Next session targets (Test-Regression-driven)**:

1. Drill into the 2151 only-in-C# entries. Trace
   `AAELLQDEYSGR` charge 3 with `OSPREY_TRACE_PEPTIDE` on
   both binaries to localize where Rust rejects it.
2. Once stage1to4 is GREEN, advance the regression to
   stage5/6/7/blib and address each stage's first FAIL with
   the same fast-cycle iteration loop.
3. Regenerate or rewrite the two failing CWT codec tests so
   they no longer pin to stale fixtures.

### 2026-05-08 — Session 2 (Stage 1-4 root-cause + dedup port + harness hardening)

Used `OSPREY_TRACE_PEPTIDE` (Rust-only) to confirm `AAELLQDEYSGR`
charge 3 never reaches Rust's first-pass CWT scoring. Rust's
`--verbose` log surfaced the proximate cause: `Double-counting
deduplication: removed 2151 entries (1406 targets, 745 decoys;
462802 remaining)` — exactly the 2151 row delta `inspect_parquet.py
--diff` was reporting. Likely added to Rust after Stage 1-4 was
declared complete; the regression test wasn't there to catch it.

**Ported Rust `deduplicate_double_counting` to OspreySharp**
(`pwiz_tools/OspreySharp/OspreySharp/AnalysisPipeline.cs`):
new `DeduplicateDoubleCounting` + helpers
`CountTopNFragmentOverlap` and `TopNFragmentMzs`. Per-window
parallel sweep, top-6 fragment overlap with calibrated tolerance,
RT neighborhood = 5x median spectrum spacing. Wired into
ProcessFile right between scoring and `DeduplicatePairs` —
mirrors Rust's call site in pipeline.rs.

**Result on Stellar 1-file**: row counts now match exactly
(462802 = 462802, only_A=0, only_B=0). 38 of 40 columns
bit-identical including all peak selections and CWT/fragment
blobs. Only `xcorr` and `sg_weighted_xcorr` still drift at
5.1e-7 / 3.1e-7 (the same sub-1e-6 algorithmic noise
`Test-Features.ps1` has accepted since Stage 1-4 was declared
complete). Test-Regression's `stage1to4` comparator tolerance
moved to 1e-6 to match the documented PIN gate.

**Stage 6 single-file gate**: `AnalysisPipeline.cs` had
`if (perFileEntries.Count > 1 && config.Reconciliation.Enabled)`
which silently bypassed Stage 6 entirely on single-file runs.
Rust's structure runs Stage 6 always (multi-charge consensus is
meaningful within one run; cross-file reconciliation degenerates
to 0 actions naturally on single file). Removed the `> 1` guard.
Stage 6 now runs on single file as expected. **Follow-up**: C#'s
reconciliation planner produces ~22758 actions on single file
where Rust produces 0 — likely C#'s `compute_consensus_rts`
builds consensus from single-file evidence; Rust's needs
cross-file. Tracked as a separate task.

**Test-Regression hardening**:
- Env-var leak: `[Environment]::SetEnvironmentVariable($k, $null)`
  in PowerShell sets to "" rather than unsetting; the OSPREY
  binaries treat "" as set. Switched to `Remove-Item env:$k`
  with a defensive sweep of every `OSPREY_*` hook at the start
  of each `Invoke-Tool` call. `OSPREY_PERCOLATOR_ONLY` (and
  similar) no longer leak from one stage's run to the next.
- `Freeze-Stage1to4` now propagates the mzML files into
  `stage5/inputs/` so Stage 6 rescore can re-extract spectra
  during stage isolation.
- `Compare-Stage1to4` runs `inspect_parquet.py --diff` at
  `--tolerance 1e-6` (matches Test-Features.ps1 PIN gate).

**Test-Regression Stellar 1-file march status after this
session**:

| Stage | Status | Notes |
|---|---|---|
| stage1to4 | PASS | dedup + 1e-6 tolerance |
| stage5 | PASS | bit-parity given shared input |
| stage6 | FAIL | C# 22758 reconciliation actions vs Rust 0 |
| stage7 | not yet reached | |
| blib  | not yet reached | |

**Next session targets**:

1. Localize C#'s `compute_consensus_rts` extra single-file
   actions vs Rust's empty consensus.
2. Add `-Verbose` and `-TracePeptide` to Test-Regression so
   future regressions like `peak_sharpness FP-noise-on-large-
   values` or `Double-counting deduplication: removed 2151`
   surface natively without requiring manual log inspection.
3. Port `OSPREY_TRACE_PEPTIDE` to OspreySharp so cross-impl
   per-peptide trace becomes possible (currently Rust-only).
4. Once stage6 GREEN, advance to stage7 + blib.
