# osprey: Surface single-peak multiple-ID co-assignment in --model-diagnostics

## Branch Information
- **Branch**: `Skyline/work/20260808_peak_coassignment_diagnostics`
- **Base**: `master`
- **Created**: 2026-08-08
- **Status**: In Progress
- **GitHub Issue**: [#4522](https://github.com/ProteoWizard/pwiz/issues/4522)
- **Module**: `osprey`
- **PR**: (pending)

## Objective

DIA search can assign two IDs to a single chromatographic peak without sequence-specific
differentiating evidence. Entrapment makes this measurable: an entrapment peptide sharing a peak
with a better-scoring target is a demonstrated false co-assignment.

Measured on a 40-file Astral cohort (TDP-43 plasma-EV, q <= 0.01), the target background sits at
4.3-5.1% of accepted precursors across all seven library variants -- roughly 1,200 accepted target
IDs per run on a peak a better-scoring same-mass precursor already explains. Entrapment is enriched
4.0-6.6x over that background in every arm.

This issue asks only to **surface the effect in the `--model-diagnostics` report**. What to do about
it is a separate question.

A precursor pair "shares a peak" when it is in the same run, at the same apex RT (+/- 0.05 min), and
within +/- 0.01 Da in precursor mass. No knowledge of the sequence relationship is required -- the
metric is pure geometry, which is why it finds relationships nobody thought to look for.

## Design (settled 2026-08-08 -- read this before re-deriving)

**Both passes are covered, and NEITHER needs the FDR score path touched.**

Pass 2 is what the user actually receives, so it is the one that must be covered; pass 1 is the
scoring/peak-assignment property the issue is about. Reporting both makes the **delta** the
interesting quantity -- reconciliation manufactures co-assignment by design (`MultiChargeConsensus`
pulls disagreeing charge states onto the leader's peak; `ForcedIntegration` gap-fills at a consensus
RT), so pass2 - pass1 is "how much did reconciliation add on top of scoring".

* **Pass 2**: `SecondPassFdrTask` already hands `WritePass2AndFinalize` the resident
  `RescoredEntries` pool -- real `FdrEntry` with `ApexRt` populated (`ParquetScoreCache.cs:809`,
  `:1284` on the survivor reload; `PerFileRescoreTask.cs:1545` on the rescore overlay), and O(survivors),
  not O(rows). A new builder call inside `BuildPass2`; nothing else.
* **Pass 1**: apex RT is NOT on the streaming path the report is built from -- `FdrProjection` was
  shrunk to 32 bytes (#4355) and the counts-only reader pulls only entry_id / charge / is_decoy /
  coelution_sum / modseq. Do NOT plumb it through the score pass. Instead do what the prototype did:
  a bounded per-file pass at report time over the two artifacts already on disk.

**The per-file pass-1 join (from `ai/scripts/Osprey/Entrapment/pass1_entrap.py`):**

| prototype | C# equivalent |
|---|---|
| `read_sidecar(stem + '.1st-pass.fdr_scores.bin')` | `FdrScoresSidecar.ReadRecords(path, Pass.First, onRecord)` -- already streams |
| `pq.read_table(stem + '.scores.parquet', ['entry_id','apex_rt'])` | `ParquetScoreCache` already reads `apex_rt` by name (`:790`, `:1226`) |
| parquet paths | `perFileParquetPaths[fileName]`, in hand in the method that writes the report |
| `sequence` / `protein_ids` -> mass, class | `libraryById` is resident at report time -- exact `PrecursorMz`, no sequence parsing |

Rows are positionally aligned between the sidecar and the parquet. **Assert it, do not assume it** --
the prototype checks full `entry_id` array equality per file and raises on mismatch; carry that check
over. One file resident at a time.

Why this over plumbing: no touch to `ReadFdrStubScalars` / `RowBuffer` / `Accept` /
`Accumulator.Add`, no 6-arg row callback, no perf-gate exposure, and it works on the
resident-projection path (`OSPREY_FDR_PROJECTION=0`) which the plumbing approach would have left
with NaN. Cost to name explicitly: re-reads two columns of every `.scores.parquet` at report time
(~340M rows on the 82-file Astral run). Opt-in behind `--model-diagnostics`; log the wall time so it
is visible rather than a silent tax.

**Deliberate deviations from the prototype (note them in the panel so the numbers do not silently
disagree with the issue):**
* Gate accepted on `EffectiveRunQvalue` at the configured `FdrLevel`, not the prototype's
  experiment precursor q, so the panel's denominators match the per-file / cross-run tables on the
  same page.
* Rank "better-scoring" by SVM score, not q -- it is the same ordering in practice and it gives the
  offenders listing a real score gap.
* At report time the pass-1 sidecar holds PARTIAL records (run_protein_qvalue = 1.0 placeholder;
  first-pass protein FDR patches [52..60] later). The panel uses precursor/peptide q and score only,
  so this is fine -- but say so in a comment, because the prototype read a fully-patched sidecar.

**Match on precursor m/z, NOT the prototype's neutral peptide mass.** This is a deliberate change
from `peak_coassignment.py` and it removes a workaround rather than adding one.

The prototype computes neutral mass from the sequence (`sum(AA) + H2O`) and compares regardless of
charge. Under neutral mass the 2+ and 3+ of ONE peptide are identical in mass and identical in apex
RT, so they match trivially - which is the only reason its `if s2 == seq` sequence-exclusion guard
exists. Match on m/z and that pair is e.g. 800.4 vs 533.9, nowhere near +/-0.01, so the artifact
cannot arise and the guard is unnecessary.

Better on three counts:
* Co-isolation is an m/z-window property. Two precursors of equal neutral mass at different charges
  sit in different isolation windows and are not on one peak in any meaningful sense.
* The `s2 == seq` guard also discarded REAL co-assignments - same sequence at the same charge is the
  most co-assignable case there is, and any modified/unmodified pair sharing a base sequence went
  with it.
* No mass computation at all: `LibraryEntry.PrecursorMz` is exact and resident. No AA table, no
  modified-sequence parsing, no residue-mass drift against the library.

The only exclusion that remains is a precursor against ITSELF, which pass 1 needs because the
pre-compaction pool holds several rows per precursor per file (different scans / candidate peaks):
reduce to best-row-per-precursor-per-file, then exclude self by `modseq|charge`.

Consequence to state in the panel, not bury: the numbers are then not strictly comparable to the
issue's table. Neutral-mass matching also paired different sequences at different charges that
happened to share a mass; m/z matching drops those. The dominant population (isobaric pairs at the
same charge - the ortholog and I/L cases) matches identically under both, so the headline rates
should move little.

**No existing gate to integrate with.** Nothing in either tree (C# or Rust) attempts to stop two
different sequences from claiming one peak; verified 2026-08-08. `MultiChargeConsensus` /
`select_post_fdr_consensus` group by modified sequence only; the decoy generator's fragment-overlap
gate (`DecoyGenerator.IsCandidateAcceptable`) is target-vs-its-own-decoy at library build time; all
"interference" handling in scoring is intra-precursor (does one precursor's own fragments agree).
The 5% is the absence of a filter, not a broken one.

## Opt-in tokens: BUILT, MEASURED, THEN REMOVED (settled 2026-08-10)

**The mechanism below was implemented and then deleted. Do not rebuild it without a measurement.**

Measured on the StellarGenDecoyEntrap gate leg: the pass-1 apex-RT recovery ran
**0.4 s over 2,937,383 pre-compaction rows = 7.3M rows/s**. Extrapolated to the 82-file Astral run
(~340M rows) that is **~46 seconds against a 10-hour search - 0.13%**. The perf premise the opt-in
rested on was wrong by two orders of magnitude; the "second pass over every pre-compaction row"
framing was pattern-matched from the SCORING path, but this is a 12-byte-per-row sequential read.

Brendan's call, and the better argument: anyone who asks for `--model-diagnostics` wants the
diagnostics, not a decision about which ones they can afford. A panel behind a token is a panel
nobody sees - which defeats a diagnostic whose entire purpose is surfacing an effect users do not
know to look for. `--model-diagnostics` shows everything we know how to show, and there is
deliberately no `--model-diagnostics all` to have to remember.

What was removed: `ModelDiagnosticsFeatures`, `OspreyConfig.ModelDiagnosticsPanels` /
`HasModelDiagnosticsPanel`, the optional-value lookahead in `TokenizeAndDispatch`, and the
`DiagnosticsPanels` field in `regression.ps1` (so all four legs now exercise the panel).

<details><summary>The token design as built, kept for whenever a panel genuinely warrants it</summary>

## Opt-in tokens on --model-diagnostics (superseded)

Expensive panels are opt-in BY NAME, not by level:

```
--model-diagnostics                       standard report (unchanged cost)
--model-diagnostics peak-coassignment     + the named panel
--model-diagnostics all                   + every expensive panel this build has
```

**Tokens, not a level, and the reason is already written down.** `ResidentPaths` records why
`OSPREY_ALLOW_UNFIXED_RESIDENT=<token>` replaced the blanket `OSPREY_ALLOW_UNBOUNDED_MEMORY=1`: a
single switch "grants amnesty to every trigger at once, so it cannot distinguish the one path we
know is unfixed from a path that silently regressed" - and it didn't: `OSPREY_PASS2_QVALUE=transfer`
regressed onto the resident pool for ten days unnoticed. A `--model-diagnostics full` level is that
same blanket switch one notch up: it would silently start doing more work every time a panel is
added. A token names what you are paying for and appears verbatim in the run log.

**Same shape, opposite direction, so a separate class.** `ResidentPaths` is amnesty for known
defects and may only SHRINK; `ModelDiagnosticsFeatures` is a menu of working features and is
expected to GROW. Keeping them apart stops the ratchet semantics from being muddled.

Details: bare flag stays the default so no existing command line silently gets slower; an unknown
token is a HARD error listing the legal values (a silently-ignored typo looks exactly like a panel
with nothing to report); `all` is documented as explicitly NOT stable across versions.

**Gate consequence, handled.** `regression.ps1` passes a bare `--model-diagnostics` on 3 of 4
datasets, so an opt-in panel would ship untested by `DiagnosticsGolden.ps1`. The spec now takes a
`DiagnosticsPanels` field and `StellarGenDecoyEntrap` sets it to `peak-coassignment` - the only leg
with generated decoys AND retained entrapment, so it is the only one where the panel has a
non-empty entrapment row. One leg is enough for the golden to catch a regression, and it keeps the
gate's wall clock honest.

</details>

## Measured results (first end-to-end run, StellarGenDecoyEntrap, 2026-08-10)

**Stellar independently reproduces the effect** - a different instrument, sample and library from
the Astral cohort the issue measured:

| scope | target | entrapment | enrichment |
|---|---|---|---|
| run-level q <= 1% | 1.18% (301/25,486) | 5.17% (14/271) | **4.4x** |
| experiment-wide q <= 1% | 2.23% (517/23,135) | 9.55% (15/157) | **4.3x** |

**The pass-1 -> pass-2 direction is the opposite of what was predicted.** An earlier version of the
code comments asserted pass 2 would be HIGHER because reconciliation manufactures co-assignment.
Measured: rates FALL (target 2.17% -> 1.18%, entrapment 6.80% -> 5.17%) because compaction drops
the weaker competitor - while ENRICHMENT RISES, 3.14x -> 4.37x, because the reported pool sheds
co-assigned targets faster than co-assigned entrapment. Comments corrected; the enrichment delta is
the quantity to watch, not the rate.

## Defects found only by looking at real output (fixed 2026-08-10)

1. **Offender rows were per-observation, not per pair.** `TTISVAHLLAAR(3) <- VHIGQVIMSIR(3)`
   printed twice from two files. Now one row per precursor pair carrying a `Runs` count, with the
   worst single observation's detail. A pair co-assigned in 31 of 40 runs is one finding, and the
   run count is the more damning number anyway.
2. **Tiny denominators produced alarming nonsense.** Experiment-scope decoys were n=7, and 1 of 7
   rendered as **6.4x enrichment** - visually indistinguishable from the 5.7x that took a 40-file
   cohort to establish. `MIN_N_FOR_ENRICHMENT = 30` now suppresses the ratio (NaN), set below the
   ~95-144 entrapment precursors real entrapment arms carry.
3. **Ladder entries at 0.01 and 0.02 min are identical** (0.5%, 0.5%). Not a bug - it is the
   scan-grid quantization the |dRT| histogram shows - but the panel must say so or it looks broken.
   TODO for the HTML work.

**The diagnostics golden did not cover the panel at all.** `Get-DiagnosticsMetrics` pins an EXPLICIT
metric list, not an enumeration of the payload, so a new card is invisible to it - the earlier
`mode1b (diagnostics vs golden): PASS` would have passed identically had the panel emitted garbage.
Co-assignment n / nBetter / enrichment are now pinned at both passes and both q scopes.

## BLOCKER: the decoy class is not correct yet (2026-08-10)

**Targets and entrapment are fine and unchanged** - gated on their own q, matching the report's own
per-file table. **Only the decoy row is wrong.** Do not open a PR until it is right; do not "fix" it
by another guess.

**What decoy inclusion must be** (Brendan): decoys have no meaningful q - they are the basis on
which q is computed - so they cannot be gated on their own q. Include a decoy when its score clears
the acceptance boundary: the lowest score among the included target/entrapment set. And for the
EXPERIMENT scope that comparison must be in **experiment aggregate score** terms, not per-run
scores.

**Expected answer** (so the next attempt is falsifiable): at experiment q <= 1% with 23,135 targets
+ 228 entrapment accepted, q ~ decoys/targets means about **233 decoys** above the cutoff. An
independent count straight from the sidecars (`run_prec_q <= 0.01`) gives **598 unique decoy
precursors** at run scope and **293** at experiment scope. The panel should land in that region.

**Three attempts, all wrong, all measured:**

| attempt | pass1 run | pass1 exp | pass2 run | pass2 exp |
|---|---|---|---|---|
| 1. gate decoys on their own q | 19 | 15 | 415 | 7 |
| 2. cutoff = min score over accepted ROWS | 96 | 43,528 | 36,228 | 43,475 |
| 3. cutoff = min over accepted PRECURSORS, per-scope aggregate | 96 | 72 | 36,228 | 36,133 |

Attempt 2's failure is understood and the fix was right: pass 1 is pre-compaction, so an accepted
precursor carries many rows including poor candidate peaks, and the min over rows sits far below the
boundary. Attempts 1 and 3 are NOT understood - that is the problem.

**Next session: diagnose, do not iterate.** Each attempt costs a ~5 minute regression leg, and three
have now been spent on hypotheses. Get the root cause first:

* The two paths disagree by ~400x on the same quantity (pass1 96 vs pass2 36,228), so at least one
  of `PeakCoAssignmentSource` (streaming, sidecar-driven) and `BuildCoAssignment` (resident pool) is
  computing a different cutoff from the other. Instrument BOTH cutoffs - log the score value and the
  count of accepted precursors that produced it - before changing any logic.
* Suspect for pass 2 being far too permissive: the post-compaction pool contains entries whose
  `Score` was zeroed by `FdrEntry.ResetScores` (Stage 6 rescore targets, gap-fill stubs). If any of
  those is "accepted", the cutoff collapses to ~0 and admits nearly every decoy. Check before
  assuming.
* Verify against the offline sidecar computation in the transcript (numpy over
  `.1st-pass.fdr_scores.bin`), which is independent of the C# entirely.

**Then**, once the count is right, the measurement Brendan actually wants: of the decoys above the
cutoff, how many share a peak and how many with a BETTER-scoring target.

**Carry this caveat into that work.** A generated decoy is its target's sequence reversed, so it has
the SAME composition, mass and precursor m/z as its own twin. Its twin is therefore a guaranteed
same-m/z partner, which entrapment never has. The decoy co-assignment rate is structurally inflated
relative to entrapment and the two are not comparable as they stand. Split the decoy column into
**co-assigned with its own twin** (how often a decoy rides the real peptide's peak - an FDR
calibration finding, and the more interesting one) vs **co-assigned with an unrelated target** (the
figure comparable to entrapment). A base-id equality test at the match site is all it needs.

## Tasks

- [x] Locate the Stage 5 `--model-diagnostics` report generation and the per-file apex RT source
- [x] Confirm which RT source is the true per-run detection -- pass 1 (pre-compaction detection);
      pass 2 is post-reconciliation and is reported alongside as the delivered-to-user number
- [x] Pure builder in Osprey.FDR over per-file (apexRt, m/z, score, key, class) rows, shared by
      both passes (`ModelDiagnosticsData.CoAssignment.cs`)
- [x] Pass-1 per-file sidecar + parquet join at report time, with the entry_id alignment assert
      (`PeakCoAssignmentSource.cs`)
- [x] Pass-2 build from the resident `RescoredEntries` pool (`BuildPass2`)
- [x] Compute co-assignment: % of detected precursors sharing a peak with a better-scoring same-m/z
      precursor, reported separately for targets, entrapment, and decoys
- [x] Report at BOTH q scopes (run-level and experiment-wide), matching the rest of the report
- [x] Report the enrichment ratio entrapment/target and decoy/target
- [x] Add a dRT histogram for co-assigned pairs, over the full 0.25 min scan window (NOT truncated
      at the headline tolerance, which would hide the jitter-vs-chance shape)
- [x] Add a listing of the worst offenders (co-assigned pairs ranked by score gap), bounded
- [x] Flag PTM positional isomers (`SameBaseSequence` / `NBetterSameBaseSequence`) so the
      "would go away under best-match-wins" count can be read net of pairs that may BOTH be real
- [x] Tolerance ladder (0.01 / 0.02 / 0.05 / 0.10 / 0.25) from one scan, so the sensitivity is
      visible rather than baked in
- [x] Opt-in token gating (see above)
- [x] Unit tests: hand-computed co-assignment fixture + token parser (576 tests green, 0 warnings)
- [x] HTML panel in the report template - **Competition tab, BELOW the paired decoy-win coinflip
      card** (Brendan: the coinflip stays on top). Q-driven, so `renderCoAssignment` is called
      before `renderCompetitionTab`'s `hasStructural` early-returns and still renders under pass-2
      confidence transfer, where the coin above degrades to an n/a note. Card hides itself entirely
      when the panel is absent: a zero rate and "could not measure" are different claims.
      Contents: scope toggle (run / experiment q), KPI row, per-class table with the
      best-match-wins reading and the PTM-isomer caveat, |dRT| histogram over the full scan window,
      tolerance-ladder chart + table, and the per-pair offender listing with run counts.
- [ ] Report the pass1 -> pass2 delta in the panel (how much co-assignment reconciliation adds)
- [ ] `regression.ps1 -Dataset Stellar`, then `-Dataset All`; capture the real memory/wall numbers
      with `--memstamp` and replace the estimates below

## Caveats to carry into the implementation

- **RT tolerance sensitivity.** Entrapment is enriched at every tolerance tested, but the magnitude
  depends on it: 2.3x at +/-0.01 min, 2.9x at +/-0.02, 5.7x at +/-0.05, 4.3x at +/-0.10, 3.4x at
  +/-0.25. The +/-0.05 figure is physically motivated (it matches the observed same-feature apex
  jitter of 0.046 min) but it also maximises the ratio, so the honest headline is a range. The dRT
  histogram makes the choice visible.
- **The set-wise isobaric gate reduces entrapment co-assignment but not the target background**
  (issue comment). It moved entrapment enrichment 6.6x -> 3.7x (shuffle) and 5.7x -> 4.2x (foreign),
  and moved the target background not at all. That gate has since been reverted as too broad, so
  shipping libraries sit at the `-no-il` row (I/L filter only), where entrapment enrichment is
  5.7-6.6x.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test
- **Fails on master**: (pending)
- **Passes on fix**: (pending)

## References

- Prototype: `ai/scripts/Osprey/Entrapment/peak_coassignment.py` (takes a `pass1_entrap.py` arm JSON)
- Measurement series: `ai/todos/active/TODO-20260801_decoy_similarity_gate.md`

## Progress Log

### 2026-08-08 - Session Start

Starting work on this issue. Created branch and TODO; next step is locating the
`--model-diagnostics` report generation and the per-file apex RT source in Osprey.
