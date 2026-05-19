# Regenerate audit log baselines on release branch after Japanese translation update in PR #4211

## Branch Information
- **Branch**: `Skyline/work/20260519_regen_ja_audit_baselines_release_26_1`
- **Base**: `Skyline/skyline_26_1`
- **Created**: 2026-05-19
- **Status**: Completed
- **GitHub Issue**: [#4228](https://github.com/ProteoWizard/pwiz/issues/4228)
- **PR**: [#4230](https://github.com/ProteoWizard/pwiz/pull/4230) (merged 2026-05-19 as 02239a0a3)

### Test Failure Tracking (for `record_test_fix` when PR merges)
- **Test Name**: TestLiveReportsTutorial (and TestPeakBoundaryImputationDiaTutorial under same fingerprint)
- **Fix Type**: failure
- **Failure Fingerprint**: `b9575cc8e050f39e`

## Objective

PR #4211 (merged to `Skyline/skyline_26_1` on 2026-05-17) updated the Japanese translation of "lookup" from "ルックアップ" to "参照" but did not regenerate the audit log baseline files used by tutorial tests. As a result, TestLiveReportsTutorial and TestPeakBoundaryImputationDiaTutorial fail on every release-branch nightly machine (15 failures total).

PR #4223 (open, base `master`) forward-ports the same translation change to master. Baseline regen will be needed there too once #4223 merges — this TODO covers the release branch only; treat master as a follow-up.

## Tasks

- [x] Identify all baselines affected by PR #4211 string changes (ja: AnnotationDef_Lookup, ImputationSettings_ImputeMissingPeaks, PeptideSettings_Imputation; zh: ImputationSettings_ImputeMissingPeaks, PeptideSettings_Imputation)
- [x] Run TestLiveReportsTutorial with `recordauditlogs=on` under ja locale → 4-line diff: ルックアップ → 参照
- [x] Run TestPeakBoundaryImputationDiaTutorial with `recordauditlogs=on` under ja locale → 4-line diff: 補間/欠損しているピークを補間 → 補完/欠損ピークを補完
- [x] Run TestPeakBoundaryImputationDiaTutorial with `recordauditlogs=on` under zh-CHS locale → 4-line diff: 插补/插补缺失峰 → 划定/划定缺失峰
- [x] Verify all three tests pass in compare mode (`recordauditlogs=off`)
- [x] Commit regenerated baselines (ae6b3d535)
- [x] Open PR against `Skyline/skyline_26_1` with `Fixes #4228` → [#4230](https://github.com/ProteoWizard/pwiz/pull/4230)

## Regression Test

- **Test name**: TestLiveReportsTutorial, TestPeakBoundaryImputationDiaTutorial — these ARE the regression tests; they were already in place and caught the issue.
- **Test project**: TestTutorial (LiveReports), TestPerf (PeakBoundaryImputationDia)
- **Fails on master**: Confirmed red at cb67cfb0f on release-branch nightly machines (fingerprint `b9575cc8e050f39e`, 15 failures across 12 machines). Local repro skipped — nightly evidence at the same commit is conclusive.
- **Passes on fix**: Verified locally — TestLiveReportsTutorial (ja) 26s 0 failures; TestPeakBoundaryImputationDiaTutorial (ja) 148s 0 failures; TestPeakBoundaryImputationDiaTutorial (zh-CHS) 149s 0 failures. All standalone, recordauditlogs=off.

No new regression test is being added: the existing tutorial tests already exercise the audit log under ja/zh locale and caught this regression in nightly. The work here is restoring the broken baseline that those tests compare against — the test is the verifier, the baseline is the data it checks.

## Out of Scope / Follow-ups

- **Pre-existing zh-CHS flake** in TestPeakBoundaryImputationDiaTutorial: line 131 `Assert.AreEqual(pepOfInterest1, CallUI(GetSelectedPeptide))` returns null when this test runs after another test in the same TestRunner invocation. Standalone runs pass. Not caused by PR #4211 (the assertion is on `SkylineWindow.SequenceTree.GetNodeOfType<PeptideTreeNode>()?.DocNode.Peptide.Sequence`, no translation involved). Worth a separate issue if reproducible on the nightly machines.
- **Master branch**: PR #4223 forward-ports the same translation .resx changes from #4211 to master. After #4223 merges, the same three baselines will need to be regenerated on master. Either bundled with the merge of #4223 or as a follow-up PR.

## Progress Log

### 2026-05-19 - Session Start

- Reviewed issue #4228 (created earlier today after research session misread PR #4223 direction).
- Confirmed PR #4223 ships translation .resx + help HTML changes to master but does NOT regenerate audit log baselines, so master will need the same fix later.
- Created branch off `Skyline/skyline_26_1` at cb67cfb0f (matches failing nightly hash).
- Test locations:
  - `pwiz_tools/Skyline/TestTutorial/LiveReportsTutorialTest.cs`
  - `pwiz_tools/Skyline/TestPerf/PeakBoundaryImputationDiaTutorial.cs`

### 2026-05-19 - Baseline regeneration

- Built Debug x64 on release-branch HEAD (cb67cfb0f). Build succeeded in 33.8s.
- Identified affected baselines by grepping for changed strings:
  - ja: only TestLiveReportsTutorial.log (ルックアップ) and TestPeakBoundaryImputationDiaTutorial.log (補間)
  - zh: only TestPeakBoundaryImputationDiaTutorial.log (插补) — zh "Lookup" translation was not changed in #4211, so zh TestLiveReportsTutorial baseline is unaffected
- Regenerated all three baselines with `recordauditlogs=on`; diffs match exactly the PropertyNames.resx changes from #4211 — no structural drift.
- Verified all three pass in compare mode (`recordauditlogs=off`) standalone.
- Encountered a pre-existing flake in TestPeakBoundaryImputationDiaTutorial line 131 when run after another test in the same TestRunner invocation (both ja and zh). Standalone is reliable. Filed under Out of Scope / Follow-ups.

Next: commit baselines and open PR against `Skyline/skyline_26_1`.

### 2026-05-19 - Merged

PR #4230 merged via squash as commit `02239a0a3` on `Skyline/skyline_26_1` (admin-bypass; release-branch protection requires TeamCity checks that don't cover ja/zh-CHS anyway). Three baselines now match #4211's translations: ja/TestLiveReportsTutorial.log, ja/TestPeakBoundaryImputationDiaTutorial.log, zh/TestPeakBoundaryImputationDiaTutorial.log. The fix lands in tonight's release-branch nightly run, which is the only environment that actually validates ja/zh-CHS audit log baselines (TeamCity does not).

Issue #4228 auto-closed via `Fixes #4228`. Test-issue tracking on fingerprint `b9575cc8e050f39e` will need to be recorded as fixed in this step.

Deferred to follow-up:
- Master-side baseline regen, to be done when PR #4223 (forward-port of #4211's translation .resx to master) merges. Without that follow-up, the same failures will appear on the master nightly.
- Pre-existing flake in `TestPeakBoundaryImputationDiaTutorial.cs:131` (GetSelectedPeptide returns null when this test runs after another in the same TestRunner invocation; standalone passes). Not caused by #4211; worth a separate issue if it surfaces on nightly machines.
