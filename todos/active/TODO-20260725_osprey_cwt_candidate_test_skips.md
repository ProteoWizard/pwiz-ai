# TODO: Remove the 3 permanently-skipped Osprey unit tests

**Created:** 2026-07-25  **Requested by:** Brendan

## Branch Information
- **Branch**: `Skyline/work/20260725_osprey_cwt_candidate_test_skips`
- **Base**: `master`
- **Created**: 2026-07-25
- **Status**: In Progress
- **PR**: (pending)

## Problem

Every Osprey unit-test run reported **3 skipped** (537 total / 534 passed). All three
lived in `Osprey.Test/CwtCandidateCodecTest.cs` and skipped via `Assert.Inconclusive`
because they read parquet files that are not in the repo:

| Test | Needed |
|---|---|
| `TestCwtCandidateCrossImplParity` | BOTH `.scores.cs.parquet` + `.scores.rust.parquet` for Stellar file 20 |
| `TestLoadCwtCandidatesFromRustParquet` | a Rust-written Astral parquet under `astral\_stage6_planning\` |
| `TestCsScoringPopulatesCwtCandidates` | a C#-written Stellar `.scores.cs.parquet` |

They resolved paths from `OSPREY_TEST_BASE_DIR`, defaulting to `D:\test\osprey-runs`
— the **Test-PerfGate scratch directory**, whose contents are transient run leftovers,
not curated fixtures. So the tests could never run in CI, and even locally they ran
only if an earlier ad-hoc run happened to leave the exact expected file behind. That
is worse than a plain skip: the suite's behaviour depended on unversioned scratch
state, so a stale leftover could make a test start running (and possibly failing)
with no source change.

Two of the three were also **Rust cross-impl parity** checks, and
`TestCwtCandidateCrossImplParity` was not even a strict gate — it allowed a 3%
value-mismatch tolerance to absorb known Stage 1-4 ULP drift.

## Decision

**Remove the two Rust-parity tests; replace the third with a self-contained
round-trip.** Rationale:

- Cross-impl parity is already covered, far more strongly, by the standing gates:
  `regression.ps1` (committed C# golden + resume, 1e-9) and
  `Compare-EndToEnd-Crossimpl.ps1` on Stellar + Astral. A 3%-tolerance unit test
  that usually does not run added nothing on top of those.
- Rust parity is slated for removal anyway (see the parity-removal sprint), so
  investing in fixtures for these two would be short-lived.
- The genuinely valuable coverage — that the codec is wired correctly into the
  `cwt_candidates` parquet column — does not need external data at all.

New `TestCwtCandidatesRoundTripThroughParquet` writes three `FdrEntry` rows carrying
known candidate lists (2 / 0 / 1, ids deliberately out of order so the writer's
canonical sort runs), reads them back through
`ParquetScoreCache.LoadCwtCandidatesFromParquet`, and asserts per-row list counts plus
bit-exact equality of all six candidate fields — including the
`0.097751617431640625` boundary value that the old round-trip test used to pin the
`BitConverter` path.

## Status

- [x] Identified all 3 skips via a TRX logger run (no `[Ignore]` attributes; the
      skips were `Assert.Inconclusive` on missing files)
- [x] Removed `TestCwtCandidateCrossImplParity` + its `FieldsBitDiff` / `BitDiff`
      helpers, and `TestLoadCwtCandidatesFromRustParquet`
- [x] Replaced `TestCsScoringPopulatesCwtCandidates` with the self-contained
      round-trip; removed the now-unused `StellarBaseDir` / `DefaultTestBaseDir`
      helpers, so no test references `OSPREY_TEST_BASE_DIR` any more
- [x] Unit tests: **535 total, 535 passed, 0 skipped** (was 537 / 534 / 3)
- [x] Inspection gate: 0 errors, 0 warnings
- [ ] PR opened, self-review, TeamCity

## Notes

- The new test is not vacuous: an early revision used the `CoelutionScoredEntry`
  `WriteScoresParquet` overload, whose schema has **no** `cwt_candidates` column, and
  the test failed immediately on the count assertion. Only the `FdrEntry` overload
  (`BuildFdrEntryColumns`) writes that column.
- The removed comment block cited `ai/todos/active/TODO-20260428_osprey_sharp_stage6.md`,
  which no longer exists — a dead reference, and citing ai/ TODO filenames from pwiz
  code is against convention anyway.
- End-to-end "scoring actually populates CWT candidates" stays gated indirectly: if
  candidates stopped being written, Stage 6 reconciliation planning would shift and
  the committed regression golden (blib + text) would diverge.
- File header AI attribution updated to Claude Opus 5 per STYLEGUIDE.

## Key files

- `pwiz_tools/Osprey/Osprey.Test/CwtCandidateCodecTest.cs` (+76 / -240)
