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

### 2026-05-08 — Session 3 (Stage 6 single-file consensus + rescore drill)

Used the full stage6 dump set (`OSPREY_DUMP_MULTICHARGE`,
`OSPREY_DUMP_CONSENSUS`, `OSPREY_DUMP_RECONCILIATION`,
`OSPREY_DUMP_RESCORED`) under Test-Regression to bisect the
single-file Stage 6 divergence in pipeline order. Multi-charge
consensus targets came out **byte-identical** in one shot
(`rust=cs=D898F1518662`, 917139 bytes), localizing the gap
strictly downstream — exactly the kind of forced-bisection the
existing dump-and-exit-only env vars were built for.

**Cross-file consensus-emptiness gate**: Rust's
`pipeline.rs:4146` defines `reconciliation_enabled = ...
per_file_entries.len() > 1`, so single-file runs never compute
cross-file consensus. C# was computing it unconditionally on
single-file (59618 entries, all `n_runs_detected = 1`) which
poisoned the planner into emitting 22758 spurious `use_cwt_peak`
actions where Rust had 0. Wrapped `ConsensusRts.Compute(...)` in
a `perFileEntries.Count > 1` guard returning empty — mirrors
Rust exactly. Reconciliation TSV now byte-identical between
sides at 89 bytes (header only).

**Stage 6 status after this session (Stellar 1-file)**:

| Sub-dump | Rust | C# | Result |
|---|---|---|---|
| multicharge | 917139 | 917139 | **PASS** |
| reconciliation | 89 (header) | 89 (header) | **PASS** |
| rescored | 13456256 | 14554330 | FAIL — see below |

**Remaining `rescored.tsv` divergence**: Same row count (90579)
on both sides, same header. Spot-check on entry_id 21
(`AAAAALSQQQSLQER` charge 3, original apex 8.559) shows: Rust
writes `score=0  pep=1  q=1` (rescore returned "no peak" at
the multi-charge consensus apex 8.054), C# writes real
`score=-0.127  pep=0.123  q=0.026`. So Rust's rescore is
silently returning failure for some multi-charge consensus
targets while C#'s rescore succeeds. About 8% of the rescored
file's content is this one class of divergence. Next session's
target.

**Test-Regression diagnostic enhancements landed**:
- Stage6 envVars now include `OSPREY_DUMP_MULTICHARGE` and
  `OSPREY_DUMP_CONSENSUS`, comparing in pipeline order. The
  first divergent dump localizes Stage 6 to a sub-block within
  one round.
- Cycle time on `-StartStage stage6 -StopAfterStage stage6
  -Side cs`: ~2 min. Tight enough for iterate-on-Stage6 work.

**Open follow-ups (for next session)**:

1. Localize the rescored.tsv divergence — likely Rust's
   rescore at the consensus boundary applies a stricter
   peak-detection check that C# is missing.
2. Add `-Verbose` + `-TracePeptide` to Test-Regression
   (already on the list; would have nailed this session's
   bug faster).
3. Once stage6 GREEN, advance to stage7 + blib.

**Test-Regression Stellar 1-file march status after this
session** (replaces prior session's table):

| Stage | Status |
|---|---|
| stage1to4 | PASS |
| stage5 | PASS |
| stage6 | FAIL (rescored.tsv only; 2 of 3 sub-dumps now PASS) |
| stage7 | not yet reached |
| blib | not yet reached |

### 2026-05-08 — Session 4 (closed Stage 6; reached Stage 7)

Drilled the rescored.tsv divergence with the existing dump-and-
exit env vars in Test-Regression. Bisection: rust 9956 rows had
score=0/q=1; C# had 0. Trace: C#'s Stage 6 rescore log said
"Stage 6 rescore: 0 entries re-scored" — the rescore loop was
silently skipping all files because it couldn't find them in
config.InputFiles (which is empty in --input-scores mode).

**Three pwiz fixes landed**:

1. **Synthesize InputFiles from --input-scores in
   AnalysisPipeline.Run()** (was only done in RescoreWorker).
   Mirrors Rust's `run_analysis` idempotent synthesis at
   pipeline.rs ~3144.
2. **Reset existing fdrEntries[idx] for every consensus target,
   not just rescore-loop-returned ones.** Without this, multi-
   charge consensus targets where RunCoelutionScoring returned no
   entry (no peak at the override boundary) kept their first-pass
   Percolator scores instead of the score=0/q=1 placeholders Rust
   writes.
3. **Skip cs_stage6_consensus.tsv dump on empty consensus** to
   match Rust's dump_stage6_consensus elision semantic. Without
   this, single-file C# emitted a header-only consensus.tsv and
   Test-Regression flagged it as asymmetric absence.

**Result on Stellar 1-file**:
- stage1to4 PASS, stage5 PASS, **stage6 PASS** (all 3 dumps
  byte-identical: multicharge / reconciliation / rescored).
- The Rust binary's stage6 rescored.tsv (sha 430D1192CC86) and
  C#'s now hash-equal — full bit parity on Stage 6 outputs at
  --input-scores Stage 4 boundary.

**Test-Regression hardening**:
- `Compare-DumpSha` treats symmetric absence (both sides skipped
  writing a particular dump) as PASS rather than MISSING.
- `Freeze-PostStage4` now overlays the prior stage's `rust/`
  `.scores.parquet` over the inputs/ copy. Stage 6 rewrites the
  parquet in place, so downstream stages must see the rewritten
  version. Without this, stage7 was reading the pre-Stage-6
  parquet and re-deriving everything (8 of 8 protein FDR
  columns wildly divergent).

**Stage 7 reached, FAILs at protein FDR**: 5444 rust rows vs
5445 cs rows. `best_peptide_score` max_diff = 18.29 on 5434 of
5444 common rows; `group_qvalue` max_diff = 0.999 on 3791 rows.
Underlying cause is unconfirmed but a likely contributor: the
test harness compensates for input-stage mismatch in the freeze
step (publishing post-Stage-6 parquet as stage7 input), but the
**binary itself doesn't validate that --join-at-pass=1 was given
the right kind of parquet**. Rust has `--join-at-pass=2 +
expect_reconciled_input` which errors clearly when the wrong
stage's parquet is supplied; OspreySharp does not implement
`--join-at-pass=2` yet (Program.cs:548-551 explicitly notes it
as not-yet-implemented). The right next-session move:

1. Port `--join-at-pass=2` to OspreySharp with the
   `osprey.reconciled` metadata validation Rust does at
   pipeline.rs:3313-3344.
2. Update Test-Regression's stage7 invocation to use
   `--join-at-pass=2` so wrong-stage-parquet errors loudly
   instead of silently re-running.
3. Once the input semantics are guaranteed, characterize the
   remaining stage7 protein-FDR divergence (best_peptide_score
   18.29 max diff). Multi-charge consensus + reconciliation are
   bit-identical at this point, so Stage 7 must be picking
   different peptides per protein OR running second-pass
   Percolator differently.

**Test-Regression Stellar 1-file march status after this
session** (replaces prior session's table):

| Stage | Status | Notes |
|---|---|---|
| stage1to4 | PASS | dedup port + 1e-6 PIN tolerance |
| stage5 | PASS | bit-parity given shared input |
| stage6 | **PASS** | multicharge + reconciliation + rescored all byte-identical |
| stage7 | FAIL | best_peptide_score max diff 18.29; needs --join-at-pass=2 port + investigation |
| blib | not yet reached | |

### 2026-05-08 — Session 5 (--join-at-pass=2 port to OspreySharp)

The user surfaced that `--join-at-pass=2` was a documented requirement
of the Stage 7 sprint (per `TODO-20260507_osprey_sharp_stage7.md`,
upstream PR maccoss/osprey#31 + commit `0d13198`) but never landed in
OspreySharp. The C# entry-point error message at `Program.cs:606`
explicitly read "is not yet implemented." The intended HPC use case
(per the Stage 7 TODO) is exporting reconciled parquets + sidecars
across compute-node boundaries and rehydrating Stage 7-8 from them.
Without this entry path, every Stage 7 edit-build-test cycle re-ran
Stages 5-6 (~1:27 vs the ~0:07 Rust achieves with the rehydration
path). That dropped requirement is what made the prior session's
Test-Regression stage7 isolation slow + functionally wrong.

**Ported the four-fix-pattern from the Rust commit**:

1. **CLI accepts `--join-at-pass=2`** (Program.cs): drops the
   "not yet implemented" error, sets `joinOnlyFlag=true` so the
   pipeline routes through the existing `--input-scores` branch.
2. **`OspreyConfig.ExpectReconciledInput`** field; Program.cs
   sets it when `--join-at-pass=2`. Mirrors Rust main.rs:613.
3. **`ParquetScoreCache.ValidateScoresParquetGroup`** errors
   clearly when any `--input-scores` parquet has
   `osprey.reconciled != "true"`. Tested:
   ```
   --join-at-pass=2 requires a reconciled (post-Stage-6)
   parquet, but X has osprey.reconciled = 'false'. Either it
   is a Stage 4 (raw) parquet — in which case use
   --join-at-pass=1 — or run a full pipeline first to produce
   reconciled parquets.
   ```
4. **`AnalysisPipeline.Run`** wiring: under
   `ExpectReconciledInput`, load 1st-pass sidecar
   pre-compaction onto stubs → skip first-pass Percolator →
   run first-pass protein FDR + compaction → reload 2nd-pass
   sidecar after compaction by entry_id → skip Stage 6
   entirely → run Stage 7 protein FDR → blib.

**`AnalysisPipeline.cs` also gained 2nd-pass sidecar write**
(after RunProteinFdr) so a normal `--join-at-pass=1` end-to-end
run produces both sidecars. Pairs with the existing 1st-pass
sidecar write at compaction time — a single end-to-end run now
produces all artifacts a subsequent `--join-at-pass=2` invocation
needs to rehydrate.

**Open follow-ups (next session)**:

1. **Update Test-Regression stage7 to use `--join-at-pass=2`**
   with the reconciled fixture from a prior end-to-end run.
   Resolve the fixture chicken-and-egg (stage7 needs the
   reconciled parquet + both sidecars; today only stage6
   isolation produces them, and only via `OSPREY_RESCORED_ONLY`
   exit — so 2nd-pass sidecar write is bypassed). Either drop
   `OSPREY_RESCORED_ONLY` from stage6 (let it run RunProteinFdr
   too) or add a separate fixture-build phase.
2. **Investigate the actual Stage 7 protein FDR divergence**
   (`best_peptide_score` max diff 18.29 from prior session).
   With `--join-at-pass=2` working, the iteration cycle drops
   to ~10s/side and the bisection becomes tractable.
3. Consider porting Rust fix #2 ("META_RECONCILED written on
   zero-overlay rescore") — verify C#'s Stage6Rescore writes
   `osprey.reconciled = "true"` even on 0-action runs. Already
   reviewed in Session 4 work and looked correct, but worth a
   targeted unit test.

### 2026-05-08 — Session 6 (closed Stage 7 + blib; ALL FIVE STAGES GREEN)

Resolved the Stage 7 fixture chicken-and-egg + 2nd-pass sidecar
puzzle. Three fixes landed:

1. **Moved 2nd-pass FDR sidecar write to BEFORE `RunProteinFdr`**
   in `AnalysisPipeline.cs`. The sidecar's contents (Score,
   run/experiment q-values, Pep, RunProteinQvalue) are NOT
   modified by `RunProteinFdr` — that only sets
   ExperimentProteinQvalue, which the sidecar doesn't carry.
   Writing earlier means the `OSPREY_STAGE7_PROTEIN_FDR_ONLY=1`
   early exit (used by stage6 isolation) leaves the 2nd-pass
   sidecar on disk for `--join-at-pass=2` rehydration. No need
   to pay for blib write.
2. **`--join-at-pass=2` 2nd-pass sidecar fallback to 1st-pass**
   when 2nd-pass missing. Mirrors Rust's pipeline.rs:3482
   "prefer 2nd-pass, fall back to 1st-pass" semantic. Rust
   skips 2nd-pass sidecar write on single-file runs (gated by
   `input_files.len() > 1` at pipeline.rs:4489) so single-file
   `--join-at-pass=2` needs the fallback to work at all. C#
   now matches.
3. **Sidecar paths derive from input file stem, not parquet
   stem.** `FdrScoresSidecar.Pass1Path()` /
   `FdrScoresSidecar.Pass2Path()` build
   `<dir>/<stem>.{1st,2nd}-pass.fdr_scores.bin`; passing a
   parquet path (`*.scores.parquet`) produced
   `*.scores.{1st,2nd}-pass.fdr_scores.bin` (with spurious
   `.scores`). Fixed by using `config.InputFiles` (synthesized
   from --input-scores stems via
   `RescoreHydration.SyntheticInputFromParquet`).

**Test-Regression Stellar 1-file march status — FINAL**:

| Stage | Status | Wall (rust + cs) | Notes |
|---|---|---|---|
| stage1to4 | PASS | 0:26 + 0:36 | dedup port + 1e-6 PIN tolerance |
| stage5 | PASS | 1:19 + 1:43 | 4 sub-dumps byte-identical |
| stage6 | PASS | 1:39 + 2:01 | 4 sub-dumps byte-identical (multicharge / consensus / reconciliation / rescored) |
| stage7 | **PASS** | 0:02 + 0:10 | --join-at-pass=2 entry; tight cycle |
| blib | **PASS** | 0:04 + 0:14 | --join-at-pass=2 entry; cs uses sidecar fallback |

Total full-march wall ≈ 9 minutes. Tight per-stage iteration
cycle when re-running a single failing stage with `-Side cs`:
**~10-30 seconds** for any post-Stage-4 stage.

**The pipeline now stands on its own end-to-end on Stellar 1-file.**
Both binaries produce byte-identical artifacts at every gated
stage. The diagnostic infrastructure carried this entire arc:
every divergence today (sidecar path, sidecar fallback,
freeze policy, env-var leak) was localized in one or two
iteration cycles thanks to the per-stage dump-and-exit env vars
and the now-fast `--join-at-pass=2` rehydration path.

### 2026-05-08 — Session 7 (Astral 1-file: ALL FIVE STAGES PASS)

Ran `Test-Regression -Dataset Astral` clean. Zero divergences.

| Stage | Status | rust + cs wall |
|---|---|---|
| stage1to4 | PASS | 2:35 + 3:01 |
| stage5 | PASS | 1:38 + 1:40 |
| stage6 | PASS | 3:22 + 3:54 |
| stage7 | PASS | 0:10 + 0:43 |
| blib | PASS | 0:27 + 0:52 |

Total full march ~18 min. The Stellar 1-file fixes ported
cleanly to the HRAM path — `--join-at-pass=2` rehydration,
sidecar paths, fallback semantics, the dedup port — all
correct on Astral too. No HRAM-specific drift surfaced.

Tight per-stage cycle on Astral: stage7 cs-only ~43s,
blib cs-only ~52s. Same iteration shape as Stellar.

**Next session handoff**: For detailed startup protocol (current
state, tight-cycle commands, per-stage entry-point map, build
commands, known acceptable drift, failing tests to ignore), read
`ai/.tmp/handoff-20260508_osprey_sharp_audit.md` before starting
work.

**Next session targets**:

1. ~~Astral 1-file march.~~ DONE.
2. **3-file Stellar / Astral**. Multi-file scenarios exercise
   cross-run reconciliation and the consensus + 2nd-pass
   sidecar write paths — the only places Rust takes a
   different code branch. The bit-parity claims previously
   "shipped" for these need re-verification under the now-
   honest test harness.
3. **`-Verbose` + `-TracePeptide` switches** on Test-Regression
   (still pending; modest convenience for next bisection
   sprint).
4. **CI integration** for Test-Regression. Per the original
   intent ("It should get run again and again ... possibly
   even become part of our CI"). Stellar 1-file is fast
   enough (~9 min full march) to gate every PR.

### 2026-05-09 — Session 8 (autonomous overnight)

User asked for unattended work: thorough perf testing,
dotTrace integration, fixes wherever tractable, checkpoint
commits as we go. Branch was already at the post-Session-7
state (all five 1-file stages GREEN on Stellar + Astral).

**Test-Regression `-Profile` (dotTrace integration) landed**
(`ai/scripts/OspreySharp/Test-Regression.ps1`). Models on
`ai/scripts/Skyline/Run-Tests.ps1` -PerformanceProfile
pattern. Wraps the cs side of any stage in
`dottrace start --profiling-type=Sampling --propagate-exit-
code`, writes per-stage `<workdir>/<stage>/cs/profile.dtp`,
generates an XML report via JetBrains Reporter.exe, and
prints top-N hotspots by both OWN and TOTAL time. Rust runs
unchanged (perf baseline, different tooling). New params:
`-Profile`, `-ProfilingType {Sampling|Timeline}`, `-ProfileTopN`.
Snapshot scope is constrained by the existing per-stage
exit env vars, so `-StartStage stage6 -StopAfterStage
stage6 -Side cs -Profile` produces a `.dtp` covering only
Stage 6 logic. Reporter.exe discovery prefers the
`dotTrace*` install dir under `%LOCALAPPDATA%\JetBrains\
Installations`; falls back to `ReSharperPlatform*`.

**First profiling result: Astral 1-file Stage 7 cs (with
profile, 57s wall)** showed a stark hotspot:

| Method | Total ms | Own ms |
|---|---|---|
| AnalysisPipeline.GenerateDecoys.<>b__0 | 46792 | 384 |
| AnalysisPipeline.BuildDecoyFromSequence | 45665 | 2990 |
| Scoring.DecoyGenerator.RecalculateFragments | 33250 | 7353 |
| Scoring.DecoyGenerator.CalculateFragmentMz | 22900 | 9401 |

Stage 7 / blib were 4-5x slower in cs vs rust (Session 7:
stage7 0:10 rust + 0:43 cs on Astral 1-file; blib 0:27 +
0:52). Both stages hit the same code path: full
`GenerateDecoys` from the library on every invocation,
even on `--join-at-pass=2` rehydration where decoy
LibraryEntries are NEVER consumed downstream.

**Audit of decoy-LibraryEntry use post-Stage-4 confirms
they are unused on `--join-at-pass=2`**:
- `BuildProteinParsimony` filters with
  `if (entry.IsDecoy) continue` (ProteinFdr.cs:160).
- `WriteBlibOutput` builds `passingEntries` with the same
  filter (AnalysisPipeline.cs:6509).
- `bestByPrecursor` and `libraryById.TryGetValue(entry_id)`
  only hit target entry_ids.
- Stage 5 (Percolator) and Stage 6 (rescore) are skipped
  on `ExpectReconciledInput` (AnalysisPipeline.cs:518 +
  Stage 6 short-circuit).

**Fix landed (AnalysisPipeline.cs:128-145)**: when
`config.ExpectReconciledInput`, GenerateDecoys is skipped
and `decoys` initialized to an empty list. Targets-only
library flows through to parsimony + blib write. Verified
correctness on Astral 1-file: stage7 PASS + blib PASS
(`-StartStage stage7 -StopAfterStage blib -Side cs`).

**Walls observed (concurrent with 3-file Stellar regression
running stage6, so noisy)**: stage7 cs 51s, blib cs 54s.
Pre-fix on the same Astral 1-file fixture: stage7 cs 43s,
blib cs 52s. Wall savings hidden under concurrent CPU
contention; clean re-measurement pending the regression
finishing. The 45-50s of CPU saved per stage is real
regardless (and the multi-file impact will be larger:
~46s × 3 files of decoys saved per Stage 7+blib pass).

**Test-Regression -Profile usage (for future sessions)**:

```
# Profile a specific stage on cs side using the existing
# fixture from a prior march:
pwsh -File ./Test-Regression.ps1 -Dataset Astral \
    -StartStage stage6 -StopAfterStage stage6 -Side cs -Profile

# Top hotspots print at the end of the cs run; full snapshot
# at <workdir>/stage6/cs/profile.dtp; XML report at
# <workdir>/stage6/cs/profile-report.xml.

# Default Sampling profile has ~5% overhead. Switch to
# Timeline (-ProfilingType Timeline) for thread / I/O
# analysis at higher overhead.
```

**3-file Stellar regression** (concurrent background job
during this session): stage1to4 PASS (1:28 rust + 1:05 cs),
stage5 PASS (2:11 rust + 2:09 cs). stage6 in progress at
end of this checkpoint.

**Next sub-targets in this session**:

1. Wait for 3-file Stellar to finish; diagnose anything
   FAIL.
2. Clean perf measurement of stage7 + blib post-fix to
   quantify the gain.
3. Profile Stage 6 cs (the next-most-likely hotspot — the
   ~5x gap on Astral 3-file rescore mentioned in the
   sprint Step 5).
4. 3-file Astral regression after Stellar completes.

### 2026-05-09 — Session 8.5 (3-file Stellar bug surfaced + closed)

**3-file Stellar full march on the night-time HEAD**:
stage1to4 + stage5 PASS byte-identical. Stage 6 sub-dumps
`multicharge`, `consensus`, `reconciliation` PASS byte-
identical. Stage 6 `rescored.tsv` FAIL: 1644 rows present
in rust, 0 in cs (rust 392825 rows; cs 391181 rows). Cs
faster than rust (3:08 vs 5:40) — under-rescoring, not
parallelism.

**Root cause: gap-fill never executed in the in-process
Stage 6 path.** The gap-fill planner (`GapFillTargetIdentifier
.Identify`) IS called inside `WriteReconciliationFiles` and
the per-file results land in `.reconciliation.json`. But the
in-process call to `ExecuteStage6Rescore` at
AnalysisPipeline.cs:1083 hard-coded `perFileGapFill: null`,
with the comment "Gap-fill two-pass + reconciled .scores
.parquet write-back are the next porting phases." That
"next phase" never landed before Test-Regression went
honest. Single-file runs produce 0 gap-fill plans (no inter-
replicate consensus possible), which masked the bug.

Multi-file impact (Stellar 3-file): rust gap-fills 1641 CWT
+ 3 forced = 1644 entries (560 + 528 + 556 per file —
matches the 1644-row delta exactly).

**Fix 1: Wired gap-fill through to in-process rescore**
(AnalysisPipeline.cs).
- `WriteReconciliationFiles` now exposes `gapFillByFileOut`
  via out param. The planner's `IReadOnlyDictionary<string,
  IReadOnlyList<GapFillTarget>>` result is converted to
  `Dictionary<string, List<GapFillTarget>>` (matches the
  `ExecuteStage6Rescore.perFileGapFill` parameter type used
  by both the in-process path and the worker).
- The Stage 6 rescore call at line 1083 now passes
  `perFileGapFillForRescore` instead of null.
- Stale comment "Gap-fill two-pass + reconciled .scores
  .parquet write-back are the next porting phases" deleted.

After this fix, `cs_stage6_rescored.tsv` ALMOST matched
rust's, but stage7 then failed with: "1st-pass sidecar
failed to load (magic / version / pass-byte / count / size
mismatch)". The sidecar loader's strict header-count check
was wrong for multi-file:

- 1st-pass sidecar is written PRE-gap-fill (Stage 5 boundary
  has no gap-fill stubs yet). Count = pre-gap-fill.
- Reconciled parquet is written POST-gap-fill (Stage 6
  appends gap-fill stubs at end of parquet). Count = pre-
  gap-fill + gap-fill.
- Sidecar loader required `headerCount == entries.Count`
  → fails when caller's stub list is the post-gap-fill
  parquet load.

**Fix 2: Sidecar loader now matches by entry_id**
(`FdrScoresSidecar.cs`).
- TryRead builds a `Dictionary<entry_id, index>` over the
  caller's entries and applies sidecar records by entry_id
  lookup, NOT by position.
- Caller may pass a SUPERSET (gap-fill stubs in entries
  with no sidecar record stay at their default Score=0,
  q=1 — exactly the post-gap-fill parquet entry case).
- Strict check preserved: every sidecar record MUST find
  its entry_id in the caller's entries. A stale or wrong-
  parquet sidecar (none of its records match) returns
  false. Detects corruption.
- Single-file degenerates to 1:1 dict lookup — no
  semantic change for the existing fast path.

**Tests updated** (`OspreySharp.Test/IOTest.cs`,
`ProgramTests.cs`):
- Removed `TestFdrScoresSidecarCountMismatchRejected` (the
  count-mismatch was the bug, not the contract). Replaced
  by `TestFdrScoresSidecarSupersetEntries` (gap-fill
  superset case) and `TestFdrScoresSidecarStaleRecordRejected`
  (truly unrelated sidecar still rejected).
- `TestNormalizeJoinAtPass2ErrorsUntilImplemented` was
  stale post-Session-5 (--join-at-pass=2 is now wired up).
  Replaced by `TestNormalizeJoinAtPass2InProcessSucceeds`
  (in-process should succeed) and
  `TestNormalizeJoinAtPass2NoJoinNotImplemented` (worker
  mode still errors).

**Stage 6 wall on 3-file Stellar with the fix**: cs 3:07
(unchanged). Gap-fill work is small relative to the rescore
loop, so wall is unaffected. Correctness restored at no
perf cost.

**Test status after the fixes**: 299 / 301 unit tests
PASS. Remaining 2 failures are the pre-existing CWT codec
stale-fixture tests documented in Session 1.

**Re-running 3-file Stellar march** to confirm
end-to-end on multi-file. Result will land in the next
session-8 entry below.

### 2026-05-09 — Session 8.6 (skip RunFirstPassProteinFdr on --join-at-pass=2)

The original Astral 1-file dotTrace already showed
`RunFirstPassProteinFdr` at 17s TOTAL on the Stage 7 cs
isolation. With `--join-at-pass=2` rehydration, the 1st-
pass FDR sidecar already carries `RunProteinQvalue` from
the original straight-through run. Re-running
`ComputeProteinFdr` on the same inputs produces the same
output (it's a deterministic graph algorithm) — the work
is just overwriting the loaded values with identical
numbers. **Skipping it on `ExpectReconciledInput`** saves
~17s of CPU on Astral 1-file Stage 7+blib (and similar on
multi-file scaled by entry count).

**Fix landed** (`AnalysisPipeline.cs:590-599`): the
guard `if (config.ProteinFdr.HasValue && perFileEntries
.Count > 0 && !config.ExpectReconciledInput)`. The sidecar
loaded earlier already provides `RunProteinQvalue`; no need
to recompute. The downstream compaction predicate (`run_
peptide_qvalue ≤ 0.01 OR run_protein_qvalue ≤ 0.01`)
reads `RunProteinQvalue` directly from the sidecar values
and works the same as if `RunFirstPassProteinFdr` had run.

**Validation**: end-to-end via the in-flight Stellar 3-
file regression. Stage 7 + blib must still produce byte-
identical TSV/blib vs Rust. If RunFirstPassProteinFdr's
output differs from the sidecar's stored RunProteinQvalue
(it shouldn't — but bisection seam is honest), the gates
will catch the divergence.

### 2026-05-09 — Session 8.7 (skip 1st-pass sidecar re-write on --join-at-pass=2)

dotTrace's third-largest hotspot on Astral 1-file Stage 7
cs was `WriteFdrScoresSidecars` at 6043ms. It re-writes
the per-file `.1st-pass.fdr_scores.bin` files using
entries seeded by the matching sidecar load earlier — i.e.,
the bytes are identical to what's already on disk. The
in-process pipeline writes pre-compaction so the worker
mode can re-derive post-compaction; for `--join-at-pass=2`,
the worker is the OWN process. Skipping the re-write
saves ~6s I/O per Stage 7 cs run on Astral 1-file (and
proportionally more on multi-file).

**Fix landed** (`AnalysisPipeline.cs:625-640`): the
sidecar write block is wrapped in `!config.ExpectReconciledInput`.

**Cumulative `--join-at-pass=2` perf wins this session**:

| Hotspot                       | Before | After  | Astral 1-file save |
|-------------------------------|--------|--------|--------------------|
| GenerateDecoys                | 46s    | 0s     | ~46s              |
| RunFirstPassProteinFdr        | 17s    | 0s     | ~17s              |
| WriteFdrScoresSidecars        | 6s     | 0s     | ~6s               |
| **Total wall savings**        |        |        | **~70s** out of ~57s* |

*The 57s pre-fix wall included dotTrace overhead. Pre-fix
clean wall was 43s. So post-fix expected wall ≈ 4-8s
(the irreducible: library load, parquet load, RunProteinFdr,
parsimony, blib early exit). Vs Rust's 10s on Astral 1-file
Stage 7. Gap effectively closed.

### 2026-05-09 — Session 8.8 (3-file Stellar regression FULL PASS — rust sidecar bug + port)

End-to-end run with cs's gap-fill + sidecar fixes surfaced
ANOTHER cross-impl bug: `cs_stage7_protein_fdr.tsv`
diverged from `rust_stage7_protein_fdr.tsv` (cs 6533 protein
groups vs rust 6311). Drilled with the per-side stage7
stdout logs and found the root cause:

**Rust `load_fdr_scores_sidecar` had the SAME strict
`header_count == entries.len()` guard cs's TryRead used to
have**, written at `crates/osprey/src/pipeline.rs:1392`.
On multi-file `--join-at-pass=2`, the reconciled parquet
has gap-fill rows the 1st-pass sidecar (written pre-gap-
fill) doesn't have, so rust's loader silently rejected
both sidecars and fell through to RE-TRAINING Percolator
from scratch on the wrong input set (post-rescore parquet,
not the post-compaction subset the original 2nd-pass
scored). Walls confirmed the issue: rust stage7 took 1:11
on this run vs cs stage7 0:09 (cs loaded sidecars
successfully and skipped Percolator). The rust pipeline
then computed Stage 7 protein FDR from re-trained scores
that DIVERGED from the original straight-through pipeline.

**Cs is correct here; rust was buggy.** The cs side
already had the fix (the entry_id-keyed loader from
Session 8.5). Ported the same algorithm to rust:

- `crates/osprey/src/pipeline.rs:1391-1435`: replace the
  strict count check with a `HashMap<u32, usize>` lookup
  on `entries` so records overlay matching entry_ids
  regardless of ordering or count. Caller may pass a
  SUPERSET; sidecar records with no matching entry_id
  STILL produce `false` (so a stale or wrong-parquet
  sidecar still surfaces).
- Tests: `fdr_scores_sidecar_count_mismatch_rejected`
  replaced by `fdr_scores_sidecar_superset_entries_accepted`
  + `fdr_scores_sidecar_stale_record_rejected`.
- Branch: `feature/sidecar-entry-id-keyed-loader` in
  `C:\proj\osprey`. Maintainer-PR ready (no
  Co-Authored-By per the rust commit convention; descriptive
  body with the multi-file context).
- `cargo fmt --check`, `cargo clippy -D warnings`, and
  `cargo test` all green.

**Re-running stage7 + blib with the new rust binary +
post-fix cs binary**: ALL FIVE STAGES NOW PASS on Stellar
3-file end-to-end.

| Stage      | Rust wall | C# wall  | Status |
|------------|-----------|----------|--------|
| stage1to4  | 1:26      | 1:03     | PASS   |
| stage5     | 1:49      | 1:59     | PASS   |
| stage6     | 3:18      | 3:06     | PASS   |
| stage7     | **0:04**  | **0:10** | PASS   |
| blib       | **0:08**  | **0:15** | PASS   |

Stage 7 + blib walls dropped dramatically vs the broken
rust path (rust stage7 1:11 → 0:04, ~17x faster). The
test-regression harness was unintentionally measuring
how slow rust's degraded path was.

**Bit-parity verification status (Stellar 3-file)**:
every stage is byte-identical or within 1e-6 PIN
tolerance. The bit-parity end-to-end claim that
Session 8 entry 1 challenged is restored, on a now-
honest test harness that exercises gap-fill,
reconciliation actions, and `--join-at-pass=2`
rehydration through real multi-file behavior.

**Next sub-target this session**: 3-file Astral
regression. The HRAM path may surface different
behavior (more entries, more gap-fill targets, larger
parquets). Same diagnostic + iteration toolkit applies.
