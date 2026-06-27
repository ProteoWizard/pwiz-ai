# Add ability to create a new folder to the waters_connect method dialog

## Branch Information
- **Branch**: `Skyline/work/20260625_watersConnectNewFolder` (pwiz1)
- **Base**: `master`
- **Created**: 2026-06-25
- **Status**: In Progress
- **GitHub Issue**: [#4329](https://github.com/ProteoWizard/pwiz/issues/4329)
- **PR**: (pending)
- **Requester/Reporter**: Waters feature request (INFMTD-312); Stephen (Waters) supplied the Folders API details. Confirm credit line at PR time (vendor request, no support-thread rowId).

## Objective

Let users create a new waters_connect folder directly from the Skyline method export
dialog, so they can organize the many methods used in method development without leaving
Skyline. Uses the waters_connect Folders API:

```
PUT /waters_connect/v2.0/folders/{parentFolderGuid}
{ "Name": "...", "Description": "..." }
```

Must catch permission errors (e.g. 403 when the user lacks folder-create permission).

## Design (agreed with developer)

- **Reusable control**: add a "New Folder" button to the parent `BaseFileDialogNE`,
  `Visible = false` by default. Its click handler calls a `protected virtual void
  CreateNewFolder()` (base no-op). See [[feedback-basefiledialogne-shared-controls]].
- **Save dialog**: `WatersConnectSaveMethodFileDialog` makes the button visible and
  overrides `CreateNewFolder()` with the waters_connect behavior (prompt for name ->
  `WatersConnectSession.CreateFolder(parentGuid, name, description)` -> refresh list ->
  navigate into the new folder).
- **Enable rule**: button enabled only when the current folder is writable
  (`WatersConnectFolderObject.CanWrite`, the same check `SetButtonQue()` uses) and not at
  the account root.
- **API**: add `CreateFolder(parentFolderGuid, name, description)` to `WatersConnectSession`
  (PUT, JSON body), reuse `EnsureSuccess`/`RemoteServerException`; invalidate the cached
  folder list so the new folder resolves on refresh.
- **Errors**: 403 -> friendly "no permission to create folders here"; name conflict ->
  "folder already exists"; otherwise the existing remote-error path.

## Tasks

- [x] `WatersConnectSession.CreateFolder(...)` API (PUT, returns HttpStatusCode + cache refresh via RetryFetch)
- [x] `BaseFileDialogNE`: hidden New Folder button + inline-rename (LabelEdit/AfterLabelEdit) + `protected virtual CreateNewFolder(string)` + `RefreshCurrentDirectory`
- [x] `WatersConnectSaveMethodFileDialog`: show button, enable on writable folder, override `CreateNewFolder`, error switch (403/409/generic), description "Created by {user} using Skyline"
- [x] Resource strings: CommonFileDialogResources (button text, placeholder) + FileUIResources (6 strings) + designers
- [x] Functional test: `WatersConnectMethodExportTest.VerifyNewFolder` (mock PUT handler success + Forbidden); test seam runs create synchronously (no LongWaitDlg) to avoid PerformWork-via-RunUI deadlock
- [x] Build green + test passing (TestWatersConnectExportMethodDlg, 8.5s)

## Follow-ups (after this test is green)

- Add a delayed mock-handler variant so a test can exercise the LongWaitDlg progress indicator
  during folder creation (developer suggestion 2026-06-25).
- Inline-rename UI itself (BeginEdit/AfterLabelEdit) is not driven by the functional harness; the
  test drives the CreateNewFolder seam directly. See [[project_functional_tests_no_gui]].

## Regression Test

- **Test name**: `TestWatersConnectExportMethodDlg` (`VerifyNewFolder`)
- **Test project**: TestFunctional
- **Fails on master**: yes - red->green verified for the self-review HIGH (post-create refresh was a
  no-op, so the new folder never appeared). Test times out "new folder did not appear" without the fix.
- **Passes on fix**: yes - `ClearResultsFor` + refetch makes the stateful mock's new folder appear.

## Progress Log

### 2026-06-25 - Session Start

Scoped the feature with the code map (BaseFileDialogNE parent, Save/Select children,
WatersConnectSession API, MockHttpMessageHandler test seam). Agreed design above. Branch
created off master; starting with the functional test.

### 2026-06-26 - Implemented, PR #4331

Implemented + tested. PR https://github.com/ProteoWizard/pwiz/pull/4331 (Requested by Stephen Jepson).
Manual real-API check: request correct, 403 handled; create-success blocked on account permission.
Cosmetics: AddFolder.png icon, More Info detail, error icon. Copilot review addressed (AssertEx.Contains;
network exception handling in CreateFolder) + resolved. Self-review found a HIGH: post-create refresh
was a no-op (RetryFetch doesn't invalidate) - fixed with ClearResultsFor + refetch and locked with a
red->green regression test (stateful mock asserts the folder appears). Also hardened cancel/inline-edit
placeholder (LOWs). 4 commits pushed; deferred LOW addressed too. Pending: TeamCity green, human review.
