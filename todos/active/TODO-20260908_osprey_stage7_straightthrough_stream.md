# TODO-20260908_osprey_stage7_straightthrough_stream.md - Stage 7 streams only on `--task SecondPassFDR`; the straight-through run still builds the pool

**Module**: `osprey`
**Status**: In Progress. Successor to
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
