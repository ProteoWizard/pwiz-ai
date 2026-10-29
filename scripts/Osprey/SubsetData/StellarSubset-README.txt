Stellar subset test data for Osprey.Test (issue #4360)

A small rectangle of real DIA data, cut from the three Stellar HeLa runs the Osprey
regression uses (osprey-testfiles-mzML-v2.zip, stellar folder), so the whole pipeline
can run in-process in a unit test in a few seconds.

Files
  Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20/21/22.mzML
      One DIA isolation window (target 594.5201, 592.52-596.52) between 6.5 and 13.5 min:
      229 MS2 spectra and 229-230 MS1 spectra per file. MS1 peaks are trimmed to
      590.5-600.5 m/z (the window plus its isotope envelopes). Binary arrays are 32-bit
      float with the mantissa rounded (m/z: 8 low bits, intensity: 12 low bits) to keep the
      zip small; both are far below unit-resolution tolerances. The indexedmzML wrapper and
      chromatogram list are dropped and spectrum indices renumbered; native ids are kept.
  stellar-subset-library.tsv
      358 target precursors from hela-filtered-SkylineAI_spectral_library.tsv, rows copied
      verbatim except ProteinID: 178 precursors the full 3-file regression run detected in
      this rectangle (observed RT 7-13 min), and 180 it did not detect whose library RT falls
      in 7-13 min. Proteins are SYNTHETIC (sp|SUBnnn|SUBnnn_SUBSET, about 4 peptides each,
      every 8th group sharing one peptide with the next): a single 4 m/z window almost never
      holds two peptides of one real protein, and without proteins detected by 2 or more
      peptides the second-pass FDR, protein parsimony and reconciliation paths never run.
  manifest.tsv
      The 358 precursors with DetectedInFullRun (1/0) and the full-run RT.
  stellar-subset-libdecoy.tsv, stellar-subset-libdecoy-pairing.tsv
      The library-decoy + entrapment variant, from the StellarLibDecoy regression library
      (stellar-libdecoy-v3, Carafe): for each target above, its whole pairing group - target,
      shuffled entrapment (_p_target), and the decoy of each (decoy_ prefix) - restricted to
      the window, 1428 precursors in 357 groups. Shuffles and reversals keep the target's
      composition, so a group shares its precursor m/z. ProteinID and the pairing manifest
      carry the same synthetic accessions, decorated as Carafe decorates real ones. Search it
      with --decoys-in-library --decoy-pairing-manifest stellar-subset-libdecoy-pairing.tsv.

Expected behavior (Osprey 26.1.1.270, default settings, --resolution unit)
  About 130-155 precursors per run at 1% run-level FDR, cross-run reconciliation over
  about 180 peptides, about 275 re-scored peaks, about 177 precursors in the blib (169 of
  the 178 full-run detections).

Why this size
  First-pass q-values are conservative, (decoys + 1) / targets, so a run needs at least 100
  targets ahead of its first decoy for anything to pass 1% FDR, and cross-run consensus is
  gated at a fixed 1% (ReconciliationConfig.ConsensusFdr). A 3 min slice gives ~75 targets
  per run and stops at first pass; 6 min clears the floor with margin.

Regenerate with ai/scripts/Osprey/SubsetData/build_subset.py stellar (pwiz-ai repository).
