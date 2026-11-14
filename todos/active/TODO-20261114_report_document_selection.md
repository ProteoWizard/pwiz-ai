# AI Connector cannot select reports into the document (Reports list rejects selection)

## Branch Information
- **Branch**: `Skyline/work/20261114_report_document_selection`
- **Base**: `master`
- **Created**: 2026-11-14
- **Status**: In Progress
- **GitHub Issue**: [#5035](https://github.com/ProteoWizard/pwiz/issues/5035)
- **Module**: `skyline`
- **PR**: (pending)
- **Checkout**: `I:\git_i\sky_reportsettingslist`

## Objective

`skyline_get_settings_list_selected_items("Reports")` and
`skyline_select_settings_list_items("Reports", ...)` throw "Selection is not
supported for settings list: Reports" because `PersistedViews` does not implement
`ISettingsListDocumentSelection`. An LLM therefore cannot save a report with the
document (Settings > Document Settings > Reports, i.e. `DataSettings.ViewSpecList`)
or ask which reports a document carries.

## Tasks

- [ ] Give Reports document selection: get = names in `DataSettings.ViewSpecList`;
      set = resolve names against `PersistedViews` main group, not-found error for
      unknown names, `ChangeDataSettings(ChangeViewSpecList(...))` (mirror
      DocumentSettingsDlg)
- [ ] Either implement `ISettingsListDocumentSelection` on `PersistedViews` or
      adapt in `JsonToolServer.ResolveDocumentSelector`
- [ ] Extend JsonToolServerSettingsTest: add report, select into document, get
      selected, save/reopen, select empty removes from doc but keeps in user list
- [ ] Follow-up: description sentence on `skyline_select_settings_list_items` /
      `skyline_add_report` that selecting under "Reports" saves it with the .sky

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: TestFunctional
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## Progress Log

### 2026-11-14 - Session Start

Starting work on this issue. Filed by Brendan (team developer), so no credit line.
