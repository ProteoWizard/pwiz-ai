---
title: Keep heap-leak checking on the native-dialog connector tests
branch: Skyline/work/20260725_native_dialog_leak_fix
repo: sky_automation
status: completed
---

## Objective

The native-dialog AI Connector tests added in #4313 report heap leaks on some
nightly machines. PR #4453 would mute them from the heap check entirely (gated on
`SystemInformation.TerminalServerSession`). Keep the heap check ON and give the
tests the extra leak-check iterations their settling distribution needs instead.

## Why the growth is not a leak

Reproduced on an RDP box (`gs\nicksh`, Windows Server 2022, `SESSIONNAME=RDP-Tcp#1`).
Machines on the physical console do not reproduce it at all, which is why a second
developer's machine could not.

Measured with `DevTools/HeapProbe` (a bare `SaveFileDialog` loop, no Skyline code):

| Path | Growth |
|---|---|
| Vista `IFileDialog` — what WinForms actually uses here | 17.2 KB/dialog over 25 |
| Legacy comdlg32 (`AutoUpgradeEnabled=false`) | 37.0 KB/dialog over 25 |
| MessageBox | 0.29 KB/dialog (flat) |

Over 250 dialogs on the Vista path the rate decays 15.9 -> ~4 -> ~2.5 KB/dialog,
and individual 25-dialog stretches give memory back (one measured -268 KB). It is
a saturating shell cache, not unbounded growth.

Two corrections to PR #4453's stated reasoning:

* Its TestRunner comment justifies muting with the LEGACY comdlg32 path being
  "a genuine unbounded leak (~27 KB/dialog, dead-linear to 1000+ dialogs -- no
  plateau, so a warm-up cannot help)". These tests never take that path -
  `UseVistaDialogInternal=True` (verified by reflection in the probe). The PR's own
  description calls the modern path "a saturating cache (~4 KB/iteration decaying
  below 1 KB by iteration 500)".
* The failures are not deterministic. `TestPrmMcpConnector`, same binary, back to
  back: FAILED at 26.6 KB, then PASSED at 13.8 KB.

## Baselines on this machine (24 iterations, 20 KB threshold)

| Test | Dialogs/run | Result |
|---|---|---|
| TestNativeFileDialog | ~4 | passed, 17.9 KB |
| TestNativeMessageBox | ~2-3 | passed, 17.0 KB |
| TestPrmMcpConnector | 1 | FAILED 26.6 KB, then passed 13.8 KB |

All cluster against a 20 KB threshold - a distribution straddling the line.

## Proof that extra iterations settle it

With `IsFixedLeakIterations` temporarily forced true (so the loop cannot exit early)
the minimum trailing-7 mean heap delta at 48 iterations:

| Test | 24 iterations | 48 iterations |
|---|---|---|
| TestPrmMcpConnector | +26.6 (fail) / +13.8 | **-20.5 KB** |
| TestNativeFileDialog | +17.9 | **-18.7 KB** |
| TestNativeMessageBox | +17.0 | **-53.8 KB** |

The growth does not merely decay, it reverses once the shell caches saturate.

## Nightly fleet magnitudes (from LabKey, 2026-07-23/24)

Both tests flag broadly, not on a few machines - and higher than this box:

| Test | Machines | Range |
|---|---|---|
| TestPrmMcpConnector | 10 | 28.5 - 71.3 KB |
| TestNativeFileDialog | 9 | 26.5 - 56.3 KB |

First seen 2026-07-23 at git `a840067e8` - the AI Connector merge (#4313).

## Change

`TestRunner/Program.cs`: add `TestNativeFileDialog`, `TestNativeMessageBox` and
`TestPrmMcpConnector` to `LeakCheckIterationsOverrideByTestName` with
`ExpandedLeakCheck(LeakCheckIterations * 4)` = 96. `MutedHeapMemoryLeakTestNames`
stays empty, so heap-leak detection remains ACTIVE for these tests.

x4 rather than x2 because the fleet sits further up the saturation curve than this
machine (26-71 KB vs 13-27 KB at 24 iterations). Extra iterations are only consumed
when a test has not settled, so the ceiling is free on machines that converge early.

## Also covered

`TestMcpConnectorBackgroundDialog` gets `ExpandedLeakCheck()` (x2) as well - nightly run
84497 shows it still running at 20+ pass-1 iterations with a 63 KB trailing delta, so it
does not settle inside the default 24 either. Its spikiness is the paste-cancel timing,
not the dialog cache, so it does not need x4. This makes the branch a complete
replacement for PR #4453's TestRunner changes.

Coverage is complete: the native-dialog helpers are used by exactly four test files, and
the fourth (`LibraryBuildTest`) is `NoLeakTesting(EXCESSIVE_TIME)` so pass 1 skips it.

Verified on this machine with the fix in place:

| Test | Heap | Iterations |
|---|---|---|
| TestNativeFileDialog | -39.9 KB | 25 |
| TestNativeMessageBox | -62.2 KB | 24 |
| TestPrmMcpConnector | +14.8 KB | 25 |
| TestMcpConnectorBackgroundDialog | +0.6 KB | 12 |

PRM converged on its 25th pass - one past the old 24 ceiling that would have failed it.
(`deltas (N)` reports `iterationCount + 1`, and `break` skips the increment, so N is the
1-based pass on which it converged; the old cap only permits passes 1-24.)

Three further trials of each test with the fix:

| Test | Trial 1 | Trial 2 | Trial 3 |
|---|---|---|---|
| TestNativeFileDialog | 13.7 KB (24) | 15.7 KB (24) | 15.9 KB (23) |
| TestNativeMessageBox | -45.8 KB (23) | -47.0 KB (23) | -72.0 KB (24) |
| TestPrmMcpConnector | 14.1 KB (25) | 17.1 KB (23) | errored, re-ran clean at 16 KB (25) |

Margin on this machine is real but not large: TestNativeFileDialog sits at 13-16 KB
against the 20 KB threshold. The single -39.9 KB reading was a lucky window, not typical.
PRM needed pass 25 on three of four runs.

One trial errored outright rather than leaking; an immediate re-run passed and the error
text was not captured (output was filtered). Intermittent failures in this test family are
already being worked (#4454, #4456).

CodeInspection passes.

## Disconnected-session experiment (06:05, with the user's go-ahead) - VALIDATES THE FIX

`tsdiscon` on this session (confirmed `Disc` in qwinsta), then re-ran everything.

Bare-probe curve is unchanged by disconnection - 1007 KB at 150 dialogs vs 984 KB
connected, same per-block decay. So disconnection is NOT what makes the fleet hotter, and
the connected-session measurements are representative.

But the number of passes needed DOES change, and that is the whole story:

| Test | Disconnected | Connected | Under the old 24-pass cap |
|---|---|---|---|
| TestPrmMcpConnector | pass 27, 14.3 KB | pass 23-25 | **would FAIL** |
| TestNativeFileDialog | pass 28, 16.4 KB | pass 23-24 | **would FAIL** |
| TestNativeMessageBox | pass 24, 12.5 KB | pass 23-24 | just barely passes |

That is the direct confirmation the fix works in the state the nightly agents run in.

## Remaining risk (reduced, not eliminated)

The disconnected run above settles the mechanism, but it is still ONE machine. The fleet
runs hotter in absolute terms, so a machine needing far more than 28 passes is still
possible - though 96 now looks comfortable rather than speculative.

Nightly per-iteration trajectories (first-8 vs last-8 of the 24 pass-1 runs):

| Machine | TestPrmMcpConnector | TestNativeFileDialog |
|---|---|---|
| BRENDANX-UW6 | +93 -> +120 KB (rising) | +251 -> +49 KB (strong decay) |
| SKYLINE-DEV1 | +70 -> +42 KB (decay) | +70 -> +74 KB (flat) |
| BRENDANX-UW5 | +74 -> +64 KB (slight) | +87 -> +68 KB (slight) |

At iteration 24 the fleet is still at 42-120 KB/run and the decay is inconsistent, so
**96 iterations may not be enough there**. This machine is an ACTIVE RDP session; the
nightly agents sit in DISCONNECTED ones, which is the uncontrolled variable.

**Decisive experiment for the morning**: `tsdiscon` this session, then re-run the leak
check. Not run unattended - the session cannot be reconnected from inside it, and losing
it would have ended the night's work.

If a machine still flags at 96, options:

* **Recommended fallback - per-test heap THRESHOLD override** (e.g. 150 KB for these
  tests) so a gross leak is still caught. TestRunner has only mute lists and iteration
  overrides today; adding a threshold override is small and preserves far more detection
  than a mute.
* **Warm-up before the measured window** - unattractive on the numbers: the 600-dialog
  curve does not fall near 1 KB/dialog until ~150 dialogs, i.e. 2-3 minutes of setup per
  test process.
* **PR #4453's mute** - gives up heap detection for these tests entirely.

Saturation curve (600 dialogs, bare SaveFileDialog loop): 11.30 KB/dialog for the first
50, 4.66 for 50-100, 3.72 for 100-150, then oscillating around a ~1.4 MB plateau with two
net-negative blocks and single give-backs of 312 KB and 430 KB.

## COMPLETED 2026-07-26 -- merged as PR #4459

`TestNativeFileDialog`, `TestNativeMessageBox` and `TestPrmMcpConnector` now get
`ExpandedLeakCheck(LeakCheckIterations * 4)`. `MutedHeapMemoryLeakTestNames` stayed empty, so
heap-leak detection remains ACTIVE for all three -- the objective at the top of this file.

Changed from what is described above, before merging:

* `TestMcpConnectorBackgroundDialog` was dropped from the list. PR #4458 reworked that test to
  create one window instead of ~100,000, and it converges in 8 passes on all four agents that
  reported (UW7 -16.8 KB, DEV6 -33.3 KB, DEV4 -24 KB), so it needs no override.
* The Terminal Services framing in the code comment was removed. The session headers added by
  #4458 falsify it: BRENDANX-DT1 reports `TerminalServerSession=False` and leaks all three tests.
  The "Why the growth is not a leak" section above is still correct about saturation, but its
  RDP-only premise is not.

**Still unverified:** no nightly has run with #4459 yet. The claim this change rests on -- that
these tests settle within 96 iterations on the agents that fail at 24 -- is supported by local
runs and one disconnected-session run, not by fleet data. Check the next nightly.

**Known residual weakness**, recorded in the PR body rather than hidden: a longer ceiling gives a
genuinely leaking test more chances to exit on a lucky trailing window, because the per-run delta
is a wide distribution straddling the threshold. A per-test heap THRESHOLD override would be the
better instrument -- fixed iteration count, still catches a gross leak -- but TestRunner has only
mute lists and iteration overrides today.

## Notes

- The pass-1 leak check is not exposed by `ai/scripts/Skyline/Run-Tests.ps1`, so
  this work invoked `TestRunner.exe test=<name> pass1=on pass2=off loop=1` directly.
- Side finding, NOT part of this change: opening `ImportPeptideSearchDlg` and
  closing it with `wizard.Close` raises `GC-LEAK ... SkylineWindow, SrmDocument`;
  `wizard.CancelDialog` does not. Needs its own confirmation and issue.
