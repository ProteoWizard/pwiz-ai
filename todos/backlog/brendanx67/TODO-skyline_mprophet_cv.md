# TODO-skyline_mprophet_cv.md -- Modernize Skyline's mProphet: add cross-validation to the LDA

## Status
**Backlog / not started.** Strategic direction from Brendan (2026-07-13), to be picked up once
Osprey dev/test intensity relaxes. No branch yet.

## The problem
Skyline's mProphet is **LDA without cross-validation**. That is a long-standing, tangible
weakness and the reason Mike MacCoss cites mProphet as "broken" / inferior to Percolator: the
weights are trained and applied on the same target-decoy population, so there is no
fold-to-fold stability signal and the scores are optimistic on the training set.

## Why it is close
pwiz_tools already holds the ML primitives in C#, adjacent to Skyline:

- a full **C# Percolator** (`Osprey.FDR`), with 3-fold CV built in
- **LDA with CV** in Osprey's calibration phase (the `calibration_ml` equivalent)

So modernizing mProphet is mostly wiring-up, not building. Much of what Osprey learns is
expected to flow into Skyline this way.

## First step (highest leverage, lowest risk)
Add **k-fold CV to the existing mProphet LDA**. This is a training-protocol change only:

- group target-decoy pairs, and all charge states of a peptide, into the same fold
- train per fold, average the fold weights
- feature set and score meaning are unchanged
- reference implementation: Osprey's `calibration_ml` / Percolator CV

It must be **opt-in and versioned** - a new peak-scoring model version - because CV changes
the trained weights and therefore scores and peak picking on the countless existing Skyline
documents. Existing documents keep the model version they were built with.

## Deeper follow-on
Port Osprey's **entire calibration phase** (pre-extraction m/z + RT recalibration from a
confident anchor set) to run before Skyline's chromatogram extraction and scoring. A larger
architectural change to the extraction pipeline, but arguably higher value.

## Background
For the LDA-vs-SVM landscape (why LDA concentrates weight on one of a covarying pair while an
L2 SVM spreads it, and why percent-contribution is a description rather than importance), see
the Osprey model-diagnostics discussion in pwiz issues #4467 and #4550.
