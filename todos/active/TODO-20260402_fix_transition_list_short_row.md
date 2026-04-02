# IndexOutOfRangeException importing transition list with rows shorter than header

## Branch Information
- **Branch**: `Skyline/work/20260402_FixTransitionListShortRow`
- **Base**: `master`
- **Created**: 2026-04-02
- **Status**: In Progress
- **GitHub Issue**: [#4133](https://github.com/ProteoWizard/pwiz/issues/4133)
- **PR**: (pending)
- **Exception Fingerprint**: `6deacab65c4dc8d4`
- **Exception ID**: 74264

## Objective

Fix IndexOutOfRangeException in `GeneralRowReader.CalcTransitionInfo()` when importing
a transition list where a data row has fewer columns than the header. Add bounds
validation so the user gets a meaningful error message instead of a raw exception.

## Tasks

- [x] Investigate root cause in Import.cs CalcTransitionInfo
- [x] Write failing unit test (MassListShortRowTest in MassListIonsTest.cs)
- [ ] Add bounds validation in NextRow or CalcTransitionInfo
- [ ] Add resource string for user-friendly error message
- [ ] Verify test passes with fix
- [ ] Verify existing MassListSpecialIonsTest still passes
- [ ] Create PR

## Progress Log

### 2026-04-02 - Session Start

Starting work on this issue. Root cause fully analyzed during daily report review:

- `CalcTransitionInfo()` accesses `Fields[ProteinColumn]` and `Fields[PeptideColumn]`
  directly without bounds checking
- Other accessors (`ColumnMz`, `ColumnInt`, `ColumnString`) already have guards
- On master, `DoImport` has a `catch (Exception)` that prevents crash but produces
  raw exception text "Index was outside the bounds of the array" as the error message
- Failing test written and verified: `MassListShortRowTest` in `MassListIonsTest.cs`
  (currently stashed on master)
