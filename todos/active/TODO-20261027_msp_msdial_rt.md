# MSP reader reads MS-DIAL RETENTIONTIME as seconds and ignores FragHub RT and PRECURSORTYPE

## Branch Information
- **Branch**: `Skyline/work/20261027_msp_msdial_rt`
- **Checkout**: `C:\Dev\BugFix`
- **Base**: `master`
- **Created**: 2026-10-27
- **Status**: In Progress
- **Module**: `skyline`
- **Support thread**: https://skyline.ms/home/support/announcements-thread.view?rowId=76102 (Rafael)
- **PR**: [#4926](https://github.com/ProteoWizard/pwiz/pull/4926)

## Objective

Rafael's MS-DIAL and FragHub MSP examples:
- MS-DIAL `RETENTIONTIME: 6.5147` is in minutes, but Skyline read any bare `RetentionTime:` as seconds.
- FragHub writes `RT: <minutes>` (or `RT: NOT FOUND`), which Skyline ignored.
- MS-DIAL / FragHub `PRECURSORTYPE:` (NIST spells it `Precursor_type:`) was not read as the adduct.

## Tasks
- [x] Read bare `RetentionTime:` as minutes when the entry has MS-DIAL cues (PRECURSORTYPE / INSTRUMENTTYPE / ONTOLOGY)
- [x] Read FragHub `RT:` as minutes
- [x] Add `RetentionTimeSecs:` so either unit can be stated explicitly
- [x] Read `PRECURSORTYPE:` as the adduct
- [x] Async warning, once per assumed unit per file, with line number and entry name, when units are guessed
- [x] Extend NistLoadLibrary (LibraryLoadTest.cs) with MS-DIAL, FragHub and RetentionTimeSecs entries and warning assertions
- [x] /code-review medium (fixed stale-units flag and cache version; rest dropped), PR #4926

## Notes
- matchms "riken" exports use the MS-DIAL field names with RETENTIONTIME in seconds; that is why the guess warns.
- `C6:OH b` in TEXT_LIB_NO_ADDUCT has NIST-style `RetentionTime: 1.52616` that looks like minutes but is read as seconds (unchanged).
- Out of scope: Rafael's request to copy library RT into Explicit Retention Time.
