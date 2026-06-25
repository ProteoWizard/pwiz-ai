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

- [ ] Regression/functional test first: extend `WatersConnectMethodExportTest` with a mock
      PUT-folders handler (success + 403) and assert the new folder appears + payload is correct
- [ ] `BaseFileDialogNE`: hidden New Folder button + `protected virtual CreateNewFolder()`
- [ ] `WatersConnectSaveMethodFileDialog`: show button, override `CreateNewFolder()`, enable logic
- [ ] `WatersConnectSession.CreateFolder(...)` API call + cache invalidation
- [ ] Folder-name prompt UI (reuse an existing simple text-input dialog)
- [ ] Error handling (403 / name conflict / generic)
- [ ] New resource strings in the appropriate .resx (+ .designer.cs)

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional (extend `WatersConnectMethodExportTest`)
- **Fails on master**: (to verify - button/flow does not exist yet)
- **Passes on fix**: (to verify)

## Progress Log

### 2026-06-25 - Session Start

Scoped the feature with the code map (BaseFileDialogNE parent, Save/Select children,
WatersConnectSession API, MockHttpMessageHandler test seam). Agreed design above. Branch
created off master; starting with the functional test.
