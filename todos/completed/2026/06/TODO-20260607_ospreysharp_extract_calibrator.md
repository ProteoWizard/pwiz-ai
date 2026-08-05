# TODO-20260607_ospreysharp_extract_calibrator.md

## Branch Information
- **Branch**: `Skyline/work/20260607_ospreysharp_extract_calibrator`
- **Base**: `master`
- **Created**: 2026-06-07
- **Status**: Completed
- **PR**: [#4276](https://github.com/ProteoWizard/pwiz/pull/4276) (merged 2026-06-07)

**Priority**: Medium — largest single readability win, lowest risk of the three;
good first step before the scoring decomposition
**Type**: Architecture / separation of concerns
**Source**: OOP review of `pwiz_tools/OspreySharp` (2026-06-06), Separation-of-
concerns lens + Top Recommendation #1

## Progress log
- 2026-06-07: Branch created off master (`c10858d971`, pre-#4275). Chose to base
  off current master rather than wait for diagnostics PR #4275 or stack on it:
  calibrator work guts `PerFileScoringTask.cs`, which #4275 never touched, and
  #4275 shipped diagnostics as a static facade (`OspreyDiagnostics.X` call sites
  unchanged), so the relocated calibration code keeps calling the facade and
  resolves correctly before or after #4275 merges. Overlap surface is tiny.

- 2026-06-07: Extraction landed. Created `Tasks/Calibrator.cs` (internal sealed,
  `pwiz.OspreySharp.Tasks`, ctor takes `PipelineContext`); moved the 5 constants,
  `CalibrationPassResult`, and all 12 calibration methods (incl. the omitted
  `ScoreCalibrationMatches`) out of `PerFileScoringTask` via scripted byte-exact
  slicing. PerFileScoringTask 2828 -> 1558 LOC; Calibrator 1330 LOC. Promoted
  `ExtractTopNFragmentXics`, `FindNearestMs1`, `CountTop6Matches` to
  `internal static` on AbstractScoringTask (all pure; `CountTop6Matches` was the
  one dependency the initial map missed, caught by the build); call site uses
  `new Calibrator(_ctx).RunCalibration(...)`. **Verified byte-identical**: moved
  method bodies (1237 lines), constants, and CalibrationPassResult all diff-clean
  vs HEAD after reversing the qualifier edits. Green: build net8.0+net472, 372
  tests, ReSharper 0 warnings. Parity (`-Files All -SkipRust`, net8.0 vs cached
  Rust): **Stellar PASS** (precursors delta=0; Stage7 + blib content 1e-9) and
  **Astral PASS** (precursors 167285=167285, delta=0; Stage7 + blib content 1e-9).
  (blib byte-size deltas are pre-existing SQLite page padding, not content.)
  Fresh-context self-review: clean, no findings -- confirmed 33 OspreyDiagnostics
  calls in identical order, no method overrides (static promotion safe),
  InternalsVisibleTo keeps test access to the promoted internals, no hidden state,
  no dead code. Ready to commit + open PR.
- 2026-06-07: PR #4276 opened. Copilot review: one comment (unused `resolution`
  local at Calibrator.cs:913, a pre-existing dead read carried over verbatim).
  Removed it (commit f0347da78c) -- side-effect-free, parity-neutral; Debug gate
  re-run green (372 tests, 0 warnings). Replied + resolved the thread. Side note:
  Copilot claimed it would trigger a ReSharper warning; it does NOT under our
  shared DotSettings -- verified by running -RunInspection (52s, 0 warnings) WITH
  the local present. The unused-local-variable inspection is disabled in the
  Skyline DotSettings that OspreySharp inherits, so the -RunInspection gate will
  not catch dead locals.

### 2026-06-07 - Merged

PR #4276 merged as commit 6774740f (squash) on 2026-06-07. Shipped the calibration
extraction in full: the RT/mass calibration cluster (12 methods, CalibrationPassResult,
5 constants) now lives in `Tasks/Calibrator.cs` (standalone, PipelineContext ctor);
PerFileScoringTask dropped 2828 -> 1558 LOC; the 3 shared helpers were promoted to
internal static and the 2 shared statics left on AbstractScoringTask. Verified pure
relocation (byte-identical bodies; Stellar + Astral cross-impl parity PASS at 1e-9;
372 tests; 0 warnings). Both open design questions resolved in-code (Calibrator stays
in the exe; shared scorer/constant stay on AbstractScoringTask). Copilot's one comment
(a pre-existing dead local) was removed and the thread resolved. No scope deferred;
no follow-up issues filed. Unblocks `TODO-ospreysharp_modular_scoring_context.md`.

## Problem

`OspreySharp/Tasks/PerFileScoringTask.cs` (2,828 LOC) owns at least four distinct
concerns in one class:

- library + decoy loading — `LoadLibraryAndDecoys` (`:592`)
- **RT/mass calibration** — roughly `:1581–2782` (~1,200 LOC, ~40% of the file)
- per-file scoring orchestration — `ProcessFile` (`:1152`), `ScoreOrLoadForFile`
  (`:1016`)
- parquet/sidecar I/O and feature dumps — `WriteFeatureDump` (`:1453`),
  `TryLoadStubsAndCalibration` (`:1081`)

Calibration is a self-contained subsystem with its own private result type
(`CalibrationPassResult`, `:80`) and has no reason to live inside the scoring task.
The methods that move together:

- `RunCalibration` (`:1581`)
- `RunCalibrationScoringPass` (`:1825`)
- `PreprocessWindowsForXcorr` (`:2012`)
- `CollectCalibrationPoints` (`:2100`)
- `AggregateMassCalibrations` (`:2157`)
- `SampleLibraryForCalibration` (`:2207`)
- `ScoreCalibrationEntry` (`:2377`, ~300 LOC)
- `ScorePeaksByCorrelation` (`:2677`)
- `CollectMs2FragmentErrors` (`:2720`)
- `ComputeMs1MassError` (`:2782`)
- the `CalibrationPassResult` private type (`:80`)

## Desired design

Move the cluster into a `Calibrator` collaborator (in `OspreySharp` or
`OspreySharp.Chromatography` — see open question) that `PerFileScoringTask`
constructs and calls. The task is left as clean orchestration:
**load → calibrate → score → persist**.

- `Calibrator` owns the calibration passes and returns an `RTCalibration` +
  mass-calibration result; `CalibrationPassResult` becomes its internal type.
- It takes its inputs (sampled library entries, spectra, config, tolerances) and
  an injected diagnostics sink (see `TODO-ospreysharp_diagnostics_di.md`) rather
  than reaching for statics or `_ctx`.
- `PerFileScoringTask` drops from 2,828 LOC toward ~1,600 LOC of readable
  orchestration; calibration becomes **independently testable**, which it is not
  today.

## Constraints (osprey)

- This is a **pure relocation** — byte-for-byte identical calibration output
  required. Calibration feeds RT prediction, which feeds scoring, so a drift here
  cascades into the feature vectors.
- Gate: the C#-side refactor regression on Stellar + Astral (expect exact for a
  clean move) -- the multi-file straight-through run reusing the cached Rust
  reference: `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust`, plus the
  pre-commit `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`.
  (Cached Rust reference must match the `-Files` set; no `-Force` with `-SkipRust`.)
- Preserve the calibration diagnostic-dump call order exactly (the Stage-cal dumps
  are bisection seams); the dumps move with the code.
- net8.0 canonical for parity. Do not loosen a gate to land it.
- Skyline conventions apply (no async/await, resource strings, `_camelCase`
  privates, CRLF, helpers after public methods).

## Open design questions

- Home for `Calibrator`: keep in the `OspreySharp` exe alongside the task, or
  promote to `OspreySharp.Chromatography` (which already houses `RTCalibration`,
  `MzCalibration`, `LoessRegression`, `CalibrationParams`)? Promotion gives a
  cleaner module boundary but widens what `Chromatography` must reference — check
  the dependency direction stays a DAG.
- Does the `s_calXcorrScorer` / `CAL_TOP_N_FRAGMENTS` calibration config
  (currently `internal` on `AbstractScoringTask`, `:67`/`:132`) move onto
  `Calibrator` too? Likely yes — it is calibration-only state.

## Relationship to sibling TODOs

- Do this **before** `TODO-ospreysharp_modular_scoring_context.md`: it shrinks the
  biggest file and removes a whole concern, making the (riskier) scoring
  decomposition easier to reason about.
- Pairs with `TODO-ospreysharp_diagnostics_di.md`: the extracted `Calibrator`
  should receive an injected diagnostics sink rather than calling the static class.

## Design decisions (resolved 2026-06-07, from code analysis)

Both open questions above are answerable from the code; resolved as follows.

- **Home for `Calibrator`: keep in the OspreySharp exe**, namespace
  `pwiz.OspreySharp.Tasks`, new file `Tasks/Calibrator.cs`. NOT promoted to
  `OspreySharp.Chromatography`. The cluster depends on `pwiz.OspreySharp.Scoring`
  (CalibrationMatch, CalibrationScorer, ScoringContext, SpectralScorer,
  ScoringMath, FragmentMath) *and* `Chromatography` (RTCalibration, MzCalibration,
  MzCalibrationResult, LoessRegression). Promotion would force a
  `Chromatography -> Scoring` reference and break the dependency DAG. Calibrator
  sits above both layers, so it belongs in the exe.
- **`s_calXcorrScorer` / `CAL_TOP_N_FRAGMENTS` do NOT move onto `Calibrator`.**
  `CAL_TOP_N_FRAGMENTS` is also used by dedup scoring in `AbstractScoringTask`
  (:1753/:1755), and `s_calXcorrScorer` is pinned by name in
  `CalibrationTest.cs:544`. Both stay `internal static` on `AbstractScoringTask`;
  the same-assembly `Calibrator` references them qualified
  (`AbstractScoringTask.s_calXcorrScorer`, `AbstractScoringTask.CAL_TOP_N_FRAGMENTS`).
- **`Calibrator` does not inherit `AbstractScoringTask`** — it is a standalone
  collaborator. Constructor takes the pipeline `PipelineContext` (`_ctx`, the only
  instance dependency of the cluster, used for LogInfo/LogWarning). The per-file
  `ScoringContext` keeps flowing as a `RunCalibration` parameter.
- **4 inherited members** the cluster reaches today get minimal, parity-safe
  treatment (no body changes, just visibility/qualification):
  - `ExtractTopNFragmentXics` (AbstractScoringTask:298): `protected` -> `internal
    static`. It is pure (params only; calls static `ScoringMath` only) and its only
    caller is the calibration cluster. Calibrator calls
    `AbstractScoringTask.ExtractTopNFragmentXics`.
  - `FindNearestMs1` (AbstractScoringTask:2259): `protected static` -> `internal
    static`. Genuinely shared (AbstractScoringTask:2210/:2233 also call it), so it
    stays on the base. Calibrator calls `AbstractScoringTask.FindNearestMs1`.
  - `s_calXcorrScorer`, `CAL_TOP_N_FRAGMENTS`: already `internal`, no change.
- **Diagnostics**: PR #4275 shipped diagnostics as a static facade
  (`OspreyDiagnostics.X`, call sites unchanged). The moved cluster keeps calling
  `OspreyDiagnostics.X` verbatim, preserving the Stage-cal dump call order. (The
  "injected sink" aspiration in the diagnostics TODO was superseded by the facade
  design; no injection needed here.)

## Cluster inventory (verified, PerFileScoringTask.cs)

Contiguous calibration region **lines 1570-2806** (RunCalibration's doc-comment
through ComputeMs1MassError's close); no non-calibration members interleaved.
NOTE: the TODO's original method list omitted `ScoreCalibrationMatches` (:2037,
a tuple-returning method called by RunCalibrationScoringPass). Full move set:

- private class `CalibrationPassResult` (:76-98)
- 5 constants (:67-74): MIN_SNR_FOR_RT_CAL, MIN_COELUTION_CORR_SCORE,
  MIN_COELUTION_SPECTRA, CAL_FDR_THRESHOLD, ABSOLUTE_MIN_CALIBRATION_POINTS
  (all cluster-only; verified)
- RunCalibration (:1581) -> becomes `public`, the only external entry point
- RunCalibrationScoringPass (:1825), PreprocessWindowsForXcorr (:2012),
  ScoreCalibrationMatches (:2037), CollectCalibrationPoints (:2100),
  AggregateMassCalibrations (:2157), SampleLibraryForCalibration (:2207, static),
  ScoreCalibrationEntry (:2377), ScorePeaksByCorrelation (:2677, static),
  CollectMs2FragmentErrors (:2720, static), ComputeMs1MassError (:2782)

Call site: ProcessFile, PerFileScoringTask.cs:1295 (only caller of RunCalibration)
-> rewrite to `new Calibrator(_ctx).RunCalibration(...)`.

`FormatPrefixList` (:2813) sits right after the region and STAYS in
PerFileScoringTask.

## Implementation plan

1. Promote `ExtractTopNFragmentXics` and `FindNearestMs1` to `internal static` in
   AbstractScoringTask.cs; remove the stale ExtractTopNFragmentXics comment block
   (:289-291). Build (confirms static promotion is clean).
2. Create `Tasks/Calibrator.cs`: file header (AI attribution), usings, namespace,
   `internal sealed class Calibrator` with `_ctx` field + ctor. Move the constants,
   `CalibrationPassResult`, and the 11 methods in VERBATIM (scripted slice to keep
   bodies byte-identical). Make RunCalibration `public`; qualify the 4 inherited
   references with `AbstractScoringTask.`.
3. Delete the moved region + constants + CalibrationPassResult from
   PerFileScoringTask.cs; rewrite the call site to use `new Calibrator(_ctx)`.
4. Add Calibrator.cs to the .csproj. Build net8.0 + net472, fix using/inspection.
5. Gate: `Build-OspreySharp.ps1 -Configuration Debug -RunTests -RunInspection`,
   then `Compare-EndToEnd-Crossimpl.ps1 -Files All -SkipRust` on Stellar + Astral
   (expect byte-exact; pure relocation). Diff a -d dump set to confirm dump order.
6. Self-review, PR, Copilot.
