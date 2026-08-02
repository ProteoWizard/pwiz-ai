# Osprey spectral library generation (Carafe)

How to build an Osprey spectral library from a protein FASTA on any machine,
including the natural (foreign-species) entrapment variant used for FDR
calibration work.

Driver: [`ai/scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1`](../scripts/Osprey/Carafe/Run-CarafeOspreyWorkflow.ps1).
Start with `-Preflight`; it resolves every tool and prints what it found without
doing any work.

> **Status.** The **digest** (stage 1) is validated on both datasets - an ungated
> rebuild reproduces Mike's delivered peptide FASTA byte for byte on Stellar
> (2026-07-04) and on Astral (2026-08-01, SHA256 over 349 MB, all 1,390,979
> manifest quartets identical). The **prediction** stages are validated on Stellar
> only; Astral's Carafe `-itol` is an instrument-appropriate assumption because no
> Astral Carafe log exists. See [Open questions](#open-questions).

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

### Traps that cost time on a fresh machine

- **A JDK 17 on `JAVA_HOME` fails deep inside stage 1**, with an
  `UnsupportedClassVersionError`, because Carafe's pom targets release 21. The
  driver probes each candidate's version and takes the first 21+, so
  `-Preflight` will tell you which it picked - but a raw `java -jar carafe.jar`
  will not. A JetBrains-bundled JBR 21+ works.
- **Maven may only exist inside IntelliJ**:
  `<IDEA>\plugins\maven\lib\maven3\bin\mvn.cmd`. There is no separate install on
  the development machine this recipe came from.
- **`mvn -o test` fails even with a warm `.m2`** if `surefire-testng` was never
  fetched; `mvn -o package` is fine. Run tests online once.
- **`Compress-Archive` cannot zip these libraries** - it dies with "Stream was
  too long" on a >4 GB member and they are ~12 GB. Use 7-Zip.

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

### Controlled comparisons need a shared prediction basis

This is the rule that matters when a library A/B is meant to isolate one
variable, and it is easy to get wrong because the sequences can be byte-identical
while the libraries are not comparable.

Targets are untouched by the similarity gate and by the entrapment source, so any
target-side difference between two libraries is the *prediction*, not the variable
under test. Two measurements, on the same 13-column libraries:

| target precursors compared | identical fragment m/z list |
|---|---|
| delivered (Mike's peptdeep model) vs our rebuild | **56.3%** |
| our two rebuilds, same training blib + seed | **100.0%** |

The first was measured on the other machine over ~3,000 shared target precursors:
44% of targets report a *different* fragment set, with a median relative intensity
difference of 2.3% (p90 8.4%, p99 19.5%). Carafe emits a top-N fragment set, so
once predicted intensities shift the ranking changes and different fragments get
written. The search scores against that list, so these are genuinely different
search inputs, not the same library with jitter.

The second was measured here over 3,129 shared target precursors sampled by
sequence hash: **every fragment m/z, every intensity and every RT identical, at
every percentile** - and the fine-tuned `ms2_model.pt` / `rt_model.pt` are
byte-identical by SHA256 across the two separate Carafe invocations.

**So the requirement is a shared prediction BASIS, not literally one invocation.**
Separate runs are fine when they share the training blib, the seed, the Carafe
parameters and the peptdeep model - fine-tuning is deterministic under those, and
that is verifiable in two cheap ways before trusting a comparison:

1. hash the fine-tuned `ms2_model.pt` / `rt_model.pt` in each output directory;
2. compare the target side directly, which is what
   `compare_target_predictions.py` does.

What is *not* comparable is anything built against a different peptdeep model
version - which is exactly what the delivered library is. Use it as a reference
arm, label it confounded, and put the baseline arm through your own pipeline.

---

## The 2026-08-01 Astral rebuild

Three libraries built from `uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta`,
forming a single-variable series. Stages 1a/2/3 are entrapment-free and were run
once and shared, which is what makes the series affordable and controlled.

```
ungated  ->  gated  ->  arabidopsis
   |           |             |
   |           |             +- removes the anagram relationship  (median overlap 0.100 -> 0.024)
   |           +- removes the near-copy tail                      (4.05% -> 0%)
   +- the pre-gate state of the world, in the same prediction basis
```

| | delivered (reference) | ungated (baseline) | gated | Arabidopsis r=1.0 |
|---|---|---|---|---|
| quartets | 1,390,979 | 1,390,979 | 1,391,732 | 1,391,734 |
| library size | 13.09 GB | 11.84 GB | 11.84 GB | 11.97 GB |
| rejectable entrapment | 4.22% | 4.22% | **0%** | **0%** |
| rejectable decoys | 1.74% | 1.74% | **0%** | **0%** |
| median entrapment overlap | 0.100 | 0.100 | 0.100 | **0.024** |
| shares our prediction basis | **no** | yes | yes | yes |

Every row audited over ALL quartets, not sampled - a 150k-quartet sample reads
4.05% / 1.70%, so quote the full number. The delivered and ungated columns are
identical by construction: their peptide sequences are the same set, proven byte
for byte. The gated variants keep MORE targets than the baseline, because the
retry rescues more old collision-drops than the gate costs.

Internal consistency check: the baseline holds **58,704** rejectable entrapment
peptides, and the gate changed **58,319** entrapment sequences. The difference is
peptides dropped outright rather than replaced, plus the small target-set
difference - the two independent counts agree.

**The delivered library is not the baseline.** Its peptide *sequences* are
identical to the ungated arm's (proven byte for byte), but it was predicted with
a different peptdeep model version, so only 56.3% of its target precursors report
the same fragment set as ours - see
[Controlled comparisons](#controlled-comparisons-need-a-shared-prediction-basis).
Treat it as a labelled reference arm and use **ungated** as the baseline. The
ungated arm exists precisely so the gate step is measured against something that
differs from it *only* by the gate.

Shared training run (`Ast-...-55.mzML`, one file): 3,167,149 initial-library
entries loaded, 77,076 precursors at 1% run FDR, 68,017 peptides at 1% experiment
FDR, 7,933 protein groups, 95,842 spectra written to the training blib. Fine-tune
from that blib: **RT R² 0.850 -> 0.9971**, **MS2 median COS 0.9653 -> 0.9778**.

The three variants were three separate Carafe invocations, and their fine-tuned
`ms2_model.pt` and `rt_model.pt` are **byte-identical by SHA256 across all
three** - fine-tuning is deterministic given the same blib and seed. So the
RT/MS2 model is held constant and the only difference between the libraries is
which peptides were predicted.

Wall clock on an RTX 4070: stage 1a ~1 min, stage 2 6.0 min, stage 3 7.7 min,
stage 4-5 15-16 min per variant. Well under two hours for all three - far cheaper
than the Stellar timings suggest, because Osprey's search is fast and stages
1a/2/3 are shared.

**One failure worth knowing about.** The second variant's prediction died with a
native Windows fault (`0xC0000409`, no Python traceback) while several prediction
workers were loading models onto the GPU, seconds after the first variant's
fine-tuning released it. The data was ruled out first - both peptide FASTAs have
an identical residue alphabet, identical 7-35 length range, and entry counts
within 8 of each other - and a clean retry succeeded in the same 15.1 min. Treat
it as a transient GPU resource fault; if it recurs, lower Carafe's prediction
parallelism rather than looking for a data cause.

---

## The similarity gate

Every generated decoy and entrapment sequence must pass a fragment-overlap check:
a candidate is rejected when more than **0.4** of its theoretical b/y ladder falls
within **0.02 Da** of its target's. This is a transcription of the gate Osprey
already applies in C# and Rust (pwiz #4480 / maccoss/osprey #58), with the same
constants; Carafe builds the libraries Osprey actually searches, so until
2026-08-01 the protection existed only on the path nobody uses.

**What it fixes.** `shufflePreservingCterm` was called once, with no retry, and
the only rejection was an exact string collision with a real target. An entrapment
peptide could therefore land close enough to its own target to be detected
wherever the target is - which makes it not a false peptide at all, while the FDP
estimator still counts it as one. Measured over the pass-1 accepted sets of two
datasets, ~27% of accepted entrapment was a rejectable near-copy, about half of
them shadowing a target that was itself accepted and co-eluting within 0.05 min.
That inflates measured FDP by roughly 25%.

**Not sequence identity.** Detection is driven by fragment evidence, not
positional string similarity. `EIVELEK`/`EEVEILK` has identity 0.571 but overlap
0.333 - shadows nothing. `LMDLIGDR`/`IMDLLGDR` has identity 0.750 but overlap
1.000 (isobaric L/I) - the overlap gate catches it, identity nearly misses it.
Adding an identity gate on top caught 9 extra cases across both datasets, all 9
with a source target that was *not* accepted: zero demonstrated shadowing.

**What it costs**, measured on Astral (1,392,350 digested targets):

| | count | of targets |
|---|---|---|
| entrapment sequences changed | 58,319 | 4.19% |
| decoy sequences changed | 24,257 | 1.74% |
| dropped, no acceptable entrapment | 155 | 0.011% |
| dropped, no acceptable decoy | 449 | 0.032% |

The 4.19% independently reproduces the 4.15% library-wide gate rate measured by
the separate Python audit tooling, which cross-validates the Java port.

The dropped set is **structured, and benignly so**: 60% of dropped peptides are
≥50% a single residue, against 0.7% of kept ones (median single-residue fraction
0.571 vs 0.200). They are poly-A, poly-G, poly-E, poly-Q and collagen-like repeats
- `GGGGGGGGDGGGR`, `QQQRQQQQQQQQK`, `PGSPGPPGSPGPR`, `RPPPPPPPPPPR`. No
permutation of 17 alanines is a valid entrapment peptide, so dropping them is the
correct answer rather than a loss.

**The retry more than pays for the gate.** Because the bounded retry also rescues
peptides the old one-shot shuffle dropped on an exact collision, the gated Astral
build keeps **1,391,732** targets against the delivered library's **1,390,979** -
a net *gain* of 753.

`-no_similarity_gate` reproduces the pre-gate behaviour. It is an audit switch,
not a tuning knob: it is what proves a rebuilt library differs from the delivered
one only by the gate, and a library built with it should not be searched.

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

Since 2026-08-01 this lives **inside Carafe** as `-entrapment_db <fasta>`
(`ForeignEntrapmentSource`), so stage 1b emits a final manifest and FASTA with no
post-processing step. `tools/make_natural_entrapment.py` is the earlier
post-processing prototype, kept because it can retrofit an existing library
without a Carafe rebuild; new work should use the Carafe option.

1. Digest the foreign proteome with identical enzyme/length params.
2. **Absence filter**: drop any foreign peptide that equals a real target (2,608
   of 1.45M on Arabidopsis vs the human Astral target set).
3. **Co-location assignment**: pair each target with one *unique* foreign peptide
   in the same isolation window. See below - the choice of algorithm matters more
   than it looks.
4. Every candidate passes the same fragment-overlap
   [similarity gate](#the-similarity-gate) as generated decoys.
5. `p_decoy` stays the reverse+cycle of the drawn `p_target`, preserving symmetry.
6. `-entrapment_ratio` selects a seeded subset when entrapment should be a thin
   overlay rather than half the library.

#### Optimize co-location count, not mass displacement

An entrapment peptide only samples the same difficulty as its target if it lands
in the same DIA isolation window, because that is the only window it competes in.
So the objective is to **maximize the number of pairs inside the window** - a
threshold - not to minimize total mass displacement. Those are different problems
and they want different algorithms. Measured on Astral, 1,392,350 targets against
1,454,810 Arabidopsis candidates (a 4.3% surplus):

| assignment | co-located | median \|Δm\| | 99th | max |
|---|---|---|---|---|
| nearest-available, sequence order | 94.64% | 0.0025 Da | 137 Da | 1278 Da |
| nearest-available, mass order | 80.95% | 0.042 Da | 82 Da | 2030 Da |
| quantile map (optimal transport) | 48.89% | 6.05 Da | 10.9 Da | 85 Da |
| **bin-based co-location** (shipped) | **99.86%** | 0.043 Da | 1.16 Da | 605 Da |

- Sweeping in **mass order** lets each target consume supply just above it, so a
  deficit accumulates and every later target is dragged further off.
- The **quantile map** is the optimal monotone transport and has by far the best
  worst case, but it spreads its error evenly so most pairs sit several Da off.
  Optimal for total displacement, wrong for a threshold.
- Binning the pool at 0.25 Da and serving from the nearest non-empty bin wins
  because inside the window every candidate is equally good, so no search is
  needed, while preferring nearer bins keeps the mass match tight anyway.

Fully deterministic: bins filled in mass-sorted order, consumed in a fixed order,
seeded ratio subset. Same inputs, same output, any machine.

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
| Arabidopsis proteome (UP000006548, 39,273 proteins) | `D:\test\entrapment\arabidopsis\UP000006548.fasta` |
| Stellar rebuild work dir | `D:\test\carafe-repro\stellar\` |
| Shuffle originals of the Stellar 1b outputs | `D:\test\carafe-repro\stellar\osprey_library_db_*.shuffle.bak` |
| FDRBench inputs + FDP results for every Stellar arm | `D:\test\carafe-repro\stellar\osprey_project\FDRBench\` |
| Astral rebuild work dir (both 2026-08-01 variants) | `D:\test\carafe-repro\astral\` |
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

1. **Astral PREDICTION parameters are assumed.** The digest is verified byte for
   byte, but Mike's `carafe_log.txt` covers Stellar only, so `-itol`/`-itolu` for
   stages 2 and 4-5 on Astral is instrument-appropriate (20 ppm) rather than
   transcribed. The driver warns when `-Dataset Astral` is used. The clean fix is
   to ask Mike for an Astral Carafe log; failing that, an Astral library's
   predicted spectra are ours, not a reproduction of his. (The Astral FASTA is
   `uniprot_human_jan2025_yeastENO1_contam_ADpeps.fasta`, 13.7 MB vs Stellar's
   3.1 MB, which is why the Astral library is 13 GB.)
2. **Stage-2 parity with Mike** would tighten if we matched his peptdeep
   pretrained model. Currently ~99.85% peptide overlap, ~13% fewer fragment rows.
3. **RT/property matching.** Natural entrapment is matched on mass only (length
   follows closely). Matching the target RT distribution too would make the
   peptides equally "findable"; mass co-location is the first-order control
   because it decides which isolation window scores the entry at all.
4. **The identity gate stays unbuilt, on evidence rather than on principle.** The
   identity-only groups were n=6 and n=3, and "source target not accepted" is not
   proof of harmlessness - the target could be present but sub-threshold. Audit
   tooling reports overlap, so revisit if a dataset ever shows an identity-only
   case that shadows an accepted target and co-elutes.
5. **Upstream.** The gate, the bounded retry, `-entrapment_db` and
   `-entrapment_ratio` live on the `feature/decoy-similarity-gate` branch of
   `maccoss/Carafe`. Shuffle remains the default, so the two are switchable for
   head-to-head. Two earlier Carafe issues from this line of work are still open
   (`ai/.tmp/carafe-issue-{1-nterm-met,2-pairing-manifest}.md`).
6. **Skyline's shuffle is a separate instance of the same defect.**
   `Model/DecoyGenerator.cs` has no gate, and its shuffle is `n` random
   transpositions - a random-transposition walk that at only `n` swaps is far from
   uniform and biased toward permutations close to the identity, which is exactly
   the near-copy failure mode. Fisher-Yates plus the gate; tracked in
   [`TODO-20260801_decoy_similarity_gate.md`](../todos/active/TODO-20260801_decoy_similarity_gate.md).

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
