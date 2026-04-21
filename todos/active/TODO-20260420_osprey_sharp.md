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

- **Branch**: `Skyline/work/20260420_osprey_sharp` (created off `master`
  after PR #4155 merges)
- **Base**: `master`
- **Working directory**: `C:\proj\pwiz\pwiz_tools\OspreySharp\`
- **Created**: 2026-04-20
- **Status**: Planning (work begins after PR #4155 merges)
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
- `C:\proj\pwiz` — OspreySharp C#, branch `Skyline/work/20260420_osprey_sharp`
  (off `master` post-#4155 merge)
- `C:\proj\osprey-mm` — upstream `maccoss/osprey:main` baseline
- `C:\proj\osprey` — our Rust fork; post-merge of PRs #9-#12 it's
  essentially mothballed. Check for any fork-only changes before starting
  Step 1.

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

(Starts on first session against this TODO, after PR #4155 merges.)
