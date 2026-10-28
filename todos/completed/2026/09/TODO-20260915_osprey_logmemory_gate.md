# Osprey: OSPREY_LOG_MEMORY=0 enables the forced-GC memory probes instead of disabling them

## Branch Information
- **Branch**: `Skyline/work/20260915_osprey_logmemory_gate` (`C:\proj\pwiz-work2`, off master
  `06ae566254`)
- **Base**: `master`
- **Created**: 2026-09-15
- **Status**: Completed
- **GitHub Issue**: [#4673](https://github.com/ProteoWizard/pwiz/issues/4673)
- **Module**: `osprey`
- **PR**: [#4675](https://github.com/ProteoWizard/pwiz/pull/4675) (merged 2026-09-15 as `7993a4ef55`)

## Objective

The dataset runners write `OSPREY_LOG_MEMORY=0` to mean OFF
(`OspreyDatasetRun.psm1:913`). The probes were gated on
`!string.IsNullOrEmpty(Environment.GetEnvironmentVariable(...))`, and `"0"` is not null or
empty - so every runner-launched run had them ON while its own banner reported
`memprobe : off (default) - --memstamp shape only, no forced GCs`.

Each probe forces a blocking `GC.Collect()` / `WaitForPendingFinalizers()` / `GC.Collect()`.
In the `--model-diagnostics` fold that is one forced gen2 collection **per file** - 446 on the
CHS cohort.

Found while answering a question about a perfviz plot: managed memory was almost flat across
`FirstPassFDR` and a textbook sawtooth across `SecondPassFDR`. The natural reading was that the
first-pass panel allocates nothing per file - which #4662's rewrite does achieve - but
`FirstPassFDR`'s range also held a forced collection at every file boundary and
`SecondPassFDR`'s did not. **The measurement was changing what it measured, in the phase whose
flatness is the claim.**

## Tasks

- [x] Route both gate sites through `OspreyEnvironment.IsSetAndNotZero`
- [x] Unit gate: 595/595, zero inspection warnings
- [x] Verify the fix on a real run (451 -> 0 probe lines on an identical 446-file fold)
- [x] Open the PR

## Regression Test

- **Test name**: `TestEnvFlagZeroCountsAsOff` (CoreTypesTest)
- **Test project**: Osprey.Test
- **Fails on master**: **NO - and this must not be misread as a regression test for this bug.**
  It pins the helper's contract (`"0"` and empty and unset are all OFF, `"1"` is ON) and asserts
  the trap inline, but it could not have caught this defect: the bug was in WHICH helper the
  flag used, not in the helper, which was already correct. It also cannot be compiled against
  master, where `IsSetAndNotZero` was `private` - this branch widens it to `internal` for the
  test.
- **Passes on fix**: yes - 595/595 in the Debug gate.

**Why no true red-to-green test.** `OspreyEnvironment.LogMemory` and
`ProfilerHooks.MemoryLoggingEnabled` are `static readonly`, evaluated once at type load, so no
test can vary the environment underneath them. Making them evaluate per access would make the
wiring testable, but that is a behavioural change beyond this fix and is deliberately NOT done
here - noted as an option rather than taken silently.

**What did verify the wiring**: the identical `--task FirstPassFDR` diagnostics fold, over the
identical 8,028-file staged bed, run before and after the fix -
**451 `[MEM ...]` lines -> 0**.

## Progress Log

### 2026-09-15 - Session start

Fix written and verified during the #4662 validation run, then deliberately held out of that PR
so #4662 stayed exactly what TeamCity #252 had validated. Patch banked at
`ai/.tmp/sessions/20260915-night/logmemory-gate-4673.patch` and re-applied cleanly onto this
branch off the post-merge master.

**Measured side effect of the defect** (single pair, not yet repeated): the same fold took
3,938.0 s with the 446 forced collections and 3,465.8 s without - 472.2 s, about 1.06 s per
collection. **Do not cite the 12% as established.** The control I intended (test 4's pass-2
fold, which had ~3 probes rather than 446, and so should have shown no saving) turned out not to
be a control at all: it ran in a fresh process with the pass-1 JSON already on disk, where the
comparison run folded pass 2 immediately after pass 1 in the same process. Firm the number up
with the panel-only harness (`OSPREY_MDIAG_COASSIGN_ONLY=1`, 9 min at 446 files) run twice per
arm.

Also worth recording: every wall time previously taken through a dataset runner includes these
collections, and reported peaks are LOWER than an uninstrumented run would show. Run-to-run
comparisons stay valid because both sides had them; comparisons to anything not launched through
a runner do not.

### 2026-09-15 - Merged

PR #4675 merged as commit `7993a4ef55`. Gate was 17/17 SUCCESS and Copilot's auto-review
recommended approval with 0 comments across all 4 files.

**What shipped.** `OspreyEnvironment.LogMemory = IsSetAndNotZero(@"OSPREY_LOG_MEMORY")`, with
`ProfilerHooks.MemoryLoggingEnabled` and the `PerFileScoringTask` library-resident probe both
routed through it, plus `TestEnvFlagZeroCountsAsOff`. `IsSetAndNotZero` widened from `private`
to `internal` so the test can reach it.

**What was deliberately NOT done.** `LogMemory` and `MemoryLoggingEnabled` remain
`static readonly`, so the WIRING is still not unit-testable - a test cannot vary the environment
under a flag evaluated once at type load. Converting them to per-access properties would fix
that and was considered and rejected as a behavioural change beyond the fix. Recorded here
rather than left implicit, because the next person to look will see a test that does not cover
the thing that broke.

**Not gated on TeamCity.** Perf/Regression was not run on `pull/4675`; the 17 green checks are
the automatic ones. The argument for skipping it is that this change cannot move output - it
gates diagnostic probes, and the probes only observe - and the 446-file 451 -> 0 verification
covers the behaviour. Brendan approved the merge on that basis. Noted so the gap is visible if
anything downstream ever looks surprising.

**Follow-up worth doing, not urgent.** The wall-time figure (3,938.0 s -> 3,465.8 s, ~1.06 s per
forced collection) is a single pair whose intended control did not hold. Re-measure with the
panel-only harness (`OSPREY_MDIAG_COASSIGN_ONLY=1`, 9 min at 446 files) twice per arm before
anyone quotes a percentage.
