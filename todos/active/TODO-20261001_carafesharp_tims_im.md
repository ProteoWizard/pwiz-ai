# TODO-20261001_carafesharp_tims_im.md

## Branch Information
- **Branch**: `Skyline/work/20261001_carafesharp_tims_im` (worktree `D:\Dev\pwiz-carafesharp-im`)
- **Base**: `Skyline/work/20260923_carafesharp` (PR [#4717](https://github.com/ProteoWizard/pwiz/pull/4717), CarafeSharp)
- **Created**: 2026-10-01
- **Status**: Merged into #4717 (016105f3ba, 2026-10-02); follow-ups below
- **Module**: `osprey`
- **PR**: none of its own: merged into [#4717](https://github.com/ProteoWizard/pwiz/pull/4717) at the developer's request
- **Follows**: `ai/todos/active/TODO-20260923_carafesharp.md`

## Objective

Predicted libraries with timsTOF ion mobility (1/K0) from AlphaPeptDeep's pretrained CCS model, as
Carafe 2.2's `-ccs` writes them. The developer needs these before Osprey can be extended to analyze
timsTOF data (2026-10-01: "We need this before we can begin to improve Osprey to analyze Tims-tof data").
Fine-tuning the CCS model is out of scope: it needs observed 1/K0 per precursor from a timsTOF search,
which Osprey does not do yet.

Reference: Carafe2 for timsTOF DIA (PMC13060252, doi 10.64898/2026.03.27.714846). Carafe's IM path:
`ai_pred.py predict_ccs` / `ai.py train_ccs` with `models.py` `Model_CCS_LSTM` and alphabase's
`ccs_to_mobility_bruker`; Java writes TSV `IonMobility` (`%.4f`) and blib `ionMobility` with type
`inverseK0(Vsec/cm^2)`, CCS NULL.

## Tasks

- [x] `ModelCcsLstm` + `EncoderAaModChargeCnnLstmAttnSum` (the RT encoder with a charge channel, 36 inputs;
      decoder 257), `CcsModel` (pretrained `generic/ccs.pth`, or a Carafe `ccs_model.pt`)
- [x] `TimsMobility.CcsToInverseK0` (alphabase constants 1059.62245, gas mass 28) and
      `AlphabaseFragmentMz.CalculatePrecursorMz` (alphabase's precursor m/z)
- [x] `-ccs` (`LibrarySettings.PredictIonMobility`), for library prediction and, as Carafe on Osprey's
      results, with training (no CCS fine-tune; the library after training predicts 1/K0, with a warning).
      The CCS model by `-tf` as Carafe's `ai_pred.py`: `all` the folder's `ccs_model.pt`, else generic;
      `-tf rt|ms2` with `-ccs` refused (Carafe predicts none and fails)
- [x] TSV `IonMobility` column (`CarafeLibraryTsvWriter.HEADER_WITH_ION_MOBILITY`); blib `ionMobility` with
      type 2 in RefSpectra and RetentionTimes, CCS NULL as Carafe writes it: given a CCS, Skyline converts it
      with the data file's calibration instead of using the library's 1/K0
      (`Library.GetLibraryMeasuredIonMobilityAndCCS`), and it derives the CCS from the 1/K0 itself
- [x] CCS clipped at 0 (Carafe's `ModelInterface.min_pred_value`); the 1/K0 is derived from the CCS when the
      spectrum is built (`LibrarySpectrumBuilder.Build`), like the RT
- [x] Tests: `TestCcsPrediction` (23 precursors against Carafe's Python: identical CCS and 1/K0 on this
      CPU), `TestLibraryIonMobility` (end to end, pretrained and folder `ccs_model.pt`, and without `-ccs`),
      writer and command-line tests
- [x] End to end against the Carafe 2.2.0 jar (`D:\test\carafesharp-runs\ccs-parity`, 30 HeLa proteins,
      1,268 precursors, CPU): TSV IonMobility identical on every row; blib 1/K0 identical to 2e-16 where
      the float32 CCS is (753/777 unmodified), else 1-2 ulps of CCS from batch composition (max 1.5e-7)
- [x] Docs: `docs/01-model-spec.md` CCS section, `models/alphapeptdeep-v1/README.md`
- [x] `/code-review max` (2026-10-01): 15 findings. Fixed: `-tf` model choice, the clip, CCS NULL in the
      blib, `-ccs` with training, `plot_timings.py` (pwiz-ai) parsing the new CCS time, test tolerances
      (6e-6 1/K0 for charge 1), the TSV `FormatRows` flag now required, header fragments, the 1/K0 derived
      in the spectrum, duplicated test setup, table indentation. Red before green: the clip and `-tf` tests
      fail without their fixes. Not done (recorded below): efficiency, ion mobility units, model-class reuse,
      a committed TSV parity test against a Carafe `-ccs` reference
- [x] Unchanged without `-ccs` (developer's request): the workflow's stages 1a-5 on Stellar (CPU, same Osprey), with
      #4717's build and the branch's, give identical libraries, Osprey results, export data and fine-tuned models; only
      timestamps, paths and the library file identity hash differ (`D:	est\carafesharp-runs\ccs-ab\compare_ab.txt`,
      `compare_ab_explained.txt`)
- [x] Merged into #4717 (016105f3ba) with the test-data fetch/verify switch (7cd987b21f): 83/83, inspection 0, pushed
- [ ] Later: check the library in Skyline with a timsTOF run (IM filtering from the library), and in
      DIA-NN (`IonMobility` column)

## Follow-ups (from the review, not done)

- Efficiency: CCS runs per precursor after RT on the predicting thread (estimated +15% CPU, +27% GPU on the
  library step) and re-featurizes what MS2 just built; share the features, or overlap CCS with MS2 on CUDA.
  Measure first; `-ccs` is opt-in.
- Ion mobility units are implied (1/K0 whenever a value is set); store the kind with the value before a
  second kind (FAIMS CV, drift time, Osprey's observed values) arrives.
- `CcsModel` follows `RtModel`'s template line for line; a shared load-for-inference helper would serve all three.
- No committed test compares the TSV IonMobility column with a Carafe `-ccs` reference: the test reader
  (`CarafeLibraryTsv`) accepts only `HEADER`, and the reference would need a test-data package.
- `docs/04-testing.md` line 112 says the CPU pass runs 74 tests; it ran 81 before this branch (pre-existing).

## Progress Log

### 2026-10-01
- Branched from #4717 at a7bf9f70be. Carafe's CCS model is the ported RT network plus one charge input;
  `generic/ccs.pth` was already in the committed `pretrained_models.zip`.
