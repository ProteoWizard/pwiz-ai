# TODO (backlog): Osprey console/logging parity cleanup

**Type:** console/logging only — NO correctness or output impact. Osprey's numeric
output (blib, q-values) is byte-parity-gated against Rust (`regression.ps1 -Dataset
Stellar`); these items are about what the *console* prints, which is not gated and has
drifted from the Rust console. Found during the 82-file Astral fit test (2026-07-08).

## 1. First-pass FDR: report EXPERIMENT-level counts, not a run-level sum

**Where:** `pwiz_tools/Osprey/Osprey.Tasks/FirstJoinTask.cs:574` and `:1517` (legacy +
projection paths both emit it).

**Current C# (misleading):**
```
Total: 1935337 precursors pass run-level FDR across all files
```
This is a **sum of per-file run-level counts** — a precursor detected in K files is
counted K times, so on the 82-file Astral set it reads as ~1.9M, far above the true
unique count. Rust prints no such run-level sum.

**What Rust prints** (`osprey-fdr/src/percolator.rs` `compute_fdr_from_stubs`, ~line 392):
```
=== Experiment-level results at 1% FDR (from <N> total entries) ===
  <N> precursors passing precursor-level FDR
  <N> peptides passing peptide-level FDR
```
i.e. the **experiment-level** unique count after cross-file competition — the number
that actually means something.

**Fix:** replace (or clearly relabel) the run-level-sum line with the experiment-level
precursor + peptide counts, **in the pwiz console formatting style** (existing
`ctx.LogInfo` indentation/wording conventions — do NOT literally copy Rust's `===`
banner if it clashes with pwiz output style; match the surrounding Osprey console
format). The experiment-level q-values are already computed (byte-parity holds) — this
is purely surfacing the right number.

**Check before implementing:** whether the experiment-level precursor/peptide counts are
available at the Stage-5 `FirstJoinTask` point in C#, or only after Stage-6
reconciliation (Rust computes both together in `compute_fdr_from_stubs`; the C# port may
split run-level @ Stage 5 vs experiment-level @ Stage 6). Emit the line wherever the
experiment-level counts first exist.

## 2. Percolator progress label reads as the wrong loop nesting

**Where:** the first-pass Percolator progress output (`Osprey.FDR` Percolator training).

**Current C# (reads backwards):**
```
3-fold cross-validation on 300000 training entries (151019 targets)
Percolator iteration 1 of 10 ... 10 of 10
[TIMING] Percolator fold 1/3: 94.0s (8 iterations)
[TIMING] Percolator fold 2/3: 94.3s (9 iterations)
[TIMING] Percolator fold 3/3: 94.3s (10 iterations)
```
The `iteration N of 10` block reads as an outer loop of 10, when the real structure
(identical to Rust) is **3 folds outer (trained in parallel) × up to 10 semi-supervised
iterations inner (early-stopping per fold)**.

**What Rust does:** one shared progress bar of `n_folds * max_iterations` (= 30) steps,
rendered as `{pos}/{len} fold-iterations`.

**Fix:** relabel the C# progress from `iteration N of 10` to something like
`fold-iteration N/30` (or `fold F/3 iteration I/10`) so it reflects folds-outer nesting,
in pwiz console style. Purely cosmetic — the computation is a confirmed match.

## Notes

- Both are non-blocking; no rush. Batch into one small console-cleanup PR when convenient.
- Neither touches the byte-parity path, so a `regression.ps1 -Dataset Stellar` run after
  the change should stay green (console text isn't compared) — but run it anyway since
  the edits are in `FirstJoinTask` / FDR code.
