# Osprey: pass-2 A/B at 82 files, and the library-production question it exposed

## Branch Information
- **Branch**: none in pwiz (measurement work on `master` at `e7b5a917ba`); Carafe work on
  `fix/nocut-met-clip` in `C:\proj\Carafe-mm`
- **Created**: 2026-08-04
- **Status**: In Progress
- **Module**: `osprey`
- **PRs**: [maccoss/Carafe#10](https://github.com/maccoss/Carafe/pull/10) (OPEN, stacked on #9)
- **Follows**: [TODO-20260802_osprey_default_flip.md](../completed/TODO-20260802_osprey_default_flip.md)
  (#4484, merged as `e7b5a917ba`)

## Why this exists

#4484 shipped `protein-compact` as the pass-2 default with its reservations recorded rather than
resolved. This is the measurement that tests it at the scale that matters: 82 SEA-AD files, where
Brendan predicted the `>=2 peptides per protein` gate would break down for decoys and entrapment
alike as random chance makes two hits per protein common.

## THE HEADLINE RESULT: protein-compact is anti-conservative at 82 files; transfer is not

Two arms, **byte-identical Stage 1-4** (arm B adopted arm A's parquets via `-LinkFrom`), same
library, same pick. So the arms differ only in pass-2 method + experiment aggregation.

| | A: protein-compact + pick | B: transfer + mean-best-6 |
|---|---|---|
| pass-1 true FDP @ 1% reported q | 0.777% | 0.775% |
| **pass-2 true FDP @ 1% reported q** | **1.156%** | **0.770%** |
| library spectra written | 37,078 | **38,913** |
| protein groups @ 1% FDR | 5,022 | **5,155** |
| wall time | 8h29m | **3h49m** |
| peak working set | **63.1 GB** | 45.9 GB |

**Pass 1 is calibrated identically in both**, so the arms start level. protein-compact then
degrades it to 1.156%; transfer preserves it at 0.770%. Arm B wins on every axis at once -
calibration, spectra, protein groups, wall time and memory.

Run dirs: `D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\seaad-82files-libdecoy-r1.0-*`.

### `frontier` and the fdpView curves are PASS-1 metrics (Brendan, 2026-08-04)

Easy to misread, and I did at first. Pass-2 mode cannot move them. So the A-vs-B `frontier`
comparison isolates **mean-best-6**, not the pass-2 method:

| | pass-1 frontier @ matched true FDP |
|---|---|
| arm A (max) | 32,923 @ 0.787% |
| arm B (mean-best-6) | 38,773 @ 0.783% |
| **mean-best-6 effect** | **+17.8%** |

That reproduces the historical **+16.4%** N-sweep peak at N=6 on a different library, a different
pass-2 mode and a different pick. **The lever is intact.** Also note the 470-row fdpView arrays
are the downsampled plot curve - their indices are NOT ID counts; do not quote them as such.

## WHY THE >=2 GATE BREAKS DOWN, MEASURED

From arm A's `crossRun` diagnostics - the union of detections as runs accumulate:

| runs | run-level q union / FDP | experiment-wide q union / FDP |
|---|---|---|
| 1 | 24,932 / 0.83% | 22,586 / 0.11% |
| 10 | 45,358 / 3.70% | 31,252 / 0.36% |
| 40 | 57,777 / 8.97% | 32,780 / 0.61% |
| **82** | **61,285 / 12.95%** | **32,923 / 0.79%** |

**The union of run-level 1% detections across 82 runs is 12.95% false** - Brendan's 2008
observation reproduced with an entrapment oracle. Experiment-wide q stays at 0.79%, **16x better
at N=82**, and essentially flat. Singletons: 16.79% false at run level vs 7.00% experiment-wide.

`DetectedPeptides` IS that run-level union (`ProteinFdr.cs:939-947`, gated on
`RunPeptideQvalue <= config.RunFdr`, unioned over files, no experiment-wide control anywhere in
the qualification). So at 82 runs the >=2 gate draws its two peptides from a pool that is 12.95%
false. Rough sizing (assumes uniform spread over proteins, so order-of-magnitude only):
~7,900 false detections over ~20,000 proteins gives on the order of **1,000-1,200 proteins
qualifying on false evidence**, against 6,501 qualifying in total.

Observed stratum: `protein-compact: 6501 proteins with >=2 detected peptides -> stratum of
721964 base_ids (from 59108 detected peptides)` - **52% of the library admitted**, a ~12x
expansion over the detected set.

## THE DESIGN TENSION (Brendan, 2026-08-04) - keep this

> "The more closely we bound them, the more like transfer_compete they become, dropping more
> randomly poor scoring targets and their paired decoys and disadvantaging our null models."

The qualification threshold is **one dial between two failure modes**, and the permissiveness that
rescues protein-compact from transfer-compete's asymmetry is the same permissiveness that lets the
null qualify by chance at scale.

* **Loose** (run-level union): decoys and entrapment qualify by luck at a rate that grows with N.
* **Tight** (experiment-wide): converges on "targets that passed", i.e. transfer-compete's
  asymmetric selection whose retained decoys are systematically the losers.

Related, from the same discussion: **a target can be admitted because of its own score** (it may
be one of the >=2 detections that qualified its protein); **a decoy never can**, since
`DetectedPeptides` is gated on `!entry.IsDecoy`. Diluted by the expansion in proportion to
(peptides per protein - 2) - at 2 peptides per protein it degenerates to transfer-compete - but
the self-admitted targets are that protein's best-scoring peptides, so the bias sits at the top of
the ranked list where a running `(nDecoy+1)/nTarget` count is most sensitive.

**And the entrapment oracle is partly blind here.** Entrapment peptides enter the stratum only
when two chance detections land on the same entrapment protein - rare, which is the gate working -
so entrapment representation in the re-scoped population is thin. Worse, the error mode
protein-compact preferentially admits (a marginal peptide of a genuinely PRESENT protein, wrong
peak/charge/interference) is one entrapment cannot see at all, because that peptide IS in the
sample. Do not treat a flat FDP as proof the expansion was earned.

## ARM C - designed, NOT implemented

Replace the stratum's qualification with **experiment-wide** peptide q. Expected pool change:
61,285 detections at 12.95% false -> 32,923 at 0.79% false.

**Where the change goes (verified in source, 2026-08-04).** At 82 files the production route is
the PROJECTION/streaming path, where `perFileEntries` is NOT in scope - so the qualification set
must come from the sidecar stream, which already carries what is needed
(`Pass2FdrSidecar.StashOffStratumPass1ExperimentQ` reads `rec.ExperimentPeptideQvalue` off the
same sidecar):

```
FirstJoinTask.cs:2086  StreamFirstPassFileScores(... (modseq, isDecoy, record) =>
    accumulator.Add(modseq, isDecoy, record.Score, record.RunPeptideQvalue))
```

1. `OspreyEnvironment`: gate `OSPREY_PROTEIN_COMPACT_QUALIFY = run | experiment`, default `run`
   so arms A and B stay bit-comparable.
2. `FirstPassProteinFdrAccumulator`: accumulate a SECOND detected set on
   `ExperimentPeptideQvalue <= config.ExperimentFdr`.
3. `FirstPassProteinFdrResult`: carry it.
4. `BuildProteinCompactStratum` (`FirstJoinTask.cs:1713`): consume it when gated.
   **Do NOT change `DetectedPeptides` in place** - `BuildProteinParsimony` reads it for Stage 7,
   so retargeting it would move protein FDR as a confounding side effect.
5. Mirror in the resident `RunFirstPassProteinFdr` so both paths agree; unit-test that the two
   sets differ only as the q source implies.

**Gate before running C**: `regression.ps1 -Dataset Stellar` with the flag OFF must be
byte-identical - that is what keeps arms A and B valid against a newer binary. Then arm C runs
Stage 5+ via `-LinkFrom` arm A (the runner version-pins automatically).

**Prediction**: if the 1.156% is qualification-driven, C pulls it toward pass-1's 0.777% and the
Stage 7 peak falls from 63.1 GB as the stratum shrinks. If FDP does NOT move, the over-optimism is
not qualification-driven and the self-admission asymmetry becomes the prime suspect.

## MEMORY: the real peak is Stage 7, not the Stage 6 plateau

| stage | arm A peak working set |
|---|---|
| Stage 1-4 | 33.7 GB |
| Stage 5 | 47.2 GB |
| Stage 6 (the #4526 plateau) | 50.7 GB |
| **Stage 7 SecondPassFDR** | **63.1 GB of 64 GB** |

Trigger: `protein-compact: mapped recomputed q onto 86,581,597 reported survivors in 1381s`, with
reporting gaps blowing out to 69-94 s (GC thrash, not work). **[#4526](https://github.com/ProteoWizard/pwiz/issues/4526)
does not cover this** - it is protein-compact's pass-2 map-back, O(survivors), and survivors are
inflated by the 721,964-base_id stratum. Same root as everything else here.

The Stage 6 plateau is real but bounded: managed floor rose to 27.0 GB and RELEASED on exit from
Stage 6 (28.1 GB at the Stage 7 transition), so the hold is scoped to Stage 6 exactly as #4526
describes. Note the 163-file run's floor was ~28 GB and 82 files gives 27.0 GB - the retained
buffer is NOT scaling linearly with file count, so it is dominated by library residency and the
retained-entry set rather than by N. Worth knowing for #4526's design.

## THE LIBRARY QUESTION - our absolute numbers are not comparable to the historical study

Our arms land ~13-14% below the historical study on both aggregation arms
(max 32,923 vs 38,300 = -14.0%; mb6 38,773 vs 44,581 = -13.0%). Nearly constant, so it is a level
shift, not the aggregation and not mean-best-N's implementation.

**Cause is the library, and the comparison was never valid.** The historical study ran on
**Mike's delivered** `lib\regression\target+decoy+entrapment\` (2026-06-30, no provenance); ours
ran on our own rebuild. `ai/docs/osprey-library-generation-guide.md` already measures that
boundary:

| target precursors compared | identical fragment m/z list |
|---|---|
| Mike's delivered vs our rebuild | **56.3%** |
| our two rebuilds, shared basis | 100.0% |

44% of targets carry a different fragment set - "genuinely different search inputs, not the same
library with jitter". The guide's own rule: a controlled comparison needs a shared prediction
BASIS.

**Transfer learning was done correctly** (Brendan asked specifically): our libraries fine-tuned on
`Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_55.mzML`, one of the 3 Astral regression files, RT
R^2 0.9971 / MS2 median COS 0.9778. Not the base AlphaPepDeep model.

**The live suspect is the Astral prediction parameters.** On Stellar, where Carafe params were
transcribed from Mike's log, our rebuild was **~7% MORE** sensitive than his (26,861 vs 25,107
stage-6 peptides). On Astral we are ~13% LESS. And every Astral run prints:

> no Astral Carafe log exists, so `-itol 20 ppm` for stages 2 and 4-5 is an instrument-appropriate
> assumption, NOT a transcribed value.

So our Astral libraries are built on a guessed fragment tolerance and our Stellar ones are not,
and Astral is exactly where we underperform. `PICK_LDA` is NOT the explanation at this magnitude -
prior measurement puts it near 1% with unstable sign across seven cells.

**Cheapest tests**, in increasing cost: search the same 82 files against Mike's delivered library
with the current binary (isolates the library completely, library already on disk); or two 20-file
arms on our library at different `-itol` (~1 h each).

## CARAFE: root-caused and fixed - [maccoss/Carafe#10](https://github.com/maccoss/Carafe/pull/10)

**Root cause of the 19,559 unpaired entrapment peptides Osprey has been working around.**
`Run-CarafeOspreyWorkflow.ps1:388` passes `-clip_n_m` to the PREDICTION pass, which runs
`-enzyme NoCut` over an already-digested peptide FASTA. `DBGear.digest_protein`'s clip block is
gated by a "peptide is a prefix of the protein" filter that is trivially true under NoCut (the
entry IS the "protein"), so every M-initial entry gained a clipped copy no digest produced. The
entrapment shuffle preserves only the C-terminus, so M-initial status is uncorrelated within a
quartet and the clip fired one-sided:

| case | pairs | consequence |
|---|---|---|
| entrapment M-initial, target not | 24,093 (**19,560** in the 400-900 m/z window) | orphan entrapment, no target twin - crashes FDRBench's paired estimator |
| target M-initial, entrapment not | **45,537** | targets with NO entrapment coverage - entrapment ratio zero, biases FDP down; nothing warned about this half |
| both | 4,492 | matched clip pair, harmless |

**The manifest-derived prediction of 19,560 matched Osprey's runtime count of 19,559 - delta 1.**
Different language, different code path, different artifact.

Fix: skip the clip under NoCut in `DBGear.digest_protein`, same guard in
`RankLabelGenerator.digest_protein`. Plus `EntrapmentPairingValidator` - quartet integrity
(throws inside `writeManifest`) and library-vs-manifest pairing.

**Three bugs in my own validator, all found by running it rather than by unit tests:**
1. Clipped entrapment pairs with the CLIP of its manifest target (exists only when that target
   starts with M), not with the manifest target - the loose version accepted exactly the
   sequences that shipped broken.
2. At `r < 1.0` most targets are deliberately unentrapped; flagging them fired on 90% of the
   library at r=0.1.
3. Asserting no sequence appears under two pair indices - not an invariant the generator offers;
   fired 526 times on the first real build and **would have blocked every library at every
   ratio**. Narrowed to "a generated sequence equal to a REAL target", which is what the
   collision-drop pass actually enforces.

Verified on real 1.4M-quartet builds at **r=0.5 (measured 0.4999)** and **r=0.1 (measured
0.1000)**, zero `p_target` rows without a target in their pair. Carafe suite 126 tests, 0 failures.
Build toolchain: IntelliJ's bundled JBR 21.0.9 + Maven 3.9.9 (JDK 17 cannot build this pom).

## Tasks

- [x] Arm A: protein-compact + pick, 82 files, from scratch
- [x] Arm B: transfer + mean-best-6, `-LinkFrom` arm A
- [x] Carafe NoCut clip fix + pairing validator, tested at r=1.0/0.5/0.1
- [x] `-ExperimentAgg` added to `Run-SeaAd.ps1` (it splats `@PSBoundParameters`, so a lever the
      script does not declare cannot reach the module - setting the env var alone yields a run
      silently aggregated as `max` in a directory named `mean-best-6`)
- [x] Auto-snapshot the Osprey exe in `Invoke-OspreyDatasetRun` so a long run stops locking the
      build tree
- [ ] **Settle the library question** - search 82 files against Mike's delivered library, or the
      20-file `-itol` probe
- [ ] **Arm C** - experiment-wide qualification (design above), gated, Stellar byte-identity
      first
- [ ] Merge Carafe #10 (retarget to `main` BEFORE deleting #9's branch, or #10 auto-closes
      unreopenably)
- [ ] Regenerate the Astral library with the fixed Carafe once `-itol` is settled

## Progress Log

### 2026-08-04 - Arms A and B complete; Carafe root-caused; library confound found

Everything above. Three process notes worth carrying:

**My verification kept being unable to reach the failure.** The `-WhatIf` that "verified" the exe
snapshot did not pass `-Tag`, so it could not surface that `$tag` and `-Tag` are the same variable
in PowerShell (case-insensitive) - which corrupted a run directory name. The four-peptide fixtures
that "verified" the pairing validator could not surface a collision defect that only exists at
1.4M sequences. Both were caught by reading the output of the first real run.

**A drift figure that SHRINKS as a run extends is a bounded band, not accumulation.** perfviz
fits one slope from first sample to last; across a run with two regimes (library load, then steady
state) it reports RISING for a floor that later returns. Read the per-phase trend, not the summary
line - I called Stage 1-4 an O(files) leak on that basis and was wrong.

**Never compare absolute IDs across libraries.** The guide says it, the 56.3% fragment-set overlap
measures it, and I still put 38,773 next to 44,581 before checking which library each used.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260804_osprey_pass2_ab.md` before starting work.
