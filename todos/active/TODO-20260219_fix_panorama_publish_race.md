# TestPublishToPanorama intermittent failure: TOCTOU race between cancel and no-network sub-tests

## Branch Information
- **Branch**: `Skyline/work/20260219_fix_panorama_publish_race`
- **Worktree**: `pwiz-work1`
- **Base**: `master`
- **Created**: 2026-02-19
- **Status**: In Progress
- **GitHub Issue**: [#3987](https://github.com/ProteoWizard/pwiz/issues/3987)
- **PR**: [#4017](https://github.com/ProteoWizard/pwiz/pull/4017)
- **Failure Fingerprint**: `8b3ee265ba8c38cd`
- **Test Name**: TestPublishToPanorama
- **Fix Type**: failure

## Objective

Fix intermittent TestPublishToPanorama failures caused by a TOCTOU race condition where a late `MessageDlg` from `TestUserCancelDuringUpload` leaks into `TestNoNetworkDuringUpload`, leaving an undismissed dialog that triggers a 10-second watchdog timeout.

## Tasks

- [ ] Improve `FindOpenForm<T>()` diagnostics to catch dual-form races
- [ ] Rename `localhost:8080` to `panorama.test.invalid:8080` (RFC 2606)
- [ ] Fix `ThreadExceptionDialog` routing for clean assertion failures
- [ ] Consider increasing 200ms wait in `TestCancellationWithoutMessageDlg`

## Files

- `pwiz_tools/Skyline/TestFunctional/PanoramaClientPublishTest.cs`
- `pwiz_tools/Skyline/TestUtil/TestFunctional.cs`
- `pwiz_tools/Skyline/TestUtil/AbstractFunctionalTestEx.cs`
- `pwiz_tools/Skyline/TestUtil/HttpClientTestHelper.cs`

## Progress Log

### 2026-02-19 - Session Start

Starting work on this issue. Branch created, TODO filed.
