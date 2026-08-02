# Entrapment audit tooling

Answers one question: **is this run's entrapment population a valid model of false targets, or
is it contaminated by near-copies of the targets it is supposed to be independent of?**

Motivated by [#4515](https://github.com/ProteoWizard/pwiz/issues/4515). The
`target+decoy+entrapment` carafe libraries generate entrapment by **shuffling** each target and
decoys by **reversing** it, with no similarity gate on either. Shuffling preserves positional
identity far more readily than reversal, so a shuffle can land close enough to its target -
especially in low-complexity sequences - that it is detected wherever the target is.

## Why pass 1, and not the output `.blib`

Every FDR statistic in the mean(best-N) programme is a **pass-1** quantity: the k-slices, the
FDP views, the reproducibility frontier. The output `.blib` is the **pass-2** reported set, so
characterising the entrapment population from it mixes scopes.

Two specific traps in using the blib for this:

* Its `OspreyExperimentScores.NRunsDetected` is **post-reconciliation** - 99.7% of accepted
  precursors read N-of-N, because Stage 6 fills in a peak for every run. It is not the
  independent-detection run count and must not be substituted for it.
* Pass-2 rescoring sharpens the target/entrapment separation. The same near-copy pairs measure
  16x apart on the blib and only **3.9x** apart at pass 1 - so the blib understates how close
  the shadow sits to the real peptide.

`pass1_entrap.py` therefore reads the pass-1 truth directly:

* `<stem>.1st-pass.fdr_scores.bin` - 32-byte header + N x 60-byte records, carrying
  `experiment_precursor_qvalue` at offset [28..36]. Written pre-compaction and post first-pass
  protein FDR, one record per input entry.
* `<stem>.scores.parquet` - the same rows **in the same order** (the sidecar loader matches by
  position, not by joining on `entry_id`), supplying sequence / protein_ids and the peak
  (`apex_rt`). Alignment is asserted per file rather than assumed.

## Usage

```powershell
python pass1_entrap.py  <run_dir> <out.json> [parquet_dir]   # harvest accepted set (q <= 1%)
python pass1_compare.py <out.json> "<label>"                 # pair to targets, score, compare peaks

python library_overlap_audit.py <osprey_library_db_pairing.tsv> --label NAME [--sample N]
```

`library_overlap_audit.py` needs **no run**: it audits the library's own pairing manifest, so it
can confirm a rebuilt library cleared the contamination before a multi-hour search is spent on it.
The library-wide rejectable fraction is the honest denominator; the accepted-set fraction the two
pass-1 tools measure is ~6.5x higher, because near-copies are enriched among hits, and only a real
run can show that.

`parquet_dir` is separate because a `-LinkFrom` arm keeps its parquets in the linked directory
while writing sidecars to its own.

Entrapment is identified by the `_p_target` suffix its shadow proteins carry. Pairing back to
the source target goes through `peptide_pair_index` in `osprey_library_db_pairing.tsv`.

## What it reports

* fraction of the **accepted** entrapment that a published similarity filter would reject
  (OpenSWATH `shuffle_sequence_identity_threshold` 0.50; EncyclopeDIA `getSmartDecoy` fragment
  overlap 0.40)
* whether each entrapment peptide's **source target is also accepted**, split by near-copy vs
  dissimilar - the shadowing test
* the q-value ratio between an entrapment peptide and its source target
* **whether they are scoring the same peak** - apex-RT agreement within 0.05 min, over every
  file where both were scored

## Reference result (TDP-43 Plasma EV, 163 files, 2026-08-01)

| | near-copy | dissimilar |
|---|---|---|
| source target also accepted | **42.9%** | 2.1% |
| same peak (apex within 0.05 min) | **41.1%** | 2.3% |
| median abs RT difference | **0.074 min** | 0.794 min |

Odds ratio 34.9x, Fisher two-sided p = 1.8e-08. 26.9% of paired accepted entrapment is
filter-rejectable.

**Interpretation caution.** Fragment overlap alone does not imply the same peak:
`LMDLIGDR` / `IMDLLGDR` differ only by isobaric L/I swaps, so their b/y ladders are identical
(overlap 1.000), yet they co-elute only 31% of the time - the peak picker also uses predicted
RT, which differs because the sequences differ. Gate on identity **and** overlap.

**Severity note.** Peak assignment is non-exclusive: in the 41.1% same-peak cases both the
entrapment and its target hold a peak at that apex and both are accepted. The contamination
inflates the measured false count but does **not** suppress real identifications.

## Reference result (Astral library, library-level, 2026-08-01)

`library_overlap_audit.py` over each Astral pairing manifest. The ungated build reproduces the
delivered library's sequences exactly, so its row IS the delivered library.

| | median overlap | 99th | max | rejectable | median identity |
|---|---|---|---|---|---|
| shuffle, ungated (= delivered) | 0.1000 | 0.5714 | 1.0000 | **4.22%** | 0.1923 |
| shuffle, gated | 0.1000 | 0.3750 | 0.4000 | **0%** | 0.1875 |
| Arabidopsis r=1.0, gated | **0.0238** | 0.2000 | 0.4000 | **0%** | **0.0588** |
| decoys, ungated | 0.0833 | 0.4545 | 1.0000 | 1.74% | - |
| decoys, gated | 0.0833 | 0.3333 | 0.4000 | **0%** | - |

Rejectable rates and median overlap are over ALL ~1.39M quartets; the percentile and identity
columns are from a 150,000-quartet sample. Sampling matters: the same 150k sample reads 4.05%
rejectable against 4.22% for the full manifest, so quote the full number when it is the headline.

Two things worth separating. The gate removes the **tail** - it is a filter, so by construction
nothing survives above 0.4. Foreign entrapment shifts the **whole distribution**: median overlap
0.0208 vs 0.1000 is 4.8x lower, and median positional identity 3.2x lower, before any gating. A
shuffled entrapment is an anagram of its target and shares its fragment masses no matter how it is
permuted; a real foreign peptide simply does not.
