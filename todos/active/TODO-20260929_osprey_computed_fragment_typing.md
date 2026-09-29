# TODO-20260929_osprey_computed_fragment_typing.md

## Branch Information
- **Branch (PR 1)**: `Skyline/work/20260929_osprey_stacked_mod_decoys` (checkout `C:\proj\pwiz-work1`)
- **Branch (PR 2)**: (not yet created)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Created**: 2026-09-29
- **Status**: In Progress - PR 1 built and unit-tested; regression-parallel All running
- **Module**: `osprey`
- **PR (PR 1)**: (pending)
- **PR (PR 2)**: (pending)
- **Replaces**: PR #4730, which is closed once both PRs below are open (see "Closing #4730")
- **Source of the code**: #4730's head, `Skyline/work/20260928_osprey_blib_annotations` @ 2e88e21746
  (checkout `C:\proj\pwiz-work1` on Brendan's machine)
- **Related**: #4708 (Mike, part B, stacked on #4730 - must re-stack on PR 2); maccoss/osprey#71
  (Rust, stacked-mod decoys) and #72 (Rust, sorted blib peaks); #4736 (UniMod);
  `TODO-carafe_osprey_library_contract.md`; `TODO-20260923_osprey_carafe_export.md`
- **Objective**: A full replacement for #4730 as two PRs, so #4730 can be closed without losing
  anything worth keeping:
  1. **PR 1 - stacked-modification decoy fix**: small, independent, ready.
  2. **PR 2 - Osprey-computed fragment typing and BLIB writing**: Osprey types library fragment
     peaks itself, from m/z, the way Skyline does, and never takes ion types from a library's
     annotations; plus the BLIB writing that is worth keeping (`--export-library`, one shared
     LibraryEntry-to-blib composition, m/z-sorted peaks), without annotation rows.

## Why (Brendan, 2026-09-29)

> "We are not going to merge 4730. It turns a corner-case small molecule feature into something in
> every BLIB file from and for Osprey. Let's start working on a replacement that treats peak
> annotating as something Osprey must do for itself, as Skyline does."

> "I think it is far better to have the software work out the peak annotations that to simply
> accept library annotations."

> "there are things in it we will want to keep, like the ability to export anything we can load
> into libcache as a .blib file."

Background, established 2026-09-28/29:
- `RefSpectraPeakAnnotations` exists in BLIB for small molecules (LipidCreator, Skyline's own
  small-molecule libraries), where Skyline has no fragmentation model. For peptides Skyline ignores
  it: "for peptides, we can generate our own fragment info" (`BiblioSpecLite.ReadPeakAnnotations`).
  Skyline's `BlibDb` writes rows only for small-molecule ions; BiblioSpec `BlibBuild` never creates
  them (it only copies them, and that copy is broken - below); its `TSVReader` reads DIA-NN's
  `aggr_Fragment_Annotation` only for peak areas.
- The original Carafe (Noble-Lab and maccoss forks) creates the table EMPTY
  (`SkylineIO.java:128-155`, "// Empty table"). Annotated blibs started with CarafeSharp (M3) and
  #4730 part A added the Osprey reader - per-fragment typing carried over from formats that have it
  (DIA-NN TSV columns, NIST `.msp`, SpectraST `.sptxt`).
- Nothing downstream reads Osprey's output annotations: CarafeSharp takes identifications from
  Osprey's blib and fragment evidence from the training export (#4708). The only annotation flow was
  CarafeSharp -> Osprey, and those peaks sit at theoretical b/y m/z Osprey can compute.
- Cost measured on the #4730 final regression output blibs (vacuumed, with and without the rows):
  Stellar 3-file 59.9 MB -> 27.4 MB without (annotations 54% of the file, 628,687 rows = every
  peak); Astral 3-file 181.3 MB -> 95.5 MB (47%, 1,617,620 rows); ~52 B/row with the index.
  CarafeSharp's 483k-precursor library carries 7,977,491 rows (~400 MB at that rate).
- BiblioSpec `BlibMaker::transferPeakAnnotations` (BlibMaker.cpp:1025-1039) formats the text
  columns into its INSERT unquoted, so `BlibBuild` cannot merge ANY blib with annotation rows.
  Not needed once Osprey writes none, but still a BiblioSpec bug for small-molecule libraries
  (fix: `sqlite3_snprintf` + `%Q`); separate pwiz PR if pursued.

## PR 1 - stacked-modification decoy fix

**The bug.** Two modifications on one residue - typically an N-terminal acetyl and an oxidized
first Met, `(UniMod:1)M(UniMod:35)...`, both of which the loaders put at position 0. When
`DecoyGenerator` recomputed a decoy fragment's m/z it built its position-to-mass map with
`modMasses[newPos] = m.MassDelta`, so the second modification REPLACED the first. Every decoy ion
spanning that residue lost one modification's mass (42.0106 Da light for acetyl) while the decoy's
precursor m/z stayed right: decoys with fragments no real peptide makes, easier to beat than a
proper decoy, biasing target-decoy competition for acetylated N-termini.

**The fix** (Mike, #4730 commit 152da04268): the map comes from
`PeptideFragmentMass.ModMassesByPosition(RemapModifications(target.Modifications, positionMapping))`,
which SUMS masses per position - the same helper the target side uses.

Contents:
- `Osprey.Core/PeptideFragmentMass.cs` - extracted from `DecoyGenerator` (pure code motion; TSV
  decoys byte-identical apart from the fix)
- `Osprey.Scoring/DecoyGenerator.cs` - the fix, decoy modifications remapped once, and the move of
  fragment m/z to `PeptideFragmentMass`
- `;decoymods=2` (`OspreyTask.DECOY_MODS_TERM`) in every task key when Osprey generates decoys, and
  `LibraryLoader.LibrarySuppliesDecoys` as the one definition of "the library supplies decoys"
  (`PerFileScoringTask` uses it)
- `Osprey.Test/DecoyConstructionTest.DecoyFragmentCarriesStackedModifications` (red before green:
  b8 42.0105 Da light without the fix); the `TaskValidityKeyTest` legs for `;decoymods=2`
- `docs/01-decoy-generation.md` (CalculateFragmentMz's new home; the stacked-mod rule)
- Rust companion: maccoss/osprey#71 (open)

Tasks:
- [x] Branch from the port branch; bring over the files above from #4730, nothing annotation-related
- [x] Gates: Build-Osprey Debug -RunTests -RunInspection; `regression-parallel.ps1 -Dataset All`
      (goldens did not move; one unreproduced calibration AV - see log); perf gate skipped (not hot path)
- [x] Cross-impl check with #71 on a library that HAS stacked mods (PASS; negative control FAILs)
- [ ] PR, `/code-review max`, TeamCity Perf/Regression (ask), merge; then #71

## PR 2 - Osprey-computed fragment typing and BLIB writing

Stacked on PR 1 (it uses `PeptideFragmentMass`), or cut after PR 1 merges.

### Design decisions (Brendan, 2026-09-29)

1. **Osprey computes the typing.** At library load, each peak is typed by m/z against the
   peptide's own ions, computed with `PeptideFragmentMass.CalculateFragmentMz` (stacked
   modifications included). `FragmentLadder` already lays out the candidate set.
2. **Primary b and y ions only, no neutral losses.** Fragment charge 1 to min(precursor charge, 2).
   Every allowed loss adds candidate m/z and raises random matches; NIST libraries list 5-6 loss
   candidates on one peak, which is the failure. A peak matching no primary ion stays Unknown
   (decoy generation already copies Unknown peaks).
3. **Losses, if ever added, are residue- or modification-specific and opt-in**: water only from
   fragments containing S/T/E/D, ammonia only from R/K/Q/N - never a universal -17/-18.
   **Phospho H3PO4 (98 Da) from pS/pT (rarely pY) is the first loss users will ask for** (DIA-NN
   supports it); it belongs to the modification (Skyline's model), would come from the shared UniMod
   data (#4736), and is NOT in this PR. Keep one place where candidate ions are generated so a
   modification-specific loss can be added there later. Today Osprey only passes through losses a
   DIA-NN TSV states (`FragmentLossType`, `DecoyGenerator.cs:751`).
4. **Ambiguity**: a peak within tolerance of two primary ions takes the nearest m/z; a tie at the
   library's precision leaves it Unknown rather than guessing.
5. **Tolerance** follows the library, not the search: max(0.02 Th, 20 ppm) (the tolerance #4730
   checks annotations with) suits predicted and HRAM libraries, whose peaks sit at theoretical m/z.
   Empirical unit-resolution libraries (NIST ion trap annotations show errors up to ~0.5 Th) need a
   wider one, as Skyline's ion match tolerance is; decide from the NIST measurement below.
6. **Cross-check warning.** When a library states annotations (blib rows, TSV columns), compare
   with Osprey's typing: agree / disagree (library names a primary b/y the typing does not match) /
   outside Osprey's model (losses, isotopes, a/c/x/z, charge > 2, unreadable - reported, not a
   failure). One warning line with counts and denominators naming the library; examples under
   `--verbose`. Tests assert zero disagreements where none are expected. #4730's
   `BlibPeakAnnotations.TryParseName` becomes the cross-check reader.
7. **DIA-NN TSV** keeps its columns as the typing source for now (goldens, Rust parity), with
   Osprey's typing computed alongside for the cross-check. Zero disagreements on the subset and a
   full Astral TSV is the evidence for moving TSVs to Osprey's typing too.

### Contents (from #4730, reworked where noted)

- **Blib reading**: Mike's residue- and precision-aware modification parsing
  (`BlibLoader.IdentifyModification`, `PrintedDecimals`, `IsPrecisionSensitive`,
  `MODIFICATION_READER_VERSION`, `;libmods=2` / `blib_mods:2`); `FileVersionProbe` (fail-closed
  cached probes); typing every blib from m/z (NEW - replaces `BlibPeakAnnotations.Apply` as the
  typing source); a blib-typing key term and `.libcache` term (NEW - replaces `;libext=ann2` /
  `blib_reader:2`)
- **Cross-check**: `BlibPeakAnnotations` reworked as the comparison reader (keeps its grammar,
  a/c/x/z counted apart, malformed rows passed over, non-finite m/z rejected, the `RefSpectraID,
  rowid` cursor order); the warning (NEW); TSV columns compared too (NEW)
- **`FragmentLadder`** (+ `FragmentLadderTest`): candidate ions for the typing; #4708 builds on it
- **BLIB writing** (R10 minus annotations): `BlibSpectrum` as the one LibraryEntry-to-blib-rows
  composition (m/z-sorted peaks; modseq from `Modifications` with printed precision, unresolved
  mods keep library text; per-residue `Modifications` rows) WITHOUT `Annotate`/`BlibPeakAnnotation`
  or the annotations index; `BlibWriter.AddSpectrum(BlibSpectrum, ...)`, nullable
  `AddRetentionTime` bounds; `BlibOutputWriter.PrepareSpectra`; `;blibout` SecondPassFDR key term
  (bump to 3 if PR 2's rows differ from #4730's); the `[UniMod:N]` output fix
- **`--export-library`**: `LibraryBlibWriter` (RetentionTimes rows with NULL bounds, decoy prefix on
  column-only decoys, progress, parallel blocks), `OspreyConfig.ExportLibraryBlib`,
  `OspreyCommandArgs.ARG_EXPORT_LIBRARY` + usage resx, `Program` (validated and dispatched before
  input checks, refuses to overwrite `--library`, `BlibOutputException` for file failures),
  `CommandLine.html`, resources
- **Goldens**: the four `tables/PeakDigest.tsv` (every spectrum re-sorted); Rust companion
  maccoss/osprey#72 (peak sort; Stellar cross-impl PASS, 0/31,720 blobs divergent)
- **Tests** (rewritten against computed typing): `BlibLibraryInputTest` (typing, cross-check,
  writer round trip, mzObserved not needed once no rows are written), `SubsetPipelineTest`
  (export round trip, output blib searches back, and an UNannotated BiblioSpec-style blib now
  searches with real decoys instead of being refused by #4727's check), `TaskValidityKeyTest`,
  `IOTest`, `BlibComparer` ignored tables
- **Docs**: `docs/13-blib-output-schema.md` (typing; empty annotation table as BiblioSpec writes
  it), `docs/14-intermediate-files.md` (key terms), `OspreyEnvironment` comment

### Validation data

- Subset TSV (predicted, exact m/z, explicit columns): `Osprey.Test/TestData/StellarSubset.zip`,
  `AstralSubset.zip` - expect zero disagreements.
- CarafeSharp 483k blib (7,977,491 annotation rows; see `TODO-20260923_carafesharp.md` M3 for its
  location) - expect zero or near-zero disagreements.
- NIST ion-trap, empirical unit resolution, with per-peak annotations incl. error, isotopes,
  losses, multiple candidates (`b6/-0.02,b12^2/-0.02`):
  `D:\Users\brendanx\Downloads\NIST_c_elegans_IT_2011-05-24.msp\NIST_c_elegans_IT_2011-05-24.msp`
  and `D:\Users\brendanx\Downloads\NIST_c_elegans_IT_2011-05-24_7AA.splib\NIST_c_elegans_IT_2011-05-24_7AA.sptxt`.
  Compare only primary b/y z<=2 NIST annotations; parser lives in a measurement harness, not Osprey.
  Decides the unit-resolution tolerance (decision 5).

### Tasks

- [ ] Branch (stacked on PR 1, or after it merges); bring over the Contents above from #4730
- [ ] Typing function (candidate primary b/y ions from `FragmentLadder`, nearest match with the tie
      rule, tolerance by decision 5) in Osprey.IO next to `BlibLoader`; `BlibLoader` types every blib
- [ ] Cross-check warning (resx, counts with denominators; examples under `--verbose`) for blib and TSV
- [ ] Remove the annotation writer; output and export blibs carry an empty table (as BiblioSpec)
- [ ] Key/cache terms for the changed blib reading; `TaskValidityKeyTest`
- [ ] Tests as listed; typing unit tests (stacked mods, ambiguity tie, charge limit, no losses)
- [ ] Measurements: agreement on subset TSV, CarafeSharp 483k blib, NIST msp/sptxt; output blib
      sizes vs #4730 (expect ~half)
- [ ] Gates: Build-Osprey Debug -RunTests -RunInspection, ja-JP/fr-FR, coverage, regression-parallel
      All (goldens: PeakDigest only), Stellar cross-impl with #72, TeamCity Perf/Regression (ask)
- [ ] PR, `/code-review max`, merge; then #72

## Dropped from #4730 (not carried into either PR)

- Annotation rows in every Osprey output and export blib (`BlibSpectrum.Annotate`,
  `BlibPeakAnnotation`, `BlibWriter` annotation inserts, `idx_peakannotations_refid`)
- Library annotations as a typing source (`BlibPeakAnnotations.Apply` in `BlibLoader`)
- `;libext=ann2` and `blib_reader:2` (superseded by the blib-typing terms)
- The docs text for writers "that target Osprey" by writing annotations (docs/13)

## Closing #4730

- [ ] Both PRs open; every Contents item above accounted for (compare `git diff --stat` of #4730
      against the two PRs)
- [ ] Review on #4730 recommending it be closed in favor of the two PRs: output blibs double in size
      (numbers above) and a small-molecule table becomes part of every Osprey blib; Osprey computes
      fragment typing as Skyline does; Mike's parsing, decoy fix, `PeptideFragmentMass`,
      `FragmentLadder` and the BLIB export all carry over
- [ ] Tell Mike: #4708 re-stacks on PR 2; CarafeSharp can stop writing annotations (his call - saves
      ~8M rows / ~400 MB and a writer thread on the 483k library)
- [ ] Close #4730 (Mike or Brendan)

## Later, separate

- Rust port of the typing (blib libraries are not in the parity datasets)
- Issue for consolidating C# BLIB read/write (Skyline `BlibDb`/`BiblioSpecLite`, Osprey
  `BlibWriter`/`BlibLoader`/`BlibSpectrum`) into `pwiz_tools/Shared/BiblioSpec` (not yet filed -
  Brendan asked for the write-up)
- Pre-existing issues #4730's first review found, "to be filed" in its description - confirm filed:
  decoys move N-terminal modifications to an internal residue (C# and Rust);
  `DiannTsvLoader.StripFlankingChars` mangles sequences with two decimal bracket masses; the second
  of two adjacent TSV bracket mods lands on residue 0

## Progress Log

### 2026-09-29 - PR 1 carved out
- Branched `Skyline/work/20260929_osprey_stacked_mod_decoys` from port @ 553a145871 in pwiz-work1
  (the #4730 checkout's branch is untouched on origin).
- Taken verbatim from #4730 @ 2e88e21746 (port had not changed any of them since #4730's merge
  base): `PeptideFragmentMass.cs`, `DecoyGenerator.cs`, `PerFileScoringTask.cs`,
  `DecoyConstructionTest.cs`, `docs/01-decoy-generation.md`. Two comment edits drop the
  "blib annotation reader" wording (PeptideFragmentMass summary, docs/01).
- Hand-carried, annotation terms left out: `LibraryLoader.LibrarySuppliesDecoys` made public
  (moved above the private helpers); `OspreyTask.DECOY_MODS_TERM` appended in the base
  `ValidityKey` when Osprey generates decoys; `TaskValidityKeyTest` leg
  `AssertGeneratedDecoysKeyOnTheStackedModFix` (every task keys on it for generated decoys; neither
  `DecoysInLibrary` nor `DecoyMethod.FromLibrary` does).
- Build-Osprey Debug -RunTests -RunInspection: 616/616 pass, inspection 0 warnings.
- Noted, not in scope: the test host prints an unhandled NRE at exit from
  `OspreyDiagnostics.cs:107` (`ProcessExit` handler dereferences `s_sink` after a later
  `Initialize` set it null). Pre-existing on the port branch; file untouched here.
- Cross-impl vs maccoss/osprey#71 on a stacked-mod Stellar variant (5,900 precursors rewritten to
  `_(UniMod:1)M(UniMod:35)..._`, precursor and b-ion m/z shifted; built by
  `ai/.tmp/sessions/20260929-8a15/make_stacked_mod_library.py` into
  `D:\test\osprey-runs\stackedmods\stellar`, mzMLs hard-linked): 3-file end-to-end PASS at 1e-9,
  30,296 precursors both. Negative control, unfixed Rust `main` vs this C#: FAIL, Rust 31,135
  (+839, 2.8%) - the buggy decoys are easier to beat. Rust's DIA-NN parser ignores a LEADING
  `[UniMod:1]` bracket (C# handles it); the `(UniMod:1)` form works in both. `C:\proj\osprey`
  restored to `fix/sort-blib-peaks` and rebuilt.
- regression-parallel All: 58 PASS / 0 FAIL, but the StellarGenDecoyEntrap straight run died at
  13:13:49 with `AccessViolationException` in `Calibrator.ScoreResolvedCalibrationEntry`
  (untouched; no unsafe code; stack in the Application event log Id 1026 - the run dir was pruned
  by the re-run's retention). Re-run of StellarGenDecoyEntrap alone: all PASS incl. vs golden.
  Loop of the crashing command (cold, exit after calibration, 2 lanes x 16 threads, snapshot exe):
  20/20 clean in ~22 min (`D:\test\osprey-runs\stress-cal-av\summary-*.log`). Only Osprey AV in
  30 days of event log. Not reproduced; recorded in the PR test plan.
- Perf gate skipped: decoy generation runs once per library, and the refactor replaces a
  per-decoy O(mods x length) position scan with the remap already done, rather than adding work.
- Committed 73d29b8b44, pushed. `/code-review max` running.
