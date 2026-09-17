# Library retention, rehydration and spectrum dropping need an end-to-end review

## Branch Information
- **Branch**: `Skyline/work/20260916_osprey_library_retention_review`
- **Checkout**: `C:\proj\pwiz-work1` (C:\proj\pwiz is occupied by open PR #4660)
- **Base**: `master` (at `7993a4ef55`, which includes #4662)
- **Created**: 2026-09-16
- **Status**: PR open, BLOCKED on cross-impl (see 2026-09-16 entry)
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
- [x] Fix the load-time skip to produce the RELEASED state, both load arms, with a
      red-checked equivalence test (Brendan's call - it was written wrong, not merely
      unwired)
- [ ] ~~ASSIGN `RetainFragmentsFor` at the library load~~ - still deferred, now for two
      concrete blockers rather than four: `DecoyGenerator`'s fragment-count gate on the
      `--task PerFileRescore` leg, and mode 6's `-RequireFreed` needing a skipped-at-load
      fact once nothing is allocated
- [x] Triage `/code-review max` - 15 findings, 3 confirmed defects in this change, fixed
- [x] Add the summary-equality assertion to `regression.ps1` mode 6
- [x] Document `retained_base_ids.bin` in `docs/14-intermediate-files.md` (it was in neither table)
- [x] Build + inspection + tests (`Build-Osprey.ps1 -RunInspection -RunTests`) - 595 pass, zero warnings
- [x] `regression.ps1 -Dataset Stellar` green (all modes, mode 6 over 8 legs)
- [ ] `regression-parallel.ps1 -Dataset All` green
- [ ] `/code-review max` before opening the PR
- [ ] Open the PR

## Regression Test

**Built-in oracle** (from the issue): a correct version must still log the same retained count
on both release lines and `Released ... 0 of N` at Stage 7. Reproduced at 3 files, so it became
an assertion in the gate that already parses those lines rather than a new comparison.

- **Test name**: `IOTest.TestLibraryCacheRetainMatchesRelease` (unit) + `regression.ps1` mode 6
  (`Test-LibraryFragmentRelease -MatchesSummaryScope`)
- **Test project**: `Osprey.Test` and `pwiz_tools/Osprey/regression.ps1`
- **Fails on master**: YES for the unit test - red-checked by disabling the single
  `entry.ReleaseSpectrum()` call in `LibraryCache`, which fails it at `entry 2 (id 11)`. The
  mode 6 oracle is relative rather than red/green on master: master has no assertion tying
  Stage 7's set to its SOURCE, which is the gap; the renamed scope token is the part that
  reddens there.
- **Passes on fix**: YES. 596 unit tests; `regression-parallel.ps1 -Dataset All` **70 PASS /
  0 FAIL / 0 SKIP** (45:13), mode 6 green on all four datasets with the #4650 count oracle
  evaluating on 4/4/2/2 legs.

What mode 6 now asserts, on every leg that runs the Stage 7 release: Stage 7's retained count
equals the count that leg's summary write reported; Stage 5's retained count is not GREATER
than it (a direction, because the relationship is documented as asymmetric); and Stage 7
releases 0 wherever Stage 5 released in the same process. It reports how many legs the oracle
evaluated on, and a run where it evaluated on none is a failure.

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

### 2026-09-16 - Q4 reopened on Brendan's call: the load-time skip was written wrong

Brendan's direction, which changed the answer to review question 4: *"The load time skip
should be changed to set to released state ... The goal is a direct swap for load all and
then release for simply loading only the spectra needed. Therefore, the load of only spectra
needed should produce exactly the same state as load and release."*

That is right, and it turns the blocker into a defect with a fix rather than a reason to
defer. **`RetainFragmentsFor` has no other use** - two references, a declaration and a
pass-through, nothing assigns it - so the behaviour could be corrected with no risk to
anything in production.

* `LibraryCache.LoadCache` now calls `entry.ReleaseSpectrum()` on an entry skipped by the
  retain set, instead of leaving it holding `Array.Empty`. `OmitFragments` is deliberately
  NOT included: that arm has no load-and-release counterpart to match, since
  `LibraryFragmentRelease` refuses the `StopAfterStage5` leg outright.
* `LibraryLoader`'s SOURCE-parse arm honoured the retain set **not at all** - it read
  `OmitFragments` only. The same options object therefore produced a lean library from a
  cache and a fat one from source, i.e. the presence of a `.libcache` decided which
  expressions throw. It now releases after the cache save, reaching the same state.
* `IOTest.TestLibraryCacheRetainMatchesRelease` pins the equivalence entry by entry:
  identity fields, `IsSpectrumReleased`, the fragment arrays on retained entries, and an
  explicit assertion that a skipped spectrum THROWS rather than reading as empty (equality
  alone would also hold if both sides had quietly become readable-empty).

**Red-checked, not just green.** Disabling the single `ReleaseSpectrum()` line fails the new
test at `entry 2 (id 11)`; restoring it passes. 596 tests, inspection zero warnings.

Still NOT wired at `PerFileScoringTask.LoadLibraryAndDecoys`. The hook is now correct and
tested, but assigning it is a separate change with two live blockers: `DecoyGenerator`'s
fragment-count gate excludes a 0-fragment target and is skipped only under `omitFragments`,
so `--task PerFileRescore` (which takes the same disk-load path and DOES generate decoys)
would be wrong; and mode 6's `-RequireFreed` on the HPC SecondPassFDR node legitimately goes
to 0 once nothing is allocated, which needs a new log fact rather than a loosened assertion.

### 2026-09-16 - /code-review max: three confirmed defects in this branch's own change

15 findings at the cap. Triaged, verified against the code, fixed or dropped - none filed.

**Confirmed and fixed:**

1. **`ReadRetainedBaseIdsOrFail` was unconditional.** The summary is written only when
   `Reconciliation.Enabled` (the `PlanStage6` gate) AND an output blib names it. Neither
   term is in `RunsOnThisLeg`, so a straight-through run with reconciliation off would now
   ABORT at the last stage where it previously completed, after all the scoring work. Fixed
   with `LibraryFragmentRelease.SummaryCanExist`, checked at the Stage 7 call site - NOT
   folded into `LegAdmitsRelease`, which would also switch off Stage 5's release, the one
   that needs no file. Costs nothing: a leg reaching Stage 7 without a summary is
   straight-through by construction (`--task FirstPassFDR` is refused outright when
   reconciliation is off), and there Stage 5 already released the same set in process.
2. **A zero-count summary read back as success.** `RetainedBaseIdSidecar.Read` returns an
   empty `HashSet` rather than null for a zero count, and `ReleaseFragments` has no
   empty-set guard - so an empty summary releases the spectra of the ENTIRE library, and the
   blib write then trips the tripwire. Reachable from disk state, not only from a bug: this
   class already documents a re-run-over-a-completed-directory shape that "rewrites both
   boundary sidecars and the retained base_id summary as empty, exit 0". Empty is now a
   failure in the `OrFail` reader, which covers all three of its callers.
3. **The remedy in the recorded design call does not work.** The issue asked for the message
   to say "re-run at least `--task FirstPassFDR`". It cannot: that task declares the summary
   in neither `Outputs` nor its `ValidityKey` - deliberate, with its own rationale, so that
   `--task ModelDiagnostics` on a finished cohort does not re-run Stage 1-5 for hours - and
   `FirstPassFdrTask.cs:947-950` says so outright: *"re-run FirstPassFDR over a complete
   analysis reports its outputs valid and writes nothing."* An operator following it would
   loop forever. The message now names the `<output>.FirstPassFDR.osprey.task` stamp
   deletion that actually forces the phase to re-run.

**Also fixed:** the summary declared in `SecondPassFdrTask.Inputs` (an HPC orchestrator
building a node's shipping list from `Inputs` would omit it and fail at the top of Stage 7);
the shared throw text no longer asserting the streamed join's consequence for both callers;
two surviving copies of the retracted gap-fill claim (`FirstPassFdrTask`'s own release doc
and the unit test's); the `CanStreamStage7Join` comments that cited the fragment release as
the concrete first-streamer, which it no longer is; `Regression/README.md`'s mode-6 contract;
and the doc row's over-promise ("FATAL at every one of them" is false for
`PerFileRescoreTask.BuildPerRunHydrate`, which takes the null-returning reader).

**Gate hardening, all from review findings:**

* The oracle was armed only on the two legs where the release is a guaranteed no-op, and
  silently absent from the HPC SecondPassFDR node - the leg where the 11 minutes / 41.5 GB
  was actually measured - because an omitted hashtable key binds to `''` rather than
  erroring. Now armed on every leg that runs Stage 7's release, taking the producer count
  from `phase2.log` where the producer is a different process.
* It failed OPEN when the scope was missing (`elseif ($scoped.Count -gt 0)`): delete Stage
  7's release and the check simply was not reached. Missing scope is now its own issue.
* `Select-String -Path` globs, unlike every other file access in the function; a run dir
  holding a PowerShell metacharacter would have reported a harness quoting bug as a C#
  wording drift. Now `-LiteralPath`.
* The equality alone was nearly vacuous - Stage 7 logs the `Count` of the set it just read
  from the file just written. Two more assertions now carry the real claims: Stage 5's
  retained count must equal the summary's (the same-set claim the whole change rests on),
  and Stage 7 must release 0 wherever Stage 5 released in the same process (the issue's own
  quoted oracle). Not asserted on the HPC node, where the release is real.
* Both gate regexes accepted separator-free counts only, so the log-readability sprint's
  `{0:N0}` would have reddened mode 6 blaming C# drift. Both now take `[\d,]+`.
* Mode 6's PASS line reports how many legs the oracle actually evaluated on, and a run where
  it evaluated on none is a failure. A gate that cannot say it asserted something is how an
  oracle wired to the wrong key goes unnoticed.

**Dropped, with the reason:** the finding that the rewritten log line should adopt the
decided user-facing vocabulary (`{0:N0}`, "precursor candidates" for "base_id(s)", no
"entries", no "fold"). Applying it to this one line while its Stage 5 sibling keeps the old
wording is worse than applying it to neither, and it would move the gate token a second
time. The actionable half - the regexes that would have collided with `{0:N0}` - is fixed
above, so the sprint can do the whole vocabulary in one pass without a collision.

### Observed and fixed on Brendan's call

`docs/14-intermediate-files.md:36` said the protein-compact stratum rides in
`.1st-pass.model.json`, contradicting `00-pipeline-architecture.md`. Brendan: *"Likely
00-pipeline is correct. It is the newer document. I think the split you are describing
happened when it was discovered that 50% of the original file was highly redundant
experiment-wide values."* Confirmed in `FirstPassModelIO.cs:56-64` - the stratum moved to
its own file because a different PHASE produces it, and writing one file meant holding the
model in memory for the whole first pass, which made a run killed in the score passes
unrecoverable. Doc 14 corrected, and `.1st-pass.stratum.json` given its own row: it was
missing from both of that document's tables, as was the retained-base_id summary.

### 2026-09-16 - Full gate green, then a SECOND review round at a higher triage bar

`regression-parallel.ps1 -Dataset All`: **70 PASS / 0 FAIL / 0 SKIP in 00:49:21**, all four
datasets. Mode 6 green everywhere, and the #4650 count oracle provably fired rather than
being silently skipped - Stellar and StellarLibDecoy `PASS (8 leg(s), oracle on 4)`, Astral
`(6 leg(s), oracle on 2)`, StellarGenDecoyEntrap `(2 leg(s), oracle on 2)`.

Brendan then called for a second review round with a raised bar: *"The cycle has proven that
addressing everything pays a penalty in introducing new defects. To ever get out of this
cycle, the implementing session needs to pay attention to risk:benefit and not just is the
finding true."*

**The result is the evidence for that.** Round 2 returned 15 findings again - the reviewer's
cap - and SIX of them trace directly to round-1 fixes. Truth was never the filter: a `max`
review verifies before reporting, so "is it true" excludes almost nothing. The filter has to
be expected cost of leaving it against expected cost of the fix, and the second term is
largest for exactly the findings that look most actionable - new predicates and changes to
SHARED readers. Both of round 1's cheapest-looking fixes were its worst trades.

#### The bar applied

* **Fix - serious**: wrong answer, silent loss of a guarantee, or an abort on a path that
  previously worked, AND the fix is local and provable.
* **Fix - free**: comment or doc only, no executable change, and the text would actively
  mislead someone changing that code.
* **Revert**: the change is not carrying its risk. Preferred over patching it.
* **Drop**: true but minor, or the fix buys less than it risks. Recorded, never filed.

#### Fix - serious

* **`SummaryCanExist` does not fix what it was added for, and still aborts working runs.**
  `Reconciliation.Enabled` defaults true and Stage 7 always has an output blib, so the
  predicate is ALWAYS true on the legs that matter - it excludes only configurations that
  could not reach Stage 7 anyway. Meanwhile a straight-through resume over a directory whose
  summary is absent or a stale `FormatVersion` now dies at the last stage, where the fold it
  replaced needed no file. Fix is SMALLER than what it replaces: delete `SummaryCanExist`,
  use the existing disk-aware `ScoringTaskShared.PerRunSurvivorLoaderAvailable`, hard-fail
  only on `ExpectReconciledInput` (where Stage 7's release is the only one) and skip with a
  warning elsewhere. Resolves the ValidityKeySuffix divergence too - the suffix stays
  accurate exactly where the skip can happen - and moots the null-deref finding. Three
  findings, one deletion.
* **Revert the empty-summary guard.** It traded a rare catastrophe for a rare legitimate
  case: zero survivors genuinely writes an empty summary, and the pipeline already handles
  that gracefully ("No entries pass FDR threshold. Creating empty blib.") ~800 lines AFTER
  the release now made to throw - and the remedy the message prescribes regenerates the
  identical zero-count file. In the only reachable empty case, releasing everything is
  CORRECT, which is also why the related finding about Stage 5 guarding on null only is not
  a defect.
* **`Select-String -LiteralPath` on the summary log is unguarded.** Under the script's
  `$ErrorActionPreference='Stop'` a missing log is a terminating error, so it kills the whole
  regression run rather than failing mode 6. One `Test-Path`.

#### Revert - the highest-value call of the round

**Drop the `LibraryLoader` source-parse arm; keep the cache arm and its test.** Brendan asked
for the load-time skip to produce the released state - that is the cache arm, it is correct,
and `IOTest.TestLibraryCacheRetainMatchesRelease` covers it. The source arm was added beyond
that ask and is WRONG: it masks `entry.Id` before `LibraryDecoyPairing` reassigns those ids,
so under `--decoys-in-library` it releases the wrong entries. It is also unreachable and
untested. Removing it deletes three findings and a doc contradiction without a line of new
logic.

#### Fix - free

Gate assertion direction (`-le`, not `-ne`) with a corrected message, since the C# documents
the relation as asymmetric and the current form reds in the SAFE direction while describing
the opposite failure; attributing the 625,620 figure to its run rather than implying it
supersedes the pre-existing 744,943; naming the `LibraryDeduplicator` grouping-key dependency
the gap-fill subset claim rests on; correcting this branch's own gate comment about what the
oracle catches; the vacuous `-gt 0` term.

#### Dropped, with reasons

* `_perFileGapFillForRescore = null` one line before the release reads it (verified, and
  pre-existing) - harmless under the subset invariant, and loud rather than silent if that
  invariant is ever violated.
* Declaring the summary in three more tasks' `Inputs` - verified that `Inputs` is provenance
  only (`TaskValiditySidecar.IsValid` keys on `validity_key` alone, inputs are recorded but
  never compared), so this buys nothing and is scope creep.
* Duplicate failure messages for one defect - cosmetic.
* An empty-set guard on the cache retain arm - unreachable while nothing assigns the option.
* Em-dash style, `{0:N0}` culture, and the sub-cap list.

#### Correction to an earlier claim in this TODO

The Stellar measurement does NOT evidence the gap-fill subset claim on the straight-through
leg, because `_perFileGapFillForRescore` is null there - Stage 5's set is `_firstPassBaseIds`
alone on that path. The claim still stands on the code-reading argument
(`GapFillTargetIdentifier` draws its keys from post-compaction entries) and on the rehydrate
leg, where the field is set from the bundle. The evidence was overstated.

### 2026-09-16 - The title decides the scope: Load&Pair&Write folded in

Brendan, asked whether to split the cache redesign out: *"What does the title of #4650 tell us
about the scope of the issue?"* It is **"Library retention, rehydration and spectrum dropping
need an end-to-end review"**, and the body says outright it is *"an ask for an end-to-end
review of that area, not a request to fix the one symptom."*

A library cache that stores a half-built library - no pairing, incomplete `IsDecoy`,
non-final ids - IS a library-retention design defect, and it is the reason spectrum dropping
could not address half the rows. Deferring it would have scoped the issue down to the symptom
it explicitly says not to scope down to. Folded in.

**Brendan's framing, which was better than the one it replaced.** Mine was "stamp final ids
into the cache", which treats the symptom. His: *"poor design to make the library cache not
include the decoy pairing information ... the library cache not being updated to make it truly
a cache of everything that is considered 'the library', which it should be ... one that
included, inside the encapsulation, Load&Pair&Write instead of having Load&Write...Pair where
the caller is responsible for applying the pairing."* Likely history: pairing arrived with
Carafe-predicted decoys, after the cache's contract was set, and was bolted onto the caller.

#### What moved

* `MarkSuppliedDecoys` and `TryPairSuppliedDecoys` moved out of `PerFileScoringTask` into
  `LibraryLoader`, ahead of `SaveCache`. No new project reference: `LibraryDecoyPairing` is in
  `Osprey.Core` and `DecoyPairingManifest` was already in `Osprey.IO`.
* Only PAIRING moved, not GENERATION. `DecoyGenerator` is in `Osprey.Scoring`, which
  `Osprey.IO` cannot see - and does not need to: for generated decoys the cache holds targets
  only, whose ids are already final, so the retain filter was correct there all along. It is
  exactly the supplied-decoy case that was broken and exactly the half that can move cleanly.
* **Cache key widened to a composition hash**: library identity + decoy mode + prefixes +
  MANIFEST identity (name/size/mtime). Required, not tidiness - the cached bytes now carry the
  manifest's accessions, so a cache built under one manifest would otherwise be reused under
  another and silently feed the first manifest's accessions to protein parsimony and FDR.
* **`LibraryCache.VERSION` 2 -> 3.** A v2 file is not a stale v3, it is a different thing;
  read as v3 it would hand every consumer parse-order decoy ids.
* **A real failure channel.** The two pairing faults (no decoys matched; paired fraction under
  threshold) set `ExitCode = 1` at the caller; they now return as `error` and the caller
  reports them with the same messages and the same exit code.
* A cached load recovers and logs the pairing fraction from the finished library, so a cached
  run is not silent about it.
* **`RetainFragmentsFor` wired for `--task SecondPassFDR`** - correct at last, because cached
  ids are now final and a target's paired decoy shares its base_id.

#### Does this invalidate existing pipeline results? No - verified

Brendan: *"How do the tasks decide whether the library is the one their existing results are
from? ... e.g. it always stored a pointer to the true library and pairing manifest instead of a
pointer to the library cache."* That is exactly what it does. `LibraryIdentityHash()` is the
SOURCE library's name/size/mtime, and its three consumers are the task validity key
(`OspreyTask.cs:181-182`) and the parquet footer stamps (`PerFileScoringTask.cs:247-248`,
`ReconciledParquetWriter.cs:199-200`), checked by `ParquetScoreCache.cs:2074-2075`. Nothing
anywhere points at the `.libcache`. The new `LibraryCompositionHash` has ONE consumer: the
libcache header.

So no override is needed. The first run rebuilds the `.libcache` once and every parquet,
sidecar, blib and task stamp stays valid.

Two notes that fell out of checking:

* **Operational**: the `.libcache` lives in `--cache-dir` and is shared across every run on
  this machine, including other branches' exes. An old exe rejects a v3 file and rebuilds v2,
  and vice versa, so an A/B across binaries thrashes it and each side pays a reparse. Warm the
  cache before timing anything.
* **Pre-existing gap, now half-covered**: `SearchParameterHash()` includes the pairing
  manifest's PATH, not its contents (`SearchIdentity.cs:107-109`). Editing a manifest in place
  changes no search hash, so already-scored parquets stay "valid" against it. The composition
  hash catches it for the library; the parquets are still exposed. Same shape as the defect
  just fixed - an input that decides the answer not being in the key that admits the reuse.

#### The gate caught a real defect in the wiring

`-Dataset All`: 69 PASS / 2 FAIL. Both failures one defect, in the `RetainFragmentsFor`
wiring rather than the move - **mode 11 cell B2** (`--task SecondPassFDR`, pass-2 diagnostics
product absent) exited 1 in 2.2 s. Reproduced with `-KeepOutput` rather than guessed:

```
Skipped library fragments for 654744 of 968394 entries at load (156832 base_ids retained...)
[ERROR] Pipeline failed: These library fragments were released after Stage 5 ...
   at LibraryEntry.ReleasedFragmentList.get_Count()
   at PerFileScoringTask.LoadLibraryAndDecoys(...)
```

`LoadLibraryAndDecoys` runs a sub-3-fragment diagnostic over the WHOLE library, guarded only
by `!omitFragments` - the same all-or-nothing assumption `DecoyGenerator`'s fragment-count gate
makes, and true only while `OmitFragments` was the single lean mode. Guard widened to
`!omitFragments && loadOptions.RetainFragmentsFor == null`. Swept for other sites: only
`DecoyGenerator`, which is mutually exclusive with the retain set by construction
(`RetainFragmentsFor` is set only under `ExpectReconciledInput`, whose arm skips generation).

**The tripwire is why this was a stack trace and not a wrong number.** It exists only because
of Brendan's earlier call to make the load-time skip install `RELEASED_SPECTRUM` rather than
`Array.Empty`; with the empty state this site would have counted 654,744 entries as
zero-fragment and reported a nonsense distribution instead of failing.

**And mode 11 is why it was caught at 3 files instead of on the 446-run bed.** It is the only
leg presenting `--task SecondPassFDR` re-entering a completed run with one product withheld;
modes 1, 2, 3, 5 and 7 all pass straight through the defect.

Byte parity of the move itself is clean: `mode1 (vs golden)` PASS on all four datasets, plus
mode 3 (HPC chain == straight-through) and the `mode1b` diagnostics goldens.

### 2026-09-16 - CHS measurements, and a MERGE BLOCKER that is not this branch's

#### CHS 446-file, `--task SecondPassFDR --model-diagnostics` (the issue's own bed)

Bed: `chs-446files-libdecoy-r1.0-protein-compact4650-secondpass`, a `-LinkThroughTask` mirror
of `...compactmdiagregen2` (8,028 staged artifacts) presented as mode 11's **cell B2** - pass-1
report present, pass-2 JSON and HTML absent. The first attempt staged NO diagnostics products
at all (they are in no stage's list) and Osprey correctly refused in 0 s: pass-2 enriches
pass-1, and pass-1 was missing. That refusal is cell B, which the gate already covers.

Warm-cache run, `run.log`:

```
Loaded 6175389 library entries from cache            (14 s)
Skipped library fragments for 4924513 of 6175389 entries at load
                             (625620 base_ids retained for the 1st-pass retained set)
Second-pass join: folding over 446 run(s) ... (625620 retained base_id(s) read once)
[TASK] SecondPassFDR:done (505.9s)   ->  8m25s total
```

* **4,924,513** skipped at load - the exact count Stage 5's release used to FREE. Never allocated.
* **No `Collecting the reported base_ids` line anywhere.** The 11-minute, 41.5 GB fold is gone.
* Cold first run (v3 cache rebuild) was 14m22s: 85 s TSV parse + pairing + a 2.06 GB cache write.
  Pairing inside the load held on the real cohort: `paired 3085757/3087385 decoys (99.9%)`.

#### Three-way library load, same warm cache, `OSPREY_LIBRARY_LOAD_ONLY`

| leg | load | shape |
|---|---|---|
| `PerFileScoring` | **14.58 s** | every fragment - what SecondPassFDR used to do |
| `FirstPassFDR` | **9.22 s** | `OmitFragments`, no fragment arrays |
| `SecondPassFDR` | **10.00 s** | `retainSet=625620` |

All three read 6,175,389 entries. The retained-set load recovers ~79% of the gap to the
omit-everything floor, which is the expected shape when 4.92 M of 6.18 M fragment blocks are
skipped but every entry still pays identity scalars, interning and protein IDs.

Bed for this: `_libload-4650`, holding ONLY the retained summary. Two preconditions, both
learned by getting them wrong and now asserted in the script: the cache must be warm (a cold
one charges the first leg a 6.2 M-entry reparse) and the bed must present UNFINISHED work (a
completed one logs `skipping (outputs valid)`, Stage 1 never runs, and three sub-second no-ops
look like a result).

#### MERGE BLOCKER: cross-impl is RED, and it is red on master too

`Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files Single`, Rust at
`fix/experiment-q-per-entry-not-per-file` 90c8968 (= merged maccoss/osprey PR #67):

| check | this branch | master `7993a4ef55` |
|---|---|---|
| precursors | 26659 = 26659, delta 0 | same |
| blib content (SQL 1e-9) | PASS | PASS |
| Stage 7 protein FDR | **FAIL** | **FAIL** |
| FDR sidecars | **FAIL** | **FAIL** |

**A/B settles authorship**: identical failure on master at this branch's own base commit, with
the identical C# blib size (19,550,208 both). Not this branch.

Per-column, the failure is narrow:

```
best_peptide_score   PASS  max_diff=1.599e-014   n_diverg=0/3258
group_qvalue         FAIL  max_diff=3.058e-004   n_diverg=18/3258
  first-diverg: sp|O00443|P3C2A_HUMAN  rust=0.0003058103975535168  cs=0
n_unique / n_shared / is_target_winner   PASS
Keys only in Rust: 5+   Keys only in C#: 0
```

Scoring agrees to 1e-14 and parsimony agrees row for row. What diverges is the protein GROUP
q-value - C# assigning exactly 0 where Rust assigns a small positive value on 0.55% of groups -
plus a handful of groups C# does not emit at all. That is not compounding arithmetic drift, so
the gate's own advice ("drift compounds beyond 1e-9 ... use the per-stage gates to localize")
points at a bisection that will find nothing. Widening the comparator would paper over it.

**Brendan's call: this PR does not merge until cross-impl passes**, and a parity branch/PR in
`maccoss/osprey` has to land first so the fix can be confirmed not to make things worse.
*"Allowing changes to continue past a failing test is more likely to add new failures than
passing all tests."*

**RESOLVED - it is a PORT, not an investigation.** Brendan has already reviewed and signed off
the pwiz Osprey side: C# is correct, Rust needs the same change. The change is how the
**run-level minimum floor for a precursor q-value reaches the protein level**. The floor used
to be applied LATE (a re-clamp mutating the entries feeding the blib); it is now applied at the
SOURCE, so the floored experiment q reaches protein FDR's **detected-peptide gate**
(`ProteinFdr.cs:883`), which shrinks parsimony's input. Principle, measurement (1,125,526 of
593,865,660 values raised, 0.1895%) and sign-off are in
`ai/todos/completed/TODO-20260912_osprey_coassignment_allocation.md`.

That explains the cross-impl signature exactly: Rust's gate still admits peptides C# now
excludes, so Rust emits groups C# does not (`Keys only in Rust: 5+`, `Keys only in C#: 0` -
one-directional, matching "groups drop, never rise") and the overlap differs on group q. Do NOT
re-open which side is right, and do NOT widen the comparator.

#### Two harness traps worth keeping

* The cross-impl gate resolves the C# exe from `Get-PwizRoot` = `C:\proj\pwiz` unless
  `$env:PWIZ_ROOT` is set. It refused here only because that tree's Release build was from
  2026-08-30; had it been fresh, the comparison would have run happily against the WRONG
  CHECKOUT. Same failure mode as `/code-review` picking the wrong repo. Always set
  `$env:PWIZ_ROOT` to the checkout under test.
* `maccoss/osprey`'s default branch is `main`, not `master`, and the local checkout sits on the
  feature branch with a stale `origin/main`, so `90c8968` reads as "1 ahead of main" when it is
  in fact merged as PR #67.

#### PR and TeamCity

* **PR [#4679](https://github.com/ProteoWizard/pwiz/pull/4679)** opened 2026-09-16, marked
  **DO NOT MERGE YET** at the top of the description.
* TeamCity Perf/Regression queued: build **4177549**, `pull/4679`, MacCoss TeamCity Agent 1.
  Do not re-trigger without asking.
* No `Reported by` line: #4650 was authored by Brendan, a developer of this project, which the
  crediting rules explicitly exclude.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260916_osprey_library_retention_review.md` before starting work.

### 2026-09-16 - Goal 2 for tonight: key the pairing manifest correctly, and prove it

Brendan put this IN SCOPE for #4679 rather than deferring it, and framed it as an experiment
rather than a cleanup:

> I definitely want the key for the manifest use the same principles as the library TSV and not
> to use the full path because that is somehow seen as more compatible with the Rust
> implementation. ... To prove the key can be filename,size,mtime and not full path. And our
> original reason for looking at cross-impl proven: either the correct key makes no difference
> to the cross-impl comparison, or then there is a second fix that needs to go into the PR for
> maccoss/osprey.

`SearchIdentity.cs:106-109` keys the manifest on its FULL PATH, with `EscapeForRustDebug`
existing specifically to reproduce Rust's `{:?}` on a `PathBuf` (Rust writes the same term at
`crates/osprey-core/src/config.rs:512`). So "the path form is more Rust-compatible" is the
stated justification, and it is what gets tested. The behaviour it produces today is backwards:
the comment says "a moved manifest invalidates the cache", while an in-place EDIT does not - so
every scored parquet stays valid against a manifest whose contents changed, and the manifest
decides decoy classification, pairing and the protein accessions protein FDR runs on.

Target: file NAME + size + mtime, the same recipe as `LibraryIdentityHash()`. The no-manifest
case must keep emitting exactly `None` so generated-decoy beds do not invalidate.

Both outcomes are results: if cross-impl is unaffected (likely - each implementation runs in its
own workdir and neither reads the other's artifacts, so a differing `search_hash` has nothing to
compare against) the change lands in #4679 alone; if it IS affected, a second fix joins the
floor port in the `maccoss/osprey` PR. Prove which, do not assume.

Cost: manifest-using beds (CHS, SEA-AD libdecoy, StellarLibDecoy) invalidate once and re-score.
`regression.ps1` stages its own beds so the gate only pays a slower first leg; re-running the
446-file CHS bed is the 13.5 h shape and needs asking first.

### 2026-09-17 (night session) - GOAL 1 DONE: the floor port cleared cross-impl, and #4679 needed nothing

**Result: `Compare-EndToEnd-Crossimpl.ps1 -Dataset Stellar -Files Single` is GREEN** - all three
legs, on the branch's own C# Release build, against Rust
`fix/experiment-q-floor-before-consumers` @ `42f40ea`:

```
Stage 7 protein FDR (per-col 1e-9): PASS
Blib content (SQL row+col 1e-9):    PASS
FDR sidecars (per-field 1e-9):      PASS
OVERALL: PASS -- bit-parity at 1e-9 on Stellar 1-file   (Rust 01:47, C# 01:28)
```

**Nothing in #4679 was touched.** The expectation the handoff recorded held: Rust-side changes
alone clear the gate.

#### The root cause, in one line

Rust ran `clamp_experiment_q_to_best_run` at the END of the pipeline - `pipeline.rs:6043`,
**after** the protein-FDR block - so protein parsimony's detected-peptide set,
`effective_experiment_qvalue(peptide_gate_level) <= experiment_fdr`, read the RAW experiment q
while C# has read the floored one since #4662. That is exactly the one-directional signature the
handoff predicted from the failure text: Rust admitted peptides C# excludes, so Rust had protein
groups C# did not emit and none the other way.

#### The correction took two placements, and the second one is the actual lesson

The first move put the clamp just before protein parsimony but still AFTER
`persist_fdr_scores(..., "2nd-pass", 2)`, on the reasoning that the per-file sidecar should keep
the unfloored competition q. Stage 7 and the blib went green; the **sidecar leg stayed red and
named the residue precisely**:

```
2nd-pass sidecars: FAIL (2 issue(s), 292833 record(s) compared)
  experiment_precursor_qvalue differs on 1312 record(s); first entry_id=23  rust=0.00043005 -> cs=1
  experiment_peptide_qvalue   differs on 1769 record(s); first entry_id=23  rust=0.00043005 -> cs=1
```

`cs=1` is a floored value - an entry with no surviving run support. So the C# artifact the
comparator joins against (the analysis-wide experiment-scope file, per
`Compare-FdrSidecars-Crossimpl.ps1`) carries the FLOORED q. Which is what "apply the floor at the
source" says on the tin: the C# pass-2 sweep raises the q-values **before the records are
written**. The first placement ported the destination and not the timing.

Second placement - clamp ahead of `persist_fdr_scores` as well - made all three legs pass. Rust
fuses run and experiment scope into one per-file record where C# splits them, so "before they are
written" is a single call site on the Rust side rather than two.

#### Why this is a port and not an accommodation

The clamp only ever RAISES a q-value. Moving it earlier is one-directional in both directions it
now reaches: protein groups drop out and none appear, and a persisted experiment q rises and never
falls. That is the same conservative direction the four C# protein goldens were recaptured in.

It also fixes a second, independent defect on the Rust side that had nothing to do with
cross-impl: the 2nd-pass sidecar is read unconditionally by Stage 7 (`--join-at-pass=2`), so a
distributed or resumed Rust run took its experiment q from records the straight-through run
corrected only in memory. The persisted and in-process values disagreed about the same analysis.

#### Rust gates and rebaseline

`Build-OspreyRust.ps1 -Fmt -Clippy -RunTests` green on both placements. **No Rust
expected-output rebaseline was needed** - `cargo test` is unchanged - which is worth stating
explicitly because the handoff flagged a Rust-side rebaseline as an expected possibility.

One thing checked and deliberately NOT changed: the second `persist_fdr_scores(..., "2nd-pass")`
at `pipeline.rs:5337` (the missing-sidecar HPC-chain path) runs immediately after
`run_percolator_fdr`, whose own terminal clamp already applies, so those records are floored too.
Only the non-default Mokapot / Simple arms of that branch would write unfloored values.

#### Commit

`maccoss/osprey` branch `fix/experiment-q-floor-before-consumers`, commit `42f40ea`, based on
`origin/main` `9e4edaf` (the squash of PR #67). NOT pushed yet.

**Note on the commit trailer**: it carries `Co-Authored-By: Claude <noreply@anthropic.com>`.
Recent upstream commits (#59-#67) carry no trailer and the osprey skill says Skyline's format does
not apply to maccoss/osprey, but `Deny-HarnessAttribution.ps1` refuses a message without it and
its `PWIZ_ALLOW_HARNESS_ATTRIBUTION=1` escape hatch is not reachable from inside a tool call
(the hook runs before the command's environment exists). Amend before opening the PR if the bare
upstream form is wanted - the commit is local.
