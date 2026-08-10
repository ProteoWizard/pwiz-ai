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

## RESOLVED (2026-08-10, later session): pass 1 now reproduces the oracle exactly

**Pass 1 is correct and cross-checked. Pass 2 is NOT - see the #4553 section below; it is
somebody else's bug and is being fixed on another branch.**

Final pass-1 numbers, StellarGenDecoyEntrap 3-file, C# panel vs the independent Python oracle -
**all twelve agree**:

| scope | class | detected | outscored | C# == oracle |
|---|---|---|---|---|
| run | target | 31,103 | 678 | yes |
| run | entrapment | 455 | 32 | yes |
| run | decoy | 675 | 94 | yes |
| experiment | target | 28,698 | 964 | yes |
| experiment | entrapment | 228 | 27 | yes |
| experiment | decoy | 468 | 95 | yes |

Acceptance boundary logged by the panel itself: experiment 0.0120 from 28,926 accepted
precursors, 468 decoys clearing it, 468 tallied.

**It took FOUR defects, two of them in the oracle and the harness rather than the panel.** The
attempts table below is preserved because the reason those attempts failed was never the rule -
it was that the numbers being read came from somewhere else.

1. **The regression harness overwrote the report being measured.** `regression.ps1` runs mode 5
   (rehydrate) into the SAME output directory as the straight run, so
   `output.model-diagnostics.html` is replaced by the rehydrate build before anyone reads it.
   Every number in the attempts table below (96 / 72 / 36,228) is the REHYDRATE page. Use
   `-SkipRehydrate` when measuring the straight-through panel, or read `straight.log` rather
   than the HTML.
2. **Two implementations of the pass-1 panel, and the wrong one won the file.** The streaming
   path builds it from the pre-compaction sidecars (`PeakCoAssignmentSource`); the rehydrate
   path built it from the resident `perFileEntries` pool. That pool is POST-compaction - the
   remarks on `LogFirstPassResultsAndDump` already said so: it "has already lost the ~52x
   non-survivors - mostly the decoys", so building the report off it "would silently produce a
   plausible WRONG page". The panel was added after that comment and did exactly that. Both
   agreed on the boundary (0.0120) and the accepted count (28,926) and still reported 72 decoys
   against 468, because compaction had already dropped the rest - target denominators intact,
   decoy class quietly gutted. **Fixed**: the rehydrate path now calls `PeakCoAssignmentSource`
   too. One implementation, verified identical on both paths in one run.
3. **The precursor key merged each decoy into its target.** The key is the LIBRARY entry's
   modified sequence + charge, and a decoy's library entry carries its target's sequence, so an
   untagged decoy key was byte-identical to its target's. The precursor registry keeps the first
   arrival and skips the rest, so 396 of 468 admitted decoys were absorbed silently. The
   `|decoy` tag was only applied on the base-id fallback path. **Fixed** in both builders, keyed
   on the decoy BIT so the fallback and own-entry cases are covered by one rule.
4. **The Python oracle's decoy m/z was wrong by ~510 Da.** Decoy modified sequences are
   `DECOY_<target>`; `mz_of()` stripped bracketed mods then walked the remaining characters as
   residues, so D + E + C + Y were ADDED to every decoy's mass. No decoy ever fell inside a
   +/-0.01 m/z window. That is what the "1,470,828 rows had an unparseable modification" warning
   was - the decoys. **Fixed** (`DECOY_PREFIX` strip). This one matters beyond the tooling: see
   the corrected finding below.

### Instrumentation kept, deliberately

The panel logs its acceptance boundary, the accepted count behind it, and an
admitted-vs-tallied check that warns when the decoy row is under-reported. The decoy row is the
only class gated by score rather than by its own q, so it is the only one with no independent
check on the page; a boundary that drifts produces a plausible number rather than a visible
failure. That comparison is the check.

<details><summary>Historical: the three failed attempts and the reasoning at the time</summary>

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

**ROOT CAUSE (Brendan, 2026-08-10): the sidecar persists ONE composite score for FIVE q-values.**

```
FdrScoreRecord: EntryId, Score, RunPrecursorQvalue, RunPeptideQvalue,
                ExperimentPrecursorQvalue, ExperimentPeptideQvalue, Pep, RunProteinQvalue
```

`Score` is the per-row SVM discriminant. The EXPERIMENT-WIDE aggregate that
`PercolatorQValues.ComputeExperimentPrecursorQMap` actually competes on is never written, and there
is nothing for the peptide or protein levels either. `FdrEntry` carries the same single `Score`, so
the resident pass-2 path is no better off. Every attempt above therefore built the experiment-scope
cutoff from a quantity that is NOT the one its q came from - in both paths. That is why attempts 1
and 3 were never going to work, and it is the thing to fix.

Note the trap: even reconstructing the aggregate, `max()` across runs is only the DEFAULT roll-up.
Under `OSPREY_EXPERIMENT_AGG` mean-best-N it is the mean of the best N per-run scores, so a
max-based cutoff is silently wrong on exactly the arms where the aggregation is under study.

Two ways forward; the second is preferred:

1. Reconstruct the aggregate inside the panel, branching on `OspreyEnvironment.ExperimentAggMeanBest`
   and mirroring `TargetDecoyCompetition.ComputeBaseIdMeanBestN`. Duplicates pipeline logic in a
   diagnostic and drifts the moment the aggregation changes.
2. **Persist the composite score PER Q LEVEL in the sidecar** - the score each q was computed from,
   beside that q. Then any consumer gates correctly by construction, this panel included, and
   mean-best-N needs no special case. A record-layout change (format version, writer, readers,
   golden), so it is its own piece of work and probably its own issue - NOT something to bolt onto
   this branch.

Until one of those lands, the decoy row cannot be right. Consider shipping the panel with the decoy
class suppressed and a note, rather than a number nobody can trust.

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

**Why this measurement matters** (Brendan, and it corrects an earlier note here): decoy and
entrapment score distributions matching is the assumption the FDR statistics rest on. This panel can
test whether they also match in CO-ASSIGNMENT behaviour, and whether either matches the false-target
distribution - which is where false-targets and entrapment appear to deviate, and why the panel is
interesting. The expectation is that decoys track entrapment; if they do not, that is a more
interesting result still. Either reading needs the decoy accounting to be correct first.

**A previous version of this file claimed decoys have a same-m/z twin that entrapment lacks, and
that the decoy rate is therefore inflated and not comparable. That is WRONG - do not act on it.**
The entrapment peptides are SHUFFLED versions of a source peptide, i.e. anagrams, so they carry the
same composition, mass and precursor m/z as their source exactly as a reversed decoy does. Decoys
are reversals of both targets and entrapment. Both classes pass the same spectral-similarity
filters, and library decoys additionally carry Carafe-predicted spectra and RTs. There is no
asymmetry here, and the decoy and entrapment co-assignment rates ARE directly comparable.

If a decomposition is still wanted, it is a SYMMETRIC one applied to both known-false classes: was
the co-assignment partner the sequence this precursor was derived from (same composition by
construction), or an unrelated target? That is a base-id / source-peptide test at the match site,
and it means the same thing for entrapment and decoys.

</details>

## CORRECTED FINDING: decoys co-assign ABOVE entrapment, not below (2026-08-10)

**The earlier headline in this file - "decoys do NOT track entrapment; they co-assign at
0.27-0.45x, BELOW the targets they model" - was an artifact of the oracle's broken decoy m/z
(defect 4 above) and must not be quoted.** With the `DECOY_` prefix stripped, the oracle and the
C# panel agree exactly:

| class | run rate | vs target | experiment rate | vs target |
|---|---|---|---|---|
| target | 2.18% | 1.00x | 3.36% | 1.00x |
| entrapment | 7.03% | 3.23x | 11.84% | 3.53x |
| decoy | 13.93% | **6.39x** | 20.30% | **6.04x** |

**Do not quote these either, yet.** The three classes are not measuring the same thing. A
reversed decoy is an anagram of its target, so it carries the target's precursor m/z EXACTLY,
by construction - and both implementations exclude only a precursor matching ITSELF (by entry
id). A decoy landing on its own target's peak therefore counts as co-assignment, and satisfying
the m/z half of the test costs it nothing. The same holds for shuffled entrapment against its
source peptide. The target rate has no such twin: a target can only co-assign by coincidence.

So the decoy and entrapment rates are (coincidence + construction) and the target rate is
(coincidence), and the enrichment ratios divide one by the other. **The next measurement is the
symmetric split described just above** - partner-derived-from-me vs partner-unrelated - applied
to both known-false classes. Agreed with Brendan 2026-08-10. Machinery already exists:
decoy-to-own-target is `partner.EntryId & BASE_ID_MASK == row.EntryId & BASE_ID_MASK`;
entrapment-to-source needs `pairByBaseId`, which `BuildClassificationFromLibrary` already
produces; and `NBetterSameBaseSequence` is the precedent for the extra column.

## SUPERSEDED: the offline estimate below (2026-08-10, StellarGenDecoyEntrap 3-file)

**Its decoy rows are wrong** - this is the run that produced the 0.27x / 0.45x figures from the
broken decoy m/z. Target and entrapment rows are unaffected and match the final numbers. Kept
for the record only. The script has since been fixed and additionally gained `--use-persisted`,
which drives its accounting off the panel's own `experiment_aggregate_score` instead of
recomputing `max()`; identical output either way is what proved the persisted field is a correct
and sufficient input to the rule.

<details><summary>Superseded offline estimate</summary>

Computed by `ai/.tmp/coassign_decoy_estimate.py` - deliberately INDEPENDENT of the C# panel, whose
decoy count is still wrong. Reads the run's own sidecars + parquet, applies the score-cutoff rule,
and uses max() across runs as the experiment aggregate (correct for the DEFAULT aggregation, which
these runs use; wrong under OSPREY_EXPERIMENT_AGG mean-best-N).

Acceptance boundary (lowest accepted target/entrapment composite score): run -0.1996 / -0.2047 /
-0.1532 per file; experiment +0.0120.

| scope | class | detected | shares a peak | outscored | rate | vs target |
|---|---|---|---|---|---|---|
| run | target | 31,103 | 1,245 | 678 | 2.18% | 1.00x |
| run | entrapment | 455 | 36 | 32 | **7.03%** | **3.23x** |
| run | decoy | 675 | 5 | 4 | **0.59%** | **0.27x** |
| experiment | target | 28,698 | 1,733 | 964 | 3.36% | 1.00x |
| experiment | entrapment | 228 | 28 | 27 | **11.84%** | **3.53x** |
| experiment | decoy | 468 | 8 | 7 | **1.50%** | **0.45x** |

**The finding: decoys do NOT track entrapment.** Entrapment co-assigns at 3.2-3.5x the target base
rate; decoys co-assign at 0.27-0.45x, i.e. BELOW the targets they are meant to model. If the FDR
statistics assume the decoy and entrapment distributions match, this is the axis on which they do
not - and it is the deviation the panel exists to surface.

Robust to the m/z approximation below: an earlier run with more unresolved modification masses gave
entrapment 3.78x / 3.84x and decoy 0.33x / 0.71x. The direction and magnitude barely moved.

**Caveats - do not quote these as final:**
* 1,470,828 rows still have an unparseable modification, so their m/z is approximate. The UniMod
  accession forms now resolve; something else (non-standard residues?) does not. Fix before quoting.
* Decoys come to 2.14% (run) / 1.62% (experiment) of the target+entrapment set where ~1% is expected
  by construction, so the acceptance boundary is slightly too permissive. "Accepted" here is ANY row
  with q <= cut rather than the best-per-precursor q, which widens the set.
* 3 Stellar files. Needs a real dataset (SEA-AD, 82 files, ~1:1 entrapment) to mean much.

</details>

## SIDECAR v4: the experiment aggregate score is now persisted (2026-08-10)

Brendan's call, after the analysis in this file said the sidecar "persists ONE composite score
for FIVE q-values": persist the score, one field, in BOTH C# and Rust.

**What was added**: `experiment_aggregate_score`, appended at `[60..68]`. Record 60 -> 68 bytes,
format version 3 -> 4. Appended at the END specifically so every v3 offset is unchanged and
`PatchRunProteinQvalues`'s `[52..60]` patch needs no modification.

**Only ONE field, not five.** Re-deriving what each q actually competes on showed the deficit was
narrower than this file claimed:

| q value | score its competition ranks on | persisted before? |
|---|---|---|
| RunPrecursorQvalue | the row's own `Score` | yes - it IS `Score` |
| RunPeptideQvalue | max over the peptide's rows in that file | no (derivable) |
| **ExperimentPrecursorQvalue** | **per-entry roll-up across runs** | **no - the gap** |
| ExperimentPeptideQvalue | max over the peptide's precursors of that roll-up | no |
| RunProteinQvalue | protein-level score | no |

Run scope needed nothing. Only the experiment aggregate is both non-derivable AND requires
branching on `OSPREY_EXPERIMENT_AGG` to rebuild - which is the drift hazard. Peptide- and
protein-level scores have no consumer; adding them would have cost +53% on a file that is ~20 GB
at 82 files, against +13% for one.

Producer is single-sourced with the q-maps it sits beside:
`PercolatorQValues.ComputeExperimentAggregateScoreMap` (flat/resident) and
`StreamingFdr.StreamingFirstPassQ.BuildExperimentAggregateScoreMap` (streaming), both reading the
same `effScores` selection the experiment competitions use, so the persisted score cannot be one
the competition did not rank on. `FdrTest.TestStreamingFirstPassQMatchesFlat` pins them against
each other AND against the definition; the mean-best-N test pins the aggregation branch.

**Not a general q-to-score inverse**, and the doc comments say so: the best-of-runs clamp
(`ClampExperimentQToBestRunFlat`, #4390) floors an experiment q up to a RUN q, so after clamping
the experiment q is not a monotone function of this score. It is the score its competition ranked
on, which is what a score-space acceptance boundary needs.

**Verified end to end**: the Python oracle reads the field and reports
`persisted experiment_aggregate_score matches computed max() for all 986,663 precursors`.
Regression mode 1 (results vs golden) PASSES, so v4 moved no search result.

Also fixed while here: `FdrScoresSidecar.ReadScalars` did not validate magic or version. Harmless
at a fixed record width; at a CHANGED width a stale v3 sidecar would be re-cut at 68 bytes and
yield plausible garbage. It now rejects.

## Rust side: done, and this machine can now build it

Ported identically (`FdrEntry.experiment_aggregate_score`, producer in
`compute_experiment_level_qvalues`, sidecar writer + loader, all 16 struct literals). Rust has no
mean-best-N mode, so the aggregate there is the max - the same value the default C# path writes.

**This machine had no Rust toolchain at all**, which is why the port could not be verified when
first written. Now installed and green: rustup 1.29 / rustc 1.97.1 (msvc), clippy, rustfmt,
rust-analyzer; `cargo check --all-targets`, `cargo fmt --check`, `cargo clippy -D warnings`,
`cargo test --workspace` (578 passed, 0 failed), and the project wrapper
`Build-OspreyRust.ps1 -Fmt -Clippy`.

Three things that cost time and are now written down so they cost nobody else any:

* **The real blocker is not rustup, it is vcpkg.** `maccoss/osprey` links native OpenBLAS via
  `openblas-src`; without it `cargo check` dies in a build script with `VcpkgNotFound`. The only
  place this was recorded was `osprey/.github/workflows/ci.yml` - the GitHub runners ship vcpkg
  preinstalled, so CI only ever runs the `vcpkg install` line and nothing else wrote it down.
  Now documented in `ai/docs/new-machine-setup.md` (Phase 7) and cross-referenced from
  `ai/docs/osprey-development-guide.md` with a symptom -> missing-piece table.
* **`Build-OspreyRust.ps1` hardcoded `VCPKG_ROOT = "$env:USERPROFILE\vcpkg"`**, unconditionally
  overwriting a correct value set by the caller - and wrong on CI too, which uses
  `VCPKG_INSTALLATION_ROOT`. Fixed to respect an existing value, then `VCPKG_INSTALLATION_ROOT`,
  then `C:\vcpkg`, then the old default.
* vcpkg installed at `C:\vcpkg`, deliberately NOT under `C:\proj` - `get_project_status` scans
  the project root for git repos and would report it as one.

**Still not run**: the `OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT` byte-parity harness against the C#.
Now possible on this machine, and see the #4553 section - that harness is being extended by
another branch right now.

## FOR THE #4553 SESSION (fdr_sidecar_parity) - please read, two asks

Written 2026-08-10 after pulling `pwiz-ai` and reading
`TODO-20260809_fdr_sidecar_parity.md`. Our branches collide in three places and one of them is a
defect I introduced that your fix is the right home for.

**Your diagnosis explains my pass-2 numbers exactly.** My panel reports 36,228 decoys at pass 2
against ~23-25k targets. Your measurement on the same dataset - 100,733 of 260,419 records
(39%) zero-score in the straight-through 2nd-pass sidecar, decoys 67,526 at 52% vs targets 25% -
is the mechanism. My pass-2 acceptance boundary is the minimum score over accepted
target/entrapment precursors; with zeros in that pool it collapses to ~0 and admits nearly every
decoy. So my pass-2 decoy row is a SYMPTOM of #4553, not a separate bug, and I am deliberately
not touching it until your fix lands. My pass-1 numbers are unaffected (pass-1 sidecars are
written at the Stage 5 boundary, before Stage 6 - your own table uses them as the reference).

**Ask 1: `ExperimentAggregateScore` needs to join your seeding fix.** I added the field to
`FdrEntry.ResetScores()` (it clears to 0.0 alongside `Score`), and I added a carry for it in
`AssignPerRunQ` - which your TODO correctly identifies as the mode that already does the right
thing. I did NOT add one to `ComputePass2TransferCompeteFull`. So on the DEFAULT pass-2 mode my
field is dropped by exactly your five-of-eight write-back defect, and becomes the FOURTH field
your fix has to seed from the 1st-pass sidecar, after `Score`, `Pep` and `RunProteinQvalue`.
Both C# and Rust. Given your list already grew from two fields to three when you re-ran the gate,
it may be worth driving the seeding off the record layout rather than an enumerated list.

**Ask 2: your sidecar decoder needs the v4 layout.** `Regression/FdrSidecars.ps1` decodes the
60-byte, seven-scalar record ("Duplicating the 60-byte record layout here is how the two copies
drift"), and `Compare-FdrSidecars-Crossimpl.ps1` dot-sources it. As of this branch the record is
**68 bytes with eight scalars** (`experiment_aggregate_score` at `[60..68]`, version byte 4).
Both need the bump plus a comparison arm for the new field. Note your script degrades gracefully
on a MISSING helper (exit 3 -> SKIP) but has no guard for a format mismatch - a v4 file against a
v3 decoder is a silent misparse, which is the same trap I closed in `ReadScalars`.

**Ordering agreed with Brendan: #4553 lands first, this branch rebases onto it, then ONE golden
rebaseline.** Your rebaseline is already approved and your `-Dataset All` is running; mine is not
started. My pass-1 numbers do not move under your fix, but my pass-2 numbers will move a lot, so
blessing them before your fix would bake in numbers produced by the zeroed-score pool. Brendan is
arranging for your branch to be pushed so I can rebase on it.

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
- [x] Persist the experiment aggregate score in the sidecar (v3 -> v4), C# AND Rust - see the
      sidecar v4 section above
- [x] Fix the decoy class: pass 1 now reproduces the Python oracle on all twelve numbers
- [x] Collapse the two pass-1 panel implementations into one (rehydrate path now uses
      `PeakCoAssignmentSource`); verified identical on both paths in a single run
- [x] Install and verify the Rust toolchain on this machine; document the vcpkg/OpenBLAS
      prerequisite that no doc covered
- [ ] **BLOCKED on #4553**: pass-2 decoy row (36,228) - a symptom of the zeroed-score defect,
      not a separate bug. Re-measure after rebasing onto that branch.
- [ ] The symmetric derived-from vs unrelated split for decoys AND entrapment (agreed with
      Brendan) - without it the 6.39x / 3.23x enrichments are not comparable to the target rate
- [ ] Report the pass1 -> pass2 delta in the panel (how much co-assignment reconciliation adds)
- [ ] Rebase onto #4553 once it is pushed, then re-run and re-measure pass 2
- [ ] Regenerate the diagnostics golden - AFTER the rebase, once, jointly with #4553's
      rebaseline (co-assignment metrics are new, and pass-1 decoy numbers move 72 -> 468 /
      96 -> 675)
- [ ] `regression.ps1 -Dataset Stellar`, then `-Dataset All`; capture the real memory/wall numbers
      with `--memstamp` and replace the estimates below
- [ ] Run the `OSPREY_CROSS_IMPL_FDR_SIDECAR_OUT` byte-parity harness (now possible on this
      machine) - coordinate with #4553, which is extending exactly that comparison

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

### 2026-08-10 - Session end, handed off

Panel complete except the decoy class. Targets and entrapment correct and cross-checked; decoy
count wrong in the C# (96 / 36,228 against an oracle of 675 / 468). Offline estimator committed as
`ai/scripts/Osprey/Entrapment/coassign_decoy_estimate.py` - the C# is right when it reproduces it.
Branch `Skyline/work/20260808_peak_coassignment_diagnostics`, 3 commits, clean, 576 tests / 0
warnings. Goldens deliberately not regenerated. NOT PR-ready.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260808_peak_coassignment_diagnostics.md` before starting work.

### 2026-08-10 - Pass 1 correct, sidecar v4 landed both sides, Rust toolchain installed

Pass 1 now reproduces the Python oracle on all twelve numbers. Getting there took four defects,
only two of which were in the panel - the other two were the regression harness overwriting the
report being measured (mode 5 rehydrate writes into the straight run's directory) and the oracle
itself computing decoy m/z ~510 Da wrong from the `DECOY_` prefix. That second one overturns this
file's earlier headline finding: decoys co-assign ABOVE entrapment (6.39x / 6.04x), not below.
Both corrected numbers still need the derived-from split before they can be quoted.

Sidecar v4 (`experiment_aggregate_score`) is implemented and green in C# and Rust. Regression
mode 1 passes, so it moved no search result; the oracle confirms the persisted field matches an
independently computed `max()` for all 986,663 precursors, and reading the field instead of
recomputing gives byte-identical output.

The Rust toolchain did not exist on this machine, so the port was written blind earlier in the
session. It is now installed, documented, and fully verified (578 tests, clippy, fmt).

### 2026-08-10 (evening) - Rebased onto #4553, integrated, and handed off to a night session

#4553 opened PR [#4557](https://github.com/ProteoWizard/pwiz/pull/4557) and maccoss/osprey #61.
Both of this branch's repos are now **rebased onto their branches, cleanly, and integrated**:

* `ExperimentAggregateScore` seeded in BOTH `Pass2FdrSidecar.RestorePass1Scalars` (C#) and
  `restore_pass1_scalars` (Rust) - the fourth field of their five-of-eight map-back.
* `Regression/FdrSidecars.ps1` decodes the v4 8-field record; verified non-vacuous (8 field
  names, 86,824 records from a 5,904,064-byte file, which only divides at the 68-byte stride).
* **Pass-2 decoys 36,228 -> 1,049 (run) and 36,133 -> 71 (experiment)**, confirming that row was
  a symptom of #4553's zeroed scores rather than a second bug.
* Full `-Dataset StellarGenDecoyEntrap`: every leg PASS - including `mode1 (vs golden)` against
  their rebaselined golden, and both `mode3` legs - except the two diagnostics-golden legs,
  whose 28 issues are all `metric not in golden` (the additive rebaseline this branch owes).
* C# 578 tests / 0 warnings; Rust fmt + clippy + 579 tests green.

Commits (nothing pushed): pwiz `11b238d706`, `1a76f4ee57`, `aa92ab413f` on top of
`a23e246fd0`; osprey `669480b`, `6e4337d` on top of `6548ea9`.

**Next session handoff**: read `ai/.tmp/handoff-20260808_peak_coassignment_diagnostics.md` -
it carries the night-session goal (stacked PR merge-ready by EU morning), the ordering with
#4557, the Rust PATH/VCPKG_ROOT trap, the regression gotchas, and the three open questions
that must NOT be silently resolved.

### 2026-08-10 - Earlier: pass 1 correct, sidecar v4 landed both sides

**Not committed at the time.** `C:\proj\pwiz` has 17 modified files, `C:\proj\osprey` 6. Held deliberately:
the ordering agreed with Brendan is that #4553 lands first and this branch rebases onto it,
because pass-2 numbers here are a symptom of that branch's zeroed-score defect and the two
branches need ONE joint golden rebaseline rather than two. See the "FOR THE #4553 SESSION"
section above for the two concrete asks (my new field needs adding to their seeding fix; their
sidecar decoder needs the v4 68-byte layout).
