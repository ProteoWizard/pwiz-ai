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
- [x] `regression.ps1 -Dataset Stellar` byte-identity PASS - mode1 (vs golden), mode2 (resume),
      mode3 (HPC chain), all blib 30,597,120. Log `ai/.tmp/transfer-guard-regression-stellar.log`.
- [ ] 82-file transfer arm: `ai/.tmp/run-pass2-82-4way.ps1 -Mode transfer`. PASS = completes
      (not ~25 s on the guard), peaks ~42 GB not ~104 GB, and reproduces the 2026-07-20 ladder
      recorded in TODO-20260727 (0.11 / 0.18 / 0.42 / **0.92** / 1.80 / 4.83% true FDP at
      0.1 / 0.25 / 0.5 / 1 / 2 / 5% nominal).
- [x] Ratchet the escape hatch (Brendan-approved follow-up, folded into this PR):
      `OSPREY_ALLOW_UNFIXED_RESIDENT=<token>` replaces the blanket
      `OSPREY_ALLOW_UNBOUNDED_MEMORY=1`; `ResidentPaths.KNOWN_UNFIXED` is the high-water mark;
      an unlisted resident path is refused unconditionally. Commits b5f59fe13 + bc6d6e95a.
- [x] Filed the missing tracking issues: #4505 (mdiag on a full resume - verified fix parked on
      the closed #4437 branch) and #4507 (`--fdrbench-pass 1`). Both were previously tracked
      only in a closed-PR comment / not at all, which is why sessions kept re-deciding whether
      they were fixed.
- [ ] `regression.ps1 -Dataset All` - REQUIRED before the PR: mode 2 now sets
      `OSPREY_ALLOW_UNFIXED_RESIDENT=mdiag-full-resume` instead of the blanket, and that change
      is unexercised until this runs.
- [x] Opened **PR #4508**. Copilot reviewed on open (one finding: a stale class docstring in
      `ResidentPoolGuardTest` - real, fixed in 63f84b0b4).
- [x] `/code-review max`: 15 findings, verified individually. **The critical one:**
      `ResidentPaths.KNOWN_UNFIXED` had ZERO production readers - the guard compared the env value
      against `ResidentPoolTrigger`'s return and never consulted the committed list, so the ratchet
      was documentation, not a mechanism, and the `OspreyEnvironment` claim that "the ONLY way to
      re-admit one is to add it to the committed list" was false. Fixed in 3f289c368 along with the
      mdiag catch-all, the literal pinning, the two stale transfer-needs-the-pool docs, the
      typo-vs-unset ambiguity, and const->static readonly.
- [ ] **DECISION FOR BRENDAN**: revert the `projection-off` token? It breaks live A/B-oracle
      recipes (see the corrected audit below), and `GuardResidentPool` sits AFTER the per-file
      scoring loop (~6h36m into an 82-file run), so a refused run wastes most of a day. It was
      approved on the premise that CI keeps the two paths identical, which turned out false.
- [ ] Remaining review findings, deliberately not fixed here: `--fdrbench-pass both` pass-1 output
      and `OSPREY_DUMP_PERCOLATOR` were only working for transfer BECAUSE the regression forced the
      resident branch (both belong with #4507); `regression.ps1` mode 2 overwrites an
      operator-supplied token; guard placement should hoist to `ValidateArgs`; `FirstJoinTask`
      keeps an untested duplicate of the predicate.
- [ ] Brendan: TeamCity Perf/Regression on `pull/4508`, and the transfer mdiag HTML at
      `D:\test\Pilot-MTG-Tissue-May2026\runs\pass2-82-4way-transfer-guardfix\out.model-diagnostics.html`.

## Progress Log

### 2026-07-30 - Root-caused and fixed; gates pending

Branched off master `f823e95294` in `C:\proj\pwiz`. Found the regression present at all three
sites (the third, `PreCompactionPoolReason`, added by #4488 two days ago and not in the earlier
analysis). Reverted, extracted the testable core, extended the guard test. Pre-commit gate green.

Remaining: the Stellar byte-identity gate, then the 82-file transfer arm - which is the only
verifier that actually proves the defect fixed, since a unit test structurally cannot.

### 2026-07-30 (later) - Stellar PASS; 82-file arm CLEARS THE GUARD

Stellar byte-identity PASS on all three modes (blib 30,597,120 throughout - the golden did not
move, as required with transfer off by default).

82-file transfer arm launched detached (`Start-Process`, PID 17456) on a snapshot exe
(`D:\test\osprey-exe-snapshots\transferguard-20260730\`) so the build tree stays free. Out dir
`D:\test\Pilot-MTG-Tissue-May2026\runs\pass2-82-4way-transfer-guardfix\`. Needed
`OSPREY_VERSION_OVERRIDE=26.1.1.199` - the linked stage-1-4 `.osprey.task` markers pin that
version, and without it the resume invalidates and Stage 1-4 re-runs for hours.

**Criterion (a) PASS, the defect is fixed.** From `run.log`:
```
[15:26:15]  10     80     [TASK] PerFileScoring:skipping (outputs valid)
[15:28:29]  13731  23716  Streaming first-pass ingest from 82 file(s)...
```
It took the STREAMING path where master dies at ~25 s on `GuardResidentPool`, and it did so on
the exact failing path (`-LinkFrom` resume -> PerFileScoring skip -> `RehydrateFromOwnOutputs`).
Peak private 30.7 GB at t+19 min, tracking toward the ~42 GB reference, not the ~104 GB a
resident pool implies. Ladder + final peak pending completion (~3.5 h).

### FOLLOW-UP APPROVED (Brendan, 2026-07-30): ratchet the escape hatch

`OSPREY_ALLOW_UNBOUNDED_MEMORY` did not catch this regression - it MASKED it. It is a single
boolean with exactly one consumer (`ResidentPoolGuardError`), thrown over a predicate whose
trigger set can silently grow, and both pass-2 TODOs record developers routinely setting it to
get transfer running. So a re-broken memory bound looked like normal operating procedure for
ten days.

Approved replacement: `OSPREY_ALLOW_UNFIXED_RESIDENT`, a high-water ratchet.
- **Value names the path** (`=stage7-survivors`), never `1`. A different resident path errors
  even with the var set - one exemption, not amnesty.
- **A committed `static readonly` token set is the high-water mark**; anything off it hard-errors
  regardless of the env var. A unit test pins the set exactly, so shrinking it is a deliberate
  edit and GROWING it shows in review as the ratchet running backwards.
- **CI refusal is enforced, not implied**: reject the var when `TEAMCITY_VERSION` is present.
- Would have caught this bug: transfer would have needed to be ON the known-unfixed list, and
  #4438 had already taken it off - hard error in June instead of a boolean waving it through.

**Why the list has exactly one entry, and why it expires (Brendan)**: Stage 7/8's resident
survivor buffer (`PercolatorScorer.cs:569`, `FdrProjection.cs:291`) was never fully fixed
BECAUSE pass-2 Percolator is going away as an option - which is what the #4484 sprint is
expected to achieve. So this is not debt to pay down but debt with a named owner and an end
date; the sprint drives the list to empty and the env var to deletion.

Brendan's call on CI: if the ratchet reds TeamCity when the PR opens, that is the guard working;
fix it before merge rather than weakening the guard.

### 2026-07-30 (later) - Ratchet implemented; the audit corrected three of my own claims

**Implemented** (b5f59fe13, bc6d6e95a): `OSPREY_ALLOW_UNFIXED_RESIDENT=<token>` replaces the
blanket boolean; `Osprey.Core/ResidentPaths.cs` holds the five tokens with each one's tracking
issue; a resident path with NO token is refused unconditionally; `regression.ps1` mode 2 names
`mdiag-full-resume`; `ResidentPoolGuardTest` asserts the WHOLE list via `CollectionAssert` so a
addition reads as the ratchet running backwards. Gate green both times (556/556, inspection 0/0).

`OSPREY_FDR_PROJECTION=0` became its own token (`projection-off`) rather than keeping its
automatic exemption - it outranks the config-driven triggers because it selects the legacy
implementation for the whole run, but it must now be stated. That closes the last route to a
resident pool nobody had to ask for.

**Audit findings - three claims I made this session were wrong, all corrected:**
1. "Dangling TODO reference" - WRONG. `TODO-osprey_stage6_rescored_buffer_streaming.md` exists as
   `completed/TODO-20260727_osprey_stage6_rescore_streaming.md`; my glob missed the datestamp that
   active work adds. The comment was stale in a different way: it cited COMPLETED work as tracking
   what remains.
2. "Stage 7/8 is O(survivors), not a memory problem" - OVER-CORRECTED. It is not gated by
   `GuardResidentPool` (true), but #4486 is open and records SecondPassFDR as the whole-run peak
   at ~45 GB / 82 files. Today's arm peaked 41.3 GB, corroborating it.
3. "CI keeps the two projection paths identical" (accepting Brendan's premise) - NOT TRUE, but my
   supporting audit was ALSO WRONG and is corrected here. No CI leg sets `OSPREY_FDR_PROJECTION=0`
   (not regression.ps1, not ai/scripts, not a unit test), so the byte-identity claim is not
   re-verified by anything. **But I then generalized that to "nothing anywhere sets it", which is
   false**: `ai/.tmp/run-mdiag-ab3.ps1:24` sets it, as do `ai/.tmp/run-mb2-20file.ps1` and the open
   protocol in TODO-20260728 line 165. I had grepped `ai/scripts`, `ai/docs` and `pwiz` but NOT
   `ai/.tmp`. Caught by `/code-review`. Consequence: making projection-off require a token breaks
   those live A/B-oracle recipes, which is why reverting that token is now on the table.

**Also established**: `--model-diagnostics` is NOT one thing. The scale case was streamed by
#4420 (today's 82-file arm runs with mdiag on, streaming, 41.3 GB); only the full-resume batch
report remains (#4505). Sessions kept flipping between "fixed" and "broken" because both are
true of different paths.
