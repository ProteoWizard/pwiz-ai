# TODO-20261012_nightly_post_matching_log.md

## Branch Information
- **Branch**: `Skyline/work/20261012_nightly_post_matching_log`
- **Base**: `master` (6ce733caba)
- **Module**: `skyline`
- **Created**: 2026-10-12 (SKYLINE-DEV6, checkout `C:\proj\pwiz`)
- **Status**: fix written; verifying by re-posting runs #86035/#86036 after Brendan deletes them

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
- [ ] Build SkylineNightly (single-file) from the branch
- [ ] Brendan deletes #86035 and #86036 on skyline.ms
- [ ] Re-post `D:\Nightly\Logs\SKYLINE-DEV6_2026-10-09_18-16-34.xml` and `..._2026-10-10_18-16-46.xml`
- [ ] Server: no rows in `testresults.hangs` for the new runs; stored log ends with each run's own last test
- [ ] PR, merge
