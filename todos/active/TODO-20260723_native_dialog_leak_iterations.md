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

## LEADING HYPOTHESIS: Remote Desktop

nicksh's console session does not leak; the machine(s) that do may be driven over
**Remote Desktop**. RDP remotes the display and changes how native common dialogs render and
allocate (the codebase already notes RDP-specific native-dialog behavior — see
`NativeFileDialogTest` comments re: `CopyFromScreen` throwing on a disconnected RDP session,
regression #4229). The common file dialog's shell/preview/thumbnail handlers are a plausible
per-dialog allocator that behaves differently over a remoted display.

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
