# TODO-osprey_test_subsetting.md

## Branch Information
- **Branch**: `Skyline/work/20261027_osprey_test_subsetting` (from `master` at b68aa96d5f, after #4917
  and #4925 merged), checkout `C:\proj\pwiz`
- **Created**: 2026-10-27
- **Status**: PR open
- **PR**: [#4931](https://github.com/ProteoWizard/pwiz/pull/4931); Rust: maccoss/osprey#74
- **Module**: `skyline` (the tests and their data; `osprey` for `Osprey.Test` and the subset scripts)
- **Objective**: Cut the cost of Skyline-Osprey integration testing to what the test data warrants: the
  functional tests tune on ONE run at 1% FDR without workarounds, and `OspreySearchPerfTest` runs in
  about 5 minutes on a CPU agent instead of 29-59 minutes on the full Stellar data.
- **Requested by**: Brendan, 2026-10-26, after PR #4917 (Osprey as the engine behind Build Library) and
  the perf test's exclusion from the TeamCity PR perf run (`tc-perftests-skiplist.txt`, f7731c2c1a)
- **Session shape**: a `/night-session` that PROPOSES the subset strategy from measurements, with the
  decision left to the morning (see "What the night decides, and what it does not")

## Why

Two things keep forcing the tests to cheat on the current subset, and one thing keeps TeamCity waiting:

1. **One run cannot tune.** `StellarSubset.zip` is 1 of 125 isolation windows over 7 of 24 minutes, with
   a 358-precursor library. First-pass q is (decoys+1)/targets, so a run needs over 100 targets before
   its first decoy; a 7-minute slice gives 128-154 per run, and a run searched alone keeps nothing at 1%
   and exports nothing (`D:\test\osprey-runs\tuning-probe\run.log:91-92`, "0 precursors at 1.0%
   run-level FDR"). So the tuning tests tune on all three runs (`OspreySearchTuningTest.cs:45-47`,
   `SubsetPipelineTest.LibraryTuning.cs:71-72`) and one of them reports every precursor
   (`--experiment-fdr 1`, `LibraryTuning.cs:136-140`) because a one-epoch tuning on two windows detects
   nothing at 1% on some CPUs. Those are the "q value < 1" and "three files instead of one" workarounds.
2. **The perf test is the whole dataset.** `OspreySearchPerfTest` searches the three full Stellar runs
   (1.49 GB each) with the 10,650-protein `hela-filtered.fasta`, tunes on `_21`, then searches again with
   the saved model, importing the three files into Skyline twice. On a CPU the Osprey part alone is about
   16 min: full-FASTA prediction twice (108 s + 214 s), the fine-tune on 27,768 exported precursors (416 s),
   the two searches (78 s + 132 s); TeamCity measured 29 min on MacCoss Agent 1 and 59 min on an AWS agent
   (`D:\test\osprey-runs\one-command-stellar-tuned\one-command\run.log` for the per-task seconds).
3. The fine-tune scales with exported precursors and the prediction with FASTA size, so both are what a
   mid-size subset shrinks; the imports scale with the mzML size.

## The two targets

**Target 1 - the functional subset.** The smallest Stellar subset on which one run, searched alone, passes
1% in the first pass and exports enough precursors (over 300) for a fine-tune that beats the pretrained
model on a held-out run; on which the Osprey leg of a functional test stays under about a minute on a
CPU. Cheapest lever: a longer RT slice of the SAME window (the full 24 minutes is about four times the
targets) before more windows, since the subset tooling keeps one window today.

**Target 2 - the perf subset.** A mid-size Stellar subset, closer to real-world but not all of it: several
windows (a contiguous m/z band) over the full gradient, with the REAL proteins of the kept peptides from
`hela-filtered.fasta` rather than synthetic ones, so one tuned run plus the saved-model search, Skyline
imports included, takes about 5 minutes on a CPU. Expected scale: a few thousand exported precursors, a
few hundred proteins, a zip of a few hundred MB.

## The one rule on where data lives (Brendan)

**There is no scenario where a second subset committed to Git makes sense.** Two outcomes are allowed:

- **A: the one subset grows.** `StellarSubset.zip` (4.1 MB in `Osprey.Test\TestData`, mirrored into
  `TestFunctional\OspreySearchTest.zip`) grows just enough to cover ALL Skyline-Osprey integration testing
  (the wizard, tuning on one run, Build Library through Osprey), and the wider Osprey-Carafe testing stays
  with `regression.ps1` on the full data. The perf test then runs on the grown subset or on the full data,
  whichever the morning decides, but no third dataset appears.
- **B: a new mid-size zip on Panorama.** A new subset of hundreds of MB, stored on panoramaweb.org beside
  the regression data (`GetPerfTestDataURL`, the `Perftests` folder; `panorama-access` skill for the
  upload), downloaded by `OspreySearchPerfTest` as the full data is today. The small subset in Git stays
  as it is or grows a little; the mid-size one is never in Git.

The night measures both routes and proposes one; it does not upload anything to Panorama and does not
replace the committed zip.

## What exists

- `ai/scripts/Osprey/SubsetData/build_subset.py` (the Stellar preset: runs `_20/_21/_22`, target window
  594.5201, half-width 2.0, RT 7-13 min, ms1 band 590.5-600.5, up to 180 undetected library precursors,
  mantissa trimming), `subset_mzml.py` (ONE `--target` window plus an RT range), `subset_library.py`
  (library rectangle, detected/undetected from a full-run blib, synthetic proteins), `subset_libdecoy.py`;
  outputs byte-identical zips. `SubsetData\README.md` "Why the sizes" explains the 100-target floor.
- `SubsetPipelineTest.LibraryBuild.cs:301-329 WriteSubsetProteinFasta()` writes the synthetic-protein
  FASTA; `WINDOW_MIN_MZ/MAX_MZ` (592.5-596.6) are the prediction window, not a builder parameter.
- `TestFunctional\OspreySearchTest.zip` is built by an UNCOMMITTED session script
  (`ai/.tmp/sessions/20261023-osprey-search/New-OspreySearchTestZip.ps1`, per
  `todos/completed/2026/10/TODO-20261023_skyline_osprey_search.md:186-190`): commit it into `SubsetData`.
- Full data: `D:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML-v2\stellar\` - three mzMLs of
  1.49 GB, 125 isolation windows 402-899 m/z, 24 min, `hela-filtered.fasta` (10,650 records), the 554 MB
  library TSV. `regression.ps1` modes 13/14 are the tuning legs at full scale.
- Inputs the subset builder needs: a full-run `output.blib` from `regression.ps1 -Dataset Stellar`
  (`--full-blib`); check `D:\test\osprey-runs` for a current one before re-running the 35-minute leg.

## Plan for the night

1. **Tooling (first, small):** extend `subset_mzml.py` to a window list or m/z band and keep
   `subset_library.py` in step; add a real-protein FASTA writer (the proteins of the kept peptides, from
   `hela-filtered.fasta`); commit the OspreySearchTest.zip builder; write `Measure-Subset.ps1` beside them:
   one command runs a candidate through Osprey's one command on the CPU (`--device cpu`,
   `--training-input <one run>`, the wizard's digest) and reports exported precursors, precursors at 1%
   per run, the tuned model's held-out metrics, per-task seconds from the `[TASK]` lines, and the zip
   size. Every candidate is one invocation, every number has a log path.
2. **Target 1 candidates** (measure all, in this order): one window over 24 min; two windows over 12 min;
   three windows over 7 min. Record targets per run, first-pass survival of one run, export size, tuning
   time, the functional-test leg time.
3. **Target 2 candidates**: a 12-window band over 24 min; 25 windows over 12 min; with real proteins.
   Record the Osprey phases, the zip size, and the Skyline import time (run `OspreySearchPerfTest`'s
   shape against the candidate through the wizard test harness if a cheap path exists; else time the
   one command plus a `SkylineCmd --import-file` of the mzMLs).
4. **Write the proposal** in this TODO's Progress Log: a table of candidates with the measured numbers,
   the route (A or B) the numbers support, and what each test would become. Keep every log under
   `D:\test\osprey-runs\subset-<candidate>\` and cite the paths.
5. If time remains and the route is clear: prepare the test changes on the branch WITHOUT replacing the
   committed zip or uploading to Panorama - `OspreySearchTuningTest` and `SubsetPipelineTest.LibraryTuning`
   tuning on one run with the workarounds removed, `OspreySearchPerfTest` as one straight-through run,
   `tc-perftests-skiplist.txt` entry removed - each gated on the candidate zip from a local path, so the
   morning can swap in the real data location.

## Acceptance (what "done" means for the sprint, after the morning decision)

- Target 1: one run tuned alone exports over 300 precursors, passes 1% in the first pass, and the tuned
  model beats the pretrained one on a held-out run; the three-run and `--experiment-fdr 1` workarounds are
  gone from `OspreySearchTuningTest` and `SubsetPipelineTest.LibraryTuning`; Osprey's own subset tests stay
  within about twice their current time (route A) or are untouched (route B).
- Target 2: `OspreySearchPerfTest` is one tuned run plus the saved-model search on the chosen data, under
  5 minutes on a CPU, and back in the TeamCity PR perf run.
- `regression.ps1` and the full Stellar data are unchanged.

## What the night decides, and what it does not

Decides: the candidate table, the route the numbers support, the tooling. Does not decide: which route
ships (Brendan), uploading to Panorama (Brendan, through the panorama-access skill), replacing
`StellarSubset.zip` (its goldens and 645 Osprey tests hang off it), or changing `regression.ps1`.

Budget rules from the nights of 2026-10-23/24 (memory): delegate the survey, read logs by range, re-measure
context at 30 minutes, announce long runs and keep the taskbar looking like progress; finish the queue
rather than winding down at the wake time; cite the on-disk path for every number.

## Progress Log

### 2026-10-26 - Written

Survey by a read-only agent (figures above); design discussed with Brendan after PR #4917. Queued for the
night session of 2026-10-26.

**Handoff from the session of 2026-10-26**: read `ai/.tmp/handoff-20261026_osprey_followups.md` first (build and test gotchas, what #4917 left in the code, the hidden cost of growing the one subset).

### 2026-10-27/28 - Session on BRENDANX-UW6 (night lost to a blocking question; resumed 08:16)

**Machine.** The paths above (`D:\test\osprey-runs`, `D:\Users\...\Downloads`) are another machine's. Here the
data is `E:\Users\brendanx\Downloads\Perftests\osprey-testfiles-mzML-v2` (the relocated Downloads that
`regression.ps1` and the Skyline perf test both resolve), runs go to `E:\test\osprey-runs`, the handoff
`ai/.tmp/handoff-20261026_osprey_followups.md` and the 2026-10-23 session folder are not on this machine.
A 21:03 AskUserQuestion about which machine to use blocked until 08:16 - the night produced nothing.

**Full-run blib.** `regression.ps1 -Dataset Stellar -SkipResume -SkipWarmRerun -SkipHpcChain -KeepOutput`
PASSED vs golden, straight-through 300 s (`ai/.tmp/sessions/20261027-subset/regression-stellar.log`);
blib copied to `E:\test\osprey-runs\stellar-full\output.blib`. Measurement exe snapshot
`E:\test\osprey-runs\_bin\subset-20261028` (v26.1.1.300, b68aa96d5f). This machine: 12 logical processors.

**Tooling (pwiz-ai 39413684).** `subset_mzml.py --target-lo/--target-hi`; `subset_fasta.py` (real records, or
`--concatenated` - reproduces the committed `stellar-subset-proteins.fasta` byte for byte, so it IS the
OspreySearchTest.zip builder's FASTA step); `build_subset.py` candidate overrides + `--functional-zip`;
`Measure-Subset.ps1`. Edits are output-neutral: HEAD scripts and edited scripts give byte-identical zips
from the same blib (`ai/.tmp/sessions/20261027-subset/StellarSubset-{orig,rebuilt}.zip`).

**Finding - regenerating the committed zip is not free even at the same geometry.** Rebuilt today, the
mzMLs and README are byte-identical to `StellarSubset.zip` but the library files are not (detected RTs move
~0.02 min, membership shifts: `manifest.tsv` 10,115 vs 10,047 bytes) - the full-run blib comes from today's
Osprey, not the 2026-09-27 one. Any route-A regeneration moves the goldens for that reason alone.

**Finding - the floor is the SECOND pass, not the first.** Control at the committed geometry (1 window,
RT 7-13, `E:\test\osprey-runs\subset-control-w1-rt7-13\tuned\run.log`): the tuning search of `_21` alone
passes 126 targets / 0 decoys at 1% in the FIRST pass (:92), but the second pass recomputes q only over the
147 candidates of the 39 proteins with 2+ detections (:97, :117) - ~74 targets, so the best possible q is
1/74 = 1.35% - and nothing passes: export 0 (:111), experiment level 0 of 183 (:124), exit 1 after 4.2 s.
What a one-run subset needs is >~100 targets in the multi-detection-protein stratum of the tuning run.
The pretrained 3-run search of the same data reports 368 (123/114/131 per run; `pretrained\run.log`).

#### Candidates measured (2026-10-28, BRENDANX-UW6, 12 threads, CPU; exe `E:\test\osprey-runs\_bin\subset-20261028`)

Every number is from `E:\test\osprey-runs\subset-<name>\summary.txt`, which cites the `run.log` of each leg.
Tuned = `--training-input _21` alone; pretrained = same command without it; saved = `--model <tuned>\output.model.zip`.
Digest = SubsetPipelineTest's (trypsin, 7-35, z2-3, C+57) with `--min/max-pep-mz` = the band, except `-wiz`.

| Candidate | Proteins | `_21` alone at 1% | Export | Final 3 runs tuned / pretrained | Held-out `_20`,`_22` tuned / pretrained | Held-out MS2 PCC pre -> tuned (n) | Tuned wall (TrainModel) | Saved wall | Zip |
|---|---|---|---|---|---|---|---|---|---|
| control w1 RT7-13 (committed geometry) | 103 syn | 126 1st pass, **0 after 2nd** | 0 | exit 1 / 368 | - | - | 4 s | - | 3.5 MB |
| w1 RT0-24 | 309 syn | 271 | 168 | 993 / 908 | 311,321 / 311,287 | .965 -> .988 (7) | 32 s (18) | - | 11.0 MB |
| **w2 RT6-18** | 354 syn | 460 | **345** | **1461 / 1383** | **481,506 / 455,455** | .914 -> .941 (22) | **43 s (31)** | - | 12.9 MB |
| w3 RT7-14 | 319 syn | 443 | 340 | 1303 / 1281 | 424,434 / 428,423 | .928 -> .949 (21) | 42 s (31) | - | 11.9 MB |
| w12 RT0-24 real, undetected 8640 | 5657 | 3475 | 2589 | 11160 / - | - | .944 -> .965 (236) | 281 s (181) | - | 127.9 MB |
| w25 RT6-18 real, undetected 9000 | 5947 | 5431 | 4751 | 18033 / - | - | .942 -> .965 (445) | 448 s (273) | - | 159.3 MB |
| w12 RT0-24 real u0 | 2360 | 3500 | 2716 | 11132 / - | - | .937 -> .958 (248) | 252 s (192) | 38 s | 125.0 MB |
| **w8 RT0-24 real u0** | 1780 | 2345 | **1614** | 7300 / - | - | .941 -> .968 (139) | **157 s (118)** | **26 s** | **83.6 MB** |
| w12 RT6-18 real u0 | 1900 | 2758 | 2050 | 8405 / - | - | .939 -> .972 (186) | 199 s (151) | 30 s | 75.7 MB |
| w8 RT0-24 real u0 **-wiz** (no m/z bounds) | 1780 | 2334 | - | 7276 / - | - | - | **362 s** | **230 s** | 83.6 MB |

- Target 1 is met by **w2 RT6-18** only: one run alone exports 345 (>300), the tuned model beats pretrained on
  all four MS2 metrics (n=22) and on both held-out runs, the Osprey leg is 43 s. w1 RT0-24 exports 168; w3's
  held-out `_20` drops (424 vs 428). Route-A sizes at w2 geometry (`subset-w2-rt6-18\routeA\`):
  `StellarSubset.zip` 14.95 MB (now 4.1), `OspreySearchTest.zip` 13.2 MB (now 3.7) - the latter is the same
  three mzMLs plus a 25 KB FASTA, so under route A the Skyline test should read the Osprey zip, not a copy.
- TrainModel is ~70 ms per exported precursor at 12 threads (118 s / 1614, 192 s / 2716); it is the cost that
  sizes Target 2. Undetected precursors cost nothing in TrainModel but drag their proteins into the FASTA
  (5657 vs 2360 at w12) and double the prediction; with real proteins, keep undetected 0 - the proteins'
  other in-band peptides are the realistic undetected targets.
- Target 2 at the bounded digest: **w8 RT0-24 real u0**, Osprey 157 + 26 = 183 s, 3 x 67.7 MB mzML, 83.6 MB zip.

**Finding - FASTA prediction ignores the runs' isolation range (an Osprey change, not this branch).**
Through the wizard (no `--min/max-pep-mz`, `OspreyHelpers.AppendLibraryBuildArgs`) Carafe predicts its
default 300-2000 m/z (`CarafeCommandLine.cs:83-84`) in PredictTrainingLibrary and in a saved-model or
pretrained PredictLibrary; only the PredictLibrary right after a fine-tune is limited, because
`CarafeModelDirectory.ApplyTrainingRunOverrides` sets the window from the training run's isolation range.
w8-wiz: 289,552 precursors predicted in 212 s for the training library vs 12,124 in 10.6 s bounded
(`subset-w8-rt0-24-real-u0-wiz\tuned\run.log` vs `subset-w8-rt0-24-real-u0\tuned\run.log`), and the saved
leg 210.5 s ("Precursor m/z 300-2000 ... from the command line", `-wiz\saved\run.log:19`) - with no change in
what is identified (7276 vs 7300). On the FULL hela-filtered.fasta, 400-900 holds 54.3% of the z2-3
precursors in 300-2000 (219,110 of 403,786; `ai/.tmp/sessions/20261027-subset/mz_fraction.py`), so every
wizard FASTA prediction on real Stellar does 1.84x the needed work. The training library is also predicted
at NCE 27 / Eclipse rather than the training run's NCE 30 / Stellar. Defaulting the precursor window (and
NCE/instrument) to the searched runs' isolation range would take Target 2 through the wizard from ~10 min
to ~3 min of Osprey on w8 and cut the full-data perf test's prediction roughly in half.

**Target 2 measured end to end.** `OspreySearchPerfTest` (branch change: `SKYLINE_TEST_OSPREY_PERF_ZIP` names a
local zip of the regression layout) against `E:\test\osprey-runs\subset-w8-rt0-24-real-u0\perf\osprey-stellar-w8-rt0-24.zip`
(87.3 MB: 3 x 71 MB mzML + 0.78 MB FASTA of 1,780 real proteins): **PASSED in 362 s** - tuning search, saved-model
search and both Skyline imports, CPU, 12 threads; 2,523 / 2,535 library spectra
(`ai/.tmp/sessions/20261027-subset/perftest-w8.log`; Osprey logs under
`pwiz_tools\Skyline\TestResults\TestRunner results\osprey-stellar-w8-rt0-24\*.osprey\osprey-skyline-stdout.log`).
Tuning search 09:35:13-09:38:41, saved search 09:39:11-09:40:45. Of the 362 s, PredictTrainingLibrary 79.3 s and the
saved PredictLibrary 78.5 s each predict 130,796 precursors over 300-2000 m/z where the post-tune PredictLibrary
(bounded by the training run) predicts 9,106 in 6.6 s - ~145 s is the isolation-range finding above. With that
Osprey fix the perf test would be ~3.6 min. (The wizard's digest is 66,704 peptide forms vs Measure-Subset's
148,661 - the document's defaults are tighter than SubsetPipelineTest's 7-35 / 1 missed cleavage.)

**Target 1 test changes verified on the w2 data (swapped into the working tree, then restored; not committed).**
`ai/.tmp/sessions/20261027-subset/run-tuning-tests-w2.ps1`: `TestOspreySearchTuning` PASSED 128 s tuning on the
middle run alone (scenario 2 browses that run held out of the outer runs' search, plus a browsed searched run
unchecked, so "never listed twice" keeps its coverage); `TestOspreySearch` PASSED 30 s
(`tuning-tests-w2.log`). Osprey `-TestName Tuned` PASSED all four - Tuned 55 s, HeldOut 24 s, Stepwise 27 s,
HpcChain 26 s (`osprey-tuned-w2.log`) - after widening `WINDOW_MAX_MZ` 596.6 -> 600.6 (the first try predicted
only window 1 and exported 118). Osprey inspection zero warnings; Skyline CodeInspection 0 failures.
Route A's hidden cost: all 28 Osprey `Subset` tests 2.26 -> 4.56 min (2.02x; `osprey-subset-tests-{baseline,w2}.log`),
4 tests failing on data-specific expectations (UnusableDecoys, NothingPasses, BlibLibrary, LibraryDecoysAndReports).

**Local commits on the branch, NOT pushed:** 74c83b911c (perf-test `SKYLINE_TEST_OSPREY_PERF_ZIP` override -
independent, pushable) and ff47137b36 (one-run tuning - passes only with the w2 zips; push only with them).

## Proposal (for Brendan)

**The numbers support route B, with the Git subset growing once.** Target 1 cannot be met without growing the
committed subset - nothing smaller than 2 windows x 12 min lets one run export >300 (w1 RT0-24: 168) - so
"stays as it is" is off the table under either route; and the grown subset is far too small to be a perf test.

1. **Target 1 - grow `StellarSubset.zip` to w2 RT6-18** (`build_subset.py stellar --windows 2 --rt-min 6
   --rt-max 18 --undetected-max 720`): 4.1 -> 14.95 MB. Make the Skyline functional tests read it (or a
   mzML+FASTA zip cut from the same build, `--functional-zip`, 13.2 MB) instead of keeping both. Costs:
   regenerate the goldens and the 4 data-specific expectations; Osprey Subset tests 2x (partly won back by
   moving the stepwise/HPC tuned tests to one run, not done). Gains: no workaround left in either tuning test;
   the held-out scenario becomes a real held-out-run check.
2. **Target 2 - route B: `osprey-stellar-w8-rt0-24.zip` (87.3 MB) on Panorama** beside the regression data
   (8 windows x the full gradient, real proteins of the detected peptides). `OspreySearchPerfTest` on it: 362 s
   on a 12-thread CPU today, both searches and both imports; back into the PR perf run (remove the
   `tc-perftests-skiplist.txt` entry) once the zip is up and the test's URL points at it.
3. **Separate Osprey change (biggest single lever):** default the FASTA prediction's precursor window (and
   NCE/instrument) to the searched runs' isolation range. ~145 of the perf test's 362 s, and ~46% of every
   wizard FASTA prediction on full Stellar, is precursors no run can measure. Perf test -> ~3.6 min.

Not done, for the morning: the Panorama upload, replacing the committed zips and goldens, the URL constant,
the skiplist line, and the Osprey prediction-window issue.

### 2026-10-28 (day) - Brendan accepted the proposal; scaling back what went to large data

**Why tests went to large data (from completed TODOs).** `OspreySearchPerfTest`'s single-run tune existed at
scale because it was "the single-run tuning the subset cannot do" (`completed/2026/10/TODO-20261024_osprey_search_tuning.md:192`);
`OspreySearchTuningTest` and `SubsetPipelineTest.LibraryTuning` tuned on three runs for the same reason (:153-158);
`BuildLibraryCarafeWizardTest` likewise (`TODO-20261026_build_library_carafe_wizard.md:141`, "feature 1 needs
one-run tuning on the subset"); `CarafeModelBuildLibraryTest.zip` (15.6 MB, a pre-tuned Astral model) was already
flagged "move to a server" (`completed/2026/09/TODO-20260928_AlphaPeptDeepSharp.md:77`). `regression.ps1` modes 13/14
were opt-in demonstrations of the tuned one command at scale, their subset twins already the gates.

**Moved / cut (all verified on the w2 data swapped into the working tree, not committed):**
- `BuildLibraryCarafeWizardTest` tunes on the middle run, and now carries `CarafeModelBuildLibraryTest`'s coverage:
  Edit list (empty grid, Add shows what the model was trained on, a duplicate name refused), combo Add... and Remove,
  the display name's instrument and gradient, `CarafeModelChoice` (1 run, NCE 30, Chronologer, RT R2 > 0.99) and the
  saved model's RTs in the tuning run's minutes (8 peptides measured in `_21`, within 1 min). Its entrapment check
  was exact on the small data only: CarafeSharp drops a pair whose target or decoy has too few fragments
  (`LibraryGenerator.cs:241-249`) - 5,332 of 5,334 on w2 - so it now counts the precursors the library holds.
- `SubsetPipelineTest`: HeldOut (search `_20`,`_22`, tune `_21`), Stepwise, HpcChain (own `tuningRuns`) and the
  precursor-table tuned leg tune on one run. `TestSubsetNothingPasses`' empty-stratum leg used to rely on the
  small data passing nothing in the second pass (a cut library probe: window 1 x RT 7-13 fails calibration; window 1
  at full RT passes 263/run - `E:\test\osprey-runs\nothing-probe*`); it now sets `--experiment-fdr 0` and also
  asserts PerFileRescoring ran, which is what the test is about. `TestSubsetBlibLibrary`'s typing check now
  requires `Differ == 0` (library-choice isobars, e.g. YDSIDSYLSK b8^2 vs b4, are the library's prerogative per
  `FragmentTypeCheck`'s own doc) instead of `StatedPrimary == Agree`.
- `OspreySearchPerfTest`: one tuned search + import (the saved-model search, Add... and both lists are
  `OspreySearchTuningTest`'s), defaulting to `osprey-stellar-subset-v1.zip`; **268 s** on the w8 data
  (`ai/.tmp/sessions/20261027-subset/verify-all.log:1673`); removed from `tc-perftests-skiplist.txt`.
- `regression.ps1` modes 13/14 removed (206 lines, the matrix entry and the two html rows); `-Dataset Stellar`
  PASSED after (`verify-all.log:1738-1754`).
- `build_subset.py --perf-zip`. Perf zip built: `E:\test\osprey-runs\perf-zip\osprey-stellar-subset-v1.zip`,
  87,264,860 bytes, SHA-256 f9fd2d9f6e2b9dc6ee8786de8c47477ee2ff567cf456c66893d425302a267f9f.

**Blocked: the Panorama upload.** PUT to `MacCoss/software/@files/perftests` returns 502 from the proxy; the listing
says this machine's key has `canUpload: False` (Reader). Needs an Editor key in `.netrc` or Brendan's upload.

**Git zips:** a Skyline test cannot read Osprey's zip - SkylineTester's zip installer (what SkylineNightly runs)
collects test zips from the Skyline tree only (`SkylineTester/CreateZipInstallerWindow.cs:465-481`) - so both
`StellarSubset.zip` and `OspreySearchTest.zip` are regenerated from one build; `CarafeModelBuildLibraryTest.zip` is deleted.

**Osprey defect found by the larger subset (fixed on this branch, Brendan's call).** On w2, `TestSubsetLibraryDecoysAndReports`
reported 63 (floor 100) though 1,356 passed run level; the old subset kept 169 of 390. Root cause (investigation scratch in
`E:\test\osprey-runs\libdecoy-investigation\`, status `ai/.tmp/agent-libdecoy-status.md`): Stage 6 re-scoring of override
peaks kept the scan nearest the consensus apex RT (`PeakDataExtractor.cs` override branch skipped the ref-XIC max re-pick,
to match Rust `pipeline.rs` ~9522), so some re-scored rows had peak_apex = 0 with a normal peak_area - interior zero-apex
rows exist only in `*.scores-reconciled.parquet` (19 of 24, 21 decoys), never in the first-pass parquets (all at the end
boundary). The w2 first-pass SVM weights peak_apex about -1.6, so those decoys scored ~+14 and every protein-stratum
pass-2 q landed at 2.26%. Fix: override peaks get the same apex re-pick (ref-XIC max within the override bounds) in C# and
Rust. All 645 Osprey tests pass on w2 with it (`candidate-zip-fix.log:703`). Rust branch `override-apex-from-ref-xic`
(ef86cd0, `C:\proj\osprey`, cloned today): fmt + clippy -D warnings + all tests green (`build-rust.log`). Cross-impl
end-to-end Stellar 3-file: PASS at 1e-9, 32,705 precursors both sides (`crossimpl-Stellar.log`). Goldens regenerating
(`regression.ps1 -Dataset All -CreateGolden`, `regression-golden.log`). This machine needed rustup (1.99.1) and vcpkg
openblas/openssl installed (`setup-rust.log`).

**Final verification (2026-10-28 afternoon, `ai/.tmp/sessions/20261027-subset/final-verify.log`).** Cross-impl Astral 3-file
PASS at 1e-9, 118,292 both sides (`crossimpl-Astral.log`). Goldens remade (`regression-golden.log`): Stellar 32,082 ->
32,705, StellarLibDecoy 31,076 -> 31,215, StellarGenDecoyEntrap 32,287 -> 32,174, Astral 118,314 -> 118,292.
`regression-parallel.ps1 -Dataset All` vs the new goldens: PASSED, every mode on every dataset, entrapment FDR sanity
bounds (mode 1b) included. With the FINAL zips in the tree (`E:\test\osprey-runs\final-zips`, from the preset alone;
README.txt is the only difference from the tested candidate): Osprey 644 passed, 1 skipped (the build-stamp test,
inconclusive under OSPREY_VERSION_OVERRIDE left set by regression-parallel), 0 failed; TestBuildLibraryCarafeWizard 103 s,
TestOspreySearchTuning 142 s, TestOspreySearch 38 s, TestOspreySearchPerf 242 s downloading the Panorama zip (Brendan
uploaded it; size and SHA-256 verified by an anonymous download). maccoss/osprey PR #74 (Rust apex change). pwiz commit
126d2183eb; /code-review medium running before the PR.
