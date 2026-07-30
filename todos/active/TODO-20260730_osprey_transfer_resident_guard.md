# Osprey: stop OSPREY_PASS2_QVALUE=transfer forcing the resident first-pass pool

## Branch Information
- **Branch**: `Skyline/work/20260730_osprey_transfer_resident_guard` (C:\proj\pwiz)
- **Base**: `master` (f823e95294)
- **Module**: `osprey`
- **Created**: 2026-07-30
- **Status**: In Progress
- **Parent issue**: [#4484](https://github.com/ProteoWizard/pwiz/issues/4484) - prerequisite for
  the pass-2 FDR default flip (see `TODO-20260727_osprey_pass2_fdr_default.md`)
- **PR**: (pending)
- **Requester**: Mike + Brendan (Osprey developers) - NO credit line.

## Objective

`OSPREY_PASS2_QVALUE=transfer` still forces the O(files) RESIDENT first-pass pool in shipped
master, so an 82-file transfer run dies in ~25 s on `GuardResidentPool` (or needs
`OSPREY_ALLOW_UNBOUNDED_MEMORY=1` and ~104 GB). This is a REGRESSION: #4438 removed the
forcing when it redesigned transfer to per-run-only, and a #4446 merge artifact restored it.
Restore #4438's memory bounding so `transfer` is usable at scale - it is the leading candidate
for the pass-2 default, and the flip cannot proceed while its 82-file arm cannot run.

## Root cause (verified 2026-07-30 at master f823e95294)

`git log -S Pass2TransferQ` on both files shows the same remove/re-add pair:
- `8a32095c5` (#4438) REMOVED `|| OspreyEnvironment.Pass2TransferQ`
- `dd9e84581` (#4446) RE-ADDED it while introducing transfer-compete / protein-compact

Both re-adds contradict comments in the same hunk, which is what identifies this as a merge
artifact rather than intent:
- `FirstJoinTask.cs:274-280` states "OSPREY_PASS2_QVALUE=transfer takes the SAME lean projection
  first-pass path as the default: it no longer forces the resident pool" - immediately above the
  statement that forced it.
- `PerFileScoringTask.NeedsResidentPool`'s docstring states "OSPREY_PASS2_QVALUE=transfer no
  longer forces the resident pool" - immediately above the clause that did.

The authority on what transfer needs is `Pass2FdrSidecar.cs:1112-1114`: "No global full-population
table and no resident first-pass pool: the frozen model is captured on the lean projection first
pass and each file's table is built from data already on disk, one file at a time."

**THIRD SITE, not in the earlier analysis**: `#4488` (`2a9e1b004`, merged 2 days ago) refactored
the `--input-scores` load decision from `NeedsResidentPool(config)` into the new
`PreCompactionPoolReason`, transcribing the already-regressed transfer clause into a third
location. Reverting only the two sites named in TODO-20260727 would have left the `--input-scores`
path (exactly what a `-LinkFrom` resume uses) still forcing the pre-compaction pool.

Corroboration that the guard is what fires: `ResidentPoolGuardError`'s trigger list never had a
transfer case, so a transfer run falls through to the generic `"this configuration"` message.

## Changes

- `Osprey.Tasks/FirstJoinTask.cs:288` - dropped `|| OspreyEnvironment.Pass2TransferQ` from
  `needsResidentFirstPassPool`.
- `Osprey.Tasks/PerFileScoringTask.cs` - dropped the same clause from `NeedsResidentPool`, and
  dropped the `OSPREY_PASS2_QVALUE=transfer` reason from `PreCompactionPoolReason` (with a
  comment recording why it must not come back).
- `Osprey.Tasks/PerFileScoringTask.cs` - split `NeedsResidentPool` into a private env-reading
  wrapper + an `internal` pure core taking `useFdrProjection`, mirroring the existing
  `ResidentPoolGuardError` pattern, so the trigger set is enumerable and testable.
- `Osprey.Test/ResidentPoolGuardTest.cs` - extended the existing `[TestMethod]` (no new test
  method, per the consolidation rule) to pin the trigger set: the four real triggers arm it,
  the default lean config and `--model-diagnostics` alone do not.

## Regression Test

- **Test name**: `TestResidentPoolGuardError` (extended) in `ResidentPoolGuardTest.cs`
- **Test project**: `Osprey.Test`
- **Fails on master**: **NO - and this is a deliberate, stated limitation.** `Pass2TransferQ` is
  a `static readonly` read from the environment, which is unset in a test process, so no unit
  test can turn the regression red without the testability refactor that is itself part of this
  fix. The test pins the enumerated trigger set; it does not catch a re-added env read. The real
  verifier for THIS defect is the 82-file transfer arm below (memory + calibration), and the
  durable barrier is that the predicate no longer reads `OspreyEnvironment` at all.
- **Passes on fix**: yes (556/556).

## Tasks

- [x] Revert the clause at all three sites; extract the testable core.
- [x] Extend `ResidentPoolGuardTest` to pin the trigger set.
- [x] Pre-commit gate: build Debug clean, 556/556 tests, inspection 0 warnings / 0 errors
      (`ai/.tmp/transfer-guard-inspection.log`).
- [ ] `regression.ps1 -Dataset Stellar` byte-identity (default path must be untouched - transfer
      is off by default, so the golden must not move).
- [ ] 82-file transfer arm: `ai/.tmp/run-pass2-82-4way.ps1 -Mode transfer`. PASS = completes
      (not ~25 s on the guard), peaks ~42 GB not ~104 GB, and reproduces the 2026-07-20 ladder
      recorded in TODO-20260727 (0.11 / 0.18 / 0.42 / **0.92** / 1.80 / 4.83% true FDP at
      0.1 / 0.25 / 0.5 / 1 / 2 / 5% nominal).
- [ ] Open the PR; ask before triggering the TeamCity Perf/Regression gate on `pull/<N>`.

## Progress Log

### 2026-07-30 - Root-caused and fixed; gates pending

Branched off master `f823e95294` in `C:\proj\pwiz`. Found the regression present at all three
sites (the third, `PreCompactionPoolReason`, added by #4488 two days ago and not in the earlier
analysis). Reverted, extracted the testable core, extended the guard test. Pre-commit gate green.

Remaining: the Stellar byte-identity gate, then the 82-file transfer arm - which is the only
verifier that actually proves the defect fixed, since a unit test structurally cannot.
