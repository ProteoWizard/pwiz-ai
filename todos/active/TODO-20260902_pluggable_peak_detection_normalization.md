# Pluggable peak detection, peak scoring and normalization algorithms

## Branch Information
- **Branch**: `Skyline/work/20260902_PluggableNormalization` (created by Nick 2026-09-02 from the net8_port tip, pushed to origin)
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619)) - NOT `master`
- **Created**: 2026-09-02
- **Status**: Phase 0 done (builds, baseline tests pass). Phase 1 next - hosting-model and contract decisions pending with Nick.
- **PR**: (none yet)
- **Module**: `skyline`
- **Worktree**: `C:\git\sky_pluggablenormalization` (full clone, not a worktree). Start sessions with `/pw-continue C:\git\sky_pluggablenormalization`.
- **GitHub Issues**: [#4094](https://github.com/ProteoWizard/pwiz/issues/4094) RT LOESS,
  [#4096](https://github.com/ProteoWizard/pwiz/issues/4096) sum coelution score,
  [#4097](https://github.com/ProteoWizard/pwiz/issues/4097) peptide/protein rollup - these asked for
  specific algorithms; this TODO changes the approach to a plug-in contract that lets any library supply them
- **Related**:
  - [[TODO-20260329_rt_loess_normalization]] - the earlier approach (PR [#4170](https://github.com/ProteoWizard/pwiz/pull/4170),
    branch `Skyline/work/20260428_PeakScoringAndNormalization`). Superseded as a direction; kept open as a
    cherry-pick source for reference algorithms and parity tests. Do not merge that branch into this one.
  - [[TODO-20260612_net8_port]] - the base branch. Build notes for the .NET 10 tree are in
    `ai/docs/new-machine-setup.md` section 4.5 and `ai/docs/build-and-test-guide.md` (the tree builds with
    `pwiz_tools\Skyline\build.bat` through the .NET SDK; no Boost.Build).
- **Skills to load**: `/skyline-development`, `/version-control` before any commit.

## Objective

Instead of implementing each skyline-prism algorithm inside Skyline (ComBat, marker normalization, extra
rollups, ...), make Skyline's peak detection, peak scoring and normalization/summarization steps pluggable so
that anyone can write an algorithm in their own library and Skyline calls out to it. skyline-prism
(`C:\git\skyline-prism\dotnet\src\SkylinePrism.Core`, C#, .NET 10) is the first external implementation to
target.

## Decisions

### 2026-09-02 - Base on the .NET 10 port branch, not master

Options weighed: (a) continue the #4170 branch, (b) fresh branch from `master`, (c) fresh branch from the
.NET 10 port (`Skyline/work/20260612_net8_port`, PR #4619). Nick chose (c).

Facts that went into it (verified 2026-09-02):
- #4619 is Matt's port of the ProteoWizard core to .NET 10 (`pwiz-sharp/`) plus a retarget of Skyline itself to
  a single `net10.0-windows` target framework. 608 commits ahead of master, 626 Skyline files changed, still
  `CONFLICTING` with master, active daily, one stacked PR (#4588). No documented landing date.
- #4619 does not touch the scoring or normalization code. Only 6 of #4170's 97 files overlap with it, all
  peripheral (menus, csproj, `ChromHeaderInfo.cs`, `SkylineGraphs.cs`).
- Master Skyline is .NET Framework 4.7.2. A 4.7.2 process cannot load a .NET 10 library in-process, so
  in-process plug-in loading against skyline-prism only works on the .NET 10 base. On .NET 10,
  `AssemblyLoadContext` is available and pwiz-sharp already uses side-by-side load contexts (Sciex wiff2).
- Cost of the choice: nothing on this branch can ship until #4619 lands, and the base moves daily. Keep the
  plug-in contract in a small separate assembly so the Skyline-side changes stay minimal and rebase cleanly.

### What #4170 contributes (cherry-pick, do not merge)

- `MedianPolishScenariosTest` + the Small/Medium datasets with golden parquet from skyline-prism: reuse as
  the contract/parity tests for whatever plug-in mechanism is built.
- Sum coelution score (`MQuestFeatureCalc.cs` changes): natural first scoring plug-in.
- Median polish + RT LOESS (`MedianPolisher`, `PolishedPeptideAbundances`, `RtLoessCurves`,
  `PeptideQuantifier` changes): reference normalization/rollup plug-in.
- The RT LOESS Curves graph and settings UI: defer; decide later whether built-ins still ship.

## Where the seams are today (surveyed on master 2026-09-02; re-verify on the net10 branch)

| Step | Seam | How closed it is |
|------|------|------------------|
| Peak detection | `IPeakFinder` (`pwiz_tools/Shared/Common/PeakFinding/IPeakFinder.cs`) | One implementation. Created by `PeakIntegrator.CreatePeakFinder` via `PeakFinders.NewDefaultPeakFinder()`; `ChromData.Finder`, `ChromPeak(IPeakFinder, ...)` consume it. No selection point. |
| Peak scoring | `IPeakFeatureCalculator` (`Model/Results/Scoring/IPeakScoringModel.cs`) | Registry is static hard-coded lists: `PeakFeatureCalculator.Calculators`, `FeatureCalculators.ALL`, `MProphetScoringModel.DEFAULT_CALCULATORS`, `LegacyScoringModel.*FeatureCalculators`. Calculators are serialized by name in scoring models and `.sky` files. |
| Normalization | `NormalizationMethod` (abstract, `LabeledValues<string>`, `Model/GroupComparison/NormalizationMethod.cs`) | Fixed subclasses; resolved by name from document settings / group comparison defs. `NormalizedValueCalculator`, `PeptideQuantifier` apply it. |
| Rollup | `SummarizationMethod` (`Model/GroupComparison/SummarizationMethod.cs`) | Fixed list. |
| External hooks | External tools framework; `--import-peak-boundaries` (`PeakBoundaryImporter`) | Out-of-process, file based; the only existing call-out precedent. Skyline proper has no dynamic assembly loading (`Assembly.LoadFrom` only in DevTools). |

## Tasks

### Phase 0 - Set up
- [x] Record the checkout path in Worktree above; create the branch from `origin/Skyline/work/20260612_net8_port` (done 2026-09-02; branch = net8_port tip `293f906d5^` + Nick's `293f906d5` "Fix build in Visual Studio by adding pwiz projects to Skyline.sln")
- [x] Build the .NET 10 tree and run one existing scoring test and one group comparison test to establish a baseline (2026-09-02: Release build 0 errors / 786 warnings; `TestMProphetScoringModel` and `TestGroupComparisonScenarios` both pass via `Run-Tests.ps1 -Configuration Release`, auto-detected `net10.0-windows`, staged to `bin\staging\Release`)
- [x] Re-verify the seam table above against the net10 branch - all six files exist at the same paths; `PeakIntegrator.CreatePeakFinder` still calls `PeakFinders.NewDefaultPeakFinder()` (verified 2026-09-02)

### Phase 1 - Contract
- [ ] Decide hosting model: in-process (`AssemblyLoadContext`) vs out-of-process (data files / pipes). Decide per step - peak detection is called per chromatogram inside import (hot path, in-process only); normalization/rollup runs on a whole matrix (out-of-process is viable)
- [ ] Define the data contract for each step as plain data (arrays / tables), independent of Skyline document types:
  - peak detection: time/intensity arrays in, peak boundaries + apex out
  - peak scoring: per-peak-group feature values in, score(s) out (must fit the existing `IPeakFeatureCalculator` name-based serialization)
  - normalization / rollup: transition x replicate matrix (+ RT, batch/annotation columns) in, peptide/protein matrix out
- [ ] Put the contract in a separate small assembly (name TBD, e.g. `pwiz.Skyline.Algorithms.Contract`) so external libraries reference only that
- [ ] Decide how a plug-in is discovered and referenced (folder scan, explicit path in settings, NuGet?) and how the choice serializes into `.sky` settings, audit log, and `RemoveUnsupportedFeatures` for older Skyline (only add a downgrade clause when it causes a real compatibility problem)

### Phase 2 - Skyline plug points
- [ ] Peak detection: selection point for the `IPeakFinder` implementation (document setting? global setting?) and an adapter from the contract to `IPeakFinder`
- [ ] Peak scoring: make the calculator registry extensible; adapter from contract to `IPeakFeatureCalculator`; scoring model training must see plug-in calculators
- [ ] Normalization / rollup: `NormalizationMethod` and `SummarizationMethod` entries that delegate to a plug-in; wire into `PeptideQuantifier` / `NormalizedValueCalculator` / group comparisons
- [ ] Settings UI (Peptide Settings > Quantification, peak scoring model dialog) and CLI arguments (must also work via the in-process MCP `RunCommand()`)
- [ ] Error handling: a failing plug-in must not corrupt import or the document; report through the normal progress/error path

### Phase 3 - Reference implementations and tests
- [ ] Cherry-pick the `MedianPolishScenariosTest` datasets from #4170 and rewrite the test against the plug-in path
- [ ] Reference plug-in: median polish + RT LOESS (from #4170) built against the contract assembly
- [ ] Reference scoring plug-in: sum coelution score (from #4170)
- [ ] skyline-prism as an external plug-in: coordinate with the PRISM repo on an adapter project that implements the contract
- [ ] Contract tests any plug-in author can run (round-trip a known matrix, missing values, single-replicate edge cases)

### Phase 4 - Wrap up
- [ ] `/code-review max` on the branch, then PR against `Skyline/work/20260612_net8_port` with title prefix `skyline:`
- [ ] Decide fate of PR #4170 (close, or reduce to the graph/UI pieces)
- [ ] Update [[TODO-20260329_rt_loess_normalization]] to point here and close it out

## Open Questions
- In-process vs out-of-process per step (see Phase 1). Peak detection almost certainly in-process; normalization could go either way.
- Does the contract assembly target `net10.0` only, or `netstandard2.0` so a plug-in can also be built for master Skyline later? netstandard2.0 costs nothing if the contract is plain data.
- Versioning: how does Skyline know a plug-in was built against a compatible contract version?
- Where do plug-in results show up in reports and graphs (e.g. the RT LOESS Curves graph assumed Skyline computed the curves)?
- Licensing / trust: loading arbitrary DLLs into Skyline; at minimum an explicit user opt-in per plug-in.

## Progress Log

### 2026-09-02 - Direction change and TODO created

Nick decided to stop porting skyline-prism algorithms one by one (the Round 2 list in
[[TODO-20260329_rt_loess_normalization]]) and instead make the steps pluggable. Weighed master vs the .NET 10
branch as the base; chose the .NET 10 branch because the target client (skyline-prism) is .NET 10 and cannot be
loaded in-process by a 4.7.2 Skyline. Facts and seam survey recorded above. Nick is cloning a fresh checkout;
next session starts at Phase 0.

### 2026-09-02 - Phase 0: checkout, base, seam details

Checkout `C:\git\sky_pluggablenormalization`, branch `Skyline/work/20260902_PluggableNormalization` = net8_port
tip + Nick's `293f906d5` (adds pwiz projects to Skyline.sln for Visual Studio). .NET SDK 10.0.400 installed;
`global.json` asks for 10.0.100 with `latestFeature` roll-forward. Ran `pwiz-sharp\i-agree-to-the-vendor-licenses.bat`
(writes the gitignored `Directory.Build.user.props`). Release build launched with
`pwiz_tools\Skyline\build.bat Release --i-agree-to-the-vendor-licenses --no-tests` through the PowerShell tool
(NOT `cmd /c` from Bash - clink swallows it, see the net8_port TODO); log in
`ai/.tmp/sessions/20260902-pluggable/build-release.log`. `Run-Tests.ps1` has a `-Framework Net8` mode for the
`bin\staging\<Config>` layout, auto-detected from Skyline.csproj.

Seam details that constrain the contract (all verified on this branch):
- **Peak detection** `IPeakFinder` is small and data-only already: `SetChromatogram(IList<float> times,
  IList<float> intensities)`, `GetPeak(startIndex, endIndex)`, `CalcPeaks(max, int[] idIndices)`, plus
  `Intensities1d/2d` and `IsHeightAsArea`. `PeakFinders.NewDefaultPeakFinder()` is the single factory
  (`new PeakFinder()`), called from `PeakIntegrator.CreatePeakFinder`. So the plug point is a factory
  selection; the interface itself can stay. Concern: `Intensities1d/2d` and `IsHeightAsArea` leak the
  Crawdad implementation; a plug-in contract should not require them.
- **Peak scoring** calculators are keyed by CLR type name: `FullyQualifiedName => GetType().FullName`,
  and `FeatureNames._calculatorsByTypeName` is built once in a static ctor from the hard-coded
  `PeakFeatureCalculator.CALCULATORS` array (`IPeakScoringModel.cs:699`). Scoring models and `.sky` files
  store those type names. A plug-in calculator therefore needs (a) a registry that can grow after static
  init and (b) a stable name that is not a CLR type name (or a synthetic one). Tooltips come from
  `FeatureTooltips.resx` keyed by the same name - plug-ins need their own tooltip source.
- **Normalization** `NormalizationMethod.FromName` parses `ratio_to_<label>` and surrogate names, then matches
  `EQUALIZE_MEDIANS` / `GLOBAL_STANDARDS` / `TIC`, and **returns `NONE` for anything unknown** - no error.
  Good for old-Skyline compatibility (a plug-in method name silently degrades to no normalization) but means
  a missing plug-in must be surfaced somewhere else. `SummarizationMethod` is three static instances
  (`regression`, `averaging`, `medianpolish`) with the same `FromName` shape.
- **skyline-prism** (`dotnet/src/SkylinePrism.Core`) already has a minimal algorithm abstraction for rollup:
  `IRollupMethod { double[] Aggregate(double[,] log2Matrix); }` over a LOG2 features x samples matrix, used
  for both transition->peptide and peptide->protein. Normalization and batch correction are static
  classes over the same matrix shape with `sealed record` results. That matrix-in / vector-out shape is a
  strong candidate for the Skyline rollup contract; the normalization contract needs the matrix plus
  per-feature RT and per-sample batch/annotation columns.

Baseline: Release build succeeded (0 errors, 786 warnings, mostly WFO1000/CA1859 from the port).
`TestMProphetScoringModel` (0 s) and `TestGroupComparisonScenarios` (10 s) pass; `Run-Tests.ps1` staged to
`bin\staging\Release` on its own. Logs: `ai/.tmp/sessions/20260902-pluggable/build-release.log`,
`baseline-tests.log`.

Where the methods are consumed (the Phase 2 plug points):
- `NormalizedValueCalculator.TryGetDenominator` (`Model/Results/NormalizedValueCalculator.cs:396`) is the
  per-replicate dispatch: `NONE` / `GLOBAL_STANDARDS` / `EQUALIZE_MEDIANS` / `TIC` / `RatioToSurrogate`
  as an if-chain, with `RatioToLabel` handled earlier as a ratio rather than a denominator. Denominators
  come from `NormalizationData` (per-document cache built by `GetNormalizationData`, wired as a
  `WorkOrder` dependency at line 556 for EQUALIZE_MEDIANS). A plug-in normalization is a new branch here
  plus a plug-in-computed `NormalizationData` equivalent.
- `GroupComparer` (`Model/GroupComparison/GroupComparer.cs:187-191`) dispatches `SummarizationMethod`
  REGRESSION / MEDIANPOLISH / else AVERAGING; `PeptideQuantifier` does the per-peptide rollup.
- 14 model files reference the built-in `NormalizationMethod` singletons (databinding entities,
  calibration, refinement, `NormalizeOption`); most only compare for equality and would pass a plug-in
  method through untouched.
