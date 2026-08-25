# Osprey Stage 7: bound the pass-1 scalar seed and keep progress under the stall threshold

## Branch Information
- **Branch**: `Skyline/work/20260825_osprey_stage7_memory`
- **Base**: `master`
- **Created**: 2026-08-25
- **Status**: Active - fixes written, verification in progress
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
- [ ] `regression.ps1 -Dataset All` before merge
- [ ] Consider progress reporting for the compaction and blib-write steps

## Related

- `ai/todos/active/TODO-20260823_osprey_chs_large_scale.md` - the 257-file run these came from
- `ai/docs/memory-band-guide.md` - the fan-out vs join shape method
