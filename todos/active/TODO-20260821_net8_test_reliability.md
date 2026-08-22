# net8 test reliability: make the net8 suite pass reliably in parallel containers

## Branch Information
- **Checkout**: `C:\proj\pwiz-work1` (the team's Integration checkout)
- **Branch**: `Skyline/work/20260821_net8_test_reliability` - rebased 2026-08-22 onto
  `Skyline/work/20260818_commonutil_winforms_split` @ `2cb66ee39d` (PR #4587, all green).
  10 commits, not pushed, no PR yet.
- **Created**: 2026-08-21
- **Status**: rebased and building; working through /code-review max findings
- **Module**: `skyline`
- **Backup of the pre-rebase branch**: `backup/20260821_net8_test_reliability-prerebase`
  @ `e1f207b1a9`, local only

## Why

The net8 port left the test suite unable to run reliably in parallel containers. Several
distinct causes were mixed together in the failure logs, and the failures carried no
information that distinguished them: a container-only layout bug, a net472-specific float
rendering, a framework hook misreported as a Skyline GC leak, and a genuine library load
race. Until each one had a diagnostic that named it, occurrences were discarded as flakes.

## What was done

| SHA | What |
|---|---|
| `01bfe422c8` | net472 removal, font pin, STA marshalling. The app-local CRT staging this carried was dropped on rebase - the base now stages the full 50-file set via `VendorNativeCrt.targets` |
| `9efb019cf5` | ImmediateWindowWarnings expected a net472 float rendering (zh/ja) |
| `4a28f8a923` | GC root chain reporting; ClrMD 0.8.31 -> 3.1.512801 |
| `3c9a1cbffb` | WinForms SystemEvents hook no longer classified as a Skyline GC leak |
| `f1e9e22a94` | library load race fixed; `IExplainDiff` / `EqualityExplainer` |
| `c0dd61d680` | comment correction (content equality named as the reason for FileIndex) |
| `887bcf8d77` | removed the ChromInfo.Equals reference-equality TODO |
| `2a587cb490` | test-run logs ignored in their net8 locations (review finding) |
| `1e544473ae` | staging no longer keeps an old copy of a shared dependency (review finding) |
| `19e5fc8e3b` | net472 dropped from the seven tool projects (review finding) |

### Dropped on rebase, superseded upstream

Matt landed equivalents on `20260612_net8_port` on 2026-08-20, so two commits were dropped
rather than merged:

* `b763d46701` dockPanel anchor fix -> his `2b9c5d2353` sets `dockPanel.Dock = Fill` in the
  designer. Keeping ours would have **undone** his: the WinForms `Anchor` setter sets
  `Dock = DockStyle.None`, and our hunk re-asserted `Anchor` after `InitializeComponent`.
* `6a18a676df`, which only edited that commit's comment.
* Our `ComparePeakPickingDlg` null-guard, character-equivalent to his `6d88331e78`.
* Our `Enumerable.Reverse(...)` fix in `CommandLineTest.cs`, in favour of the base's
  `AsEnumerable()` form of the same fix.

## Verification

- Full 1116-test parallel suite green repeatedly. Overnight: 13 full runs, 11 fully green.
- Developer's 5-language run: 5,585 executions, 0 failures, 44 min - versus ~46 min for a
  single language serial. About 6x the coverage in the same wall clock.
- `RefineConvertToSmallMoleculesTest` library race: 22 failures in 351 runs -> 0 in 501.
- GC-LEAK classification proven by forced reproduction. Full truth table: framework hook
  only -> warning and pass; genuine leak -> fail; both -> fail.

## Pre-existing flakes, measured with a control

Three runs with these changes stashed out versus three with them in: **2 failures in 3
control runs, 1 in 3 with the changes.** The suite fails more often without this work, so
the remaining flakes below are not caused by it.

| Flake | Rate | Notes |
|---|---|---|
| `TestImportFullScanNarrowScanWindows` | ~2 in 11 runs | `hdf5` load, `0x8007007E`. First blamed on container teardown here; the control reproduced it without these changes, so that attribution was wrong. |
| `TestAuditLogTutorial` | 1 seen | audit-log entry ordering in `VerifyAuditLogCorrect` |
| Refine family | ~1.8% | see open thread below |
| `"Loader cancelled"` | 1 seen, no recurrence in 6 runs | `WatersImsMse...AsSmallMolecules` |

## Open thread: chrom-info differences in RefineConvertToSmallMoleculesTest

After the library fix the residual is ~1.76%, all through
`ConvertedSmallMoleculeTransitionGroupResultIsSimilar`. The new diagnostic names it:

```
[0][0] LibraryDotProduct 0.72051907 vs (null); OriginalPeak <ScoredPeakBounds> vs <ScoredPeakBounds>
```

`LibraryDotProduct` is present on one side and null on the other, intermittently. It looks
like a score-computation race that survives `WaitForProcessing`. `ScoredPeakBounds` has no
`ToString`, so saying more needs `IExplainDiff` on that class - a one-class job now, not an
investigation.

Reproduce with `ai/.tmp/run-refine-soak.ps1`: one test, 5 languages, 5 containers, `loop=0`.
About 500 executions in a few minutes. That is how the library race went from
"unreproducible in six full runs" to root-caused in roughly ten minutes.

## Method worth repeating

Soaking ONE test across 5 languages in parallel containers turns a 1-in-N flake into a
period-to-failure measurement. Two rules made it pay:

1. **Measure the rate before theorising.** Denominators must be *executions*, not runs. The
   Refine flake looked like "1 in 6 runs" (rare) but was ~6% of executions (very tractable).
2. **When a failure message carries no information, fix the message first.** Both root
   causes fell out of the *first* occurrence after the diagnostic existed.

## Gotchas hit repeatedly

- **CRLF.** `sed -i` rewrites a whole file as LF. Bit three times, including a new file that
  `fix-crlf.ps1` skipped because it was still untracked. Verify by byte count: `wc -c` minus
  `tr -d '\r' | wc -c` must equal the line count.
- **Staging keeps stale files.** `robocopy /XO` means "exclude older", so a NuGet DLL with an
  old package timestamp loses to whatever is already staged. This silently kept ClrMD 0.8.31
  in place for a while. The new warning covers stale *projects*, not stale *dependencies*.
- **`Deny-DirectBuildTest` false-positives** on blocked exe names inside heredocs and grep
  patterns.

## Remaining tasks

`/code-review max` ran 2026-08-21 over the pre-rebase branch: 51 files, ~60 candidates cut
to 15 after verification. Three are fixed (the last three commits above). Remaining, in the
order they are worth taking:

- [ ] WiX `Product-template.wxs` still installs `BullseyeSharp.exe`, which nothing builds
- [ ] `Process.Start(url)` left in shipping Skyline code - net8 defaults
      `UseShellExecute` to false, so every Help menu link throws `Win32Exception`
- [ ] GC tracker cluster: heap walk inflates working set ~6x and does not release it;
      unlocked read of the `SystemEvents` handler table; `TargetException` on a
      non-Control survivor; leak dump written after the roots it should capture are gone
- [ ] `RunOnStaThread` creates a thread per functional test but `Application.ThreadException`
      is subscribed once, so the 2nd+ test in a process loses UI-thread exception routing
- [ ] `EqualityExplainer` swallows exceptions into "found no difference"; `ExplainDiff`
      disagrees with `Equals` on a NaN `PeakCountRatio`
- [ ] `AssertEx` `WaitForProcessing` timeout swallowed by a bare `catch`
- [ ] SkylineTester staging discovery prefers Release over a fresher Debug
- [ ] `IExplainDiff` on `ScoredPeakBounds`, then chase the `LibraryDotProduct` null race
- [ ] Open the PR against `Skyline/work/20260818_commonutil_winforms_split`, label `skyline`

## Progress Log

### 2026-08-21
Nine commits landed and verified (table above). `/code-review max` deliberately deferred
from the prior session, which was at 24% context; run at the start of this session with a
full window. This TODO replaces `ai/.tmp/handoff-20260821_net8_test_reliability.md`, which
was the only record of the work and is not durable.

### 2026-08-22
Rebased onto the updated base after PR #4587 went green. Dropped two superseded commits (see
above) and the app-local CRT block. Build verified: Skyline solution and all six test projects
compile with zero errors on SDK 10.0.400 / C# 14, which is new - the branch had only ever been
compiled at C# 12 through the CLI, because the repo-root `global.json` capped it there until
that pin was moved back under `pwiz-sharp/` on the base.

Three review findings fixed and verified: the `.gitignore` anchoring (all seven test logs now
ignored, tree fully clean), the staging one (`/XO` was real but insufficient - `TestPerf` and
`TestTutorial` stage last from output `build.bat` never rebuilds and put ClrMD 0.8.31 straight
back; stale projects now stage first, proven by the staged assembly going 603,904 -> 682,024
bytes), and the `NU1201` break (reproduced first, then fixed by dropping net472 from the seven
projects; both tool solutions build clean afterwards).

Not runnable here: the AutoQC and SkylineBatch suites. AutoQC Loader blocks on a modal asking
for an administrative or web-based Skyline installation, which a source-build machine has not
got. CI runs them with `/TestCaseFilter:"TestCategory!=Connected"`.

