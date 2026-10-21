# DIA import fails or can drop points when a spill file's MaxTime equals a demultiplexed scan time

## Branch Information
- **Branch**: `Skyline/work/20261020_spill_release_race`
- **Base**: `master`
- **Created**: 2026-10-20
- **Status**: In Progress
- **GitHub Issue**: [#4888](https://github.com/ProteoWizard/pwiz/issues/4888)
- **Module**: `skyline`
- **PR**: [#4889](https://github.com/ProteoWizard/pwiz/pull/4889)

## Objective

`ChromGroups.ReleaseChromatogram` releases a chromatogram spill file once extraction has reached
its `MaxTime` (`retentionTime >= MaxTime`). In demultiplexed overlapping-window DIA, two spectra
share each retention time. When a spill file's `MaxTime` equals that time, the reader thread reads
the spill file while the extraction thread is still appending the second spectrum's blocks. This
unsynchronized read/write on one `BufferedStream` gives an `AssumptionException` (short read), an
`ArgumentOutOfRangeException` in `BlockedList.ToArray` (block chain past the snapshot), or silently
missing points. It was found in one HuAD IPL run (PZR17) that failed every time with a 122k-peptide
DIA-NN library.

## Tasks

- [x] Reproduce with SkylineCmd at 796129c9ee (Skyline-daily 26.1.1.279)
- [x] Confirm the mechanism with temporary instrumentation (late writes at rt == MaxTime after the spill was read for release)
- [x] Fix: release only when extraction is strictly past `MaxTime` (`float.MaxValue` still releases everything)
- [x] Verify the fix on the reproducer (2 clean runs, no late writes)
- [x] Regression test for the release condition
- [x] Build and run tests on the branch
- [x] Regression check on real data: PZR16 imported with the fixed vs the official 26.1.1.279 build gives identical Area/RT/Background for all 1,022,317 transitions
- [x] Open the PR (label `skyline`, `Cherry pick to release`)
- [x] `/code-review high` (replaces the retired `/pw-self-review`); all 4 findings addressed in 78694eabb9

## Regression Test

- **Test name**: TestChromGroupsReleaseTime (`pwiz_tools/Skyline/Test/ChromGroupsTest.cs`)
- **Test project**: Test
- **Fails on master**: yes. Branch Debug build with the fix stashed (origin/master f1156f1019): `Assert.AreEqual failed. Expected:<-1>. Actual:<7>`, i.e. release at rt == MaxTime.
- **Passes on fix**: yes, `Skyline/work/20261020_spill_release_race` Debug build, net10.0-windows.

## Progress Log

### 2026-10-20 - Session Start

- Diagnosis was done in a separate worktree, `C:\Dev\pwiz-pzr17`, detached at 796129c9ee; the user's `C:\Dev\pwiz` work branch was left untouched.
- Diagnostic log lines:
  - `ToArray<Single>: block position 76908 outside spill bytes length 76840` (exactly one 68-byte block)
  - `late write: chrom 445071 ... spill MaxTime 48.85519, extraction rt 48.85519, readForRelease True, key ... C[+57.021464]RPLQFQPSK max 48.8551864624023`
- Ruled out: the mzML (a fresh conversion fails identically), network share, concurrency, spill size, temp-name collisions, a recent regression (26.1.1.265 fails the same way), and a single bad peptide (each half of the FASTA imports fine).
- The reproducer is on the MacCoss lab share: `W:\redo-HuAD-Clean\IPL\skyline_bug_PZR17\`.

### 2026-10-20 - Code review round

- `/code-review` on #4889 found 4 items; all were addressed in a new commit:
  - a per-spill-file lock for block writes and the release snapshot+reconstruction;
  - an `AssumptionException` for data added to a released `ChromCollector`;
  - a one-clause release condition;
  - the test now covers spilled data and the guard, and uses a per-test results folder.
- Fail-on-master re-verified with an exact copy of master's `ChromCollector.cs` (`Expected:<-1>. Actual:<7>`). The first attempt was invalid: PowerShell `Set-Content -NoNewline` broke the file, so the build failed and the test ran stale binaries.
- Branch tests pass: TestChromGroupsReleaseTime, TestDemux, TestDemuxAsSmallMolecules, TestMsDataFileImplDemultiplex, TestCollectStatistics, TestNoiseTimeLimit, TestDiaSearchFixedWindows, TestDiaSearchVariableWindows.
