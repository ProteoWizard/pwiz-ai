# TODO-osprey_model_diagnostics_pass_switch.md -- One top-level [Pass 1][Pass 2] switch for the whole --model-diagnostics page + Reproducibility/yield layout cleanup

## Status
**Backlog (created 2026-07-11).** Raised by Brendan after the pass-2 q-value work
(pwiz #4410, [[project_osprey_pass2_recalibration_inflates_fdr]]) made it obvious that
**almost every plot and table on the `--model-diagnostics` page is really a function of a
chosen pass's q-values / scores**, but the page exposes that choice inconsistently:
only the Model tab (composite score + feature table) and the FDR-calibration tab let you
see Pass 2; everything else is hardcoded to Pass 1. As soon as you want the **Density**
plot for Pass-2 Percolator (interesting precisely because that is where the depleted null
shows up), you can't -- only the composite-score plot offers both.

Thesis: replace the fragmented per-element pass selectors with **one page-level
[Pass 1][Pass 2] switch** (top-right, next to the tabs) that re-sources every
pass-dependent plot and table at once. Each pass carries its own complete set of
q-values and its own reported pool; the page should treat "which pass" as a single global
mode, not a per-card afterthought.

This is a diagnostics-report (Osprey.Tasks.ModelDiagnostics + Osprey.FDR.ModelDiagnostics)
cleanup; it is output-only (no FDR/scoring behavior change) and follows #4377 / #4408 /
#4410. It touches: `Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html`,
`Osprey.Tasks/ModelDiagnostics/ModelDiagnosticsReport.cs`,
`Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs`.

## Current per-element pass sourcing (reviewed 2026-07-11, cited)
Two categories -- both have a Pass-1 form always, and a Pass-2 form *when Pass 2 ran*:

**Structural (score/model-derived; a Pass-2 form exists only if Pass-2 Percolator RETRAINED
-> `modelPass2` present):**
| Element | Tab | Pass-2 data today | Current switch |
|---|---|---|---|
| Feature model table | Model | serialized (`modelPass2.features`) | Pass1/Pass2 (`modelPassSel`) |
| Composite score distribution | Model | serialized (`modelPass2.scores`) | follows model selector (shows both) |
| Per-feature score distributions | Model | serialized (per-pass rows) | follows model selector |
| Score density by class | Density | **computable, NOT wired** (`modelPass2.scores` exists) | none (Pass-1 hardcoded) |
| Null-alignment density ratio | Density | **computable, NOT serialized** (1-line `BuildDensityRatio(modelPass2.Scores)`) | none (Pass-1) |
| Paired decoy-win fraction | Competition | computable, not serialized | none (Pass-1) |

**q-driven (reported-pool q; Pass-2 form = MergeNode post-compaction `RescoredEntries`):**
| Element | Tab | Pass-2 data today | Current switch |
|---|---|---|---|
| FDR calibration (q vs true FDP) | FDR calibration | **serialized** (`fdpViews` = Pass x Scope, up to 4) | view selector (Pass x exp/run) |
| Identification yield | Reproducibility | computable, NOT serialized | exp/per-run only |
| Per-file passing precursors | Summary | computable, NOT serialized (Pass-1 run-q) | none |
| Precursor detections by run | Reproducibility | computable, NOT serialized | exp/per-run |
| Runs-detected histogram | Reproducibility | computable, NOT serialized | exp/per-run |
| Union FDP vs #runs | Reproducibility | computable, NOT serialized | none (both scopes) |

**Pass-independent:** Summary chips/KPIs (`nTarget/nDecoy/npTarget/npDecoy`) are population
counts, NOT q-gated (`ModelDiagnosticsData.cs:524-533`) -- they do not move with the switch
(the per-file passing-precursor table is the only q-gated Summary element, Pass-1 run-q,
`Data.cs:505`).

So: **only FDR-calibration currently serializes a Pass-2 variant of a q-driven plot.** The
Pass-2 pool (`RescoredEntries`) and Pass-2 score population (`modelPass2.scores`) are both
already in hand at `Report.cs WritePass2AndFinalize (:133-170)`; id-yield / per-file /
cross-run / density-ratio / win-fraction just are not built + serialized for Pass 2 yet.

## IMPORTANT design caveat -- "Pass 2" is not monolithic (transfer mode)
With #4410, Pass 2's q can come from two very different places, and the switch must handle both:
- `OSPREY_PASS2_QVALUE=percolator` (retrain): `modelPass2` PRESENT -> Pass-2 has BOTH the
  structural views (model/composite/density) AND the q-driven views (FDR cal/yield/...).
- `OSPREY_PASS2_QVALUE=transfer`: **no retrained model** -> `modelPass2` ABSENT ("pass-2
  model n/a" in the finalize log) BUT the q-driven Pass-2 views (FDR cal, yield, per-file,
  cross-run) DO exist (from the transferred q).
- no 2nd pass: no Pass-2 anything.

So under the top-level Pass-2 mode, the **structural** cards must degrade gracefully
("Pass-2 model n/a -- 2nd pass used confidence transfer, not a retrain") while the
**q-driven** cards still render. The switch should offer Pass 2 whenever EITHER a
`modelPass2` OR a Pass-2 `fdpViews`/rescored pool exists, and per-card fall back to a clear
"n/a for this pass" note rather than silently showing Pass-1 data.

## Deliverables
1. **Top-level [Pass 1][Pass 2] switch** (top-right of the tab bar). Global mode; drives
   every pass-dependent card. Pass 2 disabled/hidden when no 2nd pass ran. Subsumes the
   Model tab's `modelPassSel` and the Pass dimension of the FDR-calibration `fdpViewSel`.
2. **Keep the experiment-wide / per-run switch as an orthogonal secondary dimension** where
   it applies (FDR calibration, id yield, cross-run) -- it is NOT the same axis as Pass 1/2.
   End state: a card can be (Pass) x (Scope) with two small selectors, the Pass one global.
3. **Serialize the missing Pass-2 variants** so the switch has data: id-yield, per-file
   passing table, cross-run trio, density, density-ratio, win-fraction -- call the existing
   builders on the Pass-2 pool (`RescoredEntries` / `modelPass2.scores`) at
   `WritePass2AndFinalize`. No new data collection; the pools are already resident there.
4. **Per-card graceful "n/a for this pass"** (esp. structural cards under transfer mode).
5. Make it **unambiguous which pass every number is** -- e.g. the Summary/KPIs should note
   they are pass-independent population counts; the per-file passing table should label its
   q source. Today "is this Pass 1 or Pass 2?" is guesswork on several cards.

## Secondary layout cleanup (same page, requested together)
- [ ] **Move "Identification yield" off the Reproducibility tab, back onto "FDR calibration."**
  It started there and FDRBench places yield with calibration; that tab already has the
  exp-wide/per-run switch it needs. It became the Reproducibility headline only incidentally
  (added when the "detections by run" + "runs detected" plots were requested).
- [ ] **Reproducibility tab reorg:** it now carries 4 plots (yield + detections-by-run +
  runs-detected + union-FDP) plus a long exp-wide/per-run explanation, so the first *actual*
  reproducibility plot ("Precursor detections by run") is below the fold. With yield moved
  out, lead the tab with "Precursor detections by run"; trim/relocate the long preamble so a
  reproducibility plot is visible without scrolling.

## Gates
- Output-only: `regression.ps1 -Dataset Stellar` stays byte-identical (report is off the
  golden path; the gate never sets `--model-diagnostics`).
- Manual render check on: a percolator run (Pass-2 model present), a **transfer** run
  (`OSPREY_PASS2_QVALUE=transfer`, Pass-2 model absent but Pass-2 q present), and a
  no-entrapment / no-2nd-pass run (Pass 2 hidden). Headless-Chrome screenshot each, confirm
  every card re-sources on the toggle and structural cards show the n/a note under transfer.
- Existing `TestModelDiagnosticsData` extended for the new Pass-2 serialized fields.

## References
- Report code: `Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html`,
  `ModelDiagnosticsReport.cs` (`WritePass2AndFinalize` :133-170, `BuildModelPass2` :169),
  `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs` (`BuildScoreHistogram` :549/:645,
  `BuildDensityRatio` :554, `BuildFdpViewsFromPrecs` :577, `BuildIdYield` :557/:1093,
  `BuildCrossRunDetection` :564, `BuildWinFraction` :568, chips counts :524-533).
- Predecessors: #4377 (report), #4408 (bug fixes + cross-run graphs), #4410 (pass-2 transfer).
- [[project_ospreysharp_output_architecture]] (diagnostics is -d-only off the mainline).
