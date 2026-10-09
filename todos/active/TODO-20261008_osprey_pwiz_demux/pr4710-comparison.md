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
| Peak-binning search span | starts at `query - maxDelta`, maxDelta = largest HALF-width: high-m/z peaks lose the upper half of their window, dependent on the spectrum's other peaks | same as C++ | correct: skips only channels whose upper edge <= peak (`OverlapDemultiplexer.ExtractChannels`) | planned PR: `2 * maxDelta` (or #4710's rule) |
| Edge snapping, 3+ overlapping bins | snaps against an untouched copy of the ranges | snaps in place (port divergence) | snaps in place, same as the C# port (comment cites "pwiz SpectrumPeakExtractor") | PR 1: match C++ |
| Peak exactly on a snapped shared edge | counted in both bins (closed ranges) | counted in both bins | counted once: half-open [low, high), last channel closed | planned PR: half-open, credit #4710 |
| Block construction | 7-window slice, 7 nearest mux spectra | same | `truncated_slice` reproduces msconvert; default `covered_bins` (whole windows) | `covered` option built and measured: -7.8% on 6 runs, not merged |
| RT interpolation | natural cubic spline, 3 points (CSpline) | MathNet natural spline, 3 points | default makima; `natural_three_point` reproduces msconvert | unchanged |
| Output | regularized: observed intensity split by solution share | same | `apportioned` (default) or `solution` | unchanged |

## Identifications (6 Eclipse runs, human Carafe library with 1:1 entrapment, same Osprey flags)

| Arm | Precursors | FDP |
|---|---|---|
| pwiz + NNLS fix | 38,088 | 0.47% |
| #4710 weighted (default) | 36,453 | 0.44% |
| pwiz before the fix | 36,149 | 0.44% |
| #4710 msconvert-style | 35,664 | 0.41% |
| pwiz + covered windows | 35,103 | 0.46% |
| #4710 covered_bins + natural three-point | 34,698 | 0.40% |

Search-span and edge-count fixes: not yet measured.

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
