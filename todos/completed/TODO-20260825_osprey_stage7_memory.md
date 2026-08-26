# Osprey Stage 7: bound the pass-1 scalar seed and keep progress under the stall threshold

## Branch Information
- **Branch**: `Skyline/work/20260825_osprey_stage7_memory`
- **Base**: `master`
- **Created**: 2026-08-25
- **Status**: Completed
- **PR**: [#4615](https://github.com/ProteoWizard/pwiz/pull/4615) (merged 2026-08-26)
- **Module**: `osprey`
- **Machine**: BRENDANX-UW8, 63.7 GB RAM

## Objective

Two defects found by reading the memory and reporting profile of the first 257-file CHS run
(`chs-257files-libdecoy-r1.0-protein-compact-p0059_0060_0061`, 2026-08-24, exit=0 in 615 min).
Both are invisible at 86 files and only appear at cohort scale.

## Defect 1: `RestorePass1Scalars` is the global memory peak

`Osprey.Tasks/Pass2FdrSidecar.cs`, called from Stage 7 before the pass-2 mode dispatch.

Measured on the 257-file run - the phase announces itself as
`Seeding pass-1 scalars from 257 file(s)...`:

| point | managed |
|---|---|
| 22% | 40.4 GB (a gen2 collection had just run) |
| 50% | 49.8 GB |
| 76% | 57.9 GB |
| 96% | 64.1 GB |
| phase end | **65.2 GB - the global peak of the whole run** |
| after | 38.9 GB (all released) |

**+23.7 GB with no GC relief across 74% of the files, ~125 MB/file**, matching perfviz's
independent `+138 MB/file RISING`. Released once the phase ends, so it is a transient O(files)
structure rather than a leak - but it is what makes the run's peak 69 GB instead of ~45 GB.

**Cause**: the loop allocated a fresh `Dictionary<uint, FdrEntry>` index and a fresh
`List<KeyValuePair<FdrEntry, FdrScoreRecord>>` staging buffer per file. At cohort scale both
back onto arrays far past the 85 KB Large Object Heap threshold, and the LOH is swept only on
a gen2 collection, so the dead buffers stood until pressure forced one.

**Fix**: hoist both out of the loop and `Clear()` per file. `Clear()` retains capacity, so the
steady state is one file's worth instead of the cohort's. The staging contract is preserved -
it only requires that nothing staged before a fault is APPLIED, which clearing ahead of each
file still gives.

**Why it matters beyond this run**: at 0.130 GB/file this phase alone wants ~65 GB at 500
files, on top of the rest. It is the single largest obstacle to the 500-file target.

## Defect 2: the heartbeat sits exactly on the stall threshold

`Osprey.Core/ProgressReporter.cs`. `HEARTBEAT_SECONDS` was 30.0; `ai/scripts/perfviz.py` flags
reporting gaps `>= 30s` as a stall. The two coincided, so any phase slow enough to be
heartbeat-driven rather than percent-driven parked on the diagnostic line.

Measured in Stage 7's streaming competition:

| files | max gap | gaps >= 30s | mean |
|---|---|---|---|
| 86 | 17 s | **0** | 4.1 s |
| 257 | 49 s | **34** | 11.9 s |

**This is a regime change, not a slope.** At 86 files a whole percent advanced every ~7 s and
the idle window was never reached. At 257 files a percent takes ~30 s, so the heartbeat
becomes the binding constraint and gaps cap at 30 s + one file's work. The distribution proves
it - gaps pile up at 25-35 s and fall off a cliff above 36 s. **Do not extrapolate these gaps
linearly**; they do not reach ~95 s at 500 files, they stay ~30-50 s.

**Fix**: `HEARTBEAT_SECONDS` 30.0 -> 15.0, held clear of the diagnostic threshold rather than
equal to it. Silence is how a hung run and an OOM-killed run both look, so the heartbeat has
to stay below the line that says "this went quiet".

## Verification

**The cheap loop**: `-Task SecondPassFDR -LinkFrom <the 257-file run>` links all 2827 per-file
artifacts (11 suffixes x 257 files) and re-measures Stage 7 alone in ~1.5 h instead of the
10.25 h a full leg takes. This is what makes the fix testable at all.

```powershell
pwsh -File ai\scripts\Osprey\CHS\Run-Chs.ps1 -IncludePattern 'us(0059|0060|0061)' `
  -Tag '-p0059_0060_0061-s7base' -Task SecondPassFDR `
  -LinkFrom 'D:\test\osprey-runs\chs-seer\runs\chs-257files-libdecoy-r1.0-protein-compact-p0059_0060_0061' `
  -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -Threads 30 -FdrBenchPass 2 `
  -LibraryDir 'D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817' `
  -Exe <snapshot>\Osprey.exe
```

## Defect 3 is issue #4486, already open - NOT a new finding

**Corrected**: this was first written up here as a discovery. It is not. It is
[#4486](https://github.com/ProteoWizard/pwiz/issues/4486), "Stage-7 SecondPassFDR ~45 GB
peak", split out of TODO-20260727_osprey_stage6_rescore_streaming, referenced from
`Program.cs`, `ResidentPaths.cs`, `StreamingFdr.cs` and `FirstPassFdrTask.cs`, and printed by
`regression.ps1` on every run under "Known O(files) resident paths this gate still traverses"
with its own 500-file projection (~103 GB at 0.197 GB/file). The measurements below are a
re-measurement of a tracked issue at a new scale and on a new cohort, which is worth having -
but check for an open issue before calling something new.

### What the re-measurement adds

`Osprey.Tasks/PerFileScoringTask.cs:1447` -
`perFileEntries.Add(new KeyValuePair<string, List<FdrEntry>>(fileName, stubs))` accumulates
EVERY file's full pre-compaction stub list before Stage 7 runs.

Measured attempting the 257-file `-Task SecondPassFDR` reproduction:

| | |
|---|---|
| stubs per file | ~2.85 M |
| managed at file 63 / 81 of 257 | 19.4 GB / 25.2 GB |
| slope | **311 MB/file, linear** |
| projected at 257 files | **~80 GB - past the 63.7 GB box** |

The in-process leg entered SecondPassFDR at 19.6 GB holding ~533 K SURVIVORS per file; the
reload pulls 5.3x that because it rebuilds the PRE-compaction pool. The comment above the call
already names this "the dominant term in the O(files) rehydrate peak" - features were stripped
out (~800 MB/file), but the stubs themselves were left.

This is exactly the shape `ai/MEMORY.md` warns against (per-file compute -> O(entries)
aggregate -> per-file emit, with emission a second streamed pass). It matters most for the
distributed/HPC route, which is the whole reason `--task` exists.

**Not fixed here** - it is a restructuring job, not a buffer fix, and it was not in the
requested scope. It does mean the 257-file hard-link harness cannot reproduce the in-process
Stage 7 peak, so the A/B below runs on a 100-file subset that fits inside the reload's limits.

### Results

**100-file A/B** - same linked artifacts, two pinned binaries, serial, both `exit=0`, entering
the seeding phase within 0.2 GB of each other:

| | unfixed | fixed |
|---|---|---|
| seeding accumulation | **131 MB/file** | **1 MB/file** |
| seeding climb | +12.77 GB | +0.08 GB |
| working-set peak | 52.7 GB | **45.7 GB** |

**257 files, fixed build**: `exit=0` in 70 min, seeding climb **+0.08 GB total (0 MB/file)**,
peak 53.6 GB managed / 55.5 GB ws. The unfixed build could not finish this run at all - its
reload pool plus 257 x 131 MB of seeding went past the box.

**Reporting gaps at 257 files** (leg 4 unfixed vs fixed):

| | unfixed | fixed |
|---|---|---|
| gaps >= 30 s | **34** | **2** |
| mean gap | 11.9 s | **4.4 s** |
| samples | 461 | **948** |

The two survivors are single bulk steps that never call `Report`, so no heartbeat value can
cover them - the `--task SecondPassFDR` compaction (40 s) and the blib write (42 s). Giving
those two their own reporting is a separate small change, not heartbeat tuning.

- [x] Baseline reproduction reproduces the defect (131 MB/file at 100 files, matching the
      257-file run's ~125 and perfviz's independent +138)
- [x] Fixed build shows a bounded seeding phase
- [x] perfviz plots: `ai/.tmp/s7-100-unfixed.png`, `s7-100-fixed.png`, `s7-257-fixed.png`
- [x] `regression.ps1 -Dataset Stellar` **PASSED** - all 10 modes, including mode1 vs golden,
      so both fixes are byte-identical in output
- [x] `regression.ps1 -Dataset All` - TeamCity Perf/Regression build #218 SUCCESS on the
      PR merge ref
- [x] Progress reporting for the compaction and blib-prep steps

## Deferred, carried forward

Four `/code-review max` findings verified but deliberately left out, each needing its own
verification rather than being folded into a branch scoped to the visible perfviz defects:

1. **`BuildBestExpPrecursorQ` / `BuildSharedBoundaries` re-walk the whole pool** to re-derive
   what `CollectPassingEntries` already materialized 22 lines earlier. Result-identical per the
   reviewer's tie-break analysis, but `BuildSharedBoundaries` is `internal` and bound by
   `MultiChargeConsensusTest.cs:118`, so the signature change needs its own test pass. Removes
   two of six full passes over the 137 M-row pool.
2. **`BuildCrossFileObservations` has no `passingPrecursors` gate** - it filters on `IsDecoy`
   alone, while its only consumer looks the map up exclusively with passing keys. Every
   non-passing precursor's list is built and never read.
3. **Three more whole-pool walks at the head of the blib phase** (`ComputePassingPeptides`,
   `ComputePassingPrecursors`, `CollectPassingEntries`) still run silent, ~70 s at 257 files.
4. **`FdrScoresSidecar` has a bare `catch { return false; }`** around the record read, so an
   OutOfMemoryException in the callback is reported as a missing sidecar. Under
   transfer-compete or protein-compact those entries reach the picked-protein FDR at
   `Score == 0.0`, and the decoy side is deliberately not q-gated, so zeros compete in the
   null - and `LogWarning` sets no exit code, so the run returns 0 with corrupted protein
   numbers. **Worth its own issue**; the cheap durable fix is
   `catch (Exception ex) when (!(ex is OutOfMemoryException))`.

Also carried: three Copilot threads on PR #4615 left **unresolved** by choice. Copilot asked
for `++idx` over the 0-based `Report(idx++)`; its premise is right (`_lastPercent` starts at
-1, so `Report(0)` can emit "0%") but `++idx` prints 100% before the last file's work runs.
0/33/67/100 is the honest sequence. Left open for a human rather than resolved.

## Related

- `ai/todos/active/TODO-20260823_osprey_chs_large_scale.md` - the 257-file run these came from
- `ai/docs/memory-band-guide.md` - the fan-out vs join shape method

## Progress log

### 2026-08-26 - Merged

PR #4615 merged as commit `2a0b006`. Shipped both fixes the branch was scoped to: the
`RestorePass1Scalars` buffer reuse (131 MB/file -> 1 MB/file at 100 files, working-set peak
52.7 -> 45.7 GB) and the reporting-gap work (`HEARTBEAT_SECONDS` 30 -> 15 plus five newly
instrumented whole-pool spans, gaps >= 30 s going 34 -> 2 at 257 files). A 257-file
`--task SecondPassFDR` leg now completes in 70 min where it previously could not finish.
`regression.ps1 -Dataset Stellar` green locally and TeamCity Perf/Regression #218 green on
the merge ref, both including mode1 vs golden, so every change is byte-identical in output.

Deliberately NOT closing #4486: the post-GC characterization it had been blocked on since July
is now posted there (Stage 7's peak is a LIVE pool - 4.19 GB library + ~147 MB/file, flat
across the stage - not Server-GC gray), which reduces that issue to one sentence: the survivor
pool is resident, stream it. Removing it means restructuring what pass-2 scoring and protein
FDR consume, not tuning allocations, so it stays open for its own branch.

Four review findings deferred (see above), one of which - the bare `catch` masking an OOM as a
missing sidecar - deserves its own issue.
