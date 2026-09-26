# TODO-20260925_osprey_libdecoy_pairing_collision.md

## Branch Information
- **Branch**: `Skyline/work/20260925_osprey_libdecoy_pairing_collision` (LOCAL in `C:\proj\pwiz-work1`, not pushed)
- **Base**: `Skyline/work/20260612_net8_port` (d9a3245ffd)
- **Created**: 2026-09-25 (night session, while A/B-testing pwiz #4703)
- **Status**: In Progress - code + unit tests done and committed locally; regression gate pending
- **Module**: `osprey`
- **PR**: none

## Problem

An 82-file SEA-AD LibDecoy run on Mike's original library (`sea-ad\lib\target+decoy+entrapment`,
2026-07-27) aborted after 4h19m in first-pass FDR:

> Experiment-scope values disagree across observations of entry_id 2147809020: ... peptide_q 1 vs 0.42 ...

Two different library decoys shared that entry_id: `AQLKDTR` z2 and `TDKLQAR` z2. Per-file dedup
(`ScoringPipeline.DeduplicatePairs`, keyed on base id) kept whichever scored better, so AQLKDTR
won in 61 files and TDKLQAR in 20, and one entry_id carried two peptides.

**Root cause** (`Osprey.IO/DecoyPairingManifest.ApplyToLibrary`): entries are bucketed by the
MANIFEST's kind, not by `entry.IsDecoy`. Carafe merged decoy `AQLKDTR` with an identical real
target (ProteinID `decoy_sp|Q8N653_p_target...|LZTR1...;sp|Q9Y250...|LZTS1`), so the prefix rule
made it a decoy (Id already carrying `DECOY_ID_BIT`) while the manifest lists AQLKDTR as the
TARGET of pair 76886. Its reversed decoy TDKLQAR was paired to it and copied `Id | DECOY_ID_BIT`
= the same id. Rust `crates/osprey-io/src/pairing.rs` `apply_to_library` has identical logic.

**It is old, not new.** The 2026-08-11 run on the same library (build 26.1.1.223) logged the same
~26 `Deduplicated` removals per file and completed - silently wrong. #4621 (2026-08-31) added the
experiment-scope check that turned it into a late abort. The 08-17 rebuild
(`target+decoy+entrapment-20260817`, the library CHS / TDP-43 / recent SEA-AD use) has zero such
rows out of 6,178,120 precursors; the 07-27 library has 35 (all Carafe merged-row class).

## Decision (Brendan, 2026-09-25)

Refuse the flawed library with a clear error listing EVERY offending row, rather than tolerate it:
we can now fix the library generator, so the provider should learn the library is wrong. Report
all rows, not the first (Skyline experience: first-only hides the class of defect).

## Commits (local)

- `d64e8356e7` Fixed library-decoy pairing letting two decoys share one entry_id (decoy never on
  the target side of a manifest pair) + `DecoyPairingManifestTest.ManifestNeverPairsADecoyAsTheTargetSide`
- `194910b231` Load-time shared-decoy-id check (fresh + cached paths); library cache v3 -> v4
  (a v3 cache stores the FINISHED, colliding pairing keyed only on the source hash)
- `b0cd1bbdf6` Refuse a library its manifest contradicts: `ManifestApplyStats.DecoysListedAsTargets`
  -> loader error listing all rows; backstop lists every shared-id group

Verified: 599/599 tests + zero-warning inspection; the Release build refuses the 07-27 library at
load with all 35 rows (`D:\test\osprey-runs\astral-entrap-3file\pairing-check-0727\run.log`).

## Remaining

- [x] `regression.ps1 -Dataset Stellar` on the branch: PASSED (12 phases, 22:54, under load)
- [x] StellarLibDecoy (18 phases) + StellarGenDecoyEntrap (12 phases): PASSED 23:55 - the legs that run
      manifest pairing, with the v4 cache rebuilt
- [ ] `regression-parallel.ps1` (-Dataset All) before merge; the Astral leg (generated decoys) was skipped overnight
      via `regression-parallel.ps1` - the cache bump rebuilds every regression library cache once
- [x] Rust counterpart: LOCAL branch `fix/libdecoy-pairing-collision` in C:\proj\osprey, commit
      `a4d29fb` (off main b9ec678). Same refuse + backstop, same message text; fmt/clippy/test
      gate passed; test failed before the fix. No Rust cache bump: its .libcache holds the
      library BEFORE pairing. Carries the pwiz-ai hook's Co-Authored-By trailer - amend it off
      before pushing (upstream commits have none). Needs Mike's PR on maccoss/osprey.
- [ ] Proposal, not done: the 07-27 library also left 61,494 decoys unpaired (08-17: 1,628); a
      stricter default `DecoyPairMinFraction` would have flagged that library too
- [ ] `/code-review`, then PR against the port branch
