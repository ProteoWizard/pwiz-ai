# TODO-osprey_model_diagnostics_cross_run_detection_consistency.md -- Add cross-run detection-consistency plots (reproducibility) to the --model-diagnostics report

## Status
**COMPLETED — shipped in #4408** (merged 2026-07-11, "added cross-run reproducibility graphs").
The `CrossRunDetection` data class (`CumUnion` / `CumIntersection` / `RunCountHistogram` /
`AtLeastHalf`) and both plots landed in `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs`
(+ `ModelDiagnosticsDataTest.cs`) and the report template, in an always-present tab (report
Bug B fixed alongside). The design below is retained for reference.

_Originally: backlog (created 2026-07-09), requested by Brendan for a future self-run sprint._
Sibling of [[TODO-osprey_model_diagnostics_null_alignment_decoy_qc]] and
[[TODO-osprey_model_diagnostics_training_pool_distributions]] -- another
`--model-diagnostics` panel, but this one is **entrapment-free**: it reads FDR quality
off of cross-run detection reproducibility alone, so it works on the ordinary
target+decoy libraries most users run.

**Motivating case (fresh, concrete):** the 2026-07-09 SEA-AD Pilot-MTG Astral run
(see [[project_sead_pilot_mtg_dataset]]). The full-entrapment (r=1.0) search produced a
degenerate FDR -- experiment-wide q floored at 2.5%, one input file (0002) reported 0
IDs, 0 reported at 1% -- while the decoy-only search on the same data reported a healthy
~49K peptides. The entrapment oracle exposed it, but **most users have no entrapment
library.** These two plots would have flagged the same failure without entrapment: a run
that is quietly passing false precursors shows up as an inflated "detected in only 1 run"
bump and a collapsing all-runs intersection. This is the "when FDR control is struggling"
signal Brendan wants surfaced for the no-entrapment case.

Ties into the two report bugs found the same day (keep them in mind when placing these
panels): (A) the Identification-yield chart does not switch with the experiment-wide /
per-run selector; (B) the entire FDR tab -- and with it the yield chart -- is hidden when
`!D.hasEntrapment` (`model-diagnostics-template.html` line ~303). **These new plots are
entrapment-independent and MUST live in an always-present tab**, not behind the entrapment
gate. Consider fixing (B) as part of this sprint so yield + these plots share one
always-on home (e.g. a new "Reproducibility" tab, or fold into Summary).

## The two plots (from Brendan's R prototypes; screenshots in ai/.tmp/screenshots 2026-07-09 2142/2143)

### Plot 1 -- "Precursor Detections by Run" (bars + 3 overlays)
X = run number in **input-file order** (1..N). Y = detections (precursors passing the
reported run-level FDR), in thousands.
- **Bars**: per-run detected-precursor count. Annotate mean + stddev (prototype showed
  mean 31k, stddev 5.1k over 21 runs).
- **(a) cumulative union** (orange line): |union of detected precursors over runs 1..i|
  -- total UNIQUE precursors seen so far. Monotone up; label the final value (proto 45k).
- **(b) cumulative intersection** (dark line): |intersection over runs 1..i| -- precursors
  detected in EVERY run so far. Monotone down; label the final value (proto 15.2k). The
  gap between (a) and (b) is the reproducibility spread; a fast-collapsing intersection or
  a runaway union is the FDR-trouble tell.
- **(c) at-least-half line** (red dashed, horizontal): count of precursors detected in
  >= ceil(N/2) runs. Label "at least K (of N) - <value>" (proto "at least 10 (of 21) -
  31.6k").
- **(optional) CV<20% line** (dash-dot, horizontal): precursors whose cross-run quant CV
  < 20%. Needs a quant value per (precursor, run); if the reported pool doesn't carry
  quant yet, defer this line (proto value 1.5k). Decide during the sprint.

### Plot 2 -- histogram: precursors by number of runs detected in
X = run count k (1..N) = how many runs a precursor is detected in. Y = frequency (number
of precursors). Expected healthy shape is J/U: a right peak at k=N (reproducible real
precursors) and a modest left bump at k=1. **A growing left (k=1) bump is the
FDR-struggling signature** -- false precursors don't reproduce, so they pile up at low k.
Prototype (21 runs): ~3.8k at k=1, flat ~1-1.5k for k=2..19, sharp rise to ~14.5k at
k=20/21.

## Why these are the right entrapment-free QC
Real precursors reproduce across replicate runs; FDR-escaping false precursors do not.
So both plots read the false-discovery structure directly from run-to-run membership,
with no decoy/entrapment model assumption. They complement the existing entrapment FDP
calibration (which needs an entrapment library) and the decoy null-alignment panel.

## Implementation sketch

### Data side -- `Osprey.FDR/ModelDiagnostics/ModelDiagnosticsData.cs`
Build from the **reported** precursor set (post-reconciliation, the pool that passes the
run-level FDR per file) -- the same source the Summary tab's per-file passing counts use.
Precursor identity key = (ModifiedSequence, PrecursorCharge). Add a data class, built
**unconditionally** (not gated on `HasEntrapment`):
```
public sealed class CrossRunDetection {
    public string[] RunNames;        // input-file order
    public int[]    PerRunCount;     // bars
    public int[]    CumUnion;        // (a) |union 1..i|
    public int[]    CumIntersection; // (b) |intersect 1..i|
    public int      AtLeastHalf;     // (c) precursors in >= ceil(N/2) runs
    public int[]    RunCountHistogram; // index k-1 => #precursors detected in exactly k runs
    public double   MeanPerRun, StdPerRun;
    // optional: public int CvUnder20;   // needs per-(prec,run) quant
}
```
Compute once by walking the reported precursors and, for each, the set of run indices it
appears in. RunCountHistogram is the tally of |run-set| over precursors. Cumulative
union/intersection require the per-run detected sets in input order (keep them transiently;
only the counts are emitted). Wire it onto the top-level data object next to `IdYield`.

### Template side -- `Osprey.Tasks/ModelDiagnostics/model-diagnostics-template.html`
Add two `chartbox` cards in an always-present tab. Reuse the existing SVG helpers
(`svg()`, `E()`, `axes()`, `legend()`, tooltip via `showTip`) -- see the ID-yield chart
(~line 718) and win-fraction chart (~line 728) for the pattern (bars + overlaid polylines
+ horizontal reference lines + a legend with the same look as `fdpLegend`). Plot 1 = one
bar series + three polylines/hlines; Plot 2 = a simple histogram (reuse the bar drawing).
Label the terminal values of union/intersection and the two horizontal lines as in the
prototype.

### Placement / gating (do together with report Bug B)
Do NOT put these under the `data-tab="fdr"` section (hidden without entrapment). Either
add a new `data-tab="repro"` section registered in the `TABS` array (line ~300) with no
entrapment guard, or move both these + the Identification-yield card into Summary. Update
the `TABS` list and the tab-visibility loop accordingly.

## Open decisions for the sprint
- Identity key: (ModifiedSequence, charge) vs stripped-sequence -- pick and document.
- Run order for the cumulative curves: input-file order (matches the prototype) -- confirm.
- CV<20% line: include only if a per-(precursor, run) quant is available in the reported
  pool; otherwise ship Plot 1 with the three count-based series and add CV later.
- Interaction with report Bug A/B (view selector + entrapment gating) -- fold the gating
  fix in so these panels are always visible.
