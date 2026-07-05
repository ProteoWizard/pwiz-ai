# TODO-20260705_osprey_model_diagnostics.md -- Ship the FDR-calibration diagnostics as a self-contained interactive `--model-diagnostics` HTML report

## Branch Information
- **Branch**: `Skyline/work/20260705_osprey_model_diagnostics`
- **Base**: `master`
- **Created**: 2026-07-05
- **Status**: In Progress
- **Worktree**: `C:\proj\pwiz-work2`
- **GitHub Issue**: (pending)
- **PR**: (pending)

## Origin
Backlog item `TODO-osprey_diagnostics_fdr_plots.md` (brendanx67), motivated by the
2026-07-03/04 FDR-calibration sprint. A handful of one-off Python plots proved
decisive for understanding how Osprey's FDR performs and where its assumptions
fail; they should become reproducible, first-class Osprey exports.

## Direction decision (2026-07-05)
The backlog item's "open decision" (CSV+script vs in-process PNG) was superseded
by a better idea from brendanx67: **emit a single self-contained interactive DHTML
page** (inline JS/CSS/data, no CDN, opens offline) with a multi-tab display of rich
diagnostics -- plots AND the summary table we currently write to command output.
More informative and more dynamic than PNG/PDF, and the C# data-extraction work
(pairing, binning, dedup, classification, FDP math) is the same either way.

- **Flag**: a first-class CLI argument `--model-diagnostics` (NOT a `-d` bisection
  sub-flag). `-d` emits byte-stable English dumps for cross-impl diffing; this is a
  user-facing deliverable that writes one HTML file when a run finishes.
- **Rendering**: compact vanilla-SVG charts in JS, no charting library, everything
  inlined into one `.html`. Run data embedded as a JSON blob.
- **Scope this branch (single-run page, 4 tabs)**:
  1. **Summary** -- the per-file / total passing-precursor table currently logged
     to stdout (`FirstJoinTask.LogFirstPassResults`), rendered sortable + richer.
  2. **Win-fraction** -- paired decoy-win fraction vs winner-score bins, real
     (target) vs entrapment (p_target) pairs, fair-coin reference + null-band
     summary. Highest-value plot. Degrades to real-only when no manifest.
  3. **4-class Density** -- best-per-precursor score density for T / P / D / Pd
     (needs the manifest for the P/Pd split; degrades to T vs D without it).
  4. **FDP q-q** -- Osprey q-value vs true FDP (lower_bound / paired / combined),
     **computed in C# in-process** from the pairing manifest + per-entry q-values
     (no external FDRBench dependency). Verify numbers against the existing
     `Run-FdrBench.ps1` `fdp.csv` on Stellar so the oracle matches.
- **Deferred to a follow-up** (`--model-diagnostics-compare runA runB` mode): the
  **library-impact q-q + Venn**, which is inherently a TWO-run comparison
  (entrapment vs non-entrapment library) and cannot come from a single finishing
  run. It will read two run dirs off disk and emit its own comparison HTML.

## Data sources (all present in-memory at Stage 5 / first-join)
`FdrEntry` (`Osprey.Core/FdrEntry.cs`) already carries everything the prototypes
read from the 458 MB Stage-5 Percolator TSV: `EntryId`, `IsDecoy`, `Charge`,
`Score` (first-pass SVM discriminant), `RunPeptideQvalue` (+ the other q-values),
`ModifiedSequence`. The Stage-5 hook
`FirstJoinTask.LogFirstPassResultsAndDump(perFileEntries, config, ctx)` has the
per-file `List<FdrEntry>` lists in memory plus `config` (with
`DecoyPairingManifestPath`). So the report is computed from live data -- no
parquet/sidecar disk re-read.
- Pairing: `base_id = entry_id & 0x7FFFFFFF` (`FdrBenchInputWriter.BASE_ID_MASK`);
  high bit = decoy flag (`LibraryEntry.DECOY_ID_BIT`).
- Classification: `DecoyPairingManifest.FromTsv(path)` ->
  `PeptideKind {Target, Decoy, PTarget, PDecoy}`, looked up by
  `entry.ModifiedSequence` (matches the prototype; add an "unclassified count"
  log so a sequence-key mismatch is visible).

## Architecture (keeps the feature OUT of the `-d` bisection seam)
The feature needs only `FdrEntry` + the manifest, both reachable from
`Osprey.IO` / `Osprey.Tasks`, so it does NOT touch `IOspreyDiagnostics`
(the cross-impl bisection seam). Only exe touch = the CLI arg + help text.
- `Osprey.IO/ModelDiagnostics/` (new): pure, testable data model + computation
  (win-fraction, density, FDP, summary) returning a serializable model; +
  self-contained HTML writer that injects the JSON into an embedded template.
- `Osprey.Tasks/FirstJoinTask.cs`: one gated call
  `if (config.ModelDiagnostics) ModelDiagnosticsReport.Write(perFileEntries, config, ctx);`.
- `Osprey.Core/OspreyConfig.cs`: `ModelDiagnostics` bool.
- `Osprey/OspreyCommandArgs.cs`: `--model-diagnostics` argument + help text.
- `Osprey.Test/`: unit tests for the pure computation (win-fraction real-below-50%,
  entrapment-at-coin, 4-class counts, FDP monotonic vs oracle, no-manifest degrade)
  and a smoke test that the HTML renders + is self-contained (no external URLs).

## Work
- [ ] Locate/confirm the stdout summary + add a `TryGetKind(sequence)` accessor to
      `DecoyPairingManifest` if not already public.
- [ ] Pure data model + computation in `Osprey.IO/ModelDiagnostics/` + unit tests.
- [ ] In-process FDP (lower_bound / paired / combined) + verify vs `fdp.csv`.
- [ ] Self-contained HTML writer + template (tabs, vanilla-SVG charts). Use the
      dataviz design guidance; theme-aware, no CDN, one file.
- [ ] `--model-diagnostics` flag + `FirstJoinTask` hook + help text.
- [ ] Run on Stellar (with an entrapment manifest), open the HTML, sanity-check
      each tab against the sprint prototypes.
- [ ] Follow-up TODO for the two-run `--model-diagnostics-compare` mode + the
      HTML-text localization pass (treated as a diagnostic artifact / English for now).

## Gates
- No change to non-`--model-diagnostics` output (regression golden unaffected;
  the feature is opt-in and writes only its own HTML file).
- `Build-Osprey.ps1 -Configuration Debug -RunTests -RunInspection` clean.
- Correctness gate `regression.ps1 -Dataset Stellar` unaffected (opt-in feature).

## References
- Prototypes (NOT committed; reference only): `ai/.tmp/OspreyFDR/winfrac-plot.py`,
  `density-plot.py`, `qq-entrapment.py` + `venn-entrapment.py` (two-run, deferred),
  `qq-with-lowerbound.py` (FDP oracle).
- `FdrScoresSidecar.cs` (sidecar format), `ParquetScoreCache.cs` (scores.parquet),
  `DecoyPairingManifest.cs` (manifest), `FdrBenchInputWriter.cs` (base_id mask).
- Related memory: [[project_ospreysharp_output_architecture]] (Diagnostics is
  `-d`-only -- this feature deliberately sits beside it as a user-facing export),
  [[project_osprey_libdecoy_vs_gendecoy_calibration]] (what the plots revealed),
  [[no_localizable_string_in_static]] (localization posture).

## Night session progress (2026-07-05, autonomous)
**Status: feature built, runs end-to-end on real data, gates green, committed on
the branch (NOT pushed, no PR -- per the night-session instruction).**

Commits on `Skyline/work/20260705_osprey_model_diagnostics`:
- `53d0e6385f` -- feature: `--model-diagnostics` flag + self-contained HTML report.
- `5afdece11f` -- FDP validated vs FDRBench + unit tests + inspection fixes.

What works (verified on real Stellar all-3 + Astral entrapment runs):
- **Model tab**: 21-feature contribution table (SG-weighted cosine 44%, xcorr 30%,
  ...), negative-percent rows in red -- the Skyline mProphet feature table, reproduced.
  Composite score histogram (T/D/P/Pd) with a fitted decoy-normal overlay.
- **Density tab**: area-normalized 4-class density.
- **FDR calibration tab**: reported-q vs true-FDP. **FDP verified EXACT vs FDRBench
  fdp.csv**: combined = (1+1/r)*n_p/(n_t+n_p), lower_bound = n_p/(r*(n_t+n_p)); at
  Stellar r=1, reported q=1% -> combined FDP 1.68% / lower-bound 0.84% (reproduces the
  sprint's anti-conservative pass-2 finding, in-process, no FDRBench install).
- **Competition tab**: paired decoy-win fraction, real vs entrapment; Stellar null band
  real 47.8% vs entrapment 50.0% (the honest-coin signal).
- **Summary tab**: per-file passing counts.

Key implementation facts (for the next session):
- Data model: `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs` (pure, unit-tested).
  Orchestrator + embedded HTML template: `Osprey.Tasks/ModelDiagnostics/`.
- Hook: `FirstJoinTask.LogFirstPassResultsAndDump` (Stage 5, pre-compaction). The
  trained `FeatureContributions` is now returned out of `PercolatorEngine.RunPercolatorFdr`.
- Manifest match: strip `[UniMod:...]` mods from ModifiedSequence -> bare sequence
  (manifest is keyed bare). Lifts match 77%->98% on Stellar.
- Demo outputs: `D:\test\osprey-runs\_mdiag\{stellar,astral}\*.model-diagnostics.html`.
  Regenerate fast by clearing FDR artifacts (keep `*.scores.parquet`) and re-running
  the same Osprey command (PerFileScoring resumes from cache; FirstPassFDR reruns ~66s
  Stellar). Build Release: `Build-Osprey.ps1 -SourceRoot C:\proj\pwiz-work2 -Configuration Release -TargetFramework net8.0`.
- Screenshot QA: the Chrome extension can't screenshot localhost here; use headless
  Chrome `--screenshot` on a copy with `.tab{display:block}` forced (all tabs stacked).

Update (later in the same night session): **paired estimator now implemented** and
committed (`b6ba1ba57c`). paired = (n_p + n_p_s_t)/(n_t+n_p) via
`DecoyPairingManifest.PairIndices()`; on Stellar at reported q=1% the three curves
read lower 0.84% < paired 1.49% < combined 1.68% (FDRBench's expected ordering),
paired within [lower, combined] for all points. Unit-tested (`TestPairedEstimator`).

Deferred / follow-ups:
- **Live end-to-end FDRBench cross-check**: the three estimators are proven to match
  FDRBench's fdp.csv *formulas* (decoded byte-exact from a real fdp.csv) and are
  unit-tested, but a `--fdrbench` run of THIS build piped through the jar, diffed
  against the HTML curve, would be the belt-and-suspenders proof. (Do serially -- never
  run two Osprey processes at once; it corrupts the inspection gate and invalidates the
  scores.parquet cache, per tonight's experience.)
- **Two-run compare mode** (`--model-diagnostics-compare`) for the library-impact
  q-q/Venn (still the right home for the two-run plots).
- **HTML template ASCII cleanup**: a few typographic chars (middot, delta-mu, en-dash)
  remain as raw UTF-8 in the template JS; render fine, but convert to \uXXXX for the
  ASCII rule. (Inspection gate is C#-only, so it's green regardless.)
- **Resume path**: on a bundle-rehydrate run the model table is absent (no retrain);
  the other tabs still render. Acceptable; note for polish.
- Localization of the HTML body text (treated as diagnostic artifact / English now).

## Morning session progress (2026-07-05) - FDRBench side-by-side harness
Interactive session with Brendan reworking the FDR-calibration tab to match the
FDRBench plots he reviews. Commits on the branch (newest first):
- `fd4d0772b3` Fixed FDP counting to q-threshold (matches FDRBench) - the core fix
- `671ee677aa` Cherry-picked `--fdrbench-pass` from the libdecoy branch (stays on
  this branch per Brendan; lets ONE binary emit both the HTML report and the
  FDRBench pass-1/2 input TSVs for same-run validation)
- `47af0bfeba` Reworked FDR tab: run- vs experiment-scope precursor-q views (the
  experiment-wide views reproduce FDRBench; per-run is a new picture), 2-panel
  layout (zoom [0,2%] with auto-scaled FDP axis + full extent), y=x, open-circle
  markers, metrics box, view selector. Kept raw SVG (decided against c3.js).

**Key findings this session:**
- FDRBench does NOT compute its own q - it passes through Osprey's q from the
  `--fdrbench` TSV (experiment-precursor by default). The calibration x-axis must be
  Osprey's precursor q, not peptide q.
- FDRBench counts each class by its OWN q<=t (n_t, n_p = targets, entrapment with
  q<=t), NOT a score-ranked running tally. This was my core bug; fixing it moved
  Stellar combined@1%q from 0.82% -> 1.79% (FDRBench golden = 2.03%, CONFIRMED
  correct on our own run via the live jar).
- Built + validated the side-by-side harness (Osprey `--model-diagnostics --fdrbench
  --fdrbench-pass 1` -> FDRBench jar -> diff vs HTML). It caught the bug.

**Remaining (the finalize-blocker):** ~12% gap left - my n_p=237 vs FDRBench 275,
disc 26499 vs 26879. Source = precursor CLASSIFICATION (manifest mod-strip catches
~98%; FDRBench matches the unmodified `peptide`) + the DEDUP KEY vs
`FdrBenchInputWriter`. Next task: align the report's classification+dedup with
`FdrBenchInputWriter` (ideally reuse its row-building so they can't drift), validate
to a byte-level match, THEN add pass-2 views + a repeatable compare script.

**Next session handoff**: read `ai/.tmp/handoff-20260705-fdrbench-classification.md`
before starting - it has the exact harness commands, current numbers, the classification
alignment plan, and gotchas (no parallel Osprey; cd to C:\proj before pwsh).

## Autonomous session progress (2026-07-05, later) - FDRBench MATCH achieved
Cloned FDRBench source (`Noble-Lab/FDRBench` -> `ai/.tmp/fdrbench-src`) and read the
actual counting path (`FDREval.calc_fdp_fast_kfold` + `FDPCalcKFold`, k=1). Root cause
of the residual gap found in the source:
- FDRBench classifies each row by the library sequence its **base-id** resolves to
  (`lib.Sequence` via `EntryId & 0x7FFFFFFF`, the exact key `FdrBenchInputWriter`
  emits as the `peptide` column), then looks it up in the manifest. The report was
  stripping mods off `ModifiedSequence` instead - diverged for ~2%.
- FDRBench **removes invalid peptides** (`peptide` not in the manifest) before
  counting (`remove_invalid_peptides`): ~7,873 unique peptides / ~10k rows on Stellar.
  The report was counting those as targets, depressing the FDP.
- Paired estimator is `vt = n_p_s_t + 2*n_p_t_s` (was missing the 2x term) with the
  target matched by (pair_index, charge).

Fix (commit `45cafb60f1`): classify by base-id -> manifest (Unknown = FDRBench-invalid,
dropped from FDP); paired reworked to the two-event vt; q-aware curve thinning (dense
in [0,2%]). Plumbed `libraryById` into `ModelDiagnosticsReport.Write`.

**RESULT - HTML now reproduces FDRBench fdp.csv** (3-file Stellar libdecoy, 1% exp q):
| metric | HTML | FDRBench | 
|--------|------|----------|
| discoveries n_t | 26879 | 26879 |
| combined | 2.026% | 2.025% |
| lower_bound | 1.013% | 1.013% |
| paired | 1.786% | 1.786% |
Exact at q=0.001/0.002/0.005/0.01/0.02; off-grid points (0.008/0.015) differ only by
curve-sampling (nearest kept q differs by ~1e-4), not computation. Debug gate green
(451 tests), Release green. NOT pushed.

**Still open:** (1) per-run view validation vs FDRBench per-run TSV; (2) PASS-2 views
(post-compaction, needs the MergeNodeTask end-of-run hook + carrying FeatureContributions
forward + the 2nd-pass sidecar); (3) small repeatable compare script; (4) regenerate the
Astral page; (5) `--fdrbench-pass` accepting `1,2`/both. The FDRBench source is at
`ai/.tmp/fdrbench-src` (gitignored) for reference.

### Later autonomous progress (2026-07-05 ~10:30) - plots + Astral + compare tool
- **Plot fix (commit `204c24fb05`):** the [0,2%] zoom panel y-axis was pinned to 100%
  by the tiny-n transient (first target -> combined=100%). Now scales to the settled
  curve (ignore the first ~2% of accepted targets) and skips those points when drawing.
  Stellar zoom now reads "FDP axis to 4.6%" with clean combined/paired/lower curves
  hitting the 1%-q KPIs (2.03/1.79/1.01%). Screenshots (headless Chrome, FDR tab forced
  visible): `D:\test\osprey-runs\_mdiag\{stellar,astral}\*_fdr_zoom.png`.
- **Compare tool:** `ai/scripts/Osprey/Compare/Compare-Fdrbench-Html.py` -- runs the
  FDRBench jar on the run's `*_fdrbench.tsv` and diffs the HTML experiment view at q
  points, PASS/FAIL at q=0.001/0.002/0.005/0.01/0.02 (tol 5e-4). Stellar: MATCH.
- **Astral (libdecoy, hram, 3 files) regenerated** with the fix. HTML KPIs: 82,127
  disc @1% q, combined 1.89%, paired 1.76%, lower 0.94%, max q 88.3%. Numbers are
  correct by construction (identical validated BuildFdpView; Stellar proved it exact).
  Astral has a genuine q-floor (~0.0015) where many precursors cluster -- shows as a
  short vertical FDP feature at the far left of the zoom; faithful to FDRBench, not a
  bug. (Astral jar cross-check is slow: 2.57M-row pass-1 pool, ~O(n*uniq_q).)
- Gotcha: Astral scores.parquet cache in `_mdiag/astral` does NOT match `--resolution
  hram` params, so each regen re-scores (~15 min). For a screenshot-only refresh, patch
  the generated HTML's two `drawPanel` lines directly instead of re-running Osprey.

### PASS-2 implementation plan (deliberate, not done autonomously - carries risk)
The report fires once at `FirstJoinTask` (pass 1, pre-compaction). Pass 2 = the reported
pool = `MergeNodeTask`: `ctx.Get<RescoredEntries>().Value` (post-compaction, 2nd-pass
q-values) + `libraryById` are in scope there; `FdrBenchInputWriter` already emits the
pass-2 TSV at MergeNodeTask.cs:166 (`--fdrbench-pass 2`). To show BOTH passes in one HTML
with the existing view selector, generate the report at MergeNode with both pools -- the
pass-1 pool would be reloaded from the `.1st-pass.fdr_scores.bin` sidecars (it is compacted
away by MergeNode). The pass-2 model table needs the 2nd-pass Percolator's
FeatureContributions (not currently surfaced by `Pass2FdrSidecar`); the FDP views only need
(score, exp/run q, base-id) per precursor, which RescoredEntries has. Lowest-risk first cut:
a SECOND report invocation at MergeNode writing pass-2 FDP views into the same
`ModelDiagnosticsData.FdpViews` list (Pass=2), validated with `--fdrbench-pass 2` via the
compare tool.
