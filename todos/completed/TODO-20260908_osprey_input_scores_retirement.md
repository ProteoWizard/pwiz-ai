# TODO-20260908_osprey_input_scores_retirement.md - retire `--input-scores`, a Rust-era seam the C# port already replaced

**Module**: `osprey`
**Status**: Completed 2026-09-09 (PR #4646, merged as 794cb6a5d8). Proposed by the developer 2026-09-04 and written up in
`todos/completed/TODO-20260901_osprey_stage5_reload_materialization.md:3563` ("PROPOSAL: retire
`--input-scores`"); re-raised 2026-09-08. **That section is the design - read it first.** This
file carries what has been learned since and the one constraint it must not miss.
**Branch**: `Skyline/work/20260908_osprey_stage7_stream_and_scores_retirement` in
`C:\proj\pwiz-work2`, STACKED on #4642's branch. SHARED with
`TODO-20260908_osprey_stage7_straightthrough_stream.md` - the developer chose one branch for
both (2026-09-08), streaming commits first and the retirement after, so "Sequencing" below is
satisfied by commit order rather than by two PRs. The "its own branch" note under "Gating" is
superseded; the `-Dataset All` requirement is not.
**Depends on**: `TODO-20260908_osprey_stage7_straightthrough_stream.md`. See "Sequencing".

## The goal

Delete `--input-scores`. The pipeline has TWO mechanisms for "where does this invocation
start" and the newer subsumes the older:

| era | mechanism | how it says "Stage 1-4 is done" |
|---|---|---|
| Rust | the INPUT KIND - you handed me parquets | `--input-scores` |
| C# port | `--task` + validity sidecars + lazy `ctx.Demand` | the task names its stage; the sidecar attests each run |

The developer's framing: *"It is a vestige of the Rust implementation which was a far simpler
pipeline architecture. Start from mzML v start from Parquet may have been the only real
seams."*

## The evidence it is a round trip, not a mechanism

`RescoreHydration.SyntheticInputFromParquet` takes each supplied parquet path, strips
`.scores-reconciled` or `.scores`, and rebuilds a **synthetic `<stem>.mzML` that does not
exist** - purely so the sidecar path helpers, which all derive from the data-file root name,
can work. The flag names parquets and the first thing the pipeline does is convert them back
into data-file root names. Forward derivation from the stem is what every other sidecar
already does.

## It is NOT merely tidy - it already caused a defect, twice

The proposal records the first: `--task ModelDiagnostics` set `StopAfterStage5` (the C#-era
signal) while its inputs were mzML stems (the Rust-era signal for "start from the beginning"),
`PerFileRescoreTask.IsIncluded` believed the input kind, joined the pipeline, and demanded
state a diagnostics fold never publishes. Patched by teaching two more predicates about
`StopAfterStage5` - *"patching the symptom: the real fault is two seams disagreeing."*

**Second instance, found 2026-09-08 and still open**: `--task ModelDiagnostics` over
`--input-scores` fails at EVERY scale with
`HydrateReconciliationOverlay: failed to overlay .1st-pass.fdr_scores.bin`, reproducible in
33 s at 10 files with 7.2 GB in use. Its membership pulls in the rescore/Stage-7 tasks, whose
`--input-scores` hydration takes the strict batch overlay whose stub list (reconciled parquet =
Stage-5 survivors) is a subset of the pass-1 sidecar's pre-compaction records. The same run
succeeds via `--task FirstPassFDR --model-diagnostics` (exit 0, 75 s) and via the ordinary
command plus the flag. **This retirement is the fix; do not patch a third predicate.**

## THE CONSTRAINT THIS MUST NOT MISS

`--input-scores` is TODAY the only route to the bounded Stage-7 join:

```csharp
// ScoringTaskShared.CanStreamStage7Join
if (!config.ExpectReconciledInput || !OspreyEnvironment.Stage7Stream)
    return false;
```

and `ExpectReconciledInput` is set ONLY by `--task SecondPassFDR`. **Deleting the flag without
re-expressing that admission first silently returns every Stage 7 to the O(files) resident
pool** - 91.1 GB measured at 446 files - which is the exact regression #4642 existed to remove.

The proposal's own bullet says `ExpectReconciledInput` "must not be lost in the move". That is
the critical item in it, not a footnote.

## Sequencing

**Do `TODO-20260908_osprey_stage7_straightthrough_stream.md` FIRST.** It re-expresses the
streaming admission as the derived on-disk question and gives the straight-through Rehydrate
arm a per-run source. Once it lands, `ExpectReconciledInput` no longer carries the streaming
decision and this retirement inherits a safe world rather than creating an unsafe one.

The two are separable in DESIGN - the streaming fix does not need the retirement, which is why
it has its own TODO - but the retirement does need the streaming fix. One-way dependency.

## What removal buys, from the proposal

* **`--input-list` covers every task.** It feeds `-i` only, so FPFDR / PerFileRescoring /
  SecondPassFDR still put every path on the command line - 446 absolute parquet paths is
  ~58,000 characters against a 32,767 limit. (Measured on the other side: 446 `-i` raw paths is
  ~28,600 characters, **87% of the limit**, so even the ordinary form is near a wall at this
  scale.) One input kind closes it for all of them.
* **The predicates collapse.** Membership becomes a function of `--task` alone. Today
  `PerFileScoringTask` returns `!inputs`, and `PerFileRescoreTask` / `SecondPassFdrTask` each
  carry three-term expressions mixing both eras.
* **One derivation direction.** `SyntheticInputFromParquet` deletes.

## To settle before starting

* `ExpectReconciledInput` also arms the strict gate that every supplied parquet carries
  `osprey.reconciled = true`. Derived, it becomes the ordinary question "does
  `<stem>.scores-reconciled.parquet` exist and carry a current stamp" - which is what
  `SecondPassFdrTask.StaleReconciledParquets` already asks. It is a CORRECTNESS gate; do not
  lose it in the move.
* The HPC chain stages parquets into per-phase directories and names them relatively; that
  becomes `-i <stem>` plus `--output-dir`. **Mode 3 is the leg that catches a derivation
  mistake**, which is the reassuring part.
* Inputs that no longer exist are already tolerated ("446 of 446 input(s) are absent but have a
  spectra cache"); derivation must additionally tolerate the raw AND the cache being absent
  when only the parquet is wanted, which is the 446 bed's state.
* `ai/scripts/Osprey/Common/OspreyDatasetRun.psm1` maps every `-Task` to `--input-scores`
  (`$POST_SCORING_TASKS`). The runners change with the CLI, and
  `ai/scripts/Osprey/CHS/README.md` documents the re-entry recipe in those terms.

## Gating

Its own branch and its own `-Dataset All` - it touches argument validation, every task's
membership, the chain scripts and the docs. Mode 3 (the HPC 4-task chain) is the leg that
proves the derivation; modes 2 and 5 cover the resume arms. Then TeamCity Perf/Regression on
`pull/<N>` pinned to `MacCoss TeamCity Agent 1` - **ask before triggering**.

Also re-run the `--task ModelDiagnostics` case that fails today, at 10 files first (33 s to a
verdict) and then at 446: it is the defect this retirement is expected to fix, so it is the
acceptance test.

---

## Progress log (2026-09-08 session)

The streaming prerequisite LANDED first on this branch
([#4646](https://github.com/ProteoWizard/pwiz/pull/4646), Stellar green, all four legs asserting
the per-run fold), so "Sequencing" above is satisfied and this half is being built on top of it.

### The constraint is already discharged

`CanStreamStage7Join` no longer mentions `ExpectReconciledInput`. It asks the disk question the
flag stood in for - every run's `.scores-reconciled.parquet` present in the survivor-subset
shape - so deleting the flag cannot return Stage 7 to the O(files) pool. That was THE item in
this file, and it was closed by the predecessor rather than by this work.

### What the retirement actually turned out to be

Smaller than the file implies in one way and larger in another.

**Smaller**: `NoJoin` / `StopAfterStage5` / `ExpectReconciledInput` were ALREADY derived from
`--task` and from nothing else (`Program.Main`). They are not a second era's flags; they are
`--task` in three fields. The only Rust-era seam left was the INPUT KIND, and every predicate
that read it was reading something the task flags already said. The three membership
predicates collapse to one line each, and the truth table is unchanged - which is the claim
worth pinning, and `PipelineMembershipTest` now pins it against `--task` alone.

**Larger**: `--input-scores` was also the only form that accepted a DIRECTORY, so retiring it
moves ordering responsibility to the caller (`--input-list`, which exists and composes with
`-i`). And a task after Stage 4 is now handed data-file names that may not exist at all - the
446 bed's state - so `Program.Main`'s input check gained a third acceptance beside the spectra
cache: a run whose `.scores.parquet` (or reconciled sibling) is on disk. That is the same
tolerance `--input-scores` expressed by naming a different input kind, said once instead.

### Done in this branch

* `--input-scores`, `OspreyConfig.InputScores` and `Program.ResolveInputScores` deleted.
* `AnalysisPipeline`'s synthetic-input normalisation deleted - the round trip this TODO names
  as the evidence.
* `ScoringTaskShared.StartsAfterPerFileScoring` and `.ScoresPathsForInputs` replace the
  input-kind test and the ready-made parquet list.
* Membership: `FirstPassFdrTask` = `!NoJoin && !ExpectReconciledInput`;
  `PerFileRescoreTask` = its own task or a full run; `SecondPassFdrTask` = its own node or a
  full run; `PerFileScoringTask` = `!StartsAfterPerFileScoring`.
* `ValidateArgs`: every task requires `--input`; the input-kind crosses cannot be typed.
* Tests: the membership and release truth tables now build configs from `--task`;
  `ProgramTests` loses the cross-rejection and `ResolveInputScores` suites and gains the
  `--input` requirements. A `ModelDiagnostics` row REPLACES the retired `input-scores-full`
  row - it is the mode that was actually at risk from the two seams.
* Runner (`OspreyDatasetRun.psm1`) passes `-i` on every leg; docs 15 and 20 rewritten.

### NOT done, and deliberately

* **`RescoreHydration.SyntheticInputFromParquet` survives**, with its reason documented at the
  declaration. Its CLI purpose is gone; what is left is internal - the hydrate methods still
  take a PARQUET path per run (from `PerFileParquetPaths`) and derive the stem back from it.
  Inverting those signatures to take the input and derive the parquet is a no-behaviour-change
  refactor, deliberately not folded into the CLI change so a red gate can be attributed to one
  of them. **This is the remaining half of "One derivation direction".**
* The one-line `--input-scores` mentions in docs 00, 11, 16, 19, README and DIVERGENCES.
* `regression.ps1`'s four chain-phase argument lines: the gate was RUNNING, and a running
  script must not be edited. They are the first thing to do next, and mode 3 is the leg that
  proves the derivation.

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

### The developer's framing, which is better than the one in the docs (2026-09-08)

> *"All can use --input-list to point to a file with the full list. The --input-scores was just
> another way to specify the same list of basenames with a different extension. If the set did
> not match to the --input files it would also be invalid. The pipeline is for a set of
> basenames with naming as outlined in Osprey-workflow.html"*

This is the argument to lead with, and it is stronger than "the input KIND was a second seam
saying what `--task` already said". That framing is true but downstream. The flag was
**redundant by construction**: the pipeline is defined over a SET OF BASENAMES, every per-run
artifact is `<stem>.<suffix>` (`Osprey-workflow.html`: `.spectra.bin`, `.scores.parquet`,
`.scores-reconciled.parquet`, `.calibration.json`, `.reconciliation.json`, `.1st-pass.*`,
`.2nd-pass.*`), and `--input-scores` named that same set with a different suffix. It could never
express a valid set `-i` could not, because a parquet set not corresponding to the `-i`
basenames would be invalid anyway. `SyntheticInputFromParquet` was the visible symptom of
naming the set the long way round, not the disease.

**Verified while confirming this**: `--input-list` is expanded inside `OspreyCommandArgs.ToConfig`,
which runs during `ParseArgs` and therefore BEFORE `ValidateArgs`. So `--task FirstPassFDR
--input-list runs.txt` populates `InputFiles` before validation reads it, and the "2+ files"
check counts the expanded list. Worth having checked: making every task require `InputFiles`
would have been a real defect if the expansion had run after validation.

**Pending doc edit** (held while `/code-review max` runs on the branch): lead
`15-hpc-scoring-split.md`'s "Why the flag went" with the basename argument rather than the
input-kind one.

### `/code-review max` findings live in the OTHER TODO

All fifteen are recorded in `TODO-20260908_osprey_stage7_straightthrough_stream.md` (the two
share a branch and a PR, so they are in one place rather than split). The retirement's own
blockers there are **F1** (`--task FirstPassFDR` trains on zero entries on a re-run),
**F2** (`ScoresPathsForInputs` feeds FirstPassFDR the survivor subset), **F5** (README.md,
Osprey-workflow.html and four live ai/scripts still pass the retired flag), **F6** and **F12**.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260908_osprey_stage7_stream_and_scores_retirement.md` before starting work.

### 2026-09-09 - Merged

PR #4646 merged as `794cb6a5d8`, together with `TODO-20260908_osprey_stage7_straightthrough_stream.md`
(one branch, one PR, by the developer's choice). The retirement half shipped complete: every task
takes `-i` / `--input-list`, the per-run artifacts are derived from the input stem, and
`EffectiveScoresPathFromScoresPath` is DELETED - which resolved finding F2, because the parquet a
task reads is now decided by task membership rather than by probing disk.

See that TODO's merge entry for the 446-file acceptance numbers and the deferred findings.
