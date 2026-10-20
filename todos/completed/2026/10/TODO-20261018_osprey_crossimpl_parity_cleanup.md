# Restore Osprey cross-impl parity and finish the FirstPassFDR sprint follow-ups

## Branch Information
- **Branch**: `Skyline/work/20261019_osprey_firstpass_stamp_check` (pwiz, task 3a)
- **Base**: `master` (pwiz); `main` (maccoss/osprey)
- **Created**: 2026-10-18
- **Status**: Completed - task 3a merged as #4875 (2026-10-19), the comparator and bisect-driver
  fixes done on this branch's session. Picks up from TODO-20261015_osprey_firstpassfdr_slimming (completed, PRs #4853,
  #4863, #4864).
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: [#4875](https://github.com/ProteoWizard/pwiz/pull/4875) (merged 2026-10-19) (task 3a, opened 2026-10-19 on
  Brendan's go-ahead, rebased onto master at #4868; TeamCity Perf/Regression on ask). Related Rust PR: [maccoss/osprey#73](https://github.com/maccoss/osprey/pull/73) (merged 2026-10-18).
- **Checkout**: `C:\proj\pwiz` (master), `C:\proj\osprey` (Rust, `main`; #73 merged as `64e37ae828`, local checkout still `d19be4c` - pull)

## Objective

Brendan (2026-10-18): keep maintaining cross-impl parity with Rust while its cost stays low - it "seems to
be slipping a bit". Rust remains a reference only (never shape a C# design to it); maintaining parity means
keeping the comparison passing, by porting a deliberate C# change to Rust or by adjusting the comparator.

Out of scope (decided 2026-10-18): #4823 / #4848 (`PeptidePep`) belongs to the BiblioSpec I/O session
(`TODO-20261016_bibliospec_io_unification.md`, goal 3). The FirstPassFDR fan-out candidates (pass-1 scoring
as its own fan-out; training candidates into PerFileScoring) stay deferred.

## Tasks

### 1. Cross-impl gate on current master vs Rust main
- pwiz#4860 (one peak per m/z, typed from m/z with the C# masses, top-N tie-break by m/z) merged to master
  2026-10-18 (`5c5f3ae815`); its Rust companion maccoss/osprey#73 merged 2026-10-18 (`64e37ae828`, Brendan).
  #73's own runs passed against #4860's head; nobody has run the gate since both landed.
- [x] Pull Rust `main`, build both sides (C# Release), run `Compare-EndToEnd-Crossimpl.ps1` Stellar Single and
      Astral All against current pwiz master. PASS at 1e-9 is the expectation; a FAIL is real drift to bisect.
      Stellar Single PASS at 1e-9 (pwiz `1be16fdafe` incl. #4865, Rust `64e37ae`; 26,812 precursors each).
      Astral All PASS at 1e-9 (118,314 precursors each; walls Rust 19:32, C# 06:50).

### 2. Stage 4 feature drift (found 2026-10-18 by the DIAGNOSTICS.md parity recipe)
- Stellar file 20, C# at `aef1494771` (master, includes #4860) vs Rust `main` `d19be4c` (no #73), C# on
      Rust's calibration: entry_ids 482,885 common, 6 Rust-only, 5 C#-only; 496 shared candidates pick a
      different apex scan (`scan_number`, `apex_rt`, bounds and peak features follow); some features differ
      beyond 1e-6 on more rows (`mass_accuracy_deviation_mean` 15,301, `abs_mass_accuracy_deviation_mean`
      4,187, `explained_intensity` 4,005, `median_polish_cosine` 3,373, `xcorr` 2,529, `cwt_candidates`
      2,934). Exact: entry_id, is_decoy, sequence, charge, precursor_mz, protein_ids, the two MS1 features.
      Representation-only (not parity): `modified_sequence` (UniMod vs +mass), `fragment_mzs` /
      `fragment_intensities` (binary lists). The end-to-end gate still passed at 1e-9 before #4860 merged.
- [x] Re-run the recipe with Rust `main` (now carrying #73): fragment typing/merging and top-N tie-breaks
      are exactly what moves fragment-based features and apex choice. Only what survives that is real drift.
      Nothing survives: 482,886 entry_ids common, 0 one-sided; every column equal at 1e-6 except
      `modified_sequence` notation. Expected state recorded in DIAGNOSTICS.md.
- [x] For a surviving difference: bisect... - none survived.

### 3. Small follow-ups
- [x] (Branch `Skyline/work/20261019_osprey_firstpass_stamp_check`, uncommitted, 644 tests + inspection
      green.) Consistency check, since a reading node cannot rebuild FirstPassFDR's key (its
      `LibraryFragmentRelease` term records the writing leg): stamp names FirstPassFDR of this build,
      and consensus + retained carry the same stamp where both are present. Not anchored on the model
      file (best-effort write). Test: `FirstPassModelIoTest.TestFirstPassProductsLoadOnlyFromThisBuildAndOneRun`.
      Original item: Stamp-check FirstPassFDR's analysis-wide products on load: `Stage6ConsensusFile.Load` and
      `ScoringTaskShared.ReadRetainedBaseIds` read the files without checking the embedded
      `osprey_validity` stamp, so a stale file (an HPC node shipped an old one, a failed overwrite) drives
      planning / compaction and the outputs look current (#4863 /code-review finding 5).
- [x] Fixed the bisect driver (2026-10-19); Stellar 3-file 15/15 boundaries PASS. Was: an
      optional Stage 4 `.scores.parquet` boundary in `ai/scripts/Osprey/Compare/Compare-EndToEnd-Bisect-Crossimpl.ps1`
      using `parquet_diff.py --common-entries`. Its "rewritten in place at Stage 6" note is stale for C#,
      which writes `.scores-reconciled.parquet`; check whether Rust still rewrites in place (else it needs
      a `--no-join` Rust pass).

## Reference
- Parity recipe: `ai/scripts/Osprey/DIAGNOSTICS.md` ("Main-search feature parity"), verified 2026-10-18
  (pwiz-ai `56d4575a`: Run-Osprey Rust PATH fix, `parquet_diff.py --common-entries`).
- End-to-end gate: `ai/scripts/Osprey/Compare/Compare-EndToEnd-Crossimpl.ps1` (+ README). Last PASS:
  #4863 head `a4504c59ac` vs Rust `d19be4c` (Stellar 1 + Astral 3 at 1e-9); #4864 Stellar 1 at 1e-9.

## Progress Log

### 2026-10-18 - Created
- Split from the completed FirstPassFDR sprint. Recipe run artifacts: `D:\test\osprey-runs\feature-parity-20261018_064838`
  (rust/, csharp/), diff `ai/.tmp/sessions/20261016-b2pr/parquet-diff-common.log`.
- **Next session handoff**: For detailed startup protocol, read `ai/.tmp/handoff-20261018_osprey_crossimpl_parity.md` before starting work.

### 2026-10-18 (afternoon) - Gate and feature parity re-run
- Pulled Rust `main` (`64e37ae`, #73) and pwiz master (`1be16fdafe`, now also #4865: `.blib` replaces
  `.libcache`). Built both (C# Release). Logs: `ai/.tmp/sessions/20261018-xparity/`.
- Stellar Single gate PASS at 1e-9 (`pwiz_tools/Osprey/TestResults/crossimpl-stellar/`).
- Feature-parity recipe: drift fully explained by #73. Run `D:\test\osprey-runs\feature-parity-20261018_130553`,
  diff `ai/.tmp/sessions/20261018-xparity/feature-parity.log`. DIAGNOSTICS.md note updated.
- Task 3b finding: Rust still rewrites `.scores.parquet` in place (`crates/osprey/src/rescore.rs:637`), but C#
  writes Stage 6 to `.scores-reconciled.parquet` (survivor subset + row-ordinal column). So the bisect
  driver's existing Stage 6 boundary compares Rust Stage 6 against C# Stage 4 and cannot pass. Its
  `Stage-DatasetFiles` also still copies a `.libcache` (inert since #4865).

### 2026-10-19 - Stamp check, review, bisect driver, #4848 comparator drift
- 3a committed on `Skyline/work/20261019_osprey_firstpass_stamp_check`: `9e27d633bc` + review fixes
  `a1edb1db89` (/code-review medium: 9 findings, fixed 4 - experiment sidecar added to the
  sibling set, unreadable sibling skipped not blamed, remedy on the consensus refusal, test gaps;
  dropped 5 with reasons in the session). 644 tests + inspection green. Not pushed; no PR yet.
- Gate on Stellar All (new: never run before) FAILED on blib `Proteins`/`RefSpectraProteins`. Root
  cause: #4848 (merged after the morning's gate runs) made C# write parsimony protein GROUPS there,
  tagged [INTENTIONAL-CSHARP-DESIGN] in docs/13, but `Compare-Blib-Crossimpl.ps1` was never
  updated - the gate failed on master for every dataset. Comparator now skips both tables
  (protein inference still compared at Stage 7); README records the accepted divergence.
- Bisect driver rebuilt: Stage 4 boundary (Rust `--no-join` pass vs C# `.scores.parquet`), Stage 6
  against C# `.scores-reconciled.parquet` (`parquet_diff.py --b-subset --ignore-columns`), FDR
  sidecars via `Compare-FdrSidecars-Crossimpl.ps1` (SHA was meaningless since #4486), data and
  workdir resolved like the gate (`TestResults/crossbisect-<dataset>`), no `.libcache`.
- Found while there: Stage 3 / reconciliation boundaries read `$LASTEXITCODE` after
  `| Select-Object -First 1`, which stops the pipeline before the exit code is set - they reported
  stale PASSes. `calibration_diff.py` had always failed on real data (Rust-only mass `histogram`,
  C#-only `rt_search_window_halfwidth`); `reconciliation_diff.py` on modification notation. Both
  now drop those one-sided / notation-only fields.
- With the comparator fix, on master + branch (incl. #4848): gate Stellar All PASS (blib re-compared),
  Astral All PASS at 1e-9 (118,314 precursors each). Remaining: push the pwiz branch and open the PR
  (Brendan's call), then TeamCity on ask.
- **Opened as #4875** (2026-10-19 evening, Brendan: "Go ahead with a new PR for the stamp check" once
  #4867 and #4868 had merged; he held the branch back so it would not slow that chain). Rebased onto
  master at 394c5e364e before the push (pre-PR, so a rebase; commits now 3e726e7775 + 20cc4ab965);
  gate on the rebased tree Osprey Debug 644/644 + inspection clean. Not triggered: the TeamCity
  Perf/Regression config (ask first). Next: TeamCity's PR checks, then the Perf/Regression run when
  Brendan calls it, then `/pw-complete`.

### 2026-10-19 - Merged

PR #4875 merged as commit 954c2faee2 (night session, squash message approved by Brendan). All 16
checks green, including TeamCity Perf/Regression build 4226409 on head 20cc4ab965. Shipped: the
stamp check on FirstPassFDR's analysis-wide products (task 3a). Tasks 1, 2 and the bisect-driver and
comparator fixes landed in pwiz-ai during the sprint. Nothing deferred; no follow-up issues filed.
