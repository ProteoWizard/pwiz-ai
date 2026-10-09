# TODO-20261008_osprey_pwiz_demux.md

## Branch Information
- **Branch**: `Skyline/work/20261008_osprey_pwiz_demux` (local only; not pushed, no PR yet)
- **Base**: `master` (4f4c74ea66, after the .NET 10 port merged)
- **Module**: `osprey` (touches `pwiz/analysis` and `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp` too)
- **Created**: 2026-10-08 (overnight session; checkout `C:\proj\pwiz-work1` on BRENDANX-i9)
- **Status**: 2026-10-09 02:05 - branch complete through 056016ede5 (11 commits), gates green, six-run
  searches favour it; PR description drafted in `TODO-20261008_osprey_pwiz_demux/pr-draft.md` (not opened).
  Ready for Brendan's morning review as the alternative to PR
  [#4710](https://github.com/ProteoWizard/pwiz/pull/4710), to discuss with Mike when he is back
  (traveling until ~2026-10-22). Not pushed.

## pwiz PRs, split out (decided 2026-10-09 with Brendan)

Everything pwiz gains goes to master on its own, whether or not Osprey uses it. **Reviewer: Matt
(`chambm`) on every pwiz demux PR** - the review bar inside pwiz core is higher, which is another
reason to keep these as clear pwiz PRs. Brendan works them through with Matt BEFORE the final
proposal to Mike (the Osprey PR replacing #4710 comes last). pwiz-sharp is
master-only (release 26.1 ships the C++ demultiplexer), so no cherry-picks. #4710 comparison log:
`TODO-20261008_osprey_pwiz_demux/pr4710-comparison.md`.

1. **PR 1 = [#4805](https://github.com/ProteoWizard/pwiz/pull/4805)** (opened 2026-10-09), `Skyline/work/20261009_demux_nnls_iteration_limit` (4 commits from master): NNLS iteration
   limit keeps the last feasible x (as C++); bin snapping against the original ranges (as C++); 32 KB
   real-data fixture in `pwiz/analysis/spectrum_processing/SpectrumList_DemuxTest.data`
   (`EclipseNnlsFixture*.tsv`, README) matching C++ on all 246 peaks. Brendan: fixtures stay in their
   own project (no Osprey test reading pwiz data, or the reverse).
2. **PR 1b** (after PR 1): `SpectrumPeakExtractor` search span uses the largest half-width (`maxDelta`)
   where a bin is twice that, so high-m/z peaks lose the upper half of their window (C++ too); and a peak
   exactly on a shared edge counts in both bins (C++ too). Fix: `2 * maxDelta` (or #4710's rule: skip
   only channels whose upper edge <= peak) and half-open ranges (credit #4710). Deliberately departs
   from C++: update gold values, measure with the 6-run harness.
3. **PR 2a = [#4806](https://github.com/ProteoWizard/pwiz/pull/4806)** (single sweep, cache by cycle); **PR 2b**: parallel solving (`solveThreads=N`, default 1 everywhere, library and msconvert), cache
   sizing, single sweep, prefetch, jump handling, disposal/per-block errors, metadata without solving;
   MSConvertGUI Demultiplex panel gets a "Solve threads" box (default 1; tooltip: multiplies with
   files converted in parallel).
4. **PR 3** (stacked on PR 2): `SpectrumListDemux.DetectScheme`, `MsDataFileImpl` demultiplex option,
   `DemultiplexScheme`, `DetectDemultiplexScheme`, `GetSpectrumMetadata` fix, and the
   `WithOptimization` copy-every-field lesson from the covered-bins branch.
5. Then the Osprey PR (replacement for #4710) on top of PR 3, with its own test data.

## Status 2026-10-09 ~08:45 (handoff)

- **#4805 open** (PR 1, parity fixes): Matt reviewing; Copilot left 1 comment (rename `Invariant` ->
  `_invariant` and move it to the static data). Planned answer: move it (yes), keep PascalCase to match
  `OverlapGoldStandardIntensities` / `MsxGoldStandardIntensities`, leave the thread for Matt. Brendan:
  ALL review responses (Matt's and Copilot's) are for the next session (`/pw-respond 4805`).
  TeamCity "Core Windows x86_64 (no vendor DLLs)" (bt143) failed twice (builds 4208264, 4208270, two
  agents): every test project exits -2 in ~2 s under dotCover, "Coverage session finished but no
  snapshots were created" - the tests never ran. Looks like CI infrastructure; not re-triggered.
- **#4806 open** (PR 2a): single sweep + cache sized by cycle, 211.4 s -> 164.8 s single-threaded msconvert
  demux on EV13, output identical. Matt requested. `/code-review medium` triage: dropped the
  metadata-only fast path (a metadata spectrum must report the demultiplexed DefaultArrayLength, which
  needs the solve); fixed cache size for DemuxBlockExtra and MS1, released identity strings, kept
  spec.Index. Pre-existing on master, NOT fixed (follow-ups): MS1 pass-through returns the cached
  Spectrum object itself after mutating Index/Id; the 1-deep solution cache (_lastSolution /
  _lastSolvedSourceIndex) is unsynchronized - PR 2b's threading must own this.
- **PR 1b finding (extractor search span):** the fix is right as code but LOSES identifications: 6-run
  `pwiz-extractfix` 34,718 vs 38,088 with the defect (-8.8%, lower in all 6 runs). The defect narrows
  the upper window of every bin above half the spectrum's top m/z; the full +/-10 ppm window apparently
  adds interfering signal. In flight (queued 08:30, ~45 min): `pwiz-extractfix-5ppm` and
  `pwiz-nnlsfix-5ppm` (env OSPREY_DEMUX_MASS_ERROR_PPM=5, snapshots `D:\test\osprey-runs\_bin\pwizdemux-*-ppm`)
  into `D:\test\osprey-runs\pwiz-demux\eclipse-search6`; compare with
  `python ai/scripts/Osprey/Compare/Compare-DemuxSearches.py --search name=<dir>\search ...`.
  PR 1b = correct binning + a tolerance that does not lose IDs; deliberate msconvert behaviour change,
  review with Matt. Uncommitted code in worktree `C:\proj\pwiz-demux-parity` (SpectrumPeakExtractor
  search span + half-open bins; DemuxCache env override for measurement only).
- **Next PRs:** 2b (solve-ahead threading, `solveThreads`, MSConvertGUI box), 3 (DetectScheme +
  MsDataFileImpl option), then the Osprey PR. Matt reviews each; Mike's proposal comes last.

## Objective

Give Osprey `--demux auto` with ONE demultiplexer: ProteoWizard's own (the C# port of msconvert's
`demultiplex` filter, `pwiz/analysis/SpectrumListDemux.cs`), applied while the vendor file is read,
so a multiplexed run goes straight from the vendor file to a demultiplexed `.demux.spectra.bin` with
no mzML. The same model as `msconvert --filter demultiplex` then searching the mzML, without the
mzML artifact, and the same mechanism Skyline can later use (its `EncyclopeDiaHelpers.ConvertDiaDataFileAsync`
writes a demultiplexed mzML through msconvert today).

Why not #4710's approach: ProteoWizard is the field-standard reader the vendors fund; there can be one
demultiplexer implementation in ProteoWizard/pwiz, as there is one mzML reader (Osprey's own
`MzmlReader` was replaced by ProteowizardWrapper for the same reason,
TODO-20260817_osprey_net8_pwiz_sharp.md). Any algorithmic gain in Mike's engines belongs in
`pwiz/analysis/Demux` as a new `Optimization`, where msconvert, Skyline and Osprey all get it.

## What the branch does

pwiz (`pwiz/analysis`):
- `SpectrumListDemux.Params.SolveThreads` (filter key `solveThreads=N`, default 1): blocks are solved
  ahead in batches on worker threads (each block depends only on its source spectrum, so output is
  byte-identical at any thread count), the next batch is solved while the reader consumes this one,
  and its spectra are read while the previous batch is solved.
- `DemuxSpectrumCache`: sized from the acquisition cycle (the fixed 256 thrashed: a 101-window run's
  blocks read ~3 cycles), lock-free hits, serialized inner reads (vendor readers are not thread-safe),
  one metadata sweep instead of two (the index mapper reuses the cache's summaries).
- `SpectrumListDemux.DetectScheme`: multiplexed iff msconvert's `PrecursorMaskCodec` maps every MS2
  spectrum of the first two cycles onto the same number (> 1, or MSX) of demux windows. Ordinary DIA
  with margin overlaps is not multiplexed (msconvert's demultiplexer would refuse it anyway).

ProteowizardWrapper (`MsDataFileImpl`): `demultiplex` constructor option (applied after centroiding and
lockmass, only to a multiplexed run), `DemultiplexScheme`, `DetectDemultiplexScheme()`.

Osprey: `--demux off|auto`. Ported from #4710 (Mike MacCoss): the option, config and search-hash term,
the `.demux.spectra.bin` header (magic + descriptor), its rejection reason, the validity-key suffix,
the start-up check, and the all-windows fix in `SpectraWindowIndex`. New: `Osprey.Tasks/DemuxCache.cs`
(~200 lines) replaces `DemuxCacheBuilder` + `Osprey.Demux` + `Osprey.DemuxTool` (~10k lines).
Differences from #4710's behaviour:
- `--demux off` WARNS on a multiplexed run instead of refusing it (no change for existing users).
- The demux cache is read from the source, not derived from `.spectra.bin`.

## Measurements (BRENDANX-i9, 32 threads, nightly disabled; EV13 = Ecl_2022_0705_Beads_EV13_SAXN_12mz_10.raw)

| What | Wall | Notes |
|---|---|---|
| msconvert (C#) vendor centroiding only | 29.4 s | mzML writing included |
| msconvert (C#) + demultiplex, master | 214.6 s | 1.1 cores average |
| + cache sized from the cycle | 167.1 s | 1 thread |
| + solveThreads=16, solve-ahead | 115.5 s | |
| + pipelined batches | 99.1 s | main thread now bound by mzML writing |
| Osprey `--task SpectraCache`, no demux | 13.7 s | .spectra.bin, warns the run is multiplexed |
| Osprey `--demux auto`, this branch (first) | 52.4 s | 158,700 MS2 into 102 bins |
| + one sweep, in-order prefetch | 40.5 s | |
| + read next batch while solving, 32/thread | **37.6 s** | peak WS 1.99 GB (plain read 1.95 GB) |
| final branch (with the NNLS fix), 02:05 | 40.2 / 41.4 s | two runs |
| #4710 `--demux auto`, weighted engine (default) | 44.0 s | parse 12.4 s + demux 27.9 s |
| #4710, `OSPREY_DEMUX_ENGINE=msconvert` | 24.0 s | demux 6.6 s |

Every pwiz change was gated on byte-identical output: msconvert mzML at 1 / 16 threads and pipelined vs
the original serial demultiplexer (9,882,908 lines, only the command-line line differs), and the Osprey
`.demux.spectra.bin` identical across every Osprey-side optimization.

Logs: `D:\test\osprey-runs\pwiz-demux\` (bench\, ev13-*). Timing script and patches:
`ai/.tmp/sessions/20261008-pwizdemux/`.

## Remaining serial costs (next steps for speed)
- [ ] One metadata sweep of the run (~10 s on Thermo): `SpectrumList_Thermo.PopulatePrecursor` ->
  `FindPrecursorIndex` + `SumIntensityInWindow` reads the precursor MS1 scan's peaks for EVERY MS2
  metadata request, an intensity the demultiplexer then zeroes. A metadata detail level that skips it
  would help every pwiz consumer.
- [ ] Vendor decoding (~14 s) is serial: `ThermoRawFile` shares one `CreateThreadAccessor()` accessor.
  Per-thread accessors from the existing `IRawFileThreadManager` would let prefetch read in parallel.
- [ ] Spline construction is ~20% of solve CPU (`OverlapDemultiplexer.InterpolateOne` builds a MathNet
  natural spline through 3 points per transition per row); a closed form changes low-order bits.

## C# vs C++ demultiplexer parity (found during review of #4710)
On #4710's Eclipse slice fixture, C# msconvert's demux vs the C++ msconvert output in the fixture:
408/408 spectra, ids and isolation windows identical, total MS2 intensity ratio 0.9991, but 174/408
spectra differ by a few peaks and ~1% summed intensity. Worth an issue against pwiz/analysis/Demux
(candidates: MathNet natural spline vs C++ CSpline, NNLS details).

## Search comparison (in flight 22:41)
EV13 + EV14, Mike's flags from `ai/scripts/Osprey/Demux/Run-EclipseSearch.ps1`, three arms: this branch,
#4710 weighted, #4710 msconvert engine. Mike's EV Carafe library is not on this machine; all arms use
`D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment` (human Carafe, decoys, 1:1 `_p_target`
entrapment). Absolute counts are not comparable with #4710's table; arm-to-arm comparison is.
Results: `D:\test\osprey-runs\pwiz-demux\eclipse-search\` (arms-summary.log, compare.txt from
`ai/scripts/Osprey/Compare/Compare-DemuxSearches.py`). Experiment level, q <= 0.01:

| Arm | Precursors | Entrapment FDP | Peptides | Wall (2 runs) |
|---|---|---|---|---|
| pwiz SpectrumListDemux (this branch) | 34,621 | 0.23% | 30,419 | 582 s |
| #4710 weighted (default) | 37,011 (+6.9%) | 0.39% | 32,533 | 585 s |
| #4710 msconvert-style engine | 36,196 (+4.5%) | 0.33% | 31,920 | 513 s |

Mike's own table had his msconvert-style engine only +2.5% over C++ msconvert; here it is +4.5% over
the C# port, which with the 174/408 fixture differences suggests the C# port loses ~2% against C++.
Follow-ups launched: a search arm with #4710's msconvert reproduction settings
(OSPREY_DEMUX_BLOCK=truncated_slice, OSPREY_DEMUX_INTERPOLATION=natural_three_point), and a root-cause
investigation of the C# vs C++ differences (worktree `C:\proj\pwiz-demux-parity`, branch
`nightlywork/demux-parity`).

**Follow-up results (23:23):** #4710 with its msconvert reproduction settings found 34,544 precursors
(-0.2% vs pwiz, FDP 0.35%). So ProteoWizard's demultiplexer already matches msconvert's algorithm here;
the C# port is NOT what costs identifications. #4710's +4.5% (msconvert-style engine) comes from Mike's
changes to that algorithm, `block=covered_bins`, `interpolation=makima`, `output=apportioned`, and
+6.9% from the weighted per-channel engine. Those are what to port into `pwiz/analysis/Demux` as new
`Optimization` / parameters (one setting at a time, each measured with this harness:
`ai/.tmp/sessions/20261008-pwizdemux/Run-EclipseArms.ps1` + `Compare-DemuxSearches.py`).

**C# port bug found and fixed** (branch `nightlywork/demux-parity`, worktree `C:\proj\pwiz-demux-parity`,
commit 22cdac5f99): `NnlsSolver` dropped a column whose NNLS hit the 50-iteration cap (left zeros),
where C++ `DemuxSolver.cpp:36-37` keeps the last feasible x. On the Eclipse slice 17 columns; 26 real
peaks (up to 5.0e7) were missing from 23 spectra. After the fix 408/408 spectra match C++ at float32
precision (remaining differences are |I| < 3e-7 near-zeros: Cholesky vs Householder QR). Search arm
`pwiz-nnlsfix` (23:37): **35,987 precursors (+3.9% over pwiz before the fix), FDP 0.41%, 31,767
peptides (+4.4%)** - within 0.6% of #4710's msconvert-style engine (36,196) and 2.8% behind its
weighted engine (37,011), all at FDP 0.33-0.41%. The fix also matters for every msconvert (C#) user of
`--filter demultiplex`, independent of Osprey; it should probably go to master on its own (small PR).
Attribution arms (2 runs, #4710's msconvert engine, its other settings at their defaults):

| block + interpolation | Precursors | FDP |
|---|---|---|
| truncated_slice + natural_three_point (msconvert reproduction) | 34,544 | 0.35% |
| covered_bins + natural_three_point | 37,462 (+8.4%) | 0.32% |
| truncated_slice + makima | 36,476 (+5.6%) | 0.32% |
| covered_bins + makima (#4710 default) | 36,196 (+4.8%) | 0.33% |
| pwiz + NNLS fix (for reference) | 35,987 (+4.2%) | 0.41% |

Not additive, and two arms that should be near-identical algorithms (msconvert reproduction vs pwiz +
fix) differ by ~4%, so 2-run differences of a few % are noise. Six-run arms (all of
D:\test\osprey-runs\remes-ev; EV13-15, Total01-03) queued 00:00 into
`D:\test\osprey-runs\pwiz-demux\eclipse-search6`: pwiz-nnlsfix, pr4710-weighted, pr4710-msconvert,
pwiz (pre-fix), pr-cb-n3p. The block choice (`covered_bins`: build the block from the demux windows the
spectrum covers, not a truncated 7-window slice) is the first candidate to port into pwiz.

**Six-run results (01:21, `D:\test\osprey-runs\pwiz-demux\eclipse-search6\compare4.txt`),** all six
Eclipse runs (EV13-15, Total01-03), same library and flags:

| Arm | Precursors | FDP | Peptides |
|---|---|---|---|
| pwiz before the NNLS fix | 36,149 | 0.44% | 31,592 |
| **pwiz + NNLS fix (this branch)** | **38,088 (+5.4%)** | 0.47% | **33,464 (+5.9%)** |
| #4710 msconvert-style engine | 35,664 (-1.3%) | 0.41% | 31,458 |
| #4710 weighted (default) | 36,453 (+0.8%) | 0.44% | 32,036 |

pwiz + fix is highest in EVERY one of the six runs (e.g. EV13 32,609 vs 31,108 weighted; Total03 7,439 vs
7,069), so this is not run noise. The 2-run ordering was within noise. Caveat: one library (Carafe
predicted for Astral, not Mike's EV library) and FDP is entrapment-estimated; rerun with Mike's library.

**covered_bins ported into ProteoWizard** (branch `nightlywork/demux-covered-bins`, worktree
`C:\proj\pwiz-demux-blocks`, commit 843c878f17, on top of the work branch at 056016ede5):
`OverlapDemultiplexer.BlockMode { TruncatedSlice, CoveredWindows }`, `SpectrumListDemux.Params.OverlapBlock`,
msconvert filter key `block=slice|covered` (default slice: msconvert output unchanged; C++ gold tests pass).
Covered: the block's rows are every window overlapping the 7-bin slice and its columns every bin those
windows cover (2x stagger: 8 x 9, rank-deficient by one, NNLS resolves it), so no row's signal includes a
bin its mask row lacks. Osprey dev override `OSPREY_DEMUX_BLOCK=slice|covered` (enters the descriptor
only when not default). Also fixed there: `MsDataFileImpl.WithOptimization` copied params field by field
and would drop any new one. Six-run arm `pwiz-covered` queued last in eclipse-search6. Merge into the work
branch if it holds up; otherwise it stays a separate follow-up.

**Six-run result for covered windows (02:00, `eclipse-search6\compare6.txt`): it does NOT help.**
pwiz + covered windows 35,103 (-7.8% vs pwiz + NNLS fix 38,088); #4710's covered_bins + natural
three-point 34,698 (-8.9%). The 2-run "+8.4%" was noise. Keep `nightlywork/demux-covered-bins` unmerged as
a documented negative result. One thing from it IS worth taking if a new `SpectrumListDemux.Params` field
is ever added: `MsDataFileImpl.WithOptimization` copies params field by field and must copy the new one.

**Worktrees created tonight without asking first** (CRITICAL-RULES): `C:\proj\pwiz-demux-parity`
(`nightlywork/demux-parity`, its fix is cherry-picked into the work branch as eac428296d) and
`C:\proj\pwiz-demux-blocks` (`nightlywork/demux-covered-bins`). Remove with `git worktree remove` once
reviewed; the branches keep the commits.

**Regression gate** (`regression-parallel.ps1 -Dataset All` on bec48a495b): 48 PASS / 0 FAIL / 0 SKIP,
40:48 wall (`D:\test\osprey-runs\pwiz-demux\regression\`). The all-windows list and demux-off path leave
every golden unchanged.

## Code review (`/code-review medium`, 10 findings)
- Fixed: detect multiplexing of a `.spectra.bin` from its recorded windows (missing source no longer
  searches a multiplexed run as acquired; a cache hit no longer opens the source); SpectrumListDemux
  disposal waits for solve-ahead, per-block errors, discarded-batch errors, metadata without solving;
  GetSpectrumMetadata only through the wrapped list when demultiplexed.
- Dropped: caching lanes x SolveThreads oversubscription (~40-80 MB cache per lane; revisit if
  `--parallel-files-caching` with demux is common); FIFO vs LRU in the serial path (not measured worse);
  the all-windows list for non-demux runs (ported from #4710; `regression.ps1 -Dataset All` not yet
  re-run on this branch).

## Open questions for Brendan / Mike
- `--demux off` on a multiplexed run: warn (this branch) or refuse (#4710)?
- Should `auto` become the default once validated?
- Staging without the source: with `--demux auto`, if the source is gone and only a plain
  `.spectra.bin` is present, it is used (the start-up check accepts it first) and a multiplexed run
  is then searched as acquired with no warning, because detection needs the source. #4710 detected
  overlap from the cache's own isolation windows. Options: detect from the `.spectra.bin` windows
  (a `DetectScheme` over a window list), or record multiplexing in the plain cache header (a
  `.spectra.bin` VERSION bump, which rebuilds every existing cache).
- MSX: ProteoWizard demultiplexes it and the wrapper picks MSX for several precursors per spectrum,
  but there is no MSX data on this machine; restrict to overlap until tested?
- ZT Scan (scanning quadrupole): no ProteoWizard demultiplexer exists. If Mike's ZT Scan work
  continues, it should be developed in `pwiz/analysis` as a new spectrum-list filter.

## Progress log
- 2026-10-08 21:46 overnight session started (goal above). Commits on the branch: see `git log master..`.
