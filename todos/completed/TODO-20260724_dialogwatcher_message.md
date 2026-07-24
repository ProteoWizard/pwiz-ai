# TODO-20260724_dialogwatcher_message.md

## Branch Information
- **Branch**: `Skyline/work/20260724_dialogwatcher_message`
- **Worktree**: `sky_fixes`
- **Base**: `master`
- **Created**: 2026-07-24
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4454](https://github.com/ProteoWizard/pwiz/pull/4454)

## Problem

`TestJsonToolServer` fails intermittently in nightly — 3 failures on 2026-07-23 (BRENDANX-DT1,
BRENDANX-UW5, SKYLINE-DEV1), all with the same stack trace:

```
System.InvalidOperationException
   at pwiz.Skyline.ToolsUI.DialogWatcher.EnsureCompleted(ActionResult actionResult)
   at pwiz.Skyline.ToolsUI.DialogWatcher.CallFunction[T](...)
   at pwiz.Skyline.ToolsUI.JsonToolServer.RunCommandImpl(...)
   at pwiz.SkylineTestFunctional.JsonToolServerTest.TestDocumentOperations(...) line 1843
```

Line 1843 is `server.RunCommand(CommandArgs.ARG_NEW + newPath)`. There is exactly ONE path in
`PerformActionAndWait` that returns `Completed = false`: an unexpected interactive modal appeared
(`m.IsModal && !m.IsTransient && !startWindows.Contains(m.Hwnd)`).

**The exception carried NO message at all**, which makes the failure undiagnosable: there is no
way to tell from the nightly stack trace WHICH dialog got in the way.

## Root cause of the missing message

`EnsureCompleted` threw only `actionResult.Message` and discarded `actionResult.FormId`:

```csharp
throw new InvalidOperationException(actionResult.Message);
```

`Message` is the modal's `DetailedMessage`, which for a managed form is
`(Form as CommonFormEx)?.DetailedMessage ?? Form.Text` — empty when the form has neither a
composed message nor a caption, or when a window is caught mid-teardown. `FormId`
("TypeName:Title") always identifies the window, and it was being thrown away.

## Change

`EnsureCompleted` now leads with the FormId and appends the message only when non-empty.

**Diagnostic only** — this does NOT fix the underlying race. It makes the next nightly
occurrence name the offending dialog, which should identify the root cause in one shot.

## Investigation notes (for whoever picks up the underlying race)

- **Not reproducible locally**: 0 failures in 11 runs on a physical console session (~35 s/run).
- **A theory tested and DISCARDED**: `StandaloneWindow.NewStandaloneWindow`'s `default:` branch
  falls back to `NativeDialog.MakeNativeDialog` when `Control.FromHandle` returns null, and that
  wrapper reports `IsTransient => false`. Since `RunCommandImpl` always runs under a
  `LongWaitDlg` (which IS transient), a teardown-window misclassification would produce exactly
  this symptom. Instrumented that branch and the non-completion decision point: **zero hits** in
  4 runs, and zero non-completions in passing runs. Theory not supported.
- Note `NativeDialog.GetOpenDialogs` already skips windows it cannot classify ("a window we
  cannot classify is one we cannot drive"), while `GetModalDialogs` does not — worth revisiting
  if the FormId in a future failure points at a `Dialog:` wrapper.
- **Better repro environment**: nightly agents run under RDP/Terminal Services, which we proved
  (PR #4453 investigation) changes native-window behavior. An RDP session is a more promising
  place to loop this test than a physical console.

## Files Changed

- `pwiz_tools/Skyline/ToolsUI/DialogWatcher.cs`

## Resolution

### 2026-07-24 — Merged
PR [#4454](https://github.com/ProteoWizard/pwiz/pull/4454) squash-merged to master as
`907ab0e59038723bb3d2e01d461b5253390909b6`.

`EnsureCompleted` now throws the dialog's own message when it has one, and falls back to the
FormId ("TypeName:Title") only when the message is empty — the undiagnosable case that motivated
the change. A TeamCity failure caught during review (`TestAlertWatch` pins that a native box
surfaces its BODY, never its caption) was fixed by not prefixing the message when one exists.

**Diagnostic only** — the underlying intermittent `TestJsonToolServer` race is NOT fixed. The
next nightly occurrence will now name the offending dialog, which should identify the root cause.
Follow-up lives in this file's investigation notes; watch for a `Dialog:...` FormId (would confirm
the discarded `MakeNativeDialog` theory).
