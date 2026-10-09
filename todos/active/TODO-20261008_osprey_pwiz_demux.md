# TODO-20261008_osprey_pwiz_demux.md

## Branch Information
- **Branch**: `Skyline/work/20261008_osprey_pwiz_demux` (local only; not pushed, no PR yet)
- **Base**: `master` (4f4c74ea66, after the .NET 10 port merged)
- **Module**: `osprey` (touches `pwiz/analysis` and `pwiz_tools/Shared/ProteowizardWrapper.PwizSharp` too)
- **Created**: 2026-10-08 (overnight session; checkout `C:\proj\pwiz-work1` on BRENDANX-i9)
- **Status**: Ready for Brendan's morning review as the alternative to PR
  [#4710](https://github.com/ProteoWizard/pwiz/pull/4710), to discuss with Mike when he is back
  (traveling until ~2026-10-22). Not pushed.

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
