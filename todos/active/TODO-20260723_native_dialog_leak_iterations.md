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

## Results from <other machine>

(To be filled in by Claude on the leaking machine — see "FOR THE OTHER MACHINE" above.)
