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
- [ ] Stage 1 remaining: traces sparse (8dbdb47811); still holds every MS2 spectrum as double arrays; traces.parquet cache
- [x] Stage 2 on real data: run shape (median half-height width of 6 sample windows), anchor components, grouping into templates. Not yet: noise model estimated from data (fixed counting + 1 ion baseline), EMG dictionary for overlapping anchor peaks
- [x] Stage 3 on real data: window fit, membership by forward selection (see log), one residual pass, acceptance, median CWT boundaries. Precursor tiers 1 (MS1, template-driven) and 2 (unfragmented MS2 anchor) write `<out>.precursors.mzML`. Known templates from Osprey's blib (`--features unassigned`, d638499710). Not yet: robust areas, tier 3 complementary-pair mass, the tier 2 heaviness check
- [x] Clustering speed (2026-11-26, 3c9e6c55fc and 4053e7557f): window 81 from ~10 min to ~55 s single-threaded; full Astral 55 (167 windows, 8 threads) ~40 min
- [x] Cluster benchmark: `ai/scripts/Quasar/Benchmark-Clusters.py` on window 81 against Osprey's 205 precursors at 1% (numbers in the log)
- [x] Stage 4: pseudo-spectrum mzML, `<out>.precursors.mzML` (one copy per precursor candidate), `<out>.clusters.parquet` sidecar (609ed156b3: one row per member, one row group per window). Not yet: settings hash in the footer, robust areas
- [x] Rust Sage on window 81 pseudo-spectra (`ai/scripts/Quasar/Compare-SageToOsprey.py`)
- [x] Positive control on all of Astral 55 (r5): Sage 41,235 peptides at 1%, 36,473 of them among Osprey's 79,422 in the run (46% recall), apex difference median 0.8 s. Next: raise recall (cluster completeness), `--features unassigned`
- [ ] Stellar: unit resolution has no resolved isotope envelopes, so no Hardklor anchors; Stages 1-2 need another anchor source there (Phase 6 per spec, but it decides whether template-first works on Stellar at all)

## Progress log

### 2026-11-26
- Created worktree `C:\Dev\pwiz-quasar` on `Skyline/work/20261126_quasar` from `origin/Skyline/work/20260612_net8_port` (77da67c3f3).
- Note: the port branch was force-updated on origin (5c90942d48...77da67c3f3) shortly before this fetch.
- CarafeSharp is not on the port branch yet (it is on #4717), so Phase 3 depends on that merging.
- Scaffolded `pwiz_tools/Quasar` and ported datum's EMG code; 3 tests pass in Debug and Release, inspection clean. Nothing committed yet.
- Deferred until needed: version stamping (Osprey's `stamp-version.ps1` pattern), TeamCity config, `Quasar.SageSharp` / `Quasar.Tasks` projects, a GitHub issue.

### 2026-11-26 night session (goal: Phase 1 end to end; commit locally, no push)
- Commits (pwiz, local): f096e63ae3 (Stage 1, RunReader for raw and mzML, CLI pipeline), 3c9e6c55fc (clustering speed), 4053e7557f (forward selection), 9b5fe6843f (precursor tiers 1 and 2), d638499710 (--features unassigned), dece94504a (spec 3a note), 8dbdb47811 (sparse traces), 609ed156b3 (clusters sidecar). pwiz-ai: 198479ea (scripts) plus this TODO. No pushes.
- **Osprey truth correction.** The blib's `OspreyRunScores` / `OspreyPeakBoundaries` hold ONE row per precursor: its best run. Run 55's real 1% set is in `RetentionTimes` (one row per precursor and run; `score` = that run's q, plus that run's boundaries): 89,137 precursors / 79,422 peptides, not 29,477. Both scripts now read `RetentionTimes`; numbers below use it. Window 81 has 619 Osprey precursors, not 205. Earlier "Sage-only" counts (and the blib-membership argument for them) were mostly an artifact of this.
- **Phase 1 positive control, all of Astral 55** (Rust Sage `tryptic-wide-psms10-peaks500.json`, 1% spectrum AND peptide q): joint fit (r4) 21,556 peptides, 19,291 of them Osprey's (24% of Osprey's 79,422), 2,265 Sage-only; forward selection (r5) **41,235 peptides, 36,473 Osprey's (46% recall), 4,762 Sage-only (12%)**, apex difference median 0.8 s, boundaries Quasar minus Osprey median 0.0 s at both ends (quartiles about one scan, 1.1 s). Quasar: 150,878 pseudo-spectra in 31 min on 8 threads, ~32 GB working set. Runs: `C:\temp\quasar-runs\r4`, `\r5` (`compare-truth.*.tsv`).
- **Entrapment check of the positive control** (r5 searched with `C:\temp\quasar-runs\entrap\target-entrap.fasta`: the Carafe library's target peptides plus their 1:1 shuffled entrapment partners, Sage decoys): 35,378 peptides at 1% spectrum+peptide q, 268 entrapment, combined FDP estimate 1.5% (shuffled entrapment overestimates, ~1.6x in the Osprey work). Peptides Osprey also found in run 55: 31,893, 0 entrapment. Peptides Osprey did not find: 3,485, 268 entrapment, FDP estimate 15% (~10% after the shuffle bias). So the overall Sage FDR on chimeric pseudo-spectra is near nominal, but the "new" subset carries most of the errors; report the gain with its own FDR. Of r5's 4,762 Sage-only peptides (human FASTA), 489 were detected by Osprey in run 49 or 60, 4,273 in no run (3,623 of them plain tryptic, charge 2-3, <= 31 residues).
- Cluster benchmark (window 81, 619 precursors), joint fit -> forward selection: best cluster holds >= 3 of 20 library fragments 58% -> 91%, >= 6 24% -> 60%, >= 10 7% -> 24%; share of the fragments visible in traces 0.27 -> 0.57. Sage on window 81: 159 -> 342 peptides (default config), 391 with 10 PSMs/500 peaks.
- Cause of the joint-fit loss: templates a scan or two apart are nearly the same curve over a fragment's few points, so dropping one let the other absorb the signal and neither passed; ~4,000 of 5,063 templates had no members. Fix = forward selection (spec 3b).
- Sage recall tracks cluster completeness (window 81, old truth): best cluster 0-2 fragments 0%, 3-5 10%, 6-9 66%, 10+ 88% found. Completeness is the lever.
- Sage settings: `report_psms` 2 -> 10 and `max_peaks` 150 -> 500 add ~10% peptides (pseudo-spectra are chimeric: identified peptides explain a median 18% of a spectrum's intensity, up to 5 IDs per spectrum).
- Tried and dropped (window 81): position test (cut >= 6-fragment clusters to a fifth); membership threshold above 9.55 (16/25/50: fewer IDs, purity barely better) or below (6.63/4: +5% peptides, same Osprey overlap); seed exclusion by apex distance (1.28 s: 649 templates, 135 peptides, a peptide elutes every ~2 s); shared membership for templates a trace cannot tell apart (more PSMs, same peptides).
- Precursor tiers (9b5fe6843f): tier 2 (unfragmented precursor anchor in MS2) is rare on Astral, 7 such anchors in window 81. Tier 1 via Hardklor+Kronik on MS1 matched few Osprey precursors (MS1 diag: 115/205 have an MS1 peak at the apex, 91 a Hardklor envelope, 9 a Kronik feature peaking within 1.3 s). Replaced by template-driven tier 1 (MS1 centroid traces the template explains, grouped into isotope series): 477 of 931 clusters get a candidate, matching 234 of 619 Osprey precursors. Narrow search of `<out>.precursors.mzML` (`tryptic-narrow.json`) finds 175 peptides, almost all also in the wide search: union 413 vs 392. Expected to matter for semi-tryptic / modified searches, not for this tryptic control.
- **`--features unassigned`** (d638499710): `--osprey-blib <blib>` reads the run's 1% precursors (RetentionTimes) and library fragments (Osprey's BlibLoader); each becomes a known template fitted to its fragments' traces (PooledEmgFit). Window 81: 747 clusters; Sage wide 161 peptides, 123 of them Osprey's, **38 new** (66 with the narrow search added). `--features all` on the same window: 392 / 317 / **75 new** (92). Known templates take the fragments of co-eluting unknown peptides (forward selection gives a trace to one template), so on tryptic Astral data all-mode minus Osprey's IDs gives twice the gain. Open question for Mike: restrict known templates to their own library-fragment traces, or take the gain from all mode (spec 3a note).
- Sage settings tried on window 81 (baseline p10: 392 peptides): `max_fragment_charge` 2 -> 308; `min_matched_peaks` 3 -> 355. Cluster setting `TemplateFit.MIN_SUPPORT_POINTS` 3 (from 4) -> 377. All kept as they were.
- MS1 calibration for run 55 (Osprey): +0.5 ppm, SD 1.4 ppm; 44% of Osprey's precursors have no MS1 peak within 10 ppm at their apex, so tier 1 cannot exceed ~56%.
- **Memory** (8dbdb47811): traces keep only their non-zero span (first scan + values; indexer, PositiveCount, CopyTo, Dense()). Dense centroid traces were ~1.8 GB per window, x8 concurrent windows; only anchors are densified before the final fit. Window 81 clusters identical (member pairs 109,430, hash 305795133743). Full-run peak memory comparison (r8 dense vs r9 sparse) pending.
- Gotcha: building a scratch project that references Quasar.IO without `/p:IAgreeToVendorLicenses=true` rebuilds pwiz-sharp's Release vendor readers WITHOUT the SDK in the shared worktree output; incremental builds with the flag do not undo it. Snapshot exes before experimenting, or run scratch tools from a copy of a known-good snapshot (`C:\temp\quasar-runs\_bin\ms1diag`).
- Harness: `ai/.tmp/sessions/20261126-quasar/cluster-bench` (ClusterBench: `<traces.bin> sigma tau cycleSeconds [--dump-clusters tsv] [--mzml out] [--threshold x] [--no-residual]`), saved traces for windows 75-90 in `C:\temp\quasar-runs\traces`, all 167 windows in `C:\temp\quasar-runs\traces-ast55`.
