# TODO: OspreySharp fast subset-data pipeline test (per-commit coverage)

**Status**: Backlog (not started)
**Priority**: Medium-High -- would give the per-commit build most of the pipeline
coverage in seconds, instead of only via the hours-long overnight regression.
**Type**: Test infrastructure / coverage
**Source**: 2026-06-10 discussion with Brendan while the full cumulative-coverage
run executed. Unit coverage is ~45%; the cumulative (unit + regression) number is
much higher (full `-Dataset All` run pending) -- the gap is the pipeline chain,
which unit tests never run. Idea: a radically subset, committed dataset (the
Skyline DDA/DIA-search trick) that runs the full pipeline fast as a per-commit
test.

## Goal

A **fast, committed, subset-data integration test** that runs the OspreySharp
pipeline end-to-end (`PerFileScoring -> FirstJoin/Percolator -> PerFileRescore ->
MergeNode -> blib`) on tiny inputs, lifting per-commit coverage from ~45% toward
the cumulative number, and catching a broken pipeline in seconds. It
**complements**, not replaces, the overnight real-data regression (which stays
the scientific-validity gate).

## Why unit tests stall at ~45%

Unit tests exercise the *components* (calibration math, FDR/SVM math, IO
roundtrips, arg validation) but never run the orchestration *chain* on real
spectra. The only way to cover the pipeline stages is to actually run them on
some data -- so a (small) end-to-end run is required, not more unit tests.

## Precedent

Skyline `pwiz_tools/Skyline/TestFunctional/DiaSearchTest.cs` runs a *functional*
(fast, committed) test on `collinsb_I180316_001_SW-A-subset.mzML` (+ a B file) in
`TestFunctional/DiaSearchTest.zip` -- msconvert-subset SWATH data, multi-file.
That is the model: subset with msconvert, commit, run fast. (Matt built the DDA/
DIA search functional tests this way.)

## OspreySharp-specific catch (the key design point)

Unlike the Skyline mzML-only trick, for OspreySharp the **mzML is not the main
cost -- the spectral library + Percolator are.** In the baseline run, Percolator
FDR alone was ~400s of the ~7.5 min straight-through, and the coelution +
calibration scoring before it are next; all three scale with
**(library entries x matching spectra)**, and the library is 242,841 entries
(485,674 with decoys). So:

- **Subset the library too**, not just the mzML. The library is already a
  committable `.tsv`. Keep only peptides that elute in the kept mzML window, plus
  enough to let FDR run.
- **Coordinate** the mzML subset and library subset so the kept peptides still
  match the kept spectra (else zero results).
- **The floor is Percolator, not the blib.** It trains an SVM across 3
  target/decoy folds; too small and it degenerates / yields zero results, which
  *skips* downstream stages and *reduces* coverage. The minimum is "small enough
  to be fast + committable, big enough that Percolator runs and >=1 precursor
  reaches the blib." Finding that floor is the experiment.

## Approach (to refine)

1. msconvert a narrow slice of one Stellar (unit-resolution) file -- e.g. a 2-3
   min RT window and/or a handful of isolation windows (`--filter "scanTime ..."`
   / `"scanNumber ..."` / `"mzWindow ..."` / `"isolationWindow ..."`).
2. Subset the `.tsv` library to the peptides eluting in that window (+ keep enough
   for decoys/FDR to train).
3. Binary-search the size down until Percolator still produces a non-empty,
   structurally-valid `output.blib`. That's the floor.
4. Commit the subset(s) (small enough; see open questions) and add an
   `OspreySharp.Test` integration test that runs the pipeline and asserts a
   non-empty, well-formed blib (RefSpectra/RetentionTimes present, sane counts).
5. Repeat with an **Astral-style hram** subset and **2-3 files** to also cover the
   hram paths (`HramStrategy`, `Ms1ScoringByproduct`, MS1/isotope code that sat at
   0% on Stellar-single) and the multi-file reconciliation path.
6. Measure the coverage the subset test actually delivers
   (`Measure-CumulativeCoverage.ps1` with only the subset legs) vs the full run,
   to see how close a fast test gets.

## What it will NOT cover (keep complementary)

- **Format/mode paths** -- `ElibLoader` (0%) only runs for `.elib` input; some
  scorers are mode-specific. Smaller data doesn't help; they need dedicated
  inputs/modes (separate tests).
- **Data-volume branches** -- cross-file consensus, gap-fill, large-data
  heuristics.
- **Scientific validity** -- a handful of peptides doesn't prove the search is
  useful on real data. The overnight real-data regression remains that gate.

## Open questions

1. **Where the committed data lives** -- an `OspreySharp.Test` `TestData/`
   folder, or a committed zip like `DiaSearchTest.zip`. And the size budget that
   is comfortable to commit (target a few MB, not tens).
2. **mzML vs mz5** -- mzML is text (diff-reviewable) but bigger; mz5/mzMLb is
   smaller binary. Does OspreySharp read anything but mzML today? (It reads mzML
   via `MzmlReader`; raw/mz5 are future.) Probably commit mzML for now.
3. **Per-commit wiring** -- the integration test should run in the per-commit
   `OspreySharp.Test` suite (`build.ps1 -RunTests`/`-Coverage`) to get the
   coverage + breakage win. Confirm runtime stays seconds, not minutes.
4. **Floor experiment** -- how small can the library + mzML get before Percolator
   stops training? Capture the minimum.

## Value

Two complementary gates: a **fast per-commit** subset test (pipeline code-paths +
"did it break", seconds) and the **overnight real-data** regression (validity).
The per-commit build stops being blind to pipeline breakage between nightlies.

## Dependencies / sequencing

- Use the cumulative-coverage baseline (`Measure-CumulativeCoverage.ps1
  -Dataset All -Files All`, in progress under
  `TODO-20260610_ospreysharp_cumulative_coverage.md`) as the target to compare
  the subset test's coverage against.
- Derive the subsets from the existing regression data
  (`<Downloads>\Perftests\osprey-testfiles-mzML`).
