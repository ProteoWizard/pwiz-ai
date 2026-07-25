---
title: Keep heap-leak checking on the native-dialog connector tests
branch: Skyline/work/20260725_native_dialog_leak_fix
repo: sky_automation
status: in_progress
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

## Residual risk

This machine converges by 48; a fleet machine reporting 56-71 KB at 24 iterations is
roughly where this one was at iteration ~6, so it may need more than 96. The
definitive check is a nightly run. If a machine still flags at 96, the next lever is
a one-time warm-up (show/dismiss a file dialog before the measured window) rather
than muting - the modern IFileDialog path saturates, so a warm-up DOES help, contrary
to PR #4453's note (which was reasoning from the legacy path).

## Notes

- The pass-1 leak check is not exposed by `ai/scripts/Skyline/Run-Tests.ps1`, so
  this work invoked `TestRunner.exe test=<name> pass1=on pass2=off loop=1` directly.
- Side finding, NOT part of this change: opening `ImportPeptideSearchDlg` and
  closing it with `wizard.Close` raises `GC-LEAK ... SkylineWindow, SrmDocument`;
  `wizard.CancelDialog` does not. Needs its own confirmation and issue.
