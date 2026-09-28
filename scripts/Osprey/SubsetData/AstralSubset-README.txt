Astral subset test data for Osprey.Test (issue #4360)

A small rectangle of real HRAM DIA data, cut from two of the three Astral HeLa runs the Osprey
regression uses (osprey-testfiles-mzML-v2.zip, astral folder), so the pipeline's
high-resolution paths - MS1 isotope scoring, ppm tolerances, HRAM calibration - run in-process
in a unit test in a few seconds. The Stellar subset covers the unit-resolution paths and
three-run reconciliation.

Files
  Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_49/55.mzML
      One DIA isolation window (target 479.9681, 478.47-481.47) between 6.5 and 9.5 min:
      about 170 MS2 and 170 MS1 spectra per file. MS1 peaks are trimmed to 476.5-484.5 m/z.
      Binary arrays are 32-bit float with the mantissa rounded (m/z: 3 low bits, about
      0.5 ppm; intensity: 16 low bits, under 1%) to fit under 5 MB zipped. The indexedmzML
      wrapper and chromatogram list are dropped and spectrum indices renumbered.
  astral-subset-library.tsv
      403 target precursors from SkylineAI_spectral_library.tsv, rows copied verbatim except
      ProteinID: 203 precursors the full 3-file regression run detected in this rectangle
      (observed RT 7-9 min), and 200 it did not detect whose library RT falls in 7-9 min.
      Proteins are SYNTHETIC (about 4 peptides each), for the reason the Stellar README gives.
  manifest.tsv
      The 403 precursors with DetectedInFullRun (1/0) and the full-run RT.

Expected behavior (--resolution hram, default settings)
  About 160 precursors per run at 1% run-level FDR, about 90 re-scored peaks, about 164
  precursors in the blib.

Regenerate with ai/scripts/Osprey/SubsetData/build_subset.py astral (pwiz-ai repository).
