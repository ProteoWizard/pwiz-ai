# #4710 (Osprey.Demux) vs ProteoWizard's demultiplexer: running comparison

Kept for the eventual review of #4710 against the pwiz-based alternative. Add to it whenever comparing
the two implementations turns up a difference. Source: `origin/Skyline/work/20260923_osprey_demux`
(pwiz_tools/Osprey/Osprey.Demux); C++ = msconvert's demultiplexer at 6dd40d8c93^ (retired);
C# = pwiz/analysis/Demux on master.

## Algorithm details

| Behaviour | C++ msconvert | pwiz C# (master) | #4710 Osprey.Demux | pwiz after our PRs |
|---|---|---|---|---|
| NNLS column reaches the iteration limit | keeps last feasible x (`DemuxSolver.cpp:36-37`) | zeros the column (bug: lost peaks up to 5e7, +5.4% precursors on 6 runs once fixed) | keeps last feasible x (`NnlsPath.iteration_cap`); cap 3 x columns (pwiz: 50) | PR 1: keeps last feasible x |
| NNLS tolerance | fixed 1e-10 | fixed 1e-10 | scale-relative (1e-12 x scale x n), blocks dependent columns | unchanged |
| NNLS passive-set solve | Householder QR | Cholesky on A^T A (squares the condition number; gives up earlier on a nearly singular set, then keeps the last feasible x) | incremental factor with dependent-column blocking | unchanged; noted in the solver comment (not seen on the Eclipse fixture: 408/408 match) |
| Peak-binning search span | starts at `query - maxDelta`, maxDelta = largest HALF-width (at the spectrum's highest m/z): a peak d' above a bin's center is kept only if delta + d' <= maxDelta, so EVERY bin above half the spectrum's highest m/z loses part of its upper window, more toward the top (gold value shifted 46,296 -> 38,229 when fixed) | same as C++ | correct: skips only channels whose upper edge <= peak (`OverlapDemultiplexer.ExtractChannels`) | planned PR: `2 * maxDelta` (or #4710's rule) |
| Edge snapping, 3+ overlapping bins | snaps against an untouched copy of the ranges | snaps in place (port divergence) | snaps in place, same as the C# port (comment cites "pwiz SpectrumPeakExtractor") | PR 1: match C++ |
| Peak exactly on a snapped shared edge | counted in both bins (closed ranges) | counted in both bins | counted once: half-open [low, high), last channel closed | planned PR: half-open, credit #4710 |
| Block construction | 7-window slice, 7 nearest mux spectra | same | `truncated_slice` reproduces msconvert; default `covered_bins` (whole windows) | `covered` option built and measured: -7.8% on 6 runs, not merged |
| RT interpolation | natural cubic spline, 3 points (CSpline) | MathNet natural spline, 3 points | default makima; `natural_three_point` reproduces msconvert | unchanged |
| Output | regularized: observed intensity split by solution share | same | `apportioned` (default) or `solution` | unchanged |

## Execution model (cache, parallelism) - no effect on output, large effect on time and memory

| Behaviour | C++ msconvert | pwiz C# (master) | #4710 Osprey.Demux | pwiz after our PRs |
|---|---|---|---|---|
| Spectrum cache | `SpectrumListCache` MRU, 1000 spectra, metadata and binary (`SpectrumList_Demux.cpp:327`) | `DemuxSpectrumCache` LRU, fixed 256 binary spectra (thrashes on a 101-window run: a block reads ~3 cycles) | whole run resident, input and output | #4806: sized from the cycle (4 cycles x (spectra/cycle + 1)), floor 256. PR 2b: also covers an MSX block (PrecursorsPerSpectrum x OverlapsPerCycle cycles + 1; Copilot on #4806), plus three solve-ahead batches |
| Metadata sweeps of the run | cache fills as read | two (MS levels for the cache, identities for the index mapper) | one parse of the run | #4806: one |
| Parallelism | none across blocks: `SpectrumWorkerThreads` turns worker threads OFF for a demultiplexed list (`SpectrumWorkerThreads.cpp:115`); OpenMP across the columns of one block (`DemuxSolver.cpp:34`) | same: one block at a time, `Parallel.For` across columns | whole run in parallel | PR 2b: `solveThreads=N` (default 1) solves batches of blocks ahead in parallel, next batch solved while the reader consumes this one; columns serial inside a worker. Byte-identical at any N |
| Thread safety of the reader underneath | n/a (serial) | n/a (serial) | own parse | PR 2b: inner reads serialized by one lock (vendor readers are not thread-safe); cache hits lock-free |

## Lineage: Skyline's demultiplexer, the original reference implementation

**Lineage (Brendan, 2026-10-09):** `pwiz_tools/Skyline/Model/Results` (AbstractDemultiplexer,
OverlapDemultiplexer, MsxDemultiplexer, FastOverlapDemultiplexer, NumericsLsSolver; ~1,700 lines) was
THE reference implementation while Jarrett Egertson and Dario Amodei were actively developing it and it
was the only one. It has not been actively maintained since: its primary user, the MacCoss lab, moved
all attention to the pwiz C++ implementation, using msconvert to produce lasting demultiplexed mzML
files. The future probably removes demux support from Skyline. So it is NOT a fourth peer to compare
Osprey against; its value here is as the ancestor: **where C++ differs from it, check whether C++
introduced a regression.** Order: Skyline (reference) -> C++ msconvert -> pwiz C# port; #4710 is a
separate line derived from msconvert's behaviour.

Candidate C++ regressions from the reference (to verify by reading both sides):
- **Peak-binning search span**: Skyline's TransitionBinner starts its search at
  `query - maxTransitionWidth` (full width, `AbstractDemultiplexer.cs:1113-1127`); C++
  `SpectrumPeakExtractor` uses the largest HALF-width, which truncates the upper window of every bin
  above half the spectrum's top m/z. **Verified regression in the port:** C++
  `SpectrumPeakExtractor.cpp:76-81` is TransitionBinner's loop line for line (`minStart`, forward scan
  of `binStartIndex` while `ranges[i].first < minStart`) with `_maxDelta` (half-width: ranges are
  peak +/- delta, `:34-37`) where Skyline subtracts the full width (`_maxTransitionWidth`, set from
  `windowWidth` at `AbstractDemultiplexer.cs:1070`). Came in with the C++ demultiplexer itself
  (d24a142315, 2017-01-11, "merged SpectrumList_Demux to trunk"). (Skyline bins target transitions,
  C++ every peak; the loop is the same.) Note that on the 6 Eclipse runs the
  defect currently finds MORE IDs than the correct span (38,088 vs 34,718), the PR 1b puzzle.
- Not regressions (C++ improved on it): at the NNLS iteration cap Skyline returns the passive-set solve
  `z`, which can be negative, where C++ keeps the last feasible x.

Survey by a subagent; the two decisive claims below re-verified by hand; file:line references relative
to `pwiz_tools/Skyline/Model/Results` unless given.

- **Chosen by the document isolation scheme** (`SpectraChromDataProvider.cs:1017`): OVERLAP ->
  OverlapDemultiplexer, MULTIPLEXED -> Msx, OVERLAP_MULTIPLEXED -> MsxOverlap, FAST_OVERLAP -> Fast.
  **CLI scheme import from data gives OVERLAP_MULTIPLEXED** (`IsolationSchemeReader.cs:44`, verified),
  while the GUI shows that as "Overlap" (`EditIsolationSchemeDlg.cs:1051`): the same data can go through
  different algorithms by route. Worth confirming end to end.
- **What is binned**: only the document's target transitions (product filter width), not every peak.
  Search span is the full width: the C++ half-width defect is NOT present.
- **NNLS**: Overlap: QR (Householder) passive set, tolerance 1e-8 on L1-normalized columns, cap 3 x
  columns (= 21), and at the cap returns the passive-set solve `z`, which can be negative (`NumericsLsSolver.cs:496-503`;
  negative shares -> negative intensities, inferred). Msx and MsxOverlap: `useFirstGuess: true`
  (verified, `MsxDemultiplexer.cs:47,72`) = unconstrained least squares clipped at 0, no NNLS iteration.
- **Block**: Overlap = 7 x 7 slice of the 7 nearest first-cycle windows, like msconvert; Msx = all regions.
- **RT interpolation**: Overlap = MathNet natural cubic spline, up to 3 points (like msconvert);
  Msx/MsxOverlap/Fast none.
- **Output**: regularized like msconvert, but only to chromatograms; peaks outside every target bin
  split evenly 1/N across sub-spectra.
- **Execution**: serial (the async spectrum reader is disabled when demultiplexing,
  `SpectraChromDataProvider.cs:208`); cache = MsDataFileImpl caching NumScansBlock x 1.5 plus a FIFO of
  binned target sums.
- **FastOverlap**: a different algorithm (2x overlap assumed, halves each spectrum, 10 ppm hard-coded,
  file windows not the document's). Reported bug: `Enumerable.Range(1, index-1)` throws for index 0
  (`FastOverlapDemultiplexer.cs:60`), unverified.
- **Other reported issues (unverified)**: window centre-of-mass ignores region 0 (`OverlapDemultiplexer.cs:140`);
  rank-deficient scheme throws InvalidDataException and fails the import.

Implication for the plan: none for the current PRs. If Skyline demux support is removed, PR 3's
`MsDataFileImpl` option is what a Skyline user would get instead of the msconvert step (out of scope).

## Identifications (6 Eclipse runs, human Carafe library with 1:1 entrapment, same Osprey flags)

| Arm | Precursors | FDP |
|---|---|---|
| pwiz + NNLS fix | 38,088 | 0.47% |
| #4710 weighted (default) | 36,453 | 0.44% |
| pwiz before the fix | 36,149 | 0.44% |
| #4710 msconvert-style | 35,664 | 0.41% |
| pwiz + covered windows | 35,103 | 0.46% |
| #4710 covered_bins + natural three-point | 34,698 | 0.40% |

Search span (pwiz, NNLS fix in all): defect at 10 ppm 38,088; defect at 5 ppm 30,707; corrected at 10 ppm
34,718; corrected at 5 ppm 36,122. #4710's binning is the corrected kind, which may explain part of the gap
between #4710's engines and pwiz + fix.

## Integration and engineering (from the 2026-10-08 review of #4710)

- Build: #4710's `Osprey.DemuxTool.csproj` referenced `pwiz-sharp/pwiz/src/...` paths that #4658 moved;
  the solution did not build after the merge from the .NET 10 port.
- Inspection: 11 LocalizableElement warnings in #4710's merged state (DemuxCacheBuilder, Program.cs,
  SpectraCache.cs).
- `--demux off` on an overlapping run: #4710 throws InvalidOperationException (reported as a crash with a
  stack trace); the alternative warns.
- Detection: #4710's `DemuxSchemeDetector` weights coverage by m/z width per distinct window, so a stray
  wide window, narrow windows with large overlaps, or time-segmented methods can be misclassified, and the
  ~0.2 Th edge clustering splits jittered edges; the alternative uses msconvert's own PrecursorMaskCodec
  with a consistency check over two cycles.
- Memory: #4710 holds the whole run's input and output resident while demultiplexing (estimated
  13-15 GB per large Astral file); pwiz's SpectrumListDemux streams (msconvert: +0.06 GB over plain
  conversion; Osprey peak 1.99 GB vs 1.95 GB plain read on EV13).
- Speed, EV13 vendor file to cache, 32 threads: #4710 weighted 44.0 s, #4710 msconvert-style 24.0 s,
  pwiz 40-41 s, plain read 13.7 s.
- Size: #4710 adds ~10k lines (Osprey.Demux, Osprey.DemuxTool); the alternative ~560 lines of Osprey
  product code plus ~520 in pwiz (parallel solving, detection, MsDataFileImpl option).
- ZT Scan / scanning quadrupole: only #4710 (DemuxTool, not wired into `--demux`); pwiz has no scanning
  demultiplexer. Issues found in that code by the 2026-10-08 subagent review: crash on a truncated last
  sweep, crash when a group starts on the last bin, `--peak-shape measured` output depends on thread
  count, EventCentroider merges single-ion events in sparse spectra, no ScanningDemuxPipeline test.
