# TODO-20260728_chrominfo_memory.md

## Branch Information
- **Branch**: `Skyline/work/20260728_chrominfo_memory`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-07-28
- **Status**: In Progress
- **GitHub Issue**: (pending - not yet created)
- **PR**: (pending)

## Objective

Stop holding the rarely-used `TransitionChromInfo` and `TransitionGroupChromInfo` values in
memory, reading them back from the .skyd on demand per peptide instead.

## Architecture

A `DocNode` stops being the place complete result information comes from. It reliably
exposes only **retention time, area, and a few flags** (e.g. truncated). Everything else
lives in the .skyd and is reached through a new object that represents **one
`PeptideDocNode` plus all of its result information for all replicates**. Callers build
one, calculate with it, and let it go.

The conversion of existing readers is the bulk of the work, not a side effect of it.
Nothing can be dropped from `TransitionChromInfo` until its readers go through the facade.

`TransitionChromInfo`'s peak-derived fields are exactly the contents of one `ChromPeak`
(~48 of its 104 bytes): MassError, RetentionTime, Start/EndRetentionTime, Area,
BackgroundArea, Height, Fwhm, IsFwhmDegenerate, IsTruncated, PointsAcrossPeak,
IsForcedIntegration, PeakShapeValues, Identified. The rest - FileId, OptimizationStep,
IonMobility, Rank, RankByLevel, Annotations, UserSet - is not peak data and stays.

Rejected along the way: abstract base with compact/full subclasses; per-object lazy
loading behind a resolver back-pointer.

### What compact actually buys, exactly

`TransitionChromInfo` today, x64, 104 bytes:

| part | bytes |
|---|---:|
| object header | 16 |
| `FileId`, `IonMobility`, `Annotations` (3 refs) | 24 |
| `OptimizationStep`, `Rank`, `RankByLevel`, `_flags` (4 shorts) | 8 |
| `_massError`, `_pointsAcrossPeak` (2 shorts) | 4 |
| 7 floats: RetentionTime, Start, End, Area, BackgroundArea, Height, Fwhm | 28 |
| `PeakShapeValues` | 16 |
| `UserSet` | 4 |
| | **104** (100 padded) |

Moving the peak payload behind a reference and keeping only Area + RetentionTime:

- compact row: **~72 bytes**, a 31% saving
- custom-peak row: **~144 bytes** (72 + a separate ~72 byte peak object), 38% *worse*

So the win rides entirely on most peaks being Skyline-detected. On the reference
document that is ~31% of 14 GB, roughly **4.3 GB**.

To get past that the three references have to go too. `IonMobility` and `Annotations`
are almost always the shared EMPTY singletons, and ion mobility is already aggregated
up to the group (`IonMobilityInfo.AddIonMobilityFilterInfo`). Moving both to the group
takes a compact row to **~52 bytes**, a 50% saving, ~7 GB.

`ChromPeak` itself is ~52 bytes (7 floats + flags + massError + pointsAcross + 4
peak-shape floats), so storing one inline as a transitional step costs +4 bytes per
row before any of the saving arrives.

## Task Checklist

### Completed
- [x] Measure the baseline from the .skyd cache header on the reference document
- [x] Confirm `ChromTransition` is duplicated across replicates (byte for byte)
- [x] Agree the design: minimum resident, explicit coarse-grained load per `PeptideDocNode`
- [x] `PeptidePeakLoader` / `LoadedPeptidePeaks` - read every candidate peak for a peptide
- [x] `PeptidePeakLoaderTest` - prove cache values reproduce `TransitionChromInfo` exactly

- [x] Key candidate peaks by optimization step (`PeakKey`) - each step is its own
      chromatogram with its own candidate peaks

### In Progress
- [ ] Grow the loader into the facade: one object per `PeptideDocNode` carrying all
      result information for all replicates, including the group-level values

### Remaining
- [ ] Convert the readers to the facade. Ordering matters: the document cannot be put
      into compact format until the readers stop reading dropped values off the DocNode,
      so Reintegrate is the LAST step of this sequence, not the first
- [ ] Commit N-2: compact storage - `Area` + nullable custom-peak ref per transition cell,
      `PeakIndex` on the group
- [ ] Commit N-1: make Refine > Reintegrate produce the compact form
- [ ] Commits 3..n: convert readers - reports/databinding, results grid, scoring and
      reintegration, export
- [ ] Commit N: delete the obscure properties from `TransitionChromInfo`
- [ ] Live heap baseline against the reference document (before/after)
- [ ] Separate opportunity: deduplicate `ChromTransition` in `ChromatogramCache.RawData`
- [ ] Run ReSharper inspection before the PR (`Build-Skyline.ps1 -RunInspection`)

## Key Files

- `pwiz_tools/Skyline/Model/Results/PeptidePeakLoader.cs` - new; the loader and its result
- `pwiz_tools/Skyline/TestData/Results/PeptidePeakLoaderTest.cs` - new; validation test
- `pwiz_tools/Skyline/Model/Results/DocNodeChromInfo.cs` - `TransitionChromInfo` (104 bytes),
  `TransitionGroupChromInfo` (144 bytes); where the compact storage lands
- `pwiz_tools/Skyline/Model/TransitionGroupDocNode.cs` - `TransitionGroupChromInfoCalculator`
  aggregates every group value from the child transitions
- `pwiz_tools/Skyline/Model/Results/ChromHeaderInfo.cs` - `ChromPeak`, `ChromGroupHeaderInfo`,
  `ChromTransition`
- `pwiz_tools/Skyline/Model/Results/ChromatogramCache.cs` - `RawData` holds the header arrays
  fully resident

## Progress Log

### 2026-07-28 - Session 1

**Baseline measured** from the .skyd cache header of
`I:\bugs_i\maccoss\20260722_MemoryOptimization\TnE_2a_rerun_plate1_annotated`
(exact record counts plus struct layouts; not yet a live heap measurement).

Document shape: 96 replicates, 129,705 precursors, ~1,400,342 transitions, 10.8 transitions
per precursor. Files: .sky 17.8 GB (XML, compact `<transition_data>` format), .skyd 50.2 GB.

| Structure | cells | bytes | total |
|---|---:|---:|---:|
| `TransitionChromInfo` | 134,432,832 | 104 | 14.0 GB |
| `ChromTransition` (.skyd, resident) | 134,432,832 | 24 | 3.2 GB |
| `TransitionGroupChromInfo` | 12,451,680 | 144 | 1.8 GB |
| `Results<T>` backing arrays (transition level) | 134,432,832 | 8 | 1.1 GB |
| `ChromGroupHeaderInfo` (.skyd, resident) | 12,451,680 | 72 | 0.9 GB |
| | | | **~21 GB** |

**Findings**
- `NumPeaks` is 1 for essentially every chromatogram group in this document
  (transition-weighted mean 1.000008). Unknown whether that is typical.
- `ChromTransition` is 96x redundant byte for byte. Verified by comparing the 11-transition
  blocks for precursor 507.2548 across files 0-5: all 24 bytes identical, ion mobility
  included. ~33 MB of the 3.2 GB is unique. Deduplicating at load needs no file format
  change and is contained in `ChromatogramCache.RawData`.
- `TransitionGroupChromInfo` (144 bytes) is larger than `TransitionChromInfo` (104 bytes).
- Every `TransitionGroupChromInfo` value except QValue, ZScore, LibraryDotProduct,
  IsotopeDotProduct and Annotations is an aggregate of the child transitions.
- There is no group-level message in `SkylineDocument.proto` - it is transition-scoped
  throughout (`TransitionData` -> `Transition` -> `TransitionResults` -> `TransitionPeak`),
  and `<precursor_results>`/`<precursor_peak>` are plain XML. Persisting a group-level peak
  index would be an XML attribute, not a proto field.

**Decisions**
- Rejected: abstract base with compact/full subclasses (built, then reverted).
- Rejected: per-object lazy loading behind a resolver reference - would turn a report
  export into millions of random reads.
- Agreed: hold the minimum resident; callers needing the obscure values ask for everything
  belonging to one `PeptideDocNode` across all replicates, calculate, then release it.
  Inefficient repeated reloading is acceptable for now; optimize once the cost is located.

Resident set agreed:
```
per (transition, replicate):
    float Area
    ChromPeakValues _customPeak   // null unless the user set the boundaries

per (precursor, replicate):
    short PeakIndex               // shared by every child transition of the group
    short OptimizationStep
    float StartRetentionTime, EndRetentionTime
    float QValue, ZScore, LibraryDotProduct, IsotopeDotProduct
    Annotations                   // usually null
```

`PeakIndex` lives on the group because the same candidate peak is chosen for every
transition in the group - one short per (precursor, replicate) replaces the peak identity
that would otherwise repeat across all ~10.8 transitions.

**Commit 1 done**: `PeptidePeakLoader` reads every candidate peak for a peptide across all
replicates. `LoadedPeptidePeaks.FindPeakIndex` locates the candidate matching what the
document already records - the verification hook now, and the "recover the index at load"
mechanism later. `PeptidePeakLoaderTest` passes: for every non-empty `TransitionChromInfo`
in the Agilent results document, RetentionTime, StartTime, EndTime, Area, BackgroundArea,
Height, Fwhm and MassError all match the cache exactly.

Build succeeds; `TestLoadedPeaksMatchTransitionChromInfo` passes in 1 second.

## Context for Next Session

Commit 1 is committed on the branch. Nothing consumes the loader yet, and no memory has
been saved yet - it exists to prove the premise and to be built on.

Known gaps in commit 1:
- `PeakKey` has no optimization-step component, so CE-optimized documents would collide.
  Fix before trusting this broadly.
- The test document is small (4 peptides, 5 precursors, 20 transitions, 1 replicate). It
  proves the mechanism, not scale, and does not exercise multi-replicate or optimization
  paths.

Open questions for the developer:
- Is `NumPeaks = 1` typical, or specific to how the reference document was produced? It
  decides whether `PeakIndex` carries real information.
- Are the stored `<precursor_peak>` values used after load, or recalculated from the
  children anyway? Trace `UpdateResults` / `CalcChromInfoList` in `TransitionGroupDocNode`.
  `DocumentReader` already discards the stored `user_set` on the grounds that "all values
  are still calculated from the child transitions".
