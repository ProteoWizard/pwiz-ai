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

## ARM C - IMPLEMENTED 2026-08-05 (gate pending), not yet run

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

### As built (2026-08-05, on master `b554ce6f0d`)

The 5 insertion points above all survived #4530's `FirstJoinTask` rewrite (line numbers moved:
stratum builder 1713 -> 1727, accumulator 2086 -> 2098). Implemented as designed, plus three
things the design did not call out:

* **`OSPREY_PROTEIN_COMPACT_QUALIFY` is `run` | `experiment`**, unset = `run`. An unrecognized
  value ABORTS at startup (mirrors `OSPREY_PASS2_QVALUE`) rather than silently running the
  default - this flag selects the population a reported FDP is measured against, so a typo
  would publish the wrong arm's numbers under the arm name the operator chose.
* **A validity-key suffix**, EMPTY on the default arm so no existing output directory is
  invalidated, added to `FirstJoinTask` + `PerFileRescoreTask` + `MergeNodeTask`. Without it an
  in-place A/B is self-confirming: the second arm finds the first's reconciled parquets valid,
  skips the work, and reports a match it never computed. Same failure #4530 guarded against.
* **The stratum log line now names the arm** (`qualified by run|experiment q-value`). The two
  arms otherwise differ only in one count, with nothing in the log to tell them apart.

`FirstPassProteinFdrResult` carries BOTH sets and `ProteinCompactQualifyingPeptides()` is the
ONE place the flag is read, so the resident and streaming paths cannot pick differently.
`DetectedPeptides` is untouched, so Stage 7 parsimony does not move. The second set is
accumulated unconditionally (bounded by the set it mirrors), which keeps the flag a pure
CONSUMPTION choice - the off arm has no way to diverge.

New test `Osprey.Test/ProteinCompactQualifyTest.cs` (one `[TestMethod]`, four private
validators): the q source separates the sets, decoys enter neither, the streaming accumulator
matches the resident path row-for-row, the accessor honours the arm, and the suffix is empty on
default / non-empty on experiment. Pre-commit gate green: 575 tests, zero inspection warnings.

**Scheduling constraint**: arm C CANNOT run beside the library run below. Both are 30-thread
multi-hour jobs and arm A's protein-compact peaked at 63.1 GB of 64 GB, with the Stage 7 peak
NOT covered by #4530. Run them in sequence.

**GATE GREEN (2026-08-05)**: `regression.ps1 -Dataset Stellar` with the flag OFF, on branch
`Skyline/work/20260805_osprey_protein_compact_qualify` (commit `6c1e3b8656`):

```
Stellar mode1 (vs golden): PASS      Stellar mode2 (resume cache hits): PASS
Stellar mode3 (HPC chain==straight): PASS   Stellar mode2 (resume==straight): PASS
Stellar mode4 (warm re-run all cached): PASS
```

That is the condition the design named - it is what keeps arms A and B comparable against this
newer binary. Log: `ai/.tmp/regression-stellar-armc.log`. NOT yet pushed, no PR.

**CHAINED 2026-08-05 03:12** - `ai/.tmp/chain-armc.ps1` (PID 6116) polls for `Osprey.exe` to
exit, logs what the predecessor actually did (a missing `DONE` line is reported, so a failed
library run does not read as a completed one), then launches arm C. The exe is **PINNED** to
`D:\test\osprey-runs\_bin\armc-qualifyexp\Osprey.exe` rather than auto-snapshotted at launch:
the snapshot would otherwise be taken hours from now and any rebuild before then would silently
change what arm C runs. Verified that binary carries the gate
(`OSPREY_PROTEIN_COMPACT_QUALIFY` in `Osprey.Core.dll` + `Osprey.dll`, `qualified by` in
`Osprey.Tasks.dll`) - the strings are UTF-16 in .NET metadata, so a plain `grep`/`strings -el`
finds NOTHING and reads as a missing feature; check with a control string.

**Two errors `-WhatIf` caught before the 8-hour run**, both from reconstructing arm A's config
instead of reading its `run.log`:
* `-LibraryDir D:\test\AstralTest-TargetDecoyLibraries` + `-Ratio 1.0` resolves to
  `target+decoy+entrapment`, which is MIKE'S library - arm A used `-gated-no-il`. With
  `-LinkFrom` hard-linking arm A's Stage 1-4 parquets, that pairs one library's parquets with
  another library for Stage 5+, silently.
* Omitting `-FdrBenchPass` yields `both`, and `--fdrbench-pass 1` forces the RESIDENT
  first-pass pool that OOMs at 82 files. Arm A ran `fdrbench=2`.

**To run arm C** manually (what the chain does) once the library run frees the machine:

```
Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -PickLda \
  -QualifyBy experiment -FdrBenchPass 2 \
  -DataDir 'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\mzml' \
  -LibraryDir 'D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-gated-no-il' \
  -LinkFrom 'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\seaad-82files-libdecoy-r1.0-protein-compact-picklda' \
  -Exe 'D:\test\osprey-runs\_bin\armc-qualifyexp\Osprey.exe'
```

Verified field-by-field against arm A's `run.log` START line - every parameter is arm A's
except `-QualifyBy`. Do NOT export `OSPREY_PROTEIN_COMPACT_QUALIFY` by hand: `-QualifyBy` is a
first-class runner parameter now, and the module CLEARS the variable before re-exporting it
from the argument, so a hand-exported value is wiped. Out dir gets `-qualifyexp` automatically.

`-LinkFrom` arm A is valid: the qualification arm is deliberately absent from
`PerFileScoring`'s validity key (Stage 1-4 is scoring, upstream of any FDR), so only Stage 5+
re-runs. Confirm the banner prints `qualify : EXPERIMENT-wide q` - that line exists precisely
so this cannot be run unknowingly on the default arm.

### Arm C first result (2026-08-05 07:45): the arm engaged, stratum halved

`...runs\seaad-82files-libdecoy-r1.0-protein-compact-picklda-qualifyexp\run.log`:

```
protein-compact: 3769 proteins with >=2 detected peptides -> stratum of 335948 base_ids
(from 30167 detected peptides, qualified by experiment q-value).
```

| | arm A (run q) | arm C (experiment q) | change |
|---|---|---|---|
| detected peptides | 59,108 | 30,167 | -49.0% |
| proteins with >=2 | 6,501 | 3,769 | -42.0% |
| stratum base_ids | 721,964 | 335,948 | -53.5% |
| share of the ~1.39 M base_ids | ~52% | ~24% | |

30,167 is close to the ~32,923 the `crossRun` diagnostic predicted for the experiment-wide pool
at 82 runs. The EXPANSION factor over the detected set barely moved (11.9x -> 11.1x), so the
stratum shrank because the qualifying POOL shrank, not because the expansion rule changed -
the single-variable move the arm was built to make.

Arm C shares arm A's Stage 1-4 byte-for-byte: `LinkFrom: hard-linked 328 stage1-4 file(s),
0 missing`, `PerFileScoring:skipping (outputs valid)`. Note the banner prints `Osprey
v26.1.1.215` while the binary is the pinned 26.1.1.217 - that is `-LinkFrom` setting
`OSPREY_VERSION_OVERRIDE` from the source run so the linked artifacts validate. It changes the
stamp, not the code.

### ARM C COMPLETE 2026-08-05 11:38 - the over-optimism WAS qualification-driven

Exit 0, 285 min. Same library, same files, arm A's Stage 1-4 parquets via `-LinkFrom`, same
pick, same aggregation. ONE changed variable.

Both arms scored through FDRBench identically (`fdrbench-patched.jar`, `-level precursor
-score score:1 -entrapment_label _p_target`), metric = `combined_fdp` at the last row with
q <= 0.01:

| | arm A (run q) | arm C (experiment q) |
|---|---|---|
| **true FDP @ 1% reported q** | **1.139%** | **0.426%** |
| discoveries @ 1% reported q | 37,056 | 38,477 |
| discoveries @ true 1% FDP | 35,484 | **42,552** (+19.9%) |
| library spectra written | 37,078 | 38,500 |
| protein groups @ 1% FDR | 5,022 | 4,545 |
| reconciled survivors into Stage 7 | 86,581,597 | 43,461,681 |

**Arm A reproduces at 1.139% vs the 1.156% recorded on 2026-08-04** - within 0.02pp, which is
what anchors the comparison. Not an exact reproduction: this used the patched jar and the
earlier session's jar choice is not recorded.

The prediction was that C would pull the FDP toward pass-1's 0.777%. It went PAST it to 0.426%,
and it does not trade discoveries for calibration - MORE reported at 1% nominal (38,477 vs
37,056) at less than half the true FDP, and ~20% more at a genuine 1% true FDP.

Memory, per `[TASK]` window:

| stage | arm A floor / peak | arm C floor / peak | duration A -> C |
|---|---|---|---|
| PerFileScoring | 24.4 / 33.7 GB | (linked) | 254.5 min / - |
| FirstPassFDR (join) | 26.8 / 48.2 GB | 20.7 / 46.5 GB | 69.1 -> 72.8 min |
| PerFileRescoring (split) | 37.3 / 52.9 GB | **20.0 / 44.3 GB** | 158.5 -> 188.7 min |
| SecondPassFDR (join) | 38.3 / **63.1 GB** | 41.5 / **53.7 GB** | 27.6 -> 23.7 min |

Stage 7 peak -9.4 GB, attributable to the stratum since #4530 does not touch Stage 7.

**Three things the simple story does NOT explain** - do not paper over these:
* The map-back cost 1381s -> 1277s (-7.5%) for HALF the survivors, so it is not
  O(survivors)-dominated the way its memory is. Relevant to any #4526-style follow-up.
* Arm C's Stage 7 FLOOR is higher (41.5 vs 38.3 GB) while its peak is lower.
* Arm C's Stage 6 ran LONGER (188.7 vs 158.5 min) despite half the stratum.

**Arm C is conservative, not calibrated.** 0.426% true at a 1% nominal threshold overshoots in
the safe direction, and the 42,552-at-true-1% figure says real discoveries are being left on
the table. That is the opening for the threshold sweep below.

### NEXT: sweep the experiment-wide qualification threshold (Brendan, 2026-08-05)

The two knobs scale differently, which is the whole point:
* per-run q union: 0.83% false at 1 run -> **12.95% at 82**. Unbounded in N.
* experiment-wide q: 0.79% and **flat** in N.

So exp-q at 2% or 5% could be MORE permissive than run-q@1% while remaining better controlled,
because raising a flat threshold is bounded whereas the union's false fraction grows with files.
Mike has noted DIA-NN uses a 5% first-pass cut-off, possibly for the same reasoning that put
per-run q at 1% here - but the scaling argument says the experiment-wide axis is the one that
can afford permissiveness.

Needs a threshold decoupled from `config.ExperimentFdr` (which also governs the REPORTED set and
must not move): a new `OSPREY_PROTEIN_COMPACT_QUALIFY_FDR`, defaulting to `ExperimentFdr`.

### THE ARM TO RUN NEXT (decided from the sweep)

**protein-compact + PickLda + mean-best-6 + `-QualifyBy experiment`**, at the default 1%
threshold. Versus arm C it changes exactly ONE thing (the aggregation), so it stays a clean
single-variable comparison, and it stacks the #4484 reproducibility lever on the qualification
fix - both are Stage 5 adaptations.

Preferred over the exp-q<=5% arm: it takes most of the permissiveness (35,446 vs 44,171
qualifying peptides) at ZERO entrapment-protein cost rather than 0.96%, and arm C's 0.426% FDP
leaves the budget for it.

```
Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -PickLda \
  -QualifyBy experiment -ExperimentAgg mean-best-6 -FdrBenchPass 2 \
  -DataDir 'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\mzml' \
  -LibraryDir 'D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-gated-no-il' \
  -LinkFrom 'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\seaad-82files-libdecoy-r1.0-protein-compact-picklda' \
  -Exe 'D:\test\osprey-runs\_bin\armc-qualifyexp\Osprey.exe'
```

~4h45m. Score it with the SAME FDRBench recipe used for arms A and C (below) or the numbers are
not comparable.

**CAVEAT that must not be lost**: `OSPREY_EXPERIMENT_AGG` governs the REPORTED experiment q as
well as the qualification q, so this arm changes the reported set too - it is not a pure
qualification change. Decoupling (qualify on mean-best-N, report on max) would need two
experiment-q computations. Probably not worth it, since mean-best-6 was already the better arm
in the original A/B, but do not report this as isolating qualification.

### Scoring recipe (use this, or numbers are not comparable)

```
java -Xmx8G -jar D:\test\fdrbench\fdrbench-1.1.1\fdrbench-patched.jar \
  -i <run>\fdrbench.tsv -level precursor -score 'score:1' \
  -pep D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-gated-no-il\osprey_library_db_pairing.tsv \
  -entrapment_label _p_target -o fdp.csv
```

Metric = `combined_fdp` on the LAST row with `q_value <= 0.01` (that is
`Get-FdrBenchCalibration` in `ai/scripts/Osprey/Run-FdrBench.ps1`). The jar is chosen by
`Sort-Object Name -Descending`, which picks `fdrbench-patched.jar` over `fdrbench-1.1.1.jar`.

### THE SWEEP IS DONE - OFFLINE, NO EXTRA RUNS (2026-08-05)

Brendan's point: Stage 5 already wrote everything needed. `ai/.tmp/qualify-sweep.py` rebuilds the
qualifying peptide set and the >=2-peptide protein set at any threshold from artifacts on disk -
the 82 `.1st-pass.fdr_scores.bin` sidecars (32-byte header, 60-byte records; run-peptide-q at
offset 20, experiment-peptide-q at 36) joined by entry_id to the parquets
(`modified_sequence`, `is_decoy`, `protein_ids`). Entrapment is read straight off the
`_p_target` accessions, so the 392 MB pairing manifest is not needed. ~7 min for 82 files.

**It validates exactly against both runs' own logs** - run-q<=1% reproduces arm A's
59,108 / 6,501 and exp-q<=1% reproduces arm C's 30,167 / 3,769. That is what makes the rest
trustworthy.

**max aggregation (arm A/C Stage 5):**

| arm | qual pep | entrap pep | %ent | >=2 prot | ent >=2 | %ent |
|---|---|---|---|---|---|---|
| run q<=1% | 59,108 | 3,853 | 6.52% | 6,501 | **528** | **8.12%** |
| exp q<=1% | 30,167 | 121 | 0.40% | 3,769 | **0** | 0.00% |
| exp q<=2% | 35,479 | 329 | 0.93% | 4,222 | 2 | 0.05% |
| exp q<=5% | 44,171 | 1,055 | 2.39% | 4,919 | 47 | 0.96% |
| exp q<=10% | 52,965 | 2,591 | 4.89% | 5,760 | 255 | 4.43% |

**mean-best-6 aggregation (arm B Stage 5), same thresholds:**

| arm | qual pep | entrap pep | %ent | >=2 prot | ent >=2 | %ent |
|---|---|---|---|---|---|---|
| run q<=1% | 59,108 | 3,853 | 6.52% | 6,501 | 528 | 8.12% |
| exp q<=1% | **35,446** | 141 | 0.40% | **4,249** | **0** | 0.00% |
| exp q<=2% | 40,870 | 381 | 0.93% | 4,680 | 7 | 0.15% |
| exp q<=5% | 48,663 | 1,161 | 2.39% | 5,280 | 53 | 1.00% |
| exp q<=10% | 57,144 | 2,687 | 4.70% | 6,103 | 255 | 4.18% |

**What it establishes.**

1. **The scaling asymmetry, measured.** 2 files -> 82: run-q<=1% goes 30,325 -> 59,108 (+95%,
   still climbing at file 82); exp-q<=1% goes 30,056 -> 30,167 (+0.4%, flat from ~file 40).
2. **The failure mode, quantified.** run-q<=1% qualifies **528 entrapment proteins on >=2
   peptides - 8.12% of its protein set.** Entrapment is known-absent, so every one is a false
   qualification feeding the stratum. That is the 1.139% FDP's mechanism, not an inference.
3. **mean-best-6 shifts the whole curve, it does not trade along it.** At exp-q<=1% it gives
   +17.5% peptides and +12.7% proteins over max, still with ZERO entrapment proteins. Sharpest
   form: **mb6@1% ~= max@2% in peptide count (35,446 vs 35,479) but 0 entrapment proteins
   instead of 2.**
4. **The identical entrapment PEPTIDE fractions across aggregations** (0.40 / 0.93 / 2.39% at
   1/2/5%) are not a bug - both q estimates are calibrated, so q<=T admits the same false
   FRACTION either way. mean-best-6's gain is better RANKING: more true peptides at the same
   estimated FDR. The protein-level win then follows, because the extra peptides land on
   proteins that already had one.
5. **exp-q<=10% is past the knee** - entrapment peptide 4.89% -> protein 4.43%, i.e. the >=2
   gate has stopped suppressing. 2-5% is the useful band on max; mb6 reaches the same
   permissiveness lower.

**Correction to an earlier reading in this file**: exp-q<=5% is NOT more permissive than
run-q<=1% (44,171 vs 59,108 peptides). Brendan's claim was only that it is more permissive than
exp-q<=1% while staying selective against non-repeating false positives, which is what the
numbers show.

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

## THE LIBRARY QUESTION - ANSWERED 2026-08-05: it IS the library

Mike's delivered library, same 82 files, same binary, arm B's config otherwise byte for byte.
Pass-1 frontier `bestPeak`, extracted from each run's own `out.model-diagnostics.html` by ONE
script so the method cannot differ between arms (it reproduces arms A and B's recorded numbers
exactly, which is what validates it):

| arm | library | agg | bestPeak | bestPeakFdp | perRunPeak | expPeak | peakK |
|---|---|---|---|---|---|---|---|
| A | gated-no-il | max | 32,923 | 0.787% | 40,725 | 39,939 | 5 |
| B | gated-no-il | mean-best-6 | 38,773 | 0.783% | 40,725 | 40,004 | 5 |
| **NEW** | **Mike delivered** | mean-best-6 | **43,754** | **0.745%** | **47,133** | **45,693** | **2** |

**Against the historical mean-best-6 figure of 44,581: our gap closes from -13.0% to -1.9%.**
The library accounts for ~11 of the 13 percentage points. With Mike's library the current binary
essentially reproduces the historical study, so the pipeline was never the problem and the
"~13-14% below" finding was a library artifact throughout - exactly as the level-shift shape
(-14.0% / -13.0%, near-constant across two aggregations) predicted.

**It is not buying IDs by inflating FDP**: 0.745% true FDP vs arm B's 0.783%, so the bigger
number is also the better-calibrated one.

**What this does NOT say.** The arms differ in build provenance AND the similarity gate AND the
I/L gate at once, so this identifies "the library", not which of the three. The `-ungated` and
`-gated` rebuilds are on disk for that decomposition. The residual -1.9% is unattributed
(binary drift since the study, PICK_LDA at ~1%, or leftover config). And `peakK` moved 5 -> 2,
i.e. the reproducibility frontier peaks at a different N on this library - worth a look before
reading too much into any single mean-best-N choice. The historical 44,581 is the previous
session's recorded figure, not one re-derived here.

**Consequence for the `-itol` probe**: still worth doing, but it is now a question about OUR
library-generation parameters, not about a pipeline deficit. The decision to regenerate the
Astral library (task 4, awaiting Mike) is the one it feeds.

### DECISION (Brendan, 2026-08-05): the A/B/C set stays on OUR gated-no-il rebuild

Absolute IDs ~13% below the historical study are ACCEPTED as the baseline - the pass-2 method
comparison is a comparison BETWEEN arms on one library, and the library level-shift cancels in
it. So the set needs nothing new launched: arms A and B are on disk and arm C is chained.

The three arms as they stand:

| arm | pass-2 mode | agg | qualification |
|---|---|---|---|
| A | protein-compact | max | run (default) |
| B | transfer | mean-best-6 | n/a |
| C | protein-compact | max | **experiment** |

A vs C isolates the qualification arm exactly - one changed variable, same library, same pick,
same aggregation, same Stage 1-4 parquets via `-LinkFrom`.

**Preserved for later, do not delete**: the Mike-delivered-library run's completed Stage 1-4
(82 parquets, 4h07m) under `...-mean-best-6-mikelib\`. If the triad is ever wanted on that
library, `-LinkFrom` that directory makes each extra arm Stage 5+ only (~4h) instead of ~8h.

## Original framing - our absolute numbers are not comparable to the historical study

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

### Two corrections to the above (2026-08-05), then the run

**1. Arms A and B did NOT search a plain rebuild.** Their `run.log` names
`D:\test\AstralTest-TargetDecoyLibraries\target+decoy+entrapment-gated-no-il\`, i.e. our rebuild
PLUS the similarity gate PLUS the I/L gate. So "ours vs Mike's delivered" moves **three** things
at once, not one, and the 56.3%-fragment-overlap figure measures only the first. The -13/-14% gap
cannot be attributed to build provenance until the gates are separated - `-ungated` and `-gated`
rebuilds are both on disk next to it, so that decomposition is a later arm, not a rebuild.

**2. `-itol` is a CARAFE parameter, not an Osprey search flag.** `Run-CarafeOspreyWorkflow.ps1`
passes it as `-itol/-itolu` to library generation (`CarafeItol='20' ppm`, `Validated=$false` for
Astral); "stages 2 and 4-5" in that warning are CARAFE stages. So the "two 20-file arms at
different `-itol`" costs a library rebuild per arm, not just two searches. The good news is that
is cheaper than it sounds - the generation guide measures Astral stage 4-5 at **15-16 min per
variant on an RTX 4070** with stages 1a/2/3 shared - but it is GPU work, and it answers the
DOWNSTREAM question (why our library differs), which only matters once the library is confirmed
as the cause.

**Launched 2026-08-05 00:46** - the decisive arm, Mike's delivered library, arm B's config
otherwise byte for byte (`transfer` + `mean-best-6` + `PickLda`, 82 files, 30 threads,
`--fdrbench-pass 2`, model-diagnostics on):

```
Run-SeaAd.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode transfer -PickLda \
  -ExperimentAgg mean-best-6 -FdrBenchPass 2 \
  -DataDir 'D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\mzml' \
  -LibraryDir 'D:\test\Pilot-MTG-Tissue-May2026\lib\regression' -Tag '-mikelib'
```

Out dir `...\runs\seaad-82files-libdecoy-r1.0-transfer-picklda-mean-best-6-mikelib`; exe
snapshot `D:\test\osprey-runs\_bin\26.1.1.217-20260805-0045`. Chose that library path over the
identical copy under `AstralTest-TargetDecoyLibraries\target+decoy+entrapment\` because only this
one has the prebuilt 2.4 GB `.libcache` (13 s load vs parsing 13 GB of TSV). Mike's library
carries 6,324,700 entries against the gated-no-il library's 6,275,151.

**The comparator is arm B's pass-1 frontier, 38,773 @ 0.783% true FDP, against the historical
44,581.** Frontier is a PASS-1 metric, so the transfer/mean-best-6 config is legitimate here and
costs far less wall time and memory than protein-compact.

**#4530 does not confound this.** It changed no golden data file and its cache-validity suffix is
empty on the streamed default, so master is byte-identical to arms A/B's binary against the
committed golden - checked before launching, since a moved binary would have made the
cross-library comparison meaningless.

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

## Library-fragment release (#4532 / PR #4534) - MEASURED 2026-08-05

Separate branch `Skyline/work/20260805_osprey_library_fragment_release`, PUSHED, PR #4534 open.
Releases `LibraryEntry.Fragments` at the Stage 5 -> 6 boundary for everything outside
survivors + gap-fill. Default ON (`IsNotZero` treats unset as on); `OSPREY_RELEASE_LIBRARY_FRAGMENTS=0`
is the A/B arm.

A/B on 4 SEA-AD files against the full 12.7 GB gated-no-il library, same pinned binary, sequential.
Released 5,459,501 of 6,275,151 entries (87.0%), 409,235 base_ids retained.

| stage | ON | OFF | delta peak |
|---|---|---|---|
| PerFileScoring (pre-release) | 13.9 / 30.5 GB | 15.2 / 30.9 GB | -0.4 (noise) |
| FirstPassFDR | 27.7 / 35.7 GB | 27.3 / 40.3 GB | -4.6 GB |
| PerFileRescoring | 14.5 / 34.0 GB | 20.5 / 41.8 GB | -7.8 GB |
| SecondPassFDR | 15.9 / **17.7** GB | 22.2 / **28.5** GB | **-10.8 GB** |

Stage 7 peak -38%. Slightly faster, not slower. Stage 1-4 unchanged, as it must be.

**FEW FILES IS THE MAXIMUM-SAVING CASE, not a scaled-down one** - the library is fixed while the
retained set grows with file count. At 82 files expect ~70-75% released rather than 87%, so a
smaller (still large) saving. Do not quote the 4-file numbers as production.

`regression.ps1 -Dataset All` PASSED with the release ACTIVE - and the committed golden predates
this change, so mode1 IS the release-on vs release-off correctness proof. Verified it actually
engages in the golden-compared leg (`Released library fragments for 152830 of 485628 entries`)
after an earlier revision gated it on `ctx.Diagnostics`, which would have made that gate vacuous.

### Code review outcome (2026-08-06) - 4 real defects, all WIRING

`/code-review max` on the libfrag branch returned 15 findings. Fixed in `c601d63cd6`:

* **The Rehydrate path never released.** That is the RESUME path - what an operator runs after
  the very OOM this change targets - so the one run that most needs a lean library kept the
  whole thing resident. Worse, the doc comment justified it with a claim that was FALSE:
  `RescoreHydration` does surface the surviving set (`GlobalFirstPassBaseIds`).
* **StopAfterStage5 stripped gap-fill AND fabricated a saving.** `PlanStage6` returns early
  before assigning the gap-fill plan while `_firstPassBaseIds` IS set, so the retained set was
  survivors-only; and that path already loads with `OmitFragments`, so `ReleaseSpectrum` (which
  detects by reference identity, not "has a spectrum") swapped one shared singleton for another
  and printed millions released having freed ZERO bytes, directly above a [MEM] probe.
* **Six UTF-8 BOMs** broke the repo BOM gate and turned two 3-line diffs into whole-file
  rewrites. Cause: `io.open(...,'w',encoding='utf-8-sig')` WRITES a BOM. Read utf-8-sig, write
  utf-8. The arm C branch was checked and is clean (Edit tool throughout).

**The lesson worth carrying**: all four defects were WIRING, and the only test covered the pure
helper's set arithmetic. Deleting the production call site still leaves the suite green. An
integration test is the gap that let them through.

### The other 11 findings - ALL ADDRESSED 2026-08-06 (`a5cb0183a2`)

Posted on issue #4532 as comment 5202755992. The three that mattered:

* **The HPC merge node realized ZERO saving.** `MergeNodeTask` now performs its own release,
  retaining every base_id in the final reported pool. It had to be its own: `FirstJoinTask` -
  where the Stage 5 -> 6 release lives - is excluded from a `--task SecondPassFDR` pipeline
  entirely, and that leg loads fragment-laden (`OmitFragments` is gated on `StopAfterStage5`).
  The retained set is a superset of what is read, because `BlibOutputWriter.PrecompressSpectra`
  reads fragments only for `bestByPrecursor.Values`, derived from that pool by filtering, and
  nothing else after Stage 6 reads a spectrum: pass-2 Percolator reloads FEATURES from the
  reconciled parquet (`Pass2FdrSidecar` never touches the library) and parsimony reads identity.
  Placed AFTER `ctx.Get<RescoredEntries>()`, so the merge-mode compaction it materializes is
  already done.
* **The validity-key hole is closed at its root.** The suffix moved to
  `LibraryFragmentRelease.ValidityKeySuffix` and is keyed on whether the release RAN
  (`RunsOnThisLeg`), not on the flag - the same predicate the call sites gate on, so key and
  code cannot disagree. It is EMPTY on a leg where a release was impossible
  (`--task FirstPassFDR`, or the resident pool `--fdrbench-pass 1` forces) as well as where it
  ran: there the two arms are literally the same run, and a term would force hours of Stage 5
  re-scoring on an HPC resume to record a difference that cannot exist. **Under default
  settings every leg's key is byte-identical to master's** - nothing is invalidated.
* **`FragmentMath._top6MzCache` is cleared** by the release (`ClearTop6MzCache`). Pure memo, so
  neutral in both directions - and dropping it also stops a released entry's stale cached top-6
  from satisfying the prefilter that should have tripped the tripwire.

The rest: guards that could not fire removed (the silent `fullLibrary == null -> return 0`
degraded quietly in a fail-loud design); the misleading `~7.1 GB` replaced with the measured
28.5 -> 17.7 GB A/B plus the ~3.2 GB fragment-share caveat, since only fragments are freed;
`IsSpectrumReleased`'s doc now says what it answers ("was it RELEASED", not "does it have a
spectrum" - `Array.Empty` reports false); the `-DumpProteinFdr` citation corrected to
`OSPREY_DUMP_STAGE7_PROTEIN_FDR`; `_firstPassBaseIds` documented as deliberately separate from
`_survivorLoader` (the loader is null on the Rehydrate leg, which is where the release matters
most); and the tripwire's inability to name the offending entry recorded as the deliberate cost
of one shared singleton.

**Gates**: 576 tests, zero inspection warnings, and `regression.ps1 -Dataset All` PASSED all 26
checks across all four datasets - every `mode3 (HPC chain==straight)` included, which is the leg
the merge-node release runs on. Log: `ai/.tmp/regression-all-libfrag-review.log`. TeamCity 4123106
(SUCCESS) covered only `8317479fc4`; **4123277 is the one on the real tip `a5cb0183a2`**.

**The test gap is NARROWED, not closed.** New coverage pins the leg truth table (the merge node
MUST release, `--task FirstPassFDR` must NOT), the merge-node retained-set arithmetic, the suffix
contract, and the release arm's participation in `TaskValidityKeyTest`'s canonical-pipeline walk -
asserted against a NON-EMPTY arm, since the default emits nothing and a default-arm assertion
asserts nothing. But **deleting the production call site still leaves the unit suite green**.
Only `regression.ps1` mode1/mode3 covers that, and only because the committed golden predates the
change.

## Tasks

- [x] Arm A: protein-compact + pick, 82 files, from scratch
- [x] Arm B: transfer + mean-best-6, `-LinkFrom` arm A
- [x] Carafe NoCut clip fix + pairing validator, tested at r=1.0/0.5/0.1
- [x] `-ExperimentAgg` added to `Run-SeaAd.ps1` (it splats `@PSBoundParameters`, so a lever the
      script does not declare cannot reach the module - setting the env var alone yields a run
      silently aggregated as `max` in a directory named `mean-best-6`)
- [x] Auto-snapshot the Osprey exe in `Invoke-OspreyDatasetRun` so a long run stops locking the
      build tree
- [x] **Settle the library question** - ANSWERED: Mike's delivered library closes the gap from
      -13.0% to -1.9%, at a slightly BETTER FDP. It is the library, not the pipeline.
- [ ] Decompose which part of the library (provenance vs similarity gate vs I/L gate) using the
      `-ungated` / `-gated` rebuilds already on disk
- [x] **Arm C implemented + gated** - `OSPREY_PROTEIN_COMPACT_QUALIFY`, Stellar byte-identity
      PASS on all 5 modes with the flag off
- [x] **Run arm C** - COMPLETE 2026-08-05 11:38, scored: true FDP 1.139% -> 0.426% at 1%
      reported q, with MORE discoveries (38,477 vs 37,056)
- [x] **PR #4534 code review** - all 15 findings addressed (4 in `c601d63cd6`, 11 in
      `a5cb0183a2`); `-Dataset All` green; TeamCity 4123277 running on the tip
- [ ] Run the mb6 + `-QualifyBy experiment` arm (~4h45m) - designed, never launched
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
`ai/.tmp/handoff-20260805_osprey_qualification_sweep.md` before starting work. It carries the
night plan (one arm: protein-compact + mean-best-6 + QualifyBy experiment), the launch and
verification protocol, and the gotchas. The older
`ai/.tmp/handoff-20260804_osprey_pass2_ab.md` is superseded.
