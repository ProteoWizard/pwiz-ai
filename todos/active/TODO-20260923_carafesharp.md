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
- [x] **M0** CUDA build on the GTX 1650 (`Build-CarafeSharp.ps1 -Torch cuda`, 4.2 GB output). GPU vs CPU
      prediction of the M3 every-50 subset: 98.3% identical fragment lists, all differences at the
      1e-4 rounding floor; 15 s vs 159 s. Fine-tune of 20k RT + 15k MS2 rows: ~4 min on the GPU (RT
      R2 0.9977 on both devices), ~20 min on an uncontended CPU.
- [ ] **M0** WSL/Linux CPU smoke run
- [x] **M1** Proteome (`CarafeSharp.Proteome`, 27 classes): jfasta-compatible FASTA reader,
      compomics enzymes/digest, JavaRandom/JavaText, EntrapmentFastaBuilder (reverse/cycle decoys,
      similarity gate, shuffle and foreign entrapment, ratio), validator, reconciler, `-mz_filter`
      with compomics masses; Carafe-compatible CLI (`-build_entrapment_fasta`, `-reconcile_manifest`).
      Byte-identical (SHA-256) to the June oracle (4 files) and to 12 reference builds from a javac
      build of origin/main (`ai/.tmp/sessions/20260923-carafesharp/ref/`, each with command.txt):
      gated/ungated, ratio 0.5, foreign entrapment (full mouse, ratio 0.25, exhausted subset),
      `-mz_filter`, enzyme 1 / 2 missed cleavages / clip / `rev_` / charges 1-4, plus 13 fixture
      configs and `-reconcile_manifest`. C# 2.7-5.9 s vs Java 4.2-17.5 s. Committed `0d209915ed`.
      Carafe quirks reproduced: `-decoy_seed` unused; code defaults differ from help (miss_c 2,
      m/z 300-2000, build charges 2-3); foreign entrapment always gated; jfasta stops at an empty
      sequence. The June run did NOT pass `-clip_n_m` to stage 1 despite the GUI setting.
- [x] **M2** Inference parity against Carafe's own prediction outputs (`CarafeParityTest`, opt-in via
      `CARAFESHARP_CARAFE_REFERENCE` / `CARAFESHARP_CARAFE_FINETUNED`): 4,000 precursors each, pretrained
      MS2 max |diff| 2.6e-6 (99.9th pct 8.9e-7, no cutoff flips), RT 2.4e-7, iRT 3.5e-5; Carafe's
      fine-tuned ms2_model.pt/rt_model.pt load and match to 2.4e-6 / 1.8e-7. General mode, C+57 only -
      variable mods (Oxidation, Phospho) still to be covered.
- [x] **M3** `predict` writes a blib (annotations, DecoyPairs, decoys and entrapment). Committed
      `b1913426d3` (background agent; verified here: 30 tests, inspection clean). Parity on the Stellar
      oracles: peptide forms and fragment m/z bit-identical, assembled rows character-identical from
      Carafe's own predictions, 98.4% identical fragment lists end to end (rest is +/-1e-4 rounding).
      Full generic library 483,608 precursors in 30 min CPU. Osprey part A reads it with 0 annotation
      failures (7,977,491 peaks typed). Stage-3 search of _21 with the June flags
      (`D:\test\osprey-runs\carafesharp-blib-train`): 23,105 run precursors / 21,061 peptides /
      2,971 proteins vs 23,036 / 21,007 / 2,986 with Carafe's TSV (`D:\test\osprey-runs\carafe-june-train`,
      same exe). Skyline-daily 26.1.1.209 (SkylineCmd, `D:\test\carafesharp-runs\skyline-check`) opens the
      subset blib: 7,485 peptides, all 23,036 transitions picked from the library. Old June oracles predate maccoss/carafe#11 (M-clip under NoCut).
- [x] **M4** Osprey part B: training export (companion TODO)
- [ ] **M5** `train`: training set, masking policy, Adam fine-tune, metrics, model selection.
      Trainer done on side branch `Skyline/work/20260923_carafesharp_train` (worktree
      `D:\Dev\pwiz-carafesharp-train`, from `0d209915ed`; merge back after M3): NumpyRandomState
      (legacy MT19937 + pandas `sample` semantics, verified against numpy 2.5/pandas 3.0),
      TrainingSplit (Carafe's n_test, seed-1337 sampling, +50 per top-10 mod, sequence-disjoint
      test), FineTuneSettings (adjust_batch_size, per-epoch warmup-cosine with epoch 0 at lr 0),
      ModelFineTuner (Adam, masked L1 with modloss columns in the denominator, clip 1.0, numpy-global
      epoch shuffles shared RT -> MS2), Ms2Metrics (masked PCC/COS/SA/SPC over 8 columns, medians),
      RtMetrics (r2, median |error|, groupby-median collapse), CarafeSharp.Training
      (CarafeTrainingDirectory reader for psm_pdv/fragment tables/rt_train_data; FineTuneRun writes
      rt/ms2 .safetensors + model.json). On Carafe's own June training data: held-out rows IDENTICAL
      to Carafe's (RT 999 forms; MS2 904 spectra, 40,232 values in the same order) and pretrained
      scores equal Carafe's to 4 decimals (PCC 0.9574 COS 0.9606 SA 0.8206 SPC 0.8593; RT R2 0.8635).
      Full CPU fine-tune on Carafe's own June training data (`CARAFESHARP_FINETUNE_FULL=1`, Release,
      2.5 h on CPU: RT 4,585 s, MS2 4,264 s) lands on Carafe's GPU result:
      RT R2 0.9979 / median |err| 0.00465 (Carafe 0.99788 / 0.004675); MS2 PCC 0.9771 COS 0.9794
      SA 0.8706 SPC 0.9006 (Carafe 0.9768 / 0.9791 / 0.8698 / 0.9008); fine-tuned MS2 kept (beats
      pretrained on all four), as Carafe did.
      Fine-tune port committed `fb075aa7b6` (cherry-picked from the trainer branch).
      Osprey-export consumer committed `92eb4436e8`: `OspreyTrainingExport` reader,
      `OspreyModificationMapper` (UniMod/mass -> alphabase, N-term by leading bracket),
      `OspreyMaskingPolicy` = Carafe's rules exactly as `get_ms2_matches_diann` applies them (spec:
      `ai/.tmp/sessions/20260923-carafesharp/carafe-masking-spec.md`; durable copy in
      `pwiz_tools/CarafeSharp/docs/02-masking.md`) read from Osprey evidence: ordinal-1 always masked;
      out-of-scan-range ions valid zeros; matched ions masked by shared apex peak (other claimants via
      `shared_apex_n`, same-PSM collisions via ion_mz+apex_mz_error), `corr_polish` < -cor, two-sided
      boundary skew (Carafe's formula on xic_start/xic_end/apex), intense b2/y2 not clean; PSM gates
      matched >= 4, valid >= 4, top ion (ordinal >= 2) valid; intensities / top ion.
      `OspreyTrainingSet` (q filter, entrapment excluded, best run per precursor, RT one row per form by
      min q, rt_norm = apex_rt / (rt_max + 0.1)), `TrainingExportLocator`, Carafe `-ms` CLI
      (`-i` blib or exports, `-ms` names runs; Carafe code defaults; XIC flags warned as Osprey's),
      `ModelTrainer` (training tables, fine-tune, Carafe `model_evaluation_metrics.json` + `meta.json`,
      then the library from `-db` with the fine-tuned models; safetensors load through `-model_dir`).
      Against Carafe's June valid table (Osprey re-run of the June training search,
      `D:\test\osprey-runs\carafe-june-train`; export beside the mzML, no --output-dir):
      14,146 of Carafe's 14,806 spectra in the export, 97% on the same apex scan; slot agreement
      85.0%; kept 15,345 (12,404 also kept by Carafe). corr_polish beats corr_reference (83.5%);
      thresholds 0.75-0.85 and skew on/off move agreement by <1 point. Opt-in
      `OspreyMaskingParityTest` (`CARAFESHARP_OSPREY_TRAINING_EXPORT`).
      Running: CPU end-to-end on the CarafeSharp pipeline's own export
      (`D:\test\carafesharp-runs\stellar-m5`, exe `_bin\m5-92eb443`): 21,061 RT forms, 15,318 MS2
      spectra, then the 483k-precursor library from `osprey_library_db_peptides.fasta` as blib.
      Stage 6 (all 3 Stellar runs, June flags, same Osprey exe `_bin\carafe-export-0a0b744`,
      `D:\test\osprey-runs\stellar-stage6-*`, FDRBench via `py/stage6_summary.py`):

      | Final library (MS2 model / RT model) | 1st-pass per run | Final per run | Experiment | Peptides | Proteins | FDP |
      |---|---|---|---|---|---|---|
      | Carafe June TSV (Carafe / Carafe) | 22,868-23,959 | 23,066-23,918 | 20,712 | 19,016 | 3,977 | 0.65% |
      | blib, GPU-predicted (Carafe / Carafe) | 23,021-23,915 | 22,600-23,282 | 21,176 | 19,441 | 4,007 | 0.63% |
      | blib, CPU-predicted (Carafe / Carafe) | 23,114-23,908 | 25,728-26,640 | 28,309 | 25,817 | 4,278 | 0.56% |
      | blib (CarafeSharp / Carafe) | 23,048-23,786 | 26,827-27,170 | 29,970 | 27,169 | 4,297 | 0.64% |
      | blib (Carafe / CarafeSharp) | 23,015-23,966 | 26,318-27,147 | 30,234 | 27,554 | 4,286 | 0.62% |
      | blib (CarafeSharp / CarafeSharp), end to end | 23,156-23,958 | 25,972-26,576 | 28,812 | 26,057 | 4,289 | 0.64% |

      CONCLUSION: CarafeSharp matches Carafe. The experiment-level count is BIMODAL in Osprey (about 21k
      or 28-30k at the same measured FDP): the same Carafe models predicted on the GPU and on the CPU
      (1e-4 rounding differences) land in different groups. The first-pass per-run counts, which are
      stable, agree within 0.5% in every arm. The low group has the experiment count below the per-run
      counts and about twice the experiment-q floor raises; its first-pass model weights and bias differ.
      An Osprey robustness issue to investigate on its own (memory: osprey-stage6-bimodal-ids).
      June and current Osprey give identical apex RTs and boundaries on the 19,988 shared precursors.
      (June Carafe GUI numbers, older Osprey: 27,479 at 0.98% - not comparable.)
      CPU vs GPU fine-tune on the same data: MS2 PCC 0.9821/0.9823, COS 0.9835/0.9838, RT R2 0.9977 both.

- [ ] **M6** `ai/scripts/CarafeSharp/Run-CarafeSharpWorkflow.ps1`; Stellar then Astral end to end
      Stellar done: all stages 1a-6 from hela-filtered.fasta with the CUDA build and the part-B Osprey
      (`D:\test\carafesharp-runs\stellar-workflow`, log `ai/.tmp/sessions/20260923-carafesharp/workflow-stellar.log`):
      1a 0.03 min, 2 2.1 min, 3 4.6 min, 4-5 7.3 min, 6 7.6 min. Training 23,169 precursors -> RT R2 0.9978,
      MS2 COS 0.9853; final library 968,394; stage 6 31,460 precursors / 28,637 peptides / 4,338 proteins,
      combined FDP 0.66% (high Osprey mode; gated stage 1b, so not June-comparable). Astral still to do.

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

- M1 ported by a background agent; verified here (20/20 tests with all opt-in parity folders,
  inspection clean) and committed `0d209915ed`.
- Osprey companion: part A (blib annotations) committed `cdbab8c8ac` in `D:\Dev\pwiz-osprey-export`;
  part B (training export) in progress there. Developer approved downloading the regression
  bundle (staging to `~/Downloads/Perftests`) and the CUDA libtorch packages.

## Next steps

1. M3 (in progress, background agent): peptide-form enumeration parity vs `peptide_forms_*.parquet`,
   fragment m/z parity vs `*_ms2_mz_df`, library assembly parity vs `carafe_spectral_library.tsv`,
   `BlibLibraryWriter` (annotations per Osprey part A grammar, empty-string text columns,
   mzObserved == peak m/z), Carafe-compatible `-lf_type DIA-NN|blib`, `-model_dir`.
2. CUDA build (`-Torch cuda`) and a GPU vs CPU prediction comparison once M3 lands.
3. Osprey regression gate on part A (Release exe in the worktree; do not rebuild Release while it runs).
