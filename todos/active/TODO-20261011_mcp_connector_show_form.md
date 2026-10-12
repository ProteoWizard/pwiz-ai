# TODO-20261011_mcp_connector_show_form.md

## Branch Information
- **Branch**: `Skyline/work/20261011_mcp_connector_show_form`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-11 (SKYLINE-DEV6, checkout `C:\proj\pwiz`)
- **PR**: [#4824](https://github.com/ProteoWizard/pwiz/pull/4824) (opened 2026-10-11; commits 6a6f7019e8, 0730212d71)
- **Status**: review fixes applied, local tests green; awaiting TeamCity + human review. Wanted merged before
  SKYLINE-DEV6's next nightly run.

## Problem

Intermittent nightly failures across the MCP connector tests (TestClickCheckedListMcpConnector,
TestSetItemMcpConnector, TestSetFormValueMcpConnector, TestGetControlsMcpConnector,
TestClipboardMcpConnector; SKYLINE-DEV6 and BRENDANX-UW6):
`Expected a form of type DefineAnnotationDlg to be open, but it was not. Open forms: EditListDlg ...`
from `McpConnectorTest.GetOpenFormId` right after `ShowDialog<DefineAnnotationDlg>`.

## Root cause (observed, not inferred)

`ShowDialog<T>` returns when the form is in `Application.OpenForms` and `Created`, which is before
Windows shows it (OnLoad runs in between). The connector lists only visible windows
(`StandaloneWindow.GetTopLevelWindowHandles` filters on `IsWindowVisible`). Logged at ShowDialog's return:
`Created=True IsWindowVisible=False`. Natural rate with the real DefineAnnotationDlg, 200-show loops in
one session: 1, 2, 2, 0 misses (~0.6% per show) - Debug, SKYLINE-DEV6.

## Fix

- `McpConnectorTest.ShowMcpConnectorForm<TForm>(Action act, out string formId)`: ShowDialog, then
  `WaitForMcpConnectorForm<TForm>()`. Replaces every show-then-look-up pair (13 sites, 11 tests), both
  `ShowDialog` + `GetOpenFormId` and `RunUI(show)` + `WaitForOpenForm` + `GetOpenFormId`.
- PopupPickList (opened by a connector action) uses the existing `WaitForMcpConnectorForm` instead.
- Left alone: GetOpenFormId for long-open forms (SkylineWindow, SequenceTreeForm, two DocumentGridForm
  lookups after ChooseView - the grid's id carries its title, so it is taken after the view change).

## Verifier

`TestMcpConnectorShowForm`: a test-only `SlowLoadingForm` sleeps 300 ms in OnLoad (> the 100 ms
WaitForOpenForm poll). Guard asserts ShowDialog returns while the window is invisible (50/50 loop),
then `ShowMcpConnectorForm` must return a resolvable id. Old pattern failed 3/3; negative control
(helper without the wait) fails. Registered as `SlowLoadingForm,*` in TestRunnerFormLookup.csv (no
L10N test needed - Brendan) and on CodeInspection's test-only exclusion list next to
BackgroundEventThreadsTestForm.

## Code review (/code-review max, 9 findings)
Fixed: OnLoad gated on an event (guard no longer races the 100 ms poll; hold now 300 ms only in the
helper check), id looked up by form.GetType().Name, WaitForMcpConnectorForm falls back to GetOpenFormId's
message on timeout, reverted docked AuditLogForm/DocumentGridForm sites (listed by DockState; converting
risked a stale grid-title id), AssertEx, docs scoped to top-level dialogs. Deferred: ShowDialog-level
hardening (UI round trip at the end of ShowDialog; ~2,000 call sites).

## Side findings
- `ai/scripts/Skyline/Run-Tests.ps1` names the log after the comma-joined test list; with 13 tests
  TestRunner died at startup (0xE0434352). Batches of 2-3 worked. Not fixed yet.
- TestRunner `loop=N` stops after the first failure, so a control loop gives one sample.
