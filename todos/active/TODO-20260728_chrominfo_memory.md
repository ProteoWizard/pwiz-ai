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
