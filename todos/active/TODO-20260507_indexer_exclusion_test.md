# TODO-20260507_indexer_exclusion_test.md

## Branch Information
- **Branch**: `Skyline/work/20260507_indexer_exclusion_test`
- **Base**: `master`
- **Created**: 2026-05-07
- **Status**: In Progress
- **PR**: (pending)

## Motivation

`ConsoleSetLibraryTest` hung overnight on BSPRATT-UW4 (run `BSPRATT-UW4_2026-05-06_21-00-45`)
in iteration 1.93 (ja locale), polling forever on `Settings.PeptideSettings.Libraries`. The
same test passed earlier the same night on the same machine and on every other machine in
the nightly fleet. Diagnosis: transient external interference with the .blib load — almost
certainly a background scanner/indexer holding a brief read lock at the wrong moment. Defender
is verified at startup via the EICAR-based `AntivirusExclusionTest`, but (a) it only covered
the Skyline runtime build output directory, not the persistent test data download cache where
the .blib files actually live, and (b) nothing checked the other obvious culprits beyond AV.

## Scope

Extend the existing `AntivirusExclusionTest` (which has special run-first-once logic in
TestRunner) on two axes:

1. **More directories checked**: previously only `.` (cwd, i.e. the Skyline runtime build
   output). Now also the test data download subfolders `{DownloadsPath}\Tutorials` and
   `{DownloadsPath}\Perftests` if they exist.
2. **More check types**, applied to each directory:

- **Cloud-storage placeholders** — `File.GetAttributes` against
  `Offline | ReparsePoint | RecallOnOpen (0x40000) | RecallOnDataAccess (0x400000)`. Generic;
  catches OneDrive Files-on-Demand, Dropbox Smart Sync, Google Drive File Stream, Box Drive.
- **OneDrive sync root** — walk `HKCU:\Software\Microsoft\OneDrive\Accounts\*\UserFolder` and
  fail if the directory is under any of them.
- **Windows Search index** — `ISearchCrawlScopeManager::IncludedInCrawlScope` via inline
  `[ComImport]` declarations, GUIDs and vtable order verified against Windows SDK IDLs
  (SearchAdmin / SearchCatalog / SearchCrawlScopeManager).

`{DownloadsPath}` is `PathEx.GetDownloadsPath()` — the `SKYLINE_DOWNLOAD_PATH` env var if set,
otherwise the user's actual Downloads folder. We deliberately do NOT check that root; when
`SKYLINE_DOWNLOAD_PATH` is unset, it's the user's Downloads folder and reasonable to leave
un-excluded.

## Verification

Each new check must demonstrably fail when its predicate is true. Verified via
`ai/.tmp/Verify-AntivirusExclusionTest.ps1` (one-shot harness, not committed):
- Probe 1 (cloud placeholder): `attrib +O` build dir → expect failure → revert.
- Probe 2 (OneDrive): fake `HKCU:\...\OneDrive\Accounts\__Probe\UserFolder` → expect failure → remove.
- Probe 3 (Search index): manually tick build dir in Indexing Options → expect failure → untick.

Run the test on a clean machine and confirm it passes (no false positives).

## Out of scope

- Fix for `DriftTimePredictorTutorialTest.cs` putting downloads under `C:\Skyline T&est ^Data\Data-drift\`
  rather than `Perftests\` — flagged separately, deferred.
- A WaitForComplete timeout in the library-load polling loop that hung — separate follow-up.
- An *activity*-style probe (vs. config-style) for third-party AV / backup / kernel filter
  drivers — config-querying covers ~90% of realistic culprits; the long tail can be added
  later if needed.
