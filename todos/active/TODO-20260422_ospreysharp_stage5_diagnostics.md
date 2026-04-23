# OspreySharp Stage 5 diagnostics + cross-impl parity

> Companion to **TODO-20260420_osprey_sharp.md** (now scoped to
> Stages 6-8). This TODO captures the Stage 5 diagnostic
> infrastructure + the three Rust-side fixes + the one C# sync that
> together establish Stage 5 cross-impl bit-parity on single-file
> Stellar. Moves to `ai/todos/completed/` when the five PRs below
> merge.

## Branch Information

Five PRs, one per logical change, all open:

| Repo | Branch | PR | Purpose |
|---|---|---|---|
| pwiz | `Skyline/work/20260422_ospreysharp_stage5_diagnostics` | [#4160](https://github.com/ProteoWizard/pwiz/pull/4160) | OspreySharp C# Stage 5 dumps |
| pwiz | `Skyline/work/20260422_ospreysharp_stage5_sync` | [#4159](https://github.com/ProteoWizard/pwiz/pull/4159) | VERSION + C grid sync with maccoss/osprey v26.4 |
| osprey | `feat/stage5-diagnostics` | [#18](https://github.com/maccoss/osprey/pull/18) | Rust Stage 5 dumps |
| osprey | `fix/pep-nondeterminism` | [#16](https://github.com/maccoss/osprey/pull/16) | Self-parity fix (sort + serial KDE) |
| osprey | `fix/grid-search-crossimpl-parity` | [#17](https://github.com/maccoss/osprey/pull/17) | Cross-parity fix (tie-break + count formula) |

- **Base**: `master` (pwiz) / `main` (maccoss/osprey)
- **Created**: 2026-04-22
- **Status**: In review (Copilot round addressed 2026-04-22; CI green
  on all five; awaiting Mike's (Rust) + Nick's (pwiz) review)
- **GitHub Issue**: (none — tool work, no Skyline integration yet)

## Objective

Two coordinated deliverables:

1. **Stage 5 cross-impl bit-parity** on single-file Stellar, via the
   `--join-only` path against a canonical Rust-generated Parquet.
   All 6 numeric columns of the end-of-Stage-5 dump (`score`, `pep`,
   `run_precursor_q`, `run_peptide_q`, `experiment_precursor_q`,
   `experiment_peptide_q`) bit-match across Rust osprey and
   OspreySharp across 462,802 FdrEntry rows. Both tools: **34,158
   precursors at 1 % FDR / 30,712 peptides / 5,471 protein groups**
   on Stellar file 20.

2. **Stage 5 diagnostic harness** that made the bisection tractable
   and stays as the regression gate for Stages 6-8 forward walk.
   Four env-var-gated dumps per side (standardizer, subsample +
   fold, SVM weights, end-of-Stage-5 Percolator) plus a new
   `Compare-Percolator.ps1` hash-joined comparison script.

## What landed

### Diagnostics (PR #18 + #4160)

Four new env-var-gated dumps at Stage 5 checkpoints, each with a
matching C# mirror:

| Dump | Env var | Rust file | C# file |
|---|---|---|---|
| Standardizer | `OSPREY_DUMP_STANDARDIZER` / `_STANDARDIZER_ONLY` | `rust_stage5_standardizer.tsv` | `cs_stage5_standardizer.tsv` |
| Subsample + fold | `OSPREY_DUMP_SUBSAMPLE` / `_SUBSAMPLE_ONLY` | `rust_stage5_subsample.tsv` | `cs_stage5_subsample.tsv` |
| SVM weights per fold | `OSPREY_DUMP_SVM_WEIGHTS` / `_SVM_WEIGHTS_ONLY` | `rust_stage5_svm_weights.tsv` | `cs_stage5_svm_weights.tsv` |
| End-of-Stage-5 Percolator | `OSPREY_DUMP_PERCOLATOR` / `_PERCOLATOR_ONLY` | `rust_stage5_percolator.tsv` | `cs_stage5_percolator.tsv` |

Two dumps (train-trace + grid-search per-C) were built during the
bisection, proved invaluable for isolating `count_passing_targets_svm`
as the root cause, then **cut from the PR** as too-invasive for
long-term maintenance. Reimplementable in ~1-2 hr when next needed;
pattern captured in `ai/docs/osprey-development-guide.md`.

A shared `osprey_core::diagnostics::format_f64_roundtrip` normalizes
`-0.0` to `"0"` and gives stable textual forms for `NaN` / `inf` so
diagnostic dumps diff cleanly cross-runtime.

New harness script: `ai/scripts/OspreySharp/Compare-Percolator.ps1`
— hash-joins on `(file_name, entry_id)` composite key, sort-order-
agnostic, per-column numeric tolerance. Complements the existing
`Compare-Diagnostic.ps1` (row-wise diff for Stages 1-4).

### Self-parity fix (PR #16)

Two sources of run-to-run PEP drift in Stage 5, both fixed:

- `compute_fdr_from_stubs` iterated `targets` HashMap in
  Rust-randomized order, leaking iteration order into
  `PepEstimator::fit_default`. Fixed by sorting the union of
  base_ids first.
- `Kde::pdf` used `par_iter().fold().sum()`; Rayon's work-stealing
  reduction is non-deterministic. Converted to serial
  `iter().fold()`. Perf impact negligible.

After both: Rust Stage 5 dump byte-identical across consecutive
runs (SHA-256 `b68ffa6c`); OspreySharp was already deterministic.

### Cross-parity fix (PR #17)

Two small but load-bearing Rust fixes in the Percolator grid-search
path:

- `grid_search_c` tie-break: code used `Iterator::max_by_key`
  (returns last-tied per stdlib); comment said "first C as
  tiebreaker". Replaced with manual scan using strict `>`; matches
  OspreySharp's `GridSearchC` which already did first-tied.
- `count_passing_targets_svm`: used conservative `(n_decoy+1)/n_target`
  inline; sibling `compute_qvalues` on the same iteration path used
  non-conservative `n_decoy/n_target`. OspreySharp is internally
  consistent (both non-conservative). Rewrote to non-conservative
  with backward monotonicity pass — aligns Rust internally AND
  matches OspreySharp, no parity-switch debt.

### Upstream alignment (PR #4159)

Two small ports from maccoss/osprey v26.4 head into OspreySharp:

- `Program.VERSION` 26.3.0 → 26.4.0. Parquet footer validator
  requires matching `major.minor` for cross-impl `--join-only`.
- `PercolatorConfig.CValues` adds `0.001` to match upstream's
  6-value C grid. Zero behavior change on Stellar (grid search
  doesn't select 0.001 under current settings).

## Test-Features.ps1 enhancements

Picked up along the way, already in PR #4160's diagnostic work:

- `-CsharpRoot` param with auto-detection across `pwiz-work1` /
  `pwiz` / `pwiz-work2` worktrees. Replaces the obsolete
  `-RustTree Fork/Upstream` split.
- Rotates per-tool scores Parquet to distinct
  `.rust.parquet` / `.cs.parquet` suffixes so the C# run doesn't
  clobber the Rust output (enables cross-impl smoke tests on the
  same input).
- Passes `--parquet-compression snappy` to the Rust `--no-join`
  invocation (Parquet.Net 3.x only reads Snappy). Canonical Rust
  Stellar Parquet lives at
  `D:\test\osprey-runs\stage5\stellar\rust_scores.parquet`.

## Completion

Ready to move to `ai/todos/completed/` when all five PRs above
merge. At that point:

- Update `pwiz_tools/OspreySharp/Osprey-workflow.html` if any
  further Stage 5 progress (multi-file evidence) has landed; the
  2026-04-22 update already marked Stage 5 single-file as done.
- Next-session work continues in **TODO-20260420_osprey_sharp.md**,
  scoped to Stages 6-8.

## Copilot review round (2026-04-22)

Brief notes for posterity — all addressed, comments resolved:

- **PR #14** (LDA): warning names missing class + single-pass count.
- **PR #15** (Gauss): `left_solved` rejects NaN; zero-row on left
  requires zero-row on right; two regression tests.
- **PR #16** (PEP): determinism regression test + grammar typo.
  Initial permutation-invariance test was too strict; simplified to
  same-input-twice determinism (which is what the fix guarantees).
- **PR #17** (grid_search): first-C-tie-wins regression test.
  Skipped the empty-`c_values` guard suggestion — pre-existing
  behavior, not a regression of this PR.
- **PR #18** (diagnostics): `-0.0` normalization in the shared
  formatter; hermetic test via `tempfile::tempdir`; SVM-weights +
  standardizer dumps routed through the shared formatter. CI also
  caught `clippy::items-after-test-module` — test modules must be
  the last item in their file.

## Reference

- Full pre-split history, bisection log, and diagnostic-decision
  audit: the 2026-04-21 and 2026-04-22 progress entries in the prior
  single-file `TODO-20260420_osprey_sharp.md` (now trimmed to
  Stages 6-8).
- Debugging doctrine (classical "find a switch that toggles
  broken vs non-broken, then audit for minimality"): applied here to
  convert a 240-LOC parity switch into a 20-LOC fix. Documented in
  `ai/docs/osprey-development-guide.md` "Steel-thread parity
  doctrine".
