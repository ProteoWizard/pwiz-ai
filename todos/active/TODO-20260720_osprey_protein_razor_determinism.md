# TODO: Osprey protein parsimony razor rollup determinism

## Branch Information
- **Branch**: TBD -- to be cut fresh from `master` (see "Landing plan" below). NOT the
  current `Skyline/work/20260709_osprey_sparse_xcorr_cache` checkout, which is 29 commits
  behind master and an unrelated topic.
- **Base**: `master`
- **Created**: 2026-07-20
- **Status**: Fix written + unit-tested locally; NOT yet on a branch, NOT committed.
  Awaiting a free machine (a second session is on the Rust osprey tree) and a clean
  master-based branch before running the full dataset gates + PR.
- **Issue**: [#4441](https://github.com/ProteoWizard/pwiz/issues/4441)
- **Reported by**: Mike

**Priority**: Medium -- correctness/determinism bug, but on the non-default `--shared-peptides
razor` path (default is `all`), so it does not affect the certified Stellar/Astral output.

## The problem (code-traced)
`Osprey.FDR/ProteinFdr.cs`, `SharedPeptideMode.Razor` case (old: ProteinFdr.cs:432-467 on this
checkout; byte-identical at origin/master:513-547): the razor rollup assigns each shared peptide
independently, walking the shared peptides in `Dictionary<string,...>` (hash) enumeration order,
picking each peptide's current best group and mutating unique counts in place. Two defects:
1. **Non-deterministic across processes** -- under .NET randomized string hashing, `Dictionary`
   enumeration order is not stable run-to-run, so the protein rollup can vary between identical runs.
2. **Diverges from Rust** -- Rust `osprey-fdr/src/protein.rs` uses an iterative **group-batch**
   greedy set cover (pick the max-unique group owning an unassigned shared peptide, claim ALL of
   its remaining shared peptides in sorted order, repeat). The winner is chosen globally per round,
   so it is path-independent. The per-peptide greedy flips on cascading topologies
   (`G0 u{A,B} s{X,Y}`, `G1 u{C,D,E} s{X}`, `G2 u{F} s{Y}`: Rust => `X->G1, Y->G0`; old C# gives
   `X->G0` when `Y` is processed first and inflates G0's unique count to tie G1 on X).

Found during a C#/Rust algorithm-doc parity audit of `pwiz_tools/Osprey`
(`pwiz_tools/Osprey/algorithms-docs/` + `DIVERGENCES.md`, item P1 / U8). It was the ONLY
genuine PORT-ERROR that survived scrutiny across all 18 audited docs.

## The fix (written, unit-tested; patch at ai/.tmp/razor-determinism-20260720.patch)
Reimplemented the `Razor` case as the iterative group-batch set cover mirroring Rust:
- Collect shared peptides, `Sort(StringComparer.Ordinal)` (matches Rust's byte-wise String sort).
- `unassigned = HashSet(shared)`. While non-empty: iterate `resultGroups` ascending group id,
  pick the group with the most `UniquePeptides` that still owns an unassigned shared peptide
  (strict `>` over ascending ids => lowest-id tiebreak, matching Rust `max_by_key((len, Reverse(id)))`).
  Claim that group's still-unassigned shared peptides in ordinal-sorted order; for each, remove from
  every group's shared set, add to the winner's unique set, repoint `peptideToGroups`, mark assigned.
- Unique count read live, so peptides claimed in earlier rounds raise a group's count for later
  rounds (the greedy cascade), exactly as Rust does.
- Default remains `all` (unchanged); `unique` mode unchanged.

Files: `Osprey.FDR/ProteinFdr.cs` (razor case rewrite), `Osprey.Test/FdrTest.cs` (+2 tests).

## Validation done (this checkout, stale branch)
- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection`: build green; my two changed
  files are inspection-clean (the 2 pre-existing `RedundantNameQualifier` warnings are in
  `PerFileScoringTask.cs`, untouched, from this stale branch).
- `Build-Osprey.ps1 -RunTests -TestName Razor`: 3/3 PASS --
  `TestSharedPeptidesRazorMode` (pre-existing), `TestSharedPeptidesRazorCascadingAssignment` (new,
  pins the deterministic cascade), `TestSharedPeptidesRazorDeterministicAcrossInputOrder` (new,
  forward vs reversed input => identical rollup).
- Confirmed the bug is still present on `origin/master` (fix genuinely needed there).

## Landing plan (do when the machine is free + on a fresh branch)
1. Cut `Skyline/work/YYYYMMDD_osprey_protein_razor_determinism` from an up-to-date `master`
   (this checkout is 29 behind; the razor block is byte-identical on master so the patch applies).
2. Apply `ai/.tmp/razor-determinism-20260720.patch` (or re-do the small edit on master's files).
3. `Build-Osprey.ps1 -RunTests -RunInspection` green.
4. Run the dataset gates (below).
5. Open PR early (`gh pr create`, `Fixes #4441`), then `/pw-self-review`, then human review +
   the manual TeamCity Perf/Regression trigger on `pull/<N>`.

## Gates (before merge to master)
- **`regression.ps1 -Dataset All`** (Stellar + Astral, mode 1/2/3) **byte-identical** -- proves the
  change is INERT on the default (`all`) pipeline (razor is off the default path, so the golden must
  not move). This is the safety gate, not a razor-behavior gate.
- **Cross-impl razor run vs Rust** (`--shared-peptides razor`, Stellar + Astral): confirm the C#
  protein rollup now MATCHES Rust (the actual behavior gate). Needs a Rust build -- coordinate with
  the concurrent Rust session so the two don't contend / clobber the Rust tree.
- **`Build-Osprey.ps1 -RunTests -RunInspection`** green (0 warnings), including the 2 new razor tests.
- Consider a repeat-run determinism check (run razor twice, assert identical rollup) at dataset
  scale to prove the cross-process stability, mirroring Rust `test_shared_peptides_razor_deterministic`.

## Notes / related
- This came out of the algorithms-docs audit; `pwiz_tools/Osprey/algorithms-docs/DIVERGENCES.md`
  should be updated to mark P1/U8 RESOLVED once this lands (and U1 calibration resolved via #4402,
  U6 as a stale docstring, U5 as merge-lag) -- those docs were generated against this 29-behind
  checkout and over-report "C# lacks X" gaps. See the doc-refresh follow-up.
- The uncommitted fix currently lives in the working tree of `C:\Dev\pwiz`
  (`ProteinFdr.cs` + `FdrTest.cs`, unstaged) on the `sparse_xcorr_cache` branch. Do NOT commit it
  there; move it to the fresh branch. Patch backup: `ai/.tmp/razor-determinism-20260720.patch`.
