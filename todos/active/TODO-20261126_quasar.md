# TODO-20261126_quasar.md

## Branch Information
- **Branch**: `Skyline/work/20261126_quasar`
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619), .NET 10 port; not yet merged)
- **Created**: 2026-11-26
- **Status**: In Progress
- **GitHub Issue**: (none yet)
- **Module**: `osprey`
- **PR**: (pending)
- **Checkout**: `C:\Dev\pwiz-quasar` (git worktree of `C:\Dev\pwiz`). Every build/test call needs `-SourceRoot C:/Dev/pwiz-quasar`.

## Objective

Quasar: a spectrum-centric companion to Osprey. It turns the peptide-like MS2 signal that no
document peptide explains into deconvoluted, background-subtracted pseudo-spectra (one per
co-eluting cluster), searches them semi-tryptic / non-specific / modified, and writes an
FDR-controlled blib that Skyline and Osprey can use directly, plus an add-on library Osprey
searches beside its unmodified library.

The spec is `pwiz_tools/Quasar/docs/00-spec.md` (from Mike's "Spec: Quasar, Spectrum-Centric
Search of Unassigned MS2 Signal", 2026-11-26). It is the source of truth for stages, file
formats and milestones; this TODO tracks progress and decisions.

## Decisions (2026-11-26)

- Quasar lives in `pwiz_tools/Quasar`, laid out like Osprey; SageSharp will be `Quasar.SageSharp`.
- Glimpse's Hardklor / Kronik / `.hk` code (`Glimpse.Features`) is copied into
  `pwiz_tools/Quasar/Quasar.Features`. Glimpse switches to it (by path, the way it already
  references pwiz-sharp) in a separate Glimpse change. Can move to `Shared` later if Skyline wants it.
- datum's EMG code (`EmgFit`, `ConsensusEmgIntegrator`, Levenberg-Marquardt) is ported into
  `Quasar.Core` under Skyline conventions, with unit tests pinned to datum's values. datum stays
  the simulator.
- Projects are added when their phase starts (no empty `Quasar.SageSharp` / `Quasar.Tasks` yet).
- Clustering is template first (spec Stages 2 and 3 rewritten 2026-11-26, Mike approved). Why: each 3 Th window on the Astral runs is sampled about every 1.1 s, so a peak has only about 3 to 5 points above half height, too few for the original per-trace EMG decomposition followed by linking on shape cosine and Pearson. Now: anchors are grouped into shared EMG templates fitted to all their points at once; every trace is fitted to the overlapping templates by weighted NNLS; membership is a likelihood test under a counting-noise model (ion counts); a residual pass finds hidden anchors. In `--features unassigned`, Osprey's precursors are known templates, not a mask. Terms: a template is the shared shape, a cluster is a template plus its members.
- The cluster benchmark (spec, Validation): Astral file 55 in `--features all` mode against Osprey's 1% precursors, completeness and purity, with the original design as the baseline. It is the tuning loop for Stages 2 and 3 before any Sage search.

## Test data

The 3 Astral and 3 Stellar HeLa runs from Osprey's regression set (Mike, 2026-11-26):

| Set | Folder | Files | Notes |
|---|---|---|---|
| Astral (HRAM) | `Z:\osprey-test-data\astral` | `Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_{49,55,60}.mzML` (~6 GB each) | Osprey `calibration.json` + scores for 55 already present |
| Stellar (unit) | `Z:\osprey-test-data\stellar` | `Ste-2024-12-02_HeLa_4mz_sDIA_400-900_{20,21,22}.mzML` (~1.4 GB each) | Osprey `calibration.json` + scores for 21 already present |
| FASTA | both folders | `uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta` | Stellar also has `hela-filtered.fasta` |

`ai/scripts/Osprey/Dataset-Config.ps1` names the same files (its default base `D:\test\osprey-runs`
does not exist on this machine; the data is on `Z:`). Astral is Phase 1-5; Stellar is the
unit-resolution set for Phase 6 and the paired-run validation.

## Reference repositories (cloned 2026-11-26)

- `C:\Dev\skyline-glimpse` - maccoss/skyline-glimpse (Hardklor, Kronik, `.hk`, assignment)
- `C:\Dev\datum` - maccoss/datum (EMG fit, Consensus EMG integrator, simulations)
- `C:\Dev\sage` - maccoss/sage (fork of lazear/sage, the Rust reference for SageSharp)

## How to build and test

```powershell
pwsh -File ./ai/scripts/Quasar/Build-Quasar.ps1 -SourceRoot C:/Dev/pwiz-quasar -RunTests -RunInspection
```

Builds `Quasar.sln` (which includes `Osprey.Core` and `Osprey.Chromatography` under an `Osprey`
folder), runs `Quasar.Test`, and runs the ReSharper gate on Quasar's files (checked once with a
deliberate unused local and a bare string literal: both were reported). Warnings are errors in
Quasar's projects. In-repo equivalent without the inspection: `pwiz_tools\Quasar\build.bat`.

## Phase 1: Quasar mzML, searched by Rust Sage

- [x] Worktree and branch from the port branch
- [x] Spec into `pwiz_tools/Quasar/docs/00-spec.md` (pipeline figure redrawn as text)
- [x] Scaffold `pwiz_tools/Quasar` (sln, Directory.Build.props/targets, Quasar, Quasar.Core, Quasar.Test, build.bat/ps1, README) and `ai/scripts/Quasar/Build-Quasar.ps1`
- [x] Port datum EMG code into `Quasar.Core/Elution` (`ErrorFunctions`, `LevenbergMarquardt`, `EmgShape`, `EmgFit`, `ConsensusEmgIntegrator`, `LinearBaseline`). `EmgTest.TestEmgMatchesDatum` pins fit, consensus areas, height crossings and baseline to datum's outputs at 1e-9 relative; the values come from `ai/scripts/Quasar/DatumGolden`
- [x] Window-fit math in `Quasar.Core/Elution` (2026-11-26): `NonNegativeLeastSquares` (Lawson-Hanson; tested against brute force on 200 random problems), `NoiseModel` (counting + baseline variance), `TemplateFit` (fixed-template weighted NNLS with linear baseline, delta chi-square membership statistic; this is the `FixedShapeEmgIntegrator`), `PooledEmgFit` (one shape over many traces, variable projection + Huber IRLS), `EmgShapePrior` (run-level log-normal prior on sigma and tau), `EmgShape.Mode`/`WithModeAt`. `DenseLinearSolver` taken out of `LevenbergMarquardt`; datum parity unchanged.
  - Seed sweep (200 draws, Astral sampling 1.1 s, FWHM ~4 s, apexes 78-519 ions): pooled shape error median 0.09 vs 0.49 for single-trace EMG fits; single-trace tau ranged 0.001x to 1.6x truth. At a quarter of the signal, tau collapsed in 33/200 pooled fits without the prior and 0/200 with a prior 20% off the truth. Harness: `ai/.tmp/sessions/20261126-quasar/pooled-sweep`.
- [x] `WindowClusterer` in `Quasar.Core/Clustering` (Stages 2c-3d): anchor components from Osprey's Mexican hat (`CwtPeakDetector.Convolve`/`FindPeaks`) kept when a typical-shape template explains them; greedy grouping with pooled refit and release; local window fits per template segment (membership, amplitude, shared fraction); residual pass; acceptance. Synthetic window test: 3 peptides (two 6 s apart), a shared fragment split 11.6/10.6 vs true 12/10, a common ion in all three, 8 noise traces kept out, and a known-template run. First version made 11 spurious residual-pass templates: residuals were judged against their own near-zero variance. Fixed by counting the explained signal in the variance (`explained` arguments) and dropping residual templates within the apex tolerance of an existing one (spec 3c updated).
  - Not yet: EMG dictionary decomposition of overlapping anchor peaks (2c; CWT peaks only so far), noise model estimated from data (2b), and speed: every trace is fitted per template segment where it has signal, fine for tests, too slow for a real window (needs an index of traces by time and a cheaper signal prefilter).
- [ ] Copy Glimpse.Features into `Quasar.Features` with tests (Hardklor, Kronik, `.hk`; ~2,400 lines in modern C#: nullable, file-scoped namespaces, records, implicit usings, so it needs a real port to Skyline style). It needs `ScanHeader`, `SpectrumData` and `IScanObserver` from Glimpse.Core, and an `IEnvelopeModel` (Glimpse.Pwiz implements it with pwiz chemistry; Osprey.Core has `IsotopeDistribution` that may serve)
- [ ] Stage 1: traces (anchors + centroids, ion counts, Osprey calibration; no mask)
- [ ] Stage 2: run-level priors, noise model, anchor components, grouping anchors into templates (pooled robust EMG fit)
- [ ] Stage 3: window fit (weighted NNLS on fixed templates), membership test, residual pass, known templates from Osprey, acceptance, boundaries and areas, precursor tiers
- [ ] Cluster benchmark against Osprey on Astral file 55, with the original design as baseline
- [ ] Stage 4: pseudo-spectrum mzML + clusters sidecar
- [ ] Search with Rust Sage; positive control (`--features all`) vs Osprey on Astral

## Progress log

### 2026-11-26
- Created worktree `C:\Dev\pwiz-quasar` on `Skyline/work/20261126_quasar` from `origin/Skyline/work/20260612_net8_port` (77da67c3f3).
- Note: the port branch was force-updated on origin (5c90942d48...77da67c3f3) shortly before this fetch.
- CarafeSharp is not on the port branch yet (it is on #4717), so Phase 3 depends on that merging.
- Scaffolded `pwiz_tools/Quasar` and ported datum's EMG code; 3 tests pass in Debug and Release, inspection clean. Nothing committed yet.
- Deferred until needed: version stamping (Osprey's `stamp-version.ps1` pattern), TeamCity config, `Quasar.SageSharp` / `Quasar.Tasks` projects, a GitHub issue.
