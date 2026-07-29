# Osprey Stage 6: stream PerFileRescore survivors instead of holding all files resident

## Branch Information
- **Branch**: `Skyline/work/20260727_osprey_stage6_rescore_streaming`
- **Base**: `master` (at `6d919a080e`, after #4442 merged)
- **Created**: 2026-07-27
- **Status**: ALL GATES GREEN, PR open as DRAFT awaiting `/code-review max` + human review
- **Worktree**: `C:\proj\pwiz` (BRENDANX-UW8)
- **GitHub Issue**: [#4472](https://github.com/ProteoWizard/pwiz/issues/4472)
- **PR**: [#4488](https://github.com/ProteoWizard/pwiz/pull/4488) (DRAFT - `-Dataset All` and the
  82-file proof run still outstanding; do not mark ready until both land)
- **Requester/Reporter**: none (Osprey developers; no credit line per version-control-guide
  "Crediting Reporters and Requesters" - role-scoped, Osprey developers are not outside requesters)

## Objective

`PerFileRescoreTask` holds every file's post-compaction survivor `FdrEntry` lists resident
at once (`_perFileEntries`, `PerFileRescoreTask.cs:113`, set from `CompactedEntries` at
`:201`), so Stage-6 resident memory is O(files). This is the last O(files) live structure
between us and a 500-file run on a 64 GB box, now that Stage-5 FirstPassFDR is flat (#4435).

Hold only the bounded cross-file reconciliation state resident and reload each file's
survivors on demand, mirroring the Stage-5 treatment. Byte-identical output is mandatory.

## Scope decision (2026-07-27, Brendan)

Issue #4472 carries THREE pieces. **ONE PR for the issue, covering A+B**; C splits out.

- **A. Stage-6 straight-through** - `_perFileEntries` holds all files' survivors
  (`PerFileRescoreTask.cs:113/201`). Root-caused; lever proposed.
- **B. HPC/resume** - `FirstJoin.Rehydrate` loads the full PRE-compaction pool
  (`FirstJoinTask.cs` ~447/474), forced by `ExpectReconciledInput` on every HPC merge.
  The issue calls this "the FIRST thing to explode at 500 files." Same lever as A; its
  own gate is regression mode2/mode3, plus the `--allow-unbounded-memory` guard interaction
  (the guard currently EXEMPTS `ExpectReconciledInput`; that exemption should close with B).
- **C. Stage-7 SecondPassFDR ~45 GB peak** - SPLIT OUT to [#4486](https://github.com/ProteoWizard/pwiz/issues/4486)
  (linked from #4472 so nobody works it thinking it is in scope). The issue states
  its root cause is uncharacterized and that the first step is `[MEM]` probes + dotMemory
  *before choosing a lever*. Folding an undiagnosed peak into a PR whose value is a crisp
  byte-parity gate is how the gate stops being interpretable.

Step carefully in separate commits: characterize -> fix A -> fix B -> gates. Multiple test
runs per step are expected; a red mode2/mode3 should point at ONE lever at a time.

## Characterization first (issue's own step 1)

Do NOT write the fix before the slope is measured. The issue asks for `[MEM]` probes to
confirm `_perFileEntries` - not the Stage-6 transients bounded by #4394 - is the slope
source, and for per-file bytes/row so the 500-file projection is exact.

**Harness**: `--task PerFileRescoring --input-scores <N parquets>` against Stage 1-5
artifacts built once. Two traps, both silent:

- **Pass N files in ONE invocation.** The HPC chain (`regression.ps1:644`) calls this task
  once per stem, so `_perFileEntries` holds exactly ONE file and the band is flat BY
  CONSTRUCTION. Driven that way the harness would show a fix that is not there.
  `--input-scores` accepts a directory / many parquets (`OspreyConfig.InputScores` is a
  `List<string>`; `PerFileScoringTask` loops it), which populates the real multi-file buffer.
- **Clear `*.2nd-pass.fdr_scores.bin` between repeats.** `PerFileRescoreTask.Run:240-248`
  self-gates to a NO-OP when any pass-2 sidecar is present. A repeat run that skips this
  measures nothing and exits 0.

Slope needs no extra generation: vary how many `--input-scores` are passed (4 / 8 / 16)
against ONE set of artifacts.

## Design findings (2026-07-27, sub-agent; full doc was ai/.tmp/stage6-streaming-design.md)

**The issue's premise is partly WRONG. Three corrections, all code-verified:**

1. **`PerFileConsensusTargets` / `ReconciliationActions` / `PerFileGapFillForRescore` are
   keyed BY FILE**, i.e. O(files x targets) - NOT the O(distinct) the issue assumes. Only
   `PeptideConsensusRT` is genuinely bounded.
2. **The slope driver is not the survivor stubs.** Stage-6 entry survivors are LEAN (~184 B;
   `LoadFdrStubsFromParquet` reads 10 scalar columns). The growth is the FAT payload Stage 6
   *attaches and never releases* - `Features` / `CwtCandidates` / `Fragment*` /
   `ReferenceXic*`, ~1-3 KB per rescored + gap-filled entry. Its only post-Stage-6 reader is
   `ReconciledParquetWriter`, per file, milliseconds later; Stage 7 reloads features from the
   reconciled parquet. The code already names this "the next memory lever" at
   `PerFileRescoreTask.cs:829-838`.
3. **`RescoredEntries` has exactly ONE consumer** - `MergeNodeTask.cs:125` - fanning out to
   seven genuinely run-wide reductions (2nd-pass Percolator, protein FDR/parsimony,
   `ClampExperimentQToBestRun`, the blib cross-file reductions, FDRBench, mdiag). None can
   become per-file inside this scope, so **the milestone must stay all-files**. Stage 7 is #4486.

**Two more corrections, to the gates:**

- The `--allow-unbounded-memory` guard does **NOT** exempt `ExpectReconciledInput` - it names
  it as trigger #1 and throws; `regression.ps1:841` opts mode 3 out. (The earlier note in this
  TODO said the opposite; it was inverted.)
- **Mode 3 never exercises the multi-file Stage-6 loop.** It runs one rescore worker per stem
  (`regression.ps1:625-666`), so `_perFileEntries` holds ONE file. **Modes 1 and 2 are the
  only gates for scope A.**

## Levers

- **L1 (taken first)**: release the six fat arrays per file right after its reconciled parquet
  is written. ~20 lines, no ordering/arithmetic/IO change. Kills the growth term.
- **L2**: publish a bounded `FirstPassSurvivorSource`, load/release survivors per file, rebuild
  for MergeNode via the resume path's own `OverlayReconciledIntoBuffer` +
  `SortFileEntriesCanonical` (byte-safe by construction - mode 2 already asserts warm == cold).

**L1-specific risk (R2, LOW detectability):** `ComputePass2Resident` lets an unmapped identity
keep stale `Features`; after L1 that becomes null -> basic-feature fallback. Only bites under
`OSPREY_FDR_PROJECTION=0`, **which regression never runs** - a green gate would NOT catch it.
Mitigation: nulling happens only after a SUCCESSFUL `WriteReconciledAndStamp` (which is the
guarantee the identity IS in the parquet), plus an explicit manual A/B with
`OSPREY_FDR_PROJECTION=0` on Stellar.

## Tasks

- [x] Verify issue line refs against master (`:113`, `:201`, `:208`, probe `:593`) - all correct
- [x] Stage the 82-file SEA-AD set locally: 82 mzML + 82 `.spectra.bin`, all caches ACCEPT
- [ ] Add the Stage-6 harness to `ai/scripts/Osprey/SEA-AD/` (shared + portable, per README)
- [ ] Build Stage 1-5 artifacts once for 16 files
- [ ] Measure the resident band at 4 / 8 / 16 files; confirm positive slope in file count
- [ ] `[MEM]` probe to attribute the slope to `_perFileEntries` vs transients
- [ ] Per-file bytes/row -> exact 500-file projection
- [ ] Design the fix: separate bounded cross-file state from per-file survivor reload
      (`ReloadFirstPassSurvivors` already does the per-file reload)
- [ ] Implement; keep the canonical `(EntryId, Charge, ScanNumber, ParquetIndex)` sort

## Regression Test

- **Gate**: `regression.ps1 -Dataset All` byte-identical, mode1/2/3. Reconciliation is
  byte-parity-sensitive; this is THE gate, not a smoke test.
- **Also**: `Build-Osprey.ps1 -RunTests -RunInspection`
- **Memory A/B**: the PerFileRescoring band slope goes to ~0 in file count, as the
  FirstPassFDR band now is. Confirm the 500-file projection clears 64 GB.
- **Fails on master**: (to verify - the slope IS the failure)
- **Passes on fix**: (to verify)

## Measured: two DIFFERENT growth terms (2026-07-28 01:25)

16-file SEA-AD artifacts, post-GC `reconciliation-resident`, identical rescored counts
before/after (268046 / 539804 / 1082875 - so no behavior change):

| files | baseline | after L1 |
|---|---|---|
| 4  | 4.82 GB | 4.68 GB |
| 8  | 5.25 GB | 4.93 GB |
| 16 | 5.86 GB | 5.28 GB |

across-run slope **0.087 -> 0.050 GB/file**; 500-file projection 47.8 -> 29.5 GB.

**The across-run slope and the within-run band are not the same quantity, and only the
second is what perfviz draws.** From the `[MEM]` probes:

- `library-resident` = **4.38 GB in BOTH the 4- and 16-file runs** - a constant floor, ~85%
  of resident, not file-dependent at all.
- Within the 16-file run, `perfile-rescore-live` goes **5.19 -> 5.35 GB over all 16 files**
  = **0.010 GB/file** during the loop.
- The 4-file run's first `perfile-rescore-live` is 4.74 vs 5.19 for 16 files: **0.037
  GB/file of the across-run slope is UP-FRONT state**, materialized before the rescore loop
  runs at all (all-files lean survivor stubs + the per-file-keyed planning maps).

So: 0.050 across-run ~= 0.037 up-front + 0.010 during-loop. L1 attacked the during-loop
term and cut it ~5x (0.050 -> 0.010). **No per-file release inside the loop can fix the
up-front 0.037** - that requires not materializing all-files state, i.e. L2.

Implication for the goal: over 82 files the band should climb ~0.8 GB instead of ~4.1 GB.
Whether that reads as "level" is what the 82-file run answers - do not assert it before.

## RESULT (2026-07-28) - what actually landed

Four commits on `Skyline/work/20260727_osprey_stage6_rescore_streaming`, pushed:

| commit | change |
|---|---|
| `83ef15dbd6` | release the six fat arrays after the per-file reconciled parquet write |
| `4a9af7fc90` | stop loading PIN features the rehydrate never reads |
| `cdcaa15dcb` | stream the rehydrate - compact one file at a time (861 lines) |
| `62e7792736` | guard `--input-scores`, bound `--model-diagnostics`, memstamp in regression.ps1 |

**82-file SEA-AD Astral, `--task PerFileRescoring`, identical Stage 1-5 artifacts:**

| | before | after | after + mdiag |
|---|---|---|---|
| peak private | ~197 GB projected | **32.2 GB** | **35.2 GB** |
| floor drift | 1.19 GB/file | +19 MB/file | +36 MB/file |
| gaps >= 30s | 4 (68/33/59/56s @ 16 files) | **0** (max 12s) | **0** (max 11s) |
| rescored | - | 6,954,057 | 6,954,057 (identical) |
| wall | - | 2:45:13 | 2:47:28 |

**Gates, all green on the full branch:** `regression.ps1 -Dataset All` 18/18 byte-identical
(modes 1/1b/2/3, four datasets); `Build-Osprey.ps1 -RunTests -RunInspection` 547/547 zero
warnings; `OSPREY_FDR_PROJECTION=0` on Stellar (the path the normal gate misses).

**Scope resolved with Brendan:** Stage 7 (`SecondPassFDR` / `ExpectReconciledInput`) is OUT.
It is a bounded-height bulge (~51 GB peak in a full 64 GB run), not a growth curve, so it
does not block an 82-file run - and Percolator is being removed from that stage, so
hardening it now would harden code about to be replaced. `regression.ps1:841` keeps its
`OSPREY_ALLOW_UNBOUNDED_MEMORY=1` opt-out for that reason. Tracked as
[#4486](https://github.com/ProteoWizard/pwiz/issues/4486).

## Remaining

- [ ] `/code-review max` (user-invoked), then flip #4488 out of draft
- [ ] TeamCity Perf/Regression on `pull/4488` - manual, ASK before triggering
- [ ] Residual ~19 MB/file (all-files lean survivor list, ~184 B/entry) - #4472's L2, not a
      blocker at 500 files (~10 GB rise, inside 64 GB)
- [ ] **Unread by the parent session**: the `PreCompactionTally` plumbing in `cdcaa15dcb`
      that feeds the `totalScored` zero-guard. The retain-set logic and the gate WERE read.

## Review risks, highest first

1. **`ShouldStreamCompaction`** (`PerFileScoringTask.cs`) - streaming must never hand a
   pre-compacted pool to a consumer expecting pre-compaction. Requires
   `hasReconSidecars && NoJoin && !NeedsResidentPool && !DumpPercolator`. Any future consumer
   inserted between `PerFileScoring` and FirstJoin's compaction re-opens it SILENTLY, and no
   gate we have would catch it.
2. **mdiag `Add` ordering** - both paths must feed the accumulator in identical order or
   `BuildScoreHistogram`'s floating-point sums drift. Test asserts it; subtlest claim here.
3. `cdcaa15dcb` is 861 sub-agent-written lines.

## Progress Log

### 2026-07-27 - Session start (BRENDANX-UW8)

Machine brought up for large-scale Osprey testing:
- Full TeamCity regression green from cold: 18/18 PASS, exit 0, 78 min (`-Dataset All`).
- 82-file SEA-AD set staged locally (324.5 GB mzML + 345.9 GB caches), all 82 caches
  validated ACCEPT against the v4 header + fingerprint rules.
- Confirmed cross-system `.spectra.bin` reuse works: caches written on another machine
  streamed here with no re-parse. Requires v4 exactly + mzML size/mtime match; nothing
  else (not path, machine, or search settings - the cache is settings-independent).
  25 mzML arrived with wrong mtimes from an upload race and were repaired as metadata.
- Library restructured to the SEA-AD README convention
  (`$env:OSPREY_SEAAD_LIB\target+decoy+entrapment\`); `Run-SeaAd.ps1 -WhatIf` resolves clean.

Issue #4472 re-verified against master; scope split recorded above.

## 2026-07-28 — `/code-review max` findings + fix pass (session end)

All local gates were GREEN on the 4 committed commits before review:
`regression.ps1 -Dataset All` 18/18 byte-identical at 1e-9; `Build-Osprey.ps1
-RunTests -RunInspection` 547/547 with zero inspection warnings; 82-file Stage 6
at 32.2 GB peak, 0 reporting gaps >=30s, +19 MB/file; 82-file with
`--model-diagnostics` at 35.2 GB peak, identical 6,954,057 rescored entries.

**Then `/code-review max` found 15 verified findings.** Three of the four commits
had real defects. The core streaming/compaction/ordering mechanism was verified
clean by two independent angles — every finding is in the wrappers around it.

Most severe, in order:

1. **`PerFileScoringTask.cs:1240` — guard throws for legitimate tasks.**
   `--task SecondPassFDR`, a `--task FirstPassFDR` re-run, and
   `OSPREY_DUMP_PERCOLATOR` all trip `GuardResidentPool` and hard-fail.
   **Masked locally because `regression.ps1:857` and `:889` set
   `OSPREY_ALLOW_UNBOUNDED_MEMORY=1` around the whole HPC chain** — so mode 3
   passing is NOT evidence the guard is safe. Decision: throw only for genuinely
   new O(files) situations; warn, naming the consumer, for the deferred paths.
2. **`ReleaseRescoredPayload` misses both resume arms** — the early return at
   `PerFileRescoreTask.cs:655-656` and `Rehydrate` at `:364-403`. O(files)
   retention is fully intact on any resume.
3. **Release is unconditional after a `WriteReconciledAndStamp` that can no-op.**
   When it no-ops, 2nd-pass Percolator trains on `BuildBasicFeatures` — 1 real
   dimension out of 21 — silently, with no error.
4. **mdiag accumulator pinned in `PipelineContext._byproducts`** with zero
   remaining readers, ~1-2 GB at 82 files. This is a large part of the measured
   +2.2 GB mdiag floor and the +36 vs +19 MB/file drift.
5. `TotalPreCompactionStubs` is an unchecked `int` — overflows past ~505 files.
6. The parity test asserts action `GetType()` only, never payloads, and its
   fixture injects both hooks so no production wiring is exercised.
7. `--memstamp` snapshots every process on the machine per log line; the comment
   claiming it "is noise" was never measured.

A sub-agent was applying all 12 fixes when this session ended — **its state is
unverified**. See the handoff for how to check.

Ordering decision (user): keep PR #4488 in **draft** until the fixes land and the
gates are re-run. Copilot auto-reviews on the ready flip (~2.5 min, observed on
#4460); flipping early would spend that pass re-finding these 15 on code being
actively rewritten.

Remaining to merge: verify the fix diff → `git merge origin/master` (3 commits;
**#4487 touches `FirstJoinTask.cs` AND `regression.ps1`**, both heavily modified
here, and is semantically adjacent — it changes what the merge node does with the
1st-pass model) → build + `-RunInspection` → `regression.ps1 -Dataset All` →
push → mark ready → **ask** before triggering TeamCity on `branch="pull/4488"`.

Not in this PR, deliberately: Stage 7 / `ExpectReconciledInput` (#4486, and
Percolator is being removed from that task anyway) and the residual ~19 MB/file
all-files lean survivor list (#4472 L2).

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260727_osprey_stage6_rescore_streaming.md` before starting work.

## 2026-07-28 night session — review fixes landed, merged master, gate re-run

**21:30 start.** Fix agent's 12 fixes were present in the working tree; I read the
full diff rather than trusting the report, and it matched on all twelve.

**Merged `origin/master`** (3 commits) — clean, including both files #4487 also
touched. Its `regression.ps1` change turned out to be purely additive Stage-5
sidecar relaying (`$s.1st-pass.model.json` through the ph2->ph3->ph4 hops), with
no interaction with the guard work.

**Inspection caught two real defects the agent's "build clean" check missed** —
it ran the compiler and unit tests but never `-RunInspection`:

* `ShouldStreamCompaction` passed `hasReconSidecars` into
  `PreCompactionPoolReason` from the right side of an `&&` that had already
  tested it, so the helper's own `hasReconSidecars` clause was dead code.
  Restructured: the helper now owns the whole predicate and reports a
  "no reconciled bundle" reason of its own.
* `TryHydrateRescoreBundle` returned `true` whenever `hydrate()` didn't throw —
  including on a null return — leaving every caller dereferencing a field whose
  non-nullness could only be established inside the callee. Turned into
  `HydrateRescoreBundleOrNull`, so the null test sits at the use site.

**Reverted the memstamp change** (F12). Measured 1.01 -> 0.95 ms/line: at one
log line every 2-5 seconds that is nothing, so the comment the finding attacked
("this is noise") was right and the finding's premise was wrong. It also traded
an obviously-correct call for a cached `Process` whose silent-failure mode is a
frozen, flat memory curve — a false "bounded memory" result on the very
instrument used to prove bounded memory. Not a trade worth 6%.

**Removed `OSPREY_ALLOW_UNBOUNDED_MEMORY` from `regression.ps1`** (modes 2 and
3), which was the user's stated precondition for merge. Now possible because the
`--input-scores` resident-pool path warns instead of throwing. The mode 3 opt-in
had wrapped the entire HPC chain and would have masked a real guard regression
on any `--input-scores` worker — exactly what mode 3 exists to catch.

Gate: **551/551 unit tests, zero inspection warnings.** Full
`regression.ps1 -Dataset All` running from 21:47 — the first run ever with the
guard armed on modes 2 and 3.

**Note for the 82-file re-measure:** the harness runs **Release net8.0**
(`Measure-Stage6Rescore.ps1:107`), not the Debug build the pre-commit gate uses.
A Release build + `-Exe` snapshot is required before the measurement, and
`-VersionOverride 26.1.1.208` because the phase-dir artifacts predate today's
daily build.

### Regression run 1 found a real gap: mdiag on a FULL resume is still O(files)

Removing both `OSPREY_ALLOW_UNBOUNDED_MEMORY` opt-ins made `-Dataset All` abort
at **StellarLibDecoy mode 2** ("Osprey exited 1"). Everything before it passed:
Stellar mode1/2/3, StellarLibDecoy mode1/1b/1b/3.

`PerFileScoringTask.cs`, `--input-files` rehydrate:

```csharp
bool needsResidentPool = NeedsResidentPool(config) ||
                         (config.ModelDiagnostics && FirstPassSidecarsPresent(config));
```

Mode 2's invalidation leaves every `.1st-pass.fdr_scores.bin` on disk, so
FirstJoin skips the first-pass score pass and emits the report through the batch
`ModelDiagnosticsReport.Write`, which reads the RESIDENT per-file entries.
StellarLibDecoy is the only dataset with a diagnostics golden, which is why
Stellar passed and it did not.

**The guard is right.** That path genuinely is O(files); the standard for this
work is that such a path must error unless the flag is set. This is not a
regression introduced here — the env var had been hiding it.

**Two things this does NOT affect**, and the distinction matters:

* `--model-diagnostics` over `--input-scores` — the scale path, what an 82-file
  run uses — streams off `ModelDiagnosticsData.Accumulator` one file at a time
  and needs no opt-in at any file count.
* `--model-diagnostics` on a `-LinkFrom` (Stage 1-4) resume: sidecars are
  absent, FirstPassFDR re-runs, report streams. Also unaffected.

Only a FULL resume of an already-complete run is affected.

**Positive evidence from the same run:** StellarLibDecoy **mode 1b (diagnostics
vs golden) PASSED with the guard armed and no opt-in** — the diagnostics golden
comparison on a compute run. That is direct proof the accumulator report is both
bounded and byte-identical to the batch report, on the same mechanism the
82-file run exercises at scale.

**Resolution taken:** mode 3 keeps NO opt-in (its old one wrapped the entire HPC
chain and would mask a guard regression on any `--input-scores` worker — exactly
what mode 3 exists to catch). mode 2 keeps a scoped one, commented with the
reason and the boundary. Follow-up drafted at
`ai/.tmp/issue-osprey-mdiag-full-resume.md` — NOT filed, that is the user's
call. The fix is ~40-60 lines reusing `BuildModelDiagnosticsAccumulator` /
`FeedModelDiagnostics` / `WriteFromAccumulator` that this PR already built.

### 82-file Stage-6 re-measure on the post-review-fix build (2026-07-29 02:07)

Run on the pinned Release snapshot `D:\test\osprey-runs\_bin\stage6-pr4488\`,
same phase dir, `-VersionOverride 26.1.1.208`. Baselines preserved under
`stage6-82files/baseline-pre-review-fixes/`.

| | plain baseline | mdiag baseline | **mdiag tonight** |
|---|---|---|---|
| total peak | 32.2 GB | 35.2 GB | **33.9 GB** |
| total floor | 16.3 -> 17.8 GB | 18.5 -> 21.3 GB | **17.1 -> 18.8 GB** |
| total drift | +1.49 GB | +2.87 GB | **+1.71 GB** |
| total per file | +19 MB LEVEL | +36 MB RISING | **+21 MB** |
| managed peak | 22.3 GB | 26.3 GB | **21.9 GB** |
| managed drift | +1.42 GB | +2.06 GB | **+0.09 GB** |
| managed per file | +18 MB | +26 MB | **+1 MB LEVEL** |
| gaps >= 30s | 0 (max 12s) | 0 (max 11s) | **0 (max 11s)** |
| rescored | - | 6,954,057 | **6,954,057 (identical)** |
| actions | - | 6,472,914 | **6,472,914 (identical)** |
| wall | 2:45:12 | 2:47:27 | **2:47:39** |

**The mdiag penalty on drift is gone**: +36 -> +21 MB/file, landing on the plain
run's +19. That was the stated prediction and it held.

**Managed heap is now LEVEL at +1 MB/file** (drift +0.09 GB over 82 files) - the
post-GC "will it fit" measure, and the strongest number here.

**The model-diagnostics report is byte-identical except its embedded
`generatedUtc`.** Verified by `cmp` + `diff`: exactly one differing line, the
`osprey-data` JSON header; `ospreyVersion`, `fileCount`, `featureCount`,
`runFdr` all match. That proves F4 releases the accumulator strictly AFTER the
report is built.

**No perf cost**: 2:47:39 vs 2:47:27.

#### Two honest caveats

1. **The managed result beats even the PLAIN baseline** (+1 vs +18 MB/file). F4
   cannot explain that - the plain baseline had no accumulator to release. NOT
   attributed to a specific fix. A plain 82-file control on the new build was
   started 02:10 (ETA ~05:00) to localize it.
2. **The ~2.2 GB prediction undershot.** Elapsed-matched sampling showed a 3-9 GB
   floor gap. Direction right, magnitude wrong; the surplus is the same
   unattributed effect as (1).

Peak moved only 35.2 -> 33.9 GB, which is correct: peak is set during the
hydrate while the accumulator is necessarily resident. F4 buys floor and drift,
not peak.
