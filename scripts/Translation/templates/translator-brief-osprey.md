# Translator brief: Osprey

Osprey is a command-line DIA proteomics search engine (it will be integrated into Skyline). It
reads mass spectrometry data files (mzML or vendor raw files) and a spectral library, finds each
library precursor's chromatographic peak in each file, scores the peaks, estimates false discovery
rates (FDR) with target-decoy competition and a machine-learning rescorer (Percolator-style SVM, or
gradient-boosted trees), and writes a BiblioSpec (.blib) library and reports that Skyline reads.

## Who reads this text
The console log is Osprey's only user interface. Its reader is a mass spectrometrist running a
search - often a multi-hour, many-file run on a workstation or an HPC cluster - not a programmer.
Lines are scanned by eye and sometimes grepped. Keep them short and factual; do not add politeness
beyond the style guide's `〜してください` / `请〜` for remedies.

Kinds of strings you will see:
- **Progress lines**: "Loading spectral library from {0}...", "Scoring {0:N0} precursor candidate peaks".
- **Summary lines**: "Paired {0:N0} of {1:N0} library decoys with their targets ({2:F1}%)".
- **Warnings / errors with a remedy**: "... Delete it and score the file again."
- **Enum display names**: short labels like "peptide", "precursor and peptide", "auto", "unit".
- **Feature names**: short noun phrases naming scoring features ("Peak area (log10)"). Keep labels,
  feature names, enum names and column-like headings TERSE and noun-stacked like the English -
  never expand them into descriptive phrases. (The blind evaluation's clearest miss: "Apex Analyte
  Ion Count" became `ピーク頂点時のアナライトイオン数` where reviewers wanted `頂点アナライトイオンカウント`.)
- **Command-line help** (`OspreyCommandArgUsage.resx`): argument descriptions for `--help`.
- **Singular / plural pairs**: "...from 1 file" and "...from {0:N0} files" are separate resources;
  translate both (the singular may become the same shape as the plural in ja/zh - that is fine).

## Domain vocabulary (use the glossary for the renderings)
- **Library precursors**: rows of the spectral library (targets).
- **Precursor candidates**: targets + decoys being searched.
- **Precursor candidate peaks**: one candidate's scored peak in one run (file).
- **Run**: one MS acquisition / data file (ja `ラン`). "this run" in a message about settings or
  builds means this Osprey invocation (ja `実行`, zh `本次运行`).
- **First pass / second pass**: Osprey's FDR is computed twice - per run first, then across the
  whole experiment after cross-run reconciliation.
- **Cross-run reconciliation**: aligning each peptide's integration boundaries across runs so it is
  quantified at the same chromatographic position everywhere. Actions: peaks re-picked, peak
  boundaries imputed (Skyline's imputation vocabulary), peak boundaries imputed for missing peaks.
- **Intermediate file**: a file Osprey writes between tasks (never call it anything else).
- **Scores file** (`.scores.parquet`), **spectra cache** (`.spectra.bin`), **library cache**.
- **Tasks**: the pipeline can run as separate tasks (for HPC); task names like `PerFileScoring`,
  `FirstPassFDR`, `PerFileRescoring`, `SecondPassFDR`, `ModelDiagnostics` are identifiers - they
  arrive as `{N}` arguments or, if still present in text, must stay exactly as written.
- **Model diagnostics**: optional report panels about the trained scoring model.
- **Entrapment / FDRBench**: an FDR-validation method that adds known-false peptides; FDRBench is a tool name.
- **Calibration**: m/z and retention-time calibration from high-confidence matches ("calibrator
  yield" = how many targets the calibration step found).
- **Protein parsimony / protein groups / protein FDR**: protein inference.
- **Gradient-boosted trees** hyperparameters (max depth, learning rate, subsample, colsample,
  lambda, alpha, gamma, min child weight): keep `lambda`, `alpha`, `gamma`, `colsample`, `subsample`
  in English (they are parameter names users look up); translate "max depth", "learning rate",
  "min child weight" descriptively.
- Numbers use format items (`{0:N0}` thousands separators, `{1:P1}` percent, `{2:F1}` fixed); the
  culture formats them - never write digits or `%` signs for them yourself, and never drop a `%`
  that is literal text in the English (e.g. `{2:F1}%`).

## Never translate
Anything in the style guide's "Never translate" list, plus: file names and patterns
(`*.FirstPassFDR.osprey.task`, `reconciliation.json`), column / metadata names (`entry_id`,
`format_version`, `file_stems`, `osprey.reconciled`), cvParam accessions (`MS:1000828`), build
commands (`/p:IAgreeToVendorLicenses=true`, `bjam ...`, `msconvert --filter "..."`), `[TASK]`
markers, and the exact spelling of `--flags`.
