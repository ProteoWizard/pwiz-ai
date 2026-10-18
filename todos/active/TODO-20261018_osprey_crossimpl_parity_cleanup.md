# Restore Osprey cross-impl parity and finish the FirstPassFDR sprint follow-ups

## Branch Information
- **Branch**: (none yet - create `Skyline/work/YYYYMMDD_osprey_...` from master when a pwiz change is needed;
  Rust work goes on maccoss/osprey branches)
- **Base**: `master` (pwiz); `main` (maccoss/osprey)
- **Created**: 2026-10-18
- **Status**: Not started. Picks up from TODO-20261015_osprey_firstpassfdr_slimming (completed, PRs #4853,
  #4863, #4864).
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (none yet). Related open Rust PR: [maccoss/osprey#73](https://github.com/maccoss/osprey/pull/73).
- **Checkout**: `C:\proj\pwiz` (master), `C:\proj\osprey` (Rust, `main` at `d19be4c`)

## Objective

Brendan (2026-10-18): keep maintaining cross-impl parity with Rust while its cost stays low - it "seems to
be slipping a bit". Rust remains a reference only (never shape a C# design to it); maintaining parity means
keeping the comparison passing, by porting a deliberate C# change to Rust or by adjusting the comparator.

Out of scope (decided 2026-10-18): #4823 / #4848 (`PeptidePep`) belongs to the BiblioSpec I/O session
(`TODO-20261016_bibliospec_io_unification.md`, goal 3). The FirstPassFDR fan-out candidates (pass-1 scoring
as its own fan-out; training candidates into PerFileScoring) stay deferred.

## Tasks

### 1. maccoss/osprey#73 - Rust companion to pwiz#4860
- #73 (`fix/one-peak-per-mz-typed-from-mz`, Brendan, opened 2026-10-17, MERGEABLE, +798/-195): every
      library loads as one peak per m/z, typed from m/z with the C# (`pwiz.Common.Chemistry`) masses;
      `top_fragment_indices` tie-break by m/z; `.libcache` v2; `strip_flanking_chars` fix. Its body reports
      cross-impl Stellar single + all and Astral all OVERALL PASS at 1e-9 against pwiz#4860's head.
- pwiz#4860 merged 2026-10-18 (`5c5f3ae815`), so C# master now carries that change and Rust `main`
      does not: the cross-impl gate against Rust `main` is expected to drift until #73 merges.
- [ ] Verify: build Rust from #73's branch, run `Compare-EndToEnd-Crossimpl.ps1` Stellar Single + Astral All
      against current pwiz master. Then get #73 reviewed and merged (maccoss/osprey maintainer conventions -
      see osprey-development-guide; ask Brendan before pushing or merging).

### 2. Stage 4 feature drift (found 2026-10-18 by the DIAGNOSTICS.md parity recipe)
- Stellar file 20, C# at `aef1494771` (master, includes #4860) vs Rust `main` `d19be4c` (no #73), C# on
      Rust's calibration: entry_ids 482,885 common, 6 Rust-only, 5 C#-only; 496 shared candidates pick a
      different apex scan (`scan_number`, `apex_rt`, bounds and peak features follow); some features differ
      beyond 1e-6 on more rows (`mass_accuracy_deviation_mean` 15,301, `abs_mass_accuracy_deviation_mean`
      4,187, `explained_intensity` 4,005, `median_polish_cosine` 3,373, `xcorr` 2,529, `cwt_candidates`
      2,934). Exact: entry_id, is_decoy, sequence, charge, precursor_mz, protein_ids, the two MS1 features.
      Representation-only (not parity): `modified_sequence` (UniMod vs +mass), `fragment_mzs` /
      `fragment_intensities` (binary lists). The end-to-end gate still passed at 1e-9 before #4860 merged.
- [ ] FIRST re-run the recipe with Rust built from #73: fragment typing/merging and top-N tie-breaks are
      exactly what moves fragment-based features and apex choice. Only what survives that is real drift.
- [ ] For a surviving difference: bisect per the osprey-development-guide (stage dumps), decide per case
      whether C# or Rust is right; port or adjust the comparator.

### 3. Small follow-ups
- [ ] Stamp-check FirstPassFDR's analysis-wide products on load: `Stage6ConsensusFile.Load` and
      `ScoringTaskShared.ReadRetainedBaseIds` read the files without checking the embedded
      `osprey_validity` stamp, so a stale file (an HPC node shipped an old one, a failed overwrite) drives
      planning / compaction and the outputs look current (#4863 /code-review finding 5).
- [ ] Optional: a Stage 4 `.scores.parquet` boundary in `ai/scripts/Osprey/Compare/Compare-EndToEnd-Bisect-Crossimpl.ps1`
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
