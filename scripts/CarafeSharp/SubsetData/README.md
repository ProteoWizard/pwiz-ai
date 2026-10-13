# CarafeSharp committed test data subsets

Deterministic builders for the zips in `pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData`. Each
reads the extracted full packages (`--data-root`, normally `<Downloads>/Perftests`) and writes a
byte-identical zip for the same inputs. Each builder's docstring has the details.

## Stage1Inputs.zip (`build_stage1_inputs.py`)

Used by `EntrapmentFastaParityTest.TestSubsetFastaBuildsMatchCarafe` (default category, every
commit, about 18 s), which reruns the stage-1 entrapment FASTA builds of `carafesharp-testfiles-v1`.

- Holds a package-shaped `carafesharp-testfiles-v1/` folder with the **inputs only**:
  `stellar/hela-filtered.fasta` and `stage1/fixtures/mouse-subset1500.fasta` (unchanged), the three
  Stellar `*.carafe.sig` files, and the `command.txt` of the 10 `stage1/builds` that read only those
  two FASTAs. About 1.9 MB.
- The outputs (23-62 MB each) are not kept. Each folder that had outputs has an `expected.sha256`
  (`<sha256>  <file name>`) taken from the package's `MANIFEST.sha256`; the test compares hashes when
  the reference file is absent. A mismatch reports both hashes; the full package gives the first
  differing line.
- Download-only: `foreign-mouse` and `foreign-mouse-r025`, which read the 14.4 MB
  `stage1/uniprot_mouse_dec2024_yeastENO1.fasta` (8 MB compressed). The two `foreign-mouse-sub` builds
  cover the same foreign-database path. `TestFullFastaBuildsMatchCarafe` still runs all 12 builds on
  the full package.

```
python build_stage1_inputs.py --data-root D:/Users/<you>/Downloads/Perftests \
    --out-zip <pwiz>/pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/Stage1Inputs.zip
```

Rebuild it when the stage-1 builds or their reference outputs in the package change.

## TrainingParitySubset.zip (`build_training_parity_subset.py`)

Used by `CarafeFineTuneParityTest.TestFineTuneMatchesCarafeSubset` and
`OspreyMaskingParityTest.TestMaskingAgreesWithCarafeSubset` (default category, every commit, about
5 s together), which run the checks of `TestFineTuneMatchesCarafe` and `TestMaskingAgreesWithCarafe`.
About 4.0 MB.

- `carafesharp-testfiles-v1/`: only `stellar/carafe-osprey-entrapment/osprey_new_library` (the
  no-entrapment folder's training tables are byte-identical). `psm_pdv.txt`, `meta.json`,
  `parameter.txt`, `model_evaluation_metrics.json`, `rt_test.tsv`, `test_true_intensity.tsv` verbatim.
  The training tables keep **every row**, because Carafe's train/test split samples the whole table
  and the test checks that split, but `fragment_intensity_df.tsv` keeps intensities only for the 904
  held-out spectra (the split is ported into the builder, which checks the kept values are
  `test_true_intensity.tsv`), `fragment_intensity_valid.tsv` keeps masking counts for those and the
  spectra of sampled sequences, and `rt_train_data.tsv` keeps `rt_norm` only for the rows of the 999
  held-out forms of `rt_test.tsv`. An empty `osprey_library_db_peptides.fasta` stands in for the file
  `parameter.txt -db` names.
- `carafesharp-export-v1/`: the training export rows whose 64-bit FNV-1a hash of `sequence`, shifted
  right 32 bits, is 0 modulo 20 (1,132 of 22,761), without `xic_rts`/`xic_intensities`; footer kept,
  `osprey.training_export.rows` and parity counts updated, plus `carafesharp.subset.sequence_modulus`,
  which the masking test reads to compare only Carafe's spectra of the same sequences (85.3% slot
  agreement on the subset, 85.0% at full scale).
- Never fine-tunes: with intensities zeroed outside the held-out spectra a training run would be
  meaningless, so `CARAFESHARP_FINETUNE_FULL=1` stays download-only (ignored under the subset).

```
python build_training_parity_subset.py --data-root D:/Users/<you>/Downloads/Perftests \
    --out-zip <pwiz>/pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/TrainingParitySubset.zip
```

Rebuild it when Carafe's reference fine-tuning folder or the training export package changes.

## LibraryParitySubset.zip (`build_library_parity_subset.py`)

Used by `LibraryParityTest.TestLibraryParitySubset` (all four library checks: peptide forms,
fragment m/z, assembly, end-to-end prediction; about 11 s) and
`CarafeParityTest.TestPretrainedPredictionsMatchCarafeSubset` (the pretrained half of
`TestPredictionsMatchCarafe`; about 6 s), default category, every commit. About 3.4 MB.

- A package-shaped `carafesharp-testfiles-v1/` with five Carafe runs cut down by filtering their
  files, no Carafe rerun: the Stellar `osprey_initial_library` (1/500 of its record groups),
  `osprey_new_library` (1/1000, without its models), and the library references `m3/ref/nocut-every50`
  (1/25), `m3/ref/trypsin-proteins` (1/8) and `carafe_main_varmod` (1/30), the last three with their
  `.blib`. Each run keeps 980-1,023 precursors.
- FASTA records are grouped so no peptide, `ProteinID` or decoy pair crosses groups: records yielding
  the same peptide (NoCut: the sequence and its M-clipped copy; an enzyme: every record holding it as a
  substring), records a `ProteinID` names together, and the `peptide_pair_index` groups of the pairing
  TSV beside the FASTA. Every n-th group is kept; then the parquet frames, the library TSV and the
  `.blib` keep exactly the rows the kept records yield (`frag_start_idx`/`frag_stop_idx` renumbered,
  `.blib` rows deleted from every table keyed to `RefSpectra`, then `VACUUM`). The builder fails if a
  TSV `ProteinID` names both kept and dropped records.
- `osprey_train_db_pairing.tsv`, the `-pairing_manifest` of nocut-every50, keeps every group holding a
  kept sequence and every group sharing a sequence with those, so the decoy-pair gate decides as with
  the full manifest. `parameter.txt` files are unchanged, so paths are relocated as in the full package.
- Download-only: the fine-tuned prediction (`TestPredictionsMatchCarafe`'s second half and
  `TestPredictedLibraryMatchesCarafe` on `osprey_new_library`), which needs 16 MB of model weights.
  The subset predicts its Stellar FASTA whole instead of every 50th record.

```
python build_library_parity_subset.py --data-root D:/Users/<you>/Downloads/Perftests \
    --out-zip <pwiz>/pwiz_tools/CarafeSharp/CarafeSharp.Test/TestData/LibraryParitySubset.zip
```

Rebuild it when any of those reference runs in `carafesharp-testfiles-v1` changes.
