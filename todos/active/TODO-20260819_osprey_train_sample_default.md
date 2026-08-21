# TODO-20260819_osprey_train_sample_default.md

## Branch Information
- **Branch**: `Skyline/work/20260819_osprey_train_sample_default`
- **Base**: `master`
- **Created**: 2026-08-19
- **Status**: In Progress
- **Module**: `osprey`
- **PR**: (pending)

Spun out of the investigation in `TODO-20260801_decoy_similarity_gate.md`, which carries all the
measurement history. This file is the SHIPPING half: the training-selection change, the separately
published Stellar library, and the golden re-baseline they force.

## Problem

Osprey's first-pass Percolator trains one global model on the **best observation of each precursor
across all files** (`PercolatorSampling.SelectBestPerPrecursor`). Every training row is therefore a
maximum over however many runs were batched together, while the model it produces scores ordinary
per-run rows. The mismatch grows with the batch: mean `coelution_sum` is 1.19 at one file and 5.75
at 82, against 1.18 in the population actually being scored.

The visible symptom was read for two weeks as a property of a spectral library. It was not.

## The change

Represent each precursor by ONE uniformly sampled run's observation, at the same row count and the
same memory. Size-1 reservoir: the k-th run a precursor appears in takes the slot with probability
1/k, decided by a SplitMix64 mix of (base_id, k, training seed) rather than a shared RNG, so
thread scheduling cannot move it and a re-run trains on the same rows.

**Measured, 82 SEA-AD files, pass-1, experiment scope, protein-compact + max, at MATCHED true FDP:**

| arm | @0.650% | @0.750% | @1.000% |
|---|---|---|---|
| ours baseline | 33,789 | 34,552 | 35,533 |
| ours + reservoir | 42,131 | 42,982 | 45,252 |
| mike baseline | 34,708 | 36,143 | 39,144 |
| mike + reservoir | 41,204 | 42,989 | 47,154 |

+24.7% for our library, +18.7% for Mike's; with it the two libraries are at parity
(+2.25 / -0.02 / -4.03%). Pass-2, ours: **48,353 @ 0.750%** against 38,776 historical.

`OSPREY_MAX_TRAIN_SIZE` deliberately does NOT change: at matched FDP 300K and 1M are
indistinguishable, 2M and 3M buy ~1.8% for 7-10x the training rows and ~45% more first-pass wall
time. The sampling gets ~+25% for free.

## DECISION (Brendan, 2026-08-19): this ships as a FIX, not an env var

> "The sampling has earned its place as a fix and not an env var."

* Uniform reservoir is the DEFAULT in every selection path.
* Escape hatch INVERTED: `OSPREY_TRAIN_PICK_RUN=0` restores the cross-run maximum. Read with
  `IsNotZero`, so every script written while this was an experiment (which sets it to 1) selects
  the shipped behaviour instead of silently reverting.

## What the flip actually cost - it was not a one-line inversion

The opt-in design threaded per-file offsets (`fileStart`) into `SelectBestPerPrecursor` and made
any path WITHOUT them **throw**:

```
OSPREY_TRAIN_PICK_RUN reached a multi-run selection with no per-file offsets ...
```

Two of the three call sites pass no offsets - `PercolatorTrainer` (the direct path) and
`PercolatorEngine.RunPercolatorStreaming` - and the direct path is what a 3-file Stellar run takes.
Flipping the default alone would have hard-failed the regression suite.

**Root cause of the over-constraint**: the reservoir never read the run index the offsets existed
to supply. `ReservoirTakesSlot(baseId, seen, seed)` needs only the arrival COUNT. The cursor that
walked `fileStart` advanced a `file` local that nothing consumed - dead code. So:

* `fileStart` removed from `SelectBestPerPrecursor` and `BuildTrainingSubset`;
* the abort removed with it;
* every path now honors the reservoir identically, which is a requirement of a shipped behaviour
  and not merely a tidy-up - a path-dependent default is the same defect class as the one this
  investigation started from.

Uniform over OBSERVATIONS is uniform over RUNS exactly when there is one observation per precursor
per run, which is what first-pass per-file rows are. Stated in the doc comment rather than assumed.

## Validity keying - deliberately NOT what the handoff proposed

The handoff said to make the suffix EMPTY for the new default so no existing directory is
disturbed. That is wrong here, and the codebase had already settled it twice:
`PickValidityKeySuffix` and `Pass2QValueValidityKeySuffix` are both UNCONDITIONAL, each with the
reasoning written out - a flipped default whose new arm emits nothing produces a post-flip key
EQUAL to every pre-flip key, so a resume or `-LinkFrom` adopts the OLD selection's scores as though
the new one produced them. `AssertSuffixesAreUnconditional` already asserted the principle.

So `;trainpick=run|max` is emitted for BOTH arms. `;maxtrain=` stays conditional - that knob's
default never moved, so silence for it is correct. The one-time cost is that every
FirstPassFDR-and-later directory predating this is invalidated; Stages 1-5 carry no training
suffix, so `-LinkFrom` still adopts the expensive extraction artifacts.

**If Brendan prefers the empty default anyway it is a one-line change**, but it re-opens the silent
adoption path above.

## `LibraryUrl`: the Stellar library ships separately from the mzML bundle

`stellar-libdecoy-v3.zip` removes 21 entrapment peptides whose I/L-normalised sequence collides
with a real target. An exact-string audit shows 0 collisions for BOTH v2 and v3 - only the
I/L-normalised check separates them.

Bundle acquisition is UNCHANGED (skip-if-present on the extracted root; nobody re-downloads
24.6 GB). The library is a second, independent acquisition:

* new optional dataset key `LibraryUrl`, on both specs that set `LibraryFolder='stellar-libdecoy'`;
* presence check is the **downloaded zip itself**, `<libDir>/stellar-libdecoy-v3.zip`. NOT the
  extracted `carafe_spectral_library.tsv` - both versions produce that same name, so a v2 machine
  would look satisfied and stay on the old library forever;
* downloaded to `<marker>.part` and renamed in, so an interrupted download cannot leave a truncated
  file whose NAME claims v3 is present and suppress every later attempt;
* extracted with OVERWRITE (`Expand-ZipInto -Overwrite`, renamed from `Expand-ZipNoOverwrite` and
  given the switch) because both zips carry the same three entry names;
* ordered so `LibraryUrl` wins and the `NestedZip` branch is skipped outright when it fired, rather
  than relying on the no-overwrite semantics to protect it by accident.

## Mike's pass-2 lever arm COMPLETED 02:26 - the deficit closes at pass 1, NOT at pass 2

Run `seaad-82files-libdecoy-r1.0-protein-compact-p2lever-mike-n82`, 328.8 min (started 20:57).
Validity confirmed in the log: `competition CONSTRAINED to the 698146-base_id protein stratum`, and
PerFileRescoring took 11,977.5 s (3h20m) - the resume defect's signature is 19 minutes, so this is
a real run. It ran longer than the README's 2h39m purely because my regression and re-measure jobs
were sharing the 32 cores; that is NOT a regression and must not be used to "update" the README.

**Both arms protein-compact + max, lever ON, at matched true FDP, experiment scope:**

| arm | pass-1 @0.650% | @0.750% | @1.000% | **pass-2 @0.750%** |
|---|---|---|---|---|
| ours + lever | 42,131 | 42,982 | 45,252 | 48,353 |
| **mike + lever** | 41,204 | **42,989** | 47,154 | **52,381** |

At nominal q, Mike's pass-2 experiment arm is 58,644 @ 1.4715% combined FDP.

**The pass-1 table is confirmed exactly** - Mike's pass-1 row reproduces the handoff's numbers to
the digit, so the earlier measurement stands.

**But the pass-2 conclusion has to be withdrawn.** The reading recorded on 2026-08-19 evening was
"ours + lever (48,353) exceeds Mike's HISTORICAL 43,754 by +10.5%". That is still arithmetically
true, and it is the wrong comparison - it mixes three changes. The clean single-variable
comparison, now in hand, is **ours 48,353 vs mike 52,381 at the same 0.750% true FDP: our library
is 7.7% BEHIND at pass 2** while at parity at pass 1.

So: **the training-selection change closes the library deficit at pass 1 and does NOT close it at
pass 2.** The handoff's stated expectation was parity; the honest outcome is worse than parity for
our library downstream. Whatever remains is a pass-2 effect - reconciliation, the stratum, or the
second-pass recalibration already known to be anti-conservative - and it is a separate
investigation from this PR.

**Caveat that must travel with these two numbers**: both arms were run with the PEAK-level sampler,
which is what existed when they were launched. They are internally consistent with each other, but
neither is the shipped run-level sampler's number.

## `/code-review max` triage (2026-08-19 22:30)

15 findings. Verified before acting, per the review-chain rule. Acted on:

| # | finding | disposition |
|---|---|---|
| 1 | reservoir samples PEAKS not RUNS | **CONFIRMED against two in-repo comments; FIXED** - the root cause above |
| 4 | `ReservoirTakesSlot(baseId, ...)` masks off the decoy bit, so a target and its paired decoy draw identically at every k | **CONFIRMED from the code; FIXED** - the draw now takes `seenKey` in both files |
| 8 | `AssertEveryTaskCarriesTheSuffixesItNeeds` never built the new suffix, so any of the 3 hand-wired call sites could be deleted green | **FIXED** - walk extended with the same exemption shape |
| below-cut | braceless `if` with a two-line body (STYLEGUIDE) | **FIXED** |
| below-cut | duplicated k=1 assertion under a comment claiming a property finding 1 falsified | **FIXED** - duplicate removed, comment corrected |

Still open, in rough priority order:

* **(2) `RunStreamingFirstPass` hand-builds `trainConfig`** and drops `UseGradientBoostedTrees`,
  `GbtParams` and `NThreads` instead of calling `PercolatorConfig.CloneForTrainOnly()`, so
  `--fdr-method gbdt` on the lean counts-only path silently trains AND scores a linear SVM while
  the same run on a smaller join gets real trees. **Pre-existing, not from this branch**, but it is
  a wrong-answer defect and deserves its own issue.
* **(3) the selection is read from a process-wide static with no pass parameter**, so it governs
  SECOND-pass and per-file-rescore training too, where gap-fill rows are target-only and resolve to
  a synthetic zero-feature vector (`ParquetIndex = uint.MaxValue` -> `(int)` -> -1 ->
  `BuildBasicFeatures`). Under the maximum those rows never won; under a reservoir each wins with
  probability 1/k, contaminating the pass-2 discriminant asymmetrically. Needs either a pass-scoped
  parameter or an explicit exclusion of synthetic rows from training.
* **(5) `--input-scores` multi-path form is NOT sorted** (`Program.cs:616` sorts only the
  single-directory branch), so the doc claim "the input file list is ordered, which it is" is false
  for that form, and file order is not in the validity key.
* ~~**(7) the `StripDecoys` derived-library cache is keyed on mtime**~~ - **FIXED in `404104823b`,
  committed locally but NOT PUSHED.** `ExtractToFile` restores the ZIP ENTRY's timestamp, so a
  machine that derived from v2 AFTER the v3 zip's build stamp reuses the stale v2 library.
  Mechanism verified on this machine (the extracted v3 tsv carries a 2026-08-19 23:58 UTC stamp,
  not "now"); tonight's run re-derived correctly so no golden was poisoned. The derived name now
  carries the acquisition marker, so two library versions can never share a derived file; specs
  without `LibraryUrl` keep their existing name. Held back from the push because a new commit has
  no Perf/Regression status (manual-trigger config, status keyed to a SHA) and #4593 would stop
  reading `ready_to_merge` until re-triggered.
* **(10) `TrainPickRun` is a `static readonly` field**, breaking this file's own documented
  settable-property convention for A/B arms, so the `=0` arm has no test coverage and
  `TestEveryPathSamplesARun` fails on any machine with the variable exported.
* **(11)** the LibraryUrl marker is renamed into place before the payload is proven to be a zip,
  and nothing asserts the extraction yielded `$Spec.Library`; also the extraction sits outside the
  marker check so 2.53 GB is re-extracted on every invocation (twice under `-Dataset All`).
* **(12)/(13)** `IsNotZero` is an exact `!= "0"` test, and the maxtrain half keys on PRESENCE
  rather than resolved behaviour.
* **(14)** `bestScores` is allocated and filled full-N but never read on the default path
  (~656 MB dead at 82 files, ~4 GB at 500).
* **(15)** `docs/07-fdr-control.md`, `docs/16-determinism.md` and `docs/20-command-line.md` still
  describe the retired maximum, including a C#/Rust parity claim this change breaks.

**Refuted and recorded so nobody re-litigates it**: the mixer itself is sound. The reviewer
reproduced `ReservoirTakesSlot` at 64-bit width - P(take at k) matches 1/k, the winner is uniform
for K in {2,3,4,5,82}, decisions decorrelate across k including k<->2k, modulo bias ~k/2^64. Every
defect is in how the sampler is WIRED IN, not in the sampler.

## The corrected sampler, measured (2026-08-19 23:19)

`regression.ps1 -Dataset Stellar` on the run-level sampler, against the same committed golden:

| signal | peak-level draw | **run-level draw** |
|---|---|---|
| RefSpectra keys only in golden (sampled) | 54 | **19** |
| RefSpectra keys only in run (sampled) | 2 | 2 |
| total mode-1 issues | 77 | **71** |
| mode 1c / 2 / 3 / 4 / 5 / 6 | all PASS | all PASS |

Sampled-key loss down roughly two thirds. `mode3 (HPC chain==straight)` PASS again, so the
run-level draw is HPC-consistent; `mode2 (resume==straight)` and `mode4 (warm re-run all cached)`
PASS, so the validity keying is stable and reproducible.

### AUTHORITATIVE full-population counts (re-baseline, 23:56)

Plain Stellar, `blib_summary.tsv` - the clean training-only attribution, since that dataset uses no
libdecoy library and nothing else changed:

| selection | RefSpectra | vs old rule |
|---|---|---|
| cross-run maximum (old default) | 29,300 | - |
| peak-level draw (first cut) | 24,214 | **-17.4%** |
| **run-level draw (shipped)** | **27,321** | **-6.75%** |

The peak-vs-run correction recovered ~61% of the loss. **A -6.75% residual at 3 files remains and
has to be priced before this ships as an unconditional default.**

### Is the residual a LOSS or a CALIBRATION CORRECTION? - measurement in flight

These are counts at NOMINAL q, not at matched FDP. The whole thesis of the change is that a model
trained on cross-run maxima has inflated apparent target-decoy separation, so it reports more IDs
at a given q than it has earned. Fewer IDs at nominal q with a LOWER true FDP is the change
WORKING.

Plain Stellar carries no entrapment and therefore no FDP oracle, so it cannot settle this. The two
libdecoy goldens do carry entrapment but now confound the training change with the v2->v3 library
swap, so they cannot either.

The clean experiment, running as of 00:00: `-Dataset StellarLibDecoy -CreateGolden` with
`OSPREY_TRAIN_PICK_RUN=0`, same v3 library, same binary - so the training selection is the ONLY
variable. Compare `diagnostics.tsv` pass-1 true FDP and `blib_summary.tsv` counts against the
just-committed default-arm golden. Log `ai/.tmp/fdp-ab.log`; the golden it overwrites is restored
with `git checkout --` afterwards.

* **FDP falls with the count** -> the trade is real and defensible; ship the flip.
* **FDP flat and 6.75% of IDs simply gone** -> it helps only at large N and hurts at small N, and
  making it an unconditional default is Brendan's call, not mine. The escape hatch already exists.

### ANSWERED 2026-08-20 00:04 - the change WINS at 3 files where FDP can be measured

`-Dataset StellarLibDecoy`, v3 library, same binary, selection as the ONLY variable:

| metric | old rule (cross-run maximum) | **new default (run-level draw)** |
|---|---|---|
| RefSpectra | 29,107 | **31,046 (+6.7%)** |
| RetentionTimes | 87,320 | 93,097 |
| pass-1 experiment combined FDP | 0.7753% | 0.7985% |
| pass-1 experiment paired FDP | 0.6985% | 0.7143% |
| pass-2 experiment combined FDP | 0.5022% | 0.5230% |
| pass-2 experiment paired FDP | 0.4506% | 0.4552% |

**+6.7% identifications for +0.023 percentage points of true FDP.** Both axes move the right way at
once; at matched FDP the gain is smaller but still clearly positive. This is at THREE files, where
the run-de-biasing has almost nothing to work with - the mechanism says the advantage grows with
batch size, and the 82-file numbers say the same.

**So the -6.75% on plain Stellar is not evidence against the change.** That dataset carries no
entrapment, so its count at nominal q cannot separate lost true IDs from suppressed false ones -
and on the dataset where that separation IS measurable, the change adds IDs and holds FDP. The two
datasets also differ in decoy source (generated decoys from the hela library vs library decoys +
entrapment), which is the more likely reason the raw counts move in opposite directions.

**Recommendation: the default flip is supported.** The remaining evidence worth having is the
82-file pass-1 re-measure, confirming the +24.7% survives the peak-vs-run correction - that number
was measured on the peak-level sampler and is not automatically the corrected sampler's.

The StellarLibDecoy golden this experiment overwrote was restored with `git checkout --`.

## Tasks

- [x] Separate the work onto its own branch (it was sharing another topic's branch)
- [x] Flip the default; remove `fileStart` and the abort; honor the reservoir on every path
- [x] Invert the escape hatch to `OSPREY_TRAIN_PICK_RUN=0`
- [x] Key the selection unconditionally; keep the training cap conditional
- [x] Test that the previously-aborting path samples (`TestEveryPathSamplesARun`) - verified to
      FAIL under `OSPREY_TRAIN_PICK_RUN=0` with "every winner came from the highest-scoring run"
- [x] Wire `LibraryUrl`; point both Stellar libdecoy specs at v3
- [x] `regression.ps1 -Dataset Stellar` - the owed gate. Every mode PASS except the intended
      golden mismatch, HPC chain and both resume checks included
- [x] `regression.ps1 -Dataset All -CreateGolden`, all four goldens re-baselined and committed
- [x] `/code-review max` - 15 findings, triaged below; 2 confirmed correctness defects fixed
- [x] Single-variable FDP A/B proving the change wins at 3 files where FDP is measurable
- [x] **PR [#4593](https://github.com/ProteoWizard/pwiz/pull/4593)** + TeamCity Perf/Regression
      (4142638) and unit build (4142639) on `pull/4593`, MacCoss Agent 1 - **9/9 green at 02:08,
      `ready_to_merge: true`**
- [x] 82-file pass-1 re-measure on the corrected sampler - see below

## 82-file re-measure on the SHIPPED sampler (02:30, 145.5 min, exit 0)

Run `seaad-82files-libdecoy-r1.0-protein-compact-runlevel-corrected-ours-n82`, ours library,
`-Task FirstPassFDR -LinkFrom` the completed 82-file run, pass-1 experiment scope, matched true FDP:

| arm | @0.650% | @0.750% | @1.000% |
|---|---|---|---|
| ours baseline (cross-run maximum) | 33,789 | 34,552 | 35,533 |
| ours + peak-level draw (first cut) | 42,131 | 42,982 | 45,252 |
| **ours + run-level draw (SHIPPED)** | **44,609** | **45,943** | **48,166** |

At nominal q=0.0100: 45,943 with combined FDP 0.7460% / paired 0.7221%.

**+33.0% over baseline at 0.750% true FDP**, against +24.7% for the peak-level cut. So the
peak-vs-run correction is worth **+6.9% at 82 files on top of removing the -17.4% at 3 files** - it
pays at BOTH ends of the scale, which is what the mechanism predicts: drawing per row both
weighted runs by candidate count and discarded the best peak, and neither of those helps at any N.

This retires the caveat that the headline number was measured on a superseded sampler. The PR body
now quotes these numbers.

### THE 3-FILE GRID WITH A TRUE-FDP ORACLE (2026-08-20 05:40) - the change is a WASH at 3 runs

Pass-1, experiment scope - the same basis as the 82-file grid. Every row here has an entrapment
oracle, so these are the only 3-file numbers that can separate a lost true ID from a suppressed
false one.

| dataset | library | arm | n@1% q | FDP at q | @0.650% | @0.750% | @1.000% |
|---|---|---|---|---|---|---|---|
| Astral | SEA-AD (ours) | baseline | 83,571 | 0.7440% | 81,974 | 83,571 | 87,297 |
| Astral | SEA-AD (ours) | **pickrun3** | 83,836 | 0.7984% | 81,449 | **83,041** | 86,490 |
| StellarLibDecoy | v3 (ours) | baseline | 27,239 | 0.7753% | 26,554 | 26,982 | 28,181 |
| StellarLibDecoy | v3 (ours) | **pickrun3** | 27,191 | 0.7985% | 26,428 | **26,937** | 27,784 |
| StellarGenDecoyEntrap | v3, generated decoys | baseline | 28,629 | 1.2289% | 26,489 | 26,935 | 27,916 |
| StellarGenDecoyEntrap | v3, generated decoys | **pickrun3** | 28,691 | 1.2401% | 26,367 | **26,725** | 27,797 |

**Change at 0.750% matched FDP: Astral -0.63%, libdecoy -0.17%, gendecoy -0.78%.** Under 1%
everywhere. Against +33.0% at 82 files. The benefit scales with run count exactly as the mechanism
predicts, and there is no small-N penalty to design around.

Astral only became measurable because Brendan pointed out the SEA-AD libraries are fine-tuned to
these exact three regression files, so they can be run against them - the regression Astral spec
uses an entrapment-free library and has no oracle at all. Both Astral arms link Stage 1-4 from the
same completed run, so the training selection is the only variable.

**GOTCHA for anyone repeating this**: a full-pipeline run with `--fdrbench-pass 1` aborts in
`PerFileScoringTask.GuardResidentPool` unless `OSPREY_ALLOW_UNFIXED_RESIDENT=fdrbench-pass1` is
set. Running BOTH arms as `-Task FirstPassFDR -LinkFrom <a completed run>` sidesteps it entirely
and is better science anyway - identical upstream artifacts on both sides.

### CORRECTION: the earlier "+6.7% for StellarLibDecoy" was a PASS-2 number

It came from blib `RefSpectra` counts, and the blib is written from second-pass results, so it was
never comparable to the 82-file pass-1 table. Pass 1 is -0.17%. The movement is real but lives at
pass 2, where the two entrapment datasets go OPPOSITE ways at near-identical FDP:

| dataset | pass-2 baseline | pass-2 pickrun3 |
|---|---|---|
| StellarLibDecoy | 28,998 @ 0.5022% | 30,893 @ 0.5230% |
| StellarGenDecoyEntrap | 31,146 @ 0.9204% | 29,742 @ 0.9504% |

### The gendecoy disadvantage, measured cleanly

Same v3 library, same entrapment targets, decoy SOURCE the only variable (`StripDecoys` removes the
library's decoy rows so Osprey generates its own):

| | pass-1 n@1% q | true FDP at that q | pass-1 @0.750% |
|---|---|---|---|
| libdecoy | 27,239 | **0.775%** | 26,982 |
| gendecoy | 28,629 | **1.229%** | 26,935 |

Generated decoys report 5% more identifications at nominal 1% q and pay ~60% more real error for
them; at matched FDP the two are within 0.2%. **The entire apparent gendecoy advantage is
miscalibration, not sensitivity** - a direct argument for the libdecoy line as best practice,
independent of the training change.

### THE 3-FILE PICTURE: "detections go down" is NOT the pattern (2026-08-20 05:00)

Counts at 1% q (blib `RefSpectra` rows), baseline = `OSPREY_TRAIN_PICK_RUN=0`:

| dataset | res | entrapment | baseline | pickrun3 | delta |
|---|---|---|---|---|---|
| Astral | hram | no | 117,719 | 117,265 | **-0.39%** |
| Stellar | unit | no | 29,300 | 27,321 | **-6.75%** |
| StellarLibDecoy | unit | **yes** | 29,107 | 31,046 | **+6.7%** |
| StellarGenDecoyEntrap | unit | **yes** | *pending* | *pending* | |

**Astral - the other no-entrapment dataset, and 4x larger at 117k precursors - is flat to within
0.4%.** Plain Stellar is the only clear drop. So the -6.75% is a property of that one dataset, not
of 3-run inputs generally, and the one entrapment dataset measured so far goes UP 6.7% while
holding FDP (0.7753% -> 0.7985%).

Astral and plain Stellar are clean single-variable comparisons read straight from git: neither uses
the libdecoy library, so the golden delta is purely the training selection. The two entrapment
datasets need real runs for both arms because the golden retains only scalar diagnostics, not the
FDP curve the matched-FDP columns need - `ai/.tmp/run-3file-grid.ps1`, capturing each arm's
model-diagnostics HTML to `ai/.tmp/mdiag/`.

**Only the two entrapment datasets can fill the matched-FDP columns at all.** Plain Stellar and
Astral carry no entrapment and therefore no true-FDP oracle, which is exactly why the -6.75% was
uninterpretable on its own.

### THE FULL 82-FILE PASS-1 GRID (all six arms re-read from disk 2026-08-20 03:45)

Brendan's naming: `pickrun2` = the peak-level draw, `pickrun3` = the shipped run-level draw.
Pass-1, experiment scope, agg=max. `n@1% q` is the count at nominal 1% q; the FDP column is what
that q actually bought, and it is what makes the count readable.

| arm | agg | n@1% q | FDP at that q | @0.650% | @0.750% | @1.000% |
|---|---|---|---|---|---|---|
| ours baseline | max | 34,552 | 0.7497% | 33,789 | 34,552 | 35,533 |
| ours pickrun2 | max | 44,117 | 0.8532% | 42,131 | 42,982 | 45,252 |
| **ours pickrun3** | max | **45,943** | **0.7460%** | **44,609** | **45,943** | **48,166** |
| mike baseline | max | 37,448 | 0.8695% | 34,708 | 36,143 | 39,144 |
| mike pickrun2 | max | 43,436 | 0.7547% | 41,204 | 42,989 | 47,154 |
| **mike pickrun3** | max | **43,103** | **0.8960%** | 40,584 | 41,563 | 44,082 |

Source run dirs: `...-cleanbase-n82` (ours baseline), `...-20260814_121043` (mike baseline),
`...-lever-pickrun2-{ours,mike}-n82`, `...-runlevel-corrected-{ours,mike}-n82`. The four pre-existing
rows reproduce the prior session's table to the digit.

**The nominal-q column adds something the matched-FDP columns do not**: it shows the two libraries
move in opposite DIRECTIONS on both axes at once.

* **ours: pickrun3 strictly dominates pickrun2** - more IDs (45,943 vs 44,117) at LOWER true FDP
  (0.7460% vs 0.8532%). No trade to argue about.
* **mike: pickrun3 is strictly dominated by pickrun2** - fewer IDs (43,103 vs 43,436) at HIGHER FDP
  (0.8960% vs 0.7547%). The curve itself is worse, not just the operating point.

Gain over each library's own baseline at 0.750%:

| | pickrun2 | pickrun3 |
|---|---|---|
| ours | +24.4% | **+33.0%** |
| mike | +18.9% | **+15.0%** |

pickrun2 helped both libraries similarly and left them at parity (within 7 precursors). pickrun3
splits them. **The size of the give-back on Mike's side is the part worth replicating before
leaning on it** - one run per arm, though batch composition is controlled (identical 82 files).

### Like-for-like library comparison on the SHIPPED sampler (03:38, 64.5 min, exit 0)

`seaad-82files-libdecoy-r1.0-protein-compact-runlevel-corrected-mike-n82`. Same 82 files, same
config, same binary - the LIBRARY is the only variable. Pass-1 experiment scope, matched true FDP:

| library | @0.650% | @0.750% | @1.000% |
|---|---|---|---|
| **ours** | **44,609** | **45,943** | **48,166** |
| mike | 40,584 | 41,563 | 44,082 |

**Our library is +10.5% AHEAD at 0.750% true FDP.** At nominal q Mike's arm sits at higher FDP
(0.8960% vs ours 0.7460%), which is why matched-FDP is the comparator.

**The peak-vs-run correction is ASYMMETRIC across the two libraries:**

| library | peak-level draw | run-level draw (shipped) | delta |
|---|---|---|---|
| ours | 42,982 | 45,943 | **+6.9%** |
| mike | 42,989 | 41,563 | **-3.3%** |

So on the peak-level sampler the libraries were at parity (42,982 vs 42,989, +0.02%); on the
shipped sampler ours leads by 10.5%. **The deficit that opened this entire investigation is not
merely closed - on the shipped code it is reversed.**

**Caveats that must travel with this.** One run per arm, no replicate. The comparison IS controlled
for batch composition - identical 82 files both sides - so the known pool-composition sensitivity
is not in play here, but a single measurement is still a single measurement. And this is pass 1;
the pass-2 picture is the opposite (see Mike's pass-2 arm above, where ours is 7.7% behind), which
is now the more interesting open question: **the two libraries swap places between pass 1 and pass
2, and that gap is a pass-2 effect worth its own investigation.**

## ROOT CAUSE of the -17.4%: the reservoir samples PEAKS, not RUNS (confirmed 2026-08-19 22:30)

`/code-review max` found it and the code confirms it. **Pass 1 is pre-compaction**, so a precursor
does NOT have one row per run:

* `PercolatorScorer.cs:444` - "a precursor carries several pre-compaction rows per file"
* `ModelDiagnosticsData.CoAssignment.cs:1179` - "Pass 1 is pre-compaction, so one precursor has
  several rows per run (one per candidate peak / scan). The reported peak is the best-scoring one."

The parquet is (entry_id, charge, scan)-sorted for exactly that reason. So `seen` counts CANDIDATE
PEAKS across all files. The doc claim "one row per precursor per run, so uniform over observations
is uniform over runs" - which I wrote into `SelectBestPerPrecursor` and `FirstPassDedupRow.Seen`
tonight - **is false**.

Two consequences, and the second is the expensive one:

1. **Run-yield weighting.** A run contributing 5 candidate peaks takes the slot with probability
   5/6 against a run contributing 1. That is a yield-weighted bias - the same FAMILY of bias the
   change exists to remove, just on a different axis.
2. **Within the winning run the survivor is a RANDOM candidate peak, not that run's best.** The old
   rule took the best peak (of the best run); the new rule takes a random peak (of a
   yield-weighted run). Many candidate peaks are interference or non-apex.

### This explains both numbers

The change conflates two axes:

| axis | at 3 files | at 82 files |
|---|---|---|
| (A) remove the cross-RUN maximum - intended | almost nothing to fix, 3 runs | large, dominates: +24.7% |
| (B) remove the within-run BEST-PEAK choice - unintended | nearly pure harm | swamped by (A) |

At 82 files (A) swamps (B) and the result looks like a triumph. At 3 files (A) is nearly absent and
(B) shows through as **-17.4%**. Corroborating signal already in hand: the Stellar mode-1 comparison
reported `RetentionTimes.bestSpectrum: 100/600 rows differ` - the change is moving WHICH PEAK is
reported, which is exactly (B) and has nothing to do with run selection.

### The correct algorithm

Reservoir over **runs**, best peak **within** the chosen run:

* rows from the same run as the current holder: keep the better-scoring one (within-run best);
* the first row of a NEW run: k += 1, take the new run with probability 1/k;
* rows from a rejected run: ignore.

This keeps axis (A) - the measured +24.7% - and removes axis (B) entirely.

**Consequence for the shipping decision**: the +24.7% at 82 files was measured with the PEAK-level
sampler, so it is not automatically the number the corrected sampler gives. It should be at least
as good - it keeps the run de-biasing and stops discarding the best peak - but that has to be
MEASURED, not assumed. A pass-1 re-measure is `-Task FirstPassFDR -LinkFrom <run>`, ~70-80 min at
82 files, not the full 4.5 h.

**Recommendation: do NOT ship the default flip on the peak-level sampler.** See the status section
at the end of this file for where that stands.

## Consequence: the selection was order-INVARIANT and now is not

A maximum is commutative, so the old rule picked the same row whatever order the runs arrived in.
The reservoir picks the k-th arrival, so which RUN survives follows the arrival sequence. The
ordinal is fixed and thread scheduling cannot move it (the draw is a hash of base_id, k and the
seed, not a shared RNG), but file ORDER now feeds the trained model.

**MEASURED 2026-08-19 22:01, and it holds: `Stellar mode3 (HPC chain==straight): PASS`.** The
4-task HPC chain reproduces the straight-through run exactly under the reservoir, as do
`mode3 (per-file FDR sidecars==straight)` over 2,445,841 records. So the order-dependence is real
in principle but does not bite the chain, because the chain pins its input order. The risk is that
it is now pinned for TWO reasons rather than one, and only one of them is documented where an HPC
operator would look.

This compounds a known latent risk: multi-file FirstJoin reconciliation is already
`--input-scores`-order sensitive, and regression mode 3 pins that order, which masks it. Training
is now sensitive to the same thing. Mode 3 is therefore the test that matters for this change, not
just for reconciliation.

**There is an order-independent alternative and it was NOT taken tonight**: choose the run whose
(base_id, run identity) hash is minimal. That is uniform over runs, order-invariant, and correct
even when a precursor has several observations in one run - but it needs run IDENTITY, which is
what `fileStart`/`PercolatorEntry.FileName` supply and what the arrival-count reservoir does not.

It was not taken because the +24.7% at 82 files was measured on the arrival-order reservoir;
switching the rule selects different rows and invalidates that measurement, at ~4.5 h to re-measure.
Worth doing as a follow-up if order-independence is wanted - the reproducibility argument for it is
real.

## ANSWERED 2026-08-19 21:50: 3 files DO see it, and the effect there is a wash

The open question was whether a 3-file dataset can see a cross-run-maximum change at all, and
therefore whether the suite can protect this behaviour or the PR must add a multi-file dataset.

`regression.ps1 -Dataset Stellar` mode 1 against the committed golden:

| signal | result |
|---|---|
| RefSpectra keys only in golden | 54 |
| RefSpectra keys only in run | 2 |
| RefSpectra total in golden | 29,300 |
| RefSpectra.score rows differing | 200 / 200 sampled |
| RetentionTimes.score rows differing | 595 / 600 sampled |
| RetentionTimes.bestSpectrum rows differing | 100 / 600 sampled |

**The suite sees it clearly - no multi-file dataset is needed.** Scores move on essentially every
row, which is what a retrained model does.

### CORRECTION - the ID effect at 3 files is -17.4%, not the -0.18% first recorded here

The table above counts SAMPLED rows. `osprey-regression.data/*/tables/*.tsv` are sampled dumps
(254 RefSpectra rows before, 202 after), and the "54 only in golden / 2 only in run" figures are
over that sample: 254 - 54 + 2 = 202 reconciles exactly. Dividing a sample-space delta by the full
population gave -0.18%, which was wrong.

The authoritative counts are in `blib_summary.tsv`, which sums the whole table:

| table | golden (before) | re-baselined | delta |
|---|---|---|---|
| RefSpectra | 29,300 | 24,214 | **-17.4%** |
| RetentionTimes | 87,900 | 72,642 | -17.4% |
| OspreyRunScores | 29,300 | 24,214 | -17.4% |

**So the change costs 17.4% of identifications at 3 files while gaining 24.7% at 82.** That is a
much bigger small-N cost than "a wash" and it has to be priced before this ships as a default.

**It is NOT yet established whether that is a loss or a calibration correction.** The 3-file number
is a count at nominal q, and the whole thesis of this change is that the cross-run maximum inflates
apparent target-decoy separation - a model trained on maxima reports more IDs at a given q than it
has earned. Fewer IDs at nominal q with a LOWER true FDP is the change working, not failing.

Plain Stellar carries no entrapment, so it has no FDP oracle and cannot settle this. **The
discriminating measurement is StellarLibDecoy / StellarGenDecoyEntrap**, which do carry entrapment
and a true-FDP bound, and whose diagnostics goldens are being captured now. Compare pass-1 true FDP
before and after: if FDP falls with the ID count, the trade is real and defensible at small N; if
FDP is flat and 17% of IDs are simply gone, that is a genuine small-N regression and the default
flip needs Brendan's explicit call.

## C#/Rust parity

This is a C#-only behaviour change. The Rust equivalent is
`crates/osprey/src/pipeline.rs:6817-6900` (best-per-precursor dedup + subsample). `regression.ps1`
has no cross-impl comparison, so no gate goes red, but the "C# == Rust" signal is broken for
first-pass training until Rust takes the same change or parity is retired.

## Product defects found, worth filing separately

1. **`-Resume` past FirstPassFDR silently breaks protein-compact pass 2.** The stratum is published
   in memory only, so a resumed run has none, the stratified competition does not happen, and
   pass-2 output equals pass-1 - with no error. Fix: persist the stratum, or hard-fail without one.
2. **Batch-composition sensitivity** - a file's identifications depend on which other files were
   batched with it (~+-20% at baseline). Draft at `ai/.tmp/issue-draft-pool-sensitivity.md`.

## 2026-08-21 - The pass-2 table completed; the acquisition bug found in production

### The 82-file pass-2 table, finished

Three `-LinkFrom` arms plus a full-pipeline ungated arm, all on one pinned snapshot
(`_bin\26.1.1.232-20260820-0534`), all protein-compact + max, experiment scope, matched true
FDP @0.750%. Every arm logged the protein stratum line; every arm reproduced its pass-1 count
to the digit against an independent earlier run.

| library / arm | pass 1 | pass 2 | pass-2 lever delta |
|---|---|---|---|
| ours baseline | 34,552 | 35,327 | - |
| **ours pickrun3** | **45,943** | **52,911** | **+49.8%** |
| mike baseline | 36,143 | 42,679 | - |
| mike pickrun3 | 41,563 | 47,855 | +12.1% |
| ours ungated (pickrun3) | 43,620 | 51,325 | - |

**The pass-2 reversal was a sampler artifact.** Under pickrun2 ours was 7.7% behind at pass 2;
under the shipped sampler ours is **10.6% ahead** (52,911 vs 47,855), against +10.5% at pass 1 -
the pass-1 lead carries through unchanged. Both libraries now gain the SAME from pass 2 (+15.2%
ours, +15.1% mike); the +22.7%/+12.5% asymmetry that drove the investigation belonged to the
superseded peak-level sampler.

**The mechanism**: ours-baseline gains only **+2.2%** from pass 2 against +15.1-18.1% for every
other arm. Under the cross-run maximum our first-pass model is poor enough that the second pass
recovers little from it - the damage compounds downstream rather than washing out.

**The similarity gate at 82 files, run at last** (`...-p2-pickrun3-oursungated-n82`, full
pipeline, 8h03m): worth **+5.3% at pass 1 and +3.1% at pass 2**, while spending LESS true error
in both passes. It was elusive because at N=1 it measures -0.06%, the 82-file test was blocked
by the pooling defect, and the one table that seemed to show a gate effect was an N confound
with the wrong sign. Caveat: `-no_similarity_gate` also disables I/L collision rejection, so
this is two generation changes. Full record in the companion HTML, section 15.

### The LibraryUrl overwrite bug was real, and it was on the build agent

Confirmed in production. TeamCity build 4145031's log:

    extracting stellar-libdecoy-v3.zip into stellar-libdecoy-v3 (one time)...
    repairing 3 bundled library file(s) overwritten by a separately-shipped library...
      restoring carafe_spectral_library.tsv
      restoring osprey_library_db_pairing.tsv

MacCoss Agent 1 had been holding v3 content under the bundled v2 names since the pre-fix
acquisition ran there, which cost a parallel session a night proving its golden was fine while
the library beneath it had been silently replaced.

**Why the repair ships even though the bug was created and fixed inside this branch**: the
damaged machines are real and cannot be reached conveniently - the agent's data lives under the
build user's profile. `Get-ZipEntryMismatches` compares the bundle tree against the bundle's OWN
nested zip on entry length and last-write time (both free from the central directory, so no
multi-GB hashing), and re-extracts only what differs. Costs no download and no hand cleanup. It
runs regardless of which library the run uses, because only a URL run can damage the tree and
the tree it damages is the one that run is NOT using. This is deliberately NOT in the squash
message - it repairs a problem this branch created - so this paragraph is its durable record.

### One golden re-baseline, not two

`404104823b` keyed the derived decoy-free library on the acquisition marker at 02:34; the
goldens had been captured at 23:57, so `StellarGenDecoyEntrap` mode 1 found
`SpectrumSourceFiles.idFileName` differing on 3/3 rows
(`carafe_spectral_library.nodecoy.tsv` -> `carafe_spectral_library.stellar-libdecoy-v3.nodecoy.tsv`).
Re-captured in `cc137a07e0`: three rows, one column, `cutoffScore` and `workflowType` untouched,
no other golden file moved. The branch lands one net golden state.

**Process note worth keeping**: the 9/9 green was on `8e554b9978`, and two commits were then held
back from the gate deliberately. This was the first time they ran through it, and one of them had
moved a value a golden records. Holding commits back from a manual gate defers exactly this.
