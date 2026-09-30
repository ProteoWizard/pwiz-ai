# TODO-20260929_osprey_computed_fragment_typing.md

## Branch Information
- **Branch (PR 1)**: `Skyline/work/20260929_osprey_stacked_mod_decoys` (checkout `C:\proj\pwiz-work1`)
- **Branch (PR 2)**: (not yet created)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Created**: 2026-09-29
- **Status**: In Progress - PR 1 open (#4746), TeamCity Perf/Regression build 4194189 queued; PR 2 not started
- **Module**: `osprey`
- **PR (PR 1)**: [#4746](https://github.com/ProteoWizard/pwiz/pull/4746) (merged 2026-09-30 as 07314d47ea)
- **PR (PR 2)**: [#4749](https://github.com/ProteoWizard/pwiz/pull/4749) (base retargeted to the port branch after #4746 merged)
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
- [x] PR (#4746), `/code-review max`
- [ ] TeamCity Perf/Regression (4194189), merge; then #71

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
5. **Tolerance is the search's fragment tolerance** (`config.FragmentTolerance`: 0.5 Th for
   `--resolution unit`, ppm - default 10 - for hram, or what the user sets). DECIDED 2026-09-29,
   superseding "follows the library" and the 1-decimal heuristic. Brendan: "a library match
   tolerance that differs from what the search software does can be very confusing to users,
   especially when it is wider than the chromatogram extraction tolerance" - a user sees y6
   matched in the spectrum at 20 ppm while extraction at 10 ppm shows nothing for y6. Internal
   consistency keeps that confusion to a minimum; Skyline uses one ion match tolerance (default
   0.5 m/z) the same way. NIST at 0.5 Th: 96.2% agree, 4 disagree in 1.77M, 0.18% extra.
   Open detail: typing runs once per library at load, before any run's MS2 calibration narrows
   extraction to |mean|+3SD per file, so the configured tolerance is the upper bound of what
   extraction uses, not always equal to it. Say so in the docs; do not type per run.
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

### #4708 (Mike, training export) - what it needs from here (checked 2026-09-29)

- Uses only `FragmentLadder` (`Build`, `SlotOf`, `SlotCount`, `ChargeOf`; PR 2) and
  `PeptideFragmentMass.CalculateFragmentMz` (PR 1). Nothing from annotation reading/writing,
  `BlibSpectrum`, `--export-library` or the key terms. So it re-stacks on PR 2, not PR 1.
- Gate for PR 2: a LOCAL merge of #4708's head onto PR 2 (scratch branch, never pushed - it is
  Mike's branch), Build-Osprey -RunTests, incl. `TrainingEvidenceTest` and
  `SubsetPipelineTest.TrainingExport`.
- Semantic overlap to settle with Mike: `TrainingEvidence.MapLibrary` sends a typed fragment to
  its slot and flags it `LIBRARY_ANNOTATED`; an `IonType.Unknown` one gets its OWN nearest-m/z
  match (`NearestSlot`, no tie rule) flagged `LIBRARY_MZ_MATCHED`. Once PR 2 types every blib
  fragment at load, blib fragments arrive typed: every one would be flagged `LIBRARY_ANNOTATED`
  ("the library holds this ion by annotation", docs/22) although Osprey computed it, and
  `NearestSlot` becomes a second typing rule. Options: PR 2 records the typing's source on the
  fragment (library-stated vs computed) and `MapLibrary` keeps its two flags meaning what docs/22
  says; or the flags are redefined. The export schema is Carafe's input - Mike's call.
  `TrainingEvidenceTest` lines ~392-433 pin the unannotated-blib behavior and will fail as-is.

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

## After PR 2 - resume-invalidation fixes (Brendan, 2026-09-29: "fix #2 and #3 after PR 2")

**REMIND BRENDAN when #4746 and PR 2 are both merged**, then do this as its own PR.
From #4746's `/code-review max`; pre-existing, not caused by either PR. Each lets a resume reuse
an output whose validity key no longer matches, so any future key term is silently bypassed:
- [ ] **#2 PerFileRescoring self-gate**: `PerFileRescoreTask.Pass2SidecarCurrent`
      (`PerFileRescoreTask.cs` ~1710) accepts a `.2nd-pass.fdr_scores.bin` by FORMAT only, returns
      `RefillOnly` (~491), and `AnalysisPipeline.WriteTaskSidecars` (~224-242) then stamps the old
      Stage 6 outputs with the new key. Fix: also require
      `PerFileResumeDriver.IsCurrent(pass2Path, Name, ValidityKey(ctx))`. Reach it via
      `--task PerFileRescoring` after re-running Stages 1-5, and `--task ModelDiagnostics`.
- [ ] **#3 SecondPassFDR transfer-mode gate**: `Pass2FdrSidecar.cs` ~206
      (`recomputed = anyRescoreWork && (missingPass2 > 0 || workerDidPerFileHalf)`) judges
      existing pass-2 files by format (`Pass2SidecarWriter.IsCurrent -> IsCurrentFormat`). Under
      `OSPREY_PASS2_QVALUE=transfer`, a key change reloads old pass-2 values, re-stamps them, then
      throws "No second-pass experiment-scope records were published" (`Pass2FdrSidecar.cs` ~1490)
      on every later run until the `.2nd-pass` files are deleted by hand.
- [ ] Tests in `SubsetPipelineTest` (the pipeline-mechanics home): change a key, resume, assert
      the stage re-runs instead of adopting.
- Not doing #1 (the `--task` join validates scores parquets by footer version/hashes only; a
  fix needs a footer marker mirrored in Rust).

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

### 2026-09-29 - PR 1 review round, strict TSV loader, PR opened
- `/code-review max`: 14 findings; fixed 10 (c693e95f4a), dropped 1, 3 pre-existing resume gaps
  (HPC join footer-only check; PerFileRescore `Pass2SidecarCurrent` format-only; SecondPassFDR
  transfer-mode gate) left for Brendan's call. The `;decoymods=2` comment was wrong - no resume
  check reads the build version - so the term re-runs every generated-decoy directory once; kept,
  pending Brendan's decision (keep / drop / gate on a library probe in PR 2).
- Brendan: no guessed values from a library ("prefer a hard failure"). DIA-NN TSV loader rewritten
  (d5fe68fd07): every column present must parse; charge/ordinal 0, unknown type/loss/decoy flag,
  empty cells and unknown modifications (previously DROPPED) are errors; the whole file is read
  and every error reported `(line N, column C) ...` (1-based file lines, header = line 1, blank
  lines counted - Skyline's CLI format), first 100 listed. `tsv_reader:2` in the .libcache
  composition. Rust still lenient (follow-up question open).
- Skyline's `--import-transition-list` reports data lines one low when the list has a header
  (Import.cs:631 resets `_linesSeen` after the header bump at 513-514/582-583); verified with
  SkylineCmd (`ai/.tmp/sessions/20260929-8a15/skyline-linenum/`). Not filed - Brendan to decide.
- regression-parallel All on the strict loader: 70 PASS / 0 FAIL. PR #4746 opened; TeamCity
  Perf/Regression 4194189 triggered (Brendan approved).

### 2026-09-30 - #4746 merged

PR #4746 squash-merged into Skyline/work/20260612_net8_port as 07314d47ea: the stacked-modification
decoy fix, the strict DIA-NN TSV loader, PeptideFragmentMass. Its Perf/Regression re-run (4194805)
was dropped by Brendan: 4194189 passed at d5fe68fd, and the head b2ffe1196a had Windows/Linux green,
local regression 48/0 and cross-impl PASS. #4749 retargeted onto the port branch (branch left as
is: port tree == #4746 head tree, and #4749 already contains it; merging would only move its head
off the queued Perf run 4194827). #4746 branch deleted local + remote; C:/proj/pwiz-4746 worktree
removed. Deferred from #4746: resume gaps #2/#3 (separate PR after #4749), StripFlankingChars.

### 2026-09-30 night session - PRs opened and stacked - CURRENT STATE / RESUME HERE
Stack (bottom to top), each branch containing the head below it (merges only, no force-push):
- **#4746** stacked-mod decoys, head b2ffe1196a (Brendan's 23:58 port-branch merge). TeamCity
  Windows 4194665 + Linux 4194666 SUCCESS; Perf 4194189 SUCCESS at d5fe68fd; local
  regression-parallel All 48/0 at b2ffe1196a; cross-impl vs maccoss/osprey#71 (867029e281) on
  the stacked-mod Stellar variant PASS 1e-9, 30,296 both (logs D:/test/osprey-runs/crossimpl-4746-logs).
- **#4749** PR 2 (this TODO), head ce565c1c22 (6b909a6bcc review fixes + merge of #4746 head).
  628/628; regression 70/0 at 6b909a6bcc and 48/0 at ce565c1c22; Windows 4194844 + Linux 4194826
  SUCCESS.
- **#4708** (Mike) re-based onto #4749 by merge 874536be8e, then 9aa7429305 (merge of #4749).
  Linux failed deterministically at 9aa7429305: TestSubsetTrainingExportSingleRun. Root cause
  (sub-agent, WSL repro): whole-second mtime race. PerFileRescoring declines its resume on every
  invocation of a one-run analysis (#4729), clears the reconciled stamp and rewrites an identical
  parquet; the export's recon= identity holds its mtime. Pre-existing, not Linux-specific.
  Fixed in PerFileRescoreTask (338c593d58). Mike pushed c0c7428206 (LIBRARY_MZ_MATCHED for
  Osprey-typed blib fragments) at 01:29; merged -> cce115ab01. 638/638, regression 48/0,
  Windows 4194841/4194846 + Linux 4194842 SUCCESS.
- **#4730** commented recommending close (annotations table never meant for proteomics; doubled
  blib size 27.4 -> 59.9 MB).
- Perf/Regression queued: 4194805 (#4746), 4194827 (#4749), 4194843 (#4708). The only compatible
  agent (MacCoss TeamCity Agent 1) had 7 auto-triggered Skyline Perf/Tutorial builds ahead
  (pwiz-commit, 00:10). Not reordered or cancelled.
- Worktrees: C:/proj/pwiz-4708 (branch of #4708), C:/proj/pwiz-4746 (detached b2ffe1196a) -
  remove when done.
- Still open for Brendan: StripFlankingChars bracket bug (#4746 or separate; left untouched so
  #4746's gates stay valid). After merges: resume fixes #2/#3.

### 2026-09-30 - PR 2 code-review fixes
`/code-review max` returned 15 findings; Brendan triaged:
- **Blib annotation rows are NOT READ at all** (Skyline designed the table for small molecules; no
  proteomics software writes it). Deleted `BlibPeakAnnotations.cs`, the stated-ion pass in
  `FragmentTyping`, blib `TypeCheck`. DIA-NN TSV columns stay the typing, still compared
  (`FragmentTypeCheck`, now single stated ion per peak). Findings #8/#10/#11 moot. Future
  .sptxt/.msp/Spectronaut inputs should NOT ignore stated ions - only when a user asks.
- #3/#4 blib mods matched like Skyline `MassModification.Matches` (round at printed precision,
  cap 4 decimals, or within 1e-4), residue/terminus-specific, table order = preference; unmatched
  with <4 decimals, unknown UniMod id, other text -> library refused listing each mod once.
  `(UniMod:N)` read. New `Osprey.Core/UniMod.cs` (masses from Skyline UniModData.cs).
- #5 one UniMod table shared by DiannTsvLoader/BlibWriter/BlibLoader; corrected ids 28, 122, 214,
  312, 385, 747. Rust `unimod_id_to_mass` still wrong - noted in docs/DIVERGENCES.md (parity
  datasets use only UniMod:4). Named mods (Oxidation...) left at Rust's 4-decimal masses.
- #1 `-o` == `--library` refused (ValidateArgs, all tasks); #12 blank `--export-library` refused.
- #2 (a): unflagged precursors with decoy-prefix accessions refused unless --decoys-in-library.
- #9 blib CheckDecoysUsable message points at --fragment-tolerance/--resolution.
- #14 TIE_TOLERANCE 1e-3 -> 1e-5 Th; #15 FormatMassDelta zero section. Dropped: #6, #7 (Skyline
  quirk, composite mods), #13.
- Build 624/624 + inspection 0 (before ProgramTests.TestValidateRejectsOutputOverLibrary and the
  Deamidated R entry were added). regression-parallel All running (regr3.log).
- NEXT: finish regression, rebuild+tests, commit (msg `ai/.tmp/sessions/20260929-8a15/pr2-commit3.txt`),
  push, open PR 2 with `pr2-body.md` (base = Skyline/work/20260929_osprey_stacked_mod_decoys,
  label osprey). Ask before TeamCity. Still pending from Brendan: StripFlankingChars bracket bug
  (fix in #4746 or separate?), cross-impl re-run for #4746 (asked, no answer). Then #4730 close
  review, Mike note, resume fixes #2/#3 after merge.

### 2026-09-29 - PR 2 typing rework (a728f1a652)
Brendan's rules after reviewing the 6 subset "isobar" peaks (b2 = b4^2 of IQQLTEEIGR etc.):
1. A library-stated primary b/y ion within the search tolerance is ACCEPTED, even over Osprey's
   choice (isotope labels can resolve isobars Osprey cannot). Loss / a,c,x,z / z>2 / out of
   tolerance -> not possible -> Osprey types the peak.
2. Osprey's own typing, most intense peak first; each ion types ONE peak (Skyline's
   SpectrumRanker IsSeen(predictedMz) rule).
3. Preference: nearest (1e-3 Th = equal), then LOWER CHARGE, then y before b, then shorter ion.
   Never leave a peak with a candidate in reach untyped ("Unknown says not a peptide fragment").
- Implemented in `FragmentTyping` + new `FragmentCandidates` (Core); check categories now
  agree / library's choice / differ (out of tolerance) / outside; warning only on differ.
- Subset TSV: Osprey's own typing reproduces all 7,160 stated types; exported blib search is
  IDENTICAL to the TSV search again (AssertSameSearch restored). 624/624, inspection 0.
- NIST .msp (0.5 Th): nearest+tie->Unknown 97.13% agree/1,298 ties; +lower-charge tie-break
  97.19%/290 ties, disagree unchanged 77; Skyline's charge-FIRST order worse (145; 590 at 0.6 Th).
  Harness `ai/.tmp/sessions/20260929-8a15/measure_nist_typing.py` (modes; results nist_msp_*.txt).
- regression-parallel All on ab654217c6: 70/0 (typing rework touches only blib libraries; none in
  regression). #4708 diff applied 3-way on a728f1a652 in a scratch branch: builds, 634/634 pass
  (scratch branch deleted). MapLibrary flag semantics for loaded blibs still Mike's call.
- PR 1 #4746: TeamCity 4194189 SUCCESS (2026-09-29). pr2-body.md updated for the typing rework.
- NEXT: `/code-review max` on PR 2 was launched in background (diff vs PR 1 branch) - if its result
  is lost, re-run it (cd pwiz-work1 first). Then triage, open PR 2 with body
  `ai/.tmp/sessions/20260929-8a15/pr2-body.md` (UPDATE it: typing rules changed - library ions
  accepted, lower-charge ties, one peak per ion; exported blib search identical; drop the
  "isobaric"/90% text), base = Skyline/work/20260929_osprey_stacked_mod_decoys, label osprey.
  Ask Brendan before TeamCity. Then: review on #4730 recommending close; tell Mike (#4708
  re-stack, MapLibrary flags); after both PRs merge, REMIND Brendan of resume fixes #2/#3.

### 2026-09-29 - PR 2 first commit (ab654217c6)
Branch `Skyline/work/20260929_osprey_computed_fragment_typing`, stacked on #4746, pushed (no PR yet).
- #4730's diff applied 3-way minus PR 1's files; conflicts in LibraryLoader, SubsetPipelineTest.
- `Osprey.Core/FragmentTyping.cs`: candidates from `FragmentLadder` (primary b/y, z 1..min(prec,2),
  no losses), nearest within `config.FragmentTolerance` (ppm taken at the candidate m/z, as
  `FragmentToleranceConfig.WithinTolerance`), tie = two candidates within 1e-3 Th of the nearest
  distance -> Unknown. `Compute` returns the tied ions too.
- `Osprey.IO/FragmentTypeCheck.cs`: agree / isobaric / differ / outside, one summary line
  (warning only when differ > 0), first 10 differing peaks under `--verbose`. Blib rows and TSV
  columns both feed it; TSV columns remain the TSV typing (decision 7).
- `BlibLoader(FragmentToleranceConfig)` types every blib; annotation rows only feed the check.
- Writing: `BlibSpectrum`/`BlibWriter`/`LibraryBlibWriter` write NO annotation rows (table empty).
- Keys: ONE `;blibreader=2` base term for every blib search + `.libcache` `blib_reader:2,<tol>,<unit>`
  (`BlibLoader.READER_VERSION`). Dropped #4730's `FileVersionProbe`, `HasPeakAnnotations`,
  `HasPrecisionSensitiveModifications`, `;libext`, `;libmods`: they re-keyed only affected blibs,
  and every blib is now affected. Tolerance is in SearchParameterHash already.
- Subset TSV (Stellar, 0.5 Th): 7,154 of 7,160 stated b/y agree, 0 differ, 6 isobaric (b2/b4^2 of
  IQQLTEEIGR, LQQIAAAVENK; b2 of ELEIGQAGSQR, VQVQDNEGCPVEALVK). Consequence: an exported blib
  leaves those 6 untyped, so its search is no longer identical to the TSV search (test now asserts
  >= 90% of the TSV precursors, like the back-search leg). Per decision 4 (tie -> Unknown).
- Build-Osprey Debug -RunTests -RunInspection: 624/624, 0 warnings. regression-parallel All running.
- CarafeSharp 483k blib: not on this machine (TODO-20260923_carafesharp names D:\test paths that do
  not exist here) - measurement pending the file.

### 2026-09-29 - Brendan's answers
- `;decoymods=2`: DROP - removed (919f6ff6ea); docs/01 says a directory resumed across the fix
  keeps its old decoys. TeamCity 4194189 (on d5fe68fd07) still covers the outputs; not re-run.
- Rust `diann.rs` strict validation: NO - Rust only has to pass cross-impl, which valid libraries do.
- Skyline header line-number bug: FILED [#4747](https://github.com/ProteoWizard/pwiz/issues/4747).
- Resume gaps #1-#3: Brendan asked for clarification.
- Tolerance (decision 5): Brendan asked for precedent. Skyline: one "Ion match tolerance" setting,
  default 0.5 m/z (Properties/Settings.cs:3521), m/z or ppm. Osprey already matches peaks with
  `FragmentToleranceConfig`: 0.5 Th for `--resolution unit`, ppm (default 10) for hram, then
  MS2 calibration narrows it to |mean|+3SD. The 1-decimal heuristic has no precedent (mine);
  0.02 Th/20 ppm came from #4730. Proposal now: type with the search's fragment tolerance.

### 2026-09-29 - NIST measurement for decision 5 (PR 2 tolerance)
Harness `ai/.tmp/sessions/20260929-8a15/measure_nist_typing.py` (results `nist_msp_typing.txt`,
`nist_sptxt_typing.txt` beside it): primary b/y at z <= min(prec, 2), nearest match, a tie
(distances within 0.05) left Unknown; compared with the library's primary b/y (z <= 2) labels.
"Extra" = typed b/y on a peak the library calls a loss, isotope or `?` (random-match cost).

| tol (Th) | msp agree | msp disagree | msp extra | sptxt agree | sptxt disagree | sptxt extra |
|---|---|---|---|---|---|---|
| 0.02 | 12.26% | 14 | 0.00% | 12.00% | 6 | 0.01% |
| 0.2 | 73.22% | 5 | 0.01% | 71.51% | 151 | 0.08% |
| 0.5 | 96.18% | 4 | 0.18% | 93.29% | 368 | 0.41% |
| **0.6** | **98.89%** | **4** | **0.32%** | **94.95%** | **449** | **0.76%** |
| 0.7 | 98.94% | 4 | 1.17% | 96.05% | 631 | 1.39% |
| 1.0 | 98.94% | 4 | 7.54% | 98.91% | 714 | 7.18% |

- msp: 67,470 spectra, 10.37M peaks, 1.77M with a primary label. NIST labels stop at +/-0.607 Th
  from our m/z (p50 0.098, p99 0.566) - the mass arithmetic matches theirs. sptxt (SpectraST's
  own re-annotation of the same spectra) labels out to 1.0 Th (p95 0.58, p99 0.92).
- Disagreements are near zero at every tolerance; the ~1% the msp never reaches is the tie rule
  (e.g. NIST's own `b6/-0.02,b12^2/-0.02` - identical m/z, both listed).
- 0.6 Th is the knee: agreement plateaus and extra quadruples per 0.1 Th beyond it. Proposed
  unit-resolution tolerance: 0.6 Th. Proposed library rule: the peak m/z's SIGNIFICANT printed
  precision (trailing zeros ignored - the sptxt pads 427.2 to 427.2000) of 1 decimal or fewer
  means unit resolution (0.6 Th); otherwise max(0.02 Th, 20 ppm). Awaiting Brendan's call.
