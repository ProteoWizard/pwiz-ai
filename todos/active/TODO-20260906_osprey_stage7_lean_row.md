# TODO-20260906_osprey_stage7_lean_row.md - Stage 7 (SecondPassFDR) holds ~274 B objects where 88 B of row would serve

**Module**: `osprey`
**Status**: Not started - branch created, no commits yet
**Branch**: `Skyline/work/20260906_osprey_stage7_lean_row` in `C:\proj\pwiz-work1`,
cut from `c4921f3d6c` (master with #4633 merged). Local only - not pushed, no PR yet.
**Predecessor**: `todos/completed/TODO-20260901_osprey_stage5_reload_materialization.md`,
merged as [#4633](https://github.com/ProteoWizard/pwiz/pull/4633) / `c4921f3d6c` on 2026-09-06.

This is the work the predecessor was opened to reach. That TODO grew to cover everything that
had to be true FIRST - per-phase artifact durability, bounded Stage 6 planning, the
`--model-diagnostics` render, and getting the gate green and affordable again - and it has now
shipped. **Detail lives in the predecessor; this file carries only what is still open.** Do not
duplicate its sections here - cite them.

## The goal

Carry a **446-file analysis to completion with bounded memory** on a 63.7 GB box, and ideally
scale to **1000 runs** on the same hardware.

## THE ACCEPTANCE CRITERION (developer, 2026-09-02) - carried forward verbatim

> *"I would like to see both FDR tasks lower memory and SecondPass lower than FirstPass, because
> it is dealing with a much smaller bounded set of entries."*

Box-independent, and cannot be satisfied by adding RAM:

* FirstPassFDR processes the full PRE-compaction pool - 1,342,686,095 entries at 446 runs.
* SecondPassFDR processes only the survivors - 288,920,200. About **4.6x smaller**, and bounded.
* **A stage doing strictly less work must not peak higher.**

**The pass/fail test on any future perfviz plot: if Stage 7 is the tallest region, the goal is
not met even when the run completes.** The 257-file plot of 2026-08-24 shows the inversion -
SecondPassFDR ~70 GB against FirstPassFDR's ~55 GB - and that inversion IS the diagnosis:
Stage 7's cost is its REPRESENTATION, not its workload.

## What is still open

| # | item | where the analysis lives (predecessor TODO) |
|---|---|---|
| 1 | Stage 7 holds ~274 B `FdrEntry` objects rebuilt from parquet where 88 B of fixed-width row would serve | "THE STAGE 7 HANDOFF SHOULD BE A LEAN SIDECAR, NOT A LEAN STRUCT"; "The three-axis Stage 7 plan"; "THE STAGE 7 SIDECAR READ, and two corrections to the three-axis plan" |
| 2 | Measured cost to beat: **78.3 GB committed, ~240 MB/file at 446** | "STAGE 7 AT 446 FILES: 78.3 GB COMMITTED, ~240 MB/FILE (measured 2026-09-04)" |
| 3 | **Coupling 3** - pass-2 diagnostics read the whole-run survivor pool. The only one of the four memory couplings still open; it belongs with this work | predecessor's coupling table |
| 4 | Where the lean row does and does not apply | "Where the lean row does and does not apply to this work" |

## What the predecessor cleared out of the way

Recorded so this work does not re-litigate settled ground:

* **Per-phase durability**: model at training, protein-compact stratum at protein FDR, per-file
  `.1st-pass.fdr_scores.bin` in pass 1. A run interrupted after training re-enters at the
  compaction gate instead of repeating the score passes.
* **Stage 6 planning is bounded**: two per-file passes over the survivor loader instead of an
  all-files buffer. 30.89 -> 12.91 GB peak managed at 86 files, compaction boundary identical.
* **`--model-diagnostics` no longer pins the all-runs hydrate.** This was a stated MEMORY
  prerequisite for the lean row, not just a correctness one - it is now a render over retained
  per-pass products, verified to fold identically from the live score-pass sink and from the
  on-disk sidecars at 446 runs (exact match, 18,821 payload leaves).
* **Coupling 4 (peak co-assignment) is CLOSED as a non-issue** - characterised as a time term,
  not an O(runs) memory term. Do not re-open it as a memory item.
* **The gate is green and affordable**: `-Dataset All` is 1:06 on MacCoss TeamCity Agent 1 under
  the two-lane runner, with modes 8 and 9 now running on every dataset.

## CORRECTION 2026-09-06: the handoff names the wrong bed

The handoff points at `chs446-mdiag-coldfpfdr`, whose first pass is done but which stops
short of PerFileRescoring - reaching Stage 7 from it means running Stage 6 rescore first.
**Use `chs-446files-libdecoy-r1.0-protein-compact-stages567` instead.** It already carries a
complete 446-file PerFileRescoring (`.scores-reconciled.parquet`, `.2nd-pass.fdr_scores.bin`,
`.2nd-pass.fdr_decoys.bin`) plus both analysis-wide sidecars, and it is the very directory the
78.3 GB before-curve was measured in.

```powershell
.\Run-Chs.ps1 -DecoyMode libdecoy -Ratio 1.0 -Pass2Mode protein-compact -Threads 30 `
  -Task SecondPassFDR -Tag '-s7base' -NoModelDiagnostics -Exe <snapshot>\Osprey.exe `
  -LibraryDir D:\test\osprey-runs\sea-ad\lib\target+decoy+entrapment-20260817 `
  -LinkFrom D:\test\osprey-runs\chs-seer\runs\chs-446files-libdecoy-r1.0-protein-compact-stages567
```

That reaches `[TASK] SecondPassFDR:starting` in **under a minute**, and the runner pins
`OSPREY_VERSION_OVERRIDE=26.1.1.243` itself from the source stamps - no manual override.

Three things that are easy to get wrong here:

* **`-Task SecondPassFDR` is not merely faster, it is the only variant that reuses the work.**
  `-LinkFrom` links the stages strictly BEFORE `-Task`; with no `-Task` the runner links 1784
  files (`for stages before FirstPassFDR`, i.e. PerFileScoring only) and re-runs FirstPassFDR
  and PerFileRescoring. With it, 6690 link and 0 are missing.
* **`-NoModelDiagnostics` is required for the comparison.** The 78.3 GB baseline run records
  `mdiag=False` in its START line. Measuring with diagnostics on would compare two things.
  A separate mdiag-on leg is what measures coupling 3, and costs the same minute to set up.
* **`-Tag` is appended raw** (`OspreyDatasetRun.psm1:436`), so it must carry its own leading
  `-` or the run directory comes out as `...protein-compacts7base`.

**#4633 cannot invalidate the linked artifacts** - checked, not assumed. `PerFileRescoreTask`'s
validity key is `base + fdrsidecar + reconciliation + expagg + pass2 + trainpick + stage6stream
+ libfrag`, and `SearchIdentity.cs` (which computes the base and reconciliation hashes) is not
among #4633's 49 files; `FdrScoresSidecar.FormatVersion` is still 6; the `TaskValiditySidecar`
change is an additive `TryReadValidityKey` for `--task ModelDiagnostics`; and the only
`OspreyEnvironment` addition is `OSPREY_DROP_BETWEEN_TASKS`, default off and in no key.

## Before starting

* Read `ai/docs/osprey-development-guide.md` on the two-lane gate - `-Dataset All` no longer
  costs double a Stellar-only run, so run the full gate rather than Stellar as a stand-in.
* The per-dataset coverage matrix and the reason for each asymmetry are in that same guide,
  beside the dataset table. Astral omits mode 2 deliberately; that is budgeted, not an oversight.

**Next session handoff**: For detailed startup protocol - including the 446-file bed whose
entire first pass is already done, the two settings required to reuse it, and what to measure
- read `ai/.tmp/handoff-20260906_osprey_stage7_lean_row.md` before starting work.
