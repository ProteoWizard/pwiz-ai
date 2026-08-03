# TODO-20260802_panorama_download_showdialog_race.md

## Branch Information
- **Branch**: `Skyline/work/20260802_panorama_download_showdialog_race`
- **Base**: `master`
- **Created**: 2026-08-02
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4517](https://github.com/ProteoWizard/pwiz/pull/4517)

## Motivation

`TestPanoramaDownloadFile` was the single most frequent test failure on
`bt210` (Skyline master and PRs, with code coverage). Over builds #5119-#5135
(2026-07-19 to 2026-08-02, 17 builds) it failed 7 times, roughly three times
more often than the next worst test. Every failure was byte-identical:

```
Assert.Fail failed. pwiz.Skyline.Alerts.MessageDlg is already open with the message:
File does not exist. It may have been deleted on the server.
   at AbstractFunctionalTest.ShowDialog[TDlg](Action act, Int32 millis) TestFunctional.cs:281
   at PanoramaClientDownloadTest.TestMissingFile() PanoramaClientDownloadTest.cs:271
```

This reads like a flaky internet connection and is not one. The test sets
`DoActualWebAccess = false` and runs entirely on recorded HTTP playback, so no
request leaves the machine; the `404 (NotFound)` for `FileDeletedFromServer.sky.zip`
that appears in the log is the scenario under test, replayed from
`PanoramaClientDownloadTestWebData.json`.

Root cause: `PanoramaFilePicker.ClickFile` calls `ClickOpen()` internally
(`PanoramaFilePicker.cs:777`), so `TestMissingFile` started the download inside
its `RunUI` block and then called `ClickOpen` a second time through
`ShowDialog<MessageDlg>(remoteDlg.ClickOpen)`. `ShowDialog` checks
`FindOpenForm<TDlg>()` *before* invoking its action (`TestFunctional.cs:271-281`),
so whenever the first download's error dialog won the race, that precondition
tripped.

Agent correlation confirms a timing race rather than a network fault:

| Agent type | Builds | Failed |
|---|---|---|
| Ephemeral cloud (`pwiz-windows-i-*`) | 8 | 7 |
| `MacCoss TeamCity Agent 1` | 9 | 0 |

## Scope

`pwiz_tools/Skyline/TestConnected/PanoramaClientDownloadTest.cs`, `TestMissingFile`
only:

1. Move `ClickFile` out of the `RunUI` block so the download is triggered from
   inside `ShowDialog`, after its already-open precondition check has run.
2. Drop the duplicate `ClickOpen`. This also fixes a correctness bug — a passing
   run previously fired two downloads and asserted against whichever dialog
   appeared first.
3. Use the existing `AbstractFunctionalTestEx.TestMessageDlgShown(Action, string)`
   helper (`AbstractFunctionalTestEx.cs:520`) rather than hand-rolling
   show/validate/dismiss. Matches `TestMessageDlgShownContaining` already used at
   line 208 of the same file.

## Verification

- `TestPanoramaDownloadFile` x20 - passed
- CodeInspection - passed
- ReSharper full-solution inspection - 0 errors, 0 warnings

This developer machine does not reproduce the race: the unfixed baseline also
passed 20/20, matching `MacCoss TeamCity Agent 1`. Local green is a
non-regression check only. Real verification requires a build on an ephemeral
cloud agent, where the baseline failed 7 of 8 times.

## Follow-ups (not in this PR)

Found by `/code-review max` on this branch; filed separately so this stays a
one-test fix:

- `PanoramaFilePicker.ClickFile` is named like a selection helper but closes the
  modal dialog. Four other call sites already misread it. Renaming to
  `ClickFileAndOpen` would remove the trap everywhere at once.
- `TestVerifyJson` (`TestFunctional/TestPanoramaClient.cs:252`) has the same
  hazard - three `ClickFile` calls in one `RunUI` against a modal picker.
- `TestPanoramaDownloadFileWeb` returns silently and reports PASSED when
  `AllowInternetAccess` is false.
- `GetPanoramaServerUri` discards its `testFolder` argument in the live branch
  (`PanoramaClientDownloadTest.cs:128`).
- `PanoramaFilePicker.AddFiles` swallows all but three exception types
  (`PanoramaFilePicker.cs:424`), so a stale recording surfaces as "Unable to
  click file" instead of naming the URL.
- `PanoramaFilePicker.ClickOpen` now has no external callers and could be
  private. Deliberately left public - narrowing shared-library surface is out of
  scope here.
