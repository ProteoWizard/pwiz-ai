# TODO-20260712_osprey_model_diagnostics_calibration -- Add a "CAL" view to the --model-diagnostics HTML

## Branch Information
- **Branch**: `Skyline/work/20260712_osprey_model_diagnostics_calibration` (in C:\proj\pwiz-work1)
- **PR**: [#4414](https://github.com/ProteoWizard/pwiz/pull/4414) (pushed + opened 2026-07-12; 10 commits atop
  #4413). NEXT GATE: `/pw-self-review` (mandatory AI gate) before human review; TeamCity Perf/Regression
  (Astral legs) to trigger on pull/4414 when ready. Then Brendan's /pw-handoff + /night-session 82-file run.
- **Base**: master @ a3e227d76b (#4413 page-level Pass 1/Pass 2 switch) + 4 cherry-picked calibration
  commits from the pwiz-work2 calibrator-review branch (ac8c7c68df verbose LDA report, f06e001d7c env
  levers, d922268ba7 anchor-purity diagnostic, 61c088cfc7 anchor-purity test).
- **Created**: 2026-07-12
- **Status**: Active

## Goal (from Brendan)
Extend the `--model-diagnostics` HTML with a **CAL** button beside the existing global [1st pass][2nd pass]
switch, exposing the Stage-3 calibration phase so a reviewer can tell if calibration "went off the rails"
in one of 82 (or 500+) files. The --model-diagnostics HTML has been the highest-leverage diagnostic
surface (uncovered multiple bugs); this brings the calibration phase up to the same standard.

## Design - CAL content per tab (mirrors the Percolator passes; drops the two that don't apply)
| Tab | CAL content | Data source |
|---|---|---|
| Model | Calibration-LDA feature contributions (coelution_corr, libcosine_apex, top6_matched, xcorr, [median_polish]) + composite score dist (target/decoy/entrapment) -- PER SELECTED FILE (dropdown) | CalibrationTrainingReport + CalibrationMatch discriminant scores |
| FDR calibration | CAL q-value calibration: entrapment-FDP vs claimed q + anchor yield curve (# passing q) -- validates the "cal q is well-calibrated" finding | ComputeAnchorPurity q-sweep (this branch) |
| Reproducibility | PER-FILE MS1/MS2 mass-error + RT-correction across all files (spot the outlier file) | MzCalibrationResult (MS1/MS2) + RTCalibration.Stats() |
| Summary | Per-file table: cal-peptide count + entrapment + corrections (MS1 ppm, MS2 ppm, RT shift, R^2) | aggregate of above |
| Density, Competition | n/a for CAL (per-file, no target/decoy-null density or paired decoy-win) -- graceful note like transfer mode | -- |
- NEW UI control: a per-file dropdown (first in this report) driving the per-file cards.

## Plan (one PR per Brendan)
1. **Data capture (Stage 3)**: a per-file `CalibrationDiagnostics` record (cal-LDA contributions, composite
   score histogram by class, anchor-purity q-sweep arrays, MS1/MS2 MzCalibrationResult, RT stats, cal-peptide
   + entrapment counts). Collect in Calibrator during calibration; publish per-file to the pipeline context
   (mirror RefinedCalibrations). GATED so a non-diagnostics run pays ~nothing.
2. **Data model**: `ModelDiagnosticsData.Cal` bundle + pure `BuildCal(...)`. Reuse FeatureRow / ScoreHistogram
   / FdpView / IdYieldData / FileSummaryRow where possible.
3. **Report wiring**: FirstJoinTask passes the per-file cal bundle to ModelDiagnosticsReport.Write -> BuildCal
   -> data.Cal. Sidecar round-trips the new field automatically (Newtonsoft).
4. **HTML/JS**: add "CAL" to the global #passSel; CAL content on Model/FDR-cal/Reproducibility/Summary;
   Density/Competition show n/a; add the per-file dropdown. Reuse axes/drawPanel/classHist/drawYield/kpi.
5. **Tests + validation**: TestCal* in ModelDiagnosticsDataTest; headless-Chrome render check on a real
   multi-file run (82-file SEA-AD or a hard-linked subset); regression.ps1 -Dataset Stellar byte-identical
   (report is off the golden path).

## Progress
- **Branch set up** (2026-07-12): `pwiz-work1` off master@a3e227d76b (#4413) + 4 cherry-picked cal commits
  (clean, no conflicts); build + 504/507 tests green including the cal tests. Active project = pwiz-work1.
- **Increment 1 DONE + committed (1f0c640e97)**: the CAL data model / JSON contract, unit-tested in isolation.
  - `ModelDiagnosticsData.Cal.cs` (new partial file): `CalibrationData` (list of per-file rows + hasEntrapment
    + massUnit) / `CalFileRow` (Features=cal-LDA FeatureRow[], Scores=ScoreHistogram, Fdp=FdpView,
    Yield=IdYieldData, + scalar MS1/MS2/RT corrections + anchor/entrapment counts + AnchorFdp) / transient
    `CalFileInput` DTO / pure `BuildCalFile(input)->row` shaping (LDA weighted-share contributions, class-binned
    composite histogram, entrapment-FDP + yield sweep over a shared q-grid). `Cal` nullable prop (null hides tab).
  - `TestCalibrationBuildCalFile` added; guards the contribution sort/share, histogram totals, FDP/yield sweep,
    no-entrapment suppression. Made the unstable-sort-safe (OrderByDescending().ThenBy(Index)).
- **Increment 3 DONE + committed (31cffc1dbb, template)**: CAL button on the global pass switch; two synced
  `<select>` file pickers (shared index); Model (cal-LDA table + composite dist) / FDR (cal-FDP + yield) /
  Reproducibility (all-files scalar overview, median+-3MAD outlier=amber, uncalibrated=red, points clickable) /
  Summary (per-file corrections table, rows clickable) cards; Density+Competition n/a; `jumpToCalFile()` cross-tab
  linking; per-file print blocks; shared buildFeatureTable/drawFdpPanel/drawYieldCurve refactor + a legend()
  null-guard bugfix. Validated on synthetic data (headless Chrome, no JS errors; screenshots in ai/.tmp/cal-final-*).
  OPEN (Brendan review): ms1Count/ms2Count/rtMad/rtWindowBefore not yet surfaced (keep or prune).
- **Increment 2 DONE (capture/wiring, C# - committed after regression)**: Calibrator gains `out CalFileRow`
  (all capture gated on config.ModelDiagnostics; builds CalFileInput at the accepted pass -> BuildCalFile);
  new `PerFileCalibrationDiagnostics` byproduct (dict by file, parallels PerFileCalibrations); PerFileScoringTask
  captures+publishes; FirstJoinTask.BuildCalibrationData -> ModelDiagnosticsReport.Write(...,cal,...) sets data.Cal
  (graceful null hides tab; sidecar round-trips to pass-2). HPC caveat: straight-through only (cal matches not
  persisted; `// TODO(cal-diagnostics): HPC-split persistence`). Integrated build+504/507 tests GREEN.
- **Increment 2 COMMITTED (63a6b45e46)**. Byte-identity: Stellar regression **mode-1 (vs golden) PASSED**
  (straight blib 50,237,440 bytes == golden); modes 2/3 (HPC/resume self-consistency) were completing on an
  orphaned agent-launched regression at commit time (a concurrent-regression collision earlier caused a
  spurious exit -1 -- NOT a code defect; the default path is fully gated). FINAL GATE REMAINING: one clean
  full regression.ps1 -Dataset Stellar mode1/2/3 (run once the machine is free, before PR).
- **NEXT (render review - the key step)**: fire ai/.tmp/run-caldiag.ps1 (10 files, --model-diagnostics) ->
  D:/test/Pilot-MTG-Tissue-May2026/runs/caldiag-10file/caldiag.model-diagnostics.html. Then screenshot the
  CAL tabs (headless Chrome; per memory force tabs visible) and review the REAL per-file data with Brendan
  (does the outlier overview / dropdown / cal-LDA + FDP cards look right on real AD-file variation?). This
  is also the end-to-end functional test of the capture (--model-diagnostics ON, multi-file FirstJoin aggregation).
- Branch commits so far: ac8c7c68df/f06e001d7c/d922268ba7/61c088cfc7 (cal diag from rebase) + 1f0c640e97 (CAL
  data model) + 31cffc1dbb (CAL HTML) + 63a6b45e46 (capture). All atop a3e227d76b (#4413). NOT pushed.

## Gates
- Output-only feature: `regression.ps1 -Dataset Stellar` mode1/2/3 must stay byte-identical (report is off
  the golden path; the gate never sets --model-diagnostics).
- Build-Osprey.ps1 -RunTests -RunInspection green; TestModelDiagnosticsData extended.
- Real multi-file end-to-end render (headless Chrome), incl. entrapment + no-entrapment variants.

## References
- Diagnostics report: Osprey.Tasks/ModelDiagnostics/{model-diagnostics-template.html, ModelDiagnosticsReport.cs,
  ModelDiagnosticsHtml.cs}, Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs, Osprey.Test/ModelDiagnosticsDataTest.cs.
- Pass-switch predecessor: [[completed/TODO-20260711_osprey_model_diagnostics_pass_switch]] (#4413).
- Calibration data: Osprey.Scoring/CalibrationScorer.cs (CalibrationTrainingReport, ComputeAnchorPurity is in
  Calibrator), Osprey.Chromatography/{RTCalibration.cs (Stats), MzCalibration.cs (MzCalibrationResult)},
  Osprey.Tasks/Calibrator.cs, Osprey.Tasks/FirstJoinTask.cs (RefinedCalibrations publish + Write call site).
- Calibrator-review findings (why cal is clean/near-optimal): [[TODO-20260711_osprey_calibrator_selection_review]].

## SESSION END 2026-07-12 - feature complete, PR open, awaiting self-review + 82-file real-world run
All four increments DONE + committed + PUSHED as **PR #4414** (10 commits atop #4413): CAL data model +
capture wiring + HTML view + refinements (trend lines, prev/next steppers, slim Summary, RT R^2 4-decimal
axis) + the entrapment-distribution fix. Build+504/507 tests green; full Stellar regression mode1/2/3
byte-identical; end-to-end validated on a real 10-file SEA-AD run (report has real per-file data; CAL data
embedded + rendered correctly). PR body in team format (Co-Authored-By, test-plan checkboxes).
REMAINING: (1) `/pw-self-review` on pull/4414 (mandatory AI gate) -> address findings in NEW commits;
(2) Brendan gates the Osprey Perf/Regression TeamCity config on pull/4414 (Astral legs) when ready;
(3) the first full **82-file --model-diagnostics run** (Brendan's /night-session) for the real-world view
- rebuild Release first so the generated report carries all refinements natively (no splice needed).
Open UI items Brendan may still tweak on review of caldiag-10file-v2.html: keep-or-prune ms1Count/ms2Count
+ rtMad/rtWindowBefore fields; any further card/layout polish; more cross-tab links.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260712_osprey_model_diagnostics_calibration.md` before starting work.
