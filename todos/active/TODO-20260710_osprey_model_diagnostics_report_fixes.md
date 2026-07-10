# TODO-20260710_osprey_model_diagnostics_report_fixes.md -- Fix two --model-diagnostics report bugs and add the cross-run reproducibility graphs

## Status
**Active (2026-07-10).** Branch `Skyline/work/20260710_osprey_model_diagnostics_report_fixes`
off master `babcebdb6e`. Reporting-only change (off the production FDR path; the golden
regression output is unaffected). Implements the cross-run graphs specced in the backlog
sibling [[TODO-osprey_model_diagnostics_cross_run_detection_consistency]] and fixes the two
report bugs found alongside it on the 2026-07-09 SEA-AD run
([[project_sead_pilot_mtg_dataset]], [[project_osprey_entrapment_ratio_fdr_collapse]]).

## What this delivers (one PR)
1. **Bug A -- Identification-yield chart didn't switch scope.** `IdYieldData` now carries
   `Q[]` + `TargetsExperiment[]` + `TargetsRun[]` (both precursor-q scopes over one grid);
   the yield card gets its own experiment-wide / per-run selector that re-renders. Verified:
   the per-run curve reaches ~120K vs ~80K experiment-wide on the SEA-AD 10-file decoy run.
2. **Bug B -- FDR tab (and the yield inside it) was hidden without entrapment.** The yield
   card + the two new graphs moved to a new always-present **Reproducibility** tab
   (`data-tab="repro"`, registered in the `TABS` array with no entrapment guard). The
   entrapment FDP card stays in the still-gated `fdr` tab. Verified: the no-entrapment decoy
   run now shows the Reproducibility tab (previously the yield was entirely absent).
3. **Two cross-run graphs** (entrapment-free FDR QC), built unconditionally from the reported
   per-file passing precursors into a new `CrossRunDetection` data class:
   - "Precursor detections by run" -- per-run bars + cumulative union + cumulative
     intersection + at-least-half reference line.
   - "Precursors by number of runs detected" -- histogram (J/U shape; growing k=1 bump = FDR
     trouble).

## Files
- `pwiz_tools/Osprey/Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs` -- per-scope
  `IdYieldData`, new `CrossRunDetection` + `BuildCrossRunDetection`, wired into `Build()`
  (survives the FirstJoin->MergeNode sidecar round-trip as public properties).
- `pwiz_tools/Osprey/Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html` -- new
  `repro` tab section + TABS entry; yield redrawn with a scope selector; two new chart blocks.
- `pwiz_tools/Osprey/Osprey.Test/ModelDiagnosticsDataTest.cs` -- `TestIdYieldPerScope`,
  `TestCrossRunDetection` (+ `EntryQ` / `WrapFiles` helpers).

## Verification
- Pre-commit gate green: Debug build, 480 tests pass (incl. the two new), zero inspection
  warnings in the three touched files (the 11 reported are pre-existing SystemMemory.cs #4379
  / PerFileScoringTask.cs #4381, untouched here).
- Headless-Chrome screenshots of the regenerated SEA-AD decoy report confirm Bug A, Bug B, and
  both graphs render with no JS error.

## Remaining
- Confirm the entrapment (r=0.1) report shows the FDR tab AND the Reproducibility tab together.
- Push, open PR, self-review, trigger the Osprey Windows .NET Perf/Regression on `pull/<N>`.
