# TODO-20260507_indexer_exclusion_test.md

## Branch Information
- **Branch**: `Skyline/work/20260507_indexer_exclusion_test`
- **Base**: `master`
- **Created**: 2026-05-07
- **Status**: Completed (abandoned — see Resolution)
- **GitHub Issue**: [#4190](https://github.com/ProteoWizard/pwiz/issues/4190) (still OPEN)
- **PR**: [#4191](https://github.com/ProteoWizard/pwiz/pull/4191) (**closed 2026-06-23 without
  merging**)

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

## Warn-only mode

The new checks (cloud placeholder, OneDrive, Search index) and the EICAR check on the new
download subfolders all produce **warnings** rather than test failures for now, since these
conditions were formerly tolerated and the rest of the nightly fleet hasn't been brought
up to spec. The original AV-on-cwd check stays a hard `Assert.Fail`. Failures (when they
happen) are accumulated across all checks/dirs and reported in a single `Assert.Fail` at
the end of the test, so a problem on dir A doesn't hide a problem on dir B.

The `warnOnly: true` flags in `AaantivirusTestExclusion` should flip to `false` once every
nightly machine is configured.

## Verification

Each new check must demonstrably fire when its predicate is true. Verified via
`ai/.tmp/Verify-AntivirusExclusionTest.ps1` (one-shot harness, not committed). Each probe
sets up a failing condition, runs the test, asserts that a `# WARNING` line with the
expected substring appears, and tears down:
- Probe 1 (cloud placeholder): `attrib +O` build dir → expect warning → revert.
- Probe 2 (OneDrive): fake `HKCU:\...\OneDrive\Accounts\__Probe\UserFolder` → expect warning → remove.
- Probe 3 (Search index): manually tick build dir in Indexing Options → expect warning → untick.

Run the test on a clean machine and confirm it passes (no false positives, no warnings).

## Out of scope

- Fix for `DriftTimePredictorTutorialTest.cs` putting downloads under `C:\Skyline T&est ^Data\Data-drift\`
  rather than `Perftests\` — flagged separately, deferred.
- A WaitForComplete timeout in the library-load polling loop that hung — separate follow-up.
- An *activity*-style probe (vs. config-style) for third-party AV / backup / kernel filter
  drivers — config-querying covers ~90% of realistic culprits; the long tail can be added
  later if needed.

## Resolution

### 2026-06-23 — Abandoned (PR closed unmerged)

PR [#4191](https://github.com/ProteoWizard/pwiz/pull/4191) ("Add more checks for potential
test-interfering file system tasks (e.g. OneDrive, DropBox, Windows search indexer)") was **closed
without merging** on 2026-06-23, with no review comments recorded on the PR explaining why. None of
this work reached master.

GitHub issue [#4190](https://github.com/ProteoWizard/pwiz/issues/4190) **remains open**, so the
underlying problem is still live: `AntivirusExclusionTest` covers only the Skyline runtime build
output directory (`.`), not the persistent test-data download cache under
`{DownloadsPath}\Tutorials` and `{DownloadsPath}\Perftests` where the `.blib` files that actually
hung `ConsoleSetLibraryTest` live, and nothing checks non-AV culprits at all.

**Worth salvaging if this is picked up again** — the design work here is the valuable part:
- The three added check types (cloud-storage placeholder attributes covering OneDrive
  Files-on-Demand / Dropbox Smart Sync / Google Drive File Stream / Box Drive; OneDrive sync-root
  registry walk; `ISearchCrawlScopeManager::IncludedInCrawlScope` via inline `[ComImport]` with
  GUIDs and vtable order verified against the Windows SDK IDLs).
- The **warn-only** staging decision: new checks warn rather than fail until the whole nightly fleet
  is brought up to spec, with `warnOnly: true` flipping to `false` once it is. The original
  AV-on-cwd check stays a hard `Assert.Fail`.
- The deliberate choice **not** to check `{DownloadsPath}` itself — when `SKYLINE_DOWNLOAD_PATH` is
  unset that is the user's real Downloads folder, which is reasonable to leave un-excluded.
- The verification harness design in `ai/.tmp/Verify-AntivirusExclusionTest.ps1` (one-shot, never
  committed, so it is likely gone): each probe sets up a failing condition, asserts the expected
  `# WARNING` line appears, and tears down.

Closing this TODO reflects the PR's status, not a decision that #4190 is resolved.
