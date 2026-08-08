# Osprey Stage 7: SecondPassFDR is the whole-run memory peak — characterize live vs GC-gray before choosing a lever

## Branch Information
- **Branch**: `Skyline/work/20260808_stage7_secondpass_memory`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-08-08
- **Status**: In Progress
- **GitHub Issue**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
- **Module**: `osprey`
- **Other labels**: `performance`
- **PR**: (pending)
- **Requester/Reporter**: none (filed by Brendan, developer of Osprey — no credit line)

## Objective

Settle whether the Stage 7 (`SecondPassFDR`) memory high point is a live survivor
pool or Server-GC committed-but-free "gray" (#4404), **measured post-GC**, and only
then decide whether a lever is wanted.

The narrow question the issue has converged on, from its 2026-08-07 comment:
**can `SecondPassFdrTask` consume its input per file instead of as one whole-run
buffer?** It reads `ctx.Get<RescoredEntries>()`, the whole-run buffer that Stage 6
deliberately rebuilds at the end of its loop (`PerFileRescoreTask.cs:333`) for this
one consumer. Protein FDR and the blib write have genuinely whole-run components, so
this is a design question, not a wiring one — unverified either way.

## State of the issue (do not re-derive from the title)

The issue has been rescoped twice; both earlier premises are recorded as dead in its
comments. Carrying the corrections here so they survive compaction:

* **The "characterize first" step was done once (2026-07-31) but only by proxy.** The
  49.0 GB peak decomposed as ~13 GB live / ~9.5 GB sawtooth garbage / ~26 GB allocator
  headroom — but the "live" figure is the sawtooth FLOOR, a proxy, not a measurement.
* **The original suspected cause is gone.** #4528 (merged 2026-08-04) deleted the
  2nd-pass Percolator retrain entirely; Stage 7 wall time went 35.6s -> 3.2s.
* **"Re-measure after #4536 lands" was the wrong plan.** #4536/#4545 (merged
  2026-08-08) buys a *duration* reduction in Stage 6, not a *peak* reduction at
  Stage 7 — by design, since Stage 6 rebuilds the buffer for Stage 7 at the end of
  its loop. An unchanged Stage 7 peak is the expected result and is NOT evidence
  #4536 failed.
* **No run in this issue has ever used `OSPREY_LOG_MEMORY=1`.** Every figure quoted
  in it — the 49.0 GB peak, the 63.1 GB default-arm peak, the +165 MB/file floor
  drift, all five arms of the default-flip table — is `--memstamp`
  (`GC.GetTotalMemory(false)`), i.e. shape not magnitude. That is the measurement gap
  this branch closes first.
* **Stage 7 is mostly inherited baseline.** It ENTERS at 38 GB under
  `protein-compact` vs 24-25 GB under `transfer`; its own delta is ~10-14 GB in every
  arm. A lever here moves the peak, not the slope.

## Reusable rig (already paid for)

`D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\stage6\stage6-16files` (199 GB) —
left behind by #4536, Stage 1-5 prep (55 min) and Stage 5 (9 min) already paid.
Contains 16 each of `*.scores.parquet`, `*.1st-pass.fdr_scores.bin`,
`*.reconciliation.json`, `*.scores-reconciled.parquet`, and **zero**
`*.2nd-pass.fdr_scores.bin`.
Library: `D:\test\Pilot-MTG-Tissue-May2026\lib\regression\target+decoy+entrapment`.

Three traps, all documented on the issue and in
`ai/scripts/Osprey/SEA-AD/Measure-Stage6Rescore.ps1`:

1. **Zero 2nd-pass sidecars is required state**, not an accident. A repeat run against
   a populated directory self-gates to a no-op, exits 0, prints no error, and measures
   nothing. Clear them between repeats.
2. **Never point `Measure-Stage6Rescore.ps1 -PhaseDir` at a real run directory** — it
   begins each measurement with `rm *.2nd-pass.fdr_scores.bin
   *.scores-reconciled.parquet` inside the phase dir. Hard-linking artifacts in is
   equally unsafe (a rejected version check re-runs prep and writes through the link).
3. **Pass all N files in one invocation.** The HPC chain runs these tasks once per
   stem, so a per-stem drive makes the resident band flat by construction.

## Tasks

- [ ] Measure Stage 7 with `OSPREY_LOG_MEMORY=1` post-GC probes at the 16-file rig —
      the measurement this issue has never taken
- [ ] Establish the per-file SLOPE of the Stage 7 live set (4/8/16 files), not just a
      single peak — the slope is what decides whether 163/300 files fit
- [ ] Decide from those numbers whether the peak is live or gray, and record the
      verdict on the issue either way
- [ ] Only if live: decide whether `SecondPassFdrTask` can consume its input per file
      instead of as one whole-run buffer (protein FDR + blib write are the whole-run
      components to prove out)
- [ ] If it can, remove the Stage 6 end-of-loop rebuild (`MaterializeAllSurvivors`)
      with it — it exists only to serve this consumer
- [ ] If the peak is gray, close the issue with the measurement rather than shipping a
      lever

## Gates (if a fix is designed)

* `regression.ps1 -Dataset All` byte-identical (mode1/2/3) — Stage 7 feeds the blib
* `Build-Osprey.ps1 -RunTests -RunInspection`
* Memory A/B showing the peak actually moved, measured **post-GC**, not `--memstamp`

## Regression Test

- **Test name**: (filled in once written — expected shape is a resident-pool guard
  assertion in `ResidentPoolGuardTest` if Stage 7 gains a streamed path, matching how
  #4536/#4537 pinned Stage 6)
- **Test project**: TestOsprey (or the Osprey test assembly the guard lives in)
- **Fails on master**: (not yet — no code change designed yet)
- **Passes on fix**: (not yet)

This branch may end in a measurement and an issue close rather than a code change. If
so, that is the explicit answer for this section: no regression test, because no
behavior changed. It is not acceptable to ship a Stage 7 streaming change without a
guard test — #4536's precedent is that the guard is what keeps the streamed path from
silently reverting to resident.

## Progress Log

### 2026-08-08 - Session Start

Starting work on this issue. Read the full comment history: the issue has been
rescoped twice and both earlier premises are dead (see "State of the issue" above).
Actionable next step is the post-GC measurement at the 16-file rig, which is
ready-to-run and already prepped.

### 2026-08-08 - Root cause of the missing measurement, and the first live number

**Why the measurement was never taken: the probe did not exist.** `SecondPassFdrTask`
carried exactly one memory probe (`LogMemoryStatsIfEnabled` after the library-fragment
release) and **zero** `LogManagedHeapAfterGcIfEnabled` calls. Stage 5 has 6 post-GC
probes and Stage 6 has 5; Stage 7 had none. So "no run in this issue has ever used
`OSPREY_LOG_MEMORY=1`" understates it - setting that variable would not have produced a
Stage 7 live number, because nothing in Stage 7 logged one.

Added five post-GC probes decomposing the stage: `stage7-inherited`,
`stage7-fragments-released`, `stage7-pass2-scored`, `stage7-protein-fdr`,
`stage7-blib-written`, each paired with a pre-GC line where the transient matters.

**First live number, 16 files** (`--task SecondPassFDR` against the #4536 rig; log
`D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\stage6\stage6-16files\smoke-stage7-16f.log`):

| probe | managed_heap |
|---|---|
| `stage7 start (pre-GC)` | **40.17 GB** (working_set 41.07, gc_committed_last_gc 37.67) |
| `stage7-inherited` (post-GC) | **7.53 GB** |
| `stage7-fragments-released` | 5.04 GB (released 5,297,961 of 6,324,700 library entries) |
| `stage7-pass2-scored` | 5.03 GB (pre-GC transient 10.24 GB) |
| `stage7-protein-fdr` | 5.03 GB |
| `stage7-blib-written` | 5.03 GB |

Two readings, both bearing directly on the issue:

1. **The `--memstamp` figure overstates the live set by ~5.3x at this file count**
   (40.17 vs 7.53 GB). That is the "gray, not live" hypothesis in the issue title,
   measured rather than inferred, and it is a much larger gap than the 2026-07-31
   sawtooth-floor proxy suggested.
2. **Stage 7 adds nothing to the live set.** It goes 7.53 -> 5.04 (the fragment release
   FREES 2.5 GB) and then stays at 5.03 through pass-2 scoring, protein FDR, and the
   blib write. Every substep's whole-run aggregation is a transient over a pool that
   was already there. So a lever inside `SecondPassFdrTask` has nothing to remove -
   which retires the 2026-08-07 re-rescope's first task as posed.

Slope sweep at 4/8/16 running to separate the fixed library component (4.38 GB at
6.3 M entries, pre-release) from the per-file pool.

### 2026-08-08 - The real O(files) structure, and the fix

**Correction to the framing above, before it propagates.** The 16-file measurement is of
the `--task SecondPassFDR` HPC node, NOT the arm the issue's 82-file figures came from.
Those are all straight-through, where Stage 6 hands Stage 7 the already-compacted buffer in
memory. The HPC node instead reloads every input's FULL PRE-COMPACTION stub list before
compacting - the pool `hpc-merge` names. Measured in-run, it grows **2.07 GB/file**
(7.6 GB after file 1 -> 40.8 GB after file 16, monotonic), projecting to ~186 GB at 82
files and far worse at the 500-file target. Brendan's call: that is not acceptable either -
it makes the final join impossible on any HPC node - so this issue's remaining content is
to fix it, not to document it.

**The bounded loader already existed; this node was excluded from it by two stale gates.**
`LoadJoinOnlyScores` has twins: `RescoreHydration.HydrateCompactedStreaming` (compacts each
file as it loads, never more than one file's pool resident) and a resident `for` loop whose
own comment says it "is O(files) and does not fit at 82".
`PreCompactionPoolReason` (`PerFileScoringTask.cs`) sent this node to the resident twin via:

1. `if (config.ExpectReconciledInput) return "The reconciled-input merge (#4486)"` - the
   deferral marker itself, naming no actual consumer.
2. `if (!config.NoJoin) return "A reconciled-bundle rehydrate outside the streaming gate"`,
   justified as "FirstPassFDR is IN this pipeline, so it will Run and train first-pass
   Percolator off ScoredEntries".

**Gate 2's premise is false on this node.** `FirstPassFdrTask.IsIncluded` is
`(inputs && !NoJoin && !ExpectReconciledInput)`, i.e. FALSE when `ExpectReconciledInput` is
set. `!NoJoin` was a PROXY for "FirstPassFDR will run", and the proxy is wrong for exactly
this one task. Nothing on the node trains off the pre-compaction pool.

Verified no other pre-compaction consumer exists there:
* `Pass2FdrSidecar` frozen modes (`transfer-compete` / `protein-compact`, the current
  default) run a **streamed** full-population competition off each file's
  `.1st-pass.fdr_scores.bin` scalars, one file resident at a time.
* Its resident retrain fallback is O(survivors), and fails fast on this node anyway.
* Protein FDR, the blib write and FDRBench pass 2 are O(survivors); mdiag has a streaming
  accumulator; `--fdrbench-pass 1` keeps its own separate token.
* `AllHaveReconSidecars` is already true on the node (the chain copies both sidecars per
  stem), so the compaction predicate is present at load time.
* The resident twin loaded PIN features that `HydrateRescoreBundleIfPresent` then **nulls
  unread** - the code's own comment prices that at "~800 MB per file ... the dominant term
  in the O(files) rehydrate peak". Pure waste.

**Change made:**
* `FirstPassFdrTask.IsIncludedFor(OspreyConfig)` extracted from `IsIncluded`, so the
  membership rule has one definition and cannot drift from a proxy again.
* `PreCompactionPoolReason`: dropped the `ExpectReconciledInput` early return; replaced
  `!config.NoJoin` with `FirstPassFdrTask.IsIncludedFor(config)`.
* `NeedsResidentPool`: dropped `config.ExpectReconciledInput`.
* `ResidentPoolTrigger`: dropped the `ExpectReconciledInput -> HPC_MERGE` branch.
* `ResidentPaths`: `HPC_MERGE` retired with a tombstone comment (the ratchet shrinking a
  third time, after `mdiag-full-resume` #4505 and `resume-survivor-handoff` #4536).
* `ResidentPoolGuardTest`: guard properties re-pinned on `fdrbench-pass1`; new assertion
  that `--task SecondPassFDR` needs no resident pool AND that no token can admit it if it
  regresses.

576 unit tests green.

### 2026-08-08 - Gates on the streaming fix

* `regression.ps1 -Dataset Stellar`: **PASS**, all modes, blib byte-identical at
  25,407,488 bytes across straight-through / mode 1 golden / mode 3 HPC chain / mode 2
  resume / mode 5 rehydrate. Mode 3 is the leg that runs `--task SecondPassFDR`, so it is
  the direct oracle for this change. The gate's own summary now reports
  "Known O(files) resident paths this gate still traverses: none".
* `Build-Osprey.ps1 -RunTests -RunInspection`: 576 tests pass, 0 errors, 0 warnings.
  The first inspection run caught a dangling `<see cref="ResidentPaths.HPC_MERGE"/>` in the
  Stage 6 handoff guard's remarks, fixed in a follow-up commit.
* Memory A/B pending: baseline (resident) sweep at 4/8/16 finishing, then the identical
  sweep against the streamed binary. Baseline logs are preserved under the phase dir's
  `baseline-resident-4486/` before the after-run overwrites them in place.

Baseline to beat (post-GC, `--task SecondPassFDR`, 16-file rig):

| files | Stage 6 resident | Stage 7 inherited | Stage 7 blib |
|---|---|---|---|
| 4 | 2.07 GB | 5.19 GB | 2.68 GB |
| 8 | 2.22 GB | 5.94 GB | 3.44 GB |
| 16 | 2.22 GB | 7.53 GB | 5.03 GB |

In-run pre-compaction reload at 16 files: 7.6 GB after file 1 -> 40.8 GB after file 16,
i.e. **2.07 GB/file**, monotonic. That is the number the fix has to flatten.

Binaries pinned for the A/B: `D:\test\osprey-runs\_bin\stage7-probes-4486` (baseline,
probes only) and `D:\test\osprey-runs\_bin\stage7-streamed-4486` (probes + streaming fix).
