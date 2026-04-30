# IndexOutOfRangeException importing transition list with rows shorter than header

## Branch Information
- **Branch**: `Skyline/work/20260402_FixTransitionListShortRow`
- **Base**: `master`
- **Created**: 2026-04-02
- **Status**: Complete
- **GitHub Issue**: [#4133](https://github.com/ProteoWizard/pwiz/issues/4133)
- **PR**: [#4134](https://github.com/ProteoWizard/pwiz/pull/4134) (merged 2026-04-03, commit `91cc2f7`)
- **Exception Fingerprint**: `6deacab65c4dc8d4`
- **Exception ID**: 74264

## Objective

Fix IndexOutOfRangeException in `GeneralRowReader.CalcTransitionInfo()` when importing
a transition list where a data row has fewer columns than the header. Add bounds
validation so the user gets a meaningful error message instead of a raw exception.

## Tasks

- [x] Investigate root cause in Import.cs CalcTransitionInfo
- [x] Write failing unit test (MassListShortRowTest in MassListIonsTest.cs)
- [x] Add IsProgrammingDefect guard to DoImport catch block
- [x] Add bounds validation in NextRow with MaxColumnIndex check
- [x] Add resource string for user-friendly error message
- [x] Add ColumnIndices.MaxColumnIndex property and GetColumnProperties() helper
- [x] Verify MassListShortRowTest passes with fix
- [x] Verify existing MassListSpecialIonsTest still passes
- [x] Create PR — merged

## Progress Log

### 2026-04-02 - Session Start

Starting work on this issue. Root cause fully analyzed during daily report review:

- `CalcTransitionInfo()` accesses `Fields[ProteinColumn]` and `Fields[PeptideColumn]`
  directly without bounds checking
- Other accessors (`ColumnMz`, `ColumnInt`, `ColumnString`) already have guards
- On master, `DoImport` has a `catch (Exception)` that prevents crash but produces
  raw exception text "Index was outside the bounds of the array" as the error message
- Failing test written and verified: `MassListShortRowTest` in `MassListIonsTest.cs`

### 2026-04-02 - Fix implemented

Two fixes applied:

1. Added `when (!ExceptionUtil.IsProgrammingDefect(exception))` to the catch block
   in `DoImport` so genuine programming errors (like IndexOutOfRangeException) are
   not silently swallowed as user-facing error messages
2. Added bounds validation in `NextRow` using new `ColumnIndices.MaxColumnIndex`
   property to check that the row has enough fields before calling `CalcTransitionInfo`.
   Returns user-friendly error "Row has N fields but M are required"

Also refactored `ColumnIndices` to extract `GetColumnProperties()` helper, DRYing up
the reflection query used by both the constructor and `MaxColumnIndex`.

Both `MassListShortRowTest` and `MassListSpecialIonsTest` pass.

### 2026-04-03 - Merged

PR #4134 merged to `master` as commit `91cc2f7479f2da7dd03cdeedaaebb9daa9b5504a`.

## Resolution

Root cause: `GeneralRowReader.CalcTransitionInfo()` indexed `Fields[]` directly
for protein and peptide columns without bounds checks, and the `catch
(Exception)` in `DoImport` swallowed the resulting `IndexOutOfRangeException`
as an opaque user-facing error.

Fix: added `when (!ExceptionUtil.IsProgrammingDefect(exception))` to the
`DoImport` catch so genuine programming defects are no longer masked, and
added bounds validation in `NextRow` using a new
`ColumnIndices.MaxColumnIndex` property, producing a user-friendly
"Row has N fields but M are required" message. Extracted
`GetColumnProperties()` helper to DRY the reflection query shared by the
constructor and `MaxColumnIndex`.
