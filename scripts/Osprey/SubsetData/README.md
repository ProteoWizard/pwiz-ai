# Osprey subset test data

Scripts that cut the small real-data fixtures in
`pwiz_tools/Osprey/Osprey.Test/TestData/` (`StellarSubset.zip`, `AstralSubset.zip`) out of the
regression data, so `SubsetPipelineTest` can run the whole Osprey pipeline in-process in seconds
(issue #4360). Each zip carries a README.txt describing its contents; the templates are the
`*-README.txt` files here.

| Script | Does |
|---|---|
| `build_subset.py stellar\|astral` | Regenerates a zip byte-identically from the presets in the script |
| `subset_mzml.py` | One isolation window x RT range; MS1 trimmed to an m/z band; float32 with mantissa rounding |
| `subset_library.py` | Library precursors in the rectangle: detected (from a full-run blib) + undetected (by library RT) |
| `subset_libdecoy.py` | The library-decoy + entrapment variant (target, p_target, decoy of each) from stellar-libdecoy-v3 |
| `subset_fasta.py` | The subset's proteins: real records from the dataset FASTA, or `--concatenated` synthetic ones (what `SubsetPipelineTest.WriteSubsetProteinFasta()` writes) |
| `Measure-Subset.ps1` | One candidate subset, cut and run through the tuned one command on the CPU; writes `<run root>\subset-<name>\summary.txt` |

`subset_mzml.py` keeps one window (`--target`) or a contiguous band (`--target-lo/--target-hi`).
`build_subset.py` takes candidate overrides on top of a preset - `--windows N` (centred on the
preset's target), `--rt-min/--rt-max`, `--undetected-max`, `--real-proteins`, `--fasta` - and
without them cuts the preset exactly as committed. `--functional-zip` writes the Skyline
functional-test zip (`TestFunctional\OspreySearchTest.zip`: the three mzMLs and
`stellar-subset-proteins.fasta`, nothing else - the wizard predicts its own library).

## Regenerating

```bash
R=D:/Users/<you>/Downloads/Perftests/osprey-testfiles-mzML-v2
T=C:/proj/pwiz/pwiz_tools/Osprey/Osprey.Test/TestData
python build_subset.py stellar --data-root $R --full-blib <regression Stellar straight>/output.blib --out-zip $T/StellarSubset.zip
python build_subset.py astral  --data-root $R --full-blib <regression Astral straight>/output.blib  --out-zip $T/AstralSubset.zip
python build_subset.py stellar --data-root $R --full-blib <regression Stellar straight>/output.blib --no-libdecoy \
    --functional-zip C:/proj/pwiz/pwiz_tools/Skyline/TestFunctional/OspreySearchTest.zip
```

`$R` is wherever `regression.ps1` extracted the data: `<Downloads>\Perftests`, where Downloads
honours `SKYLINE_DOWNLOAD_PATH` and a relocated Downloads folder (on some machines that is
`E:\Users\<you>\Downloads`, not `C:\Users\...`).

Measuring a candidate (all under `E:\test\osprey-runs\subset-<name>` by default; `-Baseline` adds
the same command without `--training-input`, for the pretrained model's numbers on the same runs):

```powershell
pwsh -File ./Measure-Subset.ps1 -Name w1-rt0-24 -Windows 1 -RtMin 0 -RtMax 24 -UndetectedMax -1 `
    -FullBlib <regression Stellar straight>\output.blib -Exe <snapshot>\Osprey.exe -Baseline
```

The full-run blib comes from `regression.ps1 -Dataset Stellar` (or `Astral`), which leaves
`TestResults\regression-<stamp>\<Dataset>\straight\output.blib`.

## Why the sizes and choices

- **The floor is conservative q-values.** First-pass run q is `(decoys + 1) / targets`, so a run
  needs at least 100 targets ahead of its first decoy for anything to pass 1% FDR, and cross-run
  consensus is gated at a fixed 1% (`ReconciliationConfig.ConsensusFdr`). A 3-minute Stellar slice
  gives ~75 targets per run and the pipeline stops after first pass; 6 minutes gives 128-154.
- **Synthetic proteins.** One 4 m/z window almost never holds two peptides of one real protein,
  and without proteins detected by 2+ peptides the second-pass stratum, parsimony and
  reconciliation never run. `--synthetic-proteins 4` regroups peptides into ~4-peptide proteins.
- **Join detections on (sequence, charge, m/z to 0.01).** Joining a blib to the library on m/z
  and charge alone collides often enough to mislabel a third of a window as detected and to make
  library RT look like a poor predictor (resid SD 3 min instead of 0.18).
- **Rounding.** Unit resolution tolerates 8 m/z mantissa bits dropped (~0.015 Th at 600); HRAM
  keeps all but 3 (~0.5 ppm). Intensity drops 12 (Stellar) or 16 (Astral) bits. Zip size, not
  fidelity, is what these trade against.
- **Astral has two runs** to stay under 5 MB; three-run reconciliation is Stellar's job.

The test helpers that use these zips (`InProcessOsprey`, `BlibComparer`) live in
`Osprey.Test`.
