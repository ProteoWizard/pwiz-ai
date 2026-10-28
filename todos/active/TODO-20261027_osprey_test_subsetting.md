# TODO-osprey_test_subsetting.md

## Branch Information
- **Branch**: `Skyline/work/20261027_osprey_test_subsetting` (from `master` at b68aa96d5f, after #4917
  and #4925 merged), checkout `C:\proj\pwiz`
- **Created**: 2026-10-27
- **Status**: In progress
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
