# TODO-20260805_osprey_diagnostic_abort_capture.md

## Branch Information
- **Branch**: `Skyline/work/20260805_osprey_diagnostic_abort_capture`
- **Base**: `master` (at `b554ce6f0d`, i.e. after #4530)
- **Created**: 2026-08-05
- **Status**: Completed
- **GitHub Issue**: [#4493](https://github.com/ProteoWizard/pwiz/issues/4493)
- **Module**: `osprey`
- **PR**: [#4531](https://github.com/ProteoWizard/pwiz/pull/4531) (merged 2026-08-05 as `df3e433`)

## Problem

`PercolatorEngine.RunPercolatorFdr` invoked the `captureModel` hook BEFORE testing
`results.DiagnosticAbort`. On a diagnostic-only (`*Only`) run `DispatchSvm` returns
`new PercolatorResults { DiagnosticAbort = true }` with `FoldWeights`, `FoldBiases` and
`Standardizer` all NULL - nothing was trained - and that object was handed to the frozen-model
hook as though it were a trained 1st-pass model.

The streaming sibling in the SAME file already ordered it correctly (checks the abort at
`PercolatorEngine.cs:906`, invokes the hook at `:914`), so the two paths disagreed.

Found by `/code-review max` during #4468 / #4490. Not fixed by #4490, which was structural and
byte-identical.

## Fix

Move the `DiagnosticAbort` check ABOVE the `captureModel` invoke, matching the sibling path, and
say in the comment WHY the order matters rather than leaving it conventional.

## Regression Test

- **Test name**: `TestDiagnosticAbortDoesNotCaptureUntrainedModel` (`FdrTest.cs`)
- **Test project**: `Osprey.Test`
- **Fails on master**: YES - verified by stashing only the `PercolatorEngine.cs` change and
  re-running: `Failed: 1`, `Passed: 574`.
- **Passes on fix**: YES - 575/575.

Uses `StandardizerOnly`, the EARLIEST abort (it fires before any fold is trained), so the
sentinel is maximally empty and the assertion is unambiguous. The dump writes a fixed relative
path, so the test deletes `cs_stage5_standardizer.tsv` in a `finally` rather than leaving it in
the test working directory.

The issue notes the deeper fix - a dedicated result type, or an explicit abort return, making
the ordering *unrepresentable* rather than conventional. NOT done here: that is a wider
refactor of `PercolatorResults` across all four `DiagnosticAbort` return sites in
`PercolatorTrainer`, and it would touch the parity-locked dispatch. Recorded on #4493 as the
follow-up if the sentinel-on-the-data-object pattern bites again.

## Impact

Inert on every production path: `captureModel` is null on default percolator runs, and the
abort only fires under a `*Only` diagnostic env var. So this is a correctness fix for the
diagnostic + frozen-model combination, not a change to any shipping result.

## Progress Log

### 2026-08-05 - Fixed

Reordered the check, added the abort-path regression test, verified it fails without the fix.
Gate: 575/575 unit tests, zero ReSharper inspections.

### 2026-08-05 - Merged

PR #4531 merged as commit `df3e433`. `PercolatorEngine.RunPercolatorFdr` now tests
`results.DiagnosticAbort` BEFORE invoking the `captureModel` hook, matching the ordering the
streaming sibling in the same file already used, so the frozen-model hook can no longer be
handed the abort sentinel (null FoldWeights / FoldBiases / Standardizer) as though it were a
trained 1st-pass model. `TestDiagnosticAbortDoesNotCaptureUntrainedModel` covers the abort path
the issue named as untested, and was verified to FAIL without the fix (574 passed / 1 failed)
rather than being a test that passes either way.

Gate: 575/575 unit tests, zero ReSharper inspections, 18/18 PR checks SUCCESS.

**Deliberately not run**: `regression.ps1`. The change is inert on every production path -
`captureModel` is null on default percolator runs and the abort only fires under a `*Only`
diagnostic env var, which no regression leg sets - so it cannot move a golden. The machine was
also mid-way through a 197-file `.spectra.bin` staging sweep at the time.

**Deferred to #4493**: the deeper fix the issue suggests - a dedicated result type, or an
explicit abort return, making the ordering *unrepresentable* rather than conventional. That is a
wider refactor across all four `DiagnosticAbort` return sites in `PercolatorTrainer` and the
parity-locked dispatch.

**Not done**: `/code-review max` never ran on this branch - the harness refuses model-invoked
runs of that skill, so it needs the developer to start it. Copilot's automatic review on PR open
was the only AI review this branch received.
