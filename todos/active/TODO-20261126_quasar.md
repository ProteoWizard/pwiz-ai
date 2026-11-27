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
pwsh -File ./ai/scripts/Quasar/Build-Quasar.ps1 -SourceRoot C:/Dev/pwiz-quasar -IAgreeToVendorLicenses -RunTests -RunInspection
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
- [x] Glimpse.Features ported to `Quasar.Features` (+ `Quasar.IO/PwizEnvelopeModel`), 20 Glimpse test classes' assertions ported; committed 47b9691715 with the scaffold, EMG, clustering and mzML writer
- [x] Raw files (Mike: "we must read raw files not just mzML"): `Quasar.IO/RunReader` reads raw or mzML through ProteowizardWrapper as Osprey does, keeping injection time and analyzer per scan. Build with `-IAgreeToVendorLicenses`. Raw files downloaded from PanoramaWeb (`MacCoss/maccoss/Shared_w_lab/@files/RawFiles/osprey-testfiles/{astral,stellar}`) to `Z:\osprey-test-data\{astral,stellar}`
  - pwiz-sharp's `Sciex.csproj` pins `System.Security.Cryptography.Xml` 8.0.4, which now has high-severity advisories; with pwiz-sharp's TreatWarningsAsErrors that FAILS RESTORE of any solution referencing it (Osprey too, presumably). Quasar's build.ps1 passes `/p:NuGetAuditLevel=critical` until pwiz-sharp bumps the package. Worth telling Matt/Brendan.
- [x] Stage 1 `Quasar.Core/Traces/TraceBuilder`: anchors from Kronik-linked Hardklor envelopes (singly charged mono m/z), claimed peaks removed, centroid traces linked at 10 ppm with one missed scan, min 3 scans, 20th-percentile floor; everything in ions (`IonCalibration`, Glimpse's alpha table, ions = I x t / 1000 / alpha). Test: `TraceBuilderTest`
- [x] Pipeline + CLI: `Quasar -i <raw|mzML> [-o out.quasar.mzML] [--windows a-b] [--threads n]`; run shape from 6 sample windows; all clusters tier 3 for now
  - Astral 55: read 202,221 MS2 + 1,211 MS1 in 167 windows in 173 s (~20 GB resident, everything held as double); median anchor FWHM 2.55 s, 1.14 s between a window's scans (2-3 points per FWHM)
- [ ] Stage 1 remaining: memory (do not hold MS1 and unselected windows; floats), traces.parquet cache
- [x] Stage 2 on real data: run shape (median half-height width of 6 sample windows), anchor components, grouping into templates. Not yet: noise model estimated from data (fixed counting + 1 ion baseline), EMG dictionary for overlapping anchor peaks
- [x] Stage 3 on real data: window fit, membership by forward selection (see log), one residual pass, acceptance, median CWT boundaries. Not yet: known templates from Osprey (`--features unassigned`), robust areas, precursor tiers 1-2 (all clusters are tier 3: isolation window only)
- [x] Clustering speed (2026-11-26, 3c9e6c55fc and 4053e7557f): window 81 from ~10 min to ~55 s single-threaded; full Astral 55 (167 windows, 8 threads) ~40 min
- [x] Cluster benchmark: `ai/scripts/Quasar/Benchmark-Clusters.py` on window 81 against Osprey's 205 precursors at 1% (numbers in the log)
- [x] Stage 4: pseudo-spectrum mzML (tier 3). Not yet: clusters sidecar
- [x] Rust Sage on window 81 pseudo-spectra (`ai/scripts/Quasar/Compare-SageToOsprey.py`)
- [ ] Positive control on all of Astral 55 (run r5 in flight: `C:\temp\quasar-runs\r5`)
- [ ] Stellar: unit resolution has no resolved isotope envelopes, so no Hardklor anchors; Stages 1-2 need another anchor source there (Phase 6 per spec, but it decides whether template-first works on Stellar at all)

## Progress log

### 2026-11-26
- Created worktree `C:\Dev\pwiz-quasar` on `Skyline/work/20261126_quasar` from `origin/Skyline/work/20260612_net8_port` (77da67c3f3).
- Note: the port branch was force-updated on origin (5c90942d48...77da67c3f3) shortly before this fetch.
- CarafeSharp is not on the port branch yet (it is on #4717), so Phase 3 depends on that merging.
- Scaffolded `pwiz_tools/Quasar` and ported datum's EMG code; 3 tests pass in Debug and Release, inspection clean. Nothing committed yet.
- Deferred until needed: version stamping (Osprey's `stamp-version.ps1` pattern), TeamCity config, `Quasar.SageSharp` / `Quasar.Tasks` projects, a GitHub issue.

### 2026-11-26 night session (goal: Phase 1 end to end; commit locally, no push)
- Commits: f096e63ae3 (Stage 1, RunReader for raw and mzML, CLI pipeline), 3c9e6c55fc (clustering speed), 4053e7557f (forward selection). No pushes.
- First end-to-end result, Astral 55 window 81 (643.54-646.54): 858 pseudo-spectra; Rust Sage (`C:\temp\quasar-runs\sage\tryptic-wide.json`: wide window, chimera, tryptic, Met-ox) found 331 target PSMs / 159 peptides at 1% spectrum q; 19 of Osprey's 205 peptides at 1% in that window; apex time difference median 1.2 s.
- Cluster benchmark found the problem: the best cluster for an Osprey precursor held only 20% of the library fragments visible in its traces (median 10 of 20 visible), and ~4,000 of 5,063 templates had no members. Cause: templates a scan or two apart are nearly the same curve over a fragment's few points, so in the joint fit dropping one let the other absorb the signal and neither passed the likelihood test.
- Fix, forward selection (spec 3b): try a trace's templates best-alone first, keep each only if it passes beside those already chosen. Window 81: best cluster holds >= 3 of 20 library fragments 41% -> 84%, >= 6 15% -> 42%, >= 10 3% -> 12%; share of visible fragments 0.20 -> 0.47; Sage 703 PSMs / 342 peptides (was 331 / 159); Osprey overlap 55 of 205 (27%, was 9%); final fit 27 s -> 13 s.
- Of the Sage-only peptides (278 at the first forward-selection run), 229 are in Osprey's experiment blib with a precursor in this window but did not pass at 1% in run 55. Sage's database is 7.0 M peptides with decoys (~3.5 M targets, Met-ox variants included) and the blib 90,709 peptides, so a random false match lands in the blib ~3% of the time: most Sage-only IDs look like real peptides Osprey missed in this run, which is the point of Quasar.
- Tried and dropped: a position test (template slid +-1.5 FWHM, fit at its own place within chi-square 6.63 of the best shift). With 2-3 points per FWHM it rejected true fragments: >= 6 fragments fell to 9%, and the final fit doubled.
- Purity is low: members of the best clusters are 94% (by count and by area) neither the precursor's library fragments, their isotopes, nor fragments of another Osprey precursor eluting there; median 185 members. Likely co-eluting peptides Osprey did not identify plus non-top-20 fragments; Sage's chimeric search copes, but it is the next quality lever (membership threshold sweep in flight).
- Harness: `ai/.tmp/sessions/20261126-quasar/cluster-bench` (ClusterBench: `<traces.bin> sigma tau cycleSeconds [--dump-clusters tsv] [--mzml out] [--threshold x] [--no-residual]`), saved traces for windows 75-90 in `C:\temp\quasar-runs\traces`, all 167 windows in `C:\temp\quasar-runs\traces-ast55`.
