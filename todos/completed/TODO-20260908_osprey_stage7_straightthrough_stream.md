# TODO-20260908_osprey_stage7_straightthrough_stream.md - Stage 7 streams only on `--task SecondPassFDR`; the straight-through run still builds the pool

**Module**: `osprey`
**Status**: Completed 2026-09-09 (PR #4646, merged as 794cb6a5d8). Successor to
`todos/active/TODO-20260906_osprey_stage7_lean_row.md` ([#4642](https://github.com/ProteoWizard/pwiz/pull/4642)),
which made the streamed Stage-7 join exist and proved it at 446 files.
**Branch**: `Skyline/work/20260908_osprey_stage7_stream_and_scores_retirement` in
`C:\proj\pwiz-work2`, STACKED on #4642's branch (cut from `32ea5f6aa3`), not from master.
**Shared branch**: the developer chose ONE branch for this TODO and
`TODO-20260908_osprey_input_scores_retirement.md` (2026-09-08), streaming commits first and
the retirement after, so the dependency is satisfied by commit order inside the branch. Both
TODOs therefore name the same branch and will name the same PR.
**Predecessor detail**: #4642's TODO carries the measurements, the marker lines and the
resident-path token work. **Do not duplicate them here - cite them.**

## The goal

Make the straight-through run stream Stage 7, so the bounded join is the DEFAULT rather than a
property of one CLI invocation. When this lands there is no route left that requires the
O(files) survivor pool, `#4486`'s entry in `regression.ps1`'s `$knownResidentGaps` deletes, and
the parallel disclosure table collapses back into the named-token mechanism.

## Why this is open at all - the honest history

The predecessor's acceptance test was 446 files run as `--task SecondPassFDR` with everything
else already on disk. That was chosen as a REPRO ACCELERATOR (developer, 2026-09-08): the
fastest way to reach the bug and watch memory grow to thrashing in 30 minutes. It was never
meant to define the fix's scope - the intent was always that the lean path works on a
straight-through run.

What happened is that the fix inherited the repro's shape as its admission condition.
`ScoringTaskShared.CanStreamStage7Join` opens with `config.ExpectReconciledInput`, which only
`--task SecondPassFDR` sets, so the one route the repro used became the only route that can
stream.

**Measured cost of the gap** (2026-09-08, exe `_bin\251-p16fold`, 446-run CHS cohort, ordinary
`-i ... --output-dir` resume): 85.9 GB managed / **91.1 GB private** on a 63.7 GB box, reached
inside `Rebuilding first-pass survivors from 446 file(s)` and paging from there. It matches the
cost model `regression.ps1` already publishes to within 1.3% (4.4 GB + 0.197 GB/file predicts
92.3 GB), so the model is confirmed, not just projected.

## FOLLOW FirstPassFDR - that is the whole design instruction

The developer's standing direction, and the reason this is a bounded piece of work rather than
a research project: **FirstPassFDR already solved this exact problem and its solution is in the
tree.** Do not invent a second shape.

* `FirstPassFdrTask.Rehydrate` gives its arm its OWN per-run survivor loader, so a resumed
  first pass streams like a computed one. That change (#4536) retired the
  `resume-survivor-handoff` token, and `ResidentPaths` records the rule it established:
  *"a resume that cannot stream the Stage 6 handoff is a defect to fix, not a path to name."*
  The same sentence applies verbatim to the Stage-7 join.
* `RescoreHydration.FoldPreCompactionPerRun` is the per-run fold that arm drives.
* `PerFileRescoreTask.BuildStage7PerRunSource` is the Stage-7 equivalent that ALREADY EXISTS -
  it is simply not reachable from the straight-through arm.

## The two parts, and part 1 alone must NOT ship

Prototyped and reverted on 2026-09-08. Both findings are worth keeping because part 1 looks
sufficient and is not.

### Part 1: derive the admission (necessary)

Replace `config.ExpectReconciledInput` in `CanStreamStage7Join` with an ALL-runs on-disk check
that every input has a readable `.scores-reconciled.parquet` in the survivor-subset shape.

* The flag is a PROXY. `CanStreamStage7Join`'s own remarks say what for: *"The leg has to be
  the reconciled-input merge, whose parquets already hold the survivor subset."* On a
  straight-through run Stage 6 has just written those same parquets, so the requirement holds
  while the proxy is false.
* The route-independent helper already exists and says so:
  `SecondPassFdrTask.AnyReconciledParquet` - *"Disk-based so it reads identically in the
  in-process pipeline (Stage 6 just wrote them) and the `--task SecondPassFDR` node."*
* Sound because Stage 6 writes a reconciled parquet for EVERY file, including one with no
  rescore work (a faithful copy), so "all present" is reachable on any route.
* Use `SecondPassFdrTask.StaleReconciledParquets`' currency test (`osprey.reconciled ==
  RECONCILED_SURVIVORS` and NOT `IsSubsetWithoutScoreIndex`), NOT `AnyReconciledParquet`'s
  `osprey.rescored` footer test - "was it rescored" decides whether a second pass is owed;
  what the fold needs is "is it readable in the survivor-subset shape".
* Order it LAST among the terms: it is the only one that touches disk per file, and every
  cheaper disqualifier should return first.

### Part 2: give the straight-through Rehydrate arm a per-run source (the actual fix)

`PerFileRescoreTask.Rehydrate` has two arms and only the second consults the predicate:

```csharp
if (!ctx.Config.ExpectReconciledInput)          // straight-through resume
{
    _perFileEntries = ctx.Get<CompactedEntries>().Value;   // O(files) resident, right here
    ...
    ctx.Publish(new RescoredEntries(_perFileEntries));      // source-less milestone
    return true;
}
// only BELOW this does BuildStage7PerRunSource run
```

So the route is resident at TWO levels - it pulls `CompactedEntries.Value` AND publishes a
milestone with no per-run source. This arm needs the same treatment
`FirstPassFdrTask.Rehydrate` got: its own per-run source, so it publishes
`new RescoredEntries(buffer, materialize, source)` like the other arm does.

**Measured proof that part 1 alone is not enough**: with the derivation applied, a 10-file
straight-through resume logged `Rebuilding first-pass survivors from 10 file(s)` anyway. The
new deficiency warning did not fire, which is itself the evidence the predicate had flipped -
it keys on `!couldStream`.

### Why part 1 must not ship alone

It REGRESSES two things #4642 added:

* the O(files) deficiency warning stops firing (it keys on `!couldStream`, now true), so the
  fat path goes silent on exactly the run that takes it;
* a straight-through run with `OSPREY_STAGE7_STREAM=0` is FALSELY REFUSED by the Stage-7
  guard, telling the operator to choose a streamed join that does not exist for them.

## When this lands, finish the ratchet

* Remove `ScoringTaskShared.Stage7ResidentGuardError`'s `streamingAvailable` exemption, so the
  Stage-7 resident join is refused unconditionally without
  `OSPREY_ALLOW_UNFIXED_RESIDENT=stage7-stream-off`. The exemption exists ONLY because a run
  that cannot stream has no choice to record; when every route can stream, it has no subject.
* Delete the `#4486` entry from `regression.ps1`'s `$knownResidentGaps`, and with it the last
  `Token = 'NONE'` row. **Check `Tokens REQUIRED by this gate: 0` still holds.**
* Delete the deficiency warning in `SecondPassFdrTask.Run` - it describes a path that no longer
  exists.

## The one route that still cannot stream, and what to do about it

`CanStreamStage7Join` also requires `OspreyEnvironment.Pass2ProteinCompact`, so
`OSPREY_PASS2_QVALUE=transfer` stays resident. **Do NOT token it** - that would force
`regression.ps1` mode 10 to carry a token and break the zero-token target. The fix is the
predecessor's own step 2b (`todos/active/TODO-20260906_osprey_stage7_lean_row.md`): wire
`TransferOneFile` into `Pass2PerFileWorker` and admit `transfer` in `TryCreatePass2Worker`.
Step 2a (extracting the per-run seam) is DONE (`d969570a3c`); `TransferOneFile`'s own doc says
the rest: *"Moving the CALLER is the point ... only its home is still wrong."* Then
`!Pass2ProteinCompact` becomes "any mode with a worker" and largely dissolves, exactly as
`CanStreamStage7Join`'s comment predicts.

## Gating

* **Modes 2 and 5 are the legs that matter** - they are the resume arms this changes. Mode 1
  (vs golden) is the byte-identity oracle: the streamed and resident arms are supposed to
  produce identical output, so a diff there means the per-run source is wrong, not that
  streaming is.
* Mode 3 catches a derivation mistake in part 1 (it is the leg that already streams).
* `-Dataset All` before review, then TeamCity Perf/Regression on `pull/<N>` pinned to
  `MacCoss TeamCity Agent 1`. **Ask before triggering** - standing rule.
* **Then a 446 straight-through run**, which is the whole point: `-i` over the CHS cohort with
  `--output-dir` at a completed bed. Expect the streamed marker (`Second-pass join: folding
  over 446 run(s) ... no all-runs survivor pool`), NO `Rebuilding first-pass survivors`, and a
  peak in the 20-30 GB band rather than 91 GB. Use `ai/scripts/Osprey/CHS/Run-Chs.ps1`; read
  its README's `search_hash` section first, and pin `-LibraryDir` from the source run's own
  `Command:` line.

---

## Progress log (2026-09-08 session)

### Scope decision: this branch does part 1, part 2 and the COLD arm, not the transfer worker

The "two parts" above are necessary but not sufficient, and the reason is worth writing down
because the TODO's own framing hid it. Part 2 converts `Rehydrate`'s straight-through arm - the
RESUME. A COLD straight-through run never reaches that arm: it takes `Run`, whose comment said
in so many words that it keeps its resident pool because `MaterializeRescoredFile` is one-shot.
Deriving the admission (part 1) makes `CanStreamStage7Join` TRUE on a cold run by the time
Stage 7 asks - Stage 6 has just written the parquets - so with parts 1+2 alone a cold run would
be *admissible* and still resident, which is the same silent-fat-path shape #4642 removed. The
cold arm is therefore in scope here, not later.

Step 2b (`OSPREY_PASS2_QVALUE=transfer` -> `Pass2PerFileWorker`) is NOT. It is the predecessor's
own item, it is a redesign of the transfer arm rather than a call-shape change, and with it
still resident the ratchet items under "When this lands" cannot all be taken:

* `Stage7ResidentGuardError`'s `streamingAvailable` exemption STAYS - `transfer` genuinely has
  no streamed alternative, so its resident join is still a fact rather than a choice.
* the `#4486` row in `$knownResidentGaps` STAYS, with its `Legs` text corrected: it is no longer
  "every leg except mode 3's SecondPassFDR phase" but "the legs whose pass-2 mode has no
  per-file worker", i.e. mode 10's transfer arm.

### What changed in the code

| file | change |
|---|---|
| `Osprey.IO/ParquetScoreCache.cs` | new `IsCurrentReconciledSurvivorSubset` - marker + `score_index` in ONE open. The positive form of `IsSubsetWithoutScoreIndex`, so the Stage-7 refusal and the streaming admission ask one question. |
| `Osprey.Tasks/ScoringTaskShared.cs` | `CanStreamStage7Join` = `Stage7StreamAdmittedBeforeRescore` AND `AllReconciledParquetsCurrent`. `ExpectReconciledInput` is GONE from it. The split exists for the cold `Run` arm, which decides at the TOP of Stage 6, before the parquets the full predicate asks about have been written. |
| `Osprey.Tasks/PerFileRescoreTask.cs` | `BuildResumePerRunSource` (resume arm) and `BuildRunPerRunSource` (cold arm), both built out of the per-file halves the whole-run loops already call, so run-at-a-time is the same work in the same order. `PublishedSurvivorLoader` reads the loader WITHOUT the Stage-6 switch - one switch per stage. |
| `Osprey.Tasks/SecondPassFdrTask.cs` | the O(files) warning now keys on `rescored.Streams` (the milestone), not on the predicate, and is called from both arms that pull it. `StaleReconciledParquets` routed through the shared predicate. |
| tests | `TestIsCurrentReconciledSurvivorSubset` (real artifacts: absent / Stage-4 original / current) and `AssertStage7StreamAdmission` (ALL-not-any, and empty is not vacuously true). |

### The two design rules that decided the shape

1. **The source is the whole-run loop's own per-file half.** Not a second implementation. That
   is what makes byte-identity an argument rather than a hope, and it is the same move #4642
   made for the merge leg.
2. **A source is offered only when a dropped run can be rebuilt.** Cold arm: a survivor loader
   AND every list already empty (an empty list is what makes the one-shot materializer
   repeatable - it takes the rebuild-from-the-reconciled-parquet branch and skips the
   gap-fill-appending overlay). Resume arm: a published survivor loader.

### Open items in this branch

* [x] part 1 - derive the admission
* [x] part 2 - resume arm per-run source
* [x] cold `Run` arm per-run source
* [x] `regression.ps1`: correct the `#4486` gap `Legs` text, and ADD an assertion that the
      straight-through leg took the STREAMED join. Today only a memory profile says which arm
      ran, which is the inference #4642's own marker lines exist to replace. Deferred only
      because the gate was running - never edit a running script.
* [ ] measure Stage 7 wall time on the resume arm. Its source reads TWO parquets per run per
      pass (Stage 4 + reconciled) where the merge arm reads one, and a fold makes 2-3 passes.
      Faithfulness to the resident arm was chosen over I/O; if 446 shows it, reading the
      reconciled parquet directly is the fix, and it changes row ORDER, so it needs mode 1.
* [ ] then the `--input-scores` retirement (the other TODO), on this same branch

### Result: every in-process leg now folds run by run (2026-09-08)

`regression.ps1 -Dataset Stellar` PASSED, and the four legs each assert the marker rather than
leaving it to a memory profile:

```
Stellar mode1 (streamed join): PASS (per-run fold, no all-runs pool)   <- the COLD run
Stellar mode2 (streamed join): PASS (per-run fold, no all-runs pool)   <- resume
Stellar mode5 (streamed join): PASS (per-run fold, no all-runs pool)   <- own-sidecar rehydrate
Stellar mode3 (streamed join): PASS (per-run fold, no all-runs pool)   <- the HPC merge, as before
Tokens REQUIRED by this gate: 0 (target: 0).
```

Every leg's blib is **23,662,592 bytes**, identical to the straight-through one and to the
pre-change run, and modes 1/2/3/5/8/9 compare at 1e-9. Wall clock is unchanged within noise
(resume 1:20 -> 1:23), so the extra parquet reads a fold pays are not visible at Stellar scale;
446 is where that gets measured.

The first gate run of the day is worth keeping as the intermediate evidence: with part 1 + part 2
only, `resume.log` and `rehydrate.log` folded per run while `straight.log` logged
`Stage 7 is taking the RESIDENT join` - which is exactly the hole the cold arm closes, seen
directly rather than argued.

**PR**: [#4646](https://github.com/ProteoWizard/pwiz/pull/4646), based on #4642's branch.

### One hazard found while writing the cold arm, and how it is handled

`ExecuteRescore` drops a run's entries only when its reconciled parquet reached disk, and
KEEPS them when the write no-opped or failed - because then those entries are the only copy of
the rescore. A fold drops every run it hands over, so streaming such a run would discard that
copy and the next pass would rebuild it from the Stage 4 parquet: a blib silently carrying
1st-pass boundaries for one run, from a process that exits 0.

The resident build survives it by never dropping anything, so this is new with the fold rather
than a defect being uncovered. The source raises it as a named error at fold time - the
condition cannot be asked at publish time, since the rescore that decides it has not run yet.
The resume arms have no such hazard and say so in their own doc: a resume runs no rescore, so
no run's list ever holds state that is not already on disk.

### `-Dataset All` GREEN on both halves (2026-09-08)

95 legs, 0 failures, `Tokens REQUIRED by this gate: 0`, exit 0, 6,873.8s across 56 phases.
The legs that carry the claims, on all four datasets:

| leg | what it proves |
|---|---|
| `mode1 (vs golden)` | NO golden moved - by the streaming change or by the retirement |
| `mode3 (HPC chain==straight)` | the derived parquet paths resolve to the files `--input-scores` used to name |
| `mode3 (per-run hydrate)` | the rescore workers took the per-run hydrate |
| `mode1 / mode2 / mode5 (streamed join)` | cold run and both resumes fold run by run |

The streamed arm is now exercised on StellarLibDecoy, StellarGenDecoyEntrap and Astral, which
closes item 1 of #4642's STILL OPEN list: those three carry library decoys, entrapment and hram
data, and before this the streamed Stage-7 join was only ever reached on plain Stellar.

**Use `regression-parallel.ps1` for `-Dataset All`.** Serial is 2h04m30s (Astral alone is 51.8%
of it); two lanes is ~70-75 min for identical coverage. This session ran the serial entry point
twice by habit - once for a full 1h54m - which is why the osprey-development skill now names the
parallel runner at the gate bullet rather than leaving it to be discovered by listing the folder.

### Copilot review round (commit `1a120903fe`)

ONE inline comment, and it was correct: `PipelineContext`'s mutation contract cited
`--input-list` as a field "written once at pipeline entry", but that is expanded during CLI
parsing. The carve-out existed for the `--input-scores` synthesis in `AnalysisPipeline.Run`, and
when that mechanism was deleted the example was SWAPPED rather than the carve-out removed.

Re-checking the file for the same claim found three more comments the retirement had left stale
and Copilot had not flagged - `BuildFileNameToIndex` ("synthesized from --input-scores parquet
stems by Program.Main"), `ResolveSidecarBasePath` ("where InputFiles is empty"), and
`BlibOutputWriter` ("the acquisition itself is not among the inputs"). **The lesson is the
generalisable one: a single reviewer finding about a stale claim is worth grepping for, because
the mechanism that made it stale usually made several.**

**Left as a follow-up, deliberately**: `ScoringTaskShared.ResolveSidecarBasePath`'s
parquet-derived fallback is now UNREACHABLE - every task requires `--input`, and the `fileName`
keys are derived from those same inputs, so the first loop always matches. Marked in place rather
than deleted, because removing it is a behaviour change and does not belong inside a
review-response commit. Decide before merge: delete it, or keep it defensive and say so.

---

### The `.scores.parquet` fallback is retired in code, and all three surfaces now say so (2026-09-08)

Brendan's question: why does `SecondPassFDR` read two parquets per run when the architecture
says it reads only the `PerFileRescoring` one? Then his correction, which is the actual finding:
**there is no fallback** - "a missing `scores-reconciled.parquet` means it was not calculated,
and it is not replaceable with the `.scores.parquet`."

He is right, and the doc line I first answered from was stale. The decision is
`TODO-20260826_osprey_stage7_stream_pool.md:473` (increment 2, `WriteUnchangedReconciled` -
"that bail was the ONLY reason a file could lack the artifact") plus his 2026-08-27 instruction
at `:2192`, written up as **P13** (`docs/00-pipeline-architecture.md:497`) and the team-wide
rule at `ai/docs/osprey-development-guide.md:1689`: *"In consumers, an absent artifact is a
reported fault, not a `continue`."* Absence stopped being a run shape three weeks ago; five
live sites had not been told.

**So the two-parquet read was never an I/O-vs-faithfulness trade** - which is how the item
under "Open items" recorded it, and how I re-derived it before he corrected me. It was the
retired fallback still being the main road: the resume arm read Stage 4 for ROWS because the
overlay-restores-VALUES shape existed to serve no-work files that Stage 6 now always writes.

#### What changed

| site | was | now |
|---|---|---|
| `SecondPassFdrTask.cs:1098` | `if (!File.Exists(reconciledPath)) continue;` | `UnusableReconciledParquets` returns `(Missing, Stale)` and refuses on both, with the remedy each needs |
| `PerFileRescoreTask.Rehydrate:696` | refill-all-runs loop, then overlay-all-runs loop | one `MaterializeAllResumedFiles` loop over the shared per-file half |
| `BuildResumePerRunSource` | `MaterializeFileSurvivors` (Stage 4) + `OverlayReconciledIntoFile` | one call to `MaterializeResumedFile` - the same half the loop calls |
| `MaterializeRescoredFile` | `reconciledPath != null && entries.Count == 0` | `ReconciledPathOrFail`; the `Count == 0` term stays (it is not a fallback - see below) |
| `OverlayReconciledIntoFile` | took the map, silently skipped a run absent from it | takes a resolved, already-judged path |
| `BuildRunPerRunSource:2787` | fold-arm-only throw (finding F3's site) | deleted; the per-file half fails on BOTH arms, so absence stops being a property of the arm |

New `ReconciledPathOrFail` is the single fault, logged and thrown, naming the run and saying
why the Stage 4 file is not a substitute.

#### Two things that look like the fallback and are not - checked before touching them

1. **`RescoredPoolPlan.RefillOnly`** (`:476`). Its call site records that the resident arm does
   nothing at all on this route and `SecondPassFDR` reloads the reconciled features by identity,
   so overlaying here "applied Stage-6 boundaries the resident arm never applies", breaking the
   `OSPREY_STAGE6_STREAM_SURVIVORS=0` byte-identity oracle. A previous session already made and
   reverted that mistake. The refill-only branch now comes FIRST in `MaterializeRescoredFile`,
   explicitly, so it reads as the separate route it is rather than as a missing artifact.
2. **`entries.Count == 0`**. Not "no parquet, use Stage 4" but "these rows are already in
   memory" - the resident-oracle case, where re-reading would be the duplicate build. Both
   branches read exactly one parquet, and it is the reconciled one.

#### Why the row order works out

The worry was that loading direct interleaves gap-fill where the overlay appends it. It
resolves itself: `FirstPassSurvivorLoader` sorts canonically and documents that callers must
not re-order, which is why the cold arm already passes `canonicalize: false`. The load route
arrives in canonical order; only the overlay route needs the sort, and it keeps it.

#### The three surfaces

* **code** - above.
* **`docs/00-pipeline-architecture.md`** - the artifact table's `.scores.parquet` row no longer
  lists `SecondPassFDR` at all (it said "fallback for runs with no reconciled sibling",
  contradicting P13 forty lines below its own statement of it); the reconciled row now says
  "written for **every** run" and "the join's only row source"; Boundary 3 -> 4 gains a
  paragraph stating that absence fails and naming the retired form so it is not re-derived.
* **`Osprey-workflow.html`** - the `--task SecondPassFDR` header said its input arrives
  "via --input-scores; falls back to `<stem>.scores.parquet`". Both halves were wrong. Now
  "every run - one parquet per run, no `.scores.parquet` fallback". The other two
  `--input-scores` labels (FirstPassFDR, PerFileRescoring) are corrected to "derived from
  --input" in passing, which closes the HTML half of finding **F5**.
* Swept for the same claim elsewhere, per this branch's own Copilot lesson: fixed stale
  comments in `ScoringTaskShared:559`, `SecondPassFdrTask:76`, `SortFileEntriesCanonical`,
  and `docs/16-determinism.md:198`.

#### Left deliberately, and it is the real remaining hole

`ParquetScoreCache.EffectiveScoresPathFromScoresPath` is `File.Exists(reconciled) ? reconciled
: scoresPath` - the fallback at its lowest layer, with **12 call sites**. Its doc now states
the contract and why the "otherwise" is residue, but the code is unchanged, because the fix is
not "make it throw": ~5 of those callers are PRE-Stage-6 and the original genuinely is their
answer. The right shape is resolution that depends on the TASK - which is exactly **F2**
("the effective path has to depend on the TASK"), scheduled next. Converting the Stage-7-side
callers blind, while a gate was running, would have been a wide change to pass-2 code I had
not read. Doing it as part of F2 also concentrates what is left in one place instead of five.

**F3 is re-read by this change.** It called the fold arm's throw a defect - "refuses runs the
resident arm handles". Under the contract the fold arm was right and the resident arm's silence
was the defect, so both now fail. F3's substance survives and is unchanged: its three triggers
are runs whose parquet IS correctly written but is absent from `CurrentReconciledPaths` because
`IsCurrent` said no. That is a validity-map-vs-artifact disagreement, and the fix is to make
them agree - not to restore a Stage 4 substitution. A fix aimed only at F3 would have pushed
the wrong way.

#### Gates

* `Build-Osprey.ps1 -SourceRoot C:/proj/pwiz-work2 -RunTests -RunInspection`: 591 tests
  (590 passed, 1 pre-existing skip), inspection 0 warnings. Run twice - before the regression
  and again after the last comment edits - both green.
* `regression.ps1 -Dataset Stellar`: **PASSED**, 20 legs, 0 failures, 856.8s across 14 phases.
  The legs that carry this change:
  * `mode1 (vs golden)`: PASS - **the golden did not move**, which is the row-order answer.
    Loading a run's rows from its reconciled parquet instead of Stage 4 + overlay is
    byte-identical, because `FirstPassSurvivorLoader` already sorts canonically.
  * straight-through blib **23,662,592 bytes**, the same size every leg has produced on this
    branch and before it.
  * `mode1 / mode2 / mode5 / mode3 (streamed join)`: PASS (per-run fold, no all-runs pool) -
    the cold arm, both resumes and the HPC merge all still fold run by run.
  * `mode2 (resume==straight)`, `mode5 (rehydrate==straight)`, `mode3 (HPC chain==straight)`:
    PASS - the arms this change re-plumbed still agree with each other.
  * `mode8 (partial rescore resume)` and `mode9 (crash-shaped half-done resume)`: PASS -
    the two legs where a run is deliberately left half-done, i.e. the closest coverage the
    gate has to the missing-artifact case the new fault guards.
  * `Tokens REQUIRED by this gate: 0 (target: 0)`.
* `regression-parallel.ps1 -Dataset All` still owed before merge (NOT the serial entry point),
  then TeamCity Perf/Regression on `pull/4646` - **ask Brendan first**.
### `EffectiveScoresPathFromScoresPath` is DELETED; the task picks the parquet (2026-09-08)

Brendan, on the doc-only mitigation above: *"This should be removed and it should be determined
which score cache is appropriate for each caller... it is still only right as far as the pipeline
itself makes it right. Just like the usage that initiated this review was essentially harmless
under correct pipeline functioning, but it confused you enough that you stated SecondPassFDR
reads 2 Parquet files per data-file. The usage is confusing if harmless under correct pipeline
functioning."*

That is the general principle behind both halves of this session's work, and it is worth keeping
in those terms: **a disk probe standing in for a design fact is wrong even when it returns the
right answer**, because its correctness is a property of the caller's position in the pipeline
rather than of the expression. It cannot be read locally, so every reader has to reconstruct the
whole pipeline to know what it does - and I demonstrably failed that reconstruction on the
first attempt, from the code, with the architecture doc open.

**This is finding F2's fix.** F2 said "the effective path has to depend on the TASK"; that is
now what it does, so F2 is closed by this rather than pending.

#### What the two answers are, and why disk cannot tell them apart

`ScoringTaskShared.ReadsReconciledScores(config)` - `SelectedTask == SecondPassFdr`:

| task | reads | why |
|---|---|---|
| `FirstPassFDR` | `<stem>.scores.parquet` | it computes the FIRST pass; the survivor subset is not its population |
| `PerFileRescoring` | `<stem>.scores.parquet` | rescores from first-pass rows; writes the reconciled file as OUTPUT |
| `SecondPassFDR` | `<stem>.scores-reconciled.parquet` | the join, and the only parquet its node is shipped |

The last column is the part that makes probing indefensible rather than merely untidy: it is
also **what each node is shipped**. `regression.ps1:1592` stages phase 4 with the reconciled
parquets and *deletes* the Stage 4 originals from the worker dir first - "never the original
Stage 4 parquet" - so on a correct node exactly ONE of the two is present. A probe therefore
cannot distinguish "the artifact for my pass" from "the only artifact here", and it gets the
right answer for a reason that has nothing to do with what it asks.

Where it breaks is the case with BOTH present, which is what a completed run leaves on disk:
`--task FirstPassFDR` re-run over it took the reconciled parquets and would have trained the
first pass on ~1/52 of its rows, with every version, search and library hash matching.

#### The 12 call sites, each now naming its artifact

* `ScoringTaskShared.ScoresPathsForInputs` - task-dependent (above). Reached only by the three
  tasks `StartsAfterPerFileScoring` names, so every case has an answer.
* `Program.cs:226` - the absent-input acceptance asks for EITHER parquet explicitly. Which one
  a task reads is not this check's question; it runs before dispatch. Truth value is unchanged
  (`Exists(effective)` is exactly `Exists(stage4) || Exists(reconciled)`).
* `SecondPassFdrTask.Inputs`, `Pass2FdrSidecar` x4, `PerFileRescoreTask` x2 - all post-Stage-6
  readers, all now `GetReconciledScoresPath` / `ReconciledPathFromScoresPath`. The derivation
  is idempotent, so ONE expression is correct both in-process (the published map holds Stage 4
  paths, because Stage 1-4 ran here) and on a merge node (it holds reconciled ones).
* `PerFileRescoreTask.BuildStage7PerRunSource` - no longer re-resolves at all. The published
  path IS reconciled on that leg by task membership, so it ASSERTS that (`IsReconciledScoresPath`)
  and fails loudly instead of quietly converting.
* `IOTest.TestEffectiveScoresPathFromScoresPath` -> `TestScoresPathsDependOnTaskNotDisk`.

#### The test is the negative one on purpose

The old test laid down one file, then the other, and asserted the probe followed disk - it
pinned the defect. The replacement puts **both** files on disk (the state a completed run
leaves) and asserts the task still decides. A test that writes only one file passes against
the probe too, so it would not have caught this.

#### Still owed

The unit test pins the seam; it does not prove end-to-end that a re-run reads the Stage 4 file.
The enforcement that would is regression.ps1's own idiom from phase 4: stage a decoy
`.scores-reconciled.parquet` into the mode-3 **phase 2** dir and assert `FirstPassFDR` output is
unchanged - absence of an enforcement being why this survived. Worth a mode; not added here.

#### Gates

* `Build-Osprey.ps1 -RunTests -RunInspection`: 591 tests (590 passed, 1 pre-existing skip),
  inspection 0 warnings. `TestScoresPathsDependOnTaskNotDisk` passes.
* Docs carrying the retired rule updated with the code: `14-intermediate-files.md` (x2),
  `15-hpc-scoring-split.md` (x2, including the "Reconciled wins per stem" bullet), and
  `regression.ps1`'s phase-4 comment - which now says the task decides AND that the staging
  enforcement is deliberately independent of it, because staging alone would hide a regression
  back to a probe.
* `regression.ps1 -Dataset Stellar -KeepOutput`: running, and the retained straight-through
  directory is the bed for the F2 re-run reproduction.
### Night session 2026-09-08 -> 09: 14 of 15 findings closed

Commit `c0da9e5af8` (plus an F15(b) doc move after it). Gates at the time of writing:
`Build-Osprey.ps1 -RunTests -RunInspection` = **593 tests, 592 passed, 1 pre-existing skip,
0 warnings**; `regression.ps1 -Dataset Stellar` PASSED twice with every blib at
23,662,592 bytes and `Tokens REQUIRED: 0`.

Three new tests, each pinning a defect that the existing suite could not see:

* `TestOnlyStage7JoinTasksAdmitTheStreamedJoin` - asserts with the switch forced ON, so it
  cannot pass merely because streaming happens to be off in the environment.
* `TestScoresPathsDependOnTaskNotDisk` - asserts with BOTH parquets on disk, which is the
  state a completed run leaves. A test writing only one file passes against the old probe too.
* `TestValidateRejectsDuplicateInputStems` - asserts with the stems in DIFFERENT directories,
  the case `--input-list` makes routine and cruder checks miss.

| finding | disposition |
|---|---|
| F1 | FIXED. `RunsStage7Join` term, FIRST in `Stage7StreamAdmittedBeforeRescore` and free. Names the admitted set (straight-through, SecondPassFDR, ModelDiagnostics) so it fails closed. |
| F2 | FIXED, as the fallback-retirement work above. |
| F3 | **OPEN. The review's direction is INVERTED** - see the retirement section. |
| F4 | FIXED. Both `ForTask` copies, the truth-table row, `PerFileRescoreTask.IsIncluded`'s comment, `docs/15-hpc-scoring-split.md`. |
| F5 | FIXED. README's HPC section (its three command lines were being REJECTED), `Osprey-workflow.html`, and all four live scripts. |
| F6 | FIXED. The stand-in is gated on `StartsAfterPerFileScoring`, restoring the scoping the deleted `if (!fromInputScores)` wrapper used to give structurally. |
| F7 | FIXED. `regression.ps1` now also asserts the ABSENCE of `MaterializeAllFromSource`'s warning: the marker says a source was offered, this says nothing pulled the whole pool anyway. |
| F8 | FIXED. `$cannotStreamJoin` gained `OSPREY_STAGE6_STREAM_SURVIVORS`. The residual CLI-side gap (`--fdrbench-pass 1`, non-Percolator `--fdr-method`) is documented AT the predicate, with what to do if a spec ever sets one. |
| F9 | FIXED by F1. A `--task PerFileRescoring` worker no longer builds a Stage-7 source at all, so it neither pays the retained-sidecar read #4597 forbids nor emits the marker. |
| F10 | FIXED. `entries.Clear()` in the resume source, GUARDED ON THE LOADER - clearing unconditionally would have destroyed the `OSPREY_STAGE6_STREAM_SURVIVORS=0` oracle, whose entries are the only copy. |
| F11 | FIXED. One `ProbeReconciledSurvivorShape` open behind both predicates, wrapped, so an unreadable parquet ANSWERS false instead of throwing past the named refusal. Halves the opens: ~4,460 -> ~2,230 on a 446-run cohort. |
| F12 | FIXED. `ValidateArgs` refuses duplicate input stems, naming the stem and every colliding path. |
| F13 | PARTIAL. (b) the guard no longer demands a token for a choice the operator does not have; (c) `couldStream`'s O(files) footer sweep is no longer computed to be discarded. **(a) NOT done** - see below. |
| F14 | FIXED. The gap-fill map is `Lazy` and the load branch never reads it - order 10 GB of envelope JSON at 446 runs, previously pulled unconditionally inside a method documented as lazy. |
| F15 | FIXED. (a) dead `NewTempDir` + its now-unused `using System.IO`; (b) `BuildRescoredPool`'s summary moved back off `BuildRunPerRunSource`; (c) `IOTest` takes its metadata from `ReconciledParquetWriter.BuildReconciliationMetadata` instead of hand-feeding the marker. |

#### Deliberately not done, with the reason

**F13(a)** - refuse `OSPREY_STAGE7_STREAM=0` without a token in `ValidateArgs` rather than
hours later in Stage 7. The saving is real, but it is an env-var-only A/B path a user never
takes, and moving a refusal into CLI validation is more risk than that reward. Backlogged.

**F3** - a design decision about failure behaviour that needs the validity map and the artifact
reconciled, not a substitution restored. Left with the direction corrected in writing so the
next session does not "fix" it the wrong way.
## `/code-review max 4646` findings, 2026-09-08 - 12 of 15 open

**Status after the fallback-retirement work above** (read that section before acting on any of
these - it moved three of them):

* **F2 - FIXED.** `ScoresPathsForInputs` now resolves by TASK
  (`ScoringTaskShared.ReadsReconciledScores`), and `EffectiveScoresPathFromScoresPath` is
  deleted, so there is no longer a way to ask disk which pass an artifact belongs to.
  `TestScoresPathsDependOnTaskNotDisk` pins it with BOTH parquets present.
* **F3 - re-read, still open, and the direction is INVERTED.** It called the fold arm's throw a
  defect for refusing runs the resident arm handles; the fold arm was right and the resident
  arm's silence was the defect, so both now fail. Its substance survives: the three triggers are
  runs whose parquet IS correctly written but is absent from `CurrentReconciledPaths` because
  `IsCurrent` said no. Fix the validity-map-vs-artifact disagreement; do NOT restore a Stage 4
  substitution.
* **F5 - HTML half done.** `Osprey-workflow.html`'s three `--input-scores` labels are corrected.
  `README.md` (8 hits) and the four live `ai/scripts` still pass the retired flag.
* **F1 remains the next blocker**, and is unaffected by the above.

Run at the cap, so read this as "the 15 most severe", not "all of them". **Verify each before
acting** - the tool is confidently wrong sometimes, and two of its candidates were already
REFUTED by its own verifier (below). Two were verified by hand in-session and are marked.

The branch is stable and green as it stands (`-Dataset All`: 95 legs, 0 failures) - these are
findings against a passing gate, which is the point: most of them are shapes the gate does not
reach.

### BLOCKERS - correctness, must fix before merge

**F1. `--task FirstPassFDR` can train on ZERO entries and exit 0.**
`PerFileScoringTask.cs:1391`. `perRunJoin = !perRunRescore && CanStreamStage7Join(config)`.
For `--task FirstPassFDR`, `CanHydratePerRun` is false (it admits only `SelectedTask` null or
`PerFileRescore`), so `perRunJoin` decides - and with `ExpectReconciledInput` gone every
remaining term is TRUE on a **re-run over a completed directory**: stage7Stream on,
NeedsResidentPool false, Pass2ProteinCompact true, the retained_base_ids sidecar present from
the earlier pass, and `AllReconciledParquetsCurrent` true because Stage 6 already wrote every
reconciled parquet. `LoadJoinOnlyPerRunNames` then adds N EMPTY lists and returns null, and
`FirstPassFdrTask.Run` computes first-pass FDR/Percolator over nothing, **rewriting both
boundary sidecars and the retained base_id summary as empty**, exit 0.
`HydrateRescoreBundleIfPresent` (:1895) short-circuits on the same widened predicate.
*Before this branch the `ExpectReconciledInput` term made it unreachable for anything but
`--task SecondPassFDR`.* I checked the COLD case when I widened the predicate and concluded it
was safe; I never checked the re-run case.

**F2. `ScoresPathsForInputs` feeds FirstPassFDR the survivor SUBSET.**
`ScoringTaskShared.cs:490`. It applies `EffectiveScoresPathFromScoresPath` ("reconciled wins
per stem") to EVERY task. That rule belonged to `--input-scores <dir>`, i.e. the SecondPassFDR
case; FirstPassFDR and PerFileRescoring need the **Stage 4** file. Nothing rejects the
substitution: the strict `osprey.reconciled` gate is armed only under `ExpectReconciledInput`
(`ParquetScoreCache.cs:2078`), and version/search/library hashes all match. First-pass
Percolator would train on ~1/52 of the rows and write cohort-wide boundary artifacts from it,
exit 0. A retried `--task PerFileRescoring` would likewise hydrate from its own previous
reconciled output. **The effective path has to depend on the TASK.** The chain used to name
`--input-scores $s.scores.parquet` explicitly (regression.ps1 phase 2 did); there is now no way
to ask for the Stage 4 file.

**F3. The new fold arm refuses runs the resident arm handles.** `PerFileRescoreTask.cs:2794`.
My guard tests `plan.RescoredFiles != null` - a run-WIDE flag assigned unconditionally at :981 -
rather than "this run was rescored", so any run missing from `plan.ReconciledPaths` aborts
Stage 7 mid-fold. Three triggers, all with the parquet correctly written: a non-fatal
`PerFileResumeDriver.Stamp` failure (documented non-fatal) leaves the file correct but not
`IsCurrent`; a run whose file_name has no `input_files` stem (`WriteUnchangedReconciled`
returns silently at :1928, a state :3014 documents as SUPPORTED); and
`WriteReconciledAndStamp`'s silent `return false` at :1873. The throw fires on the FIRST
`StreamFiles` pass, which sets `_streamed` before calling the source, so earlier runs are
already dropped and any later `.Value` read throws too - exit 1 after the whole rescore has been
paid for. **The message is also wrong for two of the three**: it asserts Stage 6 logged a
warning, but Stage 6 DID persist the run (case 1) or logged nothing (case 3). Under
`--model-diagnostics` the first occurrence is swallowed by `WritePass2DiagnosticsStreamed`'s
blanket catch (`SecondPassFdrTask.cs:782`) and the run dies later at an uncaught fold.
**Do NOT "just remove the throw"** - see REFUTED (1).

**F4. VERIFIED BY HAND. My `ForTask` test helper builds a config the CLI cannot produce.**
`PipelineMembershipTest.cs:59`. It sets `StopAfterStage5` for ModelDiagnostics;
`Program.cs:132` is `config.StopAfterStage5 = selectedTask == HpcTask.FirstPassFdr;` and is the
only assignment in the tree. So the PR's headline new truth-table row asserts fiction: a real
`--task ModelDiagnostics` reaches `AnalysisPipeline` with all three flags false, giving
`{true,true,TRUE,TRUE}`, not the `{true,true,false,false}` the row claims.
`ProgramTests.cs:433` pins the REAL flags and its comment at :422 states the opposite design -
**two tests in one assembly now assert incompatible things**. The same false claim is repeated
in `docs/15-hpc-scoring-split.md`'s truth-table row and in the comments on
`PerFileRescoreTask.IsIncluded` and `SecondPassFdrTask.IsIncluded`.
`LibraryFragmentReleaseTest.cs:285` carries the identical helper (latent).

**F5. VERIFIED BY HAND. `--input-scores` is still live outside the diff.**
`README.md` 8 hits - :132/:136/:140 are copy-pasteable command lines the parser now REJECTS,
and :112/:114/:154/:156/:174 describe the flag as the input mechanism, including "ordering is
significant. A directory argument is globbed and sorted internally", a guarantee
`ScoresPathsForInputs` no longer provides. `Osprey-workflow.html` :398/:465/:509 label the
three join tasks' inputs as arriving "via --input-scores". Outside the repo, four LIVE scripts
(archive/ ones do not matter): `Compare/Compare-Stage7-Rehydration-Strict-CSharp.ps1`,
`Test-Snapshot.ps1`, `SEA-AD/Measure-Stage6Rescore.ps1`, `Profile-Stage5.sh`. Each exits
non-zero before doing any work, and reads as a phase failure rather than a CLI incompatibility.

**F6. The scores-parquet stand-in is applied to tasks that must read raw spectra.**
`Program.cs:226`. My new "an absent input is fine when its scores parquet is on disk"
acceptance is not gated on `StartsAfterPerFileScoring`, so `--task SpectraCache` or
`--task PerFileScoring` with a moved or mistyped input silently proceeds when a leftover
`.scores.parquet` happens to sit there - and logs "reading those from their scores parquet,
which is what a task after Stage 4 needs", which is FALSE for SpectraCache, whose only product
is the `.spectra.bin` it must decode from the raw file. The old `if (!fromInputScores)` wrapper
structurally could not reach the pre-Stage-4 tasks; nothing re-establishes that scoping, and
`ValidateArgs` no longer catches it because the input-KIND crosses were deleted.

### The verifiers I added, which can lie

**F7. The streamed-join marker proves the wrong thing.** `PerFileRescoreTask.cs:2773`. It is
logged when the SOURCE IS BUILT, not when anything folds through it. Two consequences: a run
that dies later in Stage 6 has already claimed the streamed join in its log; and any Stage 7
consumer reading `RescoredEntries.Value` routes to `MaterializeAllFromSource`, which builds
every run at once - the exact 91.1 GB peak - while `Streams` stays true, so
`WarnResidentStage7Join` stays SILENT and `regression.ps1:2711` reports PASS on a resident run.
`MaterializeAllFromSource` logs its own warning (:2090) but nothing asserts its absence.
**Asserting on the fold's own ProgressReporter line would fix this.**

**F8. `$cannotStreamJoin` omits `OSPREY_STAGE6_STREAM_SURVIVORS=0`.** `regression.ps1:1775`,
documented as "CanStreamStage7Join's OWN terms". Under that switch `BuildRunPerRunSource`
returns null (no loader, and the lists are never cleared), no marker reaches straight.log, and
the new mode1 leg FAILs a run behaving exactly as instructed - while mode2/mode5 PASS, because
`BuildResumePerRunSource` reads the loader through `PublishedSurvivorLoader`, which
deliberately bypasses the Stage-6 switch. The red is mode1-only and reads like a genuine
regression. Separately the predicate reads only env vars while two of the three
`NeedsResidentPool` triggers are CLI/config (`--fdrbench-pass 1`, a non-Percolator
`--fdr-method`), so a dataset spec setting either would red all three legs.

**F9. A `--task PerFileRescoring` worker emits the marker the gate greps for.**
`PerFileRescoreTask.cs:2752`. Nothing excludes the worker from `BuildRunPerRunSource`, and
regression.ps1 stages `output.1st-pass.retained_base_ids.bin` into every phase-3 dir (:1551,
deliberately unguarded), so `phase3_<stem>.log` receives the marker VERBATIM in a process whose
pipeline contains only `PerFileRescoreTask`. Any leg that widens its log set to the per-stem
logs is told a join folded when none ran. The worker also pays a retained-sidecar read that
#4597's "entering PerFileRescoring must cost the same for 1 run as for 446" contract forbids.

### Correctness, lower reachability

**F10. `BuildResumePerRunSource` omits the `entries.Clear()` its sibling adds.**
`PerFileRescoreTask.cs:2159` vs `:2808`. `MaterializeFileSurvivors` returns early when
`entries.Count > 0`, but `OverlayReconciledIntoFile` is unconditional and appends gap-fill.
`RescoredEntries.MaterializeFile` (`PipelineByproducts.cs:739`) invokes the source WITHOUT
clearing and leaves dropping to its caller, whose doc names "merely finished one of several
passes over it" as legitimate. Any path where a run is begun but `ApplyFileRunQ` does not run
duplicates that run's gap-fill precursors in the pool Stage 7 writes the `.blib` from -
silently, exit 0. This is the same duplication `BuildRunPerRunSource`'s own comment says once
exited a straight-through Stellar run 1 on `AssertSidecarDescribesPool`.

**F11. `IsCurrentReconciledSurvivorSubset` throws where it is documented to answer false.**
`ParquetScoreCache.cs:280`. `LoadFooterMetadata` is called with no try/catch, so ONE
zero-length, partially-written or foreign-build reconciled parquet turns a boolean predicate
into an unhandled stack trace at five call sites - pre-empting
`SecondPassFdrTask.StaleReconciledParquets`, which is the named, file-listing refusal the
operator is supposed to get. `ValidateScoresParquetGroup` (:2053) wraps the identical call in
try/catch, so the convention exists and I did not follow it. **Secondary**: my doc says "in one
open" but `LoadFooterMetadata` and `HasColumn` each construct their own reader - 892 opens at
446 runs, uncached across five call sites, ~4,460 parquet opens per process before any work,
typically on a network artifact directory.

**F12. Duplicate basenames across directories.** `PerFileRescoreTask.cs:2922`. Every join keys
runs on `Path.GetFileNameWithoutExtension`, and nothing rejects two inputs in different
directories sharing a stem - a shape `--input-list` makes routine at cohort scale.
`LoadJoinOnlyPerRunNames` appends TWO rows keyed `"x"` while `perFileParquetPaths["x"]` keeps
only the second; `CurrentReconciledPaths` then throws `ArgumentException: An item with the same
key has already been added` mid-Stage-6/7. **With `--output-dir` it is worse**: both stems
resolve into the same directory, so the two runs share one `.scores.parquet` and one
`.scores-reconciled.parquet` with no error at all. The `--input-scores <dir>` form made stems
unique by construction.

**F13. `Stage7ResidentGuardError`'s throw is newly reachable, and late.**
`SecondPassFdrTask.cs:290`. (a) An operator with `OSPREY_STAGE7_STREAM=0` exported and no token
runs an ordinary `-i` job: Stages 1-6 run for HOURS, Stage 6 writes the reconciled parquets,
`AllReconciledParquetsCurrent` flips true, and Run throws before writing the blib - an
invocation that completed on the previous build. `ValidateArgs` holds both env facts and could
refuse in milliseconds. (b) With `OSPREY_STAGE6_STREAM_SURVIVORS=0` too, `couldStream` is still
true but `BuildRunPerRunSource` returns null regardless, so the message "unset
OSPREY_STAGE7_STREAM to take the streamed join" is unachievable. (c) `couldStream` is computed
unconditionally although the guard's first line short-circuits - the full O(files) footer sweep
is discarded on the default path.

### Retention / performance

**F14. The resume arm forces the deferred gap-fill read and captures O(files) state.**
`PerFileRescoreTask.cs:2148`. `PerFileGapFillForRescore` is published DEFERRED
(`FirstPassFdrTask.cs:1153`) and its header records the cost: "dotTrace 69.7s total in
ReadGapFillAndCalibrations ... an in-code probe at 92.7s; and a night run's log gap at 111s" -
order 10 GB of envelope JSON at 446 runs. I pull `.Value` unconditionally inside a method whose
surrounding comment claims "LAZY ... there is no reason to do the work before the consumer that
folds asks for it", then capture the whole-run map for all of Stage 7 though the fold needs one
run's list. The sibling `BuildRunPerRunSource`'s lambda calls instance members, so it captures
`this` and pins `_poolPlan.ResetEntryIds` (a `HashSet<uint>` per file) across all 7+
`StreamFiles` passes - **a residual O(files) term invisible to the `_perFileEntries` accounting
this PR measures.**

### Cleanup

**F15.** (a) `ProgramTests.cs:842` `NewTempDir()` is dead - its five callers were the deleted
`TestResolve*` tests - and lines 844-846 are the file's only `Path.`/`Directory.` uses, so
`using System.IO;` at :27 is redundant too. Both are ReSharper inspections on a file this diff
touches, against CRITICAL-RULES' "ReSharper must show green". *(Note: the local inspection ran
CLEAN, so confirm before acting.)* (b) `PerFileRescoreTask.cs:2705-2720` is
`BuildRescoredPool`'s original `<summary>` - describing the deferred whole-run build and its
`[STAGE-WALL]` line - left attached to the new `BuildRunPerRunSource` at :2752, which carries a
second `<summary>` and does neither; `BuildRescoredPool` at :2832 is now undocumented.
(c) `IOTest.cs:2855` hand-feeds `{"osprey.reconciled", RECONCILED_SURVIVORS}` into
`StreamReconciledScoresParquet`, which writes the caller's map verbatim - **so if
`ReconciledParquetWriter` ever stops stamping that marker the test still passes while
`AllReconciledParquetsCurrent` returns false for every real run and the whole cohort silently
falls back to the 91.1 GB resident join.**

### REFUTED by the review's own verifier - do NOT re-raise

1. "`ExecuteRescore`'s keep-condition and the fold's refusal ask different questions" - they are
   the SAME `PerFileResumeDriver.IsCurrent` call with the same arguments
   (`PerFileRescoreTask.cs:2594` vs `:2919`), and the throw is what keeps the two arms
   byte-identical. **A naive "just skip the throw" fix for F3 would INTRODUCE an
   overlay/gap-fill divergence.**
2. "The resume fold's overlay map diverges from the resident arm's" - both call
   `CurrentReconciledPaths` and both canonicalize.

### Suggested order for the next session

1. **F1 and F2 together** - both are `--task FirstPassFDR` over a completed directory, and both
   want a real reproduction before and after, not just reasoning. They are also the two that
   can corrupt a cohort's artifacts while exiting 0.
2. **F4 + the doc/comment repeats**, then **F5** (the doc/script sweep) - cheap, and F4 is a
   test currently asserting a falsehood.
3. **F6, F11, F10, F8** - small, local, each with a clear fix.
4. **F3, F13** - design decisions about failure behaviour; read REFUTED (1) first.
5. **F7, F9** - the marker's meaning. Worth doing together, since both are "the gate cannot
   distinguish a source being offered from a fold running".
6. **F12, F14, F15** - judgement calls and cleanup.

Re-run `regression-parallel.ps1 -Dataset All` (NOT the serial entry point) and re-trigger
TeamCity Perf/Regression on `pull/4646` once the code findings are in. **Ask before triggering
TeamCity** - standing rule.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260908_osprey_stage7_stream_and_scores_retirement.md` before starting work.

### 2026-09-09 - Merged

PR #4646 merged as `794cb6a5d8`. TeamCity Perf/Regression 4169631 green on the merge candidate:
**95 PASS / 0 FAIL / 1 SKIP in 01:16:34**, first attempt.

**What shipped**: the streamed Stage-7 join on every route (cold `Run`, both resumes, and the
`--task SecondPassFDR` merge); `--input-scores` retired in favour of `-i` / `--input-list`; and
the `.scores.parquet` fallback deleted, so which parquet a task reads is decided by the TASK
(`ScoringTaskShared.ReadsReconciledScores`) rather than by probing disk. 14 of the 15
`/code-review max` findings closed, with three new tests.

**446-file acceptance, and it is the result this branch existed for.** Run directory
`D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-stages567-n4646`,
13h26m, exe snapshot `_bin\251-n4646`:

* `Second-pass join: folding over 446 run(s), each rebuilt from its own artifacts and dropped
  (no all-runs survivor pool)` - the marker fired.
* ZERO occurrences of `Rebuilding first-pass survivors from 446` (the resident landmark) and
  ZERO of `a consumer asked for the whole-run survivor pool` (the assertion added in this PR
  for exactly this).
* `[MEM stage7-inherited] 4.69 GB` and `[MEM stage7-pool] 4.69 GB` - flat, i.e. no pool built.
* Whole-run private peak **40.8 GB against the 91.1 GB** the resident join measured on this same
  cohort and shape. The peak now falls in `FirstPassFDR` (~04:00), not Stage 7: the bottleneck
  moved to the known Stage-5 wall.
* `PerFileRescoring` held a ~24 GB band with a hard ~9.5 GB post-GC floor across 446 files for
  eight hours; whole-run drift LEVEL (-0.36 GB managed, -1.78 GB private).

**Deferred deliberately, both recorded above rather than dropped**:

* **F3** - and its direction is INVERTED by this PR's own contract change. It called the fold
  arm's throw a defect for refusing runs the resident arm handles; under the contract the fold
  arm was right and the resident arm's silence was the defect, so both now fail. Its substance
  survives: runs whose reconciled parquet IS correctly written but is absent from
  `CurrentReconciledPaths` because `IsCurrent` said no. Fix the validity-map-vs-artifact
  disagreement; do NOT restore a Stage 4 substitution.
* **F13(a)** - refuse `OSPREY_STAGE7_STREAM=0` without a token in `ValidateArgs` rather than
  hours later. Real, but an env-var-only A/B path, and not worth CLI-validation risk.

**Follow-ups filed**:

* [#4650](https://github.com/ProteoWizard/pwiz/issues/4650) - library retention, rehydration and
  spectrum dropping need an end-to-end review. Evidence from this same run: Stage 7 spends 11
  minutes and peaks at 41.5 GB rebuilding all 446 runs to recompute a retained set Stage 5
  already computed, then releases 0 of 6,175,389 entries.
* `TODO-20260909_osprey_projection_scan_progress.md` - the deferred `FdrProjections` factory
  scanned 1.34 B rows to learn 446 footer counts. Separate branch, off master.
* `TODO-osprey_log_lines_are_user_facing_prose.md` (backlog) - audit logged lines for
  user-facing prose rather than class names.
