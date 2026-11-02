# Trim the fixed waits around tutorial screenshots

## Branch Information
- **Branch**: `Skyline/work/20261030_screenshot_wait_times`
- **Checkout**: `C:\proj\pwiz-work3` (NOT `C:\proj\pwiz`, which holds PR #4947)
- **Base**: `master`
- **Created**: 2026-10-30
- **Status**: In Progress - levers in place, ready for the night session
- **GitHub Issue**: none (planned as a night session by Brendan)
- **Module**: `skyline`
- **PR**: [#4951](https://github.com/ProteoWizard/pwiz/pull/4951)

## Objective

Every auto screenshot waits a fixed 2.5 s besides `WaitForGraphs()`:

| Wait | Where | Default | History |
|------|-------|---------|---------|
| Settle | `TestFunctional.CaptureScreenShot` | 1,500 ms | #3779 |
| Activate | `ScreenshotManager.ActivateScreenshotForm`, after `form.Activate()` | 500 ms | #3283 |
| Repaint | `ScreenshotManager.ActivateScreenshotForm`, after `AdjustControlsForConsistentScreenshots` | 500 ms | #4896 |

About 2,000 screenshots per full pass makes this ~80 min of a ~3.5 h full screenshot run. Client-area
animation is now off during screenshot runs (`ScreenshotManager.DisableControlAnimations`, #4915), so
the UI should settle much faster than when these waits were chosen.

**Goal: cut at least 30 min from a full run** by shortening the waits, or replacing fixed sleeps with
"UI idle and painted" plus a short delay, without changing any screenshot.

Origin: "Candidate night session: trim screenshot settle waits" in
ai/todos/completed/2026/10/TODO-20261020_net10_tutorial_screenshots.md.

## Levers (in place, commit b7182ec46b)

Environment variables read at every screenshot (`pwiz_tools/Skyline/TestUtil/ScreenshotWaits.cs`);
with none set, behavior is unchanged:

* `SKYLINE_SCREENSHOT_SETTLE_MS` (default 1500)
* `SKYLINE_SCREENSHOT_ACTIVATE_MS` (default 500)
* `SKYLINE_SCREENSHOT_REPAINT_MS` (default 500)
* `SKYLINE_SCREENSHOT_TIMING_LOG=<path.tsv>` - appends one row per screenshot: Test, Language,
  Screenshot, GraphsMs (WaitForGraphs), SettleMs, ActivateMs, RepaintMs (adjust + wait), CaptureMs
  (TakeShot), and the three settings in effect.

Pass several in ONE argument, comma-separated (pwsh -File passes a list as one string;
`Run-Tests.ps1` now splits on commas followed by NAME=):

```bash
pwsh -File 'C:/proj/ai/scripts/Skyline/Run-Tests.ps1' -SourceRoot C:/proj/pwiz-work3 \
  -TestName TestCEOptimizationTutorial -TakeScreenshots \
  -EnvironmentVariables 'SKYLINE_SCREENSHOT_SETTLE_MS=0,SKYLINE_SCREENSHOT_ACTIVATE_MS=0,SKYLINE_SCREENSHOT_REPAINT_MS=0,SKYLINE_SCREENSHOT_TIMING_LOG=D:\test\skyline-runs\20261030_screenshot_waits\smoke-0ms.tsv' \
  -Summary
```

Smoke test (2026-10-30, all waits 0): TestCEOptimizationTutorial passed in 12 s; 7 rows logged.
Real work per screenshot: GraphsMs 0-220, RepaintMs (adjust) 0-31, CaptureMs 20-41.
1 of 7 PNGs changed (OptimizeCE/en/s-07.png) - reverted; whether that is a too-short wait or session
noise is exactly what the method below must separate.

## Method

**Compare against a baseline captured under the same conditions, NOT against git.** Screenshots
auto-captured from a Claude Code session differ from Brendan's accepted set anyway: windows render
"inactive" (titlebar text slightly gray), so every window can differ by a few pixels (Brendan,
2026-10-30). A diff against the committed PNGs mixes that noise with wait effects.

1. **Baseline at default waits** for the chosen test set, with the timing log on. Copy the resulting
   PNGs out of the tree (e.g. `D:\test\skyline-runs\20261030_screenshot_waits\baseline\`), then
   `git checkout -- pwiz_tools/Skyline/Documentation/Tutorials` to restore the accepted set.
   Consider a second default-wait run on a subset to measure run-to-run noise.
2. **Reduced waits** (start with 0/0/0, then e.g. 100/100/100, 250/250/250, and per-wait sweeps),
   timing log on. Compare each PNG to the baseline copy (byte-identical, else pixel diff), not to git.
3. **Classify** each changed screenshot: which wait it needs and why (a control mid-fade, a graph not
   repainted, an activation not processed). Record in this TODO.
4. **Decide**: lower defaults, or a targeted wait (e.g. Application idle / `Control.Update` plus a short
   delay) only where needed. Prefer a condition over a bigger sleep.
5. **Confirm** the chosen setting on the full TestTutorial set in en (and the TestPerf tutorials if time
   allows) with zero changes vs baseline, and report the time saved from the timing logs.

Scope suggestion for ~8 h: TestTutorial in English first (~1.5 h at default waits, much less at 0).
TestPerf tutorials (~2 h at defaults, large downloads) only for the final confirmation.

## Constraints and gotchas

* **The desktop must stay connected.** Over RDP, a screenshot run waits indefinitely for a screen
  device if the session is disconnected (Brendan). Screenshot runs need the RDP client connected,
  not minimized.
* Only one screen-driving run at a time on this machine (no overnight SkylineTester run in parallel).
* Build and test scripts need `-SourceRoot C:/proj/pwiz-work3` on EVERY call; vendor readers via
  `Build-Skyline.ps1 -VendorLicenses` (already built that way).
* The Debug Solution build skips TestTutorial and TestPerf: build them with `-Target TestTutorial` /
  `-Target TestPerf`, or TestRunner reports "No tests found" and the run counts as passing.
* Never commit PNGs from these runs; restore the tree with `git checkout --` after each run.
* `TestRunner` blocks builds while alive; finish or stop a run before rebuilding.
* Long runs: Bash `run_in_background` (ai/docs/long-running-jobs-guide.md); test output to
  `D:\test\skyline-runs\20261030_screenshot_waits\`, never to ai/.tmp.

## Tasks

- [x] Branch from master in pwiz-work3
- [x] Overridable waits + per-screenshot timing log (b7182ec46b)
- [x] Run-Tests.ps1: several -EnvironmentVariables pairs in one argument
- [x] Smoke test at 0/0/0 on TestCEOptimizationTutorial
- [x] Baseline run(s) at default waits (night session)
- [x] Reduced-wait runs and PNG classification (night session)
- [x] Choose new defaults or conditional waits; implement
- [x] Confirmation run; report minutes saved
- [ ] Screen run of the code-review commit (n3/fP4)
- [ ] PeakBoundaryImputation s-19 (volcano update after IsComplete)
- [ ] PR

## Regression Test

- **Test name**: none - this changes test infrastructure timing; the verifier is "zero PNG changes vs
  a same-conditions baseline" on the full TestTutorial set, recorded here with the run logs.

## Progress Log

### 2026-10-30 - Session Start

Branch created from master c03ad0b5f7 in pwiz-work3. Levers committed (b7182ec46b), smoke-tested.
Handing off to a night session.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20261030_screenshot_wait_times.md` before starting work.

### 2026-10-30/31 - Night session

Runs: `D:\test\skyline-runs\20261030_screenshot_waits\<arm>\` (arm.log, TestTutorial.log, timing.tsv,
shots\<Test>\<lang>\s-NN.png). Driver and comparers (session-local):
`ai/.tmp/sessions/20261030-night/` (run-arm.ps1, compare.py, compare_shots.py).

**Method fix**: several tests write the same tutorial folder (TargetedMSMS x3 -> PRM, CE x2 ->
OptimizeCE, GroupedStudiesDraft -> Tutorials\en), so comparing the tree after a run only sees the last
writer. Added `SKYLINE_SCREENSHOT_COPY_DIR` (copy every saved PNG per test) and compared per test.
TestTutorial en = 26 tests, 717 screenshots.

| Arm | Settings | Run | Waits+flush | vs bA |
|-----|----------|-----|-------------|-------|
| baseline | defaults | 44.8 min | 30.4 min | (last-writer PNGs only) |
| bA | defaults | 44.4 min | 30.8 min | - (vs baseline: 1 PNG, GroupedStudies s-03) |
| w0 | 0/0/0, no flush | 14.3 min | 0.5 min | 143 of 205 last-writer PNGs differ, 2 tests crash |
| f0 | 0/0/0 + paint flush | 15.3 min | 1.4 min | 712/717 |
| f500 | 500/0/0 + paint flush | 21.3 min | 7.4 min | 715/717 |
| f0b | 0/0/0 + flush (also after activation) + import-graph condition | 15.7 min | 1.7 min | 714/717 |

**Findings**
1. At 0 ms most differences are windows not yet painted (blank grids/graphs, half-drawn tab strips).
   Replaced by a condition: `ScreenshotManager.WaitForPaint` - Invoke on the UI thread (drains work
   posted before it), `RedrawWindow(RDW_UPDATENOW | RDW_ALLCHILDREN)` on every top-level window of that
   thread, then `DwmFlush()`. Done before activation, after activation (before the adjusters), and
   before capture. ~0.1 s per screenshot.
2. Real race exposed at 0 ms: `ZedGraphShot.Take()` called `MasterPane.GetMetafile()` on the test
   thread while the UI thread painted the same panes -> "Object is currently in use elsewhere" (GDI+,
   ExistingExperiments) and "Collection was modified" (MSGraphPane labels, Ms1). Fixed: draw the
   metafile on the UI thread via Invoke. The 2.5 s waits were hiding it.
3. Import-progress shots (AllChromatogramsGraph): incremental renders are >= 1 s apart
   (MIN_INCREMENTAL_RENDER), so at 0 ms the graph was empty. Added
   `AsyncChromatogramsGraph2.IsRenderComplete` (no axis animation, no render pending/running, and
   either nothing unrendered or a render since freeze) to `AllChromatogramsGraph.IsReadyForScreenshot`.
   Residual: GroupedStudies1 s-03 peak detail still varies (data still arriving for the shown file);
   it varied between the two default-wait baselines too - inherent.
4. GroupedStudiesDraft s-04: checkbox corners blended twice (127 -> 88) whenever the pre-activation
   flush runs, even with default sleeps. Only in the draft test, which takes an untyped
   PauseForScreenShot() of the Skyline window behind a modal Peptide Settings dialog; its PNGs are not
   committed. Real tutorial Peptide Settings shots with checked lists match.
5. Ms1 s-09: 9 px at 438,314 - the same pixels differed between the default baseline and git.
6. Pre-existing: TestMSstatsTutorialLegacy and TestQuasarTutorialLegacy failed every screenshot run
   with leftover temp CSVs. Root cause: in screenshot mode the test runs the tool, which exports its
   input report to temp, then cancels the args collector - so the tool never runs and nothing
   deletes the file. Fixed in `ToolDescriptionRunUI.RunTool`: delete the report when the args
   collector is canceled. Both pass in screenshot mode now (arm `legacy`).
7. Intermittent at 0 ms even with the flush (f0b vs f0c): SmallMolQuant s-09, the file list caught
   mid-paint. Added a stable capture: `ActiveWindowShot.Take` captures again (after another
   WaitForPaint) until two captures match, max 10; retries go to the timing log (CaptureRetries).
8. Final code, no env vars (arm n1): TestTutorial en 16.3 min (was 44.4), 715/717 vs bA; the 2 are
   GroupedStudies1 s-03 (live import) and the draft s-04.

**TestPerf tutorials** (11 tests, 308 screenshots; `ai/.tmp/sessions/20261030-night/perf-tutorials.txt`):

| Arm | Settings | Run | Waits+capture | vs bP |
|-----|----------|-----|---------------|-------|
| bP | old waits forced (1500/500/500, flush 0) | 53.5 min | 13.0 min | - |
| fP | new defaults | 36.9 min | 1.1 min | 302/308, 1 capture retry |

fP differences: DDA s-12 and DiaUmpire s-13 are live search logs (text depends on search progress);
OrbiPrm s-41 1 px; PeakBoundaryImputation s-16/s-18 status bar "Label layout" instead of "Ready" and
s-19 a volcano label placed differently - the label layout (`LabelLayoutRunner`: 100 ms debounce
timer + worker thread) was still running. WaitForGraphs did not know about it; added
`LabelLayoutRunner.AnyPending` to `SkylineWindow.IsGraphUpdatePending`.

| bP2 | old waits again | 47.9 min | 13.0 min | vs bP: DDA s-12, DiaUmpire s-13, OrbiPrm s-41 differ (noise) |
| fP2 | new defaults + label layout wait | 37.8 min | 1.0 min | vs bP2: 306/308 (DiaUmpire s-13 noise, PBI s-19) |

Label-layout tests all pass with the new IsGraphUpdatePending (TestGroupComparisonVolcanoPlot,
TestLabelLayoutDeterminism, TestPeakArea*Graph, TestVolcanoPlot*).

**Scored against git** (Brendan's metric: target = shots the old code reproduces exactly from the
committed PNGs; `ai/.tmp/sessions/20261030-night/vs_git.py old1,old2 new1,new2`):
* TestTutorial: old (bA) reproduces 573 of 663; n1 and n2 572/573 - the miss is GroupedStudies1
  s-03, which the old code matched in only 1 of 2 runs, so 572/572 on shots the old code holds.
* TestPerf tutorials: old (bP and bP2) both reproduce 295 of 308; fP 292/295 (PBI s-16/18/19),
  fP2 294/295 (PBI s-19).

**Open: PeakBoundaryImputation s-19** ("Volcano plot after imputation", ZedGraph metafile). The
volcano gets one more `QueueUpdateGraph` -> `UpdateGraph` -> label layout ~0.8 s after the test's
`WaitForConditionUI(foldChangeVolcanoPlot.IsComplete)`; with any >= ~0.5 s sleep the shot matches
both old-wait baselines, with 150 ms it does not. Traced with temporary logging in LabelLayoutRunner
(reverted; logs `D:\test\skyline-runs\20261030_screenshot_waits\label-{new,old}.log`): every layout
completes; the capture simply comes before that last update. Not caught by: label-layout pending,
post-activation WaitForGraphs, or draining the UI queue to idle (GetQueueStatus loop) - so the
trigger is background-driven (`BindingListSourceAllRowsChanged`/`ListChanged`, or tree AfterSelect
after `RestoreFloatingWindows`). Next: log which caller queues that update, then make the test (or
FoldChangeForm.IsComplete) wait for it.

Also added after fP2: WaitForPaint loops until the UI queue has no posted/sent/paint messages (max
20 passes), and CaptureScreenShot waits for graphs again after activation. Confirmed by n2
(TestTutorial: 26/26 pass, 16.9 min, 572/572 of git shots the old code holds) and fP3 (perf: 11/11
pass, 38.1 min, 294/295 - PBI s-19).

Committed locally (2026-10-31): 57d7076760 waits, 5d4d544336 tool temp report, bd24eac3d7 label
layout wait, 2b3fe1834a `/code-review medium` fixes - 8 of 10 findings taken (import-graph render
flag reset at the actual freeze, zero-size graph counts as rendered, disposed-graph layouts not
pending, registry pruned on add, PAINT_FLUSH=0 restores the old waits, flush at the end of
ActivateScreenshotForm, Common User32.EnumThreadWindows, per-manager retry count); dropped: the
capture loop under animation (capped at 10, logged, 0-1 retries seen) and WaitForGraphs covering
label layout (intended). 2b3fe1834a is built, CodeInspection and label-layout tests pass, but it has
NOT been run on screen - next screenshot run should be n3/fP4 against bA/bP via vs_git.py.

Translated set (from the folders): 1,001 en + 551 ja + 551 zh-CHS = 2,103 committed screenshots;
at ~2.3 s saved each, ~81 min per full run.
