# Osprey reads DIA-NN's .parquet spectral library directly

**Status**: Backlog. Written 2026-10-28 on MACS2 (Brendan), while setting up Osprey vs DIA-NN 2.7.0 runs.
**Module**: `osprey`
**Related**: [TODO-20261021_osprey_diann_timing.md](../active/TODO-20261021_osprey_diann_timing.md),
[TODO-20261028_osprey_diann_fdr_gap.md](../active/TODO-20261028_osprey_diann_fdr_gap.md) (both use the
library swap this would simplify)

## Goal

`Osprey -i runs... -l report-lib.parquet -o out.blib` searches a library DIA-NN predicted or built,
with no conversion step. Today Osprey's `-l` takes a `.blib` or the DIA-NN import `.tsv`
(`DiannTsvLoader`), and DIA-NN 2.x no longer writes that `.tsv`, so every DIA-NN library reaches
Osprey through a Python conversion. Cross-compatibility with DIA-NN matters to users, and it is what
makes the library-swap comparisons (Osprey on DIA-NN's predictions, to separate prediction from
search) a one-flag change.

## What DIA-NN 2.7.0 writes (measured 2026-10-28, MACS2)

- `--fasta-search --predictor --gen-spec-lib --out-lib lib.tsv` with no runs writes the binary
  `lib.predicted.speclib`; the `.tsv` name is ignored. The `.speclib` format is undocumented: do not
  reverse-engineer it.
- `diann --lib lib.predicted.speclib --gen-spec-lib --out-lib x.parquet` converts it to `.parquet`.
  Asking for `x.tsv` writes `.parquet` too. A search with `--gen-spec-lib --out-lib <name>.parquet`
  writes its empirical library in the same format.
- The `.parquet` is long format, one row per fragment. Columns: `Precursor.Id`, `Modified.Sequence`,
  `Stripped.Sequence`, `Precursor.Charge`, `Proteotypic`, `Decoy`, `N.Term`, `C.Term`, `RT`, `IM`,
  `Q.Value`, `Peptidoform.Q.Value`, `PTM.Site.Confidence`, `PG.Q.Value`, `Precursor.Mz`, `Product.Mz`,
  `Relative.Intensity`, `Fragment.Type`, `Fragment.Charge`, `Fragment.Series.Number`,
  `Fragment.Loss.Type`, `Fragment.Score`, `Exclude.From.Quant`, `Protein.Ids`, `Protein.Group`,
  `Protein.Names`, `Genes`, `Flags`, `Source.Id`.
- Targets only (`Decoy` all 0 in a predicted library). `RT` is DIA-NN's normalized scale (-74 to 198
  in the test). Modifications are UniMod in `Modified.Sequence`, e.g. `C(UniMod:4)`, which
  `DiannTsvLoader` already parses (`UnimodIdToMass`).
- Test files: `D:\Users\brendanx\test\diann\libformat-test\` on MACS2 (20-protein FASTA, `.speclib`,
  `.parquet`, 2,637 precursors / 31,497 fragment rows). Regenerate anywhere with the two commands above.

## Existing pieces

- The conversion already exists as a script: `ai/scripts/Osprey/Benchmark/diann_library_swap.py convert`
  (its `COLUMNS` map, DIA-NN parquet -> the names `DiannTsvLoader` reads). It also rewrites protein
  accessions from a map so a swapped library keeps the Osprey library's accessions and decoys; that
  part is specific to the swap and stays in the script.
- `.tsv` loading: `pwiz_tools/Osprey/Osprey.IO/DiannTsvLoader.cs`, entered from
  `LibraryLoader.ParseTsv` (`Osprey.IO/LibraryLoader.cs:442`), which also derives the cached `.blib`
  (`<library>.tsv.blib`).
- Parquet.Net is already a dependency of `Osprey.IO` (pwiz's patched build,
  `Shared\Lib\Parquet\ParquetNet.targets`).

## Plan

1. A `DiannParquetLoader` beside `DiannTsvLoader`, sharing its row-to-`LibraryEntry` assembly,
   modification parsing, fragment typing check and min-fragment rule, so the two formats cannot drift.
   Read only the columns the `.tsv` path uses; stream by row group (a human library is ~3 M
   precursors x ~12 fragments).
2. `LibraryLoader` dispatches `.parquet` to it, and the derived `.blib` cache works as for `.tsv`
   (`<library>.parquet.blib`). `--decoys-in-library` honors the `Decoy` column as the `.tsv` path does.
3. `-l` help text and `docs/` name the format. Refuse a `.speclib` with a message that gives the
   `diann --lib x.speclib --gen-spec-lib --out-lib x.parquet` conversion.
4. Tests: a small committed DIA-NN `.parquet`; a test that it loads identically to the `.tsv` that
   `diann_library_swap.py convert` makes from it (the model is
   `SubsetPipelineTest.TestLibraryLoadsIdenticallyFromTsvAndBlib`).
5. Then simplify the benchmark: `diann_library_swap.py` keeps only the accession mapping (or none, if
   the swap can pass DIA-NN's accessions through), and `Run-DiannEntrapment.ps1 -Steps swap-*` passes
   the `.parquet` straight to `-l`.

## Out of scope

- Reading `.speclib`.
- The reverse direction (DIA-NN searching Osprey's Carafe library). DIA-NN reads the `.tsv`, so that
  needs a `.blib` -> DIA-NN `.tsv` export; a separate item if wanted.
