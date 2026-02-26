# TODO-20260226_cwt_peak_detection.md

## Branch Information
- **Branch**: `Skyline/work/20260226_cwt_peak_detection`
- **Base**: `master`
- **Created**: 2026-02-26
- **Status**: Not Started
- **GitHub Issue**: [#4046](https://github.com/ProteoWizard/pwiz/issues/4046)
- **PR**: (pending)

## Objective

Replace Skyline's Crawdad peak finder with CWT consensus peak detection from Osprey, and integrate cross-run peak picking, alignment, Percolator FDR, and experiment-level q-value reporting.

## Background

Michael MacCoss implemented a complete cross-run DIA peak picking pipeline in Osprey
([maccoss/osprey](https://github.com/maccoss/osprey), branch `peak-detection-improvement`).
The core innovation is CWT consensus peak detection using a Mexican Hat wavelet with
pointwise median across transitions, which naturally rejects single-fragment interference.
The full pipeline also includes LOESS RT alignment, LDA calibration scoring, a fully
deterministic native Percolator reimplementation, cross-run reconciliation with boundary
imputation, and experiment-level FDR control.

Michael has offered to package the Osprey algorithms as a DLL for Skyline consumption.

Slides: `osprey/2026-0219-Thermo Update.pptx`

## Algorithm Summary (from Michael's message)

1. **Calibration**: Select peptides from library, score with cheap LDA to get 200+ peptides.
   Calibrate mass (delta mass, not ML). LOESS alignment to library predictions. RT window =
   3x robust SD of residuals. Truncates up to 0.3% of data for speed.
2. **Fragment filter**: 2 of top 6 library fragments must be present in 3 of 4 continuous spectra.
3. **CWT peak detection**: Calculate DIA-NN Pearson sum score on all peaks. Cache info for up to top 5.
4. **Interference resolution**: Peptides sharing >50% of top 5 fragments at same time and isolation
   window - keep the one with best DIA-NN score.
5. **Full scoring**: 24 scores on top peak per run.
6. **FDR**: Full Percolator using paired library strategy (Bo and Uri's). Works much better than
   pi0 method from EncyclopeDIA/mProphet.
7. **Alignment refinement**: Take peptides at 1% FDR, redo alignment to library.
8. **Cross-run reconciliation**: For any peptide detected in any run, take best across all runs.
   Check if others are within aligned boundaries. If not, check for another CWT peak that is.
   If not, impute boundaries. Different charge states within a run must share exact boundaries.
9. **Rescore**: Recalculate 24 scores for repicked peaks. Run Percolator for q-value at
   precursor and peptide level. Report q-value and PEP per run and experiment level.
10. **Output**: Write blib.

Performance: ~9 min for 3 Stellar files, ~50 min for Astral data. Bottleneck is binary
searching through spectra for m/z extraction and file I/O (especially Astral).

## Key Reference Files

### Osprey (source algorithms)
- `osprey/crates/osprey-chromatography/src/cwt.rs` - CWT consensus peak detection (798 lines)
- `osprey/crates/osprey-chromatography/src/lib.rs` - Chromatography core (1415 lines)
- `osprey/crates/osprey-chromatography/src/calibration/rt.rs` - LOESS RT calibration (1371 lines)
- `osprey/crates/osprey-fdr/src/percolator.rs` - Native Percolator (1699 lines)
- `osprey/crates/osprey-ml/src/svm.rs` - Linear SVM dual coordinate descent (838 lines)
- `osprey/crates/osprey-ml/src/pep.rs` - PEP estimator (375 lines)
- `osprey/crates/osprey-scoring/src/batch.rs` - Feature extraction, 45 features (3363 lines)
- `osprey/crates/osprey-scoring/src/calibration_ml.rs` - LDA calibration scoring
- `osprey/crates/osprey/src/reconciliation.rs` - Cross-run reconciliation (467 lines)
- `osprey/crates/osprey/src/pipeline.rs` - Main pipeline (5229 lines)
- `osprey/crates/osprey-io/src/output/blib.rs` - Blib output (1424 lines)
- `osprey/docs/` - 11 comprehensive algorithm documentation files

### Skyline (integration points)
- `pwiz_tools/Shared/Common/PeakFinding/PeakFinder.cs` - Current peak finder (Crawdad replacement)
- `pwiz_tools/Shared/Common/PeakFinding/IPeakFinder.cs` - Peak finder interface
- `pwiz_tools/Shared/Common/PeakFinding/PeakAndValleyFinder.cs` - Current valley-based detection
- `pwiz_tools/Skyline/Model/Results/Crawdad/Crawdads.cs` - Factory for peak finder
- `pwiz_tools/Skyline/Model/Results/Scoring/` - Scoring infrastructure (mProphet, feature calculators)
- `pwiz_tools/Skyline/Model/Results/Scoring/IPeakScoringModel.cs` - Scoring model interface
- `pwiz_tools/Skyline/Model/Results/Scoring/MProphetScoringModel.cs` - Current scoring model
- `pwiz_tools/Skyline/Model/Results/Scoring/MQuestFeatureCalc.cs` - Feature calculators
- `pwiz_tools/Skyline/Model/RetentionTimes/LoessAligner.cs` - Existing LOESS aligner
- `pwiz_tools/Skyline/Model/Lib/BlibData/BlibDb.cs` - Blib database (81 KB)
- `pwiz_tools/Skyline/Model/Results/PeptideChromData.cs` - Peptide chromatogram data

## Task Checklist

### Planning / Prerequisites
- [ ] Discuss DLL interface design with Michael - what goes in the DLL vs. what stays in Skyline
- [ ] Determine DLL technology: P/Invoke to Rust FFI, or rewrite core algorithms in C++/CLI, or C# port
- [ ] Review Osprey's CWT algorithm in detail and confirm Skyline data structures can feed it
- [ ] Decide on phased rollout vs. big-bang replacement

### Phase 1: CWT Peak Finder (replace Crawdad)
- [ ] Integrate CWT consensus peak detection (Mexican Hat wavelet, scale estimation from median FWHM)
- [ ] Implement pointwise median CWT across multiple transitions
- [ ] Implement boundary extension with zero-crossing and valley guard
- [ ] Replace or supplement PeakAndValleyFinder with CWT-based detection
- [ ] Tukey median polish as complementary/fallback method

### Phase 2: Scoring and Calibration
- [ ] Add Osprey's scoring features (coelution, peak shape, spectral, mass accuracy, RT deviation, median polish)
- [ ] LDA-based calibration scoring for initial peptide selection
- [ ] DIA-NN Pearson sum score
- [ ] Fragment presence filter (2 of top 6 in 3 of 4 continuous spectra)

### Phase 3: FDR Control
- [ ] Native Percolator integration (linear SVM, 3-fold CV, deterministic)
- [ ] Paired library target-decoy strategy
- [ ] Per-run precursor and peptide level q-values
- [ ] Experiment-level FDR with PEP

### Phase 4: Cross-Run Peak Picking and Alignment
- [ ] LOESS alignment to library with robust SD-based RT windows
- [ ] Cross-run reconciliation (consensus RT, boundary transfer, imputation)
- [ ] Multi-charge consensus (same peptide, different charges share boundaries)
- [ ] Second FDR pass on reconciled peaks

### Phase 5: Output and Integration
- [ ] Blib output with Osprey extension tables
- [ ] UI for configuration and results display
- [ ] Testing

## Open Questions

1. **DLL technology**: Should Michael compile Osprey to a native DLL with C FFI that Skyline calls via P/Invoke? Or should key algorithms be ported to C#? The Rust codebase is ~20K lines.
2. **Interface granularity**: Should the DLL expose the full pipeline (give it raw spectra, get back scored peaks), or should individual components be exposed (CWT, Percolator, alignment) for tighter Skyline integration?
3. **IPeakFinder interface**: The current interface is simple (single chromatogram in, peaks out). CWT consensus needs multiple transitions simultaneously. This may require a new interface or a higher-level integration point.
4. **Backwards compatibility**: Should the old peak finder remain available as a fallback option?
5. **Scoring model integration**: Osprey uses 45 features with native Percolator. Skyline uses mProphet with MQuest features. How do we reconcile these?

## Progress Log

### 2026-02-26 - Session 1
- Created GitHub issue [#4046](https://github.com/ProteoWizard/pwiz/issues/4046)
- Created this TODO file
- Explored Osprey codebase on `peak-detection-improvement` branch
- Explored Skyline peak finding, scoring, alignment, and blib infrastructure
- Key finding: Skyline's `IPeakFinder` interface operates on single chromatograms, but CWT consensus needs multiple transitions. Integration will likely need a higher-level entry point (e.g., at `PeptideChromData` level) rather than a drop-in `IPeakFinder` replacement.

## Context for Next Session

The Osprey `peak-detection-improvement` branch has a fully working pipeline in Rust. Michael
has offered to package it as a DLL. The first step is to discuss the DLL interface design with
Michael - specifically what granularity of API makes sense. The current Skyline `IPeakFinder`
interface is too narrow for CWT consensus (it only sees one chromatogram at a time), so
integration will likely happen at a higher level in the Skyline data flow.
