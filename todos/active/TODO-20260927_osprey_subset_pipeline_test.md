# Osprey: fast committed subset-data pipeline test for per-commit coverage

## Branch Information
- **Branch**: `Skyline/work/20260927_osprey_subset_pipeline_test`
- **Base**: `Skyline/work/20260612_net8_port` (PR goes `--base` the port branch; update via `git merge origin/Skyline/work/20260612_net8_port`)
- **Checkout**: `C:\proj\pwiz-work1` (all Build-*/Run-* calls need `-SourceRoot C:/proj/pwiz-work1`)
- **Created**: 2026-09-27
- **Status**: In Progress
- **GitHub Issue**: [#4360](https://github.com/ProteoWizard/pwiz/issues/4360)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

A fast, committed, subset-data integration test that runs the OspreySharp pipeline
end-to-end (`PerFileScoring -> FirstJoin/Percolator -> PerFileRescore -> MergeNode -> blib`)
on tiny inputs in seconds, lifting per-commit coverage (unit-only ~50.9%) toward the
cumulative number (unit + Stellar 3-file + single Astral = 77.1% as of 2026-06-21).
It complements, not replaces, the overnight real-data regression, which stays the
scientific-validity gate.

Key design point: the mzML is not the main cost - the spectral library and Percolator
are. Subset the library `.tsv` together with the mzML so kept peptides still match kept
spectra. The floor is Percolator: too small and it degenerates to zero results, which
skips downstream stages and reduces coverage.

## Tasks

- [ ] msconvert a narrow slice of one Stellar file (2-3 min RT window and/or a few isolation windows)
- [ ] Subset the `.tsv` library to peptides eluting in that window (+ enough for decoys/FDR)
- [ ] Binary-search the size down until Percolator still yields a non-empty, structurally valid `output.blib` (the floor)
- [ ] Commit the subset(s) (target a few MB); add an `OspreySharp.Test` integration test asserting a non-empty, well-formed blib (RefSpectra/RetentionTimes present, sane counts)
- [ ] Wire into the per-commit `-RunTests` suite; confirm runtime stays seconds
- [ ] Repeat with an Astral-style HRAM subset + 2-3 files (`HramStrategy`, `Ms1ScoringByproduct`, MS1/isotope, multi-file reconciliation)
- [ ] Measure delivered coverage vs the full run

## Not Covered (stays with overnight regression)

Format-specific loaders, mode-specific scorers, data-volume branches (cross-file
consensus, gap-fill), and scientific validity.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: OspreySharp.Test
- **Fails on master**: n/a - this issue adds new coverage rather than fixing a defect;
  the test itself is the deliverable
- **Passes on fix**: (pending)

## Progress Log

### 2026-09-27 - Session Start

Starting work on this issue. Branched in pwiz-work1 off the .NET 10 port branch
(`Skyline/work/20260612_net8_port`, PR #4619) at `1e3f83da34` so the test targets
the ported code.
