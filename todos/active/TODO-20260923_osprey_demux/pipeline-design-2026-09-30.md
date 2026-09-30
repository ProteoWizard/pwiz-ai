# One demultiplexing pipeline: design and migration (2026-09-30)

## Decisions (Mike, 2026-09-30)

1. One pipeline in `Osprey.Demux` for every scheme, built so a new scheme adds its own stages and
   nothing else (spec §1 goal 1, §2: one forward model, schemes differ only in how `A` is built, how
   the events are gathered in time, and the noise model).
2. The new staggered demultiplexer (the apportioned per-channel solve, `DemuxInterpolatedUnit`) becomes
   the default for staggered data. `OverlapDemultiplexer` (msconvert-compatible, #4710) stays behind an
   option for comparison, with a plan to remove it later.
3. ZT Scan detection moves into `DemuxSchemeDetector`.
4. Staggered Stellar profile data is demultiplexed and centroided together (the joint solve on the
   Stellar's fixed grid, spec §5.4c-d).
5. Then the rest of the spec (below).

## Where the code stands

Three engines and three front ends share most of their parts:

| Engine | Used for | Called from |
|---|---|---|
| `OverlapDemultiplexer` | staggered, msconvert-style, one target spectrum at a time, 0/1 `A`, interpolate then solve | Osprey `--demux` (`DemuxCacheBuilder` via `Demultiplexer.Demultiplex`), #4710 |
| `ScanningDemultiplexer` | per-channel weighted NNLS on m/z channels: `DemuxUnit` (ZT Scan centroid solve, measured kernel `A`) and `DemuxInterpolatedUnit` (staggered, apportioned; 40,009 precursors on Eclipse against msconvert's 38,411) | `Osprey.DemuxTool` only |
| `JointDemultiplexer` | demultiplexing and centroiding the profile together on the TOF grid (ZT Scan MS2 and MS1) | `Osprey.DemuxTool` only |

Front ends: `ScanningDemuxSpectrumList` and `StaggeredDemuxSpectrumList` in the tool (each with its own
batching loop; the scanning one has the pipelined scheduler and 512-sample chunks), and
`DemuxCacheBuilder` in Osprey (the whole run in memory, one call).

Shared already: `DemuxScheme`/`DemuxSchemeDetector` (staggered geometry), `NnlsSolver`,
`FragmentChannelFinder`, `IonCalibration`, `ScanningKernel`, `ScanningLayout`, `RtInterpolator`, `TofGrid`,
`TofPeakShape`.

## Target pipeline

The spec's forward model, one stage each. A scheme is a choice at each stage.

| Stage | Interface (working names) | Implementations now | Later |
|---|---|---|---|
| Source | `IDemuxSource`: acquired spectra in order: level, window, time, id; peaks on demand | pwiz `ISpectrumList` (tool); Osprey's `Spectrum` lists / cache (Osprey) | streaming reader (#4714) |
| Scheme | `IDemuxScheme`: detect, cycles, bins, the events that sample each bin | staggered (window union), scanning (sweeps of encoded bins) | comb, MSX, SONAR |
| Design `A` | `IDesignBuilder`: rows, columns and `A` for a block | 0/1 windows; measured scanning kernel | measured or ramped staggered edge (§2.2 step 4); fill-time weighting (§2.0) |
| Gathering | `IEventGatherer`: which acquisitions a block solves together, at what times | same sweep (scanning); each window interpolated to the target's time (staggered) | acquired-axis fit (§4.3) |
| Observation and solve | `IUnitSolver`: centroid channels + per-channel NNLS, or profile grid + joint solve | `DemuxUnit`, `DemuxInterpolatedUnit`, `JointDemultiplexer.DemuxUnit`, `OverlapDemultiplexer` (reference) | joint solve with time gathering (staggered profile: Stellar) |
| Noise model | inside the solver's weights | counts per ion (TOF, `IonCalibration`), unweighted | Orbitrap intensity-to-ions scale |
| Layout | `IOutputLayout`: output spectra from a block's peaks | centered:k / tiled / framed, `--position-mz`; staggered per-bin apportioned; msconvert bins | |
| Driver | `DemuxPipeline`: batches of blocks, read-ahead, the pipelined scheduler, chunking | from `ScanningDemuxSpectrumList` | |
| Sink | `IDemuxSink`: receives output spectra in order | mzML (tool); `.spectra.bin` demux cache (Osprey) | streaming cache writer |

A block (today's `ScanningUnit` / `InterpolatedUnit`) is the unit of work between the stages: rows,
columns, `A`, the peaks (or profile points) and the rows' times. Staggered profile data is then the
staggered scheme, design and gathering with the profile solver: the combination no engine has today,
and the test that the stages are separated correctly.

## Migration, each step gated

Gate for every refactor step: `Osprey.DemuxTool` writes the same bytes on the reference cases
(`ai/.tmp/sessions/20260927-054c052f/Capture-DemuxGoldens.ps1`, goldens from 311d481907:
ZT joint, ZT joint at 512-sample chunks, ZT centroid solve, Eclipse EV13 staggered), plus the Osprey
test suite, inspection, and for steps touching Osprey's `--demux`, `regression.ps1`.

1. **Library pipeline, ZT Scan first.** Move `ScanningDemuxSpectrumList`'s batching, unit building and
   layout into `Osprey.DemuxTool`-independent classes in `Osprey.Demux` behind the source and sink
   interfaces; the tool's spectrum list becomes a thin adapter. ZT Scan detection moves into
   `DemuxSchemeDetector` (decision 3). Byte-identical.
   **Done:** 09f393fd7d (1a), 32b00d275c (1b), dea1c73b77 (2a: `DemuxPipeline` + `DemuxPlan`,
   `ScanningDemuxPlan`, `IDemuxSource.Describe`). Goldens identical.
2. **Staggered on the same pipeline.** `StaggeredDemuxSpectrumList`'s loop becomes the staggered scheme,
   design and gatherer on the shared driver (it gains the pipelined scheduler). Byte-identical except
   where the scheduler changes batch boundaries, which it must not.
   **Done:** 6b89e21901 (`StaggeredDemuxPlan` + `StaggeredDemuxPipeline`; the tool's spectrum list is a
   thin adapter). All four goldens identical; the Eclipse EV13 case took 350 s against 830 s at
   a96c614, on a differently loaded machine.
3. **Osprey `--demux` on the pipeline (decision 2).** `DemuxCacheBuilder` calls the pipeline with an
   Osprey source and a cache sink; the new staggered demux is the default, `OverlapDemultiplexer` behind
   an option (for example `--demux-engine msconvert`). Check Eclipse IDs and FDP through Osprey itself
   against the tool's 40,009, and ZT Scan through Osprey against the tool's whole-run results.
   **In progress:** `WeightedDemultiplexer` (Osprey's MS2 list as an `IDemuxSource` on
   `StaggeredDemuxPipeline`), `DemuxParams.Engine` weighted | msconvert in the descriptor (version 4),
   `OSPREY_DEMUX_ENGINE=msconvert` for the old engine, an env override rather than a flag because it is
   to be removed. Tests pass; the Eclipse search through Osprey is running
   (`C:	emp\osprey-runs\eclipse-staggered\search-osprey-weighted`). ZT Scan through Osprey still needs
   the profile (the joint solve reads it; the `.spectra.bin` holds centroids) and the kernel.
4. **Staggered profile (decision 4).** The profile solver takes gathered events: each window's profile
   interpolated to the target's time on the exact grid, then the joint solve as for a sweep. Needs a
   Stellar staggered profile acquisition (window width, overlap, scan rate) and a Stellar grid check
   like the ZT Scan one (spec §5.4c says the grid is fixed in firmware).
5. **The rest of the spec**: streaming for the cache (#4714), the staggered edge, fill-time weighting,
   k = 3 and 4 schedules, comb and MSX, the metrics JSON and `demux-validate` (§11).

## Open points

- #4710 is in Brendan's review and the follow-on branch is stacked on it. Step 3 changes
  `DemuxCacheBuilder`, which #4710 adds: agree the order with Brendan so his review changes and step 3
  do not collide.
- Stellar staggered profile data: none in the test data yet (Eclipse staggered, Q Exactive, ZT Scan).
- `ChunkSamples` default 2048 -> 512: done (a96c614e0d); the slice found 2,785 peptides in all runs
  against 2,698 at 2048.
