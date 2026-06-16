# Mixed-polarity Full Scan crash (issue #4240)

**Status:** Completed
**PR:** [#4241](https://github.com/ProteoWizard/pwiz/pull/4241) (merged 2026-06-15 as `ff7b5d44`)
**Branch:** `Skyline/work/20260522_mixed_polarity_fullscan_crash` (checkout: `C:\Dev\Mixed`)
**Issue:** https://github.com/ProteoWizard/pwiz/issues/4240
**Exception:** skyline.ms rowId 74770, fingerprint `eddb8a1125c183f7` (fix recorded 2026-06-15)

## Objective

Fix the `AssumptionException` in `GraphFullScan.CreateSingleScan` (#74770) and add a regression test.

## Root cause

`CreateSingleScan` asserted `transition.PrecursorMz.IsNegative == negativeScan` for every transition
in `ScanProvider.Transitions`. When that list contains a precursor of the opposite polarity to the
displayed scan, the assertion fires. A plain chromatogram click can't create that condition —
opposite-polarity precursors always render in separate panes (confirmed live), so a click only ever
gathers one polarity. The reported crash arrived via a timer-driven `UpdateGraphPanes` refresh.

## Fix

`GraphFullScan.cs` `CreateSingleScanInPane`: fold the polarity check into the existing per-transition
skip (`continue` when `IsNegative != negativeScan`) instead of asserting, so off-polarity transitions
are ignored rather than crashing.

## Regression test

`TestFunctional/MixedPolarityFullScanTest.cs` (+ `.zip`, registered in `TestFunctional.csproj`):
- Tiny synthetic polarity-switching MS1 mzML (`MixedPolarity.mzML`, 21 scans even=+/odd=-; molecule
  C20H30O2, [M+H]+=303.2319, [M-H]-=301.2173) + `GenerateMixedPolarityMzml.py` (provenance; pwiz
  round-trip verified, 21 spectra 11 pos / 10 neg).
- Builds a `ScanProvider` whose transition list spans BOTH polarities and calls `ShowGraphFullScan`
  on a positive scan - the deterministic repro (the UI-click path can't assemble it).
- Verified **red** (AssumptionException at GraphFullScan.cs:1951) with the fix stashed; **green** with the fix.

## Also: scan Polarity in Full Scan properties (user request)

`FullScanProperties.cs` + `FullScanPropertiesRes.resx`: new "Polarity" row (positive/negative) under
Acquisition in the Full Scan property sheet. `FullScanGraphTest.cs` expected dicts updated. Verified
onscreen and `TestFullScanGraph` passes.

## Status / next

PR **#4241** open (https://github.com/ProteoWizard/pwiz/pull/4241).
Crash fix, regression test, and Full Scan Polarity row all committed & pushed.

Copilot review responses committed:
- `0c79eb9ce` — RunDlg<ImportTransitionListColumnSelectDlg> for the import-dialog UI race (replaces WaitForConditionUI suggestion).
- `756174ebc` — Ms1FullScanFilteringTutorial.TestFullScanProperties: added `Polarity` to the
  expected dict (the always-populated Polarity row was breaking it) + `IsCentroided` now uses
  `FullScanPropertiesRes.False`. Required `InternalsVisibleTo("TestTutorial")` in Program.cs.
- `345d65a28` — synced the Boolean.ToString WARNING SSR pattern (from `27280cb4f`) to the
  AutoQC/SkylineBatch/SkylineMcp DotSettings (build's Sync-DotSettings did it; was 27280cb4f's leftover).

Verified: build green, `TestMs1Tutorial` green, `TestMixedPolarityFullScan`/`TestFullScanGraph` green, CodeInspection green.
All 6 Copilot review threads replied + resolved (0 open as of 2026-05-24).

**Do NOT cherry-pick to skyline_26_1** (decided 2026-05-24). No "Cherry pick to release"
label is present on issue #4240 or PR #4241, so the auto-cherry-pick will not fire. Master only.

Copilot finding (2026-05-25 re-review) — RESOLVED in `bfce1d8ad`:
the polarity guard was only on the point-assignment loop; the curve, transition-label, and
mass-error loops still filtered by Source alone, so an off-polarity precursor in a mixed list
produced an empty curve, a stray label, and possibly a bogus mass error. Factored the check
into a `TransitionAppliesToScan(transition, negativeScan)` helper and applied it at all four
enumeration sites (threading `negativeScan` out of CreateSingleScan/InPane; added
`IsDisplayedScanNegative()` for the heatmap label paths). Strengthened TestMixedPolarityFullScan
to assert the off-polarity transition renders no curve (verified red→green). Not a crash; master-only.

Copilot finding (2026-05-25, re-review of bfce1d8ad) — RESOLVED in `b4725be69`:
AddExtractionBoxes was the one remaining site filtering by Source only, so it drew a stray
extraction box for the off-polarity precursor. Threaded scan polarity through all six call sites
and filtered via TransitionAppliesToScan; extended TestMixedPolarityFullScan to assert a single
extraction box (verified red 2→green 1). Verified green: TestMixedPolarityFullScan,
TestFullScanGraph, TestMs1Tutorial, CodeInspection.

Copilot finding (2026-05-25, re-review of b4725be69) — RESOLVED in `237a76617`:
IsDisplayedScanNegative() ran twice per heatmap branch (re-running GetFilteredScans); now cached
in a local `negativeScan` and passed to both AddExtractionBoxes and AddTransitionLabels.
Verified green: TestMixedPolarityFullScan, TestFullScanGraph, CodeInspection.

Fresh-context self-review (/pw-self-review, 2026-05-26) found two MORE Source-only sites the
audit missed: CreateMobilogram (spurious off-polarity mobilogram curve) and the hover tooltip
(wrong transition name). Both fixed. Per Brian's design feedback, refactored so the helper owns
the polarity: `TransitionAppliesToScan(transition)` self-determines scan polarity from the first
displayed spectrum (checks Source first, returns early, then polarity) — removed the out-param
threading, the lambda-capture workaround, and IsDisplayedScanNegative(). All SEVEN enumeration
sites now route through the one self-contained predicate. RESOLVED in `1ca01e2c8` (+ mobilogram/
tooltip fix). Verified green: TestFullScanGraph, CodeInspection, TestMs1Tutorial (one flaky
CheckAnnotations + one flaky GC-LEAK along the way, see below).

KNOWN ISSUE (not from this work): TestMixedPolarityFullScan intermittently GC-LEAKs
(SkylineWindow, SrmDocument). Proven pre-existing — the committed head leaks identically with the
refactor stashed, and the same committed code was green earlier in the session. Looks
timing/environmental (long session). Teardown already closes the Full Scan dock pane
(RestoreMinimalView) and would flag a left-open form, so it is NOT a left-open-form issue. If it
recurs in CI, diagnose with -MemoryProfile + dotMemory retention screenshot (don't guess paths).

All 10 Copilot threads replied + resolved (0 open). Copilot does not reliably auto-review later
pushes — request explicitly after each review-response commit (see memory
reference_request_copilot_review). Requested review for 1ca01e2c8.

### 2026-06-15 - Merged

PR #4241 merged to master as squash commit `ff7b5d44` (Brian merged after CI green:
Core Windows 308 tests passed, all CodeQL green, TeamCity Skyline PR build green). Shipped:
the assert→skip crash fix routed through `TransitionAppliesToScan` at all seven enumeration
sites, the `MixedPolarityFullScanTest` regression test, and the Full Scan Acquisition
**Polarity** row (+ localizable True/False for Is Centroided). Reviewed by Rita (LGTM via
PR comment; her off-polarity-physics question answered inline) and Copilot (all 13 threads
resolved). `record_exception_fix(eddb8a1125c183f7, 4241)` recorded on skyline.ms. Issue #4240
auto-closed via `Fixes #4240`. Master only — **not** cherry-picked to skyline_26_1 (decided
2026-05-24; POST-RELEASE PATCH default is no cherry-pick).

Pre-merge self-review (fresh-context agent, 2026-06-15) — all findings dismissed/deferred,
none blocking; recorded here so they aren't lost:
- **[deferred] Test coverage:** `MixedPolarityFullScanTest` ChangeScan(±1) steps stay on
  positive scans (ScanProvider built from the positive precursor's times), so it re-renders
  the timer-refresh path but never *displays* an opposite-polarity scan. The fix is pinned by
  the initial-render assertions; stronger coverage (display a negative scan) is a future nicety.
- **[deferred] `AddExtractionBoxes`:** calls `transition.ExtractionWidth.Value` with no
  `HasValue` guard (pre-existing; the PR touched the line). Safe for current test data; would
  throw for a transition with no extraction width.
- **[dismissed] Empty/null `MsDataSpectra` defaults polarity to "positive"** in
  `TransitionAppliesToScan` — verified unreachable (every caller is gated by upstream null/empty
  checks on the UI thread).
- **[dismissed] Per-call polarity recompute** (the `237a76617` once-per-render caching got
  folded into the predicate) — correctness fine, micro-cost only.

KNOWN ISSUE carried forward: `TestMixedPolarityFullScan` intermittently GC-LEAKs
(SkylineWindow, SrmDocument); proven pre-existing and timing/environmental. If it recurs in
CI, diagnose with -MemoryProfile + dotMemory retention screenshot.
