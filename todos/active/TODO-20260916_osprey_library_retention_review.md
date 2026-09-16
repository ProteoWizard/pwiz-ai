# Library retention, rehydration and spectrum dropping need an end-to-end review

## Branch Information
- **Branch**: `Skyline/work/20260916_osprey_library_retention_review`
- **Checkout**: `C:\proj\pwiz-work1` (C:\proj\pwiz is occupied by open PR #4660)
- **Base**: `master` (at `7993a4ef55`, which includes #4662)
- **Created**: 2026-09-16
- **Status**: In Progress
- **GitHub Issue**: [#4650](https://github.com/ProteoWizard/pwiz/issues/4650)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

End-to-end review of library retention, rehydration and spectrum dropping, which are
spread across four stages with no single owner. A 446-run CHS job shows Stage 7 spends
**11 minutes and peaks at 41.5 GB** rebuilding every run to recompute a retained set
Stage 5 already computed and already persisted to disk, then releases **nothing**.

Not a correctness problem: output is correct and the run completed. This is memory
shape and wasted work.

### Evidence (from the issue)

446-run CHS cohort, straight-through Stages 5-7, 13.5 h.
Run directory: `D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-stages567-n4646`

```
04:07:44 (Stage 5)  Released library fragments for 4924513 of 6175389 entries
                    (625620 base_ids retained for rescore + gap-fill)
12:20:11 (Stage 7)  Released library fragments for       0 of 6175389 entries
                    (625620 base_ids retained for the reported pool)
```

Stage 7's `stage7-pool` is flat at 4.69 GB, so this is **not** the survivor pool
(#4486's streamed join is working). The spike is the first `StreamFiles` pass: 446 runs
rebuilt from their reconciled parquets one at a time and dropped, purely to collect
base_ids. Managed heap climbs 6.4 -> 36.2 GB with no collection, then one GC drops it to
5.4 GB — ~86% uncollected garbage, ~31 GB allocated to produce a 2.5 MB answer that was
already on disk.

## Review scope (from the issue)

1. Who owns the retained-base_id set, and can it cross a stage boundary in-process
   instead of being recomputed?
2. Is the reported pool provably a subset of the rescore+gap-fill set, or must Stage 7
   recompute?
3. Can fragment retention end before protein FDR, so only the blib write holds spectra?
4. On `--task SecondPassFDR`, can the library read skip unneeded spectra outright (the
   previously-dropped filter), now that the cost is a 41.5 GB peak rather than a 10 s load?
5. Does anything still need a reload at Stage 7 at all, and if so can it wait until just
   before the blib write?

## Shape of the fix (design call already recorded on the issue — do not re-litigate)

Stage 5 already persists the answer: `FirstPassFdrTask.WriteRetainedBaseIdSummary`
(`FirstPassFdrTask.cs:2276` -> `:2614`) writes `out.1st-pass.retained_base_ids.bin`
(2,502,512 bytes = 625,620 base_ids x 4 + 32-byte header on this cohort).
`ScoringTaskShared.ReadRetainedBaseIds` / `ReadRetainedBaseIdsOrFail` already read it
from four call sites.

* Replace the pool walk at `SecondPassFdrTask.cs:996` with
  `ScoringTaskShared.ReadRetainedBaseIdsOrFail(ctx.Config)`.
* **Delete** the `BuildRetainedBaseIds(IEnumerable<KeyValuePair<string, List<FdrEntry>>>)`
  overload — after the change its only remaining reference is a unit test.
* **Fail loudly when the sidecar is absent; do NOT fall back to the walk.** Osprey is
  pre-release, so there is no backward-compatibility burden, and an absent sidecar
  indicates Stage 5 output corruption; the remedy is re-running at least
  `--task FirstPassFDR`. Extend `ReadRetainedBaseIdsOrFail`'s `InvalidDataException`
  message to name that remedy.
* The sidecar is readable *before* the library load, so a `--task SecondPassFDR` leg can
  hand the retained set to `RetainFragmentsFor` — the hook that today has only a
  declaration and a pass-through and **nothing assigning it** — and never allocate the
  4.92 M spectra it would immediately release.

Precedent one function away: the doc on `ReadRetainedBaseIds` already says absence "is
FATAL to the caller and must not fall back to rebuilding the union from every run's
`reconciliation.json` ... precisely the O(files) pre-pass this artifact exists to
delete". Stage 7's pool walk is that same pre-pass in different clothes.

## The review: answers to the five questions

Read end-to-end on 2026-09-16 across `PerFileScoringTask` (the single library load),
`FirstPassFdrTask` (Stage 5/6 planning + its release), `Stage6Planner`,
`GapFillTargetIdentifier`, `RescoreHydration`, `PerFileRescoreTask` and `SecondPassFdrTask`.

### 1. Who owns the retained-base_id set, and can it cross a stage boundary?

`FirstPassFdrTask` owns it, and it already crosses both stage AND process boundaries.
Stage 6 planning accumulates it (`FirstPassFdrTask.cs:2197-2224`) and persists it through
`WriteRetainedBaseIdSummary` -> `RetainedBaseIdSidecar.Write`. Four call sites already read
it back. Stage 7's library-fragment release was the ONE consumer re-deriving it; the call
site was simply missed when the artifact landed (#4633). No in-process channel needed
inventing - the sidecar is strictly better, because it is also the only thing that works on
`--task SecondPassFDR`, where no in-process producer exists at all.

**Resolved by this branch.**

### 2. Is the reported pool provably a subset of the rescore+gap-fill set?

**Yes, by construction, and the doc that made it look unresolved was wrong.**

`LibraryFragmentRelease.BuildRetainedBaseIds` claimed gap-fill "resolves the MISSING charge
states of passing peptides, so by construction it names entries that did not survive
compaction". It does not. `GapFillTargetIdentifier.IdentifyFile`
(`GapFillTargetIdentifier.cs:216-260`) walks `_passingPrecursors` - a set of
`(ModifiedSequence, Charge)` keys collected from every file's POST-COMPACTION entries at
`config.Reconciliation.ConsensusFdr` - and emits a target for each key **absent from this
file's rows**. Same precursor, same charge, different file. So a gap-fill target's key came
out of some file's compacted entries, and its base_id is therefore already in the join-wide
first-pass set. "Did not survive compaction" is true of the file's ROW, never of the base_id.

Three things follow:

* the summary (`GlobalBaseIds` U action targets, and action targets index into the
  survivors so they add nothing) and the Stage 5 release set (`_firstPassBaseIds` U
  gap-fill) are the SAME set. The CHS run shows it: 625,620 on both lines and 625,620 in
  the 2,502,512-byte sidecar.
* the streamed Stage 7 join's `stubs.RemoveAll(!retained.Contains(...))`
  (`RescoreHydration.cs:922`) really does remove nothing, as its comment claims - it is not
  silently dropping gap-fill rows.
* Stage 7 reading the summary retains exactly what Stage 5 retained. On a straight-through
  run it is literally the same set applied twice to the same in-process library instance.

Doc corrected on the branch. The gap-fill union stays - it costs one pass over a short list
and the argument above is an invariant of another class - but nothing may be built on the
claim that it is strictly larger.

### 3. Can fragment retention end before protein FDR?

Yes in principle, and it already effectively does, so there is nothing to change. Only
`WriteBlibOutput` -> `BlibOutputWriter.PrecompressSpectra` reads spectra after Stage 6;
`RunProteinFdr`, `OspreyReportWriter.WriteReports` and the release itself read identity
only. And the release is already the FIRST thing Stage 7 does (`SecondPassFdrTask.cs:443`),
before pass-2 Percolator and protein FDR - so the window moving it later would shrink is
one in which the fragments are already gone.

### 4. Can the `--task SecondPassFDR` library read skip unneeded spectra outright?

The mechanism is fully built and **nothing assigns it**: `LibraryLoadOptions.RetainFragmentsFor`
-> `LibraryLoader.cs:111` -> `LibraryCache.LoadCache`, which skips the fragment block per
entry at the same cost `SkipFragment` already pays (`LibraryCache.cs:330`). The one place
that would set it is `PerFileScoringTask.LoadLibraryAndDecoys` (`:1031`), which today sets
only `OmitFragments`.

**Not wired here, deliberately - it is four problems, not one, and one of them is a
safety regression.** Recorded as a follow-up rather than carried silently:

a. **It trades the tripwire for silence.** `ReleaseSpectrum` installs `RELEASED_SPECTRUM`,
   a list that THROWS on every access, precisely so that a wrong belief about who reads a
   spectrum is loud (`LibraryEntry.cs:126-163`). The load-time skip leaves
   `Array.Empty<LibraryFragment>()`, which every scorer's
   `Fragments == null || Fragments.Count == 0` guard absorbs as "no spectrum" and scores a
   degenerate zero. Wiring the hook without first making the skip install the same sentinel
   would delete the safety argument the whole feature rests on.
b. **Decoy generation.** `DecoyGenerator`'s fragment-count gate (`DecoyGenerator.cs:254`)
   EXCLUDES a 0-fragment target, and it is skipped only under `omitFragments`. Under partial
   retention most targets look peak-less, so the generated decoy library would silently
   collapse. It does not bite the leg that matters - `--task SecondPassFDR` with generated
   decoys skips `DecoyGenerator` entirely (`PerFileScoringTask.cs:1082`) and the
   supplied-decoy arm reads no fragments - but it does bite `--task PerFileRescore`, which
   takes the same disk-load path and DOES generate decoys.
c. **The source-parse path ignores it.** `LibraryLoader` honours `RetainFragmentsFor` only
   on the cache-read arm; the from-source arm (`:209`) still applies `OmitFragments` only.
   A cold library would behave differently from a cached one.
d. **It reddens mode 6 for an honest reason.** `-RequireFreed` on the HPC SecondPassFDR node
   asserts a non-zero release count - the exact assertion that caught the original
   zero-saving defect. Under the skip that count legitimately becomes 0, because nothing was
   allocated. Keeping the gate's strength needs a NEW fact (the load reporting how many
   entries it skipped), not a loosened assertion.

Also worth weighing: with the Stage 7 fold gone, what this would still buy is smaller than
the issue assumed. The 41.5 GB peak was the pool fold, not the fragments. What remains is
the O(library) release walk (~1m54s at 6.18 M entries) and the transient allocation of the
4.92 M fragment arrays that are released moments later on the SecondPassFDR leg. Real, but a
separate piece of work with its own gate design.

### 5. Does anything still need a reload at Stage 7?

No, and there is no reload to defer: the library is loaded ONCE in Stage 1
(`PerFileScoringTask.LoadLibraryAndDecoys`), published as `FullLibrary`, and every task reads
that instance. The issue's "reload" framing came from the 41.5 GB spike, which was never a
library reload - it was the 446-run `StreamFiles` pass rebuilding every run's pool from its
reconciled parquet to read one `uint` per entry. Deleting that pass removes the spike.

### Observed, not fixed (out of scope for this branch)

* `docs/14-intermediate-files.md:36` says `<stem>.1st-pass.model.json` carries "the
  protein-compact stratum when that mode is active", while
  `docs/00-pipeline-architecture.md:1106` lists `<stem>.1st-pass.stratum.json` as a separate
  experiment-wide artifact split out of the model sidecar. One of the two is stale. The
  stratum artifact is also missing from the 14-intermediate-files tables.

## Tasks

- [x] Read the four stages end-to-end and answer review questions 1-5 in the TODO
- [x] Confirm whether the reported pool is provably a subset of the rescore+gap-fill set
      (yes, by construction - and the doc that said otherwise is corrected)
- [x] Replace the Stage 7 pool walk with `ReadRetainedBaseIdsOrFail`
- [x] Delete the `BuildRetainedBaseIds(IEnumerable<KeyValuePair<...>>)` overload
- [x] Extend the `InvalidDataException` message with the re-run remedy
- [ ] ~~Wire `RetainFragmentsFor` on the `--task SecondPassFDR` leg~~ - NOT done, and not an
      omission: it would trade the throwing released-spectrum tripwire for a silent
      `Array.Empty`, and three other things need settling with it. See review question 4;
      drafted as a follow-up issue.
- [x] Add the summary-equality assertion to `regression.ps1` mode 6
- [x] Document `retained_base_ids.bin` in `docs/14-intermediate-files.md` (it was in neither table)
- [x] Build + inspection + tests (`Build-Osprey.ps1 -RunInspection -RunTests`) - 595 pass, zero warnings
- [x] `regression.ps1 -Dataset Stellar` green (all modes, mode 6 over 8 legs)
- [ ] `regression-parallel.ps1 -Dataset All` green
- [ ] `/code-review max` before opening the PR
- [ ] Open the PR

## Regression Test

**Built-in oracle** (from the issue): any correct version must still log the same retained
count on both release lines and `Released ... 0 of N` at Stage 7 on a straight-through run.
Reproduced at 3 files, so no new comparison was needed - it became an assertion in the gate
that already parses those lines.

- **Test name**: `regression.ps1` mode 6, via `Test-LibraryFragmentRelease -MatchesSummaryScope`
- **Test project**: `pwiz_tools/Osprey/regression.ps1` (mode 6)
- **What it asserts**: on any leg that re-ran FirstPassFDR, Stage 7's retained count must
  EQUAL the count that leg's own `Wrote analysis-wide retained base_id summary: N base_id(s)`
  line reported. A Stage 7 that went back to folding the pool would report the pool's count;
  a Stage 7 reading anything else would report a third number. Relative, not absolute - both
  sides move together with any scoring change, so it does not cry wolf.
- **Fails on master**: not applicable in the usual red->green sense - on master the two
  numbers coincide, because the fold was recomputing the same set. What master does NOT have
  is any assertion tying Stage 7's set to its SOURCE, which is the gap. The renamed scope
  token is the part that goes red on master: mode 6 expects `the reported pool` there.
- **Passes on fix**: yes. `regression.ps1 -Dataset Stellar`, run 2026-09-16 07:13,
  mode 6 PASS over 8 legs. Log:
  `C:\Users\brendanx\AppData\Local\Temp\claude\C--proj\dde0f0cf-fa52-4c86-9b61-97f48a7f798b\scratchpad\regression-stellar2.log`

### Measured at 3 files

`C:\proj\pwiz-work1\pwiz_tools\Osprey\TestResults\regression-20260916_071352_38036\Stellar\straight\straight.log`:

```
Wrote analysis-wide retained base_id summary: 166724 base_id(s) across 3 run(s)
Released library fragments for 152180 of 485628 entries (166724 base_ids retained for rescore + gap-fill)
Released library fragments for      0 of 485628 entries (166724 base_ids retained for the 1st-pass retained set)
```

Same shape as the 446-run CHS evidence on the issue, and the `Collecting the reported
base_ids` progress line is gone entirely - that fold no longer exists.

The HPC SecondPassFDR node still performs a REAL release, which is what mode 6's
`-RequireFreed` exists to protect
(`...\Stellar\chain\logs\phase4.log`):

```
Released library fragments for 76117 of 242841 entries (166724 base_ids retained for the 1st-pass retained set)
```

242,841 rather than 485,628 because that leg skips decoy generation entirely
(`PerFileScoringTask.cs:1082`), so its library is targets only.

## Progress Log

### 2026-09-16 - Session Start

Starting work on this issue. Branch created in `C:\proj\pwiz-work1` off master
`7993a4ef55` (includes #4662, merged 2026-09-16 02:30 UTC). `C:\proj\pwiz` was left
alone because PR #4660 is still open there.

### 2026-09-16 - Review done, Stage 7 fold removed

Read the area end-to-end and answered all five questions (above). Implemented the recorded
design call and the doc corrections the review turned up.

**The fold was circular, which is stronger than the issue's framing.** Stage 7's streamed
join ALREADY reads the summary: `PerFileRescoreTask.BuildStage7PerRunSource` calls
`ScoringTaskShared.ReadRetainedBaseIdsOrFail`, and `RescoreHydration.RefillOneRunSurvivors`
filters every run's stubs through it (`RescoreHydration.cs:922`). The
`BuildRetainedBaseIds(rescored.StreamFiles(...))` fold therefore rebuilt all 446 runs
THROUGH that filter and collected the base_ids that survived it - recomputing a subset of a
set the same stage was already holding in memory.

Changes:

* `SecondPassFdrTask.ReleaseUnscorableLibraryFragments` reads
  `ScoringTaskShared.ReadRetainedBaseIdsOrFail(ctx.Config)`; the `rescored` parameter is gone
  with the fold.
* `LibraryFragmentRelease.BuildRetainedBaseIds(IEnumerable<KeyValuePair<string, List<FdrEntry>>>)`
  deleted, with its unit test.
* `ReadRetainedBaseIdsOrFail`'s message no longer claims the caller is the streaming join
  (two callers now) and names the remedy: re-run at least `--task FirstPassFDR`.
* `LibraryFragmentRelease.BuildRetainedBaseIds`'s doc corrected - see review question 2.
* Log scope renamed `the reported pool` -> `the 1st-pass retained set`, because the set no
  longer comes from the pool and a token that still said "pool" would assert nothing about
  where it came from. `regression.ps1` follows.
* `regression.ps1` mode 6 gains the summary-equality assertion.
* `docs/14-intermediate-files.md` gains the `retained_base_ids.bin` row - the artifact was
  in neither of its two tables despite being FATAL-if-absent at four call sites (five now).
* `docs/00-pipeline-architecture.md` notes Stage 7's release as a reader.

Gates: `Build-Osprey.ps1 -RunTests -RunInspection` green (595 tests, zero warnings);
`regression.ps1 -Dataset Stellar` green on every mode including mode 6 over 8 legs.
`regression-parallel.ps1 -Dataset All` and `/code-review max` running.

**Question 4 deliberately not implemented** - see the review section. Wiring
`RetainFragmentsFor` would trade the throwing `RELEASED_SPECTRUM` tripwire for a silent
`Array.Empty`, and three other things need settling with it. Drafted as a follow-up issue
rather than left as a declared-and-unassigned hook.
