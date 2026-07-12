# TODO-20260711_osprey_model_diagnostics_pass_switch.md -- One top-level [Pass 1][Pass 2] switch for the whole --model-diagnostics page + Reproducibility/yield layout cleanup

## Branch Information
- **Branch**: `Skyline/work/20260711_osprey_model_diagnostics_pass_switch`
- **Base**: `master`
- **Created**: 2026-07-11
- **Status**: In Progress
- **PR**: [#4413](https://github.com/ProteoWizard/pwiz/pull/4413)

## Status
**Active (created 2026-07-11, started 2026-07-11).** Raised by Brendan after the pass-2 q-value work
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

## Progress (2026-07-11)
Implemented in `pwiz-work1` on `Skyline/work/20260711_osprey_model_diagnostics_pass_switch`.

**C# data model (`Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs`)**
- New nested `Pass2Data` bundle: a STRUCTURAL half (`Model`/`DensityRatio`/`WinFraction`, null
  under transfer) + a Q-DRIVEN half (`FdpViews`/`IdYield`/`CrossRun`/`PerFile`, always). Replaces
  the old fragmentary `ModelPass2` property + the pass-2 append into the flat `FdpViews`.
- New public `BuildPass2(...)` mirrors `Build(...)` over the reported pool, reusing the existing
  private builders. Factored the inline per-file loop into `BuildPerFile` (shared pass 1 / pass 2).
- `ModelDiagnosticsReport.WritePass2AndFinalize` now calls `BuildPass2` once and sets `data.Pass2`.
- Design decision (asymmetric): pass 1 stays in the top-level `D` fields (always present, written at
  FirstJoin); pass 2 is the single `D.pass2` bundle (the MergeNode enrichment). The template's JS
  normalizes both into a symmetric `PASSES` array. Rationale: a symmetric `Passes[]` list would force
  rewriting the pass-1 build + FirstJoin render + sidecar contract + every existing test assertion
  for no user-visible gain.

**Template (`model-diagnostics-template.html`)**
- Global `[Pass 1][Pass 2]` switch top-right of the tab bar (`#passSel`); hidden when no 2nd pass.
  A `renderPass()` re-sources every card from `PASSES[PI]`. Removed the Model tab's `modelPassSel`
  and the pass dimension of the old 4-way `fdpViewSel`.
- Per-card graceful n/a (`PASS2_NA_*` + `naChart`) for the structural cards (Model / Density /
  Competition) under transfer mode.
- Deliverable 5: Summary KPIs labeled pass-independent; per-file table labels its pass + pool.

**Gates run (all green)**
- `Build-Osprey.ps1 -SourceRoot C:/proj/pwiz-work1 -RunTests -RunInspection`: 502 passed / 3 skipped;
  inspection clean for changed files (only pre-existing SystemMemory.cs local noise, #4379).
- Extended `TestModelDiagnosticsData` with `TestBuildPass2` (retrain / transfer / no-entrapment /
  sidecar round-trip).
- Template render check via headless Chrome on the real embedded JSON of
  `runs/seaad-20files-entrapment-r0.5` (transfer) and `-r0.5-percolator` (retrain), transformed to
  the new schema, plus synthetic no-2nd-pass / no-entrapment variants. Confirmed: pass switch drives
  all cards, transfer structural cards show n/a while q-driven render, no-2nd-pass hides the switch,
  no-entrapment hides the FDP card but keeps yield, no JS errors. (Render harness in `ai/.tmp/mdiag*`.)
- End-to-end render through the REAL C# path (Build + BuildPass2 -> ModelDiagnosticsHtml.Render) via
  a throwaway `_TempRenderPass2Test` (DELETE before commit): retrain + transfer variants, with a
  distinct pass-2 reported pool simulating Stage-6 reconciliation. Confirmed the q-driven tabs
  (Reproducibility / Competition / Summary) genuinely differ per pass (perFile[0].targets 10 -> 17,
  perRunCount[0] 10 -> 17) and transfer flags hasStructural=false. **Note:** the first demo files sent
  had NO real pass-2 q-driven data (old embedded JSON predates it), so the harness cloned pass-1 ->
  pass-2 and those three tabs looked identical -- a demo-data artifact, NOT a template/C# bug
  (proven: perturbing pass-2 data makes all three tabs change on the switch).
- **Real end-to-end render (authoritative):** re-ran Stages 5-7 of the 20-file SEA-AD r0.5 run on
  hard-linked Stage-1-4 caches (new dir `runs\seaad-20files-entrapment-r0.5-mdiag`, 17 min vs 118 min
  full). `PerFileScoring` + `PerFileRescoring` rehydrated from links; `FirstPassFDR` + `SecondPassFDR`
  ran and regenerated the real report ("2 pass-2 FDR views; pass-2 model included" = retrain path).
  Confirmed on real data that ALL tabs re-source per pass, incl. the three that looked static in the
  cloned demo: per-file targets 32,972 (P1) -> 52,085 (P2); real decoy-win coin 0.40 -> 0.00. No JS
  errors. (Resume mechanism: `TaskValiditySidecar.IsValid` compares only the content-based
  `validity_key`, NOT version/mtime/path, so a newer build reuses old-version caches given identical
  CLI args.)
- `regression.ps1 -Dataset Stellar`: **PASS** -- mode1 (vs golden), mode3 (HPC==straight), mode2
  (resume==straight) all byte-identical (blib 50,237,440 bytes). Report is off the golden path.
- Committed (777dd584b2) + pushed; PR #4413 opened.

## Secondary layout cleanup (same page, requested together)
- [x] **Move "Identification yield" off the Reproducibility tab, back onto "FDR calibration."**
  Done. **Decision (confirmed with Brendan):** the FDR-calibration tab is now shown on EVERY run
  (it carries the always-present yield curve); its entrapment-only "q vs true FDP" card hides itself
  when there is no entrapment. A single exp/run scope selector at the top of the tab drives BOTH the
  FDP card and the yield curve (orthogonal to the global Pass switch).
- [x] **Reproducibility tab reorg:** Done. Yield removed; the long exp-wide/per-run preamble is
  trimmed to a short lead paragraph + compact scope selector, so "Precursor detections by run" is the
  first card (above the fold).

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
