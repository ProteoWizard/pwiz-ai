# TODO-20260129_associate_proteins_null.md

## Branch Information
- **Branch**: `Skyline/work/20260129_associate_proteins_null`
- **Base**: `master`
- **Created**: 2026-01-29
- **Status**: In Progress
- **GitHub Issue**: [#3878](https://github.com/ProteoWizard/pwiz/issues/3878)
- **PR**: [#3907](https://github.com/ProteoWizard/pwiz/pull/3907)

## Objective
Add diagnostic assertions to AssociateProteinsDlg.NewTargetsFinalSync() to identify the root cause of a rare NullReferenceException on `_proteinAssociation`.

## Root Cause Analysis
`NewTargetsFinalSync()` is a test-only API (no UI callers). All test callers wait for `DocumentFinalCalculated` (which returns `IsComplete`) before calling it.

In `DisplayResults()`, the sequencing looks correct:
- Line 155: `_proteinAssociation = results.ProteinAssociation` (set first)
- Line 157: `IsComplete = true` (set after)

So `_proteinAssociation` should already be set when `IsComplete` is true. The NullRef occurred only once in 8+ months of nightly testing (run 80277). That same run also had TestDdaSearchTide fail with a timeout, suggesting environmental stress rather than a code-level race condition.

We don't fully understand why `_proteinAssociation` was null. Possible explanations:
- `results.ProteinAssociation` was null in a valid result (see `ProduceResults()` line 192 which returns early without setting ProteinAssociation if `AssociatedProteins` is null)
- `DisplayResults()` was re-entered and reset state between `IsComplete` checks
- Environmental/timing issue unique to the stressed run

## Exception Details
- **Fingerprint**: `63b9758310777f60`
- **Discovered in**: TestDdaSearchMsFragger nightly test (test-only, not user-facing)
- **Machine**: BRENDANX-UW8, Run ID 80277
- **Frequency**: 1 occurrence in Nightly x64, 1 unrelated failure in Performance Tests
- **Co-failure**: TestDdaSearchTide also timed out in the same run

## Changes Made
- [x] Added `Assume.IsTrue(IsComplete)` - detects if method called before processing finished
- [x] Added `Assume.IsNotNull(doc)` for DocumentFinal - detects if document wasn't produced
- [x] Added `Assume.IsNotNull(_proteinAssociation)` - detects the original null cause

## Files Modified
- `pwiz_tools/Skyline/EditUI/AssociateProteinsDlg.cs` - NewTargetsFinalSync() at line 861

## Test Plan
- [ ] TeamCity CI passes (assertions don't fire under normal conditions)

## Implementation Notes
- Chose diagnostic assertions over silent null-coalescing because:
  - The failure is extremely rare (1 occurrence in 8+ months)
  - Silently returning zeros would mask the root cause and let tests pass with bogus data
  - The `Assume` assertions will produce clear messages identifying which invariant failed
  - This follows the same philosophy as `NewTargetsFinal()` (line 848) which throws when `DocumentFinal == null`
- The three assertions create a diagnostic ladder:
  - `IsComplete` false -> method called too early (test timing issue)
  - `DocumentFinal` null -> processing completed but didn't produce a document
  - `_proteinAssociation` null -> processing completed but didn't produce association
