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

## `/code-review max 4646` findings, 2026-09-08 - ALL FIFTEEN, none fixed yet

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
