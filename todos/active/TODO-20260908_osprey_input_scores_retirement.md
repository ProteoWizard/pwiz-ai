# TODO-20260908_osprey_input_scores_retirement.md - retire `--input-scores`, a Rust-era seam the C# port already replaced

**Module**: `osprey`
**Status**: In Progress. Proposed by the developer 2026-09-04 and written up in
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
