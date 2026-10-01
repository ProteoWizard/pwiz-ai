# TODO: SILENT DATA LOSS - pass 2 drops runs; --parallel-files 4 collapsed the blib 119x

## Branch Information
- **Branch**: `Skyline/work/20260926_osprey_pass2_empty_run_gate` (the GATE only, not the
  fix; worktree `D:\Users\brendanx\proj\pwiz-gate`, off `5246fa6b2f`). The defect itself was
  found by measurement, not introduced by a branch.
- **Base**: `Skyline/work/20260612_net8_port` (PR #4619)
- **Created**: 2026-09-26
- **Status**: **ROOT CAUSE FOUND AND ALREADY FIXED UPSTREAM** - the `FrozenModelScorer`
  shared scratch buffer, fixed 2026-09-28 in `fcd59201a3` (#4727 / #4706), two days after
  the runs below. See the RESOLVED section at the end; read it before anything above it,
  which is the investigation as it stood before the cause was known. Remaining action is
  verification on the fixed tip, not a fix. The gate branch is recommended for DROPPING.
- **Module**: `osprey`
- **Severity**: was **HIGH** (wrong results, silently, exit code 0) - now fixed upstream

## Summary

Two 82-file SEA-AD runs from the **same exe snapshot**
(`_bin\26.1.1.268-net10port-par3-5bd83dae8b`, Osprey `26.1.1.268 (5bd83dae8b)`), same
library, same arm, same machine, differing **only** in `--parallel-files` (3 vs 4):

| artifact | par3 | par4 |
|---|---|---|
| `out.blib` | **317,149,184 bytes** | **2,662,400 bytes** |
| `out.protein_groups.tsv` rows | 6,349 | **487** |
| `out.stats.tsv` Experiment row (prec, pept, prot) | (54,660, 50,051, 6,349) | **(491, 487, 487)** |
| log: `Detected N unique peptides at 1.0% experiment FDR` | 50,051 | **487** |
| FDRBench pass 2 @ q<=0.010: N_T / combined FDP | 54,367 / **1.072%** | 377 / **46.440%** |

**Both runs exited 0 and logged `Analysis complete`. Neither logged a warning, an error, or
anything indicating loss.** par4's deliverable is effectively empty and nothing says so.

## Pass 1 is bit-identical - the divergence is entirely in pass 2

Everything up to and including the inputs of the experiment-scope pass-2 step is
**identical to the digit** across the two runs:

* scored entries `353,085,961` (both)
* `First-pass Percolator results: 2090077 targets, 20783 decoys pass 1.0% FDR` (both)
* `Total: 2090077 precursors pass run-level FDR across all files` (both)
* `protein-compact: 6812 proteins with >=2 detected peptides -> stratum of 734043
  base_ids (from 66158 detected peptides)` (both)
* `[FDR] experiment-q floors: folded 1397053 entry_id and 1055644 peptide floor(s)` (both)
* `protein-compact: mapped recomputed q onto 87919332 reported survivors` (both)
* `Collected scores for 1055644 unique peptides` (both)
* `pass1_fdp.py` pass-1 experiment: `q=0.0100 n=45943 combinedFDP=0.7460%
  pairedFDP=0.7221%`, matched-true-FDP counts 44,609 / 45,943 / 48,166 - **identical in
  both runs**

Then, from identical inputs:

```
par3:  Detected 50051 unique peptides at 1.0% experiment FDR (Precursor) -> 6349 protein groups
par4:  Detected   487 unique peptides at 1.0% experiment FDR (Precursor) ->  487 protein groups
```

Note par4's protein-group count EQUALS its peptide count (487 == 487), which looks like a
degenerate cascade rather than a plausible biological result.

## A second, related symptom: one run is dropped per run

> **Read the CORRECTION section below before this one.** This section originally read
> "nondeterministically", and that is REFUTED: Stage 7 reproduces each outcome exactly at
> `--parallel-files 1`. The varying identity of the dropped file comes from upstream Stage 6
> output differing, not from nondeterminism in Stage 7.

`out.stats.tsv` is per-file. Of 82 file rows, **78 are identical** between par3 and par4.
The four that differ:

| file | par3 | par4 |
|---|---|---|
| `...SEA-AD-0047_7049_E03_065` | (24250, 22678, 4189) | **(0, 0, 0)** |
| `...SEA-AD-0066_7170_F12_087` | **(0, 0, 0)** | (29693, 27659, 4722) |
| `...SEA-AD-0014_7038_B03_020` | (38669, 36047, 5626) | (38929, 36271, 5620) |
| `...SEA-AD-0028_7240_C07_037` | (36604, 34067, 5331) | (36604, 34118, 5467) |

**Each run silently reports ZERO pass-2 output for exactly one file, and it is a DIFFERENT
file in each run.** That is a nondeterminism signature, not a data property.

**The dropped file was fully processed.** For both, the log shows normal completion
through Stage 6 - e.g. par3/0066: `Scored 4453840 entries`, `22002 precursors at 1.0%
run-level FDR`, `Wrote reconciliation.json`, `Wrote reconciled parquet ... 1094002 rows`.

**And its second-pass artifacts exist and are byte-identical in size across the two runs:**

| file | `.2nd-pass.fdr_scores.bin` | `.2nd-pass.fdr_decoys.bin` |
|---|---|---|
| `...0066_7170_F12_087` | 39,384,104 (both runs) | 6,403,256 (both runs) |
| `...0047_7049_E03_065` | 38,896,736 (both runs) | 6,325,820 (both runs) |

So the per-file second-pass computation is correct and complete in both runs. **The loss is
purely in the roll-up that consumes those sidecars.**

## What this means

* **par3 is affected too.** Last night's run lost file 0066 entirely. I did not catch it
  because I validated the pass-1 anchors and perfviz, and pass 1 is unaffected. The par3
  experiment-scope output still looks sane (6,349 protein groups, 317 MB blib), so the
  severity varies; the defect does not.
* **The anchors do not cover this.** Both recorded correctness anchors (scored-entry count
  and pass-1 experiment FDP) pass perfectly on a run whose blib is 119x too small. Pass-2
  output needs its own gate.
* This is plausibly the same class of thing behind the unexplained **SecondPassFDR wall
  time** (1,663 s par3 / 1,575 s par4 vs a 662.5 s reference), but that is a guess, not
  established.

## Next steps

1. **Find the roll-up that enumerates per-file second-pass sidecars in Stage 7** and check
   it for a race - a concurrent collection, a shared enumerator, or a file-listing taken
   while writes are still landing. The per-file sidecars are correct, so the fault is
   between reading them and aggregating.
2. **Reproduce cheaply**: `--task SecondPassFDR -LinkFrom <either run>` reruns only Stage 7
   (~26-28 min) against fixed, known-good inputs. Repeat at `--parallel-files` 1/2/3/4 and
   see whether the dropped file tracks concurrency. Compare LinkFrom-to-LinkFrom only (a
   LinkFrom stage carries a systematic +10.1% vs a full run - see the par3 TODO).
3. **Add a gate**: assert every input file appears in `out.stats.tsv` with a non-zero row,
   and that the Experiment row is consistent with the per-file rows. A run that drops a
   file must fail, not exit 0. Per the SEA-AD README's "assert the expected result COUNT"
   rule, 82 files in must mean 82 non-zero rows out.
4. Re-examine whether any previously recorded SEA-AD/CHS result was produced by a run that
   silently dropped a file. **`out.stats.tsv` is the cheap check and it is already on disk
   for past runs.**

## Provenance

* par3: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactnet10port-par3`
  (2026-09-25 21:58:04 -> 2026-09-26 02:57:27, 4h59m23s)
* par4: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactnet10port-par4`
  (2026-09-26 09:22:46 -> 13:48:16, 4h25m30s)
* Both from `_bin\26.1.1.268-net10port-par3-5bd83dae8b`.

## CORRECTION 2026-09-26 evening: Stage 7 is DETERMINISTIC; it is not a race

Reran **Stage 7 only** (`--task SecondPassFDR -LinkFrom <par3> --parallel-files 1`,
`-NoModelDiagnostics`) against par3's linked inputs. Result:

* **All 83 rows of `out.stats.tsv` byte-identical to par3** - zero differing rows.
* **The SAME file is still dropped**: `Astral-...SEA-AD-0066_7170_F12_087` -> (0, 0, 0).
* `out.blib` 317,149,184 bytes and 6,349 protein groups - identical to par3.
* `Detected 50051 unique peptides at 1.0% experiment FDR` - identical to par3.

**With NO file concurrency at all, the same file is still dropped.** So the earlier
hypothesis in this TODO - a consumer enumerating the survivor pool while `StreamFiles`
concurrently materializes-and-drops - is **WRONG**. Stage 7 is a deterministic function of
its Stage 1-6 inputs.

### What that means

Two SEPARATE defects, not one:

1. **Upstream determinism violation.** par3 and par4 drop DIFFERENT files only because
   their Stage 1-6 outputs differ. `--parallel-files` changes `PerFileRescoring` output -
   independently visible as two files with differing per-file counts
   (`...0014_B03_020`, `...0028_C07_037`) and as PerFileRescoring being 3.0% SLOWER at par4
   (4,253.2 s vs 4,127.9 s). Per-file output must not depend on how many files run at once.
2. **Stage 7 zeroes exactly ONE file, deterministically, data-dependently.** Always exactly
   one. That shape - "exactly one, every time, identity depends on the input" - reads like
   an off-by-one or a last-file-dropped-and-never-re-materialized bug, not corruption and
   not a race.

### Still to establish

* Whether par4's experiment-scope COLLAPSE (487 peptides vs 50,051) also reproduces
  deterministically from par4's inputs at N=1. **Running now**
  (`sp2sweep-from4-n1`). If it collapses, the collapse is caused by par4's upstream data
  and Stage 7 concurrency is exonerated entirely; if it does not, Stage 7 concurrency is
  implicated for the collapse even though it is not for the dropped file.
* Which file Stage 7 zeroes and why. `StreamFiles` clears + trims each file's list after
  the consumer's body returns, and `Pass2FdrSidecar.cs:2155` calls `DropFile(fileKey)` on a
  separate "one named file" path driven by the FDR layer's own order. Two independent
  droppers over one shared buffer is where to look, but note the `_streamed` guard is set
  BEFORE the yield specifically to prevent the silent-empty-pool failure, so the fault is
  more likely a file dropped on the named path and not re-materialized for a later
  `StreamFiles` pass.

### Measurement note

Stage 7 at N=1 without model diagnostics took **1,093.9 s**. Not comparable to the
full-run 1,663.0 s: mdiag is off (removing ~308 s of folding and co-assignment) and a
LinkFrom stage carries a systematic +10.1% bias. Compare LinkFrom-to-LinkFrom only.

## 2026-09-26 evening: the GATE is written, verified and committed locally

Commit `695ac9e779` on `Skyline/work/20260926_osprey_pass2_empty_run_gate`, based on the
port-branch tip `5246fa6b2f` (our measurement pin `5bd83dae8b` plus two Skyline commits
and zero Osprey commits, so the analysis above still applies to the tip).

**This gates the SYMPTOM. It does not fix the cause**, which is upstream in Stage 6.

### What it does

| file | change |
|---|---|
| `Osprey.Core/OspreyEnvironment.cs` | `OSPREY_ALLOW_EMPTY_RUNS` override |
| `Osprey.Tasks/OspreyReportWriter.cs` | `WriteSummary` collects zero-precursor runs; `WriteReports` returns them; `TryWriteReport` returns success so a half-written report cannot read as clean |
| `Osprey.Tasks/SecondPassFdrTask.cs` | `AssertNoEmptyRuns` + pure `internal static EmptyRunGateError` |
| `Osprey.Test/EmptyRunGateTest.cs` | new, one consolidated `[TestMethod]` |

Design follows `ResidentPoolGuardTest`'s convention rather than inventing one: the guard is
a **pure function returning an error string**, and the CALLER decides warn-vs-throw. That
is why the policy is testable without a pipeline.

Three decisions worth re-reading at review time:

* **null means UNKNOWN, not "none".** Summary report off, no output stem, or a failed write
  -> the gate logs that it did not run. Otherwise a config with reports disabled would be
  indistinguishable from a run that passed the gate.
* **The override logs the identical text it would have failed with**, so a log read later
  says the same thing either way; only the opt-in differs.
* **Known coverage gap, taken deliberately**: the gate rides the summary-report path, so
  `-DiagnosticsOnly` and both-reports-off are not covered (it says so when skipped).
  Covering them needs a dedicated stream over all 82 files, i.e. a full re-read, and that
  did not seem worth taking unprompted.

### Verification

| check | result |
|---|---|
| `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` | build OK, **inspection zero warnings**, **599/599 tests** (was 598) |
| Real data: Stage 7 only, `-LinkFrom <par3>`, `--parallel-files 1`, mdiag off | **gate fired** |

```
[ERROR] Pipeline failed: System.InvalidOperationException: 1 of 82 searched file(s)
contributed NO passing precursors to the second-pass result:
Astral-SEA-AD_2-MTG-May2026_SEA-AD-0066_7170_F12_087. Their per-file second-pass sidecars
are on disk, so this is a lost run rather than a file with no identifications. Set
OSPREY_ALLOW_EMPTY_RUNS=1 if these files genuinely have none.
```

`Osprey exited 1 after 00:09:36`, `runner exit code: 1` - the failure reaches the exit
code, so a chained job cannot mistake it for success. The identical input set previously
produced exit 0 and a complete-looking log.

Log: `ai/.tmp/sessions/20260926-e07c35eb/gate-verify.log`
Run dir: `D:\Users\brendanx\test\osprey-runs\sea-ad\runs\seaad-82files-libdecoy-r1.0-protein-compactgateverify`
Verification exe snapshot: `D:\Users\brendanx\test\osprey-runs\_bin\gate-verify`

### Not done

* NOT pushed, no PR. `/code-review max` was run on the branch first, per the review-chain
  rule that reviewing before `gh pr create` avoids spending Copilot's automatic pass on
  code about to be rewritten.
* The Stage 6 determinism defect - the actual cause - is untouched.

## RESOLVED 2026-09-30: root cause was the FrozenModelScorer shared scratch buffer

**Fixed upstream two days after these runs**, in `fcd59201a3` (#4727, 2026-09-28):
"Fixed the `--parallel-files` data race in FrozenModelScorer that mixed files'
second-pass scores (#4706)". Found by the new in-process `SubsetPipelineTest`, not by
this investigation.

### The mechanism

`FrozenModelScorer` held ONE standardization buffer, `private readonly double[] _scratch`,
and its doc comment asserted "NOT thread-safe ... Every caller is serial by design". That
claim was false: **Stage 6's per-file second-pass workers of a `--parallel-files` run share
one scorer**, so concurrent `Score()` calls scored one file's entries with another file's
features. The fix makes it `ThreadLocal<double[]>`; the arithmetic per call is unchanged,
so scores stay deterministic whatever the thread.

Present at our measurement pin `5bd83dae8b` (verified), absent after `fcd59201a3`.

### It explains every observation in this TODO

| observation | explanation |
|---|---|
| Stage 6 output depends on `--parallel-files` | the race IS in Stage 6 second-pass scoring |
| one file contributes zero passing precursors | its entries were scored against another file's features, so all fail FDR |
| its `.2nd-pass.fdr_scores.bin` is present and byte-identical in size | the scorer returned A score for every entry - the file is complete, just wrong |
| Stage 7 deterministic; N=1 reproduced par3 AND par4 exactly | Stage 7 was never at fault; it faithfully processed corrupted Stage 6 output |
| a DIFFERENT file each run | race timing |
| par4 much worse than par3 (487 vs 50,051 peptides) | more concurrent workers sharing one scorer - more interleaving |
| exit 0, no warning, no error | no error path is involved anywhere |

### Corrections to earlier sections of this TODO

* The "CORRECTION" section's conclusion - "the bug is entirely upstream in Stage 6" - was
  RIGHT. The mechanism simply was not visible from Stage 7.
* The `/code-review max` finding that named `Pass2FdrSidecar.OverlayPass2SidecarOntoFile`'s
  discarded `bool` as "Root cause of the defect this commit detects" was **wrong**. It read
  as authoritative and was queued as the next thing to chase. It may still be a genuine
  robustness gap, but it is not this defect.

### What the par3 / par4 measurements are still good for

* **Valid**: PerFileScoring par4 = 1.33x par3 (first-pass scoring, untouched by this race);
  FirstPassFDR flat; both pass-1 correctness anchors; the ~1% full-run and +10.1% LinkFrom
  noise floors; perfviz memory; the D: throughput curve.
* **INVALID**: the PerFileRescoring comparison (par4 "3% slower"), both SecondPassFDR wall
  times, and every pass-2 output - blib, protein groups, pass-2 FDP, `out.stats.tsv`.
  **par3 is corrupted too, not only par4.**

### Consequence for the empty-run gate branch

`Skyline/work/20260926_osprey_pass2_empty_run_gate` (commit `695ac9e779`, never pushed)
was a detector for this defect. With the defect fixed, and with `/code-review max` having
found the gate defective on its own terms (measures RUN-level FDR while the blib it
protects gates on EXPERIMENT-level; blind to a file ABSENT from the pool; error message
asserts a diagnosis the code never checks and uses the banned word "sidecar"),
**recommendation: drop the branch.** If a backstop gate is wanted later, build it fresh
against the experiment-level predicate rather than rebasing this one - upstream has since
moved user-facing text to RESX (#4721) and replaced `Action<string> logInfo` with
`IOspreyLog` / `LogTag.COUNT` (#4718), so the old shape does not apply anyway.
