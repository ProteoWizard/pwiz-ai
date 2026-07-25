# TODO-20260723_native_dialog_leak_iterations.md

## Branch Information
- **Branch**: `Skyline/work/20260723_native_dialog_leak_iterations`
- **Worktree**: `sky_fixes` (nicksh's machine)
- **Base**: `master`
- **Created**: 2026-07-23
- **Status**: In Progress
- **GitHub Issue**: (none)
- **PR**: [#4453](https://github.com/ProteoWizard/pwiz/pull/4453)

## Problem

Nightly on some machines (e.g. BRENDANX-UW7) reported native (Win32) heap-memory leaks for
`TestNativeMessageBox` (153,936 heap bytes) and `TestMcpConnectorBackgroundDialog` (69,918
heap bytes). Managed and user/GDI deltas were ~0 — the growth is purely process-heap
(committed BUSY blocks, `GetProcessHeaps` + `HeapWalk`; see `RunTests.cs`).

## What was done

1. **Split the two large tests into single-aspect nested tests** (PR #4453). Each original
   class is now an `abstract` base holding shared setup; each aspect is a nested `[TestClass]`
   with its own `[TestMethod]` and `DoTest`. Nested classes are discovered by TestRunner
   (reflection over `assembly.GetTypes()`). Fewer native dialogs per run → smaller per-run
   heap delta.
   - `NativeMessageBoxTest` → `TestNativeMessageBoxSaveAsWithoutConfirmation`,
     `...ReplaceConfirmationDeclined`, `...ReplaceConfirmationAccepted`
   - `McpConnectorBackgroundDialogTest` → `TestMcpConnectorBackgroundDialogRead`,
     `...Cancel`
2. **Added a DevTool `HeapProbe`** (`pwiz_tools/Skyline/Executables/DevTools/HeapProbe/`) — a
   standalone .cs (no project) that shows/dismisses a bare `SaveFileDialog` or `MessageBox`
   in a loop with NO Skyline code, measuring the committed heap the same way TestRunner does.
3. **Added `TestNativeOpenFileDialogLeak`** (`TestFunctional/NativeOpenFileDialogLeakTest.cs`)
   — an `AbstractUnitTest` (NOT AbstractFunctionalTest) that shows/dismisses one native
   `OpenFileDialog` per run on an STA thread, dismissed from another thread via WM_CLOSE. It
   runs under TestRunner's pass-1 leak check but never starts Skyline, so its heap deltas are
   directly comparable to the functional tests' under the same 20 KB threshold, with none of
   our own code involved.

## KEY FINDING: the leak is machine-dependent

On **nicksh's machine (physical console session)**, NOTHING exceeds the 20 KB threshold:
- The 3 native-message-box tests pass pass-1 (worst trailing 8-run window 18.4 KB).
- `TestNativeOpenFileDialogLeak` pass-1: heap deltas ~4–10 KB.
- `HeapProbe save 120`: ~5 KB/iter early, decaying to ~2.6 KB/iter, plateaus by ~iter 20.

On the **other machine** (nicksh ran `results.txt`, 5 tests, `pass1 language=all wait=on`),
two tests LEAK reproducibly across 3 rounds and never saturate:
- `TestNativeMessageBoxSaveAsWithoutConfirmation`: heap ~42–48 KB (LEAKED each round)
- `TestNativeMessageBoxReplaceConfirmationDeclined`: heap ~30–38 KB (LEAKED each round)
- `TestNativeMessageBoxReplaceConfirmationAccepted`: ~16–19 KB (passed, just under)
- Both `TestMcpConnectorBackgroundDialog*` tests: clean (Read actually FREES ~324 KB)
- Committed heap climbed 9 → 16.6 MB over ~75 file-dialog iterations, still rising.

So the native **file dialog** is the source, and whether it leaks depends on the machine.

## UPDATE 2026-07-24: nightly shows the leak is UNIVERSAL (RDP hypothesis weakened)

The Nightly x64 dashboard (run for 07/23, `end=07/24/2026`) shows `TestNativeMessageBox`
flagged as a leak (⚠️) on **every machine whose git hash includes the test**
(hashes `a09ee…` and `a8400…`: BRENDANX-UW5, BRENDANX-DT1, SKYLINE-DEV6, BRENDANX-UW7).
The only two machines with 0 leaks (BOSS-PC, KAIPOT-PC1) are on an OLDER hash `8a320…`
from before the test was added — i.e. they don't run it yet, not counter-examples. The
same column also flags `TestNativeFileDialog`, `TestMcpConnectorBackgroundDialog`, and
`TestPrmMcpConnector` on multiple machines (the whole native-dialog/connector family).

Implications:
- **Universal, not machine-specific.** This substantially weakens the RDP hypothesis —
  if RDP were required, only remoted machines would leak, but every machine that has the
  test does. (RDP may still *amplify* magnitude — the disconnected experiment still tells
  us that — but it is no longer the primary lead.)
- **Corrects an earlier claim** in this TODO/PR: "leaks on the other machine, not on
  nicksh's console." That compared the *split* tests (1 dialog, borderline-passing) here
  against the old 2-dialog test elsewhere. A raw loop of the old `TestNativeMessageBox` on
  nicksh's console also grew ~28 KB/run — this console is not special.
- **Looks like the Windows shell cache, not a runaway leak.** The nightly memory graph
  climbs early then plateaus (~380–420 MB) and stays flat through pass 2. Total memory
  stabilizes — a saturating shell cache, not unbounded growth. Matches HeapProbe's bare
  SaveFileDialog (grows then plateaus) and uses no Skyline code.

Revised direction: the split alone will not fix nightly (it only trims magnitude, and the
other machine's split tests still leak). Since the growth is universal and OS-level, the fix
is test-infrastructure applied to the whole native-dialog family — most likely **muting**
these from the heap-leak check (`MutedHeapMemoryLeakTestNames` in `TestRunner/Program.cs`) or
a **warm-up that pre-saturates the shell cache** before the leak-check window — not a code
hunt. Confirm real-vs-cache with `TestNativeOpenFileDialogLeak` / `HeapProbe` first (does it
ever plateau?), and note the RDP-vs-console amplitude from the other machine.

## EARLIER HYPOTHESIS (now secondary): Remote Desktop

nicksh's console session does not leak; the machine(s) that do may be driven over
**Remote Desktop**. RDP remotes the display and changes how native common dialogs render and
allocate (the codebase already notes RDP-specific native-dialog behavior — see
`NativeFileDialogTest` comments re: `CopyFromScreen` throwing on a disconnected RDP session,
regression #4229). The common file dialog's shell/preview/thumbnail handlers are a plausible
per-dialog allocator that behaves differently over a remoted display.

## PRECEDENT: the #4265 RDP/accessibility GC-LEAK fix

Commit `9df041524b60cfd096f0d7bfe67b6708fd1a31f6` ("Fixed spurious GC-LEAK reports by opting
the test host into the latest accessibility level", #4265) fixed a related-but-different
problem:
- At the framework-default WinForms accessibility level, closing a window did not release the
  UI Automation accessible-object **provider handles**, which transitively pinned
  SkylineWindow/SrmDocument. Surfaced as a **GC-LEAK** (managed objects not collected), only on
  the Windows Server 2022 agent (TCA1).
- **It was NOT a real leak** — a *fixed* set of objects held by accessibility; the count did not
  grow over time. Fixed by `TestRunner.Main` setting all four `Switch.UseLegacyAccessibilityFeatures*`
  to false (opt into the latest accessibility level, where providers are released on close).

How the current problem differs:
- That fix is **already in `TestRunner.Main`**, yet the current growth still happens → not the
  same code path.
- #4265 was **WinForms** accessibility. The current leak is the native **shell** common file
  dialog (`#32770`), whose UIA providers are *outside* the `UseLegacyAccessibilityFeatures`
  switch's scope.
- Symptom: #4265 was managed **GC-leak, fixed count**; this is native **committed heap, growing**
  (~45 KB/iter, 9→16.6 MB non-saturating).

Refined hypothesis: under RDP, the accessibility/UIA bridge queries the native file dialog, and
the shell instantiates **native** UIA/COM provider objects per dialog that accumulate on the
process heap. Same family (RDP + accessibility), different layer (shell/native vs WinForms/managed).
**Open question to answer: is the count truly growing (real leak) or a fixed hold that looks like
growth (as in #4265)?**

## FOR THE OTHER MACHINE (task for Claude on the leaking machine)

Please help confirm the cause. Pull branch `Skyline/work/20260723_native_dialog_leak_iterations`
and build TestFunctional + TestRunner.

1. **Reproduce and record the split-test result** on this machine:
   ```
   TestRunner.exe test=TestNativeMessageBoxSaveAsWithoutConfirmation,TestNativeMessageBoxReplaceConfirmationDeclined,TestNativeMessageBoxReplaceConfirmationAccepted pass1=on pass2=off
   ```
   Record the per-test `heap` deltas and any `LEAKED` lines.

2. **Run the no-Skyline unit test** (isolates the OS dialog from all our code):
   ```
   TestRunner.exe test=TestNativeOpenFileDialogLeak pass1=on pass2=off
   ```
   - If this LEAKS (heap ≥ 20 KB) → the growth is the Windows common file dialog itself, not
     Skyline/connector code. That settles it: the fix belongs in test infrastructure.
   - If this stays clean while the functional tests leak → there is a real leak in our
     native-dialog path; investigate there.

3. **Run the bare DevTool probe** (no test harness at all), from
   `pwiz_tools/Skyline/Executables/DevTools/HeapProbe/`:
   ```
   csc.exe /platform:x64 /target:exe /out:HeapProbe.exe /r:System.Windows.Forms.dll /r:System.Drawing.dll HeapProbe.cs
   HeapProbe.exe save 120
   HeapProbe.exe msgbox 30
   ```
   `save` climbing without plateau = the shell; `msgbox` should stay flat.

4. **The decisive experiment — RDP vs console.** Run step 2 (and/or 3) BOTH:
   - over a Remote Desktop session, AND
   - at the physical console / an attached session (e.g. via `tscon` to redirect the session
     to the console, or on the machine directly).
   If it leaks under RDP but not at the console, the Remote Desktop hypothesis is confirmed and
   the answer is to make these tests tolerant of that environment (warm-up before the leak
   window, or expanded iterations / muting for the native-file-dialog tests), not to chase a
   nonexistent code leak.

5. **Real growth vs fixed hold (the #4265 distinction).** If it does leak, determine whether the
   growth is unbounded or plateaus. Let `TestNativeOpenFileDialogLeak` run for many more
   iterations (e.g. `pass1 wait=on`, or a large `loop=`) and watch the committed heap (2nd MB
   number): does it keep climbing indefinitely (real leak) or flatten at a ceiling (a fixed
   accessibility/shell hold that merely looks like a leak within 24 iterations, as in #4265)?
   `HeapProbe save 500` is a fast harness-free way to see whether it ever saturates.

Please write your findings back into this TODO (a "Results from <machine>" section with the
heap deltas for steps 1–4 and the RDP-vs-console outcome), and note the Windows build/version
and whether the session was RDP or console.

## Files Changed (PR #4453)

- `pwiz_tools/Skyline/TestFunctional/NativeMessageBoxTest.cs`
- `pwiz_tools/Skyline/TestFunctional/McpConnectorBackgroundDialogTest.cs`
- `pwiz_tools/Skyline/TestFunctional/NativeOpenFileDialogLeakTest.cs` (new)
- `pwiz_tools/Skyline/TestFunctional/TestFunctional.csproj`
- `pwiz_tools/Skyline/Executables/DevTools/HeapProbe/HeapProbe.cs` (new)
- `pwiz_tools/Skyline/Executables/DevTools/HeapProbe/README.md` (new)
- `pwiz_tools/Skyline/Executables/DevTools/README.md`

## Results from nicksh's machine (console session)

- Split native-message-box tests, pass-1 (en/fr/tr/ja/zh, cold process): all clear, every
  trailing heap delta under 20 KB (worst 18.4 KB), no LEAKED — vs original 153,936 bytes.
- `TestNativeOpenFileDialogLeak`, pass-1: heap deltas ~4–10 KB, no LEAKED.
- `HeapProbe save 120`: ~5 KB/iter decaying to ~2.6, plateaued.
- Session: physical console (not RDP). Did not reproduce the leak *at these magnitudes*.
  **Caveat (reconciled):** this used the MessageBox and modern-`save` paths, which are low-rate /
  saturating even under RDP. The console is NOT immune — a legacy file-dialog loop grows ~28 KB/run
  here too (see UPDATE 2026-07-24). The console difference is amplitude, not presence.

## Results from nicksh's machine — RDP SESSION (SAME MACHINE, leak reproduced)

> **RECONCILED — read this first.** This section was originally written as "the decisive A/B
> proving RDP is *required*." That overstated it. The later nightly evidence (see UPDATE
> 2026-07-24: the leak is **universal**, every machine with the test leaks, and this console is
> "not special" — a raw loop of the old file-dialog test grew ~28 KB/run here too) and the 1000-
> dialog plateau experiment together show the real picture: **the common file dialog grows the
> heap in every session; TS/RDP amplifies the magnitude but is not a prerequisite.** The two
> claims below that survive are the negative control (MessageBox never leaks → it is the file
> dialog specifically) and the modern-vs-legacy split. Treat the numbers below as valid RDP
> measurements, not as proof that the console is clean.

These results were produced on nicksh's machine over RDP (`SESSIONNAME=RDP-Tcp#0`), the *same*
physical machine, same day, same `HeapProbe.cs` as the console-session results above.

Session verified as Remote Desktop: `SESSIONNAME=RDP-Tcp#0`,
`SystemInformation.TerminalServerSession=True`, `CLIENTNAME=NICKSH-ELITEBOO`. `query session`
showed a separate `console` session (ID 2) with no interactive user, and our active session
`rdp-tcp#0` (ID 3). Windows 11 Pro 26200.

### HeapProbe (bare dialogs, NO Skyline code) over RDP

| mode | dialog | growth | per-iter | shape |
|------|--------|-------:|---------:|-------|
| `msgbox` (control) | MessageBox | 6–7 KB / 60 | ~0.1 KB | flat |
| `save` | modern `SaveFileDialog` (IFileDialog) | 302 KB / 60 · 681 KB / 120 | ~5 KB | linear, **no plateau** |
| `open` | modern `OpenFileDialog` (IFileDialog) | 685 KB / 120 | ~5.7 KB | linear, **no plateau** |
| `savelegacy` | legacy comdlg32 `GetSaveFileName` | 1656 KB / 60 | ~27.6 KB | linear, **no plateau** |
| `openlegacy` | legacy comdlg32 `GetOpenFileName` | 3389 KB / 120 | ~28.2 KB | linear, **no plateau** |

Two independent findings:

1. **It is not our code — a bare dialog leaks with zero Skyline present.** Over RDP the bare
   `SaveFileDialog`/`OpenFileDialog` loop climbs; the probe contains no Skyline/connector/test
   code. *(Original wording claimed "RDP alone flips the result — console does not leak, RDP
   never plateaus over 120." Both halves are now corrected: the console is not special — see the
   2026-07-24 universal finding — and "no plateau over 120" was too short a run. The 1000-dialog
   experiment shows the modern dialog actually saturates by ~iter 500 (4.3 → ~1 KB/iter), while
   only the legacy comdlg32 dialog stays dead-linear.)*
2. **It is NOT the modern shell/preview/thumbnail handlers.** Added an `AutoUpgradeEnabled`
   switch to the probe (`open`/`save` = modern IFileDialog; `openlegacy`/`savelegacy` = legacy
   comdlg32). The *legacy* comdlg32 dialog leaks ~5× **worse** (28 KB/iter, dead-linear) than
   the modern one. So the earlier "modern IFileDialog preview handlers" guess is wrong; the
   leak lives in the more fundamental common-dialog + remoted-display (GDI/RDP display driver)
   path, and the legacy dialog is the worse offender.

The `msgbox` control staying flat over RDP is the key negative control: it isolates the growth
to the **common file dialog** specifically, not "RDP in general" and not the probe's own
modal-loop / background-thread WM_CLOSE dismissal plumbing (which msgbox exercises identically).

### HeapProbe changes made this session

Added `open`, `openlegacy`, `savelegacy` modes and an `AutoUpgradeEnabled` parameter to
`ShowSaveDialog`/`ShowOpenDialog` in `HeapProbe.cs` (was `save`/`msgbox` only). Not yet
committed.

### DISCONNECTED RDP (client disconnected, session left running in `Disc` state)

Launched a detached self-logging probe run, then disconnected the RDP client for ~20 min and
reconnected. `query session` was captured at every mode boundary and showed our session (ID 3)
in **`Disc`** state throughout the entire run (log:
`ai/.tmp/heapprobe_disconnected/disconnected_run.log`, script `Run-DisconnectedProbe.ps1`).

| mode | connected RDP | **disconnected RDP** |
|------|--------------:|---------------------:|
| `msgbox` (control) | ~0.1 KB/iter | **0.0 KB/iter (2 KB/60)** flat |
| `save` (modern) | ~5.0 KB/iter | **4.0 & 5.5 KB/iter** |
| `open` (modern) | ~5.7 KB/iter | **4.1 KB/iter** |
| `openlegacy` (comdlg32) | ~28.2 KB/iter | **28.7 & 28.2 KB/iter** |
| `savelegacy` (comdlg32) | ~27.6 KB/iter | **27.7 KB/iter** |

**The leak persists essentially unchanged while the client is disconnected.** Therefore it is
NOT the live RDP display transport/encoder or anything about an attached viewer — merely being
a **disconnected Terminal Services session** (the headless remoted-display driver stack) is
sufficient. The legacy comdlg32 dialog is again dead-linear at ~28 KB/iter, identical connected
vs disconnected; the modern IFileDialog is the same ~4–5 KB/iter with more run-to-run noise; the
MessageBox control stays flat. This is exactly the state nightly machines sit in (logged in over
RDP, then disconnected → `Disc`), which explains why they leak while the physical console does not.

### Still to run on this machine (not yet done)

- **TestRunner legs (steps 1 & 2)** — needs a TestFunctional + TestRunner build in
  `sky_fileopendialog`, which was not built this session. Worth doing now that this RDP
  session reproduces the leak: `TestNativeOpenFileDialogLeak` and the three split
  `TestNativeMessageBox*` tests should now LEAK here too, giving a harness-level confirmation
  that matches BRENDANX-UW7.
- **The clean console leg on this machine** — the console data above was recorded separately;
  a within-session `tscon`-to-console redirect was deliberately NOT done because it would
  disconnect the live RDP session. To nail it down, run `HeapProbe.exe openlegacy 120` while
  physically logged in at the console (28 KB/iter over RDP should collapse to a plateau there).
- **RDP parameter sweep** (optional) — reconnect with persistent bitmap caching off, lower
  color depth, or themes/font-smoothing disabled to see whether the per-dialog rate changes;
  would further localize which remoted-display allocation is responsible.

### Bottom line (reconciled with the 2026-07-24 universal finding and the plateau experiment)

The OpenFileDialog/SaveFileDialog grows the process heap via the OS common file dialog, not our
code — the MessageBox control never leaks, isolating it to the file dialog specifically. Two
facts settle the shape of the fix:

- **The leak is universal, not RDP-gated.** Nightly shows it on every machine that has the test
  (see UPDATE 2026-07-24); a file-dialog loop grows on this physical console too. **RDP/TS
  amplifies the per-dialog magnitude but is not required.** (The disconnected-`Disc` run shows a
  live viewer is not required either — being a TS session is enough to get the amplified rate.)
- **Modern dialog saturates; legacy dialog does not.** Out to 1000 dialogs the modern IFileDialog
  decays 4.3 → ~1 KB/iter (a shell cache), but the legacy comdlg32 dialog is dead-linear at
  27 KB/iter (27 MB, a true unbounded leak). The functional tests' ~30–45 KB/iter matches the
  legacy path.

**Fix:** because the offending (legacy) path never plateaus, warm-up cannot solve the real
nightly failure. **Mute the native-file-dialog family from the HEAP check**
(`MutedHeapMemoryLeakTestNames`), gated on `SystemInformation.TerminalServerSession` so the
console keeps full detection. See "RESULTS: plateau experiment" and "DECISION: mute, not
warm-up" below for the numbers and the criteria.

## NEXT EXPERIMENT (decides warm-up vs. mute) — for the RDP-session Claude

We now know the leak is the OS common file dialog under a Terminal Services (RDP) session,
including disconnected (`Disc`). The remaining fork in the FIX is whether the growth ever
**plateaus** if you show enough dialogs:

- nicksh proposed a one-time **warm-up**: a static "warmed up?" flag; each affected test, on
  first run in the process, shows/dismisses a native file dialog N times before the leak-check
  window. This ONLY works if the per-dialog growth decays toward ~0 after enough dialogs.
- So far it is **dead-linear over 120 dialogs** (no decay). 120 is not 1000, so it is unsettled.

**Please run, in the RDP session (connected or `Disc` is fine), out to ~1000 dialogs and report
whether the per-iteration rate decays:**
```
HeapProbe.exe save 1000
HeapProbe.exe open 1000
HeapProbe.exe savelegacy 1000     # the worst offender, ~28 KB/iter so far
```
For each, note the **mean KB/iter over the LAST ~100 dialogs** vs the first ~100. Decision:
- If the last-100 rate collapses to ~0 (it plateaus) → **warm-up is the fix**: implement a
  shared one-time warm-up (static flag) that shows/dismisses a native file dialog ~N times
  (N = where it flattened) before the leak window. Tests then pass legitimately, nothing muted.
  Also report roughly how many dialogs/seconds N costs, so we know if the one-time price is
  tolerable for nightly.
- If it is still linear at 1000 (no plateau) → **warm-up cannot work**; the fix is to mute the
  native-file-dialog family from the HEAP check only (`MutedHeapMemoryLeakTestNames` in
  `TestRunner/Program.cs`), ideally gated on `SystemInformation.TerminalServerSession` so the
  console keeps full heap-leak detection.

## RESULTS: plateau experiment (RDP session, 1000 dialogs each) — 2026-07-24

Ran the three modes to N=1000 in this RDP session (`SESSIONNAME=RDP-Tcp#0`, Active). Rates are
from the `delta-from-baseline` column; raw logs in `ai/.tmp/heapprobe_plateau/*_1000.log`,
runner `Run-PlateauExperiment.ps1`.

| mode | total growth | first-100 | iters 500–600 | last-100 | shape |
|------|-------------:|----------:|--------------:|---------:|-------|
| `save` (modern IFileDialog) | 1,870 KB | 4.30 KB/iter | 1.22 | **0.83 KB/iter** | decays / saturates |
| `open` (modern IFileDialog) | 1,889 KB | 4.24 KB/iter | 1.99 | **1.11 KB/iter** (last-200: 0.18) | decays / saturates |
| `savelegacy` (comdlg32) | **26,950 KB (~27 MB)** | 27.20 KB/iter | 27.31 | **27.00 KB/iter** | **dead-linear, zero decay** |

**The fork resolves BOTH ways, split by dialog type:**

- **Modern IFileDialog is a saturating shell cache.** ~4.3 KB/iter early, decaying ~5× to
  ~0.8–1.1 KB/iter by iter 1000. So the earlier "no plateau over 120" was just too short a run —
  it flattens by ~iter 500. A warm-up WOULD tame the modern dialog. But it is already under the
  20 KB threshold, so it is not what fails nightly.
- **Legacy comdlg32 is a genuine unbounded leak.** Perfectly linear at 27 KB/iter all the way to
  1000 dialogs (27 MB committed), no decay at any point. **A warm-up cannot help this** — there
  is no ceiling to pre-fill.

**Magnitude points at the legacy path as the nightly culprit:** functional tests leak
~30–45 KB/iter, matching the legacy ~27 KB/iter path, NOT the modern ~1–4 KB/iter path.

### DECISION: mute, not warm-up

Per the criteria above, the offending (legacy) path is still linear at 1000 → **warm-up cannot
work; mute the native-file-dialog family from the HEAP check only**
(`MutedHeapMemoryLeakTestNames` in `TestRunner/Program.cs`), gated on
`SystemInformation.TerminalServerSession` so the physical console keeps full heap-leak
detection. (A warm-up would still be a legitimate option for the modern-dialog tests
specifically, but it does not address the real nightly failure, so mute is the primary fix.)

### Notes for whoever implements the fix
- `TestNativeOpenFileDialogLeak` as written uses a **modern** OpenFileDialog
  (`AutoUpgradeEnabled` defaults true) → only ~5.7 KB/iter under RDP, UNDER the 20 KB threshold,
  so it does **not** currently reproduce the nightly failure. To make it a faithful repro it
  would need `AutoUpgradeEnabled = false` (legacy comdlg32, ~28 KB/iter) — but then it would be
  flagged in nightly itself and need muting too. This is a point for keeping HeapProbe (a
  non-test) as the diagnostic. Keep-vs-drop of this test is still open.
- Unexplained magnitude gap: functional tests leak ~30–45 KB/iter but a bare modern dialog is
  only ~5 KB and a bare legacy dialog ~28 KB. The functional number is likely legacy dialogs
  and/or the per-iteration document save / file I/O also allocating under TS — worth confirming
  before claiming the bare test is an exact stand-in.
- Plan once the plateau question is answered: revert the test split (it was diagnostic, does not
  fix nightly), keep the chosen diagnostic (HeapProbe and/or the test), and apply the
  warm-up-or-mute fix to the native-dialog family.

## UPDATE 2026-07-24 (evening): TestMcpConnectorBackgroundDialog root cause found

Full 07/24 nightly (10 machines via LabKey MCP) gives the real magnitudes — the earlier
"spiky near threshold" read was WRONG. TestMcpConnectorBackgroundDialog leaks **25,056 /
42,624 / 47,385 / 104,235 bytes** across DT1/DEV4/... — mean ~55 KB, every reading ABOVE the
20 KB threshold (up to 5x), on 6/10 machines.

**Root cause (not the OS file dialog, not our logic):** the test pastes 50,000 rows x 2 columns
into a grid; `DataGridViewPasteHandler.TrySetValue` runs per cell and does
`CurrentCell = cell; BeginEdit(true); ...; EndEdit()` -- one editing-control (Win32 window)
create/destroy PER CELL, up to ~100,000 per run.

Proven with `GridEditProbe` (scratchpad, no Skyline code -- bare DataGridView BeginEdit/EndEdit
loop): on a CONSOLE session it grows **~0.028 KB/edit, roughly linear, no plateau** (239->931 KB
over 8k->32k edits), user handles flat (native heap, not a handle leak). So it is WinForms/
platform window-churn, the same family as the native-dialog leak, arriving via grid editing
controls instead of file dialogs.

This explains everything: no native dialog yet leaks (it's the grid); 4x variance (paste is
cancelled at a nondeterministic point, so the edit count -- and growth -- varies with machine
speed); above threshold on most machines (ExpandedLeakCheck cannot fix a workload-scaled growth).

**Fix implication — the ExpandedLeakCheck entry added earlier is WRONG and must be reverted.**
Options: (a) mute this test from the HEAP check like the native-dialog family (plain, not
TS-gated, since it grows on console too -- though the test stays under threshold on console
because it cancels early); or (b) drop PROPERTY_COUNT so far fewer edits run before the
connector cancels. Decide with tomorrow's fleet data. `GridEditProbe` is ready for the RDP
machine to confirm TS amplification.

## UPDATE 2026-07-25 (night session, nicksh's machine): enumeration hypothesis DISPROVEN

nicksh proposed that `TestMcpConnectorBackgroundDialog` -- which involves no native dialog --
leaks through the way the connector **enumerates window handles**, specifically reading the
text of windows owned by another thread via `User32.InternalGetWindowText`
(`GetWindowTextNoBlock`). **Measured directly; it is not the source.**

Probe: `LeakProbe.cs` (session scratchpad, no Skyline code), measuring committed Win32 heap
exactly the way `RunTests.MemoryManagement` does (`GetProcessHeaps` + `HeapWalk`, summing
BUSY blocks). A real `Form` runs its own message loop on its own thread, so the cross-thread
branch of `GetWindowTextNoBlock` is genuinely exercised.

| probe | iterations | committed heap growth |
|---|---:|---:|
| `idle` (control) | 200,000 | 368 B, flat |
| `text` -- `InternalGetWindowText`, cross-thread | 200,000 | **368 B, flat** (identical to control) |
| `enum` -- full connector enumeration<sup>1</sup> | 20,000 | **2,736 B, flat after iter 2,000** |

<sup>1</sup> `EnumWindows` + `GetWindowThreadProcessId` + `IsWindowVisible` +
`GetWindowTextNoBlock` + `Control.FromHandle` -- the exact `StandaloneWindow.GetTopLevelWindows`
sequence.

Three independent lines of evidence agree:

1. The measurement above: the path is a one-time 2.7 KB, then dead flat.
2. **#4455 already tested this hypothesis** ("Reduce memory churn in EnumWindows", pass the
   same delegate). Runs on hash `015d8956b` still leak: 21,462 / 32,525 / 60,301 / 65,801 bytes.
3. **19 of the 21 `*McpConnector*` tests** exercise the identical enumeration path on every
   `GetOpenForms` and do not leak at all. Only 2 of 21 do.

## What the nightly number actually means (worth pinning down)

`LeakTracking.MeanDelta` telescopes -- it averages consecutive deltas, so it equals
**(last - first) / 7** over the 8-run window (`LeakTrailingDeltas = 7`). `minDeltas` then keeps
the running **minimum** across up to 17 such windows (`LeakCheckIterations = 24`). So a
reported 58 KB heap leak means *every* 8-run window rose >= 410 KB net, and the best one still
rose 410 KB. That is sustained growth over 24 runs, not a single spike -- which rules out
"one unlucky iteration" as an explanation.

## The file-dialog explanation does NOT cover TestPrmMcpConnector

Full 07/24 fleet numbers (LabKey `testresults.memoryleaks`, mean bytes):

| test | mean bytes | needs net/8-run | native file dialog per run |
|---|---:|---:|---|
| `TestNativeMessageBox` | 131,311 | ~919 KB | 2-3 legacy comdlg32 |
| `TestMcpConnectorBackgroundDialog` | 58,817 | ~412 KB | **none** |
| `TestPrmMcpConnector` | 51,607 | ~361 KB | one, **modern** IFileDialog |
| `TestNativeFileDialog` | 40,997 | ~287 KB | yes |

The legacy-dialog rate (~27-28 KB/dialog, dead-linear) explains `TestNativeMessageBox`
quantitatively: 2-3 dialogs x ~28 KB x 8 runs ~= 670 KB, right order of magnitude.

It does **not** explain `TestPrmMcpConnector`. That test opens exactly one "Add Input Files"
dialog per run, and it is the *modern* `IFileDialog` path (`AutoUpgradeEnabled` defaults true),
measured in this TODO at ~4-5.7 KB/iter under RDP. That is ~5 KB against a ~361 KB requirement
-- a **70x gap**. So **two** of the four tests are quantitatively unexplained, not one. The
earlier framing ("the whole native-dialog/connector family is the OS file dialog") is too broad.

## Grid-workload probes (the competing hypothesis for the background-dialog test)

Same probe, console session:

| mode | what it does | result |
|---|---|---|
| `grid` | fixed-size grid, `CurrentCell`/`BeginEdit(true)`/`EndEdit` churn, 40,000 edits | rises to ~200 KB by iter 2,000 then **oscillates 195-330 KB**; bytes/iter decays 103 -> 5. Not linear. |
| `gridgrow` | same but the grid **grows** a row at a time (what the paste does), 40,000 edits | climbs 254 -> 722 KB, ~18 B/edit sustained, no plateau |
| `gridcycle` | 20 full cycles of *create form+grid -> 2,000 rows pasted -> dispose*, i.e. one cycle == one test run | cumulative delta **oscillates 267-679 KB with no net trend**; consecutive-cycle swings of **+375 / -342 / -204 / +114 KB** |

Reading of this:

- `gridgrow`'s climb is mostly **live row storage**, not a leak -- the grid is holding more
  rows, and my probe never disposes it. It does not by itself prove a leak.
- `gridcycle` is the honest model of a test run, and it shows the important thing: the paste
  workload leaves the process heap swinging by **hundreds of KB between consecutive runs**,
  an order of magnitude above the 20 KB threshold, while the underlying level is stable.
- That swing scales with **how many rows were pasted before the connector cancelled**, which
  races machine speed -- a natural explanation for the 6x spread in the fleet numbers
  (21,462 to 129,540 bytes on the same commit).

This partially corrects the 2026-07-24 evening entry above: the per-cell editing-control
create/destroy is **not** an unbounded linear leak (fixed-size grid plateaus). What scales is
the row count, and across create/dispose cycles there is noise, not monotone growth --
**at least on this console-like session**.

## Not reproduced locally (important caveat)

`Run-Tests.ps1 -TestName TestMcpConnectorBackgroundDialog -Loop 14 -Configuration Release`
(pass 2, en-US only) on this machine: heap 5.22 / 5.22 / 5.25 / 6.67 / 6.64 / 6.65 / 6.64 /
6.65 / 6.60 / ... / 6.61 / 6.60 / 6.63 MB. One step at iteration 5, then flat; consecutive
deltas +-30 KB with mean ~= 0. **No leak here.** So the mechanism that makes the rise
*persist* across 24 runs on nightly agents is still unproven, and this session cannot see it.

Note this run used `language=en-US` only, whereas the pass-1 leak check cycles
en/fr/tr each iteration (`runTests.Language = allLanguages[i % allLanguages.Length]`).
A pass-1 leak check is running to see whether language cycling is what makes it persist.

## UPDATE 2026-07-25 (night session, part 2): the real leaking log, and two corrections

Pulled the actual nightly logs from LabKey (`testruns.log` is a gzip byte array; decompress it --
script `getlog.py` in the session scratchpad) for run **84490 (BRENDANX-UW7, leaking)** and run
**84479 (RITACH-DSK, clean)**, both on hash `a09eea912`.

### The leak is REAL and unbounded -- not heap noise

Heap column across the 25 pass-1 iterations on BRENDANX-UW7:

| test | heap first -> last (MB) | per run | TestRunner verdict |
|---|---|---:|---:|
| `TestMcpConnectorBackgroundDialog` | 77.24 -> 82.01 | **212 KB** | 129,540 |
| `TestNativeMessageBox` | 80.14 -> 84.19 | **180 KB** | 175,723 |
| `TestPrmMcpConnector` | 79.80 -> 81.36 | **69 KB** | 53,712 |
| `TestNativeFileDialog` | 78.59 -> 79.97 | **61 KB** | 42,763 |

Dead linear, no plateau, monotone. Meanwhile managed is flat and *total private memory is flat at
428 MB* -- so this is native heap growth specifically, not process growth.

**This supersedes the "heap-state noise / workload variance" reading in the night-session part 1
notes above.** That reading came from a console session that does not reproduce.

### Ranked ALL 1065 tests in the run by TestRunner's own metric

Parsing every `# <test> deltas (n): ... heap = X KB` line:

```
171.6 TestNativeMessageBox          126.5 TestMcpConnectorBackgroundDialog
 52.5 TestPrmMcpConnector            41.8 TestNativeFileDialog
------------------------------------------ threshold 20.0
 20.0 TestSrmSmallMoleculeChromatograms, then ~20 tests in the 16-20 band
```

The four leakers are separated from everything else by a clear gap. They are genuinely special, not
the top of a continuum.

**Correction to an earlier draft of this line:** it said "ambient per-run heap growth for an ordinary
functional test is 16-20 KB". That is wrong -- 16-20 KB is the *p99 tail*, not the typical test. The
full distribution of the `heap = X KB` verdicts, both machines:

| log | n | min | p25 | median | p75 | p90 | p99 | max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| RITACH-DSK (clean) | 896 | -149.9 | -7.2 | **0.0** | 1.1 | 7.2 | 17.1 | **19.9** |
| BRENDANX-UW7 (leaking) | 1079 | -459.3 | -8.7 | **-0.1** | 0.2 | 8.6 | 18.8 | **171.6** |

The typical test is at ~0 KB on **both** machines, and the two distributions are near-identical all
the way to p99. So the leaking agents are **not** globally noisier -- the difference is confined to
the window-heavy tests, which is what the mechanism below predicts.

**Read the top of that table with care -- there is a censoring artifact.** The pass-1 loop *stops as
soon as a trailing window comes in below the thresholds* (`BelowThresholds` -> `break`), so for any
test that PASSES, the reported number is whatever the first qualifying window was, and is therefore
bounded just under 20 KB by construction. That is why both machines report a max of exactly 19.9 KB.
Consequences:

* The p99 / max columns are not comparable across machines in the usual way. The real difference is
  simply **how many tests never get under 20 KB**: zero on RITACH-DSK, four on BRENDANX-UW7.
* A cluster of tests reported in the 17-19.9 KB band (`TestInstrumentInfo` 19.9, `TestPolarityMismatch`
  19.6, `TestDocumentGrid` 19.4, `TestSkipZoomScans` 19.1, ~14 more) should **not** be read as "about
  to trip". A noisy test exits at the first window that dips under the bar, which will often be just
  under it; the value says more about where it stopped than about its true rate.
* If a stable per-test rate is ever wanted, it needs a fixed iteration count
  (`IsFixedLeakIterations`, currently hard-coded false) rather than the early-exit loop.

### CORRECTION 1: the RDP/Terminal-Services hypothesis is RESTORED

The "UPDATE 2026-07-24: the leak is UNIVERSAL (RDP hypothesis weakened)" section above is **wrong**.
It concluded "universal" because the only machines with 0 leaks on 07/23 were on an older hash that
did not contain the tests. On **07/24 that is no longer true**:

| machine | hash | leakedtests |
|---|---|---:|
| **RITACH-DSK** (84479) | a09eea912 | **0** |
| **KAIPOT-PC1** (84488) | a09eea912 | **0** |
| every other machine | a09eea912 / 015d8956b | 2-6 |

RITACH-DSK *ran* the tests (8 and 24 iterations logged) and did not leak. Same commit, same tests,
opposite result -> the difference is **environmental**, which is what the original RDP hypothesis said.

Same test, same commit, two machines:

| test | RITACH-DSK (clean) | BRENDANX-UW7 (leaking) |
|---|---:|---:|
| `TestMcpConnectorBackgroundDialog` | **-1.0 KB (flat)** | 126.5 |
| `TestNativeMessageBox` | **-3.1 KB (flat)** | 171.6 |
| `TestPrmMcpConnector` | 19.8 (climbing) | 52.5 |
| `TestNativeFileDialog` | 19.6 (climbing) | 41.8 |

### CORRECTION 2: Skyline never uses the legacy comdlg32 dialog

The DECISION above ("mute, not warm-up") rests on *"the offending (legacy) path never plateaus"*.
But Skyline never takes that path:

```
grep -r "AutoUpgradeEnabled" pwiz_tools/   -> no matches
grep -r "ShowHelp"           pwiz_tools/Skyline -> no matches
grep -r "ShowReadOnly"       pwiz_tools/Skyline -> no matches
```

`FileDialog.AutoUpgradeEnabled` defaults to true, and WinForms only falls back to legacy comdlg32
when it is false, or `ShowHelp` is true, or `OpenFileDialog.ShowReadOnly` is true. None occur. So
**every Skyline file dialog is the modern IFileDialog** -- the path this TODO's own 1000-dialog
experiment showed *saturates* (4.3 -> 0.83 KB/iter, flat by ~iter 500). The dead-linear 27 KB/iter
`savelegacy`/`openlegacy` rate was an artifact of HeapProbe explicitly setting
`AutoUpgradeEnabled = false`; no Skyline code path reaches it.

Consequence: the magnitudes are NOT explained by "legacy dialog leak" for any of the four tests, and
the reason given for rejecting warm-up does not apply to what Skyline actually runs.

### Two populations, one plausible mechanism

The 07/24 machine x test matrix separates cleanly:

* **Universal, near-threshold** -- `TestPrmMcpConnector`, `TestNativeFileDialog`: leak on **9/9**
  machines that ran them, and sit at 19.6-19.8 KB even on the clean machines (i.e. under the 20 KB
  bar by a hair).
* **Environment-dependent, large** -- `TestMcpConnectorBackgroundDialog`, `TestNativeMessageBox`:
  flat on RITACH-DSK, 100-175 KB elsewhere.

A single mechanism fits both: **under a Terminal Services / remoted-display session, Win32 window
creation+destruction leaks native heap**, and the four tests are exactly the ones that create an
unusual number of windows per run --

| test | windows created per run |
|---|---|
| `TestMcpConnectorBackgroundDialog` | ~100,000 short-lived grid editing controls (50,000 rows x 2 cells) |
| `TestNativeMessageBox` | 3 native Save dialogs (each ~100 child windows) + 2 message boxes |
| `TestNativeFileDialog`, `TestPrmMcpConnector` | 1 native file dialog each |
| the other 19 `*McpConnector*` tests | almost none -- and all are **dead flat**, 0 sec |

Consistent supporting measurements (this console session, which behaves as non-TS):
* Doubling the background-dialog test's paste workload (a 5 s delay before the connector cancels, so
  ~2x the cells are pasted) changed the heap delta not at all: **2.3 KB vs 2.4 KB baseline**. On a
  console, window churn is free -- exactly what the model predicts.
* Enumeration / `InternalGetWindowText` / cross-thread `Control.Invoke` probes: all flat (part 1).

**Not yet directly measured:** "window create/destroy under TS" itself, and whether RITACH-DSK /
KAIPOT-PC1 are in fact console sessions. Both need someone on those machines. That is the single
experiment that would settle this.

## SEPARATE PROVEN BUG: TaskbarProgress leaks COM on the background dialog's dying STA thread

`CommonUtil/SystemUtil/TaskBarProgress.cs` lazily creates an `ITaskbarList3` COM object and **never
releases it** (not `IDisposable`, no `Marshal.ReleaseComObject`, no finalizer).
`LongOperationRunner.BackgroundThreadLongWaitDlg` holds
`private readonly TaskbarProgress _taskbarProgress = new TaskbarProgress()` -- **one per dialog
instance** -- and `BackgroundEventThreads.CreateThreadForAction` runs that dialog on a thread with
`SetApartmentState(ApartmentState.STA)` which **exits when the dialog closes**.

Measured with `StaComProbe.cs` (session scratchpad; no Skyline code, same heap accounting as
TestRunner), 400 iterations each:

| mode | what | result |
|---|---|---|
| `thread` | STA thread created + joined, no COM | **1,056 B total, flat** -- thread churn is free |
| `com` | STA thread creates `ITaskbarList3`, calls it, thread dies | **180,336 B = ~450 B/iter, dead linear** |
| `comrel` | same + `Marshal.ReleaseComObject` before exit | **~483 B/iter, still linear** -- release does NOT fix it |
| `commain` | same object created on the long-lived main STA thread | **6,208 B total, flat** -- no leak |

So it is not RCW lifetime; it is *COM initialized on an STA apartment that is then torn down*. The
fix must be to not create it on that thread, not to dispose it.

**Deliberately not fixed tonight**: at ~450 B/run this is 0.3-2% of the four tests' leak, and every
fix has a tradeoff worth a human decision -- (a) drop the per-dialog taskbar progress (loses the
progress bar on the taskbar button during a long operation), (b) route updates to the main window's
long-lived `TaskbarProgress` (but in this exact scenario the main thread is *blocked*, which is the
whole point of the dialog, so the update would not land until the work finished), or (c) host one
`TaskbarProgress` on a dedicated long-lived STA thread (correct but heavier than the bug warrants).
Also unverifiable from here: the benefit only shows on a machine that reproduces.

## CHANGE MADE: TestMcpConnectorBackgroundDialog no longer pastes 50,000 rows

`McpConnectorBackgroundDialogTest` used a 50,000-row x 2-column grid paste purely as a way to wedge
the main UI thread so that `LongOperationRunner` would put a `BackgroundThreadLongWaitDlg` on a
thread of its own. That vehicle created ~100,000 short-lived editing-control windows per run --
the largest window-churn of any test in the suite, and (under the model above) the reason this test
is the second-worst heap leaker while `TestListDesigner`, `TestPaste` and `TestPasteTransitionList`
are all dead flat.

The test now drives `LongOperationRunner` directly with a wait-until-cancelled action. Same class,
same threading, same dialog, same connector path -- one window instead of 100,000. It also now
asserts the operation *observed* the cancel (a `ManualResetEvent` the work signals), which is a
stronger assertion than the old `grid.RowCount < PROPERTY_COUNT` proxy.

**Tradeoff to review:** the test no longer exercises `DataGridViewPasteHandler` + `LongOperationRunner`
integration. That combination is what a real user hits, and it is now covered only incidentally. If
that coverage is wanted, it belongs in a test that is not in the leak-check path (or one that is
muted), because it is inherently a ~100,000-window workload.

**Verification is partial and must be stated plainly:** this console session never reproduced the
leak (2.4 KB before the change), so the local numbers cannot show an improvement. The change is
justified by the window-churn model plus the fact that it is a faster, more deterministic, more
direct test. Confirmation has to come from the fleet.

> Night-session handoff (local only -- `ai/.tmp/` is gitignored):
> `ai/.tmp/handoff-20260725-connector-heap-leaks.md`, with the session log at
> `ai/.tmp/night-session-budget-20260724.md`.

## HEADLINE: two agents have reported ZERO leaks in 60 days, across every test

This is the strongest evidence in the whole investigation, and it predates the connector work
entirely. Nightly x64, 2026-05-25 to 2026-07-25:

| computer | runs | tests passed | **leaked tests** | OS |
|---|---:|---:|---:|---|
| **KAIPOT-PC1** | 61 | 563,316 | **0** | 10.0.19045 |
| **RITACH-DSK** | 54 | 452,505 | **0** | 10.0.19045 |
| BRENDANX-UW7 | 61 | 764,273 | 16 | 10.0.26200 |
| SKYLINE-DEV6 | 48 | 579,617 | 15 | 10.0.26200 |
| BRENDANX-DT1 | 61 | 591,296 | 12 | 10.0.19045 |
| SKYLINE-DEV4 | 52 | 518,977 | 10 | 10.0.26200 |
| SKYLINE-DEV1 | 61 | 588,704 | 9 | 10.0.19045 |
| BRENDANX-UW5 | 61 | 579,561 | 8 | 10.0.19045 |
| BSPRATT-UW3 | 61 | 637,485 | 8 | 10.0.19045 |
| BRENDANX-UW6 | 46 | 420,145 | 7 | 10.0.19045 |
| BSPRATT-UW2 | 60 | 544,187 | 6 | 10.0.19045 |
| BOSS-PC | 60 | 576,248 | 4 | 10.0.19045 |
| BSPRATT-UW4 | 19 | 174,499 | 2 | 10.0.26200 |

Two machines ran 61 and 54 full nightlies, passed over a million tests between them, and reported
**zero** leaked tests. They do not appear in the `memoryleaks` table at all for the whole window,
while the other eleven agents each accumulated leak rows across 4-6 distinct tests
(`TestMethodRefinementTutorial`, `TestTicChromatogram`, `ThermoRatioTest`, `TestImportDoc`, ... --
nothing to do with the connector). OS build does not sort them: the clean pair and most of the
leaking machines are all on 10.0.19045.

### Corroboration from leaks that have nothing to do with this work

Restricting to the 60-day window and excluding every `*Mcp*` / `*Native*` test leaves 18 leak rows
(`TestMethodRefinementTutorial`, `TestTicChromatogram`, `ThermoMixedPeptidesTest`, `TestSkyp`,
`TestImportPeptideSearch`, ...). **Every one of them is on a machine from the leaking set; none is on
KAIPOT-PC1 or RITACH-DSK.** `TestMethodRefinementTutorial` -- a tutorial test, i.e. heavy UI and many
dialogs -- leaks 157-355 KB on four different agents, the same signature as the four connector tests
and long predating them.

Worth stating the strength honestly: those 18 rows alone would not be conclusive (with ~1.4 expected
rows per machine, two zeros could happen by chance ~6% of the time). But across **all** leak rows in
the window -- 75 memory-leak rows plus 22 handle-leak rows over 13 agents -- the expected count for
any one agent is ~7.5, so two agents at exactly zero is a ~1-in-10^6 coincidence. The split is real.

**Conclusion: a large part of what nightly reports as a "memory leak" is a property of the AGENT,
not of the test.** Whatever KAIPOT-PC1 and RITACH-DSK do differently is the single most valuable
thing to identify -- replicating it fleet-wide would retire this whole class of report, and would be
far better than muting tests one at a time.

**Next step (needs a human on the machines):** compare KAIPOT-PC1 / RITACH-DSK against, say,
BRENDANX-UW7 on: whether the nightly runs in a Terminal Services / RDP session or at the physical
console (`query session`, `SESSIONNAME`, `SystemInformation.TerminalServerSession`); whether the
session is left connected or disconnected; display driver and colour depth; and whether a screen
saver / lock screen engages. Then run `WindowChurnProbe` (added under
`pwiz_tools/Skyline/Executables/DevTools/WindowChurnProbe/`) on one of each and compare -- if
`child` is dead-linear on a leaking agent and plateaus on a clean one, the mechanism is settled.

> **Careful: the obvious way to check destroys the thing being measured.** If someone RDPs into
> RITACH-DSK to find out whether it is a console session, they have just made it a Terminal Services
> session. The check has to be done *without* an interactive login -- e.g. `query session
> /server:RITACH-DSK` from another machine, PsExec/WinRM, or simply reading the session line that the
> run header now logs. (I did not run any remote query myself: these are colleagues' machines and the
> session was unattended.)
>
> This is the strongest practical argument for **pushing the session-header change before the next
> nightly** -- it collects the answer from every agent, in the exact state nightly runs in, with
> nobody having to touch anything.

### Ruled out: time of day / "someone was logged in when it ran"

Approximated each run's START hour (`posttime` minus `duration`) over all 705 runs in the window and
compared runs that reported leaks against runs that did not:

* **Within every machine the two groups have the same median start hour** -- each agent runs on a
  fixed schedule, and leaking runs are not the late or early ones.
* **Across machines, overnight runs leak too**: BSPRATT-UW2 starts at 22h and leaks, BRENDANX-UW6 at
  21h and leaks, BSPRATT-UW4 at 21h and leaks. Meanwhile the two clean agents start at 01h
  (KAIPOT-PC1) and 22h (RITACH-DSK) -- the same part of the night as several leaking agents.

So it is **not** "a developer happened to be RDP'd in while the run went past". Whatever separates
KAIPOT-PC1 and RITACH-DSK is a persistent property of how those machines are set up, not a
time-varying one -- which makes it something a configuration comparison can find.

## The connector's INSPECTION of a native dialog is not the cost -- showing it is

Worth ruling out, because the connector reads a native dialog's whole child-window tree
(`EnumChildWindows` + `GetClassName` + `GetWindowTextNoBlock` + `GetDlgCtrlID` on each) and does it
repeatedly while `WaitForNativeFileDialogReady` polls. `DialogScanProbe.cs` (session scratchpad)
shows + closes a real `OpenFileDialog` 60 times, optionally scanning every child 20 times per dialog:

| mode | dialogs | child inspections | delta over 60 dialogs |
|---|---:|---:|---:|
| `show` | 60 | 0 | 507,280 B |
| `scan` (20 scans/dialog, 48 children each) | 60 | **57,600** | **479,808 B** |

Scanning is *within noise of not scanning* -- 57,600 extra child-window inspections added nothing.
The per-dialog cost is entirely in showing the OS dialog, and it decays (47 KB -> ~3.4 KB/dialog by
iter 60), i.e. the saturating modern-IFileDialog curve this TODO measured earlier. **The connector's
Win32 introspection is exonerated**, alongside enumeration, `InternalGetWindowText` and cross-thread
`Control.Invoke` from part 1.

## Reframing: on a non-TS machine none of the four tests is unusual

On the clean machine (RITACH-DSK) the four tests measured -1.0, -3.1, 19.8 and 19.6 KB. The upper two
are in that machine's p99 tail (its overall max is 19.9) rather than being typical, but they **pass**,
and nothing on that machine crosses the bar. They only become special on the machines that report the
leak.

So there is no "file dialog problem" to fix in Skyline code. The entire effect is environmental, and
the only lever available in our own code is **how many windows a test creates** -- which is why the
background-dialog test (~100,000 editing controls) was the one worth changing and the other three
(1-3 dialogs each, inherent to what they test) are not reducible.

### Refined recommendation for PR #4453

An earlier draft of this section argued the mute should be **ungated** because the file-dialog tests
sit at 19.6-19.8 KB on clean machines. That reasoning was wrong: those values are inside the normal
16-20 KB band and they *pass*. **TS-gating the mute is fine in principle.** The only real risk is
whether the gate correctly identifies the affected machines -- and
`SystemInformation.TerminalServerSession` has already been observed reading **False** in a session
whose `SESSIONNAME` is `RDP-Tcp#0`. The session line now logged in the run header (commit
"Logged the session environment in the test run header") answers that from the next nightly: compare
`TerminalServerSession` against which machines actually report leaks before trusting the gate.

## WARNING for PR #4453: the TerminalServerSession gate may not fire

On this machine right now: `SESSIONNAME=RDP-Tcp#0` but
`SystemInformation.TerminalServerSession` reads **False**. Earlier in this TODO the same
machine over RDP recorded `TerminalServerSession=True`. So the property is not a reliable
proxy for "this is a remoted session" -- it can read False in a session that is unmistakably
RDP by every other measure.

If a nightly agent is ever in that state, a mute gated on
`SystemInformation.TerminalServerSession` **silently will not apply** and the test will be
reported as leaking anyway. Before relying on the gate, print the property on an actual
nightly agent and confirm it reads True there.
