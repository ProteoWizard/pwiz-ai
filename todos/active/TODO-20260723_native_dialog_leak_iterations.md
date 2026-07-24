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
- Session: physical console (not RDP). Did not reproduce the leak.

## Results from nicksh's machine — RDP SESSION (SAME MACHINE, leak reproduced)

**This is the decisive same-machine A/B for the RDP hypothesis.** The console-session
results above (no leak, HeapProbe plateaus by ~iter 20) and the results below were produced
on the *same* physical machine on the *same* day with the *same* `HeapProbe.cs`. The only
difference is the session type.

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

1. **RDP alone flips the result on this machine.** The console session did not leak (probe
   plateaued); over RDP the identical bare `SaveFileDialog`/`OpenFileDialog` loop climbs
   ~5 KB/iteration and never plateaus across 120 dialogs. This confirms the leak is
   environmental (remoted display), not Skyline/connector/test code — the probe contains none.
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

### Bottom line

The OpenFileDialog/SaveFileDialog inherently leaks process heap **whenever the process runs in
a Terminal Services (RDP) session — whether the client is connected OR disconnected** — on the
very machine that is clean at the physical console. The MessageBox control never leaks, so it is
the common file dialog specifically, via the TS/RDP display-driver stack, not our code. The fix
belongs in test infrastructure, gated on `SystemInformation.TerminalServerSession` (warm-up
before the leak-check window, or muting / widened thresholds for the native-file-dialog tests
under TS), not in a code hunt. Note nightly agents typically run logged-in-then-disconnected
(`Disc`), which this run reproduces directly.

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
