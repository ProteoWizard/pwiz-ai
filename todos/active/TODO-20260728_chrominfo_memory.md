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

- [x] Key candidate peaks by optimization step - each step is its own chromatogram with
      its own candidate peaks
- [x] `MoleculeResults` - one object per `PeptideDocNode` carrying all result information
      for all replicates, laid out in the flat positions the columnar classes use, with an
      interned `ChromFileIds` per transition. Constructed from a `SrmSettings` and a
      `PeptideDocNode` and reads the .skyd on first use; there is no separate loader class
- [x] Rebuild complete `TransitionChromInfo` objects from the cache (`MakeTransitionChromInfo`)
- [x] Rebuild the group level values by driving the existing calculator
      (`TransitionGroupChromInfoListCalculator`, made internal) rather than a second copy
- [x] Assign ranks and calculate dot products while materializing
- [x] One factory for all replicates or a single one
- [x] Converge the other readers onto it: `OnDemandFeatureCalculator` (and so
      `CandidatePeakForm` through `CandidatePeakGroupFactory`) and `GraphChromatogram`

- [x] Cover the paths `AgilentMix` cannot reach: optimization steps (`AgilentCEOpt`) and
      the dot products (`BlibDriftTimeTest`), each with a guard so the new assertions
      cannot pass vacuously
- [x] `OriginalPeak` derived rather than stored - `ChangeResults` recalculates it from the
      chromatogram every time, so it needs no home in the columnar classes

- [x] `ReintegratedPeak` resolved: the bounds are not needed. What is needed is the peak
      *index*, for retention time alignment and peak imputation. `TransitionGroupResults`
      now has `ChosenPeakIndexes` (renamed from `CandidatePeakIndexes`, since it holds the
      currently chosen peak), `OriginalPeakIndexes` and `ReintegratedPeakIndexes`

### In Progress
- [ ] Convert `TransitionDocNode`/`TransitionGroupDocNode` to hold the columnar classes

### Remaining - columnar storage shape (decided 2026-07-31)

The direction: **dense values that every peak has go in one struct; sparse values that
only some peaks have get a `ChromFileIdMap` each.** The map-per-column shape that
`TransitionResults` and `PeptideResults` now have is a step towards this, not the
destination.

- [ ] `TransitionGroupResults`: one struct for the dense values - `RetentionTime`,
      `StartTime`, `EndTime`, `ChosenPeakIndex` - held as a single
      `ChromFileIdMap<ThatStruct>` rather than four parallel lists. Every peak has all
      four, so nothing is wasted by keeping them together, and it is one indirection per
      peak instead of four
- [ ] `TransitionGroupResults`: the sparse values keep a `ChromFileIdMap` each -
      `Annotations`, `QValues`, `ZScores`, `UserSets`, `OriginalPeakIndexes`,
      `ReintegratedPeakIndexes`. These are absent or uniform in most documents, which is
      what `MaybeConstant()` collapses; putting them in the dense struct would undo that
- [ ] `TransitionResults`: eventually **no positionally-matched lists at all**. A
      transition stores a value only where the user moved *that transition's* peak
      boundaries independently of the rest of its precursor's. Everything else -
      `Areas`, `Truncated`, `EmptyPeaks`, `Identified`, `ForcedIntegration` - comes back
      from the .skyd via the precursor's chosen peak index.
      NOTE: this partly undoes the current map-per-column work on `TransitionResults`.
      Decide the transition-level shape before converting anything else there
- [ ] `CustomPeak`: drop `Annotations` (a `ChromFileIdMap<Annotations>` on
      `TransitionResults` instead, mirroring the precursor). Then `StartTime`/`EndTime`
      stop being nullable - a `CustomPeak` without bounds cannot exist - and
      `HasPeakBounds`/`IsEmpty` go with them, since a null entry in the list already
      means "no custom peak"
- [ ] `ChromFileIdMap.Join<TOther>(other)` for walking two maps over *different*
      `ChromFileIds` - precursor against transition, which is where position leakage
      lives. Proposed shape:
      `IEnumerable<(int ReplicateIndex, ChromFileInfoId FileId, T Value, TOther OtherValue)>`,
      a value tuple rather than `Tuple<>`. Open: inner join only, or surface the miss?
      Inner covers `GetSharedTransitionAreas`; keep `TryGetValue` for single lookups.
      Maps over the *same* `ChromFileIds` need no join - they are aligned by construction
- [ ] Finish removing `IndexOfFile` from the results classes. Still public on
      `TransitionResults`, `TransitionGroupResults`, `PeptideResults`, and these callers
      still find-then-index: `PeptideQuantifier.FindQValue`; `MoleculeResults` 431, 482,
      563, 604 (563 stores a position per transition in an array and reads it back at 649
      - the most fragile); `PeptideDocNode` 386 and 1635; `PeptideResult` 197;
      `TransitionGroupDocNode.GetPrecursorAnnotationPosition`; `MoleculeResultsTest` 249.
      `ChromFileIds.IndexOfFile` itself stays - `MergeSource.Build` needs it to align two
      layouts, which is the one place a raw position is the actual subject

Traps, both of which have already cost time:
- `ChromFileIdMap` is an `IReadOnlyList<IEnumerable<T>>`, so `map.Count` is the
  **replicate** count and `map.ToArray()` is an array of enumerables. Test comparisons
  need `.Values.ToArray()`
- Do not use `perl -0pi` with `s|...|...|` on these files; an unescaped `|` in a
  replacement clobbered the head of `TransitionGroupResults.cs`

### Remaining - the rest
- [ ] Convert the readers to the facade. Ordering matters: the document cannot be put
      into compact format until the readers stop reading dropped values off the DocNode,
      so Reintegrate is the LAST step of this sequence, not the first
- [ ] The four accessor families still backed by `LegacyChromInfos`, which is null for any
      normally-loaded document: `TransitionGroupDocNode.ChromInfos`, `GetSafeChromInfo`,
      `GetChromInfoEntry`, and the `Average*` properties. ~150 call sites; each needs a
      `MoleculeResults`. Until then they answer "no peaks" wherever they are read
- [ ] The ~130 test sites now saying `.EmptyResults` - each is a test asserting about no
      peaks, and needs moving onto a `MoleculeResults`. `RefineTest` and `AnnotationTest`
      are currently passing vacuously
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

- `pwiz_tools/Skyline/Model/Results/MoleculeResults.cs` - new; all result information for
  one molecule, plus `TransitionPeaks` and `TransitionGroupChromInfos`
- `pwiz_tools/Skyline/TestData/Results/MoleculeResultsTest.cs` - new; validation test
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
  (transition-weighted mean 1.000008), but that is **not** typical. Skyline did not do its
  own peak picking here - it took the peak boundaries from the spectral library, so there
  is only zero or one peak for everything. Normally there are about **10** candidate peaks.
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

### 2026-07-28 - Session 2

The columnar sketch (`TransitionGroupResults`, `TransitionResults`, `ChromFileIds`) is the
agreed shape and supersedes shrinking `TransitionChromInfo` in place. A cell stops being an
object and becomes 4 bytes in a flat float array: the transition level goes from ~15.1 GB
to roughly 660 MB, the precursor level from 1.8 GB to ~180 MB. Layout arithmetic, not a
measurement.

Added to the sketch: `CustomPeak` (sparse, carries annotations and the user's peak
boundaries - the thing that makes a user-set peak recoverable, since re-integrating needs
the boundaries as input), `UserSets` and `QValues`/`ZScores` lists, and `ChromFileIds.Intern`
via `ValueCache`. Scores are `float` with NaN for absent: 4 bytes rather than the 8 a
nullable float costs, and an unscored document collapses to a constant list.
`CandidatePeakIndexes` goes through `MaybeConstant` as well, but do **not** expect that to
collapse: with about 10 candidate peaks in a normally picked document the chosen index
really does vary by position. `MaybeConstant` costs nothing when it cannot collapse, so it
stays, but the memory estimate should assume 4 bytes per position for it.

**Where the cost actually is**: reading `TimeIntensitiesGroup` involves decompressing data,
and that dominates. Reading extra peaks is comparatively cheap, and in the usual case
GraphChromatogram needs all of them anyway. Do not optimize peak reading without measuring.

**Reading does not touch the library.** Library intensities and isotope proportions come
off `TransitionDocNode.LibInfo` / `IsotopeDistInfo`, which are per-transition static data
that do not vary by replicate, so the dot products need no library file access.

### 2026-07-29 - Session 3

Both result forms now live on the doc nodes at once (`AbbreviatedResults` derived from
`Results` on first use), so readers convert one at a time. Setting `Results` discards the
derived form, which matters because `ImClone` would otherwise copy the cache belonging to
the results being replaced.

Renamed away from "materialize": `MaterializedPeptideResults` + `PeptideResultsMaterializer`
are now one class, `MoleculeResults`, constructed from a `SrmSettings` and a
`PeptideDocNode` and reading the .skyd on first use. `MaterializedTransition` is
`TransitionPeaks`, `MaterializedTransitionGroup` is `TransitionGroupChromInfos`.
`MzMatchTolerance` is no longer settable: it is always
`TransitionInstrument.MzMatchTolerance`, and anywhere that used a different one was a bug.

`MoleculeResults` now answers about any replicate rather than being restricted to one:
`GetTransitionResults(TransitionGroup, Transition)` and
`GetTransitionGroupResults(TransitionGroup)`, plus the single replicate
`Get*ChromInfos(..., replicateIndex)`. A peak which is one of the candidate peaks costs only
the `ChromPeak` records; a peak whose boundaries the user set is integrated again through
`TransitionGroupIntegrator`, which decompresses the chromatogram, so those integrators are
kept once made.

**`ShapeCorrelation` cannot be reproduced from a user set peak's stored boundaries.**
Integration snaps the boundaries to the nearest chromatogram points, but the shape
correlation is measured against a median chromatogram sampled between the boundaries it was
*asked* for. The document keeps the snapped ones. Skyline has the same gap already:
`ChangeResults` re-integrates user set peaks from the stored boundaries, and the original
value survives only because `TransitionChromInfo.Equivalent` does not compare
`PeakShapeValues`. So `CustomPeak` should carry the boundaries the user gave, not the peak's
resulting start and end times. Everything else comes back exactly, which
`TestMoleculeResultsWithUserSetPeakBounds` proves by moving every peak in a replicate.

`MoleculeResults` holds only the chromatograms (`ImmutableList<ReplicateMap<ChromatogramGroupInfo>>`,
one per transition group in child order) and the `TransitionGroupIntegrator` per file. Every
chrom info is rebuilt per call, at all three levels:

- `GetTransitionResults` / `GetTransitionChromInfos` from the `ChromPeak` records, integrating
  again through `TransitionGroupIntegrator` for peaks with custom boundaries
- `GetTransitionGroupResults` / `GetTransitionGroupChromInfos` by driving
  `TransitionGroupChromInfoListCalculator`
- `GetPeptideResults` / `GetPeptideChromInfos` by driving `PeptideChromInfoListCalculator`
  (now internal, with overloads taking the chrom info lists rather than reading them off the
  doc node)

Asking for one transition rebuilds its whole group, because the ranks and the dot products
come from all of the transitions together. `ExcludeFromCalibration` and `AnalyteConcentration`
are carried forward from the doc node, the way `CopyChromInfoAttributes` does - they say
nothing about the chromatogram, so they belong in the columnar form eventually.

**Positions are found, never counted.** `ChromFileIds.IndexOfFile(replicateIndex, fileId)` is
how a caller gets a position, and `TransitionResults`/`TransitionGroupResults` expose it. The
entries of a replicate are in no order a caller can rely on, and a replicate almost always has
exactly one entry, so the linear search is cheap. The same applies to matching the doc node's
chrom infos while rebuilding: found by file and optimization step, not by index.

**The columnar classes hold optimization step zero only**, one entry per file per replicate.
The user cannot set peak boundaries or annotations for a single step, and everything else is
read back from the .skyd, which has every step. So every step of a file gets the step zero
annotations and user set when a chrom info is rebuilt. `AgilentCEOpt` confirms this: its
non-zero steps come back equal to the document's.

**Conversion lives in `MoleculeResults.ConvertResults`** (2026-07-30), called by `UpdateResults`
once the columnar results are built. A file converts only when the boundaries of *every* one of
the precursor's transition peaks match a candidate peak, and the same one; if any does not, they
are all treated as peaks whose boundaries the user set. Empty peaks say nothing either way.

Two things that had to be got right:
- **`MeasuredResults.IsLoaded` is false during the pass that recalculates results** - it wants the
  final joined cache - so guarding on it meant conversion never ran at all. The guard is now per
  file, inside `ConvertResults`: a file whose chromatograms could not be read leaves every
  transition's chrom infos alone, since integrating a custom peak needs the chromatogram too.
- **`UpdateResults` only replaces the columnar form when the results really changed.** Otherwise
  it overwrote a converted form with an unconverted one, and made an unchanged document a new
  object, which `TestMProphetResultsHandler` catches with `Assert.AreSame`.

**`UpdateResults` used to populate `ChosenPeakIndexes` itself**, capturing the index inline while
it picked each peak. `ChangeAbbreviatedResults` on both doc nodes sets them; every other path
(reading a document, merging, the many `ChangeResults` callers) still leaves them to be derived
from the chrom infos, without the indexes.

Three things that had to be got right, each of which broke something first:
- **Not every pass looks at a chromatogram.** A pass which only reuses what the node has knows no
  indexes and was stamping -1 over the real ones. `GetChosenPeakIndex` carries forward what the
  node already knew, mapping through `GetOldPosition` in case the replicate moved.
- **A negative index reads back as null**, meaning "not known", not "no candidate peak". A peak
  which really is not a candidate peak is the user's and says so with a `CustomPeak`.
- **`ChangeAbbreviatedResults` returns `this` when nothing changed**, which needs value equality
  on `TransitionGroupResults` and `TransitionResults`. Without it every recalculation produced new
  node instances and `TestMProphetResultsHandler` failed on
  `Assert.AreSame(docRepeat, docNew)` - reference equality of an unchanged document is relied on
  all over Skyline.

`MoleculeResults` still has the area search as a fallback for the paths which store no indexes.
The test asserts a non-zero count of stored indexes, because everything passed through the
fallback before that assertion was added.

**`TransitionResults.ChromInfos` is the unconverted state** (2026-07-30). A document read from a
file arrives with every chrom info kept there, because which candidate peak each peak is cannot
be told without the chromatograms. Loading them is what gets rid of it: `UpdateResults` works out
`ChosenPeakIndexes` and then drops the chrom infos. `IsConverted` says which state a transition
is in.

They are dropped only where every one of them can be got back, which
`CanDropChromInfos(groupResults)` decides per chrom info: empty peaks come back as empty, a peak
whose boundaries the user set comes back by integrating between them, and everything else needs
the precursor to know its candidate peak index. A pass which never looked at a chromatogram knows
no index and leaves the chrom infos alone rather than losing them.

Note this means the columnar form costs *more* than the chrom infos until conversion, and nothing
after it. That is the right way round: the saving is for documents whose .skyd is loaded, which is
every document being worked on.

**Still to do for the actual ask**: `UpdateResults` populates the columnar results *in addition
to* the chrom infos on the doc node, not instead of them. Dropping `Results` breaks every reader
of `nodeGroup.Results` / `nodeTran.Results`, which is the conversion this scaffold exists for.

**Tests deliberately cut back to two** (2026-07-29), one per peak selection path, because this
code is changing every session and re-verifying costs more than it catches right now. Dropped,
and worth restoring when the design settles: optimization step positions (AgilentCEOpt),
the dot products (BlibDriftTimeTest), and the stored `ChosenPeakIndexes` path. The class comment
on `MoleculeResultsTest` lists the same gaps.

**The transition level no longer reads the doc node's chrom infos at all.** It works from
`TransitionResults` plus the cache, which is the property the whole design rests on. Two things
had to move into `CustomPeak` to make that true:
- the peak boundaries, recorded for any chrom info whose `UserSet` is not FALSE, since those are
  the peaks which may not be candidate peaks
- `Identified`, because integrating between boundaries cannot rediscover it

Which candidate peak was chosen is found from the stored **areas**, since that is the only thing
about the peak the columnar results keep. It is decided once per file, at the group level, using
the transition with the largest area: a transition with little or no signal has an area which
several candidate peaks could produce (a zero area peak inside a chosen peak group is common, and
was the first thing that broke). This is the stand-in for `ChosenPeakIndexes`; populating that
list removes the search and the ambiguity with it. Only a place that has the cache can populate
it, so it cannot happen in `FromChromInfos`.

Still bridged through the doc node, both documented in the code: the group level carries scores,
annotations and the reintegrated peak forward from `nodeGroup.Results`, and
`ExcludeFromCalibration`/`AnalyteConcentration` come from `PeptideDocNode.Results`.

**`MoleculeResults` remembers what it works out** (2026-07-30), one entry per transition group.
Both levels come out of the same pass, so `GetTransitionResults` and `GetTransitionGroupResults`
share it and asking twice returns the same instance, which the test asserts.

Who holds one, from the developer:
- `Databinding.Entities.Peptide` holds one
- windows such as `GraphChromatogram` and `CandidatePeakForm` hold one for the selected molecule
- otherwise they are not held: `TransitionGroupDocNode.ChangeSettings` will take one as a
  parameter and pass it on to `UpdateResults`

`UpdateResults` is expected to get a lot smaller once that happens, because much of what it
calculates is thrown away immediately.

**Cost note**: `OnDemandFeatureCalculator` makes one `MoleculeResults` per peptide *and
replicate*, and each reads every replicate. Scoring a whole document is n times the reading it
was. Caching within one instance does not help that - it needs one instance per molecule shared
across replicates.

**Do not key dictionaries on `GlobalIndex`.** Use `ReferenceValue<T>`, which matches on the
same thing but keeps the type: an `int` key does not say which kind of object it came from,
so the wrong kind still compiles, and it does not lead back to the object in a debugger.
`architecture-data-model.md` used to recommend `GlobalIndex` first and now recommends
`ReferenceValue<T>`, with `GlobalIndex` still allowed for existing code.


### Session 6 (2026-08-01) - ownership move, encapsulation, chrom infos off the nodes

Three commits on `sky_memory`, all built and tested against the recorded baseline:

1. `f0035d174` **A transition's results moved onto its precursor.**
   `TransitionGroupResults.Transitions` holds one entry per transition, in the order of
   the precursor's children; `TransitionDocNode.AbbreviatedResults` is gone. The .sky file
   already wrote the transition areas once per precursor - holding them per node was where
   that sharing got undone, and `ApplySharedTransitionAreas` was the code doing the
   undoing.
   Alignment is kept in ONE place: `TransitionGroupDocNode.OnChangingChildren`, matching
   transitions by `Identity`. There are 29 call sites across 13 files which change a
   precursor's children; none of them had to learn about the results. A
   reference-comparison fast path means the dictionary is only built when the shape
   actually changes.
   Three things had to move up a level rather than be re-pointed: `MergeUserInfo` (the
   transition node now merges only annotations), `StripAnnotationValues` (the precursor
   strips its transitions' peak annotations with its own), and
   `DocumentAnnotationUpdater.UpdateTransitionResults`.

2. `b7ec190da` **`TransitionResults` is now `private class` nested in
   `TransitionGroupResults`.** Nothing outside can name or hold one. Callers ask the
   precursor for a value with the transition's index. The value types crossing the
   boundary - `TransitionPeak`, `CustomPeak`, `QuantifiablePeak`, `ChromFileIds` - were
   already public, so only the container got hidden.
   `DocumentWriter.GetSharedTransitionAreas` moved onto `TransitionGroupResults`.
   `DocumentReader` keeps a private `TransitionResultsData` (either the columnar values or
   the chrom infos) until the precursor has its children and can be told.
   The chrom-info factory had to be split in two, and folding them back together WILL
   break the reader: `ChangeTransitionFromChromInfos` is unconditional, while
   `UpdateTransitionFromChromInfos` keeps the "says the same" guard which stops every
   settings pass re-converting the molecule. The reader needs the unguarded one because a
   transition whose chrom infos have no step-zero peaks must still keep them.

3. `a5c5d9696` **Transition nodes no longer carry chrom infos of their own.** The compact
   (proto) reader was the last path putting them on the node - the XML reader already
   passed `null` and gave them only to the columnar form. `FromTransitionProto` now hands
   them back for the precursor.
   The two results passes which reuse what the document already has rather than reading
   the .skyd - `canUseOldResults`, and the `chromGroupInfos.Count == 0` branch - read them
   back through `TransitionGroupResults.GetTransitionLegacyChromInfos(iTran,
   chromatograms)`. That takes a `ChromatogramSet` rather than a replicate index because
   `LegacyChromInfos` is flat and its entries know their file, not their replicate.

**Where the `TransitionChromInfo` objects live now.** After a successful load: nowhere.
`ConvertResults` drops both the transitions' and the precursor's once the chosen peak
indexes are worked out. Before that pass they exist once (they used to exist twice for
compact-format documents). `TransitionDocNode.Results` is now only ever
`MeasuredResults.EmptyTransitionResults` or null, except transiently between a peak edit
and the next results pass.

**Known bounded retention, NOT fixed.** `ConvertResults` releases all-or-nothing per
precursor, gated on `everyFileRead`. That goes false if any replicate is `!IsLoaded`
(transient, resolves on a later pass) or if `FindChromatogramGroupInfo` returns null for
any single position (persistent). In the persistent case the precursor keeps every chrom
info AND `NeedsConverting` stays true, so every settings pass re-reads all of the
molecule's chromatograms.
Per-file release is NOT a small change: `chosenPeakIndexes` is rebuilt from scratch each
pass and `ChangeChosenPeakIndexes` replaces all of them, so a second pass over
partially-cleared chrom infos would reset already-found indexes to -1. Preserving the
existing indexes for positions not recomputed has to come first.

**`TestReintegrateDlg` is flaky AND order-dependent - do not use it as a regression
signal.** Six samples while checking these commits: baseline gave "diff at line 987" in a
three-test batch and line 81 twice when run alone; HEAD gave no result line at all in a
batch, then line 1107 and line 1176 when run alone. It fails on both builds either way.
HEAD diverges *later* than baseline in every comparable sample, so nothing here suggests a
regression. Same family as `TestPeakBoundaryCompare` and `TestMultiInjectRescore`.
`TestRemovePeakFromAll` and `TestReimportResults` were also confirmed failing at
`c6e2694ab`; both read `nodeTran.Results[...]`, empty since `07e082999`.

**Why `TransitionDocNode.Results` cannot simply be forced empty yet.** It is still the
write target of `ChangePeak`/`RemovePeak` and of the databinding
`TransitionResult.ChangeChromInfo`, and `SrmDocument.ChangePeak` ends at `ReplaceChild`
with no results pass and no columnar write. So immediately after a peak edit the new peak
exists ONLY there; the next pass picks it up through `canUseOldResults`. Forcing it empty
would silently discard peak edits. Order to fix: `ChangePeak`/`RemovePeak` write the
columnar form directly, then the reuse path stops needing chrom infos at all, then
`Results` can go.


### Session 7 (2026-08-02) - the retention was three separate holders, not one

The memory never dropped for `F:\skydata\20110215_MikeB\Bereman_5proteins_spikein.sky`
(format_version 1.4, 39 replicates, 442 transitions, 205 MB .skyd) across four dotMemory
snapshots. It turned out to be three unrelated holders, found one at a time. **Anything
claiming "the retention is fixed" should be treated as unverified until a profiler run on
a real document says so** - every claim of that kind this session was wrong at least once.

**1. `7fe9cc8c3` - an opened document was never converted at all.** `Chromatogram.cs` has
two paths, and the one for a document read from a file is
`docCurrent.ChangeSettingsNoDiff(...)` under the comment "Skip settings change for
deserialized document when it first becomes connected with its cache". No settings change
means no results pass, which means `ConvertResults` never runs. Import used the diffing
path, which is why every test was green while nothing was released in practice.
`MoleculeResults.ConvertDocumentResults` now runs on that path.
NOTE: that branch is gated on `FormatVersion >= VERSION_3_53`, so a genuinely old document
does NOT take it - it falls to the `else` branch and converts through the ordinary results
pass. Both paths had to work.

**2. `b0868511f` - hidden chromatogram graphs pinned the document they last drew.**
`GraphChromatogram._document` held an `SrmDocument`, and a graph on a tab which is not
showing never hears `OnDocumentUIChanged`, so it held that document - and every result
hanging off it - forever. With 39 replicates that is 39 graphs. The arithmetic gave it
away: 34.8 K retained `TransitionChromInfo` against 17,238 transition results in the
document, almost exactly 2x, so two whole documents were alive. Fixed by keeping
`SrmDocument.ReferenceId` and reading the current document from the container.
`GraphChromatogram.IsCurrent` is gone with it - any document which is not the one last
drawn is now redrawn.

**3. `04e3c438b` - `MoleculeResults` kept for molecules no longer charted.**
`GraphChromatogram.UpdateUI` now prunes `_moleculeResultsByPeptide` to the molecules under
the current selection, expanding each selected node with
`EnumeratePathsAtLevel(node.Path, Level.Molecules)`. One `MoleculeResults` holds every
chromatogram it read, so this was the most expensive thing the graph could hold.

**`everyFileRead` is gone (`b0868511f`).** It gated the release on every file of a
precursor being readable, so one unresolvable file kept the whole precursor - and since
`UpdateTransitionGroupNode` rebuilds the chrom infos on every pass while the release was
conditional, each failed pass ratcheted the retention up. Now anything which cannot be
matched to a candidate peak carries its boundaries into a `CustomPeak` instead, so there
is no case left where they must be kept and the release is unconditional.

**A user set peak can be one of the candidate peaks.** A comment in
`SearchForChosenPeakIndex` claimed otherwise. The user may have picked a different
candidate whose boundaries match exactly, and then the index reproduces it and the stored
bounds are a second copy - `DropTransitionPeakBounds` drops them. Do not reintroduce the
assumption that user set peaks never match.

**Other work**: `3190ae693` batches the peak read through
`ChromatogramGroupInfo.LoadPeaksForAll` and walks molecules with `ParallelEx.For` - note
`ReadDataForAll` takes a read lock and opens its own stream, while the lazy per-group
`ReadPeaks` uses the shared pooled stream, so the batching is what makes the parallel walk
safe. `192e5632e` finds the chosen peak from boundaries alone, with no
`GetTransitionInfo`/`GetAllTransitionInfo` call at all - those are the expensive calls,
`FindTransitionChromInfo` is not. `c3f98c18d`/`237401548` report progress 0..99.
`4913a50fd` gathers a precursor's chromatograms, calculated results and integrators into
one `GroupResults`. `6b04a7df7` makes `LegacyChromInfos` a `ChromFileIdMap` holding
optimization step zero only. `ef594f1eb` deletes `ChromFileIds.IndexOfFile(fileId)` - the
replicate is always known.

**Traps hit this session, all of which cost real time:**
- A `ResultsTestDocumentContainer` does NOT load the cache unless the document is handed to
  it as a change: `new ResultsTestDocumentContainer(docOld, path)` then
  `SetDocument(docNew, docOld, true)`. Constructing with the target document and calling
  `AssertComplete()` reports loaded while `Chromatograms[i].IsLoaded` is false, and every
  conclusion drawn from that run is worthless.
- `TestMoleculeResults*` use a ONE replicate document. `everyFileRead` needs every
  replicate to resolve, so a one-replicate test cannot see the failure that dominates a
  39-replicate document. Any test of the retention needs several replicates.
- `Run-Tests.ps1` takes `-TestName` (singular, comma separated) and builds the log file
  name from it, so more than about four names exceeds MAX_PATH and the run dies before
  starting. The code inspection test is named `CodeInspection`, not `TestCodeInspection`.
- `TestReintegrateDlg` is flaky AND order dependent - six samples gave line 987 (batch),
  81, 81 (alone) at baseline and no result (batch), 1107, 1176 (alone) at HEAD. It fails on
  both. Never use it as a regression signal.

## Context for Next Session

`MoleculeResults` is on the branch and is what `OnDemandFeatureCalculator` and
`GraphChromatogram` read chromatograms through. No memory has been saved yet, because the
doc nodes still carry both forms - the saving lands when `Results` comes off them.

Known gaps:
- `AgilentMix.zip` has no spectral library, no isotope distribution and no optimization
  function, so the dot products and the optimization step positions are NOT covered - both
  sides of those assertions are null. `BlibDriftTimeTest.zip` has a library,
  `FullScan.zip` has isotope distributions, `AgilentCEOpt.zip` has optimization steps.
- The three peak index lists often hold the same indexes, so `ShareEqualIndexes` stores an
  incoming list equal to one already present as that same instance. Worth keeping in mind
  when estimating memory: usually one list, not three.
- `GetTransitionPeakBounds` on `OnDemandFeatureCalculator` is `virtual` with no subclass
  anywhere - vestigial, not a constraint.

Open questions for the developer:
- Are the stored `<precursor_peak>` values used after load, or recalculated from the
  children anyway? Trace `UpdateResults` / `CalcChromInfoList` in `TransitionGroupDocNode`.
  `DocumentReader` already discards the stored `user_set` on the grounds that "all values
  are still calculated from the child transitions".

### 2026-08-06 - Session 8: working through the 104 failures in SkylineTester.log

Baseline: the run log at `sky_memory/SkylineTester.log` (1126 tests, 104 failures). Measured
subsets locally rather than repeating the whole run.

**Verified: the fast suites (Test.dll + TestData.dll subset of the failing list) went 28 -> 20,
and 8 of 11 converted functional tests now pass.** Nothing that passed regressed.

**The single largest cause was removing `SrmDocument.UpdateResultsSummaries` (`c7239ced8`).**
Its commit message says "nothing keeps what it worked out", which is true of the *summaries* but
not of the pass: `OnChangingChildren` ran a full results pass over every molecule whose node
changed, and that pass is the only thing which reads the .skyd for nodes that have just been
added. Without it, anything that changes children - `Refine` with auto-pick, adding isotope
transitions, importing peak boundaries - leaves the new nodes with no peaks for good. Restored,
with a comment saying what depends on it. The removal was checked against `Test.dll` only, which
is exactly the suite that has no results in it.

**Three more product defects, each found by instrumenting rather than reading:**
- `RefinementSettings.Refine` (precursor level) called the one-argument
  `TransitionGroupDocNode.GetPeakCountRatio`, one of the four accessor families still backed by
  `LegacyChromInfos`. It answers null for every precursor of a normally loaded document, so
  `RemoveMissingResults` emptied the whole document. Now calls the columnar overload.
- The columnar `GetPeakCountRatio(replicateIndex, integrateAll)` had no `-1` case, so the
  "average over replicates" meaning the accessor it replaced gave it was silently a lookup of
  replicate -1. Added `GetAveragePeakCountRatio`.
- It also returned 0 rather than null for a replicate the precursor was not measured in, because
  the denominator counted transitions with results *anywhere*. A missing chrom info used to mean
  null and refinement still relies on the difference.

**The document round trip was losing three things.** All found by dumping both sides of
`AssertEx.DescribeModelDifference`:
- `IsTruncated` and `IsForcedIntegration` were never written by `WriteTransitionResults`, so a
  peak came back with truncation "not worked out" where it had been false.
- `TransitionResults.TryGetPlainArea` let a peak ride the precursor's `transition_areas` while
  `SharedTransitionAreas.MakeTransitionResults` rebuilt it with different flags. The two now agree
  through one factory, `TransitionGroupResults.MakePlainPeak`.
- `chosen_peak_index` was written even when the indexes were not worked out, which read back as
  "this document knows them" and threw away the transition flags. It is now left out when
  `NeedsPeakIndexes`, and the "which shape are the transition elements in" question - the second
  job the writer's comment said had come apart from it - is answered by `peak_count_ratio`, which
  only a precursor that kept chrom infos ever wrote.

**Still failing, and why - these need decisions rather than fixes:**

1. **Document equality across serialization - SOLVED (Nick's design).** Two documents read from
   the same file hold different `ChromFileInfoId` objects, and `ChromFileIds.Equals` compares them
   by reference, so every `ChromFileIdMap` differed and no results document equalled itself across
   a round trip.

   Weakening `ChromFileIdMap.Equals` is **not** the answer - it hangs
   `TestCommandLineImportPeakBoundary` (tried it; blocked, 15 s of CPU in 11 minutes), and for a
   sound reason: results whose values are unchanged but whose file ids are new would be kept as
   "unchanged", and every `IndexOfFile` lookup on them then fails, so nothing is ever loaded.

   Instead the ids are **cleared before the comparison and nowhere else**. `ClearFileIds` on
   `ChromFileIds` and `ChromFileIdMap`, `ClearChromFileIds` on `TransitionGroupResults` (both
   levels), `PeptideResults` and `SrmDocument`; `AssertEx.DocsEqual` clears both sides and compares
   those. The doc nodes go on telling the ids apart - only a caller which says it means "the same
   results" gets to look past them. `LegacyChromInfos` is left alone: a `ChromInfo` compares its
   file id with `Identity` equality, which never told two apart.

   Two things it must keep doing: the document `ClearChromFileIds` returns is left deferring
   settings changes, or walking it starts a results pass which puts the ids straight back; and
   only the *comparison* may see it - `DocsEqual` diagnoses with the original documents, because
   serializing a cleared one works the chrom infos out again from the .skyd and has no file to find.
2. **The dot products are calculated, not stored** (Nick's direction, and the general rule):
   *anything needed only once is worked out by constructing a `MoleculeResults` while making one
   pass through the document.* They cost nothing to keep out of memory - the library intensities
   come off `TransitionDocNode.LibInfo` and the isotope proportions off `IsotopeDistInfo`, neither
   of which varies by replicate.

   `RefinementSettings.Refine` does that now. The molecule loop holds one lazily made
   `MoleculeResults` per molecule and lets it go before the next, and `GetAverageChromInfoValue`
   reads the dot products off it instead of `GetLibraryDotProduct`/`GetIsotopeDotProduct`, which
   are two more of the accessor families backed by `LegacyChromInfos` and were answering null for
   every precursor. Lazy on purpose: most refinements read only the columnar results and never
   touch a chromatogram.

   Note this was never only a test problem - dot-product refinement was dead for **any** document,
   loaded or not, because the accessor it went through could not answer.

   **No `MoleculeResults` at all, in the end.** The dot products need only the transitions' areas,
   which are in the columnar results, and the library intensities / isotope proportions, which are
   on the transitions. So `TransitionGroupDocNode.GetLibraryDotProduct(replicateIndex, settings)`
   and `GetIsotopeDotProduct` work them out in memory, reading no chromatogram, over the same
   transitions the results pass uses (`GetMsMsTransitions` + `ParticipatesInScoring`, and
   `GetMsTransitions`, with the same minimum counts). Refinement calls those, and the lazy
   `MoleculeResults` plumbing was removed again - nothing in refinement needs one now.

   **Verified exactly**: on `SRM_mini_single_replicate.sky` the six precursors the dot product
   filter removes come out at 0.4558922, 0.5302568, 0.6088713, 0.2184553, 0.7010977 and 0.372187,
   which are the `library_dotp` values stored in that document to every digit it wrote. The
   calculation reproduces what the results pass produced.

   Asked of the precursor **as it came**, not as refining left it: the stored chrom infos were
   worked out before any refinement ran, so they were always about the whole transition set.

   **Two of the four legacy accessor families are gone.** `GetLibraryDotProduct(int)`,
   `GetIsotopeDotProduct(int)`, `AverageLibraryDotProduct` and `AverageIsotopeDotProduct` are
   deleted rather than left beside the new overloads - an accessor which compiles and always
   answers null is exactly the trap this branch keeps falling into. Their two remaining callers
   were converted: the precursor tree label (`GetResultsText`, through
   `DisplaySettings.NormalizedValueCalculator.Document.Settings`) and `AreaReplicateGraphPane`
   (through the `_document` its `GraphData` already holds). Both were silently showing no dot
   product at all, so this fixes the tree label and the dotp line on the peak area graph as well.
   Still backed by `LegacyChromInfos`: `AveragePeakCountRatio` and `AveragePeakArea`.

   Still one peptide out: `ConsoleRefineResultsTest` now removes 6 pep / 6 prec / 65 tran where it
   expects 5 / 5 / 57. The marginal one is FLEQQNKVLETK at 0.7010977 against a threshold of
   0.7128674 - just under, so it goes. Since the computed value matches what the file stores, the
   question is whether the *areas* should have been refreshed by loading the .skyd rather than left
   as the document wrote them in 2019: master recalculated results on open, and the expectation was
   presumably taken from those recalculated areas. That is the thing to settle, and it is the same
   question as "what refreshes the columnar results when a document is opened with its cache".

   **Nick's direction: the test should load the document rather than the results being stored.**
   Right in principle, but neither document in Refine.zip can host it, and both attempts were
   built and measured before being backed out. `RefineTest.cs` is unchanged; what follows is what
   the next attempt should start from rather than rediscover.

   - **`SRM_mini.sky` can never be loaded.** It names 55 raw files which Refine.zip does not
     contain, and there is no SRM_mini.skyd.
   - **The single replicate document is the same targets** - `SRM_mini_single_replicate.sky` is
     also 4 groups, 36 molecules, 38 precursors, 334 transitions, and it loads by importing
     worm1.mzML through `AsSmallMoleculeTestUtil.ConvertToSmallMolecules`, which the small
     molecule modes already use. Three of the four "should not change the document" refinements
     at the top of `RefineResultsTest` still hold on it. `RTRegressionThreshold = 0.3` does not:
     it cuts **36 peptides to 2**. Not a legacy accessor - `GetMaxQValue` below is only reached
     for `PointsTypeRT.targets_fdr` and refinement passes `targets`. It is peak picking: the
     stored 2010 picks averaged over 55 replicates against what Skyline picks now from one
     replicate. So the RT thresholds, and every count downstream of them, need re-deriving.
   - **iPRG and sprg do not fit either.** Both ship with a .skyd, so they load with no import at
     all (worth knowing on its own), but `iPRG 2015 Study-mini` is 1 protein / 4 peptides and
     `sprg_all_charges-mini` is 1 protein / 3 peptides, and only iPRG has a .blib. The test's
     scenario - "remove the protein with only 3 peptides", "first three children unchanged",
     `MaxPepPeakRank = 5` - needs several proteins. Only iPRG could carry the dot product part.
   - **The test is one chained scenario, so the results-dependent steps cannot be lifted out.**
     Each refinement narrows the document the next one measures: cutting the dot product block
     alone moves `MaxPeakRank` from 28 transitions to 118. Verified by doing it.

   **There is no SRM_mini.skyd to be found.** Every .zip under `pwiz_tools` was searched (366 of
   them) for anything named `SRM_mini*`. What exists:
   - `Refine.zip`: `SRM_mini.sky` (no cache, 55 raw files it will never see),
     `SRM_mini_single_replicate.sky` (format 3.62, 2017, 4/36/38/334, wants worm1.mzML, no cache)
   - `CommandLineRefine.zip`: `SRM_mini_single_replicate.sky` **with its .skyd** - but a *different*
     document: format 4.2, 2019, 5 groups / 37 peptides / 40 precursors / 338 transitions, built on
     `worm_0001.mzML`, and carrying 19 `library_dotp` values against the other's 2. Its cache
     belongs to it and cannot be lent to Refine.zip's copy.

   So the only loaded multi-target refinement document that exists is CommandLineRefine.zip's, and
   `ConsoleRefineResultsTest` already uses it - which is why that test is the one showing dot
   product refinement working. If `RefineResultsTest` is to have loaded results without new test
   data, that document is the candidate; its shape is close (5/37/40/338 against 4/36/38/334) but
   the expected numbers would still need re-deriving.

   Noticed on the way: `RetentionTimeRegressionGraphData.GetMaxQValue` still reads
   `GetSafeChromInfo`, one of the legacy accessor families. The q values are in
   `TransitionGroupResults.QValues` now, and it currently answers 1.0 for every molecule - which
   means `PointsTypeRT.targets_fdr` drops every peptide from the regression.
3. **Per-optimization-step precursor annotations.** `TestAnnotations` sets an annotation on the
   second row of the results grid for a document with optimization steps and reads it back. The
   columnar results hold step zero only and give every step the step-zero annotations, so the two
   rows cannot differ. Either the grid should refuse the edit or the design needs a per-step
   annotation - not something to decide from the test.
4. **`IrtFunctionalTest` and `TestSynchronizedIntegration` hang locally** rather than failing.
   `IrtFunctionalTest` takes ~6 minutes on the reference machine (a `WaitForOpenForm` timeout) but
   did not finish in 30 here. Worth a look with a debugger attached rather than by timeout.

**Test sites converted off `.EmptyResults[...]`** (the ~130 the earlier session counted; 65
indexing sites remained, in 24 files). `ResultsUtil` gained the precursor level counterparts of
the transition helpers it already had: `EnumerateTransitionGroupChromInfos`,
`GetTransitionGroupChromInfos(document, nodeGroup[, replicateIndex])` and `FindMolecule`, which
matches on the `TransitionGroup` rather than the node so a node picked up from an earlier revision
still finds its molecule. `AssertResult.IsDocumentResultsState` now counts from the columnar
results when the document has no .skyd - a test which deserializes a document to look at it can
say nothing through a `MoleculeResults` - and counts **per file**, which is what the numbers it is
asserted against have always been (`--import-append` doubles every one of them).

Files still holding `.EmptyResults[...]` reads, all in tests which were passing vacuously:
`ShimadzuSrmDuplicateQ1Test`, `ImportDocTest`, `ManageResultsTest`, `WatersCalcurveTest`,
`RefineTest`, and the three `TestPerf` ones.

### 2026-07-30 - Session 4

Branch pushed to origin for the first time (`Skyline/work/20260728_chrominfo_memory`).

**The columnar results are now what a transition has.** `TransitionDocNode.Results` is always
empty and `AbbreviatedResults` is a plain property, not derived from anything. Reading a document
written the old way turns its chrom infos into columnar results as it goes. `File > Save` writes
the columnar form; sharing still writes every chrom info attribute for Panorama, which means
`DocumentWriter` works them out again through a `MoleculeResults` per molecule.

A precursor carries its transitions' areas in a `transition_areas` attribute and those transitions
are not written at all, but only where every one of them is ordinary at that file. A transition
left out has exactly the files the precursor carried areas for, which is what lets the reader know
which positions it owns.

`GraphChromatogram` gets its chrom infos from `MoleculeResults`, keyed on the `IdentityPath` to the
molecule. `_document` is what the graph thinks the document is, taken when it updates;
`OnDocumentUIChanged` compares against it rather than `e.DocumentPrevious`, which differ whenever
the graph missed an update.

**TestRescore hangs, and it is not a slow loop.** Bisected: not the compact save format, not the
graph changes, not the `AbbreviatedResults` simplification. It is the "Results always empty" change
in `07e082999`. The developer found the cause: an `ObjectDisposedException` reading peaks from a
`ChromatogramGroupInfo` whose cache stream has been closed, inside `CalcResultsForReplicate` during
`UpdateResultsSummaries`, while the rescore is replacing the cache. `ParallelEx.For` propagates it
correctly, so something further up - the chromatogram loader - is catching and retrying forever.

Two effects of this work widen the window: `Results` being empty means `CalcResultsForReplicate`
reads peaks it used to reuse, and `ConvertResults` reads every chromatogram of a molecule during
the settings pass. Note also that `MoleculeResults` *holds* `ChromatogramGroupInfo` objects across
calls, so anything keeping one across a cache swap has the same use-after-close exposure -
`DocumentWriter` keeps one per molecule while writing, `GraphChromatogram` one per molecule.

**Known failing**: `TestRescore` (above) and `TestCandidatePeaks` (an in-session peak edit does not
survive `UpdateResults`, since nothing rebuilds chrom infos from the columnar results yet).

**Lesson worth keeping**: three code-level hypotheses about the hang were all wrong, and each cost
a four minute build-and-run cycle. The stack trace settled it immediately. Get the exception before
theorising about a hang.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260728_chrominfo_memory.md` before starting work.

### 2026-07-30 - Session 5

**The TestRescore hang is fixed.** `TestRescore` passes again in 20 seconds. The other four
rescore tests (`TestRescoreImportDocument`, `TestRescoreSimultaneous`, `TestRescoreInPlace`,
`TestRescoreRawChromatograms`) pass as well, as do the five verification tests from the handoff.

**Where the exception went.** The previous session's guess - that the chromatogram loader catches
and retries forever - was wrong, and the diagnostic was worth the two build cycles it cost.
`Loader.FinishLoad` does rethrow the `ObjectDisposedException`, because
`ExceptionUtil.IsProgrammingDefect` is true for it, but the throw happens on the
**`Commit loaded files`** thread - the `QueueWorker` inside `FileLoadCompletionAccumulator`.
`QueueWorker.Consume` catches everything into its `Exception` property and calls `Abort()`, and
nobody ever reads that property. So the commit worker stops, no further completions are
committed, the document never becomes loaded, and `WaitForDocumentLoaded` waits forever. A
silent worker abort, not a retry loop. `FinishLoadSynch`'s `do/while` was never looping: it
printed "pass 1" on every call.

**The fix is in `ChromatogramCache.CallWithStream`.** It handed out `ReadStream.Stream` and read
from it without holding anything that stops `CloseRemovedStreams` disposing it underneath -
`PooledFileStream.Disconnect` takes the connection pool's monitor and the stream's write lock,
neither of which `CallWithStream`'s `lock (ReadStream)` excludes. It now retries once on
`ObjectDisposedException`, which either reconnects to the file or, when the file on disk has been
replaced, throws the `FileModifiedException` from `PooledFileStream.Connect` that
`CalcResultsForReplicate` and `UpdateResults` already catch and fall back from. Converting the
race into the signal the existing handlers were built for, rather than inventing a new one.

Rejected: taking `ReadStream.ReaderWriterLock.GetReadLock()` around the read, the way
`ReadDataForAll` does. It is the tidier fix but it nests the connection pool's monitor inside the
read lock, while `ConnectionPool.DisconnectWhile` takes them the other way round - a lock order
inversion. Worth revisiting deliberately rather than as a side effect of this branch.

**The silent swallow is fixed too**, at the developer's direction, on this branch rather than its
own. `FileLoadCompletionAccumulator.Commit` is the one place every batch of loaded files is handed
to the loader, from either the "Commit loaded files" worker or the "Load file" worker when there
is nothing to accumulate. Both are `QueueWorker` threads, which put anything thrown into an
`Exception` property nothing reads. It now catches and reports the failure **as a file which
could not be loaded** - a `Completion` carrying `ChangeErrorException` - so `FinishCacheBuild`
routes it to `MeasuredResults.Loader.Fail`, and from there to the load monitor. The user sees the
ordinary "Failed importing results into '<document>'" error with the exception attached, and
committing goes on to the next batch instead of stopping for the session.

Not `Program.ReportException`, which is for actual defects in Skyline; most of what can arrive
here is a user-actionable load failure. Verified by backing the `CallWithStream` fix out again:
the hang became a `MessageDlg` reading "Failed importing results into 'Rat_plasma.sky'. Cannot
access a closed file." and a test failure in 17 seconds.

That verification also turned up a **second** racing read the first stack trace never showed:
`MoleculeResults.ConvertResults` -> `FindChosenPeakIndex` -> `IndexOfPeak`
(`MoleculeResults.cs:383`), reached from `UpdateTransitionGroupNode`, distinct from the
`CalcResultsForReplicate` path. Both are covered, because the fix is at the read boundary rather
than at either call site. Worth remembering that this branch has more than one place where the
settings pass reads a chromatogram that may be swapped underneath it.

**Known failing**: `TestCandidatePeaks` only, unchanged - the in-session peak edit does not
survive `UpdateResults` (expected 60, got 109.88 at `CandidatePeakTest.cs:92`). That is the next
job: `UpdateResults` should rebuild from `ChosenPeakIndexes`/`CustomPeaks` rather than re-picking
peaks from the .skyd.

### 2026-07-31 - Session 6 (uncommitted)

**The columnar results are now what a precursor has.** `TransitionGroupDocNode.AbbreviatedResults`
is the authoritative field, and `Results` always reports an empty list per replicate, the way
`TransitionDocNode.Results` already did. `TransitionGroupResults` gained `ChromInfos` (kept as a
`Results<TransitionGroupChromInfo>` rather than flattened, so an unconverted reader can be handed
it unchanged), `IsConverted` and `ChangeChromInfos`, both in `Equals`/`GetHashCode`.

`Results` survives only so unconverted readers still compile and run. It tells them the precursor
has no peaks - wrong but quiet - and it goes when the last of them is converted.

**`UpdateResultsToEmpty` was the hard part**, and two wrong attempts are worth recording:
- Its `keepColumnarResults = !HasResults` rested on "where there are chrom infos the columnar
  results are derived from them", which is exactly what stopped being true. The columnar results
  are now kept whatever the precursor has.
- Restoring them wholesale then put back their *old* `ChromInfos` alongside emptied results, so the
  precursor claimed peaks it no longer had. The faithful translation of the old two-field state is
  `columnarResults.ChangeChromInfos(empty)`.

Both were found by instrumenting rather than reading: a stack trace printed from `ChangeResults`
when a non-empty set of areas was about to be replaced by an empty one named
`UpdateResultsToEmpty` in one run, after a whole session of wrong guesses about it.

**The `MoleculeResults` accessors are now named for what they return** (2026-07-31). The three
all-replicate getters were `GetTransitionResults`, `GetTransitionGroupResults` and
`GetPeptideResults`, which read as returning the columnar classes - `TransitionResults` and
`TransitionGroupResults` are types of their own - when what they return is
`Results<TransitionChromInfo>` and so on. They are `GetTransitionChromInfos`,
`GetTransitionGroupChromInfos` and `GetPeptideChromInfos` now, overloaded with the single replicate
versions on whether a replicate index is passed. "Results" is left to mean the columnar form
everywhere. Seven call sites, done while it was still cheap; the reader conversion will multiply
them. Pure rename, verified by the failure counts being identical either side of it.

So the three things a converted reader uses instead of the doc node:

| instead of | use |
|---|---|
| `TransitionDocNode.Results` | `MoleculeResults.GetTransitionChromInfos(transitionGroup, transition)` |
| `TransitionGroupDocNode.Results` | `MoleculeResults.GetTransitionGroupChromInfos(transitionGroup)` |
| `PeptideDocNode.Results` | `MoleculeResults.GetPeptideChromInfos()` |

**Readers converted so far**: `TransitionGroupResultsCalculator.UpdateTransitionGroupNode` (the
merge), `GetScoredPeaks`, `PeptideChromInfoListCalculator.AddChromInfoList` (which is what
aggregates the peptide level and was silently producing nothing), and `MoleculeResultsTest`'s
`CheckTransitionGroup`, `CountChosenPeakIndexes` and `MoveEveryPeak`. All read
`AbbreviatedResults?.ChromInfos` now.

**State**: `TestMoleculeResultsMatchTransitionChromInfo` passes. Failing:
`TestMoleculeResultsWithUserSetPeakBounds`, `TestColumnarResultsRoundTrip`,
`TestSaveColumnarResults`, `TestChromUI`.

**One open question, and it is semantic rather than mechanical.**
`TestMoleculeResultsWithUserSetPeakBounds` moves every peak in the document's single replicate and
then expects *no* precursor to have a chosen peak index, since every peak is now the user's. Five
still do. `MoveEveryPeak` skips nothing - verified, the diagnostic never fired - so the five are
assigned by the conversion path after the move, not left behind by the test. Either those five
moved peaks still match a candidate peak exactly, or `FindChosenPeakIndex` assigns an index for a
precursor whose transitions have been converted and so have no chrom info to compare. Worth
settling before trusting `ChosenPeakIndexes` on a document the user has integrated by hand.

`TestColumnarResultsRoundTrip` fails at `Assert.AreNotEqual(0, sharedAreasChecked)`
(`ColumnarResultsSerializationTest.cs:185`) - no transition areas are riding on their precursor
any more, which points at the writer's `GetSharedTransitionAreas` rather than at the doc node.

**Still to do**: the reader conversion proper - roughly 20-25 files, largest being `ChromInfoData`,
`AbstractTransitionResultFinder`, `RefinementSettings`, `ResultRef`, `ComparePeakBoundaries`,
`PrecursorResult`, `NormalizedValueCalculator`, `DocumentAnnotationUpdater`, the graph panes and
`PeptideQuantifier` - and then the group conversion itself, which is what actually drops the chrom
infos and delivers the memory saving. Criterion agreed with the developer: keep the exact boundary
match as the decider, and use `UserSet` only to skip work for `TRUE`/`IMPORTED`, which can never
match. Keying on `UserSet.FALSE` alone would exclude `REINTEGRATED` and `MATCHED` peaks, which are
candidate peaks - and reintegrated documents are the large ones this work is for.

**Quantification reads the columnar results** (2026-07-31). `TransitionResults` gained `Truncated`
and `EmptyPeaks`, both through `MaybeConstant`. `Truncated` is tri-state because
`TransitionChromInfo.IsTruncated` is backed by two flag bits, so null is a state of its own.
`EmptyPeaks` was the one the developer had not expected: `TransitionChromInfo.IsEmpty` is
`EndRetentionTime == 0`, quantification counts an empty peak as missing and a zero area peak as
measured, and `Areas` is zero either way, so it cannot be derived. Both are per position rather
than on `CustomPeak`, because quantification runs over the whole document and must not read a
chromatogram to get them.

`QuantifiablePeak` - file, area, truncated, empty - is what `PeptideQuantifier` and
`NormalizationData` read now, through `TransitionResults.GetQuantifiablePeaks(replicateIndex)`.
The optimization step filtering went away with it, since the columnar form holds step zero only.
Q values come from `TransitionGroupResults`, where the scores already were. Quantifying a document
now reads no chromatograms.

**`SrmDocument.UpdateResultsSummaries` is gone** (2026-07-31), along with both call sites -
`OnChangingChildren` and `ReadXml`. Nothing keeps what it worked out any more: it is either in the
columnar results already or read back on demand through a `MoleculeResults`.

It was also doing the work twice. `ChangeSettingsInternalOrThrow` calls `ChangeSettings` on every
molecule and then calls `ChangeChildren`, which came straight back through `OnChangingChildren`
into `UpdateResultsSummaries` to call `ChangeSettings` on every molecule again. The
`dictPeptideIdPeptide` guard only skipped nodes reference equal to the *previous* document's, which
after a settings change they never are.

Verified rather than assumed: `Test.dll` gives **22 failures with the removal and 22 without it**,
the same tests either way, and the results tests are unchanged. Not yet run: `TestData.dll` and the
functional suites.

Note this leaves nothing driving `ConvertResults`, so `ChosenPeakIndexes` is populated only where a
settings pass still reaches `UpdateResults`. Giving conversion an explicit home - run it when the
.skyd finishes loading, which is what the developer described - is now the next thing the memory
saving depends on.

**The precursor gives up its chrom infos** (2026-07-31), which is the precursor level saving -
1.8 GB of the 21 GB on the reference document. `ConvertResults` already had the right gate,
`everyFileRead`, and was using it to drop the transitions' chrom infos while leaving the
precursor's; it now drops both.

It has to be the same pass, not a later one. The peak indexes are found by matching the
transitions' peak boundaries, so once the transitions are converted there is nothing left to match
against. For the same reason `NeedsConverting` still asks only about the transitions: letting a
precursor whose transitions were already converted come back through would recompute every index as
-1 and overwrite the real ones.

**Three test helpers had to stop reading what the document no longer holds.** Worth recording,
because each one shows what the check has to become:
- `CheckTransitionGroup` compared the rebuilt chrom infos against the document's. It now compares
  them against the columnar values position by position - file, area, retention time, q value - and
  asserts `IsConverted`, so it actively proves the chrom infos were given up rather than merely
  surviving their absence.
- `CheckPeptide` compared against `PeptideDocNode.Results`. The molecule level is derived all the
  way down now, so there is no stored form to compare with; it checks that the results are there
  for exactly the replicates `GetReplicatesWithResults` says have them, and that asking for all
  replicates and asking for one agree.
- `MoveEveryPeak` read the peak bounds off the chrom infos; it reads them from a `MoleculeResults`.

`Test.dll` still gives **22 failures**, the same as before this change and the same as at the
commit before the `UpdateResultsSummaries` removal.

**Knock-on worth knowing**: `PeptideChromInfoListCalculator.AddChromInfoList` reads the precursor
chrom infos, which are now gone, so `PeptideDocNode.Results` comes out empty after a settings pass.
That is where the design is going anyway, but it is currently empty by accident rather than by
declaration, and should be made explicit the way `TransitionDocNode.Results` and
`TransitionGroupDocNode.Results` were.

`SameScoredPeaks` currently starts with an unconditional `return true;` (the developer's
workaround for a StackOverflowException). Underneath it, `GetScoredPeaks` now yields
`ImmutableList` rather than a bare sequence: `SequenceEqual` compares the elements - whole lists -
with the default comparer, and a bare `IEnumerable` has no value equality, so the fallback could
never return true and termination rested entirely on `ReferenceEquals(Results, other.Results)`.
That is why losing reference stability turned into unbounded recursion.

### 2026-07-31 - Session 5

Commits `0a22318a0`..`1860a68cb`, all pushed.

Landed: `StripAnnotationValues` on the columnar results; every reader of
`TransitionGroupDocNode.Results` converted and the property removed (what survives is
`EmptyResults`, named for holding nothing, which says whether the node was built from
chrom infos - `HasResults` cannot become `AbbreviatedResults != null`, that broke
`TestMoleculeResultsMatchTransitionChromInfo`); `ChromInfos` renamed `LegacyChromInfos` on
both results classes, since it is populated only between reading a document and reading
its .skyd; precursor gained `StartTimes`/`EndTimes` and lost `Areas` (a precursor's area is
the sum of its transitions', and one number cannot answer the MS1 and MS2 sums separately);
precursor annotations became a plain `ImmutableList<Annotations>` and `CustomPeak` lost its
`Position`; `ReplicatePositions` became `IReadOnlyList<IEnumerable<int>>`; `ReplicateMap`
replaced by `ChromFileIdMap<T>`, which `TransitionResults` and `PeptideResults` now use.

Bugs found on the way, all fixed: `DocumentAnnotationUpdater.UpdateTransition` guarded on
`_precursorResultUpdater` instead of `_transitionResultUpdater`; the precursor wrote
annotations (child elements) before `transition_areas` (an attribute), which `XmlWriter`
refuses once an element has content; the generic three-argument
`WriteAttribute<TAttr>(name, value, defaultValue)` formats with plain `ToString()` and so
loses float precision - use `WriteAttributeNullable`; `GetSharedTransitionAreas` held a
*precursor* position and read a *transition* with it.

Test-result gotcha: the "N failures" column in the run summary is a **running total**, not
per-test. Count the `!!! ... FAILED` markers instead.

Still failing at baseline, unchanged by any of this: `TestColumnarResultsRoundTrip`
(`CheckUserSetPeakStillWritten`, line 206), `TestSaveColumnarResults`,
`TestMoleculeResultsWithUserSetPeakBounds` (5 surviving `ChosenPeakIndexes`),
`TestAnnotations`, `TestImportAnnotations`, `TestPeakBoundaryCompare` (MessageDlg timeout).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260728_chrominfo_memory.md` before starting work.
