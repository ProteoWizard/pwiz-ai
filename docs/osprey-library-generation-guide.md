# Osprey spectral library generation (Carafe)

How to build an Osprey spectral library from a protein FASTA on any machine,
including the natural (foreign-species) entrapment variant used for FDR
calibration work.

Driver: [`ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1`](../scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1).
Start with `-Preflight`; it resolves every tool and prints what it found without
doing any work.

> **Status.** The Stellar recipe is **validated** - we reproduced it end to end
> on 2026-07-04/06 with Stage 1 byte-identical to Mike's delivered files. The
> Astral preset is **not** validated; see [Open questions](#open-questions).

---

## Why this exists

Mike MacCoss delivered the Carafe libraries our Osprey regression datasets use
(`target+decoy` and `target+decoy+entrapment`, 2026-06-30). Generating them
ourselves removes that dependency and, more importantly, lets us *change* them -
the natural-entrapment work below is only possible if we can rebuild.

Two things are easy to confuse:

- **Generation** (this guide): build a new library from a FASTA with Carafe.
  Needs a GPU, a peptdeep environment, and about an hour for Stellar.
- **Derivation** ([`New-SeaAdLibrary.ps1`](../scripts/Osprey/SEA-AD/New-SeaAdLibrary.ps1)):
  subset or strip an *existing* library (entrapment ratio, decoy removal). No
  Carafe, no GPU. Prefer this when it suffices.

---

## Prerequisites

| Component | Requirement | Notes |
|---|---|---|
| JDK | **21 or newer** | Carafe's pom targets release 21. Mike runs 25. A JetBrains-bundled JBR works. |
| Maven | any recent | No `mvnw` wrapper in the repo. Needed only to build the jar. |
| Carafe | `maccoss/Carafe` -> `C:\proj\Carafe-mm` | Mike's fork is a clean superset of Noble-Lab's: it only *adds* the Osprey integration (`EntrapmentFastaGear`, `OspreyBlibReader`, `AIGear`). Build with `mvn package`; `lib/utilities-*.jar` is a bundled patched dependency the build references. |
| peptdeep | AlphaPeptDeep venv + `pretrained_models.zip` | Carafe bootstraps `~/.carafe/.venv` on first run. This is the largest external dependency. |
| GPU | CUDA, ~4 GB used | An RTX 4070 (12 GB) is sufficient. |
| Osprey | built `Osprey.exe` | `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1` |
| Python | 3.x on PATH | Only for stage 1c (natural entrapment). |

Point the driver at non-default locations with the environment variables listed
in [`Carafe/README.md`](../scripts/Osprey/Carafe/README.md#machine-configuration).

---

## The pipeline

```
protein FASTA
   |  1a  digest (Trypsin, no-P) -> target+decoy, entrapment-FREE
   |  1b  digest (Trypsin, no-P) -> target+p_target+decoy+p_decoy quartets
   |  1c  (optional) swap shuffle p_target for matched foreign peptides
   v
osprey_train_db_peptides.fasta   + osprey_train_db_pairing.tsv
osprey_library_db_peptides.fasta + osprey_library_db_pairing.tsv
   |  2   Carafe NoCut predict from the TRAIN db (generic peptdeep, NCE 27)
   v
osprey_initial_library/carafe_spectral_library.tsv   (GENERIC)
   |  3   Osprey search ONE training run with the initial library
   v
osprey_train/osprey.blib
   |  4-5 Carafe fine-tune RT+MS2 on that blib (seed 2024, NCE 30),
   |      then predict the FINAL library from the ENTRAPMENT db
   v
osprey_new_library/carafe_spectral_library.tsv       (FINE-TUNED)
   |  6   Osprey search all runs with the final library (+ --fdrbench)
   v
osprey_project/osprey.blib + FDRBench/FDRBench-Input.tsv
```

Two structural facts worth internalizing:

1. **Fine-tuning trains on entrapment-free data.** The RT and MS2 models never
   see entrapment sequences; the entrapment database is used only to *predict*
   the final library (stage 5 `-db osprey_library_db_peptides.fasta`).
2. **The two delivered libraries differ in two dimensions, not one.**
   `target+decoy` is the **generic, un-fine-tuned** stage-2 library;
   `target+decoy+entrapment` is the **fine-tuned** stage-5 library. Comparing
   them conflates entrapment with fine-tuning.

---

## Key parameters

| Parameter | Value | Where it matters |
|---|---|---|
| Enzyme (digest) | Trypsin, no-P rule (`-enzyme 2`) | stage 1 |
| Enzyme (predict) | `NoCut` (peptides pre-digested) | stages 2, 4-5 |
| Missed cleavages | 1 | stage 1 |
| Peptide length | 7-35 | stages 1, 2, 4-5 |
| Precursor m/z | 400-900 | matches the 400-900 DIA window |
| Precursor charge | 2-3 | |
| Fixed mod | Carbamidomethyl (C) | |
| Variable mods | none | |
| Fragment m/z (library) | 200-1960, top 20, min 2 | |
| Instrument (peptdeep) | Eclipse | Stellar has no peptdeep mapping, so Carafe defaults to Eclipse |
| NCE | 27 generic / 30 fine-tuned | 30 is picked up from `HCD@30` in the data |
| Fine-tune seed | 2024 | reproducibility |
| Entrapment / decoy seeds | 42 / 24 | peptdeep defaults; make stage 1 deterministic |
| Osprey resolution | Stellar `unit` @ 0.4 Th; Astral `hram` @ 10 ppm | 10 ppm is Osprey's own default (`CoreTypesTest.cs:394`) |
| Osprey FDR | run / experiment / protein all 1%, percolator, precursor | |
| Decoy prefix | `decoy_` | |

The driver script holds these as the `$libGen`, `$ospreyCommon`, and
`$digestCommon` argument sets; the verbatim CLI Mike logged is preserved in the
script's stage comments.

---

## Validation (2026-07-04/06, Stellar)

Our build vs Mike's delivered files, same Workflow-5 config, our Osprey
v26.1.1.185 vs his v26.1.1.0.

**Stage 1: byte-identical.** All four outputs match by SHA256 - both pairing
manifests and both peptide FASTAs. 218,921 target+decoy pairs; 218,871
entrapment quartets. The digest is fully deterministic (seeds 42/24), so this
reproduces exactly on any machine.

**Stage 2: functional match, not byte-identical.** 494,264 distinct precursors
(ours) vs 494,991 (Mike), ~99.85% the same peptide set; 8.15M vs 9.22M fragment
rows. Cause: **the peptdeep pretrained-model version differs** - ours was freshly
downloaded and is likely newer. Same Carafe 2.2.0, NCE, instrument, and params
otherwise. Different predicted intensities means different fragments survive the
top-20 filter.

**Stages 3-6: faithful functional match, ~7% more sensitive.**

| Metric | Ours | Mike |
|---|---|---|
| Stage 3 run-level IDs | 21,548 | 21,541 |
| Stage 3 protein groups | 3,948 | 3,948 |
| Final library entries | 988,544 | 988,740 |
| Stage 6 peptides | 26,861 | 25,107 |
| Stage 6 proteins | 4,821 | 4,484 |
| FDRBench input rows | 41,021 | 40,902 |

The uplift tracks a newer Osprey (185 commits), a newer peptdeep model, and a
larger training blib (25,788 vs 21,340 spectra feeding fine-tuning) - not errors.

**What this means for reproducibility.** Stage 1 reproduces exactly, anywhere.
Stages 2 and beyond are **not byte-reproducible across machines** because the
peptdeep pretrained model and the GPU are part of the input. Two machines
following this guide get functionally equivalent, not identical, libraries. If
you need identical, share the built library rather than rebuilding it, and pin
the peptdeep model.

---

## Natural (foreign-species) entrapment

### Why

Entrapment peptides exist to *validate* the FDR estimate, so they only need to be
truly absent from the sample. Carafe's default entrapment is a C-term-preserving
**anagram of its own target**, which means it shares the target's exact amino-acid
composition and therefore many of its fragment masses. Anagram entrapment gets
over-identified, and an over-identified entrapment set over-estimates FDP.

Real peptides from a phylogenetically distant species (Arabidopsis) have no such
relationship. This is also standard practice (Biognosys, Bernhardt).

Decoys are a different object and are left alone: they drive the FDR *estimate*
through target-decoy competition, so they must stay mass-matched.

### The algorithm

[`tools/make_natural_entrapment.py`](../scripts/Osprey/Carafe/tools/make_natural_entrapment.py)
emits the same quartet/manifest schema as `EntrapmentFastaGear`, so stages 2-6
and FDRBench consume it unchanged. Only the `p_target` source changes.

1. Digest the foreign proteome with identical enzyme/length params.
2. **Absence filter**: drop any foreign peptide that equals a human target.
3. **Matched 1:1 draw**: pair each target with one *unique* foreign peptide of
   matched neutral mass (`strict` also matches length). This is the DIA-correct
   control - a library entry is only scored in the isolation window containing
   its precursor m/z, so entrapment must span the same m/z distribution or it
   samples a different difficulty regime.
4. Uncovered targets fall back to a C-term-preserving shuffle, counted and
   reported.
5. `p_decoy` stays the reverse+cycle of the drawn `p_target`, preserving symmetry.

Fully deterministic: seeded fallback shuffle (`seed ^ crc32(seq)`), sorted
candidate lists, seeded ratio selection. Same inputs, same output, any machine.

### Results (Stellar, precursor level, 1% q)

| Entrapment | n_t | n_p | combined FDP | paired FDP | peptides | proteins |
|---|---|---|---|---|---|---|
| Shuffle (target anagram) | 30,772 | 252 | 1.62% | 1.51% | 26,861 | 4,821 |
| Strict Arabidopsis (isobaric, 99.8% cov) | 28,091 | 163 | 1.15% | 1.08% | 25,479 | 4,635 |
| Relaxed Arabidopsis (100% natural) | 27,910 | 141 | 1.01% | 0.92% | 25,315 | 4,550 |

Monotonic: the more natural the entrapment, the lower the measured FDP. With
r=1, `combined FDP = 2*n_p/(n_t+n_p)`, so the driver is n_p (252 -> 163 -> 141):
**real foreign peptides are falsely identified about 1.8x less often than
target-anagram shuffles.**

### Ratio sweep (capture-recapture, relaxed Arabidopsis)

`r` is the entrapment:target ratio on unique peptides.
`combined FDP = N_E(1 + 1/r)/(N_T + N_E)`.

| r | N_T | N_E | combined FDP | naive FDP |
|---|---|---|---|---|
| 1.00 | 27,931 | 148 | 1.05% | 0.53% |
| 0.50 | 29,536 | 113 | 1.14% | 0.77% |
| 0.25 | 30,141 | 66 | 1.09% | 0.88% |
| 0.10 | 30,654 | 32 | 1.15% | 1.04% |
| shuffle r=1 | 30,797 | 253 | 1.63% | 0.82% |

1. **Combined FDP is ratio-invariant at ~1.1% across a 10x pool size** -
   capture-recapture works; factoring `r` into the math gives a pool-size
   independent estimate.
2. **N_T recovers from 27,931 to 30,654 as r shrinks**, converging on the
   unperturbed ~30,800. So r=1 (half the library being entrapment) genuinely
   perturbs the target search; **a small-r overlay measures without distorting**.
   Prefer r <= 0.25 when the goal is measurement.
3. **Marker realism matters more than ratio**: at the same r=1, natural is 1.05%
   vs shuffle 1.63%. That 0.58 pt is pure anagram over-identification.
4. **Best estimate: Osprey's true FDP at 1% reported q is ~1.1%** - mildly
   anti-conservative (~1.1x), not the ~1.6x that shuffle entrapment claims.

Caveat: low power at small r (N_E=32 at r=0.1). The invariance is the robust
signal, not the third significant figure.

### Caveats on the whole approach

- Entrapment lives *inside* the searched library, so changing it perturbs the
  target search. Measurement and analysis are entangled; small r mitigates this.
- No external ground truth. Natural sequences are a better prior for the
  false-positive population, but a controlled two-organism sample would be needed
  to settle which FDP is true.
- Arabidopsis peptides are frequently *mass* collisions with human peptides
  (93.9% fall within 2 ppm of a human target m/z - see `tools/occupancy_test.py`).
  That is expected and fine: it makes them MS1-representative of a real false
  target. Only *sequence* identity has to be filtered.

---

## Artifacts on disk

As of 2026-08-01, on BRENDANX-UW25:

| Artifact | Location |
|---|---|
| Arabidopsis proteome (UP000006548, 39k proteins) | `D:\test\entrapment\arabidopsis\UP000006548.fasta` |
| Stellar rebuild work dir | `D:\test\carafe-repro\stellar\` |
| Shuffle originals of the 1b outputs | `D:\test\carafe-repro\stellar\osprey_library_db_*.shuffle.bak` |
| FDRBench inputs + FDP results for every arm above | `D:\test\carafe-repro\stellar\osprey_project\FDRBench\` |
| Mike's delivered Stellar / Astral libraries | `D:\test\{Stellar,Astral}Test-TargetDecoyLibraries\` |

**The natural-entrapment libraries themselves no longer exist.** The generator
rewrites `osprey_library_db_pairing.tsv` / `osprey_library_db_peptides.fasta` in
place, and those were overwritten by a later shuffle rebuild (2026-07-06); the
predicted library in `osprey_new_library/` was overwritten at the same time. Only
the FDRBench inputs and the results above survive. They are regenerable exactly -
restore from `*.shuffle.bak` and re-run stage 1c, which the driver now does
automatically - but the Carafe prediction step is not byte-reproducible (above).

Sharing a built library across machines: the delivered libraries are 2.5 GB
(Stellar) and 13 GB (Astral) raw; zipped copies already exist beside them
(`target+decoy+entrapment.zip`, 256 MB / 1.38 GB).

---

## Open questions

1. **The Astral preset is unvalidated.** Mike's `carafe_log.txt` covers Stellar
   only - it contains no Astral run, so `-itol`/`-itolu` for Astral is an
   instrument-appropriate assumption (20 ppm), not a transcribed value. The
   driver warns loudly when `-Dataset Astral` is used. The clean fix is to ask
   Mike for an Astral Carafe log; failing that, treat an Astral build as a new
   library rather than a reproduction. The Astral FASTA is much larger
   (`uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta`, 13.7 MB vs Stellar's
   3.1 MB), which is why the Astral library is 13 GB.
2. **No Arabidopsis library has ever been built for Astral.** The entire natural
   entrapment result set above is Stellar. Whether the shuffle-vs-natural gap
   holds at high mass accuracy is untested and is the main open scientific
   question. See
   [`TODO-osprey_foreign_decoys_honest_ms1_power.md`](../todos/backlog/brendanx67/TODO-osprey_foreign_decoys_honest_ms1_power.md).
3. **Stage-2 parity with Mike** would tighten if we matched his peptdeep
   pretrained model. Currently ~99.85% peptide overlap, ~13% fewer fragment rows.
4. **RT/property matching.** Natural entrapment is matched on mass and length
   only. Matching the target RT distribution too would make the peptides equally
   "findable".
5. **Upstream.** Steps 1c and the ratio parameter are ours, applied after
   Carafe. If they prove durable they belong in `EntrapmentFastaGear` as an
   `-entrapment_source` mode so shuffle stays the default and the two are
   switchable for head-to-head. Two Carafe issues were already filed from this
   work (`ai/.tmp/carafe-issue-{1-nterm-met,2-pairing-manifest}.md`).

---

## Related

- [`ai/scripts/Osprey/Carafe/README.md`](../scripts/Osprey/Carafe/README.md) - driver usage
- [`ai/scripts/Osprey/Run-FdrBench.ps1`](../scripts/Osprey/Run-FdrBench.ps1) - the FDP oracle
- [`ai/docs/osprey-development-guide.md`](osprey-development-guide.md) - FDRBench
  entrapment validation doctrine (the oracle wins over parity)
- [`ai/scripts/Osprey/SEA-AD/`](../scripts/Osprey/SEA-AD/) - deriving library variants
  without Carafe
- Wen et al., "Assessment of FDR control ... using entrapment," Nature Methods
  22:1454 (2025); FDRBench: github.com/Noble-Lab/FDRBench
