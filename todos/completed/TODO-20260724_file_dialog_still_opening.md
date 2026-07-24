# TODO-20260724_file_dialog_still_opening.md

## Branch Information
- **Branch**: `Skyline/work/20260724_file_dialog_still_opening`
- **Worktree**: `sky_fixes`
- **Base**: `master`
- **Created**: 2026-07-24
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4456](https://github.com/ProteoWizard/pwiz/pull/4456)

## Problem

`TestNativeMessageBox` failed in nightly on BSPRATT-UW2 (2026-07-24 run):

```
System.InvalidOperationException: The file dialog is still opening. Wait a moment and try again.
   at NativeFileDialog.get_FileNameTextBox()  NativeFileDialog.cs:119
   at NativeFileDialog.EnterPath(String path) NativeFileDialog.cs:82
   at NativeDialog.SetValue(String controlId, String value) NativeDialog.cs:290
   at NativeMessageBoxTest.DoTest()          NativeMessageBoxTest.cs:83
```

A native dialog becomes discoverable — its window exists, `GetOpenForms` reports it, and it
classifies as a file dialog — a moment BEFORE the shell has finished showing and populating it.
The test took the dialog id and immediately set the file name, before the file-name Edit existed.

## Where the fix belongs

`NativeFileDialog.FileNameTextBox` deliberately does NOT block polling for the field. Its own
doc says so:

> "Rather than BLOCK here polling for the field, this throws an instruction the caller acts on,
> so the wait lives with the DRIVER, not inside the primitive both drivers share: the model waits
> and re-issues the call, and a test driving the dialog waits on its own state. A single tool call
> never sits inside a 30-second sleep."

So adding a retry inside `SetValue` would violate a deliberate contract. The wait belongs in the
test driver — this change adds it there.

## Two discovery patterns, both racy

| pattern | sites | wait before this change |
|---------|-------|-------------------------|
| `WaitForNativeFileDialog()` | 4 | waited for the WINDOW only |
| `ResolveModal(ClickMainMenuItem(...))` | 4 | **none at all** |

The failing site is the second kind — the id comes straight from the `ActionResult`, which names
the dialog the instant its window is reported.

## Change

- `NativeFileDialog.FILE_NAME_FIELD` — extracted the `"File name"` label to a public const so the
  product code and the test-side wait cannot drift. It is OUR label, not the shell's, so it is the
  same in every UI language (the failing run was French).
- `McpConnectorTest.WaitForNativeFileDialogReady(formId)` — waits until the file-name box appears
  in `GetControls` under that label, which is exactly the field `EnterPath` needs and is listed
  only once visible.
- `WaitForNativeFileDialog()` now folds that wait in, so all 4 sites of the first pattern are
  fixed with no call-site change.
- `McpConnectorTest.ResolveNativeFileDialog(actionResult)` — the `ResolveModal` counterpart for a
  file dialog (resolve + wait). Converted the 4 sites of the second pattern
  (`DiaToSrmTutorialTest` x3, `DiaFragPipeTutorialTest` x1), plus an explicit
  `WaitForNativeFileDialogReady` in `NativeMessageBoxTest` step 2 where the id is used for other
  assertions first.

Care taken: only the 4 `ResolveModal` calls whose id is then used with `SetFormValue(..., "FileName", ...)`
were converted. The other 7 `ResolveModal` calls in those files open MANAGED dialogs, which have no
file-name field and would wait forever.

## Verification

- Full solution builds with no errors or warnings.
- `TestNativeMessageBox`, `TestNativeFileDialog`, `TestPrmMcpConnector`, `TestJsonToolServer`,
  `TestAlertWatch` pass over 2 languages x 2 iterations. A wrong readiness label would hang the
  wait until timeout, so passing also confirms the predicate matches.
- **Caveat**: the original race did not reproduce locally (it failed on a nightly/RDP machine), so
  local passes cannot prove the race is gone. The fix makes the precondition explicit rather than
  relying on timing; nightly is the real confirmation.

## Files Changed

- `pwiz_tools/Skyline/ToolsUI/NativeFileDialog.cs`
- `pwiz_tools/Skyline/TestUtil/McpConnectorTest.cs`
- `pwiz_tools/Skyline/TestFunctional/NativeMessageBoxTest.cs`
- `pwiz_tools/Skyline/TestPerf/DiaToSrmTutorialTest.cs`
- `pwiz_tools/Skyline/TestPerf/DiaFragPipeTutorialTest.cs`

## Resolution

### 2026-07-24 — Merged
PR [#4456](https://github.com/ProteoWizard/pwiz/pull/4456) squash-merged to master as
`96faedda560150bc53037559b9913a3346c60093`.

The test drivers now wait for the native file dialog's file-name field to appear before typing:
`WaitForNativeFileDialog()` folds the wait in, and `ResolveNativeFileDialog(actionResult)` covers
the 4 sites that took the id straight from an ActionResult with no wait. The `"File name"` label
is a shared const (`NativeFileDialog.FILE_NAME_FIELD`) so product and test code cannot drift.

**Caveat**: the original race only reproduced on a nightly/RDP machine, so local passes cannot
prove it gone — the fix makes the precondition explicit rather than timing-dependent. Confirm on
the 2026-07-25 nightly (BSPRATT-UW2 was the machine that failed).
