# TODO-osprey_computed_fragment_typing.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_osprey_computed_fragment_typing`,
  cut from the head of `Skyline/work/20260928_osprey_blib_annotations` (#4730, 2e88e21746)
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Module**: `osprey`
- **Replaces**: PR #4730 (to be abandoned, with a review saying why - see "Deliverables")
- **Related**: #4708 (Mike, part B, stacked on #4730); maccoss/osprey#72 (Rust peak sort);
  #4736 (UniMod); `TODO-carafe_osprey_library_contract.md`; `TODO-20260923_osprey_carafe_export.md`
- **Objective**: Osprey types library fragment peaks itself, from m/z, the way Skyline does - it
  never takes fragment ion types from a library's annotations. Library annotations, where a
  format has them, are only a cross-check that warns when Osprey disagrees.

## Why (Brendan, 2026-09-29)

> "We are not going to merge 4730. It turns a corner-case small molecule feature into something in
> every BLIB file from and for Osprey. Let's start working on a replacement that treats peak
> annotating as something Osprey must do for itself, as Skyline does."

> "I think it is far better to have the software work out the peak annotations that to simply
> accept library annotations."

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

## Design decisions (Brendan, 2026-09-29)

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

## Keep from #4730 / drop

Keep: Mike's residue- and precision-aware blib modification parsing; the stacked-modification
decoy fix (`PeptideFragmentMass.ModMassesByPosition`); `PeptideFragmentMass`; `FragmentLadder`
(#4708 builds on it); the R7 items not about annotations; `BlibSpectrum` as the one
LibraryEntry-to-blib-rows composition; m/z-sorted peaks (Rust: maccoss/osprey#72);
`--export-library` with its RetentionTimes rows, decoy marking, argument checks; the `[UniMod:N]`
output fix and printed-precision masses; `;blibout` key term.

Drop: the annotation WRITER (`BlibSpectrum.Annotate`, `BlibWriter.AddSpectrum` annotation inserts,
`BlibPeakAnnotation`, the annotations index) - output blibs back to ~half the #4730 size; annotations
as a TYPING source (`BlibPeakAnnotations.Apply` in `BlibLoader`); `;libext=ann2` / `blib_reader:2`
(replace with a blib-typing key and `.libcache` term, since every blib library now reads differently);
the annotation-specific tests, rewritten against computed typing.

## Validation data

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

## Tasks

- [ ] Branch from #4730's head; typing function (candidate primary b/y ions, nearest-match with
      tie rule, tolerance by decision 5) in Osprey.IO next to `BlibLoader`
- [ ] `BlibLoader` types every blib from m/z; annotation rows read only for the cross-check
- [ ] Cross-check warning (resx, counts with denominators; examples under `--verbose`) for blib and TSV
- [ ] Remove the annotation writer; output and export blibs carry an empty table (as BiblioSpec)
- [ ] Key/cache terms for the changed blib reading; `TaskValidityKeyTest`
- [ ] Tests: typing unit tests (stacked mods, ambiguity tie, charge limit, no losses); subset TSV
      and an exported blib type identically to the TSV columns (zero disagreements); exported blib
      still searches identically to the TSV; Osprey output blib searches back; an UNannotated
      BiblioSpec-style blib now searches with real decoys (was refused by #4727's check)
- [ ] Measurements: agreement on subset TSV, CarafeSharp 483k blib, NIST msp/sptxt; output blib
      sizes vs #4730
- [ ] Gates: Build-Osprey Debug -RunTests -RunInspection, ja-JP/fr-FR, coverage, regression-parallel
      All (goldens: PeakDigest only, as #4730), TeamCity Perf/Regression (ask)
- [ ] Docs: 13-blib-output-schema (typing, empty annotation table), decoy-generation doc

## Deliverables

- [ ] The replacement PR (title along the lines of "osprey: Typed library fragments from m/z ...")
- [ ] A review on #4730 recommending it be abandoned for internal calculation: output blibs double
      in size (numbers above) and a small-molecule table becomes part of every Osprey blib; point
      to the replacement, which keeps Mike's parsing, decoy fix, `PeptideFragmentMass`,
      `FragmentLadder`
- [ ] Tell Mike: #4708 must re-stack on the replacement; CarafeSharp can stop writing annotations
      (Mike's call - saves ~8M rows / ~400 MB and a writer thread on the 483k library)
- [ ] Later, separate: Rust port of the typing (blib libraries are not in the parity datasets);
      issue for consolidating C# BLIB read/write (Skyline `BlibDb`/`BiblioSpecLite`, Osprey
      `BlibWriter`/`BlibLoader`/`BlibSpectrum`) into `pwiz_tools/Shared/BiblioSpec` (not yet filed -
      Brendan asked for the write-up)

## Progress Log

(none yet)
