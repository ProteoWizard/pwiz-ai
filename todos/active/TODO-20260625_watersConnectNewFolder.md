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

### 2026-07-05 - Added Refresh button (follow-up feature, requested by Stephen)

Second user-requested feature on the same dialog: a Refresh button to re-pull the file/folder listing
from the server. Mirrors the New Folder pattern:
- `BaseFileDialogNE`: hidden-by-default `refreshButton` on `navToolStrip` (Designer + field), text/tooltip
  from new `CommonFileDialogResources.BaseFileDialogNE_Refresh`, `refreshButton_Click` -> new
  `protected virtual RefreshFromServer()` (base = `RefreshCurrentDirectory()`).
- `WatersConnectSaveMethodFileDialog`: shows the button with a Refresh icon; overrides `RefreshFromServer`
  to invalidate the current dir's cache then repopulate. Test seam `RefreshForTest()` + `RefreshButtonVisible`.
- `WatersConnectSession.RefreshContents(url)`: `ClearResultsFor` the current dir's cached responses
  (root folders / sample sets / injections - types verified against `AsyncFetchContents`), so the
  repopulate re-fetches. Needed because `RefreshCurrentDirectory()`/`RetryFetch` are no-ops on cached
  success (same gotcha the New Folder refresh hit).
- Icon: added `Refresh.png` to Skyline `Resources/` + `Resources.resx`/`.Designer.cs` (`Refresh` bitmap).
- Test: `WatersConnectMethodExportTest.VerifyRefresh` - stateful mock adds a server-side folder after the
  listing is cached; asserts it appears only after Refresh. Red->green verified (neutered the cache-clear
  -> "did not appear after refresh" timeout). Build green, TestWatersConnectExportMethodDlg passes,
  CodeInspection test passes.

Committed `c1a09636f1` (feature) then ran `/pw-self-review` (fresh-context agent) on that commit: all findings
LOW. Applied the one worth fixing - RefreshContents now resolves the sample-set/injection child URLs BEFORE
clearing the root cache (a path-only URL could otherwise skip its own invalidation; safe today but latent) -
in `c1814f4f0a`. Dismissed: satellite-resx omission (consistent with New Folder strings), double-click double
fetch (harmless). Deferred (optional): a sample_set->injections refresh test (needs a stateful mock methods
handler). Clean build + CodeInspection + TestWatersConnectExportMethodDlg all green; both commits pushed.
PENDING: TeamCity green on c1814f4f0a; then human review.

### 2026-08-16 - Master merge + refresh-button design merge with Matt's PR #4282

Brought the branch up to date with master: clean auto-merge (GitHub's
"conflict" was staleness; branch was BEHIND/MERGEABLE), verified with
build + TestWatersConnectExportMethodDlg + CodeInspection.

Then reconciled the duplicate refresh-button implementations with
Matt's unmerged PR #4282 (commit 039979bd07) per his email agreement
(D:\...\Downloads\"[EXT] Re_ Issue list.eml", yellow highlights):
- Button now ALWAYS visible in BaseFileDialogNE (his) - removed our
  Visible=false opt-in and the subclass show/icon lines.
- Icon: his form-local refresh.png embedded in BaseFileDialogNE.resx
  (+ ApplyResources in Designer); removed our Skyline
  Resources/Refresh.png + Resources.resx/Designer entry.
- RefreshCurrentDirectory: public (his signature), plain re-read with
  _abortPopulateList=true.
- Base RefreshFromServer: his generic invalidation (RemoteUrl ->
  RemoteSession=null) as the default; WatersConnect override keeps our
  surgical RefreshContents (session/auth stay alive).
- Kept our shared CommonFileDialogResources strings and the
  VerifyRefresh functional test (still valid: button visible, seam
  drives the override).
This converges the branches so whichever PR merges first, the other's
conflict resolution is mechanical (his BaseFileDialogNE hunks become
redundant).

### 2026-06-30 - Fixed code-inspection failure after master merge

TeamCity ReSharper build #18696 failed with 2 LocalizableElement warnings: the 'NewTestFolder'
literal in VerifyNewFolder was compared against ListViewItem.Text ([Localizable(true)]) at lines
278/281. Hoisted the name into a local `const string newFolderName` and reused it across all six
call sites - removes the literal from the localizable position and de-duplicates. Verified locally:
build green, TestWatersConnectExportMethodDlg passes (10.5s), QuickInspection clean (0/0). Merged
origin master (GitHub Update-branch) into local, rebased the fix on top, pushed (de4fa4e839).
