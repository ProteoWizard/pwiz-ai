# TODO-20260923_carafesharp.md

## Branch Information
- **Branch**: `Skyline/work/20260923_carafesharp`
- **Base**: `Skyline/work/20260612_net8_port` (PR [#4619](https://github.com/ProteoWizard/pwiz/pull/4619), .NET 10 port; not yet merged)
- **Created**: 2026-09-23
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)
- **Companion**: `ai/todos/active/TODO-20260923_osprey_carafe_export.md` (the Osprey-side PR this depends on)

## Objective

A C# port of Carafe (the maccoss/carafe fork, v2.2.0) at `pwiz_tools/CarafeSharp`, command
line first (the GUI is phase 2), that closes the library loop around Osprey:

1. build a .blib library from a FASTA with the pretrained AlphaPeptDeep models;
2. search with Osprey;
3. fine-tune the MS2 and RT models on Osprey's results and build a new .blib.

Rules: only Osprey reads raw data (CarafeSharp takes everything from Osprey's blib and a new
training sidecar); fragment masking uses Osprey's median-CWT peak, median polish and
shared-fragment evidence; every library is .blib; results should come out close to Carafe's.

Approved plan: `C:\Users\maccoss\.claude\plans\i-would-like-to-starry-gizmo.md` (machine-local);
the durable parts are below and in `pwiz_tools/CarafeSharp/docs/`.

## Decisions

- **Neural nets in TorchSharp, natively** (developer's choice over a Python bridge):
  peptdeep's ModelMS2Bert and Model_RT_LSTM_CNN re-implemented with identical state_dict
  keys, pretrained `.pth` loaded directly, fine-tuning in C#. Python is development-only.
- **TorchSharp 0.106.0 / libtorch 2.10.0**, not 0.107.0 (Windows load failure
  dotnet/TorchSharp#1567; glibc 2.34 on Linux). CPU runtime by default;
  `-Torch cuda` / `/p:CarafeSharpTorch=cuda` for CUDA 12.8 (about 4 GB, GTX 1650 sm_75 ok).
- **No TorchSharp.PyBridge**: it cannot read the RT checkpoint (shared LSTM storage at
  non-zero offsets, PyBridge #18) and its `load_py` clobbers `requires_grad`. CarafeSharp has
  its own `PthReader` (Razorvine.Pickle) and `SafetensorsFile`.
- **Evidence in Osprey, masking policy in CarafeSharp** (thresholds tunable without a re-search).
- **Stage-1 parity is byte-identical** with Carafe `-build_entrapment_fasta`.
- **No pwiz-sharp reference** from CarafeSharp (no spectrum reading), so the #4658 layout
  hoist does not touch it. Only `pwiz_tools/Shared/CommonUtil` (command-line framework).
- Two PRs stacked on #4619: Osprey changes first (own regression gates), CarafeSharp after.

## Milestones

- [x] **M0** scaffold: `CarafeSharp.sln` (Core, Models, exe, Test), own `Directory.Build.props/.targets`,
      `ai/scripts/CarafeSharp/Build-CarafeSharp.ps1` (the Deny-DirectBuildTest hook blocks raw dotnet build)
- [x] **M0** TorchSharp spike: pretrained ms2.pth and rt.pth load with strict key/shape checks on
      Windows CPU; iRT kit peptides predict in order; LGGNEQVTR/2 y ions dominate
- [ ] **M0** CUDA build on the GTX 1650 (needs the 2.7 GB libtorch-cuda restore - ask first)
- [ ] **M0** WSL/Linux CPU smoke run
- [ ] **M1** Proteome: FASTA, compomics-compatible digest, JavaRandom, EntrapmentFastaBuilder
      (reverse/cycle decoys, similarity gate, shuffle and foreign entrapment, ratio), manifest
      write/validate/reconcile; `digest` verb; byte-identical tests
- [x] **M2** Inference parity against Carafe's own prediction outputs (`CarafeParityTest`, opt-in via
      `CARAFESHARP_CARAFE_REFERENCE` / `CARAFESHARP_CARAFE_FINETUNED`): 4,000 precursors each, pretrained
      MS2 max |diff| 2.6e-6 (99.9th pct 8.9e-7, no cutoff flips), RT 2.4e-7, iRT 3.5e-5; Carafe's
      fine-tuned ms2_model.pt/rt_model.pt load and match to 2.4e-6 / 1.8e-7. General mode, C+57 only -
      variable mods (Oxidation, Phospho) still to be covered.
- [ ] **M3** `predict` writes a blib (annotations, DecoyPairs, decoys and entrapment); Osprey
      searches it (needs Osprey part A); compare stage-3 IDs with Carafe (21,548 run IDs, 3,948 protein groups)
- [ ] **M4** Osprey part B: training export (companion TODO)
- [ ] **M5** `train`: training set, masking policy, Adam fine-tune, metrics, model selection
- [ ] **M6** `ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1`; Stellar then Astral end to end

## Reference data on this machine (developer's own Carafe runs)

`D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar\`:
- Stellar HeLa 400-900 `Ste-2024-12-02_HeLa_4mz_sDIA_400-900_{20,21,22}.mzML` (+ .raw),
  `hela-filtered.fasta` (training FASTA), `uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta`.
- `carafe-osprey-entrapment/` - Carafe 2.2.0 Workflow 5, 2026-06-30, BEFORE the similarity gate
  (fork PR #9), so it is the oracle for `digest --no-similarity-gate`:
  `osprey_library_db_peptides.fasta` + `osprey_library_db_pairing.tsv` (218,871 quartets),
  training DB 218,921 pairs; `osprey_initial_library/peptide_forms_*.parquet` (Java prediction
  inputs) with `*_ms2_df/_ms2_pred/_ms2_mz_df/_rt_pred.parquet` (Python outputs) - the M2
  parity oracle, no Python venv needed; `osprey_new_library/` training files
  (`psm_pdv.txt`, `fragment_intensity_df.tsv`, `fragment_intensity_valid*.tsv`,
  `rt_train_data.tsv`, `meta.json`), fine-tuned `ms2_model.pt`/`rt_model.pt`,
  `model_evaluation_metrics.json` - the M5 comparison.
- `carafe-osprey/` - the same workflow without entrapment.
- Astral: `D:\GitHub-Repo\maccoss\osprey\example_test_data\astral\` (3 runs, Carafe outputs).
- Carafe source: `D:\GitHub-Repo\maccoss\Carafe` is 5 commits behind origin/main (missing the
  similarity gate, pairing validator, NoCut fix); port from `git show origin/main:...`. No Maven;
  build a reference jar with javac against `target/carafe-2.2.0/lib/*` if needed.
- Pretrained models: `~/peptdeep/pretrained_models/pretrained_models.zip` (pinned v1, present).

## Progress Log

### 2026-09-23
- Planned (three explorations, model/TorchSharp research, Osprey hook design).
- Branched `Skyline/work/20260923_carafesharp` from `origin/Skyline/work/20260612_net8_port`
  @ `bba770990a` (upstream unset so a push cannot land on #4619).
- M0: scaffold, Build-CarafeSharp.ps1, Core (alphabase masses, modification table embedded
  verbatim, PeptideForm/PrecursorForm), Models (featurizer, BERT, building blocks, MS2 and RT
  models, PthReader, SafetensorsFile, pinned PretrainedModels), 4 tests passing.
- Wrote `pwiz_tools/CarafeSharp/docs/01-model-spec.md` from the planning research.

- M2: `CarafeSharp.IO/ParquetColumns` (Parquet.Net compiled against pwiz's patched
  `Shared/Lib/Parquet/ParquetNet.dll` - stock 4.25.0 fails on pyarrow metadata "don't know how to
  skip type Set"); `Ms2Model/RtModel.FromPthFile` for Carafe's fine-tuned checkpoints; ReSharper
  inspection clean (`CarafeSharp.sln.DotSettings` copied from Osprey). Committed `e963565660`.

## Next steps

1. M1 port of EntrapmentFastaGear / DecoySimilarityGate / ForeignEntrapmentSource from
   `origin/main`, byte-parity against `osprey_library_db_*`.
2. Start the Osprey companion branch (part A: blib annotations and DecoyPairs).
