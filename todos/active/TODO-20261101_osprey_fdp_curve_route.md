# TODO-20261101_osprey_fdp_curve_route.md

## Branch Information
- **Branch**: `Skyline/work/20261101_osprey_fdp_curve_route`
- **Base**: `master`
- **Created**: 2026-11-01
- **Status**: PR open - guard added; #4645 fixed by #4860 (see Progress Log)
- **GitHub Issue**: [#4645](https://github.com/ProteoWizard/pwiz/issues/4645)
- **Module**: `osprey`
- **PR**: [#4966](https://github.com/ProteoWizard/pwiz/pull/4966)
- **Worktree**: `D:\Dev\pwiz-fdpcurve`

## Objective

The HPC 4-task chain and straight-through disagreed on `.fdpViews[].paired[]` of
`output.2nd-pass.model-diagnostics.json` on StellarGenDecoyEntrap (~1.4%, chain lower,
496 paths, lengths 115,735 vs 115,740). Re-measure on current master, name the cause or
the change that fixed it, and add a mode-3 guard so the agreement cannot silently regress.

## Tasks
- [x] Reproduce on master: StellarGenDecoyEntrap with mode 3 un-cut (it is in SkipModes since #4728), diff paired
- [x] Identical -> name the fixing change with code evidence; different -> bisect the estimator inputs
- [x] Add the mode-3 guard comparing fdpViews[].paired straight vs chain
- [x] Review, gates, PR, status comment on #4645

## Progress Log

### 2026-11-01
- Context changes since filing: StellarGenDecoyEntrap now passes the pairing manifest
  (since 2026-10-17), and mode 3 is in its SkipModes (#4728), so the gate as committed
  never runs the chain on this dataset. Pairing is now `EntrapmentPairing.Build(libraryById)`
  reading `LibraryEntry.PairingId` (library-level, #4679), no manifest argument.
- Repro run: regression.ps1 -Dataset StellarGenDecoyEntrap -SkipResume -SkipWarmRerun with
  SkipModes temporarily set to @() (local edit, not committed). Log:
  `C:\proj\ai\.tmp\sessions\20261101-fdpcurve\repro1.log`
- Hypothesis checked and ruled out: straight-through drops targets DecoyGenerator cannot
  pair (`library = validTargets`) while chain phase 4 skips decoy generation, so their
  `libraryById` could differ. On this dataset the straight log reports "Generated 484,208
  decoys from 484,208 targets (0 excluded due to collisions)", so the two libraries hold
  the same targets.
- **Not reproduced on master 728ff3a131.** repro1 (all legs PASS, straight wall 03:38, chain
  08:46): `output.2nd-pass.model-diagnostics.json` straight vs chain phase 4 is
  BYTE-IDENTICAL (117,360 bytes each; `fdpViews[0..1].paired` 470 points each, max rel diff 0).
  The 1st-pass product differs in 2 bytes, `generatedUtc` only.
  Run dir: `D:\Dev\pwiz-fdpcurve\pwiz_tools\Osprey\TestResults\regression-20261101_200425_189700\StellarGenDecoyEntrap`
  (straight\ and chain\phase4_SecondPassFDR\). Diff script:
  `C:\proj\ai\.tmp\sessions\20261101-fdpcurve\diff_paired.py`.
- Candidate fixing change: #4860 (5c5f3ae815, 2026-10-18) did two things at once: gave this
  dataset its pairing manifest, and replaced `EntrapmentPairing.Build(libraryById, manifestPath)`
  (no manifest -> every distinct sequence a fresh `nextStandalone++` index, assigned in
  `libraryById` enumeration order) with load-time `LibraryEntry.PairingId` (PairingIds.Assign in
  the loader). repro2 runs the parent commit 5671b0c46f (worktree detached there, mode 3 un-cut
  locally) to confirm the difference still reproduced before it. Log:
  `C:\proj\ai\.tmp\sessions\20261101-fdpcurve\repro2-pre4860.log`
- **Reproduced at the parent of #4860 (5671b0c46f)** (repro2, all legs PASS, straight 04:13,
  chain 11:37): pass-2 `fdpViews[].paired` differs on 507 paths, max relative difference 9.1%
  (experiment view) and 2.3% (per-run view), chain lower; first differing
  `.fdpViews[0].paired[221]` straight 0.000500136 vs chain 0.000454669. Pass 1 identical apart
  from generatedUtc. Element counts are equal (470 per view); the issue's "115,735 vs 115,740
  lengths" were JSON BYTE lengths (here 119,798 vs 119,779), not 5 extra precursors.
  Artifacts kept: `D:\test\osprey-runs\20261101-fdpcurve\pre4860-5671b0c46f\`.
- **Root cause (old code):** `EntrapmentLibraryClassifier.IsDecoySide(ProteinIds)` recognized a
  decoy only by the ordinal `decoy_` accession prefix (Carafe's library-decoy convention), but
  `DecoyGenerator` names generated decoys `DECOY_` + accession. So wherever `libraryById` held
  generated decoys, `BuildClassificationFromLibrary` and `EntrapmentPairing.Build` walked them
  as target-side entries: each decoy got its own pair index by sequence and, sharing its
  target's base id and enumerated after it, overwrote `pairByBaseId[baseId]` (and
  `classByBaseId`, with the same class since `DECOY_` + accession keeps `_p_target`, which is
  why n_t, n_p, fdp, combined all matched). Straight-through's pass 2 and both routes' pass 1
  (chain phase 2 generates decoys too) had the decoys; chain phase 4 (`--task SecondPassFDR`,
  `ExpectReconciledInput`) skips DecoyGenerator, so its pairing came from the targets alone.
  Only pass 2 on the chain differed - exactly the observed pattern.
- **Fixed by #4860 (5c5f3ae815, 2026-10-18)**, which added
  `IsDecoySide(LibraryEntry entry) => entry.IsDecoy || IsDecoySide(entry.ProteinIds)` ("a
  generated decoy is flagged but carries Osprey's DECOY_ prefix, not the manifest's") and
  switched `EntrapmentPairing.Build`, `PairingIds.ExcludedEntrapment` and
  `BuildClassificationFromLibrary` to it, with pairing read from load-time
  `LibraryEntry.PairingId`. Both routes now skip the same decoy entries and read the same ids.
  #4679 and the October resident-pool PRs were not the fix (the difference persists at
  5671b0c46f, after all of them).
- Latent route asymmetry left (from code reading, not measured; no effect on any regression dataset; for Brendan): straight-through
  drops targets DecoyGenerator cannot make a decoy for (`library = validTargets`), chain phase 4
  keeps them because it skips decoy generation. `PairingIds.ExcludedEntrapment` reads that library,
  so an entrapment whose only original target was dropped is an orphan (excluded) straight-through
  but paired on the chain, which would move n_p and the pass-2 FDRBench files. 0 exclusions on
  StellarGenDecoyEntrap, so not reachable on the gate data.
- Guard: `Compare-FdpViews` in Regression/DiagnosticsGolden.ps1 (every view of both passes, every
  array, $Tolerance, NaN==NaN), called in mode 3 as `mode3 (chain FDP curves==straight)`; row
  `3fdp` in Write-RegressionMatrix.ps1 and regression.html (runs on StellarLibDecoy; Astral has
  no views; mode 3 stays cut on StellarGenDecoyEntrap). Offline check on the two repro runs:
  master PASS (4 views, 1,880 paired points), pre-#4860 FAIL with exactly 507 issues
  (`C:\proj\ai\.tmp\sessions\20261101-fdpcurve\guard-offline.log`).
- Pre-commit: Build-Osprey Debug -RunTests -RunInspection, 646/646 passed
  (`C:\proj\ai\.tmp\sessions\20261101-fdpcurve\precommit.log`).
- Review (fresh general-purpose agent, medium, diff `C:\proj\ai\.tmp\sessions\20261101-fdpcurve\guard.diff`):
  no defects. Taken: string scalars compared with `-ceq` (a label differing only in case would
  have passed `-eq`). Dropped: (a) a nested-object view property would compare by reference -
  views hold only scalars and arrays today, and such a change would fail loudly, not pass;
  (b) views matched by position rather than label - can only over-report, never miss a
  difference. Offline re-check after the change: pre-#4860 still FAIL with 507 issues
  (`guard-offline-ceq.log`).
- Gate 1 StellarLibDecoy ABORTED at the new line (`gate-libdecoy.log`): `$summaryLines.Add((..) -f a, b)`
  - the comma inside Add(...) ends the -f argument list ("Index ... less than the size of the
  argument list"). Every leg before it PASSED. Fixed by formatting into a variable first; the
  exact new statements run on that run's reports give `PASS (4 views, 1,880 paired points)` and
  on the pre-#4860 reports `FAIL (507 issues)` (`callsite-libdecoy.log`). Lesson: the offline
  check exercised the function, not the call site. Re-running StellarLibDecoy end to end.
- Gates (commit 5e179cecaa): StellarLibDecoy all legs PASS incl. `mode3 (chain FDP curves==straight):
  PASS (4 views, 1,880 paired points)` (`C:\proj\ai\.tmp\sessions\20261101-fdpcurve\gate-libdecoy2.log`);
  StellarGenDecoyEntrap all legs PASS (`gate-gendecoy.log`); `Write-RegressionMatrix.ps1 -VerifyAgainst`
  both logs, 18 + 12 summary lines, exit 0 (`matrix-verify.log`). No C# changed, so no Stellar gate.
- Decision for Brendan: mode 3 stays cut on StellarGenDecoyEntrap (#4728's coverage cut), so the
  guard runs on StellarLibDecoy only. Since #4860 both datasets reach the same pairing code, but
  generated-decoy behavior across the chain (incl. the latent ExcludedEntrapment asymmetry above)
  is only covered if mode 3 is un-cut there (~9-12 min more per full gate).
- Status comment posted on #4645: https://github.com/ProteoWizard/pwiz/issues/4645#issuecomment-6570082381
