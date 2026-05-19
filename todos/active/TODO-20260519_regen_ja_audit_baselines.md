# Regenerate audit log baselines on release branch after Japanese translation update in PR #4211

## Branch Information
- **Branch**: `Skyline/work/20260519_regen_ja_audit_baselines_release_26_1`
- **Base**: `Skyline/skyline_26_1`
- **Created**: 2026-05-19
- **Status**: In Progress
- **GitHub Issue**: [#4228](https://github.com/ProteoWizard/pwiz/issues/4228)
- **PR**: (pending)

### Test Failure Tracking (for `record_test_fix` when PR merges)
- **Test Name**: TestLiveReportsTutorial (and TestPeakBoundaryImputationDiaTutorial under same fingerprint)
- **Fix Type**: failure
- **Failure Fingerprint**: `b9575cc8e050f39e`

## Objective

PR #4211 (merged to `Skyline/skyline_26_1` on 2026-05-17) updated the Japanese translation of "lookup" from "ルックアップ" to "参照" but did not regenerate the audit log baseline files used by tutorial tests. As a result, TestLiveReportsTutorial and TestPeakBoundaryImputationDiaTutorial fail on every release-branch nightly machine (15 failures total).

PR #4223 (open, base `master`) forward-ports the same translation change to master. Baseline regen will be needed there too once #4223 merges — this TODO covers the release branch only; treat master as a follow-up.

## Tasks

- [ ] Reproduce TestLiveReportsTutorial failure locally on `Skyline/skyline_26_1` under ja locale (confirm red)
- [ ] Run TestLiveReportsTutorial with `RecordAuditLogs=true` under ja locale to regenerate its baseline
- [ ] Run TestPeakBoundaryImputationDiaTutorial with `RecordAuditLogs=true` under ja locale to regenerate its baseline
- [ ] Inspect baseline diff — confirm only translation-affected lines changed ("ルックアップ" → "参照"); nothing structural
- [ ] Re-run both tests under ja locale with `RecordAuditLogs=false` to confirm green
- [ ] Commit regenerated baselines
- [ ] Open PR against `Skyline/skyline_26_1` with `Fixes #4228`

## Regression Test

- **Test name**: TestLiveReportsTutorial, TestPeakBoundaryImputationDiaTutorial — these ARE the regression tests; they were already in place and caught the issue.
- **Test project**: TestTutorial (LiveReports), TestPerf (PeakBoundaryImputationDia)
- **Fails on master**: Confirmed red at cb67cfb0f on release-branch nightly machines (fingerprint `b9575cc8e050f39e`, 15 failures across 12 machines). Local reproduction pending.
- **Passes on fix**: pending baseline regeneration

No new regression test is being added: the existing tutorial tests already exercise the audit log under ja locale and caught this regression in nightly. The work here is restoring the broken baseline that those tests compare against — the test is the verifier, the baseline is the data it checks.

## Progress Log

### 2026-05-19 - Session Start

- Reviewed issue #4228 (created earlier today after research session misread PR #4223 direction).
- Confirmed PR #4223 ships translation .resx + help HTML changes to master but does NOT regenerate audit log baselines, so master will need the same fix later.
- Created branch off `Skyline/skyline_26_1` at cb67cfb0f (matches failing nightly hash).
- Test locations identified:
  - `pwiz_tools/Skyline/TestTutorial/LiveReportsTutorialTest.cs`
  - `pwiz_tools/Skyline/TestPerf/PeakBoundaryImputationDiaTutorial.cs`
- Next: reproduce the ja-locale failure locally, then regenerate baselines.
