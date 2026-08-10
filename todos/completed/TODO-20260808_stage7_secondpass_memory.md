# Osprey Stage 7: SecondPassFDR is the whole-run memory peak — characterize live vs GC-gray before choosing a lever

## Branch Information
- **Branch**: `Skyline/work/20260808_stage7_secondpass_memory`
- **Worktree**: `C:\proj\pwiz`
- **Base**: `master`
- **Created**: 2026-08-08
- **Status**: Completed
- **GitHub Issue**: [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
- **Module**: `osprey`
- **Other labels**: `performance`
- **PR**: [#4554](https://github.com/ProteoWizard/pwiz/pull/4554) (merged 2026-08-10 as 843f7e553a)
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
   *.scores-reconciled.parquet` inside the phase dir.
   (The #4486 comment adds "hard-linking artifacts in is equally unsafe". That is
   OVER-BROAD and cost this session ~15 min of needless copying - see
   ai/docs/osprey-development-guide.md, "Hard-linking artifacts between runs". Linking is
   normal when chaining your own runs; the risk is only a validity key that might not
   match, and a one-file probe settles that in minutes.)
3. **Pass all N files in one invocation.** The HPC chain runs these tasks once per
   stem, so a per-stem drive makes the resident band flat by construction.

## Tasks

- [x] Measure Stage 7 with `OSPREY_LOG_MEMORY=1` post-GC probes at the 16-file rig —
      the measurement this issue has never taken
- [x] Establish the per-file SLOPE of the Stage 7 live set (4/8/16 files), not just a
      single peak — the slope is what decides whether 163/300 files fit
- [x] Decide from those numbers whether the peak is live or gray, and record the
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

- **Test name**: `ResidentPoolGuardTest.TestResidentPoolGuardError` — extended with
  `AssertNeedsResidentPool(false, hpc)` plus a loop asserting no token (including the
  retired `"hpc-merge"` literal) can readmit `--task SecondPassFDR` if it regresses. The
  pinned `KNOWN_UNFIXED` set also drops `hpc-merge`, so re-adding the token fails here.
- **Test project**: `Osprey.Test`
- **Fails on master**: **yes** — verified by temporarily restoring master's
  `NeedsResidentPool` predicate (`config.ExpectReconciledInput ||`) on this branch:
  `Failed TestResidentPoolGuardError [40 ms]` at `ResidentPoolGuardTest.cs:103`
  (`AssertNeedsResidentPool`, `ResidentPoolGuardTest.cs:203`). Reverted immediately.
- **Passes on fix**: **yes** — 576/576 with the predicate restored to the fixed form.

This is the guard-shaped test #4536/#4537's precedent calls for: the guard is what keeps a
streamed path from silently reverting to resident, and asserting the WHOLE `KNOWN_UNFIXED`
set means re-adding the token shows up in review as the ratchet running backwards.

Not covered by a unit test, and covered instead by `regression.ps1` mode 3: that the
streamed load produces byte-identical output on the HPC chain. No unit test can reach
that - it needs real parquets and a real 4-task chain.

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

### 2026-08-08 - Memory A/B result: necessary, not sufficient

Same 16-file rig, same Stage 1-5 artifacts, two pinned binaries differing only in this
branch's streaming change. Baseline logs kept in `stage6-16files\baseline-resident-4486\`.

| files | peak private (baseline -> streamed) | pre-GC managed at S7 entry | live (post-GC) | spectra |
|---|---|---|---|---|
| 4 | 18.80 -> 15.96 GB | 15.05 -> 6.90 GB | 5.19 / 5.19 | 52,084 both |
| 8 | 29.25 -> 19.90 GB | 9.87 -> 8.10 GB | 5.94 / 5.96 | 54,432 both |
| 16 | 45.73 -> 25.88 GB | 39.64 -> 9.79 GB | 7.53 / 7.56 | 59,102 both |

* **Peak-private slope 2.06 -> 0.75 GB/file** (8->16, the representative range). At 16
  files the peak drops 43% and the pre-GC managed heap at Stage 7 entry drops 75%.
* **Stage 7 got 32% faster** (7:19 -> 5:00 at 16 files): it stops reading and discarding
  ~52x the surviving rows.
* **Live set and output are unchanged at every point**, which is the correctness argument
  in the same table as the memory argument.
* Behavioral confirmation independent of the numbers: the resident `[WARN] ... requires the
  RESIDENT pre-compaction first-pass pool` line is gone, and the per-file load line changed
  from `Loaded N FDR stubs + features` to `Loaded N FDR stubs (features not loaded - not
  read on this path)`. Same stub counts per file, so identical work.

**Two corrections to numbers quoted earlier in this session**, recorded because both were
stated before the full range was in:

1. An "~8x slope reduction" was inferred from the 4->8 working-set pair. Across the full
   4->16 range it is 2.8-4x depending on the counter. Direction and mechanism hold; the
   magnitude came from too short a baseline.
2. The N=4 headline used `managed_heap`, which is `GC.GetTotalMemory(false)`. The baseline
   series reads 15.05 / 9.87 / 39.64 GB at 4 / 8 / 16 files - NON-MONOTONIC, because it
   samples wherever the last collection happened to land. That is the "shape not magnitude"
   trap this issue has flagged about itself since 2026-07-31, met first-hand. Peak private
   and the post-GC probes are the honest comparators.

**This does NOT reach the 500-file goal, and the PR must not claim it does.** What remains
is the LIVE survivor buffer at 0.197 GB/file - unchanged by this fix and unchangeable by
it, since it is Stage 7's input rather than its load. Projecting the live set:

* 82 files: ~4.4 GB library + ~16 GB survivors = **~20 GB live**, comfortable. The baseline
  reload projected ~194 GB peak there and could not run at all.
* 500 files: **~103 GB live**, still over a 64 GB node.

So this converts an impossible 82-file join into a routine one and leaves the whole-run
`RescoredEntries` buffer as the next wall - which is what this issue's title was about all
along. Making Stage 7 consume it per file is the real 500-file work and is a genuine design
question: protein FDR (parsimony + picked-protein TDC), `ClampExperimentQToBestRun`, and the
blib's cross-file indexes are all whole-run consumers. Recommend a separate issue for it
rather than growing this one a fourth time.

### 2026-08-08 - All gates green; PR held for /code-review

`regression.ps1 -Dataset All`: **44/44 PASS**, exit 0. All four `mode3 (HPC chain==straight)`
legs pass - that is the complete `--task SecondPassFDR` coverage the gate provides - plus
every mode-1 golden comparison, `StellarGenDecoyEntrap`'s true-FDP entrapment bounds, and the
mode-5 rehydrate diagnostics.

One mid-run observation worth recording so it is not re-investigated: on `StellarLibDecoy`
the straight-through blib is 25,174,016 bytes and the HPC chain / resume blibs are
25,178,112 - a 4,096-byte (one SQLite page) difference. It is NOT a failure. The printed
size is informational; the gate is `Compare-BlibFull`, which compares CONTENT, and mode 3
passed. Stellar's four blibs were byte-identical, so it is not a systematic effect of this
branch.

**PR deliberately NOT opened yet.** Description draft lives beside this file as `TODO-20260808_stage7_secondpass_memory-pr-description.md` (committed, so it survives /clear - the scratchpad does not). The version-control skill orders `/code-review <level>`
BEFORE `gh pr create` (Copilot auto-reviews on PR open and would spend a billed pass on code
that review might change; for Osprey nothing long-running triggers on PR open, so there is no
counter-argument to that ordering). `/code-review` is `disable-model-invocation`, so Claude
cannot run it - **Brendan needs to run `/code-review max` on this branch**, then the PR goes
up with the drafted title/body:

* Title: `osprey: Streamed the --task SecondPassFDR reconciled-input load`
* Labels: `osprey`, `performance`
* Body drafted at `todos/active/TODO-20260808_stage7_secondpass_memory-pr-description.md`
  (committed); issue comment posted as
  [#4486 comment](https://github.com/ProteoWizard/pwiz/issues/4486#issuecomment-5227109043)
* `See #4486`, NOT `Fixes` - the whole-run survivor buffer at 0.197 GB/file is still the
  500-file wall and is what this issue's title names

## Open items (not done, not blocked - flagged rather than silently dropped)

1. **`/code-review max`** - user-invoked only.
2. **The straight-through arm has no post-GC measurement.** Every 82-file figure on #4486
   comes from that arm, and it was never the failing case, but the prediction that it follows
   the same fixed-library + 0.197 GB/file model is a PREDICTION. The harness has a
   `-StraightThrough` mode ready; one sweep at 4/8/16 would settle it.
3. **The 500-file survivor-buffer work** - recommend its own issue rather than rescoping
   #4486 a fourth time.
4. **`OspreyEnvironment.AllowUnfixedResidentUnrecognized` has no consumers** (pre-existing
   dead code, found while checking this change could not hard-fail on a retired token). Its
   doc says it exists so the guard can distinguish a typo'd token from an unset one; that
   message is never emitted. Left alone as out of scope.

## SCOPE CHANGE 2026-08-08: one PR covering Stage 7 memory AND reporting

Brendan's call: a single PR that fixes Stage 7 memory and reporting, even if it spans
sessions via `/pw-handoff` + `/pw-continue`. Do NOT open the PR until that is done. The
branch keeps everything: probes, the `--task SecondPassFDR` streaming fix (already green),
the pass-2 competition memory, and the reporting gaps.

### Correction that forced the rescope

The published claim `stage-7 own slope: 0.001 GB/file` is WRONG and has been corrected on the
issue ([comment](https://github.com/ProteoWizard/pwiz/issues/4486#issuecomment-5229971150)).
It came from post-GC probes that fire at substep BOUNDARIES; the pass-2 competition allocates
and releases between them, so the phase looked free. At 16 files its state is ~2.5 GB and
hides; at 82 files it is ~13 GB and dominates. **FIXED 2026-08-09**: the PR description draft is now committed beside this TODO with the
wrong claim removed and an explicit "do not reintroduce" note, plus `TODO(stage7-work)`
markers on the sections the Stage 7 work must fill in.

### Measured, 82-file straight-through (4:26:08, exit 0)

Step 3 of `ComputePass2TransferCompeteFull`, by its own per-file progress: managed 41.0 ->
56.8 GB, private 53.8 -> 63.7 GB, monotonic across every decile = **+0.214 GB/file the GC
never reclaims**. `peak_paged` 63.92 GB - commit at the 64 GB line at 82 files. Projects to
~146 GB at 500 files from this phase alone.

Per-file stages are FINE and should not be touched: Stage 6 held a ~4 GB managed floor /
~17 GB private for 2h47m, `[MEM reconciliation-resident] 2.90 GB (files=82,
file_parallelism=1)`. The problem is entirely the JOIN stages.

### The work, in the order it should be done

1. **Re-key the two dictionaries that never needed (file, entry).** Provably
   output-identical, so it lands first and cheaply:
   * `survivorExpQ[key] = max(baseIdExpQ[bid], minRunQ[eid])` - both inputs keyed by
     base_id / entry_id, so the value NEVER depends on fileKey. 86.6 M slots holding ~1 M
     distinct values -> `Dictionary<uint,double>` by eid, ~85x smaller.
   * `survivorPep[key]` is 1.0 except on the single experiment-winner observation per
     base_id (~700 K of 86.6 M) -> sparse map + 1.0 default.
2. **Decide `survivorRunQ`'s shape.** It is the only genuinely per-(file, entry) result, and
   step 4's map-back consumes it ONE FILE AT A TIME. Options, cheapest first:
   `Dictionary<string, Dictionary<uint,double>>` (kills 86.6 M filename hashes, fixes most of
   the 191s, still O(observations)); per-file `double[]` parallel to the sidecar's `uint[]
   eids` (8 B vs ~40 B, needs a per-file eid->position map, bounded and dropped per file);
   or do not retain it whole-run at all.
   NOTE: `eid` = entry_id, base_id in the low 31 bits (`PercolatorEntry.BASE_ID_MASK`) with
   the decoy flag high. A LIBRARY identifier, not a dense index - a flat array over it is
   sparse. Density has to come from per-file position.
3. **Fix the comment above the call in `Pass2FdrSidecar`** claiming the state is "bounded by
   the number of distinct precursors ... flat in file count". It is false for the outputs and
   is what made the phase look safe.
4. **Progress reporters.** The map-back already iterates `perFileEntries` - 82 natural units,
   trivial. The streaming-FDR tail needs a reporter threaded in; the
   `foreach (var key in survivorSet)` population loop over 86.6 M is the piece to report. The
   root defect is that progress counts `readFileScalars` calls, so 100% means "input
   consumed", not "nearly done".
5. **The other three gaps (35s / 33s / 32s)** - diagnose before adding anything. The 35s sits
   between `[STAGE-WALL] second-pass-fdr` and the pre-GC probe, which smells like the 82
   `.2nd-pass.fdr_scores.bin` writes (4.8 GB), not a missing reporter.

### The iteration rig - this is the big enabler

`D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\stage5to7-82f-4486` (300 GB) now holds all
82 of: `.scores.parquet`, `.1st-pass.fdr_scores.bin`, `.1st-pass.model.json`,
`.reconciliation.json`, `.scores-reconciled.parquet`, `.2nd-pass.fdr_scores.bin`, plus
out.blib. So Stage 7 alone re-runs at 82 files in **~26 min** (`[TASK] SecondPassFDR:done
(1588.0s)`) instead of 4.5 h:

```
--task SecondPassFDR --input-scores <82 *.scores-reconciled.parquet>
  -l D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-gated-no-il\carafe_spectral_library.tsv
  --decoys-in-library --decoy-pairing-manifest <same dir>\osprey_library_db_pairing.tsv
  --resolution hram --fdr-level precursor --threads 30 --output-dir <rig>
  --timestamp --memstamp --perf-stats --model-diagnostics
```
* `OSPREY_VERSION_OVERRIDE=26.1.1.215` (artifacts are stamped that; without it every parquet
  is refused with a mismatch that reads like a code bug)
* `OSPREY_LOG_MEMORY=1` for the post-GC probes
* **Clear `*.2nd-pass.fdr_scores.bin*` and `out.blib*` first** or the task self-gates to a
  no-op, exits 0 and measures nothing
* NO resident token needed - this branch retired `hpc-merge`, so this one command exercises
  BOTH the branch's streaming change and the Stage 7 work

Baseline to beat, from the straight-through run: step 3 climbs 41.0 -> 56.8 GB managed
(+0.214 GB/file); Stage 7 wall 1588.0s; 191s silent gap after the competition's 100%;
`stage7-inherited` 24.43 GB; blib 37,078 spectra from 3,037,028 passing entries.

### Gates unchanged

`regression.ps1 -Dataset All` byte-identical (44/44 green on the branch as of 2026-08-08),
`Build-Osprey.ps1 -RunTests -RunInspection` (576 tests, 0/0), and `/code-review max` -
USER-INVOKED, Claude cannot run it (`disable-model-invocation`).

## BLOCKER from /code-review max (2026-08-09) - read before resuming

Findings live in `TODO-20260808_stage7_secondpass_memory-review.md` beside this file.

**Finding 1 is a VERIFIED blocker and the PR must not open until it is settled.**
`HydrateCompactedStreaming` compacts before publishing `PerFileEntries`, so routing
`--task SecondPassFDR` onto it makes the join node run first-pass protein FDR on an
already-compacted pool. The batch twin did not. That changes the decoy null, and
`regression.ps1` mode 3 structurally cannot witness it because phase 4 copies the pass-2
sidecars in and the overlay overwrites the affected values.

Settle it with the FDRBench entrapment oracle, not byte-parity. The other 14 findings are
UNVERIFIED - reproduce or refute each; pushing back with a reason is a legitimate outcome.

### 2026-08-09 - Session end: review fix pass, gates green, PR still held

`/code-review max` on the branch returned 15 findings; **12 addressed**, all gate-green.
Per-finding status and the open items live in
`TODO-20260808_stage7_secondpass_memory-review.md`.

Branch is 12 commits, clean tree, nothing uncommitted in either repo:

```
1503b0013f Corrected two comments that no longer described the code
3a9927b369 Pinned the first-pass membership truth table across tasks
957b64f04b Listed the untokened Stage 6 to 7 survivor buffer in the gaps table
31af2e17f1 Skipped the pre-compaction tally where its only reader is excluded
72f6ed9c93 Built the mdiag accumulator only where its reader runs
9b8e51c807 Warned when OSPREY_ALLOW_UNFIXED_RESIDENT names no known path
3544d7533e Addressed code-review findings on the Stage 7 streaming change
e2bdf7e41a Kept the reconciled-input merge off the lean counts-only load
1d255e023b Updated the resident-token doc example off the retired hpc-merge
334be6f3b6 Fixed a dangling doc reference to the retired hpc-merge token
6206c09f15 Streamed the --task SecondPassFDR reconciled-input load
45f811b577 Added post-GC memory probes to Stage 7 SecondPassFDR
```

**Gates**: `regression.ps1 -Dataset All` **44/44 PASS** after the fix pass (identical to the
pre-fix run, so nothing regressed); 577 unit tests; inspection 0 errors / 0 warnings. The
gate summary now names the #4486 gap (`#4486  token: NONE`) with required tokens still 0.

**The PR is still held, on one thing**: review finding #1 is GUARDED but NOT VALIDATED, and
`regression.ps1` cannot validate it - mode 3 copies the pass-2 sidecars into phase 4, so the
overlay overwrites exactly the protein q the guard changes. The FDRBench oracle is owed.
After that: the remaining findings, then the Stage 7 competition memory work (the reason
this is one PR), then `/code-review max` (user-invoked), then open.

Three measurement lessons from this session, all the same shape - a reassuring number that
was correct and a conclusion from it that was wrong: `--memstamp` overstates live by 5.3x at
16 files; post-GC probes at substep BOUNDARIES cannot see a phase that allocates and releases
between them (this produced a claim retracted on the issue); and a byte-parity gate can
overwrite the very value it would need to witness. `perfviz.py` gained a `sustained` metric
and a per-phase table because of the second one.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260808_stage7_secondpass_memory.md` before starting work.

### 2026-08-09 - Brendan set the governing rule: no O(files x entries), ever

Session was redirected before any code: **stop treating this as "shrink the big
dictionaries" and treat it as a sequencing problem.** The rule, in his terms:

1. Per-run q values are calculated file by file, in sequence - no spike, O(one file).
2. As that happens each entry accumulates an aggregate composite score, which is
   O(entries): trivially so for `max()`, and still O(entries) for `mean(best-N)`
   because N is a small constant (`O(N x entries)`).
3. Experiment-wide q values are then computed from that O(entries) aggregate -
   `Dictionary<EntryId,double>` for max, `Dictionary<EntryId,double[N]>` for
   mean-best-N.

The library is O(entries) and the PerFile tasks already handle O(entries) fine. Any
O(files x entries) structure is the defect, not the baseline.

**The consequence that makes it non-trivial, and that a naive implementation always
misses**: run q is genuinely per-(file, entry), but the output record ALSO needs
experiment q, which is unknown until every file has been folded in. So emission must be
a SECOND streamed per-file pass. Nothing per-observation may outlive its file's scope.
Any design that "keeps the answers until the end" is O(files x entries) by construction
however well the roll-up itself is written.

**This algorithm already exists in-tree for the 1st pass**:
`PercolatorScorer.RunStreamingFirstPass` (three streamed passes, bounded maps only,
byte-identical to the resident path). Its own doc says "This is 1st-pass-only: the 2nd
pass keeps its O(survivors) resident projection". Stage 7 never adopted it.

#### What was actually wrong in Stage 7 (verified by reading, not inferred)

The roll-up ACCUMULATORS were already correct and bounded - `bestTarget`/`bestDecoy`
(`Dictionary<uint base_id, ...>`), `minRunQ` (`Dictionary<uint eid, double>`),
`baseIdExpQ`, `winnerLoc`. The RETENTION was the whole problem. Six (file, entry)-keyed
structures, ~200 B/observation x 86.6 M observations at 82 files:

| structure | site | collapses to |
|---|---|---|
| `survivorScore` | `Pass2FdrSidecar.cs:537` | per file (it is file i's features scored) |
| `survivors` + `survivorSet` | `:584`, `StreamingFdr.cs:168` | per-file ids + global `survivorEntryIds` |
| `survivorExpQ` | `StreamingFdr.cs:173` | NOTHING - `max(baseIdExpQ[bid], minRunQ[eid])`, no fileKey term |
| `survivorPep` | `:174` | NOTHING - 1.0 unless `winnerLoc[bid]` names this exact (file, eid) |
| `survivorRunQ` | `:172` | the only genuine per-(file, entry) value |

~18 GB predicted vs **+0.214 GB/file x 82 = ~17.5 GB measured**, so the list accounts
for the measurement with no unexplained remainder - it is the whole problem, not a sample.

#### Run q: the retention question dissolved

Offered Brendan (1) recompute in the emit pass or (2) spill to the per-file sidecar. He
chose 2 and asked what 1 really cost; costing it honestly showed 1 collapses INTO 2 (to
avoid re-reading ~212 GB of parquet you must stash the score, which is the spill). But
the implementation needed neither: **the per-file `List<FdrEntry>` is already resident
and already has `RunPrecursorQvalue`**, so run q is written onto the entry as each file
finishes. No sidecar spill, no partial-file rename hazard, no extra I/O.

#### Implemented (builds, 577 tests, inspection 0/0)

* `StreamingFdr.ComputeFullPopulationPrecursorFdrStreaming` returns a bounded
  `StreamedCompetitionState` (O(distinct)) instead of three whole-run dictionaries;
  takes a per-file `readFile` (scalars + THAT file's frozen-model scores) and an
  `onFileRunQ` callback. `ExperimentQ(eid, runQ)` / `Pep(fileKey, eid)` derive the
  per-observation values on demand.
* `ComputePass2TransferCompeteFull`: the separate whole-run feature-scoring pass is
  FUSED into the streamed loop (kills `survivorScore` AND one full pass over the
  reconciled parquets); the two progress reporters merge into one that now covers the
  expensive half.
* Duplicate-stem invariant asserted (same guard, same reason, as
  `PercolatorScorer.ScoreProjectionAndComputeFdrInPlace`). Pre-existing hazard
  (`sidecarByKey` was already last-wins) that the per-file emit would otherwise turn
  into a silent mixture of refreshed and stale q. Relates to review finding 4.

#### Behavior finding recorded, deliberately NOT changed

Both `continue` guards in the old map-back (`if (!runQ.TryGetValue(key, ...)) continue;`)
were **dead**: the streamed form default-filled `survivorRunQ[key] = 1.0` for EVERY
survivor before returning. So the comment claiming an unchanged off-stratum survivor "is
absent from runQ and keeps everything" described behavior the code never had - such
entries were assigned run q 1.0. The refactor REPRODUCES that exactly (byte-parity gate)
and the comment is corrected to say what actually happens.

#### MEASURED 2026-08-09: the competition now costs nothing in live memory

Complete 82-file `--task SecondPassFDR` run, 24:47, exit 0, against the stage5to7 rig
(non-destructive: fresh scratch `D:\test\osprey-runs\stage7-4486-seq-after`, hard-linked
inputs, pinned exe `D:\test\osprey-runs\_bin\stage7-seq-4486`). Log
`ai/.tmp/`-equivalent scratch: `stage7-after-run.log`; plot `stage7-after-4486.png`.

**Output identical to baseline**: `Wrote 37078 library spectra to out.blib (from 3037028
passing entries)` - exactly the recorded straight-through figures. 86,581,597 survivor
observations scored.

| post-GC probe | managed |
|---|---|
| `stage7-inherited` | 25.97 GB |
| `stage7-fragments-released` | 23.74 GB |
| `stage7-pass2-scored` | **23.73 GB** |
| `stage7-protein-fdr` | 23.73 GB |
| `stage7-blib-written` | 23.73 GB |

Baseline step 3 climbed **41.0 -> 56.8 GB (+0.214 GB/file, monotonic every decile)**; this
run enters and leaves at 23.7 GB.

**Two instruments, deliberately.** Boundary probes ALONE cannot support this claim - that is
precisely how this issue produced its retracted "stage-7 own slope 0.001 GB/file". The
in-phase `--memstamp` series across the competition (which is what caught it last time):

`4% 41.6 | 12% 33.0 | 19% 37.1 | 26% 42.2 | 34% 42.7 | 41% 50.6 | 48% 24.1 | 56% 31.8 |
63% 33.6 | 70% 37.2 | 78% 42.6 | 85% 43.2 | 92% 46.7 | 100% 42.0` GB

Sawtooth with floors 33.0 / 24.1 / 31.8 / 33.6 - FLAT, not rising. Both instruments agree,
which is what makes the claim safe to publish.

Other numbers: Stage 7 wall 1486.8s (baseline 1588.0s); managed peak 51.8 GB, private peak
53.7 GB; perfviz `sustained 28.3 GB` (55% of peak). Load phase unchanged at +195 MB/file,
which is the survivor buffer this issue's title names and is NOT addressed here.

**Caveat to carry into the PR**: this is the `--task SecondPassFDR` arm; the +0.214 GB/file
baseline came from the straight-through arm. The rig's runbook designates this pairing and
the entry points nearly match (25.97 vs 24.43 GB), but it is NOT a strict same-arm A/B and
must not be written up as one.

**Reporting gap NOT closed**: perfviz flags one gap >= 30s in the whole run - **38s** right
after `[STAGE-WALL] second-pass-fdr: 919.2s`. That is the known 191s silent tail, now 38s
but still present, so the reporting half of this PR is unfinished (work item 4/5).

#### Process lesson (cost ~25 min)

Two failed launches before this one. (1) `run_in_background` bash wrapper was reaped at
~15 min, killing osprey at 31% - the Start-Process rule was already in memory and not
applied. (2) `Start-Process -RedirectStandardOutput` HOLDS native child output: 154 bytes
after 10 minutes of a live run, so there was nothing to plot. The working pattern is the
script Tee-ing its own log (`& $exe @args *>&1 | Tee-Object -FilePath $log`), which also
makes perfviz runnable mid-run.

#### Review finding 1 - RESOLVED 2026-08-09, refuted as a defect

The FDRBench oracle was built and run. Finding 1 predicted that recomputing first-pass
protein FDR over the COMPACTED pool collapses the decoy null and drives protein q
anti-conservatively low. Measured on `StellarGenDecoyEntrap` with the pass-2 sidecars
absent (which is the real chain behavior - the `--task PerFileRescoring` workers write
none, so `regression.ps1`'s conditional copy is a no-op and the join node always
recomputes):

| arm | vs straight-through | vs master routing |
|---|---|---|
| master routing (recompute, UNcompacted pool) | 33,190 differ | - |
| guard disabled (recompute, COMPACTED pool) | 33,190 differ | **0 - byte-identical** |
| guard on (recompute skipped) | 32,450 differ | 740 (0.28%), all more conservative |

Master and the unguarded compacted recompute are byte-identical, so the predicted collapse
does not occur for this statistic. Outputs identical in every arm (26,714 peptides, 21,861
protein groups, 23,292 blib spectra from 69,876 entries).

**The guard is KEPT anyway, on Brendan's reasoning rather than the review's**: the retained
set is passing-target-driven, and a target and its paired decoy share a base_id, so
retaining a base_id retains both - which drops the high-scoring decoys whose targets failed
and biases any FDR computed on the survivors optimistic. The clean subset would need a
composite-score cutoff admitting targets AND decoys above it plus pairs. So do not run an
FDR over that pool, independent of whether this particular statistic is sensitive. The
comment at `PerFileRescoreTask.cs` now states that, and records both refuted claims so they
are not restored. See [[reference_fdr_null_bias_from_paired_subsetting]].

**What the oracle DID find became [#4553](https://github.com/ProteoWizard/pwiz/issues/4553)**,
split to its own branch (`Skyline/work/20260809_fdr_sidecar_parity`) and TODO
(`TODO-20260809_fdr_sidecar_parity.md`): straight-through and the task-by-task route write
different `Score` and `RunProteinQvalue` into every `.2nd-pass.fdr_scores.bin`, because
`OverlayRescoredEntries` calls `ResetScores()` (clearing 8 fields) and `protein-compact`
restores only 5. Pre-existing, not from this branch, and deliberately kept OFF it: the new
check turns `-Dataset All` red until the divergence is fixed.

#### Still owed on this branch
2. Review findings: 8 PUSHED BACK with verification (see the review companion), three stale
   comments FIXED (commit 20f353f77b), 4 partly addressed by the duplicate-stem assert. The
   REST OF 9 remains: `ShouldStreamCompaction` / `PreCompactionPoolReason` are private and
   take a `PipelineContext`, so covering them means making them testable first (the same
   env-statics-passed-in shape `ResidentPoolGuardError` already uses). That is the one
   review item deliberately left for `/code-review max` to weigh in on.
3. `pass1ExpQByKey` is still (file, entry)-keyed. Bounded by CHANGED off-stratum peaks,
   so believed small, but that is an ASSUMPTION carried from the old comment, not a
   measurement.
4. First-pass spike: Brendan's call is Stage 7 first, first pass after. Note the default
   1st pass already takes the flat path (`RunFirstPassStreaming` when
   `projections.IsCountsOnly`); the resident sibling
   `ScoreProjectionAndComputeFdrInPlace` still allocates flat `[n]` score/label/entryId/
   peptide arrays over all files (~21 B/observation), which is where to look.

### 2026-08-09 - Branch READY for /code-review max

`regression.ps1 -Dataset All`: **44/44 PASS, 0 FAIL, exit 0**
(`scratchpad/regression-all-final.log`), with the competition change, the reporters and the
corrected comments all in. 577 unit tests, inspection 0 errors / 0 warnings.

Branch is 15 commits, clean tree:

```
58b5444143 Reported progress through the second-pass sidecar write and reload
20f353f77b Corrected three comments the streaming change had left stale
70a9cb611c Streamed the pass-2 competition's per-observation results
1503b0013f Corrected two comments that no longer described the code
3a9927b369 Pinned the first-pass membership truth table across tasks
957b64f04b Listed the untokened Stage 6 to 7 survivor buffer in the gaps table
31af2e17f1 Skipped the pre-compaction tally where its only reader is excluded
72f6ed9c93 Built the mdiag accumulator only where its reader runs
9b8e51c807 Warned when OSPREY_ALLOW_UNFIXED_RESIDENT names no known path
3544d7533e Addressed code-review findings on the Stage 7 streaming change
e2bdf7e41a Kept the reconciled-input merge off the lean counts-only load
1d255e023b Updated the resident-token doc example off the retired hpc-merge
334be6f3b6 Fixed a dangling doc reference to the retired hpc-merge token
6206c09f15 Streamed the --task SecondPassFDR reconciled-input load
45f811b577 Added post-GC memory probes to Stage 7 SecondPassFDR
```

**Next action is BRENDAN's**: `/code-review max` on this branch, then open the PR from
`...-pr-description.md` (every marker filled). Claude cannot run `/code-review`
(`disable-model-invocation`).

Process notes worth carrying, all cost real time today:

* A `run_in_background` bash wrapper was reaped at ~15 min, killing an 82-file run at 31%.
  Then `Start-Process -RedirectStandardOutput` HELD the native child's output (154 bytes
  after 10 minutes of a live run), so there was nothing to plot. The pattern that works is
  the script Tee-ing its own log (`& $exe @args *>&1 | Tee-Object -FilePath $log`), which
  also makes `perfviz.py` runnable mid-run.
* `-o out.blib` is RELATIVE to the process working directory, not `--output-dir`. Two
  82-file runs wrote a 211 MB blib into the pwiz repo root before this was noticed.
* A compound command beginning `cd /c/proj/ai` ran `git checkout -b` in the WRONG repo, so
  a pwiz commit landed on this branch and an `ai` push silently no-oped (pushing an
  unchanged local `master` from a non-master branch). Both recovered; verify `git
  rev-parse --abbrev-ref HEAD` in the repo you mean before committing.

### 2026-08-10 - Merged

PR #4554 merged as commit 843f7e553a. TeamCity Perf/Regression green on `pull/4554`
(build #199, all four `mode3 (HPC chain==straight)` legs plus the perf leg), local
`regression.ps1 -Dataset All` 44/44, 578 unit tests, inspection 0/0.

**What shipped**: the pass-2 competition emits per file, so none of the six whole-run
`(file, entry_id)` structures survive - the competition enters and leaves Stage 7 at
23.7 GB where the baseline climbed 41.0 -> 56.8 GB (+0.214 GB/file, monotonic), with
output identical at 37,078 spectra from 3,037,028 passing entries. Plus the earlier
`--task SecondPassFDR` streamed load, the five post-GC probes, and the reporters that
took the last >30 s gap to zero.

**What was DEFERRED, and the three unchecked boxes above say so honestly**: Stage 7 still
consumes the whole-run survivor buffer. That buffer is what this issue's TITLE names, it
still grows ~0.196 GB/file, and it is the remaining 500-file wall - so
`MaterializeAllSurvivors` stays. #4486 is deliberately left OPEN (the PR says `See`, not
`Fixes`) to carry it. The last box is N/A: the peak was live, not gray.

**Follow-up issues filed from work this branch turned up**:
* #4553 - straight-through drops `Score` and `RunProteinQvalue` that the task-by-task route
  keeps (`ResetScores()` clears eight fields, `protein-compact` restores five). Branch
  `Skyline/work/20260809_fdr_sidecar_parity` pushed with a failing gate check; whether Rust
  shares the defect is still unmeasured.
* #4555 - same-base-name inputs from different directories collide in artifact names and
  per-file maps; wants Skyline's partial-.skyd path hashing.

**Review**: `/code-review max` returned 15 findings, all verified rather than auto-applied;
13 produced changes, 2 were refuted with reasons. Two of those findings were defects this
branch had introduced mid-flight (gates that were unsatisfiable inside the streaming branch,
disabling the pre-compaction tally and the mdiag accumulator) and were reverted. Copilot
added 2 comments, both addressed and resolved. Per-finding detail is in the companion
`-review.md`.
