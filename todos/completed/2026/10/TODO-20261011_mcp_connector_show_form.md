# TODO-20261011_mcp_connector_show_form.md

## Branch Information
- **Branch**: `Skyline/work/20261011_mcp_connector_show_form`
- **Base**: `master`
- **Module**: `skyline`
- **Created**: 2026-10-11 (SKYLINE-DEV6, checkout `C:\proj\pwiz`)
- **PR**: [#4824](https://github.com/ProteoWizard/pwiz/pull/4824) (merged 2026-10-11, as 8efe7e08eb)
- **Status**: Completed

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
  `WaitForMcpConnectorForm` on the shown form's own type. Replaces every ShowDialog + GetOpenFormId pair
  for a top-level dialog (11 sites, 10 tests); the docked AuditLogForm/DocumentGridForm sites stay as
  they were (see Code review).
- PopupPickList (opened by a connector action) uses the existing `WaitForMcpConnectorForm` instead.
- Left alone: GetOpenFormId for long-open forms (SkylineWindow, SequenceTreeForm, two DocumentGridForm
  lookups after ChooseView - the grid's id carries its title, so it is taken after the view change).

## Verifier

`TestMcpConnectorShowForm`: a test-only `SlowLoadingForm` holds OnLoad on an event the test releases
after asserting (a 300 ms timed hold only for the helper check). Guard asserts ShowDialog returns while
the window is invisible (50/50 loop),
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

## Progress Log

### 2026-10-11 - Merged

PR #4824 merged as commit 8efe7e08eb (admin merge at Brendan's request: all 17 checks green, no approving
review yet) so SKYLINE-DEV6's next nightly run picks it up. Shipped McpConnectorTest.ShowMcpConnectorForm,
11 call sites in 10 MCP connector tests converted, WaitForMcpConnectorForm failing with the connector's
form list, and TestMcpConnectorShowForm. Deferred: ShowDialog-level hardening, the Run-Tests.ps1 long
test-list log name crash, and DiaToSrmTutorialTest's GetOpenFormId after connector actions (out of scope
in review, unverified).
