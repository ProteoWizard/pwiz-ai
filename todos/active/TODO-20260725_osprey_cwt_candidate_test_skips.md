# TODO: Osprey friction clean-up batch (skipped tests, resume harness, IDE warnings)

**Created:** 2026-07-25  **Requested by:** Brendan

## Branch Information
- **Branch**: `Skyline/work/20260725_osprey_cwt_candidate_test_skips`
- **Base**: `master`
- **Created**: 2026-07-25
- **Status**: In Progress
- **PR**: [#4460](https://github.com/ProteoWizard/pwiz/pull/4460)

## Scope

A deliberate grab-bag. These are the small orthogonal annoyances that cause friction
during feature sprints but are individually too minor to justify their own PR and too
unrelated to ride along with a feature - so they never land. Brendan set aside a few
hours to clear them, and asked for them ALL in one PR rather than split or deferred.
The branch name reflects only the first item; the PR covers the batch.

## 1. Three permanently-skipped unit tests (the original ask)

Every Osprey unit run reported **3 skipped** (537 / 534 / 3). All three were in
`Osprey.Test/CwtCandidateCodecTest.cs`, skipping via `Assert.Inconclusive` on parquet
files that are not in the repo - resolved from `OSPREY_TEST_BASE_DIR`, defaulting to
`D:\test\osprey-runs`, the **Test-PerfGate scratch dir**. They could never run in CI,
and locally ran only if an earlier ad-hoc run happened to leave the exact file behind
- worse than a plain skip, since a stale leftover could silently start running them.

**Removed** the two Rust cross-impl parity tests (`TestCwtCandidateCrossImplParity`,
`TestLoadCwtCandidatesFromRustParquet`). That parity is covered far more strongly by
`regression.ps1` (committed golden, 1e-9) and `Compare-EndToEnd-Crossimpl.ps1`; the
removed parity test was not even strict (3% value-mismatch tolerance for Stage 1-4
ULP drift), and Rust parity is slated for removal anyway.

**Replaced** `TestCsScoringPopulatesCwtCandidates` with a self-contained round-trip.

## 2. Code-review hardening of the replacement

A `/code-review xhigh` pass found the first version of that replacement too weak. It
now lives in `IOTest` (beside the rest of the `ParquetScoreCache` coverage) and reuses
`MakeStreamEntry` instead of a duplicate fixture. It covers:

- a **null** candidate list, gating the writer's null-to-4-byte-zero-blob
  normalization (`ParquetScoreCache.cs:445`). Verified this bites: the reader leaves
  `CwtCandidates` null for a null cell (`:1243-1245`) and non-null for a zero blob, so
  reverting the normalization fails the test.
- **multi-row-group** framing via `RowGroupRowCapForTest = 2`, exercising the reader's
  per-group append loop.
- **ParquetIndex alignment** via `LoadFullFdrEntries`.

One review finding was **rejected**: that no test anchors the byte layout.
`TestEncodeMatchesRustByteLayout` pins each field to a distinct offset with a distinct
literal, so the proposed field-swap regression does fail it.

`CwtCandidateCodecTest`'s class doc now states its scope (byte arrays only, no parquet)
and records that "scoring actually populates CwtCandidates" is golden-gated only,
because `PerFileScoringTask` is not unit-testable today.

## 3. Cumulative-coverage resume leg never resumed

Found while running `-Coverage`: `Measure-CumulativeCoverage.ps1` failed on the Stellar
resume leg with `HydrateReconciliationOverlay: failed to overlay .1st-pass.fdr_scores.bin`
- while that file existed and was valid (magic/version/pass/length all verified by hand).

**Root cause:** its private `Invoke-ResumeInvalidation` was a stale copy of
`regression.ps1`'s, keyed on the task CLASS names. The tasks stamp their `Name` values:
`FirstJoinTask.Name` is `FirstPassFDR`, `MergeNodeTask.Name` is `SecondPassFDR`. Both
globs matched **zero files** (verified: 0 matched vs 6 for the correct tokens against
the failing run dir). It deleted only `output.blib` while leaving
`output.blib.SecondPassFDR.osprey.task` asserting validity - a state no supported path
produces. **Not a product bug.**

**Why CI never caught it:** the script lives in the ai repo and TeamCity never runs it;
it duplicated logic instead of sharing it; and a `Where-Object` matching nothing fails
silently, so it reported a green "resume" leg that never resumed.

**Fix:** `Invoke-ResumeInvalidation` moved into `Regression/RegressionData.ps1` (already
dot-sourced by `regression.ps1`), now **hard-fails** when it matches nothing. The ai
script dot-sources it at SCRIPT scope - its previous dot-source was inside a function,
which scoped the definitions to that call.

## 4. IDE / doc friction

- `Osprey.IO.csproj`: `<!-- ReSharper disable once VulnerablePackage -->` on
  Parquet.Net so Visual Studio is clean (Brendan's edit; indentation normalized).
- `inspect_parquet.py` no longer cites the removed test as the authority for its 50%
  CWT threshold.

## Status

- [x] 3 skips removed; suite is **535 / 535 / 0 skipped**
- [x] Review hardening applied; zero-warning inspection green
- [x] Resume invalidation shared + hard-failing; verified by direct token comparison
- [x] ai-side committed (pwiz-ai `215d029`)
- [ ] `regression.ps1 -Dataset Stellar` (modes 1/2/3) - RUNNING, gates item 3
- [ ] PR description broadened, TeamCity

## Deliberately NOT in this PR

**Bumping the transitive advisories** behind the VulnerablePackage warning -
`Snappier 1.1.6` (GHSA-pggp-6c3x-2xmx) and `System.Text.Json 8.0.4`
(GHSA-8g4q-xg66-9fp4), both High. Snappier is the parquet **compressor**, so a version
change can move compressed bytes and the committed byte-identical goldens. Different
risk class; needs its own baseline.

## Key files

- `pwiz_tools/Osprey/Osprey.Test/CwtCandidateCodecTest.cs` (-103 / +13)
- `pwiz_tools/Osprey/Osprey.Test/IOTest.cs` (+123)
- `pwiz_tools/Osprey/Regression/RegressionData.ps1`, `regression.ps1`
- `pwiz_tools/Osprey/Osprey.IO/Osprey.IO.csproj`
- ai: `scripts/Osprey/Measure-CumulativeCoverage.ps1`, `scripts/Osprey/inspect_parquet.py`
