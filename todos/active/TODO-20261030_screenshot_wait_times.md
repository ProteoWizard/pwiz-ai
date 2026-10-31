# Trim the fixed waits around tutorial screenshots

## Branch Information
- **Branch**: `Skyline/work/20261030_screenshot_wait_times`
- **Checkout**: `C:\proj\pwiz-work3` (NOT `C:\proj\pwiz`, which holds PR #4947)
- **Base**: `master`
- **Created**: 2026-10-30
- **Status**: In Progress - levers in place, ready for the night session
- **GitHub Issue**: none (planned as a night session by Brendan)
- **Module**: `skyline`
- **PR**: (pending)

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
- [ ] Baseline run(s) at default waits (night session)
- [ ] Reduced-wait runs and PNG classification (night session)
- [ ] Choose new defaults or conditional waits; implement
- [ ] Confirmation run; report minutes saved
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
