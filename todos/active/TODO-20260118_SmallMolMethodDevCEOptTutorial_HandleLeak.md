# Handle Leak in TestSmallMolMethodDevCEOptTutorial

## Branch Information
- **Branch**: `Skyline/work/20260118_SmallMolMethodDevCEOptTutorial_HandleLeak`
- **Base**: `master`
- **Created**: 2026-01-18
- **GitHub Issue**: https://github.com/ProteoWizard/pwiz/issues/3833

## Objective

Fix the reproducible handle leak of approximately 15 User+GDI handles per pass in TestSmallMolMethodDevCEOptTutorial. This is a chronic issue affecting 9+ machines in nightly testing (222 handle leak reports historically).

## Tasks

- [ ] Bisect DoTest() to find which dialog/operation leaks handles
- [ ] Use handle reporting tools to identify handle types
- [ ] Fix undisposed dialogs or forms causing the leak
- [ ] Verify fix with multi-pass testing

## Progress Log

### 2026-01-18 - Session Start

Starting work on this issue. The test is in `pwiz_tools/Skyline/TestTutorial/SmallMolMethodDevCEOptTutorial.cs` (600 lines).

Dialogs/forms used by the test that may be leaking:
- TransitionSettingsUI dialog
- ExportMethodDlg (multiple times)
- ImportResultsDlg with OpenDataSourceDialog
- ManageResultsDlg with RenameResultDlg
- DocumentGridForm
- PeptideSettingsUI
- CalibrationForm
- EditCEDlg
- SchedulingOptionsDlg

Next step: Read the test code to understand the structure and identify potential leak sources.
