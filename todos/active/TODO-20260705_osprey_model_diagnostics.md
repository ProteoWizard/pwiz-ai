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
- [x] Pure data model + computation in `Osprey.FDR/ModelDiagnostics/` + unit tests.
- [x] In-process FDP (lower_bound / paired / combined) + verified vs `fdp.csv` (Stellar + Astral MATCH).
- [x] Self-contained HTML writer + template (tabs, vanilla-SVG charts, theme-aware, no CDN, one file).
- [x] `--model-diagnostics` flag + `FirstJoinTask` hook + help text.
- [x] Run on Stellar + Astral (entrapment manifest), sanity-check each tab; pass-1 == FDRBench.
- [x] **Pass-2 FDR views** (final reported pool) via a data sidecar carried FirstJoin -> MergeNode.
- [x] **Per-feature score distributions** (mProphet "Feature Scores"): click a Model row.
- [x] **Print-to-PDF** (all tabs, all FDR views, all feature distributions).
- [x] Review round 1 (8 items) + round 2 (7 items) applied and verified.
- [ ] Push + open PR; trigger TeamCity Perf/Regression on `pull/<N>` (Astral legs).
- [ ] Follow-up TODO for the two-run `--model-diagnostics-compare` mode + HTML-text localization.

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

## KEY FINDING (2026-07-05, later) - the searched LIBRARY is a complete, single authority
Chasing "why does FDRBench drop ~2% of IDs" led to the most important structural insight
of this work. Summary:

**What FDRBench drops, and why.** FDRBench (`-pep <manifest>`) classifies each ID by the
pairing manifest and **drops** any peptide whose sequence is not in it (its
`remove_invalid_peptides` step). On Stellar pass-1 that is 10,233 rows / 7,873 unique
peptides = 2.1% of the pool; only 26 clear 1% q, so combined@1%q moves 2.03% -> 2.05% if
kept. NOT a FDRBench counting bug (our HTML matches it exactly on the kept set); it drops
because we hand it a manifest that does not fully describe the searched library.

**Root cause = two sources of truth.** The carafe spectral library and the
`osprey_library_db_pairing.tsv` manifest are produced by two different tools independently
digesting the same FASTA (Carafe predicts the library; a FDRBench-style `-build_entrapment_fasta`
step writes the manifest). They agree on 97.9% of peptides and differ on ~2% at the edges
(peptides Carafe put spectra in the library for but FDRBench's pairing step did not emit).
No reconciliation, no "counts must match" assertion -> silent drift. Brendan's framing:
that is broken-by-design; only one tool should be the authority. The manifest is Mike's
carafe/osprey workflow output (we consume it, did not produce it).

**Correction to an earlier mis-count in this session.** I first reported a huge 296K/375K
"divergence." That was WRONG: this library's `Decoy` column is all 0 (decoys are marked via
the manifest / the `decoy_` protein prefix, not the column), so I was comparing the library's
unmarked decoys against the target-only half of the manifest. Corrected: library vs FULL
manifest = 97.9% in, 2.1% out.

**THE finding: the library's `ProteinID` column already encodes everything the manifest does.**
- type: `decoy_` prefix => decoy side; `_p_target` in the name => entrapment. So
  target = neither, p_target = `_p_target`, decoy = `decoy_`, p_decoy = both.
  Verified: library protein-label type == manifest `peptide_type` on 359,309/359,309
  overlapping peptides (100%).
- pairing: the quartet {target, p_target, decoy, p_decoy} are all shuffles of ONE original
  peptide and share `<accession>_pep<NNNNN>` in the protein name (target `P55011_pep00001`,
  entrapment `P55011_p_target_pep00001`, decoy `decoy_sp|P55011_pep00001|...`, etc). Verified:
  50,000/50,003 manifest `peptide_pair_index` groups reconstruct EXACTLY from the library
  protein `(accession, pepNNNNN)`.
So the external manifest is REDUNDANT for this workflow -- the library Osprey actually
searched carries the full classification AND the pairing.

**Pairing semantics (for the record).** The quartet carries two relationships: target<->decoy
(Osprey's own target-decoy FDR competition) and target<->entrapment (FDRBench's PAIRED
estimator). FDRBench builds each entrapment by shuffling a specific target, so entrapment is
the "closest possible fake" of one real peptide; the paired estimator uses that head-to-head
(did the shuffled twin out-score the real one, or was the real one unseen?) for a tighter FDP.
combined/lower need only target-vs-entrapment counts + ratio r, no pairing.

### DECISION: library = single source of truth (implementing now)
Derive classification + pairing from the searched library (protein names), use it for the
model-diagnostics classification AND emit a complete FDRBench pairing manifest from it, so
neither the HTML nor FDRBench drops anything. Demote the external `--decoy-pairing-manifest`
to an optional cross-check and WARN loudly when it disagrees with the library (the assertion
the generation pipeline is missing). Staging by risk:
- Stage 1 (now, diagnostics-only, low risk): library-derived classifier -> HTML classByBaseId/
  pairByBaseId; emit `<fdrbench>.pairing.tsv` from the library; compare tool uses it; mismatch
  warning. Validate: HTML + FDRBench both keep all IDs and agree.
- Stage 2 (later, deliberate, regression-gated): migrate Osprey's own decoy pairing
  (`ApplyToLibrary`) to derive base-ids from the library too, so the FDR path shares the one
  authority. Mainline-affecting -> needs the regression + perf gates; NOT bundled into Stage 1.
- Upstream (Mike's pipeline): single-authority digestion + a hard count-match assertion so the
  library and manifest cannot diverge. A conversation + workflow change, characterized here for
  that discussion; not something to unilaterally rewrite.

## Single-authority classification + Met-clip root cause (2026-07-05, deep dive)
Chasing "why does FDRBench drop ~2%" led to the real root cause, confirmed in Mike's
`carafe_log.txt`:

**Root cause = Carafe `-clip_n_m` misapplied + shuffle doesn't hold the N-terminus.** Entrapment
is Carafe's own `EntrapmentFastaGear`, peptide-level clean 1:1 quartets (NOT protein-level; NOT
FDRBench). But the final library is predicted with `-clip_n_m`, which clips EVERY M-starting
peptide (98.6% are internal Mets that are never cleaved in vivo, not initiator Mets) because each
peptide is a standalone FASTA record. The entrapment/decoy shuffle fixes the C-terminus but not
the N-terminus, so it moves the Met in/out of position 1; the clip then fires asymmetrically,
leaving peptides with no counterpart. Verified: 15,539 library peptides (2.1%) are Met-clip forms
(100% are `M`+seq of a manifest peptide); orphans split 164 target / 138 entrapment among
identified, more across the full library; 164/164 orphan-target and 138/138 orphan-entrapment show
the exact M-move. Carafe issues FILED on maccoss/Carafe:
#1 (N-terminal Met handling) https://github.com/maccoss/Carafe/issues/1 ; #2 (manifest doesn't
match predicted library) https://github.com/maccoss/Carafe/issues/2. Drafts:
`ai/.tmp/carafe-issue-{1,2}-*.md`. Quantified over-representation: 14,386 of 15,539 Met-clipped
peptides (93%) are mis-clips of internal Mets; correct initiator-Met-only clip = ~30x reduction.

**Osprey fixes (committed on the branch):**
- `45cafb60f1` classify FDP by library base-id (matches FDRBench); `204c24fb05` zoom y-axis fix.
- `cdfb325217` classification is derived from the searched LIBRARY (single source of truth), not
  the external manifest; Osprey emits a corrected `<fdrbench>.pairing.tsv` from the library;
  `EntrapmentLibraryClassifier` reads type from protein accessions (`_p_target`/`decoy_`).
- `da8737694f` `EntrapmentPairing` reconciles library vs manifest: reconstruct the extras' pairing
  from the intact `_pepNNNNN` token, keep matched Met-clip pairs, DROP unmatched entrapment when
  `M`+seq is a manifest peptide (the artifact), surface anything unmatched it can't explain.
  Dropped consistently from the emitted manifest, the FDRBench input TSV, AND the HTML
  classification, so the two code paths agree.

**RESULT (Stellar libdecoy): HTML FDP now matches STOCK FDRBench** (no jar patch), 3,241 orphan
entrapment dropped, no invalid-removal, no NPE. Compare tool `RESULT: MATCH` at every gated q;
1% exp q combined 2.03% both sides. Repeatable: `Compare-Fdrbench-Html.py --dir <run> --pass 1`
(prefers Osprey's emitted `<tsv>.pairing.tsv`).

**FDRBench:** a graceful patch was tried but abandoned - stock FDRBench works once we feed it a
clean manifest. Remaining upstream nicety (optional PR): FDRBench `get_paired_target_peptide`
should give a clean error, not an NPE, on an entrapment with no target (`ai/.tmp/fdrbench-src`
has the local fork with that fix, validated).

**Still open / next:** resume general HTML work (pass-2 views still deferred; per-run view;
Astral regen with the new drop-logic); consider whether to also drop the symmetric orphan
TARGETS (currently kept - they only add to n_t). Branch has 11 commits, clean tree, NOT pushed
(no PR yet). Latest verified commit `925647753d`; HTML matches STOCK FDRBench (RESULT: MATCH).

**Next session handoff**: For detailed startup protocol (build, the reprocess+compare validation
loop, next steps, gotchas), read `ai/.tmp/handoff-20260705_osprey_model_diagnostics.md` before
starting work.

## Night session progress (2026-07-05/06, autonomous) - PASS 2 + per-feature dists + PDF
Goal (Brendan, at bedtime): pass-2 FDR views (were absent), regenerate BOTH datasets to match
(for FDR) the target PNGs in `ai/.tmp/OspreyFDR/post-PR4347`, plus extra credit per-feature score
distributions and (final stretch) print-to-PDF. **All delivered; committed on the branch (NOT
pushed).**

Commit `9fd321cd38` (pwiz) + `85a01e8` (ai, compare-tool). Debug gate green (452 tests, 0 warnings).

- **Pass 2 FDR views (the main ask).** FirstJoinTask now stashes the pass-1 `ModelDiagnosticsData`
  to a JSON sidecar (`<stem>.model-diagnostics.data.json`, Newtonsoft, NaN-safe Symbol float
  handling); MergeNodeTask reloads it, computes the pass-2 (post-compaction, 2nd-pass-q) FDP views
  from `RescoredEntries` -- the SAME pool the pass-2 FDRBench TSV is written from -- appends them,
  and re-renders one page. The 4-view selector offers Pass 1/2 x experiment/per-run. Shared code
  (`ReduceToPrecs` + `BuildFdpViewsFromPrecs`) computes both passes identically, so pass 2
  reproduces stock FDRBench by construction (same library-derived classification/pairing/orphan-drop).
  - **Both datasets validated: RESULT MATCH** (no --protein-fdr, 1% exp q).
    Stellar pass 2: combined 0.90% (FDRBench 0.90%, target PNG 0.90%), paired 0.81%, disc 26753;
    pass 1 = 2.01% (target 2.03%). Astral pass 2: combined 0.88% (FDRBench 0.876%, target 0.87%),
    paired 0.82%, disc 81918; pass 1 = 1.92% (target 1.89%). Astral's genuine ~0.0015 q-floor spike
    renders faithfully (matches `astral_libdecoy_pass2.png`). Screenshots + PDFs in ai/.tmp/mdiag-shots/.
  - Validate: `python ai/scripts/Osprey/Compare/Compare-Fdrbench-Html.py --dir <run> --pass 2`
    (the tool now filters the HTML experiment view by --pass).
- **Per-feature score distributions (extra credit).** `FeatureContributions.Accumulator` optionally
  bins each feature's standardized value by class into target/decoy histograms (gated on
  `PercolatorConfig.CollectFeatureHistograms = config.ModelDiagnostics`, so the production scoring
  path is byte-identical + perf-neutral). Carried onto the model rows. In the HTML, clicking a
  feature row in the Model tab swaps the composite-score chart for that feature's target(blue)/
  decoy(red) standardized distribution (the mProphet "Feature Scores" view) with a "back to
  composite" link. Verified on Stellar (SG-weighted cosine 44.2%; 21/21 features carry histograms).
- **Print-to-PDF (final stretch).** "Save as PDF" button + `@media print` (stacks all tabs, one
  section per page, forces the light ink-friendly palette, `print-color-adjust: exact`). Modeled on
  Brendan's UGM slide-deck DHTML. Headless `--print-to-pdf` -> valid 7-page PDF.

**Reprocess loop (both datasets, no --protein-fdr to match the target PNGs):**
`ai/.tmp/reprocess-mdiag.sh stellar|astral` clears FDR caches (keeps scores.parquet), runs Osprey
`--model-diagnostics --fdrbench <tsv> --fdrbench-pass 2`, then the compare tool. Screenshots:
`ai/.tmp/shot-mdiag.py <html> <outdir> <stem>` (headless Chrome, drives the tab/view/feature-click).
Outputs in `ai/.tmp/mdiag-shots/`.

### Review round 1 (2026-07-06, Brendan awake) - 8 fixes, commit `58d0afbd80`
All addressed + verified on Stellar (pass-2 still RESULT: MATCH; Debug gate green):
1+2. PDF now prints ALL per-feature distributions (21) + all 4 FDR views (print-only blocks;
   17-page PDF). 3. Composite "decoy normal" legend is a working toggle. 4. Feature table
   defaults to best-fit height + Show-all/Best-fit toggle so the score plot stays visible.
   5. Competition legend toggles the real/entrapment bands. 6. Per-file summary table gained an
   Entrapment column (Targets now excludes entrapment). 7. Dropped the confusing delta-mu column.
   8. Red rows now = unexpected coefficient direction (IsReversedScore XOR coef<0), not negative %;
   RT-difference(abs) with negative weight correctly no longer flagged. Astral regenerating with
   the fixes (background). Screenshots/PDF in ai/.tmp/mdiag-shots/.

### Review round 2 (2026-07-06, Brendan) - 7 UI refinements, commits `94c143ee39` + `b8c6b1634f`
1. Collapsed feature table now SCROLLS in place (overflow-y:auto), with a STICKY header row so
   the columns stay labeled; the Show-all/Best-fit toggle still expands to the full table.
2. Fixed the per-feature print-grid x-axis title ("standardized score") being clipped below the SVG.
3. Trimmed the red-row description (dropped the verbose idotp example).
4. Widened description blocks (max-width 70ch -> 105ch) to cut their height.
5. Capped the feature-contribution table width (700px) so labels sit next to the numbers.
6. Capped the per-file summary table width (640px) so it groups left instead of spanning the card.
All verified on Stellar (screenshots in ai/.tmp/mdiag-shots/). Both rounds were TEMPLATE-ONLY, so
both reports were regenerated from their on-disk data by re-splicing the template around the embedded
JSON -- NO re-search (demonstrates cheap "regenerate from disk" for pure UI changes). Release
rebuilt so the embedded template matches source.

### Review round 3 (2026-07-06) - dual model view + self-review fixes, commit `cecb77d052`
- **2nd-pass model view.** With `--protein-fdr`, Percolator retrains on the post-reconciliation
  reported pool (Pass2FdrSidecar's 2nd Percolator, ~242K entries). That model is now captured
  (`Pass2FdrSidecar.ComputeAndPersist` returns its FeatureContributions -> MergeNodeTask ->
  `ModelDiagnosticsData.BuildModelPass2`) and the Model tab gains a 1st-pass/2nd-pass selector
  that swaps the feature table + composite + per-feature distributions. Verified on Stellar
  `--protein-fdr 0.01`: the two models differ (SG cosine 44%->30% contribution) and pass-2 FDR
  shifts 0.90% -> **1.48%** (the protein-fdr recalibration inflation, as expected). Single-pass
  runs don't show the selector (backward compatible).
- **Self-review (fresh-context agent) findings addressed:** data sidecar now deleted in every
  path (was leaked with no entrapment); warn when the 1st-pass model wasn't retrained (resumed
  run) instead of a silent empty Model tab; histogram binning skips NaN std values. Deferred
  (documented): standalone `peptide_pair_index` enumeration-order dependence (harmless; flag for
  the byte-parity review).
- **Library-type robustness (in progress):** validating no-entrapment (target+decoy library ->
  FDR tab should drop) and gendecoy (Osprey-generated decoys, ~10-16% anti-conservative FDP ->
  Competition should show non-honest nulls). Runner: `ai/.tmp/run-libtypes.sh`.

## CURRENT STATE (2026-07-06) - feature complete, awaiting review sign-off, NOT pushed
Branch `Skyline/work/20260705_osprey_model_diagnostics` (pwiz-work2), clean tree, NOT pushed, no PR.
The `--model-diagnostics` HTML is a self-contained interactive report + PDF with:
- 5 tabs (Model, Density, FDR calibration, Competition, Summary).
- FDR calibration: pass-1 AND pass-2, experiment + per-run (4-view selector); pass-2 reproduces
  STOCK FDRBench by construction. **Both datasets RESULT: MATCH** -- Stellar pass2 0.90% / pass1
  2.01%; Astral pass2 0.88% / pass1 1.92% (targets 0.90/2.03, 0.87/1.89).
- Model tab: mProphet-style contribution table (red = unexpected coefficient direction),
  collapsible with sticky header, click a feature -> its target/decoy distribution.
- Save-as-PDF: 17-page complete report (all FDR views + all 21 per-feature distributions).
Debug gate green (452 tests, 0 warnings). Key commits: `9fd321cd38` (pass-2 + per-feature + PDF),
`58d0afbd80` (review 1), `94c143ee39` + `b8c6b1634f` (review 2). ai repo: compare-tool + TODO commits.

### NEXT STEPS
1. Await Brendan's next review; apply any further tweaks (template-only tweaks regenerate from disk).
2. When signed off: `/pw-self-review`, then push + open a PR (base master).
3. Trigger TeamCity `ProteoWizard_OspreyWindowsNetPerfRegressionTests` on `pull/<N>` (Astral legs).
4. Backlog: two-run `--model-diagnostics-compare` (library-impact q-q/Venn); `--fdrbench-pass 1,2`
   (emit both TSVs in one run); a true one-shot `--regenerate-diagnostics` (load scores.parquet,
   run only FDR math, emit HTML -- no flag/cache guesswork); strip the now-unused `deltaMu` JSON
   field; HTML-body localization; template ASCII cleanup.

### Regenerate cheaply (no re-search)
`bash ai/.tmp/reprocess-mdiag.sh stellar|astral` clears FDR caches (keeps scores.parquet), re-runs
Osprey with `--model-diagnostics --fdrbench <tsv> --fdrbench-pass 2` (Stellar ~2min resume; Astral
re-scores hram ~23min), then `Compare-Fdrbench-Html.py --pass 2`. For TEMPLATE-ONLY changes, re-splice
the template around the embedded JSON instead (instant). Screenshots: `ai/.tmp/shot-mdiag.py`.
Gotcha: FirstPassFDR must RETRAIN (clear 1st-pass sidecars) for the model table + per-feature
histograms; a bundle-rehydrate resume omits them.

**Still open / polish (deferred, not blocking):** ~~PDF's FDR page captures only the selected view~~ (FIXED)
(shows both passes would be nicer); disc count ~0.5% under the target PNG (known entrapment-regime
Percolator cross-build float sensitivity; FDP matches, so not a bug); template ASCII cleanup;
HTML-body localization. Next: push + PR when Brendan is happy, then trigger the manual TeamCity
Perf/Regression gate on `pull/<N>` for the Astral legs.
