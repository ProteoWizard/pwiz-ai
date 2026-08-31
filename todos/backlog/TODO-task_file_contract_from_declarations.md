# TODO-task_file_contract_from_declarations.md

## Branch Information (Future)
- **Branch**: Not yet created - will be `Skyline/work/YYYYMMDD_task_file_contract`
- **Module**: `osprey`
- **Objective**: Make each Osprey task's file contract a DECLARATION the pipeline owns, print it
  with `--help-files`, and make both test harnesses stage exactly that and nothing more.

## Background

Osprey's HPC story is that a task runs on a node holding only the files that task needs. Nothing
enforces it. The tasks do declare `Inputs(ctx)` / `Outputs(ctx)`, but:

* **nothing consumes the declarations**, so they drift. Measured 2026-08-31 during issue #4486:
  `SecondPassFdrTask` declared NONE of the per-file `.1st-pass.fdr_scores.bin` files while
  READING all of them on every run. An undeclared dependency is worse than a wrongly declared
  one - nobody can check it.
* **the harnesses stage generously.** `regression.ps1`'s HPC chain copied whatever seemed useful,
  and `Run-SeaAd.ps1 -LinkFrom` hard-links the cumulative artifact set of every earlier stage. A
  task can therefore read a file it was never promised and the gate stays green.

That is not hypothetical. The #4486 relocation was believed complete for days while Stage 7 still
read every 1st-pass sidecar; it only surfaced when the chain stopped STAGING them. And two
82-file Stage-7 A/B measurements were taken where `-LinkFrom` silently omitted the worker's
2nd-pass artifacts, so both arms ran the same fallback path and the comparison showed nothing.

**The fix is one source of truth**: the task declares its contract, `--help-files` prints it, and
both harnesses stage from it.

## The contract, as reviewed (Brendan, 2026-08-31)

`<own>` = this worker's own stem only. `<each>` = one per input file. *Italics* = analysis-wide.

| Task | Inputs | Outputs |
|---|---|---|
| **PerFileScoring** (per-file) | library (+ manifest, `.libcache`)<br>`<own>.mzML` / `<own>.spectra.bin` | `<own>.scores.parquet`<br>`<own>.calibration.json`<br>`<own>.spectra.bin` (if not cached) |
| **FirstPassFDR** (join) | library<br>`<each>.scores.parquet`<br>`<each>.calibration.json`<br>no data files | `<each>.1st-pass.fdr_scores.bin`<br>`<each>.reconciliation.json`<br>`<each>.1st-pass.model.json`<br>*`output.1st-pass.fdr_experiment.bin`* |
| **PerFileRescoring** (per-file) | library<br>`<own>.spectra.bin`<br>`<own>.scores.parquet`<br>`<own>.calibration.json`<br>`<own>.1st-pass.fdr_scores.bin`<br>`<own>.reconciliation.json`<br>`<own>.1st-pass.model.json`<br>*`output.1st-pass.fdr_experiment.bin`* | `<own>.scores-reconciled.parquet`<br>`<own>.2nd-pass.fdr_scores.bin`<br>`<own>.2nd-pass.fdr_decoys.bin` |
| **SecondPassFDR** (join) | library<br>`<each>.scores-reconciled.parquet`<br>`<each>.2nd-pass.fdr_scores.bin`<br>`<each>.2nd-pass.fdr_decoys.bin`<br>`<each>.1st-pass.model.json`<br>*`output.1st-pass.fdr_experiment.bin`* | `output.blib`<br>*`output.2nd-pass.fdr_experiment.bin`* |

Every output carries a `.<TaskName>.osprey.task` validity stamp that travels with the file.

## Tasks

### 1. Let a task say whether it is per-file

The declarations cannot currently express `<own>` vs `<each>`: per-file and join tasks BOTH
enumerate `ctx.Config.InputFiles` and yield one path each, so `PerFileRescoreTask.Outputs` is
indistinguishable in shape from `SecondPassFdrTask.Inputs`. That is the single distinction HPC
staging turns on.

```csharp
public virtual bool IsPerFile => false;   // OspreyTask
```

overridden `true` by `PerFileScoringTask` and `PerFileRescoreTask`. Four lines, and it serves the
printer AND both harnesses, so none of them maintains its own list.

### 2. `--help-files`

Print the table above, DERIVED, never hard-coded. Feasible as-is: no task's `Inputs`/`Outputs`
touches `ctx.Get` / `Demand` / `TryGet`, so none needs a live pipeline - they read `ctx.Config`
and the environment only. So:

* build a throwaway `OspreyConfig` with two synthetic stems and an output blib
* call `Inputs(ctx)` / `Outputs(ctx)` on each declaring task
  (`PerFileScoringTask`, `FirstPassFdrTask`, `PerFileRescoreTask`, `SecondPassFdrTask`,
  `SpectraCacheTask`)
* generalise the returned paths by substituting the synthetic stems back to `<own>` / `<each>`
  per `IsPerFile`, and anything with no stem to the analysis-wide form

**It must name the mode it is describing.** `Inputs` branches on `Pass2VerifyWorker`,
`Pass2ProteinCompact` and `Pass2TransferCompete`, so the contract genuinely differs between arms
- printing it per environment is the feature, printing it without saying which is a trap.

**It prints what is DECLARED, not what is READ**, and that is the point: the moment the table has
a reader, a wrong declaration becomes visible. The `.1st-pass.fdr_scores.bin` omission above
would have been obvious on day one.

### 3. Stage from the declarations, in BOTH harnesses

* **`regression.ps1`** - the HPC chain already stages close to this by hand (and already withholds
  the 1st-pass sidecars from phase 4, which is what proved the #4486 contract). Replace the
  hand-maintained copy lists with the declared inputs.
* **`Run-SeaAd.ps1 -LinkFrom`** (`ai/scripts/Osprey/Common/OspreyDatasetRun.psm1`) - replace the
  cumulative `$STAGE_ARTIFACTS` walk, which links every earlier stage's artifacts, with the
  target task's declared INPUTS. Its current shape cannot express `<own>` vs `<each>` at all.

**A missing declared input must fail at staging time**, not degrade. The 2026-08-31 measurements
failed precisely because a silent omission became a quiet fallback to a slower correct path.

### 4. Audit the declarations against reality

Open-ended, and the real work. Known suspects on SecondPassFDR, both staged today with no proof
they are read on the default path:

* `<each>.calibration.json`
* `<each>.reconciliation.json`

Withholding each and running mode 3 settles it in one run apiece - the same technique that found
the 1st-pass dependency.

## Why (the payoff)

* An undeclared or over-generous dependency becomes a **build/stage failure**, not a green run.
* `--help-files` gives a reviewer the HPC contract without reading code, per mode.
* One declaration feeds the printer, `regression.ps1` and `-LinkFrom`, so they cannot disagree.

## Related

* Issue #4486 - the relocation whose contract this makes checkable
* `TODO-20260826_osprey_stage7_stream_pool.md` - where the undeclared dependency and the
  `-LinkFrom` omission were found and recorded
* `ai/docs/long-running-jobs-guide.md` - the harness lessons from the same sessions

## Known wrinkles to resolve in design

* **0-byte `<stem>.mzML` stubs** are staged for every task purely for path derivation. An
  orchestrator would stage nothing there; phase 4's is the least defensible since it has no data
  to derive from. Either the contract admits them explicitly or paths derive from the parquet.
* **`<stem>.1st-pass.model.json` is per-file in NAME, analysis-wide in CONTENT.** Measured: all 82
  copies byte-identical, 8.9 MB each, 730 MB duplicated at 82 files (~2.3 GB at 257). 6.3 MB of
  each is `StratumBaseIds`; the frozen model is ~2 KB. Keep the model per-file - DIA-NN computes
  per-file models and that flexibility is wanted - but the stratum is analysis-wide by definition
  (#4581) and is what is being copied. Splitting them keeps the flexibility AND removes the
  duplication; they only look in tension because they share a file.
