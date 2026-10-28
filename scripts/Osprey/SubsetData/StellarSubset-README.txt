Stellar subset test data for Osprey.Test (issue #4360)

A small rectangle of real DIA data, cut from the three Stellar HeLa runs the Osprey
regression uses (osprey-testfiles-mzML-v2.zip, stellar folder), so the whole pipeline
can run in-process in a unit test in seconds, and one run searched alone can tune a model.

Files
  Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20/21/22.mzML
      Two adjacent DIA isolation windows (targets 594.5201 and 598.5219, 592.52-600.52)
      between 5.5 and 18.5 min: 850 MS2 spectra and 424 MS1 spectra per file. MS1 peaks are
      trimmed to 590.5-604.5 m/z (the windows plus their isotope envelopes). Binary arrays
      are 32-bit float with the mantissa rounded (m/z: 8 low bits, intensity: 12 low bits)
      to keep the zip small; both are far below unit-resolution tolerances. The indexedmzML
      wrapper and chromatogram list are dropped and spectrum indices renumbered; native ids
      are kept.
  stellar-subset-library.tsv
      1,270 target precursors from hela-filtered-SkylineAI_spectral_library.tsv, rows copied
      verbatim except ProteinID: 550 precursors the full 3-file regression run detected in
      this rectangle (observed RT 6-18 min), and 720 it did not detect whose library RT falls
      in 6-18 min. Proteins are SYNTHETIC (sp|SUBnnn|SUBnnn_SUBSET, about 4 peptides each,
      every 8th group sharing one peptide with the next): two 4 m/z windows rarely hold two
      peptides of one real protein, and without proteins detected by 2 or more peptides the
      second-pass FDR, protein parsimony and reconciliation paths never run.
  manifest.tsv
      The 1,270 precursors with DetectedInFullRun (1/0) and the full-run RT.
  stellar-subset-libdecoy.tsv, stellar-subset-libdecoy-pairing.tsv
      The library-decoy + entrapment variant, from the StellarLibDecoy regression library
      (stellar-libdecoy-v3, Carafe): for each target above, its whole pairing group - target,
      shuffled entrapment (_p_target), and the decoy of each (decoy_ prefix) - restricted to
      the windows, 5,068 precursors in 1,267 groups. Shuffles and reversals keep the target's
      composition, so a group shares its precursor m/z. ProteinID and the pairing manifest
      carry the same synthetic accessions, decorated as Carafe decorates real ones. Search it
      with --decoys-in-library --decoy-pairing-manifest stellar-subset-libdecoy-pairing.tsv.

Expected behavior (Osprey 26.1.1.301, default settings, --resolution unit)
  About 480-505 precursors per run at 1% run-level FDR, 206 proteins with 2 or more
  detections, about 900 re-scored peaks, about 574 precursors in the blib (528 of the
  550 full-run detections). The middle run searched alone with a FASTA of these proteins
  exports about 345 precursors for a fine-tune that beats the pretrained models.

Why this size
  First-pass q-values are conservative, (decoys + 1) / targets, so a run needs at least 100
  targets ahead of its first decoy for anything to pass 1% FDR - and a run tuned alone needs
  that in its second-pass protein stratum too, which a one-window, 6-minute slice does not
  reach (126 targets pass its first pass, about 74 sit in the stratum, and nothing passes the
  second). Two windows over 12 minutes is the smallest cut measured whose one run exports
  more than 300 precursors (ai/todos TODO-20261027_osprey_test_subsetting.md).

Regenerate with ai/scripts/Osprey/SubsetData/build_subset.py stellar (pwiz-ai repository).
