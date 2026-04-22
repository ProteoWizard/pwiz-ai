# TODO-20260420_osprey_sharp.md — Phase 4: Stages 5-8 parity walk

> **Pipeline diagram**:
> [`pwiz_tools/OspreySharp/Osprey-workflow.html`](../../../pwiz/pwiz_tools/OspreySharp/Osprey-workflow.html)
> — open this first for the canonical stage definitions, current "you are
> here" marker, and per-stage parity/performance evidence. Every "Stage N"
> reference in this TODO refers to the stages in that diagram.
>
> **Terminology note**: "Phase N" in TODO filenames refers to development
> sprints (phase1/phase2/phase3 TODOs covered Stages 1-4; this TODO is the
> Phase 4 sprint and covers pipeline Stages 5-8). "Stage N" always refers
> to a pipeline stage in the workflow diagram.

## Branch Information

- **Branch**: `Skyline/work/20260420_osprey_sharp` (created 2026-04-21 off
  `master` at `f1db9f63`, the merge commit for PR #4155)
- **Base**: `master`
- **Working directory**: `C:\proj\pwiz-work1\pwiz_tools\OspreySharp\`
  (pwiz/ is occupied by `Skyline/work/20260421_osprey_gauss_solver`)
- **Created**: 2026-04-20
- **Status**: In Progress (started 2026-04-21)
- **GitHub Issue**: (none — isolated tool work, no Skyline integration yet)
- **PR**: (pending)

## Phase History

Phases 1-3 brought pipeline Stages 1-4 (library loading, mzML parsing,
calibration, peak scoring / main search) to bit-identical 21 PIN feature
parity on Stellar and Astral vs `maccoss/osprey:main`, plus net472+net8.0
multi-targeting and the `--no-join` / `--join-only` / `--input-scores` HPC
split. Full session-by-session history in:

- `TODO-20260409_osprey_sharp-phase1.md` — Sessions 1-7
- `TODO-20260409_osprey_sharp-phase2.md` — Sessions 8-11
- `TODO-20260409_osprey_sharp.md` — Sessions 12-19

(Moved to `ai/todos/completed/` on 2026-04-21 after PR #4155 merged.)

Phase 1-3 shipped as pwiz PR #4155 (purely additive; TeamCity-excluded via
`explicit` Jamfile targets).

## Objective

Extend cross-implementation parity from pipeline Stage 4 (peak scoring)
through Stage 8 (BiblioSpecLite .blib output). The pipeline stages being
walked (see the workflow diagram linked at the top of this file):

| Stage | Name | Scope |
|-------|------|-------|
| 5 | First-pass FDR (Percolator SVM) | best-per-precursor subsampling, iterative non-negative SVM with 3-fold stratified CV by peptide, C grid search, Granholm 2012 cross-fold calibration, TDC q-values at precursor + peptide × run + experiment, FDR compaction |
| 6 | Refinement | multi-charge consensus, cross-run RT reconciliation, second-pass re-score at locked boundaries, re-trained Percolator SVM |
| 7 | Protein FDR | parsimony, subset elimination, razor assignment, picked-protein TDC on best peptide scores |
| 8 | Output | BiblioSpecLite .blib (RefSpectra, RetentionTimes, Modifications, Proteins, Osprey fragment tables) |

Mike continued Stages 5-8 work in `maccoss/osprey:main` during the
OspreySharp Phase 1-3 sprint, so OspreySharp is now out of sync with
upstream for the algorithms we're about to walk. Phase 4 begins by
resynchronizing, then walks forward stage by stage with the same Phase 1-3
bisection-to-ULP discipline.

## Strategy — five steps

### Step 1: Upstream resync review

Catalog every change to `maccoss/osprey:main` since the last OspreySharp
alignment point (Session 19's `7f7fcbf` reference, or later depending on
Mike's merges of PRs #9-#12). Classify each upstream commit:

- **Parity-critical** — touches algorithms present in `PercolatorFdr.cs`,
  `ProteinFdr.cs`, `BlibWriter.cs`, or Stages 5-8 plumbing. First-pass
  port into OspreySharp, one commit per logical upstream change.
- **Stages 1-4 drift** — any upstream algorithmic change that could break
  our existing Stage 1-4 parity. Port immediately, re-run `Test-Features.
  ps1` on both datasets, confirm 21/21 holds.
- **Out of scope** — Rust-internal refactors with no algorithmic impact
  (skip; note in the review dump).

Produce a written review dump under `ai/.tmp/stage5_upstream_delta.md`
listing every upstream commit in scope with disposition. No new forward-walk
work starts until the review dump is complete.

### Step 2: `--no-join` Parquet score-file capture (4 cases)

Run both Rust and OspreySharp with `--no-join` on each:

| Dataset | File | Resolution | Rust output | C# output |
|---------|------|------------|-------------|-----------|
| Stellar | single (file 20) | unit | `stellar_rust_scores.parquet` | `stellar_cs_scores.parquet` |
| Astral  | single (file 49) | hram | `astral_rust_scores.parquet`  | `astral_cs_scores.parquet`  |

Score files are Snappy-compressed Parquet. Validate bit-level score parity
between Rust and C# for each dataset (reuses the Phase 3 parity
infrastructure, gated at the Parquet boundary instead of the PIN boundary).

Rust Parquets become the canonical cross-impl input for Step 3.

### Step 3: Stages 5-8 single-file walk from stored Rust Parquets

Using `--join-only --input-scores <rust.parquet>`, walk both tools forward
stage by stage with identical input Parquet. Establish bit-level parity at
each stage boundary — same bisection cadence as Phase 1-3:

1. **Stage 5 first-pass FDR**: per-iteration SVM weights, per-fold state,
   precursor q-values, peptide q-values (run + experiment).
2. **Stage 6 refinement**: consensus leader picks, RT boundary reconciliation
   snapshots, re-scored features, re-trained SVM state.
3. **Stage 7 protein FDR**: parsimony graph, razor assignments, protein-
   level TDC q-values.
4. **Stage 8 output**: .blib row-level comparison (RefSpectra, RetentionTimes,
   Modifications, Proteins, Osprey fragment tables) between Rust-written
   and C#-written .blib for the same input.

Diagnostic-dump env vars follow the Phase 3 pattern (`OSPREY_DUMP_*` +
`OSPREY_*_ONLY=1` early exits per stage).

### Step 4: Multi-file Stages 5-8 walk

Repeat Step 3 with 3-file Parquet inputs on both datasets. Exercises
best-per-precursor subsampling across files, cross-run RT reconciliation,
experiment-level FDR compaction, and multi-file protein parsimony.

### Step 5: End-to-end pipeline parity

Drop `--input-scores` and run both tools end-to-end (no Parquet boundary)
on single-file and 3-file. Confirms the full pipeline is wire-compatible
and that the Parquet hand-off didn't hide a Stage 4 → Stage 5 join-side
bug.

## Tasks

### Priority 1: Upstream resync (Step 1)

- [ ] Catalog `maccoss/osprey:main` commits since Session 19 baseline;
      disposition each to `ai/.tmp/stage5_upstream_delta.md`.
- [ ] Port parity-critical Stages 5-8 algorithms into OspreySharp
      (`PercolatorFdr.cs`, `ProteinFdr.cs`, `BlibWriter.cs` and adjacent
      pieces), one commit per logical upstream change.
- [ ] Port any Stages 1-4 drift; re-run `Test-Features.ps1 -Dataset Stellar`
      and `-Dataset Astral`; confirm 21/21 @ 1e-6 still holds.

### Priority 2: `--no-join` Parquet capture (Step 2)

- [ ] Capture Rust single-file Stellar `*.scores.parquet` with `--no-join`.
- [ ] Capture Rust single-file Astral `*.scores.parquet` with `--no-join`.
- [ ] Capture C# single-file Stellar `*.scores.parquet` with `--no-join`.
- [ ] Capture C# single-file Astral `*.scores.parquet` with `--no-join`.
- [ ] Validate Stellar Rust vs C# Parquet bit-level parity.
- [ ] Validate Astral Rust vs C# Parquet bit-level parity.
- [ ] Store canonical Rust Parquets under
      `D:\test\osprey-runs\stage5\{stellar,astral}\rust_scores.parquet`.

### Priority 3: Single-file Stages 5-8 walk (Step 3)

- [ ] Stage 5 SVM training parity (Stellar Rust-scores input).
- [ ] Stage 5 SVM training parity (Astral Rust-scores input).
- [ ] Stage 5 q-value parity (precursor + peptide, run + experiment).
- [ ] Stage 6 multi-charge consensus parity.
- [ ] Stage 6 cross-run RT reconciliation parity.
- [ ] Stage 6 second-pass SVM parity.
- [ ] Stage 7 protein FDR parity.
- [ ] Stage 8 .blib row-level parity.

### Priority 4: Multi-file Stages 5-8 walk (Step 4)

- [ ] Capture 3-file Rust Parquets (Stellar + Astral).
- [ ] Multi-file Stage 5 parity (best-per-precursor across files).
- [ ] Multi-file Stage 6 cross-run reconciliation parity.
- [ ] Multi-file Stage 7 protein FDR parity.
- [ ] Multi-file Stage 8 .blib parity.

### Priority 5: End-to-end pipeline parity (Step 5)

- [ ] Single-file end-to-end Stellar + Astral (no Parquet boundary).
- [ ] 3-file end-to-end Stellar + Astral.
- [ ] Update `Osprey-workflow.html` footer: new status, "you are here"
      marker off Stage 5, final evidence numbers.

## Quick Reference — must-know commands and locations

**Parity tests (carried from Phase 3)**:
```bash
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Stellar
pwsh -File './ai/scripts/OspreySharp/Test-Features.ps1' -Dataset Astral
```

**HPC split flags (added in Phase 3, commit `51f2ec21e` in PR #4155)**:
- `--no-join` — run through Stage 4, write `*.scores.parquet`, exit
- `--join-only --input-scores <path>` — resume from an external Parquet

**Repos**:
- `C:\proj\pwiz-work1` — OspreySharp C#, branch
  `Skyline/work/20260420_osprey_sharp` (off `master` at `f1db9f63`, the
  PR #4155 merge commit). pwiz/ is occupied by `osprey_gauss_solver`.
- `C:\proj\osprey` — upstream `maccoss/osprey:main` baseline (the current
  canonical Rust we test against).
- `C:\proj\osprey-fork` — our legacy `brendanx67/osprey` fork; mothballed
  post-merge of PRs #9-#12. Check for any fork-only changes before
  starting Step 1 (per memory: fork is being retired).

**Test data**: `D:\test\osprey-runs\{stellar,astral}\` (same as Phase 1-3).

## Critical reminders

1. **PR #4155 must merge first.** New branch bases off master including the
   OspreySharp drop; don't start Phase 4 commits until #4155 lands.
2. **Don't break Stages 1-4 parity.** Every upstream port must re-run
   `Test-Features.ps1` on both datasets; 21/21 @ 1e-6 is the locked baseline.
3. **First-pass port is not good enough.** If a Stage 5-8 port doesn't
   produce bit-identical output against Rust, that's a parity-gate failure
   and must be root-caused before moving forward (Phase 1-3 bisection-to-ULP
   discipline applies stage-by-stage here too).
4. **Parquet boundary is load-bearing.** Step 3 onwards assumes Rust scores
   are the canonical input. If Step 2 can't establish bit-level score parity
   on both datasets, Step 3 can't start — fix Step 2 first.
5. **Cross-impl changes go to BOTH tools the same session** (carried from
   Phase 3). Any scoring-affecting change (bin config, dedup, rounding,
   filtering) applied in C# needs the matching change in Rust — otherwise
   parity walks diverge.

## Progress Log

### 2026-04-21 — Session 1: Phase 4 kickoff

- PR #4155 merged at 2026-04-21T15:58 UTC (merge commit `f1db9f63`),
  dropping OspreySharp onto pwiz master. Phase 4 unblocked.
- Branch `Skyline/work/20260420_osprey_sharp` created off `f1db9f63` in
  `C:\proj\pwiz-work1` (pwiz/ worktree is on an unrelated
  `osprey_gauss_solver` branch, so Phase 4 is running out of pwiz-work1).
- No GitHub issue for this work — tracked via this TODO only.
- Surveyed upstream `maccoss/osprey:main` delta since Session 19's
  `7f7fcbf`: head is `bd15572` (v26.4.0). ~40 commits. Parity-critical
  candidates include `06905be` (protein FDR always-on), `f03f162` /
  `778460e` (reconciliation changes), `3551668` / `0cc5731` (classical
  LOESS), `2db5f1c` (RT penalty sigma 3x→5x), `91ec0e5` (sparse XCorr +
  pooled scratch), `4d0119d` (CWT intensity tiebreaker), `885339b`
  (peak-boundary truncation fix). Flags infrastructure (`f91c41f`,
  `623093c`, `b5b0860`, `a8c39ac`, `1a2eeb3`) must work end-to-end for
  Step 2. (`osprey-fork` ignored per decision 2026-04-21.)

- **Strategy pivot** (user decision 2026-04-21): do not pre-catalog
  upstream drift. Go straight to `--no-join` Parquet parity (Step 2) and
  then the Stage-5 walk (Goal 1). When parity fails, port the upstream
  commit(s) responsible and keep a running disposition log in
  `ai/.tmp/stage5_upstream_delta.md`. Rationale: drift is expected given
  the gap between OspreySharp's initial Rust alignment and its Stage 1-4
  bit-parity completion; the cheapest way to surface it is to run the
  parity tests.
- Next: investigate existing Phase 3 `--no-join` infrastructure and
  build the two parity tests.

### 2026-04-21 — Session 1 progress

**Step 2 done** (both datasets: Stellar validated; Astral deferred until
Stage 5 diagnostics land per user direction).

- `Test-Features.ps1` edits: dropped obsolete `-RustTree Fork/Upstream`
  split (upstream = `osprey-mm` no longer exists), added `-CsharpRoot`
  with auto-detection across `pwiz-work1` / `pwiz` / `pwiz-work2`, added
  `--parquet-compression snappy` to the Rust `--no-join` invocation (C#
  defaults to Snappy via Parquet.Net 3.x), and rotated each tool's
  `{stem}.scores.parquet` to a distinct `.rust.parquet` / `.cs.parquet`
  suffix so the C# run doesn't overwrite Rust's output (blocks Step 3.5).
- Rebuild required: `pwiz-work1` needed `dotnet restore OspreySharp.sln`
  before MSBuild could resolve `project.assets.json`. Build wrapper
  doesn't do this today — possible future enhancement.
- `Program.VERSION` bumped `26.3.0` → `26.4.0` to match `maccoss/osprey`
  head; otherwise the cross-impl Parquet validator aborts on minor
  mismatch per HPC Phase 3 / Phase 6 contract. Touches parquet footer
  metadata + blib osprey_version tag only.
- Stellar PIN parity: **21/21 passing** at 1e-6 (xcorr/sg_weighted_xcorr
  at 1e-5), 317,842 matched entries, Rust 24.6 s / C# 28.4 s.
- Canonical Rust Stellar Parquet seeded at
  `D:\test\osprey-runs\stage5\stellar\rust_scores.parquet` (315 MB,
  Snappy, dict-disabled).

**Step 3.5 smoke tests** — both tools can consume the canonical Rust
Parquet via `--join-only`:

| Run | Time | Precursors @ 1% FDR | Protein groups |
|---|---|---|---|
| Rust self-consume | 1 m 5 s | 34,349 | 5,471 |
| C# from Rust Parquet (cross-impl) | 2 m 17 s | 33,160 | 5,445 |

The 1,189-precursor delta (3.4 %) is Stage 5 drift — exactly what Goal 1
will attack. Confirms the Snappy cross-impl interop contract holds and
that the divergence is algorithmic, not a Parquet-format issue.

Lesson: `library_identity_hash` includes `lib_path.display()`, so a
path argument formatted as `/d/test/...` (Bash-style) hashes differently
from `D:\test\...` (Windows-style). Invoke join-only smoke tests via
`pwsh` with Windows-native absolute paths to match what Test-Features.ps1
used when producing the Parquet. (Same canonical-path hazard applies to
any cross-machine Parquet handoff — a separate concern.)

### 2026-04-21 — Goal 1 design: Stage 5 diagnostic dump

Full design in `ai/.tmp/stage5_dump_design.md`.

Summary: new `OSPREY_DUMP_PERCOLATOR=1` / `OSPREY_PERCOLATOR_ONLY=1` env
vars (consistent with existing `OSPREY_*_ONLY` Phase 1-3 pattern). Dumps
a TSV with 11 columns at end-of-Stage-5 (after first-pass
`run_percolator_fdr` returns, before first-pass protein FDR + compaction).
Columns: `file_name, entry_id, charge, modified_sequence, is_decoy,
score, pep, run_precursor_q, run_peptide_q, experiment_precursor_q,
experiment_peptide_q`. Join key `(file_name, entry_id)`. Compared via
new `Compare-Percolator.ps1` that hash-joins on the composite key
(Compare-Diagnostic does row-wise diff, which bit us in Phase 1-3 — per
user).

Insertion points:
- Rust: `pipeline.rs` after `run_percolator_fdr(...)` (~line 2986)
  and `log_fdr_qvalues(...)` (~line 3011), before the first-pass
  protein-FDR block (~line 3025) and compaction (~line 3079).
- C#: `AnalysisPipeline.cs` after the `RunPercolatorFdr(...)` call
  (line 3997), before the C# equivalent of protein FDR.

Initial dump covers the coarsest Stage 5 summary. If it doesn't match,
which specific column diverges first (score vs q-values) tells us
whether SVM training or TDC q-value computation is the culprit;
finer-grained dumps (per-fold SVM weights, stratified fold assignment,
per-iteration residuals) added only when the first comparison demands.

### 2026-04-21 — Goal 1 implementation landed

**Rust dump** — `diagnostics::dump_stage5_percolator` writes
`rust_stage5_percolator.tsv` with 11 columns sorted by `(file_name,
entry_id)`. Insertion point: `pipeline.rs` after `run_percolator_fdr(...)`
returns and the first-pass FDR log, before first-pass protein FDR and
compaction. Gated by `OSPREY_DUMP_PERCOLATOR=1` /
`OSPREY_PERCOLATOR_ONLY=1`. 2 new unit tests.

**Rust determinism fixes** (found during self-parity validation — two
non-determinism leaks into PEP values):

1. `percolator.rs::compute_fdr_from_stubs` — previously iterated the
   `targets` / `decoys` `HashMap` in Rust's randomized iteration order
   when building `winner_scores` for the PEP fitter. Fixed by
   constructing a union of base_ids from both maps, sorting, then
   iterating in sorted order.
2. `osprey-ml/src/pep.rs::Kde::pdf` — used
   `par_iter().fold().sum()` for the KDE sum; Rayon's work-stealing
   reduction tree is non-deterministic, so float non-associativity made
   PEP values drift by ~1 ULP run-to-run. Converted to serial
   `iter().fold()`. Perf impact negligible (~0.5 s over the whole
   ~1 min Percolator pass; PEP fit called once per Stage 5).

After both fixes Rust Stage 5 dump is **byte-identical** across
consecutive runs (SHA-256 `b68ffa6c...`). 34,349 precursors @ 1% FDR
unchanged — no behavior regression.

**C# dump** — `OspreyDiagnostics.WriteStage5PercolatorDump` writes
`cs_stage5_percolator.tsv` with the same 11-column schema. G17 float
format (17-digit roundtrippable, avoids .NET Framework's historical R
format bugs). Call site in `AnalysisPipeline.cs` after the Percolator
FDR log, before reconciliation/protein-FDR. C# was **already
self-parity deterministic** — PepEstimator has no Parallel.For, and
`CompeteFromIndices` already sorts winners by `(score desc, base_id
asc)` before handing them to the PEP fitter. SHA-256 `c506089e...`
identical across consecutive runs, first try. 33,160 precursors @ 1 %
FDR (unchanged).

**Cross-impl compare** — new `ai/scripts/OspreySharp/Compare-Percolator.ps1`
hash-joins on `(file_name, entry_id)` (sort-order-agnostic, unlike
`Compare-Diagnostic.ps1`). Reports per-column max-abs-diff and
divergent-row count. Threshold 1e-9 on all 6 numeric columns.

**First cross-tool diff result**:

| Metric | Value |
|---|---|
| Common keys | 462,802 / 462,802 (row sets match exactly) |
| score divergence | **100 %** of rows, max_diff = 8.33 |
| pep divergence | 52 % of rows, max_diff = 0.98 |
| run_precursor_q divergence | 53 %, max_diff = 0.996 |
| run_peptide_q divergence | 63 %, max_diff = 0.996 |
| experiment_precursor_q | 53 %, max_diff = 0.996 |
| experiment_peptide_q | 63 %, max_diff = 0.996 |

Every SVM score differs → Stage 5 SVM produces materially different
classifiers on the two sides. q-values cascade from that.

**Config-default audit** landed one drift port:
- Rust C grid: `[0.001, 0.01, 0.1, 1.0, 10.0, 100.0]` (6 values)
- C# C grid was: `[0.01, 0.1, 1.0, 10.0, 100.0]` (5 values)
- Ported the `0.001` into `PercolatorFdr.cs:79`. Verified: **zero
  impact** on the dump — the grid search doesn't select `C=0.001` for
  any fold on Stellar. Red herring for this divergence but kept (real
  drift, correct to match upstream).

All other `PercolatorConfig` defaults match exactly
(`train_fdr=test_fdr=0.01`, `max_iterations=10`, `n_folds=3`, `seed=42`,
`max_train_size=300000`).

**Next session — sub-Stage-5 bisection dump**:

Candidate: a `stage5_subsample_folds.tsv` dump with columns
`(file_name, entry_id, in_subsample, fold_id)` before SVM training
begins. Hash-joined compare finds the earliest cascading divergence:

- If subsample membership differs, the two tools train on different
  ~300 K subsets — port whichever selection algorithm is upstream.
- If subsample matches but fold assignment differs, the
  3-fold-stratified-by-peptide assignment has diverged — port.
- If both match, the divergence is inside the iterative SVM itself
  (weights per fold, convergence, C grid selection with identical
  inputs). Next dump after that: per-fold final weights (22 floats per
  fold × 3 folds).

Estimated ~150 LOC: new env vars + dump fn in both tools + extending
Compare-Percolator.ps1 to handle the second TSV.

### 2026-04-21 — Session-end commits pushed

All Stage-5-end diagnostic work pushed to remote branches. Feature
branches in each repo are ready to become PRs once cross-impl parity
lands:

- **osprey** `feat/stage5-percolator-dump` @ `cb42a2d` — two commits:
  - `286d225` Fixed PEP non-determinism in first-pass FDR
  - `cb42a2d` Added Stage 5 Percolator diagnostic dump
- **pwiz** `Skyline/work/20260420_osprey_sharp` @ `1b7918d2e` —
  two commits on top of PR #4155 merge:
  - `2aaf83449` Synced OspreySharp with maccoss/osprey head (VERSION + C grid)
  - `1b7918d2e` Added Stage 5 Percolator diagnostic dump
- **pwiz-ai** `master` @ `e82d569` — two commits:
  - `c589e2a` Prepared Test-Features.ps1 for cross-tool Parquet parity
  - `e82d569` Added Compare-Percolator.ps1 for cross-impl Stage 5 diff

Pre-commit gates all green (OspreySharp 214/214 tests + inspection
clean, Rust fmt+clippy clean, workspace tests pass).

### 2026-04-21 — Next dump design: subsample + fold assignment

Direct algorithm inspection of `subsample_by_peptide_group` /
`SubsampleByPeptideGroup` (percolator.rs:1439 / PercolatorFdr.cs:1449)
and `create_stratified_folds_by_peptide` /
`CreateStratifiedFoldsByPeptide` (percolator.rs:1381 /
PercolatorFdr.cs:1344) confirmed both algorithms are **line-for-line
identical** — same HashMap→sorted-Vec→Fisher-Yates-with-xorshift64
pattern, same Ordinal string sort, same round-robin fold assignment.

So if input arrays (labels, peptides, entry_ids) are in identical
order on both sides, outputs MUST match. If the cross-tool diff
reveals subsample or fold drift, it's upstream — the two tools
populate the per-precursor arrays in different orders. That, too, is
diagnosable.

Design for the next dump:

- `OSPREY_DUMP_SUBSAMPLE=1` + `OSPREY_SUBSAMPLE_ONLY=1` (mirror the
  existing `OSPREY_*_ONLY` convention)
- Files: `rust_stage5_subsample.tsv` / `cs_stage5_subsample.tsv`
- Columns: `entry_id, native_position, charge, modified_sequence,
  is_decoy, base_id, in_subsample, fold_id`
  - `native_position`: the entry's index in the best-per-precursor
    array — catches input-order drift
  - `in_subsample`: bool; `fold_id`: 0/1/2 if in subsample, -1 if not
- Sort by `entry_id` (stable numeric order, independent of input
  ordering)
- Insertion: after `fold_assignments` returned, before SVM training
  starts (percolator.rs ~line 244, AnalysisPipeline.cs ~line 303)

Compare-Percolator.ps1 will be extended (or a sibling
Compare-Subsample.ps1 added) to diff the new TSV on
`(file_name, entry_id)` hash-join, with separate checks for:
(a) native_position mismatches (→ input-order drift),
(b) in_subsample mismatches (→ subsample selection drift),
(c) fold_id mismatches on common subsampled entries (→ fold-assignment
drift).

Next session start: implement the dump in both tools, smoke-test
self-parity on Stellar, run cross-tool compare, then either (if
subsample/fold match) drill into SVM training internals (per-fold
initial state, per-iteration weights), or (if they mismatch) port the
upstream ordering and re-test end-of-Stage-5 dump.
