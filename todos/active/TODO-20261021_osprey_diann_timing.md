# TODO-20261021_osprey_diann_timing.md

## Branch Information
- **Branch**: none - a measurement, no code change to pwiz. Osprey is built from #4885's head
  (9719d88da2, `--training-input`) in the worktree `D:\Dev\pwiz-osprey-timing`
- **Base**: `master` + #4885 (open)
- **Created**: 2026-10-20
- **Status**: In Progress - every step timed (Osprey library on GPU and CPU, DIA-NN 2.6.1); figures
  drawn; scripts and this TODO not yet committed
- **GitHub Issue**: (none)
- **Module**: `osprey`
- **PR**: (none)
- **Machine**: i9-9900K (8 cores / 16 threads), 64 GB, GeForce GTX 1650 (4 GB)

## Goal

Redo the Osprey vs DIA-NN wall-clock comparison on the Stellar and Astral test data with each tool
building its own library from the FASTA. Osprey: the one command (`--fasta --training-input <middle
run>`), CarafeSharp predicting with AlphaPeptDeep MS2 and Chronologer RT, fine-tuned on the middle
run. DIA-NN: `--fasta-search --predictor`. **Library generation and the search are timed and
plotted separately** (the library is built on the GPU, the search is not).

Runner: `ai/scripts/Osprey/Benchmark/Run-DiannComparison.ps1` (each step waits for a quiet machine
and logs other processes' CPU to `<step>\contention.tsv` and `timing.tsv`). Plots:
`ai/scripts/Osprey/Benchmark/plot_diann_comparison.py library|search|overlap|summary`.
Runs: `D:\test\osprey-runs\diann-compare\<dataset>\<step>`.

## DIA-NN on the Stellar (unit-resolution linear ion trap)

**Parameters** (Fields et al. 2026, the Stellar DIA-NN design of experiments; confirmed against the
2026 Carafe training search in `example_test_data\stellar\GPF-Data\carafe\diann_train`):

- `--no-ms1` - MS1 scoring off: the largest single gain (+22,390 precursors in the DOE)
- `--mass-acc-cal 900` - calibration starts at 900 ppm (DIA-NN's default is 100 ppm)
- **no `--mass-acc`** - the MS2 accuracy is left automatic so DIA-NN calibrates it; it optimizes to
  roughly 200-550 ppm on this data (349 ppm on run _20)
- the DOE's smaller effects, not carried forward in the manuscript: scan-window radius 5
  (`--window 5`, +6,856), interference removal off (+4,723), `--cal 1` (+2,410)

**Search the Stellar mzML, not the .raw.** DIA-NN 2.3.2 and 2.2.0 both read the Stellar `.raw`
without error but then cannot calibrate: "Using mass accuracy: 20 ppm" on every run and 0 IDs at 1%
FDR, so the MBR library is empty. The same flags on the mzML (msconvert, vendor peak picking)
optimize to 349 ppm and give 30,948 IDs on run _20 alone. Astral `.raw` is fine in DIA-NN (8 ppm,
~138k IDs per run). Every successful Stellar DIA-NN run on this machine read mzML.

**The Windows command** (DIA-NN 2.3.2; library predicted first with `--fasta-search --predictor
--gen-spec-lib` and the same digest flags):

```
C:\DIA-NN\2.3.2\diann.exe ^
  --f D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar\Ste-2024-12-02_HeLa_4mz_sDIA_400-900_20.mzML ^
  --f D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar\Ste-2024-12-02_HeLa_4mz_sDIA_400-900_21.mzML ^
  --f D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar\Ste-2024-12-02_HeLa_4mz_sDIA_400-900_22.mzML ^
  --lib <library.predicted.speclib> --temp <out dir> --out <out dir>\report.parquet ^
  --qvalue 0.01 --matrices --out-lib <out dir>\report-lib.parquet --gen-spec-lib --reannotate ^
  --individual-mass-acc --individual-windows --no-prot-inf --reanalyse --rt-profiling ^
  --no-ms1 --mass-acc-cal 900 ^
  --fasta D:\GitHub-Repo\maccoss\osprey\example_test_data\stellar\hela-filtered.fasta ^
  --met-excision --cut K*,R* --missed-cleavages 1 --min-pep-len 7 --max-pep-len 35 --unimod4 ^
  --min-pr-mz 400 --max-pr-mz 900 --min-pr-charge 2 --max-pr-charge 3 ^
  --min-fr-mz 200 --max-fr-mz 1960 --threads 16
```

Windows traps:
- **A path containing `--` breaks DIA-NN's parser**: `--temp C:\...\C--Users-maccoss...\x` is cut
  at the `--` ("Cannot find the temp folder C:\...\C/"). Claude Code's scratchpad folder names
  contain `--`; use a folder under `D:\test` instead.
- **Pass `--temp`**: without it DIA-NN writes `<run>.raw.quant` / `.mzML.quant` beside the data,
  into the shared test-data folder (and over the March Astral ones).

## Settings shared by both tools

Same FASTA per dataset (Stellar `hela-filtered.fasta`, Astral
`uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta`); trypsin without the P rule (CarafeSharp
enzyme 2 = DIA-NN `K*,R*`), 1 missed cleavage, length 7-35, N-terminal Met excision, fixed
carbamidomethyl C, no variable modifications, charge 2-3, precursor m/z 400-900, fragment m/z
200-1960, 16 threads. The predicted libraries agree: Stellar 242,814 Osprey targets vs 242,482 DIA-NN
precursors; Astral 1,567,310 vs 1,563,884. DIA-NN uses `--reanalyse` (MBR), Osprey its reconciliation.

## Results (quiet machine: other processes' CPU 2.5-8.9% mean per step)

Library generation (separate figure from the search):

| | Osprey (GPU, GTX 1650) | Osprey (CPU) | DIA-NN 2.6.1 |
|---|---|---|---|
| Stellar | 9.4 min | 28.5 min | 1.5 min |
| Astral | 38.1 min | 109.2 min | 8.3 min |

Search of 3 runs (CPU; Osprey against its GPU-built library):

| | Osprey | DIA-NN 2.6.1 | DIA-NN 2.3.2 |
|---|---|---|---|
| Stellar | 5.2 min (`.raw`) | 13.8 min (mzML) | failed on `.raw` |
| Astral | 15.4 min | 30.8 min | 37.1 min |

- Osprey's library is two predictions (it predicts decoys too, 2x DIA-NN's precursors) plus the
  fine-tune and a search of the middle run. On the GPU the fine-tune speeds up 5.2-5.6x and the
  predictions 2.5-3x; the middle-run search (3.3 / 7.9 min) stays on the CPU.
- DIA-NN's Stellar "file loading & calibration" is 6.2 of its 13.8 min (mzML parse plus calibrating
  from 900 ppm).
- IDs per run (run-level and experiment/global q <= 0.01): Stellar DIA-NN 25.8-29.1k, Osprey
  30.0-30.6k (any-run union 31,006 vs 35,143, both 24,769); Astral DIA-NN ~140k, Osprey ~99.5k
  (union 145,590 vs 113,852, both 108,621).
- Figures: `D:\test\osprey-runs\diann-compare\library.png`, `search.png`, `overlap.png`.

## Remaining

- [x] `Build-Osprey.ps1 -Torch cuda` (new switch); Osprey snapshot
      `D:\test\osprey-runs\_bin\osprey-4885-9719d88da2-vendor-cuda`; GTX 1650 confirmed in use
- [x] Osprey library + search on the GPU, Stellar and Astral
- [x] DIA-NN 2.6.1 installed (2026-10-21); it also cannot calibrate the Stellar `.raw` (20 ppm, 0 IDs)
- [x] Stellar DIA-NN search on mzML with `--no-ms1 --mass-acc-cal 900`
- [x] Separate library and search figures plus the overlap UpSet
- [x] Commit the runner, plot script, `Build-Osprey.ps1 -Torch` and this TODO to pwiz-ai
- [ ] IDs at matched entrapment FDP (below), Stellar and Astral; run, experiment and protein overlaps

## IDs at matched entrapment FDP (started 2026-10-21)

Earlier comparisons found Osprey more conservative than DIA-NN at a nominal 1% q-value, so the ID
counts are compared at the same entrapment-estimated FDP instead. `Run-DiannEntrapment.ps1`
(`D:\test\osprey-runs\diann-entrapment\<dataset>`), analysis `plot_entrapment.py`:

- Osprey: the one command with the fine-tuned model above (`--model`, so tuning never sees
  entrapment), `--entrapment 1.0 --entrapment-fasta` the Arabidopsis proteome
  (`uniprot_arabidopsis_feb2023.fasta`): one mass-matched foreign peptide per target (Stellar
  219,523 of 219,523; median |dm| 0.066 Da), `--protein-fdr 0.01`, the FDRBench export.
- DIA-NN 2.6.1: predicts from exactly Osprey's target + entrapment peptides (a peptide FASTA from the
  predicted `.blib`, one entry per peptide and accession) with `--cut ""` (verified: no digest) and
  `--duplicate-proteins` (without it DIA-NN keeps one entry per accession: 28,025 precursors instead
  of ~718k); search with protein inference (`--pg-level 0`) and `--qvalue 0.05`.
- Entrapment accessions are Osprey's FDRBench naming, the paired target's protein + `_p_target`
  (`sp|P55011_p_target|S12A2_HUMAN_p_target`), not the foreign proteome's. Stellar r = 0.9947.
- FDP = N_e (1 + 1/r) / (N_t + N_e) (combined estimator); each tool's q threshold moved to the same FDP.
