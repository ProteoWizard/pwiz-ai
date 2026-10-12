# TODO-20261012_nightly_post_matching_log.md

## Branch Information
- **Branch**: `Skyline/work/20261012_nightly_post_matching_log`
- **Base**: `master` (6ce733caba)
- **Module**: `skyline`
- **Created**: 2026-10-12 (SKYLINE-DEV6, checkout `C:\proj\pwiz`)
- **PR**: [#4829](https://github.com/ProteoWizard/pwiz/pull/4829) (opened 2026-10-12; commits 9b282101f7, cfa6683440)
- **Status**: verified, reviewed, PR open; awaiting TeamCity + review

## Problem

Posting an earlier run's results with `SkylineNightly.exe <run>.xml` attached the wrong log.
`Nightly.Post(runSpec, xmlFile)` used `GetLatestLog()` - the newest `<machine>_*.log` in the log folder -
instead of the log belonging to the XML. skyline.ms reads the posted `<Log>` to find the last test that
started; with another run's log it dated that line against the posted run and recorded a false hang.

Observed 2026-10-12: re-posting SKYLINE-DEV6's two master leak runs (Oct 9 and Oct 10, which had failed
to post because the `Nightly x64 Leak Detection` folder did not exist) gave runs #86035 and #86036 the
log of the Oct 11 19:11 standard run, and both showed `HUNG:TestKoinaBuildLibrary` (pass 4, zh, 04:12) -
the test that run was in when it reached its 9-hour limit. Server logic: TestResultsController post,
`TEST_LINE_PATTERN` scan of `<Log>` from the end, hang if older than `RunDetail.HANG_MILLISECONDS`.

## Fix

`Nightly.Post` attaches `Path.ChangeExtension(xmlFile, ".log")` when it exists. When no XML is given,
xmlFile is already the latest log's `.xml`, so the end-of-run post is unchanged.

## Verification
- [x] Build SkylineNightly (single-file, Release, `-DistroZips SkylineNightly.zip`) from the branch; test copy in
  `D:\Nightly\test-post-fix\` (production exe untouched)
- [x] Brendan deleted #86035 and #86036 on skyline.ms
- [x] Re-posted both XMLs with the test exe -> runs #86041 (Oct 9 run) and #86042 (Oct 10 run)
- [x] Server: `testresults.hangs` empty for the folder; stored logs match the local logs line for line count
  (23,658 / 23,629) and end in TestPasteMolecules (ja) / TestPeakAreaRelativeAbundanceGraph (zh)
- [x] /code-review medium: 4 findings. Fixed: log/XML pair chosen once per branch (no reused variable),
  a SkylineNightly log line when no .log sits beside the posted XML. Out of scope (existing behavior,
  unchanged here): the end-of-run post re-derives the log with GetLatestLog() instead of the log Parse()
  read (a still-running older run writing its log later could mismatch them); `post` with no argument
  throws if the latest log has no XML.
- [x] PR #4829 opened
- [ ] Merge
